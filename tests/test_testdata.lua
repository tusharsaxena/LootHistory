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

-- Timeline ledger Phase 7: the sample's holder moves are an OUT on the sender and an IN on the
-- receiver under the action's reason, sharing a pairId -- never an inter-holder MOVE.
test("TestData: the History sample writes holder moves as a loss and a gain", function()
  local L, U = NS.Ledger, NS.Util
  local byPair, reasons = {}, {}
  for _, r in ipairs(NS.BrowserTable:BuildTestData()) do
    if U.RowDir(r) == "MOVE" and r.from and r.to then
      assertEqual(L.LocationHolder(r.from), L.LocationHolder(r.to), "an inter-holder MOVE in the sample")
    end
    if L.HOLDER_MOVE_REASON[r.source] then
      assertTrue(r.pairId ~= nil, r.source .. " row has no pairId")
      byPair[r.pairId] = byPair[r.pairId] or {}
      byPair[r.pairId][U.RowDir(r)] = r
    end
  end
  for id, p in pairs(byPair) do
    assertTrue(p.OUT and p.IN, id .. " is not an OUT + IN pair")
    assertEqual(p.OUT.source, p.IN.source); assertEqual(p.OUT.quantity, p.IN.quantity)
    assertTrue(U.RowHolder(p.OUT) ~= U.RowHolder(p.IN), id .. " stays on one holder")
    assertEqual(L.LocationHolder(p.OUT.from), U.RowHolder(p.OUT))
    assertEqual(L.LocationHolder(p.IN.to), U.RowHolder(p.IN))
    if p.OUT.source == "WARBAND_DEPOSIT" then assertEqual(U.RowHolder(p.IN), WARBAND) end
    if p.OUT.source == "WARBAND_WITHDRAW" then assertEqual(U.RowHolder(p.OUT), WARBAND) end
    reasons[p.OUT.source] = true
  end
  for k in pairs(L.HOLDER_MOVE_REASON) do assertTrue(reasons[k], "no " .. k .. " pair in the sample") end
end)

test("TestData: the sample rollup books a holder move's loss and gain on each holder", function()
  local now = os.time({ year = 2026, month = 10, day = 6, hour = 15 })
  local records = NS.BrowserTable:BuildTestData()
  local _, daily = NS.TestData.Build(records, now)
  local checked = 0
  for _, r in ipairs(records) do
    local h, key = NS.Util.RowHolder(r), NS.Ledger.RowThingKey(r)
    local cellv = daily[NS.Ledger.DayKey(r.ts)]
    cellv = cellv and cellv[h] and cellv[h][key]
    if NS.Ledger.HOLDER_MOVE_REASON[r.source] and cellv then
      local side = (NS.Util.RowDir(r) == "OUT") and cellv.o or cellv.i
      assertTrue((side or 0) >= r.quantity, r.source .. " " .. NS.Util.RowDir(r) .. " not in " .. h .. "'s tally")
      checked = checked + 1
    end
  end
  assertTrue(checked >= 1, "no holder-move row lands on a held series")
end)

-- Test mode opens the Timeline on a sample item and keeps the user's own pick out of the saved view.
local function withTimeline(fn)
  withStores(function()
    local p, TL = NS.db.profile, NS.Timeline
    local views = NS.Util.DeepCopy(p.savedViews)
    local thing, testThing = TL.thing, TL.testThing
    local ok, err = pcall(function()
      NS.Browser:Show(); NS.Browser:SelectTab("Timeline"); TL:Layout(640, 320)
      fn(TL)
    end)
    if NS.BrowserTable.testMode then NS.BrowserTable:SetTestMode(false) end
    NS.Browser:SelectTab("History")
    p.savedViews = views
    TL.thing, TL.testThing = thing, testThing
    if not ok then error(err, 0) end
  end)
end

test("TestData: the default Timeline thing is Everlight Crystal, nil without a sample", function()
  withStores(function()
    assertEqual(NS.TestData.DefaultTimelineThing(), nil, "a default with no sample")
    NS.BrowserTable:SetTestMode(true)
    local d = NS.TestData.DefaultTimelineThing()
    assertEqual(NS.TestData.Describe(d).name, "Everlight Crystal")
  end)
end)

test("Test mode: the Timeline opens on the default sample item with lines drawn, saved view untouched", function()
  withTimeline(function(TL)
    TL.thing = nil
    local before = NS.Browser:ViewField("timelineThing", "Timeline")
    NS.BrowserTable:SetTestMode(true)
    TL:Refresh()
    assertEqual(TL:Thing(), NS.TestData.DefaultTimelineThing())
    assertTrue(#TL.model.series >= 2, "no lines drawn for the default item")
    assertTrue(TL.title:GetText():find("Everlight Crystal", 1, true) ~= nil, "title: " .. tostring(TL.title:GetText()))
    assertEqual(NS.Browser:ViewField("timelineThing", "Timeline"), before, "the saved view changed")
  end)
end)

test("Test mode: a pick made in test mode survives refreshes and never reaches the saved view", function()
  withTimeline(function(TL)
    TL:SetThing("c:3008", true)   -- the user's own, real pick before test mode
    local before = NS.Browser:ViewField("timelineThing", "Timeline")
    NS.BrowserTable:SetTestMode(true)
    TL:SetThing("g")
    TL:Refresh(); TL:Refresh()
    assertEqual(TL:Thing(), "g", "the pick was reset by a refresh")
    assertEqual(NS.Browser:ViewField("timelineThing", "Timeline"), before, "the saved view changed")
    NS.BrowserTable:SetTestMode(false)
    assertEqual(TL:Thing(), "c:3008", "the previous selection did not come back")
  end)
end)

test("Test mode: a pick of a thing the sample lacks falls back to the default", function()
  withTimeline(function(TL)
    TL:SetThing("i:999999", true)
    NS.BrowserTable:SetTestMode(true)
    assertEqual(TL:Thing(), NS.TestData.DefaultTimelineThing())
    NS.BrowserTable:SetTestMode(false)
    assertEqual(TL:Thing(), "i:999999")
  end)
end)

-- ── Characterization (LH-13): the seeded build and the default-thing picker ──────────────────
-- A canonical dump of both stores (keys sorted), folded to a checksum: the seeded RNG must meet the
-- series in the same order and draw the same numbers after any refactor of walk. The build reads the
-- wall clock (the History sample's `time()`) and the local zone (`date`, `time{...}`), so the pin
-- runs on a frozen UTC clock: the same bytes on every machine, in every zone, on every day.
local function canon(v, out)
  if type(v) ~= "table" then out[#out + 1] = tostring(v); return end
  local ks = {}
  for k in pairs(v) do ks[#ks + 1] = k end
  table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
  out[#out + 1] = "{"
  for _, k in ipairs(ks) do out[#out + 1] = tostring(k) .. "="; canon(v[k], out) end
  out[#out + 1] = "}"
end

local function checksum(s)
  local h = 0
  for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483647 end
  return h
end

-- Days since 1970-01-01 for a proleptic Gregorian date (Hinnant's days_from_civil); `d` may run
-- past either end of its month, as os.time's normalization allows.
local function daysFromCivil(y, m, d)
  y = y + math.floor((m - 1) / 12); m = (m - 1) % 12 + 1
  if m <= 2 then y = y - 1 end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5)
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468 + (d - 1)
end

local function withUtcClock(now, fn)
  local m = T.mocks   -- the loader's chunk environment reads the mock table before _G
  local savedTime, savedDate = m.time, m.date
  m.time = function(t)
    if not t then return now end
    return daysFromCivil(t.year, t.month, t.day) * 86400 + (t.hour or 12) * 3600 + (t.min or 0) * 60 + (t.sec or 0)
  end
  m.date = function(fmt, t)
    fmt = fmt or "%c"
    if fmt:sub(1, 1) ~= "!" then fmt = "!" .. fmt end
    return os.date(fmt, t or now)
  end
  local ok, err = pcall(fn)
  m.time, m.date = savedTime, savedDate
  if not ok then error(err, 0) end
end

test("TestData: the seeded sample stores are byte-identical to the pinned build", function()
  local now = daysFromCivil(2026, 10, 6) * 86400 + 15 * 3600
  withUtcClock(now, function()
    local holdings, daily = NS.TestData.Build(NS.BrowserTable:BuildTestData(), now)
    local h, d = {}, {}
    canon(holdings, h); canon(daily, d)
    local hs, ds = table.concat(h, ","), table.concat(d, ",")
    assertEqual(#hs .. ":" .. checksum(hs), "3160:2043831815", "holdings")
    assertEqual(#ds .. ":" .. checksum(ds), "117029:2104532542", "daily")
  end)
end)

test("TestData: with no Everlight Crystal the default thing is the item on most days, ties to the lowest key", function()
  local saved = NS.State.testDaily
  local ok, err = pcall(function()
    -- c:/g keys never count; a key seen twice in a day (two holders) counts that day once.
    NS.State.testDaily = {
      ["2026-10-01"] = { A = { ["i:5"] = {}, ["i:9"] = {}, ["c:1"] = {}, g = {} }, B = { ["i:5"] = {} } },
      ["2026-10-02"] = { A = { ["i:5"] = {}, ["c:1"] = {} }, B = { ["i:3"] = {} } },
      ["2026-10-03"] = { B = { ["i:3"] = {}, ["c:1"] = {}, g = {} } },
    }
    assertEqual(NS.TestData.DefaultTimelineThing(), "i:3", "i:3 and i:5 tie on two days")
    NS.State.testDaily["2026-10-03"].A = { ["i:5"] = {} }
    assertEqual(NS.TestData.DefaultTimelineThing(), "i:5", "i:5 now leads on three days")
    NS.State.testDaily = { ["2026-10-01"] = { A = { ["c:1"] = {}, g = {} } } }
    assertEqual(NS.TestData.DefaultTimelineThing(), nil, "no item at all")
    -- Everlight Crystal wins on any one day, over an item on more days.
    local names, everlight = NS.BrowserTable.TestSample.itemNames
    for i, n in ipairs(names) do if n == "Everlight Crystal" then everlight = "i:" .. (100000 + i) end end
    NS.State.testDaily = {
      ["2026-10-01"] = { A = { ["i:5"] = {} } }, ["2026-10-02"] = { A = { ["i:5"] = {}, [everlight] = {} } },
    }
    assertEqual(NS.TestData.DefaultTimelineThing(), everlight)
  end)
  NS.State.testDaily = saved
  if not ok then error(err, 0) end
end)
