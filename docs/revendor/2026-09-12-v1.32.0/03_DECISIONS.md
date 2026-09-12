# 03 — Decisions

This run was non-interactive. The bulk-logging rollout brief (2026-09-12) set the rules in advance
and said to skip filing and pushing, so no GitHub issue was filed for a decline.

| # | Candidate | Decision | Reason |
|---|---|---|---|
| B1 | Slash minor 8 bracket around `CliResetAll` | **adopt** | Reached by the Defaults button, the footer Defaults and `/lh resetall`. Tests first; see `04_EXECUTION_PLAN.md`. |
| B2 | Options minor 16 bracket | **decline (not reached)** | No path calls `O.RestoreDefaults` or `O.RestoreAllDefaults`. The reason is written beside the Slash descriptor (`settings/Slash.lua`) and in `docs/slash-dispatch.md`. |
| B3 | A `[Set]` line for `Sl:ResetEverything` | **not needed** | It writes no row through `Schema:Set`. Its `[Data]` line stays, and a case pins that no `[Set]` line appears. |
| B4 | Degradation stub no-ops | **none needed** | No instance member added; the parity suite passes. |

**A correction from the coordinator, applied before the adoption commit** (it follows the v1.32.0
review and is now in the rollout brief):

- N is the rows the act **actually wrote**. `bulkEnd`'s `count` counts every row whose `applyDefault`
  returned, including rows already at their default, so it is not logged. The muted seam tallies
  instead, counting a bracketed write only when the stored value changes.
- Nested brackets log once: one depth counter, one tally across levels, the line only when the depth
  returns to 0, and none if any level reported `info.profileReset`.
- An all-default press logs `[Set] reset all: 0 rows`. The choice was to keep the line rather than
  suppress it, because the act happened.
- The seam supplies both hooks.
