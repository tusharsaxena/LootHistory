# Candidates (LootHistory, LibKa0s v1.70.0 -> v1.71.0)

v1.71.0 adds no payload surface a consumer must take. Every candidate below is **not adopted in this
run**: the 2026-10-07 remediation re-vendors mechanically and defers adoption (owner scope 5). No
interview ran, so there is no `03_DECISIONS.md`, and nothing was declined, so no issue was filed.

| Candidate | Where it would land | Status |
|---|---|---|
| `Kit.secret` / `Kit.isSecret` / `Kit.reveal` / `Kit.installSecretValue` (kit 38, opt-in) | the secret-safety cases (`tests/test_libka0s.lua`, `test_util.lua`, `test_debuglog.lua`, `test_slash.lua`, `test_diagnostics.lua`), which today build their own stand-ins | not adopted in this run |
| `ChartMath.ClipSegment` (WidgetsLineChart 3) | none: the chart clips internally, the Timeline needs no direct call | not adopted in this run |
| Dropping `self.chart:ClearHover()` at `modules/Timeline.lua:308` now that a render re-syncs the hover | `modules/Timeline.lua` | not adopted in this run; keeping it is allowed per v1.71.0's "What a consumer owes" |
