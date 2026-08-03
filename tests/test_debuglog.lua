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
    if c[1] == "debug" then return c[3](rest) end
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

-- ── the LibKa0s-DebugLog-1.0 seam ────────────────────────────────────────────────────────────
--
-- DebugLog is one of the three majors that CAN express the `L` trap (it takes a descriptor `L`), so
-- it carries a real RENDERED assertion rather than a source tripwire: the library's own strings must
-- reach the screen as prose. This addon passes no `L` at all, which is the safe case — these cases
-- exist so that stops being true loudly rather than silently.

local lib = T.mocks.LibStub("LibKa0s-DebugLog-1.0", true)

test("the console title renders the library's TITLE_SUFFIX as prose, not as its key", function()
  NS.DebugLog:Show()   -- builds the frame; the composed title is recorded on it
  local frame = NS.DebugLog._frameForTest
  -- Non-vacuity coupling: without this the assertion below passes on a nil accessor, which is
  -- exactly how the first attempt at this guard proved nothing.
  assertTrue(frame ~= nil and type(frame.titleText) == "string",
    "the library must record the composed title on the frame; there is no other way to read it back")
  assertEqual(frame.titleText, "Loot History" .. lib.STRINGS.TITLE_SUFFIX)
  assertEqual(frame.titleText, "Loot History \226\128\148 Debug")
  assertTrue(frame.titleText:match("^[A-Z][A-Z0-9_]+$") == nil,
    "the title rendered as a raw locale key: " .. frame.titleText)
end)

test("every DebugLog string this addon renders resolves to prose, not to a key", function()
  local rendered = {
    NS.DebugLog:Text("TITLE_SUFFIX"), NS.DebugLog:Text("DEBUG_ON"), NS.DebugLog:Text("DEBUG_OFF"),
    NS.DebugLog:Text("CLEAR"), NS.DebugLog:Text("COPY"), NS.DebugLog:Text("COPY_TITLE"),
    NS.DebugLog:Text("LINES"), NS.DebugLog:Text("CHECKBOX_LABEL"),
    NS.DebugLog:Text("LOG_ENABLED"), NS.DebugLog:Text("LOG_DISABLED"),
  }
  assertEqual(#rendered, 10, "all ten must resolve, or the loop below runs over a short list")
  for _, s in ipairs(rendered) do
    assertTrue(type(s) == "string" and s ~= "", "unresolved string")
    assertTrue(s:match("^[A-Z][A-Z0-9_]+$") == nil, "rendered as a raw locale key: " .. s)
  end
  -- The one that pins it hardest: a real sentence, asserted byte for byte.
  assertEqual(NS.DebugLog:Text("DEBUG_ON"), "Debug: ON")
end)

test("ConsoleCheckbox composes this addon's slash prefix into its tooltip", function()
  local spec = NS.DebugLog:ConsoleCheckbox()
  assertEqual(spec.label, "Debug console")
  assertTrue(spec.tooltip:find("/lh debug", 1, true) ~= nil,
    "the descriptor's `slash` must compose the reference: " .. tostring(spec.tooltip))
  assertTrue(spec.tooltip:match("^[A-Z][A-Z0-9_]+$") == nil, "tooltip rendered as a raw key")
  -- Visibility only, never the logging flag: a user who closes the console does not expect
  -- logging to stop, and this addon's own `/lh debug` (no arg) has always behaved that way too.
  NS.State.debug = true
  spec.set(false)
  assertTrue(NS.State.debug == true, "the checkbox must not touch the logging flag")
  assertTrue(spec.get() == false, "and it must report the window's visibility")
  NS.State.debug = false
end)

test("the console closes with the LIBRARY's x, not this addon's 24-wide one", function()
  -- The console and the copy window are the library's windows, so they wear Core's thin 18x18 x.
  -- This addon's own 24x24 class-coloured glyph stays on the windows it belongs to; passing it
  -- through the `makeCloseButton` hook is what made these two windows look unlike every other
  -- Ka0s addon's (docs/pending/LEDGER.md, LIBKA0S-19).
  --
  -- The offsets are DERIVED from the returned button's width, and this addon's mock records
  -- SetSize as real state, so Core's `SetSize(18, 18)` is genuinely measured here rather than
  -- falling through to the library's 18-wide default. That is the one thing LibKa0s's own suite
  -- cannot do — its mock answers 0 from GetWidth, so both paths give it the same number.
  NS.DebugLog:Show()
  local offsets = NS.DebugLog._frameForTest.titleBarOffsets
  assertTrue(offsets ~= nil, "the library must record the computed offsets; an anchor cannot be read back")
  assertEqual(offsets.close, -6)
  assertEqual(offsets.clear, -30, "PAD + 18 + PAD — a 24-wide button would give -36")
  assertEqual(offsets.copy, -78, "clear - CLEAR_W - PAD")
end)

test("the copy window's buffer text is the whole buffer, in order", function()
  NS.DebugLog:Clear()
  NS.DebugLog:Add("A", "first")
  NS.DebugLog:Add("B", "second")
  local text = NS.DebugLog:CopyText()
  local lines = {}
  for line in text:gmatch("[^\n]+") do lines[#lines + 1] = line end
  assertEqual(#lines, 2)
  assertTrue(lines[1]:find("[A] first", 1, true) ~= nil, lines[1])
  assertTrue(lines[2]:find("[B] second", 1, true) ~= nil, lines[2])
end)

test("InitSummary reports name, version, schema, active profile, and record count", function()
  local n = #NS.db.global.history   -- order-independent: read the live count, don't hard-code it
  assertEqual(NS.InitSummary(),
    ("%s v%s, schema v7, profile 'Default', %d records"):format(NS.name, NS.version, n))
end)
