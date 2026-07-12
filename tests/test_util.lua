local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

test("Constants: source enum + order", function()
  assertEqual(NS.Constants.SourceType.KILL, "KILL")
  assertEqual(NS.Constants.SourceType.OTHER, "OTHER")
  assertEqual(NS.Constants.Confidence.CERTAIN, "CERTAIN")
  assertEqual(#NS.Constants.SourceOrder, 11)
  -- Enum stays whole (export contract), but the mute options are scoped to sources with a live
  -- capture path (F-001): AH/CRAFT/ROLL have no stamper yet and are hidden.
  assertEqual(#NS.Constants.SOURCE_OPTIONS, 8)
  local muteable = {}
  for _, o in ipairs(NS.Constants.SOURCE_OPTIONS) do muteable[o.value] = true end
  assertFalse(muteable.AH); assertFalse(muteable.CRAFT); assertFalse(muteable.ROLL)
  assertTrue(muteable.KILL); assertTrue(muteable.VENDOR)
end)

test("Util: RangeFrom maps range keys to a lower-bound timestamp", function()
  local now = os.time()
  assertEqual(NS.Util.RangeFrom("all"), nil)          -- unbounded
  assertEqual(NS.Util.RangeFrom("bogus"), nil)        -- unknown → unbounded
  local d7 = NS.Util.RangeFrom("7d")
  assertTrue(d7 ~= nil and (now - d7) >= 7 * 86400 - 5 and (now - d7) <= 7 * 86400 + 5)
  local d30 = NS.Util.RangeFrom("30d")
  assertTrue(d30 ~= nil and (now - d30) >= 30 * 86400 - 5 and (now - d30) <= 30 * 86400 + 5)
  local today = NS.Util.RangeFrom("today")
  assertTrue(today ~= nil and today <= now and (now - today) < 86400)  -- start of the calendar day
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

test("Util: FormatClock is HH:MM", function()
  local ts = 1600000000
  assertEqual(NS.Util.FormatClock(ts), os.date("%H:%M", ts))
end)

test("Util: FormatDate is DD-MMM-YYYY", function()
  local ts = 1600000000
  assertEqual(NS.Util.FormatDate(ts), os.date("%d-%b-%Y", ts))
end)

test("Util: FormatMoney shows non-zero parts", function()
  assertEqual(NS.Util.FormatMoney(0), "")
  assertEqual(NS.Util.FormatMoney(nil), "")
  assertEqual(NS.Util.FormatMoney(5), "5c")
  assertEqual(NS.Util.FormatMoney(120), "1s 20c")
  assertEqual(NS.Util.FormatMoney(10000), "1g")
  assertEqual(NS.Util.FormatMoney(123456), "12g 34s 56c")
end)

test("Util: FormatBytes scales B / kB / MB", function()
  assertEqual(NS.Util.FormatBytes(0), "0 B")
  assertEqual(NS.Util.FormatBytes(nil), "0 B")
  assertEqual(NS.Util.FormatBytes(820), "820 B")
  assertEqual(NS.Util.FormatBytes(1536), "1.5 kB")
  assertEqual(NS.Util.FormatBytes(3 * 1024 * 1024), "3.0 MB")
end)

test("Database: InitDB creates account-wide store", function()
  assertEqual(NS.db.global.schemaVersion, 4)
  assertTrue(type(NS.db.global.history) == "table")
  assertEqual(#NS.db.global.history, 0)
  assertEqual(NS.db.global.settings.qualityThreshold, 1)   -- default: Common (white) and above
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

test("Schema: reset does not alias the table-typed default (F-003)", function()
  local def = NS.Schema:Default("settings.excludedSources")
  NS.Schema:Set("settings.excludedSources", def)
  -- Mutating the stored set in place must not poison the schema default.
  NS.db.global.settings.excludedSources.KILL = true
  local fresh = NS.Schema:Default("settings.excludedSources")
  assertTrue(fresh.KILL == nil)
  -- Two Default() calls must not share identity either.
  assertFalse(NS.Schema:Default("settings.excludedSources")
    == NS.Schema:Default("settings.excludedSources"))
  -- Restore shared DB state for tests that follow (they mute by excludedSources).
  NS.Schema:Set("settings.excludedSources", {})
end)
