# Refresh (LootHistory): the local v1.75.0 tag moved

The local annotated tag v1.75.0 moved from `265a89e` to `6bf5f3e` after this bundle's re-vendor
(LH-RV). The move carries LK-26: `LibKa0s-Sim-1.0` minor 2 (Start reads the scenarios live, and a
host's own start fields reach its `prepare`; `startOpts` answers a copy of the live session's
resolved start opts) and SimTimeline minor 2 (it reads those start opts back). SimPanel stays at
minor 1; no other library file and no kit file changed, so the kit revision stays 41. The record
of the move is the run bundle's `99_EXECUTION_RECORD.md` ("The local tag v1.75.0").

This file is added rather than editing 01..05, which stay frozen as the record of `265a89e`.

**How.** The same copy as LH-RV: `git -C ../LibKa0s archive v1.75.0 LibKa0s testkit`, both
payloads replaced whole, then the tag's `tools/prune-icons.lua` against the unchanged `LibKa0s
icons:` line (16 icons declared; kept 17 files, removed 5,823). The provenance line stays
v1.75.0.

**Files that changed:**

| File | Change |
|---|---|
| `libs/LibKa0s/Sim.lua` | minor 1 -> 2 |
| `libs/LibKa0s/SimTimeline.lua` | `TIMELINE_MINOR` 1 -> 2 |
| `tests/test_libka0s.lua` | the v1.75.0 pin expects Sim 2 and SimTimeline 2; the load-order comment says so |

`tests/_kit/` is byte-identical to the previous copy.

**Gates.** `lua tests/run.lua` (bounded): 1580 passed, 0 failed, 1 skipped, with
`test_vendor_sync` green against `6bf5f3e`. `luacheck .`: 0 warnings / 0 errors in 123 files. No
authored `.lua` file is above 1500 lines (largest `tests/test_browser.lua`, 1459). The case count
did not change, so `docs/test-cases.md` and the README badge stand.
