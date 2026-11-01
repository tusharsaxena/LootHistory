# Analysis — 20261101-143701

- **Addon:** LootHistory 1.5.0
- **Verdict:** green
- **Commit:** `29746ad` (feat/2026-11-01-full-skinning), clean
- **Previous run:** `20261101-025810` (`a3a2df2`, feat/2026-10-31-findings-remediation, clean; labelled `final-pre-merge`)

## Headline

Green on a clean tree at `29746ad`, labelled `full skinning FS-LH`: lint 0/0, 1845 passed with 1 skip and 0 failed, 4 perf scenarios, 0 functions above CCN 15, nothing over the 1500 cap and no blind or crashed files ([`manifest.json`](manifest.json)). This run measures the re-vendor of LibKa0s v1.85.0 and the addon's causes of the full skinning run.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261101-025810 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 159 files | [`lint.txt`](lint.txt) | Nothing moved |
| tests | pass | 1845 passed, 1 skipped, 0 failed, 1846 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | 1842 → 1846 cases |
| perf | pass | 4 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | Bytes and scans unchanged |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | NLOC 42482 → 42624, functions 6166 → 6183 |

| Metric | Value |
|---|---|
| Total NLOC | 42624 |
| Functions | 6183 |
| Avg NLOC / function | 6.7 |
| Avg CCN | 2.3 |
| Max CCN | 15 |
| Avg tokens / function | 60.7 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 10 |
| Files over the 1500 cap | 0 |
| Blind files (parity mismatch) | 0 |
| Crashed files (lizard raised) | 0 |

The tests suite is a pass with one standing skip, not a clean 1846: the same `diagnostics contract` case as the previous run, because this addon keeps the default ([`tests.txt`](tests.txt)).

## What moved

- **lint:** did not move: 159 files, 0/0 ([`lint.txt`](lint.txt)).
- **tests:** 1842 → 1846: the v1.85.0 minors pin, the grip and export title case, the strip mark case and the degraded tab and checkbox case ([`test-cases.md`](test-cases.md)).
- **perf:** scenarios held at 4; bytes and scans did not move, `reconcileCleanBags` at 118120 B/iter under its ceiling of 124000 ([`perf.txt`](perf.txt)). No perf path was touched: the changes are window chrome.
- **complexity:** NLOC 42482 → 42624 and functions 6166 → 6183, mostly the degraded facade and the test cases. Avg NLOC 6.7, Avg CCN 2.3 and Max CCN 15 held; average tokens 60.6 → 60.7 ([`manifest.json`](manifest.json)).
- **band files:** held at 10. `modules/Browser.lua` fell 1386 → 1370 with `ReskinTabs` gone, `tests/test_libka0s.lua` grew 1108 → 1162 with the v1.85.0 pin, under its re-check at 1300 (`RESULTS.md`).

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
| 1000–1500 (on notice) | `modules/Browser.lua` | 1370 | Carried: Peeled (`LH-18`, 2026-10-07), tracked deviation |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1126 | Carried: Peeled (`LH-08`, 2026-10-07) |
| 1000–1500 (on notice) | `settings/Schema.lua` | 1252 | Carried: Accepted (2026-10-07) |
| 1000–1500 (on notice) | `tests/test_browser.lua` | 1018 | Carried: Peel next (2026-10-07), peeled by `FX-LH-SIZE` |
| 1000–1500 (on notice) | `tests/test_browsertable.lua` | 1395 | Carried: Accepted (2026-10-07) |
| 1000–1500 (on notice) | `tests/test_database.lua` | 1252 | Carried: Accepted (2026-10-07) |
| 1000–1500 (on notice) | `tests/test_libka0s.lua` | 1162 | Carried: Accepted (2026-10-31) |
| 1000–1500 (on notice) | `tests/test_panel.lua` | 1087 | Carried: Accepted (2026-10-31) |

The runner carried every disposition, so none is owed, and nothing newly crossed a threshold. The full wording is in `RESULTS.md`. No file has reached a recorded re-check line.

## Actions

None here. The in-client checks the run opened are on the owed line of `docs/smoke-tests.md`.
