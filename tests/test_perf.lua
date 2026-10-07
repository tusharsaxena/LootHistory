-- tests/test_perf.lua — the addon's wiring into LibKa0s-Perf-1.0 (core/PerfSetup.lua): every declared
-- bucket is reached by a real bracket, a dormant probe records nothing, and suspend makes the addon
-- inert without a reload (performance-§1..§6).
--
-- After tests/test_disabled.lua, which leaves the whole addon brought up: the suspend case needs the
-- live registration set underneath it, and takes it back to the state it found.
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local m = T.mocks
local LINK = "|cffa335ee|Hitem:211296::::::::80:::::|h[Vial of Fun]|h|r"

--- Wrap NS.Perf.Note with a per-key call counter. Returns the counts and the restore.
local function spyNotes()
  local seen, P = {}, NS.Perf
  local original = P.Note
  P.Note = function(key, ms, parent) seen[key] = (seen[key] or 0) + 1; return original(key, ms, parent) end
  return seen, function() P.Note = original end
end

--- One call through each bracketed handler. The history and the Reconciler's claim/dirty state are
--- swapped out and back, so the lines it writes leave nothing behind for a later suite.
local function exercise()
  local R = NS.Reconciler
  local savedH = NS.db.global.history
  local savedClaims, savedRecent, savedDirty = R.claims, R.recent, R.dirty
  NS.db.global.history = {}
  R.claims, R.recent, R.dirty = {}, {}, {}
  local ok, err = pcall(function()
    NS.Collector:RefreshUpvalues()
    NS.Collector:OnChatMsgLoot(nil, string.format(m.LOOT_ITEM_SELF, LINK))
    NS.Collector:OnChatMsgCurrency(nil, string.format(m.CURRENCY_GAINED, "|Hcurrency:3008::|h[Valorstones]|h"))
    NS.Collector:OnChatMsgMoney(nil, "You loot 5 Copper")
    NS.Attribution:OnSpellSucceeded(nil, "player", nil, 13262)
    R:OnEvent("BAG_UPDATE", 0)
  end)
  NS.db.global.history = savedH
  R.claims, R.recent, R.dirty = savedClaims, savedRecent, savedDirty
  if not ok then error(err, 0) end
end

test("perf: the buckets are declared in report order", function()
  assertEqual(table.concat(NS.Perf.BUCKET_ORDER, ","), "lootLine,currencyLine,moneyLine,spellCast,ledgerEvent")
end)

test("perf: every declared bucket is reached by a real bracket", function()
  -- red under: a bucket declared in core/PerfSetup.lua with no bracket at its handler, which reads
  -- 0.000 in every capture (performance-§3).
  local seen, restore = spyNotes()
  NS.Perf.on = true
  local ok, err = pcall(exercise)
  NS.Perf.on = false
  restore()
  if not ok then error(err, 0) end
  for _, key in ipairs(NS.Perf.BUCKET_ORDER) do
    assertTrue((seen[key] or 0) > 0, "bucket '" .. key .. "' was never noted")
  end
end)

test("perf: PLAYER_REGEN_ENABLED records no ledgerEvent sample while BAG_UPDATE does", function()
  -- red under: the combat-exit LoginScan/Flush run inside the ledgerEvent bracket, which charges a
  -- whole flush to a bucket declared as dirty bits and debounces (core/PerfSetup.lua).
  local R = NS.Reconciler
  local savedDirty, savedDeferred, savedLogin, savedFlush = R.dirty, R.deferred, R.loginPending, R.Flush
  local flushed = 0
  R.dirty, R.deferred, R.loginPending = {}, true, nil
  R.Flush = function() flushed = flushed + 1 end
  local seen, restore = spyNotes()
  NS.Perf.on = true
  local ok, err = pcall(function()
    R:OnEvent("PLAYER_REGEN_ENABLED")
    assertEqual(flushed, 1, "the regen edge still runs the deferred flush")
    assertEqual(seen.ledgerEvent, nil, "regen was noted under ledgerEvent")
    R:OnEvent("BAG_UPDATE", 0)
    assertEqual(seen.ledgerEvent, 1, "BAG_UPDATE was not noted under ledgerEvent")
  end)
  NS.Perf.on = false
  restore()
  R.dirty, R.deferred, R.loginPending, R.Flush = savedDirty, savedDeferred, savedLogin, savedFlush
  if not ok then error(err, 0) end
end)

test("perf: a dormant probe notes nothing", function()
  -- red under: a bracket that notes without testing Perf.on (performance-§2).
  local seen, restore = spyNotes()
  local ok, err = pcall(exercise)
  restore()
  if not ok then error(err, 0) end
  assertEqual(next(seen), nil)
end)

test("perf: suspend makes the addon inert and resume restores it", function()
  -- The `perf` hold on the one latch (core/LifecycleSetup.lua): the same NS.StandDown `disable`
  -- reaches, asserted on the registrations rather than on a handler's early return.
  NS.Schema:Set("settings.enabled", true)
  assertTrue(NS.addon.__events.CHAT_MSG_LOOT ~= nil, "precondition: capture is up")
  NS.Perf.Suspend()
  assertTrue(NS.Perf.suspended)
  assertEqual(NS.addon.__events.CHAT_MSG_LOOT, nil)
  assertEqual(NS.addon.__events.CHAT_MSG_MONEY, nil)
  assertEqual(NS.Reconciler.__ev, nil)
  assertEqual(NS.Attribution.__outEv, nil)
  NS.Perf.Resume()
  assertTrue(not NS.Perf.suspended)
  assertTrue(NS.addon.__events.CHAT_MSG_LOOT ~= nil)
  assertTrue(NS.Reconciler.__ev ~= nil)
  assertTrue(NS.Attribution.__outEv ~= nil)
end)

test("perf: suspend and resume log to the console whatever the debug flag says", function()
  -- red under: a descriptor `log` routed through the gated NS.Debug, which would leave the console
  -- empty for a player who started a run without `/lh debug on`.
  local saved = NS.State.debug
  NS.State.debug = false
  local buf = NS.DebugLog.buffer
  local from = #buf
  NS.Perf.Suspend()
  NS.Perf.Resume()
  NS.State.debug = saved
  -- Only the lines these two calls wrote: the console is shared with every earlier suite.
  local suspended, resumed
  for i = from + 1, #buf do
    if buf[i]:find("[Perf]", 1, true) and buf[i]:find("SUSPENDED", 1, true) then suspended = true end
    if buf[i]:find("[Perf]", 1, true) and buf[i]:find("RESUMED", 1, true) then resumed = true end
  end
  assertTrue(suspended, "no [Perf] SUSPENDED line, last: " .. tostring(NS.DebugLog:LastLine()))
  assertTrue(resumed, "no [Perf] RESUMED line, last: " .. tostring(NS.DebugLog:LastLine()))
end)

test("perf: /lh perf dispatches to the harness", function()
  local entry
  for _, e in ipairs(NS.COMMANDS) do if e[1] == "perf" then entry = e end end
  assertTrue(entry ~= nil, "no perf verb")
  local lines = NS.Perf.OnCommand("status")
  assertTrue(type(lines) == "table" and #lines > 0)
end)
