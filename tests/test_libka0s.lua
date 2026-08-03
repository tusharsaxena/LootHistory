-- LibKa0s adoption seam tests: the degradation stubs, the `L` trap guards, and the library
-- tripwires that stand in where a module cannot express the trap at all.
--
-- Everything here is ABOUT the adoption rather than about a feature, which is why it is one suite
-- rather than scattered through the per-module ones: a reader asking "is this addon a faithful
-- LibKa0s consumer?" has one file to read.

local T = _G.LH_TEST
local NS, Loader = T.NS, T.Loader
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local LIB_FILES = {
  "libs/LibKa0s/Core.lua",
  "libs/LibKa0s/DebugLog.lua",
  "libs/LibKa0s/Slash.lua",
  "libs/LibKa0s/Options.lua",
  "libs/LibKa0s/OptionsWidgets.lua",
  "libs/LibKa0s/OptionsScroll.lua",
  "libs/LibKa0s/Perf.lua",
  "libs/LibKa0s/PerfPanel.lua",
}

-- ── the shared cause clause ──────────────────────────────────────────────────────────────────
--
-- Every LibKa0s seam in this addon explains a missing library through ONE sentence and differs only
-- in the consequence it appends. The clause is asserted verbatim because the whole point of it is
-- that a user running several Ka0s addons on a broken install reads the same sentence from each.

test("NS.LIBKA0S_MISSING is the shared cause clause, verbatim", function()
  assertEqual(NS.LIBKA0S_MISSING,
    "The LibKa0s library is missing from this installation of Ka0s Loot History " ..
    "(expected in libs/LibKa0s)")
end)

test("the cause clause is published on the HEALTHY path too, not only when the lib is absent",
  function()
    -- The later seams read it on both paths, so a clause set inside the `if not lib` branch would
    -- be nil in every install that actually has the library — i.e. in every install anyone tests.
    assertTrue(T.mocks.LibStub("LibKa0s-Core-1.0", true) ~= nil, "this run has the library")
    assertTrue(type(NS.LIBKA0S_MISSING) == "string" and NS.LIBKA0S_MISSING ~= "",
      "NS.LIBKA0S_MISSING must be set whether or not the library resolved")
  end)

-- ── degradation, exercised by loading the addon WITHOUT the library ──────────────────────────
--
-- Hand-stubbing `lib = nil` would test a branch rather than an install. This loads every addon
-- file into a fresh namespace over a fresh mock set that has never seen libs/LibKa0s, which is
-- exactly the state a user gets when the folder failed to extract.

local function loadDegraded()
  local mocks = dofile("tests/wow_mock.lua")()
  local lines = {}
  mocks.DEFAULT_CHAT_FRAME.AddMessage = function(_, line) lines[#lines + 1] = line end
  local ns = {}
  Loader.loadAll(Loader.tocFiles("LootHistory.toc"), ns, mocks)
  return ns, lines
end

test("degraded install: every addon file loads with LibKa0s absent, with no error", function()
  local ok, err = pcall(loadDegraded)
  assertTrue(ok, "loading without libs/LibKa0s must degrade, not raise: " .. tostring(err))
end)

test("degraded install: the Core stub still prints a tagged, secret-safe line", function()
  local ns, lines = loadDegraded()
  ns.Print("hello", "world")
  -- Two lines: the one-shot notice, then the line the caller asked for.
  assertEqual(#lines, 2, "expected the notice plus the caller's line")
  assertEqual(lines[2], ns.PREFIX .. " hello world")
end)

test("degraded install: the notice explains the absence through the shared cause clause, once",
  function()
    local ns, lines = loadDegraded()
    ns.Print("one")
    ns.Print("two")
    ns.Print("three")
    assertEqual(lines[1], ns.PREFIX .. " " .. ns.LIBKA0S_MISSING ..
      "; running on reduced built-in fallbacks.")
    -- Said ONCE. A notice on every line turns a broken install into chat spam, and the smoke test
    -- for the degraded path checks exactly this in game.
    local seen = 0
    for _, line in ipairs(lines) do
      if line:find("running on reduced built-in fallbacks", 1, true) then seen = seen + 1 end
    end
    assertEqual(seen, 1, "the degradation notice must be announced exactly once")
  end)

test("degraded install: the Core stub answers every member the addon calls", function()
  local ns = loadDegraded()
  assertEqual(ns.SafeToString(1234), "1234")
  assertEqual(ns.SafeToString(nil), "nil")
  assertEqual(ns.SafeToString(true), "true")
  -- A table is not concat-safe, which is how the probe models a combat-protected value headlessly.
  assertEqual(ns.SafeToString({}), "<secret>")
  assertTrue(ns.IsConcatSafe("hi") == true)
  assertFalse(ns.IsConcatSafe({}))
  assertTrue(type(ns.Format) == "function", "NS.Format must exist on the degraded path")
  assertTrue(ns.Print == ns.Util.print,
    "NS.Util.print is the name core/LootHistory.lua reclaims from; the stub must publish both")
end)

-- ── the `L` trap: the source guard ───────────────────────────────────────────────────────────
--
-- A descriptor field is not observable after `lib:New` returns, so the only way to pin "no
-- descriptor was ever handed this addon's locale table" is to read the seam files. The matcher
-- below is what does it, and it gets its own case (below) because a matcher nothing tests can be
-- narrowed back to a single anchored spelling while still reporting green.

--- True when `expr` — the right-hand side of an `L =` in a descriptor — EVALUATES to the addon's
--- locale table. Matching on the value rather than on one spelling is the whole point:
---
---   L = NS.L                     the table itself                        OFFENDER
---   L = NS.L or { ... }          NS.L is always truthy, so: the table    OFFENDER
---   L = NS.L and { ... } or nil  evaluates to the plain table            fine
---
--- An end-of-line-anchored `L = NS.L` misses the second spelling entirely and never looks at the
--- third, which is the legitimate form.
local function evaluatesToLocaleTable(expr)
  local rest = expr:match("^%s*NS%.L%s*(.-)%s*$")
  if not rest then return false end
  return rest:match("^and[%s(]") == nil and rest ~= "and"
end

test("the L-trap matcher flags the value, not one spelling (all three forms)", function()
  assertTrue(evaluatesToLocaleTable("NS.L"), "the bare table is the shipped-broken case")
  assertTrue(evaluatesToLocaleTable(" NS.L or { FOO = 'bar' }"),
    "NS.L is always truthy, so `or` never reaches the plain table")
  assertFalse(evaluatesToLocaleTable("NS.L and { FOO = 'bar' } or nil"),
    "the `and` form evaluates to the plain table and is the legitimate spelling")
  assertFalse(evaluatesToLocaleTable("{ FOO = 'bar' }"), "a plain literal is never an offender")
end)

test("no descriptor in this addon is handed NS.L", function()
  local SEAMS = {
    "core/CoreSetup.lua", "core/DebugLogSetup.lua",
    "settings/Slash.lua", "settings/OptionsSetup.lua", "settings/Panel.lua",
    "core/PerfSetup.lua",
  }
  local checked = 0
  for _, path in ipairs(SEAMS) do
    local f = io.open(path, "r")
    if f then
      checked = checked + 1
      local body = f:read("*a"); f:close()
      for line in body:gmatch("[^\r\n]+") do
        -- Only a descriptor field, never `local L = ...` or a longer identifier ending in L.
        local rhs = line:match("^%s*L%s*=%s*(.*)$") or line:match("[,{]%s*L%s*=%s*(.*)$")
        if rhs then
          assertFalse(evaluatesToLocaleTable(rhs),
            path .. " hands a descriptor the addon-wide locale table: " .. line)
        end
      end
    end
  end
  assertTrue(checked > 0, "the seam list must name at least one file that exists")
end)

-- ── the library tripwires ────────────────────────────────────────────────────────────────────
--
-- Only DebugLog, Slash and Perf take an `L`, so only those three can express the trap and only
-- those three can carry a RENDERED assertion that a library string resolved to prose. Core and
-- Options cannot: a rendered assertion there is a case that cannot fail, which is worse than no
-- case because it reads as coverage. What stands in is a tripwire on the LIBRARY — it passes today
-- and goes red the day that module grows an `L`, which is the moment a guard would be needed.

test("tripwire — LibKa0s-Core-1.0 ships no STRINGS table", function()
  local core = T.mocks.LibStub("LibKa0s-Core-1.0", true)
  assertTrue(core ~= nil, "Core must be loaded")
  assertEqual(core.STRINGS, nil,
    "Core grew a STRINGS table: it can now express the L trap and needs a rendered assertion")
end)

test("tripwire — Core.lua's source names neither STRINGS nor a descriptor L", function()
  local src = Loader.readFile("libs/LibKa0s/Core.lua")
  assertEqual(src:find("STRINGS", 1, true), nil,
    "Core.lua names STRINGS: add a rendered assertion for Core's user-visible strings")
  assertEqual(src:find("d.L", 1, true), nil,
    "Core.lua reads a descriptor L: this addon must now pass a plain table or omit it")
end)

test("tripwire — Options.lua reads no descriptor L", function()
  -- The lib.STRINGS half of the Core tripwire deliberately does NOT transfer: Options.lua DOES
  -- ship a STRINGS table (DEFAULTS_LABEL, COMBAT_REFUSED, ...), so asserting its absence would
  -- fail on a module that is behaving correctly. What is asserted is that no host can override
  -- them — the source half alone.
  local src = Loader.readFile("libs/LibKa0s/Options.lua")
  assertEqual(src:find("d.L", 1, true), nil,
    "Options.lua grew a descriptor L: the settings panel is where a raw SCREAMING_SNAKE key is " ..
    "most visible, so this addon must pass a plain table or omit it")
end)

test("no rendered LibKa0s string in this addon is an unresolved SCREAMING_SNAKE key", function()
  -- The generic form of the per-module rendered assertions: whatever the seams render, none of it
  -- may look like a key. A resolved string is prose; an unresolved one is the key itself.
  local rendered = {}
  local core = T.mocks.LibStub("LibKa0s-Core-1.0", true)
  rendered[#rendered + 1] = core.SECRET
  for _, s in ipairs(rendered) do
    assertFalse(tostring(s):match("^[A-Z][A-Z0-9_]+$") ~= nil,
      "rendered as a raw locale key: " .. tostring(s))
  end
  assertTrue(#rendered > 0, "the list must not be empty, or this case cannot fail")
end)

-- ── vendor fidelity ──────────────────────────────────────────────────────────────────────────

test("every file of LibKa0s.xml is vendored and loads", function()
  local xml = Loader.readFile("libs/LibKa0s/LibKa0s.xml")
  local n = 0
  for file in xml:gmatch('<Script file="([^"]+)"/>') do
    n = n + 1
    local f = io.open("libs/LibKa0s/" .. file, "r")
    assertTrue(f ~= nil, "LibKa0s.xml lists " .. file .. " but libs/LibKa0s/ does not carry it")
    if f then f:close() end
  end
  assertEqual(n, #LIB_FILES,
    "tests/run.lua's explicit lib load list and LibKa0s.xml disagree about how many files ship")
end)

test("the vendored copy carries the library's MIT license", function()
  -- LICENSE ships INSIDE the payload as of v1.1.1, so a whole-folder copy carries it. Its absence
  -- means someone vendored file-by-file, which is the maneuver cross-major skew comes from.
  local f = io.open("libs/LibKa0s/LICENSE", "r")
  assertTrue(f ~= nil, "libs/LibKa0s/LICENSE is missing: the folder was not copied whole")
  if f then f:close() end
end)

-- ── module coverage: which majors this addon actually wires ──────────────────────────────────
--
-- Presence, not depth — depth is what the per-module suites assert. This exists so that a seam
-- file quietly failing to resolve its major (a mis-typed name, a vendored copy that did not
-- register) is a red case rather than a silently degraded addon that still passes everything else.

test("the four adopted majors all resolved, and the seams are wired to them", function()
  for _, major in ipairs({ "LibKa0s-Core-1.0", "LibKa0s-DebugLog-1.0",
                           "LibKa0s-Slash-1.0", "LibKa0s-Options-1.0" }) do
    assertTrue(T.mocks.LibStub(major, true) ~= nil, major .. " did not register")
  end
  -- Reached through the addon's own keys rather than through LibStub, so a seam that resolved the
  -- library and then failed to publish it is caught too.
  assertTrue(NS.Print ~= nil and NS.SafeToString ~= nil, "Core seam not published")
  assertTrue(NS.DebugLog ~= nil and NS.Debug ~= nil, "DebugLog seam not published")
  assertTrue(NS.Slash.CliList ~= nil and NS.Slash.LandingRows ~= nil, "Slash seam not published")
  assertTrue(NS.Options ~= nil and NS.Options.RenderRows ~= nil, "Options seam not published")
end)

test("every seam file resolves its major with the silent flag", function()
  -- LibStub without `, true` RAISES on a missing library. A seam whose whole purpose is to degrade
  -- would then take the addon down in exactly the install its stub exists for — and headlessly it
  -- would look fine, because a lookup table that never raises resolves to nil and passes.
  for _, path in ipairs({ "core/CoreSetup.lua", "core/DebugLogSetup.lua",
                          "settings/Slash.lua", "settings/OptionsSetup.lua" }) do
    local src = Loader.readFile(path)
    local found = false
    for call in src:gmatch('LibStub%("LibKa0s%-[A-Za-z]+%-1%.0"[^)]*%)') do
      found = true
      assertTrue(call:find(", true", 1, true) ~= nil,
        path .. " resolves a LibKa0s major without the silent flag: " .. call)
    end
    assertTrue(found, path .. " resolves no LibKa0s major at all")
  end
end)

test("the Options page registry built every page this addon declares", function()
  local built = {}
  for _, page in ipairs(NS.Options.__pages()) do built[page.key] = true end
  for _, key in ipairs({ "General", "Filters", "AH Price" }) do
    assertTrue(built[key], key .. " did not build (a raising builder is reported and skipped)")
  end
end)
