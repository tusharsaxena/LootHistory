local addonName, NS = ...
NS.Collector = NS.Collector or {}
local Collector = NS.Collector

-- Owns the acquisition path: CHAT_MSG_LOOT self-filter, quality gate, record build + write
-- (see docs/attribution.md).

-- Hot-path upvalues, refreshed on Ka0s_LootHistory_SettingsChanged (events-frames-taint-§7).
local enabled, qualityThreshold, excludedSources, excludeQuestItems = true, 1, {}, false
local blacklist, whitelist = {}, {}

-- ── Pure seams (unit-tested) ──────────────────────────────────────────────────

-- The normal collection gate (no id lists). Returns nil when the item passes, else the drop
-- reason "quality"/"source"/"quest".
local function gateReason(quality, source, classID, cfg)
  if (quality or 0) < cfg.qualityThreshold then return "quality" end
  if cfg.excludedSources and cfg.excludedSources[source] then return "source" end
  if cfg.excludeQuestItems and classID == NS.Constants.ITEMCLASS_QUEST then return "quest" end
  return nil
end

-- Whitelist/blacklist override (issue #14) + the normal gate. cfg = { qualityThreshold,
-- excludedSources, excludeQuestItems, itemID, blacklist, whitelist }. A blacklisted id is an
-- absolute veto; otherwise the item records if it passes the gate, OR — failing the gate — if it
-- is whitelisted. Returns:
--   true              — passes normally
--   true, "whitelist" — failed the gate but the whitelist forced it in (recorded as a plain
--                       point-in-time row; later whitelist changes never revisit it)
--   false, reason     — dropped ("blacklist"/"quality"/"source"/"quest"), surfaced by the Drop log
function Collector:ShouldRecord(quality, source, classID, cfg)
  local id = cfg.itemID
  if id and cfg.blacklist and cfg.blacklist[id] then return false, "blacklist" end
  local reason = gateReason(quality, source, classID, cfg)
  if not reason then return true end                                    -- passes the normal gate
  if id and cfg.whitelist and cfg.whitelist[id] then return true, "whitelist" end  -- rescued
  return false, reason
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
    vendorPrice  = env.vendorPrice,  -- vendor sell price (copper, per unit)
    auctionPrice = env.auctionPrice, -- nested map provider->key->copper, or nil
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
  local g = NS.db and NS.db.global
  local s = g and g.settings
  if not s then return end
  enabled = s.enabled
  qualityThreshold = s.qualityThreshold
  excludedSources = s.excludedSources or {}
  excludeQuestItems = s.excludeQuestItems
  blacklist = g.blacklist or {}
  whitelist = g.whitelist or {}
end

function Collector:OnChatMsgLoot(_, msg)
  if not enabled then return end
  local link, qty = NS.Util.ParseSelfLoot(msg)
  if not link then return end

  local itemID, itemName, quality, classID = NS.Compat.GetItemInfo(link)
  local source, sourceDetail, confidence = NS.Attribution:Consume()

  local ok, reason = self:ShouldRecord(quality, source, classID,
    { qualityThreshold = qualityThreshold, excludedSources = excludedSources,
      excludeQuestItems = excludeQuestItems, itemID = itemID,
      blacklist = blacklist, whitelist = whitelist })
  if not ok then
    if NS.State.debug and NS.Debug then
      NS.Debug("Drop", "%s q%s class=%s src=%s reason=%s",
        tostring(itemName), tostring(quality or 0), tostring(classID or "-"), tostring(source), tostring(reason))
    end
    return
  end

  local itemLevel, bound, sellPrice, itemType, itemSubType = NS.Compat.GetItemExtras(link)
  local auctionPrice = NS.AuctionPrice:GatherAll(link, itemID)
  local zone, subzone = NS.Compat.GetZone()
  local classFile = select(2, UnitClass("player"))
  local record = self:BuildRecord(link, qty,
    { source = source, sourceDetail = sourceDetail, confidence = confidence },
    { ts = time(), char = NS.Util.PlayerKey(), classFile = classFile,
      itemID = itemID, itemName = itemName, quality = quality, itemLevel = itemLevel, bound = bound,
      vendorPrice = sellPrice, auctionPrice = auctionPrice,
      itemType = itemType, itemSubType = itemSubType,
      zone = zone, mapID = NS.Compat.GetPlayerMapID(), subzone = subzone })

  NS.Database:Add(record)

  if NS.State.debug and NS.Debug then
    NS.Debug("Loot", "%s q%s ilvl=%s src=%s conf=%s",
      tostring(itemName), quality or 0, tostring(itemLevel or "-"), source, confidence)

    local parts = {}
    if auctionPrice then
      for prov, sub in pairs(auctionPrice) do
        for k, v in pairs(sub) do parts[#parts + 1] = prov .. ":" .. k .. "=" .. tostring(v) end
      end
    end
    table.sort(parts)
    local pp, ptag = NS.AuctionPrice:Pick(auctionPrice)
    NS.Debug("AHPrice", "%s | gathered: %s | pick: %s(%s)", tostring(itemName),
      (#parts > 0 and table.concat(parts, " ") or "none"), tostring(pp or "-"), tostring(ptag or "-"))
  end
end

function Collector:Enable()
  local bus = NS.addon
  if not bus or self._enabled then return end
  self._enabled = true
  self:RefreshUpvalues()
  bus:RegisterEvent("CHAT_MSG_LOOT", function(_, msg) self:OnChatMsgLoot(_, msg) end)
  -- Message subscriptions use a private bus target (never the shared bus-as-self) so they don't
  -- clobber the Browser's SettingsChanged handler on the same bus. See NS.NewBusTarget.
  self.__ev = NS.NewBusTarget() or bus
  self.__ev:RegisterMessage("Ka0s_LootHistory_SettingsChanged", function(_, _reason)
    self:RefreshUpvalues()
  end)
end
