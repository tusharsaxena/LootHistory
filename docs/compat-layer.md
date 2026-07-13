# Compat layer

WoW's item, container, quest, mail, spell, and map APIs have churned across expansions — some moved into `C_*` namespaces, some kept a deprecated global, some vary in shape. `core/Compat.lua` provides a stable surface for those varying and deprecated calls — and **only** those: it does API-shape normalisation, not attribution decisions.

The guiding principle is **Retail-only, presence-gated, no game-flavor branching.** Ka0s Loot History targets Retail, so `Compat.lua` never reads `WOW_PROJECT_ID` to pick a code path. Instead every varying/deprecated API is gated by a **direct presence check** of the `C_*` namespace or global it needs (`if C_Map and C_Map.GetBestMapForUnit then …`). When the API is absent the shim degrades to `nil`/`false` rather than erroring — capture keeps working, the affected field just goes unstamped. `core/Compat.lua:5` is the boundary comment that states the rule.

Load-first (`core/Compat.lua` heads the TOC) so every later module can reference `NS.Compat.*`.

## `Compat.*` surface

| Compat function | Wraps | Why |
|---|---|---|
| `Compat.GetPlayerMapID()` | `C_Map.GetBestMapForUnit("player")` | Best-effort current map id for the record's `mapID`; `nil` when `C_Map` is absent. |
| `Compat.GetActiveKeystoneLevel()` | `C_ChallengeMode.GetActiveKeystoneInfo` | Active M+ keystone level for keystone context; `nil` when no keystone is active or `C_ChallengeMode` is absent. |
| `Compat.HookUseContainerItem(fn)` | `C_Container.UseContainerItem` → global `UseContainerItem` | `hooksecurefunc`s the "use a bag item" path so attribution can stamp CONTAINER — opening a lockbox pushes contents to bags with no `LOOT_OPENED`/source GUID. Calls `fn(bag, slot)` after each use. |
| `Compat.ContainerItemHasLoot(bag, slot)` | `C_Container.GetContainerItemInfo` | Reads `info.hasLoot` to confirm the used bag item is actually an openable container/lockbox; `false` when unknown, so a potion/gear use never mis-stamps as CONTAINER. |
| `Compat.HookGetQuestReward(fn)` | global `GetQuestReward` | `hooksecurefunc`s the quest-reward turn-in so the QUEST stamp lands before reward items push — the `QUEST_TURNED_IN` event can fire after the reward loot line and miss it. Calls `fn()` after each turn-in. |
| `Compat.CurrentQuestID()` | global `GetQuestID` | Quest id of the quest currently open in the quest frame, for `sourceDetail`; `nil` when none/absent. |
| `Compat.IsSpellTargeting()` | global `SpellIsTargeting` | Is the cursor holding a spell awaiting a target (Disenchant/Enchant about to apply to a bag item)? Distinguishes "opening a container" from "applying a spell to an item" — both route through `UseContainerItem`. `false` when absent. |
| `Compat.GetSpellName(spellID)` | `C_Spell.GetSpellName` → global `GetSpellInfo` | Localized spell name, so attribution can detect deconstruct casts by name family across the milling/prospecting/Mass variants. `nil` when unavailable. |
| `Compat.GetMailHeader(mailIndex)` | global `GetInboxHeaderInfo` | Sender + subject for an inbox mail row, feeding MAIL vs AH classification; `nil, nil` when absent. |
| `Compat.IsAuctionHouseMail(sender, subject)` | `AUCTION_HOUSE` + `AUCTION_*_MAIL_SUBJECT` globals | Locale-independent test for AH-origin mail: matches the AH sender name or an AH mail subject prefix (won / expired / cancelled / invoice) built from the localized subject globals. Splits MAIL from AH source. |
| `Compat.GetZone()` | globals `GetZoneText` + `GetSubZoneText` | Current zone + subzone labels for the record; subzone may be `""`. |
| `Compat.UNIT_KINDS` + `Compat.DecodeGUID(guid)` | `strsplit` on the dash-split GUID | `UNIT_KINDS` is the single source of truth for GUID kinds carrying a creature/npc id (Creature/Vehicle/Pet/Vignette). `DecodeGUID` returns `kind` and, for unit kinds, the `npcID` from field 6 — how attribution tells KILL from CONTAINER/GameObject. |
| `Compat.QualityFromLink(link)` / `Compat.QualityLabel(q)` | `ITEM_QUALITY_COLORS` / `ITEM_QUALITY<q>_DESC` globals | `QualityFromLink` parses the quality id from a link's `|cffRRGGBB` color prefix (a reverse hex→quality map) for the uncached fallback. `QualityLabel` gives the localized Poor/Common/… name, falling back to a static English map headlessly and for unknown ids. |
| `Compat.GetItemInfo(link)` | `C_Item.GetItemInfoInstant` + `C_Item.GetItemInfo` | Resilient `itemID, itemName, quality, classID` for a link, falling back to the link's own display text and `QualityFromLink` when the item is not yet cached (so records never lose the name/quality). `classID` is the locale-independent `Enum.ItemClass.*`. |
| `Compat.ScanBound(link)` | `C_TooltipInfo.GetHyperlink` | Scans the link's tooltip lines for warband/account-bound text, returning `"WARBAND"`, `"ACCOUNT"`, or `nil`. Retail-only; `nil` when `C_TooltipInfo` is absent. |
| `Compat.GetItemExtras(link)` | `C_Item.GetItemInfoInstant` + `.GetItemInfo` + `.GetDetailedItemLevelInfo` + `ScanBound` | Capture-time extras in one call: effective `ilvl` (equippable weapons/armor only — reagents/consumables carry a meaningless itemLevel), `bound` (warband/account wins over BOP/BOE from `bindType`), per-unit `sellPrice`, and `itemType`/`itemSubType`. |

## Boundary rule

Modules call into `Compat.*` for every varying/deprecated API. **A direct `C_*`, `_G` API call, or `WOW_PROJECT_ID` branch outside `Compat.lua` is a smell** — the compat firewall (CLAUDE.md convention 4) exists so flavor/version drift is fixed in exactly one file.

Attribution stamping consumes most of this surface — the hooks (`HookUseContainerItem`, `HookGetQuestReward`) and probes (`ContainerItemHasLoot`, `IsSpellTargeting`, `CurrentQuestID`, `GetMailHeader`, `IsAuctionHouseMail`, `DecodeGUID`) feed the source-resolution engine described in [attribution.md](attribution.md). The collector consumes `GetItemInfo`/`GetItemExtras`/`GetZone` to build each record. See the [module map](module-map.md) for how the pieces load and connect.
