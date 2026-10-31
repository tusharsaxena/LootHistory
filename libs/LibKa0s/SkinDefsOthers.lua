-- LibKa0s-Skin-1.0 — the eight skins other than Ka0s Default: Obsidian, Azeroth, Glass, High
-- Contrast, Ember, WoW Default, WoW Midnight and WoW Forever, translated from the mockups, with
-- FOLLOW, ICON_EDGE, HUD_FACE and `__FACE_SIZES`, each shipped face's sizes.
--
-- Peeled out of SkinDefs.lua at its minor 19, unchanged (LK-M2-PEEL of Ka0sAddonsCommonTasks
-- docs/2026-10-31-FINDINGS_REMEDIATION), on the seam CLAUDE.md's band census named for that file. A
-- token still lands here as one value or `FOLLOW` per skin, so this file grows with the vocabulary,
-- not with logic. The history is SkinDefs.lua's header.
--
-- It reads Ka0s Default's table off the registered skin, and nothing else crosses the cut. A payload
-- without this file offers Ka0s Default alone, and a face override draws unscaled.
--
-- A file of `LibKa0s-Skin-1.0`, paired on the shell's minor as SkinDefs.lua is, and it attaches only
-- when SkinDefs.lua attached to the same shell.

local lib = LibStub and LibStub("LibKa0s-Skin-1.0", true)
if not lib then return end   -- the shell refused (no Core, or below its floor): nothing to attach to
if lib.__defsShellMinor ~= lib.MINOR or not lib.skins.ka0s then return end   -- no schema from this copy

-- Minor 1: the eight other skins, moved here unchanged from SkinDefs.lua (its minor 19).
local OTHERS_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own: see SkinDefs.lua.
if lib.__othersMinor and lib.__othersMinor >= OTHERS_MINOR
  and lib.__othersShellMinor == lib.MINOR then return end
lib.__othersMinor      = OTHERS_MINOR
lib.__othersShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.SkinDefsOthers = OTHERS_MINOR

local KA0S = lib.skins.ka0s.tokens

-- ── the eight other skins ────────────────────────────────────────────────────────────────────
--
-- TRANSLATED FROM THE MOCKUPS, Ka0sAddonsCommonTasks docs/2026-10-25-SKINNING/inputs/
-- mockup-tokens.dc.html (saved here under docs/skins/). Each skin's `mock` table is that skin's
-- entry in the mockup's SKINS, key for key, with CSS turned into Lua: a hex or rgba() into a color,
-- `transparent` into CLEAR, `linear-gradient(a, b)` into grad(a, b), a `<n>px <style> <color>` edge
-- into edge(n, style, color), a font family into the LSM key of the shipped face that stands for
-- it. The mockup's skin keys map `classic` -> `ka0s` and `wowdefault` -> `wow`; its `eui` entry
-- is only the EllesmereUI preview and is never registered. A key the mockup's skin leaves out
-- inherits Ka0s Default's Lua value (never the mockup's BASE), and so does every token MOCK_MAP
-- does not reach. `extra` names the tokens the mockup does not draw that a skin still sets so its
-- surfaces read (cards, drawers opened, disabled text, light-skin charts, a set drawer label the
-- mockup draws in its body color, which would hide OptionsDrawer's set / unset cue); each is a
-- schema name.
--
-- WHAT WOW CANNOT DRAW is approximated (docs/api/Skin, "The eight skins"): no blur (Glass is
-- translucency on its rounded art); no CSS radius but the one rounded art shipped, Ka0s Glass at 8,
-- so every other radius is square; a radial gradient is a vertical one; a CSS ridge / outset /
-- inset / groove edge is WoW Default's Blizzard dialog art or a two-tone bevel (`bevelOut`,
-- `bevelIn`). The mockup's scrollbar widths (`scW`) are not translated: geometry is Ka0s Default's
-- in every skin in leg 1.

local CLEAR = { 0, 0, 0, 0 }

--- "#rrggbb" (and an alpha) as a color.
local function hex(s, a)
  local r, g, b = s:match("^#(%x%x)(%x%x)(%x%x)$")
  return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, a or 1 }
end

--- CSS rgba(), 0-255 channels.
local function rgba(r, g, b, a) return { r / 255, g / 255, b / 255, a or 1 } end

--- A vertical gradient, top to bottom (CSS linear-gradient's default direction).
local function grad(top, bottom) return { top = top, bottom = bottom } end

--- A control edge: its size, its style (flat | bevelOut | bevelIn | nine:<LSM border key>), its
--- color (the art's vertex color for a nine-slice).
local function edge(size, style, color) return { size = size, style = style, color = color } end

-- Mockup key -> the schema tokens it draws, in order; a later row overrides an earlier one (the
-- mockup's headColor over titleColor, its drawer label over the accent). `edge` rows write the
-- control's border, borderSize and borderStyle; `edgeColor` rows write one color token from an edge.
local MOCK_MAP = {
  { "font", "font.body" }, { "tfont", "font.title" }, { "fs", "font.bodySize" },
  { "titleSize", "font.titleSize" },
  { "win", "win.bg", "win.bgDense" }, { "winBorder", edge = "win" }, { "winInner", "win.inner" },
  { "radius", "win.radius" },
  { "titleBg", "title.bg" }, { "titleColor", "title.text", "text.heading", "text.headingAlt" },
  { "headColor", "text.heading", "text.headingAlt" }, { "titleAlign", "title.align" },
  { "divider", "divider", "tab.rule" }, { "footBg", "foot.bg" },
  { "text", "text.body", "menu.text", "drawer.text" },
  { "muted", "text.muted", "icon.tint", "drawer.summary", "handle.rest" },
  { "accent", "text.accent", "text.link", "btn.hover", "input.focus", "menu.textSel",
    "drawer.textSet", "icon.hot" },
  { "closeColor", "close.rest" },
  { "btnBg", "btn.bg" }, { "btnBorder", edge = "btn" }, { "btnText", "btn.text", "btn.icon" },
  { "btnRadius", "btn.radius" },
  { "priBg", "btnPrimary.bg" }, { "priBorder", edge = "btnPrimary" },
  { "priText", "btnPrimary.text", "btnPrimary.icon", "btnPrimary.hover" },
  { "btnRadius", "btnPrimary.radius" },
  { "inBg", "input.bg" }, { "inBorder", edge = "input" }, { "inRadius", "input.radius" },
  { "inText", "input.text" }, { "inPh", "input.placeholder" },
  { "hdrBg", "list.header.bg" }, { "hdrText", "list.header.text" }, { "rowAlt", "list.stripe" },
  { "rowSel", "list.sel" }, { "rowSelOutline", "list.selOutline" },
  { "tabBg", "tab.bg" }, { "tabText", "tab.text" }, { "tabBorder", edge = "tab" },
  { "tabRadius", "tab.radius" }, { "tabOnBg", "tab.onBg" }, { "tabOnText", "tab.onText" },
  { "tabOnLine", "tab.onLine" },
  { "scTrack", "scroll.track" }, { "scThumb", "scroll.thumb", "scroll.thumbOff" },
  { "scRadius", "scroll.radius" },
  { "chkBg", "check.bg" }, { "chkBorder", edge = "check" }, { "chkMark", "check.mark" },
  { "chkRadius", "check.radius" },
  { "slTrack", "slider.track" }, { "slTrackBorder", edgeColor = "slider.trackBorder" },
  { "slFill", "slider.fill" }, { "slThumb", "slider.thumb" },
  { "navBg", "nav.bg" }, { "navBorder", edge = "nav" }, { "navText", "nav.text" },
  { "navSelBg", "nav.selBg" }, { "navSelText", "nav.selText" }, { "navSelBar", "nav.selBar" },
  { "drawerBg", "drawer.bg" }, { "drawerBorder", edge = "drawer" },
  { "drawerBorder", edgeColor = "drawer.boxBorder" }, { "drawerText", "drawer.textSet" },
  { "popBg", "popup.bg", "menu.bg", "list.ghostBg" }, { "popBorder", edge = "popup" }, { "popBorder", edge = "menu" },
  { "popBorder", edgeColor = "menu.borderAlt" }, { "popRadius", "popup.radius" },
  { "tipBg", "tooltip.bg" }, { "tipBorder", edgeColor = "tooltip.border" },
  { "tipLevel", "gtip.title" }, { "tipText", "gtip.body" }, { "tipMuted", "gtip.muted" },
  { "qEpic", "q.epic" }, { "qRare", "q.rare" }, { "qUnc", "q.uncommon" },
  { "gloss", "bar.gloss" }, { "barTex", "bar.texture" },
}

-- The accent at a fixed alpha: the hover and rule washes Ka0s Default draws in gold.
local ACCENT_WASH = {
  { "menu.hover", 0.15 }, { "section.rule", 0.35 },
  { "drawer.borderOpen", 0.6 }, { "handle.edge", 0.6 }, { "list.dropLine", 0.9 },
}

-- The body text at a fixed alpha: the reorder list's row boxes, which Ka0s Default draws in white.
local TEXT_WASH = {
  { "list.hover", 0.10 }, { "list.box", 0.06 }, { "list.boxDim", 0.03 }, { "list.boxEdge", 0.12 }, { "list.boxEdgeDim", 0.06 },
}

-- Tokens that follow another token the skin set (minor 4): a skin that sets the source and not the
-- follower gets the source's value, so its tool windows read in its own text, accent, disabled and
-- semantic colors; a skin that sets neither keeps Ka0s Default's constant.
local FOLLOW = {
  { "log.text", "text.body" }, { "log.count", "text.muted" }, { "text.faint", "text.muted" },
  { "log.ts", "sem.info" }, { "log.tag", "text.headingAlt" },
  { "sem.stepReady", "text.body" }, { "sem.stepBusy", "text.accent" },
  { "sem.stepLocked", "text.disabled" }, { "sem.stepCancel", "sem.off" }, { "sem.stepCancelHot", "sem.bad" },
  { "icon.arrow", "text.accent" }, { "gtip.footer", "gtip.muted" },
  { "icon.grip", "icon.tint" }, { "list.hoverArt", "text.accent" },
}

local function blend(a, b)
  return { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2, ((a[4] or 1) + (b[4] or 1)) / 2 }
end

--- Write one value. A gradient writes its two stops to `<stem>.bgTop` / `<stem>.bgBottom` where
--- the schema has them, and their blend to the flat token; a flat fill clears the stops Ka0s
--- Default sets (`false`), so its tab gradient never shows through another skin's flat tabs.
local function put(out, name, v)
  local stem = name:match("^(.+)%.bg$")
  local top = stem and stem .. ".bgTop"
  if type(v) == "table" and v.top then
    out[name] = blend(v.top, v.bottom)
    if top and lib.__schemaIndex[top] then out[top], out[stem .. ".bgBottom"] = v.top, v.bottom end
    return
  end
  out[name] = v
  if top and KA0S[top] ~= nil then out[top], out[stem .. ".bgBottom"] = false, false end
end

local function putRow(out, row, v)
  if row.edge then
    out[row.edge .. ".border"] = v.color
    out[row.edge .. ".borderSize"] = v.size
    out[row.edge .. ".borderStyle"] = v.style
  elseif row.edgeColor then
    out[row.edgeColor] = v.color
  else
    for i = 2, #row do put(out, row[i], v) end
  end
end

-- What every other skin inherited from Ka0s Default before minor 14 gave it Oxanium and the Ka0s
-- Default bar: Friz Quadrata and the client's Blizzard bar. A skin that sets its own keeps that; WoW
-- Default is the one skin that sets no face and no bar, so these are its. The face is the shipped
-- Friz since minor 18, since a client's own file need not be Friz at all (D-01). The HUD face left
-- KEEP in minor 16: every skin names its own (HUD_FACE below).
local FRIZ = "Ka0s Friz Quadrata TT"
local KEEP = { ["font.body"] = FRIZ, ["font.title"] = FRIZ, ["bar.texture"] = "Blizzard" }

--- A skin's tokens: its mockup entry through MOCK_MAP, the accent and text washes, then its extras.
local function translate(mock, extra)
  local out = {}
  for _, row in ipairs(MOCK_MAP) do
    local v = mock[row[1]]
    if v ~= nil then putRow(out, row, v) end
  end
  for _, pair in ipairs({ { mock.accent, ACCENT_WASH }, { mock.text, TEXT_WASH } }) do
    local c = pair[1]
    for _, w in ipairs(c and pair[2] or {}) do out[w[1]] = { c[1], c[2], c[3], w[2] } end
  end
  for name, v in pairs(extra or {}) do put(out, name, v) end
  for _, f in ipairs(FOLLOW) do
    if out[f[1]] == nil and out[f[2]] ~= nil then out[f[1]] = out[f[2]] end
  end
  for name, v in pairs(KEEP) do
    if out[name] == nil then out[name] = v end
  end
  return out
end

-- Each skin's icon border (minor 15), a style and a size of its own: a flat edge as thin as the
-- skin's own control edges (1px where its edges are hairlines, 2px where they are heavier), and WoW
-- Default the client's tooltip edge, its one Blizzard-art skin. The mockups draw no icon border, so
-- none comes through MOCK_MAP; a skin's `extra` may still override.
local ICON_EDGE = {
  obsidian = { "Solid", 1 }, azeroth = { "Solid", 2 }, glass = { "Solid", 1 }, contrast = { "Solid", 2 },
  ember = { "Solid", 2 }, wow = { "Blizzard Tooltip", 2 }, midnight = { "Solid", 2 }, forever = { "Solid", 1 },
}

-- Each skin's HUD face (minor 16, R-4): its own family, a weight heavy enough that its strokes do
-- not close up under an OUTLINE; since minor 18 the weight the owner picked for the skin (D-06), a
-- Semibold or a single-weight face, Fira Sans SemiBold over WoW Forever's Medium staying. WoW Default's
-- is named here rather than left to a fallback. A skin's `extra` may still override. Ka0s Default's
-- is its token above (Prototype, minor 17).
local HUD_FACE = {
  obsidian = "Ka0s Expressway", azeroth = "Ka0s Open Sans Semibold", glass = "Ka0s Avant Garde",
  contrast = "Ka0s Doris PP", ember = "Ka0s Emblem", wow = FRIZ,
  midnight = "Ka0s Segoe UI Semibold", forever = "Ka0s Fira Sans SemiBold",
}

-- Each skin's HUD size (minor 17, LK-06, D-09): the `hud.fontSize` that gives its HUD face Ka0s
-- Default's width at 12, measured as the body and title sizes are (tests/test_skin_width_parity.lua).
-- A reference, not a size: S.HudFontSize draws a stored 24 at 24 * HUD_SIZE / 12.
local HUD_SIZE = {
  obsidian = 13, azeroth = 11, glass = 11, contrast = 10.5, ember = 11, wow = 11, midnight = 11.5, forever = 11.5,
}

-- Every shipped face's sizes at Ka0s Default's width (minor 18, D-07): { body, title, HUD }, as
-- `font.bodySize`, `font.titleSize` and `hud.fontSize` would state them, the reference being
-- Prototype's row. Skin.lua's withOverrides lays a row over the sizes of an owner whose font override
-- names the face, and a face with no row, which no client can measure, draws unscaled at Ka0s
-- Default's sizes, since the skin's are tuned for the skin's own face.
-- Measured by Ka0sAddonsCommonTasks docs/2026-10-31-FONT_PICKERS_AND_SKIN_FACES/plan-data/
-- font_metrics_shipped.py, its section 10, and held to lib.FONTS and to each
-- skin's own sizes by tests/test_skin_width_parity.lua. JetBrains Mono is the small one, monospace
-- being wide.
lib.__FACE_SIZES = {
  ["JetBrains Mono"]           = { 9, 11, 9.5 },
  ["Ka0s Atkinson"]            = { 12, 14, 12 },
  ["Ka0s Atkinson Bold"]       = { 11, 13, 11 },
  ["Ka0s Avant Garde"]         = { 11, 13, 11 },
  ["Ka0s Bitter"]              = { 11.5, 13, 11.5 },
  ["Ka0s Bitter Bold"]         = { 11, 12.5, 11 },
  ["Ka0s Doris PP"]            = { 10.5, 12.5, 10.5 },
  ["Ka0s Emblem"]              = { 11, 12.5, 11 },
  ["Ka0s Expressway"]          = { 12.5, 14.5, 13 },
  ["Ka0s Fira Sans"]           = { 12, 13.5, 12 },
  ["Ka0s Fira Sans Medium"]    = { 12, 13.5, 11.5 },
  ["Ka0s Fira Sans SemiBold"]  = { 11.5, 13.5, 11.5 },
  ["Ka0s Friz Quadrata TT"]    = { 11, 13, 11 },
  ["Ka0s Inter"]               = { 11, 13, 11 },
  ["Ka0s Inter SemiBold"]      = { 11, 12.5, 10.5 },
  ["Ka0s Nunito"]              = { 11.5, 13.5, 11.5 },
  ["Ka0s Nunito SemiBold"]     = { 11.5, 13, 11 },
  ["Ka0s Open Sans"]           = { 11.5, 13, 11.5 },
  ["Ka0s Open Sans Bold"]      = { 10.5, 12, 10.5 },
  ["Ka0s Open Sans Condensed"] = { 13.5, 16, 13.5 },
  ["Ka0s Open Sans Light"]     = { 12, 13.5, 11.5 },
  ["Ka0s Open Sans Semibold"]  = { 11, 12.5, 11 },
  ["Ka0s Oxanium Bold"]        = { 11, 13, 11 },
  ["Ka0s Oxanium SemiBold"]    = { 11.5, 13, 11 },
  ["Ka0s Philosopher"]         = { 12.5, 14, 12.5 },
  ["Ka0s Philosopher Bold"]    = { 12, 13.5, 12 },
  ["Ka0s Prototype"]           = { 12, 14, 12 },
  ["Ka0s Segoe UI"]            = { 12, 14, 12 },
  ["Ka0s Segoe UI Bold"]       = { 11, 13, 11 },
  ["Ka0s Segoe UI Light"]      = { 12.5, 14.5, 12.5 },
  ["Ka0s Segoe UI Semibold"]   = { 11.5, 13.5, 11.5 },
  ["Ka0s Vollkorn"]            = { 12, 14, 12 },
  ["Ka0s Vollkorn Bold"]       = { 11.5, 12.5, 11 },
}

local function register(key, label, desc, swatches, mock, extra)
  local tokens = translate(mock, extra)
  if tokens["hud.font"] == nil then tokens["hud.font"] = HUD_FACE[key] end
  if tokens["hud.fontSize"] == nil then tokens["hud.fontSize"] = HUD_SIZE[key] end
  local icon = ICON_EDGE[key]
  if icon and tokens["icon.borderStyle"] == nil then tokens["icon.borderStyle"] = icon[1] end
  if icon and tokens["icon.borderSize"] == nil then tokens["icon.borderSize"] = icon[2] end
  lib:RegisterSkin({ key = key, label = label, desc = desc, swatches = swatches, tokens = tokens })
end

-- ── Obsidian ── mockup `obsidian`. Expressway, the owner's pick (minor 17, LK-A1; Inter, the
-- mockup's own face, from minor 11, Barlow before).
register("obsidian", "Obsidian", "True black and flat, hairline edges, one cool blue accent.",
  { "#0a0a0b", "#202024", "#141416", "#4db8ff" }, {
    font = "Ka0s Expressway", tfont = "Ka0s Expressway", fs = 12.5, titleSize = 14.5,
    barTex = "Ka0s Matte",
    win = hex("#0A0A0B"), winBorder = edge(1, "flat", hex("#202024")), winInner = false, radius = 0,
    titleBg = hex("#050506"), titleColor = hex("#2A86D1"), divider = hex("#1c1c20"),
    headColor = hex("#F2F2F4"),
    text = hex("#E8E8EC"), muted = hex("#9B9BA4"), accent = hex("#4DB8FF"),
    closeColor = hex("#9B9BA4"),
    btnBg = hex("#141416"), btnBorder = edge(1, "flat", hex("#2a2a30")), btnText = hex("#E8E8EC"),
    btnRadius = 0,
    priBg = hex("#2A86D1"), priBorder = edge(1, "flat", hex("#4DB8FF")), priText = hex("#FFFFFF"),
    inBg = hex("#040405"), inBorder = edge(1, "flat", hex("#26262b")), inRadius = 0,
    inText = hex("#E8E8EC"), inPh = hex("#8A8A93"),
    hdrBg = hex("#101012"), hdrText = hex("#9B9BA4"), rowAlt = rgba(255, 255, 255, 0.02),
    rowSel = rgba(77, 184, 255, 0.14),
    tabBg = CLEAR, tabText = hex("#9B9BA4"), tabBorder = edge(1, "flat", CLEAR), tabRadius = 0,
    tabOnBg = CLEAR, tabOnText = hex("#F2F2F4"), tabOnLine = hex("#4DB8FF"),
    scTrack = hex("#1c1c20"), scThumb = rgba(77, 184, 255, 0.9), scRadius = 0,
    chkBg = hex("#040405"), chkBorder = edge(1, "flat", hex("#34343b")), chkMark = hex("#4DB8FF"),
    chkRadius = 0,
    slTrack = hex("#202024"), slTrackBorder = edge(0, "flat", CLEAR), slFill = hex("#4DB8FF"),
    slThumb = hex("#F2F2F4"),
    navBg = CLEAR, navBorder = edge(1, "flat", CLEAR), navText = hex("#9B9BA4"),
    navSelBg = rgba(255, 255, 255, 0.06), navSelText = hex("#F2F2F4"), navSelBar = hex("#4DB8FF"),
    drawerBg = hex("#101012"), drawerBorder = edge(1, "flat", hex("#202024")),
    drawerText = hex("#E8E8EC"),
    popBg = hex("#0A0A0B"), popBorder = edge(1, "flat", hex("#2c2c32")), popRadius = 0,
    tipBg = hex("#070708"), tipBorder = edge(1, "flat", hex("#2c2c32")), tipMuted = hex("#9B9BA4"),
    footBg = hex("#050506"), gloss = false,
  }, {
    ["text.disabled"] = hex("#6A6A72"), ["text.linkHot"] = hex("#8FD3FF"),
    ["drawer.bgOpen"] = hex("#141416"), ["drawer.boxBg"] = hex("#0A0A0B"),
    ["drawer.summarySet"] = hex("#A8DBFF"), ["btnPrimary.hover"] = hex("#D6EEFF"),
    ["drawer.textSet"] = hex("#4DB8FF"),
    ["card.bg"] = hex("#101012"), ["card.border"] = hex("#202024"),
    ["panel.bg"] = hex("#070708"), ["panel.border"] = hex("#1c1c20"),
    ["scroll.thumbOn"] = rgba(77, 184, 255, 0.9), ["scroll.thumbOff"] = hex("#3a3a42"),
    ["tab.glow"] = rgba(255, 255, 255, 0.06),
  })

-- ── Azeroth ── mockup `azeroth`, reworked dark (SkinDefs minor 8, the owner's ruling of 2026-10-26:
-- "the light background is not going to work"). Dark tooled leather under a leather edge and a gold
-- inner rule, parchment text, gold headings and accent, Open Sans Semibold under Open Sans Bold titles
-- (minor 18, D-06; Vollkorn from minor 11, Cinzel titles over an Atkinson body until then); leather buttons, and
-- the red wax seal kept for the primary button and the selected tab. As a dark skin it inherits Ka0s
-- Default's semantic, quality, tooltip and chart colors.
local AZ_LEATHER, AZ_EDGE, AZ_GOLD = hex("#2B1D12"), hex("#6b4a22"), hex("#E2B659")
local AZ_TEXT, AZ_WAX = hex("#E9DDBC"), grad(hex("#a3241a"), hex("#5e1009"))
register("azeroth", "Azeroth", "Dark tooled leather, parchment text, gold and a red wax seal, Open Sans type.",
  { "#2b1d12", "#6b4a22", "#e2b659", "#8e1b10" }, {
    font = "Ka0s Open Sans Semibold", fs = 11, tfont = "Ka0s Open Sans Bold", titleSize = 12,
    barTex = "Ka0s Parchment",
    win = AZ_LEATHER, winBorder = edge(1, "flat", AZ_EDGE), winInner = hex("#8a6a36"), radius = 0,
    titleBg = hex("#1a110a"), titleColor = hex("#F5C542"), divider = AZ_EDGE,
    text = AZ_TEXT, muted = hex("#B8A07A"), accent = AZ_GOLD, closeColor = hex("#F5C542"),
    btnBg = grad(hex("#5a3d1d"), hex("#3a2614")), btnBorder = edge(1, "flat", hex("#24160a")),
    btnText = hex("#F2E3BD"), btnRadius = 0,
    priBg = AZ_WAX, priBorder = edge(1, "flat", AZ_GOLD), priText = hex("#FFD866"),
    inBg = hex("#1c130b"), inBorder = edge(1, "flat", AZ_EDGE), inRadius = 0, inText = AZ_TEXT,
    inPh = hex("#8E7A58"),
    hdrBg = hex("#3a2614"), hdrText = AZ_GOLD, rowAlt = rgba(233, 221, 188, 0.04),
    rowSel = rgba(163, 36, 26, 0.35),
    tabBg = hex("#3a2614"), tabText = hex("#CDB78A"), tabBorder = edge(1, "flat", hex("#24160a")),
    tabRadius = 0, tabOnBg = hex("#7a1a10"), tabOnText = hex("#FFD866"), tabOnLine = CLEAR,
    scTrack = rgba(0, 0, 0, 0.35), scThumb = hex("#8a6a36"), scRadius = 0,
    chkBg = hex("#1c130b"), chkBorder = edge(1, "flat", hex("#8a6a36")), chkMark = AZ_GOLD,
    chkRadius = 0,
    slTrack = hex("#5a3d1d"), slTrackBorder = edge(0, "flat", CLEAR), slFill = hex("#c0392b"),
    slThumb = AZ_GOLD,
    navBg = rgba(0, 0, 0, 0.25), navBorder = edge(1, "flat", AZ_EDGE), navText = AZ_GOLD,
    navSelBg = hex("#7a1a10"), navSelText = hex("#FFE7A8"), navSelBar = CLEAR,
    drawerBg = hex("#3a2614"), drawerBorder = edge(1, "flat", AZ_EDGE), drawerText = AZ_TEXT,
    popBg = AZ_LEATHER, popBorder = edge(2, "flat", AZ_EDGE), popRadius = 0,
    tipBg = hex("#1c130b"), tipBorder = edge(2, "flat", AZ_EDGE), tipText = AZ_TEXT,
    tipLevel = hex("#F5C542"), tipMuted = hex("#B8A07A"),
    footBg = hex("#1a110a"),
  }, {
    ["text.heading"] = AZ_GOLD, ["text.headingAlt"] = hex("#D4A84A"),
    ["text.disabled"] = hex("#8A7A60"), ["text.linkHot"] = hex("#FFD866"),
    ["btn.hover"] = hex("#FFFFFF"), ["btnPrimary.hover"] = hex("#FFFFFF"), ["close.hot"] = hex("#FF6B4A"),
    ["drawer.bgOpen"] = hex("#4a3018"), ["drawer.boxBg"] = hex("#1c130b"),
    ["drawer.summarySet"] = AZ_GOLD, ["drawer.textSet"] = AZ_GOLD,
    ["card.bg"] = hex("#3a2614"), ["card.border"] = AZ_EDGE,
    ["panel.bg"] = rgba(0, 0, 0, 0.2), ["panel.border"] = AZ_EDGE,
    ["scroll.thumbOn"] = hex("#8a6a36"), ["tab.glow"] = rgba(255, 255, 255, 0.10),
  })

-- ── Glass ── mockup `glass`. Manrope in the mockup; Avant Garde, the owner's pick, stands for it
-- (minor 18, D-06; Nunito from minor 11, Barlow before). No blur in WoW: the window is translucent on the shipped Ka0s Glass
-- art (radius 8), the one rounded skin. Minor 7 (the
-- owner's 2026-10-26 notes): denser glass (.88), and only the window and its popups keep the rounded
-- art; buttons, inputs, tabs and drawers take a flat 1px frosted edge, and the tabs Obsidian's
-- boxless underline in lilac.
local GLASS_EDGE = rgba(255, 255, 255, 0.18)
register("glass", "Glass", "Translucent frosted panels with rounded corners and a lilac accent.",
  { "#121622", "#ffffff", "#b69cff", "#5aa9ff" }, {
    font = "Ka0s Avant Garde", tfont = "Ka0s Avant Garde", fs = 11, titleSize = 13,
    barTex = "Ka0s Glass Bar",
    win = rgba(18, 22, 34, 0.88), winBorder = edge(8, "nine:Ka0s Glass", GLASS_EDGE),
    winInner = false, radius = 8,
    titleBg = rgba(255, 255, 255, 0.06), titleColor = hex("#FFFFFF"),
    divider = rgba(255, 255, 255, 0.12),
    text = hex("#F2F4F8"), muted = hex("#C9CFDB"), accent = hex("#B69CFF"),
    closeColor = hex("#C9CFDB"),
    btnBg = rgba(255, 255, 255, 0.08), btnBorder = edge(1, "flat", rgba(255, 255, 255, 0.22)),
    btnText = hex("#F2F4F8"), btnRadius = 0,
    priBg = hex("#B69CFF"), priBorder = edge(1, "flat", hex("#B69CFF")),
    priText = hex("#1A1033"),
    inBg = rgba(0, 0, 0, 0.30), inBorder = edge(1, "flat", rgba(255, 255, 255, 0.18)),
    inRadius = 0, inText = hex("#F2F4F8"), inPh = hex("#B8BFCC"),
    hdrBg = rgba(255, 255, 255, 0.06), hdrText = hex("#C9CFDB"), rowAlt = rgba(255, 255, 255, 0.03),
    rowSel = rgba(182, 156, 255, 0.24),
    tabBg = CLEAR, tabText = hex("#C9CFDB"), tabBorder = edge(1, "flat", CLEAR), tabRadius = 0,
    tabOnBg = rgba(182, 156, 255, 0.10), tabOnText = hex("#FFFFFF"), tabOnLine = hex("#B69CFF"),
    scTrack = rgba(255, 255, 255, 0.08), scThumb = rgba(255, 255, 255, 0.5), scRadius = 0,
    chkBg = rgba(0, 0, 0, 0.3), chkBorder = edge(1, "flat", rgba(255, 255, 255, 0.3)),
    chkMark = hex("#B69CFF"), chkRadius = 0,
    slTrack = rgba(255, 255, 255, 0.15), slTrackBorder = edge(0, "flat", CLEAR),
    slFill = hex("#B69CFF"), slThumb = hex("#FFFFFF"),
    navBg = CLEAR, navBorder = edge(1, "flat", CLEAR), navText = hex("#C9CFDB"),
    navSelBg = rgba(255, 255, 255, 0.12), navSelText = hex("#FFFFFF"), navSelBar = CLEAR,
    drawerBg = rgba(255, 255, 255, 0.05),
    drawerBorder = edge(1, "flat", rgba(255, 255, 255, 0.14)),
    drawerText = hex("#F2F4F8"),
    popBg = rgba(18, 22, 34, 0.92), popBorder = edge(8, "nine:Ka0s Glass", GLASS_EDGE),
    popRadius = 8,
    tipBg = rgba(15, 18, 28, 0.92), tipBorder = edge(1, "flat", GLASS_EDGE),
    tipMuted = hex("#C9CFDB"),
    qEpic = hex("#C58BFF"), qRare = hex("#5AA9FF"), qUnc = hex("#5CFF5C"),
    footBg = rgba(255, 255, 255, 0.04), gloss = true,
  }, {
    ["text.disabled"] = hex("#8A90A0"), ["text.linkHot"] = hex("#D4C4FF"),
    ["btnPrimary.hover"] = hex("#3A2A66"),
    ["drawer.bgOpen"] = rgba(255, 255, 255, 0.09), ["drawer.boxBg"] = rgba(0, 0, 0, 0.2),
    ["drawer.summarySet"] = hex("#D4C4FF"), ["drawer.textSet"] = hex("#B69CFF"),
    ["card.bg"] = rgba(255, 255, 255, 0.06), ["card.border"] = rgba(255, 255, 255, 0.14),
    ["panel.bg"] = rgba(255, 255, 255, 0.04), ["panel.border"] = rgba(255, 255, 255, 0.12),
    ["scroll.thumbOn"] = rgba(255, 255, 255, 0.6), ["scroll.thumbOff"] = rgba(255, 255, 255, 0.25),
    ["icon.hot"] = hex("#FFFFFF"),
  })

-- ── High Contrast ── mockup `contrast`: black, white 2px edges, yellow focus, Doris PP (minor 18,
-- D-06; Atkinson Hyperlegible until then), as wide as Ka0s Default's text (minor 17, LK-05; a point
-- and a half larger until then). Minor 7 (the owner's 2026-10-26 notes:
-- "borders are too thick"): every control edge is 1px; the window keeps its 2px edge and the popups
-- drop from 3px to 2px.
local HC_WHITE, HC_YELLOW = hex("#FFFFFF"), hex("#FFE600")
register("contrast", "High Contrast", "Black and white with yellow focus, crisp 1px edges.",
  { "#000000", "#ffffff", "#1a1a1a", "#ffe600" }, {
    font = "Ka0s Doris PP", tfont = "Ka0s Doris PP", fs = 10.5, titleSize = 12.5,
    barTex = "Ka0s Solid",
    win = hex("#000000"), winBorder = edge(2, "flat", HC_WHITE), winInner = false, radius = 0,
    titleBg = hex("#000000"), titleColor = HC_YELLOW, divider = HC_WHITE,
    text = HC_WHITE, muted = hex("#E0E0E0"), accent = HC_YELLOW, closeColor = HC_WHITE,
    btnBg = hex("#000000"), btnBorder = edge(1, "flat", HC_WHITE), btnText = HC_WHITE,
    btnRadius = 0,
    priBg = hex("#000000"), priBorder = edge(1, "flat", HC_YELLOW), priText = HC_YELLOW,
    inBg = hex("#000000"), inBorder = edge(1, "flat", HC_WHITE), inRadius = 0, inText = HC_WHITE,
    inPh = hex("#D0D0D0"),
    hdrBg = hex("#1a1a1a"), hdrText = HC_YELLOW, rowAlt = hex("#0d0d0d"), rowSel = hex("#000000"),
    rowSelOutline = HC_YELLOW,
    tabBg = hex("#000000"), tabText = HC_WHITE, tabBorder = edge(1, "flat", HC_WHITE),
    tabRadius = 0, tabOnBg = hex("#000000"), tabOnText = HC_YELLOW, tabOnLine = HC_YELLOW,
    scTrack = hex("#262626"), scThumb = HC_WHITE, scRadius = 0,
    chkBg = hex("#000000"), chkBorder = edge(1, "flat", HC_WHITE), chkMark = HC_YELLOW,
    chkRadius = 0,
    slTrack = hex("#FFFFFF"), slTrackBorder = edge(0, "flat", CLEAR), slFill = HC_YELLOW,
    slThumb = HC_WHITE,
    navBg = hex("#000000"), navBorder = edge(1, "flat", HC_WHITE), navText = HC_WHITE,
    navSelBg = HC_YELLOW, navSelText = hex("#000000"), navSelBar = CLEAR,
    drawerBg = hex("#000000"), drawerBorder = edge(1, "flat", HC_WHITE), drawerText = HC_YELLOW,
    popBg = hex("#000000"), popBorder = edge(2, "flat", HC_YELLOW), popRadius = 0,
    tipBg = hex("#000000"), tipBorder = edge(1, "flat", HC_WHITE), tipLevel = HC_YELLOW,
    tipMuted = hex("#E0E0E0"),
    qEpic = hex("#D199FF"), qRare = hex("#6DB6FF"), qUnc = hex("#5CFF5C"),
    footBg = hex("#000000"), gloss = false,
  }, {
    ["text.disabled"] = hex("#B0B0B0"), ["text.linkHot"] = HC_WHITE, ["btnPrimary.hover"] = HC_WHITE, ["close.hot"] = hex("#FF5050"),
    ["gtip.body"] = HC_WHITE,
    ["drawer.bgOpen"] = hex("#000000"), ["drawer.boxBg"] = hex("#000000"),
    ["drawer.borderOpen"] = HC_YELLOW, ["drawer.summarySet"] = HC_YELLOW,
    ["card.bg"] = hex("#000000"), ["card.border"] = HC_WHITE,
    ["panel.bg"] = hex("#000000"), ["panel.border"] = HC_WHITE, ["section.rule"] = HC_YELLOW,
    ["list.hover"] = rgba(255, 230, 0, 0.2), ["menu.hover"] = rgba(255, 230, 0, 0.25),
    ["scroll.thumbOn"] = HC_WHITE, ["scroll.thumbOff"] = hex("#808080"),
    ["tab.glow"] = rgba(255, 255, 255, 0.25),
    -- No faint or translucent bind state: the gray and off-white ones in the palette, opaque.
    ["sem.boundNone"] = hex("#B0B0B0"), ["sem.boundBoE"] = HC_WHITE,
    ["sem.boundNoneAlt"] = hex("#B0B0B0"),
    -- LootHistory's other grays in the palette's own (white stays white).
    ["text.value"] = hex("#E0E0E0"), ["text.bodyAlt"] = HC_WHITE, ["text.subtle"] = HC_WHITE,
    ["icon.dim"] = hex("#B0B0B0"), ["sem.unknown"] = hex("#B0B0B0"), ["gtip.subtle"] = hex("#E0E0E0"),
  })

-- ── Ember ── mockup `ember`: charred brown, orange accent, Emblem for body and titles alike (minor
-- 18, D-06; Bitter from minor 11, Cinzel titles over the client body until then).
register("ember", "Ember", "Charred browns lit by an orange accent, Emblem type.",
  { "#1a0e0a", "#6a2e17", "#c98a3a", "#ff7a33" }, {
    font = "Ka0s Emblem", fs = 11, tfont = "Ka0s Emblem", titleSize = 12.5,
    barTex = "Ka0s Forge",
    win = rgba(26, 14, 10, 0.95), winBorder = edge(1, "flat", hex("#6a2e17")),
    winInner = rgba(201, 138, 58, 0.45), radius = 0,
    titleBg = grad(hex("#3a1a0f"), hex("#24100a")), titleColor = hex("#FFB45A"),
    divider = hex("#6a2e17"),
    text = hex("#F4E7DC"), muted = hex("#C7A993"), accent = hex("#FF7A33"),
    closeColor = hex("#C7A993"),
    btnBg = grad(hex("#4a2012"), hex("#2a120a")), btnBorder = edge(1, "flat", hex("#8a3c1c")),
    btnText = hex("#FFCF9A"), btnRadius = 0,
    priBg = grad(hex("#e0662a"), hex("#a63d12")), priBorder = edge(1, "flat", hex("#ff9a5a")),
    priText = hex("#FFFFFF"),
    inBg = hex("#140a07"), inBorder = edge(1, "flat", hex("#5a2a16")), inRadius = 0,
    inText = hex("#F4E7DC"), inPh = hex("#A88A76"),
    hdrBg = rgba(255, 122, 51, 0.08), hdrText = hex("#FFB45A"), rowAlt = rgba(255, 255, 255, 0.025),
    rowSel = rgba(255, 122, 51, 0.18),
    tabBg = hex("#2a140c"), tabText = hex("#C7A993"), tabBorder = edge(1, "flat", hex("#5a2a16")),
    tabRadius = 0, tabOnBg = hex("#4a2012"), tabOnText = hex("#FFB45A"), tabOnLine = hex("#FF7A33"),
    scTrack = hex("#2e1810"), scThumb = rgba(255, 122, 51, 0.9), scRadius = 0,
    chkBg = hex("#140a07"), chkBorder = edge(1, "flat", hex("#8a3c1c")), chkMark = hex("#FF7A33"),
    chkRadius = 0,
    slTrack = hex("#4a2416"), slTrackBorder = edge(0, "flat", CLEAR),
    slFill = hex("#FF7A33"), slThumb = hex("#FFCF9A"),
    navBg = rgba(0, 0, 0, 0.3), navBorder = edge(1, "flat", hex("#5a2a16")),
    navText = hex("#C7A993"), navSelBg = rgba(255, 122, 51, 0.2), navSelText = hex("#FFE2C4"),
    navSelBar = hex("#FF7A33"),
    drawerBg = hex("#2a140c"), drawerBorder = edge(1, "flat", hex("#6a2e17")),
    drawerText = hex("#FFB45A"),
    popBg = rgba(26, 14, 10, 0.97), popBorder = edge(1, "flat", hex("#8a3c1c")), popRadius = 0,
    tipBg = hex("#140a07"), tipBorder = edge(1, "flat", hex("#8a3c1c")), tipLevel = hex("#FFB45A"),
    tipMuted = hex("#C7A993"),
    footBg = rgba(0, 0, 0, 0.3),
  }, {
    ["text.disabled"] = hex("#8A6E5C"), ["text.linkHot"] = hex("#FFA36B"),
    ["drawer.bgOpen"] = hex("#4a2012"), ["drawer.boxBg"] = hex("#140a07"),
    ["drawer.summarySet"] = hex("#FFCF9A"),
    ["card.bg"] = rgba(42, 20, 12, 0.85), ["card.border"] = hex("#5a2a16"),
    ["panel.bg"] = rgba(0, 0, 0, 0.3), ["panel.border"] = hex("#5a2a16"),
    ["icon.hot"] = hex("#FFB45A"), ["scroll.thumbOn"] = rgba(255, 122, 51, 0.9),
    ["scroll.thumbOff"] = hex("#8a3c1c"),
  })

-- ── WoW Default ── mockup `wowdefault`: the vanilla client. Its CSS ridge and outset edges are
-- Blizzard's own art here: the window is BACKDROP_DIALOG_32_32's edge (LSM `Blizzard Dialog`,
-- UI-DialogBox-Border, 32px) over UI-DialogBox-Background-Dark tiled on the window fill; buttons
-- are the red gradient under a thin dark rim, the client's own button, with the primary a brighter
-- red under a thin gold edge (minor 7: the 2px bevelOut gold edge read as a frame, not a button); tabs are UI-OptionsFrame-ActiveTab in both
-- states (the InActiveTab art is drawn shorter, so idle tabs stood lower than the selected one; the
-- owner's note, round 3), the selected tab told by its white label; the scroll thumb is UI-ScrollBar-Knob; the checkbox is UI-CheckBox-Up and -Check.
-- An art token draws that art at its own colors; the color token beside it is the fallback when
-- the art does not load. Friz Quadrata (the shipped face since minor 18, D-01) and the client's
-- Blizzard bar, through KEEP: no font token and no bar texture.
local WOW_RED = grad(hex("#b3200f"), hex("#640c05"))
register("wow", "WoW Default", "The vanilla client: dialog-box border, red buttons, gold text.",
  { "#1e1c19", "#a8a8a8", "#640c05", "#ffd100" }, {
    fs = 11, titleSize = 13,
    win = hex("#1e1c19"), winBorder = edge(32, "nine:Blizzard Dialog", hex("#FFFFFF")),
    winInner = false, radius = 0,
    titleBg = grad(hex("#4b4b4b"), hex("#252525")), titleColor = hex("#FFD100"),
    divider = hex("#6e6e6e"),
    text = hex("#FFFFFF"), muted = hex("#B8B8B8"), accent = hex("#FFD100"),
    closeColor = hex("#D9D9D9"),
    btnBg = WOW_RED, btnBorder = edge(1, "flat", hex("#1a0805")), btnText = hex("#FFD100"),
    btnRadius = 0,
    priBg = grad(hex("#d42a16"), hex("#7e1007")), priBorder = edge(1, "flat", hex("#e0b040")),
    priText = hex("#FFFFFF"),
    inBg = hex("#000000"), inBorder = edge(1, "bevelIn", hex("#7a7a7a")), inRadius = 0,
    inText = hex("#FFFFFF"), inPh = hex("#9A9A9A"),
    hdrBg = rgba(255, 255, 255, 0.07), hdrText = hex("#FFD100"), rowAlt = rgba(255, 255, 255, 0.03),
    rowSel = rgba(255, 209, 0, 0.18),
    tabBg = hex("#262626"), tabText = hex("#C9B048"), tabBorder = edge(2, "bevelOut", hex("#7a7a7a")),
    tabRadius = 0, tabOnBg = hex("#4a4a4a"), tabOnText = hex("#FFFFFF"), tabOnLine = CLEAR,
    scTrack = hex("#000000"), scThumb = rgba(255, 209, 0, 0.9), scRadius = 0,
    chkBg = hex("#111111"), chkBorder = edge(0, "flat", false), chkMark = hex("#FFD100"),
    chkRadius = 0,
    slTrack = hex("#3a3a3a"), slTrackBorder = edge(0, "flat", CLEAR), slFill = hex("#C9A24A"),
    slThumb = hex("#C9A84A"),
    navBg = rgba(0, 0, 0, 0.4), navBorder = edge(1, "bevelIn", hex("#6e6e6e")),
    navText = hex("#FFD100"), navSelBg = rgba(90, 120, 220, 0.38), navSelText = hex("#FFFFFF"),
    navSelBar = CLEAR,
    drawerBg = hex("#262626"), drawerBorder = edge(2, "bevelOut", hex("#6e6e6e")),
    drawerText = hex("#FFD100"),
    popBg = hex("#1e1c19"), popBorder = edge(16, "nine:Blizzard Dialog", hex("#FFFFFF")),
    popRadius = 0,
    tipBg = rgba(0, 0, 16, 0.92), tipBorder = edge(2, "flat", hex("#9a9a9a")),
    tipMuted = hex("#B8B8B8"),
    footBg = rgba(0, 0, 0, 0.3),
  }, {
    ["win.bgTexture"] = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    ["tab.texture"] = "Interface\\OptionsFrame\\UI-OptionsFrame-ActiveTab",
    ["tab.onTexture"] = "Interface\\OptionsFrame\\UI-OptionsFrame-ActiveTab",
    ["scroll.thumbOn"] = rgba(255, 209, 0, 0.9), ["scroll.thumbOff"] = hex("#9A7B2A"),
    ["check.texture"] = "Interface\\Buttons\\UI-CheckBox-Up",
    ["check.markTexture"] = "Interface\\Buttons\\UI-CheckBox-Check",
    ["btn.hover"] = hex("#FFFFFF"), ["btnPrimary.hover"] = hex("#FFD100"),
    ["text.disabled"] = hex("#808080"),
    ["drawer.bgOpen"] = hex("#3a3a3a"), ["drawer.boxBg"] = hex("#111111"),
    ["card.bg"] = rgba(0, 0, 0, 0.4), ["card.border"] = hex("#6e6e6e"),
    ["panel.bg"] = rgba(0, 0, 0, 0.3), ["panel.border"] = hex("#6e6e6e"),
    -- The client's own resize grip and hover art, as the client draws them (minor 16): FOLLOW
    -- would tint them.
    ["icon.grip"] = false, ["list.hoverArt"] = false,
  })

-- ── WoW Midnight ── mockup `midnight`: night blue and violet under gold. Flat WHITE8x8 with a 2px
-- #b08a3e window edge and the gradient tokens; no Blizzard art. Segoe UI Semibold under Segoe UI Bold
-- titles, the titles centered (minor 18, D-06; Philosopher from minor 11, Cinzel titles over the
-- client body until then). Minor 7 (the
-- owner's 2026-10-26 notes): the buttons leave WoW Default's red for night violet under a gold edge,
-- and the primary button is the brighter violet of the accent.
local MN_GOLD, MN_BG = hex("#b08a3e"), grad(hex("#171a2e"), hex("#0f1020"))
register("midnight", "WoW Midnight", "Night blue and violet under a gold edge, centered Segoe UI titles.",
  { "#171a2e", "#b08a3e", "#2a2347", "#b48cff" }, {
    font = "Ka0s Segoe UI Semibold", fs = 11.5, tfont = "Ka0s Segoe UI Bold", titleSize = 13,
    barTex = "Ka0s Satin",
    win = MN_BG, winBorder = edge(2, "flat", MN_GOLD), winInner = hex("#3d2f12"), radius = 0,
    titleBg = grad(hex("#2a2347"), hex("#17142b")), titleColor = hex("#F6D27A"),
    titleAlign = "CENTER", divider = hex("#4a3d1e"),
    text = hex("#F2EEF8"), muted = hex("#B4AFC8"), accent = hex("#B48CFF"),
    closeColor = hex("#F6D27A"),
    btnBg = grad(hex("#3a2f6b"), hex("#1d1838")), btnBorder = edge(1, "flat", MN_GOLD),
    btnText = hex("#F6D27A"), btnRadius = 0,
    priBg = grad(hex("#7a5ad6"), hex("#3f2c86")), priBorder = edge(1, "flat", hex("#F6D27A")),
    priText = hex("#FFFFFF"),
    inBg = hex("#08091a"), inBorder = edge(1, "flat", hex("#5a4a26")), inRadius = 0,
    inText = hex("#F2EEF8"), inPh = hex("#9A95B0"),
    hdrBg = rgba(180, 140, 255, 0.08), hdrText = hex("#F6D27A"), rowAlt = rgba(255, 255, 255, 0.025),
    rowSel = rgba(180, 140, 255, 0.2),
    tabBg = hex("#1a1730"), tabText = hex("#B4AFC8"), tabBorder = edge(1, "flat", hex("#5a4a26")),
    tabRadius = 0, tabOnBg = hex("#2c2550"), tabOnText = hex("#F6D27A"), tabOnLine = hex("#B48CFF"),
    scTrack = hex("#22224a"), scThumb = rgba(246, 210, 122, 0.9), scRadius = 0,
    chkBg = hex("#08091a"), chkBorder = edge(1, "flat", MN_GOLD), chkMark = hex("#F6D27A"),
    chkRadius = 0,
    slTrack = hex("#2c2550"), slTrackBorder = edge(0, "flat", CLEAR),
    slFill = hex("#B48CFF"), slThumb = hex("#F6D27A"),
    navBg = rgba(0, 0, 0, 0.3), navBorder = edge(1, "flat", hex("#4a3d1e")),
    navText = hex("#F6D27A"), navSelBg = rgba(180, 140, 255, 0.25), navSelText = hex("#FFFFFF"),
    navSelBar = hex("#B48CFF"),
    drawerBg = hex("#1a1730"), drawerBorder = edge(1, "flat", hex("#5a4a26")),
    drawerText = hex("#F6D27A"),
    popBg = MN_BG, popBorder = edge(2, "flat", MN_GOLD), popRadius = 0,
    tipBg = rgba(10, 10, 26, 0.95), tipBorder = edge(1, "flat", MN_GOLD), tipLevel = hex("#F6D27A"),
    tipMuted = hex("#B4AFC8"),
    footBg = rgba(0, 0, 0, 0.3),
  }, {
    ["btn.hover"] = hex("#FFFFFF"), ["text.disabled"] = hex("#7A7590"),
    ["text.linkHot"] = hex("#D4BFFF"),
    ["drawer.bgOpen"] = hex("#2c2550"), ["drawer.boxBg"] = hex("#08091a"),
    ["drawer.summarySet"] = hex("#F6D27A"),
    ["card.bg"] = rgba(26, 23, 48, 0.85), ["card.border"] = hex("#4a3d1e"),
    ["panel.bg"] = rgba(0, 0, 0, 0.3), ["panel.border"] = hex("#4a3d1e"),
    ["icon.hot"] = hex("#F6D27A"), ["scroll.thumbOn"] = hex("#F6D27A"),
    ["scroll.thumbOff"] = MN_GOLD,
  })

-- ── WoW Forever ── mockup `forever`, the EllesmereUI-on-WoW-Forever look (OWNER_SCOPE R4): warm
-- charcoal (the mockup's radial fill as a vertical gradient, no texture), black title bars with
-- centered white titles, a tan accent, gold headings, thin 1px edges. SkinDefs minor 8 (the owner's
-- notes): Atkinson Hyperlegible for the blurry Barlow, and the charcoal a step browner; minor 11
-- (round 5: a face of its own, High Contrast keeps Atkinson): Fira Sans, crisp at small sizes; minor 17
-- (the owner's 2026-10-30 pick): Medium for body text, SemiBold kept for titles and HUD.
local FV_TAN, FV_EDGE = hex("#C9A07A"), hex("#3a3530")
local FV_BG = grad(hex("#2e251c"), hex("#18120d"))
register("forever", "WoW Forever", "Warm charcoal, black title bars with centered white titles, tan accent.",
  { "#231c15", "#3a3530", "#050505", "#c9a07a" }, {
    font = "Ka0s Fira Sans Medium", tfont = "Ka0s Fira Sans SemiBold", fs = 12, titleSize = 13.5,
    barTex = "Ka0s Classic",
    win = FV_BG, winBorder = edge(1, "flat", FV_EDGE), winInner = false, radius = 0,
    titleBg = hex("#050505"), titleColor = hex("#FFFFFF"), titleAlign = "CENTER",
    divider = hex("#2e2a26"), headColor = hex("#F2B33D"),
    text = hex("#FFFFFF"), muted = hex("#A39E97"), accent = FV_TAN, closeColor = hex("#FFFFFF"),
    btnBg = hex("#1f1d1b"), btnBorder = edge(1, "flat", hex("#48433d")), btnText = hex("#FFFFFF"),
    btnRadius = 0,
    priBg = hex("#9C7A58"), priBorder = edge(1, "flat", FV_TAN), priText = hex("#FFFFFF"),
    inBg = hex("#0a0908"), inBorder = edge(1, "flat", hex("#3e3934")), inRadius = 0,
    inText = hex("#FFFFFF"), inPh = hex("#8F8A83"),
    hdrBg = rgba(0, 0, 0, 0.35), hdrText = hex("#FFFFFF"), rowAlt = rgba(255, 255, 255, 0.025),
    rowSel = rgba(201, 160, 122, 0.16),
    tabBg = CLEAR, tabText = hex("#A39E97"), tabBorder = edge(1, "flat", CLEAR), tabRadius = 0,
    tabOnBg = rgba(0, 0, 0, 0.4), tabOnText = hex("#FFFFFF"), tabOnLine = FV_TAN,
    scTrack = hex("#0a0806"), scThumb = FV_TAN, scRadius = 0,
    chkBg = hex("#0a0908"), chkBorder = edge(1, "flat", hex("#8a7a52")), chkMark = FV_TAN,
    chkRadius = 0,
    slTrack = hex("#3a3632"), slTrackBorder = edge(0, "flat", CLEAR), slFill = FV_TAN,
    slThumb = FV_TAN,
    navBg = rgba(0, 0, 0, 0.3), navBorder = edge(1, "flat", CLEAR), navText = hex("#D8D3CB"),
    navSelBg = rgba(255, 255, 255, 0.07), navSelText = hex("#FFFFFF"), navSelBar = FV_TAN,
    drawerBg = hex("#1c1a17"), drawerBorder = edge(1, "flat", hex("#2e2a26")),
    drawerText = hex("#FFFFFF"),
    popBg = FV_BG, popBorder = edge(1, "flat", FV_EDGE), popRadius = 0,
    tipBg = hex("#0e0d0b"), tipBorder = edge(1, "flat", FV_EDGE), tipLevel = hex("#FFD100"),
    tipMuted = hex("#A39E97"),
    footBg = hex("#050505"), gloss = false,
  }, {
    ["btnPrimary.hover"] = hex("#FFE9D2"), ["drawer.textSet"] = hex("#F2B33D"),
    ["text.disabled"] = hex("#7A756E"), ["text.linkHot"] = hex("#E0C3A6"),
    ["drawer.bgOpen"] = hex("#24211e"), ["drawer.boxBg"] = hex("#0a0908"),
    ["drawer.summarySet"] = hex("#E0C3A6"),
    ["card.bg"] = hex("#1c1a17"), ["card.border"] = hex("#2e2a26"),
    ["panel.bg"] = rgba(0, 0, 0, 0.3), ["panel.border"] = hex("#2e2a26"),
    ["scroll.thumbOn"] = FV_TAN, ["scroll.thumbOff"] = hex("#6e5a46"),
  })
