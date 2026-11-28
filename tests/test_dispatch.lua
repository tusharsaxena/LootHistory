local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse
local PM = dofile("tests/mock_progress.lua")

-- core/Dispatch.lua (LootHistory#37, Ka0sAddonsCommonTasks req-lh-sim.md §3.2-3.3): ONE capture event table and ONE
-- read-side hook table. Every capture registration the four capture modules make comes out of
-- NS.EVENT_ROWS, and every read-side hook out of NS.HOOK_ROWS, so a simulated delivery
-- (NS.DeliverAll) reaches exactly the handlers the client would call.
--
-- This slot runs after tests/test_disabled.lua, which leaves the whole addon brought up, so the
-- registrations are live here. Every case leaves the addon up again on the way out.

-- The (target, event) set the four capture modules registered BEFORE the dispatch refactor, read
-- off the kit's registration survey with the hand-written Enable lists still in place and pasted
-- here as data. A list derived from NS.EVENT_ROWS would agree with the rows however wrong they got.
-- Rows added since, by hand and with their own case: the bank's two re-read cues,
-- ledger:BAG_CONTAINER_UPDATE and ledger:BANK_TABS_CHANGED (the WoW Forever port, ruling R8); the
-- Reputation owner's bus:FACTION_STANDING_CHANGED (rep/appearance spec §3.1, M2.2); the Appearance
-- owner's bus:TRANSMOG_COLLECTION_SOURCE_ADDED and _REMOVED (§3.1, M2.3; Retail only); the
-- Progress owners' five (toast spec §5.5, #38 M3.1), live while the default Main feed wants
-- experience and skill-ups; the toast feeds' two combat rows on their own `toasts` target (toast spec
-- §8.5, #38 M3.3), live while any feed is enabled.
local SNAPSHOT = {
  "bus:CHALLENGE_MODE_COMPLETED", "bus:CHALLENGE_MODE_RESET", "bus:CHALLENGE_MODE_START",
  "bus:CHAT_MSG_CURRENCY", "bus:CHAT_MSG_LOOT", "bus:CHAT_MSG_MONEY", "bus:CHAT_MSG_SKILL", "bus:ENCOUNTER_END",
  "bus:ENCOUNTER_START", "bus:FACTION_STANDING_CHANGED", "bus:LOOT_CLOSED", "bus:LOOT_OPENED",
  "bus:PLAYER_LEVEL_UP", "bus:PLAYER_REGEN_ENABLED", "bus:PLAYER_XP_UPDATE",
  "bus:QUEST_TURNED_IN", "bus:SKILL_LINES_CHANGED", "bus:TRADE_ACCEPT_UPDATE",
  "bus:TRANSMOG_COLLECTION_SOURCE_ADDED", "bus:TRANSMOG_COLLECTION_SOURCE_REMOVED",
  "bus:ZONE_CHANGED_NEW_AREA",
  "ledger:ACCOUNT_MONEY", "ledger:BAG_CONTAINER_UPDATE", "ledger:BAG_UPDATE", "ledger:BAG_UPDATE_DELAYED",
  "ledger:BANK_TABS_CHANGED",
  "ledger:CURRENCY_DISPLAY_UPDATE", "ledger:CURRENCY_TRANSFER_LOG_UPDATE", "ledger:MAIL_INBOX_UPDATE",
  "ledger:OWNED_AUCTIONS_UPDATED", "ledger:PLAYERBANKSLOTS_CHANGED",
  "ledger:PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", "ledger:PLAYER_EQUIPMENT_CHANGED",
  "ledger:PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "ledger:PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
  "ledger:PLAYER_MONEY", "ledger:PLAYER_REGEN_ENABLED",
  "out:ADDON_LOADED", "out:MAIL_FAILED", "out:MAIL_SEND_SUCCESS",
  "out:PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "out:PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
  "out:TRADE_ACCEPT_UPDATE",
  "spell:UNIT_SPELLCAST_SUCCEEDED:player",
  "toasts:PLAYER_REGEN_DISABLED", "toasts:PLAYER_REGEN_ENABLED",
}
-- The warband bank's two rows are Retail-only (R1, clients-§4), and so are the keystone's four (R2):
-- WoW Forever registers none of them, nor the appearances' two (rep/appearance spec, D7).
if T.forever then
  local retailOnly = { ["ledger:ACCOUNT_MONEY"] = true, ["ledger:PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED"] = true,
    ["bus:CHALLENGE_MODE_COMPLETED"] = true, ["bus:CHALLENGE_MODE_RESET"] = true,
    ["bus:CHALLENGE_MODE_START"] = true, ["bus:ZONE_CHANGED_NEW_AREA"] = true,
    ["bus:TRANSMOG_COLLECTION_SOURCE_ADDED"] = true, ["bus:TRANSMOG_COLLECTION_SOURCE_REMOVED"] = true }
  for i = #SNAPSHOT, 1, -1 do if retailOnly[SNAPSHOT[i]] then table.remove(SNAPSHOT, i) end end
end

-- The farm session's three rows (#39, farm spec §5.8), on its own two targets: registered only while
-- a session is open, so they are not in SNAPSHOT (no session is open here) and have their own case.
-- Both clients: Farm's ZONE_CHANGED_NEW_AREA is its own row, not Attribution's Retail-only one.
local FARM_ROWS = { "farm:PLAYER_DEAD", "farm:ZONE_CHANGED_NEW_AREA", "farmUnit:PLAYER_FLAGS_CHANGED:player" }

-- The shared bus also carries the lifecycle's own PLAYER_ENTERING_WORLD (core/LifecycleSetup.lua),
-- which is not a capture event and has never been one of the four modules' registrations.
local NOT_CAPTURE = { ["bus:PLAYER_ENTERING_WORLD"] = true }

local function targetKeys()
  local A, R = NS.Attribution, NS.Reconciler
  local t = { [NS.addon] = "bus" }
  if A.__outEv then t[A.__outEv] = "out" end
  if A.__spellFrame then t[A.__spellFrame] = "spell" end
  if R.__ev then t[R.__ev] = "ledger" end
  if NS.Toasts and NS.Toasts.__rows then t[NS.Toasts.__rows] = "toasts" end
  return t
end

-- Every live game-event registration on the four capture targets, as "target:EVENT[:unit]".
local function liveCapture()
  local keys, out = targetKeys(), {}
  for _, r in ipairs(M.__registrations()) do
    local k = keys[r.target]
    if k and r.kind ~= "message" then
      local s = k .. ":" .. tostring(r.event) .. (r.unit and (":" .. tostring(r.unit)) or "")
      if not NOT_CAPTURE[s] then out[#out + 1] = s end
    end
  end
  table.sort(out)
  return out
end

-- The same set, read off the rows that say they registered.
local function fromRows()
  local out = {}
  for _, row in ipairs(NS.EVENT_ROWS or {}) do
    if row.registered then
      out[#out + 1] = row.target .. ":" .. row.event .. (row.unit and (":" .. row.unit) or "")
    end
  end
  table.sort(out)
  return out
end

local function ownersInOrder()
  local seen, out = {}, {}
  for _, row in ipairs(NS.EVENT_ROWS or {}) do
    if not seen[row.owner] then seen[row.owner] = true; out[#out + 1] = row.owner end
  end
  return table.concat(out, ",")
end

-- Run `body`, then put the addon back up whatever happened: the suites after this one read a
-- brought-up addon.
-- The Progress owners' rows, live only while a toast feed wants experience or skill-ups.
local PROGRESS_ROWS = { ["bus:CHAT_MSG_SKILL"] = true, ["bus:PLAYER_LEVEL_UP"] = true,
  ["bus:PLAYER_REGEN_ENABLED"] = true, ["bus:PLAYER_XP_UPDATE"] = true, ["bus:SKILL_LINES_CHANGED"] = true }

-- The toast feeds' combat rows, live only while some feed is enabled.
local TOAST_ROWS = { ["toasts:PLAYER_REGEN_DISABLED"] = true, ["toasts:PLAYER_REGEN_ENABLED"] = true }

--- SNAPSHOT with no toast feed enabled: the Progress rows and the toast combat rows are down.
local function feedOffSnapshot()
  local out = {}
  for _, k in ipairs(SNAPSHOT) do if not (PROGRESS_ROWS[k] or TOAST_ROWS[k]) then out[#out + 1] = k end end
  return table.concat(out, ",")
end

--- Run `body` with every toast feed disabled (the gain feed then wants nothing), and put the feeds back.
local function withFeedsOff(body)
  local feeds, saved = NS.db.profile.settings.toasts.feeds, {}
  for fid, f in pairs(feeds) do saved[fid] = f.enabled; f.enabled = false end
  NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "toasts")
  local ok, err = pcall(body)
  for fid, v in pairs(saved) do feeds[fid].enabled = v end
  NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "toasts")
  if not ok then error(err, 0) end
end

local function restoring(body)
  local ok, err = pcall(body)
  NS.Schema:Set("settings.trackLedger", true)
  NS.Schema:Set("settings.enabled", true)
  if not ok then error(err, 0) end
end

test("Dispatch: every capture registration comes from NS.EVENT_ROWS and the (target, event) set "
  .. "equals the pre-refactor snapshot", function()
  NS.Schema:Set("settings.trackLedger", true)
  local live = table.concat(liveCapture(), ",")
  assertEqual(live, table.concat(SNAPSHOT, ","),
    "the capture registration set moved: the refactor must keep every (target, event) pair")
  assertEqual(table.concat(fromRows(), ","), live,
    "a live capture registration did not come out of NS.EVENT_ROWS (or a row claims one that is not live)")
  assertEqual(#(NS.EVENT_ROWS or {}), #SNAPSHOT + #FARM_ROWS,
    "one row per (target, event) registration, the farm session's three included")
end)

test("Dispatch: row order is Attribution, AttributionOut, Collector, Reputation, Appearance, Progress, Reconciler, Toasts", function()
  -- TOC order, which is the stand-up order (core/LifecycleSetup.lua's STAND_UP_STEPS). WoW Forever
  -- declares no Appearance rows (C.FEATURE.appearances), so the owner is not in its list. Progress
  -- (#38) owns three row owners, one per thing the gain feed can want. The toast feeds' combat rows
  -- (#38) come last: modules/ToastFeed.lua loads after the Reconciler, and the farm session's (#39,
  -- modules/Farm.lua) between them.
  local progress = "ProgressXP,ProgressSkill,ProgressRegen,"
  assertEqual(ownersInOrder(), T.forever and ("Attribution,AttributionOut,Collector,Reputation," .. progress .. "Reconciler,Farm,Toasts")
    or ("Attribution,AttributionOut,Collector,Reputation,Appearance," .. progress .. "Reconciler,Farm,Toasts"))
  local hooks, seen = {}, {}
  for _, row in ipairs(NS.HOOK_ROWS or {}) do
    if not seen[row.owner] then seen[row.owner] = true; hooks[#hooks + 1] = row.owner end
  end
  assertEqual(table.concat(hooks, ","), "Attribution,AttributionOut")
end)

test("Dispatch: the farm session's three rows register on its own targets while a session is open, and go at finish", function()
  -- red under: a farm row on the shared bus (the toast feeds' and Attribution's own registrations
  -- would be clobbered), or one left registered after the session closed (farm spec §5.1: with no
  -- session open, farm holds no registration at all).
  local F, g, cf = NS.Farm, NS.db.global, M.DEFAULT_CHAT_FRAME
  local saved, savedAdd = g.farm, cf.AddMessage
  g.farm, cf.AddMessage = {}, function() end
  local function farmLive()
    local keys, out = { [F.__ev or false] = "farm", [F.__unitFrame or false] = "farmUnit" }, {}
    for _, r in ipairs(M.__registrations()) do
      local k = keys[r.target]
      if k and r.kind ~= "message" then
        out[#out + 1] = k .. ":" .. tostring(r.event) .. (r.unit and (":" .. tostring(r.unit)) or "")
      end
    end
    table.sort(out)
    return table.concat(out, ",")
  end
  local ok, err = pcall(function()
    assertEqual(farmLive(), "", "no session: no farm registration")
    F:Start()
    local rows = {}
    for _, row in ipairs(NS.EVENT_ROWS) do
      if row.owner == "Farm" and row.registered then
        rows[#rows + 1] = row.target .. ":" .. row.event .. (row.unit and (":" .. row.unit) or "")
      end
    end
    table.sort(rows)
    assertEqual(table.concat(rows, ","), table.concat(FARM_ROWS, ","), "every farm row registered")
    assertEqual(farmLive(), "farm:LOGOUT_CANCEL,farm:PLAYER_CAMPING,farm:PLAYER_DEAD,farm:PLAYER_LOGOUT,"
      .. "farm:PLAYER_QUITING,farm:ZONE_CHANGED_NEW_AREA,farmUnit:PLAYER_FLAGS_CHANGED:player",
      "the rows plus the four lifecycle events, on the farm targets")
    F:FinishVerb()
    assertEqual(farmLive(), "", "the finish took every farm registration down")
  end)
  if F:Active() then F:Finish("manual", os.time()) end
  g.farm, cf.AddMessage = saved, savedAdd
  if not ok then error(err, 0) end
end)

local function registeredBy(owner)
  local n, total = 0, 0
  for _, row in ipairs(NS.EVENT_ROWS) do
    if row.owner == owner then
      total = total + 1
      if row.registered then n = n + 1 end
    end
  end
  return n, total
end

test("Dispatch: registered follows Enable/Disable, including trackLedger off", function()
  restoring(function()
    local owners = { "Attribution", "AttributionOut", "Collector", "Reputation", "ProgressXP", "ProgressSkill",
      "ProgressRegen", "Reconciler", "Toasts" }
    if not T.forever then table.insert(owners, 5, "Appearance") end
    for _, owner in ipairs(owners) do
      local n, total = registeredBy(owner)
      assertTrue(total > 0, owner .. " owns no rows")
      assertEqual(n, total, owner .. ": every row is registered while the addon is up")
    end

    NS.Schema:Set("settings.trackLedger", false)
    assertEqual((registeredBy("Reconciler")), 0, "trackLedger off unregisters every Reconciler row")
    -- Sixteen Reconciler rows on Retail; fourteen on WoW Forever, which lacks the warband bank's two
    -- (R1). Both carry the bank's two re-read cues (R8).
    local rows = T.forever and 14 or 16
    assertEqual(#liveCapture(), #SNAPSHOT - rows, "and only those " .. rows .. " come off the live set")
    local n, total = registeredBy("Collector")
    assertEqual(n, total, "the Collector's rows stay registered with trackLedger off")
    NS.Schema:Set("settings.trackLedger", true)
    n, total = registeredBy("Reconciler")
    assertEqual(n, total, "ticking trackLedger back on registers the Reconciler rows again")

    NS.Schema:Set("settings.enabled", false)
    for _, row in ipairs(NS.EVENT_ROWS) do
      assertFalse(row.registered == true, row.owner .. ":" .. row.event .. " still claims a registration when stood down")
    end
    assertEqual(#liveCapture(), 0, "nothing on the four capture targets survives the stand-down")
    NS.Schema:Set("settings.enabled", true)
    assertEqual(table.concat(fromRows(), ","), table.concat(SNAPSHOT, ","),
      "the stand-up registers every row again")
  end)
end)

-- Swap one row's fn for a recorder; returns the restore function.
local function recordRows(rows, log, raiseOn)
  local saved = {}
  for i, row in ipairs(rows) do
    saved[i] = row.fn
    row.fn = function(...)
      log[#log + 1] = row.owner .. ":" .. (row.event or row.name)
      if raiseOn and raiseOn(row) then error("row raised on purpose") end
      return select("#", ...)
    end
  end
  return function() for i, row in ipairs(rows) do row.fn = saved[i] end end
end

test("Dispatch: DeliverAll calls exactly the registered rows in order and isolates a raising row",
function()
  local rows = {}
  for _, row in ipairs(NS.EVENT_ROWS) do
    if row.event == "TRADE_ACCEPT_UPDATE" or row.event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
      rows[#rows + 1] = row
    end
  end
  assertEqual(#rows, 4, "two handlers each for TRADE_ACCEPT_UPDATE and PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
  local log = {}
  local restore = recordRows(rows, log, function(row) return row.owner == "Attribution" end)
  local ok, err = pcall(function()
    -- Attribution's TRADE_ACCEPT_UPDATE row raises; AttributionOut's still runs after it.
    assertEqual(NS.DeliverAll("TRADE_ACCEPT_UPDATE", 1, 1), 2)
    assertEqual(table.concat(log, ","), "Attribution:TRADE_ACCEPT_UPDATE,AttributionOut:TRADE_ACCEPT_UPDATE")

    -- An unregistered row is not called: trackLedger off takes the Reconciler's SHOW row down.
    for i = #log, 1, -1 do log[i] = nil end
    NS.Schema:Set("settings.trackLedger", false)
    assertEqual(NS.DeliverAll("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 1), 1)
    assertEqual(table.concat(log, ","), "AttributionOut:PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    NS.Schema:Set("settings.trackLedger", true)
    for i = #log, 1, -1 do log[i] = nil end
    assertEqual(NS.DeliverAll("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 1), 2)
    assertEqual(table.concat(log, ","),
      "AttributionOut:PLAYER_INTERACTION_MANAGER_FRAME_SHOW,Reconciler:PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    assertEqual(NS.DeliverAll("NOT_AN_EVENT_ANYONE_REGISTERS"), 0)
  end)
  restore()
  NS.Schema:Set("settings.trackLedger", true)
  if not ok then error(err, 0) end
end)

test("Dispatch: a real event goes through NS.Deliver, and RealEventFilter answering true consumes it",
function()
  local row
  for _, r in ipairs(NS.EVENT_ROWS) do if r.event == "MAIL_FAILED" then row = r end end
  local log = {}
  local restore = recordRows({ row }, log)
  local ok, err = pcall(function()
    -- M.__fire dispatches to the LIVE registration set, which is what the client does.
    M.__fire("MAIL_FAILED")
    assertEqual(#log, 1, "the registration's handler reaches the row through NS.Deliver")
    local seen
    NS.RealEventFilter = function(r, event) seen = r.event .. "/" .. event; return true end
    M.__fire("MAIL_FAILED")
    assertEqual(#log, 1, "a filter answering true consumes the real event")
    assertEqual(seen, "MAIL_FAILED/MAIL_FAILED")
  end)
  NS.RealEventFilter = nil
  restore()
  if not ok then error(err, 0) end
end)

-- The read-side hook installers, recorded rather than reaching the kit's no-op hooksecurefunc.
local function withHookRecorder(body)
  local C = NS.Compat
  local A = NS.Attribution
  local saved = { C.HookSecure, C.HookSecureMember, C.HookUseContainerItem, C.HookGetQuestReward }
  local latches = { A._hooked, A._outHooked }
  local installs = {}
  C.HookSecure = function(name) installs[#installs + 1] = name; return true end
  C.HookSecureMember = function(_, member) installs[#installs + 1] = member; return true end
  C.HookUseContainerItem = function() installs[#installs + 1] = "UseContainerItem"; return true end
  C.HookGetQuestReward = function() installs[#installs + 1] = "GetQuestReward"; return true end
  local ok, err = pcall(body, installs)
  C.HookSecure, C.HookSecureMember, C.HookUseContainerItem, C.HookGetQuestReward =
    saved[1], saved[2], saved[3], saved[4]
  A._hooked, A._outHooked = latches[1], latches[2]
  NS.Schema:Set("settings.enabled", true)
  if not ok then error(err, 0) end
end

test("Dispatch: hook rows install once across Disable/Enable and both BuyMerchantItem rows run, in order",
function()
  withHookRecorder(function(installs)
    assertEqual(#NS.HOOK_ROWS, 18, "five read-side hooks (Attribution) and thirteen outbound (AttributionOut)")
    NS.Schema:Set("settings.enabled", false)
    NS.Attribution._hooked, NS.Attribution._outHooked = nil, nil
    NS.Schema:Set("settings.enabled", true)
    assertEqual(#installs, 18, "every hook row installed on the first stand-up")
    NS.Schema:Set("settings.enabled", false)
    NS.Schema:Set("settings.enabled", true)
    assertEqual(#installs, 18, "a second stand-up installs nothing: hooksecurefunc has no un-hook")

    local buys = {}
    for _, row in ipairs(NS.HOOK_ROWS) do
      if row.name == "BuyMerchantItem" then buys[#buys + 1] = row end
      assertTrue(row.installed == true, row.name .. " is not marked installed")
    end
    assertEqual(#buys, 2, "BuyMerchantItem keeps its two rows")
    local log = {}
    local restore = recordRows(buys, log)
    local n = NS.DeliverAll("hook:BuyMerchantItem", 3, 1)
    restore()
    assertEqual(n, 2)
    assertEqual(table.concat(log, ","), "Attribution:BuyMerchantItem,AttributionOut:BuyMerchantItem",
      "StampVendor runs before StampOut BUY")
  end)
end)

test("Dispatch: hook:<name> through DeliverAll reaches the HOOK_ROWS fns", function()
  withHookRecorder(function()
    NS.Schema:Set("settings.enabled", false)
    NS.Attribution._hooked, NS.Attribution._outHooked = nil, nil
    NS.Schema:Set("settings.enabled", true)
    local State = NS.State
    State.outContext = nil
    assertEqual(NS.DeliverAll("hook:RepairAllItems"), 1)
    assertEqual(State.outContext and State.outContext.reason, "REPAIR",
      "the real hook body ran: a repair stamps REPAIR on the outbound context")
    State.lootContext = nil
    assertEqual(NS.DeliverAll("hook:GetQuestReward"), 1)
    assertEqual(State.lootContext and State.lootContext.source, NS.Constants.SourceType.QUEST)
    assertEqual(NS.DeliverAll("hook:NotAHook"), 0)
    State.outContext, State.lootContext = nil, nil
  end)
end)

test("Dispatch: Record reputation off unregisters bus:FACTION_STANDING_CHANGED and on restores it", function()
  -- red under: a draw gate (the row left registered and the handler returning early), or a listener
  -- that hears only the module's own reason and not the switch (slash-commands-§7, anti-pattern #85).
  local function live()
    for _, k in ipairs(liveCapture()) do if k == "bus:FACTION_STANDING_CHANGED" then return true end end
    return false
  end
  local Rep = NS.Reputation
  local h = PM.install(M)
  local ok, err = pcall(withFeedsOff, function()
    assertTrue(live(), "precondition: the row is live while the addon is up")
    h.faction(72, { name = "Stormwind", reaction = 5, standing = 3000 })
    h.list = { { id = 72, depth = 0 } }
    assertTrue(Rep:Seed(true), "precondition: the baseline is seeded")
    NS.Schema:Set("settings.recordReputation", false)
    assertFalse(live(), "the switch off takes the registration down")
    assertEqual((registeredBy("Reputation")), 0)
    assertTrue(Rep._settings ~= nil, "the settings listener stays, so the switch can come back")
    -- red under: DisableCapture without its ResetState (a stale baseline the switch's return diffs
    -- against), or EnableCapture without its seed (every first change after it unseeded).
    assertEqual(Rep:Baseline(72), nil, "the switch off drops the baseline")
    assertEqual(Rep._seedTimer, nil, "and any pending seed")
    h.factions[72].standing = 3500
    NS.Schema:Set("settings.recordReputation", true)
    assertTrue(live(), "the switch on registers it again")
    assertEqual(table.concat(fromRows(), ","), feedOffSnapshot())
    assertTrue(Rep._seedTimer ~= nil, "the switch on arms the seed again")
    local seed = M.__timers[#M.__timers]
    assertEqual(seed.delay, 2, "two seconds out")
    seed.fn()
    assertEqual(Rep:Baseline(72) and Rep:Baseline(72).standing, 3500, "the seed refilled the baseline from now")
  end)
  NS.Schema:Set("settings.recordReputation", true)
  Rep:ResetState()
  h.uninstall()
  if not ok then error(err, 0) end
end)

test("Dispatch: Record appearances off unregisters the two TRANSMOG rows and on restores them", function()
  -- red under: a draw gate (the rows left registered and the handler returning early), or a listener
  -- that hears only another module's reason (slash-commands-§7, anti-pattern #85). On WoW Forever
  -- the rows are never declared (clients-§4), so the switch has nothing to take down.
  local function live()
    local n = 0
    for _, k in ipairs(liveCapture()) do
      if k == "bus:TRANSMOG_COLLECTION_SOURCE_ADDED" or k == "bus:TRANSMOG_COLLECTION_SOURCE_REMOVED" then n = n + 1 end
    end
    return n
  end
  if T.forever then
    assertEqual(live(), 0, "WoW Forever registers no appearance row")
    assertEqual(select(2, registeredBy("Appearance")), 0, "and declares none")
    assertEqual(NS.Appearance._settings, nil, "nor stands up a settings listener for a feature it lacks")
    return
  end
  local savedH = NS.db.global.history
  local ok, err = pcall(withFeedsOff, function()
    NS.db.global.history = {}
    assertEqual(live(), 2, "precondition: both rows are live while the addon is up")
    NS.Appearance:OnSourceAdded(nil, 424243)
    assertEqual(#NS.db.global.history, 1, "precondition: the source wrote its row")
    NS.Schema:Set("settings.recordAppearances", false)
    assertEqual(live(), 0, "the switch off takes both registrations down")
    assertEqual((registeredBy("Appearance")), 0)
    assertTrue(NS.Appearance._settings ~= nil, "the settings listener stays, so the switch can come back")
    NS.Schema:Set("settings.recordAppearances", true)
    assertEqual(live(), 2, "the switch on registers them again")
    assertEqual(table.concat(fromRows(), ","), feedOffSnapshot())
    -- red under: DisableCapture without its ResetState, which keeps the duplicate maps across the
    -- switch, so the same source inside 5 s is dropped as a duplicate.
    NS.Appearance:OnSourceAdded(nil, 424243)
    assertEqual(#NS.db.global.history, 2, "after the switch cycled, the same source is a new row")
  end)
  NS.db.global.history = savedH
  NS.Appearance:ResetState()
  NS.Schema:Set("settings.recordAppearances", true)
  if not ok then error(err, 0) end
end)

-- The amendment to M2 §5 (toast spec §5.4, #38 M3.1): a capture row is live while its record switch
-- is on OR the gain feed wants the kind; with both off it is a real unregister.
test("Dispatch: the reputation row follows Record reputation OR the gain feed, and the Progress rows the feed", function()
  local function live(event)
    for _, k in ipairs(liveCapture()) do if k == "bus:" .. event then return true end end
    return false
  end
  local ok, err = pcall(function()
    NS.Schema:Set("settings.recordReputation", false)
    assertTrue(live("FACTION_STANDING_CHANGED"), "switch off, the default Main feed wants reputation: live")
    assertTrue(NS.GainFeed.wants.REPUTATION and NS.GainFeed.on, "the feed wants it")
    withFeedsOff(function()
      assertFalse(live("FACTION_STANDING_CHANGED"), "switch off and no feed: unregistered")
      for k in pairs(PROGRESS_ROWS) do assertFalse(live(k:sub(5)), k .. " is down with no feed") end
      assertFalse(NS.GainFeed.on, "nothing wanted")
      NS.Schema:Set("settings.recordReputation", true)
      assertTrue(live("FACTION_STANDING_CHANGED"), "switch on, no feed: live")
      NS.Schema:Set("settings.recordReputation", false)
    end)
    assertTrue(live("FACTION_STANDING_CHANGED"), "the feed back on registers it again")
    for k in pairs(PROGRESS_ROWS) do assertTrue(live(k:sub(5)), k .. " is back with the feed") end
  end)
  NS.Schema:Set("settings.recordReputation", true)
  if not ok then error(err, 0) end
end)
