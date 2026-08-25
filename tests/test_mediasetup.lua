-- tests/test_mediasetup.lua — core/MediaSetup.lua, the LibKa0s-Media-1.0 seam.
--
-- THE CASE THAT EARNS THIS FILE is the catalog cross-check. Every mark this addon draws is a plain
-- string in modules/, resolved against a catalog that now lives in ANOTHER REPO. If the library
-- renames one, or this addon asks for one it never shipped, the answer is nil, the ladder walks
-- down to the Blizzard art it used to draw, and the control quietly stops being the mark it was --
-- with every suite green, because a texture that does not load draws nothing and raises nothing.
-- The same failure mode retires the ladder's usefulness as a safety net: it is a fallback for a
-- MISSING LIBRARY, not a licence to misspell a name.

local T = _G.LH_TEST
local NS = T.NS
local Loader = T.Loader
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local assertNil = T.assertNil

local VENDORED = "Interface\\AddOns\\LootHistory\\libs\\LibKa0s\\media\\"

-- Every catalog name this addon asks for, in one place, so the cross-check below cannot be told a
-- shorter story than the source. Both halves of every two-state control are listed, because only
-- one is drawn at a time and a test taking the default state would miss the other.
--
--   grep -rhno 'NS\.Icon("[a-z-]*")\|NS\.IconMarkup("[a-z-]*"' core modules settings
--
-- plus the three the row menu names as data (`icon = "..."` in BrowserTable:ShowRowMenu), the one
-- passed as a trailing argument to a button factory ("spreadsheet", on the export window's
-- "Export to CSV" -- the filter bar's Export button is deliberately unmarked), and the three the
-- LIBRARY draws on this addon's behalf once core/DebugLogSetup.lua tells it the folder name.
local DRAWN = {
  -- this addon's own art
  "chevron-down", "chevron-right", "confirm", "lock", "sort-down", "sort-up",
  "ban", "chat", "clear", "spreadsheet",
  -- drawn by LibKa0s on our behalf: Core's close on four windows, DebugLog's strip on two
  "close", "copy",
}

-- ---------------------------------------------------------------------------
-- The seam
-- ---------------------------------------------------------------------------

test("MediaSetup: NS.Icon answers the vendored path, extensionless", function()
  -- Extensionless is not a preference. The client appends the extension, and a path carrying `.tga`
  -- is one of the two spellings that draw nothing -- which matters more here than in most hosts,
  -- because modules/BrowserTable.lua splices these paths into inline `|T...|t` escapes where a bad
  -- path is not even a blank square.
  assertEqual(NS.Icon("close"), VENDORED .. "icons\\close")
end)

test("MediaSetup: an icon the library does not ship answers nil", function()
  -- nil is a value a ladder can branch on. A plausible path to a texture that is not there is a
  -- control that is simply absent, forever, silently.
  assertNil(NS.Icon("nosuchicon"))
end)

test("MediaSetup: NS.MediaFont answers the vendored face, and only a face it ships", function()
  assertEqual(NS.MediaFont("JetBrains Mono"),
    VENDORED .. "fonts\\JetBrainsMono-Regular.ttf")
  assertNil(NS.MediaFont("Comic Sans"))
end)

test("MediaSetup: the font this addon names is the face the library registers", function()
  -- Two names for one thing, in two repos: Constants.FONT_MONO_NAME is the key core/MediaSetup.lua
  -- registers with LibSharedMedia and a profile stores, and the library's FONTS is what carries it.
  -- A name nobody registered renders in Blizzard's proportional fallback, which is the exact
  -- outcome shipping a monospace face was meant to prevent.
  local Media = T.mocks.LibStub("LibKa0s-Media-1.0", true)
  assertTrue(Media ~= nil, "the vendored library did not load")
  assertTrue(Media.FONTS[NS.Constants.FONT_MONO_NAME] ~= nil,
    "FONT_MONO_NAME is '" .. tostring(NS.Constants.FONT_MONO_NAME)
    .. "', which the library's FONTS does not carry")
  assertEqual(NS.Constants.FONT_MONO, NS.MediaFont(NS.Constants.FONT_MONO_NAME))
end)

test("MediaSetup: the font no longer resolves inside this addon's own folder", function()
  -- media/fonts/ is deleted. A path still pointing there would load nothing and raise nothing --
  -- the debug console would simply render in whatever the client picked.
  assertTrue(NS.Constants.FONT_MONO:find("LootHistory\\media\\fonts", 1, true) == nil,
    "FONT_MONO still names this addon's deleted media folder: " .. NS.Constants.FONT_MONO)
  assertTrue(NS.Constants.FONT_MONO:find("libs\\LibKa0s\\media\\fonts", 1, true) ~= nil)
end)

-- ---------------------------------------------------------------------------
-- The catalog, against what this addon actually asks for
-- ---------------------------------------------------------------------------

test("MediaSetup: every mark this addon draws is one the library ships", function()
  local Media = T.mocks.LibStub("LibKa0s-Media-1.0", true)
  local known = {}
  for _, name in ipairs(Media.ICONS) do known[name] = true end
  for _, name in ipairs(DRAWN) do
    assertTrue(known[name] == true,
      "this addon draws '" .. name .. "', which LibKa0s-Media does not ship")
    assertTrue(NS.Icon(name) ~= nil, "NS.Icon answered nil for " .. name)
  end
end)

test("MediaSetup: every name the library ships has a file in the vendored copy", function()
  -- The library's own suite checks its catalog against its own directory. This checks the COPY: a
  -- re-vendor that dropped a file, or a packaging step that filtered it out, leaves a catalog
  -- naming art this build does not carry.
  local Media = T.mocks.LibStub("LibKa0s-Media-1.0", true)
  local missing = {}
  for _, name in ipairs(Media.ICONS) do
    local fh = io.open("libs/LibKa0s/media/icons/" .. name .. ".tga", "rb")
    if fh then fh:close() else missing[#missing + 1] = name end
  end
  assertEqual(table.concat(missing, ", "), "")
end)

test("MediaSetup: the source names no icon the DRAWN list above has forgotten", function()
  -- The list is the input to two cases above, so a name added to a module and not to the list would
  -- be checked by nothing. This closes that: it re-derives the names from the source and compares.
  local drawn = {}
  for _, name in ipairs(DRAWN) do drawn[name] = true end
  local unlisted = {}
  for _, file in ipairs({ "modules/Browser.lua", "modules/BrowserTable.lua", "modules/Export.lua",
                          "core/Constants.lua", "core/CoreSetup.lua", "core/DebugLogSetup.lua" }) do
    local src = Loader.readFile(file)
    for name in src:gmatch('NS%.Icon%("([a-z%-]+)"%)') do
      if not drawn[name] then unlisted[#unlisted + 1] = file .. ": " .. name end
    end
    for name in src:gmatch('NS%.IconMarkup%("([a-z%-]+)"') do
      if not drawn[name] then unlisted[#unlisted + 1] = file .. ": " .. name end
    end
    for name in src:gmatch('icon = "([a-z%-]+)"') do
      if not drawn[name] then unlisted[#unlisted + 1] = file .. ": " .. name end
    end
  end
  assertEqual(table.concat(unlisted, ", "), "")
end)

-- ---------------------------------------------------------------------------
-- The markup helper
-- ---------------------------------------------------------------------------

test("MediaSetup: a tinted mark spells the long escape, vertex color last", function()
  -- The short form has nowhere to put a color, and an inline texture is NOT reached by the
  -- FontString's SetTextColor -- which is why a gold column header used to carry a white arrow.
  -- 64:64 with bounds 0:64 is the whole texture whatever the file's real size is.
  assertEqual(NS.IconMarkup("sort-up", "Interface\\Buttons\\Arrow-Up-Up", 0, 1, 0.82, 0),
    "|T" .. VENDORED .. "icons\\sort-up:0:0:0:0:64:64:0:64:0:64:255:209:0|t")
  assertEqual(NS.IconMarkup("lock", "Interface\\Buttons\\WHITE8X8", 14, 0.3, 0.82, 0.42),
    "|T" .. VENDORED .. "icons\\lock:14:14:0:0:64:64:0:64:0:64:77:209:107|t")
  -- No color asked for, no color spelled: the untinted call is byte-identical to what it was.
  assertEqual(NS.IconMarkup("lock", "Interface\\Buttons\\WHITE8X8", 14),
    "|T" .. VENDORED .. "icons\\lock:14|t")
end)

test("MediaSetup: NS.IconMarkup splices the extensionless path and never answers nil", function()
  -- `"|T" .. nil` is the second spelling that draws nothing, and the reason `fallback` is required
  -- rather than optional: there is no shape of this call that can come back empty.
  assertEqual(NS.IconMarkup("lock", "Interface\\Buttons\\WHITE8X8"),
    "|T" .. VENDORED .. "icons\\lock:0|t")
  assertEqual(NS.IconMarkup("nosuchicon", "Interface\\Buttons\\WHITE8X8"),
    "|TInterface\\Buttons\\WHITE8X8:0|t")
  assertEqual(NS.IconMarkup("lock", "Interface\\Buttons\\WHITE8X8", 14),
    "|T" .. VENDORED .. "icons\\lock:14|t")
end)

-- ---------------------------------------------------------------------------
-- Degraded
-- ---------------------------------------------------------------------------

test("MediaSetup: with no library there is no art and no face, and that is not an error", function()
  -- Both are INSIDE the payload that is missing, so a degraded install has neither. NS.Icon
  -- answering nil is what sends every art site down to the Blizzard texture it drew before, and
  -- NS.MediaFont answering nil is what core/Constants.lua turns into STANDARD_TEXT_FONT -- a real
  -- client font, because SetFont on a path that is not there simply does not draw.
  local mocks = dofile("tests/wow_mock.lua")()
  local ns = {}
  Loader.loadAll(Loader.tocFiles("LootHistory.toc"), ns, mocks)
  assertNil(ns.Icon("close"))
  assertNil(ns.MediaFont("JetBrains Mono"))
  assertEqual(ns.Constants.FONT_MONO, mocks.STANDARD_TEXT_FONT)
  assertEqual(ns.IconMarkup("lock", "Interface\\Buttons\\WHITE8X8"),
    "|TInterface\\Buttons\\WHITE8X8:0|t")
end)
