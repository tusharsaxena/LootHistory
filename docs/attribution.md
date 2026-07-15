# Attribution & capture engine

Ka0s Loot History's core subsystem. Two modules cooperate: `modules/Attribution.lua` (the source-resolution engine) stamps a short-lived context from peripheral events, and `modules/Collector.lua` (the acquisition path) consumes it on the authoritative "item received" signal to build one record per loot event. Attribution loads before Collector (TOC order) so the stamper is live before the first loot line.

The design question the engine answers: WoW gives you a reliable "you looted item X" signal, but not *why* — a green from a mob kill, a bag you opened, a mail attachment, and an AH win all arrive as the same `CHAT_MSG_LOOT` line. Attribution reconstructs the "why" by watching the peripheral events that *precede* the loot and leaving a breadcrumb the collector reads back.

## The authoritative signal: `CHAT_MSG_LOOT`

`CHAT_MSG_LOOT` is the one authoritative "item received (self)" signal, and the only event that writes a record. `Collector:OnChatMsgLoot` (`modules/Collector.lua:60`) runs `NS.Util.ParseSelfLoot(msg)` (`core/Util.lua:112`), which matches the line against the localized self-loot global strings (`LOOT_ITEM_SELF_MULTIPLE`, `LOOT_ITEM_PUSHED_SELF_MULTIPLE`, `LOOT_ITEM_SELF`, `LOOT_ITEM_PUSHED_SELF`) compiled once into anchored Lua patterns. Lines that aren't the player's own loot (party members, "created", etc.) don't match and return `nil` — that is the **self-filter**. Quantity-bearing patterns are tried first because their greedy `(.+)` link capture would otherwise swallow the trailing `xN` of a multiple-loot line.

Everything else — LOOT_OPENED, trade, mail, casts, merchant, container use, quest turn-in — is *peripheral*. None of it writes a record; it only stamps context.

## The single-slot context

Peripheral events call `Attribution:Stamp(source, detail, confidence, trigger)` (`modules/Attribution.lua:71`), which overwrites one slot on `State.lootContext` (`core/State.lua:7`):

```lua
State.lootContext = {
  source = source,        -- a Constants.SourceType key
  detail = detail,        -- npcID / encounter / keystone / questID, or nil
  confidence = confidence or CERTAIN,
  expires = GetTime() + Constants.CONTEXT_TTL,   -- ~1.5s
}
```

`Collector:OnChatMsgLoot` reads it back via `Attribution:Consume` (`modules/Attribution.lua:85`):

- **Fresh** (`expires >= GetTime()`) → returns the stamped `source, detail, confidence`.
- **Stale or never stamped** → returns the fallback `OTHER, nil, INFERRED`.

Two deliberate properties of this single-slot design (see [Do not change without reason](../CLAUDE.md)):

1. **`CONTEXT_TTL` is ~1.5s** (`core/Constants.lua:51`). Long enough to bridge the gap between the peripheral event and the loot line it explains, short enough that an unrelated later loot doesn't inherit a stale source.
2. **Consume does not clear the slot.** One loot window emits many `CHAT_MSG_LOOT` lines that all share a source — a kill dropping four items, a bag with six stacks. Clearing on first consume would attribute only the first line and drop the rest to `OTHER`. The context intentionally survives the whole burst; the TTL, not consumption, ends it.

Confidence is `CERTAIN` for every live stamper and `INFERRED` only on the fallback path — so `confidence == INFERRED` is exactly "no fresh context existed when this item landed." See [data-model.md](data-model.md) for how `source` / `sourceDetail` / `confidence` are stored.

## Source resolution from the loot window

`LOOT_OPENED` is the richest stamper because the loot window exposes each slot's **source GUID**, and the GUID's *kind* determines the source. `Attribution:OnLootOpened` (`modules/Attribution.lua:131`) reads the first slot's GUID via `GetLootSourceInfo` and feeds it to the pure resolver `Attribution:ResolveLootSource` (`modules/Attribution.lua:103`), which decodes it through `NS.Compat.DecodeGUID` (`core/Compat.lua:124`):

| GUID kind | Instance state | Source | Detail |
|---|---|---|---|
| `Creature` / `Vehicle` / `Pet` / `Vignette` (`Compat.UNIT_KINDS`) | encounter active | `KILL` | `{ npcID, encounterID, difficulty }` |
| `Creature` / … | no encounter | `KILL` | `{ npcID }` |
| `GameObject` | keystone active | `MPLUS` | `{ keystoneLevel }` |
| `GameObject` | no keystone | `CONTAINER` | — |
| `Item` | — | `CONTAINER` | — |
| anything else | — | `OTHER` | — |

The unit-kind set lives in `Compat.UNIT_KINDS` (`core/Compat.lua:120`) as the single source of truth, so KILL detection can't drift from GUID decoding. All slots in one window share a source closely enough that stamping from the first slot is sufficient; the TTL then spans the resulting `CHAT_MSG_LOOT` burst.

### Instance context enrichment

The encounter and keystone detail is layered on by separate rolling-context stampers that write `State.encounter` / `State.keystone` (`core/State.lua:10`) rather than the loot context:

- `ENCOUNTER_START` → `OnEncounterStart` sets `{ id, name, difficulty }` (`modules/Attribution.lua:155`); `ENCOUNTER_END` clears it. Any KILL loot in between carries the encounter id + difficulty.
- `CHALLENGE_MODE_START` → `OnChallengeModeStart` records `{ level }` from `NS.Compat.GetActiveKeystoneLevel` (`core/Compat.lua:19`). `CHALLENGE_MODE_COMPLETED` deliberately **keeps** the keystone context (refreshing the level) rather than clearing it, because the reward chest is looted shortly *after* completion and its GameObject GUID must still resolve to `MPLUS` (`modules/Attribution.lua:175`).

## Peripheral stampers

Sources that arrive without a loot window (or whose window would mis-resolve) each stamp just before their resulting self-loot line. Registered in `Attribution:Enable` (`modules/Attribution.lua:261`) via events and `hooksecurefunc`:

- **VENDOR** — `hooksecurefunc("BuyMerchantItem")` → `StampVendor` (`modules/Attribution.lua:188`).
- **TRADE** — `TRADE_ACCEPT_UPDATE` → `OnTradeAcceptUpdate` (`modules/Attribution.lua:224`); stamps only when **both** `playerAccepted` and `targetAccepted` are `1` (trade actually completed).
- **MAIL / AH** — `hooksecurefunc` on both `TakeInboxItem` and `AutoLootMailItem` → `StampMail` (`modules/Attribution.lua:233`). The mail's sender/subject decides which: `NS.Compat.IsAuctionHouseMail` (`core/Compat.lua:95`) matches the `AUCTION_HOUSE` sender or an AH subject prefix (won / expired / cancelled / invoice, built from the localized `*_MAIL_SUBJECT` globals) → `AH`; everything else → `MAIL`. This is the only stamper for `AH` — there is no live auction-house-frame stamper.
- **QUEST** — the client-side `hooksecurefunc("GetQuestReward")` → `StampQuestReward` (`modules/Attribution.lua:253`) is the primary path: it fires *before* the server pushes the reward items, so the stamp is fresh when the reward loot line lands. The `QUEST_TURNED_IN` event → `OnQuestTurnedIn` (`modules/Attribution.lua:244`) is a backstop; alone it can fire *after* the reward line and miss it. Detail carries the quest id when the quest frame still exposes it (`NS.Compat.CurrentQuestID`, `core/Compat.lua:58`).
- **CONTAINER (bag item)** — opening a container/lockbox from bags pushes contents to inventory with no `LOOT_OPENED` or GUID, so `NS.Compat.HookUseContainerItem` (`core/Compat.lua:29`, `C_Container.UseContainerItem` on retail) → `OnContainerItemUse` (`modules/Attribution.lua:196`) stamps `CONTAINER` — but **only** when the item actually has loot (`Compat.ContainerItemHasLoot`) **and** no spell is awaiting a target (`Compat.IsSpellTargeting`). Clicking a bag item as a Disenchant/Enchant target also routes through `UseContainerItem`, and that must not be read as opening a container.

### Deconstruct: DISENCHANT / MILLING / PROSPECTING

Disenchant, Milling, and Prospecting each stamp their **own** first-class source rather than a generic "Craft," so the Source column reads the ability. Their materials arrive through a loot window whose `Item` GUID would otherwise resolve to `CONTAINER`, so this stamper both attributes the source *and* protects that attribution.

`UNIT_SPELLCAST_SUCCEEDED` (filtered to `unit == "player"` via a dedicated `RegisterUnitEvent` frame, to avoid the raid-wide cast firehose) → `OnSpellSucceeded` (`modules/Attribution.lua:211`) maps the completed cast to a source through `Attribution:DeconstructSource` (`modules/Attribution.lua:46`):

1. **Spell-name family match first** (enUS): `Disenchant`, `Milling` / `^Mass Mill`, `Prospecting` / `^Mass Prospect`. Modern retail has split milling/prospecting into generic + per-expansion + per-herb/ore "Mass" variants — far too many ids to enumerate, but they share a name family. Name comes from `NS.Compat.GetSpellName` (`core/Compat.lua:72`).
2. **Per-expansion id fallback** — `DECONSTRUCT_ID` (`modules/Attribution.lua:30`), a locale-independent table of the primary per-expansion spell ids, used when the name is unavailable (uncached). Non-English clients rely on this fallback; full localization is a tracked backlog item.

The cast succeeds right as the materials are produced, so the stamp is fresh within TTL. `Attribution:OnLootOpened` then guards against clobbering it: if the live context is already one of `DECONSTRUCT_SOURCE` (`modules/Attribution.lua:41`), the subsequent material-window `LOOT_OPENED` returns early and keeps the more specific deconstruct stamp (`modules/Attribution.lua:135`).

## The collector's gates

Once `Collector:OnChatMsgLoot` has a link and a resolved `(source, detail, confidence)`, it decides whether to record. The pure seam `Collector:ShouldRecord` (`modules/Collector.lua:17`) applies three gates in order and, on a drop, returns a reason for the debug log:

1. **Quality** — `quality < qualityThreshold` → drop (`"quality"`). Threshold options in `Constants.QUALITY_OPTIONS`.
2. **Excluded source** — the item's source is muted in `excludedSources` → drop (`"source"`).
3. **Quest item** — when `excludeQuestItems` is on and the item's class is `Constants.ITEMCLASS_QUEST` (`core/Constants.lua:44`, `Enum.ItemClass.Questitem` = 12) → drop (`"quest"`). The gate keys on the **locale-independent item class id**, never the localized `itemType` string, so it works on every client.

The `CHAT_MSG_LOOT` self-filter (`ParseSelfLoot` returning `nil`) is the implicit gate ahead of all three.

Records that pass are assembled by `Collector:BuildRecord` (`modules/Collector.lua:25`) — one record per loot event — and handed to `NS.Database:Add`. Item extras (ilvl, bound, sell price, type/subtype) come from `NS.Compat.GetItemExtras`; the `classFile` colouring token from `UnitClass("player")`.

### Hot-path upvalues

The three gate settings plus `enabled` are cached as file-local upvalues (`modules/Collector.lua:9`), not re-read from the DB on every loot line (standard §9.7). `Collector:RefreshUpvalues` (`modules/Collector.lua:51`) reloads them, and the collector subscribes to `Ka0s_LootHistory_SettingsChanged` to refresh on any settings write (`modules/Collector.lua:106`). That subscription registers on a **private** `NS.NewBusTarget()`, never the shared bus-as-self, so it doesn't clobber the Browser's handler for the same message — see [message-bus.md](message-bus.md).

## Wired vs enum'd sources

`Constants.SourceType` (`core/Constants.lua:8`) is the whole enum and the stable **export contract** — keys are never renamed. But not every enum member has a live stamper:

- **Live today:** `KILL`, `CONTAINER`, `MPLUS`, `QUEST`, `VENDOR`, `MAIL`, `TRADE`, `AH`, `DISENCHANT`, `MILLING`, `PROSPECTING`, `OTHER`.
- **Enum'd but not stamped:** `CRAFT` (reserved for broad recipe crafting) and `ROLL` (specified but unwired).

`Constants.SOURCE_IMPLEMENTED` (`core/Constants.lua:33`) is the gate: it lists only sources with a live capture path, and drives `SOURCE_OPTIONS` (`core/Constants.lua:77`) so the settings panel's per-source **mute list** never shows a dead checkbox for an unreachable bucket. The enum stays whole for the export seam; only the option lists scope down. See [compat-layer.md](compat-layer.md) for the shims and [module-map.md](module-map.md) for where these modules sit.

## Known limitation

The whole design assumes the peripheral event and its loot line fall within `CONTEXT_TTL` (~1.5s). **Slow manual click-looting** — opening a corpse or container and hovering before clicking an item well past the TTL — lets the stamp expire, so that item falls back to `OTHER` / `INFERRED`. This is an accepted trade-off: a longer TTL would risk bleeding a stale source onto an unrelated later loot. Auto-loot (the common case) fires the loot lines immediately, comfortably inside the window.

## Tracing attribution

Every stamp, consume, and trigger logs to the session debug console when `/lh debug` is on (`NS.State.debug`), each guarded at the call site so nothing is built when debug is off (standard §8). Turn it on and reproduce a loot to see the exact path — e.g. `[Open] LOOT_OPENED 3 slots -> KILL`, `[Attr] stamp KILL via LOOT_OPENED [npc=… enc=…]`, `[Attr] consume -> KILL (CERTAIN)`, or `[Drop] … reason=quality`. A `LOOT_OPENED` window logs exactly one coalesced `[Open]` summary line regardless of slot count, not one line per slot. The pure seams (`ResolveLootSource`, `DeconstructSource`, `ShouldRecord`, `BuildRecord`) are unit-tested headlessly without touching WoW event APIs.
