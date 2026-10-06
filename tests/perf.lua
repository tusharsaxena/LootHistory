-- tests/perf.lua — the offline performance runner (performance-§9).
--
--   lua tests/perf.lua
--
-- OUTSIDE THE GREEN GATE: `lua tests/run.lua` does not run it. It asserts only deterministic
-- quantities — bytes allocated per iteration with the GC stopped, and call counts — never time.
-- Exit code is non-zero on a failed check.

local Loader     = dofile("tests/_kit/loader.lua")
local buildMocks = dofile("tests/wow_mock.lua")
-- Each dofile of the kit loader returns a fresh table, so this runner sets its own addonName:
-- core/PerfSetup.lua reads it as the first chunk argument.
Loader.addonName = "LootHistory"

-- Derived from the XML and the TOC, never hand-listed: a library file left out here does not fail,
-- it turns NS.Perf into the degradation stub and every scenario measures a stub.
local mocks = buildMocks()
local NS = {}
Loader.loadAll(Loader.xmlFiles("libs/LibKa0s/LibKa0s.xml"), NS, mocks)
Loader.loadAll(Loader.tocFiles("LootHistory.toc"), NS, mocks)
NS.addon:OnInitialize()
NS.addon:OnEnable()

local failures = 0
local function check(name, ok, detail)
  print(("%s  %s%s"):format(ok and "PASS" or "FAIL", name, detail and ("  (" .. detail .. ")") or ""))
  if not ok then failures = failures + 1 end
end

-- Bytes per iteration of fn, GC stopped, after a warm-up pass.
local function bytesPerIter(fn, n)
  for _ = 1, 50 do fn() end
  collectgarbage("collect"); collectgarbage("stop")
  local before = collectgarbage("count")
  for _ = 1, n do fn() end
  local after = collectgarbage("count")
  collectgarbage("restart")
  return (after - before) * 1024 / n
end

check("harness: NS.Perf is the live instance, not the stub", NS.Perf.descriptor ~= nil)

-- Scenario 1 — zero overhead (performance-§2/§9): a DROPPED loot line (below the quality gate, the
-- common in-raid case) through the bracketed handler with capture off allocates no more than the
-- unbracketed body.
NS.db.profile.settings.qualityThreshold = 5
NS.Collector:RefreshUpvalues()
local line = string.format(mocks.LOOT_ITEM_SELF, "|cffa335ee|Hitem:211296::::::::80:::::|h[Vial]|h|r")
NS.Perf.on = false
local bracketed = bytesPerIter(function() NS.Collector:OnChatMsgLoot(nil, line) end, 2000)
local bare = bytesPerIter(function() NS.Collector._lootLine(NS.Collector, line) end, 2000)
check("zero-overhead: dropped loot line, capture off", bracketed <= bare,
  ("%.1f B/iter bracketed vs %.1f bare"):format(bracketed, bare))

-- Scenario 2 — an in-combat BAG_UPDATE storm is dirty bits only: no allocation after warm-up, no scan.
local scans, base = 0, NS.Scanner.ScanContainers
NS.Scanner.ScanContainers = function(...) scans = scans + 1; return base(...) end
mocks.InCombatLockdown = function() return true end
local storm = bytesPerIter(function() NS.Reconciler:OnEvent("BAG_UPDATE", 0) end, 5000)
check("combat BAG_UPDATE: no allocation", storm == 0, ("%.1f B/iter"):format(storm))
check("combat BAG_UPDATE: no scan", scans == 0, tostring(scans) .. " scans")
mocks.InCombatLockdown = function() return false end
NS.Scanner.ScanContainers = base

-- Scenario 3 — one out-of-combat reconcile over a full bag set: scan calls are bounded by the
-- number of bags (one ScanContainers per dirty container group), never per slot.
for bag = 0, 5 do
  mocks.__bagSlots[bag] = 36
  mocks.__bags[bag] = {}
  for s = 1, 36 do mocks.__bags[bag][s] = { itemID = 1000 + s, link = "L", count = 1 } end
end
NS.Reconciler:LoginScan()
scans = 0
NS.Scanner.ScanContainers = function(...) scans = scans + 1; return base(...) end
NS.Reconciler.dirty = {}
NS.Reconciler:MarkDirty("bags"); NS.Reconciler:Flush()
check("reconcile: one container scan per dirty group", scans == 1, tostring(scans) .. " scans")
NS.Scanner.ScanContainers = base

if failures > 0 then os.exit(1) end
