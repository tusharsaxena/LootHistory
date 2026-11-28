local _, NS = ...
NS.ToastSample = NS.ToastSample or {}
local TS = NS.ToastSample
local C = NS.Constants

-- The sample toasts (#38, toast spec docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md §8.6,
-- §8.7): one fixed payload per kind, shown through the Feed's Preview while a feed is unlocked and
-- empty (preview-mode, the same present and paint path). A sample never goes through GAIN, so no
-- receiver (the farm tally, #39) ever counts one. Reached from NS.Toasts at call time only.
--
-- The unlocked preview and test mode show these payloads as they are; the per-feed Test act pushes a
-- copy of each (ToastModel.NewPayload), so a pushed sample is never a shared table.

local L = NS.L

-- The sample of each kind, in C.TOAST_KIND_KEYS' settings order. Read-only once built: the Feed stores
-- a preview payload untouched, and Preview frees its rows (never the payloads) on the next call.
local ORDER = { "item", "money", "currency", "reputation", "appearance", "xp", "skill" }

local function sampleFor(kind)
  if kind == C.GainKind.ITEM then
    return { kind = kind, dir = "IN", id = 6948, qty = 3, name = L["Sample item"], quality = 3 }
  elseif kind == C.GainKind.GOLD then
    return { kind = kind, dir = "IN", qty = 123456 }
  elseif kind == C.GainKind.CURRENCY then
    return { kind = kind, dir = "IN", id = 1, qty = 25, name = L["Sample currency"], quality = 1 }
  elseif kind == C.GainKind.REPUTATION then
    return { kind = kind, dir = "IN", id = 1, qty = 250, name = L["Sample faction"] }
  elseif kind == C.GainKind.APPEARANCE then
    return { kind = kind, dir = "IN", id = 1, qty = 1, name = L["Sample appearance"], quality = 4 }
  elseif kind == C.GainKind.XP then
    return { kind = kind, dir = "IN", qty = 1500 }
  end
  return { kind = kind, dir = "IN", id = 1, qty = 1, name = L["Sample profession"] }
end

local built = {}       -- GainKind -> its { key, payload } pair, made once
local lists = {}       -- fid -> the reused list handed to Preview

local function pair(kind)
  local e = built[kind]
  if not e then
    local p = sampleFor(kind)
    e = { NS.ToastModel.Key(p), p }
    built[kind] = e
  end
  return e
end

--- The preview list for feed `fid`: one sample per kind the feed shows, as the Feed's
--- `{ { key, payload }, ... }`. The same table every call, refilled.
function TS.ForFeed(fid)
  local list = lists[fid]
  if not list then list = {}; lists[fid] = list end
  for i = #list, 1, -1 do list[i] = nil end
  local cfg = NS.ToastModel.Config(fid)
  for _, leaf in ipairs(ORDER) do
    local kind = C.TOAST_KIND_KEYS[leaf]
    if cfg.kinds[kind] then list[#list + 1] = pair(kind) end
  end
  return list
end
