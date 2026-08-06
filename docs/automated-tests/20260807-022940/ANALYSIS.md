# Analysis — 20260807-022940

- **Addon:** LootHistory 1.2.0
- **Verdict:** green
- **Commit:** 24a17849a68a (master), dirty
- **Started:** 2026-08-07T02:29:40+05:30
- **Previous run:** [`20260804-233322`](../20260804-233322/) — the run that closed the CCN work

## Headline

Both gating suites are clean, and the record is taken on `master` rather than mid-branch this time:
`luacheck` 0 warnings / 0 errors over 23 files, and the headless harness **594 of 594**, up 15 cases
since the previous run. Complexity is unmoved where it counts — **0 functions above CCN 15**, max
still 15 over the same six functions, every average flat — while the totals grew (+112 NLOC, +13
functions) because the `feat/2026-08-05-audit-review-remediation` work and the LibKa0s v1.8.1 /
testkit rev-9 re-vendor both landed in between. `perf` is a **skip**, not a pass, and this is the
first write-up to name the reason correctly: this addon holds a ratified **`performance-§12`
no-combat-path exemption**, so it ships no `tests/perf.lua` by design rather than by omission.

## Suites

Every row links its artifact. A skipped suite links nothing — there is no artifact — and says what
was not measured.

| Suite | Status | Result | Artifact | Moved since 20260804-233322 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 23 files | [`lint.txt`](lint.txt) | unchanged — 0/0 over the same 23 files |
| tests | pass | 594 passed, 0 skipped, 0 failed, 594 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | **579 → 594 (+15)**, across six suite files, one of them new |
| perf | skip | — | — (not run) | still absent — no `tests/perf.lua`, and the `performance-§12` exemption is why |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | 0 warnings → 0 warnings; max CCN 15 → 15; totals up, averages flat |

### Complexity in full

Every field of `lizard`'s footer, plus the two derived file counts. The **averages** are the point: a
total that rose because the addon grew is a different fact from an average that rose because it got
denser, and only the second is a complexity signal. Here the totals moved and not one average did.

| Metric | Value | Previous (`20260804-233322`) |
|---|---|---|
| Total NLOC | 11479 | 11367 |
| Functions | 1531 | 1518 |
| Avg NLOC / function | 6.5 | 6.5 |
| Avg CCN | 2.2 | 2.2 |
| Max CCN | 15 | 15 |
| Avg tokens / function | 53.9 | 53.7 |
| Warnings (CCN > 15) | **0** | 0 |
| Warning rate — `Fun Rt` / `nloc Rt` | 0.00 / 0.00 | 0.00 / 0.00 |
| Files in the 1000–1500 band | 3 | 3 |
| Files over the 1500 cap | 0 | 0 |

Every value comes from this bundle's [`manifest.json`](manifest.json) (`suites.complexity`) and is
reproduced in [`complexity.txt`](complexity.txt)'s footer —
`Total nloc 11479 | Avg.NLOC 6.5 | AvgCCN 2.2 | Avg.token 53.9 | Fun Cnt 1531 | Warning cnt 0 | Fun Rt 0.00 | nloc Rt 0.00`,
under `No thresholds exceeded (cyclomatic_complexity > 15 …)`.

**The six functions on the cap.** `lizard` warns on nothing, and a max CCN of 15 means six functions
sit exactly on the line without crossing it. They are the **same six, at the same CCN, on the same
line ranges** as the previous bundle — nothing on the cap moved. From
[`complexity.txt`](complexity.txt)'s per-function rows:

| Function | CCN | Location |
|---|---|---|
| `E@39-159` — the block `lizard` attributes to `E:WowheadLink`, its Lua parser extending the span over the file-local CSV helpers that follow | 15 | `modules/Export.lua:39` |
| `BrowserTable:GroupRecords` (`BrowserTable@550-598`) | 15 | `modules/BrowserTable.lua:550` |
| `BrowserTable:UpdateHeaderArrows` (`BrowserTable@968-1005`) | 15 | `modules/BrowserTable.lua:968` |
| `BrowserTable:BindRow` (`BrowserTable@866-883`) | 15 | `modules/BrowserTable.lua:866` |
| `Attribution:OnLootOpened` (`Attribution@173-196`) | 15 | `modules/Attribution.lua:173` |
| `Compat.ScanBound` (`Compat.ScanBound@271-291`) | 15 | `core/Compat.lua:271` |

None of them is a control-flow tangle. `lizard` counts every `and`/`or` short-circuit as a decision,
and in Lua a run of `t.k = rec.k or D.k` defaulting lines scores high with no visible branching
(`performance-§10`) — these six are dense **defaulting and guarding**, which wants a different fix
from tangled flow and carries different risk.

**Perf was not measured, and that is a standing fact rather than this run's news.**
[`manifest.json`](manifest.json) records `"status": "skip"` with
`"skipReason": "no tests/perf.lua — this addon ships no offline scenarios"`. That is a **skip, not a
pass**: this run says nothing about the addon's runtime cost. Of `automated-tests-§3`'s two sanctioned
`perf` skip reasons the applicable one is the **second and more informative**: LootHistory holds a
recorded **`performance-§12` no-combat-path exemption**, ratified and carried as a register row in
[`../../ARCHITECTURE.md`](../../ARCHITECTURE.md) → `## Documented deviations` (the `LH-20`…`LH-26`
chain), with the committed sweep in [`../../performance.md`](../../performance.md). The addon
brackets nothing because it has no combat path to bracket — it ships no `tests/perf.lua` **by
design**. At the release gate this still reads as **NOT EVALUATED** rather than passed, and the
release notes have to say so out loud, naming the exemption.

## What moved

- **Tests, +15 (579 → 594).** The additions land in six files, from the two bundles'
  [`test-cases.md`](test-cases.md) totals tables: `test_libka0s.lua` 17 → 22, `test_harness.lua`
  **0 → 5** (a new suite file — `b4f489a test(harness): pin the TOC derivation and the suite list`),
  `test_schema.lua` 30 → 32, `test_panel.lua` 24 → 25, `test_auctionprice.lua` 23 → 24 and
  `test_analytics.lua` 57 → 58. No case was removed and none skipped: `manifest.json` records
  `"passed": 594, "failed": 0, "total": 594`.
- **Tests, one file shrank without losing coverage.** `tests/test_vendor_sync.lua` fell from 84 NLOC
  to **2** while keeping both its cases — the LibKa0s v1.8.1 / testkit rev-9 re-vendor moved the
  gate's body into the vendored `tests/_kit/vendor_sync.lua`, leaving one line of adoption. Its case
  names changed with the provenance line's move from `README.md` to `CLAUDE.md`, which is why the
  inventory regenerated with it.
- **Size, +112 NLOC (11367 → 11479) and +13 functions (1518 → 1531).** Almost all of it is test and
  seam code rather than feature code, per the two bundles' per-file `complexity.txt` rows:
  `tests/test_libka0s.lua` +48, `tests/test_harness.lua` +39 (new), `tests/test_schema.lua` +31,
  `tests/test_panel.lua` +23, `tests/test_analytics.lua` +11, `tests/test_auctionprice.lua` +9,
  `settings/Slash.lua` +25, `core/CoreSetup.lua` +23, `settings/Schema.lua` +4, `tests/run.lua` +2,
  against `tests/test_vendor_sync.lua` −82, `modules/Browser.lua` −20 and `modules/Analytics.lua`
  −1. The previous run was taken **dirty on `feat/fix-ccn`**; this one is on `master` after that
  branch and `feat/2026-08-05-audit-review-remediation` both merged, so the span covers a dozen
  commits rather than one change.
- **Complexity, nothing.** 0 warnings before and after, max CCN 15 both times over the same six
  functions, avg CCN 2.2 and avg NLOC 6.5 unmoved, avg tokens 53.7 → 53.9. The addon grew about 1%
  and got no denser — exactly the case the totals-and-averages rule exists to distinguish.
- **Lint, nothing.** 0 warnings / 0 errors over the same 23 files. Scope is unchanged; see
  [`../RESULTS.md`](../RESULTS.md)'s `## Lint` for what `.luacheckrc` leaves out.
- **File bands, nothing crossed.** Still 3 files in the 1000–1500 band and 0 over the 1500 cap
  (`"bandFiles": 3`, `"overCapFiles": 0`). Within the band `modules/Browser.lua` came **down** 6 LOC
  and `modules/Analytics.lua` went **up** 7; neither approached an edge.
- **Perf, nothing — and nothing was ever going to move.** Unchanged skip, unchanged reason.

## Complexity watch list

### Functions `lizard` warned on

**None.** No function in this addon exceeds CCN 15 (`"warnings": 0`, `"maxCcn": 15` in
[`manifest.json`](manifest.json)). That is a result, not an empty section — the six functions sitting
exactly on the cap are named above, and none is carried as a watch-list entry because none warns.

### Files by `layout-§1` band

`manifest.json` records the band as counts only (`"bandFiles": 3`, `"overCapFiles": 0`), and
[`complexity.txt`](complexity.txt)'s per-file rows carry **NLOC** (958 / 931 / 867), not raw LOC. The
LOC column below is the same `wc -l` measurement the runner's own band counter takes over `*.lua`
outside `libs/` and `tests/_kit/`. Nothing newly crossed; all three dispositions carry forward.

| Band | File | LOC | Disposition |
|---|---|---|---|
| 1000–1500 (on notice) | `modules/Browser.lua` | 1366 | **Accepted, own disposition — `LH-37`.** The window shell, filter bar and dropdown widget kit; the peel seam is the widget kit into a sibling file. Down 6 LOC (−20 NLOC) as the window edge finished delegating to `NS.ApplySkin`. Not newly crossed. |
| 1000–1500 (on notice) | `modules/Analytics.lua` | 1187 | **Peel next — still unblocked, still not done.** Gated originally on the `Database:Stats` work, which landed three runs ago. Split renderers from the formatting/segmenting helpers. Up 7 LOC; carried unchanged since the baseline. |
| 1000–1500 (on notice) | `modules/BrowserTable.lua` | 1097 | **Accepted.** Just over the line, already three clean layers, and flat at 1097 LOC / 867 NLOC across both runs. Watch it; do nothing yet. |
| > 1500 (over cap) | — | — | **None.** `"overCapFiles": 0`. |

## Actions

1. **Correct the `## Perf` narrative in [`../RESULTS.md`](../RESULTS.md)** — done in the same change
   as this analysis. The standing section framed the skip as an unmeasured gap; `automated-tests-§3`
   requires the ratified **`performance-§12`** exemption to be named when it applies, and this addon
   holds one (`docs/performance.md`, `docs/ARCHITECTURE.md` → `## Documented deviations`). The skip
   is real either way; what changes is that a reader can now tell a ratified exemption from a suite
   nobody wrote.
2. **`modules/Analytics.lua`'s peel is overdue rather than pending.** It has read *"peel next —
   unblocked"* since [`20260804-233322`](../20260804-233322/) and has grown 7 LOC since. It gates
   nothing — the file warns on no function — but a disposition that says "next" across runs and does
   not move is a disposition with no owner. No deviation ID tracks it today; that is the thing to
   fix, either by doing the peel or by filing it.
3. **No new action from lint, tests or complexity.** All three are clean and moved in the direction
   they should.
