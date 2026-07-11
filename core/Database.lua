local addonName, NS = ...

-- AceDB init. Account-wide: all history + settings live in NS.db.global.
function NS:InitDB()
  NS.db = LibStub("AceDB-3.0"):New("LootHistoryDB", NS.defaults, true)
end

-- Schema migration runner. Ships from day one even with no migrations yet.
function NS:RunMigrations()
  local g = NS.db.global
  g.schemaVersion = g.schemaVersion or 1
  -- if g.schemaVersion < 2 then <transform each record> ; g.schemaVersion = 2 end
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
      ts = r.ts, char = r.char, itemID = r.itemID, itemLink = r.itemLink,
      itemName = r.itemName, quality = r.quality, quantity = r.quantity,
      source = r.source, sourceName = r.sourceName, sourceDetail = r.sourceDetail,
      zone = r.zone, mapID = r.mapID, subzone = r.subzone, confidence = r.confidence,
    }
  end
  return out
end

-- Delete / PruneOld / Stats are implemented later in Milestone 2.
-- PruneOld is stubbed now so retention wiring and settings onChange are safe to call.
function Database:PruneOld()
  -- no-op until Task 2.3
end
