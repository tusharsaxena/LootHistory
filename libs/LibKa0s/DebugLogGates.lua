-- LibKa0s-DebugLog-1.0 — the change gates: "log this once" and "log this when it changes", on the
-- console instance, re-armed by the console itself; and the at-enable queue, "log this state when
-- logging is turned on".
--
-- ── WHY THIS IS A LIBRARY AND NOT FIVE COPIES ────────────────────────────────────────────────
--
-- A line on a timer-driven path (a render pass, a roster walk, a list signature) is either noise
-- every tick or it is behind a gate that writes it once, or when it changes. Five hosts wrote that
-- gate for themselves (MultiMeters, PanelMaster, KickCD, PartyFrameEnhanced, ConsumableMaster), and
-- none of the five was re-armed by the console's Clear, because Clear offered the host no hook: a
-- cleared console stayed silent until the next change, and a reader took "nothing written" for
-- "nothing happening". Gap G2 of the 2026-09-30 debug-gaps run. The gates live here, and the shell
-- re-arms them on both edges a reader means "start again" by: Clear, and turning logging on. A host
-- that keeps a gate of its own is re-armed through the shell's `onClear` descriptor hook instead.
--
-- ── WHY IT IS A FILE OF ITS OWN AND NOT MORE OF DebugLog.lua ─────────────────────────────────
--
-- The reason DebugLogDiagnostics.lua is one: DebugLog.lua sits at the 1000-line band `CLAUDE.md`
-- keeps on notice. It is NOT a major of its own. It is a secondary file of `LibKa0s-DebugLog-1.0`,
-- paired on the shell's minor with the same idiom, and `lib:New` calls `lib.__installGates` when
-- this file has loaded; when it has not, an instance has no gate members, which a host's
-- degradation stub answers for.
--
-- ── THE CONTRACT ─────────────────────────────────────────────────────────────────────────────
--
-- `D.DebugOnce(key, tag, fmt, ...)` and `D.DebugChanged(key, tag, fmt, ...)` are gated exactly as
-- `D.Debug` is: logging off, they return false at once, stringify nothing and REMEMBER nothing, so
-- a key is never spent on a line nobody saw. Logging on, they format as `D.Debug` formats (every
-- argument through the console's `safeToString`, a pcall'd format, the same fallback line) and
-- answer true when they wrote. Plain functions rather than methods, like `D.Debug`: hosts bind them
-- bare. `D.DebugForget(key)` re-arms one key in both gates. A nil key is a key of its own.
--
-- Memory is bounded: past `GATE_MAX_KEYS` keys in one gate that gate is wiped, which costs a
-- repeated line, never growth. Depends on the DebugLog shell, and through it on Core.
--
-- ── THE AT-ENABLE QUEUE ──────────────────────────────────────────────────────────────────────
--
-- debug-logging-§8 asks for a module's dependencies "once at enable", and the flag is session-only
-- and off at login by design, so a line written from OnEnable through `D.Debug` is gated off and
-- never lands. Gap G4 of the same run: the Launcher's LibDataBroker / LibDBIcon lines were exactly
-- that. `D.DebugAtEnable(tag, fmt, ...)` writes at once when logging is on; while it is off it
-- builds the line NOW (a state line says what the state was when it was written, which is the one
-- place this file stringifies with logging off) and holds it, and the shell's `SetEnabled(true)`
-- writes every held line after its session bracket and the host's summary. The flush is one-shot:
-- a held line is written once, not on every enable edge. For STATE lines only (a dependency found
-- or missing, a registration); an event written this way would land out of time.
--
-- Bounded at `AT_ENABLE_MAX` lines: the first ones are kept (dependencies are written first, at
-- enable) and every later line is dropped and counted, and the flush ends with one `[Debug]` line
-- saying how many. A line identical (tag and text) to one already held is held once, so a Register
-- retried at login is one line. Clear neither drops nor flushes the queue: nothing in it is on
-- screen yet.

local lib = LibStub and LibStub("LibKa0s-DebugLog-1.0", true)
if not lib then return end

local GATES_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own, as DebugLogDiagnostics.lua is: gates
-- that attached to a console from another vendored copy would re-arm on edges that shell never
-- signals, and nothing would say the two came from different copies.
if lib.__gatesMinor and lib.__gatesMinor >= GATES_MINOR
  and lib.__gatesShellMinor == lib.MINOR then return end
lib.__gatesMinor      = GATES_MINOR
lib.__gatesShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.DebugLogGates = GATES_MINOR

-- The most keys one gate remembers before it is wiped. Hosts key by window, frame or list id, a
-- handful each; 256 is well past any of them and small enough that a key per GUID cannot grow the
-- table for a whole session.
lib.GATE_MAX_KEYS = 256

-- The most lines the at-enable queue holds. A host writes a handful at enable (Launcher writes one
-- or two); 32 is room for every module of a host several times over.
lib.AT_ENABLE_MAX = 32

-- A nil key cannot index a table. It stands for itself rather than raising, and rather than
-- sharing a slot with any string a host might pass.
local NIL_KEY = {}

--- A gate's memory: the table, and how many keys it holds, so the bound costs no walk.
local function newMemory() return { keys = {}, n = 0 } end

local function wipeMemory(mem)
  for k in pairs(mem.keys) do mem.keys[k] = nil end
  mem.n = 0
end

local function put(mem, key, value)
  if mem.keys[key] == nil then
    if mem.n >= lib.GATE_MAX_KEYS then wipeMemory(mem) end
    mem.n = mem.n + 1
  end
  mem.keys[key] = value
end

local function forget(mem, key)
  if mem.keys[key] ~= nil then
    mem.keys[key] = nil
    mem.n = mem.n - 1
  end
end

--- Installed by `lib:New` on every instance when this file has loaded. `ctx` carries the one
--- piece of the shell the gates need, `safeToString`. Answers two functions: the re-arm the shell
--- calls on Clear and on turning logging on, and the at-enable flush it calls at the end of
--- `SetEnabled(true)`.
function lib.__installGates(D, ctx)
  local safeToString = ctx.safeToString
  local once, changed = newMemory(), newMemory()

  --- The line `D.Debug` would write for `fmt` and `...`, byte for byte (see D.Debug for why the
  --- format is pcall'd and why the fallback lands rather than drops).
  local function build(fmt, ...)
    local n = select("#", ...)
    if n == 0 then return fmt end
    local parts = {}
    for i = 1, n do parts[i] = safeToString((select(i, ...))) end
    local ok, out = pcall(string.format, fmt, unpack(parts))
    if ok then return out end
    local joined = { safeToString(fmt) }
    for i = 1, n do joined[i + 1] = parts[i] end
    return table.concat(joined, " ")
  end

  --- The first call per key per arming writes; the rest are held.
  function D.DebugOnce(key, tag, fmt, ...)
    if not D:IsEnabled() then return false end
    if key == nil then key = NIL_KEY end
    if once.keys[key] then return false end
    put(once, key, true)
    D:Add(tag, build(fmt, ...))
    return true
  end

  --- Writes when the line (tag and text) differs from the last one written for this key.
  function D.DebugChanged(key, tag, fmt, ...)
    if not D:IsEnabled() then return false end
    if key == nil then key = NIL_KEY end
    local msg = build(fmt, ...)
    local line = tostring(tag) .. "\31" .. tostring(msg)
    if changed.keys[key] == line then return false end
    put(changed, key, line)
    D:Add(tag, msg)
    return true
  end

  --- Re-arm one key in both gates: its next DebugOnce writes, and so does its next DebugChanged.
  function D.DebugForget(key)
    if key == nil then key = NIL_KEY end
    forget(once, key)
    forget(changed, key)
  end

  -- The at-enable queue: held lines, the tag-and-text of each (for the duplicate hold), and how
  -- many were dropped past the bound.
  local held, heldSeen, dropped = {}, {}, 0

  --- A state line: written now when logging is on, held for the next enable edge when it is off.
  --- Answers true when it wrote.
  function D.DebugAtEnable(tag, fmt, ...)
    local msg = build(fmt, ...)
    if D:IsEnabled() then
      D:Add(tag, msg)
      return true
    end
    local line = tostring(tag) .. "\31" .. tostring(msg)
    if heldSeen[line] then return false end
    if #held >= lib.AT_ENABLE_MAX then
      dropped = dropped + 1
      return false
    end
    heldSeen[line] = true
    held[#held + 1] = { tag = tag, msg = msg }
    return false
  end

  local function flush()
    if #held == 0 and dropped == 0 then return end
    local lines, n = held, dropped
    held, heldSeen, dropped = {}, {}, 0
    for i = 1, #lines do D:Add(lines[i].tag, lines[i].msg) end
    if n > 0 then
      D:Add("Debug", ("at-enable queue full: %d later line%s dropped"):format(n, n == 1 and "" or "s"))
    end
  end

  return function() wipeMemory(once); wipeMemory(changed) end, flush
end
