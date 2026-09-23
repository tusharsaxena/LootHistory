-- LibKa0s-Bus-1.0 -- the stand-down record for an addon's bus receivers, and the strict
-- declare-once message catalog.
--
-- Every addon in this collection talks to itself over AceEvent-3.0's message bus, and every one of
-- them hands each receiver a private target (`NS.NewBusTarget()`), because one shared target
-- silently overwrites a second receiver of the same message. That factory is four lines of
-- `AceEvent:Embed` and stays host code: the standard prints it as host code (architecture-§4), and
-- promoting it would be promotion on frequency alone (library-stack-§7).
--
-- What is NOT four lines is standing those receivers down. A stood-down addon has to unregister
-- every event and message its receivers hold, and a stood-up one has to put back exactly what is
-- wanted NOW -- not a snapshot taken on the way down, because a receiver can drop or gain a
-- registration while the addon is down. Four repos wrote that record by hand and their reach
-- differed: one recorded events and messages, three recorded messages only. None disagreed with
-- the widest on correctness, so this file is that union design, without the two defects the
-- copies carried: a key list that gained a duplicate on every re-register, and CallbackHandler's
-- optional `arg` dropped on replay.
--
-- WHAT A TRACKED TARGET IS. `bus:NewTarget()` embeds AceEvent into a fresh table, then wraps its six
-- register/unregister members so the bus holds a live record of every (kind, name) the target is
-- registered for, with the handler exactly as given. `SendMessage` is left raw: sending is not a
-- registration.
--
-- WHAT THE BUS DELIBERATELY DOES NOT DO. It owns no hold set, no edge and no callbacks. The latch
-- (LibKa0s-Lifecycle-1.0) decides WHEN an addon stands down; the host calls `bus:StandDown()` and
-- `bus:StandUp()` from inside its own latch callbacks, at the position in its own sequence it
-- chooses, because that position is load-bearing and differs per host. The one question the bus
-- asks the latch is `descriptor.isDown()`, so that a bare stand-up of the registrations while the
-- latch still holds the addon down is refused.
--
-- It never prints. It resolves AceEvent-3.0 at CALL time and answers nil / 0 without it, as
-- Options, Media and Launcher resolve their optional libraries; no floor on AceEvent is possible,
-- since the payload may not contain it (library-stack-§6).
--
-- Depends on LibStub and LibKa0s-Core-1.0, and on AceEvent-3.0 only when present.

-- The Core floor, declared even though not one member of Core is called below: a LOAD-PAYLOAD
-- check, not a dependency check (library-stack-§7), exactly as Lifecycle.lua declares it. A host
-- holding a partial vendored copy gets every module of the payload absent rather than a mixed set.
local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Bus-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

-- Which version of each FILE in this major is actually live. See docs/releasing.md.
lib.MODULES = lib.MODULES or {}
lib.MODULES.Bus = MINOR

local type, select, pairs, ipairs, pcall, error, tostring = type, select, pairs, ipairs, pcall, error, tostring
local unpack, tsort, tconcat = unpack, table.sort, table.concat

-- The six wrapped members, by kind: register, unregister one, unregister all. AceEvent keeps the
-- two kinds in separate CallbackHandler registries, so `UnregisterAllEvents` leaves messages alone
-- and the record has to do the same.
local KINDS = {
  event   = { reg = "RegisterEvent",   unreg = "UnregisterEvent",   all = "UnregisterAllEvents" },
  message = { reg = "RegisterMessage", unreg = "UnregisterMessage", all = "UnregisterAllMessages" },
}
local KIND_ORDER = { "event", "message" }

local function keyOf(kind, name) return kind .. "\0" .. name end

local function byOrd(a, b) return a.ord < b.ord end
local function bySeq(a, b) return a.seq < b.seq end

--- Create the record for one addon's tracked receivers. ONE INSTANCE PER ADDON, beside its latch.
---
--- Descriptor fields:
---   name    string    required. The addon folder name. Diagnostic only: published as `bus.name`,
---                     never branched on and never printed.
---   isDown  function  optional. The host's latch predicate, late-bound through a closure because a
---                     host builds its bus long before its latch exists. While it answers truthy,
---                     `StandUp` is refused. Inside the latch's own `standUp` callback the latch has
---                     already recorded the edge, so it answers false there and the replay proceeds.
function lib:New(descriptor)
  local d = type(descriptor) == "table" and descriptor or {}
  if type(d.name) ~= "string" or d.name == "" then
    error(MAJOR .. ":New requires descriptor.name - the addon folder name", 2)
  end
  if d.isDown ~= nil and type(d.isDown) ~= "function" then
    error(MAJOR .. ":New: descriptor.isDown must be a function when given - the latch predicate", 2)
  end
  local isDown = d.isDown

  -- The state of THIS BUS'S REGISTRATIONS, not a second latch: no reason to be down is recorded in
  -- it. It exists for idempotence and for the deferral rule below.
  local down = false

  -- target -> rec, STRONG, and exactly while the record holds at least one entry. Strong because a
  -- stand-down drops CallbackHandler's reference to the target, and a target nothing else holds
  -- must still be here to replay. (In the client AceEvent-3.0's own `embeds` set also holds every
  -- embedded table for the session; the bus does not lean on that internal.) Released the moment
  -- the record empties, so a receiver its owner retires by unregistering everything leaves the bus
  -- with no `Retire` member needed. Outside that window the bus holds no reference to the target.
  local held = {}
  -- Creation order for targets, first-registration order for entries. Dispatch order is not
  -- observable through CallbackHandler, so these exist for a deterministic replay and a
  -- deterministic `rejected` list, and for nothing else.
  local seq, ord = 0, 0

  local B = { name = d.name }

  --- Record (kind, name) on `rec`. A key already recorded is REPLACED IN PLACE and keeps its
  --- position: CallbackHandler's own rule is one callback per (event, target) with the later one
  --- winning, so the record and the live registration never disagree about which handler wins, and
  --- the key list never holds a key twice.
  ---
  --- The handler is kept exactly as given -- a function, a method name, or nil -- and the optional
  --- argument with its COUNT, because CallbackHandler tells "no arg" from "arg is nil" by counting.
  --- The stored table is named `extra`, not `arg`: Lua 5.1 declares a hidden `arg` in every vararg
  --- function.
  local function remember(rec, kind, name, handler, ...)
    local key = keyOf(kind, name)
    local entry = rec.entries[key]
    if entry == nil then
      ord = ord + 1
      entry = { kind = kind, name = name, ord = ord }
      rec.entries[key] = entry
      rec.count = rec.count + 1
      if rec.count == 1 then held[rec.target] = rec end
    end
    entry.handler, entry.n, entry.extra = handler, select("#", ...), { ... }
  end

  local function forget(rec, key)
    if rec.entries[key] == nil then return end
    rec.entries[key] = nil
    rec.count = rec.count - 1
    if rec.count == 0 then held[rec.target] = nil end
  end

  local function forgetKind(rec, kind)
    -- Clearing an existing field during `pairs` is permitted in Lua; adding one is not, and
    -- nothing here adds.
    for key, entry in pairs(rec.entries) do
      if entry.kind == kind then forget(rec, key) end
    end
  end

  local function heldInOrder()
    local list = {}
    for _, rec in pairs(held) do list[#list + 1] = rec end
    tsort(list, bySeq)
    return list
  end

  --- Stamp the three wrappers of one kind over `t`'s raw members. Only a call on `t` itself is
  --- recorded; a raw member reached with some other `self` is passed straight through.
  local function wrapKind(rec, t, kind)
    local names = KINDS[kind]
    local rawReg, rawUnreg, rawAll = t[names.reg], t[names.unreg], t[names.all]
    rec.raw[kind] = { reg = rawReg, unreg = rawUnreg, all = rawAll }

    -- Register. While UP: the raw call FIRST, then the record, so a raw call that raises (the
    -- client's "Attempt to register unknown event") reaches the caller unchanged and is NOT
    -- recorded. While DOWN: the record only, and the registration goes live at StandUp -- which is
    -- what makes "a stood-down addon registers nothing" structural for every tracked receiver
    -- rather than a guard each host has to remember. A non-string name is handed to the raw call
    -- in both states, so CallbackHandler raises its own usage error and nothing is recorded.
    t[names.reg] = function(self, name, handler, ...)
      if self ~= t or type(name) ~= "string" then return rawReg(self, name, handler, ...) end
      if down then
        remember(rec, kind, name, handler, ...)
        return
      end
      rawReg(self, name, handler, ...)
      remember(rec, kind, name, handler, ...)
    end

    -- Unregister one, and unregister all: forget, then raw, in BOTH states. While down the raw
    -- call is a no-op on the registry; it stays unconditional so the two paths cannot drift.
    t[names.unreg] = function(self, name, ...)
      if self == t and type(name) == "string" then forget(rec, keyOf(kind, name)) end
      return rawUnreg(self, name, ...)
    end
    t[names.all] = function(...)
      if (...) == t then forgetKind(rec, kind) end
      return rawAll(...)
    end
  end

  --- A fresh AceEvent-embedded receiver, tracked by this bus. One per receiver, never shared: two
  --- receivers of one message on one target overwrite each other in CallbackHandler.
  ---
  --- Answers nil when AceEvent-3.0 is not in LibStub, resolved NOW rather than at file load, so a
  --- library loaded after this file is still found. Callers already treat nil as "no bus".
  function B:NewTarget()
    local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
    if not AceEvent then return nil end
    local t = {}
    AceEvent:Embed(t)
    seq = seq + 1
    local rec = { target = t, seq = seq, entries = {}, count = 0, raw = {} }
    for _, kind in ipairs(KIND_ORDER) do wrapKind(rec, t, kind) end
    return t
  end

  --- Take every tracked registration down, events AND messages, and KEEP the record. Answers the
  --- number of (kind, name) entries recorded at this moment. A second call answers 0 and touches
  --- nothing.
  ---
  --- Not guarded by `isDown`: taking registrations down is always safe, and a host may reach its
  --- teardown from AceAddon's OnDisable as well as from the latch. State first, then work, for the
  --- reason Lifecycle's edge() gives.
  function B:StandDown()
    if down then return 0 end
    down = true
    local n = 0
    for _, rec in ipairs(heldInOrder()) do
      n = n + rec.count
      rec.raw.event.all(rec.target)
      rec.raw.message.all(rec.target)
    end
    return n
  end

  --- Replay the record AS IT IS NOW. Answers `replayed, rejected`: the number of entries made live,
  --- and a FRESH SORTED array of `"event:NAME"` / `"message:NAME"` for the entries that raised.
  ---
  --- Refused -- `0, {}`, and the bus stays down -- while `descriptor.isDown()` answers truthy. That
  --- is the latch's "no bare stand-up" rule carried into the one member here that could otherwise
  --- be one. Answers `0, {}` when already up.
  ---
  --- Each entry replays through pcall, so one entry that raises cannot leave the rest unregistered
  --- (events-frames-taint-§1's "a block MUST survive one bad name", applied to the replay).
  --- A raising entry is dropped from the record, and whatever the raw call left behind in
  --- CallbackHandler is unregistered. NOTHING IS RAISED OUT OF HERE: this runs inside the host's
  --- `standUp` callback, and a raise would abort the rest of the host's rebuild. The host logs
  --- `rejected` through its debug seam. Only an entry recorded while down was never validated by a
  --- raw call, so in practice `rejected` is empty.
  function B:StandUp()
    if not down then return 0, {} end
    if isDown and isDown() then return 0, {} end
    down = false
    local replayed, rejected = 0, {}
    for _, rec in ipairs(heldInOrder()) do
      local entries = {}
      for _, entry in pairs(rec.entries) do entries[#entries + 1] = entry end
      tsort(entries, byOrd)
      for _, e in ipairs(entries) do
        local raw = rec.raw[e.kind]
        if pcall(raw.reg, rec.target, e.name, e.handler, unpack(e.extra, 1, e.n)) then
          replayed = replayed + 1
        else
          forget(rec, keyOf(e.kind, e.name))
          pcall(raw.unreg, rec.target, e.name)
          rejected[#rejected + 1] = e.kind .. ":" .. e.name
        end
      end
    end
    tsort(rejected)
    return replayed, rejected
  end

  return B
end

-- ── the catalog ─────────────────────────────────────────────────────────────────────────────
--
-- architecture-§4 requires every bus message to be declared ONCE, as a constant, and the
-- naming cheatsheet requires the wire name `Ka0s_<Addon>_<Event>` with `<Event>` in PascalCase.
-- Both are review rules until something reads the table. `Catalog` reads it: it validates the
-- declaration at load, and hands back a STRICT copy, so a mistyped key raises at the call site.
--
-- That closes a hole the rule's own rationale overclaims. A mistyped constant fails at once for a
-- SUBSCRIBER (CallbackHandler raises on a non-string name), but a PUBLISHER's `SendMessage(nil)` is
-- silent: CallbackHandler's Fire returns quietly on an event nobody registered. With the strict
-- read, `NS.MSG.TYPO` raises for both.

local KEY_PATTERN   = "^%u[%u%d_]*$"   -- SCREAMING_SNAKE
local EVENT_PATTERN = "^%u[%a%d]*$"    -- PascalCase letters and digits, and at least one lowercase

local function catalogError(addonName, text)
  error(("%s.Catalog(%s): %s"):format(MAJOR, tostring(addonName), text), 3)
end

--- Validate a host's message table and answer a fresh, strict copy of it. DOT-CALLED:
--- `Bus.Catalog(addonName, messages)`, with the host's FULL wire names as values, so the same table
--- is the declaration on the live path and on the degraded one and each `Ka0s_` literal still
--- appears exactly once in the repo.
---
--- Raises at load, naming the offending key, when: `addonName` is not a non-empty string;
--- `messages` is not a non-empty table; a key is not SCREAMING_SNAKE; a value does not start with
--- `Ka0s_<addonName>_`; the part after that prefix is not PascalCase; or two keys declare one wire
--- name. Keys are checked in sorted order, so which refusal a table with several faults raises is
--- deterministic.
---
--- The copy's metatable raises on reading an undeclared key and on adding a new one. `pairs` still
--- enumerates exactly the declared keys, and the host's input table is not mutated.
function lib.Catalog(addonName, messages)
  if addonName == lib then
    error(MAJOR .. ".Catalog is dot-called: Bus.Catalog(addonName, messages)", 2)
  end
  if type(addonName) ~= "string" or addonName == "" then
    error(MAJOR .. ".Catalog requires addonName - the addon folder name, a non-empty string", 2)
  end
  if type(messages) ~= "table" or next(messages) == nil then
    catalogError(addonName, "messages must be a non-empty table of KEY = wire name")
  end

  local keys = {}
  for key in pairs(messages) do
    if type(key) ~= "string" then
      catalogError(addonName, "key " .. tostring(key) .. " is not a string")
    end
    keys[#keys + 1] = key
  end
  tsort(keys)

  local prefix = "Ka0s_" .. addonName .. "_"
  local out, owner = {}, {}
  for _, key in ipairs(keys) do
    local value = messages[key]
    if not key:find(KEY_PATTERN) then
      catalogError(addonName, "key " .. key .. " is not SCREAMING_SNAKE")
    end
    if type(value) ~= "string" or value:sub(1, #prefix) ~= prefix then
      catalogError(addonName, "key " .. key .. " = " .. tostring(value)
        .. " does not start with " .. prefix)
    end
    local event = value:sub(#prefix + 1)
    if not event:find(EVENT_PATTERN) or not event:find("%l") then
      catalogError(addonName, "key " .. key .. " = " .. value
        .. ": the part after the prefix is not PascalCase")
    end
    if owner[value] then
      catalogError(addonName, "keys " .. tconcat({ owner[value], key }, " and ")
        .. " declare one wire name, " .. value)
    end
    owner[value] = key
    out[key] = value
  end

  return setmetatable(out, {
    __index = function(_, key)
      error(("%s: no bus message named %s"):format(addonName, tostring(key)), 2)
    end,
    __newindex = function(_, key)
      error(("%s: bus message %s is not declared in the catalog"):format(addonName, tostring(key)), 2)
    end,
  })
end
