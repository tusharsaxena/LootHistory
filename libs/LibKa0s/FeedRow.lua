-- LibKa0s-Feed-1.0 -- FeedRow.lua, the toast feed's rows.
--
-- Builds a row's regions once, places them (icon side, alignment, heights) and paints them in the
-- style the shell snapshotted over the owner's skin, or the degraded look without one. The shell
-- (Feed.lua) reads it through `lib.__row` at call time:
--
--   Build(container, n)       the n-th row record over a frame parented to the container, in a
--                             level band of its own (ROW_BAND levels, the n-th of ROW_BANDS)
--   Place(R, layout, style)   the regions laid out for the row's spec at the font sizes it is
--                             drawn at (Paint runs first); answers the row's height
--   Paint(R, spec, cfg)       the spec's text and icon drawn, then Restyle
--   Restyle(R, cfg)           the style re-applied (fill, border, fonts, text colors, bar, icon
--                             edge, glow color), after a skin switch or a Refresh too
--   Bar(R, frac)              the countdown bar at `frac` of the row (nil or 0 hides it)
--   Animate(R, pulse, clock)  the merge pulse on the border and the count, and the glow's breath
--   Reset(R)                  a released row's look put back: hidden, alpha 1, no pulse, no glow
--
-- STYLE OVER THE SKIN. The facade is Core's `__SkinFacade(cfg.owner)`, read at CALL time (this file
-- loads before Skin), and every name used on it is one of Skin's trampolines, so a newer Skin minor's
-- code draws. Each part has a `<part>FromSkin` companion that the snapshot defaults to true:
--
--   fill     bgColorFromSkin (the ColorPair composer's name) rules the whole fill: bgType,
--            bgColor, bgColor2 and bgTexture follow it.
--            From skin: S.Shell(row, { noTopBar, noBands, noBorder }), recorded, so a skin switch
--            repaints it (noBorder: the border is the style's own, below). Override: the row's
--            Shell record is replaced with keepEdge (a repaint leaves the host's fill alone) and
--            the row's own fill draws bgType: none, solid (WHITE8X8 tinted), gradient
--            (HORIZONTAL, bgColor to bgColor2) or texture (an LSM background, solid when
--            LibSharedMedia-3.0 or the name is absent)
--   border   style, show, size from S.BarBorder(borderStyle, true, borderSize, borderStyleFromSkin);
--            the color, meaning and class first: borderTint and spec.tint, borderClass, the skin's
--            `bar.border`, else borderColor. A merge pulses its alpha (Animate)
--   fonts    every string through S.HudFont, one font object per look; no string gets a SetFont of
--            its own. The title at fontSize, every other string at fontSize2, each scaled by
--            S.HudFontSize; the drawn sizes are kept on the row for Place
--   text     the spec's own color, then fontClass, then the skin's HudTextColor (the title) or
--            HudLabelColor (the rest), else fontColor
--   bar      the two parts O.BarGroup emits, each on its own: barTextureFromSkin, S.BarTexture,
--            else the LSM statusbar barTexture, flat where none resolves; barColorFromSkin,
--            S.BarFillColor(), else barColor
--   icon     S.IconBorder(holder, { fromSkin, hud }) crops 0.07 and draws the HUD's icon edge; a
--            spec.tint draws its edge in the tint, over the skin's
--   glow     ADD-blend WHITE8X8 strips on a holder at the top of the row's band: spec.highlight when it
--            is a color, else the skin's GlowColor, else `sem.gold`, else glowColor
--
-- THE DEGRADED LOOK. No Core facade, no Skin major or an unregistered owner: the style's stored
-- values are the fallback (skinning-§6), FromSkin companion or not. So the fill is bgType in
-- bgColor (a WHITE8X8 at { 0, 0, 0, 0.7 } by default), the edge borderColor ({ 0.3, 0.3, 0.3, 1 }),
-- the text fontColor (white) and the spec's colors where given, the bar barColor, flat. The fonts
-- are the client's templates, GameFontHighlight for the title and GameFontHighlightSmall for the
-- rest: the font, fontSize, fontSize2, fontFlags and fontShadow overrides need the facade's
-- S.HudFont and do not draw here, and Place measures the templates' own sizes. Every facade call
-- is presence-checked; none raises.
--
-- LEVELS (frame-layering-§3). A row's band is ROW_BAND levels over its base, the container's level
-- plus 1 plus ROW_BAND times its build index (wrapping after ROW_BANDS): the row at +0, the icon
-- holder +1 (the skin's icon edge holder +2, which IconBorder makes one over it), the tint edge and
-- the badge +3, the LSM backdrop edge +4, the glow +5. Set once at build, before any child exists,
-- so overlapping rows (one fading where it stood while the stack slides over it) never interleave.
--
-- Minor 1 (LootHistory#38, task S2 of the Feed build): the rows.

local lib = LibStub and LibStub("LibKa0s-Feed-1.0", true)
if not lib then return end

local ROW_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own, as FeedModel.lua is.
if lib.__rowMinor and lib.__rowMinor >= ROW_MINOR and lib.__rowShellMinor == lib.MINOR then return end
lib.__rowMinor, lib.__rowShellMinor = ROW_MINOR, lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.FeedRow = ROW_MINOR

local sin, pi, max, min, floor = math.sin, math.pi, math.max, math.min, math.floor
local HUGE = math.huge

local WHITE8 = "Interface\\Buttons\\WHITE8X8"
local ICON_CROP = 0.07
local BAR_HEIGHT = 2
local GLOW_SIZE = 2
local TITLE_GAP, COUNT_GAP = 3, 4
local FONT_TITLE, FONT_SMALL = "GameFontHighlight", "GameFontHighlightSmall"
local DEGRADED_EDGE = { 0.3, 0.3, 0.3, 1 }
local ROW_BAND, ROW_BANDS = 6, 20   -- levels per row, and bands before they wrap (2 * SHOWN_MAX)

-- The Shell opts, shared by every row (Shell records the table and never writes it).
local SHELL_SKIN = { noTopBar = true, noBands = true, noBorder = true }
local SHELL_KEEP = { keepEdge = true, noTopBar = true, noBands = true }

local Row = {}

-- == readers ==================================================================================

local function finite(v) return type(v) == "number" and v == v and v ~= HUGE and v ~= -HUGE end

local function resolve(major) return LibStub and LibStub(major, true) end

--- The owner's skin facade, or nil (no Core facade, no Skin major, an unregistered owner).
local function facade(cfg)
  local core = resolve("LibKa0s-Core-1.0")
  local fn = core and core.__SkinFacade
  if type(fn) ~= "function" then return nil end
  local ok, S = pcall(fn, cfg and cfg.owner)
  if ok and type(S) == "table" then return S end
  return nil
end

--- r, g, b, a of a color table (array or r/g/b/a keys), or nil.
local function rgba(c)
  if type(c) ~= "table" then return nil end
  local r, g, b, a = c[1], c[2], c[3], c[4]
  if r == nil then r, g, b, a = c.r, c.g, c.b, c.a end
  if not (finite(r) and finite(g) and finite(b)) then return nil end
  return r, g, b, finite(a) and a or 1
end

--- A facade getter's r, g, b, a, or nil.
local function fromFacade(S, name)
  local fn = S and S[name]
  if type(fn) ~= "function" then return nil end
  local ok, r, g, b, a = pcall(fn)
  if not (ok and finite(r) and finite(g) and finite(b)) then return nil end
  return r, g, b, finite(a) and a or 1
end

local function tokenColor(S, name)
  local fn = S and S.Token
  if type(fn) ~= "function" then return nil end
  local ok, c = pcall(fn, name)
  if ok then return rgba(c) end
  return nil
end

local function classColor()
  local core = resolve("LibKa0s-Core-1.0")
  if not (core and type(core.ClassColor) == "function") then return nil end
  local r, g, b = core.ClassColor("player")
  if finite(r) and finite(g) and finite(b) then return r, g, b, 1 end
  return nil
end

--- A LibSharedMedia-3.0 path for `kind` and `key`, or nil.
local function media(kind, key)
  local LSM = resolve("LibSharedMedia-3.0")
  if not (LSM and type(LSM.Fetch) == "function" and type(key) == "string" and key ~= "") then return nil end
  local ok, path = pcall(LSM.Fetch, LSM, kind, key, true)
  if ok and type(path) == "string" and path ~= "" then return path end
  return nil
end

--- R[field], a color object made once per row and refreshed in place, so a gradient paint
--- allocates nothing after the first.
local function colorOn(R, field, c)
  local o = R[field]
  if not o then
    if type(CreateColor) == "function" then o = CreateColor(c[1], c[2], c[3], c[4]) else o = {} end
    R[field] = o
  end
  if type(o.SetRGBA) == "function" then
    o:SetRGBA(c[1], c[2], c[3], c[4])
  else
    o.r, o.g, o.b, o.a = c[1], c[2], c[3], c[4]
  end
  return o
end

local function filled(s) return type(s) == "string" and s ~= "" end

local EMPTY = {}

--- Secondary line `i` of `spec`, or an empty table: a host that swapped `spec.lines` for a table of
--- its own draws what it holds and never raises here.
local function partOf(spec, i)
  local lines = spec.lines
  local part = type(lines) == "table" and lines[i]
  if type(part) == "table" then return part end
  return EMPTY
end

-- == build ====================================================================================

local function level(f)
  local lv = type(f.GetFrameLevel) == "function" and f:GetFrameLevel()
  return type(lv) == "number" and lv or 0
end

--- Four edge textures on `owner`, in `layer`: top, bottom, left, right.
local function edges(owner, layer)
  local t = {}
  for i = 1, 4 do t[i] = owner:CreateTexture(nil, layer) end
  return t
end

--- The four edges hung on `frame`'s sides, `size` px thick.
local function hangEdges(list, frame, size)
  local top, bottom, left, right = list[1], list[2], list[3], list[4]
  top:ClearAllPoints(); top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0); top:SetHeight(size)
  bottom:ClearAllPoints(); bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); bottom:SetHeight(size)
  left:ClearAllPoints(); left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); left:SetWidth(size)
  right:ClearAllPoints(); right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); right:SetWidth(size)
end

local function colorEdges(list, r, g, b, a)
  for i = 1, 4 do
    local t = list[i]
    if r then
      t:SetColorTexture(r, g, b, a)
      t:Show()
    else
      t:Hide()
    end
  end
end

local function alphaEdges(list, a)
  for i = 1, 4 do list[i]:SetAlpha(a) end
end

local function text(owner)
  local fs = owner:CreateFontString(nil, "OVERLAY")
  fs:SetWordWrap(false)
  return fs
end

local function buildIcon(R, f)
  local holder = CreateFrame("Frame", nil, f)
  holder:SetFrameLevel(level(f) + 1)
  R.iconHolder = holder
  R.icon = holder:CreateTexture(nil, "ARTWORK")
  R.icon:SetAllPoints(holder)
  R.iconOpts = { fromSkin = true, hud = true, icon = R.icon }
  -- The tint's own edge and the badge, two levels over the holder: the skin's icon edge hangs on
  -- a holder of its own one level over it.
  local over = CreateFrame("Frame", nil, holder)
  over:SetAllPoints(holder)
  over:SetFrameLevel(level(f) + 3)
  R.iconOver = over
  R.iconTint = edges(over, "OVERLAY")
  hangEdges(R.iconTint, over, 1)
  R.badge = text(over)
  R.badge:SetPoint("TOPLEFT", holder, "TOPLEFT", 1, -1)
end

local function buildGlow(R, f)
  local g = CreateFrame("Frame", nil, f)
  g:SetAllPoints(f)
  g:SetFrameLevel(level(f) + 5)
  R.glowHolder = g
  R.glow = edges(g, "OVERLAY")
  for i = 1, 4 do
    R.glow[i]:SetTexture(WHITE8)
    R.glow[i]:SetBlendMode("ADD")
  end
  hangEdges(R.glow, g, GLOW_SIZE)
  g:Hide()
end

--- The `n`-th row record of a feed over a frame parented to `container`, in its own band over it
--- (LEVELS in the header). Every region is made here, once; a pooled row is repainted, never
--- rebuilt, and keeps its band.
function Row.Build(container, n)
  local f = CreateFrame("Frame", nil, container)
  local band = ((tonumber(n) or 1) - 1) % ROW_BANDS
  f:SetFrameLevel(level(container) + 1 + ROW_BAND * band)
  f:Hide()
  local R = { frame = f, spec = { lines = { {}, {}, {} } } }
  R.specLines = R.spec.lines   -- the three sub-tables the shell hands back after every wipe
  R.bg = f:CreateTexture(nil, "BACKGROUND", nil, -6)
  R.bg:SetAllPoints(f)
  R.edges = edges(f, "BORDER")
  R.edgeSize = 1
  hangEdges(R.edges, f, 1)
  buildIcon(R, f)
  R.prefix, R.title, R.count = text(f), text(f), text(f)
  R.lines = {}
  for i = 1, 3 do R.lines[i] = { left = text(f), right = text(f) } end
  R.sub = text(f)
  R.bar = f:CreateTexture(nil, "ARTWORK")
  R.bar:SetHeight(BAR_HEIGHT)
  R.bar:Hide()
  buildGlow(R, f)
  return R
end

-- == place ====================================================================================

local function at(fs, point, rel, relPoint, x, y)
  fs:ClearAllPoints()
  fs:SetPoint(point, rel, relPoint, x, y)
end

--- The title line under right alignment: the count at the right text edge, the title and the
--- prefix leftward of it.
local function placeTitleRight(R, f, r, y, hasCount)
  if hasCount then
    at(R.count, "TOPRIGHT", f, "TOPRIGHT", -r, y)
    at(R.title, "TOPRIGHT", R.count, "TOPLEFT", -COUNT_GAP, 0)
  else
    at(R.title, "TOPRIGHT", f, "TOPRIGHT", -r, y)
  end
  at(R.prefix, "TOPRIGHT", R.title, "TOPLEFT", -TITLE_GAP, 0)
end

--- The title line under left alignment: the prefix at the left text edge, the title and the count
--- rightward of it.
local function placeTitleLeft(R, f, l, y, hasPrefix)
  if hasPrefix then
    at(R.prefix, "TOPLEFT", f, "TOPLEFT", l, y)
    at(R.title, "TOPLEFT", R.prefix, "TOPRIGHT", TITLE_GAP, 0)
  else
    at(R.title, "TOPLEFT", f, "TOPLEFT", l, y)
  end
  at(R.count, "TOPLEFT", R.title, "TOPRIGHT", COUNT_GAP, 0)
end

local function placeTitle(R, f, l, r, y, right)
  local spec = R.spec
  local hasPrefix, hasCount = filled(spec.prefix), filled(spec.count)
  if right then placeTitleRight(R, f, r, y, hasCount) else placeTitleLeft(R, f, l, y, hasPrefix) end
  R.title:SetJustifyH(right and "RIGHT" or "LEFT")
  R.prefix:SetShown(hasPrefix)
  R.count:SetShown(hasCount)
end

--- One secondary line at `y`: its left part from the left text edge and its right part from the
--- right one, swapped under right alignment. Answers whether it is filled.
local function placeLine(line, part, f, l, r, y, right)
  local has = filled(part.left) or filled(part.right)
  line.left:SetShown(has)
  line.right:SetShown(has)
  if not has then return false end
  local nearL, nearR = line.left, line.right
  if right then nearL, nearR = line.right, line.left end
  at(nearL, "TOPLEFT", f, "TOPLEFT", l, y)
  nearL:SetJustifyH("LEFT")
  at(nearR, "TOPRIGHT", f, "TOPRIGHT", -r, y)
  nearR:SetJustifyH("RIGHT")
  return true
end

--- The icon on its side, centered on the row's height. Answers the width it takes from the text.
local function placeIcon(R, f, L)
  local has = R.spec.icon ~= nil
  R.iconHolder:SetShown(has)
  if not has then return 0 end
  local side = L.iconSide == "right" and "RIGHT" or "LEFT"
  R.iconHolder:SetSize(L.iconSize, L.iconSize)
  R.iconHolder:ClearAllPoints()
  R.iconHolder:SetPoint(side, f, side, side == "LEFT" and L.padding or -L.padding, 0)
  return L.iconSize + L.padding
end

local function placeSub(R, f, l, r, y, right)
  local has = filled(R.spec.sub)
  R.sub:SetShown(has)
  if not has then return end
  local point = right and "TOPRIGHT" or "TOPLEFT"
  at(R.sub, point, f, point, right and -r or l, y)
  R.sub:SetJustifyH(right and "RIGHT" or "LEFT")
end

--- The regions laid out for R.spec: the icon on its side, the title line and each filled secondary
--- line under it, the bar along the foot. Sizes the row to `layout.width` and its height, which it
--- answers. The height and the line steps count the sizes the strings are DRAWN at, which the last
--- paint kept on the row; `st` (the style snapshot) answers for a row not painted yet.
function Row.Place(R, L, st)
  local model = lib.__model
  local spec, f = R.spec, R.frame
  local titleSize = R.titleSize or (st and st.fontSize) or model.FONT_SIZE
  local lineSize = R.lineSize or (st and st.fontSize2) or model.FONT_SIZE2
  local h = model.RowHeight(spec, L, titleSize, lineSize)
  f:SetSize(L.width, h)
  local iconW = placeIcon(R, f, L)
  local onRight = L.iconSide == "right"
  local l = L.padding + (onRight and 0 or iconW)
  local r = L.padding + (onRight and iconW or 0)
  local right = L.align == "right"
  local y = -L.padding
  placeTitle(R, f, l, r, y, right)
  y = y - (titleSize + 2)
  for i = 1, 3 do
    if placeLine(R.lines[i], partOf(spec, i), f, l, r, y, right) then y = y - (lineSize + 2) end
  end
  placeSub(R, f, l, r, y, right)
  at(R.bar, "BOTTOMLEFT", f, "BOTTOMLEFT", R.edgeSize, R.edgeSize)
  R.width = L.width
  return h
end

-- == paint: the fill and the border =========================================================

--- The skin's own window fill under a row whose fill is now the host's: Shell keeps its regions
--- across a keepEdge call, so the fill it drew is hidden here, through Skin's public `painted`
--- record (Core's ApplySkin hand-off reads it the same way).
local function hideSkinFill(f)
  local Skin = resolve("LibKa0s-Skin-1.0")
  local rec = Skin and type(Skin.painted) == "table" and Skin.painted[f]
  local fill = type(rec) == "table" and type(rec.regions) == "table" and rec.regions.fill
  if type(fill) == "table" and type(fill.Hide) == "function" then fill:Hide() end
end

local BG = {}

function BG.none(R) R.bg:Hide() end

function BG.solid(R, c)
  R.bg:SetColorTexture(c[1], c[2], c[3], c[4])
  R.bg:Show()
end

function BG.gradient(R, c, c2)
  R.bg:SetColorTexture(1, 1, 1, 1)
  R.bg:SetGradient("HORIZONTAL", colorOn(R, "gc1", c), colorOn(R, "gc2", c2))
  R.bg:Show()
end

function BG.texture(R, c, _, name)
  local path = media("background", name)
  if not path then return BG.solid(R, c) end
  R.bg:SetTexture(path)
  R.bg:SetVertexColor(c[1], c[2], c[3], c[4])
  R.bg:Show()
end

local function paintFill(R, S, st)
  local f = R.frame
  local shell = S and S.Shell
  if type(shell) ~= "function" then shell = nil end
  if shell and st.bgColorFromSkin then
    shell(f, SHELL_SKIN)
    return R.bg:Hide()
  end
  if shell then
    shell(f, SHELL_KEEP)
    hideSkinFill(f)
  end
  local draw = BG[st.bgType] or BG.solid
  draw(R, st.bgColor, st.bgColor2, st.bgTexture)
end

local function borderColor(R, S, st)
  if st.borderTint and rgba(R.spec.tint) then return rgba(R.spec.tint) end
  if st.borderClass then
    local r, g, b, a = classColor()
    if r then return r, g, b, a end
  end
  if S and st.borderColorFromSkin then
    local r, g, b, a = tokenColor(S, "bar.border")
    if r then return r, g, b, a end
  end
  local c = st.borderColor
  return c[1], c[2], c[3], c[4]
end

--- style, show, size the border draws: the skin's S.BarBorder over the style's three.
local function borderOf(S, st)
  local style, show, size = st.borderStyle or "Solid", true, st.borderSize
  local fn = S and S.BarBorder
  if type(fn) == "function" then
    local ok, a, b, c = pcall(fn, st.borderStyle, true, st.borderSize, st.borderStyleFromSkin)
    if ok and a ~= nil then style, show, size = a, b, tonumber(c) or size end
  end
  if style == "None" or not finite(size) or size <= 0 then show = false end
  return style, show, size
end

--- An LSM border style on a backdrop child of the row, made on first use; hidden for none.
local function paintBackdropEdge(R, path, size, r, g, b, a)
  local e = R.edgeFrame
  if not (path or e) then return end
  if not e then
    e = CreateFrame("Frame", nil, R.frame, "BackdropTemplate")
    e:SetAllPoints(R.frame)
    e:SetFrameLevel(level(R.frame) + 4)
    R.edgeFrame = e
    R.backdrop = {}
  end
  e:SetShown(path ~= nil)
  if path and type(e.SetBackdrop) == "function" then
    if R.backdrop.edgeFile ~= path or R.backdrop.edgeSize ~= size then   -- one table, set on change
      R.backdrop.edgeFile, R.backdrop.edgeSize = path, size
      e:SetBackdrop(R.backdrop)
    end
    e:SetBackdropBorderColor(r, g, b, a)
  end
end

local function paintBorder(R, S, st)
  local style, show, size = borderOf(S, st)
  local r, g, b, a = borderColor(R, S, st)
  local path = show and style ~= "Solid" and media("border", style) or nil
  if show and not path then
    if R.edgeSize ~= size then
      hangEdges(R.edges, R.frame, size)
      R.edgeSize = size
    end
    colorEdges(R.edges, r, g, b, a)
  else
    colorEdges(R.edges, nil)
  end
  paintBackdropEdge(R, path, size, r, g, b, a)
end

-- == paint: fonts and text colors ===========================================================

local FONT_OPTS = {}   -- one scratch table: S.HudFont reads it and keeps nothing

--- The face the style names, as a path: S.Resolve's answer, through LibSharedMedia-3.0 when it is
--- a media key. nil lets S.HudFont take the skin's own face.
local function faceOf(S, st)
  if type(S.Resolve) ~= "function" then return nil end
  local ok, v = pcall(S.Resolve, "hud.font", st.font, st.fontFromSkin)
  if not (ok and filled(v)) then return nil end
  if v:find("[\\/]") then return v end
  return media("font", v)
end

local function hudFont(S, fs, face, size, st)
  FONT_OPTS.face = face
  FONT_OPTS.size = size
  FONT_OPTS.flags = type(S.FontFlags) == "function" and S.FontFlags(st.fontFlags) or st.fontFlags
  FONT_OPTS.shadow = st.fontShadow
  FONT_OPTS.shadowFromSkin = st.fontShadowFromSkin
  S.HudFont(fs, FONT_OPTS)
end

--- `fn(fs, ...)` for every string of the row but the title.
local function eachSmall(R, fn, ...)
  fn(R.prefix, ...); fn(R.count, ...); fn(R.sub, ...); fn(R.badge, ...)
  for i = 1, 3 do fn(R.lines[i].left, ...); fn(R.lines[i].right, ...) end
end

local function setObject(fs, name) fs:SetFontObject(name) end
local function fontOn(fs, S, face, size, st) hudFont(S, fs, face, size, st) end

--- The size the client font object named `name` draws at, else `fallback`.
local function objectSize(name, fallback)
  local o = _G[name]
  local fn = type(o) == "table" and o.GetFont
  if type(fn) ~= "function" then return fallback end
  local ok, _, size = pcall(fn, o)
  if ok and finite(size) and size > 0 then return size end
  return fallback
end

--- Every string's font, and the two sizes they draw at kept on the row for Place.
local function paintFonts(R, S, st)
  if not (S and type(S.HudFont) == "function") then
    setObject(R.title, FONT_TITLE)
    eachSmall(R, setObject, FONT_SMALL)
    local model = lib.__model
    R.titleSize = objectSize(FONT_TITLE, model.FONT_SIZE)
    R.lineSize = objectSize(FONT_SMALL, model.FONT_SIZE2)
    return
  end
  local face = faceOf(S, st)
  local sizeFn = S.HudFontSize
  local big, small = st.fontSize, st.fontSize2
  if type(sizeFn) == "function" then
    big, small = sizeFn(big, st.fontSizeFromSkin), sizeFn(small, st.fontSizeFromSkin)
  end
  hudFont(S, R.title, face, big, st)
  eachSmall(R, fontOn, S, face, small, st)
  R.titleSize = finite(big) and big or st.fontSize
  R.lineSize = finite(small) and small or st.fontSize2
end

--- The text color a string without its own draws in: the class's, the skin's, else the style's.
local function baseColor(S, st, title)
  if st.fontClass then
    local r, g, b, a = classColor()
    if r then return r, g, b, a end
  end
  if S and st.fontColorFromSkin then
    local r, g, b, a = fromFacade(S, title and "HudTextColor" or "HudLabelColor")
    if r then return r, g, b, a end
  end
  local c = st.fontColor
  return c[1], c[2], c[3], c[4]
end

local function tint(fs, own, br, bg, bb, ba)
  local r, g, b, a = rgba(own)
  if r then return fs:SetTextColor(r, g, b, a) end
  fs:SetTextColor(br, bg, bb, ba)
end

local function paintColors(R, S, st)
  local spec = R.spec
  tint(R.title, spec.titleColor, baseColor(S, st, true))
  local lr, lg, lb, la = baseColor(S, st, false)
  R.labelR, R.labelG, R.labelB, R.labelA = lr, lg, lb, la
  tint(R.prefix, spec.prefixColor, lr, lg, lb, la)
  tint(R.count, spec.countColor, lr, lg, lb, la)
  tint(R.sub, spec.subColor, lr, lg, lb, la)
  tint(R.badge, nil, lr, lg, lb, la)
  for i = 1, 3 do
    local part, line = partOf(spec, i), R.lines[i]
    tint(line.left, part.leftColor, lr, lg, lb, la)
    tint(line.right, part.rightColor, lr, lg, lb, la)
  end
  R.countPulsing = nil
end

-- == paint: bar, icon, glow =================================================================

--- The bar's color: the skin's S.BarFillColor() under barColorFromSkin, else barColor.
local function barColor(S, st)
  if S and st.barColorFromSkin then
    local r, g, b, a = fromFacade(S, "BarFillColor")
    if r then return r, g, b, a end
  end
  local c = st.barColor
  return c[1], c[2], c[3], c[4]
end

--- The texture and the color, each following the skin on its own companion.
local function paintBar(R, S, st)
  local r, g, b, a = barColor(S, st)
  if S and st.barTextureFromSkin and type(S.BarTexture) == "function" then
    return S.BarTexture(R.bar, r, g, b, a)
  end
  local path = media("statusbar", st.barTexture)
  if path then
    R.bar:SetTexture(path)
    return R.bar:SetVertexColor(r, g, b, a)
  end
  R.bar:SetColorTexture(r, g, b, a)
end

local function paintIcon(R, S)
  local spec = R.spec
  if spec.icon ~= nil then R.icon:SetTexture(spec.icon) end
  if S and type(S.IconBorder) == "function" then
    S.IconBorder(R.iconHolder, R.iconOpts)
  else
    R.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
  end
  local r, g, b, a = rgba(spec.tint)
  if not (r or S) then r, g, b, a = unpack(DEGRADED_EDGE) end
  colorEdges(R.iconTint, r, g, b, a)
  R.badge:SetText(filled(spec.badge) and spec.badge or "")
end

local function glowColor(R, S, st)
  local r, g, b, a = rgba(R.spec.highlight)
  if r then return r, g, b, a end
  if S and st.glowColorFromSkin then
    r, g, b, a = fromFacade(S, "GlowColor")
    if r then return r, g, b, a end
    r, g, b, a = tokenColor(S, "sem.gold")
    if r then return r, g, b, a end
  end
  local c = st.glowColor
  return c[1], c[2], c[3], c[4]
end

local function paintGlow(R, S, st)
  local hl = R.spec.highlight
  local on = hl ~= nil and hl ~= false
  local r, g, b, a = glowColor(R, S, st)
  R.glowOn, R.glowR, R.glowG, R.glowB, R.glowA = on, r, g, b, a
  R.glowHolder:SetShown(on)
  if not on then return end
  for i = 1, 4 do R.glow[i]:SetVertexColor(r, g, b, a) end
end

-- == the members ==============================================================================

--- The style re-applied to R as it stands (its spec already drawn): after a paint, a skin switch or
--- a Refresh.
function Row.Restyle(R, cfg)
  local S, st = facade(cfg), cfg.style
  paintFill(R, S, st)
  paintBorder(R, S, st)
  paintFonts(R, S, st)
  paintColors(R, S, st)
  paintBar(R, S, st)
  paintIcon(R, S)
  paintGlow(R, S, st)
  if R.pulsing then
    alphaEdges(R.edges, 1)
    R.pulsing = nil
  end
end

local function setText(fs, s) fs:SetText(filled(s) and s or "") end

--- `spec` (R.spec) drawn: every string's text, then the style over it.
function Row.Paint(R, spec, cfg)
  spec = spec or R.spec
  setText(R.prefix, spec.prefix)
  setText(R.title, spec.title)
  setText(R.count, spec.count)
  setText(R.sub, spec.sub)
  for i = 1, 3 do
    local part, line = partOf(spec, i), R.lines[i]
    setText(line.left, part.left)
    setText(line.right, part.right)
  end
  Row.Restyle(R, cfg)
end

--- The countdown bar at `frac` (0..1) of the row's inner width; nil or 0 hides it. Touches the
--- texture only when the drawn width moves by a pixel.
function Row.Bar(R, frac)
  local w = 0
  if finite(frac) and frac > 0 then
    w = floor(max(0, (R.width or lib.WIDTH) - 2 * R.edgeSize) * min(frac, 1) + 0.5)
  end
  if w == R.barW then return end
  R.barW = w
  if w <= 0 then return R.bar:Hide() end
  R.bar:SetWidth(w)
  R.bar:Show()
end

--- The merge pulse (`pulse` seconds left) on the border's alpha and the count's color, and the
--- glow's breath at clock time `clock`. Per-frame work: alphas and, at a pulse's edges, one color.
function Row.Animate(R, pulse, clock)
  if finite(pulse) and pulse > 0 then
    alphaEdges(R.edges, 0.6 + 0.4 * sin(pulse / lib.PULSE_TIME * pi))
    R.pulsing = true
    if not R.countPulsing and R.spec.countColor == nil and R.glowR then
      R.count:SetTextColor(R.glowR, R.glowG, R.glowB, R.glowA)
      R.countPulsing = true
    end
  elseif R.pulsing then
    R.pulsing = nil
    alphaEdges(R.edges, 1)
    if R.countPulsing and R.labelR then
      R.count:SetTextColor(R.labelR, R.labelG, R.labelB, R.labelA)
    end
    R.countPulsing = nil
  end
  if R.glowOn then R.glowHolder:SetAlpha(0.35 + 0.35 * sin((clock or 0) * 4)) end
end

--- A released row's look put back: hidden, full alpha, no pulse, no glow, no bar.
function Row.Reset(R)
  local f = R.frame
  f:Hide()
  f:SetAlpha(1)
  alphaEdges(R.edges, 1)
  R.pulsing, R.countPulsing, R.glowOn, R.barW = nil, nil, nil, nil
  R.glowHolder:Hide()
  R.bar:Hide()
end

lib.__row = Row
