-- tests/test_diagnostics.lua — this addon's half of the diagnostics report (debug-logging-§14).
--
-- The dispatcher contract (both forms, while disabled, append, ungated, the markers, `diag` not
-- running it) is the kit's shared case, tests/_kit/test_diagnostics_contract.lua, wired through
-- Kit.diagnostics in tests/run.lua. What the library writes around the sections is LibKa0s's own
-- suite. What is left, and lives here, is what only this addon knows: which sections it writes,
-- what each one says, that none of them reaches an API the report must not touch, and that the
-- rules STD-19 names for a host (a raising section, an over-cap report, a secret value) hold
-- against THIS addon's sections rather than against a fixture.

local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local BRAND = "Ka0s Loot History"

--- The report as plain strings, built without writing anything (LIB-02).
local function build(spec)
  local report = NS.DebugLog:BuildDiagnostics(spec)
  local out = {}
  for i, line in ipairs(report.lines) do out[i] = line[2] end
  return out, report
end

--- The first line holding `needle` (plain find), or nil.
local function find(lines, needle)
  for _, line in ipairs(lines) do
    if line:find(needle, 1, true) then return line end
  end
  return nil
end

--- How many lines hold `needle`.
local function count(lines, needle)
  local n = 0
  for _, line in ipairs(lines) do
    if line:find(needle, 1, true) then n = n + 1 end
  end
  return n
end

--- Run `fn` with the account store swapped for `g`, then put the real one back however it ends.
local function withStore(g, fn)
  local real = NS.db.global
  NS.db.global = g
  local ok, err = pcall(fn)
  NS.db.global = real
  if not ok then error(err, 0) end
end

--- A store shaped like defaults/Global.lua's, deep-copied so a case can bend it freely.
local function freshStore()
  return NS.Util.DeepCopy(NS.defaults.global)
end

local function record(i, over)
  local r = {
    ts = 1700000000 + i, char = "Alt" .. (i % 3) .. "-Realm", classFile = "MAGE",
    itemID = 1000 + i, itemName = "Item " .. i,
    itemLink = "|cff0070dd|Hitem:" .. (1000 + i) .. "::::|h[Item " .. i .. "]|h|r",
    quality = 2 + (i % 3), itemType = "Armor", bound = (i % 2 == 0) and "BOE" or nil,
    quantity = 1, source = (i % 2 == 0) and "KILL" or "CONTAINER",
    confidence = (i % 2 == 0) and "high" or "low", zone = "Dornogal",
    auctionPrice = (i % 4 == 0) and { tsm = { dbmarket = 100 } } or nil,
  }
  for k, v in pairs(over or {}) do r[k] = v end
  return r
end

-- ── the shape ─────────────────────────────────────────────────────────────────────────────

test("diagnostics: the report is bracketed by this addon's brand, and no section fails", function()
  local lines = build()
  assertEqual(lines[1], "==== " .. BRAND .. " diagnostics begin ====")
  assertTrue(lines[#lines]:find("^==== " .. BRAND:gsub("%p", "%%%0") .. " diagnostics end: %d+ line%(s%) ====$") ~= nil,
    "the end marker carries the brand: " .. tostring(lines[#lines]))
  assertEqual(count(lines, "failed:"), 0, "a section raised: " .. tostring(find(lines, "failed:")))
end)

test("diagnostics: every DX-LH section writes its own lead line, in the report's order", function()
  local lines = build()
  local want = {
    "identity:", "patterns:", "lifecycle:", "capture:", "settings:", "auction:", "filters:",
    "attribution:", "history:", "tail:", "bound repair:", "browser:", "launcher:", "pools:",
  }
  local last = 0
  for _, lead in ipairs(want) do
    local at
    for i, line in ipairs(lines) do
      if line:sub(1, #lead) == lead then at = i; break end
    end
    assertTrue(at ~= nil, "no line leads with `" .. lead .. "`")
    assertTrue(at > last, "`" .. lead .. "` is out of order")
    last = at
  end
end)

test("diagnostics: the identity section names the stored and code schema, and account-wide", function()
  local lines = build()
  assertTrue(find(lines, "code v" .. tostring(NS.SCHEMA_VERSION)) ~= nil,
    "the code schema version is printed")
  assertTrue(find(lines, "profile: account-wide") ~= nil,
    "an addon with no profile says account-wide (STD-10)")
end)

-- ── settings ──────────────────────────────────────────────────────────────────────────────

test("diagnostics: a changed setting prints as path = value (default); the always rows print anyway", function()
  local g = freshStore()
  g.settings.qualityThreshold = 4
  withStore(g, function()
    local lines = build()
    assertTrue(find(lines, "settings.qualityThreshold = 4 (1)") ~= nil,
      "a non-default row prints with its default")
    -- The three rows DX-LH names print at their defaults too.
    assertTrue(find(lines, "settings.enabled = true (true)") ~= nil, "enabled is always printed")
    assertTrue(find(lines, "settings.retentionDays = 30 (30)") ~= nil, "retention is always printed")
    assertTrue(find(lines, "settings.auction.enabled = true (true)") ~= nil,
      "the AH switch is always printed")
    -- red under: a walk that prints every row, which buries the one a player changed.
    assertTrue(find(lines, "settings.rowHeight") == nil, "a row at its default is not printed")
  end)
end)

test("diagnostics: the AH section prints the priority cascade and which providers are loaded", function()
  local lines = build()
  local line = find(lines, "auction: priority")
  assertTrue(line ~= nil, "the cascade is printed")
  assertTrue(line:find(NS.Constants.AUCTION_PRIORITY_DEFAULT[1], 1, true) ~= nil,
    "the cascade names its tags: " .. tostring(line))
  assertTrue(find(lines, "auction: providers auctionator=no tsm=no oribos=no") ~= nil,
    "no pricing addon is loaded headless")
end)

-- ── filters ───────────────────────────────────────────────────────────────────────────────

test("diagnostics: a filter list past 40 ids prints the first 40 and says how many more", function()
  local g = freshStore()
  for id = 1, 45 do g.blacklist[id] = true end
  g.whitelist[7] = true
  withStore(g, function()
    local lines, report = build()
    local line = find(lines, "filters: blacklist (45)")
    assertTrue(line ~= nil, "the blacklist is counted")
    assertTrue(table.concat(lines, "\n"):find("(+5 more)", 1, true) ~= nil,
      "the ids past the cap are counted, not printed")
    assertTrue(report.capsHit, "the per-list flag is raised, so the truncated line says so")
    assertTrue(find(lines, "filters: whitelist (1) 7") ~= nil, "a short list prints whole")
    assertTrue(find(lines, "filters: currency blacklist (0) -") ~= nil, "an empty list reads -")
  end)
end)

-- ── history ───────────────────────────────────────────────────────────────────────────────

test("diagnostics: the history summary is aggregate: counts by source, quality, bound, characters", function()
  local g = freshStore()
  for i = 1, 8 do g.history[i] = record(i) end
  withStore(g, function()
    local lines = build()
    assertTrue(find(lines, "history: 8 records") ~= nil, "the total")
    assertTrue(find(lines, "history: by source CONTAINER=4, KILL=4") ~= nil,
      tostring(find(lines, "by source")))
    assertTrue(find(lines, "history: by bound BOE=4, none=4") ~= nil, tostring(find(lines, "by bound")))
    assertTrue(find(lines, "history: 3 distinct characters") ~= nil,
      tostring(find(lines, "distinct characters")))
    assertTrue(find(lines, "history: AH-priced 2 of 8") ~= nil, tostring(find(lines, "AH-priced")))
  end)
end)

test("diagnostics: the tail is the newest 25 records, stored fields only, with no link escapes", function()
  local g = freshStore()
  for i = 1, 30 do g.history[i] = record(i) end
  withStore(g, function()
    local lines = build()
    assertEqual(count(lines, "tail: #"), 25, "exactly the newest 25")
    assertTrue(find(lines, "tail: #30 ") ~= nil, "the newest record is in it")
    assertTrue(find(lines, "tail: #5 ") == nil, "an old one is not")
    assertTrue(find(lines, "Item 30") ~= nil, "a row names its item by its stored name")
    for _, line in ipairs(lines) do
      assertTrue(not line:find("|H", 1, true) and not line:find("|c", 1, true),
        "an escape reached the report: " .. line)
    end
  end)
end)

-- ── capture, rejected events, stood down ──────────────────────────────────────────────────

test("diagnostics: the rejected events `/lh debug events` prints are folded into the report", function()
  local saved = NS.RejectedEvents
  NS.RejectedEvents = { "SOME_RETIRED_EVENT" }
  local ok, err = pcall(function()
    assertTrue(find(build(), "rejected events: SOME_RETIRED_EVENT") ~= nil, "the rejected event is named")
  end)
  NS.RejectedEvents = saved
  if not ok then error(err, 0) end
  NS.RejectedEvents = {}
  assertTrue(find(build(), "rejected events: none") ~= nil, "a healthy client says none")
  NS.RejectedEvents = saved
end)

test("diagnostics: while stood down, the capture section says so instead of printing empty wiring", function()
  NS.Schema:Set("settings.enabled", false)
  local ok, err = pcall(function()
    local lines = build()
    assertTrue(find(lines, "capture: stood down") ~= nil, tostring(find(lines, "capture:")))
    assertTrue(find(lines, "enabled=false") ~= nil, "the stored switch reads false")
    assertTrue(find(lines, "stoodDown=true") ~= nil, "the latch reads down")
  end)
  NS.Schema:Set("settings.enabled", true)
  if not ok then error(err, 0) end
end)

-- ── what the report must not touch (STD-05, DX-LH "Never") ────────────────────────────────

test("diagnostics: the report calls no item, tooltip or keystone API and changes no state", function()
  local C = NS.Compat
  local saved = { gi = C.GetItemInfo, sb = C.ScanBound, cm = _G.C_ChallengeMode,
                  clear = NS.DebugLog.Clear }
  local touched = {}
  C.GetItemInfo = function() touched[#touched + 1] = "GetItemInfo" end
  C.ScanBound = function() touched[#touched + 1] = "ScanBound" end
  _G.C_ChallengeMode = setmetatable({}, { __index = function(_, k)
    touched[#touched + 1] = "C_ChallengeMode." .. tostring(k)
    return function() end
  end })
  NS.DebugLog.Clear = function() touched[#touched + 1] = "Clear" end
  local regsBefore = #M.__registrations()
  local holdsBefore = table.concat(NS.Lifecycle:Holds(), ",")
  local debugBefore = NS.State.debug
  local ok, err = pcall(function() NS.DebugLog:RunDiagnostics() end)
  C.GetItemInfo, C.ScanBound, _G.C_ChallengeMode = saved.gi, saved.sb, saved.cm
  NS.DebugLog.Clear = saved.clear
  if not ok then error(err, 0) end
  -- red under: a history section that resolved names through GetItemInfo, a bound readout that
  -- rebuilt a tooltip, or a keystone line read live instead of from the stored context.
  assertEqual(table.concat(touched, ", "), "", "the report reached an API it must not")
  assertEqual(#M.__registrations(), regsBefore, "the report registered or unregistered something")
  assertEqual(table.concat(NS.Lifecycle:Holds(), ","), holdsBefore, "the report moved a hold")
  assertEqual(NS.State.debug, debugBefore, "the report changed the debug flag")
end)

-- ── STD-19's host cases, against this addon's own sections ────────────────────────────────

test("diagnostics: a raising section costs exactly one line and the sections after it still land", function()
  local F = NS.Filters
  local real = F.SortedIDs
  F.SortedIDs = function() error("boom") end
  local ok, err = pcall(function()
    local lines = build()
    assertEqual(count(lines, "failed:"), 1, "exactly one failure line")
    assertTrue(find(lines, "section filters failed:") ~= nil, tostring(find(lines, "failed:")))
    assertTrue(find(lines, "history:") ~= nil, "a later section still ran")
  end)
  F.SortedIDs = real
  if not ok then error(err, 0) end
end)

test("diagnostics: an over-cap report ends with the truncated line, then the end marker", function()
  local g = freshStore()
  for i = 1, 30 do g.history[i] = record(i) end
  withStore(g, function()
    local lines, report = build({ maxLines = 40 })
    assertTrue(report.capped, "the cap bit")
    assertEqual(#lines, 40, "the report stops at its cap")
    assertTrue(lines[#lines - 1]:find("^truncated: %d+ line%(s%) omitted") ~= nil,
      "the truncated line precedes the end: " .. tostring(lines[#lines - 1]))
    assertTrue(lines[#lines]:find(BRAND .. " diagnostics end:", 1, true) ~= nil, "then the end marker")
  end)
end)

test("diagnostics: a secret value in the stored loot context does not raise the report", function()
  -- Modeled as tests/test_debuglog.lua models one: a table string.format rejects.
  local secret = setmetatable({}, { __concat = function() return "secret-propagated" end })
  local saved = NS.State.lootContext
  NS.State.lootContext = { source = secret, confidence = secret, expires = secret }
  local ok, err = pcall(function()
    local lines = build()
    assertEqual(count(lines, "failed:"), 0, "a section raised on a secret: " .. tostring(find(lines, "failed:")))
    assertTrue(find(lines, "attribution: context") ~= nil, "the context line still lands")
  end)
  NS.State.lootContext = saved
  if not ok then error(err, 0) end
end)

-- ── the dispatcher (the contract suite covers the rest) ───────────────────────────────────

test("diagnostics: the COMMANDS row sits directly after debug", function()
  local at = {}
  for i, entry in ipairs(NS.COMMANDS) do at[entry[1]] = i end
  assertTrue(at.diagnostics ~= nil, "/lh diagnostics is a COMMANDS row")
  assertEqual(at.diagnostics, at.debug + 1, "the report follows the debug verb in help")
end)

test("diagnostics: `/lh debug diagnostics` runs before `/lh debug events` could claim the word", function()
  NS.DebugLog:Clear()
  NS.Slash:OnSlash("debug diagnostics")
  assertTrue(find(NS.DebugLog.buffer, "==== " .. BRAND .. " diagnostics begin ====") ~= nil,
    "the debug word wrote a report")
  -- The topic word stays a topic (debug-logging-§4 MAY): it prints to chat and writes no report.
  NS.DebugLog:Clear()
  NS.Slash:OnSlash("debug events")
  assertFalse(find(NS.DebugLog.buffer, "diagnostics begin") ~= nil, "`debug events` is not the report")
end)
