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

test("Database: Query by minimum quality (>=)", function()
  seed()
  local r = NS.Database:Query({ quality = 3 })
  assertEqual(#r, 2)
  assertEqual(r[1].itemID, 2)
  assertEqual(r[2].itemID, 3)
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
  assertEqual(#NS.Database:QueryList(recs, { quality = 3 }), 1)
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
