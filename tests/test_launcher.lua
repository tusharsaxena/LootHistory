local T = _G.LH_TEST
local NS, Loader = T.NS, T.Loader
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- ── The launcher: the minimap button and the broker plugin, as ONE object (launcher-§1) ────────
--
-- Everything here used to be three functions on modules/Browser.lua. It is `LibKa0s-Launcher-1.0`
-- now, wired from core/LauncherSetup.lua, and the two cases that moved with it kept their names'
-- meaning: the registration happens once, and Reset all settings re-points LibDBIcon at the store's
-- new table.
--
-- ORDER IS LOAD-BEARING INSIDE THIS FILE. The degradation case runs FIRST, while nothing has
-- registered LibDataBroker or LibDBIcon — which is the state every headless run starts in and the
-- state the lifecycle kick already met. The fakes are registered after it and stay behind, inert,
-- for the later suites (every Reset all settings in test_slash reaches Refresh through
-- NS.RefreshLauncher).

local ADDON = "LootHistory"   -- the FOLDER name, which is both registration keys (launcher-§1)

-- ── the icon file (launcher-§4, layout-§4) ────────────────────────────────────────────────────

test("launcher: the 128 logo ships, and it is the uncompressed 32-bit file the client can load",
  function()
    -- anti-pattern #82's subtler half. A `## IconTexture` in the wrong TGA flavour draws NOTHING
    -- and raises nothing, so no runtime gate would ever report it — the header is read here
    -- instead. layout-§4 fixes the format: TGA image type 2 (uncompressed), 32 bpp, 128x128.
    -- red under: an RLE-compressed export (type 10), a 24-bit save, a resize to something else, or
    -- the file simply not being regenerated after the source art changed.
    local f = io.open("media/logos/loothistory.logo.128.tga", "rb")
    assertTrue(f ~= nil, "media/logos/loothistory.logo.128.tga is missing: the launcher and the "
      .. "AddOns list would both draw nothing")
    local header = f:read(18)
    local size = f:seek("end")
    f:close()
    assertEqual(#header, 18, "the file is shorter than a TGA header")
    assertEqual(header:byte(3), 2, "TGA image type must be 2 (uncompressed true-color)")
    assertEqual(header:byte(17), 32, "must be 32 bpp — convert('RGBA') is what makes it so")
    local w = header:byte(13) + header:byte(14) * 256
    local h = header:byte(15) + header:byte(16) * 256
    assertEqual(w, 128, "width")
    assertEqual(h, 128, "height")
    -- 128 * 128 * 4 = 65536 pixel bytes, plus the header and Pillow's footer. An RLE file would be
    -- a fraction of this, which is the other way the format check above can be read.
    assertTrue(size >= 65554, "an uncompressed 128x128 32-bit TGA is ~64 KB, got " .. size)
  end)

test("launcher: the TOC's IconTexture and the LDB object's icon are the SAME file", function()
  -- launcher-§4: one file is the addon's face in three places — the AddOns list, the minimap button
  -- and a broker display — so a player who has seen the addon once recognises it in all three.
  -- red under: a Blizzard icon path or a numeric file id on either side, or the two drifting apart.
  local toc = Loader.readFile("LootHistory.toc")
  local declared = toc:match("##%s*IconTexture:%s*([^\r\n]+)")
  assertTrue(declared ~= nil, "the TOC declares no ## IconTexture")
  declared = declared:gsub("%s+$", "")
  assertEqual(declared, NS.LAUNCHER_ICON, "the TOC and core/LauncherSetup.lua name different files")
  assertTrue(declared:lower():find("media\\logos\\", 1, true) ~= nil,
    "the icon must be the addon's own logo, never a Blizzard path or a file id: " .. declared)
  -- The path the client resolves, mapped back onto the repo, so a rename of the file cannot leave
  -- the TOC pointing at nothing.
  local onDisk = declared:gsub("^Interface\\AddOns\\" .. ADDON .. "\\", ""):gsub("\\", "/")
  local f = io.open(onDisk, "rb")
  assertTrue(f ~= nil, "the TOC names " .. onDisk .. ", which is not in the repo")
  if f then f:close() end
end)

-- ── degradation: a host with neither broker library ───────────────────────────────────────────

test("launcher: with no LibDataBroker / LibDBIcon nothing raises, and the store is still the truth",
  function()
    -- The library resolves both with LibStub(..., true) at REGISTER time and degrades by name, so
    -- a host with neither gets a launcher that reports itself absent rather than one that raises.
    -- This addon's `libs/` carries both, but eleven addons' do not all look alike and the headless
    -- environment loads neither — which is exactly the shape this case wants.
    -- red under: a Register that indexes a nil library, an IsShown that answers from the button
    -- rather than the store, or a SetShown that drops the write when there is nothing to move.
    assertTrue(NS.Launcher ~= nil, "LibKa0s-Launcher-1.0 did not resolve at all")
    assertTrue(NS.Launcher:IsRegistered() == false,
      "nothing has registered LibDataBroker yet, so the launcher cannot be wired")
    assertEqual(NS.Launcher:Register(), false, "Register reports the honest answer, and does not raise")
    assertTrue(NS.Launcher:Object() == nil, "there is no broker object without LibDataBroker")

    -- The STORE is still updated, so the Master-controls checkbox reflects what the player chose
    -- rather than reading `true` because nothing contradicted it.
    local before = NS.db.global.minimap.hide
    assertEqual(NS.Launcher:SetShown(false), false, "the button could not be moved")
    assertEqual(NS.db.global.minimap.hide, true, "but the choice was recorded")
    assertEqual(NS.Launcher:IsShown(), false, "IsShown answers from the store")
    NS.Launcher:SetShown(true)
    assertEqual(NS.db.global.minimap.hide, false)
    NS.db.global.minimap.hide = before

    -- The reset re-point is a no-op rather than an error when there is no button to re-point.
    NS.RefreshLauncher()
  end)

-- ── the wired launcher ────────────────────────────────────────────────────────────────────────

-- The two fakes, registered through the kit's real NewLibrary INSIDE the first wired case rather
-- than at this file's load. That is what keeps the degradation case above honest: a NewLibrary here
-- would run before any test does, and the case that wants a host with neither library would meet
-- both. They stay behind afterwards, inert, for the suites below this one.
local ldb, icons
local registered, shown = {}, {}

local function wireBrokerFakes()
  ldb   = T.mocks.LibStub:NewLibrary("LibDataBroker-1.1", 1)
  icons = T.mocks.LibStub:NewLibrary("LibDBIcon-1.0", 1)
  assertTrue(ldb ~= nil and icons ~= nil, "a suite registered the broker fakes already")
  function ldb.NewDataObject(_, name, obj) obj.__name = name; return obj end
  function ldb.GetDataObjectByName() return nil end
  function icons.Register(_, name, obj, db) registered[#registered + 1] = { name, obj, db } end
  function icons.IsRegistered(_, name) return registered[1] ~= nil and registered[1][1] == name end
  function icons.Show(_, name) shown[#shown + 1] = { name, true } end
  function icons.Hide(_, name) shown[#shown + 1] = { name, false } end
  function icons.Refresh() end
end

test("launcher: ONE object, registered twice, under the addon's FOLDER name — and idempotent",
  function()
    -- launcher-§1. The addon creates a single LibDataBroker object of type "launcher" and hands
    -- THAT object to LibDBIcon; one OnClick, one icon, one label, one identity. The name is the
    -- folder name on both registrations, and that is not cosmetic: LibDBIcon keys the button's
    -- saved position by it.
    -- red under: two objects, a "data source" type (a display would draw an empty value cell beside
    -- the icon forever), a second registration under a different spelling, or a Register that
    -- builds a second button over the first when it is called twice.
    wireBrokerFakes()
    assertEqual(NS.Launcher:Register(), true, "both halves wired")
    assertTrue(NS.Launcher:IsRegistered())

    assertEqual(#registered, 1, "LibDBIcon registers the launcher exactly once")
    assertEqual(registered[1][1], ADDON, "the registration key is the FOLDER name")

    local object = NS.Launcher:Object()
    assertTrue(object ~= nil, "the broker object was not published")
    assertTrue(registered[1][2] == object, "LibDBIcon must hold the SAME object, not a copy")
    assertEqual(object.type, "launcher")
    assertEqual(object.__name, ADDON, "the LDB object carries the folder name too")
    assertEqual(object.icon, NS.LAUNCHER_ICON, "the object wears the addon's own logo")
    assertEqual(object.label, "Ka0s Loot History", "what a broker display prints")
    assertEqual(type(object.OnClick), "function", "there is one click implementation")

    -- The table handed over is the LIVE one, resolved at Register time through the descriptor's
    -- function — not a table captured at file load, which AceDB would have replaced by now.
    assertTrue(registered[1][3] == NS.db.global.minimap,
      "LibDBIcon must hold db.global.minimap itself (launcher-§3)")

    -- Idempotent: a host may call this from OnInitialize and again from a login handler.
    assertEqual(NS.Launcher:Register(), true)
    assertEqual(#registered, 1, "a second Register must not build a second button")
  end)

test("launcher: setup writes nothing into the stored minimap table", function()
  -- architecture-§5 (v2.44.0): `minimap.hide` is a schema row, so a whole-table seed over `minimap`
  -- is a schema-row write ("a row wins"). The AceDB default (defaults/Global.lua) serves the table.
  -- red under: the old `if not mm then mm = { hide = false }; NS.db.global.minimap = mm end` seed
  -- coming back, anywhere.
  assertEqual(NS.defaults.global.minimap.hide, false, "the default the seed duplicated ships")
  local mm = NS.db.global.minimap
  local keys = 0
  for _ in pairs(mm) do keys = keys + 1 end
  assertEqual(keys, 1, "only `hide` is in there; LibDBIcon adds `minimapPos` on a drag, nothing else")
end)

test("launcher: RUNG (a) — left-click toggles the browser, the addon's own switch", function()
  -- launcher-§2. This addon has a PRIMARY WINDOW, so left-click toggles it and the rung is
  -- expressed by the PRESENCE of `onClick` rather than by a flag. The switch is `B:Toggle`, the one
  -- `/lh toggle` calls — the launcher drives the addon's existing state and never holds a copy.
  -- red under: a left-click that opens the settings panel instead (the panel is already on the
  -- right button, so that is a skipped rule rather than a different design — anti-pattern #81), or
  -- a second toggle implementation appearing here.
  local object = NS.Launcher:Object()
  local realToggle, toggles = NS.Browser.Toggle, 0
  NS.Browser.Toggle = function() toggles = toggles + 1 end
  local realOpen, opens = NS.Panel.Open, 0
  NS.Panel.Open = function() opens = opens + 1 end

  local ok, err = pcall(object.OnClick, object, "LeftButton")
  NS.Browser.Toggle, NS.Panel.Open = realToggle, realOpen
  if not ok then error(err, 0) end

  assertEqual(toggles, 1, "left-click must reach NS.Browser:Toggle")
  assertEqual(opens, 0, "left-click must NOT open the settings panel on rung (a)")
end)

test("launcher: right-click ALWAYS opens the settings panel", function()
  -- launcher-§2, on every addon, whatever rung its left click sits on. It is what lets rung (a)
  -- spend the left button on the window.
  -- red under: a right-click wired to anything else at all.
  local object = NS.Launcher:Object()
  local realToggle, toggles = NS.Browser.Toggle, 0
  NS.Browser.Toggle = function() toggles = toggles + 1 end
  local realOpen, opens = NS.Panel.Open, 0
  NS.Panel.Open = function() opens = opens + 1 end

  local ok, err = pcall(object.OnClick, object, "RightButton")
  NS.Browser.Toggle, NS.Panel.Open = realToggle, realOpen
  if not ok then error(err, 0) end

  assertEqual(opens, 1, "right-click must reach NS.Panel:Open")
  assertEqual(toggles, 0, "right-click must not toggle the window")
end)

test("launcher: the Minimap button row moves the real button, through the single write seam",
  function()
    -- launcher-§3, end to end: the row says SHOWN, the store says HIDDEN, and the `set` calls
    -- LibDBIcon's Show/Hide so the button follows the checkbox immediately rather than at the next
    -- reload. Driven through Schema:Set, which is the seam the panel checkbox and `/lh set` both
    -- take (options-ui-§1).
    -- red under: a row that writes the store but never moves the button, or one that moves the
    -- button without recording it.
    local before = NS.db.global.minimap.hide
    local from = #shown

    NS.Schema:Set("minimap.hide", false)
    assertEqual(NS.db.global.minimap.hide, true, "unticked stores hidden")
    assertEqual(#shown, from + 1, "LibDBIcon was not called")
    assertEqual(shown[#shown][1], ADDON)
    assertEqual(shown[#shown][2], false, "the button was hidden")

    NS.Schema:Set("minimap.hide", true)
    assertEqual(NS.db.global.minimap.hide, false)
    assertEqual(shown[#shown][2], true, "the button came back")

    NS.db.global.minimap.hide = before
  end)

test("launcher: Reset all settings re-points LibDBIcon at the new minimap table, so a drag persists",
  function()
    -- Sl:ResetEverything empties db.global and merges fresh defaults back, so `minimap` is a NEW
    -- table afterwards while LibDBIcon's button still holds the old one. A drag before /reload would
    -- write `minimapPos` into that orphan and the position would be lost. The call moved out of
    -- NS.Browser with the rest of the launcher; the library publishes no re-point seam of its own,
    -- so NS.RefreshLauncher reaches LibDBIcon directly.
    -- red under: a ResetEverything that never hands the library the live table.
    local refreshed = {}
    local realRefresh = icons.Refresh
    function icons.Refresh(_, name, db) refreshed[#refreshed + 1] = { name, db } end

    -- The reset empties the shared store, and later suites read state earlier ones seeded (the
    -- migrated schemaVersion, for one), so the store's contents are put back afterwards.
    local g = NS.db.global
    local saved = {}
    for k, v in pairs(g) do saved[k] = v end
    local before = g.minimap
    local ok, err = pcall(NS.Slash.ResetEverything, NS.Slash)
    local live = g.minimap
    icons.Refresh = realRefresh
    for k in pairs(g) do g[k] = nil end
    for k, v in pairs(saved) do g[k] = v end
    if not ok then error(err, 0) end

    assertTrue(live ~= nil and live ~= before, "the reset gives the store a new minimap table")
    assertEqual(#refreshed, 1, "the reset refreshes the LibDBIcon button exactly once")
    assertEqual(refreshed[1][1], ADDON, "registration key")
    assertTrue(refreshed[1][2] == live, "LibDBIcon must be handed the live minimap table")
  end)
