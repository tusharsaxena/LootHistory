local _, NS = ...

-- core/SimSeam.lua: the simulator's answer seam, on LibKa0s-Sim-1.0 (library-stack-§7;
-- LootHistory#37, LibKa0s#54; Ka0sAddonsCommonTasks req-lh-sim.md §2.2, §2.4).
--
-- ── THE SEAM ─────────────────────────────────────────────────────────────────────────────────
--
-- At file load, straight after the compat family (core/Compat.lua, core/CompatClient.lua,
-- core/CompatTooltip.lua) and before any other file can read a member,
-- Sim:NewSeam wraps every NS.Compat function but the PURE ones in place, once. While a simulation
-- runs (modules/Sim.lua's NS.Sim) a wrapped member answers through its provider (registered by the
-- simulator's world module with NS.SimSeam:SetProvider); with no provider, or with no simulation
-- running, it answers live. Idle, the cost is one field test per call. This file names no client
-- API: the compat family stays the only caller (compat).
--
-- H1 and H2 are what keep it whole. Every client read the simulator answers is a Compat member read
-- at CALL time (`NS.Compat.Member(...)`); a member captured into a local at load would be the live
-- one and escape the wrap, and tests/test_compat_routing.lua scans the source for that capture. A
-- member added to NS.Compat after this file runs escapes too: NS.SimSeam:Unwrapped() lists it, and
-- tests/test_sim_seam.lua asserts that list is empty once the whole addon has loaded.
--
-- ── PURE, GUARDED, WRAPPED ───────────────────────────────────────────────────────────────────
--
--   PURE      never wrapped. The text and parse helpers answer for nobody; the tooltip family only
--             draws; the hook installers run once at stand-up, never during a simulation.
--   GUARDED   the one member that changes client state. ListCurrencies expands and collapses the
--             player's Currency-tab headers to walk the list, so while a session is active it
--             answers the simulated world's list (NS.SimHost.world.currencies, modules/SimWorld.lua)
--             or nothing, and never reaches C_CurrencyInfo.ExpandCurrencyList, inside Live included.
--   WRAPPED   everything else: the item, spell and currency reads (the simulated player is the real
--             player, so live is right for them), the world reads the simulator provides, and the
--             three world rules (InInstance, InGroup, PlayerInCombat) its refusal and its automatic
--             stop read only through NS.SimSeam:Live.
--
-- ── LIBRARY ABSENT ───────────────────────────────────────────────────────────────────────────
--
-- Nothing is wrapped and NS.SimSeam is the inert stub (Live calls fn; SetProvider does nothing;
-- Keys and Unwrapped answer {}), and modules/Sim.lua publishes NS.Sim as the session stub built by
-- NS.SimHost.NewSimStub, which starts nothing and says why. Both are the reference stubs of LibKa0s
-- tests/test_sim_stub.lua, member for member (H9), because hot real-event paths call
-- NS.Sim:IsActive() and NS.SimSeam:Live(...) unconditionally: one missing member would raise on
-- exactly the degraded path the stub exists to survive.
--
-- ── THE HOST TABLE ───────────────────────────────────────────────────────────────────────────
--
-- NS.SimHost holds everything that is LootHistory's own about the simulation (OWNER_SCOPE C.4):
-- the stub factories here, and the session's world, counters and hooks (modules/Sim.lua and the
-- Sim* modules after it). Nothing is ever written onto the library's seam or instance.

NS.SimHost = NS.SimHost or {}
local Host = NS.SimHost

local Sim = LibStub and LibStub("LibKa0s-Sim-1.0", true)

-- Never wrapped (req-lh-sim §2.2). Written as fields so tests/test_compat_routing.lua's scans never
-- read a key as a call.
local PURE = {
  FoldNBSP = true, IsAuctionHouseMail = true, DecodeGUID = true, BindState = true, BestBound = true,
  CurrencyLinkID = true, AuctionMailKind = true, CurrencySourceName = true, InteractionType = true,
  BankerKind = true, UnreadyBankContainers = true,
  ShowItemTooltip = true, ShowCurrencyTooltip = true, ShowTextTooltip = true, ShowAmountTooltip = true,
  ShowLinesTooltip = true, ShowTintedTooltip = true, ShowLineTooltip = true, HideTooltip = true,
  OwnTooltip = true, PlaceTooltip = true,
  HookUseContainerItem = true, HookGetQuestReward = true, HookSecure = true, HookSecureMember = true,
  -- The holdings tooltip (#34): the post-call installer, the id readers and guards, and the painters
  -- answer for nobody; IsSecret is the secret test they all ask.
  HookTooltipType = true, TooltipItemID = true, TooltipCurrencyID = true, TooltipWritable = true,
  IsComparisonTooltip = true, AppendTooltipRows = true, TooltipTint = true, FormatCount = true,
  IsSecret = true,
}

-- The safe answers while a session is active (req-lh-sim §2.4). A provider, when one is set, gets
-- this as its fallback; the live member is never reached.
local GUARDED = {}
GUARDED.ListCurrencies = function()
  local world = Host.world
  return (world and world.currencies) or {}
end

--- The guarded keys, sorted: the diagnostics report's `sim` section names them
--- (modules/Diagnostics.lua), since the seam answers only its wrapped keys.
Host.GUARDED_KEYS = {}
for key in pairs(GUARDED) do Host.GUARDED_KEYS[#Host.GUARDED_KEYS + 1] = key end
table.sort(Host.GUARDED_KEYS)

-- ── the sample characters (preview-mode "Sample characters", LibKa0s#87 and #104) ───────────
--
-- The made-up people test mode and the simulator draw are the library's and only the library's
-- (LibKa0s#104, decision D1 of Ka0sAddonsCommonTasks docs/2026-11-24-FEEDBACK_BATCH; Sim minor 5,
-- LibKa0s v1.113.0): LibKa0s-Sim-1.0's five protagonists (Sim.Sample) and its seeded crowd beyond
-- them (Sim.SampleCrowd), read for the client running, picked once at file load by
-- NS.Compat.ClientKey() (clients-§5): Retail's are `Name-Realm`, WoW Forever's "First Surname" with no
-- realm in the key (forever-quirks-§4), each the shape NS.Util.PlayerKey gives a holder on that
-- client. This addon keeps no copy of either: without the library both answer an empty list, and
-- tests/test_testdata.lua holds the shipped code to typing no sample name at all. Names are data,
-- never localized. Users: the History sample (modules/BrowserTableTestData.lua) and through it the
-- Holdings and Timeline samples (modules/TestData.lua), and the simulator's alt and stranger
-- (modules/Sim.lua, modules/SimScenario.lua).
local SAMPLE_CLIENT = NS.Compat.ClientKey() == "forever" and "forever" or "retail"

--- A fresh copy of the five sample characters, the caller's own: the library's set for this client,
--- else none.
function NS.SampleCharacters()
  if Sim and Sim.Sample then return Sim.Sample(SAMPLE_CLIENT) end
  return {}
end

--- `n` sample people beyond the five, the caller's own: the library's crowd for this client at
--- `seed` (the same seed answers the same crowd), `n` clamped to its CROWD_MAX, else none.
function NS.SampleCrowd(n, seed)
  if not (Sim and Sim.SampleCrowd) then return {} end
  n = math.max(0, math.min(math.floor(tonumber(n) or 0), Sim.CROWD_MAX or 0))
  return Sim.SampleCrowd(SAMPLE_CLIENT, n, seed)
end

-- ── the reference stubs (LibKa0s tests/test_sim_stub.lua) ────────────────────────────────────

local NEEDS_LINE = "The simulator needs LibKa0s-Sim-1.0."

--- The seam's four members, inert.
function Host.NewSeamStub()
  local seam = {}
  function seam.SetProvider() end
  function seam.Live(_, fn, ...) return fn(...) end
  function seam.Keys() return {} end
  function seam.Unwrapped() return {} end
  return seam
end

--- The session instance's surface, inert: nothing starts, and a start or a verb prints `say`'s line.
function Host.NewSimStub(say)
  local sim = {}
  local function no() return false end
  local function noop() end
  local function absent() return false, "absent" end
  sim.IsActive, sim.IsDelivering, sim.IsPanelShown = no, no, no
  function sim.Fire() return 0 end
  function sim.DeliverForCleanup() return 0 end
  function sim.After() return nil end
  function sim.Start() say(NEEDS_LINE); return false, NEEDS_LINE end
  sim.Stop = no
  sim.OnStop, sim.OnStopGuarded, sim.AddListener = noop, noop, noop
  function sim.Status() return { active = false } end
  function sim.Session() return nil end
  function sim.Steps() return {} end
  function sim.Step() return nil, "absent" end
  sim.Run, sim.Pause, sim.Resume, sim.Restart = absent, absent, absent, absent
  function sim.RunVerb() say(NEEDS_LINE); return false, "absent" end
  sim.ShowPanel, sim.TogglePanel = no, no
  sim.HidePanel, sim.RefreshPanel, sim.ResetPanelPosition = noop, noop, noop
  function sim.PanelRows() return {} end
  return sim
end

-- ── the seam ─────────────────────────────────────────────────────────────────────────────────

if Sim then
  NS.SimSeam = Sim:NewSeam(NS.Compat, {
    name = "LootHistory",
    pure = PURE,
    guarded = GUARDED,
    -- Live's traceback sink until the session binds; gated at the call site like every tag
    -- (docs/debug.md). NS.State and NS.Debug are read at call time: both load after this file.
    debug = function(_, fmt, ...)
      if NS.State and NS.State.debug and NS.Debug then NS.Debug("Sim", fmt, ...) end
    end,
  })
else
  NS.SimSeam = Host.NewSeamStub()
end
