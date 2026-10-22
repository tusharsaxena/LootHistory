# Refresh 2 (LootHistory): the local v1.75.0 tag moved again

The local annotated tag v1.75.0 moved from `6bf5f3e` to `9e5c4e2` after this bundle's first
refresh (LH-RV2, recorded in `06_REFRESH.md`). The move carries LK-27: SimPanel minor 2 (the
picker reads its scenario at use, so a host that fills `d.scenarios` after `New` gets a real
choice rather than `Start: nil`; LibKa0s#54). Sim stays at minor 2 and SimTimeline at minor 2; no other library file and no kit file
changed, so the kit revision stays 41. The record of the move is the run bundle's
`99_EXECUTION_RECORD.md` ("The local tag v1.75.0").

This file is added rather than editing 01..06, which stay frozen as the record of the earlier
copies.

**How.** The same copy as LH-RV and LH-RV2: `git -C ../LibKa0s archive v1.75.0 LibKa0s testkit`,
both payloads replaced whole, then the tag's `tools/prune-icons.lua` against the unchanged
`LibKa0s icons:` line (16 icons declared; kept 17 files, removed 5,823). The provenance line stays
v1.75.0.

**Files that changed:**

| File | Change |
|---|---|
| `libs/LibKa0s/SimPanel.lua` | `SIM_PANEL_MINOR` 1 -> 2 |
| `tests/test_libka0s.lua` | the v1.75.0 pin expects SimPanel 2; the load-order comment says so |

`tests/_kit/` is byte-identical to the previous copy.

**Gates.** `lua tests/run.lua` (bounded): 1580 passed, 0 failed, 1 skipped, with
`test_vendor_sync` green against `9e5c4e2`. `luacheck .`: 0 warnings / 0 errors in 123 files. No
authored `.lua` file is above 1500 lines (largest `tests/test_browser.lua`, 1459). The case count
did not change, so `docs/test-cases.md` and the README badge stand.
