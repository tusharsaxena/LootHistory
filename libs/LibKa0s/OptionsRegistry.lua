-- LibKa0s-Options-1.0 — the page registry: the queue a host's page files register into, the
-- main canvas category CreateOptionsPanel registers and the pages it builds, the park that holds a
-- registration asked for in combat until combat ends, and OpenOptionsPanel (O.RegisterOptionsPage,
-- O.__pages, O.CreateOptionsPanel, O.OpenOptionsPanel).
--
-- Peeled out of Options.lua at OptionsRegistry minor 1 / Options minor 26 (LK-ATS-04, the
-- 2026-09-26 automated-tests sweep) with no change in behavior. Options.lua carried it since
-- minor 1, and the park since minor 24 (LK-25). It is a seam of its own: the registry's state
-- (the page queue, the built list, the main category and its ID, the parked flag) is read by
-- nothing else in the shell, and the registry reaches the rest of the instance only through
-- members (O.CreatePanel, O.SetRenderer, O.AceGUI, O.__print) and the descriptor. The park's
-- library half (lib.__parkedPanels, lib.__OnParkEvent, lib.__parkRegistration, lib.__parkFrame)
-- has one caller, CreateOptionsPanel's parkIfLocked, so it moved with it.
--
-- WHO CALLS IN. lib:New calls lib.__AttachRegistry at the point the registry used to be defined, so
-- every instance still gets its members in the same order. A copy with no OptionsRegistry.lua has
-- no O.CreateOptionsPanel, and a host fails when it calls it: the call-time failure a partly-copied
-- Options major has always had (docs/releasing.md).
--
-- Part of the Options major rather than a major of its own, and guarded with the same multi-file
-- idiom as OptionsCombat.lua and OptionsIds.lua.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

-- Minor 1: the page registry and the registration park, moved here from Options.lua (its minors
-- 1 to 25) with no change in behavior.
local REGISTRY_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own — see OptionsScroll.lua for why the
-- file's own counter is not enough.
if lib.__registryMinor and lib.__registryMinor >= REGISTRY_MINOR
  and lib.__registryShellMinor == lib.MINOR then return end
lib.__registryMinor      = REGISTRY_MINOR
lib.__registryShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsRegistry = REGISTRY_MINOR

-- ── the registration park (minor 24) ────────────────────────────────────────────────────────
--
-- O.CreateOptionsPanel under InCombatLockdown() registers nothing: registering a category is the
-- first touch a panel makes on Blizzard's settings tree, and a host reaching it from a /reload taken
-- in combat is the one path every consumer shares. The request is PARKED here instead, and replayed
-- once when combat ends. The replay does not go through the host: it runs whatever the host's own
-- stand-down state, so an addon disabled mid-combat still gets its category (ConsumableMaster's own
-- park lost it there). No instance member is added, so no degradation stub moves.
--
-- LIBRARY-LEVEL and private: one frame for the whole process (`lib.__parkFrame`), separate from the
-- page lock's, registered for PLAYER_REGEN_ENABLED ONLY while something is parked and let go before
-- the replay runs. Its handler looks `lib.__OnParkEvent` up when the event arrives, so the newest
-- copy's dispatcher drains what an older copy parked. A stand-down suite that fires every event at
-- every frame reaches it with nothing parked, and nothing happens.

lib.__parkedPanels = lib.__parkedPanels or {}

--- Drain the park: let go of the event, then replay every parked request once, in order. Each is
--- pcall'd so one host's registration cannot cost another's; the first error is raised after the
--- rest have run, so it is reported rather than swallowed.
function lib.__OnParkEvent(event)
  if event ~= "PLAYER_REGEN_ENABLED" then return end
  local f = lib.__parkFrame
  if f then f:UnregisterEvent("PLAYER_REGEN_ENABLED") end
  local parked = lib.__parkedPanels
  lib.__parkedPanels = {}
  local firstErr
  for _, replay in ipairs(parked) do
    local ok, err = pcall(replay)
    if not ok and firstErr == nil then firstErr = err end
  end
  if firstErr ~= nil then error(firstErr, 0) end
end

--- Park one replay and listen for the end of combat. Answers false when the client has no frame to
--- listen with, and the caller then registers at once, as every minor before 24 did.
function lib.__parkRegistration(replay)
  local f = lib.__parkFrame
  if not f then
    if type(CreateFrame) ~= "function" then return false end
    f = CreateFrame("Frame")
    if not f then return false end
    f:Hide()
    lib.__parkFrame = f
  end
  f:SetScript("OnEvent", function(_, event)
    local dispatch = lib.__OnParkEvent
    if type(dispatch) == "function" then dispatch(event) end
  end)
  local parked = lib.__parkedPanels
  parked[#parked + 1] = replay
  f:RegisterEvent("PLAYER_REGEN_ENABLED")
  return true
end

-- ── the instance half ──────────────────────────────────────────────────────────────────────

--- Attach the page registry to one instance. Called by lib:New (Options minor 26) at the point
--- the registry used to be defined there, so its members arrive in the same order. The sink is
--- the shell's own (`O.__print`, set before any attach runs), the one lib:New built from `d`.
function lib.__AttachRegistry(O, d)
  local print = O.__print

  local pendingPages = {}      -- file-load-time queue; page files register into it
  local builtPages  = {}       -- the ones that actually built, in build order
  local built       = false    -- has CreateOptionsPanel drained the queue yet?
  local mainCategory           -- Settings.RegisterCanvasLayoutCategory return
  local mainCategoryID         -- numeric ID for OpenToCategory

  -- ── the page registry ────────────────────────────────────────────────────────────────────

  --- Register a sub-page builder.
  --- @param key      unique short key ("general", "bar", ...)
  --- @param name     display name in Blizzard Settings
  --- @param builder  function(mainCategory) -> subcategory | nil. Called once at
  ---                 CreateOptionsPanel time, after the db is ready. nil means the page opted out
  ---                 (an optional dependency the host did not find).
  --- Build one page, reporting rather than propagating. The key is in the message because a
  --- builder's own stack rarely names the page a user would recognize.
  local function buildPage(page)
    local ok, err = pcall(page.builder, mainCategory)
    if ok then
      builtPages[#builtPages + 1] = page
      return true
    end
    print(lib.STRINGS.PAGE_FAILED:format(tostring(page.key or "?"), tostring(err)))
    return false
  end

  function O.RegisterOptionsPage(key, name, builder)
    local page = { key = key, name = name, builder = builder }
    -- A page registered AFTER the build is built immediately rather than queued behind a drain
    -- that has already happened — otherwise it silently never appears.
    if built and mainCategory then return buildPage(page) end
    pendingPages[#pendingPages + 1] = page
  end

  --- Every page that built successfully, for a host's own diagnostics and for the suite.
  function O.__pages() return builtPages end

  local function registerMain()
    if not (Settings and Settings.RegisterCanvasLayoutCategory
            and Settings.RegisterAddOnCategory) then
      return
    end

    local mainCtx = O.CreatePanel(d.mainPanelName, d.parentTitle or "", { isMain = true })

    -- Deferred to first OnShow through the same seam every sub-page uses: AceGUI's ScrollFrame
    -- lays children out against the parent's CURRENT width, which is zero at enable time. Routing
    -- it through SetRenderer rather than a private flag also gives the main page the combat guard
    -- and the dirty-re-render, which it had neither of.
    --
    -- d.buildMain is the ONLY main-page seam. O.BuildLandingPage is a renderer a host may call from
    -- its own buildMain; the shell does not sniff the descriptor for a spec and wire one up on the
    -- host's behalf. A shell that installs a renderer the host never asked for makes "what draws my
    -- main page?" unanswerable from the host's own source, and it is a change to what lib:New DOES
    -- rather than an addition to what it offers.
    if type(d.buildMain) == "function" then
      O.SetRenderer(mainCtx, d.buildMain)
    end

    mainCategory   = Settings.RegisterCanvasLayoutCategory(mainCtx.panel, d.parentTitle)
    Settings.RegisterAddOnCategory(mainCategory)
    mainCategoryID = mainCategory:GetID()
  end

  local parked = false         -- is a combat-time CreateOptionsPanel waiting in lib.__parkedPanels?

  --- Under InCombatLockdown(), park this instance's registration for the end of combat (minor 24;
  --- read the note at lib.__parkRegistration). Answers true when the caller must stop here: parked
  --- now, or already parked, which makes a second call in the same combat a no-op.
  local function parkIfLocked()
    if parked then return true end
    if not (InCombatLockdown and InCombatLockdown()) then return false end
    parked = lib.__parkRegistration(function()
      parked = false
      O.CreateOptionsPanel()
    end)
    if parked and type(d.debug) == "function" then d.debug("Cfg", "register parked (in combat)") end
    return parked
  end

  --- Build the whole options surface: resolve AceGUI, validate, register the main canvas, then run
  --- every page builder. In combat it registers nothing and replays itself once combat ends.
  function O.CreateOptionsPanel()
    -- Idempotent: a second call is a no-op. The function is public and cheap to reach twice (a
    -- login plus a profile change), and re-running it would register a SECOND Blizzard category
    -- for the same addon and append a second ctx per page to renderedPanels, permanently doubling
    -- the RefreshAllPanels fan-out. The guard is on RE-registration only; the lazy body render at
    -- first OnShow is untouched.
    if mainCategory then return end
    if parkIfLocked() then return end

    -- Re-resolved rather than trusting the handle taken at New time. A host builds its panel at
    -- PLAYER_LOGIN, by which point an AceGUI that was absent at load may be present (and vice
    -- versa on a broken install), and this is the one place that can report it.
    O.AceGUI = LibStub and LibStub("AceGUI-3.0", true) or nil
    if not O.AceGUI then
      print(lib.STRINGS.NO_ACEGUI)
      return
    end
    if type(d.onAceGUI) == "function" then d.onAceGUI(O.AceGUI) end

    if type(d.validate) == "function" then d.validate() end

    registerMain()
    if not mainCategory then return end

    -- Each builder registers its own Blizzard subcategory as a side effect, and each is pcall'd
    -- SEPARATELY. Unguarded, one raising builder killed every page after it in the list — and the
    -- user sees a half-registered options tree with no error naming which page did it.
    for _, page in ipairs(pendingPages) do
      buildPage(page)
    end
    -- Drained, so a page registered before the build cannot be built twice. REASSIGNED rather than
    -- wiped in place: nothing outside this closure holds the table.
    pendingPages = {}
    built = true
  end

  -- Expand the parent category in the Blizzard left tree so every sub-page is visible. Wrapped in
  -- pcall: SettingsPanel internals are private API and could shift between patches.
  local function expandMainCategory()
    if not (mainCategory and SettingsPanel) then return end
    pcall(function()
      local list = SettingsPanel.GetCategoryList
        and SettingsPanel:GetCategoryList()
        or SettingsPanel.CategoryList
      if not (list and list.GetCategoryEntry) then return end
      local entry = list:GetCategoryEntry(mainCategory)
      if entry and entry.SetExpanded then
        entry:SetExpanded(true)
      end
    end)
  end

  --- Open the host's settings category.
  ---
  --- REFUSES under combat, and does not defer-and-replay. Blizzard's category switch is protected,
  --- so calling it under lockdown taints the panel for the rest of the session (options-ui-§2).
  --- Replaying on PLAYER_REGEN_ENABLED is the other wrong answer: a panel that opens itself the
  --- instant combat drops steals focus during post-pull recovery. The user re-runs the command.
  ---
  --- The gate lives HERE rather than in a host's slash dispatcher, so every caller is refused —
  --- the config verb, a /run script, a future internal caller.
  ---
  --- @return true when the category was opened; false when refused in combat (the chat line is
  ---         still printed); nil when there is no category to open -- CreateOptionsPanel has not
  ---         registered one yet (or is parked for the end of combat), or the client has no
  ---         Settings.OpenToCategory. (minor 24; every earlier minor returned nothing.)
  function O.OpenOptionsPanel()
    if InCombatLockdown and InCombatLockdown() then
      if type(d.debug) == "function" then d.debug("Cfg", "open refused (in combat)") end
      print(lib.STRINGS.COMBAT_REFUSED)
      return false
    end
    if not (Settings and Settings.OpenToCategory) then return nil end
    if not mainCategoryID then return nil end
    if type(d.debug) == "function" then d.debug("Cfg", "opened") end
    Settings.OpenToCategory(mainCategoryID)
    expandMainCategory()
    return true
  end
end
