-- testkit/test_skin_switch.lua — the skin-switch test (skinning-§1): change the skin and every painted
-- surface the host declares changes with it (kit revision 50). The probe skin, the spies and the two
-- passes are `skin_switch.lua` beside this file.
--
-- WIRING, in the consumer's `tests/run.lua`, before `Kit.run`:
--
--   Kit.skinSwitch = {
--     owner = "AuraMaster",                       -- the addon folder name, a registered owner
--     skin  = function() return LibStub("LibKa0s-Skin-1.0") end,   -- or the table
--     reset = function() ... end,                 -- optional: run after every surface
--     surfaces = {
--       { name = "the bar's fill",                -- one entry per painted surface
--         build = function() ... return frame end,   -- answers what was painted; its regions, its
--                                                    -- children and a NineSlice are read too
--         paint = function(frame) ... end,        -- optional: the redraw a mock has no listener
--                                                 -- for; a tracked primitive needs none
--         scope = "panel",                        -- optional: "panel" or "fonts", what Ignore keeps
--         companion = function(on) ... end },     -- optional: writes this surface's FromSkin row
--     },
--   }
--   Kit.run{ dir = "tests/", suites = { ..., { name = "test_skin_switch", dir = "tests/_kit/" } } }
--
-- Declared by the pair like every other kit suite (testing-§9). Until the host declares its surfaces
-- `Kit.skinSwitch` is unset and the suite registers ONE declared skip that names the rule, so a
-- re-vendor stays green.
--
-- A surface gets one case with the Scope cleared and its companion on, and, unless `scope` or
-- `companion` excludes it, a second with the Scope ignored and companions off. Coverage is the
-- host's declaration: a surface it does not list is not tested. The audit reads the list.

local Kit = ...
local test, fail = Kit.test, Kit.fail

local RULE = "skinning-§1"

local facts = Kit.skinSwitch

if facts == nil then
  test("skin switch: " .. RULE, nil, "Kit.skinSwitch is not set in the runner, so this repo's "
    .. "painted surfaces are not declared yet. Every addon that adopted skins owes " .. RULE
    .. "; wire Kit.skinSwitch to adopt it")
  return
end

if type(facts) ~= "table" then
  fail("skin switch: Kit.skinSwitch is the consumer-facts table, { owner, skin, surfaces }, not a "
    .. type(facts), 1)
end

--- This file's folder, from its own chunk name, with the vendored layout as the fallback.
local function ownDir()
  local info = debug and debug.getinfo and debug.getinfo(1, "S")
  local dir = info and tostring(info.source or ""):match("^@(.*[/\\])")
  return dir or "tests/_kit/"
end

local W = dofile(ownDir() .. "skin_switch.lua")

local problems = W.factsProblems(facts)
if #problems > 0 then fail("skin switch: Kit.skinSwitch: " .. table.concat(problems, "; "), 1) end

local function case(name, surface, mode)
  test(name, function()
    local problem = W.runSurface(facts, surface, mode)
    if problem then fail("skin switch: " .. problem) end
  end)
end

test("skin switch: the check is falsifiable, a surface that redraws a literal is reported", function()
  local still = { SetVertexColor = function() end }
  local problem = W.runSurface(facts, {
    name = "planted", build = function() return still end,
    paint = function(o) o:SetVertexColor(0.5, 0.5, 0.5) end,
  }, "clear")
  if not problem then fail("skin switch: a surface that never changed passed") end
end)

for _, surface in ipairs(facts.surfaces) do
  case("skin switch: " .. surface.name .. " changes", surface, "clear")
  if not (surface.scope or surface.companion) then
    case("skin switch: " .. surface.name .. " changes with the Scope ignored", surface, "ignored")
  end
end
