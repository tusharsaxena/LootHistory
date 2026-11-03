-- LibKa0s-Options-1.0 — the combat lock's page chrome (options-ui-§2): the one event frame the
-- lock listens on, its dispatcher and the page-scoped registration beside it, and the cover over a
-- page with the level that puts it above everything the page draws.
--
-- Peeled out of OptionsTabs.lua at OptionsCombat minor 1 (LK-ATS-03, the 2026-09-26
-- automated-tests sweep) with no change in behavior. OptionsTabs.lua carried it from its minor 2
-- (v1.46.0, the combat lock) and minor 3 (v1.46.1, registration only while a page is shown), where
-- it had gone to keep Options.lua under the cap. It is a seam of its own: nothing below reads a
-- local of the tab strip, its art or the tabbed page, and nothing there reads a local of this file.
-- The two halves meet only through `lib` fields and the two members lib.__AttachCombat defines.
--
-- The lock's logic -- the predicate, the per-instance hooks, the refusal -- is still the shell's
-- (Options.lua minor 22); read its note first. A minor named in the notes below without a file is
-- OptionsTabs.lua's, where the code was written.
--
-- WHO CALLS IN. Options.lua reaches the library half through `lib` (lib.__pageShown,
-- lib.__pageHidden, lib.__coverLevel), each call guarded; lib.__AttachTabs calls
-- lib.__AttachCombat where the cover's two members used to be defined, so an instance gets the same
-- members in the same order and Options.lua does not move. A copy with no OptionsCombat.lua draws no
-- cover and registers no event, and the refusal still answers InCombatLockdown().
--
-- Part of the Options major rather than a major of its own, and guarded with the same multi-file
-- idiom as OptionsTabs.lua and OptionsIds.lua.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

-- Minor 1: the combat lock's page chrome, moved here from OptionsTabs.lua (its minors 2 and 3)
-- with no change in behavior.
-- Minor 2: O.__releaseOwnedFocus also closes an IdList suggestion list one of the instance's pages
-- opened (OptionsIds minor 3's O.__closeOwnedSuggest), after the pullout rather than instead of it.
-- Minor 3: a registered skin owner's cover takes its skin each time it goes up (S.Cover: the dim
-- and the line), so an owner that registered after the page was built still gets it (LK-07).
-- Minor 4: an AceGUI pullout on a Ka0s surface closes on a mouse press outside it (R4-L1 of
-- Ka0sAddonsCommonTasks docs/2026-11-03-SMOKE_ROUND4/): lib.__armPulloutClose and the watcher below.
local COMBAT_MINOR = 4
-- Paired on the SHELL's minor as well as this file's own — see OptionsScroll.lua for why the
-- file's own counter is not enough.
if lib.__combatMinor and lib.__combatMinor >= COMBAT_MINOR
  and lib.__combatShellMinor == lib.MINOR then return end
lib.__combatMinor      = COMBAT_MINOR
lib.__combatShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsCombat = COMBAT_MINOR

-- ── the combat cover's library half (minor 2) ──────────────────────────────────────────────
--
-- The lock itself -- the predicate, the dispatcher, the per-instance hooks -- is Options.lua's
-- (minor 22; read its note first). What lives here is the page chrome it draws with: the ONE event
-- frame the library listens on, and the arithmetic that puts a cover above everything a page draws.
--
-- The frame is created once for the process, hidden, and kept across a LibStub upgrade
-- (`lib.__combatFrame`); its handler looks `lib.__OnCombatEvent` up when the event arrives, so the
-- newest copy's dispatcher is the one that runs. The handler is re-set on every load that gets this
-- far, so an upgrade replaces an older copy's closure as well.
--
-- REGISTERED ONLY WHILE A PAGE IS SHOWN (minor 3). v1.46.0 registered PLAYER_REGEN_* at load, for
-- the life of the process: every host -- a stood-down one included, with no settings page open --
-- then owned two live registrations and a second REGEN dispatcher beside its own, which is what
-- each consumer's stand-down suite counts. Now a page's show registers both events and the last
-- page's hide lets go of them. A page shown mid-combat is locked off InCombatLockdown(), which is
-- all the predicate needs; the registration it makes is what hears the end of that combat.

local function combatEventFrame()
  if lib.__combatFrame then return lib.__combatFrame end
  if type(CreateFrame) ~= "function" then return nil end
  local f = CreateFrame("Frame")
  if not f then return nil end
  f:Hide()
  lib.__combatFrame = f
  return f
end

-- Every ctx whose page is on screen, across every host. Weak-keyed: a ctx nobody holds is gone.
lib.__shownPages = lib.__shownPages or setmetatable({}, { __mode = "k" })

local function onScreen(ctx)
  local panel = ctx.panel
  if not panel then return false end
  local probe = panel.IsVisible or panel.IsShown
  return probe == nil or probe(panel) and true or false
end

--- Drop every page no longer on screen, then register the two events if any page is left, or let
--- go of them -- and of PLAYER_REGEN_DISABLED's flag, which nothing will clear once unregistered --
--- if none is. The predicate still answers InCombatLockdown() for a page shown later.
function lib.__syncCombatEvents()
  local f = lib.__combatFrame
  for ctx in pairs(lib.__shownPages) do
    if not onScreen(ctx) then lib.__shownPages[ctx] = nil end
  end
  local any = next(lib.__shownPages) ~= nil
  if f then
    if any then
      f:RegisterEvent("PLAYER_REGEN_DISABLED")
      f:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
      f:UnregisterEvent("PLAYER_REGEN_DISABLED")
      f:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
  end
  if not any then lib.__combatLocked = false end
end

--- The dispatcher (Options minor 22; here, beside the registration, from minor 3). The events are
--- first re-synced to the pages on screen: with none left the library lets go of them and of the
--- flag and does nothing else, so an event that reaches it anyway -- a stand-down suite fires every
--- event at every frame that ever owned one -- draws, renders and prints nothing. Otherwise
--- PLAYER_REGEN_DISABLED locks, PLAYER_REGEN_ENABLED unlocks, and every host's hook runs, each
--- pcall'd so one host's page cannot keep another's cover up.
function lib.__OnCombatEvent(event)
  lib.__syncCombatEvents()
  if next(lib.__shownPages) == nil then return end
  if event == "PLAYER_REGEN_DISABLED" then
    lib.__combatLocked = true
  elseif event == "PLAYER_REGEN_ENABLED" then
    lib.__combatLocked = false
  else
    return
  end
  local locked = lib.__combatLocked
  for hook in pairs(lib.__combatHooks) do pcall(hook, locked) end
end

--- A page came on screen: watch combat. Asked of the page rather than taken from the OnShow that
--- called this, so a show that did not leave the page on screen registers nothing.
function lib.__pageShown(ctx)
  -- A page show re-arms the pullout close (minor 4): an AceGUI that upgraded since load is hooked.
  if lib.__armPulloutClose then lib.__armPulloutClose() end
  if not onScreen(ctx) then return end
  lib.__shownPages[ctx] = true
  local f = lib.__combatFrame
  if f then
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
  end
end

--- A page went off screen: let go of combat if it was the last.
function lib.__pageHidden(ctx)
  lib.__shownPages[ctx] = nil
  lib.__syncCombatEvents()
end

do
  local f = combatEventFrame()
  if f then
    f:SetScript("OnEvent", function(_, event)
      local dispatch = lib.__OnCombatEvent
      if type(dispatch) == "function" then dispatch(event) end
    end)
  end
  -- An older copy (v1.46.0) registered for good at load; this lets go unless a page is shown.
  lib.__syncCombatEvents()
end

-- ── the outside press that closes an AceGUI pullout (minor 4) ───────────────────────────────
--
-- Stock AceGUI has no outside-click close. A Dropdown's pullout (and every type built from it:
-- Ka0sMedia_Font, Ka0sMedia_Statusbar and the other media pickers, AuraMaster's AuraMasterDropdown)
-- closes only through AceGUI:ClearFocus, which AceGUI's own Frame container calls on a press and
-- which no Ka0s settings canvas or window ever calls. The library's own Widgets dropdown and the
-- client's Menu close on GLOBAL_MOUSE_DOWN; this gives the AceGUI ones the same.
--
-- THE SEAM. Dropdown_TogglePullout calls AceGUI:SetFocus(self) right after the pullout opens, so
-- one post-hook on AceGUI.SetFocus sees every open. It is a plain Lua table hook (AceGUI is
-- insecure; SkinAce.lua hooks AceGUI objects the same way). The toggle runs on OnClick, the
-- RELEASE, so the press that opened the pullout has already gone by when the watcher registers:
-- no frame delay is needed and the opening click cannot close what it opened.
--
-- KA0S SURFACES ONLY (the lead's call 1). The pullout must hang off a Ka0s settings page on screen
-- (lib.__shownPages, which an AceDBOptions Profiles page joins too: its AceConfigDialog container
-- is parented to the page's body) or a window the Skin major painted with Shell (Core.ApplySkin's
-- `owner` path and every host's S.Shell). Another author's AceGUI dropdown in the same client keeps
-- AceGUI's behavior. Escape is not added.
--
-- LISTENED, NEVER CAUGHT. One hidden frame for the process (`lib.__pulloutWatch`, kept across a
-- LibStub upgrade) registers GLOBAL_MOUSE_DOWN only while such a pullout is open, as the Widgets
-- menu does. The press still reaches whatever is under the cursor: a press on another dropdown
-- closes this pullout, and that dropdown's release opens its own. A press over the pullout (a row,
-- its scrollbar, the multiselect Close row: all inside the pullout frame's bounds) or over the
-- owning dropdown (whose release is the toggle) is not outside. The handler reads
-- AceGUI.FocusedWidget when the press arrives, never a widget captured at open, and lets go
-- lazily: a pullout closed by any other route (a pick, the toggle, Dropdown_OnHide when its panel
-- hides, O.__releaseOwnedFocus at combat start, the skin picker's dropFocus, a release from the
-- pool) is found closed on the next press, which unregisters and clears nothing. Both frames are
-- plain and non-protected, so this works in combat too. The registration goes through Core's
-- SafeRegisterEvent.
--
-- THE HOOK GUARD is keyed on the AceGUI table and its LibStub minor, not on the function: a newer
-- AceGUI that loads later redefines SetFocus and is hooked again at the next arm (every instance's
-- New and every page show arm), while another addon's hook laid over ours is not hooked over. If
-- ours were ever laid twice, the handler is idempotent (a second RegisterEvent is a no-op). The hook
-- looks lib.__OnPulloutFocus up when it runs, so the newest copy's code is what answers.

local MOUSE_DOWN = "GLOBAL_MOUSE_DOWN"
local SURFACE_DEPTH = 100

--- The pullout of `w` when `w` is an AceGUI dropdown whose pullout is open, else nil.
local function openPullout(w)
  if type(w) ~= "table" or not w.open or type(w.frame) ~= "table" then return nil end
  local pullout = rawget(w, "pullout")
  if type(pullout) ~= "table" or type(pullout.frame) ~= "table" then return nil end
  return pullout
end

-- The panels of the Ka0s settings pages on screen, as a set.
local function shownPanels()
  local pages = {}
  for ctx in pairs(lib.__shownPages) do
    if type(ctx) == "table" and ctx.panel then pages[ctx.panel] = true end
  end
  return pages
end

-- The Skin major's paint records (frame -> { owner, calls, ... }), or nil with no Skin major.
local function paintRecords()
  local Skin = LibStub and LibStub("LibKa0s-Skin-1.0", true)
  return type(Skin) == "table" and type(Skin.painted) == "table" and Skin.painted or nil
end

-- Did the Skin major paint `f` as a window (Shell)?
local function shellPainted(painted, f)
  local rec = painted and painted[f]
  return type(rec) == "table" and type(rec.calls) == "table" and rec.calls.Shell ~= nil
end

--- Does `frame` sit on a Ka0s surface: a Ka0s settings page on screen, or a Shell-painted window?
--- A bounded walk up GetParent.
--- @return boolean
function lib.__onKa0sSurface(frame)
  local pages, painted = shownPanels(), paintRecords()
  local f = frame
  for _ = 1, SURFACE_DEPTH do
    if type(f) ~= "table" then return false end
    if pages[f] or shellPainted(painted, f) then return true end
    local parent = f.GetParent and f:GetParent()
    if parent == f then return false end
    f = parent
  end
  return false
end

local function onPulloutEvent(_, event)
  if event ~= MOUSE_DOWN then return end
  local handler = lib.__OnPulloutPress
  if type(handler) == "function" then handler() end
end

local function pulloutWatch()
  local f = lib.__pulloutWatch
  if f then return f end
  if type(CreateFrame) ~= "function" then return nil end
  f = CreateFrame("Frame")
  if not f then return nil end
  f:Hide()
  f:SetScript("OnEvent", onPulloutEvent)
  lib.__pulloutWatch = f
  return f
end

local function stopWatch()
  local f = lib.__pulloutWatch
  if f then f:UnregisterEvent(MOUSE_DOWN) end
  lib.__pulloutAce = nil
end

local function mouseOver(frame)
  local probe = frame.IsMouseOver
  return type(probe) == "function" and probe(frame) == true
end

--- AceGUI:SetFocus's post-hook: a dropdown on a Ka0s surface just opened its pullout, so listen.
function lib.__OnPulloutFocus(AceGUI, w)
  if not openPullout(w) or not lib.__onKa0sSurface(w.frame) then return end
  local f = pulloutWatch()
  if not f then return end
  lib.__pulloutAce = AceGUI
  -- Through Core's pcall'd SafeRegisterEvent, as OptionsKeybinds' frame does: not a raw site of
  -- CLAUDE.md's events-frames-taint-§1 row. Without it nothing registers and nothing closes.
  local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
  local register = core and core.SafeRegisterEvent
  if type(register) == "function" and not f:IsEventRegistered(MOUSE_DOWN) then register(f, MOUSE_DOWN) end
end

--- GLOBAL_MOUSE_DOWN while listening: close the focused pullout unless the press is on it or on its
--- dropdown; let go when nothing of ours is open any more.
function lib.__OnPulloutPress()
  local AceGUI = lib.__pulloutAce
  local w = AceGUI and AceGUI.FocusedWidget
  local pullout = openPullout(w)
  if not pullout or not lib.__onKa0sSurface(w.frame) then
    stopWatch()
    return
  end
  if mouseOver(pullout.frame) or mouseOver(w.frame) then return end
  stopWatch()
  pcall(AceGUI.ClearFocus, AceGUI)
end

--- Hook `AceGUI` (default: LibStub's AceGUI-3.0 and its minor) once per AceGUI table and minor.
--- Answers true when it hooked. Internal: called at load, from every instance's New and every page
--- show.
--- @return boolean
function lib.__armPulloutClose(AceGUI, minor)
  if AceGUI == nil and LibStub then AceGUI, minor = LibStub("AceGUI-3.0", true) end
  if type(AceGUI) ~= "table" or type(AceGUI.SetFocus) ~= "function" then return false end
  if type(hooksecurefunc) ~= "function" then return false end
  local rec = lib.__pulloutHook
  if rec and rec.ace == AceGUI and rec.minor == minor then return false end
  hooksecurefunc(AceGUI, "SetFocus", function(self, w)
    local fn = lib.__OnPulloutFocus
    if type(fn) == "function" then fn(self, w) end
  end)
  lib.__pulloutHook = { ace = AceGUI, minor = minor }
  return true
end

do
  -- A watcher an older copy made takes this copy's handler, and this load arms the AceGUI loaded
  -- so far.
  if lib.__pulloutWatch then lib.__pulloutWatch:SetScript("OnEvent", onPulloutEvent) end
  lib.__armPulloutClose()
end

-- The cover's frame level: the deepest level under the page, plus one, and never less than
-- COVER_LEVEL_FLOOR above the page itself -- the floor covers a descendant whose level moves after
-- the walk (an AceGUI widget that raises its own frame). Capped at the client's frame-level
-- ceiling. A walk rather than a constant because the tab buttons already sit two levels above
-- the chrome frame they hang off (newTabButton's +1), and AceGUI nests a scroll's rows several
-- levels deep: any fixed small offset is a number some page's furniture will one day draw over.
local COVER_LEVEL_FLOOR = 100
local MAX_FRAME_LEVEL = 10000

local function levelOf(frame)
  local level = frame.GetFrameLevel and frame:GetFrameLevel()
  return type(level) == "number" and level or 0
end

local function deepestLevel(frame, skip, seen)
  local top = levelOf(frame)
  if type(frame.GetChildren) ~= "function" then return top end
  for _, kid in ipairs({ frame:GetChildren() }) do
    if type(kid) == "table" and kid ~= skip and kid ~= frame and not seen[kid] then
      seen[kid] = true
      local level = deepestLevel(kid, skip, seen)
      if level > top then top = level end
    end
  end
  return top
end

--- The level `cover` takes over `panel`, computed when the cover goes up over a page on screen.
--- @return number
function lib.__coverLevel(panel, cover)
  local floor = levelOf(panel) + COVER_LEVEL_FLOOR
  local want = math.max(floor, deepestLevel(panel, cover, {}) + 1)
  return math.min(want, MAX_FRAME_LEVEL)
end

--- Does `frame` sit under `ancestor`? A bounded walk up GetParent.
--- @return boolean
function lib.__descendsFrom(frame, ancestor)
  local f = frame
  for _ = 1, 64 do
    if f == nil then return false end
    if f == ancestor then return true end
    local parent = f.GetParent and f:GetParent()
    if parent == f then return false end
    f = parent
  end
  return false
end

--- Attach the cover's two members to one instance. Called by lib.__AttachTabs (OptionsTabs minor
--- 6) at the point they used to be defined there, so they arrive in the same order.
function lib.__AttachCombat(O)
  -- Every instance's New arms the pullout close (minor 4), after the host's own AceGUI loaded.
  if lib.__armPulloutClose then lib.__armPulloutClose() end
  -- ── the combat cover (minor 2) ──────────────────────────────────────────────────────────

  --- The cover over one page (Options.lua's CreatePanel calls this, out of combat): a plain,
  --- non-secure Frame over the whole canvas -- header band, chrome and tab strip included -- that
  --- takes the mouse and the wheel, so nothing under it can be clicked, dragged or scrolled, with a
  --- dim and one centered gray line. Hidden until the lock puts it up. It never touches keyboard
  --- propagation: a frame that swallowed keys would take the Escape that closes the window.
  function O.__buildCover(panel)
    local cover = CreateFrame("Frame", nil, panel)
    cover:SetAllPoints(panel)
    cover:EnableMouse(true)
    cover:EnableMouseWheel(true)
    cover:SetScript("OnMouseWheel", function() end)
    local dim = cover:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints(cover)
    dim:SetColorTexture(0, 0, 0, 0.6)
    local line = cover:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    line:SetPoint("CENTER", cover, "CENTER", 0, 0)
    line:SetTextColor(0.667, 0.667, 0.667)
    line:SetText(lib.STRINGS.COMBAT_LOCKED)
    -- Recorded as a plain field too, as panel.titleText is: a headless FontString cannot be read.
    cover.__text = lib.STRINGS.COMBAT_LOCKED
    -- HELD by the cover (minor 3), not left to locals. The client keeps a region alive through its
    -- parent, but a harness whose CreateTexture / CreateFontString hand back tracked objects does
    -- not: two unreferenced regions per page were garbage that a collection could take between two
    -- counts of what is on screen, and a stand-down suite read that as a frame appearing or going.
    cover.__dim, cover.__line = dim, line
    -- The page owner's skin, on every show (minor 3); nothing for a page with no registered owner.
    if cover.HookScript then
      cover:HookScript("OnShow", function()
        if O.__chromePaint then O.__chromePaint("Cover", dim, { text = line }) end
      end)
    end
    cover:Hide()
    return cover
  end

  --- At the start of combat, close an AceGUI pullout the player left open on one of `panels` (the
  --- instance's pages). AceGUI marks an open dropdown as its focused widget, and ClearFocus closes
  --- the pullout -- which is parented to UIParent, so the cover cannot reach it. Only a widget
  --- under one of these pages: another addon's dropdown is not the library's to close. A color
  --- picker is Blizzard's frame and is left alone; the write seam refuses what it commits. It also
  --- closes an IdList suggestion list one of these pages opened (minor 2): it is parented to
  --- UIParent, so the cover cannot reach it either. The pullout is not a reason to skip the list.
  function O.__releaseOwnedFocus(panels)
    local AceGUI = O.AceGUI
    local w = AceGUI and AceGUI.FocusedWidget
    if w and w.frame and type(AceGUI.ClearFocus) == "function" then
      for _, ctx in ipairs(panels) do
        if lib.__descendsFrom(w.frame, ctx.panel) then
          pcall(AceGUI.ClearFocus, AceGUI)
          break
        end
      end
    end
    if O.__closeOwnedSuggest then O.__closeOwnedSuggest(panels) end
  end
end
