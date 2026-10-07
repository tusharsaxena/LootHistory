local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local DAY = 86400
local function TM() return NS.TimelineModel end

-- The Timeline's model (timeline-ledger spec §8.1). Pure apart from Build, which reads NS.Holdings
-- and the rollup store. Every case runs through `case`, which puts NS.db.global.holdings / daily and
-- the Rollup's key index back the way it found them, so the suites after this one see no seed.
local function case(name, fn)
  test(name, function()
    local g = NS.db.global
    local holdings, daily, keys = g.holdings, g.daily, NS.Rollup and NS.Rollup._keys
    if NS.Rollup then NS.Rollup._keys = nil end
    local ok, err = pcall(fn)
    g.holdings, g.daily = holdings, daily
    if NS.Rollup then NS.Rollup._keys = keys end
    if not ok then error(err, 0) end
  end)
end
local function noon(y, m, d) return os.time({ year = y, month = m, day = d, hour = 12 }) end

local function seedMoney(holders, ts)
  NS.db.global.holdings, NS.db.global.daily = {}, {}
  for h, copper in pairs(holders) do NS.Holdings:ApplyMoney(h, copper, ts) end
end

local function params(over)
  local p = { thing = "g", range = "30d", now = noon(2026, 10, 5), maxLines = 8,
    daily = NS.db.global.daily, history = {}, retentionDays = 0 }
  p.from = p.now - 30 * DAY
  for k, v in pairs(over or {}) do p[k] = v end
  return p
end

local function byHolder(m, h)
  for _, s in ipairs(m.series) do if s.holder == h then return s end end
end

-- ── day walk ──

case("Timeline model: NextDay and DayStart walk local calendar days", function()
  assertEqual(TM().NextDay("2026-10-31"), "2026-11-01")
  assertEqual(TM().NextDay("2026-12-31"), "2027-01-01")
  assertEqual(os.date("*t", TM().DayStart("2026-10-25")).hour, 0)
  assertEqual(NS.Ledger.DayKey(TM().DayStart("2026-10-25")), "2026-10-25")
end)

-- ── carry-forward ──

case("Timeline model: DailySeries carries the last close forward", function()
  -- Review Focus 2: no change inside the range still draws a flat line at the pre-range close
  local daily = { ["2026-09-01"] = { ["A-R"] = { g = { c = 500 } } } }
  local pts = TM().DailySeries(daily, TM().SortedDays(daily), "A-R", "g", "2026-10-01", "2026-10-03", nil)
  assertEqual(#pts, 3)
  for _, p in ipairs(pts) do assertEqual(p.y, 500) end
  assertEqual(pts[1].x, TM().DayStart("2026-10-01"))
end)

case("Timeline model: DailySeries starts at genesis and picks up each day's close", function()
  local daily = {
    ["2026-10-02"] = { ["A-R"] = { g = { c = 10 } } },
    ["2026-10-04"] = { ["A-R"] = { g = { c = 30, i = 20 } } },
  }
  local pts = TM().DailySeries(daily, TM().SortedDays(daily), "A-R", "g", "2026-10-01", "2026-10-05", "2026-10-02")
  assertEqual(#pts, 4)       -- 02, 03 (carried), 04, 05 (carried); nothing for 01
  assertEqual(pts[1].y, 10); assertEqual(pts[2].y, 10); assertEqual(pts[3].y, 30); assertEqual(pts[4].y, 30)
end)

case("Timeline model: a flow-only cell does not break the carry", function()
  local daily = {
    ["2026-10-01"] = { ["A-R"] = { g = { c = 10 } } },
    ["2026-10-02"] = { ["A-R"] = { g = { i = 4 } } },
  }
  local pts = TM().DailySeries(daily, TM().SortedDays(daily), "A-R", "g", "2026-10-01", "2026-10-02", nil)
  assertEqual(pts[2].y, 10)
end)

case("Timeline model: ValueAt and TotalSeries treat a not-yet-started holder as 0", function()
  local a = { { x = 1, y = 10 }, { x = 2, y = 20 } }
  local b = { { x = 2, y = 5 } }
  assertEqual(TM().ValueAt(a, 1.5), 10); assertEqual(TM().ValueAt(b, 1), nil)
  local t = TM().TotalSeries({ a, b })
  assertEqual(#t, 2)
  assertEqual(t[1].y, 10); assertEqual(t[2].y, 25)
end)

case("Timeline model: TotalSeries keeps an intraday step vertical", function()
  -- A step is two points at one x, (x, before) then (x, after). The Total must step at the same x,
  -- not join the pre-step point to the post-step value with a diagonal.
  local a = { { x = 0, y = 100 }, { x = 50, y = 100 }, { x = 50, y = 200 }, { x = 100, y = 200 } }
  local t = TM().TotalSeries({ a })
  assertEqual(#t, 4, "one holder's Total is that holder's line")
  for i = 1, 4 do
    assertEqual(t[i].x, a[i].x, "point " .. i .. " x"); assertEqual(t[i].y, a[i].y, "point " .. i .. " y")
  end
  -- a second, flat holder lifts both sides of the step by its own value
  local b = { { x = 0, y = 5 }, { x = 100, y = 5 } }
  t = TM().TotalSeries({ a, b })
  assertEqual(#t, 4)
  assertEqual(t[2].x, 50); assertEqual(t[2].y, 105)
  assertEqual(t[3].x, 50); assertEqual(t[3].y, 205)
  assertEqual(TM().ValueBefore(a, 50), 100); assertEqual(TM().ValueBefore(a, 75), 200)
  assertEqual(TM().ValueBefore(b, -1), nil)
end)

-- ── ranking and the cap ──

case("Timeline model: RankHolders applies the Character filter before the cap", function()
  -- Review Focus 4
  local latest = { ["A-R"] = 100, ["B-R"] = 300, ["C-R"] = 200, ["§warband"] = 50 }
  local cands = { "A-R", "B-R", "C-R", "§warband" }
  assertEqual(table.concat(TM().RankHolders(latest, cands, nil, 2), ","), "B-R,C-R")
  assertEqual(table.concat(TM().RankHolders(latest, cands, { ["A-R"] = true, ["§warband"] = true }, 2), ","),
    "A-R,§warband")
  assertEqual(#TM().RankHolders(latest, cands, {}, 8), 4, "an empty selection means everyone")
end)

case("Timeline model: Build draws Total plus at most maxLines holders, richest first", function()
  -- Review Focus 4, end to end
  local holders = {}
  for i = 1, 12 do holders[("H%02d-R"):format(i)] = i * 100 end
  seedMoney(holders, noon(2026, 10, 1))
  local m = TM().Build(params({ maxLines = 8 }))
  assertEqual(#m.series, 9)
  assertEqual(m.series[#m.series].holder, TM().TOTAL, "Total is drawn last, on top")
  assertEqual(m.series[1].holder, "H12-R")
  assertEqual(m.series[#m.series].points[#m.series[#m.series].points].y,
    1200 + 1100 + 1000 + 900 + 800 + 700 + 600 + 500, "Total sums the SHOWN holders")
end)

case("Timeline model: a holder with nothing now but a balance in range is still a candidate", function()
  seedMoney({ ["A-R"] = 100, ["B-R"] = 50 }, noon(2026, 10, 1))
  NS.Holdings:ApplyMoney("B-R", 0, noon(2026, 10, 3))
  local m = TM().Build(params())
  assertTrue(byHolder(m, "B-R") ~= nil)
  assertEqual(byHolder(m, "B-R").points[#byHolder(m, "B-R").points].y, 0)
end)

-- ── decorations ──

case("Timeline model: ledgerSince inside the range is a dashed marker; outside it is not", function()
  seedMoney({ ["A-R"] = 1 }, noon(2026, 10, 1))
  local inside = TM().Build(params({ ledgerSince = noon(2026, 10, 2) }))
  assertEqual(#inside.markers, 1); assertTrue(inside.markers[1].dashed)
  local outside = TM().Build(params({ ledgerSince = noon(2026, 1, 1) }))
  assertEqual(#outside.markers, 0)
end)

case("Timeline model: a partial holder is dashed from genesis until its bank was first seen", function()
  local g, done = noon(2026, 10, 1), noon(2026, 10, 3)
  assertEqual(TM().DashRange({ genesis = g, partial = false, completeAt = done }, 0), g)
  assertEqual(select(2, TM().DashRange({ genesis = g, partial = false, completeAt = done }, 0)), done)
  local from, to = TM().DashRange({ genesis = g, partial = true }, noon(2026, 10, 5))
  assertEqual(from, g); assertEqual(to, noon(2026, 10, 5))
  assertEqual(TM().DashRange({ genesis = g, partial = false }, 0), nil, "complete at genesis: solid")
end)

case("Timeline model: Flows sum the shown holders' gains and losses per day", function()
  local daily = {
    ["2026-10-02"] = { ["A-R"] = { g = { c = 1, i = 10, o = 3 } }, ["B-R"] = { g = { i = 5 } },
                       ["C-R"] = { g = { i = 999 } } },
  }
  local f = TM().Flows(daily, TM().SortedDays(daily), { "A-R", "B-R" }, "g", "2026-10-01", "2026-10-05")
  assertEqual(#f, 1); assertEqual(f[1].i, 15); assertEqual(f[1].o, 3)
end)

case("Timeline model: gold reaches the chart in gold units and stays copper in the model", function()
  seedMoney({ ["A-R"] = 25000 }, noon(2026, 10, 1))
  local m = TM().Build(params())
  local data = TM().ChartData(m)
  assertEqual(m.series[1].points[1].y, 25000)
  assertEqual(data.series[1].points[1].y, 2.5)
  assertFalse(data.integer, "gold is fractional on the chart")
end)

-- ── intraday (Today / 7 d) ──

case("Timeline model: IntradaySeries rebuilds steps from rows, newest backwards from now", function()
  local from = TM().DayStart("2026-10-05")
  local now = from + 18 * 3600
  local rows = {
    { ts = from + 3600, dir = "IN", kind = "GOLD", holder = "A-R", quantity = 100 },
    { ts = from + 7200, dir = "OUT", kind = "GOLD", holder = "A-R", quantity = 30 },
    { ts = from + 7300, dir = "IN", kind = "GOLD", holder = "B-R", quantity = 999 },
  }
  local pts = TM().IntradaySeries(rows, "A-R", "g", from, now, 570, 500)
  assertEqual(#pts, 6)
  assertEqual(pts[1].x, from); assertEqual(pts[1].y, 500)
  assertEqual(pts[3].y, 600); assertEqual(pts[5].y, 570)
  assertEqual(pts[6].x, now); assertEqual(pts[6].y, 570)
end)

case("Timeline model: IntradaySeries gives up when the rows disagree with the rollup", function()
  local from = TM().DayStart("2026-10-05")
  local rows = { { ts = from + 60, dir = "IN", kind = "GOLD", holder = "A-R", quantity = 100 } }
  assertEqual(TM().IntradaySeries(rows, "A-R", "g", from, from + 3600, 570, 400), nil)
  assertEqual(TM().IntradaySeries(rows, "A-R", "g", from, from + 3600, 50, nil), nil, "negative start")
end)

case("Timeline model: a MOVE row moves the holder's own balance by its side", function()
  local out = { dir = "MOVE", kind = "GOLD", holder = "A-R", quantity = 40, from = "A-R/money", to = "§warband/money" }
  local inn = { dir = "MOVE", kind = "GOLD", holder = "§warband", quantity = 40, from = "A-R/money", to = "§warband/money" }
  local intra = { dir = "MOVE", kind = "ITEM", itemID = 7, holder = "A-R", quantity = 5, from = "A-R/bags", to = "A-R/bank" }
  assertEqual(TM().RowDelta(out, "A-R"), -40)
  assertEqual(TM().RowDelta(inn, "§warband"), 40)
  assertEqual(TM().RowDelta(intra, "A-R"), 0)
  assertEqual(TM().RowDelta(out, "§warband"), 0, "another holder's row never moves this one")
end)

case("Timeline model: intraday only for Today / 7d, inside retention, after the ledger began", function()
  local now = noon(2026, 10, 5)
  assertTrue(TM().IntradayOK("today", now - 3600, now, 0, now - 99 * DAY))
  assertTrue(TM().IntradayOK("7d", now - 7 * DAY, now, 30, now - 99 * DAY))
  assertFalse(TM().IntradayOK("30d", now - 30 * DAY, now, 0, now - 99 * DAY))
  assertFalse(TM().IntradayOK("7d", now - 7 * DAY, now, 3, now - 99 * DAY), "rows pruned at 3 days")
  assertFalse(TM().IntradayOK("7d", now - 7 * DAY, now, 0, now - DAY), "rows before ledgerSince are gains-only")
end)

-- ── hover and picker ──

case("Timeline model: HoverLines reads each line's value and that day's flows", function()
  seedMoney({ ["A-R"] = 500 }, noon(2026, 10, 1))
  NS.Rollup:NoteFlow("A-R", "g", noon(2026, 10, 1), "IN", 500)
  local m = TM().Build(params())
  local i
  for k, x in ipairs(m.hoverXs) do if NS.Ledger.DayKey(x) == "2026-10-01" then i = k end end
  local h = TM().HoverLines(m, i)
  assertEqual(h.rows[1].text, TM().FormatValue("GOLD", 500))
  assertEqual(h.gain, TM().FormatValue("GOLD", 500))
  assertEqual(h.loss, TM().FormatValue("GOLD", 0))
end)

case("Timeline model: Suggest puts Gold first, then the biggest totals, capped", function()
  local things = {
    { key = "i:1", name = "Gloom Potion", total = 3 },
    { key = "g", name = "Gold", total = 10 },
    { key = "i:2", name = "Golden Potion", total = 50 },
  }
  local s = TM().Suggest("o", things, 2)
  assertEqual(#s, 2); assertEqual(s[1].key, "g"); assertEqual(s[2].key, "i:2")
  assertEqual(#TM().Suggest("zzz", things, 8), 0)
end)

-- ── visibility (P8: the Total-only toggle and the click-to-toggle legend) ──

case("Timeline model: Visible drops the hidden series and ignores keys it does not draw", function()
  local series = { { holder = "A-R" }, { holder = "B-R" }, { holder = TM().TOTAL } }
  local v = TM().Visible(series, { ["B-R"] = true, ["Gone-R"] = true })
  assertEqual(#v, 2); assertEqual(v[1].holder, "A-R"); assertEqual(v[2].holder, TM().TOTAL)
  assertEqual(#TM().Visible(series, nil), 3, "no set hides nothing")
  assertEqual(#TM().Visible(series, { ["A-R"] = true, ["B-R"] = true, [TM().TOTAL] = true }), 0)
end)

case("Timeline model: YRange spans only the series it is handed", function()
  local series = { { points = { { x = 1, y = 5 }, { x = 2, y = 900 } } },
                   { points = { { x = 1, y = 20 }, { x = 2, y = 40 } } } }
  local lo, hi = TM().YRange(series)
  assertEqual(lo, 5); assertEqual(hi, 900)
  lo, hi = TM().YRange({ series[2] })
  assertEqual(lo, 20); assertEqual(hi, 40)
  lo, hi = TM().YRange({})
  assertEqual(lo, nil); assertEqual(hi, nil)
end)

case("Timeline model: ChartData draws only the visible lines and scales y over them", function()
  -- Review Focus 2: the axis rescales to what is drawn
  seedMoney({ ["A-R"] = 2000000, ["B-R"] = 30000 }, noon(2026, 10, 1))
  local m = TM().Build(params())
  local all = TM().ChartData(m)
  assertEqual(#all.series, 3)
  assertEqual(all.yMax, 203, "the Total, in gold")
  local hidden = { ["A-R"] = true, [TM().TOTAL] = true }
  local data = TM().ChartData(m, hidden)
  assertEqual(#data.series, 1, "B-R alone")
  assertEqual(data.yMin, 3); assertEqual(data.yMax, 3)
  assertEqual(#data.hoverXs, #all.hoverXs, "the hover days do not depend on what is drawn")
end)

case("Timeline model: HoverLines lists only the visible lines, flows unchanged", function()
  seedMoney({ ["A-R"] = 500, ["B-R"] = 700 }, noon(2026, 10, 1))
  local m = TM().Build(params())
  local i = #m.hoverXs
  local h = TM().HoverLines(m, i, { ["A-R"] = true })
  assertEqual(#h.rows, 2)
  assertEqual(h.rows[1].label, TM().Label("B-R")); assertEqual(h.rows[2].label, "Total")
  assertEqual(#TM().HoverLines(m, i).rows, 3)
end)

-- ── the in/out strip's tooltip (P8) ──

case("Timeline model: FlowLines titles the day as the Total's and signs Gained / Lost / Net", function()
  local x = TM().DayStart("2026-08-14")
  local G, L = NS.Constants.TIMELINE.GAIN, NS.Constants.TIMELINE.LOSS
  local h = TM().FlowLines({ kind = "GOLD" }, { x = x, day = "2026-08-14", i = 20000, o = 5000 })
  assertEqual(h.title, "14 Aug 2026 \194\183 Total")
  assertEqual(#h.rows, 3)
  assertEqual(h.rows[1].label, "Gained"); assertEqual(h.rows[1].text, "+" .. NS.Util.FormatMoney(20000))
  assertEqual(h.rows[2].label, "Lost"); assertEqual(h.rows[2].text, "-" .. NS.Util.FormatMoney(5000))
  assertEqual(h.rows[3].label, "Net"); assertEqual(h.rows[3].text, "+" .. NS.Util.FormatMoney(15000))
  assertTrue(h.rows[1].color == G and h.rows[2].color == L and h.rows[3].color == G, "gain green, loss red, net by sign")
end)

case("Timeline model: FlowLines counts a currency, shows a zero side as 0 and a negative net red", function()
  local x = TM().DayStart("2026-08-14")
  local L = NS.Constants.TIMELINE.LOSS
  local h = TM().FlowLines({ kind = "CURRENCY" }, { x = x, i = 3, o = 10 })
  assertEqual(h.rows[1].text, "+3"); assertEqual(h.rows[2].text, "-10"); assertEqual(h.rows[3].text, "-7")
  assertTrue(h.rows[3].color == L)
  h = TM().FlowLines({ kind = "GOLD" }, { x = x, i = 0, o = 4 })
  assertEqual(h.rows[1].text, "0", "the zero side reads 0 when the other is not")
  assertEqual(h.rows[3].text, "-" .. NS.Util.FormatMoney(4))
  h = TM().FlowLines({ kind = "ITEM" }, { x = x, i = 2, o = 2 })
  assertEqual(h.rows[3].text, "0", "an even day nets to an unsigned 0")
end)

case("Timeline model: FlowLines answers nil for a day with no flow", function()
  assertEqual(TM().FlowLines({ kind = "GOLD" }, { x = 0, i = 0, o = 0 }), nil)
  assertEqual(TM().FlowLines({ kind = "GOLD" }, nil), nil)
end)

-- ── the legend's tooltip and layout (P10) ──

case("Timeline model: FormatCount groups thousands, FormatHolding reads gold as coins", function()
  assertEqual(TM().FormatCount(0), "0")
  assertEqual(TM().FormatCount(999), "999")
  assertEqual(TM().FormatCount(1000), "1,000")
  assertEqual(TM().FormatCount(1234567), "1,234,567")
  assertEqual(TM().FormatCount(-12345), "-12,345")
  assertEqual(TM().FormatHolding("GOLD", 123456), NS.Util.FormatMoney(123456), "History's gold Qty formatter")
  assertEqual(TM().FormatHolding("GOLD", 0), "0", "no gold reads 0, not blank")
  assertEqual(TM().FormatHolding("CURRENCY", 12345), "12,345")
  assertEqual(TM().FormatHolding("ITEM", nil), "0")
end)

local function tipModel(key, kind, holders)
  local series = {}
  for _, h in ipairs(holders) do
    series[#series + 1] = { holder = h, label = TM().Label(h), color = TM().Color(h, TM().Meta(h)) }
  end
  series[#series + 1] = { holder = TM().TOTAL, label = "Total", color = NS.Constants.TIMELINE.TOTAL }
  return { key = key, kind = kind, series = series }
end

case("Timeline model: LegendTip colors the title by holder kind and reads the current holding", function()
  local W = NS.Constants.WARBAND_HOLDER
  seedMoney({ ["A-R"] = 70000, [W] = 25000 }, noon(2026, 10, 5))
  NS.db.global.holdings["A-R"].meta.classFile = "MAGE"
  local m = tipModel("g", "GOLD", { "A-R", W })
  local t = TM().LegendTip(m, "A-R")
  local cc = T.mocks.RAID_CLASS_COLORS.MAGE
  assertEqual(t.title, "A-R")
  assertEqual(t.color[1], cc.r); assertEqual(t.color[2], cc.g); assertEqual(t.color[3], cc.b)
  assertEqual(t.label, "Holding"); assertEqual(t.value, NS.Util.FormatMoney(70000))
  assertEqual(t.hint, "Click to hide/show")
  t = TM().LegendTip(m, W)
  assertEqual(t.title, "Warband")
  assertTrue(t.color == NS.Constants.TIMELINE.WARBAND, "the Warband's title is its series color")
  assertEqual(t.value, NS.Util.FormatMoney(25000))
  t = TM().LegendTip(m, TM().TOTAL)
  assertEqual(t.title, "Total")
  assertEqual(t.color[1], 1); assertEqual(t.color[2], 0.82); assertEqual(t.color[3], 0)
  assertEqual(t.label, "Holding", "every holder is charted, so the Total is the account's")
  assertEqual(t.value, NS.Util.FormatMoney(95000))
end)

case("Timeline model: LegendTip's Total sums only the charted holders and says so", function()
  seedMoney({ ["A-R"] = 70000, ["B-R"] = 10000 }, noon(2026, 10, 5))
  local t = TM().LegendTip(tipModel("g", "GOLD", { "B-R" }), TM().TOTAL)
  assertEqual(t.label, "Holding (all shown characters)")
  assertEqual(t.value, NS.Util.FormatMoney(10000))
end)

case("Timeline model: LegendTip counts currencies and items with separators, and a holder with none reads 0", function()
  NS.db.global.holdings, NS.db.global.daily = {}, {}
  local ts = noon(2026, 10, 5)
  NS.Holdings:ApplyCurrency("A-R", { [3008] = 12345 }, ts)
  NS.Holdings:ApplyContainer("A-R", "bags", { [2589] = 1500 }, nil, ts)
  assertEqual(TM().LegendTip(tipModel("c:3008", "CURRENCY", { "A-R" }), "A-R").value, "12,345")
  assertEqual(TM().LegendTip(tipModel("i:2589", "ITEM", { "A-R" }), "A-R").value, "1,500")
  assertEqual(TM().LegendTip(tipModel("i:2589", "ITEM", { "Gone-R" }), "Gone-R").value, "0")
  assertEqual(TM().LegendTip(tipModel("g", "GOLD", { "Gone-R" }), "Gone-R").value, "0")
  assertEqual(TM().LegendTip(tipModel("g", "GOLD", {}), "Nobody-R"), nil, "a key the chart does not draw")
end)

case("Timeline model: LegendTip reads the test-mode store when it is on", function()
  seedMoney({ ["A-R"] = 70000 }, noon(2026, 10, 5))
  local sample = NS.db.global.holdings
  NS.db.global.holdings = {}
  local saved = NS.State.testHoldings
  NS.State.testHoldings = sample
  local ok, err = pcall(function()
    assertEqual(TM().LegendTip(tipModel("g", "GOLD", { "A-R" }), "A-R").value, NS.Util.FormatMoney(70000))
  end)
  NS.State.testHoldings = saved
  if not ok then error(err, 0) end
end)

case("Timeline model: LegendLayout keeps the Total's slot and one gap between the rest, wrapping rows", function()
  local pos, rows = TM().LegendLayout({ 30, 42, 60, 54 }, 120, 16, 1000)
  assertEqual(rows, 1)
  assertEqual(pos[1].x, 0); assertEqual(pos[2].x, 120, "the Total's slot is unchanged")
  assertEqual(pos[3].x, 120 + 42 + 16); assertEqual(pos[4].x, 120 + 42 + 16 + 60 + 16)
  pos, rows = TM().LegendLayout({ 30, 42, 60, 54 }, 120, 16, 240)
  assertEqual(rows, 2)
  assertEqual(pos[3].row, 1); assertEqual(pos[4].row, 2); assertEqual(pos[4].x, 0, "a wrapped row starts at the left")
  pos, rows = TM().LegendLayout({ 30, 500 }, 120, 16, 100)
  assertEqual(rows, 2, "an entry wider than the row still gets a row of its own")
  assertEqual(pos[2].x, 0)
end)
