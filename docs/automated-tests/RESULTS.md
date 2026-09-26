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

**Commit** is the short sha the run measured and **Tree** is whether that tree was clean at the
time. Both are read from git by the runner; neither is ever typed. A **dirty** row measured bytes
that no sha can bring back, so it is kept as an experiment honestly labeled rather than dropped —
and a release record is refused outright on a dirty tree, so no release row can be one.

A row reading `unknown` in both cells was recorded before the runner emitted them. That is what
the record holds about those runs — it is not `clean`, and it is not reconstructed from git
archaeology, for the same reason a skip is never a pass (`automated-tests-§4`).

| Run | Commit | Tree | Version | Lint w/e | Files | Tests | Perf | NLOC | Funcs | Avg NLOC | Avg CCN | Max CCN | CCN warn | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [`20260926-160249`](20260926-160249/) | `3ce80a7` | clean | 1.3.0 | 0/0 | 70 | 961/0/961 | skip | 18443 | 2519 | 6.3 | 2.1 | 15 | 0 | **green** |
| [`20260924-121347`](20260924-121347/) | `2f232f0` | clean | 1.3.0 | 0/0 | 67 | 928/0/928 | skip | 17579 | 2395 | 6.3 | 2.1 | 15 | 0 | **green** |
| [`20260916-184506`](20260916-184506/) | unknown | unknown | 1.3.0 | 0/0 | 63 | 786/0/786 | skip | 15349 | 2045 | 6.4 | 2.1 | 15 | 0 | **green** |
| [`20260916-094432`](20260916-094432/) | unknown | unknown | 1.3.0 | 0/0 | 59 | 768/0/768 | skip | 14889 | 1980 | 6.4 | 2.2 | 16 | 1 | **green** |
| [`20260910-234511`](20260910-234511/) | unknown | unknown | 1.2.0 → 1.3.0 | 0/0 | 59 | 720/0/720 | skip | 13892 | 1810 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260908-181338`](20260908-181338/) | unknown | unknown | 1.2.0 | 0/0 | 58 | 714/0/714 | skip | 13670 | 1803 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260825-103428`](20260825-103428/) | unknown | unknown | 1.2.0 | 0/0 | 28 | 644/644 | skip | 12116 | 1639 | 6.4 | 2.2 | 15 | 0 | **green** |
| [`20260807-114650`](20260807-114650/) | unknown | unknown | 1.2.0 | 0/0 | 23 | 594/594 | skip | 11479 | 1531 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260807-110451`](20260807-110451/) | unknown | unknown | 1.2.0 | 0/0 | 23 | 594/594 | skip | 11479 | 1531 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260807-022940`](20260807-022940/) | unknown | unknown | 1.2.0 | 0/0 | 23 | 594/594 | skip | 11479 | 1531 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260804-233322`](20260804-233322/) | unknown | unknown | 1.2.0 | 0/0 | 23 | 579/579 | skip | 11367 | 1518 | 6.5 | 2.2 | 15 | 0 | **green** |
| [`20260804-220017`](20260804-220017/) | unknown | unknown | 1.2.0 | 0/0 | 23 | 579/579 | skip | 11361 | 1518 | 6.5 | 2.2 | 0 | 0 | **green** |
| [`20260804-182216`](20260804-182216/) | unknown | unknown | 1.2.0 | 0/0 | 23 | 563/563 | skip | 11196 | 1457 | 6.7 | 2.3 | 58 | 9 | **green** |

## Test suite

**961 cases** — 961 passed, 0 failed, 0 skipped. The generated inventory
[`20260926-160249/test-cases.md`](20260926-160249/test-cases.md) is the authority on which cases existed at this run;
`docs/test-cases.md` is that same list at HEAD.

Moved **928 → 961** since the previous run.

No case reported a `skip`, so passed and total agree and nothing in this row claims coverage
that was not exercised.

## Lint

**0 warnings / 0 errors over 70 files** (`luacheck .`).

Read that figure with its scope attached: `.luacheckrc` excludes 5 path(s) from it — `libs/`, `docs/audits/`, `docs/reviews/`, `_dev/`, `tests/_kit/` —
so nothing under them is in the count above. A `0/0` that never moves is partly a statement about
what was never looked at, which is why the exclusions are NAMED here on every run rather than left
to whoever thinks to open `.luacheckrc`.

## Perf

**This repo holds a ratified `performance-§12` no-combat-path exemption, so `perf` is a
permanent `skip`** — the second of `automated-tests-§3`'s two sanctioned reasons, read by
this runner from the `## Documented deviations` register in `docs/ARCHITECTURE.md`. The exemption, and the sweep behind it, are in
`docs/performance.md`: this record carries no scenario table because the addon has no
combat path for one to measure, not because the question was never asked.

## Complexity watch list

Current as of [`20260926-160249`](20260926-160249/) — **this run's measurement, not its diff.** Max CCN **15** across 2519
functions, **0** of them warned on; 6 file(s) in the 1000–1500 band and 0 over the 1500 cap
(`layout-§1`).

Every row below is generated from this run's own `lizard` output. **The `Disposition` column is
the one authored cell in this file** (`automated-tests-§4`, *the one boundary*): it is carried
forward verbatim while its entry is unchanged, and left **blank** when the entry is new — a blank
cell is this file saying something crossed and nobody has ruled on it yet.

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Analytics.lua` | 1200 | **Peel — already tracked as #32** ([the issue](https://github.com/tusharsaxena/LootHistory/issues/32), `state:triaged`, `severity:low`: split the chart renderers from the formatting and segmenting helpers). That issue is the owned home the six previous runs asked for, so this cell stops restating the plan and points at it. Up from 1178 at [`20260916-184506`](20260916-184506/): 932 NLOC over 80 functions in [`complexity.txt`](20260924-121347/complexity.txt), still 300 lines under the cap. Re-rule when #32 closes, or at 1300 lines if it has not. |
| 1000–1500 (on notice) | `modules/Browser.lua` | 1289 | **Accepted, own disposition — `LH-37`.** The window shell, filter bar and dropdown widget kit; if it needs peeling the seam is the widget kit into a sibling file. It **grew** this cycle, 1244 at [`20260916-184506`](20260916-184506/) to the count beside this cell (804 NLOC over 103 functions, [`complexity.txt`](20260924-121347/complexity.txt)); the earlier wording that it shrank described the run before that and is withdrawn. The growth is the disabled-state stand-down, the combat-edge visibility decision (`LH-05`), the resize grip's Lock-frame gate (`LH-10`) and `NS.SafeRegisterEvent` for the two combat edges (`LH-17`): more of the same responsibilities, not a new one. `LH-37` (`docs/audits/2026-08-05/02_DEVIATIONS.md`) is the live finding for its size; there is deliberately **no** deviation ID, because a file in the 1000–1500 band is the **compliant** state under `layout-§1`, on notice rather than in breach, so it is not filed in `docs/ARCHITECTURE.md`'s `## Documented deviations` register. Re-check at 1400 lines, and peel the widget kit then. |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1227 | **Accepted.** Just over the line, and already three clean layers. Near flat this cycle (1225 at [`20260916-184506`](20260916-184506/)); 911 NLOC over 103 functions, and it still holds **three** of the addon's seven functions sitting at exactly CCN 15, now at `@659-707`, `@971-988` and `@1082-1125` ([`complexity.txt`](20260924-121347/complexity.txt)). Those are dense **guarding and defaulting**, not tangled control flow — cell-formatting bodies that fan out over column kinds. Do nothing yet. Re-check at 1300 lines, or the moment any of the three reaches 16. |
| 1000–1500 (on notice) | `settings/Panel.lua` | 1107 | **Accepted.** Up from 1062 at [`20260916-184506`](20260916-184506/), from the Filters tab's id lists (two to a line, the X on each entry) and the bus-message catalog; 561 NLOC over 48 functions ([`complexity.txt`](20260924-121347/complexity.txt)), so well under half of it is code, because a settings page is mostly declarative layout. On notice, which is the compliant state under `layout-§1`, not a breach. Re-check at 1200, or the moment a fourth tab arrives. |
| 1000–1500 (on notice) | `tests/test_schema.lua` | 1199 | **Accepted (2026-09-24).** New in the band: the schema suite grew with the `LibKa0s-Schema-1.0` handover, the retention-shortening confirm (`LH-04`) and the `minimap.shown` row (`LH-13`); 880 NLOC over 103 functions ([`complexity.txt`](20260924-121347/complexity.txt)). A test file has no runtime cost and its cases are already grouped by concern, so the split is mechanical when it is due. Re-check at 1300 lines, and peel by concern (row contract vs CLI) then, the way `test_slash_degraded.lua` came out of `test_slash.lua`. |
| 1000–1500 (on notice) | `tests/test_slash.lua` | 1094 | **Accepted (2026-09-24).** New in the band, and already peeled once: `LH-16` moved the degraded-path cases into `tests/test_slash_degraded.lua` when it neared 1100. 743 NLOC over 167 small functions ([`complexity.txt`](20260924-121347/complexity.txt)), one per case. Re-check at 1300 lines, and split the next concern out then. |

`lizard` counts every `and`/`or` short-circuit as a decision, so in Lua a run of
`t.k = rec.k or D.k` defaulting lines scores high with no visible branching at all: a large CCN
here usually means *this function defaults or guards a lot of fields* rather than *this function
is tangled*, and the two want different fixes (`performance-§10`).

