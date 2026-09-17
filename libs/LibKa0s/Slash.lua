-- LibKa0s-Slash-1.0 — the slash dispatcher, the help renderer, the schema CLI, and the parser.
--
-- Four-plus copies across the collection in two different shapes, and the divergence is not
-- cosmetic: one shape parses values by bare coercion, so `set barWidth 99999` stores 99999 and
-- `set` on a color prints a table address. This library takes the type-aware shape — clamping,
-- enum validation, color tuples — because a CLI that silently accepts a value it cannot honor is
-- worse than one that refuses.
--
-- What the host keeps, and why it is not squeamishness: the COMMANDS table itself. A host owns its
-- verbs, passes the table in, and renders the same table on its own About page. If the library
-- owned it, an options module rendering that page would have to consume this one — and two
-- libraries reaching for each other is a real dependency cycle. The table crossing between them as
-- plain data is what keeps them independent.
--
-- Depends on LibStub and LibKa0s-Core-1.0, and on no addon framework.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Slash-1.0", 14
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

-- Which version of each FILE in this major is actually live, so version skew is discoverable at
-- runtime rather than by reading source. See docs/releasing.md.
lib.MODULES = lib.MODULES or {}
lib.MODULES.Slash = MINOR

-- ── strings ────────────────────────────────────────────────────────────────────────────────

lib.STRINGS = {
  HELP_HEADER      = "v%s \226\128\148 slash commands",
  HELP_ALIAS       = " (|cFFFFFF00%s|r is an alias for |cFFFFFF00%s|r)",
  UNKNOWN_COMMAND  = "unknown command '%s'",
  -- Green header, azure group headings. Lowercase hex, deliberately: only the command-row
  -- formatter above converges on uppercase, and quietly recasing these would be a user-visible
  -- change nobody asked for.
  LIST_HEADER      = "|cff33ff99Available settings|r",
  LIST_GROUP       = "  |cff3399ff[%s]|r",
  LIST_EMPTY       = "No settings registered yet",
  USAGE_GET        = "Usage: %s get <path>",
  USAGE_SET        = "Usage: %s set <path> <value>  (try %s list)",
  USAGE_RESET      = "Usage: %s reset <path>",
  NOT_FOUND        = "Setting not found: %s",
  INVALID          = "Invalid value for %s",
  RESET_ALL        = "All settings reset to defaults",
  VERSION          = "v%s",
  NONE             = "(none)",
  ERR_BOOL         = "expected true/false/on/off/1/0/yes/no",
  ERR_NUMBER       = "expected a number",
  ERR_STRING       = "expected a value",
  ERR_ALLOWED      = "allowed values: %s",
  ERR_COLOR        = "expected: r g b [a] (each 0-1 or 0-255)",
  ERR_TYPE         = "unknown setting type '%s'",
}

-- ── the disabled gate ──────────────────────────────────────────────────────────────────────
--
-- Disabled means the addon is NOT RUNNING, so a dispatcher that kept answering `get`, `set`,
-- `lock` and every host feature verb would be the slash half of the draw gate: the player has
-- switched the addon off and it still talks back as though it were working. Exactly three verbs
-- answer normally, every other input answers ONE line, and the line is the collection's rather
-- than the addon's.
--
-- THE WORDING LIVES HERE AND NOWHERE ELSE. It is one sentence, so re-spelling it per addon costs
-- nothing and is exactly why eleven addons would each end up with their own — one saying "disabled",
-- one "turned off", one adding a second line about the settings panel — and a player who uses four
-- of them reads four different answers to the same question. The launcher's left-click prints this
-- same line from this same member; it MUST NOT be re-spelled host-side.
--
-- The format is exported beside the builder so a conformance suite can match against the SHAPE
-- rather than hard-code the words, which is the difference between a suite that pins the wording
-- and a suite that has to be edited every time the wording is improved.
--
-- Gold FFFFFF00 on the command, which is the same gold lib.FormatRow gives a command in the help
-- index — a player scanning the index and a player reading this line are being shown the same kind
-- of thing, so they are shown the same color. The command carries its leading slash, the rest of
-- the line is default-colored, the dash is an em dash with a single space either side to match the
-- row formatter, and there is no trailing colon (house style) and no trailing period.
lib.DISABLED_LINE_FORMAT = "%s is disabled \226\128\148 enable it with |cFFFFFF00%s|r"

-- The verbs that still answer while disabled, and the set is DATA rather than a branch buried in
-- dispatch so that a reader can see the whole of it at once and a suite can assert on it.
--
-- It is the standard's twelve RESERVED verbs and nothing else (slash-commands-§2). The dispatcher
-- SURVIVES the disabled state: `help`, `config`, `version`, `enable`, `disable`, `debug`, `perf`
-- and the whole schema CLI — `get`, `set`, `list`, `reset`, `resetall` — keep answering. A player
-- must be able to READ AND REPAIR SETTINGS and to REACH THE PANEL while the addon is off, which is
-- precisely when they are most likely to need to, and `enable` above all, or the switch only goes
-- one way. `debug` and `perf` are diagnostics rather than features: the usual reason to reach for
-- either is that the addon is misbehaving.
--
-- What the gate is left refusing is therefore exactly the HOST'S OWN FEATURE VERBS — the ones that
-- draw, show, hide, track, record, test, clear or export the thing the addon exists to do. That is
-- §2's SHOULD, and it is the only refusal in the disabled state.
--
-- This list read { "enable", "help", "disable" } at minor 12, under the standard's v2.56.0, and is
-- RESTORED here at minor 13 under v2.57.0. The narrowing failed at the first thing anyone tried:
-- `/<slash>` on a disabled addon answered with a refusal instead of the settings panel, which is
-- the one surface a player uses to switch it back on by hand. None of that weakens the stand-down
-- — a disabled addon still registers nothing, runs no timer, draws nothing and writes nothing from
-- a game event. Its command surface is not the addon.
--
-- A host MAY narrow this to the verbs it actually ships, and a host that declines §2's SHOULD MAY
-- widen it to include its own. This library ships exactly ONE default, exported so a host that
-- must name the set names THIS one rather than a copy of it.
lib.LIVE_VERBS = {
  "help", "config", "version", "enable", "disable", "debug",
  "perf", "get", "set", "list", "reset", "resetall",
}

-- ── the formatters ─────────────────────────────────────────────────────────────────────────
--
-- Lib-level and stateless: a host's tests call them directly, and nothing about a rendered row
-- depends on which instance rendered it.

--- One row of a command list: gold command, an em dash with a single space either side, white
--- description. NOT indented — the indent belongs to whoever is rendering, because a chat line
--- needs one to sit under a header and a settings-panel label does not.
function lib.FormatRow(command, description)
  return ("|cFFFFFF00%s|r \226\128\148 |cFFFFFFFF%s|r"):format(tostring(command), tostring(description))
end

--- One `key = value` pair: gold key, white value, no trailing colon. Used by the list rows and by
--- the get/set echo, so the shape reads identically wherever a setting is printed.
function lib.FormatKV(path, valueStr)
  return ("|cFFFFFF00%s|r = |cFFFFFFFF%s|r"):format(tostring(path), tostring(valueStr))
end

-- One row per color channel: named key, positional index, default. Both stored shapes are read,
-- because the collection genuinely holds both: AbsorbTracker keeps { r =, g =, b =, a = } and the
-- Ka0s options color widget writes { r, g, b, a } POSITIONALLY. The named key wins when present,
-- so a host that stores them is rendered exactly as before; a positional table used to read as
-- all-zero.
--
-- A host whose storage is neither shape passes colorDecode on the descriptor. This fallback exists
-- so the common case needs no descriptor at all — the CLI is often the first thing wired up, and
-- rendering every color as {0.00, 0.00, 0.00, 1.00} is a poor first impression of a library that
-- had no hook to fix it.
--
-- Module-level, built once at load: nothing here is allocated per rendered value.
local COLOR_KEYS = { { "r", 1, 0 }, { "g", 2, 0 }, { "b", 3, 0 }, { "a", 4, 1 } }

-- One channel as a NUMBER, or nil when it is a secret. The table itself is never concat-safe; it
-- is the four COMPONENTS that reach %.2f. Never returns false: the `or` chain ends in a numeric
-- default, so nil unambiguously means "unsafe".
local function colorChannel(v, k)
  local n = v[k[1]] or v[k[2]] or k[3]
  if not core.IsConcatSafe(n) then return nil end
  return n
end

-- One formatter per declared row type. A formatter returns the rendered string, or nil to fall
-- through to core.SafeToString — which is how a non-table `color`, a non-empty `string` and an
-- unknown row type all reach the same generic renderer they always have.
--
-- Every formatter guards its input through the Core seam BEFORE the value reaches a format. The
-- invariant that would make that unnecessary, that a stored settings value is never a
-- combat-protected value, is true of every host today, but it is written down nowhere and
-- enforced nowhere: a host whose `d.get` returns a derived or live value (an absorb total, a
-- health fraction) hands us a secret, and a secret RAISES inside `string.format` exactly as it
-- does inside `table.concat`. Guarding the input rather than the output keeps every rendered
-- byte of an ordinary value identical.
local FORMATTERS = {
  color = function(_, v)
    if type(v) ~= "table" then return nil end
    local r = colorChannel(v, COLOR_KEYS[1])
    local g = colorChannel(v, COLOR_KEYS[2])
    local b = colorChannel(v, COLOR_KEYS[3])
    local a = colorChannel(v, COLOR_KEYS[4])
    if not (r and g and b and a) then return core.SECRET end
    return ("{%.2f, %.2f, %.2f, %.2f}"):format(r, g, b, a)
  end,

  number = function(row, v)
    if not core.IsConcatSafe(v) then return core.SECRET end
    if row.fmt then return row.fmt:format(v) end
    return tostring(v)
  end,

  bool = function(_, v) return v and "true" or "false" end,

  string = function(_, v)
    if v == "" then return lib.STRINGS.NONE end
    return nil
  end,
}

--- Render a stored value for display, by the row's declared type.
function lib.FormatValue(row, v)
  row = row or {}
  if v == nil then return "nil" end
  local f = FORMATTERS[row.type]
  -- No formatter can return false, so the `and` is a plain "call it if there is one".
  local s = f and f(row, v)
  if s ~= nil then return s end
  return core.SafeToString(v)
end

-- ── the command primitives ─────────────────────────────────────────────────────────────────
--
-- The vocabulary a sub-command level needs: split the verb off, look it up, render its rows. Two
-- hosts had already copied byte-identical `lowerFirst`/`findCommand` file-locals out of this
-- dispatcher and hand-rolled a SECOND row format beside the library's own, which is precisely the
-- drift the shared formatter exists to end. The DISPATCHER itself is deliberately not here — its
-- control flow is genuinely per-host — but the vocabulary it runs on is.

--- Split `rest` into its leading verb and everything after it.
---
--- The verb is LOWERCASED and the remainder's case is PRESERVED, and the asymmetry is the
--- contract, not an oversight: a verb is an identifier, while the remainder is user data —
--- AceDB profile names and schema paths are both case-sensitive, so folding them would resolve
--- something the user did not name. The remainder also keeps its internal spacing, because a
--- color is several tokens.
function lib.SplitVerb(rest)
  local verb, remainder = (rest or ""):match("^(%S*)%s*(.*)$")
  return (verb or ""):lower(), remainder or ""
end

--- Find one entry in an ordered { name, description, handler } array, or nil.
---
--- The same row shape the `commands` descriptor field has always taken, so a sub level reuses this
--- major's existing vocabulary rather than inventing one. Compares verbatim: callers lowercase
--- through lib.SplitVerb first.
function lib.FindCommand(list, name)
  if type(list) ~= "table" then return nil end
  for _, entry in ipairs(list) do
    if entry[1] == name then return entry end
  end
end

--- Render one command list as rows, prefixed by the chat command that reaches them.
---
--- `indent` defaults to "" — the indent belongs to whoever is rendering, exactly as it does for
--- lib.FormatRow. Every level, top and sub, renders through this one formatter by construction.
function lib.CommandRows(prefix, commands, indent)
  indent = indent or ""
  local out = {}
  if type(commands) ~= "table" then return out end
  for _, entry in ipairs(commands) do
    out[#out + 1] = indent .. lib.FormatRow(prefix .. " " .. entry[1], entry[2])
  end
  return out
end

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

local function parseBool(args)
  local v = lib.ParseBool(args[1])
  if v == nil then return nil, lib.STRINGS.ERR_BOOL end
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
-- Duplicated verbatim in Slash.lua and OptionsWidgets.lua rather than hoisted into Core. The two
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

local function parseNumber(args, row)
  local n = tonumber(args[1])
  if not n then return nil, lib.STRINGS.ERR_NUMBER end
  -- A NUMERIC dropdown constrains rather than clamps. Clamping a value that is merely outside the
  -- list lands BETWEEN two entries, and the renderer then has no label for what is stored — the
  -- row reads as blank and the user cannot tell what they set.
  local allowed = enumList(row)
  if #allowed > 0 then
    for _, item in ipairs(allowed) do
      if tonumber(item.value) == n then return n end
    end
    return nil, lib.STRINGS.ERR_ALLOWED:format(allowedText(allowed))
  end
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
local function parseString(text, row)
  local v = (text or ""):match("^%s*(.-)%s*$")
  if v == "" then return nil, lib.STRINGS.ERR_STRING end
  local allowed = enumList(row)
  -- Only CONSTRAINED when the row declares a list. A free-text row (dialogControl = "EditBox")
  -- carries no `values` at all, and the old code walked an empty list and therefore refused every
  -- value — so that widget type shipped un-settable from the CLI. A constrained row is matched on
  -- the full string, so trailing words after a valid entry are refused rather than dropped.
  if #allowed == 0 then return v end
  for _, item in ipairs(allowed) do
    if tostring(item.value) == v then return v end
  end
  return nil, lib.STRINGS.ERR_ALLOWED:format(allowedText(allowed))
end

local function parseColor(args)
  local r, g, b = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
  local a = tonumber(args[4]) or 1
  if not (r and g and b) then return nil, lib.STRINGS.ERR_COLOR end
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
--- its first four.
function lib.ParseValue(row, text)
  row = row or {}
  if row.type == "string" then return parseString(text, row) end

  local args = {}
  for w in (text or ""):gmatch("%S+") do args[#args + 1] = w end

  if row.type == "bool"   then return parseBool(args)        end
  if row.type == "number" then return parseNumber(args, row) end
  if row.type == "color"  then return parseColor(args)       end
  return nil, lib.STRINGS.ERR_TYPE:format(tostring(row.type))
end

-- ── the instance ───────────────────────────────────────────────────────────────────────────

--- Build a dispatcher for one host. Bare /slash runs the host's `config` verb when it has one
--- (minor 11, slash-commands-§4); `help` prints the index.
---
--- Descriptor:
---   slash        string    required. The command prefix, with its slash: "/at". Every usage line
---                          and every help row is composed from it.
---   commands     table     required. The HOST's ordered { name, description, handler } triples.
---                          Passed in rather than owned, so the host's own About page can render
---                          the same table without that page's library depending on this one.
---   slashAliases table     optional. Other chat commands that reach the same dispatcher, named in
---                          the help header.
---   aliases      table     optional. Map of typed verb -> real verb, for backwards compatibility.
---   print        function  optional. Where lines go. Defaults to the chat frame.
---   version      function  optional. Returns the host's version string.
---   get/set      function  optional. Read and write one setting by path.
---   findRow      function  optional. Resolve a path to a schema row, or nil.
---   allRows      function  optional. Every row, in declaration order.
---   applyDefault function  optional. Restore one row to its default.
---   bulkBegin    function  optional, minor 8. function(act, scope). Called before CliResetAll
---                          writes its first row, act "reset", scope "all". Mute the host
---                          seam's per-row `[Set]` line here (debug-logging-§10).
---   bulkEnd      function  optional, minor 8. function(act, scope, count, err, info). Called once
---                          after the walk, ALWAYS when the bracket was begun: `count` is the rows
---                          the walk called applyDefault for and that returned, INCLUDING rows
---                          already at their default — so it is NOT debug-logging-§10's N; `err`
---                          the raised value if the walk raised (it is re-raised after this
---                          returns), `info` the Options major's table — `info.profileReset` is
---                          always false here, since no Slash walk resets a profile. Unmute and
---                          emit `[Set] reset all: N rows` here, with N the host's OWN tally of
---                          writes that changed a stored value, never `count`.
---   parse        function  optional, defaults to lib.ParseValue. Handed the row and the whole
---                          remainder after the path, untrimmed; lib.ParseValue gives a `string`
---                          row all of it (minor 10).
---   format       function  optional, minor 5. function(row, storedValue) -> string. Renders a
---                          value for display, replacing lib.FormatValue outright, at every one
---                          of the list/get/set/reset echoes. The counterpart of `parse`, for a
---                          row type this library does not know. Handed the value as stored, and
---                          taking precedence over colorDecode.
---   groupKey     function  optional. Row -> the heading it lists under. Defaults to row.page.
---   colorDecode  function  optional. stored -> r, g, b, a. Defaults to reading the named-key
---                          form, then the positional one. Same field name as the Options
---                          descriptor's, so a host passes one pair to both majors.
---   colorEncode  function  optional. r, g, b, a -> stored. Defaults to { r =, g =, b =, a = }.
---   L            table     optional. Locale override, keyed to lib.STRINGS. It does NOT reach the
---                          disabled refusal line: that wording is the collection's rather than the
---                          addon's, and a locale table is the obvious place for eleven addons to
---                          each grow their own version of it.
---   isEnabled    function  optional, minor 12. -> boolean. ABSENT means the gate is OFF and this
---                          dispatcher behaves exactly as it did at minor 11, so an un-adopted host
---                          is unaffected. Present and answering false, the verbs in `liveVerbs`
---                          dispatch as usual — as does the bare command, which opens the panel —
---                          and every other verb prints the one refusal line. Asked at dispatch
---                          time, never cached.
---   brandName    string    required WHEN `isEnabled` is given, minor 12. The addon's brand name in
---                          plain text, `Ka0s <Name>` — the same string the LDB object takes as its
---                          `label`. MUST NOT be derived from the TOC Title, which may carry color
---                          escapes.
---   liveVerbs    table     optional, minor 12. Array of the verbs that still answer while
---                          disabled, defaulting to lib.LIVE_VERBS — the standard's twelve reserved
---                          verbs since minor 13. Present so the set is data rather than a
---                          hard-coded branch; a host MAY narrow it to the verbs it ships.
function lib:New(d)
  d = type(d) == "table" and d or {}
  if type(d.slash) ~= "string" or d.slash == "" then
    error(MAJOR .. ":New requires descriptor.slash — the command prefix, e.g. \"/at\"", 2)
  end
  if type(d.commands) ~= "table" then
    error(MAJOR .. ":New requires descriptor.commands — the host's own verb table", 2)
  end

  -- The gate is OFF when `isEnabled` is absent, and that is the whole of the migration story: a
  -- host that has not adopted the stand-down latch yet passes no `isEnabled`, and its dispatcher
  -- behaves byte for byte as it did at minor 11. There is no half-adopted state to reason about.
  local isEnabled = type(d.isEnabled) == "function" and d.isEnabled or nil
  if isEnabled and (type(d.brandName) ~= "string" or d.brandName == "") then
    -- Refused at construction rather than rendered as "nil is disabled" at the one moment a
    -- confused player is reading the line. `brandName` is the plain-text `Ka0s <Name>` a host
    -- already MUSTs as its LDB object's label, and the reuse is load-bearing rather than tidy:
    -- that field already forbids escape sequences, which is what makes it safe to drop into a
    -- colored line, and it means an addon has ONE brand spelling rather than a second one invented
    -- for this message. It MUST NOT be derived from the TOC Title, which may carry color escapes.
    error(MAJOR .. ":New requires descriptor.brandName alongside isEnabled — the plain-text "
      .. "`Ka0s <Name>`, the same string the LDB object takes as its label", 2)
  end
  local liveVerbs = {}
  for _, verb in ipairs(type(d.liveVerbs) == "table" and d.liveVerbs or lib.LIVE_VERBS) do
    liveVerbs[tostring(verb):lower()] = true
  end

  local strings = type(d.L) == "table" and d.L or nil
  local parse   = type(d.parse) == "function" and d.parse or lib.ParseValue
  local aliases = type(d.aliases) == "table" and d.aliases or {}
  local groupKey = type(d.groupKey) == "function" and d.groupKey
    or function(row) return row.page or "settings" end

  local emit = type(d.print) == "function" and d.print or function(line)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(line) end
  end

  local Sl = {}
  local annotator

  --- Resolve one user-visible string, host override first.
  ---
  --- rawget, NOT a plain index, and this is load-bearing rather than pedantic. Every Ka0s host's
  --- locale table carries a metatable fallback that answers an unknown key WITH THE KEY (the
  --- standard mandates it — anti-patterns #2). A plain index therefore accepts that synthesized
  --- string for every key, these STRINGS become unreachable, and the host renders raw keys like
  --- LIST_HEADER in place of English. It shipped exactly that way in a consumer's perf panel, for
  --- every string at once, and no headless case caught it because a synthesized value IS a string.
  ---
  --- rawget asks the only question that matters — did the host actually put a value here? — so a
  --- genuine entry still wins and a fallback-only table correctly falls through.
  function Sl:Text(key)
    local v = strings and rawget(strings, key)
    if type(v) == "string" then return v end
    return lib.STRINGS[key]
  end

  --- Whatever the host wants appended to a rendered setting — a note that a value is not the one
  --- actually in effect, most usefully. Applied at exactly three sites: a list row, a get echo and
  --- a set echo. Never on reset or resetall: an explanation of what a value means is noise stapled
  --- to an acknowledgment that the value went away.
  function Sl:SetRowAnnotator(fn)
    annotator = type(fn) == "function" and fn or nil
  end

  local function annotate(row)
    if not annotator then return "" end
    return annotator(row) or ""
  end

  -- Color storage is the HOST's shape, not the library's — the same reasoning
  -- OptionsWidgets.lua's codec carries, and deliberately the same two field names, so a host
  -- passes one pair to both majors. lib.FormatValue already reads the two shapes the collection
  -- actually uses; this is the escape hatch for anything else, and it is the reason kv() no
  -- longer calls the lib-level formatter directly.
  local function formatValue(row, value)
    -- The host's own renderer wins outright, and it is handed the value exactly as STORED. It is
    -- the counterpart `parse` has had since -1.0: a host has always been able to teach this CLI to
    -- READ a value type the library does not know, and had no way to teach it to WRITE one back.
    -- BankLedger's muted-store SET (`type = "table"`) fell through to Core's SafeToString, which
    -- probes table.concat and answers the sentinel — telling the user a plain settings value is
    -- combat-protected. Ahead of the color codec because a host supplying both is saying it owns
    -- rendering; decoding first would hand the hook something other than what the host stored.
    if type(d.format) == "function" then return d.format(row, value) end
    if row and row.type == "color" and type(d.colorDecode) == "function"
        and type(value) == "table" then
      local r, g, b, a = d.colorDecode(value)
      return lib.FormatValue(row, { r = r, g = g, b = b, a = a })
    end
    return lib.FormatValue(row, value)
  end

  local function kv(row, value)
    return lib.FormatKV(row.path, formatValue(row, value)) .. annotate(row)
  end

  -- ── help ─────────────────────────────────────────────────────────────────────────────────

  --- The chat form: indented, because each row sits under a header.
  function Sl:HelpRows() return lib.CommandRows(d.slash, d.commands, "  ") end

  --- The panel form: identical colors and spacing, no indent. A landing page renders each row as
  --- its own label, where a leading indent reads as a mistake rather than as structure.
  function Sl:LandingRows() return lib.CommandRows(d.slash, d.commands, "") end

  function Sl:HelpHeader()
    local version = type(d.version) == "function" and d.version() or "?"
    local header = self:Text("HELP_HEADER"):format(core.SafeToString(version))
    local alias = type(d.slashAliases) == "table" and d.slashAliases[1]
    if alias then header = header .. self:Text("HELP_ALIAS"):format(alias, d.slash) end
    return header
  end

  --- The one refusal line, built in the one place. Every call site — the dispatcher's own gate,
  --- the help header, and the launcher's left-click handler — calls THIS, and a host that spells it
  --- again has created the second wording this member exists to prevent.
  ---
  --- The host's own `print` adds NS.PREFIX exactly as it does for every other line, so the tag is
  --- not built in here: a line that carried its own tag would double it in every host that prints
  --- it correctly.
  function Sl:DisabledLine()
    return lib.DISABLED_LINE_FORMAT:format(tostring(d.brandName or d.slash), d.slash .. " enable")
  end

  --- Is the gate closed right now? `isEnabled` is asked at DISPATCH TIME, never cached: the value
  --- can change between two commands, and a cached answer would refuse the command that follows
  --- the `enable` that just worked.
  local function disabled()
    return isEnabled ~= nil and not isEnabled()
  end

  function Sl:PrintHelp()
    emit(self:HelpHeader())
    -- IMMEDIATELY AFTER THE HEADER, AND UNINDENTED. It is not a refusal OF `help` — the index
    -- answers in full while disabled — but a statement about the whole of it: some of the rows
    -- below are the host's own feature verbs, which are the one thing still refused. Under the
    -- header it reads as that statement; below the rows it would be a footnote to the last command.
    -- Unindented for the same reason: the indent is what marks a line as belonging to the list.
    if disabled() then emit(self:DisabledLine()) end
    for _, line in ipairs(self:HelpRows()) do emit(line) end
  end

  -- ── the schema verbs ─────────────────────────────────────────────────────────────────────

  local function rowFor(path)
    return type(d.findRow) == "function" and d.findRow(path) or nil
  end

  -- Spelled out rather than folded into an `and`/`or` chain. A stored `false` is a perfectly good
  -- value, and `x and false or nil` yields nil — which would render every unticked checkbox in
  -- the addon as "nil" instead of "false".
  local function read(path)
    if type(d.get) ~= "function" then return nil end
    return d.get(path)
  end

  function Sl:BuildListLines()
    local all = type(d.allRows) == "function" and d.allRows() or {}
    if #all == 0 then return { self:Text("LIST_EMPTY") } end

    local out = { self:Text("LIST_HEADER") }
    -- Grouped in the order the rows were declared, not alphabetically: a schema's own order is the
    -- order its panel shows, and a list that disagreed with the panel would be its own puzzle.
    local order, grouped = {}, {}
    for _, row in ipairs(all) do
      local key = groupKey(row)
      if not grouped[key] then
        grouped[key] = {}
        order[#order + 1] = key
      end
      local g = grouped[key]
      g[#g + 1] = row
    end
    for _, key in ipairs(order) do
      out[#out + 1] = self:Text("LIST_GROUP"):format(key)
      for _, row in ipairs(grouped[key]) do
        out[#out + 1] = "    " .. kv(row, read(row.path))
      end
    end
    return out
  end

  function Sl:CliList()
    for _, line in ipairs(self:BuildListLines()) do emit(line) end
  end

  function Sl:CliGet(rest)
    local path = (rest or ""):match("^(%S+)")
    if not path then return emit(self:Text("USAGE_GET"):format(d.slash)) end
    local row = rowFor(path)
    if not row then return emit(self:Text("NOT_FOUND"):format(path)) end
    emit(kv(row, read(row.path)))
  end

  function Sl:CliSet(rest)
    local path, value = (rest or ""):match("^(%S+)%s*(.*)$")
    if not path then return emit(self:Text("USAGE_SET"):format(d.slash, d.slash)) end
    local row = rowFor(path)
    if not row then return emit(self:Text("NOT_FOUND"):format(path)) end

    local v, err = parse(row, value or "")
    if v == nil then
      emit(self:Text("INVALID"):format(row.path))
      if err and err ~= "" then emit("  " .. err) end
      return
    end

    -- Written in the host's own color shape. The lib-level parser answers the named-key form
    -- because that is what it has always answered and hosts read it directly; a host that stores
    -- another shape says so once, on the descriptor, rather than translating at every read site.
    if row.type == "color" and type(d.colorEncode) == "function" and type(v) == "table" then
      v = d.colorEncode(v.r, v.g, v.b, v.a)
    end
    if type(d.set) == "function" then d.set(row.path, v) end
    -- Re-read rather than echo what was parsed: a clamped number is only visible to the user
    -- because the echo reports what was actually stored.
    emit(kv(row, read(row.path)))
  end

  --- Reset ONE setting. There is deliberately no page-shaped form: a page is a property of a
  --- settings panel, and every such panel already carries a Defaults button that resets its page.
  function Sl:CliReset(rest)
    local path = (rest or ""):match("^(%S+)")
    if not path then return emit(self:Text("USAGE_RESET"):format(d.slash)) end
    -- Not lowercased. A path is case-sensitive, so folding it would resolve a setting the user did
    -- not name.
    local row = rowFor(path)
    if not row then return emit(self:Text("NOT_FOUND"):format(path)) end
    if type(d.applyDefault) == "function" then d.applyDefault(row) end
    emit(lib.FormatKV(row.path, formatValue(row, read(row.path))))
  end

  --- Run one bulk act inside the host's optional bracket (minor 8). The same contract, field names
  --- and error semantics as the Options major's, so a host passes one pair to both: debug-logging-§10
  --- makes a bulk reset through the helper ONE flow line with a row count, and the host mutes its
  --- per-row `[Set]` between bulkBegin and bulkEnd.
  ---
  --- Unbracketed — neither field a function — the walk runs bare, exactly as at minor 7: no pcall,
  --- and a raising row escapes with its own stack. Bracketed, a begun bracket always closes:
  --- bulkBegin and the walk share one pcall, bulkEnd runs once with `count` (the rows handed to
  --- applyDefault that returned, a row already at its default included — the host tallies §10's N
  --- itself) and the raised value if any, and only then is that value re-raised unchanged.
  ---
  --- bulkEnd's fifth argument is the Options major's `info` table. No Slash walk resets a profile,
  --- so `info.profileReset` is always false here and a host passing one pair to both majors always
  --- logs its `[Set] <act> <scope>: N rows` line for a resetall.
  local function runBulk(act, scope, walk)
    local begin, finish = d.bulkBegin, d.bulkEnd
    local count = 0
    local info = { profileReset = false }
    local function write(row)
      if type(d.applyDefault) == "function" then
        d.applyDefault(row)
        count = count + 1
      end
    end
    if type(begin) ~= "function" and type(finish) ~= "function" then
      walk(write)
      return
    end
    local ok, err = pcall(function()
      if type(begin) == "function" then begin(act, scope) end
      walk(write)
    end)
    if type(finish) == "function" then finish(act, scope, count, err, info) end
    if not ok then error(err, 0) end
  end

  --- Bracketed as act "reset", scope "all" (minor 8). The acknowledgment is printed after the
  --- bracket closes, and not at all if the walk raised.
  function Sl:CliResetAll()
    local all = type(d.allRows) == "function" and d.allRows() or {}
    runBulk("reset", "all", function(write)
      for _, row in ipairs(all) do write(row) end
    end)
    emit(self:Text("RESET_ALL"))
  end

  function Sl:CliVersion()
    local version = type(d.version) == "function" and d.version() or "?"
    emit(self:Text("VERSION"):format(core.SafeToString(version)))
  end

  -- ── dispatch ─────────────────────────────────────────────────────────────────────────────

  local function findCommand(name)
    for _, entry in ipairs(d.commands) do
      if entry[1] == name then return entry end
    end
  end

  function Sl:OnSlash(msg)
    local raw = (msg or ""):match("^%s*(.-)%s*$") or ""
    -- Asked ONCE per dispatch rather than at each of the exits below, so a host whose
    -- `isEnabled` reads a database cannot have the answer change halfway through one command.
    local isDown = disabled()

    -- Bare /slash runs the host's `config` verb (minor 11, slash-commands-§4): the settings panel on
    -- its landing page, whose own combat refusal is what a player in a fight sees. `help` is the
    -- index. A host with no `config` verb falls back to the index, as every minor before 11 did.
    --
    -- Disabled, the bare form is UNCHANGED (minor 13, standard v2.57.0). The panel is the one
    -- surface from which a disabled addon gets switched back on by hand, and refusing it — which is
    -- what minor 12 did — hides the off switch from the player looking for it. The settings
    -- registration and the panel body are SETUP rather than features: they stand while the addon
    -- does not.
    if raw == "" then
      local config = findCommand("config")
      if config then return config[3]("") end
      return self:PrintHelp()
    end

    -- Only the verb is lowercased. `rest` keeps its case because schema paths are case-sensitive,
    -- and its internal spacing because a color is several tokens. Unchanged by the gate: an input
    -- is parsed identically whether or not it will be answered, because a gate that parsed
    -- differently would be a second parser.
    local cmd, rest = raw:match("^(%S+)%s*(.*)$")
    cmd  = (cmd or ""):lower()
    rest = rest or ""

    -- Aliases resolve BEFORE the gate, so a host's `on` -> `enable` alias still reaches `enable`
    -- while disabled. Gating the raw word would refuse the alias and honor the verb it names, which
    -- is one surface answering two ways.
    if aliases[cmd] then cmd = aliases[cmd] end

    -- THE GATE. What is left once the twelve reserved verbs have passed is the host's own feature
    -- verbs, and input that is not a verb at all. Each gets the one line and nothing else. Not
    -- `unknown command '<verb>'`, and not the help index: both of those answer "I did not
    -- understand you", and the addon understood perfectly well. It is off.
    --
    -- The schema CLI entry points (CliGet, CliSet, CliList, CliReset, the resetall path,
    -- CliVersion) are reached only through this dispatch, and from minor 13 they are LIVE here:
    -- reading and repairing settings is precisely what a player needs from an addon they have
    -- switched off, and they are the largest thing minor 12 gave up.
    local entry = findCommand(cmd)

    -- THE GATE SITS AFTER THE LOOKUP, and the order is the whole of it. What it must refuse is a
    -- verb this addon SHIPS and is currently standing down from — the note above is right that the
    -- addon understood perfectly well and is simply off. A TYPO is the opposite case: the addon did
    -- not understand, nothing was refused, and slash-commands-§3's `unknown command '<verb>'`
    -- followed by the index is an unqualified MUST that the disabled state does not carve out.
    -- Gating BEFORE the lookup conflated the two and answered a misspelling with "the addon is
    -- disabled" — a true sentence and the wrong answer, since it tells a player who mistyped that
    -- their spelling was fine.
    if isDown and entry and not liveVerbs[cmd] then return emit(self:DisabledLine()) end

    if entry then return entry[3](rest) end

    -- A RESERVED VERB THE HOST NEVER REGISTERED answers exactly as it does when ENABLED, which is
    -- `unknown command` and the index. Minor 13 printed the refusal line here instead, on the
    -- reasoning that the player had named a real verb rather than mistyped. That reasoning was
    -- wrong in the way that matters: a verb is reserved always but REGISTERED WHEN WIRED, so an
    -- addon with a no-combat-path exemption ships no `perf` and `perf` is simply not one of its
    -- commands. Answering it one way while off and another way while on makes the disabled state
    -- look like it swallowed a command the addon never had — five of the eleven consumers reported
    -- exactly that for `/<slash> perf`. Nothing was refused, so nothing says it was.

    emit(self:Text("UNKNOWN_COMMAND"):format(cmd))
    self:PrintHelp()
  end

  return Sl
end
