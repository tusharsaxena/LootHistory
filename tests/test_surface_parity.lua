-- tests/test_surface_parity.lua — every degradation stub carries the whole live surface.
--
-- The cases in tests/test_libka0s.lua assert the members somebody thought to name. Parity asserts
-- the SET: every key the live seam publishes is present on the degraded one, and a key that is a
-- function live is a function degraded (`X = UI and UI.X` leaves `false` in place, and a check that
-- only asks "is the key set?" waves that through while the call site raises anyway).
--
-- ONE FILE, AT THIS NAME, IN ALL NINE ADDONS. The gate itself is not new here — these five cases
-- have run inside tests/test_libka0s.lua since 20b4574 — but they were the only copy in the
-- collection kept somewhere a reader had to already know about. M4-09 puts every addon's stub-parity
-- gate at the same path, so "is this addon's degradation stub checked?" is one `ls` in any of the
-- nine rather than a grep through a suite named after something else.
--
-- Two rules the cases follow, both from testing-§8:
--
--   * The degraded arm comes from a REAL LOAD with a partial file list (tests/degraded_env.lua
--     loads the TOC and nothing from libs/), never from a hand-written stub. A hand-stub asserts
--     the test author's typing, not the shipped file.
--   * Where a member is live-only on purpose, it is named in the `ignore` set with the grep that
--     proves this addon has no call site for it. An intentional omission and a bug are otherwise
--     indistinguishable, and the usual resolution for that is to delete the case.
--
-- WHICH FORM EACH CASE USES, and why they are not all the same. The kit publishes two:
--
--   assertSurfaceParity(live, degraded, label, ignore)   -- two tables, compared key for key
--   assertSurfaceParity(stub, majorName, ignore)         -- the live half is looked up by name
--
-- The by-name form arrived at kit 15 with M4-01 and compares only Kit.publicMembers — LibStub's
-- MAJOR/MINOR/MODULES and every `__`-prefixed key drop out, because those are the library talking to
-- itself across its own file boundary. DebugLog and Options use it: both are `lib:New(...)`
-- instances, so there is a major to name. Core, Widgets and Slash do NOT, and the reason is worth
-- having written down — none of the three is a major's surface at all. Core's and Widgets' halves
-- are two blocks of one file of ours and what they have in common is a set of names hung on NS;
-- Slash's are the two halves of settings/Slash.lua's own `Sl` table, which wraps the library's
-- dispatcher rather than being it. There is no name to look up, so the four-argument form is the
-- right one, not a form they have yet to be moved off.
--
-- WHAT THE BY-NAME FORM STOPPED CHECKING, said out loud because it is a real trade. The live Options
-- instance carries thirteen `__` members and settings/OptionsSetup.lua's stub deliberately mirrors
-- twelve of them, with its own argument at the `__layoutTabs` block for why. Under the four-argument
-- form this case COMPELLED all twelve and had to exempt the thirteenth, `__print`, by hand — an
-- exemption that grew by one on every re-vendor that published an internal, which is what the
-- entry's own comment said as it was written. Under the by-name form none of the twelve is compared,
-- so keeping them is now the host's decision (argued where they are written) instead of this file's.
-- That is the collection's rule rather than this repo's preference: LibKa0s' own comment at O.__print
-- says a degradation stub does not mirror an internal, and cites Kit.publicMembers by name.
--
-- WHERE THE LIVE HALF COMES FROM. tests/run.lua registers it with Kit.setSurfaceSource, and it has
-- to: both stubs mirror an INSTANCE — what `lib:New(descriptor)` returned — and not the library
-- table LibStub answers for the same name. Left to Kit.expose's auto-wiring, which reaches for the
-- mock's LibStub, "LibKa0s-Options-1.0" would resolve the library's four-member module table and
-- this case would go red for reasons that have nothing to do with the stub.

local T = _G.LH_TEST
local NS, Loader = T.NS, T.Loader
local test, assertTrue = T.test, T.assertTrue

local loadDegraded = dofile("tests/degraded_env.lua")

-- One load for the whole file. The environment is immutable as far as these cases are concerned —
-- none of them writes to it — and a fresh full-addon load per case buys nothing but seconds.
local degradedNS = loadDegraded()

-- ── Core ───────────────────────────────────────────────────────────────────────────────────────

test("parity: the Core seam publishes the same NS members on both paths", function()
  -- Core publishes onto NS itself rather than onto a module table, so the member list is derived
  -- from the seam file rather than re-typed:
  --   grep -nE "^\s*NS\.[A-Za-z_]+\s*=" core/CoreSetup.lua
  -- Deriving it is what makes a member added to the live half and forgotten in the stub go red;
  -- a hand-typed list here would go stale in exactly that case.
  local live, degraded = {}, {}
  local seen = {}
  for line in Loader.readFile("core/CoreSetup.lua"):gmatch("[^\r\n]+") do
    local key = line:match("^%s*NS%.([A-Za-z_][A-Za-z0-9_]*)%s*=")
    if key and not seen[key] then
      seen[key] = true
      live[key], degraded[key] = NS[key], degradedNS[key]
    end
  end
  assertTrue(seen.Print and seen.SafeToString,
    "the derivation found no NS.Print/NS.SafeToString — core/CoreSetup.lua changed shape and this "
    .. "case is now asserting nothing")
  T.assertSurfaceParity(live, degraded, "Core seam (NS members)")
end)

-- ── Widgets ────────────────────────────────────────────────────────────────────────────────────

test("parity: the Widgets seam publishes the same NS members on both paths", function()
  -- Derived from the seam file, exactly as the Core case above is:
  --   grep -nE "^\s*function NS\.[A-Za-z_]+" core/WidgetsSetup.lua
  -- Both members exist on both paths BY CONSTRUCTION here -- the seam defines them outside any
  -- `if W` branch and each degrades inside itself (nil dropdown, no-op close). That is the shape
  -- worth pinning: the alternative, defining them only when the library resolved, is what turns a
  -- missing library into "attempt to call a nil value" at the first close of a window.
  local live, degraded = {}, {}
  local seen = {}
  for line in Loader.readFile("core/WidgetsSetup.lua"):gmatch("[^\r\n]+") do
    local key = line:match("^%s*function NS%.([A-Za-z_][A-Za-z0-9_]*)")
    if key and not seen[key] then
      seen[key] = true
      live[key], degraded[key] = NS[key], degradedNS[key]
    end
  end
  assertTrue(seen.MakeDropdown and seen.CloseMenu,
    "the derivation found neither NS.MakeDropdown nor NS.CloseMenu — core/WidgetsSetup.lua changed "
    .. "shape and this case is now asserting nothing")
  T.assertSurfaceParity(live, degraded, "Widgets seam (NS members)")
end)

-- ── Slash ──────────────────────────────────────────────────────────────────────────────────────

test("parity: the Slash stub carries the whole live surface", function()
  -- Members from: grep -nE "^Sl\.[A-Za-z]|^function Sl[.:]" settings/Slash.lua
  -- Both arms are settings/Slash.lua's own `Sl` table, which is why this stays on the four-argument
  -- form: the live half wraps LibKa0s-Slash-1.0's dispatcher (Sl.CliGet forwards to Dispatcher:CliGet)
  -- and is not that dispatcher, so naming the major would compare the wrong pair of tables.
  T.assertSurfaceParity(NS.Slash, degradedNS.Slash, "Slash stub")
end)

-- ── DebugLog ───────────────────────────────────────────────────────────────────────────────────

test("parity: the DebugLog stub carries the whole live surface", function()
  -- The live half is the LibKa0s-DebugLog-1.0 instance core/DebugLogSetup.lua builds, registered
  -- under that name by tests/run.lua. Read off the built instance rather than the file, which is the
  -- same list as
  --   grep -nE "^function D[:.]|^  [A-Za-z_]+ *= *function" libs/LibKa0s/DebugLog.lua
  -- without a parser.
  T.assertSurfaceParity(degradedNS.DebugLog, "LibKa0s-DebugLog-1.0", {
    -- The library's own window internals. `grep -rn "DebugLog[.:]\(CopyText\|Text\|MakeCloseButton\)"
    -- core settings modules` returns nothing: this addon reaches the console through
    -- Show/Hide/IsShown/Toggle/SetEnabled/ConsoleCheckbox only, and there is no window to copy
    -- text out of when the library is absent.
    "CopyText", "Text", "MakeCloseButton",
    -- Reached under its published name instead: core/DebugLogSetup.lua does `NS.Debug =
    -- NS.DebugLog.Debug` live and publishes a no-op `NS.Debug` on the stub path, which is what the
    -- ~40 call sites across seven files actually call. Asserted directly below.
    "Debug",
    -- Test-only seams the library attaches to the live instance the first time the window is
    -- built (tests/test_debuglog.lua drives it, and that suite loads before this one). They are
    -- not addon surface, and there is no window to attach them to on the degraded path. Single
    -- underscore, so Kit.publicMembers does not filter them — that exclusion is the `__` prefix.
    "_frameForTest", "_toggleClickForTest",
  })
  assertTrue(type(NS.Debug) == "function" and type(degradedNS.Debug) == "function",
    "NS.Debug is the name the sink is called by; it must be a function on BOTH paths")
end)

-- ── Options ────────────────────────────────────────────────────────────────────────────────────

test("parity: the Options stub carries the whole live surface", function()
  -- The live half is the LibKa0s-Options-1.0 instance settings/OptionsSetup.lua assigns to
  -- NS.Options, registered under that name by tests/run.lua.
  --   grep -n "Options\.[A-Za-z_]" core modules settings   names the addon's call sites.
  T.assertSurfaceParity(degradedNS.Options, "LibKa0s-Options-1.0", {
    -- Live-only, all four with no call site in this addon:
    --   grep -rn "Options\.\(AceGUI\|BuildLandingPage\|PADDING_X\|TextRow\)" core settings modules
    -- returns nothing. The AceGUI instance is reached as NS.AceGUI (settings/OptionsSetup.lua's
    -- `onAceGUI` hook), never off the Options table; the landing page is built by NS.Panel through
    -- `buildMain`; and this addon reads none of the library's published layout scalars — it draws
    -- its two carve-outs (the set picker, the AH price rows) with its own constants.
    "AceGUI", "BuildLandingPage", "PADDING_X", "TextRow",
    -- `__print` USED TO BE THE FIFTH ENTRY HERE, and its departure is the measurable half of
    -- M4-09. It is the one instance print sink the shell publishes so OptionsWidgets stops building
    -- a second one from the same descriptor (libs/LibKa0s/Options.lua, read at
    -- OptionsWidgets.lua:763), it arrived with v1.27.0 three days ago, and the library's comment
    -- where it is published says a degradation stub does not mirror it BECAUSE Kit.publicMembers
    -- drops the `__` prefix. That was true of the by-name form and not of the four-argument form
    -- this case used to use, so the exemption had to be typed. It no longer does, and neither will
    -- the next internal the library publishes.
  })
end)

-- ── Bus (Catalog only) ─────────────────────────────────────────────────────────────────────────

test("parity: the Bus stub carries the live surface this addon calls", function()
  -- core/Constants.lua resolves LibKa0s-Bus-1.0 for `Catalog` alone and publishes the resolved table
  -- as NS.BusLib, which on the degraded path is its one-member stub.
  T.assertSurfaceParity(degradedNS.BusLib, "LibKa0s-Bus-1.0", {
    -- Live-only on purpose. `New` builds a stand-down record for TRACKED receivers, and this addon's
    -- receivers are untracked by design: every one registers on its own NS.NewBusTarget() target
    -- (core/LootHistory.lua) and each module stands its own down. `grep -rn "BusLib" core modules
    -- settings` names only core/Constants.lua, which calls `Catalog`. A member the major adds later
    -- is in neither list and fails this case until the addon decides.
    "New",
  })
end)
