# Analysis — 20261101-202413

- **Addon:** LootHistory 1.5.0
- **Verdict:** green
- **Commit:** `ed7a0d5` (feat/2026-11-01-full-skinning), clean
- **Previous run:** `20261101-143701` (`29746ad`, feat/2026-11-01-full-skinning, clean; labelled `full skinning FS-LH`)

## Headline

Green on a clean tree at `ed7a0d5`, labelled `re-cut v1.85.0 and the kit skin gates`: lint 0/0, 1954 passed with 1 skip and 0 failed, 4 perf scenarios, 0 functions above CCN 15, nothing over the 1500 cap and no blind or crashed files ([`manifest.json`](manifest.json)). This run measures the re-cut LibKa0s v1.85.0, kit revision 50, and this addon's adoption of the typed-value gate and the skin-switch test.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261101-143701 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 160 files | [`lint.txt`](lint.txt) | 159 → 160 files |
| tests | pass | 1954 passed, 1 skipped, 0 failed, 1955 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | 1846 → 1955 cases |
| perf | pass | 4 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | Bytes and scans unchanged |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | NLOC 42624 → 42924, functions 6183 → 6290 |

| Metric | Value |
|---|---|
| Total NLOC | 42924 |
| Functions | 6290 |
| Avg NLOC / function | 6.6 |
| Avg CCN | 2.3 |
| Max CCN | 15 |
| Avg tokens / function | 60.2 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 10 |
| Files over the 1500 cap | 0 |
| Blind files (parity mismatch) | 0 |
| Crashed files (lizard raised) | 0 |

The tests suite is a pass with one standing skip, not a clean 1955: the same `diagnostics contract` case as the previous run, because this addon keeps the default ([`tests.txt`](tests.txt)).

## What moved

- **lint:** 159 → 160 files: `tests/skin_surfaces.lua` and `tests/test_skin_surfaces.lua` in, `tests/test_skin_literals.lua` out; 0/0 ([`lint.txt`](lint.txt)).
- **tests:** 1846 → 1955, nearly all the switch test's cases, one or two per declared surface in `tests/skin_surfaces.lua`. The kit's three typed-value cases replace the addon's own three. The suite's own time rose from 56419 ms to 133528 ms, because every flip repaints what stands ([`manifest.json`](manifest.json), and the previous bundle's).
- **perf:** scenarios held at 4; bytes and scans did not move, `reconcileCleanBags` at 118120 B/iter under its ceiling of 124000 ([`perf.txt`](perf.txt)). No perf path was touched.
- **complexity:** NLOC 42624 → 42924 and functions 6183 → 6290, mostly `tests/skin_surfaces.lua`'s one-line builds, which is also why the averages eased: Avg NLOC 6.7 → 6.6 and average tokens 60.7 → 60.2, with Avg CCN 2.3 and Max CCN 15 held ([`manifest.json`](manifest.json)).
- **band files:** held at 10 (`RESULTS.md`).

## Complexity watch list

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

None. `lizard` reports 0 warnings over the sighted shadow ([`complexity.txt`](complexity.txt)).

### Files by `layout-§1` band

Unchanged from the previous run's table, dispositions carried by the runner; the rows and full wording are in `RESULTS.md`. Nothing newly crossed a threshold, and no file has reached a recorded re-check line.

## Actions

None here. No smoke check's expected result moved, so the owed in-client checks on `docs/smoke-tests.md` stand as they were.
