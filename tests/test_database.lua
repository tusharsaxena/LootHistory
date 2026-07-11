local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue =
  T.test, T.assertEqual, T.assertTrue

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

test("Database: Query by minimum quality (>=)", function()
  seed()
  local r = NS.Database:Query({ quality = 3 })
  assertEqual(#r, 2)
  assertEqual(r[1].itemID, 2)
  assertEqual(r[2].itemID, 3)
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
