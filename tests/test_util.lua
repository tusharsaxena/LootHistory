local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

test("Constants: source enum + order", function()
  assertEqual(NS.Constants.SourceType.KILL, "KILL")
  assertEqual(NS.Constants.SourceType.OTHER, "OTHER")
  assertEqual(NS.Constants.Confidence.CERTAIN, "CERTAIN")
  assertEqual(#NS.Constants.SourceOrder, 11)
  assertEqual(#NS.Constants.SOURCE_OPTIONS, 11)
end)

test("Util: PlayerKey is Name-Realm", function()
  assertEqual(NS.Util.PlayerKey(), "Mock-Realm")
end)

test("Util: SplitPath splits dotted paths", function()
  local p = NS.Util.SplitPath("settings.qualityThreshold")
  assertEqual(#p, 2)
  assertEqual(p[1], "settings")
  assertEqual(p[2], "qualityThreshold")
end)

do
  local LINK = "|cff1eff00|Hitem:12345::::::::70:::::|h[Green Widget]|h|r"

  test("Util: ParseSelfLoot single self-loot → link, qty 1", function()
    local msg = string.format(T.mocks.LOOT_ITEM_SELF, LINK)
    local link, qty = NS.Util.ParseSelfLoot(msg)
    assertEqual(link, LINK)
    assertEqual(qty, 1)
  end)

  test("Util: ParseSelfLoot multiple self-loot → link, qty N", function()
    local msg = string.format(T.mocks.LOOT_ITEM_SELF_MULTIPLE, LINK, 3)
    local link, qty = NS.Util.ParseSelfLoot(msg)
    assertEqual(link, LINK)
    assertEqual(qty, 3)
  end)

  test("Util: ParseSelfLoot pushed variant → link, qty", function()
    local one = string.format(T.mocks.LOOT_ITEM_PUSHED_SELF, LINK)
    local link, qty = NS.Util.ParseSelfLoot(one)
    assertEqual(link, LINK)
    assertEqual(qty, 1)

    local many = string.format(T.mocks.LOOT_ITEM_PUSHED_SELF_MULTIPLE, LINK, 5)
    local link2, qty2 = NS.Util.ParseSelfLoot(many)
    assertEqual(link2, LINK)
    assertEqual(qty2, 5)
  end)

  test("Util: ParseSelfLoot ignores another player's loot", function()
    local msg = "Someone else receives loot: " .. LINK .. "."
    assertEqual(NS.Util.ParseSelfLoot(msg), nil)
  end)
end

test("Database: InitDB creates account-wide store", function()
  assertEqual(NS.db.global.schemaVersion, 1)
  assertTrue(type(NS.db.global.history) == "table")
  assertEqual(#NS.db.global.history, 0)
  assertEqual(NS.db.global.settings.qualityThreshold, 0)
end)

test("Schema: Set writes through the single seam", function()
  local ok = NS.Schema:Set("settings.qualityThreshold", 4)
  assertTrue(ok)
  assertEqual(NS.db.global.settings.qualityThreshold, 4)
end)

test("Schema: Set unknown path returns false", function()
  local ok, err = NS.Schema:Set("does.not.exist", 1)
  assertFalse(ok)
  assertTrue(type(err) == "string")
end)

test("Schema: nested minimap path writes", function()
  local ok = NS.Schema:Set("minimap.hide", true)
  assertTrue(ok)
  assertEqual(NS.db.global.minimap.hide, true)
end)
