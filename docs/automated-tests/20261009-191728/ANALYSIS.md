# Analysis — 20261009-191728

- **Addon:** LootHistory 1.4.0 → 1.5.0 (release run)
- **Verdict:** green
- **Commit:** `fe1b6cd` (master), clean
- **Previous run:** `20261007-215451` (`15759e0`, feat/2026-10-07-review-audit-remediation, clean)

## Headline

Green on a clean tree at `fe1b6cd`, 11 commits after the previous run, and every condition of the `automated-tests-§3` release gate holds: lint, tests, perf and complexity at `pass`, 0 functions above CCN 15, `blindFiles` 0 ([`manifest.json`](manifest.json)). Almost nothing moved: two new Reconciler cases from the `LED-P2-01` bank-withdraw fix and 18 NLOC. Two things to act on, neither a gate failure: `settings/Panel.lua` has now been *Accepted* across three consecutive release runs and is owed a fix or a tracked deviation ID, and the `perf` suite still records 0 scenarios because `tests/perf.lua` writes no `perf.json`.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261007-215451 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 118 files | [`lint.txt`](lint.txt) | none; 118 files, 0/0 |
| tests | pass | 1523 passed, 1 skipped, 0 failed, 1524 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | 1522 → 1524 total; skips held at 1 |
| perf | pass | 0 scenarios | [`perf.txt`](perf.txt) (no `perf.json` was written; see below) | none; same five checks pass |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | see below |

**Complexity is reported in full.** Every value is from [`manifest.json`](manifest.json) `suites.complexity` and the footer of [`complexity.txt`](complexity.txt):

| Metric | Value |
|---|---|
| Total NLOC | 32955 (was 32937) |
| Functions | 4627 (was 4627) |
| Avg NLOC / function | 6.9 (was 6.9) |
| Avg CCN | 2.4 (was 2.4) |
| Max CCN | 15 (was 15) |
| Avg tokens / function | 64.0 (was 63.9) |
| Warnings (CCN > 15) | 0 (was 0) |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 10 (was 10) |
| Files over the 1500 cap | 0 (was 0) |
| Blind files (parity mismatch) | 0 (was 0) |

**complexity.** Sighted (`blindFiles` 0), so all 4627 functions were measured. The 18 NLOC and the 0.1 rise in average tokens are the `LED-P2-01` fix (`19fc557`, re-read the bank on a bag change at an open bank) and its two cases; the function count and the other averages did not move.

**perf.** Unchanged from the previous run. [`perf.txt`](perf.txt) shows the same five checks passing: the live `NS.Perf` instance, zero allocation for a dropped loot line, no allocation and no scan on an in-combat `BAG_UPDATE`, and one container scan per dirty group. The manifest reads `scenarios: 0` and there is no `perf.json`, because `tests/perf.lua` prints checks rather than the scenario table the runner parses. This is a run of `tests/perf.lua`, not a skip: the `pass` rests on the script's exit code, and it satisfies the release gate's Perf condition. The record still holds no scenario figures to compare (Actions, 2, carried from the previous run).

**tests.** The one skip is unchanged: the kit's `diagnostics contract: an addon that opts out ...` case ([`tests.txt`](tests.txt)). This addon keeps the default, so its report turns logging on and the case beside it covers that path. It is a sanctioned `Kit.skip` with its reason, counted in the total and not in `passed`.

## What moved

- **lint:** did not move: 118 files, 0/0 ([`lint.txt`](lint.txt)).
- **tests:** 1522 → 1524 cases (1523 passed, 1 skipped, 0 failed). The two new cases are in `test_reconciler_rows.lua` (31 → 33): a split withdraw that fires only a bag event is still one MOVE bank to bags, and a bag change with the bank closed never reads the bank ([`test-cases.md`](test-cases.md)). One case was renamed, not added: `LedgerFormat: glyph and color per direction ...` now reads `LedgerFormat: color per direction ...`.
- **perf:** did not move: pass, 0 scenarios, same five checks ([`perf.txt`](perf.txt)).
- **complexity:** NLOC 32937 → 32955 and average tokens 63.9 → 64.0; functions, the other averages, max CCN 15 and 0 warnings held.
- **band files:** did not move. The same ten files, at the same line counts as the previous run.

## Complexity watch list

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

None. `lizard` reports 0 warnings over the sighted shadow ([`complexity.txt`](complexity.txt)), which is what the release gate requires.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `tests/test_browser.lua` | 1459 | **Peel next (2026-10-07).** Carried forward; 41 under the cap. Seam: the timeline-ledger sections into their own suite. |
| 1000–1500 (on notice) | `tests/test_browsertable.lua` | 1392 | **Accepted (2026-10-07).** Carried forward. Re-check at 1450. |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1302 | **Peeled (`LH-08`).** Carried forward. Re-check at 1400; seam: the test-mode dataset. |
| 1000–1500 (on notice) | `core/Database.lua` | 1258 | **Accepted (2026-10-07).** Carried forward. Re-check at 1400; seam: the migration half. |
| 1000–1500 (on notice) | `modules/Browser.lua` | 1231 | **Peeled (`LH-18`).** Carried forward. Re-check at 1400; seam: the per-tab view layer. |
| 1000–1500 (on notice) | `tests/test_schema.lua` | 1202 | **Accepted (2026-09-24).** Carried forward; second release run as *Accepted* (1.4.0, 1.5.0). Re-check at 1300. |
| 1000–1500 (on notice) | `tests/test_database.lua` | 1157 | **Accepted (2026-10-07).** Carried forward. Re-check at 1300. |
| 1000–1500 (on notice) | `settings/Panel.lua` | 1134 | **Shelf life spent.** Third consecutive release run as *Accepted* (1.3.0, 1.4.0, 1.5.0). Owed a fix or a tracked deviation ID (anti-pattern #53); neither exists yet. |
| 1000–1500 (on notice) | `settings/Schema.lua` | 1133 | **Accepted (2026-10-07).** Carried forward. Re-check at 1300. |
| 1000–1500 (on notice) | `tests/test_slash.lua` | 1131 | **Accepted (2026-09-24).** Carried forward; second release run as *Accepted* (1.4.0, 1.5.0). Re-check at 1300. |

The full rulings are the Disposition cells in `RESULTS.md`; only `settings/Panel.lua`'s changed in this commit. The previous run's analysis counted 1.5.0 as the third release run for `tests/test_schema.lua` and `tests/test_slash.lua` as well, but both entered the band on 2026-09-24, after the 1.3.0 release run, so 1.5.0 is their second.

## Actions

1. `settings/Panel.lua`: peel it below 1000 lines, or open a tracked deviation with an ID and an owner and cite it in the Disposition cell. New here; no issue or finding owns it yet.
2. `tests/perf.lua`: honor `--out <path>` and write the `perf.json` the runner records, so the `perf` suite reports scenarios instead of `0`. Carried from `20261007-215451`; no issue or finding owns it yet.
3. `tests/test_browser.lua`: peel the timeline-ledger sections into their own suite before the next case lands there. Carried from `20261007-215451`.
