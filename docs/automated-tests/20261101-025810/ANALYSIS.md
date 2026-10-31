# Analysis — 20261101-025810

- **Addon:** LootHistory 1.5.0
- **Verdict:** green
- **Commit:** `a3a2df2` (feat/2026-10-31-findings-remediation), clean
- **Previous run:** `20261101-002120` (`ad76bb7`, feat/2026-10-31-findings-remediation, clean; labelled `v1.84.0-adoption`)

## Headline

Green on a clean tree at `a3a2df2`, labelled `final-pre-merge`: lint 0/0, 1841 passed with 1 skip and 0 failed, 4 perf scenarios, 0 functions above CCN 15, nothing over the 1500 cap and no blind or crashed files ([`manifest.json`](manifest.json)). The case inventory is identical to the previous run's, and the only measured source movement is 3 NLOC, with `tests/test_libka0s.lua` 5 lines longer. Nothing here needs action before a merge.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261101-002120 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 159 files | [`lint.txt`](lint.txt) | Nothing moved |
| tests | pass | 1841 passed, 1 skipped, 0 failed, 1842 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | Counts and inventory unchanged; recorded time 1575213 → 49322 ms |
| perf | pass | 4 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | Bytes and scans unchanged; timings lower |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | NLOC 42479 → 42482; every other field unchanged |

| Metric | Value |
|---|---|
| Total NLOC | 42482 |
| Functions | 6166 |
| Avg NLOC / function | 6.7 |
| Avg CCN | 2.3 |
| Max CCN | 15 |
| Avg tokens / function | 60.6 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 10 |
| Files over the 1500 cap | 0 |
| Blind files (parity mismatch) | 0 |
| Crashed files (lizard raised) | 0 |

The tests suite is a pass with one standing skip, not a clean 1842. `diagnostics contract: an addon that opts out lands the report and leaves logging off` reports a skip because this addon keeps the default, `Kit.diagnostics.enablesLogging` is not false, so its report turns logging on and the case above it holds that ([`tests.txt`](tests.txt)). It is pre-existing: the previous run recorded the same 1 skip, and it is neither a regression nor counted as passed.

## What moved

- **lint:** did not move: 159 files, 0/0 ([`lint.txt`](lint.txt)).
- **tests:** 1842 cases held, and [`test-cases.md`](test-cases.md) matches the previous bundle's line for line. Recorded time fell from 1575213 ms to 49322 ms ([`manifest.json`](manifest.json)). The bundle holds no evidence of why, and the identical inventory rules out a change in what ran.
- **perf:** scenarios held at 4; bytes and scans did not move. Timings fell: `lootDroppedBracketed` 0.00700 → 0.00508 ms/iter, `lootDroppedBare` 0.00729 → 0.00502, `combatBagUpdate` 0.00110 → 0.00073, `reconcileCleanBags` 0.38744 → 0.28288 ([`perf.txt`](perf.txt)). The suite says its timings are for orientation only, so this is not read as an improvement.
- **complexity:** NLOC 42479 → 42482. Functions 6166, Avg NLOC 6.7, Avg CCN 2.3, Max CCN 15, average tokens 60.6 and 0 warnings all held ([`manifest.json`](manifest.json)).
- **band files:** held at 10, none entering or leaving. `tests/test_libka0s.lua` grew 1103 → 1108, under its re-check at 1300; the other nine did not move (`RESULTS.md`).

## Complexity watch list

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

None. `lizard` reports 0 warnings over the sighted shadow ([`complexity.txt`](complexity.txt)).

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `core/Compat.lua` | 1001 | Carried: Accepted (2026-10-31) |
| 1000–1500 (on notice) | `core/Database.lua` | 1275 | Carried: Accepted (2026-10-07) |
| 1000–1500 (on notice) | `modules/Browser.lua` | 1386 | Carried: Peeled (`LH-18`, 2026-10-07), tracked deviation |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1127 | Carried: Peeled (`LH-08`, 2026-10-07) |
| 1000–1500 (on notice) | `settings/Schema.lua` | 1252 | Carried: Accepted (2026-10-07) |
| 1000–1500 (on notice) | `tests/test_browser.lua` | 1018 | Carried: Peel next (2026-10-07), peeled by `FX-LH-SIZE` |
| 1000–1500 (on notice) | `tests/test_browsertable.lua` | 1395 | Carried: Accepted (2026-10-07) |
| 1000–1500 (on notice) | `tests/test_database.lua` | 1252 | Carried: Accepted (2026-10-07) |
| 1000–1500 (on notice) | `tests/test_libka0s.lua` | 1108 | Carried: Accepted (2026-10-31) |
| 1000–1500 (on notice) | `tests/test_panel.lua` | 1087 | Carried: Accepted (2026-10-31) |

The runner carried every disposition, so none is owed, and nothing newly crossed a threshold. The full wording is in `RESULTS.md`. No file has reached a recorded re-check line.

## Actions

None.
