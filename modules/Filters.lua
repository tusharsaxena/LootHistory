local addonName, NS = ...   -- luacheck: ignore addonName
NS.Filters = NS.Filters or {}
local F = NS.Filters

-- Item-id blacklist / whitelist (issue #14).
--
--   * Blacklist — ids that must NOT be recorded even if they pass the collection gates, and whose
--     already-stored rows are hidden from every view. Nothing is deleted: Database:VisibleHistory
--     filters blacklisted ids out at the single read seam, so removing the id restores the rows.
--   * Whitelist — ids that must ALWAYS be recorded, bypassing the quality / source / quest gates.
--
-- The two lists are stored account-wide in NS.db.global.{blacklist,whitelist} (NOT settings, NOT
-- Schema rows). Like `window`/`savedView` they are an architecture-§5 carve-out, mutated directly
-- here rather than through Schema:Set — a dynamic id-set has no Schema widget to drive. An id can
-- be on at most ONE list (adding to one drops it from the other), so the collector's whitelist/
-- blacklist checks can never contradict.
--
-- Every mutation writes a FRESH table back to NS.db.global (copy-on-write) so it never mutates an
-- AceDB shared-default table in place, then propagates the change WITHOUT adding a second bus
-- sender (message-bus's "one sender per message" invariant): it re-caches the Collector's list
-- upvalues by a direct call, and broadcasts HistoryChanged through Database's own emitter so the
-- browser + Insights re-query and hidden rows appear/disappear.

local function currentSet(key)
  return (NS.db and NS.db.global and NS.db.global[key]) or {}
end

-- Shallow copy of a set, so the write never aliases the stored (or AceDB default) table.
local function setCopy(t)
  local c = {}
  if type(t) == "table" then for k, v in pairs(t) do c[k] = v end end
  return c
end

function F:Blacklist() return currentSet("blacklist") end
function F:Whitelist() return currentSet("whitelist") end

function F:IsBlacklisted(id)
  id = tonumber(id)
  return id ~= nil and currentSet("blacklist")[id] == true
end
function F:IsWhitelisted(id)
  id = tonumber(id)
  return id ~= nil and currentSet("whitelist")[id] == true
end

-- Propagate a list change. Re-cache the Collector's list upvalues by a direct cross-module call
-- (not a bus message — the lists aren't schema settings, and the Collector is the only capture-side
-- consumer), then broadcast HistoryChanged through Database's sole emitter so the browser + Insights
-- re-query and hidden rows update. No second sender is introduced for either message.
function F:_notify(reason)   -- luacheck: ignore reason
  if NS.Collector and NS.Collector.RefreshUpvalues then NS.Collector:RefreshUpvalues() end
  if NS.Database and NS.Database.FireHistoryChanged then NS.Database:FireHistoryChanged() end
  if NS.State and NS.State.debug and NS.Debug then
    NS.Debug("Filters", "blacklist=%d whitelist=%d",
      self:Count(self:Blacklist()), self:Count(self:Whitelist()))
  end
end

-- Number of ids in a set (also used by the [Filters] trace).
function F:Count(set)
  local n = 0
  for _ in pairs(set or {}) do n = n + 1 end
  return n
end

-- Move `id` onto `listKey`, dropping it from the sibling list. Returns true when the store
-- actually changed. No-op (returns false) for a non-numeric id or one already on the target list.
function F:_move(listKey, id)
  id = tonumber(id)
  if not id then return false end
  local siblingKey = (listKey == "blacklist") and "whitelist" or "blacklist"
  local target = currentSet(listKey)
  local sibling = currentSet(siblingKey)
  if target[id] and not sibling[id] then return false end
  local t = setCopy(target); t[id] = true; NS.db.global[listKey] = t
  if sibling[id] then
    local s = setCopy(sibling); s[id] = nil; NS.db.global[siblingKey] = s
  end
  self:_notify(listKey)
  return true
end

-- Remove `id` from `listKey`. Returns true when it was present.
function F:_remove(listKey, id)
  id = tonumber(id)
  if not id then return false end
  local target = currentSet(listKey)
  if not target[id] then return false end
  local t = setCopy(target); t[id] = nil; NS.db.global[listKey] = t
  self:_notify(listKey)
  return true
end

function F:AddBlacklist(id)    return self:_move("blacklist", id) end
function F:AddWhitelist(id)    return self:_move("whitelist", id) end
function F:RemoveBlacklist(id) return self:_remove("blacklist", id) end
function F:RemoveWhitelist(id) return self:_remove("whitelist", id) end

-- Sorted array of the ids on a list, for a stable management-UI order.
function F:SortedIDs(set)
  local ids = {}
  for id in pairs(set or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

-- Extract an item id from free-form input: a bare number, or an item link / itemString the user
-- shift-clicked into the field. Returns a number, or nil when nothing parses.
function F:ParseItemID(input)
  if type(input) == "number" then return input end
  if type(input) ~= "string" then return nil end
  input = input:match("^%s*(.-)%s*$")
  local fromLink = input:match("|Hitem:(%d+)") or input:match("^item:(%d+)")
  if fromLink then return tonumber(fromLink) end
  return tonumber(input)
end
