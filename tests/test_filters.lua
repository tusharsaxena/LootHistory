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

test("Filters: change fires SettingsChanged + HistoryChanged", function()
  clear()
  local sent = {}
  local orig = NS.bus.SendMessage
  NS.bus.SendMessage = function(_, msg) sent[#sent + 1] = msg end
  F:AddBlacklist(321)
  NS.bus.SendMessage = orig
  local gotSettings, gotHistory = false, false
  for _, m in ipairs(sent) do
    if m == "Ka0s_LootHistory_SettingsChanged" then gotSettings = true end
    if m == "Ka0s_LootHistory_HistoryChanged" then gotHistory = true end
  end
  assertTrue(gotSettings, "SettingsChanged fired")
  assertTrue(gotHistory, "HistoryChanged fired")
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
