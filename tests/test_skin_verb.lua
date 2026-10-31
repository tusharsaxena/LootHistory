-- tests/test_skin_verb.lua — the reserved `/lh skin` verb (LibKa0s v1.82.0's O.SkinVerb,
-- OptionsSkinPicker minor 3; LH-01 of Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK,
-- ruling D-16).
--
-- What this addon owes the verb, and nothing the library pins itself: a `skin` row right after
-- `config`, its help the library's VERB_HELP; NS.RunSkinVerb handing O.SkinVerb the spec the
-- first-run start builds, so it shows the picker on a profile that has already seen it; the
-- library's gray line in combat on every call; and the dispatcher's one refusal while the addon is
-- disabled. The library-absent half is tests/test_slash_degraded.lua's.
--
-- After test_skin_picker; leaves the picker down and the profile's pickerSeen false.

local T = _G.LH_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local O = NS.Options
local OptionsLib = mocks.LibStub("LibKa0s-Options-1.0")
local PATH = "settings.appearance.pickerSeen"

--- Run `fn(calls)` with O.SkinPicker replaced by a recorder: each call's spec, in order. O.SkinVerb
--- reaches it through the instance at call time.
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

--- Run `fn(lines)` with every chat line captured.
local function capture(fn)
  local cf = mocks.DEFAULT_CHAT_FRAME
  local add = cf.AddMessage
  local lines = {}
  cf.AddMessage = function(_, line) lines[#lines + 1] = tostring(line) end
  local ok, err = pcall(fn, lines)
  cf.AddMessage = add
  if not ok then error(err, 0) end
  return lines
end

local function clean(fn)
  return function()
    NS.HideSkinPicker()
    local ok, err = pcall(fn)
    NS.HideSkinPicker()
    NS.Schema:Set(PATH, false)
    if not ok then error(err, 0) end
  end
end

local function row(verb)
  for i, entry in ipairs(NS.COMMANDS) do
    if entry[1] == verb then return entry, i end
  end
end

test("Skin verb: a skin row right after config, worded as the library words it", function()
  -- red under: a missing row, one placed away from config, or help text of the addon's own.
  local entry, at = row("skin")
  local _, configAt = row("config")
  assertTrue(entry ~= nil, "NS.COMMANDS has no skin row")
  assertEqual(at, configAt + 1, "skin sits right after config")
  assertEqual(entry[2], OptionsLib.SKIN_PICKER_STRINGS.VERB_HELP)
end)

test("Skin verb: /lh skin shows the picker on a profile that has already seen it", clean(function()
  -- red under: the verb routed through NS.MaybeShowSkinPicker, which a seen profile skips.
  NS.Schema:Set(PATH, true)
  spying(function(calls)
    NS.Slash:OnSlash("skin")
    assertEqual(#calls, 1, "the verb did not reach O.SkinPicker")
    local spec = calls[1]
    assertEqual(spec.owner, "LootHistory")
    assertEqual(spec.page, "General")
    assertEqual(spec.tab, "Appearance")
    assertTrue(spec.get == NS.SkinChoice and spec.set == NS.WriteSkinChoice,
      "the verb's spec is not the first-run start's")
  end)
  assertEqual(NS.Schema:Get(PATH), true, "showing on demand does not unmark the profile")
end))

test("Skin verb: in combat nothing shows and the gray line prints on every call", clean(function()
  local real = mocks.InCombatLockdown
  mocks.InCombatLockdown = function() return true end
  local ok, err = pcall(function()
    spying(function(calls)
      local lines = capture(function()
        NS.Slash:OnSlash("skin")
        NS.Slash:OnSlash("skin")
      end)
      assertEqual(#calls, 0, "a picker showed in combat")
      local combat = OptionsLib.SKIN_PICKER_STRINGS.VERB_COMBAT
      local n = 0
      for _, line in ipairs(lines) do
        if line:find(combat, 1, true) then n = n + 1 end
      end
      assertEqual(n, 2, "one combat line per call")
    end)
  end)
  mocks.InCombatLockdown = real
  if not ok then error(err, 0) end
end))

test("Skin verb: refused while the addon is disabled, with the one refusal line", clean(function()
  -- red under: `skin` on LIVE_WHILE_DISABLED (a disabled addon would open its picker).
  local lines
  spying(function(calls)
    capture(function() NS.Schema:Set("settings.enabled", false) end)
    local ok, err = pcall(function()
      lines = capture(function() NS.Slash:OnSlash("skin") end)
      assertEqual(#calls, 0, "a disabled addon opened its picker")
    end)
    capture(function() NS.Schema:Set("settings.enabled", true) end)
    if not ok then error(err, 0) end
  end)
  assertEqual(#lines, 1, "one line, and nothing else")
  assertEqual(lines[1]:find(NS.Slash.DisabledLine(), 1, true) ~= nil, true, "the collection's refusal line")
end))
