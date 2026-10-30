-- LibKa0s-Skin-1.0 — the Ka0s paint primitives, part two: the window family's Ka0s extras
-- (TitleBar, Divider, Footer, Card, Strip, Cover, Tooltip, MenuFrame), the stock-art faders of
-- EllesmereUI's vocabulary (FadeRegions, FadeNineSlice, from SkinPaint.lua since its minor 11), the
-- text and font primitives (Text, Font, White), the bar texture (BarTexture) and the getters
-- (GetAccentColor, GetPanelColor, GetFont, GlowColor, ChartStyle, BarStyle).
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
-- Minor 5 (LK-02 of Ka0sAddonsCommonTasks docs/2026-10-29-SKINNING_ROLLOUT): Card's `opts.tokens`
-- slot remap (`bg`, `border`, `title`, `text`; SkinPaint minor 11's P.remap), and the two faders,
-- moved here unchanged from SkinPaint.lua, which they would have taken into layout-§1's band.
-- Then (LK-05 of the same run, still minor 5): TitleBar's and FadeNineSlice's `opts.stockDefault`
-- (SkinPaint minor 11's P.keepStock, retired at SkinPaint minor 12), and Panel and Inset, moved here
-- unchanged from SkinPaint.lua for the same reason. And (LK-01's review, still minor 5): S.Text takes an owner or library token
-- NAME as well as a role, so an owner token is drawn through a tracked, replayed primitive.
-- Minor 6 (LK-01 of Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_LIBRARY_FOLLOWUPS, ruling R-1):
-- BarStyle's `font`, `fontKey` and `outline` are nil while the owner ignores fonts, read through
-- `Skin:Token` like every host read, so the host's own setting stands.
-- Then (LK-05 of the same run, ruling R-5, decision D-02, still minor 6): P.panelIgnored, the
-- settings-panel scope every primitive and widget can share, and S.Text's `opts.panel`. It lives here
-- rather than in SkinPaint.lua, so that file stays out of layout-§1's 1000-line band.
-- Then (LK-02 of the same run, ruling R-2, still minor 6): the stock look is retired. TitleBar,
-- FadeNineSlice, Panel and Inset ignore a stale `opts.stockDefault` and paint under Ka0s Default as
-- under every skin (SkinPaint minor 12, which gives a TitleBar's alignment back in P.unpaint).
-- Then (LK-06a of the same run, ruling R-5, decision D-02, still minor 6): S.Strip takes
-- `opts.panel` as S.Text does, for `W.TestStrip`'s `opts.panel`; P.panelIgnored records its answer
-- as `rec.panelOff` for P.hook.
local EXTRAS_MINOR = 6
if lib.__extrasMinor and lib.__extrasMinor >= EXTRAS_MINOR
  and lib.__extrasShellMinor == lib.MINOR then return end
lib.__extrasMinor      = EXTRAS_MINOR
lib.__extrasShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.SkinPaintExtras = EXTRAS_MINOR

local prim, P = lib.prim, lib.__P
local rgba = P.rgba

--- The settings-panel scope (minor 6, LK-05, decision D-02): true when `opts.panel == true` puts the
--- target on its owner's settings panel and that owner ignores its panel (the public
--- `Skin:GetIgnore(owner)` panel half, which is false for an unregistered owner, so an owner-less
--- facade keeps reading Ka0s Default). Then everything the target wears from the library is given
--- back (P.unpaint) and the caller paints nothing. The call stays recorded, so `SetIgnore`'s repaint
--- replays it and the switch is live both ways. Without `opts.panel` it answers false: a window wears
--- the skin whatever that switch says (D-01).
--- The answer is kept on the record as `rec.panelOff` (LK-06a, still minor 6), so a hook a primitive
--- laid (P.hook: the search box's focus line) stands down with the paint it belongs to, live both ways.
--- Dropdown, EditBox and Strip take the same `opts.panel` from LK-06a, for the Widgets controls.
function P.panelIgnored(owner, rec, frame, opts)
  if not rec then return false end
  local off = type(opts) == "table" and opts.panel == true
    and type(lib.GetIgnore) == "function" and lib:GetIgnore(owner) == true
  rec.panelOff = off or nil
  if not off then return false end
  P.unpaint(rec, frame)
  return true
end

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
--- `bar.title` / `bar.text`) takes `title.text`, the title font and `title.align`, every one given
--- back by P.unpaint (the alignment since SkinPaint minor 12). Draws no Media icon.
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

local CARD_SLOTS = { bg = "card.bg", border = "card.border", title = "text.heading", text = "text.body" }
local CARD_FILLS = { bg = true }

--- S.Card(frame, opts): a card (LootHistory's KPI cards), `card.bg` under `card.border` as the
--- flat-control backdrop; `opts.title` takes `text.heading`, `opts.text` `text.body`. `opts.tokens`
--- (minor 5) remaps `bg`, `border`, `title` and `text` to a library or owner token by NAME (an
--- alternate card fill, a callout). Draws no Media icon.
prim.Card = function(owner, frame, opts)
  if type(frame) ~= "table" then return end
  local rec = P.track(owner, frame, "Card", opts)
  opts = type(opts) == "table" and opts or {}
  local T = P.T(owner)
  if P.remap then T = P.remap(owner, T, opts.tokens, CARD_SLOTS, CARD_FILLS, "Card") end
  P.box(rec, frame, T, CARD, opts)
  if P.isFS(opts.title) then P.label(owner, rec, opts.title, T, "text.heading", "title") end
  if P.isFS(opts.text) then P.label(owner, rec, opts.text, T, "text.body") end
end

-- A wash: a texture colored in place, or a region of a frame filling it, under the frame's own text
-- and art (P.SUB.wash).
local function wash(owner, target, name, token, opts)
  if type(target) ~= "table" then return nil end
  local rec = P.track(owner, target, name, opts)
  if P.panelIgnored(owner, rec, target, opts) then return rec end
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
--- meaning colors are the library's; a skin changes only their legibility. `opts.panel = true`
--- (minor 6, LK-06a): the strip is on its owner's settings panel, so nothing is painted while the
--- owner ignores its panel (P.panelIgnored); a texture's own color cannot be read back, so the caller
--- puts it back (`W.TestStrip` does). Draws no Media icon.
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

-- ── the panels (SkinPaint.lua's until its minor 11, LK-05; moved unchanged) ────────────────────

local PANEL = { fill = "panel.bg", border = "panel.border" }
local NAV_SLOTS = { bg = "nav.bg", border = "nav.border" }
local INSET = { fill = "input.bg", border = "input.border", style = "input.borderStyle",
                size = "input.borderSize" }

local function panel(owner, frame, opts, name, spec)
  if type(frame) ~= "table" then return end
  local rec = P.track(owner, frame, name, opts)
  opts = type(opts) == "table" and opts or {}
  P.markStock(rec, frame, opts)
  local T = P.T(owner)
  if opts.nav then
    -- The settings nav rail keeps its own backdrop art and is recolored (OptionsNav's pane); its
    -- colors are saved first, so P.unpaint can put them back (minor 8: the panel exception, live).
    if P.hasBackdrop(frame) then P.saveBackdrop(rec, frame) end
    T = P.remap(owner, T, opts.tokens, NAV_SLOTS, nil, name)
    return P.recolor(frame, T["nav.bg"], T["nav.border"])
  end
  if opts.inset then spec = INSET end
  T = P.remap(owner, T, opts.tokens, { bg = spec.fill, border = spec.border }, P.FILL_SLOTS, name)
  P.box(rec, frame, T, spec, opts)
end

--- S.Panel(frame, opts): a flat panel, `panel.bg` under a `panel.border` edge (LootHistory's list
--- panels). `opts.inset` paints it as an inset (`input.*`); `opts.noBg`, `opts.noBorder` leave out
--- either half; `opts.nav` recolors the backdrop the frame already wears with `nav.bg` /
--- `nav.border` (the settings nav rail). `opts.tokens` (SkinPaint minor 11) remaps `bg` and `border` (the
--- panel's, the inset's or the nav rail's) to a library or owner token by NAME (a caution callout).
--- Draws no Media icon.
prim.Panel = function(owner, frame, opts) return panel(owner, frame, opts, "Panel", PANEL) end

--- S.Inset(frame, opts): a recessed area, the input colors (`input.bg`, `input.border`, its style
--- and size). `opts.tokens` remaps `bg` and `border` as Panel's does. Draws no Media icon.
prim.Inset = function(owner, frame, opts) return panel(owner, frame, opts, "Inset", INSET) end

-- ── the stock-art faders (SkinPaint.lua's until its minor 11) ───────────────────────────────

--- S.FadeRegions(frame, ...): fade every texture region of `frame` (and of each further frame) that
--- no primitive made, prior alphas recorded, under every skin, Ka0s Default included (SkinPaint
--- minor 6).
prim.FadeRegions = function(owner, frame, ...)
  if not P.isFrame(frame) then return end
  local rec = P.track(owner, frame, "FadeRegions", ...)
  rec.regions.stock = true
  local frames = { frame, ... }
  for _, f in ipairs(frames) do
    if P.isFrame(f) and type(f.GetRegions) == "function" then
      for _, r in ipairs({ f:GetRegions() }) do
        if P.isTexture(r) and not lib.__ours[r] then P.fade(rec, r) end
      end
    end
  end
end

--- S.FadeNineSlice(frame, opts): fade the nine pieces of `frame.NineSlice`, under every skin, Ka0s
--- Default included.
prim.FadeNineSlice = function(owner, frame, opts)
  if not P.isFrame(frame) then return end
  local rec = P.track(owner, frame, "FadeNineSlice", opts)
  rec.regions.stock = true
  local ns = rawget(frame, "NineSlice")
  if not P.isFrame(ns) then return end
  for _, k in ipairs(P.NINE_KEYS or {}) do P.fade(rec, P.field(ns, k, "Texture")) end
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
--- roles, the body font for the rest). Or (minor 5) a token NAME, library or owner ("dw.note",
--- "sem.good"): the color from that token, in the body font, replayed on a skin switch like a role.
--- A name the owner cannot read (logged once) or a token that is not a color draws as "body".
--- S.Text(fs, role, { panel = true }) (minor 6, LK-05): the string is on the owner's settings panel,
--- so it is given back, its own color and font, while the owner ignores its panel (P.panelIgnored),
--- live both ways. Without it Text paints whatever that switch says, as a window string must; Ignore
--- fonts reaches it either way, through P.font. Draws no Media icon.
prim.Text = function(owner, fs, role, opts)
  if not P.isFS(fs) then return end
  local rec = P.track(owner, fs, "Text", role, opts)
  if P.panelIgnored(owner, rec, fs, opts) then return end
  local T, token = P.T(owner), TEXT_ROLE[role]
  if not token and type(role) == "string" and role:find(".", 1, true)
    and type(lib.__RemapName) == "function" and lib:__RemapName(owner, role, "Text")
    and (T[role] == nil or type(T[role]) == "table") then   -- a color token; never a face or a size
    token = role
  end
  P.tint(rec, fs, T, token or "text.body")
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
--- `outline`, `iconBorder`. `font`, `fontKey` and `outline` are nil while the owner ignores fonts
--- (minor 6, R-1): they read through `Skin:Token`, which leaves the HUD's face and outline alone then.
prim.BarStyle = function(owner)
  local T = P.T(owner)
  local face, outline = lib:Token(owner, "hud.font"), lib:Token(owner, "hud.outline")
  return {
    texture = P.media("statusbar", T["bar.texture"]), textureKey = T["bar.texture"],
    gloss = T["bar.gloss"] == true, bg = T["bar.bg"], border = T["bar.border"],
    borderStyle = T["bar.borderStyle"], borderSize = T["bar.borderSize"],
    font = P.media("font", face), fontKey = face, fontSize = T["hud.fontSize"],
    outline = outline, iconBorder = T["icon.border"],
  }
end
