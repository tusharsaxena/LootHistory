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
local BAR_H, BAR_GAP, SECTION_GAP = K.BAR_H, K.BAR_GAP, K.SECTION_GAP
local DAYSTRIP_H, STRIP_LABEL_H, STRIP_AXIS_GAP = K.DAYSTRIP_H, K.STRIP_LABEL_H, K.STRIP_AXIS_GAP
local STRIP_LABEL_GAP, LABEL_X_ADJUST, LIST_ROW_H = K.STRIP_LABEL_GAP, K.LABEL_X_ADJUST, K.LIST_ROW_H
local LABELW, VALW, LABEL_MAXCHARS, LEGEND_MAXCHARS = K.LABELW, K.VALW, K.LABEL_MAXCHARS, K.LEGEND_MAXCHARS

-- THE SKIN (LH-04). Every color this file draws is a token, read through NS.SkinColor at the point
-- the literal stood (same call, same arity, same order, so tests/analytics_golden.txt does not move):
-- the bar track chart.track, the strip fill chart.bar, the strip axis chart.axis, the axis labels
-- text.muted, the value and legend columns text.value, a row's default label text.body, the section
-- headings and panel titles text.heading, the section rules section.rule, the list panels the skin's
-- Panel. A factory paints its widget through the widget's own `_reskin`, so Analytics:Reskin (the
-- end of this file) reaches every pooled widget, the free list's too, with the same calls. The
-- hover lines go through core/Compat.lua, the one place tooltip lines read gtip.*.

-- A row's default label color (no color of its own): r, g, b.
local function bodyRGB() return NS.SkinColor("text.body") end

-- A hover line pinned just above and right of the cursor: the bars' and segments' and rows' full
-- label in a gtip.* token (Compat.ShowCursorTooltip).
local function showCursorTooltip(owner, text, token) NS.Compat.ShowCursorTooltip(owner, text, token) end
local function hideTooltip() NS.Compat.HideTooltip() end

-- The track under a bar's fill (a horizontal or a stacked bar): chart.track.
local function paintTrack(bar) bar.track:SetColorTexture(NS.SkinColor("chart.track")) end

-- A horizontal bar row: fixed label (left) + value (right), track + fill between them.
local function makeBar(parent)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(BAR_H)
  local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  NS.Skin.Font(label)
  label:SetJustifyH("LEFT")
  bar.label = label
  local track = bar:CreateTexture(nil, "BACKGROUND")
  bar.track = track
  bar._reskin = paintTrack
  paintTrack(bar)
  local fill = bar:CreateTexture(nil, "ARTWORK")
  bar.fill = fill
  local value = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  NS.Skin.Font(value)
  value:SetJustifyH("RIGHT")
  bar.value = value
  label:SetWordWrap(false)
  bar:EnableMouse(true)
  bar:SetScript("OnEnter", function(self2) showCursorTooltip(self2, self2._fullLabel, "gtip.title") end)
  bar:SetScript("OnLeave", hideTooltip)
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
  NS.Skin.Font(label)
  label:SetJustifyH("LEFT")
  bar.label = label
  local track = bar:CreateTexture(nil, "BACKGROUND")
  bar.track = track
  bar._reskin = paintTrack
  paintTrack(bar)
  local value = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  NS.Skin.Font(value)
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
    seg:SetScript("OnEnter", function(self2) showCursorTooltip(self2, self2._info, "gtip.value") end)
    seg:SetScript("OnLeave", hideTooltip)
    bar.segs[i] = seg
  end
  label:SetWordWrap(false)
  bar:EnableMouse(true)
  bar:SetScript("OnEnter", function(self2) showCursorTooltip(self2, self2._fullLabel, "gtip.title") end)
  bar:SetScript("OnLeave", hideTooltip)
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
      NS.SkinBar(seg.tex, sd.color[1], sd.color[2], sd.color[3], 0.95)
      seg._info = sd.tip
      seg:Show()
      x = x + segW
    else
      seg:Hide()
    end
  end
end

-- A strip bar's fill (chart.bar, in the bar texture) and its rotated axis label (text.muted).
local function paintStripBar(f)
  NS.SkinBar(f.fill, NS.SkinColor("chart.bar"))
  f.axis:SetTextColor(NS.SkinColor("text.muted"))
end

-- One vertical bar in a per-bucket strip; hovering shows the bucket's info line.
local function makeStripBar(parent)
  local f = CreateFrame("Frame", nil, parent)
  local fill = f:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("BOTTOM", 0, 0)
  f.fill = fill
  -- Vertical axis label under the bar, rotated 90° CCW so it reads bottom-to-top. It is
  -- right-aligned to the axis line (top of the label at the line, hanging down) in renderStrip,
  -- where its measured width sets the anchor offset.
  local axis = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  NS.Skin.Font(axis)
  axis:SetRotation(math.pi / 2)
  f.axis = axis
  f._reskin = paintStripBar
  paintStripBar(f)
  f:SetScript("OnEnter", function(self2)
    if self2.info then NS.Compat.ShowLineTooltip(self2, self2.info, "gtip.value", "ANCHOR_TOP") end
  end)
  f:SetScript("OnLeave", hideTooltip)
  return f
end

-- A ranked-list row: name (left, may be quality-colored) + count/value (right).
local function makeListRow(parent)
  local r = CreateFrame("Frame", nil, parent)
  r:SetHeight(LIST_ROW_H)
  local name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  NS.Skin.Font(name)
  name:SetJustifyH("LEFT"); name:SetPoint("LEFT", 4, 0); name:SetWordWrap(false)
  r.name = name
  local count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  NS.Skin.Font(count)
  count:SetJustifyH("RIGHT"); count:SetPoint("RIGHT", -4, 0); count:SetWordWrap(false)
  r.count = count
  r:EnableMouse(true)
  r:SetScript("OnEnter", function(self2) showCursorTooltip(self2, self2._fullName, "gtip.value") end)
  r:SetScript("OnLeave", hideTooltip)
  return r
end

-- A legend chip's label: text.value.
local function paintSwatch(f) f.fs:SetTextColor(NS.SkinColor("text.value")) end

-- A legend chip: color swatch + label.
local function makeSwatch(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(14)
  local sw = f:CreateTexture(nil, "ARTWORK"); sw:SetSize(10, 10)
  sw:SetPoint("LEFT", f, "LEFT", 0, 0)
  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  NS.Skin.Font(fs)
  f.sw, f.fs = sw, fs
  fs:SetPoint("LEFT", sw, "RIGHT", 4, 0); paintSwatch(f)
  fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
  f._reskin = paintSwatch
  f:EnableMouse(true)
  f:SetScript("OnEnter", function(self2) showCursorTooltip(self2, self2._full, "gtip.body") end)
  f:SetScript("OnLeave", hideTooltip)
  return f
end

-- A section heading's color: text.heading.
local function headingRGB() return NS.SkinColor("text.heading") end

local function sectionHeader(parent, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  NS.Skin.Font(fs)
  fs:SetText(text)
  fs:SetTextColor(headingRGB())
  return fs
end

-- Full-width section divider: centered gold title flanked by horizontal rule lines (the
-- "Slash Commands" separator look). Returns a frame; caller anchors its TOPLEFT on the y cursor.
local function sectionDivider(parent, text)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(26) -- taller to fit the enlarged title
  local lineL = f:CreateTexture(nil, "ARTWORK")
  lineL:SetColorTexture(NS.SkinColor("section.rule"))
  lineL:SetHeight(1.25) -- 25% thicker rule
  local lineR = f:CreateTexture(nil, "ARTWORK")
  lineR:SetColorTexture(NS.SkinColor("section.rule"))
  lineR:SetHeight(1.25)
  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  NS.Skin.Font(fs)
  local file, size, flags = fs:GetFont()
  fs:SetFont(file, size * 1.5, flags) -- 50% larger title
  fs:SetPoint("CENTER", f, "CENTER", 0, 0)
  fs:SetTextColor(headingRGB())
  fs:SetText(text)
  f.fs, f.rules = fs, { lineL, lineR }
  -- lines fill the space either side of the centered label (8px gap)
  lineL:SetPoint("LEFT", f, "LEFT", 0, 0)
  lineL:SetPoint("RIGHT", fs, "LEFT", -8, 0)
  lineR:SetPoint("LEFT", fs, "RIGHT", 8, 0)
  lineR:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  return f
end

-- A list panel is the skin's Panel (panel.bg under panel.border; on Ka0s Default call for call the
-- backdrop it always drew, and recorded, so a switch repaints it), its title in the heading color.
local function listPanel(parent, title)
  local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  NS.Skin.Panel(p)
  local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  NS.Skin.Font(t)
  t:SetPoint("TOPLEFT", 6, -5)
  t:SetTextColor(headingRGB())
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
    NS.SkinBar(bar.fill, row.color[1], row.color[2], row.color[3], 0.95)
    bar._fullLabel = Analytics._tipText(row.label, row.value)
    bar.label:SetText((Analytics._truncate(row.label, LABEL_MAXCHARS)))
    local lc = row.labelColor or row.color -- default the label color to its bar color
    bar.label:SetTextColor(lc[1], lc[2], lc[3])
    bar.value:SetText(row.value)
    bar.value:SetTextColor(NS.SkinColor("text.value"))
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
    if lc then bar.label:SetTextColor(lc[1], lc[2], lc[3]) else bar.label:SetTextColor(bodyRGB()) end
    bar.value:SetText(row.value); bar.value:SetTextColor(NS.SkinColor("text.value"))
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
  strip.axisLine:SetColorTexture(NS.SkinColor("chart.axis"))
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
    if nc then r.name:SetTextColor(nc[1], nc[2], nc[3]) else r.name:SetTextColor(bodyRGB()) end
    r.count:SetWidth(rightW); r.count:SetText(row.right); r.count:SetTextColor(NS.SkinColor("text.value"))
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

-- ── the skin (LH-04) ──────────────────────────────────────────────────────────────────────────
--
-- What a skin switch repaints that the library's own repaint does not reach. The cards, the list
-- panels and the scroll bar are recorded frames the library repaints itself; this walk covers what
-- Insights colors at build time: the palette and the meaning colors (synced FIRST, whether or not
-- the pane was ever built, so a first build after a switch draws the new skin), the card captions,
-- the section headings, rules and titles, the panel titles, every pooled widget's factory paint on
-- the active AND the free list (its `_reskin`), and the ledger half's chrome. Then a refresh
-- rebinds the charts in the new colors while the pane is up; a hidden pane refreshes when its tab is
-- next selected. Fires after the new skin is resolved (NS.Skin.OnLooksChanged).
local function reskinPool(pool)
  for _, w in ipairs(pool.active) do if w._reskin then w._reskin(w) end end
  for _, w in ipairs(pool.free) do if w._reskin then w._reskin(w) end end
end

local function reskinDivider(d)
  for _, rule in ipairs(d.rules) do rule:SetColorTexture(NS.SkinColor("section.rule")) end
  d.fs:SetTextColor(headingRGB())
end

function Analytics:Reskin()
  Analytics._syncSkinColors()
  if not self.content then return end
  -- A headline card's base face is read again here, after the repaint: Layout puts it back before it
  -- shrinks to fit, so a face saved at build time would undo a live outline change or skin switch.
  for _, c in pairs(self.cards or {}) do
    c.caption:SetTextColor(NS.SkinColor("text.disabled"))
    if c.bigStr then c.fontFile, c.baseSize, c.fontFlags = c.num:GetFont() end
  end
  for _, h in pairs(self.headers) do h:SetTextColor(headingRGB()) end
  reskinDivider(self.lootDivider); reskinDivider(self.currencyDivider)
  for _, p in ipairs({ self.zonePanel, self.itemPanel, self.itemValuePanel }) do p.title:SetTextColor(headingRGB()) end
  self.emptyText:SetTextColor(NS.SkinColor("text.disabled"))
  for _, pool in pairs(self.pool) do reskinPool(pool) end
  if Analytics._ledger then Analytics._ledger.Reskin(self, reskinPool, reskinDivider) end
  if self.pane and self.pane:IsVisible() then self:Refresh() end
end

if NS.Skin then NS.Skin.OnLooksChanged(function() Analytics:Reskin() end) end
