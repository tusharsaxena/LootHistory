-- testkit/test_lizard_sighted.lua — the sighted complexity gate's own cases (automated-tests-§3,
-- kit revision 35, WowAddonStandards#6).
--
-- WHAT IT PROVES. That `lizard_sighted.lua`, the module `run-automated-tests.sh` builds its
-- complexity shadow with, neutralizes every lizard 1.24.0 blind spot it names and nothing else:
-- each hazard is rewritten where lizard loses a function over it; strings, long strings and
-- comments come through byte for byte; no line is added or removed, so every line number in
-- `complexity.txt` is the real file's. Then that the parity half counts `function` tokens the way a
-- Lua reader does and reads lizard's per-file table the way lizard writes it. And, when lizard is on
-- PATH, that a fixture holding every hazard lizard is blind to measures with full parity once
-- sanitized: the end-to-end claim the runner rests on.
--
-- WHY IT SHIPS IN THE KIT. The shadow is built in every consumer, so a sanitizer defect would
-- misreport twelve repositories' complexity at once; the cases that pin it travel with it. Wire it
-- as `{ name = "test_lizard_sighted", dir = "tests/_kit/" }`; `Kit.assertSuiteInventory` goes red
-- until you do. It takes the kit as its chunk argument, like every kit suite, and needs no consumer
-- facts.

local Kit = ...
local test, assertEqual, assertTrue, fail = Kit.test, Kit.assertEqual, Kit.assertTrue, Kit.fail

-- Found from this chunk's own name, the way `test_prose.lua` finds `prose_lists.lua`, with the
-- vendored layout as the fallback. A missing module raises at load: a gate with nothing to test
-- would pass.
local function kitDir()
  local info = debug and debug.getinfo and debug.getinfo(1, "S")
  local dir = info and tostring(info.source or ""):match("^@(.*[/\\])")
  local f = dir and io.open(dir .. "lizard_sighted.lua", "r")
  if f then f:close(); return dir end
  return "tests/_kit/"
end

local S = dofile(kitDir() .. "lizard_sighted.lua")

local function lines(s)
  local _, n = s:gsub("\n", "")
  return n
end

-- ── the hazards ───────────────────────────────────────────────────────────────────────────────

local POSITIVE = {
  { "for _, x in ipairs(t) do t[#t + 1] = x end", "for _, x in ipairs(t) do t[ t + 1] = x end" },
  { "local class = c", "local class_ = c" },
  { "for _, it in ipairs(t) do", "for _, it_ in ipairs(t) do" },
  { "local t = { module = 1 }", "local t = { module_ = 1 }" },
  { "x:begin()", "x:begin_()" },
  { "x:class()", "x:class_()" },
  { "local y = x.it", "local y = x.it_" },
  { "if unless then", "if unless_ then" },
  { "local y = x.unless", "local y = x.unless_" },
}

test("lizard sighted: every hazard lizard loses a function over is neutralized", function()
  for _, case in ipairs(POSITIVE) do
    assertEqual(S.sanitize(case[1]), case[2], "sanitize(" .. case[1] .. ")")
  end
end)

local NEGATIVE = {
  "local c = u.class",
  "local m = x.module .. y.begin",
  "local s = '#' .. \"# it class\"",
  "local n = 1 -- it class # module",
  "local s = [[ # it class ]] .. [==[ begin # ]==]",
  "--[[ # it\nclass ]] local z = 1",
  "local itself, classic, beginning, modules = 1, 2, 3, 4",
}

test("lizard sighted: fields, strings, comments and look-alike names come through unchanged", function()
  for _, src in ipairs(NEGATIVE) do
    assertEqual(S.sanitize(src), src, "sanitize must leave this alone: " .. src)
  end
end)

test("lizard sighted: a method definition is rewritten to its dot form with self", function()
  assertEqual(S.sanitize("function a:b(x, y)"), "function a.b(self, x, y)")
  assertEqual(S.sanitize("function a.c:d()"), "function a.c.d(self)")
  assertEqual(S.sanitize("function a:e( )"), "function a.e(self )")
  assertEqual(S.sanitize("function class:it()"), "function class_.it_(self)",
    "a hazard in the head is renamed by the same rule as anywhere else")
  assertEqual(S.sanitize("local f = function(x) end"), "local f = function(x) end", "not a method")
  assertEqual(S.sanitize("x:b(function() end)"), "x:b(function() end)", "a method call is not a definition")
end)

test("lizard sighted: no line is added or removed, CRLF included", function()
  local src = table.concat({
    "local M = {}",
    "function M:go(t) -- it",
    "  local s = [[",
    "# it class",
    "]]",
    "  for _, it in ipairs(t) do t[#t + 1] = it end",
    "  return \"a\\",
    "b\" .. #s",
    "end",
    "return M",
  }, "\r\n") .. "\r\n"
  local out = S.sanitize(src)
  assertEqual(lines(out), lines(src), "the same number of lines")
  local _, crlf = out:gsub("\r\n", "")
  assertEqual(crlf, lines(src), "and every terminator is still CRLF")
  local i = 0
  for line in out:gmatch("([^\n]*)\n") do
    i = i + 1
    if i == 4 then assertEqual(line, "# it class\r", "the long string's line is untouched") end
    if i == 8 then assertEqual(line, "b\" ..  s\r", "a string continued past its line ends where Lua ends it") end
  end
end)

-- ── parity ────────────────────────────────────────────────────────────────────────────────────

test("lizard sighted: countFunctions counts the keyword, not strings, comments or longer names", function()
  local src = "local function a() end\nlocal b = function() end -- function\n"
    .. "local s = 'function' .. [[function]]\nlocal functions = 1\nfunction M:c() end\n"
  assertEqual(S.countFunctions(src), 3)
end)

local LIZARD_OUT = table.concat({
  "================================================",
  "  NLOC    CCN   token  PARAM  length  location  ",
  "------------------------------------------------",
  "       4     16     15      0       4 M.b@2-5@./a.lua",
  "       3      1     11      2       3 f@6-8@./sub/b.lua",
  "2 file analyzed.",
  "==============================================================",
  "NLOC    Avg.NLOC  AvgCCN  Avg.token  function_cnt    file",
  "--------------------------------------------------------------",
  "     16       3.2     1.2       10.2         1     ./a.lua",
  "      8       3.0     1.0        6.0         1     ./sub/b.lua",
  "      2       0.0     0.0        0.0         0     ./c.lua",
  "",
  "!!!! Warnings (cyclomatic_complexity > 15 or length > 1000) !!!!",
  "================================================",
  "  NLOC    CCN   token  PARAM  length  location  ",
  "------------------------------------------------",
  "       4     16     15      0       4 M.b@2-5@./a.lua",
  "==========================================================================================",
  "Total nloc   Avg.NLOC  AvgCCN  Avg.token   Fun Cnt  Warning cnt   Fun Rt   nloc Rt",
  "------------------------------------------------------------------------------------------",
  "        26       3.2     1.2       10.2        2            1      0.50    0.20",
}, "\r\n")

test("lizard sighted: listedCounts reads the per-file table, once per file", function()
  local listed = S.listedCounts(LIZARD_OUT)
  assertEqual(listed["a.lua"], 1, "the warnings block's repeat of a row is not a second function")
  assertEqual(listed["sub/b.lua"], 1)
  assertEqual(listed["c.lua"], 0)
end)

test("lizard sighted: parity names every file whose counts differ, and only those", function()
  local files = {
    ["a.lua"] = "function M:b() end",
    ["sub/b.lua"] = "local function f() end\nlocal g = function() end",
    ["c.lua"] = "",
    ["d.lua"] = "local function h() end",
  }
  local blind = S.parity({ "a.lua", "sub/b.lua", "c.lua", "d.lua" }, LIZARD_OUT, function(p) return files[p] end)
  assertEqual(#blind, 2, "two blind files")
  assertEqual(table.concat(blind[1], " "), "sub/b.lua 2 1")
  assertEqual(table.concat(blind[2], " "), "d.lua 1 0", "a file lizard never listed counts as 0")
end)

-- ── end to end, against the lizard on this host ──────────────────────────────────────────────────

local FIXTURE = table.concat({
  "local M = {}",
  "local function len(t) return #t end",
  "local function cls() return { class = '?' } end",
  "local function each(t) for _, it in ipairs(t) do t[#t + 1] = it end end",
  "local function mod() return { module = 1, begin = 2 } end",
  "local function call(x) return x:begin(), x.it end",
  "function M:method(x) if x then return 1 end return 2 end",
  "return M",
}, "\n") .. "\n"

local function shell(cmd)
  local p = io.popen(cmd)
  if not p then return nil end
  local out = p:read("*a")
  p:close()
  return out
end

test("lizard sighted: lizard lists every function of a hazard fixture once it is sanitized", function()
  if not io.popen then Kit.skip("io.popen is unavailable, so lizard cannot be run") end
  local where = shell("command -v lizard 2>/dev/null") or ""
  if not where:match("%S") then Kit.skip("lizard is not on PATH, so the end-to-end case cannot run") end
  local dir = (shell("mktemp -d 2>/dev/null") or ""):match("^%s*(.-)%s*$")
  if dir == "" then Kit.skip("no `mktemp -d` on this host") end
  local f = assert(io.open(dir .. "/fixture.lua", "wb"))
  f:write(S.sanitize(FIXTURE))
  f:close()
  local out = shell(("cd '%s' && lizard -l lua . 2>&1"):format(dir)) or ""
  os.execute(("rm -rf '%s'"):format(dir))
  local blind = S.parity({ "fixture.lua" }, out, function() return FIXTURE end)
  if #blind > 0 then
    fail(("lizard listed %d of the fixture's %d functions after sanitizing; its output:\n%s")
      :format(blind[1][3], blind[1][2], out), 1)
  end
  assertTrue(out:find("M.method@", 1, true) ~= nil, "the method is listed under its own name: " .. out)
end)
