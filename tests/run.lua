-- Headless test runner for Ka0s Loot History.
-- Run from the repo root:  lua tests/run.lua
--
-- The registry, the assertions, the `--list` renderer and the source loader all come from the
-- shared LibKa0s test kit, vendored byte-for-byte at tests/_kit/ (see docs/testing.md). What stays
-- here is only what is genuinely per-addon: the load list, the lifecycle kick and the suite list.

local Kit    = dofile("tests/_kit/framework.lua")
local Loader = dofile("tests/_kit/loader.lua")
local mocks  = dofile("tests/wow_mock.lua")()

Loader.addonName = "LootHistory"
local NS = {}

-- The vendored library first, every file of LibKa0s.xml spelled out in XML order: the TOC pulls
-- them through that XML, which Loader.tocFiles cannot see (it skips every `libs\` line).
Loader.loadAll({
  "libs/LibKa0s/Core.lua",
  "libs/LibKa0s/Env.lua",
  "libs/LibKa0s/Pool.lua",
  "libs/LibKa0s/Item.lua",
  "libs/LibKa0s/Media.lua",
  "libs/LibKa0s/Widgets.lua",
  "libs/LibKa0s/DebugLog.lua",
  "libs/LibKa0s/Slash.lua",
  "libs/LibKa0s/Launcher.lua",
  "libs/LibKa0s/Options.lua",
  "libs/LibKa0s/OptionsWidgets.lua",
  "libs/LibKa0s/OptionsTabs.lua",
  "libs/LibKa0s/OptionsCompose.lua",
  "libs/LibKa0s/OptionsScroll.lua",
  "libs/LibKa0s/Perf.lua",
  "libs/LibKa0s/PerfPanel.lua",
}, NS, mocks)

-- Derived from the TOC rather than hand-listed, so the runner's load order cannot drift from the
-- client's — the exact drift a second hand-maintained list invites. The derivation is captured into
-- a local and published through Kit.expose rather than fed straight in, because testing-§9 pins the
-- derivation itself: tests/test_harness.lua compares what the loader was ACTUALLY handed against a
-- fresh derivation, checks every path exists, and checks no `libs/` path leaked in.
local ADDON_FILES = Loader.tocFiles("LootHistory.toc")
Loader.loadAll(ADDON_FILES, NS, mocks)

-- The lifecycle kick the client's OnInitialize does. Register() only builds the canvas frames and
-- registers the Blizzard categories — every page BODY is still deferred to its first OnShow, which
-- tests/test_panel.lua drives explicitly through the mock's recorded script handlers.
--
-- Recorded as it runs and published through Kit.expose, because this is the fourth list in the repo
-- that has to agree with something else and was the only one nothing read. tests/test_harness.lua
-- derives what addon:OnInitialize ACTUALLY calls out of core/LootHistory.lua and compares the two,
-- so a step added there and forgotten here goes red instead of quietly leaving every suite below
-- measuring an addon the client never builds. The label is recorded by the same call that runs the
-- step, so the list cannot drift from the kick even by one line.
local LIFECYCLE = {}
local function kick(label, fn) LIFECYCLE[#LIFECYCLE + 1] = label; fn() end

kick("NS:InitDB",          function() NS:InitDB() end)
kick("NS.Schema:Register", function() NS.Schema:Register() end)
kick("NS.Slash:Register",  function() NS.Slash:Register() end)
kick("NS.Panel:Register",  function() NS.Panel:Register() end)

-- Load order is significant (later suites read state earlier ones seed); keep as-is. The list is a
-- named local so tests/test_harness.lua can hand it to Kit.assertSuiteInventory as a named case —
-- Kit.run applies the same gate implicitly, but an implicit gate contributes no row to
-- docs/test-cases.md and nobody reading the inventory can tell whether it ran.
local SUITES = {
  "test_constants", "test_mediasetup", "test_envsetup", "test_poolsetup", "test_itemsetup", "test_util",
  "test_compat", "test_attribution",
  "test_filters", "test_auctionprice", "test_collector", "test_database", "test_stats",
  "test_browser", "test_browsertable", "test_export", "test_debuglog", "test_slash",
  "test_schema", "test_analytics", "test_panel", "test_panel_filters", "test_harness", "test_libka0s",
  -- After test_libka0s and after test_debuglog, both deliberately. It shares the degraded
  -- environment with the first, and the second is what attaches the library's `_frameForTest`
  -- seams to the live DebugLog instance -- the ignore entries naming them describe the state this
  -- suite actually meets, and would be exempting nothing if it ran earlier.
  "test_surface_parity",
  "test_doc_structure",
  -- The lint-suppression gate. Like test_doc_structure and test_eol it reads the repository
  -- from disk rather than the loaded addon, so it wants no particular slot; it sits beside
  -- the other two gates that answer for the repo rather than for the code.
  "test_lintconfig",
  "test_vendor_sync",
  -- The kit has shipped one suite of its own since revision 15: the working-tree line-ending
  -- gate, over every path `git ls-files` reports. It lives where the rest of the kit lives
  -- rather than being re-typed into nine repositories, so it is declared with its own `dir`.
  -- Kit.assertSuiteInventory fails the run until it is declared, so it cannot arrive with a
  -- re-vendor and then quietly run nothing. It shells out to git and reads no addon state, so
  -- it is safe anywhere in this list and does not want the last slot.
  { name = "test_eol", dir = "tests/_kit/" },
  -- Last on purpose: its close-path cases build and show the History window, which attaches
  -- BrowserTable to a mock that has no FauxScrollFrame_* globals. Nothing after it may assume an
  -- unbuilt window.
  "test_widgets",
}

-- Where Kit.assertSurfaceParity's by-name form looks a live surface up, for the two seams that have
-- a major to name. It has to be said here: both stubs mirror an INSTANCE -- what `lib:New(descriptor)`
-- returned -- and not the library table LibStub answers for the same name. Under Kit.expose's
-- auto-wiring "LibKa0s-Options-1.0" resolves the library's own module table rather than the surface
-- settings/Panel.lua actually calls, and tests/test_surface_parity.lua goes red naming members no
-- stub was ever meant to carry.
--
-- Set BEFORE Kit.expose, which is what makes it stick: expose registers a source only when none is
-- registered yet, precisely so a runner like this one keeps its own.
Kit.setSurfaceSource{
  ["LibKa0s-Options-1.0"]  = NS.Options,
  ["LibKa0s-DebugLog-1.0"] = NS.DebugLog,
}

_G.LH_TEST = Kit.expose{
  NS = NS, mocks = mocks, Loader = Loader,
  addonFiles = ADDON_FILES, suites = SUITES, lifecycle = LIFECYCLE,
}

Kit.run{ dir = "tests/", suites = SUITES }
