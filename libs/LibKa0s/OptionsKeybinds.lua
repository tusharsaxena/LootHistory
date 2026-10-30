-- LibKa0s-Options-1.0 -- the Keybindings tab's model: the settings-panel editor for the key
-- bindings a host declares in its own Bindings.xml (launcher-§6), the client's two slots per action
-- under one key button per row, saved by the game to whichever set is in force. This file
-- holds the headless half: lib.__keybindSet / lib.__keybindClear (write a key with the client's own
-- slot semantics, refuse in combat, save once), lib.__keyChord (a key press to the client's chord
-- string), lib.__keybindSetName and the words, lib.KEYBIND_STRINGS. From minor 2 it also holds the
-- tab that draws it (options-ui-§20): the instance members O.KeybindingsTab, O.KeybindRows and
-- O.KEYBINDS_UNCHANGED, attached through lib.__AttachKeybinds, and the one capture listener every
-- host shares, lib.__keybindListener. From minor 3 the tab follows Options -> Keybindings: one
-- library frame, lib.__keybindEventFrame, hears UPDATE_BINDINGS while a keybind row is on screen
-- and repaints once per frame, and the page's OnShow re-reads every key. From minor 4 a row is one
-- key button and Clear (options-ui-§20): the button binds slot 1 and shows the first key, and a
-- second key, set on the client's page, is counted on it ("F5 +1") and named in its tooltip.
--
-- A twelfth file of the Options major (minor 1), guarded with the same multi-file idiom as
-- OptionsDrawer.lua; Options minor 30 attaches it. It loads after OptionsCombat.lua, because every
-- write asks the combat lock (lib.__IsCombatLocked, Options.lua) first.
--
-- WHY A LIBRARY SURFACE, THOUGH LAUNCHER-§6's RECORDED REJECTION (LibKa0s#58) STANDS. That ruling
-- keeps Bindings.xml and the BINDING_* globals in each addon, so one owner names each category and
-- action. It still holds: this file writes no BINDING_* global, never reads Bindings.xml and sets no
-- default key. What it shares is the editor -- one capture, one write path and one set of words for
-- every addon that offers its bindings on its own settings page, instead of a copy per addon.
--
-- SUPERSEDES QuickComms' 2026-10-21 retirement of its in-panel key box (QuickComms b902e35). The
-- working code it retired (db8f7a6: modules/Dial.lua, core/Compat.lua, modules/Library.lua) is
-- where the write-and-save path below was first run out of combat; it moves here, so a host gets
-- the box back through the library rather than through its own copy.
--
-- THE RULES IT KEEPS (KEYBINDINGS_RESEARCH 3.2 and 5.1 of Ka0sAddonsCommonTasks'
-- docs/2026-10-24-KEYBINDS_LAYOUT_STRATA/):
--   * It never touches SettingsPanel, KeybindListener, Settings.*BindingSet*, HideUIPanel or
--     ToggleGameMenu. Blizzard's own save path (its panel's Commit and OnHide) stays Blizzard's; this
--     file saves its own write with SaveBindings(GetCurrentBindingSet()) and nothing else.
--   * No key is bound, cleared or saved in combat: SetBinding is #nocombat, and SaveBindings is
--     blocked from tainted code in combat. A refusal calls no binding API at all.
--   * No SetPropagateKeyboardInput (protected in combat); the capture enables the keyboard only
--     while it listens, out of combat.
--   * It never reuses KeyBindingFrameBindingTemplate (it writes KeybindListener and SettingsPanel)
--     or AceGUI's Keybinding widget (Escape clears instead of canceling, no META, mouse buttons stop
--     at 5, one slot, English-only words, a FULLSCREEN_DIALOG message frame).

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end
-- Core's SafeRegisterEvent is the one registration route (minor 3); without it nothing registers.
local core = LibStub and LibStub("LibKa0s-Core-1.0", true)

-- Minor 1: the binding model (lib.__keybindSet / lib.__keybindClear / lib.__keybindAvailable /
-- lib.__keybindSetName), the chord builder (lib.__keyChord), the words (lib.KEYBIND_STRINGS) and an
-- empty lib.__AttachKeybinds.
-- Minor 2: the Keybindings tab -- O.KeybindingsTab, O.KeybindRows and O.KEYBINDS_UNCHANGED, two key
-- slots and a Clear button per action, the capture (lib.__keybindListener, one across every host,
-- Escape cancels, a right-click clears a slot), the set line and the outcome line, the combat
-- refusals and the capture stopped at combat start (lib.__keybindOnCombat), and the degradation row.
-- Minor 3: the tab follows Options -> Keybindings -- UPDATE_BINDINGS heard through Core's
-- SafeRegisterEvent only while a keybind row is on screen (lib.__keybindEventFrame,
-- lib.__keybindLive, lib.__syncKeybindEvents), one debounced repaint per frame
-- (lib.__OnKeybindEvent), and the page's OnShow re-reading every key.
-- Minor 4: one key button and Clear per row, the owner's follow-up to 015 -- the button binds and
-- right-click clears slot 1 (a second key moves up), reads "<first key> +N" when the action holds
-- more, and its tooltip, read at hover, names every key and says where the others were set. The
-- second slot widget and the KEY1 / KEY2 words are gone; KEY, KEY_MORE, KEYS_ALL and KEYS_OTHER
-- are new, and CLEAR_TIP says every key.
-- Minor 5: on a registered skin owner's page wearing a skin other than Ka0s Default, the rows' text
-- takes the skin's roles (the action's name `text.body`, the set and outcome lines `text.muted`),
-- through the widgets' own SetColor, which AceGUI resets when it hands a Label out again (LK-07).
-- Minor 6: the key button's tooltip title through O.__tipColor (`gtip.value`; OptionsScroll minor 9)
-- (LK-06d of Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_LIBRARY_FOLLOWUPS).
local KEYBINDS_MINOR = 6
-- Paired on the SHELL's minor as well as this file's own -- see OptionsScroll.lua for why.
if lib.__keybindsMinor and lib.__keybindsMinor >= KEYBINDS_MINOR
  and lib.__keybindsShellMinor == lib.MINOR then return end
lib.__keybindsMinor      = KEYBINDS_MINOR
lib.__keybindsShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsKeybinds = KEYBINDS_MINOR

-- ── the words ────────────────────────────────────────────────────────────────────────────────
--
-- A literal table, as OptionsIds.lua's ID_TEXT is: the library carries no locale, and a host that
-- has one passes `spec.strings` with any of these keys. ASCII throughout, with "->" for an arrow
-- (Options.lua's reason: the client's font may draw U+2192 as an empty box).
lib.KEYBIND_STRINGS = {
  TAB_LABEL     = "Keybindings",
  TAB_TIP       = "The same key bindings as Options -> Keybindings. A key set here shows there, " ..
                  "and the other way round.",
  INTRO         = "Key bindings are saved by the game, not in your profile. Defaults and Reset " ..
                  "all settings leave them alone.",
  UNCHANGED     = "Key bindings are not changed.",
  KEY           = "Key binding",
  KEY_MORE      = "%s +%d",
  KEYS_ALL      = "Keys: %s",
  KEYS_OTHER    = "The others were set on the game's Key Bindings page (Options -> Keybindings).",
  CLEAR         = "Clear",
  CLEAR_TIP     = "Remove every key from this action.",
  SLOT_TIP      = "Click, then press a key or a mouse button to bind it. Esc cancels. " ..
                  "Right-click removes this key.",
  LISTENING     = "Press a key...",
  SET_ACCOUNT   = "Saved for: all characters",
  SET_CHARACTER = "Saved for: this character only",
  SET_HOW       = "(Options -> Keybindings -> Character Specific Keybindings)",
  COMBAT        = "Key bindings can be changed after combat.",
  FAILED        = "That key could not be bound.",
  CLEARED       = "Key removed.",
  UNAVAILABLE   = "Key bindings cannot be set here on this client. Use Options -> Keybindings.",
}

-- The client's own words win where it has them, so the tab reads like its Keybindings page. Read
-- at use, never cached: a locale's global strings are the client's, not this file's.
local CLIENT_FALLBACK = {
  NOT_BOUND         = "Not bound",
  KEY_BOUND         = "Key bound.",
  KEY_UNBOUND_ERROR = "%s is now unbound.",
}

--- The client's string `name` (NOT_BOUND, KEY_BOUND or KEY_UNBOUND_ERROR), else the fallback.
function lib.__keybindClientString(name)
  local v
  if name == "NOT_BOUND" then v = NOT_BOUND
  elseif name == "KEY_BOUND" then v = KEY_BOUND
  elseif name == "KEY_UNBOUND_ERROR" then v = KEY_UNBOUND_ERROR end
  if type(v) == "string" and v ~= "" then return v end
  return CLIENT_FALLBACK[name]
end

-- ── the chord builder ────────────────────────────────────────────────────────────────────────
--
-- BindingUtil.lua's logic, bundled for a client (or the headless harness) without its functions.
-- The client's GetConvertedKeyOrButton, IsKeyPressIgnoredForBinding and
-- CreateKeyChordStringUsingMetaKeyState are taken first, each on its own guard. IGNORED applies
-- on BOTH routes: the client's ignore check covers the modifier keys and UNKNOWN only
-- (BindingUtil.lua:21-25), and the binding page refuses BUTTON1 / BUTTON2 in its own click
-- handler (:90-92), so trusting the client alone would bind a plain left or right click.

local IGNORED = {
  LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
  LMETA = true, RMETA = true, UNKNOWN = true, BUTTON1 = true, BUTTON2 = true,
}
local MOUSE = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3" }

local function convertKey(key)
  if type(GetConvertedKeyOrButton) == "function" then return GetConvertedKeyOrButton(key) end
  if MOUSE[key] then return MOUSE[key] end
  local n = tonumber(key:match("^Button(%d+)$"))
  if n and n >= 4 and n <= 31 then return "BUTTON" .. n end
  return key
end

local function isIgnored(key)
  if IGNORED[key] then return true end
  return type(IsKeyPressIgnoredForBinding) == "function" and IsKeyPressIgnoredForBinding(key) and true
    or false
end

local function isDown(fn)
  return type(fn) == "function" and fn() and true or false
end

local function bundledChord(key, mods)
  local parts = {}
  if mods.alt then parts[#parts + 1] = "ALT" end
  if mods.ctrl then parts[#parts + 1] = "CTRL" end
  if mods.shift then parts[#parts + 1] = "SHIFT" end
  if mods.meta then parts[#parts + 1] = "META" end
  parts[#parts + 1] = key
  return table.concat(parts, "-")
end

--- A key press as the client's binding string, or nil for a press that binds nothing: a modifier
--- alone, UNKNOWN, the left and right mouse buttons, and ESCAPE (the capture cancels on it before it
--- asks). Prefixes ALT- CTRL- SHIFT- META- in that order. `mods` ({ alt, ctrl, shift, meta })
--- overrides the modifier state for a suite, and takes the bundled route; without it the client's
--- own chord string is used where it exists. PRINTSCREEN is the capture's to handle.
--- @param key string the OnKeyDown key or the OnMouseDown button name
--- @param mods table|nil
--- @return string|nil
function lib.__keyChord(key, mods)
  if type(key) ~= "string" or key == "ESCAPE" then return nil end
  key = convertKey(key)
  if type(key) ~= "string" or key == "" or isIgnored(key) then return nil end
  if mods == nil and type(CreateKeyChordStringUsingMetaKeyState) == "function" then
    return CreateKeyChordStringUsingMetaKeyState(key)
  end
  mods = mods or { alt = isDown(IsAltKeyDown), ctrl = isDown(IsControlKeyDown),
                   shift = isDown(IsShiftKeyDown), meta = isDown(IsMetaKeyDown) }
  return bundledChord(key, mods)
end

-- ── the binding model ────────────────────────────────────────────────────────────────────────

--- True when the client has every binding function the model calls.
function lib.__keybindAvailable()
  return type(GetBindingKey) == "function" and type(GetBindingAction) == "function"
    and type(SetBinding) == "function" and type(SaveBindings) == "function"
    and type(GetCurrentBindingSet) == "function"
end

-- "combat" or "unavailable", or nil when a write may go ahead. Combat first, so a refusal in combat
-- never so much as reads the binding API.
local function refusal()
  if lib.__IsCombatLocked and lib.__IsCombatLocked() then return "combat" end
  if not lib.__keybindAvailable() then return "unavailable" end
  return nil
end

-- The command's keys in slot order, with no hole.
local function currentKeys(command)
  local k1, k2 = GetBindingKey(command)
  local list = {}
  if k1 ~= nil and k1 ~= "" then list[#list + 1] = k1 end
  if k2 ~= nil and k2 ~= "" then list[#list + 1] = k2 end
  return list
end

-- The new slot order (Blizzard's RebindKeysInOrder, Blizzard_Keybindings.lua): the old keys with
-- `key` in `slot`. A key the command already holds moves (the two swap); a new key replaces the
-- slot's old key; slot 2 on a keyless command becomes slot 1.
local function newOrder(old, slot, key)
  local rest, moved = {}, false
  for _, k in ipairs(old) do
    if k == key then moved = true else rest[#rest + 1] = k end
  end
  if moved or rest[slot] == nil then
    table.insert(rest, math.min(slot, #rest + 1), key)
  else
    rest[slot] = key
  end
  return rest
end

-- Put everything back after a falsy SetBinding: unbind what was bound, rebind the old keys in
-- order, and give `key` back to the action it was taken from.
local function restore(command, old, bound, key, displaced)
  for _, k in ipairs(bound) do SetBinding(k, nil) end
  for _, k in ipairs(old) do SetBinding(k, command) end
  if displaced then SetBinding(key, displaced) end
end

-- Steps 5 to 7: unbind the old keys, take `key` from `displaced`, rebind in order. Answers false at
-- the first falsy return, with what it had bound so far.
local function writeOrder(command, old, order, key, displaced, bound)
  for _, k in ipairs(old) do
    if not SetBinding(k, nil) then return false end
  end
  if displaced and not SetBinding(key, nil) then return false end
  for _, k in ipairs(order) do
    if not SetBinding(k, command) then return false end
    bound[#bound + 1] = k
  end
  return true
end

--- Bind `key` to `command` in `slot` (1 or 2), the client's way, and save it to the set in force.
--- @return boolean ok
--- @return string|nil displaced the action `key` was taken from
--- @return boolean|nil displacedUnbound true when that action is left with no key
--- @return string|nil reason "combat", "unavailable" or "failed" when not ok
function lib.__keybindSet(command, slot, key)
  local why = refusal()
  if why then return false, nil, nil, why end
  slot = (slot == 2) and 2 or 1
  local old = currentKeys(command)
  if old[slot] == key then return true end
  local prev = GetBindingAction(key)
  local displaced = (prev ~= nil and prev ~= "" and prev ~= command) and prev or nil
  local order, bound = newOrder(old, slot, key), {}
  if not writeOrder(command, old, order, key, displaced, bound) then
    restore(command, old, bound, key, displaced)
    return false, nil, nil, "failed"
  end
  local displacedUnbound = displaced ~= nil and GetBindingKey(displaced) == nil
  SaveBindings(GetCurrentBindingSet())
  return true, displaced, displacedUnbound
end

--- Remove `command`'s key in `slot` (1 or 2), or both when `slot` is nil, and save once.
--- Nothing to clear answers true and saves nothing.
--- @return boolean ok
--- @return string|nil reason "combat", "unavailable" or "failed" when not ok
function lib.__keybindClear(command, slot)
  local why = refusal()
  if why then return false, why end
  local old = currentKeys(command)
  local targets = {}
  if slot == 1 or slot == 2 then targets[1] = old[slot] else targets = old end
  if #targets == 0 then return true end
  for _, k in ipairs(targets) do
    if not SetBinding(k, nil) then
      for _, o in ipairs(old) do SetBinding(o, nil) end
      for _, o in ipairs(old) do SetBinding(o, command) end
      return false, "failed"
    end
  end
  SaveBindings(GetCurrentBindingSet())
  return true
end

--- "character" when the character-specific set is in force, else "account".
function lib.__keybindSetName()
  if type(GetCurrentBindingSet) ~= "function" then return "account" end
  local character = (Enum and Enum.BindingSet and Enum.BindingSet.Character)
    or CHARACTER_BINDINGS or 2
  return GetCurrentBindingSet() == character and "character" or "account"
end

-- ── the capture (minor 2) ────────────────────────────────────────────────────────────────────
--
-- ONE listener for every host in the session, because only one slot may listen at a time and
-- every vendored copy is handed the same `lib`: lib.__keybindListener, created once and kept across
-- a LibStub upgrade the way lib.__parkFrame is (OptionsRegistry.lua). A plain Frame that draws
-- nothing (frame-layering T0): no strata and no level of its own, so parented over the slot it
-- listens for it sits one level above it. Its scripts dispatch through the lib-level functions by
-- name, at call time, so a newer minor's handlers are the ones that run on an older copy's frame.
--
-- While it listens it covers the slot (SetAllPoints) and takes the keyboard, the mouse and the
-- wheel; the keyboard-enabled frame consumes Escape, so the Settings window stays open. It never
-- calls SetPropagateKeyboardInput (protected in combat), and it is never left enabled: every stop
-- turns all three off, hides it, clears its points and parents it back to UIParent.
--
-- lib.__keybindCapture is nil or { view = <the rows' view>, row = <row record>, slot = 1 }. From
-- minor 4 the tab only ever listens for slot 1; the field stays so the write path is the model's.

--- The listener, made on first use. nil without CreateFrame.
function lib.__keybindEnsureListener()
  local f = lib.__keybindListener
  if f then return f end
  if type(CreateFrame) ~= "function" then return nil end
  f = CreateFrame("Frame")
  if not f then return nil end
  f:Hide()
  f:SetScript("OnKeyDown", function(_, key)
    local fn = lib.__keybindOnKey
    if type(fn) == "function" then fn(key) end
  end)
  f:SetScript("OnMouseDown", function(_, button)
    local fn = lib.__keybindOnMouse
    if type(fn) == "function" then fn(button) end
  end)
  f:SetScript("OnMouseWheel", function(_, delta)
    local fn = lib.__keybindOnWheel
    if type(fn) == "function" then fn(delta) end
  end)
  lib.__keybindListener = f
  return f
end

--- Stop the capture, if any: the listener lets go of everything and goes home. With `repaint`
--- not false the slot shows its key again (false when the slot widget is being released and may
--- already belong to someone else). Answers the capture it stopped, or nil.
function lib.__keybindStop(repaint)
  local cap = lib.__keybindCapture
  lib.__keybindCapture = nil
  local f = lib.__keybindListener
  if f then
    f:EnableKeyboard(false)
    f:EnableMouse(false)
    f:EnableMouseWheel(false)
    f:Hide()
    f:ClearAllPoints()
    f:SetParent(UIParent)
  end
  if cap and repaint ~= false and cap.view and cap.view.paintRow then cap.view.paintRow(cap.row) end
  return cap
end

--- Start listening for `row`'s `slot` (1, the key button), stopping any other capture first. The
--- caller has already asked the combat lock. Answers false when there is no listener to listen with.
function lib.__keybindStart(view, row, slot)
  lib.__keybindStop()
  local f = lib.__keybindEnsureListener()
  local w = row.slots[slot]
  if not f or not w or not w.frame then return false end
  lib.__keybindCapture = { view = view, row = row, slot = slot }
  f:SetParent(w.frame)
  f:ClearAllPoints()
  f:SetAllPoints(w.frame)
  f:EnableKeyboard(true)
  f:EnableMouse(true)
  f:EnableMouseWheel(true)
  f:Show()
  w:SetText(view.S.LISTENING)
  return true
end

local function bindingName(command)
  if type(GetBindingName) == "function" then
    local name = GetBindingName(command)
    if type(name) == "string" and name ~= "" then return name end
  end
  local g = _G["BINDING_NAME_" .. tostring(command)]
  if type(g) == "string" and g ~= "" then return g end
  return tostring(command)
end

--- The outcome line for a refusal or a failure: `why` from __keybindSet / __keybindClear.
local function reasonText(S, why)
  if why == "combat" then return S.COMBAT end
  if why == "unavailable" then return S.UNAVAILABLE end
  return S.FAILED
end

--- The outcome line after a write, in the client's own words where it has them.
local function setOutcome(S, ok, displaced, displacedUnbound, why)
  if not ok then return reasonText(S, why) end
  if displaced and displacedUnbound then
    return lib.__keybindClientString("KEY_UNBOUND_ERROR"):format(bindingName(displaced))
  end
  return lib.__keybindClientString("KEY_BOUND")
end

--- Write `chord` to the listening slot, stop, and show the outcome on every row of that view.
local function captureWrite(chord)
  local cap = lib.__keybindCapture
  if not cap then return end
  local ok, displaced, displacedUnbound, why = lib.__keybindSet(cap.row.command, cap.slot, chord)
  lib.__keybindStop(false)
  cap.view.setStatus(setOutcome(cap.view.S, ok, displaced, displacedUnbound, why))
  cap.view.repaint()
end

--- OnKeyDown: Escape cancels; PRINTSCREEN takes the screenshot and keeps listening; a press that
--- binds nothing (a modifier alone) keeps listening; anything else is written.
function lib.__keybindOnKey(key)
  if not lib.__keybindCapture then return end
  if key == "ESCAPE" then lib.__keybindStop(); return end
  if key == "PRINTSCREEN" then
    if type(Screenshot) == "function" then Screenshot() end
    return
  end
  local chord = lib.__keyChord(key)
  if chord then captureWrite(chord) end
end

--- OnMouseDown: the left or right button cancels (click the slot again to cancel, as on the
--- client's page); any other button is written.
function lib.__keybindOnMouse(button)
  if not lib.__keybindCapture then return end
  if button == "LeftButton" or button == "RightButton" then lib.__keybindStop(); return end
  local chord = lib.__keyChord(button)
  if chord then captureWrite(chord) end
end

--- OnMouseWheel: MOUSEWHEELUP or MOUSEWHEELDOWN, with the modifiers held.
function lib.__keybindOnWheel(delta)
  if not lib.__keybindCapture then return end
  local chord = lib.__keyChord((tonumber(delta) or 0) > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
  if chord then captureWrite(chord) end
end

-- Combat start stops a capture in progress, through the combat lock's hook set (Options.lua;
-- OptionsCombat.lua calls each hook as pcall(hook, locked)). Held strongly on lib, since the set is
-- weak-keyed, and an older copy's hook is taken out of the set before this one goes in. No event
-- registration of its own: the lock's one combat frame is the only listener.
if lib.__combatHooks then
  if lib.__keybindOnCombat then lib.__combatHooks[lib.__keybindOnCombat] = nil end
  lib.__keybindOnCombat = function(locked)
    if locked ~= true then return end
    local cap = lib.__keybindStop()
    if cap and cap.view and cap.view.setStatus then cap.view.setStatus(cap.view.S.COMBAT) end
  end
  lib.__combatHooks[lib.__keybindOnCombat] = true
end

-- ── the sync (minor 3) ───────────────────────────────────────────────────────────────────────
--
-- The tab follows Options -> Keybindings and the binding set in force (KEYBINDINGS_RESEARCH 3.1,
-- 3.4 and 5.1 "Syncing"): SetBinding, SaveBindings, LoadBindings on a set switch and the client's
-- override bindings all fire UPDATE_BINDINGS. ONE library frame hears it, and only while a keybind
-- row is on screen -- the lock's discipline (lib.__syncCombatEvents, OptionsCombat.lua) -- so a host
-- with no settings page open owns no registration. It registers through Core's SafeRegisterEvent
-- on purpose, so this is not a fourth raw private registration site (CLAUDE.md's
-- events-frames-taint-§1 row); without Core it registers nothing, and the page's OnShow re-read and
-- the refreshers still keep the slots true. Events come in bursts (a rebind is several SetBinding
-- calls, and an override binding fires too), so they are debounced to one repaint per frame. A
-- repaint only reads, so it runs in combat as well.
--
-- lib.__keybindLive: row record -> its ctx, weak-keyed, from the row's build to its group's
-- OnRelease. lib.__keybindEventFrame: made once, kept across an upgrade, its OnEvent looking the
-- dispatcher up by name at call time (lib.__combatFrame's idiom).

lib.__keybindLive = lib.__keybindLive or setmetatable({}, { __mode = "k" })

-- Shown, by IsVisible where the frame has it, else IsShown; a frame with neither counts as shown.
local function shown(f)
  if type(f) ~= "table" then return false end
  local probe = f.IsVisible or f.IsShown
  return probe == nil or probe(f) and true or false
end

-- A row is on screen when its group's frame is, on a page that is. In the client the group's
-- IsVisible already answers for its parents; the page is asked as well for a frame that does not.
local function rowOnScreen(row, ctx)
  local g = row.group
  if type(g) ~= "table" or not shown(g.frame) then return false end
  return type(ctx) ~= "table" or ctx.panel == nil or shown(ctx.panel)
end

local function eventRegistered(f)
  return type(f.IsEventRegistered) == "function" and f:IsEventRegistered("UPDATE_BINDINGS")
end

--- Drop dead rows, then hear UPDATE_BINDINGS if any live row is on screen, or let go of it if none
--- is. Answers whether one is.
function lib.__syncKeybindEvents()
  local any = false
  for row, ctx in pairs(lib.__keybindLive) do
    if row.dead or type(row.group) ~= "table" then
      lib.__keybindLive[row] = nil
    elseif not any and rowOnScreen(row, ctx) then
      any = true
    end
  end
  local f = lib.__keybindEventFrame
  if not f then return any end
  if not any then
    if f.UnregisterEvent then f:UnregisterEvent("UPDATE_BINDINGS") end
  elseif not eventRegistered(f) then
    local register = core and core.SafeRegisterEvent
    if type(register) == "function" then register(f, "UPDATE_BINDINGS") end
  end
  return any
end

-- Every distinct view of the live rows `pick(row, ctx)` accepts, repainted once each: its slots
-- (a listening slot keeps saying so) and its set line.
local function repaintViews(pick)
  local done = {}
  for row, ctx in pairs(lib.__keybindLive) do
    local view = row.view
    if view and not done[view] and view.repaint and pick(row, ctx) then
      done[view] = true
      view.repaint()
    end
  end
end

--- The debounced repaint: every live row on screen, read again from GetBindingKey.
function lib.__keybindFlush()
  lib.__keybindRepaintPending = nil
  repaintViews(rowOnScreen)
end

--- The dispatcher. Synced first: with no row on screen it lets go and draws nothing. Otherwise one
--- repaint is queued for the end of the frame, however many events arrive before it runs.
function lib.__OnKeybindEvent(event)
  if not lib.__syncKeybindEvents() or event ~= "UPDATE_BINDINGS" then return end
  if lib.__keybindRepaintPending then return end
  lib.__keybindRepaintPending = true
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(0, function() lib.__keybindFlush() end)
  else
    lib.__keybindFlush()
  end
end

--- A page came on screen: hear the event again, and re-read every key of its rows, so a key set
--- while it was hidden shows with no event at all.
function lib.__keybindOnPanelShow(ctx)
  lib.__syncKeybindEvents()
  repaintViews(function(_, c) return c == ctx end)
end

--- A page went off screen: a capture on it stops, and the event is let go of if it was the last.
function lib.__keybindOnPanelHide(ctx)
  local cap = lib.__keybindCapture
  if cap and cap.view and cap.view.panel == ctx.panel then lib.__keybindStop() end
  lib.__syncKeybindEvents()
end

do
  local f = lib.__keybindEventFrame
  if not f and type(CreateFrame) == "function" then
    f = CreateFrame("Frame")
    if f then
      f:Hide()
      lib.__keybindEventFrame = f
    end
  end
  if f then
    f:SetScript("OnEvent", function(_, event)
      local dispatch = lib.__OnKeybindEvent
      if type(dispatch) == "function" then dispatch(event) end
    end)
  end
  -- An older copy's frame may still hold a registration; this lets go unless a row is on screen.
  lib.__syncKeybindEvents()
end

-- ── the attach ───────────────────────────────────────────────────────────────────────────────

-- The row's column widths, relative, summing below 1 for the clip inset (options-ui-§8). Minor 4
-- dropped the second slot and kept the others' widths, so the label and the key line up as before.
local W_LABEL, W_SLOT, W_CLEAR = 0.40, 0.22, 0.12

--- lib.KEYBIND_STRINGS with a host's translations over it, as a fresh table.
local function mergeStrings(overrides)
  local S = {}
  for k, v in pairs(lib.KEYBIND_STRINGS) do S[k] = v end
  if type(overrides) == "table" then
    for k, v in pairs(overrides) do
      if type(v) == "string" then S[k] = v end
    end
  end
  return S
end

local function slotText(key)
  if key == nil or key == "" then return lib.__keybindClientString("NOT_BOUND") end
  if type(GetBindingText) == "function" then
    local t = GetBindingText(key)
    if type(t) == "string" and t ~= "" then return t end
  end
  return key
end

-- Every key the command holds, in slot order, with no hole.
local function boundKeys(command)
  local keys = {}
  if type(GetBindingKey) ~= "function" then return keys end
  for _, k in ipairs({ GetBindingKey(command) }) do
    if k ~= nil and k ~= "" then keys[#keys + 1] = k end
  end
  return keys
end

-- The key button's text: the first key, counted with the rest ("F5 +1"), or NOT_BOUND.
local function buttonText(S, keys)
  local first = slotText(keys[1])
  if #keys > 1 then return S.KEY_MORE:format(first, #keys - 1) end
  return first
end

local function setLineText(S)
  local which = lib.__keybindSetName() == "character" and S.SET_CHARACTER or S.SET_ACCOUNT
  return which .. " " .. S.SET_HOW
end

--- Called by lib:New (Options minor 30), guarded. Minor 2 attaches the tab's three members.
function lib.__AttachKeybinds(O, d) -- luacheck: no unused args
  local function print(line) if O.__print then O.__print(line) end end
  local function refused(command)
    return O.__combatRefused ~= nil and O.__combatRefused("keybind", command)
  end

  --- `options-ui-§20`'s sentence for the General page's Defaults tooltip (`opts.defaultsTooltip`).
  O.KEYBINDS_UNCHANGED = lib.KEYBIND_STRINGS.UNCHANGED

  --- A host-tab entry for O.RenderTabbedSchema's `opts.tabs`; see O.KeybindRows for `spec`.
  function O.KeybindingsTab(spec)
    spec = spec or {}
    local S = mergeStrings(spec.strings)
    return {
      key = spec.key or "Keybindings", label = S.TAB_LABEL, tooltip = S.TAB_TIP, before = spec.before,
      render = function(ctx) O.KeybindRows(ctx, spec) end,
    }
  end

  --- Color one AceGUI label in the page owner's text role `token` while the chrome is skinned
  --- (O.__chromeAway: every skin, Ka0s Default included, since SkinPaint minor 6).
  local function skinLabel(w, token)
    local S = O.__chromeAway and O.__chromeAway()
    if not (S and w and type(w.SetColor) == "function") then return end
    local r, g, b = S.Color(token)
    if r then w:SetColor(r, g, b) end
  end

  --- One full-width line of text in `parent`: O.TextRow on the page's own scroll, a Label in a
  --- host-built body.
  local function textLine(view, text)
    if view.parent == view.ctx.scroll then return O.TextRow(view.ctx, text) end
    local w = O.AceGUI:Create("Label")
    w:SetFullWidth(true)
    w:SetText(text)
    view.parent:AddChild(w)
    return w
  end

  --- The view's painters: one row's key button (left saying so while it listens), every row and the
  --- set line, and the outcome line. Nothing is cached; every paint reads GetBindingKey.
  local function painters(view)
    function view.paintRow(row)
      local cap = lib.__keybindCapture
      if cap and cap.row == row then return end
      row.slots[1]:SetText(buttonText(view.S, boundKeys(row.command)))
    end
    function view.repaint()
      for _, row in ipairs(view.rows) do view.paintRow(row) end
      if view.setLine then view.setLine:SetText(setLineText(view.S)) end
    end
    function view.setStatus(text)
      if view.status then view.status:SetText(text or "") end
    end
  end

  local function onSlotClick(view, row, slot, button)
    local S = view.S
    if button == "RightButton" then
      lib.__keybindStop()
      if refused(row.command) then view.setStatus(S.COMBAT); return end
      local ok, why = lib.__keybindClear(row.command, slot)
      view.setStatus(ok and S.CLEARED or reasonText(S, why))
      view.repaint()
      return
    end
    local cap = lib.__keybindCapture
    if cap and cap.row == row and cap.slot == slot then lib.__keybindStop(); return end
    if refused(row.command) then
      lib.__keybindStop()
      view.setStatus(S.COMBAT)
      return
    end
    lib.__keybindStart(view, row, slot)
  end

  local function onClear(view, row)
    local cap = lib.__keybindCapture
    if cap and cap.row == row then lib.__keybindStop() end
    if refused(row.command) then view.setStatus(view.S.COMBAT); return end
    local ok, why = lib.__keybindClear(row.command, nil)
    view.setStatus(ok and view.S.CLEARED or reasonText(view.S, why))
    view.repaint()
  end

  --- The key button's tooltip, read at hover: the how-to line, and with more than one key every key
  --- and where the others were set, so a key set on the client's page is never hidden.
  local function keyTooltip(view, row, btn)
    local S = view.S
    local anchor = btn.frame or btn
    btn:SetCallback("OnEnter", function()
      if not GameTooltip then return end
      GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
      GameTooltip:SetText(S.KEY, O.__tipColor("gtip.value", 1, 1, 1))
      GameTooltip:AddLine(S.SLOT_TIP, nil, nil, nil, true)
      local keys = boundKeys(row.command)
      if #keys > 1 then
        local names = {}
        for i, k in ipairs(keys) do names[i] = slotText(k) end
        GameTooltip:AddLine(S.KEYS_ALL:format(table.concat(names, ", ")), nil, nil, nil, true)
        GameTooltip:AddLine(S.KEYS_OTHER, nil, nil, nil, true)
      end
      GameTooltip:Show()
    end)
    btn:SetCallback("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  end

  --- The key button: an AceGUI Button that takes both mouse buttons, handed back to the pool as it
  --- came (options-ui-§19): its one OnRelease restores LeftButtonUp and stops a capture it holds.
  local function makeSlot(view, row, slot)
    local btn = O.AceGUI:Create("Button")
    btn:SetRelativeWidth(W_SLOT)
    if btn.frame and btn.frame.RegisterForClicks then
      btn.frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    btn:SetCallback("OnClick", function(_, _, button) onSlotClick(view, row, slot, button) end)
    btn:SetCallback("OnRelease", function(w)
      if w.frame and w.frame.RegisterForClicks then w.frame:RegisterForClicks("LeftButtonUp") end
      local cap = lib.__keybindCapture
      if cap and cap.row.slots[cap.slot] == w then lib.__keybindStop(false) end
    end)
    keyTooltip(view, row, btn)
    if view.ctx.__renderDisabled then btn:SetDisabled(true) end
    return btn
  end

  --- One action's row: label, the key button, Clear, in a full-width Flow group.
  local function makeRow(view, binding)
    local AceGUI, S = O.AceGUI, view.S
    local row = { command = binding.command, status = view.status, slots = {}, view = view }
    local group = AceGUI:Create("SimpleGroup")
    group:SetLayout("Flow")
    group:SetFullWidth(true)
    -- Released (a tab change or a structural refresh): no longer live, and maybe the last on screen.
    group:SetCallback("OnRelease", function()
      row.dead = true
      lib.__keybindLive[row] = nil
      lib.__syncKeybindEvents()
    end)
    local name = bindingName(binding.command)
    -- An InteractiveLabel, because a plain Label takes no mouse and its tooltip would never show.
    local label = AceGUI:Create("InteractiveLabel")
    label:SetText(name)
    label:SetRelativeWidth(W_LABEL)
    skinLabel(label, "text.body")
    O.AttachTooltip(label, name, binding.tooltip)
    group:AddChild(label)
    row.slots[1] = makeSlot(view, row, 1)
    group:AddChild(row.slots[1])
    local clear = AceGUI:Create("Button")
    clear:SetText(S.CLEAR)
    clear:SetRelativeWidth(W_CLEAR)
    clear:SetCallback("OnClick", function() onClear(view, row) end)
    O.AttachTooltip(clear, S.CLEAR, S.CLEAR_TIP)
    if view.ctx.__renderDisabled then clear:SetDisabled(true) end
    group:AddChild(clear)
    row.group, row.label, row.clear = group, label, clear
    return row
  end

  --- The page's OnShow re-reads its rows and its OnHide stops a capture on it, both re-syncing the
  --- event; hooked once per page, each dispatching by name so a newer minor's handler runs.
  local function hookPanel(ctx)
    local panel = ctx.panel
    if ctx.__keybindSyncHooked or type(panel) ~= "table" or not panel.HookScript then return end
    ctx.__keybindSyncHooked = true
    panel:HookScript("OnShow", function()
      local fn = lib.__keybindOnPanelShow
      if type(fn) == "function" then fn(ctx) end
    end)
    panel:HookScript("OnHide", function()
      local fn = lib.__keybindOnPanelHide
      if type(fn) == "function" then fn(ctx) end
    end)
  end

  local function drawRows(view, bindings)
    for _, b in ipairs(bindings) do
      if type(b) == "table" and type(b.command) == "string" then
        local row = makeRow(view, b)
        view.parent:AddChild(row.group)
        view.rows[#view.rows + 1] = row
        lib.__keybindLive[row] = view.ctx
      else
        local what = type(b) == "table" and b.command or b
        print(lib.STRINGS.ROW_FAILED:format(tostring(what), "a binding's command must be a string"))
      end
    end
  end

  --- Draw the Keybindings rows into `parent` (default: the page's scroll). Answers the row records
  --- `{ command, label, group, slots = { key button }, clear, status, view }`, or nil when degraded.
  --- `spec`: bindings ({ { command, tooltip } }, row order), intro (one host line under the fixed
  --- intro), strings (translations of lib.KEYBIND_STRINGS keys); key and before are the tab's.
  function O.KeybindRows(ctx, spec, parent)
    spec = spec or {}
    parent = parent or O.EnsureScroll(ctx)
    if not O.AceGUI or not parent then return nil end
    local S = mergeStrings(spec.strings)
    local view = { ctx = ctx, panel = ctx.panel, parent = parent, S = S, rows = {} }
    if not lib.__keybindAvailable() then
      textLine(view, S.UNAVAILABLE)
      return nil
    end
    painters(view)
    textLine(view, S.INTRO)
    if type(spec.intro) == "string" and spec.intro ~= "" then textLine(view, spec.intro) end
    O.AddSpacer(parent, O.ROW_VSPACER)

    view.status = O.AceGUI:Create("Label")
    view.status:SetFullWidth(true)
    view.status:SetText("")
    drawRows(view, type(spec.bindings) == "table" and spec.bindings or {})

    view.setLine = O.AceGUI:Create("Label")
    view.setLine:SetFullWidth(true)
    skinLabel(view.setLine, "text.muted")
    skinLabel(view.status, "text.muted")
    parent:AddChild(view.setLine)
    parent:AddChild(view.status)
    view.repaint()

    for _, row in ipairs(view.rows) do
      if type(ctx.refreshers) == "table" then
        ctx.refreshers[#ctx.refreshers + 1] = function()
          view.paintRow(row)
          view.setLine:SetText(setLineText(S))
        end
      end
    end
    hookPanel(ctx)
    lib.__syncKeybindEvents()
    return view.rows
  end
end
