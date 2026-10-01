local _, NS = ...
NS.Analytics = NS.Analytics or {}
local Analytics = NS.Analytics

-- The Insights tab's pure half: layout constants, color tables and palettes, and the formatting
-- and segmenting helpers. No frame is built here and nothing reads the client but the star-atlas
-- probe and the class/quality color tables, each at call time. Loaded BEFORE modules/Analytics.lua,
-- which binds what it needs to file-scope locals at load (docs/common-tasks.md, hot-path upvalues),
-- and before modules/AnalyticsCharts.lua, which does the same. Peeled out of modules/Analytics.lua
-- (LootHistory#32) verbatim; the _-prefixed names below were already the suite's seam.

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
  -- ONE _charStackSegments call per character (LH-R-09). Two passes are still needed — a segment's
  -- `frac` is measured against rowMax, and rowMax is not knowable until every character's total is
  -- in — but the first pass used to discard the segment list it had just built and the second pass
  -- rebuilt it, paying two table.sorts per character for a result it already had. The segments are
  -- kept instead. Same output, half the work, on the Insights repaint path.
  local rowMax, totals, segsByChar = 1, {}, {}
  for ch, mags in pairs(matrix) do
    local segs, total = Analytics._charStackSegments(mags, catOrder, MAX_STACK_SEGS)
    segsByChar[ch], totals[ch] = segs, total
    if total > rowMax then rowMax = total end
  end
  local rows = {}
  for ch in pairs(matrix) do
    local segments = {}
    for _, s in ipairs(segsByChar[ch]) do
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

-- Hover text for a chart element: the FULL (untruncated) label plus the value it encodes, so a
-- tooltip always states the number as well as the name — on-chart value text is clipped to its
-- column and the label itself is truncated. Label-only when the element carries no value.
function Analytics._tipText(label, value)
  label = label or ""
  if value == nil or value == "" then return label end
  if label == "" then return tostring(value) end
  return label .. ":  " .. value
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

-- ── seams for the two files that load after this one ───────────────────────────────────────────
--
-- The layout constants and the color tables, published once so modules/Analytics.lua and
-- modules/AnalyticsCharts.lua read the same numbers. Both bind these to file-scope locals at load.
Analytics.K = {
  WHITE = WHITE, BAR_H = BAR_H, BAR_GAP = BAR_GAP, SECTION_GAP = SECTION_GAP,
  DAYSTRIP_H = DAYSTRIP_H, STRIP_LABEL_H = STRIP_LABEL_H, STRIP_AXIS_GAP = STRIP_AXIS_GAP,
  STRIP_LABEL_GAP = STRIP_LABEL_GAP, LABEL_X_ADJUST = LABEL_X_ADJUST, LIST_ROW_H = LIST_ROW_H,
  LABELW = LABELW, VALW = VALW, LABEL_MAXCHARS = LABEL_MAXCHARS, LEGEND_MAXCHARS = LEGEND_MAXCHARS,
  MAX_STACK_SEGS = MAX_STACK_SEGS, MIN_HEADLINE_SIZE = MIN_HEADLINE_SIZE, MAX_DAY_BARS = MAX_DAY_BARS,
  NEUTRAL = NEUTRAL, COIN_H = COIN_H,
}
Analytics._fmt = {
  SOURCE_COLOR = SOURCE_COLOR, BOUND_LABEL = BOUND_LABEL, BOUND_COLOR = BOUND_COLOR,
  BOUND_ORDER = BOUND_ORDER, WEEKDAY = WEEKDAY, starMarkup = starMarkup,
}
