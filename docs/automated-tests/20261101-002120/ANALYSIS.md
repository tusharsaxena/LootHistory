# Analysis — 20261101-002120

- **Addon:** LootHistory 1.5.0
- **Verdict:** green
- **Commit:** `ad76bb7` (feat/2026-10-31-findings-remediation), clean
- **Previous run:** `20261031-214112` (`d902af3`, feat/2026-10-31-findings-remediation, clean; labelled `findings-remediation`)

## Headline

Green on a clean tree at `ad76bb7`, labelled `v1.84.0-adoption`: lint 0/0, 1841 passed with 1 skip and 0 failed, 4 perf scenarios, 0 functions above CCN 15, nothing over the 1500 cap and no blind or crashed files ([`manifest.json`](manifest.json)). The one real movement is the case count, 1861 → 1842, and it is deliberate: 22 cases left with the Insights helpers that `LibKa0s-Charts-1.0` replaced, and 3 arrived. The tests suite's recorded time rose to 1575213 ms from 27391 ms; no case or count points to the suite itself, and that is read below. Nothing here needs action before a merge.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261031-214112 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 159 files | [`lint.txt`](lint.txt) | none |
| tests | pass | 1841 passed, 1 skipped, 0 failed, 1842 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | 1861 → 1842 total; skips held at 1 |
| perf | pass | 4 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | bytes and scans unchanged; timings up |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | see below |

| Metric | Value |
|---|---|
| Total NLOC | 42479 (was 42868) |
| Functions | 6166 (was 6212) |
| Avg NLOC / function | 6.7 (was 6.7) |
| Avg CCN | 2.3 (was 2.3) |
| Max CCN | 15 (was 15) |
| Avg tokens / function | 60.6 (was 60.9) |
| Warnings (CCN > 15) | 0 (was 0) |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 10 (was 10) |
| Files over the 1500 cap | 0 (was 0) |
| Blind files (parity mismatch) | 0 (was 0) |
| Crashed files (lizard raised) | 0 (was 0) |

**complexity.** A clean pass on the sighted gate (`blindFiles` 0, `crashedFiles` 0), so all 6166 functions were measured. The footer reads "No thresholds exceeded" for CCN, length, NLOC and parameter count ([`complexity.txt`](complexity.txt)). The totals fell because chart code left the addon for the library, and the averages held, so the addon got smaller and no denser. Max CCN still sits exactly at the limit, so a function at 15 has no margin.

**tests.** The one skip is unchanged: the kit's `diagnostics contract: an addon that opts out ...` case ([`tests.txt`](tests.txt)). This addon keeps the default (`Kit.diagnostics.enablesLogging` is not false), so its report turns logging on. It is a sanctioned `Kit.skip` with its reason, counted in the total and not in `passed`.

**tests duration.** `durationMs` for the suite is 1575213 against 27391 at the previous run ([`manifest.json`](manifest.json)). This is a wall-clock reading from a run that shared the machine with other repositories' batteries, and the bundle does not separate waiting from working. The same run's `perf` timings roughly doubled with identical bytes and scans, which also points at load. No failure, skip or timeout is recorded, and the figure says nothing about the addon's tests. It is recorded as read, not as a regression.

**perf.** A pass. All ten checks pass: `reconcileCleanBags` stands at 118120.0 B/iter against a ceiling of 124000, with scans pinned at 1, and the other three scenarios allocate nothing and scan nothing ([`perf.txt`](perf.txt), [`perf.json`](perf.json)). The zero-overhead check holds at 0.0 B/iter bracketed and bare. Every byte and scan figure matches the previous run, so the library move added no allocation to these paths. These scenarios do not exercise the Insights tab. The timings are for orientation within a run and are not comparable across runs under different load.

## What moved

- **lint:** did not move: 159 files, 0/0 ([`lint.txt`](lint.txt)).
- **tests:** 1861 → 1842 cases ([`test-cases.md`](test-cases.md)). Removed 22 from `test_analytics.lua` (71 → 49): `Analytics._charStackSegments` 9, `Analytics._truncate` 6, `Analytics._fitFontSize` 4, `Analytics._tipText` 3. None of those four names remains in the addon's source. Added 3: two in `test_analytics_layout.lua` (9 → 11), for hover routing through Compat and for the tab's refusal without `LibKa0s-Charts-1.0`, and one in `test_libka0s.lua` (42 → 43), pinning the v1.84.0 vendored minors and kit revision. The passed figure moved 1860 → 1841 and failures held at 0.
- **perf:** scenarios held at 4; bytes and scans did not move. Timings rose: `lootDroppedBracketed` 0.00362 → 0.00700 ms/iter, `lootDroppedBare` 0.00359 → 0.00729, `combatBagUpdate` 0.00054 → 0.00110, `reconcileCleanBags` 0.21875 → 0.38744. Read with the duration paragraph above.
- **complexity:** NLOC 42868 → 42479 and functions 6212 → 6166; average tokens 60.9 → 60.6. Avg NLOC 6.7, Avg CCN 2.3, Max CCN 15 and 0 warnings all held.
- **band files:** held at 10, none entering or leaving. Grown: `tests/test_libka0s.lua` 1054 → 1103 and `tests/test_panel.lua` 1083 → 1087 (`RESULTS.md`).

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
| 1000–1500 (on notice) | `modules/Browser.lua` | 1386 | Carried: Peeled (`LH-18`, 2026-10-07) |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1127 | Carried: Peeled (`LH-08`, 2026-10-07) |
| 1000–1500 (on notice) | `settings/Schema.lua` | 1252 | Carried: Accepted (2026-10-07) |
| 1000–1500 (on notice) | `tests/test_browser.lua` | 1018 | Carried: Peel next (2026-10-07) |
| 1000–1500 (on notice) | `tests/test_browsertable.lua` | 1395 | Carried: Accepted (2026-10-07) |
| 1000–1500 (on notice) | `tests/test_database.lua` | 1252 | Carried: Accepted (2026-10-07) |
| 1000–1500 (on notice) | `tests/test_libka0s.lua` | 1103 | Carried: Accepted (2026-10-31) |
| 1000–1500 (on notice) | `tests/test_panel.lua` | 1087 | Carried: Accepted (2026-10-31) |

The runner carried every disposition, so none is owed, and nothing newly crossed a threshold. The full wording is in `RESULTS.md`. No *Accepted* entry has reached three consecutive release runs: the oldest date from 2026-10-07, and one release run has followed.

## Actions

None.
