## 1. Shared settings core (stage 1)

- [ ] 1.1 Add `KF6Config` (ConfigGui) and `KF6ConfigQml` to `find_package` and link them in `plugin/CMakeLists.txt`; verify `just build` succeeds
- [ ] 1.2 Compile `package/contents/config/main.xml` into the plugin as a Qt resource, and add a build-time check that the embedded and packaged copies are identical; verify the build fails when they differ and passes when they match
- [ ] 1.3 Add process-wide `SharedSettings` (KSharedConfig `plasma_ai_usage_monitorrc` + `KConfigLoader` from the embedded schema), exposing a `KConfigPropertyMap`; verify with a new `test_sharedsettings` that defaults match `main.xml` and a written value survives a reload
- [ ] 1.4 Implement the one-time migration from `plasma-org.kde.plasma.desktop-appletsrc`, following design Decision 5; verify with `test_sharedsettings` fixtures that:
  - values all copies agree on are kept;
  - Codex keys and `googleModel` are reset to their defaults;
  - browser sync is Firefox + `default-release`;
  - other conflicts take the most-configured copy's value and are logged;
  - a second start does not migrate again
- [ ] 1.5 Add the `SettingsMirror` QML type (design Decision 4): push shared values on attach, forward `valueChanged` to `SharedSettings`, broadcast to other mirrors with `insert` + `writeConfig()`, compare values before writing; verify in `test_sharedsettings`, using three `KConfigPropertyMap`s on separate skeletons, that:
  - a write to one reaches the other two;
  - pushes do not echo back;
  - when two writes hit the same key, the last one wins
- [ ] 1.6 Expose the shared map to QML (per-engine wrapper over `SharedSettings`) and create a `SettingsMirror { configuration: Plasmoid.configuration }` in `main.qml`; verify `just test` passes
- [ ] 1.7 Live check stage 1 after `just dev`:
  - the shared file exists and its migration log matches the `global-settings` spec scenario;
  - changing the warning threshold on one panel updates the other two panels' dialogs;
  - commit stage 1

## 2. Hub singleton (stage 2)

- [ ] 2.1 Add the `HubGuard` C++ type (first live instance is `primary`, handover when it is destroyed, log line with the number of guards seen); verify with `test_hubguard` covering first-wins, a second instance being passive, and handover
- [ ] 2.2 Create `package/contents/ui/Hub.qml` (`pragma Singleton`), register it in the package's `qmldir`, and add `KI18nContext` for translations; verify a QML test can import it and call `l10n.i18n` (design Decision 7)
- [ ] 2.3 Move provider objects, refresh timers, `loadApiKeys`, `refreshAll`, the projection maths and provider snapshot recording from `main.qml` into `Hub.qml`, reading `Hub.settings` and gated on `guard.primary`; verify `just test` passes and the widget shows provider cards after `just dev`
- [ ] 2.4 Move the subscription monitors, `BrowserCookieExtractor`, the browser sync timer, `performBrowserSync` and tool snapshot recording into `Hub.qml`; verify with `just dev` that one `subscription_tool_usage` row is written per Claude sync with three panels placed (sqlite count over 10 minutes)
- [ ] 2.5 Move `NotificationGate`, the 5 `Notification` objects and all `handle*` alert functions into `Hub.qml`; verify `tst_notificationgate.qml` passes and a forced quota warning shows exactly one notification with three panels
- [ ] 2.6 Reduce `main.qml` to a `PlasmoidItem` whose `root.*` properties forward to `Hub` (design Decision 6), and switch the views' `plasmoid.configuration` reads to `Hub.settings`; verify `tst_compactchart.qml` and `tst_configgeneral.qml` pass, and `grep plasmoid.configuration` finds no matches outside `config*.qml` and the mirror
- [ ] 2.7 Add a test asserting that no `config*.qml` imports or references `Hub`; verify it fails when such a reference is added temporarily
- [ ] 2.8 Live check stage 2 with three panels after `just dev`:
  - one claude.ai request per sync interval (from the log);
  - one row per sync;
  - identical percentage and run-out time on all panels;
  - removing one panel's widget keeps the others live, with pace history kept;
  - commit stage 2

## 3. Strict Firefox profile and clean-up (stage 3)

- [ ] 3.1 Make `BrowserCookieExtractor::firefoxProfilePath()` read only the selected profile when one is set, and report "not logged in" with the profile name when it has no `cookies.sqlite`; keep automatic detection when none is set; verify with new `test_browsercookieextractor` cases for a selected-but-empty profile and for no selection
- [ ] 3.2 Delete the backend code left over in `main.qml` and any dead `root.*` forwards; verify `just test` passes and `main.qml` contains no provider, monitor, `Timer` or `Notification` declarations
- [ ] 3.3 Update `README.md` and `CHANGELOG.md`: shared settings across panels, the settings file location and the migration; verify the docs name `~/.config/plasma_ai_usage_monitorrc`
- [ ] 3.4 Final live check after `just dev`: Claude syncs from the `default-release` profile, every requirement scenario in both specs is observed or covered by a test; commit stage 3
