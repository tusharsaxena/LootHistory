local T = _G.LH_TEST
local NS, test, assertTrue, assertEqual = T.NS, T.test, T.assertTrue, T.assertEqual

test("FONT_MONO constant is a JetBrains Mono TTF path", function()
  assertTrue(type(NS.Constants.FONT_MONO) == "string", "FONT_MONO must be a string")
  assertTrue(NS.Constants.FONT_MONO:match("JetBrainsMono.-%.ttf$") ~= nil,
    "FONT_MONO must point at the vendored JetBrainsMono TTF")
end)

test("FormatPlain pads a short tag to 10 chars inside brackets", function()
  local out = NS.DebugLog.FormatPlain("15:04:43", "Cast", "player spell=3365")
  assertEqual(out, "15:04:43  |  [Cast      ] player spell=3365")
end)

test("FormatPlain truncates a tag longer than 10 chars", function()
  local out = NS.DebugLog.FormatPlain("15:04:43", "Prospecting", "x")
  assertEqual(out, "15:04:43  |  [Prospectin] x")
end)

test("FormatPlain tolerates a nil tag", function()
  local out = NS.DebugLog.FormatPlain("15:04:43", nil, "hi")
  assertEqual(out, "15:04:43  |  [          ] hi")
end)

local function debugCmd(rest)
  for _, c in ipairs(NS.COMMANDS) do
    if c.name == "debug" then return c.fn(rest) end
  end
  error("no debug command")
end

test("/lh debug on enables state", function()
  NS.State.debug = false
  debugCmd("on")
  assertTrue(NS.State.debug == true, "state should be on")
end)

test("/lh debug off disables state", function()
  NS.State.debug = true
  debugCmd("off")
  assertTrue(NS.State.debug == false, "state should be off")
end)

test("/lh debug (no arg) toggles the window, not state", function()
  NS.State.debug = true
  debugCmd("")
  assertTrue(NS.State.debug == true, "bare toggle must not change state")
  NS.State.debug = false
  debugCmd("")
  assertTrue(NS.State.debug == false, "bare toggle must not change state")
end)
