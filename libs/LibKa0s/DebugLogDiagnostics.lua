-- LibKa0s-DebugLog-1.0 — the diagnostics report: one command that writes everything a maintainer
-- needs into the debug console, after the trace the player just reproduced, so one Copy carries
-- both. And, from minor 11, every other report: `D:Report`, the seam a host's dumps and lists
-- write through, and `D:Serialize`, the table serializer they render a table with.
--
-- ── WHY THIS IS A LIBRARY AND NOT ELEVEN COPIES ──────────────────────────────────────────────
--
-- The Ka0s WoW Addon Standard makes the report a MUST for every addon (debug-logging-§14). What is
-- per-addon is only the CONTENT, the sections that read the addon's own state. Everything around
-- the sections is the same everywhere and is exactly what drifted in the one addon that wrote its
-- own (AuraMaster): the two markers and their brand, the identity header, the cap and the reserve
-- it keeps for the truncated line and the end marker, one pcall per section so a raise costs one
-- line, the secret-safe formatting, the escape stripping, and the append itself. So all of that
-- lives here, and a host writes sections.
--
-- ── WHY IT IS A FILE OF ITS OWN AND NOT MORE OF DebugLog.lua ─────────────────────────────────
--
-- The same reason WidgetsDragHandle.lua is one: DebugLog.lua is close to 900 lines, and the report
-- would have taken it past the 1000-line band `CLAUDE.md` keeps on notice. It is NOT a major of its
-- own. It is a secondary file of `LibKa0s-DebugLog-1.0`, guarded with the same pairing idiom, so a
-- report from one vendored copy can never attach to a console from another without saying so.
-- `lib:New` calls `lib.__installDiagnostics` when this file has loaded; when it has not, an
-- instance simply has no report methods, which is the state a host's degradation stub already
-- answers for.
--
-- ── WHAT A RUN DOES TO THE FLAG (minor 2) ────────────────────────────────────────────────────
--
-- A RUN turns debug logging on for the session, before it writes, when logging is off: through the
-- flag's one seam, `D:SetEnabled(true)`, so the `[Debug] logging enabled` line, the host's `[Init]`
-- summary and the chat ack come first and the player's next reproduction is traced (debug-logging-
-- §14 at v2.71.0, the owner's call of 2026-09-30). It never turns logging OFF, and with logging
-- already on it calls nothing, so there is no second enable line. A host opts out with the
-- descriptor field `diagnosticsEnablesLogging = false`, read at every run; only false opts out.
-- BUILDING the report never touches the flag, and neither does any section: the sections read.
--
-- ── THE FOUR THINGS THE REPORT NEVER DOES ────────────────────────────────────────────────────
--
-- It never CLEARS the console: the trace above it is half the evidence. Its sections never write
-- the debug-logging flag, only print it, and the report is written through the ungated append, so
-- an opted-out run lands with logging off and leaves logging off. It never reads the host's
-- enabled state: whether a disabled addon may run it is the dispatcher's question (Slash's live
-- verbs), not the report's. And it never calls a protected API or does arithmetic on a value it
-- has not proved readable, so it is safe in combat and on a secret value.
--
-- Depends on the DebugLog shell, and through it on Core; on no addon framework.

local lib = LibStub and LibStub("LibKa0s-DebugLog-1.0", true)
if not lib then return end

local DIAG_MINOR = 12
-- Minor 12 (LibKa0s#105, SF-LK-01 of Ka0sAddonsCommonTasks docs/2026-11-25-SEEDS_AND_FOREVERDB): the
-- identity header names LibKa0s-ForeverDB-1.0 among the running majors, and prints one ForeverDB
-- line (present, loaded, its version, and its build and hash when loaded) through that major's
-- Status(), which never loads the data addon, so the report never does either.
-- Minor 11 (LibKa0s#79, LK-79 of Ka0sAddonsCommonTasks docs/2026-11-16-LIBKA0S_ISSUES_75_PLUS): the
-- report seam `D:Report(tag, title, fn)`, the serializer `lib.Serialize` with its instance
-- forwarder `D:Serialize`, and the strip read from the shell (`lib.__stripEscapes`, DebugLog minor
-- 23) rather than kept here as a second copy.
-- Paired on the SHELL's minor as well as this file's own, exactly as WidgetsDragHandle.lua pairs on
-- Widgets': a report that attached to an older console would install methods that call private
-- pieces the shell no longer hands over, and nothing would say the two came from different copies.
if lib.__diagMinor and lib.__diagMinor >= DIAG_MINOR
  and lib.__diagShellMinor == lib.MINOR then return end
lib.__diagMinor      = DIAG_MINOR
lib.__diagShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.DebugLogDiagnostics = DIAG_MINOR

-- The most lines one report may write, markers included. The effective cap is this or `MAX_BUFFER -
-- 100`, whichever is smaller, so a report can never evict itself and always leaves some of the
-- trace above it. A fixed number rather than a share of the buffer: no addon's report is expected
-- past about 600 lines, and a larger buffer should go to trace, not to a longer report.
lib.DIAG_MAX_LINES = 1200

-- The default per-list cap for `out:list`. An unbounded list (every aura id, every loot row) is
-- where a report runs away; a host may pass its own cap per list.
lib.DIAG_MAX_PER_LIST = 40

local TAG      = "Diag"
local WRAP     = 200   -- `out:joined` wraps a line at this many characters
local HEADROOM = 100   -- the lines of trace the cap always leaves below MAX_BUFFER
local RESERVE  = 2     -- the truncated line and the end marker, kept free until the very end
local FLOOR    = 3     -- the smallest cap that still fits the begin marker, truncated and end

-- The majors whose running minors the identity header prints. LibStub has no way to list the
-- libraries it holds (its IterateLibraries is not on every copy), so the names are written down.
-- A major missing from this client is skipped, not reported as an error. The list is in
-- tests/majors.lua order, and tests/test_debuglog_diagnostics.lua fails naming the file when a major
-- that file ships is missing here. Minor 12 adds ForeverDB (v1.114.0); minor 11 added Tooltip (v1.105.0); minor 10 added WaypointArrow (v1.99.0); minor 9 adds Callout (v1.96.0); minor 8 added Role (v1.95.0); minor 7 added IconBrowser (v1.86.0),
-- minor 6 Charts (v1.84.0), minor 5 Toast (v1.79.0), minor 4 Skin, minor 3 Glow and Sim.
local MAJORS = {
  "Core", "Tooltip", "Env", "Compat", "Role", "Lifecycle", "Bus", "Schema", "Pool", "Item", "ForeverDB", "Glow", "Toast", "Callout",
  "WaypointArrow",
  "Charts", "Media", "Skin", "Widgets", "DebugLog", "Slash", "Launcher", "Options", "IconBrowser", "Perf", "Sim",
}

-- The chat line's English, for the one case where the shell's STRINGS table does not carry it.
local DIAG_WRITTEN =
  "Diagnostic report written to the debug console: %d lines. Use Copy to share it."

-- ── plain text ─────────────────────────────────────────────────────────────────────────────
--
-- Every line the report writes is stripped of color, texture, atlas and hyperlink escapes, so the
-- Copy text reads cleanly, and of newlines, so a line stays one line. `||`, WoW's escaped pipe,
-- survives: it is how `out:escape` renders a value whose escapes are the evidence (a chat format
-- string). The strip is the shell's (minor 23), the one `Add` keeps the buffer plain with; read at
-- call time, and paired by this file's guard on the shell's minor, so it is always the live shell's.

local function strip(s) return lib.__stripEscapes(s, true) end

--- `fmt` filled with the already-stringified `...`. The format is pcall'd and the fallback is the
--- one the gated sink uses: a format the stringified arguments cannot satisfy (a `%d` handed the
--- secret sentinel) lands as the format followed by the arguments, space-joined, rather than
--- raising and costing the whole section.
local function render(str, fmt, ...)
  local n = select("#", ...)
  if n == 0 then return str(fmt) end
  local parts = {}
  for i = 1, n do parts[i] = str((select(i, ...))) end
  local ok, text = pcall(string.format, str(fmt), unpack(parts))
  if ok then return text end
  local joined = { str(fmt) }
  for i = 1, n do joined[i + 1] = parts[i] end
  return table.concat(joined, " ")
end

-- ── the writer a section is handed ─────────────────────────────────────────────────────────

local Out = {}
Out.__index = Out

local function newOut(safeToString, cap, perList)
  return setmetatable({
    lines = {}, dropped = 0, capsHit = false,
    _room = cap - RESERVE, _perList = perList, _s = safeToString,
  }, Out)
end

--- Any value as plain report text: through the console's `safeToString`, then stripped.
function Out:str(v) return strip(self._s(v)) end

--- Text as plain report text. The same thing as `str`, named for what the caller is holding.
function Out:plain(s) return strip(self._s(s)) end

--- `|` doubled to `||`, for a value whose escapes are what is being reported. The doubled pipe
--- survives the strip and pastes back into a `/<slash> set` unchanged.
function Out:escape(s) return (self._s(s):gsub("|", "||")) end

local function probeNumber(v) return v + 0 == v end

--- True only for a number that can be compared and added. A secret number raises on both, so the
--- client's own test is asked first where it exists, and the arithmetic is pcall'd either way.
function Out:readable(v)
  if type(v) ~= "number" then return false end
  if type(issecretvalue) == "function" then
    local ok, secret = pcall(issecretvalue, v)
    if not ok or secret then return false end
  end
  local ok, same = pcall(probeNumber, v)
  return ok and same == true
end

--- One report line. Every argument is stringified before the format sees it, so formats are
--- `%s`-only in effect. Past the cap the line is dropped and counted, and `false` comes back.
function Out:add(tag, fmt, ...)
  if #self.lines >= self._room then
    self.dropped = self.dropped + 1
    return false
  end
  self.lines[#self.lines + 1] = { strip(self._s(tag or TAG)), strip(render(self._s, fmt, ...)) }
  return true
end

--- `lead` followed by `parts`, comma-separated, wrapped at `width` (default 200) characters onto
--- indented continuation lines. An empty list writes `lead -`, so "none" and "not printed" read
--- differently.
function Out:joined(tag, lead, parts, width)
  width = tonumber(width) or WRAP
  lead = self:str(lead)
  if type(parts) ~= "table" or #parts == 0 then return self:add(tag, "%s -", lead) end
  local line, first = lead, true
  for i = 1, #parts do
    local part = self:str(parts[i])
    local candidate = line .. (first and " " or ", ") .. part
    if not first and #candidate > width then
      self:add(tag, "%s", line)
      line = "  " .. part
    else
      line = candidate
    end
    first = false
  end
  return self:add(tag, "%s", line)
end

--- `joined` with a cap: past `cap` items (default `lib.DIAG_MAX_PER_LIST`) the rest become one
--- `(+N more)` and the report's per-list flag is set, which the truncated line reports.
function Out:list(tag, lead, items, cap)
  items = type(items) == "table" and items or {}
  cap = tonumber(cap) or self._perList
  if #items <= cap then return self:joined(tag, lead, items) end
  self.capsHit = true
  local head = {}
  for i = 1, cap do head[i] = items[i] end
  head[cap + 1] = ("(+%d more)"):format(#items - cap)
  return self:joined(tag, lead, head)
end

--- `fn(out, ...)` under its own pcall. A raise costs exactly one line, and the report goes on.
function Out:section(name, fn, ...)
  local ok, err = pcall(fn, self, ...)
  if not ok then self:add(TAG, "section %s failed: %s", name, err) end
  return ok
end

local function same(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do
    if not same(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

--- A table value in one line, keys sorted, so a color or a nested setting reads in a stable order.
local function shown(v)
  if type(v) ~= "table" then return v end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  local parts = {}
  for i, k in ipairs(keys) do
    local value = v[k]
    if value == nil then value = v[tonumber(k)] end
    parts[i] = k .. "=" .. tostring(shown(value))
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function asSet(list)
  local set = {}
  for k, v in pairs(type(list) == "table" and list or {}) do
    if type(k) == "number" then set[v] = true else set[k] = v and true or nil end
  end
  return set
end

local function nonDefaultRow(out, row, how)
  if row.sessionOnly or row.hidden == true or type(row.path) ~= "string" then return 0 end
  local value = how.get(row)
  local default
  if how.default then default = how.default(row) else default = row.default end
  if not how.always[row.path] and same(value, default) then return 0 end
  out:add(how.tag, "%s = %s (%s)", row.path, how.format(row, value), how.format(row, default))
  return 1
end

--- Every schema row whose value differs from its default, as `path = value (default)`. Skips
--- `sessionOnly` rows and rows marked `hidden = true`; a path in `opts.always` prints whatever its
--- value. `get(row)` reads the value, `default(row)` the default (`row.default` when omitted), and
--- `format(row, v)` renders one (a one-line table dump when omitted). Returns how many printed.
function Out:nonDefaults(rows, get, default, format, opts)
  opts = type(opts) == "table" and opts or {}
  local how = {
    get = get, default = default, always = asSet(opts.always), tag = opts.tag or "Set",
    format = type(format) == "function" and format or function(_, v) return shown(v) end,
  }
  local n = 0
  for _, row in ipairs(type(rows) == "table" and rows or {}) do
    n = n + nonDefaultRow(self, row, how)
  end
  return n
end

-- ── the identity header ────────────────────────────────────────────────────────────────────

--- A client read, pcall'd: the value, or "unreadable" when the call raised or is missing.
local function read(fn, ...)
  if type(fn) ~= "function" then return "unavailable" end
  local ok, v = pcall(fn, ...)
  if not ok then return "unreadable" end
  return v
end

--- Every file of every LibKa0s major running in this client, as `File minor`. RUNNING, because
--- under LibStub the winning copy of a major may be another addon's vendor, not this one's.
local function runningMinors()
  local parts = {}
  for _, name in ipairs(MAJORS) do
    local major = LibStub("LibKa0s-" .. name .. "-1.0", true)
    local files = {}
    if type(major) == "table" and type(major.MODULES) == "table" then
      for file, minor in pairs(major.MODULES) do
        files[#files + 1] = file .. " " .. tostring(minor)
      end
    end
    table.sort(files)
    for _, f in ipairs(files) do parts[#parts + 1] = f end
  end
  return parts
end

--- The ForeverDB line (minor 12): LibKa0s-ForeverDB-1.0's Status(), when that major is running in
--- this client. Status() never loads the data addon and is not gated on the client, so the line
--- reports what is installed and loaded on either client and the report never loads anything.
local function foreverDB(out)
  local F = LibStub("LibKa0s-ForeverDB-1.0", true)
  if type(F) ~= "table" or type(F.Status) ~= "function" then return end
  local s = F.Status()
  if type(s) ~= "table" then return end
  local parts = { ("ForeverDB: present=%s loaded=%s"):format(s.present and "yes" or "no",
    s.loaded and "yes" or "no") }
  for _, key in ipairs({ "version", "build", "hash" }) do
    if type(s[key]) == "string" then parts[#parts + 1] = key .. "=" .. s[key] end
  end
  out:add(TAG, "%s", table.concat(parts, " "))
end

local function identity(out, D, d)
  -- pcall'd like the client reads: the summary is host code, and a raise here must not cost the
  -- client, locale, flag, combat and minor lines below it, which a broken addon needs most.
  local summary = type(d.initSummary) == "function" and read(d.initSummary) or nil
  if summary ~= nil then out:add(TAG, "%s", summary) end
  if type(GetBuildInfo) == "function" then
    local ok, version, build, stamp, interface = pcall(GetBuildInfo)
    if ok then
      out:add(TAG, "client: version=%s build=%s date=%s interface=%s", version, build, stamp,
        interface)
    else
      out:add(TAG, "client: unreadable")
    end
  end
  out:add(TAG, "locale: %s", read(GetLocale))
  out:add(TAG, "debug logging: %s", D:IsEnabled() and "on" or "off")
  out:add(TAG, "combat: InCombatLockdown=%s UnitAffectingCombat=%s", read(InCombatLockdown),
    read(UnitAffectingCombat, "player"))
  out:joined(TAG, "LibKa0s running:", runningMinors())
  -- pcall'd like the reads above: Status() asks the client about an addon most clients lack.
  if not pcall(foreverDB, out) then out:add(TAG, "ForeverDB: unreadable") end
end

-- ── the report ─────────────────────────────────────────────────────────────────────────────

local function capOf(spec)
  local want = tonumber(spec.maxLines) or lib.DIAG_MAX_LINES
  local cap = math.min(want, (tonumber(lib.MAX_BUFFER) or 0) - HEADROOM)
  return math.max(math.floor(cap), FLOOR)
end

local function brandOf(d, out)
  local brand = d.brandName
  if type(brand) ~= "string" or brand == "" then brand = d.title end
  return out:str(brand)
end

--- The host's sections: `spec.sections` when a caller passed them, else `d.diagnostics()`, called
--- now rather than at New so a module that loaded after the console can supply one.
local function sectionsOf(spec, d)
  if type(spec.sections) == "table" then return spec.sections end
  if type(d.diagnostics) ~= "function" then return {} end
  return d.diagnostics()
end

local function runSections(out, list)
  if type(list) ~= "table" then return end
  for _, entry in ipairs(list) do
    if type(entry) == "table" then
      out:section(tostring(entry[1] or entry.name), entry[2] or entry.fn)
    end
  end
end

local function finish(out, brand)
  local lines = out.lines
  local capped = out.dropped > 0 or out.capsHit
  if capped then
    lines[#lines + 1] = { TAG, ("truncated: %d line(s) omitted, per-list caps hit=%s")
      :format(out.dropped, out.capsHit and "yes" or "no") }
  end
  local total = #lines + 1
  lines[total] = { TAG, ("==== %s diagnostics end: %d line(s) ===="):format(brand, total) }
  return { lines = lines, dropped = out.dropped, capped = capped, capsHit = out.capsHit }
end

local function build(D, ctx, spec)
  spec = type(spec) == "table" and spec or {}
  local d = ctx.d
  local out = newOut(ctx.safeToString, capOf(spec),
    tonumber(spec.maxPerList) or lib.DIAG_MAX_PER_LIST)
  local brand = brandOf(d, out)
  out:add(TAG, "==== %s diagnostics begin ====", brand)
  out:section("identity", identity, D, d)
  local ok, list = pcall(sectionsOf, spec, d)
  if ok then
    runSections(out, list)
  else
    out:add(TAG, "section list failed: %s", list)
  end
  return finish(out, brand)
end

-- ── the table serializer (minor 11) ────────────────────────────────────────────────────────
--
-- What a report renders a table with, so no host reaches for DevTools_Dump, which prints to the
-- chat frame. Ported from Ka0s Consumable Master's `SlashDump.Serialize` (its commit 9d2b26e), the
-- reference the owner's ruling of 2026-11-08 was built on, line for line where a line can be
-- compared: keys sorted numbers, then strings, then everything else; identifier keys bare, other
-- keys bracketed; strings `%q` with the newline escape kept on one line; nested tables two spaces
-- further in; `{}` for an empty one, `{...}` past the depth cap, `<cycle>` for a table already on
-- the current path (so a table shared by two branches renders under both), `<function>`,
-- `<userdata>` and `<thread>` by type, and `... truncated at N lines` past the line cap.
--
-- STRICTER ABOUT SECRETS than the original, because it is a library and a host hands it whatever it
-- holds. A value or key the client calls secret (`issecretvalue`, asked under pcall, and a probe
-- that raises counts as yes) renders as Core's sentinel and is never formatted, compared or matched,
-- all of which raise on a secret; a secret TABLE is never walked. Every other scalar is rendered by
-- the stringifier, which is the console's `safeToString` on an instance, so a concat-hostile value
-- renders the sentinel too. Tables are read rawly (`next`, `rawget`), so neither a `__pairs` nor an
-- `__index` runs. The sort is under pcall (a failed sort walks the table in its own order), and the
-- whole walk is too: a raise keeps the lines so far and adds one `<serialize failed: ...>` line.

local SERIAL_MAX_LINES = 400
local SERIAL_MAX_DEPTH = 6
local SERIAL_INDENT    = "  "

local function sentinel()
  local core = LibStub("LibKa0s-Core-1.0", true)
  return core and core.SECRET or "<secret>"
end

local function isSecret(v)
  if type(issecretvalue) ~= "function" then return false end
  local ok, secret = pcall(issecretvalue, v)
  return not ok or secret == true
end

local function valueText(v, str)
  if isSecret(v) then return sentinel() end
  local tv = type(v)
  if tv == "string" then return (("%q"):format(v):gsub("\\\n", "\\n")) end
  if tv == "function" or tv == "userdata" or tv == "thread" or tv == "table" then
    return "<" .. tv .. ">"
  end
  return str(v)
end

local function keyText(k, str)
  if isSecret(k) then return "[" .. sentinel() .. "]" end
  if type(k) == "string" and k:match("^[%a_][%w_]*$") then return k end
  return "[" .. valueText(k, str) .. "]"
end

-- Numbers, then strings, then any other key by its rendering; a secret key last, never compared.
local function rankOf(k)
  if isSecret(k) then return 4 end
  local t = type(k)
  if t == "number" then return 1 end
  if t == "string" then return 2 end
  return 3
end

local function keyLess(a, b)
  if a.rank ~= b.rank then return a.rank < b.rank end
  if a.rank == 1 or a.rank == 2 then return a.k < b.k end
  if a.rank == 3 then return a.s < b.s end
  return false
end

local function keysOf(tbl, sort)
  local keys = {}
  for k in next, tbl do keys[#keys + 1] = k end
  if not sort then return keys end
  local entries = {}
  for i, k in ipairs(keys) do
    local rank = rankOf(k)
    entries[i] = { k = k, rank = rank, s = rank == 3 and tostring(k) or nil }
  end
  if not pcall(table.sort, entries, keyLess) then return keys end
  for i, e in ipairs(entries) do keys[i] = e.k end
  return keys
end

local function serialOpts(opts)
  opts = type(opts) == "table" and opts or {}
  local maxLines = math.max(1, math.floor(tonumber(opts.maxLines) or SERIAL_MAX_LINES))
  local maxDepth = math.max(1, math.floor(tonumber(opts.maxDepth) or SERIAL_MAX_DEPTH))
  local indent = type(opts.indent) == "string" and opts.indent or SERIAL_INDENT
  return maxLines, maxDepth, indent, opts.sort ~= false
end

--- One nested table's entry: `head` then its rendering, through `emit` and `walk`.
local function entry(w, head, v, pad, depth)
  if type(v) ~= "table" or isSecret(v) then return w.emit(head .. valueText(v, w.str)) end
  if w.open[v] then return w.emit(head .. "<cycle>") end
  if next(v) == nil then return w.emit(head .. "{}") end
  if depth >= w.maxDepth then return w.emit(head .. "{...}") end
  w.open[v] = true
  w.emit(head .. "{")
  w.walk(v, pad .. SERIAL_INDENT, depth + 1)
  w.emit(pad .. "}")
  w.open[v] = nil
end

local function serialize(value, opts, str)
  local maxLines, maxDepth, indent, sort = serialOpts(opts)
  local lines, truncated = {}, false
  local w = { open = {}, maxDepth = maxDepth, str = str }
  function w.emit(line)
    if #lines >= maxLines then truncated = true; return end
    lines[#lines + 1] = line
  end
  function w.walk(tbl, pad, depth)
    for _, k in ipairs(keysOf(tbl, sort)) do
      if truncated then return end
      entry(w, pad .. keyText(k, str) .. " = ", rawget(tbl, k), pad, depth)
    end
  end
  local ok, err = pcall(function()
    if type(value) ~= "table" or isSecret(value) then
      w.emit(indent .. valueText(value, str))
    elseif next(value) == nil then
      w.emit(indent .. "{}")
    else
      w.open[value] = true
      w.walk(value, indent, 1)
    end
  end)
  if not ok then
    local okText, text = pcall(str, err)
    lines[#lines + 1] = ("%s<serialize failed: %s>"):format(indent, okText and text or "?")
  elseif truncated then
    lines[#lines + 1] = ("%s... truncated at %d lines"):format(indent, maxLines)
  end
  return lines, truncated
end

--- `value` as report lines: `lines, truncated`. Writes nothing. `opts`: `maxLines` (400),
--- `maxDepth` (6), `indent` (the first level's prefix, two spaces) and `sort` (`false` walks a
--- table in its own order). Values render through Core's SafeToString; an instance's `D:Serialize`
--- renders them through the console's own `safeToString`.
function lib.Serialize(value, opts)
  local core = LibStub("LibKa0s-Core-1.0", true)
  return serialize(value, opts, core and core.SafeToString or tostring)
end

-- ── the report seam (minor 11) ─────────────────────────────────────────────────────────────
--
-- The owner's ruling of 2026-11-08 (LibKa0s#79): a report, any multi-line read-out a player asks
-- for, goes to the debug console whether or not trace logging is on, the console opens if it is
-- hidden, and chat gets exactly one pointer line. Ka0s Consumable Master's `DL.Report` was the
-- reference, and this is it lifted with the decisions the design recorded: a raising body is caught
-- and costs one line (D2), a report never touches the logging flag (D7), and the pointer counts the
-- header (D8). Unlike the diagnostics report, body lines are not stripped as they are written: the
-- view keeps their colors, and `Add`'s buffer keeps Copy plain (DebugLog minor 23).

local REPORT_TAG = "Report"
local REPORT_WRITTEN = "%s: %d lines written to the debug console. Use Copy to share it."

--- The body, collected: `lines, ok, err`. `fn(out)`, `out(line)` one line through `safeToString`.
local function collect(fn, str)
  local lines = {}
  if type(fn) ~= "function" then return lines, true end
  local ok, err = pcall(fn, function(line) lines[#lines + 1] = str(line) end)
  return lines, ok, err
end

--- The lines a report writes, header first, capped at the diagnostics cap: the header, as much of
--- the body as fits, a truncated line when some did not, and the failure line when `fn` raised.
local function reportLines(ctx, title, body, ok, err)
  local slash = ctx.d.slash
  local header = (type(slash) == "string" and slash ~= "") and (slash .. " " .. title) or title
  local cap = capOf({})
  local reserve = ok and 0 or 1
  local room = cap - 1 - reserve
  local keep, omitted = #body, 0
  if keep > room then keep, omitted = room - 1, #body - (room - 1) end
  local out = { header }
  for i = 1, keep do out[#out + 1] = body[i] end
  if omitted > 0 then out[#out + 1] = ("%s truncated: %d line(s) omitted"):format(title, omitted) end
  if not ok then out[#out + 1] = ("%s failed: %s"):format(title, ctx.safeToString(err)) end
  return out
end

local function runReport(D, ctx, tag, title, fn)
  tag = type(tag) == "string" and tag or REPORT_TAG
  title = type(title) == "string" and title or ctx.safeToString(title)
  local body, ok, err = collect(fn, ctx.safeToString)
  if ok and #body == 0 then return 0 end
  local lines = reportLines(ctx, title, body, ok, err)
  for _, line in ipairs(lines) do ctx.append(tag, line) end
  ctx.repaint()
  if not D:IsShown() then D:Show() end
  local n = #lines
  ctx.emit((D:Text("REPORT_WRITTEN") or REPORT_WRITTEN):format(title, n))
  return n
end

-- ── installed on every instance ────────────────────────────────────────────────────────────

--- Called by `lib:New` with the instance and the private pieces of it this file needs:
--- `d` (the descriptor), `emit` (the chat printer), `safeToString`, `append` (Add without the
--- repaint) and `repaint` (one scrollbar and status update).
function lib.__installDiagnostics(D, ctx)
  --- The report as data: `{ lines = { { tag, msg }, ... }, dropped = n, capped = bool,
  --- capsHit = bool }`. Writes nothing, anywhere.
  function D:BuildDiagnostics(spec) return build(D, ctx, spec) end

  --- A report (minor 11): `fn(out)` writes the body, `out(line)` one line (any value, through the
  --- console's `safeToString`), collected before anything is written. A body that writes nothing
  --- writes nothing, prints nothing and returns 0: the verb refused in chat itself. Otherwise a
  --- `<slash> <title>` header (the title alone with no slash) and the body go to the console under
  --- `tag` (`Report` when it is not a string) through the ungated append, capped at the diagnostics
  --- cap with a truncated line, then one repaint, the console shown if it was hidden, and one
  --- `REPORT_WRITTEN` line through the descriptor's `print`. A raising body still writes what it
  --- collected, plus one `<title> failed: <err>` line, and still points. Never touches the logging
  --- flag and never clears. Returns the lines written, the header included.
  function D:Report(tag, title, fn) return runReport(D, ctx, tag, title, fn) end

  --- `value` as report lines, rendered through the console's `safeToString` (minor 11): see
  --- `lib.Serialize`. A method, so a host's library-absent stub answers it as `Serialize(_, v)`.
  function D:Serialize(value, opts) return serialize(value, opts, ctx.safeToString) end

  --- Build the report and append it to the console: every line through the ungated append, one
  --- repaint at the end, the console shown if it was hidden, and one chat line naming the count.
  --- Never clears. With logging off it first turns logging on through SetEnabled (minor 2), unless
  --- the descriptor sets `diagnosticsEnablesLogging = false`; it never turns logging off. Returns
  --- the number of report lines written (the enable line and the summary are SetEnabled's).
  function D:RunDiagnostics(spec)
    if ctx.d.diagnosticsEnablesLogging ~= false and not D:IsEnabled() then D:SetEnabled(true) end
    local report = build(D, ctx, spec)
    for _, line in ipairs(report.lines) do ctx.append(line[1], line[2]) end
    ctx.repaint()
    if not D:IsShown() then D:Show() end
    local n = #report.lines
    ctx.emit((D:Text("DIAG_WRITTEN") or DIAG_WRITTEN):format(n))
    return n
  end

  --- The standard's `debug` words, for a host that wants them from one place: `diagnostics` runs
  --- the report (tested FIRST, case-insensitively), `on` and `off` set the flag, and anything else
  --- answers false so the host keeps its own fallback — its window toggle, its usage line, or its
  --- own topic words. Optional: the standard requires the behavior, not this call.
  function D:DebugVerb(rest)
    local word = (type(rest) == "string" and rest or ""):match("^%s*(%S*)"):lower()
    if word == "diagnostics" then
      D:RunDiagnostics()
      return true
    end
    if word == "on" or word == "off" then
      D:SetEnabled(word == "on")
      return true
    end
    return false
  end
end
