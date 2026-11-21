local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- Test mode's ledger half (timeline-ledger P6 Task 1, smoke TM-1): the Holdings and Timeline tabs
-- read session-only sample stores while test mode is on, and the real db.global stores otherwise.
-- NS.TestData builds them from the History sample's universe; every read path resolves through
-- NS.Holdings:ActiveStore / NS.Rollup:ActiveStore, and no write path ever sees them.

local WARBAND = "§warband"
-- The kit profile this run is (tests/run.lua's T.forever): every per-client seed is read for it.
local CLIENT = T.forever and "forever" or "retail"

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
  -- WoW Forever has no warband bank (R1), and its sample marks no account currency, so its account
  -- holder holds nothing and is not in the sample (modules/TestData.lua).
  if T.forever then
    assertTrue(n >= 4 and h1[WARBAND] == nil, "want at least four characters and no account holder")
  else
    assertTrue(n >= 5 and h1[WARBAND] ~= nil, "want at least four characters and the Warband")
  end
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
    -- WoW Forever's sample has no account holder (no warband bank, no account currency in it).
    assertTrue(n >= (T.forever and 4 or 5), "Holdings shows " .. n .. " holders")
    assertEqual(set[WARBAND] == true, not T.forever, "Holdings shows the Warband on Retail only")
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
    NS.Holdings:ApplyMoney("Mockflame-Mockrealm", 12345, ts)
    NS.Holdings:ApplyContainer("Mockflame-Mockrealm", "bags", { [100001] = 3 }, {}, ts)
    assertEqual(g.holdings["Mockflame-Mockrealm"].money, 12345, "the write missed the real store")
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
  -- A reason this client lacks (the warband directions on WoW Forever, R1) makes no pair at all.
  local absent = NS.Constants.SOURCE_ABSENT
  for k in pairs(L.HOLDER_MOVE_REASON) do
    if absent[k] then assertEqual(reasons[k], nil, k .. " is absent, yet the sample pairs it")
    else assertTrue(reasons[k], "no " .. k .. " pair in the sample") end
  end
end)

test("TestData: the sample rollup books a holder move's loss and gain on each holder", function()
  -- The rollup reads the clock the sample was stamped with: BuildTestData dates its rows from
  -- time(), so a fixed date here drifted out of the sample's window as the calendar moved on.
  local records = NS.BrowserTable:BuildTestData()
  local now = T.mocks.time()   -- the clock the addon chunks resolve (the kit binds os.time)
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

-- The item the Timeline opens on, per client: the fifth of each client's own item list.
local DEFAULT_ITEM = ({ retail = "Everlight Crystal", forever = "Arcane Crystal" })[CLIENT]

test("TestData: the default Timeline thing is the client's default item, nil without a sample", function()
  withStores(function()
    assertEqual(NS.TestData.DefaultTimelineThing(), nil, "a default with no sample")
    NS.BrowserTable:SetTestMode(true)
    local d = NS.TestData.DefaultTimelineThing()
    -- red under: one Retail item list on both clients (Everlight Crystal on WoW Forever).
    assertEqual(NS.TestData.Describe(d).name, DEFAULT_ITEM)
    assertEqual(NS.BrowserTable.TestSample.defaultItem, DEFAULT_ITEM, "the sample names its default")
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
    assertTrue(TL.title:GetText():find(DEFAULT_ITEM, 1, true) ~= nil, "title: " .. tostring(TL.title:GetText()))
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
    -- Re-pinned by AD-87-LH (was 3160:2043831815 and 117029:2104532542): the holder keys are the
    -- sample characters now, and the daily walk meets the holders in their sorted-key order, so the
    -- PRNG reaches each series in a new order. Nothing else about the build moved.
    -- WoW Forever's pins are its own sample's (LH-05: its holder keys, items and currencies); Retail's
    -- did not move with it. Re-pinned by LH-06 (was 3093:296770321 and 110993:401539997): WoW Forever
    -- has no warband bank (R1), so its sample has no Warband holder, tabs or gold.
    local pin = ({ retail = { "3180:521769667", "118617:161303863" }, forever = { "2628:515834675", "95662:1728806636" } })[CLIENT]
    assertEqual(#hs .. ":" .. checksum(hs), pin[1], "holdings")
    assertEqual(#ds .. ":" .. checksum(ds), pin[2], "daily")
  end)
end)

test("TestData: with no default item the default thing is the item on most days, ties to the lowest key", function()
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
    -- The default item (Everlight Crystal, Arcane Crystal) wins on any one day, over an item on more days.
    local names, everlight = NS.BrowserTable.TestSample.itemNames
    for i, n in ipairs(names) do if n == DEFAULT_ITEM then everlight = "i:" .. (100000 + i) end end
    NS.State.testDaily = {
      ["2026-10-01"] = { A = { ["i:5"] = {} } }, ["2026-10-02"] = { A = { ["i:5"] = {}, [everlight] = {} } },
    }
    assertEqual(NS.TestData.DefaultTimelineThing(), everlight)
  end)
  NS.State.testDaily = saved
  if not ok then error(err, 0) end
end)

-- ── the sample characters (preview-mode "Sample characters", LibKa0s#87, AD-87-LH) ──────────────
--
-- Test mode and the simulator draw made-up people, and since the standard's v2.113.0 rule they are
-- the collection's: the five of LibKa0s-Sim-1.0's SAMPLE for the client running (LH-05: Retail's
-- set on Retail, WoW Forever's on Forever) for their classes, and for the classes those five lack,
-- the host's own pool, named to the same convention. Before AD-87-LH every sample character was
-- `<Class>-Ravencrest`, a real realm.

local function sampleWord(w)
  return w ~= nil and #w <= 12 and (w:find("^Sample") or w:find("^Mock")) ~= nil
end

--- True when `key` is a sample identity under the convention for this run's client: on Retail
--- `Name-Realm`, a name of 2-12 letters starting Sample or Mock and the realm Samplerealm or
--- Mockrealm; on WoW Forever "First Surname", both words so, and no realm (forever-quirks-§4).
local function conventional(key)
  if CLIENT == "forever" then
    local first, surname = tostring(key):match("^(%u%l+) (%u%l+)$")
    return sampleWord(first) and sampleWord(surname)
  end
  local name, realm = tostring(key):match("^(%u%l+)%-(%u%l+)$")
  return sampleWord(name) and (realm == "Samplerealm" or realm == "Mockrealm")
end

local function sharedByClass()
  local out = {}
  for _, c in ipairs(T.mocks.LibStub("LibKa0s-Sim-1.0").Sample(CLIENT)) do out[c.classFile] = c.fullName end
  return out
end

test("Test mode: every History sample character is a sample identity, the shared five by class", function()
  local shared, seen = sharedByClass(), {}
  for _, r in ipairs(NS.BrowserTable:BuildTestData()) do
    -- red under: `<Class>-Ravencrest` (a real realm, no Sample or Mock name).
    assertTrue(conventional(r.char), "a sample character off the convention: " .. tostring(r.char))
    if shared[r.classFile] then
      assertEqual(r.char, shared[r.classFile], "the " .. r.classFile .. " is the shared sample character")
      seen[r.char] = true
    end
    for _, ends in ipairs({ r.from, r.to }) do
      local holder = ends:match("^(.-)/")
      assertTrue(holder == WARBAND or conventional(holder), "a move end off the convention: " .. ends)
    end
  end
  local n = 0
  for _ in pairs(seen) do n = n + 1 end
  assertEqual(n, 5, "all five shared characters appear in the sample")
end)

test("Test mode: every Holdings sample holder is a sample identity", function()
  local holdings = NS.TestData.Build(NS.BrowserTable:BuildTestData(), os.time())
  local shared, n = sharedByClass(), 0
  for key, e in pairs(holdings) do
    if key ~= WARBAND then
      n = n + 1
      assertTrue(conventional(key), "a holder off the convention: " .. tostring(key))
      if shared[e.meta.classFile] then assertEqual(key, shared[e.meta.classFile]) end
    end
  end
  assertEqual(n, 4, "the History sample's four mains hold things")
end)

test("the library-absent copies of the sample five are LibKa0s-Sim-1.0's SAMPLE, per client", function()
  -- The fallback NS.SampleCharacters answers without the library (core/SimSeam.lua). A copy that
  -- drifts from the library's rows goes red here, as the skin fallback does in surface parity. Both
  -- clients' copies are held on every run; the one answering is the running client's.
  local SAMPLE = T.mocks.LibStub("LibKa0s-Sim-1.0").SAMPLE
  for _, client in ipairs({ "retail", "forever" }) do
    local live, copy = SAMPLE[client], (NS.SAMPLE_FALLBACKS or {})[client]
    assertTrue(copy ~= nil, client .. ": a library-absent copy")
    assertEqual(#copy, #live, client .. ": five rows")
    for i, row in ipairs(live) do
      for _, field in ipairs({ "name", "realm", "classFile", "fullName", "surname" }) do
        assertEqual(copy[i][field], row[field], client .. " row " .. i .. " " .. field)
      end
    end
  end
  assertTrue(NS.SAMPLE_FALLBACK == NS.SAMPLE_FALLBACKS[CLIENT], "the running client's copy answers")
  local live = SAMPLE[CLIENT]
  local rows = NS.SampleCharacters()
  -- red under: Sim.Sample("retail") on both clients ("Samplehunter-Samplerealm" on WoW Forever).
  assertEqual(rows[1].fullName, live[1].fullName, "with the library, the library's rows for this client")
  rows[1].fullName = "changed"
  assertEqual(NS.SampleCharacters()[1].fullName, live[1].fullName, "each call answers a fresh copy")
end)

test("the sample five are the client's identity shape: Name-Realm on Retail, First Surname on Forever", function()
  local want = ({ retail = "Sampleblade-Samplerealm", forever = "Sampleblade Mockvale" })[CLIENT]
  assertEqual(NS.SampleCharacters()[2].fullName, want)
  for _, c in ipairs(NS.SampleCharacters()) do
    assertTrue(conventional(c.fullName), "off the convention: " .. tostring(c.fullName))
  end
end)

-- ── the History sample's universe, per client (LH-05, clients-§5) ──────────────────────────────

local CLASSES = {
  retail = { "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER", "MAGE", "MONK", "PALADIN", "PRIEST",
    "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" },
  forever = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" },
}
local ZONES = {
  retail = { "Eversong Woods=94", "Harandar=2400", "Isle of Quel'Danas=122", "Silvermoon City=110",
    "Tirisfal Glades=18", "Zul'Aman=781" },
  forever = { "Duskwood=1431", "Elwynn Forest=1429", "Redridge Mountains=1433", "Stormwind City=1453",
    "Teldrassil=1438", "Westfall=1436" },
}

local function sortedSet(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out)
  return table.concat(out, ",")
end

test("Test mode: the History sample's classes are the client's own, one sample character each", function()
  local classes, chars = {}, {}
  for _, r in ipairs(NS.BrowserTable:BuildTestData()) do
    classes[r.classFile] = true
    chars[r.char] = r.classFile
  end
  -- red under: Retail's thirteen on WoW Forever (a Death Knight, Monk, Demon Hunter or Evoker).
  assertEqual(sortedSet(classes), table.concat(CLASSES[CLIENT], ","))
  local perClass = {}
  for key, cls in pairs(chars) do
    assertTrue(perClass[cls] == nil or perClass[cls] == key, cls .. ": one sample character")
    perClass[cls] = key
  end
end)

test("Test mode: the History sample's zones are the client's own, with their uiMapIDs", function()
  local zones = {}
  for _, r in ipairs(NS.BrowserTable:BuildTestData()) do zones[r.zone .. "=" .. tostring(r.mapID)] = true end
  -- red under: Midnight's Quel'Thalas on WoW Forever.
  assertEqual(sortedSet(zones), table.concat(ZONES[CLIENT], ","))
end)

test("Test mode: the History sample's items are the client's own names and item levels", function()
  local names, lo, hi = {}, math.huge, 0
  for _, n in ipairs(NS.BrowserTable.TestSample.itemNames) do names[n] = true end
  assertEqual(#NS.BrowserTable.TestSample.itemNames, 30, "thirty items on each client")
  for _, r in ipairs(NS.BrowserTable:BuildTestData()) do
    assertTrue(names[r.itemName], "a row names an item off the sample: " .. tostring(r.itemName))
    if r.itemLevel then lo, hi = math.min(lo, r.itemLevel), math.max(hi, r.itemLevel) end
  end
  -- red under: one Retail list and Midnight's item levels (560 and up) on WoW Forever.
  if CLIENT == "forever" then
    assertTrue(names["Arcane Crystal"] and not names["Everlight Crystal"], "WoW Forever's own item names")
    assertTrue(lo >= 21 and hi <= 80, ("WoW Forever's item levels, 21..80: %d..%d"):format(lo, hi))
  else
    assertTrue(names["Everlight Crystal"] and not names["Arcane Crystal"], "Retail's own item names")
    assertTrue(lo >= 561 and hi <= 660, ("Retail's item levels, 561..660: %d..%d"):format(lo, hi))
  end
end)

test("Test mode: the sample currencies are the client's own", function()
  local want = ({ retail = { 3008, "Valorstones" }, forever = { 1792, "Honor Points" } })[CLIENT]
  local other = ({ retail = 1792, forever = 3008 })[CLIENT]
  -- red under: Retail's Valorstones, Resonance Crystals and Undercoin on WoW Forever.
  assertEqual((NS.TestData.Describe("c:" .. want[1]) or {}).name, want[2])
  assertEqual(NS.TestData.Describe("c:" .. other), nil, "the other client's currency is not in the sample")
  local holdings = NS.TestData.Build(NS.BrowserTable:BuildTestData(), os.time())
  for key, e in pairs(holdings) do
    for id in pairs(e.currency) do
      assertTrue(NS.TestData.Describe("c:" .. id) ~= nil, key .. " holds a currency off the sample: " .. id)
    end
  end
end)

test("Sim: the stranger the social scenario trades with is a shared sample character", function()
  local target
  for _, st in ipairs(NS.SimHost.SCENARIOS.defs.social.steps) do
    for _, call in ipairs(st.calls) do
      if call[1] == "trade" and call[2] ~= "@alt" then target = call[2] end
    end
  end
  -- red under: "Stranger-Realm"; on WoW Forever, Retail's "Mockflame-Mockrealm".
  assertEqual(target, ({ retail = "Mockflame-Mockrealm", forever = "Mockflame Samplewick" })[CLIENT])
end)
