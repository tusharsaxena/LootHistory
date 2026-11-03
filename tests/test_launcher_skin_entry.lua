-- tests/test_launcher_skin_entry.lua — the launcher menu offers "Open skin selector" (SF-FIX, LibKa0s Launcher minor 6).
-- The library offers the entry only when the host passes openSkinPicker, so the descriptor must carry it
-- and it must reach this addon's picker verb.

local T = _G.LH_TEST
local test, assertTrue = T.test, T.assertTrue

test("launcher descriptor passes openSkinPicker, which runs the skin verb", function()
  local f = assert(io.open("core/LauncherSetup.lua", "r"))
  local src = f:read("*a")
  f:close()
  assertTrue(src:find("openSkinPicker%s*=%s*function") ~= nil, "openSkinPicker is passed")
  assertTrue(src:find("RunSkinVerb") ~= nil, "and it runs RunSkinVerb")
end)

test("mode strips pass sim or onEnd, so the right-click menu has something to end (SF-F1)", function()
  local f0 = assert(io.open("core/WidgetsSetup.lua", "r"))
  local src0 = f0:read("*a")
  f0:close()
  assertTrue(src0:find("onEnd") ~= nil or src0:find("sim%s*=") ~= nil, "core/WidgetsSetup.lua passes sim or onEnd")
end)
