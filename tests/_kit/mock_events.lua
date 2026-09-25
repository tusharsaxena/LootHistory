-- testkit/mock_events.lua — the client's event surfaces beyond AceEvent (revision 26).
--
-- Three things the kit did not model, each of which let a consumer suite pass over a case the
-- client fails:
--
--   * `EventRegistry` — Blizzard's global CallbackRegistry. Its callbacks never reached
--     `M.__registrations()`, so a stand-down suite could not see an `EditMode.Exit` callback that
--     survived the addon being switched off (review finding `PartyFrameEnhanced-R-10`). Every live
--     callback is now a survey row `{ kind = "callback", event = <name>, owner = <owner> }`. The
--     row has NO `target`: a callback's owner is whatever the addon passed, often not a frame and
--     not an AceEvent target, and a suite that renders rows reads `r.target or r.owner`.
--   * a RAW `frame:RegisterEvent` / `frame:RegisterUnitEvent` on an unknown name. The client raises
--     `Attempt to register unknown event "<NAME>"`; through revision 25 only the AceEvent path
--     (`mock_base.lua`'s `makeAceEvent`) honored `M.__badEvents`, and a bare frame recorded
--     anything. The raise is at level 2, so its position names the caller as the client's names the
--     addon, and it happens BEFORE anything is recorded, because the client registers nothing.
--   * `C_EventUtils.IsEventValid(name)` — the client's own answer to "would that raise?". False for
--     a name in `M.__badEvents`, true otherwise. A suite models an older client, which has no
--     `C_EventUtils`, by setting `M.C_EventUtils = nil`; nothing in the kit reads it.
--
-- `M.__badEvents` is read at CALL time on every path, so a test that swaps the table is heard.
--
-- Loaded by `mock_base.lua` from its own folder, like `mock_record.lua`, and for the same reason it
-- is a file of its own: `mock_base.lua` sits near `layout-§1`'s 1500-line cap. It answers two
-- functions: `decorateFrame(M, f)`, which every tracked frame passes through as it is made, and
-- `install(M)`, which runs after the recorder so it can extend the survey the recorder published.

local Events = {}

local function isBad(M, event)
  local bad = M.__badEvents
  return type(bad) == "table" and bad[event] and true or false
end

-- The client's message, byte for byte the one `makeAceEvent`'s onUsed raises.
local function unknownEvent(event)
  return "Attempt to register unknown event \"" .. tostring(event) .. "\""
end

--- Wrap one frame's RegisterEvent and RegisterUnitEvent so an unknown name raises before anything is
--- recorded. The frame stub's own recording functions run unchanged for every other name.
function Events.decorateFrame(M, f)
  local register, registerUnit = f.RegisterEvent, f.RegisterUnitEvent
  function f.RegisterEvent(self, event, ...)
    if isBad(M, event) then error(unknownEvent(event), 2) end
    return register(self, event, ...)
  end
  function f.RegisterUnitEvent(self, event, ...)
    if isBad(M, event) then error(unknownEvent(event), 2) end
    return registerUnit(self, event, ...)
  end
  return f
end

-- ── EventRegistry ──────────────────────────────────────────────────────────────────────────
--
-- Blizzard_SharedXMLBase/CallbackRegistry.lua, which GlobalCallbackRegistry.lua mixes into
-- EventRegistry. One callback per (event, owner): RegisterCallback unregisters the owner's previous
-- one first, so a second registration REPLACES rather than adds. A function callback is invoked as
-- `func(owner, ...)`. An owner left nil is given a generated numeric id, which is returned; a
-- numeric owner passed in is refused, because numbers are that id space. The closure form (extra
-- arguments after `owner`) is not modeled and RAISES, so a first use of it fails loudly here rather
-- than silently dropping the bound arguments (fidelity rule 1). The client runs each callback
-- through securecallfunction, which reports an error rather than raising it; this fake lets it
-- propagate, so the suite sees it.
local function makeEventRegistry()
  local byEvent, seq, nextOwnerId = {}, 0, 0   -- byEvent[event] = { { owner, func, seq }, ... }

  local function remove(event, owner)
    local list = byEvent[event]
    if not list then return end
    for i = #list, 1, -1 do
      if list[i].owner == owner then table.remove(list, i) end
    end
    if #list == 0 then byEvent[event] = nil end
  end

  local registry = {}
  function registry.RegisterCallback(_, event, func, owner, ...)
    if type(event) ~= "string" then error("RegisterCallback 'event' requires string type.", 2) end
    if type(func) ~= "function" then error("RegisterCallback 'func' requires function type.", 2) end
    if select("#", ...) > 0 then
      error("testkit: the closure form of RegisterCallback is not modeled", 2)
    end
    if owner == nil then
      nextOwnerId = nextOwnerId + 1
      owner = nextOwnerId
    elseif type(owner) == "number" then
      error("RegisterCallback 'owner' as number is reserved internally.", 2)
    end
    remove(event, owner)
    seq = seq + 1
    byEvent[event] = byEvent[event] or {}
    table.insert(byEvent[event], { owner = owner, func = func, seq = seq })
    return owner
  end

  function registry.UnregisterCallback(_, event, owner)
    if owner == nil then error("UnregisterCallback 'owner' is required.", 2) end
    remove(event, owner)
  end

  -- A snapshot first, so a callback that unregisters itself or another owner mid-dispatch does not
  -- skip a neighbor, which the client's own dispatch also guards against.
  function registry.TriggerEvent(_, event, ...)
    local snapshot = {}
    for i, entry in ipairs(byEvent[event] or {}) do snapshot[i] = entry end
    for _, entry in ipairs(snapshot) do entry.func(entry.owner, ...) end
  end

  --- The live callbacks as survey rows, ordered by event name, then registration order.
  local function rows()
    local events = {}
    for event in pairs(byEvent) do events[#events + 1] = event end
    table.sort(events)
    local out = {}
    for _, event in ipairs(events) do
      for _, entry in ipairs(byEvent[event]) do
        out[#out + 1] = { kind = "callback", event = event, owner = entry.owner }
      end
    end
    return out
  end

  return registry, rows
end

--- Publish `EventRegistry` and `C_EventUtils`, and extend `M.__registrations()` with the callback
--- rows. Runs after `mock_record.lua`'s installer, whose survey it wraps: the other kinds keep their
--- order, and the callback rows follow them.
function Events.install(M)
  local registry, rows = makeEventRegistry()
  M.EventRegistry = registry

  M.C_EventUtils = {
    IsEventValid = function(name) return not isBad(M, name) end,
  }

  local survey = M.__registrations
  M.__registrations = function()
    local out = survey()
    for _, row in ipairs(rows()) do out[#out + 1] = row end
    return out
  end
  return M
end

return Events
