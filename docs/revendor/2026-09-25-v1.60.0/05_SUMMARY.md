# 05 — Summary

**LibKa0s v1.58.0 -> v1.60.0**, spanning v1.59.0, from the local tag `v1.60.0` (commit `bed0eb1`).
Plan item DR-LH-01 of the 2026-09-25 diagnostics rollout.

## Minors that moved

| File | v1.58.0 | v1.60.0 |
|---|---|---|
| `WidgetsDragHandle.lua` | 2 | 3 |
| `DebugLog.lua` | 13 | 14 |
| `DebugLogDiagnostics.lua` | absent | 1 (new, 22nd file) |
| `Slash.lua` | 15 | 16 |
| test kit (`Kit.VERSION`) | 26 | 27 |

Every other file is unchanged. Nothing was removed upstream, so the copy deleted nothing.

## Delivered for free (class A)

- The console keeps 3000 lines instead of 1500 (the slack moves from 64 to 128).
- `lib.TIME_COPY`, the maintainer's copy-timing switch, off by default.
- `diagnostics` is live while disabled on the library's own gate.

## Contract blockers, fixed in the vendor commit

1. **DebugLog stub parity**: `core/DebugLogSetup.lua`'s library-absent stub gains `RunDiagnostics`
   (prints `/lh diagnostics is unavailable: the LibKa0s library did not load.`, writes nothing,
   returns 0), `BuildDiagnostics` (an empty report) and `DebugVerb` (`false`).
   `tests/test_debuglog.lua` gains one case that pins that behavior.
2. **The live set**: `settings/Schema.lua`'s `LIVE_WHILE_DISABLED` gains `diagnostics`, and so do the
   two test copies (`tests/test_disabled.lua`, `tests/test_slash.lua`), in `lib.LIVE_VERBS` order.
   The counting comments beside them go from twelve to thirteen, and so does the `settings/Slash.lua`
   comment on the library default.
3. **The kit's new suite**: `tests/run.lua` declares `test_diagnostics_contract` (one declared skip
   until `Kit.diagnostics` is wired in DR-LH-03). `tests/test_libka0s.lua`'s explicit lib load list
   gains `DebugLogDiagnostics.lua` after `DebugLog.lua` (it pins the count against `LibKa0s.xml`).

## Adopted, declined, unreached

- Adopted in this run: nothing. The report (B1) and the verb (B2) are adopted later, in DR-LH-03.
- Declined: nothing. The plan files no decline issues.
- Not a candidate: the DragHandle close mark (no `DragHandle` in this addon).

## Gates, after the copy (all through `ka0s-bounded`)

- `luacheck .`: 0 warnings / 0 errors in 68 files (`libs/` and `tests/_kit/` excluded by
  `.luacheckrc`; the host files that carry the seams are all inside the checked set).
- `lua tests/run.lua`: 933 passed, 0 failed, 1 skipped (the kit's diagnostics contract, by design),
  934 total. `test_vendor_sync` passes against v1.60.0.
- `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .`: no function above CCN 15.
- Largest authored file: `modules/Browser.lua`, 1289 lines, under the 1500-line cap.

Docs rolled in the same commit: the `CLAUDE.md` provenance line, `docs/test-cases.md` (regenerated),
the README test badge (933/934), and `docs/testing.md` (thirty-seven suites, four from the kit, the
contract row and the stub case). The smoke-test lines that quote `N / 1500 lines` belong to DR-LH-05.
