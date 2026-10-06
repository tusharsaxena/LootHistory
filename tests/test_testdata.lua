local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- Test mode's ledger half (timeline-ledger P6 Task 1, smoke TM-1): the Holdings and Timeline tabs
-- read session-only sample stores while test mode is on, and the real db.global stores otherwise.
-- NS.TestData builds them from the History sample's universe; every read path resolves through
-- NS.Holdings:ActiveStore / NS.Rollup:ActiveStore, and no write path ever sees them.

local WARBAND = "§warband"

local function deepEqual(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

--- Run `fn` with the real ledger stores emptied (the fixture's "real" data) and test mode off at
--- both ends; the stores, the rollup's key index and the window are put back however it ends.
local function withStores(fn)
  local g, BT, s = NS.db.global, NS.BrowserTable, NS.db.profile.settings
  local holdings, daily, keys, vis = g.holdings, g.daily, NS.Rollup._keys, s.visibility
  local savedGroup, savedFilter = BT.groupBy, BT.filter
  g.holdings, g.daily, NS.Rollup._keys, s.visibility = {}, {}, nil, "always"
  local ok, err = pcall(fn)
  if BT.testMode then BT:SetTestMode(false) end
  NS.Browser:Hide()
  g.holdings, g.daily, NS.Rollup._keys, s.visibility = holdings, daily, keys, vis
  BT.groupBy, BT.filter = savedGroup, savedFilter
  if not ok then error(err, 0) end
end

local function holderSet(lines)
  local set, n = {}, 0
  for _, l in ipairs(lines) do
    if l.kind == "holder" and not set[l.holder] then set[l.holder] = true; n = n + 1 end
  end
  return set, n
end

local function allExpanded()
  local open = {}
  for _, t in ipairs(NS.Holdings:Search({})) do open[t.key] = true end
  return open
end

local function timelineModel(thing)
  local p = NS.Timeline:Params({})
  p.thing, p.from, p.range = thing, nil, "all"
  return NS.TimelineModel.Build(p)
end

test("TestData: the sample holdings and daily stores build deterministically", function()
  local records = NS.BrowserTable:BuildTestData()
  local now = os.time({ year = 2026, month = 10, day = 6, hour = 15 })
  local h1, d1 = NS.TestData.Build(records, now)
  local h2, d2 = NS.TestData.Build(records, now)
  assertTrue(deepEqual(h1, h2), "two holdings builds differ")
  assertTrue(deepEqual(d1, d2), "two daily builds differ")
  -- Same universe as the History sample: every character holder plays in the sample rows.
  local chars = {}
  for _, r in ipairs(records) do chars[r.char] = true end
  local n = 0
  for h in pairs(h1) do
    n = n + 1
    if h ~= WARBAND then assertTrue(chars[h], h .. " is not a character of the History sample") end
  end
  assertTrue(n >= 5 and h1[WARBAND] ~= nil, "want at least four characters and the Warband")
end)

test("TestData: a day's close is its flows applied to the day before", function()
  local now = os.time({ year = 2026, month = 10, day = 6, hour = 15 })
  local holdings, daily = NS.TestData.Build(NS.BrowserTable:BuildTestData(), now)
  local days = NS.TimelineModel.SortedDays(daily)
  assertTrue(#days >= 100, "the daily series covers " .. #days .. " days")
  -- Every holder's gold close today is what the holdings store says it holds now.
  local today = NS.Ledger.DayKey(now)
  for h, e in pairs(holdings) do
    local c = NS.TimelineModel.CloseBefore(daily, days, h, "g", NS.TimelineModel.NextDay(today))
    assertEqual(c, e.money, h .. ": today's gold close is not the held gold")
  end
  -- And between days, close(d) = close(d-1) + gained - lost, never below zero.
  local checked = 0
  for i = 2, #days do
    for h, things in pairs(daily[days[i]]) do
      for key, cell in pairs(things) do
        local prev = NS.TimelineModel.CloseBefore(daily, days, h, key, days[i])
        if prev and cell.c then
          assertEqual(cell.c, prev + (cell.i or 0) - (cell.o or 0), h .. " " .. key .. " on " .. days[i])
          assertTrue(cell.c >= 0, "a negative close")
          checked = checked + 1
        end
      end
    end
  end
  assertTrue(checked > 100, "only " .. checked .. " cells checked")
end)

test("Test mode: Holdings and Timeline show the sample, and the real stores come back after", function()
  withStores(function()
    local g = NS.db.global
    local realH, realD = NS.Util.DeepCopy(g.holdings), NS.Util.DeepCopy(g.daily)

    NS.BrowserTable:SetTestMode(true)
    assertTrue(NS.State.testHoldings ~= nil and NS.State.testDaily ~= nil, "test mode published no ledger sample")
    local set, n = holderSet(NS.HoldingsTab.BuildModel({}, allExpanded(), "name"))
    assertTrue(n >= 5, "Holdings shows " .. n .. " holders")
    assertTrue(set[WARBAND], "Holdings shows no Warband")
    for _, thing in ipairs({ "g", "i:100001" }) do
      local m, lines = timelineModel(thing), 0
      for _, sr in ipairs(m.series) do
        if sr.holder ~= NS.TimelineModel.TOTAL then
          lines = lines + 1
          assertTrue(#sr.points >= 100, thing .. ": " .. sr.holder .. " has " .. #sr.points .. " points")
        end
      end
      assertTrue(lines >= 2, thing .. ": " .. lines .. " holder line(s)")
    end
    assertTrue(next(NS.Rollup:Keys()) ~= nil, "the Timeline picker offers no sample thing")
    assertTrue(deepEqual(g.holdings, realH), "test mode wrote db.global.holdings")
    assertTrue(deepEqual(g.daily, realD), "test mode wrote db.global.daily")

    NS.BrowserTable:SetTestMode(false)
    assertTrue(NS.State.testHoldings == nil and NS.State.testDaily == nil, "the sample outlived test mode")
    assertEqual(#NS.HoldingsTab.BuildModel({}, {}, "name"), 0, "Holdings still shows the sample")
    local m = timelineModel("g")
    assertEqual(#m.series, 1, "the Timeline still draws holder lines")   -- only the empty Total
    assertTrue(next(NS.Rollup:Keys()) == nil, "the picker still offers the sample")
    assertTrue(deepEqual(g.holdings, realH), "test mode off wrote db.global.holdings")
    assertTrue(deepEqual(g.daily, realD), "test mode off wrote db.global.daily")
  end)
end)

test("Test mode: ledger writes go to the real stores, never the sample", function()
  withStores(function()
    local g = NS.db.global
    NS.BrowserTable:SetTestMode(true)
    local sampleH = NS.Util.DeepCopy(NS.State.testHoldings)
    local sampleD = NS.Util.DeepCopy(NS.State.testDaily)
    local ts = os.time()
    NS.Holdings:ApplyMoney("Mage-Ravencrest", 12345, ts)
    NS.Holdings:ApplyContainer("Mage-Ravencrest", "bags", { [100001] = 3 }, {}, ts)
    assertEqual(g.holdings["Mage-Ravencrest"].money, 12345, "the write missed the real store")
    assertTrue(g.daily[NS.Ledger.DayKey(ts)] ~= nil, "the rollup close missed the real store")
    assertTrue(deepEqual(NS.State.testHoldings, sampleH), "a holdings write reached the sample")
    assertTrue(deepEqual(NS.State.testDaily, sampleD), "a rollup write reached the sample")
  end)
end)
