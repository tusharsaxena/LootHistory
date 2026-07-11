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

-- Resilient item info for an item link. Returns itemID, itemName, quality, falling back to
-- the link's own display data when the item is not yet cached (GetItemInfo returns nil).
function Compat.GetItemInfo(link)
  local itemID
  if C_Item and C_Item.GetItemInfoInstant then
    itemID = C_Item.GetItemInfoInstant(link)
  end
  local name, quality
  if C_Item and C_Item.GetItemInfo then
    name, _, quality = C_Item.GetItemInfo(link)
  end
  name = name or (link and link:match("%[(.-)%]"))
  quality = quality or Compat.QualityFromLink(link)
  return itemID, name, quality
end
