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

-- Clock-only (HH:MM) — used by the Time column now that Date is its own column.
function Util.FormatClock(ts)
  return date("%H:%M", ts or 0)
end

-- Compact date (MM/DD/YY) for the Date column.
function Util.FormatDate(ts)
  return date("%m/%d/%y", ts or 0)
end

-- Format a copper amount as "Ng Ns Nc" (only non-zero parts). "" for nil/0.
function Util.FormatMoney(copper)
  copper = copper or 0
  if copper <= 0 then return "" end
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "g" end
  if s > 0 then parts[#parts + 1] = s .. "s" end
  if c > 0 then parts[#parts + 1] = c .. "c" end
  return table.concat(parts, " ")
end

-- Shallow count of an array-or-map table.
function Util.TableCount(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- Convert a WoW loot global-string (e.g. "You receive loot: %sx%d.") into an anchored
-- Lua pattern: literal text is escaped, %s → (.+) (item link), %d → (%d+) (quantity).
local function toLootPattern(fmt)
  local p = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1") -- escape magic chars (incl. %)
  p = p:gsub("%%%%s", "(.+)")   -- escaped %s → link capture
  p = p:gsub("%%%%d", "(%%d+)") -- escaped %d → quantity capture
  return "^" .. p .. "$"
end

-- Self-loot patterns, compiled once from the localized global strings. Quantity-bearing
-- variants come first: their (.+) is greedy, so a single-loot pattern would otherwise
-- swallow the trailing "xN" of a multiple-loot line.
local lootPatterns
function Util.BuildLootPatterns()
  local specs = {
    { g = LOOT_ITEM_SELF_MULTIPLE,        hasQty = true },
    { g = LOOT_ITEM_PUSHED_SELF_MULTIPLE, hasQty = true },
    { g = LOOT_ITEM_SELF,                 hasQty = false },
    { g = LOOT_ITEM_PUSHED_SELF,          hasQty = false },
  }
  local out = {}
  for _, s in ipairs(specs) do
    if s.g then
      out[#out + 1] = { pattern = toLootPattern(s.g), hasQty = s.hasQty }
    end
  end
  lootPatterns = out
  return out
end

-- Parse a CHAT_MSG_LOOT line. Returns itemLink, quantity for the player's own loot; nil otherwise.
function Util.ParseSelfLoot(msg)
  if not msg then return nil end
  local pats = lootPatterns or Util.BuildLootPatterns()
  for _, p in ipairs(pats) do
    if p.hasQty then
      local link, qty = msg:match(p.pattern)
      if link then return link, tonumber(qty) or 1 end
    else
      local link = msg:match(p.pattern)
      if link then return link, 1 end
    end
  end
  return nil
end
