local _, NS = ...

-- modules/Sim.lua: the simulator's session host, on LibKa0s-Sim-1.0 (LootHistory#37, LibKa0s#54;
-- req-lh-sim.md §4-§5). Binds NS.SimSeam (core/SimSeam.lua) to one session with Sim:New and
-- publishes it as NS.Sim. Everything that is LootHistory's own lives on NS.SimHost, never on the
-- library's instance (OWNER_SCOPE C.4).
--
-- ── THE PRINCIPLE ────────────────────────────────────────────────────────────────────────────
--
-- `/lh sim` runs the REAL capture engine against an invented world. The simulator invents the
-- inputs at the edges (the seam's providers, modules/SimWorld.lua; the events and hook calls it
-- fires through NS.Sim:Fire, which this descriptor hands to NS.DeliverAll, core/Dispatch.lua) and
-- the engine decides every source, reason and row. It never calls Database:Add, Holdings:Apply*,
-- Attribution:Stamp or R:Write itself. Test mode is the opposite (fixed preview data), so each
-- refuses while the other runs.
--
-- ── SAVED DATA STAYS UNTOUCHED (H4) ──────────────────────────────────────────────────────────
--
-- The start swaps fresh session tables into NS.SimStores (core/State.lua): every capture-path
-- accessor (Database's history, Holdings:Store, Rollup:Store) reads them first, so a simulated row
-- lands in the session and nowhere else. The stop puts nil back and every accessor answers the
-- saved store again. The destructive surfaces (purge, the ledger reset, Forget this character, a
-- row's Delete and a retention change that would prune) refuse while a session runs, through
-- NS.SimBlocks below; the maintenance paths that write NS.db.global directly cannot race the swap,
-- because the start refuses until the login deferrals have run (NS.State.loginSettled).
--
-- ── REAL INPUT DURING A SESSION ──────────────────────────────────────────────────────────────
--
-- Every live capture registration and installed hook goes through NS.Deliver / NS.DeliverHook,
-- whose one hook point is NS.RealEventFilter. The start sets it to Host.OnRealEvent, the stop puts
-- nil back. A real event that is not the simulator's own delivery is either:
--   INTERFERENCE  a self loot, currency or money line, a loot window, an encounter or key start, a
--                 quest turn-in, a trade, a sent mail, an interaction frame, or any real hook call:
--                 the session stops with reason `world`, and the event then runs live into the
--                 saved stores, so no real loot is lost;
--   SETUP         ADDON_LOADED (the guild bank frame's hook install): delivered live, no stop;
--   ABSORBED      everything else (bags, money, currency, equipment, bank, auctions, spell casts,
--                 another player's chat line): dropped. The stop's drift pass sees what it changed.
-- A private world-watch target, registered only while a session runs, stops it on a real group
-- (`group`), a real instance (`instance`) and combat (`combat`). The stand-down stops it first of
-- all (`standDown`, core/LifecycleSetup.lua's first STAND_DOWN_STEPS step, H6), and a profile
-- switch, copy or reset (`profile`, NS.OnProfileEvent). Nothing is saved, so /reload ends it too.
--
-- ── THE STOP ─────────────────────────────────────────────────────────────────────────────────
--
-- The library's two-phase stop runs the OnStop steps below with the seam already off, each under
-- pcall: cancel the Reconciler's flush and recheck fuses, reset its state and the attribution
-- contexts (a simulated stamp or claim must never attribute the next real loot), release the
-- session stores, take the real-event split and the world watch down, schedule a real LoginScan one
-- second out unless the stop is a stand-down (whatever really changed meanwhile becomes UNTRACKED
-- drift, as after a disable and enable), tell the History window and the two buses, then clear the
-- host's session fields with one [Sim] line.

NS.SimHost = NS.SimHost or {}
local Host = NS.SimHost
local L = NS.L

-- The pause after each step before `run` plays the next one: a fixed constant, never a schema row
-- (OWNER_SCOPE C.11). The host gate (modules/SimScenario.lua) holds the next step while the ledger
-- settles, so this only paces the run for the eye.
local SIM_STEP_DELAY = 1.5

--- The scenarios, filled in place at file load by modules/SimScenario.lua (the library reads them
--- at call time): { names = { ordered }, defs = { [name] = def } }.
Host.SCENARIOS = Host.SCENARIOS or { names = {}, defs = {} }

-- The scenarios whose steps record through the ledger, refused while gains and losses are off.
local LEDGER_SCENARIOS = { vendor = true, ah = true, bank = true, social = true }

local function debug(fmt, ...)
  if NS.State.debug and NS.Debug then NS.Debug("Sim", fmt, ...) end
end

local function trackLedgerOn()
  local s = NS.db and NS.db.profile and NS.db.profile.settings
  return s ~= nil and s.trackLedger ~= false
end

-- ── refusals (req-lh-sim §5.1) ────────────────────────────────────────────────────────────────

-- Each answers its line or nil, checked in this order. The library runs the refusal inside
-- NS.SimSeam:Live, so the world reads below answer the real client.
local CHECKS = {
  function()
    if NS.IsStoodDown() then
      return NS.RefusalLine() or L["A simulation cannot start while the addon is disabled."]
    end
  end,
  function()
    if NS.BrowserTable and NS.BrowserTable.testMode then
      return L["Turn test mode off before starting a simulation."]
    end
  end,
  function() if NS.Compat.PlayerInCombat() then return L["A simulation cannot start in combat."] end end,
  function() if NS.Compat.InInstance() then return L["A simulation cannot start inside an instance."] end end,
  function()
    if NS.Compat.InGroup() then return L["A simulation cannot start in a group: leave it first."] end
  end,
  -- A real interaction frame: its readable and scope state would interleave with the simulated one.
  function()
    if next(NS.State.scopes) ~= nil or next(NS.Reconciler.readable or {}) ~= nil then
      return L["A simulation cannot start while a merchant, mailbox, bank or auction house window is open."]
    end
  end,
  -- A real classification still in flight: the start's reset would discard it.
  function()
    local R = NS.Reconciler
    if R._pending or R._holdSince or R.deferred or R.loginPending then
      return L["A simulation cannot start while the ledger is still settling a change: try again in a few seconds."]
    end
  end,
  -- The login prune, bound-state repair and rollup seed write NS.db.global directly.
  function()
    if not (NS.State.cleanupDone and NS.State.loginSettled) then
      return L["A simulation cannot start until login has settled: try again in a few seconds."]
    end
  end,
  function(opts)
    if LEDGER_SCENARIOS[tostring(opts.scenario):lower()] and not trackLedgerOn() then
      return L["These steps record through the ledger, so turn on gains and losses first."]
    end
  end,
}

--- Why a simulation may not start now, as the one line to print, or nil when it may. The library
--- has already refused an unknown scenario and a second session.
function Host.Refusal(opts)
  opts = opts or {}
  for i = 1, #CHECKS do
    local line = CHECKS[i](opts)
    if line then
      debug("refused: %s", line)
      return line
    end
  end
  return nil
end

-- ── the real-event split ──────────────────────────────────────────────────────────────────────

local INTERFERENCE = {
  LOOT_OPENED = true, ENCOUNTER_START = true, CHALLENGE_MODE_START = true, QUEST_TURNED_IN = true,
  TRADE_ACCEPT_UPDATE = true, MAIL_SEND_SUCCESS = true, PLAYER_INTERACTION_MANAGER_FRAME_SHOW = true,
}

-- A chat line interferes only when it is the player's own: another player's line is absorbed.
local SELF_LINE = {
  CHAT_MSG_LOOT = function(msg) return NS.Util.ParseSelfLoot(msg) or NS.Util.ParseRollWon(msg) end,
  CHAT_MSG_CURRENCY = function(msg) return NS.Util.ParseSelfCurrency(msg) end,
  CHAT_MSG_MONEY = function(msg) return NS.Util.ParseSelfMoney(msg) end,
}

local SETUP = { ADDON_LOADED = true }

local function interferes(event, msg)
  if INTERFERENCE[event] or event:sub(1, 5) == "hook:" then return true end
  local own = SELF_LINE[event]
  return own ~= nil and own(msg) ~= nil
end

--- NS.RealEventFilter while a session runs: true consumes the real event (absorbed); false lets it
--- run live, after stopping the session when it interferes.
function Host.OnRealEvent(_, event, ...)
  local sim = NS.Sim
  if not sim:IsActive() or sim:IsDelivering() or SETUP[event] then return false end
  if interferes(event, ...) then
    debug("real %s: stopping, then recording it live", tostring(event))
    sim:Stop("world")
    return false
  end
  return true
end

-- ── the world watch ───────────────────────────────────────────────────────────────────────────

local watch

local function inInstance() return (NS.Compat.InInstance()) end
local function inGroup() return NS.Compat.InGroup() end
local function always() return true end

-- A real world event that ends the session when `read`, run with the seam off, answers true.
local function stopWhen(reason, read)
  return function()
    if NS.Sim:IsActive() and NS.SimSeam:Live(read) then NS.Sim:Stop(reason) end
  end
end

local WATCH = {
  { "GROUP_ROSTER_UPDATE", stopWhen("group", inGroup) },
  { "PLAYER_ENTERING_WORLD", stopWhen("instance", inInstance) },
  { "ZONE_CHANGED_NEW_AREA", stopWhen("instance", inInstance) },
  { "PLAYER_REGEN_DISABLED", stopWhen("combat", always) },
}

-- Its own bus target: the shared one already binds PLAYER_ENTERING_WORLD to addon:OnEnterWorld.
local function registerWatch()
  if watch then return end
  watch = NS.NewBusTarget()
  if not watch then return end
  for _, w in ipairs(WATCH) do NS.SafeRegisterEvent(watch, w[1], w[2], NS.RejectedEvents) end
end

local function unregisterWatch()
  if watch then watch:UnregisterAllEvents(); watch = nil end
end

-- ── the start (the descriptor's prepare) ──────────────────────────────────────────────────────

-- `Simalt-<realm>`, seeded into the session holdings so Attribution:IsOwnAlt answers true for it
-- (the ALT_MAIL and ALT_TRADE steps). Written through Holdings:Get, which resolves the session store.
local function seedAlt()
  local realm = NS.Util.PlayerKey():match("%-(.+)$") or "Unknown"
  local key = "Simalt-" .. realm
  NS.Holdings:Get(key, true)
  return key
end

local function datasetChanged()
  if NS.Browser and NS.Browser.OnDatasetChanged then NS.Browser:OnDatasetChanged() end
end

--- Build the session: the host fields (the world seeded from the def's fixture and the session's
--- seed, modules/SimWorld.lua), the session stores, a clean engine, the real-event split, the
--- world watch and the session's genesis, then ready. The seam is already on.
function Host.Prepare(_, def, opts, ready)
  local World = Host.World
  Host.world = World and World.New(def and def.fixture, opts and opts.seed) or {}
  Host.counts = { hooks = 0 }
  local S = NS.SimStores
  S.history, S.holdings, S.daily = {}, {}, {}
  Host.alt = seedAlt()
  NS.Reconciler:ResetState()
  NS.Attribution:ResetContexts()
  NS.RealEventFilter = Host.OnRealEvent
  registerWatch()
  -- The session holdings are empty, so this first pass is a silent genesis: no rows.
  if NS.Reconciler._enabled then NS.Reconciler:LoginScan() end
  datasetChanged()
  ready()
end

-- ── the session (LibKa0s-Sim-1.0) ─────────────────────────────────────────────────────────────

-- The stop lines for the host's own reasons and the stand-down.
local STOP_TEXT = {
  world     = L["Simulation stopped: something real happened (a loot, a trade, a mail or a window), and it is recorded as usual."],
  group     = L["Simulation stopped: you joined a group."],
  instance  = L["Simulation stopped: you entered an instance."],
  combat    = L["Simulation stopped: you entered combat."],
  standDown = L["Simulation stopped: the addon stood down (disabled, or a performance capture)."],
  profile   = L["Simulation stopped: the profile changed."],
}

-- The library's lines in this addon's words, by its STRINGS keys. STARTED makes the saved-data
-- claim the library leaves to its host (H4); the host's byte-identical before/after test backs it.
local LINES = {
  STARTED = L["Simulation started (%s): nothing is saved; your history and holdings are not touched."],
}

local function deliver(event, ...)
  local c = Host.counts
  if c and type(event) == "string" and event:sub(1, 5) == "hook:" then c.hooks = c.hooks + 1 end
  return NS.DeliverAll(event, ...)
end

-- ── the host verb: /lh sim loot [n] ────────────────────────────────────────────────────────────

-- n ad hoc self-loot lines now, from a kill: one loot window over a Creature GUID (the Rookery Bat
-- the loot scenario kills), n CHAT_MSG_LOOT lines with their bag bursts cycling through the
-- fixture's items, then the window closes. Played through the drivers (modules/SimDrivers.lua),
-- so the engine decides the source exactly as it does for a timeline step.
local LOOT_NPC, LOOT_DEFAULT, LOOT_MAX = 219000, 3, 10
local LOOT_KEYS = { "herb", "ore", "trinket" }

local function parseLoot(words)
  if words[2] == nil then return { n = LOOT_DEFAULT } end
  local n = tonumber(words[2])
  if not n or n ~= math.floor(n) then return nil end
  return { n = n }
end

local function runLoot(cmd, sim)
  if cmd.n < 1 or cmd.n > LOOT_MAX then return false, "lootCount" end
  if not sim:Status().ready then return false, "building" end
  local D = Host.Drivers
  D.LootOpened("Creature", LOOT_NPC, cmd.n)
  for i = 1, cmd.n do D.Loot(LOOT_KEYS[(i - 1) % #LOOT_KEYS + 1], 1) end
  D.LootClosed()
  NS.Print(L["Simulated a kill's %d loot lines."]:format(cmd.n))
  debug("loot verb: %d lines", cmd.n)
  return true
end

--- The descriptor's `verbs`, `why` and `usage`: the one host verb and its lines.
Host.VERBS = { loot = { parse = parseLoot, run = runLoot } }
Host.WHY = { lootCount = L["/lh sim loot takes a count from 1 to 10."] }
Host.USAGE = { L["/lh sim loot [n]: n loot lines now, from a kill (1 to 10, default 3)."] }

--- The descriptor's `panel`, filled in place at load by modules/SimPanel.lua.
Host.PANEL = Host.PANEL or {}

-- The library's `play`: the history index the step begins at goes on the host's own step table
-- (`lhFrom`), so the step's tooltip can name the rows it recorded (modules/SimPanel.lua).
local function play(step, session)
  if not Host.Play then return nil end
  step.lhFrom = #NS.Database:History()
  return Host.Play(step, session)
end

local Lib = LibStub and LibStub("LibKa0s-Sim-1.0", true)
if Lib then
  NS.Sim = Lib:New({
    name = "LootHistory",
    seam = NS.SimSeam,
    slash = "/lh sim",
    deliver = deliver,
    isStoodDown = function() return NS.IsStoodDown() end,
    scenarios = Host.SCENARIOS,
    prepare = function(...) return Host.Prepare(...) end,
    play = play,
    refusal = function(opts) return Host.Refusal(opts) end,
    gate = function(session) if Host.Gate then return Host.Gate(session) end return true end,
    stepDelay = SIM_STEP_DELAY,
    verbs = Host.VERBS,
    why = Host.WHY,
    usage = Host.USAGE,
    panel = Host.PANEL,
    stopText = STOP_TEXT,
    L = LINES,
    print = function(line) NS.Print(line) end,
    debug = function(_, fmt, ...) debug(fmt, ...) end,
  })
else
  NS.Sim = Host.NewSimStub(function(line) NS.Print(line) end)
end

-- ── the stop ──────────────────────────────────────────────────────────────────────────────────

-- The session store's holders and row count, read before the stores go (for the announce and the
-- [Sim] line), on the library's session table: the host bag.
local function releaseStores(s)
  local S = NS.SimStores
  local holders = {}
  for holder in pairs(S.holdings or {}) do holders[#holders + 1] = holder end
  s.lhHolders, s.lhRows = holders, S.history and #S.history or 0
  S.history, S.holdings, S.daily = nil, nil, nil
end

local function announce(s)
  datasetChanged()
  if NS.Database and NS.Database.FireHistoryChanged then NS.Database:FireHistoryChanged() end
  NS.Reconciler:AnnounceHolders(s.lhHolders)
end

local STOP_STEPS = {
  function()
    NS.CancelDeferral(NS.Reconciler._pending)
    NS.CancelDeferral(NS.Reconciler._recheck)
  end,
  function() NS.Reconciler:ResetState() end,
  function() NS.Attribution:ResetContexts() end,
  releaseStores,
  function()
    if NS.RealEventFilter == Host.OnRealEvent then NS.RealEventFilter = nil end
    unregisterWatch()
  end,
  -- What really changed while the session ran becomes UNTRACKED drift. Not on a stand-down: the
  -- Reconciler's own stand-up rescan covers that.
  function(_, reason)
    if reason == "standDown" then return end
    NS.After(1, function() if NS.Reconciler._enabled then NS.Reconciler:LoginScan() end end)
  end,
  announce,
  function(s, reason)
    debug("simulation stopped (%s): %d events, %d rows", tostring(reason), s.events or 0, s.lhRows or 0)
    -- The diagnostics report's `last stop` (modules/Diagnostics.lua): the reason and what it ended.
    Host.lastStop = { reason = tostring(reason), events = s.events or 0, rows = s.lhRows or 0,
      hooks = Host.counts and Host.counts.hooks or 0 }
    Host.world, Host.counts, Host.alt = nil, nil, nil
  end,
}

for _, step in ipairs(STOP_STEPS) do NS.Sim:OnStop(step) end

--- Stop a running simulation: the first stand-down step (core/LifecycleSetup.lua, H6) calls it bare
--- (`standDown`), and NS.OnProfileEvent calls it with `profile`. A no-op when none runs.
function NS.SimStop(reason)
  return NS.Sim:Stop(reason or "standDown")
end

--- A destructive surface asks this first: while a simulation runs it prints
--- "<what> is not available while a simulation runs." and answers true (refused).
function NS.SimBlocks(what)
  if not NS.Sim:IsActive() then return false end
  NS.Print(L["%s is not available while a simulation runs."]:format(what))
  debug("refused while active: %s", what)
  return true
end
