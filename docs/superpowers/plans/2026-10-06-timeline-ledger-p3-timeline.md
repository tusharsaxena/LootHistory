# Timeline Ledger — Phase 3 (Timeline) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Draw the **Timeline** tab: one thing (Gold, a currency or an item) charted over time as a Total line plus one line per holder, fed by a sparse **daily rollup** that the ledger writes as it runs, with an in/out bar strip, a hover crosshair and tooltip, "Show in Timeline" from History and Holdings rows, and "Forget this character". The line-chart primitive is built **in LibKa0s** first, released as a tag, then re-vendored here.

**Architecture:** Two repos, gated by a release. **Part A (LibKa0s)** adds `LibKa0s/WidgetsLineChart.lua`, a secondary file of `LibKa0s-Widgets-1.0` paired on the shell's minor exactly like `WidgetsDragHandle.lua`: pure chart math (`lib.ChartMath`: nice ticks, LTTB downsampling to one point per 2 px, time ticks, nearest index, dash cutting) plus a pooled `lib.LineChart(parent, opts)` drawn with `Region:CreateLine` Line objects. The test kit gains `testkit/mock_lines.lua` (kit revision 37) so a headless suite can observe Line objects. Released as **v1.69.0** (Widgets key **12.1.4.1**). **Part B (LootHistory)** re-vendors v1.69.0, leases the widget through `NS.MakeLineChart` in `core/WidgetsSetup.lua`, writes the rollup (`db.global.daily[day][holder][thingKey] = {c,i,o}`) from two seams — closes from the `NS.Holdings` write methods, in/out tallies from Phase 2's synchronous `NS.Database:OnWrite` hook — prunes it with `rollupRetentionDays`, and renders the Timeline from a pure model (`modules/TimelineModel.lua`) into a thin view (`modules/Timeline.lua`). The Browser's tab registry learns per-tab filter graying (spec §8.0) and a holders-sourced Character list.

**Tech Stack:** Lua 5.1 (WoW Retail 12.1.0, Interface 120100), Ace3, LibKa0s v1.68.1 → **v1.69.0**, test kit revision 36 → **37**, headless harnesses `lua tests/run.lua` in both repos, `luacheck .` in both repos, LibKa0s release runner `tests/_kit/run-automated-tests.sh --release`.

**Spec:** `docs/superpowers/specs/2026-10-06-timeline-ledger-design.md` (§4.3, §8.0 per-tab filters, §8.1 Timeline, §8.2 "Show in Timeline" and "Forget this character", §11 `timelineMaxLines` / `rollupRetentionDays`, §12, §13 F3, §14 phase 3).

**Builds on:** `docs/superpowers/plans/2026-10-06-timeline-ledger-p1-foundation.md` and `docs/superpowers/plans/2026-10-06-timeline-ledger-p2-ledger-capture.md` (their **Produces** interfaces are consumed verbatim below). From Phase 2 this plan uses: the row shape (`dir`, `kind`, `holder`, unsigned `quantity`, `ts`, `from`/`to` on `MOVE` rows; an inter-holder transfer is a `MOVE` **pair, one row per holder**); `NS.Database:OnWrite(fn)` → `fn(record, deltaQty, isNew)`, run synchronously for every `Add` **and** `Amend` (Phase 2 Task 4: "Phase 3's rollup registers here"); `NS.Database:RemoveWriteHook(fn)`; `NS.Holdings:CreditCurrency(holder, id, qty)` and `NS.Holdings:CreditEscrow(holder, container, id, qty, own)` (the two Phase 2 holdings writes that bypass `Apply*`); `NS.LedgerFormat.HolderLabel`; `NS.Constants.DirRGB`; the Direction dropdown `B._dd.dir`. Note Phase 2's S2: `RECORD_ADDED` is **re-sent on an amend** with the same row, so it is a repaint signal and must never be counted. **What this plan needs from Phase 2 is restated once, in "Phase 2 contract (rollup hook)" below.**

## Global Constraints

- Ka0s WoW Addon Standard governs both repos. Any deviation: **STOP and flag** (each repo's CLAUDE.md). Do not add rows to either `## Documented deviations` register without the user's say-so. The open flags are listed under **Standards flags** and must be resolved **before** the task that trips them.
- **LibKa0s rules** (its `CLAUDE.md`, `docs/releasing.md`):
  - The shipped payload `LibKa0s/` is **ASCII-only except the em dash** (`tests/test_prose.lua`) and **US English**. No `§`, `≤`, `·`, curly quotes or arrows in `LibKa0s/*.lua`. Write `--`, `<=`, `->`.
  - A new file in an existing major is a **paired secondary**: own `CHART_MINOR`, `lib.__chartMinor` / `lib.__chartShellMinor`, `lib.MODULES.WidgetsLineChart`, a `LibKa0s.xml` row after `WidgetsDragHandle.lua`, and a `paired` row in `tests/majors.lua`. `Widgets.lua` stays at minor **12**; the major's version key becomes **12.1.4.1**.
  - Every minor move needs, in the same commit, the `CHANGELOG.md` needle `WidgetsLineChart minor 1`, `docs/api/Widgets/version-12.1.4.1-docs.md`, and regenerated manifests (`lua tools/gen-api-members.lua`). `tests/test_versioning.lua` is red otherwise.
  - A `testkit/` change bumps `Kit.VERSION`, writes `docs/api/testkit/version-<N>-docs.md`, and is re-vendored into LibKa0s's own `tests/_kit/` (`cp -r testkit/. tests/_kit/`) before the gate can pass (`tests/test_kitsync.lua`).
  - No function above CCN 15 (lizard; the release gate counts it). Keep helpers small; the code below is already split for that.
  - `testkit/mock_base.lua` is at 1456 lines with a 1490 re-check trigger: it gains **two** lines only; the Line model lives in its own kit file.
  - LibKa0s green gate: `lua tests/run.lua` (0 failed) and `luacheck .` (0/0). Regenerate `docs/test-cases.md` with `lua tests/run.lua --list > docs/test-cases.md` (keep CRLF; `.gitattributes` pins it) and move the README test badge to the `## Totals` figure in any task that adds cases.
- **LootHistory rules** (inherited from Phase 1, unchanged): `local _, NS = ...` + `NS.X = NS.X or {}`; Compat for every direct client call that is not already a sanctioned global in `.luacheckrc` (`CreateFrame`, `GameTooltip`, `RAID_CLASS_COLORS`, `date`, `time`, `StaticPopup_Show` are already read-globals); private `NS.NewBusTarget()` per module; a real `Disable`; settings through `settings/Schema.lua` rows with defaults once in `defaults/`; files ≤ 1500 lines (`modules/Browser.lua` must stay under 1500 after Phase 2's additions; this plan adds ≈ 70 lines to it); never edit `libs/` or `tests/_kit/`; match neighbors' comment density.
- **Re-vendor rule** (LootHistory `CLAUDE.md`): the `## Vendored LibKa0s` provenance line and the copied bytes move **in the same commit**, from the **tag**, never from untagged `master` (`tests/test_vendor_sync.lua` resolves the tag).
- LootHistory green gate before every commit: `lua tests/run.lua` (all pass) and `luacheck .` (0/0); regenerate `docs/test-cases.md` with `lua tests/run.lua --list > docs/test-cases.md` in any task that adds tests.
- Work trunk-based on `master` in **both** repos; commit at the end of each task only when that repo's gate is green. **Pushing, tagging and publishing LibKa0s, and pushing LootHistory, are outward-facing: each such step below is marked ⚠ CONFIRM and must not run without the user's explicit go-ahead at execution time.**
- Commit trailer (both repos):
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt
  ```

## Review Focus

1. **Downsampling bound** — a series of any length draws at most `floor(plotWidth / 2)` points and always keeps its first and last point. Pinned in Task A2 (`chart math: Downsample keeps at most one point per 2px and both endpoints`) and, through the widget, in Task A3 (`line chart: the plot never gets more than one point per 2px`).
2. **Carry-forward** — a holder whose balance did not change inside the range still draws a flat line at the last close recorded **before** the range. Pinned in Task B6 (`Timeline model: DailySeries carries the last close forward`).
3. **Rollup prune keeps carry-forward alive** — pruning old days folds each (holder, thing)'s newest pruned close onto the cutoff day and never overwrites a close already there. Pinned in Task B3 (`Ledger: PruneDaily drops old days and folds each thing's last close onto the cutoff day`).
4. **Line cap and filter order** — Total plus at most `timelineMaxLines` holders, ranked by latest balance, with the Character filter applied **before** the cap (a filtered-in poor holder is never pushed out by a filtered-out rich one). Pinned in Task B6 (`Timeline model: RankHolders applies the Character filter before the cap`, `Timeline model: Build draws Total plus at most maxLines holders`).
5. **Pool recycling** — a second render/refresh with the same data creates **no** new Line objects or pooled frames. Pinned in Task A3 (`line chart: a second Render of the same data creates no new Line objects`) and Task B8 (`Timeline tab: refresh twice recycles Lines and pooled rows`).

## Standards flags (resolve before the named task)

> **Resolved by the user 2026-10-06:** **S1 → (a) record a deviation** (row in LibKa0s `CLAUDE.md` → `## Documented deviations`, added in Task A2's commit). **S3 → re-vendor ALL consumers** after v1.69.0 is tagged (the other ten addons, each via its own re-vendor commit; LootHistory is Task B1). S2 remains an upstream-standard recount to flag at A4.

| # | Where | What | Why it may deviate | Proposed resolution (user decides) |
|---|---|---|---|---|
| S1 | Task A2 (LibKa0s) | `library-stack-§7` "What earns promotion into a Ka0s-owned lib (MUST)", bar 1: **two or more consumers with the same semantics**. The line chart has exactly **one** consumer (LootHistory). | Spec §13 F3 is a user ratification to build it in LibKa0s from the start, but a ratification recorded only in an addon's spec is not in any register. | Either (a) a row in LibKa0s `CLAUDE.md` → `## Documented deviations` (`library-stack-§7` · one consumer at promotion · F3, 2026-10-06 · re-check trigger: a second addon draws a chart, or one release passes with no second consumer named), or (b) an upstream evolution of the standard allowing a single-consumer widget when the owner pre-commits it. **Ask at the start of A2; do not write A2's file until answered.** |
| S2 | Task A4 (LibKa0s release) | The standard's own text, `library-stack-§7` module table: "**fifteen LibStub majors across thirty-two files**" and the Widgets row naming three files. v1.69.0 ships **thirty-three** files and Widgets has **four**. | A change to the standard itself, not to either repo. | Flag to the user at A4: the WowAddonStandards text needs an upstream bump (recount, not increment, as the section demands). Out of scope for this plan's commits. |
| S3 | Task A4 step "re-vendor every consumer" | `library-stack-§7` and LibKa0s `docs/releasing.md` step 8: a change to the lib **MUST** be followed by a re-vendor commit in **every consumer**. This plan re-vendors **LootHistory only** (Task B1). | The other ten consumers do not draw a chart, and the release moves no existing file's minor, so their stale copies keep working, but the rule has no "additive" carve-out. | Ask at A4: run `/dev-copilot:wow-revendor-libka0s` in each of the other ten repos as follow-up work (recommended, separate sessions), or accept the lag knowingly. Do not silently skip. |
| S4 | Task B4 (LootHistory) | Spec §4.3 says the rollup is "written by the reconciler alongside each row". This plan writes **closes from `NS.Holdings`' write methods** and **in/out from `NS.Database:OnWrite`**. | Spec-shape change (not a standard rule): same data, different seam; see "Phase 2 contract" for why. | Record in `docs/data-flow.md` and amend spec §4.3's sentence in Task B11. Ask only if the user wants the Reconciler-call shape instead. |
| S5 | Task B7 (LootHistory) | Spec §8.1: the Timeline pick is "remembered in `savedView`". A pick with no saved view **materializes** `profile.savedView` as a copy of the stock view plus `timelineThing`. | Not a standard rule; it changes when `savedView` first exists (a copy of stock applies identically to stock). | Proceed; documented in `docs/browser.md` and `docs/profiles.md`. |

No other deviation is expected: the popup (`KA0S_LOOTHISTORY_FORGET_HOLDER`) sits beside the existing host-owned confirms in `settings/Slash.lua` (spec F6), both new settings are schema rows, and the General ▸ History tab's single-row exemption in `tests/test_schema.lua` becomes unnecessary (it now holds two rows) and is removed rather than kept stale.

## Phase 2 contract (rollup hook)

**Chosen hook: closes come from `NS.Holdings`' write seam; in/out tallies come from `NS.Database:OnWrite`.** Phase 2's plan already provides the second seam ("Phase 3's rollup registers here"); Phase 3 implements both receivers. Phase 2 must keep these four promises (all hold in the Phase 2 plan as written; they are restated so a later change to Phase 2 knows what it would break):

1. **Every holdings write goes through `NS.Holdings`' methods** — `ApplyContainer`, `ApplyCurrency`, `ApplyMoney` (Phase 1) and `CreditCurrency`, `CreditEscrow` (Phase 2). Phase 3 adds, inside each, a call `NS.Rollup:NoteClose(holder, thingKey, ts, close)` for every thing whose total changed, with `close` read from the store **after** the write. Nothing writes `db.global.holdings[...]` tables directly.
2. **Every IN/OUT/MOVE row is written through `NS.Database:Add` or `NS.Database:Amend`**, which run the `OnWrite` hooks synchronously with the quantity that changed (`deltaQty`) and `isNew`. The receiver is `NS.Rollup:OnWrite(row, deltaQty, isNew)`; it reads only `NS.Util.RowDir/RowKind/RowHolder`, `row.itemID`, `row.currencyID`, `row.ts`. `MOVE` rows tally nothing; an amend tallies only its delta, on the day it happens.
3. **`RECORD_ADDED` stays a repaint signal.** The Timeline listens to it (coalesced) to repaint; nothing in Phase 3 counts it, because Phase 2 re-sends it on every amend.
4. **An inter-holder transfer is a `MOVE` pair, one row per holder**, each with `holder` = that side and `from` / `to` = `"<holder>/<container>"` (Phase 2 `R:WriteRows`). Only the Timeline's intraday (Today / 7 d) reconstruction reads this, and it falls back to daily points whenever the rebuilt balance disagrees with the rollup, so a violation degrades the resolution rather than drawing a wrong line.

**Why this shape rather than a single Reconciler call:** (a) the close is a holdings fact, and `NS.Holdings`' write methods are the only place a total changes, so they see every change exactly once — genesis (the first scan writes every thing's first close), login drift, intra-holder moves, both sides of a transfer, escrow credits — with no knowledge of the Reconciler's scan → plan → commit internals; (b) a chat-path row (`Collector`) is written **before** the Reconciler commits the matching delta, so a close read at write time would be stale, while the tally of that same row is exactly right; (c) the row hook is synchronous and carries the delta, so an amended row is counted once per delta (counting `RECORD_ADDED` would count an amended row's whole quantity again). Both receivers are O(1) per change. If the user prefers the spec's literal "Reconciler writes it" shape, the swap is local: delete the `noteClose` calls in `modules/Holdings.lua` and have the Reconciler's commit step call `NS.Rollup:NoteClose(holder, key, ts, close)` per committed holder/thing instead; nothing else in this plan moves.

---

## File Structure

### Part A — LibKa0s (`/mnt/d/Profile/Users/Tushar/Documents/GIT/LibKa0s`)

| File | Status | Responsibility |
|---|---|---|
| `testkit/mock_lines.lua` | Create | Kit revision 37: `CreateLine` on every tracked frame answers a distinct, recording Line object. |
| `testkit/mock_base.lua` | Modify (+2 lines) | Load `mock_lines.lua`; decorate every tracked frame. |
| `testkit/framework.lua` | Modify | `Kit.VERSION = 37`. |
| `testkit/README.md` | Modify | File-table row and "vendor as one folder" sentence name `mock_lines.lua`. |
| `tests/_kit/` | Re-vendor | Byte copy of `testkit/` (`tests/test_kitsync.lua`). |
| `tests/test_mock_lines.lua` | Create | The Line mock's own cases. |
| `tests/test_kit_inventory.lua` | Modify | Pins revision 37. |
| `LibKa0s/WidgetsLineChart.lua` | Create | `lib.LINE_CHART`, `lib.ChartMath`, `lib.LineChart` (CHART_MINOR 1). |
| `LibKa0s/LibKa0s.xml` | Modify | `<Script file="WidgetsLineChart.lua"/>` after `WidgetsDragHandle.lua`. |
| `tests/majors.lua` | Modify | Widgets row: fourth file + `paired` entry. |
| `tests/test_widgets_linechart_math.lua` | Create | Pure math cases. |
| `tests/test_widgets_linechart.lua` | Create | Widget cases (pool, mapping, dashes, markers, hover). |
| `tests/run.lua` | Modify | Declare the three new suites. |
| `docs/api/Widgets/version-12.1.4.1-docs.md` | Create | Current Widgets document. |
| `docs/api/Widgets/version-12.1.4-docs.md` | Modify | Superseded + "Moving to 12.1.4.1". |
| `docs/api/Widgets/members-12.1.4.1.json` | Generate | `lua tools/gen-api-members.lua`. |
| `docs/api/testkit/version-37-docs.md`, `version-36-docs.md` | Create / Modify | Kit document; 36 superseded. |
| `docs/api/README.md` | Modify | Widgets 12.1.4.1 and testkit 37 rows. |
| `CHANGELOG.md` | Modify | `## v1.69.0` block (needles `WidgetsLineChart minor 1`, `test kit revision 37`) + release-gate line. |
| `docs/releasing.md` | Modify | Thirty-three files, `CHART_MINOR` in both constant lists, provenance template v1.69.0, Widgets MODULES line, Consumers row. |
| `README.md` | Modify | Widgets module row (files, key 12.1.4.1, LineChart sentence), test badge. |
| `docs/test-cases.md` | Regenerate | — |
| `docs/automated-tests/<stamp>/` | Generate | Release record + `ANALYSIS.md`. |
| `docs/api/CONSUMERS.md` | Modify (Task B10) | LootHistory's `NS.MakeLineChart` consumer row. |

### Part B — LootHistory (`/mnt/d/Profile/Users/Tushar/Documents/GIT/LootHistory`)

| File | Status | Responsibility |
|---|---|---|
| `libs/LibKa0s/`, `tests/_kit/` | Re-vendor | v1.69.0 bytes (kit 37). |
| `CLAUDE.md` | Modify | Provenance line → v1.69.0 (same commit as the bytes). |
| `docs/debug.md` | Modify | "vendored set, from LibKa0s v1.69.0" stamp. |
| `docs/revendor/2026-10-06-v1.69.0/` | Create | Frozen re-vendor bundle (`01_DELTA.md`, `02_CANDIDATES.md`, `05_SUMMARY.md`). |
| `tests/test_libka0s.lua` | Modify | `LIB_FILES` gains `libs/LibKa0s/WidgetsLineChart.lua`. |
| `core/WidgetsSetup.lua` | Modify | `NS.MakeLineChart(parent, opts)` seam. |
| `tests/test_widgets.lua` | Modify | Seam cases. |
| `core/Ledger.lua` | Modify | `DayKey`, `RowThingKey`, `RollupClose`, `RollupFlow`, `PruneDaily`, `ForgetHolderDaily`. |
| `modules/Rollup.lua` | Create | Rollup writer: closes, tallies, amend, seed, prune, forget, key index; lifecycle. |
| `modules/Holdings.lua` | Modify | `noteClose` in `ApplyContainer` / `ApplyCurrency` / `ApplyMoney` (Phase 1) and `CreditCurrency` / `CreditEscrow` (Phase 2); `meta.completeAt`; `Holdings:Describe(key)`. |
| `modules/Reconciler.lua` | Modify | `R:ForgetHolder(holder)` (sole `HOLDINGS_CHANGED` sender stays the Reconciler). |
| `core/Constants.lua` | Modify | `ROLLUP_RETENTION_OPTIONS`, `TIMELINE` colors/widths. |
| `defaults/Global.lua`, `defaults/Profile.lua` | Modify | `rollupRetentionDays = 0`; `settings.timelineMaxLines = 8`. |
| `settings/Schema.lua` | Modify | Rows `settings.rollupRetentionDays` (global-stored) and `settings.timelineMaxLines`; `RESET_EXEMPT` entry. |
| `settings/Slash.lua` | Modify | `KA0S_LOOTHISTORY_FORGET_HOLDER` popup. |
| `core/LootHistory.lua` | Modify | Login deferral: `Rollup:SeedOnce` + `Rollup:Prune`. |
| `core/Util.lua` | Modify | `RangeFrom("90d" / "1y")`. |
| `modules/TimelineModel.lua` | Create | Pure model: day walk, carry-forward, ranking, totals, flows, intraday, hover, suggestions, chart data. |
| `modules/Timeline.lua` | Create | Timeline tab view (order 30). |
| `modules/Browser.lua` | Modify | Date options 90 d / 1 y; per-tab filter graying; holders Character list; `DateRange`, `SetViewField`, `ViewField`, `ShowTimeline`; export button handle. |
| `modules/BrowserTable.lua` | Modify | `RowMenuItems(record)` / `ShowMenu(anchor, items)` split; "Show in Timeline". |
| `modules/HoldingsTab.lua` | Modify | `filters` + `charSource` on its tab spec; `HT.RowActions(line)`; right-click menu. |
| `core/LifecycleSetup.lua` | Modify | StandUp/StandDown include `NS.Rollup`, `NS.Timeline`. |
| `LootHistory.toc` | Modify | `modules\Rollup.lua` after `modules\Holdings.lua`; `modules\TimelineModel.lua`, `modules\Timeline.lua` after `modules\HoldingsTab.lua`. |
| `tests/test_ledger.lua`, `tests/test_util.lua`, `tests/test_browser.lua`, `tests/test_browsertable.lua`, `tests/test_holdingstab.lua`, `tests/test_schema.lua`, `tests/test_disabled.lua` | Modify | New cases / pins. |
| `tests/test_rollup.lua`, `tests/test_timeline.lua`, `tests/test_timelinetab.lua` | Create | Suites. |
| `tests/run.lua` | Modify | Register the three suites. |
| docs (`scope.md`, `schema.md`, `module-map.md`, `message-bus.md`, `data-flow.md`, `browser.md`, `profiles.md`, `settings-panel.md`, `disabled-state.md`, `ARCHITECTURE.md`, `smoke-tests.md`, `test-cases.md`), `README.md`, spec §4.3 sentence | Modify | Task B11. |

---

# Part A — LibKa0s repo

All Part A commands run from `/mnt/d/Profile/Users/Tushar/Documents/GIT/LibKa0s`. Its suites read `_G.LK_TEST` (`T.test`, `T.assertEqual`, `T.assertTrue`, `T.assertFalse`, `T.mocks`, `T.widgets`).

### Task A1: Kit revision 37 — Line regions in the mock

**Files:**
- Create: `testkit/mock_lines.lua`
- Modify: `testkit/mock_base.lua:79` (one `loadRecorder` line after the `Resize` line) and `:1042` (one `Lines.decorateFrame(f)` line after `Resize.decorateFrame(f)` in `trackFrame`)
- Modify: `testkit/framework.lua:20` (`Kit.VERSION = 37`)
- Modify: `testkit/README.md` (file table row after `mock_resize.lua`; the "They vendor as one folder" sentence)
- Create: `tests/test_mock_lines.lua`; Modify: `tests/run.lua:92` (add `"test_mock_lines"` after `"test_mock_resize"`)
- Modify: `tests/test_kit_inventory.lua:340-342` (revision 37)
- Create: `docs/api/testkit/version-37-docs.md`; Modify: `docs/api/testkit/version-36-docs.md` (Superseded), `docs/api/README.md` (testkit row)
- Modify: `CHANGELOG.md` (open the `## v1.69.0 — 2026-10-06` block; Task A4 re-dates it if the tag lands later)
- Re-vendor: `tests/_kit/` from `testkit/`

**Interfaces:**
- Consumes: `mock_base.lua`'s `loadRecorder(name)` and `trackFrame(f)`.
- Produces:
  - `Lines.decorateFrame(f)` (kit-internal), giving every tracked frame `f:CreateLine(name, layer, template, sublevel) -> line` and the recorder list `f.__madeLines` (creation order).
  - Line object methods: `Show`, `Hide`, `SetShown(v)`, `IsShown()`, `SetStartPoint(relPoint, relTo, x, y)`, `GetStartPoint() -> relPoint, relTo, x, y`, `SetEndPoint(...)`, `GetEndPoint()`, `SetThickness(n)`, `GetThickness()`, `SetColorTexture(r, g, b, a)`, `SetVertexColor(r, g, b, a)`, `SetTexture(path)`, `SetAlpha(a)`, `GetAlpha()`, `SetDrawLayer(layer, sub)`, `ClearAllPoints()`; recorder fields `__start`, `__end`, `__thickness`, `__color`, `__shown`, `__layer`. Any other capitalized method **raises** naming itself (fidelity rule 1).
  - `Kit.VERSION == 37`.

- [ ] **Step 1: Write the failing test** — `tests/test_mock_lines.lua`

```lua
-- tests/test_mock_lines.lua — the kit's Line regions (revision 37, testkit/mock_lines.lua).
--
-- Through revision 36 `CreateLine` answered from mock_base.lua's metatable, which hands back THE
-- FRAME: every line a chart drew was the same object as its parent, and SetStartPoint / SetEndPoint
-- were silent no-ops, so no suite could tell a drawn segment from a missing one (fidelity rules 1
-- and 3). Each case below is red on revision 36 for the reason its comment names.
--
-- Every case builds a fresh mock, for the reason `tests/test_mock_record.lua` gives.

local T = _G.LK_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local buildMocks = dofile("tests/wow_mock.lua")

test("line mock: CreateLine answers a distinct object per call, recorded on its frame", function()
  -- red under: revision 36, where CreateLine answered the frame itself
  local f = buildMocks().CreateFrame("Frame")
  local a, b = f:CreateLine(nil, "ARTWORK"), f:CreateLine()
  assertTrue(a ~= f and b ~= f and a ~= b, "two calls, two lines, neither the frame")
  assertEqual(#f.__madeLines, 2)
  assertTrue(f.__madeLines[1] == a and f.__madeLines[2] == b, "recorded in creation order")
  assertEqual(a.__layer, "ARTWORK")
end)

test("line mock: start, end, thickness and color are answered back", function()
  -- red under: revision 36, where every setter was a no-op and every getter answered the frame
  local l = buildMocks().CreateFrame("Frame"):CreateLine()
  l:SetStartPoint("BOTTOMLEFT", nil, 3, 4)
  l:SetEndPoint("BOTTOMLEFT", nil, 10, 12)
  l:SetThickness(2)
  l:SetColorTexture(1, 0, 0, 0.5)
  local p, _, x, y = l:GetStartPoint()
  assertEqual(p, "BOTTOMLEFT"); assertEqual(x, 3); assertEqual(y, 4)
  local _, _, x2, y2 = l:GetEndPoint()
  assertEqual(x2, 10); assertEqual(y2, 12)
  assertEqual(l:GetThickness(), 2)
  assertEqual(l.__color[1], 1); assertEqual(l.__color[4], 0.5)
end)

test("line mock: a new line is shown, and Hide / Show / SetShown are tracked", function()
  local l = buildMocks().CreateFrame("Frame"):CreateLine()
  assertTrue(l:IsShown(), "a new region is shown, as in the client")
  l:Hide(); assertFalse(l:IsShown())
  l:SetShown(true); assertTrue(l:IsShown())
end)

test("line mock: ClearAllPoints forgets both ends", function()
  local l = buildMocks().CreateFrame("Frame"):CreateLine()
  l:SetStartPoint("CENTER", nil, 1, 1); l:SetEndPoint("CENTER", nil, 2, 2)
  l:ClearAllPoints()
  assertEqual(l:GetStartPoint(), nil); assertEqual(l:GetEndPoint(), nil)
end)

test("line mock: an unmodeled method raises instead of silently succeeding", function()
  -- Fidelity rule 1: a Line is not a Frame, and a call the client would not answer must not pass.
  local l = buildMocks().CreateFrame("Frame"):CreateLine()
  local ok, err = pcall(function() l:SetScript("OnUpdate", function() end) end)
  assertFalse(ok, "a Line has no SetScript in the client")
  assertTrue(tostring(err):find("SetScript", 1, true) ~= nil, "the error names the method")
end)
```

In `tests/test_kit_inventory.lua` change the revision pin:

```lua
test("the kit is revision 37", function()
  assertEqual(Kit.VERSION, 37, "v1.69.0 ships revision 37, whose mock answers Line regions")
  assertEqual(T.KIT_VERSION, 37, "and `Kit.expose` publishes it to every consumer")
end)
```

Add `"test_mock_lines"` after `"test_mock_resize"` in `tests/run.lua`'s suite list.

- [ ] **Step 2: Run to verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -E "line mock|kit is revision|FAIL" | head -20`
Expected: FAIL — `line mock:` cases fail (`f.__madeLines` is nil; `a ~= f` false) and `the kit is revision 37` fails (36).

- [ ] **Step 3: Implement** — `testkit/mock_lines.lua`

```lua
-- testkit/mock_lines.lua — Line regions (revision 37).
--
-- LibKa0s v1.69.0 ships a line chart (`LibKa0s-Widgets-1.0`'s `WidgetsLineChart.lua`) that draws
-- every segment, grid rule and crosshair as a `Line` from `Region:CreateLine`. Through revision 36
-- `CreateLine` answered from `mock_base.lua`'s metatable, which hands back the frame itself, so a
-- chart's hundred segments were one object and every endpoint it set was dropped (fidelity rules
-- 1 and 3).
--
-- What is modeled, and the client behavior each one follows:
--
--   * `CreateLine` answers a NEW object per call, recorded in creation order on the frame that
--     made it (`f.__madeLines`), so a suite can count what a render created and see that a second
--     render created nothing.
--   * The two ends are recorded as given (`relativePoint, relativeTo, x, y`) and answered back by
--     `GetStartPoint` / `GetEndPoint`; `ClearAllPoints` forgets both, as it does on a Region.
--   * Thickness, color, texture, alpha and draw layer are recorded.
--   * A new line is SHOWN, as a new region is in the client (and as `mock_base.lua` makes frames).
--
-- What is NOT modeled, deliberately: a Line is not a Frame. It has no scripts, no mouse, no
-- children and no geometry of its own, so any capitalized method this file does not define RAISES,
-- naming itself. A chart that called `SetScript` on a line would fail in the client; it fails here.
--
-- Loaded by `mock_base.lua` from its own folder, like `mock_resize.lua`, and a file of its own for
-- the same reason: `mock_base.lua` sits near `layout-§1`'s 1500-line cap. It answers one function,
-- `decorateFrame(f)`, which every tracked frame passes through as it is made.

local Lines = {}

local LINE_METHODS = {}

function LINE_METHODS:Show() self.__shown = true end
function LINE_METHODS:Hide() self.__shown = false end
function LINE_METHODS:SetShown(v) self.__shown = not not v end
function LINE_METHODS:IsShown() return self.__shown end
function LINE_METHODS:SetStartPoint(relPoint, relTo, x, y) self.__start = { relPoint, relTo, x or 0, y or 0 } end
function LINE_METHODS:SetEndPoint(relPoint, relTo, x, y) self.__end = { relPoint, relTo, x or 0, y or 0 } end
function LINE_METHODS:GetStartPoint()
  local s = self.__start
  if not s then return nil end
  return s[1], s[2], s[3], s[4]
end
function LINE_METHODS:GetEndPoint()
  local e = self.__end
  if not e then return nil end
  return e[1], e[2], e[3], e[4]
end
function LINE_METHODS:ClearAllPoints() self.__start, self.__end = nil, nil end
function LINE_METHODS:SetThickness(t) self.__thickness = t end
function LINE_METHODS:GetThickness() return self.__thickness end
function LINE_METHODS:SetColorTexture(r, g, b, a) self.__color = { r, g, b, a or 1 } end
function LINE_METHODS:SetVertexColor(r, g, b, a) self.__vertex = { r, g, b, a or 1 } end
function LINE_METHODS:SetTexture(path) self.__texture = path end
function LINE_METHODS:SetAlpha(a) self.__alpha = a end
function LINE_METHODS:GetAlpha() return self.__alpha or 1 end
function LINE_METHODS:SetDrawLayer(layer, sub) self.__layer, self.__sublevel = layer, sub end

local LINE_META = {
  __index = function(_, key)
    local m = LINE_METHODS[key]
    if m then return m end
    if type(key) == "string" and key:match("^%u") then
      error("testkit: a Line has no " .. key .. " -- model it in testkit/mock_lines.lua if the "
        .. "client answers it, or stop calling it on a Line", 2)
    end
    return nil
  end,
}

local function newLine(owner, layer)
  return setmetatable({ __owner = owner, __layer = layer, __shown = true, __thickness = 1 }, LINE_META)
end

--- Give one frame the recording `CreateLine`. Plain field `__madeLines`, so a suite reads it directly.
function Lines.decorateFrame(f)
  f.__madeLines = {}
  function f:CreateLine(_, layer)
    local l = newLine(self, layer)
    self.__madeLines[#self.__madeLines + 1] = l
    return l
  end
end

return Lines
```

`testkit/mock_base.lua` — after line 79 (`local Resize = loadRecorder("mock_resize.lua") ...`):

```lua
local Lines = loadRecorder("mock_lines.lua")    -- Line regions from CreateLine (revision 37)
```

and in `trackFrame`, after `Resize.decorateFrame(f)`:

```lua
    Lines.decorateFrame(f)
```

`testkit/framework.lua:20`: `Kit.VERSION = 37`.

`testkit/README.md`: add the row after `mock_resize.lua`:

```markdown
| `mock_lines.lua` | Line regions: `CreateLine` on every tracked frame answers a distinct, recording Line (`__madeLines` on the frame; both ends, thickness, color and shown state answered back), and any method a Line does not have raises; `mock_base.lua` loads it from its own folder (kit revision 37) |
```

and add `mock_lines.lua` to the "They vendor as one folder. A copy that leaves out …" list.

`docs/api/testkit/version-37-docs.md`: copy `version-36-docs.md`; set the title to version 37, `Payload` adds `mock_lines.lua` after `mock_resize.lua`, `Version` **37**, `First released in` v1.69.0, `Status` **Current**, `Supersedes` [version 36](version-36-docs.md) — no Line regions, `Confirm in a consumer` → `37`; replace the lead paragraph and `## What changed` with: one file added (`mock_lines.lua`), two lines in `mock_base.lua`, `Kit.VERSION` 37, no public member renamed or removed, five kit-owned cases are **not** added (the cases live in this repo's `tests/test_mock_lines.lua`), a consumer's own suites that called `CreateLine` on a stub and relied on getting the frame back now get a Line (none in the collection does: `grep -rn CreateLine ../*/modules ../*/core` printed nothing on 2026-10-06), and "**What a consumer owes:** the whole-folder copy." In `version-36-docs.md`: `Status` → Superseded, `Superseded by` → [version 37](version-37-docs.md), and a closing `## Moving to 37` section ("Copy the kit whole. A suite that counts frames is unaffected: a Line is not a frame and is not tracked as one."). Add the revision-37 row to `docs/api/README.md`'s testkit table (Current) and mark 36 Superseded.

`CHANGELOG.md` — insert above `## v1.68.1`:

```markdown
## v1.69.0 — 2026-10-06

Versions in this release: **test kit revision 37**.

### Test kit revision 37: Line regions

- **`mock_lines.lua`** (new): `CreateLine` on every tracked frame answers a distinct Line that
  records both ends, thickness, color and shown state, listed on its frame as `__madeLines`; a
  method a Line does not have raises. `mock_base.lua` loads it (two lines).
- `Kit.VERSION` is 37. Documented in [`docs/api/testkit/version-37-docs.md`](docs/api/testkit/version-37-docs.md);
  revision 36 is Superseded.
- **What a consumer owes:** the whole-folder copy of both payloads and the provenance line.
```

Re-vendor the kit into this repo's own copy:

```bash
cp -r testkit/. tests/_kit/
diff -r --strip-trailing-cr testkit tests/_kit   # must print nothing
```

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: `0 failed` (the five `line mock:` cases and `the kit is revision 37` pass; `test_kitsync` passes after the copy); luacheck `0 warnings / 0 errors`. If any existing suite relied on `CreateLine` answering the frame, it now raises naming the method — none does today (`grep -rn "CreateLine" LibKa0s tests --include=*.lua | grep -v _kit` prints only the new files).

- [ ] **Step 5: Regenerate inventory and commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
# README.md: set the Tests badge to the new `## Totals` figure from docs/test-cases.md
git add testkit/mock_lines.lua testkit/mock_base.lua testkit/framework.lua testkit/README.md tests/_kit \
  tests/test_mock_lines.lua tests/test_kit_inventory.lua tests/run.lua docs/api/testkit/version-37-docs.md \
  docs/api/testkit/version-36-docs.md docs/api/README.md CHANGELOG.md docs/test-cases.md README.md
git commit -m "$(cat <<'EOF'
TL-LK-01: kit revision 37 - the mock answers Line regions (mock_lines.lua)

CreateLine on every tracked frame now answers a distinct recording Line
(__madeLines on the frame; ends, thickness, color, shown state answered back;
an unmodeled method raises). mock_base.lua gains two lines. Re-vendored into
tests/_kit/.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt
EOF
)"
```

---

### Task A2: `WidgetsLineChart.lua` — the pairing guard and the chart math

> **Standards flag S1 — RESOLVED (a), 2026-10-06: record a deviation.** Add the row to `## Documented deviations` in this task's commit and update the "**Five rows.**" paragraph under it to six.

**Files:**
- Create: `LibKa0s/WidgetsLineChart.lua`
- Modify: `LibKa0s/LibKa0s.xml` (after `<Script file="WidgetsDragHandle.lua"/>`)
- Modify: `tests/majors.lua` (the `LibKa0s-Widgets-1.0` row)
- Create: `tests/test_widgets_linechart_math.lua`; Modify: `tests/run.lua:81` (add `"test_widgets_linechart_math"` after `"test_widgets_draghandle_place"`)
- Create: `docs/api/Widgets/version-12.1.4.1-docs.md`; Modify: `docs/api/Widgets/version-12.1.4-docs.md`, `docs/api/README.md`
- Generate: `docs/api/Widgets/members-12.1.4.1.json`
- Modify: `CHANGELOG.md` (v1.69.0 block)

**Interfaces:**
- Consumes: the Widgets shell (`LibStub("LibKa0s-Widgets-1.0", true)`, `lib.MINOR`, `lib.MODULES`); globals `date`, `time`.
- Produces:
  - `lib.__chartMinor = 1`, `lib.__chartShellMinor = lib.MINOR`, `lib.MODULES.WidgetsLineChart = 1` (version key 12.1.4.1).
  - `lib.LINE_CHART = { PAD_LEFT=52, PAD_RIGHT=8, PAD_TOP=8, PAD_BOTTOM=18, PX_PER_POINT=2, DASH=4, GAP=3, Y_TICKS=5, X_TICKS=6, LABEL_GAP=4, AXIS={..}, GRID={..}, CROSSHAIR={..}, MARKER={..}, LINE={..} }`
  - `lib.ChartMath.NiceTicks(lo, hi, maxTicks, integer) -> ticks, niceLo, niceHi, step`
  - `lib.ChartMath.Budget(plotWidth) -> maxPoints` (`max(3, floor(w / PX_PER_POINT))`)
  - `lib.ChartMath.Downsample(points, maxPoints) -> points` (LTTB; the input table itself when it already fits; `points` are `{x=, y=}` sorted by x)
  - `lib.ChartMath.TimeTicks(xMin, xMax, maxTicks) -> ticks, step` (step from 1 h … 365 d; day steps land on local midnight)
  - `lib.ChartMath.NearestIndex(xs, x) -> index|nil`
  - `lib.ChartMath.Dashes(x1, y1, x2, y2, dash, gap) -> { {x1, y1, x2, y2}, ... }`

- [ ] **Step 1: Write the failing test** — `tests/test_widgets_linechart_math.lua`

```lua
-- tests/test_widgets_linechart_math.lua — LibKa0s-Widgets-1.0: the line chart's pure math.
--
-- Everything the chart decides without a frame -- where the y ticks go, how a long series is
-- thinned to the pixels it has, where the time labels land, which x a cursor is nearest, how a
-- dashed segment is cut -- lives in `lib.ChartMath` so it is pinned here headless, with no geometry
-- stub at all. tests/test_widgets_linechart.lua pins what the widget DRAWS from it.

local T = _G.LK_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local mocks = T.mocks
local W = T.widgets
local function M() return W.ChartMath end

test("chart math: the file attaches to the Widgets shell and records its minor", function()
  assertEqual(W.MODULES.WidgetsLineChart, 1)
  assertEqual(W.__chartMinor, 1)
  assertEqual(W.__chartShellMinor, W.MINOR, "paired on the shell's minor, as WidgetsDragHandle is")
end)

test("chart math: NiceTicks picks a 1-2-2.5-5 step and covers the data", function()
  local ticks, lo, hi, step = M().NiceTicks(0, 97, 5)
  assertEqual(step, 20); assertEqual(lo, 0); assertEqual(hi, 100)
  assertEqual(#ticks, 6); assertEqual(ticks[1], 0); assertEqual(ticks[6], 100)
  ticks, lo, hi, step = M().NiceTicks(13, 47, 5)
  assertEqual(step, 10); assertEqual(lo, 10); assertEqual(hi, 50); assertEqual(#ticks, 5)
end)

test("chart math: NiceTicks widens a flat or empty range instead of dividing by zero", function()
  local ticks, lo, hi = M().NiceTicks(5, 5, 5)
  assertEqual(lo, 0); assertEqual(hi, 5); assertEqual(#ticks, 6)
  ticks, lo, hi = M().NiceTicks(0, 0, 5, true)
  assertEqual(lo, 0); assertEqual(hi, 1); assertEqual(#ticks, 2)
  ticks, lo, hi = M().NiceTicks(nil, nil, 5)
  assertEqual(lo, 0); assertTrue(hi > 0 and #ticks >= 2)
end)

test("chart math: NiceTicks with integer=true never steps below 1", function()
  local _, _, _, step = M().NiceTicks(0, 2, 5)
  assertEqual(step, 0.5)
  _, _, _, step = M().NiceTicks(0, 2, 5, true)
  assertEqual(step, 1)
end)

test("chart math: NiceTicks handles a range that crosses zero", function()
  local _, lo, hi, step = M().NiceTicks(-30, 70, 5)
  assertEqual(step, 20); assertEqual(lo, -40); assertEqual(hi, 80)
end)

test("chart math: Downsample keeps at most one point per 2px and both endpoints", function()
  -- Review Focus 1
  local pts = {}
  for i = 1, 1000 do pts[i] = { x = i, y = (i % 7) * 10 } end
  local n = M().Budget(200)
  assertEqual(n, 100, "200px holds 100 points at 2px each")
  local out = M().Downsample(pts, n)
  assertEqual(#out, 100)
  assertTrue(out[1] == pts[1] and out[#out] == pts[1000], "first and last points survive")
  for i = 2, #out do assertTrue(out[i].x > out[i - 1].x, "x stays strictly increasing") end
end)

test("chart math: Downsample hands a series that already fits back untouched", function()
  local pts = { { x = 1, y = 1 }, { x = 2, y = 5 } }
  assertTrue(M().Downsample(pts, 100) == pts, "same table, no copy")
end)

test("chart math: Downsample keeps a one-point spike", function()
  local pts = {}
  for i = 1, 500 do pts[i] = { x = i, y = 0 } end
  pts[250].y = 1000
  local peak = 0
  for _, p in ipairs(M().Downsample(pts, 50)) do if p.y > peak then peak = p.y end end
  assertEqual(peak, 1000, "a balance spike must not be averaged away")
end)

test("chart math: Budget never answers fewer than three points", function()
  assertEqual(M().Budget(0), 3); assertEqual(M().Budget(3), 3)
end)

test("chart math: TimeTicks lands day steps on local midnight", function()
  local x0 = mocks.time({ year = 2026, month = 10, day = 1, hour = 0 })
  local ticks, step = M().TimeTicks(x0, x0 + 30 * 86400, 6)
  assertEqual(step, 7 * 86400)
  assertEqual(#ticks, 5)
  for _, t in ipairs(ticks) do assertEqual(mocks.date("*t", t).hour, 0) end
end)

test("chart math: TimeTicks uses hour steps inside one day", function()
  local x0 = mocks.time({ year = 2026, month = 10, day = 1, hour = 0 })
  local ticks, step = M().TimeTicks(x0, x0 + 86400, 6)
  assertEqual(step, 6 * 3600)
  assertEqual(#ticks, 5)
  assertEqual(mocks.date("*t", ticks[2]).hour, 6)
end)

test("chart math: TimeTicks answers nothing for an empty span", function()
  local ticks, step = M().TimeTicks(100, 100, 6)
  assertEqual(#ticks, 0); assertEqual(step, nil)
end)

test("chart math: NearestIndex snaps to the closest x and clamps at the ends", function()
  local xs = { 0, 10, 20, 30 }
  assertEqual(M().NearestIndex(xs, -5), 1)
  assertEqual(M().NearestIndex(xs, 14), 2)
  assertEqual(M().NearestIndex(xs, 16), 3)
  assertEqual(M().NearestIndex(xs, 99), 4)
  assertEqual(M().NearestIndex({}, 3), nil)
end)

test("chart math: Dashes cuts a segment into dash-gap pieces along its length", function()
  local d = M().Dashes(0, 0, 20, 0, 4, 3)
  assertEqual(#d, 3)
  assertEqual(d[1][1], 0); assertEqual(d[1][3], 4)
  assertEqual(d[3][1], 14); assertEqual(d[3][3], 18)
  local v = M().Dashes(0, 0, 0, 10, 4, 3)
  assertEqual(#v, 2)
  assertEqual(v[2][4], 10, "the last dash is clipped at the segment's end")
  assertEqual(#M().Dashes(5, 5, 5, 5, 4, 3), 0, "a zero-length segment has no dashes")
end)
```

Add `"test_widgets_linechart_math"` to `tests/run.lua` after `"test_widgets_draghandle_place"`.

- [ ] **Step 2: Run to verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -E "chart math|FAIL" | head`
Expected: FAIL — `W.ChartMath` is nil (`attempt to index a nil value`), `W.MODULES.WidgetsLineChart` is nil.

- [ ] **Step 3: Implement** — `LibKa0s/WidgetsLineChart.lua` (math half; Task A3 appends the widget)

```lua
-- LibKa0s-Widgets-1.0 -- the line chart: one or more series of points drawn as Line regions over
-- a time axis, with auto-scaled y ticks, a dashed vertical marker, a dashed-range style for a part
-- of a series the host wants read as provisional, and a hover crosshair that reports the nearest x.
--
-- -- WHY IT IS A FILE OF ITS OWN AND NOT MORE OF Widgets.lua ------------------------------------
--
-- For the reason WidgetsDragHandle.lua gives: one file per widget keeps each under layout-1's
-- 1500-line cap, and a secondary file paired on the SHELL's minor cannot attach to a shell from
-- another vendored copy without saying so. It is not a major of its own: a new major would cost a
-- setup seam in every consumer, and only one draws a chart today.
--
-- -- WHY THE MATH IS PUBLISHED ------------------------------------------------------------------
--
-- Everything decided without a frame -- the tick ladder, the thinning, the time labels, the
-- nearest x, the dash cutting -- is on `lib.ChartMath`, so a library suite pins it with no geometry
-- stub and a host can line its own decorations (a bar strip under the plot) up with the same
-- numbers rather than restating them.
--
-- -- WHAT THE HOST STILL OWNS -------------------------------------------------------------------
--
-- Every string and color it passes, where the chart sits, when it is shown, what a hover means
-- (the widget reports an index; the host draws its own tooltip) and every unit conversion: the
-- widget plots the numbers it is handed.
--
-- Depends on LibStub and on the Widgets shell, and on no addon framework. Reads the client's
-- `date` and `time` for the time axis.

local lib = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
if not lib then return end

local CHART_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own, as WidgetsDragHandle.lua is: a chart that
-- attached to an older shell would publish `lib.LineChart` beside a `lib.MODULES` the shell owns,
-- and nothing would say the two came from different vendored copies.
if lib.__chartMinor and lib.__chartMinor >= CHART_MINOR
  and lib.__chartShellMinor == lib.MINOR then return end
lib.__chartMinor      = CHART_MINOR
lib.__chartShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.WidgetsLineChart = CHART_MINOR

local floor, ceil, max, min, abs, sqrt = math.floor, math.ceil, math.max, math.min, math.abs, math.sqrt
local log10 = math.log10
local DAY = 86400

--- The chart's published chrome. READ, never restated: a host that lines anything up with the plot
--- reads the paddings here (or asks `chart:GetPlotRect()`), so a later minor that moves them moves
--- the host too.
lib.LINE_CHART = {
  PAD_LEFT = 52, PAD_RIGHT = 8, PAD_TOP = 8, PAD_BOTTOM = 18,
  PX_PER_POINT = 2, DASH = 4, GAP = 3, Y_TICKS = 5, X_TICKS = 6, LABEL_GAP = 4,
  AXIS = { 0.45, 0.45, 0.5, 0.8 }, GRID = { 1, 1, 1, 0.07 }, CROSSHAIR = { 1, 1, 1, 0.35 },
  MARKER = { 0.8, 0.8, 0.8, 0.6 }, LINE = { 0.4, 0.6, 0.95, 1 },
}
local LC = lib.LINE_CHART

local Math = {}
lib.ChartMath = Math

-- -- y ticks: the 1 / 2 / 2.5 / 5 ladder -------------------------------------------------------

local function niceStep(span, maxTicks)
  local raw = span / max(1, maxTicks)
  local mag = 10 ^ floor(log10(raw))
  local norm = raw / mag
  if norm <= 1 then return mag end
  if norm <= 2 then return 2 * mag end
  if norm <= 2.5 then return 2.5 * mag end
  if norm <= 5 then return 5 * mag end
  return 10 * mag
end

-- A flat series still needs a span to divide by. A positive flat line is drawn from zero, a
-- negative one up to zero, and an all-zero one over 0..1, so the line sits on a real axis rather
-- than on a degenerate one.
local function widenFlat(lo, hi)
  if hi ~= lo then return lo, hi end
  if lo > 0 then return 0, hi end
  if lo < 0 then return lo, 0 end
  return 0, 1
end

function Math.NiceTicks(lo, hi, maxTicks, integer)
  lo, hi = lo or 0, hi or 0
  if hi < lo then lo, hi = hi, lo end
  lo, hi = widenFlat(lo, hi)
  local step = niceStep(hi - lo, maxTicks or LC.Y_TICKS)
  if integer and step < 1 then step = 1 end
  local niceLo, niceHi = floor(lo / step) * step, ceil(hi / step) * step
  local ticks, n = {}, floor((niceHi - niceLo) / step + 0.5)
  for k = 0, n do ticks[k + 1] = niceLo + k * step end
  return ticks, niceLo, niceHi, step
end

-- -- thinning: Largest-Triangle-Three-Buckets ----------------------------------------------------
--
-- A balance line is mostly flat with steps and spikes, and a spike is the thing a player is looking
-- for. Averaging or taking every Nth point erases it; LTTB keeps, per bucket, the point that spans
-- the largest triangle with its neighbors, so a one-point spike survives (pinned).

function Math.Budget(plotWidth)
  return max(3, floor((plotWidth or 0) / LC.PX_PER_POINT))
end

local function bucketAverage(points, from, to)
  local ax, ay, n = 0, 0, 0
  for j = from, to - 1 do
    ax, ay, n = ax + points[j].x, ay + points[j].y, n + 1
  end
  if n == 0 then
    local p = points[#points]
    return p.x, p.y
  end
  return ax / n, ay / n
end

local function largestTriangle(points, pa, from, to, ax, ay)
  local best, bestArea = from, -1
  for j = from, to - 1 do
    local p = points[j]
    local area = abs((pa.x - ax) * (p.y - pa.y) - (pa.x - p.x) * (ay - pa.y))
    if area > bestArea then best, bestArea = j, area end
  end
  return best
end

function Math.Downsample(points, maxPoints)
  local n = #points
  if maxPoints >= n or maxPoints < 3 then return points end
  local out, every, a = { points[1] }, (n - 2) / (maxPoints - 2), 1
  for i = 0, maxPoints - 3 do
    local ax, ay = bucketAverage(points, floor((i + 1) * every) + 2, min(floor((i + 2) * every) + 2, n + 1))
    local pick = largestTriangle(points, points[a], floor(i * every) + 2, floor((i + 1) * every) + 2, ax, ay)
    out[#out + 1] = points[pick]
    a = pick
  end
  out[#out + 1] = points[n]
  return out
end

-- -- x ticks: a time ladder that lands on the player's midnight ----------------------------------

local TIME_STEPS = { 3600, 10800, 21600, 43200, DAY, 2 * DAY, 7 * DAY, 14 * DAY, 30 * DAY,
  91 * DAY, 182 * DAY, 365 * DAY }

local function midnight(ts)
  local t = date("*t", ts)
  return time({ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 })
end

local function pickStep(span, maxTicks)
  for _, s in ipairs(TIME_STEPS) do
    if span / s <= maxTicks then return s end
  end
  return TIME_STEPS[#TIME_STEPS]
end

-- Day steps re-anchor on midnight after every step, with a two-hour nudge, so a 23- or 25-hour
-- day (a daylight-saving change) cannot walk the labels off midnight.
local function nextTick(x, step)
  if step >= DAY then return midnight(x + step + 7200) end
  return x + step
end

local function firstTick(xMin, step)
  local m = midnight(xMin)
  if step >= DAY then
    if m < xMin then return midnight(m + DAY + 7200) end
    return m
  end
  return m + ceil((xMin - m) / step) * step
end

function Math.TimeTicks(xMin, xMax, maxTicks)
  maxTicks = maxTicks or LC.X_TICKS
  if not (xMin and xMax) or xMax <= xMin then return {}, nil end
  local step = pickStep(xMax - xMin, maxTicks)
  local ticks, x = {}, firstTick(xMin, step)
  while x <= xMax and #ticks <= maxTicks do
    ticks[#ticks + 1] = x
    x = nextTick(x, step)
  end
  return ticks, step
end

-- -- hover and dashes ----------------------------------------------------------------------------

function Math.NearestIndex(xs, x)
  local n = #xs
  if n == 0 then return nil end
  if x <= xs[1] then return 1 end
  if x >= xs[n] then return n end
  local lo, hi = 1, n
  while hi - lo > 1 do
    local mid = floor((lo + hi) / 2)
    if xs[mid] <= x then lo = mid else hi = mid end
  end
  if x - xs[lo] <= xs[hi] - x then return lo end
  return hi
end

function Math.Dashes(x1, y1, x2, y2, dash, gap)
  dash, gap = dash or LC.DASH, gap or LC.GAP
  local dx, dy = x2 - x1, y2 - y1
  local len = sqrt(dx * dx + dy * dy)
  local out = {}
  if len <= 0 then return out end
  local ux, uy, s = dx / len, dy / len, 0
  while s < len do
    local e = min(s + dash, len)
    out[#out + 1] = { x1 + ux * s, y1 + uy * s, x1 + ux * e, y1 + uy * e }
    s = s + dash + gap
  end
  return out
end
```

`LibKa0s/LibKa0s.xml` — after `<Script file="WidgetsDragHandle.lua"/>`:

```xml
	<Script file="WidgetsLineChart.lua"/>
```

`tests/majors.lua` — the Widgets row becomes:

```lua
  {
    major = "LibKa0s-Widgets-1.0",
    files = { "Widgets", "WidgetsReorder", "WidgetsDragHandle", "WidgetsLineChart" },
    primary = "Widgets",
    paired = {
      { file = "WidgetsReorder",    minorField = "__reorderMinor", probeField = "__reorderShellMinor" },
      { file = "WidgetsDragHandle", minorField = "__dragMinor",    probeField = "__dragShellMinor" },
      { file = "WidgetsLineChart",  minorField = "__chartMinor",   probeField = "__chartShellMinor" },
    },
  },
```

`docs/api/Widgets/version-12.1.4.1-docs.md`: copy `version-12.1.4-docs.md`; header table: `Files and minors` adds `` `WidgetsLineChart.lua` minor **1** ``, `Shipped in` v1.69.0, `Status` **Current**, `Supersedes` [version 12.1.4](./version-12.1.4-docs.md) — no line chart, `Confirm in-game` `{ Widgets = 12, WidgetsReorder = 1, WidgetsDragHandle = 4, WidgetsLineChart = 1 }`. Add `## What changed at 12.1.4.1` above `## What changed at 12.1.4` (new file, paired on the shell's minor, `Widgets.lua` stays 12, the version key gains a component; one consumer at release — cite S1's resolution), and a new `## The line chart` section after `## The unlocked drag handle` with `### lib.LINE_CHART` (every field, **Since 1**) and `### lib.ChartMath` (each of the six functions with its signature, return shape and the edge cases the suite pins, **Since 1**). In `version-12.1.4-docs.md`: `Status` Superseded, `Superseded by` 12.1.4.1, closing `## Moving to 12.1.4.1` ("Copy the folder whole. Nothing a host calls moves; a host that draws no chart owes nothing."). Add the 12.1.4.1 row (Current) to `docs/api/README.md`'s Widgets table and mark 12.1.4 Superseded.

`CHANGELOG.md` — the v1.69.0 block's first line becomes `Versions in this release: **WidgetsLineChart minor 1**, a new file (`LibKa0s-Widgets-1.0` key 12.1.4.1), and **test kit revision 37**.` and gains a section:

```markdown
### WidgetsLineChart minor 1: the line chart's math

- **A new secondary file of `LibKa0s-Widgets-1.0`**, paired on the shell's minor like
  `WidgetsDragHandle.lua`. `Widgets.lua` stays at minor 12; the key is 12.1.4.1.
- **`lib.LINE_CHART`** (chrome constants) and **`lib.ChartMath`**: `NiceTicks`, `Budget`,
  `Downsample` (LTTB, at most one point per 2px, endpoints kept), `TimeTicks` (day steps on local
  midnight), `NearestIndex`, `Dashes`. Cases: `tests/test_widgets_linechart_math.lua`.
```

Then regenerate the manifests:

```bash
lua tools/gen-api-members.lua
```

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: `0 failed` — the fourteen `chart math:` cases pass; `test_versioning` passes (the needle `WidgetsLineChart minor 1` is in `CHANGELOG.md`, `version-12.1.4.1-docs.md` exists, the regenerated `members-12.1.4.1.json` matches, the paired guard records `__chartShellMinor`); `test_prose` passes (ASCII-only file). luacheck 0/0.

- [ ] **Step 5: Regenerate inventory and commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
# README.md: Tests badge to the new Totals figure
git add LibKa0s/WidgetsLineChart.lua LibKa0s/LibKa0s.xml tests/majors.lua tests/test_widgets_linechart_math.lua \
  tests/run.lua docs/api/Widgets docs/api/README.md CHANGELOG.md docs/test-cases.md README.md CLAUDE.md
git commit -m "$(cat <<'EOF'
TL-LK-02: WidgetsLineChart minor 1 - chart math (nice ticks, LTTB, time ticks, dashes)

New secondary file of LibKa0s-Widgets-1.0 paired on the shell's minor (key
12.1.4.1). Publishes lib.LINE_CHART and lib.ChartMath; the widget lands next.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt
EOF
)"
```

(`CLAUDE.md` is in the `git add` only if S1 was resolved as a register row.)

---

### Task A3: `lib.LineChart` — the pooled widget

**Files:**
- Modify: `LibKa0s/WidgetsLineChart.lua` (append)
- Create: `tests/test_widgets_linechart.lua`; Modify: `tests/run.lua` (add `"test_widgets_linechart"` after `"test_widgets_linechart_math"`)
- Modify: `docs/api/Widgets/version-12.1.4.1-docs.md` (the widget's sections), `CHANGELOG.md`
- Regenerate: `docs/api/Widgets/members-12.1.4.1.json`

**Interfaces:**
- Consumes: Task A2's `lib.ChartMath`, `lib.LINE_CHART`; kit 37's `CreateLine` (tests); globals `CreateFrame`, `GetCursorPosition`, `date`.
- Produces:
  - `lib.LineChart(parent, opts) -> chart` — a `Frame`. `opts` (read on every render, never written): `font` (FontObject name for labels, default `"GameFontDisableSmall"`), `onHover(chart, index|nil, x|nil)`, `formatY(v) -> string`, `formatX(x, step) -> string`.
  - `chart:SetData(data)` — `data = { xMin, xMax, yMin?, yMax?, integer?, series = { { points = {{x=,y=},...}, color = {r,g,b,a}?, thickness? = 1.5, dashFrom? = x, dashTo? = x } }, markers = { { x, color?, dashed? = true } }?, hoverXs = {sorted x}? }`. Stores the reference; does not draw.
  - `chart:Render(w?, h?)` — draws at the given size (default `GetWidth/GetHeight`); recycles every Line and label.
  - `chart:Clear()` — forgets data, hides everything, clears hover.
  - `chart:GetPlotRect() -> left, bottom, width, height` (nil before the first sized render).
  - `chart:XToPixel(x) -> px`, `chart:YToPixel(y) -> py`, `chart:PixelToX(px) -> x` (chart-local, BOTTOMLEFT origin).
  - `chart:HoverAtPixel(px) -> index|nil` — snaps to the nearest `hoverXs`, moves the crosshair, calls `opts.onHover` only when the index changes.
  - `chart:ClearHover()`; `chart:HoverIndex() -> index|nil`.
  - Scripts it owns: `OnEnter` (arms an `OnUpdate` reading `GetCursorPosition`), `OnLeave` / `OnHide` (disarm + `ClearHover`), `OnSizeChanged` (re-render).

- [ ] **Step 1: Write the failing test** — `tests/test_widgets_linechart.lua`

```lua
-- tests/test_widgets_linechart.lua — LibKa0s-Widgets-1.0: `lib.LineChart`, the drawn half.
--
-- Built on kit revision 37's Line regions: every segment, grid rule and crosshair the chart makes is
-- a distinct recording Line on the chart frame (`__madeLines`), so these cases can count what a
-- render drew and prove a second render drew nothing new. Labels are FontStrings, which the base
-- kit still aliases to the frame (testkit/mock_base.lua's "Known divergence"); no case here reads a
-- label's text for that reason -- the text comes from formatY/formatX, and those are the host's.

local T = _G.LK_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse
local mocks = T.mocks
local W = T.widgets

local function newChart(opts)
  return W.LineChart(mocks.CreateFrame("Frame"), opts or {})
end

local function ramp(n, y0, step)
  local pts = {}
  for i = 1, n do pts[i] = { x = i * 100, y = y0 + (i - 1) * step } end
  return pts
end

local function shownLines(c)
  local n = 0
  for _, l in ipairs(c.__madeLines) do if l:IsShown() then n = n + 1 end end
  return n
end

local function yTicks(lo, hi)
  return (W.ChartMath.NiceTicks(lo, hi, W.LINE_CHART.Y_TICKS))
end

test("line chart: Render draws the axis, one grid rule per y tick and one line per segment", function()
  local c = newChart()
  c:SetData({ xMin = 100, xMax = 300, series = { { points = ramp(3, 0, 50) } } })
  c:Render(400, 200)
  -- axis 1 + grid #ticks(0..100) + 2 segments; the crosshair exists but is hidden
  assertEqual(shownLines(c), 1 + #yTicks(0, 100) + 2)
end)

test("line chart: a second Render of the same data creates no new Line objects", function()
  -- Review Focus 5
  local c = newChart()
  c:SetData({ xMin = 100, xMax = 2000, series = { { points = ramp(20, 0, 3) }, { points = ramp(20, 5, 1) } } })
  c:Render(400, 200)
  local made, shown = #c.__madeLines, shownLines(c)
  c:Render(400, 200)
  assertEqual(#c.__madeLines, made, "the pool hands the same Lines back")
  assertEqual(shownLines(c), shown)
end)

test("line chart: a smaller render hides the leftovers instead of leaving them drawn", function()
  local c = newChart()
  c:SetData({ xMin = 100, xMax = 2000, series = { { points = ramp(20, 0, 3) } } })
  c:Render(400, 200)
  local before = shownLines(c)
  c:SetData({ xMin = 100, xMax = 300, series = { { points = ramp(3, 0, 3) } } })
  c:Render(400, 200)
  assertTrue(shownLines(c) < before, "segments the new data does not need are hidden")
end)

test("line chart: the plot never gets more than one point per 2px", function()
  -- Review Focus 1, through the widget
  local c = newChart()
  c:SetData({ xMin = 100, xMax = 100000, series = { { points = ramp(1000, 0, 1) } } })
  c:Render(208, 120)
  local _, _, pw = c:GetPlotRect()
  local budget = W.ChartMath.Budget(pw)
  assertEqual(shownLines(c), 1 + #yTicks(0, 999) + (budget - 1))
end)

test("line chart: a series maps its first point onto the plot's bottom-left corner", function()
  local c = newChart()
  c:SetData({ xMin = 100, xMax = 300, series = { { points = ramp(3, 0, 50), thickness = 3 } } })
  c:Render(400, 200)
  local left, bottom = c:GetPlotRect()
  local first = c.__madeLines[1 + 1 + #yTicks(0, 100) + 1]  -- crosshair, axis, grid, then the series
  local _, rel, x, y = first:GetStartPoint()
  assertTrue(rel == c, "anchored to the chart frame")
  assertEqual(x, left); assertEqual(y, bottom)
  assertEqual(first:GetThickness(), 3)
  assertEqual(c:XToPixel(300), left + select(3, c:GetPlotRect()))
end)

test("line chart: a dashed range draws dashes, an undashed series one line per segment", function()
  local solid, dashed = newChart(), newChart()
  local pts = { { x = 0, y = 0 }, { x = 100, y = 0 } }
  solid:SetData({ xMin = 0, xMax = 100, yMin = 0, yMax = 1, series = { { points = pts } } })
  dashed:SetData({ xMin = 0, xMax = 100, yMin = 0, yMax = 1, series = { { points = pts, dashFrom = 0, dashTo = 100 } } })
  solid:Render(400, 200); dashed:Render(400, 200)
  assertTrue(shownLines(dashed) > shownLines(solid) + 10, "a 340px dashed segment is many dashes")
end)

test("line chart: a marker inside the domain draws a dashed rule; outside it draws nothing", function()
  local inside, outside = newChart(), newChart()
  local base = { xMin = 0, xMax = 100, yMin = 0, yMax = 1, series = {} }
  inside:SetData({ xMin = 0, xMax = 100, yMin = 0, yMax = 1, series = {}, markers = { { x = 50 } } })
  outside:SetData({ xMin = 0, xMax = 100, yMin = 0, yMax = 1, series = {}, markers = { { x = 500 } } })
  local plain = newChart(); plain:SetData(base)
  inside:Render(400, 200); outside:Render(400, 200); plain:Render(400, 200)
  assertTrue(shownLines(inside) > shownLines(plain), "the marker drew")
  assertEqual(shownLines(outside), shownLines(plain), "an out-of-range marker draws nothing")
end)

test("line chart: HoverAtPixel snaps to the nearest x and calls onHover once per change", function()
  local calls = {}
  local c = newChart({ onHover = function(_, i, x) calls[#calls + 1] = { i, x } end })
  c:SetData({ xMin = 100, xMax = 300, series = { { points = ramp(3, 0, 1) } }, hoverXs = { 100, 200, 300 } })
  c:Render(400, 200)
  assertEqual(c:HoverAtPixel(c:XToPixel(190)), 2)
  c:HoverAtPixel(c:XToPixel(205))
  assertEqual(#calls, 1, "the same index again is not a new hover")
  assertEqual(calls[1][1], 2); assertEqual(calls[1][2], 200)
  assertTrue(c.__madeLines[1]:IsShown(), "the crosshair is up")
  c:ClearHover()
  assertEqual(#calls, 2); assertEqual(calls[2][1], nil)
  assertFalse(c.__madeLines[1]:IsShown(), "and down again")
  assertEqual(c:HoverIndex(), nil)
end)

test("line chart: OnLeave clears the hover the way ClearHover does", function()
  local last = "unset"
  local c = newChart({ onHover = function(_, i) last = i end })
  c:SetData({ xMin = 0, xMax = 10, series = {}, hoverXs = { 0, 10 } })
  c:Render(400, 200)
  c:HoverAtPixel(c:XToPixel(9))
  c:__fire("OnLeave")
  assertEqual(last, nil)
end)

test("line chart: Clear hides every line", function()
  local c = newChart()
  c:SetData({ xMin = 100, xMax = 300, series = { { points = ramp(3, 0, 50) } } })
  c:Render(400, 200)
  c:Clear()
  assertEqual(shownLines(c), 0)
end)

test("line chart: Render before SetData or at zero size draws nothing and does not raise", function()
  local c = newChart()
  c:Render(400, 200)
  assertEqual(shownLines(c), 0)
  c:SetData({ xMin = 100, xMax = 300, series = { { points = ramp(3, 0, 50) } } })
  c:Render(0, 0)
  assertEqual(shownLines(c), 0)
  assertEqual(c:GetPlotRect(), nil)
end)

test("line chart: a one-point series still draws a visible mark", function()
  local c = newChart()
  c:SetData({ xMin = 0, xMax = 100, series = { { points = { { x = 50, y = 5 } } } } })
  c:Render(400, 200)
  assertEqual(shownLines(c), 1 + #yTicks(0, 5) + 1)
end)
```

Add `"test_widgets_linechart"` after `"test_widgets_linechart_math"` in `tests/run.lua`.

- [ ] **Step 2: Run to verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -E "line chart:|FAIL" | head`
Expected: FAIL — `W.LineChart` is nil.

- [ ] **Step 3: Implement** — append to `LibKa0s/WidgetsLineChart.lua`

```lua
-- -- the widget ----------------------------------------------------------------------------------
--
-- POOLED BY INDEX. A render hands out Lines and labels from two arrays in order and hides whatever
-- it did not reach, so the same data drawn twice creates nothing new and a smaller drawing leaves
-- nothing stale on screen. Regions are never destroyed in the client, so a chart that created per
-- render would grow for the life of the session.

local function plotRect(w, h)
  return LC.PAD_LEFT, LC.PAD_BOTTOM,
    max(0, w - LC.PAD_LEFT - LC.PAD_RIGHT), max(0, h - LC.PAD_TOP - LC.PAD_BOTTOM)
end

local function acquireLine(c)
  c.__lineUsed = c.__lineUsed + 1
  local l = c.__linePool[c.__lineUsed]
  if not l then
    l = c:CreateLine(nil, "ARTWORK")
    c.__linePool[c.__lineUsed] = l
  end
  l:Show()
  return l
end

local function seg(c, x1, y1, x2, y2, color, thickness)
  local l = acquireLine(c)
  l:SetThickness(thickness or 1)
  l:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
  l:SetStartPoint("BOTTOMLEFT", c, x1, y1)
  l:SetEndPoint("BOTTOMLEFT", c, x2, y2)
  return l
end

local function dashed(c, x1, y1, x2, y2, color, thickness)
  for _, d in ipairs(Math.Dashes(x1, y1, x2, y2)) do
    seg(c, d[1], d[2], d[3], d[4], color, thickness)
  end
end

local function acquireLabel(c)
  c.__labelUsed = c.__labelUsed + 1
  local fs = c.__labelPool[c.__labelUsed]
  if not fs then
    -- Created WITH a template: a FontString with no face raises on its first SetText in the client.
    fs = c:CreateFontString(nil, "OVERLAY", c.__opts.font or "GameFontDisableSmall")
    c.__labelPool[c.__labelUsed] = fs
  end
  fs:ClearAllPoints()
  fs:Show()
  return fs
end

local function hideUnused(c)
  for i = c.__lineUsed + 1, #c.__linePool do c.__linePool[i]:Hide() end
  for i = c.__labelUsed + 1, #c.__labelPool do c.__labelPool[i]:Hide() end
end

local function dataRange(series)
  local lo, hi
  for _, s in ipairs(series or {}) do
    for _, p in ipairs(s.points or {}) do
      if not lo or p.y < lo then lo = p.y end
      if not hi or p.y > hi then hi = p.y end
    end
  end
  return lo, hi
end

local function xToPixel(s, x)
  if s.x1 == s.x0 then return s.left end
  return s.left + (x - s.x0) / (s.x1 - s.x0) * s.w
end

local function yToPixel(s, y)
  if s.y1 == s.y0 then return s.bottom end
  return s.bottom + (y - s.y0) / (s.y1 - s.y0) * s.h
end

local function defaultFormatY(v)
  if v == floor(v) then return tostring(v) end
  return string.format("%.2f", v)
end

local function defaultFormatX(x, step)
  if step and step < DAY then return date("%H:%M", x) end
  return date("%d %b", x)
end

local function drawXAxis(c, s)
  seg(c, s.left, s.bottom, s.left + s.w, s.bottom, LC.AXIS, 1)
  local ticks, step = Math.TimeTicks(s.x0, s.x1, LC.X_TICKS)
  local fmt = c.__opts.formatX or defaultFormatX
  for _, t in ipairs(ticks) do
    local fs = acquireLabel(c)
    fs:SetPoint("TOP", c, "BOTTOMLEFT", xToPixel(s, t), s.bottom - 2)
    fs:SetText(fmt(t, step))
  end
end

local function drawYAxis(c, s, ticks)
  local fmt = c.__opts.formatY or defaultFormatY
  for _, t in ipairs(ticks) do
    local y = yToPixel(s, t)
    seg(c, s.left, y, s.left + s.w, y, LC.GRID, 1)
    local fs = acquireLabel(c)
    fs:SetPoint("RIGHT", c, "BOTTOMLEFT", s.left - LC.LABEL_GAP, y)
    fs:SetText(fmt(t))
  end
end

local function drawMarkers(c, s, markers)
  for _, m in ipairs(markers or {}) do
    if m.x and m.x >= s.x0 and m.x <= s.x1 then
      local x = xToPixel(s, m.x)
      if m.dashed == false then
        seg(c, x, s.bottom, x, s.bottom + s.h, m.color or LC.MARKER, 1)
      else
        dashed(c, x, s.bottom, x, s.bottom + s.h, m.color or LC.MARKER, 1)
      end
    end
  end
end

-- A segment is drawn dashed when its midpoint lies in the series' dashed range. The host uses the
-- range for the part of a line it wants read as provisional.
local function inDash(sr, xa, xb)
  if not sr.dashFrom then return false end
  local mid = (xa + xb) / 2
  return mid >= sr.dashFrom and mid <= (sr.dashTo or math.huge)
end

local function drawSeries(c, s, sr)
  local pts = Math.Downsample(sr.points or {}, Math.Budget(s.w))
  local color, th = sr.color or LC.LINE, sr.thickness or 1.5
  if #pts == 1 then
    local x, y = xToPixel(s, pts[1].x), yToPixel(s, pts[1].y)
    seg(c, x - 1, y, x + 1, y, color, th)
    return
  end
  for i = 2, #pts do
    local a, b = pts[i - 1], pts[i]
    local x1, y1 = xToPixel(s, a.x), yToPixel(s, a.y)
    local x2, y2 = xToPixel(s, b.x), yToPixel(s, b.y)
    if inDash(sr, a.x, b.x) then dashed(c, x1, y1, x2, y2, color, th) else seg(c, x1, y1, x2, y2, color, th) end
  end
end

local function scaleFor(d, w, h)
  local left, bottom, pw, ph = plotRect(w, h)
  local lo, hi = d.yMin, d.yMax
  if lo == nil or hi == nil then lo, hi = dataRange(d.series) end
  local ticks, y0, y1 = Math.NiceTicks(lo, hi, LC.Y_TICKS, d.integer)
  return { x0 = d.xMin, x1 = d.xMax, y0 = y0, y1 = y1, left = left, bottom = bottom, w = pw, h = ph }, ticks
end

local function render(c, w, h)
  c.__lineUsed, c.__labelUsed = 0, 0
  local d = c.__data
  if d and d.xMin and d.xMax and w > 0 and h > 0 then
    local s, ticks = scaleFor(d, w, h)
    c.__scale = s
    drawXAxis(c, s)
    drawYAxis(c, s, ticks)
    drawMarkers(c, s, d.markers)
    for _, sr in ipairs(d.series or {}) do drawSeries(c, s, sr) end
  else
    c.__scale = nil
  end
  hideUnused(c)
end

local function moveCross(c, x)
  local s = c.__scale
  local px = xToPixel(s, x)
  c.__cross:SetStartPoint("BOTTOMLEFT", c, px, s.bottom)
  c.__cross:SetEndPoint("BOTTOMLEFT", c, px, s.bottom + s.h)
  c.__cross:Show()
end

-- The pointer read, armed only while the cursor is over the chart. Every value is type-checked
-- because a headless frame answers its own table for any getter it does not model.
local function hoverTick(self)
  if not GetCursorPosition then return end
  local cx = GetCursorPosition()
  local scale, left = self:GetEffectiveScale(), self:GetLeft()
  if type(cx) ~= "number" or type(scale) ~= "number" or type(left) ~= "number" or scale == 0 then return end
  self:HoverAtPixel(cx / scale - left)
end

local function attachMethods(c)
  function c:SetData(data) self.__data = data end
  function c:Render(w, h) render(self, w or self:GetWidth() or 0, h or self:GetHeight() or 0) end
  function c:Clear() self.__data = nil; self:ClearHover(); render(self, 0, 0) end
  function c:GetPlotRect()
    local s = self.__scale
    if not s then return nil end
    return s.left, s.bottom, s.w, s.h
  end
  function c:XToPixel(x) return self.__scale and xToPixel(self.__scale, x) or 0 end
  function c:YToPixel(y) return self.__scale and yToPixel(self.__scale, y) or 0 end
  function c:PixelToX(px)
    local s = self.__scale
    if not s or s.w == 0 then return s and s.x0 or 0 end
    return s.x0 + (px - s.left) / s.w * (s.x1 - s.x0)
  end
  function c:HoverIndex() return self.__hoverIndex end
  function c:HoverAtPixel(px)
    local d, s = self.__data, self.__scale
    local xs = d and d.hoverXs
    if not (s and xs and #xs > 0) then return nil end
    local i = Math.NearestIndex(xs, self:PixelToX(px))
    if i ~= self.__hoverIndex then
      self.__hoverIndex = i
      moveCross(self, xs[i])
      if self.__opts.onHover then self.__opts.onHover(self, i, xs[i]) end
    end
    return i
  end
  function c:ClearHover()
    self.__cross:Hide()
    if self.__hoverIndex == nil then return end
    self.__hoverIndex = nil
    if self.__opts.onHover then self.__opts.onHover(self, nil, nil) end
  end
end

--- One line chart, parented to `parent`. See the API document for `opts` and `data`.
function lib.LineChart(parent, opts)
  local c = CreateFrame("Frame", nil, parent)
  c.__opts = opts or {}
  c.__linePool, c.__lineUsed, c.__labelPool, c.__labelUsed = {}, 0, {}, 0
  local cross = c:CreateLine(nil, "OVERLAY")
  cross:SetThickness(1)
  cross:SetColorTexture(LC.CROSSHAIR[1], LC.CROSSHAIR[2], LC.CROSSHAIR[3], LC.CROSSHAIR[4])
  cross:Hide()
  c.__cross = cross
  attachMethods(c)
  c:EnableMouse(true)
  c:SetScript("OnEnter", function(self) self:SetScript("OnUpdate", hoverTick) end)
  c:SetScript("OnLeave", function(self) self:SetScript("OnUpdate", nil); self:ClearHover() end)
  c:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil); self:ClearHover() end)
  c:SetScript("OnSizeChanged", function(self, w, h) self:Render(w, h) end)
  return c
end
```

> The crosshair is the chart's **first** created Line (`__madeLines[1]`); the test above relies on that order and the comment in `lib.LineChart` should say so.

`docs/api/Widgets/version-12.1.4.1-docs.md`: under `## The line chart` add `### lib.LineChart(parent, opts)`, `### opts`, `### data` (every field, defaults, **Since 1**), `### Instance methods` (the ten methods above), `### Behavior a host must know` (pooled by index; `SetData` stores a reference and the host must not mutate it between `SetData` and `Render`; y range is the data's unless `yMin`/`yMax` given; `integer` keeps the y step ≥ 1; a segment is dashed when its midpoint is in `[dashFrom, dashTo]`; markers outside `[xMin, xMax]` draw nothing; `onHover` fires only on index change and with `nil` on leave/hide; the chart re-renders itself on `OnSizeChanged`; it is `EnableMouse(true)`), and extend `## Degraded` ("a host with no Widgets copy gets no chart; LootHistory's seam answers nil and its Timeline tab says why"). Add `lib.LineChart` to `## Lib-level surface`. CHANGELOG section title becomes "WidgetsLineChart minor 1: the line chart" with a bullet for the widget and `tests/test_widgets_linechart.lua`. Regenerate: `lua tools/gen-api-members.lua`.

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: `0 failed` (twelve `line chart:` cases pass; `test_versioning` re-reads the regenerated manifest); luacheck 0/0 (`GetCursorPosition`, `date`, `time`, `CreateFrame` are already `read_globals` in `.luacheckrc`). Also run the complexity check the release gate will run: `tests/_kit/run-automated-tests.sh` (no `--release`) and confirm `complexity.warnings` is 0 in the printed manifest; split any function lizard flags.

- [ ] **Step 5: Regenerate inventory and commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
# README.md: Tests badge to the new Totals figure
git add LibKa0s/WidgetsLineChart.lua tests/test_widgets_linechart.lua tests/run.lua docs/api/Widgets \
  CHANGELOG.md docs/test-cases.md README.md
git commit -m "$(cat <<'EOF'
TL-LK-03: lib.LineChart - pooled Line-region chart with markers, dashes and hover

Series drawn as Line regions pooled by index (a second render creates
nothing), LTTB-thinned to one point per 2px, auto-scaled y, time x axis,
dashed markers and dashed ranges, crosshair with an index-change hover hook.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt
EOF
)"
```

---

### Task A4: Release v1.69.0 (the gate between Part A and Part B)

> **Flags to raise now:** S2 (the standard's library-stack-§7 counts need an upstream recount) and S3 (re-vendor of the other ten consumers). Record the user's answers in the CHANGELOG block's "What a consumer owes" line.

**Files:**
- Modify: `CHANGELOG.md` (finalize the v1.69.0 block: date, "fifteen majors across **thirty-three** files", every unchanged file's minor named the way v1.68.0's block names them, "No `NEEDS_*` floor rises", the consumer line, then — after the run — the release-gate line)
- Modify: `docs/releasing.md` (top table and step 2's constant list gain `CHART_MINOR` / "`CHART_MINOR` in `WidgetsLineChart.lua`"; "thirty-two" → "thirty-three" at step 2 and "Re-vendoring consumers"; provenance template line → v1.69.0; the Widgets `MODULES` example line → `{ Widgets = 12, WidgetsReorder = 1, WidgetsDragHandle = 4, WidgetsLineChart = 1 }`; the file-tree comment block gains `WidgetsLineChart.lua -- the line chart, same module, CHART_MINOR of its own`; the release-status paragraph for v1.69.0 in the style of the v1.68.x ones)
- Modify: `README.md` (Widgets row: files and key **12.1.4.1**, one sentence "And `LineChart`, a pooled line chart over a time axis with markers, dashed ranges and a hover crosshair."; the standards pointer stays v2.76.0 unless the standard moved — check per releasing step 7; Tests badge)
- Modify: `docs/test-cases.md` (regenerate)
- Generate: `docs/automated-tests/<stamp>/` (+ `ANALYSIS.md`), `docs/automated-tests/RESULTS.md` row

**Interfaces:**
- Consumes: Tasks A1–A3.
- Produces: git tag **`v1.69.0`** on LibKa0s `master`, pushed (⚠ CONFIRM), which Part B re-vendors from.

- [ ] **Step 1: Prove the version-bearing lines** (releasing step 7):

```bash
head -1 ../WowAddonStandards/standards/STANDARDS.md
grep -n 'v2\.' README.md | head -1
grep -rn "thirty-two" docs/releasing.md README.md CLAUDE.md   # every live hit is about the payload count -> thirty-three
```
Expected: the standard version matches the README pointer (if not, read the standard's changes first, then move the pointer); no live "thirty-two" left that describes v1.69.0's payload.

- [ ] **Step 2: Green gate, then commit 1 (the release minus its evidence)**

```bash
lua tests/run.lua 2>&1 | tail -3 && luacheck .
lua tests/run.lua --list > docs/test-cases.md
git add CHANGELOG.md docs/releasing.md README.md docs/test-cases.md
git commit -m "$(cat <<'EOF'
TL-LK-04: v1.69.0 - WidgetsLineChart minor 1 and kit revision 37

Fifteen majors across thirty-three files; Widgets key 12.1.4.1. No existing
file's minor moves and no NEEDS_* floor rises.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt
EOF
)"
git status --porcelain   # must print nothing
```

- [ ] **Step 3: Take the release record**

```bash
tests/_kit/run-automated-tests.sh --release 1.69.0
```
Expected: a new `docs/automated-tests/<stamp>/` with `manifest.json`; lint/tests/complexity `pass`, perf `skip` (no `tests/perf.lua`, a recorded hole).

- [ ] **Step 4: Write `docs/automated-tests/<stamp>/ANALYSIS.md`** per the standards repo's `AUTOMATED_TESTS.md` (*Step 2*), every figure from the manifest; the perf skip is "not measured", never "passed".

- [ ] **Step 5: Release-notes line, commit 2**

Append to the v1.69.0 block, figures read off `S=docs/automated-tests/<stamp>/manifest.json`:

```text
Release gate (`docs/automated-tests/<stamp>/`): lint pass, <warnings>/<errors> in <files> files;
tests pass, <total> tests, <failed> failed; complexity pass, <warnings> over CCN 15. Perf
SKIPPED, not measured — no `tests/perf.lua` — so the gate covered three suites, not four.
```

```bash
git add docs/automated-tests CHANGELOG.md
git commit -m "$(cat <<'EOF'
TL-LK-05: v1.69.0 release record and its ANALYSIS.md

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt
EOF
)"
```

- [ ] **Step 6: Check the tag's preconditions** (all must hold):

```bash
S=docs/automated-tests/<stamp>/manifest.json
jq -r '.release' "$S"                         # 1.69.0
jq -r '.git.dirty' "$S"                       # false
jq -r '.git.sha' "$S"                         # HEAD~0 or HEAD~1
jq -r '.suites | to_entries[] | "\(.key) \(.value.status)"' "$S"   # lint/tests/complexity pass, perf skip
jq -r '.suites.complexity.warnings' "$S"      # 0
grep -l '"release": "1.69.0"' docs/automated-tests/*/manifest.json   # includes <stamp>
test -f docs/automated-tests/<stamp>/ANALYSIS.md && echo present
```

- [ ] **Step 7: ⚠ CONFIRM — tag and publish.** Ask the user before running any of these; they are outward-facing and every consumer's vendor gate resolves this tag.

```bash
git tag -a v1.69.0 -m "LibKa0s v1.69.0 - WidgetsLineChart minor 1 (Widgets 12.1.4.1), kit revision 37"
git push origin master
git push origin v1.69.0
```

**GATE:** Part B does not start until `git -C /mnt/d/Profile/Users/Tushar/Documents/GIT/LibKa0s rev-parse v1.69.0` resolves locally (LootHistory's `tests/test_vendor_sync.lua` reads the sibling checkout's tag; the push is for everyone else).

---

# Part B — LootHistory repo

All Part B commands run from `/mnt/d/Profile/Users/Tushar/Documents/GIT/LootHistory` unless a step says otherwise. Suites read `_G.LH_TEST` (`T.NS`, `T.test`, `T.assertEqual`, `T.assertTrue`, `T.assertFalse`, `T.mocks`). Phase 1 and Phase 2 must be merged and green on `master` before B1.

### Task B1: Re-vendor LibKa0s v1.69.0 (bytes + provenance line, one commit)

**Files:**
- Replace: `libs/LibKa0s/` (whole folder) and `tests/_kit/` (whole folder) from tag `v1.69.0`
- Modify: `CLAUDE.md` (`## Vendored LibKa0s`: `v1.68.1` → `v1.69.0`)
- Modify: `docs/debug.md:14` ("from LibKa0s v1.68.1" → "v1.69.0")
- Modify: `tests/test_libka0s.lua:42` (`LIB_FILES` gains `"libs/LibKa0s/WidgetsLineChart.lua"` after `WidgetsDragHandle.lua`, with a "New in v1.69.0" comment)
- Create: `docs/revendor/2026-10-06-v1.69.0/01_DELTA.md`, `02_CANDIDATES.md`, `05_SUMMARY.md`
- Regenerate: `docs/test-cases.md`

**Interfaces:**
- Consumes: LibKa0s tag `v1.69.0` (Task A4).
- Produces: `LibStub("LibKa0s-Widgets-1.0").LineChart`, `.ChartMath`, `.LINE_CHART` at runtime; kit 37's `CreateLine` in every mock frame.

- [ ] **Step 1: Write the failing test** — in `tests/test_libka0s.lua`, add the file to `LIB_FILES` (this alone turns `every file of LibKa0s.xml is vendored and loads` red until the bytes arrive, because the count no longer matches the old XML), and add:

```lua
test("v1.69.0: the line chart is vendored and attached to the Widgets major", function()
  local W = T.mocks.LibStub("LibKa0s-Widgets-1.0", true)
  assertTrue(W ~= nil and type(W.LineChart) == "function", "lib.LineChart missing: re-vendor v1.69.0")
  assertEqual(W.MODULES.WidgetsLineChart, 1)
  assertEqual(T.KIT_VERSION, 37)
end)
```

and in `CLAUDE.md` move the provenance line to `v1.69.0`.

- [ ] **Step 2: Run to verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -E "vendored|v1.69.0|CLAUDE.md says|FAIL" | head`
Expected: FAIL — the XML count case (33 listed vs 32 shipped), the new v1.69.0 case, and `test_vendor_sync` (the payload is v1.68.1's while CLAUDE.md names v1.69.0).

- [ ] **Step 3: Copy both payloads from the tag** (never from `master`):

```bash
LK=/mnt/d/Profile/Users/Tushar/Documents/GIT/LibKa0s
TMP=$(mktemp -d)
git -C "$LK" archive v1.69.0 LibKa0s testkit | tar -x -C "$TMP"
rm -rf libs/LibKa0s tests/_kit
mkdir -p libs/LibKa0s tests/_kit
cp -r "$TMP/LibKa0s/." libs/LibKa0s/
cp -r "$TMP/testkit/." tests/_kit/
diff -r --strip-trailing-cr "$TMP/LibKa0s" libs/LibKa0s   # must print nothing
diff -r --strip-trailing-cr "$TMP/testkit" tests/_kit     # must print nothing
git add --renormalize libs/LibKa0s tests/_kit
```

Edit `docs/debug.md:14` to name v1.69.0. Write the frozen bundle `docs/revendor/2026-10-06-v1.69.0/` in the shape of `docs/revendor/2026-10-04-v1.68.1/`: `01_DELTA.md` (one file added, `WidgetsLineChart.lua` minor 1; Widgets key 12.1.4 → 12.1.4.1; kit 36 → 37 with `mock_lines.lua`; no floor rises; no existing minor moves), `02_CANDIDATES.md` (one candidate, `lib.LineChart` — **adopt**, by the timeline plan's Task B2; no interview needed because the adoption is already ratified by spec F3), `05_SUMMARY.md` (test counts before/after, both diffs empty).

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: all pass, including both `test_vendor_sync` cases and the XML count; luacheck 0/0 (`libs/` and `tests/_kit/` are outside the checked set).

- [ ] **Step 5: Regenerate inventory and commit** (its own commit, per the re-vendor rule):

```bash
lua tests/run.lua --list > docs/test-cases.md
git add libs/LibKa0s tests/_kit CLAUDE.md docs/debug.md tests/test_libka0s.lua docs/revendor/2026-10-06-v1.69.0 docs/test-cases.md
git commit -m "$(cat <<'EOF'
TL-LH-01: re-vendor LibKa0s v1.69.0 (WidgetsLineChart 1; kit 37)

Both payloads copied whole from tag v1.69.0 via git archive; diff -r empty
with and without --strip-trailing-cr. CLAUDE.md provenance line and the
docs/debug.md stamp roll in this commit. One file added upstream
(libs/LibKa0s/WidgetsLineChart.lua, Widgets key 12.1.4.1); no minor moved,
no floor rose. Kit 37 models Line regions. Bundle:
docs/revendor/2026-10-06-v1.69.0/.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt
EOF
)"
```

---

### Task B2: `NS.MakeLineChart` — the host seam

**Files:**
- Modify: `core/WidgetsSetup.lua` (append after `NS.CopyWindow`; extend the header's "WHAT A DEGRADED INSTALL GETS" with one paragraph)
- Modify: `tests/test_widgets.lua` (append), `tests/test_libka0s.lua` (the "nine adopted majors" case asserts the seam), `tests/test_surface_parity.lua` (nothing to edit: its derivation greps `function NS.` out of `core/WidgetsSetup.lua`, so the new member is checked on both paths automatically — confirm it is listed in the run output)

**Interfaces:**
- Consumes: `LibStub("LibKa0s-Widgets-1.0", true).LineChart` (the file-level `W`).
- Produces: `NS.MakeLineChart(parent, opts) -> chart|nil` — `opts` is **copied** (a host may hoist it to a file constant); `opts.font` defaults to `"GameFontDisableSmall"`. `nil` on a degraded install.

- [ ] **Step 1: Write the failing test** — append to `tests/test_widgets.lua`

```lua
-- ── the line chart seam (timeline ledger, Phase 3) ─────────────────────────────────────────────

test("seam: NS.MakeLineChart builds the library's chart and routes hover back to the host", function()
  local hovered = "unset"
  local c = NS.MakeLineChart(T.mocks.UIParent, { onHover = function(_, i) hovered = i end })
  assertTrue(c ~= nil, "the library is present in this run, so the seam must build")
  assertTrue(type(c.SetData) == "function" and type(c.Render) == "function")
  c:SetData({ xMin = 0, xMax = 100, series = { { points = { { x = 0, y = 1 }, { x = 100, y = 2 } } } },
    hoverXs = { 0, 100 } })
  c:Render(300, 150)
  c:HoverAtPixel(c:XToPixel(90))
  assertEqual(hovered, 2)
end)

test("seam: NS.MakeLineChart copies the host's opts rather than stamping them", function()
  local opts = { onHover = function() end }
  NS.MakeLineChart(T.mocks.UIParent, opts)
  assertEqual(opts.font, nil, "the seam's default face must not be written into the caller's table")
end)

test("seam: the chart draws Line regions, not textures", function()
  local c = NS.MakeLineChart(T.mocks.UIParent, {})
  c:SetData({ xMin = 0, xMax = 10, series = { { points = { { x = 0, y = 0 }, { x = 10, y = 1 } } } } })
  c:Render(300, 150)
  assertTrue(#c.__madeLines >= 3, "crosshair, axis and at least one segment, all Lines")
end)
```

In `tests/test_libka0s.lua`'s "the nine adopted majors" case, extend the Widgets assertion:

```lua
  assertTrue(type(NS.MakeDropdown) == "function" and type(NS.CloseMenu) == "function"
    and type(NS.MakeLineChart) == "function", "Widgets seam not published")
```

and add a degraded case next to the other degraded-install cases:

```lua
test("degraded install: NS.MakeLineChart answers nil rather than a dead frame", function()
  local ns = dofile("tests/degraded_env.lua")()
  assertTrue(type(ns.MakeLineChart) == "function", "the seam is published on the degraded path too")
  assertEqual(ns.MakeLineChart({}, {}), nil)
end)
```

- [ ] **Step 2: Run to verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -E "MakeLineChart|Widgets seam|FAIL" | head`
Expected: FAIL — `NS.MakeLineChart` is nil.

- [ ] **Step 3: Implement** — `core/WidgetsSetup.lua`, appended:

```lua
--- One line chart, or nil when the library is absent.
---
--- The Timeline tab's whole drawing surface (modules/Timeline.lua): series as Line regions over a
--- time axis, a dashed marker, dashed ranges and a hover crosshair that reports the nearest x
--- index. Leased here, behind the same named seam as the dropdown, for the reason the header gives:
--- one file leases LibKa0s-Widgets-1.0.
---
--- The caller's opts are COPIED, as NS.MakeReorderList's are: a host hoists its opts to a file
--- constant, and the default face below must not be written into it.
---
--- NIL IS A REAL ANSWER. The Timeline refuses to draw and says why through NS.LIBKA0S_MISSING
--- rather than building a pane with no chart in it.
---
--- @param parent table  the frame to parent it to
--- @param opts table    onHover / formatY / formatX / font (see LibKa0s docs/api/Widgets/version-12.1.4.1-docs.md)
--- @return table|nil    the library's chart frame
function NS.MakeLineChart(parent, opts)
    if not (W and W.LineChart) then return nil end
    local o = {}
    for k, v in pairs(opts or {}) do o[k] = v end
    o.font = o.font or "GameFontDisableSmall"
    return W.LineChart(parent, o)
end
```

Header, under "WHAT A DEGRADED INSTALL GETS", add: "NS.MakeLineChart answers nil for the same reason, and the Timeline tab degrades like the export modal: it draws one line naming the cause (NS.LIBKA0S_MISSING) instead of a pane with nothing in it. `W.LineChart` is checked as well as `W`, because a v1.68 copy of the Widgets major vendored by another addon can win the LibStub negotiation for the SHELL while this addon's chart file still attaches — the paired guard refuses that pairing and leaves `LineChart` unset."

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS (incl. `parity: the Widgets seam publishes the same NS members on both paths`, which now derives `NS.MakeLineChart` too); 0/0.

- [ ] **Step 5: Regenerate inventory and commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add core/WidgetsSetup.lua tests/test_widgets.lua tests/test_libka0s.lua docs/test-cases.md
git commit -m "$(cat <<'EOF'
feat(widgets): NS.MakeLineChart seam over LibKa0s LineChart (timeline ledger P3)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt
EOF
)"
```

---

### Task B3: Rollup cell math (pure, in `core/Ledger.lua`)

**Files:**
- Modify: `core/Ledger.lua` (append)
- Modify: `tests/test_ledger.lua` (append)

**Interfaces:**
- Consumes: `NS.Ledger.ThingKey`, `NS.Util.RowKind`, `date`.
- Produces:
  - `NS.Ledger.DayKey(ts) -> "YYYY-MM-DD"` (local calendar day; lexical order = chronological order)
  - `NS.Ledger.RowThingKey(row) -> thingKey|nil` (`"g"` for GOLD; `"c:<id>"` / `"i:<id>"`; nil when the row names no id)
  - `NS.Ledger.RollupClose(daily, day, holder, key, close)` — sets `.c`
  - `NS.Ledger.RollupFlow(daily, day, holder, key, dir, qty)` — `IN` adds to `.i`, `OUT` to `.o`; `MOVE` or `qty <= 0` creates nothing
  - `NS.Ledger.PruneDaily(daily, cutoffDay) -> removedDayCount` — deletes days `< cutoffDay`, folding each (holder, key)'s newest pruned close onto `cutoffDay` unless a close is already there; flows are not folded
  - `NS.Ledger.ForgetHolderDaily(daily, holder) -> removedCellCount` — deletes the holder from every day, and days left empty
  - Cell shape: `{ c = <close>|nil, i = <in>|nil, o = <out>|nil }` — an absent field reads as "no close noted" (`c`) or 0 (`i`/`o`).

- [ ] **Step 1: Write the failing tests** — append to `tests/test_ledger.lua`

```lua
-- ── daily rollup cells (timeline ledger P3, spec §4.3) ───────────────────────────────────────

test("Ledger: DayKey is the local calendar day and sorts chronologically", function()
  local late = os.time({ year = 2026, month = 10, day = 6, hour = 23, min = 59 })
  assertEqual(NS.Ledger.DayKey(late), "2026-10-06")
  assertTrue(NS.Ledger.DayKey(late) < NS.Ledger.DayKey(late + 120), "string order is day order")
end)

test("Ledger: RowThingKey covers items, currencies, gold and legacy rows", function()
  local L = NS.Ledger
  assertEqual(L.RowThingKey({ itemID = 7 }), "i:7")                       -- legacy loot row
  assertEqual(L.RowThingKey({ currencyID = 3008 }), "c:3008")
  assertEqual(L.RowThingKey({ kind = "GOLD", quantity = 5 }), "g")
  assertEqual(L.RowThingKey({ kind = "ITEM" }), nil)                       -- no id, no thing
end)

test("Ledger: RollupClose overwrites the day's close; RollupFlow accumulates by direction", function()
  local d, L = {}, NS.Ledger
  L.RollupClose(d, "2026-10-06", "A-R", "g", 100)
  L.RollupClose(d, "2026-10-06", "A-R", "g", 120)
  L.RollupFlow(d, "2026-10-06", "A-R", "g", "IN", 30)
  L.RollupFlow(d, "2026-10-06", "A-R", "g", "IN", 5)
  L.RollupFlow(d, "2026-10-06", "A-R", "g", "OUT", 10)
  local c = d["2026-10-06"]["A-R"].g
  assertEqual(c.c, 120); assertEqual(c.i, 35); assertEqual(c.o, 10)
end)

test("Ledger: a MOVE or a zero flow creates no cell (the rollup stays sparse)", function()
  local d = {}
  NS.Ledger.RollupFlow(d, "2026-10-06", "A-R", "g", "MOVE", 99)
  NS.Ledger.RollupFlow(d, "2026-10-06", "A-R", "g", "IN", 0)
  assertEqual(next(d), nil)
end)

test("Ledger: PruneDaily drops old days and folds each thing's last close onto the cutoff day", function()
  -- Review Focus 3
  local d = {
    ["2026-01-01"] = { ["A-R"] = { g = { c = 10, i = 10 }, ["i:7"] = { c = 3 } } },
    ["2026-02-01"] = { ["A-R"] = { g = { c = 40 } } },
    ["2026-06-01"] = { ["A-R"] = { ["i:7"] = { c = 9 } } },
  }
  assertEqual(NS.Ledger.PruneDaily(d, "2026-05-01"), 2)
  assertEqual(d["2026-01-01"], nil); assertEqual(d["2026-02-01"], nil)
  assertEqual(d["2026-05-01"]["A-R"].g.c, 40, "the newest pruned close is the one carried")
  assertEqual(d["2026-05-01"]["A-R"].g.i, nil, "flows are history, not state: never carried")
  assertEqual(d["2026-05-01"]["A-R"]["i:7"].c, 3, "carried to the cutoff even though June has a close")
  assertEqual(d["2026-06-01"]["A-R"]["i:7"].c, 9, "days at or after the cutoff are untouched")
end)

test("Ledger: PruneDaily never overwrites a close already on the cutoff day", function()
  local d = {
    ["2026-01-01"] = { ["A-R"] = { g = { c = 10 } } },
    ["2026-05-01"] = { ["A-R"] = { g = { c = 77, o = 3 } } },
  }
  NS.Ledger.PruneDaily(d, "2026-05-01")
  assertEqual(d["2026-05-01"]["A-R"].g.c, 77); assertEqual(d["2026-05-01"]["A-R"].g.o, 3)
end)

test("Ledger: PruneDaily with nothing old is a no-op", function()
  local d = { ["2026-06-01"] = { ["A-R"] = { g = { c = 1 } } } }
  assertEqual(NS.Ledger.PruneDaily(d, "2026-05-01"), 0)
  assertEqual(d["2026-05-01"], nil)
end)

test("Ledger: ForgetHolderDaily removes a holder's cells and days it leaves empty", function()
  local d = {
    ["2026-10-01"] = { ["A-R"] = { g = { c = 1 }, ["i:7"] = { c = 2 } } },
    ["2026-10-02"] = { ["A-R"] = { g = { c = 3 } }, ["B-R"] = { g = { c = 4 } } },
  }
  assertEqual(NS.Ledger.ForgetHolderDaily(d, "A-R"), 3)
  assertEqual(d["2026-10-01"], nil)
  assertEqual(d["2026-10-02"]["A-R"], nil); assertEqual(d["2026-10-02"]["B-R"].g.c, 4)
end)
```

- [ ] **Step 2: Run to verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -E "Ledger: (DayKey|RowThingKey|Rollup|Prune|Forget)" | head`
Expected: FAIL — `NS.Ledger.DayKey` (and the others) are nil.

- [ ] **Step 3: Implement** — append to `core/Ledger.lua`

```lua
-- ── Daily rollup cells (timeline-ledger spec §4.3) ───────────────────────────────────────────
--
-- daily[day][holder][thingKey] = { c = close, i = gained, o = lost }. SPARSE twice over: a cell
-- exists only for a (day, holder, thing) that changed, and inside it a field exists only when it is
-- non-zero / known. `c` is the holder's total of the thing at the end of that day as far as the
-- addon has seen; the Timeline carries the last `c` forward across days with no cell.

local DAY_FMT = "%Y-%m-%d"

-- The local calendar day of `ts`. "YYYY-MM-DD" is zero-padded, so plain string comparison orders
-- days chronologically -- PruneDaily and the Timeline's day walk both rely on that.
function Ledger.DayKey(ts) return date(DAY_FMT, ts) end

function Ledger.RowThingKey(r)
  local kind = NS.Util.RowKind(r)
  if kind == "GOLD" then return "g" end
  local id = (kind == "CURRENCY") and r.currencyID or r.itemID
  if id == nil then return nil end
  return Ledger.ThingKey(kind, id)
end

local function cellOf(daily, day, holder, key)
  local d = daily[day]
  if not d then d = {}; daily[day] = d end
  local h = d[holder]
  if not h then h = {}; d[holder] = h end
  local c = h[key]
  if not c then c = {}; h[key] = c end
  return c
end

function Ledger.RollupClose(daily, day, holder, key, close)
  cellOf(daily, day, holder, key).c = close
end

function Ledger.RollupFlow(daily, day, holder, key, dir, qty)
  if not qty or qty <= 0 then return end
  if dir == "IN" then
    local c = cellOf(daily, day, holder, key); c.i = (c.i or 0) + qty
  elseif dir == "OUT" then
    local c = cellOf(daily, day, holder, key); c.o = (c.o or 0) + qty
  end
end

-- Newest close per (holder, key) across `days` (sorted ascending), as last[holder][key].
local function lastCloses(daily, days)
  local last = {}
  for _, day in ipairs(days) do
    for holder, things in pairs(daily[day]) do
      local h = last[holder] or {}
      last[holder] = h
      for key, cell in pairs(things) do
        if cell.c ~= nil then h[key] = cell.c end
      end
    end
  end
  return last
end

-- Drop days before `cutoffDay`. What a pruned day knew that the Timeline still needs is each
-- thing's last close -- without it a balance that did not move after the cutoff would draw nothing
-- until its next change -- so the newest pruned close is folded onto the cutoff day, unless that
-- day already has a close of its own (which is newer). In/out tallies are not folded.
function Ledger.PruneDaily(daily, cutoffDay)
  local old = {}
  for day in pairs(daily) do
    if day < cutoffDay then old[#old + 1] = day end
  end
  if #old == 0 then return 0 end
  table.sort(old)
  local last = lastCloses(daily, old)
  for _, day in ipairs(old) do daily[day] = nil end
  for holder, things in pairs(last) do
    for key, c in pairs(things) do
      local d = daily[cutoffDay]
      local cell = d and d[holder] and d[holder][key]
      if not (cell and cell.c ~= nil) then Ledger.RollupClose(daily, cutoffDay, holder, key, c) end
    end
  end
  return #old
end

function Ledger.ForgetHolderDaily(daily, holder)
  local removed = 0
  for day, holders in pairs(daily) do
    local things = holders[holder]
    if things then
      for _ in pairs(things) do removed = removed + 1 end
      holders[holder] = nil
      if next(holders) == nil then daily[day] = nil end
    end
  end
  return removed
end
```

> `pairs` + assigning `nil` to the key being visited (`daily[day] = nil` inside `ForgetHolderDaily`'s loop) is allowed in Lua 5.1 ("you may clear existing fields during traversal").

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS, 0/0.

- [ ] **Step 5: Regenerate inventory and commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add core/Ledger.lua tests/test_ledger.lua docs/test-cases.md
git commit -m "$(cat <<'EOF'
feat(ledger): daily rollup cell math - DayKey, close/flow, prune with carry, forget holder

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt
EOF
)"
```

---

### Task B4: The rollup writer — `modules/Rollup.lua` and the `NS.Holdings` close seam

**Files:**
- Create: `modules/Rollup.lua`
- Modify: `modules/Holdings.lua` (`ApplyContainer`, `ApplyCurrency`, `ApplyMoney`, `CreditCurrency`, `CreditEscrow` note closes; `ApplyContainer` ends the partial window; new `Holdings:Describe(key)`)
- Modify: `LootHistory.toc` (`modules\Rollup.lua` after `modules\Holdings.lua`)
- Modify: `core/LifecycleSetup.lua` (`StandUp` enables `NS.Rollup` after the Reconciler line; `StandDown` list gains `NS.Rollup`)
- Modify: `tests/test_disabled.lua` (one case: after stand-down a `Database:Add` writes no rollup cell)
- Create: `tests/test_rollup.lua`; Modify: `tests/run.lua` (`"test_rollup"` after `"test_holdings"`)

**Interfaces:**
- Consumes: Task B3's `NS.Ledger.*`; Phase 1's `NS.Holdings:Get/Store/ApplyContainer/ApplyCurrency/ApplyMoney/MarkGenesis`, `NS.Constants.WARBAND_HOLDER`, `NS.Constants.Container`; Phase 2's `NS.Database:OnWrite/RemoveWriteHook/Amend`, `NS.Holdings:CreditCurrency/CreditEscrow`; `NS.Util.RowDir/RowHolder`.
- Produces (on `NS.Rollup`):
  - `:Store() -> db.global.daily`
  - `:NoteClose(holder, key, ts, close)`; `:NoteFlow(holder, key, ts, dir, qty)`
  - `:OnWrite(row, deltaQty, isNew)` — the `NS.Database:OnWrite` receiver (MOVE ignored; an amend is tallied on today; gated on `settings.trackLedger ~= false`)
  - `:ForgetHolder(holder) -> removedCells`
  - `:Keys() -> { [thingKey] = true }` (cached; reset by prune/forget)
  - `:Enable()` / `:Disable()` — register / remove the write hook (`self._hook`, the function handed to `OnWrite`)
  - On `NS.Holdings`: `:Describe(key) -> { name, quality, itemType, itemSubType }`; `entry.meta.completeAt` (ts the gate container — `bank` for characters, `tabs` for the warband — was first scanned after genesis; `meta.partial` flips to false then).

- [ ] **Step 1: Write the failing test** — `tests/test_rollup.lua`

```lua
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local T0 = os.time({ year = 2026, month = 10, day = 3, hour = 12 })
local function day(ts) return os.date("%Y-%m-%d", ts) end
local function reset() NS.db.global.daily, NS.db.global.holdings = {}, {} end
local function cell(ts, holder, key)
  local d = NS.db.global.daily[day(ts)]
  return d and d[holder] and d[holder][key]
end

test("Rollup: a holdings change writes that day's close for the thing that moved", function()
  reset()
  NS.Holdings:ApplyContainer("A-R", "bags", { [7] = 5 }, {}, T0)
  NS.Holdings:ApplyContainer("A-R", "bank", { [7] = 10 }, {}, T0 + 60)
  assertEqual(cell(T0, "A-R", "i:7").c, 15, "close = total across containers, after the write")
end)

test("Rollup: an unchanged thing writes no cell", function()
  reset()
  NS.Holdings:ApplyContainer("A-R", "bags", { [7] = 5, [8] = 1 }, {}, T0)
  NS.db.global.daily = {}
  NS.Holdings:ApplyContainer("A-R", "bags", { [7] = 4, [8] = 1 }, {}, T0 + 86400)
  assertEqual(cell(T0 + 86400, "A-R", "i:7").c, 4)
  assertEqual(cell(T0 + 86400, "A-R", "i:8"), nil)
end)

test("Rollup: a thing leaving every container closes at 0", function()
  reset()
  NS.Holdings:ApplyContainer("A-R", "bags", { [7] = 5 }, {}, T0)
  NS.Holdings:ApplyContainer("A-R", "bags", {}, {}, T0 + 5)
  assertEqual(cell(T0, "A-R", "i:7").c, 0)
end)

test("Rollup: currency and money changes write closes", function()
  reset()
  NS.Holdings:ApplyCurrency("A-R", { [3008] = 40, [2245] = 1 }, T0)
  NS.Holdings:ApplyCurrency("A-R", { [3008] = 55 }, T0 + 1)
  NS.Holdings:ApplyMoney("A-R", 12345, T0 + 2)
  assertEqual(cell(T0, "A-R", "c:3008").c, 55)
  assertEqual(cell(T0, "A-R", "c:2245").c, 0, "a currency that left the map closes at 0")
  assertEqual(cell(T0, "A-R", "g").c, 12345)
end)

test("Rollup: the write hook tallies gains and losses; transfers tally nothing", function()
  reset()
  local R = NS.Rollup
  R:OnWrite({ ts = T0, dir = "IN", kind = "GOLD", holder = "A-R", quantity = 500 }, 500, true)
  R:OnWrite({ ts = T0, dir = "OUT", kind = "GOLD", holder = "A-R", quantity = 200 }, 200, true)
  R:OnWrite({ ts = T0, dir = "MOVE", kind = "GOLD", holder = "A-R", quantity = 999,
    from = "A-R/money", to = "§warband/money" }, 999, true)
  R:OnWrite({ ts = T0, itemID = 7, quantity = 3, char = "A-R" }, 3, true)   -- a legacy-shaped chat row
  assertEqual(cell(T0, "A-R", "g").i, 500); assertEqual(cell(T0, "A-R", "g").o, 200)
  assertEqual(cell(T0, "A-R", "i:7").i, 3)
end)

test("Rollup: an amend tallies only its delta, on the day it happens", function()
  reset()
  if not NS.Rollup._hook then NS.Rollup:Enable() end
  local h = NS.db.global.history
  local n = #h
  local now = time()
  local idx = NS.Database:Add({ ts = now, dir = "OUT", kind = "ITEM", itemID = 9, holder = "A-R", quantity = 2 })
  NS.Database:Amend(idx, 3)
  assertEqual(cell(now, "A-R", "i:9").o, 5, "2 from the row plus 3 from the amend -- never 2 + 5")
  for i = #h, n + 1, -1 do h[i] = nil end
end)

test("Rollup: the gate container's first scan after genesis ends the partial window", function()
  reset()
  NS.Holdings:ApplyContainer("A-R", "bags", { [7] = 1 }, {}, T0)
  NS.Holdings:MarkGenesis("A-R", T0)
  assertTrue(NS.Holdings:Get("A-R").meta.partial)
  NS.Holdings:ApplyContainer("A-R", "bank", { [7] = 2 }, {}, T0 + 500)
  local m = NS.Holdings:Get("A-R").meta
  assertFalse(m.partial); assertEqual(m.completeAt, T0 + 500)
  NS.Holdings:ApplyContainer("A-R", "bank", { [7] = 3 }, {}, T0 + 900)
  assertEqual(NS.Holdings:Get("A-R").meta.completeAt, T0 + 500, "set once")
end)

test("Rollup: the warband's gate is its tabs", function()
  reset()
  NS.Holdings:ApplyMoney("§warband", 10, T0)
  NS.Holdings:MarkGenesis("§warband", T0)
  NS.Holdings:ApplyContainer("§warband", "tabs", { [7] = 1 }, {}, T0 + 10)
  assertEqual(NS.Holdings:Get("§warband").meta.completeAt, T0 + 10)
end)

test("Rollup: wired through the write hook - Database:Add reaches the tally", function()
  reset()
  if not NS.Rollup._hook then NS.Rollup:Enable() end
  local h = NS.db.global.history
  local n = #h
  NS.Database:Add({ ts = T0, dir = "IN", kind = "GOLD", holder = "A-R", quantity = 9, itemName = "Gold" })
  assertEqual(cell(T0, "A-R", "g").i, 9)
  h[n + 1] = nil
end)

test("Rollup: Keys indexes every thing in the rollup and learns new ones", function()
  reset()
  NS.Rollup._keys = nil
  NS.Holdings:ApplyMoney("A-R", 1, T0)
  local k = NS.Rollup:Keys()
  assertTrue(k.g)
  NS.Holdings:ApplyCurrency("A-R", { [3008] = 1 }, T0)
  assertTrue(NS.Rollup:Keys()["c:3008"], "a new key joins the cached index")
end)

test("Rollup: escrow and currency credits write closes too (Phase 2's direct holdings writes)", function()
  reset()
  NS.Holdings:ApplyContainer("Alt-R", "bags", { [7] = 1 }, {}, T0)
  NS.Holdings:ApplyCurrency("Alt-R", { [3008] = 10 }, T0)
  NS.db.global.daily = {}
  NS.Holdings:CreditEscrow("Alt-R", "mail", 7, 4)
  NS.Holdings:CreditCurrency("Alt-R", 3008, 5)
  local today = time()
  assertEqual(cell(today, "Alt-R", "i:7").c, 5)
  assertEqual(cell(today, "Alt-R", "c:3008").c, 15)
end)

test("Rollup: Disable removes the write hook", function()
  reset()
  NS.Rollup:Disable()
  local h = NS.db.global.history
  local n = #h
  NS.Database:Add({ ts = T0, dir = "IN", kind = "GOLD", holder = "A-R", quantity = 9 })
  assertEqual(cell(T0, "A-R", "g"), nil)
  h[n + 1] = nil
  NS.Rollup:Enable()
end)

test("Rollup: ForgetHolder drops every cell of that holder", function()
  reset()
  NS.Holdings:ApplyMoney("A-R", 1, T0); NS.Holdings:ApplyMoney("B-R", 2, T0)
  assertEqual(NS.Rollup:ForgetHolder("A-R"), 1)
  assertEqual(cell(T0, "A-R", "g"), nil); assertEqual(cell(T0, "B-R", "g").c, 2)
end)

test("Holdings: Describe names a thing by key, Gold included", function()
  reset()
  assertEqual(NS.Holdings:Describe("g").name, "Gold")
  NS.Holdings:ApplyContainer("A-R", "bags", { [7] = 1 }, { [7] = "|Hitem:7|h[Apple]|h" }, T0)
  assertTrue(type(NS.Holdings:Describe("i:7").name) == "string")
end)
```

Add `"test_rollup"` after `"test_holdings"` in `tests/run.lua`.

- [ ] **Step 2: Run to verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -E "Rollup:|Describe|FAIL" | head`
Expected: FAIL — `NS.Rollup` is nil; no `daily` cells are written.

- [ ] **Step 3: Implement**

`modules/Rollup.lua`:

```lua
local _, NS = ...
NS.Rollup = NS.Rollup or {}
local Rollup = NS.Rollup

-- The daily rollup writer (timeline-ledger spec §4.3). Two seams feed it, and the choice is the
-- plan's "Phase 2 contract":
--   * CLOSES come from NS.Holdings' write methods (NoteClose), because a close is a holdings fact
--     and those methods are the only place a total changes -- genesis, drift, moves, both sides of
--     a transfer and escrow credits included -- with nothing to know about the Reconciler.
--   * IN / OUT TALLIES come from NS.Database:OnWrite (OnWrite), because a row is where direction
--     lives and the hook hands over the quantity that CHANGED, so an amended row is counted once per
--     delta. RECORD_ADDED is not used for this: it is re-sent on every amend and is a repaint signal
--     only (Phase 2 plan, S2).
-- Both are O(1) per change. Pruning and the one-time seed run off the login deferral
-- (core/LootHistory.lua), never on an event.

local Ledger = NS.Ledger

function Rollup:Store()
  local g = NS.db and NS.db.global
  if not g then return {} end
  g.daily = g.daily or {}
  return g.daily
end

local function learnKey(self, key)
  if self._keys then self._keys[key] = true end
end

function Rollup:NoteClose(holder, key, ts, close)
  Ledger.RollupClose(self:Store(), Ledger.DayKey(ts), holder, key, close)
  learnKey(self, key)
end

function Rollup:NoteFlow(holder, key, ts, dir, qty)
  Ledger.RollupFlow(self:Store(), Ledger.DayKey(ts), holder, key, dir, qty)
  learnKey(self, key)
end

local function ledgerOn()
  local s = NS.db and NS.db.profile and NS.db.profile.settings
  return not s or s.trackLedger ~= false
end

-- The Database write hook. `delta` is what this write changed (the whole quantity for a new row,
-- the added amount for an amend). A new row is tallied on its own day; an amend on today, because
-- the 60 s coalescing window may straddle midnight.
function Rollup:OnWrite(row, delta, isNew)
  if not (row and ledgerOn()) then return end
  local dir = NS.Util.RowDir(row)
  if dir == "MOVE" then return end
  local key, holder = Ledger.RowThingKey(row), NS.Util.RowHolder(row)
  if not (key and holder) then return end
  local ts = (isNew ~= false) and (row.ts or time()) or time()
  self:NoteFlow(holder, key, ts, dir, delta or 0)
end

function Rollup:ForgetHolder(holder)
  self._keys = nil
  return Ledger.ForgetHolderDaily(self:Store(), holder)
end

-- Every thing the rollup has a cell for. Built once per session from the store and kept current by
-- NoteClose/NoteFlow, so the Timeline's picker can offer a thing nobody holds any more without
-- walking every day on every keystroke.
function Rollup:Keys()
  if self._keys then return self._keys end
  local keys = {}
  for _, holders in pairs(self:Store()) do
    for _, things in pairs(holders) do
      for key in pairs(things) do keys[key] = true end
    end
  end
  self._keys = keys
  return keys
end

-- A write hook, not a bus subscription: it holds no event or message registration, so the
-- disabled-state survey has nothing of it to find, and the stand-down proof is behavioral (a row
-- written while stood down tallies nothing -- tests/test_rollup.lua, tests/test_disabled.lua).
function Rollup:Enable()
  if self._hook or not (NS.Database and NS.Database.OnWrite) then return end
  self._hook = NS.Database:OnWrite(function(row, delta, isNew) Rollup:OnWrite(row, delta, isNew) end)
end

function Rollup:Disable()
  if not self._hook then return end
  NS.Database:RemoveWriteHook(self._hook)
  self._hook = nil
end
```

`modules/Holdings.lua` — add near the top (after `local WARBAND = C.WARBAND_HOLDER`):

```lua
-- The rollup's close seam (timeline-ledger P3, plan "Phase 2 contract"): every total that changes
-- here is reported once, after the write, so the Timeline's daily close is exactly this store.
local function noteClose(holder, key, ts, n)
  if NS.Rollup and NS.Rollup.NoteClose then NS.Rollup:NoteClose(holder, key, ts, n) end
end

local function itemTotal(row)
  local n = 0
  if row then for _, k in pairs(row) do n = n + k end end
  return n
end

-- A holder is partial from genesis until its gate container (bank / warband tabs) is first read;
-- the Timeline draws that stretch dashed, so the moment it ends is recorded once.
local function endPartial(e, holder, container, ts)
  local gate = (holder == WARBAND) and C.Container.TABS or C.Container.BANK
  if container == gate and e.meta.genesis and e.meta.partial and not e.meta.completeAt then
    e.meta.partial, e.meta.completeAt = false, ts
  end
end
```

Replace Phase 1's `Holdings:ApplyContainer` with:

```lua
function Holdings:ApplyContainer(holder, container, counts, links, ts)
  local e = self:Get(holder, true)
  local touched = {}
  for id, row in pairs(e.items) do
    local want = counts[id]
    if row[container] ~= want then
      row[container] = want; touched[id] = true
      if next(row) == nil then e.items[id] = nil end
    end
  end
  for id, n in pairs(counts) do
    local row = e.items[id]
    if not row then row = {}; e.items[id] = row end
    if row[container] ~= n then row[container] = n; touched[id] = true end
  end
  for id, link in pairs(links or {}) do e.links[id] = link end
  e.scanned[container] = ts
  e.meta.lastSeen = ts
  endPartial(e, holder, container, ts)
  local changed = false
  for id in pairs(touched) do
    changed = true
    noteClose(holder, "i:" .. id, ts, itemTotal(e.items[id]))
  end
  return changed
end
```

Replace `Holdings:ApplyCurrency` and `Holdings:ApplyMoney` with:

```lua
function Holdings:ApplyCurrency(holder, map, ts)
  local e = self:Get(holder, true)
  local old, changed = e.currency, false
  for id, n in pairs(map) do
    if old[id] ~= n then changed = true; noteClose(holder, "c:" .. id, ts, n) end
  end
  for id in pairs(old) do
    if map[id] == nil then changed = true; noteClose(holder, "c:" .. id, ts, 0) end
  end
  e.currency = map
  e.scanned.currency, e.meta.lastSeen = ts, ts
  return changed
end

function Holdings:ApplyMoney(holder, copper, ts)
  local e = self:Get(holder, true)
  local changed = e.money ~= copper
  e.money = copper
  e.scanned.money, e.meta.lastSeen = ts, ts
  if changed then noteClose(holder, "g", ts, copper or 0) end
  return changed
end
```

Phase 2's two direct writes note their closes too — one line before each one's `return true`:

```lua
-- in Holdings:CreditCurrency(holder, id, qty), after e.currency[id] is set:
  noteClose(holder, "c:" .. id, time(), e.currency[id] or 0)

-- in Holdings:CreditEscrow(holder, container, id, qty, own), after row[container] is set:
  noteClose(holder, "i:" .. id, time(), itemTotal(e.items[id]))
```

(`sameMap` from Phase 1 becomes unused — delete it so luacheck stays 0/0.)

After Phase 1's local `describe`, publish it:

```lua
-- The display fields for one thing key, for surfaces that hold a key and not a Search row (the
-- Timeline's title and its picker's rollup-only suggestions). Uses any holder's last-seen link.
function Holdings:Describe(key)
  local kind, id = NS.Ledger.ParseThingKey(key)
  if not kind then return { name = tostring(key) } end
  local link
  if kind == "ITEM" then
    for _, e in pairs(self:Store()) do link = link or (e.links and e.links[id]) end
  end
  return describe(key, kind, id, link)
end
```

`LootHistory.toc`: `modules\Rollup.lua` on the line after `modules\Holdings.lua`. `core/LifecycleSetup.lua`: `if NS.Rollup and NS.Rollup.Enable then NS.Rollup:Enable() end` in `StandUp` after the Reconciler line; add `NS.Rollup` to `StandDown`'s `ipairs({ ... })` list. `tests/test_disabled.lua`: add a case beside the stand-down survey — after `NS.StandDown`, `NS.Database:Add({ ts = time(), dir = "IN", kind = "GOLD", holder = "A-R", quantity = 1 })` leaves `db.global.daily` unchanged (compare a deep copy taken before), then remove the row and stand back up; the write hook is not a registration, so the survey alone cannot see it.

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS — all `Rollup:` cases; Phase 1's `test_holdings` cases unchanged (the Apply methods return the same booleans); `test_disabled`'s new case shows a stood-down addon tallies nothing. 0/0.

- [ ] **Step 5: Regenerate inventory and commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add modules/Rollup.lua modules/Holdings.lua LootHistory.toc core/LifecycleSetup.lua tests/test_rollup.lua \
  tests/test_disabled.lua tests/run.lua docs/test-cases.md
git commit -m "$(cat <<'EOF'
feat(rollup): daily rollup writer - closes from Holdings, in/out from the Database write hook

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt
EOF
)"
```

---

### Task B5: Rollup retention, the login prune and the one-time seed

**Files:**
- Modify: `modules/Rollup.lua` (append `SeedOnce`, `Prune`)
- Modify: `core/Constants.lua` (append `C.ROLLUP_RETENTION_OPTIONS` after `C.RETENTION_OPTIONS`, ~line 118)
- Modify: `defaults/Global.lua` (`rollupRetentionDays = 0`; comment that `rollupSeeded` is deliberately undeclared)
- Modify: `settings/Schema.lua` (row after `settings.retentionDays`, ~line 407; `S.RESET_EXEMPT` entry, ~line 475)
- Modify: `core/LootHistory.lua:138-141` (login deferral)
- Modify: `tests/test_rollup.lua` (append), `tests/test_schema.lua:648-652` (`{ "History", 2 }`) and `:707-725` (drop the `History` exemption and its comment)

**Interfaces:**
- Consumes: Task B3/B4.
- Produces:
  - `NS.Rollup:SeedOnce(ts) -> cellsWritten` — once per account (`db.global.rollupSeeded`), writes today's close for every (holder, thing) in holdings that has no close today, so a thing that never changes after the Phase-3 upgrade still has a line.
  - `NS.Rollup:Prune(now) -> removedDays` — `db.global.rollupRetentionDays` (0 = Always = no-op).
  - `NS.Constants.ROLLUP_RETENTION_OPTIONS` (`90, 180, 365, 730, 0`).
  - Schema row `settings.rollupRetentionDays` (stored at `db.global.rollupRetentionDays`, default 0, General ▸ History, `RESET_EXEMPT`).

- [ ] **Step 1: Write the failing tests** — append to `tests/test_rollup.lua`

```lua
test("Rollup: Prune with Always (0) keeps every day", function()
  reset()
  NS.db.global.daily = { ["2020-01-01"] = { ["A-R"] = { g = { c = 1 } } } }
  NS.db.global.rollupRetentionDays = 0
  assertEqual(NS.Rollup:Prune(T0), 0)
  assertTrue(NS.db.global.daily["2020-01-01"] ~= nil)
end)

test("Rollup: Prune drops days past the retention and carries their closes", function()
  reset()
  NS.db.global.daily = {
    [day(T0 - 400 * 86400)] = { ["A-R"] = { g = { c = 5 } } },
    [day(T0 - 10 * 86400)] = { ["A-R"] = { ["i:7"] = { c = 1 } } },
  }
  NS.db.global.rollupRetentionDays = 365
  assertEqual(NS.Rollup:Prune(T0), 1)
  local cutoff = day(T0 - 365 * 86400)
  assertEqual(NS.db.global.daily[cutoff]["A-R"].g.c, 5)
  NS.db.global.rollupRetentionDays = 0
end)

test("Rollup: SeedOnce writes today's close for every held thing, once per account", function()
  reset()
  NS.db.global.rollupSeeded = nil
  NS.db.global.holdings = { ["A-R"] = { meta = {}, scanned = {}, links = {},
    items = { [7] = { bags = 2, bank = 3 } }, currency = { [3008] = 4 }, money = 99 } }
  local n = NS.Rollup:SeedOnce(T0)
  assertEqual(n, 3)
  assertEqual(cell(T0, "A-R", "i:7").c, 5); assertEqual(cell(T0, "A-R", "c:3008").c, 4)
  assertEqual(cell(T0, "A-R", "g").c, 99)
  assertEqual(NS.db.global.rollupSeeded, T0)
  assertEqual(NS.Rollup:SeedOnce(T0 + 86400), 0, "the second call is a no-op")
  NS.db.global.rollupSeeded = nil
end)

test("Rollup: SeedOnce never overwrites a close already written today", function()
  reset()
  NS.db.global.rollupSeeded = nil
  NS.db.global.holdings = { ["A-R"] = { meta = {}, scanned = {}, links = {}, items = {}, currency = {}, money = 99 } }
  NS.Rollup:NoteClose("A-R", "g", T0, 42)
  NS.Rollup:SeedOnce(T0)
  assertEqual(cell(T0, "A-R", "g").c, 42)
  NS.db.global.rollupSeeded = nil
end)

test("Schema: rollupRetentionDays is account-wide, defaults to Always and is reset-exempt", function()
  local S = NS.Schema
  local row = S:FindRow("settings.rollupRetentionDays")
  assertTrue(row ~= nil)
  assertEqual(row.default, 0); assertEqual(row.group, "History")
  S:Set("settings.rollupRetentionDays", 365)
  assertEqual(NS.db.global.rollupRetentionDays, 365)
  assertEqual(NS.db.profile.settings.rollupRetentionDays, nil, "never stored per profile")
  assertEqual(S.RESET_EXEMPT["settings.rollupRetentionDays"], "rollupRetentionDays")
  S:Set("settings.rollupRetentionDays", 0)
end)
```

In `tests/test_schema.lua` change the partition to `{ "History", 2 }` and replace the exemption case's body so the rule binds every tab:

```lua
test("Schema: no tab holds fewer than two controls", function()
  -- General ▸ History was exempted by name while it held one stored row; the rollup retention row
  -- (timeline ledger P3) made it two, so the rule now binds every tab with no exemption.
  -- red under: a tab losing rows until one is left, or a new one-row group.
  local counts, pageOf = {}, {}
  for _, row in ipairs(S.Schema) do
    counts[row.group] = (counts[row.group] or 0) + 1
    pageOf[row.group] = row.page
  end
  for group, n in pairs(counts) do
    assertTrue(n >= 2, pageOf[group] .. " / " .. group .. " holds only " .. n)
  end
end)
```

- [ ] **Step 2: Run to verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -E "Prune|SeedOnce|rollupRetention|History|FAIL" | head`
Expected: FAIL — `NS.Rollup.Prune` / `SeedOnce` nil; `FindRow` answers nil; the partition says History 1.

- [ ] **Step 3: Implement**

`modules/Rollup.lua` — append:

```lua
local DAY = 86400

local function seedCell(daily, day, holder, key, n)
  local d = daily[day]
  local c = d and d[holder] and d[holder][key]
  if c and c.c ~= nil then return 0 end
  Ledger.RollupClose(daily, day, holder, key, n)
  return 1
end

local function seedHolder(daily, day, holder, e)
  local n = 0
  for id, row in pairs(e.items or {}) do
    local total = 0
    for _, k in pairs(row) do total = total + k end
    n = n + seedCell(daily, day, holder, "i:" .. id, total)
  end
  for id, q in pairs(e.currency or {}) do n = n + seedCell(daily, day, holder, "c:" .. id, q) end
  if e.money then n = n + seedCell(daily, day, holder, "g", e.money) end
  return n
end

-- Once per account. Holdings that existed before the rollup was written (the Phase 1/2 releases)
-- have no cell anywhere, and a thing that never changes again would never get one, so its line would
-- never draw. Today's close of everything held is the honest starting point.
function Rollup:SeedOnce(ts)
  local g = NS.db and NS.db.global
  if not g or g.rollupSeeded then return 0 end
  local daily, day, n = self:Store(), Ledger.DayKey(ts), 0
  for holder, e in pairs(NS.Holdings:Store()) do n = n + seedHolder(daily, day, holder, e) end
  g.rollupSeeded = ts
  self._keys = nil
  if NS.State.debug and NS.Debug then NS.Debug("Rollup", "seeded %d cells", n) end
  return n
end

function Rollup:Prune(now)
  local days = NS.db and NS.db.global and NS.db.global.rollupRetentionDays
  if not days or days == 0 then
    if NS.State.debug and NS.Debug then NS.Debug("Rollup", "prune skipped: retention is Always") end
    return 0
  end
  local removed = Ledger.PruneDaily(self:Store(), Ledger.DayKey((now or time()) - days * DAY))
  if removed > 0 then self._keys = nil end
  if NS.State.debug and NS.Debug then NS.Debug("Rollup", "retention %dd: removed %d days", days, removed) end
  return removed
end
```

`core/Constants.lua` — after `C.RETENTION_OPTIONS`:

```lua
-- How long the Timeline's daily rollup is kept (settings.rollupRetentionDays). Longer floors than the
-- raw history's: the rollup is the long-term record, one small cell per changed thing per day.
C.ROLLUP_RETENTION_OPTIONS = {
  { value = 90,  text = "90 days" },
  { value = 180, text = "180 days" },
  { value = 365, text = "1 year" },
  { value = 730, text = "2 years" },
  { value = 0,   text = "Always" },
}
```

`defaults/Global.lua` — after `retentionDays = 30,`:

```lua
  rollupRetentionDays = 0,   -- the Timeline's daily rollup: 0 = Always (spec §11)
  -- rollupSeeded (ts of the one-time seed, modules/Rollup.lua) is deliberately NOT declared, for
  -- the reason ledgerSince is not: AceDB strips a value equal to its default.
```

`settings/Schema.lua` — after the `settings.retentionDays` row, inside `ROWS`:

```lua
  -- The Timeline's daily rollup (timeline ledger P3). ACCOUNT-WIDE for the reason retentionDays is
  -- (D6): it governs recorded data every profile shares. No confirm: nothing is deleted on change --
  -- the prune runs once per session from the login deferral (core/LootHistory.lua), so the new
  -- window takes effect at the next login, which the tooltip says.
  { path = "settings.rollupRetentionDays", default = GD.rollupRetentionDays, type = "number",
    widget = "Dropdown", page = "General", group = "History", label = "Keep Timeline days for",
    values = C.ROLLUP_RETENTION_OPTIONS,
    tooltip = "How long the Timeline keeps its daily balances. 'Always' keeps every day. A shorter "
      .. "window is applied at your next login; each line still starts from its last known value. "
      .. "Account-wide.",
    get = function()
      local g = NS.db and NS.db.global
      return g and g.rollupRetentionDays
    end,
    set = function(days)
      local g = NS.db and NS.db.global
      if g then g.rollupRetentionDays = days end
    end },
```

`S.RESET_EXEMPT` gains:

```lua
  ["settings.rollupRetentionDays"] = "rollupRetentionDays",
```

(and its doc comment gets one sentence: "`settings.rollupRetentionDays` is the third, for the same reason as the second.")

`core/LootHistory.lua` — inside the `NS.After(5, function() … end)` in `OnEnterWorld`, after the `PruneOld` line:

```lua
    -- The Timeline's rollup: seed once (holdings that predate it), then prune by its own retention.
    -- After the 3 s login scan, so the seed reads this login's holdings.
    if NS.Rollup and NS.Rollup._hook then
      NS.Rollup:SeedOnce(time())
      NS.Rollup:Prune(time())
    end
```

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS. If `tests/test_panel.lua` pins the General ▸ History tab's rendered widget count, it now sees one more dropdown: update that pin (grep `History` in `tests/test_panel.lua`). If `tests/test_profiles.lua` enumerates global default keys, add `rollupRetentionDays`. 0/0.

- [ ] **Step 5: Regenerate inventory and commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add modules/Rollup.lua core/Constants.lua defaults/Global.lua settings/Schema.lua core/LootHistory.lua \
  tests/test_rollup.lua tests/test_schema.lua tests/test_panel.lua tests/test_profiles.lua docs/test-cases.md
git commit -m "$(cat <<'EOF'
feat(rollup): rollupRetentionDays (account-wide, default Always), login prune and one-time seed

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt
EOF
)"
```

(Drop any path from `git add` that did not change.)

---

### Task B6: The Timeline model (pure) — `modules/TimelineModel.lua`

**Files:**
- Create: `modules/TimelineModel.lua`
- Modify: `LootHistory.toc` (`modules\TimelineModel.lua` after `modules\HoldingsTab.lua`)
- Modify: `core/Constants.lua` (append `C.TIMELINE`)
- Create: `tests/test_timeline.lua`; Modify: `tests/run.lua` (`"test_timeline"` after `"test_holdingstab"`)

**Interfaces:**
- Consumes: `NS.Ledger.DayKey/RowThingKey/ParseThingKey`, `NS.Util.RowDir/RowHolder/FormatMoney`, `NS.Holdings:Total/Get/Describe`, `NS.Constants.WARBAND_HOLDER/DirRGB`, `NS.LedgerFormat.HolderLabel` (Phase 2), `RAID_CLASS_COLORS`, `date`, `time`.
- Produces (on `NS.TimelineModel`, all pure except `Build`/`Latest`/`Meta`, which read `NS.Holdings`):
  - `TM.TOTAL = "__total"`
  - `TM.DayStart(day) -> ts` (local midnight); `TM.NextDay(day) -> day`; `TM.SortedDays(daily) -> {day...}`
  - `TM.CloseBefore(daily, days, holder, key, day) -> close|nil` (newest close strictly before `day`)
  - `TM.DailySeries(daily, days, holder, key, fromDay, toDay, genesisDay) -> points` (one point per day at its midnight, carry-forward, starts at the later of `fromDay` / `genesisDay`, nothing before the first known close)
  - `TM.ValueAt(points, x) -> y|nil` (last point with `x' <= x`)
  - `TM.TotalSeries({points...}) -> points` (sum at the union of x; a series not started yet counts 0)
  - `TM.RankHolders(latest, candidates, allowed, cap) -> {holder...}` (allowed applied first; empty set = nil)
  - `TM.RowDelta(row, holder) -> signed qty`; `TM.IntradaySeries(history, holder, key, from, now, current, anchor) -> points|nil`
  - `TM.IntradayOK(range, from, now, retentionDays, ledgerSince) -> boolean`
  - `TM.Flows(daily, days, holders, key, fromDay, toDay) -> { {x, day, i, o} ... }`
  - `TM.DashRange(meta, now) -> dashFrom|nil, dashTo|nil`
  - `TM.Label(holder) -> string`; `TM.Color(holder, meta) -> {r,g,b,a}`
  - `TM.FormatValue(kind, v) -> string`
  - `TM.Suggest(text, things, limit) -> things` (Gold first, then by total, capped)
  - `TM.Build(p) -> model` with `p = { thing, range, from, now, allowed, maxLines, daily, history, ledgerSince, retentionDays }` and `model = { key, kind, title, mode = "daily"|"intraday", now, xMin, xMax, series = { {holder, label, color, thickness, points, dashFrom, dashTo} ... Total last }, flows, flowByX, hoverXs, markers }`
  - `TM.HoverLines(model, i) -> { title, rows = { {label, text, color} }, gain, loss }|nil`
  - `TM.ChartData(model) -> data` for `chart:SetData` (gold scaled to gold units for the chart only)
  - `NS.Constants.TIMELINE = { TOTAL, WARBAND, OTHER, MARKER, GAIN, LOSS, TOTAL_W, LINE_W }`

- [ ] **Step 1: Write the failing test** — `tests/test_timeline.lua`

```lua
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local DAY = 86400
local function TM() return NS.TimelineModel end
local function noon(y, m, d) return os.time({ year = y, month = m, day = d, hour = 12 }) end

local function seedMoney(holders, ts)
  NS.db.global.holdings, NS.db.global.daily = {}, {}
  for h, copper in pairs(holders) do NS.Holdings:ApplyMoney(h, copper, ts) end
end

local function params(over)
  local p = { thing = "g", range = "30d", now = noon(2026, 10, 5), maxLines = 8,
    daily = NS.db.global.daily, history = {}, retentionDays = 0 }
  p.from = p.now - 30 * DAY
  for k, v in pairs(over or {}) do p[k] = v end
  return p
end

local function byHolder(m, h)
  for _, s in ipairs(m.series) do if s.holder == h then return s end end
end

-- ── day walk ──

test("Timeline model: NextDay and DayStart walk local calendar days", function()
  assertEqual(TM().NextDay("2026-10-31"), "2026-11-01")
  assertEqual(TM().NextDay("2026-12-31"), "2027-01-01")
  assertEqual(os.date("*t", TM().DayStart("2026-10-25")).hour, 0)
  assertEqual(NS.Ledger.DayKey(TM().DayStart("2026-10-25")), "2026-10-25")
end)

-- ── carry-forward ──

test("Timeline model: DailySeries carries the last close forward", function()
  -- Review Focus 2: no change inside the range still draws a flat line at the pre-range close
  local daily = { ["2026-09-01"] = { ["A-R"] = { g = { c = 500 } } } }
  local pts = TM().DailySeries(daily, TM().SortedDays(daily), "A-R", "g", "2026-10-01", "2026-10-03", nil)
  assertEqual(#pts, 3)
  for _, p in ipairs(pts) do assertEqual(p.y, 500) end
  assertEqual(pts[1].x, TM().DayStart("2026-10-01"))
end)

test("Timeline model: DailySeries starts at genesis and picks up each day's close", function()
  local daily = {
    ["2026-10-02"] = { ["A-R"] = { g = { c = 10 } } },
    ["2026-10-04"] = { ["A-R"] = { g = { c = 30, i = 20 } } },
  }
  local pts = TM().DailySeries(daily, TM().SortedDays(daily), "A-R", "g", "2026-10-01", "2026-10-05", "2026-10-02")
  assertEqual(#pts, 4)       -- 02, 03 (carried), 04, 05 (carried); nothing for 01
  assertEqual(pts[1].y, 10); assertEqual(pts[2].y, 10); assertEqual(pts[3].y, 30); assertEqual(pts[4].y, 30)
end)

test("Timeline model: a flow-only cell does not break the carry", function()
  local daily = {
    ["2026-10-01"] = { ["A-R"] = { g = { c = 10 } } },
    ["2026-10-02"] = { ["A-R"] = { g = { i = 4 } } },
  }
  local pts = TM().DailySeries(daily, TM().SortedDays(daily), "A-R", "g", "2026-10-01", "2026-10-02", nil)
  assertEqual(pts[2].y, 10)
end)

test("Timeline model: ValueAt and TotalSeries treat a not-yet-started holder as 0", function()
  local a = { { x = 1, y = 10 }, { x = 2, y = 20 } }
  local b = { { x = 2, y = 5 } }
  assertEqual(TM().ValueAt(a, 1.5), 10); assertEqual(TM().ValueAt(b, 1), nil)
  local t = TM().TotalSeries({ a, b })
  assertEqual(#t, 2)
  assertEqual(t[1].y, 10); assertEqual(t[2].y, 25)
end)

-- ── ranking and the cap ──

test("Timeline model: RankHolders applies the Character filter before the cap", function()
  -- Review Focus 4
  local latest = { ["A-R"] = 100, ["B-R"] = 300, ["C-R"] = 200, ["§warband"] = 50 }
  local cands = { "A-R", "B-R", "C-R", "§warband" }
  assertEqual(table.concat(TM().RankHolders(latest, cands, nil, 2), ","), "B-R,C-R")
  assertEqual(table.concat(TM().RankHolders(latest, cands, { ["A-R"] = true, ["§warband"] = true }, 2), ","),
    "A-R,§warband")
  assertEqual(#TM().RankHolders(latest, cands, {}, 8), 4, "an empty selection means everyone")
end)

test("Timeline model: Build draws Total plus at most maxLines holders, richest first", function()
  -- Review Focus 4, end to end
  local holders = {}
  for i = 1, 12 do holders[("H%02d-R"):format(i)] = i * 100 end
  seedMoney(holders, noon(2026, 10, 1))
  local m = TM().Build(params({ maxLines = 8 }))
  assertEqual(#m.series, 9)
  assertEqual(m.series[#m.series].holder, TM().TOTAL, "Total is drawn last, on top")
  assertEqual(m.series[1].holder, "H12-R")
  assertEqual(m.series[#m.series].points[#m.series[#m.series].points].y,
    1200 + 1100 + 1000 + 900 + 800 + 700 + 600 + 500, "Total sums the SHOWN holders")
end)

test("Timeline model: a holder with nothing now but a balance in range is still a candidate", function()
  seedMoney({ ["A-R"] = 100, ["B-R"] = 50 }, noon(2026, 10, 1))
  NS.Holdings:ApplyMoney("B-R", 0, noon(2026, 10, 3))
  local m = TM().Build(params())
  assertTrue(byHolder(m, "B-R") ~= nil)
  assertEqual(byHolder(m, "B-R").points[#byHolder(m, "B-R").points].y, 0)
end)

-- ── decorations ──

test("Timeline model: ledgerSince inside the range is a dashed marker; outside it is not", function()
  seedMoney({ ["A-R"] = 1 }, noon(2026, 10, 1))
  local inside = TM().Build(params({ ledgerSince = noon(2026, 10, 2) }))
  assertEqual(#inside.markers, 1); assertTrue(inside.markers[1].dashed)
  local outside = TM().Build(params({ ledgerSince = noon(2026, 1, 1) }))
  assertEqual(#outside.markers, 0)
end)

test("Timeline model: a partial holder is dashed from genesis until its bank was first seen", function()
  local g, done = noon(2026, 10, 1), noon(2026, 10, 3)
  assertEqual(TM().DashRange({ genesis = g, partial = false, completeAt = done }, 0), g)
  assertEqual(select(2, TM().DashRange({ genesis = g, partial = false, completeAt = done }, 0)), done)
  local from, to = TM().DashRange({ genesis = g, partial = true }, noon(2026, 10, 5))
  assertEqual(from, g); assertEqual(to, noon(2026, 10, 5))
  assertEqual(TM().DashRange({ genesis = g, partial = false }, 0), nil, "complete at genesis: solid")
end)

test("Timeline model: Flows sum the shown holders' gains and losses per day", function()
  local daily = {
    ["2026-10-02"] = { ["A-R"] = { g = { c = 1, i = 10, o = 3 } }, ["B-R"] = { g = { i = 5 } },
                       ["C-R"] = { g = { i = 999 } } },
  }
  local f = TM().Flows(daily, TM().SortedDays(daily), { "A-R", "B-R" }, "g", "2026-10-01", "2026-10-05")
  assertEqual(#f, 1); assertEqual(f[1].i, 15); assertEqual(f[1].o, 3)
end)

test("Timeline model: gold reaches the chart in gold units and stays copper in the model", function()
  seedMoney({ ["A-R"] = 25000 }, noon(2026, 10, 1))
  local m = TM().Build(params())
  local data = TM().ChartData(m)
  assertEqual(m.series[1].points[1].y, 25000)
  assertEqual(data.series[1].points[1].y, 2.5)
  assertFalse(data.integer, "gold is fractional on the chart")
end)

-- ── intraday (Today / 7 d) ──

test("Timeline model: IntradaySeries rebuilds steps from rows, newest backwards from now", function()
  local from = TM().DayStart("2026-10-05")
  local now = from + 18 * 3600
  local rows = {
    { ts = from + 3600, dir = "IN", kind = "GOLD", holder = "A-R", quantity = 100 },
    { ts = from + 7200, dir = "OUT", kind = "GOLD", holder = "A-R", quantity = 30 },
    { ts = from + 7300, dir = "IN", kind = "GOLD", holder = "B-R", quantity = 999 },
  }
  local pts = TM().IntradaySeries(rows, "A-R", "g", from, now, 570, 500)
  assertEqual(#pts, 6)
  assertEqual(pts[1].x, from); assertEqual(pts[1].y, 500)
  assertEqual(pts[3].y, 600); assertEqual(pts[5].y, 570)
  assertEqual(pts[6].x, now); assertEqual(pts[6].y, 570)
end)

test("Timeline model: IntradaySeries gives up when the rows disagree with the rollup", function()
  local from = TM().DayStart("2026-10-05")
  local rows = { { ts = from + 60, dir = "IN", kind = "GOLD", holder = "A-R", quantity = 100 } }
  assertEqual(TM().IntradaySeries(rows, "A-R", "g", from, from + 3600, 570, 400), nil)
  assertEqual(TM().IntradaySeries(rows, "A-R", "g", from, from + 3600, 50, nil), nil, "negative start")
end)

test("Timeline model: a MOVE row moves the holder's own balance by its side", function()
  local out = { dir = "MOVE", kind = "GOLD", holder = "A-R", quantity = 40, from = "A-R/money", to = "§warband/money" }
  local inn = { dir = "MOVE", kind = "GOLD", holder = "§warband", quantity = 40, from = "A-R/money", to = "§warband/money" }
  local intra = { dir = "MOVE", kind = "ITEM", itemID = 7, holder = "A-R", quantity = 5, from = "A-R/bags", to = "A-R/bank" }
  assertEqual(TM().RowDelta(out, "A-R"), -40)
  assertEqual(TM().RowDelta(inn, "§warband"), 40)
  assertEqual(TM().RowDelta(intra, "A-R"), 0)
  assertEqual(TM().RowDelta(out, "§warband"), 0, "another holder's row never moves this one")
end)

test("Timeline model: intraday only for Today / 7d, inside retention, after the ledger began", function()
  local now = noon(2026, 10, 5)
  assertTrue(TM().IntradayOK("today", now - 3600, now, 0, now - 99 * DAY))
  assertTrue(TM().IntradayOK("7d", now - 7 * DAY, now, 30, now - 99 * DAY))
  assertFalse(TM().IntradayOK("30d", now - 30 * DAY, now, 0, now - 99 * DAY))
  assertFalse(TM().IntradayOK("7d", now - 7 * DAY, now, 3, now - 99 * DAY), "rows pruned at 3 days")
  assertFalse(TM().IntradayOK("7d", now - 7 * DAY, now, 0, now - DAY), "rows before ledgerSince are gains-only")
end)

-- ── hover and picker ──

test("Timeline model: HoverLines reads each line's value and that day's flows", function()
  seedMoney({ ["A-R"] = 500 }, noon(2026, 10, 1))
  NS.Rollup:NoteFlow("A-R", "g", noon(2026, 10, 1), "IN", 500)
  local m = TM().Build(params())
  local i
  for k, x in ipairs(m.hoverXs) do if NS.Ledger.DayKey(x) == "2026-10-01" then i = k end end
  local h = TM().HoverLines(m, i)
  assertEqual(h.rows[1].text, TM().FormatValue("GOLD", 500))
  assertEqual(h.gain, TM().FormatValue("GOLD", 500))
  assertEqual(h.loss, TM().FormatValue("GOLD", 0))
end)

test("Timeline model: Suggest puts Gold first, then the biggest totals, capped", function()
  local things = {
    { key = "i:1", name = "Gloom Potion", total = 3 },
    { key = "g", name = "Gold", total = 10 },
    { key = "i:2", name = "Golden Potion", total = 50 },
  }
  local s = TM().Suggest("o", things, 2)
  assertEqual(#s, 2); assertEqual(s[1].key, "g"); assertEqual(s[2].key, "i:2")
  assertEqual(#TM().Suggest("zzz", things, 8), 0)
end)
```

Add `"test_timeline"` after `"test_holdingstab"` in `tests/run.lua`.

- [ ] **Step 2: Run to verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -E "Timeline model|FAIL" | head`
Expected: FAIL — `NS.TimelineModel` is nil.

- [ ] **Step 3: Implement**

`core/Constants.lua` — append:

```lua
-- The Timeline's look (timeline-ledger spec §8.1). Total is the gold accent; the warband has its own
-- hue so it never reads as a class; gains/losses ARE the History Direction column's (C.DirRGB,
-- spec §7), so this block must stay below C.DirRGB in this file.
C.TIMELINE = {
  TOTAL   = { 1, 0.82, 0, 1 },
  WARBAND = { 0.25, 0.75, 0.95, 1 },
  OTHER   = { 0.7, 0.7, 0.72, 1 },
  MARKER  = { 0.8, 0.8, 0.8, 0.6 },
  GAIN    = C.DirRGB.IN,     -- Phase 2's direction colors: one definition
  LOSS    = C.DirRGB.OUT,
  TOTAL_W = 2.5,
  LINE_W  = 1.5,
}
```

`modules/TimelineModel.lua`:

```lua
local _, NS = ...
NS.TimelineModel = NS.TimelineModel or {}
local TM = NS.TimelineModel

-- The Timeline's model (timeline-ledger spec §8.1): everything the tab draws, computed without a
-- frame. The view (modules/Timeline.lua) only paints what Build returns, so every rule the spec states
-- -- carry-forward, genesis start, the line cap, the Character filter, dashed partial stretches, the
-- ledgerSince marker, intraday points for Today / 7 d -- is pinned headless in tests/test_timeline.lua.
--
-- Daily points sit at each day's local midnight and carry that day's CLOSE (the balance at the end of
-- the day as far as the addon saw). A day with no cell carries the previous close forward.

local DAY = 86400
local MAX_DAYS = 4000         -- an 11-year "All" is the ceiling of one day walk
TM.TOTAL = "__total"

local function C() return NS.Constants.TIMELINE end

-- ── days ──

function TM.DayStart(day)
  local y, m, d = day:match("^(%d+)-(%d+)-(%d+)$")
  return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0, min = 0, sec = 0 })
end

-- +26 h rides over a 25-hour daylight-saving day without skipping or repeating a date.
function TM.NextDay(day) return NS.Ledger.DayKey(TM.DayStart(day) + DAY + 7200) end

function TM.SortedDays(daily)
  local out = {}
  for k in pairs(daily or {}) do out[#out + 1] = k end
  table.sort(out)
  return out
end

local function closeOn(daily, day, holder, key)
  local d = daily[day]
  local cell = d and d[holder] and d[holder][key]
  return cell and cell.c
end

function TM.CloseBefore(daily, days, holder, key, day)
  for i = #days, 1, -1 do
    if days[i] < day then
      local c = closeOn(daily, days[i], holder, key)
      if c ~= nil then return c end
    end
  end
  return nil
end

function TM.DailySeries(daily, days, holder, key, fromDay, toDay, genesisDay)
  local day = (genesisDay and genesisDay > fromDay) and genesisDay or fromDay
  local carry = TM.CloseBefore(daily, days, holder, key, day)
  local pts, n = {}, 0
  while day <= toDay and n < MAX_DAYS do
    local c = closeOn(daily, day, holder, key)
    if c ~= nil then carry = c end
    if carry ~= nil then pts[#pts + 1] = { x = TM.DayStart(day), y = carry } end
    day, n = TM.NextDay(day), n + 1
  end
  return pts
end

-- ── series arithmetic ──

function TM.ValueAt(points, x)
  local lo, hi, ans = 1, #points, nil
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    if points[mid].x <= x then ans, lo = points[mid].y, mid + 1 else hi = mid - 1 end
  end
  return ans
end

function TM.TotalSeries(list)
  local xs, seen = {}, {}
  for _, pts in ipairs(list) do
    for _, pt in ipairs(pts) do
      if not seen[pt.x] then seen[pt.x] = true; xs[#xs + 1] = pt.x end
    end
  end
  table.sort(xs)
  local out = {}
  for _, x in ipairs(xs) do
    local sum = 0
    for _, pts in ipairs(list) do sum = sum + (TM.ValueAt(pts, x) or 0) end
    out[#out + 1] = { x = x, y = sum }
  end
  return out
end

-- ── who gets a line ──

function TM.RankHolders(latest, candidates, allowed, cap)
  if allowed and next(allowed) == nil then allowed = nil end
  local list = {}
  for _, h in ipairs(candidates) do
    if not allowed or allowed[h] then list[#list + 1] = h end
  end
  table.sort(list, function(a, b)
    local va, vb = latest[a] or 0, latest[b] or 0
    if va ~= vb then return va > vb end
    return a < b
  end)
  for i = #list, (cap or #list) + 1, -1 do list[i] = nil end
  return list
end

function TM.Latest(key)
  local _, rows = NS.Holdings:Total(key)
  local m = {}
  for _, r in ipairs(rows) do m[r.holder] = r.count end
  return m
end

function TM.Meta(holder)
  local e = NS.Holdings:Get(holder)
  return (e and e.meta) or {}
end

local function candidates(daily, days, key, fromDay, toDay, latest)
  local set, out = {}, {}
  for h in pairs(latest) do set[h] = true end
  for _, d in ipairs(days) do
    if d >= fromDay and d <= toDay then
      for h, things in pairs(daily[d]) do if things[key] then set[h] = true end end
    end
  end
  for h in pairs(set) do out[#out + 1] = h end
  table.sort(out)
  return out
end

-- ── intraday (Today / 7 d) ──

local function sideOf(path) return path and path:match("^(.-)/") end

function TM.RowDelta(r, holder)
  if NS.Util.RowHolder(r) ~= holder then return 0 end
  local dir, q = NS.Util.RowDir(r), r.quantity or 0
  if dir == "IN" then return q end
  if dir == "OUT" then return -q end
  local fromH, toH = sideOf(r.from), sideOf(r.to)
  if fromH == toH then return 0 end
  if toH == holder then return q end
  if fromH == holder then return -q end
  return 0
end

-- Rebuilt backwards from the balance the holder has NOW, undoing each row of this thing newest first,
-- so it needs no stored snapshot. Two checks keep it honest: the balance it arrives at for `from` must
-- not be negative, and must equal the rollup's close before that day when there is one. Either failing
-- answers nil and the caller draws daily points instead (plan "Phase 2 contract", item 4).
function TM.IntradaySeries(history, holder, key, from, now, current, anchor)
  local bal, pts = current, { { x = now, y = current } }
  for i = #history, 1, -1 do
    local r = history[i]
    if (r.ts or 0) < from then break end
    if NS.Ledger.RowThingKey(r) == key then
      local d = TM.RowDelta(r, holder)
      if d ~= 0 then
        pts[#pts + 1] = { x = r.ts, y = bal }
        bal = bal - d
        pts[#pts + 1] = { x = r.ts, y = bal }
      end
    end
  end
  if bal < 0 or (anchor ~= nil and anchor ~= bal) then return nil end
  pts[#pts + 1] = { x = from, y = bal }
  local out = {}
  for i = #pts, 1, -1 do out[#out + 1] = pts[i] end
  return out
end

function TM.IntradayOK(range, from, now, retentionDays, ledgerSince)
  if range ~= "today" and range ~= "7d" then return false end
  if retentionDays and retentionDays > 0 and from < now - retentionDays * DAY then return false end
  return ledgerSince ~= nil and from >= ledgerSince
end

-- ── decorations ──

function TM.Flows(daily, days, holders, key, fromDay, toDay)
  local set, out = {}, {}
  for _, h in ipairs(holders) do set[h] = true end
  for _, d in ipairs(days) do
    if d >= fromDay and d <= toDay then
      local i, o = 0, 0
      for h, things in pairs(daily[d]) do
        local cell = set[h] and things[key]
        if cell then i, o = i + (cell.i or 0), o + (cell.o or 0) end
      end
      if i > 0 or o > 0 then out[#out + 1] = { x = TM.DayStart(d), day = d, i = i, o = o } end
    end
  end
  return out
end

function TM.DashRange(meta, now)
  if not meta.genesis then return nil, nil end
  if meta.completeAt then return meta.genesis, meta.completeAt end
  if meta.partial then return meta.genesis, now end
  return nil, nil
end

function TM.Label(holder)
  if holder == TM.TOTAL then return "Total" end
  return NS.LedgerFormat.HolderLabel(holder)   -- "Warband" for the warband (Phase 2)
end

function TM.Color(holder, meta)
  if holder == NS.Constants.WARBAND_HOLDER then return C().WARBAND end
  local cc = meta and meta.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[meta.classFile]
  if cc then return { cc.r, cc.g, cc.b, 1 } end
  return C().OTHER
end

function TM.FormatValue(kind, v)
  v = v or 0
  if kind == "GOLD" then
    if v == 0 then return "0" end
    return NS.Util.FormatMoney(v)
  end
  return tostring(math.floor(v + 0.5))
end

function TM.Suggest(text, things, limit)
  local t, out = (text or ""):lower(), {}
  for _, th in ipairs(things) do
    if t == "" or th.name:lower():find(t, 1, true) then out[#out + 1] = th end
  end
  table.sort(out, function(a, b)
    if (a.key == "g") ~= (b.key == "g") then return a.key == "g" end
    if (a.total or 0) ~= (b.total or 0) then return (a.total or 0) > (b.total or 0) end
    return a.name < b.name
  end)
  for i = #out, (limit or 8) + 1, -1 do out[i] = nil end
  return out
end

-- ── Build ──

local function window(p)
  local days = TM.SortedDays(p.daily)
  local from = p.from
  if not from then
    from = p.ledgerSince or p.now
    if days[1] then from = math.min(from, TM.DayStart(days[1])) end
  end
  local fromDay = NS.Ledger.DayKey(from)
  return { days = days, from = TM.DayStart(fromDay), fromDay = fromDay, toDay = NS.Ledger.DayKey(p.now) }
end

local function holderSeries(p, w, h, key, pts)
  local meta = TM.Meta(h)
  local dashFrom, dashTo = TM.DashRange(meta, p.now)
  if not pts then
    local gDay = meta.genesis and NS.Ledger.DayKey(meta.genesis) or nil
    pts = TM.DailySeries(p.daily, w.days, h, key, w.fromDay, w.toDay, gDay)
  end
  return { holder = h, label = TM.Label(h), color = TM.Color(h, meta), thickness = C().LINE_W,
    points = pts, dashFrom = dashFrom, dashTo = dashTo }
end

-- All shown holders intraday, or none: mixing event-time points with midnight points would make the
-- Total sum two different clocks.
local function tryIntraday(p, w, shown, key)
  if not TM.IntradayOK(p.range, w.from, p.now, p.retentionDays, p.ledgerSince) then return nil end
  local out = {}
  for _, h in ipairs(shown) do
    local meta = TM.Meta(h)
    local start = math.max(w.from, meta.genesis or w.from)
    local anchor = TM.CloseBefore(p.daily, w.days, h, key, w.fromDay)
    local pts = TM.IntradaySeries(p.history or {}, h, key, start, p.now, w.latest[h] or 0, anchor)
    if not pts then return nil end
    out[h] = pts
  end
  return out
end

local function hoverDays(w)
  local xs, day, n = {}, w.fromDay, 0
  while day <= w.toDay and n < MAX_DAYS do
    xs[#xs + 1] = TM.DayStart(day)
    day, n = TM.NextDay(day), n + 1
  end
  return xs
end

local function markers(p, xMin, xMax)
  local out = {}
  local s = p.ledgerSince
  if s and s >= xMin and s <= xMax then out[1] = { x = s, dashed = true, color = C().MARKER } end
  return out
end

function TM.Build(p)
  local key = p.thing or "g"
  local kind = NS.Ledger.ParseThingKey(key) or "GOLD"
  local w = window(p)
  w.latest = TM.Latest(key)
  local shown = TM.RankHolders(w.latest, candidates(p.daily, w.days, key, w.fromDay, w.toDay, w.latest),
    p.allowed, p.maxLines or 8)
  local intra = tryIntraday(p, w, shown, key)
  local series, lists = {}, {}
  for _, h in ipairs(shown) do
    local s = holderSeries(p, w, h, key, intra and intra[h])
    series[#series + 1] = s
    lists[#lists + 1] = s.points
  end
  series[#series + 1] = { holder = TM.TOTAL, label = "Total", color = C().TOTAL, thickness = C().TOTAL_W,
    points = TM.TotalSeries(lists) }
  local xMin = w.from
  local xMax = intra and p.now or math.max(TM.DayStart(w.toDay), xMin + DAY)
  local flows = TM.Flows(p.daily, w.days, shown, key, w.fromDay, w.toDay)
  local flowByX = {}
  for _, f in ipairs(flows) do flowByX[f.x] = f end
  return { key = key, kind = kind, title = NS.Holdings:Describe(key).name, mode = intra and "intraday" or "daily",
    now = p.now, xMin = xMin, xMax = xMax, series = series, flows = flows, flowByX = flowByX,
    hoverXs = hoverDays(w), markers = markers(p, xMin, xMax) }
end

function TM.HoverLines(m, i)
  local x = m and m.hoverXs[i]
  if not x then return nil end
  local xEnd = math.min(x + DAY - 1, m.now)
  local out = { title = date("%d %b %Y", x), rows = {} }
  for _, s in ipairs(m.series) do
    local v = TM.ValueAt(s.points, xEnd)
    if v ~= nil then out.rows[#out.rows + 1] = { label = s.label, text = TM.FormatValue(m.kind, v), color = s.color } end
  end
  local f = m.flowByX[x]
  out.gain = TM.FormatValue(m.kind, f and f.i or 0)
  out.loss = TM.FormatValue(m.kind, f and f.o or 0)
  return out
end

function TM.ChartData(m)
  local scale = (m.kind == "GOLD") and (1 / 10000) or 1
  local series = {}
  for i, s in ipairs(m.series) do
    local pts = {}
    for j, pt in ipairs(s.points) do pts[j] = { x = pt.x, y = pt.y * scale } end
    series[i] = { points = pts, color = s.color, thickness = s.thickness, dashFrom = s.dashFrom, dashTo = s.dashTo }
  end
  return { xMin = m.xMin, xMax = m.xMax, integer = m.kind ~= "GOLD", series = series,
    markers = m.markers, hoverXs = m.hoverXs }
end
```

`LootHistory.toc`: `modules\TimelineModel.lua` after `modules\HoldingsTab.lua`.

> Daily-mode check of the Review-Focus-4 case: twelve holders each get a genesis-day close on 2026-10-01 from `ApplyMoney`; the 30-day window starts 2026-09-05, so each series has five points (10-01 … 10-05) and the Total's last point sums the eight richest (H05..H12 = 6800 copper).

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS (seventeen `Timeline model:` cases); 0/0. If lizard (`test_lizard_sighted`) flags `TM.Build` above CCN 15, move the series loop into a `buildSeries(p, w, shown, key, intra)` helper.

- [ ] **Step 5: Regenerate inventory and commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add modules/TimelineModel.lua core/Constants.lua LootHistory.toc tests/test_timeline.lua tests/run.lua docs/test-cases.md
git commit -m "$(cat <<'EOF'
feat(timeline): pure Timeline model - carry-forward, ranking, cap, intraday, flows, hover

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt
EOF
)"
```

---

### Task B7: Browser — 90 d / 1 y, per-tab filter graying, holders Character list, the view field

**Files:**
- Modify: `core/Util.lua:47-59` (`RangeFrom`)
- Modify: `modules/Browser.lua` — `DATE_OPTIONS` (~:231), the `-- ── Tabs ──` block (Phase 1's registry: add `B._filterHonored`, `B:ApplyTabFilters`, call it from `B:SelectTab`), `charOptions` (~:338, split), `B:RefreshFilterOptions` (~:519), `B:CaptureView` (~:600), `BuildFilterBar` (keep `self._exportBtn`), new `B:DateRange`, `B:SetViewField`, `B:ViewField`, `B:ShowTimeline`; publish `B._dateOptions`; `B._options.char` takes `holdersMode`
- Modify: `modules/HoldingsTab.lua` (its `RegisterTab` call gains `filters` and `charSource`)
- Modify: `tests/test_util.lua`, `tests/test_browser.lua` (append)

**Interfaces:**
- Consumes: Phase 1's `tabSpecs`, `lastTab`, `B:RegisterTab`, `B:_UnregisterTabForTest`, `B:SelectTab`, `NS.Holdings:Holders/Get`, `NS.BrowserTable:ClassIconMarkup`.
- Produces:
  - `NS.Util.RangeFrom("90d") -> now - 90 d`, `("1y") -> now - 365 d`
  - Date options `all, today, 7d, 30d, 90d, 1y` (`B._dateOptions`)
  - Tab spec fields read: `filters = { [control]=true }|nil` (nil = every control honored; control keys are `B._dd`'s keys — `group, dir, date, bound, quality, type, subtype, source, zone, char` (`dir` is Phase 2's Direction) — plus `"search"` and `"export"`), `charSource = "holders"|nil`
  - `B._filterHonored(spec, key) -> boolean`; `B:ApplyTabFilters(name)` (gray = `SetEnabled(false)` + alpha 0.4; never hidden)
  - `B._options.char(holdersMode) -> options` (holders mode: `NS.Holdings:Holders()`, `§warband` labelled "Warband")
  - `B:DateRange() -> "all"|"today"|"7d"|"30d"|"90d"|"1y"`
  - `B:SetViewField(k, v)` (materializes `profile.savedView` from the stock view when absent), `B:ViewField(k) -> v`; `CaptureView` carries `timelineThing`
  - `B:ShowTimeline(key)` (sets the Timeline's thing without a refresh, shows the window, selects "Timeline")
  - Holdings tab spec: `filters = { search, quality, type, subtype, char }`, `charSource = "holders"`

- [ ] **Step 1: Write the failing tests**

`tests/test_util.lua` — append:

```lua
test("Util.RangeFrom: 90d and 1y are rolling windows", function()
  local now = time()
  assertTrue(math.abs(NS.Util.RangeFrom("90d") - (now - 90 * 86400)) <= 1)
  assertTrue(math.abs(NS.Util.RangeFrom("1y") - (now - 365 * 86400)) <= 1)
end)
```

`tests/test_browser.lua` — append:

```lua
-- ── timeline ledger P3: date options, per-tab filters, holders, the remembered pick ────────────

test("Browser: date options offer 90 days and 1 year after 30 days", function()
  local vals = {}
  for _, o in ipairs(NS.Browser._dateOptions) do vals[#vals + 1] = o.value end
  assertEqual(table.concat(vals, ","), "all,today,7d,30d,90d,1y")
end)

test("Browser: _filterHonored - no set honors everything, a set honors only its keys", function()
  local f = NS.Browser._filterHonored
  assertTrue(f(nil, "bound")); assertTrue(f({}, "bound"))
  assertTrue(f({ filters = { date = true } }, "date"))
  assertFalse(f({ filters = { date = true } }, "bound"))
  assertFalse(f({ filters = { date = true } }, "search"))
end)

test("Browser: a tab grays the controls it does not honor, and History restores them", function()
  NS.Browser:Show()
  NS.Browser:RegisterTab{ name = "ZGray", order = 98, filters = { date = true }, build = function() end }
  NS.Browser:SelectTab("ZGray")
  local dd = NS.Browser._dd
  assertTrue(dd.date:IsEnabled())
  assertFalse(dd.bound:IsEnabled()); assertFalse(dd.char:IsEnabled()); assertFalse(dd.group:IsEnabled())
  assertFalse(NS.Browser._search:IsEnabled()); assertFalse(NS.Browser._exportBtn:IsEnabled())
  assertTrue(dd.bound:IsShown(), "grayed, never hidden: the bar does not reflow between tabs")
  NS.Browser:SelectTab("History")
  assertTrue(dd.bound:IsEnabled()); assertTrue(NS.Browser._search:IsEnabled())
  assertTrue(NS.Browser._exportBtn:IsEnabled())
  NS.Browser:_UnregisterTabForTest("ZGray")
end)

test("Browser: the Holdings tab grays Date, Source, Bound, Zone and Group", function()
  NS.Browser:Show(); NS.Browser:SelectTab("Holdings")
  local dd = NS.Browser._dd
  for _, k in ipairs({ "date", "source", "bound", "zone", "group", "dir" }) do
    assertFalse(dd[k]:IsEnabled(), k .. " is not a Holdings filter")
  end
  for _, k in ipairs({ "quality", "type", "subtype", "char" }) do
    assertTrue(dd[k]:IsEnabled(), k .. " is a Holdings filter")
  end
  NS.Browser:SelectTab("History")
end)

test("Browser: a holders tab lists holders, with the warband as Warband", function()
  NS.db.global.holdings = {}
  NS.Holdings:ApplyMoney("§warband", 5, 1)
  NS.Holdings:ApplyMoney("Alt-Realm", 5, 1)
  local labels = {}
  for _, o in ipairs(NS.Browser._options.char(true)) do labels[o.value] = o.label end
  assertTrue(labels["§warband"] ~= nil and labels["§warband"]:find("Warband", 1, true) ~= nil)
  assertTrue(labels["Alt-Realm"] ~= nil)
  assertTrue(labels["current"] ~= nil, "the Current preset stays")
end)

test("Browser: SetViewField remembers a field with no Save, from a copy of the stock view", function()
  local p = NS.db.profile
  local saved = p.savedView
  p.savedView = nil
  NS.Browser:SetViewField("timelineThing", "c:3008")
  assertEqual(NS.Browser:ViewField("timelineThing"), "c:3008")
  assertEqual(p.savedView.groupBy, NS.Browser._stockView.groupBy, "everything else is stock")
  assertTrue(p.savedView ~= NS.Browser._stockView, "a copy, never the stock table itself")
  assertEqual(NS.Browser._stockView.timelineThing, nil)
  p.savedView = saved
end)

test("Browser: CaptureView keeps the remembered Timeline pick", function()
  local p = NS.db.profile
  local saved = p.savedView
  p.savedView = nil
  NS.Browser:SetViewField("timelineThing", "i:7")
  assertEqual(NS.Browser:CaptureView().timelineThing, "i:7")
  p.savedView = saved
end)

test("Browser: DateRange reads the Date dropdown, all when there is none", function()
  NS.Browser:Show()
  NS.Browser._dd.date:SelectValue("90d")
  assertEqual(NS.Browser:DateRange(), "90d")
  NS.Browser._dd.date:SelectValue("all")
  assertEqual(NS.Browser:DateRange(), "all")
end)
```

- [ ] **Step 2: Run to verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -E "Browser: (date options|_filterHonored|a tab grays|the Holdings tab grays|a holders tab|SetViewField|CaptureView keeps|DateRange)|RangeFrom: 90d" | head -20`
Expected: FAIL — `_dateOptions`, `_filterHonored`, `ApplyTabFilters`, `SetViewField`, `DateRange` are nil; `RangeFrom("90d")` is nil.

- [ ] **Step 3: Implement**

`core/Util.lua` — in `RangeFrom`, before the final `return nil`:

```lua
  elseif range == "90d" then
    return now - 90 * 86400
  elseif range == "1y" then
    return now - 365 * 86400
```

(and extend its comment: "90d/1y were added for the Timeline (spec §8.1); History and Insights offer them too, since the filter is one singleton".)

`modules/Browser.lua` — `DATE_OPTIONS` gains:

```lua
  { value = "90d", label = "Last 90 days" },
  { value = "1y", label = "Last year" },
```

In the Tabs block (Phase 1's registry), add:

```lua
-- Per-tab filters (spec §8.0). The bar is one window-wide singleton; a tab that does not honor a
-- control GRAYS it rather than hiding it, so the bar never reflows when the player switches tabs and
-- the filter it still holds is visible. A spec with no `filters` set honors every control (History,
-- Insights). Keys are B._dd's keys plus "search" and "export".
local GRAY_ALPHA = 0.4

function B._filterHonored(spec, key)
  if not (spec and spec.filters) then return true end
  return spec.filters[key] == true
end

local function setHonored(ctl, on)
  if not ctl then return end
  if ctl.SetEnabled then ctl:SetEnabled(on) end
  if ctl.SetAlpha then ctl:SetAlpha(on and 1 or GRAY_ALPHA) end
end

function B:ApplyTabFilters(name)
  local spec = tabSpecs[name]
  for key, ctl in pairs(self._dd or {}) do setHonored(ctl, B._filterHonored(spec, key)) end
  setHonored(self._search, B._filterHonored(spec, "search"))
  setHonored(self._exportBtn, B._filterHonored(spec, "export"))
  self:RefreshFilterOptions()
end
```

In `B:SelectTab`, right after `lastTab = name`, add `B:ApplyTabFilters(name)`.

Split `charOptions` so the History list and the holders list share the tail:

```lua
local function historyCharItems()
  local seen, items = {}, {}
  for _, r in ipairs(dataset()) do
    local c = r.char
    if c and not seen[c] then
      seen[c] = true
      -- (the existing class-icon comment block stays here, unchanged)
      local icon = (NS.BrowserTable and NS.BrowserTable.ClassIconMarkup
        and NS.BrowserTable:ClassIconMarkup(r.classFile)) or ""
      local cc = r.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[r.classFile]
      items[#items + 1] = {
        value = c, label = (icon ~= "" and (icon .. " " .. c) or c),
        color = cc and { cc.r, cc.g, cc.b } or nil,
      }
    end
  end
  return items
end

-- The Character list for a tab whose rows are HOLDERS rather than history rows (Timeline, Holdings):
-- every holder the ledger knows, and the warband under the name a player reads, "Warband".
local function holderCharItems()
  local items = {}
  for _, h in ipairs(NS.Holdings and NS.Holdings:Holders() or {}) do
    local e = NS.Holdings:Get(h)
    local cf = e and e.meta and e.meta.classFile
    local icon = (cf and NS.BrowserTable and NS.BrowserTable.ClassIconMarkup
      and NS.BrowserTable:ClassIconMarkup(cf)) or ""
    local cc = cf and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
    local name = NS.LedgerFormat.HolderLabel(h)
    items[#items + 1] = { value = h, label = (icon ~= "" and (icon .. " " .. name) or name),
      color = cc and { cc.r, cc.g, cc.b } or nil }
  end
  return items
end

local function charOptions(holdersMode)
  local items = holdersMode and holderCharItems() or historyCharItems()
  -- (the existing withAll + "Character: Current" preset tail, unchanged, operating on `items`)
end
```

`B._options.char = charOptions` already publishes it; it now takes `holdersMode`. In `B:RefreshFilterOptions`:

```lua
  local spec = tabSpecs[lastTab]
  dd.char:SetOptions(charOptions(spec ~= nil and spec.charSource == "holders"))
```

(replacing the bare `dd.char:SetOptions(charOptions())`; `tabSpecs`/`lastTab` are file locals defined above in the Tabs block).

In `BuildFilterBar`, after `local exportBtn = makeBarButton(...)`: `self._exportBtn = exportBtn`.

Below `B:CurrentFilter`:

```lua
-- The Date dropdown's range KEY ("today", "7d", ...), not its resolved `from`: the Timeline draws
-- intraday points for Today / 7d only, which a timestamp cannot tell it.
function B:DateRange()
  local dd = self._dd
  return (dd and dd.date and dd.date._value) or "all"
end

-- One field of the saved view, written without a Save (the Timeline's last pick, spec §8.1). With no
-- saved view yet, the view is materialized as a COPY of the stock one, which applies exactly as stock
-- does, so remembering a pick never changes anything else a later Reset or Save would see.
function B:SetViewField(k, v)
  local p = NS.db and NS.db.profile
  if not p then return end
  if type(p.savedView) ~= "table" then
    local copy = {}
    for kk, vv in pairs(STOCK_VIEW) do copy[kk] = vv end
    p.savedView = copy
  end
  p.savedView[k] = v
end

function B:ViewField(k) return savedViewOrStock()[k] end

-- "Show in Timeline" from a History or Holdings row (spec §8.2).
function B:ShowTimeline(key)
  if NS.Timeline and NS.Timeline.SetThing then NS.Timeline:SetThing(key, true) end
  self:Show()
  self:SelectTab("Timeline")
end
```

In `B:CaptureView`, before `return v`: `v.timelineThing = savedViewOrStock().timelineThing`. Publish `B._dateOptions = DATE_OPTIONS` beside `B._stockView`.

`modules/HoldingsTab.lua` — its registration becomes:

```lua
NS.Browser:RegisterTab{ name = "Holdings", order = 40,
  -- Holdings are current state: no Date, Source, Bound, Zone or grouping applies (spec §8.2).
  filters = { search = true, quality = true, type = true, subtype = true, char = true },
  charSource = "holders",
  build = function(pane) HT:Attach(pane) end,
  refresh = function() HT:Refresh() end }
```

> `wc -l modules/Browser.lua` must stay under 1500. If Phase 2 left it above ~1420, peel `historyCharItems`/`holderCharItems`/`charOptions` and the other option builders into `modules/BrowserOptions.lua` (publishing `NS.BrowserOptions`) in this task, before adding anything, and say so in the commit.

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS — the new Browser and Util cases, and every existing `test_browser.lua` / `test_panel_filters.lua` case (History and Insights register no `filters`, so nothing grays there). 0/0. `wc -l modules/Browser.lua` < 1500.

- [ ] **Step 5: Regenerate inventory and commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add core/Util.lua modules/Browser.lua modules/HoldingsTab.lua tests/test_util.lua tests/test_browser.lua docs/test-cases.md
git commit -m "$(cat <<'EOF'
feat(browser): per-tab filter graying, 90d/1y ranges, holders Character list, remembered view field

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt
EOF
)"
```

---

### Task B8: The Timeline tab — `modules/Timeline.lua` and `settings.timelineMaxLines`

**Files:**
- Create: `modules/Timeline.lua`
- Modify: `LootHistory.toc` (`modules\Timeline.lua` after `modules\TimelineModel.lua`)
- Modify: `defaults/Profile.lua` (`settings.timelineMaxLines = 8`)
- Modify: `settings/Schema.lua` (row after `settings.rowHeight`, General ▸ Interface)
- Modify: `core/LifecycleSetup.lua` (enable/disable `NS.Timeline`)
- Modify: `tests/test_disabled.lua` (`featureTargets()` gains `NS.Timeline.__ev`), `tests/test_schema.lua` (`PARTITION` Interface +1 from whatever Phase 2 left it at)
- Create: `tests/test_timelinetab.lua`; Modify: `tests/run.lua` (`"test_timelinetab"` after `"test_timeline"`)

**Interfaces:**
- Consumes: `NS.MakeLineChart`, `NS.TimelineModel.*`, `NS.Browser:RegisterTab/CurrentFilter/DateRange/ViewField/SetViewField/_search`, `NS.Holdings:Search/Describe`, `NS.Rollup:Keys`, `NS.Database:History`, `NS.Pool`, `NS.MSG.HOLDINGS_CHANGED`, `NS.MSG.RECORD_ADDED`, `NS.Coalesce`, `NS.Constants.RECORD_ADDED_COALESCE`, `NS.LIBKA0S_MISSING`.
- Produces (on `NS.Timeline`):
  - `:Thing() -> key` (session pick, else the saved view's `timelineThing`, else `"g"`); `:SetThing(key, quiet)`
  - `:Attach(pane)`, `:Refresh()`, `:RefreshIfShown()`, `:Layout(w?, h?)`, `:OnHover(index|nil)`
  - `:Enable()` / `:Disable()` (private `self.__ev`: `HOLDINGS_CHANGED` and coalesced `RECORD_ADDED` → `RefreshIfShown`)
  - Test seams: `:VisibleSeriesCount()`, `:SuggestionKeys()`; fields `chart`, `model`, `legendPool`, `stripPool`, `suggestPool`
  - Tab spec `{ name = "Timeline", order = 30, filters = { search, date, char }, charSource = "holders" }`
  - Setting `settings.timelineMaxLines` (profile, default 8, 2–16, Slider)

- [ ] **Step 1: Write the failing test** — `tests/test_timelinetab.lua`

```lua
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local function seed()
  NS.db.global.holdings, NS.db.global.daily = {}, {}
  local t = time()
  NS.Holdings:ApplyMoney("Mock-Realm", 50000, t - 86400)
  NS.Holdings:ApplyMoney("Mock-Realm", 70000, t)
  NS.Holdings:ApplyMoney("Alt-Realm", 10000, t)
end

local function open()
  NS.Browser:Show()
  NS.Browser:SetCharSet(nil)
  NS.Browser:SelectTab("Timeline")
  NS.Timeline:SetThing("g")
  NS.Timeline:Layout(640, 320)
end

test("Timeline tab: registered between Insights and Holdings", function()
  local names = NS.Browser:Tabs()
  assertEqual(names[3], "Timeline"); assertEqual(names[4], "Holdings")
end)

test("Timeline tab: Total plus one line per holder; the Character filter narrows it", function()
  seed(); open()
  assertEqual(NS.Timeline:VisibleSeriesCount(), 3)
  NS.Browser:SetCharSet({ ["Alt-Realm"] = true })
  assertEqual(NS.Timeline:VisibleSeriesCount(), 2)
  NS.Browser:SetCharSet(nil); NS.Browser:SelectTab("History")
end)

test("Timeline tab: refresh twice recycles Lines and pooled rows", function()
  -- Review Focus 5 (the host half)
  seed(); open()
  local made = #NS.Timeline.chart.__madeLines
  local f1, a1 = NS.Pool.Counts(NS.Timeline.legendPool)
  local s1, b1 = NS.Pool.Counts(NS.Timeline.stripPool)
  NS.Timeline:Refresh(); NS.Timeline:Layout(640, 320)
  assertEqual(#NS.Timeline.chart.__madeLines, made, "no new Line objects")
  local f2, a2 = NS.Pool.Counts(NS.Timeline.legendPool)
  local s2, b2 = NS.Pool.Counts(NS.Timeline.stripPool)
  assertEqual(f1 + a1, f2 + a2); assertEqual(s1 + b1, s2 + b2)
  NS.Browser:SelectTab("History")
end)

test("Timeline tab: maxLines caps the holders drawn", function()
  NS.db.global.holdings, NS.db.global.daily = {}, {}
  for i = 1, 5 do NS.Holdings:ApplyMoney(("H%d-Realm"):format(i), i, time()) end
  local saved = NS.db.profile.settings.timelineMaxLines
  NS.Schema:Set("settings.timelineMaxLines", 2)
  open()
  assertEqual(NS.Timeline:VisibleSeriesCount(), 3, "two holders and the Total")
  NS.Schema:Set("settings.timelineMaxLines", saved or 8)
  NS.Browser:SelectTab("History")
end)

test("Timeline tab: typing in Search offers matching things, Gold first", function()
  seed(); open()
  NS.Browser._search:SetText("gol")
  NS.Browser._search:__fire("OnTextChanged")
  local keys = NS.Timeline:SuggestionKeys()
  assertEqual(keys[1], "g")
  NS.Browser._search:SetText(""); NS.Browser._search:__fire("OnTextChanged")
  assertEqual(#NS.Timeline:SuggestionKeys(), 0, "no text, no suggestion list")
  NS.Browser:SelectTab("History")
end)

test("Timeline tab: the pick is remembered in the saved view", function()
  seed(); open()
  NS.Timeline:SetThing("c:3008")
  assertEqual(NS.Browser:ViewField("timelineThing"), "c:3008")
  NS.Timeline.thing = nil
  assertEqual(NS.Timeline:Thing(), "c:3008")
  NS.Timeline:SetThing("g")
  NS.Browser:SelectTab("History")
end)

test("Timeline tab: grays every filter but Search, Date and Character", function()
  seed(); open()
  local dd = NS.Browser._dd
  assertTrue(dd.date:IsEnabled()); assertTrue(dd.char:IsEnabled()); assertTrue(NS.Browser._search:IsEnabled())
  for _, k in ipairs({ "group", "dir", "bound", "quality", "type", "subtype", "source", "zone" }) do
    assertFalse(dd[k]:IsEnabled(), k .. " is not a Timeline filter")
  end
  assertFalse(NS.Browser._exportBtn:IsEnabled())
  NS.Browser:SelectTab("History")
end)

test("Timeline tab: a hover with no model or index hides the tooltip and does not raise", function()
  seed(); open()
  NS.Timeline:OnHover(nil)
  NS.Timeline:OnHover(1)
  NS.Browser:SelectTab("History")
end)

test("Schema: timelineMaxLines is a 2-16 slider under Interface, default 8", function()
  local row = NS.Schema:FindRow("settings.timelineMaxLines")
  assertTrue(row ~= nil)
  assertEqual(row.default, 8); assertEqual(row.min, 2); assertEqual(row.max, 16)
  assertEqual(row.group, "Interface"); assertEqual(row.widget, "Slider")
end)
```

> If `tests/wow_mock.lua`'s EditBox does not record scripts for `__fire`, drive the search through `NS.Browser.activeFilter.text = "gol"; NS.Timeline:Refresh()` instead; the behavior pinned is the suggestion list, not the EditBox.

- [ ] **Step 2: Run to verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -E "Timeline tab|timelineMaxLines|FAIL" | head`
Expected: FAIL — no "Timeline" tab (`names[3]` is "Holdings"); `NS.Timeline` nil; no schema row.

- [ ] **Step 3: Implement**

`defaults/Profile.lua` — in `settings`: `timelineMaxLines = 8,   -- lines besides the Total on the Timeline (2-16)`.

`settings/Schema.lua` — after the `settings.rowHeight` row:

```lua
  -- How many holders the Timeline draws besides its Total (spec §11). The richest holders of the
  -- charted thing win the slots; the Character filter narrows the field first.
  { path = "settings.timelineMaxLines", default = PD.settings.timelineMaxLines, type = "number",
    min = 2, max = 16, step = 1, widget = "Slider", fmt = "%d",
    page = "General", group = "Interface", label = "Timeline lines",
    tooltip = "How many characters the Timeline draws as their own line, besides the Total. "
      .. "The ones holding the most of the charted item, currency or gold are shown first.",
    onChange = function()
      if NS.Timeline and NS.Timeline.RefreshIfShown then NS.Timeline:RefreshIfShown() end
    end },
```

`modules/Timeline.lua`:

```lua
local _, NS = ...
NS.Timeline = NS.Timeline or {}
local TL = NS.Timeline

-- The Timeline tab (timeline-ledger spec §8.1): one thing over time, a Total line and a line per
-- holder, an in/out bar strip under the plot, a legend and a hover tooltip. Every number comes from
-- NS.TimelineModel.Build; this file paints it. The chart itself is LibKa0s's (NS.MakeLineChart).
--
-- The THING is picked with the browser's shared Search box: typing offers matching things (what is
-- held now, plus anything the rollup has a day for), clicking one charts it, and the pick is
-- remembered in the saved view.

local TM = NS.TimelineModel
local DAY = 86400
local BAR_H, STRIP_H, LEGEND_H, ROW_H, SUGGEST_MAX, LEGEND_W, GAP = 22, 56, 16, 18, 8, 120, 6
local WHITE = "Interface\\Buttons\\WHITE8X8"

function TL:Thing()
  if self.thing then return self.thing end
  local v = NS.Browser and NS.Browser.ViewField and NS.Browser:ViewField("timelineThing")
  return v or "g"
end

function TL:SetThing(key, quiet)
  self.thing = key
  if NS.Browser and NS.Browser.SetViewField then NS.Browser:SetViewField("timelineThing", key) end
  if not quiet then self:RefreshIfShown() end
end

-- ── pooled pieces ──

local function makeSuggestRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(ROW_H)
  b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.fs:SetPoint("LEFT", 6, 0); b.fs:SetPoint("RIGHT", -6, 0); b.fs:SetJustifyH("LEFT")
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.15)
  b:SetScript("OnClick", function(self2)
    TL:SetThing(self2.key, true)
    -- The pick is made; clearing Search closes the list and re-runs the shared filter once.
    if NS.Browser._search then NS.Browser._search:SetText("") end
    TL:Refresh()
  end)
  return b
end

local function makeFlowBar(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.up = f:CreateTexture(nil, "ARTWORK")
  f.down = f:CreateTexture(nil, "ARTWORK")
  return f
end

local function makeLegendEntry(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(LEGEND_W, LEGEND_H)
  f.fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.fs:SetPoint("LEFT", 0, 0); f.fs:SetWidth(LEGEND_W - 4); f.fs:SetWordWrap(false); f.fs:SetJustifyH("LEFT")
  return f
end

-- ── build ──

local function buildHeader(self, pane)
  local bar = CreateFrame("Frame", nil, pane)
  bar:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0); bar:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, 0)
  bar:SetHeight(BAR_H)
  self.title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  self.title:SetPoint("LEFT", 4, 0)
  local hint = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("LEFT", self.title, "RIGHT", 10, 0)
  hint:SetText("Type in Search to chart an item or currency.")
  self.bar = bar
  local sug = CreateFrame("Frame", nil, pane, "BackdropTemplate")
  sug:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -2); sug:SetWidth(320)
  sug:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  sug:SetBackdropColor(0.06, 0.06, 0.08, 0.98); sug:SetBackdropBorderColor(0.62, 0.5, 0.18, 1)
  sug:SetFrameLevel(pane:GetFrameLevel() + 10)
  sug:Hide()
  self.suggest, self.suggestPool = sug, NS.Pool.New()
end

local function buildBody(self, pane)
  self.strip = CreateFrame("Frame", nil, pane)
  self.strip:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, LEGEND_H + GAP)
  self.strip:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -4, LEGEND_H + GAP)
  self.strip:SetHeight(STRIP_H)
  self.stripAxis = self.strip:CreateTexture(nil, "ARTWORK")
  self.stripAxis:SetColorTexture(0.45, 0.45, 0.5, 0.8)
  self.stripPool = NS.Pool.New()
  self.legend = CreateFrame("Frame", nil, pane)
  self.legend:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 0)
  self.legend:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -4, 0)
  self.legend:SetHeight(LEGEND_H)
  self.legendPool = NS.Pool.New()
end

function TL:Attach(pane)
  if self.pane then return end
  self.pane = pane
  buildHeader(self, pane)
  self.chart = NS.MakeLineChart(pane, {
    onHover = function(_, i) TL:OnHover(i) end,
    formatY = function(v) return TL:FormatAxis(v) end,
  })
  if self.chart then
    self.chart:SetPoint("TOPLEFT", self.bar, "BOTTOMLEFT", 0, -4)
    self.chart:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -4, STRIP_H + LEGEND_H + 2 * GAP)
  else
    -- Degraded install: say why, draw nothing else (core/WidgetsSetup.lua's header).
    self.missing = pane:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.missing:SetPoint("CENTER")
    self.missing:SetText(NS.LIBKA0S_MISSING .. ", and the Timeline needs it to draw.")
  end
  buildBody(self, pane)
  pane:SetScript("OnSizeChanged", function(p, w, h) TL:Layout(w, h) end)
  self:Refresh()
end

-- ── refresh / layout ──

local function ledgerOn()
  local s = NS.db and NS.db.profile and NS.db.profile.settings
  return not s or s.trackLedger ~= false
end

function TL:Params(f)
  local g, s = NS.db.global, NS.db.profile.settings
  return { thing = self:Thing(), range = NS.Browser:DateRange(), from = f.from, now = time(),
    allowed = f.char, maxLines = s.timelineMaxLines or 8, daily = g.daily or {},
    history = NS.Database:History(), ledgerSince = g.ledgerSince, retentionDays = g.retentionDays or 0 }
end

function TL:Refresh()
  if not self.pane then return end
  local f = NS.Browser:CurrentFilter()
  self:RenderSuggestions(f.text)
  if not (self.chart and ledgerOn()) then
    self.model = nil
    self.title:SetText(self.chart and "Turn on ledger tracking (Settings, Capture) to see the Timeline." or "")
    if self.chart then self.chart:Clear() end
    NS.Pool.ReleaseAll(self.stripPool); NS.Pool.ReleaseAll(self.legendPool)
    return
  end
  self.model = TM.Build(self:Params(f))
  self.title:SetText(self.model.title or "")
  self.chart:SetData(TM.ChartData(self.model))
  self:Layout()
end

function TL:RefreshIfShown()
  if self.pane and self.pane:IsShown() then self:Refresh() end
end

function TL:Layout(w, h)
  if not (self.pane and self.chart and self.model) then return end
  w = w or self.pane:GetWidth() or 0
  h = h or self.pane:GetHeight() or 0
  self.chart:Render(w - 4, h - BAR_H - 4 - STRIP_H - LEGEND_H - 2 * GAP)
  self:RenderStrip()
  self:RenderLegend()
end

function TL:FormatAxis(v)
  if self.model and self.model.kind == "GOLD" then return tostring(v) .. "g" end
  return tostring(v)
end

local function paintFlow(bar, f, peak, half, w)
  local C = NS.Constants.TIMELINE
  bar.up:ClearAllPoints(); bar.down:ClearAllPoints()
  bar.up:SetColorTexture(C.GAIN[1], C.GAIN[2], C.GAIN[3], 0.9)
  bar.down:SetColorTexture(C.LOSS[1], C.LOSS[2], C.LOSS[3], 0.9)
  bar.up:SetPoint("BOTTOMLEFT", bar, "LEFT", 0, 1)
  bar.up:SetSize(w, math.max(f.i > 0 and 1 or 0, f.i / peak * half))
  bar.up:SetShown(f.i > 0)
  bar.down:SetPoint("TOPLEFT", bar, "LEFT", 0, -1)
  bar.down:SetSize(w, math.max(f.o > 0 and 1 or 0, f.o / peak * half))
  bar.down:SetShown(f.o > 0)
end

function TL:RenderStrip()
  NS.Pool.ReleaseAll(self.stripPool)
  local m, c = self.model, self.chart
  local left, _, pw = c:GetPlotRect()
  if not (left and pw and pw > 0) then return end
  self.stripAxis:ClearAllPoints()
  self.stripAxis:SetPoint("LEFT", self.strip, "LEFT", left, 0)
  self.stripAxis:SetSize(pw, 1)
  local peak = 0
  for _, f in ipairs(m.flows) do peak = math.max(peak, f.i, f.o) end
  if peak == 0 then return end
  local dayPx = math.max(2, math.min(24, c:XToPixel(m.xMin + DAY) - c:XToPixel(m.xMin) - 1))
  for _, f in ipairs(m.flows) do
    local bar = NS.Pool.Acquire(self.stripPool, function() return makeFlowBar(self.strip) end)
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", self.strip, "BOTTOMLEFT", c:XToPixel(f.x), 0)
    bar:SetSize(dayPx, STRIP_H)
    paintFlow(bar, f, peak, STRIP_H / 2 - 2, dayPx)
  end
end

-- Total first in the legend (it is drawn last, on top of the chart).
function TL:RenderLegend()
  NS.Pool.ReleaseAll(self.legendPool)
  local s = self.model.series
  local order = { s[#s] }
  for i = 1, #s - 1 do order[#order + 1] = s[i] end
  for i, sr in ipairs(order) do
    local e = NS.Pool.Acquire(self.legendPool, function() return makeLegendEntry(self.legend) end)
    e:ClearAllPoints()
    e:SetPoint("LEFT", self.legend, "LEFT", (i - 1) * LEGEND_W, 0)
    e.fs:SetText(sr.label)
    e.fs:SetTextColor(sr.color[1], sr.color[2], sr.color[3])
  end
end

-- ── the picker ──

local function pickerThings(text)
  local out, seen = {}, {}
  for _, r in ipairs(NS.Holdings:Search({ text = text })) do
    out[#out + 1] = { key = r.key, name = r.name, total = r.total }
    seen[r.key] = true
  end
  for key in pairs(NS.Rollup and NS.Rollup:Keys() or {}) do
    if not seen[key] then out[#out + 1] = { key = key, name = NS.Holdings:Describe(key).name, total = 0 } end
  end
  return out
end

function TL:RenderSuggestions(text)
  NS.Pool.ReleaseAll(self.suggestPool)
  self.suggestions = {}
  if not text or text == "" then self.suggest:Hide(); return end
  self.suggestions = TM.Suggest(text, pickerThings(text), SUGGEST_MAX)
  for i, th in ipairs(self.suggestions) do
    local b = NS.Pool.Acquire(self.suggestPool, function() return makeSuggestRow(self.suggest) end)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", self.suggest, "TOPLEFT", 1, -1 - (i - 1) * ROW_H)
    b:SetPoint("RIGHT", self.suggest, "RIGHT", -1, 0)
    b.key = th.key
    b.fs:SetText(th.name)
  end
  self.suggest:SetHeight(#self.suggestions * ROW_H + 2)
  self.suggest:SetShown(#self.suggestions > 0)
end

function TL:SuggestionKeys()
  local out = {}
  for i, th in ipairs(self.suggestions or {}) do out[i] = th.key end
  return out
end

-- ── hover ──

function TL:OnHover(i)
  if not GameTooltip then return end
  local h = i and self.model and TM.HoverLines(self.model, i)
  if not h then GameTooltip:Hide(); return end
  local C = NS.Constants.TIMELINE
  GameTooltip:SetOwner(self.chart, "ANCHOR_CURSOR")
  GameTooltip:SetText(h.title, 1, 0.82, 0)
  for _, r in ipairs(h.rows) do
    GameTooltip:AddDoubleLine(r.label, r.text, r.color[1], r.color[2], r.color[3], 1, 1, 1)
  end
  GameTooltip:AddDoubleLine("Gained", h.gain, C.GAIN[1], C.GAIN[2], C.GAIN[3], C.GAIN[1], C.GAIN[2], C.GAIN[3])
  GameTooltip:AddDoubleLine("Lost", h.loss, C.LOSS[1], C.LOSS[2], C.LOSS[3], C.LOSS[1], C.LOSS[2], C.LOSS[3])
  GameTooltip:Show()
end

function TL:VisibleSeriesCount() return self.model and #self.model.series or 0 end

-- ── lifecycle ──

function TL:Enable()
  if self.__ev or not NS.bus then return end
  self.__ev = NS.NewBusTarget()
  local live = function() TL:RefreshIfShown() end
  self.__ev:RegisterMessage(NS.MSG.HOLDINGS_CHANGED, live)
  self.__ev:RegisterMessage(NS.MSG.RECORD_ADDED, NS.Coalesce(live, NS.Constants.RECORD_ADDED_COALESCE))
end

function TL:Disable()
  if not self.__ev then return end
  self.__ev:UnregisterAllMessages()
  self.__ev:UnregisterAllEvents()
  self.__ev = nil
  if GameTooltip and self.chart and GameTooltip:GetOwner() == self.chart then GameTooltip:Hide() end
end

NS.Browser:RegisterTab{ name = "Timeline", order = 30,
  filters = { search = true, date = true, char = true },
  charSource = "holders",
  build = function(pane) TL:Attach(pane) end,
  refresh = function() TL:Refresh() end }
```

`LootHistory.toc`: `modules\Timeline.lua` after `modules\TimelineModel.lua`. `core/LifecycleSetup.lua`: `if NS.Timeline and NS.Timeline.Enable then NS.Timeline:Enable() end` in `StandUp`; `NS.Timeline` in `StandDown`'s list. `tests/test_disabled.lua`: add `NS.Timeline.__ev` to `featureTargets()`'s list (its two message names, `HoldingsChanged` and `RecordAdded`, are already in `OWNED`). `tests/test_schema.lua` `PARTITION`: Interface count + 1.

> `GameTooltip:GetOwner()` — add to `tests/wow_mock.lua` only if the kit's `GameTooltip` does not answer it (check `grep -n GetOwner tests/_kit/mock_base.lua`); in the client it exists.

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS — nine new cases; `HoldingsTab: tab is registered after History and Insights` still passes (Holdings is still last); `test_disabled` sees `NS.Timeline.__ev` gone after stand-down; `test_schema` partition matches. 0/0 (`GameTooltip` is already a read-global).

- [ ] **Step 5: Regenerate inventory and commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add modules/Timeline.lua LootHistory.toc defaults/Profile.lua settings/Schema.lua core/LifecycleSetup.lua \
  tests/test_timelinetab.lua tests/test_disabled.lua tests/test_schema.lua tests/run.lua docs/test-cases.md
git commit -m "$(cat <<'EOF'
feat(timeline): Timeline tab - LibKa0s line chart, thing picker, in/out strip, legend, hover; timelineMaxLines

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt
EOF
)"
```

---

### Task B9: "Show in Timeline" (History and Holdings rows) and "Forget this character"

**Files:**
- Modify: `modules/BrowserTable.lua:1177-1252` (split `ShowRowMenu` into `RowMenuItems(record)` + `ShowMenu(anchor, items)`; add the "Show in Timeline" item)
- Modify: `modules/HoldingsTab.lua` (`HT.RowActions(line)`; row buttons take right-clicks and open `NS.BrowserTable:ShowMenu`)
- Modify: `modules/Reconciler.lua` (`R:ForgetHolder(holder)`)
- Modify: `settings/Slash.lua` (popup `KA0S_LOOTHISTORY_FORGET_HOLDER`, inside the existing `if type(StaticPopupDialogs) == "table" then` block)
- Modify: `tests/test_browsertable.lua`, `tests/test_holdingstab.lua` (append)

**Interfaces:**
- Consumes: `NS.Ledger.RowThingKey`, `NS.Browser:ShowTimeline`, `NS.Holdings:ForgetHolder`, `NS.Rollup:ForgetHolder`, `NS.Util.PlayerKey`, `NS.Constants.WARBAND_HOLDER`, `NS.MSG.HOLDINGS_CHANGED`, Phase 1's HoldingsTab line shape (`{kind="thing"|"holder", key, holder, ...}`).
- Produces:
  - `NS.BrowserTable:RowMenuItems(record) -> { {label, icon, enabled, fn} ... }`; `NS.BrowserTable:ShowMenu(anchor, items)`; `ShowRowMenu(anchor, record)` unchanged for callers.
  - `NS.HoldingsTab.RowActions(line) -> items` (thing line: Show in Timeline; holder line: Show in Timeline + Forget this character, the latter disabled for the warband and the logged-in character)
  - `NS.Reconciler:ForgetHolder(holder) -> ok:boolean, reason:"warband"|"current"|nil` — drops `db.global.holdings[holder]` and every rollup cell of it, keeps history rows, sends `HOLDINGS_CHANGED(holder)` once (the Reconciler stays the message's only sender).
  - Popup `KA0S_LOOTHISTORY_FORGET_HOLDER` (`%s` = holder label; `data = { holder = key }`).

- [ ] **Step 1: Write the failing tests**

`tests/test_browsertable.lua` — append:

```lua
test("History row menu: Show in Timeline opens the Timeline on that row's thing", function()
  local rec = { itemID = 7, itemName = "Apple", quantity = 1, ts = time(), char = "Mock-Realm" }
  local show
  for _, it in ipairs(NS.BrowserTable:RowMenuItems(rec)) do
    if it.label == "Show in Timeline" then show = it end
  end
  assertTrue(show ~= nil and show.enabled)
  show.fn()
  assertEqual(NS.Browser:ActiveTab(), "Timeline")
  assertEqual(NS.Timeline:Thing(), "i:7")
  NS.Browser:SelectTab("History")
end)

test("History row menu: Show in Timeline is disabled for a row that names no thing", function()
  for _, it in ipairs(NS.BrowserTable:RowMenuItems({ kind = "ITEM", quantity = 1 })) do
    if it.label == "Show in Timeline" then assertFalse(it.enabled) end
  end
end)

test("History row menu: the existing four entries keep their order around the new one", function()
  local labels = {}
  for _, it in ipairs(NS.BrowserTable:RowMenuItems({ itemID = 7 })) do labels[#labels + 1] = it.label end
  assertEqual(labels[1], "Link to chat"); assertEqual(labels[2], "Show in Timeline")
  assertEqual(labels[3], "Blacklist item"); assertEqual(#labels, 5)
end)
```

`tests/test_holdingstab.lua` — append:

```lua
local function captureChanged(fn)
  local got, orig = {}, NS.bus.SendMessage
  NS.bus.SendMessage = function(self, msg, a, ...)
    if msg == NS.MSG.HOLDINGS_CHANGED then got[#got + 1] = a end
    return orig(self, msg, a, ...)
  end
  fn()
  NS.bus.SendMessage = orig
  return got
end

local function labels(items)
  local out = {}
  for _, it in ipairs(items) do out[it.label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")] = it end
  return out
end

test("Holdings row actions: a thing line offers Show in Timeline", function()
  local a = labels(NS.HoldingsTab.RowActions({ kind = "thing", key = "c:3008" }))
  assertTrue(a["Show in Timeline"] ~= nil and a["Show in Timeline"].enabled)
  assertEqual(a["Forget this character"], nil, "a thing line is not a character")
end)

test("Holdings row actions: Forget is offered for an alt, never for the warband or the logged-in character", function()
  local alt = labels(NS.HoldingsTab.RowActions({ kind = "holder", key = "g", holder = "Alt-Realm" }))
  assertTrue(alt["Forget this character"].enabled)
  local wb = labels(NS.HoldingsTab.RowActions({ kind = "holder", key = "g", holder = "§warband" }))
  assertFalse(wb["Forget this character"].enabled)
  local me = labels(NS.HoldingsTab.RowActions({ kind = "holder", key = "g", holder = NS.Util.PlayerKey() }))
  assertFalse(me["Forget this character"].enabled)
end)

test("Forget this character: drops holdings and rollup cells, keeps history rows, announces once", function()
  NS.db.global.holdings, NS.db.global.daily = {}, {}
  NS.Holdings:ApplyMoney("Alt-Realm", 100, time())
  NS.Holdings:ApplyMoney("Keep-Realm", 5, time())
  local hist = #NS.db.global.history
  local got = captureChanged(function() assertTrue(NS.Reconciler:ForgetHolder("Alt-Realm")) end)
  assertEqual(NS.Holdings:Get("Alt-Realm"), nil)
  for _, holders in pairs(NS.db.global.daily) do assertEqual(holders["Alt-Realm"], nil) end
  assertTrue(NS.Holdings:Get("Keep-Realm") ~= nil)
  assertEqual(#NS.db.global.history, hist)
  assertEqual(#got, 1); assertEqual(got[1], "Alt-Realm")
end)

test("Forget this character: refuses the logged-in character and the warband", function()
  local ok, why = NS.Reconciler:ForgetHolder(NS.Util.PlayerKey())
  assertFalse(ok); assertEqual(why, "current")
  ok, why = NS.Reconciler:ForgetHolder("§warband")
  assertFalse(ok); assertEqual(why, "warband")
end)

test("Forget popup: registered, and its accept forgets the holder it carries", function()
  local d = T.mocks.StaticPopupDialogs["KA0S_LOOTHISTORY_FORGET_HOLDER"]
  assertTrue(d ~= nil and d.text:find("%s", 1, true) ~= nil)
  NS.db.global.holdings = {}
  NS.Holdings:ApplyMoney("Alt-Realm", 1, time())
  d.OnAccept(nil, { holder = "Alt-Realm" })
  assertEqual(NS.Holdings:Get("Alt-Realm"), nil)
end)
```

- [ ] **Step 2: Run to verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -E "row menu|row actions|Forget|FAIL" | head`
Expected: FAIL — `RowMenuItems`, `HT.RowActions`, `R:ForgetHolder` nil; popup missing.

- [ ] **Step 3: Implement**

`modules/BrowserTable.lua` — replace `BrowserTable:ShowRowMenu` with the split (the item bodies other than the new one move unchanged, with their comments):

```lua
-- The History row's context entries, as data (tests/test_browsertable.lua reads them). EVERY LABEL
-- STAYS -- see ShowMenu.
function BrowserTable:RowMenuItems(record)
  local thing = NS.Ledger and NS.Ledger.RowThingKey and NS.Ledger.RowThingKey(record)
  return {
    { label = "Link to chat", icon = "chat", enabled = record.itemLink ~= nil, fn = function()
        if record.itemLink and ChatEdit_InsertLink then ChatEdit_InsertLink(record.itemLink) end
      end },
    -- Chart this row's item, currency or gold over time (timeline ledger P3, spec §8.2).
    { label = "Show in Timeline", icon = "graph", enabled = thing ~= nil and NS.Timeline ~= nil,
      fn = function() NS.Browser:ShowTimeline(thing) end },
    -- (the "Blacklist item", "Blacklist currency" and "Delete" entries, unchanged)
  }
end

-- One flat context menu at `anchor`, from item data. Shared by the History table and the Holdings
-- tab so the collection has one row-menu look, not two.
function BrowserTable:ShowMenu(anchor, items)
  local m = EnsureRowMenu()
  local MENU_ROW_H, W = 18, 150
  -- (the existing button loop, SetSize, anchor and Show, unchanged, iterating `items`)
end

function BrowserTable:ShowRowMenu(anchor, record)
  self:ShowMenu(anchor, self:RowMenuItems(record))
end
```

`modules/Reconciler.lua` — append:

```lua
-- "Forget this character" (spec §8.2): drop a character's holdings and its Timeline cells. History
-- rows are kept -- they are what happened. The logged-in character would be re-created by its next
-- scan, and the warband is not a character, so both are refused. The Reconciler announces the change
-- because it is HOLDINGS_CHANGED's one sender (docs/message-bus.md).
function R:ForgetHolder(holder)
  if holder == nil or holder == C.WARBAND_HOLDER then return false, "warband" end
  if holder == NS.Util.PlayerKey() then return false, "current" end
  local had = NS.Holdings:ForgetHolder(holder)
  local cells = (NS.Rollup and NS.Rollup:ForgetHolder(holder)) or 0
  if not (had or cells > 0) then return false end
  NS.bus:SendMessage(NS.MSG.HOLDINGS_CHANGED, holder)
  return true
end
```

`settings/Slash.lua` — inside the `StaticPopupDialogs` block:

```lua
  -- "Forget this character" from a Holdings holder row (spec §8.2). The holder key arrives as the
  -- popup's data, never through a module-level variable, so two quick right-clicks cannot cross.
  StaticPopupDialogs["KA0S_LOOTHISTORY_FORGET_HOLDER"] = {
    text = "Forget %s?\n\nTheir holdings and Timeline history are removed. Loot history rows are " ..
      "kept. Logging in on them again starts their ledger afresh.",
    button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function(_, data)
      if data and data.holder and NS.Reconciler then NS.Reconciler:ForgetHolder(data.holder) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
  }
```

`modules/HoldingsTab.lua` — add:

```lua
-- Right-click actions for one Holdings line, as data (tests/test_holdingstab.lua reads them). A thing
-- line charts the thing; a holder line also offers to forget the character (spec §8.2), never the
-- warband and never the character you are logged in on (its next scan would put it straight back).
function HT.RowActions(line)
  local items = {
    { label = "Show in Timeline", icon = "graph", enabled = NS.Timeline ~= nil,
      fn = function() NS.Browser:ShowTimeline(line.key) end },
  }
  if line.kind == "holder" then
    local h = line.holder
    local forgettable = h ~= NS.Constants.WARBAND_HOLDER and h ~= NS.Util.PlayerKey()
    items[#items + 1] = { label = "|cffff5555Forget this character|r", icon = "clear", enabled = forgettable,
      fn = function() StaticPopup_Show("KA0S_LOOTHISTORY_FORGET_HOLDER", h, nil, { holder = h }) end }
  end
  return items
end
```

In `HT:Refresh`'s per-line row setup (Phase 1 Task 8), register both buttons and route the right one:

```lua
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self2, button)
      if button == "RightButton" then
        if NS.BrowserTable and NS.BrowserTable.ShowMenu then NS.BrowserTable:ShowMenu(self2, HT.RowActions(self2.line)) end
      elseif self2.line.kind == "thing" then
        HT:Toggle(self2.line.key)
      end
    end)
```

(with `row.line = line` set where the line is painted).

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS — the new cases and every existing `test_browsertable.lua` row-menu case (`ShowRowMenu` still builds the same menu plus one row). 0/0.

- [ ] **Step 5: Regenerate inventory and commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add modules/BrowserTable.lua modules/HoldingsTab.lua modules/Reconciler.lua settings/Slash.lua \
  tests/test_browsertable.lua tests/test_holdingstab.lua docs/test-cases.md
git commit -m "$(cat <<'EOF'
feat(timeline): Show in Timeline from History and Holdings rows; Forget this character

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt
EOF
)"
```

---

### Task B10: LibKa0s consumer census (in the LibKa0s repo; releasing step 9)

**Files (LibKa0s):**
- Modify: `docs/releasing.md` `## Consumers` table, `LibKa0s-Widgets-1.0` row (append: "LootHistory adopts `LineChart` at v1.69.0 through `NS.MakeLineChart` in `core/WidgetsSetup.lua`, the same named seam as its dropdown; it is the only chart host.")
- Modify: `docs/api/CONSUMERS.md` (re-run with the tool its own header names; the `lib.LineChart` row shows 1 consumer, LootHistory `core/WidgetsSetup.lua`; `lib.ChartMath` and `lib.LINE_CHART` show zero host calls with the verdict "published for hosts that align decorations; kept")

**Interfaces:** none (documentation).

- [ ] **Step 1:** From `/mnt/d/Profile/Users/Tushar/Documents/GIT/LibKa0s`, run releasing step 9's sweep and confirm LootHistory's new lookup site is the one already-named seam file:

```bash
for a in AbsorbTracker AuraMaster BankLedger ConsumableMaster KickCD LootHistory MultiMeters PanelMaster PartyFrameEnhanced PrettyChat WhatGroup; do
  grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' ../$a --include='*.lua' | grep -v '/libs/' | grep -v '/tests/'
done
```
Expected: LootHistory prints `core/WidgetsSetup.lua` for Widgets (no new lookup site).

- [ ] **Step 2:** Edit the two documents; `lua tests/run.lua && luacheck .` (0 failed, 0/0; `test_prose` reads both).

- [ ] **Step 3: Commit** (LibKa0s):

```bash
git add docs/releasing.md docs/api/CONSUMERS.md
git commit -m "$(cat <<'EOF'
TL-LK-06: consumer census - LootHistory adopts LineChart through NS.MakeLineChart

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt
EOF
)"
```

- [ ] **Step 4: ⚠ CONFIRM** — `git push origin master` in LibKa0s only with the user's go-ahead.

---

### Task B11: Documentation and smoke tests for Phase 3 (LootHistory)

**Files:**
- Modify: `docs/scope.md` — the Timeline is in scope (D8): one thing at a time, holders as lines, daily rollup kept long-term; note what is not (back-casting before genesis, per-variant counts).
- Modify: `docs/schema.md` — `db.global.daily` shape and sparsity; `rollupRetentionDays` (global, 0 = Always, reset-exempt); `rollupSeeded` (undeclared bookkeeping); `holdings[h].meta.completeAt`; `settings.timelineMaxLines`; `savedView.timelineThing`.
- Modify: `docs/module-map.md` — `modules/Rollup.lua`, `modules/TimelineModel.lua`, `modules/Timeline.lua` with TOC positions; `core/WidgetsSetup.lua` gains `NS.MakeLineChart`.
- Modify: `docs/message-bus.md` — receivers: `RECORD_ADDED` → `Timeline` (coalesced repaint; never counted); `HOLDINGS_CHANGED` → `Timeline`; sender of `HOLDINGS_CHANGED` still only the Reconciler (now also from `ForgetHolder`); the rollup is a `Database:OnWrite` hook, not a bus receiver.
- Modify: `docs/data-flow.md` — new "Daily rollup" section: the two seams, the Phase 2 contract (verbatim), seed and prune timing, the intraday rebuild and its fallback.
- Modify: `docs/browser.md` — Timeline tab (picker, lines, strip, hover, legend, dashed partial, ledgerSince marker); per-tab filter graying table (History/Insights all; Timeline Search·Date·Character; Holdings Search·Quality·Type·SubType·Character); 90 d / 1 y; "Show in Timeline"; "Forget this character".
- Modify: `docs/profiles.md` — `savedView` may now be materialized by the Timeline pick (S5).
- Modify: `docs/settings-panel.md` — the two rows; General ▸ History now holds two stored rows (exemption retired).
- Modify: `docs/disabled-state.md` — Rollup and Timeline teardown.
- Modify: `docs/ARCHITECTURE.md` — module map rows, message-bus receivers, the vendored LibKa0s version, Documentation map unchanged unless a page was added; no new deviation row unless S1–S5 were decided as deviations of **this** repo.
- Modify: `docs/superpowers/specs/2026-10-06-timeline-ledger-design.md` §4.3 — replace "Written by the reconciler alongside each row" with "Closes are written from `NS.Holdings`' write methods and in/out tallies from the `NS.Database:OnWrite` hook (Phase 3 plan, 'Phase 2 contract')" (S4).
- Modify: `docs/smoke-tests.md` — add a `## Timeline` section with:
  - **TL-1 Line regions draw.** Open the Timeline on Gold with two or more characters known: lines, y labels in gold, date labels, no Lua error (`/console scriptErrors 1`).
  - **TL-2 Line cap.** Set "Timeline lines" to 2, 8 and 16: the line count follows (Total + N), richest first; with the Character filter on one alt, only that alt + Total.
  - **TL-3 Hover.** Move across the plot: the crosshair snaps per day, the tooltip lists each line's value and that day's Gained / Lost; leaving the plot hides both; hiding the window mid-hover leaves no tooltip.
  - **TL-4 Picker.** Type part of a potion's name in Search: suggestions appear (Gold first when "gol" is typed); pick one: the chart switches and Search clears; `/reload`: the pick is remembered.
  - **TL-5 Ranges.** Today and 7 d show intraday steps after a vendor sale and a loot; 30 d / 90 d / 1 y / All show daily points; History and Insights also offer 90 d and 1 y.
  - **TL-6 Partial and marker.** A character created after the upgrade draws dashed until its bank is first opened, solid after; the ledgerSince dashed rule shows when All is selected.
  - **TL-7 Warband and colors.** Warband appears in the Character list on Timeline/Holdings as "Warband" and draws in its own blue; characters draw in class colors.
  - **TL-8 Filter graying.** On Timeline: Group, Bound, Quality, Type, SubType, Source, Zone and Export are grayed and **do not open** on click; on Holdings: Group, Date, Source, Bound, Zone and Export are grayed; History and Insights: nothing grayed.
  - **TL-9 Show in Timeline.** Right-click a History row → Show in Timeline; right-click a Holdings thing → Show in Timeline; both land on the Timeline charting that thing.
  - **TL-10 Forget.** Right-click an alt's holder line on Holdings → Forget this character → confirm: the alt leaves Holdings and the Timeline; its History rows remain; the option is grayed on the logged-in character and the warband.
  - **TL-11 Rollup retention.** Set "Keep Timeline days for" to 90 days; `/reload`; after ~5 s, older days are gone (All starts ≤ 90 days back) and every line still starts at its carried value.
  - **TL-12 Load.** 1 y on Gold with 16 lines, resize the window repeatedly: no visible hitch; the in/out strip stays aligned under the plot.
  - **TL-13 API facts.** The "WoW API facts to verify" list below: record each answer in the smoke log.
- Modify: `README.md` — feature list gains the Timeline tab; Tests badge to the `## Totals` figure.
- Regenerate: `docs/test-cases.md`.

- [ ] **Step 1:** Make the edits above in each file's voice. `tests/test_doc_structure.lua` checks ARCHITECTURE's sections and anchors.
- [ ] **Step 2:** Run `lua tests/run.lua 2>&1 | tail -5 && luacheck .` — Expected: PASS, 0/0.
- [ ] **Step 3: Commit.**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add docs/ README.md
git commit -m "$(cat <<'EOF'
docs: timeline ledger phase 3 - Timeline tab, daily rollup, filter graying, smokes TL-1..13

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt
EOF
)"
```

- [ ] **Step 4:** Hand the in-game smoke list (TL-1..13) to the user. Phase 3 is complete only when they report the smokes passed. **⚠ CONFIRM** before pushing LootHistory `master`.

---

## Spec coverage (Phase 3)

| Spec section | Task |
|---|---|
| §4.3 daily rollup: sparse `{c,i,o}` cells, carry-forward, own retention, pruned with the session prune | B3, B4, B5, B6 |
| §8.0 per-tab filters (unused ones grayed, not hidden) | B7 (+ Holdings spec), B8 (Timeline spec) |
| §8.1 thing picker via shared Search, remembered in `savedView`; "Show in Timeline" sets it | B7, B8, B9 |
| §8.1 lines: Total (thick) + up to `timelineMaxLines` holders by latest balance; Character filter; warband selectable; class colors | B6, B7, B8 |
| §8.1 Y axis native unit, nice ticks; X axis Date filter; 90 d and 1 y | A2, A3, B6, B7 |
| §8.1 intraday points for Today / 7 d within retention | B6 |
| §8.1 under-strip daily in/out bars for the Total | B6, B8 |
| §8.1 genesis start, dashed `ledgerSince` marker, dashed while partial | B4 (`completeAt`), B6, A3 |
| §8.1 hover crosshair + tooltip per date (values and that day's in/out) | A3, B6, B8 |
| §8.1 primitive: pooled LibKa0s line chart via `Texture:CreateLine`, ≤ 1 point per 2 px, host seam `NS.MakeLineChart` | A1, A2, A3, B2 |
| §8.2 "Show in Timeline" (Holdings and History rows) | B9 |
| §8.2 "Forget this character" (confirm popup; drops holdings and rollup cells; history kept) | B9 |
| §11 `settings.timelineMaxLines` (8, 2–16) | B8 |
| §11 `rollupRetentionDays` (global, 0 = Always) | B5 |
| §12 tests: pools recycle; downsampling; line cap; carry-forward; rollup cell math; disabled-state | A2, A3, B3, B4, B6, B8 |
| §12 smokes: Timeline with 1 / 8 / 16 lines | B11 (TL-2) |
| §13 F3: build in LibKa0s, release a tag, re-vendor, provenance line in the same commit | A1–A4, B1, B10 |
| §14 phase 3 | all |
| Not in this plan: §5 capture rows, claims, reasons, gold rows, §6, §7 (Phase 2); export-to-AI for loss rows (§15) | — |

## WoW API facts to verify in smoke tests (12.1.0)

These are assumed by the code above and cannot be proved headless. Record each in TL-13; any "no" is a stop-and-fix before release of the addon (and, for 1–4, a LibKa0s patch release).

1. `Frame:CreateLine(name, drawLayer)` exists on a plain `Frame` and returns a `Line` region (it has since 7.1; confirm on 12.1).
2. `Line:SetStartPoint(relativePoint, relativeTo, offsetX, offsetY)` / `SetEndPoint(...)` take that argument order, and offsets are in the **relative frame's** coordinate space (the chart's BOTTOMLEFT), so a chart inside a scaled window draws at the window's scale.
3. `Line:SetThickness(n)` accepts fractional thickness (1.5, 2.5) and `Line:SetColorTexture(r, g, b, a)` colors a Line (not only `SetVertexColor` on a textured Line).
4. Several hundred Lines on one frame (TL-12: 16 lines × up to ~300 segments + dashes) render without a visible hitch, and hidden pooled Lines cost nothing per frame.
5. `GetCursorPosition()` returns UI-scaled pixels that `/ frame:GetEffectiveScale() - frame:GetLeft()` turns into chart-local x, and `OnUpdate` armed on `OnEnter` / cleared on `OnLeave` fires only while hovered.
6. A disabled LibKa0s dropdown (a `Button`, `SetEnabled(false)`) refuses `OnClick`; `EditBox:SetEnabled(false)` blocks typing in the Search box; `SetAlpha(0.4)` reads as grayed against the flat skin.
7. `date("*t", ts)` / `time{...}` give local midnight across a daylight-saving change (EU 2026-10-25, US 2026-11-01): Timeline day labels stay on midnight and no day repeats or vanishes.
8. `GameTooltip:AddDoubleLine` renders `GetCoinTextureString` coin markup on the right side.
9. `StaticPopup_Show(name, text1, text2, data)` hands `data` to `OnAccept(self, data)` on 12.1.
10. `RAID_CLASS_COLORS[classFile]` still carries `r, g, b` for every class (Evoker included).
