# Analysis — 20260910-234511

- **Addon:** LootHistory 1.2.0 → 1.3.0
- **Verdict:** green
- **Commit:** 4929b233e99a (master), clean
- **Previous run:** [`20260908-181338`](../20260908-181338/)

## Headline

The release run for **1.3.0**. Lint, tests and complexity are green with zero functions above CCN 15; **perf did not run** — this addon ships no `tests/perf.lua`, so the gate covered three suites, not four. Six new test cases and 222 more NLOC. One new file entered the 1000–1500 band and is ruled on below.

## Suites

| Suite | Status | Result | Artifact | Moved since `20260908-181338` |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 59 files | [`lint.txt`](lint.txt) | see below |
| tests | pass | 720 passed, 0 skipped, 0 failed, 720 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | see below |
| perf | skip | not measured — no `tests/perf.lua` in this addon | — | not measured in either run |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | see below |

| Metric | Value |
|---|---|
| Total NLOC | 13892 |
| Functions | 1810 |
| Avg NLOC / function | 6.5 |
| Avg CCN | 2.2 |
| Max CCN | 15 |
| Avg tokens / function | 52.7 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.0 / 0.0 |
| Files in the 1000–1500 band | 5 |
| Files over the 1500 cap | 0 |

**perf is the one suite that is not a clean pass, and it is a skip rather than a failure.** `manifest.json` records the reason verbatim: *"no tests/perf.lua — this addon ships no offline scenarios"*. Nothing ran, so nothing was measured — this is a pre-existing condition of the addon, not a regression in this run, and it is stated in the release notes as well as here. The release gate's perf condition is satisfied by the no-scenarios exception, which means this tag rests on three measured suites.

## What moved

- **lint** — 59 files, up one from 58. Still 0 warnings / 0 errors.
- **tests** — 720 passed, up 6 from 714. No skips, no failures.
- **perf** — skipped in both runs, same reason: no `tests/perf.lua` exists. Not measured, not a pass.
- **complexity** — NLOC 13670 → 13892 (+222) over 1803 → 1810 functions (+7). Avg NLOC flat at 6.5, avg CCN flat at 2.2, avg tokens 52.5 → 52.7. Max CCN 15, zero warnings in both. Band files 4 → 5: `tests/test_panel.lua` crossed at 1030.

## Complexity watch list

Both tables are maintained in [`RESULTS.md`](../RESULTS.md), which the runner regenerates whole on every run; the **Disposition** column there is the authored half and is current as of this run.

### Functions `lizard` warned on

None. Zero functions above CCN 15 is what the release gate required, and it is what this run measured — max CCN 15.

### Files by `layout-§1` band

5 file(s) in the 1000–1500 on-notice band, 0 over the 1500 cap. Each carries a disposition in [`RESULTS.md`](../RESULTS.md#files-by-layout-1-band). The band is not part of the release gate.

## Actions

1. `tests/test_panel.lua` newly entered the band (998 → 1030 raw lines) and is ruled **Accepted** in `RESULTS.md`, paired with `settings/Panel.lua` which crossed alongside it. Neither is a peel candidate yet.
2. `modules/Analytics.lua` is still marked **peel next** and has been unblocked since [`20260804-233322`](../20260804-233322/) without the peel starting. This is its sixth run in that state; it is owed either the peel or a tracked deviation ID.
