local addonName, NS = ...
NS.Collector = NS.Collector or {}
local Collector = NS.Collector

-- Owns the acquisition path: CHAT_MSG_LOOT self-filter, quality gate, record build + write
-- (see docs/TECHNICAL_DESIGN §5).

-- Hot-path upvalues, refreshed on Ka0s_LootHistory_SettingsChanged (standard §9.7).
local enabled, qualityThreshold, excludedSources = true, 2, {}

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
    itemID       = env.itemID,
    itemLink     = link,
    itemName     = env.itemName,
    quality      = env.quality,
    quantity     = qty,
    source       = ctx.source,
    sourceName   = ctx.sourceName,
    sourceDetail = ctx.sourceDetail,
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
  local source, sourceName, sourceDetail, confidence = NS.Attribution:Consume()

  if not self:ShouldRecord(quality, source,
    { qualityThreshold = qualityThreshold, excludedSources = excludedSources }) then
    return
  end

  local zone, subzone = NS.Compat.GetZone()
  local record = self:BuildRecord(link, qty,
    { source = source, sourceName = sourceName, sourceDetail = sourceDetail, confidence = confidence },
    { ts = time(), char = NS.Util.PlayerKey(), itemID = itemID, itemName = itemName,
      quality = quality, zone = zone, mapID = NS.Compat.GetPlayerMapID(), subzone = subzone })

  NS.Database:Add(record)

  if NS.db.global.debug then
    print(string.format("|cff33ff99%s|r loot: %s q%d src=%s conf=%s",
      addonName, tostring(itemName), quality or 0, source, confidence))
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
