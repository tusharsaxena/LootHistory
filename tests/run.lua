-- Headless test runner for Ka0s Loot History.
-- Run from the repo root:  lua tests/run.lua

local Loader     = dofile("tests/loader.lua")
local buildMocks = dofile("tests/wow_mock.lua")

-- --- tiny test framework (exposed to test files via _G.LH_TEST) ---
local tests = {}
local currentSuite = nil
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn, suite = currentSuite } end

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
  "modules/Export.lua",
  "modules/Analytics.lua",
  "modules/DebugLog.lua",
}, NS, mocks)

NS:InitDB()

_G.LH_TEST = {
  NS = NS, mocks = mocks, test = test,
  assertEqual = assertEqual, assertTrue = assertTrue, assertFalse = assertFalse,
}

-- --- load test suites (order is load-order-sensitive; keep as-is) ---
local SUITE_FILES = {
  "test_util.lua", "test_compat.lua", "test_attribution.lua",
  "test_collector.lua", "test_database.lua", "test_stats.lua",
  "test_browsertable.lua", "test_export.lua", "test_debuglog.lua", "test_slash.lua",
}
for _, s in ipairs(SUITE_FILES) do
  currentSuite = s
  dofile("tests/" .. s)
end
currentSuite = nil

-- --- inventory mode: emit docs/test-cases.md and exit without running ---
if arg and arg[1] == "--list" then
  local order, byS = {}, {}
  for _, t in ipairs(tests) do
    if not byS[t.suite] then byS[t.suite] = {}; order[#order + 1] = t.suite end
    local b = byS[t.suite]; b[#b + 1] = t.name
  end
  print("# Test Cases")
  print("")
  print("The full inventory of every headless test case, grouped by suite. This file is the")
  print("**authoritative pass count** for the addon.")
  print("")
  print("**Generated — do not hand-edit.** Regenerate with `lua tests/run.lua --list > docs/test-cases.md`")
  print("whenever the suite changes (see [testing.md](testing.md)).")
  print("")
  for _, s in ipairs(order) do
    local b = byS[s]
    print(string.format("### %s (%d)", s, #b))
    print("")
    for _, n in ipairs(b) do print("- " .. n) end
    print("")
  end
  print("## Totals")
  print("")
  print("| Suite | Cases |")
  print("|-------|------:|")
  for _, s in ipairs(order) do print(string.format("| %s | %d |", s, #byS[s])) end
  print(string.format("| **Total** | **%d** |", #tests))
  os.exit(0)
end

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
