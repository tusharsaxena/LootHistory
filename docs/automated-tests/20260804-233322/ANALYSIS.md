# Analysis — 20260804-233322

- **Addon:** LootHistory 1.2.0
- **Verdict:** green
- **Commit:** 8f4e7aaf38e7 (feat/fix-ccn), dirty
- **Started:** 2026-08-04T23:33:22+05:30
- **Previous run:** [`20260804-220017`](../20260804-220017/) — the first run of `feat/fix-ccn` with zero warnings

## Headline

This is the run that closes the CCN work, and it closes it twice over: **zero functions above CCN 15,
and an instrument that can finally say so.** The previous run had the same result and could not report
it — `manifest.json` there records `"maxCcn": 0` because the kit read `CCN_MAX` out of `lizard`'s
`!!!! Warnings` block, which is empty the moment an addon reaches zero warnings. The re-vendored
testkit (rev 6, in the working tree over `8f4e7aa`) reads the per-function table instead, so this
run's `manifest.json` records `"maxCcn": 15` — the true maximum, and the same six functions were
sitting on the cap in the previous bundle's `complexity.txt` all along. Both gating suites are clean:
`luacheck` 0 warnings / 0 errors over 23 files, and the headless harness 579 of 579. The only code
change since the previous run is `Database:QueryList`'s filter compile step, worth +6 NLOC.

## Suites

| Suite | Status | Result | Artifact | Moved since 20260804-220017 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 23 files | [`lint.txt`](lint.txt) | unchanged — clean before, clean now |
| tests | pass | 579 passed, 0 failed, 579 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | unchanged — 579 → 579, and `test-cases.md` is byte-identical to the previous bundle's |
| perf | skip | — | — (not run) | still absent — no `tests/perf.lua` |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | 0 warnings → 0 warnings; reported `Max CCN` 0 → **15**, which is an instrument change, not a code change |

### Complexity in full

Every field of `lizard`'s footer, plus the two derived file counts. The **averages** are the point:
a total that rose because the addon grew is a different fact from an average that rose because it got
denser, and only the second is a complexity signal. Here the total moved by six lines and not one
average moved at all.

| Metric | Value | Previous |
|---|---|---|
| Total NLOC | 11367 | 11361 |
| Functions | 1518 | 1518 |
| Avg NLOC / function | 6.5 | 6.5 |
| Avg CCN | 2.2 | 2.2 |
| Max CCN | **15** | 0 (reported) — true value 15 |
| Avg tokens / function | 53.7 | 53.7 |
| Warnings (CCN > 15) | **0** | 0 |
| Warning rate — `Fun Rt` / `nloc Rt` | 0.00 / 0.00 | 0.00 / 0.00 |
| Files in the 1000–1500 band | 3 | 3 |
| Files over the 1500 cap | 0 | 0 |

Every value comes from this bundle's [`manifest.json`](manifest.json) (`suites.complexity`) and is
reproduced in [`complexity.txt`](complexity.txt)'s footer —
`Total nloc 11367 | Avg.NLOC 6.5 | AvgCCN 2.2 | Avg.token 53.7 | Fun Cnt 1518 | Warning cnt 0 | Fun Rt 0.00 | nloc Rt 0.00`,
under `No thresholds exceeded (cyclomatic_complexity > 15 …)`.

**The six functions on the cap.** `lizard` warns on nothing, and a `Max CCN` of 15 means six functions
sit exactly on the line without crossing it. Naming all six, from [`complexity.txt`](complexity.txt)'s
per-function rows:

| Function | CCN | Location |
|---|---|---|
| `E@39-159` — the block `lizard` attributes to `E:WowheadLink`, its Lua parser extending the span over the file-local CSV helpers that follow | 15 | `modules/Export.lua:39` |
| `BrowserTable:GroupRecords` (`BrowserTable@550-598`) | 15 | `modules/BrowserTable.lua:550` |
| `BrowserTable:UpdateHeaderArrows` (`BrowserTable@968-1005`) | 15 | `modules/BrowserTable.lua:968` |
| `BrowserTable:BindRow` (`BrowserTable@866-883`) | 15 | `modules/BrowserTable.lua:866` |
| `Attribution:OnLootOpened` (`Attribution@173-196`) | 15 | `modules/Attribution.lua:173` |
| `Compat.ScanBound` (`Compat.ScanBound@271-291`) | 15 | `core/Compat.lua:271` |

The same six were at 15 in the previous bundle's `complexity.txt`, on the same line ranges. None of
them is a control-flow tangle: `lizard` counts every `and`/`or` short-circuit as a decision, and in
Lua a run of `t.k = rec.k or D.k` defaulting lines scores high with no visible branching
(`performance-§10`).

**Perf was not measured.** `tests/perf.lua` is absent — this addon ships no offline scenarios — so
`manifest.json` records `"status": "skip"` with `"skipReason": "no tests/perf.lua — this addon ships
no offline scenarios"`. That is a **skip, not a pass**: this run says nothing about the addon's
runtime cost, including the cost of the `QueryList` change below.

## What moved

- **Complexity, instrument.** Reported `Max CCN` 0 → 15. Nothing in the addon got more complex; the
  kit stopped maximizing over the (empty) warnings block and started reading the per-function table.
  This is the fix that makes the previous run's `0` legible, and every run stamped before it carries
  the same artifact — see the note in [`../RESULTS.md`](../RESULTS.md).
- **Complexity, code.** One function pair changed shape. `anyFiltered@371-373` (CCN 5) and
  `Database@375-403` (`Database:QueryList`, CCN 13) in the previous bundle became
  `compileFilter@380-399` (CCN 13) and `Database@401-423` (`QueryList`, CCN **9**) in this one: the
  or-hiding helper became a real filter-compile step, and `QueryList` itself dropped four. The
  warning count stayed at zero throughout.
- **Size.** +6 NLOC (11361 → 11367), function count flat at 1518, every average unmoved. Six lines is
  not a size story.
- **Tests.** 579 → 579, and `test-cases.md` is byte-identical to the previous bundle's — the
  `QueryList` change was covered by the three filter-contract cases the previous run added, so it
  needed no new ones.
- **Lint and files.** Unchanged. 0/0 over the same 23 files; the same three files sit in the
  1000–1500 band and nothing crossed either way.

## Complexity watch list

### Functions `lizard` warned on

**None.** No function in this addon exceeds CCN 15, and `manifest.json` now records the true maximum
(`"maxCcn": 15`) rather than a zero standing in for "no warnings to maximize over".

### Files by `layout-§1` band

`manifest.json` records the band as counts only (`"bandFiles": 3`, `"overCapFiles": 0`), and
`complexity.txt`'s per-file rows carry NLOC (978 / 932 / 867), not raw LOC; the LOC column below is
read from the tree at this run's commit. All three entries carry forward from the previous run
unchanged — nothing newly crossed.

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Browser.lua` | 1372 | **Already tracked as `LH-31`.** The window shell, filter bar and dropdown widget kit; if it needs peeling the seam is the widget kit into a sibling file. Untouched by this run. |
| 1000–1500 (on notice) | `modules/Analytics.lua` | 1180 | **Peel next — unblocked.** It was gated on the `Database:Stats` work, which has landed. Split renderers from the formatting/segmenting helpers. Untouched by this run. |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1097 | **Accepted.** Just over the line and already three clean layers. Watch it; do nothing yet. Untouched by this run. |
| > 1500 (over cap) | — | — | **None.** `"overCapFiles": 0`. |

## Actions

None arising from this run. The one thing it retires is a reading rather than a defect: the previous
run's `Max CCN 0` was an instrument fault, and it is now annotated in [`../RESULTS.md`](../RESULTS.md)
so a reader hitting `58 → 0 → 15` in the trend column can find the true figure in one step. The three
file-band dispositions carry forward unchanged; `LH-31` and the Analytics peel are both pre-existing.
The standing gap is perf: adding `tests/perf.lua` is the only thing that will put a runtime-cost
number on any of this.
