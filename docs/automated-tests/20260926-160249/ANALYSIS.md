# Analysis — 20260926-160249

- **Addon:** LootHistory 1.3.0
- **Verdict:** green
- **Commit:** `3ce80a7` (master), clean
- **Previous run:** `20260924-121347` (`2f232f0`, clean)

## Headline

Green, on a clean `master` at `3ce80a7`, 21 commits past the previous bundle (the diagnostics rollout on LibKa0s v1.60.0 and the NavRail re-vendor to v1.61.0). Tests grew 928 → 961 and lint scope 67 → 70 files, both still clean. Complexity grew in total but not in density: the averages did not move, no function is above CCN 15, and no file moved band. Nothing to act on. `perf` is the permanent, ratified `performance-§12` skip, not a pass.

## Suites

| Suite | Status | Result | Artifact | Moved since 20260924-121347 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 70 files | [`lint.txt`](lint.txt) | files 67 → 70; still 0/0 |
| tests | pass | 961 passed, 0 skipped, 0 failed, 961 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | 928 → 961 (+33) |
| perf | skip | 0 scenarios: `performance-§12` no-combat-path exemption (ratified; `docs/ARCHITECTURE.md` → Documented deviations) | none; the suite did not run | unchanged (skip) |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | NLOC +864, functions +124, averages flat |

**Complexity is reported in full.** Every value is from [`manifest.json`](manifest.json) `suites.complexity` and the footer of [`complexity.txt`](complexity.txt):

| Metric | Value |
|---|---|
| Total NLOC | 18443 (was 17579) |
| Functions | 2519 (was 2395) |
| Avg NLOC / function | 6.3 (was 6.3) |
| Avg CCN | 2.1 (was 2.1) |
| Max CCN | 15 (was 15) |
| Avg tokens / function | 50.9 |
| Warnings (CCN > 15) | 0 (was 0) |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 6 (was 6) |
| Files over the 1500 cap | 0 (was 0) |

**perf (skip).** The runner read the ratified `performance-§12` no-combat-path exemption from `docs/ARCHITECTURE.md`'s `## Documented deviations` register ([`manifest.json`](manifest.json) `suites.perf.skipReason`). This run says nothing about runtime cost. That is a standing fact about the addon, not a tooling gap. At the release gate this suite is **NOT EVALUATED**, not passed.

## What moved

- **tests:** 928 → 961 cases (+33), all passing, no skips ([`tests.txt`](tests.txt)). The growth matches the new and extended files in [`complexity.txt`](complexity.txt): `tests/test_diagnostics.lua` (new, 256 NLOC), `tests/test_launcher.lua` (293 → 474 NLOC), `tests/mock_menu.lua` (new, 70 NLOC), and smaller additions to `test_disabled`, `test_doc_structure`, `test_debuglog` and `test_slash_degraded`.
- **lint:** 67 → 70 files, still 0/0 ([`lint.txt`](lint.txt)). The three new files are `modules/Diagnostics.lua`, `tests/test_diagnostics.lua` and `tests/mock_menu.lua`. The `.luacheckrc` exclusions (`libs/`, `docs/audits/`, `docs/reviews/`, `_dev/`, `tests/_kit/`) are unchanged.
- **complexity:** NLOC 17579 → 18443 (+864) and functions 2395 → 2519 (+124). Summed per file from both bundles' `complexity.txt`, the +864 is entirely `modules/Diagnostics.lua` (new, 239), the test files above, and small growth in `core/DebugLogSetup.lua` (+14), `core/LauncherSetup.lua` (+9), `settings/Schema.lua` (+3), `settings/OptionsSetup.lua` (+1) and `tests/run.lua` (+9). Avg NLOC/function (6.3), avg CCN (2.1) and max CCN (15) did not move, so the addon grew without getting denser. Seven functions still sit at exactly CCN 15, the same seven as the previous run: `Compat.ScanBound` (`core/Compat.lua@241`), `Attribution` (`modules/Attribution.lua@193`), `AuctionPrice` (`modules/AuctionPrice.lua@171`), three in `modules/BrowserTable.lua` (`@659-707`, `@971-988`, `@1082-1125`) and `E` (`modules/Export.lua@39-159`). None of them is warned.
- **band files:** the same six files, with the same LOC as the previous run's watch list. `tests/test_panel.lua` (974) and `settings/Schema.lua` (972) are the next two below the band.
- **perf:** unchanged. It is the ratified skip.

Two earlier bundles, `20260807-110451` and `20260825-103428`, have no `ANALYSIS.md`. They are not backfilled (`automated-tests-§5`).

## Complexity watch list

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

None. `lizard` reports 0 warnings ([`complexity.txt`](complexity.txt): "No thresholds exceeded").

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Browser.lua` | 1289 | carried forward: accepted, `LH-37` |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1227 | carried forward: accepted |
| 1000–1500 (on notice) | `modules/Analytics.lua` | 1200 | carried forward: already tracked as #32 |
| 1000–1500 (on notice) | `tests/test_schema.lua` | 1199 | carried forward: accepted (2026-09-24) |
| 1000–1500 (on notice) | `settings/Panel.lua` | 1107 | carried forward: accepted |
| 1000–1500 (on notice) | `tests/test_slash.lua` | 1094 | carried forward: accepted (2026-09-24) |

No entry is new, so the runner carried every disposition forward and left no blank cell in `RESULTS.md`. **Shelf life:** only one runner-stamped release run exists (`20260910-234511`, `--release 1.3.0`), so no *Accepted* entry has crossed three consecutive release runs yet.

## Actions

None.
