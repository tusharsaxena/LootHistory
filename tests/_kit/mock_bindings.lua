-- testkit/mock_bindings.lua — the kit's opt-in binding mock (revision 42): the client's key-binding
-- API, for a suite that drives LibKa0s-Options-1.0's Keybindings tab or an addon's Bindings.xml
-- commands.
--
-- Returns an INSTALLER, called on a finished mock:
--
--   local M = base()
--   dofile("tests/_kit/mock_bindings.lua")(M)                                 -- the binding API
--   dofile("tests/_kit/mock_bindings.lua")(M, { clientChordHelpers = true })  -- and the chord helpers
--
-- OPT-IN, AND A FILE OF ITS OWN, as mock_ids.lua is: mock_base.lua sits close to layout-§1's cap,
-- and an addon with no binding has no reason to carry the surface. Through revision 41 the base
-- answered none of these names, and a frame method of the same shape answered with the frame.
--
-- WHAT IS FILLED. Every public name below is set only where M does not already have it, so a
-- consumer's own fixture keeps answering. The `__binding*` seams are always (re)installed: they are
-- the mock's state, and a consumer's leftover table under the same name would be read as truth.
--
-- THE MODEL (ported from QuickComms' harness, which carried it first):
--
--   M.__bindingSets   { [1] = { actions = {}, keys = {} }, [2] = { ... } }: what each saved set holds
--   M.__bindingLive   the LIVE tables every call reads and writes, a copy of a set until saved
--   M.__bindingSet    the current set (default 1, ACCOUNT_BINDINGS)
--   actions[key]      the command a key runs
--   keys[command]     an ARRAY of the command's keys, in bind order (slot 1, slot 2, ...)
--
--   GetBindingKey(command)   every key in order, or nil when none
--   GetBindingAction(key)    the command, or "" for a free key (the client's answer)
--   SetBinding(key, cmd)     refused in combat: appends { key, cmd } to M.__bindingRefusals and
--                            answers false. Refused once when M.__bindingFailNext == key (the seam
--                            clears). Otherwise a nil cmd unbinds the key; a cmd takes the key from
--                            the action that had it (which may be left keyless) and appends it to
--                            its own array. Appends { key, cmd } to M.__bindingWrites and fires
--                            UPDATE_BINDINGS through M.__fire unless M.__bindingsFireOnSet == false.
--                            Answers true.
--   SaveBindings(set)        refused in combat ({ save = set } in M.__bindingRefusals). Otherwise
--                            copies the live tables into M.__bindingSets[set], makes `set` current
--                            (the client's character-specific toggle works this way), appends
--                            `set` to M.__savedBindingSets and fires UPDATE_BINDINGS.
--   LoadBindings(set)        makes `set` current and live (an unsaved change is discarded), fires.
--   GetCurrentBindingSet()   M.__bindingSet
--   GetBindingText(key)      the key itself
--   GetBindingName(cmd)      M["BINDING_NAME_" .. cmd], else _G's, else cmd (BindingUtil.lua)
--
--   Every UPDATE_BINDINGS the mock fires counts in M.__bindingFires, so a suite can assert that a
--   repaint was asked for without registering a frame of its own.
--
-- CONSTANTS, where missing: NOT_BOUND, KEY_BOUND, KEY_UNBOUND_ERROR, ACCOUNT_BINDINGS (1),
-- CHARACTER_BINDINGS (2), and Enum.BindingSet { Default = 0, Account = 1, Character = 2 } merged
-- into M.Enum (created if absent) member by member, never replacing one already there.
--
-- MODIFIERS. IsAltKeyDown / IsControlKeyDown / IsShiftKeyDown / IsMetaKeyDown read M.__modifiers;
-- M.setModifiers{ alt =, ctrl =, shift =, meta = } sets all four (a missing field is false).
--
-- SEEDING. M.bindKey(key, cmd) binds into the live tables AND the current set without recording or
-- firing, for a suite's starting state. M.clearBindings() empties both sets, the live tables and
-- every log.
--
-- CHORD HELPERS. With `opts.clientChordHelpers = true` the installer adds the client's
-- GetConvertedKeyOrButton, IsKeyPressIgnoredForBinding and CreateKeyChordStringUsingMetaKeyState
-- (BindingUtil.lua's ALT-CTRL-SHIFT-META- order). They are ABSENT by default, so a suite exercises
-- the library's bundled fallback unless it asks for the client's.

return function(M, opts)
  opts = opts or {}

  local function fill(name, value)
    if M[name] == nil then M[name] = value end
  end

  local function newSet() return { actions = {}, keys = {} } end
  local function copySet(src)
    local out = newSet()
    for k, v in pairs(src.actions) do out.actions[k] = v end
    for cmd, list in pairs(src.keys) do
      local l = {}
      for i, k in ipairs(list) do l[i] = k end
      out.keys[cmd] = l
    end
    return out
  end

  M.__bindingSets = { [1] = newSet(), [2] = newSet() }
  M.__bindingLive = newSet()
  M.__bindingSet = 1
  M.__bindingRefusals, M.__bindingWrites, M.__savedBindingSets = {}, {}, {}
  M.__bindingFires = 0
  M.__bindingFailNext = nil
  M.__bindingsFireOnSet = nil

  local function fireUpdate()
    M.__bindingFires = M.__bindingFires + 1
    if M.__fire then M.__fire("UPDATE_BINDINGS") end
  end

  local function inCombat()
    return type(M.InCombatLockdown) == "function" and M.InCombatLockdown() == true
  end

  local function unbindKey(set, key)
    local prev = set.actions[key]
    if prev == nil then return end
    set.actions[key] = nil
    local list = set.keys[prev]
    if not list then return end
    for i = #list, 1, -1 do
      if list[i] == key then table.remove(list, i) end
    end
    if #list == 0 then set.keys[prev] = nil end
  end

  local function bindInto(set, key, command)
    unbindKey(set, key)
    if command == nil then return end
    set.actions[key] = command
    local list = set.keys[command] or {}
    list[#list + 1] = key
    set.keys[command] = list
  end

  fill("GetBindingKey", function(command)
    local list = M.__bindingLive.keys[command]
    if not list or #list == 0 then return nil end
    return unpack(list)
  end)
  fill("GetBindingAction", function(key) return M.__bindingLive.actions[key] or "" end)
  fill("SetBinding", function(key, command)
    if inCombat() then
      M.__bindingRefusals[#M.__bindingRefusals + 1] = { key, command }
      return false
    end
    if M.__bindingFailNext ~= nil and M.__bindingFailNext == key then
      M.__bindingFailNext = nil
      return false
    end
    bindInto(M.__bindingLive, key, command)
    M.__bindingWrites[#M.__bindingWrites + 1] = { key, command }
    if M.__bindingsFireOnSet ~= false then fireUpdate() end
    return true
  end)
  fill("SaveBindings", function(set)
    if inCombat() then
      M.__bindingRefusals[#M.__bindingRefusals + 1] = { save = set }
      return
    end
    M.__bindingSets[set] = copySet(M.__bindingLive)
    M.__bindingSet = set
    M.__savedBindingSets[#M.__savedBindingSets + 1] = set
    fireUpdate()
  end)
  fill("GetCurrentBindingSet", function() return M.__bindingSet end)
  fill("LoadBindings", function(set)
    M.__bindingSets[set] = M.__bindingSets[set] or newSet()
    M.__bindingLive = copySet(M.__bindingSets[set])
    M.__bindingSet = set
    fireUpdate()
  end)
  fill("GetBindingText", function(key) return key end)
  fill("GetBindingName", function(command)
    local name = "BINDING_NAME_" .. tostring(command)
    local v = M[name]
    if v == nil then v = rawget(_G, name) end
    if v ~= nil then return v end
    return command
  end)

  fill("NOT_BOUND", "Not Bound")
  fill("KEY_BOUND", "Key Bound Successfully")
  fill("KEY_UNBOUND_ERROR", "|cffff0000%s Function is Now Unbound!|r")
  fill("ACCOUNT_BINDINGS", 1)
  fill("CHARACTER_BINDINGS", 2)
  if type(M.Enum) ~= "table" then M.Enum = {} end
  if type(M.Enum.BindingSet) ~= "table" then M.Enum.BindingSet = {} end
  for k, v in pairs({ Default = 0, Account = 1, Character = 2 }) do
    if M.Enum.BindingSet[k] == nil then M.Enum.BindingSet[k] = v end
  end

  if type(M.__modifiers) ~= "table" then
    M.__modifiers = { alt = false, ctrl = false, shift = false, meta = false }
  end
  fill("IsAltKeyDown", function() return M.__modifiers.alt == true end)
  fill("IsControlKeyDown", function() return M.__modifiers.ctrl == true end)
  fill("IsShiftKeyDown", function() return M.__modifiers.shift == true end)
  fill("IsMetaKeyDown", function() return M.__modifiers.meta == true end)
  fill("setModifiers", function(t)
    t = t or {}
    M.__modifiers = { alt = t.alt == true, ctrl = t.ctrl == true, shift = t.shift == true,
                      meta = t.meta == true }
  end)

  fill("bindKey", function(key, command)
    bindInto(M.__bindingLive, key, command)
    M.__bindingSets[M.__bindingSet] = copySet(M.__bindingLive)
  end)
  fill("clearBindings", function()
    M.__bindingSets = { [1] = newSet(), [2] = newSet() }
    M.__bindingLive = newSet()
    M.__bindingRefusals, M.__bindingWrites, M.__savedBindingSets = {}, {}, {}
    M.__bindingFires = 0
    M.__bindingFailNext = nil
  end)

  if opts.clientChordHelpers then
    local BUTTONS = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3" }
    -- BindingUtil.lua:21-25: the modifier keys and UNKNOWN only. BUTTON1 / BUTTON2 are refused by
    -- the binding page's click handler (:90-92), so a caller must refuse them itself.
    local IGNORED = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true,
                      RALT = true, LMETA = true, RMETA = true, UNKNOWN = true }
    local META = { LALT = true, RALT = true, LCTRL = true, RCTRL = true, LSHIFT = true,
                   RSHIFT = true, LMETA = true, RMETA = true }
    fill("GetConvertedKeyOrButton", function(key)
      if BUTTONS[key] then return BUTTONS[key] end
      local n = type(key) == "string" and key:match("^Button(%d+)$")
      if n then return "BUTTON" .. n end
      return key
    end)
    fill("IsKeyPressIgnoredForBinding", function(key) return IGNORED[key] == true end)
    fill("CreateKeyChordStringUsingMetaKeyState", function(key)
      local chord = {}
      if M.IsAltKeyDown() then chord[#chord + 1] = "ALT" end
      if M.IsControlKeyDown() then chord[#chord + 1] = "CTRL" end
      if M.IsShiftKeyDown() then chord[#chord + 1] = "SHIFT" end
      if M.IsMetaKeyDown() then chord[#chord + 1] = "META" end
      if not META[key] then chord[#chord + 1] = key end
      return table.concat(chord, "-")
    end)
  end

  return M
end
