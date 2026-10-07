-- LibKa0s-Widgets-1.0 -- the line chart: one or more series of points drawn as Line regions over
-- a time axis, with auto-scaled y ticks, a dashed vertical marker, a dashed-range style for a part
-- of a series the host wants read as provisional, and a hover crosshair that reports the nearest x.
--
-- -- WHY IT IS A FILE OF ITS OWN AND NOT MORE OF Widgets.lua ------------------------------------
--
-- For the reason WidgetsDragHandle.lua gives: one file per widget keeps each under layout-1's
-- 1500-line cap, and a secondary file paired on the SHELL's minor cannot attach to a shell from
-- another vendored copy without saying so. It is not a major of its own: a new major would cost a
-- setup seam in every consumer, and only one draws a chart today.
--
-- -- WHY THE MATH IS PUBLISHED ------------------------------------------------------------------
--
-- Everything decided without a frame -- the tick ladder, the thinning, the time labels, the
-- nearest x, the dash cutting, the clip to the plot -- is on `lib.ChartMath`, so a library suite
-- pins it with no geometry stub and a host can line its own decorations (a bar strip under the
-- plot) up with the same numbers rather than restating them.
--
-- -- WHAT THE HOST STILL OWNS -------------------------------------------------------------------
--
-- Every string and color it passes, where the chart sits, when it is shown, what a hover means
-- (the widget reports an index; the host draws its own tooltip) and every unit conversion: the
-- widget plots the numbers it is handed.
--
-- Depends on LibStub and on the Widgets shell, and on no addon framework. Reads the client's
-- `date` and `time` for the time axis.

local lib = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
if not lib then return end

local CHART_MINOR = 3
-- Paired on the SHELL's minor as well as this file's own, as WidgetsDragHandle.lua is: a chart that
-- attached to an older shell would publish `lib.LineChart` beside a `lib.MODULES` the shell owns,
-- and nothing would say the two came from different vendored copies.
if lib.__chartMinor and lib.__chartMinor >= CHART_MINOR
  and lib.__chartShellMinor == lib.MINOR then return end
lib.__chartMinor      = CHART_MINOR
lib.__chartShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.WidgetsLineChart = CHART_MINOR

local floor, ceil, max, min, abs, sqrt = math.floor, math.ceil, math.max, math.min, math.abs, math.sqrt
local log10 = math.log10
local DAY = 86400

--- The chart's published chrome. READ, never restated: a host that lines anything up with the plot
--- reads the paddings here (or asks `chart:GetPlotRect()`), so a later minor that moves them moves
--- the host too.
lib.LINE_CHART = {
  PAD_LEFT = 52, PAD_RIGHT = 8, PAD_TOP = 8, PAD_BOTTOM = 18,
  PX_PER_POINT = 2, DASH = 4, GAP = 3, Y_TICKS = 5, X_TICKS = 6, LABEL_GAP = 4,
  AXIS = { 0.45, 0.45, 0.5, 0.8 }, GRID = { 1, 1, 1, 0.07 }, CROSSHAIR = { 1, 1, 1, 0.35 },
  MARKER = { 0.8, 0.8, 0.8, 0.6 }, LINE = { 0.4, 0.6, 0.95, 1 },
}
local LC = lib.LINE_CHART

local Math = {}
lib.ChartMath = Math

-- -- y ticks: the 1 / 2 / 2.5 / 5 ladder -------------------------------------------------------

local function niceStep(span, maxTicks)
  local raw = span / max(1, maxTicks)
  local mag = 10 ^ floor(log10(raw))
  local norm = raw / mag
  if norm <= 1 then return mag end
  if norm <= 2 then return 2 * mag end
  if norm <= 2.5 then return 2.5 * mag end
  if norm <= 5 then return 5 * mag end
  return 10 * mag
end

-- A flat series still needs a span to divide by. A positive flat line is drawn from zero, a
-- negative one up to zero, and an all-zero one over 0..1, so the line sits on a real axis rather
-- than on a degenerate one.
local function widenFlat(lo, hi)
  if hi ~= lo then return lo, hi end
  if lo > 0 then return 0, hi end
  if lo < 0 then return lo, 0 end
  return 0, 1
end

function Math.NiceTicks(lo, hi, maxTicks, integer)
  lo, hi = lo or 0, hi or 0
  if hi < lo then lo, hi = hi, lo end
  lo, hi = widenFlat(lo, hi)
  local step = niceStep(hi - lo, maxTicks or LC.Y_TICKS)
  if integer and step < 1 then step = 1 end
  local niceLo, niceHi = floor(lo / step) * step, ceil(hi / step) * step
  local ticks, n = {}, floor((niceHi - niceLo) / step + 0.5)
  for k = 0, n do ticks[k + 1] = niceLo + k * step end
  return ticks, niceLo, niceHi, step
end

-- -- thinning: Largest-Triangle-Three-Buckets ----------------------------------------------------
--
-- A balance line is mostly flat with steps and spikes, and a spike is the thing a player is looking
-- for. Averaging or taking every Nth point erases it; LTTB keeps, per bucket, the point that spans
-- the largest triangle with its neighbors, so a one-point spike survives (pinned).

function Math.Budget(plotWidth, pxPerPoint)
  local px = pxPerPoint
  if type(px) ~= "number" or px <= 0 then px = LC.PX_PER_POINT end
  return max(3, floor((plotWidth or 0) / px))
end

local function bucketAverage(points, from, to)
  local ax, ay, n = 0, 0, 0
  for j = from, to - 1 do
    ax, ay, n = ax + points[j].x, ay + points[j].y, n + 1
  end
  if n == 0 then
    local p = points[#points]
    return p.x, p.y
  end
  return ax / n, ay / n
end

local function largestTriangle(points, pa, from, to, ax, ay)
  local best, bestArea = from, -1
  for j = from, to - 1 do
    local p = points[j]
    local area = abs((pa.x - ax) * (p.y - pa.y) - (pa.x - p.x) * (ay - pa.y))
    if area > bestArea then best, bestArea = j, area end
  end
  return best
end

function Math.Downsample(points, maxPoints)
  local n = #points
  if maxPoints >= n or maxPoints < 3 then return points end
  local out, every, a = { points[1] }, (n - 2) / (maxPoints - 2), 1
  for i = 0, maxPoints - 3 do
    local ax, ay = bucketAverage(points, floor((i + 1) * every) + 2, min(floor((i + 2) * every) + 2, n + 1))
    local pick = largestTriangle(points, points[a], floor(i * every) + 2, floor((i + 1) * every) + 2, ax, ay)
    out[#out + 1] = points[pick]
    a = pick
  end
  out[#out + 1] = points[n]
  return out
end

-- -- x ticks: a time ladder that lands on the player's midnight ----------------------------------

local TIME_STEPS = { 3600, 10800, 21600, 43200, DAY, 2 * DAY, 7 * DAY, 14 * DAY, 30 * DAY,
  91 * DAY, 182 * DAY, 365 * DAY }

local function midnight(ts)
  local t = date("*t", ts)
  return time({ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 })
end

local function pickStep(span, maxTicks)
  for _, s in ipairs(TIME_STEPS) do
    if span / s <= maxTicks then return s end
  end
  return TIME_STEPS[#TIME_STEPS]
end

-- Day steps re-anchor on midnight after every step, with a two-hour nudge, so a 23- or 25-hour
-- day (a daylight-saving change) cannot walk the labels off midnight.
local function nextTick(x, step)
  if step >= DAY then return midnight(x + step + 7200) end
  return x + step
end

local function firstTick(xMin, step)
  local m = midnight(xMin)
  if step >= DAY then
    if m < xMin then return midnight(m + DAY + 7200) end
    return m
  end
  return m + ceil((xMin - m) / step) * step
end

function Math.TimeTicks(xMin, xMax, maxTicks)
  maxTicks = maxTicks or LC.X_TICKS
  if not (xMin and xMax) or xMax <= xMin then return {}, nil end
  local step = pickStep(xMax - xMin, maxTicks)
  local ticks, x = {}, firstTick(xMin, step)
  while x <= xMax and #ticks <= maxTicks do
    ticks[#ticks + 1] = x
    x = nextTick(x, step)
  end
  return ticks, step
end

-- -- hover and dashes ----------------------------------------------------------------------------

function Math.NearestIndex(xs, x)
  local n = #xs
  if n == 0 then return nil end
  if x <= xs[1] then return 1 end
  if x >= xs[n] then return n end
  local lo, hi = 1, n
  while hi - lo > 1 do
    local mid = floor((lo + hi) / 2)
    if xs[mid] <= x then lo = mid else hi = mid end
  end
  if x - xs[lo] <= xs[hi] - x then return lo end
  return hi
end

function Math.Dashes(x1, y1, x2, y2, dash, gap)
  dash, gap = dash or LC.DASH, gap or LC.GAP
  local dx, dy = x2 - x1, y2 - y1
  local len = sqrt(dx * dx + dy * dy)
  local out = {}
  if len <= 0 then return out end
  local ux, uy, s = dx / len, dy / len, 0
  while s < len do
    local e = min(s + dash, len)
    out[#out + 1] = { x1 + ux * s, y1 + uy * s, x1 + ux * e, y1 + uy * e }
    s = s + dash + gap
  end
  return out
end

-- -- the clip: Liang-Barsky against the plot rectangle ---------------------------------------------
--
-- WHY EVERY SEGMENT IS CLIPPED BEFORE IT IS DRAWN. A host may pin yMin/yMax (or xMin/xMax) inside
-- its data, and a point a long way off the plot then maps to a pixel a long way off the chart. A
-- solid segment to it draws over the rest of the UI, and a DASHED one is worse: Dashes cuts the
-- whole unclipped length, one pooled Line per dash, and Lines are never destroyed in the client,
-- so one far point could grow the pool by millions for the session. Clipped first, a segment is
-- never longer than the plot's diagonal, so the dashes one range can make are bounded by geometry.

-- One edge of the parametric clip: p is the direction's component toward the edge, q the distance
-- to it. Answers the narrowed [t0, t1], or nil when the segment lies wholly beyond the edge.
local function clipEdge(p, q, t0, t1)
  if p == 0 then
    if q < 0 then return nil end
    return t0, t1
  end
  local r = q / p
  if p < 0 then
    if r > t1 then return nil end
    if r > t0 then t0 = r end
  else
    if r < t0 then return nil end
    if r < t1 then t1 = r end
  end
  return t0, t1
end

function Math.ClipSegment(x1, y1, x2, y2, left, bottom, right, top)
  local dx, dy = x2 - x1, y2 - y1
  local t0, t1 = clipEdge(-dx, x1 - left, 0, 1)
  if t0 then t0, t1 = clipEdge(dx, right - x1, t0, t1) end
  if t0 then t0, t1 = clipEdge(-dy, y1 - bottom, t0, t1) end
  if t0 then t0, t1 = clipEdge(dy, top - y1, t0, t1) end
  if not t0 then return nil end
  -- An end the clip did not move is answered as given, not recomputed, so an inside segment comes
  -- back bit-for-bit.
  if t1 < 1 then x2, y2 = x1 + t1 * dx, y1 + t1 * dy end
  if t0 > 0 then x1, y1 = x1 + t0 * dx, y1 + t0 * dy end
  return x1, y1, x2, y2
end

-- -- the widget ----------------------------------------------------------------------------------
--
-- POOLED BY INDEX. A render hands out Lines and labels from two arrays in order and hides whatever
-- it did not reach, so the same data drawn twice creates nothing new and a smaller drawing leaves
-- nothing stale on screen. Regions are never destroyed in the client, so a chart that created per
-- render would grow for the life of the session.

local function plotRect(w, h)
  return LC.PAD_LEFT, LC.PAD_BOTTOM,
    max(0, w - LC.PAD_LEFT - LC.PAD_RIGHT), max(0, h - LC.PAD_TOP - LC.PAD_BOTTOM)
end

local function acquireLine(c)
  c.__lineUsed = c.__lineUsed + 1
  local l = c.__linePool[c.__lineUsed]
  if not l then
    l = c:CreateLine(nil, "ARTWORK")
    c.__linePool[c.__lineUsed] = l
  end
  l:Show()
  return l
end

local function seg(c, x1, y1, x2, y2, color, thickness)
  local l = acquireLine(c)
  l:SetThickness(thickness or 1)
  l:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
  l:SetStartPoint("BOTTOMLEFT", c, x1, y1)
  l:SetEndPoint("BOTTOMLEFT", c, x2, y2)
  return l
end

local function dashed(c, x1, y1, x2, y2, color, thickness)
  for _, d in ipairs(Math.Dashes(x1, y1, x2, y2)) do
    seg(c, d[1], d[2], d[3], d[4], color, thickness)
  end
end

local function acquireLabel(c)
  c.__labelUsed = c.__labelUsed + 1
  local fs = c.__labelPool[c.__labelUsed]
  if not fs then
    -- Created WITH a template: a FontString with no face raises on its first SetText in the client.
    fs = c:CreateFontString(nil, "OVERLAY", c.__opts.font or "GameFontDisableSmall")
    c.__labelPool[c.__labelUsed] = fs
  end
  fs:ClearAllPoints()
  fs:Show()
  return fs
end

local function hideUnused(c)
  for i = c.__lineUsed + 1, #c.__linePool do c.__linePool[i]:Hide() end
  for i = c.__labelUsed + 1, #c.__labelPool do c.__labelPool[i]:Hide() end
end

local function dataRange(series)
  local lo, hi
  for _, s in ipairs(series or {}) do
    for _, p in ipairs(s.points or {}) do
      if not lo or p.y < lo then lo = p.y end
      if not hi or p.y > hi then hi = p.y end
    end
  end
  return lo, hi
end

local function xToPixel(s, x)
  if s.x1 == s.x0 then return s.left end
  return s.left + (x - s.x0) / (s.x1 - s.x0) * s.w
end

local function yToPixel(s, y)
  if s.y1 == s.y0 then return s.bottom end
  return s.bottom + (y - s.y0) / (s.y1 - s.y0) * s.h
end

local function defaultFormatY(v)
  if v == floor(v) then return tostring(v) end
  return string.format("%.2f", v)
end

local function defaultFormatX(x, step)
  if step and step < DAY then return date("%H:%M", x) end
  return date("%d %b", x)
end

local function drawXAxis(c, s)
  seg(c, s.left, s.bottom, s.left + s.w, s.bottom, LC.AXIS, 1)
  local ticks, step = Math.TimeTicks(s.x0, s.x1, LC.X_TICKS)
  local fmt = c.__opts.formatX or defaultFormatX
  for _, t in ipairs(ticks) do
    local fs = acquireLabel(c)
    fs:SetPoint("TOP", c, "BOTTOMLEFT", xToPixel(s, t), s.bottom - 2)
    fs:SetText(fmt(t, step))
  end
end

local function drawYAxis(c, s, ticks)
  local fmt = c.__opts.formatY or defaultFormatY
  for _, t in ipairs(ticks) do
    local y = yToPixel(s, t)
    seg(c, s.left, y, s.left + s.w, y, LC.GRID, 1)
    local fs = acquireLabel(c)
    fs:SetPoint("RIGHT", c, "BOTTOMLEFT", s.left - LC.LABEL_GAP, y)
    fs:SetText(fmt(t))
  end
end

local function drawMarkers(c, s, markers)
  for _, m in ipairs(markers or {}) do
    if m.x and m.x >= s.x0 and m.x <= s.x1 then
      local x = xToPixel(s, m.x)
      if m.dashed == false then
        seg(c, x, s.bottom, x, s.bottom + s.h, m.color or LC.MARKER, 1)
      else
        dashed(c, x, s.bottom, x, s.bottom + s.h, m.color or LC.MARKER, 1)
      end
    end
  end
end

-- A segment is drawn dashed when its midpoint lies in the series' dashed range. The host uses the
-- range for the part of a line it wants read as provisional.
local function inDash(sr, xa, xb)
  if not sr.dashFrom then return false end
  local mid = (xa + xb) / 2
  return mid >= sr.dashFrom and mid <= (sr.dashTo or math.huge)
end

-- THE ONE PLACE A SERIES SEGMENT IS CLIPPED, before it is dashed or drawn solid, so Dashes only
-- ever cuts a clipped length. A segment wholly off the plot draws nothing. Input values are never
-- clamped: a clipped segment keeps the slope of the data it came from.
local function drawSegment(c, s, sr, a, b, color, th)
  local x1, y1, x2, y2 = Math.ClipSegment(xToPixel(s, a.x), yToPixel(s, a.y), xToPixel(s, b.x),
    yToPixel(s, b.y), s.left, s.bottom, s.left + s.w, s.bottom + s.h)
  if not x1 then return end
  if inDash(sr, a.x, b.x) then dashed(c, x1, y1, x2, y2, color, th) else seg(c, x1, y1, x2, y2, color, th) end
end

local function drawSeries(c, s, sr)
  local pts = Math.Downsample(sr.points or {}, Math.Budget(s.w, c.__opts.pxPerPoint))
  local color, th = sr.color or LC.LINE, sr.thickness or 1.5
  if #pts == 1 then
    local x, y = xToPixel(s, pts[1].x), yToPixel(s, pts[1].y)
    -- The tick only for a point on the plot, for the reason drawSegment clips.
    if Math.ClipSegment(x, y, x, y, s.left, s.bottom, s.left + s.w, s.bottom + s.h) then
      seg(c, x - 1, y, x + 1, y, color, th)
    end
    return
  end
  for i = 2, #pts do drawSegment(c, s, sr, pts[i - 1], pts[i], color, th) end
end

local function scaleFor(d, w, h)
  local left, bottom, pw, ph = plotRect(w, h)
  local lo, hi = d.yMin, d.yMax
  if lo == nil or hi == nil then lo, hi = dataRange(d.series) end
  local ticks, y0, y1 = Math.NiceTicks(lo, hi, LC.Y_TICKS, d.integer)
  return { x0 = d.xMin, x1 = d.xMax, y0 = y0, y1 = y1, left = left, bottom = bottom, w = pw, h = ph }, ticks
end

-- Every render RE-ARMS the hover: the scale (and maybe the data) under a resting cursor has just
-- changed, so the crosshair's pixel and the host's tooltip are both stale even when the nearest
-- index is not. `__hoverStale` makes the next HoverAtPixel -- the armed OnUpdate's, one frame later
-- -- move the crosshair and fire onHover even for the same index. The index itself is kept, so a
-- ClearHover (OnLeave, OnHide) that arrives first still tells the host its hover ended. With no
-- scale left there is nothing to point at, so the crosshair goes now.
local function render(c, w, h)
  c.__lineUsed, c.__labelUsed = 0, 0
  c.__hoverStale = true
  local d = c.__data
  if d and d.xMin and d.xMax and w > 0 and h > 0 then
    local s, ticks = scaleFor(d, w, h)
    c.__scale = s
    drawXAxis(c, s)
    drawYAxis(c, s, ticks)
    drawMarkers(c, s, d.markers)
    for _, sr in ipairs(d.series or {}) do drawSeries(c, s, sr) end
  else
    c.__scale = nil
    c.__cross:Hide()
  end
  hideUnused(c)
end

local function moveCross(c, x)
  local s = c.__scale
  local px = xToPixel(s, x)
  c.__cross:SetStartPoint("BOTTOMLEFT", c, px, s.bottom)
  c.__cross:SetEndPoint("BOTTOMLEFT", c, px, s.bottom + s.h)
  c.__cross:Show()
end

-- The pointer read, armed only while the cursor is over the chart. Every value is type-checked
-- because a headless frame answers its own table for any getter it does not model.
local function hoverTick(self)
  if not GetCursorPosition then return end
  local cx = GetCursorPosition()
  local scale, left = self:GetEffectiveScale(), self:GetLeft()
  if type(cx) ~= "number" or type(scale) ~= "number" or type(left) ~= "number" or scale == 0 then return end
  self:HoverAtPixel(cx / scale - left)
end

local function attachMethods(c)
  function c:SetData(data) self.__data = data end
  function c:Render(w, h) render(self, w or self:GetWidth() or 0, h or self:GetHeight() or 0) end
  function c:Clear() self.__data = nil; self:ClearHover(); render(self, 0, 0) end
  function c:GetPlotRect()
    local s = self.__scale
    if not s then return nil end
    return s.left, s.bottom, s.w, s.h
  end
  function c:XToPixel(x) return self.__scale and xToPixel(self.__scale, x) or 0 end
  function c:YToPixel(y) return self.__scale and yToPixel(self.__scale, y) or 0 end
  function c:PixelToX(px)
    local s = self.__scale
    if not s or s.w == 0 then return s and s.x0 or 0 end
    return s.x0 + (px - s.left) / s.w * (s.x1 - s.x0)
  end
  function c:HoverIndex() return self.__hoverIndex end
  function c:HoverAtPixel(px)
    local d, s = self.__data, self.__scale
    local xs = d and d.hoverXs
    if not (s and xs and #xs > 0) then return nil end
    local i = Math.NearestIndex(xs, self:PixelToX(px))
    if i ~= self.__hoverIndex or self.__hoverStale then
      self.__hoverIndex, self.__hoverStale = i, nil
      moveCross(self, xs[i])
      if self.__opts.onHover then self.__opts.onHover(self, i, xs[i]) end
    end
    return i
  end
  function c:ClearHover()
    self.__cross:Hide()
    if self.__hoverIndex == nil then return end
    self.__hoverIndex = nil
    if self.__opts.onHover then self.__opts.onHover(self, nil, nil) end
  end
end

--- One line chart, parented to `parent`. See the API document for `opts` and `data`.
function lib.LineChart(parent, opts)
  local c = CreateFrame("Frame", nil, parent)
  c.__opts = opts or {}
  c.__linePool, c.__lineUsed, c.__labelPool, c.__labelUsed = {}, 0, {}, 0
  -- The crosshair is the chart's FIRST CreateLine, made here before any render draws from the pool.
  -- It lives outside the pool so a render never hands it out or hides it mid-hover, and suites
  -- (and any host that inspects the chart's lines) rely on that order: keep it first.
  local cross = c:CreateLine(nil, "OVERLAY")
  cross:SetThickness(1)
  cross:SetColorTexture(LC.CROSSHAIR[1], LC.CROSSHAIR[2], LC.CROSSHAIR[3], LC.CROSSHAIR[4])
  cross:Hide()
  c.__cross = cross
  attachMethods(c)
  c:EnableMouse(true)
  c:SetScript("OnEnter", function(self) self:SetScript("OnUpdate", hoverTick) end)
  c:SetScript("OnLeave", function(self) self:SetScript("OnUpdate", nil); self:ClearHover() end)
  c:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil); self:ClearHover() end)
  c:SetScript("OnSizeChanged", function(self, w, h) self:Render(w, h) end)
  return c
end
