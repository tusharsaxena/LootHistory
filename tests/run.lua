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

-- The vendored library first, every file of LibKa0s.xml in XML order -- DERIVED FROM THAT XML
-- rather than spelled out here. The TOC pulls them through the XML, which Loader.tocFiles cannot
-- see (it skips every `libs\` line), so this runner has to name them itself; naming them by hand
-- is the second maintained list the comment below warns about, and it drifted at LibKa0s v1.48.0,
-- which added WidgetsDragHandle.lua. Loader.xmlFiles returns XML order, directory-prefixed, and
-- raises on a missing XML.
Loader.loadAll(Loader.xmlFiles("libs/LibKa0s/LibKa0s.xml"), NS, mocks)

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
-- The launcher (launcher-§1). Last, as in the client, and after NS:InitDB for the same reason:
-- `Register()` hands LibDBIcon `db.global.minimap`, which InitDB is what creates. Nothing in the
-- headless environment registers LibDataBroker or LibDBIcon, so this resolves neither and returns
-- false -- which is the degraded path, and tests/test_launcher.lua registers its own fakes to
-- drive the wired one.
kick("NS.Launcher:Register", function() if NS.Launcher then NS.Launcher:Register() end end)
-- The latch's AceDB profile callbacks (slash-commands-§7). Last, as in the client, and after
-- NS:InitDB for the plainest of reasons: it registers callbacks on `NS.db`, which InitDB creates.
-- It does NOT bring the addon up -- `addon:OnEnable` is what does that, and no suite but
-- tests/test_disabled.lua wants the whole addon registered underneath it.
kick("NS.BindLifecycle", function() NS.BindLifecycle() end)

-- Load order is significant (later suites read state earlier ones seed); keep as-is. The list is a
-- named local so tests/test_harness.lua can hand it to Kit.assertSuiteInventory as a named case —
-- Kit.run applies the same gate implicitly, but an implicit gate contributes no row to
-- docs/test-cases.md and nobody reading the inventory can tell whether it ran.
local SUITES = {
  "test_constants", "test_mediasetup", "test_envsetup", "test_poolsetup", "test_itemsetup", "test_util",
  "test_compat", "test_attribution",
  "test_filters", "test_auctionprice", "test_collector", "test_database", "test_stats",
  "test_browser", "test_browsertable", "test_export", "test_debuglog",
  -- BEFORE test_slash, deliberately: it leaves inert LibDataBroker / LibDBIcon fakes behind, and
  -- every Reset all settings below reaches LibDBIcon through NS.RefreshLauncher.
  "test_launcher", "test_slash",
  "test_schema", "test_analytics", "test_panel", "test_panel_filters", "test_harness", "test_libka0s",
  -- After test_libka0s and after test_debuglog, both deliberately. It shares the degraded
  -- environment with the first, and the second is what attaches the library's `_frameForTest`
  -- seams to the live DebugLog instance -- the ignore entries naming them describe the state this
  -- suite actually meets, and would be exempting nothing if it ran earlier.
  "test_surface_parity",
  -- slash-commands-§7's conformance suite. LATE, and after test_launcher deliberately: it is the
  -- only suite that brings the WHOLE addon up through addon:OnEnable, and step 8 drives the LDB
  -- object test_launcher leaves registered.
  "test_disabled",
  "test_doc_structure",
  -- The lint-suppression gate. Like test_doc_structure and test_eol it reads the repository
  -- from disk rather than the loaded addon, so it wants no particular slot; it sits beside
  -- the other two gates that answer for the repo rather than for the code.
  "test_lintconfig",
  -- The kit's US-English gate (localization-5), declared by the pair (basename, directory) as
  -- testing-9 prescribes. A bare "test_prose" here once ran a hand-written local copy and let the
  -- kit's own suite load nothing; the local copy is gone, and the one spelling it waived
  -- (the British-spelled flag on core/LifecycleSetup.lua's deferral handle) is now
  -- `h.canceled`, so there is no waiver file.
  { name = "test_prose", dir = "tests/_kit/" },
  "test_vendor_sync",
  -- The kit has shipped one suite of its own since revision 15: the working-tree line-ending
  -- gate, over every path `git ls-files` reports. It lives where the rest of the kit lives
  -- rather than being re-typed into nine repositories, so it is declared with its own `dir`.
  -- Kit.assertSuiteInventory fails the run until it is declared, so it cannot arrive with a
  -- re-vendor and then quietly run nothing. It shells out to git and reads no addon state, so
  -- it is safe anywhere in this list and does not want the last slot.
  { name = "test_eol", dir = "tests/_kit/" },
  -- The kit's layout-1 cap gate (revision 25): every authored, tracked .lua file against the
  -- `Files over the 1500-line cap` census in docs/ARCHITECTURE.md. Like test_eol it reads the
  -- checkout through git and no addon state, so it wants no particular slot.
  { name = "test_layout_cap", dir = "tests/_kit/" },
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
  -- The three v1.55.0 majors are LIBRARY tables, not instances, so these rows name what the
  -- auto-wiring would have: the mock's own LibStub answer. A table map answers only what it lists,
  -- so each adopted major needs its row or the by-name parity call cannot find the live half.
  ["LibKa0s-Bus-1.0"]      = mocks.LibStub("LibKa0s-Bus-1.0", true),
}

_G.LH_TEST = Kit.expose{
  NS = NS, mocks = mocks, Loader = Loader,
  addonFiles = ADDON_FILES, suites = SUITES, lifecycle = LIFECYCLE,
}

Kit.run{ dir = "tests/", suites = SUITES }
