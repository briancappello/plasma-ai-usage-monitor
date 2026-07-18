# Per-Model Weekly Usage Bars

## Goal

Show the Claude subscription's per-model weekly limits (the `weekly_scoped`
entries in the usage API, e.g. "Fable") as individual usage bars in the
Claude Code / OpenCode subscription cards, matching claude.ai's own UI. The
set of models is fluid: 0 to N entries, with model names that vary over time.

## Data source

The `GET /api/organizations/{uuid}/usage` response includes a `limits` array.
Each element:

```json
{
  "kind": "weekly_scoped",
  "group": "weekly",
  "percent": 1,
  "resets_at": "2026-07-21T07:00:00Z",
  "scope": { "model": { "display_name": "Fable", "id": null }, "surface": null },
  "severity": "normal",
  "is_active": false
}
```

Relevant kinds already handled: `session` (primary bar), `weekly_all`
(secondary/weekly bar). `weekly_scoped` entries are currently ignored; this
feature surfaces them.

## Design

### C++ — base class `SubscriptionToolBackend`

Add a percentage-native, variable-length list property (defaults empty, so
tools that never set it render nothing):

- `Q_PROPERTY(QVariantList scopedLimits READ scopedLimits NOTIFY usageUpdated)`
- `QVariantList scopedLimits() const;`
- `void setScopedLimits(const QVariantList &limits);`
- member `QVariantList m_scopedLimits;`

Each list element is a `QVariantMap`:

```
{ "name": QString, "percent": int, "resetsAt": QString }
```

`name` is `scope.model.display_name`; `percent` is the entry's `percent`
(0–100); `resetsAt` is the entry's `resets_at` (kept for a possible future
per-model countdown, not displayed in v1).

### C++ — Claude Code & OpenCode monitors

The usage parser already iterates `limits[]` for `session` / `weekly_all`.
Extend that same loop to collect `weekly_scoped` entries into a local
`QVariantList`, then `setScopedLimits(list)`. An entry with no
`scope.model.display_name` is skipped. Both monitors get the identical change
(they share the claude.ai endpoint).

Ordering: preserve API order.

### QML — `SubscriptionToolCard.qml`

After the existing Weekly (secondary) bar block, add a section:

- Visible when `!collapsed && (monitor?.scopedLimits?.length ?? 0) > 0`.
- A `Repeater { model: monitor?.scopedLimits ?? [] }` producing, per entry, a
  labeled progress bar that mirrors the weekly-bar style:
  - header row: `modelData.name` (left, dimmed) and `modelData.percent + " / 100"` (right, bold)
  - `QQC2.ProgressBar` from 0 to 100, value `modelData.percent`, fill color
    from the existing `usageColor(modelData.percent)` helper
- Percentage-native (limit is implicitly 100), consistent with the rest of
  the card. No per-model reset text in v1 (they share the weekly reset).

## Testing

Extend `claudeSyncParsesPercentageUsage` in
`plugin/tests/test_subscription_tools.cpp`. The mock already returns a
`weekly_scoped` "Fable" entry at 1%:

- assert `claude.scopedLimits().size() == 1`
- assert `[0]["name"] == "Fable"`
- assert `[0]["percent"] == 1`

## Out of scope (YAGNI)

- Per-model reset countdown text (data captured in `resetsAt` for later).
- Config toggle to hide the section (always shown when data present).
- Chips/compact rendering (full bars chosen).
- Surfacing non-model scopes (`scope.surface`); only `scope.model` is used.
