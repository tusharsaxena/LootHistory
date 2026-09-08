# Analysis — 20260908-181338

- **Addon:** LootHistory 1.2.0
- **Verdict:** green
- **Commit:** 1ef54e1 (`feat/2026-09-07-audit-review-remediation`), clean
- **Previous run:** [`20260825-103428`](../20260825-103428/)

## Headline

Three suites pass and one is a permanent skip. Lint 0/0 over 58 files, 714 cases with none failed and
none skipped, `lizard` warns on nothing at max CCN 15 across 1803 functions, and `perf` skips because
this repository ships no `tests/perf.lua`.

This is the first bundle written by test-kit revision 15 and the first whose `RESULTS.md` came out of
the runner end to end. The watch list it replaces described three files as flat; all three had moved,
one of them by 91 lines, and a fourth had joined the band. That is `C08` in one repository, and it is
a consequence of the runner rather than of anyone's neglect: until today the two tables
`automated-tests-§4` mandates had no producer.

## Suites

| Suite | Status | Result | Artifact | Moved since `20260825-103428` |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 58 files | [`lint.txt`](lint.txt) | 28 → 58 files; 0/0 unchanged |
| tests | pass | 714 passed, 0 skipped, 0 failed, 714 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | 644 → 714 |
| perf | skip | no `tests/perf.lua` | — | Unchanged, and permanent |
| complexity | pass | 0 warnings, max CCN 15 | [`complexity.txt`](complexity.txt) | Totals up; averages flat; band 3 → 4 files |

**On the `perf` skip.** This is the first of `automated-tests-§3`'s two sanctioned reasons —
*nothing to run* — and not a ratified `performance-§12` exemption. The record is **silent about
runtime cost**: nothing here says this addon is cheap, only that the question was never asked. A
skip is never a pass, and at the release gate it is NOT EVALUATED.

**Complexity in full.**

| Metric | `20260825-103428` | This run |
|---|---|---|
| Total NLOC | 12116 | 13670 |
| Functions | 1639 | 1803 |
| Avg NLOC / function | 6.4 | 6.5 |
| Avg CCN | 2.2 | 2.2 |
| Max CCN | 15 | 15 |
| Avg tokens / function | 52.6 | 52.5 |
| Warnings (CCN > 15) | 0 | 0 |
| Files 1000–1500 | 3 | 4 |
| Files over 1500 | 0 | 0 |

Totals up 13% and 10%, every average flat. Six functions sit at exactly CCN 15 and none above:
`E@39-159` (`modules/Export.lua`), `BrowserTable@605-653` and `BrowserTable@1028-1071`
(`modules/BrowserTable.lua`), `Compat.ScanBound@237-257` (`core/Compat.lua`),
`Attribution@184-207` (`modules/Attribution.lua`) and `AuctionPrice@156-180`
(`modules/AuctionPrice.lua`). Zero headroom on six functions is worth stating: one more `or` on any
of them warns, and a warning blocks a tag (`automated-tests-§3`).

## What moved

- **lint** — 28 → 58 files at 0/0, the test tree coming into scope.
- **tests** — 644 → 714. `docs/test-cases.md` and the README badge already read 714, and the
  bundle's [`test-cases.md`](test-cases.md) is byte-identical to `docs/test-cases.md` at HEAD, so no
  count claim moves in this commit.
- **Band** — three files to four, and every one of them moved:
  `settings/Panel.lua` crossed at 1041 from 811, `modules/Browser.lua` 1198 → 1289,
  `modules/BrowserTable.lua` 1125 → 1173, `modules/Analytics.lua` 1174 → 1178. Three dispositions
  described their file as flat. None was.

## The disposition that has stopped being a decision

`modules/Analytics.lua` has read **"peel next"** since [`20260804-233322`](../20260804-233322/),
where it was recorded as unblocked by the `Database:Stats` work landing. That is now **five
consecutive runs** in which the same cell has named the same file next and nothing has happened, and
nothing in the issue store tracks it — `gh issue list` on this repository returns four open issues
and none of them is this.

`automated-tests-§4` gives an accepted entry a shelf life for exactly this reason, and a *peel next*
that never gets peeled is the same failure wearing a more urgent word. No peel lands in this cycle
(`03_SPEC.md` § C22 rules out splitting shipped source), so the remaining honest move is the one the
cell itself named a month ago: an owned issue. `M5-07` is this plan's item for filing what it decided
not to do, and this belongs to it. The disposition now says so instead of repeating "peel next" a
sixth time.

## The `ANALYSIS.md` gap, noted once

Three of eight bundles here carry no `ANALYSIS.md`: `20260807-110451`, `20260825-103428`, and until
this file, this one. The first two are not getting one. An analysis written today into a folder
stamped in August would date a reading to a day nobody took it, which is worse than a gap, because a
gap is legible. Fixed forward. Collection-wide the same gap stands at 37 of 95 bundles.

## Actions

One, and it is not a code change: `modules/Analytics.lua`'s five-run-old *peel next* needs an owner
in the issue store, at `M5-07`. Everything else is clean — no warned function, no file over cap, and
no disposition due for conversion, because every manifest here carries `"release": null` and the
three-consecutive-release-runs clock has not started.
