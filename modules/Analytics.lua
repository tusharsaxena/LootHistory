local addonName, NS = ...
NS.Analytics = NS.Analytics or {}
local Analytics = NS.Analytics

-- Insights tab: stat/highlight cards + a stack of breakdown sections (source, value, quality,
-- item type, bound type, per-character, time-of-day/week, M+ keystone, confidence) plus top
-- zones/items/value lists, scoped by a date-range selector (see docs/browser.md). Everything
-- is driven off a single Database:Stats(filter) pass; widgets are pooled and re-laid-out on resize.
-- "Value" is vendor value (vendorPrice × quantity), not market price.

local WHITE = "Interface\\Buttons\\WHITE8X8"

local BAR_H, BAR_GAP = 16, 3
local SECTION_GAP = 16
local DAYSTRIP_H = 46
local STRIP_LABEL_H = 44   -- reserved space under a strip for the rotated x-axis labels
local STRIP_AXIS_GAP = 2   -- gap between the bar bases and the separator line
local STRIP_LABEL_GAP = 7  -- gap between the separator line and the label text
local LABEL_X_ADJUST = -2  -- nudge to visually center the rotated label under the bar (tunable)
local LIST_ROW_H = 16
local LABELW, VALW = 108, 92   -- fixed label/value columns in a horizontal bar; track fills the rest
local LABEL_MAXCHARS = 16      -- cap a bar/row label to this many glyphs (+ ellipsis) so it fits LABELW
local LEGEND_MAXCHARS = 13     -- cap a legend chip label to this many glyphs (+ ellipsis) to fit the chip
local MAX_STACK_SEGS = 9       -- segment ceiling per stacked bar (matches makeStackedBar's texture pool)
local MIN_HEADLINE_SIZE = 11   -- floor for the shrink-to-fit KPI headline font
local MAX_DAY_BARS = 60        -- cap the per-day strip so long "All" ranges stay readable
local NEUTRAL = { 0.55, 0.62, 0.72 }

-- Per-source bar colors (no such table in Constants; kept local to the chart).
-- Palette derived via the dataviz skill: 15 hues spaced 24 degrees apart in OKLCH
-- (dark-band L 0.62/0.53 alternating, C 0.17/0.14 alternating) run through a
-- coprime-step reordering so every *adjacent* pair in that sequence clears the
-- categorical gates on the dark surface (node scripts/validate_palette.js --mode
-- dark: lightness band / chroma floor / CVD separation / normal-vision floor /
-- contrast all PASS). Themed groups (roll variants, professions, economy) were
-- then assigned to sequence-adjacent slots so the pairs most likely to sit next
-- to each other in a sorted bar/legend are the ones proven furthest apart.
-- 16 categorical keys exceeds the skill's validated 8-hue cap, so full all-pairs
-- separation (any two slots as neighbors) is not achievable here - a documented,
-- inherent limit, not an oversight; the existing direct value/count labels on
-- every bar and legend entry are the required secondary encoding.
local SOURCE_COLOR = {
  KILL        = { 0.68, 0.27, 0.26 }, CONTAINER  = { 0.83, 0.37, 0.00 },
  MPLUS       = { 0.53, 0.31, 0.65 }, ROLL       = { 0.20, 0.62, 0.23 },
  BONUS_ROLL  = { 0.25, 0.40, 0.74 }, QUEST      = { 0.65, 0.51, 0.00 },
  TRADE       = { 0.00, 0.64, 0.63 }, MAIL       = { 0.00, 0.56, 0.88 },
  AH          = { 0.76, 0.34, 0.67 }, VENDOR     = { 0.61, 0.35, 0.00 },
  CRAFT       = { 0.00, 0.52, 0.36 }, DISENCHANT = { 0.52, 0.44, 0.90 },
  MILLING     = { 0.38, 0.46, 0.00 }, PROSPECTING= { 0.00, 0.49, 0.62 },
  REFUND      = { 0.83, 0.32, 0.51 }, OTHER      = { 0.58, 0.58, 0.62 },
}

-- Bound-type display labels + colors.
local BOUND_LABEL = {
  BOP = "Soulbound", BOE = "BoE", WARBAND = "Warbound", WARBAND_UE = "Warbound (UE)",
  UNBOUND = "Unbound",
}
-- Warbound/until-equipped take the Bound column's blue/orange so the two views read alike.
local BOUND_COLOR = {
  BOP = { 0.85, 0.45, 0.45 }, BOE = { 0.55, 0.80, 0.60 },
  WARBAND = { 0.30, 0.58, 0.98 }, WARBAND_UE = { 0.95, 0.52, 0.12 },
  UNBOUND = { 0.60, 0.60, 0.65 },
}
local BOUND_ORDER = { "BOP", "BOE", "WARBAND", "WARBAND_UE", "UNBOUND" }

local WEEKDAY = { [0] = "Sun", [1] = "Mon", [2] = "Tue", [3] = "Wed", [4] = "Thu", [5] = "Fri", [6] = "Sat" }

-- Gold star before epic+ items in the Top-items list. Uses whichever star atlas exists on this
-- client; falls back to no star (the quality color still marks it) so it never renders a box.
local STAR_ATLASES = { "PetJournal-FavoritesIcon", "auctionhouse-icon-favorite", "communities-icon-star" }
local resolvedStar
local function starMarkup()
  if resolvedStar ~= nil then return resolvedStar end
  resolvedStar = ""
  if CreateAtlasMarkup and C_Texture and C_Texture.GetAtlasInfo then
    for _, a in ipairs(STAR_ATLASES) do
      if C_Texture.GetAtlasInfo(a) then resolvedStar = CreateAtlasMarkup(a, 12, 12) .. " "; break end
    end
  end
  return resolvedStar
end

-- Class color for a per-character bar (falls back to a neutral gray).
local function classColor(classFile)
  local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
  if c then return { c.r, c.g, c.b } end
  return { 0.7, 0.7, 0.72 }
end

-- Item-quality color as an {r,g,b} triple (falls back to neutral gray).
local function qualityColor(q)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
  if c then return { c.r, c.g, c.b } end
  return { 0.6, 0.6, 0.6 }
end

-- Short character label ("Name-Realm" → "Name") for narrow per-character bars.
local function shortChar(key) return (key and key:match("^[^-]+")) or key or "?" end

-- Shrink a headline number's font only when its rendered string would overflow the card, so long
-- money strings stay on one line while normal values keep the full headline size. Pure + testable.
function Analytics._fitFontSize(stringWidth, maxWidth, baseSize, minSize)
  if not stringWidth or stringWidth <= 0 or stringWidth <= maxWidth then return baseSize end
  return math.max(minSize, baseSize * maxWidth / stringWidth)
end

-- Standard categorical palette for charts NOT tied to a predefined color (class / bound / quality /
-- source all keep their own maps). Sequence is inverse-VIBGYOR (R→O→Y→G→B→I→V) so neighboring
-- entries are rainbow-distinct — never two lookalikes side by side — then the same rainbow in a
-- lighter band and a darker band (21 total). Colors are assigned by a category's rank in its chart's
-- sort order (paletteColor), so consecutive bars/segments always draw from adjacent, dissimilar hues.
local PALETTE = {
  { 0.90, 0.25, 0.25 }, { 0.95, 0.55, 0.15 }, { 0.88, 0.82, 0.22 }, { 0.35, 0.75, 0.38 },
  { 0.28, 0.55, 0.90 }, { 0.42, 0.38, 0.82 }, { 0.72, 0.42, 0.86 },
  { 0.97, 0.58, 0.58 }, { 0.98, 0.76, 0.50 }, { 0.94, 0.90, 0.55 }, { 0.60, 0.87, 0.63 },
  { 0.58, 0.76, 0.97 }, { 0.68, 0.64, 0.92 }, { 0.86, 0.68, 0.94 },
  { 0.62, 0.18, 0.18 }, { 0.70, 0.40, 0.10 }, { 0.60, 0.56, 0.12 }, { 0.18, 0.52, 0.28 },
  { 0.15, 0.38, 0.66 }, { 0.28, 0.24, 0.58 }, { 0.50, 0.28, 0.62 },
}
-- 1-based rank → palette color (cycles). Pure + testable.
function Analytics.paletteColor(rank)
  return PALETTE[((rank - 1) % #PALETTE) + 1]
end
-- Build a { categoryKey → palette color } map from an ordered list of keys (rank = list position),
-- so a category keeps one color across the charts that share the same order (e.g. a currency in both
-- Currency Collected and Currency by Character × Type).
local function paletteMap(orderedKeys)
  local m = {}
  for i, k in ipairs(orderedKeys or {}) do m[k] = Analytics.paletteColor(i) end
  return m
end
-- Published for the headless suite alongside the other pure helpers below.
Analytics._paletteMap  = paletteMap
Analytics._shortChar   = shortChar
Analytics._classColor  = classColor
Analytics._qualityColor = qualityColor

-- Cap a bar/row label to a fixed glyph count with a trailing ellipsis. English-only labels, so a
-- byte-based sub is safe (see CLAUDE.md: English only). Pure + testable.
function Analytics._truncate(text, maxChars)
  text = text or ""
  if #text <= maxChars then return text, false end
  return text:sub(1, maxChars - 1) .. "\226\128\166", true
end

-- Reduce a character's per-category magnitudes to at most maxSegs stacked segments: keep the top
-- (maxSegs-1) by magnitude, lump any remainder into a single "__OTHER__" segment, then order the
-- kept segments by their global rank in catOrder ("__OTHER__" always last). Pure + testable.
function Analytics._charStackSegments(catMags, catOrder, maxSegs)
  local list, total = {}, 0
  for k, v in pairs(catMags) do
    if v and v > 0 then list[#list + 1] = { key = k, mag = v }; total = total + v end
  end
  table.sort(list, function(a, b)
    if a.mag ~= b.mag then return a.mag > b.mag end
    return tostring(a.key) < tostring(b.key)
  end)
  local kept, otherMag = {}, 0
  if #list > maxSegs then
    for i = 1, maxSegs - 1 do kept[#kept + 1] = list[i] end
    for i = maxSegs, #list do otherMag = otherMag + list[i].mag end
  else
    for i = 1, #list do kept[#kept + 1] = list[i] end
  end
  local rank = {}
  for i, k in ipairs(catOrder) do rank[k] = i end
  table.sort(kept, function(a, b) return (rank[a.key] or math.huge) < (rank[b.key] or math.huge) end)
  if otherMag > 0 then kept[#kept + 1] = { key = "__OTHER__", mag = otherMag } end
  return kept, total
end

-- Build renderStackedBarSection rows from a char→{cat→mag} matrix. Per-char total drives row width
-- (frac = mag / rowMax); segment colors come from colorFn(catKey) with "__OTHER__" → NEUTRAL; the
-- row label is the short character name, class-colored. Each segment carries a "<category>: <value>"
-- hover tip via labelFn(catKey). Rows sorted by total desc then name asc.
function Analytics._buildCharStackRows(matrix, byCharMap, catOrder, colorFn, valueFmt, labelFn)
  labelFn = labelFn or tostring
  local rowMax, totals = 1, {}
  for ch, mags in pairs(matrix) do
    local _, total = Analytics._charStackSegments(mags, catOrder, MAX_STACK_SEGS)
    totals[ch] = total
    if total > rowMax then rowMax = total end
  end
  local rows = {}
  for ch, mags in pairs(matrix) do
    local segs = Analytics._charStackSegments(mags, catOrder, MAX_STACK_SEGS)
    local segments = {}
    for _, s in ipairs(segs) do
      local isOther = s.key == "__OTHER__"
      local color = isOther and NEUTRAL or (colorFn(s.key) or NEUTRAL)
      local name = isOther and "Other" or labelFn(s.key)
      segments[#segments + 1] = { frac = s.mag / rowMax, color = color,
        tip = name .. ": " .. valueFmt(s.mag) }
    end
    local classFile = byCharMap and byCharMap[ch] and byCharMap[ch].classFile
    rows[#rows + 1] = { label = shortChar(ch), labelColor = classColor(classFile),
      value = valueFmt(totals[ch]), segments = segments, _total = totals[ch] }
  end
  table.sort(rows, function(a, b)
    if a._total ~= b._total then return a._total > b._total end
    return a.label < b.label
  end)
  return rows
end

-- Coin-glyph height for Insights money strings — ~25% smaller than the client default (~14px) so the
-- gold/silver/copper icons don't dominate the bar/card text.
local COIN_H = 10

-- Value → display string (coin glyphs in-game, "Ng Ns Nc" headless; "0" when zero).
local function money(copper)
  copper = copper or 0
  if copper <= 0 then return "0" end
  return NS.Util.FormatMoney(copper, COIN_H)
end

-- ── Widget primitives (pooled) ─────────────────────────────────────────────────────
local function acquire(pool, factory)
  local o = table.remove(pool.free)
  if not o then o = factory() end
  pool.active[#pool.active + 1] = o
  o:Show()
  return o
end
local function releaseAll(pool)
  for _, o in ipairs(pool.active) do o:Hide() end
  wipe(pool.active)
end

-- Hover text for a chart element: the FULL (untruncated) label plus the value it encodes, so a
-- tooltip always states the number as well as the name — on-chart value text is clipped to its
-- column and the label itself is truncated. Label-only when the element carries no value.
function Analytics._tipText(label, value)
  label = label or ""
  if value == nil or value == "" then return label end
  if label == "" then return tostring(value) end
  return label .. ":  " .. value
end

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

-- Stat / highlight cards, in row order (4 columns per row; `wide` spans 2). `str` cards hold a
-- string (smaller font). Value strings are produced in UpdateCards.
local CARD_DEFS = {
  { key = "records", label = "records" },
  { key = "items",   label = "distinct items" },
  { key = "chars",   label = "characters" },
  { key = "value",   label = "value", str = true, bigStr = true },
  { key = "active",  label = "active days" },
  { key = "epic",    label = "epic+ drops" },
  { key = "best",    label = "best drop (ilvl)" },
  { key = "richest", label = "richest drop", str = true, bigStr = true },
  { key = "span",    label = "date range", str = true, bigStr = true, wide = true },
  { key = "busy",    label = "busiest day", str = true, bigStr = true, wide = true },
}

-- ── Build ────────────────────────────────────────────────────────────────────────

function Analytics:Attach(pane)
  if self.pane then return end
  self.pane = pane

  -- No range selector here (issue #13): the Insights view is scoped by the browser's shared filter
  -- bar (its Date dropdown + every column filter), so the charts fill the whole pane below.
  local scroll = CreateFrame("ScrollFrame", nil, pane, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -26, 4)
  self.scroll = scroll
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  self.content = content
  scroll:SetScript("OnSizeChanged", function() Analytics:Layout() end)

  -- Cards.
  self.cards = {}
  for _, def in ipairs(CARD_DEFS) do
    local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
    card:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                       insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    card:SetBackdropColor(0.1, 0.1, 0.12, 0.85)
    card:SetBackdropBorderColor(0.24, 0.24, 0.27, 0.9)
    -- Plain string cards (date range / busiest day) hold a long value → small font. The `value`
    -- and `richest` cards keep the big headline font (bigStr) and shrink-to-fit in Layout instead.
    local fontTemplate = (def.str and not def.bigStr) and "GameFontNormal" or "GameFontNormalHuge"
    local num = card:CreateFontString(nil, "OVERLAY", fontTemplate)
    if def.bigStr then num:SetWordWrap(false) end
    num:SetPoint("TOP", 0, -9)
    num:SetPoint("LEFT", 2, 0)
    num:SetPoint("RIGHT", -2, 0)
    num:SetJustifyH("CENTER")
    num:SetTextColor(1, 0.82, 0)
    local cl = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cl:SetPoint("BOTTOM", 0, 7)
    cl:SetText(def.label)
    local entry = { frame = card, num = num, bigStr = def.bigStr }
    if def.bigStr then
      local file, size, flags = num:GetFont()
      entry.fontFile, entry.baseSize, entry.fontFlags = file, size, flags
    end
    self.cards[def.key] = entry
  end

  self:BuildCharts(content)
  self:Refresh()
end

-- ── Refresh + layout ──────────────────────────────────────────────────────────────

-- Pure one-line summary for the [Insights] trace.
function Analytics.SummaryLine(scope, count)
  return ("computed range=%s, %s records"):format(tostring(scope), tostring(count))
end

function Analytics:Refresh()
  if not self.content then return end
  -- Scope by the browser's shared filter (issue #13) so the Insights view and the History table
  -- always reflect the exact same criteria; empty filter = the whole (visible) history.
  local filter = (NS.Browser and NS.Browser.CurrentFilter and NS.Browser:CurrentFilter()) or {}
  local stats = NS.Database:Stats(filter)
  self.stats = stats
  self:UpdateCards(stats)
  self:Layout() -- Layout → LayoutCharts binds the charts off self.stats
  if NS.State.debug and NS.Debug then
    local scope = next(filter) and "filtered" or "all"
    NS.Debug("Insights", "%s", Analytics.SummaryLine(scope, stats.totals.records))
  end
end

function Analytics:UpdateCards(stats)
  local t = stats.totals
  local dash = "\226\128\148" -- em-dash
  self.cards.records.num:SetText(tostring(t.records))
  self.cards.items.num:SetText(tostring(t.distinctItems))
  self.cards.chars.num:SetText(tostring(t.distinctChars))
  self.cards.value.num:SetText(money(t.totalValue))
  self.cards.active.num:SetText(tostring(t.activeDays))
  self.cards.epic.num:SetText(tostring(t.epicPlus))
  self.cards.best.num:SetText(t.bestDrop and tostring(t.bestDrop.itemLevel) or dash)
  self.cards.richest.num:SetText(t.richestDrop and money(t.richestDrop.value) or dash)
  local span = dash
  if t.firstTs and t.lastTs then
    span = NS.Util.FormatDate(t.firstTs) .. "  \226\128\147  " .. NS.Util.FormatDate(t.lastTs) -- – en-dash
  end
  self.cards.span.num:SetText(span)
  self.cards.busy.num:SetText(t.busiestDay and (t.busiestDay.day .. "  (" .. t.busiestDay.count .. ")") or dash)
end

-- Position everything top-down given the current content width; set the scroll child height.
function Analytics:Layout()
  if not self.content then return end
  local w = self.scroll:GetWidth()
  if not w or w <= 0 then w = 780 end
  self.content:SetWidth(w)

  local PAD, GAP, COLS = 8, 8, 4
  local colW = math.floor((w - PAD * 2 - GAP * (COLS - 1)) / COLS)
  local cardH = 52
  local col, rowY = 0, -PAD
  for _, def in ipairs(CARD_DEFS) do
    local span = def.wide and 2 or 1
    if col + span > COLS then col = 0; rowY = rowY - cardH - GAP end
    local c = self.cards[def.key]
    c.frame:ClearAllPoints()
    c.frame:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD + col * (colW + GAP), rowY)
    c.frame:SetSize(colW * span + GAP * (span - 1), cardH)
    if c.bigStr and c.baseSize then
      c.num:SetFont(c.fontFile, c.baseSize, c.fontFlags) -- reset to base, then shrink if it overflows
      local maxW = colW * span + GAP * (span - 1) - 12   -- card inner width (small padding)
      local size = Analytics._fitFontSize(c.num:GetStringWidth(), maxW, c.baseSize, MIN_HEADLINE_SIZE)
      if size < c.baseSize then c.num:SetFont(c.fontFile, size, c.fontFlags) end
    end
    col = col + span
  end

  local y = rowY - cardH - 14
  y = self:LayoutCharts(y, w, PAD)
  self.content:SetHeight(math.max(1, -y + PAD))
end

-- ── Charts ─────────────────────────────────────────────────────────────────────────

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

-- Build the persistent chart chrome (section headers, strips, list panels, pools) once.
function Analytics:BuildCharts(content)
  self.headers = {
    char    = sectionHeader(content, "Loot By Character"),
    source  = sectionHeader(content, "Loot By Source"),
    charBySource = sectionHeader(content, "Loot By Character \195\151 Source"),
    vsource = sectionHeader(content, "Value By Source"),
    charValueSource = sectionHeader(content, "Value By Character \195\151 Source"),
    quality = sectionHeader(content, "Loot By Quality"),
    charQuality = sectionHeader(content, "Loot By Character \195\151 Quality"),
    itype   = sectionHeader(content, "Loot By Item Type"),
    charType = sectionHeader(content, "Loot By Character \195\151 Item Type"),
    bound   = sectionHeader(content, "Loot By Bound Type"),
    charBound = sectionHeader(content, "Loot By Character \195\151 Bound Type"),
    time    = sectionHeader(content, "Loot Over Time (Per Day)"),
    vtime   = sectionHeader(content, "Value Over Time (Per Day)"),
    hour    = sectionHeader(content, "Loot By Hour Of Day"),
    weekday = sectionHeader(content, "Loot By Weekday"),
    currencyCollected = sectionHeader(content, "Currency Collected"),
    currencySrc   = sectionHeader(content, "Currency By Type \195\151 Source"),
    currencyChar  = sectionHeader(content, "Currency By Character \195\151 Type"),
    currencyTime  = sectionHeader(content, "Currency Over Time (Per Day)"),
  }
  self.lootDivider = sectionDivider(content, "LOOT")
  self.currencyDivider = sectionDivider(content, "CURRENCY")
  self.dayStrip   = CreateFrame("Frame", nil, content)
  self.valueStrip = CreateFrame("Frame", nil, content)
  self.hourStrip  = CreateFrame("Frame", nil, content)
  self.zonePanel  = listPanel(content, "Top Zones")
  self.itemPanel  = listPanel(content, "Top Items By Count")
  self.itemValuePanel = listPanel(content, "Top Items By Value")
  self.currencyStrip = CreateFrame("Frame", nil, content)
  self.emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
  self.emptyText:SetText("No loot in this range.")
  self.emptyText:Hide()
  self.pool = {
    source = { free = {}, active = {} }, vsource = { free = {}, active = {} },
    quality = { free = {}, active = {} },
    itype  = { free = {}, active = {} }, bound   = { free = {}, active = {} },
    char   = { free = {}, active = {} }, day     = { free = {}, active = {} },
    vday   = { free = {}, active = {} }, hour    = { free = {}, active = {} },
    weekday = { free = {}, active = {} },
    zone    = { free = {}, active = {} },
    item   = { free = {}, active = {} }, itemval = { free = {}, active = {} },
    curcollected = { free = {}, active = {} }, curcollectedleg = { free = {}, active = {} },
    cursrc = { free = {}, active = {} }, curlegend = { free = {}, active = {} },
    curchar = { free = {}, active = {} }, curcharlegend = { free = {}, active = {} },
    curday = { free = {}, active = {} },
    -- Legends for the single-bar categorical charts.
    sourceleg = { free = {}, active = {} }, vsourceleg = { free = {}, active = {} },
    qualityleg = { free = {}, active = {} }, itypeleg = { free = {}, active = {} },
    boundleg = { free = {}, active = {} },
    -- Per-character × category companion stacked bars + their color legends (one pool each).
    chsource = { free = {}, active = {} }, chsourceleg = { free = {}, active = {} },
    chvsource = { free = {}, active = {} }, chvsourceleg = { free = {}, active = {} },
    chquality = { free = {}, active = {} }, chqualityleg = { free = {}, active = {} },
    chtype = { free = {}, active = {} }, chtypeleg = { free = {}, active = {} },
    chbound = { free = {}, active = {} }, chboundleg = { free = {}, active = {} },
  }

  -- Live-update while the Insights tab is visible (new loot / deletes / prune).
  if NS.bus and not self._subscribed then
    self._subscribed = true
    local function live()
      if self.pane and self.pane:IsVisible() then Analytics:Refresh() end
    end
    -- Private bus target (never the shared bus-as-self) so these don't clobber the Browser's
    -- RecordAdded/HistoryChanged handlers on the same bus. See NS.NewBusTarget.
    self.__ev = NS.NewBusTarget() or NS.bus
    self.__ev:RegisterMessage("Ka0s_LootHistory_RecordAdded", live)
    self.__ev:RegisterMessage("Ka0s_LootHistory_HistoryChanged", live)
  end
end

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
    local bar = acquire(pool, function() return makeBar(self.content) end)
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
    local bar = acquire(pool, function() return makeStackedBar(self.content) end)
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
    local chip = acquire(pool, function() return makeSwatch(self.content) end)
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
    local f = acquire(pool, function() return makeStripBar(strip) end)
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
    local r = acquire(pool, function() return makeListRow(panel) end)
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
end

-- Build the firstTs..lastTs day-key list (gaps included), capped to MAX_DAY_BARS most recent.
local function dayKeyList(firstTs, lastTs)
  local keys = {}
  if not (firstTs and lastTs) then return keys end
  local function dayStart(ts) local d = date("*t", ts); return ts - (d.hour * 3600 + d.min * 60 + d.sec) end
  for ts = dayStart(firstTs), dayStart(lastTs), 86400 do keys[#keys + 1] = date("%Y-%m-%d", ts) end
  if #keys > MAX_DAY_BARS then
    local trimmed = {}
    for i = #keys - MAX_DAY_BARS + 1, #keys do trimmed[#trimmed + 1] = keys[i] end
    keys = trimmed
  end
  return keys
end

-- "YYYY-MM-DD" → compact "M/D" for the per-day strip's x-axis labels.
local function shortDay(k)
  local m, d = k:match("^%d+%-(%d+)%-(%d+)$")
  if m then return tonumber(m) .. "/" .. tonumber(d) end
  return k
end

-- Sort a key→count map into a { key, count } array, count desc then key asc.
local function sortedByCount(map)
  local rows = {}
  for k, c in pairs(map) do rows[#rows + 1] = { key = k, count = c } end
  table.sort(rows, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return tostring(a.key) < tostring(b.key)
  end)
  return rows
end

-- Published for the headless suite (pure).
Analytics._dayKeyList   = dayKeyList
Analytics._shortDay     = shortDay
Analytics._sortedByCount = sortedByCount
Analytics._money        = money

-- Bind + position every chart off self.stats for the given width; return the final y cursor.
function Analytics:LayoutCharts(y, w, pad)
  local stats, P = self.stats, self.pool
  for _, name in ipairs({ "source", "vsource", "quality", "itype", "bound", "char",
                          "day", "vday", "hour", "weekday", "zone", "item", "itemval",
                          "curcollected", "curcollectedleg", "cursrc", "curlegend", "curchar", "curcharlegend", "curday",
                          "sourceleg", "vsourceleg", "qualityleg", "itypeleg", "boundleg",
                          "chsource", "chsourceleg", "chvsource", "chvsourceleg", "chquality", "chqualityleg",
                          "chtype", "chtypeleg", "chbound", "chboundleg" }) do
    releaseAll(P[name])
  end

  if not stats or stats.totals.records == 0 then
    self:HideAllCharts()
    self.emptyText:ClearAllPoints()
    self.emptyText:SetPoint("TOP", self.content, "TOP", 0, y - 10)
    self.emptyText:Show()
    return y - 50
  end
  self.emptyText:Hide()
  local H, total = self.headers, stats.totals.records
  local rows

  self.lootDivider:ClearAllPoints()
  self.lootDivider:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y)
  self.lootDivider:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -pad, y)
  self.lootDivider:Show()
  y = y - 30

  -- Loot by character (first chart in the LOOT section) — class-colored, sorted by count desc.
  -- byChar registers currency-only characters with count 0 (for class colors elsewhere); skip them.
  rows = {}
  local chRows = {}
  for _, ce in pairs(stats.byChar) do if ce.count > 0 then chRows[#chRows + 1] = ce end end
  table.sort(chRows, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.char < b.char
  end)
  local chMax = 1
  for _, ce in ipairs(chRows) do if ce.count > chMax then chMax = ce.count end end
  for _, ce in ipairs(chRows) do
    rows[#rows + 1] = { label = shortChar(ce.char), color = classColor(ce.classFile),
      frac = ce.count / chMax, value = tostring(ce.count) }
  end
  y = self:renderBarSection(P.char, H.char, rows, y, w, pad)

  -- Loot by source — length = share of all records.
  rows = {}
  for _, e in ipairs(sortedByCount(stats.bySource)) do
    rows[#rows + 1] = {
      label = NS.Constants.SourceLabel[e.key] or e.key, color = SOURCE_COLOR[e.key] or NEUTRAL,
      frac = e.count / total, value = string.format("%d  %d%%", e.count, math.floor(e.count / total * 100 + 0.5)),
    }
  end
  y = self:renderBarSection(P.source, H.source, rows, y, w, pad, P.sourceleg)

  -- Loot by Character × Source — companion. Segment order matches the parent's Y axis (count desc).
  local srcOrder = {}
  for _, e in ipairs(sortedByCount(stats.bySource)) do srcOrder[#srcOrder + 1] = e.key end
  local function srcColor(k) return SOURCE_COLOR[k] or NEUTRAL end
  local function srcLabel(k) return NS.Constants.SourceLabel[k] or k end
  y = self:renderCharCompanion("chsource", "chsourceleg", H.charBySource, stats.charBySource,
    srcOrder, srcColor, srcLabel, function(t) return tostring(t) end, y, w, pad)

  -- Vendor value by source — length relative to the biggest bucket, ordered by value desc.
  rows = {}
  local vMax = 1
  for _, v in pairs(stats.valueBySource) do if v > vMax then vMax = v end end
  local vsrc = {}
  for src, v in pairs(stats.valueBySource) do vsrc[#vsrc + 1] = { src = src, v = v } end
  table.sort(vsrc, function(a, b) if a.v ~= b.v then return a.v > b.v end return a.src < b.src end)
  local vsrcOrder = {}
  for _, e in ipairs(vsrc) do
    vsrcOrder[#vsrcOrder + 1] = e.src
    if e.v > 0 then
      rows[#rows + 1] = { label = NS.Constants.SourceLabel[e.src] or e.src,
        color = SOURCE_COLOR[e.src] or NEUTRAL, frac = e.v / vMax, value = money(e.v) }
    end
  end
  y = self:renderBarSection(P.vsource, H.vsource, rows, y, w, pad, P.vsourceleg)

  -- Value by Character × Source — companion. Segment order matches the parent's Y axis (value desc).
  y = self:renderCharCompanion("chvsource", "chvsourceleg", H.charValueSource, stats.charValueBySource,
    vsrcOrder, srcColor, srcLabel, function(t) return money(t) end, y, w, pad)

  -- Quality distribution — bars in quality order, length relative to the biggest bucket.
  rows = {}
  local qRows, qMax = {}, 1
  for q, c in pairs(stats.byQuality) do qRows[#qRows + 1] = { q = q, c = c }; if c > qMax then qMax = c end end
  table.sort(qRows, function(a, b) return a.q < b.q end)
  for _, e in ipairs(qRows) do
    local col = qualityColor(e.q)
    rows[#rows + 1] = { label = NS.Compat.QualityLabel(e.q), labelColor = col, color = col,
      frac = e.c / qMax, value = tostring(e.c) }
  end
  y = self:renderBarSection(P.quality, H.quality, rows, y, w, pad, P.qualityleg)

  -- Loot by Character × Quality — companion, segments colored by item quality (parent order).
  local qOrder = {}
  for q = 0, 8 do if stats.byQuality[q] then qOrder[#qOrder + 1] = q end end
  y = self:renderCharCompanion("chquality", "chqualityleg", H.charQuality, stats.charByQuality,
    qOrder, function(q) return qualityColor(q) end, function(q) return NS.Compat.QualityLabel(q) end,
    function(t) return tostring(t) end, y, w, pad)

  -- Loot by item type — bars colored per type from the standard palette (rank = sort order); the
  -- Character × Item Type companion reuses the same map so a type keeps its color across both.
  local tyKeys = {}
  for _, e in ipairs(sortedByCount(stats.byType)) do tyKeys[#tyKeys + 1] = e.key end
  local typeColor = paletteMap(tyKeys)
  rows = {}
  for _, e in ipairs(sortedByCount(stats.byType)) do
    rows[#rows + 1] = { label = e.key, color = typeColor[e.key] or NEUTRAL,
      frac = e.count / total, value = tostring(e.count) }
  end
  y = self:renderBarSection(P.itype, H.itype, rows, y, w, pad, P.itypeleg)

  y = self:renderCharCompanion("chtype", "chtypeleg", H.charType, stats.charByType,
    tyKeys, function(k) return typeColor[k] or NEUTRAL end, function(k) return k end,
    function(t) return tostring(t) end, y, w, pad)

  -- Loot by bound type — sorted count desc; the companion reuses this exact order for its segments.
  rows = {}
  local bRows = {}
  for _, bk in ipairs(BOUND_ORDER) do
    local c = stats.byBound[bk]
    if c then bRows[#bRows + 1] = { bk = bk, c = c } end
  end
  table.sort(bRows, function(a, b) if a.c ~= b.c then return a.c > b.c end return a.bk < b.bk end)
  local boundOrder = {}
  for _, e in ipairs(bRows) do
    boundOrder[#boundOrder + 1] = e.bk
    rows[#rows + 1] = { label = BOUND_LABEL[e.bk] or e.bk, color = BOUND_COLOR[e.bk] or NEUTRAL,
      frac = e.c / total, value = tostring(e.c) }
  end
  y = self:renderBarSection(P.bound, H.bound, rows, y, w, pad, P.boundleg)

  -- Loot by Character × Bound Type — companion. Segment order matches the parent's Y axis (count desc).
  y = self:renderCharCompanion("chbound", "chboundleg", H.charBound, stats.charByBound,
    boundOrder, function(k) return BOUND_COLOR[k] or NEUTRAL end,
    function(k) return BOUND_LABEL[k] or k end, function(t) return tostring(t) end, y, w, pad)

  -- Loot over time + vendor value over time — two per-day strips over the same day range.
  local keys = dayKeyList(stats.totals.firstTs, stats.totals.lastTs)
  local dayB, valB = {}, {}
  for _, k in ipairs(keys) do
    local c = stats.byDay[k] or 0
    local v = stats.valueByDay[k] or 0
    local lbl = shortDay(k)
    dayB[#dayB + 1] = { info = k .. ":  " .. c, count = c, label = lbl }
    valB[#valB + 1] = { info = k .. ":  " .. money(v), count = v, label = lbl }
  end
  y = self:renderStrip(P.day, H.time, self.dayStrip, dayB, y, w, pad)
  y = self:renderStrip(P.vday, H.vtime, self.valueStrip, valB, y, w, pad)

  -- Loot by hour of day — 24 fixed buckets.
  local hourB = {}
  for h = 0, 23 do
    local c = stats.byHour[h] or 0
    hourB[#hourB + 1] = { info = string.format("%02d:00  %d", h, c), count = c, label = string.format("%02d", h) }
  end
  y = self:renderStrip(P.hour, H.hour, self.hourStrip, hourB, y, w, pad)

  -- Loot by weekday — Sun..Sat, each day a unique palette color (Sun=rank 1 … Sat=rank 7).
  rows = {}
  local wMax = 1
  for _, c in pairs(stats.byWeekday) do if c > wMax then wMax = c end end
  for d = 0, 6 do
    local c = stats.byWeekday[d]
    if c then rows[#rows + 1] = { label = WEEKDAY[d], color = Analytics.paletteColor(d + 1),
      frac = c / wMax, value = tostring(c) } end
  end
  y = self:renderBarSection(P.weekday, H.weekday, rows, y, w, pad)

  -- Ranked lists — two half-width columns:
  --   left  : Top items by value → Top zones (stacked)
  --   right : Top items by count
  local colGap = 12
  local colW = math.floor((w - pad * 2 - colGap) / 2)
  local leftX, rightX = pad, pad + colW + colGap
  local MONEY_W = 110  -- value column wide enough for "Ng Ns Nc" coin strings (no wrapping)

  -- Top items by value (left, top).
  local valRows = {}
  for i = 1, math.min(10, #stats.topItemsByValue) do
    local it = stats.topItemsByValue[i]
    if (it.value or 0) > 0 then
      local star = ((it.quality or 1) >= 4) and starMarkup() or ""
      valRows[#valRows + 1] = { name = star .. (it.itemName or ("item " .. (it.itemID or "?"))),
        nameColor = qualityColor(it.quality or 1), right = money(it.value) }
    end
  end

  -- Top items by count (right, top).
  local itemRows = {}
  for i = 1, math.min(10, #stats.topItems) do
    local it = stats.topItems[i]
    local star = ((it.quality or 1) >= 4) and starMarkup() or ""
    itemRows[#itemRows + 1] = { name = star .. (it.itemName or ("item " .. (it.itemID or "?"))),
      nameColor = qualityColor(it.quality or 1), right = tostring(it.count) }
  end

  -- Top zones (left, below the value list).
  local zoneRows = {}
  for i = 1, math.min(10, #stats.topZones) do
    local z = stats.topZones[i]
    zoneRows[#zoneRows + 1] = { name = z.zone, right = tostring(z.count) }
  end

  local zoneY = y
  if #valRows > 0 then
    local hVal = self:renderListPanel(P.itemval, self.itemValuePanel, valRows, y, colW, leftX, MONEY_W)
    zoneY = y - hVal - SECTION_GAP
  else
    self.itemValuePanel:Hide()
  end
  local hItem = self:renderListPanel(P.item, self.itemPanel, itemRows, y, colW, rightX)
  local hZone = self:renderListPanel(P.zone, self.zonePanel, zoneRows, zoneY, colW, leftX)

  local leftH = (y - zoneY) + hZone -- top of column (y) down to the bottom of the zone panel
  y = y - math.max(leftH, hItem) - SECTION_GAP
  -- (fall through to Currency)

  -- ── Currency ──────────────────────────────────────────────────────────────────
  local ct = stats.currencyTotals or { distinct = 0, events = 0 }
  if ct.events and ct.events > 0 then
    self.currencyDivider:ClearAllPoints()
    self.currencyDivider:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y)
    self.currencyDivider:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -pad, y)
    self.currencyDivider:Show()
    y = y - 30

    -- Currency Collected — one bar per currency, colored per currency from the standard palette
    -- (rank = qty order). curColor is shared with Currency by Character × Type so a currency keeps one
    -- color across both charts.
    local curKeys = {}
    for _, e in ipairs(sortedByCount(stats.byCurrency)) do curKeys[#curKeys + 1] = e.key end
    local curColor = paletteMap(curKeys)
    local curMaxCollected = 1
    for _, curTotal in pairs(stats.byCurrency) do if curTotal > curMaxCollected then curMaxCollected = curTotal end end
    local collectedRows = {}
    for _, e in ipairs(sortedByCount(stats.byCurrency)) do
      collectedRows[#collectedRows + 1] = { label = e.key, color = curColor[e.key] or NEUTRAL,
        frac = e.count / curMaxCollected, value = tostring(e.count) }
    end
    y = self:renderBarSection(P.curcollected, H.currencyCollected, collectedRows, y, w, pad, P.curcollectedleg)

    -- Currency by Type × Source: one stacked bar per currency, segments colored by source.
    local curMax = 1
    for _, curTotal in pairs(stats.byCurrency) do if curTotal > curMax then curMax = curTotal end end
    local stackRows = {}
    for _, e in ipairs(sortedByCount(stats.byCurrency)) do
      local perSrc = stats.currencySourceMatrix[e.key] or {}
      local order = {}
      for srcKey in pairs(perSrc) do order[#order + 1] = srcKey end
      table.sort(order, function(a, b) return (perSrc[a] or 0) > (perSrc[b] or 0) end)
      local curSegs = {}
      for _, srcKey in ipairs(order) do
        curSegs[#curSegs + 1] = { frac = (perSrc[srcKey] or 0) / curMax, color = SOURCE_COLOR[srcKey] or NEUTRAL,
          tip = (NS.Constants.SourceLabel[srcKey] or srcKey) .. ": " .. (perSrc[srcKey] or 0) }
      end
      stackRows[#stackRows + 1] = { label = e.key, value = tostring(e.count), segments = curSegs }
    end
    y = self:renderStackedBarSection(P.cursrc, H.currencySrc, stackRows, y, w, pad)

    local legendRows = {}
    for _, le in ipairs(sortedByCount(stats.currencyBySource or {})) do
      legendRows[#legendRows + 1] = { label = NS.Constants.SourceLabel[le.key] or le.key,
        color = SOURCE_COLOR[le.key] or NEUTRAL }
    end
    y = self:renderLegend(P.curlegend, legendRows, y, w, pad)

    -- Currency by Character × Type — one stacked bar per character, segmented by currency (each a
    -- distinct palette color, shared with Currency Collected via curColor). Currencies ordered by
    -- global qty so a given currency keeps a consistent segment position across character rows.
    local ccRows = Analytics._buildCharStackRows(stats.currencyCharMatrix, stats.byChar, curKeys,
      function(cname) return curColor[cname] or NEUTRAL end, function(t) return tostring(t) end,
      function(cname) return cname end)
    y = self:renderStackedBarSection(P.curchar, H.currencyChar, ccRows, y, w, pad)

    -- Legend: one swatch per currency, matching the segment colors.
    local curCharLegend = {}
    for _, cname in ipairs(curKeys) do
      curCharLegend[#curCharLegend + 1] = { label = cname, color = curColor[cname] or NEUTRAL }
    end
    y = self:renderLegend(P.curcharlegend, curCharLegend, y, w, pad)

    -- Currency over time (per-day strip of total currency quantity).
    local ckeys = dayKeyList(stats.totals.firstTs, stats.totals.lastTs)
    local curDayB = {}
    for _, k in ipairs(ckeys) do
      local c = stats.currencyByDay[k] or 0
      curDayB[#curDayB + 1] = { info = k .. ":  " .. c, count = c, label = shortDay(k) }
    end
    y = self:renderStrip(P.curday, H.currencyTime, self.currencyStrip, curDayB, y, w, pad)
  else
    H.currencyCollected:Hide(); H.currencySrc:Hide(); H.currencyChar:Hide(); H.currencyTime:Hide()
    self.currencyStrip:Hide()
    self.currencyDivider:Hide()
  end

  return y
end
