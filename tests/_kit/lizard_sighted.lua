-- testkit/lizard_sighted.lua — the sanitized shadow the complexity suite measures, and the parity
-- check that says whether lizard saw every function in it (kit revision 35, WowAddonStandards#6).
--
-- WHY A SHADOW. lizard 1.24.0 reads Lua through a reader that is not a Lua reader. Two families of
-- token make it lose functions without a word:
--
--   * `#`, read as a C preprocessor line, so `t[#t + 1] = x` swallows the rest of its line and the
--     function around it is never closed. `local function a(t) return #t end` is not listed.
--   * the Ruby-like reader's (lizard_languages/rubylike.py) bare `class`, `module`, `begin` and
--     `unless`, which open a block that wants an `end`, and `it`, which enters an RSpec state.
--     `{ class = "?" }` or `for _, it in ipairs(t)` drops the whole function they sit in.
--
-- A dropped function is a function whose CCN is never measured, and a gate that reports "no
-- function above 15" over a set it could not see is the green that measured nothing. Measured on
-- 2026-10-01 across the collection: about 1,600 `function` tokens lizard never listed, and 29 of
-- them above CCN 15.
--
-- THE FIX IS THE MEASUREMENT, NOT THE SOURCE. Rewriting some 2,800 hazard lines across twelve
-- repositories to dodge a tool's reader is churn that the next blind spot undoes. Instead the
-- runner copies every measured file into a temporary shadow with each hazard neutralized, and runs
-- the fixed lizard command there, so `complexity.txt` paths read exactly as before:
--
--   * `#` becomes a space;
--   * `it` and `unless` become `it_` and `unless_` everywhere, field and method names included;
--     `class` / `module` / `begin` become `class_` and so on everywhere but after `.`, where the
--     reader already reads them as a field name (after `:` too: `x:begin()` loses its function);
--   * `function a:b(` becomes `function a.b(self, ` (`function a.b(self)` with no parameters), so a
--     method is listed under its own name, `a.b`, rather than lizard's `a`.
--
-- Strings, long strings and comments are copied byte for byte, and no newline is added or removed,
-- so every line number lizard reports is the line number in the real file.
--
-- PARITY IS WHAT MAKES IT SAFE. The sanitizer is a heuristic: the next lizard blind spot will not be
-- one of the five words above. So the runner also counts the `function` keyword tokens in each
-- shadow file and compares them with the functions lizard listed for it. Any file where the two
-- differ is a file lizard was blind in, and the complexity suite does not pass
-- (`automated-tests-§3`). That catches a blind spot nobody has named yet, which the sanitizer alone
-- never could.
--
-- PURE LUA 5.1, NO DEPENDENCIES. Loaded as a module (`dofile` returns the table) by the kit's own
-- gate, `test_lizard_sighted.lua`, and run as a script by `run-automated-tests.sh`:
--
--   lua lizard_sighted.lua shadow <dir>      paths on stdin; writes sanitized copies under <dir>
--   lua lizard_sighted.lua parity <file>     paths on stdin, read from the cwd (the shadow); <file>
--                                            is lizard's output; prints `path<TAB>tokens<TAB>listed`
--                                            for every file where the two counts differ

local S = {}

--- The words lizard's Ruby-like reader treats as block openers or an RSpec state.
S.HAZARDS = { it = true, class = true, module = true, begin = true, unless = true }

--- `word` as the shadow spells it, given the last significant character before it. Measured against
--- lizard 1.24.0 on 2026-10-01: `it` loses its function wherever it stands, field and method names
--- included (`x.it`, `x:it()`); `unless` the same, since `u.unless` loses the next function when
--- both sit on one line; `class` / `module` / `begin` only when bare or after `:` (`x:begin()`),
--- never after `.` (`u.class`). A field renamed needlessly would cost nothing but a name, but a
--- method name renamed needlessly would show up in the watch list, so `.` keeps those three.
function S.renamed(word, prev)
  if not S.HAZARDS[word] then return word end
  if prev == "." and word ~= "it" and word ~= "unless" then return word end
  return word .. "_"
end

--- The index of the last byte of the long bracket `level` closes, searching from `i`, or of the source.
local function longEnd(src, i, level)
  local close = "]" .. level .. "]"
  local _, e = src:find(close, i, true)
  return e or #src
end

--- The index of the closing quote of a short string opened at `i` with `quote` (or of the line's
--- end, for a string the source never closes).
local function quotedEnd(src, i, quote)
  local j = i + 1
  while j <= #src do
    local c = src:sub(j, j)
    if c == "\\" then j = j + (src:sub(j + 1, j + 2) == "\r\n" and 2 or 1)
    elseif c == quote or c == "\n" then break end
    j = j + 1
  end
  return math.min(j, #src)
end

--- A comment or a string starting at `i`: its kind and the index of its last byte, or nil.
local function quotedPiece(src, i)
  local ch = src:sub(i, i)
  if ch == "-" and src:sub(i + 1, i + 1) == "-" then
    local level = src:match("^%[(=*)%[", i + 2)
    if level then return "comment", longEnd(src, i + 4 + #level, level) end
    return "comment", (src:find("\n", i, true) or #src + 1) - 1
  end
  local level = ch == "[" and src:match("^%[(=*)%[", i)
  if level then return "string", longEnd(src, i + 2 + #level, level) end
  if ch == '"' or ch == "'" then return "string", quotedEnd(src, i, ch) end
  return nil
end

--- One lexical piece of `src` starting at `i`: its kind ("comment", "string", "name", "number",
--- "hash", "space" or "other") and the index of its last byte.
local function piece(src, i)
  local kind, e = quotedPiece(src, i)
  if kind then return kind, e end
  local name = src:match("^[%a_][%w_]*", i)
  if name then return "name", i + #name - 1 end
  local num = src:match("^%d[%w_]*%.?[%w_]*", i)
  if num then return "number", i + #num - 1 end
  local ch = src:sub(i, i)
  if ch == "#" then return "hash", i end
  if ch:match("%s") then return "space", i end
  return "other", i
end

--- `function` followed by a method name `a.b:c` and its `(`: the replacement text and the index of
--- the `(`'s last byte, or nil when this `function` is not a method definition.
local function methodHead(src, i)
  local s, e, chain, method, paren = src:find("^(%s+[%a_][%w_%.]*):([%a_][%w_]*)(%s*%()", i)
  if not s then return nil end
  chain = chain:gsub("^(%s*)([%a_][%w_]*)", function(space, word) return space .. S.renamed(word, "") end)
    :gsub("%.([%a_][%w_]*)", function(word) return "." .. S.renamed(word, ".") end)
  local empty = src:match("^%s*%)", e + 1) ~= nil
  return chain .. "." .. S.renamed(method, ".") .. paren .. (empty and "self" or "self, "), e
end

--- `src` with every lizard hazard neutralized and every line where it was (see the header).
function S.sanitize(src)
  local out, i, n, prev = {}, 1, #src, ""
  while i <= n do
    local kind, e = piece(src, i)
    local text = src:sub(i, e)
    if kind == "hash" then
      text = " "
    elseif kind == "name" then
      text = S.renamed(text, prev)
      if text == "function" then
        local head, headEnd = methodHead(src, e + 1)
        if head then text, e = text .. head, headEnd end
      end
    end
    out[#out + 1] = text
    if kind ~= "space" and kind ~= "comment" then prev = text:match("(%S)%s*$") or prev end
    i = e + 1
  end
  return table.concat(out)
end

--- How many `function` keyword tokens `src` holds outside strings and comments: the number of
--- functions lizard should list for it.
function S.countFunctions(src)
  local i, n, count = 1, #src, 0
  while i <= n do
    local kind, e = piece(src, i)
    if kind == "name" and src:sub(i, e) == "function" then count = count + 1 end
    i = e + 1
  end
  return count
end

--- Path -> how many functions lizard listed, read from the per-file table of its output
--- (`NLOC Avg.NLOC AvgCCN Avg.token function_cnt file`). The function rows are not counted: the
--- warnings block repeats them, and the per-file table names every file once.
function S.listedCounts(text)
  local listed, inTable = {}, false
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    line = line:gsub("\r$", "")
    if line:match("^NLOC%s+Avg%.NLOC%s+AvgCCN%s+Avg%.token%s+function_cnt%s+file") then
      inTable = true
    elseif inTable then
      local count, path = line:match("^%s*%d+%s+[%d%.]+%s+[%d%.]+%s+[%d%.]+%s+(%d+)%s+(.-)%s*$")
      if count then
        listed[(path:gsub("^%./", ""))] = tonumber(count)
      elseif not line:match("^%-+$") then
        inTable = false
      end
    end
  end
  return listed
end

--- The files whose token count and listed count differ: an array of { path, tokens, listed }, in
--- the order `paths` gives. `read(path)` answers a file's bytes.
function S.parity(paths, lizardText, read)
  local listed, blind = S.listedCounts(lizardText), {}
  for _, path in ipairs(paths) do
    local tokens = S.countFunctions(read(path) or "")
    local got = listed[path] or 0
    if tokens ~= got then blind[#blind + 1] = { path, tokens, got } end
  end
  return blind
end

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

local function stdinPaths()
  local paths = {}
  for line in io.lines() do
    line = line:gsub("\r$", ""):gsub("^%./", "")
    if line ~= "" then paths[#paths + 1] = line end
  end
  return paths
end

local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

--- `shadow <dir>`: every path on stdin, sanitized, at the same relative path under `dir`.
local function cliShadow(root)
  local paths, dirs, seen = stdinPaths(), {}, {}
  for _, path in ipairs(paths) do
    local dir = (root .. "/" .. path):match("^(.*)/[^/]*$")
    if dir and not seen[dir] then seen[dir] = true; dirs[#dirs + 1] = quote(dir) end
  end
  for at = 1, #dirs, 200 do
    os.execute("mkdir -p " .. table.concat(dirs, " ", at, math.min(at + 199, #dirs)))
  end
  for _, path in ipairs(paths) do
    local f = assert(io.open(root .. "/" .. path, "wb"))
    f:write(S.sanitize(readFile(path) or ""))
    f:close()
  end
end

--- `parity <lizard-output>`: one `path<TAB>tokens<TAB>listed` line per blind file.
local function cliParity(lizardOut)
  for _, row in ipairs(S.parity(stdinPaths(), readFile(lizardOut) or "", readFile)) do
    io.write(row[1], "\t", row[2], "\t", row[3], "\n")
  end
end

local mode, argument = ...
if mode == "shadow" and argument then
  cliShadow(argument)
elseif mode == "parity" and argument then
  cliParity(argument)
end

return S
