-- tests/test_skin_picker.lua — the first-run skin picker on this addon's seam (core/SkinSetup.lua;
-- LibKa0s OptionsSkinPicker 1, LibKa0s#64).
--
-- What this addon owes the picker, and nothing the library pins itself: the spec it hands
-- O.SkinPicker (its owner, its two seams, the Skin tab's page and key, the eye, the close); WHEN it
-- shows (a profile whose `pickerSeen` is false, once after login and after every profile event,
-- never while the addon stands down, held through combat); and that only the player's close marks
-- it seen. The trigger cases spy on O.SkinPicker; the last cases drive the library's real window.
--
-- After test_skin_overrides; leaves the harness on `Default`, the picker down and marked unseen.

local T = _G.LH_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local O = NS.Options
local PATH = "settings.appearance.pickerSeen"

--- Run `fn(calls)` with O.SkinPicker replaced by a recorder: each call's spec, in order.
local function spying(fn)
  local real = O.SkinPicker
  local calls = {}
  O.SkinPicker = function(spec)
    calls[#calls + 1] = spec
    return { spy = true }
  end
  local ok, err = pcall(fn, calls)
  O.SkinPicker = real
  if not ok then error(err, 0) end
end

--- The picker down (quietly) and this profile's key back to false, whatever `fn` raised.
local function clean(fn)
  return function()
    NS.HideSkinPicker()
    NS.Schema:Set(PATH, false)
    local ok, err = pcall(fn)
    NS.HideSkinPicker()
    if NS.db:GetCurrentProfile() ~= "Default" then NS.db:SetProfile("Default") end
    NS.Schema:Set(PATH, false)
    if not ok then error(err, 0) end
  end
end

local function quietly(fn)
  local cf = mocks.DEFAULT_CHAT_FRAME
  local add = cf.AddMessage
  cf.AddMessage = function() end
  local ok, err = pcall(fn)
  cf.AddMessage = add
  if not ok then error(err, 0) end
end

-- ── the key and the spec ─────────────────────────────────────────────────────────────────────

test("Skin picker: pickerSeen defaults to false, a skip-render row on the Skin tab", function()
  -- red under: a default of true (no profile would ever show it), or a row that draws itself.
  assertEqual(NS.defaults.profile.settings.appearance.pickerSeen, false)
  local row = NS.Schema:FindRow(PATH)
  assertTrue(row ~= nil, PATH .. " is not a schema row")
  assertEqual(row.type, "bool")
  assertEqual(row.group, "Appearance")
  assertTrue(row.skipRender == true, "nothing draws it")
end)

test("Skin picker: the spec names this owner, its seams, the Skin tab and the eye", function()
  -- red under: a set that is not the write seam (a pick would never reach the profile), or a page
  -- or tab key O.SelectTab does not know (the gear would open the panel on the wrong tab).
  local spec = NS.SkinPickerSpec()
  assertEqual(spec.owner, "LootHistory")
  assertTrue(rawequal(spec.get, NS.SkinChoice), "get is the read seam")
  assertTrue(rawequal(spec.set, NS.WriteSkinChoice), "set is the write seam")
  assertEqual(spec.page, "General")
  assertEqual(spec.tab, "Appearance", "the Skin tab's key")
  assertTrue(NS.Panel.general ~= nil and rawequal(O.__panelFor("General"), NS.Panel.general),
    "\"General\" is the page O.SelectTab finds")
  assertEqual(type(spec.onPreview), "function")
  assertEqual(type(spec.onClose), "function")
end)

-- ── when it shows ────────────────────────────────────────────────────────────────────────────

test("Skin picker: an unseen profile shows it; a seen one does not", clean(function()
  spying(function(calls)
    NS.MaybeShowSkinPicker()
    assertEqual(#calls, 1, "pickerSeen false: the picker shows")
    assertEqual(calls[1].owner, "LootHistory")
    NS.Schema:Set(PATH, true)
    NS.MaybeShowSkinPicker()
    assertEqual(#calls, 1, "pickerSeen true: it does not show again")
  end)
end))

test("Skin picker: it shows once after login, two seconds in, on the once-per-session path", clean(function()
  -- red under: dropping the call from addon:OnEnterWorld, or making it a C_Timer.After the
  -- stand-down cannot cancel.
  local after, done = NS.After, NS.State.cleanupDone
  local fuses = {}
  NS.After = function(delay, fn) fuses[#fuses + 1] = { delay = delay, fn = fn } end
  NS.State.cleanupDone = false
  local ok, err = pcall(function()
    NS.addon:OnEnterWorld()
    local fuse
    for _, f in ipairs(fuses) do if f.delay == 2 then fuse = f end end
    assertTrue(fuse ~= nil, "OnEnterWorld lit no two-second fuse")
    spying(function(calls)
      fuse.fn()
      assertEqual(#calls, 1, "the login fuse shows the picker")
    end)
  end)
  NS.After, NS.State.cleanupDone = after, done
  if not ok then error(err, 0) end
end))

test("Skin picker: in combat a start waits for PLAYER_REGEN_ENABLED, once", clean(function()
  local real = mocks.InCombatLockdown
  mocks.InCombatLockdown = function() return true end
  local ok, err = pcall(function()
    spying(function(calls)
      assertEqual(NS.MaybeShowSkinPicker(), nil)
      NS.MaybeShowSkinPicker()
      assertEqual(#calls, 0, "nothing shows in combat")
      mocks.InCombatLockdown = function() return false end
      mocks.__fireEvent("PLAYER_REGEN_ENABLED")
      assertEqual(#calls, 1, "the combat edge shows it, once for two held starts")
      mocks.__fireEvent("PLAYER_REGEN_ENABLED")
      assertEqual(#calls, 1, "the one-shot target is gone")
    end)
  end)
  mocks.InCombatLockdown = real
  if not ok then error(err, 0) end
end))

test("Skin picker: a held start is dropped by the stand-down's HideSkinPicker", clean(function()
  local real = mocks.InCombatLockdown
  mocks.InCombatLockdown = function() return true end
  local ok, err = pcall(function()
    spying(function(calls)
      NS.MaybeShowSkinPicker()
      NS.HideSkinPicker()
      mocks.InCombatLockdown = function() return false end
      mocks.__fireEvent("PLAYER_REGEN_ENABLED")
      assertEqual(#calls, 0, "a dropped start must not fire on the combat edge")
    end)
  end)
  mocks.InCombatLockdown = real
  if not ok then error(err, 0) end
end))

test("Skin picker: never while the addon is switched off", clean(function()
  quietly(function()
    spying(function(calls)
      NS.Schema:Set("settings.enabled", false)
      local ok, err = pcall(function()
        assertTrue(NS.IsStoodDown(), "the switch stood the addon down")
        NS.MaybeShowSkinPicker()
        assertEqual(#calls, 0, "a disabled addon shows no picker")
      end)
      NS.Schema:Set("settings.enabled", true)
      if not ok then error(err, 0) end
    end)
  end)
end))

test("Skin picker: a new profile and a reset profile show it again", clean(function()
  -- Both start from the defaults, pickerSeen false (owner decision D6). red under: no call on the
  -- profile adopt path, or one before the latch re-reads the new profile's switch.
  local db = NS.db
  NS.Schema:Set(PATH, true)
  quietly(function()
    spying(function(calls)
      db:SetProfile("PickerProbe")
      assertEqual(#calls, 1, "a new profile shows the picker")
      NS.Schema:Set(PATH, true)
      db:ResetProfile()
      assertEqual(#calls, 2, "a reset profile shows it again")
      NS.Schema:Set(PATH, true)
      db:SetProfile("Default")
      assertEqual(#calls, 2, "back on a profile that has seen it: no picker")
    end)
  end)
  if db.DeleteProfile then pcall(db.DeleteProfile, db, "PickerProbe", true) end
end))

-- ── the real window ──────────────────────────────────────────────────────────────────────────

test("Skin picker: the player's close marks it seen; this addon's own hide does not", clean(function()
  local f = NS.MaybeShowSkinPicker()
  assertTrue(f ~= nil and f:IsShown(), "the library's picker did not show")
  NS.HideSkinPicker()
  assertEqual(NS.Schema:Get(PATH), false, "a stand-down hide is not the player's close")
  f = NS.MaybeShowSkinPicker()
  assertTrue(f ~= nil and f:IsShown(), "it shows again while unseen")
  O.HideSkinPicker()
  assertEqual(NS.Schema:Get(PATH), true, "the player's close sets pickerSeen")
  assertEqual(NS.MaybeShowSkinPicker(), nil, "and it does not show again")
end))

test("Skin picker: a profile that has seen it takes a shown picker down, unmarked", clean(function()
  local f = NS.MaybeShowSkinPicker()
  assertTrue(f ~= nil and f:IsShown())
  NS.db.profile.settings.appearance.pickerSeen = true
  NS.MaybeShowSkinPicker()
  assertFalse(f:IsShown(), "the picker stayed up on a profile that has seen it")
end))

test("Skin picker: the eye opens the History window in test mode", clean(function()
  local BT, B = NS.BrowserTable, NS.Browser
  local ok, err = pcall(function()
    quietly(function() NS.SkinPickerSpec().onPreview() end)
    assertTrue(BT.testMode == true, "the eye did not start test mode")
    local f = B:GetWindow()
    assertTrue(f ~= nil and f:IsShown(), "the eye did not show the History window")
    B:Hide()
    quietly(function() NS.SkinPickerSpec().onPreview() end)
    assertTrue(B:GetWindow():IsShown(), "with test mode already on, the eye still shows the window")
  end)
  quietly(function() if BT.testMode then BT:SetTestMode(false) end end)
  B:Hide()
  if not ok then error(err, 0) end
end))
