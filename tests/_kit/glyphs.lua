-- testkit/glyphs.lua — the display-glyph guard (kit revision 45): no string an addon paints in a
-- skin face carries a character some shipped skin face cannot draw.
--
-- WHY. The owner's image-19 (Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK, item 5b,
-- ruling D-19): LootHistory's footer read "Database [] 1.6 MB" under Obsidian, because its string
-- carried U+2248 (written as the escape "\226\137\136", which a plain grep never finds) and
-- Expressway has no such glyph. Ten skins draw text in a dozen faces, and a character one of them
-- lacks is a box in that skin only, so nobody notices until a player picks it.
--
-- THE SAFE SET is printable ASCII (and every other byte under 0x80: tab, newline) plus the non-ASCII
-- code points EVERY face in LibKa0s/media/fonts draws, read from their cmaps by
-- tools/glyph_safe_set.py, which writes the generated block below (FACES and RANGES). That folder is
-- exactly the faces the skins name, JetBrains Mono (the mono role) included. Regenerate after any
-- face is added, removed or replaced:
--
--   python3 tools/glyph_safe_set.py && cp -r testkit/. tests/_kit/      (in LibKa0s, needs fontTools)
--
-- LibKa0s's tests/test_glyph_guard.lua is red while FACES (each face's file name and byte size)
-- disagrees with the folder. Real Friz Quadrata (WoW Default's face, the client's own) ships in no
-- folder anyone can read and is not measured (D-05, IS-07); a font override (any LibSharedMedia face)
-- guarantees nothing beyond ASCII.
--
-- SURFACE, on the kit table and published by `Kit.expose`:
--
--   Kit.glyphUnsafe(s) -> list        every character of `s` outside the safe set, in order, each
--                                     { cp = <code point>, char = <its UTF-8> }, or { byte = <n> }
--                                     for a byte that is not valid UTF-8; `|T...|t` and `|A...|a`
--                                     markup is left out (a texture draws no glyph). Empty: safe
--   Kit.assertGlyphSafe(s, label)     fails naming each unsafe character as U+XXXX
--   Kit.scanGlyphSource(text, path, opts) -> hits
--                                     the string literals of one Lua chunk that carry an unsafe
--                                     character: { path, line, cp | byte, char, text }
--   Kit.scanDisplayGlyphs(opts) -> hits, files
--                                     every tracked .lua file of the repo, through scanGlyphSource
--   Kit.assertDisplayGlyphs(opts)     fails listing the hits (the first 20, and the count)
--   Kit.GLYPH_FACES, Kit.GLYPH_RANGES the generated block, read-only by convention
--
-- WHAT IS SCANNED. Every string literal, "..." and '...' (escapes decoded: \ddd, \xNN, \u{X}, \z
-- and the letter escapes) and [[...]] / [==[...]==]: a locale file's values are literals too. NOT
-- scanned:
--   - comments, line and block;
--   - the arguments of a debug-log call: a call whose callee's last name is one of the collection's
--     debug sinks (DEBUG_SINKS below: Debug, Debugf, DebugOnce, DebugErrorOnce, DebugSteady,
--     DebugChanged, DebugAtEnable, DebugMessage, AddDebugMessage, DebugTable, DebugStack, debug, dbg,
--     Dbg) or one of opts.debugNames, to its closing paren, however many lines it spans, and the one
--     string literal of a string call (`NS.Debug "..."`): the debug console draws in the mono face,
--     which has the arrows. Only exact names: a display helper whose name merely carries "Debug"
--     (DebugLabel, doDebugTooltip) is scanned;
--   - a line carrying the comment marker `glyph: mono`, and every line between `glyph: mono begin`
--     and `glyph: mono end`: strings the code draws in the mono role (S.Text(fs, "mono"),
--     NS.SkinMono) or as a single glyph its own FontString pins to JetBrains Mono. `glyph: data`
--     (and its begin / end) is the same marker for a string that is never drawn: a lookup key, a
--     pattern, a saved value's name. A `begin` with no `end` before the end of the file, or an `end`
--     with no `begin`, fails: a mistyped marker never turns the guard off for the rest of a file;
--   - a stray byte in a literal that is not valid UTF-8: byte data (a pattern's `[\128-\191]`
--     class), never shown. Kit.glyphUnsafe on a runtime string still names such a byte;
--   - `|T...|t` / `|A...|a` texture markup inside a string.
--
-- opts (scanDisplayGlyphs, assertDisplayGlyphs):
--   opts.paths     a list of files to read, instead of git's tracked .lua files
--   opts.include   path prefixes kept (default: every tracked .lua file)
--   opts.skip      { [path prefix] = "why" }: left out, each with its reason (a missing or empty
--                  reason fails: a skip is a decision, so it says what it decided). libs/, tests/
--                  and tools/ are always left out: vendored code, test fixtures, and developer tools
--                  that print to a terminal
--   opts.debugNames  extra callee names to read as debug-log calls (a set or a list)
--   opts.label     leads every failure message (the addon's name)
--
-- A consumer wires it as one case (testing-§9 does not make it a kit suite, so nothing goes red on
-- a re-vendor before the addon's own strings are fixed):
--
--   test("display strings use only characters every shipped skin face draws", function()
--     T.assertDisplayGlyphs{ label = "LootHistory", skip = { ["defaults/Realms.lua"] = "lookup keys" } }
--   end)
--
-- IT FAILS RATHER THAN PASSES WHEN IT CANNOT LOOK: no io.popen, no git, or no tracked .lua file
-- (with no opts.paths) is a failure, never an empty pass, the bargain test_eol.lua strikes.

-- The members, kept here and copied onto the kit table by the installer this file returns.
local G = {}

-- BEGIN GENERATED by tools/glyph_safe_set.py: do not edit by hand
local FACES = {
  { file = "AtkinsonHyperlegible-Bold.ttf", bytes = 55256 },
  { file = "AtkinsonHyperlegible-Regular.ttf", bytes = 54348 },
  { file = "Bitter-Bold.ttf", bytes = 202296 },
  { file = "Bitter-Regular.ttf", bytes = 202016 },
  { file = "Expressway-Bold.ttf", bytes = 99820 },
  { file = "FiraSans-Medium.ttf", bytes = 457248 },
  { file = "FiraSans-SemiBold.ttf", bytes = 489028 },
  { file = "JetBrainsMono-Regular.ttf", bytes = 273900 },
  { file = "Nunito-Regular.ttf", bytes = 132360 },
  { file = "Nunito-SemiBold.ttf", bytes = 132336 },
  { file = "Philosopher-Bold.ttf", bytes = 110068 },
  { file = "Philosopher-Regular.ttf", bytes = 111676 },
  { file = "Prototype-Regular.ttf", bytes = 29592 },
  { file = "Vollkorn-Bold.ttf", bytes = 365096 },
  { file = "Vollkorn-Regular.ttf", bytes = 363616 },
}
local RANGES = {
  { 0x00A0, 0x00A3 }, { 0x00A5, 0x00AB }, { 0x00AE, 0x00BB }, { 0x00BF, 0x00FF }, { 0x0152, 0x0153 },
  { 0x0160, 0x0161 }, { 0x0178, 0x0178 }, { 0x017D, 0x017E }, { 0x02C6, 0x02C7 }, { 0x02D8, 0x02D8 },
  { 0x02DA, 0x02DA }, { 0x02DC, 0x02DC }, { 0x2013, 0x2014 }, { 0x2018, 0x201A }, { 0x201C, 0x201E },
  { 0x2020, 0x2022 }, { 0x2026, 0x2026 }, { 0x2039, 0x203A }, { 0x2044, 0x2044 }, { 0x2122, 0x2122 },
}
-- END GENERATED

local function fail(msg) return G.fail(msg, 3) end

--- True for a code point every shipped face draws.
local function safe(cp)
  if cp < 0x80 then return true end
  for _, r in ipairs(RANGES) do
    if cp < r[1] then return false end
    if cp <= r[2] then return true end
  end
  return false
end

--- `s` without its `|T...|t` and `|A...|a` texture markup.
local function stripMarkup(s)
  return (s:gsub("|T.-|t", ""):gsub("|A.-|a", ""))
end

-- The second byte's range for the lead bytes that narrow it (RFC 3629's table): no overlong form,
-- no surrogate (U+D800-DFFF), nothing past U+10FFFF.
local SECOND = { [0xE0] = { 0xA0, 0xBF }, [0xED] = { 0x80, 0x9F }, [0xF0] = { 0x90, 0xBF },
                 [0xF4] = { 0x80, 0x8F } }

--- A lead byte's sequence length and its payload bits, or nil for a byte no sequence starts with.
local function lead(c)
  if c >= 0xF0 and c <= 0xF4 then return 4, c - 0xF0 end
  if c >= 0xE0 and c <= 0xEF then return 3, c - 0xE0 end
  if c >= 0xC2 and c <= 0xDF then return 2, c - 0xC0 end
  return nil
end

--- The UTF-8 sequence at `i` of `s`: its code point and length, or nil when it is not valid.
local function decodeAt(s, i)
  local c = s:byte(i)
  local n, cp = lead(c)
  if not n then return nil end
  local lo, hi = 0x80, 0xBF
  if SECOND[c] then lo, hi = SECOND[c][1], SECOND[c][2] end
  for k = 1, n - 1 do
    local b = s:byte(i + k)
    if not b or b < lo or b > hi then return nil end
    cp = cp * 64 + (b - 0x80)
    lo, hi = 0x80, 0xBF
  end
  return cp, n
end

function G.glyphUnsafe(s)
  local out = {}
  if type(s) ~= "string" then return out end
  s = stripMarkup(s)
  local i = 1
  while i <= #s do
    local c = s:byte(i)
    if c < 0x80 then
      i = i + 1
    else
      local cp, n = decodeAt(s, i)
      if not cp then
        out[#out + 1] = { byte = c }
        i = i + 1
      else
        if not safe(cp) then out[#out + 1] = { cp = cp, char = s:sub(i, i + n - 1) } end
        i = i + n
      end
    end
  end
  return out
end

local function describe(u)
  if u.cp then return string.format("U+%04X %s", u.cp, u.char) end
  return string.format("byte 0x%02X (not UTF-8)", u.byte)
end

function G.assertGlyphSafe(s, label)
  local bad = G.glyphUnsafe(s)
  if #bad == 0 then return end
  local names = {}
  for _, u in ipairs(bad) do names[#names + 1] = describe(u) end
  fail((label and (label .. ": ") or "") .. "a character some shipped skin face cannot draw: "
    .. table.concat(names, ", ") .. " in " .. string.format("%q", s)
    .. " (testkit/glyphs.lua: use ASCII, a catalog icon, or the mono face)")
end

-- ── the lexer ──────────────────────────────────────────────────────────────────────────────

local LETTER = { a = "\a", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", v = "\v",
                 ["\\"] = "\\", ['"'] = '"', ["'"] = "'", ["\n"] = "\n", ["\r"] = "\n" }

local function utf8char(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
  if cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
  end
  return string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64,
    0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

--- One escape at `i` (the character after the backslash): its bytes and the index after it.
local function escapeAt(src, i)
  local ch = src:sub(i, i)
  local d = src:match("^%d%d?%d?", i)
  if d then return string.char(tonumber(d) % 256), i + #d end
  local x = src:match("^x(%x%x)", i)
  if x then return string.char(tonumber(x, 16)), i + 3 end
  local u = src:match("^u{(%x+)}", i)
  if u then return utf8char(tonumber(u, 16)), i + 3 + #u end
  if ch == "z" then
    local _, e = src:find("^%s*", i + 1)
    return "", e + 1
  end
  if ch == "\r" and src:sub(i + 1, i + 1) == "\n" then return "\n", i + 2 end
  return LETTER[ch] or ch, i + 1
end

--- A quoted string opening at `i`: its decoded bytes and the index after the closing quote.
local function quotedAt(src, i)
  local q, parts, j = src:sub(i, i), {}, i + 1
  while j <= #src do
    local ch = src:sub(j, j)
    if ch == q then return table.concat(parts), j + 1 end
    if ch == "\\" then
      local bytes
      bytes, j = escapeAt(src, j + 1)
      parts[#parts + 1] = bytes
    elseif ch == "\n" then
      return table.concat(parts), j   -- unfinished: Lua would not load it; stop at the line
    else
      parts[#parts + 1] = ch
      j = j + 1
    end
  end
  return table.concat(parts), j
end

--- A long bracket opening at `i` ("[[", "[==["): its body and the index after it, or nil.
local function longAt(src, i)
  local eq = src:match("^%[(=*)%[", i)
  if not eq then return nil end
  local open = i + #eq + 2
  local close = "]" .. eq .. "]"
  local e = src:find(close, open, true)
  local body = src:sub(open, (e or #src + 1) - 1):gsub("^\r?\n", "")
  return body, e and (e + #close) or (#src + 1)
end

-- The collection's debug sinks, by exact name: a callee spelled otherwise is a display call unless
-- the host names it in opts.debugNames.
local DEBUG_SINKS = { Debug = true, Debugf = true, DebugOnce = true, DebugErrorOnce = true,
                      DebugSteady = true, DebugChanged = true, DebugAtEnable = true, DebugMessage = true,
                      AddDebugMessage = true, DebugTable = true, DebugStack = true,
                      debug = true, dbg = true, Dbg = true }

local function isDebugName(name, extra)
  return DEBUG_SINKS[name] or (extra and extra[name]) or false
end

local MARKERS = { mono = true, data = true }

--- The lines a `glyph: mono` or `glyph: data` marker covers in `src`: a set of line numbers. A region
--- left open at the end of the file, or an `end` with no `begin`, fails naming the line.
local function markedLines(src, path)
  local covered, line, openAt = {}, 0, nil
  for text in (src .. "\n"):gmatch("([^\n]*)\n") do
    line = line + 1
    local kind, edge = text:match("glyph:%s*(%a+)%s*(%a*)")
    local marker = kind and MARKERS[kind] and edge or nil
    if marker == "begin" then openAt = openAt or line end
    if marker == "end" and not openAt then
      fail("glyph guard: " .. path .. ":" .. line .. ": `glyph: " .. kind .. " end` with no `begin`")
    end
    if openAt or marker ~= nil then covered[line] = true end
    if marker == "end" then openAt = nil end
  end
  if openAt then
    fail("glyph guard: " .. path .. ":" .. openAt .. ": a `glyph: ... begin` with no `end` before the "
      .. "end of the file, which would leave every later string unchecked")
  end
  return covered
end

local function newlines(s) local _, n = s:gsub("\n", "") return n end

--- The scanner's state while it walks a chunk: the line, the debug call it is inside, the hits.
local function walker(src, path, opts)
  local extra = opts and opts.debugNames
  if extra and extra[1] then
    local set = {}
    for _, n in ipairs(extra) do set[n] = true end
    extra = set
  end
  return { src = src, path = path, i = 1, line = 1, depth = 0, debugAt = nil, last = nil,
           extra = extra, marked = markedLines(src, path), hits = {} }
end

local function record(w, body, line)
  if w.debugAt or w.marked[line] then return end
  for _, u in ipairs(G.glyphUnsafe(body)) do
    if u.cp then
      w.hits[#w.hits + 1] = { path = w.path, line = line, cp = u.cp, char = u.char, text = body:sub(1, 60) }
    end
  end
end

--- Advance over the comment at w.i ("--" seen).
local function comment(w)
  local body, after = longAt(w.src, w.i + 2)
  if body then
    w.line = w.line + newlines(w.src:sub(w.i, after - 1))
    w.i = after
    return
  end
  local e = w.src:find("\n", w.i, true)
  w.i = e or (#w.src + 1)
end

--- A literal: recorded, unless it is the one argument of a debug sink's string call (`NS.Debug "..."`).
local function literal(w, body, after)
  local line = w.line
  w.line = w.line + newlines(w.src:sub(w.i, after - 1))
  w.i = after
  local stringCall = w.last and w.last ~= "string" and isDebugName(w.last, w.extra)
  if not stringCall then record(w, body, line) end
  w.last = "string"
end

--- A quoted or long-bracket literal at w.i: true when one was read.
local function stringAt(w, ch)
  if ch == '"' or ch == "'" then literal(w, quotedAt(w.src, w.i)); return true end
  if ch ~= "[" then return false end
  local body, after = longAt(w.src, w.i)
  if not body then return false end
  literal(w, body, after)
  return true
end

local function name(w)
  local id = w.src:match("^[%a_][%w_]*", w.i)
  w.i = w.i + #id
  w.last = id
end

local function paren(w, ch)
  if ch == "(" then
    w.depth = w.depth + 1
    if not w.debugAt and w.last and w.last ~= "string" and isDebugName(w.last, w.extra) then
      w.debugAt = w.depth
    end
  else
    if w.debugAt == w.depth then w.debugAt = nil end
    w.depth = math.max(0, w.depth - 1)
  end
  w.last = nil
  w.i = w.i + 1
end

--- One step of the walk at w.i.
local function step(w)
  local src, i = w.src, w.i
  local ch = src:sub(i, i)
  if ch == "\n" then w.line = w.line + 1; w.i = i + 1; return end
  if ch:match("%s") then w.i = i + 1; return end
  if ch == "-" and src:sub(i + 1, i + 1) == "-" then return comment(w) end
  if stringAt(w, ch) then return end
  if ch:match("[%a_]") then return name(w) end
  if ch == "(" or ch == ")" then return paren(w, ch) end
  if ch ~= "." and ch ~= ":" then w.last = nil end
  w.i = i + 1
end

function G.scanGlyphSource(text, path, opts)
  local w = walker(text:gsub("\r\n", "\n"), path or "?", opts)
  while w.i <= #w.src do step(w) end
  return w.hits
end

-- ── the repository ─────────────────────────────────────────────────────────────────────────

local ALWAYS_SKIPPED = { "libs/", "tests/", "tools/" }

local function startsWith(s, prefix) return s:sub(1, #prefix) == prefix end

local function tracked()
  if not io.popen then fail("glyph guard: io.popen is unavailable, so this gate cannot run") end
  local p = io.popen("git ls-files -z -- '*.lua' 2>/dev/null")
  if not p then fail("glyph guard: io.popen returned no handle, so this gate cannot run") end
  local data = p:read("*a") or ""
  p:close()
  -- Split on NUL by hand: `%z` is Lua 5.1's spelling and an error in 5.4 (test_eol.lua's reason).
  local out, pos = {}, 1
  while pos <= #data do
    local at = data:find("\0", pos, true) or (#data + 1)
    if at > pos then out[#out + 1] = data:sub(pos, at - 1) end
    pos = at + 1
  end
  if #out == 0 then
    fail("glyph guard: `git ls-files` named no .lua file; git is missing or this is not a "
      .. "repository, and the gate must not be reported as passing")
  end
  table.sort(out)
  return out
end

local function kept(path, opts)
  for _, p in ipairs(ALWAYS_SKIPPED) do if startsWith(path, p) then return false end end
  for prefix in pairs(opts.skip or {}) do if startsWith(path, prefix) then return false end end
  if not opts.include then return true end
  for _, prefix in ipairs(opts.include) do if startsWith(path, prefix) then return true end end
  return false
end

local function checkSkips(opts)
  for prefix, why in pairs(opts.skip or {}) do
    if type(why) ~= "string" or not why:match("%S") then
      fail("glyph guard: opts.skip[" .. string.format("%q", tostring(prefix)) .. "] gives no reason")
    end
  end
end

function G.scanDisplayGlyphs(opts)
  opts = opts or {}
  checkSkips(opts)
  local hits, files = {}, {}
  for _, path in ipairs(opts.paths or tracked()) do
    if opts.paths or kept(path, opts) then
      local f = io.open(path, "rb")
      if not f then fail("glyph guard: cannot read " .. path) end
      local text = f:read("*a")
      f:close()
      files[#files + 1] = path
      for _, h in ipairs(G.scanGlyphSource(text, path, opts)) do hits[#hits + 1] = h end
    end
  end
  return hits, files
end

local SHOWN = 20

function G.assertDisplayGlyphs(opts)
  opts = opts or {}
  local hits = G.scanDisplayGlyphs(opts)
  if #hits == 0 then return end
  local lines = {}
  for k = 1, math.min(#hits, SHOWN) do
    local h = hits[k]
    lines[k] = string.format("  %s:%d  %s  in %q", h.path, h.line, describe(h), h.text)
  end
  if #hits > SHOWN then lines[#lines + 1] = "  ... and " .. (#hits - SHOWN) .. " more" end
  fail((opts.label and (opts.label .. ": ") or "") .. #hits .. " display string character(s) some "
    .. "shipped skin face cannot draw (testkit/glyphs.lua; use ASCII, a catalog icon, or the mono "
    .. "face and a `glyph: mono` marker):\n" .. table.concat(lines, "\n"))
end

local PUBLISHED = { "glyphUnsafe", "assertGlyphSafe", "scanGlyphSource", "scanDisplayGlyphs", "assertDisplayGlyphs" }

return function(Kit)
  G.fail = Kit.fail
  for _, k in ipairs(PUBLISHED) do Kit[k] = G[k] end
  Kit.GLYPH_FACES, Kit.GLYPH_RANGES = FACES, RANGES
end
