-- LibKa0s-Skin-1.0 — the token schema and the nine skins: Ka0s Default, then Obsidian, Azeroth,
-- Glass, High Contrast, Ember, WoW Default, WoW Midnight and WoW Forever.
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
-- nil always means "leave the stock value alone": Ka0s Default leaves every font token nil, so a
-- FontString keeps its font object, its size and whatever a font-replacement addon did to it.
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
local DEFS_MINOR = 16
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
  -- Fonts (minor 8, the owner's ruling: Ka0s Default sets a font like every skin; minor 14, the
  -- owner's choice of face): Oxanium, SemiBold for the body and Bold for titles; the mono face
  -- DebugLog's console names; no outline, the client's 1, -1 shadow.
  ["font.body"] = "Ka0s Oxanium SemiBold", ["font.title"] = "Ka0s Oxanium Bold",
  ["font.mono"] = "JetBrains Mono",
  ["font.outline"] = "", ["font.shadow"] = true,
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
  ["bar.borderSize"] = 1, ["hud.font"] = "Ka0s Oxanium SemiBold", ["hud.fontSize"] = 12,
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
-- Default bar: the client's Friz Quadrata and its Blizzard bar. A skin that sets its own keeps that;
-- WoW Default is the one skin that sets no face and no bar, so these are its. The HUD face left KEEP
-- in minor 16: every skin names its own (HUD_FACE below).
local FRIZ = "Friz Quadrata TT"
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

-- Each skin's HUD face (minor 16, R-4): its own family at the heavier shipped weight, since HUD text
-- is 12px under an OUTLINE and a Regular's thin strokes close up under it; WoW Default the client's
-- own face, named here rather than left to a fallback. A skin's `extra` may still override.
local HUD_FACE = {
  obsidian = "Ka0s Inter SemiBold", azeroth = "Ka0s Vollkorn Bold", glass = "Ka0s Nunito SemiBold",
  contrast = "Ka0s Atkinson Bold", ember = "Ka0s Bitter Bold", wow = FRIZ,
  midnight = "Ka0s Philosopher Bold", forever = "Ka0s Fira Sans SemiBold",
}

local function register(key, label, desc, swatches, mock, extra)
  local tokens = translate(mock, extra)
  if tokens["hud.font"] == nil then tokens["hud.font"] = HUD_FACE[key] end
  local icon = ICON_EDGE[key]
  if icon and tokens["icon.borderStyle"] == nil then tokens["icon.borderStyle"] = icon[1] end
  if icon and tokens["icon.borderSize"] == nil then tokens["icon.borderSize"] = icon[2] end
  lib:RegisterSkin({ key = key, label = label, desc = desc, swatches = swatches, tokens = tokens })
end

-- ── Obsidian ── mockup `obsidian`. Inter, the mockup's own face (Barlow until minor 11).
register("obsidian", "Obsidian", "True black and flat, hairline edges, one cool blue accent.",
  { "#0a0a0b", "#202024", "#141416", "#4db8ff" }, {
    font = "Ka0s Inter", tfont = "Ka0s Inter SemiBold", fs = 12, titleSize = 14,
    barTex = "Ka0s Matte",
    win = hex("#0A0A0B"), winBorder = edge(1, "flat", hex("#202024")), winInner = false, radius = 0,
    titleBg = hex("#050506"), titleColor = hex("#F2F2F4"), divider = hex("#1c1c20"),
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
-- inner rule, parchment text, gold headings and accent, Vollkorn, a dark old-style book face, for body
-- and titles alike (minor 11; Cinzel titles over an Atkinson body until then); leather buttons, and
-- the red wax seal kept for the primary button and the selected tab. As a dark skin it inherits Ka0s
-- Default's semantic, quality, tooltip and chart colors.
local AZ_LEATHER, AZ_EDGE, AZ_GOLD = hex("#2B1D12"), hex("#6b4a22"), hex("#E2B659")
local AZ_TEXT, AZ_WAX = hex("#E9DDBC"), grad(hex("#a3241a"), hex("#5e1009"))
register("azeroth", "Azeroth", "Dark tooled leather, parchment text, gold and a red wax seal, Vollkorn type.",
  { "#2b1d12", "#6b4a22", "#e2b659", "#8e1b10" }, {
    font = "Ka0s Vollkorn", fs = 13, tfont = "Ka0s Vollkorn Bold", titleSize = 14,
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

-- ── Glass ── mockup `glass`. Manrope in the mockup; Nunito, rounded as its corners are, stands for
-- it (Barlow until minor 11). No blur in WoW: the window is translucent on the shipped Ka0s Glass
-- art (radius 8), the one rounded skin. Minor 7 (the
-- owner's 2026-10-26 notes): denser glass (.88), and only the window and its popups keep the rounded
-- art; buttons, inputs, tabs and drawers take a flat 1px frosted edge, and the tabs Obsidian's
-- boxless underline in lilac.
local GLASS_EDGE = rgba(255, 255, 255, 0.18)
register("glass", "Glass", "Translucent frosted panels with rounded corners and a lilac accent.",
  { "#121622", "#ffffff", "#b69cff", "#5aa9ff" }, {
    font = "Ka0s Nunito", tfont = "Ka0s Nunito SemiBold", fs = 12.5, titleSize = 14,
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

-- ── High Contrast ── mockup `contrast`: black, white 2px edges, yellow focus, Atkinson
-- Hyperlegible a point and a half above Ka0s Default's body size. Minor 7 (the owner's 2026-10-26 notes:
-- "borders are too thick"): every control edge is 1px; the window keeps its 2px edge and the popups
-- drop from 3px to 2px.
local HC_WHITE, HC_YELLOW = hex("#FFFFFF"), hex("#FFE600")
register("contrast", "High Contrast", "Black and white with yellow focus, crisp 1px edges, larger type.",
  { "#000000", "#ffffff", "#1a1a1a", "#ffe600" }, {
    font = "Ka0s Atkinson", tfont = "Ka0s Atkinson Bold", fs = 13.5, titleSize = 15,
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

-- ── Ember ── mockup `ember`: charred brown, orange accent, Bitter, a sturdy slab, for body and
-- titles alike (minor 11; Cinzel titles over the client body until then).
register("ember", "Ember", "Charred browns lit by an orange accent, Bitter type.",
  { "#1a0e0a", "#6a2e17", "#c98a3a", "#ff7a33" }, {
    font = "Ka0s Bitter", fs = 12, tfont = "Ka0s Bitter Bold", titleSize = 13.5,
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
-- the art does not load. The client's own Friz Quadrata and Blizzard bar, through KEEP: no font
-- token and no bar texture.
local WOW_RED = grad(hex("#b3200f"), hex("#640c05"))
register("wow", "WoW Default", "The vanilla client: dialog-box border, red buttons, gold text.",
  { "#1e1c19", "#a8a8a8", "#640c05", "#ffd100" }, {
    fs = 12, titleSize = 14,
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
-- #b08a3e window edge and the gradient tokens; no Blizzard art. Philosopher for body and titles,
-- the titles centered (minor 11; Cinzel titles over the client body until then). Minor 7 (the
-- owner's 2026-10-26 notes): the buttons leave WoW Default's red for night violet under a gold edge,
-- and the primary button is the brighter violet of the accent.
local MN_GOLD, MN_BG = hex("#b08a3e"), grad(hex("#171a2e"), hex("#0f1020"))
register("midnight", "WoW Midnight", "Night blue and violet under a gold edge, centered Philosopher titles.",
  { "#171a2e", "#b08a3e", "#2a2347", "#b48cff" }, {
    font = "Ka0s Philosopher", fs = 12.5, tfont = "Ka0s Philosopher Bold", titleSize = 14,
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
-- (round 5: a face of its own, High Contrast keeps Atkinson): Fira Sans, crisp at small sizes.
local FV_TAN, FV_EDGE = hex("#C9A07A"), hex("#3a3530")
local FV_BG = grad(hex("#2e251c"), hex("#18120d"))
register("forever", "WoW Forever", "Warm charcoal, black title bars with centered white titles, tan accent.",
  { "#231c15", "#3a3530", "#050505", "#c9a07a" }, {
    font = "Ka0s Fira Sans", tfont = "Ka0s Fira Sans SemiBold", fs = 12, titleSize = 14,
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
