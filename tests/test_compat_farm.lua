-- tests/test_compat_farm.lua — core/CompatFarm.lua's farm-session reads (#39, farm spec
-- docs/superpowers/specs/2026-11-27-39-farm-mode-design.md §11.6): LootSourceGUIDs (every GUID of
-- a slot, the tail wiped, the absent API), IsPlayerAFK (a secret or non-boolean answers nil),
-- QuestTitle, and HookLogoutFamily's count. Each case plants the client globals it needs on the mock
-- and puts them back; a secret is the kit's secret double (T.secret) with issecretvalue planted.

local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local NIL = {}
local function with(t, fields, fn)
  local saved = {}
  for k, v in pairs(fields) do
    saved[k] = { v = rawget(t, k) }
    if v == NIL then rawset(t, k, nil) else rawset(t, k, v) end
  end
  local ok, err = pcall(fn)
  for k, s in pairs(saved) do rawset(t, k, s.v) end
  if not ok then error(err, 0) end
end

local C = function() return NS.Compat end
local SECRETS = { issecretvalue = function(v) return T.isSecret(v) end }

test("CompatFarm LootSourceGUIDs: every pair's GUID in order, the tail wiped, 0 without the API", function()
  local out = {}
  with(M, { GetLootSourceInfo = function(slot)
    if slot == 1 then return "Creature-0-1-2-3-11-A", 2, "Creature-0-1-2-3-12-B", 1, "Creature-0-1-2-3-13-C", 3 end
    return "GameObject-0-1-2-3-99-D", 1
  end }, function()
    -- red under: one GUID per slot (Compat.LootSourceGUID's shape), so an AoE slot counts one corpse
    assertEqual(C().LootSourceGUIDs(1, out), 3)
    assertEqual(table.concat(out, ","), "Creature-0-1-2-3-11-A,Creature-0-1-2-3-12-B,Creature-0-1-2-3-13-C")
    assertEqual(C().LootSourceGUIDs(2, out), 1)
    assertEqual(#out, 1, "the previous call's tail is wiped")
    assertEqual(out[1], "GameObject-0-1-2-3-99-D")
  end)
  with(M, { GetLootSourceInfo = function() return nil end }, function()
    assertEqual(C().LootSourceGUIDs(1, out), 0, "a slot with no source")
    assertEqual(next(out), nil)
  end)
  out[1] = "stale"
  with(M, { GetLootSourceInfo = NIL }, function()
    assertEqual(C().LootSourceGUIDs(1, out), 0, "absent API")
    assertEqual(next(out), nil, "absent API still wipes the tail")
  end)
end)

test("CompatFarm IsPlayerAFK: a boolean, nil for a secret, a non-boolean or no API", function()
  with(M, { UnitIsAFK = function(unit) return unit == "player" end }, function()
    assertEqual(C().IsPlayerAFK(), true)
  end)
  with(M, { UnitIsAFK = function() return false end }, function() assertEqual(C().IsPlayerAFK(), false) end)
  with(M, { UnitIsAFK = function() return 1 end }, function() assertEqual(C().IsPlayerAFK(), nil, "not a boolean") end)
  with(M, SECRETS, function()
    with(M, { UnitIsAFK = function() return T.secret(true) end }, function()
      assertEqual(C().IsPlayerAFK(), nil, "a secret changes nothing")
    end)
  end)
  with(M, { UnitIsAFK = NIL }, function() assertEqual(C().IsPlayerAFK(), nil, "absent API") end)
end)

test("CompatFarm QuestTitle: a plain non-empty title, else nil", function()
  local titles = { [101] = "The Ore Thief", [102] = "", [103] = 7 }
  with(M, { C_QuestLog = { GetTitleForQuestID = function(id) return titles[id] end } }, function()
    assertEqual(C().QuestTitle(101), "The Ore Thief")
    assertEqual(C().QuestTitle(102), nil, "empty")
    assertEqual(C().QuestTitle(103), nil, "not a string")
    assertEqual(C().QuestTitle(104), nil, "unknown")
    assertEqual(C().QuestTitle(nil), nil, "no id")
    titles[105] = T.secret("Hidden")
    with(M, SECRETS, function() assertEqual(C().QuestTitle(105), nil, "a secret") end)
  end)
  with(M, { C_QuestLog = NIL }, function() assertEqual(C().QuestTitle(101), nil, "absent API") end)
end)

test("CompatFarm HookLogoutFamily: intent on Logout/Quit/ForceQuit, cancel on CancelLogout/ReloadUI/C_UI.Reload", function()
  -- Compat.HookSecure resolves its target BY NAME through the real _G (tests/test_compat.lua's
  -- HookSecure case), so the six names go on _G; hooksecurefunc and C_UI are read bare (the mock).
  local hooked = {}
  local function hook(a, b, fn)
    if type(a) == "table" then hooked[#hooked + 1] = "C_UI." .. b .. "=" .. tostring(fn)
    else hooked[#hooked + 1] = a .. "=" .. tostring(b) end
  end
  local function f() end
  local names = { Logout = f, Quit = f, ForceQuit = f, CancelLogout = f, ReloadUI = f }
  local intent, cancel = function() end, function() end
  local function run(globals, ui, expect, why)
    with(_G, globals, function()
      with(M, { hooksecurefunc = hook, C_UI = ui }, function()
        assertEqual(C().HookLogoutFamily(intent, cancel), expect, why)
      end)
    end)
  end
  run(names, { Reload = f }, 6, "all six installed")
  local want = { "Logout=" .. tostring(intent), "Quit=" .. tostring(intent), "ForceQuit=" .. tostring(intent),
                 "CancelLogout=" .. tostring(cancel), "ReloadUI=" .. tostring(cancel), "C_UI.Reload=" .. tostring(cancel) }
  assertEqual(table.concat(hooked, ","), table.concat(want, ","), "each to its own callback")
  run(names, NIL, 5, "an absent C_UI installs five")
  names.Quit = NIL
  run(names, { Reload = f }, 5, "a missing global is skipped, presence-gated")
  assertTrue(#hooked == 16, "one hook per installed member, nothing twice")
end)
