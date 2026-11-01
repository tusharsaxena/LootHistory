-- LibKa0s-Skin-1.0 — the Ka0s paint primitives, part two: the window family's Ka0s extras
-- (TitleBar, Divider, Footer, Card, Strip, Cover, Tooltip, MenuFrame), the stock-art faders of
-- EllesmereUI's vocabulary (FadeRegions, FadeNineSlice, from SkinPaint.lua since its minor 11), the
-- text and font primitives (Text, Font, White), the bar texture (BarTexture) and the getters
-- (GetAccentColor, GetPanelColor, GetFont, GlowColor, HudTextColor, HudLabelColor, BarFillColor,
-- HudShadow, ChartStyle, BarStyle), and the HUD's two shared looks (BarGloss, HudFont).
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
-- Minor 7 (LK-04 of Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK, the owner's ruling
-- D-07): S.FontFlags(value, where), the flags an element draws with from its stored Font flags: a
-- picked flag wins, and "From skin" (FROM_SKIN; nil too) resolves through the owner's Font outline
-- (Skin minor 9). OptionsCompose minor 14's `flagsFromSkin` offers the value. Then (LK-06 of the same
-- bundle, ruling D-09, still minor 7): S.HudFontSize(size, fromSkin), the size a HUD element stored at
-- `size` draws at: scaled by the skin's `hud.fontSize` over Ka0s Default's while it uses the skin's
-- face, the stored size while it draws its own (fromSkin false) or the owner ignores fonts.
-- Minor 8 (cause L3 of Ka0sAddonsCommonTasks docs/2026-11-01-FULL_SKINNING): a stated
-- `popup.borderStyle` or `nav.borderStyle` boxes the suggestion popup or the rail in the skin's own
-- edge and size, where both only recolored; `false`, Ka0s Default's, is the art the frame wears.
-- Minor 9 (cause L6 of the same bundle): S.Mark and S.MarkText, a small mark in the skin's tint and,
-- once the host names one, a Ka0s icon in place of client art.
-- Minor 10 (cause L8 of the same bundle): S.GetFont("mono") answers `font.mono`, or nil; a proportional
-- fallback would draw a glyph column as boxes.
-- Minor 11 (cause L9 of the same bundle): S.TitleBar's `opts.place`, the bar's height from
-- `title.height` and its text placed by `title.align`. Additive: with no `opts.place` a bar is as it was.
-- Minor 12 (FS-T1 of the same bundle, causes D2, D3 and D6): S.HudTextColor, S.HudLabelColor,
-- S.BarFillColor and S.HudShadow, and BarStyle's `text`, `label` and `fill`. Additive.
-- Minor 13 (cause A4 of the same bundle): S.Panel's `opts.popup`, the box in `popup.*`, and the
-- delete confirmation of a Ka0s profile page (the section at the end of this file). Additive.
-- Minor 14 (FS-FIX of the same bundle, the AbsorbTracker pilot's gaps): S.BarGloss and S.HudFont, so
-- five hosts draw one gloss and none writes its own font object. Additive.
-- Minor 15 (FS-FIX of the same bundle, the review of minor 14): S.BarGloss's `fromSkin`, the host's
-- texture companion, kept on a replay; S.HudFont's skin face read through Skin:Token, so Ignore fonts
-- reaches it as it reaches the shadow. Additive. Ka0s Default's look does not move.
local EXTRAS_MINOR = 15
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

-- Where a placed title stands: the token's edge, in from it by what the host reserved for controls.
local TITLE_INSET = 8

--- opts.place: the bar takes `title.height`, and its text an anchor on the bar's `title.align`.
--- Justifying a string only moves it inside its own width, and a hand-anchored title has none.
local function place(bar, fs, T, spec)
  if T["title.height"] then bar:SetHeight(T["title.height"]) end
  local align = T["title.align"]
  if not (fs and align) then return end
  local reserve = type(spec) == "table" and spec or {}
  local x = 0
  if align == "LEFT" then x = reserve.left or TITLE_INSET end
  if align == "RIGHT" then x = -(reserve.right or TITLE_INSET) end
  fs:ClearAllPoints()
  fs:SetPoint(align, bar, align, x, 0)
end

--- S.TitleBar(bar, opts): a title bar. Its fill is `title.bg` (or the `title.bgTop` / `bgBottom`
--- gradient), the bar's backdrop when it has one, else a region of the bar under its text; its text (`opts.text`, else
--- `bar.title` / `bar.text`) takes `title.text`, the title font and `title.align`, every one given
--- back by P.unpaint (the alignment since SkinPaint minor 12). `opts.place` (minor 11), true or
--- `{ left, right }`, the px a LEFT or RIGHT title stays clear of for the bar's controls (default 8),
--- gives a hand-built bar `title.height` and anchors its text by `title.align`; that is geometry,
--- so P.unpaint leaves it. Draws no Media icon.
prim.TitleBar = function(owner, bar, opts)
  if type(bar) ~= "table" then return end
  local rec = P.track(owner, bar, "TitleBar", opts)
  opts = type(opts) == "table" and opts or {}
  local T = P.T(owner)
  P.box(rec, bar, T, TITLE, opts)
  local fs = textOf(bar, opts, "text", { "title", "text" })
  if opts.place then place(bar, fs, T, opts.place) end
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

--- S.Mark(tex, opts): a small mark on texture `tex` in the skin's tint. `opts.token` names the color
--- (default `icon.tint`; `sem.good` and `sem.bad` for a mark that means something), `opts.art` is the
--- Ka0s icon drawn in place of the client art `tex` wore, a path the host resolved and declared.
--- `opts.panel = true`: the mark is on the owner's settings panel, so while the owner ignores its
--- panel the tint is given back and `opts.stock(tex)` puts the client art back, a texture's art
--- being nothing P.unpaint can read. Live both ways, replayed on a skin switch. Draws no Media icon
--- of its own.
prim.Mark = function(owner, tex, opts)
  if not P.isTexture(tex) then return end
  opts = type(opts) == "table" and opts or {}
  local rec = P.track(owner, tex, "Mark", opts)
  if P.panelIgnored(owner, rec, tex, opts) then
    if type(opts.stock) == "function" then opts.stock(tex) end
    return
  end
  if opts.art then tex:SetTexture(opts.art) end
  P.tint(rec, tex, P.T(owner), opts.token or "icon.tint", "SetVertexColor")
end

--- S.MarkText(path, size, token): the same mark as inline `|T...|t` markup, for a line of text: icon
--- `path` at `size` (default 14; 0 is the line's height) in `token`, default `icon.tint`. A string
--- cannot be repainted, so a caller writes it again after a skin switch. Draws no Media icon of its
--- own.
prim.MarkText = function(owner, path, size, token)
  size = size or 14
  local c = P.T(owner)[token or "icon.tint"]
  if type(c) ~= "table" then return ("|T%s:%d:%d|t"):format(path, size, size) end
  local function byte(x) return math.floor(x * 255 + 0.5) end
  return ("|T%s:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t"):format(path, size, size,
    byte(c[1]), byte(c[2]), byte(c[3]))
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

--- Give a settings frame its own art back after a skin boxed it, so the recolor that follows lands
--- on the art it was built with.
local function keepArt(rec, frame)
  if not rec.regions.boxed then return end
  rec.regions.boxed = nil
  P.restoreBackdrop(rec, frame)
  P.hide(rec, "grad")
  P.hideEdges(rec, frame)
end

local POPUP = { fill = "popup.bg", border = "popup.border", style = "popup.borderStyle",
                size = "popup.borderSize", insets = false }

--- S.MenuFrame(frame, opts): a popup menu. The flat backdrop with no insets, `menu.bg` under
--- `menu.border` (Widgets' shared popup menu), or `menu.borderAlt` with `opts.alt` (LootHistory's
--- row menu). `opts.popup` recolors the backdrop the frame already wears with `popup.bg` /
--- `popup.border` instead (the id-suggestion popup); a nil one restores what the frame wore before
--- the first paint. A skin stating `popup.borderStyle` boxes it in `popup.borderSize` instead of
--- recoloring; `false`, Ka0s Default's, keeps the frame's art. Draws no Media icon.
prim.MenuFrame = function(owner, frame, opts)
  if not P.hasBackdrop(frame) then return end
  local rec = P.track(owner, frame, "MenuFrame", opts)
  opts = type(opts) == "table" and opts or {}
  local T = P.T(owner)
  if opts.popup and T["popup.borderStyle"] then
    rec.regions.boxed = true
    return P.box(rec, frame, T, POPUP, opts)
  end
  if opts.popup then
    keepArt(rec, frame)
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
local NAV = { fill = "nav.bg", border = "nav.border", style = "nav.borderStyle", size = "nav.borderSize" }
local INSET = { fill = "input.bg", border = "input.border", style = "input.borderStyle",
                size = "input.borderSize" }

--- The settings nav rail: boxed in the skin's edge when it states `nav.borderStyle`, else its own
--- backdrop art recolored, its colors saved first so P.unpaint can put them back (minor 8: the panel
--- exception, live).
local function navPane(owner, rec, frame, T, opts, name)
  T = P.remap(owner, T, opts.tokens, NAV_SLOTS, nil, name)
  if T["nav.borderStyle"] then
    rec.regions.boxed = true
    return P.box(rec, frame, T, NAV, opts)
  end
  keepArt(rec, frame)
  if P.hasBackdrop(frame) then P.saveBackdrop(rec, frame) end
  return P.recolor(frame, T["nav.bg"], T["nav.border"])
end

local function panel(owner, frame, opts, name, spec)
  if type(frame) ~= "table" then return end
  local rec = P.track(owner, frame, name, opts)
  opts = type(opts) == "table" and opts or {}
  P.markStock(rec, frame, opts)
  local T = P.T(owner)
  if opts.nav then return navPane(owner, rec, frame, T, opts, name) end
  if opts.inset then spec = INSET elseif opts.popup then spec = POPUP end
  T = P.remap(owner, T, opts.tokens, { bg = spec.fill, border = spec.border }, P.FILL_SLOTS, name)
  P.box(rec, frame, T, spec, opts)
end

--- S.Panel(frame, opts): a flat panel, `panel.bg` under a `panel.border` edge (LootHistory's list
--- panels). `opts.inset` paints it as an inset (`input.*`); `opts.noBg`, `opts.noBorder` leave out
--- either half; `opts.nav` recolors the backdrop the frame already wears with `nav.bg` /
--- `nav.border` (the settings nav rail), or boxes it in `nav.borderStyle` and `nav.borderSize` when
--- the skin states a style; `false`, Ka0s Default's, keeps the art. `opts.popup` (minor 13) paints it
--- as a floating box instead, `popup.bg` under `popup.border` in `popup.borderStyle` and
--- `popup.borderSize`. `opts.tokens` (SkinPaint minor 11) remaps `bg` and `border` (the
--- panel's, the inset's, the popup's or the nav rail's) to a library or owner token by NAME (a
--- caution callout). Draws no Media icon.
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
prim.GetFont = function(owner, role)
  local mono = role == "mono"
  local path = P.media("font", P.T(owner)[mono and "font.mono" or "font.body"])
  if path or mono then return path end
  return type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT or nil
end
--- S.GlowColor(): r, g, b, a of `glow.color`, or nil (the host's own glow color stands).
prim.GlowColor = function(owner) return colorOf(owner, "glow.color") end
--- S.HudTextColor() (minor 12, D2): r, g, b, a of `hud.text`, HUD text's color. Never a class color.
prim.HudTextColor = function(owner) return colorOf(owner, "hud.text") end
--- S.HudLabelColor() (minor 12, D2): r, g, b, a of `hud.label`, a HUD label or header's color.
prim.HudLabelColor = function(owner) return colorOf(owner, "hud.label") end
--- S.BarFillColor() (minor 12, D3): r, g, b, a of `bar.fill`. Class and state fills stay the host's.
prim.BarFillColor = function(owner) return colorOf(owner, "bar.fill") end
--- S.HudShadow() (minor 12, D6): the skin's HUD text shadow as x, y, r, g, b, a; `false` when the skin
--- draws none (`hud.shadow` false); nil while the owner ignores fonts, when the host's own setting
--- stands. A 12.0.7 client draws only a font object's shadow, so set these on one (SkinPaint's header).
prim.HudShadow = function(owner)
  if lib:__FontsIgnored(owner) then return nil end
  local T = P.T(owner)
  local c = T["hud.shadow"]
  if type(c) ~= "table" then return false end
  return T["hud.shadowX"], T["hud.shadowY"], c[1], c[2], c[3], c[4] or 1
end

local CHART_KEYS = { "axis", "axisAlt", "grid", "crosshair", "marker", "line", "bar", "track", "total",
                     "other", "otherLine", "series" }

--- S.ChartStyle(): a fresh table of the chart tokens by short name (`axis`, `grid`, `crosshair`,
--- `marker`, `line`, `series`, ...). The colors are shared: read them, never write them.
prim.ChartStyle = function(owner)
  local T, out = P.T(owner), {}
  for _, k in ipairs(CHART_KEYS) do out[k] = T["chart." .. k] end
  return out
end

--- S.FontFlags(value, where) (minor 7): the font flags an element draws with, from its stored Font
--- flags `value`. A picked flag (any string but FROM_SKIN: "", "OUTLINE", "THICKOUTLINE",
--- "MONOCHROME", "OUTLINE, MONOCHROME") wins, answered as stored. FROM_SKIN, the setting's "From skin"
--- (and nil or a non-string: nothing stored), resolves through the owner's Font outline: the HUD's
--- `hud.outline` ("OUTLINE" under "all" and "hud", "" under "off"), or with `where == "window"` the
--- window text's `font.outline` ("" under "hud" too). While the owner ignores fonts the Font outline
--- is not read: FROM_SKIN answers "OUTLINE" for the HUD (FontGroup's old default; on purpose unlike
--- `Resolve`, whose nil hands the host its own) and "" for window text (its stock flags). Never nil.
prim.FontFlags = function(owner, value, where)
  if type(value) == "string" and value ~= lib.FROM_SKIN then return value end
  if lib:__FontsIgnored(owner) then return where == "window" and "" or "OUTLINE" end
  local v = P.T(owner)[where == "window" and "font.outline" or "hud.outline"]
  return type(v) == "string" and v or ""
end

--- S.HudFontSize(size, fromSkin) (minor 7, LK-06): the size a HUD element stored at `size` draws at.
--- While it uses the skin's face (`fromSkin` true or nil) that is `size` times the owner's skin's
--- `hud.fontSize` over Ka0s Default's (P.fontSize), so its text is as wide in every skin; with
--- `fromSkin == false` (its own face) or while the owner ignores fonts, `size` as stored. The stored
--- value is never written. A size that is not a number above 0 counts as none: the skin's HUD size,
--- or 12 unscaled. Never nil, never a height SetFont refuses.
prim.HudFontSize = function(owner, size, fromSkin)
  local n = tonumber(size)
  if n and n <= 0 then n = nil end
  if fromSkin == false or lib:__FontsIgnored(owner) then return n or 12 end
  return P.fontSize(owner, "hud.fontSize", n)
end

--- S.BarStyle(): a fresh table of the HUD tokens: `texture` (the LSM path, or nil), `textureKey`,
--- `gloss`, `bg`, `border`, `borderStyle`, `borderSize`, `font` (path or nil), `fontKey`, `fontSize`,
--- `outline`, `iconBorder`, `text`, `label`, `fill` (minor 12). The shadow is `S.HudShadow`'s, not
--- a field here. `font`, `fontKey` and `outline` are nil while the owner ignores fonts
--- (minor 6, R-1): they read through `Skin:Token`, which leaves the HUD's face and outline alone then.
--- `fontSize` is `S.HudFontSize()` (minor 7): the skin's own `hud.fontSize`, or Ka0s Default's 12
--- while the owner ignores fonts, since the host's own face was never measured at the skin's size.
prim.BarStyle = function(owner)
  local T = P.T(owner)
  local face, outline = lib:Token(owner, "hud.font"), lib:Token(owner, "hud.outline")
  return {
    texture = P.media("statusbar", T["bar.texture"]), textureKey = T["bar.texture"],
    gloss = T["bar.gloss"] == true, bg = T["bar.bg"], border = T["bar.border"],
    borderStyle = T["bar.borderStyle"], borderSize = T["bar.borderSize"],
    font = P.media("font", face), fontKey = face, fontSize = prim.HudFontSize(owner),
    outline = outline, iconBorder = T["icon.border"],
    text = T["hud.text"], label = T["hud.label"], fill = T["bar.fill"],
  }
end

-- ── the HUD's shared looks (minor 14) ────────────────────────────────────────────────────────

-- The one gloss look, as P.fill's tokens: no skin token says otherwise, `bar.gloss` is a bool.
local GLOSS = { glossTop = { 1, 1, 1, 0.25 }, glossBottom = { 1, 1, 1, 0 } }

--- S.BarGloss(statusBar, fromSkin) (minor 14): the skin's gloss on a bar of data, where `bar.gloss` is true: a
--- white gradient over the fill's top half, 0.25 at the top and clear at the middle. One layer, built
--- on first need, a region of the status bar at the bottom of OVERLAY, so it sits over the fill and
--- under a host's text, and it is anchored to the fill, so it never shines past it. That makes it the
--- one overlay that is no holder's: a holder would sit over a host's border and text. `fromSkin`
--- (minor 15) is the host's texture companion: the gloss belongs to the skin's texture, so `false`, a
--- player's own texture, hides it, and nil or true leave it to the skin. Recorded with the argument,
--- so a skin change shows or hides it with no host call and a replay keeps `false`; call it once
--- after the bar has its texture, again when the companion moves, and again if a host hands the bar
--- a new fill Texture. Anything but a StatusBar is left alone. Draws no Media icon.
prim.BarGloss = function(owner, statusBar, fromSkin)
  if P.kind(statusBar) ~= "StatusBar" then return end
  local rec = P.track(owner, statusBar, "BarGloss", fromSkin)
  local fill = statusBar:GetStatusBarTexture()
  if fromSkin == false or P.T(owner)["bar.gloss"] ~= true or not fill then
    return P.hide(rec, "gloss")
  end
  local gloss = P.tex(rec, "gloss", statusBar, "OVERLAY", -8)
  if not gloss then return end
  gloss:ClearAllPoints()
  gloss:SetPoint("TOPLEFT", fill, "TOPLEFT")
  gloss:SetPoint("BOTTOMRIGHT", fill, "RIGHT")
  P.fill(rec, gloss, GLOSS, "gloss")
end

lib.__hudFonts = lib.__hudFonts or setmetatable({}, { __mode = "k" })
lib.__hudFontSeq = lib.__hudFontSeq or 0

--- The font object `fs` wears: one per string, named, kept for the session. Nil where the client has
--- no CreateFont. A client never frees a font object, so a repeat call never makes another.
local function hudFontObject(owner, fs)
  if type(CreateFont) ~= "function" then return nil end
  local obj = lib.__hudFonts[fs]
  if obj then return obj end
  lib.__hudFontSeq = lib.__hudFontSeq + 1
  obj = CreateFont("LibKa0sHud_" .. tostring(owner) .. "_" .. lib.__hudFontSeq)
  lib.__hudFonts[fs] = obj
  return obj
end

--- A stored shadow as x, y, r, g, b, a, or false: `true` is the client's 1, -1 in black, a table is
--- `{ x, y, r, g, b, a }`, anything else is none.
local function storedShadow(s)
  if s == true then return 1, -1, 0, 0, 0, 1 end
  if type(s) ~= "table" or type(s[1]) ~= "number" then return false end
  return s[1], s[2] or 0, s[3] or 0, s[4] or 0, s[5] or 0, s[6] or 1
end

--- The shadow a HUD string draws. With the host's companion on (nil counts), S.HudShadow's answer:
--- false none, numbers those; nil, the owner ignoring fonts, and a companion off leave the stored one.
local function hudShadow(owner, opts)
  if opts.shadowFromSkin ~= false then
    local x, y, r, g, b, a = prim.HudShadow(owner)
    if x == false then return false end
    if x ~= nil then return x, y, r, g, b, a end
  end
  return storedShadow(opts.shadow)
end

--- Face, size and flags on `target`. The client answers false for a file it has not loaded, which
--- on a fresh font object leaves no font at all, so the client's own face goes on instead.
local function setHudFace(target, face, size, flags)
  if target:SetFont(face, size, flags) == false and type(STANDARD_TEXT_FONT) == "string" then
    target:SetFont(STANDARD_TEXT_FONT, size, flags)
  end
end

--- BOTH shadow arms write: an off arm that skipped the calls would keep what the last pass set.
local function setHudShadow(target, x, y, r, g, b, a)
  if x == false then x, y, r, g, b, a = 0, 0, 0, 0, 0, 0 end
  target:SetShadowColor(r, g, b, a)
  target:SetShadowOffset(x, y)
end

--- S.HudFont(fs, opts) (minor 14): the one way to give a HUD string its face, size, flags and shadow.
--- It all goes on one named font object per string, the only place a 12.0.7 client draws a shadow,
--- or on the string where the client has no CreateFont. `opts`, all optional: `face` (a path; the
--- skin's `hud.font`, unread while the owner ignores fonts (minor 15), else the client's), `size` (as it draws: pass `S.HudFontSize`'s
--- answer; 12 when not above 0), `flags` (through S.FontFlags, so "@skin" is safe), `shadow` (the
--- host's stored one: true, false or `{ x, y, r, g, b, a }`), `shadowFromSkin` (the host's companion;
--- false draws `shadow` under every skin). S.HudShadow's three answers apply while the companion is
--- on: false no shadow, nil the stored `shadow`, numbers those. A keyed table is no shadow, with no
--- error. Answers the font object, or nil.
--- Not recorded: the face and size are the host's resolved values, which a replay would draw stale,
--- so call it from the appearance pass a skin change reaches, and set the text color after it.
prim.HudFont = function(owner, fs, opts)
  if type(fs) ~= "table" or P.isTexture(fs) or type(fs.SetFont) ~= "function" then return nil end
  opts = type(opts) == "table" and opts or {}
  local face = opts.face
  if type(face) ~= "string" or face == "" then
    face = P.media("font", lib:Token(owner, "hud.font")) or STANDARD_TEXT_FONT
  end
  if type(face) ~= "string" then return nil end
  local size, flags = prim.HudFontSize(owner, opts.size, false), prim.FontFlags(owner, opts.flags)
  local obj = hudFontObject(owner, fs)
  local target = obj or fs
  setHudFace(target, face, size, flags)
  setHudShadow(target, hudShadow(owner, opts))
  if obj then fs:SetFontObject(obj) end
  return obj
end

-- ── AceConfigDialog's confirmation box, for a Ka0s profile page (cause A4) ─────────────────────
--
-- AceConfigDialog keeps ONE popup for the client, and AceDBOptions-3.0 hands every database the SAME
-- `args` table, so neither can be written to for one addon. What is one addon's alone is the group
-- AceDBOptions made for its database. So the first PaintAceTree of a page gives that group its own
-- `args` with its own `delete` row, equal to the shared one but for a `confirm` function that says
-- "this delete is ours" and answers true, which is what AceConfigDialog read from the shared row. No
-- other row moves, and the group keeps it across every redraw of the page; a client-wide table is
-- never written, and an AceDBOptions upgrade taking the shared `args` back only means the next
-- PaintAceTree does this again.
--
-- The box paints when its text is set: AceConfigDialog sets it right after that `confirm`, and
-- measures it right after, so the skin's font is the one it measures. Text set with nothing armed
-- is someone else's use of the box, which is never modal, so a box of ours still open gives itself
-- back first. Hiding gives it back too: every part, recorded by the primitives, and the registry
-- forgets them, so the box is stock when it next opens. The hooks are inert while nothing is painted.
--
-- It is part of the settings panel: nothing paints while the owner ignores its panel. A box another
-- skinning addon already took is left to it. This lives here, not in SkinAce.lua, to keep that file
-- out of layout-§1's 1000-line band; SkinAce's PaintAceTree is the one caller.

local WEAK_KEYS = { __mode = "k" }
-- `rows`: a row of ours -> its owner. `hooked`: a popup -> true. `armed`: the owner whose delete is
-- raising the box right now. `painted`: true while the box wears a skin.
lib.__aceConfirm = lib.__aceConfirm or { rows = setmetatable({}, WEAK_KEYS), hooked = setmetatable({}, WEAK_KEYS) }
local confirmBox = lib.__aceConfirm

local OTHER_SKIN_MARKS = { "isSkinned", "backdrop", "template" }

local function copyTable(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

--- The box's four painted parts, as a list, or nil when AceConfigDialog no longer builds them.
local function confirmParts(popup)
  local text, accept, cancel = P.field(popup, "text", "FontString"), rawget(popup, "accept"), rawget(popup, "cancel")
  if not (text and P.isFrame(accept) and P.isFrame(cancel)) then return nil end
  return { popup, text, accept, cancel }
end

local function takenByOtherSkin(parts)
  for _, part in ipairs(parts) do
    for _, mark in ipairs(OTHER_SKIN_MARKS) do
      if rawget(part, mark) ~= nil then return true end
    end
  end
  return false
end

local function giveConfirmBack(popup)
  confirmBox.painted = nil
  for _, part in ipairs(confirmParts(popup) or {}) do
    local rec = lib.painted[part]
    if rec then
      P.unpaint(rec, part)
      lib:Untrack(part)
    end
  end
end

--- The box for `owner`: `popup.*`, the body text, two buttons, and the client's border faded.
local function paintConfirm(owner, popup)
  local parts = confirmParts(popup)
  if not parts or takenByOtherSkin(parts) then return end
  local text, accept, cancel = parts[2], parts[3], parts[4]
  confirmBox.painted = true
  prim.Panel(owner, popup, { popup = true })
  local rec = lib.painted[popup]
  for _, child in ipairs({ popup:GetChildren() }) do
    if child ~= accept and child ~= cancel and not lib.__ours[child] then P.fade(rec, child) end
  end
  prim.Text(owner, text, "body")
  prim.Button(owner, accept)
  prim.Button(owner, cancel)
end

--- The box's text was set: paint it for an armed owner, else give back whatever it wears. Internal.
function lib.__AceConfirmRaised(popup)
  local owner = confirmBox.armed
  confirmBox.armed = nil
  if owner then return paintConfirm(owner, popup) end
  if confirmBox.painted then giveConfirmBack(popup) end
end

--- The box hid. Internal.
function lib.__AceConfirmHidden(popup)
  confirmBox.armed = nil
  if confirmBox.painted then giveConfirmBack(popup) end
end

--- A hook's body must never raise into AceConfigDialog's own code path.
local function guarded(fn, arg)
  local ok, err = pcall(fn, arg)
  if ok then return end
  local handler = type(geterrorhandler) == "function" and geterrorhandler()
  if type(handler) == "function" then handler("LibKa0s-Skin-1.0 confirm box: " .. tostring(err)) end
end

local function hookConfirm(popup, text)
  if confirmBox.hooked[popup] then return end
  confirmBox.hooked[popup] = true
  hooksecurefunc(text, "SetText", function() guarded(lib.__AceConfirmRaised, popup) end)
  popup:HookScript("OnHide", function(self) guarded(lib.__AceConfirmHidden, self) end)
end

--- `owner`'s delete is about to raise the box.
local function armConfirm(owner)
  local dialog = LibStub("AceConfigDialog-3.0", true)
  local popup = dialog and dialog.popup
  if not P.isFrame(popup) then return end
  local parts = confirmParts(popup)
  if not parts then return end
  hookConfirm(popup, parts[2])
  confirmBox.armed = lib:__PanelSkinned(owner) and owner or nil
end

--- The group holding row `user.option` when that row is AceDBOptions' delete, and its key.
local function deleteRowOf(user)
  local option, path = user.option, user.path
  if type(option) ~= "table" or option.set ~= "DeleteProfile" or type(path) ~= "table" then return nil end
  local group = user.options
  for i = 1, #path - 1 do
    group = type(group) == "table" and type(group.args) == "table" and group.args[path[i]] or nil
  end
  if type(group) ~= "table" or type(group.args) ~= "table" then return nil end
  return group, path[#path]
end

--- True when `group` is the table AceDBOptions made for one database, which nobody else reads.
local function ownGroup(group)
  local dbo = LibStub("AceDBOptions-3.0", true)
  local tables = dbo and dbo.optionTables
  local handler = group.handler
  return type(tables) == "table" and type(handler) == "table" and handler.db ~= nil
    and tables[handler.db] == group
end

--- For PaintAceTree: when `widget` is AceDBOptions' delete row on `owner`'s page, give the row's
--- group its own row that arms the box. Not while it has one, and never on a table AceDBOptions
--- did not make for one database. Internal.
function lib.__AceConfirmArm(owner, widget)
  local user = rawget(widget, "userdata")
  if type(user) ~= "table" then return end
  local group, key = deleteRowOf(user)
  if not group or key == nil then return end
  local row = group.args[key]
  if type(row) ~= "table" or confirmBox.rows[row] or not ownGroup(group) then return end
  local mine = copyTable(row)
  mine.confirm = function()
    guarded(armConfirm, owner)
    return true
  end
  local args = copyTable(group.args)
  args[key] = mine
  confirmBox.rows[mine] = owner
  group.args = args
end
