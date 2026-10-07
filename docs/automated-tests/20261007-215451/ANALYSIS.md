# Analysis — 20261007-215451

- **Addon:** LootHistory 1.4.0
- **Verdict:** green
- **Commit:** `15759e0` (feat/2026-10-07-review-audit-remediation), clean
- **Previous run:** `20260927-030334` (`8e60c1f`, master, clean; release run for 1.4.0)

## Headline

Green on a clean tree at `15759e0`, 191 commits after the previous run. This is the first **sighted** complexity run in the record: the previous bundle measured on a kit older than revision 35, so lizard was blind in part of the source. This run measured every function (0 blind files) and found 0 above CCN 15, max 15, because `LH-09` through `LH-14` split the 26 functions above 15 that the 2026-10-07 review found. Two things to act on, neither a gate failure: `tests/test_browser.lua` is 41 lines under the cap, and the `perf` suite reports 0 scenarios because `tests/perf.lua` writes no `perf.json`.

## Suites

| Suite | Status | Result | Artifact | Moved since 20260927-030334 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 118 files | [`lint.txt`](lint.txt) | 70 → 118 files, still 0/0 |
| tests | pass | 1521 passed, 1 skipped, 0 failed, 1522 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | 961 → 1522 total; 0 → 1 skipped |
| perf | pass | 0 scenarios | [`perf.txt`](perf.txt) (no `perf.json` was written; see below) | skip → pass |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | sighted for the first time; see below |

**Complexity is reported in full.** Every value is from [`manifest.json`](manifest.json) `suites.complexity` and the footer of [`complexity.txt`](complexity.txt):

| Metric | Value |
|---|---|
| Total NLOC | 32937 (was 18447) |
| Functions | 4627 (was 2519) |
| Avg NLOC / function | 6.9 (was 6.3) |
| Avg CCN | 2.4 (was 2.1) |
| Max CCN | 15 (was 15) |
| Avg tokens / function | 63.9 (was 50.9) |
| Warnings (CCN > 15) | 0 (was 0) |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 10 (was 6) |
| Files over the 1500 cap | 0 (was 0) |
| Blind files (parity mismatch) | 0 (not recorded before: the previous run's kit predates revision 35) |

**complexity.** The runner built the sighted shadow and its function-count parity check found no blind file, so every one of the 4627 functions was measured. The previous run's 2519 functions were measured unsighted, so the two function counts and averages are not like for like: part of the rise is source that lizard used to skip, and part is the timeline ledger (spec phases 2 to 7), which added the ledger, holdings, reconciler, escrow and timeline modules after it. The averages rose (CCN 2.1 → 2.4, tokens 50.9 → 63.9), which is denser code as well as more of it. The 0 warnings is not a carried figure: between the runs the sighted runner reported 26 warnings at max CCN 24 (review 2026-10-07 F-001, LH-R-01), and `LH-09`, `LH-10`, `LH-11`, `LH-12`, `LH-13` and `LH-14` brought each one to 15 or below, with a characterization test first. Those were real regressions, not only newly sighted debt.

**perf.** The `performance-§12` no-combat-path exemption the previous run skipped under was retired by `571deb4` (the timeline ledger put holdings work behind `BAG_UPDATE`, money and currency events, which fire in combat; `docs/performance.md`), so the suite now runs `tests/perf.lua`. [`perf.txt`](perf.txt) shows its five checks passing: the live `NS.Perf` instance, zero allocation for a dropped loot line, no allocation and no scan on an in-combat `BAG_UPDATE`, and one container scan per dirty group. But the manifest reads `scenarios: 0` and there is no `perf.json` in this bundle, because `tests/perf.lua` ignores the runner's `--out` argument and prints checks rather than the scenario table the runner parses. So the `pass` here rests on the script's exit code alone, and the record holds no scenario figures to compare against the next run. Not a regression in the addon; a gap between this addon's perf script and the runner's contract (Actions, 2).

**tests.** The one skip is the kit's `diagnostics contract: an addon that opts out ...` case ([`tests.txt`](tests.txt)): this addon keeps the default, so its report turns logging on and the case beside it covers that path. It is a sanctioned `Kit.skip` with its reason, counted in the total and not in `passed`.

## What moved

- **lint:** 70 → 118 files in scope, still 0/0 ([`lint.txt`](lint.txt)). The rise is new source and suite files since the previous run. The `.luacheckrc` exclusions are the five `RESULTS.md` names.
- **tests:** 961 → 1522 cases (1521 passed, 1 skipped, 0 failed). [`test-cases.md`](test-cases.md) is the inventory; it equals `docs/test-cases.md` at this commit. `LH-14` added six of them: the Character option lists, the sample's holder-move pairs, `GroupRecords` under nil, unknown and column-less modes, and `SetTestMode`'s no-op, trace lines and Refresh fallback.
- **perf:** skip (ratified exemption) → pass with 0 scenarios, as above.
- **complexity:** every footer field moved, as in the table. Max CCN held at 15 and warnings at 0.
- **band files:** 6 → 10. In: `core/Database.lua` (1258), `settings/Schema.lua` (1133), `tests/test_browser.lua` (1459), `tests/test_browsertable.lua` (1392), `tests/test_database.lua` (1157). Out: `modules/Analytics.lua`, now 674 lines after the #32 peel (`6faecb1`, `d9ebc61`; #32 is closed). Every file that stayed moved: `modules/BrowserTable.lua` 1227 → 1302 (the `LH-08` peel took it from 1476 to 1272, and `LH-14`'s helpers added 30), `modules/Browser.lua` 1289 → 1231 (the `LH-18` peel), `settings/Panel.lua` 1107 → 1134, `tests/test_schema.lua` 1199 → 1202, `tests/test_slash.lua` 1094 → 1131.

## Complexity watch list

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

None. `lizard` reports 0 warnings over the sighted shadow ([`complexity.txt`](complexity.txt)), so the `automated-tests-§3` release gate's CCN condition is clear.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `tests/test_browser.lua` | 1459 | **Peel next.** 41 under the cap; `LH-14` already had to put cases elsewhere. Seam: the timeline-ledger sections (from line 1020) into their own suite. |
| 1000–1500 (on notice) | `tests/test_browsertable.lua` | 1392 | **Accepted (2026-10-07).** Re-check at 1450; seam: the Test mode section. |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1302 | **Peeled (`LH-08`).** 1272 after the peel, 1302 with `LH-14`'s helpers. Re-check at 1400; seam: the test-mode dataset. |
| 1000–1500 (on notice) | `core/Database.lua` | 1258 | **Accepted (2026-10-07).** `LH-09` split its four CCN>15 functions. Re-check at 1400; seam: the migration half. |
| 1000–1500 (on notice) | `modules/Browser.lua` | 1231 | **Peeled (`LH-18`).** Carried forward. Re-check at 1400; seam: the per-tab view layer. |
| 1000–1500 (on notice) | `tests/test_schema.lua` | 1202 | **Accepted (2026-09-24).** Carried forward with the new count. Re-check at 1300. |
| 1000–1500 (on notice) | `tests/test_database.lua` | 1157 | **Accepted (2026-10-07).** Re-check at 1300; seam: the v13 migration cases. |
| 1000–1500 (on notice) | `settings/Panel.lua` | 1134 | **Accepted.** Carried forward with the new count. Re-check at 1200 or a fourth tab. |
| 1000–1500 (on notice) | `settings/Schema.lua` | 1133 | **Accepted (2026-10-07).** Declarative row table, average CCN 2.8. Re-check at 1300. |
| 1000–1500 (on notice) | `tests/test_slash.lua` | 1131 | **Accepted (2026-09-24).** Carried forward with the new count. Re-check at 1300. |

The full rulings, with their figures, are the Disposition cells in `RESULTS.md`, which this run's five new band files left blank and which were filled in the same commit as this file. **Shelf life:** this is not a release run, so it does not count toward the three consecutive release runs after which an *Accepted* entry is owed a fix or a tracked deviation ID (anti-pattern #53). The 1.5.0 release run is the third for `settings/Panel.lua`, `tests/test_schema.lua` and `tests/test_slash.lua`.

## Actions

1. `tests/test_browser.lua`: peel the timeline-ledger sections into their own suite before the next case lands there. New here; no issue or finding owns it yet.
2. `tests/perf.lua`: honor `--out <path>` and write the `perf.json` the runner records, so the `perf` suite reports scenarios instead of `0` and the next run has figures to compare. New here; no issue or finding owns it yet.
