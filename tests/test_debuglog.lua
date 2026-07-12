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
