-- tests/test_slash_degraded.lua — settings/Slash.lua's `if not lib` branch, on a real degraded load.
--
-- Split out of tests/test_slash.lua when that file neared the 1100-line split point. Every case
-- here runs against the namespace tests/degraded_env.lua builds: the whole TOC loaded with
-- libs/LibKa0s absent, so each setup file's degradation stub is the one under test, never a
-- hand-written copy. The degraded load calls no InitDB, so the cases that write hand it a store of
-- their own through `degradedNS.db` and take it back afterwards.

local T = _G.LH_TEST
local NS, test, assertTrue, assertEqual = T.NS, T.test, T.assertTrue, T.assertEqual

local degradedNS, lines = dofile("tests/degraded_env.lua")()
local DSl = degradedNS.Slash
-- The degraded printer announces the missing library ONCE, on the first line printed. Spend that
-- here, so a case counting its own lines is not counting the notice for whichever case ran first.
degradedNS.Print("")

--- Run `act` with a fresh store on the degraded namespace and the chat capture emptied. Returns
--- the lines printed and the store. Both are restored however the case ends.
local function withDegradedStore(act, lists)
  local store = {
    settings = { enabled = true },
    blacklist = lists and lists.blacklist or {},
    whitelist = lists and lists.whitelist or {},
    currencyBlacklist = lists and lists.currencyBlacklist or {},
  }
  local savedDb = degradedNS.db
  degradedNS.db = { global = store }
  for i = #lines, 1, -1 do lines[i] = nil end
  local ok, err = pcall(act, store)
  local out = {}
  for i, line in ipairs(lines) do out[i] = line end
  if degradedNS.Lifecycle then degradedNS.Lifecycle:Set(degradedNS.HOLD_DISABLED, false) end
  degradedNS.db = savedDb
  if not ok then error(err, 0) end
  return out, store
end

--- The verbs the degraded help lists, as a set.
local function listedVerbs()
  local listed = {}
  for _, row in ipairs(DSl.HelpRows()) do
    local verb = row:match("^%s*|cFFFFFF00/lh (%S+)|r")
    assertTrue(verb ~= nil, "unparseable help row: " .. tostring(row))
    listed[verb] = true
  end
  return listed
end

--- NS.COMMANDS' handler for `verb` on the degraded namespace.
local function handler(verb)
  for _, entry in ipairs(degradedNS.COMMANDS) do
    if entry[1] == verb then return entry[3] end
  end
  error("no degraded COMMANDS entry for " .. verb, 2)
end

test("library-less install: the Slash under test is the degraded stub", function()
  -- Precondition for every case below: a live Slash here would make them measure the wrong path.
  assertTrue(DSl.HelpHeader():find(NS.LIBKA0S_MISSING, 1, true) == 1,
    "the degraded help header carries the shared cause clause")
end)

-- ── the refusal line (slash-commands-§7) ──────────────────────────────────────────────────────

test("library-less install: the stub's DISABLED_LINE_FORMAT is the library's, byte for byte", function()
  -- slash-commands-§1 allows a library-absent stub exactly one verbatim library string, on
  -- condition a case pins it against the live library.
  T.assertLibraryConstant(DSl.DISABLED_LINE_FORMAT, "LibKa0s-Slash-1.0", "DISABLED_LINE_FORMAT")
end)

test("library-less install: the refusal line names /lh enable, as the library's does", function()
  -- red under: a stub formatting its own copy with "/lh" where the library passes slash .. " enable".
  local live = T.mocks.LibStub("LibKa0s-Slash-1.0").DISABLED_LINE_FORMAT
  assertEqual(DSl.DisabledLine(), live:format(NS.BRAND, "/lh enable"))
  assertEqual(DSl.DisabledLine(), NS.Slash.DisabledLine(), "the degraded and live lines agree")
end)

-- ── the help list is rendered by subtraction ──────────────────────────────────────────────────
--
-- The degraded help SUBTRACTS the verbs that cannot answer on this path from NS.COMMANDS, rather
-- than rendering a second hand-typed list that would drift. Membership is "cannot answer here", not
-- "went through the library": `config` never did, but its handler lands on the Options stub's
-- declining OpenOptionsPanel. slash-commands-§1 wants the list to hold what still WORKS.

test("library-less install: the degraded help omits config, which would only decline", function()
  local listed = listedVerbs()
  assertTrue(not listed.config,
    "`/lh config` reaches a stub that declines on this path, so it must not be advertised")
  -- The verbs that genuinely still work have to survive, or "omit config" is satisfied by a help
  -- list that omits everything -- the failure the subtraction shape exists to make impossible.
  for _, verb in ipairs({ "show", "hide", "toggle", "debug", "test", "purge" }) do
    assertTrue(listed[verb], "the degraded help must still offer /lh " .. verb)
  end
  -- The library-owned half stays out. `set` among them: the degraded CliSet writes only the
  -- enable path, so advertising the verb would promise the whole schema CLI.
  for _, verb in ipairs({ "version", "get", "set", "list", "reset", "resetall", "help" }) do
    assertTrue(not listed[verb], "/lh " .. verb .. " cannot answer with no library")
  end
end)

test("library-less install: the degraded help lists enable and disable, which now work", function()
  -- red under: enable/disable still in UNAVAILABLE_WITHOUT_LIB.
  local listed = listedVerbs()
  assertTrue(listed.enable, "/lh enable works degraded, so the help must offer it")
  assertTrue(listed.disable, "/lh disable works degraded, so the help must offer it")
end)

-- ── enable / disable write through (options-ui-§1 route (a)) ──────────────────────────────────

test("library-less install: /lh disable stores false, stands the addon down, and acks once", function()
  -- red under: the degraded CliSet being the bare `unavailable` stub.
  local out, store = withDegradedStore(function(s)
    local ok, err = pcall(handler("disable"), "")
    assertTrue(ok, "/lh disable must not raise: " .. tostring(err))
    assertEqual(s.settings.enabled, false, "the stored switch is written through the seam")
    assertTrue(degradedNS.IsStoodDown(), "the latch took the disabled hold")
  end)
  assertEqual(#out, 1, "one ack line: " .. table.concat(out, " | "))
  assertEqual(out[1], NS.PREFIX .. " " .. DSl.FormatKV("settings.enabled", "false"))
  assertEqual(store.settings.enabled, false)
end)

test("library-less install: /lh enable reverses /lh disable", function()
  local out = withDegradedStore(function(s)
    handler("disable")("")
    handler("enable")("")
    assertEqual(s.settings.enabled, true, "enable writes true back")
    assertTrue(not degradedNS.IsStoodDown(), "the latch released the disabled hold")
  end)
  assertEqual(#out, 2, "one ack per verb: " .. table.concat(out, " | "))
  assertEqual(out[2], NS.PREFIX .. " " .. DSl.FormatKV("settings.enabled", "true"))
end)

test("library-less install: set on any other path, or a non-bool value, stays unavailable", function()
  local out, store = withDegradedStore(function()
    DSl:CliSet("settings.scale 2")
    DSl:CliSet("settings.enabled maybe")
  end)
  assertEqual(#out, 2)
  for _, line in ipairs(out) do
    assertTrue(line:find("slash command interface is unavailable", 1, true) ~= nil, line)
  end
  assertEqual(store.settings.enabled, true, "a refused value writes nothing")
end)

-- ── resetall (R-14) ───────────────────────────────────────────────────────────────────────────

test("library-less install: resetall clears the id lists and says how many", function()
  -- red under: a stub that clears all three lists and then only prints "unavailable".
  local out, store = withDegradedStore(function() DSl:CliResetAll() end, {
    blacklist = { [101] = true, [102] = true },
    whitelist = { [201] = true },
    currencyBlacklist = {},
  })
  assertEqual(#out, 1, "one line: " .. table.concat(out, " | "))
  assertEqual(out[1], NS.PREFIX
    .. " filters reset (3 ids cleared); other settings need the LibKa0s library.")
  assertEqual(next(store.blacklist), nil)
  assertEqual(next(store.whitelist), nil)
end)

test("library-less install: resetall on one id says id, not ids", function()
  local out = withDegradedStore(function() DSl:CliResetAll() end,
    { currencyBlacklist = { [3008] = true } })
  assertEqual(out[1], NS.PREFIX
    .. " filters reset (1 id cleared); other settings need the LibKa0s library.")
end)

-- ── the diagnostics report (debug-logging-§14) ────────────────────────────────────────────────

test("library-less install: both report forms answer with the library-absent line and nothing else", function()
  -- red under: a `diagnostics` row missing from NS.COMMANDS, which answers with the generic
  -- unavailable line; or a debug word that falls through to the stub's silent Toggle.
  local want = NS.PREFIX .. " /lh diagnostics is unavailable: the LibKa0s library did not load."
  for _, form in ipairs({ "diagnostics", "debug diagnostics" }) do
    local out = withDegradedStore(function() DSl:OnSlash(form) end)
    assertEqual(#out, 1, "/lh " .. form .. " answers on one line: " .. table.concat(out, " | "))
    assertEqual(out[1], want, "/lh " .. form)
  end
  assertEqual(degradedNS.DebugLog:BufferSize(), 0, "no report was written anywhere")
end)

test("library-less install: the degraded help does not offer /lh diagnostics", function()
  -- red under: diagnostics missing from UNAVAILABLE_WITHOUT_LIB. It dispatches, but only to say
  -- the library is missing, and slash-commands-§1 wants this list to hold what still works.
  assertTrue(not listedVerbs().diagnostics, "/lh diagnostics cannot write a report with no library")
end)
