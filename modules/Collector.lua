local addonName, NS = ...
NS.Collector = NS.Collector or {}
local Collector = NS.Collector

-- Owns the acquisition path: CHAT_MSG_LOOT self-filter, quality gate, record build + write
-- (see docs/TECHNICAL_DESIGN §5).

-- Hot-path upvalues, refreshed on Ka0s_LootHistory_SettingsChanged (standard §9.7).
local enabled, qualityThreshold, excludedSources = true, 1, {}

-- ── Pure seams (unit-tested) ──────────────────────────────────────────────────

-- Quality gate + per-source exclude. cfg = { qualityThreshold, excludedSources }.
function Collector:ShouldRecord(quality, source, cfg)
  if (quality or 0) < cfg.qualityThreshold then return false end
  if cfg.excludedSources and cfg.excludedSources[source] then return false end
  return true
end

-- Assemble a loot record. ctx = attribution result; env = item/location/time fields.
function Collector:BuildRecord(link, qty, ctx, env)
  return {
    ts           = env.ts,
    char         = env.char,
    classFile    = env.classFile,   -- locale-independent class token, e.g. "MAGE"
    itemID       = env.itemID,
    itemLink     = link,
    itemName     = env.itemName,
    quality      = env.quality,
    itemLevel    = env.itemLevel,   -- effective ilvl for equippable items; nil otherwise
    bound        = env.bound,       -- nil | "BOE" | "BOP" | "ACCOUNT" | "WARBAND"
    sellPrice    = env.sellPrice,   -- vendor sell price (copper, per unit)
    itemType     = env.itemType,
    itemSubType  = env.itemSubType,
    quantity     = qty,
    source       = ctx.source,
    sourceDetail = ctx.sourceDetail,   -- npcID / encounter / keystone / questID (not displayed)
    zone         = env.zone,
    mapID        = env.mapID,
    subzone      = env.subzone,
    confidence   = ctx.confidence,
  }
end

-- ── Runtime path ──────────────────────────────────────────────────────────────

function Collector:RefreshUpvalues()
  local s = NS.db and NS.db.global and NS.db.global.settings
  if not s then return end
  enabled = s.enabled
  qualityThreshold = s.qualityThreshold
  excludedSources = s.excludedSources or {}
end

function Collector:OnChatMsgLoot(_, msg)
  if not enabled then return end
  local link, qty = NS.Util.ParseSelfLoot(msg)
  if not link then return end

  local itemID, itemName, quality = NS.Compat.GetItemInfo(link)
  local source, sourceDetail, confidence = NS.Attribution:Consume()

  if not self:ShouldRecord(quality, source,
    { qualityThreshold = qualityThreshold, excludedSources = excludedSources }) then
    return
  end

  local itemLevel, bound, sellPrice, itemType, itemSubType = NS.Compat.GetItemExtras(link)
  local zone, subzone = NS.Compat.GetZone()
  local classFile = select(2, UnitClass("player"))
  local record = self:BuildRecord(link, qty,
    { source = source, sourceDetail = sourceDetail, confidence = confidence },
    { ts = time(), char = NS.Util.PlayerKey(), classFile = classFile,
      itemID = itemID, itemName = itemName, quality = quality, itemLevel = itemLevel, bound = bound,
      sellPrice = sellPrice, itemType = itemType, itemSubType = itemSubType,
      zone = zone, mapID = NS.Compat.GetPlayerMapID(), subzone = subzone })

  NS.Database:Add(record)

  if NS.State.debug and NS.Debug then
    NS.Debug("Loot", "%s q%d ilvl=%s src=%s conf=%s",
      tostring(itemName), quality or 0, tostring(itemLevel or "-"), source, confidence)
  end
end

function Collector:Enable()
  local bus = NS.addon
  if not bus or self._enabled then return end
  self._enabled = true
  self:RefreshUpvalues()
  bus:RegisterEvent("CHAT_MSG_LOOT", function(_, msg) self:OnChatMsgLoot(_, msg) end)
  bus:RegisterMessage("Ka0s_LootHistory_SettingsChanged", function() self:RefreshUpvalues() end)
end
