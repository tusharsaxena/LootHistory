-- tests/test_skin_picker.lua — the first-run skin picker on this addon's seam (core/SkinSetup.lua;
-- LibKa0s OptionsSkinPicker 1, LibKa0s#64).
--
-- What this addon owes the picker, and nothing the library pins itself: the spec it hands
-- O.SkinPicker (its owner, its two seams, the Skin tab's page and key, the eye, the close); WHEN it
-- shows (a profile whose `pickerSeen` is false, once after login and after every profile event,
-- never while the addon stands down, held through combat); and that only the player's close marks
-- it seen. The trigger cases spy on O.SkinPicker; the last cases drive the library's real window.
--
-- And, since the library's PK-02 rework (a pick previews, Apply saves, one window across addons):
-- the title naming this addon; a pick worn but unsaved and Apply saving it through
-- NS.WriteSkinChoice; the close control putting the old skin back unsaved; the gear saving and
-- opening General on its Skin tab; each marking the picker seen; behind another Ka0s addon's picker
-- (a probe owner on a second Options instance sharing the library table) a queued nil, "queued",
-- shown when that one closes, dismissed seen and skinned by its "Apply to all Ka0s addons", and taken
-- out unseen by this addon's own hide; and a profile switch with a preview pending wearing the new
-- profile's skin (NS.OnProfileEvent takes the picker down before applying it).
--
-- After test_skin_overrides; leaves the harness on `Default`, the picker down and marked unseen.

local T = _G.LH_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local O = NS.Options
local PATH = "settings.appearance.pickerSeen"

-- Every frame built from here on, by parent, so a case can reach the picker list's rows: the
-- shared mock's frames do not list their children (only the paint recorder's do), and the picker
-- builds its window, rows included, on its first show, which is in this file.
local childrenOf = setmetatable({}, { __mode = "k" })
do
  local create = mocks.CreateFrame
  mocks.CreateFrame = function(frameType, name, parent, ...)
    local f = create(frameType, name, parent, ...)
    if parent ~= nil then
      local list = childrenOf[parent] or {}
      childrenOf[parent] = list
      list[#list + 1] = f
    end
    return f
  end
end

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

-- ── preview, Apply, close and the gear (PK-02: a pick previews, Apply saves) ─────────────────

local Skin = mocks.LibStub("LibKa0s-Skin-1.0")
local OptionsLib = mocks.LibStub("LibKa0s-Options-1.0")
local OWNER = "LootHistory"
local OTHER = "LHPickerProbe"
local PS = dofile("tests/panel_support.lua")

--- The skin the Skin major wears for this addon now, and the one its profile stores.
local function worn() return select(2, Skin:GetChoice(OWNER)) end
local function stored() return select(2, NS.SkinChoice()) end

--- Open the window's list and click the row for skin `key`, as the player does.
local function pickRow(f, key)
  f.dd:__fire("OnClick")
  local hit = false
  for _, r in ipairs(childrenOf[f.list] or {}) do
    if r.key == key then r:__fire("OnClick"); hit = true end
  end
  assertTrue(hit, "no row for " .. key)
end

--- Run `fn` on this addon's real picker, the skin put back on Ka0s Default (stored and worn) and any
--- probe owner and its queue entry gone, whatever `fn` raised.
local function onWindow(fn)
  return clean(function()
    local ok, err = pcall(function()
      quietly(function()
        local f = NS.MaybeShowSkinPicker()
        assertTrue(f ~= nil and f:IsShown(), "the library's picker did not show")
        fn(f)
      end)
    end)
    NS.HideSkinPicker()
    local q = OptionsLib.__pickerQueue
    if q then
      if q.current and q.current.owner == OTHER then q.current = nil end
      for i = #(q.waiting or {}), 1, -1 do
        if q.waiting[i].owner == OTHER or q.waiting[i].owner == OWNER then table.remove(q.waiting, i) end
      end
    end
    Skin.owners[OTHER] = nil
    NS.WriteSkinChoice("ka0s", "ka0s")
    Skin:SetChoice(OWNER, "ka0s", "ka0s")
    mocks.__fireTimers()
    if not ok then error(err, 0) end
  end)
end

test("Skin picker: the title names this addon", onWindow(function(f)
  -- red under: the old fixed TITLE (the window could be any addon's), or no owner label passed.
  assertEqual(f.title:GetText(), "Choose a skin for " .. NS.BRAND)
end))

test("Skin picker: a pick previews, unsaved; Apply saves it and marks the picker seen", onWindow(function(f)
  -- red under: a spec.set that is not the write seam (Apply would save nothing), or an onClose
  -- that does not write pickerSeen (the picker would come back on the next login).
  pickRow(f, "obsidian")
  assertEqual(worn(), "obsidian", "the pick is worn at once")
  assertEqual(stored(), "ka0s", "a pick alone writes nothing to the profile")
  assertEqual(NS.Schema:Get(PATH), false, "a pick does not end the showing")
  assertTrue(f:IsShown(), "the window stays up for Apply")
  f.apply:__fire("OnClick")
  assertFalse(f:IsShown(), "Apply closes the window")
  assertEqual(stored(), "obsidian", "Apply saves through NS.WriteSkinChoice")
  assertEqual(worn(), "obsidian")
  assertEqual(NS.Schema:Get(PATH), true, "Apply marks the picker seen")
end))

test("Skin picker: the close control puts the old skin back, saves nothing, and marks it seen", onWindow(function(f)
  pickRow(f, "obsidian")
  assertTrue(f.close ~= nil, "the window has a close control")
  f.close:__fire("OnClick")
  assertFalse(f:IsShown(), "the close control closes the window")
  assertEqual(worn(), "ka0s", "closing puts back the skin the window opened with")
  assertEqual(stored(), "ka0s", "and writes nothing")
  assertEqual(NS.Schema:Get(PATH), true, "a close by the player still counts as seen")
end))

test("Skin picker: the gear saves the pick and opens General on its Skin tab", onWindow(function(f)
  -- red under: a gear that opens the landing page (no page key) or another tab, or one that drops
  -- the pending pick.
  local realOpen, opened = O.OpenOptionsPanel, {}
  O.OpenOptionsPanel = function(page) opened[#opened + 1] = page; return realOpen(page) end
  local ok, err = pcall(function()
    pickRow(f, "obsidian")
    f.settings:__fire("OnClick")
  end)
  O.OpenOptionsPanel = realOpen
  if not ok then error(err, 0) end
  assertEqual(#opened, 1, "the gear opens the settings once")
  assertEqual(opened[1], "General", "on this addon's General page, not the landing page")
  assertEqual(NS.Panel.general.activeTab, "Appearance", "on its Skin tab")
  assertFalse(f:IsShown(), "the gear closes the window")
  assertEqual(stored(), "obsidian", "the gear saves the pending pick")
  assertEqual(NS.Schema:Get(PATH), true, "and marks the picker seen")
  PS.homeTab(NS.Panel.general)
end))

-- ── one window across Ka0s addons (PK-02) ────────────────────────────────────────────────────

--- A second Ka0s addon on the same client: a skin owner with its own store and its own Options
--- instance, which shares this addon's Options library table (and so its picker queue).
local function probe()
  local store = { source = "ka0s", skin = "ka0s", closed = 0 }
  Skin:RegisterOwner(OTHER, {
    label = "Probe Addon",
    get = function() return { source = store.source, skin = store.skin } end,
    set = function(src, sk) store.source, store.skin = src, sk end,
  })
  local inst = OptionsLib:New({
    parentTitle = "Picker Probe", mainPanelName = "LHPickerProbeMain", addonName = OTHER,
    print = function() end, get = function() end, set = function() end, applyDefault = function() end,
    rowsForPage = function() return {} end, allRows = function() return {} end,
  })
  local spec = {
    owner = OTHER,
    get = function() return { source = store.source, skin = store.skin } end,
    set = function(src, sk) store.source, store.skin = src, sk end,
    onClose = function() store.closed = store.closed + 1 end,
  }
  return inst, spec, store
end

test("Skin picker: behind another addon's picker it queues, answers nil, \"queued\", then shows", onWindow(function(mine)
  -- red under: a second window over the first (two pickers at once), or a host that reads the
  -- queued answer as a shown picker.
  NS.HideSkinPicker()
  local inst, spec = probe()
  local theirs = inst.SkinPicker(spec)
  assertTrue(theirs ~= nil and theirs:IsShown(), "the other addon's picker is up")
  local f, why = NS.MaybeShowSkinPicker()
  assertEqual(f, nil, "no frame while another addon's picker is up")
  assertEqual(why, "queued")
  assertFalse(mine:IsShown(), "this addon's window stays hidden")
  assertEqual(NS.Schema:Get(PATH), false, "queued is not seen")
  inst.HideSkinPicker()
  assertTrue(mine:IsShown(), "the other picker's close shows this addon's next")
end))

test("Skin picker: the other addon's Apply to all dismisses this queued picker, seen and skinned", onWindow(function(mine)
  NS.HideSkinPicker()
  local inst, spec, store = probe()
  local theirs = inst.SkinPicker(spec)
  assertTrue(select(2, NS.MaybeShowSkinPicker()) == "queued", "this addon's picker queued")
  pickRow(theirs, "obsidian")
  assertTrue(theirs.applyAll:IsShown(), "two owners: Apply to all is offered")
  theirs.applyAll:__fire("OnClick")
  assertFalse(theirs:IsShown(), "Apply to all closes the other addon's window")
  assertFalse(mine:IsShown(), "and never shows this addon's")
  assertEqual(store.skin, "obsidian", "the other addon saved its pick")
  assertEqual(stored(), "obsidian", "this addon got the same skin, through its write seam")
  assertEqual(worn(), "obsidian")
  assertEqual(NS.Schema:Get(PATH), true, "this addon's onClose ran: the picker counts as seen")
  assertEqual(NS.MaybeShowSkinPicker(), nil, "and it does not show again")
end))

test("Skin picker: this addon's own hide takes a queued picker out of the queue, unseen", onWindow(function(mine)
  NS.HideSkinPicker()
  local inst, spec = probe()
  inst.SkinPicker(spec)
  assertTrue(select(2, NS.MaybeShowSkinPicker()) == "queued")
  NS.HideSkinPicker()
  inst.HideSkinPicker()
  assertFalse(mine:IsShown(), "a queued picker this addon took down does not show later")
  assertEqual(NS.Schema:Get(PATH), false, "and was never seen")
end))

-- ── a profile event with a preview pending ───────────────────────────────────────────────────

test("Skin picker: a profile switch with a preview pending wears the new profile's skin", onWindow(function()
  -- The picker's dismissal puts back the skin its window opened with, which on a profile switch is
  -- the OLD profile's. red under: taking the picker down after the new profile's skin is applied
  -- (the old profile's skin would be worn over the new one's).
  local db = NS.db
  NS.HideSkinPicker()
  db:SetProfile("PickerProbe")
  NS.Schema:Set(PATH, true)
  NS.WriteSkinChoice("ka0s", "azeroth")
  NS.ApplySkinChoice()
  NS.HideSkinPicker()
  db:SetProfile("Default")
  assertEqual(stored(), "ka0s")
  local f = NS.MaybeShowSkinPicker()
  assertTrue(f ~= nil and f:IsShown(), "Default has not seen the picker")
  pickRow(f, "obsidian")
  assertEqual(worn(), "obsidian")
  db:SetProfile("PickerProbe")
  assertFalse(f:IsShown(), "a profile that has seen it takes the picker down")
  assertEqual(worn(), "azeroth", "the new profile's skin is worn, not the old one's")
  db:SetProfile("Default")
  assertEqual(worn(), "ka0s", "and back on Default, its own stored skin")
  assertEqual(stored(), "ka0s", "the preview was never saved")
  if db.DeleteProfile then pcall(db.DeleteProfile, db, "PickerProbe", true) end
end))
