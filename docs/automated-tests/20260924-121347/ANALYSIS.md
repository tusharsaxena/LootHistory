# Analysis — 20260924-121347

- **Addon:** LootHistory 1.3.0
- **Verdict:** green
- **Commit:** 2f232f06f982f3bbd94018edb3f5e3daf74379fb (feat/2026-09-23-review-audit-remediation), clean
- **Previous run:** [`20260916-184506`](../20260916-184506/)

## Headline

Both gating suites are clean: `luacheck` reports 0 warnings / 0 errors over 67 files, and all 928
cases pass with no skips. The run and the commit gate are green. Two things changed in the record
itself. First, `perf` now records the **second** sanctioned skip reason, the ratified `performance-§12`
no-combat-path exemption, which kit revision 26 reads out of `docs/ARCHITECTURE.md`'s register.
Every earlier bundle recorded "no tests/perf.lua" and so denied the exemption (LootHistory-A-12).
Second, this is the first row that names its commit and tree state. Complexity stays at max CCN 15
with no warnings. Two test files entered the 1000–1500 band, and they carry dispositions in
`RESULTS.md`.

## Suites

| Suite | Status | Result | Artifact | Moved since [`20260916-184506`](../20260916-184506/) |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 67 files | [`lint.txt`](lint.txt) | Same 0/0; scope widened 63 → 67 files. |
| tests | pass | 928 passed, 0 skipped, 0 failed, 928 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | +142 cases (786 → 928), 31 → 36 suites; still zero skips. |
| perf | skip | 0 scenarios. Skip reason: `performance-§12 no-combat-path exemption (ratified; docs/ARCHITECTURE.md -> Documented deviations)` | none (nothing was measured) | Still a standing skip, but the recorded reason moved from (1) "no tests/perf.lua" to (2), the exemption. |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | Max CCN 15 → 15; warnings 0 → 0; band files 4 → 6; over-cap 0 → 0. |

Every status and count above comes from [`manifest.json`](manifest.json).

**Complexity in full.** All eight of `lizard`'s footer fields plus the two derived counts come from
`manifest.json`'s `suites.complexity`. The same footer is at the end of
[`complexity.txt`](complexity.txt).

| Metric | Value |
|---|---|
| Total NLOC | 17579 |
| Functions | 2395 |
| Avg NLOC / function | 6.3 |
| Avg CCN | 2.1 |
| Max CCN | 15 |
| Avg tokens / function | 51.2 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 6 |
| Files over the 1500 cap | 0 |

**perf, the one suite that is not a clean pass.** It did not run. It could not have: there is no
`tests/perf.lua`, and by design there never will be while the exemption holds. The reason is the
`performance-§12` row in `docs/ARCHITECTURE.md` → `## Documented deviations`. The sweep behind that
row, every event registration and timer with its per-fire work, is in `docs/combat-path-sweep.md`.
This bundle therefore says nothing measured about runtime cost. At the tag gate the skip reads
**NOT EVALUATED**, not pass (`automated-tests-§3`).

## What moved

- **lint.** Still 0/0. The scope grew by four files (63 → 67), all of them new test suites and
  test helpers. `.luacheckrc`'s five exclusions are unchanged (see `RESULTS.md` → Lint).
- **tests.** +142 cases. Five suites are new since the previous run: `test_slash_degraded.lua` (10),
  `test_schema_stub.lua` (9), `test_disabled.lua` (12), and the kit's `test_prose.lua` (15) and
  `test_layout_cap.lua` (13). The largest growth in existing suites is `test_schema.lua` 50 → 72,
  `test_attribution.lua` 25 → 37, `test_surface_parity.lua` 5 → 14 and `test_compat.lua` 31 → 39.
  One suite shrank on purpose: `test_debuglog.lua` 22 → 19, because it no longer re-tests the
  library's own formatters. All counts are from the two bundles' `test-cases.md`.
- **perf.** No scenarios either time. The recorded reason changed (see Suites).
- **complexity.** Total NLOC 15349 → 17579 and functions 2045 → 2395, so the addon grew. The averages
  held or fell: avg NLOC 6.4 → 6.3, avg CCN 2.1 → 2.1, avg tokens 52.0 → 51.2. Growth, not
  densification. Max CCN held at 15, and the count of functions at exactly 15 held at seven
  (`complexity.txt`: `Compat.ScanBound`, one each in `Attribution`, `AuctionPrice` and `Export`, and
  three in `BrowserTable`).

## Complexity watch list

**Functions `lizard` warned on**

| Function | CCN | Location | Disposition |
|---|---|---|---|
| None. | | | |

**Files by `layout-§1` band**

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Analytics.lua` | 1200 | Peel. Already tracked as #32 (`state:triaged`, `severity:low`). |
| 1000–1500 (on notice) | `modules/Browser.lua` | 1289 | Accepted, own disposition `LH-37`. It grew from 1244, and the earlier "shrank" wording is withdrawn. Re-check at 1400. |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1227 | Accepted. Three functions at exactly CCN 15. Re-check at 1300, or if any reaches 16. |
| 1000–1500 (on notice) | `settings/Panel.lua` | 1107 | Accepted. Re-check at 1200, or at a fourth tab. |
| 1000–1500 (on notice) | `tests/test_schema.lua` | 1199 | New in the band. Accepted (2026-09-24). Re-check at 1300, then peel by concern. |
| 1000–1500 (on notice) | `tests/test_slash.lua` | 1094 | New in the band. Accepted (2026-09-24), already peeled once (LH-16). Re-check at 1300. |

The LOC column is the runner's, from this run. The full disposition text is the authored cell in
`RESULTS.md`.

## Actions

1. `modules/Analytics.lua`: peel the chart renderers from the formatting and segmenting helpers.
   This is owned by issue #32. It is not new.
2. No other action. Every band file carries a dated re-check line, and no function is above CCN 15.
   A release run taken at this commit would clear the zero-above-CCN-15 condition. It would still
   need its own `--release` bundle, and `perf` would read NOT EVALUATED under the exemption.
