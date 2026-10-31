-- LibKa0s-Skin-1.0 — the token schema and Ka0s Default. SkinDefsOthers.lua registers the other eight
-- skins on top of it: Obsidian, Azeroth, Glass, High Contrast, Ember, WoW Default, WoW Midnight and
-- WoW Forever.
--
-- ── WHY IT IS A FILE OF ITS OWN AND NOT MORE OF Skin.lua ─────────────────────────────────────
--
-- Skin.lua is the engine (owners, choice, resolve, the frame registry, the repaint); this file is
-- data. It is part of `LibKa0s-Skin-1.0`, paired on the shell's minor with the Widgets / Sim idiom,
-- so a skin table from one vendored copy never attaches to an engine from another without saying
-- so. A payload without this file still runs the engine: no skin is registered, every token
-- resolves to nil, and every primitive leaves the frame's stock look alone.
--
-- ── THE SCHEMA ───────────────────────────────────────────────────────────────────────────────
--
-- `lib.SCHEMA` lists every token a skin may set, in groups, each as `{ name, kind, nilable }`.
-- Kinds: `color` ({ r, g, b, a }, 0-1), `colors` (an ordered list of colors), `number`, `string`
-- (an LSM key, a texture path, an anchor word) and `bool`. A NILABLE token may resolve to nil, and
-- nil always means "leave the stock value alone": a skin that sets a font token to nil leaves a
-- FontString its font object, its size and whatever a font-replacement addon did to it. (Ka0s Default
-- has set every font token since minor 8.)
-- A skin derives from Ka0s Default (Skin:ResolveSkin): it names only the tokens it changes, and
-- `false` is how it says "none" for a token Ka0s Default sets.
--
-- ── KA0S DEFAULT IS TODAY'S CONSTANTS ────────────────────────────────────────────────────────
--
-- Every value below is a constant the library or LootHistory draws today, cited by name. Where two
-- sites draw one role in two colors, both survive as two tokens (`text.heading` and
-- `text.headingAlt`, `menu.border` and `menu.borderAlt`, ...) rather than one pixel changing; the
-- list is docs/api/Skin's "Split roles", the candidates for leg 2. Meaning-carrying colors (item
-- quality) stay the client's: Ka0s Default's `q.*` tokens are the client's ITEM_QUALITY_COLORS
-- written out exactly, hex / 255 (minor 16), never read from the client at load, when it may not
-- have filled them yet.
--
-- Geometry (`title.height`, `scroll.width`, `scroll.gutter`, `win.inset`) is skin-invariant in leg
-- 1: every skin carries Ka0s Default's value, so a live switch and a reload lay out the same.

local lib = LibStub and LibStub("LibKa0s-Skin-1.0", true)
if not lib then return end   -- the shell refused (no Core, or below its floor): nothing to attach to
-- Minor 7: no new token. Five skins retuned from the owner's in-game notes of 2026-10-26: Azeroth
-- (muted parchment, a shadowless Barlow body, light-on-leather tabs), Glass (denser, flat 1px
-- controls, underlined tabs), Obsidian (darker), High Contrast (1px control edges) and WoW Midnight
-- (violet-and-gold buttons). Ka0s Default's pixels are unchanged.

-- Minor 3: eight Widgets tokens (`handle.edge`, `handle.rest`, `list.dropLine`, `list.ghostBg` and
-- the four `list.box*`), so the drag handle and the reorder list follow a skin with Ka0s Default's
-- pixels unchanged (LK-06 of the skinning run).
-- Minor 4: ten tool-window tokens (`log.ts`, `log.tag`, `log.text`, `log.count`, `text.faint` and
-- the five `sem.step*`), so the debug console and the perf and sim panels follow a skin with Ka0s
-- Default's pixels unchanged (LK-09 of the skinning run); the other skins derive them (FOLLOW).
-- Minor 5: nine Semantic tokens, the five bind states (`sem.boundNone`, `sem.boundBoE`,
-- `sem.boundBoP`, `sem.boundWarband`, `sem.boundWarbandUE`), Insights' split of three of them
-- (`sem.boundBoPAlt`, `sem.boundBoEAlt`, `sem.boundNoneAlt`) and `sem.danger` for a destructive
-- menu item, so LootHistory's padlocks and row menu follow a skin with Ka0s Default's pixels
-- unchanged (LK-A2 of the skinning run). The dark skins inherit them; Azeroth and High Contrast
-- override for legibility.
-- Minor 6: eleven tokens for the rest of LootHistory's constants, each where no older token held
-- the exact value (LK-A3 of the skinning run, one sweep of the surfaces still to be skinned):
-- `text.value`, `text.bodyAlt`, `text.subtle`, `text.highlight`, `gtip.value`, `gtip.subtle`,
-- `icon.dim`, `sem.goodAlt`, `sem.badAlt`, `sem.warbandAlt` and `sem.unknown`. The dark skins
-- inherit them; Azeroth sets every window one in ink, and no skin darkens a gtip one.
-- Minor 8 (the owner's ruling, 2026-10-26: "make sure even the Ka0s Default has a setting for
-- everything"): Ka0s Default sets every token, faces and sizes included, and SkinPaint minor 6 paints
-- it like any skin; Azeroth is reworked dark (its light parchment did not read in Loot History);
-- WoW Forever takes Atkinson Hyperlegible and a browner charcoal.
-- Minor 9 (the owner's note, 2026-10-27: the scroll bar's thumb barely visible in Obsidian, High
-- Contrast, Ember, WoW Default and WoW Midnight): `scroll.thumbFill`, a flat fill laid over the
-- thumb (SkinPaintControls minor 6), which those five set in their accent; a tint can only darken
-- the client's thumb art, so no tint could brighten it. Ka0s Default and the rest set none.
-- Minor 10 (the owner's round-5 notes, 2026-10-28): every skin draws a scroll corridor and one knob.
-- `scroll.thumbFill` and `scroll.thumbTexture` are retired (never released): the knob is a flat
-- `scroll.thumb` over the faded thumb art (SkinPaintControls minor 7), and every skin's
-- `scroll.track` is a corridor that reads against its window, `thumbOn` / `thumbOff` the knob's
-- two states on the settings panel's bar.
-- Minor 11 (the owner's round-5 notes: titles that do not match the body, faces reused across skins,
-- Obsidian's not modern enough): every skin draws one family of its own for body and titles alike,
-- Obsidian Inter, Azeroth Vollkorn, Glass Nunito, High Contrast Atkinson Hyperlegible, Ember Bitter,
-- WoW Midnight Philosopher and WoW Forever Fira Sans (Media minor 8 ships them); Ka0s Default and WoW
-- Default draw the client's Friz Quadrata, the one face two skins share. Sizes retuned per face.
-- Minor 12 (the owner's round-5 showroom audit): `icon.arrow`, the in-client arrow art's color (the
-- paging, dropdown and sort arrows), Ka0s Default's gold and every other skin's accent (FOLLOW); the
-- art is yellow and a tint only multiplies it, so every skin drew yellow arrows. WoW Forever's check
-- mark is its tan accent, no longer Ka0s gold.
-- Minor 14 (the owner's choice, 2026-10-28): Ka0s Default draws Oxanium (SemiBold for body and HUD
-- text, Bold for titles) and the Ka0s Default bar (Media minor 9 ships both). Every other skin inherits
-- Ka0s Default's tokens, so `KEEP` holds the four values they inherited until now, Friz Quadrata and
-- the client's Blizzard bar, and each keeps them unless it sets its own. Then (SO-04, the owner's
-- approved mockup, still minor 14, unreleased): every skin but WoW Default draws a bar of its own,
-- `barTex` in its mockup entry (Media minor 9 ships them): Obsidian Ka0s Matte, Azeroth Ka0s
-- Parchment, Glass Ka0s Glass Bar, High Contrast Ka0s Solid, Ember Ka0s Forge, WoW Midnight Ka0s
-- Satin and WoW Forever Ka0s Classic. WoW Default sets none and keeps the Blizzard bar through KEEP.
-- Minor 15 (LK-04 of Ka0sAddonsCommonTasks docs/2026-10-29-SKINNING_ROLLOUT, gap DW-G14): the icon
-- border family, `icon.borderStyle` (a LibSharedMedia border key, as `bar.borderStyle` is; "Solid" is
-- the flat WHITE8X8 edge and "None" draws none) and `icon.borderSize` beside `icon.border`, so an item
-- icon's border can follow the skin (S.IconBorder's `opts.fromSkin`, OptionsCompose's
-- `BorderGroup{ fromSkin = "icon" }`). Ka0s Default's is Drop Watcher's Window › Icons border today,
-- Solid 2px; every other skin sets its own (ICON_EDGE below). No existing token moves.
-- Minor 16 (LK-09 of Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_LIBRARY_FOLLOWUPS, the owner's
-- ruling R-8): Ka0s Default's `q.*` tokens equal the client's quality colors exactly, hex / 255
-- (9d9d9d, ffffff, 1eff00, 0070dd, a335ee, ff8000), where they were rounded to two places (0.64,
-- 0.21, 0.93 is a3 36 ed, not the client's a335ee). Every skin that sets no `q.*` of its own, and
-- the eui source, inherits them. Then (LK-04, the owner's ruling R-4, DECISIONS D-11, still minor
-- 16): every skin names a HUD face of its own (HUD_FACE below), its text's family at the heavier
-- shipped weight: Obsidian Inter SemiBold, Azeroth Vollkorn Bold, Glass Nunito SemiBold, High Contrast
-- Atkinson Bold, Ember Bitter Bold, WoW Midnight Philosopher Bold, WoW Forever Fira Sans SemiBold, and
-- WoW Default the client's Friz Quadrata, set explicitly. `hud.font` leaves KEEP, which minor 14 had
-- send every one of them to Friz Quadrata. `hud.outline` (OUTLINE) and `hud.fontSize` (12) stay Ka0s
-- Default's everywhere. The eui source derives from Ka0s Default and keeps its Oxanium. Then (LK-08,
-- the owner's ruling R-7, DECISIONS D-14, still minor 16): `gtip.footer`, the drag handle's tooltip footer,
-- Ka0s Default's 0.6 gray (the literal WidgetsDragHandle drew) and every other skin's `gtip.muted`
-- through FOLLOW. The eui source derives it from Ka0s Default. Then (LK-06b, ruling R-5, decision
-- D-14, still minor 16): `icon.grip`, the resize grip's art color (Core.MakeResizable's
-- `opts.owner`), `false` in Ka0s Default and WoW Default (the client's size-grabber art as drawn) and
-- every other skin's `icon.tint` through FOLLOW. The eui source derives it from Ka0s Default. Then
-- (LK-06c, ruling R-5, decision D-14, still minor 16): `list.hoverArt`, the settings chrome's hover
-- art color (the drawer head, the nav entry, the id list entry, the id suggestion row), `false` in
-- Ka0s Default and WoW Default (the client's ADD highlight art as drawn) and every other skin's
-- `text.accent` through FOLLOW. The eui source derives it from Ka0s Default.
--
-- Minor 17 (LK-02 of Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK, the owner's
-- 2026-10-30 picks, DECISIONS D-02): Ka0s Default draws Prototype (Media minor 10) for body, titles
-- and HUD text, where minor 14 drew Oxanium SemiBold and Bold; Prototype has one weight, so its titles
-- differ by size alone. The eui source inherits the HUD face. WoW Forever's body text is Fira Sans
-- Medium; its titles and HUD stay Fira Sans SemiBold, the heavier-HUD rule above. Then (LK-A1, the
-- owner's ruling of 2026-10-30, "Ship it anyways", which overrides the EULA finding LK-01 withheld it
-- on; Media minor 10 ships it): Obsidian draws Expressway for body, titles and HUD text, where it drew
-- Inter and Inter SemiBold. Expressway ships one weight, the pack's Bold, so its titles differ by size
-- and its HUD face is its body face; the heavier-HUD rule is met by the Bold itself. Sizes do not move
-- here. Then (LK-03, the owner's ruling D-06, still minor 17): Ka0s Default's `font.outline` is
-- OUTLINE, where it was "", so every skin and the eui source state OUTLINE for window text as they do
-- for the HUD; an owner's Skin-tab "Font outline" takes it away (Skin minor 9), and the mono role is
-- never outlined (SkinPaint minor 13). Then (LK-05, the owner's item 5 and ruling D-08, still minor
-- 17): every skin's body and title sizes give its text Ka0s Default's width (Prototype at 12 / 14),
-- measured on the shipped bytes with OUTLINE on by Ka0sAddonsCommonTasks
-- docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK/plan-data/font_metrics_shipped.py:
-- Obsidian 12.5 / 14.5, Azeroth 12 / 12.5, Glass 11.5 / 13, High Contrast 12 / 13 (it no longer
-- reads larger), Ember 11.5 / 12.5, WoW Midnight 12.5 / 13.5 and WoW Forever 12 / 13.5; Ka0s Default
-- keeps 12 / 14, and so does WoW Default until minor 18. tests/test_skin_width_parity.lua
-- pins the measured widths. Then (LK-06, ruling D-09, still minor 17): every skin names a HUD size
-- of its own (HUD_SIZE below), from the same measurement, and `hud.fontSize` becomes a relative
-- reference like `font.bodySize`: S.HudFontSize scales a HUD element's stored size by it over Ka0s
-- Default's 12 (SkinPaintExtras minor 7).
--
-- Minor 18 (LK-F02 of Ka0sAddonsCommonTasks docs/2026-10-31-FONT_PICKERS_AND_SKIN_FACES, the owner's
-- 2026-10-31 picks, DECISIONS D-06; every face ships in Media minor 11): WoW Midnight draws Segoe UI
-- Semibold with Segoe UI Bold titles, Azeroth Open Sans Semibold with Open Sans Bold titles, Ember
-- Emblem, High Contrast Doris PP and Glass Avant Garde, the last three in one weight, so their
-- titles differ by size. WoW Default draws the shipped Ka0s Friz Quadrata TT, HUD included, where it
-- drew the client's: the owner's client file is Prototype's bytes, so the two skins read alike
-- (D-01). The HUD draws the owner's picked weight, the heavier-HUD rule surviving in WoW Forever
-- alone. Obsidian's title is its primary button's blue, #2A86D1, and its headings stay #F2F2F4. Then every size is
-- re-measured against Prototype at 12 / 14 / 12 (D-03) by Ka0sAddonsCommonTasks
-- docs/2026-10-31-FONT_PICKERS_AND_SKIN_FACES/plan-data/font_metrics_shipped.py, on the shipped bytes
-- with OUTLINE both ways: FACE_SIZES (SkinDefsOthers.lua since minor 19)
-- holds each shipped face's sizes, each skin's sizes are its faces' rows, and a font override of a
-- shipped face draws at that face's row (Skin minor 10, D-07). Real Friz is measured at last, so WoW
-- Default no longer shares Ka0s Default's sizes: 11 / 13 / 11, measured on FrizQuadrataTT-Regular.ttf,
-- md5 87cd491cd119e8c7aa48b562d7482ed8 (LibKa0s#69, re-measured 2026-10-31), where Prototype-Regular.ttf and the
-- owner's replaced client file are md5 0483b4eeaaefc7b81986e43702c7900d.
-- Minor 19: the eight other skins moved out, unchanged, to SkinDefsOthers.lua (LK-M2-PEEL of
-- Ka0sAddonsCommonTasks docs/2026-10-31-FINDINGS_REMEDIATION, the seam CLAUDE.md's census named).
local DEFS_MINOR = 19
if lib.__defsMinor and lib.__defsMinor >= DEFS_MINOR
  and lib.__defsShellMinor == lib.MINOR then return end
lib.__defsMinor      = DEFS_MINOR
lib.__defsShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.SkinDefs = DEFS_MINOR

-- ── the schema ───────────────────────────────────────────────────────────────────────────────

-- One string per group: `name:kind`, a trailing `?` marks a nilable token.
local GROUPS = {
  { "Fonts", "font.body:string? font.title:string? font.mono:string? font.bodySize:number? "
    .. "font.titleSize:number? font.outline:string? font.shadow:bool?" },
  { "Window", "win.bg:color win.bgTop:color? win.bgBottom:color? win.bgTexture:string? "
    .. "win.bgDense:color win.border:color win.borderSize:number win.borderStyle:string "
    .. "win.inner:color? win.inset:number win.radius:number title.bg:color? title.bgTop:color? "
    .. "title.bgBottom:color? title.text:color title.align:string? title.height:number "
    .. "divider:color foot.bg:color? close.rest:color close.hot:color" },
  { "Text", "text.body:color text.muted:color text.heading:color text.headingAlt:color "
    .. "text.accent:color text.disabled:color text.link:color text.linkHot:color "
    .. "gtip.title:color gtip.body:color gtip.muted:color text.faint:color log.ts:color "
    .. "log.tag:color log.text:color log.count:color text.value:color text.bodyAlt:color "
    .. "text.subtle:color text.highlight:color gtip.value:color gtip.subtle:color gtip.footer:color" },
  { "Buttons", "btn.bg:color btn.bgTop:color? btn.bgBottom:color? btn.border:color "
    .. "btn.borderSize:number? btn.borderStyle:string? btn.text:color btn.hover:color "
    .. "btn.icon:color btn.radius:number btnPrimary.bg:color btnPrimary.bgTop:color? "
    .. "btnPrimary.bgBottom:color? btnPrimary.border:color btnPrimary.borderSize:number? "
    .. "btnPrimary.borderStyle:string? btnPrimary.text:color btnPrimary.hover:color "
    .. "btnPrimary.icon:color btnPrimary.radius:number" },
  { "Inputs", "input.bg:color input.border:color input.borderSize:number? "
    .. "input.borderStyle:string? input.text:color? input.placeholder:color? input.focus:color "
    .. "input.radius:number check.bg:color check.border:color? check.borderSize:number? "
    .. "check.borderStyle:string? check.mark:color check.radius:number check.texture:string? "
    .. "check.markTexture:string? slider.track:color? "
    .. "slider.trackBorder:color? slider.fill:color? slider.thumb:color? scroll.track:color "
    .. "scroll.thumb:color scroll.thumbOn:color scroll.thumbOff:color scroll.width:number "
    .. "scroll.gutter:number scroll.radius:number" },
  { "Tabs and navigation", "tab.bg:color tab.bgTop:color? tab.bgBottom:color? tab.glow:color "
    .. "tab.text:color tab.border:color? tab.borderSize:number? tab.borderStyle:string? "
    .. "tab.onBg:color? tab.onText:color tab.onLine:color tab.rule:color tab.radius:number "
    .. "tab.texture:string? tab.onTexture:string? "
    .. "nav.bg:color nav.border:color nav.borderSize:number? nav.borderStyle:string? "
    .. "nav.text:color nav.selBg:color nav.selText:color nav.selBar:color?" },
  { "Drawers and menus", "drawer.bg:color drawer.bgOpen:color drawer.border:color "
    .. "drawer.borderOpen:color drawer.borderSize:number? drawer.borderStyle:string? "
    .. "drawer.boxBg:color drawer.boxBorder:color drawer.text:color drawer.textSet:color "
    .. "drawer.summary:color drawer.summarySet:color menu.bg:color menu.border:color "
    .. "menu.borderAlt:color menu.borderSize:number? menu.borderStyle:string? menu.hover:color "
    .. "menu.text:color menu.textSel:color" },
  { "Lists and cards", "list.header.bg:color? list.header.text:color list.stripe:color "
    .. "list.hover:color list.sel:color? list.selOutline:color? card.bg:color card.border:color "
    .. "panel.bg:color panel.border:color section.rule:color icon.tint:color icon.hot:color "
    .. "handle.bg:color handle.edge:color handle.rest:color list.dropLine:color list.ghostBg:color "
    .. "list.box:color list.boxDim:color list.boxEdge:color list.boxEdgeDim:color icon.dim:color "
    .. "icon.arrow:color icon.grip:color? list.hoverArt:color?" },
  { "Overlays", "popup.bg:color popup.border:color? popup.borderSize:number? "
    .. "popup.borderStyle:string? popup.radius:number tooltip.bg:color? tooltip.border:color? "
    .. "strip.test:color strip.sim:color cover.dim:color cover.text:color" },
  { "HUD", "bar.texture:string bar.gloss:bool bar.bg:color? bar.border:color? "
    .. "bar.borderStyle:string bar.borderSize:number icon.border:color? glow.color:color? "
    .. "hud.font:string hud.fontSize:number hud.outline:string icon.borderStyle:string "
    .. "icon.borderSize:number" },
  { "Charts", "chart.axis:color chart.axisAlt:color chart.grid:color chart.crosshair:color "
    .. "chart.marker:color chart.line:color chart.bar:color chart.track:color chart.total:color "
    .. "chart.other:color chart.otherLine:color chart.series:colors" },
  { "Semantic", "q.poor:color? q.common:color? q.uncommon:color? q.rare:color? q.epic:color? "
    .. "q.legendary:color? sem.good:color sem.bad:color sem.neutral:color sem.warn:color "
    .. "sem.info:color sem.gold:color sem.warband:color sem.statusOk:color "
    .. "sem.statusWarn:color sem.statusBad:color sem.modeTest:color sem.on:color sem.off:color "
    .. "sem.stepReady:color sem.stepBusy:color sem.stepLocked:color sem.stepCancel:color "
    .. "sem.stepCancelHot:color sem.boundNone:color sem.boundBoE:color sem.boundBoP:color "
    .. "sem.boundWarband:color sem.boundWarbandUE:color sem.boundBoPAlt:color sem.boundBoEAlt:color "
    .. "sem.boundNoneAlt:color sem.danger:color sem.goodAlt:color sem.badAlt:color "
    .. "sem.warbandAlt:color sem.unknown:color" },
}

local function buildSchema()
  local schema, index = {}, {}
  for _, g in ipairs(GROUPS) do
    for name, kind, opt in g[2]:gmatch("([%w%.]+):(%a+)(%??)") do
      local entry = { name = name, kind = kind, nilable = opt == "?", group = g[1] }
      schema[#schema + 1] = entry
      index[name] = entry
    end
  end
  return schema, index
end

--- Every token a skin may set, in groups, as `{ name, kind, nilable, group }`. Read-only.
lib.SCHEMA, lib.__schemaIndex = buildSchema()

-- ── Ka0s Default ─────────────────────────────────────────────────────────────────────────────

local GOLD     = { 1, 0.82, 0, 1 }          -- NORMAL_FONT_COLOR: Core.SKIN.title, every heading
local WHITE    = { 1, 1, 1, 1 }
local GRAY     = { 0.7, 0.7, 0.72, 1 }      -- Core CLOSE_REST, Browser SKIN.tabIdle, axis labels
local BODY     = { 0.9, 0.9, 0.9, 1 }       -- Widgets menu text, BrowserTable enabled text
local DIM      = { 0.5, 0.5, 0.5, 1 }       -- BrowserTable disabled, Compat tooltip hint
local EDGE     = { 0.24, 0.24, 0.27, 0.85 } -- Core.SKIN.innerBorder / divider
local CTL_FILL = { 0.1, 0.1, 0.12, 0.9 }    -- Widgets SKIN.fill; LootHistory's three button copies
local CTL_LINE = { 0.24, 0.24, 0.27, 0.9 }  -- Widgets SKIN.line; the same three copies

-- LootHistory AnalyticsFormat PALETTE: three seven-hue ramps, inverse VIBGYOR.
local SERIES = {
  { 0.90, 0.25, 0.25, 1 }, { 0.95, 0.55, 0.15, 1 }, { 0.88, 0.82, 0.22, 1 }, { 0.35, 0.75, 0.38, 1 },
  { 0.28, 0.55, 0.90, 1 }, { 0.42, 0.38, 0.82, 1 }, { 0.72, 0.42, 0.86, 1 },
  { 0.97, 0.58, 0.58, 1 }, { 0.98, 0.76, 0.50, 1 }, { 0.94, 0.90, 0.55, 1 }, { 0.60, 0.87, 0.63, 1 },
  { 0.58, 0.76, 0.97, 1 }, { 0.68, 0.64, 0.92, 1 }, { 0.86, 0.68, 0.94, 1 },
  { 0.62, 0.18, 0.18, 1 }, { 0.70, 0.40, 0.10, 1 }, { 0.60, 0.56, 0.12, 1 }, { 0.18, 0.52, 0.28, 1 },
  { 0.15, 0.38, 0.66, 1 }, { 0.28, 0.24, 0.58, 1 }, { 0.50, 0.28, 0.62, 1 },
}

local KA0S = {
  -- Fonts (minor 8, the owner's ruling: Ka0s Default sets a font like every skin; minor 17, the
  -- owner's choice of face): Prototype, for the body and titles alike (one weight; titles are larger);
  -- the mono face DebugLog's console names; OUTLINE (minor 17, D-06: the owner's "Font outline"
  -- removes it, and the mono role never takes it), the client's 1, -1 shadow.
  ["font.body"] = "Ka0s Prototype", ["font.title"] = "Ka0s Prototype",
  ["font.mono"] = "JetBrains Mono",
  ["font.outline"] = "OUTLINE", ["font.shadow"] = true,
  -- Window: Core.SKIN, the CopyWindow backdrop, LootHistory's title bar.
  ["win.bg"] = { 0.06, 0.06, 0.08, 0.92 }, ["win.bgDense"] = { 0.06, 0.06, 0.08, 0.95 },
  ["win.border"] = { 0, 0, 0, 1 }, ["win.borderSize"] = 1, ["win.borderStyle"] = "flat",
  ["win.inner"] = EDGE, ["win.inset"] = 1, ["win.radius"] = 0,
  ["title.text"] = GOLD, ["title.height"] = 30, ["divider"] = EDGE,
  ["close.rest"] = GRAY, ["close.hot"] = { 1, 0.3, 0.3, 1 },
  -- Text: Widgets menu rows, BrowserTable cells, LootHistory Panel's AH header, DebugLog's link.
  ["text.body"] = BODY, ["text.muted"] = GRAY, ["text.heading"] = GOLD,
  ["text.headingAlt"] = { 0.91, 0.77, 0.42, 1 }, ["text.accent"] = GOLD, ["text.disabled"] = DIM,
  ["text.link"] = { 1, 0.5, 0, 1 }, ["text.linkHot"] = { 1, 0.72, 0.28, 1 },
  -- Lines added to Blizzard's GameTooltip (LootHistory Compat Show*): title, body, hint.
  ["gtip.title"] = GOLD, ["gtip.body"] = BODY, ["gtip.muted"] = DIM,
  -- The tool windows: the perf / sim panels' command column (CMD_COLOR) and their disabled button
  -- label; DebugLog's console line (FormatColored's 6f8faf stamp and c9a66b tag, the message frame's
  -- own white) and its line count.
  ["text.faint"] = { 0.45, 0.45, 0.48, 1 },
  ["log.ts"] = { 0x6f / 255, 0x8f / 255, 0xaf / 255, 1 }, ["log.tag"] = { 0xc9 / 255, 0xa6 / 255, 0x6b / 255, 1 },
  ["log.text"] = WHITE, ["log.count"] = { 0.6, 0.6, 0.62, 1 },
  -- LootHistory's other text grays (minor 6): Insights' value and legend column (AnalyticsCharts),
  -- the AH table's live addon name (Panel), Holdings' holder total and fresh age, and its cells'
  -- white default; the GameTooltip value column (Compat, Timeline, Insights) and the launcher's
  -- record-count line.
  ["text.value"] = { 0.8, 0.8, 0.82, 1 }, ["text.bodyAlt"] = { 0.86, 0.86, 0.86, 1 },
  ["text.subtle"] = { 0.85, 0.85, 0.85, 1 }, ["text.highlight"] = WHITE,
  ["gtip.value"] = WHITE, ["gtip.subtle"] = { 0.7, 0.7, 0.7, 1 },
  -- The drag handle's tooltip footer (minor 16, LK-08): the 0.6 gray WidgetsDragHandle drew.
  ["gtip.footer"] = { 0.6, 0.6, 0.6, 1 },
  -- Buttons: LootHistory's flat buttons (BrowserFilterBar, Export, Timeline). No primary today.
  ["btn.bg"] = CTL_FILL, ["btn.border"] = CTL_LINE, ["btn.borderSize"] = 1,
  ["btn.borderStyle"] = "flat", ["btn.text"] = WHITE, ["btn.hover"] = GOLD,
  ["btn.icon"] = { 0.85, 0.85, 0.85, 1 }, ["btn.radius"] = 0,
  -- The primary button in Ka0s Default's gold (minor 7, the owner's note: a primary must differ
  -- from a normal button in every skin): a dark gold fill under a gold edge, gold text.
  ["btnPrimary.bg"] = { 0.2, 0.16, 0.03, 0.95 }, ["btnPrimary.border"] = { 1, 0.82, 0, 0.8 },
  ["btnPrimary.borderSize"] = 1,
  ["btnPrimary.borderStyle"] = "flat", ["btnPrimary.text"] = GOLD, ["btnPrimary.hover"] = WHITE,
  ["btnPrimary.icon"] = { 0.85, 0.85, 0.85, 1 }, ["btnPrimary.radius"] = 0,
  -- Inputs: Widgets SKIN (dropdown, SearchBox), LootHistory Timeline's toggle box and tick.
  ["input.bg"] = CTL_FILL, ["input.border"] = CTL_LINE, ["input.borderSize"] = 1,
  ["input.borderStyle"] = "flat", ["input.focus"] = { 1, 0.82, 0, 0.9 }, ["input.radius"] = 0,
  -- The reference sizes (SkinPaint minor 4): every skin sets both, and a target's size under a skin
  -- is its stock size times the skin's over these, so under Ka0s Default every string keeps its own.
  ["font.bodySize"] = 12, ["font.titleSize"] = 14,
  -- A square box in the control colors with a gold mark (minor 7, the owner's note: "more square,
  -- like Forever, in the Ka0s Default style"); Checkbox paints it under Ka0s Default since
  -- SkinPaintControls minor 2.
  ["check.bg"] = CTL_FILL, ["check.border"] = CTL_LINE, ["check.borderSize"] = 1,
  ["check.borderStyle"] = "flat",
  ["check.mark"] = GOLD, ["check.radius"] = 0,
  -- Scroll: DebugLog's console bar (BAR_W 8) and OptionsScroll's thumb tints and GUTTER.
  ["scroll.track"] = { 0.24, 0.24, 0.27, 0.4 }, ["scroll.thumb"] = { 0.5, 0.5, 0.55, 0.85 },
  ["scroll.thumbOn"] = WHITE, ["scroll.thumbOff"] = { 0.5, 0.5, 0.5, 0.6 },
  ["scroll.width"] = 8, ["scroll.gutter"] = 20, ["scroll.radius"] = 0,
  -- Tabs: OptionsTabs' backing gradient, glow and hairline; LootHistory Browser's labels.
  ["tab.bg"] = { 0.10, 0.10, 0.10, 0.85 }, ["tab.bgBottom"] = { 0.10, 0.10, 0.10, 0.85 },
  ["tab.bgTop"] = { 0.15, 0.15, 0.15, 0.85 }, ["tab.glow"] = { 1, 1, 1, 0.15 },
  ["tab.text"] = GRAY, ["tab.onText"] = GOLD, ["tab.onLine"] = GOLD,
  ["tab.rule"] = { 1, 0.82, 0, 0.16 }, ["tab.radius"] = 0,
  -- Nav rail: OptionsNav PANE_FILL / PANE_BORDER, SELECT_RGB, LABEL_GOLD / LABEL_WHITE.
  ["nav.bg"] = { 0.1, 0.1, 0.1, 0.5 }, ["nav.border"] = { 0.4, 0.4, 0.4, 1 },
  ["nav.text"] = GOLD, ["nav.selBg"] = { 0.3, 0.5, 1, 1 }, ["nav.selText"] = WHITE,
  -- Drawer: OptionsDrawer's palette.
  ["drawer.bg"] = { 0.08, 0.07, 0.06, 0.9 }, ["drawer.bgOpen"] = { 0.13, 0.11, 0.08, 0.95 },
  ["drawer.border"] = { 0.18, 0.16, 0.14, 1 }, ["drawer.borderOpen"] = { 0.42, 0.33, 0.13, 1 },
  ["drawer.borderSize"] = 1, ["drawer.borderStyle"] = "flat",
  ["drawer.boxBg"] = { 0.08, 0.07, 0.05, 0.9 }, ["drawer.boxBorder"] = { 0.24, 0.2, 0.13, 1 },
  ["drawer.text"] = WHITE, ["drawer.textSet"] = GOLD,
  ["drawer.summary"] = DIM, ["drawer.summarySet"] = { 0.91, 0.85, 0.66, 1 },
  -- Menus: Widgets' shared popup menu; LootHistory BrowserTable's row menu edge.
  ["menu.bg"] = { 0.06, 0.06, 0.08, 0.98 }, ["menu.border"] = { 0, 0, 0, 1 },
  ["menu.borderAlt"] = { 0.62, 0.5, 0.18, 1 }, ["menu.borderSize"] = 1,
  ["menu.borderStyle"] = "flat", ["menu.hover"] = { 1, 0.82, 0, 0.15 },
  ["menu.text"] = BODY, ["menu.textSel"] = GOLD,
  -- Lists and cards: BrowserTable / HoldingsTab rows, Analytics KPI cards and list panels.
  ["list.header.text"] = GOLD, ["list.stripe"] = { 1, 1, 1, 0.03 },
  ["list.hover"] = { 1, 0.82, 0, 0.10 },
  -- The settings chrome's hover art (minor 16, LK-06c): `false`, the client's ADD highlight art
  -- as it draws it (the drawer head, the nav entry, the id list entry, the suggestion row).
  ["list.hoverArt"] = false,
  ["card.bg"] = { 0.1, 0.1, 0.12, 0.85 }, ["card.border"] = CTL_LINE,
  ["panel.bg"] = { 0.08, 0.08, 0.10, 0.6 }, ["panel.border"] = { 0.24, 0.24, 0.27, 0.7 },
  ["section.rule"] = { 1, 0.82, 0, 0.35 },
  ["icon.tint"] = GRAY, ["icon.hot"] = WHITE, ["icon.arrow"] = GOLD,
  -- The resize grip (minor 16, LK-06b): `false`, the client's size-grabber art as it draws it.
  ["icon.grip"] = false, ["handle.bg"] = { 0, 0, 0, 0.75 },
  -- Widgets: WidgetsDragHandle's gold edge; WidgetsReorder's handle at rest, its insertion line, its
  -- carried copy and lib.ROW_BOX's fills and edges.
  ["handle.edge"] = { 1, 0.82, 0, 0.6 }, ["handle.rest"] = { 0.7, 0.7, 0.7, 1 },
  ["list.dropLine"] = { 1, 0.82, 0, 0.9 }, ["list.ghostBg"] = { 0.12, 0.12, 0.12, 0.95 },
  ["list.box"] = { 1, 1, 1, 0.06 }, ["list.boxDim"] = { 1, 1, 1, 0.03 },
  ["list.boxEdge"] = { 1, 1, 1, 0.12 }, ["list.boxEdgeDim"] = { 1, 1, 1, 0.06 },
  -- The AH table's info icon on an inactive row (LootHistory Panel; a live one is icon.hot).
  ["icon.dim"] = { 0.55, 0.55, 0.55, 1 },
  -- Overlays: OptionsIds' suggestion popup, Widgets STRIP_FILL, OptionsCombat's cover.
  ["popup.bg"] = { 0, 0, 0, 0.92 }, ["popup.radius"] = 0,
  ["strip.test"] = { 1, 0.65, 0.15, 0.12 }, ["strip.sim"] = { 0.35, 0.8, 1, 0.12 },
  ["cover.dim"] = { 0, 0, 0, 0.6 }, ["cover.text"] = { 0.667, 0.667, 0.667, 1 },
  -- HUD: OptionsCompose's FontGroup / BorderGroup / BarGroup defaults.
  ["bar.texture"] = "Ka0s Default", ["bar.gloss"] = false, ["bar.borderStyle"] = "None",
  ["bar.borderSize"] = 1, ["hud.font"] = "Ka0s Prototype", ["hud.fontSize"] = 12,
  ["hud.outline"] = "OUTLINE",
  -- The icon border (minor 15): Drop Watcher's Window › Icons border, the one item-icon border a Ka0s
  -- addon draws today (its defaults/Profile.lua icons.borderStyle "Solid", icons.borderSize 2; the
  -- color is `icon.border`'s black, below).
  ["icon.borderStyle"] = "Solid", ["icon.borderSize"] = 2,
  -- Charts: Widgets LINE_CHART, LootHistory AnalyticsCharts / AnalyticsLedger / C.TIMELINE.
  ["chart.axis"] = { 0.45, 0.45, 0.5, 0.8 }, ["chart.axisAlt"] = { 0.55, 0.55, 0.60, 0.9 },
  ["chart.grid"] = { 1, 1, 1, 0.07 }, ["chart.crosshair"] = { 1, 1, 1, 0.35 },
  ["chart.marker"] = { 0.8, 0.8, 0.8, 0.6 }, ["chart.line"] = { 0.4, 0.6, 0.95, 1 },
  ["chart.bar"] = { 0.40, 0.60, 0.95, 0.9 }, ["chart.track"] = { 1, 1, 1, 0.06 },
  ["chart.total"] = GOLD, ["chart.other"] = { 0.55, 0.62, 0.72, 1 }, ["chart.otherLine"] = GRAY,
  ["chart.series"] = SERIES,
  -- Semantic: LootHistory C.DirRGB, C.GOLD_RGB, C.TIMELINE.WARBAND, Panel STATUS_RGB, Browser
  -- TEST_MARK / SIM_MARK; OptionsIds' warn; DebugLog's on / off. Quality: the client's (nil).
  ["sem.good"] = { 0.35, 0.80, 0.45, 1 }, ["sem.bad"] = { 1, 0.33, 0.33, 1 },
  ["sem.neutral"] = { 0.62, 0.62, 0.66, 1 }, ["sem.warn"] = { 1, 0.5, 0, 1 },
  ["sem.info"] = { 0.3, 0.8, 1, 1 }, ["sem.gold"] = { 1, 0.86, 0.55, 1 },
  ["sem.warband"] = { 0.25, 0.75, 0.95, 1 }, ["sem.statusOk"] = { 0.30, 0.95, 0.35, 1 },
  ["sem.statusWarn"] = { 1, 0.82, 0.10, 1 }, ["sem.statusBad"] = { 1, 0.32, 0.32, 1 },
  ["sem.modeTest"] = { 1, 0.15, 0.15, 1 }, ["sem.on"] = { 0.3, 0.85, 0.3, 1 },
  ["sem.off"] = { 0.9, 0.3, 0.3, 1 },
  -- The perf / sim panels' step states (PerfPanel and SimPanel COLORS; done and used are sem.on):
  -- ready, busy, locked, cancel, and cancel under the pointer.
  ["sem.stepReady"] = { 0.9, 0.9, 0.92, 1 }, ["sem.stepBusy"] = GOLD,
  ["sem.stepLocked"] = { 0.4, 0.4, 0.42, 1 }, ["sem.stepCancel"] = { 0.8, 0.32, 0.32, 1 },
  ["sem.stepCancelHot"] = { 1, 0.45, 0.45, 1 },
  -- The bind states: LootHistory BrowserTable BOUND_STYLE (the table's padlocks, legend and
  -- filter), then AnalyticsFormat BOUND_COLOR's split of three of them (Insights; its warband and
  -- warband-until-equipped are the table's two). Danger: the row menu's Delete / Forget, |cffff5555.
  ["sem.boundNone"] = { 0.60, 0.60, 0.60, 0.40 }, ["sem.boundBoE"] = { 0.92, 0.92, 0.92, 0.95 },
  ["sem.boundBoP"] = { 0.30, 0.82, 0.42, 1 }, ["sem.boundWarband"] = { 0.30, 0.58, 0.98, 1 },
  ["sem.boundWarbandUE"] = { 0.95, 0.52, 0.12, 1 },
  ["sem.boundBoPAlt"] = { 0.85, 0.45, 0.45, 1 }, ["sem.boundBoEAlt"] = { 0.55, 0.80, 0.60, 1 },
  ["sem.boundNoneAlt"] = { 0.60, 0.60, 0.65, 1 },
  ["sem.danger"] = { 1, 1 / 3, 1 / 3, 1 },
  -- LedgerFormat's signed counts and money (|cff40ff40 / |cffff4040, not C.DirRGB), Holdings'
  -- Warband label (not C.TIMELINE.WARBAND) and Insights' no-quality fallback gray.
  ["sem.goodAlt"] = { 0.25, 1, 0.25, 1 }, ["sem.badAlt"] = { 1, 0.25, 0.25, 1 },
  ["sem.warbandAlt"] = { 0.4, 0.78, 1, 1 }, ["sem.unknown"] = { 0.6, 0.6, 0.6, 1 },
  -- ── Every other token, set (minor 8) ──────────────────────────────────────────────────────
  -- The owner's ruling (2026-10-26): Ka0s Default leaves nothing to the client. Each value below
  -- was nil, which meant "leave the client's look", and is now Ka0s Default's own: a color from its
  -- palette, the client's quality colors written out, or `false`, the explicit "none" (a decoration
  -- Ka0s Default does not draw, which is a setting, not a fallback).
  ["win.bgTop"] = false, ["win.bgBottom"] = false, ["win.bgTexture"] = false,
  ["title.bg"] = { 0.04, 0.04, 0.05, 0.9 }, ["title.bgTop"] = false, ["title.bgBottom"] = false,
  ["title.align"] = "CENTER", ["foot.bg"] = { 0.04, 0.04, 0.05, 0.9 },
  ["btn.bgTop"] = false, ["btn.bgBottom"] = false, ["btnPrimary.bgTop"] = false, ["btnPrimary.bgBottom"] = false,
  ["input.text"] = BODY, ["input.placeholder"] = DIM,
  ["check.texture"] = false, ["check.markTexture"] = false,
  -- The slider: the thin bar every skin draws (SkinPaintControls minor 3), in Ka0s Default's colors.
  ["slider.track"] = CTL_LINE, ["slider.trackBorder"] = false, ["slider.fill"] = GOLD,
  ["slider.thumb"] = { 0.9, 0.9, 0.9, 1 },
  ["tab.border"] = CTL_LINE, ["tab.borderSize"] = 1, ["tab.borderStyle"] = "flat",
  ["tab.onBg"] = { 0.18, 0.18, 0.18, 0.9 }, ["tab.texture"] = false, ["tab.onTexture"] = false,
  ["nav.borderSize"] = 1, ["nav.borderStyle"] = "flat", ["nav.selBar"] = false,
  ["list.header.bg"] = { 1, 1, 1, 0.04 }, ["list.sel"] = { 1, 0.82, 0, 0.18 }, ["list.selOutline"] = false,
  ["popup.border"] = CTL_LINE, ["popup.borderSize"] = 1, ["popup.borderStyle"] = "flat",
  ["tooltip.bg"] = { 0.05, 0.05, 0.08, 0.95 }, ["tooltip.border"] = CTL_LINE,
  ["bar.bg"] = { 0, 0, 0, 0.5 }, ["bar.border"] = { 0, 0, 0, 1 }, ["icon.border"] = { 0, 0, 0, 1 },
  ["glow.color"] = GOLD,
  -- The client's ITEM_QUALITY_COLORS, written out exactly (hex / 255, minor 16): the values every
  -- Blizzard frame draws.
  ["q.poor"] = { 0x9d / 255, 0x9d / 255, 0x9d / 255, 1 }, ["q.common"] = WHITE,
  ["q.uncommon"] = { 0x1e / 255, 1, 0, 1 }, ["q.rare"] = { 0, 0x70 / 255, 0xdd / 255, 1 },
  ["q.epic"] = { 0xa3 / 255, 0x35 / 255, 0xee / 255, 1 }, ["q.legendary"] = { 1, 0x80 / 255, 0, 1 },
}

lib:RegisterSkin({
  key = "ka0s",
  label = "Ka0s Default",
  desc = "Today's look: dark panels, hard 1px black edges, gold titles.",
  swatches = { "#0f0f14", "#000000", "#3d3d45", "#ffd100" },
  tokens = KA0S,
})
