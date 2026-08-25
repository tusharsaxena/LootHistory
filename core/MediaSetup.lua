-- core/MediaSetup.lua
--
-- The LibKa0s-Media-1.0 seam: where this addon's art and its monospace face come from.
--
-- ---------------------------------------------------------------------------
-- THE FONT USED TO BE OURS, AND THAT WAS THE PROBLEM
-- ---------------------------------------------------------------------------
--
-- This addon shipped its own copy of JetBrains Mono under `media/fonts/`, with
-- its own OFL notice beside it, as a ratified exception to the media rule --
-- WoW ships no monospace font object and the debug console and the export copy
-- box both need one. Every other Ka0s addon shipped the same bytes for the same
-- reason, so the collection carried six copies of one typeface: six licences to
-- track, six provenance stories, and six chances for one copy to be replaced and
-- the rest to drift.
--
-- The face now ships inside LibKa0s (`LibKa0s-Media-1.0`) and arrives with the
-- library payload, alongside the icon catalog this addon's windows draw from.
-- The exception is retired: the font is no longer this addon's media, and the
-- comment in core/Constants.lua that used to defend it now points here.
--
-- ---------------------------------------------------------------------------
-- WHY THE LIBRARY HAS TO BE TOLD OUR NAME
-- ---------------------------------------------------------------------------
--
-- A texture path is absolute from `Interface\AddOns\`, and LibKa0s is VENDORED:
-- every consumer has its own copy at its own path, and a copy cannot know which
-- addon folder it was copied into. So the library asks, and this file is where
-- the answer lives -- `addonName`, the first vararg every TOC-loaded file gets.
-- It is the FOLDER name, which is a different question from the frame-name
-- prefix and from the `## Title`, even though this addon happens to answer the
-- first two with the same string.
--
-- ---------------------------------------------------------------------------
-- WHY THIS LOADS BEFORE core/Constants.lua
-- ---------------------------------------------------------------------------
--
-- `Constants.FONT_MONO` is resolved from `NS.MediaFont` at FILE LOAD, so the
-- seam has to be published first. That is why this file's TOC position is
-- load-bearing rather than conventional: move it below core\Constants.lua and
-- every consumer of FONT_MONO silently falls back to the client's own face,
-- with every suite still green.
--
-- ---------------------------------------------------------------------------
-- WHAT A DEGRADED INSTALL GETS
-- ---------------------------------------------------------------------------
--
-- No LibKa0s means no art and no face -- both are inside the payload that is
-- missing. `NS.Icon` answers nil, which every art site in modules/ already
-- treats as "walk down the ladder" (the Blizzard atlases and inline markup this
-- addon drew before still sit under each call), and `NS.MediaFont` answers nil,
-- which core/Constants.lua turns into the client's own STANDARD_TEXT_FONT.
-- Neither is an error: the chrome degrades and every word stays readable.

local addonName, NS = ...

local Media = LibStub and LibStub("LibKa0s-Media-1.0", true)
local floor = math.floor

--- The texture path for one shipped icon, or nil.
---
--- NIL IS A REAL ANSWER, twice over: the library may be absent, and the name may
--- not be one the library ships. Both are the same thing to a caller -- draw
--- something else -- and both are far better than the alternative the library
--- exists to remove, which is a plausible path to a texture that does not load,
--- draws nothing, and raises nothing.
---
--- THE PATH IS EXTENSIONLESS. `Media.Icon` answers `...\media\icons\close`, never
--- `close.tga`; the client appends the extension itself, and a path carrying one
--- is one of the two spellings that draw nothing. That matters here more than in
--- most hosts because modules/BrowserTable.lua splices these paths into inline
--- `|T...|t` markup, where a bad path is not even a blank texture -- it is a
--- silently swallowed escape.
---
--- The library's third parameter is an optional vendorPath override, deliberately
--- not forwarded: this addon vendors LibKa0s at the standard `libs\LibKa0s`, so
--- there is nothing to override, and a wrapper with a parameter no caller can
--- reach is a parameter nobody maintains. (Contrast NS.MakeCloseButton in
--- core/CoreSetup.lua, whose third argument is REQUIRED and must be passed.)
---
--- @param name string  an entry of the library's `ICONS` catalog, e.g. "close"
--- @return string|nil
function NS.Icon(name)
    if not Media then return nil end
    return Media.Icon(addonName, name)
end

--- The path of one shipped font face, or nil when the library is absent.
---
--- Same optional-vendorPath reasoning as NS.Icon above.
---
--- @param name string  a key of the library's `FONTS`, e.g. "JetBrains Mono"
--- @return string|nil
function NS.MediaFont(name)
    if not Media then return nil end
    return Media.Font(addonName, name)
end

--- One icon spliced into an inline `|T...|t` escape, with a Blizzard texture behind it.
---
--- THE MARKUP PATH IS THE FIDDLY ONE and it earns a shared helper. Three files splice art into
--- strings here -- the multi-select tick, the column sort arrows, the group-header disclosure and
--- the Bound legend -- and both spellings that draw nothing are easy to write by hand: a path
--- carrying `.tga`, and `"|T" .. nil`, which is not a blank square but a raised error or a
--- swallowed escape that quietly costs a label its mark. `fallback` is REQUIRED for that reason:
--- there is no shape of this call that can answer nil.
---
--- COLOR IS OPTIONAL AND, WHEN GIVEN, CHANGES THE ESCAPE'S SHAPE. An inline texture is drawn
--- white and is untouched by the FontString's SetTextColor, so a gold header label carries a
--- white arrow unless the tint is baked into the escape itself. The `|T` escape takes vertex
--- color as its last three fields, but only in the LONG form -- every field up to them must be
--- spelled out, which is why the tinted branch writes offsets and texel bounds the short form
--- leaves implicit. `64:64` with bounds `0:64` is the whole texture whatever the file's real
--- dimensions are: the bounds are read against the width and height declared right here.
---
--- NOT CreateTextureMarkup: its ninth and tenth arguments are xOffset/yOffset, NOT color. Passing
--- 0-255 color there is a silent bug -- the mark keeps its white tint and is flung up to 255px
--- away from the text it belongs to, which is exactly what the Bound legend used to do.
---
--- @param name string      an entry of the library's ICONS catalog
--- @param fallback string  the Blizzard texture path to draw when the seam answers nil
--- @param size number|nil  pixels; 0 (the default) means "the line height"
--- @param r number|nil     vertex tint, 0-1; when nil the mark draws in its own colors
--- @param g number|nil
--- @param b number|nil
--- @return string
function NS.IconMarkup(name, fallback, size, r, g, b)
    local path, px = NS.Icon(name) or fallback, size or 0
    if not r then return "|T" .. path .. ":" .. px .. "|t" end
    return ("|T%s:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t"):format(
        path, px, px, floor(r * 255 + 0.5), floor((g or 0) * 255 + 0.5), floor((b or 0) * 255 + 0.5))
end

-- REGISTERED AT FILE LOAD, not at PLAYER_LOGIN, and this addon is the reason the
-- distinction is worth writing down: the registration used to live in
-- core/LootHistory.lua's OnInitialize, which runs at ADDON_LOADED, long after
-- core/Constants.lua has already resolved a path and settings/Schema.lua has
-- already built its rows. LibSharedMedia is vendored under libs/ and has
-- therefore run by the time the TOC reaches core/, so there is nothing to wait
-- for and a deferred call only opens a window in which a stored default names a
-- face LSM has never heard of.
--
-- What registration buys over the bare path is the settings panel: a registered
-- face appears in the font dropdown beside every other font the player has, and
-- a profile then stores the NAME -- portable across installs -- rather than a
-- path naming one addon's folder. The library's call is idempotent and points
-- every consumer at one set of bytes under one key, which is what makes two Ka0s
-- addons registering "JetBrains Mono" agree rather than collide.
if Media then Media.RegisterLSM(addonName) end
