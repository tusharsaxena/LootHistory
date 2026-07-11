local addonName, NS = ...
NS.Compat = NS.Compat or {}
local Compat = NS.Compat

-- Flavor flags. The only place WOW_PROJECT_ID is read; feature code branches on these.
Compat.IsRetail  = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
Compat.IsClassic = (WOW_PROJECT_ID == WOW_PROJECT_CLASSIC)

-- Best-effort current map id for the player (nil if unavailable).
function Compat.GetPlayerMapID()
  if C_Map and C_Map.GetBestMapForUnit then
    return C_Map.GetBestMapForUnit("player")
  end
  return nil
end

-- Current zone + subzone labels (subzone may be "").
function Compat.GetZone()
  local zone = (GetZoneText and GetZoneText()) or ""
  local subzone = (GetSubZoneText and GetSubZoneText()) or ""
  return zone, subzone
end

-- GUID kinds that carry a creature/npc id in field 6 of the dash-split GUID.
local UNIT_KINDS = { Creature = true, Vehicle = true, Pet = true, Vignette = true }

-- Decode a WoW GUID → kind ("Creature"/"GameObject"/"Item"/...) and, for unit kinds,
-- the npcID (field 6). Non-unit kinds return nil for the id.
function Compat.DecodeGUID(guid)
  if not guid then return nil end
  local kind = strsplit("-", guid)
  local npcID
  if UNIT_KINDS[kind] then
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

-- Resilient item info for an item link. Returns itemID, itemName, quality, falling back to
-- the link's own display data when the item is not yet cached (GetItemInfo returns nil).
function Compat.GetItemInfo(link)
  local itemID
  if C_Item and C_Item.GetItemInfoInstant then
    itemID = C_Item.GetItemInfoInstant(link)
  end
  local name, _, quality
  if C_Item and C_Item.GetItemInfo then
    name, _, quality = C_Item.GetItemInfo(link)
  end
  name = name or (link and link:match("%[(.-)%]"))
  quality = quality or Compat.QualityFromLink(link)
  return itemID, name, quality
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

-- Capture-time extras for a looted item: effective item level (equippable gear only) and
-- bound state ∈ { nil(unbound), "BOE", "BOP", "ACCOUNT", "WARBAND" }. A warband/account
-- tooltip wins over the plain bindType.
local ITEMCLASS_WEAPON, ITEMCLASS_ARMOR = 2, 4  -- Enum.ItemClass.Weapon / .Armor
function Compat.GetItemExtras(link)
  if not link then return nil, nil end
  local ilvl, bound

  -- Item level only for real gear. Reagents/consumables also carry an itemLevel, but it is
  -- meaningless in a loot log, so gate on item class (weapon/armor), not just equipLoc.
  if C_Item and C_Item.GetItemInfoInstant then
    local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(link)
    if (classID == ITEMCLASS_WEAPON or classID == ITEMCLASS_ARMOR)
      and equipLoc and equipLoc ~= "" then
      ilvl = (C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link))
        or (C_Item.GetItemInfo and select(4, C_Item.GetItemInfo(link)))
    end
  end

  bound = Compat.ScanBound(link) -- WARBAND / ACCOUNT / nil
  if not bound and C_Item and C_Item.GetItemInfo then
    local bindType = select(14, C_Item.GetItemInfo(link))
    if bindType == 1 or bindType == 4 then
      bound = "BOP"                 -- bind on pickup / quest
    elseif bindType == 2 or bindType == 3 then
      bound = "BOE"                 -- bind on equip / on use
    end
  end
  return ilvl, bound
end
