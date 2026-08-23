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
-- That is also why `ICONS` and `FONTS` are published. They are the catalog — what exists, by the
-- names callers use — so a settings dropdown or a test can enumerate rather than hardcode.
--
-- Depends on LibStub and LibKa0s-Core-1.0, and on no addon framework. LibSharedMedia is OPTIONAL:
-- `RegisterLSM` is a no-op without it, because an addon that does not carry LSM still wants its
-- icons.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Media-1.0", 3
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

-- Every icon in `media/icons/`, by the name callers use, which is the file's own basename. Open
-- Iconic (MIT), rendered to 64x64 white RGBA TGAs by `tools/artwork/icon_cleaner.py` — that tool is
-- the provenance record for this art: which upstream glyph each name draws, and every
-- transformation applied. The license ships beside the art in `media/icons/`.
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
-- `license` names the file recording its terms, which ships beside it.
--
-- ONE FACE, AND IT IS MONOSPACE. A meter, a debug console and a perf table are all grids of digits
-- that change while you read them, and in a proportional face every digit is a different width, so
-- the column shivers as it ticks. JetBrains Mono pins them to a grid. It is the face the debug
-- console has always asked its host for; carrying it here is what stops each host answering with a
-- different one.
lib.FONTS = {
  ["JetBrains Mono"] = { file = "JetBrainsMono-Regular.ttf", license = "JetBrainsMono-OFL.txt" },
}

-- Every statusbar texture in `media/textures/`, keyed by the LSM name it registers under -- which is
-- also the name a player sees in a bar-texture dropdown and the string a profile stores. `file` is
-- the basename; there is no per-file license row because unlike the icons and the font, nothing here
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
-- seven and a player switching between them gets a different line, never a different-shaped widget.
lib.TEXTURES = {
  ["Ka0s Gradient"]    = { file = "gradient.tga" },
  ["Ka0s Underline 1"] = { file = "underline-1.tga" },
  ["Ka0s Underline 2"] = { file = "underline-2.tga" },
  ["Ka0s Underline 4"] = { file = "underline-4.tga" },
  ["Ka0s Overline 1"]  = { file = "overline-1.tga" },
  ["Ka0s Overline 2"]  = { file = "overline-2.tga" },
  ["Ka0s Overline 4"]  = { file = "overline-4.tga" },
}

-- Answering a lookup with a set rather than a linear scan of ICONS. Built once, from the array, so
-- the array stays the single place a name is written down.
local KNOWN_ICON = {}
for i = 1, #lib.ICONS do KNOWN_ICON[lib.ICONS[i]] = true end

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
--- @param addonName string  the consumer's own addon folder name (its first vararg)
--- @param name string       an entry of `lib.ICONS`
--- @param vendorPath string optional, defaults to `lib.VENDOR_PATH`
--- @return string|nil
function lib.Icon(addonName, name, vendorPath)
  if not KNOWN_ICON[name] then return nil end
  local base = root(addonName, vendorPath)
  if not base then return nil end
  return base .. ICON_DIR .. "\\" .. name
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
  local entry = lib.TEXTURES[name]
  if not entry then return nil end
  local base = root(addonName, vendorPath)
  if not base then return nil end
  return base .. TEXTURE_DIR .. "\\" .. (entry.file:gsub("%.tga$", ""))
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

--- Put every shipped font AND statusbar texture into LibSharedMedia under its catalog name.
---
--- WHY REGISTERING MATTERS AND A PATH DOES NOT. A host can draw with `Font(...)` and never touch
--- LSM. What registration buys is the settings panel: an LSM-registered face appears in the font
--- dropdown beside every other font the player has, and a profile can then store the NAME —
--- portable across installs — instead of a path that names one addon's folder and breaks the moment
--- the player renames it.
---
--- IDEMPOTENT, AND THAT IS LSM'S DOING: `Register` for an identical (mediatype, key, path) triple
--- costs nothing, so two consumers each registering the same face at load is not a conflict. Two
--- consumers registering DIFFERENT paths under one key would be — which is precisely the collision
--- this module removes, because every consumer now points at the same bytes under the same name.
---
--- Call it at FILE LOAD rather than at PLAYER_LOGIN. LibSharedMedia is vendored under `libs/` and
--- has therefore already run by the time a TOC reaches the consumer's own files, and a default that
--- names a face LSM has not heard of yet is a default that resolves to nothing.
---
--- @param addonName string  the consumer's own addon folder name
--- @param vendorPath string optional
--- @return number fonts, number statusbars  how many of each registered; 0, 0 when LSM is absent,
---         which is not an error
function lib.RegisterLSM(addonName, vendorPath)
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  if not LSM then return 0, 0 end

  local mt = LSM.MediaType or {}

  local fonts = 0
  for name in pairs(lib.FONTS) do
    local path = lib.Font(addonName, name, vendorPath)
    if path then
      LSM:Register(mt.FONT or "font", name, path)
      fonts = fonts + 1
    end
  end

  -- STATUSBAR, and it is the same bargain the fonts strike. A registered texture is what a player
  -- picks out of a bar-texture dropdown by name, and a NAME is what their profile then stores --
  -- portable between installs, where a path is pinned to one addon's folder and breaks the moment
  -- the folder is renamed.
  local bars = 0
  for name in pairs(lib.TEXTURES) do
    local path = lib.Texture(addonName, name, vendorPath)
    if path then
      LSM:Register(mt.STATUSBAR or "statusbar", name, path)
      bars = bars + 1
    end
  end

  return fonts, bars
end
