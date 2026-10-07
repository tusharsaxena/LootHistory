# Automated test results

<!-- Regenerated whole by tests/_kit/run-automated-tests.sh on every run. -->
<!-- This file is OVERWRITTEN IN PLACE — the git history of this one path is the trend line. -->
<!-- Everything here is generated EXCEPT the watch list's Disposition column. -->

One row per run. The frozen evidence for each is in the dated folder beside this file;
the analysis of a given run is its `ANALYSIS.md`.

**`lint` and `tests` gate the run and gate the commit** (`testing-§4`).
**`perf` and `complexity` never fail a run and never block a commit** — they are recorded,
read and compared, not thresholded (`performance-§9`, `performance-§10`).

**The tag is gated on all four suites at `pass`, plus zero functions above CCN 15**
(`automated-tests-§3`, *The release gate*), evaluated by `/dev-copilot:bump-version` from the
`manifest.json` the release run writes — not by this script, whose exit code is unchanged.

A `skip` is a suite that did not run at all. It is never a pass, and at the release gate it is
**NOT EVALUATED** rather than passed: install the tool and re-run. A `—` is a suite that was
not selected, which is a different fact again.

The **Tests** cell reads `passed/skipped/total`.

**Commit** is the short sha the run measured and **Tree** is whether that tree was clean at the
time. Both are read from git by the runner; neither is ever typed. A **dirty** row measured bytes
that no sha can bring back, so it is kept as an experiment honestly labeled rather than dropped —
and a release record is refused outright on a dirty tree, so no release row can be one.

A row reading `unknown` in both cells was recorded before the runner emitted them. That is what
the record holds about those runs — it is not `clean`, and it is not reconstructed from git
archaeology, for the same reason a skip is never a pass (`automated-tests-§4`).

| Run | Commit | Tree | Version | Lint w/e | Files | Tests | Perf | NLOC | Funcs | Avg NLOC | Avg CCN | Max CCN | CCN warn | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [`20261007-215451`](20261007-215451/) | `15759e0` | clean | 1.4.0 | 0/0 | 118 | 1521/1/1522 | pass | 32937 | 4627 | 6.9 | 2.4 | 15 | 0 | **green** |
| [`20260927-030334`](20260927-030334/) | `8e60c1f` | clean | 1.3.0 → 1.4.0 | 0/0 | 70 | 961/0/961 | skip | 18447 | 2519 | 6.3 | 2.1 | 15 | 0 | **green** |
| [`20260926-193103`](20260926-193103/) | `93e879d` | clean | 1.3.0 | 0/0 | 70 | 961/0/961 | skip | 18447 | 2519 | 6.3 | 2.1 | 15 | 0 | **green** |
| [`20260926-160249`](20260926-160249/) | `3ce80a7` | clean | 1.3.0 | 0/0 | 70 | 961/0/961 | skip | 18443 | 2519 | 6.3 | 2.1 | 15 | 0 | **green** |
| [`20260924-121347`](20260924-121347/) | `2f232f0` | clean | 1.3.0 | 0/0 | 67 | 928/0/928 | skip | 17579 | 2395 | 6.3 | 2.1 | 15 | 0 | **green** |
| [`20260916-184506`](20260916-184506/) | unknown | unknown | 1.3.0 | 0/0 | 63 | 786/0/786 | skip | 15349 | 2045 | 6.4 | 2.1 | 15 | 0 | **green** |
| [`20260916-094432`](20260916-094432/) | unknown | unknown | 1.3.0 | 0/0 | 59 | 768/0/768 | skip | 14889 | 1980 | 6.4 | 2.2 | 16 | 1 | **green** |
| [`20260910-234511`](20260910-234511/) | unknown | unknown | 1.2.0 → 1.3.0 | 0/0 | 59 | 720/0/720 | skip | 13892 | 1810 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260908-181338`](20260908-181338/) | unknown | unknown | 1.2.0 | 0/0 | 58 | 714/0/714 | skip | 13670 | 1803 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260825-103428`](20260825-103428/) | unknown | unknown | 1.2.0 | 0/0 | 28 | 644/644 | skip | 12116 | 1639 | 6.4 | 2.2 | 15 | 0 | **green** |
| [`20260807-114650`](20260807-114650/) | unknown | unknown | 1.2.0 | 0/0 | 23 | 594/594 | skip | 11479 | 1531 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260807-110451`](20260807-110451/) | unknown | unknown | 1.2.0 | 0/0 | 23 | 594/594 | skip | 11479 | 1531 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260807-022940`](20260807-022940/) | unknown | unknown | 1.2.0 | 0/0 | 23 | 594/594 | skip | 11479 | 1531 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260804-233322`](20260804-233322/) | unknown | unknown | 1.2.0 | 0/0 | 23 | 579/579 | skip | 11367 | 1518 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260804-220017`](20260804-220017/) | unknown | unknown | 1.2.0 | 0/0 | 23 | 579/579 | skip | 11361 | 1518 | 6.5 | 2.2 | 0 | 0 | **green** |
| [`20260804-182216`](20260804-182216/) | unknown | unknown | 1.2.0 | 0/0 | 23 | 563/563 | skip | 11196 | 1457 | 6.7 | 2.3 | 58 | 9 | **green** |

## Test suite

**1522 cases** — 1521 passed, 0 failed, 1 skipped. The generated inventory
[`20261007-215451/test-cases.md`](20261007-215451/test-cases.md) is the authority on which cases existed at this run;
`docs/test-cases.md` is that same list at HEAD.

Moved **961 → 1522** since the previous run.

**1 case(s) reported a `skip`.** A skip is counted in the total and never in `passed`, and at
the release gate it is NOT EVALUATED rather than passed (`automated-tests-§3`).

## Lint

**0 warnings / 0 errors over 118 files** (`luacheck .`).

Read that figure with its scope attached: `.luacheckrc` excludes 5 path(s) from it — `libs/`, `docs/audits/`, `docs/reviews/`, `_dev/`, `tests/_kit/` —
so nothing under them is in the count above. A `0/0` that never moves is partly a statement about
what was never looked at, which is why the exclusions are NAMED here on every run rather than left
to whoever thinks to open `.luacheckrc`.

## Perf

**0 scenarios** from `tests/perf.lua`; the measurements are in
[`20261007-215451/perf.json`](20261007-215451/perf.json).

This run's `tests/perf.lua` printed no scenario table this generator could read, so the
names are in [`20261007-215451/perf.txt`](20261007-215451/perf.txt) rather than here.

`perf` never fails a run and never blocks a commit — it is recorded, read and compared, not
thresholded (`performance-§9`). It does gate the **tag** (`automated-tests-§3`).

## Complexity watch list

Current as of [`20261007-215451`](20261007-215451/) — **this run's measurement, not its diff.** Max CCN **15** across 4627
functions, **0** of them warned on; 10 file(s) in the 1000–1500 band and 0 over the 1500 cap
(`layout-§1`).

Every row below is generated from this run's own `lizard` output. **The `Disposition` column is
the one authored cell in this file** (`automated-tests-§4`, *the one boundary*): it is carried
forward verbatim while its entry is unchanged, and left **blank** when the entry is new — a blank
cell is this file saying something crossed and nobody has ruled on it yet.

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

None.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `core/Database.lua` | 1258 | **Accepted (2026-10-07).** New in the band: the timeline ledger's v13 migration (`convertHolderMoves`), the ledger accumulators and `Stats` grew it to 1258 lines, 805 NLOC over 81 functions at this run ([`complexity.txt`](20261007-215451/complexity.txt)). `LH-09` brought its four functions above CCN 15 down to 12 or below with named helpers, so the size is breadth, not tangle. On notice, which is the compliant state under `layout-§1`. Re-check at 1400 lines; the seam then is the migration half (the file-scope steps from `migrateLog` through `NS:RunMigrations`, lines 16-424) into a file of its own. |
| 1000–1500 (on notice) | `modules/Browser.lua` | 1231 | **Peeled (`LH-18`, 2026-10-07).** The 1400 re-check fired (1416 after the 2026-10-07 review, review F-002 / LH-R-02). The widget kit proper had already left: the dropdowns are `LibKa0s-Widgets-1.0`'s (through `core/WidgetsSetup.lua`) and the bar's construction is `modules/BrowserFilterBar.lua`. What remained of it, the dropdown-option kit — `qualityColor`, the Bound labels and order, `dataset`, `withAll` and the seven option builders (`B._options`) — moved verbatim to `modules/BrowserWidgets.lua` (209 lines), loaded directly before it. What remains is the window shell: frame, skin, tabs, per-tab views, the footer, master chrome and visibility. `LH-37` (`docs/audits/2026-08-05/02_DEVIATIONS.md`) stays the finding of record for its size; a file in the 1000–1500 band is the **compliant** state under `layout-§1`, so there is no deviation ID. Re-check at 1400 lines; the next seam is the per-tab view layer (`CaptureView` / `ApplyView` / `resolveInto` and the `live` park). |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1302 | **Peeled (`LH-08`, 2026-10-07).** The 1300 re-check fired (1476 at the 2026-10-07 review, 24 under the cap: review F-002), and the display-list layer — `SortRecords`, `SetSort`, `SetGroupBy`, `ToggleCollapse`, `GroupRecords` with `GROUP_OF` / `groupOf` / `GROUP_PREFIX`, `CurrentRecords`, `BuildDisplayList`, `SetFilter`, `OrderedFilteredRecords` — moved verbatim to `modules/BrowserTableGroup.lua` (227 lines), loaded directly after it. What remains is the column model, the pooled rows and header, the row menu and the test-mode dataset. 1272 after the peel, 1302 at this run: `LH-14` split `holderMoves` and `SetTestMode` into named helpers (941 NLOC over 109 functions, [`complexity.txt`](20261007-215451/complexity.txt)). Re-check at 1400 lines; the next seam is the test-mode dataset (`BuildTestData` and its `test*` helpers). |
| 1000–1500 (on notice) | `settings/Panel.lua` | 1134 | **Accepted.** 1134 lines at this run, up from 1107 at [`20260927-030334`](20260927-030334/); 576 NLOC over 59 functions ([`complexity.txt`](20261007-215451/complexity.txt)), so about half of it is code, because a settings page is mostly declarative layout. On notice, which is the compliant state under `layout-§1`, not a breach. Re-check at 1200, or the moment a fourth tab arrives. |
| 1000–1500 (on notice) | `settings/Schema.lua` | 1133 | **Accepted (2026-10-07).** New in the band: 1133 lines, but 561 NLOC over 107 functions at an average CCN of 2.8 ([`complexity.txt`](20261007-215451/complexity.txt)). It is the schema row table, which is declarative data with one small getter or setter per row, so its length is the settings surface, not tangle. On notice, the compliant state under `layout-§1`. Re-check at 1300 lines; the seam then is the row table split by settings page. |
| 1000–1500 (on notice) | `tests/test_browser.lua` | 1459 | **Peel next (2026-10-07).** New in the band and the largest authored file: 1459 lines, 41 under the cap, 1144 NLOC over 209 functions ([`complexity.txt`](20261007-215451/complexity.txt)). It already turned cases away: `LH-14` put its Character-option pins in `tests/test_widgets.lua` because adding them here would have crossed 1500. A test file has no runtime cost, but the next Browser change has no room, so it is peeled before it grows again. Seam: the timeline-ledger sections (P3 per-tab filters onward, from line 1020) into their own suite, the way `test_slash_degraded.lua` came out of `test_slash.lua`. Re-check at 1480 lines at the latest. |
| 1000–1500 (on notice) | `tests/test_browsertable.lua` | 1392 | **Accepted (2026-10-07).** New in the band: 1392 lines, 1130 NLOC over 149 functions ([`complexity.txt`](20261007-215451/complexity.txt)), grown by `LH-14`'s characterization cases. Its cases are grouped by concern under section rules. Re-check at 1450 lines; the seam then is the Test mode section (from `-- ── Test mode`) into its own suite. |
| 1000–1500 (on notice) | `tests/test_database.lua` | 1157 | **Accepted (2026-10-07).** New in the band: 1157 lines, 980 NLOC over 114 functions ([`complexity.txt`](20261007-215451/complexity.txt)), grown with the timeline ledger's migration and query cases and `LH-09`'s characterization pins. A test file has no runtime cost and its cases are grouped by concern. Re-check at 1300 lines, and peel the v13 migration cases into their own suite then. |
| 1000–1500 (on notice) | `tests/test_schema.lua` | 1202 | **Accepted (2026-09-24).** The schema suite grew with the `LibKa0s-Schema-1.0` handover, the retention-shortening confirm (`LH-04`) and the `minimap.shown` row (`LH-13`). 1202 lines at this run, up from 1199 at [`20260927-030334`](20260927-030334/); 870 NLOC over 106 functions ([`complexity.txt`](20261007-215451/complexity.txt)). A test file has no runtime cost and its cases are already grouped by concern, so the split is mechanical when it is due. Re-check at 1300 lines, and peel by concern (row contract vs CLI) then, the way `test_slash_degraded.lua` came out of `test_slash.lua`. |
| 1000–1500 (on notice) | `tests/test_slash.lua` | 1131 | **Accepted (2026-09-24).** Already peeled once: `LH-16` moved the degraded-path cases into `tests/test_slash_degraded.lua` when it neared 1100. 1131 lines at this run, up from 1094 at [`20260927-030334`](20260927-030334/); 785 NLOC over 174 small functions ([`complexity.txt`](20261007-215451/complexity.txt)), one per case. Re-check at 1300 lines, and split the next concern out then. |

`lizard` counts every `and`/`or` short-circuit as a decision, so in Lua a run of
`t.k = rec.k or D.k` defaulting lines scores high with no visible branching at all: a large CCN
here usually means *this function defaults or guards a lot of fields* rather than *this function
is tangled*, and the two want different fixes (`performance-§10`).

