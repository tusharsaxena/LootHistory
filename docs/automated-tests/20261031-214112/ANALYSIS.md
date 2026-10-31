# Analysis — 20261031-214112

- **Addon:** LootHistory 1.5.0
- **Verdict:** green
- **Commit:** `d902af3` (feat/2026-10-31-findings-remediation), clean
- **Previous run:** `20261031-202125` (`1952c06`, feat/2026-10-31-font-pickers-skin-faces, clean; labelled `pre-merge`)

## Headline

Green on a clean tree at `d902af3`, labelled `findings-remediation`: lint 0/0, 1860 passed with 1 skip and 0 failed, 4 perf scenarios, 0 functions above CCN 15, nothing over the 1500 cap and no blind or crashed files ([`manifest.json`](manifest.json)). The findings remediation moved code rather than changing it: the case count held at 1861, lint gained five files, and the 1000–1500 band fell from 13 files to 10. The `perf` suite now reports real scenarios and writes `perf.json`, which closes the gap the previous run carried. Nothing here needs action before a merge.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261031-202125 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 159 files | [`lint.txt`](lint.txt) | 154 → 159 files; still 0/0 |
| tests | pass | 1860 passed, 1 skipped, 0 failed, 1861 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | none; skips held at 1 |
| perf | pass | 4 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | 0 → 4 scenarios; `perf.json` now written |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | see below |

| Metric | Value |
|---|---|
| Total NLOC | 42868 (was 42741) |
| Functions | 6212 (was 6203) |
| Avg NLOC / function | 6.7 (was 6.7) |
| Avg CCN | 2.3 (was 2.3) |
| Max CCN | 15 (was 15) |
| Avg tokens / function | 60.9 (was 60.9) |
| Warnings (CCN > 15) | 0 (was 0) |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 10 (was 13) |
| Files over the 1500 cap | 0 (was 0) |
| Blind files (parity mismatch) | 0 (was 0) |
| Crashed files (lizard raised) | 0 (was 0) |

**complexity.** A clean pass on the sighted gate (`blindFiles` 0, `crashedFiles` 0), so all 6212 functions were measured. The footer reads "No thresholds exceeded" for CCN, length, NLOC and parameter count ([`complexity.txt`](complexity.txt)). The totals rose slightly and every average held, so the addon got no denser. Max CCN still sits exactly at the limit, so a function at 15 has no margin.

**tests.** The one skip is unchanged: the kit's `diagnostics contract: an addon that opts out ...` case ([`tests.txt`](tests.txt)). This addon keeps the default (`Kit.diagnostics.enablesLogging` is not false), so its report turns logging on and the case above it covers that path. It is a sanctioned `Kit.skip` with its reason, counted in the total and not in `passed`.

**perf.** A pass, and a change of shape rather than of behavior. The previous run's manifest read `scenarios: 0` with no `perf.json`, because `tests/perf.lua` printed checks only. This run prints a scenario table and pins each scenario's bytes and scans ([`perf.txt`](perf.txt)). All ten checks pass: `reconcileCleanBags` stands at 118120.0 B/iter against a ceiling of 124000, with scans pinned at 1, and the other three scenarios allocate nothing and scan nothing ([`perf.json`](perf.json)). The timings are for orientation within a run and are not comparable across machines.

## What moved

- **lint:** 154 → 159 files, still 0/0 ([`lint.txt`](lint.txt)).
- **tests:** did not move at 1861 cases. The same cases moved between files ([`test-cases.md`](test-cases.md)): `test_browser.lua` 96 → 74 with 22 in the new `test_browser_filterbar.lua`, `test_schema.lua` 73 → 48 with 25 in the new `test_schema_seam.lua`, and `test_slash.lua` 63 → 50 with 13 in the new `test_slash_verbs.lua`.
- **perf:** 0 → 4 scenarios, and `perf.json` exists for the first time. The earlier checks are replaced by per-scenario ceilings and scan pins. The zero-overhead check still passes at 0.0 B/iter bracketed and bare ([`perf.txt`](perf.txt)). This row is the first with scenario figures, so there is no earlier reading to diff them against.
- **complexity:** NLOC 42741 → 42868 and functions 6203 → 6212. Avg NLOC 6.7, Avg CCN 2.3, average tokens 60.9, Max CCN 15 and 0 warnings all held.
- **band files:** 13 → 10. Gone from the band: `settings/Panel.lua`, `tests/test_schema.lua`, `tests/test_slash.lua`. Peeled and still in it: `modules/BrowserTable.lua` 1407 → 1127, `tests/test_browser.lua` 1459 → 1018. Grown: `tests/test_panel.lua` 1080 → 1083. No file newly entered the band (`RESULTS.md`).

## Complexity watch list

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

None. `lizard` reports 0 warnings over the sighted shadow ([`complexity.txt`](complexity.txt)).

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `tests/test_browsertable.lua` | 1395 | **Accepted (2026-10-07).** Carried forward. Re-check at 1450. |
| 1000–1500 (on notice) | `modules/Browser.lua` | 1386 | **Tracked deviation (`layout-§1`, 2026-10-31).** Carried forward; 14 lines from its 1400 re-check. |
| 1000–1500 (on notice) | `core/Database.lua` | 1275 | **Accepted (2026-10-07).** Carried forward. Re-check at 1400. |
| 1000–1500 (on notice) | `settings/Schema.lua` | 1252 | **Accepted (2026-10-07).** Carried forward. Re-check at 1300. |
| 1000–1500 (on notice) | `tests/test_database.lua` | 1252 | **Accepted (2026-10-07).** Carried forward. Re-check at 1300. |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1127 | **Peeled again (`FX-LH-SIZE`, 2026-10-31).** Carried forward. Re-check at 1400; next seam is the row context menu. |
| 1000–1500 (on notice) | `tests/test_panel.lua` | 1083 | **Accepted (2026-10-31).** Carried forward. Re-check at 1300. |
| 1000–1500 (on notice) | `tests/test_libka0s.lua` | 1054 | **Accepted (2026-10-31).** Carried forward. Re-check at 1300. |
| 1000–1500 (on notice) | `tests/test_browser.lua` | 1018 | **Peeled (`FX-LH-SIZE`, 2026-10-31).** Carried forward. Re-check at 1300; next seam is the Master controls cases. |
| 1000–1500 (on notice) | `core/Compat.lua` | 1001 | **Accepted (2026-10-31).** Carried forward. Re-check at 1200. |

The full rulings are the Disposition cells in `RESULTS.md`. Every row arrived carried forward with no blank cell, so none was written in this commit, and no re-check fired at this run.

## Actions

None. The previous run's five actions are all closed. `settings/Panel.lua`, `tests/test_schema.lua` and `tests/test_slash.lua` left the band, `modules/BrowserTable.lua` and `tests/test_browser.lua` were peeled, and `tests/perf.lua` now writes the `perf.json` this bundle carries.
