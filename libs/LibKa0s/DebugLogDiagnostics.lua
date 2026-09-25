-- LibKa0s-DebugLog-1.0 — the diagnostics report: one command that writes everything a maintainer
-- needs into the debug console, after the trace the player just reproduced, so one Copy carries
-- both.
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
-- ── THE FOUR THINGS THE REPORT NEVER DOES ────────────────────────────────────────────────────
--
-- It never CLEARS the console: the trace above it is half the evidence. It never reads or writes
-- the debug-logging flag except to print it: the report is written through the ungated append, so
-- it lands with logging off and leaves logging off. It never reads the host's enabled state:
-- whether a disabled addon may run it is the dispatcher's question (Slash's live verbs), not the
-- report's. And it never calls a protected API or does arithmetic on a value it has not proved
-- readable, so it is safe in combat and on a secret value.
--
-- Depends on the DebugLog shell, and through it on Core; on no addon framework.

local lib = LibStub and LibStub("LibKa0s-DebugLog-1.0", true)
if not lib then return end

local DIAG_MINOR = 1
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
-- A major missing from this client is skipped, not reported as an error.
local MAJORS = {
  "Core", "Env", "Compat", "Lifecycle", "Bus", "Schema", "Pool", "Item", "Media", "Widgets",
  "DebugLog", "Slash", "Launcher", "Options", "Perf",
}

-- The chat line's English, for the one case where the shell's STRINGS table does not carry it.
local DIAG_WRITTEN =
  "Diagnostic report written to the debug console: %d lines. Use Copy to share it."

-- ── plain text ─────────────────────────────────────────────────────────────────────────────
--
-- Every line the report writes is stripped of color, texture, atlas and hyperlink escapes, so the
-- Copy text reads cleanly. `||`, WoW's escaped pipe, is protected first and put back after: it is
-- how `out:escape` renders a value whose escapes are the evidence (a chat format string), and a
-- strip that ate half of it would turn `||cff` back into a live color code.

local PIPE = "\1"

local function strip(s)
  s = s:gsub("||", PIPE)
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  s = s:gsub("|H.-|h(.-)|h", "%1")
  s = s:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|K.-|k", "")
  s = s:gsub("|n", " "):gsub("[\r\n]+", " ")
  return (s:gsub(PIPE, "||"))
end

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

-- ── installed on every instance ────────────────────────────────────────────────────────────

--- Called by `lib:New` with the instance and the private pieces of it this file needs:
--- `d` (the descriptor), `emit` (the chat printer), `safeToString`, `append` (Add without the
--- repaint) and `repaint` (one scrollbar and status update).
function lib.__installDiagnostics(D, ctx)
  --- The report as data: `{ lines = { { tag, msg }, ... }, dropped = n, capped = bool,
  --- capsHit = bool }`. Writes nothing, anywhere.
  function D:BuildDiagnostics(spec) return build(D, ctx, spec) end

  --- Build the report and append it to the console: every line through the ungated append, one
  --- repaint at the end, the console shown if it was hidden, and one chat line naming the count.
  --- Never clears, never touches the logging flag. Returns the number of lines written.
  function D:RunDiagnostics(spec)
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
