# Compat layer

WoW's item, container, quest, mail, spell, and map APIs have churned across expansions — some moved into `C_*` namespaces, some kept a deprecated global, some vary in shape. `core/Compat.lua` provides a stable surface for those varying and deprecated calls — and **only** those: it does API-shape normalization, not attribution decisions.

The guiding principle is **Retail-only, presence-gated, no game-flavor branching.** Ka0s Loot History targets Retail, so `Compat.lua` never reads `WOW_PROJECT_ID` to pick a code path. Instead every varying/deprecated API is gated by a **direct presence check** of the `C_*` namespace or global it needs (`if C_Map and C_Map.GetBestMapForUnit then …`). When the API is absent the shim degrades to `nil`/`false` rather than erroring — capture keeps working, the affected field just goes unstamped. `core/Compat.lua:5` is the boundary comment that states the rule.

Load-first (`core/Compat.lua` heads the TOC) so every later module can reference `NS.Compat.*`.

**What is deliberately not here.** The map-id read, the zone read and the TOC-metadata read used to be
`Compat` shims. They behaved identically in every addon that carried them — the metadata one was written
eleven times across nine addons — which is what made them the library's business rather than this addon's.
They are `LibKa0s-Env-1.0`'s now and reach this addon through `core/EnvSetup.lua` as `NS.PlayerMapID()`,
`NS.Zone()`, `NS.Meta(field)` and `NS.Version()`. The boundary rule below is unchanged by that move: the
seam still keeps direct `C_*`/global calls out of the modules, it just resolves them through the library
first and falls back to the ladder the shim ran, minus one rung. The metadata read's ladder is
library → `C_AddOns.GetAddOnMetadata` → `nil`: the bare global `GetAddOnMetadata` rung is deleted, because no
client this addon's `## Interface` admits provides it and compat rules a dead rung is deleted, not shimmed.

`Compat.GetSpellName` went the same way at LibKa0s v1.55.0. Three addons carried the ladder and the
copies disagreed about what a nil top rung means, so it is `LibKa0s-Compat-1.0`'s member now. It is still
reached as `NS.Compat.GetSpellName`, a field `core/Compat.lua` assigns, so no call site moved. Nothing
else here moved: the major's secret guards and spec readers have no caller in this addon.

The same went for three item primitives. `QualityFromLink`, `QualityLabel` and `LoadItem` are
`LibKa0s-Item-1.0`'s now and reach this addon through [`core/ItemSetup.lua`](module-map.md) as
`NS.Item.*`, which also brings `NS.Item.ItemIDFromLink` — a primitive only BankLedger had written.
**`Compat.GetItemInfo` did NOT move, and that is the point.** This
addon guesses for an uncached item (the name from the link's brackets, the quality from its color)
because a browsable capture log would rather show an approximate row than lose the drop; BankLedger's
quality gate refuses one outright. Both are right for their addon, so the library carries the
primitives and holds no opinion about how they are composed.

## `Compat.*` surface

| Compat function | Wraps | Why |
|---|---|---|
| `Compat.FoldNBSP(s)` | — (pure) | Folds U+00A0, the no-break space (`\194\160`), to an ordinary space. Lua's `%s` is a byte-wise ASCII class and never matches it, so every trim, split or suffix strip over client text walks past one — and Blizzard's string tables carry them. Folded, not trimmed as a `[ \194\160]` class: `\160` also legitimately ends a multi-byte character (`à` is `\195\160`), so an end-anchored class trim can saw one in half. Consumed by `ScanBound` and by `modules/Attribution.lua`'s localized name-family seeds. |
| `Compat.GetActiveKeystoneLevel()` | `C_ChallengeMode.GetActiveKeystoneInfo` | Active M+ keystone level for keystone context; `nil` when no keystone is active or `C_ChallengeMode` is absent. |
| `Compat.InPartyInstance()` | `IsInInstance` | `true` only inside a party (5-player dungeon) instance; `false` otherwise or when `IsInInstance` is absent. The keystone context is cleared on a zone change where this is `false`. |
| `Compat.HookUseContainerItem(fn)` | `C_Container.UseContainerItem` → global `UseContainerItem` | `hooksecurefunc`s the "use a bag item" path so attribution can stamp CONTAINER — opening a lockbox pushes contents to bags with no `LOOT_OPENED`/source GUID. Calls `fn(bag, slot)` after each use. |
| `Compat.ContainerItemHasLoot(bag, slot)` | `C_Container.GetContainerItemInfo` | Reads `info.hasLoot` to confirm the used bag item is actually an openable container/lockbox; `false` when unknown, so a potion/gear use never mis-stamps as CONTAINER. |
| `Compat.HookGetQuestReward(fn)` | global `GetQuestReward` | `hooksecurefunc`s the quest-reward turn-in so the QUEST stamp lands before reward items push — the `QUEST_TURNED_IN` event can fire after the reward loot line and miss it. Calls `fn()` after each turn-in. |
| `Compat.CurrentQuestID()` | global `GetQuestID` | Quest id of the quest currently open in the quest frame, for `sourceDetail`; `nil` when none/absent. |
| `Compat.IsSpellTargeting()` | global `SpellIsTargeting` | Is the cursor holding a spell awaiting a target (Disenchant/Enchant about to apply to a bag item)? Distinguishes "opening a container" from "applying a spell to an item" — both route through `UseContainerItem`. `false` when absent. |
| `Compat.GetSpellName(spellID)` | **`LibKa0s-Compat-1.0`'s member** (v1.55.0): `C_Spell.GetSpellName` → `C_Spell.GetSpellInfo(id).name` → global `GetSpellInfo`, a nil or `""` answer falling through to the next rung | Localized spell name, so attribution can detect deconstruct casts by name family across the milling/prospecting/Mass variants. One value, `nil` when unavailable. With the library absent it is the reader stub, which always answers `nil`: attribution keeps its enumerated ids and loses only the name-family match. |
| `Compat.GetMailHeader(mailIndex)` | global `GetInboxHeaderInfo` | Sender + subject for an inbox mail row, feeding MAIL vs AH classification; `nil, nil` when absent. |
| `Compat.IsAuctionHouseMail(sender, subject)` | `AUCTION_HOUSE` + `AUCTION_*_MAIL_SUBJECT` globals | Locale-independent test for AH-origin mail: matches the AH sender name or an AH mail subject prefix (won / expired / canceled / invoice) built from the localized subject globals. Splits MAIL from AH source. |
| `Compat.UNIT_KINDS` + `Compat.DecodeGUID(guid)` | `strsplit` on the dash-split GUID | `UNIT_KINDS` is the single source of truth for GUID kinds carrying a creature/npc id (Creature/Vehicle/Pet/Vignette). `DecodeGUID` returns `kind` and, for unit kinds, the `npcID` from field 6 — how attribution tells KILL from CONTAINER/GameObject. |
| `Compat.GetItemInfo(link)` | `C_Item.GetItemInfoInstant` + `C_Item.GetItemInfo` | Resilient `itemID, itemName, quality, classID` for a link, falling back to the link's own display text and `NS.Item.QualityFromLink` when the item is not yet cached (so records never lose the name/quality). **The guess is this addon's policy and stays here**; only the color primitive under it lives in the library. `classID` is the locale-independent `Enum.ItemClass.*`. |
| `Compat.BindState(bindType)` | — (pure) | Maps an `Enum.ItemBind` value to a bind token: 1/4 → `"BOP"`, 2/3 → `"BOE"`, 7/8 → `"WARBAND"`, 9 → `"WARBAND_UE"`. Corroborating, **not** authoritative: Blizzard reports `2` for warbound caches (see [midnight-quirks.md](midnight-quirks.md)), so its silence proves nothing. |
| `Compat.ItemBindState(idOrLink, link?)` | `C_Item.GetItemInfo` (14th return) + `ScanBound` | Bind token for a stored row, both signals merged by `BestBound`. Returns **state, settled** — `settled` tracks tooltip readability, which is what a retrying caller must wait on. Builds `"item:<id>"` when the row has no link. |
| `Compat.BestBound(a, b)` | — (pure) | The more specific of two bind verdicts (`WARBAND_UE` > `WARBAND` > the rest). Neither signal is reliable alone, so whichever one sees warbound is believed — a warbound answer is never demoted to BoE/BoP. |
| `Compat.ScanBound(link)` | `C_TooltipInfo.GetHyperlink` | Scans the link's tooltip lines for warbound text. Returns **state, readable** — `"WARBAND_UE"` / `"WARBAND"` / `nil`, plus whether the tooltip had any text to judge (a nil state alone can't distinguish "not warbound" from "tooltip not built yet"). Matches both wordings of each state as **whole lines** (an item *name* can contain "Warbound"), until-equipped first. Retail-only. |
| `Compat.GetItemExtras(link)` | `C_Item.GetItemInfoInstant` + `.GetItemInfo` + `.GetDetailedItemLevelInfo` + `ScanBound` | Capture-time extras in one call: effective `ilvl` (equippable weapons/armor only — reagents/consumables carry a meaningless itemLevel), `bound` (warband/account wins over BOP/BOE from `bindType`), per-unit vendor sell price (stored as the record's `vendorPrice`), and `itemType`/`itemSubType`. |
| `Compat.CurrencyLinkID(link)` | `link:match("|?H?currency:(%d+)")` | Parses the `currencyID` from a `|Hcurrency:ID:…|h` link; locale-independent, `nil` when absent. The structural signal that a `CHAT_MSG_CURRENCY` line is the player's own currency gain. |
| `Compat.GetCurrencyInfoFromLink(link)` | `C_CurrencyInfo.GetCurrencyInfoFromLink` | `(id, name, iconFileID)` for a currency link — id + name come from the link itself (works headless / pre-cache); `C_CurrencyInfo` enriches name + icon when present. |
| `Compat.CurrencyCategory(currencyID)` | `C_CurrencyInfo.GetCurrencyListSize`/`…ListInfo`/`…ListLink` | The currency window's expansion/type header (e.g. "The War Within") for the record's `itemSubType`, from a cached walk of the list. The cache rebuilds once on a missed id, and is dropped when `GetCurrencyListSize` changes or `CurrencyListChanged` is called; `nil` when absent or unlisted (a currency under a collapsed header is not walked, see [midnight-quirks.md](midnight-quirks.md#currency-category--rebuild-on-a-miss-blind-to-collapsed-headers)). |
| `Compat.CurrencyListChanged()` | — (drops the cache above) | Drops the category cache, the listed-id set and the missed-id memo, so the next lookup walks the list again. The Reconciler calls it on a nil-id `CURRENCY_DISPLAY_UPDATE` (the client's bulk refresh), when a currency may have joined the list. |
| `Compat.ListedCurrencyID(id, name)` | the same cached walk + `C_CurrencyInfo.GetCurrencyInfo` (names) + `NS.Holdings` (stored currency baselines) | The id a chat currency line records under, or `nil` to drop it (Phase 7). `id` stands when it is listed or held in the current character's or the Warband's baseline (which covers a collapsed header); otherwise exactly one listed or held currency of the same name stands for it (a hidden tracking currency such as 3513 maps to its listed twin 3418), and anything else is `nil`. **This is a decision, not shape normalization**, and the one exception to this page's rule: whether an id is "the same currency" depends on the list walk the category cache already owns, so the Phase 7 plan put the test beside that cache rather than walking the list a second time from the Collector. It reads `NS.Holdings` only through `Holdings:Get`. With `settings.trackLedger` off the Collector keeps the link's id on a `nil` answer, because no current baseline exists to cover a collapsed header. |
| `Compat.CurrencyQuality(currencyID)` | `C_CurrencyInfo.GetCurrencyInfo` | The currency's `Enum.ItemQuality` tier — colors the Name cell + fills the Quality column for currency rows, and drives the v3→v4 backfill migration; `nil` when uncached/absent. |
| `Compat.CurrencyName(currencyID)` | `C_CurrencyInfo.GetCurrencyInfo` | Localized currency name for the holdings search's currency rows; `nil` when uncached/absent. |
| `Compat.GetItemTypeInfo(idOrLink)` | `C_Item.GetItemInfo` (6th/7th returns) | Localized `itemType, itemSubType` for the holdings search's type filters; `nil, nil` when uncached or the API is absent. |
| `Compat.GetItemSellPrice(idOrLink)` | `C_Item.GetItemInfo` (11th return) | Per-unit vendor sell price (copper) the Holdings tab values a stack from beside the picked auction price; `nil` when uncached or the API is absent. Kept apart from `GetItemExtras`, which also scans the tooltip. |
| `Compat.GearItemLevel(idOrLink)` | `C_Item.GetItemInfoInstant` + `C_Item.GetDetailedItemLevelInfo` (fallback `GetItemInfo` 4th return) | Item level of a weapon or armor piece with an equip slot, for the Holdings tab's iLvl column; `nil` for anything else or when the API is absent. No tooltip scan, unlike `GetItemExtras`. |
| `Compat.ShowItemTooltip(owner, link, anchor)` / `ShowCurrencyTooltip(owner, id, anchor)` / `ShowTextTooltip(owner, title, body, anchor)` / `ShowAmountTooltip(owner, title, rgb, label, value, hint, anchor)` / `ShowLinesTooltip(owner, title, rows, anchor)` / `HideTooltip()` | `GameTooltip` (`SetOwner`, `SetHyperlink`, `SetCurrencyByID`, `AddLine`, `AddDoubleLine`, `Show`, `Hide`) | The Holdings tab's row and header tooltips, and History's gold-row tooltip (`ShowAmountTooltip`) and row leave (`HideTooltip`), and the Timeline strip's Gained / Lost / Net (`ShowLinesTooltip`, a gold title over one double line per row, both sides in the row's color). Each answers `false` and draws nothing when `GameTooltip` or the method it needs is missing. |
| `Compat.CurrencyBound(currencyID)` | `C_CurrencyInfo.GetCurrencyInfo` (`isAccountTransferable`) | `"WARBAND"` for a Warband-transferable currency, else `"BOP"` — drives the currency Bound-column glyph and the v4→v5 backfill migration; `nil` when the id can't be resolved. |
| `Compat.GetContainerNumSlots(bagID)` | `C_Container.GetContainerNumSlots` | Slot count of a bag or bank tab; `0` when the API is absent, so a holdings walk over a missing container is a no-op. |
| `Compat.GetContainerSlot(bagID, slot)` | `C_Container.GetContainerItemInfo` | `{itemID, link, count}` for an occupied slot, `nil` when empty or absent; flattens `hyperlink`/`stackCount` so callers never see the client's info-table shape. |
| `Compat.GetMoney()` | `GetMoney` − `GetCursorMoney` − `GetPlayerTradeMoney` | Purse copper as the player owns it: money held on the cursor or staged in a trade window is still theirs. Missing parts read `0`. |
| `Compat.GetWarbandMoney()` | `C_Bank.FetchDepositedMoney(Enum.BankType.Account)` | Warband bank gold in copper; `nil` when the API or enum is absent (distinct from a real `0`). |
| `Compat.InCombatLockdown()` | `InCombatLockdown` | `true` only when the client reports lockdown. The Reconciler's combat gate: the lockdown flag, not `UnitAffectingCombat`, because it decides whether a scan may run rather than whether something is displayed. `false` when the API is absent. |
| `Compat.PlayerClassFile()` | `UnitClass("player")` (2nd return) | The locale-independent class token (`"MAGE"`) the Holdings tab colors a holder's name with; `nil` when the API is absent. |
| `Compat.GetInventoryItem(slot)` | `GetInventoryItemID` + `GetInventoryItemLink` | `itemID, link` for an equipped slot of the player; `nil` when empty or absent. |
| `Compat.BagInventorySlot(bagID)` | `C_Container.ContainerIDToInventoryID` | The inventory slot a bag container is equipped in, `nil` for the backpack or when absent. |
| `Compat.ListCurrencies()` | `C_CurrencyInfo.GetCurrencyListSize`/`…ListInfo`/`…ListLink`/`ExpandCurrencyList` | Every currency the character has as `{id, quantity, accountWide}`. Collapsed headers are expanded for the walk and collapsed again after (last-to-first), because the list hides their children; `{}` when the API is absent. |
| `Compat.InteractionType(name)` | `Enum.PlayerInteractionType[name]` | Numeric interaction type for a name (`"Banker"`, `"AccountBanker"`, …) so handlers never hardcode the number; `nil` when unknown. |
| `Compat.HookSecure(name, fn)` | `hooksecurefunc` (global) | Presence-gated post-hook by global name; `false` and nothing installed when the target is absent. No un-hook exists, so the body gates itself on `NS.IsStoodDown`. |
| `Compat.HookSecureMember(tbl, member, fn)` | `hooksecurefunc` (table member) | Same gate for a namespace function such as `C_AuctionHouse.PostItem`. |
| `Compat.IsConsumable(itemID)` | `C_Item.GetItemInfoInstant` | `true` when the item's class id is Consumable (0), locale-independent; `false` when absent. |
| `Compat.CurrencyIsAccountWide(id)` | `C_CurrencyInfo.GetCurrencyInfo` | `isAccountWide` as a strict boolean; `false` when absent. |
| `Compat.CurrencySourceName(gain, destroy, change)` | `Enum.CurrencySource` / `Enum.CurrencyDestroyReason` | Reverse-looks-up the CURRENCY_DISPLAY_UPDATE source or destroy reason to its Enum member NAME by the sign of `change`; `nil` when unknown. |
| `Compat.ScanInbox()` | `GetInboxNumItems` / `GetInboxItem` / `GetInboxItemLink` | Attachment counts and links by itemID across the loaded inbox; empty tables when absent. |
| `Compat.ReadSendMail()` | `GetSendMailItem` / `GetSendMailMoney` | Staged send-mail attachments by itemID plus the staged money in copper. |
| `Compat.ScanOwnedAuctions()` | `C_AuctionHouse.GetNumOwnedAuctions` / `GetOwnedAuctionInfo` | Counts and links of the player's ACTIVE auctions only, by itemID. |
| `Compat.ItemLocationID(loc)` | `C_Item.GetItemID` | itemID for an ItemLocation; `nil` when absent. |
| `Compat.AuctionMailKind(subject)` | `AUCTION_SOLD/EXPIRED/REMOVED/WON_MAIL_SUBJECT` | `"sold"`, `"expired"`, `"cancelled"` or `"won"` plus the item name, parsed from the localized subject globals; `nil` otherwise. |
| `Compat.TradeTargetKey()` | `UnitName("NPC")`, `GetNormalizedRealmName` | The open trade's other party as a `Name-Realm` holder key; `nil` when none. |
| `Compat.LatestCurrencyTransfer()` | `C_CurrencyInfo.FetchCurrencyTransferTransactions` | Newest warband currency transfer as `{currencyID, quantity, toKey}`; `nil` when none or absent. |

## Boundary rule

Modules call into `Compat.*` for every varying/deprecated API. **A direct `C_*`, `_G` API call, or `WOW_PROJECT_ID` branch outside `Compat.lua` is a smell** — the compat firewall exists so flavor/version drift is fixed in exactly one file (see [common-tasks.md](common-tasks.md)).

Attribution stamping consumes most of this surface — the hooks (`HookUseContainerItem`, `HookGetQuestReward`) and probes (`ContainerItemHasLoot`, `IsSpellTargeting`, `InPartyInstance`, `CurrentQuestID`, `GetMailHeader`, `IsAuctionHouseMail`, `DecodeGUID`) feed the source-resolution engine described in [data-flow.md](data-flow.md). The collector consumes `GetItemInfo`/`GetItemExtras` to build each record, and takes the where-am-I stamp from `NS.Zone` / `NS.PlayerMapID` in [`core/EnvSetup.lua`](module-map.md) rather than from here. See the [module map](module-map.md) for how the pieces load and connect.

## Third-party pricing addons stay out of Compat

The AH-price integration's shims (the `Auctionator`, `TSM_API` and `OEMarketInfo` presence checks and the call wrapping around them) live in `modules/AuctionPrice.lua`, deliberately outside this file. That was raised and ratified on 2026-07-18. `core/Compat.lua` is the *Blizzard*-API firewall. A cascade over **other addons'** APIs is a different kind of boundary: optional, config-driven, multi-provider, and irrelevant to every module that does not price items, so folding it in here would blur this file's one job. `AuctionPrice` is presence-gated the way Compat's own shims are, and wraps each provider call in `pcall` so a broken or absent pricing addon degrades to `nil` and the cascade moves on to the next.

The Ka0s Standard defines no boundary for non-Blizzard addon interop, so this is a gap in the standard rather than a deviation from it, and it has no row in the register. The standard's own definition was left unchanged.
