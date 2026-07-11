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

-- Query / Delete / PruneOld / Export / Stats are implemented in Milestone 2.
-- PruneOld is stubbed now so retention wiring and settings onChange are safe to call.
function Database:PruneOld()
  -- no-op until Milestone 2
end
