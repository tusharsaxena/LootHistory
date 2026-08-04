# Analysis — 20260804-220017

- **Addon:** LootHistory 1.2.0
- **Verdict:** green
- **Commit:** 99c47ba07216 (feat/fix-ccn), dirty
- **Started:** 2026-08-04T22:00:17+05:30
- **Previous run:** [`20260804-182216`](../20260804-182216/) — the master baseline, taken before this branch

## Headline

The run that records what `feat/fix-ccn` was for: **`lizard` warns on nothing.** Nine functions were
over the CCN cap of 15 in the baseline, topping out at 58; this run has **zero** warnings and a true
maximum of 15. Both gating suites are clean — `luacheck` 0 warnings / 0 errors over 23 files, and the
headless harness 579 of 579 cases, 16 more than the baseline's 563 (the refactor's characterization
tests). The addon is 165 NLOC and 61 functions larger for it, which is the shape of the change: the
same work, cut into more, smaller named units.

## Suites

| Suite | Status | Result | Artifact | Moved since previous run |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 23 files | [`lint.txt`](lint.txt) | unchanged — clean before, clean now |
| tests | pass | 579 passed, 0 failed, 579 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | 563 → 579 (+16 characterization cases) |
| perf | skip | — | — (not run) | still absent — no `tests/perf.lua` |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | 9 warnings → **0** |

### Complexity in full

Every field of `lizard`'s footer, plus the two derived file counts. The **averages** are what make
this run comparable to the previous one across a change in size: a total that rises because the addon
grew is a different fact from an average that rises because it got denser, and only the second is a
complexity signal. Here the total grew and every average fell.

| Metric | Value | Previous |
|---|---|---|
| Total NLOC | 11361 | 11196 |
| Functions | 1518 | 1457 |
| Avg NLOC / function | 6.5 | 6.7 |
| Avg CCN | 2.2 | 2.3 |
| Max CCN | 0 (reported) — see below | 58 |
| Avg tokens / function | 53.7 | 55.4 |
| Warnings (CCN > 15) | **0** | 9 |
| Warning rate — `Fun Rt` / `nloc Rt` | 0.00 / 0.00 | 0.01 / 0.04 |
| Files in the 1000–1500 band | 3 | 3 |
| Files over the 1500 cap | 0 | 0 |

`Max CCN` is reported as `0` because the kit takes the maximum **over warned functions**, and there
are none. Read from `complexity.txt` directly, the true maximum is **15** — six functions sit exactly
on the cap (`E@39-159` in `modules/Export.lua`, `Compat.ScanBound`, three in `modules/BrowserTable.lua`,
one in `modules/Attribution.lua`), none over it.

`tests/perf.lua` is absent — this addon ships no offline scenarios, so nothing was measured there.
That is a **skip, not a pass**: it is recorded as one in `manifest.json`, and it means this run says
nothing about the addon's runtime cost. The one hot path this branch did touch, `Database:QueryList`,
was measured out of band against master (5000 records, 150 passes, best of 3) rather than here.

## What moved

- **Complexity.** Nine warned functions to none. `Database:QueryList` 58 → 13, `NS:RunMigrations`
  56 → 7, `Database:RepairBoundStates` 23 → 6, `B:CaptureView` 23 → 5, `menu:Populate` 20 → 4,
  `dd:UpdateMultiLabel` 19 → 5, `groupOf` 19 → 2, `B:ApplyView` 17 → 8, `make` 16 → 8. Every one of
  them was split into named file-local helpers or a module-level dispatch/step table; none was
  deleted and no behavior changed.
- **Tests.** +16: three pinning `QueryList`'s filter contract (quality `0` is a real selection, the
  exact-vs-set asymmetry on a record with no quality, a falsy filter field means unfiltered) and
  thirteen pinning the Browser's collapsed multi-select label and menu-row highlight precedence.
- **Size.** +165 NLOC, +61 functions, with every average down. That is the arithmetic of splitting:
  more units, each smaller and simpler than what it came out of.
- **Lint and files.** Unchanged. The same three files sit in the 1000–1500 band; two of them grew a
  little as helpers landed beside their callers.

## Complexity watch list

### Functions `lizard` warned on

**None.** No function in this addon exceeds CCN 15.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Browser.lua` | 1372 | **Already tracked as `LH-31`.** The window shell, filter bar and dropdown widget kit; if it needs peeling the seam is the widget kit into a sibling file. Up 58 lines from the baseline — the menu-row and view-descriptor helpers this branch extracted. |
| 1000–1500 (on notice) | `modules/Analytics.lua` | 1180 | **Peel next — now unblocked.** Untouched by this branch. It was gated on the `Database:Stats` work, which has landed. Split renderers from the formatting/segmenting helpers. |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1097 | **Accepted.** Still just over the line and still three clean layers; up 57 lines for the `GROUP_OF` dispatch table and the synthetic-record helpers. Watch it; do nothing yet. |

## Actions

None arising from this run. The nine dispositions the baseline carried are all discharged — the
functions they covered no longer warn — and the three file-band dispositions carry forward unchanged
(`LH-31` and the Analytics peel are both pre-existing and untouched here).
