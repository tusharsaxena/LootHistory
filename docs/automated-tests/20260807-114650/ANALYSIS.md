# Analysis — 20260807-114650

- **Addon:** LootHistory 1.2.0
- **Verdict:** green
- **Commit:** e55fda34f34baca991b4471e68dcbe319f38bcf2 (master), clean
- **Previous run:** [`20260807-110451`](../20260807-110451/)

## Headline

Green, and every figure is flat against the previous run — 0/0 lint over 23 files, 594 of 594 cases
passing with none skipped, and complexity unchanged at 11479 NLOC across 1531 functions with no
function above CCN 15. Nothing crossed a threshold and nothing needs acting on. What this run
carries that the numbers cannot is the end-to-end proof of testkit **revision 10**'s `normalize_eol`
pass: all five artifacts this run wrote land with the CRLF the repo's `.gitattributes` pins,
verified by byte count rather than by `file(1)`.

## Suites

| Suite | Status | Result | Artifact | Moved since 20260807-110451 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 23 files | [`lint.txt`](lint.txt) | No change — identical scope and result |
| tests | pass | 594 passed, 0 skipped, 0 failed, 594 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | No change |
| perf | skip | 0 scenarios — no `tests/perf.lua` | *(none — nothing ran)* | No change; a standing skip, not a transient one |
| complexity | pass | 0 warnings, max CCN 15 — see below | [`complexity.txt`](complexity.txt) | No change in any field |

**Complexity in full**, totals and averages both, every field from
[`manifest.json`](manifest.json)'s `suites.complexity` and [`complexity.txt`](complexity.txt)'s
footer:

| Metric | Value |
|---|---|
| Total NLOC | 11479 |
| Functions | 1531 |
| Avg NLOC / function | 6.5 |
| Avg CCN | 2.2 |
| Max CCN | 15 |
| Avg tokens / function | 53.9 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 3 |
| Files over the 1500 cap | 0 |

Totals and averages moved together, which is to say neither moved. The addon did not grow between
these two runs and did not get denser; 11479 NLOC over 1531 functions is the same reading
`20260807-110451` and `20260807-022940` took. Only a rising **average** would have been a complexity
signal, and there is none here.

**`perf` is the one suite that is not a clean pass, and it is a skip rather than a failure.** The
runner records `skipReason` as *"no tests/perf.lua — this addon ships no offline scenarios"*, which
is `automated-tests-§3`'s **first** sanctioned reason. The addon's actual position is the **second**
and more informative one: a ratified `performance-§12` no-combat-path exemption, carried as a
register row in [`../../ARCHITECTURE.md`](../../ARCHITECTURE.md) `## Documented deviations` against
criteria (a) and (c), with the committed whole-repo sweep in
[`../../performance.md`](../../performance.md). The runner detects absence and cannot read a
register, so the bundle records reason (1) and the exemption is stated here and in `RESULTS.md`.
Either way this run is **silent about runtime cost**, and `performance-§9`'s zero-overhead evidence
does not exist for this addon. At the release gate the skip is **NOT EVALUATED**, never passed.

## What moved

- **lint** — nothing. 0 warnings / 0 errors over 23 files, the sixth consecutive run at that reading.
- **tests** — nothing. 594 passed / 0 skipped / 594 total, flat since `20260807-022940`. Worth saying
  explicitly: `0 skipped` is a real figure from [`tests.txt`](tests.txt)'s footer, not an absent one
  — every case ran, including the vendored-payload gate cases that skip when the sibling `LibKa0s`
  checkout is missing.
- **perf** — nothing, and nothing can move here until the addon grows a combat path or the exemption
  is withdrawn.
- **complexity** — nothing, in any of the ten fields above. Membership of the 1000–1500 band is the
  same three files at the same line counts: `modules/Browser.lua` 1366, `modules/Analytics.lua` 1187,
  `modules/BrowserTable.lua` 1097.
- **Line endings** — not a suite, but what this run was for. First run whose artifacts were written
  by testkit revision 10's `normalize_eol` pass and verified as such: `complexity.txt` 1590 CR /
  1590 LF, `tests.txt` 596 / 596, `test-cases.md` 687 / 687, `lint.txt` 25 / 25, `manifest.json`
  19 / 19. Equal counts is the pass condition in a CRLF-pinned repo. These files had never been
  checked out by git when measured, so this reads what the **runner** wrote rather than what a smudge
  filter produced.

## Complexity watch list

### Functions `lizard` warned on

**None.** `"warnings": 0` with `"maxCcn": 15` in [`manifest.json`](manifest.json), and
[`complexity.txt`](complexity.txt)'s footer states *"No thresholds exceeded"* outright. Six functions
sit exactly on the CCN 15 cap without crossing it, unchanged in membership since `20260804-233322`,
and all six are dense **defaulting/guarding** rather than tangled control flow — `lizard` scores
every `and`/`or` short-circuit as a decision, so a run of `t.k = rec.k or D.k` lines reads high with
no branching to show for it (`performance-§10`).

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Browser.lua` | 1366 | **Accepted, own disposition — `LH-37`.** Window shell, filter bar and dropdown widget kit; the seam if it needs peeling is the widget kit into a sibling file. Flat this run. |
| 1000–1500 (on notice) | `modules/Analytics.lua` | 1187 | **Peel next — unblocked since `20260804-233322`, still not started.** Flat this run, the fourth consecutive run without movement. Split renderers from the formatting/segmenting helpers. Nothing tracks it. |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1097 | **Accepted.** Just over the line, already three clean layers. Flat. |
| > 1500 (over cap) | — | — | **None.** `"overCapFiles": 0`. |

Nothing newly crossed a band in this run.

## Actions

1. **`modules/Analytics.lua` — peel it, or file it.** Its disposition has read *"peel next"* since
   `20260804-233322` across four runs without a line moving, and no deviation ID tracks it. This is
   not a `layout-§1` breach — the 1000–1500 band is the compliant, on-notice state — so it does not
   belong in the `## Documented deviations` register. It belongs in the issue store, or it should
   stop claiming to be next. **New here:** it has no owner in the addon's own tracking.
2. **The `perf` skip remains the addon's largest blind spot.** `Database:QueryList`'s
   compiled-filter rewrite is now four runs old and no bundle has ever put a number on it. The
   exemption is ratified and correct; it is not a substitute for knowing what a query costs. No
   action is owed under any MUST — recorded so the gap stays visible rather than becoming invisible
   by default.
