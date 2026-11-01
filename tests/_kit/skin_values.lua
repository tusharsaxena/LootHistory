-- testkit/skin_values.lua — the typed-value scanner behind tests/_kit/test_skin_values.lua (kit
-- revision 50, FS-GATE of Ka0sAddonsCommonTasks docs/2026-11-01-FULL_SKINNING): a pure reader of
-- Lua source that names every value typed where a skin token belongs, sorts out the ones the
-- collection's rulings leave alone, and leaves the rest to the suite.
--
-- WHAT IT LOOKS FOR. Two kinds of typed value, each with its shapes:
--
--   color    a numeric literal in a color position of a paint call (V.COLOR_ARGS, plus the host's
--            `calls`) or of a CreateColor, typed outright or as a fallback (`c.r or 1`); a `|cff`
--            escape in a string; a `{ text, r, g, b }` row of components, the shape a tooltip line
--            table feeds AddLine.
--   texture  a client path in a string, under Interface\ or Fonts\, wherever it stands; a literal
--            handed to a texture setter or an atlas setter (V.TEXTURE_SETTERS): a path, a name or a
--            file id. Fonts are here because a face is drawn from a path the same way a bar is.
--
-- An ALPHA literal over token components (`SetColorTexture(r, g, b, 0.95)`) is no hit: it is the
-- surface's opacity, the same under every skin. Comments never reach a shape, and a client path
-- counts only inside a string, because the lexer below tells them apart.
--
-- WHAT IT LEAVES ALONE. V.PATH_RULES out of scope by file, then V.COLOR_RULES and V.TEXTURE_RULES by
-- hit: each row is a category, named after the ruling that left that value alone. A hit a rule takes
-- carries `category`; `check` answers the rest, after the host's own rows. A category is kept narrow
-- on purpose: it reads what the line says, and a client default counts only in a fallback's shape, so
-- `bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")` is still a hit. So is any
-- path handed to SetStatusBarTexture, which is `bar.texture`'s place whatever the path, a font face
-- for `font.body`'s, and white no tint follows on the same object, which is white under every skin.
--
-- It holds no state and loads nothing, so tests/test_kit_skin_values.lua can plant whatever it likes.

local V = {}

--- Where a host's drawn code lives: the tracked `.lua` under these, as `git ls-files` patterns. A
--- host's `paths` replaces them.
V.SCOPE = { "core/*.lua", "modules/*.lua", "settings/*.lua" }

--- Call name -> the argument positions that hold color components.
V.COLOR_ARGS = {
  SetTextColor = { 1, 2, 3 }, SetColorTexture = { 1, 2, 3 }, SetVertexColor = { 1, 2, 3 },
  SetBackdropColor = { 1, 2, 3 }, SetBackdropBorderColor = { 1, 2, 3 },
  SetStatusBarColor = { 1, 2, 3 }, SetShadowColor = { 1, 2, 3 }, SetSwipeColor = { 1, 2, 3 },
  AddLine = { 2, 3, 4 }, AddDoubleLine = { 3, 4, 5, 6, 7, 8 },
}

--- The setters whose first argument names a texture or an atlas.
V.TEXTURE_SETTERS = {
  "SetTexture", "SetNormalTexture", "SetPushedTexture", "SetHighlightTexture", "SetDisabledTexture",
  "SetCheckedTexture", "SetDisabledCheckedTexture", "SetThumbTexture", "SetStatusBarTexture",
  "SetAtlas", "SetNormalAtlas", "SetPushedAtlas", "SetHighlightAtlas", "SetDisabledAtlas",
}

-- ── the lexer ────────────────────────────────────────────────────────────────────────────────

--- The byte after the long bracket that opens at `i`, or nil when none opens there.
local function longClose(src, i)
  local eq = src:match("^%[(=*)%[", i)
  if not eq then return nil end
  local _, stop = src:find("]" .. eq .. "]", i + #eq + 2, true)
  return (stop or #src) + 1, #eq + 2
end

--- The byte after the quoted string that opens at `i`. A string left open ends with its line.
local function quotedClose(src, i)
  local q, j = src:sub(i, i), i + 1
  while j <= #src do
    local c = src:sub(j, j)
    if c == "\\" then j = j + 2
    elseif c == q then return j + 1
    elseif c == "\n" then return j
    else j = j + 1 end
  end
  return #src + 1
end

--- `s` with everything but its line breaks turned to spaces, so byte positions and lines hold.
local function blank(s) return (s:gsub("[^\n]", " ")) end

--- The byte after the comment that opens at `i`.
local function commentClose(src, i)
  local stop = longClose(src, i + 2)
  if stop then return stop end
  return src:find("\n", i, true) or (#src + 1)
end

--- `src` read as Lua: `code` with comments blanked, `bare` with string bodies blanked as well (the
--- quotes stay, so an argument still reads as a string), both the length of `src`, and `strings`,
--- each `{ pos, body }`.
local function lex(src)
  local code, bare, strings, i = {}, {}, {}, 1
  local function take(stop, codeText, bareText)
    code[#code + 1], bare[#bare + 1] = codeText, bareText
    i = stop
  end
  while i <= #src do
    local c = src:sub(i, i)
    local stop, open = nil, nil
    if c == "-" and src:sub(i, i + 1) == "--" then
      stop = commentClose(src, i)
      local gap = blank(src:sub(i, stop - 1))
      take(stop, gap, gap)
    elseif c == '"' or c == "'" then stop, open = quotedClose(src, i), 1
    elseif c == "[" then stop, open = longClose(src, i) end
    if open then
      local text = src:sub(i, stop - 1)
      strings[#strings + 1] = { pos = i, body = text:sub(open + 1, -open - 1) }
      take(stop, text, text:sub(1, open) .. blank(text:sub(open + 1, -open - 1)) .. text:sub(-open))
    elseif not stop then take(i + 1, c, c) end
  end
  return table.concat(code), table.concat(bare), strings
end

-- ── arguments and positions ──────────────────────────────────────────────────────────────────

local OPENS, CLOSES = { ["("] = true, ["{"] = true, ["["] = true }, { [")"] = true, ["}"] = true, ["]"] = true }

--- Split an argument list at its top-level commas. String bodies are blanked before it gets here,
--- so only the brackets nest.
local function splitArgs(s)
  local args, depth, start = {}, 0, 1
  for i = 1, #s do
    local c = s:sub(i, i)
    if OPENS[c] then depth = depth + 1
    elseif CLOSES[c] then depth = depth - 1
    elseif c == "," and depth == 0 then
      args[#args + 1] = s:sub(start, i - 1)
      start = i + 1
    end
  end
  args[#args + 1] = s:sub(start)
  return args
end

--- A numeric literal: `.5`, `1.`, `0x10`. The lead keeps out a name tonumber would read, `inf`.
local function isNumber(arg) return arg:find("^%s*%-?%.?%d") ~= nil and tonumber(arg) ~= nil end

--- A number typed in a color position: outright, or as the fallback of `c.r or 1`.
local function isTyped(arg)
  if isNumber(arg) then return true end
  local tail = arg:match("%f[%a]or%s+(%S+)%s*$")
  return tail ~= nil and isNumber(tail)
end

--- The 1-based line of byte `pos`, from the sorted line-start offsets.
local function lineOf(starts, pos)
  local lo, hi = 1, #starts
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if starts[mid] <= pos then lo = mid else hi = mid - 1 end
  end
  return lo
end

--- Every `[from, to]` span the pattern's match fills in `text`, sorted by nature of `find`.
local function spansOf(text, pattern, spans)
  local init = 1
  while true do
    local s, e = text:find(pattern, init)
    if not s then return spans end
    spans[#spans + 1] = { s, e }
    init = e + 1
  end
end

local function inSpans(spans, pos)
  for _, span in ipairs(spans) do
    if pos >= span[1] and pos <= span[2] then return true end
  end
  return false
end

-- ── the shapes ───────────────────────────────────────────────────────────────────────────────

--- Every match of `pattern` in the bare text, its capture an argument list: fn(pos, args list).
local function eachArgs(bare, pattern, fn)
  local init = 1
  while true do
    local s, e, list = bare:find(pattern, init)
    if not s then return end
    init = e + 1
    fn(s, splitArgs(list:sub(2, -2)))
  end
end

--- Every method or field call of `name` in the bare text: fn(pos, args list). `pos` is the `:`.
local function eachCall(bare, name, fn)
  eachArgs(bare, "[:%.]" .. name .. "%s*(%b())", fn)
end

local function numericAt(list, positions)
  for _, p in ipairs(positions) do
    if list[p] and isTyped(list[p]) then return true end
  end
  return false
end

local function scanColorCalls(ctx, calls)
  for name, positions in pairs(calls) do
    eachCall(ctx.bare, name, function(pos, list)
      if numericAt(list, positions) then ctx.add{ kind = "color", shape = "call", pos = pos, call = name, args = list } end
    end)
  end
  -- A global, so no receiver to match on, and a gradient's stops are read here.
  eachArgs(ctx.bare, "%f[%w_]CreateColor%s*(%b())", function(pos, list)
    if numericAt(list, { 1, 2, 3 }) then ctx.add{ kind = "color", shape = "call", pos = pos, call = "CreateColor", args = list } end
  end)
end

local function isComponent(arg)
  local n = isNumber(arg) and tonumber(arg)
  return n and n >= 0 and n <= 1
end

--- `{ text, r, g, b }`: a first field that is no number and no assignment, then three components.
local function isColorRow(list)
  if #list ~= 4 or isNumber(list[1]) or list[1]:find("=", 1, true) then return false end
  return isComponent(list[2]) and isComponent(list[3]) and isComponent(list[4])
end

local function scanColorRows(ctx)
  local init = 1
  while true do
    local s, _, body = ctx.bare:find("(%b{})", init)
    if not s then return end
    init = s + 1
    if isColorRow(splitArgs(body:sub(2, -2))) then ctx.add{ kind = "color", shape = "row", pos = s } end
  end
end

--- A setter's first argument, when it is a literal worth a hit: a non-empty string (the empty one
--- clears the slot) or a file id. Answers the value as text, and the string's byte when it is one.
local function literalArg(ctx, pos, first)
  if isNumber(first) then return (tonumber(first) or 0) > 0 and first:match("%S+") or nil end
  local lead = first:find("[\"'%[]")
  if not lead or first:sub(1, lead - 1):find("%S") then return nil end
  local at = ctx.bare:find("(", pos, true) + lead
  return ctx.stringAt[at], at
end

local function scanTextureCalls(ctx)
  for _, name in ipairs(V.TEXTURE_SETTERS) do
    eachCall(ctx.bare, name, function(pos, list)
      local value, at = nil, nil
      if list[1] then value, at = literalArg(ctx, pos, list[1]) end
      if value and value ~= "" then
        if at then ctx.taken[at] = true end
        ctx.add{ kind = "texture", shape = "call", pos = pos, call = name, value = value }
      end
    end)
  end
end

--- A string's body with its separators as `/`, lower-cased: the one spelling the rules compare.
local function normPath(body) return (body:gsub("[\\/]+", "/"):lower()) end

local function isClientPath(norm) return norm:find("^interface/") or norm:find("^fonts/") end

local function scanStrings(ctx)
  for _, s in ipairs(ctx.strings) do
    if s.body:find("|c[fF][fF]") then
      ctx.add{ kind = "color", shape = "escape", pos = s.pos, body = s.body }
    elseif not ctx.taken[s.pos] and isClientPath(normPath(s.body)) then
      ctx.add{ kind = "texture", shape = "path", pos = s.pos, value = s.body }
    end
  end
end

-- ── the categories ───────────────────────────────────────────────────────────────────────────

--- Files no hit is reported in: `{ category, Lua pattern over the root-relative path }`.
V.PATH_RULES = {
  { "seam", "^core/SkinSetup%.lua$" },   -- the host copy of Ka0s Default every other file reads through
  { "defaults swatch", "^defaults/" },   -- the companion-off look: the player's stored color
  { "locale", "^locales?/" },
}

local function words(line, set)
  for _, word in ipairs(set) do
    if line:find(word) then return true end
  end
  return false
end

local CHAT_FILES = { "Slash%w*%.lua$", "DebugLogSetup%.lua$", "Diagnostics[%w_]*%.lua$" }
local QUALITY_LOOKUPS = { "[Qq]uality%w*%s*[%(%[]", "ITEM_QUALITY" }
local MEANING_GLOBALS = { "RAID_CLASS_COLORS", "CUSTOM_CLASS_COLORS", "C_ClassColor", "GetClassColor",
  "DebuffTypeColor", "GetDebuffTypeColor" }
local function setOf(list)
  local set = {}
  for _, word in ipairs(list) do set[word] = true end
  return set
end

local MEANING_WORDS = setOf({ "CLASS", "CLASSES", "QUALITY", "QUALITIES", "RARITY", "RARITIES", "DISPEL",
  "DISPELS", "DEBUFF", "DEBUFFS", "SCHOOL", "SCHOOLS", "POWER", "POWERS", "REACTION", "REACTIONS", "STAT",
  "STATS", "CATEGORY", "CATEGORIES", "REGION", "REGIONS", "ROLE", "ROLES", "CAST", "CASTS" })
local COLOR_WORDS = setOf({ "COLOR", "COLORS", "HEX", "HEXES", "HUE", "HUES" })

--- A chat line (L13): inside a print's parens, the chat prefix's assignment, or, for an escape, in
--- a slash file, the debug seam or a diagnostics report, whose strings go to chat or the console.
local function isChat(hit, ctx)
  if inSpans(ctx.chat, hit.pos) or hit.text:find("%f[%w_]PREFIX%s*=") then return true end
  return hit.shape == "escape" and words(ctx.path, CHAT_FILES)
end

--- A hyperlink's or an item quality's color: the client's byte for byte. A real link, or a quality
--- looked up in the code: the word in a string, or a name that merely holds it, is neither.
local function isLink(hit)
  if hit.shape ~= "escape" then return false end
  if hit.body:find("|c%x%x%x%x%x%x%x%x|H") ~= nil or hit.text:find("|H%l+:") ~= nil then return true end
  return words(hit.bareText, QUALITY_LOOKUPS)
end

--- An escape builder or a `|c` search pattern: `|cff%02x...`, `"|cff" .. hex`, `|cff(%x+)`. No
--- color byte is typed.
local function isBuilder(hit)
  if hit.shape ~= "escape" then return false end
  return hit.body:find("|c[fF][fF][%%%(%[]") ~= nil or hit.body:find("|c[fF][fF]$") ~= nil
end

--- An escape inside a locale key, `L["...|cff808080...|r"]`, which a translator owns.
local function isLocale(hit, ctx)
  return hit.shape == "escape" and inSpans(ctx.locale, hit.pos)
end

--- The client's meaning colors, read on this line, or a table named for what its colors mean.
local function isMeaning(hit, ctx)
  if words(hit.text, MEANING_GLOBALS) then return true end
  return inSpans(ctx.meaning, hit.pos)
end

--- A 1, 1, 1 call: which setters may take it decides what it is.
local function isWhiteCall(hit, setters)
  if hit.shape ~= "call" or not setters[hit.call] then return false end
  local white = function(arg) return tonumber(arg) == 1 end
  return white(hit.args[1]) and white(hit.args[2]) and white(hit.args[3])
end

local NEUTRAL_SETTERS = { SetVertexColor = true, SetStatusBarColor = true }
local WHITE_SETTERS = { SetColorTexture = true }

--- What tints a white texture, each followed by a `name` of the object it runs on.
local TINT_CALLS = { ":SetVertexColor%s*%(", ":SetGradient%s*%(", ":Get%w*Texture%s*%(%s*%)%s*:SetVertexColor%s*%(" }

--- True when the object `hit`'s call runs on is tinted later in the file. It reads the object's last
--- name, so `self.fill` here and `b.fill` in a paint function are one object; a call on a call's
--- answer names none, and a tint a host's helper does is a host row's to name.
local function tintFollows(hit, ctx)
  local name = ctx.bare:sub(math.max(1, hit.pos - 64), hit.pos - 1):match("([%a_][%w_]*)$")
  if not name then return false end
  for _, call in ipairs(TINT_CALLS) do
    if ctx.bare:find("%f[%w_]" .. name .. call, hit.pos + 1) then return true end
  end
  return false
end

local function isNeutral(hit) return isWhiteCall(hit, NEUTRAL_SETTERS) end
local function isWhiteBase(hit, ctx) return isWhiteCall(hit, WHITE_SETTERS) and tintFollows(hit, ctx) end

local function isPopup(hit, ctx)
  return hit.shape == "escape" and inSpans(ctx.popup, hit.pos)
end

--- `{ category, rule }` in reading order; the first that takes a hit names it.
V.COLOR_RULES = {
  { "chat line (L13)", isChat },
  { "hyperlink or quality color", isLink },
  { "escape builder or search pattern", isBuilder },
  { "locale string", isLocale },
  { "meaning color table (MC)", isMeaning },
  { "neutral 1,1,1 reset", isNeutral },
  { "white base for tinting", isWhiteBase },
  { "StaticPopup text", isPopup },
}

local function hasAny(norm, list)
  for _, tail in ipairs(list) do
    if norm:find(tail, 1, true) then return true end
  end
  return false
end

--- L10: an icon set is not skin data.
local ICON_ART = {
  "interface/buttons/arrow-up-up", "interface/buttons/arrow-down-up", "interface/buttons/ui-sortarrow",
  "interface/buttons/ui-plusbutton-up", "interface/buttons/ui-minusbutton-up",
  "interface/buttons/ui-spellbookicon-", "interface/chatframe/chatframeexpandarrow",
  "interface/minimap/minimaparrow", "interface/raidframe/readycheck-", "interface/common/favoritesicon",
  "interface/friendsframe/informationicon", "interface/petbattles/petbattle-lockicon",
  "interface/targetingframe/ui-classes-circles", "interface/targetingframe/ui-raidtargetingicon",
  "interface/glues/charactercreate/ui-charactercreate-classes",
}
--- A6: the game feedback players know: spark, shield, press and flash, proc glow, the sweep. And
--- D9's resize grip, which a skin tints and never replaces.
local BLIZZARD_ART = {
  "interface/chatframe/ui-chatim-sizegrabber-",
  "interface/castingbar/ui-castingbar-spark", "interface/castingbar/ui-castingbar-small-shield",
  "interface/buttons/buttonhilight-square", "interface/buttons/ui-quickslot-depress",
  "interface/cooldown/", "interface/spellactivationoverlay/",
}
--- What a degraded host or an ignored settings panel draws, and what LibSharedMedia falls back to:
--- each a client default, named here only in a fallback's shape (V.isFallback).
local STOCK_ART = {
  "interface/tooltips/ui-tooltip-border", "interface/tooltips/ui-tooltip-background",
  "interface/targetingframe/ui-statusbar", "interface/dialogframe/ui-dialogbox-",
  "fonts/frizqt__.ttf", "fonts/morpheus.ttf", "fonts/skurri.ttf",
}

--- The line reads as a fallback: `x or "path"`, `return "path"`, or a name that says so.
local function isFallback(hit)
  local t = hit.text
  return t:find("%f[%a]or%s+[\"%[]") ~= nil or t:find("%f[%a]return%s+[\"%[]") ~= nil
    or t:upper():find("FALLBACK", 1, true) ~= nil or t:find("STANDARD_TEXT_FONT", 1, true) ~= nil
end

local function hitPath(hit) return normPath(hit.value or "") end

local function isIcon(hit) return hitPath(hit):find("^interface/icons/") ~= nil end
local function isIconArt(hit) return hasAny(hitPath(hit), ICON_ART) end
local function isBlizzardArt(hit) return hasAny(hitPath(hit), BLIZZARD_ART) end

--- A typed bar: whatever the path, it stands where `bar.texture` belongs.
local function isBarTexture(hit)
  return hit.call == "SetStatusBarTexture" or hit.text:find("[:%.]SetStatusBarTexture%s*%(") ~= nil
end

--- The white texture: a name for it anywhere, or a setter's when a tint on that object follows.
local function isTintBase(hit, ctx)
  if hitPath(hit) ~= "interface/buttons/white8x8" or isBarTexture(hit) then return false end
  return hit.call == nil or tintFollows(hit, ctx)
end

local function isStock(hit) return hasAny(hitPath(hit), STOCK_ART) and isFallback(hit) end
local function isMono(hit) return hitPath(hit):find("^fonts/arialn%.ttf") ~= nil end
local function isLsm(hit) return hit.text:find("[%.:]Fetch%s*%(") ~= nil or hit.text:find("LSM[%.:]Register") ~= nil end
local function isAcePage(hit) return hit.text:find("AceDBOptions", 1, true) ~= nil end

--- A font face: `font.body`'s place, by its file or by the call it stands in.
local function isFontFace(hit)
  return hitPath(hit):find("%.[to]tf$") ~= nil or hit.text:find("[:%.]SetFont%s*%(") ~= nil
end

--- A path into an addon's own folder, its `media/` or a prefix a name is joined to, drawn as art: a
--- bar or a face stands where a token belongs wherever the file lives.
local function isMedia(hit)
  local p = hitPath(hit)
  if not p:find("^interface/addons/") or isBarTexture(hit) or isFontFace(hit) then return false end
  return p:find("/media/", 1, true) ~= nil or p == "interface/addons/"
end

V.TEXTURE_RULES = {
  { "spell or item icon", isIcon },
  { "L10 art", isIconArt },
  { "A6 Blizzard art", isBlizzardArt },
  { "white base for tinting", isTintBase },
  { "degraded or ignored-panel stock path", isStock },
  { "L12 mono", isMono },
  { "LSM pick or client default", isLsm },
  { "Ace profile page", isAcePage },
  { "media/ path", isMedia },
}

local function categoryOf(hit, ctx)
  for _, row in ipairs(hit.kind == "color" and V.COLOR_RULES or V.TEXTURE_RULES) do
    if row[2](hit, ctx) then return row[1] end
  end
  return nil
end

--- The name's words, upper-cased: split at `_`, `.` and a lower-to-upper step, so STATUS is no STAT
--- and BROADCAST no CAST, and ClassColors reads as DISPEL_COLORS does.
local function nameWords(name)
  local found = {}
  for word in (name:gsub("(%l)(%u)", "%1_%2")):gmatch("[^_%.]+") do found[word:upper()] = true end
  return found
end

local function hasWord(found, set)
  for word in pairs(found) do
    if set[word] then return true end
  end
  return false
end

--- The name a table is assigned to reads as a meaning table: a word of what it means, and a color.
local function meaningSpans(bare)
  local spans, init = {}, 1
  while true do
    local s, e, name = bare:find("([%w_%.]+)%s*=%s*%b{}", init)
    if not s then return spans end
    local found = nameWords(name)
    if hasWord(found, COLOR_WORDS) and hasWord(found, MEANING_WORDS) then spans[#spans + 1] = { s, e } end
    init = bare:find("=", s, true) + 1
  end
end

local function chatSpans(bare)
  local spans = {}
  spansOf(bare, "[%w_]*[Pp]rintf?%s*%b()", spans)
  spansOf(bare, "%f[%w_]pout%s*%b()", spans)
  spansOf(bare, "[%.:]Say%s*%b()", spans)
  spansOf(bare, "AddMessage%s*%b()", spans)
  return spans
end

local function popupSpans(bare)
  local spans = {}
  spansOf(bare, "StaticPopupDialogs[%.%[][^=\n]*=%s*%b{}", spans)
  spansOf(bare, "StaticPopup_Show%s*%b()", spans)
  return spans
end

-- ── the scan ─────────────────────────────────────────────────────────────────────────────────

local function lineTable(code)
  local lines, starts, at = {}, {}, 1
  for line in (code .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1], starts[#starts + 1] = line, at
    at = at + #line + 1
  end
  return lines, starts
end

local function byLine(a, b)
  if a.line ~= b.line then return a.line < b.line end
  return a.pos < b.pos
end

local function mergedCalls(extra)
  local calls = {}
  for name, positions in pairs(V.COLOR_ARGS) do calls[name] = positions end
  for name, positions in pairs(extra or {}) do calls[name] = positions end
  return calls
end

--- Every typed value in `src`, sorted: `{ kind, shape, line, text, bareText, pos, value / body / call,
--- category }`. `text` is the line with its comment cut, `bareText` that with its string bodies
--- blanked too, and `category` nil is a value no ruling leaves alone.
--- `opts`: `path` (root-relative, which the file rules read) and `calls` (name -> color positions,
--- on top of V.COLOR_ARGS).
function V.scan(src, opts)
  opts = opts or {}
  src = src:gsub("\r\n", "\n")
  local code, bare, strings = lex(src)
  local lines, starts = lineTable(code)
  local bareLines = lineTable(bare)
  local hits, stringAt = {}, {}
  for _, s in ipairs(strings) do stringAt[s.pos] = s.body end
  local ctx = {
    bare = bare, strings = strings, stringAt = stringAt, taken = {}, path = opts.path or "",
    chat = chatSpans(bare), popup = popupSpans(bare), meaning = meaningSpans(bare),
    locale = spansOf(bare, "%f[%w_]L%s*%b[]", {}),
  }
  function ctx.add(hit)
    hit.line = lineOf(starts, hit.pos)
    hit.text, hit.bareText = lines[hit.line], bareLines[hit.line]
    hit.category = categoryOf(hit, ctx)
    hits[#hits + 1] = hit
  end
  scanColorCalls(ctx, mergedCalls(opts.calls))
  scanColorRows(ctx)
  scanTextureCalls(ctx)
  scanStrings(ctx)
  table.sort(hits, byLine)
  return hits
end

--- The category that takes the whole file at `path` out of scope, or nil.
function V.pathCategory(path)
  for _, row in ipairs(V.PATH_RULES) do
    if path:find(row[2]) then return row[1] end
  end
  return nil
end

-- ── the host's rows ──────────────────────────────────────────────────────────────────────────

local ROW_FIELDS = { "file", "substring", "why", "cause" }
local CAUSE_ID = "^%u[%u%d][%u%d%-]*$"

--- What is wrong with one host row, or nil.
local function rowProblem(row, i)
  if type(row) ~= "table" then return ("row %d is a %s, not { file, substring, why, cause }"):format(i, type(row)) end
  for _, field in ipairs(ROW_FIELDS) do
    if type(row[field]) ~= "string" or row[field] == "" then
      return ("row %d (%s) has no %s"):format(i, tostring(row.file), field)
    end
  end
  if not row.cause:find(CAUSE_ID) then
    return ("row %d (%s) has cause %q, which is no cause id such as L13 or FS-AM-02"):format(i, row.file, row.cause)
  end
  return nil
end

--- Every problem in the host's rows: a missing field or a cause that is no id.
function V.rowProblems(rows)
  local out = {}
  for i, row in ipairs(rows or {}) do
    local problem = rowProblem(row, i)
    if problem then out[#out + 1] = problem end
  end
  return out
end

--- The host row that excuses `hit` in `path`, marking it used; nil when none does.
local function excuse(rows, used, path, hit)
  for i, row in ipairs(rows) do
    if row.file == path and hit.text:find(row.substring, 1, true) then
      used[i] = true
      return row
    end
  end
  return nil
end

--- The sources a host's scan reads: `{ { path, src }, ... }`, the tracked `.lua` under `opts.paths`
--- (default V.SCOPE) at `opts.root`, without the V.PATH_RULES files. Raises when it cannot look: no
--- io.popen, no git or an empty list is a failure and never a pass.
function V.collect(opts)
  opts = opts or {}
  local root = opts.root or "."
  if not io.popen then error("skin values: io.popen is unavailable, so this gate cannot run", 0) end
  local patterns = {}
  for _, pattern in ipairs(opts.paths or V.SCOPE) do patterns[#patterns + 1] = "'" .. pattern .. "'" end
  local p = io.popen("git -C '" .. root .. "' ls-files " .. table.concat(patterns, " ") .. " 2>/dev/null")
  if not p then error("skin values: io.popen returned no handle", 0) end
  local sources = {}
  for path in p:lines() do
    if not V.pathCategory(path) then
      local f = io.open(root .. "/" .. path, "rb")
      if not f then error("skin values: cannot read " .. path, 0) end
      sources[#sources + 1] = { path, f:read("*a") }
      f:close()
    end
  end
  p:close()
  if #sources == 0 then error("skin values: git listed no source files, so nothing was scanned", 0) end
  return sources
end

--- Sort a host's hits: `sources` is what V.collect answers. Answers `bad`, each
--- "path:line: text", and `stale`, each row no hit reached. A row is only ever asked about a hit no
--- category took, so a row that repeats a category goes stale.
function V.judge(sources, opts)
  opts = opts or {}
  local rows, used, bad, stale = opts.rows or {}, {}, {}, {}
  for _, file in ipairs(sources) do
    local hits = V.scan(file[2], { path = file[1], calls = opts.calls })
    for _, hit in ipairs(hits) do
      if not hit.category and not excuse(rows, used, file[1], hit) then
        bad[#bad + 1] = ("%s:%d: [%s] %s"):format(file[1], hit.line, hit.kind, (hit.text:gsub("^%s+", "")))
      end
    end
  end
  for i, row in ipairs(rows) do
    if not used[i] then stale[#stale + 1] = ("%s %q matches nothing"):format(row.file, row.substring) end
  end
  return bad, stale
end

return V
