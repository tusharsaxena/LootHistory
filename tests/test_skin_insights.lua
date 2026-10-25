-- tests/test_skin_insights.lua — Insights, the Timeline, Holdings and the AH price table on the skin
-- (LH-04; core/SkinSetup.lua's NS.Skin over LibKa0s-Skin-1.0, skinning-§3).
--
-- What this pins: on Ka0s Default each of these surfaces draws the values it drew before the skin
-- engine (the KPI cards and list panels call for call through the skin's Card and Panel, the chart
-- chrome, the series palette, the signed escapes' bytes, the toggle, the Holdings rows, the AH
-- table's colors and ticks), a skin switch repaints them live with no reload (the pooled widgets on
-- the free list too, the palette and the meaning colors synced, the markup rebuilt, the parked AH
-- host repainted), and Ka0s Default puts them back. tests/analytics_golden.txt and
-- tests/panel_auction_golden.txt pin the Ka0s Default render itself and stay unchanged.
--
-- THE PAINT RECORDER. As tests/test_skin_table.lua: the shared mock's CreateTexture answers the
-- frame itself, so each surface is built FRESH under the kit's opt-in recorder
-- (tests/_kit/mock_paint.lua) on the live module, whose build fields are put back afterwards, with
-- the recorder restored and the skin reset to Ka0s Default whatever the case raised.
--
-- After tests/test_skin_table.lua, whose reset this file repeats for the same reason.

local T = _G.LH_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local Skin = mocks.LibStub("LibKa0s-Skin-1.0")
local OptionsLib = mocks.LibStub("LibKa0s-Options-1.0")
local installPaint = dofile("tests/_kit/mock_paint.lua")
local PS = dofile("tests/panel_support.lua")
local OWNER = "LootHistory"

-- ── the skin back on Ka0s Default (tests/test_skin_chrome.lua's reset) ──────────────────────────
local WAS_SHOWN
local function reset()
  if not WAS_SHOWN then
    WAS_SHOWN = {}
    for ctx in pairs(OptionsLib.__shownPages or {}) do
      if ctx.panel and ctx.panel:IsShown() then WAS_SHOWN[ctx] = true end
    end
  end
  NS.WriteSkinChoice("ka0s", "ka0s")
  Skin:SetChoice(OWNER, "ka0s", "ka0s")
  mocks.__fireTimers()
  for ctx in pairs(WAS_SHOWN) do
    local panel = ctx.panel
    if rawequal(rawget(panel, "__ka0sSkinBg"), panel) then rawset(panel, "__ka0sSkinBg", nil) end
    if not (panel:IsShown() and OptionsLib.__shownPages[ctx]) then
      panel:Show()
      panel:__fire("OnShow")
    end
  end
  mocks.__fireTimers()
end

-- "r,g,b,a" at three decimals, alpha 1 when absent: one spelling for a recorded and a token color.
local function rgba(c)
  if type(c) ~= "table" then return tostring(c) end
  return ("%.3f,%.3f,%.3f,%.3f"):format(c[1], c[2], c[3], c[4] or 1)
end
local function tokenOf(name) return rgba({ Skin:Color(OWNER, name) }) end
local function textColor(fs) return rgba(rawget(fs, "__textColor")) end
local function texColor(t) return rgba(rawget(t, "__color")) end

local function recorded(frame, prim)
  local rec = Skin.painted[frame]
  return rec ~= nil and rec.owner == OWNER and rec.calls[prim] ~= nil
end

-- A "|cffrrggbb" escape of a token, rounded to the byte.
local function escapeOf(name)
  local r, g, b = Skin:Color(OWNER, name)
  local function byte(v) return ("%02x"):format(math.floor(v * 255 + 0.5)) end
  return "|cff" .. byte(r) .. byte(g) .. byte(b)
end

-- Every token a case compares must differ in Azeroth, or the switch proves nothing.
local function assertMoves(names, today)
  for _, name in ipairs(names) do
    assertTrue(tokenOf(name) ~= today(name), "Azeroth's " .. name .. " is today's value: pick another skin")
  end
end

-- Build `mod` afresh under the recorder: `keys` (its build fields) are cleared, `build(pane)` runs,
-- then `fn`; the fields, the recorder and the skin are put back whatever happened. A templated font
-- string is given the client's 12-point face, as tests/test_analytics_layout.lua does (Insights'
-- section dividers scale it by 1.5).
local function withFresh(mod, keys, build, fn)
  reset()
  local saved = {}
  for _, k in ipairs(keys) do saved[k] = mod[k]; mod[k] = nil end
  local restorePaint = installPaint(mocks)
  local painted = mocks.CreateFrame
  rawset(mocks, "CreateFrame", function(...)
    local f = painted(...)
    local createFS = rawget(f, "CreateFontString")
    if createFS then
      rawset(f, "CreateFontString", function(self, name, layer, template)
        local s = createFS(self, name, layer, template)
        if template then s:SetFont("Fonts\\FRIZQT__.TTF", 12, "") end
        -- The strip's axis labels are turned upright; the recorder models no rotation.
        rawset(s, "SetRotation", function(fs, r) rawset(fs, "__rotation", r) end)
        return s
      end)
    end
    return f
  end)
  local ok, err = pcall(function()
    build(mocks.CreateFrame("Frame", nil, mocks.UIParent))
    fn()
  end)
  rawset(mocks, "CreateFrame", painted)
  restorePaint()
  for _, k in ipairs(keys) do mod[k] = saved[k] end
  reset()
  if not ok then error(err, 0) end
end

-- Today's values, the literals these surfaces drew before the skin engine.
local TODAY = {
  ["card.bg"] = { 0.1, 0.1, 0.12, 0.85 }, ["card.border"] = { 0.24, 0.24, 0.27, 0.9 },
  ["panel.bg"] = { 0.08, 0.08, 0.10, 0.6 }, ["panel.border"] = { 0.24, 0.24, 0.27, 0.7 },
  ["text.heading"] = { 1, 0.82, 0 }, ["text.disabled"] = { 0.5, 0.5, 0.5 },
  ["section.rule"] = { 1, 0.82, 0, 0.35 }, ["chart.track"] = { 1, 1, 1, 0.06 },
  ["chart.bar"] = { 0.40, 0.60, 0.95, 0.9 }, ["text.muted"] = { 0.7, 0.7, 0.72 },
  ["text.value"] = { 0.8, 0.8, 0.82 }, ["chart.axis"] = { 0.45, 0.45, 0.5, 0.8 },
  ["chart.axisAlt"] = { 0.55, 0.55, 0.60, 0.9 }, ["text.accent"] = { 1, 0.82, 0 },
  ["check.bg"] = { 0.24, 0.24, 0.27, 1 }, ["check.mark"] = { 1, 0.82, 0, 1 },
  ["btn.bg"] = { 0.1, 0.1, 0.12, 0.9 }, ["btn.border"] = { 0.24, 0.24, 0.27, 0.9 },
  ["list.header.text"] = { 1, 0.82, 0 }, ["list.stripe"] = { 1, 1, 1, 0.03 },
  ["list.hover"] = { 1, 0.82, 0, 0.10 }, ["text.highlight"] = { 1, 1, 1 },
  ["text.headingAlt"] = { 0.91, 0.77, 0.42 }, ["text.bodyAlt"] = { 0.86, 0.86, 0.86 },
  ["text.body"] = { 0.9, 0.9, 0.9 }, ["sem.statusOk"] = { 0.30, 0.95, 0.35 },
  ["sem.statusBad"] = { 1, 0.32, 0.32 }, ["sem.statusWarn"] = { 1, 0.82, 0.10 },
  ["icon.hot"] = { 1, 1, 1 }, ["icon.dim"] = { 0.55, 0.55, 0.55 },
  ["gtip.title"] = { 1, 0.82, 0 }, ["gtip.body"] = { 0.9, 0.9, 0.9 }, ["gtip.value"] = { 1, 1, 1 },
  ["gtip.muted"] = { 0.5, 0.5, 0.5 }, ["sem.warbandAlt"] = { 0.4, 0.78, 1 },
}
local function today(name) return rgba(TODAY[name]) end

-- ── Insights ────────────────────────────────────────────────────────────────────────────────────

local A = NS.Analytics
local A_KEYS = { "pane", "scroll", "content", "cards", "headers", "lootDivider", "currencyDivider",
                 "dayStrip", "valueStrip", "hourStrip", "zonePanel", "itemPanel", "itemValuePanel",
                 "currencyStrip", "emptyText", "pool", "ledgerUI", "stats" }

-- A small history with items, a loss (the GAINS & LOSSES half) and two days, laid out at 780 wide.
local FX = dofile("tests/fixture_insights.lua")
local function insightsStats()
  local h = FX.richHistory()
  h[#h + 1] = { ts = 1600000000, char = "Alpha-Realm", classFile = "WARRIOR", kind = "GOLD", itemName = "Gold",
                source = "REPAIR", dir = "OUT", quantity = 300 }
  return FX.statsFor(h)
end

-- The refresh a switch ends with redraws the fixture (the live one recomputes from the session's
-- history) and parks the bind-state bars again, so the walk's reach to the free list stays visible.
local function fixtureRefresh(self)
  self:LayoutCharts(-100, 780, 8)
  NS.Pool.ReleaseAll(self.pool.bound)
end

local function withInsights(fn)
  withFresh(A, A_KEYS, function(pane) A:Attach(pane) end, function()
    A.stats = insightsStats()
    local stock = rawget(A, "Refresh")
    A.Refresh = fixtureRefresh
    local ok, err = pcall(function()
      -- Park every bar of one section on its free list, so the walk has both lists to reach.
      fixtureRefresh(A)
      fn()
    end)
    A.Refresh = stock
    if not ok then error(err, 0) end
  end)
end

-- Every Insights surface colored at build time, against `want(name)`.
local function assertInsights(want, label)
  for key, c in pairs(A.cards) do
    assertTrue(recorded(c.frame, "Card"), label .. ": card " .. key .. " is the skin's Card")
    assertEqual(rgba(rawget(c.frame, "__backdropColor")), want("card.bg"), label .. ": card " .. key .. " fill")
    assertEqual(rgba(rawget(c.frame, "__backdropBorderColor")), want("card.border"), label .. ": card edge")
    assertEqual(textColor(c.num), want("text.heading"), label .. ": card " .. key .. " headline")
    assertEqual(textColor(c.caption), want("text.disabled"), label .. ": card " .. key .. " caption")
  end
  for key, h in pairs(A.headers) do assertEqual(textColor(h), want("text.heading"), label .. ": heading " .. key) end
  for _, d in ipairs({ A.lootDivider, A.currencyDivider, A.ledgerUI.divider }) do
    for i, rule in ipairs(d.rules) do assertEqual(texColor(rule), want("section.rule"), label .. ": rule " .. i) end
    assertEqual(textColor(d.fs), want("text.heading"), label .. ": divider title")
  end
  for _, p in ipairs({ A.zonePanel, A.itemPanel, A.itemValuePanel }) do
    assertTrue(recorded(p, "Panel"), label .. ": a list panel is the skin's Panel")
    assertEqual(rgba(rawget(p, "__backdropColor")), want("panel.bg"), label .. ": panel fill")
    assertEqual(rgba(rawget(p, "__backdropBorderColor")), want("panel.border"), label .. ": panel edge")
    assertEqual(textColor(p.title), want("text.heading"), label .. ": panel title")
  end
  assertEqual(textColor(A.ledgerUI.caveat), want("text.accent"), label .. ": the caveat")
  local function each(pool, fn) for _, w in ipairs(pool.active) do fn(w) end for _, w in ipairs(pool.free) do fn(w) end end
  assertTrue(#A.pool.bound.free > 0, label .. ": no bar on a free list")
  each(A.pool.bound, function(b) assertEqual(texColor(b.track), want("chart.track"), label .. ": a parked bar's track") end)
  each(A.pool.chsource, function(b) assertEqual(texColor(b.track), want("chart.track"), label .. ": a stacked track") end)
  each(A.pool.day, function(f)
    assertEqual(texColor(f.fill), want("chart.bar"), label .. ": a strip bar")
    assertEqual(textColor(f.axis), want("text.muted"), label .. ": a strip label")
  end)
  each(A.pool.sourceleg, function(f) assertEqual(textColor(f.fs), want("text.value"), label .. ": a legend chip") end)
  each(A.ledgerUI.pools.reason, function(b)
    assertEqual(texColor(b.track), want("chart.track"), label .. ": a ledger track")
    assertEqual(texColor(b.axis), want("chart.axisAlt"), label .. ": the ledger's center axis")
  end)
  assertTrue(#A.pool.day.active > 0 and #A.pool.sourceleg.active > 0 and #A.ledgerUI.pools.reason.active > 0,
    label .. ": the fixture drew no strip, legend or ledger bar")
end

test("skin insights: on Ka0s Default the cards, panels and chart chrome draw today's values", function()
  withInsights(function()
    assertInsights(today, "Ka0s Default")
    local bd = rawget(A.cards.records.frame, "__backdrop")
    assertEqual(bd.bgFile, "Interface\\Buttons\\WHITE8X8"); assertEqual(bd.edgeSize, 1)
    assertEqual(bd.insets and bd.insets.left, 1, "the card's backdrop is inset by one, as before")
    local p = A.pool.source.active[1]
    assertEqual(rgba(rawget(p.value, "__textColor")), today("text.value"), "a bar's value column")
    assertEqual(texColor(A.dayStrip.axisLine), today("chart.axis"), "the strip's axis")
  end)
end)

test("skin insights: the palette, the Other gray and the bind colors are today's on Ka0s Default", function()
  local want = { { 0.90, 0.25, 0.25 }, { 0.95, 0.55, 0.15 }, { 0.50, 0.28, 0.62 } }
  for i, rank in ipairs({ 1, 2, 21 }) do
    assertEqual(rgba(A.paletteColor(rank)), rgba(want[i]), "palette rank " .. rank)
  end
  assertEqual(rgba(A.K.NEUTRAL), rgba({ 0.55, 0.62, 0.72 }), "the Other segment")
  local B = A._fmt.BOUND_COLOR
  assertEqual(rgba(B.BOP), rgba({ 0.85, 0.45, 0.45 }), "Insights' BoP")
  assertEqual(rgba(B.UNBOUND), rgba({ 0.60, 0.60, 0.65 }), "Insights' unbound")
  assertEqual(rgba(B.WARBAND), rgba({ 0.30, 0.58, 0.98 }), "Warbound, the table's blue")
  assertEqual(rgba(A._qualityColor(nil)), rgba({ mocks.ITEM_QUALITY_COLORS[1].r, mocks.ITEM_QUALITY_COLORS[1].g,
    mocks.ITEM_QUALITY_COLORS[1].b }), "a missing quality reads common")
end)

test("skin insights: a switch repaints Insights live, the free list too, and syncs the palette", function()
  withInsights(function()
    NS.ApplySkinChoice("ka0s", "azeroth")
    assertMoves({ "card.bg", "card.border", "panel.bg", "text.heading", "text.disabled", "section.rule",
                  "chart.track", "chart.bar", "text.muted", "text.value", "chart.axisAlt" }, today)
    assertInsights(tokenOf, "Azeroth")
    local series = Skin:Token(OWNER, "chart.series")
    assertEqual(rgba(A.paletteColor(1)), rgba({ series[1][1], series[1][2], series[1][3] }), "the palette is the skin's")
    assertEqual(#A.paletteColor(1), 3, "still a triple")
    assertEqual(rgba(A.K.NEUTRAL), rgba({ Skin:Color(OWNER, "chart.other") }), "the Other segment follows")
    assertEqual(rgba(A._fmt.BOUND_COLOR.BOP), rgba({ Skin:Color(OWNER, "sem.boundBoPAlt") }), "the bind split follows")
    -- The refresh after the walk rebound the charts in the new skin.
    local bar = A.pool.source.active[1]
    assertEqual(rgba(rawget(bar.value, "__textColor")), tokenOf("text.value"), "a rebound bar's value")
    NS.ApplySkinChoice("ka0s", "ka0s")
    assertInsights(today, "back on Ka0s Default")
    assertEqual(rgba(A.paletteColor(1)), rgba({ 0.90, 0.25, 0.25 }), "the palette back")
  end)
end)

test("skin insights: the signed figures keep their bytes on Ka0s Default and follow a switch", function()
  local LF = NS.LedgerFormat
  assertEqual(LF.SignedCount(3), "|cff40ff40+3|r")
  assertEqual(LF.SignedCount(-2), "|cffff4040-2|r")
  assertEqual(LF.SignedCount(0), "|cff808080\226\128\148|r")
  local r, g, b = LF.Color("OUT")
  assertEqual(rgba({ r, g, b }), rgba({ 1, 0.33, 0.33 }), "a loss, BankLedger's red")
  NS.ApplySkinChoice("ka0s", "azeroth")
  local ok, err = pcall(function()
    assertTrue(escapeOf("sem.goodAlt") ~= "|cff40ff40", "Azeroth's sem.goodAlt is today's")
    assertEqual(LF.SignedCount(3), escapeOf("sem.goodAlt") .. "+3|r")
    assertEqual(LF.SignedMoney(-5), escapeOf("sem.badAlt") .. "-" .. NS.Util.FormatMoney(5) .. "|r")
    assertEqual(rgba({ LF.Color("IN") }), rgba({ Skin:Color(OWNER, "sem.good") }), "a gain follows")
  end)
  reset()
  if not ok then error(err, 0) end
end)

-- ── the tooltip lines (core/Compat.lua) ─────────────────────────────────────────────────────────

-- Capture GameTooltip's AddLine / AddDoubleLine for the length of `fn`.
local function tipLines(fn)
  local tt, lines = mocks.GameTooltip, {}
  local stock = { AddLine = rawget(tt, "AddLine"), AddDoubleLine = rawget(tt, "AddDoubleLine") }
  rawset(tt, "AddLine", function(_, text, r, g, bl, wrap)
    lines[#lines + 1] = { text = text, c = rgba({ r, g, bl }), wrap = wrap }
  end)
  rawset(tt, "AddDoubleLine", function(_, l, v, lr, lg, lb, rr, rg, rb)
    lines[#lines + 1] = { text = l, value = v, c = rgba({ lr, lg, lb }), vc = rgba({ rr, rg, rb }) }
  end)
  local ok, err = pcall(fn)
  rawset(tt, "AddLine", stock.AddLine); rawset(tt, "AddDoubleLine", stock.AddDoubleLine)
  if not ok then error(err, 0) end
  return lines
end

local function assertTips(want, label)
  local C = NS.Compat
  local l = tipLines(function() C.ShowTextTooltip({}, "Title", "Body") end)
  assertEqual(l[1].c, want("gtip.title"), label .. ": a text tooltip's title")
  assertEqual(l[2].c, want("gtip.body"), label .. ": its body")
  assertTrue(l[2].wrap == true and l[1].wrap == nil, label .. ": the body wraps, the title does not")
  l = tipLines(function() C.ShowAmountTooltip({}, "Gold", nil, "Amount", "5g", "hint") end)
  assertEqual(l[1].c, want("gtip.title"), label .. ": an amount tooltip's default title")
  assertEqual(l[2].c, want("gtip.body"), label .. ": its label"); assertEqual(l[2].vc, want("gtip.value"), label .. ": its value")
  assertEqual(l[3].c, want("gtip.muted"), label .. ": its hint")
  assertTrue(l[1].wrap == nil and l[3].wrap == nil, label .. ": no alpha lands in the wrap flag")
  l = tipLines(function() C.ShowLinesTooltip({}, "Day", { { label = "Net", text = "0" } }) end)
  assertEqual(l[1].c, want("gtip.title"), label .. ": a lines tooltip's title")
  assertEqual(l[2].c, want("gtip.value"), label .. ": a row with no color")
  local cursor, scale = rawget(mocks, "GetCursorPosition"), rawget(mocks.UIParent, "GetEffectiveScale")
  rawset(mocks, "GetCursorPosition", function() return 100, 100 end)
  rawset(mocks.UIParent, "GetEffectiveScale", function() return 1 end)
  l = tipLines(function() C.ShowCursorTooltip({}, "Sword: 3", "gtip.title") end)
  rawset(mocks, "GetCursorPosition", cursor); rawset(mocks.UIParent, "GetEffectiveScale", scale)
  assertEqual(l[1].c, want("gtip.title"), label .. ": a cursor line")
  l = tipLines(function() C.ShowLineTooltip({}, "3 drops") end)
  assertEqual(l[1].c, want("gtip.value"), label .. ": a strip bar's line")
end

test("skin insights: the host's tooltip lines read gtip.* in core/Compat.lua and follow a switch", function()
  assertTips(today, "Ka0s Default")
  NS.ApplySkinChoice("ka0s", "azeroth")
  local ok, err = pcall(function()
    assertMoves({ "gtip.title", "gtip.body" }, today)
    assertTips(tokenOf, "Azeroth")
  end)
  reset()
  if not ok then error(err, 0) end
end)

-- ── the Timeline ────────────────────────────────────────────────────────────────────────────────

local TL = NS.Timeline
local TL_KEYS = { "pane", "bar", "title", "hint", "totalOnlyBtn", "chart", "emptyMsg", "missing", "strip",
                  "stripAxis", "stripPool", "legend", "legendPool", "legendH", "legendButtons", "model",
                  "chartW", "flowTipOwner", "legendTipOwner", "thing" }

-- The tab's own filter, unfiltered: the shared bar's parked Character scope belongs to other suites.
local function unfiltered(tab, fn)
  local B, stock = NS.Browser, NS.Browser.CurrentFilter
  B.CurrentFilter = function(self, t) if t == tab then return {} end return stock(self, t) end
  local ok, err = pcall(fn)
  B.CurrentFilter = stock
  if not ok then error(err, 0) end
end

local function withTimeline(fn)
  local g = NS.db.global
  local holdings, daily = g.holdings, g.daily
  g.holdings, g.daily = {}, {}
  local now = os.time()
  NS.Holdings:ApplyMoney("Mock-Realm", 50000, now - 86400)
  NS.Holdings:ApplyMoney("Mock-Realm", 70000, now)
  NS.Holdings:ApplyMoney(NS.Constants.WARBAND_HOLDER, 10000, now)
  local ok, err = pcall(unfiltered, "Timeline", function()
    withFresh(TL, TL_KEYS, function(pane)
      TL.thing = "g"
      TL:Attach(pane)
      TL:Layout(640, 320)
    end, fn)
  end)
  g.holdings, g.daily = holdings, daily
  if not ok then error(err, 0) end
end

local function seriesColor(holder)
  for _, s in ipairs(TL.model.series) do if s.holder == holder then return rgba(s.color) end end
end

local function assertTimeline(want, label)
  local b = TL.totalOnlyBtn
  assertTrue(recorded(b, "Button"), label .. ": the toggle is the skin's Button")
  assertEqual(rgba(rawget(b, "__backdropColor")), want("btn.bg"), label .. ": the toggle's fill")
  assertEqual(rgba(rawget(b, "__backdropBorderColor")), want("btn.border"), label .. ": the toggle's edge")
  assertEqual(texColor(b.box), want("check.bg"), label .. ": the toggle's box")
  assertEqual(texColor(b.tick), want("check.mark"), label .. ": the toggle's tick")
  assertEqual(textColor(TL.title), want("text.heading"), label .. ": the title")
  assertEqual(textColor(TL.hint), want("text.disabled"), label .. ": the hint")
  assertEqual(texColor(TL.stripAxis), want("chart.axis"), label .. ": the strip's axis")
end

test("skin timeline: Ka0s Default draws today's toggle, header and strip; the series are the skin's", function()
  withTimeline(function()
    assertTimeline(today, "Ka0s Default")
    assertEqual(seriesColor(NS.TimelineModel.TOTAL), rgba({ 1, 0.82, 0, 1 }), "the Total's gold")
    assertEqual(seriesColor(NS.Constants.WARBAND_HOLDER), rgba({ 0.25, 0.75, 0.95, 1 }), "the Warband's blue")
    assertTrue(TL.chart.__opts.owner == OWNER, "the line chart is skinned for this addon")
  end)
end)

test("skin timeline: a switch repaints the toggle, header and strip and rebuilds the series", function()
  withTimeline(function()
    NS.ApplySkinChoice("ka0s", "azeroth")
    assertMoves({ "btn.bg", "check.bg", "text.heading", "text.disabled", "chart.axis" }, today)
    assertTimeline(tokenOf, "Azeroth")
    assertEqual(seriesColor(NS.TimelineModel.TOTAL), tokenOf("chart.total"), "the Total follows the skin")
    assertEqual(seriesColor(NS.Constants.WARBAND_HOLDER), tokenOf("sem.warband"), "the Warband follows the skin")
    NS.ApplySkinChoice("ka0s", "ka0s")
    assertTimeline(today, "back on Ka0s Default")
  end)
end)

-- ── Holdings ────────────────────────────────────────────────────────────────────────────────────

local HT = NS.HoldingsTab
local HT_KEYS = { "pane", "header", "scroll", "content", "rows", "_rowList", "_visible", "_headerText" }

local function withHoldings(fn)
  local g = NS.db.global
  local holdings, expanded = g.holdings, HT.expanded
  g.holdings = {}
  local now = os.time()
  NS.Holdings:ApplyMoney("Mock-Realm", 70000, now)
  NS.Holdings:ApplyMoney(NS.Constants.WARBAND_HOLDER, 10000, now - 3 * 86400)
  HT.expanded = { g = true }
  local ok, err = pcall(unfiltered, "Holdings", function()
    withFresh(HT, HT_KEYS, function(pane) HT:Attach(pane) end, fn)
  end)
  g.holdings, HT.expanded = holdings, expanded
  if not ok then error(err, 0) end
end

-- Collapse the thing: its two holder rows go back to the pool's free list, so a walk has both lists.
local function park()
  HT.expanded = {}
  HT:Refresh()
end

local function holderRow(holder)
  for _, row in ipairs(HT.rows.active) do
    if row.line and row.line.holder == holder then return row end
  end
end

local function assertHoldings(want, label)
  for key, b in pairs(HT.header.cells) do
    assertEqual(textColor(b.fs), want("list.header.text"), label .. ": header " .. key)
  end
  local r, g, b = Skin:Color(OWNER, "list.header.text")
  local arrow = NS.IconMarkup("sort-up", "Interface\\Buttons\\Arrow-Up-Up", 0, r, g, b)
  assertTrue(rawget(HT.header.cells.name.fs, "__text"):find(arrow, 1, true) ~= nil, label .. ": the sort arrow")
  local all = {}
  for _, row in ipairs(HT.rows.active) do all[#all + 1] = row end
  for _, row in ipairs(HT.rows.free) do all[#all + 1] = row end
  assertTrue(#HT.rows.free >= 1 and #all >= 2, label .. ": the fixture parked no row")
  for i, row in ipairs(all) do
    assertEqual(texColor(row.stripe), want("list.stripe"), label .. ": row " .. i .. " stripe")
    assertEqual(texColor(row.hl), want("list.hover"), label .. ": row " .. i .. " hover")
    assertEqual(textColor(row.detail), want("text.disabled"), label .. ": row " .. i .. " container split")
  end
  local thing = HT.rows.active[1]
  assertEqual(textColor(thing.cells.total), want("text.highlight"), label .. ": a thing's default cell")
end

test("skin holdings: Ka0s Default draws today's header, arrows, rows and cells", function()
  withHoldings(function()
    local wb = holderRow(NS.Constants.WARBAND_HOLDER)
    assertTrue(wb ~= nil, "the Warband's holder line")
    assertEqual(textColor(wb.cells.name), today("sem.warbandAlt"), "the Warband's lighter blue")
    assertEqual(textColor(wb.cells.value), today("text.disabled"), "a stale age")
    assertEqual(textColor(holderRow("Mock-Realm").cells.value), rgba({ 0.85, 0.85, 0.85 }), "a fresh age")
    park()
    assertHoldings(today, "Ka0s Default")
  end)
end)

test("skin holdings: a switch rebuilds the arrows and repaints every pooled row live", function()
  withHoldings(function()
    park()
    NS.ApplySkinChoice("ka0s", "azeroth")
    assertMoves({ "list.header.text", "list.stripe", "list.hover", "text.disabled", "text.highlight" }, today)
    assertHoldings(tokenOf, "Azeroth")
    NS.ApplySkinChoice("ka0s", "ka0s")
    assertHoldings(today, "back on Ka0s Default")
  end)
end)

-- ── the AH price table (settings/Panel.lua) ─────────────────────────────────────────────────────

local function withAuctionTable(fn)
  reset()
  local ctx = NS.Panel.general
  local savedAvail = NS.AuctionPrice.IsProviderAvailable
  local savedCapture = NS.Schema:Get("settings.auction.capture")
  NS.AuctionPrice.IsProviderAvailable = function(_, prov) return prov == "tsm" end
  NS.Schema:Set("settings.auction.capture", { ["tsm:dbmarket"] = true })
  local ok, err = pcall(function()
    PS.clickTab(mocks.__subcategories["General"], ctx, PS.tabAt("AH price"))
    for _, r in ipairs(ctx._priRows) do
      rawset(r.info.tex, "SetVertexColor", function(self, a, b, c) self.__vc = { a, b, c }; return self end)
    end
    -- Parked: another tab is on screen when the skin moves (the host is repainted all the same).
    PS.homeTab(ctx)
    fn(ctx)
  end)
  NS.AuctionPrice.IsProviderAvailable = savedAvail
  NS.Schema:Set("settings.auction.capture", savedCapture)
  PS.homeTab(ctx)
  reset()
  if not ok then error(err, 0) end
end

local function rowFor(ctx, tag)
  for _, r in ipairs(ctx._priRows) do if r._tag == tag then return r end end
end

local function assertAuction(ctx, want, label)
  for i, fs in ipairs(ctx._priHeads) do
    assertEqual(rgba(rawget(fs, "__color")), want("text.headingAlt"), label .. ": header " .. i)
  end
  local live, idle, absent = rowFor(ctx, "tsm:dbmarket"), rowFor(ctx, "tsm:dbminbuyout"), rowFor(ctx, "oribos:market")
  assertEqual(rgba(rawget(live.addon, "__color")), want("text.bodyAlt"), label .. ": a live addon name")
  assertEqual(rgba(rawget(live.module, "__color")), want("text.body"), label .. ": a live module")
  assertEqual(rgba(rawget(idle.addon, "__color")), want("text.disabled"), label .. ": an idle row")
  assertEqual(rgba(rawget(live.status, "__color")), want("sem.statusOk"), label .. ": collecting")
  assertEqual(rgba(rawget(idle.status, "__color")), want("sem.statusWarn"), label .. ": not collecting")
  assertEqual(rgba(rawget(absent.status, "__color")), want("sem.statusBad"), label .. ": not installed")
  assertEqual(rgba(live.info.tex.__vc), want("icon.hot"), label .. ": a live info mark")
  assertEqual(rgba(idle.info.tex.__vc), want("icon.dim"), label .. ": an idle info mark")
  local r, g, b = Skin:Color(OWNER, "sem.statusOk")
  assertEqual(rawget(live.tick, "__text"), NS.IconMarkup("circle-check", "Interface\\RaidFrame\\ReadyCheck-Ready", 16, r, g, b),
    label .. ": the collecting tick's tint")
end

test("skin AH table: a switch repaints the parked host, ticks rebuilt, and Ka0s Default puts it back", function()
  withAuctionTable(function(ctx)
    assertAuction(ctx, today, "Ka0s Default")
    NS.ApplySkinChoice("ka0s", "azeroth")
    assertMoves({ "text.headingAlt", "text.bodyAlt", "text.body", "text.disabled", "sem.statusOk" }, today)
    assertAuction(ctx, tokenOf, "Azeroth")
    NS.ApplySkinChoice("ka0s", "ka0s")
    assertAuction(ctx, today, "back on Ka0s Default")
  end)
end)

-- ── the degraded facade ─────────────────────────────────────────────────────────────────────────

test("skin insights: the degraded facade draws the KPI card and the list panel today's way", function()
  local dns, _, dm = dofile("tests/degraded_env.lua")()
  local function frame()
    local f = dm.CreateFrame("Frame", nil, dm.UIParent, "BackdropTemplate")
    local seen = {}
    rawset(f, "SetBackdrop", function(_, t) seen.bd = t end)
    rawset(f, "SetBackdropColor", function(_, ...) seen.fill = rgba({ ... }) end)
    rawset(f, "SetBackdropBorderColor", function(_, ...) seen.edge = rgba({ ... }) end)
    return f, seen
  end
  local card, c = frame()
  local num = { SetTextColor = function(self, ...) self.c = rgba({ ... }) end }
  dns.Skin.Card(card, { title = num })
  assertEqual(c.bd and c.bd.insets and c.bd.insets.left, 1, "the WHITE8X8 box, inset by one")
  assertEqual(c.fill, today("card.bg")); assertEqual(c.edge, today("card.border"))
  assertEqual(num.c, today("text.heading"), "the headline")
  local panel, p = frame()
  dns.Skin.Panel(panel)
  assertEqual(p.fill, today("panel.bg")); assertEqual(p.edge, today("panel.border"))
  assertEqual(dns.LedgerFormat.SignedCount(3), "|cff40ff40+3|r", "the signed bytes degraded too")
end)
