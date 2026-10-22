local _, NS = ...

-- ONE capture event table and ONE read-side hook table (LootHistory#37, req-lh-sim.md §3.2-3.3).
--
-- Before this file the four capture modules each registered from a hand-written list on their own
-- target (Attribution on the shared bus plus a per-unit spell frame, AttributionOut on `__outEv`,
-- Collector on the bus, Reconciler on `__ev`), and the read-side hooks were installed inline. A
-- simulated delivery then had no way to reach "exactly the handlers the client would call". Now
-- every capture registration is a ROW here, appended by its module at file load (the
-- R.SCAN_STEPS precedent, modules/Escrow.lua), so row order is TOC order, which is the stand-up
-- order (core/LifecycleSetup.lua's STAND_UP_STEPS): Attribution, AttributionOut, Collector,
-- Reconciler.
--
--   NS.EVENT_ROWS  ordered { event, owner, target, fn, unit? }. `target` is "bus" (NS.addon),
--                  "out" (Attribution.__outEv), "ledger" (Reconciler.__ev) or "spell" (the
--                  RegisterUnitEvent frame, `unit` its filter). fn(event, ...) gets the client's
--                  full payload. `registered` is true only while the registration is live.
--   NS.HOOK_ROWS   ordered { name, owner, fn, tbl?, install? }. A plain row hooks the global
--                  `name` through Compat.HookSecure; `tbl` (a function answering the table, read at
--                  install time) makes it a Compat.HookSecureMember hook on that table's `name`;
--                  `install` names a Compat installer that owns its own presence ladder
--                  (HookUseContainerItem). fn(...) gets the hooked call's arguments.
--
-- Hooks go in ONCE PER SESSION (hooksecurefunc has no un-hook), so the latches stay in the modules
-- (`_hooked`, `_outHooked`) and the stood-down gate stays in the hook bodies (slash-commands-§7).
--
-- THE REAL-EVENT SEAM. Every live registration's handler is NS.Deliver and every installed hook's
-- is NS.DeliverHook. Each tests one hook point, NS.RealEventFilter (nil until the simulator sets
-- it): when set and it answers true the real event is consumed. With no filter the cost is one nil
-- test per event, so tests/perf.lua's baselines do not move; the Shape-A perf brackets stay inside
-- the module handlers.
--
-- LOAD-BEARING POSITION (see LootHistory.toc): above every module, which append rows at file load.

local EVENT_ROWS = NS.EVENT_ROWS or {}
local HOOK_ROWS = NS.HOOK_ROWS or {}
NS.EVENT_ROWS, NS.HOOK_ROWS = EVENT_ROWS, HOOK_ROWS

--- Append a capture event row. Called at file load by the module that owns it.
function NS.EventRow(owner, target, event, fn, unit)
  local row = { owner = owner, target = target, event = event, fn = fn, unit = unit }
  EVENT_ROWS[#EVENT_ROWS + 1] = row
  return row
end

--- Append a read-side hook row (opts: tbl, install). Called at file load by its owner.
function NS.HookRow(owner, name, fn, opts)
  local row = { owner = owner, name = name, key = "hook:" .. name, fn = fn,
                tbl = opts and opts.tbl, install = opts and opts.install }
  HOOK_ROWS[#HOOK_ROWS + 1] = row
  return row
end

--- A real client event reaching a row.
function NS.Deliver(row, event, ...)
  local filter = NS.RealEventFilter
  if filter and filter(row, event, ...) then return end
  return row.fn(event, ...)
end

--- A real hooked client call reaching a hook row. The filter sees "hook:<name>" as the event.
function NS.DeliverHook(row, ...)
  local filter = NS.RealEventFilter
  if filter and filter(row, row.key, ...) then return end
  return row.fn(...)
end

local function handlerFor(row)
  local h = row.handler
  if not h then
    h = function(event, ...) return NS.Deliver(row, event, ...) end
    row.handler = h
  end
  return h
end

--- Register every `owner` row whose target is `targetKey` on `targetObj`, each through Core's
--- per-event helper (events-frames-taint-§1), so a refused name costs only itself and lands once on
--- NS.RejectedEvents. A unit row registers through SafeRegisterUnitEvent, and the frame's OnEvent
--- script routes to its rows. Answers the event names that registered, in row order.
function NS.RegisterRows(owner, targetObj, targetKey)
  local names, byEvent = {}, nil
  for i = 1, #EVENT_ROWS do
    local row = EVENT_ROWS[i]
    if row.owner == owner and row.target == targetKey then
      local ok
      if row.unit then
        ok = NS.SafeRegisterUnitEvent(targetObj, row.event, NS.RejectedEvents, row.unit)
        byEvent = byEvent or {}
        byEvent[row.event] = row
      else
        ok = NS.SafeRegisterEvent(targetObj, row.event, handlerFor(row), NS.RejectedEvents)
      end
      if ok then
        row.registered, row.targetObj = true, targetObj
        names[#names + 1] = row.event
      end
    end
  end
  if byEvent then
    -- Set whether or not the registration took, as the hand-written frame did: the script costs
    -- nothing when no event reaches it.
    targetObj:SetScript("OnEvent", function(_, event, ...)
      local row = byEvent[event]
      if row then return NS.Deliver(row, event, ...) end
    end)
  end
  return names
end

--- Unregister every live `owner` row by name from the target it registered on, and clear its flag.
--- A by-name unregister, never UnregisterAllEvents: the shared bus carries other owners' rows.
function NS.UnregisterRows(owner)
  for i = 1, #EVENT_ROWS do
    local row = EVENT_ROWS[i]
    if row.owner == owner then
      local t = row.targetObj
      if row.registered and t and t.UnregisterEvent then t:UnregisterEvent(row.event) end
      row.registered, row.targetObj = nil, nil
    end
  end
end

--- Install every `owner` hook row. The caller holds the once-per-session latch. Answers the count.
function NS.InstallHookRows(owner)
  local C, n = NS.Compat, 0
  for i = 1, #HOOK_ROWS do
    local row = HOOK_ROWS[i]
    if row.owner == owner then
      local hook = function(...) return NS.DeliverHook(row, ...) end
      local ok
      if row.install then ok = C[row.install](hook)
      elseif row.tbl then ok = C.HookSecureMember(row.tbl(), row.name, hook)
      else ok = C.HookSecure(row.name, hook) end
      row.installed = ok and true or nil
      if ok then n = n + 1 end
    end
  end
  return n
end

local function isolated(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and NS.State.debug and NS.Debug then NS.Debug("Dispatch", "row raised: %s", tostring(err)) end
end

--- Deliver `event` to every registered row in order, or "hook:<name>" to every installed hook row,
--- each under pcall so one raising row never stops the rest. Bypasses RealEventFilter: this is the
--- simulated delivery. Answers how many rows it called.
function NS.DeliverAll(event, ...)
  local n = 0
  if type(event) == "string" and event:sub(1, 5) == "hook:" then
    for i = 1, #HOOK_ROWS do
      local row = HOOK_ROWS[i]
      if row.installed and row.key == event then n = n + 1; isolated(row.fn, ...) end
    end
    return n
  end
  for i = 1, #EVENT_ROWS do
    local row = EVENT_ROWS[i]
    if row.registered and row.event == event then n = n + 1; isolated(row.fn, event, ...) end
  end
  return n
end
