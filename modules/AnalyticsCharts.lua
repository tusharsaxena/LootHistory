local _, NS = ...
NS.Analytics = NS.Analytics or {}
local Analytics = NS.Analytics

-- The Insights tab's drawing half: the pooled widget factories (bars, stacked bars, strip bars,
-- list rows, legend chips), the section chrome (headers, dividers, list panels) and the render*
-- methods LayoutCharts calls. Loaded AFTER modules/Analytics.lua, so the chrome BuildCharts needs
-- goes out on Analytics._charts and is resolved there at call time. Peeled out of
-- modules/Analytics.lua (LootHistory#32) verbatim.

-- The constants come from modules/AnalyticsFormat.lua, bound once at load (hot-path upvalues).
local K = Analytics.K
local WHITE, BAR_H, BAR_GAP, SECTION_GAP = K.WHITE, K.BAR_H, K.BAR_GAP, K.SECTION_GAP
local DAYSTRIP_H, STRIP_LABEL_H, STRIP_AXIS_GAP = K.DAYSTRIP_H, K.STRIP_LABEL_H, K.STRIP_AXIS_GAP
local STRIP_LABEL_GAP, LABEL_X_ADJUST, LIST_ROW_H = K.STRIP_LABEL_GAP, K.LABEL_X_ADJUST, K.LIST_ROW_H
local LABELW, VALW, LABEL_MAXCHARS, LEGEND_MAXCHARS = K.LABELW, K.VALW, K.LABEL_MAXCHARS, K.LEGEND_MAXCHARS

-- Show a one-line tooltip pinned just above-and-right of the cursor (offset +5,+5), rather than
-- anchored to the (far-right) row edge. GetCursorPosition returns physical pixels, so divide by the
-- UIParent scale before placing against UIParent's bottom-left.
local function showCursorTooltip(owner, text, r, g, b)
  if not text or text == "" then return end
  GameTooltip:SetOwner(owner, "ANCHOR_NONE")
  local scale = UIParent:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  GameTooltip:ClearAllPoints()
  GameTooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / scale + 5, cy / scale + 5)
  GameTooltip:ClearLines()
  GameTooltip:AddLine(text, r or 1, g or 1, b or 1)
  GameTooltip:Show()
end

-- A horizontal bar row: fixed label (left) + value (right), track + fill between them.
local function makeBar(parent)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(BAR_H)
  local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetJustifyH("LEFT")
  bar.label = label
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetColorTexture(1, 1, 1, 0.06)
  bar.track = track
  local fill = bar:CreateTexture(nil, "ARTWORK")
  bar.fill = fill
  local value = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  value:SetJustifyH("RIGHT")
  bar.value = value
  label:SetWordWrap(false)
  bar:EnableMouse(true)
  bar:SetScript("OnEnter", function(self2) showCursorTooltip(self2, self2._fullLabel, 1, 0.82, 0) end)
  bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return bar
end

local function positionBar(bar, content, pad, y, barW, frac)
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", content, "TOPLEFT", pad, y)
  bar:SetWidth(barW)
  bar.label:ClearAllPoints(); bar.label:SetPoint("LEFT", 0, 0); bar.label:SetWidth(LABELW)
  bar.value:ClearAllPoints(); bar.value:SetPoint("RIGHT", 0, 0); bar.value:SetWidth(VALW)
  local trackW = math.max(1, barW - LABELW - VALW - 12)
  bar.track:ClearAllPoints(); bar.track:SetPoint("LEFT", LABELW + 6, 0); bar.track:SetSize(trackW, BAR_H - 4)
  bar.fill:ClearAllPoints(); bar.fill:SetPoint("LEFT", bar.track, "LEFT", 0, 0)
  bar.fill:SetSize(math.max(1, trackW * math.min(1, frac)), BAR_H - 4)
end

-- A single horizontal bar split into colored segments (used for the Quality-mix composition).
local function makeStackedBar(parent)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(BAR_H)
  local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetJustifyH("LEFT")
  bar.label = label
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetColorTexture(1, 1, 1, 0.06)
  bar.track = track
  local value = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  value:SetJustifyH("RIGHT")
  bar.value = value
  -- Each segment is a mouse-enabled frame (not a bare texture) so it can carry its own hover
  -- tooltip ("<category>: <value>"). The frame's texture fills it.
  bar.segs = {}
  for i = 1, 9 do
    local seg = CreateFrame("Frame", nil, bar)
    seg:EnableMouse(true)
    local tex = seg:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(seg)
    seg.tex = tex
    seg:SetScript("OnEnter", function(self2) showCursorTooltip(self2, self2._info, 1, 1, 1) end)
    seg:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.segs[i] = seg
  end
  label:SetWordWrap(false)
  bar:EnableMouse(true)
  bar:SetScript("OnEnter", function(self2) showCursorTooltip(self2, self2._fullLabel, 1, 0.82, 0) end)
  bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return bar
end

-- segments: ordered array of { frac (0..1 of the track), color = {r,g,b}, tip = string|nil }.
local function positionStacked(bar, content, pad, y, barW, segments)
  bar:ClearAllPoints(); bar:SetPoint("TOPLEFT", content, "TOPLEFT", pad, y); bar:SetWidth(barW)
  bar.label:ClearAllPoints(); bar.label:SetPoint("LEFT", 0, 0); bar.label:SetWidth(LABELW)
  bar.value:ClearAllPoints(); bar.value:SetPoint("RIGHT", 0, 0); bar.value:SetWidth(VALW)
  local trackW = math.max(1, barW - LABELW - VALW - 12)
  bar.track:ClearAllPoints(); bar.track:SetPoint("LEFT", LABELW + 6, 0); bar.track:SetSize(trackW, BAR_H - 4)
  local x = 0
  for i = 1, #bar.segs do
    local seg, sd = bar.segs[i], segments[i]
    if sd and sd.frac and sd.frac > 0 then
      local segW = math.max(1, trackW * math.min(1, sd.frac))
      seg:ClearAllPoints(); seg:SetPoint("LEFT", bar.track, "LEFT", x, 0); seg:SetSize(segW, BAR_H - 4)
      seg.tex:SetColorTexture(sd.color[1], sd.color[2], sd.color[3], 0.95)
      seg._info = sd.tip
      seg:Show()
      x = x + segW
    else
      seg:Hide()
    end
  end
end

-- One vertical bar in a per-bucket strip; hovering shows the bucket's info line.
local function makeStripBar(parent)
  local f = CreateFrame("Frame", nil, parent)
  local fill = f:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("BOTTOM", 0, 0)
  fill:SetColorTexture(0.40, 0.60, 0.95, 0.9)
  f.fill = fill
  -- Vertical axis label under the bar, rotated 90° CCW so it reads bottom-to-top. It is
  -- right-aligned to the axis line (top of the label at the line, hanging down) in renderStrip,
  -- where its measured width sets the anchor offset.
  local axis = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  axis:SetRotation(math.pi / 2)
  axis:SetTextColor(0.7, 0.7, 0.72)
  f.axis = axis
  f:SetScript("OnEnter", function(self2)
    if not self2.info then return end
    GameTooltip:SetOwner(self2, "ANCHOR_TOP")
    GameTooltip:AddLine(self2.info, 1, 1, 1)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end

-- A ranked-list row: name (left, may be quality-colored) + count/value (right).
local function makeListRow(parent)
  local r = CreateFrame("Frame", nil, parent)
  r:SetHeight(LIST_ROW_H)
  local name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  name:SetJustifyH("LEFT"); name:SetPoint("LEFT", 4, 0); name:SetWordWrap(false)
  r.name = name
  local count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  count:SetJustifyH("RIGHT"); count:SetPoint("RIGHT", -4, 0); count:SetWordWrap(false)
  r.count = count
  r:EnableMouse(true)
  r:SetScript("OnEnter", function(self2) showCursorTooltip(self2, self2._fullName, 1, 1, 1) end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return r
end

-- A legend chip: color swatch + label.
local function makeSwatch(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(14)
  local sw = f:CreateTexture(nil, "ARTWORK"); sw:SetSize(10, 10)
  sw:SetPoint("LEFT", f, "LEFT", 0, 0)
  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", sw, "RIGHT", 4, 0); fs:SetTextColor(0.8, 0.8, 0.82)
  fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
  f.sw, f.fs = sw, fs
  f:EnableMouse(true)
  f:SetScript("OnEnter", function(self2) showCursorTooltip(self2, self2._full, 0.9, 0.9, 0.9) end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end

local function sectionHeader(parent, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetText(text)
  fs:SetTextColor(1, 0.82, 0)
  return fs
end

-- Full-width section divider: centered gold title flanked by horizontal rule lines (the
-- "Slash Commands" separator look). Returns a frame; caller anchors its TOPLEFT on the y cursor.
local function sectionDivider(parent, text)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(26) -- taller to fit the enlarged title
  local lineL = f:CreateTexture(nil, "ARTWORK")
  lineL:SetColorTexture(1, 0.82, 0, 0.35)
  lineL:SetHeight(1.25) -- 25% thicker rule
  local lineR = f:CreateTexture(nil, "ARTWORK")
  lineR:SetColorTexture(1, 0.82, 0, 0.35)
  lineR:SetHeight(1.25)
  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  local file, size, flags = fs:GetFont()
  fs:SetFont(file, size * 1.5, flags) -- 50% larger title
  fs:SetPoint("CENTER", f, "CENTER", 0, 0)
  fs:SetTextColor(1, 0.82, 0)
  fs:SetText(text)
  f.fs = fs
  -- lines fill the space either side of the centered label (8px gap)
  lineL:SetPoint("LEFT", f, "LEFT", 0, 0)
  lineL:SetPoint("RIGHT", fs, "LEFT", -8, 0)
  lineR:SetPoint("LEFT", fs, "RIGHT", 8, 0)
  lineR:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  return f
end

local function listPanel(parent, title)
  local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  p:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                  insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  p:SetBackdropColor(0.08, 0.08, 0.10, 0.6)
  p:SetBackdropBorderColor(0.24, 0.24, 0.27, 0.7)
  local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  t:SetPoint("TOPLEFT", 6, -5)
  t:SetTextColor(1, 0.82, 0)
  t:SetText(title)
  p.title = t
  return p
end

-- The chrome BuildCharts draws, for modules/Analytics.lua, which loads before this file.
Analytics._charts = { sectionHeader = sectionHeader, sectionDivider = sectionDivider, listPanel = listPanel }

-- Render a horizontal-bar section: header + one bar per row. rows: ordered array of
--   { label, labelColor = {r,g,b}|nil, color = {r,g,b}, frac (0..1), value = string }.
-- Returns the new y cursor (skips the section entirely when rows is empty).
-- rows: ordered { label, labelColor = {r,g,b}|nil, color = {r,g,b}, frac (0..1), value = string }.
-- The label text is colored to match its bar (row.color) unless the caller gives an explicit
-- labelColor (e.g. quality color) — this makes single bars self-legending. legendPool (optional)
-- draws a category legend below the bars (each row's label + color).
function Analytics:renderBarSection(pool, header, rows, y, w, pad, legendPool)
  if #rows == 0 then header:Hide(); return y end
  -- Normalize so the largest bar always fills the track and the rest scale relative to it
  -- (a no-op for sections already built max-relative). Bars are ordered by the caller.
  local maxFrac = 0
  for _, row in ipairs(rows) do if (row.frac or 0) > maxFrac then maxFrac = row.frac end end
  if maxFrac > 0 then
    for _, row in ipairs(rows) do row.frac = (row.frac or 0) / maxFrac end
  end
  header:ClearAllPoints(); header:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y); header:Show()
  y = y - 18
  local innerW = w - pad * 2
  for _, row in ipairs(rows) do
    local bar = NS.Pool.Acquire(pool, function() return makeBar(self.content) end)
    bar.fill:SetColorTexture(row.color[1], row.color[2], row.color[3], 0.95)
    bar._fullLabel = Analytics._tipText(row.label, row.value)
    bar.label:SetText((Analytics._truncate(row.label, LABEL_MAXCHARS)))
    local lc = row.labelColor or row.color -- default the label color to its bar color
    bar.label:SetTextColor(lc[1] or 0.9, lc[2] or 0.9, lc[3] or 0.9)
    bar.value:SetText(row.value)
    bar.value:SetTextColor(0.8, 0.8, 0.82)
    positionBar(bar, self.content, pad, y, innerW, row.frac)
    y = y - (BAR_H + BAR_GAP)
  end
  if legendPool then
    local leg = {}
    for _, row in ipairs(rows) do leg[#leg + 1] = { label = row.label, color = row.color, value = row.value } end
    return self:renderLegend(legendPool, leg, y, w, pad)
  end
  return y - SECTION_GAP
end

-- Render a section where each row is a horizontal STACKED bar (one per currency). rows: ordered
--   { label, value (string), segments = { {frac (0..1 of the track), color = {r,g,b}}, ... } }.
-- `frac`s are already max-relative (the caller divides by the largest currency total), so the
-- longest bar fills the track and each segment is that source's share of the track. Empty → skipped.
function Analytics:renderStackedBarSection(pool, header, rows, y, w, pad)
  if #rows == 0 then header:Hide(); return y end
  header:ClearAllPoints(); header:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y); header:Show()
  y = y - 18
  local innerW = w - pad * 2
  for _, row in ipairs(rows) do
    local bar = NS.Pool.Acquire(pool, function() return makeStackedBar(self.content) end)
    bar._fullLabel = Analytics._tipText(row.label, row.value)
    bar.label:SetText((Analytics._truncate(row.label, LABEL_MAXCHARS)))
    local lc = row.labelColor
    bar.label:SetTextColor(lc and lc[1] or 0.9, lc and lc[2] or 0.9, lc and lc[3] or 0.9)
    bar.value:SetText(row.value); bar.value:SetTextColor(0.8, 0.8, 0.82)
    positionStacked(bar, self.content, pad, y, innerW, row.segments)
    y = y - (BAR_H + BAR_GAP)
  end
  return y - SECTION_GAP
end

-- Render a wrapped legend of color-swatch + label chips.
-- rows = { { label, color = {r,g,b}, value = string|nil } }.
-- Chips start at the track's left edge (aligned under the bars, not the text labels). Long labels
-- are truncated with an ellipsis; hovering a chip shows the full label.
function Analytics:renderLegend(pool, rows, y, w, pad)
  local x0 = pad + LABELW + 6 -- align the legend with where the bars/track begin
  local x, rowY, chipW = x0, y, 120
  for _, row in ipairs(rows) do
    if x + chipW > w - pad then x = x0; rowY = rowY - 16 end
    local chip = NS.Pool.Acquire(pool, function() return makeSwatch(self.content) end)
    chip.sw:SetColorTexture(row.color[1], row.color[2], row.color[3], 0.95)
    -- `value` is only present for legends mirroring a bar section (a category key built from
    -- catOrder has no single value) — _tipText then falls back to the label alone.
    chip._full = Analytics._tipText(row.label, row.value)
    chip.fs:SetWidth(chipW - 16)
    chip.fs:SetText((Analytics._truncate(row.label, LEGEND_MAXCHARS)))
    chip:ClearAllPoints(); chip:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, rowY)
    chip:SetWidth(chipW); chip:Show()
    x = x + chipW
  end
  return rowY - 16 - SECTION_GAP
end

-- Render a "… by Character" companion: a per-character stacked bar (segments = a chart's categories,
-- colored by colorFn, hover-tipped via labelFn) plus a color-swatch legend naming each category.
-- catOrder is the global category order; colorFn(k)/labelFn(k) map a category key to color/label.
function Analytics:renderCharCompanion(poolKey, legendKey, header, matrix, catOrder, colorFn, labelFn, valueFmt, y, w, pad)
  local rows = Analytics._buildCharStackRows(matrix or {}, self.stats.byChar, catOrder, colorFn, valueFmt, labelFn)
  y = self:renderStackedBarSection(self.pool[poolKey], header, rows, y, w, pad)
  if #rows > 0 then
    local legend = {}
    for _, k in ipairs(catOrder) do legend[#legend + 1] = { label = labelFn(k), color = colorFn(k) } end
    y = self:renderLegend(self.pool[legendKey], legend, y, w, pad)
  end
  return y
end

-- Render a per-bucket vertical strip. buckets: ordered array of { info (hover), count, label }.
-- Each bar carries a rotated x-axis label (thinned out when bars get too narrow to fit them).
function Analytics:renderStrip(pool, header, strip, buckets, y, w, pad)
  if #buckets == 0 then header:Hide(); strip:Hide(); return y end
  header:ClearAllPoints(); header:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y); header:Show()
  y = y - 18
  local innerW = w - pad * 2
  strip:ClearAllPoints(); strip:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y)
  strip:SetSize(innerW, DAYSTRIP_H); strip:Show()
  local n = #buckets
  local slot = n > 0 and (innerW / n) or innerW
  local barW = math.max(2, math.min(14, slot - 2))
  local labelStride = math.max(1, math.ceil(11 / slot))  -- keep labels >= ~11px apart
  local maxC = 1
  for _, b in ipairs(buckets) do if b.count > maxC then maxC = b.count end end
  -- Axis line separating the bars (above) from the labels (below), spanning the strip. Sits a
  -- small gap below the bar bases so the bars don't touch it.
  strip.axisLine = strip.axisLine or strip:CreateTexture(nil, "ARTWORK")
  strip.axisLine:SetColorTexture(0.45, 0.45, 0.5, 0.8)
  strip.axisLine:ClearAllPoints()
  strip.axisLine:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, -STRIP_AXIS_GAP)
  strip.axisLine:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 0, -STRIP_AXIS_GAP)
  strip.axisLine:SetHeight(1); strip.axisLine:Show()
  for i, b in ipairs(buckets) do
    local f = NS.Pool.Acquire(pool, function() return makeStripBar(strip) end)
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", (i - 1) * slot, 0)
    f:SetSize(barW, DAYSTRIP_H)
    f.fill:SetSize(barW, math.max(1, (b.count / maxC) * (DAYSTRIP_H - 2)))
    f.fill:SetAlpha(b.count == 0 and 0.12 or 0.9)
    f.info = b.info
    if b.label and ((i - 1) % labelStride == 0) then
      f.axis:SetText(b.label)
      -- Right-align the rotated label: its top (right end pre-rotation) sits a gap below the axis
      -- line and it hangs straight down, so labels of different lengths all start at the line.
      -- Center x on the bar; the top offset = line gap (below bar) + label gap (below line).
      local tw = f.axis:GetStringWidth() or 0
      f.axis:ClearAllPoints()
      f.axis:SetPoint("CENTER", f, "BOTTOMLEFT", barW / 2 + LABEL_X_ADJUST,
        -(tw / 2) - STRIP_AXIS_GAP - STRIP_LABEL_GAP)
      f.axis:Show()
    else
      f.axis:SetText(""); f.axis:Hide()
    end
  end
  return y - DAYSTRIP_H - STRIP_LABEL_H - SECTION_GAP
end

-- Render a ranked list panel (top zones / items / value). rows: array of
--   { name, nameColor = {r,g,b}|nil, right (string) }, capped to 10. `rightW` sizes the value
--   column — money strings (coin glyphs) need more room than plain counts. Returns new y.
function Analytics:renderListPanel(pool, panel, rows, y, colW, pad, rightW)
  rightW = rightW or 48
  local n = math.min(10, #rows)
  local panelH = 20 + math.max(n, 1) * LIST_ROW_H + 4
  panel:ClearAllPoints(); panel:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y)
  panel:SetSize(colW, panelH); panel:Show()
  for i = 1, n do
    local row = rows[i]
    local r = NS.Pool.Acquire(pool, function() return makeListRow(panel) end)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -20 - (i - 1) * LIST_ROW_H)
    r:SetWidth(colW - 8)
    r.name:SetWidth(math.max(1, colW - 8 - rightW - 6)); r.name:SetText(row.name)
    r._fullName = Analytics._tipText(row.name, row.right)
    local nc = row.nameColor
    r.name:SetTextColor(nc and nc[1] or 0.9, nc and nc[2] or 0.9, nc and nc[3] or 0.9)
    r.count:SetWidth(rightW); r.count:SetText(row.right); r.count:SetTextColor(0.8, 0.8, 0.82)
  end
  return panelH
end

-- Hide every chart section (used for the empty-range state).
function Analytics:HideAllCharts()
  for _, h in pairs(self.headers) do h:Hide() end
  self.dayStrip:Hide(); self.valueStrip:Hide(); self.hourStrip:Hide()
  self.zonePanel:Hide(); self.itemPanel:Hide(); self.itemValuePanel:Hide()
  self.currencyStrip:Hide()
  self.lootDivider:Hide(); self.currencyDivider:Hide()
  if Analytics._ledger then Analytics._ledger.Hide(self) end
end
