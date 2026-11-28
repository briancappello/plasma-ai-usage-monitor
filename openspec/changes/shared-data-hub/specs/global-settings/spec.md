## Purpose

Gives the AI Usage Monitor one set of settings for the whole desktop session, so that every widget copy behaves and looks the same and a change made on any panel applies everywhere.

## ADDED Requirements

### Requirement: One settings set for all widget copies
The system SHALL keep one value per setting for all widget copies. This covers every setting the widget declares, including display settings such as the compact display mode, the chart tool and the popup size. No widget copy SHALL keep a value that differs from the shared one.

#### Scenario: Display setting is shared
- **WHEN** the compact display mode is changed on one panel
- **THEN** every panel's compact view switches to that mode

#### Scenario: Data setting is shared
- **WHEN** Claude Code is enabled on one panel
- **THEN** Claude Code is enabled in every panel and is synced once by the shared backend

### Requirement: Changes made in any settings dialog apply everywhere
When the user applies a change in the settings dialog of any widget copy, the system SHALL save it to the shared settings and apply it to every widget copy without a plasmashell restart. When two dialogs apply changes to the same setting, the last change applied SHALL win.

#### Scenario: Apply on one panel
- **WHEN** the user changes the warning threshold in panel A's settings dialog and presses Apply
- **THEN** panels B and C use the new threshold, and their settings dialogs show it the next time they open

#### Scenario: Two dialogs open
- **WHEN** dialogs from panels A and B are both open and both change the browser sync interval, B applying last
- **THEN** every widget copy uses B's value

### Requirement: New widget copies start with the shared settings
A widget copy added after the shared settings exist SHALL start with the shared values, not the declared defaults.

#### Scenario: Adding a widget to a new panel
- **WHEN** the user adds the widget to a fourth panel
- **THEN** it shows the same tools, thresholds and display mode as the other panels, with no manual configuration

### Requirement: Shared settings persist across sessions
The shared settings SHALL be stored outside any single widget copy's configuration, so they survive plasmashell restarts and the removal of any widget copy.

#### Scenario: Removing the widget that was configured
- **WHEN** the widget copy whose dialog was last used to change settings is removed, and plasmashell is restarted
- **THEN** the remaining widget copies still use those settings

### Requirement: One-time migration from per-widget settings
On the first start with shared settings, the system SHALL build the shared settings from the existing per-widget settings once, using these rules:
- a setting all existing copies agree on keeps that value;
- Codex settings and `googleModel` are reset to their declared defaults;
- browser sync is set to enabled, browser Firefox, profile `default-release`;
- any other conflicting setting takes the value from the copy with the most explicitly set settings.

The system SHALL log every setting it resolved from a conflict. Later starts SHALL NOT repeat the migration.

#### Scenario: Migrating the current three widgets
- **WHEN** shared settings are created from widgets 88, 87 and 92
- **THEN** `codexPlan`, `codexCustomLimit` and `googleModel` have their default values
- **AND** browser sync is enabled with browser Firefox and profile `default-release`
- **AND** each conflicting setting is written to the log with the value chosen

#### Scenario: Migration does not run twice
- **WHEN** plasmashell restarts after the migration
- **THEN** the shared settings are loaded as stored, and per-widget values are not merged again

### Requirement: Claude syncs from the Firefox default-release profile
With the shared defaults of this change, browser sync SHALL read claude.ai cookies from the Firefox profile `default-release`. If that profile has no cookie store, the system SHALL report the sync as not logged in rather than silently using another profile.

#### Scenario: Sync after migration
- **WHEN** a Claude sync runs after the migration
- **THEN** cookies are read from the `default-release` Firefox profile

#### Scenario: Selected profile missing
- **WHEN** the selected Firefox profile has no `cookies.sqlite`
- **THEN** the Claude card shows a "not logged in" status naming the profile, and no other profile is read
