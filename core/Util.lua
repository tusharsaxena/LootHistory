local addonName, NS = ...
NS.Util = NS.Util or {}
local Util = NS.Util

-- "Name-Realm" of the current player (realm normalized, spaces stripped).
function Util.PlayerKey()
  local name = UnitName("player") or "Unknown"
  local realm = (GetNormalizedRealmName and GetNormalizedRealmName())
    or (GetRealmName and GetRealmName()) or "Unknown"
  realm = tostring(realm):gsub("%s+", "")
  return name .. "-" .. realm
end

-- Split a dotted settings path ("settings.qualityThreshold") into components.
function Util.SplitPath(path)
  local parts = {}
  for p in tostring(path):gmatch("[^.]+") do
    parts[#parts + 1] = p
  end
  return parts
end

-- Format an epoch timestamp for table display: HH:MM if today, else MM/DD HH:MM.
function Util.FormatTime(ts, nowTs)
  ts = ts or 0
  nowTs = nowTs or time()
  local today = date("%Y%m%d", nowTs)
  local sameDay = (date("%Y%m%d", ts) == today)
  if sameDay then
    return date("%H:%M", ts)
  end
  return date("%m/%d %H:%M", ts)
end

-- Shallow count of an array-or-map table.
function Util.TableCount(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end
