-- tests/test_farm.lua — modules/Farm.lua, farm mode's runtime (#39, farm spec
-- docs/superpowers/specs/2026-11-27-39-farm-mode-design.md §5, §11, §13): store routing and
-- Reconcile (no session, no registration), the GAIN receiver through the feed's real senders, the
-- pauses, the cost hook, the logout intent, suspend and restore, the activity notifications, the
-- zone, death and AFK rows, the price pass, the F6 discard, the saved-sessions cap and the verbs.
--
-- After tests/test_dispatch.lua, with the whole addon brought up (tests/test_disabled.lua). Every case
-- runs on a scratch db.global.farm (and, where it writes rows, a scratch history and daily store),
-- with time() on a test clock, and leaves no session open and nothing registered.

local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local F, FM = NS.Farm, NS.FarmModel
local T0 = 1795000000
local clock = { t = T0 }
local NIL = {}

--- rawset `fields` on `t` for the call (NIL removes one), then put each back.
local function with(t, fields, fn)
  local saved = {}
  for k, v in pairs(fields) do
    saved[k] = { v = rawget(t, k) }
    if v == NIL then rawset(t, k, nil) else rawset(t, k, v) end
  end
  local ok, err = pcall(fn)
  for k, s in pairs(saved) do rawset(t, k, s.v) end
  if not ok then error(err, 0) end
end

--- Chat lines written during `fn`, the prefix stripped.
local function chat(fn)
  local cf = M.DEFAULT_CHAT_FRAME
  local old, out = cf.AddMessage, {}
  cf.AddMessage = function(_, line)
    out[#out + 1] = tostring(line):gsub("^" .. NS.PREFIX:gsub("%p", "%%%0") .. " ", "")
  end
  local ok, err = pcall(fn)
  cf.AddMessage = old
  if not ok then error(err, 0) end
  return out
end

--- Run `body(g)` on a scratch farm, history and daily store with time() at T0, then close whatever
--- is open and put every store, the clock and the session flags back.
local function world(body)
  local g = NS.db.global
  local saved = { g.farm, g.history, g.daily, g.farmKeep, NS.State.farmLogoutIntent, F._containerAt }
  g.farm, g.history, g.daily = {}, {}, {}
  clock.t = T0
  local ok, err
  with(M, { time = function() return clock.t end }, function()
    chat(function()
      ok, err = pcall(body, g)
      NS.SimStores.farm, NS.State.testFarm = nil, nil
      if F:Active() then F:Finish("manual", clock.t) end
      F:Reconcile()
      NS.FarmPanel:Hide()
    end)
  end)
  NS.GainFeed:ResetState()
  g.farm, g.history, g.daily, g.farmKeep, NS.State.farmLogoutIntent, F._containerAt =
    saved[1], saved[2], saved[3], saved[4], saved[5], saved[6]
  if not ok then error(err, 0) end
end

local function me() return NS.Util.PlayerKey() end

--- Every Farm row that says it registered, sorted.
local function farmRows()
  local out = {}
  for _, row in ipairs(NS.EVENT_ROWS) do
    if row.owner == "Farm" and row.registered then out[#out + 1] = row.event end
  end
  table.sort(out)
  return table.concat(out, ",")
end

-- ── the feed's real senders (§2's fields) ────────────────────────────────────────────────────

local GF = function() return NS.GainFeed end

local function sendItem(id, qty, source, record, origin)
  local g = GF():Begin("ITEM")
  g.id, g.link, g.qty, g.quality, g.source = id, "|cff1eff00|Hitem:" .. id .. "::::|h[Thing " .. id .. "]|h|r",
    qty, 2, source
  g.record = record
  if origin == "event" then GF():SendEvent(g) else GF():SendChat(g) end
end

local function sendGold(copper, source)
  local g = GF():Begin("GOLD")
  g.qty, g.name, g.source = copper, "Gold", source
  GF():SendChat(g)
end

local function sendRep(factionID, qty, dir)
  local g = GF():Begin("REPUTATION")
  g.id, g.qty, g.dir, g.name, g.source = factionID, qty, dir or "IN", "Council of Dornogal", "KILL"
  GF():SendEvent(g)
end

-- ── store routing and Reconcile (§5.1) ──────────────────────────────────────────────────────

test("Farm: with no session nothing is registered; Start registers all of it, Finish takes it all down", function()
  -- red under: a Reconcile that registers at Enable whatever the store holds, or a Finish that leaves
  -- the write hook, the ticker or the farm set behind.
  world(function()
    assertEqual(F._live, nil, "no session: not live")
    assertEqual(farmRows(), "", "no session: no farm row registered")
    assertEqual(NS.GainFeed._farm, nil, "no session: the gain feed holds no farm set")
    assertEqual(F._tick, nil, "no session: no idle ticker")
    local s = F:Start()
    assertTrue(s ~= nil and F:Active() == s, "Start opened a session in the store")
    assertTrue(NS.db.global.farm[me()].active == s, "in this character's entry")
    assertEqual(farmRows(), "PLAYER_DEAD,PLAYER_FLAGS_CHANGED,ZONE_CHANGED_NEW_AREA")
    assertTrue(F._live == true and F._hook ~= nil, "live, with the write hook")
    assertTrue(NS.GainFeed._farm == NS.Constants.FARM.GAIN_KINDS, "SetFarm(C.FARM.GAIN_KINDS)")
    assertTrue(F._tick ~= nil, "the idle ticker is armed")
    F:FinishVerb()
    assertEqual(F._live, nil)
    assertEqual(farmRows(), "")
    assertEqual(F._hook, nil)
    assertEqual(NS.GainFeed._farm, nil, "SetFarm(nil) at the finish")
    assertEqual(F._tick, nil)
  end)
end)

test("Farm: Start while a session is open refuses on one line", function()
  world(function()
    F:Start()
    local out = chat(function() F:Start() end)
    assertEqual(table.concat(out, " | "), "a farm session is already running.")
    assertEqual(NS.db.global.farm[me()].nextId, 2, "the refusal took no id")
  end)
end)

test("Farm: Active reads without creating an entry; Store and ActiveStore follow the sim and test stores", function()
  world(function(g)
    assertEqual(F:Active(), nil)
    assertEqual(next(g.farm), nil, "a read created nothing")
    local sim, sample = {}, {}
    NS.SimStores.farm = sim
    assertTrue(F:Store() == sim, "Store is the session store during a sim")
    NS.State.testFarm = sample
    assertTrue(F:ActiveStore() == sample, "ActiveStore is the test sample while on")
    assertTrue(F:Store() == sim, "and Store never is")
    NS.State.testFarm, NS.SimStores.farm = nil, nil
    assertTrue(F:Store() == g.farm and F:LiveStore() == g.farm)
  end)
end)

-- ── gains (§5.5) ─────────────────────────────────────────────────────────────────────────────

test("Farm: gains tally through the feed's real senders, with a row's own prices", function()
  -- red under: a receiver on the shared bus target (the toasts' own would be replaced), or one that
  -- keeps the scratch table.
  world(function()
    local s = F:Start()
    clock.t = T0 + 10
    sendItem(210930, 5, "GATHERING", { vendorPrice = 176, auctionPrice = nil })
    sendGold(12345, "KILL")
    sendRep(2590, 50)
    sendRep(2590, 20, "OUT")
    assertEqual(s.items[210930].qty, 5)
    assertEqual(s.items[210930].vu, 176, "the row's vendor price")
    assertEqual(s.money.KILL, 12345, "a GOLD gain (id nil) keyed by its source")
    assertEqual(s.activity.rep[2590].delta, 30, "a REPUTATION OUT subtracts")
    assertEqual(s.lastGainAt, T0 + 10)
    assertEqual(F:Totals(s).money, 12345)
    assertEqual(F:Totals(s).vendor, 5 * 176, "the totals cache was dirtied")
  end)
end)

test("Farm: a diff OTHER gain is skipped and a chat OTHER gain counted (F4)", function()
  world(function()
    local s = F:Start()
    GF():FromDiff("i:2589", 3, "OTHER", GetTime and GetTime() or 0, "|cffffffff|Hitem:2589::::|h[Linen]|h|r")
    assertEqual(s.items[2589], nil, "the holdings diff's OTHER is not farm income")
    sendItem(2589, 2, "OTHER")
    assertEqual(s.items[2589].qty, 2, "a chat line's OTHER counts")
    sendItem(2590, 1, "VENDOR")
    assertEqual(s.items[2590], nil, "a vendor buy never counts")
  end)
end)

test("Farm: a manual pause drops gains and keeps costs; an idle pause resumes on the next gain", function()
  world(function()
    local s = F:Start()
    F:PauseVerb()
    assertEqual(s.pauseReason, "manual")
    sendGold(100, "KILL")
    assertEqual(s.money.KILL, nil, "a manual pause drops the gain (F2)")
    NS.Database:Add({ ts = clock.t, dir = "OUT", kind = "GOLD", holder = me(), quantity = 900, source = "REPAIR" })
    assertEqual(s.costs.REPAIR, 900, "but the cost counts")
    F:ResumeVerb()
    clock.t = T0 + 400
    F:IdleTick(clock.t)
    assertEqual(s.pauseReason, "idle", "5 idle minutes paused it")
    clock.t = T0 + 900
    sendGold(100, "KILL")
    assertEqual(s.money.KILL, 100, "the gain on an idle pause is tallied")
    assertTrue(s.runningSince == T0 + 900 and s.pauseReason == nil, "and resumes the clock")
  end)
end)

test("Farm: the idle ticker re-arms itself and stamps lastSeen", function()
  world(function()
    local s = F:Start()
    local h = F._tick
    assertTrue(h ~= nil and h.timer ~= nil, "a cancelable NS.After handle")
    clock.t = T0 + 30
    h.timer.fn()
    h.timer.Cancel()   -- fired by hand: out of the kit's live set, as a run timer is
    assertEqual(s.lastSeen, T0 + 30)
    assertTrue(F._tick ~= nil and F._tick ~= h, "the chain re-armed")
  end)
end)

-- ── costs (§5.6) ─────────────────────────────────────────────────────────────────────────────

test("Farm: an OUT GOLD REPAIR row and its amend add each delta once; other holders and reasons do not", function()
  world(function()
    local s = F:Start()
    local i = NS.Database:Add({ ts = clock.t, dir = "OUT", kind = "GOLD", holder = me(), quantity = 500, source = "REPAIR" })
    NS.Database:Amend(i, 250)
    assertEqual(s.costs.REPAIR, 750, "the add and the amend, by delta")
    NS.Database:Add({ ts = clock.t, dir = "OUT", kind = "GOLD", holder = "Other-Realm", quantity = 99, source = "REPAIR" })
    NS.Database:Add({ ts = clock.t, dir = "OUT", kind = "GOLD", holder = me(), quantity = 99, source = "WARBAND_DEPOSIT" })
    NS.Database:Add({ ts = clock.t, dir = "OUT", kind = "GOLD", holder = me(), quantity = 99, source = "AH_BUY" })
    NS.Database:Add({ ts = clock.t, dir = "IN", kind = "GOLD", holder = me(), quantity = 99, source = "REPAIR" })
    assertEqual(s.costs.REPAIR, 750)
    assertEqual(s.costs.WARBAND_DEPOSIT, nil)
    assertEqual(s.costs.AH_BUY, nil)
    NS.Database:Add({ ts = clock.t, dir = "OUT", kind = "CURRENCY", currencyID = 3008, holder = me(), quantity = 40,
      source = "BUY" })
    assertEqual(s.costCurrencies[3008], 40, "currency spent under BUY")
  end)
end)

-- ── logout, suspend and restore (§5.4) ──────────────────────────────────────────────────────

test("Farm: a logout intent then PLAYER_LOGOUT finishes the session as logout", function()
  world(function(g)
    local s = F:Start()
    sendGold(100, "KILL")
    F:OnLogoutIntent()
    clock.t = T0 + 600
    assertTrue(M.__fire("PLAYER_LOGOUT") > 0, "PLAYER_LOGOUT is registered while a session is open")
    assertEqual(g.farm[me()].active, nil)
    assertTrue(g.farm[me()].sessions[1] == s and s.endReason == "logout", "saved as logout")
  end)
end)

test("Farm: no intent suspends at PLAYER_LOGOUT; the restore resumes with the reload seconds off the clock", function()
  world(function(g)
    local s = F:Start()
    sendGold(100, "KILL")
    clock.t = T0 + 600
    M.__fire("PLAYER_LOGOUT")
    assertTrue(g.farm[me()].active == s, "still open")
    assertTrue(s.resumeOnLoad and s.wasRunning, "suspended, running before")
    assertEqual(s.activeSec, 600, "banked at the logout")
    clock.t = T0 + 660
    assertEqual(F:Restore(clock.t), 1, "rule 1")
    assertEqual(s.resumeOnLoad, nil)
    assertEqual(s.runningSince, T0 + 660, "running again from the load")
    assertEqual(FM.Elapsed(s, T0 + 700), 640, "the 60 s of the reload stayed off")
  end)
end)

test("Farm: an intent older than 30 s suspends; CancelLogout and LOGOUT_CANCEL clear the intent", function()
  world(function(g)
    local s = F:Start()
    sendGold(100, "KILL")
    local now = M.__now
    F:OnLogoutIntent()
    M.__now = now + 31
    M.__fire("PLAYER_LOGOUT")
    assertTrue(g.farm[me()].active == s and s.resumeOnLoad, "an expired intent is a suspend")
    s.resumeOnLoad, s.wasRunning = nil, nil
    FM.Resume(s, clock.t)
    F:OnLogoutIntent()
    F:OnLogoutCancel()
    assertEqual(NS.State.farmLogoutIntent, nil, "the cancel hook clears it")
    M.__fire("PLAYER_CAMPING")
    assertTrue(NS.State.farmLogoutIntent ~= nil, "PLAYER_CAMPING stamps it")
    M.__fire("LOGOUT_CANCEL")
    assertEqual(NS.State.farmLogoutIntent, nil, "LOGOUT_CANCEL clears it")
    M.__now = now
  end)
end)

test("Farm: Enable installs the logout family once and its bodies drive the intent", function()
  local hooked = {}
  local function hook(a, b, fn)
    if type(a) == "table" then hooked[b] = fn else hooked[a] = b end
  end
  local function f() end
  local savedHooked = F._hooked
  F._hooked = nil
  local ok, err = pcall(function()
    with(_G, { Logout = f, Quit = f, ForceQuit = f, CancelLogout = f, ReloadUI = f }, function()
      with(M, { hooksecurefunc = hook, C_UI = { Reload = f } }, function()
        F:Enable()
        F:Enable()
      end)
    end)
    local n = 0
    for _ in pairs(hooked) do n = n + 1 end
    assertEqual(n, 6, "six hooks, installed once")
    hooked.Logout()
    assertTrue(NS.State.farmLogoutIntent ~= nil, "Logout stamps the intent")
    hooked.Reload()
    assertEqual(NS.State.farmLogoutIntent, nil, "C_UI.Reload clears it: a reload keeps the session")
    hooked.ForceQuit()
    NS.Schema:Set("settings.enabled", false)
    hooked.ReloadUI()
    assertTrue(NS.State.farmLogoutIntent ~= nil, "a hook body is a no-op while stood down")
    NS.Schema:Set("settings.enabled", true)
  end)
  NS.Schema:Set("settings.enabled", true)
  NS.State.farmLogoutIntent = nil
  F._hooked = savedHooked or true
  if not ok then error(err, 0) end
end)

test("Farm: a crash restores within the stale window and is finished as stale beyond it", function()
  world(function(g)
    local s = F:Start()
    sendGold(100, "KILL")
    s.lastSeen = T0 + 300
    clock.t = T0 + 900
    assertEqual(F:Restore(clock.t), 2, "rule 2: running with no clean logout")
    assertEqual(s.activeSec, 300, "banked to lastSeen")
    assertEqual(s.runningSince, T0 + 900)
    s.lastSeen = T0 + 900
    clock.t = T0 + 900 + 1801
    local out = chat(function() F:Restore(clock.t) end)
    assertEqual(g.farm[me()].active, nil, "past STALE_SEC it is finished")
    assertEqual(s.endReason, "stale")
    assertEqual(s.endedAt, T0 + 900, "at lastSeen")
    assertTrue(out[1]:find("was left open; it has been finished and saved.", 1, true) ~= nil, out[1])
  end)
end)

test("Farm: a paused session left stale is finished; a standDown pause within the window resumes", function()
  world(function(g)
    local s = F:Start()
    sendGold(100, "KILL")
    FM.Pause(s, "standDown", T0 + 60)
    s.lastSeen = T0 + 60
    assertEqual(F:Restore(T0 + 120), 3, "rule 3")
    assertTrue(s.pauseReason == nil and s.runningSince == T0 + 120, "the standDown pause resumed")
    FM.Pause(s, "manual", T0 + 200)
    s.lastSeen = T0 + 200
    F:Restore(T0 + 300)
    assertEqual(s.pauseReason, "manual", "a manual pause stays paused")
    chat(function() F:Restore(T0 + 200 + 1801) end)
    assertEqual(g.farm[me()].active, nil, "and past STALE_SEC it is finished")
    assertEqual(s.endReason, "stale")
  end)
end)

test("Farm: sessions are per character: another character's open session is neither read nor restored", function()
  world(function(g)
    local other = FM.New(T0 - 99999, 1, "Other-Realm", "MAGE", "Hallowfall")
    g.farm["Other-Realm"] = { sessions = {}, nextId = 2, active = other }
    assertEqual(F:Active(), nil, "this character has none")
    assertEqual(F:Restore(T0), nil, "and nothing to restore")
    assertTrue(g.farm["Other-Realm"].active == other, "the other character's session survives, untouched")
    local s = F:Start()
    assertTrue(F:Active() == s and s.id == 1, "this character's own entry and ids")
    g.farm["Other-Realm"] = nil
  end)
end)

test("Farm: during a simulation PLAYER_LOGOUT never writes the live session", function()
  world(function(g)
    local s = F:Start()
    sendGold(100, "KILL")
    local before = FM.Elapsed(s, T0)
    NS.SimStores.farm = {}
    F:OnStoreSwapped()
    assertEqual(F._live, nil, "the live session goes quiet during a sim")
    clock.t = T0 + 600
    F:OnLogout()
    assertEqual(s.resumeOnLoad, nil, "no suspend written")
    assertTrue(s.runningSince == T0 and s.activeSec == before, "the live clock untouched")
    NS.SimStores.farm = nil
    F:OnStoreSwapped()
    assertTrue(F._live == true and g.farm[me()].active == s, "the stop brings it back up")
  end)
end)

-- ── activity (§5.7, §5.8) ────────────────────────────────────────────────────────────────────

local function lootSources(bySlot)
  return function(slot)
    local list = bySlot[slot]
    if not list then return nil end
    local out = {}
    for _, guid in ipairs(list) do out[#out + 1] = guid; out[#out + 1] = 1 end
    return unpack(out)
  end
end

local function corpse(n) return "Creature-0-1-2-3-" .. (1000 + n) .. "-" .. string.format("%010X", n) end

test("Farm: a KILL window counts each corpse once, AoE included; a skinning window adds nothing", function()
  world(function()
    local s = F:Start()
    with(M, { GetLootSourceInfo = lootSources({ { corpse(1), corpse(2), corpse(3) }, { corpse(1) } }) }, function()
      F:OnLootWindow("KILL", 2)
      assertEqual(s.activity.mobs, 3, "an AoE slot with three GUIDs is three corpses")
      F:OnLootWindow("KILL", 2)
      assertEqual(s.activity.mobs, 3, "the same corpses again (skinning) add 0 (F11)")
    end)
    with(M, { GetLootSourceInfo = lootSources({ { "GameObject-0-1-2-3-99-0000000001" } }) }, function()
      F:OnLootWindow("KILL", 1)
      assertEqual(s.activity.mobs, 3, "a GameObject GUID is no corpse")
    end)
  end)
end)

test("Farm: the corpse ring evicts the oldest at 257", function()
  world(function()
    local s = F:Start()
    for n = 1, 257 do
      with(M, { GetLootSourceInfo = lootSources({ { corpse(n) } }) }, function() F:OnLootWindow("KILL", 1) end)
    end
    assertEqual(s.activity.mobs, 257)
    with(M, { GetLootSourceInfo = lootSources({ { corpse(1) } }) }, function() F:OnLootWindow("KILL", 1) end)
    assertEqual(s.activity.mobs, 258, "corpse 1 was evicted, so it counts again")
    with(M, { GetLootSourceInfo = lootSources({ { corpse(257) } }) }, function() F:OnLootWindow("KILL", 1) end)
    assertEqual(s.activity.mobs, 258, "a recent one is still remembered")
  end)
end)

test("Farm: fishing, gathering, chest and item windows count; the hook stamp and its window count once", function()
  world(function()
    local s = F:Start()
    F:OnLootWindow("FISHING", 1)
    F:OnLootWindow("GATHERING", 1)
    F:OnLootWindow("GATHERING", 1)
    with(M, { GetLootSourceInfo = lootSources({ { "GameObject-0-1-2-3-99-0000000001" } }) }, function()
      F:OnLootWindow("CONTAINER", 1)
    end)
    assertEqual(s.activity.fish, 1)
    assertEqual(s.activity.nodes, 2, "each tap of a node is a window")
    assertEqual(s.activity.containers, 1, "a GameObject chest is a container")
    F:OnContainerOpened()
    with(M, { GetLootSourceInfo = lootSources({ { "Item-0-0-0-0-0-0000000001" } }) }, function()
      F:OnLootWindow("CONTAINER", 1)
      assertEqual(s.activity.containers, 2, "the bag item's window belongs to the hook's count")
      F:OnLootWindow("CONTAINER", 1)
      assertEqual(s.activity.containers, 3, "a second Item window is a second container")
    end)
    F:OnLootWindow("VENDOR", 1)
    assertEqual(s.activity.containers + s.activity.fish + s.activity.nodes, 6, "other sources count nothing")
    assertEqual(s.lastGainAt, nil, "activity stamps lastSeen, never lastGainAt")
  end)
end)

test("Farm: Attribution's notifications reach the session only while it is live", function()
  world(function()
    local calls = 0
    local real = F.OnLootWindow
    F.OnLootWindow = function(self, ...) calls = calls + 1; return real(self, ...) end
    local ok, err = pcall(function()
      NS.Attribution:OnLootOpened()
      assertEqual(calls, 0, "no session: Attribution does not call in")
      F:Start()
      with(M, { GetNumLootItems = function() return 1 end,
                GetLootSourceInfo = lootSources({ { corpse(7) } }) }, function()
        NS.Attribution:OnLootOpened()
      end)
      assertEqual(calls, 1, "a live session hears the classified window")
      assertEqual(F:Active().activity.mobs, 1)
    end)
    F.OnLootWindow = real
    NS.Attribution:ResetContexts()
    if not ok then error(err, 0) end
  end)
end)

test("Farm: a quest turned in counts and logs its title, or `Quest <id>` without one", function()
  world(function()
    local s = F:Start()
    with(M, { C_QuestLog = { GetTitleForQuestID = function(id) return id == 7 and "Supplies Needed" or nil end } },
      function()
        F:OnQuestTurnedIn(7)
        F:OnQuestTurnedIn(8)
      end)
    assertEqual(s.activity.quests, 2)
    local _, _, id, title = FM.Unpack(s.log[#s.log - 1])
    assertEqual(id, 7); assertEqual(title, "Supplies Needed")
    local _, _, _, title2 = FM.Unpack(s.log[#s.log])
    assertEqual(title2, "Quest 8")
  end)
end)

test("Farm: the zone and death rows bank zones and count deaths; manual pauses still count deaths", function()
  world(function()
    local s = F:Start()
    clock.t = T0 + 100
    with(M, { GetZoneText = function() return "Ringing Deeps" end }, function()
      assertTrue(NS.DeliverAll("ZONE_CHANGED_NEW_AREA") > 0, "Farm's zone row is registered")
    end)
    assertEqual(s.zone, "Ringing Deeps")
    assertEqual(s.zoneSec[s.zoneOrder[1]], 100, "the old zone banked")
    F:PauseVerb()
    NS.DeliverAll("PLAYER_DEAD")
    assertEqual(s.activity.deaths, 1, "a death is not a gain")
  end)
end)

test("Farm: AFK is a unit row on player; it pauses and resumes, a nil answer and pauseOnAFK off do nothing", function()
  world(function()
    local s = F:Start()
    local afk
    with(M, { UnitIsAFK = function() return afk end }, function()
      afk = true
      clock.t = T0 + 42
      NS.DeliverAll("PLAYER_FLAGS_CHANGED", "player")
      assertEqual(s.pauseReason, "afk")
      assertEqual(s.activeSec, 42, "banked at the moment AFK set (F3)")
      afk = nil
      NS.DeliverAll("PLAYER_FLAGS_CHANGED", "player")
      assertEqual(s.pauseReason, "afk", "an unknown answer changes nothing")
      afk = false
      clock.t = T0 + 100
      NS.DeliverAll("PLAYER_FLAGS_CHANGED", "player")
      assertTrue(s.pauseReason == nil and s.runningSince == T0 + 100, "clearing AFK resumes")
      NS.db.profile.settings.farm.pauseOnAFK = false
      afk = true
      NS.DeliverAll("PLAYER_FLAGS_CHANGED", "player")
      NS.db.profile.settings.farm.pauseOnAFK = true
      assertTrue(s.runningSince ~= nil, "pauseOnAFK off ignores AFK")
    end)
  end)
end)

-- ── the price pass (§5.5, F7) ────────────────────────────────────────────────────────────────

test("Farm: an unpriced item waits for the deferred pass, which re-arms in combat; Finish fills the rest", function()
  world(function()
    local s = F:Start()
    local info = M.C_Item.GetItemInfo
    local ok, err = pcall(function()
      M.C_Item.GetItemInfo = function(link)
        return "Thing", link, 2, 1, nil, "Tradegoods", "Herb", nil, nil, nil, 33
      end
      sendItem(4001, 2, "GATHERING")
      assertEqual(s.items[4001].vu, nil, "no row: no price yet")
      local h = F._price
      assertTrue(h ~= nil and h.timer ~= nil, "the pass is deferred")
      with(M, { UnitAffectingCombat = function() return true end }, function() h.timer.fn() end)
      h.timer.Cancel()
      assertEqual(s.items[4001].vu, nil, "never priced in combat")
      assertTrue(F._price ~= nil and F._price ~= h, "the pass re-armed")
      local h2 = F._price
      h2.timer.fn()
      h2.timer.Cancel()
      assertEqual(s.items[4001].vu, 33, "priced out of combat")
      sendItem(4002, 1, "GATHERING")
      F:FinishVerb()
      assertEqual(s.items[4002].vu, 33, "the finish fills what is still queued")
      assertEqual(s.totals.vendor, 3 * 33, "before the totals snapshot")
    end)
    M.C_Item.GetItemInfo = info
    if not ok then error(err, 0) end
  end)
end)

-- ── finishing, the cap and the verbs ─────────────────────────────────────────────────────────

test("Farm: a session with nothing logged is discarded on one line (F6)", function()
  world(function(g)
    F:Start()
    local out = chat(function() F:FinishVerb() end)
    assertEqual(table.concat(out, " | "), "farm session discarded: nothing was gained.")
    assertEqual(#g.farm[me()].sessions, 0)
  end)
end)

test("Farm: the finish names the session, its value and its clock, then trims to the cap", function()
  world(function(g)
    g.farmKeep = 2
    for n = 1, 3 do
      F:Start()
      clock.t = clock.t + 600
      sendGold(10000 * n, "KILL")
      local out = chat(function() F:FinishVerb() end)
      assertEqual(out[1], ("farm session finished: Testville, %dg in 00:10:00."):format(n))
    end
    local list = g.farm[me()].sessions
    assertEqual(#list, 2, "the cap keeps two")
    assertEqual(list[1].id, 2, "the oldest went")
    assertEqual(F:CountOverCap(1), 1)
    assertEqual(F:OnKeepChanged(1), 1)
    assertEqual(#list, 1)
    assertEqual(F:OnKeepChanged(0), 0, "0 keeps all")
  end)
end)

test("Farm: the verbs answer each state, the bare verb toggles the panel, the status line reads the session", function()
  world(function()
    local toggled = 0
    with(NS.FarmPanel, { Toggle = function() toggled = toggled + 1 end }, function()
      assertEqual(table.concat(chat(function() F:RunVerb("") end)), "", "bare: no chat line")
    end)
    assertEqual(toggled, 1, "bare toggles the companion panel (M4.2)")
    assertEqual(table.concat(chat(function() F:PrintStatus() end)), "no farm session is running.")
    assertEqual(table.concat(chat(function() F:RunVerb("pause") end)), "no farm session is running.")
    assertEqual(table.concat(chat(function() F:RunVerb("resume") end)), "no farm session is running.")
    assertEqual(table.concat(chat(function() F:RunVerb("finish") end)), "no farm session is running.")
    assertEqual(table.concat(chat(function() F:RunVerb("start") end)), "farm session started.")
    assertEqual(table.concat(chat(function() F:RunVerb("resume") end)), "the farm session is not paused.")
    assertEqual(table.concat(chat(function() F:RunVerb("PAUSE") end)), "farm session paused.")
    assertEqual(table.concat(chat(function() F:RunVerb("pause") end)), "the farm session is already paused.")
    local status = table.concat(chat(function() F:PrintStatus() end))
    assertEqual(status, "farm session paused (manual) in Testville: 00:00:00 active, 0c (\226\128\148/h).")
    assertEqual(table.concat(chat(function() F:RunVerb("resume") end)), "farm session resumed.")
    assertEqual(table.concat(chat(function() F:RunVerb("bogus") end)), "usage: /lh farm [start|pause|resume|finish]")
    -- The pause and resume lines are log lines, so this session is saved, not discarded (F6).
    local out = chat(function() NS.Slash:OnSlash("farm finish") end)
    assertEqual(table.concat(out), "farm session finished: Testville, 0c in 00:00:00.", "the COMMANDS row routes")
  end)
end)

test("Farm: an idle pause made manual by the verb stays closed to gains", function()
  world(function()
    local s = F:Start()
    FM.Pause(s, "idle", T0 + 10)
    F:PauseVerb()
    assertEqual(s.pauseReason, "manual")
    sendGold(100, "KILL")
    assertEqual(s.money.KILL, nil)
  end)
end)

-- ── storage ──────────────────────────────────────────────────────────────────────────────────

test("Farm: StorageStats estimates every saved and open session; Database:StorageStats carries it", function()
  world(function(g)
    g.farm["Other-Realm"] = { nextId = 2, sessions = { { log = { "1|d", "2|d" }, items = { [1] = {} },
      currencies = {}, costs = { REPAIR = 1 }, zoneSec = { A = 1, B = 2 } } } }
    local st = F:StorageStats()
    assertEqual(st.sessions, 1)
    assertEqual(st.bytes, 256 + 60 * 2 + 90 * 1 + 40 * 3)
    F:Start()
    assertEqual(F:StorageStats().sessions, 2, "the open session counts")
    local db = NS.Database:StorageStats()
    assertEqual(db.farmSessions, 2)
    assertEqual(db.farmBytes, F:StorageStats().bytes)
    g.farm["Other-Realm"] = nil
  end)
end)

-- ── the Farm page's rows (§9.2, M4.5; settings/SchemaFarm.lua) ───────────────────────────────

test("Farm: Pause after idle re-arms the ticker; Pause when AFK off resumes an AFK pause", function()
  -- red under: an idle change that waits out the old interval, or an AFK pause that outlives the
  -- setting that made it.
  world(function()
    local p = NS.db.profile.settings.farm
    local savedIdle, savedAfk = p.idleMinutes, p.pauseOnAFK
    local ok, err = pcall(function()
      local s = F:Start()
      local h = F._tick
      assertTrue(h ~= nil, "the idle ticker is armed")
      NS.Schema:Set("settings.farm.idleMinutes", 10)
      assertTrue(F._tick ~= nil and F._tick ~= h, "a fresh ticker")
      assertTrue(h.canceled == true, "the old one canceled")
      clock.t = T0 + 30
      with(NS.Compat, { IsPlayerAFK = function() return true end }, function() F:OnFlags("player") end)
      assertEqual(s.pauseReason, "afk", "AFK paused it")
      clock.t = T0 + 90
      NS.Schema:Set("settings.farm.pauseOnAFK", false)
      assertTrue(s.runningSince == T0 + 90 and s.pauseReason == nil, "Pause when AFK off resumed it")
      NS.Schema:Set("settings.farm.pauseOnAFK", true)
      assertTrue(s.runningSince == T0 + 90, "turning it back on pauses nothing")
    end)
    p.idleMinutes, p.pauseOnAFK = savedIdle, savedAfk
    if not ok then error(err, 0) end
  end)
end)
