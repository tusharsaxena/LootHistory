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

test("coverage: a stand-down and a stand-up are one [State] line each, naming holds and dependencies", function()
  -- red under: dropping either line from NS.StandDown / NS.StandUp (core/LifecycleSetup.lua). The
  -- latch narrates nothing, so without them a switched-off addon's silence reads exactly like a
  -- broken capture, and a pasted log cannot say which price providers the session had.
  local lines = whileDisabled(function() end)
  assertEqual(count(lines, "[State] stood down"), 1, table.concat(lines, "\n"))
  assertEqual(count(lines, "[State] stood up"), 1, table.concat(lines, "\n"))
  local down = first(lines, "[State] stood down")
  assertTrue(down:find("holds: disabled", 1, true) ~= nil, down)
  assertTrue(down:match("%d+ deferral%(s%) canceled") ~= nil, down)
  local up = first(lines, "[State] stood up")
  assertTrue(up:find("price providers: none", 1, true) ~= nil, up)
  assertTrue(up:find("latch: LibKa0s-Lifecycle-1.0", 1, true) ~= nil, up)
end)

test("coverage: with logging off, an edge builds and writes nothing", function()
  local saved, calls = NS.Debug, 0
  NS.Debug = function() calls = calls + 1 end
  NS.State.debug = false
  quietChat(function()
    NS.Schema:Set("settings.enabled", false)
    NS.Schema:Set("settings.enabled", true)
  end)
  NS.Debug = saved
  assertEqual(calls, 0, "a gated line reached the sink with logging off")
end)

-- ── refusals, each naming its guard ──────────────────────────────────────────────────────────

test("coverage: while stood down, a hook's stamp, an open and a feature verb each name the guard", function()
  -- red under: dropping the gated line from Attribution:Stamp's stood-down return, from B:Show's
  -- stood-down return, or settings/Slash.lua's traceDisabledRefusal. The report is "nothing
  -- happened"; each line is the answer.
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
  assertEqual(count(lines, "[Cmd] /lh " .. verb .. " refused: addon disabled"), 1,
    table.concat(lines, "\n"))
end)

test("coverage: a live verb or a typo while disabled is not logged as a refusal", function()
  local lines = whileDisabled(function()
    NS.Slash:OnSlash("version")
    NS.Slash:OnSlash("nosuchverb")
  end)
  assertEqual(count(lines, "[Cmd]"), 0, table.concat(lines, "\n"))
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
  -- seen-set (the same fault repeats on every kept loot line).
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
