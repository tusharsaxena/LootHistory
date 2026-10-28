-- LibKa0s-Skin-1.0 — the Ka0s paint primitives, part two: the window family's Ka0s extras
-- (TitleBar, Divider, Footer, Card, Strip, Cover, Tooltip, MenuFrame), the text and font
-- primitives (Text, Font, White), the bar texture (BarTexture) and the getters (GetAccentColor,
-- GetPanelColor, GetFont, GlowColor, ChartStyle, BarStyle).
--
-- A file of its own so no primitive file reaches layout-§1's 1000-line band: it is part of the same
-- major, paired on the shell's minor (`__extrasMinor` / `__extrasShellMinor`), and it paints with
-- SkinPaint.lua's helpers (`lib.__P`), so it attaches only when that file attached to the same
-- shell. The technique, the holder rule and the Ka0s Default rule are SkinPaint.lua's header.
--
-- Every extra's edges and lines go on the holder over the target, its fills and washes are regions
-- of the target under everything it draws (P.SUB, P.subTex), and a frame that wears a backdrop
-- takes its fill in that backdrop.
-- No primitive here draws a LibKa0s-Media icon.

local lib = LibStub and LibStub("LibKa0s-Skin-1.0", true)
if not lib then return end   -- the shell refused (no Core, or below its floor): nothing to attach to
if lib.__paintShellMinor ~= lib.MINOR or not lib.__P then return end   -- no helpers from this copy

-- Minor 2 (the owner's notes, round 2): Footer, Card and Cover give the strings they color the
-- skin's face through P.label, so no labeled string keeps the client's font and its shadow.
-- Minor 3: a wash is a region of its frame at the bottom of BACKGROUND (SkinPaint minor 7's P.SUB),
-- not of the fill holder, which could tie the frame's parent for frame level.
-- Minor 4: BarTexture, the owner's bar texture (`bar.texture`, its texture override when it sets
-- one, Skin minor 6) on a Texture or a StatusBar, tinted and recorded (LibKa0s#63). A repaint and a
-- nil color keep the bar's live color (a host's own recolor included), never a first-paint snapshot.
local EXTRAS_MINOR = 4
if lib.__extrasMinor and lib.__extrasMinor >= EXTRAS_MINOR
  and lib.__extrasShellMinor == lib.MINOR then return end
lib.__extrasMinor      = EXTRAS_MINOR
lib.__extrasShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.SkinPaintExtras = EXTRAS_MINOR

local prim, P = lib.prim, lib.__P
local rgba = P.rgba

-- ── the Ka0s extras of the window family ─────────────────────────────────────────────────────

local TITLE = { fill = "title.bg", extra = true }
local FOOT = { fill = "foot.bg", extra = true }
local CARD = { fill = "card.bg", border = "card.border", extra = true }

--- The first FontString among `opts[key]` and the frame's `fields`.
local function textOf(frame, opts, key, fields)
  if P.isFS(opts[key]) then return opts[key] end
  for _, f in ipairs(fields) do
    local v = P.field(frame, f, "FontString")
    if v then return v end
  end
  return nil
end

local function justify(rec, fs, align)
  local priors = P.saved(rec, "justify")
  if align then
    if priors[fs] == nil then priors[fs] = fs:GetJustifyH() end
    fs:SetJustifyH(align)
  elseif priors[fs] then
    fs:SetJustifyH(priors[fs])
    priors[fs] = nil
  end
end

--- S.TitleBar(bar, opts): a title bar. Its fill is `title.bg` (or the `title.bgTop` / `bgBottom`
--- gradient), the bar's backdrop when it has one, else a region of the bar under its text; its text (`opts.text`, else
--- `bar.title` / `bar.text`) takes `title.text`, the title font and `title.align`. Draws no Media
--- icon.
prim.TitleBar = function(owner, bar, opts)
  if type(bar) ~= "table" then return end
  local rec = P.track(owner, bar, "TitleBar", opts)
  opts = type(opts) == "table" and opts or {}
  local T = P.T(owner)
  P.box(rec, bar, T, TITLE, opts)
  local fs = textOf(bar, opts, "text", { "title", "text" })
  if not fs then return end
  P.tint(rec, fs, T, "title.text")
  P.font(owner, rec, fs, "title")
  justify(rec, fs, T["title.align"])
end

--- S.Divider(target, opts): a rule. A texture is colored in place (`SetColorTexture`, four
--- components: Core.ApplySkin's divider); a frame gets a line on its holder filling it.
--- `opts.token` names another color token ("section.rule", "tab.rule"). Draws no Media icon.
prim.Divider = function(owner, target, opts)
  if type(target) ~= "table" then return end
  local rec = P.track(owner, target, "Divider", opts)
  opts = type(opts) == "table" and opts or {}
  local c = P.T(owner)[opts.token or "divider"]
  if P.isTexture(target) then
    if c then target:SetColorTexture(rgba(c)) end
    return
  end
  local h = c and P.holder(rec, target)
  local t = h and P.tex(rec, "line", h, "ARTWORK")
  if not t then return P.hide(rec, "line") end
  t:SetAllPoints(h)
  t:SetColorTexture(rgba(c))
  t:Show()
end

--- S.Footer(frame, opts): a footer band, `foot.bg`, its text
--- (`opts.text`, else `frame.text`) in `text.muted`. Draws no Media icon.
prim.Footer = function(owner, frame, opts)
  if type(frame) ~= "table" then return end
  local rec = P.track(owner, frame, "Footer", opts)
  opts = type(opts) == "table" and opts or {}
  local T = P.T(owner)
  P.box(rec, frame, T, FOOT, opts)
  local fs = textOf(frame, opts, "text", { "text" })
  if fs then P.label(owner, rec, fs, T, "text.muted") end
end

--- S.Card(frame, opts): a card (LootHistory's KPI cards), `card.bg` under `card.border` as the
--- flat-control backdrop; `opts.title` takes `text.heading`, `opts.text` `text.body`. Draws no
--- Media icon.
prim.Card = function(owner, frame, opts)
  if type(frame) ~= "table" then return end
  local rec = P.track(owner, frame, "Card", opts)
  opts = type(opts) == "table" and opts or {}
  local T = P.T(owner)
  P.box(rec, frame, T, CARD, opts)
  if P.isFS(opts.title) then P.label(owner, rec, opts.title, T, "text.heading", "title") end
  if P.isFS(opts.text) then P.label(owner, rec, opts.text, T, "text.body") end
end

-- A wash: a texture colored in place, or a region of a frame filling it, under the frame's own text
-- and art (P.SUB.wash).
local function wash(owner, target, name, token, opts)
  if type(target) ~= "table" then return nil end
  local rec = P.track(owner, target, name, opts)
  local c = P.T(owner)[token]
  if P.isTexture(target) then
    if c then target:SetColorTexture(rgba(c)) end
    return rec
  end
  local t = c and P.subTex(rec, "wash", target, P.SUB.wash)
  if not t then
    P.hide(rec, "wash")
    return rec
  end
  t:SetAllPoints(target)
  t:SetColorTexture(rgba(c))
  t:Show()
  return rec
end

--- S.Strip(target, opts): the test / simulation strip's wash, `strip.test` or `strip.sim`
--- (`opts.kind`), on a texture in place (`W.TestStrip`'s fill) or as a region of a frame. The strip's
--- meaning colors are the library's; a skin changes only their legibility. Draws no Media icon.
prim.Strip = function(owner, target, opts)
  local kind = type(opts) == "table" and opts.kind == "sim" and "sim" or "test"
  wash(owner, target, "Strip", "strip." .. kind, opts)
end

--- S.Cover(target, opts): the combat cover's dim, `cover.dim`, on a texture in place
--- (OptionsCombat's) or a frame's fill holder; `opts.text` takes `cover.text`. Draws no Media icon.
prim.Cover = function(owner, target, opts)
  local rec = wash(owner, target, "Cover", "cover.dim", opts)
  if rec and type(opts) == "table" and P.isFS(opts.text) then
    P.label(owner, rec, opts.text, P.T(owner), "cover.text")
  end
end

--- S.Tooltip(frame): a LIBRARY-OWNED tooltip frame, never GameTooltip. Its backdrop is recolored
--- with `tooltip.bg` / `tooltip.border`. Draws no Media icon.
prim.Tooltip = function(owner, frame)
  if not P.hasBackdrop(frame) then return end
  local rec = P.track(owner, frame, "Tooltip")
  local T = P.T(owner)
  local bg, border = T["tooltip.bg"], T["tooltip.border"]
  if bg or border then
    P.saveBackdrop(rec, frame)
    return P.recolor(frame, bg, border)
  end
  if rec.regions.backdrop and rec.regions.backdrop.bd then P.restoreBackdrop(rec, frame) end
end

local MENU = { fill = "menu.bg", border = "menu.border", style = "menu.borderStyle",
               size = "menu.borderSize", insets = false }
local MENU_ALT = { fill = "menu.bg", border = "menu.borderAlt", style = "menu.borderStyle",
                   size = "menu.borderSize", insets = false }

--- S.MenuFrame(frame, opts): a popup menu. The flat backdrop with no insets, `menu.bg` under
--- `menu.border` (Widgets' shared popup menu), or `menu.borderAlt` with `opts.alt` (LootHistory's
--- row menu). `opts.popup` recolors the backdrop the frame already wears with `popup.bg` /
--- `popup.border` instead (the id-suggestion popup); a nil one restores what the frame wore before
--- the first paint. Draws no Media icon.
prim.MenuFrame = function(owner, frame, opts)
  if not P.hasBackdrop(frame) then return end
  local rec = P.track(owner, frame, "MenuFrame", opts)
  opts = type(opts) == "table" and opts or {}
  local T = P.T(owner)
  if opts.popup then
    -- The frame is built once and kept, so a nil token puts that half back as the frame wore it
    -- before the first paint, not as the last skin left it.
    P.saveBackdrop(rec, frame)
    local s, bg, border = rec.regions.backdrop, T["popup.bg"], T["popup.border"]
    if s and s.bd then
      if not bg and s.c[1] then frame:SetBackdropColor(unpack(s.c)) end
      if not border and s.b[1] then frame:SetBackdropBorderColor(unpack(s.b)) end
    end
    return P.recolor(frame, bg, border)
  end
  P.box(rec, frame, T, opts.alt and MENU_ALT or MENU, opts)
end

-- ── text and fonts ───────────────────────────────────────────────────────────────────────────

local TEXT_ROLE = {
  body = "text.body", muted = "text.muted", heading = "text.heading", headingAlt = "text.headingAlt",
  accent = "text.accent", disabled = "text.disabled", link = "text.link", linkHot = "text.linkHot",
  title = "title.text",
}
local TEXT_FONT = { title = "title", heading = "title", headingAlt = "title" }

--- S.Text(fs, role): a text role, "body", "muted", "heading", "headingAlt", "accent", "disabled",
--- "link", "linkHot" or "title": its color and its font (the title font for the title and heading
--- roles, the body font for the rest). Draws no Media icon.
prim.Text = function(owner, fs, role)
  if not P.isFS(fs) then return end
  local rec = P.track(owner, fs, "Text", role)
  role = TEXT_ROLE[role] and role or "body"
  P.tint(rec, fs, P.T(owner), TEXT_ROLE[role])
  P.font(owner, rec, fs, TEXT_FONT[role] or "body")
end

--- S.Font(fs, r, g, b): the skin's body font on `fs`, and the color when one is given.
prim.Font = function(owner, fs, r, g, b)
  if type(fs) ~= "table" then return end
  local rec = P.track(owner, fs, "Font", r, g, b)
  P.font(owner, rec, fs, "body")
  if type(r) == "number" and type(fs.SetTextColor) == "function" then fs:SetTextColor(r, g, b) end
end

--- S.White(fs): the body font and the body text color (white in the dark skins; EllesmereUI's
--- White, legible in a light skin).
prim.White = function(owner, fs)
  if type(fs) ~= "table" or type(fs.SetTextColor) ~= "function" then return end
  local rec = P.track(owner, fs, "White")
  P.font(owner, rec, fs, "body")
  P.tint(rec, fs, P.T(owner), "text.body")
end

-- ── the bar texture ──────────────────────────────────────────────────────────────────────────

--- The color a bar wears now: a Texture's vertex color, a StatusBar's bar color, alpha 1 if absent.
local function liveTint(target, statusBar)
  local get = statusBar and target.GetStatusBarColor or target.GetVertexColor
  local c = type(get) == "function" and { get(target) } or {}
  return { tonumber(c[1]) or 1, tonumber(c[2]) or 1, tonumber(c[3]) or 1, tonumber(c[4]) or 1 }
end

local function isWhite(c) return c[1] == 1 and c[2] == 1 and c[3] == 1 and c[4] == 1 end

--- The tint a BarTexture call paints with. A host's call that names a color paints that color.
--- Anything else, a nil color or any repaint, paints the bar's LIVE color, read on every call, so a
--- host's own SetVertexColor or SetStatusBarColor between paints is kept rather than undone. The one
--- color that cannot be read is a flat Texture's (its tint lives in SetColorTexture, its vertex
--- color is the white this primitive set): while that white is unchanged the remembered tint paints.
--- The memory belongs to the record that made it, so a texture Skin:Untrack handed back to a pool
--- starts from its own color, never the previous user's.
local function barTint(rec, target, statusBar, r, g, b, a)
  local mem = P.saved(rec, "barTint")
  local tint
  if type(r) == "number" and not lib.__repainting then
    tint = { r, tonumber(g) or 0, tonumber(b) or 0, tonumber(a) or 1 }
  else
    tint = liveTint(target, statusBar)
    if mem.rec == rec and mem.flat and isWhite(tint) then tint = mem.tint end
  end
  mem.rec, mem.tint, mem.flat = rec, tint, false
  return mem, unpack(tint)
end

--- S.BarTexture(target, r, g, b, a): the owner's bar texture (`bar.texture`, an LSM statusbar key;
--- the owner's texture override when it sets one) on a bar of data, tinted r, g, b, a. A Texture
--- takes SetTexture and SetVertexColor; a StatusBar SetStatusBarTexture and SetStatusBarColor. With
--- no texture resolved a Texture falls back to SetColorTexture(r, g, b, a), the flat look (its
--- vertex color white), and a StatusBar to WHITE8X8. Recorded, so a skin switch or an override
--- change re-applies the texture. The color is the bar's own from then on: a repaint keeps whatever
--- color the bar wears, a host's direct recolor included, and a nil color paints the bar's current
--- color on every call. Draws no Media icon.
prim.BarTexture = function(owner, target, r, g, b, a)
  if type(target) ~= "table" then return end
  local statusBar = P.kind(target) == "StatusBar"
  if not statusBar and not P.isTexture(target) then return end
  local rec = P.track(owner, target, "BarTexture", r, g, b, a)
  local path = P.media("statusbar", P.T(owner)["bar.texture"])
  local mem, tr, tg, tb, ta = barTint(rec, target, statusBar, r, g, b, a)
  if statusBar then
    target:SetStatusBarTexture(path or P.WHITE8)
    return target:SetStatusBarColor(tr, tg, tb, ta)
  end
  if path then
    target:SetTexture(path)
    return target:SetVertexColor(tr, tg, tb, ta)
  end
  target:SetColorTexture(tr, tg, tb, ta)
  target:SetVertexColor(1, 1, 1, 1)
  mem.flat = true
end

-- ── the getters (never recorded: they paint nothing) ─────────────────────────────────────────

local function colorOf(owner, name)
  local c = P.T(owner)[name]
  if type(c) ~= "table" then return nil end
  return c[1], c[2], c[3], c[4] or 1
end

--- S.GetAccentColor(): r, g, b, a of `text.accent`.
prim.GetAccentColor = function(owner) return colorOf(owner, "text.accent") end
--- S.GetPanelColor(): r, g, b, a of `win.bg`.
prim.GetPanelColor = function(owner) return colorOf(owner, "win.bg") end
--- S.GetFont(): the body font's path, or the client's standard font when the skin sets none.
prim.GetFont = function(owner)
  local path = P.media("font", P.T(owner)["font.body"])
  if path then return path end
  return type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT or nil
end
--- S.GlowColor(): r, g, b, a of `glow.color`, or nil (the host's own glow color stands).
prim.GlowColor = function(owner) return colorOf(owner, "glow.color") end

local CHART_KEYS = { "axis", "axisAlt", "grid", "crosshair", "marker", "line", "bar", "track", "total",
                     "other", "otherLine", "series" }

--- S.ChartStyle(): a fresh table of the chart tokens by short name (`axis`, `grid`, `crosshair`,
--- `marker`, `line`, `series`, ...). The colors are shared: read them, never write them.
prim.ChartStyle = function(owner)
  local T, out = P.T(owner), {}
  for _, k in ipairs(CHART_KEYS) do out[k] = T["chart." .. k] end
  return out
end

--- S.BarStyle(): a fresh table of the HUD tokens: `texture` (the LSM path, or nil), `textureKey`,
--- `gloss`, `bg`, `border`, `borderStyle`, `borderSize`, `font` (path or nil), `fontKey`, `fontSize`,
--- `outline`, `iconBorder`.
prim.BarStyle = function(owner)
  local T = P.T(owner)
  return {
    texture = P.media("statusbar", T["bar.texture"]), textureKey = T["bar.texture"],
    gloss = T["bar.gloss"] == true, bg = T["bar.bg"], border = T["bar.border"],
    borderStyle = T["bar.borderStyle"], borderSize = T["bar.borderSize"],
    font = P.media("font", T["hud.font"]), fontKey = T["hud.font"], fontSize = T["hud.fontSize"],
    outline = T["hud.outline"], iconBorder = T["icon.border"],
  }
end
