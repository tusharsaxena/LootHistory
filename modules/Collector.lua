local addonName, NS = ...
NS.Collector = NS.Collector or {}
local Collector = NS.Collector

-- Owns the acquisition path: CHAT_MSG_LOOT self-filter, quality gate, record build + write
-- (see docs/attribution.md).

-- Hot-path upvalues, refreshed on Ka0s_LootHistory_SettingsChanged (events-frames-taint-§7).
local enabled, qualityThreshold, excludedSources, excludeQuestItems = true, 1, {}, false
local recordCurrency = true
local currencyBlacklist = {}
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
  recordCurrency = s.recordCurrency
  currencyBlacklist = g.currencyBlacklist or {}
  blacklist = g.blacklist or {}
  whitelist = g.whitelist or {}
end

function Collector:OnChatMsgLoot(_, msg)
  if not enabled then return end

  -- A roll-won line ("You won: <item>") is not a receipt — the item arrives a moment later on its own
  -- "You receive loot:" line. Stamp ROLL context so that imminent line attributes to the roll rather
  -- than inheriting a stale kill/container stamp, then wait for it (no record is written here).
  if NS.Util.ParseRollWon(msg) then
    NS.Attribution:StampRoll()
    return
  end

  local link, qty, directSource = NS.Util.ParseSelfLoot(msg)
  if not link then return end

  local itemID, itemName, quality, classID = NS.Compat.GetItemInfo(link)
  -- Some loot lines are self-identifying: the line itself names the source (a bonus roll, a crafted
  -- "You create", a token/vendor refund), so we attribute it directly with CERTAIN confidence rather
  -- than reading the peripheral context — which by now may be stale or belong to an unrelated kill.
  -- Everything else consumes the stamped context (which a roll-won stamp above may have set to ROLL).
  local source, sourceDetail, confidence
  if directSource then
    source, sourceDetail, confidence =
      NS.Constants.SourceType[directSource], nil, NS.Constants.Confidence.CERTAIN
  else
    source, sourceDetail, confidence = NS.Attribution:Consume()
  end

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

-- CHAT_MSG_CURRENCY: currency loot. Reuses the same attribution context as items (currency fires in
-- the same loot window), but takes a slimmer gate — the recordCurrency master toggle, the per-source
-- mute list, and the currency-specific blacklist; the quality threshold, quest filter, and itemID
-- blacklist don't apply to currency. A currency-vendor refund arrives here (not on CHAT_MSG_LOOT) as
-- a self-identifying "You are refunded" line — attributed to REFUND directly, bypassing the context
-- (which by then holds the stale VENDOR stamp from the purchase).
function Collector:OnChatMsgCurrency(_, msg)
  if not enabled or not recordCurrency then return end
  local link, qty, directSource = NS.Util.ParseSelfCurrency(msg)
  if not link then return end

  local currencyID, name = NS.Compat.GetCurrencyInfoFromLink(link)
  if not currencyID then return end

  if currencyBlacklist[currencyID] then
    if NS.State.debug and NS.Debug then
      NS.Debug("Drop", "currency %s id=%s reason=blacklist", tostring(name), tostring(currencyID))
    end
    return
  end

  local source, sourceDetail, confidence
  if directSource then
    source, sourceDetail, confidence =
      NS.Constants.SourceType[directSource], nil, NS.Constants.Confidence.CERTAIN
  else
    source, sourceDetail, confidence = NS.Attribution:Consume()
  end
  if excludedSources[source] then
    if NS.State.debug and NS.Debug then
      NS.Debug("Drop", "currency %s src=%s reason=source", tostring(name), tostring(source))
    end
    return
  end

  local zone, subzone = NS.Compat.GetZone()
  local record = {
    ts = time(), char = NS.Util.PlayerKey(), classFile = select(2, UnitClass("player")),
    currencyID = currencyID, itemName = name,
    itemType = NS.Constants.CURRENCY_TYPE, itemSubType = NS.Compat.CurrencyCategory(currencyID),
    quality = NS.Compat.CurrencyQuality(currencyID),
    bound = NS.Compat.CurrencyBound(currencyID),   -- WARBAND (Warband-transferable) | BOP | nil
    quantity = qty,
    source = source, sourceDetail = sourceDetail, confidence = confidence,
    zone = zone, mapID = NS.Compat.GetPlayerMapID(), subzone = subzone,
  }
  NS.Database:Add(record)

  if NS.State.debug and NS.Debug then
    NS.Debug("Currency", "%s x%s id=%s src=%s conf=%s",
      tostring(name), tostring(qty), tostring(currencyID), source, confidence)
  end
end

function Collector:Enable()
  local bus = NS.addon
  if not bus or self._enabled then return end
  self._enabled = true
  self:RefreshUpvalues()
  bus:RegisterEvent("CHAT_MSG_LOOT", function(_, msg) self:OnChatMsgLoot(_, msg) end)
  bus:RegisterEvent("CHAT_MSG_CURRENCY", function(_, msg) self:OnChatMsgCurrency(_, msg) end)
  -- Message subscriptions use a private bus target (never the shared bus-as-self) so they don't
  -- clobber the Browser's SettingsChanged handler on the same bus. See NS.NewBusTarget.
  self.__ev = NS.NewBusTarget() or bus
  self.__ev:RegisterMessage("Ka0s_LootHistory_SettingsChanged", function(_, _reason)
    self:RefreshUpvalues()
  end)
end
