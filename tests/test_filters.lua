local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local F = NS.Filters

-- Each test leaves the lists empty so later suites (Collector/Database) start clean.
local function clear()
  NS.db.global.blacklist = {}
  NS.db.global.whitelist = {}
end

test("Filters: AddBlacklist stores the id; IsBlacklisted sees it", function()
  clear()
  assertTrue(F:AddBlacklist(4242))
  assertTrue(F:IsBlacklisted(4242))
  assertFalse(F:IsWhitelisted(4242))
  clear()
end)

test("Filters: AddBlacklist accepts a numeric string", function()
  clear()
  assertTrue(F:AddBlacklist("4242"))
  assertTrue(F:IsBlacklisted(4242))
  assertTrue(F:IsBlacklisted("4242"))
  clear()
end)

test("Filters: adding to one list removes the id from the other", function()
  clear()
  F:AddWhitelist(500)
  assertTrue(F:IsWhitelisted(500))
  F:AddBlacklist(500)                  -- moves it
  assertTrue(F:IsBlacklisted(500))
  assertFalse(F:IsWhitelisted(500))
  clear()
end)

test("Filters: Remove drops the id", function()
  clear()
  F:AddBlacklist(7)
  assertTrue(F:RemoveBlacklist(7))
  assertFalse(F:IsBlacklisted(7))
  clear()
end)

test("Filters: mutations write a fresh table (no shared-default aliasing)", function()
  clear()
  local before = NS.db.global.blacklist
  F:AddBlacklist(9)
  assertTrue(NS.db.global.blacklist ~= before, "blacklist table replaced, not mutated in place")
  clear()
end)

test("Filters: AddBlacklist rejects non-numeric input", function()
  clear()
  assertFalse(F:AddBlacklist("not-an-id"))
  assertFalse(F:AddBlacklist(nil))
  clear()
end)

test("Filters: adding an id already present is a no-op (returns false)", function()
  clear()
  assertTrue(F:AddBlacklist(11))
  assertFalse(F:AddBlacklist(11))
  clear()
end)

test("Filters: change fires HistoryChanged (via Database) and re-caches the Collector", function()
  clear()
  local sent = {}
  local origSend = NS.bus.SendMessage
  NS.bus.SendMessage = function(_, msg) sent[#sent + 1] = msg end
  -- Spy on the direct Collector re-cache (the lists are not a bus SettingsChanged sender).
  local recached = false
  local realRefresh = NS.Collector.RefreshUpvalues
  NS.Collector.RefreshUpvalues = function(self, ...) recached = true; return realRefresh(self, ...) end

  F:AddBlacklist(321)

  NS.bus.SendMessage = origSend
  NS.Collector.RefreshUpvalues = realRefresh

  local gotHistory, gotSettings = false, false
  for _, m in ipairs(sent) do
    if m == "Ka0s_LootHistory_HistoryChanged" then gotHistory = true end
    if m == "Ka0s_LootHistory_SettingsChanged" then gotSettings = true end
  end
  assertTrue(gotHistory, "HistoryChanged fired")
  assertFalse(gotSettings, "no second SettingsChanged sender")
  assertTrue(recached, "Collector re-cached its list upvalues")
  clear()
end)

test("Filters: ClearList empties one list and returns the count removed", function()
  clear()
  F:AddBlacklist(1); F:AddBlacklist(2); F:AddBlacklist(3)
  F:AddWhitelist(9)
  assertEqual(F:ClearList("blacklist"), 3)
  assertEqual(F:Count(F:Blacklist()), 0)
  assertTrue(F:IsWhitelisted(9), "ClearList blacklist leaves the whitelist intact")
  clear()
end)

test("Filters: ClearList on an empty or unknown list is a no-op returning 0", function()
  clear()
  assertEqual(F:ClearList("blacklist"), 0)   -- already empty
  assertEqual(F:ClearList("bogus"), 0)        -- unknown key
  clear()
end)

test("Filters: ClearList writes a fresh table (no shared-default aliasing)", function()
  clear()
  F:AddBlacklist(5)
  local before = NS.db.global.blacklist
  F:ClearList("blacklist")
  assertTrue(NS.db.global.blacklist ~= before, "blacklist table replaced, not mutated in place")
  clear()
end)

test("Filters: ClearAll empties both lists and returns the total removed", function()
  clear()
  F:AddBlacklist(1); F:AddBlacklist(2)
  F:AddWhitelist(3)
  assertEqual(F:ClearAll(), 3)
  assertEqual(F:Count(F:Blacklist()), 0)
  assertEqual(F:Count(F:Whitelist()), 0)
  clear()
end)

test("Filters: ClearAll with both lists empty is a no-op returning 0", function()
  clear()
  assertEqual(F:ClearAll(), 0)
  clear()
end)

test("Filters: ClearList fires HistoryChanged and re-caches the Collector", function()
  clear()
  F:AddBlacklist(77)
  local sent = {}
  local origSend = NS.bus.SendMessage
  NS.bus.SendMessage = function(_, msg) sent[#sent + 1] = msg end
  local recached = false
  local realRefresh = NS.Collector.RefreshUpvalues
  NS.Collector.RefreshUpvalues = function(self, ...) recached = true; return realRefresh(self, ...) end

  F:ClearList("blacklist")

  NS.bus.SendMessage = origSend
  NS.Collector.RefreshUpvalues = realRefresh

  local gotHistory = false
  for _, m in ipairs(sent) do if m == "Ka0s_LootHistory_HistoryChanged" then gotHistory = true end end
  assertTrue(gotHistory, "HistoryChanged fired")
  assertTrue(recached, "Collector re-cached its list upvalues")
  clear()
end)

test("Filters: SortedIDs returns ids ascending", function()
  clear()
  F:AddBlacklist(30); F:AddBlacklist(10); F:AddBlacklist(20)
  local ids = F:SortedIDs(F:Blacklist())
  assertEqual(ids[1], 10); assertEqual(ids[2], 20); assertEqual(ids[3], 30)
  clear()
end)

test("Filters: ParseItemID reads a number, an item link, and an itemString", function()
  assertEqual(F:ParseItemID("211296"), 211296)
  assertEqual(F:ParseItemID(211296), 211296)
  assertEqual(F:ParseItemID("|cffa335ee|Hitem:211296::::::::80:::::|h[X]|h|r"), 211296)
  assertEqual(F:ParseItemID("item:6948:0:0"), 6948)
  assertEqual(F:ParseItemID("nonsense"), nil)
end)
