local addonName, NS = ...

-- AceDB init. Account-wide: all history + settings live in NS.db.global.
function NS:InitDB()
  NS.db = LibStub("AceDB-3.0"):New("LootHistoryDB", NS.defaults, true)
  NS:RunMigrations()   -- normalize the persisted schema before any history read
  NS.Database:RebuildWhitelistIndex()   -- session index for the whitelist-orphan hide (issue #14)
end

-- Schema-migration runner (Ka0s Standard §2.2/§5.1). Reads/writes db.global.schemaVersion and
-- ships even with an effectively empty body — the *seam* is the requirement: future schema
-- changes get a single, idempotent upgrade path invoked once at init, before any read of
-- db.global.history. Safe no-op when the DB isn't ready yet.
function NS:RunMigrations()
  local g = NS.db and NS.db.global
  if not g then return end
  g.schemaVersion = g.schemaVersion or 1
  -- v1 -> v2: point-in-time filtering (removed soft-add/soft-delete). Strip the retired
  -- per-record `viaWhitelist` flag; rows are never hidden/resurrected after capture. Non-
  -- destructive — no rows are deleted (see docs/superpowers/specs/2026-07-18-*).
  if g.schemaVersion < 2 then
    local n = 0
    for _, r in ipairs(g.history or {}) do
      if r.viaWhitelist ~= nil then r.viaWhitelist = nil; n = n + 1 end
    end
    g.schemaVersion = 2
    if NS.State.debug and NS.Debug then NS.Debug("Migrate", "%s", NS.MigrationSummary(1, 2, n)) end
  end
end

-- Pure migration summary for the [Migrate] line.
function NS.MigrationSummary(from, to, rows)
  return ("v%s -> v%s, %s rows touched"):format(tostring(from), tostring(to), tostring(rows))
end

-- Pure [Init] session summary for the SetEnabled seam (debug-logging-§5/§8): addon name + version,
-- schema/DB version, active profile, and record count — e.g.
-- "LootHistory v1.1.0, schema v1, profile 'Default', 1423 records".
-- Guarded so it can't error before the DB is ready (db.global / GetCurrentProfile may be absent).
-- All values are plain constants/counts, so a raw tostring is secret-safe here.
function NS.InitSummary()
  local g = NS.db and NS.db.global
  local schema = (g and g.schemaVersion) or 0
  local profile = (NS.db and NS.db.GetCurrentProfile and NS.db:GetCurrentProfile()) or "?"
  local records = (g and g.history and #g.history) or 0
  return ("%s v%s, schema v%s, profile '%s', %s records"):format(
    tostring(NS.name), tostring(NS.version), tostring(schema), tostring(profile), tostring(records))
end

NS.Database = NS.Database or {}
local Database = NS.Database

function Database:History()
  return NS.db.global.history
end

-- Session index of item ids that have at least one record kept ONLY because it was whitelisted
-- (r.viaWhitelist). Lets VisibleHistory keep its no-alloc fast path unless there is actually
-- something to hide. Derived from history (not persisted): rebuilt at init, maintained by Add.
-- A whitelist "orphan" — a viaWhitelist id no longer on the whitelist — is what must be hidden.
function Database:RebuildWhitelistIndex()
  local via = {}
  for _, r in ipairs(NS.db.global.history) do
    if r.viaWhitelist and r.itemID then via[r.itemID] = true end
  end
  NS.State.viaWhitelistIDs = via
  return via
end

-- True when some viaWhitelist id is no longer on the whitelist (so its rows must be hidden). Cheap:
-- iterates only the (small) set of ever-whitelist-rescued ids.
local function whitelistOrphanExists()
  local via = NS.State and NS.State.viaWhitelistIDs
  if not via then return false end
  local wl = NS.db.global.whitelist
  for id in pairs(via) do
    if not (wl and wl[id]) then return true end
  end
  return false
end

-- Live history with hidden items (issue #14) filtered out — nothing is ever deleted:
--   * blacklisted ids are hidden (removing the id restores their rows);
--   * a row recorded ONLY via the whitelist (r.viaWhitelist) is hidden once its id leaves the
--     whitelist (re-adding the id restores it) — symmetric with the blacklist, so "undo whitelist"
--     removes exactly the rows the whitelist added.
-- Returns the raw array unchanged (no allocation) when there is nothing to hide — the common case —
-- so the hot read path pays nothing until a blacklist or a whitelist orphan exists.
function Database:VisibleHistory()
  local g = NS.db.global
  local history = g.history
  local bl = g.blacklist
  local hasBl = bl and next(bl) ~= nil
  local hideWl = whitelistOrphanExists()
  if not hasBl and not hideWl then return history end
  local wl = g.whitelist or {}
  local out = {}
  for _, r in ipairs(history) do
    local hidden = (hasBl and bl[r.itemID]) or (r.viaWhitelist and not wl[r.itemID])
    if not hidden then out[#out + 1] = r end
  end
  return out
end

-- The dataset every read-path query (Query/Stats/Export, and thus the table + Insights tab)
-- resolves against. In Browser test mode this is the synthetic preview dataset published to
-- State by BrowserTable:ToggleTestMode, so the whole UI renders off the same fake data;
-- otherwise it is the live account-wide history with blacklisted items hidden (VisibleHistory).
-- Write paths (Add/prune) always target the real history directly and never see the override.
function Database:ActiveHistory()
  return (NS.State and NS.State.testRecords) or self:VisibleHistory()
end

function Database:Count()
  return #NS.db.global.history
end

-- Append a record to the account-wide history; fire RecordAdded; return its index.
function Database:Add(record)
  local history = NS.db.global.history
  history[#history + 1] = record
  local index = #history
  -- Keep the whitelist-orphan index current for a row kept only via the whitelist (issue #14).
  if record.viaWhitelist and record.itemID then
    local via = NS.State.viaWhitelistIDs or {}
    via[record.itemID] = true
    NS.State.viaWhitelistIDs = via
  end
  if NS.bus then
    NS.bus:SendMessage("Ka0s_LootHistory_RecordAdded", record, index)
  end
  return index
end

-- Filter an arbitrary record array by the filter spec. Fields, all optional (AND-combined).
-- source/char/itemType/mapID each accept a scalar (equality) OR a set table (membership, for
-- the Browser's multi-select filters); quality accepts a number (EXACT match) or a set table.
--   quality · source · char · itemType · mapID · from/to (ts, inclusive) · text (case-
--   insensitive substring on itemName). Empty/nil filter returns all.
-- Kept generic (not tied to the live history) so the Browser can filter its test dataset too.
function Database:QueryList(records, filter)
  filter = filter or {}
  -- A numeric quality matches that quality exactly; a set table matches any listed quality
  -- (multi-select). Anything else (e.g. a stray "all" sentinel) is ignored so it can never
  -- crash the comparison below and take the window with it.
  local qIsSet = type(filter.quality) == "table"
  local qExact = type(filter.quality) == "number" and filter.quality or nil
  local src = filter.source
  local srcIsSet = type(src) == "table"
  local char = filter.char
  local charIsSet = type(char) == "table"
  local itype = filter.itemType
  local itypeIsSet = type(itype) == "table"
  local isub = filter.itemSubType
  local isubIsSet = type(isub) == "table"
  local mapID = filter.mapID
  local mapIsSet = type(mapID) == "table"
  local boundSet = type(filter.bound) == "table" and filter.bound or nil
  local from = filter.from
  local to = filter.to
  local text = filter.text and filter.text:lower() or nil

  local out = {}
  for _, r in ipairs(records) do
    local ok = true
    if qIsSet then
      if not filter.quality[r.quality] then ok = false end
    elseif qExact and (r.quality or 0) ~= qExact then
      ok = false
    end
    if ok and src then
      if srcIsSet then
        if not src[r.source] then ok = false end
      elseif r.source ~= src then
        ok = false
      end
    end
    if ok and char then
      if charIsSet then if not char[r.char] then ok = false end
      elseif r.char ~= char then ok = false end
    end
    if ok and itype then
      if itypeIsSet then if not itype[r.itemType] then ok = false end
      elseif r.itemType ~= itype then ok = false end
    end
    if ok and isub then
      if isubIsSet then if not isub[r.itemSubType] then ok = false end
      elseif r.itemSubType ~= isub then ok = false end
    end
    if ok and mapID then
      if mapIsSet then if not mapID[r.mapID] then ok = false end
      elseif r.mapID ~= mapID then ok = false end
    end
    if ok and boundSet and not boundSet[r.bound or "NONE"] then ok = false end
    if ok and from and (r.ts or 0) < from then ok = false end
    if ok and to and (r.ts or 0) > to then ok = false end
    if ok and text then
      local name = r.itemName and r.itemName:lower() or ""
      if not name:find(text, 1, true) then ok = false end
    end
    if ok then out[#out + 1] = r end
  end
  return out
end

-- Query the active dataset (live history, or the test dataset in Browser test mode).
function Database:Query(filter)
  return self:QueryList(self:ActiveHistory(), filter)
end

-- Plain, metatable-free copy of the (optionally filtered) history — the forward-compatible
-- v2 export contract (see docs/data-model.md). Field shape is stable except for schema bumps
-- (v4 dropped the retired `sourceName`).
function Database:Export(filter)
  local out = {}
  for _, r in ipairs(self:Query(filter or {})) do
    out[#out + 1] = {
      ts = r.ts, char = r.char, classFile = r.classFile, itemID = r.itemID, itemLink = r.itemLink,
      itemName = r.itemName, quality = r.quality, itemLevel = r.itemLevel, bound = r.bound,
      sellPrice = r.sellPrice, itemType = r.itemType, itemSubType = r.itemSubType,
      quantity = r.quantity,
      source = r.source or "OTHER", sourceDetail = r.sourceDetail,
      zone = r.zone, mapID = r.mapID, subzone = r.subzone, confidence = r.confidence,
    }
  end
  return out
end

-- Aggregate the (optionally filtered) history in one O(n) pass. Returns count maps, value maps,
-- per-character/type/bound/time breakdowns, pre-sorted top lists, and totals/highlights — the
-- struct all Insights widgets consume (see docs/browser.md). "Value" is vendor value: sellPrice × quantity
-- (captured at loot time; not market price). New fields are additive.
function Database:Stats(filter)
  local records = self:Query(filter or {})
  local bySource, byQuality, byDay, byZone, byItem = {}, {}, {}, {}, {}
  local valueBySource, valueByDay, valueByZone = {}, {}, {}
  local byChar, byType, byBound, byHour, byWeekday, byKeystone, byConfidence =
    {}, {}, {}, {}, {}, {}, {}
  local distinctItems, distinctChars = 0, 0
  local firstTs, lastTs
  local totalValue, totalQuantity, epicPlus = 0, 0, 0
  local bestDrop, richestDrop

  for _, r in ipairs(records) do
    local qty = r.quantity or 1
    local value = (r.sellPrice or 0) * qty
    totalValue = totalValue + value
    totalQuantity = totalQuantity + qty

    local src = r.source or "OTHER"
    bySource[src] = (bySource[src] or 0) + 1
    valueBySource[src] = (valueBySource[src] or 0) + value

    local q = r.quality or 0
    byQuality[q] = (byQuality[q] or 0) + 1
    if q >= 4 then epicPlus = epicPlus + 1 end

    if r.ts then
      local day = date("%Y-%m-%d", r.ts)
      byDay[day] = (byDay[day] or 0) + 1
      valueByDay[day] = (valueByDay[day] or 0) + value
      local d = date("*t", r.ts)
      byHour[d.hour] = (byHour[d.hour] or 0) + 1
      byWeekday[d.wday - 1] = (byWeekday[d.wday - 1] or 0) + 1  -- Lua wday 1=Sun → key 0=Sun
      if not firstTs or r.ts < firstTs then firstTs = r.ts end
      if not lastTs or r.ts > lastTs then lastTs = r.ts end
    end

    local zone = r.zone or "Unknown"
    byZone[zone] = (byZone[zone] or 0) + 1
    valueByZone[zone] = (valueByZone[zone] or 0) + value

    local ty = r.itemType
    if ty and ty ~= "" then byType[ty] = (byType[ty] or 0) + 1 end

    local bk = r.bound or "UNBOUND"
    byBound[bk] = (byBound[bk] or 0) + 1

    local conf = r.confidence or "INFERRED"
    byConfidence[conf] = (byConfidence[conf] or 0) + 1

    local kl = r.sourceDetail and r.sourceDetail.keystoneLevel
    if kl then byKeystone[kl] = (byKeystone[kl] or 0) + 1 end

    local id = r.itemID
    if id ~= nil then
      local e = byItem[id]
      if e then
        e.count = e.count + 1
        e.value = e.value + value
      else
        byItem[id] = { itemID = id, itemName = r.itemName, quality = r.quality,
                       count = 1, value = value }
        distinctItems = distinctItems + 1
      end
    end

    local ch = r.char
    if ch then
      local ce = byChar[ch]
      if ce then
        ce.count = ce.count + 1
        ce.value = ce.value + value
      else
        byChar[ch] = { char = ch, classFile = r.classFile, count = 1, value = value }
        distinctChars = distinctChars + 1
      end
    end

    -- Highlights: best gear (max itemLevel, ties → higher quality) + richest single drop.
    local ilvl = r.itemLevel or 0
    if ilvl > 0 and (not bestDrop or ilvl > bestDrop.itemLevel
        or (ilvl == bestDrop.itemLevel and (r.quality or 0) > (bestDrop.quality or 0))) then
      bestDrop = { itemName = r.itemName, quality = r.quality, itemLevel = ilvl, itemLink = r.itemLink }
    end
    if value > 0 and (not richestDrop or value > richestDrop.value) then
      richestDrop = { itemName = r.itemName, quality = r.quality, value = value, itemLink = r.itemLink }
    end
  end

  local topZones = {}
  for zone, count in pairs(byZone) do
    topZones[#topZones + 1] = { zone = zone, count = count, value = valueByZone[zone] or 0 }
  end
  table.sort(topZones, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.zone < b.zone
  end)

  -- topItems and topItemsByValue share the same entry tables (from byItem) — two orderings.
  local topItems, topItemsByValue = {}, {}
  for _, e in pairs(byItem) do
    topItems[#topItems + 1] = e
    topItemsByValue[#topItemsByValue + 1] = e
  end
  table.sort(topItems, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    if (a.quality or 0) ~= (b.quality or 0) then return (a.quality or 0) > (b.quality or 0) end
    return (a.itemID or 0) < (b.itemID or 0)
  end)
  table.sort(topItemsByValue, function(a, b)
    if a.value ~= b.value then return a.value > b.value end
    if a.count ~= b.count then return a.count > b.count end
    return (a.itemID or 0) < (b.itemID or 0)
  end)

  local activeDays, busiestDay = 0, nil
  for day, count in pairs(byDay) do
    activeDays = activeDays + 1
    if not busiestDay or count > busiestDay.count then busiestDay = { day = day, count = count } end
  end

  return {
    bySource = bySource, byQuality = byQuality, byDay = byDay,
    byZone = byZone, byItem = byItem, topZones = topZones,
    topItems = topItems, topItemsByValue = topItemsByValue,
    valueBySource = valueBySource, valueByDay = valueByDay, valueByZone = valueByZone,
    byChar = byChar, byType = byType, byBound = byBound,
    byHour = byHour, byWeekday = byWeekday, byKeystone = byKeystone, byConfidence = byConfidence,
    totals = {
      records = #records, distinctItems = distinctItems, distinctChars = distinctChars,
      firstTs = firstTs, lastTs = lastTs,
      totalValue = totalValue, totalQuantity = totalQuantity,
      activeDays = activeDays, busiestDay = busiestDay,
      epicPlus = epicPlus, bestDrop = bestDrop, richestDrop = richestDrop,
    },
  }
end

local function fireHistoryChanged()
  if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_HistoryChanged") end
end

-- Public HistoryChanged emitter for non-Database owners of a visible-history change (the
-- blacklist/whitelist lists in NS.Filters call this after mutating db.global). Keeps Database the
-- single sending module for this message (message-bus's one-sender-per-message invariant).
function Database:FireHistoryChanged()
  fireHistoryChanged()
end

-- Delete a single row by index (from the table UI). Compacts the array; fires HistoryChanged.
function Database:DeleteAt(index)
  local history = NS.db.global.history
  if type(index) ~= "number" or index < 1 or index > #history then return false end
  local ts = history[index] and history[index].ts
  table.remove(history, index)
  self:RebuildWhitelistIndex()   -- a viaWhitelist row may have gone
  fireHistoryChanged()
  if NS.State.debug and NS.Debug then
    NS.Debug("Data", "deleted row @%s", tostring(ts))
  end
  return true
end

-- Delete every record for which pred(record) is true. Rebuild-and-swap (no holes).
-- Returns the number removed; fires HistoryChanged.
function Database:Delete(pred)
  local history = NS.db.global.history
  local kept, removed = {}, 0
  for _, r in ipairs(history) do
    if pred(r) then
      removed = removed + 1
    else
      kept[#kept + 1] = r
    end
  end
  NS.db.global.history = kept
  self:RebuildWhitelistIndex()
  fireHistoryChanged()
  return removed
end

-- Wipe all history (the /lh purge command). Fires HistoryChanged. Returns the count removed.
function Database:Purge()
  local removed = #NS.db.global.history
  NS.db.global.history = {}
  NS.State.viaWhitelistIDs = {}
  fireHistoryChanged()
  if NS.State.debug and NS.Debug then
    NS.Debug("Data", "purge-all removed %s rows", tostring(removed))
  end
  return removed
end

-- Rough per-record byte cost as written to the SavedVariables .lua file. WoW gives addons
-- no way to read the real on-disk file size, so we estimate: a fixed overhead covering the
-- record's key names, table syntax, and numeric fields, plus the length of each string field.
local RECORD_OVERHEAD = 256
local function estimateRecordBytes(r)
  local n = RECORD_OVERHEAD
  local strFields = { r.itemLink, r.itemName,
                      r.zone, r.subzone, r.char, r.itemType, r.itemSubType }
  for _, s in ipairs(strFields) do
    if type(s) == "string" then n = n + #s end
  end
  return n
end

-- Storage summary for the settings panel: record count, span in days since the earliest
-- record, and an ESTIMATED SavedVariables byte size (see estimateRecordBytes). `now` is
-- injectable for tests; it defaults to time().
function Database:StorageStats(now)
  local history = NS.db.global.history
  local firstTs, bytes = nil, 0
  for _, r in ipairs(history) do
    if r.ts and (not firstTs or r.ts < firstTs) then firstTs = r.ts end
    bytes = bytes + estimateRecordBytes(r)
  end
  local days = 0
  if firstTs then
    now = now or time()
    days = math.max(1, math.ceil((now - firstTs) / 86400))
  end
  return { count = #history, days = days, bytes = bytes }
end

-- Retention cleanup. Drops records older than settings.retentionDays (0 == Never).
-- Rebuild-and-swap avoids O(n^2) shifting and array holes. Fires HistoryChanged when it runs.
function Database:PruneOld()
  local days = NS.db.global.settings.retentionDays
  if not days or days == 0 then return 0 end
  local cutoff = time() - days * 86400
  local history = NS.db.global.history
  local kept = {}
  for _, r in ipairs(history) do
    if (r.ts or 0) >= cutoff then kept[#kept + 1] = r end
  end
  local removed = #history - #kept
  NS.db.global.history = kept
  self:RebuildWhitelistIndex()
  fireHistoryChanged()
  if NS.State.debug and NS.Debug then
    NS.Debug("Prune", "retention %sd: removed %s rows", tostring(days), tostring(removed))
  end
  return removed
end
