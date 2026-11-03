# Analysis — 20261104-042200

- **Addon:** LootHistory 1.5.0
- **Verdict:** green
- **Commit:** 0b42d72 (feat/2026-11-01-full-skinning)
- **Previous run:** 20261101-202413 (`ed7a0d5`, 30 commits behind this one)

## Headline

Green on all four suites at `0b42d72`, the round 6 head of the full skinning run (preview through
`spec.preview`, the Master controls Sim mode checkbox, the LibKa0s v1.85.0 re-vendors, the README
rename). The suite grew by 21 cases (1955 to 1976) with no failure, lint stayed 0/0 over two more
files, and complexity stayed at max CCN 15 with no warned function and no blind or crashed file.
Nothing to act on.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261101-202413 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 162 files | [`lint.txt`](lint.txt) | files 160 → 162; still 0/0 |
| tests | pass | 1975 passed, 1 skipped, 0 failed, 1976 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | total 1955 → 1976 (+21); skip count unchanged at 1 |
| perf | pass | 4 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | same 4 scenarios; scans and bytes per iteration unchanged, ms/iter higher (see below) |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | +479 NLOC, +73 functions; averages flat |

| Metric | Value |
|---|---|
| Total NLOC | 43403 |
| Functions | 6363 |
| Avg NLOC / function | 6.6 |
| Avg CCN | 2.3 |
| Max CCN | 15 |
| Avg tokens / function | 60.1 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 10 |
| Files over the 1500 cap | 0 |
| Blind files (parity mismatch) | 0 |
| Crashed files (lizard raised) | 0 |

All values are from [`manifest.json`](manifest.json) `suites.complexity`. The run is sighted
(`blindFiles` 0) and nothing crashed (`crashedFiles` 0).

**tests: the one skip.** `diagnostics contract: an addon that opts out lands the report and leaves
logging off` reports `Kit.skip` because this addon keeps the default (`Kit.diagnostics.enablesLogging`
is not false), so the opt-out branch does not apply; the case above it in [`tests.txt`](tests.txt)
holds the default branch. It is a standing, by-design skip, the same one the previous run carried,
and it is counted in neither passed nor failed.

**perf.** Every scenario is the same workload as the previous run: `scans/iter` and `bytes/iter`
are identical (0/0 for the three event scenarios, 1 scan and 118120 bytes for `reconcileCleanBags`,
[`perf.json`](perf.json)). The ms/iter figures rose on all four at once (for example
`reconcileCleanBags` 0.21 → 0.26 ms, computed from the two runs' `perf.json` `totalMs`/`calls`).
A uniform rise across untouched scenarios with unchanged scan and allocation counts reads as host
load, not a code change: the runner waited for a slot because all eight bounded slots were in use
by other repos' batteries at the time. It is recorded, not thresholded.

## What moved

- **lint:** 160 → 162 files, still 0 warnings / 0 errors. The two new files are
  `tests/test_launcher_skin_entry.lua` and `tests/test_sim_checkbox.lua`; the `.luacheckrc` exclusions are unchanged.
- **tests:** +21 net. New cases cover the skin preview through `spec.preview` (the History window
  the preview opens is hidden again at every close path), the Master controls Sim mode checkbox and
  its shared NS pair with the launcher, the v14 → v15 font migration, the launcher's
  `openSkinPicker`, and the R4/R5 skin-chrome pins. The old `Skin picker: the eye opens the History
  window in test mode` and the two `skin switch: the window's divider changes` cases were replaced.
  Diffed from the two bundles' `tests.txt`.
- **perf:** same four scenarios; see above.
- **complexity:** NLOC 42924 → 43403 and functions 6290 → 6363, with avg NLOC 6.6, avg CCN 2.3 and
  max CCN 15 unchanged and avg tokens 60.2 → 60.1. The addon grew without getting denser. The band
  holds the same 10 files, none over the cap.

## Complexity watch list

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

None.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `core/Compat.lua` | 1001 | Carried forward: accepted, re-check at 1200 |
| 1000–1500 (on notice) | `core/Database.lua` | 1308 | Carried forward: accepted, re-check at 1400 |
| 1000–1500 (on notice) | `modules/Browser.lua` | 1378 | Carried forward: tracked deviation (`docs/ARCHITECTURE.md`), re-check at 1400 |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1126 | Carried forward: peeled, re-check at 1400 |
| 1000–1500 (on notice) | `settings/Schema.lua` | 1268 | Carried forward: accepted, re-check at 1300 |
| 1000–1500 (on notice) | `tests/test_browser.lua` | 1018 | Carried forward: peeled, re-check at 1300 |
| 1000–1500 (on notice) | `tests/test_browsertable.lua` | 1395 | Carried forward: accepted, re-check at 1450 |
| 1000–1500 (on notice) | `tests/test_database.lua` | 1252 | Carried forward: accepted, re-check at 1300 |
| 1000–1500 (on notice) | `tests/test_libka0s.lua` | 1165 | Carried forward: accepted, re-check at 1300 |
| 1000–1500 (on notice) | `tests/test_panel.lua` | 1087 | Carried forward: accepted, re-check at 1300 |

The full dispositions are in `../RESULTS.md`. No entry is new, so no Disposition cell was blank.
`modules/Browser.lua` (1378) and `tests/test_browsertable.lua` (1395) are the nearest to their
re-check lines, at 22 and 55 lines short. `settings/Schema.lua` sits 32 lines under its 1300 re-check
after the Sim mode row.

## Actions

None.
