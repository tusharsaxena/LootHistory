-- LibKa0s-Widgets-1.0 -- Bar: a data bar, a fill and a bonus past it, segments, threshold marks, a
-- spark, a text and an expiry timer, drawn on its owner's skin tokens and pooled (LibKa0s#80).
--
-- ── WHY THIS EXISTS ──────────────────────────────────────────────────────────────────────────
--
-- Ka0s Skill Master built it in `modules/Bar.lua` (`NS.Bar`) because the library had no bar: its
-- skill and stat rows, its detached blocks, its row tooltip, its journal and its broker tooltip all
-- draw through it. It is promoted here with its behavior kept and its host ties cut (Ka0sAddonsCommonTasks
-- docs/2026-11-16-LIBKA0S_ISSUES_75_PLUS, design section 3.8, research note R4 section 3):
--
--   * No profile reads and no class color. The host resolves its own settings into a STYLE table
--     (`W.BarStyle(presetKey, overrides)`) and hands it over; Skill Master's ResolveStyle, Swatch,
--     PlayerColor, WithClass, ShowMarkers and TooltipRowHeight stay in Skill Master.
--   * Colors are TOKEN NAMES or literals. A name (`"bar.fill"`, an owner token such as
--     `"sm.bonusTemp"`) is resolved at paint time against the bar's `owner`, and repainted after
--     each of that owner's skin changes with no host call (the shell's `__onSkin`). A literal
--     `{ r, g, b, a }` is the host's and never moves. A bar with no registered owner paints Ka0s
--     Default's values. No new skin token exists for it: the bonus defaults to `sem.info` (temp) and
--     `sem.good` (permanent), and a host remaps a slot by naming another token (R4 Q10).
--   * `tiers` is `segments` and `{rank}` is `{value}` (with `{rank}` kept as an alias): the
--     profession words are Skill Master's.
--   * The border's edges are one physical pixel per unit of size (the shell's `__pixelLine`), where
--     the host drew them 1 UI unit thick.
--
-- ── ONE CONSUMER, BY THE OWNER'S RULING ──────────────────────────────────────────────────────
--
-- library-stack-§7 bar 1 asks a one-consumer promotion to wait for a second consumer unless the
-- owner rules it a suite-wide component. The owner ruled on 2026-11-16 (that bundle's
-- `inputs/owner-rulings.md`, Q1) to build it now for Skill Master, the one known consumer; the ruling
-- is recorded in docs/api/Widgets and the CHANGELOG. Skill Master adopts it in that run's phase [3].
--
-- ── WHAT IT DELIBERATELY IS NOT ──────────────────────────────────────────────────────────────
--
-- Not a StatusBar: the bonus, the segments and the marks are textures laid by `Layout`, which a
-- StatusBar's one fill cannot carry. Marker LABELS are carried in `bar.geom.markers` and never drawn
-- (R4 Q11): Skill Master's row tooltip draws them as lines of its own. No tick lines: what the issue
-- called tier ticks are the segments.
--
-- A file of the Widgets major, paired on the shell's minor with the same multi-file idiom as
-- WidgetsCopyWindow.lua. Depends on LibStub and the Widgets shell; Skin, Pool and LibSharedMedia are
-- resolved at call time, and each is optional.

local lib = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
if not lib then return end

-- Minor 1 (LK-80 of Ka0sAddonsCommonTasks docs/2026-11-16-LIBKA0S_ISSUES_75_PLUS, LibKa0s#80).
local BAR_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own, as WidgetsCopyWindow.lua is.
if lib.__barMinor and lib.__barMinor >= BAR_MINOR
  and lib.__barShellMinor == lib.MINOR then return end
lib.__barMinor      = BAR_MINOR
lib.__barShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.WidgetsBar = BAR_MINOR

local floor, max, min = math.floor, math.max, math.min
local INSET = 1   -- the fill's inset from the bar's edge, UI units (Skill Master's EDGE)

--- Read-only figures and the presets. PRESETS are Skill Master's four kinds of bar at its default
--- sizes; a host fills its own sizes through `W.BarStyle`'s overrides.
lib.BAR = {
  TIMER_TICK = 0.2,   -- seconds between timer redraws while one runs (the only per-frame work)
  TIMER_W    = 38,    -- the timer's width, drawn inside the bar's far end
  INSET      = INSET,
  TEMPLATE   = "{value} {bonus} / {max}",
  SHADE      = { 1, 0.8, 0.64, 0.5 },
  PRESETS = {
    row     = { height = 14, showText = true,  showMarkers = false },
    compact = { height = 14, showText = true,  showMarkers = false },
    tooltip = { height = 8,  showText = false, showMarkers = true },
    mini    = { height = 10, showText = false, showMarkers = false },
  },
}
local BAR = lib.BAR

-- What every style starts from, before its preset and the host's overrides. Colors are token names.
local DEFAULTS = {
  fill = "bar.fill", bg = "bar.bg", border = "bar.border", marker = "hud.label", spark = false,
  text = "hud.text", timer = "sem.info", bonusTemp = "sem.info", bonusPerm = "sem.good",
  borderShow = false, borderStyle = "Solid", borderSize = 1, borderFromSkin = false,
  alpha = 1, fontSize = 11, textAnchor = "CENTER", reverse = false, segmented = false,
  showTimer = true,
}

-- Ka0s Default's values of DEFAULTS' token names, what an owner-less bar paints. Held to Ka0s
-- Default's table by tests/test_widgets_bar.lua, so a token that moves there moves here.
lib.__barFallback = {
  ["bar.fill"] = { 0.20, 0.55, 0.95, 1 }, ["bar.bg"] = { 0, 0, 0, 0.5 }, ["bar.border"] = { 0, 0, 0, 1 },
  ["hud.label"] = { 1, 0.82, 0, 1 }, ["hud.text"] = { 1, 1, 1, 1 },
  ["sem.info"] = { 0.3, 0.8, 1, 1 }, ["sem.good"] = { 0.35, 0.80, 0.45, 1 },
}

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end

-- ── styles and colors ────────────────────────────────────────────────────────────────────────

--- A style: DEFAULTS, then preset `key`'s fields (`row` for an unknown key), then `overrides`. It
--- carries `key`, so ApplyStyle takes it whole. Colors stay names until the bar paints.
function lib.BarStyle(key, overrides)
  key = BAR.PRESETS[key] and key or "row"
  local s = { key = key }
  for k, v in pairs(DEFAULTS) do s[k] = v end
  for k, v in pairs(BAR.PRESETS[key]) do s[k] = v end
  for k, v in pairs(type(overrides) == "table" and overrides or {}) do s[k] = v end
  return s
end

--- The Skin major while `bar.owner` is a registered skin owner, else nil.
local function skinOf(bar) return lib.__skinOf(bar.owner) end

--- `v` as a color: a table as given, a name through the owner's skin (an owner-less bar, or a name
--- its skin leaves alone, through Ka0s Default: the fallback table for the default names, the Skin
--- major's Ka0s Default for any other), false or nil as none.
local function resolve(bar, v)
  if type(v) == "table" then return v end
  if type(v) ~= "string" then return nil end
  local Skin = skinOf(bar)
  local c = Skin and Skin:Token(bar.owner, v)
  if type(c) == "table" then return c end
  c = lib.__barFallback[v]
  if c then return c end
  -- Any other name an owner-less bar is handed: Ka0s Default's, where the Skin major is loaded.
  local S = LibStub("LibKa0s-Skin-1.0", true)
  local ka0s = S and type(S.ResolveSkin) == "function" and S:ResolveSkin("ka0s")
  c = type(ka0s) == "table" and ka0s[v] or nil
  return type(c) == "table" and c or nil
end
lib.__barResolve = resolve

--- The LibSharedMedia path for `key` of `kind`, or nil.
local function media(kind, key)
  local LSM = LibStub("LibSharedMedia-3.0", true)
  if not (LSM and type(key) == "string" and key ~= "") then return nil end
  local ok, path = pcall(LSM.Fetch, LSM, kind, key, true)
  return ok and path or nil
end

--- The fill texture a style names: an LSM statusbar key, else a path as given, else nil.
local function texturePath(s)
  local t = s.texture
  if type(t) ~= "string" or t == "" then return nil end
  return media("statusbar", t) or ((t:find("[/\\]") and t) or nil)
end

--- `c`'s `i`th shade (BAR.SHADE, its last past the table), the alpha kept.
function lib.BarShade(c, i)
  local k = BAR.SHADE[i] or BAR.SHADE[#BAR.SHADE]
  return { c[1] * k, c[2] * k, c[3] * k, c[4] or 1 }
end

-- ── the geometry, pure ───────────────────────────────────────────────────────────────────────

local function clamp01(x)
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

--- The fill split by cap on a scale to the last cap: one { from, to, tier } per cap the value has
--- entered, as fractions of the scale.
local function capSegments(caps, value, scale)
  local out, from = {}, 0
  for i, cap in ipairs(caps) do
    if value <= from then break end
    out[#out + 1] = { from = from / scale, to = min(value, cap) / scale, tier = i }
    from = cap
  end
  return out
end

local function markerFractions(list, cap)
  local out = {}
  for _, m in ipairs(type(list) == "table" and list or {}) do
    local at = tonumber(m.at)
    if at and at >= 0 and at <= cap then out[#out + 1] = { at = at / cap, label = m.label } end
  end
  return out
end

local function signed(bonus)
  if bonus and bonus > 0 then return "+" .. bonus end
  if bonus and bonus < 0 then return tostring(bonus) end
  return ""
end

--- The bar text from `template` (BAR.TEMPLATE when nil): {value} ({rank} too), {bonus} ("+25", "-3"
--- or nothing), {max}, {pct} (whole percent of the cap) and {left} (points to the cap). A token with
--- nothing to say leaves no double space; an unknown one stays as written.
function lib.BarText(value, bonus, cap, template)
  value, bonus, cap = tonumber(value) or 0, tonumber(bonus) or 0, tonumber(cap) or 0
  local pct = cap > 0 and floor(value / cap * 100 + 0.5) or 0
  local v = tostring(value)
  local subs = { value = v, rank = v, bonus = signed(bonus), max = tostring(cap),
                 pct = tostring(pct), left = tostring(max(cap - value, 0)) }
  local out = tostring(template or BAR.TEMPLATE):gsub("{(%a+)}", subs)
  return (out:gsub("%s%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

--- The geometry of values `v`: the base clamped to [0, 1], the bonus reaching at most the end, the
--- markers up to and including the cap. `segmented` draws a bar carrying `segments` (caps) on a
--- scale to its last cap whatever its max, its fill in `segments`, one per cap entered. The text
--- keeps the full numbers.
function lib.BarCompute(v, template, segmented)
  local cap, value, bonus = tonumber(v.max) or 0, tonumber(v.value) or 0, tonumber(v.bonus) or 0
  local g = { fill = 0, bonus = 0, markers = {} }
  local caps = segmented and type(v.segments) == "table" and #v.segments > 0 and v.segments or nil
  local scale = caps and tonumber(caps[#caps]) or cap
  if scale > 0 then
    g.fill = clamp01(value / scale)
    g.bonus = max(0, clamp01((value + max(bonus, 0)) / scale) - g.fill)
    g.markers = markerFractions(v.markers, scale)
    if caps then g.segments = capSegments(caps, min(value, scale), scale) end
  end
  g.text = v.text or lib.BarText(value, bonus, cap, template)
  return g
end

--- Seconds as m:ss, or h:mm:ss from an hour; never negative.
function lib.BarFormatTimer(seconds)
  local s = max(0, floor((tonumber(seconds) or 0) + 0.5))
  local h, m = floor(s / 3600), floor(s % 3600 / 60)
  if h > 0 then return ("%d:%02d:%02d"):format(h, m, s % 60) end
  return ("%d:%02d"):format(m, s % 60)
end

-- ── painting ─────────────────────────────────────────────────────────────────────────────────

--- A data fill in `c`: the style's texture tinted, else the owner's bar texture (S.BarTexture,
--- recorded, so a skin switch follows), else a flat color.
local function paintFill(bar, tex, c)
  if not c then return end
  local s = bar.style
  local r, g, b, a = rgba(c)
  a = a * (tonumber(s.alpha) or 1)
  local path = texturePath(s)
  local Skin = skinOf(bar)
  if path then
    tex:SetTexture(path)
    tex:SetVertexColor(r, g, b, a)
  elseif Skin then
    Skin:For(bar.owner).BarTexture(tex, r, g, b, a)
  else
    tex:SetColorTexture(r, g, b, a)
  end
end

--- What the border draws, as show, style, size: the style's three, through the owner's S.BarBorder
--- while `borderFromSkin` is on (skinning-§6: a skin that states a real style wins over Show
--- border). None or a size of 0 draws nothing.
local function borderOf(bar)
  local s = bar.style
  local show, style, size = s.borderShow == true, s.borderStyle or "Solid", tonumber(s.borderSize) or 1
  local Skin = skinOf(bar)
  if Skin then
    local st, sh, sz = Skin:For(bar.owner).BarBorder(style, show, size, s.borderFromSkin == true)
    if st ~= nil then style, show, size = st, sh, tonumber(sz) or size end
  end
  if style == "None" or size <= 0 then show = false end
  return show, style, size
end

--- The four edges at `size` physical pixels in `c`, or hidden.
local function paintEdges(bar, c, size)
  for i, t in ipairs(bar.edges) do
    if c then
      lib.__pixelLine(t, bar, i <= 2, size)
      t:SetColorTexture(rgba(c))
      t:Show()
    else
      t:Hide()
    end
  end
end

--- An LSM border style on a backdrop child, made on first use; hidden for none.
local function paintBackdropEdge(bar, path, size, c)
  local f = bar.edgeFrame
  if not (path or f) then return end
  if not f then
    f = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    f:SetAllPoints(bar)
    bar.edgeFrame = f
  end
  f:SetShown(path ~= nil)
  if path and f.SetBackdrop then
    f:SetBackdrop({ edgeFile = path, edgeSize = size })
    if c then f:SetBackdropBorderColor(rgba(c)) end
  end
end

local function paintBorder(bar)
  local show, style, size = borderOf(bar)
  local c = show and resolve(bar, bar.style.border) or nil
  local path = c and style ~= "Solid" and media("border", style) or nil
  paintEdges(bar, (c and not path) and c or nil, size)
  paintBackdropEdge(bar, path, size, c)
end

--- The text at its anchor; the timer inside the bar's far end, or its near end when the text sits
--- right, so the two never share a corner.
local function placeText(bar, anchor)
  bar.text:ClearAllPoints()
  local x = anchor == "LEFT" and 4 or (anchor == "RIGHT" and -4 or 0)
  bar.text:SetPoint(anchor, bar, anchor, x, 0)
  bar.text:SetJustifyH(anchor)
  local side = anchor == "RIGHT" and "LEFT" or "RIGHT"
  bar.timer:ClearAllPoints()
  bar.timer:SetPoint(side, bar, side, side == "LEFT" and 3 or -3, 0)
  bar.timer:SetJustifyH(side)
end

--- The text's face through the owner's HUD font (not recorded, so the repaint calls it again), or a
--- host face where it named one; then both strings' colors.
local function paintText(bar)
  local s, f = bar.style, type(bar.style.font) == "table" and bar.style.font or {}
  local Skin = skinOf(bar)
  if Skin then
    local S = Skin:For(bar.owner)
    S.HudFont(bar.text, { size = S.HudFontSize(s.fontSize or 11, f.fromSkin), face = f.face,
                          flags = S.FontFlags(f.flags or S.FROM_SKIN), shadow = f.shadow,
                          shadowFromSkin = f.shadowFromSkin })
  elseif type(f.face) == "string" and f.face ~= "" then
    bar.text:SetFont(f.face, tonumber(s.fontSize) or 11, f.flags or "")
  end
  local tc, mc = resolve(bar, s.text), resolve(bar, s.timer)
  if tc then bar.text:SetTextColor(rgba(tc)) end
  if mc then bar.timer:SetTextColor(rgba(mc)) end
end

local function textureList(bar, field, n, layer, sublevel)
  local list = bar[field]
  while #list < n do list[#list + 1] = bar:CreateTexture(nil, layer, nil, sublevel) end
  return list
end

-- ── the widget ───────────────────────────────────────────────────────────────────────────────

local Methods = {}
lib.__barMethods = Methods

--- The edge the fill grows from and the sign of an x offset along it: LEFT, +1; RIGHT, -1 while the
--- style fills right to left.
local function origin(bar)
  if bar.style and bar.style.reverse then return "RIGHT", -1 end
  return "LEFT", 1
end

--- The inner width: the frame's, or the last plain one where WoW Forever answers a tooltip-anchored
--- bar's width as a secret number while the caller is tainted (Skill Master, 2026-11-12).
local function innerWidth(bar)
  local w = bar:GetWidth()
  if isSecret(w) or type(w) ~= "number" then
    w = bar.knownWidth or 0
  elseif w > 0 then
    bar.knownWidth = w   -- a frame not laid out yet answers 0: never the width to fall back to
  end
  return w - 2 * INSET
end

local function span(bar, tex, x, w)
  local side = origin(bar)
  tex:ClearAllPoints()
  tex:SetPoint("TOP" .. side, bar, "TOP" .. side, x, -INSET)
  tex:SetPoint("BOTTOM" .. side, bar, "BOTTOM" .. side, x, INSET)
  tex:SetWidth(max(w, 0.01))
end

--- Place the fill (or its segments), the bonus, the spark and the marks from `geom` on the current
--- width, from the style's edge. Anchors and widths only.
function Methods:Layout()
  local g, w = self.geom, innerWidth(self)
  local side, sgn = origin(self)
  local fillW, bonusW = max(0, w * g.fill), max(0, w * g.bonus)
  span(self, self.fill, sgn * INSET, fillW)
  self.fill:SetShown(fillW >= 0.5 and not g.segments)
  self:LayoutSegments(g.segments, w)
  local x = sgn * (INSET + fillW)
  span(self, self.bonus, x, bonusW)
  self.bonus:SetShown(bonusW >= 0.5)
  self.spark:ClearAllPoints()
  self.spark:SetPoint("TOP", self, "TOP" .. side, x, 0)
  self.spark:SetPoint("BOTTOM", self, "BOTTOM" .. side, x, 0)
  self.spark:SetShown(self.style.spark and fillW >= 1 and g.fill < 1 or false)
  self:LayoutMarks(g.markers, w)
end

--- The segments, each from its cap's start to where the value stops in it; none unsegmented.
function Methods:LayoutSegments(segs, w)
  local sgn = select(2, origin(self))
  for i, t in ipairs(self.segmentTextures) do
    local seg = segs and segs[i]
    local sw = seg and w * (seg.to - seg.from) or 0
    if seg and sw >= 0.5 then span(self, t, sgn * (INSET + w * seg.from), sw) end
    t:SetShown(seg ~= nil and sw >= 0.5)
  end
end

function Methods:LayoutMarks(marks, w)
  local side, sgn = origin(self)
  for i, t in ipairs(self.markerTextures) do
    local m = marks[i]
    if m then
      local x = sgn * (INSET + min(w * m.at, max(w - 1, 0)))
      t:ClearAllPoints()
      t:SetPoint("TOP" .. side, self, "TOP" .. side, x, 0)
      t:SetPoint("BOTTOM" .. side, self, "BOTTOM" .. side, x, 0)
    end
    t:SetShown(m ~= nil)
  end
end

--- The segments take the fill's place and layer, each its cap's shade of the fill color; the
--- marks are 2 px lines in the marker color (none while the style hides them).
function Methods:PaintMarks()
  local g, s = self.geom, self.style
  local segs = textureList(self, "segmentTextures", g.segments and #g.segments or 0, "ARTWORK", 1)
  local base = resolve(self, (self.values and self.values.color) or s.fill)
  for i, t in ipairs(segs) do
    local seg = g.segments and g.segments[i]
    if seg and base then paintFill(self, t, lib.BarShade(base, seg.tier)) end
  end
  if s.showMarkers == false then for i = #g.markers, 1, -1 do g.markers[i] = nil end end
  local marks = textureList(self, "markerTextures", #g.markers, "OVERLAY")
  local mc = resolve(self, s.marker)
  for i, t in ipairs(marks) do
    if g.markers[i] and mc then t:SetColorTexture(rgba(mc)) end
    t:SetWidth(2)
  end
end

--- Set the numbers: `{ value, max, bonus, bonusKind = "temp" | "perm", segments = { caps }, markers =
--- { { at, label } }, text, color }`. Recomputes the geometry, repaints what changed, lays it out.
function Methods:SetValues(v)
  v = type(v) == "table" and v or {}
  self.values = v
  local s = self.style
  self.geom = lib.BarCompute(v, s.template, s.segmented)
  local fillColor = resolve(self, v.color or s.fill)
  if fillColor ~= self.fillColor then
    self.fillColor = fillColor
    paintFill(self, self.fill, fillColor)
  end
  local bonusColor = resolve(self, v.bonusKind == "temp" and s.bonusTemp or s.bonusPerm)
  if bonusColor ~= self.bonusColor then
    self.bonusColor = bonusColor
    paintFill(self, self.bonus, bonusColor)
  end
  self.text:SetText(self.geom.text)
  self.text:SetShown(s.showText ~= false)
  self:PaintMarks()
  self:Layout()
end

local function timerTick(self, elapsed)
  self.__acc = (self.__acc or 0) + (elapsed or 0)
  if self.__acc < BAR.TIMER_TICK then return end
  self.__acc = 0
  self:RedrawTimer()
end

function Methods:RedrawTimer()
  local left = self.expires and self.expires - GetTime()
  if not left or left <= 0 then
    self:SetTimer(nil)
    return
  end
  self.timer:SetText(lib.BarFormatTimer(left))
end

--- Show the time left until `expires` (a GetTime() second), or clear it with nil. The OnUpdate runs
--- only while a timer does, and is disarmed when it is cleared or runs out.
function Methods:SetTimer(expires)
  self.expires = tonumber(expires)
  if self.style and self.style.showTimer == false then self.expires = nil end
  if not self.expires or self.expires <= GetTime() then
    self.expires = nil
    self.timer:SetText("")
    self.timer:Hide()
    self:SetScript("OnUpdate", nil)
    return
  end
  self.timer:Show()
  self.__acc = 0
  self:RedrawTimer()
  self:SetScript("OnUpdate", timerTick)
end

--- Apply a style. A full one (it carries `key`, as W.BarStyle's does) REPLACES the current one: its
--- absent fields mean "none", and a merge would keep the last style's border or texture. A partial
--- table merges over the current style.
function Methods:ApplyStyle(style)
  local s = {}
  if not (type(style) == "table" and style.key) then
    for k, v in pairs(self.style or {}) do s[k] = v end
  end
  for k, v in pairs(type(style) == "table" and style or {}) do s[k] = v end
  self.style = s
  self:Repaint()
end

--- Paint the current style again: what a skin switch of the owner runs.
function Methods:Repaint()
  local s = self.style
  self:SetHeight(tonumber(s.height) or 14)
  local bg = resolve(self, s.bg)
  if bg then self.bg:SetColorTexture(rgba(bg)) end
  paintBorder(self)
  local spark = resolve(self, s.spark == true and "hud.text" or s.spark)
  if spark then self.spark:SetColorTexture(rgba(spark)) end
  placeText(self, s.textAnchor or "CENTER")
  paintText(self)
  self.fillColor, self.bonusColor = nil, nil
  if self.values then self:SetValues(self.values) end
end

--- The release hook: the timer off and the points cleared.
function Methods:Park()
  self:SetTimer(nil)
  self:ClearAllPoints()
end

local function buildRegions(bar)
  bar.bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetAllPoints(bar)
  bar.fill = bar:CreateTexture(nil, "ARTWORK", nil, 1)   -- anchored by Layout, from the style's edge
  bar.bonus = bar:CreateTexture(nil, "ARTWORK", nil, 2)
  bar.spark = bar:CreateTexture(nil, "OVERLAY")
  bar.spark:SetWidth(1)
  bar.edges = {}
  for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local t = bar:CreateTexture(nil, "OVERLAY")
    local a, b = side .. "LEFT", side .. "RIGHT"
    if i > 2 then a, b = "TOP" .. side, "BOTTOM" .. side end
    t:SetPoint(a, bar, a, 0, 0)
    t:SetPoint(b, bar, b, 0, 0)
    t:Hide()
    bar.edges[i] = t
  end
  bar.segmentTextures, bar.markerTextures = {}, {}
  bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.text:SetWordWrap(false)
  bar.timer = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.timer:SetWidth(BAR.TIMER_W - 4)
  bar.timer:Hide()
end

--- The owner's repaint: record the bar on the shell's per-owner list once per owner it is drawn for.
local function watchOwner(bar)
  local Skin = skinOf(bar)
  if not Skin or bar.__watched == bar.owner then return end
  bar.__watched = bar.owner
  lib.__onSkin(Skin, bar.owner, bar, function(target) target:Repaint() end)
end

local function styleFrom(opts)
  if type(opts.style) == "table" then return opts.style end
  return lib.BarStyle(opts.preset)
end

--- One bar on `parent`. `opts`: `owner` (the skin owner, an addon folder name), `style` (a
--- W.BarStyle table) or `preset` (a preset key, default `row`).
function lib.Bar(parent, opts)
  if type(parent) ~= "table" then error("LibKa0s-Widgets-1.0: Bar(parent, opts): parent is not a frame", 2) end
  opts = type(opts) == "table" and opts or {}
  local bar = CreateFrame("Frame", nil, parent)
  for k, fn in pairs(Methods) do bar[k] = fn end
  bar.owner = type(opts.owner) == "string" and opts.owner ~= "" and opts.owner or nil
  buildRegions(bar)
  bar.geom = lib.BarCompute({ value = 0, max = 0 })
  bar:ApplyStyle(styleFrom(opts))
  watchOwner(bar)
  bar:SetScript("OnSizeChanged", function(self) self:Layout() end)
  return bar
end

-- ── the pool (LibKa0s-Pool-1.0 at call time; its ordered contract inline without it) ─────────

local function poolMajor() return LibStub("LibKa0s-Pool-1.0", true) end

--- A bar from `pool` (a Pool.New() table), on `parent`, in `opts`' style and owner (a skin or a
--- setting change reaches every bar on the next render). Position n gets its bar back after a
--- ReleaseBars.
function lib.AcquireBar(pool, parent, opts)
  opts = type(opts) == "table" and opts or {}
  pool.free, pool.active = pool.free or {}, pool.active or {}
  local function make() return lib.Bar(parent, opts) end
  local Pool = poolMajor()
  local bar = Pool and Pool.Acquire(pool, make) or nil
  if not Pool then
    bar = table.remove(pool.free) or make()
    pool.active[#pool.active + 1] = bar
  end
  bar:SetParent(parent)
  if opts.owner ~= nil then bar.owner = opts.owner end
  bar:ApplyStyle(styleFrom(opts))
  watchOwner(bar)
  bar:Show()
  return bar
end

local function park(bar) bar:Park() end

--- Park, hide and free every active bar of `pool`, last first, as LibKa0s-Pool-1.0's ReleaseAll.
function lib.ReleaseBars(pool)
  local Pool = poolMajor()
  if Pool then return Pool.ReleaseAll(pool, park) end
  local active = pool.active or {}
  for i = #active, 1, -1 do
    local o = active[i]
    park(o)
    o:Hide()
    pool.free[#pool.free + 1] = o
    active[i] = nil
  end
end
