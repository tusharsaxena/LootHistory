-- LibKa0s-Media-1.0 — the art and type this collection ships, and the paths that reach them.
--
-- Every Ka0s addon draws the same marks and prints its numbers in the same face. Before this module
-- each one shipped its own copy: Mythic Meters carried 49 TGAs and JetBrains Mono under its own
-- `media/`, built by a tool that lived in that repo, and the second addon to want a gear icon would
-- have copied both. Two copies of a texture is two licenses to track, two provenance stories, and a
-- collection whose addons stop looking like one author's work the moment one copy is regenerated.
--
-- So the art ships HERE, inside the vendored payload, and every consumer gets it with the `cp -r`
-- it already does.
--
-- ---------------------------------------------------------------------------------------------
-- WHY THIS TAKES AN ADDON NAME
-- ---------------------------------------------------------------------------------------------
--
-- A WoW texture path is absolute from `Interface\AddOns\`, and this library is VENDORED — there is
-- no single path to it, there are eight, one per consumer, and a copy cannot know which one it was
-- copied into. Lua gives a file no way to ask where it is: `...` carries the addon name only for a
-- file the TOC loads directly, and `LibKa0s.xml` is loaded from inside `libs/`, so what arrives is
-- the consumer's name in some builds and nothing in others. Guessing is worse than asking, because
-- a wrong texture path FAILS SILENTLY: the texture simply does not draw, no error, no log line.
--
-- The host passes its own name — which it has, verbatim, as the first vararg of every file the TOC
-- loads — and gets back a path that is correct by construction:
--
--     local M = LibStub("LibKa0s-Media-1.0", true)
--     M.Icon(addonName, "settings")
--       -> "Interface\\AddOns\\MythicMeters\\libs\\LibKa0s\\media\\icons\\settings.tga"
--
-- A consumer that vendors somewhere other than `libs/LibKa0s` passes `vendorPath`; nothing in the
-- collection does today, and the option exists so that a repo which must is not forced to rebuild
-- the string by hand and drift from it.
--
-- ---------------------------------------------------------------------------------------------
-- WHY AN UNKNOWN NAME ANSWERS NIL
-- ---------------------------------------------------------------------------------------------
--
-- Because the failure it replaces is invisible. A misspelt icon name built into a path yields a
-- texture that does not load, and a texture that does not load draws nothing and raises nothing —
-- the control is simply absent, and stays absent through every green test suite. `nil` is a value
-- the caller can see: it falls straight into the kind of fallback ladder a host already has for a
-- texture that fails to load, and a host without one gets a nil where it expected a string rather
-- than a button that quietly is not there.
--
-- That is also why `ICONS`, `FONTS` and the texture catalogs are published. They are the catalog — what exists, by the
-- names callers use — so a settings dropdown or a test can enumerate rather than hardcode.
--
-- Depends on LibStub and LibKa0s-Core-1.0, and on no addon framework. LibSharedMedia is OPTIONAL:
-- `RegisterLSM` is a no-op without it, because an addon that does not carry LSM still wants its
-- icons.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Media-1.0", 11
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

-- Which version of each FILE in this major is actually live, so version skew is discoverable at
-- runtime rather than by reading source. See docs/releasing.md.
lib.MODULES = lib.MODULES or {}
lib.MODULES.Media = MINOR

-- ── where the payload sits ─────────────────────────────────────────────────────────────────

-- Where a consumer vendors this library, from its own folder. The collection's convention, and the
-- one `docs/releasing.md` documents; `Icon`/`Font` take an override for a repo that differs.
lib.VENDOR_PATH = "libs\\LibKa0s"

local ICON_DIR    = "media\\icons"
local FONT_DIR    = "media\\fonts"
local TEXTURE_DIR = "media\\textures"

-- ── the catalog ──────────────────────────────────────────────────────────────────────────

-- Every icon in `media/icons/`, by the name callers use: Open Iconic's 113 semantic keys (MIT),
-- rendered to 64x64 white RGBA TGAs by `tools/artwork/icon_cleaner.py`, the provenance record for
-- ALL the art here. `MediaIcons.lua` appends the other sets at load (see ICON_SETS below); this
-- block stays first and in this order, because consumers store the path a name resolves to.
--
-- WHITE, AND THAT IS A CONTRACT. A texture is tinted by MULTIPLYING, so white art becomes any
-- color a caller asks for and black art stays black whatever it is asked for. Every mark here is
-- white with its shape entirely in the alpha channel. Art added later must be too, or a caller's
-- color setting silently stops working on that one icon.
--
-- TWO MARKS DELIBERATELY ABSENT, because Open Iconic has no glyph for them and a hand-drawn
-- substitute would be the one icon in the set that looks foreign: `save` (no floppy; `confirm`
-- carries the meaning) and `hidden` (no crossed-out eye; `eye` drawn dimmed is the state).
lib.ICONS = {
  -- the window header strip
  "close", "minimise", "expand", "lock", "unlock", "settings", "segment", "reset", "export",
  "sort-up", "sort-down",
  -- core actions
  "copy", "clear", "add", "edit", "confirm", "cancel", "search", "undo", "redo", "import",
  -- status and feedback
  "info", "warning", "help", "ban", "bug",
  -- state
  "pin", "eye", "star",
  -- layout
  "move", "resize", "fullscreen-enter", "fullscreen-exit", "grid", "list", "layers",
  -- navigation
  "chevron-left", "chevron-right", "chevron-up", "chevron-down",
  -- data
  "chart", "graph", "spreadsheet", "timer", "clock",
  -- arrows: the up/down family, every weight the set offers
  "arrow-up", "arrow-down", "arrow-thick-up", "arrow-thick-down", "arrow-circle-up",
  "arrow-circle-down", "collapse-up", "collapse-down", "expand-up", "expand-down", "align-top",
  "align-bottom",
  -- arrows: the marks that draw TWO of them
  "sort-asc", "sort-desc", "transfer", "elevator",
  -- talking
  "chat", "speech-bubble",
  -- arrows: left and right, matching the up/down family above
  "arrow-left", "arrow-right", "arrow-thick-left", "arrow-thick-right", "arrow-circle-left",
  "arrow-circle-right", "caret-left", "caret-right", "expand-left", "expand-right",
  -- text alignment
  "align-left", "align-center", "align-right", "justify-left", "justify-center", "justify-right",
  -- layout, continued
  "grid-two-up", "grid-four-up", "resize-height", "resize-width",
  -- status and state, continued
  "circle-check", "task", "thumb-up", "thumb-down", "heart", "bookmark",
  -- place and navigation
  "home", "location", "map-marker", "external-link", "link-intact",
  -- tools and devices
  "wrench", "terminal", "monitor", "video", "aperture", "zoom-in", "zoom-out",
  -- sound
  "volume-high", "volume-low", "volume-off",
  -- documents and labels
  "document", "tag", "tags",
  -- session
  "account-login", "account-logout",
  -- entities
  "person", "people", "target", "shield",
}

-- Every font in `media/fonts/`, keyed by the LSM name it registers under. `file` is the basename;
-- `license` names the file recording its terms, which ships beside it; `langmask` lists the
-- LibSharedMedia locale groups (`LSM.LOCALE_BIT_<group>`) whose text the face can draw.
--
-- JETBRAINS MONO IS THE MONOSPACE. A meter, a debug console and a perf table are all grids of
-- digits that change while you read them, and in a proportional face every digit is a different
-- width, so the column shivers as it ticks. JetBrains Mono pins them to a grid. It is the face the
-- debug console has always asked its host for; carrying it here is what stops each host answering
-- with a different one.
--
-- THE "Ka0s" FACES ARE THE SKINS' (minor 6; minor 8 gave every skin a family of its own, body and
-- titles alike, the owner's round-5 notes): Nunito (Glass), Vollkorn (Azeroth),
-- Bitter (Ember), Philosopher (WoW Midnight), Fira Sans (WoW Forever: Medium for body text since
-- minor 10, SemiBold for titles and HUD) and Atkinson Hyperlegible (High Contrast), each SIL OFL 1.1;
-- Prototype (Ka0s Default) and Expressway (Obsidian) are not, each on a recorded owner ruling (below);
-- WoW Default draws the client's Friz Quadrata. The skins' faces move again with SkinDefs in this
-- release, so that list dates from minor 10. Barlow and Cinzel, minor 6's, left at minor 8, never
-- released. `tools/artwork/fonts.py` is their provenance record: the pinned upstream commits, and the
-- static weights it cuts from the three variable fonts. A skin names a face by this key and resolves
-- it through LSM, never by path.
--
-- THE MASK IS PER FACE (minor 6; minor 5 had one for all). LibSharedMedia refuses a font whose mask
-- lacks the client's locale bit, which is the point: a face that draws a player's text as boxes does
-- not belong in their dropdown. The mask is read off each shipped file's cmap: JetBrains Mono and the
-- families with Cyrillic (Expressway among them) are western + ruRU; Atkinson, Prototype, Friz, Emblem
-- and Doris PP have none and are western only.
-- None has Hangul or Han, and on such a client the skin falls back to the client's own font.
--
-- PROTOTYPE IS KA0S DEFAULT'S FACE (minor 10; the owner's ruling of 2026-10-30), for body, titles
-- and HUD text alike: it has one weight, so titles differ by size. It is NOT under the OFL. Its own
-- name table reads "free for personal use, freely distributed with Prototype.txt", and the owner
-- ruled to ship it on those terms, so `Prototype.txt`, the author's text, ships beside it byte for
-- byte. That reverses minor 9, when the owner first ruled it out for its terms and Oxanium (OFL)
-- stood in for it. The key is the one the owner's SharedMedia pack registers, so a stored
-- "Ka0s Prototype" keeps resolving, to the same bytes. Latin only, so western.
--
-- EXPRESSWAY IS OBSIDIAN'S FACE (minor 10, LK-A1), for body, titles and HUD text alike: the owner's
-- pack copy, Expressway Rg Bold 2.100, one weight, so titles differ by size. It is NOT under the
-- OFL, and its terms do not allow this: its name table reads "(c) 2005 Typodermic. Do not
-- distribute.", and the Typodermic Desktop EULA 2026 that dafont's archive carries puts
-- "Embedding in an app, game, plug-in, program, or software product" outside the free license.
-- LK-01 withheld it on that evidence. The owner saw it and ruled on 2026-10-30: "Ship it anyways."
-- So it ships on that ruling, which overrides the EULA finding, and the EULA (`Expressway-EULA.pdf`)
-- and its quick guide (`Expressway-EULA-Guide.html`) ship beside it, unchanged but for the guide's
-- line endings, as the record of the terms the ruling overrode. The key is the one the owner's
-- SharedMedia pack registers, so a stored "Ka0s Expressway" keeps resolving, to the same bytes.
-- Its cmap has the whole Russian alphabet, so western + ruRU.
--
-- THE THIRTEEN FACES OF MINOR 11 (LK-F01, the owner's rulings of 2026-10-31) come from add-ons in the
-- owner's WoW install, unchanged: Friz Quadrata (a real copy, because the owner's client FRIZQT__.TTF
-- is Prototype's bytes, so a client Friz key cannot tell the two apart), Segoe UI's four weights, Open
-- Sans's five, Emblem, Doris PP and Avant Garde. "Segoe UI Light" is the Semilight file and "Open Sans
-- Condensed" the CondBold file, the keys the owner sees from Sorted. Open Sans is Apache 2.0, its text
-- beside it. The other eight have no license allowing this and ship on the owner's ruling alone;
-- `FONTS.md` quotes each notice, and is the `license` such a face names. Friz, Emblem and Doris PP have
-- no Cyrillic, so western; Segoe UI, Open Sans and Avant Garde have the Russian alphabet.
--
-- EVERY FACE STAYS (minor 11, the owner's item 3), a skin naming it or not: Nunito, Vollkorn, Bitter,
-- Philosopher, Fira Sans and Atkinson stay pickable after their skins moved on. That reverses the
-- rule minor 10 worked to, under which Oxanium SemiBold and Bold, Fira Sans Regular and Inter Regular
-- and SemiBold left: v1.81.0 shipped those five, so they come back with the Oxanium and Inter texts,
-- and a profile naming one keeps resolving.
local WEST_RU = { "western", "ruRU" }
lib.FONTS = {
  ["JetBrains Mono"]          = { file = "JetBrainsMono-Regular.ttf", license = "JetBrainsMono-OFL.txt",
                                  langmask = WEST_RU },
  ["Ka0s Nunito"]             = { file = "Nunito-Regular.ttf", license = "Nunito-OFL.txt", langmask = WEST_RU },
  ["Ka0s Nunito SemiBold"]    = { file = "Nunito-SemiBold.ttf", license = "Nunito-OFL.txt", langmask = WEST_RU },
  ["Ka0s Vollkorn"]           = { file = "Vollkorn-Regular.ttf", license = "Vollkorn-OFL.txt", langmask = WEST_RU },
  ["Ka0s Vollkorn Bold"]      = { file = "Vollkorn-Bold.ttf", license = "Vollkorn-OFL.txt", langmask = WEST_RU },
  ["Ka0s Bitter"]             = { file = "Bitter-Regular.ttf", license = "Bitter-OFL.txt", langmask = WEST_RU },
  ["Ka0s Bitter Bold"]        = { file = "Bitter-Bold.ttf", license = "Bitter-OFL.txt", langmask = WEST_RU },
  ["Ka0s Philosopher"]        = { file = "Philosopher-Regular.ttf", license = "Philosopher-OFL.txt",
                                  langmask = WEST_RU },
  ["Ka0s Philosopher Bold"]   = { file = "Philosopher-Bold.ttf", license = "Philosopher-OFL.txt",
                                  langmask = WEST_RU },
  ["Ka0s Oxanium SemiBold"]   = { file = "Oxanium-SemiBold.ttf", license = "Oxanium-OFL.txt",
                                  langmask = { "western" } },
  ["Ka0s Oxanium Bold"]       = { file = "Oxanium-Bold.ttf", license = "Oxanium-OFL.txt", langmask = { "western" } },
  ["Ka0s Inter"]              = { file = "Inter-Regular.ttf", license = "Inter-OFL.txt", langmask = WEST_RU },
  ["Ka0s Inter SemiBold"]     = { file = "Inter-SemiBold.ttf", license = "Inter-OFL.txt", langmask = WEST_RU },
  ["Ka0s Fira Sans"]          = { file = "FiraSans-Regular.ttf", license = "FiraSans-OFL.txt", langmask = WEST_RU },
  ["Ka0s Fira Sans Medium"]   = { file = "FiraSans-Medium.ttf", license = "FiraSans-OFL.txt", langmask = WEST_RU },
  ["Ka0s Fira Sans SemiBold"] = { file = "FiraSans-SemiBold.ttf", license = "FiraSans-OFL.txt",
                                  langmask = WEST_RU },
  ["Ka0s Atkinson"]           = { file = "AtkinsonHyperlegible-Regular.ttf",
                                  license = "AtkinsonHyperlegible-OFL.txt", langmask = { "western" } },
  ["Ka0s Atkinson Bold"]      = { file = "AtkinsonHyperlegible-Bold.ttf",
                                  license = "AtkinsonHyperlegible-OFL.txt", langmask = { "western" } },
  ["Ka0s Prototype"]          = { file = "Prototype-Regular.ttf", license = "Prototype.txt", langmask = { "western" } },
  ["Ka0s Expressway"]         = { file = "Expressway-Bold.ttf", license = "Expressway-EULA.pdf",
                                  langmask = WEST_RU },
  ["Ka0s Friz Quadrata TT"]   = { file = "FrizQuadrataTT-Regular.ttf", license = "FONTS.md", langmask = { "western" } },
  ["Ka0s Segoe UI"]           = { file = "SegoeUI-Regular.ttf", license = "FONTS.md", langmask = WEST_RU },
  ["Ka0s Segoe UI Bold"]      = { file = "SegoeUI-Bold.ttf", license = "FONTS.md", langmask = WEST_RU },
  ["Ka0s Segoe UI Light"]     = { file = "SegoeUI-Semilight.ttf", license = "FONTS.md", langmask = WEST_RU },
  ["Ka0s Segoe UI Semibold"]  = { file = "SegoeUI-Semibold.ttf", license = "FONTS.md", langmask = WEST_RU },
  ["Ka0s Open Sans"]          = { file = "OpenSans-Regular.ttf", license = "OpenSans-Apache-2.0.txt",
                                  langmask = WEST_RU },
  ["Ka0s Open Sans Bold"]     = { file = "OpenSans-Bold.ttf", license = "OpenSans-Apache-2.0.txt",
                                  langmask = WEST_RU },
  ["Ka0s Open Sans Condensed"] = { file = "OpenSans-CondBold.ttf", license = "OpenSans-Apache-2.0.txt",
                                   langmask = WEST_RU },
  ["Ka0s Open Sans Light"]    = { file = "OpenSans-Light.ttf", license = "OpenSans-Apache-2.0.txt",
                                  langmask = WEST_RU },
  ["Ka0s Open Sans Semibold"] = { file = "OpenSans-Semibold.ttf", license = "OpenSans-Apache-2.0.txt",
                                  langmask = WEST_RU },
  ["Ka0s Emblem"]             = { file = "Emblem-Regular.ttf", license = "FONTS.md", langmask = { "western" } },
  ["Ka0s Doris PP"]           = { file = "DorisPP-Bold.ttf", license = "FONTS.md", langmask = { "western" } },
  ["Ka0s Avant Garde"]        = { file = "AvantGarde-Regular.ttf", license = "FONTS.md", langmask = WEST_RU },
}

-- Every statusbar texture in `media/textures/`, keyed by the LSM name it registers under -- which is
-- also the name a player sees in a bar-texture dropdown and the string a profile stores. `file` is
-- the basename; there is no per-file license row because unlike the icons and the fonts, nothing here
-- came from anywhere: `tools/artwork/bar_textures.py` synthesizes every pixel, and that file is both
-- the provenance record and the license answer.
--
-- WHY THE KEYS LOOK LIKE LABELS AND THE FILES LOOK LIKE CODE. A dropdown reads "Ka0s Underline 2";
-- a path reads `underline-2`. They are the same thing said twice for two different readers, and the
-- pairing lives here so neither has to be derived from the other by string surgery.
--
-- UNDERLINE AND OVERLINE, not bottom and top: the pair names where the line SITS relative to the bar
-- the way type does. The number is a multiple of the base band (2px of 32), so `4` is four times the
-- line and NOT four pixels -- a name carrying a pixel count would be wrong the moment the canvas
-- changed. Every one of them is the same 256x32 canvas, so a frame sized for one is sized for all
-- of them and a player switching between them gets a different line, never a different-shaped widget.
--
-- KA0S DEFAULT (minor 9, 2026-10-28) is Ka0s Default's bar: dim at the top, a highlight low on the
-- bar and a short lip, in the manner of the "Melli Dark" bar the owner asked for, drawn by the same
-- tool rather than copied, because that file's author is not recorded.
--
-- EVERY SKIN'S OWN BAR (minor 9, SO-04, the owner's approved mockup): Ka0s Matte (Obsidian), Ka0s
-- Parchment (Azeroth), Ka0s Glass Bar (Glass), Ka0s Solid (High Contrast), Ka0s Forge (Ember), Ka0s
-- Satin (WoW Midnight) and Ka0s Classic (WoW Forever), from the same tool on the same canvas. WoW
-- Default keeps the client's `Blizzard` bar, so it has none here. GLASS BAR, not Glass: `Ka0s Glass`
-- is already the Glass border and background, and one name in three LSM catalogs would read in a
-- dropdown as one asset.
lib.TEXTURES = {
  ["Ka0s Gradient"]    = { file = "gradient.tga" },
  ["Ka0s Underline 1"] = { file = "underline-1.tga" },
  ["Ka0s Underline 2"] = { file = "underline-2.tga" },
  ["Ka0s Underline 4"] = { file = "underline-4.tga" },
  ["Ka0s Overline 1"]  = { file = "overline-1.tga" },
  ["Ka0s Overline 2"]  = { file = "overline-2.tga" },
  ["Ka0s Overline 4"]  = { file = "overline-4.tga" },
  ["Ka0s Default"]     = { file = "ka0s-default.tga" },
  ["Ka0s Matte"]       = { file = "matte.tga" },
  ["Ka0s Parchment"]   = { file = "parchment.tga" },
  ["Ka0s Glass Bar"]   = { file = "glass-bar.tga" },
  ["Ka0s Solid"]       = { file = "solid.tga" },
  ["Ka0s Forge"]       = { file = "forge.tga" },
  ["Ka0s Satin"]       = { file = "satin.tga" },
  ["Ka0s Classic"]     = { file = "classic.tga" },
}

-- The LSM `border` and `background` catalogs (minor 6): shipped art for a frame's edge and fill,
-- keyed by the LSM name, the files in `media/textures/` beside the statusbars. White, alpha carries
-- the shape, tinted at runtime like every other texture here. `tools/artwork/glass_textures.py`
-- synthesizes both and is their provenance record.
--
-- GLASS IS THE ONE ROUNDED SKIN, radius 8. The border is in the client's backdrop edge-file layout
-- (eight cells), so it draws wherever an LSM border does: `SetBackdrop{ edgeFile = <path>,
-- edgeSize = 8 }` is a 1px line with radius-8 corners. `edgeSize` records the size it is drawn at.
-- The background is a one-file nine-slice; `slice` is the margin to pass
-- `SetTextureSliceMargins`, so its corners stay 8x8 at any frame size and meet the border's.
--
-- ONLY SHIPPED ART. The in-client keys the skins use (`Blizzard Dialog`, `Blizzard Tooltip`,
-- `Blizzard Dialog Background`, `Solid`, ...) are LibSharedMedia's own defaults already, so nothing
-- here re-registers them.
lib.BORDERS = {
  ["Ka0s Glass"] = { file = "glass-border.tga", edgeSize = 8 },
}
lib.BACKGROUNDS = {
  ["Ka0s Glass"] = { file = "glass-fill.tga", slice = 8 },
}

-- THREE ICON SETS, ONE CATALOG (minor 5): Open Iconic (MIT, flat in `media/icons/`, unprefixed),
-- Phosphor Fill (MIT, `ph:<name>` in `media/icons/phosphor/`) and Game-icons.net (CC BY 3.0,
-- `gi:<name>` in `media/icons/game-icons/`). The prefix exists because the sets reuse each other's
-- names (star, heart, bug), and `:` occurs in no Open Iconic name, so the split is unambiguous.
-- `ICONS` stays the ONE enumerable list of every name: minor 4's 113 hand-written names first and
-- unmoved, then the generated names `MediaIcons.lua` appends.
--
-- The icon sets, in the order a browser lists them. `prefix` starts every name of the set (empty
-- for Open Iconic, whose names predate the other sets), `dir` is its folder under `media\icons`
-- (empty: the folder itself), `license` the file recording its terms, which ships in that folder.
-- Game-icons is CC BY 3.0, so its folder also carries `AUTHORS.txt` (every mark's author) and the
-- statement of changes, and `IconAuthor` answers the author per name.
lib.ICON_SETS = {
  { id = "open-iconic", prefix = "",    dir = "",           label = "Open Iconic",
    license = "LICENSE-open-iconic.txt" },
  { id = "phosphor",    prefix = "ph:", dir = "phosphor",   label = "Phosphor",
    license = "LICENSE-phosphor.txt" },
  { id = "game-icons",  prefix = "gi:", dir = "game-icons", label = "Game-icons",
    license = "LICENSE-game-icons.txt" },
}

-- A prefix's folder, answered by lookup. Built once from ICON_SETS so that table stays the one
-- place a set is described.
local SET_DIR = {}
for _, set in ipairs(lib.ICON_SETS) do
  SET_DIR[set.prefix] = set.dir == "" and ICON_DIR or (ICON_DIR .. "\\" .. set.dir)
end

-- Answering a lookup with a set rather than a linear scan of ICONS. Built from the array, so the
-- array stays the single place a name is written down; `__SetGeneratedIcons` rebuilds it.
local KNOWN_ICON, ICON_AUTHOR = {}, {}
local BASE_ICONS = #lib.ICONS
for i = 1, BASE_ICONS do KNOWN_ICON[lib.ICONS[i]] = true end

--- Append the generated names to ICONS, in place, and index them. Called by `MediaIcons.lua`, once
--- per load of that file against this shell.
---
--- IDEMPOTENT, because the paired-file guard lets a newer `MediaIcons.lua` run again against the
--- same shell: ICONS is cut back to the hand-written block first, then refilled, so a second call
--- never doubles a name. The TABLE keeps its identity — a host that captured `ICONS` once still
--- reads the whole catalog.
---
--- @param names table    array of catalog names, prefixes included
--- @param authors table  optional, name -> author, for the CC BY sets
function lib.__SetGeneratedIcons(names, authors)
  local icons = lib.ICONS
  for i = #icons, BASE_ICONS + 1, -1 do
    KNOWN_ICON[icons[i]] = nil
    icons[i] = nil
  end
  ICON_AUTHOR = {}
  for i = 1, #names do
    local name = names[i]
    if not KNOWN_ICON[name] then
      icons[#icons + 1] = name
      KNOWN_ICON[name] = true
    end
  end
  for name, who in pairs(authors or {}) do
    if KNOWN_ICON[name] then ICON_AUTHOR[name] = who end
  end
end

-- ── paths ──────────────────────────────────────────────────────────────────────────────────

local function root(addonName, vendorPath)
  if type(addonName) ~= "string" or addonName == "" then return nil end
  return "Interface\\AddOns\\" .. addonName .. "\\" .. (vendorPath or lib.VENDOR_PATH) .. "\\"
end

--- The texture path for one icon, or nil when the name is not in `ICONS`.
---
--- EXTENSIONLESS, and that changed at minor 2. Minor 1 answered `...\\settings.tga` on the
--- reasoning that one spelling beats two. The consumer that adopted it first records the opposite
--- from a live client: Mythic Meters' header art has failed silently twice, and its surviving note
--- says a path carrying `.tga` is one of the two spellings that draws NOTHING. A texture that does
--- not load draws nothing and raises nothing, so "it probably works either way" is not a thing
--- anyone discovers is wrong. The client appends the extension itself. The file on disk is still
--- `<name>.tga`, and `tests/test_media.lua` checks for it under that name.
---
--- A PREFIXED NAME resolves into its set's folder (minor 5): `ph:sword` is
--- `...\media\icons\phosphor\sword`. The name must still be in `ICONS`, so an unknown prefix,
--- or a set's mark asked for without its prefix, answers nil like any other unknown name.
---
--- @param addonName string  the consumer's own addon folder name (its first vararg)
--- @param name string       an entry of `lib.ICONS`
--- @param vendorPath string optional, defaults to `lib.VENDOR_PATH`
--- @return string|nil
function lib.Icon(addonName, name, vendorPath)
  if not KNOWN_ICON[name] then return nil end
  local base = root(addonName, vendorPath)
  if not base then return nil end
  local prefix, rest = name:match("^(%l+:)(.+)$")
  if not prefix then return base .. ICON_DIR .. "\\" .. name end
  local dir = SET_DIR[prefix]
  if not dir then return nil end
  return base .. dir .. "\\" .. rest
end

--- The author of one icon, for the sets whose license asks for attribution per mark (Game-icons,
--- CC BY 3.0), or nil for every other name, an unknown one included. A browser shows it in the
--- mark's tooltip; the full list ships as `media/icons/game-icons/AUTHORS.txt`.
---
--- @param name string  an entry of `lib.ICONS`
--- @return string|nil
function lib.IconAuthor(name)
  if type(name) ~= "string" then return nil end
  return ICON_AUTHOR[name]
end

--- The extensionless path of one entry of a texture catalog, or nil. Shared by `Texture`,
--- `Border` and `Background`, whose files all sit in `media/textures/`.
local function texturePath(catalog, addonName, name, vendorPath)
  local entry = catalog[name]
  if not entry then return nil end
  local base = root(addonName, vendorPath)
  if not base then return nil end
  return base .. TEXTURE_DIR .. "\\" .. (entry.file:gsub("%.tga$", ""))
end

--- The path of one shipped statusbar texture, or nil when the name is not in `TEXTURES`.
---
--- EXTENSIONLESS, like `Icon` and for the same recorded reason. LSM stores whatever string it is
--- handed and hands it back untouched, so the convention costs nothing there, and one rule for every
--- path this module answers is worth more than matching what other addons happen to register.
---
--- @param addonName string  the consumer's own addon folder name
--- @param name string       a key of `lib.TEXTURES`, e.g. "Ka0s Underline 2"
--- @param vendorPath string optional
--- @return string|nil
function lib.Texture(addonName, name, vendorPath)
  return texturePath(lib.TEXTURES, addonName, name, vendorPath)
end

--- The path of one shipped border (a backdrop edge file), extensionless, or nil when the name is
--- not in `BORDERS` or `addonName` is missing. The skin engine reaches it through LSM instead.
---
--- @param addonName string  the consumer's own addon folder name
--- @param name string       a key of `lib.BORDERS`, e.g. "Ka0s Glass"
--- @param vendorPath string optional
--- @return string|nil
function lib.Border(addonName, name, vendorPath)
  return texturePath(lib.BORDERS, addonName, name, vendorPath)
end

--- The path of one shipped background, extensionless, or nil when the name is not in
--- `BACKGROUNDS` or `addonName` is missing.
---
--- @param addonName string  the consumer's own addon folder name
--- @param name string       a key of `lib.BACKGROUNDS`, e.g. "Ka0s Glass"
--- @param vendorPath string optional
--- @return string|nil
function lib.Background(addonName, name, vendorPath)
  return texturePath(lib.BACKGROUNDS, addonName, name, vendorPath)
end

--- The font path for one registered face, or nil when the name is not in `FONTS`.
---
--- @param addonName string  the consumer's own addon folder name
--- @param name string       a key of `lib.FONTS`, e.g. "JetBrains Mono"
--- @param vendorPath string optional
--- @return string|nil
function lib.Font(addonName, name, vendorPath)
  local entry = lib.FONTS[name]
  if not entry then return nil end
  local base = root(addonName, vendorPath)
  if not base then return nil end
  return base .. FONT_DIR .. "\\" .. entry.file
end

-- ── LibSharedMedia ─────────────────────────────────────────────────────────────────────────

--- Register one entry and answer 1 when LSM holds the key afterwards, 0 when it does not.
--- A key LSM already holds is never offered (minor 7): it counts as held and `Register` is not
--- called, because LSM-3.0 validates the file before it checks the key and reports a missing one
--- (see RegisterLSM). `langmask` is passed only when non-nil, so an LSM without locale bits sees
--- the plain call. An LSM with no `IsValid` (a consumer's test fake; the real LSM-3.0 has it)
--- cannot be asked, so every call is made and counts, as it did at minor 3.
local function registerOne(LSM, kind, name, path, langmask)
  local canAsk = type(LSM.IsValid) == "function"
  if canAsk and LSM:IsValid(kind, name) then return 1 end
  if langmask then
    LSM:Register(kind, name, path, langmask)
  else
    LSM:Register(kind, name, path)
  end
  if not canAsk then return 1 end
  return LSM:IsValid(kind, name) and 1 or 0
end

--- The locale mask for one face, the sum of `LSM.LOCALE_BIT_<group>` over its `langmask` list
--- (see RegisterLSM), or nil when LSM publishes no bit for one of them, so an LSM too old to carry
--- the constants gets the plain call.
local function fontLangmask(LSM, entry)
  local mask = 0
  for _, group in ipairs(entry.langmask or {}) do
    local bit = LSM["LOCALE_BIT_" .. group]
    if type(bit) ~= "number" then return nil end
    mask = mask + bit
  end
  return mask > 0 and mask or nil
end

--- Register every entry of one catalog as `kind` and answer how many LSM holds afterwards.
--- `pathOf` is the catalog's path reader (`lib.Font`, `lib.Texture`, ...); `maskOf`, when given,
--- answers the langmask for an entry (fonts only).
local function registerCatalog(LSM, kind, catalog, pathOf, addonName, vendorPath, maskOf)
  local held = 0
  for name, entry in pairs(catalog) do
    local path = pathOf(addonName, name, vendorPath)
    if path then
      held = held + registerOne(LSM, kind, name, path, maskOf and maskOf(entry) or nil)
    end
  end
  return held
end

--- Put every shipped font, statusbar texture, border and background into LibSharedMedia under its
--- catalog name.
---
--- WHY REGISTERING MATTERS AND A PATH DOES NOT. A host can draw with `Font(...)` and never touch
--- LSM. What registration buys is the settings panel: an LSM-registered face appears in the font
--- dropdown beside every other font the player has, and a profile can then store the NAME —
--- portable across installs — instead of a path that names one addon's folder and breaks the moment
--- the player renames it.
---
--- THE FIRST REGISTRATION WINS, BUT A LATER ONE IS NOT SILENT. LSM keeps the first path offered
--- under a key and answers `false` to every later `Register` for it. Each consumer offers a
--- DIFFERENT path — its own `Interface\AddOns\<Addon>\libs\LibKa0s\...` — and every one of those
--- paths names identical bytes, the same file vendored whole into each addon, so whichever copy
--- wins, the player sees the same face under the same name. What LSM-3.0 does BEFORE that check is
--- the catch: for a font, border or background it validates the file first, and a path to a file
--- that does not exist is reported through `geterrorhandler()` as "Attempt to register an invalid
--- font" (or border, or background), held key or not. Non-fatal, but it lands in the player's
--- BugSack once per key per addon. LibStub keeps the highest minor, so a host whose own vendored
--- folder predates a key's art still runs the newest copy's `RegisterLSM`, and that copy builds the
--- path into the host's folder, where the file is absent. The owner's client showed exactly this on
--- 2026-10-25, once LootHistory vendored minor 6 and the other addons still carried minor 5.
---
--- SO A HELD KEY IS NEVER OFFERED (minor 7). When `LSM:IsValid(type, name)` already answers true,
--- `Register` is not called at all and the key counts as held. The host never needs its own path in
--- LSM: the held one names the same bytes.
---
--- EACH FACE CARRIES ITS OWN MASK (minor 6), from its `langmask` list in `FONTS`. On a non-western
--- client LSM refuses a font that carries no langmask, and one whose mask lacks the client's locale
--- bit. JetBrains Mono has Latin and Cyrillic glyphs and no Hangul or Han, so it is offered to
--- western and ruRU clients; the five skin faces are western only. CJK clients are excluded on
--- purpose: a face that draws their text as boxes does not belong in their font dropdown. An LSM
--- too old to publish the `LOCALE_BIT_*` constants gets a plain `Register`.
---
--- COUNTED ONLY WHEN LSM HAS IT. A font or texture counts when `LSM:IsValid(type, name)` answers
--- true after the call, not because `Register` was called: a refused face is not registered, and a
--- key another copy registered first is (see above). An LSM without `IsValid` — never the real
--- LSM-3.0, but the fakes in consumers' test harnesses — cannot be asked, so every key is offered
--- and every call counts, as minor 3 did.
---
--- Call it at FILE LOAD rather than at PLAYER_LOGIN. LibSharedMedia is vendored under `libs/` and
--- has therefore already run by the time a TOC reaches the consumer's own files, and a default that
--- names a face LSM has not heard of yet is a default that resolves to nothing.
---
--- THE NEW LEG-1 KEYS LAND FROM ONE FOLDER. While only one consumer vendors the skin faces and the
--- Glass art, its `RegisterLSM` is the first to offer them, so they resolve into THAT addon's folder,
--- which holds the files. A consumer that loads before it runs its own older copy, which does not
--- know the keys; one that loads after it runs this code, finds the keys held and offers nothing.
--- What remains: a key nobody holds yet is still offered at the CALLER's folder. So a host that
--- vendors this minor but never calls `RegisterLSM` (or calls it later than file load) leaves the
--- new keys unheld, and the next addon to call it reports the missing files as above. That case
--- ends when the collection's rollout re-vendors v1.78.0 into every consumer, since every folder
--- then carries the files.
---
--- @param addonName string  the consumer's own addon folder name
--- @param vendorPath string optional
--- @return number fonts, number statusbars, number borders, number backgrounds  how many of each LSM
---         holds after the call; all 0 when LSM is absent, which is not an error. The third and
---         fourth arrived at minor 6; a caller reading two still reads the first two.
function lib.RegisterLSM(addonName, vendorPath)
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  if not LSM then return 0, 0, 0, 0 end

  local mt = LSM.MediaType or {}

  local fonts = registerCatalog(LSM, mt.FONT or "font", lib.FONTS, lib.Font, addonName, vendorPath,
    function(entry) return fontLangmask(LSM, entry) end)

  -- STATUSBAR, and it is the same bargain the fonts strike. A registered texture is what a player
  -- picks out of a bar-texture dropdown by name, and a NAME is what their profile then stores --
  -- portable between installs, where a path is pinned to one addon's folder and breaks the moment
  -- the folder is renamed.
  local bars = registerCatalog(LSM, mt.STATUSBAR or "statusbar", lib.TEXTURES, lib.Texture,
    addonName, vendorPath)

  -- BORDER and BACKGROUND, the same bargain again: a frame-art dropdown offers them by name.
  local borders = registerCatalog(LSM, mt.BORDER or "border", lib.BORDERS, lib.Border,
    addonName, vendorPath)
  local backgrounds = registerCatalog(LSM, mt.BACKGROUND or "background", lib.BACKGROUNDS,
    lib.Background, addonName, vendorPath)

  return fonts, bars, borders, backgrounds
end
