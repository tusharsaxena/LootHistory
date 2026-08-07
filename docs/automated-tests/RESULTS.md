# Automated test results

<!-- The newest run is prepended by tests/_kit/run-automated-tests.sh. -->
<!-- This file is OVERWRITTEN IN PLACE — the git history of this one path is the trend line. -->

One row per run. The frozen evidence for each is in the dated folder beside this file;
the analysis of a given run is its `ANALYSIS.md`.

**`lint` and `tests` gate the run and gate the commit** (`testing-§4`).
**`perf` and `complexity` never fail a run and never block a commit** — they are recorded,
read and compared, not thresholded (`performance-§9`, `performance-§10`).

**The tag is gated on all four suites at `pass`, plus zero functions above CCN 15**
(`automated-tests-§3`, *The release gate*), evaluated by `/wow-addon:bump-version` from the
`manifest.json` the release run writes — not by this script, whose exit code is unchanged.

A `skip` is a suite that did not run at all. It is never a pass, and at the release gate it is
**NOT EVALUATED** rather than passed: install the tool and re-run. A `—` is a suite that was
not selected, which is a different fact again.

| Run | Version | Lint w/e | Files | Tests | Perf | NLOC | Funcs | Avg NLOC | Avg CCN | Max CCN | CCN warn | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [`20260807-114650`](20260807-114650/) | 1.2.0 | 0/0 | 23 | 594/594 | skip | 11479 | 1531 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260807-110451`](20260807-110451/) | 1.2.0 | 0/0 | 23 | 594/594 | skip | 11479 | 1531 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260807-022940`](20260807-022940/) | 1.2.0 | 0/0 | 23 | 594/594 | skip | 11479 | 1531 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260804-233322`](20260804-233322/) | 1.2.0 | 0/0 | 23 | 579/579 | skip | 11367 | 1518 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260804-220017`](20260804-220017/) | 1.2.0 | 0/0 | 23 | 579/579 | skip | 11361 | 1518 | 6.5 | 2.2 | 0 | 0 | **green** |
| [`20260804-182216`](20260804-182216/) | 1.2.0 | 0/0 | 23 | 563/563 | skip | 11196 | 1457 | 6.7 | 2.3 | 58 | 9 | **green** |

## Test suite

**594 cases, 0 skipped**, and the count has now held flat across three consecutive runs
([`20260807-022940`](20260807-022940/), [`20260807-110451`](20260807-110451/),
[`20260807-114650`](20260807-114650/)) — but so has the addon, at exactly 11479 NLOC, so this is a
suite standing still beside source standing still rather than a coverage gap opening up. The figure
to watch is the pair: a count that stays put while NLOC climbs is the gap `automated-tests-§4` wants
flagged, and that is not yet what these rows show. The 594 arrived as +15 over the 579 that held
before it, spread across six suite files rather than concentrated in one — `test_libka0s.lua`
17 → 22, `test_schema.lua` 30 → 32, `test_panel.lua` 24 → 25, `test_auctionprice.lua` 23 → 24,
`test_analytics.lua` 57 → 58, plus a **new suite file**, `test_harness.lua` (5), which pins the
TOC-derived load order and the suite list itself so the harness stops being the one thing nothing
checks.

The generated inventory [`test-cases.md`](20260807-114650/test-cases.md) in each bundle is the
authority on what exists at that point, and the README badge tracks the same number. **`0 skipped`
is a measured figure, not an absent one** — [`tests.txt`](20260807-114650/tests.txt)'s footer reads
`594 passed, 0 failed, 0 skipped, 594 total`, which means the two vendored-payload gate cases found
their sibling `LibKa0s` checkout and actually looked. Coverage is broad but not uniform: 19 of the
20 suite files test addon code, and the twentieth, `test_vendor_sync.lua`, is the vendored-payload
gate — it collapsed from 84 NLOC to 2 at the LibKa0s v1.8.1 / testkit rev-9 re-vendor without losing
either of its cases, because the checks now live in `tests/_kit/vendor_sync.lua`. What the suite
still cannot reach is anything needing a live client: the History window's rendering, the settings
canvas and every taint-sensitive path are covered only by [`../smoke-tests.md`](../smoke-tests.md).

## Lint

Clean over 23 files: 0 warnings, 0 errors, unchanged across all six recorded runs. Those 23 are the
addon's **shipped source and nothing else** — every `.lua` under the five source directories
`core/`, `defaults/`, `locales/`, `modules/` and `settings/`, none of them excluded, which is what
each run's [`lint.txt`](20260807-114650/lint.txt) lists file by file. `.luacheckrc`'s
`exclude_files` carries five globs, and the test suite is one of them: `libs/`, **`tests/`**,
`docs/audits/`, `docs/reviews/`, `_dev/`. So the vendored library is out of scope because it is not
this repo's to fix, but `tests/run.lua`, `tests/wow_mock.lua`, every `tests/test_*.lua` and the
vendored `tests/_kit/` are unlinted too — the lint gate covers what ships and says nothing about the
code that tests it. A `0/0` row is worth exactly that scope and no more.

## Perf

This addon ships **no `tests/perf.lua`**, so the `perf` column is a permanent `skip`. The runner
writes the **first** of `automated-tests-§3`'s two sanctioned reasons into `skipReason` — *"no
tests/perf.lua — this addon ships no offline scenarios"* — because absence is all a script can
detect. The addon's real position is the **second** and more informative reason, and the distinction
matters: this is not a suite nobody got round to writing, it is a recorded **`performance-§12`
no-combat-path exemption**. LootHistory brackets nothing because it has no combat path to bracket.
The exemption is ratified and carried as a register row in [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
→ `## Documented deviations` (the `LH-20`…`LH-26` chain), claimed against criteria **(a)** and
**(c)**, with the committed whole-repo sweep in [`../performance.md`](../performance.md), and that
page states the condition that would end it: the first `OnUpdate` handler, repeating ticker, or
in-combat event handler doing real work re-arms the full wiring MUST.

Two things still follow, and both are standing facts rather than any one run's news. The record says
**nothing** about the addon's runtime cost — `Database:QueryList`'s compiled-filter rewrite is now
four runs old and no bundle has ever put a number on it. And `performance-§9`'s zero-overhead
evidence does not exist for this addon. At the release gate the skip is **NOT EVALUATED** rather
than passed, so the release notes must name the exemption out loud rather than letting a blank
column read as clean.

## Complexity watch list

Current state as of [`20260807-114650`](20260807-114650/) — not that run's diff.
Every function `lizard` warned on, and every file at or above `layout-§1`'s 1000-LOC
on-notice threshold, each with a one-line disposition.

**Reading the `Max CCN` column: the `0` in [`20260804-220017`](20260804-220017/) is an instrument fault, not a measurement.** Runs recorded before the testkit rev-6 re-vendor read `CCN_MAX` out of `lizard`'s `!!!! Warnings` block, which maximizes over *warned* functions only — so it reported `0` the moment the addon reached zero warnings. Of the runs in the table, that bites exactly one: `20260804-220017`, whose true maximum was **15**, and it is there in that bundle's own [`complexity.txt`](20260804-220017/complexity.txt) — six functions at CCN 15, none above. The `58` in [`20260804-182216`](20260804-182216/) came off the same faulty reader but is correct by accident, because that run had nine warned functions for it to maximize over. The generated rows are left exactly as the tool wrote them (`performance-§10`: a hand-edited record is worse than a wrong one, because it reads as measured); [`20260804-233322`](20260804-233322/) was the first run with the fixed kit, which is why `58 → 0 → 15 → 15` in the column is a reporting change followed by honest readings, not a regression and recovery.

**On disposition shelf life.** `automated-tests-§4` retires an entry carried as *accepted* across
**three consecutive release runs**. **No run in this record is a release run** — all six manifests
carry `"release": null` — so that clock has not started, and the two `Accepted` rows below are
carried forward on their own merits rather than by default. Nothing has crossed the three-release
line, and nothing can until the first `--release` run is cut. The row to watch is not either
`Accepted` entry: it is `modules/Analytics.lua`, which has read *"peel next"* since
[`20260804-233322`](20260804-233322/) — four consecutive runs — without a line moving, and which no
deviation ID tracks. That is a shelf-life problem in substance even though the letter of the rule
does not yet reach it.

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|
| — | — | — | **None.** No function exceeds CCN 15. |

That is a result, not an empty section: `"warnings": 0` with `"maxCcn": 15` in
[`20260807-114650/manifest.json`](20260807-114650/manifest.json), and that bundle's
[`complexity.txt`](20260807-114650/complexity.txt) footer states *"No thresholds exceeded"*
outright. The `20260804-182216` baseline listed nine warned functions, from `Database:QueryList` at
58 down to `make` at 16, each with an "accepted" disposition; all nine were split into named helpers
or a module-level dispatch table, and none of those dispositions carries forward because none of the
functions they covered warns any more.

The true maximum is **15**, and six functions sit exactly on the cap without crossing it — unchanged
in membership, CCN and line range across the last four runs. Naming all six, from
[`20260807-114650/complexity.txt`](20260807-114650/complexity.txt): `E@39-159` (the block `lizard`
attributes to `E:WowheadLink`, `modules/Export.lua:39`), `BrowserTable:GroupRecords`
(`modules/BrowserTable.lua:550`), `BrowserTable:UpdateHeaderArrows`
(`modules/BrowserTable.lua:968`), `BrowserTable:BindRow` (`modules/BrowserTable.lua:866`),
`Attribution:OnLootOpened` (`modules/Attribution.lua:173`) and `Compat.ScanBound`
(`core/Compat.lua:271`). None is carried as a watch-list entry, because none warns; and all six are
dense **defaulting/guarding** rather than tangled control flow — `lizard` scores every `and`/`or`
short-circuit as a decision, so a run of `t.k = rec.k or D.k` lines reads high with no branching to
show for it (`performance-§10`).

### Files by `layout-§1` band

`manifest.json` records the band as counts only (`"bandFiles": 3`, `"overCapFiles": 0`); the LOC
column is the same `wc -l` measurement the runner's band counter takes over `*.lua` outside `libs/`
and `tests/_kit/`. **Nothing newly crossed in this run**, and all three line counts are flat against
[`20260807-110451`](20260807-110451/).

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Browser.lua` | 1366 | **Accepted, own disposition — `LH-37`.** The window shell, filter bar and dropdown widget kit; if it needs peeling the seam is the widget kit into a sibling file. Flat this run. This row used to read *"Already tracked as `LH-31`"*, which was the retired **`docs/complexity.md` is not shipped** finding (`automated-tests-§7` retired that file in v2.19.0) — it never tracked a file's size, and `LH-37` (`docs/audits/2026-08-05/02_DEVIATIONS.md`) is the live finding that says so. There is deliberately **no** deviation ID to cite instead: a file in the 1000–1500 band is the **compliant** state under `layout-§1`, on notice rather than in breach, so it is not filed in `docs/ARCHITECTURE.md`'s `## Documented deviations` register. |
| 1000–1500 (on notice) | `modules/Analytics.lua` | 1187 | **Peel next — unblocked since [`20260804-233322`](20260804-233322/), and still not started after four runs.** It was gated on the `Database:Stats` work, which has landed. Split renderers from the formatting/segmenting helpers. Flat at 1187 LOC across the last three runs, nothing tracks it, and that is the gap: a disposition that has named itself next for four consecutive runs is a decision that has stopped being one. Either peel it or file it in the issue store with an owner. |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1097 | **Accepted.** Just over the line, and already three clean layers. Flat at 1097 LOC / 867 NLOC across the last four runs. Watch it; do nothing yet. |
| > 1500 (over cap) | — | — | **None.** No file is over the 1500 cap (`"overCapFiles": 0` in every recorded run). |
