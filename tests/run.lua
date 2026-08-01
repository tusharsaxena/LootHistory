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
  "libs/LibKa0s/DebugLog.lua",
  "libs/LibKa0s/Slash.lua",
  "libs/LibKa0s/Options.lua",
  "libs/LibKa0s/OptionsWidgets.lua",
  "libs/LibKa0s/OptionsScroll.lua",
  "libs/LibKa0s/Perf.lua",
  "libs/LibKa0s/PerfPanel.lua",
}, NS, mocks)

-- Derived from the TOC rather than hand-listed, so the runner's load order cannot drift from the
-- client's — the exact drift a second hand-maintained list invites.
Loader.loadAll(Loader.tocFiles("LootHistory.toc"), NS, mocks)

NS:InitDB()

_G.LH_TEST = Kit.expose{ NS = NS, mocks = mocks, Loader = Loader }

-- Load order is significant (later suites read state earlier ones seed); keep as-is.
Kit.run{
  dir = "tests/",
  suites = {
    "test_constants", "test_util", "test_compat", "test_attribution",
    "test_filters", "test_auctionprice", "test_collector", "test_database", "test_stats",
    "test_browser", "test_browsertable", "test_export", "test_debuglog", "test_slash",
    "test_schema", "test_analytics",
  },
}
