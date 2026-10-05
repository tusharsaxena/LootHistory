# Timeline Ledger — Phase 2 (Ledger Capture) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Phase 1 holdings refresh into a full **ledger**: every settled holdings change becomes a gain (`IN`), loss (`OUT`) or transfer (`MOVE`) row with a reason, gold included; the existing chat paths keep their rich rows and **claim** the matching delta so nothing is counted twice; History gets a Direction column and filter, Insights gets Gained / Lost / Net and a gains-vs-losses chart; the History CSV gains `dir, kind, holder, from, to`; and the performance harness is wired (the `performance-§12` exemption is retired).

**Architecture:** All decisions are pure functions in `core/Ledger.lua` (classify a holder's container deltas into moves / net changes / escrow arrivals and exits, pair char ↔ warband, claim matching, coalesce key, hold decision, reason selection) pinned headless first. `modules/Reconciler.lua` (Phase 1) is restructured into **scan → plan → hold-or-commit**: a pass reads every dirty, readable part *without* touching `db.global.holdings`, plans rows against the stored baseline, and either **holds** that baseline (one-sided change while a pairing frame is open, or a gain still waiting for its chat claim) or **commits**: consume claims, apply holdings, write rows through `NS.Database:Add` / `NS.Database:Amend`, fire `HOLDINGS_CHANGED`. Outbound reasons come from a new `modules/AttributionOut.lua` (second single-slot TTL stamp + frame scopes, on its own private bus target). Mail and auction-house escrow live in `modules/Escrow.lua`, which plugs into the Reconciler's `SCAN_STEPS` / `PLAN_STEPS` / `COMMIT_STEPS` arrays. `NS.Database:OnWrite(fn)` is the synchronous per-row hook Phase 3's daily rollup registers on.

**Tech Stack:** Lua 5.1 (WoW Retail 12.1.0, Interface 120100), Ace3 (AceDB/AceEvent), vendored LibKa0s v1.68.1 (incl. `LibKa0s-Perf-1.0`), headless harness `lua tests/run.lua` (LibKa0s kit 36), `luacheck .`, offline runner `lua tests/perf.lua` (outside the green gate).

**Spec:** `docs/superpowers/specs/2026-10-06-timeline-ledger-design.md` (§4.1, §5 entire, §6, §7, §11 `recordGold`/`showTransfers`, §12, §13 F2 + F4 + F5, §14 phase 2).

**Builds on:** `docs/superpowers/plans/2026-10-06-timeline-ledger-p1-foundation.md` — every **Consumes** below names a Phase 1 **Produces** exactly. Phase 1 must be merged and its smokes (LED-1..8) reported passing before Task 1 starts.

**Follow-on plan:** `2026-10-06-timeline-ledger-p3-timeline.md` (LibKa0s LineChart, daily rollup writes/prune, Timeline tab). It relies on this plan's **Produces**: the row shape, `Database:OnWrite`, `Database:Amend`, `Stats().ledger`, `LedgerFormat`.

## Global Constraints

- Ka0s WoW Addon Standard governs everything. Any deviation: **STOP and flag** (CLAUDE.md). Do not add rows to `## Documented deviations` without the user's say-so. This plan **removes** one row (`performance-§12`) under the user-ratified resolution F2 (spec §13).
- Every new file opens `local _, NS = ...` and publishes `NS.X = NS.X or {}` (or extends an existing `NS.X`); no globals (`docs/common-tasks.md`).
- Every direct WoW API call goes through `core/Compat.lua` (presence-gated, degrades to nil/0/false) (`docs/compat-layer.md`). Hooks go through `NS.Compat.HookSecure` / `NS.Compat.HookSecureMember`; every hook body gates on `NS.IsStoodDown()` (the `hooksecurefunc` carve-out, slash-commands-§7).
- Every module that registers anything has a real `Disable` that unregisters; it is called from `NS.StandDown` and covered by `tests/test_disabled.lua`.
- New events are registered one-by-one via `NS.SafeRegisterEvent(target, EVENT, fn, NS.RejectedEvents)` on a **private** `NS.NewBusTarget()` target. (The Collector's existing chat events stay on the shared `NS.addon` target, as today; `CHAT_MSG_MONEY` joins them there and `Collector:Disable` unregisters it by name.)
- Bus messages: **no new message** in this phase. `RECORD_ADDED` is re-documented as "a row was added **or amended** — repaint, never count" (receivers are all coalesced repaints today: `modules/Browser.lua:1285`, `modules/Analytics.lua:263`, `settings/Panel.lua:168`).
- Settings rows live in `settings/Schema.lua`, defaults once in `defaults/Profile.lua`; every write through `Schema:Set`.
- `NS.Constants.SourceType` is **append-only** (export contract). New members are appended, never inserted, never renamed.
- Combat: every in-combat handler only sets dirty bits (or folds one event argument into a per-id accumulator); `Reconciler:Flush` returns `deferred` under `InCombatLockdown()`; work runs on `PLAYER_REGEN_ENABLED`.
- Container ids come from `NS.Constants.BAG_IDS` / `BANK_IDS` / `WARBAND_TAB_IDS` (Phase 1); never hardcode numbers.
- Warband holder key is exactly `NS.Constants.WARBAND_HOLDER` (`"§warband"`); characters are `NS.Util.PlayerKey()`.
- **Rows are never written for a holder with no `meta.genesis`, nor for a container whose `scanned[c]` was nil before this pass** (its first scan is its own genesis).
- **Blacklisted itemIDs never get a row** (any direction); `currencyBlacklist` and `recordCurrency=false` suppress currency rows; `recordGold=false` suppresses gold rows. Holdings still count all of them.
- Files ≤ 1500 lines (`tests/_kit/test_layout_cap.lua`). Current: `modules/Browser.lua` ≤ 1318 after Phase 1, `modules/BrowserTable.lua` 1252, `core/Database.lua` 972, `modules/Attribution.lua` 483, `modules/Analytics.lua` 649. New logic goes into new files (`modules/AttributionOut.lua`, `modules/Escrow.lua`, `modules/LedgerFormat.lua`, `modules/AnalyticsLedger.lua`, `core/PerfSetup.lua`) so no file crosses 1400.
- Match surrounding comment density and idiom (this repo comments the *why* heavily). Code blocks below show the logic; add the explanatory comments the neighbors would have.
- Green gate before every commit: `lua tests/run.lua` (all pass) and `luacheck .` (0 warnings / 0 errors). Regenerate `docs/test-cases.md` with `lua tests/run.lua --list > docs/test-cases.md` in any task that adds tests.
- Work trunk-based on `master`; commit at the end of each task only when green. Commit trailer (append to every message below):
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt
  ```

## Review Focus

1. **Bag → bank deposit** (bags −5, bank +5 in one settled pass) → exactly **one** `MOVE` row (`from = me/bags`, `to = me/bank`) and **zero** `IN`/`OUT` rows. Pinned in Task 7 (`Reconciler: bag to bank deposit writes one MOVE and no gain or loss`).
2. **Chat loot + holdings diff** for the same 3 items → exactly **one** row in history (the rich chat row, stamped `claimed=true`), whichever of the chat line and the bag delta arrives first. Pinned in Task 2 (pure claim math) and Task 8 (`Collector+Reconciler: a looted stack is counted once, chat first` / `…delta first`).
3. **Combat burst** (5 potions drunk in combat, 20 `BAG_UPDATE`s) → zero scans in combat, then **one** `OUT` row `source=CONSUME quantity=5` after `PLAYER_REGEN_ENABLED`; a second burst 30 s later amends that row to 10 instead of appending. Pinned in Task 7 (`Reconciler: combat potion burst lands as one CONSUME row and coalesces`).
4. **Login drift vs genesis** → first login after v11 writes **no** rows; a later login whose stored snapshot differs writes `UNTRACKED` rows only, and claims/holds are bypassed. Pinned in Task 9 (`Reconciler: first login is genesis and writes nothing` / `Reconciler: login drift writes UNTRACKED rows`).
5. **Perf brackets are free when off** → with `Perf.on == false` no bracket calls `Perf.Note` and no bracket allocates; every declared bucket is reached when on; `Perf.Suspend()` unregisters the Collector's chat events and the Reconciler/AttributionOut targets and `Perf.Resume()` restores them. Pinned in Task 13 (`perf: a dormant probe notes nothing`, `perf: every declared bucket is reached by a real bracket`, `perf: suspend makes the addon inert and resume restores it`) and by `tests/perf.lua`'s zero-overhead scenario.

## Standards flags (decide before Task 1)

| # | Item | Standard / contract touched | What this plan does | Decision needed |
|---|---|---|---|---|
| S1 | Outbound reasons use a **second** single-slot TTL context (`State.outContext`) beside the existing `State.lootContext`, rather than generalizing `lootContext` → `State.context` as spec §5.4 words it. | Spec wording only (no standard rule). | One `BuyMerchantItem` call must stamp **both** an inbound `VENDOR` (for the item gain) and an outbound `BUY` (for the gold loss); a single slot makes one clobber the other. Both slots share `CONTEXT_TTL` and the `IsStoodDown` funnel gate. | Confirm the spec refinement (else: one slot with per-direction fields). |
| S2 | `RECORD_ADDED` is also sent for an **amended** (coalesced) row with the same `(record, index)` payload. | `architecture-§4` message contract / `docs/message-bus.md`. | No new message (closed set); all three receivers are coalesced repaints. Documented in `docs/message-bus.md` and `core/Constants.lua`'s MSG comment. | Confirm (else: add `RECORD_AMENDED` per the add-a-message recipe). |
| S3 | `NS.Constants.SOURCE_IMPLEMENTED` stays total (new reasons have live paths) but the **mute list** (`SOURCE_OPTIONS`) excludes the 18 ledger reasons (`C.LEDGER_REASON`). | `options-ui` (no dead checkbox) vs the existing "every implemented source is a mute option" invariant pinned in `tests/test_constants.lua:72`. | Updates that test to "implemented sources minus ledger reasons". Muting gates the *rich chat record*; a ledger reason never reaches that gate. | Confirm. |
| S4 | History CSV: the five new columns are appended **after** `wowheadLink`, which `modules/Export.lua:114`'s comment says "stays the final column". | F4 (accepted) + `scope.md:223-226`. | Literal append (existing columns keep their order and index); the comment is rewritten; the pinned header in `tests/test_export.lua:31` is extended. `tests/export_golden.txt` (Insights CSV) is untouched: the new Insights "Ledger" rows are emitted only when the range holds a loss or transfer row, which no fixture does. | Confirm append-after-wowheadLink (else: insert before it, which moves `wowheadLink`'s index). |
| S5 | Perf harness wiring (performance-§1..§9) and removal of the `performance-§12` row. | F2 (accepted). | Wired per the standard, including the degradation **stub** performance-§1 requires (siblings like ConsumableMaster return without one — this plan follows the standard, not the sibling). | None — recorded for the reviewer. |
| S6 | Mail/AH escrow: inbox arrivals and auction exits are **holdings-only** until resolved (taken from mail / sold-mail / returned). Holdings ≠ genesis + Σgains − Σlosses while items sit in escrow. | Spec §1 invariant. | Documented as a Known limitation in `docs/ARCHITECTURE.md`; reconciles once the escrow resolves. | Confirm the limitation (else: book arrivals as `IN` and accept double counting with the take's chat line). |
| S7 | Every positive delta without a claim waits up to `CLAIM_WAIT` (1.5 s) before being written (spec §5.3 "held for the settle window"). Vendor-sale gold therefore lands ~1.5 s late. | Spec §5.3. | As specified. | None. |

No other deviation is foreseen: all new registrations are per-event on private targets, all hooks gate on the latch, all settings are schema rows, no file crosses the cap.

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `core/Constants.lua` | Modify | 18 appended `SourceType` members + labels + order; `LEDGER_REASON`; `DirRGB`/`DirGlyph`/`DirLabel`; `GOLD_TYPE`; `CRAFT_TTL`; `CURRENCY_SOURCE_REASON`; mute list excludes ledger reasons. |
| `core/Ledger.lua` | Modify | Pure: `ClassifyItems`, `PairHolders`, claims (`PostClaim`/`ClaimAvailable`/`ConsumeClaim`/`PruneClaims`), `CoalesceKey`, `Amendable`, `ShouldHold`, `PickReason`, `CurrencyReason`. |
| `core/Database.lua` | Modify | `OnWrite` hooks, `Amend`, QueryList `dir` + `minQuality` clauses, `Export` ledger fields, `Stats().ledger`, legacy charts fed by `dir==IN` non-gold rows only. |
| `core/Compat.lua` | Modify | Hook helpers, consumable test, account-wide currency, currency-source enum names, inbox / send-mail / owned-auction reads, item-location id, mail kind, trade target, latest currency transfer. |
| `core/Util.lua` | Modify | `Util.ParseSelfMoney` (CHAT_MSG_MONEY). |
| `core/PerfSetup.lua` | Create | `NS.Perf` (LibKa0s-Perf instance or stub). |
| `core/LifecycleSetup.lua` | Modify | StandUp/StandDown include `Attribution:EnableOut/DisableOut`; perf-hold comment. |
| `modules/AttributionOut.lua` | Create | Outbound stamps, frame scopes, outbound hooks, guild-bank frame hooks, `ReasonContext`. |
| `modules/Reconciler.lua` | Modify | scan → plan → hold/commit; row writer; claims API; coalescing; currency deltas; login/resume reconcile. |
| `modules/Escrow.lua` | Create | Mail inbox + auctions containers; own-alt mail in flight; AH post in flight; auction exits/returns/sold. |
| `modules/Holdings.lua` | Modify | `Escrow(holder)`, `CreditEscrow`, `CreditCurrency`. |
| `modules/Collector.lua` | Modify | Claims after each rich row; `CHAT_MSG_MONEY` gold rows; perf brackets. |
| `modules/Attribution.lua` | Modify | Perf bracket on `OnSpellSucceeded`. |
| `modules/LedgerFormat.lua` | Create | Pure display helpers: glyph, colors, signed qty/count/money, holder label. |
| `modules/BrowserTable.lua` | Modify | Direction column (mono face), signed/colored Qty, group-by Direction/Holder, test data carries ledger rows. |
| `modules/Browser.lua` | Modify | Direction filter (row 1), default view: min-quality floor + Transfers per setting, group options. |
| `modules/Analytics.lua` | Modify | Gained/Lost/Net/Transfers cards; ledger section hook; empty-state rule. |
| `modules/AnalyticsLedger.lua` | Create | Back-to-back renderer + "Gains vs losses" sections + pre-ledger caveat. |
| `modules/Export.lua` | Modify | CSV `dir,kind,holder,from,to`; Insights CSV ledger section. |
| `settings/Schema.lua` | Modify | `settings.recordGold`, `settings.showTransfers`, min-quality relabel, `perf` verb. |
| `settings/Slash.lua` | Modify | `perf` in `UNAVAILABLE_WITHOUT_LIB`. |
| `defaults/Profile.lua` | Modify | `recordGold = true`, `showTransfers = false`. |
| `LootHistory.toc` | Modify | `LootHistoryPerfDB`; new files. |
| `.luacheckrc` | Modify | New read_globals; `LootHistoryPerfDB` global. |
| `tests/wow_mock.lua` | Modify | Mail/AH/send/trade/currency-source mocks, money strings. |
| `tests/test_ledger.lua`, `tests/test_reconciler_rows.lua`, `tests/test_attribution_out.lua`, `tests/test_escrow.lua`, `tests/test_ledgerformat.lua`, `tests/test_perf.lua` | Create/Modify | Suites. |
| `tests/perf.lua` | Create | Offline runner (outside the gate). |
| docs (`ARCHITECTURE.md`, `data-flow.md`, `schema.md`, `message-bus.md`, `module-map.md`, `browser.md`, `performance.md`, `combat-path-sweep.md`, `perf-analysis/README.md`, `disabled-state.md`, `compat-layer.md`, `smoke-tests.md`, `scope.md`, `test-cases.md`) | Modify/Create | Tasks 13–14. |

---

### Task 1: Ledger reasons and display constants

**Files:**
- Modify: `core/Constants.lua:8-41` (SourceType/SourceOrder/SourceLabel/SOURCE_IMPLEMENTED), `:120-127` (SOURCE_OPTIONS loop); append ledger display constants after `C.Kind`/`C.WARBAND_HOLDER` (Phase 1 block)
- Modify: `modules/AnalyticsFormat.lua:43-52` (`SOURCE_COLOR`)
- Modify: `modules/BrowserTable.lua:464-533` (`BuildTestData`: ledger reasons carry `dir`)
- Test: `tests/test_constants.lua:60-80` (mute-list case), append new cases

**Interfaces:**
- Consumes: `NS.Constants.Dir`, `NS.Constants.Kind` (Phase 1 Task 1).
- Produces:
  - `NS.Constants.SourceType.{SELL,BUY,REPAIR,MAIL_SEND,TRADE_GIVE,AH_POST_FEE,AH_SOLD,AH_BUY,DESTROY,CONSUME,CRAFT_REAGENT,DECONSTRUCT,GUILD_DEPOSIT,GUILD_WITHDRAW,TRAINING,TRAVEL,TRANSFER,UNTRACKED}` (value == key)
  - `NS.Constants.LEDGER_REASON` — set of exactly those 18 keys
  - `NS.Constants.DirRGB = { IN={0.35,0.80,0.45}, OUT={1,0.33,0.33}, MOVE={0.62,0.62,0.66} }`
  - `NS.Constants.DirGlyph = { IN="▲", OUT="▼", MOVE="⇄" }` (UTF-8 escapes; mono face only)
  - `NS.Constants.DirLabel = { IN="Gain", OUT="Loss", MOVE="Transfer" }`, `NS.Constants.DirOrder = {"IN","OUT","MOVE"}`
  - `NS.Constants.GOLD_TYPE = "Gold"`, `NS.Constants.GOLD_RGB = {1.00,0.86,0.55}`
  - `NS.Constants.CRAFT_TTL = 6`

- [ ] **Step 1: Write the failing tests** — append to `tests/test_constants.lua`, and replace the body of `"Constants: the mute options are the implemented sources, in display order"` (line 72) so it skips ledger reasons:

```lua
test("Constants: the mute options are the implemented sources, in display order", function()
  local i = 0
  for _, s in ipairs(C.SourceOrder) do
    if C.SOURCE_IMPLEMENTED[s] and not C.LEDGER_REASON[s] then
      i = i + 1
      assertEqual(C.SOURCE_OPTIONS[i].value, s, "mute option " .. i .. " out of order")
      assertEqual(C.SOURCE_OPTIONS[i].text, C.SourceLabel[s])
    end
  end
  assertEqual(#C.SOURCE_OPTIONS, i, "no extra mute options")
end)

local LEDGER_KEYS = { "SELL", "BUY", "REPAIR", "MAIL_SEND", "TRADE_GIVE", "AH_POST_FEE", "AH_SOLD",
  "AH_BUY", "DESTROY", "CONSUME", "CRAFT_REAGENT", "DECONSTRUCT", "GUILD_DEPOSIT", "GUILD_WITHDRAW",
  "TRAINING", "TRAVEL", "TRANSFER", "UNTRACKED" }

test("Constants: ledger reasons are appended SourceType members with labels", function()
  for _, k in ipairs(LEDGER_KEYS) do
    assertEqual(C.SourceType[k], k)
    assertTrue(C.LEDGER_REASON[k], k .. " missing from LEDGER_REASON")
    assertTrue(type(C.SourceLabel[k]) == "string" and C.SourceLabel[k] ~= "", k .. " has no label")
  end
  local n = 0; for _ in pairs(C.LEDGER_REASON) do n = n + 1 end
  assertEqual(n, #LEDGER_KEYS)
end)

test("Constants: existing sources keep their order positions (append-only)", function()
  local legacy = { "KILL", "CONTAINER", "MPLUS", "BONUS_ROLL", "ROLL", "QUEST", "TRADE", "MAIL", "AH",
    "VENDOR", "DISENCHANT", "MILLING", "PROSPECTING", "CRAFT", "REFUND", "OTHER" }
  for i, s in ipairs(legacy) do assertEqual(C.SourceOrder[i], s) end
  for i, s in ipairs(LEDGER_KEYS) do assertEqual(C.SourceOrder[#legacy + i], s) end
end)

test("Constants: no ledger reason is offered as a capture mute", function()
  for _, o in ipairs(C.SOURCE_OPTIONS) do assertFalse(C.LEDGER_REASON[o.value], o.value) end
end)

test("Constants: direction palette and glyphs", function()
  for _, d in ipairs(C.DirOrder) do
    assertEqual(#C.DirRGB[d], 3)
    assertTrue(type(C.DirGlyph[d]) == "string" and #C.DirGlyph[d] >= 3, "glyph is a multibyte char")
    assertTrue(type(C.DirLabel[d]) == "string")
  end
  assertEqual(C.GOLD_TYPE, "Gold")
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -E "FAIL|Constants:" | head -20`
Expected: FAIL — `C.LEDGER_REASON` is nil, `C.SourceType.SELL` is nil.

- [ ] **Step 3: Implement** — `core/Constants.lua`. Append to `C.SourceType` (after `REFUND = "REFUND",`):

```lua
  -- Ledger reasons (timeline-ledger spec §4.1/§5.4), APPENDED in 2026-10: `source` now carries the
  -- reason for gains AND losses. Stored strings and export contract like every member above.
  SELL = "SELL", BUY = "BUY", REPAIR = "REPAIR", MAIL_SEND = "MAIL_SEND", TRADE_GIVE = "TRADE_GIVE",
  AH_POST_FEE = "AH_POST_FEE", AH_SOLD = "AH_SOLD", AH_BUY = "AH_BUY", DESTROY = "DESTROY",
  CONSUME = "CONSUME", CRAFT_REAGENT = "CRAFT_REAGENT", DECONSTRUCT = "DECONSTRUCT",
  GUILD_DEPOSIT = "GUILD_DEPOSIT", GUILD_WITHDRAW = "GUILD_WITHDRAW", TRAINING = "TRAINING",
  TRAVEL = "TRAVEL", TRANSFER = "TRANSFER", UNTRACKED = "UNTRACKED",
```

Append to `C.SourceOrder` after `"OTHER"`:

```lua
  -- Ledger reasons, appended (append-only display order; the gain sources above keep their slots).
  "SELL", "BUY", "REPAIR", "MAIL_SEND", "TRADE_GIVE", "AH_POST_FEE", "AH_SOLD", "AH_BUY",
  "DESTROY", "CONSUME", "CRAFT_REAGENT", "DECONSTRUCT", "GUILD_DEPOSIT", "GUILD_WITHDRAW",
  "TRAINING", "TRAVEL", "TRANSFER", "UNTRACKED",
```

Append to `C.SourceLabel`:

```lua
  SELL = "Sell", BUY = "Buy", REPAIR = "Repair", MAIL_SEND = "Mail Sent", TRADE_GIVE = "Trade Given",
  AH_POST_FEE = "AH Deposit", AH_SOLD = "AH Sold", AH_BUY = "AH Bought", DESTROY = "Destroyed",
  CONSUME = "Consumed", CRAFT_REAGENT = "Crafting Reagent", DECONSTRUCT = "Deconstructed",
  GUILD_DEPOSIT = "Guild Deposit", GUILD_WITHDRAW = "Guild Withdraw", TRAINING = "Training",
  TRAVEL = "Travel", TRANSFER = "Transfer", UNTRACKED = "Untracked",
```

Append to `C.SOURCE_IMPLEMENTED`:

```lua
  SELL = true, BUY = true, REPAIR = true, MAIL_SEND = true, TRADE_GIVE = true, AH_POST_FEE = true,
  AH_SOLD = true, AH_BUY = true, DESTROY = true, CONSUME = true, CRAFT_REAGENT = true,
  DECONSTRUCT = true, GUILD_DEPOSIT = true, GUILD_WITHDRAW = true, TRAINING = true, TRAVEL = true,
  TRANSFER = true, UNTRACKED = true,
```

Directly after `C.SOURCE_IMPLEMENTED`:

```lua
-- The reasons only the LEDGER writes (holdings diffs, timeline-ledger spec §5.4). They have live
-- paths (so SOURCE_IMPLEMENTED stays total) but they are NOT capture mutes: the mute list gates the
-- rich chat record (Collector), and no chat line ever carries one of these.
C.LEDGER_REASON = {
  SELL = true, BUY = true, REPAIR = true, MAIL_SEND = true, TRADE_GIVE = true, AH_POST_FEE = true,
  AH_SOLD = true, AH_BUY = true, DESTROY = true, CONSUME = true, CRAFT_REAGENT = true,
  DECONSTRUCT = true, GUILD_DEPOSIT = true, GUILD_WITHDRAW = true, TRAINING = true, TRAVEL = true,
  TRANSFER = true, UNTRACKED = true,
}
```

Change the `C.SOURCE_OPTIONS` loop condition to:

```lua
  if C.SOURCE_IMPLEMENTED[s] and not C.LEDGER_REASON[s] then
```

After the Phase 1 ledger enum block (`C.WARBAND_HOLDER`), append:

```lua
-- Direction display (History column, Insights, Timeline). Cosmetic only — never stored. Colors are
-- BankLedger's (core/Constants.lua DirectionRGB) so a gain/loss reads the same in both addons.
C.DirOrder = { "IN", "OUT", "MOVE" }
C.DirLabel = { IN = "Gain", OUT = "Loss", MOVE = "Transfer" }
C.DirRGB = {
  IN   = { 0.35, 0.80, 0.45 },
  OUT  = { 1.00, 0.33, 0.33 },
  MOVE = { 0.62, 0.62, 0.66 },
}
-- TEXT glyphs: the default font has none of them and draws a box, so any FontString showing one
-- MUST use C.FONT_MONO (the LibKa0s JetBrains Mono face). ▲ U+25B2, ▼ U+25BC, ⇄ U+21C4.
C.DirGlyph = { IN = "\226\150\178", OUT = "\226\150\188", MOVE = "\226\135\132" }
-- Gold rows (kind GOLD): the Type value they carry, and the pale gold their quantity is drawn in.
C.GOLD_TYPE = "Gold"
C.GOLD_RGB = { 1.00, 0.86, 0.55 }
-- Seconds a tradeskill craft keeps reagent losses attributed to CRAFT_REAGENT (a cast is 1-3 s; a
-- queued "craft all" re-arms it per CraftRecipe call).
C.CRAFT_TTL = 6
```

`modules/AnalyticsFormat.lua` — add to `SOURCE_COLOR` (keep existing entries; new reasons in muted, distinct tones):

```lua
  SELL = { 0.80, 0.62, 0.20 }, BUY = { 0.70, 0.45, 0.25 }, REPAIR = { 0.55, 0.50, 0.45 },
  MAIL_SEND = { 0.20, 0.45, 0.70 }, TRADE_GIVE = { 0.10, 0.50, 0.50 },
  AH_POST_FEE = { 0.60, 0.30, 0.55 }, AH_SOLD = { 0.85, 0.45, 0.75 }, AH_BUY = { 0.55, 0.25, 0.50 },
  DESTROY = { 0.45, 0.20, 0.20 }, CONSUME = { 0.30, 0.65, 0.55 }, CRAFT_REAGENT = { 0.20, 0.45, 0.30 },
  DECONSTRUCT = { 0.42, 0.36, 0.72 }, GUILD_DEPOSIT = { 0.25, 0.60, 0.25 },
  GUILD_WITHDRAW = { 0.40, 0.75, 0.40 }, TRAINING = { 0.75, 0.70, 0.30 }, TRAVEL = { 0.50, 0.65, 0.80 },
  TRANSFER = { 0.62, 0.62, 0.66 }, UNTRACKED = { 0.40, 0.40, 0.44 },
```

`modules/BrowserTable.lua` `BuildTestData` — inside `make`, directly after the `out[#out + 1] = { ... }` record, add (no extra `rng` draws, so every record's other fields are unchanged for a given seed index):

```lua
    -- A ledger reason in the seed walk is a loss (TRANSFER a transfer), so the preview shows the
    -- Direction column and the gains-vs-losses charts with real shapes.
    if C.LEDGER_REASON[source] then
      local rec = out[#out]
      rec.dir = (source == "TRANSFER") and "MOVE" or "OUT"
      rec.kind, rec.holder = "ITEM", rec.char
    end
```

> `seedN` grows with `#C.SourceOrder` (16 → 34), so the bulk pass draws from a later PRNG state and the preview dataset changes. Grep `tests/test_browsertable.lua` and `tests/test_analytics.lua` for counts pinned on `BuildTestData()` (e.g. `#data`, a specific `byQuality` count) and update them to the new deterministic values the run prints.

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: all PASS (test_browsertable's "every SourceType is represented" passes because the seed walk covers the appended members), luacheck 0/0.

- [ ] **Step 5: Regenerate inventory and commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add core/Constants.lua modules/AnalyticsFormat.lua modules/BrowserTable.lua tests/test_constants.lua tests/test_browsertable.lua tests/test_analytics.lua docs/test-cases.md
git commit -m "feat(ledger): append 18 ledger reasons to SourceType; direction palette and glyphs" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt"
```

---

### Task 2: Pure classification — items, holder pairs, claims, coalescing, hold

**Files:**
- Modify: `core/Ledger.lua` (append after Phase 1's `Ledger.Diff`)
- Test: `tests/test_ledger.lua` (append)

**Interfaces:**
- Consumes: `NS.Ledger.ThingKey`, `NS.Ledger.Diff` (Phase 1).
- Produces (all pure, no WoW API):
  - Constants: `Ledger.CLAIM_TTL = 5`, `Ledger.CLAIM_WAIT = 1.5`, `Ledger.SETTLE_TIMEOUT = 6`, `Ledger.COALESCE_WINDOW = 60`, `Ledger.CONTAINER_ORDER = {"bags","equipped","bank","tabs","mail","auctions"}`, `Ledger.ESCROW = {mail=true, auctions=true}`.
  - `Ledger.ClassifyItems(before, after, own) -> moves, net, arrivals, exits`
    - `before`/`after`: `{ [container] = {[itemID]=n} }`; only containers present in **both** are compared.
    - `own`: `{ mail = {[itemID]=n} }|nil` — escrow provenance (own-origin counts in mail).
    - `moves`: array `{ id=, qty=, from=<container>, to=<container> }` (intra-holder, deterministic order: id asc, then CONTAINER_ORDER).
    - `net`: `{ [itemID] = signed }` — gains/losses after pairing (escrow → non-escrow beyond `own` counts as a gain; mail leaving without landing counts as nothing).
    - `arrivals`: `{ mail = {[id]=n}, auctions = {[id]=n} }` — escrow increases with no source (holdings-only).
    - `exits`: `{ [id] = n }` — `auctions` decreases with no sink (pending sale/return).
  - `Ledger.PairHolders(holderA, netA, holderB, netB) -> pairs` — mutates both nets; `pairs = { {key=, qty=, from=<holder>, to=<holder>} }` sorted by key.
  - `Ledger.PostClaim(claims, key, qty, row, now)`; `Ledger.ClaimAvailable(claims, key, now) -> n`; `Ledger.ConsumeClaim(claims, key, gain, now) -> remainder, matchedRows|nil`; `Ledger.PruneClaims(claims, now)`.
  - `Ledger.CoalesceKey(holder, key, dir, reason, route) -> string`; `Ledger.Amendable(entry, now) -> boolean` (`entry = {row=, index=, ts=}`).
  - `Ledger.ShouldHold(oneSided, unclaimedGain, holdSince, now) -> boolean`.
  - `Ledger.Signed(dir, qty) -> number` (`qty * DirSign[dir]`).

- [ ] **Step 1: Write the failing tests** — append to `tests/test_ledger.lua`:

```lua
local L = function() return NS.Ledger end

test("Ledger: ClassifyItems pairs a bag-to-bank deposit into one MOVE, no net", function()
  local moves, net = L().ClassifyItems(
    { bags = { [7] = 5 }, bank = { [7] = 0 } },
    { bags = { [7] = 0 }, bank = { [7] = 5 } })
  assertEqual(#moves, 1)
  assertEqual(moves[1].id, 7); assertEqual(moves[1].qty, 5)
  assertEqual(moves[1].from, "bags"); assertEqual(moves[1].to, "bank")
  assertEqual(next(net), nil)
end)

test("Ledger: ClassifyItems keeps the unpaired remainder as net change", function()
  local moves, net = L().ClassifyItems(
    { bags = { [7] = 5 }, bank = {} },
    { bags = { [7] = 1 }, bank = { [7] = 3 } })
  assertEqual(moves[1].qty, 3)
  assertEqual(net[7], -1)              -- 4 left the bags, 3 landed: 1 is a loss
end)

test("Ledger: ClassifyItems ignores containers not rescanned on both sides", function()
  local moves, net = L().ClassifyItems({ bags = { [7] = 5 } }, { bags = { [7] = 2 }, bank = { [7] = 3 } })
  assertEqual(#moves, 0)
  assertEqual(net[7], -3)              -- bank had no baseline: never inferred
end)

test("Ledger: mail taken is a gain unless it was own-origin", function()
  local before = { bags = {}, mail = { [9] = 4 } }
  local after  = { bags = { [9] = 4 }, mail = {} }
  local moves, net = L().ClassifyItems(before, after, { mail = { [9] = 1 } })
  assertEqual(#moves, 1); assertEqual(moves[1].qty, 1); assertEqual(moves[1].from, "mail")
  assertEqual(net[9], 3)
end)

test("Ledger: escrow arrivals and auction exits never become net", function()
  local _, net, arrivals, exits = L().ClassifyItems(
    { mail = {}, auctions = { [3] = 2 } },
    { mail = { [5] = 1 }, auctions = {} })
  assertEqual(next(net), nil)
  assertEqual(arrivals.mail[5], 1)
  assertEqual(exits[3], 2)
end)

test("Ledger: posting bags to auctions is a MOVE", function()
  local moves, net = L().ClassifyItems({ bags = { [3] = 2 }, auctions = {} }, { bags = {}, auctions = { [3] = 2 } })
  assertEqual(moves[1].to, "auctions"); assertEqual(next(net), nil)
end)

test("Ledger: PairHolders turns a warband deposit into one pair and clears both nets", function()
  local me, wb = { ["i:7"] = -2, g = -500 }, { ["i:7"] = 2, g = 300 }
  local pairs_ = L().PairHolders("A-Realm", me, "§warband", wb)
  assertEqual(#pairs_, 2)
  assertEqual(pairs_[1].key, "g"); assertEqual(pairs_[1].qty, 300)
  assertEqual(pairs_[1].from, "A-Realm"); assertEqual(pairs_[1].to, "§warband")
  assertEqual(pairs_[2].key, "i:7"); assertEqual(pairs_[2].qty, 2)
  assertEqual(me.g, -200); assertEqual(me["i:7"], nil); assertEqual(wb.g, nil)
end)

test("Ledger: PairHolders leaves same-sign changes alone", function()
  local me, wb = { g = 10 }, { g = 5 }
  assertEqual(#L().PairHolders("A", me, "§warband", wb), 0)
  assertEqual(me.g, 10); assertEqual(wb.g, 5)
end)

test("Ledger: claims consume fully, partially, and expire", function()
  local claims, rowA, rowB = {}, {}, {}
  L().PostClaim(claims, "i:7", 3, rowA, 100)
  assertEqual(L().ClaimAvailable(claims, "i:7", 101), 3)
  local rest, matched = L().ConsumeClaim(claims, "i:7", 5, 101)
  assertEqual(rest, 2); assertTrue(matched[1] == rowA)
  assertEqual(claims["i:7"], nil)
  L().PostClaim(claims, "g", 50, rowB, 100)
  rest = L().ConsumeClaim(claims, "g", 20, 101)
  assertEqual(rest, 0); assertEqual(L().ClaimAvailable(claims, "g", 101), 30)
  assertEqual(L().ClaimAvailable(claims, "g", 100 + L().CLAIM_TTL + 1), 0)   -- expired
  L().PruneClaims(claims, 200)
  assertEqual(claims.g, nil)
end)

test("Ledger: a late claim is still consumed inside its TTL", function()
  local claims, row = {}, {}
  L().PostClaim(claims, "c:3008", 10, row, 50)
  local rest, matched = L().ConsumeClaim(claims, "c:3008", 10, 54)
  assertEqual(rest, 0); assertTrue(matched[1] == row)
end)

test("Ledger: coalesce key and the 60 s amend window", function()
  local k1 = L().CoalesceKey("A", "i:7", "OUT", "CONSUME")
  assertEqual(k1, L().CoalesceKey("A", "i:7", "OUT", "CONSUME"))
  assertTrue(k1 ~= L().CoalesceKey("A", "i:7", "OUT", "SELL"))
  assertTrue(L().CoalesceKey("A", "i:7", "MOVE", "TRANSFER", "bags>bank")
    ~= L().CoalesceKey("A", "i:7", "MOVE", "TRANSFER", "bank>bags"))
  assertTrue(L().Amendable({ ts = 1000 }, 1059))
  assertFalse(L().Amendable({ ts = 1000 }, 1060))
  assertFalse(L().Amendable(nil, 1000))
end)

test("Ledger: ShouldHold — one-sided waits 6 s, unclaimed gain waits 1.5 s", function()
  local H = L().ShouldHold
  assertFalse(H(false, false, nil, 0))
  assertTrue(H(true, false, nil, 10)); assertTrue(H(true, false, 10, 15.9)); assertFalse(H(true, false, 10, 16))
  assertTrue(H(false, true, 10, 11)); assertFalse(H(false, true, 10, 11.5))
end)

test("Ledger: Signed applies DirSign", function()
  assertEqual(L().Signed("IN", 4), 4); assertEqual(L().Signed("OUT", 4), -4); assertEqual(L().Signed("MOVE", 4), 0)
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -E "FAIL.*Ledger" | head -20`
Expected: FAIL — `ClassifyItems`, `PairHolders`, `PostClaim`, … are nil.

- [ ] **Step 3: Implement** — append to `core/Ledger.lua`:

```lua
-- ── Phase 2: classification (timeline-ledger spec §5.1, §5.3, §5.5) ──────────────────────────
-- Everything the Reconciler decides about a settled change, as pure functions over count maps.

Ledger.CLAIM_TTL       = 5     -- a chat claim waits this long for its holdings delta
Ledger.CLAIM_WAIT      = 1.5   -- a gain waits this long for its chat claim (delta-first case)
Ledger.SETTLE_TIMEOUT  = 6     -- a one-sided change at an open bank/mailbox/AH waits this long (BankLedger)
Ledger.COALESCE_WINDOW = 60    -- a same-key row younger than this is amended, not appended

-- Pairing order: sources and sinks are matched in this fixed order so the output is deterministic.
Ledger.CONTAINER_ORDER = { "bags", "equipped", "bank", "tabs", "mail", "auctions" }
-- Escrow: things that are the holder's but not in hand. Arrivals here are holdings-only (no row)
-- until resolved: a take from mail, a sale or a return from the auction house.
Ledger.ESCROW = { mail = true, auctions = true }

local ESCROW = Ledger.ESCROW

local function sortedIDs(maps)
  local seen, ids = {}, {}
  for _, m in ipairs(maps) do
    for id in pairs(m) do if not seen[id] then seen[id] = true; ids[#ids + 1] = id end end
  end
  table.sort(ids)
  return ids
end

-- One item's per-container deltas split into sources (went down) and sinks (went up).
local function splitDeltas(id, list, before, after)
  local src, snk = {}, {}
  for _, c in ipairs(list) do
    local d = (after[c][id] or 0) - (before[c][id] or 0)
    if d < 0 then src[#src + 1] = { c = c, n = -d } elseif d > 0 then snk[#snk + 1] = { c = c, n = d } end
  end
  return src, snk
end

-- Match sources to sinks. An escrow source only MOVEs its own-origin count; the rest of what it
-- hands to a non-escrow sink is a gain from outside (mail from another player, a won auction).
local function pairWithin(id, src, snk, own, moves)
  local gain = 0
  for _, s in ipairs(src) do
    for _, t in ipairs(snk) do
      if s.n > 0 and t.n > 0 and not (ESCROW[s.c] and ESCROW[t.c]) then
        local q = math.min(s.n, t.n)
        local movable = q
        if ESCROW[s.c] then movable = math.min(q, (own and own[s.c] and own[s.c][id]) or 0) end
        if movable > 0 then moves[#moves + 1] = { id = id, qty = movable, from = s.c, to = t.c } end
        gain = gain + (q - movable)
        s.n, t.n = s.n - q, t.n - q
      end
    end
  end
  return gain
end

function Ledger.ClassifyItems(before, after, own)
  local moves, net = {}, {}
  local arrivals, exits = { mail = {}, auctions = {} }, {}
  local list, maps = {}, {}
  for _, c in ipairs(Ledger.CONTAINER_ORDER) do
    if before[c] and after[c] then
      list[#list + 1] = c
      maps[#maps + 1] = before[c]; maps[#maps + 1] = after[c]
    end
  end
  for _, id in ipairs(sortedIDs(maps)) do
    local src, snk = splitDeltas(id, list, before, after)
    local d = pairWithin(id, src, snk, own, moves)
    for _, s in ipairs(src) do
      if s.n > 0 then
        if s.c == "auctions" then exits[id] = (exits[id] or 0) + s.n
        elseif s.c ~= "mail" then d = d - s.n end   -- mail gone without landing: it never counted
      end
    end
    for _, t in ipairs(snk) do
      if t.n > 0 then
        if ESCROW[t.c] then arrivals[t.c][id] = (arrivals[t.c][id] or 0) + t.n else d = d + t.n end
      end
    end
    if d ~= 0 then net[id] = d end
  end
  return moves, net, arrivals, exits
end

-- Inter-holder pairing (char <-> §warband): opposite-sign changes of one thing on the two holders
-- are a transfer for the smaller magnitude. Both nets are reduced in place; zeros are removed.
function Ledger.PairHolders(a, netA, b, netB)
  local keys = {}
  for k in pairs(netA) do if netB[k] then keys[#keys + 1] = k end end
  table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
  local out = {}
  for _, k in ipairs(keys) do
    local x, y = netA[k], netB[k]
    if (x < 0) ~= (y < 0) then
      local q = math.min(math.abs(x), math.abs(y))
      out[#out + 1] = { key = k, qty = q, from = (x < 0) and a or b, to = (x < 0) and b or a }
      x = x + ((x < 0) and q or -q); y = y + ((y < 0) and q or -q)
      netA[k] = (x ~= 0) and x or nil
      netB[k] = (y ~= 0) and y or nil
    end
  end
  return out
end

-- ── Claims ──────────────────────────────────────────────────────────────────────────────────
-- claims[thingKey] = array of { qty, expires, row }. Posted by the chat paths after they write a
-- rich row; consumed by the Reconciler against a positive delta of the same thing.

function Ledger.PostClaim(claims, key, qty, row, now)
  local list = claims[key]
  if not list then list = {}; claims[key] = list end
  list[#list + 1] = { qty = qty, expires = now + Ledger.CLAIM_TTL, row = row }
end

function Ledger.ClaimAvailable(claims, key, now)
  local n = 0
  for _, c in ipairs(claims[key] or {}) do if c.expires >= now then n = n + c.qty end end
  return n
end

function Ledger.ConsumeClaim(claims, key, gain, now)
  local list = claims[key]
  if not list or gain <= 0 then return gain, nil end
  local matched, i = nil, 1
  while i <= #list and gain > 0 do
    local c = list[i]
    if c.expires < now then
      table.remove(list, i)
    else
      local take = math.min(gain, c.qty)
      gain, c.qty = gain - take, c.qty - take
      matched = matched or {}
      matched[#matched + 1] = c.row
      if c.qty == 0 then table.remove(list, i) else i = i + 1 end
    end
  end
  if #list == 0 then claims[key] = nil end
  return gain, matched
end

function Ledger.PruneClaims(claims, now)
  for key, list in pairs(claims) do
    for i = #list, 1, -1 do if list[i].expires < now then table.remove(list, i) end end
    if #list == 0 then claims[key] = nil end
  end
end

-- ── Coalescing and the settle hold ──────────────────────────────────────────────────────────
function Ledger.CoalesceKey(holder, key, dir, reason, route)
  return table.concat({ holder, tostring(key), dir, reason, route or "" }, "\001")
end

function Ledger.Amendable(entry, now)
  return entry ~= nil and (now - entry.ts) < Ledger.COALESCE_WINDOW
end

-- Hold the baseline (write nothing, keep the dirty bits) while a change is plausibly half-done:
-- a one-sided move at an open bank/mailbox/AH (the other side is a server round-trip away), or a
-- gain whose chat claim has not arrived yet. Each wait is bounded; past it the pass commits.
function Ledger.ShouldHold(oneSided, unclaimedGain, holdSince, now)
  if not (oneSided or unclaimedGain) then return false end
  local waited = holdSince and (now - holdSince) or 0
  if oneSided and waited < Ledger.SETTLE_TIMEOUT then return true end
  if unclaimedGain and waited < Ledger.CLAIM_WAIT then return true end
  return false
end

function Ledger.Signed(dir, qty) return (qty or 0) * (Ledger.DirSign[dir] or 0) end
```

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS, 0/0.

- [ ] **Step 5: Commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add core/Ledger.lua tests/test_ledger.lua docs/test-cases.md
git commit -m "feat(ledger): pure item classification, holder pairing, claims, coalescing, hold" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt"
```

---

### Task 3: Pure reason selection

**Files:**
- Modify: `core/Ledger.lua` (append)
- Modify: `core/Constants.lua` (append `CURRENCY_SOURCE_REASON`)
- Test: `tests/test_ledger.lua` (append)

**Interfaces:**
- Consumes: `NS.Constants.LEDGER_REASON`, `NS.Constants.SourceType` (Task 1).
- Produces:
  - `NS.Constants.CURRENCY_SOURCE_REASON = { gain = {[enumMemberName]=reason}, loss = {[enumMemberName]=reason} }`
  - `NS.Ledger.PickReason(kind, dir, ctx) -> reason` with `ctx = { now, forced, out = {reason, expires, dirs?, kinds?}|nil, loot = {source, expires}|nil, scopes = {merchant, guildBank, mailbox, auction, trainer, taxi, bank}, craftUntil, consumable, currencySrc }`. Precedence: `forced` > fresh `out` stamp matching dir/kind > `currencySrc` > guild bank scope > merchant scope > gold-out scopes (trainer/taxi/auction/mailbox) > item-out inference (deconstruct loot stamp, craft window, consumable) > fresh inbound loot stamp (IN) > mailbox/auction scope (IN) > `OTHER`.
  - `NS.Ledger.CurrencyReason(enumName, dir) -> reason|nil`.

- [ ] **Step 1: Write the failing tests** — append to `tests/test_ledger.lua`:

```lua
local function ctx(t)
  t.now = t.now or 100
  t.scopes = t.scopes or {}
  return t
end

test("Ledger: PickReason — forced wins (login drift)", function()
  assertEqual(L().PickReason("ITEM", "OUT", ctx({ forced = "UNTRACKED", scopes = { merchant = true } })), "UNTRACKED")
end)

test("Ledger: PickReason — a fresh outbound stamp beats scopes, filtered by kind/dir", function()
  local c = ctx({ out = { reason = "REPAIR", expires = 101, kinds = { GOLD = true }, dirs = { OUT = true } },
                  scopes = { merchant = true } })
  assertEqual(L().PickReason("GOLD", "OUT", c), "REPAIR")
  assertEqual(L().PickReason("ITEM", "OUT", c), "SELL")        -- stamp is gold-only
  c.out.expires = 99
  assertEqual(L().PickReason("GOLD", "OUT", c), "BUY")         -- stale stamp: merchant scope
end)

test("Ledger: PickReason — merchant scope", function()
  local c = ctx({ scopes = { merchant = true } })
  assertEqual(L().PickReason("ITEM", "OUT", c), "SELL")
  assertEqual(L().PickReason("GOLD", "IN", c), "SELL")
  assertEqual(L().PickReason("GOLD", "OUT", c), "BUY")
  assertEqual(L().PickReason("ITEM", "IN", c), "VENDOR")
end)

test("Ledger: PickReason — guild bank is outside the account", function()
  local c = ctx({ scopes = { guildBank = true, merchant = true } })
  assertEqual(L().PickReason("ITEM", "OUT", c), "GUILD_DEPOSIT")
  assertEqual(L().PickReason("GOLD", "IN", c), "GUILD_WITHDRAW")
end)

test("Ledger: PickReason — gold-out scopes", function()
  assertEqual(L().PickReason("GOLD", "OUT", ctx({ scopes = { trainer = true } })), "TRAINING")
  assertEqual(L().PickReason("GOLD", "OUT", ctx({ scopes = { taxi = true } })), "TRAVEL")
  assertEqual(L().PickReason("GOLD", "OUT", ctx({ scopes = { auction = true } })), "AH_POST_FEE")
  assertEqual(L().PickReason("GOLD", "OUT", ctx({ scopes = { mailbox = true } })), "MAIL_SEND")
end)

test("Ledger: PickReason — item losses by inference", function()
  assertEqual(L().PickReason("ITEM", "OUT", ctx({ loot = { source = "DISENCHANT", expires = 101 } })), "DECONSTRUCT")
  assertEqual(L().PickReason("ITEM", "OUT", ctx({ craftUntil = 105 })), "CRAFT_REAGENT")
  assertEqual(L().PickReason("ITEM", "OUT", ctx({ consumable = true })), "CONSUME")
  assertEqual(L().PickReason("ITEM", "OUT", ctx({})), "OTHER")
end)

test("Ledger: PickReason — gains read the inbound loot stamp, then mailbox/AH scope", function()
  assertEqual(L().PickReason("ITEM", "IN", ctx({ loot = { source = "KILL", expires = 101 } })), "KILL")
  assertEqual(L().PickReason("ITEM", "IN", ctx({ scopes = { mailbox = true } })), "MAIL")
  assertEqual(L().PickReason("ITEM", "IN", ctx({ scopes = { auction = true } })), "AH")
  assertEqual(L().PickReason("CURRENCY", "IN", ctx({})), "OTHER")
end)

test("Ledger: PickReason — currency source names map before scopes", function()
  assertEqual(L().PickReason("CURRENCY", "OUT", ctx({ currencySrc = "CRAFT_REAGENT", scopes = { merchant = true } })),
    "CRAFT_REAGENT")
end)

test("Ledger: CurrencyReason maps known enum member names, nil otherwise", function()
  assertEqual(L().CurrencyReason("Vendor", "OUT"), "BUY")
  assertEqual(L().CurrencyReason("QuestReward", "IN"), "QUEST")
  assertEqual(L().CurrencyReason("AccountTransfer", "OUT"), "TRANSFER")
  assertEqual(L().CurrencyReason("NoSuchMember", "IN"), nil)
  assertEqual(L().CurrencyReason(nil, "IN"), nil)
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -E "FAIL.*PickReason|FAIL.*CurrencyReason" | head`
Expected: FAIL — `PickReason` nil.

- [ ] **Step 3: Implement**

`core/Constants.lua` — append:

```lua
-- CURRENCY_DISPLAY_UPDATE's gainSource / destroyReason, mapped BY ENUM MEMBER NAME
-- (Enum.CurrencySource / Enum.CurrencyDestroyReason, reverse-looked-up in core/Compat.lua) to a
-- ledger reason. By name, never by number: the numbers are not documented as stable. A member not
-- listed maps to nil and the reason falls through to the context stamps. The names below are the
-- 12.x members as recalled; docs/smoke-tests.md LED-P2-14 verifies them in the client.
C.CURRENCY_SOURCE_REASON = {
  gain = {
    QuestReward = "QUEST", Vendor = "VENDOR", Trade = "TRADE", ItemRefund = "REFUND",
    GuildBankWithdrawal = "GUILD_WITHDRAW", AccountTransfer = "TRANSFER",
  },
  loss = {
    Vendor = "BUY", Trade = "TRADE_GIVE", FulfillCraftingOrder = "CRAFT_REAGENT",
    ConcentrationCast = "CRAFT_REAGENT", AccountTransfer = "TRANSFER", Spell = "CONSUME",
  },
}
```

`core/Ledger.lua` — append:

```lua
-- ── Reasons (timeline-ledger spec §5.4) ─────────────────────────────────────────────────────
local DECONSTRUCT_SOURCE = { DISENCHANT = true, MILLING = true, PROSPECTING = true }

local function stampApplies(o, kind, dir, now)
  return o and o.expires >= now and (not o.dirs or o.dirs[dir]) and (not o.kinds or o.kinds[kind])
end

local function scopeReason(kind, dir, s)
  if s.guildBank then return dir == "OUT" and "GUILD_DEPOSIT" or "GUILD_WITHDRAW" end
  if s.merchant then
    if dir == "OUT" then return kind == "ITEM" and "SELL" or "BUY" end
    return kind == "ITEM" and "VENDOR" or "SELL"
  end
  if kind == "GOLD" and dir == "OUT" then
    if s.trainer then return "TRAINING" end
    if s.taxi then return "TRAVEL" end
    if s.auction then return "AH_POST_FEE" end
    if s.mailbox then return "MAIL_SEND" end
  end
  return nil
end

local function inferItemLoss(c)
  local l = c.loot
  if l and l.expires >= c.now and DECONSTRUCT_SOURCE[l.source] then return "DECONSTRUCT" end
  if c.craftUntil and c.craftUntil >= c.now then return "CRAFT_REAGENT" end
  if c.consumable then return "CONSUME" end
  return nil
end

function Ledger.PickReason(kind, dir, c)
  if c.forced then return c.forced end
  if stampApplies(c.out, kind, dir, c.now) then return c.out.reason end
  if c.currencySrc then return c.currencySrc end
  local s = c.scopes or {}
  local r = scopeReason(kind, dir, s)
  if r then return r end
  if kind == "ITEM" and dir == "OUT" then r = inferItemLoss(c); if r then return r end end
  if dir == "IN" then
    local l = c.loot
    if l and l.expires >= c.now then return l.source end
    if s.mailbox then return "MAIL" end
    if s.auction then return "AH" end
  end
  return "OTHER"
end

function Ledger.CurrencyReason(name, dir)
  if not name then return nil end
  local map = NS.Constants.CURRENCY_SOURCE_REASON[dir == "IN" and "gain" or "loss"]
  return map and map[name] or nil
end
```

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS, 0/0.

- [ ] **Step 5: Commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add core/Ledger.lua core/Constants.lua tests/test_ledger.lua docs/test-cases.md
git commit -m "feat(ledger): pure reason selection and currency-source mapping" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt"
```

---
### Task 4: Database — write hooks, amend, ledger filters, ledger Stats, export fields

**Files:**
- Modify: `core/Database.lua:410-419` (`Add`), add `Amend`/`OnWrite`/`RemoveWriteHook` after it; `:446-549` (`compileFilter`/`QueryList` + new `matchLedger`); `:558-572` (`Export`); `:584-606` (`newAccumulator`), `:796-848` (`Stats`)
- Modify: `modules/Export.lua:70-116` (CSV columns, F4)
- Modify: `core/Constants.lua` MSG comment for `RECORD_ADDED` (S2)
- Test: `tests/test_database.lua`, `tests/test_stats.lua`, `tests/test_export.lua:31-41` (append cases; extend the pinned header)

**Interfaces:**
- Consumes: `NS.Util.RowDir/RowKind/RowHolder` (Phase 1), `NS.Constants.GOLD_TYPE` (Task 1).
- Produces:
  - `NS.Database:OnWrite(fn) -> fn` — `fn(record, deltaQty, isNew)` runs synchronously for **every** `Add` (`deltaQty = record.quantity or 1`, `isNew = true`) and `Amend` (`deltaQty = added`, `isNew = false`), before `RECORD_ADDED` is sent. **Phase 3's rollup registers here.** `NS.Database:RemoveWriteHook(fn)`.
  - `NS.Database:Amend(index, addQty) -> record|nil` — `quantity += addQty`, hooks, then `RECORD_ADDED(record, index)`.
  - Query filter fields: `dir` (scalar or set over `"IN"|"OUT"|"MOVE"`, legacy rows read `"IN"`); `minQuality` (number: ITEM rows — `itemID ~= nil` — below it are hidden) with `minQualityExempt` (set of itemIDs that bypass the floor, i.e. the whitelist).
  - `Database:Export` rows gain `dir, kind, holder, from, to, claimed`.
  - `Stats(filter).ledger = { gainedCount, lostCount, movedCount, gainedValue, lostValue, netValue, netCount, reasonIn={[src]=count}, reasonOut={[src]=count}, valueReasonIn={}, valueReasonOut={}, charIn={[char]=value}, charOut={[char]=value}, kindIn={[kind]=count}, kindOut={[kind]=count}, goldIn, goldOut, preLedgerRows }` — value = item value (as before) or copper for GOLD rows; currency value 0. Every pre-existing `Stats` field (incl. `totals.records`) now counts only `dir == "IN"` rows of kind ITEM/CURRENCY, so legacy histories produce identical numbers.
  - CSV (`NS.Export:CSV`) appends `dir,kind,holder,from,to` after `wowheadLink`.

- [ ] **Step 1: Write the failing tests** — append to `tests/test_database.lua`:

```lua
test("Database: OnWrite hooks see Add and Amend with the quantity delta", function()
  local g = NS.db.global
  local saved = g.history
  g.history = {}
  local seen = {}
  local hook = NS.Database:OnWrite(function(r, d, isNew) seen[#seen + 1] = { r = r, d = d, n = isNew } end)
  local row = { ts = 1, itemID = 7, quantity = 2, dir = "OUT", source = "CONSUME" }
  local idx = NS.Database:Add(row)
  NS.Database:Amend(idx, 3)
  NS.Database:RemoveWriteHook(hook)
  NS.Database:Add({ ts = 2, itemID = 8, quantity = 1 })
  assertEqual(#seen, 2)
  assertTrue(seen[1].r == row); assertEqual(seen[1].d, 2); assertTrue(seen[1].n)
  assertEqual(seen[2].d, 3); assertFalse(seen[2].n)
  assertEqual(row.quantity, 5)
  g.history = saved
end)

test("Database: Amend re-sends RecordAdded with the same record and index", function()
  local g = NS.db.global
  local saved = g.history
  g.history = {}
  local got, orig = {}, NS.bus.SendMessage
  NS.bus.SendMessage = function(_, msg, r, i) if msg == NS.MSG.RECORD_ADDED then got[#got + 1] = { r, i } end end
  local idx = NS.Database:Add({ ts = 1, itemID = 7, quantity = 1 })
  NS.Database:Amend(idx, 1)
  NS.bus.SendMessage = orig
  assertEqual(#got, 2); assertTrue(got[2][1] == g.history[idx]); assertEqual(got[2][2], idx)
  assertEqual(NS.Database:Amend(99, 1), nil)
  g.history = saved
end)

test("Database: QueryList dir clause treats legacy rows as gains", function()
  local rows = { { itemID = 1 }, { itemID = 2, dir = "OUT" }, { itemID = 3, dir = "MOVE" } }
  assertEqual(#NS.Database:QueryList(rows, { dir = "IN" }), 1)
  assertEqual(#NS.Database:QueryList(rows, { dir = { IN = true, OUT = true } }), 2)
  assertEqual(#NS.Database:QueryList(rows, {}), 3)
end)

test("Database: minQuality floors items only, whitelist exempt", function()
  local rows = {
    { itemID = 1, quality = 0 }, { itemID = 2, quality = 2 }, { itemID = 3, quality = 0 },
    { currencyID = 3008, quality = 1 }, { kind = "GOLD", quantity = 100 },
  }
  local out = NS.Database:QueryList(rows, { minQuality = 1, minQualityExempt = { [3] = true } })
  local ids = {}
  for _, r in ipairs(out) do ids[#ids + 1] = tostring(r.itemID or r.currencyID or r.kind) end
  assertEqual(table.concat(ids, ","), "2,3,3008,GOLD")
end)

test("Database: Export carries the ledger fields with legacy defaults", function()
  local g = NS.db.global
  local saved = g.history
  g.history = {
    { ts = 1, char = "A-Realm", itemID = 1, quantity = 1 },
    { ts = 2, char = "A-Realm", kind = "GOLD", dir = "MOVE", holder = "§warband", quantity = 50,
      from = "A-Realm/money", to = "§warband/money" },
  }
  local out = NS.Database:Export({})
  assertEqual(out[1].dir, "IN"); assertEqual(out[1].kind, "ITEM"); assertEqual(out[1].holder, "A-Realm")
  assertEqual(out[2].dir, "MOVE"); assertEqual(out[2].kind, "GOLD")
  assertEqual(out[2].from, "A-Realm/money"); assertEqual(out[2].to, "§warband/money")
  g.history = saved
end)
```

Append to `tests/test_stats.lua`:

```lua
local function seedLedger()
  NS.db.global.history = {
    { ts = T1, char = "A-Realm", itemID = 10, itemName = "Sword", quality = 4, source = "KILL", quantity = 1, vendorPrice = 100 },
    { ts = T1, char = "A-Realm", itemID = 11, itemName = "Potion", quality = 1, source = "CONSUME",
      dir = "OUT", kind = "ITEM", quantity = 5, vendorPrice = 10 },
    { ts = T2, char = "A-Realm", kind = "GOLD", itemName = "Gold", source = "SELL", dir = "IN", quantity = 700 },
    { ts = T2, char = "B-Realm", kind = "GOLD", itemName = "Gold", source = "REPAIR", dir = "OUT", quantity = 300 },
    { ts = T2, char = "A-Realm", itemID = 10, itemName = "Sword", quality = 4, source = "TRANSFER",
      dir = "MOVE", kind = "ITEM", quantity = 1, from = "A-Realm/bags", to = "A-Realm/bank" },
  }
end

test("Stats: legacy breakdowns count only gains of items and currency", function()
  seedLedger()
  local s = NS.Database:Stats({})
  assertEqual(s.totals.records, 1)
  assertEqual(s.bySource.KILL, 1)
  assertEqual(s.bySource.CONSUME, nil)
  assertEqual(s.bySource.SELL, nil)
end)

test("Stats: ledger gains, losses, net and transfers", function()
  seedLedger()
  local L = NS.Database:Stats({}).ledger
  assertEqual(L.gainedCount, 2); assertEqual(L.lostCount, 2); assertEqual(L.movedCount, 1)
  assertEqual(L.gainedValue, 100 + 700)           -- sword value + gold copper
  assertEqual(L.lostValue, 5 * 10 + 300)
  assertEqual(L.netValue, 800 - 350); assertEqual(L.netCount, 0)
  assertEqual(L.reasonOut.CONSUME, 1); assertEqual(L.reasonIn.SELL, 1)
  assertEqual(L.goldIn, 700); assertEqual(L.goldOut, 300)
  assertEqual(L.charOut["B-Realm"], 300)
  assertEqual(L.kindIn.GOLD, 1); assertEqual(L.kindOut.ITEM, 1)
end)

test("Stats: preLedgerRows counts rows older than ledgerSince", function()
  seedLedger()
  local g = NS.db.global
  local saved = g.ledgerSince
  g.ledgerSince = T2
  assertEqual(NS.Database:Stats({}).ledger.preLedgerRows, 2)
  g.ledgerSince = saved
end)
```

In `tests/test_export.lua:41`, change the final line of the pinned header from `"wowheadLink")` to:

```lua
    "wowheadLink,dir,kind,holder,from,to")
```

and append:

```lua
test("Export: CSV ledger columns follow wowheadLink and default for legacy rows", function()
  local csv = NS.Export:CSV({
    { ts = 1, char = "A-Realm", itemID = 1, quantity = 1 },
    { ts = 2, char = "A-Realm", kind = "GOLD", dir = "OUT", holder = "A-Realm", quantity = 5, source = "REPAIR" },
  })
  local lines = {}
  for line in csv:gmatch("(.-)\r\n") do lines[#lines + 1] = line end
  assertTrue(lines[2]:find(",IN,ITEM,A%-Realm,,$") ~= nil, lines[2])
  assertTrue(lines[3]:find(",OUT,GOLD,A%-Realm,,$") ~= nil, lines[3])
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -E "FAIL" | head -20`
Expected: FAIL — `OnWrite`/`Amend` nil, dir clause ignored, `ledger` nil, header mismatch.

- [ ] **Step 3: Implement** — `core/Database.lua`.

Replace `Database:Add` and add the hook plumbing directly above it:

```lua
-- Per-row write hooks (timeline-ledger spec §4.3): the daily rollup (Phase 3) and any later
-- per-row accountant register here and are called SYNCHRONOUSLY for every row this module writes
-- or amends, with the quantity that changed. Synchronous on purpose: a bus message would let a
-- receiver see the row after a later amend, and the rollup's in/out cells must add each delta once.
local writeHooks = {}

function Database:OnWrite(fn)
  writeHooks[#writeHooks + 1] = fn
  return fn
end

function Database:RemoveWriteHook(fn)
  for i = #writeHooks, 1, -1 do if writeHooks[i] == fn then table.remove(writeHooks, i) end end
end

local function runWriteHooks(record, delta, isNew)
  for i = 1, #writeHooks do writeHooks[i](record, delta, isNew) end
end

-- Append a record to the account-wide history; run the write hooks; fire RecordAdded; return its index.
function Database:Add(record)
  local history = NS.db.global.history
  history[#history + 1] = record
  local index = #history
  runWriteHooks(record, record.quantity or 1, true)
  if NS.bus then
    NS.bus:SendMessage(NS.MSG.RECORD_ADDED, record, index)
  end
  return index
end

-- Grow an existing row in place (the Reconciler's 60 s coalescing, spec §5.5). RecordAdded is sent
-- again with the same (record, index): every receiver is a coalesced repaint, never a counter.
function Database:Amend(index, addQty)
  local r = NS.db.global.history[index]
  if not r or not addQty or addQty == 0 then return nil end
  r.quantity = (r.quantity or 1) + addQty
  runWriteHooks(r, addQty, false)
  if NS.bus then NS.bus:SendMessage(NS.MSG.RECORD_ADDED, r, index) end
  return r
end
```

Add the ledger clause beside `matchRange`:

```lua
-- The ledger clauses (timeline-ledger spec §7): direction (a legacy row has no `dir` and is a gain)
-- and the default view's min-quality floor, which applies to ITEM rows only — currency never had
-- the quality gate and gold has no quality — and never to a whitelisted id.
local function matchLedger(r, dirSet, minQ, exempt)
  if dirSet and not dirSet[r.dir or "IN"] then return false end
  if minQ and r.itemID ~= nil and (r.quality or 0) < minQ and not (exempt and exempt[r.itemID]) then
    return false
  end
  return true
end
```

In `compileFilter`, add to the plan table and flags:

```lua
    dirSet   = membershipSet(filter.dir),
    minQ     = type(filter.minQuality) == "number" and filter.minQuality or nil,
    minQEx   = type(filter.minQualityExempt) == "table" and filter.minQualityExempt or nil,
```

```lua
  p.anyLedger = p.dirSet or p.minQ
```

In `QueryList`, hoist and test it:

```lua
  local anyLedger, dirSet, minQ, minQEx = p.anyLedger, p.dirSet, p.minQ, p.minQEx
```

```lua
    if (not anyQ or matchQuality(r, qSet, qExact))
        and (not anyScalar or matchScalarOrSet(r, srcSet, chrSet, itypeSet, isubSet, zoneSet))
        and (not anyRange or matchRange(r, boundSet, from, to, text))
        and (not anyLedger or matchLedger(r, dirSet, minQ, minQEx)) then
```

Update the QueryList field comment to list `dir · minQuality · minQualityExempt`.

`Database:Export` — add to each output row:

```lua
      dir = NS.Util.RowDir(r), kind = NS.Util.RowKind(r), holder = NS.Util.RowHolder(r),
      from = r.from, to = r.to, claimed = r.claimed,
```

Stats — add the ledger accumulator beside `newAccumulator`:

```lua
-- The ledger half of a Stats pass (timeline-ledger spec §6). Every row lands here; only gains of
-- items and currency also feed the legacy breakdowns, so their meaning does not change.
local function newLedger()
  return {
    gainedCount = 0, lostCount = 0, movedCount = 0, gainedValue = 0, lostValue = 0,
    reasonIn = {}, reasonOut = {}, valueReasonIn = {}, valueReasonOut = {},
    charIn = {}, charOut = {}, kindIn = {}, kindOut = {}, goldIn = 0, goldOut = 0,
    preLedgerRows = 0,
  }
end

local function accumulateLedger(L, dir, kind, qty, value, src, ch)
  if dir == "MOVE" then L.movedCount = L.movedCount + 1; return end
  local v = (kind == "GOLD") and qty or value
  local gain = dir ~= "OUT"
  local reasons, values, chars, kinds =
    gain and L.reasonIn or L.reasonOut, gain and L.valueReasonIn or L.valueReasonOut,
    gain and L.charIn or L.charOut, gain and L.kindIn or L.kindOut
  if gain then L.gainedCount, L.gainedValue = L.gainedCount + 1, L.gainedValue + v
  else L.lostCount, L.lostValue = L.lostCount + 1, L.lostValue + v end
  reasons[src] = (reasons[src] or 0) + 1
  values[src] = (values[src] or 0) + v
  if ch then chars[ch] = (chars[ch] or 0) + v end
  kinds[kind] = (kinds[kind] or 0) + 1
  if kind == "GOLD" then
    if gain then L.goldIn = L.goldIn + qty else L.goldOut = L.goldOut + qty end
  end
end
```

Replace the `Stats` loop body:

```lua
function Database:Stats(filter)
  local records = self:Query(filter or {})
  local A = newAccumulator()
  local L = newLedger()
  local since = NS.db and NS.db.global and NS.db.global.ledgerSince
  local loot = 0

  for _, r in ipairs(records) do
    local qty = r.quantity or 1
    -- Inline legacy defaults (NS.Util.RowDir/RowKind) — no per-record call on the read path.
    local dir = r.dir or "IN"
    local kind = r.kind or ((r.itemID == nil and r.currencyID ~= nil) and "CURRENCY" or "ITEM")
    local value = (kind == "ITEM") and (NS.Util.RecordValue(r) or 0) * qty or 0
    local src = r.source or "OTHER"
    local ch = r.char
    accumulateLedger(L, dir, kind, qty, value, src, ch)
    if since and r.ts and r.ts < since then L.preLedgerRows = L.preLedgerRows + 1 end

    if dir == "IN" and kind ~= "GOLD" then
      loot = loot + 1
      local isCurrency = kind == "CURRENCY"
      A.totalValue = A.totalValue + value
      A.totalQuantity = A.totalQuantity + qty
      if isCurrency then accumulateCurrency(A, r, src, qty) else accumulateItem(A, r, ch, src, value) end
      accumulateTime(A, r, value)
      accumulateProvenance(A, r, value)
      accumulateChar(A, r, ch, isCurrency, value)
    end
  end
  L.netValue = L.gainedValue - L.lostValue
  L.netCount = L.gainedCount - L.lostCount
```

…and in the returned table set `records = loot` (instead of `#records`) inside `totals`, and add `ledger = L,` at the top level. (A legacy currency row had `value = RecordValue(r) * qty` before; it carries no vendor/auction price, so `0` is the same number.)

`modules/Export.lua` — after `COLUMNS[#COLUMNS + 1] = { "wowheadLink", … }`:

```lua
-- Ledger columns (timeline-ledger spec §13 F4), APPENDED after wowheadLink so every earlier column
-- keeps its index for existing spreadsheets. Legacy rows export their accessor defaults.
COLUMNS[#COLUMNS + 1] = { "dir",    function(r) return NS.Util.RowDir(r) end }
COLUMNS[#COLUMNS + 1] = { "kind",   function(r) return NS.Util.RowKind(r) end }
COLUMNS[#COLUMNS + 1] = { "holder", function(r) return NS.Util.RowHolder(r) end }
COLUMNS[#COLUMNS + 1] = { "from",   function(r) return r.from end }
COLUMNS[#COLUMNS + 1] = { "to",     function(r) return r.to end }
```

and rewrite the column comment's last sentence to: "`wowheadLink` follows the auction columns; the five ledger columns (`dir, kind, holder, from, to`) are appended after it."

`core/Constants.lua` MSG comment for `RECORD_ADDED`:

```lua
  -- Sender: core/Database.lua `Database:Add` and `Database:Amend`. Payload: (record, index) — a row
  -- was added OR grew in place (60 s coalescing). Receivers repaint; none may count it as one more.
```

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS, 0/0. `tests/test_analytics_layout.lua` (golden) and `tests/test_export.lua`'s Insights goldens stay green: the fixtures are all legacy gains.

- [ ] **Step 5: Commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add core/Database.lua core/Constants.lua modules/Export.lua tests/test_database.lua tests/test_stats.lua tests/test_export.lua docs/test-cases.md
git commit -m "feat(db): write hooks, Amend, dir/minQuality filters, ledger Stats, CSV ledger columns (F4)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt"
```

---

### Task 5: Compat shims, money-line parser, mock support

**Files:**
- Modify: `core/Compat.lua` (append `-- ── Ledger capture (Phase 2) ──` section)
- Modify: `core/Util.lua` (append `Util.BuildMoneyPatterns`, `Util.ParseSelfMoney`)
- Modify: `tests/wow_mock.lua` (append mocks before `return M`)
- Modify: `.luacheckrc` `read_globals` (add only the missing: `GetInboxNumItems`, `GetInboxItem`, `GetInboxItemLink`, `GetSendMailItem`, `GetSendMailItemLink`, `GetSendMailMoney`, `ATTACHMENTS_MAX_RECEIVE`, `ATTACHMENTS_MAX_SEND`, `C_AuctionHouse`, `C_TradeSkillUI`, `GuildBankFrame`, `YOU_LOOT_MONEY`, `LOOT_MONEY_SPLIT`, `YOU_LOOT_MONEY_GUILD`, `GOLD_AMOUNT`, `SILVER_AMOUNT`, `COPPER_AMOUNT`, `AUCTION_SOLD_MAIL_SUBJECT`, `AUCTION_EXPIRED_MAIL_SUBJECT`, `AUCTION_REMOVED_MAIL_SUBJECT`, `AUCTION_WON_MAIL_SUBJECT`, `debugprofilestop`)
- Modify: `docs/compat-layer.md` (one row per new shim)
- Test: `tests/test_compat.lua`, `tests/test_util.lua` (append)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `NS.Compat.HookSecure(globalName, fn) -> boolean`; `NS.Compat.HookSecureMember(tbl, member, fn) -> boolean` (presence-gated `hooksecurefunc`)
  - `NS.Compat.IsConsumable(itemID) -> boolean` (`C_Item.GetItemInfoInstant` classID == 0)
  - `NS.Compat.CurrencyIsAccountWide(id) -> boolean` (`GetCurrencyInfo(id).isAccountWide`)
  - `NS.Compat.CurrencySourceName(gainSource, destroyReason, change) -> enumMemberName|nil` (reverse lookup in `Enum.CurrencySource` when `change > 0`, `Enum.CurrencyDestroyReason` when `< 0`)
  - `NS.Compat.ScanInbox() -> counts {[itemID]=n}, links {[itemID]=link}`
  - `NS.Compat.ReadSendMail() -> items {[itemID]=n}, money` (copper)
  - `NS.Compat.ScanOwnedAuctions() -> counts, links` (active auctions only)
  - `NS.Compat.ItemLocationID(itemLocation) -> itemID|nil`
  - `NS.Compat.AuctionMailKind(subject) -> "sold"|"expired"|"cancelled"|"won"|nil, itemName|nil`
  - `NS.Compat.TradeTargetKey() -> "Name-Realm"|nil`
  - `NS.Compat.LatestCurrencyTransfer() -> { currencyID, quantity, toKey }|nil`
  - `NS.Util.ParseSelfMoney(msg) -> copper|nil`
  - Mock seams on `T.mocks`: `__inbox = { {items = { {itemID=, count=, link=} }, money=, subject=} }`, `__sendMail = { items = { [slot] = {itemID=, count=, link=} }, money = }`, `__ownedAuctions = { {itemID=, quantity=, link=, status=0|1} }`, `__currencyAccountWide = {[id]=true}`, `__currencyTransfers = { {...} }`, `__tradeTarget`, `Enum.CurrencySource`, `Enum.CurrencyDestroyReason`, `Enum.AuctionStatus`, money global strings, AH mail subjects.

- [ ] **Step 1: Write the failing tests** — append to `tests/test_compat.lua`:

```lua
test("Compat: IsConsumable reads the item class", function()
  local m = T.mocks
  m.__itemClassID = 0; assertTrue(NS.Compat.IsConsumable(211296))
  m.__itemClassID = 4; assertFalse(NS.Compat.IsConsumable(211296))
  m.__itemClassID = 0
end)

test("Compat: account-wide currency and currency-source names", function()
  local m = T.mocks
  m.__currencyAccountWide = { [2032] = true }
  assertTrue(NS.Compat.CurrencyIsAccountWide(2032))
  assertFalse(NS.Compat.CurrencyIsAccountWide(3008))
  assertEqual(NS.Compat.CurrencySourceName(m.Enum.CurrencySource.Vendor, nil, 5), "Vendor")
  assertEqual(NS.Compat.CurrencySourceName(nil, m.Enum.CurrencyDestroyReason.AccountTransfer, -5), "AccountTransfer")
  assertEqual(NS.Compat.CurrencySourceName(nil, nil, 5), nil)
end)

test("Compat: inbox scan sums attachments by itemID", function()
  local m = T.mocks
  m.__inbox = {
    { items = { { itemID = 9, count = 2, link = "L9" }, { itemID = 9, count = 1, link = "L9" } } },
    { items = { { itemID = 4, count = 5, link = "L4" } } },
  }
  local c, l = NS.Compat.ScanInbox()
  assertEqual(c[9], 3); assertEqual(c[4], 5); assertEqual(l[4], "L4")
  m.__inbox = {}
end)

test("Compat: send-mail read returns attachments and money", function()
  local m = T.mocks
  m.__sendMail = { items = { [1] = { itemID = 7, count = 3, link = "L7" } }, money = 5000 }
  local items, money = NS.Compat.ReadSendMail()
  assertEqual(items[7], 3); assertEqual(money, 5000)
  m.__sendMail = { items = {}, money = 0 }
end)

test("Compat: owned auctions count only active ones", function()
  local m = T.mocks
  m.__ownedAuctions = {
    { itemID = 3, quantity = 2, link = "L3", status = 0 },
    { itemID = 3, quantity = 1, link = "L3", status = 1 },
  }
  local c = NS.Compat.ScanOwnedAuctions()
  assertEqual(c[3], 2)
  m.__ownedAuctions = {}
end)

test("Compat: AuctionMailKind parses the localized subjects", function()
  assertEqual((NS.Compat.AuctionMailKind("Auction successful: Herb")), "sold")
  local kind, name = NS.Compat.AuctionMailKind("Auction expired: Herb")
  assertEqual(kind, "expired"); assertEqual(name, "Herb")
  assertEqual(NS.Compat.AuctionMailKind("Hello"), nil)
end)

test("Compat: TradeTargetKey appends the player's realm when missing", function()
  T.mocks.__tradeTarget = "Alt"
  assertEqual(NS.Compat.TradeTargetKey(), "Alt-Realm")
  T.mocks.__tradeTarget = nil
  assertEqual(NS.Compat.TradeTargetKey(), nil)
end)

test("Compat: HookSecure is presence-gated", function()
  local m = T.mocks
  local savedHook = m.hooksecurefunc
  local hooked = {}
  m.hooksecurefunc = function(a, b) hooked[#hooked + 1] = type(a) == "table" and b or a end
  -- HookSecure resolves the target BY NAME through _G (as hooksecurefunc itself does), and the
  -- loader env only falls through to _G after the mocks, so the stub goes on _G (core/Compat.lua's
  -- IsAuctionHouseMail global-string lookup is exercised the same way).
  rawset(_G, "RepairAllItems", function() end)
  assertTrue(NS.Compat.HookSecure("RepairAllItems", function() end))
  assertFalse(NS.Compat.HookSecure("NoSuchFunction", function() end))
  assertTrue(NS.Compat.HookSecureMember(m.C_AuctionHouse, "PostItem", function() end))
  assertEqual(table.concat(hooked, ","), "RepairAllItems,PostItem")
  m.hooksecurefunc = savedHook
  rawset(_G, "RepairAllItems", nil)
end)
```

Append to `tests/test_util.lua`:

```lua
test("Util: ParseSelfMoney reads looted and shared money", function()
  assertEqual(NS.Util.ParseSelfMoney("You loot 1 Gold, 2 Silver, 3 Copper"), 10203)
  assertEqual(NS.Util.ParseSelfMoney("You loot 45 Copper"), 45)
  assertEqual(NS.Util.ParseSelfMoney("Your share of the loot is 2 Silver."), 200)
  assertEqual(NS.Util.ParseSelfMoney("Bob loots 3 Gold"), nil)
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -E "FAIL.*(Compat|Util)" | head -20`
Expected: FAIL — the shims and the parser are nil.

- [ ] **Step 3: Implement the mock** — `tests/wow_mock.lua`, before `return M`:

```lua
  -- ── ledger capture (timeline ledger P2) ────────────────────────────────────
  M.Enum = M.Enum or {}
  -- Member names as the 12.x client ships them (as recalled; verified by smoke LED-P2-14). The
  -- numbers are arbitrary here on purpose: the addon reverse-looks-up by NAME.
  M.Enum.CurrencySource = { Loot = 0, QuestReward = 1, Vendor = 3, Trade = 4, ItemRefund = 5, AccountTransfer = 50 }
  M.Enum.CurrencyDestroyReason = { Vendor = 3, Trade = 4, Spell = 1, FulfillCraftingOrder = 9,
    ConcentrationCast = 12, AccountTransfer = 13 }
  M.Enum.AuctionStatus = { Active = 0, Sold = 1 }
  M.Enum.PlayerInteractionType = M.Enum.PlayerInteractionType or {}
  M.Enum.PlayerInteractionType.Trainer = 7
  M.Enum.PlayerInteractionType.TaxiNode = 2
  M.__currencyAccountWide = {}
  local baseGetCurrencyInfo = M.C_CurrencyInfo.GetCurrencyInfo
  M.C_CurrencyInfo.GetCurrencyInfo = function(id)
    local info = baseGetCurrencyInfo(id) or { name = "currency " .. id, quantity = 0 }
    info.isAccountWide = M.__currencyAccountWide[id] or false
    return info
  end
  M.__currencyTransfers = {}
  M.C_CurrencyInfo.FetchCurrencyTransferTransactions = function() return M.__currencyTransfers end

  M.ATTACHMENTS_MAX_RECEIVE, M.ATTACHMENTS_MAX_SEND = 16, 12
  M.__inbox = {}
  M.GetInboxNumItems = function() return #M.__inbox end
  M.GetInboxItem = function(i, a)
    local att = M.__inbox[i] and M.__inbox[i].items and M.__inbox[i].items[a]
    if not att then return nil end
    return "name", att.itemID, nil, att.count
  end
  M.GetInboxItemLink = function(i, a)
    local att = M.__inbox[i] and M.__inbox[i].items and M.__inbox[i].items[a]
    return att and att.link
  end
  M.__sendMail = { items = {}, money = 0 }
  M.GetSendMailItem = function(slot)
    local it = M.__sendMail.items[slot]
    if not it then return nil end
    return "name", it.itemID, nil, it.count
  end
  M.GetSendMailItemLink = function(slot) local it = M.__sendMail.items[slot]; return it and it.link end
  M.GetSendMailMoney = function() return M.__sendMail.money or 0 end

  M.__ownedAuctions = {}
  M.C_AuctionHouse = {
    GetNumOwnedAuctions = function() return #M.__ownedAuctions end,
    GetOwnedAuctionInfo = function(i)
      local a = M.__ownedAuctions[i]
      if not a then return nil end
      return { itemKey = { itemID = a.itemID }, itemLink = a.link, quantity = a.quantity, status = a.status }
    end,
    PostItem = function() end, PostCommodity = function() end,
    PlaceBid = function() end, ConfirmCommoditiesPurchase = function() end,
  }
  M.C_Item.GetItemID = function(loc) return loc and loc.__itemID end
  M.C_TradeSkillUI = { CraftRecipe = function() end, CraftSalvage = function() end, CraftEnchant = function() end }

  M.__tradeTarget = nil
  local baseUnitName = M.UnitName
  M.UnitName = function(unit)
    if unit == "NPC" then return M.__tradeTarget end
    return baseUnitName(unit)
  end

  M.YOU_LOOT_MONEY = "You loot %s"
  M.LOOT_MONEY_SPLIT = "Your share of the loot is %s."
  M.YOU_LOOT_MONEY_GUILD = "You loot %s (%s deposited to guild bank)"
  M.GOLD_AMOUNT, M.SILVER_AMOUNT, M.COPPER_AMOUNT = "%d Gold", "%d Silver", "%d Copper"
  M.AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
  M.AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
  M.AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"
  M.AUCTION_WON_MAIL_SUBJECT = "Auction won: %s"
```

> Reuse the Phase 1 mock's `M.Enum` table (it already holds `BagIndex`, `BankType`, `PlayerInteractionType`); the lines above only add members.

- [ ] **Step 4: Implement Compat** — `core/Compat.lua`, append:

```lua
-- ── Ledger capture (timeline ledger Phase 2) ─────────────────────────────────────────────────

-- hooksecurefunc, presence-gated. A missing target (renamed between builds, absent on a flavor)
-- returns false and installs nothing; the hook BODY must gate itself on NS.IsStoodDown (there is
-- no un-hook — slash-commands-§7's carve-out).
function Compat.HookSecure(name, fn)
  if type(hooksecurefunc) ~= "function" or type(_G[name]) ~= "function" then return false end
  hooksecurefunc(name, fn)
  return true
end

function Compat.HookSecureMember(tbl, member, fn)
  if type(hooksecurefunc) ~= "function" or type(tbl) ~= "table" or type(tbl[member]) ~= "function" then
    return false
  end
  hooksecurefunc(tbl, member, fn)
  return true
end

-- Consumable = Enum.ItemClass.Consumable (0), locale-independent.
function Compat.IsConsumable(itemID)
  local fn = C_Item and C_Item.GetItemInfoInstant
  if not (fn and itemID) then return false end
  local classID = select(6, fn(itemID))
  return classID == 0
end

function Compat.CurrencyIsAccountWide(id)
  local fn = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo
  local info = fn and fn(id)
  return info ~= nil and info.isAccountWide == true
end

local function enumName(enum, value)
  if type(enum) ~= "table" or value == nil then return nil end
  for name, v in pairs(enum) do if v == value then return name end end
  return nil
end

-- CURRENCY_DISPLAY_UPDATE's 4th/5th args, as the Enum MEMBER NAME (C.CURRENCY_SOURCE_REASON keys).
function Compat.CurrencySourceName(gainSource, destroyReason, change)
  local E = Enum or {}
  if (change or 0) > 0 then return enumName(E.CurrencySource, gainSource) end
  if (change or 0) < 0 then return enumName(E.CurrencyDestroyReason, destroyReason) end
  return nil
end

local function addCount(counts, links, id, n, link)
  if not id or not n or n <= 0 then return end
  counts[id] = (counts[id] or 0) + n
  if link and not links[id] then links[id] = link end
end

-- Every attachment in the inbox the client has loaded (readable only while the mailbox is open).
function Compat.ScanInbox()
  local counts, links = {}, {}
  if type(GetInboxNumItems) ~= "function" or type(GetInboxItem) ~= "function" then return counts, links end
  local maxA = ATTACHMENTS_MAX_RECEIVE or 16
  for i = 1, (GetInboxNumItems() or 0) do
    for a = 1, maxA do
      local _, itemID, _, count = GetInboxItem(i, a)
      if itemID then
        addCount(counts, links, itemID, count or 1, type(GetInboxItemLink) == "function" and GetInboxItemLink(i, a) or nil)
      end
    end
  end
  return counts, links
end

-- What is staged in the Send Mail frame right now (read from the SendMail post-hook).
function Compat.ReadSendMail()
  local items = {}
  if type(GetSendMailItem) == "function" then
    for slot = 1, (ATTACHMENTS_MAX_SEND or 12) do
      local _, itemID, _, count = GetSendMailItem(slot)
      if itemID then items[itemID] = (items[itemID] or 0) + (count or 1) end
    end
  end
  local money = type(GetSendMailMoney) == "function" and (GetSendMailMoney() or 0) or 0
  return items, money
end

-- Active owned auctions (sold-but-uncollected ones have left the player's escrow already).
function Compat.ScanOwnedAuctions()
  local counts, links = {}, {}
  local AH = C_AuctionHouse
  if not (AH and AH.GetNumOwnedAuctions and AH.GetOwnedAuctionInfo) then return counts, links end
  local active = (Enum and Enum.AuctionStatus and Enum.AuctionStatus.Active) or 0
  for i = 1, (AH.GetNumOwnedAuctions() or 0) do
    local a = AH.GetOwnedAuctionInfo(i)
    if a and a.status == active and a.itemKey then
      addCount(counts, links, a.itemKey.itemID, a.quantity or 1, a.itemLink)
    end
  end
  return counts, links
end

function Compat.ItemLocationID(loc)
  local fn = C_Item and C_Item.GetItemID
  return (fn and loc) and fn(loc) or nil
end

-- Auction-house mail subject -> kind, item name. Built from the localized global strings, so it
-- follows the client language (the same rule as Compat.IsAuctionHouseMail).
local AH_SUBJECTS
local function ahSubjects()
  if AH_SUBJECTS then return AH_SUBJECTS end
  AH_SUBJECTS = {}
  for kind, g in pairs({ sold = AUCTION_SOLD_MAIL_SUBJECT, expired = AUCTION_EXPIRED_MAIL_SUBJECT,
                         cancelled = AUCTION_REMOVED_MAIL_SUBJECT, won = AUCTION_WON_MAIL_SUBJECT }) do
    if type(g) == "string" then
      local p = g:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1"):gsub("%%%%s", "(.+)")
      AH_SUBJECTS[#AH_SUBJECTS + 1] = { kind = kind, pattern = "^" .. p .. "$" }
    end
  end
  return AH_SUBJECTS
end

function Compat.AuctionMailKind(subject)
  if type(subject) ~= "string" then return nil end
  for _, s in ipairs(ahSubjects()) do
    local name = subject:match(s.pattern)
    if name then return s.kind, name end
  end
  return nil
end

-- The trade partner as a holder key. UnitName("NPC") is the open trade's other party.
function Compat.TradeTargetKey()
  if type(UnitName) ~= "function" then return nil end
  local name, realm = UnitName("NPC")
  if not name or name == "" then return nil end
  if name:find("-", 1, true) then return name end
  realm = (realm and realm ~= "") and realm
    or (type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName()) or nil
  return realm and (name .. "-" .. realm) or name
end

-- The newest warband currency transfer this character made (CURRENCY_TRANSFER_LOG_UPDATE). Field
-- names are the 11.x CurrencyTransferTransaction shape as recalled; smoke LED-P2-13 verifies them.
function Compat.LatestCurrencyTransfer()
  local fn = C_CurrencyInfo and C_CurrencyInfo.FetchCurrencyTransferTransactions
  local list = fn and fn()
  if type(list) ~= "table" or #list == 0 then return nil end
  local t = list[#list]
  local to = t.destinationCharacterName
  if to and not to:find("-", 1, true) and type(GetNormalizedRealmName) == "function" then
    to = to .. "-" .. (GetNormalizedRealmName() or "")
  end
  return { currencyID = t.currencyType, quantity = t.quantityTransferred, toKey = to }
end
```

`core/Util.lua` — append (reuses the file's `toLootPattern`):

```lua
-- CHAT_MSG_MONEY (timeline-ledger spec §5.4 "Gold gains"): the player's own looted money and their
-- party share. The money text is the localized "1 Gold, 2 Silver, 3 Copper" built from
-- GOLD_AMOUNT / SILVER_AMOUNT / COPPER_AMOUNT, any part omitted when zero.
local moneyPatterns, coinPatterns
function Util.BuildMoneyPatterns()
  moneyPatterns, coinPatterns = {}, {}
  for _, g in ipairs({ YOU_LOOT_MONEY_GUILD, LOOT_MONEY_SPLIT, YOU_LOOT_MONEY }) do
    if type(g) == "string" then moneyPatterns[#moneyPatterns + 1] = toLootPattern(g) end
  end
  for mult, g in pairs({ [10000] = GOLD_AMOUNT, [100] = SILVER_AMOUNT, [1] = COPPER_AMOUNT }) do
    if type(g) == "string" then
      local p = g:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1"):gsub("%%%%d", "(%%d+)")
      coinPatterns[#coinPatterns + 1] = { pattern = p, mult = mult }
    end
  end
end

function Util.ParseSelfMoney(msg)
  if not msg then return nil end
  if not moneyPatterns then Util.BuildMoneyPatterns() end
  for _, p in ipairs(moneyPatterns) do
    local text = msg:match(p)
    if text then
      local copper = 0
      for _, c in ipairs(coinPatterns) do
        local n = text:match(c.pattern)
        if n then copper = copper + tonumber(n) * c.mult end
      end
      return copper > 0 and copper or nil
    end
  end
  return nil
end
```

> `toLootPattern` turns the guild variant's second `%s` into a second capture; `msg:match(p)` returns the first (the money text), which is what is wanted. The guild variant is listed first because `YOU_LOOT_MONEY`'s greedy `(.+)` would otherwise swallow its parenthetical.

Add the missing names to `.luacheckrc` `read_globals` and one row per shim to `docs/compat-layer.md` (Wraps / Why, the neighbors' voice).

- [ ] **Step 5: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS, 0/0.

- [ ] **Step 6: Commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add core/Compat.lua core/Util.lua tests/wow_mock.lua tests/test_compat.lua tests/test_util.lua .luacheckrc docs/compat-layer.md docs/test-cases.md
git commit -m "feat(compat): mail, auction, consumable, currency-source and money-line reads for the ledger" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt"
```

---

### Task 6: Outbound attribution — stamps, frame scopes, hooks (`modules/AttributionOut.lua`)

**Files:**
- Create: `modules/AttributionOut.lua`
- Modify: `core/State.lua` (declare `outContext`, `scopes`, `pendingMail`, `pendingPost`, `craftUntil`, `soldMail`, `tradeTarget`)
- Modify: `core/Util.lua` (append `Util.QualifyName`)
- Modify: `core/LifecycleSetup.lua` (`StandUp`: `NS.Attribution:EnableOut()` after `Attribution:Enable`; `StandDown`: call `NS.Attribution:DisableOut()` after the module loop)
- Modify: `LootHistory.toc` (`modules\AttributionOut.lua` directly after `modules\Attribution.lua`)
- Modify: `tests/test_disabled.lua` (`featureTargets` list ~line 107: add `NS.Attribution.__outEv`)
- Create: `tests/test_attribution_out.lua`; register `"test_attribution_out"` after `"test_attribution"` in `tests/run.lua`

**Interfaces:**
- Consumes: `NS.Compat.HookSecure/HookSecureMember/ReadSendMail/ItemLocationID/AuctionMailKind/TradeTargetKey/GetMailHeader/InteractionType` (Task 5 + existing), `NS.Holdings:Get` (Phase 1), `NS.Constants.CONTEXT_TTL`, `NS.Constants.CRAFT_TTL` (Task 1), `NS.SafeRegisterEvent`, `NS.NewBusTarget`, `NS.IsStoodDown`.
- Produces (on `NS.Attribution`):
  - `:StampOut(reason, opts, trigger)` — `opts = { ttl, dirs = {IN|OUT|MOVE=true}, kinds = {ITEM|CURRENCY|GOLD=true} }`; writes `NS.State.outContext = { reason, expires, dirs, kinds }`; ignored while stood down.
  - `:SetScope(name, on)`; `NS.State.scopes` keys `merchant, trainer, taxi, mailbox, auction, bank, guildBank`.
  - `:OnInteraction(shown, interactionType)` (routes `PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE`).
  - `:ReasonContext(clock) -> ctx` (one reused table; shape of `Ledger.PickReason`'s `ctx`; `forced/consumable/currencySrc` reset to nil each call).
  - `:OnSendMail(recipient)`, `:OnMailSent()`, `:OnMailFailed()`; `NS.State.pendingMail = { to = holderKey|nil, items = {[id]=n}, money, sent = bool, expires }`.
  - `:OnPost(itemLocation, quantity)`; `NS.State.pendingPost = {[itemID]=n}`.
  - `:OnTakeInboxMoney(index)`; `NS.State.soldMail = { itemName, expires }`.
  - `:OnTradeAccept(playerAccepted, targetAccepted)`; `NS.State.tradeTarget`.
  - `:OnCraft()`; `NS.State.craftUntil`.
  - `:HookGuildBankFrame() -> boolean`.
  - `:EnableOut()` / `:DisableOut()`; private target `NS.Attribution.__outEv`; hooks installed once (`_outHooked`).
  - `NS.Util.QualifyName(name) -> "Name-Realm"`.

- [ ] **Step 1: Write the failing test** — `tests/test_attribution_out.lua`

```lua
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local A = function() return NS.Attribution end
local S = function() return NS.State end

local function reset()
  T.mocks.__now = 100
  local st = S()
  st.outContext, st.pendingMail, st.pendingPost, st.soldMail, st.tradeTarget, st.craftUntil = nil, nil, {}, nil, nil, nil
  for k in pairs(st.scopes) do st.scopes[k] = nil end
end

test("AttributionOut: StampOut writes the outbound slot with TTL and filters", function()
  reset()
  A():StampOut("REPAIR", { kinds = { GOLD = true }, dirs = { OUT = true } })
  local o = S().outContext
  assertEqual(o.reason, "REPAIR"); assertEqual(o.expires, 100 + NS.Constants.CONTEXT_TTL)
  assertTrue(o.kinds.GOLD); assertTrue(o.dirs.OUT)
  assertEqual(S().lootContext == o, false)          -- never the inbound slot
end)

test("AttributionOut: interaction show/hide toggles scopes", function()
  reset()
  local M = NS.Compat.InteractionType
  A():OnInteraction(true, M("Merchant"));  assertTrue(S().scopes.merchant)
  A():OnInteraction(true, M("Trainer"));   assertTrue(S().scopes.trainer)
  A():OnInteraction(false, M("Merchant")); assertEqual(S().scopes.merchant, nil)
  A():OnInteraction(true, M("MailInfo"));  assertTrue(S().scopes.mailbox)
end)

test("AttributionOut: ReasonContext exposes both slots and the scopes, resetting per-call fields", function()
  reset()
  NS.Attribution:Stamp("KILL", nil, "CERTAIN")
  A():StampOut("DESTROY", { kinds = { ITEM = true } })
  local c = A():ReasonContext(101)
  assertEqual(c.now, 101); assertEqual(c.loot.source, "KILL"); assertEqual(c.out.reason, "DESTROY")
  c.forced, c.consumable = "UNTRACKED", true
  c = A():ReasonContext(102)
  assertEqual(c.forced, nil); assertEqual(c.consumable, nil)
end)

test("AttributionOut: SendMail to an own alt resolves the holder and stages attachments", function()
  reset()
  NS.db.global.holdings = { ["Alt-Realm"] = { meta = {}, scanned = {}, items = {}, currency = {}, links = {} } }
  T.mocks.__sendMail = { items = { [1] = { itemID = 7, count = 3 } }, money = 500 }
  A():OnSendMail("Alt")
  local p = S().pendingMail
  assertEqual(p.to, "Alt-Realm"); assertEqual(p.items[7], 3); assertEqual(p.money, 500)
  assertFalse(p.sent)
  A():OnMailSent()
  assertTrue(S().pendingMail.sent)
  assertEqual(S().outContext.reason, "MAIL_SEND")
  T.mocks.__sendMail = { items = {}, money = 0 }
end)

test("AttributionOut: SendMail to a stranger leaves `to` nil", function()
  reset()
  NS.db.global.holdings = {}
  A():OnSendMail("Stranger-Otherrealm")
  assertEqual(S().pendingMail.to, nil)
end)

test("AttributionOut: posting records the item in flight and stamps the deposit", function()
  reset()
  A():OnPost({ __itemID = 3 }, 2)
  A():OnPost({ __itemID = 3 }, 1)
  assertEqual(S().pendingPost[3], 3)
  assertEqual(S().outContext.reason, "AH_POST_FEE")
  assertTrue(S().outContext.kinds.GOLD)
end)

test("AttributionOut: taking AH sale money stamps AH_SOLD and names the item", function()
  reset()
  local saved = T.mocks.GetInboxHeaderInfo
  T.mocks.GetInboxHeaderInfo = function() return nil, nil, "Auction House", "Auction successful: Herb" end
  A():OnTakeInboxMoney(1)
  assertEqual(S().outContext.reason, "AH_SOLD"); assertTrue(S().outContext.dirs.IN)
  assertEqual(S().soldMail.itemName, "Herb")
  T.mocks.GetInboxHeaderInfo = saved
end)

test("AttributionOut: a completed trade stamps TRADE_GIVE and records the partner", function()
  reset()
  T.mocks.__tradeTarget = "Bob"
  A():OnTradeAccept(1, 0); assertEqual(S().outContext, nil)
  A():OnTradeAccept(1, 1)
  assertEqual(S().outContext.reason, "TRADE_GIVE"); assertEqual(S().tradeTarget, "Bob-Realm")
  T.mocks.__tradeTarget = nil
end)

test("AttributionOut: a craft arms the reagent window", function()
  reset()
  A():OnCraft()
  assertEqual(S().craftUntil, 100 + NS.Constants.CRAFT_TTL)
end)

test("AttributionOut: guild bank frame OnShow/OnHide drive the guildBank scope", function()
  reset()
  local scripts = {}
  local frame = { HookScript = function(_, what, fn) scripts[what] = fn end }
  rawset(_G, "GuildBankFrame", frame)
  A()._guildHooked = nil
  assertTrue(A():HookGuildBankFrame())
  scripts.OnShow(); assertTrue(S().scopes.guildBank)
  scripts.OnHide(); assertEqual(S().scopes.guildBank, nil)
  assertTrue(A():HookGuildBankFrame())           -- idempotent, no second hook
  rawset(_G, "GuildBankFrame", nil)
end)

test("AttributionOut: stood down, stamps and scopes are ignored", function()
  reset()
  local saved = NS.IsStoodDown
  NS.IsStoodDown = function() return true end
  A():StampOut("DESTROY")
  A():OnCraft()
  assertEqual(S().outContext, nil); assertEqual(S().craftUntil, nil)
  NS.IsStoodDown = saved
end)

test("AttributionOut: EnableOut registers on a private target; DisableOut unregisters and clears", function()
  reset()
  A():EnableOut()
  local ev = A().__outEv
  assertTrue(ev ~= nil and ev ~= NS.addon)
  assertTrue(ev.__events.PLAYER_INTERACTION_MANAGER_FRAME_SHOW ~= nil)
  assertTrue(ev.__events.MAIL_SEND_SUCCESS ~= nil)
  S().scopes.merchant = true
  A():DisableOut()
  assertEqual(A().__outEv, nil)
  assertEqual(next(ev.__events), nil)
  assertEqual(S().scopes.merchant, nil)
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -A2 "AttributionOut:" | head -20`
Expected: FAIL — `StampOut` nil.

- [ ] **Step 3: Implement**

`core/State.lua` — append:

```lua
-- Outbound (loss-side) context for the ledger (timeline-ledger spec §5.4). A SECOND single slot
-- beside lootContext, same TTL engine: one BuyMerchantItem must stamp an inbound VENDOR for the
-- item AND an outbound BUY for the gold, and one slot would let either clobber the other.
-- Shape: { reason, expires, dirs = {IN|OUT|MOVE=true}|nil, kinds = {ITEM|CURRENCY|GOLD=true}|nil }
State.outContext = nil
State.scopes = {}          -- open interaction frames: merchant/trainer/taxi/mailbox/auction/bank/guildBank
State.pendingMail = nil    -- { to, items, money, sent, expires } staged by the SendMail hook
State.pendingPost = {}     -- [itemID] = qty posted to the auction house, not yet seen in `auctions`
State.craftUntil = nil     -- GetTime() until which item losses read as CRAFT_REAGENT
State.soldMail = nil       -- { itemName, expires } from taking an "Auction successful" mail's money
State.tradeTarget = nil    -- holder key of the last completed trade's partner
```

`core/Util.lua` — append:

```lua
-- "Name" or "Name-Realm" -> "Name-Realm" on the player's own (normalized) realm. Mail recipients and
-- trade partners are typed or shown without a realm when they share the player's.
function Util.QualifyName(name)
  if not name or name == "" then return nil end
  if name:find("-", 1, true) then return (name:gsub("%s+", "")) end
  local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
  return name .. "-" .. tostring(realm):gsub("%s+", "")
end
```

`modules/AttributionOut.lua`:

```lua
local _, NS = ...
NS.Attribution = NS.Attribution or {}
local Attribution = NS.Attribution

-- The LOSS side of attribution (timeline-ledger spec §5.4): where modules/Attribution.lua stamps
-- why something ARRIVED, this file stamps why something LEFT, and which interaction frame is open.
-- The Reconciler reads both through Attribution:ReasonContext when it writes a diff row.
--
-- Its own file and its own private bus target (`__outEv`), so Attribution:Enable's registration set
-- (pinned in tests/test_attribution.lua) is unchanged and this half tears down on its own.

local State = NS.State
local C = NS.Constants

local function stoodDown() return NS.IsStoodDown and NS.IsStoodDown() end

-- PLAYER_INTERACTION_MANAGER_FRAME_* type name -> scope key.
local SCOPE_OF = {
  Merchant = "merchant", Trainer = "trainer", TaxiNode = "taxi", MailInfo = "mailbox",
  Auctioneer = "auction", Banker = "bank", AccountBanker = "bank", GuildBanker = "guildBank",
}

function Attribution:StampOut(reason, opts, trigger)
  -- The hooksecurefunc carve-out (slash-commands-§7): every hook below lands here or in one of the
  -- On* bodies, each of which checks the latch first, because a hook has no un-hook.
  if stoodDown() then return end
  State.outContext = {
    reason = reason,
    expires = GetTime() + ((opts and opts.ttl) or C.CONTEXT_TTL),
    dirs = opts and opts.dirs, kinds = opts and opts.kinds,
  }
  if NS.State.debug and NS.Debug then
    NS.Debug("Attr", "stamp-out %s%s", reason, trigger and (" via " .. trigger) or "")
  end
end

function Attribution:SetScope(name, on)
  if on then State.scopes[name] = true else State.scopes[name] = nil end
end

function Attribution:OnInteraction(shown, interactionType)
  for name, scope in pairs(SCOPE_OF) do
    if interactionType ~= nil and interactionType == NS.Compat.InteractionType(name) then
      self:SetScope(scope, shown)
      if NS.State.debug and NS.Debug then NS.Debug("Attr", "scope %s %s", scope, shown and "open" or "closed") end
    end
  end
end

-- One table, refilled per call: ReasonContext runs once per written row, out of combat.
local ctx = {}
function Attribution:ReasonContext(clock)
  ctx.now = clock
  ctx.out, ctx.loot, ctx.scopes, ctx.craftUntil = State.outContext, State.lootContext, State.scopes, State.craftUntil
  ctx.forced, ctx.consumable, ctx.currencySrc = nil, nil, nil
  return ctx
end

-- ── Hook bodies ─────────────────────────────────────────────────────────────────────────────

-- SendMail is a POST-hook: the attachments are still staged in the Send Mail frame when it runs
-- (verified by smoke LED-P2-06). The bags only change on MAIL_SEND_SUCCESS.
function Attribution:OnSendMail(recipient)
  if stoodDown() then return end
  local items, money = NS.Compat.ReadSendMail()
  local key = NS.Util.QualifyName(recipient)
  local own = key and key ~= NS.Util.PlayerKey() and NS.Holdings and NS.Holdings:Get(key) ~= nil
  State.pendingMail = { to = own and key or nil, items = items, money = money, sent = false, expires = GetTime() + 30 }
  self:StampOut("MAIL_SEND", { dirs = { OUT = true }, ttl = 30 }, "SendMail")
end

function Attribution:OnMailSent()
  local p = State.pendingMail
  if not p or stoodDown() then return end
  p.sent, p.expires = true, GetTime() + 10
  self:StampOut("MAIL_SEND", { dirs = { OUT = true } }, "MAIL_SEND_SUCCESS")
end

function Attribution:OnMailFailed() State.pendingMail = nil end

function Attribution:OnPost(itemLocation, quantity)
  if stoodDown() then return end
  local id = NS.Compat.ItemLocationID(itemLocation)
  if id then State.pendingPost[id] = (State.pendingPost[id] or 0) + (quantity or 1) end
  self:StampOut("AH_POST_FEE", { kinds = { GOLD = true }, dirs = { OUT = true }, ttl = 5 }, "PostAuction")
end

function Attribution:OnAuctionBuy()
  self:StampOut("AH_BUY", { kinds = { GOLD = true }, dirs = { OUT = true }, ttl = 5 }, "AuctionBuy")
end

function Attribution:OnTakeInboxMoney(index)
  if stoodDown() then return end
  local _, subject = NS.Compat.GetMailHeader(index)
  local kind, itemName = NS.Compat.AuctionMailKind(subject)
  if kind == "sold" then
    State.soldMail = { itemName = itemName, expires = GetTime() + 10 }
    self:StampOut("AH_SOLD", { kinds = { GOLD = true }, dirs = { IN = true } }, "TakeInboxMoney")
  end
end

function Attribution:OnTradeAccept(playerAccepted, targetAccepted)
  if playerAccepted == 1 and targetAccepted == 1 then
    State.tradeTarget = NS.Compat.TradeTargetKey()
    self:StampOut("TRADE_GIVE", { dirs = { OUT = true } }, "trade-complete")
  end
end

function Attribution:OnCraft()
  if stoodDown() then return end
  State.craftUntil = GetTime() + C.CRAFT_TTL
end

-- Guild bank open/close: GuildBankFrame's own OnShow/OnHide (BankLedger: GUILDBANKFRAME_* never
-- fire on 12.x). The frame is load-on-demand, so this runs again on ADDON_LOADED and is idempotent.
function Attribution:HookGuildBankFrame()
  if self._guildHooked then return true end
  local frame = _G.GuildBankFrame
  if not (frame and type(frame.HookScript) == "function") then return false end
  self._guildHooked = true
  frame:HookScript("OnShow", function() if not stoodDown() then Attribution:SetScope("guildBank", true) end end)
  frame:HookScript("OnHide", function() Attribution:SetScope("guildBank", false) end)
  return true
end

-- Installed ONCE per session (hooksecurefunc has no un-hook); each body gates on the latch.
local function installHooks(self)
  if self._outHooked then return end
  self._outHooked = true
  local H, HM = NS.Compat.HookSecure, NS.Compat.HookSecureMember
  H("RepairAllItems", function() self:StampOut("REPAIR", { kinds = { GOLD = true }, dirs = { OUT = true } }, "RepairAllItems") end)
  H("BuyMerchantItem", function() self:StampOut("BUY", { dirs = { OUT = true } }, "BuyMerchantItem") end)
  H("BuybackItem", function() self:StampOut("BUY", { dirs = { OUT = true } }, "BuybackItem") end)
  H("DeleteCursorItem", function() self:StampOut("DESTROY", { kinds = { ITEM = true }, dirs = { OUT = true } }, "DeleteCursorItem") end)
  H("SendMail", function(recipient) self:OnSendMail(recipient) end)
  H("TakeInboxMoney", function(index) self:OnTakeInboxMoney(index) end)
  local AH = C_AuctionHouse
  HM(AH, "PostItem", function(loc, _, qty) self:OnPost(loc, qty) end)
  HM(AH, "PostCommodity", function(loc, _, qty) self:OnPost(loc, qty) end)
  HM(AH, "PlaceBid", function() self:OnAuctionBuy() end)
  HM(AH, "ConfirmCommoditiesPurchase", function() self:OnAuctionBuy() end)
  local TS = C_TradeSkillUI
  HM(TS, "CraftRecipe", function() self:OnCraft() end)
  HM(TS, "CraftSalvage", function() self:OnCraft() end)
  HM(TS, "CraftEnchant", function() self:OnCraft() end)
end

function Attribution:EnableOut()
  if self.__outEv then return end
  installHooks(self)
  self:HookGuildBankFrame()
  local ev = NS.NewBusTarget()
  self.__outEv = ev
  local function reg(event, fn) NS.SafeRegisterEvent(ev, event, fn, NS.RejectedEvents) end
  reg("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, t) self:OnInteraction(true, t) end)
  reg("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, t) self:OnInteraction(false, t) end)
  reg("MAIL_SEND_SUCCESS", function() self:OnMailSent() end)
  reg("MAIL_FAILED", function() self:OnMailFailed() end)
  reg("TRADE_ACCEPT_UPDATE", function(_, p, t) self:OnTradeAccept(p, t) end)
  reg("ADDON_LOADED", function(_, name) if name == "Blizzard_GuildBankUI" then self:HookGuildBankFrame() end end)
end

-- Stand-down: the target goes wholesale and every outbound state goes with it, so nothing stamped
-- while the addon was up attributes a change after it comes back.
function Attribution:DisableOut()
  if self.__outEv then
    self.__outEv:UnregisterAllEvents()
    self.__outEv:UnregisterAllMessages()
    self.__outEv = nil
  end
  State.outContext, State.pendingMail, State.soldMail, State.tradeTarget, State.craftUntil = nil, nil, nil, nil, nil
  for k in pairs(State.scopes) do State.scopes[k] = nil end
  for k in pairs(State.pendingPost) do State.pendingPost[k] = nil end
end
```

> `PostItem(itemLocation, duration, quantity, bid, buyout)` and `PostCommodity(itemLocation, duration, quantity, unitPrice)` — the third argument is the quantity in both (12.x signatures as recalled; smoke LED-P2-08 verifies).

`core/LifecycleSetup.lua`:
- `NS.StandUp`: after `NS.Attribution:Enable()` add `if NS.Attribution and NS.Attribution.EnableOut then NS.Attribution:EnableOut() end`.
- `NS.StandDown`: after the module loop add `if NS.Attribution and NS.Attribution.DisableOut then NS.Attribution:DisableOut() end`.

- [ ] **Step 4: Update teardown coverage** — `tests/test_disabled.lua` `featureTargets()`: add `NS.Attribution.__outEv` to the list; `OWNED`: add `"event:MAIL_SEND_SUCCESS:nil"`, `"event:MAIL_FAILED:nil"`, `"event:ADDON_LOADED:nil"` (the interaction-frame pair and `TRADE_ACCEPT_UPDATE` are already named by Phase 1 / Attribution; if `OWNED` is compared as a multiset rather than a set, add a second entry for each).

- [ ] **Step 5: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS, 0/0. If `tests/test_debug_coverage.lua` asks for a debug line per new trace tag, the `[Attr]` lines above satisfy it; if it names `AttributionOut`, add the module to its subsystem list the way `Attribution` is listed.

- [ ] **Step 6: Commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add modules/AttributionOut.lua core/State.lua core/Util.lua core/LifecycleSetup.lua LootHistory.toc tests/test_attribution_out.lua tests/test_disabled.lua tests/run.lua docs/test-cases.md
git commit -m "feat(attribution): outbound reason stamps, frame scopes and loss-side hooks" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt"
```

---

### Task 7: Reconciler — scan → plan → hold/commit, row writer, claims API, coalescing

**Files:**
- Modify: `modules/Reconciler.lua` — replace Phase 1's `local function flushPart` and `function R:Flush` with the pipeline below; extend `R:DisableCapture`; add the row writer, claims API, hold logic.
- Modify: `defaults/Profile.lua` (settings: `recordGold = true`)
- Modify: `settings/Schema.lua` (row `settings.recordGold`, General ▸ Capture, after `settings.trackLedger`)
- Create: `tests/test_reconciler_rows.lua`; register `"test_reconciler_rows"` after `"test_reconciler"` in `tests/run.lua`

**Interfaces:**
- Consumes: Phase 1 — `NS.Reconciler.dirty/readable/deferred`, `:MarkDirty`, `:OnEvent`, `:IsReadable`, `:DisableCapture`, `_enabled`; `NS.Scanner.ScanContainers/ScanEquipped/ScanCurrencies/ReadMoney/ReadWarbandMoney`; `NS.Holdings:Get/ApplyContainer/ApplyMoney/ApplyCurrency/MarkGenesis`; `NS.Constants.Container/WARBAND_HOLDER/BAG_IDS/BANK_IDS/WARBAND_TAB_IDS`; `NS.MSG.HOLDINGS_CHANGED`. This plan — `NS.Ledger.ClassifyItems/PairHolders/ClaimAvailable/ConsumeClaim/PruneClaims/CoalesceKey/Amendable/ShouldHold/PickReason/ThingKey/ParseThingKey/Diff` (Tasks 2–3), `NS.Attribution:ReasonContext` (Task 6), `NS.Database:Add/Amend` (Task 4), `NS.Compat.IsConsumable` (Task 5).
- Produces (on `NS.Reconciler`):
  - `R.SCAN_STEPS`, `R.PLAN_STEPS`, `R.COMMIT_STEPS` — arrays of `fn(self, snap|plan, me, clock[, now])`; Task 9 and Task 10 append to them.
  - `:Scan(me) -> snap` with `snap[holder] = { items = {[container] = {[itemID]=n}}, links = {}, money = copper|nil, currency = {[id]=n}|nil }` (no Holdings writes).
  - `:Plan(snap, me, clock) -> plan` with `plan = { net = {[holder] = {[thingKey]=signed}}, moves = { {holder, id, qty, from, to} }, pairs = { {key, qty, from, to, fromC?, toC?, reason?} }, arrivals = {[holder]=…}, exits = {[holder]=…} }`.
  - `:DecideHold(plan, clock) -> boolean`; `R._holdSince`.
  - `:WriteRows(plan, now, clock)`; `:Write(holder, key, dir, reason, qty, now, from, to) -> row|nil`; `:MakeRow(...) -> row`.
  - `:PostClaim(thingKey, qty, row)` — no-op unless capture is enabled. **The chat paths call this (Task 8).**
  - Flags `R.silent` (apply holdings, write nothing — genesis) and `R.forceReason` (every row gets this reason, no holds, no claims — login drift).
  - **Row shape** (every ledger row; Phase 3 relies on it): `{ ts, char, classFile, holder, dir, kind, quantity (unsigned), source (reason), confidence, zone, subzone, mapID, from?, to?, itemID?, itemLink?, itemName, quality?, itemLevel?, bound?, vendorPrice?, auctionPrice?, itemType, itemSubType?, currencyID? }`; GOLD rows: `itemName = "Gold"`, `itemType = C.GOLD_TYPE`, `quantity` in copper.
  - Setting `settings.recordGold` (bool, default true, `SETTINGS_CHANGED` reason `"ledger"`).

- [ ] **Step 1: Write the failing test** — `tests/test_reconciler_rows.lua`

```lua
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local m = T.mocks
local R = function() return NS.Reconciler end
local ME
local function H() return NS.db.global.history end

-- Every case runs on a frozen wall clock (row ts, the 60 s coalescing window) and restores the
-- shared mock on the way out whether the body passed or threw.
local function case(name, body)
  test(name, function()
    local savedTime, savedICL = m.time, m.InCombatLockdown
    local savedList, savedWide, savedXfer = m.__currencyList, m.__currencyAccountWide, m.__currencyTransfers
    m.__epoch, m.__now = 5000, 100
    m.time = function() return m.__epoch end
    local ok, err = pcall(body)
    m.time, m.InCombatLockdown = savedTime, savedICL
    m.__currencyList, m.__currencyAccountWide, m.__currencyTransfers = savedList, savedWide, savedXfer
    if not ok then error(err, 0) end
  end)
end

local function setBag(bagID, slots)
  m.__bags[bagID] = slots
  local n = 0; for s in pairs(slots) do if s > n then n = s end end
  m.__bagSlots[bagID] = n
end

local function reset()
  ME = NS.Util.PlayerKey()
  NS.db.global.history, NS.db.global.holdings = {}, {}
  m.__bags, m.__bagSlots, m.__inventory, m.__money, m.__warbandMoney = {}, {}, {}, 0, 0
  m.__itemClassID = 4                                     -- not consumable unless a case says so
  NS.db.profile.blacklist = {}
  NS.db.profile.settings.recordGold = true
  local r = R()
  r.dirty, r.readable, r.deferred, r._holdSince = {}, {}, nil, nil
  r.claims, r.recent, r.reasonMemo = {}, {}, {}
  r._enabled = true
  NS.State.outContext, NS.State.lootContext = nil, nil
  for k in pairs(NS.State.scopes) do NS.State.scopes[k] = nil end
end

-- Seed the stored baseline for the carried parts and stamp genesis, writing nothing.
local function genesis()
  for _, p in ipairs({ "bags", "equipped", "money" }) do R():MarkDirty(p) end
  R().silent = true; R():Flush(); R().silent = nil
  NS.Holdings:MarkGenesis(ME, m.__epoch)
end

local function openBank(kind)
  R():OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", NS.Compat.InteractionType(kind or "Banker"))
end

case("Reconciler: bag to bank deposit writes one MOVE and no gain or loss", function()
  reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 5 } })
  genesis()
  openBank(); setBag(6, {}); R():Flush()                  -- the bank's first scan is its own genesis
  assertEqual(#H(), 0)
  setBag(0, {}); setBag(6, { [1] = { itemID = 7, link = "L7", count = 5 } })
  R():MarkDirty("bags"); R():MarkDirty("bank"); R():Flush()
  assertEqual(#H(), 1)
  local r = H()[1]
  assertEqual(r.dir, "MOVE"); assertEqual(r.source, "TRANSFER"); assertEqual(r.quantity, 5)
  assertEqual(r.from, ME .. "/bags"); assertEqual(r.to, ME .. "/bank")
  assertEqual(r.holder, ME); assertEqual(r.kind, "ITEM"); assertEqual(r.itemID, 7)
end)

case("Reconciler: a one-sided change at an open bank is held, then paired", function()
  reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 2 } })
  genesis()
  openBank(); setBag(6, {}); R():Flush()
  setBag(0, {})                                           -- bags update first ...
  R():MarkDirty("bags"); R():Flush()
  assertEqual(#H(), 0); assertTrue(R()._holdSince ~= nil)
  m.__now = 102
  setBag(6, { [1] = { itemID = 7, link = "L7", count = 2 } })   -- ... the bank a round-trip later
  R():MarkDirty("bank"); R():Flush()
  assertEqual(#H(), 1); assertEqual(H()[1].dir, "MOVE")
  assertEqual(NS.Holdings:Get(ME).items[7].bank, 2)
end)

case("Reconciler: vendor sale writes item OUT SELL and gold IN SELL", function()
  reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 1 } }); m.__money = 1000
  genesis()
  NS.Attribution:SetScope("merchant", true)
  setBag(0, {}); m.__money = 1500
  R():MarkDirty("bags"); R():MarkDirty("money"); R():Flush()
  assertEqual(#H(), 0)                                    -- the gold gain waits for a claim
  m.__now = 102; R():Flush()
  assertEqual(#H(), 2)
  local byKind = {}
  for _, r in ipairs(H()) do byKind[r.kind] = r end
  assertEqual(byKind.ITEM.dir, "OUT"); assertEqual(byKind.ITEM.source, "SELL")
  assertEqual(byKind.GOLD.dir, "IN"); assertEqual(byKind.GOLD.source, "SELL"); assertEqual(byKind.GOLD.quantity, 500)
  assertEqual(byKind.GOLD.itemName, "Gold")
end)

case("Reconciler: combat potion burst lands as one CONSUME row and coalesces", function()
  reset()
  m.__itemClassID = 0
  setBag(0, { [1] = { itemID = 191, link = "L191", count = 10 } })
  genesis()
  local scans, base = 0, NS.Scanner.ScanContainers
  NS.Scanner.ScanContainers = function(...) scans = scans + 1; return base(...) end
  m.InCombatLockdown = function() return true end
  setBag(0, { [1] = { itemID = 191, link = "L191", count = 5 } })
  for _ = 1, 20 do R():OnEvent("BAG_UPDATE", 0); R():OnEvent("BAG_UPDATE_DELAYED") end
  R():Flush()
  assertEqual(scans, 0); assertEqual(#H(), 0)
  m.InCombatLockdown = function() return false end
  R():OnEvent("PLAYER_REGEN_ENABLED")
  assertEqual(#H(), 1)
  assertEqual(H()[1].source, "CONSUME"); assertEqual(H()[1].quantity, 5); assertEqual(H()[1].dir, "OUT")
  m.__epoch = m.__epoch + 30
  setBag(0, {})
  R():MarkDirty("bags"); R():Flush()
  assertEqual(#H(), 1); assertEqual(H()[1].quantity, 10)  -- amended, not appended
  m.__epoch = m.__epoch + 61
  NS.Scanner.ScanContainers = base
end)

case("Reconciler: rows after the 60 s window append", function()
  reset()
  m.__itemClassID = 0
  setBag(0, { [1] = { itemID = 191, link = "L191", count = 3 } })
  genesis()
  setBag(0, { [1] = { itemID = 191, link = "L191", count = 2 } }); R():MarkDirty("bags"); R():Flush()
  m.__epoch = m.__epoch + 60
  setBag(0, { [1] = { itemID = 191, link = "L191", count = 1 } }); R():MarkDirty("bags"); R():Flush()
  assertEqual(#H(), 2)
end)

case("Reconciler: a warband deposit is a MOVE pair, one row per holder", function()
  reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 2 } })
  genesis()
  openBank("AccountBanker"); setBag(12, {}); R():Flush()
  NS.Holdings:MarkGenesis(NS.Constants.WARBAND_HOLDER, m.__epoch)
  setBag(0, {}); setBag(12, { [1] = { itemID = 7, link = "L7", count = 2 } })
  R():MarkDirty("bags"); R():MarkDirty("tabs"); R():Flush()
  assertEqual(#H(), 2)
  local holders = {}
  for _, r in ipairs(H()) do
    assertEqual(r.dir, "MOVE"); assertEqual(r.from, ME .. "/bags"); assertEqual(r.to, "§warband/tabs")
    holders[r.holder] = true
  end
  assertTrue(holders[ME] and holders["§warband"])
end)

case("Reconciler: a posted claim absorbs the gain and stamps the chat row", function()
  reset()
  genesis()
  local chatRow = { itemID = 7, quantity = 3 }
  R():PostClaim("i:7", 3, chatRow)
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 3 } })
  R():MarkDirty("bags"); R():Flush()
  assertEqual(#H(), 0)
  assertTrue(chatRow.claimed); assertEqual(chatRow.dir, "IN"); assertEqual(chatRow.holder, ME)
  assertEqual(chatRow.kind, "ITEM")
end)

case("Reconciler: blacklisted items never get a row but holdings still count them", function()
  reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 4 } })
  genesis()
  NS.db.profile.blacklist = { [7] = true }
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 1 } })
  R():MarkDirty("bags"); R():Flush()
  assertEqual(#H(), 0)
  assertEqual(NS.Holdings:Get(ME).items[7].bags, 1)
end)

case("Reconciler: recordGold off suppresses gold rows only", function()
  reset()
  m.__money = 100
  genesis()
  NS.db.profile.settings.recordGold = false
  NS.Attribution:SetScope("merchant", true)
  m.__money = 50
  R():MarkDirty("money"); R():Flush()
  assertEqual(#H(), 0)
  assertEqual(NS.Holdings:Get(ME).money, 50)
end)

case("Reconciler: no genesis, no rows", function()
  reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 4 } })
  R():MarkDirty("bags"); R():Flush()
  setBag(0, {})
  R():MarkDirty("bags"); R():Flush()
  assertEqual(#H(), 0)
end)

case("Reconciler: an unexplained loss with no stamp is OTHER", function()
  reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 1 } })
  genesis()
  setBag(0, {})
  R():MarkDirty("bags"); R():Flush()
  assertEqual(H()[1].source, "OTHER"); assertEqual(H()[1].confidence, "INFERRED")
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -A2 "Reconciler:" | head -40`
Expected: FAIL — no rows written (Phase 1 Flush only updates holdings), `PostClaim` nil.

- [ ] **Step 3: Implement** — `modules/Reconciler.lua`. Delete Phase 1's `local function flushPart(...)` and `function R:Flush()`; add, below `R:OnEvent`:

```lua
-- ── Phase 2: scan -> plan -> hold or commit (timeline-ledger spec §5.1-§5.5) ─────────────────
--
-- A pass READS every dirty, readable part without touching db.global.holdings; PLANS rows against
-- the stored baseline; and either HOLDS (keeps baseline and dirty bits, looks again shortly) or
-- COMMITS (consume claims, write holdings, write rows). Holding is what lets the two halves of one
-- bank deposit, which arrive a server round-trip apart, meet in one pass (BankLedger's
-- settleBaseline), and what gives a chat line the moment it needs to claim its delta.

R.claims, R.recent, R.reasonMemo = {}, {}, {}
-- Extension points, in order. Escrow (Task 10) and currency deltas (Task 9) append to them.
R.SCAN_STEPS, R.PLAN_STEPS, R.COMMIT_STEPS = {}, {}, {}

local L = NS.Ledger

local function snapFor(snap, holder)
  local s = snap[holder]
  if not s then s = { items = {}, links = {} }; snap[holder] = s end
  return s
end

local function addLinks(dst, src) for id, l in pairs(src or {}) do if not dst[id] then dst[id] = l end end end

-- part -> whose container it is, which column, how to read it.
local CONTAINER_READS = {
  bags     = { mine = true,  c = CT.BAGS,     ids = function() return C.BAG_IDS end },
  bank     = { mine = true,  c = CT.BANK,     ids = function() return C.BANK_IDS end },
  tabs     = { mine = false, c = CT.TABS,     ids = function() return C.WARBAND_TAB_IDS end },
  equipped = { mine = true,  c = CT.EQUIPPED },
}

function R:Scan(me)
  local snap, d, S = {}, self.dirty, NS.Scanner
  for part, spec in pairs(CONTAINER_READS) do
    if d[part] and self:IsReadable(part) then
      local counts, links
      if spec.ids then counts, links = S.ScanContainers(spec.ids()) else counts, links = S.ScanEquipped() end
      local s = snapFor(snap, spec.mine and me or WARBAND)
      s.items[spec.c] = counts
      addLinks(s.links, links)
    end
  end
  if d.money then snapFor(snap, me).money = S.ReadMoney() end
  if d.warbandMoney and self:IsReadable("warbandMoney") then
    local v = S.ReadWarbandMoney()
    if v then snapFor(snap, WARBAND).money = v end
  end
  if d.currency then
    local ch, wb = S.ScanCurrencies()
    snapFor(snap, me).currency = ch
    snapFor(snap, WARBAND).currency = wb
  end
  for _, step in ipairs(R.SCAN_STEPS) do step(self, snap, me) end
  return snap
end

local function columnOf(e, c)
  local out = {}
  for id, row in pairs(e.items) do if row[c] then out[id] = row[c] end end
  return out
end

-- One holder's net change per thing, plus its intra-holder moves and escrow traffic. Only
-- containers that already had a baseline take part (a container's first scan is its genesis).
local function planHolder(plan, holder, e, s)
  local before, after = {}, {}
  for c, counts in pairs(s.items) do
    if e.scanned[c] then before[c] = columnOf(e, c); after[c] = counts end
  end
  local own = e.escrow and { mail = e.escrow.mailOwn } or nil
  local moves, ids, arrivals, exits = L.ClassifyItems(before, after, own)
  local net = {}
  for id, dlt in pairs(ids) do net[L.ThingKey("ITEM", id)] = dlt end
  if s.money and e.scanned.money then
    local dm = s.money - (e.money or 0)
    if dm ~= 0 then net.g = dm end
  end
  if s.currency and e.scanned.currency then
    for _, x in ipairs(L.Diff(e.currency, s.currency)) do net[L.ThingKey("CURRENCY", x.key)] = x.delta end
  end
  plan.net[holder] = net
  for _, mv in ipairs(moves) do mv.holder = holder; plan.moves[#plan.moves + 1] = mv end
  plan.arrivals[holder], plan.exits[holder] = arrivals, exits
end

function R:Plan(snap, me, clock)
  local plan = { net = {}, moves = {}, pairs = {}, arrivals = {}, exits = {} }
  if not self.silent then
    for holder, s in pairs(snap) do
      local e = NS.Holdings:Get(holder)
      if e and e.meta.genesis then planHolder(plan, holder, e, s) end
    end
  end
  for _, step in ipairs(R.PLAN_STEPS) do step(self, plan, me, clock) end
  return plan
end

-- Plan step 1: char <-> warband transfers (warband bank deposit/withdraw, warband gold, account
-- currency moving between the two holders).
R.PLAN_STEPS[#R.PLAN_STEPS + 1] = function(_, plan, me)
  local a, b = plan.net[me], plan.net[WARBAND]
  if not (a and b) then return end
  for _, p in ipairs(L.PairHolders(me, a, WARBAND, b)) do plan.pairs[#plan.pairs + 1] = p end
end

-- Reasons are decided when a change is FIRST seen, not when its hold ends: a stamp with a 1.5 s
-- TTL would be gone by then. Memoized per holder/thing/direction and dropped at commit.
local function computeReason(self, key, dir, clock)
  if self.forceReason then return self.forceReason end
  local kind, id = L.ParseThingKey(key)
  local ctx = NS.Attribution.ReasonContext and NS.Attribution:ReasonContext(clock) or { now = clock, scopes = {} }
  ctx.consumable = (kind == "ITEM" and dir == "OUT" and NS.Compat.IsConsumable(id)) or nil
  ctx.currencySrc = self.CurrencyReasonFor and self:CurrencyReasonFor(kind, id, dir) or nil
  return L.PickReason(kind, dir, ctx)
end

function R:ReasonFor(holder, key, dir, clock)
  local mk = holder .. "\001" .. tostring(key) .. "\001" .. dir
  return self.reasonMemo[mk] or computeReason(self, key, dir, clock)
end

local function memoReasons(self, plan, clock)
  for holder, net in pairs(plan.net) do
    for key, dlt in pairs(net) do
      local dir = dlt > 0 and "IN" or "OUT"
      local mk = holder .. "\001" .. tostring(key) .. "\001" .. dir
      if not self.reasonMemo[mk] then self.reasonMemo[mk] = computeReason(self, key, dir, clock) end
    end
  end
end

-- What can still be waiting for its other half: items while a bank, mailbox or auction house is
-- open (a deposit, a mail take, a post), gold only at a bank (warband gold). A one-sided gold change
-- at a mailbox (postage) or a vendor has no other half coming and is never held for one.
function R:DecideHold(plan, clock)
  if self.forceReason or self.silent then return false end
  local itemPairing = self.readable.bank or self.readable.mail or self.readable.auctionHouse
  local goldPairing = self.readable.bank
  local oneSided, unclaimed = false, false
  for _, net in pairs(plan.net) do
    for key, dlt in pairs(net) do
      local isItem = tostring(key):sub(1, 2) == "i:"
      if (isItem and itemPairing) or (key == "g" and goldPairing) then oneSided = true end
      if dlt > 0 and L.ClaimAvailable(self.claims, key, clock) < dlt then unclaimed = true end
    end
  end
  local hold = L.ShouldHold(oneSided, unclaimed, self._holdSince, clock)
  if hold then memoReasons(self, plan, clock) end
  return hold
end

-- Commit step 1: consume chat claims against gains; the matched chat rows are stamped as the
-- ledger rows they now are (spec §5.3), and only the unclaimed remainder becomes a diff row.
R.COMMIT_STEPS[#R.COMMIT_STEPS + 1] = function(self, plan, _, clock)
  if self.forceReason then return end
  for holder, net in pairs(plan.net) do
    for key, dlt in pairs(net) do
      if dlt > 0 then
        local rest, matched = L.ConsumeClaim(self.claims, key, dlt, clock)
        for _, row in ipairs(matched or {}) do
          row.dir, row.holder, row.claimed = "IN", holder, true
          row.kind = NS.Util.RowKind(row)
        end
        net[key] = (rest ~= 0) and rest or nil
      end
    end
  end
end

local function applySnap(snap, now)
  local Hd, changed = NS.Holdings, {}
  for holder, s in pairs(snap) do
    for c, counts in pairs(s.items) do
      if Hd:ApplyContainer(holder, c, counts, s.links, now) then changed[holder] = true end
    end
    if s.money ~= nil and Hd:ApplyMoney(holder, s.money, now) then changed[holder] = true end
    if s.currency and Hd:ApplyCurrency(holder, s.currency, now) then changed[holder] = true end
  end
  return changed
end

-- ── The row writer ──────────────────────────────────────────────────────────────────────────

local function rowAllowed(kind, id)
  local p = NS.db.profile
  local s = p.settings
  if kind == "ITEM" then return not (p.blacklist and p.blacklist[id]) end
  if kind == "CURRENCY" then
    return s.recordCurrency ~= false and not (p.currencyBlacklist and p.currencyBlacklist[id])
  end
  return s.recordGold ~= false
end

local function linkFor(holder, id)
  for _, h in ipairs({ holder, NS.Util.PlayerKey(), WARBAND }) do
    local e = NS.Holdings:Get(h)
    if e and e.links[id] then return e.links[id] end
  end
  return "item:" .. id
end

function R:MakeRow(holder, kind, id, dir, reason, qty, now, from, to)
  local zone, subzone = NS.Zone()
  local row = {
    ts = now, char = NS.Util.PlayerKey(), classFile = select(2, UnitClass("player")),
    holder = holder, dir = dir, kind = kind, quantity = qty, source = reason,
    confidence = (reason == "OTHER" or reason == "UNTRACKED") and C.Confidence.INFERRED or C.Confidence.CERTAIN,
    zone = zone, subzone = subzone, mapID = NS.PlayerMapID(), from = from, to = to,
  }
  if kind == "ITEM" then
    local link = linkFor(holder, id)
    local _, name, quality = NS.Compat.GetItemInfo(link)
    local ilvl, bound, sell, itype, isub = NS.Compat.GetItemExtras(link)
    row.itemID, row.itemLink, row.itemName, row.quality = id, link, name or ("item:" .. id), quality
    row.itemLevel, row.bound, row.vendorPrice, row.itemType, row.itemSubType = ilvl, bound, sell, itype, isub
    if dir ~= "MOVE" then row.auctionPrice = NS.AuctionPrice:GatherAll(link, id) end
  elseif kind == "CURRENCY" then
    row.currencyID = id
    row.itemName = NS.Compat.CurrencyName(id) or ("currency:" .. id)
    row.itemType, row.itemSubType = C.CURRENCY_TYPE, NS.Compat.CurrencyCategory(id)
    row.quality, row.bound = NS.Compat.CurrencyQuality(id), NS.Compat.CurrencyBound(id)
  else
    row.itemName, row.itemType = "Gold", C.GOLD_TYPE
  end
  return row
end

-- Write one ledger row, or amend the same-key row written under COALESCE_WINDOW seconds ago.
function R:Write(holder, key, dir, reason, qty, now, from, to)
  local kind, id = L.ParseThingKey(key)
  if not kind or qty <= 0 or not rowAllowed(kind, id) then return nil end
  local ck = L.CoalesceKey(holder, key, dir, reason, from and (from .. ">" .. (to or "")) or nil)
  local recent = self.recent[ck]
  if L.Amendable(recent, now) and NS.db.global.history[recent.index] == recent.row then
    NS.Database:Amend(recent.index, qty)
    return recent.row
  end
  local row = self:MakeRow(holder, kind, id, dir, reason, qty, now, from, to)
  local index = NS.Database:Add(row)
  self.recent[ck] = { row = row, index = index, ts = now }
  return row
end

local function sideOf(key, holder, explicit)
  if explicit then return explicit end
  if key == "g" then return "money" end
  if tostring(key):sub(1, 2) == "c:" then return "currency" end
  return holder == WARBAND and CT.TABS or CT.BAGS
end

function R:WriteRows(plan, now, clock)
  for _, mv in ipairs(plan.moves) do
    self:Write(mv.holder, L.ThingKey("ITEM", mv.id), "MOVE", "TRANSFER", mv.qty, now,
      mv.holder .. "/" .. mv.from, mv.holder .. "/" .. mv.to)
  end
  for _, p in ipairs(plan.pairs) do
    local from = p.from .. "/" .. sideOf(p.key, p.from, p.fromC)
    local to = p.to .. "/" .. sideOf(p.key, p.to, p.toC)
    self:Write(p.from, p.key, "MOVE", p.reason or "TRANSFER", p.qty, now, from, to)
    self:Write(p.to, p.key, "MOVE", p.reason or "TRANSFER", p.qty, now, from, to)
  end
  for holder, net in pairs(plan.net) do
    for key, dlt in pairs(net) do
      local dir = dlt > 0 and "IN" or "OUT"
      self:Write(holder, key, dir, self:ReasonFor(holder, key, dir, clock), math.abs(dlt), now)
    end
  end
  self.reasonMemo = {}
end

-- ── Claims API (the chat paths post here, Task 8) ───────────────────────────────────────────
function R:PostClaim(key, qty, row)
  if not self._enabled or not key or not qty or qty <= 0 then return end
  L.PostClaim(self.claims, key, qty, row, GetTime())
end

-- ── Flush ───────────────────────────────────────────────────────────────────────────────────

-- While holding, look again every CLAIM_WAIT seconds (bounded by SETTLE_TIMEOUT in ShouldHold).
-- Events drive the real re-checks; this is the deadline. `_flushing` stops a deferral that runs
-- straight through (no C_Timer) from re-entering Flush.
function R:ScheduleRecheck()
  if self._recheck then return end
  self._recheck = true
  local h = NS.After(L.CLAIM_WAIT, function()
    self._recheck = nil
    if not self._flushing then self:Flush() end
  end)
  if h == nil then self._recheck = nil end
end

local function clearReadDirty(self)
  for part in pairs(self.dirty) do
    if self:IsReadable(part) then self.dirty[part] = nil end
  end
end

-- Holders seen in this pass: a warband entry with no genesis gets it now (its first scan), and a
-- character's `partial` flag is recomputed once its bank has been read.
local function settleGenesis(snap, now)
  for holder in pairs(snap) do
    local e = NS.Holdings:Get(holder)
    if e and (e.meta.genesis or holder == WARBAND) then NS.Holdings:MarkGenesis(holder, now) end
  end
end

local function flushBody(self)
  local me, now, clock = NS.Util.PlayerKey(), time(), GetTime()
  L.PruneClaims(self.claims, clock)
  local snap = self:Scan(me)
  local plan = self:Plan(snap, me, clock)
  if self:DecideHold(plan, clock) then
    self._holdSince = self._holdSince or clock
    self:ScheduleRecheck()
    return
  end
  self._holdSince = nil
  for _, step in ipairs(R.COMMIT_STEPS) do step(self, plan, me, clock, now) end
  local changed = applySnap(snap, now)
  self:WriteRows(plan, now, clock)
  clearReadDirty(self)
  if not self.silent then settleGenesis(snap, now) end
  local e = NS.Holdings:Get(me)
  if e then e.meta.classFile = e.meta.classFile or select(2, UnitClass("player")) end
  for h in pairs(changed) do NS.bus:SendMessage(NS.MSG.HOLDINGS_CHANGED, h) end
end

function R:Flush()
  if InCombatLockdown and InCombatLockdown() then self.deferred = true; return end
  self._flushing = true
  flushBody(self)
  self._flushing = nil
end
```

Extend `R:DisableCapture` (Phase 1) so the ledger state goes down with the registrations:

```lua
function R:DisableCapture()
  if self.__ev then self.__ev:UnregisterAllEvents(); self.__ev = nil end
  self.dirty, self.deferred, self._pending = {}, nil, nil
  self.claims, self.recent, self.reasonMemo = {}, {}, {}
  self._holdSince, self._recheck = nil, nil
  self._enabled = nil
end
```

> `NS.Compat.CurrencyName` is Phase 1's shim (Phase 1 Task 5 note). `NS.Zone` / `NS.PlayerMapID` are the Collector's existing seams.

`defaults/Profile.lua` settings, after `trackLedger`:

```lua
    recordGold       = true,   -- gold gains/losses as ledger rows (holdings track gold regardless)
```

`settings/Schema.lua`, after the `settings.trackLedger` row:

```lua
  { path = "settings.recordGold", default = PD.settings.recordGold, type = "bool", widget = "CheckBox",
    page = "General", group = "Capture", label = "Record gold",
    tooltip = "Write a History row for every gold gain and loss (loot, vendor, repairs, auction house, " ..
      "mail, guild bank). Holdings keep counting gold either way.",
    onChange = function()
      if NS.bus then NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "ledger") end
    end },
```

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS, 0/0 — including every Phase 1 `test_reconciler` case (holdings still update; bank still unreadable when closed; combat still defers). If Phase 1's `"Reconciler: BAG_UPDATE only marks dirty; BAG_UPDATE_DELAYED flushes"` now sees no `HOLDINGS_CHANGED` because the holder has no genesis — it should still see it: `applySnap` runs whether or not rows are planned.

- [ ] **Step 5: Commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add modules/Reconciler.lua defaults/Profile.lua settings/Schema.lua tests/test_reconciler_rows.lua tests/run.lua docs/test-cases.md
git commit -m "feat(ledger): Reconciler writes gain/loss/transfer rows — hold, claims, coalescing" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt"
```

---

### Task 8: Claims from the chat paths, and gold from `CHAT_MSG_MONEY`

**Files:**
- Modify: `modules/Collector.lua:13-19` (upvalues), `:72-86` (`RefreshUpvalues`), `:138-180` (`OnChatMsgLoot`: post claim after `Database:Add`), `:194-260` (`OnChatMsgCurrency`: post claim), add `OnChatMsgMoney`; `:262-284` (`Enable`: register `CHAT_MSG_MONEY`), `:292-306` (`Disable`: unregister it)
- Modify: `tests/test_disabled.lua:69-87` (`OWNED`: add `"event:CHAT_MSG_MONEY:nil"`)
- Test: `tests/test_collector.lua` (append), `tests/test_reconciler_rows.lua` (append the end-to-end pair)

**Interfaces:**
- Consumes: `NS.Reconciler:PostClaim(thingKey, qty, row)` (Task 7), `NS.Ledger.ThingKey` (Phase 1), `NS.Util.ParseSelfMoney` (Task 5), `NS.Constants.GOLD_TYPE` (Task 1), `settings.recordGold` (Task 7), `settings.trackLedger` (Phase 1).
- Produces:
  - Every rich row the Collector writes (`CHAT_MSG_LOOT`, `CHAT_MSG_CURRENCY`) posts a claim for `(thingKey, quantity, row)`; a gated-out line posts none.
  - `NS.Collector:OnChatMsgMoney(_, msg)` — writes `{ kind="GOLD", dir="IN", holder=me, itemName="Gold", itemType=C.GOLD_TYPE, quantity=copper, source/sourceDetail/confidence from Attribution:Consume(), zone/subzone/mapID, ts, char, classFile }` and claims `"g"`. Writes nothing when `trackLedger` or `recordGold` is off.

- [ ] **Step 1: Write the failing tests** — append to `tests/test_collector.lua`:

```lua
local function claimsReset()
  NS.Reconciler.claims = {}
  NS.Reconciler._enabled = true
end

test("Collector: a recorded loot line claims its stack for the holdings diff", function()
  local mocks = T.mocks
  mocks.__now = 0
  claimsReset()
  NS.Collector:RefreshUpvalues()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF_MULTIPLE, LINK, 3))
  local list = NS.Reconciler.claims["i:211296"]
  assertTrue(list ~= nil, "no claim posted")
  assertEqual(list[1].qty, 3)
  assertTrue(list[1].row == NS.Database:History()[NS.Database:Count()])
  NS.Reconciler.claims = {}
end)

test("Collector: a gated-out loot line claims nothing", function()
  local mocks = T.mocks
  claimsReset()
  NS.db.profile.settings.qualityThreshold = 5
  NS.Collector:RefreshUpvalues()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
  assertEqual(NS.Reconciler.claims["i:211296"], nil)
  NS.db.profile.settings.qualityThreshold = 1
  NS.Collector:RefreshUpvalues()
end)

test("Collector: a recorded currency line claims its amount", function()
  local mocks = T.mocks
  claimsReset()
  NS.db.profile.settings.recordCurrency = true
  NS.Collector:RefreshUpvalues()
  NS.Collector:OnChatMsgCurrency(nil, string.format(mocks.CURRENCY_GAINED_MULTIPLE, "|Hcurrency:3008::|h[Valorstones]|h", 25))
  assertEqual(NS.Reconciler.claims["c:3008"][1].qty, 25)
  NS.Reconciler.claims = {}
end)

test("Collector: CHAT_MSG_MONEY writes a GOLD gain and claims it", function()
  claimsReset()
  NS.db.profile.settings.recordGold, NS.db.profile.settings.trackLedger = true, true
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("KILL", { npcID = 5 }, "CERTAIN")
  local before = NS.Database:Count()
  NS.Collector:OnChatMsgMoney(nil, "You loot 1 Gold, 2 Silver, 3 Copper")
  assertEqual(NS.Database:Count(), before + 1)
  local r = NS.Database:History()[NS.Database:Count()]
  assertEqual(r.kind, "GOLD"); assertEqual(r.dir, "IN"); assertEqual(r.quantity, 10203)
  assertEqual(r.itemName, "Gold"); assertEqual(r.itemType, "Gold"); assertEqual(r.source, "KILL")
  assertEqual(r.holder, NS.Util.PlayerKey())
  assertEqual(NS.Reconciler.claims.g[1].qty, 10203)
  NS.Reconciler.claims = {}
end)

test("Collector: CHAT_MSG_MONEY with recordGold or trackLedger off writes nothing", function()
  claimsReset()
  local s = NS.db.profile.settings
  s.recordGold = false; NS.Collector:RefreshUpvalues()
  local before = NS.Database:Count()
  NS.Collector:OnChatMsgMoney(nil, "You loot 5 Copper")
  s.recordGold, s.trackLedger = true, false; NS.Collector:RefreshUpvalues()
  NS.Collector:OnChatMsgMoney(nil, "You loot 5 Copper")
  assertEqual(NS.Database:Count(), before)
  assertEqual(NS.Reconciler.claims.g, nil)
  s.trackLedger = true; NS.Collector:RefreshUpvalues()
end)
```

Append to `tests/test_reconciler_rows.lua` (reuses its `case`, `reset`, `genesis`, `setBag`, `H`):

```lua
local LINK = "|cffa335ee|Hitem:211296::::::::80:::::|h[Vial of Fun]|h|r"

local function chatLoot(qty)
  NS.db.profile.settings.qualityThreshold = 1
  NS.Collector:RefreshUpvalues()
  NS.Collector:OnChatMsgLoot(nil, string.format(m.LOOT_ITEM_SELF_MULTIPLE, LINK, qty))
end

case("Collector+Reconciler: a looted stack is counted once, chat first", function()
  reset()
  genesis()
  chatLoot(3)
  setBag(0, { [1] = { itemID = 211296, link = LINK, count = 3 } })
  R():MarkDirty("bags"); R():Flush()
  assertEqual(#H(), 1)
  assertTrue(H()[1].claimed); assertEqual(H()[1].dir, "IN")
  assertEqual(NS.Holdings:Get(ME).items[211296].bags, 3)
end)

case("Collector+Reconciler: a looted stack is counted once, delta first", function()
  reset()
  genesis()
  setBag(0, { [1] = { itemID = 211296, link = LINK, count = 3 } })
  R():MarkDirty("bags"); R():Flush()
  assertEqual(#H(), 0)                                    -- held: waiting for the claim
  m.__now = 100.4
  chatLoot(3)
  R():Flush()
  assertEqual(#H(), 1); assertTrue(H()[1].claimed)
end)

case("Collector+Reconciler: a partial claim leaves the remainder as a diff row", function()
  reset()
  genesis()
  chatLoot(2)
  setBag(0, { [1] = { itemID = 211296, link = LINK, count = 5 } })
  R():MarkDirty("bags"); R():Flush()                      -- 3 unclaimed: held
  m.__now = 102; R():Flush()
  assertEqual(#H(), 2)
  assertEqual(H()[2].quantity, 3); assertEqual(H()[2].dir, "IN"); assertTrue(H()[2].claimed == nil)
end)

case("Collector+Reconciler: looted gold is counted once", function()
  reset()
  m.__money = 0
  genesis()
  NS.db.profile.settings.trackLedger = true
  NS.Collector:RefreshUpvalues()
  NS.Collector:OnChatMsgMoney(nil, "You loot 45 Copper")
  m.__money = 45
  R():MarkDirty("money"); R():Flush()
  assertEqual(#H(), 1); assertEqual(H()[1].kind, "GOLD"); assertTrue(H()[1].claimed)
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -E "FAIL" | head -20`
Expected: FAIL — no claims posted; `OnChatMsgMoney` nil; the end-to-end cases write two rows.

- [ ] **Step 3: Implement** — `modules/Collector.lua`.

Upvalues (beside `recordCurrency`):

```lua
local recordGold, trackLedger = true, true
```

`RefreshUpvalues`, after `recordCurrency = s.recordCurrency`:

```lua
  recordGold = s.recordGold ~= false
  trackLedger = s.trackLedger ~= false
```

A shared claim helper above `OnChatMsgLoot`:

```lua
-- The holdings diff will see this same thing land. The claim tells it the gain is already written,
-- so only an unclaimed remainder becomes a diff row (timeline-ledger spec §5.3). Posted ONLY for a
-- row that was written: a gated-out line posts nothing, and the diff then records the item as a
-- plain row (spec D2). PostClaim is itself a no-op while ledger capture is off.
local function claim(kind, id, qty, record)
  if (id or kind == "GOLD") and NS.Reconciler and NS.Reconciler.PostClaim then
    NS.Reconciler:PostClaim(NS.Ledger.ThingKey(kind, id), qty, record)
  end
end
```

In `OnChatMsgLoot`, directly after `NS.Database:Add(record)`:

```lua
  claim("ITEM", itemID, qty, record)
```

In `OnChatMsgCurrency`, directly after `NS.Database:Add(record)`:

```lua
  claim("CURRENCY", currencyID, qty, record)
```

New handler after `OnChatMsgCurrency`:

```lua
-- CHAT_MSG_MONEY: the player's own looted money and party share (timeline-ledger spec §5.4). Writes
-- the rich gold row — the loot context still says which kill or chest it came from — and claims it,
-- exactly as a loot line does for an item. Gold rows are a ledger feature: nothing is written while
-- `trackLedger` (legacy gains-only) or `recordGold` is off.
function Collector:OnChatMsgMoney(_, msg)
  local copper = NS.Util.ParseSelfMoney(msg)
  if not copper then return end
  if not (trackLedger and recordGold) then
    if NS.State.debug and NS.Debug then NS.Debug("Drop", "money %s reason=gold-off", tostring(copper)) end
    return
  end
  local source, sourceDetail, confidence = NS.Attribution:Consume()
  local zone, subzone = NS.Zone()
  local me = NS.Util.PlayerKey()
  local record = {
    ts = time(), char = me, classFile = select(2, UnitClass("player")),
    holder = me, dir = "IN", kind = "GOLD",
    itemName = "Gold", itemType = NS.Constants.GOLD_TYPE, quantity = copper,
    source = source, sourceDetail = sourceDetail, confidence = confidence,
    zone = zone, mapID = NS.PlayerMapID(), subzone = subzone,
  }
  NS.Database:Add(record)
  claim("GOLD", nil, copper, record)
  if NS.State.debug and NS.Debug then NS.Debug("Money", "%sc src=%s", tostring(copper), tostring(source)) end
end
```

(`claim("GOLD", nil, …)` claims `"g"`: `ThingKey("GOLD")` ignores the id.)

`Collector:Enable`, after the `CHAT_MSG_CURRENCY` registration:

```lua
  NS.SafeRegisterEvent(bus, "CHAT_MSG_MONEY", function(_, msg) self:OnChatMsgMoney(_, msg) end,
    NS.RejectedEvents)
```

`Collector:Disable`, beside the other two `UnregisterEvent` calls:

```lua
    bus:UnregisterEvent("CHAT_MSG_MONEY")
```

Update the Collector header comment ("CHAT_MSG_LOOT self-filter, quality gate, record build + write") to name the money line and the claims.

- [ ] **Step 4: Update teardown coverage** — `tests/test_disabled.lua` `OWNED`: add `"event:CHAT_MSG_MONEY:nil",` after `CHAT_MSG_CURRENCY`.

- [ ] **Step 5: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS, 0/0. `tests/test_debug_coverage.lua` may require the new `[Money]` tag to be listed where `[Currency]` is; add it there if it fails naming the tag.

- [ ] **Step 6: Commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add modules/Collector.lua tests/test_collector.lua tests/test_reconciler_rows.lua tests/test_disabled.lua docs/test-cases.md
git commit -m "feat(ledger): chat paths claim their rows; CHAT_MSG_MONEY gold gains" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt"
```

---

### Task 9: Currency deltas, account currency transfers, login and resume reconcile

**Files:**
- Modify: `modules/Reconciler.lua` — `R:OnEvent` signature `(event, a1, a2, a3, a4, a5)`; route `CURRENCY_DISPLAY_UPDATE` to `OnCurrencyUpdate`; add `CURRENCY_TRANSFER_LOG_UPDATE` to `EVENTS`; replace Phase 1's `R:LoginScan`; extend `R:Enable` (resume) and the `PLAYER_REGEN_ENABLED` branch (pending login); add the currency scan/plan/commit steps.
- Modify: `modules/Holdings.lua` (append `CreditCurrency`)
- Modify: `tests/test_disabled.lua` `OWNED` (add `"event:CURRENCY_TRANSFER_LOG_UPDATE:nil"`)
- Test: `tests/test_reconciler_rows.lua` (append)

**Interfaces:**
- Consumes: Task 7 pipeline (`R.SCAN_STEPS/PLAN_STEPS/COMMIT_STEPS`, `R.silent`, `R.forceReason`), `NS.Compat.CurrencyIsAccountWide/CurrencySourceName/LatestCurrencyTransfer` (Task 5), `NS.Ledger.CurrencyReason` (Task 3), Phase 1 `NS.Holdings:MarkGenesis`.
- Produces:
  - `NS.Reconciler:OnCurrencyUpdate(id, change, gainSource, destroyReason)` — combat-safe: folds into `R.pendingCur[id]`, `R.curGain[id]`, `R.curLoss[id]`; a nil `id` marks the full list (`"currency"`) dirty.
  - `NS.Reconciler:CurrencyReasonFor(kind, id, dir) -> reason|nil`.
  - `NS.Reconciler:LoginScan()` — first login after v11: silent genesis (no rows); later logins: drift rows with `source = "UNTRACKED"`, no holds, no claims; in combat: `R.loginPending = true`, re-run on `PLAYER_REGEN_ENABLED`.
  - Resume: `R:Enable()` after a stand-down in a session that already logged in schedules `LoginScan` (+1 s), so changes made while stood down land as `UNTRACKED`.
  - `NS.Holdings:CreditCurrency(holder, id, qty) -> boolean` (only for a holder whose `scanned.currency` exists).

- [ ] **Step 1: Write the failing tests** — append to `tests/test_reconciler_rows.lua`:

```lua
local function genesisWithCurrency(list)
  m.__currencyList = list
  for _, p in ipairs({ "bags", "equipped", "money", "currency" }) do R():MarkDirty(p) end
  R().silent = true; R():Flush(); R().silent = nil
  NS.Holdings:MarkGenesis(ME, m.__epoch)
  if NS.Holdings:Get("§warband") then NS.Holdings:MarkGenesis("§warband", m.__epoch) end
end

case("Reconciler: first login is genesis and writes nothing", function()
  reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 4 } }); m.__money = 900
  R():LoginScan()
  assertEqual(#H(), 0)
  local e = NS.Holdings:Get(ME)
  assertTrue(e.meta.genesis ~= nil); assertEqual(e.items[7].bags, 4); assertEqual(e.money, 900)
end)

case("Reconciler: login drift writes UNTRACKED rows, no holds, claims untouched", function()
  reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 4 } }); m.__money = 900
  R():LoginScan()
  R():PostClaim("i:7", 2, {})
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 6 } }); m.__money = 400
  R():LoginScan()
  assertEqual(#H(), 2)
  for _, r in ipairs(H()) do assertEqual(r.source, "UNTRACKED"); assertEqual(r.confidence, "INFERRED") end
  assertEqual(NS.Ledger.ClaimAvailable(R().claims, "i:7", m.__now), 2)
end)

case("Reconciler: a login in combat waits for regen", function()
  reset()
  m.InCombatLockdown = function() return true end
  R():LoginScan()
  assertEqual(NS.Holdings:Get(ME), nil); assertTrue(R().loginPending)
  m.InCombatLockdown = function() return false end
  R():OnEvent("PLAYER_REGEN_ENABLED")
  assertTrue(NS.Holdings:Get(ME).meta.genesis ~= nil)
end)

case("Reconciler: a currency spend from the event args is an OUT with its mapped reason", function()
  reset()
  genesisWithCurrency({ { id = 3008, quantity = 50 } })
  R():OnEvent("CURRENCY_DISPLAY_UPDATE", 3008, 40, -10, nil, m.Enum.CurrencyDestroyReason.Vendor)
  R():Flush()
  assertEqual(#H(), 1)
  local r = H()[1]
  assertEqual(r.kind, "CURRENCY"); assertEqual(r.currencyID, 3008); assertEqual(r.dir, "OUT")
  assertEqual(r.quantity, 10); assertEqual(r.source, "BUY")
  assertEqual(NS.Holdings:Get(ME).currency[3008], 40)
end)

case("Reconciler: currency events in combat accumulate, one row after regen", function()
  reset()
  genesisWithCurrency({ { id = 3008, quantity = 50 } })
  m.InCombatLockdown = function() return true end
  for _ = 1, 5 do R():OnEvent("CURRENCY_DISPLAY_UPDATE", 3008, nil, -2, nil, m.Enum.CurrencyDestroyReason.Spell) end
  R():Flush()
  assertEqual(#H(), 0)
  m.InCombatLockdown = function() return false end
  R():OnEvent("PLAYER_REGEN_ENABLED")
  assertEqual(#H(), 1); assertEqual(H()[1].quantity, 10); assertEqual(H()[1].source, "CONSUME")
end)

case("Reconciler: an account-wide currency change lands on the warband holder", function()
  reset()
  m.__currencyAccountWide = { [2032] = true }
  genesisWithCurrency({ { id = 2032, quantity = 5, accountWide = true } })
  R():OnEvent("CURRENCY_DISPLAY_UPDATE", 2032, 3, -2, nil, nil)
  R():Flush()
  assertEqual(H()[1].holder, "§warband")
  assertEqual(NS.Holdings:Get("§warband").currency[2032], 3)
  m.__currencyAccountWide = {}
end)

case("Reconciler: an account currency transfer to an own alt is a MOVE pair and credits the alt", function()
  reset()
  genesisWithCurrency({ { id = 3008, quantity = 50 } })
  NS.db.global.holdings["Alt-Realm"] = { meta = { genesis = 1 }, scanned = { currency = 1 },
    items = {}, currency = {}, links = {} }
  m.__currencyTransfers = { { currencyType = 3008, quantityTransferred = 10, destinationCharacterName = "Alt" } }
  R():OnEvent("CURRENCY_TRANSFER_LOG_UPDATE")
  R():OnEvent("CURRENCY_DISPLAY_UPDATE", 3008, 38, -12, nil, m.Enum.CurrencyDestroyReason.AccountTransfer)
  R():Flush()
  local moves, outs = 0, 0
  for _, r in ipairs(H()) do
    if r.dir == "MOVE" then moves = moves + 1; assertEqual(r.to, "Alt-Realm/currency") end
    if r.dir == "OUT" then outs = outs + 1; assertEqual(r.quantity, 2); assertEqual(r.source, "TRANSFER") end
  end
  assertEqual(moves, 2); assertEqual(outs, 1)               -- 10 moved, 2 was the transfer fee
  assertEqual(NS.db.global.holdings["Alt-Realm"].currency[3008], 10)
  m.__currencyTransfers = {}
end)

case("Reconciler: changes made while stood down land as UNTRACKED on resume", function()
  reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 1 } })
  R():LoginScan()
  R():DisableCapture()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 3 } })
  R():Enable()
  m.__fireTimers()
  assertEqual(#H(), 1); assertEqual(H()[1].source, "UNTRACKED"); assertEqual(H()[1].quantity, 2)
  R():DisableCapture(); R()._enabled = true
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -E "FAIL" | head -20`
Expected: FAIL — Phase 1 `LoginScan` writes rows for drift with ordinary reasons (or none), currency args are ignored, `loginPending` nil.

- [ ] **Step 3: Implement** — `modules/Reconciler.lua`.

State beside `R.claims`:

```lua
R.pendingCur, R.curGain, R.curLoss = {}, {}, {}
```

`EVENTS`: append `"CURRENCY_TRANSFER_LOG_UPDATE"`.

`R:OnEvent` — change the signature to `function R:OnEvent(event, a1, a2, a3, a4, a5)` and replace the `CURRENCY_DISPLAY_UPDATE` branch and the `PLAYER_REGEN_ENABLED` branch:

```lua
  elseif event == "CURRENCY_DISPLAY_UPDATE" then
    self:OnCurrencyUpdate(a1, a3, a4, a5)                 -- (id, quantity, change, gainSrc, lostSrc)
  elseif event == "CURRENCY_TRANSFER_LOG_UPDATE" then
    self.pendingTransfer = true
    self:MarkDirty("currencyDelta"); scheduleFlush(self)
```

```lua
  elseif event == "PLAYER_REGEN_ENABLED" then
    if self.loginPending then self:LoginScan()
    elseif self.deferred then self.deferred = nil; self:Flush() end
```

Below `R:OnEvent`:

```lua
-- CURRENCY_DISPLAY_UPDATE carries the change itself (timeline-ledger spec §5.2), so currency needs
-- no list rescan: the delta is folded into a per-id accumulator (combat-safe, no allocation after a
-- currency's first event) and the raw source/destroy enums are kept for the reason. A nil id is the
-- client's bulk refresh: rescan the whole list instead.
function R:OnCurrencyUpdate(id, change, gainSrc, lostSrc)
  if not id then self:MarkDirty("currency"); scheduleFlush(self); return end
  if not change or change == 0 then return end
  self.pendingCur[id] = (self.pendingCur[id] or 0) + change
  if gainSrc ~= nil then self.curGain[id] = gainSrc end
  if lostSrc ~= nil then self.curLoss[id] = lostSrc end
  self:MarkDirty("currencyDelta"); scheduleFlush(self)
end

function R:CurrencyReasonFor(kind, id, dir)
  if kind ~= "CURRENCY" then return nil end
  local name = NS.Compat.CurrencySourceName(self.curGain[id], self.curLoss[id], dir == "IN" and 1 or -1)
  return L.CurrencyReason(name, dir)
end

-- Scan step: the pending deltas become a currency map per holder (account-wide -> §warband),
-- built on the stored baseline. A full list rescan in the same pass is authoritative instead.
R.SCAN_STEPS[#R.SCAN_STEPS + 1] = function(self, snap, me)
  if not self.dirty.currencyDelta or self.dirty.currency then return end
  for id, dlt in pairs(self.pendingCur) do
    local holder = NS.Compat.CurrencyIsAccountWide(id) and WARBAND or me
    local s = snapFor(snap, holder)
    if not s.currency then
      local e = NS.Holdings:Get(holder)
      s.currency = {}
      for k, v in pairs(e and e.currency or {}) do s.currency[k] = v end
    end
    local v = (s.currency[id] or 0) + dlt
    s.currency[id] = (v > 0) and v or nil
  end
end

-- Plan step: a warband-transferable currency sent to an own alt (CURRENCY_TRANSFER_LOG_UPDATE) is a
-- transfer, not a loss. Whatever the transfer consumed beyond the amount received stays an OUT
-- (reason TRANSFER — the transfer's cost).
R.PLAN_STEPS[#R.PLAN_STEPS + 1] = function(self, plan, me)
  local net = plan.net[me]
  if not (net and self.pendingTransfer) then return end
  local t = NS.Compat.LatestCurrencyTransfer()
  if not (t and t.currencyID and t.toKey and t.toKey ~= me) then return end
  local key = L.ThingKey("CURRENCY", t.currencyID)
  local dlt = net[key]
  if not dlt or dlt >= 0 then return end
  local q = math.min(-dlt, t.quantity or 0)
  if q <= 0 then return end
  plan.pairs[#plan.pairs + 1] = { key = key, qty = q, from = me, to = t.toKey,
    fromC = "currency", toC = "currency", creditCurrency = t.currencyID }
  net[key] = (dlt + q ~= 0) and (dlt + q) or nil
end

-- Commit step: credit the recipient's stored currency, freeze the currency reasons into the memo
-- (WriteRows runs after this), then clear the accumulators.
R.COMMIT_STEPS[#R.COMMIT_STEPS + 1] = function(self, plan, _, clock)
  for _, p in ipairs(plan.pairs) do
    if p.creditCurrency then NS.Holdings:CreditCurrency(p.to, p.creditCurrency, p.qty) end
  end
  memoReasons(self, plan, clock)
  for k in pairs(self.pendingCur) do self.pendingCur[k] = nil end
  for k in pairs(self.curGain) do self.curGain[k] = nil end
  for k in pairs(self.curLoss) do self.curLoss[k] = nil end
  self.pendingTransfer = nil
end
```

> `snapFor` and `memoReasons` are file-local functions defined earlier in `modules/Reconciler.lua` (Task 7); these steps sit below them in the same file. `memoReasons` is called **before** `WriteRows`, so `ReasonFor` reads the reason computed while the source enums were still known.

Replace Phase 1's `R:LoginScan`:

```lua
-- Login reconcile (timeline-ledger spec §5.6). The first login after v11 writes the snapshot as
-- this holder's GENESIS and no rows. Every later login diffs against the stored snapshot: whatever
-- changed while the addon was not watching is written as UNTRACKED — no holds (nothing is in
-- flight), no claims (no chat line belongs to it) — so holdings and the rows reconcile.
function R:LoginScan()
  self._sessionStarted = true
  if InCombatLockdown and InCombatLockdown() then self.loginPending, self.deferred = true, true; return end
  self.loginPending = nil
  for _, p in ipairs({ "bags", "equipped", "money", "currency", "warbandMoney" }) do self:MarkDirty(p) end
  local me = NS.Util.PlayerKey()
  local e = NS.Holdings:Get(me)
  local first = not (e and e.meta.genesis)
  if first then self.silent = true else self.forceReason = C.SourceType.UNTRACKED end
  self:Flush()
  self.silent, self.forceReason = nil, nil
  local now = time()
  NS.Holdings:MarkGenesis(me, now)
  if NS.Holdings:Get(WARBAND) then NS.Holdings:MarkGenesis(WARBAND, now) end
end
```

In `R:Enable`, after the registration loop sets `self._enabled = true`:

```lua
  -- Back up after a stand-down (disable, perf suspend) in a session that already logged in: what
  -- changed while nothing was watching is drift, exactly like a login.
  if self._sessionStarted then
    NS.After(1, function() if self._enabled then self:LoginScan() end end)
  end
```

`R:DisableCapture` — add `self.pendingCur, self.curGain, self.curLoss, self.pendingTransfer, self.loginPending = {}, {}, {}, nil, nil`.

`modules/Holdings.lua` — append:

```lua
-- Credit an own alt's stored currency for a transfer this character just made, so the alt's next
-- login does not read the arrival as untracked drift. Only a holder whose currency was ever scanned:
-- an alt with no baseline gets the amount as part of its genesis instead.
function Holdings:CreditCurrency(holder, id, qty)
  local e = self:Get(holder)
  if not (e and e.scanned.currency) then return false end
  local v = (e.currency[id] or 0) + qty
  e.currency[id] = (v > 0) and v or nil
  return true
end
```

- [ ] **Step 4: Update teardown coverage** — `tests/test_disabled.lua` `OWNED`: add `"event:CURRENCY_TRANSFER_LOG_UPDATE:nil",`.

- [ ] **Step 5: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS, 0/0. Phase 1's `"Reconciler: LoginScan seeds genesis, partial until bank seen"` still passes (first login path). Phase 1's `"Reconciler: account-wide currency lands on the warband holder"` still passes (it marks `"currency"` dirty explicitly: list rescan).

- [ ] **Step 6: Commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add modules/Reconciler.lua modules/Holdings.lua tests/test_reconciler_rows.lua tests/test_disabled.lua docs/test-cases.md
git commit -m "feat(ledger): currency deltas from event args, account transfers, UNTRACKED login and resume drift" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt"
```

---

### Task 10: Mail and auction-house escrow (`modules/Escrow.lua`)

**Files:**
- Create: `modules/Escrow.lua`
- Modify: `modules/Reconciler.lua` — replace Phase 1's interaction branch (`BANK_INTERACTIONS` loop) with the table-driven `R.READABLE_ON` + `R:OnInteraction`; extend `R:IsReadable`; add `MAIL_INBOX_UPDATE`, `OWNED_AUCTIONS_UPDATED` to `EVENTS` and `OnEvent`; expose `R.SnapFor`; `WriteRows` writes a self-pair once and writes `plan.extra`.
- Modify: `modules/Holdings.lua` (append `Escrow`, `CreditEscrow`)
- Modify: `LootHistory.toc` (`modules\Escrow.lua` directly after `modules\Reconciler.lua`)
- Modify: `tests/test_disabled.lua` `OWNED` (add `"event:MAIL_INBOX_UPDATE:nil"`, `"event:OWNED_AUCTIONS_UPDATED:nil"`)
- Create: `tests/ledger_support.lua` (shared Reconciler test helpers), `tests/test_escrow.lua`; register `"test_escrow"` after `"test_reconciler_rows"` in `tests/run.lua`

**Interfaces:**
- Consumes: Task 7 pipeline arrays, `R.readable`, `R:Write`, `R:Flush`; `NS.State.pendingMail/pendingPost/soldMail` (Task 6); `NS.Compat.ScanInbox/ScanOwnedAuctions/GetItemInfo` (Task 5 + existing); `NS.Ledger.ThingKey` (Phase 1).
- Produces:
  - `NS.Reconciler.READABLE_ON` — `{ [interactionTypeName] = { flag = readableKey, parts = {dirtyPart,...} } }` (Banker, AccountBanker → `bank`; MailInfo → `mail`; Auctioneer → `auctionHouse`); `R:OnInteraction(shown, interactionType)`.
  - `R:IsReadable("mail")` (mailbox open), `R:IsReadable("auctions")` (owned-auctions list received while the AH is open).
  - `NS.Reconciler.SnapFor(snap, holder) -> s`.
  - `plan.extra = { {holder, key, dir, reason, qty} }` rows written verbatim by `WriteRows`.
  - `NS.Holdings:Escrow(holder) -> { mailOwn = {[id]=n}, mailMoney = copper, exits = {[id] = {n, ts}} }` (persisted in `db.global.holdings[holder].escrow`).
  - `NS.Holdings:CreditEscrow(holder, container, id, qty, own) -> boolean`.
  - `NS.Escrow.EXIT_TTL = 30 * 86400` (an auction exit unresolved this long is booked as `AH_SOLD`).

- [ ] **Step 1: Write the shared helpers** — `tests/ledger_support.lua`

```lua
-- Shared helpers for the Reconciler-driven suites (test_escrow). Frozen wall clock per case, the
-- shared mock restored on the way out whether the body passed or threw.
local T = _G.LH_TEST
local NS, m = T.NS, T.mocks
local S = {}

function S.R() return NS.Reconciler end
function S.H() return NS.db.global.history end
function S.me() return NS.Util.PlayerKey() end

function S.case(name, body)
  T.test(name, function()
    local savedTime, savedICL = m.time, m.InCombatLockdown
    local savedInbox, savedAuctions = m.__inbox, m.__ownedAuctions
    m.__epoch, m.__now = 5000, 100
    m.time = function() return m.__epoch end
    local ok, err = pcall(body)
    m.time, m.InCombatLockdown = savedTime, savedICL
    m.__inbox, m.__ownedAuctions = savedInbox, savedAuctions
    if not ok then error(err, 0) end
  end)
end

function S.setBag(bagID, slots)
  m.__bags[bagID] = slots
  local n = 0; for s in pairs(slots) do if s > n then n = s end end
  m.__bagSlots[bagID] = n
end

function S.reset()
  NS.db.global.history, NS.db.global.holdings = {}, {}
  m.__bags, m.__bagSlots, m.__inventory, m.__money, m.__warbandMoney = {}, {}, {}, 0, 0
  m.__inbox, m.__ownedAuctions, m.__itemClassID = {}, {}, 4
  NS.db.profile.blacklist = {}
  local r = S.R()
  r.dirty, r.readable, r.deferred, r._holdSince = {}, {}, nil, nil
  r.claims, r.recent, r.reasonMemo = {}, {}, {}
  r._enabled = true
  local st = NS.State
  st.outContext, st.lootContext, st.pendingMail, st.soldMail = nil, nil, nil, nil
  for k in pairs(st.scopes) do st.scopes[k] = nil end
  for k in pairs(st.pendingPost) do st.pendingPost[k] = nil end
end

function S.genesis()
  local r = S.R()
  for _, p in ipairs({ "bags", "equipped", "money" }) do r:MarkDirty(p) end
  r.silent = true; r:Flush(); r.silent = nil
  NS.Holdings:MarkGenesis(S.me(), m.__epoch)
end

function S.show(name) S.R():OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", NS.Compat.InteractionType(name)) end

return S
```

- [ ] **Step 2: Write the failing test** — `tests/test_escrow.lua`

```lua
local T = _G.LH_TEST
local NS = T.NS
local assertEqual, assertTrue = T.assertEqual, T.assertTrue
local m = T.mocks
local S = dofile("tests/ledger_support.lua")
local case, R, H, setBag = S.case, S.R, S.H, S.setBag

local function rowsBy(dir)
  local out = {}
  for _, r in ipairs(H()) do if r.dir == dir then out[#out + 1] = r end end
  return out
end

case("Escrow: mail to an own alt is a MOVE pair; the alt's mail and own-origin are credited", function()
  S.reset()
  setBag(0, { [1] = { itemID = 7, link = "L7", count = 3 } }); m.__money = 5000
  S.genesis()
  NS.db.global.holdings["Alt-Realm"] = { meta = { genesis = 1 }, scanned = { bags = 1 }, items = {},
    currency = {}, links = {} }
  NS.State.pendingMail = { to = "Alt-Realm", items = { [7] = 3 }, money = 1000, sent = true, expires = 200 }
  NS.Attribution:StampOut("MAIL_SEND", { dirs = { OUT = true } })
  S.show("MailInfo")
  setBag(0, {}); m.__money = 3970                         -- 1000 sent + 30 postage
  R():MarkDirty("bags"); R():MarkDirty("money"); R():Flush()
  assertEqual(#rowsBy("MOVE"), 4)                          -- item and gold, one row per holder each
  local outs = rowsBy("OUT")
  assertEqual(#outs, 1); assertEqual(outs[1].kind, "GOLD"); assertEqual(outs[1].quantity, 30)
  assertEqual(outs[1].source, "MAIL_SEND")
  local alt = NS.db.global.holdings["Alt-Realm"]
  assertEqual(alt.items[7].mail, 3)
  assertEqual(alt.escrow.mailOwn[7], 3); assertEqual(alt.escrow.mailMoney, 1000)
  assertEqual(NS.State.pendingMail, nil)
end)

case("Escrow: taking mail splits own-origin (MOVE) from outside gains (IN)", function()
  S.reset()
  S.genesis()
  m.__inbox = { { items = { { itemID = 9, count = 4, link = "L9" } } } }
  S.show("MailInfo"); NS.Attribution:SetScope("mailbox", true)
  R():Flush()                                              -- the inbox's first scan: its genesis
  assertEqual(#H(), 0)
  NS.Holdings:Escrow(S.me()).mailOwn[9] = 1
  m.__inbox = {}; setBag(0, { [1] = { itemID = 9, link = "L9", count = 4 } })
  R():MarkDirty("mail"); R():MarkDirty("bags"); R():Flush()
  m.__now = 108; R():Flush()                               -- past the settle and claim waits
  assertEqual(#rowsBy("MOVE"), 1); assertEqual(rowsBy("MOVE")[1].from, S.me() .. "/mail")
  local ins = rowsBy("IN")
  assertEqual(#ins, 1); assertEqual(ins[1].quantity, 3); assertEqual(ins[1].source, "MAIL")
  assertEqual(NS.Holdings:Escrow(S.me()).mailOwn[9], nil)
end)

case("Escrow: posting moves bags to auctions and credits the auctions column", function()
  S.reset()
  setBag(0, { [1] = { itemID = 3, link = "L3", count = 2 } })
  S.genesis()
  S.show("Auctioneer")
  NS.State.pendingPost[3] = 2
  setBag(0, {})
  R():MarkDirty("bags"); R():Flush()
  assertEqual(#H(), 1)
  assertEqual(H()[1].dir, "MOVE"); assertEqual(H()[1].to, S.me() .. "/auctions")
  assertEqual(NS.Holdings:Get(S.me()).items[3].auctions, 2)
  assertEqual(NS.State.pendingPost[3], nil)
end)

case("Escrow: an auction that leaves and comes back by mail is a return, not a sale", function()
  S.reset()
  S.genesis()
  S.show("Auctioneer")
  m.__ownedAuctions = { { itemID = 3, quantity = 2, link = "L3", status = 0 } }
  R():OnEvent("OWNED_AUCTIONS_UPDATED"); R():Flush()       -- auctions column genesis
  m.__ownedAuctions = {}
  R():OnEvent("OWNED_AUCTIONS_UPDATED"); R():Flush()
  assertEqual(#H(), 0)
  assertEqual(NS.Holdings:Escrow(S.me()).exits[3].n, 2)
  S.show("MailInfo"); R():Flush()                          -- empty inbox: mail column genesis
  m.__inbox = { { items = { { itemID = 3, count = 2, link = "L3" } } } }
  R():OnEvent("MAIL_INBOX_UPDATE"); R():Flush()
  assertEqual(#H(), 0)
  assertEqual(NS.Holdings:Escrow(S.me()).mailOwn[3], 2)
  assertEqual(NS.Holdings:Escrow(S.me()).exits[3], nil)
end)

case("Escrow: an AH sale mail books the pending exit as AH_SOLD", function()
  S.reset()
  m.__money = 0
  S.genesis()
  local esc = NS.Holdings:Escrow(S.me())
  esc.exits[3] = { n = 2, ts = m.__epoch }
  NS.db.global.holdings[S.me()].links[3] = "L3"            -- mock GetItemInfo names it "Item Name"
  NS.State.soldMail = { itemName = "Item Name", expires = 150 }
  NS.Attribution:StampOut("AH_SOLD", { kinds = { GOLD = true }, dirs = { IN = true } })
  m.__money = 9000
  R():MarkDirty("money"); R():Flush()
  m.__now = 102; R():Flush()
  local outs, ins = rowsBy("OUT"), rowsBy("IN")
  assertEqual(#outs, 1); assertEqual(outs[1].source, "AH_SOLD"); assertEqual(outs[1].quantity, 2)
  assertEqual(outs[1].itemID, 3)
  assertEqual(#ins, 1); assertEqual(ins[1].kind, "GOLD"); assertEqual(ins[1].source, "AH_SOLD")
  assertEqual(esc.exits[3], nil); assertEqual(NS.State.soldMail, nil)
end)

case("Escrow: an exit unresolved for 30 days is booked as sold", function()
  S.reset()
  S.genesis()
  NS.Holdings:Escrow(S.me()).exits[3] = { n = 1, ts = m.__epoch - NS.Escrow.EXIT_TTL - 1 }
  R():MarkDirty("bags"); R():Flush()
  assertEqual(#H(), 1); assertEqual(H()[1].source, "AH_SOLD")
end)

case("Escrow: mail money taken from an own alt's send is a MOVE", function()
  S.reset()
  m.__money = 0
  S.genesis()
  NS.Holdings:Escrow(S.me()).mailMoney = 1000
  S.show("MailInfo"); R():Flush()
  m.__money = 1000
  R():MarkDirty("money"); R():Flush()
  assertEqual(#H(), 1); assertEqual(H()[1].dir, "MOVE"); assertEqual(H()[1].to, S.me() .. "/money")
  assertEqual(NS.Holdings:Escrow(S.me()).mailMoney, 0)
end)

case("Escrow: the mailbox is unreadable once closed", function()
  S.reset()
  S.genesis()
  S.show("MailInfo")
  assertTrue(R():IsReadable("mail"))
  R():OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", NS.Compat.InteractionType("MailInfo"))
  assertEqual(R():IsReadable("mail"), false)
end)
```

- [ ] **Step 3: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -A2 "Escrow:" | head -30`
Expected: FAIL — `NS.Escrow` nil, mail never readable, `Holdings:Escrow` nil.

- [ ] **Step 4: Implement the Reconciler changes** — `modules/Reconciler.lua`.

Replace the Phase 1 `BANK_INTERACTIONS` table and the interaction branch of `OnEvent`:

```lua
-- Which interaction frame makes which containers readable, and which parts to rescan on open.
-- Escrow's two (mailbox, auction house) are listed here because the readable flags are this
-- module's; what to DO with the mail/auctions columns is modules/Escrow.lua's.
R.READABLE_ON = {
  Banker        = { flag = "bank",         parts = { "bank", "tabs", "warbandMoney" } },
  AccountBanker = { flag = "bank",         parts = { "bank", "tabs", "warbandMoney" } },
  MailInfo      = { flag = "mail",         parts = { "mail" } },
  Auctioneer    = { flag = "auctionHouse", parts = {} },
}

function R:OnInteraction(shown, interactionType)
  for name, spec in pairs(R.READABLE_ON) do
    if interactionType ~= nil and interactionType == NS.Compat.InteractionType(name) then
      if shown then
        self.readable[spec.flag] = true
        for _, p in ipairs(spec.parts) do self:MarkDirty(p) end
        scheduleFlush(self)
      else
        self:Flush()                                       -- final read while still readable
        self.readable[spec.flag] = nil
        if spec.flag == "auctionHouse" then self.readable.auctions = nil end
      end
    end
  end
end
```

`OnEvent` interaction branch becomes:

```lua
  elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then self:OnInteraction(true, a1)
  elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then self:OnInteraction(false, a1)
  elseif event == "MAIL_INBOX_UPDATE" then
    if self.readable.mail then self:MarkDirty("mail"); scheduleFlush(self) end
  elseif event == "OWNED_AUCTIONS_UPDATED" then
    -- The owned list is only trustworthy once the client has answered the query, which is this event.
    if self.readable.auctionHouse then self.readable.auctions = true; self:MarkDirty("auctions"); scheduleFlush(self) end
```

`R:IsReadable`:

```lua
function R:IsReadable(part)
  if part == "bank" or part == "tabs" then return self.readable.bank == true end
  if part == "mail" then return self.readable.mail == true end
  if part == "auctions" then return self.readable.auctions == true end
  if part == "warbandMoney" then return NS.Compat.GetWarbandMoney() ~= nil end
  return true
end
```

`EVENTS`: append `"MAIL_INBOX_UPDATE", "OWNED_AUCTIONS_UPDATED"`.

Below `snapFor`: `R.SnapFor = snapFor`.

In `R:WriteRows`, replace the pairs loop and add the extra rows before the net loop:

```lua
  for _, p in ipairs(plan.pairs) do
    local from = p.from .. "/" .. sideOf(p.key, p.from, p.fromC)
    local to = p.to .. "/" .. sideOf(p.key, p.to, p.toC)
    self:Write(p.from, p.key, "MOVE", p.reason or "TRANSFER", p.qty, now, from, to)
    -- A pair within one holder (mail money taken) is one row, not two.
    if p.to ~= p.from then self:Write(p.to, p.key, "MOVE", p.reason or "TRANSFER", p.qty, now, from, to) end
  end
  for _, x in ipairs(plan.extra or {}) do self:Write(x.holder, x.key, x.dir, x.reason, x.qty, now) end
```

- [ ] **Step 5: Implement Holdings** — `modules/Holdings.lua`, append:

```lua
-- Escrow bookkeeping (timeline-ledger spec §3 `mail`/`auctions`): how much of a holder's mail came
-- from an own source (an alt's send, a returned auction), gold mailed in from an alt, and auctions
-- that left the AH without yet resolving to a sale or a return. Persisted: a mail can sit for weeks.
function Holdings:Escrow(holder)
  local e = self:Get(holder, true)
  e.escrow = e.escrow or { mailOwn = {}, mailMoney = 0, exits = {} }
  return e.escrow
end

-- Put `qty` of `id` into a holder's escrow container without a scan (a send to an alt, a post).
-- The column's scanned time is left alone: the next real scan is authoritative.
function Holdings:CreditEscrow(holder, container, id, qty, own)
  local e = self:Get(holder)
  if not e then return false end
  local row = e.items[id]
  if not row then row = {}; e.items[id] = row end
  row[container] = (row[container] or 0) + qty
  if own then
    local esc = self:Escrow(holder)
    esc.mailOwn[id] = (esc.mailOwn[id] or 0) + qty
  end
  return true
end
```

- [ ] **Step 6: Implement** — `modules/Escrow.lua`:

```lua
local _, NS = ...
NS.Escrow = NS.Escrow or {}
local Escrow = NS.Escrow

-- Mail and auction-house escrow (timeline-ledger spec §3, §5.1 case 2, §5.4 AH rows). Plugs into
-- the Reconciler's SCAN/PLAN/COMMIT steps; owns no events (the readable flags and MAIL_INBOX_UPDATE
-- / OWNED_AUCTIONS_UPDATED are the Reconciler's), so it has nothing to stand down.
--
-- The rules: an arrival in mail or auctions is HOLDINGS-ONLY (no row) until it resolves —
--   * mail taken into bags: own-origin part is a MOVE, the rest a gain (Ledger.ClassifyItems);
--   * an auction that leaves the list: held as an EXIT until it comes back by mail (a return:
--     own-origin mail) or a sale mail names it (OUT AH_SOLD), or EXIT_TTL passes (sold).
-- Outbound: a send to an own alt is a MOVE pair into the alt's mail; a post is a MOVE into auctions.

local L = NS.Ledger
local R = NS.Reconciler
local C = NS.Constants

Escrow.EXIT_TTL = 30 * 86400

local function addLinks(dst, src) for id, l in pairs(src or {}) do if not dst[id] then dst[id] = l end end end

-- ── Scan ────────────────────────────────────────────────────────────────────────────────────
R.SCAN_STEPS[#R.SCAN_STEPS + 1] = function(self, snap, me)
  local d = self.dirty
  if d.mail and self:IsReadable("mail") then
    local s = R.SnapFor(snap, me)
    local c, l = NS.Compat.ScanInbox()
    s.items[C.Container.MAIL] = c; addLinks(s.links, l)
  end
  if d.auctions and self:IsReadable("auctions") then
    local s = R.SnapFor(snap, me)
    local c, l = NS.Compat.ScanOwnedAuctions()
    s.items[C.Container.AUCTIONS] = c; addLinks(s.links, l)
  end
end

-- ── Plan ────────────────────────────────────────────────────────────────────────────────────

local function reduce(net, key, q)
  local v = net[key] + q
  net[key] = (v ~= 0) and v or nil
end

-- A sent mail to an own alt: what left the bags/purse is that alt's mail now.
local function planMail(_, plan, me, clock)
  local p, net = NS.State.pendingMail, plan.net[me]
  if not (p and p.sent and p.to and p.expires >= clock and net) then return end
  for id, n in pairs(p.items) do
    local key = L.ThingKey("ITEM", id)
    local dlt = net[key]
    if dlt and dlt < 0 then
      local q = math.min(-dlt, n)
      plan.pairs[#plan.pairs + 1] = { key = key, qty = q, from = me, to = p.to,
        fromC = C.Container.BAGS, toC = C.Container.MAIL, creditMail = id }
      reduce(net, key, q)
    end
  end
  if (p.money or 0) > 0 and net.g and net.g < 0 then
    local q = math.min(-net.g, p.money)
    plan.pairs[#plan.pairs + 1] = { key = "g", qty = q, from = me, to = p.to, fromC = "money",
      toC = C.Container.MAIL, creditMailMoney = true }
    reduce(net, "g", q)
  end
  plan.mailConsumed = true
end

-- A post: what left the bags is in this character's auctions now (before the owned list says so).
local function planPost(_, plan, me)
  local net = plan.net[me]
  if not net then return end
  for id, n in pairs(NS.State.pendingPost) do
    local key = L.ThingKey("ITEM", id)
    local dlt = net[key]
    if dlt and dlt < 0 then
      local q = math.min(-dlt, n)
      plan.moves[#plan.moves + 1] = { holder = me, id = id, qty = q, from = C.Container.BAGS,
        to = C.Container.AUCTIONS, creditAuctions = true }
      reduce(net, key, q)
    end
  end
end

-- Gold an own alt mailed in: taking it is a MOVE inside this holder (mail -> money).
local function planMailMoney(self, plan, me)
  local net, e = plan.net[me], NS.Holdings:Get(me)
  local esc = e and e.escrow
  if not (net and net.g and net.g > 0 and esc and (esc.mailMoney or 0) > 0 and self.readable.mail) then return end
  local q = math.min(net.g, esc.mailMoney)
  plan.pairs[#plan.pairs + 1] = { key = "g", qty = q, from = me, to = me, fromC = C.Container.MAIL,
    toC = "money", debitMailMoney = q }
  reduce(net, "g", q)
end

local function itemName(e, id)
  local _, name = NS.Compat.GetItemInfo((e and e.links[id]) or ("item:" .. id))
  return name
end

-- Exits: a mail arrival of an exited item is its return; a sale mail naming it is its sale; an exit
-- older than EXIT_TTL is booked as sold.
local function planExits(_, plan, me, clock, now)
  now = now or time()
  local e = NS.Holdings:Get(me)
  local esc = e and e.escrow
  plan.returns, plan.sold, plan.extra = {}, {}, plan.extra or {}
  local arrived = plan.arrivals[me] and plan.arrivals[me].mail or {}
  if esc then
    for id, x in pairs(esc.exits) do
      local back = math.min(arrived[id] or 0, x.n)
      if back > 0 then plan.returns[id] = back end
    end
    local sold = NS.State.soldMail
    for id, x in pairs(esc.exits) do
      local left = x.n - (plan.returns[id] or 0)
      local byMail = sold and sold.expires >= clock and sold.itemName and sold.itemName == itemName(e, id)
      if left > 0 and (byMail or (now - x.ts) >= Escrow.EXIT_TTL) then
        plan.sold[id] = left
        plan.extra[#plan.extra + 1] = { holder = me, key = L.ThingKey("ITEM", id), dir = "OUT",
          reason = "AH_SOLD", qty = left }
      end
    end
  end
end

R.PLAN_STEPS[#R.PLAN_STEPS + 1] = planMail
R.PLAN_STEPS[#R.PLAN_STEPS + 1] = planPost
R.PLAN_STEPS[#R.PLAN_STEPS + 1] = planMailMoney
R.PLAN_STEPS[#R.PLAN_STEPS + 1] = function(self, plan, me, clock) planExits(self, plan, me, clock, time()) end

-- ── Commit ──────────────────────────────────────────────────────────────────────────────────
local function commitPairs(plan)
  local Hd = NS.Holdings
  for _, p in ipairs(plan.pairs) do
    if p.creditMail then Hd:CreditEscrow(p.to, C.Container.MAIL, p.creditMail, p.qty, true) end
    if p.creditMailMoney and Hd:Get(p.to) then
      local esc = Hd:Escrow(p.to); esc.mailMoney = (esc.mailMoney or 0) + p.qty
    end
    if p.debitMailMoney then
      local esc = Hd:Escrow(p.from); esc.mailMoney = math.max(0, (esc.mailMoney or 0) - p.debitMailMoney)
    end
  end
end

local function commitMoves(plan)
  local Hd = NS.Holdings
  for _, mv in ipairs(plan.moves) do
    if mv.creditAuctions then
      Hd:CreditEscrow(mv.holder, C.Container.AUCTIONS, mv.id, mv.qty, false)
      local left = (NS.State.pendingPost[mv.id] or 0) - mv.qty
      NS.State.pendingPost[mv.id] = (left > 0) and left or nil
    end
    if mv.from == C.Container.MAIL then
      local own = Hd:Escrow(mv.holder).mailOwn
      local left = (own[mv.id] or 0) - mv.qty
      own[mv.id] = (left > 0) and left or nil
    end
  end
end

local function commitExits(plan, me, now)
  local hasExits = next(plan.exits[me] or {}) ~= nil
  local e = NS.Holdings:Get(me)
  if not (e and (e.escrow or hasExits)) then return end
  local esc = NS.Holdings:Escrow(me)
  for id, n in pairs(plan.exits[me] or {}) do
    local x = esc.exits[id] or { n = 0 }
    x.n, x.ts = x.n + n, now
    esc.exits[id] = x
  end
  for id, back in pairs(plan.returns or {}) do
    esc.mailOwn[id] = (esc.mailOwn[id] or 0) + back
    esc.exits[id].n = esc.exits[id].n - back
  end
  for id, n in pairs(plan.sold or {}) do esc.exits[id].n = esc.exits[id].n - n end
  for id, x in pairs(esc.exits) do if x.n <= 0 then esc.exits[id] = nil end end
  if next(plan.sold or {}) then NS.State.soldMail = nil end
end

R.COMMIT_STEPS[#R.COMMIT_STEPS + 1] = function(_, plan, me, _, now)
  commitPairs(plan)
  commitMoves(plan)
  commitExits(plan, me, now or time())
  if plan.mailConsumed then NS.State.pendingMail = nil end
end
```

> Load order: `modules\Escrow.lua` is listed after `modules\Reconciler.lua`, so `NS.Reconciler`'s step arrays exist when this file appends to them. Escrow's PLAN steps run after the warband pairing and currency-transfer steps; its COMMIT step after claims and the currency commit.

- [ ] **Step 7: Update teardown coverage** — `tests/test_disabled.lua` `OWNED`: add `"event:MAIL_INBOX_UPDATE:nil",` and `"event:OWNED_AUCTIONS_UPDATED:nil",`.

- [ ] **Step 8: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS, 0/0, including every Phase 1 bank-readability case through the new `OnInteraction`.

- [ ] **Step 9: Commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add modules/Escrow.lua modules/Reconciler.lua modules/Holdings.lua LootHistory.toc tests/ledger_support.lua tests/test_escrow.lua tests/test_disabled.lua tests/run.lua docs/test-cases.md
git commit -m "feat(ledger): mail and auction-house escrow — own-alt sends, posts, returns, sales" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt"
```

---

### Task 11: History — Direction column, signed quantity, Direction filter, default view

**Files:**
- Create: `modules/LedgerFormat.lua`; add to `LootHistory.toc` directly before `modules\Browser.lua`
- Modify: `modules/BrowserTable.lua:163-232` (COLUMNS: `dir` after `time`; `qty` signed), `:245` (`NUMERIC_SORT`), `:273-314` (`GROUP_OF`/`GROUP_COLUMN`/`GROUP_PREFIX`), `:782-788` (`BuildRow`: mono face), `:1129-1142` (`BindRow`: colors)
- Modify: `modules/Browser.lua:222-230` (`GROUP_OPTIONS`), `:249-255` (`STOCK_VIEW` comment), `:418-430` (`qualityOptions` "all" label), `:573-576` (`VIEW_FILTERS`), `:624-642` (`applyDropdowns`/`resolveFilter`), `:720-800` (`BuildFilterBar`: `dd.dir` in row 1; `dd.quality.onMultiSelect`), `:1240` (`OnSettingsChanged`)
- Modify: `defaults/Profile.lua` (`showTransfers = false`); `settings/Schema.lua` (`settings.showTransfers` row; relabel `settings.qualityThreshold`, F5)
- Create: `tests/test_ledgerformat.lua`; register `"test_ledgerformat"` after `"test_ledger"` in `tests/run.lua`
- Test: `tests/test_browsertable.lua`, `tests/test_browser.lua` (append)

**Interfaces:**
- Consumes: `NS.Constants.DirGlyph/DirRGB/DirLabel/GOLD_RGB/WARBAND_HOLDER/FONT_MONO` (Task 1 + existing), `NS.Util.RowDir/RowKind/RowHolder` (Phase 1), `NS.Ledger.Signed` (Task 2), query fields `dir`/`minQuality`/`minQualityExempt` (Task 4).
- Produces:
  - `NS.LedgerFormat.Glyph(dir)`, `.Color(dir) -> r,g,b`, `.QtyText(row)`, `.QtyColor(row) -> r,g,b`, `.SignedQty(row)`, `.SignedCount(n)`, `.SignedMoney(copper)`, `.HolderLabel(holder)` — pure; **Phase 3 Timeline reuses `SignedCount`/`SignedMoney`/`HolderLabel`.**
  - BrowserTable column `dir` (mono face), group-by modes `"dir"` and `"holder"`.
  - Browser filter field `dir` (multi-select: Gains/Losses/Transfers); stock view = Gains + Losses (+ Transfers when `settings.showTransfers`); stock/legacy views apply `minQuality = settings.qualityThreshold` (+ whitelist exempt) until a Quality selection is made; `B._defaultDirSet()`, `B._applyQualityFloor(filter)`.
  - Setting `settings.showTransfers` (bool, default false).

- [ ] **Step 1: Write the failing tests** — `tests/test_ledgerformat.lua`:

```lua
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local F = function() return NS.LedgerFormat end

test("LedgerFormat: glyph and color per direction, legacy reads as a gain", function()
  assertEqual(F().Glyph("OUT"), NS.Constants.DirGlyph.OUT)
  assertEqual(F().Glyph(nil), NS.Constants.DirGlyph.IN)
  local r, g, b = F().Color("OUT")
  assertEqual(r, 1.00); assertEqual(g, 0.33); assertEqual(b, 0.33)
end)

test("LedgerFormat: quantity text is signed; transfers unsigned; gold as money", function()
  assertEqual(F().QtyText({ itemID = 1, quantity = 3 }), "+3")
  assertEqual(F().QtyText({ itemID = 1, quantity = 3, dir = "OUT" }), "-3")
  assertEqual(F().QtyText({ itemID = 1, quantity = 3, dir = "MOVE" }), "3")
  assertEqual(F().QtyText({ kind = "GOLD", dir = "OUT", quantity = 10203 }), "-" .. NS.Util.FormatMoney(10203))
  assertEqual(F().SignedQty({ dir = "OUT", quantity = 4 }), -4)
end)

test("LedgerFormat: gold quantity is pale gold; others take the direction color", function()
  local r, g, b = F().QtyColor({ kind = "GOLD", dir = "OUT", quantity = 1 })
  assertEqual(r, NS.Constants.GOLD_RGB[1]); assertEqual(b, NS.Constants.GOLD_RGB[3])
  r = F().QtyColor({ itemID = 1, dir = "IN" })
  assertEqual(r, 0.35)
end)

test("LedgerFormat: signed count and money; zero is a gray dash", function()
  assertEqual(F().SignedCount(3), "|cff40ff40+3|r")
  assertEqual(F().SignedCount(-2), "|cffff4040-2|r")
  assertTrue(F().SignedCount(0):find("\226\128\148", 1, true) ~= nil)
  assertEqual(F().SignedMoney(-500), "|cffff4040-" .. NS.Util.FormatMoney(500) .. "|r")
end)

test("LedgerFormat: the warband holder reads as Warband", function()
  assertEqual(F().HolderLabel("§warband"), "Warband")
  assertEqual(F().HolderLabel("A-Realm"), "A-Realm")
end)
```

Append to `tests/test_browsertable.lua`:

```lua
test("BrowserTable: a Direction column follows Time and draws in the mono face", function()
  local cols = NS.BrowserTable.COLUMNS
  assertEqual(cols[2].key, "time"); assertEqual(cols[3].key, "dir")
  assertTrue(cols[3].mono)
  assertEqual(cols[3].valueFn({ dir = "MOVE" }), NS.Constants.DirGlyph.MOVE)
end)

test("BrowserTable: the Qty column shows signed quantities", function()
  local qty
  for _, c in ipairs(NS.BrowserTable.COLUMNS) do if c.key == "qty" then qty = c end end
  assertEqual(qty.valueFn({ quantity = 2, dir = "OUT" }), "-2")
  assertEqual(qty.sortFn({ quantity = 2, dir = "OUT" }), -2)
end)

test("BrowserTable: group by Direction and by Holder", function()
  local BT = NS.BrowserTable
  local saved = BT.groupBy
  local rows = { { dir = "OUT", char = "A-Realm" }, { char = "A-Realm" },
                 { dir = "MOVE", char = "A-Realm", holder = "§warband" } }
  BT.groupBy = "dir"
  local labels = {}
  for _, e in ipairs(BT:GroupRecords(rows)) do if e.kind == "header" then labels[#labels + 1] = e.label end end
  table.sort(labels)
  assertEqual(table.concat(labels, "|"), "Direction: Gain|Direction: Loss|Direction: Transfer")
  BT.groupBy = "holder"
  labels = {}
  for _, e in ipairs(BT:GroupRecords(rows)) do if e.kind == "header" then labels[#labels + 1] = e.label end end
  table.sort(labels)
  assertEqual(table.concat(labels, "|"), "Holder: A-Realm|Holder: Warband")
  BT.groupBy = saved
end)
```

Append to `tests/test_browser.lua` (inside its existing `withFixture` pattern):

```lua
test("Browser: the stock view shows gains and losses, transfers per setting", function()
  withFixture(FIXTURE, function()
    B._dd = nil
    NS.db.profile.settings.showTransfers = false
    B:ApplyView(B._stockView, "all")
    local f = B:CurrentFilter()
    assertTrue(f.dir.IN and f.dir.OUT); assertEqual(f.dir.MOVE, nil)
    NS.db.profile.settings.showTransfers = true
    B:ApplyView(B._stockView, "all")
    assertTrue(B:CurrentFilter().dir.MOVE)
    NS.db.profile.settings.showTransfers = false
    B:ApplyView({ dir = {}, date = "all" }, "all")
    assertEqual(B:CurrentFilter().dir, nil, "a saved empty set is All")
    B:ApplyView(B._stockView, "all")
  end)
end)

test("Browser: the default view floors items at the minimum-quality setting", function()
  withFixture(FIXTURE, function()
    B._dd = nil
    NS.db.profile.settings.qualityThreshold = 2
    NS.db.profile.whitelist = { [42] = true }
    B:ApplyView(B._stockView, "all")
    local f = B:CurrentFilter()
    assertEqual(f.minQuality, 2); assertTrue(f.minQualityExempt[42])
    B:ApplyView({ quality = { [0] = true }, date = "all" }, "all")
    assertEqual(B:CurrentFilter().minQuality, nil, "an explicit quality selection replaces the floor")
    NS.db.profile.settings.qualityThreshold = 1
    NS.db.profile.whitelist = {}
    B:ApplyView(B._stockView, "all")
  end)
end)

test("Browser: the Quality 'all' option names the floor", function()
  withFixture(FIXTURE, function()
    NS.db.profile.settings.qualityThreshold = 2
    local all = B._options.quality()[1]
    assertEqual(all.value, "all")
    assertEqual(all.label, "Quality: " .. NS.Item.QualityLabel(2) .. "+")
    NS.db.profile.settings.qualityThreshold = 0
    assertEqual(B._options.quality()[1].label, "Quality: All")
    NS.db.profile.settings.qualityThreshold = 1
  end)
end)

test("Browser: group options offer Direction and Holder", function()
  local seen = {}
  for _, o in ipairs(B._groupOptions) do seen[o.value] = true end
  assertTrue(seen.dir and seen.holder)
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -E "FAIL" | head -20`
Expected: FAIL — `NS.LedgerFormat` nil; no `dir` column; `f.dir` nil.

- [ ] **Step 3: Implement** — `modules/LedgerFormat.lua`:

```lua
local _, NS = ...
NS.LedgerFormat = NS.LedgerFormat or {}
local F = NS.LedgerFormat

-- Pure display helpers for ledger rows (History, Insights, and the Phase 3 Timeline). No frames.
-- Signed styling is BankLedger's (InsightsWidgets SignedCount/SignedMoney): green +N, red -N, a
-- gray em dash for exactly zero, which is a real answer rather than a missing one.

local C = NS.Constants
local DASH = "\226\128\148"

function F.Glyph(dir) return C.DirGlyph[dir or "IN"] or "" end

function F.Color(dir)
  local c = C.DirRGB[dir or "IN"] or C.DirRGB.MOVE
  return c[1], c[2], c[3]
end

function F.SignedQty(r) return NS.Ledger.Signed(NS.Util.RowDir(r), r.quantity or 1) end

-- Plain text (the cell color carries the direction). ASCII "-" because the default font has no
-- U+2212; a transfer is unsigned, it is neither a gain nor a loss.
function F.QtyText(r)
  local dir, q = NS.Util.RowDir(r), r.quantity or 1
  local sign = (dir == "IN" and "+") or (dir == "OUT" and "-") or ""
  if NS.Util.RowKind(r) == "GOLD" then return sign .. NS.Util.FormatMoney(q) end
  return sign .. tostring(q)
end

function F.QtyColor(r)
  if NS.Util.RowKind(r) == "GOLD" then local g = C.GOLD_RGB; return g[1], g[2], g[3] end
  return F.Color(NS.Util.RowDir(r))
end

function F.SignedCount(n)
  n = n or 0
  if n == 0 then return "|cff808080" .. DASH .. "|r" end
  if n > 0 then return "|cff40ff40+" .. n .. "|r" end
  return "|cffff4040-" .. (-n) .. "|r"
end

function F.SignedMoney(copper)
  copper = copper or 0
  if copper == 0 then return "|cff808080" .. DASH .. "|r" end
  if copper > 0 then return "|cff40ff40+" .. NS.Util.FormatMoney(copper) .. "|r" end
  return "|cffff4040-" .. NS.Util.FormatMoney(-copper) .. "|r"
end

function F.HolderLabel(h)
  if h == C.WARBAND_HOLDER then return "Warband" end
  return h or ""
end
```

`modules/BrowserTable.lua`:

Insert after the `time` column:

```lua
  -- Direction (timeline-ledger spec §7). The glyphs exist only in the mono face (`mono`, BuildRow);
  -- the default font draws them as boxes. Color comes from BindRow.
  { key = "dir", label = "", width = 18, align = "CENTER", mono = true,
    desc = "Direction: green up = gain, red down = loss, gray arrows = transfer between your own containers or characters.",
    valueFn = function(r) return NS.LedgerFormat.Glyph(NS.Util.RowDir(r)) end,
    sortFn = function(r) return DIR_RANK[NS.Util.RowDir(r)] or 0 end },
```

with, above `BrowserTable.COLUMNS`:

```lua
local DIR_RANK = { IN = 1, OUT = 2, MOVE = 3 }
```

Replace the `qty` column:

```lua
  { key = "qty", label = "Qty", width = 34, align = "RIGHT",
    desc = "Quantity: + gained, - lost, unsigned for a transfer. Gold rows show the amount.",
    valueFn = function(r) return NS.LedgerFormat.QtyText(r) end,
    sortFn = function(r) return NS.LedgerFormat.SignedQty(r) end },
```

`NUMERIC_SORT`: add `dir = true`.

`GROUP_OF` — add:

```lua
  dir = function(r)
    local d = NS.Util.RowDir(r)
    return d, C.DirLabel[d] or d
  end,
  holder = function(r)
    local h = NS.Util.RowHolder(r) or "Unknown"
    return h, NS.LedgerFormat.HolderLabel(h)
  end,
```

`GROUP_COLUMN`: add `dir = "dir"`. `GROUP_PREFIX`: add `dir = "Direction", holder = "Holder"`.

`BuildRow`, inside the per-column loop after `fs:SetWordWrap(false)`:

```lua
    if col.mono then fs:SetFont(C.FONT_MONO, 12, "") end
```

`BindRow`, extend the color branch:

```lua
    elseif col.key == "dir" then
      fs:SetTextColor(NS.LedgerFormat.Color(NS.Util.RowDir(r)))
    elseif col.key == "qty" then
      fs:SetTextColor(NS.LedgerFormat.QtyColor(r))
```

`modules/Browser.lua`:

`GROUP_OPTIONS` — append `{ value = "dir", label = "Group: Direction" }, { value = "holder", label = "Group: Holder" },` and publish `B._groupOptions = GROUP_OPTIONS` beside the other `B._*` test seams.

Below `BOUND_ORDER`:

```lua
local DIR_OPTIONS = {
  { value = "all",  label = "Direction: All" },
  { value = "IN",   label = "Gains" },
  { value = "OUT",  label = "Losses" },
  { value = "MOVE", label = "Transfers" },
}

-- The Direction filter's default (spec §7): gains and losses; transfers only when the player asked
-- for them in settings. Applied to a view that never stored a `dir` (the stock view, and every view
-- saved before the ledger existed); a stored empty set means "All".
local function defaultDirSet()
  local s = NS.db and NS.db.profile and NS.db.profile.settings
  return { IN = true, OUT = true, MOVE = (s and s.showTransfers) and true or nil }
end

-- The minimum-quality setting is also the default History view's floor (spec §5.3, F5): items
-- below it are captured now, but hidden until the player picks qualities explicitly. Whitelisted
-- ids are exempt, exactly as they were exempt from the capture gate.
local function applyQualityFloor(f)
  local p = NS.db and NS.db.profile
  local t = p and p.settings and p.settings.qualityThreshold
  if f.quality or type(t) ~= "number" or t <= 0 then
    f.minQuality, f.minQualityExempt = nil, nil
  else
    f.minQuality, f.minQualityExempt = t, p.whitelist
  end
end

local VIEW_DEFAULTS = { dir = defaultDirSet }

-- A view field as a selection set: the stored set, or the field's default when the view never
-- stored one.
local function viewSet(view, key)
  local v = view[key]
  if v == nil and VIEW_DEFAULTS[key] then return VIEW_DEFAULTS[key]() end
  return asSet(v)
end
```

(`viewSet` must sit below `asSet`; place this block right after `asSet`.) Publish `B._defaultDirSet = defaultDirSet` and `B._applyQualityFloor = applyQualityFloor`.

`qualityOptions` — replace `table.insert(items, 1, { value = "all", label = "Quality: All" })` with:

```lua
  local t = NS.db and NS.db.profile and NS.db.profile.settings and NS.db.profile.settings.qualityThreshold
  local allLabel = (type(t) == "number" and t > 0) and ("Quality: " .. NS.Item.QualityLabel(t) .. "+") or "Quality: All"
  table.insert(items, 1, { value = "all", label = allLabel })
```

`VIEW_FILTERS` — append `{ "dir", "dir" }`.

`applyDropdowns` — change the loop body to `dd[f[2]]:SetSelected(viewSet(view, f[1]))`.

`resolveFilter` — change the loop body to `self.activeFilter[vk] = setToFilter(viewSet(view, vk))` and add after the loop:

```lua
  applyQualityFloor(self.activeFilter)
```

`BuildFilterBar`, row 1 — after `dd.group`'s setup and before the `search` box:

```lua
  -- Direction (multi-select), between Group and Search: row 2's span is the toolbar's width floor
  -- (DROPDOWNS_W), so a ninth row-2 dropdown would widen the minimum window by 104 px; row 1's
  -- search box absorbs it instead.
  dd.dir = NS.MakeDropdown(bar, 104)
  dd.dir:SetPoint("LEFT", dd.group, "RIGHT", 8, 0)
  dd.dir:SetMulti(true)
  dd.dir:SetOptions(DIR_OPTIONS)
  dd.dir.onMultiSelect = function(set)
    B.activeFilter.dir = setToFilter(set)
    ApplyFilter()
  end
```

and anchor the search box to it: `search:SetPoint("TOPLEFT", dd.dir, "TOPRIGHT", 8, 0)` (replacing `dd.group`). Update the row-1 comment to "Group by · Direction · [search…] · Save · Reset · Clear".

`dd.quality.onMultiSelect`:

```lua
  dd.quality.onMultiSelect = function(set)
    B.activeFilter.quality = setToFilter(set)
    applyQualityFloor(B.activeFilter)
    ApplyFilter()
  end
```

`B:OnSettingsChanged` — append (the floor follows the setting live while the window is up):

```lua
  if frame and frame:IsShown() and B.activeFilter then
    applyQualityFloor(B.activeFilter)
    if B._dd and B._dd.quality then B._dd.quality:SetOptions(qualityOptions()) end
    ApplyFilter()
  end
```

`defaults/Profile.lua` settings: `showTransfers    = false,  -- History's Direction filter includes transfers by default`.

`settings/Schema.lua` — relabel the min-quality row (F5) and add the transfers row in group "History":

```lua
  { path = "settings.qualityThreshold", default = PD.settings.qualityThreshold, type = "number", widget = "Dropdown",
    page = "General", group = "Capture", label = "Minimum quality (detailed records)", values = C.QUALITY_OPTIONS,
    tooltip = "Items at or above this quality get a detailed loot record (source, zone, encounter). " ..
      "Every item is still tracked in the ledger; History hides items below this quality until you " ..
      "pick qualities in its Quality filter.",
    onChange = function()
      if NS.bus then NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "quality") end
    end },
```

```lua
  { path = "settings.showTransfers", default = PD.settings.showTransfers, type = "bool", widget = "CheckBox",
    page = "General", group = "History", label = "Show transfers by default",
    tooltip = "Include transfers (bank deposits, warband moves, mail to your alts) in History's " ..
      "default Direction filter. Applies the next time the default view is loaded (Clear or reopen).",
    onChange = function()
      if NS.bus then NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "view") end
    end },
```

> The default floor hides quality-0 items under the stock view. If an existing `tests/test_browser.lua` / `tests/test_browsertable.lua` case counts rows under the stock view over a fixture with Poor items, set `NS.db.profile.settings.qualityThreshold = 0` inside that case (it is testing the table, not the floor) and say so in a comment. `wc -l modules/Browser.lua` must stay ≤ 1400.

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS, 0/0. `test_schema` may pin the min-quality label; update it to the new text.

- [ ] **Step 5: Commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add modules/LedgerFormat.lua modules/BrowserTable.lua modules/Browser.lua LootHistory.toc defaults/Profile.lua settings/Schema.lua tests/test_ledgerformat.lua tests/test_browsertable.lua tests/test_browser.lua tests/test_schema.lua tests/run.lua docs/test-cases.md
git commit -m "feat(history): Direction column and filter, signed quantities, group by direction/holder, min-quality view floor" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt"
```

---

### Task 12: Insights — Gained / Lost / Net, gains vs losses, pre-ledger caveat, Insights CSV

**Files:**
- Create: `modules/AnalyticsLedger.lua`; add to `LootHistory.toc` directly after `modules\AnalyticsCharts.lua`
- Modify: `modules/Analytics.lua:22-33` (`CARD_DEFS`), `:62-77` (Attach: keep each card's label FontString), `:120-138` (`UpdateCards`), `:174-237` (`BuildCharts`: `Analytics._ledger.Build`), `:621-649` (`LayoutCharts`: ledger section first; empty-state rule; LOOT sections only with gains)
- Modify: `modules/AnalyticsCharts.lua:398-404` (`HideAllCharts` hides the ledger UI)
- Modify: `modules/Export.lua:305-315` (`InsightsCSV`: `emitLedger` last)
- Test: `tests/test_analytics.lua` (append), `tests/test_analytics_layout.lua` (`layout` helper pins `resetPrompt = nil`; append a ledger case), `tests/test_export.lua` (append)

**Interfaces:**
- Consumes: `Stats().ledger` (Task 4), `NS.LedgerFormat.SignedCount/SignedMoney/HolderLabel` (Task 11), `NS.Constants.DirRGB/SourceLabel` (Task 1), `db.global.resetPrompt` / `db.global.ledgerSince` (Phase 1), `NS.Pool`.
- Produces:
  - `NS.Analytics._ledger.Caveat(resetPrompt, ledgerSince, preLedgerRows) -> string|nil`
  - `NS.Analytics._ledger.BackToBackRows(inMap, outMap, labelOf, labelColorOf, signedFmt, plainFmt) -> rows` (`{ key, label, labelColor, leftFrac, rightFrac, total, value, leftTip, rightTip }`, shared peak scale, sorted total desc then label)
  - `NS.Analytics._ledger.HasLedger(stats) -> boolean` (any loss or transfer in range)
  - `NS.Analytics._ledger.Build(inst, content)`, `.Layout(inst, stats, y, w, pad) -> y`, `.Hide(inst)`; chrome lives in `inst.ledgerUI` (deliberately **not** in `inst.headers` / `inst.pool`, which the golden snapshot walks).
  - Cards `gained`, `lost`, `net`, `moved`.
  - Insights CSV sections `Ledger`, `Gains by Reason`, `Losses by Reason` (only when `HasLedger`).

- [ ] **Step 1: Write the failing tests** — append to `tests/test_analytics.lua`:

```lua
local AL = function() return NS.Analytics._ledger end

test("Insights ledger: the caveat shows only for kept history with pre-ledger rows", function()
  assertEqual(AL().Caveat(nil, 1000, 5), nil)
  assertEqual(AL().Caveat("reset", 1000, 5), nil)
  assertEqual(AL().Caveat("kept", 1000, 0), nil)
  local text = AL().Caveat("kept", 1000, 5)
  assertTrue(text:find(NS.Util.FormatDate(1000), 1, true) ~= nil)
  assertTrue(text:find("only gains were recorded", 1, true) ~= nil)
end)

test("Insights ledger: back-to-back rows share one peak and sort by total", function()
  local rows = AL().BackToBackRows({ SELL = 4, KILL = 10 }, { SELL = 8, REPAIR = 2 },
    function(k) return k end, nil, NS.LedgerFormat.SignedCount, tostring)
  assertEqual(rows[1].key, "SELL"); assertEqual(rows[2].key, "KILL"); assertEqual(rows[3].key, "REPAIR")
  assertEqual(rows[1].rightFrac, 0.4); assertEqual(rows[1].leftFrac, 0.8)
  assertEqual(rows[2].rightFrac, 1.0)
  assertEqual(rows[1].value, NS.LedgerFormat.SignedCount(-4))
  assertEqual(rows[1].leftTip, "Lost: 8"); assertEqual(rows[1].rightTip, "Gained: 4")
end)

test("Insights ledger: HasLedger is false for gains-only ranges", function()
  assertEqual(AL().HasLedger({ ledger = { lostCount = 0, movedCount = 0 } }), false)
  assertEqual(AL().HasLedger({ ledger = { lostCount = 1, movedCount = 0 } }), true)
  assertEqual(AL().HasLedger({}), false)
end)
```

In `tests/test_analytics_layout.lua`, change the `layout` helper so every golden case runs with no caveat:

```lua
local function layout(inst, stats)
  local savedCF = mocks.CreateFrame
  local g = NS.db.global
  local savedRP = g.resetPrompt
  g.resetPrompt = nil                       -- the pre-ledger caveat is pinned by its own case
  mocks.CreateFrame = recordingCreateFrame()
  inst.stats = stats
  local ok, y = pcall(inst.LayoutCharts, inst, -100, 780, 8)
  mocks.CreateFrame = savedCF
  g.resetPrompt = savedRP
  if not ok then error(y, 0) end
  return y
end
```

and append:

```lua
test("Insights layout: a range with losses draws the gains-vs-losses section first", function()
  local T1 = 1600000000
  local stats = statsFor({
    { ts = T1, char = "A-Realm", classFile = "MAGE", itemID = 10, itemName = "Sword", quality = 4, source = "KILL", quantity = 1, vendorPrice = 100 },
    { ts = T1, char = "A-Realm", classFile = "MAGE", itemID = 11, itemName = "Potion", quality = 1, source = "CONSUME",
      dir = "OUT", kind = "ITEM", quantity = 5, vendorPrice = 10 },
    { ts = T1, char = "A-Realm", classFile = "MAGE", kind = "GOLD", itemName = "Gold", source = "REPAIR", dir = "OUT", quantity = 300 },
  })
  local inst = newInstance()
  local y = layout(inst, stats)
  local ui = inst.ledgerUI
  assertTrue(ui.divider.__shown, "the GAINS & LOSSES divider is shown")
  assertTrue(ui.headers.reason.__shown)
  assertEqual(#ui.pools.reason.active, 3)                 -- KILL, CONSUME, REPAIR
  assertTrue(inst.lootDivider.__shown, "the LOOT sections still draw for the gain")
  assertTrue(y < -100)
  -- Drawn above LOOT: the divider's anchor y is above the loot divider's.
  assertTrue(ui.divider:__lastPoint().y > inst.lootDivider:__lastPoint().y)
end)

test("Insights layout: losses only — no empty text, no LOOT divider", function()
  local stats = statsFor({
    { ts = 1600000000, char = "A-Realm", classFile = "MAGE", kind = "GOLD", itemName = "Gold", source = "REPAIR", dir = "OUT", quantity = 300 },
  })
  local inst = newInstance()
  layout(inst, stats)
  assertTrue(not inst.emptyText.__shown)
  assertTrue(not inst.lootDivider.__shown)
  assertTrue(inst.ledgerUI.divider.__shown)
end)
```

Append to `tests/test_export.lua`:

```lua
test("Export: InsightsCSV appends Ledger sections only when the range has losses", function()
  local stats = NS.Database:Stats({})            -- whatever is loaded; force a ledger table below
  stats.ledger = { gainedCount = 2, lostCount = 1, movedCount = 0, gainedValue = 800, lostValue = 300,
    netCount = 1, netValue = 500, reasonIn = { KILL = 2 }, reasonOut = { REPAIR = 1 },
    valueReasonIn = { KILL = 800 }, valueReasonOut = { REPAIR = 300 } }
  local csv = NS.Export:InsightsCSV(stats)
  assertTrue(csv:find("Ledger,Net,1,500", 1, true) ~= nil)
  assertTrue(csv:find("Losses by Reason,Repair,1,300", 1, true) ~= nil)
  stats.ledger.lostCount = 0
  assertTrue(NS.Export:InsightsCSV(stats):find("Ledger,", 1, true) == nil)
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -E "FAIL" | head -20`
Expected: FAIL — `NS.Analytics._ledger` nil.

- [ ] **Step 3: Implement** — `modules/AnalyticsLedger.lua`:

```lua
local _, NS = ...
NS.Analytics = NS.Analytics or {}
local Analytics = NS.Analytics

-- The Insights tab's ledger half (timeline-ledger spec §6): a GAINS & LOSSES divider, the
-- pre-ledger caveat, and three back-to-back charts (by reason, by character, by kind) — losses grow
-- left of a fixed center axis in red, gains right in green, one shared scale per chart (BankLedger
-- InsightsWidgets BuildBackToBackRows / PeakShares). Drawn only when the range holds a loss or a
-- transfer, so a gains-only range (every legacy history) renders exactly as before.
--
-- Its chrome lives in inst.ledgerUI, NOT in inst.headers / inst.pool: the golden snapshot in
-- tests/test_analytics_layout.lua walks those two tables, and this section is pinned by its own cases.

local AL = {}
Analytics._ledger = AL

local C = NS.Constants
local BAR_H, BAR_GAP, LABEL_W, VALUE_W, SECTION_GAP = 16, 4, 130, 110, 14

-- ── Pure ────────────────────────────────────────────────────────────────────────────────────

function AL.HasLedger(stats)
  local L = stats and stats.ledger
  return L ~= nil and ((L.lostCount or 0) > 0 or (L.movedCount or 0) > 0)
end

function AL.Caveat(resetPrompt, ledgerSince, preLedgerRows)
  if resetPrompt ~= "kept" or not ledgerSince or (preLedgerRows or 0) == 0 then return nil end
  return ("Before %s only gains were recorded \226\128\148 totals for that period overstate net.")
    :format(NS.Util.FormatDate(ledgerSince))
end

function AL.BackToBackRows(inMap, outMap, labelOf, labelColorOf, signedFmt, plainFmt)
  inMap, outMap = inMap or {}, outMap or {}
  local keys, seen = {}, {}
  for _, m in ipairs({ inMap, outMap }) do
    for k in pairs(m) do if not seen[k] then seen[k] = true; keys[#keys + 1] = k end end
  end
  local peak = 0
  for _, k in ipairs(keys) do peak = math.max(peak, inMap[k] or 0, outMap[k] or 0) end
  local rows = {}
  for _, k in ipairs(keys) do
    local i, o = inMap[k] or 0, outMap[k] or 0
    rows[#rows + 1] = {
      key = k, label = labelOf(k), labelColor = labelColorOf and labelColorOf(k) or nil,
      rightFrac = peak > 0 and i / peak or 0, leftFrac = peak > 0 and o / peak or 0,
      total = i + o, value = signedFmt(i - o),
      rightTip = "Gained: " .. plainFmt(i), leftTip = "Lost: " .. plainFmt(o),
    }
  end
  table.sort(rows, function(a, b)
    if a.total ~= b.total then return a.total > b.total end
    return tostring(a.label) < tostring(b.label)
  end)
  return rows
end

-- ── Widgets ─────────────────────────────────────────────────────────────────────────────────

local function makeBar(parent)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(BAR_H)
  bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.label:SetJustifyH("LEFT")
  bar.value = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.value:SetJustifyH("RIGHT")
  bar.track = bar:CreateTexture(nil, "BACKGROUND")
  bar.track:SetColorTexture(1, 1, 1, 0.06)
  bar.axis = bar:CreateTexture(nil, "OVERLAY")
  bar.axis:SetColorTexture(0.55, 0.55, 0.60, 0.9)
  bar.left = bar:CreateTexture(nil, "ARTWORK")
  bar.right = bar:CreateTexture(nil, "ARTWORK")
  bar:EnableMouse(true)
  bar:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:AddLine(self._fullLabel or "", 1, 0.82, 0)
    GameTooltip:AddLine(self._info or "", 0.9, 0.9, 0.9)
    GameTooltip:Show()
  end)
  bar:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return bar
end

-- Anchored to the track's CENTER, not its edges: the split sits on one vertical line in every row.
local function placeBar(bar, content, pad, y, w, row)
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", content, "TOPLEFT", pad, y)
  bar:SetWidth(w)
  bar.label:ClearAllPoints(); bar.label:SetPoint("LEFT", bar, "LEFT", 0, 0); bar.label:SetWidth(LABEL_W)
  bar.value:ClearAllPoints(); bar.value:SetPoint("RIGHT", bar, "RIGHT", 0, 0); bar.value:SetWidth(VALUE_W)
  local trackW = math.max(2, w - LABEL_W - VALUE_W - 12)
  local half = trackW / 2
  bar.track:ClearAllPoints(); bar.track:SetPoint("LEFT", bar, "LEFT", LABEL_W + 6, 0)
  bar.track:SetSize(trackW, BAR_H - 4)
  bar.axis:ClearAllPoints(); bar.axis:SetPoint("CENTER", bar.track, "CENTER", 0, 0)
  bar.axis:SetSize(1, BAR_H - 2)
  local out, gain = C.DirRGB.OUT, C.DirRGB.IN
  local lw, rw = half * row.leftFrac, half * row.rightFrac
  bar.left:ClearAllPoints(); bar.left:SetPoint("RIGHT", bar.track, "CENTER", 0, 0)
  bar.left:SetSize(math.max(1, lw), BAR_H - 4); bar.left:SetColorTexture(out[1], out[2], out[3], 0.95)
  bar.left:SetShown(lw > 0)
  bar.right:ClearAllPoints(); bar.right:SetPoint("LEFT", bar.track, "CENTER", 0, 0)
  bar.right:SetSize(math.max(1, rw), BAR_H - 4); bar.right:SetColorTexture(gain[1], gain[2], gain[3], 0.95)
  bar.right:SetShown(rw > 0)
end

function AL.Build(inst, content)
  local charts = Analytics._charts
  inst.ledgerUI = {
    divider = charts.sectionDivider(content, "GAINS & LOSSES"),
    caveat = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"),
    headers = {
      reason = charts.sectionHeader(content, "Gains Vs Losses By Reason"),
      char   = charts.sectionHeader(content, "Gains Vs Losses By Character"),
      kind   = charts.sectionHeader(content, "Gains Vs Losses By Kind"),
    },
    pools = { reason = NS.Pool.New(), char = NS.Pool.New(), kind = NS.Pool.New() },
  }
  inst.ledgerUI.caveat:SetJustifyH("LEFT")
  inst.ledgerUI.caveat:SetTextColor(1, 0.82, 0)
  AL.Hide(inst)
end

function AL.Hide(inst)
  local ui = inst.ledgerUI
  if not ui then return end
  ui.divider:Hide(); ui.caveat:Hide()
  for _, h in pairs(ui.headers) do h:Hide() end
end

local function section(inst, key, rows, y, w, pad)
  local ui = inst.ledgerUI
  local header = ui.headers[key]
  if #rows == 0 then header:Hide(); return y end
  header:ClearAllPoints(); header:SetPoint("TOPLEFT", inst.content, "TOPLEFT", pad, y); header:Show()
  y = y - 18
  for _, row in ipairs(rows) do
    local bar = NS.Pool.Acquire(ui.pools[key], function() return makeBar(inst.content) end)
    bar._fullLabel = tostring(row.label)
    bar._info = row.rightTip .. "   " .. row.leftTip
    bar.label:SetText(row.label)
    local lc = row.labelColor
    bar.label:SetTextColor(lc and lc[1] or 0.9, lc and lc[2] or 0.9, lc and lc[3] or 0.9)
    bar.value:SetText(row.value)
    placeBar(bar, inst.content, pad, y, w - pad * 2, row)
    bar:Show()
    y = y - (BAR_H + BAR_GAP)
  end
  return y - SECTION_GAP
end

local KIND_LABEL = { ITEM = "Items", CURRENCY = "Currency", GOLD = "Gold" }

function AL.Layout(inst, stats, y, w, pad)
  local ui = inst.ledgerUI
  for _, p in pairs(ui.pools) do NS.Pool.ReleaseAll(p) end
  local g = NS.db and NS.db.global or {}
  local note = AL.Caveat(g.resetPrompt, g.ledgerSince, stats.ledger and stats.ledger.preLedgerRows)
  if note then
    ui.caveat:ClearAllPoints(); ui.caveat:SetPoint("TOPLEFT", inst.content, "TOPLEFT", pad, y)
    ui.caveat:SetText(note); ui.caveat:Show()
    y = y - 18
  else
    ui.caveat:Hide()
  end
  if not AL.HasLedger(stats) then AL.Hide(inst); if note then ui.caveat:Show() end; return y end
  ui.divider:ClearAllPoints()
  ui.divider:SetPoint("TOPLEFT", inst.content, "TOPLEFT", pad, y)
  ui.divider:SetPoint("TOPRIGHT", inst.content, "TOPRIGHT", -pad, y)
  ui.divider:Show()
  y = y - 30
  local L, LF = stats.ledger, NS.LedgerFormat
  local function srcLabel(k) return C.SourceLabel[k] or k end
  local function classOf(ch) local ce = stats.byChar and stats.byChar[ch]; return ce and ce.classFile end
  local function charColor(ch)
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classOf(ch) or ""]
    return cc and { cc.r, cc.g, cc.b } or nil
  end
  y = section(inst, "reason", AL.BackToBackRows(L.reasonIn, L.reasonOut, srcLabel, nil, LF.SignedCount, tostring), y, w, pad)
  y = section(inst, "char", AL.BackToBackRows(L.charIn, L.charOut, function(k) return (k:match("^[^-]+") or k) end,
    charColor, LF.SignedMoney, function(v) return NS.Util.FormatMoney(v) end), y, w, pad)
  y = section(inst, "kind", AL.BackToBackRows(L.kindIn, L.kindOut, function(k) return KIND_LABEL[k] or k end,
    nil, LF.SignedCount, tostring), y, w, pad)
  return y
end
```

`modules/Analytics.lua`:

`CARD_DEFS` — append:

```lua
  -- The ledger row (timeline-ledger spec §6): value with the row count in the caption, signed.
  { key = "gained", label = "gained", str = true, bigStr = true },
  { key = "lost",   label = "lost",   str = true, bigStr = true },
  { key = "net",    label = "net",    str = true, bigStr = true },
  { key = "moved",  label = "transfers" },
```

In `Attach`, store the caption: `local entry = { frame = card, num = num, bigStr = def.bigStr, caption = cl, captionBase = def.label }`.

`UpdateCards` — append:

```lua
  local L, LF = stats.ledger or {}, NS.LedgerFormat
  local function cap(key, n) local c = self.cards[key]; c.caption:SetText(c.captionBase .. " \194\183 " .. tostring(n or 0)) end
  self.cards.gained.num:SetText(LF.SignedMoney(L.gainedValue or 0)); cap("gained", L.gainedCount)
  self.cards.lost.num:SetText(LF.SignedMoney(-(L.lostValue or 0)));   cap("lost", L.lostCount)
  self.cards.net.num:SetText(LF.SignedMoney(L.netValue or 0))
  self.cards.net.caption:SetText("net \194\183 " .. LF.SignedCount(L.netCount or 0))
  self.cards.moved.num:SetText(tostring(L.movedCount or 0))
```

`BuildCharts` — after the pools table: `Analytics._ledger.Build(self, content)`.

`LayoutCharts` — replace the empty check and the LOOT block:

```lua
  local AL = Analytics._ledger
  local hasLoot = stats and stats.totals.records > 0
  if not stats or (not hasLoot and not AL.HasLedger(stats)) then
    self:HideAllCharts()
    self.emptyText:ClearAllPoints()
    self.emptyText:SetPoint("TOP", self.content, "TOP", 0, y - 10)
    self.emptyText:Show()
    return y - 50
  end
  self.emptyText:Hide()

  y = AL.Layout(self, stats, y, w, pad)
  if hasLoot then
    y = placeDivider(self, self.lootDivider, y, pad)
    for _, section in ipairs(LOOT_SECTIONS) do y = section(self, stats, y, w, pad) end
  else
    self.lootDivider:Hide()
    for _, h in pairs(self.headers) do h:Hide() end
  end
```

(the currency block below is unchanged; with no loot it hides itself via `hideCurrency`).

`modules/AnalyticsCharts.lua` `HideAllCharts` — append `if Analytics._ledger then Analytics._ledger.Hide(self) end`.

`modules/Export.lua` — above `E:InsightsCSV`:

```lua
-- The ledger summary (timeline-ledger spec §6), appended LAST so every earlier row keeps its place
-- for an existing spreadsheet, and only when the range holds a loss or transfer: a gains-only
-- range (every legacy history) exports exactly as before.
local function emitLedger(row, stats)
  local L = stats.ledger
  if not L or ((L.lostCount or 0) == 0 and (L.movedCount or 0) == 0) then return end
  row("Ledger", "Gained", L.gainedCount, L.gainedValue)
  row("Ledger", "Lost", L.lostCount, L.lostValue)
  row("Ledger", "Net", L.netCount, L.netValue)
  row("Ledger", "Transfers", L.movedCount)
  emitSection(row, "Gains by Reason", rankedRows(L.reasonIn, insightsSourceLabel, L.valueReasonIn))
  emitSection(row, "Losses by Reason", rankedRows(L.reasonOut, insightsSourceLabel, L.valueReasonOut))
end
```

and in `E:InsightsCSV`, after `emitCurrency(row, stats)`: `emitLedger(row, stats)`.

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS, 0/0 — the analytics and export **goldens are unchanged** (their fixtures are gains-only and the caveat is pinned off). If `tests/test_analytics.lua` pins the card count, update it to 14.

- [ ] **Step 5: Commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add modules/AnalyticsLedger.lua modules/Analytics.lua modules/AnalyticsCharts.lua modules/Export.lua LootHistory.toc tests/test_analytics.lua tests/test_analytics_layout.lua tests/test_export.lua docs/test-cases.md
git commit -m "feat(insights): gained/lost/net cards, gains-vs-losses charts, pre-ledger caveat, ledger CSV rows" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt"
```

---

### Task 13: Performance harness (F2) — wire LibKa0s-Perf, retire the `performance-§12` exemption

**Files:**
- Create: `core/PerfSetup.lua`; `LootHistory.toc`: line 7 → `## SavedVariables: LootHistoryDB, LootHistoryPerfDB`, and `core\PerfSetup.lua` directly after `core\LifecycleSetup.lua` (with a LOAD-BEARING comment: above every module that takes `local Perf = NS.Perf`)
- Modify: `.luacheckrc` (`globals`: `LootHistoryPerfDB` with a comment beside `LootHistoryDB`)
- Modify: `modules/Collector.lua` (Shape A brackets `lootLine`, `currencyLine`, `moneyLine`), `modules/Attribution.lua` (`spellCast` around `OnSpellSucceeded`), `modules/Reconciler.lua` (`ledgerEvent` around `OnEvent`)
- Modify: `settings/Schema.lua` (`perf` row in `NS.COMMANDS`; rewrite the "`perf` is listed although this addon does not register it" comment), `settings/Slash.lua:196-198` (`perf = true` in `UNAVAILABLE_WITHOUT_LIB`)
- Modify: `core/LifecycleSetup.lua:20-26` ("THIS ADDON TAKES ONE HOLD TODAY" → both holds are taken)
- Modify: `docs/ARCHITECTURE.md` (delete the `performance-§12` row from `## Documented deviations`; Documentation map rows for `performance.md`, `combat-path-sweep.md`, `perf-analysis/README.md`), `docs/performance.md` (rewrite), `docs/combat-path-sweep.md` (header note), create `docs/perf-analysis/README.md`
- Create: `tests/test_perf.lua` (register after `"test_disabled"` in `tests/run.lua`), `tests/perf.lua` (offline, **not** in `SUITES`)
- Test: `tests/test_slash_degraded.lua` (append)

**Interfaces:**
- Consumes: `NS.Lifecycle` (`core/LifecycleSetup.lua`), `NS.version`, `NS.DebugLog:Add/Show`, `NS.Print`; the handlers named below.
- Produces:
  - `NS.Perf` — the `LibKa0s-Perf-1.0` instance (`on`, `Note`, `Open`, `Close`, `Suspend`, `Resume`, `suspended`, `BUCKET_ORDER`, `OnCommand`), or on a library-less install a stub `{ on = false, Note = noop, Open = noop, Close = noop, BUCKET_ORDER = {}, OnCommand = -> {"perf capture unavailable."} }`.
  - Buckets, in report order: `lootLine`, `currencyLine`, `moneyLine`, `spellCast`, `ledgerEvent` — the five handlers that run in combat. `Reconciler:Flush` is out of combat by construction and is measured by `tests/perf.lua` instead (a bucket that reads 0.000 in every capture is "a lie in every report", performance-§3).
  - `/lh perf` (live while disabled; on `LIVE_WHILE_DISABLED` already).
  - `NS.Collector._lootLine(self, msg)` — the unbracketed body, for the offline zero-overhead scenario.

- [ ] **Step 1: Write the failing test** — `tests/test_perf.lua`

```lua
-- tests/test_perf.lua — the addon's wiring into LibKa0s-Perf-1.0 (core/PerfSetup.lua): every declared
-- bucket is reached by a real bracket, a dormant probe records nothing, and suspend makes the addon
-- inert without a reload (performance-§1..§6).
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local m = T.mocks
local LINK = "|cffa335ee|Hitem:211296::::::::80:::::|h[Vial of Fun]|h|r"

local function spyNotes()
  local seen, P = {}, NS.Perf
  local original = P.Note
  P.Note = function(key, ms, parent) seen[key] = (seen[key] or 0) + 1; return original(key, ms, parent) end
  return seen, function() P.Note = original end
end

local function exercise()
  local savedH = NS.db.global.history
  NS.db.global.history = {}
  NS.Collector:RefreshUpvalues()
  NS.Collector:OnChatMsgLoot(nil, string.format(m.LOOT_ITEM_SELF, LINK))
  NS.Collector:OnChatMsgCurrency(nil, string.format(m.CURRENCY_GAINED, "|Hcurrency:3008::|h[Valorstones]|h"))
  NS.Collector:OnChatMsgMoney(nil, "You loot 5 Copper")
  NS.Attribution:OnSpellSucceeded(nil, "player", nil, 13262)
  NS.Reconciler:OnEvent("BAG_UPDATE", 0)
  NS.db.global.history = savedH
end

test("perf: the buckets are declared in report order", function()
  assertEqual(table.concat(NS.Perf.BUCKET_ORDER, ","), "lootLine,currencyLine,moneyLine,spellCast,ledgerEvent")
end)

test("perf: every declared bucket is reached by a real bracket", function()
  local seen, restore = spyNotes()
  NS.Perf.on = true
  local ok, err = pcall(exercise)
  NS.Perf.on = false
  restore()
  if not ok then error(err, 0) end
  for _, key in ipairs(NS.Perf.BUCKET_ORDER) do
    assertTrue((seen[key] or 0) > 0, "bucket '" .. key .. "' was never noted")
  end
end)

test("perf: a dormant probe notes nothing", function()
  local seen, restore = spyNotes()
  local ok, err = pcall(exercise)
  restore()
  if not ok then error(err, 0) end
  assertEqual(next(seen), nil)
end)

test("perf: suspend makes the addon inert and resume restores it", function()
  NS.Schema:Set("settings.enabled", true)
  assertTrue(NS.addon.__events.CHAT_MSG_LOOT ~= nil, "precondition: capture is up")
  NS.Perf.Suspend()
  assertTrue(NS.Perf.suspended)
  assertEqual(NS.addon.__events.CHAT_MSG_LOOT, nil)
  assertEqual(NS.addon.__events.CHAT_MSG_MONEY, nil)
  assertEqual(NS.Reconciler.__ev, nil)
  assertEqual(NS.Attribution.__outEv, nil)
  NS.Perf.Resume()
  assertTrue(not NS.Perf.suspended)
  assertTrue(NS.addon.__events.CHAT_MSG_LOOT ~= nil)
  assertTrue(NS.Reconciler.__ev ~= nil)
  assertTrue(NS.Attribution.__outEv ~= nil)
end)

test("perf: suspend and resume log to the console whatever the debug flag says", function()
  local saved = NS.State.debug
  NS.State.debug = false
  NS.Perf.Suspend()
  assertTrue(NS.DebugLog:FindLine("[Perf]") ~= nil, tostring(NS.DebugLog:LastLine()))
  NS.Perf.Resume()
  NS.State.debug = saved
end)

test("perf: /lh perf dispatches to the harness", function()
  local entry
  for _, e in ipairs(NS.COMMANDS) do if e[1] == "perf" then entry = e end end
  assertTrue(entry ~= nil, "no perf verb")
  local lines = NS.Perf.OnCommand("status")
  assertTrue(type(lines) == "table" and #lines > 0)
end)
```

Append to `tests/test_slash_degraded.lua`:

```lua
test("library-less install: NS.Perf is the degradation stub and /lh perf answers", function()
  assertEqual(degradedNS.Perf.on, false)
  degradedNS.Perf.Note("lootLine", 1)                    -- a bracket call is a no-op, never an error
  assertEqual(degradedNS.Perf.OnCommand("")[1], "perf capture unavailable.")
  handler("perf")("")
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -E "FAIL|perf" | head -20`
Expected: FAIL — `NS.Perf` nil.

- [ ] **Step 3: Implement** — `core/PerfSetup.lua`:

```lua
-- core/PerfSetup.lua — the addon's half of LibKa0s-Perf-1.0 (performance-§1).
--
-- Sits right after core/LifecycleSetup.lua in the TOC: it reads NS.Lifecycle at load (Perf minor 12
-- requires the latch and raises at :New without it), and every module taking `local Perf = NS.Perf`
-- as a load-time upvalue (Collector, Attribution, Reconciler) loads below it.
--
-- WHY THIS ADDON NOW HAS ONE. It held the performance-§12 no-combat-path exemption until the
-- timeline ledger (spec §13 F2): holdings diffing put real work behind BAG_UPDATE, money and currency
-- events, which is exactly the exemption's re-check trigger. The buckets are the five handlers that
-- run in combat; the reconcile itself never does (Reconciler:Flush defers to PLAYER_REGEN_ENABLED)
-- and is measured offline by tests/perf.lua instead.
--
-- Suspend no longer loses data the way criterion (c) feared: what changes while window B holds the
-- `perf` hold is read back on resume as UNTRACKED drift (Reconciler:Enable -> LoginScan).

local addonName, NS = ...

local lib = LibStub and LibStub("LibKa0s-Perf-1.0", true)

-- The degradation stub (performance-§1): every member the addon calls — the gate field, the bracket
-- sinks and the slash entry point — so a missing diagnostics library cannot break capture.
local function stub()
  local noop = function() end
  return {
    on = false, suspended = false, BUCKET_ORDER = {},
    Note = noop, Open = noop, Close = noop, Suspend = noop, Resume = noop,
    OnCommand = function() return { "perf capture unavailable." } end,
  }
end

if not (lib and NS.Lifecycle) then
  NS.Perf = stub()
  return
end

NS.Perf = lib:New({
  name      = addonName,        -- seeds the sampler/panel frame globals
  addonName = addonName,        -- the folder the panel's close mark is built from
  title     = "Loot History",   -- the library appends " — Perf Run"
  slash     = "/lh",
  -- Its OWN SavedVariables global (performance-§5), declared in the TOC beside LootHistoryDB and
  -- kept outside the AceDB tree.
  sv        = "LootHistoryPerfDB",
  version   = NS.version,
  lifecycle = NS.Lifecycle,     -- P.Suspend/Resume take and release the `perf` hold
  -- Ungated: a perf run is an explicit user act; routing through NS.Debug would swallow it.
  log     = function(line)
    if NS.DebugLog and NS.DebugLog.Add then NS.DebugLog:Add("Perf", line) else NS.Print(line) end
  end,
  print   = function(line) NS.Print(line) end,
  showLog = function() if NS.DebugLog and NS.DebugLog.Show then NS.DebugLog:Show() end end,
  buckets = {
    { key = "lootLine" },       -- Collector:OnChatMsgLoot (every loot line in the raid)
    { key = "currencyLine" },   -- Collector:OnChatMsgCurrency
    { key = "moneyLine" },      -- Collector:OnChatMsgMoney
    { key = "spellCast" },      -- Attribution:OnSpellSucceeded (every player cast)
    { key = "ledgerEvent" },    -- Reconciler:OnEvent (BAG_UPDATE storms, money, currency: dirty bits)
  },
})
```

Brackets — Shape A everywhere (single exit; dormant cost one upvalue read, one field read, one test):

`modules/Collector.lua` — at file top after `local Collector = NS.Collector`: `local Perf = NS.Perf -- load-time upvalue (performance-§2); core/PerfSetup.lua loads above`. Rename the body of `Collector:OnChatMsgLoot` to a local `function lootLine(self, msg)` (unchanged body, including its early returns) and add:

```lua
function Collector:OnChatMsgLoot(_, msg)
  local t0 = Perf.on and debugprofilestop()
  lootLine(self, msg)
  if t0 then Perf.Note("lootLine", debugprofilestop() - t0) end
end
Collector._lootLine = lootLine   -- the unbracketed body: tests/perf.lua's zero-overhead baseline
```

Do the same for `OnChatMsgCurrency` (body → `currencyLine`, bucket `"currencyLine"`) and `OnChatMsgMoney` (body → `moneyLine`, bucket `"moneyLine"`).

`modules/Attribution.lua` — `local Perf = NS.Perf` at top; rename `Attribution:OnSpellSucceeded`'s body to `local function spellCast(self, unit, spellID)` and:

```lua
function Attribution:OnSpellSucceeded(_, unit, _castGUID, spellID)
  local t0 = Perf.on and debugprofilestop()
  spellCast(self, unit, spellID)
  if t0 then Perf.Note("spellCast", debugprofilestop() - t0) end
end
```

`modules/Reconciler.lua` — `local Perf = NS.Perf` at top; rename `R:OnEvent`'s body to `local function onEvent(self, event, a1, a2, a3, a4, a5)` and:

```lua
function R:OnEvent(event, a1, a2, a3, a4, a5)
  local t0 = Perf.on and debugprofilestop()
  onEvent(self, event, a1, a2, a3, a4, a5)
  if t0 then Perf.Note("ledgerEvent", debugprofilestop() - t0) end
end
```

`settings/Schema.lua` `NS.COMMANDS` — after the `diagnostics` row:

```lua
  -- The A/B performance capture (performance-§4). The verb is the host's; the library returns
  -- lines and this prints them. Live while disabled (LIVE_WHILE_DISABLED). With no LibKa0s the
  -- core/PerfSetup.lua stub answers "perf capture unavailable.".
  { "perf", "A/B performance capture \226\128\148 /lh perf opens the step panel", function(rest)
      for _, line in ipairs(NS.Perf.OnCommand(rest or "")) do print(line) end
    end },
```

and rewrite the comment block above `LIVE_WHILE_DISABLED` that says `perf` is listed although not registered: it is registered now (timeline ledger F2).

`settings/Slash.lua` `UNAVAILABLE_WITHOUT_LIB`: add `perf = true` (the stub answers, but answering is not working — the same reason `diagnostics` is listed).

`.luacheckrc` `globals`: add `"LootHistoryPerfDB",  -- the perf harness's capture ring (performance-§5), outside AceDB`.

`core/LifecycleSetup.lua` — replace the "THIS ADDON TAKES ONE HOLD TODAY…" paragraph with: "THIS ADDON TAKES BOTH HOLDS. `disabled` from the stored switch, `perf` from LibKa0s-Perf's Suspend/Resume (core/PerfSetup.lua, wired for the timeline ledger, spec §13 F2). tests/test_disabled.lua and tests/test_perf.lua drive both through the latch."

- [ ] **Step 4: Write the offline runner** — `tests/perf.lua`

```lua
-- tests/perf.lua — the offline performance runner (performance-§9).
--
--   lua tests/perf.lua
--
-- OUTSIDE THE GREEN GATE: `lua tests/run.lua` does not run it. It asserts only deterministic
-- quantities — bytes allocated per iteration with the GC stopped, and call counts — never time.

local Loader     = dofile("tests/_kit/loader.lua")
local buildMocks = dofile("tests/wow_mock.lua")
Loader.addonName = "LootHistory"

local mocks = buildMocks()
local NS = {}
Loader.loadAll(Loader.xmlFiles("libs/LibKa0s/LibKa0s.xml"), NS, mocks)
Loader.loadAll(Loader.tocFiles("LootHistory.toc"), NS, mocks)
NS.addon:OnInitialize()
NS.addon:OnEnable()

local failures = 0
local function check(name, ok, detail)
  print(("%s  %s%s"):format(ok and "PASS" or "FAIL", name, detail and ("  (" .. detail .. ")") or ""))
  if not ok then failures = failures + 1 end
end

-- Bytes per iteration of fn, GC stopped, after a warm-up pass.
local function bytesPerIter(fn, n)
  for _ = 1, 50 do fn() end
  collectgarbage("collect"); collectgarbage("stop")
  local before = collectgarbage("count")
  for _ = 1, n do fn() end
  local after = collectgarbage("count")
  collectgarbage("restart")
  return (after - before) * 1024 / n
end

-- Scenario 1 — zero overhead (performance-§2/§9): a DROPPED loot line (below the quality gate, the
-- common in-raid case) through the bracketed handler with capture off allocates no more than the
-- unbracketed body.
NS.db.profile.settings.qualityThreshold = 5
NS.Collector:RefreshUpvalues()
local line = string.format(mocks.LOOT_ITEM_SELF, "|cffa335ee|Hitem:211296::::::::80:::::|h[Vial]|h|r")
NS.Perf.on = false
local bracketed = bytesPerIter(function() NS.Collector:OnChatMsgLoot(nil, line) end, 2000)
local bare = bytesPerIter(function() NS.Collector._lootLine(NS.Collector, line) end, 2000)
check("zero-overhead: dropped loot line, capture off", bracketed <= bare,
  ("%.1f B/iter bracketed vs %.1f bare"):format(bracketed, bare))

-- Scenario 2 — an in-combat BAG_UPDATE storm is dirty bits only: no allocation after warm-up, no scan.
local scans, base = 0, NS.Scanner.ScanContainers
NS.Scanner.ScanContainers = function(...) scans = scans + 1; return base(...) end
mocks.InCombatLockdown = function() return true end
local storm = bytesPerIter(function() NS.Reconciler:OnEvent("BAG_UPDATE", 0) end, 5000)
check("combat BAG_UPDATE: no allocation", storm == 0, ("%.1f B/iter"):format(storm))
check("combat BAG_UPDATE: no scan", scans == 0, tostring(scans) .. " scans")
mocks.InCombatLockdown = function() return false end
NS.Scanner.ScanContainers = base

-- Scenario 3 — one out-of-combat reconcile over a full bag set: scan calls are bounded by the
-- number of bags (one ScanContainers per dirty container group), never per slot.
for bag = 0, 5 do
  mocks.__bagSlots[bag] = 36
  mocks.__bags[bag] = {}
  for s = 1, 36 do mocks.__bags[bag][s] = { itemID = 1000 + s, link = "L", count = 1 } end
end
NS.Reconciler:LoginScan()
scans = 0
NS.Scanner.ScanContainers = function(...) scans = scans + 1; return base(...) end
NS.Reconciler:MarkDirty("bags"); NS.Reconciler:Flush()
check("reconcile: one container scan per dirty group", scans == 1, tostring(scans) .. " scans")
NS.Scanner.ScanContainers = base

if failures > 0 then os.exit(1) end
```

- [ ] **Step 5: Docs for the harness**

- `docs/ARCHITECTURE.md` → `## Documented deviations`: delete the `performance-§12` row entirely (F2, user-ratified 2026-10-06, supersedes the decline in issue #29). In `## Documentation map`: `perf-analysis/README.md` → present ("The in-game capture store: bundle naming, the three artifacts, schema pointer, how to capture with `/lh perf`, the capture index"); `performance.md` → "The harness: buckets and why, the zero-overhead evidence, how to capture"; `combat-path-sweep.md` → "The whole-repo event/timer inventory with per-fire work (kept as the event census; it no longer backs an exemption)".
- `docs/performance.md` — rewrite: the five buckets and what each covers; why `Reconciler:Flush` is not a bucket (out of combat by construction; `tests/perf.lua` scenario 3); the zero-overhead evidence (`tests/perf.lua` scenario 1); suspend semantics (both holds on one latch; drift read back as `UNTRACKED` on resume); how to capture (`/lh perf`, the panel, then `/dev-copilot:wow-perf-analysis` with report + dump); the offline runner is outside the green gate.
- `docs/combat-path-sweep.md` — add a header note: "Retained as the event census. It no longer backs the `performance-§12` exemption (retired 2026-10-06, timeline ledger F2)", and add the Phase 1/2 registrations (Reconciler, AttributionOut, `CHAT_MSG_MONEY`) with their per-fire work (dirty bit / accumulator / stamp).
- `docs/perf-analysis/README.md` — create: purpose; bundle naming `docs/perf-analysis/<YYYYMMDD-HHMMSS>/` in local time from the record's own timestamp; the three artifacts (`report.md`, `dump.json` byte-for-byte, `ANALYSIS.md` per `PERF_ANALYSIS.md`); the record schema is LibKa0s-Perf's (pointer to `libs/LibKa0s/Perf.lua` `lib.SCHEMA` and the library's `docs/api/`); capture with `/lh perf`; offline runs live in `docs/automated-tests/`; `## Captures` index ("None yet.").

- [ ] **Step 6: Run tests, lint and the offline runner**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck . && lua tests/perf.lua`
Expected: PASS, 0/0; `tests/perf.lua` prints four PASS lines. `tests/test_doc_structure.lua` passes with the doc-map rows updated (it checks every listed page exists). If `tests/test_surface_parity.lua` reports the Perf stub's surface, add `["LibKa0s-Perf-1.0"] = NS.Perf` to `Kit.setSurfaceSource` in `tests/run.lua` and list stub-only omissions in that suite's `ignore` the way `New` is listed for the Bus.

- [ ] **Step 7: Commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add core/PerfSetup.lua LootHistory.toc .luacheckrc modules/Collector.lua modules/Attribution.lua modules/Reconciler.lua settings/Schema.lua settings/Slash.lua core/LifecycleSetup.lua tests/test_perf.lua tests/perf.lua tests/test_slash_degraded.lua tests/run.lua docs/ARCHITECTURE.md docs/performance.md docs/combat-path-sweep.md docs/perf-analysis/README.md docs/test-cases.md
git commit -m "feat(perf): wire LibKa0s-Perf (five in-combat buckets, /lh perf, LootHistoryPerfDB); retire the performance-§12 exemption (F2)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt"
```

---

### Task 14: Documentation and smoke tests for Phase 2

**Files:**
- Modify: `docs/data-flow.md` — new `## The ledger: holdings diff + claims` section after `## The collector's gates`: scan → plan → hold/commit; the three classification cases (§5.1); claims (both orders, partial, TTL, gated-out lines post none); reasons (two context slots, scopes, precedence list from `Ledger.PickReason`); coalescing; currency from event args; escrow rules; login/resume `UNTRACKED`; combat (dirty bits + per-id currency accumulator only).
- Modify: `docs/schema.md` — row fields now written (`dir, kind, holder, from, to, claimed`) with the GOLD row shape; `holdings[h].escrow` (`mailOwn`, `mailMoney`, `exits`); settings `recordGold`, `showTransfers`, relabelled `qualityThreshold` (F5); History CSV column list + the five appended columns (F4); `Stats().ledger` field list; `Database:OnWrite` / `Amend` contract.
- Modify: `docs/scope.md` — min-quality's new meaning (F5): gates detailed records and the default view, not what the ledger counts; `recordGold`; the export-shape decision (F4) with its 2026-10-06 date.
- Modify: `docs/message-bus.md` — `RECORD_ADDED` sent by `Add` **and** `Amend`; receivers repaint, never count (S2).
- Modify: `docs/module-map.md` — `modules/AttributionOut.lua`, `modules/Escrow.lua`, `modules/LedgerFormat.lua`, `modules/AnalyticsLedger.lua`, `core/PerfSetup.lua` with TOC positions and roles.
- Modify: `docs/ARCHITECTURE.md` — module map rows (same five), event-wiring table (`CHAT_MSG_MONEY`, `MAIL_INBOX_UPDATE`, `OWNED_AUCTIONS_UPDATED`, `CURRENCY_TRANSFER_LOG_UPDATE`, `MAIL_SEND_SUCCESS`, `MAIL_FAILED`, `ADDON_LOADED`, AttributionOut's interaction/trade registrations), hooks list (RepairAllItems, BuyMerchantItem (2nd), BuybackItem, DeleteCursorItem, SendMail, TakeInboxMoney, C_AuctionHouse.PostItem/PostCommodity/PlaceBid/ConfirmCommoditiesPurchase, C_TradeSkillUI.CraftRecipe/CraftSalvage/CraftEnchant, GuildBankFrame OnShow/OnHide — all latch-gated), slash table (`perf`), `## Known limitations`: escrow is holdings-only until resolved (S6); the AH-sale match is by item name from the sale mail subject; an exit unresolved for 30 days is booked as sold; the guild cut in `YOU_LOOT_MONEY_GUILD` lines; one-online-character-per-account makes own-alt trades impossible (the TRANSFER path for trades is dormant).
- Modify: `docs/browser.md` — Direction column (mono glyphs), signed Qty, Direction filter in row 1 and why (toolbar width floor), default view (Gains+Losses, Transfers per setting, min-quality floor, whitelist exempt), group by Direction/Holder; Insights ledger cards and section; caveat.
- Modify: `docs/disabled-state.md` — `AttributionOut` (`__outEv`, state cleared), Reconciler ledger state cleared, `CHAT_MSG_MONEY` unregistered, the new hooks gate on the latch; perf hold.
- Modify: `docs/smoke-tests.md` — `## Ledger capture (timeline ledger Phase 2)` section with the cases below (add each to `## Index`).
- Modify: `docs/test-cases.md` — regenerate.
- README.md: no change now — the F4 column note and the feature line go into `## Version History` at release time via `/dev-copilot:bump-version` (documentation-§1).

Smoke cases to add (each with steps and the expected rows; **the bracketed checks are the API facts this plan could not verify headless**):

- **LED-P2-01 Bank deposit/withdraw.** Deposit a stack, withdraw half. Expect only `MOVE` rows (Direction filter → Transfers), no gain/loss; Holdings bank column updates.
- **LED-P2-02 Warband deposit.** Item and gold into the warband bank. Expect a `MOVE` pair (one row per holder) for each. [`ACCOUNT_MONEY` fires on a warband gold deposit; `C_Bank.FetchDepositedMoney(Enum.BankType.Account)` answers while the bank is open.]
- **LED-P2-03 Vendor.** Sell junk, repair, buy one item, buy back one. Expect item `OUT SELL` + gold `IN SELL` (~1.5 s later), gold `OUT REPAIR`, gold `OUT BUY` + item `IN VENDOR` (chat-claimed), buyback gold `OUT BUY`. [`RepairAllItems` / `BuybackItem` are hookable globals on 12.x.]
- **LED-P2-04 Loot.** Kill a mob with gold and two items (one grey). Expect one claimed row per item and one claimed gold row (`source=KILL`); the grey item appears only with Quality → Poor selected (min-quality floor). [`CHAT_MSG_MONEY` arrives as "You loot …" built from `GOLD_AMOUNT`/`SILVER_AMOUNT`/`COPPER_AMOUNT`.]
- **LED-P2-05 Combat potions.** Drink 3 potions in one pull. No hitch; after combat exactly one `OUT CONSUME` row ×3; a second pull within 60 s amends it.
- **LED-P2-06 Mail to own alt.** Send items + gold to an alt. Expect `MOVE` pairs to `Alt/mail`, a gold `OUT MAIL_SEND` for postage; log the alt in, take the mail: `MOVE` rows only, no `IN`. [`SendMail` is a post-hook and `GetSendMailItem`/`GetSendMailMoney` still return the staged attachments when it runs; `MAIL_SEND_SUCCESS` fires after the bags change or within the 10 s window.]
- **LED-P2-07 Mail from others / AH won.** Take a mail from another player and a won auction. Expect `IN MAIL` / `IN AH`, chat-claimed when a loot line fires. [`GetInboxItem(i, a)` returns `name, itemID, texture, count`.]
- **LED-P2-08 AH post.** Post one item and one commodity. Expect `MOVE` to `me/auctions` and gold `OUT AH_POST_FEE`. [`C_AuctionHouse.PostItem(itemLocation, duration, quantity, bid, buyout)` and `PostCommodity(itemLocation, duration, quantity, unitPrice)`: the third argument is the quantity; `C_Item.GetItemID(itemLocation)` resolves it.]
- **LED-P2-09 AH outcomes.** Cancel one auction (return → take = `MOVE`), let one sell (take the money: item `OUT AH_SOLD` + gold `IN AH_SOLD`). [`OWNED_AUCTIONS_UPDATED` fires after opening the Auctions tab; `GetOwnedAuctionInfo(i).status` uses `Enum.AuctionStatus.Active`/`Sold`; `AUCTION_SOLD_MAIL_SUBJECT` matches the sale mail subject and its `%s` is the item name only.]
- **LED-P2-10 Guild bank.** Deposit and withdraw an item and gold. Expect `OUT GUILD_DEPOSIT` / `IN GUILD_WITHDRAW`. [`GuildBankFrame` exists after `Blizzard_GuildBankUI` loads and its `OnShow`/`OnHide` fire on open/close.]
- **LED-P2-11 Crafting.** Craft 5 of a recipe. Expect reagent `OUT CRAFT_REAGENT` rows and the product `IN CRAFT`. [`C_TradeSkillUI.CraftRecipe` / `CraftSalvage` / `CraftEnchant` exist and are hookable.]
- **LED-P2-12 Disenchant.** Disenchant one item. Expect the item `OUT DECONSTRUCT` and the materials `IN DISENCHANT`.
- **LED-P2-13 Warband currency transfer.** Transfer a transferable currency to an alt. Expect a `MOVE` pair to `Alt/currency` and any fee as `OUT TRANSFER`; the alt's next login shows no `UNTRACKED` for it. [`CURRENCY_TRANSFER_LOG_UPDATE` fires; `C_CurrencyInfo.FetchCurrencyTransferTransactions()` returns records with `currencyType`, `quantityTransferred`, `destinationCharacterName`; `CURRENCY_DISPLAY_UPDATE`'s `destroyReason` names `AccountTransfer`.]
- **LED-P2-14 Currency spend.** Spend crests on an upgrade and currency at a vendor. Expect `OUT` rows with mapped reasons. [`CURRENCY_DISPLAY_UPDATE` payload is `(currencyType, quantity, quantityChange, quantityGainSource, quantityLostSource)`; `/dump Enum.CurrencySource` and `/dump Enum.CurrencyDestroyReason` contain the member names in `C.CURRENCY_SOURCE_REASON` — correct the table if not.]
- **LED-P2-15 Login drift.** Disable the addon, log in, move items, re-enable, `/reload`. Expect `UNTRACKED` rows for the differences; a brand-new character's first login writes none.
- **LED-P2-16 Resume drift.** `/lh disable`, loot something, `/lh enable`. Expect the loot as `UNTRACKED` ~1 s after enabling.
- **LED-P2-17 History display.** Direction glyphs ▲ ▼ ⇄ render (no boxes) in the mono face, colored; Qty shows `+3`/`-3`; gold rows in pale gold; Direction filter default = Gains + Losses; ticking "Show transfers by default" then Clear includes transfers; group by Direction and by Holder. [JetBrains Mono carries U+21C4.]
- **LED-P2-18 Insights.** With losses in range: Gained/Lost/Net/Transfers cards; "Gains vs losses by reason/character/kind" charts above LOOT; with kept history and a range before the upgrade date, the yellow caveat line.
- **LED-P2-19 Exports.** History CSV ends `…,wowheadLink,dir,kind,holder,from,to`; legacy rows read `IN,ITEM,<char>,,`; Insights CSV ends with `Ledger` sections when losses are in range.
- **LED-P2-20 Perf run.** `/lh perf`: the step panel opens; complete both arms on a training dummy with a loot-heavy pull; `/lh perf finish` prints a report whose `lootLine`, `spellCast` and `ledgerEvent` buckets are non-zero; record it with `/dev-copilot:wow-perf-analysis`.
- **LED-P2-21 Trainer and taxi.** Train a skill, take a flight. Expect gold `OUT TRAINING` / `OUT TRAVEL`. [`Enum.PlayerInteractionType.Trainer` and `.TaxiNode` are the member names.]
- **LED-P2-22 Party loot money.** In a group, loot gold split. Expect "Your share of the loot is …" parsed and claimed; with guild perks, note whether `YOU_LOOT_MONEY_GUILD`'s first amount is the pre- or post-cut figure (Known limitation if pre-cut).
- **LED-P2-23 Trade.** Trade an item and gold to another player. Expect `OUT TRADE_GIVE` rows. [`UnitName("NPC")` names the trade partner while the trade window is open.]
- **LED-P2-24 Destroy.** Delete an item. Expect `OUT DESTROY`. [`DeleteCursorItem` is a hookable global.]

- [ ] **Step 1:** Make the doc edits above, matching each file's voice. Run `lua tests/run.lua 2>&1 | grep -i doc_structure` — `tests/test_doc_structure.lua` checks ARCHITECTURE's sections, the doc map and anchors.
- [ ] **Step 2:** Run `lua tests/run.lua 2>&1 | tail -5 && luacheck .` — Expected: PASS, 0/0.
- [ ] **Step 3:** Commit.

```bash
lua tests/run.lua --list > docs/test-cases.md
git add docs/
git commit -m "docs: timeline ledger phase 2 — data flow, schema, bus, module map, known limits, LED-P2 smokes" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt"
```

- [ ] **Step 4:** Hand the in-game smoke list (LED-P2-01..24) to the user. Phase 2 is complete only when they report the smokes passed; every bracketed check that fails becomes a Compat/mock fix in a follow-up commit before Phase 3 starts.

---

## Spec coverage (Phase 2)

| Spec section | Task |
|---|---|
| §4.1 row fields written (`dir, kind, holder, from, to, claimed`), GOLD rows, unsigned quantity + `DirSign` | 2, 7, 8 |
| §4.1 18 appended `SourceType` reasons | 1 |
| §5.1 intra-holder MOVE | 2, 7 |
| §5.1 inter-holder MOVE pairs (warband bank, warband gold, account currency) | 2, 7, 9 |
| §5.1 mail to own alt (recipient's mail in flight) | 6, 10 |
| §5.1 net IN/OUT with reason | 3, 7 |
| §5.1 only readable containers diffed; never inferred empty | 2, 7 (Phase 1 Task 6 pin kept) |
| §5.2 triggers (`MAIL_INBOX_UPDATE`, `OWNED_AUCTIONS_UPDATED`, `CURRENCY_DISPLAY_UPDATE` args, `CURRENCY_TRANSFER_LOG_UPDATE`, interaction scopes, guild bank frame hooks, combat deferral) | 6, 9, 10 |
| §5.2 settle window / held baseline / give-up 6 s | 2, 7 |
| §5.3 claims from `CHAT_MSG_LOOT` / `CHAT_MSG_CURRENCY` (both orders, partial, TTL) | 2, 7, 8 |
| §5.3 capture gate keeps gating rich rows; gated-out items become plain diff rows; blacklist never rows | 7, 8 |
| §5.3 / F5 min-quality as default History view filter + settings text | 11 |
| §5.4 outbound stamps: SELL, BUY, REPAIR, MAIL_SEND, TRADE_GIVE, AH_POST_FEE, AH_SOLD, AH_BUY, DESTROY, CONSUME, CRAFT_REAGENT, DECONSTRUCT, GUILD_DEPOSIT/WITHDRAW, TRAINING, TRAVEL, TRANSFER, OTHER, UNTRACKED | 3, 6, 9, 10 |
| §5.4 gold gains via `CHAT_MSG_MONEY` claims | 5, 8 |
| §5.5 coalescing within a pass and across 60 s | 2, 7 |
| §5.6 login reconcile: genesis writes none; drift → UNTRACKED | 9 |
| §6 Gained/Lost/Net KPIs, signed styling | 4, 11, 12 |
| §6 Gains vs losses by reason / character / kind (back-to-back, shared scale) | 12 |
| §6 existing charts gain-only (`dir == IN`) | 4 |
| §6 pre-`ledgerSince` caveat when `resetPrompt == "kept"` | 4, 12 |
| §7 Direction column (mono glyphs, colors), signed Qty, gold as money | 1, 11 |
| §7 Direction filter (default Gains + Losses), group-by Direction / Holder, new reasons in Source lists | 11 |
| §11 `recordGold`, `showTransfers` | 7, 11 |
| §12 headless tests (`test_ledger`, reconciler cases, database/stats, disabled-state) and smokes | 2–14 |
| §13 F2 perf harness wired; `performance-§12` row removed | 13 |
| §13 F4 CSV `dir, kind, holder, from, to` appended | 4 |
| Phase 3 hook point: `Database:OnWrite(fn(record, delta, isNew))` on every `Add`/`Amend` | 4 |
| Deferred to Phase 3: §4.3 rollup writes/prune, §8.1 Timeline, F3 LibKa0s LineChart, "Show in Timeline", per-tab filter greying, "Forget this character" | — |

## Unverified WoW API assumptions (each is a smoke check, not a fact)

| Assumption | Where it is used | Smoke |
|---|---|---|
| `CURRENCY_DISPLAY_UPDATE` payload `(currencyType, quantity, quantityChange, quantityGainSource, quantityLostSource)` | `Reconciler:OnEvent` → `OnCurrencyUpdate` | LED-P2-14 |
| `Enum.CurrencySource` / `Enum.CurrencyDestroyReason` member names (`Vendor`, `QuestReward`, `Trade`, `ItemRefund`, `AccountTransfer`, `FulfillCraftingOrder`, `ConcentrationCast`, `Spell`, `GuildBankWithdrawal`) | `C.CURRENCY_SOURCE_REASON`, `Compat.CurrencySourceName` | LED-P2-14 |
| `C_CurrencyInfo.FetchCurrencyTransferTransactions()` record fields and `CURRENCY_TRANSFER_LOG_UPDATE` timing | `Compat.LatestCurrencyTransfer` | LED-P2-13 |
| `C_CurrencyInfo.GetCurrencyInfo(id).isAccountWide` distinguishes warband-wide currencies | `Compat.CurrencyIsAccountWide` | LED-P2-02/13 |
| `C_AuctionHouse.PostItem` / `PostCommodity` argument 3 is the quantity; `PlaceBid` / `ConfirmCommoditiesPurchase` exist and are hookable | `AttributionOut` hooks | LED-P2-08 |
| `C_AuctionHouse.GetNumOwnedAuctions` / `GetOwnedAuctionInfo(i)` → `{ itemKey.itemID, itemLink, quantity, status }`; `Enum.AuctionStatus.Active` | `Compat.ScanOwnedAuctions` | LED-P2-09 |
| `OWNED_AUCTIONS_UPDATED` fires once the owned list is loaded | `Reconciler` readability | LED-P2-09 |
| `AUCTION_SOLD_MAIL_SUBJECT` etc. are `"…: %s"` with the bare item name | `Compat.AuctionMailKind` | LED-P2-09 |
| `SendMail` post-hook still sees staged attachments (`GetSendMailItem(slot)` → `name, itemID, texture, count`), `GetSendMailMoney()` | `AttributionOut:OnSendMail` | LED-P2-06 |
| `GetInboxItem(i, a)` → `name, itemID, texture, count`; `ATTACHMENTS_MAX_RECEIVE` | `Compat.ScanInbox` | LED-P2-07 |
| `MAIL_SEND_SUCCESS` / `MAIL_FAILED` event names | `AttributionOut` | LED-P2-06 |
| `TakeInboxMoney(index)`, `RepairAllItems`, `BuybackItem`, `DeleteCursorItem` are hookable globals | `AttributionOut` hooks | LED-P2-03/09/24 |
| `C_TradeSkillUI.CraftRecipe` / `CraftSalvage` / `CraftEnchant` are the craft entry points | `AttributionOut:OnCraft` | LED-P2-11 |
| `GuildBankFrame` + `Blizzard_GuildBankUI` addon name; frame `OnShow`/`OnHide` fire | `AttributionOut:HookGuildBankFrame` | LED-P2-10 |
| `Enum.PlayerInteractionType` members `Merchant`, `Trainer`, `TaxiNode`, `MailInfo`, `Auctioneer`, `Banker`, `AccountBanker`, `GuildBanker` | scopes, readability | LED-P2-03/21 |
| `UnitName("NPC")` is the trade partner | `Compat.TradeTargetKey` | LED-P2-23 |
| `YOU_LOOT_MONEY`, `LOOT_MONEY_SPLIT`, `YOU_LOOT_MONEY_GUILD`, `GOLD_AMOUNT`/`SILVER_AMOUNT`/`COPPER_AMOUNT` shapes | `Util.ParseSelfMoney` | LED-P2-04/22 |
| `C_Item.GetItemInfoInstant` 6th return is `classID` (Consumable = 0) | `Compat.IsConsumable` | LED-P2-05 |
| `C_Item.GetItemID(itemLocation)` | `Compat.ItemLocationID` | LED-P2-08 |
| JetBrains Mono (LibKa0s media) has U+25B2, U+25BC, U+21C4 | Direction column | LED-P2-17 |
