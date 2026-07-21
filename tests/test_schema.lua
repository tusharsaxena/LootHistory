local T = _G.LH_TEST
local NS, test, assertTrue, assertEqual = T.NS, T.test, T.assertTrue, T.assertEqual

-- The "Debug console" checkbox is a SESSION-ONLY schema row: it renders in the panel like any
-- setting, but its value is backed by the debug console window's visibility (get/set → NS.DebugLog),
-- never written to NS.db.global. These tests pin that mechanism (independent of real frame state by
-- stubbing NS.DebugLog's Show/Hide/IsShown).

local function withDebugLogSpies(fn)
  local D = NS.DebugLog
  local realShow, realHide, realIsShown = D.Show, D.Hide, D.IsShown
  local calls, shown = { show = 0, hide = 0 }, false
  D.Show = function() calls.show = calls.show + 1; shown = true end
  D.Hide = function() calls.hide = calls.hide + 1; shown = false end
  D.IsShown = function() return shown end
  local ok, err = pcall(fn, calls, function() return shown end, function(v) shown = v end)
  D.Show, D.Hide, D.IsShown = realShow, realHide, realIsShown
  if not ok then error(err) end
end

test("Schema: debugConsole row is session-only, in Master Controls", function()
  local row = NS.Schema:FindRow("state.debugConsole")
  assertTrue(row ~= nil, "state.debugConsole row missing")
  assertTrue(row.sessionOnly == true, "row not marked sessionOnly")
  assertEqual(row.group, "Master Controls")
  assertEqual(row.label, "Debug console")
end)

test("Schema: setting debugConsole toggles the window, never writes db.global", function()
  NS.db.global.state = nil
  withDebugLogSpies(function(calls)
    NS.Schema:Set("state.debugConsole", true)
    assertEqual(calls.show, 1, "Set(true) should Show the console window")
    assertEqual(calls.hide, 0)
    NS.Schema:Set("state.debugConsole", false)
    assertEqual(calls.hide, 1, "Set(false) should Hide the console window")
  end)
  assertTrue(NS.db.global.state == nil, "session-only row must not persist to db.global")
end)

test("Schema: getting debugConsole reflects the window visibility", function()
  withDebugLogSpies(function(_, _, setShown)
    setShown(true)
    assertEqual(NS.Schema:Get("state.debugConsole"), true)
    setShown(false)
    assertEqual(NS.Schema:Get("state.debugConsole"), false)
  end)
end)

test("Schema: a normal (persisted) row still writes db.global", function()
  NS.Schema:Set("settings.enabled", false)
  assertEqual(NS.db.global.settings.enabled, false, "normal row must persist to db.global")
  assertEqual(NS.Schema:Get("settings.enabled"), false)
  NS.Schema:Set("settings.enabled", true) -- restore default
end)

test("Schema: auction rows exist with the AH Price group and defaults", function()
  local NS2 = NS
  local row = NS2.Schema:FindRow("settings.auction.enabled")
  assertTrue(row ~= nil, "settings.auction.enabled row missing")
  assertEqual(row.group, "AH Price")
  assertEqual(NS2.Schema:Default("settings.auction.enabled"), true)
end)

test("Schema: auction capture is a MultiCheck row; Rev-1 provider/priority rows are gone", function()
  local NS2 = NS
  local row = NS2.Schema:FindRow("settings.auction.capture")
  assertTrue(row ~= nil, "settings.auction.capture row missing")
  assertEqual(row.group, "AH Price")
  assertEqual(row.widget, "MultiCheck")
  assertEqual(NS2.Schema:Default("settings.auction.capture")["tsm:dbmarket"], true)

  assertTrue(NS2.Schema:FindRow("settings.auction.tsmSource") == nil, "tsmSource row should be removed")
  assertTrue(NS2.Schema:FindRow("settings.auction.auctionator") == nil, "auctionator row should be removed")
  assertTrue(NS2.Schema:FindRow("settings.auction.priorityAuctionator") == nil, "priorityAuctionator row should be removed")
  assertTrue(NS2.Schema:FindRow("settings.auction.tsm") == nil, "tsm row should be removed")
  assertTrue(NS2.Schema:FindRow("settings.auction.priorityTSM") == nil, "priorityTSM row should be removed")
  assertTrue(NS2.Schema:FindRow("settings.auction.oribos") == nil, "oribos row should be removed")
  assertTrue(NS2.Schema:FindRow("settings.auction.priorityOribos") == nil, "priorityOribos row should be removed")
end)

test("Schema: recordCurrency row exists, defaults true, settable", function()
  assertEqual(NS.Schema:Default("settings.recordCurrency"), true)
  assertEqual(NS.defaults.global.settings.recordCurrency, true)
  assertTrue(NS.Schema:Set("settings.recordCurrency", false))
  assertEqual(NS.Schema:Get("settings.recordCurrency"), false)
  NS.Schema:Set("settings.recordCurrency", true)   -- restore default
end)

test("Constants: CURRENCY_TYPE is \"Currency\"", function()
  assertEqual(NS.Constants.CURRENCY_TYPE, "Currency")
end)
