-- testkit/test_skin_values.lua — the typed-value gate (skinning-§1, anti-pattern #107): no color or
-- texture a host draws is a value the skin cannot reach (kit revision 50). The scanner and its
-- categories are `skin_values.lua` beside this file.
--
-- IT SHIPS IN THE KIT because eight addons carried a copy, tests/test_skin_literals.lua, with 61 allow
-- entries between them, colors only, most of them the same few rulings typed again. It keeps what
-- those copies proved: a stale row fails, no git fails, a planted value proves the check.
--
-- WIRING, in the consumer's `tests/run.lua`, before `Kit.run`:
--
--   Kit.skinValues = {
--     rows  = {                                        -- what no kit category takes
--       { file = "modules/StandIn.lua", substring = "|cff999999",
--         why = "the stand-in's (test) mark, drawn in Blizzard's frames", cause = "A7" },
--     },
--     calls = { DrawEdge = { 3, 4, 5 } },              -- optional: the host's own paint calls
--     paths = { "core/*.lua", "ui/*.lua" },            -- optional: replaces V.SCOPE
--     root  = ".",                                     -- optional
--   }
--   Kit.run{ dir = "tests/", suites = { ..., { name = "test_skin_values", dir = "tests/_kit/" } } }
--
-- Declared by the pair like every other kit suite (testing-§9), so the suite inventory goes red
-- until it is wired. Until the host adopts it, `Kit.skinValues` is unset and the suite registers ONE
-- declared skip that names the rule: a re-vendor has to stay green. `Kit.skinValues = {}` is the
-- host with no rows.
--
-- It takes the kit as its chunk argument, for the reason `test_eol.lua` does: the exposed table's
-- global name belongs to the consumer.

local Kit = ...
local test, fail = Kit.test, Kit.fail

local RULE = "skinning-§1"

local facts = Kit.skinValues

if facts == nil then
  test("skin values: " .. RULE, nil, "Kit.skinValues is not set in the runner, so this repo's typed "
    .. "colors and textures are not gated yet. Every addon that adopted skins owes " .. RULE
    .. "; wire Kit.skinValues to adopt it")
  return
end

if type(facts) ~= "table" then
  fail("skin values: Kit.skinValues is the consumer-facts table, { rows, calls, paths }, not a "
    .. type(facts), 1)
end

--- This file's folder, from its own chunk name, with the vendored layout as the fallback.
local function ownDir()
  local info = debug and debug.getinfo and debug.getinfo(1, "S")
  local dir = info and tostring(info.source or ""):match("^@(.*[/\\])")
  return dir or "tests/_kit/"
end

local V = dofile(ownDir() .. "skin_values.lua")

test("skin values: every host row carries its file, substring, why and cause id", function()
  local problems = V.rowProblems(facts.rows)
  if #problems > 0 then fail("skin values: " .. table.concat(problems, "\n  ")) end
end)

test("skin values: no typed value outside the kit's categories and the host's rows", function()
  local bad, stale = V.judge(V.collect(facts), facts)
  if #bad > 0 then
    fail("typed values the skin cannot reach (read a token through the seam, or add a row with its "
      .. "reason and cause id):\n  " .. table.concat(bad, "\n  "))
  end
  if #stale > 0 then fail("stale host rows:\n  " .. table.concat(stale, "\n  ")) end
end)

test("skin values: the check is falsifiable, a planted value of each shape is reported", function()
  local planted = table.concat({
    "fs:SetTextColor(0.85, 0.85, 0.85)",
    'tt:AddLine("n", 0.7, 0.7, 0.7)',
    'local s = "|cff808080(none)|r"',
    "rows[1] = { label, 0.6, 0.6, 0.7 }",
    'bar:SetStatusBarTexture("Interface\\\\TargetingFrame\\\\UI-StatusBar")',
    "icon:SetTexture(134400)",
    'local P = "Interface\\\\FrameGeneral\\\\UI-Frame"',
    'bar:SetStatusBarTexture("Interface\\\\Buttons\\\\WHITE8X8")',
    'bar:SetStatusBarTexture("Interface\\\\AddOns\\\\Foo\\\\media\\\\bar.tga")',
    'fs:SetTextColor(NS.SkinColor("text.body"))',
    "tex:SetColorTexture(r, g, b, 0.95)",
    "-- |cffffffff in a comment",
  }, "\n")
  local lines = {}
  for _, hit in ipairs(V.scan(planted, { path = "modules/Planted.lua" })) do
    if not hit.category then lines[#lines + 1] = hit.line end
  end
  if table.concat(lines, ",") ~= "1,2,3,4,5,6,7,8,9" then
    fail("the scanner reported lines " .. table.concat(lines, ",") .. ", not 1 to 9")
  end
end)
