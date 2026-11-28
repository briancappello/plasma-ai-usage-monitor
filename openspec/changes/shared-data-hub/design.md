## Context

See `proposal.md` for motivation, and `specs/shared-data-hub/spec.md` and `specs/global-settings/spec.md` for the requirements.

Current state:
- `package/contents/ui/main.qml` (1,209 lines) is the whole backend for each widget copy. It holds:
  - 13 provider objects and 6 subscription monitors;
  - `SecretsManager` (KWallet), `UsageDatabase`, `BrowserCookieExtractor` and `NotificationGate`;
  - 5 `Notification` objects and about 20 timers;
  - about 30 JavaScript functions: refresh, key loading, notification rules, snapshots, browser sync.
- The views reach this through `root.*` (for example `root.allSubscriptionTools`, `root.allProviders`, `root.usageDb`, `root.performBrowserSync`). Settings are read through `plasmoid.configuration`: 193 uses in `main.qml`, 23 in `FullRepresentation.qml` and 7 in `CompactRepresentation.qml`.
- The settings schema is `package/contents/config/main.xml`: 144 entries in 6 groups. Plasma keeps one copy per widget copy in `~/.config/plasma-org.kde.plasma.desktop-appletsrc`.

Plasma 6.8 constraints, verified in libplasma and the installed shell package:
1. **All widgets share one QML engine.** Every widget copy is created on `PlasmaQuick::globalEngine()`, one `QQmlEngine` shared through a `std::weak_ptr` (`appletquickitem.cpp`). Each widget gets its own `AppletContext`, whose context object is a `KLocalizedQmlContext` set to the widget's translation domain.
2. **Settings dialogs use their own engine.** `ConfigView` creates a separate `QQmlEngine` for each dialog (`configview.cpp`).
3. **How the dialog loads and saves settings.** `AppletConfiguration.qml` fills each page's `cfg_*` properties from `Plasmoid.configuration` when the page opens. On Apply it copies them back with `config[key] = …`, then calls `writeConfig()`.
4. **How `KConfigPropertyMap` behaves.**
   - Every write from QML emits `valueChanged(key, value)`, which writes the value into the backing settings object.
   - `writeConfig()` copies every current value into that object and saves it to disk.
   - A plain C++ `insert()` updates bindings but does not emit `valueChanged`.
5. **Sharing a singleton across engines.** Qt discourages handing one singleton object to several engines. The Qt documentation's own example asserts single-engine use, and Qt maintainers call the old `qmlRegisterSingletonInstance` way of doing it "somewhat problematic".

## Goals / Non-Goals

**Goals:**
- One polling, syncing, storing and alerting backend per plasmashell process, with no dependence on how many widget copies there are or the order they load.
- One settings set, still edited through the stock Plasma settings dialog, so the 6 existing `config*.qml` pages keep working with little change.
- A move that can be shipped in stages, each stage verifiable on its own.
- If Plasma ever stops sharing one engine between widgets, fall back safely: no duplicate work. Showing stale data in extra copies is acceptable; double polling is not.

**Non-Goals:**
- A separate background service (daemon or KDE background module) with a D-Bus interface, or a System Settings page.
- Porting the backend's JavaScript logic to C++. It moves almost as-is (see Decision 1).
- Removing the per-widget settings copies from `appletsrc`. They stay, kept in sync.
- Removing the existing duplicate rows in `usage_history.db`. Normal retention drops them within 90 days.
- Changing how providers or monitors fetch or parse data.

## Decisions

### 1. The hub is a QML singleton (`Hub.qml`) on the shared widget engine

Move the backend part of `main.qml` almost as-is into `package/contents/ui/Hub.qml`: the provider and monitor objects, the timers, the notifications, the gate and the JavaScript functions. Mark it `pragma Singleton`. A QML singleton exists once per engine, and every widget copy runs on Plasma's shared engine (Context 1), so there is one hub per plasmashell.

`main.qml` shrinks to a `PlasmoidItem` that forwards to the hub.

Alternatives considered:
- **Port the backend logic to a C++ hub object.** This is cleaner in the long run, but means rewriting about 30 working, tested JavaScript functions and their notification rules in one go. It is high risk for no change the user can see. It stays possible later, because the hub's interface does not depend on its language.
- **A process-wide C++ object handed to every engine as a singleton.** Qt discourages this (Context 5). The dialog engines would also get the live backend, which they do not need.
- **"First widget copy wins": copies elect a leader and the others stay idle.** This removes the duplicate polling, but the panels still show separate states, the pace history dies with the leader, and settings stay split. It does not meet the spec.

### 2. A C++ guard makes "one active hub" hold even if engines multiply

`Hub.qml` creates a small C++ `HubGuard` object. The first guard created in the process is `primary`, and any later guard is not. Every timer, sync and database write in `Hub.qml` is gated on `guard.primary`. When the primary guard is destroyed, the next live guard takes over.

Today exactly one `Hub.qml` exists, so this costs nothing. It protects the "poll once" and "store once" requirements if a future Plasma version gives each widget its own engine, or if a settings page imports `Hub` by mistake. The cost is a short handover gap, not duplicates.

### 3. Shared settings live in C++, in their own file, using the same schema

Add `SharedSettings`, a process-wide C++ core:
- It uses `KSharedConfig::openConfig("plasma_ai_usage_monitorrc")` together with a `KConfigLoader`.
- The loader is built from `main.xml`, compiled into the plugin as a Qt resource, so the schema and defaults have one source.
- It exposes a `KConfigPropertyMap` (`Hub.settings`) that the hub and the views read in place of `plasmoid.configuration`.

`KSharedConfig` already gives one config object per file per process, and the core keeps one loader on top of it. A thin QML-facing wrapper can then exist in each engine without splitting the data.

Alternative considered: keep each widget's `appletsrc` copy as the source of truth and copy between widgets. There would be no master copy to restore from or to seed new widgets with, and "which widget wins" would depend on load order.

### 4. Each widget's own settings mirror the shared settings

The stock dialog only reads and writes `Plasmoid.configuration` (Context 3). So each widget's `main.qml` creates a C++ `SettingsMirror { configuration: Plasmoid.configuration }`:
- **When attached:** copy every shared value into the widget's map (`insert`, then `writeConfig()`). The dialog then always opens showing the shared values.
- **When `valueChanged(key, value)` fires on a widget's map** (a dialog Apply, or any other write from QML): if the value differs from the shared one, write it to `SharedSettings` and save. `SharedSettings` then pushes it to every other attached mirror with `insert` + `writeConfig()`.
- **No loops:** `insert` does not emit `valueChanged` (Context 4), so pushes do not echo back. Values are also compared before writing.
- **Two dialogs at once:** if two dialogs apply the same key, the second Apply comes last and wins, as the spec requires.

Alternative considered: write a custom `saveConfig()` in every settings page that writes to the shared settings. Plasma would still copy the `cfg_*` values into `Plasmoid.configuration` afterwards, so the mirror is needed anyway. It would also touch 6 pages and 144 `cfg_` bindings for no gain.

### 5. Migration reads `appletsrc` directly, once

The first time `SharedSettings` starts and the shared file has no `[Migration] version`, it:
1. Reads `plasma-org.kde.plasma.desktop-appletsrc` with `KConfig`, finds every applet whose `plugin` is `com.github.loofi.aiusagemonitor`, and collects the explicitly set keys from its `[Configuration][<Group>]` sections.
2. Applies the rules in the `global-settings` spec:
   - keep values all copies agree on;
   - reset Codex settings and `googleModel` to their defaults;
   - browser sync on, Firefox (`browserSyncBrowser=0`), `browserSyncProfile=default-release`;
   - otherwise use the values from the copy with the most explicit keys;
   - log each conflict it resolves.
3. Writes the shared file with `[Migration] version=1`.

Reading the file instead of waiting for widgets to register makes the result independent of load order and race-free. The mirrors attach afterwards and copy the result into every widget (Decision 4).

### 6. Views keep their `root.*` interface

`main.qml` keeps its current `root.*` properties (`allProviders`, `allSubscriptionTools`, `usageDb`, `connectedCount`, `performBrowserSync`, `refreshAll`, …) as forwards to `Hub`. So `FullRepresentation`, `CompactRepresentation` and the cards change only where they read `plasmoid.configuration` (switched to `Hub.settings`). Existing QML tests, which build a fake `root`, keep working.

### 7. Translations in the hub use `KI18nContext`

A singleton does not get the per-widget `KLocalizedQmlContext`, so `i18n()` is not in scope there (Context 1). `Hub.qml` creates its own `KI18nContext { translationDomain: "plasma_applet_com.github.loofi.aiusagemonitor" }` (from `org.kde.ki18n`, installed) and calls `l10n.i18n(...)`.

### 8. Firefox profile selection becomes strict

`BrowserCookieExtractor::firefoxProfilePath()` currently falls back silently: from the selected profile to `profiles.ini` defaults, then to any profile with cookies. Panel 92's `default` selection only worked through that fallback, which reads a different profile (`default-release`). With a profile selected, the extractor will read only that profile, and report "not logged in" naming the profile when it has no `cookies.sqlite`. With no profile selected, the current automatic detection stays.

## Risks / Trade-offs

- **[Risk] The hub relies on Plasma's shared engine, which libplasma does not document as a promise.** → The `HubGuard` (Decision 2) keeps "poll, sync and store once" true even if engines multiply. A startup log line records the engine count the guard sees, so a regression is visible.
- **[Risk] Singleton lifetime ends when the shared engine is destroyed.** This happens only when the last widget copy goes away, so it matches the spec. Pace history is in memory and is lost on a plasmashell restart, the same as today. → No mitigation needed.
- **[Risk] A settings page imports `Hub` and creates a second instance in the dialog's engine.** → `HubGuard` keeps that copy passive. A test asserts that no `config*.qml` file imports `Hub`.
- **[Risk] Mirror write-backs make `appletsrc` save several times per Apply (one save per widget copy).** → Acceptable: Apply is rare and the file is small. The writes happen only when a value actually changes.
- **[Risk] `main.xml` is compiled into the plugin and also installed with the package, so the two copies can drift.** → Both come from the same source file at build time. A build-time check compares the embedded and packaged copies.
- **[Trade-off] Per-widget copies in `appletsrc` remain, as stale-looking duplicates of the shared file.** This is accepted to keep the stock dialog (Non-Goals).
- **[Trade-off] Strict profile selection (Decision 8) can surface "not logged in" where a silent fallback used to work.** This is intended: the migration sets the correct profile, and a wrong selection should be visible.
- **[Trade-off] The backend stays in JavaScript.** Porting to C++ is left for later if it proves worth it.

## Migration Plan

Each stage ships, and is verified live, on its own:

1. **Shared settings.** Add `SharedSettings`, the migration from `appletsrc` and `SettingsMirror`. Widgets still each poll, but settings are now global. Verify: one Apply changes all three panels; the migration log matches the spec scenario.
2. **Hub.** Move the backend into `Hub.qml` behind `HubGuard`. `main.qml` and the views forward to it. Verify: one `subscription_tool_usage` row per Claude sync, one claude.ai request per interval (from the log), one notification per alert, identical panels.
3. **Strict Firefox profile** (Decision 8), plus clean-up of the leftover per-widget backend code.

**Rollback:** each stage is its own commit. Reverting stage 2 restores per-widget backends; the shared settings from stage 1 stay valid. Reverting stage 1 brings back per-widget settings, which still sit untouched in `appletsrc`. The shared file is ignored, and can be deleted by hand.
