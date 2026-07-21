local addonName, NS = ...
NS.Compat = NS.Compat or {}
local Compat = NS.Compat

-- Retail-only addon: no game-flavor branching. Every varying/deprecated API is gated by a
-- direct C_*/global presence check below, so a shim degrades to nil/false when its API is
-- absent — never by reading a game-flavor project id.

-- Best-effort current map id for the player (nil if unavailable).
function Compat.GetPlayerMapID()
  if C_Map and C_Map.GetBestMapForUnit then
    return C_Map.GetBestMapForUnit("player")
  end
  return nil
end

-- Active M+ keystone level (nil if no keystone active or the API is absent). Guarded by
-- C_ChallengeMode presence — degrades to nil when the challenge-mode API is unavailable.
function Compat.GetActiveKeystoneLevel()
  if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
    return (C_ChallengeMode.GetActiveKeystoneInfo())
  end
  return nil
end

-- Hook the "use a bag item" path. Opening a container item pushes its contents straight to bags
-- with no LOOT_OPENED / source GUID, so attribution needs a stamp from here. Calls fn(bag, slot)
-- after each use. Retail routes through C_Container; older clients expose a global.
function Compat.HookUseContainerItem(fn)
  if C_Container and C_Container.UseContainerItem then
    hooksecurefunc(C_Container, "UseContainerItem", fn)
  elseif type(UseContainerItem) == "function" then
    hooksecurefunc("UseContainerItem", fn)
  end
end

-- Does the bag item at (bag, slot) have openable loot (a container / lockbox)? False when unknown
-- or the API is absent — so a non-container item (potion, gear) never mis-stamps as CONTAINER.
function Compat.ContainerItemHasLoot(bag, slot)
  local get = C_Container and C_Container.GetContainerItemInfo
  if get then
    local info = get(bag, slot)
    if info and info.hasLoot then return true end
  end
  return false
end

-- Hook the quest-reward turn-in. GetQuestReward is the client call that triggers the server
-- turn-in, so a stamp here lands before the reward items push (the QUEST_TURNED_IN *event* can
-- fire after the reward loot line and miss it). Calls fn() after each turn-in.
function Compat.HookGetQuestReward(fn)
  if type(GetQuestReward) == "function" then
    hooksecurefunc("GetQuestReward", fn)
  end
end

-- The quest ID of the quest currently open in the quest frame (nil / 0 when none).
function Compat.CurrentQuestID()
  if type(GetQuestID) == "function" then return GetQuestID() end
  return nil
end

-- Is the cursor holding a spell awaiting a target (e.g. Disenchant/Enchant about to be applied
-- to a bag item)? Used to tell "opening a container" apart from "applying a spell to an item",
-- both of which route through UseContainerItem. False when the API is absent.
function Compat.IsSpellTargeting()
  return type(SpellIsTargeting) == "function" and SpellIsTargeting() or false
end

-- Localized spell name for a spell id (nil if unavailable). Lets attribution detect deconstruct
-- casts by name family across the many milling/prospecting/Mass variants. Retail moved to C_Spell.
function Compat.GetSpellName(spellID)
  if not spellID then return nil end
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
  if type(GetSpellInfo) == "function" then return (GetSpellInfo(spellID)) end
  return nil
end

-- Sender + subject for an inbox mail row (nil when the API is absent).
function Compat.GetMailHeader(mailIndex)
  if type(GetInboxHeaderInfo) == "function" and mailIndex then
    local _, _, sender, subject = GetInboxHeaderInfo(mailIndex)
    return sender, subject
  end
  return nil, nil
end

-- Is this inbox mail from the Auction House? Locale-independent: matches the AH sender name
-- (AUCTION_HOUSE global) or an AH mail subject prefix (won / expired / cancelled / invoice,
-- built from the localized *_MAIL_SUBJECT globals). Rebuilt per call — mail-take is infrequent.
local AH_SUBJECT_GLOBALS = {
  "AUCTION_WON_MAIL_SUBJECT", "AUCTION_EXPIRED_MAIL_SUBJECT",
  "AUCTION_REMOVED_MAIL_SUBJECT", "AUCTION_INVOICE_MAIL_SUBJECT",
}
function Compat.IsAuctionHouseMail(sender, subject)
  if sender and sender ~= "" and type(AUCTION_HOUSE) == "string" and sender == AUCTION_HOUSE then
    return true
  end
  if subject and subject ~= "" then
    for _, name in ipairs(AH_SUBJECT_GLOBALS) do
      local g = _G[name]
      if type(g) == "string" then
        local prefix = g:match("^(.-)%%s") or g   -- "Auction won: %s" → "Auction won: "
        if prefix ~= "" and subject:sub(1, #prefix) == prefix then return true end
      end
    end
  end
  return false
end

-- Current zone + subzone labels (subzone may be "").
function Compat.GetZone()
  local zone = (GetZoneText and GetZoneText()) or ""
  local subzone = (GetSubZoneText and GetSubZoneText()) or ""
  return zone, subzone
end

-- GUID kinds that carry a creature/npc id in field 6 of the dash-split GUID. Exposed as the
-- single source of truth; the attribution engine reads it to distinguish KILL from CONTAINER.
Compat.UNIT_KINDS = { Creature = true, Vehicle = true, Pet = true, Vignette = true }

-- Decode a WoW GUID → kind ("Creature"/"GameObject"/"Item"/...) and, for unit kinds,
-- the npcID (field 6). Non-unit kinds return nil for the id.
function Compat.DecodeGUID(guid)
  if not guid then return nil end
  local kind = strsplit("-", guid)
  local npcID
  if Compat.UNIT_KINDS[kind] then
    npcID = tonumber((select(6, strsplit("-", guid))))
  end
  return kind, npcID
end

-- Reverse map of item-quality color hex (rrggbb) → quality id, for the uncached fallback.
local qualityByHex
local function buildQualityByHex()
  qualityByHex = {}
  if type(ITEM_QUALITY_COLORS) == "table" then
    for q = 0, 8 do
      local c = ITEM_QUALITY_COLORS[q]
      if c and c.hex then qualityByHex[c.hex:sub(-6)] = q end
    end
  end
end

-- Quality id parsed from an item link's color prefix (|cffRRGGBB...). nil if unknown.
function Compat.QualityFromLink(link)
  if not link then return nil end
  local hex = link:match("|c%x%x(%x%x%x%x%x%x)")
  if not hex then return nil end
  if not qualityByHex then buildQualityByHex() end
  return qualityByHex[hex]
end

-- Localized quality label (Poor/Common/…). Falls back to a static English map headlessly
-- and for unknown ids.
local QUALITY_LABEL_EN = {
  [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare",
  [4] = "Epic", [5] = "Legendary", [6] = "Artifact", [7] = "Heirloom", [8] = "WoW Token",
}
function Compat.QualityLabel(q)
  q = q or 0
  return _G["ITEM_QUALITY" .. q .. "_DESC"] or QUALITY_LABEL_EN[q] or tostring(q)
end

-- Resilient item info for an item link. Returns itemID, itemName, quality, classID, falling
-- back to the link's own display data when the item is not yet cached (GetItemInfo returns nil).
-- classID is the locale-independent item class (Enum.ItemClass.*); nil when uncached/unknown.
function Compat.GetItemInfo(link)
  local itemID, classID
  if C_Item and C_Item.GetItemInfoInstant then
    local _
    itemID, _, _, _, _, classID = C_Item.GetItemInfoInstant(link)
  end
  local name, _, quality
  if C_Item and C_Item.GetItemInfo then
    name, _, quality = C_Item.GetItemInfo(link)
  end
  name = name or (link and link:match("%[(.-)%]"))
  quality = quality or Compat.QualityFromLink(link)
  return itemID, name, quality, classID
end

-- Resolve an item id to a display name + quality for the filter-management UI (issue #14).
-- Returns (name, quality); name is nil when the item is not yet cached (the caller shows an
-- "Item <id>" placeholder). C_Item.GetItemInfo accepts a bare id as well as a link.
function Compat.ItemNameQuality(id)
  if not id then return nil end
  if C_Item and C_Item.GetItemInfo then
    local name, _, quality = C_Item.GetItemInfo(id)
    return name, quality
  end
  return nil
end

-- Request the server to cache an item id so a later ItemNameQuality resolves; `cb` fires once
-- the item is loaded (no-op when the API is absent). Used by the filter panel to fill in names
-- that weren't cached on first paint.
function Compat.LoadItem(id, cb)
  if not (id and C_Item and C_Item.RequestLoadItemDataByID) then return end
  C_Item.RequestLoadItemDataByID(id)
  if cb and C_Timer and C_Timer.After then C_Timer.After(0.4, cb) end
end

-- Scan an item link's tooltip for warband/account-bound text.
-- Returns "WARBAND", "ACCOUNT", or nil. Retail-only (C_TooltipInfo); nil elsewhere.
local WARBAND_STRINGS = {
  ITEM_ACCOUNTBOUND_UNTIL_EQUIP, -- "Warbound until equipped"
  ITEM_BNETACCOUNTBOUND,         -- "Warbound"
}
local ACCOUNT_STRINGS = {
  ITEM_ACCOUNTBOUND,             -- "Account Bound"
  ITEM_BIND_TO_BNETACCOUNT,      -- "Blizzard Account Bound" (legacy)
}
local function lineMatchesAny(text, list)
  for _, s in ipairs(list) do
    if s and s ~= "" and text:find(s, 1, true) then return true end
  end
  return false
end

function Compat.ScanBound(link)
  if not (link and C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return nil end
  local data = C_TooltipInfo.GetHyperlink(link)
  if not (data and data.lines) then return nil end
  for _, line in ipairs(data.lines) do
    local text = line.leftText
    if text then
      if lineMatchesAny(text, WARBAND_STRINGS) then return "WARBAND" end
      if lineMatchesAny(text, ACCOUNT_STRINGS) then return "ACCOUNT" end
    end
  end
  return nil
end

-- Capture-time extras for a looted item. Returns:
--   ilvl        effective item level (equippable weapons/armor only; nil otherwise)
--   bound       nil(unbound) | "BOE" | "BOP" | "ACCOUNT" | "WARBAND" (warband/account wins)
--   sellPrice   vendor sell price in copper (per unit)
--   itemType    top-level type ("Armor", "Weapon", "Tradegoods", …)
--   itemSubType finer subtype ("Cloth", "Sword", "Cooking", …)
local ITEMCLASS_WEAPON, ITEMCLASS_ARMOR = 2, 4  -- Enum.ItemClass.Weapon / .Armor
function Compat.GetItemExtras(link)
  if not link then return nil, nil, nil, nil, nil end
  local ilvl, bound, sellPrice, itemType, itemSubType

  local classID, equipLoc
  if C_Item and C_Item.GetItemInfoInstant then
    local _, _, _, eLoc, _, cID = C_Item.GetItemInfoInstant(link)
    classID, equipLoc = cID, eLoc
  end

  local bindType
  if C_Item and C_Item.GetItemInfo then
    local _, itemLevel
    _, _, _, itemLevel, _, itemType, itemSubType, _, _, _, sellPrice, _, _, bindType =
      C_Item.GetItemInfo(link)
    -- ilvl only for real gear; reagents/consumables carry a meaningless itemLevel.
    if (classID == ITEMCLASS_WEAPON or classID == ITEMCLASS_ARMOR)
      and equipLoc and equipLoc ~= "" then
      ilvl = (C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)) or itemLevel
    end
  end

  bound = Compat.ScanBound(link) -- WARBAND / ACCOUNT / nil
  if not bound then
    if bindType == 1 or bindType == 4 then
      bound = "BOP"                 -- bind on pickup / quest
    elseif bindType == 2 or bindType == 3 then
      bound = "BOE"                 -- bind on equip / on use
    end
  end

  return ilvl, bound, sellPrice, itemType, itemSubType
end

-- Currency id parsed from a |Hcurrency:ID:...|h link. Locale-independent; nil when absent.
function Compat.CurrencyLinkID(link)
  if not link then return nil end
  return tonumber(link:match("|?H?currency:(%d+)"))
end

-- Resolve a currency link to id, name, iconFileID. Id + name come from the link itself (so this
-- works headlessly / before the client caches the currency); C_CurrencyInfo enriches name + icon
-- when present. icon is nil when the API is absent.
function Compat.GetCurrencyInfoFromLink(link)
  local id = Compat.CurrencyLinkID(link)
  local name = link and link:match("%[(.-)%]")
  local icon
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfoFromLink then
    local info = C_CurrencyInfo.GetCurrencyInfoFromLink(link)
    if info then
      name = info.name or name
      icon = info.iconFileID
    end
  end
  return id, name, icon
end

-- currencyID -> category (the currency window's expansion/type header, e.g. "The War Within").
-- Built once by walking the currency list and tracking the most recent header, then cached for the
-- session. nil when the API is absent or the id isn't in the list. Cheap after the first call.
local currencyCategoryCache
local function buildCurrencyCategoryCache()
  currencyCategoryCache = {}
  local api = C_CurrencyInfo
  if not (api and api.GetCurrencyListSize and api.GetCurrencyListInfo and api.GetCurrencyListLink) then
    return
  end
  local header
  for i = 1, (api.GetCurrencyListSize() or 0) do
    local info = api.GetCurrencyListInfo(i)
    if info then
      if info.isHeader then
        header = info.name
      else
        local id = Compat.CurrencyLinkID(api.GetCurrencyListLink(i))
        if id and header then currencyCategoryCache[id] = header end
      end
    end
  end
end
function Compat.CurrencyCategory(currencyID)
  if not currencyID then return nil end
  if not currencyCategoryCache then buildCurrencyCategoryCache() end
  return currencyCategoryCache[currencyID]
end

-- Display name for a currency id (nil when uncached / API absent). Used by the Filters panel to
-- label a stored currency-blacklist entry.
function Compat.CurrencyName(currencyID)
  if not currencyID then return nil end
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if info then return info.name end
  end
  return nil
end

-- Quality tier (Enum.ItemQuality) for a currency id, from C_CurrencyInfo; nil when uncached/absent.
-- Colours the currency name + fills the Quality column, and drives the v3->v4 backfill migration.
function Compat.CurrencyQuality(currencyID)
  if not currencyID then return nil end
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if info then return info.quality end
  end
  return nil
end

-- Addon TOC metadata field (e.g. "Version"), read from the packaged manifest so `/lh version`
-- can't drift from the TOC. Retail moved the getter to C_AddOns; falls back to the bare global,
-- then nil when neither is present.
function Compat.GetAddOnMetadata(name, field)
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    return C_AddOns.GetAddOnMetadata(name, field)
  end
  if type(GetAddOnMetadata) == "function" then
    return GetAddOnMetadata(name, field)
  end
  return nil
end
