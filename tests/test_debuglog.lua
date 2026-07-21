local T = _G.LH_TEST
local NS, test, assertTrue, assertEqual = T.NS, T.test, T.assertTrue, T.assertEqual

test("FONT_MONO constant is a JetBrains Mono TTF path", function()
  assertTrue(type(NS.Constants.FONT_MONO) == "string", "FONT_MONO must be a string")
  assertTrue(NS.Constants.FONT_MONO:match("JetBrainsMono.-%.ttf$") ~= nil,
    "FONT_MONO must point at the vendored JetBrainsMono TTF")
end)

test("FormatPlain wraps the tag in brackets with single-space separators", function()
  local out = NS.DebugLog.FormatPlain("15:04:43", "Cast", "player spell=3365")
  assertEqual(out, "15:04:43 | [Cast] player spell=3365")
end)

test("FormatPlain renders the tag verbatim (no padding or truncation)", function()
  local out = NS.DebugLog.FormatPlain("15:04:43", "Prospecting", "x")
  assertEqual(out, "15:04:43 | [Prospecting] x")
end)

test("FormatPlain tolerates a nil tag", function()
  local out = NS.DebugLog.FormatPlain("15:04:43", nil, "hi")
  assertEqual(out, "15:04:43 | [] hi")
end)

test("FormatColored colors the timestamp and tag; pipe and content default", function()
  local out = NS.DebugLog.FormatColored("15:04:43", "Cast", "player spell=3365")
  assertEqual(out, "|cff6f8faf15:04:43|r || |cffc9a66b[Cast]|r player spell=3365")
end)

-- Secret-safe sink (events-frames-taint-§8): a combat "secret" arg must reach string.format only
-- through NS.SafeToString, so it logs as <secret> instead of raising. Modelled as a table (which
-- table.concat / string.format reject) — the same shape a real secret trips on.
local secretMock = setmetatable({}, { __concat = function() return "secret-propagated" end })

test("NS.Debug renders a secret message arg as <secret> without raising", function()
  NS.State.debug = true
  local before = #NS.DebugLog.buffer
  local ok = pcall(NS.Debug, "UNIT", "value=%s", secretMock)
  assertTrue(ok, "NS.Debug must not raise on a secret arg")
  assertTrue(#NS.DebugLog.buffer > before, "a line was logged")
  local last = NS.DebugLog.buffer[#NS.DebugLog.buffer]
  assertTrue(last:find("value=<secret>", 1, true) ~= nil,
    "secret arg should render as <secret>: " .. tostring(last))
  NS.State.debug = false
end)

test("NS.Debug formats ordinary args (numbers included) through %s", function()
  NS.State.debug = true
  NS.Debug("Tag", "a=%s b=%s", 1, "two")
  local last = NS.DebugLog.buffer[#NS.DebugLog.buffer]
  assertTrue(last:find("a=1 b=two", 1, true) ~= nil, "normal format: " .. tostring(last))
  NS.State.debug = false
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

test("header toggle click flips debug state", function()
  NS.State.debug = false
  NS.DebugLog:Show()
  local click = NS.DebugLog._toggleClickForTest
  assertTrue(type(click) == "function", "toggle click closure must be exposed")
  click(); assertTrue(NS.State.debug == true, "click should turn state on")
  click(); assertTrue(NS.State.debug == false, "second click should turn state off")
end)

-- ── SetEnabled seam: colour-coded chat ack + [Init] summary (debug-logging-§5) ──
local function capture(fn)
  local out = {}
  local cf = T.mocks.DEFAULT_CHAT_FRAME
  local old = cf.AddMessage
  cf.AddMessage = function(_, msg) out[#out + 1] = msg end
  local ok, err = pcall(fn)
  cf.AddMessage = old
  if not ok then error(err) end
  return out
end

test("SetEnabled(true) prints a green-coded ON ack through the NS.PREFIX printer", function()
  local out = capture(function() NS.DebugLog:SetEnabled(true) end)
  assertEqual(out[1], NS.PREFIX .. " debug logging |cff40ff40ON|r")
  NS.State.debug = false
end)

test("SetEnabled(false) prints a red-coded OFF ack", function()
  local out = capture(function() NS.DebugLog:SetEnabled(false) end)
  assertEqual(out[1], NS.PREFIX .. " debug logging |cffff4040OFF|r")
end)

test("SetEnabled(true) appends the [Init] summary right after the enable bracket", function()
  NS.State.debug = false
  local before = #NS.DebugLog.buffer
  NS.DebugLog:SetEnabled(true)
  local buf = NS.DebugLog.buffer
  assertEqual(#buf, before + 2, "enable appends exactly the bracket + [Init] lines")
  assertTrue(buf[before + 1]:find("[Debug] logging enabled", 1, true) ~= nil,
    "enable bracket first: " .. tostring(buf[before + 1]))
  assertTrue(buf[before + 2]:find("[Init]", 1, true) ~= nil,
    "[Init] line follows: " .. tostring(buf[before + 2]))
  assertTrue(buf[before + 2]:find(NS.InitSummary(), 1, true) ~= nil,
    "[Init] carries the session summary: " .. tostring(buf[before + 2]))
  NS.State.debug = false
end)

test("SetEnabled(false) appends a [Debug] logging disabled line after the flag flips off", function()
  NS.State.debug = true
  local before = #NS.DebugLog.buffer
  NS.DebugLog:SetEnabled(false)
  local buf = NS.DebugLog.buffer
  assertTrue(NS.State.debug == false, "flag must be off")
  assertEqual(#buf, before + 1, "disable appends exactly one console line")
  assertTrue(buf[#buf]:find("[Debug] logging disabled", 1, true) ~= nil,
    "disable line via raw append: " .. tostring(buf[#buf]))
end)

test("InitSummary reports name, version, schema, active profile, and record count", function()
  local n = #NS.db.global.history   -- order-independent: read the live count, don't hard-code it
  assertEqual(NS.InitSummary(),
    ("%s v%s, schema v4, profile 'Default', %d records"):format(NS.name, NS.version, n))
end)
