# Analysis — 20260804-114855

- **Addon:** LootHistory 1.2.0
- **Verdict:** green
- **Commit:** 6894e65763b3 (master), dirty
- **Previous run:** none — this is the first recorded run

## Headline

The first automated-test record for this addon, produced while adopting `automated-tests`
(standard v2.19.0). Both gating suites are clean: `luacheck` reports 0 warnings / 0 errors across
23 files and the headless harness passes 563 of 563 cases. The offline perf runner is absent (see below). Every figure below is a **baseline** —
there is no previous run to diff against, so nothing here is a regression and nothing is an
improvement.

## Suites

| Suite | Status | Result | Moved since previous run |
|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 23 files (`lint.txt`) | — first run |
| tests | pass | 563 passed, 0 failed, 563 total (`tests.txt`) | — first run |
| perf | skip | skip | — first run |
| complexity | pass | 9 warnings, max CCN 58, 11196 NLOC / 1457 functions (`complexity.txt`) | — first run |

`tests/perf.lua` is absent — this addon ships no offline scenarios, so nothing was measured here. That is a **skip, not a pass**: it is recorded as one in `manifest.json`, and it means this run says nothing about the addon's runtime cost.

## What moved

**First run — nothing to diff against; every figure above is a baseline reading.** The next run is
the first one that can say something moved, and this record is what it will be read against.

## Complexity watch list

| `Database:QueryList` | 58 | `core/Database.lua` | **Accepted.** A filter-predicate chain, one branch per field, on the browser's per-keystroke path. |
| `NS:RunMigrations` | 56 | `core/Database.lua` | **Accepted, by design.** The CCN *is* the migration count; it can only rise. |
| `Database:RepairBoundStates` | 23 | `core/Database.lua` | **Accepted for now.** The repair "has been wrong more than once"; leave it one readable pass. |

Six further entries in `modules/Browser.lua` / `BrowserTable.lua` accepted with reasons recorded at 2026-08-04. `Database:Stats` (was 75, the worst in the repo) is **gone** — peeled this session into eleven named helpers, max CCN 13.

**Files in the 1000–1500 band:** `modules/Browser.lua` (1314) — already tracked as LH-31; `modules/Analytics.lua` (1180) — **peel next, now unblocked** by the `Database:Stats` work; `modules/BrowserTable.lua` (1040) — accepted.

## Actions

None arising from this run. The dispositions above are carried forward from the complexity reports
written against the same measurements earlier today; each was recorded with its evidence at the
time, and none is new here.
