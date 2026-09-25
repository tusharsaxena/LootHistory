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
    -- anti-pattern #82's subtler half. A `## IconTexture` in the wrong TGA flavor draws NOTHING
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
  -- and a broker display — so a player who has seen the addon once recognizes it in all three.
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

test("launcher: the stored minimap table is the declared default, unseeded and unreplaced",
  function()
  -- architecture-§5 (v2.44.0): `minimap.hide` is the stored key of a schema row (the row's path is
  -- `minimap.shown`), so a whole-table seed over `minimap` is a schema-row write ("a row wins"). AceDB's declared default (defaults/Global.lua) serves the
  -- table; nothing in the addon may write one over it.
  --
  -- WHAT THIS CATCHES, stated exactly, because the version of it that shipped with the launcher
  -- claimed more. It said "red under: the old `if not mm then mm = { hide = false }` seed coming
  -- back" while asserting only that the live table has one key -- and that seed writes exactly one
  -- key, so the case stayed green through the regression it named. Injecting that seed and watching
  -- this case pass is how that was established.
  --
  -- The seed is NOT reachable from here: the descriptor's `minimap` resolver is resolved ONCE, at
  -- Register time during load (launcher-§1), and the descriptor is inline in Launcher:New with no
  -- test seam. Driving Register again returns early (idempotent) and IsShown reads the already
  -- resolved table, so neither re-enters the resolver. Both were tried against the injected seed
  -- and both stayed green.
  --
  -- So this case asserts what IS observable after a full load, and no more: the table AceDB
  -- declared is the one in the store, carrying only `hide`. That catches a second key or a
  -- replacement table; it does not catch a seed that reproduces the default exactly. The case above
  -- carries the other half -- LibDBIcon holds `db.global.minimap` ITSELF, so a resolver handing
  -- over a replacement is caught there.
  assertEqual(NS.defaults.global.minimap.hide, false, "the default the seed duplicated ships")
  local mm = NS.db.global.minimap
  assertTrue(mm ~= nil, "the declared default materialises the table")
  local keys = 0
  for _ in pairs(mm) do keys = keys + 1 end
  assertEqual(keys, 1, "only `hide` is in there; LibDBIcon adds `minimapPos` on a drag, nothing else")
end)

--- Strip WoW color escapes, so a line reads as the player reads it.
local function plain(s)
  return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

--- Draw the launcher's tooltip into a fake GameTooltip and answer its lines, as plain text.
local function tooltipLines()
  local object = NS.Launcher:Object()
  assertTrue(object ~= nil and type(object.OnTooltipShow) == "function",
    "the broker object must carry the library's OnTooltipShow")
  local lines = {}
  local tt = { AddLine = function(_, text) lines[#lines + 1] = plain(text) end }
  object.OnTooltipShow(tt)
  return lines
end

--- Run `fn` with the lock, the test mode and the enabled switch set as asked, then put them back.
local function withState(state, fn)
  local s = NS.db.global.settings
  local BT = NS.BrowserTable
  local was = { locked = s.locked, test = BT.testMode, enabled = NS.Schema:Get("settings.enabled") }
  s.locked = state.locked
  BT.testMode = state.test
  NS.Schema:Set("settings.enabled", state.enabled)
  local ok, res = pcall(fn)
  s.locked, BT.testMode = was.locked, was.test
  NS.Schema:Set("settings.enabled", was.enabled)
  if not ok then error(res, 0) end
  return res
end

local function recordLine()
  local n = (NS.Database and NS.Database.Count) and NS.Database:Count() or 0
  return n == 1 and "1 record" or (n .. " records")
end

-- ── the two buttons (Launcher minor 4, LibKa0s v1.58.0; launcher-§2 as of standard v2.67.0) ─────
--
-- The owner's M6 ruling: LEFT-click opens the settings panel on every addon, in either state, and
-- RIGHT-click opens the client's context menu with one checkbox per toggle the addon has. This
-- addon has all four -- Enabled, Locked, Test mode, Show window (ADDONS.md's row) -- and every entry
-- toggles through the addon's OWN handler: the slash verb's function for Enabled, Test mode and
-- Show window, and the *Lock frame* row's write for Locked (there is no lock verb here).
--
-- The menu is driven through the library's own `MenuUtil` stand-in, tests/mock_menu.lua (copied
-- verbatim from LibKa0s v1.58.0). It is installed only inside the cases that want it: with no
-- `MenuUtil` in the environment the right click takes the library's degraded path, which is a
-- checkable fact of its own and what every other suite (test_disabled's step 8 included) meets.

local MENU = dofile("tests/mock_menu.lua")(T.mocks)
MENU.remove()

local SPIED_VERBS = { enable = true, disable = true, test = true, toggle = true }

--- Run `fn(calls)` with the panel opener and the four verbs the menu reaches replaced by counters,
--- IN NS.COMMANDS ITSELF -- the table `/lh <verb>` dispatches through -- so a case can tell a toggle
--- that runs the verb from one that reaches past it into the model (B:Toggle, CliSet) and would
--- therefore skip the verb's gate and its chat line. Everything is put back, raise or not.
local function withSpies(fn)
  local calls = { open = 0, verbs = {} }
  local realOpen = NS.Panel.Open
  NS.Panel.Open = function() calls.open = calls.open + 1 end
  local saved = {}
  for _, entry in ipairs(NS.COMMANDS) do
    local verb = entry[1]
    if SPIED_VERBS[verb] then
      saved[entry] = entry[3]
      entry[3] = function() calls.verbs[#calls.verbs + 1] = verb end
    end
  end
  local ok, err = pcall(fn, calls)
  NS.Panel.Open = realOpen
  for entry, run in pairs(saved) do entry[3] = run end
  if not ok then error(err, 0) end
end

--- Open the options menu the way a player does -- a right click on the object -- and answer the
--- menu the mock recorded. `windowShown` stands in for the History window's visibility.
local function openMenu(windowShown)
  local realGet = NS.Browser.GetWindow
  NS.Browser.GetWindow = function() return { IsShown = function() return windowShown and true or false end } end
  MENU.install()
  MENU.reset()
  local object, owner = NS.Launcher:Object(), { name = "LootHistoryMinimapButton" }
  local ok, err = pcall(object.OnClick, owner, "RightButton")
  MENU.remove()
  NS.Browser.GetWindow = realGet
  if not ok then error(err, 0) end
  assertEqual(MENU.opens, 1, "a right click must open the context menu exactly once")
  assertTrue(MENU.last.owner == owner, "the menu anchors to the frame that was clicked")
  return MENU.last
end

test("launcher: left-click opens the settings panel, enabled or disabled, and does nothing else",
  function()
    -- launcher-§2 (v2.67.0): the panel is setup, not a feature, and it is where a disabled addon
    -- is switched back on, so the left button is never refused.
    -- red under: the retired rung (a) coming back (a left click reaching `/lh toggle`), or the
    -- retired disabled refusal (a line printed and no panel).
    withSpies(function(calls)
      local object = NS.Launcher:Object()
      withState({ locked = false, test = false, enabled = true }, function()
        object.OnClick(object, "LeftButton")
      end)
      withState({ locked = false, test = false, enabled = false }, function()
        object.OnClick(object, "LeftButton")
      end)
      assertEqual(calls.open, 2, "left-click must reach NS.Panel:Open in both states")
      assertEqual(#calls.verbs, 0, "left-click must run no verb: " .. table.concat(calls.verbs, ", "))
    end)
  end)

test("launcher: right-click with no client menu API degrades to the settings panel", function()
  -- The library resolves MenuUtil on every right click; a client without it gets the panel, which
  -- holds every toggle the menu would have. The headless environment has none unless a case
  -- installs the stand-in.
  -- red under: an unguarded MenuUtil (a raise inside the client's click dispatch), or a right click
  -- that falls through to nothing.
  withSpies(function(calls)
    local object = NS.Launcher:Object()
    object.OnClick(object, "RightButton")
    assertEqual(calls.open, 1, "with no MenuUtil the right click must open the panel")
    assertEqual(#calls.verbs, 0)
  end)
end)

test("launcher: right-click opens the options menu — the brand title, then the four entries in order",
  function()
    -- launcher-§2: Enabled, Locked, Test mode, Show window, each a checkbox showing the state read
    -- when the menu opened; the title is the plain-text label (launcher-§1).
    -- red under: a missing pair (an entry the addon has but does not offer), an entry this addon does
    -- not have, a different order, or a checkmark read from a cached value.
    local menu = withState({ locked = true, test = false, enabled = true }, function()
      return openMenu(true)
    end)
    assertEqual(#menu.titles, 1)
    assertEqual(menu.titles[1], NS.BRAND, "the menu's title is the plain-text label")
    local texts = menu:Texts()
    local want = { "Enabled", "Locked", "Test mode", "Show window" }
    assertEqual(#texts, #want, "the menu lists exactly four entries: " .. table.concat(texts, " / "))
    for i, w in ipairs(want) do assertEqual(texts[i], w, "menu entry " .. i) end
    for _, e in ipairs(menu.entries) do assertTrue(e.enabled, e.text .. " must be live while enabled") end
    assertEqual(menu:Checked("Enabled"), true)
    assertEqual(menu:Checked("Locked"), true, "Locked reads settings.locked when the menu opens")
    assertEqual(menu:Checked("Test mode"), false, "Test mode reads BrowserTable.testMode")
    assertEqual(menu:Checked("Show window"), true, "Show window reads the History window's IsShown")

    menu = withState({ locked = false, test = true, enabled = true }, function()
      return openMenu(false)
    end)
    assertEqual(menu:Checked("Locked"), false, "the next open reads the lock afresh")
    assertEqual(menu:Checked("Test mode"), true, "the next open reads the test mode afresh")
    assertEqual(menu:Checked("Show window"), false, "the next open reads the window afresh")
  end)

test("launcher: each menu entry toggles through the addon's own handler, once", function()
  -- launcher-§2: the menu holds no state and has no handler of its own. Enabled runs `/lh disable`
  -- (or `enable`), Test mode runs `/lh test`, Show window runs `/lh toggle` -- the functions in
  -- NS.COMMANDS, spied in place -- and Locked writes the *Lock frame* row's own path through the
  -- single write seam, because this addon has no lock verb.
  -- red under: a toggle reaching past the verb (B:Toggle or BT:ToggleTestMode called directly skips
  -- the feature-verb gate and the verb's chat line: anti-pattern #81's "copy of the handler"), a
  -- second write of `settings.enabled` beside the verb's, or an entry calling two handlers.
  withSpies(function(calls)
    withState({ locked = false, test = false, enabled = true }, function()
      openMenu(false):Click("Enabled")
      assertEqual(table.concat(calls.verbs, ","), "disable", "Enabled while on runs /lh disable")
      openMenu(false):Click("Test mode")
      assertEqual(table.concat(calls.verbs, ","), "disable,test", "Test mode runs /lh test")
      openMenu(false):Click("Show window")
      assertEqual(table.concat(calls.verbs, ","), "disable,test,toggle", "Show window runs /lh toggle")

      local sets, realSet = {}, NS.Schema.Set
      NS.Schema.Set = function(self, path, v)
        sets[#sets + 1] = { path, v }
        return realSet(self, path, v)
      end
      local ok, err = pcall(function() openMenu(false):Click("Locked") end)
      NS.Schema.Set = realSet
      if not ok then error(err, 0) end
      assertEqual(#sets, 1, "Locked writes once, through the single write seam")
      assertEqual(sets[1][1], "settings.locked", "the Lock frame row's own path")
      assertEqual(sets[1][2], true, "unlocked -> locked")
      assertEqual(NS.db.global.settings.locked, true, "and the lock landed")
      assertEqual(#calls.verbs, 3, "Locked runs no verb")
    end)
    -- The other direction: Enabled while the addon is off runs /lh enable.
    withState({ locked = false, test = false, enabled = false }, function()
      openMenu(false):Click("Enabled")
    end)
    assertEqual(calls.verbs[#calls.verbs], "enable", "Enabled while off runs /lh enable")
    assertEqual(calls.open, 0, "no entry opens the settings panel")
  end)
end)

test("launcher: while disabled, Enabled stays live and the other three are grayed and call nothing",
  function()
    -- launcher-§2 and slash-commands-§7: features refuse while the addon is off, so the menu shows
    -- them grayed with "enable the addon first" rather than hiding them, and Enabled -- the off
    -- switch -- has to work in the off state, as `/lh enable` does.
    -- red under: a grayed entry that still calls its handler (the library's own gate is reached with
    -- ForceClick, as a client that dispatched a grayed entry would), or Enabled grayed with the rest.
    withSpies(function(calls)
      withState({ locked = false, test = false, enabled = false }, function()
        local menu = openMenu(false)
        local texts = menu:Texts()
        local want = { "Enabled", "Locked (enable the addon first)",
          "Test mode (enable the addon first)", "Show window (enable the addon first)" }
        for i, w in ipairs(want) do assertEqual(texts[i], w, "disabled menu entry " .. i) end
        assertTrue(menu:Find("Enabled").enabled, "Enabled stays clickable while off")
        local lockedBefore = NS.db.global.settings.locked
        for _, prefix in ipairs({ "Locked", "Test mode", "Show window" }) do
          assertEqual(menu:Find(prefix).enabled, false, prefix .. " must be grayed while off")
          assertTrue(menu:Click(prefix) == nil, "a grayed entry cannot be clicked")
          menu:ForceClick(prefix)
        end
        assertEqual(#calls.verbs, 0, "a grayed entry must call no handler: " .. table.concat(calls.verbs, ", "))
        assertEqual(NS.db.global.settings.locked, lockedBefore, "a grayed Locked writes nothing")
      end)
    end)
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

    NS.Schema:Set("minimap.shown", false)
    assertEqual(NS.db.global.minimap.hide, true, "unticked stores hidden")
    assertEqual(#shown, from + 1, "LibDBIcon was not called")
    assertEqual(shown[#shown][1], ADDON)
    assertEqual(shown[#shown][2], false, "the button was hidden")

    NS.Schema:Set("minimap.shown", true)
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

-- ── the broker label (launcher-§1, standard v2.54.0) ──────────────────────────────────────────

test("launcher: the broker label is the BRAND NAME in plain text, not the folder name", function()
  -- `label` is the string a broker display prints in its own row, and it prints it beside the other
  -- ten Ka0s addons -- so it is the single field that decides whether the collection reads as one
  -- collection in Titan Panel or as eleven unrelated addons. §1 fixes it at `Ka0s <Name>`.
  -- red under: the folder name ("LootHistory", which a display would file under L while the rest
  -- sit under K), an ad-hoc spelling, or the TOC `## Title` wired through -- a Title MAY carry
  -- color escapes (Ka0s Pretty Chat's does) and one handed to a display that draws the string raw
  -- splatters across a list in which every other row is plain text.
  -- READ THROUGH THE INDIRECTION, because there is one now and pinning the literal would forbid
  -- it. slash-commands-§7's refusal line is built from this same string, so the two are ONE
  -- constant (core/Namespace.lua's NS.BRAND) and the descriptor names it rather than re-typing it.
  -- The file case below is what stops the indirection becoming a place to hide an escaped Title.
  local descriptor = Loader.readFile("core/LauncherSetup.lua")
  assertTrue(descriptor:match("label%s*=%s*NS%.BRAND") ~= nil,
    "the descriptor must take its label from NS.BRAND, not a second spelling")
  local label = NS.BRAND
  assertEqual(label, "Ka0s Loot History", "the LDB label must be the addon's brand name")
  assertTrue(label ~= ADDON, "the folder name is the REGISTRATION name, never the label")
  assertTrue(label:find("|", 1, true) == nil,
    "an escape sequence of any kind is forbidden here: " .. label)
end)

-- ── reset survival (launcher-§3, standard v2.54.0) ────────────────────────────────────────────
--
-- A player's minimap-button choice is a PER-INSTALLATION DISPLAY PREFERENCE and survives a reset,
-- and that is a property of the setting rather than a consequence of where it is stored. Both of
-- this addon's resets reached the row before the exemption landed, and for different reasons:
--
--   * `/lh resetall` and the General page's Defaults button (settings/Panel.lua routes the click to
--     Sl:CliResetAll) walk EVERY schema row through applyDefault.
--   * *Reset all settings* is Sl:ResetEverything, which empties `db.global` wholesale and merges
--     defaults/Global.lua's `minimap = { hide = false }` back -- this addon has no profile, so the
--     scope argument §3 used to rest on never applied here at all.
--
-- Both cases below RUN the reset and read the stored visibility back; a case that only asserted the
-- veto's configuration would pass over a walk that skipped a different row.

--- Run `act` with the account store saved and put back afterwards. Both resets below empty
--- `db.global`, and the suites after this one read state earlier ones seeded.
local function acrossAReset(act)
  local g = NS.db.global
  local saved = {}
  for k, v in pairs(g) do saved[k] = v end
  local ok, err = pcall(act)
  for k in pairs(g) do g[k] = nil end
  for k, v in pairs(saved) do g[k] = v end
  if not ok then error(err, 0) end
end

test("launcher: no BULK reset moves the minimap button — /lh resetall and the page Defaults button",
  function()
    -- The General page's Defaults button reaches this same call (settings/Panel.lua's
    -- P:RestoreDefaults), so one case answers for both surfaces.
    -- red under: an applyDefault that hands `minimap.shown` to the seam like any other row, which is
    -- what this addon shipped -- a player who hid the button found it back on their minimap after
    -- asking for their settings to be reset.
    acrossAReset(function()
      local g = NS.db.global
      NS.Schema:Set("minimap.shown", false)      -- the ROW says shown; the player unticks it
      assertEqual(g.minimap.hide, true, "the player hid the button")

      NS.Slash:CliResetAll()

      assertEqual(g.minimap.hide, true, "/lh resetall must not un-hide the button")
      assertEqual(NS.Schema:Get("minimap.shown"), false, "and the row still reads hidden")
      assertEqual(NS.Launcher:IsShown(), false, "the button itself is still hidden")

      -- The other direction is a rule too: neither reset may RE-HIDE a shown one.
      NS.Schema:Set("minimap.shown", true)
      NS.Slash:CliResetAll()
      assertEqual(g.minimap.hide, false, "a shown button is left shown")

      -- And the veto is scoped to the BULK act: naming the row explicitly still resets it.
      NS.Schema:Set("minimap.shown", false)
      NS.Slash:CliReset("minimap.shown")
      assertEqual(g.minimap.hide, false, "/lh reset minimap.shown is the player naming the row")
    end)
  end)

test("launcher: Reset all settings leaves a hidden button hidden, across the wholesale wipe",
  function()
    -- options-ui-§12's global reset, in the shape it takes for an addon with NO profile: empty the
    -- account-wide store and merge the declared defaults back. The declared default is SHOWN, so
    -- without the carve-out the merge itself is what un-hides the button.
    -- red under: a wipeGlobal that carries nothing across, which is what this addon shipped.
    acrossAReset(function()
      local g = NS.db.global
      NS.Schema:Set("minimap.shown", false)
      assertEqual(g.minimap.hide, true, "the player hid the button")
      local before = g.minimap

      NS.Slash:ResetEverything()

      assertTrue(g.minimap ~= before,
        "the wipe still gives the store a new minimap table, so this is a real carry-across")
      assertEqual(g.minimap.hide, true, "Reset all settings must not un-hide the button")
      assertEqual(NS.Launcher:IsShown(), false, "the button itself is still hidden")
      assertEqual(#NS.db.global.history, 0, "and the reset still did everything else it does")
    end)
  end)

test("launcher: RESET_EXEMPT maps the row path to the stored path, and both resets honor it",
  function()
    -- launcher-§3 (standard v2.65.0) renamed the row to `minimap.shown` while the stored key stays
    -- `minimap.hide`. The two resets read the exemption on different sides of that split: the bulk
    -- walk's veto is keyed by ROW path, and wipeGlobal carries the STORED path across its raw wipe.
    -- So RESET_EXEMPT is a map `{ [row path] = stored path }`, and each reset reads its own side.
    -- red under: the rename landing WITHOUT the map (`{ ["minimap.shown"] = true }`), which is the
    -- regression the map prevents -- wipeGlobal then carries a `shown` path that is never stored,
    -- the merge puts `hide = false` back, and Reset all settings un-hides the button.
    assertEqual(NS.Schema.RESET_EXEMPT["minimap.shown"], "minimap.hide")
    acrossAReset(function()
      local g = NS.db.global
      NS.Schema:Set("minimap.shown", false)
      NS.Slash:ResetEverything()
      assertEqual(g.minimap.hide, true, "Reset all settings keeps the hidden button hidden")
      assertTrue(g.minimap.shown == nil, "and carries no `shown` key into the store")
      NS.Slash:CliResetAll()
      assertEqual(g.minimap.hide, true, "/lh resetall keeps it hidden too")
    end)
  end)

test("launcher: Reset all settings leaves a SHOWN button shown, and does not invent a second key",
  function()
    -- The carry-across must not become a copy of the state. One boolean is stored -- LibDBIcon's own
    -- `hide` -- and the wipe puts that one value back, never a `shown` key beside it.
    -- red under: a carve-out that writes through Schema:Set (a second [Set] line inside a reset that
    -- logs exactly one) or that seeds a parallel key.
    acrossAReset(function()
      local g = NS.db.global
      NS.Schema:Set("minimap.shown", true)
      NS.Slash:ResetEverything()
      assertEqual(g.minimap.hide, false, "a shown button stays shown")
      local keys = 0
      for _ in pairs(g.minimap) do keys = keys + 1 end
      assertEqual(keys, 1, "only `hide` is in there; nothing was invented beside it")
    end)
  end)

-- ── the status tooltip is the LIBRARY's (Launcher minor 3, launcher-§1, M5; hints fixed at minor 4, M6) ──
--
-- Launcher minor 3 (LibKa0s v1.57.0) DRAWS the tooltip, on every host and while the addon is
-- disabled: the title with the version, Enabled, Locked and Test mode where the host has them, the
-- host's own lines, then the two click hints -- fixed since minor 4 (LibKa0s v1.58.0) at
-- `Left-click: Open settings` and `Right-click: Options menu`, in either state. This addon used to
-- draw the whole tooltip itself, and under minor 3 every line would be drawn twice (anti-pattern
-- #89). The cases below pin what is left: the descriptor answers the library's questions, and
-- `onTooltipShow` adds the record count and nothing else.

test("launcher: the enabled tooltip is the library's block, with the addon's one line inside it",
  function()
    -- launcher-§1 (standard v2.66.0): the exact shape, in order. The title carries the TOC version,
    -- Locked and Test mode are drawn because this addon HAS both (the Lock frame row and the
    -- History window's test mode), the record count is this addon's own line, and the two hints are
    -- the library's fixed pair (launcher-§2, v2.67.0).
    -- red under: the old hand-drawn title or hints coming back (a second copy, anti-pattern #89), a
    -- missing isLocked / isTestMode / version, or the count line going missing.
    local lines = withState({ locked = false, test = false, enabled = true }, tooltipLines)
    local want = {
      NS.BRAND .. "  v" .. NS.Version(),
      "Enabled: Yes",
      "Locked: No",
      "Test mode: Off",
      recordLine(),
      "Left-click: Open settings",
      "Right-click: Options menu",
    }
    assertEqual(#lines, #want, "the tooltip draws exactly seven lines: " .. table.concat(lines, " / "))
    for i, w in ipairs(want) do assertEqual(lines[i], w, "tooltip line " .. i) end
    assertTrue(Loader.readFile("core/LauncherSetup.lua"):find('"Ka0s Loot History"', 1, true) == nil,
      "core/LauncherSetup.lua must not re-type the brand string")
  end)

test("launcher: Locked and Test mode are read on every show, never cached", function()
  -- The accessors are the ones the Master-controls rows read: `settings.locked` in the store, and
  -- BrowserTable.testMode (the session-only `state.testMode` row's own get).
  -- red under: a value captured at Register time, or an accessor reading some other copy.
  local lines = withState({ locked = true, test = true, enabled = true }, tooltipLines)
  assertEqual(lines[3], "Locked: Yes", "the lock is read from settings.locked on this show")
  assertEqual(lines[4], "Test mode: On", "the test mode is read from BrowserTable.testMode")
  lines = withState({ locked = false, test = false, enabled = true }, tooltipLines)
  assertEqual(lines[3], "Locked: No")
  assertEqual(lines[4], "Test mode: Off")
end)

test("launcher: while disabled the tooltip still shows, says Enabled: No, and keeps the same hints",
  function()
    -- The owner's rulings: the button ALWAYS answers a hover, disabled included (M5), and neither
    -- button is refused while off (M6) -- the left opens the panel, the right opens the menu with
    -- Enabled live -- so the hints are the enabled tooltip's, word for word.
    -- red under: the retired `Left-click: disabled — /lh enable` pointer coming back, the addon's
    -- own refusal line drawn, or the status block missing while off.
    local lines = withState({ locked = false, test = false, enabled = false }, tooltipLines)
    local want = {
      NS.BRAND .. "  v" .. NS.Version(),
      "Enabled: No",
      "Locked: No",
      "Test mode: Off",
      recordLine(),
      "Left-click: Open settings",
      "Right-click: Options menu",
    }
    assertEqual(#lines, #want, "the disabled tooltip draws exactly seven lines: "
      .. table.concat(lines, " / "))
    for i, w in ipairs(want) do assertEqual(lines[i], w, "disabled tooltip line " .. i) end
  end)

test("launcher: the descriptor answers the library's questions, and every toggle is the addon's own",
  function()
    -- Re-run core/LauncherSetup.lua against a fake Launcher that records the descriptor, into a
    -- scratch namespace, so the fields the library reads are asserted rather than inferred.
    -- red under: a retired field still passed (onClick, leftClickLabel, disabledLine, slash --
    -- dead configuration, launcher-§5), half a pair (the library draws no entry for it), a toggle
    -- that reaches past the verb into the model, a minor-3 field reading a cached value, or an
    -- onTooltipShow that draws a title, a status line or a click hint again.
    local captured
    local fakeLauncher = { New = function(_, d) captured = d; return {} end }
    local fakeLibStub = setmetatable({}, { __call = function(_, name)
      if name == "LibKa0s-Launcher-1.0" then return fakeLauncher end
    end })
    local mocks = setmetatable({ LibStub = fakeLibStub }, { __index = T.mocks })
    local off, locked, opens, winShown = false, false, 0, false
    local ran, sets = {}, {}
    local function verb(name) return { name, name, function() ran[#ran + 1] = name end } end
    local ns = {
      BRAND = NS.BRAND,
      L = setmetatable({}, { __index = function(_, k) return k end }),
      Version = function() return "7.7.7" end,
      AddonIsOff = function() return off end,
      Panel = { Open = function() opens = opens + 1 end },
      Schema = { Set = function(_, path, v) sets[#sets + 1] = { path, v } end },
      Browser = {
        Toggle = function() error("the window toggle must go through /lh toggle, not B:Toggle") end,
        IsLocked = function() return locked end,
        GetWindow = function() return { IsShown = function() return winShown end } end,
      },
      BrowserTable = { testMode = false },
      Database = { Count = function() return 3 end },
      COMMANDS = { verb("show"), verb("toggle"), verb("enable"), verb("disable"), verb("test") },
    }
    Loader.load("core/LauncherSetup.lua", ns, mocks)
    assertTrue(captured ~= nil, "the file must build its launcher through Launcher:New")

    for _, k in ipairs({ "onClick", "leftClickLabel", "disabledLine", "slash" }) do
      assertTrue(captured[k] == nil, "descriptor." .. k .. " is retired at Launcher minor 4")
    end
    -- The four pairs (Launcher minor 4) and the minor-3 version, every one a FUNCTION so the
    -- library asks on every show and every menu open.
    for _, k in ipairs({ "openSettings", "isEnabled", "setEnabled", "isLocked", "toggleLock",
      "isTestMode", "toggleTestMode", "isWindowShown", "toggleWindow", "version" }) do
      assertEqual(type(captured[k]), "function", "descriptor." .. k)
    end

    captured.openSettings("LeftButton")
    assertEqual(opens, 1, "openSettings is NS.Panel:Open, the seam /lh config reaches")

    assertEqual(captured.isEnabled(), true, "enabled while AddonIsOff answers false")
    off = true
    assertEqual(captured.isEnabled(), false, "disabled while AddonIsOff answers true")
    captured.setEnabled(true)
    captured.setEnabled(false)
    captured.toggleTestMode()
    captured.toggleWindow()
    assertEqual(table.concat(ran, ","), "enable,disable,test,toggle",
      "each toggle runs its verb's own NS.COMMANDS handler, looked up at call time")

    assertEqual(captured.isLocked(), false)
    captured.toggleLock()
    locked = true
    assertEqual(captured.isLocked(), true, "isLocked reads B:IsLocked on every call")
    captured.toggleLock()
    assertEqual(#sets, 2, "toggleLock writes through the single write seam, once per call")
    assertEqual(sets[1][1], "settings.locked", "the Lock frame row's own path")
    assertEqual(sets[1][2], true, "unlocked -> lock")
    assertEqual(sets[2][2], false, "locked -> unlock")

    assertEqual(captured.isWindowShown(), false)
    winShown = true
    assertEqual(captured.isWindowShown(), true, "isWindowShown reads the History window on every call")
    ns.Browser.GetWindow = function() return nil end
    assertEqual(captured.isWindowShown(), false, "a window never built is not shown")

    assertEqual(captured.version(), "7.7.7", "the version is NS.Version(), the TOC's own")
    assertEqual(captured.isTestMode(), false)
    ns.BrowserTable.testMode = true
    assertEqual(captured.isTestMode(), true, "isTestMode reads BrowserTable.testMode on every call")

    -- The host hook draws the addon's OWN line and nothing else.
    local drawn = {}
    captured.onTooltipShow({ AddLine = function(_, text) drawn[#drawn + 1] = text end })
    assertEqual(#drawn, 1, "onTooltipShow draws one line: " .. table.concat(drawn, " / "))
    assertEqual(drawn[1], "3 records", "the record count is the addon's own line")
  end)
