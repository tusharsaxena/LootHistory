local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- ── Secret-safe printer (events-frames-taint-§8) ──────────────────────────────────────────────
-- A stand-in for a combat "secret" value: it models BOTH halves of the real trap — the `..`
-- operator SUCCEEDS (silently propagating secretness), while table.concat RAISES. A `..`-based
-- probe would wrongly report this as safe; NS.IsConcatSafe must probe table.concat.
local secretMock = setmetatable({}, {
  __concat = function() return "secret-propagated" end,
})

test("IsConcatSafe: true for number/string, false for an un-concatenable value", function()
  assertTrue(NS.IsConcatSafe(1234) == true, "numbers concat fine")
  assertTrue(NS.IsConcatSafe("hi") == true, "strings concat fine")
  assertTrue(NS.IsConcatSafe(secretMock) == false, "secret-like value must be flagged unsafe")
end)

test("SafeToString: passes normal values through tostring", function()
  assertEqual(NS.SafeToString(1234), "1234")
  assertEqual(NS.SafeToString("hi"), "hi")
  assertEqual(NS.SafeToString(nil), "nil")
  assertEqual(NS.SafeToString(true), "true")
end)

test("SafeToString: renders a secret value as <secret> instead of raising", function()
  assertEqual(NS.SafeToString(secretMock), "<secret>")
end)

test("NS.Print: writes a cyan-tagged, space-joined line to the chat sink", function()
  local cf = T.mocks.DEFAULT_CHAT_FRAME
  local old, got = cf.AddMessage, nil
  cf.AddMessage = function(_, msg) got = msg end
  NS.Print("hello", "world")
  cf.AddMessage = old
  assertEqual(got, NS.PREFIX .. " hello world")
end)

test("NS.Print: tolerates a secret arg (no concat crash), renders it <secret>", function()
  local cf = T.mocks.DEFAULT_CHAT_FRAME
  local old, got = cf.AddMessage, nil
  cf.AddMessage = function(_, msg) got = msg end
  local ok = pcall(NS.Print, "value:", secretMock)
  cf.AddMessage = old
  assertTrue(ok, "Print must not raise on a secret arg")
  assertTrue(got:find("value: <secret>", 1, true) ~= nil,
    "the secret arg should render as <secret>: " .. tostring(got))
end)

test("NS.Print is reclaimed from AceConsole's :Print mixin (architecture-§2)", function()
  -- NewAddon(NS, …, "AceConsole-3.0") embeds :Print onto NS, clobbering the Util printer;
  -- core/LootHistory.lua reclaims it from NS.Util.print. Without that, /lh lines lose the tag.
  assertTrue(NS.Print == NS.Util.print,
    "NS.Print must be the secret-safe Util printer, not AceConsole's embedded mixin")
end)

test("Constants: source enum + order", function()
  assertEqual(NS.Constants.SourceType.KILL, "KILL")
  assertEqual(NS.Constants.SourceType.OTHER, "OTHER")
  assertEqual(NS.Constants.SourceType.BONUS_ROLL, "BONUS_ROLL")
  assertEqual(NS.Constants.SourceLabel.BONUS_ROLL, "Bonus Roll")
  assertEqual(NS.Constants.SourceType.REFUND, "REFUND")
  assertEqual(NS.Constants.SourceLabel.REFUND, "Refund")
  assertEqual(NS.Constants.Confidence.CERTAIN, "CERTAIN")
  assertEqual(#NS.Constants.SourceOrder, 16)   -- + DISENCHANT/MILLING/PROSPECTING + BONUS_ROLL + REFUND
  -- Every enum member now has a live capture path, so all are offered in the mute list: CRAFT (from
  -- "You create"), REFUND (from "You are refunded") and ROLL (from the "You won:" roll line) joined
  -- the wired sources (deconstruct abilities, AH from mail, BONUS_ROLL from the bonus-roll line).
  assertEqual(#NS.Constants.SOURCE_OPTIONS, 16)
  local muteable = {}
  for _, o in ipairs(NS.Constants.SOURCE_OPTIONS) do muteable[o.value] = true end
  assertTrue(muteable.ROLL); assertTrue(muteable.CRAFT); assertTrue(muteable.REFUND)
  assertTrue(muteable.KILL); assertTrue(muteable.AH); assertTrue(muteable.BONUS_ROLL)
  assertTrue(muteable.DISENCHANT); assertTrue(muteable.MILLING); assertTrue(muteable.PROSPECTING)
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

  test("Util: ParseSelfLoot tags a bonus-roll self-loot line as BONUS_ROLL", function()
    local one = string.format(T.mocks.LOOT_ITEM_BONUS_ROLL_SELF, LINK)
    local link, qty, src = NS.Util.ParseSelfLoot(one)
    assertEqual(link, LINK)
    assertEqual(qty, 1)
    assertEqual(src, "BONUS_ROLL")

    local many = string.format(T.mocks.LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE, LINK, 4)
    local link2, qty2, src2 = NS.Util.ParseSelfLoot(many)
    assertEqual(link2, LINK)
    assertEqual(qty2, 4)
    assertEqual(src2, "BONUS_ROLL")
  end)

  test("Util: ParseSelfLoot tags a created (crafted) self-loot line as CRAFT", function()
    local one = string.format(T.mocks.LOOT_ITEM_CREATED_SELF, LINK)
    local link, qty, src = NS.Util.ParseSelfLoot(one)
    assertEqual(link, LINK)
    assertEqual(qty, 1)
    assertEqual(src, "CRAFT")

    local many = string.format(T.mocks.LOOT_ITEM_CREATED_SELF_MULTIPLE, LINK, 2)
    local link2, qty2, src2 = NS.Util.ParseSelfLoot(many)
    assertEqual(link2, LINK)
    assertEqual(qty2, 2)   -- the "xN" is NOT swallowed by the singular pattern (quantity variants first)
    assertEqual(src2, "CRAFT")
  end)

  test("Util: ParseSelfLoot tags a refund self-loot line as REFUND", function()
    local one = string.format(T.mocks.LOOT_ITEM_REFUND, LINK)
    local link, qty, src = NS.Util.ParseSelfLoot(one)
    assertEqual(link, LINK)
    assertEqual(qty, 1)
    assertEqual(src, "REFUND")

    local many = string.format(T.mocks.LOOT_ITEM_REFUND_MULTIPLE, LINK, 6)
    local link2, qty2, src2 = NS.Util.ParseSelfLoot(many)
    assertEqual(link2, LINK)
    assertEqual(qty2, 6)
    assertEqual(src2, "REFUND")
  end)

  test("Util: ParseSelfLoot leaves the source tag nil for normal loot", function()
    local _, _, src = NS.Util.ParseSelfLoot(string.format(T.mocks.LOOT_ITEM_SELF, LINK))
    assertEqual(src, nil)
    local _, _, src2 = NS.Util.ParseSelfLoot(string.format(T.mocks.LOOT_ITEM_PUSHED_SELF, LINK))
    assertEqual(src2, nil)
  end)

  test("Util: ParseSelfLoot ignores another player's bonus roll", function()
    local msg = "Someone else receives bonus loot: " .. LINK
    assertEqual(NS.Util.ParseSelfLoot(msg), nil)
  end)

  test("Util: ParseRollWon matches the player's roll-won line, else nil", function()
    local won = string.format(T.mocks.LOOT_ROLL_YOU_WON, LINK)
    assertEqual(NS.Util.ParseRollWon(won), LINK)
    -- A normal receive line is not a roll-won line.
    assertEqual(NS.Util.ParseRollWon(string.format(T.mocks.LOOT_ITEM_SELF, LINK)), nil)
    -- Another player's win ("%s won: %s") must not match the self-only "You won:" pattern.
    assertEqual(NS.Util.ParseRollWon("Someone won: " .. LINK), nil)
  end)

  local CURR = "|cffffffff|Hcurrency:3008::|h[Valorstones]|h|r"

  test("Util: ParseSelfCurrency single currency line -> link, qty 1", function()
    local link, qty = NS.Util.ParseSelfCurrency(string.format(T.mocks.CURRENCY_GAINED, CURR))
    assertEqual(link, CURR)
    assertEqual(qty, 1)
  end)

  test("Util: ParseSelfCurrency multiple currency line -> link, qty N", function()
    local link, qty = NS.Util.ParseSelfCurrency(string.format(T.mocks.CURRENCY_GAINED_MULTIPLE, CURR, 45))
    assertEqual(link, CURR)
    assertEqual(qty, 45)
  end)

  test("Util: ParseSelfCurrency bonus + overflow variants -> link, qty", function()
    local l1, q1 = NS.Util.ParseSelfCurrency(string.format(T.mocks.CURRENCY_GAINED_MULTIPLE_BONUS, CURR, 10))
    assertEqual(l1, CURR); assertEqual(q1, 10)
    local l2, q2 = NS.Util.ParseSelfCurrency(
      string.format(T.mocks.CURRENCY_GAINED_MULTIPLE_OVERFLOW, CURR, 5, "Valorstones"))
    assertEqual(l2, CURR); assertEqual(q2, 5)
  end)

  test("Util: ParseSelfCurrency ignores item loot and other players", function()
    assertEqual(NS.Util.ParseSelfCurrency(string.format(T.mocks.LOOT_ITEM_SELF, LINK)), nil)
    assertEqual(NS.Util.ParseSelfCurrency("Someone receives currency: " .. CURR), nil)
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

test("Util: RecordValue = max(pickedAuction, vendorPrice), else whichever exists", function()
  NS.db.global.settings.auction = { enabled = true, priority = { "tsm:dbmarket" } }
  assertEqual(NS.Util.RecordValue({ vendorPrice = 10, auctionPrice = { tsm = { dbmarket = 500 } } }), 500)
  assertEqual(NS.Util.RecordValue({ vendorPrice = 800, auctionPrice = { tsm = { dbmarket = 500 } } }), 800) -- vendor higher
  assertEqual(NS.Util.RecordValue({ vendorPrice = 10 }), 10)                       -- no auction
  assertEqual(NS.Util.RecordValue({ auctionPrice = { tsm = { dbmarket = 500 } } }), 500) -- no vendor
  assertEqual(NS.Util.RecordValue({}), nil)
  NS.db.global.settings.auction = nil
end)
