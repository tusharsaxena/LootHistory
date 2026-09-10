# Automated test results

<!-- Regenerated whole by tests/_kit/run-automated-tests.sh on every run. -->
<!-- This file is OVERWRITTEN IN PLACE — the git history of this one path is the trend line. -->
<!-- Everything here is generated EXCEPT the watch list's Disposition column. -->

One row per run. The frozen evidence for each is in the dated folder beside this file;
the analysis of a given run is its `ANALYSIS.md`.

**`lint` and `tests` gate the run and gate the commit** (`testing-§4`).
**`perf` and `complexity` never fail a run and never block a commit** — they are recorded,
read and compared, not thresholded (`performance-§9`, `performance-§10`).

**The tag is gated on all four suites at `pass`, plus zero functions above CCN 15**
(`automated-tests-§3`, *The release gate*), evaluated by `/wow-addon:bump-version` from the
`manifest.json` the release run writes — not by this script, whose exit code is unchanged.

A `skip` is a suite that did not run at all. It is never a pass, and at the release gate it is
**NOT EVALUATED** rather than passed: install the tool and re-run. A `—` is a suite that was
not selected, which is a different fact again.

The **Tests** cell reads `passed/skipped/total`.

| Run | Version | Lint w/e | Files | Tests | Perf | NLOC | Funcs | Avg NLOC | Avg CCN | Max CCN | CCN warn | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [`20260910-234511`](20260910-234511/) | 1.2.0 → 1.3.0 | 0/0 | 59 | 720/0/720 | skip | 13892 | 1810 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260908-181338`](20260908-181338/) | 1.2.0 | 0/0 | 58 | 714/0/714 | skip | 13670 | 1803 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260825-103428`](20260825-103428/) | 1.2.0 | 0/0 | 28 | 644/644 | skip | 12116 | 1639 | 6.4 | 2.2 | 15 | 0 | **green** |
| [`20260807-114650`](20260807-114650/) | 1.2.0 | 0/0 | 23 | 594/594 | skip | 11479 | 1531 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260807-110451`](20260807-110451/) | 1.2.0 | 0/0 | 23 | 594/594 | skip | 11479 | 1531 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260807-022940`](20260807-022940/) | 1.2.0 | 0/0 | 23 | 594/594 | skip | 11479 | 1531 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260804-233322`](20260804-233322/) | 1.2.0 | 0/0 | 23 | 579/579 | skip | 11367 | 1518 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260804-220017`](20260804-220017/) | 1.2.0 | 0/0 | 23 | 579/579 | skip | 11361 | 1518 | 6.5 | 2.2 | 0 | 0 | **green** |
| [`20260804-182216`](20260804-182216/) | 1.2.0 | 0/0 | 23 | 563/563 | skip | 11196 | 1457 | 6.7 | 2.3 | 58 | 9 | **green** |

## Test suite

**720 cases** — 720 passed, 0 failed, 0 skipped. The generated inventory
[`20260910-234511/test-cases.md`](20260910-234511/test-cases.md) is the authority on which cases existed at this run;
`docs/test-cases.md` is that same list at HEAD.

Moved **714 → 720** since the previous run.

No case reported a `skip`, so passed and total agree and nothing in this row claims coverage
that was not exercised.

## Lint

**0 warnings / 0 errors over 59 files** (`luacheck .`).

Read that figure with its scope attached: `.luacheckrc` sets `exclude_files = { "libs/", "docs/audits/", "docs/reviews/", "_dev/", "tests/_kit/" }`, so those paths
are not in it. A `0/0` that never moves is partly a statement about what was never looked at, which
is why the exclusion is restated on every run.

## Perf

**This repo ships no `tests/perf.lua`, so `perf` is a permanent `skip`** — the first of
`automated-tests-§3`'s two sanctioned reasons, *nothing to run*, rather than a ratified
`performance-§12` no-combat-path exemption. The record is therefore **silent about runtime
cost**: nothing in this file says this addon is fast or cheap, only that the question was
never asked.

## Complexity watch list

Current as of [`20260910-234511`](20260910-234511/) — **this run's measurement, not its diff.** Max CCN **15** across 1810
functions, **0** of them warned on; 5 file(s) in the 1000–1500 band and 0 over the 1500 cap
(`layout-§1`).

Every row below is generated from this run's own `lizard` output. **The `Disposition` column is
the one authored cell in this file** (`automated-tests-§4`, *the one boundary*): it is carried
forward verbatim while its entry is unchanged, and left **blank** when the entry is new — a blank
cell is this file saying something crossed and nobody has ruled on it yet.

### Functions `lizard` warned on

None.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Analytics.lua` | 1178 | **Peel next — unblocked since [`20260804-233322`](20260804-233322/), and still not started after five runs.** It was gated on the `Database:Stats` work, which has landed. Split renderers from the formatting/segmenting helpers. Effectively flat — 1174 at the previous run's commit, 1178 now, 921 NLOC over 78 functions. Nothing tracks it, and that is the gap this cell has now reported five times running: a disposition that names itself next and never moves is a decision that has stopped being one. No peel lands this cycle (`03_SPEC.md` § C22), so the remaining honest move is an owned issue, and `M5-07` is where this plan files what it decided not to do. |
| 1000–1500 (on notice) | `modules/Browser.lua` | 1289 | **Accepted, own disposition — `LH-37`.** The window shell, filter bar and dropdown widget kit; if it needs peeling the seam is the widget kit into a sibling file. Not flat this cycle — 1198 at the previous run's commit, +91 to 1289, the largest move of the four files here. This row used to read *"Already tracked as `LH-31`"*, which was the retired **`docs/complexity.md` is not shipped** finding (`automated-tests-§7` retired that file in v2.19.0) — it never tracked a file's size, and `LH-37` (`docs/audits/2026-08-05/02_DEVIATIONS.md`) is the live finding that says so. There is deliberately **no** deviation ID to cite instead: a file in the 1000–1500 band is the **compliant** state under `layout-§1`, on notice rather than in breach, so it is not filed in `docs/ARCHITECTURE.md`'s `## Documented deviations` register. |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1173 | **Accepted.** Just over the line, and already three clean layers. No longer flat: 1125 at the previous run's commit, 1173 now, 880 NLOC over 99 functions. It also holds two of this addon's six functions at exactly CCN 15, at `@605-653` and `@1028-1071`, so size and density are both worth watching here rather than only size. Watch it; do nothing yet. Re-check at 1300. |
| 1000–1500 (on notice) | `settings/Panel.lua` | 1056 | **Accepted.** Newly in the band and the crossing is this cycle's: 811 lines at the previous run's commit, 1041 now. It is the least dense file of the four — 596 NLOC over 45 functions, so well under half of it is code — because a settings page is mostly declarative layout. On notice, which is the compliant state under `layout-§1`, not a breach. Re-check at 1200, or the moment a fourth tab arrives. |
| 1000–1500 (on notice) | `tests/test_panel.lua` | 1030 | **Accepted.** Newly in the band, and the crossing is this cycle's: 998 lines at the previous run's commit, 1030 now — it went over on 32 lines, not on a growth spurt. It is the settings panel's suite and it grew with the tabbed General/Filters work the same way `settings/Panel.lua` did; both crossed together and the pair should peel together if either does. Re-check at 1200. |

`lizard` counts every `and`/`or` short-circuit as a decision, so in Lua a run of
`t.k = rec.k or D.k` defaulting lines scores high with no visible branching at all: a large CCN
here usually means *this function defaults or guards a lot of fields* rather than *this function
is tangled*, and the two want different fixes (`performance-§10`).

