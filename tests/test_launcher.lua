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

-- ── the status tooltip is the LIBRARY's (Launcher minor 3, launcher-§1, M5) ───────────────────
--
-- LibKa0s-Launcher-1.0 minor 2 gates a rung-(a)/(b) left click on the descriptor's `isEnabled` and
-- prints its `disabledLine()`; minor 3 (LibKa0s v1.57.0) also DRAWS the tooltip, on every host and
-- while the addon is disabled: the title with the version, Enabled, Locked and Test mode where the
-- host has them, the host's own lines, then the two click hints. This addon used to draw the whole
-- tooltip itself -- title, hints and the disabled refusal line -- and under minor 3 every one of those
-- would be drawn twice (anti-pattern #89). The cases below pin what is left: the descriptor answers
-- the library's questions, and `onTooltipShow` adds the record count and nothing else.

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

test("launcher: the enabled tooltip is the library's block, with the addon's one line inside it",
  function()
    -- launcher-§1 (standard v2.66.0): the exact shape, in order. The title carries the TOC version,
    -- Locked and Test mode are drawn because this addon HAS both (the Lock frame row and the
    -- History window's test mode), the record count is this addon's own line, and the left click
    -- names rung (a)'s window.
    -- red under: the old hand-drawn title or hints coming back (a second copy, anti-pattern #89), a
    -- missing isLocked / isTestMode / version / leftClickLabel, or the count line going missing.
    local lines = withState({ locked = false, test = false, enabled = true }, tooltipLines)
    local want = {
      NS.BRAND .. "  v" .. NS.Version(),
      "Enabled: Yes",
      "Locked: No",
      "Test mode: Off",
      recordLine(),
      "Left-click: Toggle History window",
      "Right-click: Open settings",
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

test("launcher: while disabled the tooltip still shows, says Enabled: No and points at /lh enable",
  function()
    -- The owner's ruling (M5): the button ALWAYS answers a hover, disabled included. The left
    -- click on rung (a) is refused while off, so its hint gives way to the library's pointer, read
    -- out of NS.Slash.DisabledLine(); the right click is never gated.
    -- red under: a tooltip that keeps promising the window while the library refuses the click, the
    -- addon's own refusal line drawn a second time, or the status block missing while off.
    local lines = withState({ locked = false, test = false, enabled = false }, tooltipLines)
    local want = {
      NS.BRAND .. "  v" .. NS.Version(),
      "Enabled: No",
      "Locked: No",
      "Test mode: Off",
      recordLine(),
      "Left-click: disabled \226\128\148 /lh enable",
      "Right-click: Open settings",
    }
    assertEqual(#lines, #want, "the disabled tooltip draws exactly seven lines: "
      .. table.concat(lines, " / "))
    for i, w in ipairs(want) do assertEqual(lines[i], w, "disabled tooltip line " .. i) end
  end)

test("launcher: the descriptor answers the library's questions, and onClick gates nothing",
  function()
    -- Re-run core/LauncherSetup.lua against a fake Launcher that records the descriptor, into a
    -- scratch namespace, so the fields the library reads are asserted rather than inferred.
    -- red under: a descriptor without the minor-2 pair (the library could not refuse the click), an
    -- onClick that still carries its own AddonIsOff branch (two gates, two places to drift), a
    -- minor-3 field missing or reading a cached value, or an onTooltipShow that draws a title,
    -- a status line or a click hint again.
    local captured
    local fakeLauncher = { New = function(_, d) captured = d; return {} end }
    local fakeLibStub = setmetatable({}, { __call = function(_, name)
      if name == "LibKa0s-Launcher-1.0" then return fakeLauncher end
    end })
    local mocks = setmetatable({ LibStub = fakeLibStub }, { __index = T.mocks })
    local off, toggles, locked = false, 0, false
    local ns = {
      BRAND = NS.BRAND,
      L = setmetatable({}, { __index = function(_, k) return k end }),
      Version = function() return "7.7.7" end,
      AddonIsOff = function() return off end,
      Slash = { DisabledLine = function() return "the one refusal line" end },
      Browser = {
        Toggle = function() toggles = toggles + 1 end,
        IsLocked = function() return locked end,
      },
      BrowserTable = { testMode = false },
      Database = { Count = function() return 3 end },
    }
    Loader.load("core/LauncherSetup.lua", ns, mocks)
    assertTrue(captured ~= nil, "the file must build its launcher through Launcher:New")
    assertEqual(type(captured.isEnabled), "function", "descriptor.isEnabled (Launcher minor 2)")
    assertEqual(type(captured.disabledLine), "function", "descriptor.disabledLine (Launcher minor 2)")
    assertEqual(captured.isEnabled(), true, "enabled while AddonIsOff answers false")
    off = true
    assertEqual(captured.isEnabled(), false, "disabled while AddonIsOff answers true")
    assertEqual(captured.disabledLine(), "the one refusal line", "the line is NS.Slash.DisabledLine()")
    captured.onClick("LeftButton")
    assertEqual(toggles, 1, "onClick carries no gate of its own; the library's isEnabled is the gate")

    -- Launcher minor 3: every one a FUNCTION, so the library asks on every show.
    for _, k in ipairs({ "version", "isLocked", "isTestMode", "leftClickLabel" }) do
      assertEqual(type(captured[k]), "function", "descriptor." .. k .. " (Launcher minor 3)")
    end
    assertEqual(captured.version(), "7.7.7", "the version is NS.Version(), the TOC's own")
    assertEqual(captured.leftClickLabel(), "Toggle History window", "rung (a): the History window")
    assertEqual(captured.isLocked(), false)
    locked = true
    assertEqual(captured.isLocked(), true, "isLocked reads B:IsLocked on every call")
    assertEqual(captured.isTestMode(), false)
    ns.BrowserTable.testMode = true
    assertEqual(captured.isTestMode(), true, "isTestMode reads BrowserTable.testMode on every call")
    assertEqual(captured.slash, nil, "no slash: the library reads /lh out of the disabled line")

    -- The leftClickLabel goes through the addon's locale.
    ns.L = setmetatable({ ["Toggle History window"] = "Verlaufsfenster" }, {
      __index = function(_, k) return k end })
    assertEqual(captured.leftClickLabel(), "Verlaufsfenster", "the label is read through NS.L")

    -- The host hook draws the addon's OWN line and nothing else.
    local drawn = {}
    captured.onTooltipShow({ AddLine = function(_, text) drawn[#drawn + 1] = text end })
    assertEqual(#drawn, 1, "onTooltipShow draws one line: " .. table.concat(drawn, " / "))
    assertEqual(drawn[1], "3 records", "the record count is the addon's own line")
  end)
