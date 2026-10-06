local _, NS = ...
NS.Collector = NS.Collector or {}
local Collector = NS.Collector
local Perf = NS.Perf -- load-time upvalue (performance-§2); core/PerfSetup.lua loads above

-- Owns the acquisition path: CHAT_MSG_LOOT self-filter, quality gate, record build + write, the
-- CHAT_MSG_CURRENCY and CHAT_MSG_MONEY lines, and the claim each written row posts to the
-- Reconciler so the holdings diff never counts the same gain twice (see docs/data-flow.md).

-- Hot-path upvalues, refreshed on Ka0s_LootHistory_SettingsChanged (events-frames-taint-§7).
--
-- `enabled` IS NOT ONE OF THEM ANY MORE, and its removal is the point of the change rather than a
-- tidy-up. It used to be read at the top of OnChatMsgLoot and OnChatMsgCurrency, which is the DRAW
-- GATE anti-patterns #85 names: the handler stopped reacting and the addon never stopped watching,
-- so the client walked the registration list, built the argument frame and entered Lua on every
-- loot line in the raid for an addon the player had switched off. The switch now tears the chat
-- registrations out (Collector:Disable, below), so there is nothing left to gate -- and a flag kept
-- beside a real unregister is a second answer to "is this addon running" that can disagree with it.
local qualityThreshold, excludedSources, excludeQuestItems = 1, {}, false
local recordCurrency = true
local recordGold, trackLedger = true, true
local currencyBlacklist = {}
local blacklist, whitelist = {}, {}

-- The gate config handed to ShouldRecord, reused across every loot line rather than built per
-- CHAT_MSG_LOOT (events-frames-taint-§7: no per-event allocation on a hot path). RefreshUpvalues
-- rewrites its settings fields; OnChatMsgLoot sets only itemID per call. Safe to share because
-- ShouldRecord reads cfg and never keeps it.
local gateCfg = {
  qualityThreshold = qualityThreshold, excludedSources = excludedSources,
  excludeQuestItems = excludeQuestItems, blacklist = blacklist, whitelist = whitelist,
}

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
    bound        = env.bound,       -- nil | "BOE" | "BOP" | "WARBAND" | "WARBAND_UE"
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
  local p = NS.db and NS.db.profile
  local s = p and p.settings
  if not s then return end
  qualityThreshold = s.qualityThreshold
  excludedSources = s.excludedSources or {}
  excludeQuestItems = s.excludeQuestItems
  recordCurrency = s.recordCurrency
  recordGold = s.recordGold ~= false
  trackLedger = s.trackLedger ~= false
  currencyBlacklist = p.currencyBlacklist or {}
  blacklist = p.blacklist or {}
  whitelist = p.whitelist or {}
  gateCfg.qualityThreshold, gateCfg.excludedSources = qualityThreshold, excludedSources
  gateCfg.excludeQuestItems = excludeQuestItems
  gateCfg.blacklist, gateCfg.whitelist = blacklist, whitelist
end

-- Some loot lines are self-identifying: the line itself names the source (a bonus roll, a crafted
-- "You create", a token/vendor refund), so we attribute it directly with CERTAIN confidence rather
-- than reading the peripheral context — which by now may be stale or belong to an unrelated kill.
-- Everything else consumes the stamped context (which a roll-won stamp may have set to ROLL).
local function resolveLootSource(directSource)
  if directSource then
    return NS.Constants.SourceType[directSource], nil, NS.Constants.Confidence.CERTAIN
  end
  return NS.Attribution:Consume()
end

-- The [Drop] line for a loot line the gate refused. Builds nothing while logging is off.
local function traceLootDrop(itemName, quality, classID, source, reason)
  if NS.State.debug and NS.Debug then
    NS.Debug("Drop", "%s q%s class=%s src=%s reason=%s",
      tostring(itemName), tostring(quality or 0), tostring(classID or "-"), tostring(source), tostring(reason))
  end
end

-- The [Loot] line for a written record, then [AHPrice]: every gathered price, sorted, and the pick.
-- Builds nothing while logging is off.
local function traceLootRecorded(itemName, quality, itemLevel, source, confidence, auctionPrice)
  if not (NS.State.debug and NS.Debug) then return end
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

-- The holdings diff will see this same thing land. The claim tells it the gain is already written,
-- so only an unclaimed remainder becomes a diff row (timeline-ledger spec §5.3). Posted ONLY for a
-- row that was written: a gated-out line posts nothing, and the diff then records the item as a
-- plain row (spec D2). PostClaim is itself a no-op while ledger capture is off.
local function claim(kind, id, qty, record)
  if (id or kind == "GOLD") and NS.Reconciler and NS.Reconciler.PostClaim then
    NS.Reconciler:PostClaim(NS.Ledger.ThingKey(kind, id), qty, record)
  end
end

local function lootLine(self, msg)
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
  local source, sourceDetail, confidence = resolveLootSource(directSource)

  gateCfg.itemID = itemID
  local ok, reason = self:ShouldRecord(quality, source, classID, gateCfg)
  if not ok then
    traceLootDrop(itemName, quality, classID, source, reason)
    return
  end

  local itemLevel, bound, sellPrice, itemType, itemSubType = NS.Compat.GetItemExtras(link)
  local auctionPrice = NS.AuctionPrice:GatherAll(link, itemID)
  local zone, subzone = NS.Zone()
  local classFile = select(2, UnitClass("player"))
  local record = self:BuildRecord(link, qty,
    { source = source, sourceDetail = sourceDetail, confidence = confidence },
    { ts = time(), char = NS.Util.PlayerKey(), classFile = classFile,
      itemID = itemID, itemName = itemName, quality = quality, itemLevel = itemLevel, bound = bound,
      vendorPrice = sellPrice, auctionPrice = auctionPrice,
      itemType = itemType, itemSubType = itemSubType,
      zone = zone, mapID = NS.PlayerMapID(), subzone = subzone })

  NS.Database:Add(record)
  claim("ITEM", itemID, qty, record)

  traceLootRecorded(itemName, quality, itemLevel, source, confidence, auctionPrice)
end

-- Shape A brackets (performance-§2): one exit, so the dormant cost is one upvalue read, one field
-- read and one test. Each body is a file-local function so the bracket wraps every early return.
function Collector:OnChatMsgLoot(_, msg)
  local t0 = Perf.on and debugprofilestop()
  lootLine(self, msg)
  if t0 then Perf.Note("lootLine", debugprofilestop() - t0) end
end
Collector._lootLine = lootLine   -- the unbracketed body: tests/perf.lua's zero-overhead baseline

-- The [Drop] line for a currency line refused before it names a currency. `reason` is a constant,
-- so the call builds nothing while logging is off.
local function traceCurrencyLineDrop(reason)
  if NS.State.debug and NS.Debug then NS.Debug("Drop", "currency line reason=%s", reason) end
end

-- CHAT_MSG_CURRENCY: currency loot. Reuses the same attribution context as items (currency fires in
-- the same loot window), but takes a slimmer gate — the recordCurrency master toggle, the per-source
-- mute list, and the currency-specific blacklist; the quality threshold, quest filter, and itemID
-- blacklist don't apply to currency. A currency-vendor refund arrives here (not on CHAT_MSG_LOOT) as
-- a self-identifying "You are refunded" line — attributed to REFUND directly, bypassing the context
-- (which by then holds the stale VENDOR stamp from the purchase).
local function currencyLine(self, msg)
  -- A line the self-parse rejects (another player's, or not a currency gain) returns silently: no
  -- decision of ours. Past it, each guard names itself in a [Drop] line (debug-logging-§8).
  local link, qty, directSource = NS.Util.ParseSelfCurrency(msg)
  if not link then return end
  if not recordCurrency then
    traceCurrencyLineDrop("recordCurrency-off")
    return
  end

  local currencyID, name = NS.Compat.GetCurrencyInfoFromLink(link)
  if not currencyID then
    traceCurrencyLineDrop("unresolved-link")
    return
  end

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

  local zone, subzone = NS.Zone()
  local record = {
    ts = time(), char = NS.Util.PlayerKey(), classFile = select(2, UnitClass("player")),
    currencyID = currencyID, itemName = name,
    itemType = NS.Constants.CURRENCY_TYPE, itemSubType = NS.Compat.CurrencyCategory(currencyID),
    quality = NS.Compat.CurrencyQuality(currencyID),
    bound = NS.Compat.CurrencyBound(currencyID),   -- WARBAND (Warband-transferable) | BOP | nil
    quantity = qty,
    source = source, sourceDetail = sourceDetail, confidence = confidence,
    zone = zone, mapID = NS.PlayerMapID(), subzone = subzone,
  }
  NS.Database:Add(record)
  claim("CURRENCY", currencyID, qty, record)

  if NS.State.debug and NS.Debug then
    NS.Debug("Currency", "%s x%s id=%s src=%s conf=%s",
      tostring(name), tostring(qty), tostring(currencyID), source, confidence)
  end
end

function Collector:OnChatMsgCurrency(_, msg)
  local t0 = Perf.on and debugprofilestop()
  currencyLine(self, msg)
  if t0 then Perf.Note("currencyLine", debugprofilestop() - t0) end
end

-- CHAT_MSG_MONEY: the player's own looted money and party share (timeline-ledger spec §5.4). Writes
-- the rich gold row -- the loot context still says which kill or chest it came from -- and claims it,
-- exactly as a loot line does for an item. Gold rows are a ledger feature: nothing is written while
-- `trackLedger` (legacy gains-only) or `recordGold` is off.
local function moneyLine(self, msg)
  local copper = NS.Util.ParseSelfMoney(msg)
  if not copper then return end
  if not (trackLedger and recordGold) then
    if NS.State.debug and NS.Debug then NS.Debug("Drop", "money %s reason=gold-off", tostring(copper)) end
    return
  end
  local source, sourceDetail, confidence = NS.Attribution:Consume()
  local zone, subzone = NS.Zone()
  local me = NS.Util.PlayerKey()
  local record = {
    ts = time(), char = me, classFile = NS.Compat.PlayerClassFile(),
    holder = me, dir = "IN", kind = "GOLD",
    itemName = "Gold", itemType = NS.Constants.GOLD_TYPE, quantity = copper,
    source = source, sourceDetail = sourceDetail, confidence = confidence,
    zone = zone, mapID = NS.PlayerMapID(), subzone = subzone,
  }
  NS.Database:Add(record)
  claim("GOLD", nil, copper, record)
  if NS.State.debug and NS.Debug then NS.Debug("Money", "%sc src=%s", tostring(copper), tostring(source)) end
end

function Collector:OnChatMsgMoney(_, msg)
  local t0 = Perf.on and debugprofilestop()
  moneyLine(self, msg)
  if t0 then Perf.Note("moneyLine", debugprofilestop() - t0) end
end

function Collector:Enable()
  local bus = NS.addon
  if not bus or self._enabled then return end
  self._enabled = true
  self:RefreshUpvalues()
  -- Per event through Core's helper (events-frames-taint-§1): a refused name costs only itself.
  NS.SafeRegisterEvent(bus, "CHAT_MSG_LOOT", function(_, msg) self:OnChatMsgLoot(_, msg) end,
    NS.RejectedEvents)
  NS.SafeRegisterEvent(bus, "CHAT_MSG_CURRENCY",
    function(_, msg) self:OnChatMsgCurrency(_, msg) end, NS.RejectedEvents)
  NS.SafeRegisterEvent(bus, "CHAT_MSG_MONEY", function(_, msg) self:OnChatMsgMoney(_, msg) end,
    NS.RejectedEvents)
  -- Message subscriptions use a private bus target (never the shared bus-as-self) so they don't
  -- clobber the Browser's SettingsChanged handler on the same bus. See NS.NewBusTarget.
  -- No `or bus` tail: NS.NewBusTarget returns nil ONLY when AceEvent-3.0 is unresolvable, and
  -- core/LootHistory.lua:4's NewAddon(NS, addonName, "AceEvent-3.0", …) errors first in exactly
  -- that case (AceAddon-3.0.lua's EmbedLibrary raises on a missing non-silent library), so
  -- NS.addon, NS.bus and NS.NewBusTarget itself never come into existence and Enable never runs.
  -- The fallback could only ever have reinstated the shared-target clobber the comment forbids.
  self.__ev = NS.NewBusTarget()
  self.__ev:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, _reason)
    self:RefreshUpvalues()
  end)
end

--- The stand-down half of Enable (slash-commands-§7). Every registration this module made is
--- actually UNREGISTERED, never gated: the three chat events off the shared AceAddon target by name
--- (UnregisterAllEvents there would take the other modules' registrations with it), and the private
--- bus target wholesale.
---
--- `_enabled` is cleared last, so Enable rebuilds on the way back up.
function Collector:Disable()
  if not self._enabled then return end
  local bus = NS.addon
  if bus and bus.UnregisterEvent then
    bus:UnregisterEvent("CHAT_MSG_LOOT")
    bus:UnregisterEvent("CHAT_MSG_CURRENCY")
    bus:UnregisterEvent("CHAT_MSG_MONEY")
  end
  if self.__ev then
    self.__ev:UnregisterAllMessages()
    self.__ev:UnregisterAllEvents()
    self.__ev = nil
  end
  self._enabled = nil
end
