-- LibKa0s-IconBrowser-1.0 — IconBrowserSources.lua: what the icon browser offers, tab by tab, and
-- what each icon is called. Pure: it reads the Media major's catalog and, at call time, the client's
-- macro icon lists, and draws nothing.
--
-- Promoted from Ka0s Quick Comms (`settings/IconBrowser_Sources.lua`, the glyph helpers of
-- `modules/Library.lua` and `Compat.MacroIcons`), because Outfitter Reborn wants the same browser
-- with the same semantics (library-stack-§7, *What earns promotion*). What changed on the way in is
-- that a TAB IS A DESCRIPTOR rather than a key the module knows, so a host can add tabs of its own
-- and hide built-in ones:
--
--     {
--       key     = string,                 -- unique within the tabs
--       label   = string,                 -- the strip's text
--       tooltip = string?,                -- the strip's tooltip
--       list    = function(filter) -> icons, loaded
--                                         -- `icons` a list of icon VALUES (a texture path, or a
--                                         -- texture id); `loaded` false while the client has not
--                                         -- answered yet (nil reads as true)
--       name    = function(icon) -> string?   -- what the tab calls an icon (nil: the default)
--       search  = function(icon) -> string?   -- the text a search reads (nil: name, else the id)
--       owns    = function(icon) -> bool      -- whether a stored icon opens on this tab
--       swatch  = bool,                   -- the tab's icons take a color (glyphs)
--     }
--
-- THE THREE BUILT-INS (IB.BUILTIN_TABS, in order) are descriptors too:
--
--     markers    the eight raid target markers
--     game       every icon the macro icon selector offers (IB.MacroIcons: spells, then items), as
--                texture ids, filtered "all" / "spells" / "items"
--     glyphs     every icon of the Media catalog, white on transparent so each takes a color,
--                filtered "all" or one of the catalog's sets (Media.ICON_SETS); swatch = true
--
-- `Sources.Tabs(spec)` builds what a host is offered: `spec.tabs` first, in the host's order, then
-- the built-ins `spec.hide` does not name. A host tab carrying a built-in's key replaces it. The
-- glyph tab's paths carry the host's folder (`spec.owner`, its first vararg), because the library is
-- vendored and cannot know which folder it was copied into (Media.lua, *Why this takes an addon
-- name*). The built-ins are built once per owner and locale table, so a descriptor keeps its
-- identity for the session and the search memo below holds across opens.
--
-- Each list is of icon VALUES, never a table per icon: the game list holds thousands.
--
-- THE GAME LIST is read on first use and kept only once the client answers with icons: until its
-- own icon list has loaded the client answers with none, so an empty answer is asked again next
-- time (`list`'s second value).
--
-- A SET'S PREFIX ("ph:", "gi:") is part of a glyph's catalog key, never of its label: "ph:arrow-up"
-- reads "Arrow up", and Credit names the set (and a Game-icons mark's author) instead.
--
-- SEARCH (Sources.Search) is a case-insensitive plain substring over what an icon is called on its
-- tab: a marker's name, a glyph's catalog key and its shown label, a game icon's texture id (its
-- digits; a texture path by its file name), a host tab's `search` text, else its `name`, else the
-- id's digits. The client has no API that names a game icon from its texture id.
--
-- THE GLYPH HELPERS (IB.IsGlyph, IB.ValidColor, IB.ColorFrom, IB.Tint) are the stored shape of a
-- glyph pick: the glyph's path, and its color as six lowercase hex digits, or none for white.
--
-- Depends on LibStub, LibKa0s-Core-1.0 and LibKa0s-Media-1.0, and on no addon framework.
-- LibKa0s-Compat-1.0 is read at call time when present, for its secret guard.
--
-- Minor 1: the major's first file. Sources.Tabs / TabFor / List / Label / Search / Credit / SetOf /
-- Glyphs / GlyphSets / GlyphLabel / GameIcons / Markers / MarkerPath, IB.MacroIcons and the glyph
-- helpers, lib.STRINGS.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local Media = LibStub and LibStub("LibKa0s-Media-1.0", true)
local NEEDS_CORE, NEEDS_MEDIA = 1, 5   -- Media minor 5: the icon sets and their prefixes
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent
if not Media or (Media.MINOR or 0) < NEEDS_MEDIA then return end

local MAJOR, MINOR = "LibKa0s-IconBrowser-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.IconBrowserSources = MINOR

lib.BUILTIN_TABS = { "markers", "game", "glyphs" }

-- Every word this file can show. A literal table, as every other major's is: the library carries no
-- locale, and a host that wants its own words passes `spec.L` keyed to these.
lib.STRINGS = {
  TAB_MARKERS     = "Markers",
  TAB_MARKERS_TIP = "The eight raid target markers.",
  TAB_GAME        = "Game icons",
  TAB_GAME_TIP    = "Every icon the macro icon picker offers.",
  TAB_GLYPHS      = "Glyphs",
  TAB_GLYPHS_TIP  = "Every LibKa0s glyph. A glyph is drawn in the color you pick.",
  TEXTURE_ID      = "Texture id %d",
  CREDIT          = "%s, by %s",
  -- The raid markers, in their index order.
  MARKER_1 = "Star", MARKER_2 = "Circle", MARKER_3 = "Diamond", MARKER_4 = "Triangle",
  MARKER_5 = "Moon", MARKER_6 = "Square", MARKER_7 = "Cross", MARKER_8 = "Skull",
  -- The icon sets, by id.
  SET_OPEN_ICONIC = "Open Iconic",
  SET_PHOSPHOR    = "Phosphor",
  SET_GAME_ICONS  = "Game-icons",
  -- The curated glyphs' labels (GLYPH_LABELS below).
  GLYPH_CHAT = "Chat", GLYPH_SPEECH_BUBBLE = "Speech bubble", GLYPH_WARNING = "Warning",
  GLYPH_INFO = "Information", GLYPH_HELP = "Help", GLYPH_TARGET = "Target", GLYPH_SHIELD = "Shield",
  GLYPH_HEART = "Heart", GLYPH_STAR = "Star", GLYPH_MAP_MARKER = "Map marker",
  GLYPH_LOCATION = "Location", GLYPH_PEOPLE = "People", GLYPH_PERSON = "Person",
  GLYPH_TIMER = "Timer", GLYPH_BAN = "Ban", GLYPH_THUMB_UP = "Thumbs up",
}

-- The glyph tab's default label map: catalog name -> lib.STRINGS key. Every other catalog glyph
-- (most of it is window chrome: close, sort, align) is labeled from its name (GlyphLabel). A name
-- the catalog drops simply loses its label.
lib.GLYPH_LABELS = {
  chat = "GLYPH_CHAT", ["speech-bubble"] = "GLYPH_SPEECH_BUBBLE", warning = "GLYPH_WARNING",
  info = "GLYPH_INFO", help = "GLYPH_HELP", target = "GLYPH_TARGET", shield = "GLYPH_SHIELD",
  heart = "GLYPH_HEART", star = "GLYPH_STAR", ["map-marker"] = "GLYPH_MAP_MARKER",
  location = "GLYPH_LOCATION", people = "GLYPH_PEOPLE", person = "GLYPH_PERSON",
  timer = "GLYPH_TIMER", ban = "GLYPH_BAN", ["thumb-up"] = "GLYPH_THUMB_UP",
}

local SET_KEYS = { ["open-iconic"] = "SET_OPEN_ICONIC", phosphor = "SET_PHOSPHOR", ["game-icons"] = "SET_GAME_ICONS" }
local MARKERS = 8

lib.Sources = lib.Sources or {}
local Src = lib.Sources

--- One word, the host's override first. rawget, NOT a plain index: every Ka0s host's locale table
--- answers an unknown key WITH THE KEY, so a plain index would accept that for every key.
local function text(L, key)
  local v = type(L) == "table" and rawget(L, key)
  if type(v) == "string" then return v end
  return lib.STRINGS[key]
end

-- ── the glyph helpers ──────────────────────────────────────────────────────────────────────

-- Media's set folders, by folder, answering the set's prefix ("" for the unfoldered set).
local function prefixOfDir(dir)
  for _, set in ipairs(Media.ICON_SETS or {}) do
    if (set.dir or "") == dir then return set.prefix or "" end
  end
  return nil
end

-- The catalog name a glyph path resolves back from, or nil (see IsGlyph).
local function nameOfPath(v)
  local folder, vendor, rest = v:match("^Interface\\AddOns\\([^\\]+)\\(.-)\\media\\icons\\(.+)$")
  if not folder then return nil end
  local dir, file = rest:match("^([^\\]+)\\([^\\]+)$")
  if not dir then dir, file = "", rest end
  local prefix = prefixOfDir(dir)
  if not prefix then return nil end
  local name = prefix .. file
  if Media.Icon(folder, name, vendor) ~= v then return nil end
  return name
end

-- path -> catalog name, or false: the catalog is fixed for the session, and the glyph tab asks once
-- per icon on every search and hover.
local glyphOf = {}

--- The Media catalog name of icon `v` when it is one of the catalog's glyphs at ANY host's path
--- (white on transparent, so it takes a tint), else nil: a texture id, a raid marker, any other
--- texture. Read from the path rather than a per-owner map, because a stored path carries the
--- folder of the addon that stored it; the answer is checked by building the path back.
--- @return string|nil
function lib.IsGlyph(v)
  if type(v) ~= "string" then return nil end
  local known = glyphOf[v]
  if known ~= nil then return known or nil end
  local name = nameOfPath(v)
  glyphOf[v] = name or false
  return name
end

--- Whether `v` is a stored glyph color: none (nil or false) or six lowercase hex digits.
--- @return boolean ok, string|nil reason
function lib.ValidColor(v)
  if v == nil or v == false then return true end
  if type(v) == "string" and v:match("^%x%x%x%x%x%x$") and v == v:lower() then return true end
  return false, "badColor"
end

--- The stored glyph color for a picked r, g, b (0..1, as the color picker answers): six lowercase
--- hex digits, or false (none) for white, which is how an untinted glyph is drawn. A channel out of
--- range is clamped.
--- @return string|false
function lib.ColorFrom(r, g, b)
  local function byte(v)
    v = tonumber(v) or 1
    return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5)
  end
  local hex = ("%02x%02x%02x"):format(byte(r), byte(g), byte(b))
  if hex == "ffffff" then return false end
  return hex
end

--- A stored color as r, g, b (0..1): white (1, 1, 1) for none or a malformed one. Whoever draws a
--- glyph sets this every time, white included, since a pooled texture keeps the last tint it had.
--- @return number r, number g, number b
function lib.Tint(hex)
  if type(hex) ~= "string" or not lib.ValidColor(hex) then return 1, 1, 1 end
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

-- ── the client's macro icon lists ──────────────────────────────────────────────────────────

-- Compat's secret guard, read once per read of the lists (Compat is optional), else none.
local function secretGuard()
  local compat = LibStub("LibKa0s-Compat-1.0", true)
  if compat and type(compat.IsSecret) == "function" then return compat.IsSecret end
  return function() return false end
end

-- The macro icon selector's readers for `kind`, in the order Blizzard's IconDataProvider calls them
-- (the loose icons first; wow-ui-source@297d7aa:Interface/AddOns/Blizzard_FrameXMLBase/
-- IconDataProvider.lua:16-19), read at call time: each fills the table it is handed (and may return it).
local function macroReaders(kind)
  if kind == "spells" then return { GetLooseMacroIcons, GetMacroIcons } end
  if kind == "items" then return { GetLooseMacroItemIcons, GetMacroItemIcons } end
  return {}
end

-- One reader's list, appended to `out` as plain texture ids. Nothing when the reader is absent,
-- raises, or its list has not loaded yet.
local function readInto(reader, out, isSecret)
  if type(reader) ~= "function" then return end
  local filled = {}
  local ok, returned = pcall(reader, filled)
  if not ok then return end
  if #filled == 0 and type(returned) == "table" then filled = returned end
  for _, v in ipairs(filled) do
    if type(v) == "number" and not isSecret(v) then out[#out + 1] = v end
  end
end

--- The icons the macro icon selector offers, `kind` "spells" (GetLooseMacroIcons, then
--- GetMacroIcons) or "items" (GetLooseMacroItemIcons, then GetMacroItemIcons): texture ids (plain
--- numbers only), repeats kept (GameIcons dedups). A reader that is absent, raises, or has not
--- loaded yet adds nothing.
--- @return number[]
function lib.MacroIcons(kind)
  local out = {}
  -- A list with holes (an absent reader) is walked by index, not ipairs.
  local readers, isSecret = macroReaders(kind), secretGuard()
  for i = 1, 2 do readInto(readers[i], out, isSecret) end
  return out
end

-- ── markers ────────────────────────────────────────────────────────────────────────────────

function Src.MarkerPath(i)
  return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i
end

--- The eight raid target markers' paths, in their index order.
function Src.Markers()
  local out = {}
  for i = 1, MARKERS do out[i] = Src.MarkerPath(i) end
  return out
end

-- ── glyphs ─────────────────────────────────────────────────────────────────────────────────

--- A catalog name's label: the curated one, else the name without its set's prefix, its dashes as
--- spaces and its first letter capitalized ("arrow-circle-down" -> "Arrow circle down",
--- "ph:arrow-up" -> "Arrow up"; not localized). `L` is a host's override of lib.STRINGS.
function Src.GlyphLabel(name, L)
  local key = lib.GLYPH_LABELS[name]
  if key then return text(L, key) end
  local words = (name:match("^%l+:(.+)$") or name):gsub("-", " ")
  return (words:gsub("^%l", string.upper))
end

--- The catalog's sets, in the Media major's order: { id, label, prefix }.
--- @return table[]
function Src.GlyphSets(L)
  local out = {}
  for _, set in ipairs(Media.ICON_SETS or {}) do
    local key = SET_KEYS[set.id]
    out[#out + 1] = { id = set.id, label = key and text(L, key) or set.label, prefix = set.prefix or "" }
  end
  return out
end

-- A catalog name's set id, by its prefix (none: the set whose prefix is empty), or nil.
local function setOfName(name)
  local prefix = name:match("^(%l+:)") or ""
  for _, set in ipairs(Media.ICON_SETS or {}) do
    if (set.prefix or "") == prefix then return set.id end
  end
  return nil
end

-- Each owner's glyph lists by set, built on the first ask and kept: the catalog is fixed for the
-- session, and Search memoizes by list identity, so a list rebuilt per keystroke would miss both of
-- its memos and recompute ~5,800 labels on every one.
local glyphLists = {}

--- The catalog's glyphs' paths at `owner`'s folder, in the catalog's order: every one (`set` nil or
--- "all"), or one set's by its id. Empty without an owner. The same table on every call.
--- @return table
function Src.Glyphs(owner, set)
  if type(owner) ~= "string" or owner == "" then return {} end
  set = set or "all"
  local byOwner = glyphLists[owner]
  if not byOwner then
    byOwner = {}
    glyphLists[owner] = byOwner
  end
  if byOwner[set] then return byOwner[set] end
  local out = {}
  for _, name in ipairs(Media.ICONS) do
    local path = Media.Icon(owner, name)
    if path and (set == "all" or setOfName(name) == set) then out[#out + 1] = path end
  end
  byOwner[set] = out
  return out
end

--- The set id of glyph `icon` (a path), or nil for anything that is no catalog glyph.
--- @return string|nil
function Src.SetOf(icon)
  local name = lib.IsGlyph(icon)
  return name and setOfName(name) or nil
end

--- The set's shown name for glyph `icon`, with its author where the set's license asks for one
--- ("Game-icons, by Lorc"), or nil for anything that is no catalog glyph.
--- @return string|nil
function Src.Credit(icon, L)
  local name = lib.IsGlyph(icon)
  if not name then return nil end
  local id = setOfName(name)
  local label = id
  for _, set in ipairs(Src.GlyphSets(L)) do
    if set.id == id then label = set.label end
  end
  local who = Media.IconAuthor and Media.IconAuthor(name)
  if who then return text(L, "CREDIT"):format(label, who) end
  return label
end

-- ── game icons ─────────────────────────────────────────────────────────────────────────────

-- The client's icon lists, kept once they answered with icons.
local cache = {}

local function source(kind)
  if cache[kind] then return cache[kind] end
  local list = lib.MacroIcons(kind)
  if #list > 0 then cache[kind] = list end
  return list
end

--- The game icons for `filter` ("all", "spells", "items"; default all), spells before items, each
--- once. Second value: false while the client's list has not loaded (it answered with none).
--- @return table icons, boolean loaded
function Src.GameIcons(filter)
  local kinds = { "spells", "items" }
  if filter == "spells" or filter == "items" then kinds = { filter } else filter = "all" end
  local key = "once:" .. filter
  if cache[key] then return cache[key], true end
  -- The loose lists and the full ones overlap, and so may the two kinds: each icon once.
  local out, seen, loaded = {}, {}, true
  for _, kind in ipairs(kinds) do
    for _, v in ipairs(source(kind)) do
      if not seen[v] then
        seen[v] = true
        out[#out + 1] = v
      end
    end
    if not cache[kind] then loaded = false end
  end
  if loaded then cache[key] = out end
  return out, #out > 0
end

-- ── the built-in descriptors ───────────────────────────────────────────────────────────────

local function defaultName(icon, L)
  if type(icon) == "number" then return text(L, "TEXTURE_ID"):format(icon) end
  return tostring(icon or "")
end

local function markerTab(L)
  local names = {}
  for i = 1, MARKERS do names[Src.MarkerPath(i)] = text(L, "MARKER_" .. i) end
  local function name(icon) return names[icon] end
  return {
    key = "markers", label = text(L, "TAB_MARKERS"), tooltip = text(L, "TAB_MARKERS_TIP"),
    list = function() return Src.Markers(), true end,
    name = name,
    search = function(icon) return names[icon] or tostring(icon or "") end,
    owns = function(icon) return names[icon] ~= nil end,
  }
end

local function gameTab(L)
  return {
    key = "game", label = text(L, "TAB_GAME"), tooltip = text(L, "TAB_GAME_TIP"),
    list = function(filter) return Src.GameIcons(filter) end,
    name = function(icon) return defaultName(icon, L) end,
    -- A texture id by its digits; a path, should the client's list carry one, by its file name.
    search = function(icon)
      if type(icon) == "number" then return tostring(icon) end
      icon = tostring(icon or "")
      return icon:match("([^\\/]+)$") or icon
    end,
    owns = function(icon) return type(icon) == "number" end,
  }
end

local function glyphTab(owner, L)
  return {
    key = "glyphs", label = text(L, "TAB_GLYPHS"), tooltip = text(L, "TAB_GLYPHS_TIP"), swatch = true,
    list = function(set) return Src.Glyphs(owner, set), true end,
    name = function(icon)
      local name = lib.IsGlyph(icon)
      return name and Src.GlyphLabel(name, L) or nil
    end,
    -- The catalog key and the shown label, so "thumb-up" and "Thumbs up" both find it.
    search = function(icon)
      local name = lib.IsGlyph(icon)
      if not name then return tostring(icon or "") end
      return name .. "\n" .. Src.GlyphLabel(name, L)
    end,
    owns = function(icon) return lib.IsGlyph(icon) ~= nil end,
  }
end

local BUILD = {
  markers = function(_, L) return markerTab(L) end,
  game = function(_, L) return gameTab(L) end,
  glyphs = glyphTab,
}

-- owner -> L (or the NO_L sentinel) -> key -> descriptor, kept for the session. Not weak: the game
-- and glyph descriptors close over L, and Lua 5.1 has no ephemerons, so a weak key would be held by
-- its own value anyway. A host passes one locale table for the session, so this stays one slot per
-- owner.
local builtins = {}
local NO_L = {}

local function builtin(key, owner, L)
  local byOwner = builtins[owner]
  if not byOwner then
    byOwner = {}
    builtins[owner] = byOwner
  end
  local slot = byOwner[L or NO_L]
  if not slot then
    slot = {}
    byOwner[L or NO_L] = slot
  end
  if not slot[key] then slot[key] = BUILD[key](owner, L) end
  return slot[key]
end

local function validTab(t)
  return type(t) == "table" and type(t.key) == "string" and t.key ~= "" and type(t.list) == "function"
end

-- The host's own tabs, in order: a malformed descriptor is skipped and a repeated key keeps the
-- first. Answers the list and the set of keys it took.
local function hostTabs(tabs)
  local out, taken = {}, {}
  for _, t in ipairs(type(tabs) == "table" and tabs or {}) do
    if validTab(t) and not taken[t.key] then
      taken[t.key] = true
      out[#out + 1] = t
    end
  end
  return out, taken
end

--- The tabs a host is offered, in order: `spec.tabs` (its own descriptors; a malformed one is
--- skipped, a repeated key keeps the first), then the built-ins `spec.hide` does not name and no
--- host tab replaced. `spec.owner` is the host's folder (the glyph tab's paths); `spec.L` its
--- override of lib.STRINGS.
--- @return table[] tabs
function Src.Tabs(spec)
  spec = type(spec) == "table" and spec or {}
  local owner = type(spec.owner) == "string" and spec.owner or ""
  local L = type(spec.L) == "table" and spec.L or nil
  local hide = type(spec.hide) == "table" and spec.hide or {}
  local out, taken = hostTabs(spec.tabs)
  for _, key in ipairs(lib.BUILTIN_TABS) do
    if not taken[key] and not hide[key] then
      taken[key] = true
      out[#out + 1] = builtin(key, owner, L)
    end
  end
  return out
end

--- The key of the first of `tabs` that owns `icon`, or nil (a path no tab lists: a built-in set's
--- spell icon, a typed path). Host tabs come first in `tabs`, so they are asked first.
--- @return string|nil
function Src.TabFor(icon, tabs)
  if icon == nil then return nil end
  for _, t in ipairs(tabs or {}) do
    if type(t.owns) == "function" and t.owns(icon) then return t.key end
  end
  return nil
end

--- The list `tab` shows for `filter`, and whether it is loaded (a descriptor that answers no second
--- value is loaded).
--- @return table icons, boolean loaded
function Src.List(tab, filter)
  local icons, loaded = tab.list(filter)
  return icons or {}, loaded ~= false
end

--- What `tab` calls `icon`: its name there, else "Texture id N" for a texture id, else the path.
--- @return string
function Src.Label(tab, icon)
  local name = tab and type(tab.name) == "function" and tab.name(icon)
  if type(name) == "string" then return name end
  return defaultName(icon, nil)
end

-- What a search on `tab` reads of `icon`, lowercased.
local function searchText(tab, icon)
  local t = type(tab.search) == "function" and tab.search(icon)
  if type(t) ~= "string" then
    t = type(tab.name) == "function" and tab.name(icon)
    if type(t) == "string" and type(icon) == "number" then t = t .. "\n" .. icon end
  end
  if type(t) ~= "string" then t = tostring(icon or "") end
  return t:lower()
end

-- Each list's icons' search text, built the first time a search reads it (a list is searched once
-- per keystroke, and the game list is ~30k icons), weak so a list the tabs drop is collected. And
-- the last search, so a query that holds the last one narrows its results instead of the list.
local textOf = setmetatable({}, { __mode = "k" })
local last = setmetatable({}, { __mode = "k" })

--- The icons of `list` (a tab's, as List answers it) whose text on `tab` holds `query`: case-
--- insensitive, plain text, trimmed. A blank or nil query answers `list` itself.
--- @return table icons
function Src.Search(list, tab, query)
  local q = tostring(query or ""):match("^%s*(.-)%s*$"):lower()
  if q == "" then return list end
  local memo = textOf[list]
  if not (memo and memo.tab == tab) then
    memo = { tab = tab, text = {} }
    textOf[list] = memo
  end
  local cached, from = memo.text, list
  local prev = last[list]
  if prev and prev.tab == tab and prev.n == #list and q:find(prev.q, 1, true) then from = prev.out end
  local out = {}
  for _, v in ipairs(from) do
    local t = cached[v]
    if t == nil then
      t = searchText(tab, v)
      cached[v] = t
    end
    if t:find(q, 1, true) then out[#out + 1] = v end
  end
  last[list] = { tab = tab, n = #list, q = q, out = out }
  return out
end
