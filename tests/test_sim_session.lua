local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- modules/Sim.lua (LootHistory#37, LibKa0s#54; req-lh-sim.md §5): the simulator's session host on
-- LibKa0s-Sim-1.0. The refusals, in their order; what a start sets up and a stop takes down; the
-- automatic stops; the real-event split (interference stops the simulation and then lands live,
-- everything else is absorbed); test mode and the simulation excluding each other; and every
-- destructive surface refusing while a session runs.
--
-- The scenarios are modules/SimScenario.lua's (a later item); these cases register a test-only def,
-- `lhtest`, whose one step does nothing, and remove it on the way out. This slot runs after
-- tests/test_sim_seam.lua, with the whole addon brought up.

local Sim, Host, R, A = NS.Sim, NS.SimHost, NS.Reconciler, NS.Attribution

local LINK = "|cffa335ee|Hitem:211296::::::::80:::::|h[Vial of Fun]|h|r"

local function printed(fragment)
  for _, line in ipairs(M.__printed()) do
    if line:find(fragment, 1, true) then return true end
  end
  return false
end

local function assertPrinted(fragment, label)
  assertTrue(printed(fragment), (label or "missing line") .. ": " .. fragment .. "\n  printed: "
    .. table.concat(M.__printed(), " | "))
end

-- A clean world to start in: login settled, no ledger in flight, nothing open, solo, out of combat.
local function settle()
  NS.State.cleanupDone, NS.State.loginSettled = true, true
  R:ResetState()
  A:ResetContexts()
  M.__inCombat = false
  M.__context.inGroup, M.__context.inInstance = false, false
end

-- Run body with the test-only scenario registered, and never leave a session running behind it.
local function withScenario(body, extra)
  local sc = Host.SCENARIOS
  local added = {}
  local function add(name, def)
    if sc.defs[name] then return end
    sc.names[#sc.names + 1] = name
    sc.defs[name] = def
    added[#added + 1] = name
  end
  local steps = function() return { { kind = "noop", label = "Noop" } } end
  add("lhtest", { label = "Test", timeline = steps })
  for _, name in ipairs(extra or {}) do add(name, { label = name, timeline = steps }) end
  settle()
  M.__resetPrinted()
  local ok, err = pcall(body)
  Sim:Stop("stop")
  for _, name in ipairs(added) do
    sc.defs[name] = nil
    for i = #sc.names, 1, -1 do if sc.names[i] == name then table.remove(sc.names, i) end end
  end
  settle()
  if not ok then error(err, 0) end
end

local function start(name)
  return Sim:Start({ scenario = name or "lhtest" })
end

test("Sim: NS.Sim is the library's session bound to NS.SimSeam; host fields live on NS.SimHost", function()
  assertTrue(type(Sim) == "table" and type(Sim.Start) == "function", "modules/Sim.lua publishes NS.Sim")
  assertTrue(type(Host.SCENARIOS) == "table" and type(Host.SCENARIOS.names) == "table", "the scenarios table")
  assertFalse(Sim:IsActive(), "no session runs at load")
  assertEqual(Sim.Refusal, nil, "no host member hangs on the library instance (OWNER_SCOPE C.4)")
  assertTrue(type(Host.Refusal) == "function", "the refusal is the host's")
end)

-- ── refusals ────────────────────────────────────────────────────────────────────────────────

test("Sim: each refusal prints its one line, in order, and the start goes ahead once all are clear",
function()
  withScenario(function()
    local saved = { NS.IsStoodDown, NS.BrowserTable.testMode }
    local conditions = {
      { "Not available during a performance capture.",
        function() NS.IsStoodDown = function() return true end end,
        function() NS.IsStoodDown = saved[1] end },
      { "Turn test mode off before starting a simulation.",
        function() NS.BrowserTable.testMode = true end, function() NS.BrowserTable.testMode = saved[2] end },
      { "A simulation cannot start in combat.",
        function() M.__inCombat = true end, function() M.__inCombat = false end },
      { "A simulation cannot start inside an instance.",
        function() M.__context.inInstance = true end, function() M.__context.inInstance = false end },
      { "A simulation cannot start in a group: leave it first.",
        function() M.__context.inGroup = true end, function() M.__context.inGroup = false end },
      { "A simulation cannot start while a merchant, mailbox, bank or auction house window is open.",
        function() NS.State.scopes.merchant = true end, function() NS.State.scopes.merchant = nil end },
      { "A simulation cannot start while the ledger is still settling a change: try again in a few seconds.",
        function() R._holdSince = 1 end, function() R._holdSince = nil end },
      { "A simulation cannot start until login has settled: try again in a few seconds.",
        function() NS.State.loginSettled = false end, function() NS.State.loginSettled = true end },
    }
    local ok, err = pcall(function()
      for _, c in ipairs(conditions) do c[2]() end
      for _, c in ipairs(conditions) do
        M.__resetPrinted()
        local started, line = start()
        assertFalse(started, "refused while: " .. c[1])
        assertEqual(line, c[1])
        assertPrinted(c[1])
        assertEqual(#M.__printed(), 1, "one line per refusal")
        c[3]()
      end
    end)
    for _, c in ipairs(conditions) do c[3]() end
    if not ok then error(err, 0) end
    M.__resetPrinted()
    assertTrue(start(), "every condition clear: the start goes ahead")
    assertTrue(Sim:IsActive())
  end)
end)

test("Sim: the stood-down refusal names the disabled line while the addon is switched off", function()
  withScenario(function()
    local saved = NS.IsStoodDown
    local savedOff = NS.AddonIsOff
    NS.IsStoodDown, NS.AddonIsOff = function() return true end, function() return true end
    local ok, err = pcall(function()
      local started, line = start()
      assertFalse(started)
      assertEqual(line, NS.Slash.DisabledLine())
    end)
    NS.IsStoodDown, NS.AddonIsOff = saved, savedOff
    if not ok then error(err, 0) end
  end)
end)

test("Sim: the ledger scenarios refuse while gains and losses are off; loot and key run either way",
function()
  withScenario(function()
    NS.Schema:Set("settings.trackLedger", false)
    local ok, err = pcall(function()
      for _, name in ipairs({ "vendor", "ah", "bank", "social" }) do
        M.__resetPrinted()
        local started, line = start(name)
        assertFalse(started, name .. " must refuse with the ledger off")
        assertEqual(line, "These steps record through the ledger, so turn on gains and losses first.")
      end
      assertTrue(start("loot"), "loot runs with the ledger off")
      Sim:Stop("stop")
      settle()
      assertTrue(start("key"), "key runs with the ledger off")
    end)
    Sim:Stop("stop")
    NS.Schema:Set("settings.trackLedger", true)
    if not ok then error(err, 0) end
  end, { "vendor", "ah", "bank", "social", "loot", "key" })
end)

-- ── start and stop ──────────────────────────────────────────────────────────────────────────

test("Sim: a start swaps in session stores, seeds the alt, resets the engine and prints its line", function()
  withScenario(function()
    local live = NS.db.global.history
    local liveCount = #live
    NS.State.lootContext = { source = "KILL", expires = math.huge }
    R.claims = { stale = true }
    assertTrue(start())
    assertPrinted("Simulation started (Test): nothing is saved; your history and holdings are not touched.")
    local S = NS.SimStores
    assertTrue(type(S.history) == "table" and S.history ~= live, "a session history store")
    assertTrue(type(S.holdings) == "table" and type(S.daily) == "table", "session holdings and daily stores")
    local realm = NS.Util.PlayerKey():match("%-(.+)$")
    assertTrue(S.holdings["Simalt-" .. realm] ~= nil, "the simulated alt is seeded into the session holdings")
    assertTrue(A:IsOwnAlt("Simalt-" .. realm), "the alt answers as an own alt")
    assertEqual(NS.State.lootContext, nil, "the real loot context was cleared")
    assertEqual(next(R.claims), nil, "the Reconciler's claims were cleared")
    assertTrue(NS.RealEventFilter ~= nil, "the real-event split is in place")
    assertEqual(#S.history, 0, "the session genesis writes no rows")
    assertTrue(S.holdings[NS.Util.PlayerKey()] ~= nil, "the session genesis scanned the player")
    assertEqual(#NS.db.global.history, liveCount, "the saved history is untouched")
    assertTrue(type(Host.world) == "table" and type(Host.counts) == "table", "the host's session fields")
  end)
end)

test("Sim: a stop clears contexts and Reconciler state, cancels R._pending, releases the stores and schedules the drift scan",
function()
  withScenario(function()
    assertTrue(start())
    local fired = false
    R._pending = NS.After(0.35, function() fired = true end)
    local pending = R._pending
    NS.State.lootContext = { source = "KILL", expires = math.huge }
    R.dirty.bags = { [0] = true }
    local afters, savedAfter, savedScan = {}, NS.After, R.LoginScan
    local scans = 0
    NS.After = function(delay, fn) afters[#afters + 1] = { delay = delay, fn = fn }; return savedAfter(delay, fn) end
    local ok, err = pcall(function()
      assertTrue(Sim:Stop("stop"))
      assertFalse(Sim:IsActive())
      assertTrue(pending == nil or pending.canceled == true, "the flush fuse was canceled")
      assertEqual(R._pending, nil)
      assertEqual(NS.State.lootContext, nil, "the simulated loot context was cleared")
      assertEqual(next(R.dirty), nil, "the Reconciler's dirty bits were cleared")
      assertEqual(NS.SimStores.history, nil); assertEqual(NS.SimStores.holdings, nil)
      assertEqual(NS.SimStores.daily, nil)
      assertEqual(NS.RealEventFilter, nil, "the real-event split is gone")
      assertEqual(Host.world, nil, "the host's session fields are cleared")
      local drift
      for _, a in ipairs(afters) do if a.delay == 1 then drift = a end end
      assertTrue(drift ~= nil, "a drift LoginScan is scheduled one second out")
      R.LoginScan = function() scans = scans + 1 end
      drift.fn()
      assertEqual(scans, 1, "the drift deferral runs R:LoginScan")
    end)
    NS.After, R.LoginScan = savedAfter, savedScan
    if not ok then error(err, 0) end
    assertFalse(fired, "a canceled fuse never runs")
  end)
end)

test("Sim: a stop announces the history and each session holder through their one senders", function()
  withScenario(function()
    assertTrue(start())
    local realm = NS.Util.PlayerKey():match("%-(.+)$")
    local sent, bus = {}, NS.bus
    local saved = bus.SendMessage
    bus.SendMessage = function(self, msg, a, ...)
      sent[#sent + 1] = msg .. ":" .. tostring(a)
      return saved(self, msg, a, ...)
    end
    local ok, err = pcall(function() Sim:Stop("stop") end)
    bus.SendMessage = saved
    if not ok then error(err, 0) end
    local seen = table.concat(sent, ",")
    assertTrue(seen:find(NS.MSG.HISTORY_CHANGED, 1, true) ~= nil, "HistoryChanged was sent: " .. seen)
    assertTrue(seen:find(NS.MSG.HOLDINGS_CHANGED .. ":Simalt-" .. realm, 1, true) ~= nil,
      "HoldingsChanged was sent for the session's alt: " .. seen)
  end)
end)

test("Sim: a stand-down stop schedules no drift scan", function()
  withScenario(function()
    assertTrue(start())
    local afters, savedAfter = {}, NS.After
    NS.After = function(delay, fn) afters[#afters + 1] = delay; return savedAfter(delay, fn) end
    local ok, err = pcall(function() assertTrue(Sim:Stop("standDown")) end)
    NS.After = savedAfter
    if not ok then error(err, 0) end
    for _, d in ipairs(afters) do assertTrue(d ~= 1, "no drift LoginScan on a stand-down") end
  end)
end)

-- ── automatic stops ─────────────────────────────────────────────────────────────────────────

local function stopsOn(label, line, provoke, restore)
  withScenario(function()
    assertTrue(start())
    M.__resetPrinted()
    local ok, err = pcall(provoke)
    if restore then restore() end
    if not ok then error(err, 0) end
    assertFalse(Sim:IsActive(), label .. " must stop the simulation")
    assertPrinted(line, label)
  end)
end

test("Sim: joining a real group stops it", function()
  stopsOn("group", "Simulation stopped: you joined a group.", function()
    M.__context.inGroup = true
    M.__fire("GROUP_ROSTER_UPDATE")
  end, function() M.__context.inGroup = false end)
end)

test("Sim: entering an instance stops it (zone change and entering the world)", function()
  for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
    stopsOn(event, "Simulation stopped: you entered an instance.", function()
      M.__context.inInstance = true
      M.__fire(event)
    end, function() M.__context.inInstance = false end)
  end
end)

test("Sim: a roster update or zone change that changes nothing real leaves it running", function()
  withScenario(function()
    assertTrue(start())
    M.__fire("GROUP_ROSTER_UPDATE")
    M.__fire("ZONE_CHANGED_NEW_AREA")
    assertTrue(Sim:IsActive(), "still solo and outside an instance")
  end)
end)

test("Sim: entering combat stops it", function()
  stopsOn("combat", "Simulation stopped: you entered combat.", function() M.__fire("PLAYER_REGEN_DISABLED") end)
end)

test("Sim: a real loot line stops it, then lands in the saved history", function()
  local settings = NS.db.profile.settings
  local savedThreshold = settings.qualityThreshold
  settings.qualityThreshold = 0
  NS.Collector:RefreshUpvalues()
  local before = #NS.db.global.history
  local ok, err = pcall(stopsOn, "a real loot line",
    "Simulation stopped: something real happened (a loot, a trade, a mail or a window), and it is recorded as usual.",
    function() M.__fire("CHAT_MSG_LOOT", string.format(M.LOOT_ITEM_SELF, LINK)) end)
  local after = #NS.db.global.history
  if after > before then table.remove(NS.db.global.history) end
  settings.qualityThreshold = savedThreshold
  NS.Collector:RefreshUpvalues()
  if not ok then error(err, 0) end
  assertEqual(after, before + 1, "the real loot was recorded live, into the saved history")
end)

test("Sim: another player's loot line is absorbed, and so are bag and money events", function()
  withScenario(function()
    assertTrue(start())
    local function keys(t)
      local out = {}
      for k in pairs(t) do out[#out + 1] = tostring(k) end
      table.sort(out)
      return table.concat(out, ",")
    end
    local dirty = keys(R.dirty)
    M.__fire("CHAT_MSG_LOOT", "Someone receives loot: " .. LINK .. ".")
    M.__fire("BAG_UPDATE", 0)
    M.__fire("PLAYER_MONEY")
    assertTrue(Sim:IsActive(), "absorbed events never stop the simulation")
    assertEqual(keys(R.dirty), dirty, "an absorbed BAG_UPDATE or PLAYER_MONEY marks nothing dirty")
    assertEqual(#NS.SimStores.history, 0, "nothing was recorded")
  end)
end)

test("Sim: a real hook call stops it, then runs live", function()
  local row
  for _, r in ipairs(NS.HOOK_ROWS) do if r.name == "BuybackItem" then row = r end end
  assertTrue(row ~= nil, "the BuybackItem hook row exists")
  local ran, savedFn = 0, row.fn
  row.fn = function() ran = ran + 1 end
  local ok, err = pcall(stopsOn, "a real hook",
    "Simulation stopped: something real happened (a loot, a trade, a mail or a window), and it is recorded as usual.",
    function() NS.DeliverHook(row, 1) end)
  row.fn = savedFn
  if not ok then error(err, 0) end
  assertEqual(ran, 1, "the real hook reached its row after the stop")
end)

test("Sim: the stand-down stops it first", function()
  stopsOn("stand-down", "Simulation stopped: the addon stood down (disabled, or a performance capture).",
    function() NS.Schema:Set("settings.enabled", false) end,
    function() NS.Schema:Set("settings.enabled", true) end)
end)

test("Sim: a profile event stops it", function()
  stopsOn("profile", "Simulation stopped: the profile changed.",
    function() NS.OnProfileEvent("OnProfileChanged", NS.db:GetCurrentProfile()) end)
end)

-- ── exclusivity and the destructive surfaces ────────────────────────────────────────────────

test("Sim: test mode and the simulation exclude each other", function()
  withScenario(function()
    assertTrue(start())
    M.__resetPrinted()
    local switched = NS.BrowserTable:SetTestMode(true)
    local on = NS.BrowserTable.testMode == true
    if on then NS.BrowserTable:SetTestMode(false) end
    assertFalse(switched, "test mode refuses while a simulation runs")
    assertFalse(on)
    assertPrinted("a simulation is running (/lh sim stop ends it).")
  end)
end)

local function refusesWhileActive(line, act)
  withScenario(function()
    assertTrue(start())
    M.__resetPrinted()
    act()
    assertPrinted(line)
  end)
end

-- Each surface is driven ON ITS OWN, with StaticPopup_Show counted: the purge confirm's OnAccept
-- prints the same line as the slash verb and the button, so a case that reaches both would stay
-- green with either guard gone. The refusal must print its line exactly once and raise nothing.
local function refusesAlone(line, act)
  local shown, savedShow = {}, M.StaticPopup_Show
  M.StaticPopup_Show = function(which) shown[#shown + 1] = which end
  local ok, err = pcall(refusesWhileActive, line, function()
    act()
    local n = 0
    for _, l in ipairs(M.__printed()) do if l:find(line, 1, true) then n = n + 1 end end
    assertEqual(n, 1, "the refusal line is printed exactly once")
  end)
  M.StaticPopup_Show = savedShow
  if not ok then error(err, 0) end
  assertEqual(#shown, 0, "no confirm is raised: " .. table.concat(shown, ", "))
end

local PURGE_LINE = "Purge is not available while a simulation runs."

test("Sim: /lh purge refuses while a simulation runs and raises no confirm", function()
  local before = #NS.db.global.history
  refusesAlone(PURGE_LINE, function() NS.Slash:OnSlash("purge") end)
  assertEqual(#NS.db.global.history, before, "nothing was purged")
end)

test("Sim: the settings panel's Purge history button refuses while a simulation runs", function()
  local PS = dofile("tests/panel_support.lua")
  local ctx = NS.Panel.general
  local created = PS.clickTab(M.__subcategories["General"], ctx, PS.tabAt("History"))
  local btn = PS.findByLabel(created, "Purge history\226\128\166")
  assertTrue(btn ~= nil, "the History tab draws the Purge history button")
  local before = #NS.db.global.history
  refusesAlone(PURGE_LINE, function() btn:__fire("OnClick") end)
  PS.homeTab(ctx)
  assertEqual(#NS.db.global.history, before, "nothing was purged")
end)

test("Sim: the purge confirm raised before the session refuses on accept", function()
  local before = #NS.db.global.history
  refusesAlone(PURGE_LINE, function() M.StaticPopupDialogs.KA0S_LOOTHISTORY_PURGE.OnAccept() end)
  assertEqual(#NS.db.global.history, before, "nothing was purged")
end)

local LEDGER_LINE = "The ledger reset is not available while a simulation runs."

test("Sim: the ledger reset offer refuses while a simulation runs and raises no popup", function()
  local g = NS.db.global
  local savedH, savedPending, savedPrompt = g.history, g.resetPromptPending, g.resetPrompt
  g.history, g.resetPrompt, g.resetPromptPending = { {} }, nil, true
  assertTrue(NS.ShouldOfferLedgerReset(g), "the offer is due, so only the simulation holds it back")
  local ok, err = pcall(refusesAlone, LEDGER_LINE, function() NS.OfferLedgerReset() end)
  local prompt, pending = g.resetPrompt, g.resetPromptPending
  g.history, g.resetPromptPending, g.resetPrompt = savedH, savedPending, savedPrompt
  if not ok then error(err, 0) end
  assertEqual(prompt, nil, "no choice was stored")
  assertEqual(pending, true, "the offer stays pending for a later login")
end)

test("Sim: the ledger reset popup and its confirm refuse on accept while a simulation runs", function()
  local g = NS.db.global
  local before, savedPrompt = #g.history, g.resetPrompt
  refusesAlone(LEDGER_LINE, function()
    M.StaticPopupDialogs.KA0S_LOOTHISTORY_LEDGER_RESET.OnAccept()
  end)
  refusesAlone(LEDGER_LINE, function()
    M.StaticPopupDialogs.KA0S_LOOTHISTORY_LEDGER_RESET_CONFIRM.OnAccept()
  end)
  assertEqual(#g.history, before, "nothing was reset")
  assertEqual(g.resetPrompt, savedPrompt, "no choice was stored")
end)

test("Sim: Forget this character refuses while a simulation runs", function()
  refusesWhileActive("Forget this character is not available while a simulation runs.", function()
    local ok, why = NS.Reconciler:ForgetHolder("Somebody-Elsewhere")
    assertFalse(ok); assertEqual(why, "simulation")
  end)
end)

test("Sim: the History row's Delete refuses while a simulation runs", function()
  refusesWhileActive("Delete is not available while a simulation runs.", function()
    local record = { ts = 1, itemID = 7, quantity = 1 }
    table.insert(NS.SimStores.history, record)
    for _, it in ipairs(NS.BrowserTable:RowMenuItems(record)) do
      if it.label:find("Delete", 1, true) then it.fn() end
    end
    assertEqual(#NS.SimStores.history, 1, "the row was not deleted")
  end)
end)

test("Sim: a retention change that would prune refuses and keeps the confirmed value", function()
  local g = NS.db.global
  local savedHistory, savedDays = g.history, g.retentionDays
  g.history = { { ts = os.time() - 40 * 86400, itemID = 1 } }
  g.retentionDays = 30
  NS.Schema:SyncRetention()
  local ok, err = pcall(refusesWhileActive, "Shortening 'Keep history for' is not available while a simulation runs.",
    function()
      NS.Schema:Set("settings.retentionDays", 7)
      assertEqual(g.retentionDays, 30, "the confirmed retention was written back")
      M.StaticPopupDialogs.KA0S_LOOTHISTORY_PRUNE.OnAccept(nil, { days = 7 })
      assertEqual(#g.history, 1, "nothing was pruned")
      assertEqual(g.retentionDays, 30)
    end)
  g.history, g.retentionDays = savedHistory, savedDays
  NS.Schema:SyncRetention()
  if not ok then error(err, 0) end
end)
