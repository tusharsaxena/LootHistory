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
| [`20260804-233322`](20260804-233322/) | 1.2.0 | 0/0 | 23 | 579/579 | skip | 11367 | 1518 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260804-220017`](20260804-220017/) | 1.2.0 | 0/0 | 23 | 579/579 | skip | 11361 | 1518 | 6.5 | 2.2 | 0 | 0 | **green** |
| [`20260804-182216`](20260804-182216/) | 1.2.0 | 0/0 | 23 | 563/563 | skip | 11196 | 1457 | 6.7 | 2.3 | 58 | 9 | **green** |

## Test suite

579 cases, and the count has now held across two consecutive runs — the sixteen that arrived with the CCN split ([`20260804-182216`](20260804-182216/) → [`20260804-220017`](20260804-220017/): three pinning `Database:QueryList`'s filter contract, thirteen pinning the Browser's collapsed multi-select label and menu-row highlight precedence) were written as characterization tests, run green against the old shape first, and they are what made splitting nine over-cap functions a safe change — the same role `test_stats.lua` played for `Database:Stats`. That they did not move again through the `compileFilter` extraction is the point rather than a gap: the extraction was covered by cases that already existed. The generated inventory `test-cases.md` in each bundle is the authority on what exists at that point; the README badge tracks the same number.

## Lint

Clean over 23 files: 0 warnings, 0 errors, unchanged across all three recorded runs. `luacheck .` runs over the addon's own source and its `tests/`; the vendored `libs/` and `tests/_kit/` are out of scope by config, since neither is this repo's to fix. That is the whole exclusion — no `exclude_files` glob quietly takes any of `core/`, `modules/`, `settings/`, `defaults/` or `locales/` out of the 23.

## Perf

This addon ships no `tests/perf.lua`, so the `perf` column is a permanent `skip` rather than a transient tooling gap. Two things follow, and both are standing facts rather than any one run's news: the record says **nothing** about the addon's runtime cost, and `performance-§9`'s zero-overhead evidence — that bracketed instrumentation is free when capture is off — does not exist for it. That gap is live right now: `Database:QueryList` was rewritten around a compiled filter across the last two runs and every figure recorded here is silent on what it cost. The one measurement taken was out of band against master (5000 records, 150 passes, best of 3) and is not in any bundle. Adding scenarios is the only thing that changes either.

## Complexity watch list

Current state as of [`20260804-233322`](20260804-233322/) — not that run's diff.
Every function `lizard` warned on, and every file at or above `layout-§1`'s 1000-LOC
on-notice threshold, each with a one-line disposition.

**Reading the `Max CCN` column: the `0` in [`20260804-220017`](20260804-220017/) is an instrument fault, not a measurement.** Runs recorded before the testkit rev-6 re-vendor read `CCN_MAX` out of `lizard`'s `!!!! Warnings` block, which maximizes over *warned* functions only — so it reported `0` the moment the addon reached zero warnings. Of the runs in the table, that bites exactly one: `20260804-220017`, whose true maximum was **15**, and it is there in that bundle's own [`complexity.txt`](20260804-220017/complexity.txt) — six functions at CCN 15, none above. The `58` in [`20260804-182216`](20260804-182216/) came off the same faulty reader but is correct by accident, because that run had nine warned functions for it to maximize over. The generated rows are left exactly as the tool wrote them (`performance-§10`: a hand-edited record is worse than a wrong one, because it reads as measured); [`20260804-233322`](20260804-233322/) is the first run with the fixed kit, which is why `58 → 0 → 15` in the column is a reporting change and not a regression.

### Functions `lizard` warned on

**None.** No function in this addon exceeds CCN 15.

That is a result, not an empty section. The `20260804-182216` baseline listed nine, from `Database:QueryList` at 58 down to `make` at 16, each with an "accepted" disposition; all nine were split into named helpers or a module-level dispatch table, and none of those dispositions carries forward because none of the functions they covered warns any more. The true maximum is **15**, and six functions sit exactly on the cap without crossing it — naming all six, from [`20260804-233322/complexity.txt`](20260804-233322/complexity.txt): `E@39-159` (the block `lizard` attributes to `E:WowheadLink`, `modules/Export.lua:39`), `BrowserTable:GroupRecords` (`modules/BrowserTable.lua:550`), `BrowserTable:UpdateHeaderArrows` (`modules/BrowserTable.lua:968`), `BrowserTable:BindRow` (`modules/BrowserTable.lua:866`), `Attribution:OnLootOpened` (`modules/Attribution.lua:173`) and `Compat.ScanBound` (`core/Compat.lua:271`). None is carried as a watch-list entry, because none warns.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Browser.lua` | 1372 | **Already tracked as `LH-31`.** The window shell, filter bar and dropdown widget kit; if it needs peeling the seam is the widget kit into a sibling file. Up 58 lines over the baseline as the extracted menu-row and view-descriptor helpers landed beside their callers; flat since. |
| 1000–1500 (on notice) | `modules/Analytics.lua` | 1180 | **Peel next — now unblocked.** It was gated on the `Database:Stats` work, which has landed. Split renderers from the formatting/segmenting helpers. |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1097 | **Accepted.** Just over the line, and already three clean layers. Up 57 lines over the baseline for the `GROUP_OF` dispatch table and the synthetic-record helpers; flat since. Watch it; do nothing yet. |
| > 1500 (over cap) | — | — | **None.** No file is over the 1500 cap (`"overCapFiles": 0` in every recorded run). |
