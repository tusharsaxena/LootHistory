# Attribution & capture engine

Ka0s Loot History's core subsystem. Two modules cooperate: `modules/Attribution.lua` (the source-resolution engine) stamps a short-lived context from peripheral events, and `modules/Collector.lua` (the acquisition path) consumes it on the authoritative "item received" signal to build one record per loot event. Attribution loads before Collector (TOC order) so the stamper is live before the first loot line.

The design question the engine answers: WoW gives you a reliable "you looted item X" signal, but not *why* — a green from a mob kill, a bag you opened, a mail attachment, and an AH win all arrive as the same `CHAT_MSG_LOOT` line. Attribution reconstructs the "why" by watching the peripheral events that *precede* the loot and leaving a breadcrumb the collector reads back.

## The authoritative signal: `CHAT_MSG_LOOT`

`CHAT_MSG_LOOT` is the one authoritative "item received (self)" signal, and the only event that writes a record. `Collector:OnChatMsgLoot` runs `NS.Util.ParseSelfLoot(msg)`, which matches the line against the localized self-loot global strings (`LOOT_ITEM_SELF_MULTIPLE`, `LOOT_ITEM_PUSHED_SELF_MULTIPLE`, `LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE`, `LOOT_ITEM_CREATED_SELF_MULTIPLE`, `LOOT_ITEM_REFUND_MULTIPLE`, then the singular `LOOT_ITEM_SELF`, `LOOT_ITEM_PUSHED_SELF`, `LOOT_ITEM_BONUS_ROLL_SELF`, `LOOT_ITEM_CREATED_SELF`, `LOOT_ITEM_REFUND`) compiled once into anchored Lua patterns. Lines that aren't the player's own loot (party members, etc.) don't match and return `nil` — that is the **self-filter**. Quantity-bearing patterns are tried first because their greedy `(.+)` link capture would otherwise swallow the trailing `xN` of a multiple-loot line.

### Self-identifying loot lines

Some self-loot lines name their own source: a bonus roll (`LOOT_ITEM_BONUS_ROLL_SELF`), a crafted item (`LOOT_ITEM_CREATED_SELF`, *"You create"*), or a token/vendor refund (`LOOT_ITEM_REFUND`, *"You are refunded"*). For these, `ParseSelfLoot` returns a third value — a `source` tag string — and the collector attributes the record to that source directly with `CERTAIN` confidence, **bypassing `Consume`**. This is deliberate: a bonus roll resolves seconds after the kill (well past `CONTEXT_TTL`), so a context read would return stale `OTHER` — or worse, mis-inherit the boss's still-fresh `KILL` stamp; a "You create" / refund line has no meaningful peripheral context at all.

### Roll wins are a two-line dance

Winning a group need/greed/transmog roll is the one source where the announcement and the item are *separate* lines. The roll-won line (`LOOT_ROLL_YOU_WON`, *"You won: X"*) arrives first, then the item is delivered a moment later on an ordinary `LOOT_ITEM_SELF` receive line. So the collector treats the win line as a **stamp, not a record**: `Util.ParseRollWon` detects it, `Attribution:StampRoll()` marks `ROLL` context, and `OnChatMsgLoot` returns without writing. The imminent receive line then `Consume`s that `ROLL` stamp instead of inheriting a stale kill/container context. This avoids the double-count that would occur if we recorded both the win line and the receive line.

Everything else — LOOT_OPENED, trade, mail, casts, merchant, container use, quest turn-in — is *peripheral*. None of it writes a record; it only stamps context.

### Currency

Currency rides a parallel signal: `CHAT_MSG_CURRENCY` → `Collector:OnChatMsgCurrency` →
`Util.ParseSelfCurrency`. It reuses the **same peripheral context** as items (`Attribution:Consume`)
for its source, since currency is delivered inside the same loot window. Currency records carry
`currencyID` + `itemType = "Currency"` (never an `itemID`), take a slimmer gate (the `recordCurrency`
master toggle + the per-source mute list; no quality/quest gate), and are stored in the same
`global.history` array. The gate does check its own **currency blacklist** —
`profile.currencyBlacklist` (per profile since schema v9), a separate id-set from the item blacklist/whitelist — so a
currency-blacklisted id is dropped at capture the same way a blacklisted item id is. See
[schema.md](schema.md) and the currency-capture spec.

**Listed currencies only.** The chat link can name a **hidden tracking currency** the token list never
shows (the 2026-10-06 report: "Nebulous Voidcore" arrived as hidden 3513 and listed 3418 a second
apart, two rows). After resolving the link, `Compat.ListedCurrencyID(id, name)` picks the id the row
records under: `id` itself when it is in the token list (the category cache's walk) or in the current
character's or `§warband`'s stored currency baseline (which covers a currency under a collapsed
header); otherwise the one listed or held currency with the same name (3513 → 3418); otherwise nil,
and the line is dropped with `[Drop] currency line reason=unlisted` and posts **no claim**. The
remapped id carries both the row and its claim, so the twin's holdings delta consumes it. A genuinely
new currency whose list entry is not there yet at chat time is dropped the same way; its first gain
then arrives as a diff row once the list has it (accepted). Rows stored under a hidden id before this
rule are not migrated (a cold client at migration time cannot tell listed from hidden); the owner
deletes them from the row menu. The holdings diff is already list-only (`Scanner.ScanCurrencies` →
`Compat.ListCurrencies`).

A **currency-vendor refund** rides this channel too: when you refund a purchase paid for with a
currency, the game returns the currency on `CHAT_MSG_CURRENCY` as a *"You are refunded"* line
(`LOOT_ITEM_REFUND` / `LOOT_ITEM_REFUND_MULTIPLE`) — **not** on `CHAT_MSG_LOOT`. So `ParseSelfCurrency`
also carries the two refund patterns and tags them `REFUND`; like the self-identifying item lines,
the collector then attributes `REFUND` directly with `CERTAIN` confidence, **bypassing `Consume`** (by
then the context holds the stale `VENDOR` stamp from the purchase). The result is a `Type = Currency`
row with `source = REFUND`. (Refunds that return an *item* would instead surface on `CHAT_MSG_LOOT` via
the loot-path `LOOT_ITEM_REFUND` handling — see the item-refund follow-up issue; that path is retained
but was not the case observed on modern currency vendors.)

## The single-slot context

Peripheral events call `Attribution:Stamp(source, detail, confidence, trigger)` (`modules/Attribution.lua:120`), which overwrites one slot on `State.lootContext` (`core/State.lua:7`):

```lua
State.lootContext = {
  source = source,        -- a Constants.SourceType key
  detail = detail,        -- npcID / encounter / keystone / questID, or nil
  confidence = confidence or CERTAIN,
  expires = GetTime() + Constants.CONTEXT_TTL,   -- ~1.5s
}
```

`Collector:OnChatMsgLoot` reads it back via `Attribution:Consume` (`modules/Attribution.lua:147`):

- **Fresh** (`expires >= GetTime()`) → returns the stamped `source, detail, confidence`.
- **Stale or never stamped** → returns the fallback `OTHER, nil, INFERRED`.

Two deliberate properties of this single-slot design — do not change either without reason:

1. **`CONTEXT_TTL` is ~1.5s** (`core/Constants.lua:67`). Long enough to bridge the gap between the peripheral event and the loot line it explains, short enough that an unrelated later loot doesn't inherit a stale source.
2. **Consume does not clear the slot.** One loot window emits many `CHAT_MSG_LOOT` lines that all share a source — a kill dropping four items, a bag with six stacks. Clearing on first consume would attribute only the first line and drop the rest to `OTHER`. The context intentionally survives the whole burst; the TTL, not consumption, ends it.

Confidence is `CERTAIN` for every live stamper and `INFERRED` only on the fallback path — so `confidence == INFERRED` is exactly "no fresh context existed when this item landed." See [schema.md](schema.md) for how `source` / `sourceDetail` / `confidence` are stored.

## Source resolution from the loot window

`LOOT_OPENED` is the richest stamper because the loot window exposes each slot's **source GUID**, and the GUID's *kind* determines the source. `Attribution:OnLootOpened` (`modules/Attribution.lua:196`) reads the first slot's GUID via `GetLootSourceInfo` and feeds it to the pure resolver `Attribution:ResolveLootSource` (`modules/Attribution.lua:165`), which decodes it through `NS.Compat.DecodeGUID` (`core/Compat.lua:143`):

| GUID kind | Instance state | Source | Detail |
|---|---|---|---|
| `Creature` / `Vehicle` / `Pet` / `Vignette` (`Compat.UNIT_KINDS`) | encounter active, or a won encounter inside its grace window | `KILL` | `{ npcID, encounterID, difficulty }` |
| `Creature` / … | no encounter (or the grace window has passed) | `KILL` | `{ npcID }` |
| `GameObject` | keystone active | `MPLUS` | `{ keystoneLevel }` |
| `GameObject` | no keystone | `CONTAINER` | — |
| `Item` | — | `CONTAINER` | — |
| anything else | — | `OTHER` | — |

The unit-kind set lives in `Compat.UNIT_KINDS` (`core/Compat.lua:139`) as the single source of truth, so KILL detection can't drift from GUID decoding. All slots in one window share a source closely enough that stamping from the first slot is sufficient; the TTL then spans the resulting `CHAT_MSG_LOOT` burst.

### Instance context enrichment

The encounter and keystone detail is layered on by separate rolling-context stampers that write `State.encounter` / `State.keystone` (`core/State.lua:10-11`) rather than the loot context:

- `ENCOUNTER_START` → `OnEncounterStart` sets `{ id, name, difficulty }` (`modules/Attribution.lua:221`); `ENCOUNTER_END` → `OnEncounterEnd` (`modules/Attribution.lua:232`) keeps it on a kill (`success == 1`) with `expires = GetTime() + Constants.ENCOUNTER_GRACE` (60 s, `core/Constants.lua:73`), because the boss corpse is looted *after* `ENCOUNTER_END`; on a wipe it clears it. `ResolveLootSource` treats the context as live while it has no `expires` or the clock is still at or before it, so KILL loot during the pull and from the corpse inside the window carries the encounter id + difficulty. Trash KILL loot inside the same window carries it too, which is accepted. The next `ENCOUNTER_START` replaces the table, so a new pull drops the old expiry.
- `CHALLENGE_MODE_START` → `OnChallengeModeStart` records `{ level }` from `NS.Compat.GetActiveKeystoneLevel` (`core/Compat.lua:29`). `CHALLENGE_MODE_COMPLETED` deliberately **keeps** the keystone context (refreshing the level) rather than clearing it, because the reward chest is looted shortly *after* completion and its GameObject GUID must still resolve to `MPLUS` (`modules/Attribution.lua:253`); a completion-time level of 0 is ignored rather than stored.
- The keystone context ends when the player leaves the party instance: `ZONE_CHANGED_NEW_AREA` → `OnZoneChanged` (`modules/Attribution.lua:270`) clears it when `NS.Compat.InPartyInstance` (`core/Compat.lua:38`) is false, and `CHALLENGE_MODE_RESET` → `OnChallengeModeReset` (`modules/Attribution.lua:291`) clears it outright. Inside a party instance with no context, the same zone-change handler re-arms it from `GetActiveKeystoneLevel` when a key is active, because `CHALLENGE_MODE_START` does not fire again for a player who zoned back into a running key. Each is one API call per zone change.

## Peripheral stampers

Sources that arrive without a loot window (or whose window would mis-resolve) each stamp just before their resulting self-loot line. Registered in `Attribution:Enable` (`modules/Attribution.lua:400`) via events and `hooksecurefunc`:

- **VENDOR** — `hooksecurefunc("BuyMerchantItem")` → `StampVendor` (`modules/Attribution.lua:299`).
- **TRADE** — `TRADE_ACCEPT_UPDATE` → `OnTradeAcceptUpdate` (`modules/Attribution.lua:363`); stamps only when **both** `playerAccepted` and `targetAccepted` are `1` (trade actually completed).
- **MAIL / AH** — `hooksecurefunc` on both `TakeInboxItem` and `AutoLootMailItem` → `StampMail` (`modules/Attribution.lua:372`). The mail's sender/subject decides which: `NS.Compat.IsAuctionHouseMail` (`core/Compat.lua:121`) matches the `AUCTION_HOUSE` sender or an AH subject prefix (won / expired / canceled / invoice, built from the localized `*_MAIL_SUBJECT` globals) → `AH`; everything else → `MAIL`. This is the only stamper for `AH` — there is no live auction-house-frame stamper.
- **QUEST** — the client-side `hooksecurefunc("GetQuestReward")` → `StampQuestReward` (`modules/Attribution.lua:392`) is the primary path: it fires *before* the server pushes the reward items, so the stamp is fresh when the reward loot line lands. The `QUEST_TURNED_IN` event → `OnQuestTurnedIn` (`modules/Attribution.lua:383`) is a backstop; alone it can fire *after* the reward line and miss it. Detail carries the quest id when the quest frame still exposes it (`NS.Compat.CurrentQuestID`, `core/Compat.lua:76`).
- **CONTAINER (bag item)** — opening a container/lockbox from bags pushes contents to inventory with no `LOOT_OPENED` or GUID, so `NS.Compat.HookUseContainerItem` (`core/Compat.lua:47`, `C_Container.UseContainerItem` on retail) → `OnContainerItemUse` (`modules/Attribution.lua:320`) stamps `CONTAINER` — but **only** when the item actually has loot (`Compat.ContainerItemHasLoot`) **and** no spell is awaiting a target (`Compat.IsSpellTargeting`). Clicking a bag item as a Disenchant/Enchant target also routes through `UseContainerItem`, and that must not be read as opening a container.

### Deconstruct: DISENCHANT / MILLING / PROSPECTING

Disenchant, Milling, and Prospecting each stamp their **own** first-class source rather than a generic "Craft," so the Source column reads the ability. Their materials arrive through a loot window whose `Item` GUID would otherwise resolve to `CONTAINER`, so this stamper both attributes the source *and* protects that attribution.

`UNIT_SPELLCAST_SUCCEEDED` (filtered to `unit == "player"` via a dedicated `RegisterUnitEvent` frame, to avoid the raid-wide cast firehose) → `OnSpellSucceeded` (`modules/Attribution.lua:340`) maps the completed cast to a source through `Attribution:DeconstructSource` (`modules/Attribution.lua:85`):

1. **Spell-id match first** — `DECONSTRUCT_ID` (`modules/Attribution.lua:32`), a locale-independent table of the base + primary per-expansion spell ids (plus a representative per-herb/ore "Mass" spell per family). Authoritative and language-agnostic; this alone attributes the common cases on every client.
2. **Localized name-family fallback** — for the un-enumerated per-herb/ore "Mass Mill/Prospect" variants (too many to list, and growing each patch). The cast's **localized** name is matched against localized reference tokens derived at match time from seed spellIDs via `NS.Compat.GetSpellName` (`core/Compat.lua:103`) — `NAME_SEEDS` (`modules/Attribution.lua:53`). No hardcoded English literal is ever compared: `GetSpellName` returns the client-locale name, so the "Milling" seed becomes "Mahlen" on deDE and the check follows the player's language automatically (a localization-§4 / anti-pattern #37 departure, ratified in `docs/ARCHITECTURE.md` → Documented deviations). `dropLast` seeds match the shared command prefix (`Mass Mill …`) minus the herb/ore word.

Because this fires on **every** player cast (a combat rotation included), the `(spellID → source)` resolution is **memoized per spellID** on `OnSpellSucceeded` (`modules/Attribution.lua:340`): the mapping is immutable for a session, so a repeated cast costs one table lookup — no `GetSpellName`, no name-family loop, no allocation. Only *conclusive* results are cached — `DeconstructSource` returns a second `conclusive` flag: a positive is always conclusive, a negative only once every seed name has resolved, so a not-yet-cached name can't freeze a wrong miss. The debug `[Cast]` trace logs **only** the deconstruct hits, never the non-deconstruct majority (no per-cast spam).

The cast succeeds right as the materials are produced, so the stamp is fresh within TTL. `Attribution:OnLootOpened` then guards against clobbering it: if the live context is already one of `DECONSTRUCT_SOURCE` (`modules/Attribution.lua:45`), the subsequent material-window `LOOT_OPENED` returns early and keeps the more specific deconstruct stamp (`modules/Attribution.lua:201`).

## The collector's gates

Once `Collector:OnChatMsgLoot` has a link and a resolved `(source, detail, confidence)`, it decides whether to record. The pure seam `Collector:ShouldRecord` (`modules/Collector.lua:50`) applies three gates in order and, on a drop, returns a reason for the debug log:

1. **Quality** — `quality < qualityThreshold` → drop (`"quality"`). Threshold options in `Constants.QUALITY_OPTIONS`.
2. **Excluded source** — the item's source is muted in `excludedSources` → drop (`"source"`).
3. **Quest item** — when `excludeQuestItems` is on and the item's class is `Constants.ITEMCLASS_QUEST` (`core/Constants.lua:48`, `Enum.ItemClass.Questitem` = 12) → drop (`"quest"`). The gate keys on the **locale-independent item class id**, never the localized `itemType` string, so it works on every client.

The `CHAT_MSG_LOOT` self-filter (`ParseSelfLoot` returning `nil`) is the implicit gate ahead of all three.

Records that pass are assembled by `Collector:BuildRecord` (`modules/Collector.lua:60`) — one record per loot event — and handed to `NS.Database:Add`. Item extras (ilvl, bound, sell price, type/subtype) come from `NS.Compat.GetItemExtras`; the `classFile` coloring token from `UnitClass("player")`.

### Hot-path upvalues

The three gate settings are cached as file-local upvalues (`modules/Collector.lua`), not re-read from the DB on every loot line (standard events-frames-taint-§7). **`enabled` is no longer one of them, and its removal is the point rather than a tidy-up** — it used to be read at the top of `OnChatMsgLoot`, which is the DRAW GATE `anti-patterns #85` names: the handler stopped reacting and the addon never stopped watching, so the client walked the registration list, built the argument frame and entered Lua on every loot line in the raid for an addon the player had switched off. Disabling now tears `CHAT_MSG_LOOT` and `CHAT_MSG_CURRENCY` out entirely ([disabled-state.md](disabled-state.md)), so there is nothing left to gate — and a flag kept beside a real unregister is a second answer to “is this addon running” that can disagree with it. `Collector:RefreshUpvalues` (`modules/Collector.lua:87`) reloads them — and rewrites the one module-level `gateCfg` table that `OnChatMsgLoot` hands `ShouldRecord`, so a loot line sets only `gateCfg.itemID` and allocates no config table (`ShouldRecord` reads `cfg` and never keeps it) — and the collector subscribes to `Ka0s_LootHistory_SettingsChanged` to refresh on any settings write (`modules/Collector.lua:266`). That subscription registers on a **private** `NS.NewBusTarget()`, never the shared bus-as-self, so it doesn't clobber the Browser's handler for the same message — see [message-bus.md](message-bus.md).

## Wired vs enum'd sources

`Constants.SourceType` (`core/Constants.lua:8`) is the whole enum and the stable **export contract** — keys are never renamed. Every member now has a live capture path, but they fall into three kinds by *how* they are attributed:

- **Peripheral stamp:** `KILL`, `CONTAINER`, `MPLUS`, `QUEST`, `VENDOR`, `MAIL`, `TRADE`, `AH`, `DISENCHANT`, `MILLING`, `PROSPECTING` — reconstructed from a preceding event and read back via `Consume` (see [The single-slot context](#the-single-slot-context)).
- **Self-identifying loot line:** `BONUS_ROLL`, `CRAFT`, `REFUND` — attributed straight from the loot line, no peripheral context (see [Self-identifying loot lines](#self-identifying-loot-lines)).
- **Two-line stamp:** `ROLL` — the "You won:" line stamps context and the follow-up receive line consumes it (see [Roll wins are a two-line dance](#roll-wins-are-a-two-line-dance)). Distinct from `BONUS_ROLL`, the seal-of-fate bonus-roll reward.
- **Fallback:** `OTHER` — no fresh context and no self-identifying line.

`Constants.SOURCE_IMPLEMENTED` (`core/Constants.lua:37`) is the gate: it lists sources with a live capture path, and drives `SOURCE_OPTIONS` so the settings panel's per-source **mute list** never shows a dead checkbox. With every source now wired, all appear in the mute list. The enum stays whole for the export seam. See [compat-layer.md](compat-layer.md) for the shims and [module-map.md](module-map.md) for where these modules sit.

## Holdings scan

A second, independent engine sits beside loot capture: the **Reconciler** (`modules/Reconciler.lua`) keeps `db.global.holdings` equal to what the account owns, using `NS.Scanner` for the reads and `NS.Holdings` for the writes (timeline-ledger spec §5.2). It never touches `CHAT_MSG_LOOT` or the attribution context; Phase 2 is where the two meet, as a diff of successive scans that the existing context then claims.

**Events mark, `Flush` works.** Fourteen events register one by one on a private bus target, and only while `settings.trackLedger` is on. A handler does nothing but set a dirty bit (`MarkDirty`) and, for the events that close a burst, arm a 0.35 s `NS.After` fuse:

| Event | Marks | Arms the fuse |
|---|---|---|
| `BAG_UPDATE(bagID)` | `bags` (that bag), or `bank` / `tabs` when the bag id belongs to the bank or a warband tab | no |
| `BAG_UPDATE_DELAYED` | nothing | yes (it ends the burst of `BAG_UPDATE`s) |
| `PLAYER_EQUIPMENT_CHANGED` | `equipped` | yes |
| `PLAYER_MONEY` / `ACCOUNT_MONEY` | `money` / `warbandMoney` | yes |
| `CURRENCY_DISPLAY_UPDATE(id, qty, change, gainSrc, lostSrc)` | `currencyDelta` (the change is folded into `pendingCur[id]`, the source enums kept for the reason); a nil id marks `currency` for a full list rescan | yes |
| `CURRENCY_TRANSFER_LOG_UPDATE` | `currencyDelta` (sets `pendingTransfer`: the flush writes the loss as an OUT here and an IN on the own alt, both `CURRENCY_TRANSFER`, and credits the alt's stored currency) | yes |
| `PLAYERBANKSLOTS_CHANGED` / `PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED` | `bank` / `tabs` | yes |
| `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` / `_HIDE` | per `R.READABLE_ON`: bank, tabs, warband gold for a Banker or AccountBanker; `mail` for the mailbox; nothing for the auction house (its list waits for `OWNED_AUCTIONS_UPDATED`). Show sets the readable flag | show yes; hide runs a final `Flush` itself, then clears the flag |
| `MAIL_INBOX_UPDATE` | `mail`, only while the mailbox is open (escrow: `modules/Escrow.lua`) | yes |
| `OWNED_AUCTIONS_UPDATED` | `auctions`, only while the auction house is open; it is also what makes the owned list readable | yes |
| `PLAYER_REGEN_ENABLED` | nothing | runs a pending login reconcile, else replays a deferred flush |

`BAG_UPDATE` carries no fuse of its own on purpose: a raid-pull storm costs one table write per event and nothing else.

**Combat deferral.** `Flush` begins with `Compat.InCombatLockdown()`. In combat it sets `deferred` and returns, leaving every dirty bit in place; `PLAYER_REGEN_ENABLED` clears `deferred` and flushes once, so five potions drunk mid-pull cost one refresh after the fight, not five scans during it.

**Readability.** The client answers an unopened bank slot as *empty*, not as *unknown*, so reading it away from a banker would record the whole bank as lost. `R:IsReadable(part)` therefore gates `bank` and `tabs` on `readable.bank`, set only between the show and hide of a `Banker` or `AccountBanker` interaction (`Compat.InteractionType`); warband gold is readable only when `Compat.GetWarbandMoney()` answers non-nil. An unreadable part **stays dirty** for the next flush rather than being dropped. The hide handler flushes once more while the bank is still readable, then clears the flag.

**Changed once.** `Flush` applies each readable part (`ApplyContainer` / `ApplyCurrency` / `ApplyMoney`, each returning whether anything moved), collects the changed holders into a set and sends `HOLDINGS_CHANGED` once per holder. A flush that changed nothing sends nothing and, with debug on, writes nothing.

**Login genesis and drift.** `LoginScan` marks everything dirty and flushes, then stamps `meta.genesis` and `meta.partial` on the character (and on the Warband when it already exists). The first login after v11 flushes `silent` (no rows: the snapshot is the genesis); every later login flushes with `forceReason = UNTRACKED`, so whatever changed while the addon was not watching is written as `UNTRACKED` rows with no hold and no claim consumed. `Enable` after a stand-down in a session that already logged in schedules the same scan a second later, so changes made while stood down land as `UNTRACKED` too. A login inside combat (a reload mid-pull) sets `loginPending` and defers both the read and the stamp to the regen edge, so genesis never lands on a holder that was not scanned. A fresh holder stays `partial` until its bank (for the Warband, its tabs) has been read once, which is why a new character's bank shows **never** until the first banker visit.

**Turning it off.** Unticking `trackLedger` runs `DisableCapture`: the capture target is unregistered, dirty bits and `deferred` are cleared, and the `SettingsChanged` listener stays so re-ticking re-registers. `NS.StandDown` runs the full `Disable`. See [disabled-state.md](disabled-state.md).
## The ledger: holdings diff + claims

Phase 2 turns the holdings scan into the ledger's writer (timeline-ledger spec §5). The Reconciler still only *reads* the account; what changed is what it does with a difference. This section follows one `Flush` through its steps. Placement note: it sits after [Holdings scan](#holdings-scan) rather than directly after [The collector's gates](#the-collectors-gates), because it builds on the fuse, readability and combat rules stated there.

### Scan → plan → hold or commit

`flushBody` (`modules/Reconciler.lua`) runs four steps, and three of them are extension lists so a module can add its own without editing the Reconciler:

1. **Scan.** `R:Scan` reads every dirty, readable part into a snapshot, then runs each `R.SCAN_STEPS` function. `modules/Escrow.lua` adds the mail and owned-auction columns; the currency step turns the per-id accumulator into a currency map (see [Currency](#currency-from-event-args-not-a-rescan)).
2. **Plan.** `R:Plan` diffs the snapshot against the stored holdings (`Ledger.Diff`), classifies each item (the three cases below), then runs each `R.PLAN_STEPS` function (mail sends, auction posts, mail money, exits, account currency transfers). The result is `plan.moves`, `plan.pairs`, `plan.net` and `plan.extra`.
3. **Hold or commit.** `R:DecideHold` may postpone the whole pass (next paragraph). Otherwise each `R.COMMIT_STEPS` function runs (claims consume, escrow credits, the currency memo), `applySnap` writes the new counts into Holdings, and `WriteRows` writes the rows.
4. **Announce.** `HOLDINGS_CHANGED` once per changed holder, as in Phase 1.

**Hold.** A pass is held (nothing written, dirty bits kept, the stored baseline untouched) while a change is plausibly half done: a one-sided item change at an open bank, mailbox or auction house (the other half is a server round trip away), a one-sided gold change at a bank, or a gain whose chat claim has not arrived yet. `Ledger.ShouldHold` bounds both waits: `SETTLE_TIMEOUT` = 6 s for the one-sided case, `CLAIM_WAIT` = 1.5 s for the unclaimed gain. `ScheduleRecheck` arms a `CLAIM_WAIT` timer so a quiet client still comes back; events do the real re-checks. A one-sided gold change at a mailbox (postage) or a vendor is never held, because nothing is coming to pair with it. A login or resume pass (`forceReason`) and a genesis pass (`silent`) never hold.

### The three classification cases (spec §5.1)

`Ledger.ClassifyItems` compares the before and after count of one item across every container that was readable in both scans (a container that was not read is never inferred empty):

1. **Intra-holder MOVE.** An item left one container of a holder and arrived in another (bags to bank, bags to mail, mail to bags). One `MOVE` row, `from` and `to` naming `holder/container`. Mail and auction columns are *escrow*: they pair only with a non-escrow container, and an escrow source moves only its own-origin count (`escrow.mailOwn`); the rest is a gain from outside.
2. **Inter-holder move: a loss and a gain.** The same thing went down on one holder and up on another in the same flush (warband bank, warband gold, an account currency transferred to an alt). `Ledger.PairHolders` pairs opposite-sign nets for the smaller magnitude and `WriteRows` writes **an `OUT` on the sender and an `IN` on the receiver** (owner decision 2026-10-06, Phase 7), both carrying the same `from` / `to`, the same action reason (`WARBAND_DEPOSIT` character to `§warband`, `WARBAND_WITHDRAW` `§warband` to character, `CURRENCY_TRANSFER`, `ALT_MAIL`, `ALT_TRADE`) and one shared `pairId` (`"<ts>:<n>"`). Inside the 60 s coalescing window each half amends only its own row: the coalescing key carries holder and `dir`, so an `IN` never folds into an `OUT`.
3. **Net IN / OUT.** What is left after pairing is a real gain or loss, written as `IN` or `OUT` with a reason (below).

### Claims: the chat paths and the diff meet

A loot, currency or money chat line writes its rich row immediately (source, zone, price) and **posts a claim** for that thing (`Collector`'s `claim`, then `Reconciler:PostClaim` into `Ledger.PostClaim`). When the diff sees the same thing arrive, `Ledger.ConsumeClaim` matches it, and the commit step's claim pass stamps the existing chat row as the ledger row it now is (`dir = "IN"`, `holder`, `claimed = true`, `kind`) instead of writing a second one. Only an unclaimed remainder becomes a diff row.

- **Both orders work.** Claim first (the usual case: the chat line precedes the bag update) consumes on the next flush. Delta first holds the pass for up to `CLAIM_WAIT` waiting for the line; past that the gain is written as a plain row.
- **Partial.** A claim for 3 against a gain of 5 consumes 3 and leaves 2 for the diff; a claim for 5 against a gain of 3 leaves 2 on the claim for the next arrival.
- **TTL.** A claim expires `CLAIM_TTL` = 5 s after it is posted; `PruneClaims` drops the dead ones at the top of every flush.
- **Gated-out lines post none.** A line the Collector gates out (quality below **Minimum quality**, a muted source, a quest item) writes no rich row and posts no claim, so the diff books the arrival as a plain row (spec D2: the ledger counts everything, the gate only decides which rows are *detailed*). A blacklisted id or currency never gets a row at all, and `recordCurrency` / `recordGold` off suppress those kinds (`rowAllowed`); holdings count them regardless.

### Reasons

Every diff row needs a reason, and `Ledger.PickReason(kind, dir, ctx)` chooses it from what the two stamp slots and the interaction scopes say. `Attribution:ReasonContext` (`modules/AttributionOut.lua`) hands it the context. There are **two context slots**: `State.lootContext`, the Phase 1 stamp that says why something *arrived*, and `State.outContext`, the new one that says why something *left* (`StampOut`; fresh for `CONTEXT_TTL`, restricted to the `dirs` and `kinds` it names). Beside them `State.scopes` records which interaction frames are open (merchant, trainer, taxi, mailbox, auction, bank, guildBank), set from `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` / `_HIDE` and the `GuildBankFrame` hooks.

Precedence, first match wins:

1. `forced`: a login or resume pass says `UNTRACKED`.
2. A live **outbound stamp** that applies to this direction and kind (`REPAIR`, `BUY`, `DESTROY`, `AH_SOLD`, `TRADE_GIVE`, ...).
3. A **currency source** reason (`CURRENCY_DISPLAY_UPDATE`'s gain or destroy enum, mapped through `C.CURRENCY_SOURCE_REASON`).
4. An open **scope**: guild bank (`GUILD_DEPOSIT` / `GUILD_WITHDRAW`); merchant (`SELL` / `BUY` for what leaves, `VENDOR` for an item that arrives, `SELL` for gold that arrives); for gold leaving: trainer `TRAINING`, taxi `TRAVEL`, auction house `AH_POST_FEE`, mailbox `MAIL_SEND`.
5. For an **item loss**: a fresh deconstruct loot context gives `DECONSTRUCT`, a craft window (`CRAFT_TTL` = 6 s after a `C_TradeSkillUI` craft call) gives `CRAFT_REAGENT`, a consumable item gives `CONSUME`.
6. For a **gain**: the live loot context's source, else `MAIL` at an open mailbox, else `AH` at the auction house.
7. `OTHER`.

The reason for a key is **memoized** when the pass is planned or held (`memoReasons`), so a stamp that expires during a hold still attributes the change it was stamped for.

### Coalescing

`R:Write` keeps `recent[coalesceKey]`, with the key built from holder, thing, direction, reason and route. A same-key row younger than `COALESCE_WINDOW` = 60 s is **amended** (`Database:Amend(index, addQty)`) instead of appended, so three potions drunk across a pull, or a stack sold in chunks, become one row. Amend runs the same write hooks as Add and sends `RECORD_ADDED` again with the same `(record, index)`. Coalescing also happens within a single pass, because the net is already summed per key.

### Currency from event args, not a rescan

`CURRENCY_DISPLAY_UPDATE` carries `(currencyType, quantity, quantityChange, gainSource, lostSource)`, so `R:OnCurrencyUpdate` folds the change into `pendingCur[id]` and keeps the two source enums; no currency list is walked. A nil id (the client's bulk refresh) marks `currency` for a full rescan instead, and a full rescan in the same pass is authoritative over the deltas. A holder with no stored currency baseline also falls back to a rescan, because a delta on nothing would invent a whole balance, and so does a delta for an id the holder's baseline does not hold: the event also fires for hidden and tracking currencies the list never shows, and folding those would pair an `IN` now with an `UNTRACKED` `OUT` at the next full rescan. Account-wide currencies (`Compat.CurrencyIsAccountWide`) accrue to `§warband`. `CURRENCY_TRANSFER_LOG_UPDATE` sets `pendingTransfer`; the plan step pairs the loss with the own alt named in `Compat.LatestCurrencyTransfer` as an `OUT` here and an `IN` on the alt (both `CURRENCY_TRANSFER`, one `pairId`) and credits that alt's stored currency, so its next login reconciles clean. Whatever the transfer consumed beyond what arrived stays an `OUT` with reason `TRANSFER`.

### Mail and auction-house escrow (`modules/Escrow.lua`)

Items in transit are *holdings-only* until they resolve: they sit in the `mail` and `auctions` columns with no row.

- **Send to an own alt.** The `SendMail` post-hook stages `State.pendingMail`; `MAIL_SEND_SUCCESS` confirms it. The plan pairs the loss in bags with the alt's mail: the sender writes an `OUT ALT_MAIL` now, and the alt's `IN ALT_MAIL` waits until it takes the mail (the alt's `mail` column, `escrow.mailOwn`, `escrow.mailAlt`, `escrow.mailMoney` and `escrow.mailMoneyAlt` grow as the in-flight credit). Attachment gold that left is a gold `OUT ALT_MAIL` the same way; postage stays `OUT MAIL_SEND`. The staged send is used up only as far as it paired, so a money-only pass that lands before the bag change leaves the items staged for the next pass; `expires` retires anything left.
- **Taking mail.** The own-origin part (`mailOwn`) consumes `mailOwn`: what an own alt sent (`mailAlt`, a subset) is an `IN ALT_MAIL` mail to bags (the alt's move landing), the rest of it (an auction's return) a `MOVE`; what is left is an `IN` (`MAIL`, or `AH` for auction mail) from outside. Gold taken while `escrow.mailMoney` is owed is an `IN ALT_MAIL` mail to money for the part an alt sent since Phase 7 (`escrow.mailMoneyAlt`, taken first) and a `MOVE` for the rest (gold sent before Phase 7, whose pair v13 already turns into an OUT + IN), except while a sale mail's payout is live (`State.soldMail`: it stays `IN AH_SOLD`) or when the `TakeInboxMoney` hook saw a sender who is not an own holder (`State.mailTaken`: another player's gold is a gain).
- **Post.** A post hook records `State.pendingPost[itemID]`; the item leaving bags and appearing in the owned-auction list is a `MOVE` to `me/auctions`, and the deposit is `OUT AH_POST_FEE`.
- **Exit.** An auction that leaves the owned list is held as an *exit* (`escrow.exits[id] = { n, ts }`) until it resolves: it comes back by mail (a return: own-origin mail, so the take is a `MOVE`), a sale mail names it (item `OUT AH_SOLD`; the gold arrives `IN AH_SOLD` when the money is taken), or `EXIT_TTL` = 30 days passes and it is booked as sold.

### Login and resume: `UNTRACKED`

`LoginScan` and the resume scan run with `forceReason = UNTRACKED`: no hold, no claims, and every difference between the stored holdings and what the account holds now becomes an `UNTRACKED` row. The first login after the upgrade runs `silent` (genesis, no rows). Resume means `Enable` after a stand-down in a session that already logged in; it schedules the same scan one second later. The disabled-at-login gap is a known limitation (ARCHITECTURE.md).

The bank and the warband tabs are not part of that scan: outside a banker the client answers their slots as empty, so they can only be read at one. Their drift is therefore taken on the **first read of each banker visit**. Opening a `Banker` or `AccountBanker` frame (`R.READABLE_ON`, `drift = true`) sets `driftPending`; the next `Flush` first runs a drift pass over `bank`, `tabs` and `warbandMoney` alone, with `forceReason = UNTRACKED` and no plan steps (no hold, no pairing, no claims), so a bank-to-warband move made elsewhere lands as an `UNTRACKED` OUT on the character and an `UNTRACKED` IN on `§warband`, not as a `MOVE`. Any other dirty part (a bag change in flight) is flushed right after it with normal classification, and later flushes of the same visit are ordinary capture (a deposit to your own bank is one `MOVE` row; one to the warband bank is an `OUT` on the character and an `IN` on `§warband`, both `WARBAND_DEPOSIT`). A container read for the first time has no baseline, so that read is its genesis: no rows, and the holder's `partial` flag ends. Two PCs that each run the addon keep separate SavedVariables, so each sees the other's play as `UNTRACKED` drift: totals stay right, reasons are lost (a known limitation in ARCHITECTURE.md).

### Combat

A handler in combat does **nothing but set a dirty bit**, or, for `CURRENCY_DISPLAY_UPDATE`, add to the per-id accumulator (a table write, no allocation after a currency's first event). No scan, plan, claim or row work runs; `PLAYER_REGEN_ENABLED` flushes once. A login in combat defers the scan and its genesis stamp to the same edge. The five handlers that do run in combat are the `LibKa0s-Perf` buckets (`core/PerfSetup.lua`, [performance.md](performance.md)).

## Daily rollup

The Timeline reads `db.global.daily`, a sparse `["YYYY-MM-DD"][holder][thingKey] = { c, i, o }` store (close, gained, lost; see [schema.md](schema.md#the-ledger-stores)), written by `modules/Rollup.lua`. The spec (§4.3) first said the reconciler writes it "alongside each row"; Phase 3 split it across two seams instead, and the reasoning is kept here because a later change to capture has to know what it would break (Phase 3 plan, S4).

### The two seams

**Closes come from `NS.Holdings`' write methods; gained and lost tallies come from `NS.Database:OnWrite`.** Phase 2 already provided the second seam. The Phase 2 contract the rollup relies on, verbatim from the Phase 3 plan:

1. **Every holdings write goes through `NS.Holdings`' methods** — `ApplyContainer`, `ApplyCurrency`, `ApplyMoney` (Phase 1) and `CreditCurrency`, `CreditEscrow` (Phase 2). Phase 3 adds, inside each, a call `NS.Rollup:NoteClose(holder, thingKey, ts, close)` for every thing whose total changed, with `close` read from the store **after** the write. Nothing writes `db.global.holdings[...]` tables directly.
2. **Every IN/OUT/MOVE row is written through `NS.Database:Add` or `NS.Database:Amend`**, which run the `OnWrite` hooks synchronously with the quantity that changed (`deltaQty`) and `isNew`. The receiver is `NS.Rollup:OnWrite(row, deltaQty, isNew)`; it reads only `NS.Util.RowDir/RowKind/RowHolder`, `row.itemID`, `row.currencyID`, `row.ts`. `MOVE` rows tally nothing; an amend tallies only its delta, on the day it happens.
3. **`RECORD_ADDED` stays a repaint signal.** The Timeline listens to it (coalesced) to repaint; nothing in Phase 3 counts it, because Phase 2 re-sends it on every amend.
4. **An inter-holder transfer is an `OUT` on the sender and an `IN` on the receiver** (Phase 7; before it, a `MOVE` pair, which the v13 step converts), each with `holder` = that side, `from` / `to` = `"<holder>/<container>"` and one shared `pairId` (`R:WriteRows`). The rollup tallies each half on its own holder like any loss or gain. The Timeline's intraday (Today / 7 d) reconstruction reads the halves through `TimelineModel.RowDelta` (by holder and direction; a legacy inter-holder `MOVE` still signs by its ends), and it falls back to daily points whenever the rebuilt balance disagrees with the rollup, so a violation degrades the resolution rather than drawing a wrong line.

**Why two seams and not one Reconciler call.** The close is a holdings fact, and `NS.Holdings`' write methods are the only place a total changes, so they see every change exactly once (genesis, login drift, intra-holder moves, both sides of a transfer, escrow credits) with no knowledge of the Reconciler's scan, plan and commit internals. A chat-path row (`Collector`) is written *before* the Reconciler commits the matching delta, so a close read when that row is written would be stale, while the tally of the same row is exactly right. And the row hook is synchronous and carries the delta, so an amended row is counted once per delta; counting `RECORD_ADDED` would count an amended row's whole quantity again. Both receivers are O(1) table writes, which is why they are allowed on the combat path (see [Combat](#combat) below: they add no scan and no allocation beyond a day's first cell).

### Seed, prune and forget

- **Seed.** Holdings that existed before the rollup was written have no cell anywhere, and a thing that never changes again would never get one. `Rollup:SeedOnce(ts)` writes today's close for everything held, once per account (`db.global.rollupSeeded`), and never overwrites a close already written today.
- **Prune.** `Rollup:Prune(now)` applies `db.global.rollupRetentionDays` (`0` = Always, a no-op). It drops the days before the cutoff and folds each thing's newest pruned close onto the cutoff day first (`Ledger.PruneDaily`), so a line still starts from its last known value. In and out tallies are not folded.
- **Timing.** Both run from the five-second login deferral in `core/LootHistory.lua` (`NS.After`, cancelable, after the three-second login scan so the seed reads this login's holdings), and only while the rollup is enabled. Neither runs on an event. A retention change is applied at the next login; changing it deletes nothing on the spot.
- **Forget.** `Reconciler:ForgetHolder` calls `Holdings:ForgetHolder` and `Rollup:ForgetHolder` (which drops that holder's cells from every day and empties the days it leaves bare), then sends `HOLDINGS_CHANGED`. History rows are kept.

### The Timeline's read of it

`TimelineModel.Build` walks the days of the chosen range, carries each holder's last close forward across days with no cell, ranks the holders of the thing by latest balance, caps them at `settings.timelineMaxLines` and adds a Total. A holder's line starts at its genesis (never before: back-casting is out of scope), is drawn dashed until `meta.completeAt` (its gate container's first read), and the ledger's `ledgerSince` is drawn as a dashed rule when the range reaches it.

**Intraday.** Today and 7 d, when the range lies inside the retention and after `ledgerSince`, are rebuilt from event time rather than from daily points: `IntradaySeries` starts at the holder's balance *now* and undoes each history row of the thing, newest first, so it needs no stored snapshot. Two checks keep it honest. The balance it arrives at for the range start must not be negative, and it must equal the rollup's last close before that day when there is one. If either fails for any shown holder, the whole chart falls back to daily points (all holders or none, because mixing event-time and midnight points would make the Total add two clocks).

## Known limitation

The whole design assumes the peripheral event and its loot line fall within `CONTEXT_TTL` (~1.5s). **Slow manual click-looting** — opening a corpse or container and hovering before clicking an item well past the TTL — lets the stamp expire, so that item falls back to `OTHER` / `INFERRED`. This is an accepted trade-off: a longer TTL would risk bleeding a stale source onto an unrelated later loot. Auto-loot (the common case) fires the loot lines immediately, comfortably inside the window.

## Tracing attribution

Every stamp, consume, and trigger logs to the session debug console when `/lh debug` is on (`NS.State.debug`), each guarded at the call site so nothing is built when debug is off (standard debug-logging-§4). Turn it on and reproduce a loot to see the exact path — e.g. `[Open] LOOT_OPENED 3 slots -> KILL`, `[Attr] stamp KILL via LOOT_OPENED [npc=… enc=…]`, `[Attr] consume -> KILL (CERTAIN)`, or `[Drop] … reason=quality`. A `LOOT_OPENED` window logs exactly one coalesced `[Open]` summary line regardless of slot count, not one line per slot. The pure seams (`ResolveLootSource`, `DeconstructSource`, `ShouldRecord`, `BuildRecord`) are unit-tested headlessly without touching WoW event APIs.
