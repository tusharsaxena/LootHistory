local _, NS = ...
NS.Timeline = NS.Timeline or {}
local TL = NS.Timeline

-- The Timeline tab (timeline-ledger spec §8.1): one thing over time, a Total line and a line per
-- holder, an in/out bar strip under the plot, a legend and a hover tooltip. Every number comes from
-- NS.TimelineModel.Build; this file paints it. The chart itself is LibKa0s's (NS.MakeLineChart).
--
-- The THING is picked with the browser's shared Search box: typing offers matching things (what is
-- held now, plus anything the rollup has a day for), clicking one charts it, and the pick is
-- remembered in the saved view.

local TM = NS.TimelineModel
local DAY = 86400
local BAR_H, STRIP_H, LEGEND_H, ROW_H, SUGGEST_MAX, LEGEND_W, GAP = 22, 56, 16, 18, 8, 120, 6
local WHITE = "Interface\\Buttons\\WHITE8X8"

function TL:Thing()
  if self.thing then return self.thing end
  local v = NS.Browser and NS.Browser.ViewField and NS.Browser:ViewField("timelineThing")
  return v or "g"
end

function TL:SetThing(key, quiet)
  self.thing = key
  if NS.Browser and NS.Browser.SetViewField then NS.Browser:SetViewField("timelineThing", key) end
  if not quiet then self:RefreshIfShown() end
end

-- ── pooled pieces ──

local function makeSuggestRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(ROW_H)
  b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.fs:SetPoint("LEFT", 6, 0); b.fs:SetPoint("RIGHT", -6, 0); b.fs:SetJustifyH("LEFT")
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.15)
  b:SetScript("OnClick", function(self2)
    TL:SetThing(self2.key, true)
    -- The pick is made; clearing Search closes the list and re-runs the shared filter once.
    if NS.Browser._search then NS.Browser._search:SetText("") end
    TL:Refresh()
  end)
  return b
end

local function makeFlowBar(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.up = f:CreateTexture(nil, "ARTWORK")
  f.down = f:CreateTexture(nil, "ARTWORK")
  return f
end

local function makeLegendEntry(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(LEGEND_W, LEGEND_H)
  f.fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.fs:SetPoint("LEFT", 0, 0); f.fs:SetWidth(LEGEND_W - 4); f.fs:SetWordWrap(false); f.fs:SetJustifyH("LEFT")
  return f
end

-- ── build ──

local function buildHeader(self, pane)
  local bar = CreateFrame("Frame", nil, pane)
  bar:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0); bar:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, 0)
  bar:SetHeight(BAR_H)
  self.title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  self.title:SetPoint("LEFT", 4, 0)
  local hint = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("LEFT", self.title, "RIGHT", 10, 0)
  hint:SetText("Type in Search to chart an item or currency.")
  self.bar = bar
  local sug = CreateFrame("Frame", nil, pane, "BackdropTemplate")
  sug:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -2); sug:SetWidth(320)
  sug:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  sug:SetBackdropColor(0.06, 0.06, 0.08, 0.98); sug:SetBackdropBorderColor(0.62, 0.5, 0.18, 1)
  -- Above the chart, which is built after it: a raised strata, not a level read off the pane.
  sug:SetFrameStrata("DIALOG")
  sug:Hide()
  self.suggest, self.suggestPool = sug, NS.Pool.New()
end

local function buildBody(self, pane)
  self.strip = CreateFrame("Frame", nil, pane)
  self.strip:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, LEGEND_H + GAP)
  self.strip:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -4, LEGEND_H + GAP)
  self.strip:SetHeight(STRIP_H)
  self.stripAxis = self.strip:CreateTexture(nil, "ARTWORK")
  self.stripAxis:SetColorTexture(0.45, 0.45, 0.5, 0.8)
  self.stripPool = NS.Pool.New()
  self.legend = CreateFrame("Frame", nil, pane)
  self.legend:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 0)
  self.legend:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -4, 0)
  self.legend:SetHeight(LEGEND_H)
  self.legendPool = NS.Pool.New()
end

function TL:Attach(pane)
  if self.pane then return end
  self.pane = pane
  buildHeader(self, pane)
  self.chart = NS.MakeLineChart(pane, {
    onHover = function(_, i) TL:OnHover(i) end,
    formatY = function(v) return TL:FormatAxis(v) end,
  })
  if self.chart then
    self.chart:SetPoint("TOPLEFT", self.bar, "BOTTOMLEFT", 0, -4)
    self.chart:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -4, STRIP_H + LEGEND_H + 2 * GAP)
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

function TL:Params(f)
  local g, s = NS.db.global, NS.db.profile.settings
  return { thing = self:Thing(), range = NS.Browser:DateRange(), from = f.from, now = time(),
    allowed = f.char, maxLines = s.timelineMaxLines or 8, daily = g.daily or {},
    history = NS.Database:History(), ledgerSince = g.ledgerSince, retentionDays = g.retentionDays or 0 }
end

function TL:Refresh()
  if not self.pane then return end
  local f = NS.Browser:CurrentFilter()
  self:RenderSuggestions(f.text)
  if not (self.chart and ledgerOn()) then
    self.model = nil
    self.title:SetText(self.chart and "Turn on ledger tracking (Settings, Capture) to see the Timeline." or "")
    if self.chart then self.chart:Clear() end
    NS.Pool.ReleaseAll(self.stripPool); NS.Pool.ReleaseAll(self.legendPool)
    return
  end
  self.model = TM.Build(self:Params(f))
  self.title:SetText(self.model.title or "")
  -- The chart re-fires onHover only when the nearest index CHANGES, so a hover left up across a live
  -- repaint would keep the old model's tooltip and crosshair. Dropping it here lets the armed OnUpdate
  -- hover again against the new data on the next frame.
  self.chart:ClearHover()
  self.chart:SetData(TM.ChartData(self.model))
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
  self.chart:Render(w - 4, h - BAR_H - 4 - STRIP_H - LEGEND_H - 2 * GAP)
  self:RenderStrip()
  self:RenderLegend()
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

function TL:RenderStrip()
  NS.Pool.ReleaseAll(self.stripPool)
  local m, c = self.model, self.chart
  local left, _, pw = c:GetPlotRect()
  if not (left and pw and pw > 0) then return end
  self.stripAxis:ClearAllPoints()
  self.stripAxis:SetPoint("LEFT", self.strip, "LEFT", left, 0)
  self.stripAxis:SetSize(pw, 1)
  local peak = 0
  for _, f in ipairs(m.flows) do peak = math.max(peak, f.i, f.o) end
  if peak == 0 then return end
  local dayPx = math.max(2, math.min(24, c:XToPixel(m.xMin + DAY) - c:XToPixel(m.xMin) - 1))
  for _, f in ipairs(m.flows) do
    local bar = NS.Pool.Acquire(self.stripPool, function() return makeFlowBar(self.strip) end)
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", self.strip, "BOTTOMLEFT", c:XToPixel(f.x), 0)
    bar:SetSize(dayPx, STRIP_H)
    paintFlow(bar, f, peak, STRIP_H / 2 - 2, dayPx)
  end
end

-- Total first in the legend (it is drawn last, on top of the chart).
function TL:RenderLegend()
  NS.Pool.ReleaseAll(self.legendPool)
  local s = self.model.series
  local order = { s[#s] }
  for i = 1, #s - 1 do order[#order + 1] = s[i] end
  for i, sr in ipairs(order) do
    local e = NS.Pool.Acquire(self.legendPool, function() return makeLegendEntry(self.legend) end)
    e:ClearAllPoints()
    e:SetPoint("LEFT", self.legend, "LEFT", (i - 1) * LEGEND_W, 0)
    e.fs:SetText(sr.label)
    e.fs:SetTextColor(sr.color[1], sr.color[2], sr.color[3])
  end
end

-- ── the picker ──

local function pickerThings(text)
  local out, seen = {}, {}
  for _, r in ipairs(NS.Holdings:Search({ text = text })) do
    out[#out + 1] = { key = r.key, name = r.name, total = r.total }
    seen[r.key] = true
  end
  for key in pairs(NS.Rollup and NS.Rollup:Keys() or {}) do
    if not seen[key] then out[#out + 1] = { key = key, name = NS.Holdings:Describe(key).name, total = 0 } end
  end
  return out
end

function TL:RenderSuggestions(text)
  NS.Pool.ReleaseAll(self.suggestPool)
  self.suggestions = {}
  if not text or text == "" then self.suggest:Hide(); return end
  self.suggestions = TM.Suggest(text, pickerThings(text), SUGGEST_MAX)
  for i, th in ipairs(self.suggestions) do
    local b = NS.Pool.Acquire(self.suggestPool, function() return makeSuggestRow(self.suggest) end)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", self.suggest, "TOPLEFT", 1, -1 - (i - 1) * ROW_H)
    b:SetPoint("RIGHT", self.suggest, "RIGHT", -1, 0)
    b.key = th.key
    b.fs:SetText(th.name)
  end
  self.suggest:SetHeight(#self.suggestions * ROW_H + 2)
  self.suggest:SetShown(#self.suggestions > 0)
end

function TL:SuggestionKeys()
  local out = {}
  for i, th in ipairs(self.suggestions or {}) do out[i] = th.key end
  return out
end

-- ── hover ──

function TL:OnHover(i)
  if not GameTooltip then return end
  local h = i and self.model and TM.HoverLines(self.model, i)
  if not h then GameTooltip:Hide(); return end
  local C = NS.Constants.TIMELINE
  GameTooltip:SetOwner(self.chart, "ANCHOR_CURSOR")
  GameTooltip:SetText(h.title, 1, 0.82, 0)
  for _, r in ipairs(h.rows) do
    GameTooltip:AddDoubleLine(r.label, r.text, r.color[1], r.color[2], r.color[3], 1, 1, 1)
  end
  GameTooltip:AddDoubleLine("Gained", h.gain, C.GAIN[1], C.GAIN[2], C.GAIN[3], C.GAIN[1], C.GAIN[2], C.GAIN[3])
  GameTooltip:AddDoubleLine("Lost", h.loss, C.LOSS[1], C.LOSS[2], C.LOSS[3], C.LOSS[1], C.LOSS[2], C.LOSS[3])
  GameTooltip:Show()
end

function TL:VisibleSeriesCount() return self.model and #self.model.series or 0 end

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
end

NS.Browser:RegisterTab{ name = "Timeline", order = 30,
  -- The Timeline charts holdings over days: Search picks the thing, Date sets the window and
  -- Character narrows the holders; nothing else describes it (spec §8.0).
  filters = { search = true, date = true, char = true },
  charSource = "holders",
  build = function(pane) TL:Attach(pane) end,
  refresh = function() TL:Refresh() end }
