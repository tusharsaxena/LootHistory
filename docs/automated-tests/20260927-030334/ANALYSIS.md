# Analysis — 20260927-030334

- **Addon:** LootHistory 1.3.0 (release run for **1.4.0**, `--release 1.4.0`)
- **Verdict:** green
- **Commit:** `8e60c1f` (master), clean
- **Previous run:** `20260926-193103` (`93e879d`, clean)

## Headline

Green, on a clean `master` at `8e60c1f`, and this is the release run the 1.4.0 version bump was gated on: lint, tests and complexity pass, zero functions above CCN 15, and `perf` is the ratified `performance-§12` no-combat-path skip, which the release gate's one narrow exception (`automated-tests-§3`: the addon ships no `tests/perf.lua`) lets through, stated in the release notes rather than read as measured. Every figure is identical to the previous run. The seven commits since it are README and docs edits plus comment-only citation fixes in five `.lua` files. Nothing to act on.

## Suites

| Suite | Status | Result | Artifact | Moved since 20260926-193103 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 70 files | [`lint.txt`](lint.txt) | unchanged (70 files, 0/0) |
| tests | pass | 961 passed, 0 skipped, 0 failed, 961 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | unchanged (961) |
| perf | skip | 0 scenarios: `performance-§12` no-combat-path exemption (ratified; `docs/ARCHITECTURE.md` → Documented deviations) | none; the suite did not run | unchanged (skip) |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | unchanged |

**Complexity is reported in full.** Every value is from [`manifest.json`](manifest.json) `suites.complexity` and the footer of [`complexity.txt`](complexity.txt):

| Metric | Value |
|---|---|
| Total NLOC | 18447 (was 18447) |
| Functions | 2519 (was 2519) |
| Avg NLOC / function | 6.3 (was 6.3) |
| Avg CCN | 2.1 (was 2.1) |
| Max CCN | 15 (was 15) |
| Avg tokens / function | 50.9 (was 50.9) |
| Warnings (CCN > 15) | 0 (was 0) |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 6 (was 6) |
| Files over the 1500 cap | 0 (was 0) |

**perf (skip).** The runner read the ratified `performance-§12` no-combat-path exemption from `docs/ARCHITECTURE.md`'s `## Documented deviations` register ([`manifest.json`](manifest.json) `suites.perf.skipReason`), and the addon ships no `tests/perf.lua`. This run says nothing about runtime cost; that is a standing fact about the addon, not a tooling gap. At the release gate `automated-tests-§3` covers this skip under its one narrow exception (no `tests/perf.lua`, including the `performance-§12` case), so the gate passed on three measured suites, and the 1.4.0 row in the README's `## Version History` says so in one sentence that names the exemption.

## Release gate (1.4.0)

Evaluated from [`manifest.json`](manifest.json):

| Gate | Result | Detail |
|---|---|---|
| Lint | PASS | 0 warnings / 0 errors in 70 files |
| Tests | PASS | 961 passed, 0 failed of 961 |
| Perf | PASS (exception) | skipped, not measured: ships no `tests/perf.lua`, ratified `performance-§12` exemption |
| Complexity | PASS | ran; lizard 1.24.0 |
| CCN <= 15 | PASS | 0 functions over 15, max CCN 15 |

## What moved

- **tests:** 961 cases, unchanged, all passing, no skips ([`tests.txt`](tests.txt)). The count is now flat across the last three runs, which `RESULTS.md`'s generated `## Test suite` section flags; the commits since the previous run added no behavior, so no case was owed.
- **lint:** 70 files, still 0/0 ([`lint.txt`](lint.txt)). The `.luacheckrc` exclusions are unchanged.
- **complexity:** every footer field unchanged ([`complexity.txt`](complexity.txt)). The five `.lua` files touched since the previous run (`settings/Panel.lua`, `tests/panel_support.lua`, `tests/test_envsetup.lua`, `tests/test_panel_filters.lua`, `tests/test_surface_parity.lua`) changed comment lines only, 12 in and 12 out, so neither NLOC nor LOC moved. The same seven functions sit at exactly CCN 15, none warned.
- **band files:** the same six files at the same LOC.
- **perf:** unchanged; the ratified skip.

## Complexity watch list

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

None. `lizard` reports 0 warnings ([`complexity.txt`](complexity.txt)), which the release gate requires.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Browser.lua` | 1289 | carried forward: accepted, `LH-37` |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1227 | carried forward: accepted |
| 1000–1500 (on notice) | `modules/Analytics.lua` | 1200 | carried forward: already tracked as #32 |
| 1000–1500 (on notice) | `tests/test_schema.lua` | 1199 | carried forward: accepted (2026-09-24) |
| 1000–1500 (on notice) | `settings/Panel.lua` | 1107 | carried forward: accepted |
| 1000–1500 (on notice) | `tests/test_slash.lua` | 1094 | carried forward: accepted (2026-09-24) |

Nothing entered or left the band, so no cell was blank. The carried Dispositions in `RESULTS.md` were refreshed to cite this run's `complexity.txt`, with every ruling kept because no figure moved. **Shelf life:** this is the second runner-stamped release run (after `20260910-234511`, `--release 1.3.0`), so no *Accepted* entry has yet crossed three consecutive release runs. The 1.5.0 release run is the third; any band entry still *Accepted* then is owed a fix or a tracked deviation ID (anti-pattern #53).

## Actions

None.
