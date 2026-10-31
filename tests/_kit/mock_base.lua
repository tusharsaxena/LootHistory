-- testkit/mock_base.lua — the universal half of every Ka0s addon's WoW-API mock.
--
-- Returns a BUILDER, so each run gets a fresh, isolated environment. An addon's own
-- tests/wow_mock.lua calls this and then overwrites the handful of keys that are genuinely its own
-- (bag APIs, spell APIs, absorb APIs, …). Plain per-key overwrite — no merge machinery, because the
-- builder hands back a fresh table every call and readability is worth more than cleverness here.
--
-- WHAT BELONGS HERE: an API every addon in the collection touches, or would if it grew a window.
-- WHAT DOES NOT: anything only one addon calls. A mock that stubs every addon's APIs for everyone
-- is one more thing every future test has to reason about, and it hides a missing stub behind a
-- neighbor's.
--
-- ── Fidelity rules, which are the whole reason this is one file rather than eight ──────────────
--
-- 1. A stub that silently succeeds is worse than no stub. If production code branches on a return
--    value, the mock must return something a branch can distinguish — not the frame, not nil.
-- 2. Getters used in ARITHMETIC or CONCATENATION must return real numbers and strings.
--    LibKa0s-Options-1.0's scrollbar patch multiplies GetHeight() and concatenates GetName();
--    both raise on a table, and the metatable's blanket "return the frame" would supply
--    exactly that.
-- 3. Anything a test needs to OBSERVE must be recorded, not no-opped. Event registration, script
--    handlers and widget creation order are all load-bearing for at least one suite: a no-op
--    RegisterUnitEvent would let a widened or dropped per-unit filter pass the entire suite.
-- 4. Anything a test needs to DRIVE must be fireable. `__fire` on frames and on AceGUI widgets is
--    what makes the lazy first-OnShow render and the OnValueChanged write path reachable at all.
-- 5. Model the awkward real behavior, not the convenient one. AceDB's copyDefaults merges in place
--    and AceConsole's Embed clobbers a same-named custom Print and Printf — all are reproduced
--    here, because each has already caused a real bug that a friendlier mock would have hidden.
--    A new frame starts shown, as in the client: the hidden default was the convenient one, and it
--    let a frame production never hid pass every "nothing is on screen" assertion (kit 26).
--
-- ── Known divergence, deliberately kept ────────────────────────────────────────────────────────
--
-- `CreateTexture` and `CreateFontString` answer from the metatable and so return the FRAME ITSELF
-- rather than a distinct object. WhatGroup's and KickCD's mocks make distinct objects and treat it
-- as a correctness requirement, and they are right — a font string and its parent are not one
-- object, and the aliasing has already forced a workaround in LibKa0s's own PerfPanel.lua (which
-- records `__label`/`__state` on the button instead of asking the FontString).
--
-- It is kept for now because changing it is not a harness change: AbsorbTracker's tests/perf.lua
-- memoizes frame proxies specifically BECAUSE `bar.valueText` and `bar.statusBar` are the same
-- table, so distinct objects move the api/iter parity figure, and tests/test_display.lua counts
-- Show/Hide calls that currently land on one shared object. Fixing it is a deliberate change with
-- its own test updates and a fresh parity baseline — not something to smuggle into an extraction.
-- A suite that needs distinct, recording regions installs `mock_paint.lua` (opt-in, kit revision 43).

-- ── the recording half ─────────────────────────────────────────────────────────────────────────
--
-- `mock_record.lua` carries the five surveys a suite asserts on -- the registration set, the live
-- timers, the shown frames, the SavedVariables writes and the printed lines -- plus the two fakes
-- the last two are recorded inside. It is a sibling file rather than part of this one because this
-- file sits ON `layout-§1`'s 1500-line cap, and the seam was already there.
--
-- FOUND, NOT CONFIGURED. The kit vendors as one folder into `tests/_kit/`, and this file is
-- `dofile`d by path from a consumer's own `tests/wow_mock.lua`, so the chunk name is the only thing
-- that knows where the folder is; the two known layouts follow it as a fallback for any consumer
-- whose loader rewrites chunk names. A MISSING recorder RAISES rather than degrading, and that is
-- the whole point of the error: a mock with no registry does not fail a stand-down suite, it
-- PASSES it over an empty table, which is worse than having no suite.
local function loadRecorder(name)
  local info = debug and debug.getinfo and debug.getinfo(1, "S")
  local dir = info and tostring(info.source or ""):match("^@(.*[/\\])")
  local tried = {}
  local candidates = { dir and (dir .. name) or nil, "tests/_kit/" .. name, "testkit/" .. name }
  for _, path in ipairs(candidates) do
    local f = io.open(path, "r")
    if f then
      f:close()
      return dofile(path)
    end
    tried[#tried + 1] = path
  end
  error("testkit: " .. name .. " was not found beside mock_base.lua (tried "
    .. table.concat(tried, ", ") .. ") -- the kit vendors as ONE folder, and a half-copied kit has "
    .. "to fail loudly here: without the recorder every stand-down assertion passes over an empty "
    .. "registry", 2)
end
local installRecorders = loadRecorder("mock_record.lua")
local Events = loadRecorder("mock_events.lua")  -- EventRegistry, C_EventUtils, frame __badEvents
local Resize = loadRecorder("mock_resize.lua")  -- the resize grip's surface (revision 33)
local Lines = loadRecorder("mock_lines.lua")    -- Line regions from CreateLine (revision 37)
-- The Ace fakes (revision 47): CallbackHandler through AceAddon, moved out unchanged. AceGUI stays
-- below, inside the builder, because it closes over the frames this file tracks.
local Ace = loadRecorder("mock_ace.lua")
local makeAceTimer, makeAceConsole, makeAceEvent = Ace.makeAceTimer, Ace.makeAceConsole, Ace.makeAceEvent
local makeAceAddon, embedEvents = Ace.makeAceAddon, Ace.embedEvents
local printMixin, printfMixin = Ace.printMixin, Ace.printfMixin

local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = deepcopy(v) end
  return r
end

-- The atlas sizes this kit publishes, and the one table `SetAtlas` reads.
--
-- THESE ARE A FIXTURE, NOT A MEASUREMENT. Nothing here has been read off a client; they are stand-in
-- figures chosen so that art the client draws at different heights answers at different heights here
-- too, which is the only property a geometry assertion can actually rest on. A test must therefore
-- read the figure it expects OUT of this table rather than hard-coding it -- a case pinned to the
-- literal 28 is a case that goes red for the wrong reason the day a real measurement corrects it.
--
-- The two tab families are the reason the table exists at all. `OptionsWidgets.lua`'s row pitch is
-- the UNSELECTED tab art's own height, measured through a probe texture, and the selected art is
-- taller; a fixture that answered one number for both could not fail a selection-invariance
-- assertion, which is how anti-patterns #70 shipped green. The 28/33 pair is the one LibKa0s's own
-- tab suite has used as its stand-in since the strip was written, kept so the two agree.
--
-- It is a single shared table on purpose: that is what "kit-published" means here, and a consumer
-- that needs an atlas the collection has not needed yet adds it in its own tests/wow_mock.lua. A
-- test that mutates it is mutating it for every instance in the process, and owes it a restore.
local ATLAS_SIZES = {
  ["Options_Tab_Left"]          = { 12,  28 },
  ["Options_Tab_Middle"]        = { 20,  28 },
  ["Options_Tab_Right"]         = { 12,  28 },
  ["Options_Tab_Active_Left"]   = { 12,  33 },
  ["Options_Tab_Active_Middle"] = { 20,  33 },
  ["Options_Tab_Active_Right"]  = { 12,  33 },
  ["Options_InnerFrame"]        = { 256, 256 },
  ["Options_HorizontalDivider"] = { 256, 8 },
}

-- A universal frame stub: any PascalCase method is a no-op returning the frame itself; other
-- (lowercase/custom) field access misses through to nil so addon code can stash custom fields.
-- `track`, when given, is the build's frame recorder: every frame this builds is handed to it, so
-- `M.__shownFrames()` and `M.__timers()` can answer over the frames this build actually made
-- rather than over a module-level list that would mix two builds' frames together. Optional,
-- because a consumer's own mock may call the published `M.__stubFrame` (which supplies it) or this
-- function through some older path (which does not, and whose frames are then simply not surveyed).
local function stubFrame(track)
  local f = { __shown = true, __scripts = {} }
  -- Track shown state so IsShown/Toggle behave (a debug console's visibility checkbox reads it).
  -- A new frame starts SHOWN, as `CreateFrame` hands one back in the client (kit revision 26; it
  -- started hidden before, so a stand-down baseline never saw a container nobody hid -- rule 5).
  -- Every other capitalized method still no-ops through the metatable below.
  function f:Show() self.__shown = true; return self end
  function f:Hide() self.__shown = false; return self end
  function f:SetShown(v) self.__shown = not not v; return self end
  function f:IsShown() return self.__shown end
  function f:IsVisible() return self.__shown end

  -- Enabled state, TRACKED rather than no-opped. The metatable below answers any capitalized
  -- call with the frame itself, so `IsEnabled()` came back truthy no matter what SetEnabled was
  -- told -- and an `assertFalse(b:IsEnabled())` could never fail, in this repo or in any
  -- consumer's suite. Same fidelity rule as GetHeight/GetWidth (rule 2: return real values, not
  -- the frame), applied to the one boolean it was missed on. Blizzard's own tab groups mark the
  -- selected tab by DISABLING it, which is what turns this from a gap into a blocker.
  f.__enabled = true
  function f:SetEnabled(v) self.__enabled = not not v; return self end
  function f:Enable() self.__enabled = true; return self end
  function f:Disable() self.__enabled = false; return self end
  function f:IsEnabled() return self.__enabled end

  -- Store handlers instead of discarding them, and expose __fire so a test can drive the lazy
  -- OnShow paths a settings panel depends on (the deferred body render, and the first-OnShow
  -- Defaults-button build — options-ui-§5). A no-op SetScript made those unreachable.
  -- `SetScript("OnUpdate", nil)` is a CANCELLATION, and `M.__timers()` reads exactly this table to
  -- see it. Storing the handler already did that; what is new is that a suite can now ask the
  -- question -- an OnUpdate left armed on a stood-down addon is a per-frame cost that no visible
  -- surface reports, which is why it has its own step in the conformance suite.
  function f:SetScript(name, fn) self.__scripts[name] = fn; return self end
  function f:GetScript(name) return self.__scripts[name] end
  function f:HookScript(name, fn)
    local prev = self.__scripts[name]
    self.__scripts[name] = function(...)
      if prev then prev(...) end
      return fn(...)
    end
    return self
  end
  function f:__fire(name, ...)
    local fn = self.__scripts[name]
    if fn then return fn(self, ...) end
  end

  -- Geometry and naming must return real values, not the frame (fidelity rule 2). Deliberately NOT
  -- defining the setters (SetSize/SetWidth/...): tests spy on those by rawsetting a recorder and
  -- rawsetting nil to restore, which would erase an explicit definition for good.
  function f:GetName() return nil end
  -- GEOMETRY IS RECORDED HERE, AND ANSWERED ONLY WHERE A TEST ASKED FOR IT. `__geomLive` is the
  -- whole opt-in, one word wide. The kit-wide flip, every frame answering what was recorded on it,
  -- was planned from revision 15 and is RETIRED at revision 35: it would churn some 308 consumer
  -- test files to re-test geometry four consumers draw through one library helper (`H.TabStrip`).
  -- The defect it was for, a tab strip whose band moves with the selection (LibKa0s#17-#20), is
  -- pinned where the pitch and band are computed, in LibKa0s's `tests/test_options_tabs.lua`: its
  -- selection-invariance cases arm geometry through an instrumented harness whose two atlas
  -- families answer different heights, so they fail without any flip here. Zero stays the default
  -- answer of an unarmed frame, and an assertion that relies on it is relying on the kit's
  -- contract, not on a stopgap. See docs/api/testkit/version-35-docs.md.
  function f:GetHeight() return (self.__geomLive and self.__geomH) or 0 end
  function f:GetWidth() return (self.__geomLive and self.__geomW) or 0 end

  -- The opt-in, and the ONLY thing that arms a frame. It has to be the test's call and not
  -- production's: `OptionsWidgets.lua` measures its tab pitch by calling `SetAtlas` on a probe
  -- texture it builds itself, so a `SetAtlas` that armed geometry on its own would silently switch
  -- that measurement on in every suite in the collection -- the retired flip, arriving by accident
  -- through a side door. Arm with no arguments and let production dress the frame, or hand it the
  -- two numbers directly; both are the same switch.
  function f:__setGeom(w, h) self.__geomW, self.__geomH, self.__geomLive = w, h, true; return self end

  -- `SetAtlas` RECORDS what it was told, always: the atlas name, and -- when `useAtlasSize` asks for
  -- it, which is the same argument that makes a real texture take the art's dimensions -- the size
  -- the fixture publishes for that art. Recording is unconditional and answering is not, so a test
  -- can assert which art a widget dressed itself in without arming anything, and a test that wants
  -- the measurement live arms the frame first.
  --
  -- An atlas the fixture does not publish leaves the geometry as it found it, because the client
  -- draws nothing for an unknown atlas rather than collapsing the texture to zero; answering 0 there
  -- would be indistinguishable from a frame nobody ever dressed, which is fidelity rule 1's failure
  -- mode rather than fidelity.
  function f:SetAtlas(name, useAtlasSize)
    self.__atlas = name
    local size = ATLAS_SIZES[name]
    if useAtlasSize and size then self.__geomW, self.__geomH = size[1], size[2] end
    return self
  end

  -- Record RegisterUnitEvent's (event -> unit tokens) instead of no-opping it (fidelity rule 3):
  -- an addon that registers per-unit events ONLY for enabled units is only trustworthy if a test
  -- can see exactly which units each frame registered. UnregisterAllEvents is likewise explicit —
  -- the metatable's blanket no-op would leave a disabled unit's registrations visibly in place and
  -- make the gating untestable.
  -- RAW frame:RegisterEvent, recorded for the same reason (revision 22). The metatable below
  -- answered it with the frame and remembered nothing, so an addon whose events sit on a plain
  -- CreateFrame -- which is most of them, and all of the per-unit ones -- had a registration set no
  -- suite could see. That is not a gap in coverage, it is what makes the question "did this addon
  -- actually stop watching, or does it merely decline to react?" unaskable: a handler that early-
  -- returns looks identical from the outside to one that is gone, and the client still walks the
  -- registration list, still builds the argument frame and still enters Lua either way.
  --
  -- `IsEventRegistered` answers from the same table rather than through the metatable, which used
  -- to hand back the frame -- truthy for every event, registered or not.
  f.__frameEvents = {}
  f.__unitEvents = {}
  function f:RegisterEvent(event) self.__frameEvents[event] = true; return self end
  function f:UnregisterEvent(event) self.__frameEvents[event] = nil; return self end
  function f:IsEventRegistered(event) return self.__frameEvents[event] == true end
  function f:RegisterUnitEvent(event, ...) self.__unitEvents[event] = { ... }; return self end
  function f:UnregisterAllEvents() self.__frameEvents, self.__unitEvents = {}, {}; return self end

  setmetatable(f, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then
      return function() return f end
    end
    return nil
  end })
  if track then track(f) end
  return f
end

return function()
  local M = {}

  -- Every frame this build made, weak-keyed so a frame nobody holds is not kept alive by the
  -- survey, and numbered in creation order so `M.__shownFrames()` and `M.__registrations()` can be
  -- sorted into an order a suite may assert on. `pairs` order is not an order: a suite that
  -- asserted on one would pass or fail on somebody else's hash seed.
  local frameSet, frameSeq = setmetatable({}, { __mode = "k" }), 0
  local function trackFrame(f)
    frameSeq = frameSeq + 1
    f.__seq = frameSeq
    Events.decorateFrame(M, f)
    Resize.decorateFrame(f)
    Lines.decorateFrame(f)
    frameSet[f] = true
    return f
  end
  local function newFrame() return stubFrame(trackFrame) end

  -- Exposed so an addon's own mock can build extra frame-shaped objects (GameTooltip stand-ins,
  -- StopwatchFrame, …) without duplicating the stub. It hands back a TRACKED frame, so a stand-in
  -- an addon's own mock builds is surveyed exactly like one this file built -- otherwise the one
  -- frame a consumer had to make for itself would be the one frame its stand-down suite cannot see.
  M.__stubFrame = newFrame
  M.__deepcopy  = deepcopy
  -- Published, not private: a consumer's suite reads the height it expects out of this rather than
  -- restating it, and a consumer that needs an atlas nobody has needed yet adds the entry here.
  M.__atlasSizes = ATLAS_SIZES

  -- ── time / string ────────────────────────────────────────────────────────────────────────
  M.__now = 0
  M.time = os.time
  M.date = os.date
  M.GetTime = function() return M.__now end
  M.format = string.format
  -- Millisecond CPU clock backing the perf brackets (LibKa0s-Perf-1.0). Driven off a settable
  -- counter rather than a real clock so a test can assert on EXACT bucket totals — a wall-clock
  -- reading would make every timing assertion flaky. Tests advance it via M.__profileMs.
  M.__profileMs = 0
  M.debugprofilestop = function() return M.__profileMs end
  M.wipe = function(t) if type(t) == "table" then for k in pairs(t) do t[k] = nil end end return t end
  M.tinsert = table.insert
  M.tremove = table.remove
  -- `strsplit` and `strtrim` are deliberately absent. Neither consumer of this kit calls them, and a
  -- hand-rolled reimplementation of a WoW string function that nothing exercises is a subtly-wrong
  -- shared helper waiting to be adopted. The addon that first needs one adds it to its own extender
  -- with a test, and it graduates here once a second addon wants the same behavior.


  -- ── unit / world ─────────────────────────────────────────────────────────────────────────
  M.__unitExists = { player = true, target = false, focus = false }
  M.UnitExists = function(unit) return M.__unitExists[unit] == true end
  M.InCombatLockdown = function() return false end
  M.GetLocale = function() return "enUS" end

  -- Capture-context lookups (LibKa0s-Perf-1.0). Settable so a test can assert the recorded context
  -- is the character's rather than a hard-coded string.
--
  -- Class lives here too, and `UnitClass` reads it rather than returning a literal: the localized
  -- NAME and the uppercase TOKEN are different strings, and a stub that returned the token for both
  -- let a context field silently render as "?" in every test that claimed to cover it. Repos whose
  -- suites assert on a particular class override these two fields in their own extender.
  M.__context = {
    name = "Testchar", realm = "Testrealm", level = 80,
    class = "Mage", classToken = "MAGE",
    spec = "Blood", zone = "Silvermoon City", subZone = "Falconwing Square",
    inInstance = false, instanceType = "none", inGroup = false, inRaid = false, groupSize = 0,
  }
  M.UnitClass = function() return M.__context.class, M.__context.classToken end
  M.UnitName = function() return M.__context.name end
  M.GetRealmName = function() return M.__context.realm end
  M.UnitLevel = function() return M.__context.level end
  M.GetZoneText = function() return M.__context.zone end
  M.GetSubZoneText = function() return M.__context.subZone end
  M.GetSpecialization = function() return 1 end
  M.GetSpecializationInfo = function() return 250, M.__context.spec end
  M.IsInInstance = function() return M.__context.inInstance, M.__context.instanceType end
  M.IsInRaid = function() return M.__context.inRaid end
  M.IsInGroup = function() return M.__context.inGroup end
  M.GetNumGroupMembers = function() return M.__context.groupSize end
  M.__inCombat = false
  M.UnitAffectingCombat = function() return M.__inCombat end

  -- NOTE: `C_AddOns` is deliberately NOT stubbed here.
  --
  -- It is the target of every addon's Compat metadata shim, and those shims are tested by swapping
  -- `_G.C_AddOns` to nil to drive the deprecated-global fallback branch. The loader env resolves
  -- mocks BEFORE _G, so a base-level stub would shadow the swap and make the fallback branch
  -- unreachable — silently, as three passing-then-failing cases in AbsorbTracker's test_compat
  -- demonstrated. An addon (or LibKa0s itself, for a perf record's `interface` field) stubs it in
  -- its own extender, where the addon's own tests can see and manage it.

  -- Blizzard's stopwatch, which a perf run drives as its visible arm indicator. Universal because
  -- every addon in the collection vendors the whole LibKa0s folder, Perf included.
  --
  -- Recorded as an ORDERED LOG rather than as counters: which of clear/play/pause fired, and in what
  -- order, is the only observable difference between an armed window and a recording one. Counters
  -- would report the same totals for a correct run and one that played before it cleared.
  M.__stopwatch = {}
  local function sw(action) return function() M.__stopwatch[#M.__stopwatch + 1] = action end end
  M.Stopwatch_Clear, M.Stopwatch_Play, M.Stopwatch_Pause = sw("clear"), sw("play"), sw("pause")
  M.StopwatchFrame = newFrame():Hide()   -- hidden until opened, as in the client (kit 26)

  -- ── UI ───────────────────────────────────────────────────────────────────────────────────
  M.UIParent = newFrame()
  -- The ARGUMENTS are recorded, not discarded (fidelity rule 3). A frame's global name is
  -- load-bearing in real code and not merely decorative: UIPanelScrollFrameTemplate derives its
  -- scrollbar children's names from its parent's, and UISpecialFrames is a list of global NAMES,
  -- so "did this frame get the name it needs" is a question a suite has to be able to ask. It
  -- could not, and a copy window shipped for five versions with the answer unpinned.
  --
  -- Recorded on the frame rather than returned through GetName(), which stays nil-answering:
  -- LibKa0s-Options-1.0's scrollbar patch CONCATENATES GetName(), and handing it a real string
  -- would change a code path rather than observe one.
  M.CreateFrame = function(frameType, name, parent, template)
    local f = newFrame()
    f.__frameType, f.__name, f.__parent, f.__template = frameType, name, parent, template
    return f
  end
  M.UISpecialFrames = {}
  M.DEFAULT_CHAT_FRAME = newFrame()
  M.StaticPopupDialogs = {}
  M.StaticPopup_Show = function() end
  M.GameTooltip = newFrame():Hide()      -- hidden until something owns it, as in the client
  M.hooksecurefunc = function() end
  M.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
  M.PlaySound = function() end

  -- Record the canvas frames as they are registered. This is the only public seam a test has for
  -- reaching the real page panels built by an addon's settings pages, which is what makes it
  -- possible to fire their OnShow and exercise the genuine deferred render.
  M.__mainPanel     = nil
  M.__subcategories = {}   -- [displayName] = panel frame
  -- Blizzard's settings WINDOW, distinct from the Settings registration API below. Present rather
  -- than absent, and its Close is RECORDED (fidelity rule: anything a test needs to observe must
  -- be observable): a panel's combat guard closes this window, and the only thing distinguishing
  -- that from a guard which merely printed is seeing the close land. Left nil, the branch is
  -- unreachable and the case passes either way.
  M.__settingsClosed = 0
  M.SettingsPanel = newFrame():Hide()    -- closed until opened, as in the client
  function M.SettingsPanel:Close() M.__settingsClosed = M.__settingsClosed + 1 end

  M.Settings = {
    RegisterCanvasLayoutCategory = function(panel)
      M.__mainPanel = panel
      return { GetID = function() return 1 end }
    end,
    RegisterCanvasLayoutSubcategory = function(_parent, panel, name)
      M.__subcategories[name] = panel
      return {}
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
  }

  -- ── LibStub + the Ace fakes ──────────────────────────────────────────────────────────────
  local libs = {}
  -- Exposed so an addon's own mock can register additional library fakes (AceDBOptions,
  -- AceConfigDialog, LibSharedMedia) without reaching through LibStub's closure.
  M.__libs = libs

  -- The event half's recorder, fresh per build and shared by NewAddon and AceEvent:Embed below:
  -- [target] = { [event] = handler or true }. Weak-keyed, so a target nobody holds is not kept.
  local eventRegistry = setmetatable({}, { __mode = "k" })

  -- Event names this fake client does not know. Registering one raises on its first registrant,
  -- as retail does (revision 17; see makeAceEvent). Read at call time, so a test may swap the table.
  M.__badEvents = {}

  -- AceEvent-3.0: both CallbackHandler registries (makeAceEvent, above). A no-op Embed would hide
  -- the whole (message, target) clobber class of bug (architecture-§4): the real lib keys callbacks
  -- by (message, target) through one shared registry, so a SendMessage on any embedded object fans
  -- out to every target that registered that message, and two receivers on ONE target overwrite
  -- each other. Fresh per build for isolation.
  local AceEvent, eventBuild = makeAceEvent(M, eventRegistry)
  libs["AceEvent-3.0"] = AceEvent
  -- Published harness seams: the message registry, and a game event fired the way AceEvent's own
  -- frame fires one -- to every target registered for it, as `handler(event, ...)` or
  -- `target[method](target, event, ...)`. Answers how many handlers ran.
  M.__msgRegistry = AceEvent.messages.events
  M.__fireEvent = function(event, ...) return eventBuild.events:fire(event, ...) end

  -- Revision 16's NewAddon, kept for a caller that passes no name (divergence 1 in makeAceAddon).
  local function legacyNewAddon(target)
    local noop = function() end
    -- AceEvent's event half, recorded -- the same three functions an `AceEvent:Embed` target gets
    -- (see embedEvents above).
    embedEvents(target, eventRegistry, eventBuild)
    target.RegisterChatCommand = noop
    target.ScheduleTimer = function(_, fn, delay)
      local timer = { fn = fn, delay = delay }
      M.__timers[#M.__timers + 1] = timer
      return timer
    end
    target.ScheduleRepeatingTimer = function() return {} end
    -- Honored since the 2026-09-12 review: the handle is the queue entry, so marking it is what
    -- makes __fireTimers skip it.
    target.CancelTimer = function(_, handle)
      if type(handle) == "table" then handle.cancelled = true end
    end
    -- Faithfully mirror AceConsole-3.0's Embed: its mixins are :Print AND :Printf, stamped onto
    -- the addon object and clobbering any same-named custom NS.Print or NS.Printf. Called as
    -- `NS.Print(msg)`, AceConsole treats the message as `self` and renders "|cff33ff99<msg>|r:" —
    -- green, trailing colon, no tag. The addon must reclaim BOTH after NewAddon; reproducing the
    -- clobber here lets the tests exercise the real production print path instead of a clean one
    -- the client never uses.
    target.Print = printMixin
    target.Printf = printfMixin
    return target
  end
  libs["AceAddon-3.0"] = makeAceAddon(M, legacyNewAddon)

  -- AceGUI-3.0. Without this the options toolkit's widget makers all return early and the schema →
  -- widget translation layer is untestable. Widgets here are inert data recorders rather than
  -- frames: they remember what was set on them and, crucially, expose __fire so a test can drive
  -- the OnValueChanged / OnMouseUp / OnValueConfirmed callbacks the way a real click would — which
  -- is what exercises the read → write → refresh loop.
  --
  -- `aceGUI` is declared here and built below, so a widget's `:Release()` can reach it.
  local aceGUI
  -- CheckBox check texture, pooled: AceGUI pools the FRAME not the widget table, which is what
  -- OptionsWidgets.lua's choiceFill needs its OnRelease vertex-color fix to be observable against.
  local checkTexturePool = {}
  local function newCheckTexture()
    local tex = { vertexColor = { 1, 1, 1 } }
    function tex:SetTexture(path) self.texturePath = path end function tex:SetVertexColor(r, g, b) self.vertexColor = { r, g, b } end
    function tex:GetVertexColor() local c = self.vertexColor return c[1], c[2], c[3] end return tex
  end
  local function makeWidget(wtype)
    local w = {
      type      = wtype,
      children  = {},
      callbacks = {},
      -- AceGUI's documented per-widget scratch table, cleared in place by Release.
      userdata  = {},
      frame     = newFrame(),
    }
    -- WidgetBase.Release: the method form of AceGUI:Release, which correct code may call instead.
    function w:Release() return aceGUI:Release(self) end
    function w:SetLabel(v) self.labelText = v; return self end
    function w:SetText(v) self.text = v; return self end
    -- AceGUI's EditBox answers what is typed, so a button beside it can read the box (revision 20).
    function w:GetText() return self.text end
    -- A CheckBox's radio look, and an EditBox asked to hide its own Okay button (revision 20).
    function w:SetType(v) self.checkType = v; return self end
    function w:DisableButton(v) self.buttonDisabled = v and true or false; return self end
    function w:SetValue(v) self.value = v; return self end
    function w:GetValue() return self.value end
    function w:SetList(items, order) self.list, self.order = items, order; return self end
    function w:SetColor(r, g, b, a) self.color = { r = r, g = g, b = b, a = a }; return self end
    function w:SetHasAlpha(v) self.hasAlpha = v; return self end
    function w:SetDisabled(v) self.disabled = v and true or false; return self end
    function w:SetSliderValues(mn, mx, st) self.min, self.max, self.step = mn, mx, st; return self end
    function w:SetIsPercent(v) self.isPercent = v; return self end
    function w:SetWidth(v) self.width = v; return self end
    function w:SetHeight(v) self.height = v; return self end
    function w:SetRelativeWidth(v) self.relativeWidth = v; return self end
    function w:SetFullWidth(v) self.fullWidth = v and true or false; return self end
    function w:SetLayout(v) self.layout = v; return self end
    function w:SetAutoAdjustHeight(v) self.autoAdjustHeight = v; return self end
    function w:SetImage(...) self.image = { ... }; return self end
    function w:SetImageSize(...) self.imageSize = { ... }; return self end
    function w:SetMaxLetters(v) self.maxLetters = v; return self end
    function w:SetCallback(name, fn) self.callbacks[name] = fn; return self end
    function w:AddChild(child) self.children[#self.children + 1] = child; return self end
    function w:ReleaseChildren() self.children = {}; return self end
    function w:DoLayout() self.layoutCount = (self.layoutCount or 0) + 1; return self end
    -- AceGUI invokes a callback as fn(widget, eventName, ...); mirror that exactly, because the
    -- makers destructure it as function(_, _, value).
    function w:__fire(name, ...)
      local fn = self.callbacks[name]
      if fn then return fn(self, name, ...) end
    end

    if wtype == "ScrollFrame" then
      -- The always-shown-scrollbar patch reaches into these three by name and does real work with
      -- them.
      w.scrollbar   = newFrame()
      w.scrollframe = newFrame()
      w.content     = newFrame()
      w.content.original_width = 400
      w.localstatus = { offset = 0 }
      function w:FixScroll() self.fixScrollCount = (self.fixScrollCount or 0) + 1 end
      function w:MoveScroll(v) self.movedTo = v end
      function w:SetScroll(v) self.scrolledTo = v end
    elseif wtype == "CheckBox" then
      local tex = table.remove(checkTexturePool); if tex then tex.texturePath = nil else tex = newCheckTexture() end
      w.check = tex
    end
    return w
  end

  aceGUI = {
    -- Populated by RegisterWidgetType. Empty by default, which models
    -- AceGUI-3.0-SharedMediaWidgets being absent: a dropdown maker asks GetWidgetVersion about
    -- LSM30_* and falls back to a plain Dropdown when it comes back nil.
    WidgetRegistry   = {},
    __widgetVersions = {},
    -- AceGUI:RegisterLayout's table, keyed by the upper-cased name (revision 17).
    LayoutRegistry   = {},
  }
  -- The version table under its real name as well (revision 17). The SAME table, not a copy: the
  -- kit has always kept it as `__widgetVersions`, and a host that reads AceGUI's own field --
  -- ConsumableMaster's fake grew one for exactly that -- must see what RegisterWidgetType wrote.
  aceGUI.WidgetVersions = aceGUI.__widgetVersions
  function aceGUI.RegisterLayout(_, name, fn)
    assert(type(fn) == "function")
    if type(name) == "string" then name = name:upper() end
    aceGUI.LayoutRegistry[name] = fn
  end
  function aceGUI.GetLayout(_, name)
    if type(name) == "string" then name = name:upper() end
    return aceGUI.LayoutRegistry[name]
  end
  -- Every widget this factory hands out, in creation order. Harness-side only — no production code
  -- knows it exists. It is the only way a test can reach a widget on a page whose ctx the toolkit
  -- keeps private, which is why a button's onClick once shipped unreachable and therefore untested.
  aceGUI.__created = {}
  function aceGUI:Create(wtype)
    local ctor = self.WidgetRegistry[wtype]
    local w = ctor and ctor() or makeWidget(wtype)
    self.__created[#self.__created + 1] = w
    M.__aceguiNote(w, wtype, 1)   -- mock_record.lua's live-widget survey (revision 26)
    return w
  end
  function aceGUI:GetWidgetVersion(wtype) return self.__widgetVersions[wtype] end
  function aceGUI:RegisterWidgetType(wtype, ctor, version)
    self.WidgetRegistry[wtype]   = ctor
    self.__widgetVersions[wtype] = version
  end

  -- AceGUI:Release, in the real one's order (AceGUI-3.0.lua): guarded against a release reached
  -- from inside its own release, the frame hidden, "OnRelease" fired while the widget still has its
  -- children and its callbacks, the children released, the widget's own :OnRelease() run, and only
  -- then the widget wiped: `userdata` and the callbacks cleared in place, so a widget handed back
  -- cannot fire a stale handler or carry stale data; the size fields the real one nils (`width`,
  -- `height`, `relWidth`, `relHeight`, `noAutoHeight`, plus `relativeWidth`, this fake's recorder
  -- for SetRelativeWidth) dropped; the frame's points cleared and its parent reset to UIParent.
  -- LibKa0s's OptionsWidgets.lua relies on that order: it hides its band texture from an OnRelease
  -- callback. On top of the real behavior sits the recorder a test needs and the client does not:
  -- `w.__released = true`, and `AceGUI.__released` listing every widget taken back, in order.
  --
  -- Two differences, both deliberate. The real one parks the widget in a pool a later `Create` may
  -- hand back; this factory never reuses a widget, so a `Create` after a Release is always fresh.
  -- And the children go through the widget's own `ReleaseChildren`, which on a widget from this
  -- factory forgets them rather than releasing each one: making it release them is a change to
  -- every re-rendering panel in the collection, and a revision of its own.
  --
  -- Two raises, both as in the client (fidelity rule 1). `nil` raises on the first index. A second
  -- Release of the same widget raises "Attempt to Release Widget that is already released", which
  -- the real one raises from delWidget at its END, after re-running the steps above; because this
  -- factory never reuses a widget, the fake can tell at the top and raises before touching it.
  aceGUI.__released = {}
  function aceGUI:Release(widget)
    if widget.isQueuedForRelease then return end
    if widget.__released then error("Attempt to Release Widget that is already released", 2) end
    widget.isQueuedForRelease = true
    if widget.frame then widget.frame:Hide() end
    if widget.__fire then widget:__fire("OnRelease") end
    if widget.ReleaseChildren then widget:ReleaseChildren() end
    if widget.OnRelease then widget:OnRelease() end
    for _, bag in ipairs({ widget.userdata, widget.callbacks }) do
      if type(bag) == "table" then
        for k in pairs(bag) do bag[k] = nil end
      end
    end
    widget.width, widget.height, widget.relativeWidth = nil, nil, nil
    widget.relWidth, widget.relHeight, widget.noAutoHeight = nil, nil, nil
    if widget.frame then
      widget.frame:ClearAllPoints()
      widget.frame:SetParent(M.UIParent)
    end
    widget.__released = true
    M.__aceguiNote(widget, nil, -1)
    self.__released[#self.__released + 1] = widget
    widget.isQueuedForRelease = nil
    if widget.type == "CheckBox" and widget.check then checkTexturePool[#checkTexturePool + 1] = widget.check end
  end
  M.__makeAceGUIWidget = makeWidget
  libs["AceGUI-3.0"] = aceGUI

  -- Real surfaces since revision 17 (makeAceTimer, makeAceConsole, above). Until then both Embeds
  -- returned the target untouched, so only the NewAddon target ever had a timer or a printer.
  local aceTimerLib = makeAceTimer(M)
  libs["AceTimer-3.0"] = aceTimerLib
  libs["AceConsole-3.0"] = makeAceConsole(M)

  -- LibStub. The Ace libraries are fakes looked up from `libs`; vendored LibKa0s modules register
  -- for real through NewLibrary, exactly as they do in the client.
  --
  -- STRICT about the silent flag, matching the real LibStub. A lookup table that never raised meant
  -- `LibStub("LibKa0s-Options-1.0")` — written WITHOUT `, true` — resolved to nil headlessly and
  -- passed the whole suite green, then hard-errored in the client in exactly the install the
  -- degradation stubs exist to protect. Every soft-optional lookup passes `, true`; a missing one
  -- is a bug, and this is the only thing that can say so.
  local minors = {}
  M.LibStub = setmetatable({
    GetLibrary = function(_, major, silent)
      if libs[major] == nil and not silent then
        error("Cannot find a library instance of " .. tostring(major))
      end
      return libs[major], minors[major]
    end,
    NewLibrary = function(_, major, minor)
      minor = tonumber(minor)
      if minors[major] and minors[major] >= minor then return nil end
      libs[major] = libs[major] or {}
      minors[major] = minor
      return libs[major], minors[major]
    end,
  }, { __call = function(self, major, silent) return self:GetLibrary(major, silent) end })

  -- LAST, and after every fake it reads. The recorder takes this build's internals by reference --
  -- the frame set, the two CallbackHandler registries, the LibStub registry and the AceTimer fake
  -- -- because the surveys have to answer over the LIVE tables rather than over copies taken at
  -- build time: a copy would report the registration set as it was when the mock was made, which
  -- is the one moment nobody is asking about.
  installRecorders(M, {
    frames   = frameSet,
    libs     = libs,
    events   = eventBuild.events,
    messages = AceEvent.messages,
    aceTimer = aceTimerLib,
  })
  Events.install(M)

  return M
end
