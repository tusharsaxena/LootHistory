local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- core/Dispatch.lua (LootHistory#37, req-lh-sim.md §3.2-3.3): ONE capture event table and ONE
-- read-side hook table. Every capture registration the four capture modules make comes out of
-- NS.EVENT_ROWS, and every read-side hook out of NS.HOOK_ROWS, so a simulated delivery
-- (NS.DeliverAll) reaches exactly the handlers the client would call.
--
-- This slot runs after tests/test_disabled.lua, which leaves the whole addon brought up, so the
-- registrations are live here. Every case leaves the addon up again on the way out.

-- The (target, event) set the four capture modules registered BEFORE the dispatch refactor, read
-- off the kit's registration survey with the hand-written Enable lists still in place and pasted
-- here as data. A list derived from NS.EVENT_ROWS would agree with the rows however wrong they got.
local SNAPSHOT = {
  "bus:CHALLENGE_MODE_COMPLETED", "bus:CHALLENGE_MODE_RESET", "bus:CHALLENGE_MODE_START",
  "bus:CHAT_MSG_CURRENCY", "bus:CHAT_MSG_LOOT", "bus:CHAT_MSG_MONEY", "bus:ENCOUNTER_END",
  "bus:ENCOUNTER_START", "bus:LOOT_OPENED", "bus:QUEST_TURNED_IN", "bus:TRADE_ACCEPT_UPDATE",
  "bus:ZONE_CHANGED_NEW_AREA",
  "ledger:ACCOUNT_MONEY", "ledger:BAG_UPDATE", "ledger:BAG_UPDATE_DELAYED",
  "ledger:CURRENCY_DISPLAY_UPDATE", "ledger:CURRENCY_TRANSFER_LOG_UPDATE", "ledger:MAIL_INBOX_UPDATE",
  "ledger:OWNED_AUCTIONS_UPDATED", "ledger:PLAYERBANKSLOTS_CHANGED",
  "ledger:PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", "ledger:PLAYER_EQUIPMENT_CHANGED",
  "ledger:PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "ledger:PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
  "ledger:PLAYER_MONEY", "ledger:PLAYER_REGEN_ENABLED",
  "out:ADDON_LOADED", "out:MAIL_FAILED", "out:MAIL_SEND_SUCCESS",
  "out:PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "out:PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
  "out:TRADE_ACCEPT_UPDATE",
  "spell:UNIT_SPELLCAST_SUCCEEDED:player",
}

-- The shared bus also carries the lifecycle's own PLAYER_ENTERING_WORLD (core/LifecycleSetup.lua),
-- which is not a capture event and has never been one of the four modules' registrations.
local NOT_CAPTURE = { ["bus:PLAYER_ENTERING_WORLD"] = true }

local function targetKeys()
  local A, R = NS.Attribution, NS.Reconciler
  local t = { [NS.addon] = "bus" }
  if A.__outEv then t[A.__outEv] = "out" end
  if A.__spellFrame then t[A.__spellFrame] = "spell" end
  if R.__ev then t[R.__ev] = "ledger" end
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
  assertEqual(#(NS.EVENT_ROWS or {}), #SNAPSHOT, "one row per (target, event) registration")
end)

test("Dispatch: row order is Attribution, AttributionOut, Collector, Reconciler", function()
  -- TOC order, which is the stand-up order (core/LifecycleSetup.lua's STAND_UP_STEPS).
  assertEqual(ownersInOrder(), "Attribution,AttributionOut,Collector,Reconciler")
  local hooks, seen = {}, {}
  for _, row in ipairs(NS.HOOK_ROWS or {}) do
    if not seen[row.owner] then seen[row.owner] = true; hooks[#hooks + 1] = row.owner end
  end
  assertEqual(table.concat(hooks, ","), "Attribution,AttributionOut")
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
    for _, owner in ipairs({ "Attribution", "AttributionOut", "Collector", "Reconciler" }) do
      local n, total = registeredBy(owner)
      assertTrue(total > 0, owner .. " owns no rows")
      assertEqual(n, total, owner .. ": every row is registered while the addon is up")
    end

    NS.Schema:Set("settings.trackLedger", false)
    assertEqual((registeredBy("Reconciler")), 0, "trackLedger off unregisters every Reconciler row")
    assertEqual(#liveCapture(), #SNAPSHOT - 14, "and only those fourteen come off the live set")
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
