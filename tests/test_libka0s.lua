-- LibKa0s adoption seam tests: the degradation stubs, the `L` trap guards, and the library
-- tripwires that stand in where a module cannot express the trap at all.
--
-- Everything here is ABOUT the adoption rather than about a feature, which is why it is one suite
-- rather than scattered through the per-module ones: a reader asking "is this addon a faithful
-- LibKa0s consumer?" has one file to read.
--
-- With ONE exception, and it is a deliberate one. The five stub-PARITY cases moved out to
-- tests/test_surface_parity.lua in M4-09, because that path is where all nine addons in the
-- collection keep the same gate and a reader looking for it should not have to know which suite a
-- given repo filed it under. What stays here is the degraded install itself -- that every file
-- loads, that the notice is said once, that a bare `/lh` still answers -- which is behavior rather
-- than surface. Both suites build the environment through tests/degraded_env.lua.

local T = _G.LH_TEST
local NS, Loader = T.NS, T.Loader
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local LIB_FILES = {
  "libs/LibKa0s/Core.lua",
  "libs/LibKa0s/Env.lua",
  -- New in v1.55.0: LibKa0s-Compat-1.0. core/Compat.lua wires its GetSpellName.
  "libs/LibKa0s/Compat.lua",
  -- New in v1.41.0 (shipped at v1.40.0): LibKa0s-Lifecycle-1.0, the ONE latch both
  -- "be inert" reasons hold (slash-commands-§7). core/LifecycleSetup.lua resolves it at file load.
  "libs/LibKa0s/Lifecycle.lua",
  -- New in v1.55.0, in XML order: LibKa0s-Bus-1.0 (core/Constants.lua takes its `Catalog`) and
  -- LibKa0s-Schema-1.0 (settings/Schema.lua's runtime).
  "libs/LibKa0s/Bus.lua",
  "libs/LibKa0s/Schema.lua",
  "libs/LibKa0s/Pool.lua",
  "libs/LibKa0s/Item.lua",
  "libs/LibKa0s/Media.lua",
  "libs/LibKa0s/Widgets.lua",
  -- New in v1.48.0: the drag handle PEELS out of Widgets.lua as its own file and its own
  -- LibStub minor. This addon adopts nothing from it -- ConsumableMaster and Aura Master are
  -- the hosts that do -- but the client loads every file of the XML, so the suite must too.
  "libs/LibKa0s/WidgetsDragHandle.lua",
  "libs/LibKa0s/DebugLog.lua",
  -- New in v1.60.0: the diagnostics report, a second file of LibKa0s-DebugLog-1.0 (key 14.1) that
  -- lib:New installs on each instance. Loaded after DebugLog.lua, as the XML orders it.
  "libs/LibKa0s/DebugLogDiagnostics.lua",
  "libs/LibKa0s/Slash.lua",
  -- New in v1.39.0: LibKa0s-Launcher-1.0, the minimap button and the broker plugin as one
  -- object registered twice (launcher-§1). core/LauncherSetup.lua resolves it at file load.
  "libs/LibKa0s/Launcher.lua",
  "libs/LibKa0s/Options.lua",
  -- New in v1.62.0: four peels, each a move with its own minor and no member change -- the page
  -- registry out of Options.lua (OptionsRegistry), the id surface out of OptionsWidgets.lua
  -- (OptionsIds, OptionsIdList) and the combat lock's page chrome out of OptionsTabs.lua
  -- (OptionsCombat). Listed in XML order because the client loads them and the suite must too.
  "libs/LibKa0s/OptionsRegistry.lua",
  "libs/LibKa0s/OptionsWidgets.lua",
  "libs/LibKa0s/OptionsIds.lua",
  "libs/LibKa0s/OptionsIdList.lua",
  -- New in v1.39.0: the tab-strip and page-chrome PEEL out of Options.lua. It adds, removes and
  -- renames no member -- O.TabStrip, O.PageBanner, O.PageHeader, O.SubTabStrip and the eight
  -- O.__ geometry seams all still attach to the same instance under the same names -- so no
  -- caller here changed. It is listed because the client loads it and the suite must too.
  "libs/LibKa0s/OptionsTabs.lua",
  "libs/LibKa0s/OptionsCombat.lua",
  -- New in v1.24.0: the schema COMPOSERS, which settings/Schema.lua calls at file load for its
  -- Master controls block. A file listed in LibKa0s.xml and missing from tests/run.lua's explicit
  -- load list is a file the client loads and the suite does not, so the composers would be nil in
  -- every headless run and present in every real one.
  "libs/LibKa0s/OptionsCompose.lua",
  "libs/LibKa0s/OptionsScroll.lua",
  "libs/LibKa0s/OptionsNav.lua",
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
-- Hand-stubbing `lib = nil` would test a branch rather than an install. tests/degraded_env.lua loads
-- every addon file into a fresh namespace over a fresh mock set that has never seen libs/LibKa0s,
-- which is exactly the state a user gets when the folder failed to extract. It was a local here
-- until M4-09 moved the stub-parity cases into tests/test_surface_parity.lua; two suites need the
-- same environment, and one builder is one thing to keep true.

local loadDegraded = dofile("tests/degraded_env.lua")

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

test("NS.MakeCloseButton hands the library this addon's FOLDER name as the third argument", function()
  -- ANTI-PATTERNS #64, and the one case in this repo that exists for a bug nobody can see. The
  -- target is lib.MakeCloseButton(parent, onClick, addonName) and the wrapper takes two arguments;
  -- a two-argument passthrough still runs, still returns a button, and still passes every other
  -- case here -- the button just draws a multiplication sign forever, because a nil folder name
  -- means no texture path, and a texture that does not load draws nothing and raises nothing.
  --
  -- The FOLDER name specifically: "LootHistory", not the "Ka0s Loot History" title and not the
  -- LootHistory* frame-name prefix. They are three different questions this addon answers with two
  -- strings, and only one of them is a path component.
  local lib = T.mocks.LibStub("LibKa0s-Core-1.0", true)
  assertTrue(lib ~= nil, "LibKa0s-Core-1.0 did not register")
  local stock = lib.MakeCloseButton
  local seenParent, seenClick, seenName
  lib.MakeCloseButton = function(parent, onClick, addonName)
    seenParent, seenClick, seenName = parent, onClick, addonName
    return "button"
  end
  local parent, click = {}, function() end
  local got = NS.MakeCloseButton(parent, click)
  lib.MakeCloseButton = stock

  assertEqual(seenName, "LootHistory")
  assertTrue(seenParent == parent, "the parent frame must be forwarded unchanged")
  assertTrue(seenClick == click, "the OnClick handler must be forwarded unchanged")
  assertEqual(got, "button", "the wrapper must RETURN what the library built; a call site anchors it")
end)

test("every window this addon owns closes through that one wrapper", function()
  -- One wrapper is the point: the History title bar, the export modal and the export copy window
  -- all reach it through B:MakeCloseButton, so the folder name is passed in one place instead of
  -- three call sites remembering. A private lookalike here -- a factory that builds its own button
  -- rather than delegating -- is how this addon shipped a multiplication sign for four releases.
  local src = T.Loader.readFile("modules/Browser.lua")
  assertTrue(src:find("NS.MakeCloseButton(parent, onClick)", 1, true) ~= nil,
    "modules/Browser.lua's B:MakeCloseButton must delegate to the core seam")
  assertTrue(src:find("\\195\\151", 1, true) == nil,
    "no multiplication sign may be drawn here any more; the degraded one lives in core/CoreSetup.lua")
end)

test("degraded install: a bare /lh prints help listing the verbs that still work", function()
  -- slash-commands-§3. It used to fall through the verb walk to the "unavailable" line, which
  -- blacks out the whole command surface in the one install where a user most needs to be told
  -- which commands survived — and six of them do, because they never went through the library AND
  -- their handlers reach nothing that did. `config` is the one that reads like a seventh and is
  -- not: its handler is host-owned, but it calls NS.Panel:Open, which reaches O.OpenOptionsPanel,
  -- a stub on this path. It is asserted ABSENT below for that reason. With the library present a
  -- bare /lh opens the settings panel instead (slash-commands-§3); that is not possible here, so
  -- the stub falls back to this help (the next case pins the fallback).
  local ns, lines = loadDegraded()
  ns.Slash:OnSlash("")
  local body = table.concat(lines, "\n")
  assertTrue(body:find(ns.LIBKA0S_MISSING, 1, true) ~= nil,
    "the help header must still explain WHY through the shared cause clause")
  for _, verb in ipairs({ "show", "hide", "toggle", "debug", "test", "purge" }) do
    assertTrue(body:find("/lh " .. verb, 1, true) ~= nil,
      "a bare /lh must list the host-owned verb " .. verb .. ", which still works: " .. body)
  end
  for _, verb in ipairs({ "list", "get", "set", "reset", "resetall", "version", "config" }) do
    assertTrue(body:find("/lh " .. verb .. "|", 1, true) == nil,
      "a bare /lh must not offer " .. verb .. ", which answers \"unavailable\" on this path")
  end
end)

test("degraded install: bare /lh skips the config verb, which cannot answer here, for help", function()
  -- The stub mirrors Slash minor 11: bare runs the registered `config` verb, else help. But
  -- `config` is registered on this path and only declines (the Options stub), so the stub's
  -- UNAVAILABLE_WITHOUT_LIB set keeps it out of the bare dispatch as it keeps it out of the list.
  -- Whitespace-only input is bare too.
  -- red under: a stub that runs `config` on bare input, which prints the "unavailable" line alone.
  for _, input in ipairs({ "", "   \t " }) do
    local ns, lines = loadDegraded()
    local called = 0
    for i, entry in ipairs(ns.COMMANDS) do
      if entry[1] == "config" then
        ns.COMMANDS[i] = { entry[1], entry[2], function() called = called + 1 end }
      end
    end
    local before = #lines
    ns.Slash:OnSlash(input)
    assertEqual(called, 0, "bare /lh must not run config on this path (input '" .. input .. "')")
    -- The one-shot degradation notice may come first: it is said on the first Print, not at load.
    local header
    for i = before + 1, #lines do
      if lines[i]:find(ns.Slash.HelpHeader(), 1, true) then header = i end
    end
    assertTrue(header ~= nil, "bare /lh prints the degraded help header: " .. table.concat(lines, " | "))
  end
end)

test("degraded install: /lh help prints the same degraded help list", function()
  local ns, lines = loadDegraded()
  local before = #lines
  ns.Slash:OnSlash("help")
  -- The one-shot degradation notice may come first: it is said on the first Print, not at load.
  local header
  for i = before + 1, #lines do
    if lines[i]:find(ns.Slash.HelpHeader(), 1, true) then header = i end
  end
  assertTrue(header ~= nil, "/lh help prints the degraded help header: " .. table.concat(lines, " | "))
  assertEqual(#lines - header, #ns.Slash.HelpRows(), "one row per working verb after the header")
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
    "core/CoreSetup.lua", "core/DebugLogSetup.lua", "core/WidgetsSetup.lua",
    "core/EnvSetup.lua",
    "settings/Slash.lua", "settings/OptionsSetup.lua", "settings/Panel.lua",
    "settings/Schema.lua",
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

test("the nine adopted majors all resolved, and the seams are wired to them", function()
  for _, major in ipairs({ "LibKa0s-Core-1.0", "LibKa0s-Media-1.0", "LibKa0s-DebugLog-1.0",
                           "LibKa0s-Slash-1.0", "LibKa0s-Options-1.0",
                           "LibKa0s-Widgets-1.0", "LibKa0s-Env-1.0",
                           "LibKa0s-Pool-1.0", "LibKa0s-Item-1.0" }) do
    assertTrue(T.mocks.LibStub(major, true) ~= nil, major .. " did not register")
  end
  -- Reached through the addon's own keys rather than through LibStub, so a seam that resolved the
  -- library and then failed to publish it is caught too.
  assertTrue(NS.Print ~= nil and NS.SafeToString ~= nil, "Core seam not published")
  assertTrue(type(NS.Icon) == "function" and type(NS.MediaFont) == "function",
    "Media seam not published")
  assertTrue(NS.DebugLog ~= nil and NS.Debug ~= nil, "DebugLog seam not published")
  assertTrue(NS.Slash.CliList ~= nil and NS.Slash.LandingRows ~= nil, "Slash seam not published")
  assertTrue(NS.Options ~= nil and NS.Options.RenderRows ~= nil, "Options seam not published")
  assertTrue(type(NS.MakeDropdown) == "function" and type(NS.CloseMenu) == "function",
    "Widgets seam not published")
  assertTrue(type(NS.Meta) == "function" and type(NS.Version) == "function"
    and type(NS.Zone) == "function" and type(NS.PlayerMapID) == "function",
    "Env seam not published")
  assertTrue(type(NS.Pool) == "table" and type(NS.Pool.Acquire) == "function",
    "Pool seam not published")
  assertTrue(type(NS.Item) == "table" and type(NS.Item.QualityLabel) == "function",
    "Item seam not published")
end)

test("every seam file resolves its major with the silent flag", function()
  -- LibStub without `, true` RAISES on a missing library. A seam whose whole purpose is to degrade
  -- would then take the addon down in exactly the install its stub exists for — and headlessly it
  -- would look fine, because a lookup table that never raises resolves to nil and passes.
  for _, path in ipairs({ "core/CoreSetup.lua", "core/DebugLogSetup.lua", "core/WidgetsSetup.lua",
                          "core/EnvSetup.lua", "core/PoolSetup.lua", "core/ItemSetup.lua",
                          "core/Constants.lua", "core/Compat.lua",
                          "settings/Slash.lua", "settings/OptionsSetup.lua",
                          "settings/Schema.lua" }) do
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
  -- ONE sub-page since R6: the Filters and AH Price sub-pages are tabs on General's strip now, so
  -- their registrations are gone rather than failing. Asserted as an exact set rather than a
  -- presence check, because a page registered and never removed is invisible to the latter.
  local built = {}
  for _, page in ipairs(NS.Options.__pages()) do built[#built + 1] = page.key end
  assertEqual(table.concat(built, " | "), "General",
    "a raising builder is reported and skipped, and a leftover registration is a page nobody drew")
end)

-- ── degraded Core stub: the minor-8 surface (LK-10, LK-11) ────────────────────────────────────
--
-- The stub mirrors Core minor 8 in one rung each. printer.Format pcalls string.format, so a secret
-- reaching a NUMERIC slot falls back to a joined line instead of raising; the SafeRegister family
-- pcalls the registration with no C_EventUtils front gate and appends a refused name once to the
-- caller's list.

test("degraded install: NS.Format with a secret in a %d slot prints a line and raises nothing",
  function()
    local ns, lines = loadDegraded()
    local ok, err = pcall(ns.Format, "%d rows", {})
    assertTrue(ok, "the degraded NS.Format raised on a secret in a %d slot: " .. tostring(err))
    assertEqual(lines[#lines], ns.PREFIX .. " %d rows <secret>")
    ns.Format("%d rows", 3)
    assertEqual(lines[#lines], ns.PREFIX .. " 3 rows", "a satisfiable format is untouched")
  end)

test("degraded install: the SafeRegister stubs isolate a refused name and record it once",
  function()
    local ns = loadDegraded()
    assertTrue(type(ns.RejectedEvents) == "table", "NS.RejectedEvents must exist on both paths")
    local got = {}
    local target = {
      RegisterEvent = function(_, event)
        if event == "GONE" then error("Attempt to register unknown event \"GONE\"") end
        got[#got + 1] = event
      end,
      RegisterUnitEvent = function(_, event, u1)
        if event == "GONE" then error("Attempt to register unknown event \"GONE\"") end
        got[#got + 1] = event .. ":" .. tostring(u1)
      end,
    }
    local rejected = {}
    assertTrue(ns.SafeRegisterEvent(target, "A", nil, rejected) == true)
    assertTrue(ns.SafeRegisterEvent(target, "GONE", nil, rejected) == false)
    assertTrue(ns.SafeRegisterUnitEvent(target, "GONE", rejected, "player") == false)
    assertTrue(ns.SafeRegisterUnitEvent(target, "U", rejected, "player") == true)
    assertEqual(ns.SafeRegisterEvents(target, { "B", "GONE", "C" }, nil, rejected), 2)
    assertEqual(table.concat(got, ","), "A,U:player,B,C")
    assertEqual(table.concat(rejected, ","), "GONE", "a refused name is appended once")
  end)
