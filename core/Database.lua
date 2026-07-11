local addonName, NS = ...

-- AceDB init. Account-wide: all history + settings live in NS.db.global.
function NS:InitDB()
  NS.db = LibStub("AceDB-3.0"):New("LootHistoryDB", NS.defaults, true)
end

-- Schema migration runner. Ships from day one even with no migrations yet.
function NS:RunMigrations()
  local g = NS.db.global
  g.schemaVersion = g.schemaVersion or 1
  -- v2: records gained optional itemLevel + bound fields. Additive and nil-safe, so old
  -- records need no transform; they simply carry no ilvl/bound until re-looted.
  if g.schemaVersion < 2 then g.schemaVersion = 2 end
  -- v3: added classFile, sellPrice, itemType, itemSubType. Also additive/nil-safe.
  if g.schemaVersion < 3 then g.schemaVersion = 3 end
end

NS.Database = NS.Database or {}
local Database = NS.Database

function Database:History()
  return NS.db.global.history
end

function Database:Count()
  return #NS.db.global.history
end

-- Append a record to the account-wide history; fire RecordAdded; return its index.
function Database:Add(record)
  local history = NS.db.global.history
  history[#history + 1] = record
  local index = #history
  if NS.bus then
    NS.bus:SendMessage("Ka0s_LootHistory_RecordAdded", record, index)
  end
  return index
end

-- Return an array of records matching the filter spec. Fields, all optional (AND-combined):
--   quality (min, >=) · source (string or set table) · char · mapID · from/to (ts, inclusive)
--   · text (case-insensitive substring on itemName). Empty/nil filter returns all.
function Database:Query(filter)
  filter = filter or {}
  local minQ = filter.quality
  local src = filter.source
  local srcIsSet = type(src) == "table"
  local char = filter.char
  local mapID = filter.mapID
  local from = filter.from
  local to = filter.to
  local text = filter.text and filter.text:lower() or nil

  local out = {}
  for _, r in ipairs(NS.db.global.history) do
    local ok = true
    if minQ and (r.quality or 0) < minQ then ok = false end
    if ok and src then
      if srcIsSet then
        if not src[r.source] then ok = false end
      elseif r.source ~= src then
        ok = false
      end
    end
    if ok and char and r.char ~= char then ok = false end
    if ok and mapID and r.mapID ~= mapID then ok = false end
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

-- Plain, metatable-free copy of the (optionally filtered) history — the forward-compatible
-- v2 export contract (TECHNICAL_DESIGN §13). Do not change the field shape.
function Database:Export(filter)
  local out = {}
  for _, r in ipairs(self:Query(filter or {})) do
    out[#out + 1] = {
      ts = r.ts, char = r.char, classFile = r.classFile, itemID = r.itemID, itemLink = r.itemLink,
      itemName = r.itemName, quality = r.quality, itemLevel = r.itemLevel, bound = r.bound,
      sellPrice = r.sellPrice, itemType = r.itemType, itemSubType = r.itemSubType,
      quantity = r.quantity,
      source = r.source, sourceName = r.sourceName, sourceDetail = r.sourceDetail,
      zone = r.zone, mapID = r.mapID, subzone = r.subzone, confidence = r.confidence,
    }
  end
  return out
end

-- Aggregate the (optionally filtered) history in one O(n) pass. Returns count maps plus
-- pre-sorted topZones/topItems and totals — the struct all Insights widgets consume (TD §8).
function Database:Stats(filter)
  local records = self:Query(filter or {})
  local bySource, byQuality, byDay, byZone, byItem = {}, {}, {}, {}, {}
  local chars = {}
  local distinctItems, distinctChars = 0, 0
  local firstTs, lastTs

  for _, r in ipairs(records) do
    local src = r.source or "OTHER"
    bySource[src] = (bySource[src] or 0) + 1

    local q = r.quality or 0
    byQuality[q] = (byQuality[q] or 0) + 1

    if r.ts then
      local day = date("%Y-%m-%d", r.ts)
      byDay[day] = (byDay[day] or 0) + 1
      if not firstTs or r.ts < firstTs then firstTs = r.ts end
      if not lastTs or r.ts > lastTs then lastTs = r.ts end
    end

    local zone = r.zone or "Unknown"
    byZone[zone] = (byZone[zone] or 0) + 1

    local id = r.itemID
    if id ~= nil then
      local e = byItem[id]
      if e then
        e.count = e.count + 1
      else
        byItem[id] = { itemID = id, itemName = r.itemName, quality = r.quality, count = 1 }
        distinctItems = distinctItems + 1
      end
    end

    if r.char and not chars[r.char] then
      chars[r.char] = true
      distinctChars = distinctChars + 1
    end
  end

  local topZones = {}
  for zone, count in pairs(byZone) do topZones[#topZones + 1] = { zone = zone, count = count } end
  table.sort(topZones, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.zone < b.zone
  end)

  local topItems = {}
  for _, e in pairs(byItem) do topItems[#topItems + 1] = e end
  table.sort(topItems, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    if (a.quality or 0) ~= (b.quality or 0) then return (a.quality or 0) > (b.quality or 0) end
    return (a.itemID or 0) < (b.itemID or 0)
  end)

  return {
    bySource = bySource, byQuality = byQuality, byDay = byDay,
    byZone = byZone, byItem = byItem, topZones = topZones, topItems = topItems,
    totals = {
      records = #records, distinctItems = distinctItems, distinctChars = distinctChars,
      firstTs = firstTs, lastTs = lastTs,
    },
  }
end

local function fireHistoryChanged()
  if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_HistoryChanged") end
end

-- Delete a single row by index (from the table UI). Compacts the array; fires HistoryChanged.
function Database:DeleteAt(index)
  local history = NS.db.global.history
  if type(index) ~= "number" or index < 1 or index > #history then return false end
  table.remove(history, index)
  fireHistoryChanged()
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
  fireHistoryChanged()
  return removed
end

-- Wipe all history (the /lh purge command). Fires HistoryChanged.
function Database:Purge()
  NS.db.global.history = {}
  fireHistoryChanged()
end

-- Retention cleanup. Drops records older than settings.retentionDays (0 == Never).
-- Rebuild-and-swap avoids O(n^2) shifting and array holes. Fires HistoryChanged when it runs.
function Database:PruneOld()
  local days = NS.db.global.settings.retentionDays
  if not days or days == 0 then return end
  local cutoff = time() - days * 86400
  local history = NS.db.global.history
  local kept = {}
  for _, r in ipairs(history) do
    if (r.ts or 0) >= cutoff then kept[#kept + 1] = r end
  end
  NS.db.global.history = kept
  fireHistoryChanged()
end
