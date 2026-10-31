# Analysis — 20261031-202125

- **Addon:** LootHistory 1.5.0
- **Verdict:** green
- **Commit:** `1952c06` (feat/2026-10-31-font-pickers-skin-faces), clean
- **Previous run:** `20261009-191728` (`fe1b6cd`, master, clean; the 1.4.0 → 1.5.0 release run)

## Headline

Green on a clean tree at `1952c06`, labelled `pre-merge`: lint 0/0, 1860 passed with 1 skip and 0 failed, 0 functions above CCN 15, nothing over the 1500 cap and no blind or crashed files ([`manifest.json`](manifest.json)). The addon grew sharply since the previous run while its averages fell, so this is size and not density. There is nothing to fix for CCN or NLOC, but the 1000–1500 band went from 10 files to 13, three recorded re-check lines have now fired, and `settings/Panel.lua`'s spent shelf life is still open.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261009-191728 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 154 files | [`lint.txt`](lint.txt) | 118 → 154 files; still 0/0 |
| tests | pass | 1860 passed, 1 skipped, 0 failed, 1861 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | 1524 → 1861 total; skips held at 1 |
| perf | pass | 0 scenarios | [`perf.txt`](perf.txt) (no `perf.json` was written; see below) | none; same five checks pass |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | see below |

**Complexity is reported in full.** Every value is from [`manifest.json`](manifest.json) `suites.complexity` and the footer of [`complexity.txt`](complexity.txt):

| Metric | Value |
|---|---|
| Total NLOC | 42741 (was 32955) |
| Functions | 6203 (was 4627) |
| Avg NLOC / function | 6.7 (was 6.9) |
| Avg CCN | 2.3 (was 2.4) |
| Max CCN | 15 (was 15) |
| Avg tokens / function | 60.9 (was 64.0) |
| Warnings (CCN > 15) | 0 (was 0) |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 13 (was 10) |
| Files over the 1500 cap | 0 (was 0) |
| Blind files (parity mismatch) | 0 (was 0) |
| Crashed files (lizard raised) | 0 (the previous manifest has no such field) |

**complexity.** Sighted (`blindFiles` 0, `crashedFiles` 0), so all 6203 functions were measured. The footer line reads "No thresholds exceeded" for CCN, length, NLOC and parameter count ([`complexity.txt`](complexity.txt)), so there is no CCN or NLOC flag to fix. Every average fell, which makes the growth breadth rather than density. Max CCN sits exactly at the limit, so these functions have no margin: `Ledger.ClassifyItems`, `HT.ColumnLayout`, `Analytics.UpdateCards` and an anonymous function in `tests/test_panel_filters.lua` are among those at 15.

**perf.** Unchanged from the previous run. [`perf.txt`](perf.txt) shows the same five checks passing. The manifest reads `scenarios: 0` and there is no `perf.json`, so `RESULTS.md`'s generated link to that file does not resolve. `tests/perf.lua` prints checks rather than a scenario table, and it writes no JSON. This is a pre-existing condition, not a regression.

**tests.** The one skip is unchanged: the kit's `diagnostics contract: an addon that opts out ...` case ([`tests.txt`](tests.txt)). This addon keeps the default, so its report turns logging on and the case beside it covers that path. It is a sanctioned `Kit.skip` with its reason, counted in the total and not in `passed`.

## What moved

- **lint:** 118 → 154 files, still 0/0 ([`lint.txt`](lint.txt)).
- **tests:** 1524 → 1861 cases. No suite lost cases. The growth is mostly new suites for the simulator (`test_sim_*`) and the skin system (`test_skin*`), plus 11 more in `test_libka0s.lua` (31 → 42) ([`test-cases.md`](test-cases.md)).
- **perf:** did not move: pass, 0 scenarios, same five checks ([`perf.txt`](perf.txt)).
- **complexity:** NLOC 32955 → 42741 and functions 4627 → 6203; Avg NLOC 6.9 → 6.7, Avg CCN 2.4 → 2.3, average tokens 64.0 → 60.9. Max CCN 15 and 0 warnings held.
- **band files:** 10 → 13. New: `core/Compat.lua`, `tests/test_libka0s.lua`, `tests/test_panel.lua`. Grown: `modules/BrowserTable.lua` 1302 → 1407, `modules/Browser.lua` 1231 → 1386, `tests/test_schema.lua` 1202 → 1340, `core/Database.lua` 1258 → 1275, `settings/Panel.lua` 1134 → 1262, `settings/Schema.lua` 1133 → 1252, `tests/test_database.lua` 1157 → 1252, `tests/test_browsertable.lua` 1392 → 1395. Unchanged: `tests/test_browser.lua` 1459, `tests/test_slash.lua` 1131.

## Complexity watch list

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

None. `lizard` reports 0 warnings over the sighted shadow ([`complexity.txt`](complexity.txt)).

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `tests/test_browser.lua` | 1459 | **Peel next (2026-10-07).** Carried forward, not yet peeled; 41 under the cap. |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1407 | **Peeled (`LH-08`).** Carried forward. **Its 1400 re-check has fired.** Seam: the test-mode dataset. |
| 1000–1500 (on notice) | `tests/test_browsertable.lua` | 1395 | **Accepted (2026-10-07).** Carried forward. Re-check at 1450. |
| 1000–1500 (on notice) | `modules/Browser.lua` | 1386 | **Peeled (`LH-18`).** Carried forward. Re-check at 1400, 14 lines away. |
| 1000–1500 (on notice) | `tests/test_schema.lua` | 1340 | **Accepted (2026-09-24).** Carried forward. **Its 1300 re-check has fired.** Seam: row contract vs CLI. Its next release run is its third as *Accepted*. |
| 1000–1500 (on notice) | `core/Database.lua` | 1275 | **Accepted (2026-10-07).** Carried forward. Re-check at 1400. |
| 1000–1500 (on notice) | `settings/Panel.lua` | 1262 | **Shelf life spent at `20261009-191728`, still open.** Owed a fix or a tracked deviation ID (anti-pattern #53); neither exists. **Its 1200 re-check has also fired.** |
| 1000–1500 (on notice) | `settings/Schema.lua` | 1252 | **Accepted (2026-10-07).** Carried forward. Re-check at 1300. |
| 1000–1500 (on notice) | `tests/test_database.lua` | 1252 | **Accepted (2026-10-07).** Carried forward. Re-check at 1300. |
| 1000–1500 (on notice) | `tests/test_slash.lua` | 1131 | **Accepted (2026-09-24).** Carried forward. Its next release run is its third as *Accepted*. Re-check at 1300. |
| 1000–1500 (on notice) | `tests/test_panel.lua` | 1080 | **Accepted (2026-10-31).** Back in the band: 750 NLOC, one section per panel concern, no runtime cost. Re-check at 1300. |
| 1000–1500 (on notice) | `tests/test_libka0s.lua` | 1054 | **Accepted (2026-10-31).** New in the band: 708 NLOC, deliberately one adoption suite under section rules, no runtime cost. Re-check at 1300. |
| 1000–1500 (on notice) | `core/Compat.lua` | 1001 | **Accepted (2026-10-31).** New in the band: 673 NLOC over 83 functions, the compat firewall as small commented shims, cohesive by design. Re-check at 1200. |

The full rulings are the Disposition cells in `RESULTS.md`; only the three new rows were written in this commit, and the fired re-checks above are reported here rather than re-ruled.

## Actions

1. `settings/Panel.lua`: peel it below 1000 lines, or open a tracked deviation with an ID and an owner and cite it in the Disposition cell. Carried from `20261009-191728`; no issue or finding owns it yet.
2. `modules/BrowserTable.lua`: decide on its fired 1400 re-check; the recorded seam is the test-mode dataset (`BuildTestData` and its `test*` helpers). New here.
3. `tests/test_schema.lua`: decide on its fired 1300 re-check; the recorded seam is row contract vs CLI. New here.
4. `tests/test_browser.lua`: peel the timeline-ledger sections into their own suite before the next case lands there. Carried from `20261007-215451`.
5. `tests/perf.lua`: honor `--out <path>` and write the `perf.json` the runner records, so the `perf` suite reports scenarios instead of `0`. Carried from `20261007-215451`; no issue or finding owns it yet.
