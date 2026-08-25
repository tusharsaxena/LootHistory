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
-- neighbour's.
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
--    and AceConsole's Embed clobbers a same-named custom Print — both are reproduced here, because
--    both have already caused a real bug that a friendlier mock would have hidden.
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
-- memoises frame proxies specifically BECAUSE `bar.valueText` and `bar.statusBar` are the same
-- table, so distinct objects move the api/iter parity figure, and tests/test_display.lua counts
-- Show/Hide calls that currently land on one shared object. Fixing it is a deliberate change with
-- its own test updates and a fresh parity baseline — not something to smuggle into an extraction.

local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = deepcopy(v) end
  return r
end

-- A universal frame stub: any PascalCase method is a no-op returning the frame itself; other
-- (lowercase/custom) field access misses through to nil so addon code can stash custom fields.
local function stubFrame()
  local f = { __shown = false, __scripts = {} }
  -- Track shown state so IsShown/Toggle behave (a debug console's visibility checkbox reads it).
  -- Every other capitalized method still no-ops through the metatable below.
  function f:Show() self.__shown = true; return self end
  function f:Hide() self.__shown = false; return self end
  function f:SetShown(v) self.__shown = not not v; return self end
  function f:IsShown() return self.__shown end
  function f:IsVisible() return self.__shown end

  -- Store handlers instead of discarding them, and expose __fire so a test can drive the lazy
  -- OnShow paths a settings panel depends on (the deferred body render, and the first-OnShow
  -- Defaults-button build — options-ui-§5). A no-op SetScript made those unreachable.
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
  function f:GetHeight() return 0 end
  function f:GetWidth() return 0 end

  -- Record RegisterUnitEvent's (event -> unit tokens) instead of no-opping it (fidelity rule 3):
  -- an addon that registers per-unit events ONLY for enabled units is only trustworthy if a test
  -- can see exactly which units each frame registered. UnregisterAllEvents is likewise explicit —
  -- the metatable's blanket no-op would leave a disabled unit's registrations visibly in place and
  -- make the gating untestable.
  f.__unitEvents = {}
  function f:RegisterUnitEvent(event, ...) self.__unitEvents[event] = { ... }; return self end
  function f:UnregisterAllEvents() self.__unitEvents = {}; return self end

  setmetatable(f, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then
      return function() return f end
    end
    return nil
  end })
  return f
end

return function()
  local M = {}

  -- Exposed so an addon's own mock can build extra frame-shaped objects (GameTooltip stand-ins,
  -- StopwatchFrame, …) without duplicating the stub.
  M.__stubFrame = stubFrame
  M.__deepcopy  = deepcopy

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

  -- Scheduled one-shot timers, recorded so tests can inspect coalescing and fire them on demand.
  M.__timers = {}
  M.__fireTimers = function()
    local due = M.__timers
    M.__timers = {}
    for _, t in ipairs(due) do t.fn() end
  end
  M.C_Timer = {
    After = function(delay, fn) M.__timers[#M.__timers + 1] = { fn = fn, delay = delay } end,
    NewTimer = function(delay, fn)
      local t = { fn = fn, delay = delay, Cancel = function() end }
      M.__timers[#M.__timers + 1] = t
      return t
    end,
  }

  -- ── unit / world ─────────────────────────────────────────────────────────────────────────
  M.__unitExists = { player = true, target = false, focus = false }
  M.UnitExists = function(unit) return M.__unitExists[unit] == true end
  M.InCombatLockdown = function() return false end
  M.GetLocale = function() return "enUS" end

  -- Capture-context lookups (LibKa0s-Perf-1.0). Settable so a test can assert the recorded context
  -- is the character's rather than a hard-coded string.
--
  -- Class lives here too, and `UnitClass` reads it rather than returning a literal: the localised
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
  M.StopwatchFrame = stubFrame()

  -- ── UI ───────────────────────────────────────────────────────────────────────────────────
  M.UIParent = stubFrame()
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
    local f = stubFrame()
    f.__frameType, f.__name, f.__parent, f.__template = frameType, name, parent, template
    return f
  end
  M.UISpecialFrames = {}
  M.DEFAULT_CHAT_FRAME = stubFrame()
  M.StaticPopupDialogs = {}
  M.StaticPopup_Show = function() end
  M.GameTooltip = stubFrame()
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
  M.SettingsPanel = stubFrame()
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

  -- AceDB-3.0 with a WORKING profile surface. A bare {global, profile} stub leaves an addon's
  -- entire `profile` verb untestable: the handler bails at `if not db.SetProfile` before touching a
  -- single subcommand, so a broken switch/copy/delete passes the suite silently. Model enough of
  -- the real lib to exercise it — a named profile store, switch/copy/delete/reset, and the
  -- OnProfileChanged / OnProfileCopied / OnProfileReset callbacks AceDB fires via CallbackHandler.
  libs["AceDB-3.0"] = {
    -- `tbl` is the real signature's first arg: either the STRING name of a global SavedVariables
    -- table (what an addon passes: `AceDB:New("<Addon>DB", ...)`), or an actual table. Resolving it
    -- against `_G` (rather than always starting fresh) is what lets a test seed the global with a
    -- legacy profile and then drive the REAL InitDB path against real AceDB merge-in-place
    -- semantics, instead of only against a bespoke plain table that never triggers them.
    New = function(_, tbl, defaults)
      local sv
      if type(tbl) == "string" then
        sv = _G[tbl]
        if not sv then
          sv = {}
          _G[tbl] = sv
        end
      else
        sv = tbl or {}
      end
      sv.profiles = sv.profiles or {}
      sv.global = sv.global or {}

      local db = {}
      local current, callbacks = "Default", {}

      -- Faithful (if simplified) copy of AceDB-3.0's copyDefaults: recurse into every TABLE-valued
      -- default, creating the dest sub-table if it is missing, but only ever fill a SCALAR leaf
      -- when the dest does not already have it. An existing user value always wins — this is the
      -- exact merge-in-place behavior that makes a naive `if profile.x == nil then migrate()`
      -- guard unreachable, because a bare read of db.profile has already populated it.
      local function copyDefaults(dest, src)
        for k, v in pairs(src or {}) do
          if type(v) == "table" then
            if type(dest[k]) ~= "table" then dest[k] = {} end
            copyDefaults(dest[k], v)
          elseif dest[k] == nil then
            dest[k] = v
          end
        end
      end

      local function ensureProfile(name)
        sv.profiles[name] = sv.profiles[name] or {}
        copyDefaults(sv.profiles[name], defaults and defaults.profile)
        return sv.profiles[name]
      end

      copyDefaults(sv.global, defaults and defaults.global)
      -- Real AceDB-3.0 exposes the whole raw SavedVariables table as db.sv, and that is how a
      -- migration reaches `sv.profiles` to lift EVERY saved profile rather than just the active
      -- one. Note the fidelity that matters: profiles are only merged with the defaults by
      -- ensureProfile when they are actually activated, so a pre-seeded, never-activated profile
      -- stays exactly as the SavedVariables file had it — un-stamped, which is precisely the case a
      -- per-profile lift has to handle.
      db.sv      = sv
      db.global  = sv.global
      db.profile = ensureProfile(current)

      local function fire(event)
        for _, cb in ipairs(callbacks[event] or {}) do cb(event, db, current) end
      end

      -- CallbackHandler shape: db.RegisterCallback(target, event, fn) — dot-called, so the
      -- registering object arrives as the first arg.
      db.RegisterCallback = function(_target, event, fn)
        callbacks[event] = callbacks[event] or {}
        callbacks[event][#callbacks[event] + 1] = fn
      end

      db.GetCurrentProfile = function() return current end

      db.GetProfiles = function()
        local names = {}
        for name in pairs(sv.profiles) do names[#names + 1] = name end
        table.sort(names)
        return names
      end

      db.SetProfile = function(_, name)
        if name == current then return end
        current = name
        db.profile = ensureProfile(name)
        fire("OnProfileChanged")
      end

      db.ResetProfile = function()
        -- Wipe in place: the real lib keeps the profile table's identity across a reset, so
        -- anything holding a reference to db.profile keeps seeing the live table.
        local p = sv.profiles[current]
        for k in pairs(p) do p[k] = nil end
        copyDefaults(p, defaults and defaults.profile)
        fire("OnProfileReset")
      end

      db.CopyProfile = function(_, name)
        local src = sv.profiles[name]
        if not src or name == current then return end
        local p = sv.profiles[current]
        for k in pairs(p) do p[k] = nil end
        for k, v in pairs(deepcopy(src)) do p[k] = v end
        fire("OnProfileCopied")
      end

      db.DeleteProfile = function(_, name)
        if name == current then return end
        sv.profiles[name] = nil
      end

      return db
    end,
  }

  libs["AceAddon-3.0"] = {
    NewAddon = function(_, target)
      target = target or {}
      local noop = function() end
      -- Record AceEvent registrations rather than no-opping them: an addon that registers a
      -- target/focus event only while that unit is enabled has gating a test cannot see unless the
      -- mock remembers what is currently registered.
      target.__events = {}
      target.RegisterEvent = function(self, event, handler)
        self.__events[event] = handler or true
        return self
      end
      target.UnregisterEvent = function(self, event)
        self.__events[event] = nil
        return self
      end
      target.RegisterChatCommand = noop
      target.ScheduleTimer = function(_, fn, delay)
        local timer = { fn = fn, delay = delay }
        M.__timers[#M.__timers + 1] = timer
        return timer
      end
      target.ScheduleRepeatingTimer = function() return {} end
      target.CancelTimer = noop
      -- Faithfully mirror AceConsole-3.0's Embed: it stamps a :Print mixin onto the addon object,
      -- clobbering any same-named custom NS.Print. Called as `NS.Print(msg)`, AceConsole treats the
      -- message as `self` and renders "|cff33ff99<msg>|r:" — green, trailing colon, no tag. The
      -- addon must reclaim NS.Print after NewAddon; reproducing the clobber here lets the tests
      -- exercise the real production print path instead of a clean one the client never uses.
      target.Print = function(selfOrMsg, ...)
        local parts = { "|cff33ff99" .. tostring(selfOrMsg) .. "|r:" }
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(table.concat(parts, " ")) end
      end
      return target
    end,
  }

  -- AceEvent-3.0 message bus. A no-op Embed would hide the whole (message, target) clobber class of
  -- bug (architecture-§4): the real lib keys callbacks by (message, target) through one shared
  -- registry, so a SendMessage on any embedded object fans out to every target that registered that
  -- message, and two receivers on ONE target would overwrite each other. Model that faithfully —
  -- one registry shared across every embed, dispatching fn(message, ...) exactly as CallbackHandler
  -- fires a function-ref callback. Fresh per build for isolation.
  local busRegistry = {}  -- [message] = { [target] = fn }
  libs["AceEvent-3.0"] = {
    Embed = function(_, obj)
      obj.RegisterMessage = function(self, msg, fn)
        busRegistry[msg] = busRegistry[msg] or {}
        busRegistry[msg][self] = fn
      end
      obj.UnregisterMessage = function(self, msg)
        if busRegistry[msg] then busRegistry[msg][self] = nil end
      end
      obj.SendMessage = function(_, msg, ...)
        local subs = busRegistry[msg]
        if not subs then return end
        for _, fn in pairs(subs) do fn(msg, ...) end
      end
      return obj
    end,
  }

  -- AceGUI-3.0. Without this the options toolkit's widget makers all return early and the schema →
  -- widget translation layer is untestable. Widgets here are inert data recorders rather than
  -- frames: they remember what was set on them and, crucially, expose __fire so a test can drive
  -- the OnValueChanged / OnMouseUp / OnValueConfirmed callbacks the way a real click would — which
  -- is what exercises the read → write → refresh loop.
  local function makeWidget(wtype)
    local w = {
      type      = wtype,
      children  = {},
      callbacks = {},
      frame     = stubFrame(),
    }
    function w:SetLabel(v) self.labelText = v; return self end
    function w:SetText(v) self.text = v; return self end
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
      w.scrollbar   = stubFrame()
      w.scrollframe = stubFrame()
      w.content     = stubFrame()
      w.content.original_width = 400
      w.localstatus = { offset = 0 }
      function w:FixScroll() self.fixScrollCount = (self.fixScrollCount or 0) + 1 end
      function w:MoveScroll(v) self.movedTo = v end
      function w:SetScroll(v) self.scrolledTo = v end
    end
    return w
  end

  local aceGUI = {
    -- Populated by RegisterWidgetType. Empty by default, which models
    -- AceGUI-3.0-SharedMediaWidgets being absent: a dropdown maker asks GetWidgetVersion about
    -- LSM30_* and falls back to a plain Dropdown when it comes back nil.
    WidgetRegistry   = {},
    __widgetVersions = {},
  }
  -- Every widget this factory hands out, in creation order. Harness-side only — no production code
  -- knows it exists. It is the only way a test can reach a widget on a page whose ctx the toolkit
  -- keeps private, which is why a button's onClick once shipped unreachable and therefore untested.
  aceGUI.__created = {}
  function aceGUI:Create(wtype)
    local ctor = self.WidgetRegistry[wtype]
    local w = ctor and ctor() or makeWidget(wtype)
    self.__created[#self.__created + 1] = w
    return w
  end
  function aceGUI:GetWidgetVersion(wtype) return self.__widgetVersions[wtype] end
  function aceGUI:RegisterWidgetType(wtype, ctor, version)
    self.WidgetRegistry[wtype]   = ctor
    self.__widgetVersions[wtype] = version
  end
  M.__makeAceGUIWidget = makeWidget
  libs["AceGUI-3.0"] = aceGUI

  libs["AceTimer-3.0"] = { Embed = function(_, obj) return obj end }
  libs["AceConsole-3.0"] = { Embed = function(_, obj) return obj end }

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

  return M
end
