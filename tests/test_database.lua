local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- Capture bus messages fired during fn(); returns an array of { msg, ... } records.
local function captureMessages(fn)
  local sent = {}
  local orig = NS.bus.SendMessage
  NS.bus.SendMessage = function(_, msg, a, b)
    sent[#sent + 1] = { msg = msg, a = a, b = b }
  end
  fn()
  NS.bus.SendMessage = orig
  return sent
end

test("Database: Add appends, increments Count, returns index", function()
  local before = NS.Database:Count()
  local rec = { itemID = 999, quality = 3 }
  local idx = NS.Database:Add(rec)
  assertEqual(NS.Database:Count(), before + 1)
  assertEqual(idx, before + 1)
  assertTrue(NS.Database:History()[idx] == rec)
end)

test("Database: Add fires RecordAdded with record + index", function()
  local before = NS.Database:Count()
  local rec = { itemID = 1001 }
  local sent = captureMessages(function() NS.Database:Add(rec) end)
  assertEqual(#sent, 1)
  assertEqual(sent[1].msg, "Ka0s_LootHistory_RecordAdded")
  assertTrue(sent[1].a == rec)
  assertEqual(sent[1].b, before + 1)
end)

-- Deterministic seed for Query/Export/Delete/Prune tests (bypasses Add + its message).
local function seed()
  NS.db.global.history = {
    { ts = 1000, char = "A-Realm", itemID = 1, itemName = "Red Potion",
      quality = 1, source = "KILL",      mapID = 10 },
    { ts = 2000, char = "B-Realm", itemID = 2, itemName = "Blue Cloak",
      quality = 3, source = "CONTAINER", mapID = 20, sourceDetail = { npcID = 55 } },
    { ts = 3000, char = "A-Realm", itemID = 3, itemName = "Red Sword",
      quality = 4, source = "KILL",      mapID = 10 },
    { ts = 4000, char = "C-Realm", itemID = 4, itemName = "Green Ring",
      quality = 2, source = "VENDOR",    mapID = 20 },
  }
  return NS.db.global.history
end
T.seedDatabase = seed

test("Database: Query empty filter returns all", function()
  seed()
  assertEqual(#NS.Database:Query({}), 4)
  assertEqual(#NS.Database:Query(), 4)
end)

test("Database: Query by exact quality", function()
  seed()
  local r = NS.Database:Query({ quality = 3 })
  assertEqual(#r, 1)
  assertEqual(r[1].itemID, 2)
end)

test("Database: Query by quality set (multi-select membership)", function()
  seed()
  -- qualities present: 1, 3, 4, 2 → selecting {2,4} matches itemIDs 3 and 4.
  local r = NS.Database:Query({ quality = { [2] = true, [4] = true } })
  assertEqual(#r, 2)
  assertEqual(r[1].itemID, 3)
  assertEqual(r[2].itemID, 4)
end)

test("Database: Query ignores a non-numeric quality (no crash, returns all)", function()
  seed()
  -- Regression: a stray "all" sentinel used to reach `r.quality < "all"` and error out.
  assertEqual(#NS.Database:Query({ quality = "all" }), 4)
end)

test("Database: QueryList filters an arbitrary array, not the live history", function()
  local recs = {
    { quality = 4, source = "KILL",   itemName = "Sword" },
    { quality = 1, source = "VENDOR", itemName = "Rag" },
  }
  assertEqual(#NS.Database:QueryList(recs, {}), 2)
  assertEqual(#NS.Database:QueryList(recs, { source = "KILL" }), 1)
  assertEqual(#NS.Database:QueryList(recs, { quality = 4 }), 1)
end)

test("Database: Query filters by itemType", function()
  local recs = {
    { itemType = "Armor",  itemName = "Helm" },
    { itemType = "Weapon", itemName = "Axe" },
    { itemType = "Armor",  itemName = "Boots" },
  }
  assertEqual(#NS.Database:QueryList(recs, { itemType = "Armor" }), 2)
  assertEqual(#NS.Database:QueryList(recs, { itemType = "Weapon" }), 1)
  assertEqual(#NS.Database:QueryList(recs, {}), 3)
  -- Multi-select: an itemType set matches any listed type.
  assertEqual(#NS.Database:QueryList(recs, { itemType = { Armor = true, Weapon = true } }), 3)
  assertEqual(#NS.Database:QueryList(recs, { itemType = { Weapon = true } }), 1)
end)

test("Database: Query filters by itemSubType", function()
  local recs = {
    { itemSubType = "Cloth", itemName = "Helm" },
    { itemSubType = "Plate", itemName = "Boots" },
    { itemSubType = "Cloth", itemName = "Robe" },
  }
  assertEqual(#NS.Database:QueryList(recs, { itemSubType = "Cloth" }), 2)
  assertEqual(#NS.Database:QueryList(recs, {}), 3)
  -- Multi-select: a subtype set matches any listed subtype.
  assertEqual(#NS.Database:QueryList(recs, { itemSubType = { Cloth = true, Plate = true } }), 3)
  assertEqual(#NS.Database:QueryList(recs, { itemSubType = { Plate = true } }), 1)
end)

test("Database: QueryList bound=NONE matches unbound records", function()
  local recs = {
    { bound = nil, itemID = 1 }, { bound = "BOE", itemID = 2 }, { bound = "BOP", itemID = 3 },
  }
  local out = NS.Database:QueryList(recs, { bound = { NONE = true } })
  assertEqual(#out, 1)
  assertEqual(out[1].itemID, 1)
end)

test("Database: QueryList bound set unions tokens", function()
  local recs = {
    { bound = nil, itemID = 1 }, { bound = "BOE", itemID = 2 },
    { bound = "ACCOUNT", itemID = 3 }, { bound = "WARBAND", itemID = 4 },
  }
  local out = NS.Database:QueryList(recs, { bound = { BOE = true, WARBAND = true } })
  assertEqual(#out, 2)
end)

test("Database: QueryList ignores non-table bound filter", function()
  local recs = { { bound = "BOE", itemID = 2 }, { bound = nil, itemID = 1 } }
  local out = NS.Database:QueryList(recs, { bound = "BOE" })
  assertEqual(#out, 2)  -- scalar bound ignored, all returned
end)

test("Database: Query by char/mapID set (multi-select membership)", function()
  seed()
  assertEqual(#NS.Database:Query({ char = { ["A-Realm"] = true, ["C-Realm"] = true } }), 3)
  assertEqual(#NS.Database:Query({ mapID = { [10] = true, [20] = true } }), 4)
  assertEqual(#NS.Database:Query({ mapID = { [20] = true } }), 2)
end)

test("Database: Query by source (string)", function()
  seed()
  assertEqual(#NS.Database:Query({ source = "KILL" }), 2)
  assertEqual(#NS.Database:Query({ source = "VENDOR" }), 1)
end)

test("Database: Query by source (set membership)", function()
  seed()
  assertEqual(#NS.Database:Query({ source = { KILL = true, VENDOR = true } }), 3)
end)

test("Database: Query by char and by mapID", function()
  seed()
  assertEqual(#NS.Database:Query({ char = "A-Realm" }), 2)
  assertEqual(#NS.Database:Query({ mapID = 20 }), 2)
end)

test("Database: Query by ts range (from/to inclusive)", function()
  seed()
  local r = NS.Database:Query({ from = 2000, to = 3000 })
  assertEqual(#r, 2)
  assertEqual(r[1].itemID, 2)
  assertEqual(r[2].itemID, 3)
end)

test("Database: Query by case-insensitive text substring", function()
  seed()
  assertEqual(#NS.Database:Query({ text = "red" }), 2)
  assertEqual(#NS.Database:Query({ text = "CLOAK" }), 1)
  assertEqual(#NS.Database:Query({ text = "zzz" }), 0)
end)

test("Database: Query combines predicates (AND)", function()
  seed()
  local r = NS.Database:Query({ source = "KILL", quality = 4 })
  assertEqual(#r, 1)
  assertEqual(r[1].itemID, 3)
end)

test("Database: VisibleHistory hides blacklisted ids but keeps them in history", function()
  seed()
  NS.db.global.blacklist = { [2] = true, [4] = true }
  local vis = NS.Database:VisibleHistory()
  assertEqual(#vis, 2)
  assertEqual(vis[1].itemID, 1)
  assertEqual(vis[2].itemID, 3)
  assertEqual(#NS.db.global.history, 4)   -- nothing deleted
  NS.db.global.blacklist = {}
end)

test("Database: VisibleHistory returns the raw array unchanged when blacklist is empty", function()
  seed()
  NS.db.global.blacklist = {}
  assertTrue(NS.Database:VisibleHistory() == NS.db.global.history)  -- no allocation
end)

test("Database: Query/Stats/Export all exclude blacklisted ids via ActiveHistory", function()
  seed()
  NS.db.global.blacklist = { [3] = true }
  assertEqual(#NS.Database:Query({}), 3)
  assertEqual(NS.Database:Stats({}).totals.records, 3)
  assertEqual(#NS.Database:Export({}), 3)
  NS.db.global.blacklist = {}
  assertEqual(#NS.Database:Query({}), 4)   -- restored once un-blacklisted
end)

test("Database: Export returns metatable-free copies with all fields", function()
  seed()
  local out = NS.Database:Export({})
  assertEqual(#out, 4)
  assertEqual(getmetatable(out[1]), nil)
  -- a copy, not the same table reference
  assertTrue(out[1] ~= NS.db.global.history[1])
  -- fields carried through, incl. sourceDetail
  assertEqual(out[2].itemID, 2)
  assertEqual(out[2].source, "CONTAINER")
  assertEqual(out[2].sourceDetail.npcID, 55)
  -- respects the filter
  assertEqual(#NS.Database:Export({ source = "KILL" }), 2)
end)

local function firedHistoryChanged(sent)
  for _, m in ipairs(sent) do
    if m.msg == "Ka0s_LootHistory_HistoryChanged" then return true end
  end
  return false
end

test("Database: DeleteAt removes the row, compacts, fires HistoryChanged", function()
  seed()
  local sent = captureMessages(function()
    assertTrue(NS.Database:DeleteAt(2))
  end)
  assertEqual(NS.Database:Count(), 3)
  local h = NS.Database:History()
  assertEqual(h[1].itemID, 1)
  assertEqual(h[2].itemID, 3) -- row 2 gone; array stays dense
  assertEqual(h[3].itemID, 4)
  assertTrue(firedHistoryChanged(sent))
end)

test("Database: DeleteAt out-of-range returns false, no change", function()
  seed()
  assertFalse(NS.Database:DeleteAt(99))
  assertFalse(NS.Database:DeleteAt(0))
  assertEqual(NS.Database:Count(), 4)
end)

test("Database: Delete(pred) removes all matching, compacts, returns count", function()
  seed()
  local removed = NS.Database:Delete(function(r) return r.source == "KILL" end)
  assertEqual(removed, 2)
  assertEqual(NS.Database:Count(), 2)
  local h = NS.Database:History()
  assertEqual(h[1].itemID, 2)
  assertEqual(h[2].itemID, 4)
end)

test("Database: PruneOld drops records older than retentionDays", function()
  local now, day = os.time(), 86400
  NS.db.global.history = {
    { ts = now - 10 * day, itemID = 1 },
    { ts = now - 40 * day, itemID = 2 },
    { ts = now - 100 * day, itemID = 3 },
  }
  NS.db.global.settings.retentionDays = 30
  local sent = captureMessages(function() NS.Database:PruneOld() end)
  assertEqual(NS.Database:Count(), 1)
  assertEqual(NS.Database:History()[1].itemID, 1)
  assertTrue(firedHistoryChanged(sent))
end)

test("Database: PruneOld with retentionDays=0 keeps everything", function()
  local now = os.time()
  NS.db.global.history = { { ts = now - 999 * 86400, itemID = 1 } }
  NS.db.global.settings.retentionDays = 0
  NS.Database:PruneOld()
  assertEqual(NS.Database:Count(), 1)
end)

test("Database: Purge wipes history and fires HistoryChanged", function()
  seed()
  assertTrue(NS.Database:Count() > 0)
  local sent = captureMessages(function() NS.Database:Purge() end)
  assertEqual(NS.Database:Count(), 0)
  assertTrue(firedHistoryChanged(sent))
end)

test("Database: PruneOld returns removed count and logs [Prune]", function()
  seed()
  NS.db.global.settings.retentionDays = 30
  NS.State.debug = true
  local before = #NS.DebugLog.buffer
  local removed = NS.Database:PruneOld()
  assertTrue(type(removed) == "number", "PruneOld returns a number")
  assertTrue(#NS.DebugLog.buffer > before, "a [Prune] line was logged")
  assertTrue(NS.DebugLog.buffer[#NS.DebugLog.buffer]:find("[Prune]", 1, true) ~= nil,
    "last line is tagged [Prune]")
  NS.State.debug = false
end)

test("Database: PruneOld is zero-alloc and silent when debug is off", function()
  seed()
  NS.db.global.settings.retentionDays = 30
  NS.State.debug = false
  local before = #NS.DebugLog.buffer
  NS.Database:PruneOld()
  assertEqual(#NS.DebugLog.buffer, before, "no line logged when debug off")
end)

test("Database: Purge returns removed count and logs [Data]", function()
  seed()
  NS.State.debug = true
  local n = NS.Database:Purge()
  assertTrue(type(n) == "number" and n > 0, "Purge returns the removed count")
  assertTrue(NS.DebugLog.buffer[#NS.DebugLog.buffer]:find("[Data]", 1, true) ~= nil,
    "last line is tagged [Data]")
  NS.State.debug = false
end)

test("Database: DeleteAt logs [Data] with the deleted row's ts", function()
  seed()
  NS.State.debug = true
  local ts = NS.db.global.history[1].ts
  assertTrue(NS.Database:DeleteAt(1))
  assertTrue(NS.DebugLog.buffer[#NS.DebugLog.buffer]:find("[Data]", 1, true) ~= nil,
    "last line is tagged [Data]")
  assertTrue(NS.DebugLog.buffer[#NS.DebugLog.buffer]:find(tostring(ts), 1, true) ~= nil,
    "the deleted row's ts appears in the line")
  NS.State.debug = false
end)

test("Database: StorageStats counts records, day span, and estimated bytes", function()
  NS.db.global.history = {
    { ts = 1000, char = "A-Realm", itemLink = "[Red]",  itemName = "Red" },
    { ts = 1000 + 3 * 86400, char = "A-Realm", itemLink = "[Blue]", itemName = "Blue" },
  }
  local s = NS.Database:StorageStats(1000 + 3 * 86400)  -- inject `now` = last ts
  assertEqual(s.count, 2)
  assertEqual(s.days, 3)                 -- ceil((now - firstTs) / 86400)
  assertTrue(s.bytes > 0)                -- overhead + string field lengths
end)

test("Database: StorageStats on empty history is zeroed", function()
  NS.db.global.history = {}
  local s = NS.Database:StorageStats(9999)
  assertEqual(s.count, 0)
  assertEqual(s.days, 0)
  assertEqual(s.bytes, 0)
end)

-- ── RunMigrations: the schema-migration seam (Ka0s Standard §2.2/§5.1) ─────────────
test("Database: RunMigrations sets schemaVersion when absent", function()
  NS.db.global.schemaVersion = nil
  NS:RunMigrations()
  assertEqual(NS.db.global.schemaVersion, 1)
end)

test("Database: RunMigrations leaves an already-current DB unchanged", function()
  NS.db.global.schemaVersion = 1
  NS:RunMigrations()
  assertEqual(NS.db.global.schemaVersion, 1)
end)

test("Database: RunMigrations is idempotent across repeated runs", function()
  NS.db.global.schemaVersion = nil
  NS:RunMigrations(); NS:RunMigrations(); NS:RunMigrations()
  assertEqual(NS.db.global.schemaVersion, 1)
end)

test("Database: RunMigrations is a safe no-op when the DB is absent", function()
  local saved = NS.db
  NS.db = nil
  NS:RunMigrations()   -- must not error with no db.global to touch
  NS.db = saved
end)

test("NS.MigrationSummary formats from/to/rows", function()
  assertEqual(NS.MigrationSummary(1, 2, 1423), "v1 -> v2, 1423 rows touched")
end)
