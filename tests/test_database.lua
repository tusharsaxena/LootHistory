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
