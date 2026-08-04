# Automated test results

<!-- The newest run is prepended by tests/_kit/run-automated-tests.sh. -->
<!-- This file is OVERWRITTEN IN PLACE — the git history of this one path is the trend line. -->

One row per run. The frozen evidence for each is in the dated folder beside this file;
the analysis of a given run is its `ANALYSIS.md`.

**`lint` and `tests` gate. `perf` and `complexity` are recorded and never fail a run** —
they are read and compared, not thresholded. A `skip` is a suite that did not run at all,
which is never the same as a pass.

| Run | Version | Lint w/e | Files | Tests | Perf | NLOC | Funcs | Avg NLOC | Avg CCN | Max CCN | CCN warn | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [`20260804-182216`](20260804-182216/) | 1.2.0 | 0/0 | 23 | 563/563 | skip | 11196 | 1457 | 6.7 | 2.3 | 58 | 9 | **green** |

## Test suite

563 cases, with `test_stats.lua` pinning the `Database:Stats` output struct — which is what made peeling that CCN-75 function from one loop into eleven helpers a safe change. The generated inventory `test-cases.md` in each bundle is the authority on what exists at that point; the README badge tracks the same number.

## Lint

Clean over 23 files: 0 warnings, 0 errors. `luacheck .` runs over the addon's own source and its `tests/`; the vendored `libs/` and `tests/_kit/` are out of scope by config, since neither is this repo's to fix.

## Perf

This addon ships no `tests/perf.lua`, so the `perf` column is a permanent `skip` rather than a transient tooling gap. Two things follow, and both are standing facts rather than this run's news: the record says **nothing** about the addon's runtime cost, and `performance-§9`'s zero-overhead evidence — that bracketed instrumentation is free when capture is off — does not exist for it. Adding scenarios is the only thing that changes either.

## Complexity watch list

Current state as of [`20260804-182216`](20260804-182216/) — not that run's diff.
Every function `lizard` warned on, and every file at or above `layout-§1`'s 1000-LOC
on-notice threshold, each with a one-line disposition.

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|
| `Database:QueryList` | 58 | `core/Database.lua` | **Accepted.** A filter-predicate chain — one branch per filter field, each independent and short, on the path the browser calls on every filter change. |
| `NS:RunMigrations` | 56 | `core/Database.lua` | **Accepted, by design.** A strictly ordered ladder of schema steps; the CCN *is* the migration count and can only rise. Do not read growth here as decay. |
| `Database:RepairBoundStates` | 23 | `core/Database.lua` | **Accepted for now.** The warband/BoE repair; its comment records that it "has been wrong more than once", which argues for one readable pass. |
| `B:CaptureView` | 23 | `modules/Browser.lua` | **Accepted.** One guard per captured field; read and pinned together with its inverse `B:ApplyView`. |
| `menu:Populate` | 20 | `modules/Browser.lua` | **Accepted.** Dropdown row construction, one branch per widget decision, run on menu open. |
| `dd:UpdateMultiLabel` | 19 | `modules/Browser.lua` | **Accepted.** The collapsed-button label rule; every branch is a documented display case, all pinned in `tests/test_browser.lua`. |
| `groupOf` | 19 | `modules/BrowserTable.lua` | **Accepted.** One branch per group-by mode, with the namespaced key that stops collapse state colliding between modes. |
| `B:ApplyView` | 17 | `modules/Browser.lua` | **Accepted.** The restore half of `CaptureView`, plus the deliberate carve-out that player scope is not part of a saved view. |
| `make` | 16 | `modules/BrowserTable.lua` | **Accepted — test mode only.** The fixed-seed synthetic record builder; never runs for a player. |

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Browser.lua` | 1314 | **Already tracked as `LH-31`.** The window shell, filter bar and dropdown widget kit; if it needs peeling the seam is the widget kit into a sibling file. |
| 1000–1500 (on notice) | `modules/Analytics.lua` | 1180 | **Peel next — now unblocked.** It was gated on the `Database:Stats` work, which has landed. Split renderers from the formatting/segmenting helpers. |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1040 | **Accepted.** Just over the line, and already three clean layers. Watch it; do nothing yet. |
