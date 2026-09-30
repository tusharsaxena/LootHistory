local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- ── debug-logging-§8 (Diagnosis) and §9 (quiet steady state) ─────────────────────────────────
--
-- The lines a support read of a pasted log needs beyond the flows, and the repeating paths that
-- must stay quiet when nothing changed. docs/debug.md -> ## Coverage lists every tag; this suite
-- pins the lines that were added for it and the two change gates.
--
-- Every case records through a stand-in NS.Debug. Each call site gates on NS.State.debug and then
-- calls NS.Debug by name at call time (the Schema, Options, Slash, Lifecycle and Launcher
-- descriptors late-bind it the same way), so the stand-in sees exactly what the library's sink
-- would, without the 3000-line buffer deciding whether a count moved. The console's own writers --
-- the DebugOnce / DebugChanged gates and the at-enable queue (DebugLogGates 1) -- append through
-- NS.DebugLog:Add rather than the sink, so the console's Add is recorded into the same list for the
-- call. The two never overlap: the stand-in never reaches Add, so no line is counted twice.

--- Run `fn` with logging on and NS.Debug recording. Returns the lines, "[Tag] message".
local function capture(fn)
  local D = NS.DebugLog
  local lines, saved, savedAdd, savedFlag = {}, NS.Debug, D.Add, NS.State.debug
  NS.Debug = function(tag, fmt, ...) lines[#lines + 1] = "[" .. tag .. "] " .. fmt:format(...) end
  D.Add = function(_, tag, msg) lines[#lines + 1] = "[" .. tostring(tag) .. "] " .. tostring(msg) end
  NS.State.debug = true
  local ok, err = pcall(fn)
  NS.Debug, D.Add, NS.State.debug = saved, savedAdd, savedFlag
  if not ok then error(err, 0) end
  return lines
end

local function count(lines, needle)
  local n = 0
  for _, l in ipairs(lines) do if l:find(needle, 1, true) then n = n + 1 end end
  return n
end

local function first(lines, needle)
  for _, l in ipairs(lines) do if l:find(needle, 1, true) then return l end end
  return nil
end

--- Chat swallowed for the call: the refusals under test also print, and the suite list does not
--- want the noise.
local function quietChat(fn)
  local cf = M.DEFAULT_CHAT_FRAME
  local oldAdd = cf.AddMessage
  cf.AddMessage = function() end
  local ok, err = pcall(fn)
  cf.AddMessage = oldAdd
  if not ok then error(err, 0) end
end

--- Run `fn` with the addon switched off through the stored switch (the latch takes `disabled`),
--- then switch it back on. Returns everything logged across both edges and `fn`.
local function whileDisabled(fn)
  return capture(function()
    quietChat(function()
      NS.Schema:Set("settings.enabled", false)
      local ok, err = pcall(fn)
      NS.Schema:Set("settings.enabled", true)
      if not ok then error(err, 0) end
    end)
  end)
end

-- ── state edges ──────────────────────────────────────────────────────────────────────────────

test("coverage: each latch edge is the library's one [Lifecycle] line plus the host's one [State] line", function()
  -- red under: dropping `debug` from the Lifecycle descriptor (core/LifecycleSetup.lua), which
  -- leaves the edge and its holds unlogged; dropping either host line from NS.StandDown /
  -- NS.StandUp, which leaves what this addon took down unsaid; or a host line that names the holds
  -- again, which logs the one edge twice (debug-logging-§4, "The library's own lines").
  local lines = whileDisabled(function() end)
  local all = table.concat(lines, "\n")
  assertEqual(count(lines, "[Lifecycle] stood down: added disabled (holds: disabled)"), 1, all)
  assertEqual(count(lines, "[Lifecycle] stood up: released disabled (holds: none)"), 1, all)
  assertEqual(count(lines, "[Lifecycle]"), 2, all)
  assertEqual(count(lines, "[State] stand-down"), 1, all)
  assertEqual(count(lines, "[State] stand-up"), 1, all)
  assertEqual(count(lines, "holds:"), 2, "only the library's lines name the holds:\n" .. all)
  local down = first(lines, "[State] stand-down")
  assertTrue(down:match("%d+ deferral%(s%) canceled") ~= nil, down)
  -- With logging on, the stand-up's dependency line goes through the at-enable queue and so lands
  -- at once, right after the edge.
  assertEqual(count(lines, "[State] dependencies: "), 1, all)
  local deps = first(lines, "[State] dependencies: ")
  assertTrue(deps:find("price providers: none", 1, true) ~= nil, deps)
  assertTrue(deps:find("latch: LibKa0s-Lifecycle-1.0", 1, true) ~= nil, deps)
end)

-- ── state at enable: the console's at-enable queue (DebugLogGates 1) ─────────────────────────

--- Turn logging on through the console's one seam, as `/lh debug on` does, and return the lines it
--- wrote, from the enable bracket on. Chat is swallowed; the flag is put back afterwards.
local function enableAndRead(D)
  local before = #D.buffer
  quietChat(function() D:SetEnabled(true) end)
  local lines = {}
  for i = before + 1, #D.buffer do lines[#lines + 1] = D.buffer[i] end
  quietChat(function() D:SetEnabled(false) end)
  return lines
end

test("coverage: a stand-up with logging off holds its dependency line, and `debug on` writes it after [Init]", function()
  -- red under: the dependency line on the gated sink (the load-time stand-up runs from OnEnable
  -- with the session-only flag off, so the line never landed: debug-logging-§8, Dependencies).
  local D, savedFlag = NS.DebugLog, NS.State.debug
  NS.State.debug = false
  quietChat(function()
    NS.Schema:Set("settings.enabled", false)
    NS.Schema:Set("settings.enabled", true)
  end)
  local lines = enableAndRead(D)
  NS.State.debug = savedFlag
  local all = table.concat(lines, "\n")
  local initAt, depsAt
  for i, l in ipairs(lines) do
    if not initAt and l:find("[Init] ", 1, true) then initAt = i end
    if l:find("[State] dependencies: price providers: none; latch: LibKa0s-Lifecycle-1.0", 1, true) then
      assertTrue(depsAt == nil, "the held line was written twice:\n" .. all)
      depsAt = i
    end
  end
  assertTrue(depsAt ~= nil, "the held dependency line did not land:\n" .. all)
  assertTrue(initAt ~= nil and initAt < depsAt, "held lines follow the [Init] summary:\n" .. all)
  -- One-shot: a second `debug on` has nothing held to write.
  assertEqual(count(enableAndRead(D), "[State] dependencies: "), 0, "the queue is one-shot")
end)

test("coverage: an event name this client refuses is held for `debug on`, once per name", function()
  -- red under: the [Init] refusal line on the gated sink, which the load-time registrations meet
  -- with logging off. The name is client state, so it waits in the at-enable queue.
  local D, savedFlag = NS.DebugLog, NS.State.debug
  NS.State.debug = false
  local rejected = {}
  local target = { RegisterEvent = function() error("refused", 0) end }
  NS.SafeRegisterEvent(target, "LH_COVERAGE_NO_SUCH_EVENT", function() end, rejected)
  NS.SafeRegisterEvent(target, "LH_COVERAGE_NO_SUCH_EVENT", function() end, rejected)
  local lines = enableAndRead(D)
  NS.State.debug = savedFlag
  assertEqual(count(lines, "[Init] event LH_COVERAGE_NO_SUCH_EVENT refused by this client"), 1,
    table.concat(lines, "\n"))
end)

test("coverage: with logging off, an edge builds nothing of the host's and writes nothing", function()
  -- The library builds its own [Lifecycle] line and hands it to the sink, which drops it at the
  -- gate; everything else is the host's, and none of it may reach the sink with logging off.
  local saved, tags = NS.Debug, {}
  NS.Debug = function(tag) tags[#tags + 1] = tostring(tag) end
  NS.State.debug = false
  quietChat(function()
    NS.Schema:Set("settings.enabled", false)
    NS.Schema:Set("settings.enabled", true)
  end)
  NS.Debug = saved
  for _, tag in ipairs(tags) do
    assertEqual(tag, "Lifecycle", "a host line reached the sink with logging off")
  end
  local D, before = NS.DebugLog, #NS.DebugLog.buffer
  quietChat(function()
    NS.Schema:Set("settings.enabled", false)
    NS.Schema:Set("settings.enabled", true)
  end)
  assertEqual(#D.buffer, before, "the real sink wrote a line with logging off")
end)

-- ── refusals, each naming its guard ──────────────────────────────────────────────────────────

test("coverage: while stood down, a hook's stamp, an open and a feature verb each name the guard", function()
  -- red under: dropping the gated line from Attribution:Stamp's stood-down return or from B:Show's
  -- stood-down return, or dropping `debug` from the Slash descriptor (settings/Slash.lua), whose
  -- disabled gate then refuses in chat only. The report is "nothing happened"; each line is the
  -- answer. The [Cmd] line is the library's (Slash minor 18); a host copy would be a second one.
  local live = {}
  for _, v in ipairs(M.LibStub("LibKa0s-Slash-1.0").LIVE_VERBS) do live[v:lower()] = true end
  live.profile = true
  local verb
  for _, entry in ipairs(NS.COMMANDS) do
    if not live[entry[1]] then verb = entry[1]; break end
  end
  assertTrue(verb ~= nil, "NS.COMMANDS carries no feature verb to refuse")
  local lines = whileDisabled(function()
    NS.Attribution:Stamp("VENDOR", nil, "CERTAIN", "vendor-buy")
    NS.Browser:Show()
    NS.Slash:OnSlash(verb)
  end)
  assertEqual(count(lines, "[Attr] stamp VENDOR ignored: stood down"), 1, table.concat(lines, "\n"))
  assertEqual(count(lines, "[UI] open refused: stood down"), 1, table.concat(lines, "\n"))
  assertEqual(count(lines, "[Cmd] refused " .. verb .. ": disabled"), 1, table.concat(lines, "\n"))
  assertEqual(count(lines, "[Cmd]"), 1, "one refusal, one line:\n" .. table.concat(lines, "\n"))
end)

test("coverage: while disabled, a live verb logs no refusal and a typo is the unknown-verb line", function()
  -- A live verb runs; a typo is not the disabled gate's refusal (slash-commands-§3) but the
  -- dispatcher's unknown-verb refusal, its own one line.
  local lines = whileDisabled(function()
    NS.Slash:OnSlash("version")
    NS.Slash:OnSlash("nosuchverb")
  end)
  local all = table.concat(lines, "\n")
  assertEqual(count(lines, "[Cmd] refused nosuchverb: unknown verb"), 1, all)
  assertEqual(count(lines, "[Cmd]"), 1, all)
  assertEqual(count(lines, "[Cmd] refused version"), 0, all)
end)

test("coverage: the library's own lines land in this addon's console, once each", function()
  -- Through the REAL sink and the real buffer, not a stand-in: what a player copies out. A Slash
  -- refusal (Slash minor 18) and a Lifecycle edge (Lifecycle minor 3) each land as exactly one line.
  local D, savedFlag = NS.DebugLog, NS.State.debug
  NS.State.debug = true
  local before = #D.buffer
  local ok, err = pcall(quietChat, function()
    NS.Slash:OnSlash("get")
    NS.Schema:Set("settings.enabled", false)
    NS.Schema:Set("settings.enabled", true)
  end)
  NS.State.debug = savedFlag
  if not ok then error(err, 0) end
  local lines = {}
  for i = before + 1, #D.buffer do lines[#lines + 1] = D.buffer[i] end
  local all = table.concat(lines, "\n")
  assertEqual(count(lines, "[Cmd] refused get: usage"), 1, all)
  assertEqual(count(lines, "[Lifecycle] stood down: added disabled (holds: disabled)"), 1, all)
  assertEqual(count(lines, "[Lifecycle] stood up: released disabled (holds: none)"), 1, all)
  assertEqual(count(lines, "[Cmd]"), 1, all)
end)

test("coverage: an Options combat-lock refusal is the library's one [Cfg] line in this console", function()
  -- red under: dropping `debug` from the Options descriptor (settings/OptionsSetup.lua), which
  -- leaves the combat lock's refusals (Options minor 27) unlogged; or a host line beside it, which
  -- logs the one refusal twice (debug-logging-§4, "The library's own lines"). Through the REAL sink
  -- and buffer, as the Slash and Lifecycle case above. The mock's InCombatLockdown answers true for
  -- the call, so the page's Defaults (O.RestoreDefaults) is refused at the lock and writes nothing.
  local O, D, savedFlag = NS.Options, NS.DebugLog, NS.State.debug
  local pages = O.__pages()
  assertTrue(pages[1] ~= nil and pages[1].key ~= nil, "no Options page to refuse on")
  local pageKey = pages[1].key
  local realCombat = M.InCombatLockdown
  M.InCombatLockdown = function() return true end
  NS.State.debug = true
  local before = #D.buffer
  local ok, err = pcall(quietChat, function() O.RestoreDefaults(pageKey) end)
  M.InCombatLockdown, NS.State.debug = realCombat, savedFlag
  if not ok then error(err, 0) end
  local lines = {}
  for i = before + 1, #D.buffer do lines[#lines + 1] = D.buffer[i] end
  local all = table.concat(lines, "\n")
  assertEqual(count(lines, "[Cfg] defaults " .. tostring(pageKey) .. " refused (in combat)"), 1, all)
  assertEqual(count(lines, "[Cfg]"), 1, "one refusal, one line, no host copy:\n" .. all)
end)

test("coverage: the visibility refusal and the visibility hide name the mode", function()
  -- red under: dropping the [UI] line from B:Show's visibility refusal or from B:ApplyVisibility.
  local s = NS.db.profile.settings
  local saved = s.visibility
  local lines = capture(function()
    quietChat(function()
      s.visibility = "never"
      NS.Browser:Show()
      s.visibility = "always"
      NS.Browser:Show()
      s.visibility = "outOfCombat"
      NS.Browser:ApplyVisibility(true)
    end)
  end)
  s.visibility = saved
  NS.Browser:Hide()
  assertEqual(count(lines, "[UI] open refused: visibility=never"), 1, table.concat(lines, "\n"))
  assertEqual(count(lines, "[UI] window hidden by visibility=outOfCombat (combat=true)"), 1,
    table.concat(lines, "\n"))
end)

test("coverage: a refused schema write is one [Set] line with the seam's reason", function()
  -- red under: dropping traceRefusal from S:Set (settings/Schema.lua). The library prints the
  -- refusal to chat and logs only accepted writes.
  local lines = capture(function() NS.Schema:Set("settings.nosuchthing", 1) end)
  assertEqual(#lines, 1, table.concat(lines, "\n"))
  assertEqual(lines[1], "[Set] settings.nosuchthing rejected: unknown path: settings.nosuchthing")
end)

test("coverage: a currency line refused before it names a currency says why", function()
  -- red under: bare returns for the recordCurrency and unresolved-link guards in
  -- Collector:OnChatMsgCurrency, or running the recordCurrency check before the self-parse (the
  -- first call below is not a self line and must log nothing even with capture off).
  local C, U, Cp = NS.Collector, NS.Util, NS.Compat
  local realParse, realInfo = U.ParseSelfCurrency, Cp.GetCurrencyInfoFromLink
  local lines = capture(function()
    NS.db.profile.settings.recordCurrency = false
    C:RefreshUpvalues()
    C:OnChatMsgCurrency(nil, "not a currency line")
    U.ParseSelfCurrency = function() return "|Hcurrency:0|h[x]|h", 1 end
    C:OnChatMsgCurrency(nil, "anything")
    NS.db.profile.settings.recordCurrency = true
    C:RefreshUpvalues()
    Cp.GetCurrencyInfoFromLink = function() return nil end
    C:OnChatMsgCurrency(nil, "anything")
  end)
  U.ParseSelfCurrency, Cp.GetCurrencyInfoFromLink = realParse, realInfo
  assertEqual(count(lines, "[Drop] currency line reason=recordCurrency-off"), 1, table.concat(lines, "\n"))
  assertEqual(count(lines, "[Drop] currency line reason=unresolved-link"), 1, table.concat(lines, "\n"))
end)

test("coverage: a container use logs only the spell-targeting refusal, never a non-loot item", function()
  -- red under: restoring the per-use [Open] line (a merchant sale or a bag addon's bulk action is
  -- one UseContainerItem per item, debug-logging-§9), or dropping the targeting refusal.
  local Cp = NS.Compat
  local origHas, origTgt = Cp.ContainerItemHasLoot, Cp.IsSpellTargeting
  local lines = capture(function()
    Cp.ContainerItemHasLoot = function() return false end
    for slot = 1, 10 do NS.Attribution:OnContainerItemUse(0, slot) end
    Cp.ContainerItemHasLoot = function() return true end
    Cp.IsSpellTargeting = function() return true end
    NS.Attribution:OnContainerItemUse(0, 1)
  end)
  Cp.ContainerItemHasLoot, Cp.IsSpellTargeting = origHas, origTgt
  assertEqual(#lines, 1, table.concat(lines, "\n"))
  assertEqual(lines[1], "[Open] container use bag=0 slot=1 ignored: spell targeting")
end)

-- ── errors caught, deferred work, data mutations ─────────────────────────────────────────────

test("coverage: a price provider that raises is one [AHPrice] line per distinct error", function()
  -- red under: dropping traceFetchError (the pcall then costs nothing visible at all), or its
  -- DebugOnce gate (the same fault repeats on every kept loot line).
  -- Planted and restored through a table walk, as tests/test_auctionprice.lua's withGlobals does.
  local plant = { Auctionator = { API = { v1 = {
    GetAuctionPriceByItemID = function() error("coverage-boom", 0) end } } } }
  local saved = {}
  for k, v in pairs(plant) do saved[k] = _G[k]; _G[k] = v end
  local ok, lines = pcall(capture, function()
    for _ = 1, 5 do NS.AuctionPrice:GatherAll("|Hitem:1|h[x]|h", 1) end
  end)
  for k in pairs(plant) do _G[k] = saved[k] end
  if not ok then error(lines, 0) end
  assertEqual(count(lines, "[AHPrice] auctionator fetch failed: coverage-boom"), 1, table.concat(lines, "\n"))
end)

test("coverage: the deferred bound repair's end names done or gave up, with the real attempt", function()
  -- red under: the old line, which read the attempt AFTER the clear and so ended every job on
  -- "attempt 0" with no word for whether it finished or gave up.
  local g = NS.db.global
  local savedHistory, savedPending, savedAttempts = g.history, g.boundRepairPending, g.boundRepairAttempts
  local Cp, I = NS.Compat, NS.Item
  local realBind, realLoad = Cp.ItemBindState, I.LoadItem
  local lines = capture(function()
    g.history, g.boundRepairPending, g.boundRepairAttempts = {}, true, nil
    NS.Database:RepairBoundStates()
    Cp.ItemBindState = function() return nil, false end
    I.LoadItem = function() end
    g.history = { { itemID = 1, bound = "BOE" } }
    g.boundRepairPending, g.boundRepairAttempts = true, 9
    NS.Database:RepairBoundStates()
  end)
  Cp.ItemBindState, I.LoadItem = realBind, realLoad
  g.history, g.boundRepairPending, g.boundRepairAttempts = savedHistory, savedPending, savedAttempts
  assertEqual(count(lines, "(attempt 1, done)"), 1, table.concat(lines, "\n"))
  assertEqual(count(lines, "1 pending, 1 candidates (attempt 10, gave up)"), 1, table.concat(lines, "\n"))
end)

test("coverage: a prune with retention Always says it skipped", function()
  local g = NS.db.global
  local saved = g.retentionDays
  local lines = capture(function()
    g.retentionDays = 0
    NS.Database:PruneOld()
  end)
  g.retentionDays = saved
  assertEqual(lines[1], "[Prune] skipped: retention is Always")
end)

test("coverage: a filter-list edit names the act and all three list sizes", function()
  -- red under: the old _notify, which printed two sizes and no act, so an add and a remove
  -- read the same.
  local lines = capture(function()
    NS.Filters:AddBlacklist(987654)
    NS.Filters:RemoveBlacklist(987654)
  end)
  local add, remove = first(lines, "[Filters] add blacklist 987654:"),
    first(lines, "[Filters] remove blacklist 987654:")
  assertTrue(add ~= nil and add:match("blacklist=%d+ whitelist=%d+ currency=%d+$") ~= nil, tostring(add))
  assertTrue(remove ~= nil, table.concat(lines, "\n"))
end)

-- ── quiet steady state (debug-logging-§9) ────────────────────────────────────────────────────

test("coverage: N table repaints with nothing changed log one [Table] line, and a real change logs", function()
  -- red under: dropping the change gate from BrowserTable:Refresh. A coalesced RecordAdded in test
  -- mode, a resize and a no-op HistoryChanged all repaint an identical summary.
  local B, BT = NS.Browser, NS.BrowserTable
  quietChat(function() B:Show() end)
  assertTrue(BT.frame ~= nil, "the History table did not attach")
  local savedSort, savedAsc = BT.sortKey, BT.sortAsc
  local lines = capture(function()
    BT.ResetRenderTrace()
    for _ = 1, 10 do BT:Refresh() end
  end)
  assertEqual(count(lines, "[Table]"), 1, table.concat(lines, "\n"))
  local changed = capture(function() BT:SetSort(BT.sortKey) end)   -- flips the direction
  assertEqual(count(changed, "[Table]"), 1, "a real change must still log: " .. table.concat(changed, "\n"))
  BT.sortKey, BT.sortAsc = savedSort, savedAsc
  BT:Refresh()
  B:Hide()
end)

test("coverage: each open of the History window logs its render once, even when unchanged", function()
  -- red under: dropping ResetRenderTrace from the window's OnShow, which would leave an open that
  -- matches the last summary with no [Table] line at all. The mock's Show does not run OnShow, so
  -- each open fires it first, as the client does from inside f:Show().
  local B = NS.Browser
  quietChat(function() B:Show(); B:Hide() end)   -- the window exists before the first counted open
  local function open()
    B:GetWindow():__fire("OnShow")
    B:Show()
    B:Hide()
  end
  local lines = capture(function() quietChat(function() open(); open() end) end)
  assertEqual(count(lines, "[Table]"), 2, table.concat(lines, "\n"))
end)

test("coverage: N Insights recomputes with nothing changed log one [Insights] line", function()
  -- red under: dropping the change gate from Analytics:Refresh. The live refresh rides every
  -- coalesced RecordAdded while the tab is up, and a loot the filter does not match changes nothing.
  local A = NS.Analytics
  local savedContent, savedCards, savedLayout = A.content, A.UpdateCards, A.Layout
  A.content, A.UpdateCards, A.Layout = A.content or {}, function() end, function() end
  local lines = capture(function()
    A.ResetRenderTrace()
    for _ = 1, 10 do A:Refresh() end
  end)
  A.content, A.UpdateCards, A.Layout = savedContent, savedCards, savedLayout
  assertEqual(count(lines, "[Insights]"), 1, table.concat(lines, "\n"))
end)

test("coverage: a console Clear re-arms the change gates, so the next pass logs over an empty console", function()
  -- red under: a hand-rolled memo in place of the console's DebugOnce / DebugChanged (a file-local
  -- seen-set or last-line string survives a Clear, so the first pass after it writes nothing and
  -- the player copies an empty console). The gates are the console's (DebugLogGates 1), and Clear
  -- re-arms them.
  local plant = { Auctionator = { API = { v1 = {
    GetAuctionPriceByItemID = function() error("rearm-boom", 0) end } } } }
  local saved = {}
  for k, v in pairs(plant) do saved[k] = _G[k]; _G[k] = v end
  local A = NS.Analytics
  local savedContent, savedCards, savedLayout = A.content, A.UpdateCards, A.Layout
  A.content, A.UpdateCards, A.Layout = A.content or {}, function() end, function() end
  local function pass()
    return capture(function()
      NS.AuctionPrice:GatherAll("|Hitem:1|h[x]|h", 1)
      A:Refresh()
    end)
  end
  local ok, err = pcall(function()
    pass()                               -- arms both keys
    local quiet = pass()
    assertEqual(count(quiet, "[AHPrice] auctionator fetch failed: rearm-boom"), 0, table.concat(quiet, "\n"))
    assertEqual(count(quiet, "[Insights]"), 0, table.concat(quiet, "\n"))
    NS.DebugLog:Clear()
    local again = pass()
    assertEqual(count(again, "[AHPrice] auctionator fetch failed: rearm-boom"), 1, table.concat(again, "\n"))
    assertEqual(count(again, "[Insights]"), 1, table.concat(again, "\n"))
  end)
  for k in pairs(plant) do _G[k] = saved[k] end
  A.content, A.UpdateCards, A.Layout = savedContent, savedCards, savedLayout
  if not ok then error(err, 0) end
end)

-- ── the test-mode material effect ────────────────────────────────────────────────────────────

test("coverage: test mode's start, combat stop and refusal are one [Table] line each", function()
  -- red under: dropping traceTestMode (nothing else in the log says the rows are samples) or the
  -- refusal line.
  local BT = NS.BrowserTable
  local savedCombat = M.__inCombat
  local lines = capture(function()
    quietChat(function()
      BT:SetTestMode(true)
      BT:EndTestModeForCombat()
      M.__inCombat = true
      BT:SetTestMode(true)
    end)
  end)
  M.__inCombat = savedCombat
  if BT.testMode then BT:SetTestMode(false) end
  NS.Browser:Hide()
  assertTrue(first(lines, "[Table] test mode on: ") ~= nil, table.concat(lines, "\n"))
  assertEqual(count(lines, "[Table] test mode off (combat started)"), 1, table.concat(lines, "\n"))
  assertEqual(count(lines, "[Table] test mode refused: "), 1, table.concat(lines, "\n"))
end)
