## Why

Every copy of the widget (one per panel, three today) builds its own full backend. Each copy has its own provider pollers, subscription monitors, KWallet access, SQLite connection, notifications and about 20 timers. Each copy also has its own copy of the settings. The result:

- every claude.ai sync runs three times;
- every reading is stored three times (137,225 Claude rows in `subscription_tool_usage`, mostly triplicates);
- alerts can fire once per copy;
- the panels can show different numbers;
- a setting changed on one panel does not change the others.

The data belongs to the desktop session, not to a panel. So it needs one owner, with every panel as a plain view of it.

## What Changes

- Add a single data hub per plasmashell process, written in C++. It owns every provider, subscription monitor, sync timer, the secrets access, the usage database, alert notifications and the pace history. It is created when the first widget loads and is shared by every widget copy and every settings dialog.
- Make widget copies display-only: `main.qml` connects to the hub and shows its state. `FullRepresentation`, `CompactRepresentation` and the cards bind to hub objects instead of objects they create.
- Make settings global: one settings store, owned by the hub. A change applied in any panel's settings dialog takes effect in every panel at once. This covers all settings, display settings included. The stock Plasma settings dialog stays in use.
- Settings pages keep their short-lived helpers for one-off actions: tool detection, storing keys in KWallet, showing the history size. They must never poll, sync, write readings or send alerts.
- When a Firefox profile is selected, browser sync reads only that profile. If the profile has no cookies, sync reports "not logged in" instead of silently reading another profile (today panel 92's `default` selection only works through that fallback).
- One-time migration of existing per-widget settings into the shared store:
  - start from the values the widget copies agree on;
  - reset Codex settings and `googleModel` to their defaults (unused);
  - set browser sync to Firefox, profile `default-release`.
- **BREAKING** (behavior): widget copies can no longer hold different settings. Today's per-panel differences are dropped by the migration.

## Capabilities

### New Capabilities
- `shared-data-hub`: one backend per plasmashell process that every widget copy uses. Covers single polling and syncing, single storage of readings, single delivery of alerts, and the same state in every panel.
- `global-settings`: one settings store for all widget copies. Covers how changes spread between panels, how settings from the old per-widget model are migrated, and the shared defaults chosen in this change.

### Modified Capabilities
None. No specs exist yet in `openspec/specs/`.

## Impact

- **Code**:
  - **New:** `plugin/` hub class and its registration in `plugin/aiusageplugin.cpp`.
  - **Reworked:** `package/contents/ui/main.qml` (1,209 lines; most of its wiring moves to C++).
  - **Changed:** `FullRepresentation.qml`, `CompactRepresentation.qml`, `SubscriptionToolCard.qml`, `ProviderCard.qml`, and the `config*.qml` pages.
- **Data**: existing `usage_history.db` stays as is. Writes drop from N per reading to one. Existing duplicate rows are left for normal retention (90 days) to remove.
- **Settings storage**: a new shared settings file is added. Each widget's settings section in `plasma-org.kde.plasma.desktop-appletsrc` is kept in sync with it, because the Plasma settings dialog reads and writes that section.
- **External calls**: claude.ai and provider APIs are called once per interval instead of once per widget copy.
- **Tests**:
  - **New:** C++ tests for the hub's lifetime and single ownership, and for how settings spread and migrate.
  - **Updated:** QML tests that build monitors directly (`tst_compactchart.qml`).
