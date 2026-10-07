local _, NS = ...
NS.Timeline = NS.Timeline or {}
local TL = NS.Timeline

-- The Timeline tab (timeline-ledger spec §8.1): one thing over time, a Total line and a line per
-- holder, an in/out bar strip under the plot, a legend and a hover tooltip. Every number comes from
-- NS.TimelineModel.Build; this file paints it. The chart itself is LibKa0s's (NS.MakeLineChart).
--
-- The THING is picked with the browser's shared Search box: its autocomplete (P9, the same list
-- every tab wears, modules/BrowserFilterBar.lua) offers matching things through this tab's
-- `suggest` (what is held now, plus anything the rollup has a day for, Gold first), and a pick
-- charts it, leaves the thing's name in Search and is remembered in the Timeline's saved view.
--
-- Each line can be hidden (spec §8.1, P8): a legend entry is a button that toggles its line, and the
-- header's "Total only" toggle hides every holder at once. The per-line hidden set is session-only and
-- keyed by holder, so it outlives a change of thing or range; "Total only" is remembered in the saved
-- view. The in/out strip stays the Total's whatever is hidden.

local TM = NS.TimelineModel
local DAY = 86400
local BAR_H, STRIP_H, LEGEND_H, SUGGEST_MAX, LEGEND_W, GAP = 22, 56, 16, 8, 120, 6
-- LEGEND_W is the Total's legend slot and the widest a holder's label is drawn; LEGEND_GAP is the one
-- gap between every other entry (P10).
local LEGEND_GAP = 16
local WHITE = "Interface\\Buttons\\WHITE8X8"
local TOTAL = TM.TOTAL
local EMPTY_TEXT = "All lines hidden — click a legend entry to show it."
local DIM_ALPHA = 0.4

TL.hidden = TL.hidden or {}

-- Test mode charts the sample, which holds only sample things: a pick made there is session-only
-- (testThing, never the saved view), and with nothing valid picked the sample's default item opens.
local function sampleHas(key)
  local d = NS.State.testDaily
  if not (d and key) then return false end
  for _, holders in pairs(d) do
    for _, things in pairs(holders) do
      if things[key] then return true end
    end
  end
  return false
end

function TL:Thing()
  if NS.State.testDaily then
    if sampleHas(self.testThing) then return self.testThing end
    local real = self.thing or (NS.Browser and NS.Browser.ViewField and NS.Browser:ViewField("timelineThing", "Timeline"))
    if sampleHas(real) then return real end
    return NS.TestData.DefaultTimelineThing() or "g"
  end
  self.testThing = nil
  if self.thing then return self.thing end
  local v = NS.Browser and NS.Browser.ViewField and NS.Browser:ViewField("timelineThing", "Timeline")
  return v or "g"
end

function TL:SetThing(key, quiet)
  if NS.State.testDaily then
    self.testThing = key
  else
    self.thing = key
    if NS.Browser and NS.Browser.SetViewField then NS.Browser:SetViewField("timelineThing", key, "Timeline") end
  end
  if not quiet then self:RefreshIfShown() end
end

-- ── line visibility ──

-- The remembered toggle. Under it every holder is hidden whatever the session set says, so turning it
-- off hands back exactly the set that was shown before it went on.
local function totalOnly()
  return NS.Browser and NS.Browser.ViewField and NS.Browser:ViewField("timelineTotalOnly", "Timeline") == true
end

local function setTotalOnlyField(on)
  if NS.Browser and NS.Browser.SetViewField then NS.Browser:SetViewField("timelineTotalOnly", on, "Timeline") end
end

function TL:IsHidden(key)
  if totalOnly() then return key ~= TOTAL end
  return self.hidden[key] == true
end

-- The set handed to the model: only the keys this chart draws, so an absent holder never counts.
function TL:HiddenSet()
  local out = {}
  for _, s in ipairs(self.model and self.model.series or {}) do
    if self:IsHidden(s.holder) then out[s.holder] = true end
  end
  return out
end

-- What the toggle reads as: the Total drawn and every holder in this chart hidden, however it got so.
function TL:TotalOnlyShown()
  if not self.model then return totalOnly() end
  for _, s in ipairs(self.model.series) do
    if (s.holder == TOTAL) == self:IsHidden(s.holder) then return false end
  end
  return true
end

function TL:SetTotalOnly(on)
  setTotalOnlyField(on and true or false)
  -- Off with the session set itself hiding every holder (they were hidden by hand): show them, or
  -- the toggle would read as off and change nothing.
  if not on and self:TotalOnlyShown() then
    for _, s in ipairs(self.model.series) do
      if s.holder ~= TOTAL then self.hidden[s.holder] = nil end
    end
  end
  self:Refresh()
end

-- A legend click. Under Total only the click first turns what is shown into the session set, so the
-- one line clicked changes and every other stays as it was.
function TL:ToggleSeries(key)
  if totalOnly() then
    for _, s in ipairs(self.model and self.model.series or {}) do
      self.hidden[s.holder] = (s.holder ~= TOTAL) or nil
    end
  end
  self.hidden[key] = (not self.hidden[key]) or nil
  -- Cleared first so the reading below is of the session set alone; a click that leaves every holder
  -- hidden and the Total drawn turns the remembered toggle on.
  setTotalOnlyField(false)
  setTotalOnlyField(self:TotalOnlyShown())
  self:Refresh()
end

-- ── pooled pieces ──

-- ReleaseAll's per-bar hook: a parked bar must not keep the day it last showed.
local function clearFlow(bar) bar.flow = nil end

-- And the legend's: a parked entry must not keep the line it last named, so a hovered entry the
-- rebuild leaves unbound reads as such (TL:RefreshLegendTip).
local function clearLegend(e) e.key, e.label = nil, nil end

-- A day's column is its own hover region: the frame spans the strip's full height and the day's
-- width, so the gain bar, the loss bar and the gap between them all hover it, and it is pooled with
-- the bars it holds. The strip sits below the chart, so this never meets the chart's crosshair.
local function makeFlowBar(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.up = f:CreateTexture(nil, "ARTWORK")
  f.down = f:CreateTexture(nil, "ARTWORK")
  f:EnableMouse(true)
  f:SetScript("OnEnter", function(self2) TL:ShowFlowTip(self2) end)
  f:SetScript("OnLeave", function() TL:HideFlowTip() end)
  return f
end

local function makeLegendEntry(parent)
  local f = CreateFrame("Button", nil, parent)
  f:SetSize(LEGEND_W, LEGEND_H)
  f.fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.fs:SetPoint("LEFT", 0, 0); f.fs:SetWidth(LEGEND_W - 4); f.fs:SetWordWrap(false); f.fs:SetJustifyH("LEFT")
  f:SetScript("OnClick", function(self2) TL:ToggleSeries(self2.key) end)
  f:SetScript("OnEnter", function(self2) TL:ShowLegendTip(self2) end)
  f:SetScript("OnLeave", function() TL:HideLegendTip() end)
  return f
end

-- The house's flat bar-button skin (BrowserFilterBar's makeBarButton) with a box that fills gold when
-- on. A plain Button rather than a CheckButton: the state is derived (TL:TotalOnlyShown), so the
-- button only ever paints it.
local function makeToggle(parent, text, onClick, tip)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(84, 18)
  b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                  insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  b:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
  b:SetBackdropBorderColor(0.24, 0.24, 0.27, 0.9)
  b.box = b:CreateTexture(nil, "ARTWORK")
  b.box:SetSize(10, 10); b.box:SetPoint("LEFT", 6, 0)
  b.box:SetColorTexture(0.24, 0.24, 0.27, 1)
  b.tick = b:CreateTexture(nil, "OVERLAY")
  b.tick:SetSize(6, 6); b.tick:SetPoint("CENTER", b.box, "CENTER", 0, 0)
  b.tick:SetColorTexture(1, 0.82, 0, 1)
  b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.fs:SetPoint("LEFT", b.box, "RIGHT", 5, 0)
  b.fs:SetText(text)
  function b:SetChecked(on)
    self.checked = on and true or false
    self.tick:SetShown(self.checked)
  end
  b:SetChecked(false)
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self2)
    b.fs:SetTextColor(1, 0.82, 0)
    NS.Compat.ShowTextTooltip(self2, text, tip, "ANCHOR_BOTTOM")
  end)
  b:SetScript("OnLeave", function() b.fs:SetTextColor(1, 1, 1); NS.Compat.HideTooltip() end)
  return b
end

-- ── build ──

local function buildHeader(self, pane)
  local bar = CreateFrame("Frame", nil, pane)
  bar:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0); bar:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, 0)
  bar:SetHeight(BAR_H)
  self.title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  self.title:SetPoint("LEFT", 4, 0)
  self.totalOnlyBtn = makeToggle(bar, "Total only", function() TL:SetTotalOnly(not TL:TotalOnlyShown()) end,
    "Hide every character's line and keep the Total. Turn it off to bring back the lines shown before.")
  self.totalOnlyBtn:SetPoint("LEFT", self.title, "RIGHT", 10, 0)
  local hint = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("LEFT", self.totalOnlyBtn, "RIGHT", 10, 0)
  hint:SetText("Type in Search to chart an item or currency.")
  self.bar = bar
end

-- The strip and the chart sit above the legend, which grows a row for each wrap (P10), so both are
-- re-anchored whenever its height changes.
local function anchorBody(self, legendH)
  if self.legendH == legendH then return end
  self.legendH = legendH
  self.legend:SetHeight(legendH)
  self.strip:ClearAllPoints()
  self.strip:SetPoint("BOTTOMLEFT", self.pane, "BOTTOMLEFT", 0, legendH + GAP)
  self.strip:SetPoint("BOTTOMRIGHT", self.pane, "BOTTOMRIGHT", -4, legendH + GAP)
  if self.chart then
    self.chart:ClearAllPoints()
    self.chart:SetPoint("TOPLEFT", self.bar, "BOTTOMLEFT", 0, -4)
    self.chart:SetPoint("BOTTOMRIGHT", self.pane, "BOTTOMRIGHT", -4, STRIP_H + legendH + 2 * GAP)
  end
end

local function buildBody(self, pane)
  self.strip = CreateFrame("Frame", nil, pane)
  self.strip:SetHeight(STRIP_H)
  self.stripAxis = self.strip:CreateTexture(nil, "ARTWORK")
  self.stripAxis:SetColorTexture(0.45, 0.45, 0.5, 0.8)
  self.stripPool = NS.Pool.New()
  self.legend = CreateFrame("Frame", nil, pane)
  self.legend:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 0)
  self.legend:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -4, 0)
  self.legendPool = NS.Pool.New()
  self.legendH = nil
  anchorBody(self, LEGEND_H)
end

function TL:Attach(pane)
  if self.pane then return end
  self.pane = pane
  self.hidden = self.hidden or {}
  buildHeader(self, pane)
  self.chart = NS.MakeLineChart(pane, {
    onHover = function(_, i) TL:OnHover(i) end,
    formatY = function(v) return TL:FormatAxis(v) end,
    pxPerPoint = NS.Constants.TIMELINE.PX_PER_POINT,
  })
  if self.chart then
    self.emptyMsg = self.chart:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.emptyMsg:SetPoint("CENTER")
    self.emptyMsg:SetText(EMPTY_TEXT)
    self.emptyMsg:Hide()
  else
    -- Degraded install: say why, draw nothing else (core/WidgetsSetup.lua's header).
    self.missing = pane:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.missing:SetPoint("CENTER")
    self.missing:SetText(NS.LIBKA0S_MISSING .. ", and the Timeline needs it to draw.")
  end
  buildBody(self, pane)
  pane:SetScript("OnSizeChanged", function(_, w, h) TL:Layout(w, h) end)
  self:Refresh()
end

-- ── refresh / layout ──

local function ledgerOn()
  local s = NS.db and NS.db.profile and NS.db.profile.settings
  return not s or s.trackLedger ~= false
end

-- In test mode the sample stands in for the rollup and the rows (NS.Rollup:ActiveStore and
-- Database:ActiveHistory); it has no ledgerSince, so it draws no marker and stays on daily points.
function TL:Params(f)
  local g, s = NS.db.global, NS.db.profile.settings
  local sample = NS.State.testDaily ~= nil
  return { thing = self:Thing(), range = NS.Browser:DateRange(), from = f.from, now = time(),
    allowed = f.char, maxLines = s.timelineMaxLines or 8, daily = NS.Rollup:ActiveStore(),
    history = NS.Database:ActiveHistory(), ledgerSince = (not sample) and g.ledgerSince or nil,
    retentionDays = g.retentionDays or 0 }
end

function TL:Refresh()
  if not self.pane then return end
  local f = NS.Browser:CurrentFilter("Timeline")
  if not (self.chart and ledgerOn()) then
    self.model = nil
    self.title:SetText(self.chart and "Turn on ledger tracking (Settings, Capture) to see the Timeline." or "")
    self.totalOnlyBtn:Hide()
    if self.chart then self.chart:Clear(); self.emptyMsg:Hide() end
    NS.Pool.ReleaseAll(self.stripPool, clearFlow); NS.Pool.ReleaseAll(self.legendPool, clearLegend)
    self.legendButtons = {}
    self:HideFlowTip(); self:HideLegendTip()
    return
  end
  self.model = TM.Build(self:Params(f))
  self.title:SetText(self.model.title or "")
  self.totalOnlyBtn:Show()
  self.totalOnlyBtn:SetChecked(self:TotalOnlyShown())
  -- The chart re-fires onHover only when the nearest index CHANGES, so a hover left up across a live
  -- repaint would keep the old model's tooltip and crosshair. Dropping it here lets the armed OnUpdate
  -- hover again against the new data on the next frame.
  self.chart:ClearHover()
  -- Every line hidden: no data at all, so the chart draws no axes (a zero-range y would be meaningless)
  -- and the message says how to get a line back. The legend stays.
  local allHidden = self:VisibleSeriesCount() == 0
  self.emptyMsg:SetShown(allHidden)
  if allHidden then self.chart:Clear() else self.chart:SetData(TM.ChartData(self.model, self:HiddenSet())) end
  self:Layout()
end

-- IsVisible, not IsShown, as HoldingsTab's live handler does: closing the browser with the Timeline
-- as the last tab leaves the pane SHOWN inside a hidden window, and every Reconciler flush would then
-- rebuild the model off screen.
function TL:RefreshIfShown()
  if self.pane and self.pane:IsVisible() then self:Refresh() end
end

function TL:Layout(w, h)
  if not (self.pane and self.chart and self.model) then return end
  w = w or self.pane:GetWidth() or 0
  h = h or self.pane:GetHeight() or 0
  self.chartW = w - 4
  -- The legend first: how many rows it wraps to decides how tall the plot can be.
  local legendH = self:RenderLegend() * LEGEND_H
  anchorBody(self, legendH)
  self.chart:Render(self.chartW, h - BAR_H - 4 - STRIP_H - legendH - 2 * GAP)
  self:RenderStrip()
end

function TL:FormatAxis(v)
  if self.model and self.model.kind == "GOLD" then return tostring(v) .. "g" end
  return tostring(v)
end

local function paintFlow(bar, f, peak, half, w)
  local C = NS.Constants.TIMELINE
  bar.up:ClearAllPoints(); bar.down:ClearAllPoints()
  bar.up:SetColorTexture(C.GAIN[1], C.GAIN[2], C.GAIN[3], 0.9)
  bar.down:SetColorTexture(C.LOSS[1], C.LOSS[2], C.LOSS[3], 0.9)
  bar.up:SetPoint("BOTTOMLEFT", bar, "LEFT", 0, 1)
  bar.up:SetSize(w, math.max(f.i > 0 and 1 or 0, f.i / peak * half))
  bar.up:SetShown(f.i > 0)
  bar.down:SetPoint("TOPLEFT", bar, "LEFT", 0, -1)
  bar.down:SetSize(w, math.max(f.o > 0 and 1 or 0, f.o / peak * half))
  bar.down:SetShown(f.o > 0)
end

-- The strip's x mapping: the chart's own while it has a plot. With every line hidden the chart is
-- cleared (no axes) and has none, but the strip is the Total's flow and stays, so it takes the same
-- mapping from the chart's published paddings and the width Layout last rendered at.
local function stripScale(self)
  local c, m = self.chart, self.model
  local left, _, pw = c:GetPlotRect()
  if left then return left, pw, c:XToPixel(m.xMin), c:XToPixel(m.xMax) end
  local LC = NS.LineChartChrome()
  if not (LC and self.chartW and m.xMin and m.xMax) then return nil end
  pw = math.max(0, self.chartW - LC.PAD_LEFT - LC.PAD_RIGHT)
  return LC.PAD_LEFT, pw, LC.PAD_LEFT, LC.PAD_LEFT + pw
end

function TL:RenderStrip()
  NS.Pool.ReleaseAll(self.stripPool, clearFlow)
  local m = self.model
  local left, pw, px0, px1 = stripScale(self)
  if not (left and pw and pw > 0) then self:RefreshFlowTip(); return end
  local span = m.xMax - m.xMin
  local function toPx(x) return span == 0 and px0 or px0 + (x - m.xMin) / span * (px1 - px0) end
  self.stripAxis:ClearAllPoints()
  self.stripAxis:SetPoint("LEFT", self.strip, "LEFT", left, 0)
  self.stripAxis:SetSize(pw, 1)
  local peak = 0
  for _, f in ipairs(m.flows) do peak = math.max(peak, f.i, f.o) end
  if peak == 0 then self:RefreshFlowTip(); return end
  local dayPx = math.max(2, math.min(24, toPx(m.xMin + DAY) - toPx(m.xMin) - 1))
  for _, f in ipairs(m.flows) do
    local bar = NS.Pool.Acquire(self.stripPool, function() return makeFlowBar(self.strip) end)
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", self.strip, "BOTTOMLEFT", toPx(f.x), 0)
    bar:SetSize(dayPx, STRIP_H)
    paintFlow(bar, f, peak, STRIP_H / 2 - 2, dayPx)
    bar.flow = f
  end
  self:RefreshFlowTip()
end

-- ── the strip's tooltip ──

function TL:ShowFlowTip(bar)
  local h = self.model and TM.FlowLines(self.model, bar.flow)
  if not h then self:HideFlowTip(); return end
  self.flowTipOwner, self.legendTipOwner = bar, nil
  NS.Compat.ShowLinesTooltip(bar, h.title, h.rows, "ANCHOR_CURSOR")
end

function TL:HideFlowTip()
  if not self.flowTipOwner then return end
  self.flowTipOwner = nil
  NS.Compat.HideTooltip()
end

-- A live repaint under a resting cursor: the column keeps its day (the pool hands each bar back to
-- the rank it held), so its tooltip is redrawn on the new numbers; a column whose day lost its flow
-- went back to the pool, and its tooltip goes with it.
function TL:RefreshFlowTip()
  local bar = self.flowTipOwner
  if not bar then return end
  if bar.flow and bar:IsShown() then self:ShowFlowTip(bar) else self:HideFlowTip() end
end

-- A label's drawn width, capped at the slot it had before P10. A client (or the headless mock) that
-- measures nothing falls back to the cap, so the entries keep their old pitch rather than collapse.
local function labelWidth(e)
  local w = e.fs.GetUnboundedStringWidth and e.fs:GetUnboundedStringWidth() or 0
  if not w or w <= 0 then return LEGEND_W - 4 end
  return math.min(math.ceil(w), LEGEND_W - 4)
end

-- Total first in the legend (it is drawn last, on top of the chart). Every line keeps its entry and
-- its place when hidden; a hidden one is dimmed gray. Entries are as wide as their labels and one even
-- gap apart, the Total keeping its slot (TM.LegendLayout); answers the number of rows they wrap to.
function TL:RenderLegend()
  NS.Pool.ReleaseAll(self.legendPool, clearLegend)
  self.legendButtons = {}
  local s = self.model.series
  local order = { s[#s] }
  for i = 1, #s - 1 do order[#order + 1] = s[i] end
  local widths = {}
  for i, sr in ipairs(order) do
    local e = NS.Pool.Acquire(self.legendPool, function() return makeLegendEntry(self.legend) end)
    e.key, e.label = sr.holder, sr.label
    e.fs:SetText(sr.label)
    if self:IsHidden(sr.holder) then
      e.fs:SetTextColor(0.5, 0.5, 0.5, DIM_ALPHA)
    else
      e.fs:SetTextColor(sr.color[1], sr.color[2], sr.color[3], 1)
    end
    widths[i] = labelWidth(e)
    e.fs:SetWidth(widths[i]); e:SetSize(widths[i], LEGEND_H)
    self.legendButtons[i] = e
  end
  local pos, rows = TM.LegendLayout(widths, LEGEND_W, LEGEND_GAP, self.chartW)
  for i, e in ipairs(self.legendButtons) do
    e:ClearAllPoints()
    e:SetPoint("TOPLEFT", self.legend, "TOPLEFT", pos[i].x, -(pos[i].row - 1) * LEGEND_H)
  end
  self:RefreshLegendTip()
  return math.max(1, rows)
end

-- The entry's line in its own color, what that holder holds of the thing now, and the click hint
-- (TM.LegendTip). Drawn by the amount-tooltip shim: a colored title, one label/value line, a gray hint.
function TL:ShowLegendTip(btn)
  if not btn.key then self:HideLegendTip(); return end
  self.legendTipOwner, self.flowTipOwner = btn, nil
  local t = TM.LegendTip(self.model, btn.key)
  if not t then
    NS.Compat.ShowTextTooltip(btn, btn.label, "Click to hide/show", "ANCHOR_TOP")
    return
  end
  NS.Compat.ShowAmountTooltip(btn, t.title, t.color, t.label, t.value, t.hint, "ANCHOR_TOP")
end

function TL:HideLegendTip()
  if not self.legendTipOwner then return end
  self.legendTipOwner = nil
  NS.Compat.HideTooltip()
end

-- A click or a live repaint under a resting cursor: the cursor never left the entry, so no OnEnter
-- comes, and the pool may have handed that frame another line (the ranks follow the series order,
-- which a filter or a new holder shifts). Re-shown for the line the entry names now; an entry the
-- rebuild left unbound went back to the pool, and its tooltip goes with it. Only a tooltip the legend
-- owns is touched, so this costs nothing on a repaint nobody is hovering.
function TL:RefreshLegendTip()
  local btn = self.legendTipOwner
  if not btn then return end
  if btn.key and btn:IsShown() then self:ShowLegendTip(btn) else self:HideLegendTip() end
end

-- ── the picker: this tab's half of the Search autocomplete ──
-- The list itself is the browser's (NS.MakeAutocomplete on the shared Search box); this tab answers
-- what it offers (TL.Suggest) and what a pick does (TL:Pick), through its tab spec.

local function pickerThings(text)
  local out, seen = {}, {}
  for _, r in ipairs(NS.Holdings:Search({ text = text })) do
    out[#out + 1] = { key = r.key, name = r.name, total = r.total, quality = r.quality }
    seen[r.key] = true
  end
  for key in pairs(NS.Rollup and NS.Rollup:Keys() or {}) do
    if not seen[key] then
      local d = NS.Holdings:Describe(key)
      out[#out + 1] = { key = key, name = d.name, total = 0, quality = d.quality }
    end
  end
  return out
end

--- The things matching `text`, as autocomplete rows: Gold first, then the biggest totals
--- (TM.Suggest), each in its quality's color. `value` is the thing key a pick charts.
function TL.Suggest(text)
  local t = (text or ""):match("^%s*(.-)%s*$") or ""
  if t == "" then return {} end
  local out = {}
  for i, th in ipairs(TM.Suggest(t, pickerThings(t), SUGGEST_MAX)) do
    out[i] = { text = th.name, value = th.key, color = NS.Browser._qualityColorOrNil(th.quality) }
  end
  return out
end

--- A pick charts the thing and leaves its name in Search. Setting the name re-applies the shared
--- filter, which repaints this tab already; a name Search already held repaints here instead.
function TL:Pick(item)
  if not (item and item.value) then return end
  self:SetThing(item.value, true)
  if not NS.Browser:SetSearchText(item.text or "") then self:Refresh() end
end

-- ── hover ──

function TL:OnHover(i)
  if not GameTooltip then return end
  local h = i and self.model and TM.HoverLines(self.model, i, self:HiddenSet())
  -- The chart reports its hover ending a frame after the cursor has left the plot, by which time
  -- the cursor may be on the strip below and the strip's tooltip up: only the chart's own goes.
  if not h then
    if GameTooltip:GetOwner() == self.chart then GameTooltip:Hide() end
    return
  end
  local C = NS.Constants.TIMELINE
  -- the tooltip is the chart's now; a strip or legend repaint must not take it back
  self.flowTipOwner, self.legendTipOwner = nil, nil
  GameTooltip:SetOwner(self.chart, "ANCHOR_CURSOR")
  GameTooltip:SetText(h.title, 1, 0.82, 0)
  for _, r in ipairs(h.rows) do
    GameTooltip:AddDoubleLine(r.label, r.text, r.color[1], r.color[2], r.color[3], 1, 1, 1)
  end
  GameTooltip:AddDoubleLine("Gained", h.gain, C.GAIN[1], C.GAIN[2], C.GAIN[3], C.GAIN[1], C.GAIN[2], C.GAIN[3])
  GameTooltip:AddDoubleLine("Lost", h.loss, C.LOSS[1], C.LOSS[2], C.LOSS[3], C.LOSS[1], C.LOSS[2], C.LOSS[3])
  GameTooltip:Show()
end

function TL:VisibleSeriesCount()
  if not self.model then return 0 end
  return #TM.Visible(self.model.series, self:HiddenSet())
end

-- ── lifecycle ──

--- One coalesced repaint for both messages: the Reconciler sends HOLDINGS_CHANGED once per holder in
--- a flush (Reconciler.lua's Flush), and a loot burst sends RECORD_ADDED per record, so either one
--- uncoalesced would rebuild the whole model several times for one change. Coalesced through
--- NS.After (the same trigger the Browser and Insights use), so a repaint in flight at stand-down
--- is canceled rather than left armed; and it paints only while the pane is visible.
function TL:Enable()
  if self.__ev or not NS.bus then return end
  self.__ev = NS.NewBusTarget()
  local live = NS.Coalesce(function() TL:RefreshIfShown() end, NS.Constants.RECORD_ADDED_COALESCE)
  self.__ev:RegisterMessage(NS.MSG.HOLDINGS_CHANGED, live)
  self.__ev:RegisterMessage(NS.MSG.RECORD_ADDED, live)
end

--- The stand-down half (slash-commands-§7): the private bus target goes wholesale, and a tooltip
--- this tab owns goes with it.
function TL:Disable()
  if not self.__ev then return end
  self.__ev:UnregisterAllMessages()
  self.__ev:UnregisterAllEvents()
  self.__ev = nil
  if GameTooltip and self.chart and GameTooltip:GetOwner() == self.chart then GameTooltip:Hide() end
  self:HideFlowTip()
end

NS.Browser:RegisterTab{ name = "Timeline", order = 30,
  -- The Timeline charts holdings over days: Search picks the thing, Date sets the window and
  -- Character narrows the holders; nothing else describes it (spec §8.0).
  filters = { search = true, date = true, char = true },
  charSource = "holders",
  -- The remembered pick and Total only are written to this tab's saved view as they change (spec
  -- §8.1), so a Save carries them; no view applies them back, which keeps them through Clear (P11).
  captureView = function(v)
    v.timelineThing = NS.Browser:ViewField("timelineThing", "Timeline")
    v.timelineTotalOnly = NS.Browser:ViewField("timelineTotalOnly", "Timeline")
  end,
  suggest = function(text) return TL.Suggest(text) end,
  pick = function(item) TL:Pick(item) end,
  build = function(pane) TL:Attach(pane) end,
  refresh = function() TL:Refresh() end }
