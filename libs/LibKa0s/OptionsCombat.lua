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
local COMBAT_MINOR = 1
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
    cover:Hide()
    return cover
  end

  --- At the start of combat, close an AceGUI pullout the player left open on one of `panels` (the
  --- instance's pages). AceGUI marks an open dropdown as its focused widget, and ClearFocus closes
  --- the pullout -- which is parented to UIParent, so the cover cannot reach it. Only a widget
  --- under one of these pages: another addon's dropdown is not the library's to close. A color
  --- picker is Blizzard's frame and is left alone; the write seam refuses what it commits.
  function O.__releaseOwnedFocus(panels)
    local AceGUI = O.AceGUI
    local w = AceGUI and AceGUI.FocusedWidget
    if not (w and w.frame and type(AceGUI.ClearFocus) == "function") then return end
    for _, ctx in ipairs(panels) do
      if lib.__descendsFrom(w.frame, ctx.panel) then
        pcall(AceGUI.ClearFocus, AceGUI)
        return
      end
    end
  end
end
