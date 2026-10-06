# Timeline ledger — gains, losses, holdings & timeline — design spec

**Status:** design approved incl. §13 resolutions (2026-10-06) — **not built**; next: implementation plan
**Date:** 2026-10-06
**Branch:** none yet (trunk-based on `master` unless asked otherwise)
**Scope:** turn Loot History from a *gains-only loot log* into a full **ledger** of items,
currencies and gold: every gain and loss attributed to a reason, transfers recognized as
transfers, a current-**holdings** ledger across all characters plus the warband, a **Holdings**
search tab, and a **Timeline** line-chart tab. Breaking schema change (v10 → v11) with an
in-game **reset recommendation** on first load.

---

## 1. Goal

Answer two questions equally well:

1. **Wealth over time** — "how did my gold / a currency / an item rise and fall, and why?"
2. **Where is my stuff** — "what do I own right now, across every alt and the warband?"

…with the two always reconciling: current holdings = genesis snapshot + Σ(gains) − Σ(losses).

## 2. Decisions (ratified during brainstorming, 2026-10-05/06)

| # | Decision |
|---|---|
| D1 | Purpose: **both** wealth-over-time and where-is-my-stuff, equally weighted. |
| D2 | Coverage: **everything, everywhere** — every item (any quality), every currency, gold; both holdings and gain/loss rows. |
| D3 | **Guild bank = outside the account.** Deposit is a loss (`GUILD_DEPOSIT`), withdrawal a gain (`GUILD_WITHDRAW`); guild contents are not tracked. |
| D4 | Volume: **raw rows + daily rollup.** Raw rows obey the existing retention setting; a sparse daily rollup is kept long-term and feeds the Timeline. Bursts coalesce. |
| D5 | Migration: **timeline starts at upgrade.** No row rewrite; each holder's lines begin at its *genesis* (first full scan after upgrade). Legacy gains stay visible in History/Insights. |
| D6 | Capture engine: **holdings-diff + claims** (§5). |
| D7 | Holdings search lives in a **4th tab "Holdings"**. |
| D8 | Timeline charts **one thing at a time** (Gold, one currency, or one item). Lines = **holders** (Total + up to *X* characters/Warband). |
| D9 | On first load after upgrade with existing history, show a **reset recommendation popup** (§9). |

## 3. Concepts

- **Thing** — what is counted. `thingKey` = `"g"` (gold, copper), `"c:<currencyID>"`, or
  `"i:<itemID>"`. Items are keyed by **base itemID** (BagSync "unique" mode): ilvl/bonus variants
  of one id share a count. The scanned hyperlink is kept as a side-table (BankLedger pattern) for
  display only.
- **Holder** — who owns things. Each character (`"Name-Realm"`, `Util.PlayerKey`) and one
  virtual holder **`"§warband"`** (warband bank tabs, warband gold, account-wide currencies). `§`
  marks system keys (BagSync convention); iteration that means "characters" skips them.
- **Container** — where a holder keeps a thing:

  | Container | Holder | Readable | Notes |
  |---|---|---|---|
  | `bags` (incl. reagent bag) | char | always | `BAG_UPDATE` set drained on `BAG_UPDATE_DELAYED` |
  | `equipped` (incl. profession tools) | char | always | equip/unequip = transfer |
  | `bank` | char | bank frame open | `Enum.BagIndex.CharacterBankTab_*`, ids derived by name (BankLedger lesson) |
  | `mail` | char | inbox open; **in-flight** writes from our own `SendMail` | escrow |
  | `auctions` | char | AH owned-auctions query | escrow, with expiry |
  | `tabs` | §warband | bank frame open | `Enum.BagIndex.AccountBankTab_*` |
  | `currency` | char or §warband | always | account-wide currencies → §warband |
  | `money` | char or §warband | char always; warband via `C_Bank.FetchDepositedMoney(Enum.BankType.Account)` | |

  Every container stores `scannedAt`. UI shows staleness ("bank as of 3 d ago").
- **Row directions** — `IN` (gain), `OUT` (loss), `MOVE` (transfer; never counted in gain/loss
  totals).

## 4. Data model — schema v11

All new state is account-wide in `db.global`. Profile scope is untouched except new settings (§11).

### 4.1 History rows (existing `global.history`, extended)

New optional fields on every row; **absent on legacy rows, which read as defaults** (no rewrite):

| Field | Values | Legacy default |
|---|---|---|
| `dir` | `"IN"` / `"OUT"` / `"MOVE"` | `"IN"` |
| `kind` | `"ITEM"` / `"CURRENCY"` / `"GOLD"` | derived: `itemID` → ITEM, `currencyID` → CURRENCY |
| `holder` | holder key | `char` |
| `from`, `to` | `"<holder>/<container>"` (MOVE rows only) | — |
| `claimed` | `true` on rows written by the chat path that the diff matched | — |

- Accessors `Util.RowDir(r)`, `Util.RowKind(r)`, `Util.RowHolder(r)` encapsulate the defaults;
  no consumer reads the raw fields.
- `quantity` stays **unsigned**; sign is applied only when totalling (`DirSign = {IN=1, OUT=-1, MOVE=0}`) — BankLedger pattern.
- `GOLD` rows: `quantity` in copper, `itemName = "Gold"`, no itemID/currencyID.
- `source` carries the reason for **both** directions. New enum members (append-only; export contract):
  `SELL, BUY, REPAIR, MAIL_SEND, TRADE_GIVE, AH_POST_FEE, AH_SOLD, AH_BUY, DESTROY, CONSUME,
  CRAFT_REAGENT, DECONSTRUCT, GUILD_DEPOSIT, GUILD_WITHDRAW, TRAINING, TRAVEL, TRANSFER,
  UNTRACKED`. Existing members unchanged (`VENDOR` stays the gain-from-merchant source).

### 4.2 Holdings (`global.holdings`)

```lua
global.holdings["Name-Realm" | "§warband"] = {
  meta    = { classFile=, genesis=<ts|nil>, partial=<bool>, lastSeen=<ts> },
  scanned = { bags=<ts>, equipped=<ts>, bank=<ts>, mail=<ts>, auctions=<ts>, tabs=<ts>,
              currency=<ts>, money=<ts> },
  items   = { [itemID] = { bags=n, bank=n, equipped=n, mail=n, auctions=n, tabs=n } },  -- sparse
  currency= { [currencyID] = n },
  money   = <copper>,
  links   = { [itemID] = "<last seen hyperlink>" },  -- display only
}
```

Sparse: zero counts are deleted. The **logged-in character's** live totals are read from the API
(`C_Item.GetItemCount`, `GetMoney`, `C_CurrencyInfo`), stored data is used for every other holder
(BagSync pattern) — the stored copy of the current character is written on each reconcile so it is
correct at logout.

### 4.3 Daily rollup (`global.daily`)

```lua
global.daily["YYYY-MM-DD"][holder][thingKey] = { c=<close>, i=<in>, o=<out> }
```

Sparse: a cell exists only for a (day, holder, thing) that changed. The Timeline carries the last
`c` forward. Written by the reconciler alongside each row (O(1) per row). Own retention setting
`rollupRetentionDays` (default **0 = Always**). Pruned with the existing once-per-session prune.

### 4.4 Bookkeeping

`global.ledgerSince = <ts of v11 migration>`, `global.resetPrompt = nil | "reset" | "kept"`
(§9), `global.schemaVersion = 11`.

## 5. Capture engine — holdings-diff + claims

### 5.1 Principle

The **reconciler** is the single authority for quantities. On each settled change it diffs the
holder's previous count maps against freshly scanned ones (pure `Ledger.Diff(old, new) → deltas`,
sorted by thingKey for testability — BankLedger pattern), then classifies each delta:

1. **Intra-holder** — the thing went down in one container and up in another of the **same
   holder** by a matching amount → `MOVE` row (`from`/`to`), net 0.
2. **Inter-holder (own)** — char ↔ §warband (warband bank, warband gold deposit/withdraw,
   account-currency transfer), or char → own alt (mail/trade to a known holder) → opposite
   `MOVE` pair; recipient's `mail` container gets the in-flight count.
3. **Net change** — whatever remains after (1)/(2) and after **claims** (5.3) → `IN` or `OUT`
   row with a reason from the context stamp (5.4).

Only containers **currently readable** take part in a diff; an unreadable container keeps its
last snapshot and is never inferred to be empty.

### 5.2 Triggers

| Event | Action |
|---|---|
| `BAG_UPDATE` | add bagID to dirty set (no work) |
| `BAG_UPDATE_DELAYED` | drain dirty set → scan those bags (+ warband tab bags if open) → reconcile (debounced 0.35 s, settle window per BankLedger's held-baseline, give-up 6 s) |
| `PLAYER_EQUIPMENT_CHANGED` | rescan `equipped` |
| `PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE` (Banker, AccountBanker, MailInfo, Auctioneer, GuildBanker, Merchant) | set readable flags; full scan of that container on show; final reconcile on hide |
| `PLAYERBANKSLOTS_CHANGED`, `PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED` | rescan bank / tab |
| `PLAYER_MONEY`, `ACCOUNT_MONEY` | money reconcile (`GetMoney() - GetCursorMoney() - GetPlayerTradeMoney()`) |
| `CURRENCY_DISPLAY_UPDATE(id, qty, change, gainSrc, lostSrc)` | currency delta direct from args; `gainSrc`/`lostSrc` map to reasons |
| `CURRENCY_TRANSFER_LOG_UPDATE` | currency transfer between holders → MOVE pair |
| `MAIL_INBOX_UPDATE` (debounced 0.3 s) | rescan `mail` |
| `OWNED_AUCTIONS_UPDATED` | rescan `auctions` |
| `PLAYER_REGEN_ENABLED` | run any reconcile deferred by combat |
| `PLAYER_ENTERING_WORLD` (+3 s) | **login reconcile** (5.6) |

All registrations via `NS.SafeRegisterEvent`; each event independently (BankLedger: an unknown
name raises and deafens a bulk loop). Guild bank open/close via `GuildBankFrame` `OnShow/OnHide`
hooks (BankLedger: `GUILDBANKFRAME_*` never fire on 12.x).

**Combat:** in combat every handler above only sets a dirty bit. Reconcile runs on
`PLAYER_REGEN_ENABLED`. A combat burst (potions, healthstones) therefore lands as one `CONSUME`
row per thing.

### 5.3 Claims (no double counting)

The existing chat paths are **kept unchanged** (`CHAT_MSG_LOOT` → `Collector:OnChatMsgLoot`,
`CHAT_MSG_CURRENCY`), because they carry the richest attribution (bonus-ID link, npc/encounter,
keystone). After writing its record, the chat path posts a **claim**
`claims[thingKey] += qty` with a 5 s expiry and a back-reference to the row. When the reconciler
sees a positive delta *d* for that thing, it consumes `min(d, claim)`; only the **remainder** is
written as a diff row. If the delta arrives first, it is held for the settle window waiting for a
claim. Matched chat rows are stamped `dir="IN", kind=…, holder=…` (and `claimed=true`).

Consequence for the existing **capture gate** (blacklist / min-quality / quest / whitelist): it
keeps gating the *rich chat record*. Items that fail the gate are still captured by the diff as
plain rows (D2). The **blacklist** is the one exception: blacklisted itemIDs never get rows
(still counted in holdings). The min-quality setting additionally becomes the **default History
view filter** so the table's look is unchanged for existing users. *(Flag: settings-text change;
see §13.)*

### 5.4 Reasons (context stamps)

Extend `Attribution` with **outbound** stamps using the same single-slot TTL engine
(`State.lootContext` → generalized to `State.context`, TTL 1.5 s; some reasons use a longer
"while frame open" scope):

| Reason | Stamp |
|---|---|
| `SELL` / `BUY` / `REPAIR` | merchant frame open + `hooksecurefunc` on `SellCursorItem`/`UseContainerItem` (sell), `BuyMerchantItem` (existing), `RepairAllItems` |
| `MAIL_SEND` / own-alt `TRANSFER` | `SendMail` hook (recipient resolved against holders) + `MAIL_SEND_SUCCESS` |
| `TRADE_GIVE` / own-alt `TRANSFER` | `TRADE_ACCEPT_UPDATE` (existing) + trade target name |
| `AH_POST_FEE`, post (→ `auctions` MOVE), `AH_SOLD`, `AH_BUY` | AH frame + `C_AuctionHouse.PostItem/PostCommodity` hooks; sale detected when an auction leaves `auctions` without returning to mail as expired |
| `DESTROY` | `DeleteCursorItem` hook |
| `CONSUME` | unexplained decrease of a usable item (`C_Item.IsUsableItem` / consumable class) |
| `CRAFT_REAGENT` | decrease while a tradeskill cast is in flight (`UNIT_SPELLCAST_*` player, existing listener) |
| `DECONSTRUCT` | existing DISENCHANT/MILLING/PROSPECTING spell stamp, outbound side |
| `GUILD_DEPOSIT` / `GUILD_WITHDRAW` | guild bank frame open + one-sided bag/money delta (D3) |
| `TRAINING`, `TRAVEL` | trainer / taxi interaction open + money decrease |
| `OTHER` | no stamp matched |
| `UNTRACKED` | login reconcile (5.6) |

Gold gains: `CHAT_MSG_MONEY` (loot, and party split) acts as a claim source for gold the same way
`CHAT_MSG_LOOT` does for items.

### 5.5 Coalescing

Within one reconcile, deltas for the same (holder, thing, dir, reason) merge into one row. Across
reconciles, a row of the same key written < 60 s earlier is **amended** (quantity +=) rather than
appended — bounds row count for spammy activity (gathering, consuming, vendoring junk).

### 5.6 Login reconcile & genesis

At login (+3 s, after item cache warm-up): scan all always-readable containers, diff against the
stored snapshot for this holder.

- **No stored snapshot** (first login after v11) → write it as **genesis**; no rows.
  `meta.partial = true` until the bank has been opened once (bank/mail/auctions unknown).
- **Stored snapshot differs** → changes happened while the addon was off or the client was not
  this one; write `UNTRACKED` rows so holdings and rollup stay consistent.

§warband genesis happens on the first warband-bank open; warband gold is read at login if
`C_Bank.FetchDepositedMoney` answers outside the bank (verify in smoke; else first open).

## 6. Insights changes

- KPIs: **Gained / Lost / Net** (value and count), signed styling via `SignedCount`/`SignedMoney`
  (`+N` green, `−N` red, gray em dash for 0 — BankLedger).
- New section **Gains vs losses by reason**: back-to-back bars about a center axis, losses left in
  red, gains right in green, shared scale (`PeakShares`). Same treatment by character and by kind.
- Existing gain-only charts filter to `dir == IN` so their meaning does not change.
- If the date range spans `ledgerSince` and history was kept, a one-line note:
  *"Before <date> only gains were recorded — totals for that period overstate net."*

## 7. History tab changes

- New **Direction** column: ▲ gain / ▼ loss / ⇄ transfer, colored (gain green `0.35,0.80,0.45`,
  loss red `1,0.33,0.33`, transfer gray), glyphs in the LibKa0s mono face (default font renders
  them as boxes).
- Quantity column shows signed values; gold rows formatted as money (pale gold).
- New **Direction** multi-select filter: Gains, Losses, Transfers — default Gains + Losses.
- New group-by modes: Direction, Holder. Source filter/group lists the new reasons.

## 8. New tabs

### 8.0 Tab registry (prerequisite refactor)

`Browser.lua` is at 1318/1500 lines and hard-codes two tabs across `TABS`, `BuildPane`,
`SelectTab`, `ApplyFilter`, `OpenExport`. Replace with a registry:
`B:RegisterTab{ name, order, build(pane), refresh(filter), export?() }`. History and Insights
register first; Timeline and Holdings live in their own modules. The filter bar remains the
window-wide singleton; each tab declares which filters it honors (unused ones are greyed, not hidden).

### 8.1 Timeline (3rd tab)

- **Thing picker** at the head of the pane: Gold, or one currency/item. Driven by the shared
  search box (type-ahead over things present in holdings or rollup); last pick remembered in
  `savedView`. "Show in Timeline" from History/Holdings rows sets it.
- **Lines:** **Total** (sum over shown holders, thick) + one line per holder, capped at
  `timelineMaxLines` (default 8) ranked by latest balance; Character filter restricts holders;
  §warband is a selectable holder. Class colors for characters, warband in its own color.
- **Y axis:** native unit of the thing (gold / count). Linear; auto-scaled with nice ticks.
- **X axis:** Date filter. Options add **90 d** and **1 y**. Daily points from the rollup;
  **Today / 7 d** ranges with raw rows still in retention use per-reconcile points for intraday
  resolution.
- **Under-strip:** daily in/out bars (gains up green, losses down red) for the Total, reusing the
  `renderStrip` look.
- **Genesis / gaps:** a holder's line starts at its genesis; a vertical dashed marker at
  `ledgerSince`; a holder with `partial=true` draws dashed until its bank is first seen.
- **Hover:** crosshair + tooltip per date with each line's value and that day's in/out.
- **Primitive:** new pooled line-chart renderer using `Texture:CreateLine` (`SetStartPoint`,
  `SetEndPoint`, `SetThickness`) — none exists today. Built **in LibKa0s** (F3) as a pooled line-chart widget
  (lines, axes, ticks, crosshair hook), downsampled to ≤ 1 point per 2 px of width; reached here
  through a host seam `NS.MakeLineChart` (same pattern as `NS.MakeDropdown`).

### 8.2 Holdings (4th tab)

- One row per thing with **Total**; expand to per-holder rows, each with container breakdown
  (`Bags 12 · Bank 40 · Equipped 1 · Mail 5 · AH 3`) and staleness of the oldest contributing
  container.
- Honors search, Type, SubType, Quality, Character (→ holders, plus "Warband") filters; Date,
  Source, Direction greyed.
- Gold row (sum of `money`, with per-holder breakdown) and currency rows included.
- Sort by name / total / value (`Util.RecordValue` × count). Row action: **Show in Timeline**.
- Search over all holders is a linear scan (BagSync does the same) with an itemID → name cache
  and throttled `RequestLoadItemDataByID` for uncached names ("N items loading…").
- Character deletion: Holdings row context action "Forget this character" (confirm popup) drops
  its holdings and rollup cells; history rows are kept.

## 9. Migration v10 → v11 and the reset recommendation

### 9.1 Migration step (appended to `MIGRATIONS`, `to = 11`)

Creates `holdings = {}`, `daily = {}`, sets `ledgerSince = time()`; rewrites **no** rows (legacy
defaults via accessors, §4.1). Idempotent; returns 0 rows changed. Arms §9.2 by persisting
`global.resetPromptPending = true` when the history is non-empty (persisted, not in-memory: the
same load stamps schemaVersion 11, so a session-only marker could not re-ask after an Esc). Fresh
installs (no history) skip §9.2.

### 9.2 Reset recommendation popup

**When:** first `PLAYER_ENTERING_WORLD` (+5 s, out of combat — deferred to
`PLAYER_REGEN_ENABLED` otherwise) of a session where `global.resetPrompt == nil`, `global.resetPromptPending` is set (the DB was
migrated from < 11 with history; Keep, Reset and `/lh purge` clear it), and `#history > 0`. Shown **once per account**; the choice is stored in
`global.resetPrompt`. Re-reachable later with `/lh purge` (unchanged).

**Mechanism:** `StaticPopupDialogs["KA0S_LOOTHISTORY_LEDGER_RESET"]`, alongside the existing
confirm dialogs in `settings/Slash.lua`; three buttons.

**Text (draft):**

> **Loot History has become a full ledger.**
> It now tracks gains *and* losses of items, currencies and gold, plus what every character
> and your warband currently holds.
>
> **Recommended: start a fresh history.** Your existing <N> records only ever captured gains.
> Mixed with the new data, any period before today would show income with no spending, so
> net totals and Insights for that period overstate what you actually kept.
>
> **If you keep your history:** nothing is lost, and older loot stays browsable. But Insights
> net/loss figures are only accurate from today onward. Ranges that include older dates will
> carry a warning. The Timeline starts today either way.
>
> **If you reset:** older loot records are deleted permanently. Settings, filters and profiles
> are kept. Use Export first if you want a copy.

| Button | Action |
|---|---|
| **Reset history (recommended)** | Second confirm ("Delete <N> records permanently?") → same path as `/lh purge` (`Database:Purge`, fires `HISTORY_CHANGED`); `resetPrompt="reset"`; `ledgerSince = now`. |
| **Keep history** | `resetPrompt="kept"`; enables the Insights caveat note (§6). |
| **Export first** | Opens the browser's Export (CSV) with all rows; popup re-shows when the export window closes; `resetPrompt` stays nil. |

Esc / close = **not decided** (`resetPrompt` stays nil → shown next session). Holdings and rollup
are never reset by this prompt (they are new and correct).

## 10. Modules & files

| File | Role |
|---|---|
| `core/Ledger.lua` | pure functions: `Diff`, classify, coalesce key, claim matching, `DirSign`, rollup cell update. No WoW API — fully headless-testable. |
| `modules/Scanner.lua` | container reads (bags, equipped, bank, tabs, mail, auctions, currency, money) → count maps + links; bag ids from `Enum.BagIndex` names. |
| `modules/Reconciler.lua` | dirty sets, debounce/settle, combat deferral, calls `Ledger.*`, writes rows via `Database:Add`, updates holdings & rollup, login reconcile. |
| `modules/Holdings.lua` | holdings store API (`Get`, `Set`, `Total(thingKey)`, `Search(query, filter)`, `ForgetHolder`). |
| `modules/Attribution.lua` | extended with outbound stamps (§5.4). |
| `modules/Browser.lua` | tab registry refactor (§8.0). |
| `core/WidgetsSetup.lua` | `NS.MakeLineChart` seam over the LibKa0s line-chart widget (F3). |
| `modules/Timeline.lua` | Timeline tab. |
| `modules/HoldingsTab.lua` | Holdings tab. |
| `core/Database.lua` | migration v11, rollup prune, `Stats` gains/losses, export fields. |
| `settings/Slash.lua` | reset popup; `/lh holdings <query>` prints totals. |

Message bus (closed set; added per `docs/message-bus.md` recipe): **`HOLDINGS_CHANGED(holder)`**
(sender: Reconciler; receivers: Holdings tab, Timeline). New rows keep using `RECORD_ADDED`.
Every new module gets a real `Disable` (disabled-state conformance suite).

## 11. Settings (schema rows)

| Key | Scope | Default | Meaning |
|---|---|---|---|
| `settings.trackLedger` | profile | true | master toggle for losses/transfers/holdings/gold (off = legacy gains-only behavior) |
| `settings.recordGold` | profile | true | gold rows |
| `settings.showTransfers` | profile | false | default of the Direction filter's Transfers option |
| `settings.timelineMaxLines` | profile | 8 | 2–16 |
| `rollupRetentionDays` | global | 0 (Always) | daily rollup retention |

## 12. Testing

- **Headless (`lua tests/run.lua`):**
  - `test_ledger.lua`: Diff over count maps; intra-holder MOVE; inter-holder MOVE pairs; claim
    consume / partial / late claim; coalescing; DirSign totals; rollup cell math.
  - `test_reconciler.lua` with the mock: bag→bank deposit = MOVE only; vendor sell = OUT SELL +
    gold IN; potion in combat deferred and coalesced; guild deposit = OUT; mail to own alt =
    MOVE + recipient mail count; login drift → UNTRACKED; genesis on empty store; unreadable
    container never zeroed.
  - `test_database.lua`: v10→v11 step, idempotence, no row rewritten, legacy accessor defaults;
    rollup prune; Stats gains/losses.
  - `test_analytics.lua` / new `test_timeline.lua`: pools recycle on second pass; downsampling;
    line count cap; carry-forward.
  - Disabled-state suite covers the new modules.
- **Lint:** `luacheck .` 0/0.
- **Smokes (add to `docs/smoke-tests.md`):** bank deposit/withdraw (no gain/loss), warband
  deposit (MOVE pair), vendor junk, AH post → sell, mail to alt, guild deposit, potion in combat,
  crafting, disenchant, reset popup (all three buttons + Esc), Timeline with 1 / 8 / 16 lines,
  Holdings search for an uncached item, `C_Bank.FetchDepositedMoney` outside the bank.

## 13. Standards & scope flags — resolved 2026-10-06

| # | Item | Resolution (user-ratified) |
|---|---|---|
| F1 | `docs/scope.md:213` lists **gold** as a non-goal; scope also defines the addon as "a personal loot ledger". **Reverse the non-goal.** Scope change, not a standard deviation — rewrite scope.md (currency-reversal precedent, `scope.md:201`). |
| F2 | `performance-§12` exemption (no perf harness) has re-check trigger "first in-combat handler doing real work". Bag/money diffing at volume trips it. **Conform — add the perf harness:** wire the vendored-but-unused LibKa0s Perf and drop the exemption row from the deviations register (supersedes the decline recorded in issue #29). |
| F3 | Line-chart primitive is a reusable widget — candidate for LibKa0s (`library-stack`). **Build in LibKa0s from the start** as a new widget (e.g. `LibKa0s-Widgets` `LineChart`, or its own `LibKa0s-Chart` major), with its own tests in the LibKa0s repo; release a LibKa0s tag, then re-vendor here and bump the CLAUDE.md provenance line in the same commit (`test_vendor_sync`). |
| F4 | Export field shape is a "resolved decision" (`scope.md:223-226`). **Accepted:** append `dir, kind, holder, from, to` columns; existing columns keep their order; note in CHANGELOG and update the export field list in schema.md. |
| F5 | Min-quality setting changes meaning (gates rich records + default History view, no longer what gets captured). **Accepted:** re-label in settings text; document in scope.md. |
| F6 | `StaticPopupDialogs` for the reset prompt. | Matches existing host-owned confirms in `settings/Slash.lua`; no deviation expected. |

## 14. Delivery phases (one plan, gated milestones; green gate + commit at each)

1. **Foundation** — migration v11, `core/Ledger.lua`, Scanner, Holdings store, login genesis,
   tab registry refactor, **Holdings tab**, reset popup. *(Useful on its own.)*
2. **Ledger capture** — Reconciler, claims, outbound attribution, gold, coalescing, History
   direction column/filter, Insights gains-vs-losses.
3. **Timeline** — LibKa0s line-chart widget (built, tested and tagged in the LibKa0s repo, then
   re-vendored), rollup writing/pruning, **Timeline tab**.

Perf harness wiring (F2) lands in **phase 2**, together with the first in-combat handlers that trip
the exemption's re-check trigger.

## 15. Out of scope / deferred

- Guild bank contents as a holder (D3).
- Per-variant (bonus-ID) holdings counts — base itemID only.
- Cross-account sync; other players' loot.
- Back-casting balances before genesis (rejected in D5).
- Export-to-AI support for loss rows (follow-up).
- Void storage / legacy reagent bank (removed in Midnight).
