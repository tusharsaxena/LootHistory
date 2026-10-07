-- LibKa0s-Slash-1.0 — the type-aware value parser behind `set`: lib.ParseBool and lib.ParseValue.
--
-- ── WHY IT IS A FILE OF ITS OWN AND NOT MORE OF Slash.lua ────────────────────────────────────
--
-- Because of `layout-§1`. Slash.lua came into the 1000–1500 band at 1030 lines on 2026-10-01, and
-- the parser block was the seam its band entry named, the cut tests/test_slash_parse.lua had
-- already made on the suite side. It moved here unchanged at Slash minor 19. It reads nothing of the
-- shell's but `lib` (lib.STRINGS, for the default resolver, restated below as `libText`).
--
-- It is NOT a major of its own: it is part of `LibKa0s-Slash-1.0`, guarded with the multi-file
-- idiom the other majors' secondary files use, so a parser from one vendored copy never pairs with
-- a shell from another without saying so. A payload without this file loads whole and has no
-- lib.ParseBool and no lib.ParseValue; an instance's `set` then refuses with one line naming this
-- file (Slash.lua's `parseMissing`), unless the host passes its own `parse`.

local lib = LibStub and LibStub("LibKa0s-Slash-1.0", true)
if not lib then return end

local PARSE_MINOR = 2
-- Paired on the SHELL's minor as well as this file's own: a parser that attached to an older shell
-- would publish lib.ParseValue beside a `lib.MODULES` the shell owns, and nothing would say the two
-- came from different vendored copies.
if lib.__parseMinor and lib.__parseMinor >= PARSE_MINOR
  and lib.__parseShellMinor == lib.MINOR then return end
lib.__parseMinor      = PARSE_MINOR
lib.__parseShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.SlashParse = PARSE_MINOR

-- The default key -> string resolver, as Slash.lua's: the library's own strings.
local function libText(key) return lib.STRINGS[key] end

-- ── the parser ─────────────────────────────────────────────────────────────────────────────
--
-- Type-aware, and that is the whole point of taking this shape rather than the coercing one. A
-- number out of range CLAMPS rather than failing, because a user typing a width larger than the
-- panel allows means "as wide as it goes"; a string outside its enum FAILS, because there is no
-- such reading of a misspelt texture name.
--
-- Failure is signaled by a nil first return plus a message. A row type whose valid value could
-- itself be nil would be indistinguishable from an error — none exists, and adding one would be a
-- contract change, not a new type.

-- The exact eight-word set lib.STRINGS.ERR_BOOL already advertises. Module-level and booleans
-- only, so a miss is unambiguously nil rather than a stored false.
local BOOL_WORDS = {
  ["true"] = true,  ["1"] = true,  ["on"]  = true,  ["yes"] = true,
  ["false"] = false, ["0"] = false, ["off"] = false, ["no"] = false,
}

--- One boolean word, case-insensitively, or nil.
---
--- nil means "not a boolean word" — never "false" — which is what lets a caller implement
--- toggle-on-absent rather than having to distinguish the two by re-reading the raw text.
function lib.ParseBool(word)
  if type(word) ~= "string" then return nil end
  return BOOL_WORDS[word:lower()]
end

local function parseBool(args, S)
  local v = lib.ParseBool(args[1])
  if v == nil then return nil, S("ERR_BOOL") end
  return v
end

-- Both enum shapes the collection actually declares, normalized to one ordered list of
-- { value =, text = }.
--
--   ordered array   { { value = "SHORT", text = "Short" }, ... }   the Ka0s options schema
--   key map         { SHORT = "Short", LONG = "Long" }             AceGUI's own SetList shape
--   key set         { SHORT = true, LONG = true }                  the degenerate key map
--
-- The array is identified by its FIRST element being a table carrying `value`; nothing else in
-- play can look like that, so the two are distinguishable without a declared discriminator.
-- Array POSITION is the order — that is the entire point of the shape — so `sorting` is ignored
-- there. A key map keeps the existing rule: `sorting` if the row declares one, else sorted keys.
--
-- Evaluated at call time, not at load: a host's media list is populated by another addon and is
-- not knowable when the schema row is declared.
--
-- Duplicated verbatim in SlashParse.lua and OptionsWidgets.lua rather than hoisted into Core. The two
-- readers MUST agree — a CLI that accepts a value the dropdown cannot display is worse than
-- either being wrong alone — but hoisting would raise NEEDS_CORE in two majors, and
-- docs/releasing.md is explicit that a floor raise is a breaking change to the VENDORING: every
-- consumer carrying a stale Core.lua would lose both majors outright. The agreement is pinned by
-- a cross-major parity case instead, which is the cheaper guarantee.
local function enumList(row)
  local v = type(row.values) == "function" and row.values() or row.values
  if type(v) ~= "table" then return {} end

  if type(v[1]) == "table" and v[1].value ~= nil then
    local out = {}
    for i, item in ipairs(v) do
      out[i] = { value = item.value, text = item.text or tostring(item.value) }
    end
    return out
  end

  local keys = {}
  if type(row.sorting) == "table" then
    for i, k in ipairs(row.sorting) do keys[i] = k end
  else
    for k in pairs(v) do keys[#keys + 1] = k end
    -- Mixed key types would raise on a bare `<`. Homogeneous string keys sort exactly as before.
    table.sort(keys, function(a, b)
      if type(a) == type(b) then return a < b end
      return tostring(a) < tostring(b)
    end)
  end
  local out = {}
  for i, k in ipairs(keys) do
    -- `true` is the SET shape, and rendering it as the label is how a key set becomes a dropdown
    -- of entries all reading "true". The key is the only honest label such a row has.
    local text = v[k]
    out[i] = { value = k, text = type(text) == "string" and text or tostring(k) }
  end
  return out
end

local function allowedText(list)
  local parts = {}
  for i, item in ipairs(list) do parts[i] = tostring(item.value) end
  return table.concat(parts, ", ")
end

local function parseNumber(args, row, S)
  local n = tonumber(args[1])
  -- Lua's tonumber reads "nan", "inf" and "-inf" as numbers, and "1e400" overflows to inf. None of
  -- them is a setting anyone means, and an unbounded row has no clamp to catch them, so they are
  -- refused here as not-a-number, before the enum and the clamp (minor 2; n ~= n is NaN's test).
  if not n or n ~= n or n == math.huge or n == -math.huge then return nil, S("ERR_NUMBER") end
  -- A NUMERIC dropdown constrains rather than clamps. Clamping a value that is merely outside the
  -- list lands BETWEEN two entries, and the renderer then has no label for what is stored — the
  -- row reads as blank and the user cannot tell what they set.
  local allowed = enumList(row)
  if #allowed > 0 then
    for _, item in ipairs(allowed) do
      if tonumber(item.value) == n then return n end
    end
    return nil, S("ERR_ALLOWED"):format(allowedText(allowed))
  end
  -- n stays the SECOND argument on purpose. Lua 5.1's math.max(0/0, -100) answers nan while
  -- math.max(-100, 0/0) answers -100, so this order is what kept a NaN off a bounded row before
  -- the refusal above existed. Non-finite input never reaches here now; keep the order anyway.
  if row.min then n = math.max(row.min, n) end
  if row.max then n = math.min(row.max, n) end
  return n
end

-- A string row takes the WHOLE remainder, trimmed at both ends, never its first token (minor 10).
-- Through minor 9 it took `args[1]`, so `set container.name My Raid Buffs` stored "My" and an enum
-- whose values carry a space -- an LSM font such as "Friz Quadrata TT", the "OUTLINE, MONOCHROME"
-- font flag -- could not be named at all. The truncation was silent: the value was stored, nothing
-- was raised, and only the echo showed it. Internal spacing is kept verbatim, because it is the
-- user's data; only the edges are trimmed.
local function parseString(text, row, S)
  local v = (text or ""):match("^%s*(.-)%s*$")
  if v == "" then return nil, S("ERR_STRING") end
  local allowed = enumList(row)
  -- Only CONSTRAINED when the row declares a list. A free-text row (dialogControl = "EditBox")
  -- carries no `values` at all, and the old code walked an empty list and therefore refused every
  -- value — so that widget type shipped un-settable from the CLI. A constrained row is matched on
  -- the full string, so trailing words after a valid entry are refused rather than dropped.
  if #allowed == 0 then return v end
  for _, item in ipairs(allowed) do
    if tostring(item.value) == v then return v end
  end
  return nil, S("ERR_ALLOWED"):format(allowedText(allowed))
end

local function parseColor(args, S)
  local r, g, b = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
  local a = tonumber(args[4]) or 1
  if not (r and g and b) then return nil, S("ERR_COLOR") end
  -- Rescaled JOINTLY, not per channel: "255 128 0" is one color expressed in one scale, and
  -- dividing only the channels that happen to exceed 1 would mangle the others.
  if r > 1 or g > 1 or b > 1 then r, g, b = r / 255, g / 255, b / 255 end
  if a > 1 then a = a / 255 end
  local function clamp01(n) return math.max(0, math.min(1, n)) end
  return { r = clamp01(r), g = clamp01(g), b = clamp01(b), a = clamp01(a) }
end

--- Parse `text` for `row`. Returns the value, or nil plus a reason.
---
--- A `string` row reads the whole of `text`, trimmed at both ends (minor 10); every other type
--- reads whitespace-separated tokens exactly as before — a bool and a number their first, a color
--- its first four. `textOf` (minor 19, optional) resolves each refusal's key; else lib.STRINGS.
function lib.ParseValue(row, text, textOf)
  row = row or {}
  local S = textOf or libText
  if row.type == "string" then return parseString(text, row, S) end

  local args = {}
  for w in (text or ""):gmatch("%S+") do args[#args + 1] = w end

  if row.type == "bool"   then return parseBool(args, S)        end
  if row.type == "number" then return parseNumber(args, row, S) end
  if row.type == "color"  then return parseColor(args, S)       end
  return nil, S("ERR_TYPE"):format(tostring(row.type))
end
