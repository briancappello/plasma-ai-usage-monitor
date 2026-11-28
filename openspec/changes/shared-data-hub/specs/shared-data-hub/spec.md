## Purpose

Gives every copy of the AI Usage Monitor widget in a desktop session one shared source of usage data. Each external service is polled once, each reading is stored once, each alert is sent once, and every panel shows the same numbers.

## ADDED Requirements

### Requirement: One backend per desktop session
The system SHALL keep exactly one set of polling and syncing backends (providers, subscription monitors, usage history writer, alerts) per plasmashell process, however many widget copies are placed. Every widget copy SHALL show data from that set. Settings dialogs MAY use short-lived helpers for one-off actions (detecting installed tools, storing API keys, showing the history size), but they SHALL NOT poll services, run syncs, write readings or send alerts.

#### Scenario: Several panels share one backend
- **WHEN** three widget copies are placed on three panels
- **THEN** the session polls and syncs through one instance of each enabled backend, not three

#### Scenario: Settings dialog is open
- **WHEN** a settings dialog is open for any widget copy
- **THEN** no extra provider polls, claude.ai requests, history rows or alerts happen because of it

### Requirement: Backend lifetime is independent of any single widget
The shared backend SHALL be created when the first widget copy loads. It SHALL stay alive while any widget copy exists. Closing a settings dialog or removing one widget copy SHALL NOT stop or reset it.

#### Scenario: Removing one panel's widget
- **WHEN** one of three widget copies is removed
- **THEN** the remaining copies keep showing live data without a resync, and the pace history is kept

#### Scenario: Closing a settings dialog
- **WHEN** a settings dialog opened from any panel is closed
- **THEN** the shared backend and its data remain available to every widget copy

### Requirement: External services are polled once per interval
Each enabled provider API and each enabled subscription sync (such as claude.ai) SHALL be called at most once per configured interval per session, however many widget copies exist.

#### Scenario: Claude sync with three panels
- **WHEN** browser sync runs for Claude with three widget copies placed
- **THEN** claude.ai receives one usage request per sync interval

#### Scenario: Manual sync from a panel
- **WHEN** the user triggers a sync from one panel's card
- **THEN** one sync runs, and every panel shows its result

### Requirement: Readings are stored once
Each usage reading SHALL be written to the usage history once, however many widget copies exist.

#### Scenario: Subscription reading with three panels
- **WHEN** a Claude sync returns a reading with three widget copies placed
- **THEN** `subscription_tool_usage` gains exactly one row for that reading

### Requirement: Alerts are delivered once
Each quota, budget, error or sync alert SHALL be sent once per occurrence per session, however many widget copies exist.

#### Scenario: Quota warning with three panels
- **WHEN** the Claude weekly quota crosses the warning threshold with three widget copies placed
- **THEN** exactly one desktop notification is shown

### Requirement: Every panel shows the same state
All widget copies SHALL show the same usage values, pace, run-out estimates, sync status and errors at any moment, because they read the same backend.

#### Scenario: Two panels after a sync
- **WHEN** a sync updates the Claude weekly percentage
- **THEN** every panel shows the new percentage and the same run-out time

#### Scenario: Panel added later
- **WHEN** a new widget copy is added to a panel while others are running
- **THEN** it shows the current data at once, with no new sync and with the existing pace history
