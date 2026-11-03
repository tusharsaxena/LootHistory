-- tests/test_skin_surfaces.lua — the close of the skin-switch declaration (tests/skin_surfaces.lua).
--
-- The kit's suite flips the surfaces and tests/skin_surfaces.lua keeps the last fixture standing
-- between them, so this suite, right after it, takes that fixture down. And it holds the declaration
-- to the addon: every window this addon draws has surfaces in the list, so dropping one goes red.

local T = _G.LH_TEST
local test, assertTrue = T.test, T.assertTrue

local facts = T.skinSwitch

test("skin surfaces: the last fixture comes down and the paint recorder with it", function()
  facts.close()
  assertTrue(rawequal(T.mocks.CreateFrame, facts.baseCreateFrame()), "the paint recorder stayed installed")
end)

test("skin surfaces: the degraded facade's BarBorder answers the three it is handed", function()
  local S = dofile("tests/degraded_env.lua")().Skin
  local style, show, size = S.BarBorder("Solid", false, 3, true)
  assertTrue(style == "Solid" and show == false and size == 3, "the stored border was not answered")
end)

test("skin surfaces: every window and tab this addon draws is declared", function()
  local names = {}
  for _, s in ipairs(facts.surfaces) do names[#names + 1] = s.name end
  local all = "\n" .. table.concat(names, "\n") .. "\n"
  for _, word in ipairs({ "window's edge", "export modal", "table header", "row menu", "KPI", "Timeline",
                          "Holdings", "AH table", "debug console", "export copy window", "test strip" }) do
    assertTrue(all:find(word, 1, true) ~= nil, "no declared surface names " .. word)
  end
end)
