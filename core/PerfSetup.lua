local addonName, NS = ...

-- core/PerfSetup.lua — the addon's half of LibKa0s-Perf-1.0 (performance-§1).
--
-- The probe, the guided A/B run, the record schema and the step panel are the library's. This file
-- supplies what only this addon can know: which handlers are worth measuring, and the latch that
-- makes it inert.
--
-- TOC POSITION, LOAD-BEARING: directly after core/LifecycleSetup.lua. `lib:New` reads NS.Lifecycle
-- at load (Perf minor 12 requires the latch and raises without it), and every module that takes
-- `local Perf = NS.Perf` as a load-time upvalue (Collector, Attribution, Reconciler) loads below.
-- The log/print/showLog sinks are closures resolved at call time, so DebugLogSetup below is fine.
--
-- WHY THIS ADDON NOW HAS ONE. It held the performance-§12 no-combat-path exemption until the
-- timeline ledger (spec §13 F2): holdings diffing put real work behind BAG_UPDATE, money and
-- currency events, which is exactly the exemption's re-check trigger. The buckets are the five
-- handlers that run in combat; the reconcile itself never does (Reconciler:Flush defers to
-- PLAYER_REGEN_ENABLED) and is measured offline by tests/perf.lua instead.
--
-- Suspend no longer loses data the way the old criterion (c) feared: what changes while window B
-- holds the `perf` hold is read back on resume as UNTRACKED drift (Reconciler:Enable -> LoginScan).

local lib = LibStub and LibStub("LibKa0s-Perf-1.0", true)

-- The degradation stub (performance-§1): every member the addon calls — the gate field, the bracket
-- sinks and the slash entry point — so a missing diagnostics library cannot break capture.
local function stub()
  local noop = function() end
  return {
    on = false, suspended = false, BUCKET_ORDER = {},
    Note = noop, Open = noop, Close = noop, Suspend = noop, Resume = noop,
    OnCommand = function() return { "perf capture unavailable." } end,
  }
end

if not (lib and NS.Lifecycle) then
  NS.Perf = stub()
  return
end

NS.Perf = lib:New({
  name      = addonName,        -- seeds the sampler/panel frame globals
  addonName = addonName,        -- the folder the panel's close mark is built from
  title     = "Loot History",   -- the library appends " — Perf Run"
  slash     = "/lh",
  -- Its OWN SavedVariables global (performance-§5), declared in the TOC beside LootHistoryDB and
  -- kept outside the AceDB tree.
  sv        = "LootHistoryPerfDB",
  -- The TOC manifest first, as `/lh version` prints it (core/EnvSetup.lua): a record stamped with a
  -- version that drifted from the packaged build is unattributable (performance-§8). Resolved once
  -- at :New, which is why EnvSetup sits above this file.
  version   = NS.Version and NS.Version() or NS.version,
  lifecycle = NS.Lifecycle,     -- P.Suspend/Resume take and release the `perf` hold
  -- Ungated: a perf run is an explicit user act; routing through NS.Debug would swallow it.
  log     = function(line)
    if NS.DebugLog and NS.DebugLog.Add then NS.DebugLog:Add("Perf", line) else NS.Print(line) end
  end,
  print   = function(line) NS.Print(line) end,
  showLog = function()
    if NS.DebugLog and NS.DebugLog.Show and not NS.DebugLog:IsShown() then NS.DebugLog:Show() end
  end,
  -- No `L`: the library's own English, never NS.L (tests/test_libka0s.lua pins why).
  buckets = {
    { key = "lootLine" },       -- Collector:OnChatMsgLoot (every loot line in the raid)
    { key = "currencyLine" },   -- Collector:OnChatMsgCurrency
    { key = "moneyLine" },      -- Collector:OnChatMsgMoney
    { key = "spellCast" },      -- Attribution:OnSpellSucceeded (every player cast)
    { key = "ledgerEvent" },    -- Reconciler:OnEvent (BAG_UPDATE storms, money, currency: dirty bits)
  },
})
