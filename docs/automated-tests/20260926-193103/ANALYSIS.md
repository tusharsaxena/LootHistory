# Analysis — 20260926-193103

- **Addon:** LootHistory 1.3.0
- **Verdict:** green
- **Commit:** `93e879d` (feat/2026-09-26-automated-tests-sweep), clean
- **Previous run:** `20260926-160249` (`3ce80a7`, clean)

## Headline

Green, on a clean tree at `93e879d`, two commits past the previous bundle: that bundle's own record commit (`LH-ATS-00`) and the LibKa0s v1.62.0 re-vendor (`LH-ATS-RV`, kit revision 27 → 31). Tests, lint scope, the complexity averages, max CCN and the band table are all unchanged; the only moved figure is NLOC +4, all of it in `tests/test_libka0s.lua`. Nothing to act on. `perf` is the permanent, ratified `performance-§12` skip, not a pass.

## Suites

| Suite | Status | Result | Artifact | Moved since 20260926-160249 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 70 files | [`lint.txt`](lint.txt) | unchanged (70 files, 0/0) |
| tests | pass | 961 passed, 0 skipped, 0 failed, 961 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | unchanged (961) |
| perf | skip | 0 scenarios: `performance-§12` no-combat-path exemption (ratified; `docs/ARCHITECTURE.md` → Documented deviations) | none; the suite did not run | unchanged (skip) |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | NLOC +4, functions flat, averages flat |

**Complexity is reported in full.** Every value is from [`manifest.json`](manifest.json) `suites.complexity` and the footer of [`complexity.txt`](complexity.txt):

| Metric | Value |
|---|---|
| Total NLOC | 18447 (was 18443) |
| Functions | 2519 (was 2519) |
| Avg NLOC / function | 6.3 (was 6.3) |
| Avg CCN | 2.1 (was 2.1) |
| Max CCN | 15 (was 15) |
| Avg tokens / function | 50.9 (was 50.9) |
| Warnings (CCN > 15) | 0 (was 0) |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 6 (was 6) |
| Files over the 1500 cap | 0 (was 0) |

**perf (skip).** The runner read the ratified `performance-§12` no-combat-path exemption from `docs/ARCHITECTURE.md`'s `## Documented deviations` register ([`manifest.json`](manifest.json) `suites.perf.skipReason`). This run says nothing about runtime cost. That is a standing fact about the addon, not a tooling gap. At the release gate this suite is **NOT EVALUATED**, not passed.

## What moved

- **tests:** 961 cases, unchanged, all passing, no skips ([`tests.txt`](tests.txt)). The re-vendor added four entries to `tests/test_libka0s.lua`'s explicit file list inside existing cases, so the case count did not move.
- **lint:** 70 files, still 0/0 ([`lint.txt`](lint.txt)). The `.luacheckrc` exclusions (`libs/`, `docs/audits/`, `docs/reviews/`, `_dev/`, `tests/_kit/`) are unchanged, so the re-vendored `libs/` and `tests/_kit/` bytes are outside this count.
- **complexity:** NLOC 18443 → 18447 (+4); functions 2519 unchanged. The +4 is `tests/test_libka0s.lua`, 308 → 312 NLOC over the same 29 functions (both bundles' `complexity.txt` file tables): the four new LibKa0s v1.62.0 files in its list. Averages and max CCN did not move. The same seven functions sit at exactly CCN 15 and none is warned: `Compat.ScanBound` (`core/Compat.lua@241-261`), `Attribution` (`modules/Attribution.lua@193-216`), `AuctionPrice` (`modules/AuctionPrice.lua@171-195`), three in `modules/BrowserTable.lua` (`@659-707`, `@971-988`, `@1082-1125`) and `E` (`modules/Export.lua@39-159`).
- **band files:** the same six files at the same LOC. `tests/test_panel.lua` (974) and `settings/Schema.lua` (972) are still the next two below the band.
- **perf:** unchanged. It is the ratified skip.
- **runner:** kit revision 31 now writes `None.` under the empty functions table in `RESULTS.md` (ATS-20); that part of the generated half changed because of the kit, not the addon.

## Complexity watch list

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

None. `lizard` reports 0 warnings ([`complexity.txt`](complexity.txt)).

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Browser.lua` | 1289 | carried forward: accepted, `LH-37` |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1227 | carried forward: accepted |
| 1000–1500 (on notice) | `modules/Analytics.lua` | 1200 | carried forward: already tracked as #32 |
| 1000–1500 (on notice) | `tests/test_schema.lua` | 1199 | carried forward: accepted (2026-09-24) |
| 1000–1500 (on notice) | `settings/Panel.lua` | 1107 | carried forward: accepted |
| 1000–1500 (on notice) | `tests/test_slash.lua` | 1094 | carried forward: accepted (2026-09-24) |

Nothing entered or left the band, so no cell was blank. Each carried Disposition in `RESULTS.md` still cited `20260924-121347`'s `complexity.txt`; those cells were refreshed to cite this run's figures and evidence, with every ruling kept because no figure moved. **Shelf life:** only one runner-stamped release run exists (`20260910-234511`, `--release 1.3.0`), so no *Accepted* entry has crossed three consecutive release runs.

## Actions

None.
