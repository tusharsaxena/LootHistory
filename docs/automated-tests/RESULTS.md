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

579 cases, up 16 on the previous run: three pin `Database:QueryList`'s filter contract and thirteen pin the Browser's collapsed multi-select label and menu-row highlight precedence. All sixteen were written as characterization tests — run green against the old shape first — because they are what made splitting nine over-cap functions a safe change, the same role `test_stats.lua` played for `Database:Stats`. The generated inventory `test-cases.md` in each bundle is the authority on what exists at that point; the README badge tracks the same number.

## Lint

Clean over 23 files: 0 warnings, 0 errors. `luacheck .` runs over the addon's own source and its `tests/`; the vendored `libs/` and `tests/_kit/` are out of scope by config, since neither is this repo's to fix.

## Perf

This addon ships no `tests/perf.lua`, so the `perf` column is a permanent `skip` rather than a transient tooling gap. Two things follow, and both are standing facts rather than this run's news: the record says **nothing** about the addon's runtime cost, and `performance-§9`'s zero-overhead evidence — that bracketed instrumentation is free when capture is off — does not exist for it. Adding scenarios is the only thing that changes either.

## Complexity watch list

Current state as of [`20260804-220017`](20260804-220017/) — not that run's diff.
Every function `lizard` warned on, and every file at or above `layout-§1`'s 1000-LOC
on-notice threshold, each with a one-line disposition.

### Functions `lizard` warned on

**None.** No function in this addon exceeds CCN 15.

That is a result, not an empty section. The previous run listed nine, from `Database:QueryList` at
58 down to `make` at 16, each with an "accepted" disposition; all nine were split into named helpers
or a module-level dispatch table, and none of those dispositions carries forward because none of the
functions they covered warns any more. The true maximum is now **15** — six functions sit exactly on
the cap and none is over it (`lizard`'s own `Max CCN` field reads `0` here because it maximizes over
warned functions, of which there are none).

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Browser.lua` | 1372 | **Already tracked as `LH-31`.** The window shell, filter bar and dropdown widget kit; if it needs peeling the seam is the widget kit into a sibling file. Up 58 lines as the extracted menu-row and view-descriptor helpers landed beside their callers. |
| 1000–1500 (on notice) | `modules/Analytics.lua` | 1180 | **Peel next — now unblocked.** It was gated on the `Database:Stats` work, which has landed. Split renderers from the formatting/segmenting helpers. |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1097 | **Accepted.** Just over the line, and already three clean layers. Up 57 lines for the `GROUP_OF` dispatch table and the synthetic-record helpers. Watch it; do nothing yet. |
