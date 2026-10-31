-- tests/perf.lua — the offline performance runner (performance-§9).
--
--   lua tests/perf.lua [--out <path>] [--label <text>]
--
-- OUTSIDE THE GREEN GATE: `lua tests/run.lua` does not run it. It asserts only deterministic
-- quantities — bytes allocated per iteration with the GC stopped, and call counts — never time.
-- Exit code is non-zero on a failed check. `--out` writes the scenarios as the JSON record the
-- vendored runner keeps in its bundle; the table below is what its `perf` suite counts.
--
-- CEILINGS (measured 2026-10-31, Lua 5.1.5). Each is a pinned number, never derived from the run
-- that checks it. The three zeros are the claims themselves: a dropped line and a combat BAG_UPDATE
-- allocate nothing. reconcileCleanBags is real work: 118120 bytes for one pass over 216 occupied
-- slots with nothing changed (about 547 per slot, the snapshot the diff reads), behind the debounce
-- and never in combat, so its ceiling is that work plus 5%. Raise one only by re-measuring and saying
-- why beside it; a rise is the finding.
local BYTE_CEILING = { lootDroppedBracketed = 0, lootDroppedBare = 0, combatBagUpdate = 0,
                       reconcileCleanBags = 124000 }
local SCANS_PER_ITER = { lootDroppedBracketed = 0, lootDroppedBare = 0, combatBagUpdate = 0,
                         reconcileCleanBags = 1 }

local USAGE = "usage: lua tests/perf.lua [--out <path>] [--label <text>]\n"

local opts = { out = nil, label = "offline" }
do
  local i = 1
  while arg and arg[i] do
    local a = arg[i]
    if a == "--out" and arg[i + 1] then opts.out = arg[i + 1]; i = i + 2
    elseif a == "--label" and arg[i + 1] then opts.label = arg[i + 1]; i = i + 2
    else
      io.stderr:write("unknown argument: " .. tostring(a) .. "\n", USAGE)
      os.exit(2)
    end
  end
end

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

check("harness: NS.Perf is the live instance, not the stub", NS.Perf.descriptor ~= nil)

-- Counts ScanContainers without allocating: a counter around the real function.
local scans, baseScan = 0, NS.Scanner.ScanContainers
NS.Scanner.ScanContainers = function(...) scans = scans + 1; return baseScan(...) end

local results = {}

-- The warm-up and the measured loop both run through here, so `fn` is called at the same stack depth.
local function loop(n, fn)
  for _ = 1, n do fn() end
end

-- One scenario: bytes and scans per iteration, the collector stopped, after a warm-up pass.
local function measure(name, n, fn)
  loop(50, fn)
  collectgarbage("collect"); collectgarbage("collect")
  collectgarbage("stop")
  -- A full collect halves an oversized Lua stack, so the next deep call regrows it: 1776 bytes billed
  -- once, to whichever scenario ran first (0.9 B/iter here). One call under the stopped collector
  -- pays that outside the measured loop.
  fn()
  scans = 0
  local before = collectgarbage("count")
  local t0 = os.clock()
  loop(n, fn)
  local t1 = os.clock()
  local after = collectgarbage("count")
  collectgarbage("restart")
  local r = { name = name, iterations = n, totalMs = (t1 - t0) * 1000, msPerIter = (t1 - t0) * 1000 / n,
              scansPerIter = scans / n, bytesPerIter = math.max(0, (after - before) * 1024 / n) }
  results[#results + 1] = r
  return r
end

-- Scenario 1 — zero overhead (performance-§2/§9): a DROPPED loot line (below the quality gate, the
-- common in-raid case) through the bracketed handler with capture off allocates no more than the
-- unbracketed body.
NS.db.profile.settings.qualityThreshold = 5
NS.Collector:RefreshUpvalues()
local line = string.format(mocks.LOOT_ITEM_SELF, "|cffa335ee|Hitem:211296::::::::80:::::|h[Vial]|h|r")
NS.Perf.on = false
local bracketed = measure("lootDroppedBracketed", 2000, function() NS.Collector:OnChatMsgLoot(nil, line) end)
local bare = measure("lootDroppedBare", 2000, function() NS.Collector._lootLine(NS.Collector, line) end)
check("zero-overhead: dropped loot line, capture off", bracketed.bytesPerIter <= bare.bytesPerIter,
  ("%.1f B/iter bracketed vs %.1f bare"):format(bracketed.bytesPerIter, bare.bytesPerIter))

-- Scenario 2 — an in-combat BAG_UPDATE storm is dirty bits only: no allocation after warm-up, no scan.
mocks.InCombatLockdown = function() return true end
measure("combatBagUpdate", 5000, function() NS.Reconciler:OnEvent("BAG_UPDATE", 0) end)
mocks.InCombatLockdown = function() return false end

-- Scenario 3 — one out-of-combat reconcile over a full bag set: scan calls are bounded by the
-- number of bags (one ScanContainers per dirty container group), never per slot.
for bag = 0, 5 do
  mocks.__bagSlots[bag] = 36
  mocks.__bags[bag] = {}
  for s = 1, 36 do mocks.__bags[bag][s] = { itemID = 1000 + s, link = "L", count = 1 } end
end
NS.Reconciler:LoginScan()
NS.Reconciler.dirty = {}
measure("reconcileCleanBags", 200, function()
  NS.Reconciler:MarkDirty("bags"); NS.Reconciler:Flush()
end)
NS.Scanner.ScanContainers = baseScan

for _, r in ipairs(results) do
  local ceiling, want = BYTE_CEILING[r.name], SCANS_PER_ITER[r.name]
  check(r.name .. ": bytes under the ceiling", ceiling ~= nil and r.bytesPerIter <= ceiling,
    ("%.1f B/iter, ceiling %s"):format(r.bytesPerIter, tostring(ceiling)))
  check(r.name .. ": scans pinned", want ~= nil and math.abs(r.scansPerIter - want) < 1e-9,
    ("%.2f scans/iter, pinned at %s"):format(r.scansPerIter, tostring(want)))
end

-- The report. Five columns, exactly: tests/_kit/run-automated-tests.sh counts scenarios as the
-- five-field rows under this header, up to the first blank line.
print()
print(("Ka0s Loot History \226\128\148 offline perf  (v%s, label '%s')"):format(tostring(NS.version), opts.label))
print()
print(("%-24s %8s %11s %10s %11s"):format("scenario", "iters", "ms/iter", "scans/iter", "bytes/iter"))
for _, r in ipairs(results) do
  print(("%-24s %8d %11.5f %10.2f %11.1f"):format(r.name, r.iterations, r.msPerIter, r.scansPerIter, r.bytesPerIter))
end
print()
print("timings are for orientation only \226\128\148 compare scenarios within a run, never across machines")

local function writeRecord(path)
  local buckets = {}
  for _, r in ipairs(results) do
    buckets[r.name] = { calls = r.iterations, totalMs = r.totalMs, maxMs = r.msPerIter,
                        scansPerIter = r.scansPerIter, bytesPerIter = r.bytesPerIter }
  end
  local fh, err = io.open(path, "w")
  if not fh then
    io.stderr:write("cannot write " .. path .. ": " .. tostring(err) .. "\n")
    os.exit(2)
  end
  fh:write(NS.Perf.EncodeJSON({
    schema = 1, addon = "LootHistory", source = "offline", version = tostring(NS.version), interface = 0,
    timestamp = os.time(), label = opts.label, buckets = buckets, failures = failures,
  }), "\n")
  fh:close()
  print("wrote " .. path)
end

if opts.out then writeRecord(opts.out) end
if failures > 0 then os.exit(1) end
