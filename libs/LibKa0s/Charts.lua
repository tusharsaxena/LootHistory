-- LibKa0s-Charts-1.0 — the Insights chart renderers: the shell. This file holds the host seams,
-- the context and the pure helpers; ChartsRender.lua holds the widgets and the renderers.
--
-- ── WHY THIS EXISTS ──────────────────────────────────────────────────────────────────────────
--
-- Ka0s Loot History's Insights tab grew pooled horizontal bars, stacked bars, vertical strips,
-- ranked list panels, legends, stat cards and section dividers (its modules/AnalyticsCharts.lua and
-- AnalyticsFormat.lua). Ka0s DPS Race's Insights tab needed the same shapes and carried a private,
-- host-agnostic port (its modules/Results_InsightsCharts.lua, DpsRace#12). This file is that port,
-- once, with the names kept so a consumer's diff is a swap of the table it calls (LibKa0s#66). Ka0s
-- Bank Ledger and Ka0s Drop Watcher are the owner's next two in line.
--
-- ── THE CONTRACT ─────────────────────────────────────────────────────────────────────────────
--
-- `Charts:New(content, host)` answers a context drawing into `content`. One config table, `host`,
-- carries everything the host owns, and every field is optional:
--   host.owner    a registered skin owner: the colors, the palette, the faces, the bar texture and
--                 the panels then come from that owner's skin, and a skin switch reaches them
--   host.pool     a pool API, New() / Acquire(pool, factory) / ReleaseAll(pool); LibKa0s-Pool-1.0's
--                 when left out. With neither, New raises
--   host.panel    function(parent) -> a bordered frame, for list panels and cards
--   host.tip      function(owner, lines, anchor): show `lines` (a title, then strings)
--   host.hideTip  function()
--   host.colors   { body, value, muted, heading, caption, rule, track, bar, axis, tipTitle, tipBody },
--                 each { r, g, b[, a] } or a function answering one
--   host.fonts    { label, axis, heading, divider, panelTitle, caption, figure }: font object names
--   host.palette  the ranked palette, a list of { r, g, b }, or a function answering one
--   host.text     function(parent, font, justify) -> a FontString in that font object
--   host.paint    function(fs, color): a label's color (and the host's face for it)
--   host.fill     function(texture, color, alpha): a texture's flat color
--   host.barFill  function(texture, color, alpha): a bar of data's fill
--   host.onReskin function(ctx): redraw the bound rows, after Reskin repainted the chrome
-- docs/api/Charts/version-1.1-docs.md is the full contract, and each row's fields are on its renderer
-- below.
--
-- ── WHERE A LOOK COMES FROM ──────────────────────────────────────────────────────────────────
--
-- The host first, then the owner's skin, then Ka0s Default's values, field by field. So a host with
-- no skin owner gets a working chart from `Charts:New(content, {})`, and a host with an owner names
-- only what it wants different. The tokens are Loot History's: `text.*`, `section.rule`, `chart.*`
-- and `gtip.*`. Skin is read at call time and is optional: without it, or for an owner that is not
-- registered, the skin half is simply not there.
--
-- ── EVERY SEAM IS THE CONTEXT'S ──────────────────────────────────────────────────────────────
--
-- DPS Race's port kept the drawing seams in file locals, "the last host's", because it was one
-- addon's file. This file is shared process-wide across addons through LibStub, so that would hand
-- one addon's paint to another's chart. Every factory reads the context it was built for.
--
-- ── POOLED AND REPAINTED ─────────────────────────────────────────────────────────────────────
--
-- Every widget a render draws comes from a pool the context names (`ctx:Pool(name)`), and
-- `ctx:ReleaseAll()` parks them all, so a layout pass after the first builds no frame. Each widget
-- that paints at build time keeps that paint as its `_reskin`, and the chrome the context made is on
-- `ctx.chrome`, so `ctx:Reskin()` reaches the free list and the active list alike, with the same
-- calls. An owner's context calls it itself on the owner's OnLooksChanged. What a row was bound with
-- is the host's data, so a redraw of the rows is `host.onReskin`'s.
--
-- ── WHAT STAYED IN THE ADDONS ────────────────────────────────────────────────────────────────
--
-- Row building: what a bar means, its colors for a class or a quality, the money strings, the day
-- keys, the layout pass that walks the sections, and when to render. Loot History's rotated strip
-- labels did not come: in game they crossed the axis line, so a strip's labels here are level, in a
-- short band under it, and thinned by the room between them (DPS Race's owner round of 2026-10-28).
--
-- ── DEPENDENCIES ─────────────────────────────────────────────────────────────────────────────
--
-- LibStub and LibKa0s-Core-1.0 minor 1 or newer, for the same reason Glow gates on it: a partial
-- payload gets every module absent rather than a working half. LibKa0s-Pool-1.0 and
-- LibKa0s-Skin-1.0 are resolved at call time. Nothing here is a protected call, so it works in
-- combat.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Charts-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.Charts = MINOR

-- ── constants ────────────────────────────────────────────────────────────────────────────────

--- The layout constants, shared across addons, so read them and never write them.
local K = {
  BAR_H = 16, BAR_GAP = 3, SECTION_GAP = 16,
  BAR_H2 = 26,            -- a bar row whose label takes two lines (a row with a `sublabel`)
  HEADER_H = 18,          -- a section heading's line, above its first bar
  TRACK_GAP = 6,          -- between a bar's label column and its track
  DAYSTRIP_H = 46,
  STRIP_LABEL_H = 16,     -- the band under a strip's axis line that holds its level labels
  STRIP_AXIS_GAP = 2,     -- gap between the column bases and the separator line
  STRIP_LABEL_GAP = 3,    -- gap between the separator line and the label text
  STRIP_BAR_MAX = 36,     -- a strip column's widest
  STRIP_SLOT_MAX = 48,    -- a strip slot's widest: a few buckets sit side by side, not far apart
  STRIP_LABEL_PITCH = 40, -- the least room between two axis labels' centers; closer ones drop
  RANGE_MIN_W = 3,        -- a range bar's narrowest (one run, or runs all alike)
  RANGE_MARK_W = 2,       -- a range bar's average mark
  RANGE_SCALE_H = 14,     -- the line under a range section naming its scale's two ends
  LIST_ROW_H = 16, LIST_MAX = 10,
  LIST_TITLE_H = 20,      -- a list panel's title band, above its first row
  LABELW = 108, VALW = 92,   -- fixed label and value columns in a bar; the track fills the rest
  LABEL_MAXCHARS = 16,    -- cap a bar or row label to this many glyphs (+ ellipsis)
  LEGEND_MAXCHARS = 13,   -- cap a legend chip's label to this many glyphs (+ ellipsis)
  MAX_STACK_SEGS = 9,     -- segment ceiling per stacked bar
  CHIP_W = 120, CHIP_H = 14, LEGEND_ROW_H = 16,
  DIVIDER_H = 26,
  CARD_H = 52,
  MIN_HEADLINE_SIZE = 11, -- floor for a card's shrink-to-fit figure
}
lib.K = K

--- The key StackSegments folds the remainder under.
lib.OTHER = "__OTHER__"

-- Three periods and not the ellipsis glyph: a skin's face may draw that glyph as an empty box
-- (tests/test_prose.lua holds the shipped payload to it). Loot History's port drew the glyph.
local ELLIPSIS = "..."

-- Ka0s Default's values (SkinDefs.lua, the tokens below), for a color nothing else supplies.
local DEFAULT_COLORS = {
  body = { 0.9, 0.9, 0.9 }, value = { 0.8, 0.8, 0.82 }, muted = { 0.7, 0.7, 0.72 },
  heading = { 1, 0.82, 0 }, caption = { 0.5, 0.5, 0.5 }, rule = { 1, 0.82, 0, 0.35 },
  track = { 1, 1, 1, 0.06 }, bar = { 0.40, 0.60, 0.95, 0.9 }, axis = { 0.45, 0.45, 0.5, 0.8 },
  tipTitle = { 1, 0.82, 0 }, tipBody = { 1, 1, 1 },
}
-- The skin token each color reads for a context with an owner.
local TOKENS = {
  body = "text.body", value = "text.value", muted = "text.muted", heading = "text.heading",
  caption = "text.disabled", rule = "section.rule", track = "chart.track", bar = "chart.bar",
  axis = "chart.axis", tipTitle = "gtip.title", tipBody = "gtip.value",
}
local DEFAULT_FONTS = {
  label = "GameFontHighlightSmall", axis = "GameFontDisableSmall", heading = "GameFontNormal",
  divider = "GameFontNormalLarge", panelTitle = "GameFontNormalSmall",
  caption = "GameFontDisableSmall", figure = "GameFontNormalHuge",
}
-- Ka0s Default's chart.series: three seven-hue ramps, inverse VIBGYOR, so neighbors in a sorted
-- chart never share a hue.
local DEFAULT_PALETTE = {
  { 0.90, 0.25, 0.25 }, { 0.95, 0.55, 0.15 }, { 0.88, 0.82, 0.22 }, { 0.35, 0.75, 0.38 },
  { 0.28, 0.55, 0.90 }, { 0.42, 0.38, 0.82 }, { 0.72, 0.42, 0.86 },
  { 0.97, 0.58, 0.58 }, { 0.98, 0.76, 0.50 }, { 0.94, 0.90, 0.55 }, { 0.60, 0.87, 0.63 },
  { 0.58, 0.76, 0.97 }, { 0.68, 0.64, 0.92 }, { 0.86, 0.68, 0.94 },
  { 0.62, 0.18, 0.18 }, { 0.70, 0.40, 0.10 }, { 0.60, 0.56, 0.12 }, { 0.18, 0.52, 0.28 },
  { 0.15, 0.38, 0.66 }, { 0.28, 0.24, 0.58 }, { 0.50, 0.28, 0.62 },
}

-- ── the pure helpers ─────────────────────────────────────────────────────────────────────────

--- Cap `text` at `maxChars` glyphs, its trailing "..." among them. Counts UTF-8 glyphs, so a cut
--- never splits one.
--- @return string, boolean  the text, and whether it was cut
function lib.truncate(text, maxChars)
  text = text == nil and "" or tostring(text)
  local n, cut = 0, 1
  for start in text:gmatch("()[^\128-\191][\128-\191]*") do
    n = n + 1
    if n == maxChars - 2 then cut = start end
  end
  if n <= maxChars then return text, false end
  return text:sub(1, cut - 1) .. ELLIPSIS, true
end

--- Hover text for a chart element: the FULL (untruncated) label plus the value it encodes, so a
--- tooltip always states the number as well as the name. Label-only when the element has no value.
function lib.tipText(label, value)
  label = label or ""
  if value == nil or value == "" then return label end
  if label == "" then return tostring(value) end
  return label .. ":  " .. tostring(value)
end

--- Shrink a figure's font only when its rendered string would overflow, never under `minSize`.
function lib.fitFontSize(stringWidth, maxWidth, baseSize, minSize)
  if not stringWidth or stringWidth <= 0 or stringWidth <= maxWidth then return baseSize end
  return math.max(minSize, baseSize * maxWidth / stringWidth)
end

--- Reduce one row's per-category magnitudes to at most `maxSegs` stacked segments: the top
--- (maxSegs - 1) by magnitude, the remainder lumped under `lib.OTHER`, then the kept ones in
--- `order`'s order with OTHER last. Non-positive magnitudes drop. Pure.
--- @param mags table  { key -> magnitude }
--- @param order table  the keys' global order; an unlisted key sorts after the listed ones
--- @param maxSegs number|nil  K.MAX_STACK_SEGS when nil
--- @return table, number  { { key, mag }, ... }, and the total
function lib.StackSegments(mags, order, maxSegs)
  maxSegs = maxSegs or K.MAX_STACK_SEGS
  local list, total = {}, 0
  for k, v in pairs(mags) do
    if v and v > 0 then
      list[#list + 1] = { key = k, mag = v }
      total = total + v
    end
  end
  table.sort(list, function(a, b)
    if a.mag ~= b.mag then return a.mag > b.mag end
    return tostring(a.key) < tostring(b.key)
  end)
  local kept, otherMag = {}, 0
  local keep = #list > maxSegs and maxSegs - 1 or #list
  for i, s in ipairs(list) do
    if i <= keep then kept[i] = s else otherMag = otherMag + s.mag end
  end
  local rank = {}
  for i, k in ipairs(order or {}) do rank[k] = i end
  table.sort(kept, function(a, b)
    local ra, rb = rank[a.key] or math.huge, rank[b.key] or math.huge
    if ra ~= rb then return ra < rb end
    return tostring(a.key) < tostring(b.key)
  end)
  if otherMag > 0 then kept[#kept + 1] = { key = lib.OTHER, mag = otherMag } end
  return kept, total
end

--- The scale a range section draws on: the lowest `lo` to the highest `hi` over the rows, so the
--- track is not 0-based. When they meet, the scale opens 5% either side (at least 1). Pure.
--- @return number, number  the scale's two ends (0 and 1 for no rows)
function lib.RangeScale(rows)
  if #rows == 0 then return 0, 1 end
  local lo, hi = math.huge, -math.huge
  for _, row in ipairs(rows) do
    lo, hi = math.min(lo, row.lo), math.max(hi, row.hi)
  end
  if hi > lo then return lo, hi end
  local d = math.max(math.abs(hi) * 0.05, 1)
  return lo - d, hi + d
end

--- A strip's geometry for `n` buckets across `innerW`: the slot (at most K.STRIP_SLOT_MAX, so a few
--- buckets sit side by side) and the column's width in it (at most K.STRIP_BAR_MAX). Pure.
--- @return number, number  slot, barW
function lib.StripSlots(innerW, n)
  local slot = math.min(K.STRIP_SLOT_MAX, innerW / math.max(1, n))
  return slot, math.max(2, math.min(K.STRIP_BAR_MAX, slot - 2))
end

-- The labeled columns as blocks: each runs from its label to the column before the next label.
local function labelBlocks(buckets)
  local blocks, last = {}, nil
  for i, b in ipairs(buckets) do
    if b.label then
      if last then last.size = i - last.i end
      last = { i = i }
      blocks[#blocks + 1] = last
    end
  end
  if last then last.size = #buckets - last.i + 1 end
  return blocks
end

local function clearOf(kept, x)
  for _, k in ipairs(kept) do
    if math.abs(x - k) < K.STRIP_LABEL_PITCH then return false end
  end
  return true
end

--- Which strip labels show, and how far each moves off its column's center. A label shows only
--- K.STRIP_LABEL_PITCH or more from every other one shown, so two never collide; the larger block
--- (the most columns up to the next label) wins, then the earlier one, so a one-run day never takes
--- the label of the many-run day after it. A label is never wider than the pitch, so one within
--- half of it of the content's edge moves in until it fits. Pure.
--- @return table  { [bucket index] = x offset } for the labels shown
function lib.StripLabels(buckets, slot, innerW)
  local half = K.STRIP_LABEL_PITCH / 2
  local blocks = labelBlocks(buckets)
  table.sort(blocks, function(a, b)
    if a.size ~= b.size then return a.size > b.size end
    return a.i < b.i
  end)
  local shown, kept = {}, {}
  for _, blk in ipairs(blocks) do
    local center = (blk.i - 0.5) * slot
    local x = math.max(half, math.min(center, innerW - half))
    if clearOf(kept, x) then
      kept[#kept + 1] = x
      shown[blk.i] = x - center
    end
  end
  return shown
end

-- ── the drawing seams ────────────────────────────────────────────────────────────────────────

local function plainPaint(fs, c) fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
local function plainFill(tex, c, a) tex:SetColorTexture(c[1], c[2], c[3], a or c[4] or 1) end
local function plainText(parent, font, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end
local function plainPanel(parent)
  return CreateFrame("Frame", nil, parent, "BackdropTemplate")
end

local function plainTip(ctx)
  return function(owner, lines, anchor)
    local tip, title, body = GameTooltip, ctx.colors.tipTitle, ctx.colors.tipBody
    if not tip then return end
    tip:SetOwner(owner, anchor)
    tip:SetText(lines[1], title[1], title[2], title[3], 1, true)
    for i = 2, #lines do
      tip:AddLine(tostring(lines[i]), body[1], body[2], body[3], true)
    end
    tip:Show()
  end
end
local function plainHideTip()
  if GameTooltip then GameTooltip:Hide() end
end

-- The owner's facade, or nil: no Skin, or an owner it does not know.
local function skinOf(owner)
  if type(owner) ~= "string" then return nil end
  local Skin = LibStub("LibKa0s-Skin-1.0", true)
  if not Skin or not Skin:IsOwner(owner) then return nil end
  return Skin:For(owner)
end

-- The seams an owner's skin supplies, for the ones the host left out. `face` restores the skin's
-- face to a string a figure's font object just replaced.
local function skinSeams(ctx, S, host)
  ctx.face = not host.text and S.Font or nil
  ctx.text = host.text or function(parent, font, justify)
    local fs = plainText(parent, font, justify)
    S.Font(fs)
    return fs
  end
  ctx.barFill = host.barFill or function(tex, c, a)
    S.BarTexture(tex, c[1], c[2], c[3], a or c[4] or 1)
  end
  ctx.panel = host.panel or function(parent)
    local f = plainPanel(parent)
    S.Panel(f)
    return f
  end
  ctx.paletteOf = ctx.paletteOf or (not ctx.paletteList and function() return S.Token("chart.series") end or nil)
end

local function plainSeams(ctx, host)
  ctx.text = host.text or plainText
  ctx.barFill = host.barFill or host.fill or plainFill
  ctx.panel = host.panel or plainPanel
end

-- Fill ctx.colors in place, the host's over the skin's over the defaults, so a table a caller holds
-- moves with a skin switch.
local function syncColors(ctx)
  local S, out = ctx.skin, ctx.colors
  for name, fallback in pairs(DEFAULT_COLORS) do
    local given = ctx.givenColors[name]
    if type(given) == "function" then given = given() end
    out[name] = given or (S and S.Token(TOKENS[name])) or fallback
  end
end

local function validPalette(p)
  return type(p) == "table" and p[1] ~= nil
end

local function mergedFonts(given)
  local out = {}
  for k, v in pairs(DEFAULT_FONTS) do out[k] = v end
  if type(given) == "table" then
    for k, v in pairs(given) do out[k] = v end
  end
  return out
end

-- ── the context ──────────────────────────────────────────────────────────────────────────────

-- Published for ChartsRender.lua, which adds the factories, the chrome and the renderers.
local Ctx = {}
Ctx.__index = Ctx
lib.__Ctx = Ctx

--- A chart context drawing into `content` through `host` (the header lists its fields). One per
--- content frame, for the session: an owner's context stays subscribed to the owner's looks.
--- @param content table  the frame every section anchors to
--- @param host table|nil  the host config
--- @return table
function lib:New(content, host)
  host = host or {}
  local poolApi = host.pool or LibStub("LibKa0s-Pool-1.0", true)
  if type(poolApi) ~= "table" then
    error("Charts:New: host.pool, or LibKa0s-Pool-1.0, is required", 2)
  end
  local ctx = setmetatable({
    content = content, poolApi = poolApi, pools = {}, poolOrder = {}, chrome = {},
    colors = {}, givenColors = type(host.colors) == "table" and host.colors or {},
    fonts = mergedFonts(host.fonts), skin = skinOf(host.owner), onReskin = host.onReskin,
    paint = host.paint or plainPaint, fill = host.fill or plainFill,
    hideTip = host.hideTip or plainHideTip,
    paletteOf = type(host.palette) == "function" and host.palette or nil,
    paletteList = validPalette(host.palette) and host.palette or nil,
  }, Ctx)
  ctx.tip = host.tip or plainTip(ctx)
  if ctx.skin then
    skinSeams(ctx, ctx.skin, host)
    ctx.skin.OnLooksChanged(function() ctx:Reskin() end)
  else
    plainSeams(ctx, host)
  end
  syncColors(ctx)
  return ctx
end

--- The pool called `name`, made on first ask. ReleaseAll parks every pool made here.
function Ctx:Pool(name)
  local pool = self.pools[name]
  if not pool then
    pool = self.poolApi.New()
    self.pools[name] = pool
    self.poolOrder[#self.poolOrder + 1] = pool
  end
  return pool
end

--- Park every pooled widget (a layout pass starts here).
function Ctx:ReleaseAll()
  for _, pool in ipairs(self.poolOrder) do self.poolApi.ReleaseAll(pool) end
end

local function reskinList(ctx, list)
  if type(list) ~= "table" then return end
  for _, w in ipairs(list) do
    if w._reskin then w._reskin(ctx, w) end
  end
end

--- Repaint what this context painted at build time: the colors, every pooled widget on the active
--- and the free list, and the chrome. Then host.onReskin redraws the rows. A context with an owner
--- runs this on the owner's OnLooksChanged; any other host calls it when its look moves.
function Ctx:Reskin()
  syncColors(self)
  reskinList(self, self.chrome)
  for _, pool in ipairs(self.poolOrder) do
    reskinList(self, pool.active)
    reskinList(self, pool.free)
  end
  if self.onReskin then self.onReskin(self) end
end

function Ctx:acquire(pool, factory, parent)
  return self.poolApi.Acquire(pool, function() return factory(self, parent or self.content) end)
end

--- Show `tip` (a string, or lines: a title, then strings) for `owner`; nothing for an empty one.
function Ctx:showTip(owner, tip, anchor)
  if tip == nil or tip == "" then return end
  if type(tip) ~= "table" then tip = { tostring(tip) } end
  if tip[1] == nil then return end
  self.tip(owner, tip, anchor or "ANCHOR_CURSOR_RIGHT")
end

--- The palette color at 1-based `rank` (cycles). Read at every draw, so a skin switch moves it.
function Ctx:paletteColor(rank)
  local p = self.paletteOf and self.paletteOf() or self.paletteList
  if not validPalette(p) then p = DEFAULT_PALETTE end
  return p[((rank - 1) % #p) + 1]
end

--- { key -> palette color } by position in `orderedKeys`, so a key keeps one color across charts.
function Ctx:paletteMap(orderedKeys)
  local m = {}
  for i, k in ipairs(orderedKeys or {}) do m[k] = self:paletteColor(i) end
  return m
end
