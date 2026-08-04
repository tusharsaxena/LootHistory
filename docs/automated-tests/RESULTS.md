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

Current state as of [`20260804-182216`](20260804-182216/) — not that run's diff. Every function `lizard` warned on and every file in `layout-§1`'s 1000–1500 on-notice band, each with a one-line disposition.

| `Database:QueryList` | 58 | `core/Database.lua` | **Accepted.** A filter-predicate chain, one branch per field, on the browser's per-keystroke path. |
| `NS:RunMigrations` | 56 | `core/Database.lua` | **Accepted, by design.** The CCN *is* the migration count; it can only rise. |
| `Database:RepairBoundStates` | 23 | `core/Database.lua` | **Accepted for now.** The repair "has been wrong more than once"; leave it one readable pass. |

Six further entries in `modules/Browser.lua` / `BrowserTable.lua` accepted with reasons recorded 2026-08-04. `Database:Stats` (was 75, the worst in the repo) is **gone** — peeled into eleven named helpers, max CCN 13.

**Files in the 1000–1500 band:** `modules/Browser.lua` (1314) — already tracked as LH-31; `modules/Analytics.lua` (1180) — **peel next, now unblocked**; `modules/BrowserTable.lua` (1040) — accepted.
