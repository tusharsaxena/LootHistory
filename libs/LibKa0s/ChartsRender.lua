-- LibKa0s-Charts-1.0 — the renderers: the pooled widget factories (bars, stacked bars, range bars,
-- strip columns, list rows, legend chips), the chrome (headings, dividers, list panels, stat cards)
-- and the render* methods a host's layout walks.
--
-- ── WHY IT IS A FILE OF ITS OWN ──────────────────────────────────────────────────────────────
--
-- Charts.lua is the host seams and the arithmetic, and this file is what draws, which is about half
-- of the port and would have put one file in layout-§1's 1000-1500 band on its first day. It is a
-- secondary file paired on the shell's minor, as WidgetsLineChart.lua is on Widgets', so it cannot
-- attach to a shell from another vendored copy without saying so. Charts.lua's header is the
-- contract, and every row's fields are on its renderer below.
--
-- Depends on LibStub and on the Charts shell. Every method it adds is on the shell's context.

local lib = LibStub and LibStub("LibKa0s-Charts-1.0", true)
if not lib then return end

local RENDER_MINOR = 1
if lib.__renderMinor and lib.__renderMinor >= RENDER_MINOR
  and lib.__renderShellMinor == lib.MINOR then return end
lib.__renderMinor      = RENDER_MINOR
lib.__renderShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.ChartsRender = RENDER_MINOR

local Ctx, K = lib.__Ctx, lib.K

-- A frame whose hover shows its `_tip`.
local function hoverable(ctx, f, anchor)
  f:EnableMouse(true)
  f:SetScript("OnEnter", function(self2) ctx:showTip(self2, self2._tip, anchor) end)
  f:SetScript("OnLeave", function() ctx.hideTip() end)
end

-- Keep `w` on the chrome list, painted now and by every Reskin.
local function chromed(ctx, w, reskin)
  w._reskin = reskin
  ctx.chrome[#ctx.chrome + 1] = w
  reskin(ctx, w)
end

-- ── the factories ────────────────────────────────────────────────────────────────────────────

local function paintBar(ctx, bar)
  ctx.paint(bar.sub, ctx.colors.muted)
  ctx.fill(bar.track, ctx.colors.track)
end

-- A horizontal bar row's frame: fixed label (left, with an optional second line under it) + value
-- (right), the track between them.
local function barFrame(ctx, parent)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(K.BAR_H)
  bar.label = ctx.text(bar, ctx.fonts.label, "LEFT")
  bar.sub = ctx.text(bar, ctx.fonts.label, "LEFT")
  bar.track = bar:CreateTexture(nil, "BACKGROUND")
  bar.value = ctx.text(bar, ctx.fonts.label, "RIGHT")
  bar._reskin = paintBar
  paintBar(ctx, bar)
  hoverable(ctx, bar)
  return bar
end

local function makeBar(ctx, parent)
  local bar = barFrame(ctx, parent)
  bar.fill = bar:CreateTexture(nil, "ARTWORK")
  return bar
end

-- A single horizontal bar split into colored segments. Each segment is a mouse-enabled frame (not a
-- bare texture) so it carries its own hover; its texture fills it.
local function makeStackedBar(ctx, parent)
  local bar = barFrame(ctx, parent)
  bar.segs = {}
  for i = 1, K.MAX_STACK_SEGS do
    local seg = CreateFrame("Frame", nil, bar)
    seg.tex = seg:CreateTexture(nil, "ARTWORK")
    seg.tex:SetAllPoints(seg)
    hoverable(ctx, seg)
    bar.segs[i] = seg
  end
  return bar
end

-- A range bar: a bar row whose fill spans worst to best, with a thin mark at the average.
local function makeRange(ctx, parent)
  local bar = makeBar(ctx, parent)
  bar.mark = bar:CreateTexture(nil, "OVERLAY")
  return bar
end

local function paintScale(ctx, f)
  ctx.paint(f.lo, ctx.colors.muted)
  ctx.paint(f.hi, ctx.colors.muted)
end

-- A range section's scale line: its two ends' values, under the left and right ends of the track.
local function makeScale(ctx, parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(K.RANGE_SCALE_H)
  f.lo = ctx.text(f, ctx.fonts.axis, "LEFT")
  f.lo:SetPoint("LEFT", 0, 0)
  f.hi = ctx.text(f, ctx.fonts.axis, "RIGHT")
  f.hi:SetPoint("RIGHT", 0, 0)
  f._reskin = paintScale
  paintScale(ctx, f)
  return f
end

local function paintStripBar(ctx, f) ctx.paint(f.axis, ctx.colors.muted) end

-- One vertical column in a strip, with its level axis label under the strip's axis line.
local function makeStripBar(ctx, parent)
  local f = CreateFrame("Frame", nil, parent)
  f.fill = f:CreateTexture(nil, "ARTWORK")
  f.fill:SetPoint("BOTTOM", 0, 0)
  f.axis = ctx.text(f, ctx.fonts.axis, "CENTER")
  f._reskin = paintStripBar
  paintStripBar(ctx, f)
  hoverable(ctx, f, "ANCHOR_TOP")
  return f
end

-- A ranked-list row: name (left) + count or value (right). A click goes to the row's `_onClick`.
local function makeListRow(ctx, parent)
  local r = CreateFrame("Frame", nil, parent)
  r:SetHeight(K.LIST_ROW_H)
  r.name = ctx.text(r, ctx.fonts.label, "LEFT")
  r.name:SetPoint("LEFT", 4, 0)
  r.count = ctx.text(r, ctx.fonts.label, "RIGHT")
  r.count:SetPoint("RIGHT", -4, 0)
  hoverable(ctx, r)
  r:SetScript("OnMouseUp", function(self2, button)
    if self2._onClick then self2._onClick(self2, button) end
  end)
  return r
end

local function paintSwatch(ctx, f) ctx.paint(f.fs, ctx.colors.value) end

-- A legend chip: color swatch + label.
local function makeSwatch(ctx, parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(K.CHIP_H)
  f.sw = f:CreateTexture(nil, "ARTWORK")
  f.sw:SetSize(10, 10)
  f.sw:SetPoint("LEFT", f, "LEFT", 0, 0)
  f.fs = ctx.text(f, ctx.fonts.label, "LEFT")
  f.fs:SetPoint("LEFT", f.sw, "RIGHT", 4, 0)
  f._reskin = paintSwatch
  paintSwatch(ctx, f)
  hoverable(ctx, f)
  return f
end

-- ── the chrome ───────────────────────────────────────────────────────────────────────────────

local function paintHeading(ctx, fs) ctx.paint(fs, ctx.colors.heading) end

--- A section heading in the heading font and color; the caller (or a renderer) places it.
function Ctx:sectionHeader(parent, title)
  local fs = self.text(parent or self.content, self.fonts.heading, "LEFT")
  fs:SetText(title)
  chromed(self, fs, paintHeading)
  return fs
end

local function paintDivider(ctx, f)
  ctx.paint(f.fs, ctx.colors.heading)
  for _, rule in ipairs(f.rules) do ctx.fill(rule, ctx.colors.rule) end
end

--- A full-width divider: a centered title flanked by two rules. The caller anchors its TOPLEFT.
function Ctx:sectionDivider(parent, title)
  local f = CreateFrame("Frame", nil, parent or self.content)
  f:SetHeight(K.DIVIDER_H)
  local fs = self.text(f, self.fonts.divider, "CENTER")
  fs:SetPoint("CENTER", f, "CENTER", 0, 0)
  fs:SetText(title)
  local rules = {}
  for i = 1, 2 do
    rules[i] = f:CreateTexture(nil, "ARTWORK")
    rules[i]:SetHeight(1.25)
  end
  -- The rules fill the space either side of the centered title (an 8px gap).
  rules[1]:SetPoint("LEFT", f, "LEFT", 0, 0)
  rules[1]:SetPoint("RIGHT", fs, "LEFT", -8, 0)
  rules[2]:SetPoint("LEFT", fs, "RIGHT", 8, 0)
  rules[2]:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  f.fs, f.rules = fs, rules
  chromed(self, f, paintDivider)
  return f
end

local function paintPanelTitle(ctx, p) ctx.paint(p.title, ctx.colors.heading) end

--- A list panel: the host's panel with its title in the heading color.
function Ctx:listPanel(parent, title)
  local p = self.panel(parent or self.content)
  local t = self.text(p, self.fonts.panelTitle, "LEFT")
  t:SetPoint("TOPLEFT", 6, -5)
  t:SetText(title)
  p.title = t
  chromed(self, p, paintPanelTitle)
  return p
end

local function paintStrip(ctx, strip)
  if strip.axisLine then ctx.fill(strip.axisLine, ctx.colors.axis) end
end

--- A strip's frame (the columns and the axis line hang off it).
function Ctx:strip(parent)
  local strip = CreateFrame("Frame", nil, parent or self.content)
  chromed(self, strip, paintStrip)
  return strip
end

local function paintCard(ctx, card)
  ctx.paint(card.label, ctx.colors.caption)
  ctx.paint(card.value, card.color or ctx.colors.heading)
end

--- A stat card: a large figure on top, centered and in the heading color, over a small caption, on
--- the host's panel. Its hover states the figure (setCard).
--- @return table  { frame, label, value, caption }
function Ctx:card(parent, caption)
  local f = self.panel(parent or self.content)
  f:SetHeight(K.CARD_H)
  local value = self.text(f, self.fonts.figure, "CENTER")
  value:SetPoint("TOP", f, "TOP", 0, -9)
  value:SetPoint("LEFT", f, "LEFT", 2, 0)
  value:SetPoint("RIGHT", f, "RIGHT", -2, 0)
  local label = self.text(f, self.fonts.caption, "CENTER")
  label:SetPoint("BOTTOM", f, "BOTTOM", 0, 7)
  label:SetPoint("LEFT", f, "LEFT", 4, 0)
  label:SetPoint("RIGHT", f, "RIGHT", -4, 0)
  label:SetText(caption)
  hoverable(self, f)
  local card = { frame = f, label = label, value = value, caption = caption }
  chromed(self, card, paintCard)
  return card
end

-- Shrink `fs` to fit `maxW` (its font object's own size when it fits).
local function fitFigure(fs, maxW)
  local file, size, flags = fs:GetFont()
  if type(size) ~= "number" then return end
  local fit = lib.fitFontSize(fs:GetStringWidth(), maxW, size, K.MIN_HEADLINE_SIZE)
  if fit ~= size then fs:SetFont(file, fit, flags) end
end

--- Set a card's figure, its color (`color`, else the heading color) and its hover (`tip`, else
--- "caption: figure"); `maxW` shrinks an overflowing figure to fit. Puts the figure's font back
--- first, so an earlier bind's shrink never carries over.
function Ctx:setCard(card, value, tip, maxW, color)
  card.value:SetFontObject(self.fonts.figure)
  if self.face then self.face(card.value) end
  card.value:SetText(value)
  card.color = color
  self.paint(card.value, color or self.colors.heading)
  card.frame._tip = tip or lib.tipText(card.caption, value)
  if maxW then fitFigure(card.value, maxW) end
end

-- ── the renderers ────────────────────────────────────────────────────────────────────────────

--- Place a section's heading at the cursor.
--- @return number  the cursor under it
function Ctx:placeHeader(header, y, pad)
  header:ClearAllPoints()
  header:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y)
  header:Show()
  return y - K.HEADER_H
end

-- A section's row height: two lines when any row carries a sublabel, so its rows stay even.
local function rowHeight(rows)
  for _, row in ipairs(rows) do
    if row.sublabel then return K.BAR_H2 end
  end
  return K.BAR_H
end

-- Lay out a bar row `rowH` tall: its value and track, both centered on the row; returns the track's
-- width. The label is bindBarText's.
local function placeTrack(bar, content, pad, y, barW, rowH)
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", content, "TOPLEFT", pad, y)
  bar:SetSize(barW, rowH or K.BAR_H)
  bar.value:ClearAllPoints()
  bar.value:SetPoint("RIGHT", 0, 0)
  bar.value:SetWidth(K.VALW)
  local trackW = math.max(1, barW - K.LABELW - K.VALW - 12)
  bar.track:ClearAllPoints()
  bar.track:SetPoint("LEFT", K.LABELW + K.TRACK_GAP, 0)
  bar.track:SetSize(trackW, K.BAR_H - 4)
  return trackW
end

-- The label column: one line centered on the row, or the label over its sublabel, both truncated.
local function placeLabel(bar, row)
  bar.label:ClearAllPoints()
  bar.sub:ClearAllPoints()
  bar.label:SetWidth(K.LABELW)
  bar.label:SetText((lib.truncate(row.label, K.LABEL_MAXCHARS)))
  if not row.sublabel then
    bar.label:SetPoint("LEFT", 0, 0)
    bar.sub:SetText("")
    bar.sub:Hide()
    return
  end
  bar.label:SetPoint("BOTTOMLEFT", bar, "LEFT", 0, 1)
  bar.sub:SetPoint("TOPLEFT", bar, "LEFT", 0, -1)
  bar.sub:SetWidth(K.LABELW)
  bar.sub:SetText((lib.truncate(row.sublabel, K.LABEL_MAXCHARS)))
  bar.sub:Show()
end

--- A bar row's words: the truncated label in `labelColor` (and its sublabel, muted), the value, and
--- the hover.
function Ctx:bindBarText(bar, row, labelColor)
  bar._tip = row.tip or lib.tipText(row.label, row.value)
  placeLabel(bar, row)
  self.paint(bar.label, labelColor)
  bar.value:SetText(row.value)
  self.paint(bar.value, self.colors.value)
end

local function longest(rows)
  local top = 0
  for _, row in ipairs(rows) do
    if (row.frac or 0) > top then top = row.frac end
  end
  return top
end

--- A horizontal-bar section: the heading, then one bar per row, the longest filling the track. rows:
--- ordered { label, sublabel|nil, color = {r,g,b}|nil, labelColor = {r,g,b}|nil, frac (>= 0),
--- value = string, tip|nil }. The bar takes the `bar` color unless the row gives one, and the label
--- takes its bar's color unless the row gives one, so single bars are self-legending; a sublabel is
--- a second, muted line under it (every row then K.BAR_H2 tall). The rows are not written.
--- `legendPool` (optional) draws a legend of the rows under the bars. Skipped when rows is empty.
--- @return number  the cursor under the section
function Ctx:renderBarSection(pool, header, rows, y, w, pad, legendPool)
  if #rows == 0 then header:Hide(); return y end
  local top, rowH = longest(rows), rowHeight(rows)
  y = self:placeHeader(header, y, pad)
  for _, row in ipairs(rows) do
    local bar = self:acquire(pool, makeBar)
    local color = row.color or self.colors.bar
    self.barFill(bar.fill, color, 0.95)
    self:bindBarText(bar, row, row.labelColor or color)
    local trackW = placeTrack(bar, self.content, pad, y, w - pad * 2, rowH)
    local frac = top > 0 and (row.frac or 0) / top or 0
    bar.fill:ClearAllPoints()
    bar.fill:SetPoint("LEFT", bar.track, "LEFT", 0, 0)
    bar.fill:SetSize(math.max(1, trackW * math.min(1, frac)), K.BAR_H - 4)
    y = y - (rowH + K.BAR_GAP)
  end
  if legendPool then
    local leg = {}
    for i, row in ipairs(rows) do
      leg[i] = { label = row.label, color = row.color or self.colors.bar, value = row.value }
    end
    return self:renderLegend(legendPool, leg, y, w, pad)
  end
  return y - K.SECTION_GAP
end

-- Lay a stacked bar's segments along its track, hiding the unused ones.
local function placeSegments(ctx, bar, trackW, segments)
  local x = 0
  for i = 1, #bar.segs do
    local seg, sd = bar.segs[i], segments[i]
    if sd and sd.frac and sd.frac > 0 then
      local segW = math.max(1, trackW * math.min(1, sd.frac))
      seg:ClearAllPoints()
      seg:SetPoint("LEFT", bar.track, "LEFT", x, 0)
      seg:SetSize(segW, K.BAR_H - 4)
      ctx.barFill(seg.tex, sd.color, 0.95)
      seg._tip = sd.tip
      seg:Show()
      x = x + segW
    else
      seg:Hide()
    end
  end
end

--- A section of horizontal STACKED bars. rows: ordered { label, labelColor|nil, value, tip|nil,
--- segments = { { frac (0..1 of the track), color = {r,g,b}, tip }, ... } }. The fracs are already
--- relative to the longest row (the caller divides by the largest total), and a row draws its first
--- K.MAX_STACK_SEGS segments (lib.StackSegments folds the rest). Skipped when rows is empty.
--- @return number  the cursor under the section
function Ctx:renderStackedBarSection(pool, header, rows, y, w, pad)
  if #rows == 0 then header:Hide(); return y end
  local rowH = rowHeight(rows)
  y = self:placeHeader(header, y, pad)
  for _, row in ipairs(rows) do
    local bar = self:acquire(pool, makeStackedBar)
    self:bindBarText(bar, row, row.labelColor or self.colors.body)
    placeSegments(self, bar, placeTrack(bar, self.content, pad, y, w - pad * 2, rowH), row.segments or {})
    y = y - (rowH + K.BAR_GAP)
  end
  return y - K.SECTION_GAP
end

-- Lay a range bar's fill (lo to hi, at least RANGE_MIN_W) and its mark along a track on [lo0, hi0].
local function placeRange(ctx, bar, row, trackW, lo0, hi0)
  local span = hi0 - lo0
  local x1, x2 = trackW * (row.lo - lo0) / span, trackW * (row.hi - lo0) / span
  local fillW = math.max(K.RANGE_MIN_W, x2 - x1)
  x1 = math.max(0, math.min(x1, trackW - fillW))
  bar.fill:ClearAllPoints()
  bar.fill:SetPoint("LEFT", bar.track, "LEFT", x1, 0)
  bar.fill:SetSize(fillW, K.BAR_H - 4)
  ctx.barFill(bar.fill, row.color or ctx.colors.bar, 0.95)
  if not row.mark then bar.mark:Hide(); return end
  bar.mark:ClearAllPoints()
  bar.mark:SetPoint("CENTER", bar.track, "LEFT", trackW * (row.mark - lo0) / span, 0)
  bar.mark:SetSize(K.RANGE_MARK_W, K.BAR_H)
  ctx.fill(bar.mark, ctx.colors.body)
  bar.mark:Show()
end

--- The scale line under a range section: `fmt(lo0)` under the track's left end, `fmt(hi0)` its right.
--- @return number  the cursor under it
function Ctx:placeScale(pool, y, w, pad, lo0, hi0, fmt)
  local f = self:acquire(pool, makeScale)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad + K.LABELW + K.TRACK_GAP, y)
  f:SetWidth(math.max(1, w - pad * 2 - K.LABELW - K.VALW - 12))
  f.lo:SetText(fmt(lo0))
  f.hi:SetText(fmt(hi0))
  return y - K.RANGE_SCALE_H
end

--- A section of range bars: per row, a bar from its worst (`lo`) to its best (`hi`) with a mark at
--- its average (`mark`), on one scale from the lowest lo to the highest hi (lib.RangeScale), so
--- figures near each other do not all look full the way they do on a 0-based track. rows: ordered
--- { label, sublabel|nil, color|nil, labelColor|nil, lo, hi, mark|nil, value = string, tip|nil }.
--- With `scalePool` and `fmt`, a line under the bars names the scale's two ends. Skipped when rows
--- is empty.
--- @return number  the cursor under the section
function Ctx:renderRangeSection(pool, header, rows, y, w, pad, scalePool, fmt)
  if #rows == 0 then header:Hide(); return y end
  local lo0, hi0 = lib.RangeScale(rows)
  local rowH = rowHeight(rows)
  y = self:placeHeader(header, y, pad)
  for _, row in ipairs(rows) do
    local bar = self:acquire(pool, makeRange)
    self:bindBarText(bar, row, row.labelColor or row.color or self.colors.bar)
    placeRange(self, bar, row, placeTrack(bar, self.content, pad, y, w - pad * 2, rowH), lo0, hi0)
    y = y - (rowH + K.BAR_GAP)
  end
  if scalePool and fmt then y = self:placeScale(scalePool, y, w, pad, lo0, hi0, fmt) end
  return y - K.SECTION_GAP
end

--- A wrapped legend of swatch + label chips, starting at `x0` (by default the track's left edge,
--- under the bars, not their labels). rows: { { label, color = {r,g,b}, value|nil, tip|nil } }. A
--- long label is cut with an ellipsis; the hover shows it whole, with the value. Skipped when rows
--- is empty.
--- @return number  the cursor under the legend
function Ctx:renderLegend(pool, rows, y, w, pad, x0)
  if #rows == 0 then return y end
  x0 = x0 or pad + K.LABELW + K.TRACK_GAP
  local x, rowY = x0, y
  for _, row in ipairs(rows) do
    if x > x0 and x + K.CHIP_W > w - pad then
      x = x0
      rowY = rowY - K.LEGEND_ROW_H
    end
    local chip = self:acquire(pool, makeSwatch)
    self.fill(chip.sw, row.color, 0.95)
    chip._tip = row.tip or lib.tipText(row.label, row.value)
    chip.fs:SetWidth(K.CHIP_W - 16)
    chip.fs:SetText((lib.truncate(row.label, K.LEGEND_MAXCHARS)))
    chip:ClearAllPoints()
    chip:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, rowY)
    chip:SetWidth(K.CHIP_W)
    x = x + K.CHIP_W
  end
  return rowY - K.LEGEND_ROW_H - K.SECTION_GAP
end

-- A strip column's label: level, centered under the column (shifted by `dx` at the strip's ends),
-- its top a gap below the axis line, so it sits in the band under the line and never reaches a
-- column.
local function placeAxisLabel(f, label, dx)
  if not label then
    f.axis:SetText("")
    f.axis:Hide()
    return
  end
  f.axis:SetText(label)
  f.axis:ClearAllPoints()
  f.axis:SetPoint("TOP", f, "BOTTOM", dx or 0, -(K.STRIP_AXIS_GAP + K.STRIP_LABEL_GAP))
  f.axis:Show()
end

--- The axis line under a strip's columns, `width` long, a small gap below their bases.
function Ctx:placeAxisLine(strip, width)
  strip.axisLine = strip.axisLine or strip:CreateTexture(nil, "ARTWORK")
  self.fill(strip.axisLine, self.colors.axis)
  strip.axisLine:ClearAllPoints()
  strip.axisLine:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, -K.STRIP_AXIS_GAP)
  strip.axisLine:SetSize(width, 1)
  strip.axisLine:Show()
end

local function tallest(buckets, top)
  if top and top > 0 then return top end
  top = 1
  for _, b in ipairs(buckets) do
    if b.count > top then top = b.count end
  end
  return top
end

-- One strip column at its slot.
local function placeColumn(ctx, f, strip, b, x, barW, top)
  f:SetParent(strip)
  f:ClearAllPoints()
  f:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", x, 0)
  f:SetSize(barW, K.DAYSTRIP_H)
  f.fill:SetSize(barW, math.max(1, math.min(1, b.count / top) * (K.DAYSTRIP_H - 2)))
  ctx.barFill(f.fill, b.color or ctx.colors.bar)
  f.fill:SetAlpha(b.count == 0 and 0.12 or 0.9)
  f._tip = b.info
end

--- A strip of vertical columns, one per bucket: { count, label|nil, info (the hover: a string or
--- lines), color|nil }. A column's height is its count over `top` (the largest count, at least 1,
--- when nil); a zero column is a faint stub. lib.StripLabels picks the labels that show.
--- @return number  the cursor under the strip and its labels
function Ctx:renderStrip(pool, header, strip, buckets, y, w, pad, top)
  if #buckets == 0 then header:Hide(); strip:Hide(); return y end
  y = self:placeHeader(header, y, pad)
  local innerW = w - pad * 2
  strip:ClearAllPoints()
  strip:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y)
  strip:SetSize(innerW, K.DAYSTRIP_H)
  strip:Show()
  local slot, barW = lib.StripSlots(innerW, #buckets)
  local shown = lib.StripLabels(buckets, slot, innerW)
  top = tallest(buckets, top)
  self:placeAxisLine(strip, slot * #buckets)
  for i, b in ipairs(buckets) do
    local f = self:acquire(pool, makeStripBar, strip)
    placeColumn(self, f, strip, b, (i - 1) * slot + (slot - barW) / 2, barW, top)
    local dx = shown[i]
    placeAxisLabel(f, dx and b.label or nil, dx)
  end
  return y - K.DAYSTRIP_H - K.STRIP_LABEL_H - K.SECTION_GAP
end

--- A ranked list panel. rows: { name, nameColor = {r,g,b}|nil, right (string), tip|nil, onClick|nil },
--- capped at K.LIST_MAX. `rightW` sizes the value column (48 without). A row's click is its own: a
--- reused row forgets the last one's.
--- @return number  the panel's height
function Ctx:renderListPanel(pool, panel, rows, y, colW, pad, rightW)
  rightW = rightW or 48
  local n = math.min(K.LIST_MAX, #rows)
  local panelH = K.LIST_TITLE_H + math.max(n, 1) * K.LIST_ROW_H + 4
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y)
  panel:SetSize(colW, panelH)
  panel:Show()
  for i = 1, n do
    local row = rows[i]
    local r = self:acquire(pool, makeListRow, panel)
    r:SetParent(panel)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -K.LIST_TITLE_H - (i - 1) * K.LIST_ROW_H)
    r:SetWidth(colW - 8)
    r.name:SetWidth(math.max(1, colW - 8 - rightW - 6))
    r.name:SetText(row.name)
    self.paint(r.name, row.nameColor or self.colors.body)
    r.count:SetWidth(rightW)
    r.count:SetText(row.right)
    self.paint(r.count, self.colors.value)
    r._tip = row.tip or lib.tipText(row.name, row.right)
    r._onClick = row.onClick
  end
  return panelH
end
