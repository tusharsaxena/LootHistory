local _, NS = ...
-- luacheck: ignore 212/self
NS.Farm = NS.Farm or {}
local Farm = NS.Farm
local FarmModel = NS.FarmModel  -- load-time upvalue: modules/FarmModel.lua loads above
local Perf = NS.Perf            -- load-time upvalue (performance-§2); core/PerfSetup.lua loads above
local C = NS.Constants

-- modules/Farm.lua — farm mode's runtime (#39, farm spec docs/superpowers/specs/2026-11-27-39-farm-mode-design.md
-- §5). modules/FarmModel.lua owns every rule over a session table; this file owns where the session
-- lives, when the clock moves, what reaches it and what it tells the rest of the addon:
--
--   store routing      LiveStore / Store / ActiveStore / Mine / Active (§5.1)
--   registration       Reconcile: with no session open, farm holds NO registration at all; with one,
--                      its rows (`farm`, `farmUnit`), the four lifecycle events, the GAIN receiver,
--                      the Database write hook, GainFeed:SetFarm and the idle ticker (§5.1)
--   the edges          Start / Pause / Resume / Finish, the verbs, Suspend at PLAYER_LOGOUT, Restore
--                      at the first stand-up, the logout intent (§5.4)
--   the tallies        gains (NS.MSG.GAIN, bucket farmGain), costs (Database:OnWrite), loot windows,
--                      containers and quests (Attribution's notifications, bucket farmWindow), zones,
--                      deaths, AFK, the deferred price pass (§5.5-§5.8)
--   the bus            NS.MSG.FARM_CHANGED, sent on every edge and tally (receivers coalesce)
--
-- THE LIFECYCLE EVENTS AND LOGOUT HOOKS ARE NOT CAPTURE ROWS. PLAYER_LOGOUT, PLAYER_CAMPING,
-- PLAYER_QUITING and LOGOUT_CANCEL register straight on Farm.__ev, and the logout-family hooks go in
-- through Compat.HookLogoutFamily, so a real logout reaches them while a simulation runs (the
-- simulator's filter absorbs every NS.Deliver row but the toasts'; farm spec §5.4, §14).

local floor = math.floor

-- Runtime-only state, keyed by the session table and never written into it (§4.2): the corpse set,
-- the items still waiting for a price (itemID -> attempts so far), and the open session's totals.
local mobSets = setmetatable({}, { __mode = "k" })
local priceQueue = setmetatable({}, { __mode = "k" })
local totalsCache = setmetatable({}, { __mode = "k" })

local LIFECYCLE_EVENTS = { "PLAYER_LOGOUT", "PLAYER_CAMPING", "PLAYER_QUITING", "LOGOUT_CANCEL" }

local function debug(fmt, ...)
  if NS.State.debug and NS.Debug then NS.Debug("Farm", fmt, ...) end
end

local function say(fmt, ...) NS.Format(fmt, ...) end

local function farmOpt(key)
  local p = NS.db and NS.db.profile
  local f = p and p.settings and p.settings.farm
  if f == nil then return nil end
  return f[key]
end

-- ── store routing (§5.1) ─────────────────────────────────────────────────────────────────────

--- db.global.farm, created if missing. PLAYER_LOGOUT, Restore and StorageStats name it directly: they
--- are live-only and never touch a simulation's session store.
function Farm:LiveStore()
  local g = NS.db and NS.db.global
  if not g then return {} end
  g.farm = g.farm or {}
  return g.farm
end

--- The store every WRITE resolves against: the simulator's session table while one runs
--- (NS.SimStores.farm, core/State.lua), otherwise the saved store.
function Farm:Store()
  local sim = NS.SimStores and NS.SimStores.farm
  return sim or self:LiveStore()
end

--- The store the session LISTS read (the Farm tab, the sessions list): test mode's session-only
--- sample (NS.State.testFarm) while it is on, else Store(). The panel's live view reads Store().
function Farm:ActiveStore()
  return (NS.State and NS.State.testFarm) or self:Store()
end

--- This character's entry in `store` (default Store()), created on demand: { sessions, nextId }.
function Farm:Mine(store, key)
  store = store or self:Store()
  key = key or NS.Util.PlayerKey()
  local mine = store[key]
  if not mine then
    mine = { sessions = {}, nextId = 1 }
    store[key] = mine
  end
  return mine
end

--- This character's open session in Store(), or nil. A read: it creates no entry.
function Farm:Active()
  local mine = self:Store()[NS.Util.PlayerKey()]
  return mine and mine.active or nil
end

--- The bus edge every receiver repaints on. `reason`: start|pause|resume|finish|gain|cost|store|
--- rename|delete.
function Farm:Changed(reason)
  if NS.bus then NS.bus:SendMessage(NS.MSG.FARM_CHANGED, reason) end
end

--- The open (or a finished) session's { money, vendor, ah, costs }: a finished one's snapshot, else
--- a cached sum dirtied by every tally and price fill.
function Farm:Totals(s)
  if s.totals then return s.totals end
  local t = totalsCache[s]
  if not t then
    t = FarmModel.Totals(s)
    totalsCache[s] = t
  end
  return t
end

local function dirty(s) totalsCache[s] = nil end

local function mobSet(s)
  local set = mobSets[s]
  if not set then
    set = FarmModel.MobSet(s)
    mobSets[s] = set
  end
  return set
end

local function forget(s)
  mobSets[s], priceQueue[s], totalsCache[s] = nil, nil, nil
end

-- ── the clock's edges (§5.2) ─────────────────────────────────────────────────────────────────

local function pause(self, s, reason, at)
  FarmModel.Pause(s, reason, at)
  debug("pause #%s (%s)", tostring(s.id), reason)
  self:Changed("pause")
end

local function resume(self, s, now)
  FarmModel.Resume(s, now)
  debug("resume #%s", tostring(s.id))
  self:Changed("resume")
end

-- A manual pause stops the tally and the clock; a stand-down pause too (F2). Costs still count.
local function closedToGains(s)
  return s.pauseReason == "manual" or s.pauseReason == "standDown"
end

-- An idle or AFK pause stops only the clock: the next tally resumes it (F2).
local function resumeOnTally(self, s, now)
  if s.pauseReason == "idle" or s.pauseReason == "afk" then resume(self, s, now) end
end

--- The idle ticker's body (§5.2, D16): stamp lastSeen, then pause a running session idle past
--- `idleMinutes`, banked back to the last gain.
function Farm:IdleTick(now)
  local s = self:Active()
  if not s then return end
  s.lastSeen = now
  local at = FarmModel.IdleAt(s, now, farmOpt("idleMinutes"))
  if at then pause(self, s, "idle", at) end
end

-- The self-re-arming idle chain. It re-arms only where NS.After really defers: headless, NS.After runs
-- straight through and the chain would never end (core/LifecycleSetup.lua).
local function armTick(self)
  if self._tick and not self._tick.canceled then return end
  self._tick = nil
  if not (C_Timer and C_Timer.NewTimer) then return end
  self._tick = NS.After(C.FARM.IDLE_TICK, function()
    self._tick = nil
    self:IdleTick(time())
    if self._live then armTick(self) end
  end)
end

-- ── the price pass (§5.5, F7) ────────────────────────────────────────────────────────────────

-- The vendor price by itemID through Compat.GetItemSellPrice (no tooltip scan: only the sell price is
-- needed), the AH price through the picker.
local function priceOf(link, itemID)
  local vu = NS.Compat.GetItemSellPrice(itemID)
  local AP, au = NS.AuctionPrice, nil
  if AP and AP.GatherAll then au = (AP:Pick(AP:GatherAll(link, itemID))) end
  return vu, au
end

--- Price up to `limit` queued items of `s` (all with nil). An item whose vendor price is still
--- unknown stays queued for PRICE_TRIES attempts, then is dropped with vu nil (Totals reads it as 0;
--- Finish tries it once more). Answers whether any price was filled and whether any item is left.
local function fillPrices(s, limit)
  local queue, filled, n = priceQueue[s], false, 0
  if not queue then return false, false end
  for itemID, tries in pairs(queue) do
    if limit and n >= limit then break end
    n = n + 1
    local it = s.items[itemID]
    if it then
      local vu, au = priceOf(it.link, itemID)
      if FarmModel.SetPrices(s, itemID, vu, au) then filled = true end
    end
    if not it or it.vu ~= nil or tries + 1 >= C.FARM.PRICE_TRIES then
      queue[itemID] = nil
    else
      queue[itemID] = tries + 1
    end
  end
  return filled, next(queue) ~= nil
end

-- Queue `itemID` of `s` for the pass (a fresh queue entry starts at 0 attempts; a queued one keeps its
-- count).
local function enqueue(s, itemID)
  local queue = priceQueue[s]
  if not queue then
    queue = {}
    priceQueue[s] = queue
  end
  if queue[itemID] == nil then queue[itemID] = 0 end
end

-- Queue every item of `s` still lacking a vendor price. The queue is runtime-only, so a restore after
-- /reload and the finish's last fill rebuild it from the session itself.
local function enqueueUnpriced(s)
  for itemID, it in pairs(s.items) do
    if it.vu == nil then enqueue(s, itemID) end
  end
end

local function armPrice(self)
  if self._price and not self._price.canceled then return end
  self._price = NS.After(C.FARM.PRICE_DELAY, function()
    self._price = nil
    self:PricePass()
  end)
end

--- The coalesced, deferred price pass: never in combat (it re-arms instead), PRICE_BATCH items at a
--- time, one FARM_CHANGED("gain") when a price landed.
function Farm:PricePass()
  local s = self:Active()
  if not (s and priceQueue[s]) then return end
  local deferrable = C_Timer and C_Timer.NewTimer
  if NS.Compat.PlayerInCombat() and deferrable then return armPrice(self) end
  local filled, left = fillPrices(s, C.FARM.PRICE_BATCH)
  if filled then
    dirty(s)
    self:Changed("gain")
  end
  if left and deferrable and self._live then armPrice(self) end
end

local function queuePrice(self, s, itemID)
  enqueue(s, itemID)
  armPrice(self)
end

-- Arm the pass when the open session still has queued items (goLive after a stand-down, a sim swap).
local function armQueued(self)
  local s = self:Active()
  local queue = s and priceQueue[s]
  if queue and next(queue) ~= nil then armPrice(self) end
end

-- ── gains (§5.5) ─────────────────────────────────────────────────────────────────────────────

-- The per-unit prices a chat gain's row carries (Collector, point-in-time), or nil without a row.
local function rowPrices(g)
  local r = g.record
  if type(r) ~= "table" then return nil, nil end
  local AP, au = NS.AuctionPrice, nil
  if AP and AP.Pick and r.auctionPrice then au = (AP:Pick(r.auctionPrice)) end
  return r.vendorPrice, au
end

--- One GAIN payload. `g` is the feed's reused scratch: FarmModel copies values only.
function Farm:OnGain(g)
  local s = self:Active()
  if not s or closedToGains(s) then return end
  local now = time()
  local vu, au = rowPrices(g)
  local tallied, needs = FarmModel.ApplyGain(s, g, now, vu, au)
  if not tallied then return end
  s.lastGainAt, s.lastSeen = now, now
  dirty(s)
  resumeOnTally(self, s, now)
  if needs then queuePrice(self, s, needs) end
  self:Changed("gain")
end

-- GAIN is sent only from inside GainFeed:Send's gainSend bracket, so the parent is always gainSend
-- (core/PerfSetup.lua declares farmGain `within = "gainSend"`; performance-§3).
local function onGain(_, g)
  local t0 = Perf.on and debugprofilestop()
  Farm:OnGain(g)
  if t0 then Perf.Note("farmGain", debugprofilestop() - t0, "gainSend") end
end

-- ── costs (§5.6, D19) ────────────────────────────────────────────────────────────────────────

-- Whether `row` is this character's own loss under a cost reason.
local function isCost(row)
  local U = NS.Util
  if type(row) ~= "table" or U.RowDir(row) ~= "OUT" then return false end
  if U.RowHolder(row) ~= U.PlayerKey() then return false end
  return C.FARM.COST_REASONS[row.source] == true
end

--- The Database write hook. `delta` is what this write changed (an amend adds only its growth), so a
--- coalesced row is counted once per delta. Costs count paused or running (F2).
function Farm:OnWrite(row, delta)
  if NS.IsStoodDown() then return end
  local s = self:Active()
  if not s or not isCost(row) then return end
  local kind, now, counted = NS.Util.RowKind(row), time(), false
  if kind == "GOLD" then
    counted = FarmModel.ApplyCost(s, row.source, delta, now)
  elseif kind == "CURRENCY" and row.source == C.SourceType.BUY then
    counted = FarmModel.ApplyCurrencyCost(s, row.currencyID, delta, now)
  end
  if not counted then return end
  s.lastSeen = now
  dirty(s)
  self:Changed("cost")
end

local function onWrite(row, delta) Farm:OnWrite(row, delta) end

-- ── loot windows, containers and quests (§5.7, Attribution's notifications) ────────────────

local scratch = {}

-- Every creature GUID of every slot, each corpse once (AoE loot carries several per slot; a skinning
-- window repeats a corpse already counted, F11).
local function countMobs(s, n)
  local Compat, set, any = NS.Compat, mobSet(s), false
  for slot = 1, n or 0 do
    for i = 1, Compat.LootSourceGUIDs(slot, scratch) do
      local guid = scratch[i]
      if not Compat.IsSecret(guid) then
        local kind = Compat.DecodeGUID(guid)
        if (kind == "Creature" or kind == "Vehicle") and FarmModel.NoteMob(s, set, guid) then any = true end
      end
    end
  end
  return any
end

-- An Item window inside the container hook's stamp was counted by OnContainerOpened already.
local function countContainer(self, s)
  local Compat = NS.Compat
  local guid = Compat.LootSourceGUIDs(1, scratch) > 0 and scratch[1] or nil
  local fromHook = guid ~= nil and not Compat.IsSecret(guid) and Compat.DecodeGUID(guid) == "Item"
    and GetTime() - (self._containerAt or -1e9) <= C.CONTAINER_TTL
  if fromHook then
    self._containerAt = nil
    return false
  end
  s.activity.containers = s.activity.containers + 1
  return true
end

local WINDOW = {
  FISHING   = function(_, s) s.activity.fish = s.activity.fish + 1; return true end,
  GATHERING = function(_, s) s.activity.nodes = s.activity.nodes + 1; return true end,
  KILL      = function(_, s, n) return countMobs(s, n) end,
  CONTAINER = function(self, s) return countContainer(self, s) end,
  MPLUS     = function(self, s) return countContainer(self, s) end,
}

-- One activity tally: lastSeen (never lastGainAt), an idle/AFK pause resumed, the edge sent.
local function tallied(self, s)
  local now = time()
  s.lastSeen = now
  resumeOnTally(self, s, now)
  self:Changed("gain")
end

--- A classified loot window (Attribution:OnLootOpened): `n` slots of `source`.
function Farm:CountWindow(source, n)
  local s = self:Active()
  local count = WINDOW[source]
  if not s or not count or closedToGains(s) then return end
  if count(self, s, n) then tallied(self, s) end
end

--- Attribution's notification, bracketed `farmWindow` (top level: the loot-window and container
--- paths carry no bracket of their own).
function Farm:OnLootWindow(source, n)
  local t0 = Perf.on and debugprofilestop()
  self:CountWindow(source, n)
  if t0 then Perf.Note("farmWindow", debugprofilestop() - t0) end
end

--- A bag container opened (Attribution's container hook, after its stamp).
function Farm:OnContainerOpened()
  local s = self:Active()
  if not s or closedToGains(s) then return end
  s.activity.containers = s.activity.containers + 1
  self._containerAt = GetTime()
  tallied(self, s)
end

--- A quest turned in (Attribution's QUEST_TURNED_IN): counted and logged with its title.
function Farm:OnQuestTurnedIn(questID)
  local s = self:Active()
  if not s or closedToGains(s) then return end
  s.activity.quests = s.activity.quests + 1
  local title = NS.Compat.QuestTitle(questID) or ("Quest " .. tostring(questID or "?"))
  FarmModel.Log(s, time(), "q", questID or 0, title)
  tallied(self, s)
end

-- ── zones, deaths and AFK (§5.8, EVENT_ROWS owner `Farm`) ───────────────────────────────────

function Farm:OnZone()
  local s = self:Active()
  if not s then return end
  if FarmModel.SetZone(s, (NS.Compat.Zone()), time()) then self:Changed("gain") end
end

function Farm:OnDeath()
  local s = self:Active()
  if not s then return end
  local now = time()
  s.activity.deaths = s.activity.deaths + 1
  FarmModel.Log(s, now, "d")
  s.lastSeen = now
  self:Changed("gain")
end

--- PLAYER_FLAGS_CHANGED for `player`: an AFK flag pauses a running session at that moment (F3), and
--- clearing it resumes an AFK pause. A nil answer (secret or unknown) changes nothing. When the idle
--- rule would already pause (the client's auto-AFK and the idle limit both sit near 5 minutes, and the
--- idle ticker checks every 30 s), the AFK pause banks back to the idle rule's moment instead, so the
--- dead minutes come off the clock whichever lands first (D16).
function Farm:OnFlags(unit)
  if unit ~= nil and unit ~= "player" then return end
  local s = self:Active()
  local afk = s and NS.Compat.IsPlayerAFK()
  if afk == nil then return end
  local now = time()
  if afk and s.runningSince and farmOpt("pauseOnAFK") ~= false then
    pause(self, s, "afk", FarmModel.IdleAt(s, now, farmOpt("idleMinutes")) or now)
  elseif not afk and s.pauseReason == "afk" then
    resume(self, s, now)
  end
end

NS.EventRow("Farm", "farm", "ZONE_CHANGED_NEW_AREA", function() Farm:OnZone() end)
NS.EventRow("Farm", "farm", "PLAYER_DEAD", function() Farm:OnDeath() end)
NS.EventRow("Farm", "farmUnit", "PLAYER_FLAGS_CHANGED", function(_, unit) Farm:OnFlags(unit) end, "player")

-- ── the logout intent (§5.4) ─────────────────────────────────────────────────────────────────

--- A logout-family call or PLAYER_CAMPING / PLAYER_QUITING: this character is leaving.
function Farm:OnLogoutIntent()
  if NS.IsStoodDown() then return end
  NS.State.farmLogoutIntent = GetTime()
end

--- CancelLogout, a reload or LOGOUT_CANCEL: the leaving is off.
function Farm:OnLogoutCancel()
  if NS.IsStoodDown() then return end
  NS.State.farmLogoutIntent = nil
end

local function intentHolds()
  local stamp = NS.State.farmLogoutIntent
  return stamp ~= nil and GetTime() - stamp <= C.FARM.INTENT_TTL
end

-- ── finishing (§5.4, F6) ─────────────────────────────────────────────────────────────────────

function Farm:Keep()
  local g = NS.db and NS.db.global
  local keep = g and g.farmKeep
  if keep == nil then keep = NS.defaults and NS.defaults.global and NS.defaults.global.farmKeep or 0 end
  return keep
end

-- Close `mine.active` at `at` for `reason`: the last price fill, the pure close, then into the saved
-- list and the cap (or discarded, F6). Answers the saved session, or nil when it was discarded.
local function finishMine(self, mine, reason, at)
  local s = mine.active
  enqueueUnpriced(s)
  fillPrices(s)
  local kept = FarmModel.Close(s, reason, at)
  mine.active = nil
  forget(s)
  if kept then
    mine.sessions[#mine.sessions + 1] = s
    local trimmed = FarmModel.TrimCap(mine.sessions, self:Keep())
    debug("finish #%s (%s): %d lines, value %d", tostring(s.id), reason, #s.log,
      FarmModel.Value(s.totals, "ah", "gross"))
    if trimmed > 0 then debug("trim: %d saved session(s) over the cap of %d", trimmed, self:Keep()) end
  else
    debug("discard #%s (%s): nothing was gained", tostring(s.id), reason)
  end
  self:Reconcile()
  self:Changed("finish")
  return kept and s or nil
end

local function headline(s)
  local measure, basis = farmOpt("headlineValue") or "ah", farmOpt("headlineBasis") or "gross"
  return FarmModel.Value(Farm:Totals(s), measure, basis)
end

--- Finish the open session (Store()) at `at` for `reason`. Answers the saved session or nil.
function Farm:Finish(reason, at)
  local mine = self:Mine()
  if not mine.active then return nil end
  return finishMine(self, mine, reason, at or time())
end

-- ── the verbs (§8; the bare verb toggles the companion panel, M4.2) ──────────────────────────

local function refused()
  local why = NS.RefusalLine and NS.RefusalLine()
  if why then NS.Print(why) end
  return why ~= nil
end

function Farm:Start()
  if refused() then return nil end
  local mine = self:Mine()
  if mine.active then
    debug("refused start: session #%s is open", tostring(mine.active.id))
    say("a farm session is already running.")
    return nil
  end
  local now = time()
  local s = FarmModel.New(now, mine.nextId, NS.Util.PlayerKey(), NS.Compat.PlayerClassFile(), (NS.Compat.Zone()))
  mine.nextId = mine.nextId + 1
  mine.active = s
  self:Reconcile()
  debug("start #%d in %s", s.id, s.zone ~= "" and s.zone or "?")
  self:Changed("start")
  say("farm session started.")
  if farmOpt("showPanelOnStart") ~= false and NS.FarmPanel then NS.FarmPanel:Show() end
  return s
end

local function noSession()
  debug("refused: no session is open")
  say("no farm session is running.")
end

-- The session-edge verbs ask the refusal line first, as Start does: the slash gate keys on the stored
-- switch only, and during a perf-capture stand-down the session is paused `standDown` with nothing
-- tallied, so a resume would run the clock over an untallied span and a pause would keep the stand-up
-- from resuming it.
function Farm:PauseVerb()
  if refused() then return end
  local s = self:Active()
  if not s then return noSession() end
  if s.pauseReason == "manual" then return say("the farm session is already paused.") end
  local now = time()
  if s.runningSince then
    pause(self, s, "manual", now)
  else
    -- An idle or AFK pause becomes a manual one: the clock is already banked.
    s.pauseReason = "manual"
    FarmModel.Log(s, now, "p", "manual")
    self:Changed("pause")
  end
  say("farm session paused.")
end

function Farm:ResumeVerb()
  if refused() then return end
  local s = self:Active()
  if not s then return noSession() end
  if s.runningSince then return say("the farm session is not paused.") end
  resume(self, s, time())
  say("farm session resumed.")
end

--- The manual finish (the verb, the panel's button, the key binding from M4.5): the chat line, then
--- the summary window on the saved session (modules/FarmDetails.lua, farm spec §7.4).
function Farm:FinishVerb()
  if refused() then return end
  if not self:Active() then return noSession() end
  local at = time()
  local kind = (NS.SimStores and NS.SimStores.farm) and "sim" or "live"
  local mine = self:Mine()
  local s = finishMine(self, mine, "manual", at)
  if not s then return say("farm session discarded: nothing was gained.") end
  say("farm session finished: %s, %s in %s.", s.name, FarmModel.CopperText(headline(s)),
    FarmModel.Clock(s.activeSec))
  if NS.FarmDetails and NS.FarmDetails.OpenSummary then
    NS.FarmDetails:OpenSummary({ store = kind, char = s.char, id = s.id })
  end
end

local function stateWords(s)
  if s.runningSince then return "running" end
  return "paused (" .. tostring(s.pauseReason) .. ")"
end

function Farm:PrintStatus()
  local s = self:Active()
  if not s then return say("no farm session is running.") end
  local active = FarmModel.Elapsed(s, time())
  local value = headline(s)
  say("farm session %s in %s: %s active, %s (%s/h).", stateWords(s), s.zone ~= "" and s.zone or "?",
    FarmModel.Clock(active), FarmModel.CopperText(value), FarmModel.RateText(FarmModel.PerHour(value, active)))
end

local VERBS = { start = "Start", pause = "PauseVerb", resume = "ResumeVerb", finish = "FinishVerb" }

--- `/lh farm [start|pause|resume|finish]`. settings/Schema.lua's row; the feature-verb gate runs first.
--- Bare toggles the companion panel (modules/FarmPanel.lua); the status line answers only where the
--- panel module is absent.
function Farm:RunVerb(rest)
  local w = rest and tostring(rest):lower():match("^%s*(%S*)") or ""
  if w == "" then
    if NS.FarmPanel then return NS.FarmPanel:Toggle() end
    return self:PrintStatus()
  end
  local m = VERBS[w]
  if m then return self[m](self) end
  say("usage: /lh farm [start|pause|resume|finish]")
end

-- ── the Farm page's rows (§9.2; settings/SchemaFarm.lua) ─────────────────────────────────────

--- A Farm row was written (`leaf` under settings.farm, value `v`): the two the open session reacts to.
--- `idleMinutes` re-arms the idle ticker, so the new limit is read from a fresh interval; `pauseOnAFK`
--- turned off resumes an AFK pause, which nothing would otherwise end while the flag stands.
function Farm:OnSettingChanged(leaf, v)
  if leaf == "idleMinutes" and self._live then
    NS.CancelDeferral(self._tick)
    self._tick = nil
    armTick(self)
  elseif leaf == "pauseOnAFK" and v == false then
    local s = self:Active()
    if s and s.pauseReason == "afk" then resume(self, s, time()) end
  end
end

-- ── the saved-sessions cap (D18; the confirm is settings/SchemaFarm.lua's) ───────────────────

--- How many saved sessions, over every character in the saved store, a cap of `keep` would drop.
function Farm:CountOverCap(keep)
  if not keep or keep <= 0 then return 0 end
  local n = 0
  for _, mine in pairs(self:LiveStore()) do
    local over = #(mine.sessions or {}) - keep
    if over > 0 then n = n + over end
  end
  return n
end

--- Apply a new cap to every character's saved sessions. Answers how many were dropped.
function Farm:OnKeepChanged(keep)
  local n = 0
  for _, mine in pairs(self:LiveStore()) do
    if mine.sessions then n = n + FarmModel.TrimCap(mine.sessions, keep) end
  end
  if n > 0 then
    debug("trim: %d saved session(s) over the cap of %d", n, keep)
    self:Changed("delete")
  end
  return n
end

-- ── the saved sessions' readers and edits (§7.5, §7.6; M4.4) ─────────────────────────────────

--- Every character in ActiveStore() with at least one saved session, as { key, classFile }, keyed
--- order. The Farm tab's Character options (modules/BrowserWidgets.lua, mode "farm").
function Farm:Characters()
  local out = {}
  for key, mine in pairs(self:ActiveStore()) do
    local list = mine.sessions
    if list and #list > 0 then out[#out + 1] = { key = key, classFile = list[#list].classFile } end
  end
  table.sort(out, function(a, b) return a.key < b.key end)
  return out
end

--- The distinct primary zones of every saved session in ActiveStore() (the Zone options, "farm").
function Farm:Zones()
  local seen, out = {}, {}
  for _, mine in pairs(self:ActiveStore()) do
    for _, s in ipairs(mine.sessions or {}) do
      local z = s.primaryZone or ""
      if not seen[z] then seen[z] = true; out[#out + 1] = z end
    end
  end
  table.sort(out)
  return out
end

Farm.TEST_REFUSAL = "test mode shows sample sessions; nothing to rename or delete."

-- The saved session `ref` ({ store, char, id }) names in Store(), with its index and its character's
-- entry; nil for a test-sample row (refused with the line), a reference to a store that is not the
-- one writes go to now, or a session that is gone.
local function savedRef(self, ref)
  if type(ref) ~= "table" or ref.id == nil then return nil end
  if ref.store == "test" then
    say(Farm.TEST_REFUSAL)
    return nil
  end
  local kind = (NS.SimStores and NS.SimStores.farm) and "sim" or "live"
  if ref.store and ref.store ~= kind then return nil end
  local mine = self:Store()[ref.char]
  for i, s in ipairs(mine and mine.sessions or {}) do
    if s.id == ref.id then return s, i, mine end
  end
  return nil
end

--- Rename a saved session (FarmModel.SessionName: an empty name restores the zone). Answers true.
function Farm:Rename(ref, name)
  local s = savedRef(self, ref)
  if not s then return false end
  s.name = FarmModel.SessionName(name, s.primaryZone)
  debug("rename #%s", tostring(s.id))
  self:Changed("rename")
  return true
end

--- Delete a saved session from Store(). Answers true.
function Farm:Delete(ref)
  local s, i, mine = savedRef(self, ref)
  if not s then return false end
  table.remove(mine.sessions, i)
  debug("delete #%s", tostring(s.id))
  self:Changed("delete")
  return true
end

-- ── suspend and restore (§5.4) ───────────────────────────────────────────────────────────────

--- PLAYER_LOGOUT. Live store only (the sim store is never persisted, and during a simulation the live
--- session is never written: it restores through rule 2). With a fresh logout intent the session is
--- finished as `logout`; without one it is suspended, its clock banked, for the next load to resume.
function Farm:OnLogout()
  if NS.IsStoodDown() or (NS.SimStores and NS.SimStores.farm) then return end
  local mine = self:LiveStore()[NS.Util.PlayerKey()]
  local s = mine and mine.active
  if not s then return end
  local now = time()
  if intentHolds() then
    finishMine(self, mine, "logout", now)
    return
  end
  s.wasRunning = s.runningSince ~= nil
  FarmModel.Bank(s, now)
  s.resumeOnLoad, s.lastSeen = true, now
  debug("suspend #%s (was running: %s)", tostring(s.id), tostring(s.wasRunning))
end

local function finishStale(self, mine, s, now)
  debug("stale #%s: last seen %ds ago", tostring(s.id), floor(now - (s.lastSeen or s.startedAt)))
  local day = FarmModel.DayLabel(s.startedAt)
  if finishMine(self, mine, "stale", s.lastSeen or s.startedAt) then
    say("farm session from %s was left open; it has been finished and saved.", day)
  else
    say("farm session discarded: nothing was gained.")
  end
end

-- Which restore rule applies (§5.4): 1 a suspend, 2 a crash while running, 3 a paused session.
local function restoreRule(s)
  if s.resumeOnLoad then return 1 end
  if s.runningSince then return 2 end
  return 3
end

-- The three rules' resumes once a session is not stale.
local RESUME = {
  function(self, s, now)
    if s.wasRunning then resume(self, s, now) end
  end,
  function(self, s, now) resume(self, s, now) end,
  function(self, s, now)
    if s.pauseReason == "standDown" then resume(self, s, now) end
  end,
}

--- The first stand-up of the client session: the saved open session suspended, crashed or left paused
--- is resumed, or finished as stale past STALE_SEC (F5). Answers the rule applied, or nil.
function Farm:Restore(now)
  local mine = self:LiveStore()[NS.Util.PlayerKey()]
  local s = mine and mine.active
  if not s then return nil end
  local rule = restoreRule(s)
  s.resumeOnLoad = nil
  if rule == 2 then FarmModel.Bank(s, s.lastSeen or s.runningSince) end
  if now - (s.lastSeen or s.startedAt) > C.FARM.STALE_SEC then
    s.wasRunning = nil
    finishStale(self, mine, s, now)
    return rule
  end
  RESUME[rule](self, s, now)
  s.wasRunning = nil
  mobSets[s] = FarmModel.MobSet(s)
  enqueueUnpriced(s)   -- the price queue is runtime-only: rebuild it; goLive arms the pass
  debug("restore #%s: rule %d", tostring(s.id), rule)
  return rule
end

-- ── registration (§5.1) ──────────────────────────────────────────────────────────────────────

local function onLifecycle(event)
  if event == "PLAYER_LOGOUT" then return Farm:OnLogout() end
  if event == "LOGOUT_CANCEL" then return Farm:OnLogoutCancel() end
  Farm:OnLogoutIntent()
end

local function goLive(self)
  self.__ev = self.__ev or NS.NewBusTarget()
  self.__unitFrame = self.__unitFrame or CreateFrame("Frame")
  NS.RegisterRows("Farm", self.__ev, "farm")
  NS.RegisterRows("Farm", self.__unitFrame, "farmUnit")
  for _, event in ipairs(LIFECYCLE_EVENTS) do
    NS.SafeRegisterEvent(self.__ev, event, onLifecycle, NS.RejectedEvents)
  end
  self.__ev:RegisterMessage(NS.MSG.GAIN, onGain)
  self._hook = NS.Database:OnWrite(onWrite)
  NS.GainFeed:SetFarm(C.FARM.GAIN_KINDS)
  self._live = true
  armTick(self)
  armQueued(self)
end

local function goDown(self)
  NS.UnregisterRows("Farm")
  if self.__unitFrame then self.__unitFrame:UnregisterAllEvents() end
  if self.__ev then
    self.__ev:UnregisterAllEvents()
    self.__ev:UnregisterAllMessages()
  end
  if self._hook then NS.Database:RemoveWriteHook(self._hook) end
  self._hook = nil
  if NS.GainFeed and NS.GainFeed.SetFarm then NS.GainFeed:SetFarm(nil) end
  NS.CancelDeferral(self._tick)
  NS.CancelDeferral(self._price)
  self._tick, self._price, self._live = nil, nil, nil
end

--- Bring the registrations in line with the store: up while a session is open and the addon stands
--- up, down otherwise. Runs after every edge (start, finish, enable, disable, store swap).
function Farm:Reconcile()
  local open = not NS.IsStoodDown() and self:Active() ~= nil
  if open and not self._live then
    goLive(self)
  elseif not open and self._live then
    goDown(self)
  end
end

--- The simulator swapped NS.SimStores.farm in or out (modules/Sim.lua).
function Farm:OnStoreSwapped()
  self:Reconcile()
  if self._live then armQueued(self) end   -- a swap that kept the module live re-arms the pass
  self:Changed("store")
end

-- ── lifecycle (core/LifecycleSetup.lua, §11.1) ───────────────────────────────────────────────

--- Stand-up, after the gain feed and every observer: the logout hooks once per client session, the
--- restore once, a stand-down pause resumed, then Reconcile (which hands GainFeed the farm set again
--- after the stand-down dropped it).
function Farm:Enable()
  if not NS.addon then return end
  if not self._hooked then
    self._hooked = true
    NS.Compat.HookLogoutFamily(function() Farm:OnLogoutIntent() end, function() Farm:OnLogoutCancel() end)
  end
  local now = time()
  if not self._restored then
    self._restored = true
    self:Restore(now)
  else
    local s = self:Active()
    if s and s.pauseReason == "standDown" then resume(self, s, now) end
  end
  self:Reconcile()
end

--- Stand-down, before the gain feed's: a running session paused `standDown` (an already paused one
--- keeps its reason), then every registration, the hook, the farm set and both deferrals down.
function Farm:Disable()
  local s = self:Active()
  if s and s.runningSince then pause(self, s, "standDown", time()) end
  if self._live then goDown(self) end
end

-- ── storage and diagnostics (§4.6, §11.5) ────────────────────────────────────────────────────

local function countOf(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

--- One session's estimated SavedVariables bytes (§4.6).
function Farm.EstimateBytes(s)
  local small = countOf(s.currencies) + countOf(s.costs) + countOf(s.zoneSec)
  return 256 + 60 * #(s.log or {}) + 90 * countOf(s.items) + 40 * small
end

--- The saved store's size: { sessions, bytes } over every character, open sessions included.
function Farm:StorageStats()
  local n, bytes = 0, 0
  for _, mine in pairs(self:LiveStore()) do
    for _, s in ipairs(mine.sessions or {}) do
      n, bytes = n + 1, bytes + Farm.EstimateBytes(s)
    end
    if mine.active then n, bytes = n + 1, bytes + Farm.EstimateBytes(mine.active) end
  end
  return { sessions = n, bytes = bytes }
end

--- The diagnostics line's fields (modules/Diagnostics.lua): never creates an entry.
function Farm:DiagnosticsInfo()
  local s = self:Active()
  local mine = self:Store()[NS.Util.PlayerKey()]
  local stats = self:StorageStats()
  return {
    live = self._live == true, active = s ~= nil,
    state = s and (s.runningSince and "running" or ("paused:" .. tostring(s.pauseReason))) or "-",
    sessions = mine and #(mine.sessions or {}) or 0, chars = countOf(self:Store()),
    log = s and #s.log or 0, bytes = stats.bytes, intent = intentHolds(),
  }
end
