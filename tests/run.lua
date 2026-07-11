-- Headless test runner for Ka0s Loot History.
-- Run from the repo root:  lua tests/run.lua

local Loader     = dofile("tests/loader.lua")
local buildMocks = dofile("tests/wow_mock.lua")

-- --- tiny test framework (exposed to test files via _G.LH_TEST) ---
local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function fail(msg, level) error(msg, (level or 1) + 1) end
local function assertEqual(got, want, msg)
  if got ~= want then
    fail((msg or "assertEqual") ..
      string.format(" (expected %s, got %s)", tostring(want), tostring(got)), 1)
  end
end
local function assertTrue(c, msg) if not c then fail(msg or "assertTrue failed", 1) end end
local function assertFalse(c, msg) if c then fail(msg or "assertFalse failed", 1) end end

-- --- build the shared addon environment once (mirrors in-game load + OnInitialize) ---
local mocks = buildMocks()
local NS = {}

Loader.loadAll({
  "core/Compat.lua",
  "core/Constants.lua",
  "core/Namespace.lua",
  "core/State.lua",
  "core/Util.lua",
  "core/LootHistory.lua",
  "core/Database.lua",
  "defaults/Global.lua",
  "locales/enUS.lua",
  "settings/Schema.lua",
  "settings/Slash.lua",
  "settings/Panel.lua",
  "modules/Attribution.lua",
  "modules/Collector.lua",
  "modules/Browser.lua",
  "modules/BrowserTable.lua",
  "modules/Analytics.lua",
}, NS, mocks)

NS:InitDB()
NS:RunMigrations()

_G.LH_TEST = {
  NS = NS, mocks = mocks, test = test,
  assertEqual = assertEqual, assertTrue = assertTrue, assertFalse = assertFalse,
}

-- --- load test suites ---
dofile("tests/test_util.lua")
dofile("tests/test_compat.lua")
dofile("tests/test_attribution.lua")
dofile("tests/test_collector.lua")
dofile("tests/test_database.lua")
dofile("tests/test_stats.lua")

-- --- run ---
local passed, failed = 0, 0
for _, t in ipairs(tests) do
  local ok, err = pcall(t.fn)
  if ok then
    passed = passed + 1
    print("  PASS  " .. t.name)
  else
    failed = failed + 1
    print("  FAIL  " .. t.name .. "\n          " .. tostring(err))
  end
end
print(string.format("\n%d passed, %d failed, %d total", passed, failed, passed + failed))
os.exit(failed == 0 and 0 or 1)
