-- tests/test_skin_literals.lua — the hard-coded color gate (LH-05; skinning's anti-pattern, binding
-- for this addon since it adopted skins).
--
-- WHAT IT PROVES. That no color this addon draws is a literal the skin cannot reach. Two shapes are
-- caught, in every tracked .lua file under core/, modules/ and settings/:
--
--   1. A NUMERIC LITERAL IN A COLOR POSITION of a paint call: the r, g or b argument of
--      SetTextColor, SetColorTexture, SetVertexColor, SetBackdropColor and SetBackdropBorderColor,
--      the r, g, b after AddLine's text, and the two r, g, b triples after AddDoubleLine's texts.
--      `SetTextColor(0.85, 0.85, 0.85)` fails; `SetTextColor(NS.SkinColor("btn.icon"))` passes.
--      An ALPHA literal over token components (`SetColorTexture(r, g, b, 0.95)`) is not a color:
--      it is the surface's opacity, the same under every skin, and is left alone on purpose.
--   2. A `|cff` (any case) escape in code, i.e. markup that names a color byte for byte. Comments
--      are stripped first; NS.SkinEscape builds the escapes a token feeds.
--
-- core/SkinSetup.lua is out of scope: it IS the seam, and its host copy of the Ka0s Default tokens
-- (NS.SKIN_FALLBACK) and NS.SkinEscape's format are the literals every other file reads through.
--
-- THE ALLOW-LIST. Each entry names one file, a plain substring the offending line carries, and the
-- reason it is not chrome; docs/ARCHITECTURE.md's "Skins: intentional exceptions" carries the same
-- list. An entry that matches nothing fails the gate, so the list cannot outlive what it excuses.
--
-- IT FAILS RATHER THAN PASSES WHEN IT CANNOT LOOK: no io.popen, no git, or an empty file list is a
-- failure, the bargain tests/test_doc_structure.lua strikes. The last case proves the gate is
-- falsifiable: a planted literal of each shape is reported.

local T = _G.LH_TEST
local test, assertEqual, assertTrue, fail = T.test, T.assertEqual, T.assertTrue, T.fail
local ROOT = T.root or "."

local SEAM = "core/SkinSetup.lua"

-- call name -> the argument positions that hold color components.
local COLOR_ARGS = {
  SetTextColor = { 1, 2, 3 }, SetColorTexture = { 1, 2, 3 }, SetVertexColor = { 1, 2, 3 },
  SetBackdropColor = { 1, 2, 3 }, SetBackdropBorderColor = { 1, 2, 3 },
  AddLine = { 2, 3, 4 }, AddDoubleLine = { 3, 4, 5, 6, 7, 8 },
}

local ALLOW = {
  { file = "core/Constants.lua", find = "qualityHex(q)",
    why = "the Minimum quality options: an item quality's client color, passed through" },
  { file = "core/Namespace.lua", find = "NS.PREFIX",
    why = "the chat prefix: chat output, not a skinned surface (chat-output's cyan brand)" },
  { file = "settings/Slash.lua", find = "|cffffd100",
    why = "the ledger reset prompt's text: a Blizzard StaticPopup, which stays stock" },
  { file = "settings/Slash.lua", find = "|cFFFFFF00",
    why = "chat output: the get/set echo and the library's disabled-line fallback, pinned byte for byte" },
  { file = "modules/SimWorld.lua", find = "|H",
    why = "the simulator's fixture links: item and currency hyperlinks as the client colors them" },
}

--- Strip a line's trailing comment. `--` never occurs inside a string in these files' color code, so
--- a plain cut is enough; a string that did hold one would only shorten what is scanned.
local function code(line) return (line:gsub("%-%-.*$", "")) end

--- Split a call's argument list at its top-level commas (parens, braces and quotes nest).
local function splitArgs(s)
  local args, depth, buf, quote = {}, 0, {}, nil
  local i = 1
  while i <= #s do
    local c = s:sub(i, i)
    if quote then
      buf[#buf + 1] = c
      if c == "\\" then buf[#buf + 1] = s:sub(i + 1, i + 1); i = i + 1
      elseif c == quote then quote = nil end
    elseif c == '"' or c == "'" then quote = c; buf[#buf + 1] = c
    elseif c == "(" or c == "{" or c == "[" then depth = depth + 1; buf[#buf + 1] = c
    elseif c == ")" or c == "}" or c == "]" then depth = depth - 1; buf[#buf + 1] = c
    elseif c == "," and depth == 0 then args[#args + 1] = table.concat(buf); buf = {}
    else buf[#buf + 1] = c end
    i = i + 1
  end
  args[#args + 1] = table.concat(buf)
  return args
end

local function isNumber(arg) return arg:match("^%s*%-?%d*%.?%d+%s*$") ~= nil end

--- Every offending line of one source text: { line = n, text = what was found }.
local function scan(src)
  local lines, hits = {}, {}
  for ln in (src .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = code(ln) end
  local stripped = table.concat(lines, "\n")
  for name, positions in pairs(COLOR_ARGS) do
    local init = 1
    while true do
      local s, e, args = stripped:find("[:%.]" .. name .. "%s*(%b())", init)
      if not s then break end
      init = e + 1
      local list = splitArgs(args:sub(2, -2))
      for _, p in ipairs(positions) do
        if list[p] and isNumber(list[p]) then
          local n = select(2, stripped:sub(1, s):gsub("\n", "")) + 1
          hits[#hits + 1] = { line = n, text = lines[n] }
          break
        end
      end
    end
  end
  for n, ln in ipairs(lines) do
    if ln:find("|c[fF][fF]") then hits[#hits + 1] = { line = n, text = ln } end
  end
  return hits
end

local function allowed(file, text, used)
  for i, a in ipairs(ALLOW) do
    if a.file == file and text:find(a.find, 1, true) then used[i] = true; return true end
  end
  return false
end

local function trackedSources()
  if not io.popen then fail("skin literal gate: io.popen is unavailable, so this gate cannot run") end
  local p = io.popen("git -C " .. ROOT .. " ls-files 'core/*.lua' 'modules/*.lua' 'settings/*.lua' 2>/dev/null")
  if not p then fail("skin literal gate: io.popen returned no handle") end
  local files = {}
  for path in p:lines() do if path ~= SEAM then files[#files + 1] = path end end
  p:close()
  if #files == 0 then fail("skin literal gate: git listed no source files, so nothing was scanned") end
  return files
end

local function readAll(path)
  local f = io.open(ROOT .. "/" .. path, "rb")
  if not f then fail("skin literal gate: cannot read " .. path) end
  local s = f:read("*a")
  f:close()
  return s
end

test("no color literal outside core/SkinSetup.lua and the named allow-list", function()
  local bad, used = {}, {}
  for _, path in ipairs(trackedSources()) do
    for _, h in ipairs(scan(readAll(path))) do
      if not allowed(path, h.text, used) then
        bad[#bad + 1] = ("%s:%d: %s"):format(path, h.line, (h.text:gsub("^%s+", "")))
      end
    end
  end
  assertEqual(#bad, 0, "hard-coded colors the skin cannot reach (read a token through NS.Skin / "
    .. "NS.SkinColor / NS.SkinEscape, or add an allow-list entry with its reason):\n  "
    .. table.concat(bad, "\n  "))
  for i, a in ipairs(ALLOW) do
    assertTrue(used[i], ("stale allow-list entry: %s %q matches nothing"):format(a.file, a.find))
  end
end)

test("every allow-list entry carries its reason", function()
  for _, a in ipairs(ALLOW) do
    assertTrue(type(a.why) == "string" and #a.why > 10, a.file .. " " .. a.find .. ": no reason")
  end
end)

test("the gate is falsifiable: a planted literal of each shape is reported", function()
  local planted = table.concat({
    "local x = 1",
    "fs:SetTextColor(0.85, 0.85, 0.85)",
    "tex:SetColorTexture(r, g,",
    "  0.5, 1)",
    'tt:AddLine("n records", 0.7, 0.7, 0.7)',
    'tt:AddDoubleLine("a", "b", r, g, b, 1, 1, 1)',
    'local s = "|cff808080(none)|r"',
    "fs:SetTextColor(NS.SkinColor(\"text.body\"))   -- 0.9, 0.9, 0.9 in a comment",
    "tex:SetColorTexture(r, g, b, 0.95)",
    "-- |cffffffff in a comment",
  }, "\n")
  local hits = scan(planted)
  local lines = {}
  for _, h in ipairs(hits) do lines[#lines + 1] = h.line end
  table.sort(lines)
  assertEqual(table.concat(lines, ","), "2,3,5,6,7",
    "the literal lines and only those (a token call, an alpha literal and a comment pass)")
end)
