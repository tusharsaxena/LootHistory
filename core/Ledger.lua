local _, NS = ...
NS.Ledger = NS.Ledger or {}
local Ledger = NS.Ledger

-- Pure ledger primitives: no WoW API, no SavedVariables. Everything the Reconciler decides is built
-- from these so it can be pinned headless (timeline-ledger spec §5.1).

local KIND_PREFIX = { ITEM = "i:", CURRENCY = "c:" }
local PREFIX_KIND = { i = "ITEM", c = "CURRENCY" }

function Ledger.ThingKey(kind, id)
  if kind == "GOLD" then return "g" end
  return KIND_PREFIX[kind] .. tostring(id)
end

function Ledger.ParseThingKey(key)
  if key == "g" then return "GOLD", nil end
  local p, id = tostring(key):match("^([ic]):(%d+)$")
  if not p then return nil end
  return PREFIX_KIND[p], tonumber(id)
end

Ledger.DirSign = { IN = 1, OUT = -1, MOVE = 0 }

local function byKey(a, b) return tostring(a.key) < tostring(b.key) end

-- Signed per-key change from `old` to `new` ({[key]=count} maps; nil reads as empty). Sorted by
-- tostring(key) so callers and tests can index the result; a key whose count did not move is omitted.
-- NB the order is lexical ("10" < "2"): callers need a STABLE order, not a numeric one.
function Ledger.Diff(old, new)
  old, new = old or {}, new or {}
  local out = {}
  for k, n in pairs(new) do
    local d = n - (old[k] or 0)
    if d ~= 0 then out[#out + 1] = { key = k, delta = d } end
  end
  for k, o in pairs(old) do
    if new[k] == nil and o ~= 0 then out[#out + 1] = { key = k, delta = -o } end
  end
  table.sort(out, byKey)
  return out
end
