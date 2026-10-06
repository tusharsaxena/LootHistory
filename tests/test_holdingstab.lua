local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- The Holdings tab (timeline-ledger spec §8.2). BuildModel carries every decision and is pure, so
-- most of this suite never touches a frame; the last case opens the window to pin that the pooled
-- rows are recycled rather than reallocated on refresh.

local function seed()
  NS.db.global.holdings = {}
  NS.Holdings:ApplyContainer("A-Realm", "bags", { [7] = 2 }, { [7] = "|Hitem:7|h[Apple]|h" }, 100)
  NS.Holdings:ApplyContainer("B-Realm", "bank", { [7] = 9 }, {}, 50)
  NS.Holdings:ApplyMoney("A-Realm", 10000, 100)
end

test("HoldingsTab: model lists things collapsed by default", function()
  seed()
  local lines = NS.HoldingsTab.BuildModel({}, {}, "name")
  local things = 0
  for _, l in ipairs(lines) do if l.kind == "thing" then things = things + 1 else error("holder line while collapsed") end end
  assertEqual(things, 2)   -- Apple + Gold
end)

test("HoldingsTab: expanding a thing adds one line per holder", function()
  seed()
  local lines = NS.HoldingsTab.BuildModel({}, { ["i:7"] = true }, "total")
  assertEqual(lines[1].key, "g")            -- total sort: gold 10000 first
  local holders = 0
  for _, l in ipairs(lines) do if l.kind == "holder" then holders = holders + 1 end end
  assertEqual(holders, 2)
end)

test("HoldingsTab: character filter narrows holders", function()
  seed()
  local lines = NS.HoldingsTab.BuildModel({ char = { ["B-Realm"] = true } }, { ["i:7"] = true }, "name")
  for _, l in ipairs(lines) do
    if l.kind == "holder" then assertEqual(l.holder, "B-Realm") end
    if l.kind == "thing" then assertTrue(l.key ~= "g") end   -- B has no gold
  end
end)

test("HoldingsTab: container and age formatting", function()
  assertEqual(NS.HoldingsTab.FormatContainers({ tabs = 100, bags = 12, bank = 40 }), "Bags 12 · Bank 40 · Warband 100")
  assertEqual(NS.HoldingsTab.FormatAge(1000, 1030), "now")
  assertEqual(NS.HoldingsTab.FormatAge(1000, 1000 + 3 * 3600), "3 h")
  assertEqual(NS.HoldingsTab.FormatAge(1000, 1000 + 2 * 86400), "2 d")
end)

test("HoldingsTab: tab is registered after History and Insights", function()
  local names = NS.Browser:Tabs()
  assertEqual(names[#names], "Holdings")
end)

test("HoldingsTab: attach builds rows and recycles them on refresh", function()
  -- Adapted from the plan's snippet: the window is closed again on every path, because a browser
  -- left on screen keeps repainting under the panel suites that run next and skews their counts.
  -- The pool's free/active split is also pinned, since an equal row count alone passes a refresh
  -- that allocates a fresh frame per line every time. The window opens scoped to the logged-in
  -- character (Mock-Realm), who holds nothing in this seed, so the scope is widened for the case
  -- and put back after.
  seed()
  local savedChar = NS.Browser:CurrentFilter().char
  local ok, err = pcall(function()
    NS.Browser:Show(); NS.Browser:SetCharSet(nil); NS.Browser:SelectTab("Holdings")
    local first = NS.HoldingsTab:VisibleRowCount()
    local _, active = NS.Pool.Counts(NS.HoldingsTab.rows)
    NS.HoldingsTab:Refresh()
    assertEqual(NS.HoldingsTab:VisibleRowCount(), first)
    assertTrue(first >= 2)
    local free2, active2 = NS.Pool.Counts(NS.HoldingsTab.rows)
    assertEqual(active2, active); assertEqual(free2, 0, "a refresh re-acquired every released row")
  end)
  NS.Browser:SetCharSet(savedChar); NS.Browser:SelectTab("History"); NS.Browser:Hide()
  if not ok then error(err, 0) end
end)

test("HoldingsTab: HOLDINGS_CHANGED does not rebuild the pane once the window is closed", function()
  -- red under: the handler gating on pane:IsShown() -- closing the browser with Holdings as the
  -- last tab leaves the pane shown inside a hidden window, and every Reconciler flush then ran a
  -- full off-screen BuildModel (AH-price lookups included). The kit's IsVisible does not walk
  -- parents, so the pane is told what the client would answer: shown, but not visible.
  seed()
  local savedChar = NS.Browser:CurrentFilter().char
  local realRefresh, calls = NS.HoldingsTab.Refresh, 0
  local pane, realVisible
  local ok, err = pcall(function()
    NS.Browser:Show(); NS.Browser:SetCharSet(nil); NS.Browser:SelectTab("Holdings")
    pane = NS.HoldingsTab.pane
    assertTrue(pane ~= nil, "the Holdings pane was not attached")
    NS.HoldingsTab.Refresh = function(self, ...) calls = calls + 1; return realRefresh(self, ...) end
    NS.bus:SendMessage(NS.MSG.HOLDINGS_CHANGED, "A-Realm")
    assertEqual(calls, 1, "the visible pane did not repaint on HOLDINGS_CHANGED")
    NS.Browser:Hide()
    realVisible = pane.IsVisible
    pane.IsVisible = function() return false end
    assertTrue(pane:IsShown(), "the case needs the pane still shown inside the hidden window")
    NS.bus:SendMessage(NS.MSG.HOLDINGS_CHANGED, "A-Realm")
    assertEqual(calls, 1, "HOLDINGS_CHANGED rebuilt the Holdings pane while the window was closed")
  end)
  NS.HoldingsTab.Refresh = realRefresh
  if pane and realVisible then pane.IsVisible = realVisible end
  NS.Browser:Show(); NS.Browser:SetCharSet(savedChar); NS.Browser:SelectTab("History"); NS.Browser:Hide()
  if not ok then error(err, 0) end
end)

-- ---------------------------------------------------------------------------
-- Row actions and "Forget this character" (timeline ledger P3, spec §8.2)
-- ---------------------------------------------------------------------------
-- Adapted from the plan's snippets: each store-touching case runs through `keep`, which puts the
-- holdings and daily stores and the Rollup key index back as it found them (addenda, Global); the
-- chunk has no global `time`, so the seeds read os.time().

local assertFalse = T.assertFalse

local function keep(fn)
  local g = NS.db.global
  local holdings, daily, keys = g.holdings, g.daily, NS.Rollup and NS.Rollup._keys
  local ok, err = pcall(fn)
  g.holdings, g.daily = holdings, daily
  if NS.Rollup then NS.Rollup._keys = keys end
  if not ok then error(err, 0) end
end

local function captureChanged(fn)
  local got, orig = {}, NS.bus.SendMessage
  NS.bus.SendMessage = function(self, msg, a, ...)
    if msg == NS.MSG.HOLDINGS_CHANGED then got[#got + 1] = a end
    return orig(self, msg, a, ...)
  end
  local ok, err = pcall(fn)
  NS.bus.SendMessage = orig
  if not ok then error(err, 0) end
  return got
end

local function labels(items)
  local out = {}
  for _, it in ipairs(items) do out[(it.label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))] = it end
  return out
end

test("Holdings row actions: a thing line offers Show in Timeline", function()
  local a = labels(NS.HoldingsTab.RowActions({ kind = "thing", key = "c:3008" }))
  assertTrue(a["Show in Timeline"] ~= nil and a["Show in Timeline"].enabled)
  assertEqual(a["Forget this character"], nil, "a thing line is not a character")
end)

test("Holdings row actions: Forget is offered for an alt, never for the warband or the logged-in character", function()
  local alt = labels(NS.HoldingsTab.RowActions({ kind = "holder", key = "g", holder = "Alt-Realm" }))
  assertTrue(alt["Forget this character"].enabled)
  local wb = labels(NS.HoldingsTab.RowActions({ kind = "holder", key = "g", holder = NS.Constants.WARBAND_HOLDER }))
  assertFalse(wb["Forget this character"].enabled)
  local me = labels(NS.HoldingsTab.RowActions({ kind = "holder", key = "g", holder = NS.Util.PlayerKey() }))
  assertFalse(me["Forget this character"].enabled)
end)

test("Forget this character: drops holdings and rollup cells, keeps history rows, announces once", function()
  keep(function()
    NS.db.global.holdings, NS.db.global.daily = {}, {}
    local t = os.time()
    NS.Holdings:ApplyMoney("Alt-Realm", 100, t)
    NS.Holdings:ApplyMoney("Keep-Realm", 5, t)
    -- A rollup cell for the alt whether or not the write hook is live in this harness.
    NS.Ledger.RollupClose(NS.db.global.daily, NS.Ledger.DayKey(t), "Alt-Realm", "g", 100)
    local hist = #NS.db.global.history
    local got = captureChanged(function() assertTrue(NS.Reconciler:ForgetHolder("Alt-Realm")) end)
    assertEqual(NS.Holdings:Get("Alt-Realm"), nil)
    for _, holders in pairs(NS.db.global.daily) do assertEqual(holders["Alt-Realm"], nil) end
    assertTrue(NS.Holdings:Get("Keep-Realm") ~= nil)
    assertEqual(#NS.db.global.history, hist)
    assertEqual(#got, 1); assertEqual(got[1], "Alt-Realm")
  end)
end)

test("Forget this character: a holder with nothing stored is a no-op and announces nothing", function()
  keep(function()
    NS.db.global.holdings, NS.db.global.daily = {}, {}
    local ok
    local got = captureChanged(function() ok = NS.Reconciler:ForgetHolder("Nobody-Realm") end)
    assertFalse(ok); assertEqual(#got, 0)
  end)
end)

test("Forget this character: refuses the logged-in character and the warband", function()
  local ok, why = NS.Reconciler:ForgetHolder(NS.Util.PlayerKey())
  assertFalse(ok); assertEqual(why, "current")
  ok, why = NS.Reconciler:ForgetHolder(NS.Constants.WARBAND_HOLDER)
  assertFalse(ok); assertEqual(why, "warband")
end)

test("Forget popup: registered, and its accept forgets the holder it carries", function()
  keep(function()
    local d = T.mocks.StaticPopupDialogs["KA0S_LOOTHISTORY_FORGET_HOLDER"]
    assertTrue(d ~= nil and d.text:find("%s", 1, true) ~= nil)
    NS.db.global.holdings, NS.db.global.daily = {}, {}
    NS.Holdings:ApplyMoney("Alt-Realm", 1, os.time())
    d.OnAccept(nil, { holder = "Alt-Realm" })
    assertEqual(NS.Holdings:Get("Alt-Realm"), nil)
  end)
end)
