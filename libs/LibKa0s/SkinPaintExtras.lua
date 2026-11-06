-- LibKa0s-Skin-1.0 — the Ka0s paint primitives, part two: the window family's Ka0s extras
-- (TitleBar, Divider, Footer, Card, Strip, Cover, Tooltip, MenuFrame), the stock-art faders of
-- EllesmereUI's vocabulary (FadeRegions, FadeNineSlice, from SkinPaint.lua since its minor 11), the
-- text and font primitives (Text, Font, White), the bar texture (BarTexture) and the getters
-- (GetAccentColor, GetPanelColor, GetFont, GlowColor, HudTextColor, HudLabelColor, BarFillColor,
-- HudShadow, ChartStyle, BarStyle, BarBorder) and hover art (HoverArt). The HUD's two shared looks
-- (BarGloss, HudFont) are SkinPaintHud.lua's and AceConfigDialog's confirmation box SkinAceConfirm.lua's
-- from minor 19.
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

-- Minors 2 to 16, each in the Skin document's *What changed*: P.label on Footer, Card and Cover;
-- BarTexture; the faders, Panel and Inset moved here; P.panelIgnored; S.FontFlags and S.HudFontSize
-- (to minor 7); boxed popup and rail edges (8); S.Mark and S.MarkText (9); S.GetFont("mono") (10);
-- S.TitleBar's `opts.place` (11); the HUD color getters and S.HudShadow (12); S.Panel's `opts.popup`
-- and the profile delete confirmation (13); S.BarGloss and S.HudFont (14), their companion and
-- Ignore fonts (15); S.BarBorder, shadow tokens, one font object per look, S.HoverArt (16).
-- Then, still minor 16 and not yet shipped (Ka0sAddonsCommonTasks docs/2026-11-02-SMOKE_ROUND3):
-- P.holdFace, so a face shows on a string given its own SetFont first (R3-DR-1L); P.px and
-- FadeNineSlice's 1 px edge in every skin (R3-L2); P.pxWatch, which keeps a pixel edge one pixel
-- through a UI scale, display size or ancestor SetScale change (R3-FIX).
-- Minor 17 (R5-L3 of Ka0sAddonsCommonTasks docs/2026-11-03-SMOKE_ROUND5, feedback item 5): S.Band, the
-- window's title band as a frame Shell lays and keeps (EllesmereUI's 25 px bar under that source), and
-- S.Header, which anchors every header child LEFT, CENTER or RIGHT to it at y 0, the title by
-- `title.align` or the caller's `align`. S.TitleBar's `opts.place` takes the same title anchor.
-- Minor 18 (SF1-L1 of Ka0sAddonsCommonTasks docs/2026-11-06-REVENDOR_LIBKA0S_V1_89): P.px and the
-- pixel watch are Core minor 16's, shared with Widgets; P.pxEdge sizes a non-flat edge P.box draws
-- on a frame Core keeps pixel-exact in physical pixels.
-- Minor 19 (FU-L2 of Ka0sAddonsCommonTasks docs/2026-11-06-FOLLOWUPS_V1_91): the HUD's shared looks moved,
-- unchanged, to SkinPaintHud.lua, and AceConfigDialog's confirmation box to SkinAceConfirm.lua
-- (layout-§1). No member and no behavior changes.
local EXTRAS_MINOR = 19
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
P.justify = justify   -- SkinAce's AceGUI Dropdown label (R3-L1); P.unpaint gives the prior back

-- Where a placed title stands: the token's edge, in from it by what the host reserved for controls.
local TITLE_INSET = 8

--- opts.place: the bar takes `title.height`, and its text an anchor on the bar's `title.align`.
--- Justifying a string only moves it inside its own width, and a hand-anchored title has none.
-- A title on `anchor` (a bar, or the band) by `align`, at y 0: LEFT `left` px in, RIGHT `right` px in,
-- CENTER on the middle. One anchor, so a repaint leaves one.
local function anchorTitle(anchor, fs, align, left, right)
  local x = 0
  if align == "LEFT" then x = left or TITLE_INSET end
  if align == "RIGHT" then x = -(right or TITLE_INSET) end
  fs:ClearAllPoints()
  fs:SetPoint(align, anchor, align, x, 0)
end

local function place(bar, fs, T, spec)
  if T["title.height"] then bar:SetHeight(T["title.height"]) end
  local align = T["title.align"]
  if not (fs and align) then return end
  local reserve = type(spec) == "table" and spec or {}
  anchorTitle(bar, fs, align, reserve.left, reserve.right)
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

-- ── the band and the header (minor 17) ───────────────────────────────────────────────────────

-- EllesmereUI's shell bar, flush with the window's top: what a player sees as the header while
-- EllesmereUI paints the owner (Premade Groups Filter Extension measured it, modules/Panel.lua).
local EUI_BAR_H = 25
-- A header control's width when its frame answers none (before layout, or headless): Core's close.
local CONTROL_W = 18
local HEADER_PAD, HEADER_GAP = 6, 4

--- Where the band stands: in from a flat edge by `win.borderSize`, else 1, `title.height` high (the
--- top bar S.Shell paints); flush at the top and 25 high while EllesmereUI paints the owner's Shell.
local function bandGeometry(owner, frame, T)
  local route = lib.__euiRoute
  if type(route) == "function" and route(owner, "Shell") and not lib.euiRefused[owner]
    and not lib.shared[frame] then
    return 0, EUI_BAR_H
  end
  local inset = (T["win.borderStyle"] or "flat") == "flat" and T["win.borderSize"] or 1
  return type(inset) == "number" and inset or 1, T["title.height"] or 30
end

--- The record's band holder for `frame`, laid where the band stands now: an invisible child frame,
--- made once, that takes no mouse. Shell lays it on every paint, `noTopBar` or not (geometry is not
--- fill), so a child anchored to it moves with a switch and no host code.
function P.layBand(owner, rec, frame, T)
  local b = rec and rec.regions.band
  if not b then
    if not rec or type(CreateFrame) ~= "function" or not P.isFrame(frame) then return nil end
    b = CreateFrame("Frame", nil, frame)
    if type(b) ~= "table" then return nil end
    if type(b.EnableMouse) == "function" then b:EnableMouse(false) end
    lib.__ours[b] = true
    rec.regions.band = b
  end
  local inset, h = bandGeometry(owner, frame, T or P.T(owner))
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
  b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
  b:SetHeight(h)
  b:Show()
  return b
end

--- S.Band(frame): the window's title band as a frame, answered for a host to anchor its header to.
--- Recorded, so a switch (to or from the eui source too) lays it again. Draws nothing.
prim.Band = function(owner, frame)
  if type(frame) ~= "table" then return nil end
  return P.layBand(owner, P.track(owner, frame, "Band"), frame)
end

--- A header entry: a frame, or `{ frame = f, width = n, x = n }` (`x` its offset from the band's
--- edge, else chained after the one before it). Answers the frame, its width and its x or nil.
local function isWidget(o)
  local k = P.kind(o)
  return k ~= nil and k ~= "table"
end

local function entryOf(e)
  if isWidget(e) then return e, nil, nil end
  if type(e) == "table" and isWidget(e.frame) then return e.frame, e.width, e.x end
  return nil
end

local function widthOf(f, w)
  if type(w) == "number" then return w end
  local got = type(f.GetWidth) == "function" and f:GetWidth()
  return (type(got) == "number" and got > 0) and got or CONTROL_W
end

--- Anchor `list` to `band`'s `side` (LEFT or RIGHT) at y 0, the first `pad` in and each next `gap`
--- past the one before. Answers how far in from that edge the controls reach (0 with none).
local function chain(band, list, side, pad, gap)
  local off, reach = pad, 0
  for _, e in ipairs(type(list) == "table" and list or {}) do
    local f, w, x = entryOf(e)
    if f then
      off = x or off
      f:ClearAllPoints()
      f:SetPoint(side, band, side, side == "RIGHT" and -off or off, 0)
      reach = off + widthOf(f, w)
      off = reach + gap
    end
  end
  return reach
end

--- `bars` (drag strips) take the band's whole rect.
local function layBars(band, bars)
  for _, bar in ipairs(type(bars) == "table" and bars or {}) do
    if P.isFrame(bar) then bar:ClearAllPoints(); bar:SetAllPoints(band) end
  end
end

--- `spec.title` on the band by `spec.align`, else `title.align`, clear of the controls that reach
--- `left` and `right` in from its edges (`spec.inset` with none), and justified to it.
local function headerTitle(rec, band, T, spec, left, right, gap)
  local fs = spec.title
  if not P.isFS(fs) then return end
  local align = spec.align or T["title.align"] or "CENTER"
  anchorTitle(band, fs, align, left > 0 and left + gap or spec.inset, right > 0 and right + gap or spec.inset)
  justify(rec, fs, align)
end

--- S.Header(frame, spec): a window's header on its band (S.Band). `spec.right` and `spec.left` are its
--- controls, outermost first, each anchored RIGHT or LEFT to the band at y 0, `spec.pad` (6) in and
--- `spec.gap` (4) apart, an entry `{ frame, width, x }` naming its own; `spec.title` is anchored by
--- `spec.align`, else `title.align`, clear of the controls on its side (8 px with none), and justified
--- to it; `spec.bars` (drag strips) take the band's whole rect. Every child is vertically centered on
--- the band's geometric middle in every skin, and the call is recorded, so a switch places it again.
--- Geometry only: P.unpaint leaves the anchors and gives back the justification. Draws nothing.
prim.Header = function(owner, frame, spec)
  if type(frame) ~= "table" or type(spec) ~= "table" then return end
  local rec = P.track(owner, frame, "Header", spec)
  local T = P.T(owner)
  local band = P.layBand(owner, rec, frame, T)
  if not band then return end
  layBars(band, spec.bars)
  local pad, gap = spec.pad or HEADER_PAD, spec.gap or HEADER_GAP
  local right = chain(band, spec.right, "RIGHT", pad, gap)
  local left = chain(band, spec.left, "LEFT", pad, gap)
  headerTitle(rec, band, T, spec, left, right, gap)
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

--- The AceGUI widget that owns region `tex`, or nil: `opts.widget`, else the widget of the frame it is
--- a region of (every AceGUI constructor sets `frame.obj`).
local function pooledWidget(tex, opts)
  if type(opts.widget) == "table" then return opts.widget end
  local parent = type(tex.GetParent) == "function" and tex:GetParent()
  local w = type(parent) == "table" and rawget(parent, "obj")
  if type(w) == "table" and type(rawget(w, "type")) == "string" and rawget(w, "frame") ~= nil then return w end
  return nil
end

--- A pool hands an AceGUI widget to the next caller, in any addon, with this paint's record and tint
--- still on it, so release gives them back (QuickComms' ab3be75 did this by hand). Armed once per
--- acquire: a replay finds it armed. A copy with no SkinAce.lua has no OnRelease, and arms nothing.
local function giveBackOnRelease(rec, tex, opts)
  local w = pooledWidget(tex, opts)
  if not w or rec.regions.released == w or type(lib.OnRelease) ~= "function" then return end
  rec.regions.released = w
  lib:OnRelease(w, function()
    rec.regions.released = nil
    P.unpaint(rec, tex)
    lib:Untrack(tex)
    if type(opts.stock) == "function" then opts.stock(tex) end
  end)
end

--- S.Mark(tex, opts): a small mark on texture `tex` in the skin's tint. `opts.token` names the color
--- (default `icon.tint`; `sem.good` and `sem.bad` for a mark that means something), `opts.art` is the
--- Ka0s icon drawn in place of the client art `tex` wore, a path the host resolved and declared.
--- `opts.panel = true`: the mark is on the owner's settings panel, so while the owner ignores its
--- panel the tint is given back and `opts.stock(tex)` puts the client art back, a texture's art
--- being nothing P.unpaint can read. Live both ways, replayed on a skin switch. On a region of a
--- pooled AceGUI widget (minor 16) the record and the tint are given back at its release, and
--- `opts.stock` runs: nothing for a host to do. `opts.widget` names the widget where `tex` is not a
--- region of its frame. Draws no Media icon of its own.
prim.Mark = function(owner, tex, opts)
  if not P.isTexture(tex) then return end
  opts = type(opts) == "table" and opts or {}
  local rec = P.track(owner, tex, "Mark", opts)
  giveBackOnRelease(rec, tex, opts)
  if P.panelIgnored(owner, rec, tex, opts) then
    if type(opts.stock) == "function" then opts.stock(tex) end
    return
  end
  if opts.art then tex:SetTexture(opts.art) end
  P.tint(rec, tex, P.T(owner), opts.token or "icon.tint", "SetVertexColor")
end

--- S.HoverArt(tex, opts) (minor 16): hover art `tex`, an ADD highlight the client draws in its own
--- color, desaturated and tinted `list.hoverArt`; left as the client draws it where that token is
--- `false` (Ka0s Default, WoW Default). A recorded primitive, so a skin change needs no call, and
--- the public seam for the Options instance's private `O.__hoverArt`. `opts.panel` is S.Mark's: the
--- art is the client's while the owner ignores its panel. `opts.back`: give it back and forget it, for
--- a pool of the host's own; a region of an AceGUI widget does that at release, as S.Mark's does.
--- Draws no Media icon.
prim.HoverArt = function(owner, tex, opts)
  if not P.isTexture(tex) then return end
  opts = type(opts) == "table" and opts or {}
  if opts.back then
    local rec = lib.painted[tex]
    if rec then P.unpaint(rec, tex) end
    return lib:Untrack(tex)
  end
  local rec = P.track(owner, tex, "HoverArt", opts)
  giveBackOnRelease(rec, tex, opts)
  if P.panelIgnored(owner, rec, tex, opts) then return end
  P.glyph(rec, tex, P.T(owner), "list.hoverArt")
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

local function pxCore() return LibStub and LibStub("LibKa0s-Core-1.0", true) end

--- `n` physical pixels (1 by default) in the UI units of `frame`, a frame, so a 1 px edge is one
--- pixel at any UI scale (R3-L2, R3-L3): Core's `__PixelSize` since Core minor 16 (SF1-L1), the one
--- mechanism Widgets shares. `n` itself under a Core without it.
function P.px(frame, n)
  local c = pxCore()
  if c and type(c.__PixelSize) == "function" then return c.__PixelSize(frame, n) end
  return type(n) == "number" and n or 1
end

-- Pixel edges stay one pixel (R3-FIX of docs/2026-11-02-SMOKE_ROUND3): each is recorded weakly and
-- re-sized, never repainted, when Core's pixel watch fires (Core minor 16, SF1-L1): UIParent's size moves
-- (a UI scale or display size change), or a SetScale of the holder or an ancestor moves the scale
-- (DpsRace's HUD, WhatGroup's and MultiMeters' windows). Hooks, never an event.
lib.__pxSized = lib.__pxSized or setmetatable({}, { __mode = "k" })    -- target -> { h, prim, prefix, n }
local PX_SIDES = { Top = "SetHeight", Bottom = "SetHeight", Left = "SetWidth", Right = "SetWidth" }

--- Re-size every recorded pixel edge whose primitive still paints its target.
function lib:__RefreshPixels()
  for target, e in pairs(self.__pxSized) do
    local rec, regions = self.painted[target], self.__regions[target]
    if rec and regions and rec.calls and rec.calls[e.prim] then
      local size = P.px(e.h, e.n)
      for side, method in pairs(PX_SIDES) do
        local t = regions[e.prefix .. side]
        if t then t[method](t, size) end
      end
    end
  end
end

local function refreshLive()
  local live = LibStub and LibStub("LibKa0s-Skin-1.0", true)
  if live and live.__RefreshPixels then live:__RefreshPixels() end
end

--- Record `target`'s pixel edge for the refresh: primitive `name` paints it, its four regions are
--- `prefix .. side` on holder `h`, `n` physical pixels wide; Core watches `h`'s scale.
function P.pxWatch(target, h, name, prefix, n)
  lib.__pxSized[target] = { h = h, prim = name, prefix = prefix, n = n }
  local c = pxCore()
  if not (c and type(c.__WatchPixels) == "function") then return end
  c.__OnPixelScale("LibKa0s-Skin-1.0", refreshLive)
  c.__WatchPixels(h)
end

--- The size P.box draws a non-flat edge at (SF1-L1): on a frame Core keeps pixel-exact (Widgets'
--- dropdown, search box and menus) `size` physical pixels on the holder, watched; on any other
--- frame, and for a nine-slice's art, `size` as given.
function P.pxEdge(rec, frame, style, size)
  local c = pxCore()
  local pixel = c and type(c.__pxBackdrops) == "table" and c.__pxBackdrops[frame]
  if not pixel or (type(style) == "string" and style:find("^nine:")) then return size end
  local h = P.holder(rec, frame)
  if not h then return size end
  P.pxWatch(frame, h, rec.order and rec.order[1], "edge", size)
  return P.px(h, size)
end

-- FadeNineSlice's edge, four regions of its own on the holder (R3-L2): the faded art leaves the frame
-- no edge, and a dark frame vanished on a dark skin (images 85 to 87).
local RING = { Top = { "TOPLEFT", "TOPRIGHT", "SetHeight" }, Bottom = { "BOTTOMLEFT", "BOTTOMRIGHT", "SetHeight" },
               Left = { "TOPLEFT", "BOTTOMLEFT", "SetWidth" }, Right = { "TOPRIGHT", "BOTTOMRIGHT", "SetWidth" } }

--- An edge's color: the token `first` (the ring's `panel.border`, as S.Panel edges a box, image 93;
--- S.IconBorder's `icon.border`, read after `icon.outline`), else `divider`, else the body text at 0.4, so a skin that
--- sets none still draws a visible edge.
function P.edgeColor(T, first)
  local c = T[first or "panel.border"] or T["divider"]
  if c then return c end
  local b = T["text.body"]
  return type(b) == "table" and { b[1], b[2], b[3], 0.4 } or nil
end
local ringColor = P.edgeColor

--- A frame another primitive already edged (a Shell's or a Panel's edge, a backdrop a primitive
--- dressed) keeps that edge, and the ring hides, as it does under `opts.noBorder`.
local function sliceRing(rec, frame, T, opts)
  local edged = rec.regions.edgeTop or rec.regions.nine or rec.regions.backdrop
  local c = not (opts.noBorder or edged) and ringColor(T) or nil
  local h = c and P.holder(rec, frame)
  for side, a in pairs(RING) do
    local t = h and P.tex(rec, "ring" .. side, h, "BORDER")
    if t then
      t:ClearAllPoints()
      t:SetPoint(a[1], h, a[1])
      t:SetPoint(a[2], h, a[2])
      t[a[3]](t, P.px(h, 1))
      t:SetColorTexture(rgba(c))
      t:Show()
    else
      P.hide(rec, "ring" .. side)
    end
  end
  if h then P.pxWatch(frame, h, "FadeNineSlice", "ring", 1) end
end

--- S.FadeNineSlice(frame, opts): fade the nine pieces of `frame.NineSlice`, under every skin, Ka0s
--- Default included, and draw a 1 px edge in its place on the holder, one physical pixel, in
--- `panel.border` (`divider`, else the body text at 0.4, where a skin sets none), in every skin
--- (R3-L2). A frame another primitive edged keeps that edge alone, and `opts.noBorder` draws none.
prim.FadeNineSlice = function(owner, frame, opts)
  if not P.isFrame(frame) then return end
  local rec = P.track(owner, frame, "FadeNineSlice", opts)
  rec.regions.stock = true
  local ns = rawget(frame, "NineSlice")
  if P.isFrame(ns) then
    for _, k in ipairs(P.NINE_KEYS or {}) do P.fade(rec, P.field(ns, k, "Texture")) end
  end
  sliceRing(rec, frame, P.T(owner), type(opts) == "table" and opts or {})
end

-- ── text and fonts ───────────────────────────────────────────────────────────────────────────

--- Make `fs` draw `face`, `size` and `flags` after it was handed a font object that carries them. The
--- client lets a font a string was given with its own SetFont beat any font object, so a string
--- that ever had one keeps that face through SetFontObject (DpsRace's clocks under every skin, R3-DR-1
--- of Ka0sAddonsCommonTasks docs/2026-11-02-SMOKE_ROUND3). Only a string whose GetFont disagrees is
--- written, so one that never had a face of its own stays on the object alone; the shadow stays the
--- object's, the only one a 12.0.7 client draws. SkinPaint's P.font and P.unfont call it too.
function P.holdFace(fs, face, size, flags)
  if type(face) ~= "string" or type(size) ~= "number" or size <= 0 or type(fs.GetFont) ~= "function" then return end
  local f, s, fl = fs:GetFont()
  if f == face and (fl or "") == (flags or "") and type(s) == "number" and math.abs(s - size) < 0.05 then return end
  fs:SetFont(face, size, flags or "")
end

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
--- S.HudShadow(token) (minor 12, D6): the skin's HUD text shadow as x, y, r, g, b, a; `false` when the
--- skin draws none (`hud.shadow` false); nil while the owner ignores fonts, when the host's own setting
--- stands. A 12.0.7 client draws only a font object's shadow, so set these on one (SkinPaint's header).
--- `token` (minor 16), optional, names the color token to read instead, a library or owner token: an
--- owner token following `hud.shadow` gives a host its shipped shadow under Ka0s Default. A name the
--- owner cannot read is logged once and reads `hud.shadow`; one that is no color is no shadow.
prim.HudShadow = function(owner, token)
  if lib:__FontsIgnored(owner) then return nil end
  local T = P.T(owner)
  local named = token ~= nil and lib:__RemapName(owner, token, "HudShadow")
  local c = T[named and token or "hud.shadow"]
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

--- S.BarBorder(style, show, size, fromSkin) (minor 16): what a bar border draws, as style, show, size,
--- from the host's stored three and its companion. With the companion off (or a stored value that is
--- no FROM_SKIN), the stored three. Following a skin that states a real `bar.borderStyle`, the skin's
--- style and `bar.borderSize`, and show true: a real style wins over Show border. Following a skin's
--- None, the player's stored three, because None is no border of the skin's own. A stored FROM_SKIN
--- names no style, so under None it answers "None" with the stored show. Never recorded.
prim.BarBorder = function(owner, style, show, size, fromSkin)
  local follows = fromSkin == true or style == lib.FROM_SKIN
  if not follows then return style, show, size end
  local skin = lib:Token(owner, "bar.borderStyle")
  if skin ~= nil and skin ~= "None" then return skin, true, lib:Token(owner, "bar.borderSize") end
  if style == lib.FROM_SKIN then style = skin end
  return style, show, size
end
