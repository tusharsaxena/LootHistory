-- LibKa0s-Schema-1.0 — the settings schema's runtime: path primitives, the row registry, the single
-- write seam, the bulk bracket, the reset count and the shape check.
--
-- Nine addons in this collection each carry a settings/Schema.lua, 6188 lines between them, and
-- under the host-specific rows every one of them re-implements the same machinery: split a dotted
-- path, walk it for a read, walk it creating intermediates for a write, compare two stored values
-- by content, index the rows by path, route every write through one helper that validates, stores,
-- logs and reacts (architecture-§5), bracket a bulk act so it logs one line instead of one per row
-- (debug-logging-§10), count the rows a profile reset is about to change, and check the schema's
-- shape at load. Eight path walkers, seven byte-equivalent deep-equal bodies and nine brackets is
-- the drift library-stack-§7 exists to end, and it had already drifted: which row wins on a
-- duplicate path, whether a table value is copied into the store, and whether the bulk line counts
-- rows that were already at their default all differed from host to host.
--
-- WHAT THIS FILE DELIBERATELY DOES NOT DO. It owns no storage: where a row's value lives is the
-- host's `resolveRoot` or the row's own `get`/`set`. It owns no migration, no AceDB defaults, no
-- page ordering and no value formatting (the last is LibKa0s-Slash-1.0's, and this major takes the
-- host's formatter rather than shipping a second one). It sends no message: what a write announces
-- is the host's `announce` (or, for a batch, its `announceBatch`). Every single-consumer write
-- semantic the survey found (per-write old values, skip flags) stays in the host that has it, in
-- front of this seam, rather than becoming a flag on it — library-stack-§7 bar 2. Two semantics
-- left that list at minor 2 because a second consumer arrived for each: a row's post-validate
-- `normalize` (AuraMaster, ConsumableMaster) and the all-or-nothing batch `SetMany`
-- (ConsumableMaster, MultiMeters, KickCD's copy styling). A third is not a host semantic but a
-- load shape: `writeThrough`, the declared paths a host verb writes while the composer that would
-- have declared their rows is absent (options-ui-§1's route (a); eight adopters).
--
-- WHY THE INSTANCE MEMBERS ARE DOT-CALLED. `inst.Set(path, value, id)`, never `inst:Set(...)`. The
-- Options and Slash descriptors take their seams AS VALUES — the flow engine calls
-- `d.set(row.path, value)` — so a member that needed `self` could not be handed over as
-- `set = inst.Set`. Every instance member is a closure bound at :New, and a suite case takes each
-- one as a bare value and calls it to prove it.
--
-- Depends on LibStub and LibKa0s-Core-1.0, and on no addon framework.

-- The Core floor, declared even though not one member of Core is called below — the same
-- LOAD-PAYLOAD check LibKa0s-Lifecycle-1.0 carries (library-stack-§7). A host holding a partial
-- vendored copy must end up with EVERY module of the payload absent rather than a working Schema
-- beside an absent Options, so its own degradation stub answers for all of it at once.
local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Schema-1.0", 2
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

-- Which version of each FILE in this major is actually live. See docs/releasing.md.
lib.MODULES = lib.MODULES or {}
lib.MODULES.Schema = MINOR

local type, pairs, ipairs, tostring, tonumber, pcall, error, rawget =
  type, pairs, ipairs, tostring, tonumber, pcall, error, rawget
local tinsert, floor = table.insert, math.floor

-- The three refusal texts `Set` answers with. The first two are the texts the two largest hosts
-- already print; a host wanting its old wording back puts it in `descriptor.L`.
lib.STRINGS = {
  NOT_FOUND = "Setting not found: %s",
  INVALID   = "Invalid value for %s",
  NO_ROOT   = "Setting has nowhere to be stored yet: %s",
}

-- The bulk line's failure suffix (debug-logging-§10). Not a refusal text, so not in STRINGS: it is
-- part of a debug line whose shape every host in the collection already prints byte for byte.
local STOPPED = " (stopped by an error)"

-- SetMany's options when a caller passes none. Read only, never written.
local NO_OPTS = {}

-- The four Options widget types, the shape check's default when a host names none.
local DEFAULT_TYPES = { bool = true, number = true, string = true, color = true }

-- ── path primitives ─────────────────────────────────────────────────────────────────────────
--
-- Pure, lib-level, and holding no per-host state. Lib-level rather than instance members because a
-- host that keeps its own write seam still calls them, and because a lib-level function is what
-- the published member manifest can gate.

-- One array per distinct path string, built once and handed back by identity forever after.
--
-- MEASURED, NOT TIDY. Two hosts carry a perf ceiling on their read path: AbsorbTracker's dormant
-- repaint went from 312 to 840 bytes/iter when its walker used `gmatch`, against a 320 ceiling,
-- and PartyFrameEnhanced's show decision is pinned at 0 bytes/iter. A memoized split allocates
-- once per distinct path and never again, and the read loop below is an integer `for` over the
-- cached array, so a warm read allocates nothing. The cache is bounded by the distinct paths ever
-- asked for — the schema's own plus whatever a player types into a `get` — which is the bound the
-- two hosts that already memoize accept.
local splitCache = {}
local EMPTY = {}

--- Split a dotted path into its segments. Answers ONE shared array per path string: callers MUST
--- NOT mutate it. Empty segments are dropped (`"a..b"` is `{ "a", "b" }`); a non-string is
--- `tostring`ed first, except nil, which is the empty path rather than the one-segment path "nil".
function lib.SplitPath(path)
  if path == nil then return EMPTY end
  if type(path) ~= "string" then path = tostring(path) end
  local parts = splitCache[path]
  if parts then return parts end
  parts = {}
  for segment in path:gmatch("[^%.]+") do parts[#parts + 1] = segment end
  splitCache[path] = parts
  return parts
end

local splitPath = lib.SplitPath

local function toParts(pathOrParts)
  if type(pathOrParts) == "table" then return pathOrParts end
  return splitPath(pathOrParts)
end

--- Read the value at `pathOrParts` under `root`, starting at segment `first` (default 1). A string
--- path is split through SplitPath; a table is taken as already split, which is what lets a host
--- whose root resolver consumed a leading `container.` segment pass its parts and a first index of
--- 2. Answers nil when `root` is not a table, when any intermediate is not a table, and for the
--- empty path — the root itself is never an answer, because no setting is stored AT the root.
function lib.Read(root, pathOrParts, first)
  if type(root) ~= "table" then return nil end
  local parts = toParts(pathOrParts)
  first = first or 1
  local n = #parts
  if n < first then return nil end
  local node = root
  for i = first, n do
    if type(node) ~= "table" then return nil end
    node = node[parts[i]]
  end
  return node
end

--- Store `value` at `pathOrParts` under `root`, creating intermediates. A non-table intermediate
--- is REPLACED by a fresh table — all eight host copies do this, and a scalar sitting where a
--- section belongs is a stale shape a write is entitled to repair. No-op when `root` is not a table
--- or the path is empty. Stores `value` itself: copying is the write seam's decision, not this one.
function lib.Write(root, pathOrParts, value, first)
  if type(root) ~= "table" then return end
  local parts = toParts(pathOrParts)
  first = first or 1
  local n = #parts
  if n < first then return end
  local node = root
  for i = first, n - 1 do
    local key = parts[i]
    if type(node[key]) ~= "table" then node[key] = {} end
    node = node[key]
  end
  node[parts[n]] = value
end

--- Stored-value equality: `a == b` first (so -0 equals 0 and nil equals nil), then tables by
--- content, both directions, recursively. A key present on one side as `false` and absent on the
--- other is a difference. No cycle detection and no metatable, exactly like the seven host copies
--- this replaces: a stored setting is a tree of plain tables.
local function sameValue(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do
    if not sameValue(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end
lib.SameValue = sameValue

-- Internal and deliberately not exported: a deep copy was refuted as a library member on frequency
-- alone (library-stack-§7 keeps high-frequency, low-content helpers inline). It is used where
-- copying is part of a semantic — the write seam's aliasing guard, `Default`, the tally's snapshot.
local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, vv in pairs(v) do out[k] = deepCopy(vv) end
  return out
end

-- ── the shape check's rules ─────────────────────────────────────────────────────────────────
--
-- Pure, and each one a rule an instance's Validate applies per row. Lib-level locals rather than
-- instance closures because none of them reads a descriptor; none is exported.

--- Validate's options with every malformed field replaced by its fallback: the host's `types` set
--- or the four widget types, the host's `pages` set or nil (no page check), and the host's
--- `defaultsRoot` or nil (no resolution check). A spec that is not a table is the empty spec.
local function validateOptions(spec)
  spec = type(spec) == "table" and spec or {}
  local types = type(spec.types) == "table" and spec.types or DEFAULT_TYPES
  local pages = type(spec.pages) == "table" and spec.pages or nil
  local defaultsRoot = type(spec.defaultsRoot) == "function" and spec.defaultsRoot or nil
  return types, pages, defaultsRoot
end

--- How a schema error names row `i`: its path as text, or `<no path>` when it has none.
local function rowLabel(i, path)
  return ("row #%d (%s)"):format(i, path ~= nil and tostring(path) or "<no path>")
end

--- Print one schema error line through the host's `print`, when it gave one.
local function printSchemaError(print, where, msg)
  if print then print(("|cffff0000schema error|r: %s: %s"):format(where, msg)) end
end

--- Report each malformed field of one table row, in the order Validate prints them: a row nothing
--- can reach (no path, and not an Options bound row carrying both `get` and `set`), then `type`,
--- `page` and `group`.
local function reportFieldErrors(row, hasPath, types, pages, report)
  -- A path-less row carrying both halves of a binding is an Options bound row, which is
  -- legitimately path-less; anything else without a path is a row nothing can reach.
  if not hasPath and not (type(row.get) == "function" and type(row.set) == "function") then
    report("missing or empty `path`")
  end
  if not types[row.type] then report("invalid `type` = " .. tostring(row.type)) end
  if pages and not pages[row.page] then report("invalid `page` = " .. tostring(row.page)) end
  if type(row.group) ~= "string" or row.group == "" then
    report("missing or empty `group`")
  end
end

--- Whether a stored row's path resolves against the host's defaults: true or false, or nil when
--- the check does not apply. architecture-§5: a stored path must resolve against the defaults that
--- hold it, or a typo reads and writes nothing. It does not apply to a row with no path, when there
--- is no `defaultsRoot`, to a sessionOnly row (not stored), or when the root is not a table (the
--- host saying "this row is not in any defaults tree": a profiles page, an AceDBOptions row).
local function resolvesInDefaults(defaultsRoot, row, path, hasPath)
  if not (hasPath and defaultsRoot and not row.sessionOnly) then return nil end
  local parts = splitPath(path)
  local root, first = defaultsRoot(parts, row)
  if type(root) ~= "table" then return nil end
  return lib.Read(root, parts, tonumber(first) or 1) ~= nil
end

-- ── the instance ────────────────────────────────────────────────────────────────────────────

--- One schema runtime for one host. ONE INSTANCE PER ADDON: the bracket, the index and the pending
--- reset count are per instance, and a second instance over the same rows is a second bracket that
--- the first one's writes do not tally into.
---
--- Descriptor fields (only `rows` is required; everything else is read AT CALL TIME, so a host may
--- fill a field such as `announce` after :New, which is the Lifecycle precedent):
---   rows          array     The host's live schema array, held BY REFERENCE and never copied.
---   resolveRoot   function  (parts, instanceId) -> root, first, resolvedId | nil, reason
---   announce      function  (row, path, value, resolvedId) — the post-write tail
---   announceBatch function  (writes, resolvedId) — SetMany's one tail, in place of announce
---   debug         function  (tag, fmt, ...) — the host's debug sink
---   debugEnabled  function  () -> boolean, consulted BEFORE a line is formatted
---   format        function  (row, value) -> string, renders a value for the `[Set]` line
---   print         function  (line), used by Validate only
---   resetExempt   set       { [path] = true }: rows a SWEEP must not reset
---   writeThrough  array     { path, ... }: row-less paths Set still stores (read ONCE, at :New)
---   L             table     overrides lib.STRINGS by key (raw keys only; see text() below)
function lib:New(descriptor)
  local d = type(descriptor) == "table" and descriptor or {}
  if type(d.rows) ~= "table" then
    error(MAJOR .. ": descriptor.rows must be a table", 2)
  end
  local rows = d.rows
  local index = {}
  -- The writeThrough rows: one synthetic `{ path =, writeThrough = true }` per listed path, built
  -- here and handed out by identity forever after, so a write through one allocates nothing. Read
  -- once, like `rows`, because the set is what the host declares its degraded writers reach, not
  -- something a later call may widen.
  local throughRows = {}
  if type(d.writeThrough) == "table" then
    for _, path in ipairs(d.writeThrough) do
      if type(path) == "string" and path ~= "" and not throughRows[path] then
        throughRows[path] = { path = path, writeThrough = true }
      end
    end
  end

  -- The bracket: one tally shared across nesting levels, a depth, and the two flags that decide
  -- whether the outermost close speaks and what it says.
  local depth, tally, silent, failed = 0, 0, false, false
  -- The profile reset's count, pending between ResetCounted and the host's reset handler.
  local pending

  local S = {}

  --- rawget, NOT a plain index. A Ka0s host's locale table answers EVERY key with the key itself
  --- (the standard mandates the metatable fallback), so a plain index would make this module's own
  --- strings unreachable the moment a host handed its `L` over — the `L` trap LibKa0s-Slash-1.0
  --- and LibKa0s-DebugLog-1.0 document in full. Only a value the host actually put there wins.
  local function text(key)
    local L = d.L
    local v = type(L) == "table" and rawget(L, key) or nil
    if type(v) ~= "string" then v = lib.STRINGS[key] end
    return v
  end

  local function fn(field)
    local f = d[field]
    if type(f) == "function" then return f end
    return nil
  end

  -- A debug line, if the host has a sink and has not switched logging off. `debugEnabled` is asked
  -- first so that nothing at all — not the host's formatter, not a tostring — runs on the path a
  -- color-picker drag reaches every frame while debug is off.
  local function logEnabled()
    local debug = fn("debug")
    if not debug then return nil end
    local enabled = fn("debugEnabled")
    if enabled and not enabled() then return nil end
    return debug
  end

  -- ── the registry ──────────────────────────────────────────────────────────────────────────

  --- Rebuild the path index from `rows`. FIRST-REGISTERED WINS on a duplicate path (the linear
  --- hosts' answer); Validate reports the duplicate, so the disagreement between first-wins and
  --- last-wins hosts becomes unreachable rather than resolved by accident. A row with no string
  --- path — an Options bound row, a header — is not indexed.
  local function reindex()
    for k in pairs(index) do index[k] = nil end
    for _, row in ipairs(rows) do
      if type(row) == "table" then
        local path = row.path
        if type(path) == "string" and path ~= "" and index[path] == nil then index[path] = row end
      end
    end
  end

  --- The descriptor's `rows` table itself (identity). Both descriptors and at least one host depend
  --- on getting the live array rather than a copy of it.
  function S.AllRows() return rows end

  function S.FindRow(path)
    if type(path) ~= "string" then return nil end
    return index[path]
  end

  --- Add `list`'s rows to the schema, in order. `at` nil, not a number, or past the end appends;
  --- `at` >= 1 inserts the rows starting at that position, in their own order (a head splice is
  --- `AddRows(rows, 1)`); `at` below 1 is the head. Re-indexes, because an insert ahead of an
  --- existing row can change which of two duplicates is first. Answers the number of rows added.
  function S.AddRows(list, at)
    if type(list) ~= "table" then return 0 end
    local n = #list
    at = tonumber(at)
    if at then at = floor(at) end
    if not at or at > #rows + 1 then at = #rows + 1 end
    if at < 1 then at = 1 end
    for i = 1, n do tinsert(rows, at + i - 1, list[i]) end
    reindex()
    return n
  end

  --- For a host that mutated AllRows() in place — removed a row, spliced by hand. Without it the
  --- index goes on answering the rows as they were.
  function S.Reindex() reindex() end

  -- ── reads ─────────────────────────────────────────────────────────────────────────────────

  -- Where a STORED path lives right now. Answers root, first, resolvedId on success and nil,
  -- reason when there is nowhere. A root that is not a table is nowhere, whatever else came back:
  -- `function() return NS.db and NS.db.global, 1 end` answers `nil, 1` before the db exists, and
  -- the 1 is not a reason.
  local function resolve(parts, instanceId)
    local resolveRoot = fn("resolveRoot")
    if not resolveRoot then return nil end
    local root, first, rid = resolveRoot(parts, instanceId)
    if type(root) ~= "table" then
      return nil, type(first) == "string" and first or nil
    end
    return root, tonumber(first) or 1, rid
  end

  --- The value at `path`. A row carrying `get` answers through it, handed `instanceId` (minor 2);
  --- a `sessionOnly` row without one answers nil; everything else is read through `resolveRoot`.
  --- A path with NO row is still read — `get` is a debugging tool, and a player inspecting an
  --- interior node is asking a real question. Root absent answers nil.
  function S.Get(path, instanceId)
    if type(path) ~= "string" then return nil end
    local row = index[path]
    if row then
      local get = row.get
      if type(get) == "function" then return get(instanceId) end
      if row.sessionOnly then return nil end
    end
    local parts = splitPath(path)
    local root, first = resolve(parts, instanceId)
    if not root then return nil end
    return lib.Read(root, parts, first)
  end

  -- ── the write seam ────────────────────────────────────────────────────────────────────────

  --- The row a write to `path` goes through: the indexed row, else the path's writeThrough row,
  --- else nil. A path with a row ALWAYS takes the row, so a listed path whose composer did load is
  --- validated, normalized and reacted to like any other. A writeThrough row carries no validate,
  --- normalize, set or onChange, so the pipeline below stores it raw (a copy), logs it and
  --- announces it — and refuses it on a missing root, as any stored row.
  local function writeRow(path)
    if type(path) ~= "string" then return nil end
    return index[path] or throughRows[path]
  end

  --- Where a write to a STORED row's `path` lands. Answers `parts, root, first, rid`, or `parts,
  --- nil, nil, rid, reason` when there is nowhere. `rid` is the id the resolver named, or the
  --- caller's `instanceId` when it named none — a `false` id is still an id.
  local function writeTarget(path, instanceId)
    local parts = splitPath(path)
    local root, first, id = resolve(parts, instanceId)
    if not root then return parts, nil, nil, instanceId, first end
    if id == nil then id = instanceId end
    return parts, root, first, id
  end

  --- The INVALID refusal and the row's `why` when the row's own `validate` rejects `value`; nil
  --- when the row has no validate or it accepts.
  local function invalidReason(row, path, value, rid)
    local validate = row.validate
    if type(validate) ~= "function" then return nil end
    local ok, why = validate(value, rid)
    if ok then return nil end
    return text("INVALID"):format(path), why
  end

  --- The value the row wants stored: `value` itself when the row has no `normalize`, else what
  --- `normalize(value, rid)` answers. `nil` from it is a refusal — INVALID and its `why` — so a
  --- normalize cannot clear a setting to absence; a row that needs that uses its own `set`.
  local function normalizeValue(row, path, value, rid)
    local normalize = row.normalize
    if type(normalize) ~= "function" then return value end
    local out, why = normalize(value, rid)
    if out == nil then return nil, text("INVALID"):format(path), why end
    return out
  end

  --- Everything the seam checks before it stores, shared by Set and SetMany so a batch refuses on
  --- exactly the rules a single write does. Answers `true, value, rid, set, parts, root, first` —
  --- `value` being the one to store, normalized — or `false, err, why, withWhy` with nothing
  --- called but the row's own validate and normalize. `withWhy` keeps minor 1's answer count:
  --- a value refusal answers `false, err, why` (three values, even when `why` is nil) and a
  --- missing root answers `false, err` (two), and a host pinning `select("#", ...)` sees no change.
  local function prepareWrite(row, path, value, instanceId)
    local set = row.set
    if type(set) ~= "function" then set = nil end
    local stored = not set and not row.sessionOnly
    local parts, root, first, reason
    local rid = instanceId
    if stored then parts, root, first, rid, reason = writeTarget(path, instanceId) end

    -- Validate, then normalize, BEFORE the missing-root refusal, so a bad value is named as bad
    -- even when there is also nowhere to put it — the error a player can act on comes first.
    local invalid, why = invalidReason(row, path, value, rid)
    if invalid then return false, invalid, why, true end
    value, invalid, why = normalizeValue(row, path, value, rid)
    if invalid then return false, invalid, why, true end
    if stored and not root then
      return false, reason or text("NO_ROOT"):format(path), nil, false
    end
    return true, value, rid, set, parts, root, first
  end

  --- Hand `value` to the row's own `set` (as given, never a copy), or copy it into a resolved
  --- `root`; with neither — a sessionOnly row without a `set` — nothing is stored.
  local function storeWrite(set, value, parts, root, first)
    if set then
      set(value)
    elseif root then
      -- Copied on the way in, so the caller's table and the store never alias: mutating the
      -- argument afterwards must not reach into a profile, and two profiles must never share one.
      lib.Write(root, parts, deepCopy(value), first)
    end
  end

  --- The per-write `[Set]` line, if logging is on: the host's `format(row, value)` when it answers
  --- non-nil, the value's tostring otherwise. The formatter never runs while logging is off.
  local function logWrite(row, path, value)
    local debug = logEnabled()
    if not debug then return end
    local format = fn("format")
    local shown = format and format(row, value)
    if shown == nil then shown = tostring(value) end
    debug("Set", "%s = %s", path, shown)
  end

  --- The row's own reaction. Errors propagate.
  local function runOnChange(row, value, rid)
    local onChange = row.onChange
    if type(onChange) == "function" then onChange(value, rid) end
  end

  --- The write's tail, in the contract's order: the row's `onChange`, then the host's `announce`.
  --- Errors propagate, so a raising onChange means no announce.
  local function reactToWrite(row, path, value, rid)
    runOnChange(row, value, rid)
    local announce = fn("announce")
    if announce then announce(row, path, value, rid) end
  end

  --- Count one bracketed write into the tally when the row's read-back differs from `before`,
  --- the snapshot taken ahead of the store.
  local function tallyIfMoved(before, path, instanceId)
    if not sameValue(before, S.Get(path, instanceId)) then tally = tally + 1 end
  end

  --- Store a prepared write, then tally it (inside a bracket) or log it (outside one).
  ---
  --- The tally's before-image is read (and snapshotted, so a closure `set` that mutates a stored
  --- table in place is still seen as a change) only inside a bracket: outside one this seam
  --- carries every color-picker drag frame, and the comparison is needed for nothing but N.
  --- An `if`, not `bulk and x or nil`: a stored `false` would read back as nil through the idiom
  --- and every false-valued row in a sweep would count as changed.
  ---
  --- Counted before any host code runs, so a raising onChange cannot drop a write that did land
  --- from N. Read-back rather than before-versus-argument, because a closure row may store
  --- something other than what it was handed (an inverted key, a clear-to-absence). Logged
  --- BEFORE the reaction, so a raising onChange cannot erase the trace of a write that landed;
  --- muted inside a bracket, whose one line stands for the act.
  local function commitWrite(row, path, value, instanceId, set, parts, root, first)
    local bulk = depth > 0
    local before
    if bulk then before = deepCopy(S.Get(path, instanceId)) end
    storeWrite(set, value, parts, root, first)
    if bulk then
      tallyIfMoved(before, path, instanceId)
    else
      logWrite(row, path, value)
    end
  end

  --- The single write seam for every schema-row path (architecture-§5). THE ORDER IS THE CONTRACT:
  --- refuse an unknown path (a listed writeThrough path is not unknown); resolve the root;
  --- validate; normalize; refuse a missing root; store; tally; log; react; announce. Answers
  --- `true`, or `false, err[, why]` with nothing stored and nothing called.
  function S.Set(path, value, instanceId)
    local row = writeRow(path)
    if not row then
      -- architecture-§5 scopes the seam to schema-row paths. A write to a path no row declares is
      -- refused, not stored: silently storing it is how a typo'd key becomes a setting nothing
      -- reads and nothing resets. The one exception is a path the host LISTED in writeThrough.
      return false, text("NOT_FOUND"):format(tostring(path))
    end
    -- On a refusal the next three answers are `err, why, withWhy` (see prepareWrite).
    local ok, stored, rid, set, parts, root, first = prepareWrite(row, path, value, instanceId)
    if not ok then
      if set then return false, stored, rid end
      return false, stored
    end
    commitWrite(row, path, stored, instanceId, set, parts, root, first)
    -- Errors propagate. The value is stored and the line written, so the host's error handler sees
    -- a failure that never claims less than happened.
    reactToWrite(row, path, stored, rid)
    return true
  end

  -- ── the batch ─────────────────────────────────────────────────────────────────────────────

  --- One entry of a batch, checked as Set would check it: a plan to commit, or `nil, err, why`.
  local function prepareEntry(entry, instanceId)
    local path = type(entry) == "table" and entry.path or nil
    local row = writeRow(path)
    if not row then return nil, text("NOT_FOUND"):format(tostring(path)) end
    local ok, value, rid, set, parts, root, first = prepareWrite(row, path, entry.value, instanceId)
    if not ok then return nil, value, rid end
    return { row = row, path = path, value = value, rid = rid,
             set = set, parts = parts, root = root, first = first }
  end

  --- Phase 1: every entry checked before any is stored. Answers the plans, or `nil, err, why, i`.
  local function prepareBatch(entries, instanceId)
    local plans = {}
    for i = 1, #entries do
      local plan, err, why = prepareEntry(entries[i], instanceId)
      if not plan then return nil, err, why, i end
      plans[i] = plan
    end
    return plans
  end

  --- Phase 2: store every plan in order, THEN run every onChange in order. Stores first, so a
  --- reaction reading a sibling row sees the whole batch and a raising onChange cannot leave the
  --- store half-written.
  local function commitBatch(plans, instanceId)
    for i = 1, #plans do
      local p = plans[i]
      commitWrite(p.row, p.path, p.value, instanceId, p.set, p.parts, p.root, p.first)
    end
    for i = 1, #plans do
      local p = plans[i]
      runOnChange(p.row, p.value, p.rid)
    end
  end

  --- The batch's tail: the host's `announceBatch(writes, rid)` once, with `writes` an array of
  --- `{ row, path, value, rid }` and `rid` the first write's resolved id; without it, `announce`
  --- once per write. Nothing for an empty batch.
  local function announceBatch(plans)
    if #plans == 0 then return end
    local batch = fn("announceBatch")
    if batch then
      local writes = {}
      for i, p in ipairs(plans) do
        writes[i] = { row = p.row, path = p.path, value = p.value, rid = p.rid }
      end
      batch(writes, plans[1].rid)
      return
    end
    local announce = fn("announce")
    if not announce then return end
    for _, p in ipairs(plans) do announce(p.row, p.path, p.value, p.rid) end
  end

  --- Write several rows as ONE act, all or nothing. `entries = { { path =, value = }, ... }`,
  --- `opts = { instanceId =, act =, scope = }`. Every entry is resolved, validated and normalized
  --- first; one refusal answers `false, err, why, index` with nothing stored and nothing called.
  --- Then every entry is stored in order — inside one bracket when `opts.act` is given, so one
  --- `[Set] <act> <scope>: N rows` line, else one `[Set]` line per write — every row's onChange
  --- runs, and the host is told once through `announceBatch` (or per write through `announce`).
  --- A raising onChange propagates after every store landed; the bracket still closes.
  function S.SetMany(entries, opts)
    if type(entries) ~= "table" then entries = EMPTY end
    if type(opts) ~= "table" then opts = NO_OPTS end
    local instanceId = opts.instanceId
    local plans, err, why, at = prepareBatch(entries, instanceId)
    if not plans then return false, err, why, at end
    if opts.act ~= nil then
      S.BulkRun(opts.act, opts.scope, function() commitBatch(plans, instanceId) end)
    else
      commitBatch(plans, instanceId)
    end
    announceBatch(plans)
    return true
  end

  -- ── defaults ──────────────────────────────────────────────────────────────────────────────

  --- A deep copy of the row's default, so the caller can never reach into the schema. nil for an
  --- unknown path and for a row with no default.
  function S.Default(path)
    local row = S.FindRow(path)
    if not row then return nil end
    return deepCopy(row.default)
  end

  --- Reset one row through the seam: one `[Set]` line and one onChange, exactly as a player's write.
  --- `default == nil` means NO RESTORE and answers false with nothing written: with no default, a
  --- reset does not reach the row (options-ui-§15's test mode reads this way). A row in
  --- `resetExempt` answers false ONLY WHILE A BRACKET IS OPEN, which is what makes it a sweep veto
  --- (launcher-§3's minimap row) while a named single-row reset still works. `instanceId` (minor
  --- 2) reaches Set, so an instanced host resets the instance it names.
  function S.ApplyDefault(row, instanceId)
    if type(row) ~= "table" or type(row.path) ~= "string" or row.default == nil then return false end
    local exempt = d.resetExempt
    if depth > 0 and type(exempt) == "table" and exempt[row.path] then return false end
    return S.Set(row.path, deepCopy(row.default), instanceId)
  end

  -- ── the bulk bracket (debug-logging-§10) ──────────────────────────────────────────────────

  --- Open a bracket: the Options and Slash descriptors' `bulkBegin`. A depth, not a flag, so a
  --- bracket inside a bracket is still one act; the outermost open starts a fresh tally.
  function S.BulkBegin(_act, _scope)
    if depth == 0 then tally, silent, failed = 0, false, false end
    depth = depth + 1
  end

  --- Close a bracket: `bulkEnd(act, scope, count, err, info)`'s shape. `count` is IGNORED — it is
  --- the libraries' count of rows whose applyDefault returned, which includes rows already at their
  --- default, and N is the rows the act actually changed. The outermost close emits
  --- `[Set] <act> <scope>: N rows`, marked ` (stopped by an error)` if any level carried an error,
  --- and nothing at all if any level reported a profile reset (its own handler's line stands for
  --- the act). Never raises the error itself. An unpaired close is a no-op, never a negative depth.
  function S.BulkEnd(act, scope, _count, err, info)
    if depth == 0 then return end
    depth = depth - 1
    if type(info) == "table" and info.profileReset then silent = true end
    if err ~= nil then failed = true end
    if depth > 0 or silent then return end
    local debug = logEnabled()
    if debug then
      debug("Set", "%s %s: %d rows%s", tostring(act), tostring(scope), tally, failed and STOPPED or "")
    end
  end

  --- Run a host-owned bulk act inside a bracket. `fn(info)` does its writes through Set and sets
  --- `info.profileReset = true` when it reset the profile. The bracket ALWAYS closes, even when
  --- `fn` raises, so the mute cannot stick; the error is then re-raised unchanged — the same value,
  --- a table error by identity.
  function S.BulkRun(act, scope, walk)
    local info = { profileReset = false }
    S.BulkBegin(act, scope)
    local ok, err = pcall(walk, info)
    local mark = nil
    if not ok then mark = err == nil and true or err end
    S.BulkEnd(act, scope, nil, mark, info)
    if not ok then error(err, 0) end
  end

  --- Add `n` to the open bracket's tally: a host whose own write path cannot go through Set (a
  --- deduplicated batch, a count taken elsewhere) still lands in the one line. Outside a bracket,
  --- and for a non-number, nothing.
  function S.BulkAdd(n)
    n = tonumber(n)
    if depth > 0 and n then tally = tally + n end
  end

  function S.InBulk() return depth > 0 end

  -- ── the profile reset's count ─────────────────────────────────────────────────────────────

  --- The indexed, stored rows whose current value differs from their default: the rows a reset
  --- would change. Skips path-less rows, `sessionOnly` rows (a profile reset cannot reach their
  --- storage), a later duplicate of an indexed path, and any row `pred(row)` answers exactly
  --- `false` for. A root that is absent reads nil, so such a row counts iff it has a default.
  function S.CountOffDefault(pred)
    if type(pred) ~= "function" then pred = nil end
    local n = 0
    for _, row in ipairs(rows) do
      if type(row) == "table" then
        local path = row.path
        if type(path) == "string" and index[path] == row and not row.sessionOnly
          and (not pred or pred(row) ~= false)
          and not sameValue(S.Get(path), row.default) then
          n = n + 1
        end
      end
    end
    return n
  end

  --- Run a whole-profile reset with its count pending. `resetFn` is typically
  --- `function() db:ResetProfile() end`; the host's OnProfileReset handler takes the count with
  --- ConsumeResetCount. The count is cleared on BOTH exits, so a reset that never reached the
  --- handler cannot hand its number to a later, unrelated one; an error is re-raised unchanged.
  function S.ResetCounted(resetFn, pred)
    pending = S.CountOffDefault(pred)
    local ok, err = pcall(resetFn)
    pending = nil
    if not ok then error(err, 0) end
  end

  --- The pending reset count, taken once: nil when the reset did not come through ResetCounted.
  --- ALSO marks an open bracket as a profile reset, so a reset fired inside a bulk act emits the
  --- handler's line and not a second bulk line — the handler calls this on every reset, which makes
  --- it the one place that knows.
  function S.ConsumeResetCount()
    if depth > 0 then silent = true end
    local n = pending
    pending = nil
    return n
  end

  -- ── the shape check ───────────────────────────────────────────────────────────────────────

  --- Walk the schema and report every malformed row. PRINTS AND COUNTS, never refuses: a schema
  --- error is a developer's problem, and an addon that would not load over one is a player's.
  ---
  --- `spec = { types = set?, pages = set?, defaultsRoot = function(parts, row) -> root, first }`.
  --- Answers `errors, resolved, missing`: shape errors, stored paths that resolve against the
  --- defaults, and stored paths that do not.
  function S.Validate(spec)
    local types, pages, defaultsRoot = validateOptions(spec)
    local print = fn("print")
    local errors, resolved, missing = 0, 0, 0
    local seen = {}

    for i, row in ipairs(rows) do
      local isTable = type(row) == "table"
      local path = isTable and row.path or nil
      local where = rowLabel(i, path)
      local function report(msg)
        errors = errors + 1
        printSchemaError(print, where, msg)
      end

      if not isTable then
        report("row is not a table")
      else
        local hasPath = type(path) == "string" and path ~= ""
        reportFieldErrors(row, hasPath, types, pages, report)
        if hasPath then
          if seen[path] then
            report(("duplicate `path` (first used by row #%d)"):format(seen[path]))
          else
            seen[path] = i
          end
        end

        -- A missing path is printed but not counted as an error: `missing` is its own count.
        local found = resolvesInDefaults(defaultsRoot, row, path, hasPath)
        if found then
          resolved = resolved + 1
        elseif found == false then
          missing = missing + 1
          printSchemaError(print, where, "`path` does not resolve against the defaults")
        end
      end
    end
    return errors, resolved, missing
  end

  reindex()
  return S
end
