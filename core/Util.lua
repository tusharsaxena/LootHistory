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

-- Clock-only (HH:MM) — used by the Time column now that Date is its own column.
function Util.FormatClock(ts)
  return date("%H:%M", ts or 0)
end

-- Compact date (MM/DD/YY) for the Date column.
-- DD-MMM-YYYY (e.g. 11-Jul-2026) — unambiguous across locales (no US/EU MM/DD confusion).
function Util.FormatDate(ts)
  return date("%d-%b-%Y", ts or 0)
end

-- A date-range key → a `from` epoch timestamp (nil = no lower bound / "all"). "today" is the
-- current calendar day; "7d"/"30d" are rolling windows. Shared by the Browser date filter and
-- the Insights range selector so the two can't drift.
function Util.RangeFrom(range)
  local now = time()
  if range == "today" then
    local t = date("*t", now)
    return now - (t.hour * 3600 + t.min * 60 + t.sec)
  elseif range == "7d" then
    return now - 7 * 86400
  elseif range == "30d" then
    return now - 30 * 86400
  end
  return nil
end

-- Format a copper amount for display. In-game uses gold/silver/copper coin icon glyphs
-- (GetCoinTextureString); headless falls back to "Ng Ns Nc" (only non-zero parts).
-- "" for nil/0. Shared by the Vendor column and any future currency columns.
function Util.FormatMoney(copper)
  copper = copper or 0
  if copper <= 0 then return "" end
  if GetCoinTextureString then
    return GetCoinTextureString(copper)
  end
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "g" end
  if s > 0 then parts[#parts + 1] = s .. "s" end
  if c > 0 then parts[#parts + 1] = c .. "c" end
  return table.concat(parts, " ")
end

-- Derived per-unit worth: the higher of the picked auction price and the vendor price (auction can
-- be below vendor). Pick chooses WHICH auction number via the priority list. nil if neither exists.
function Util.RecordValue(record)
  if record == nil then return nil end
  local a = record.auctionPrice and NS.AuctionPrice:Pick(record.auctionPrice) or nil
  local v = record.vendorPrice
  if a and v then return math.max(a, v) end
  return a or v
end

-- Human-readable byte size: "820 B", "12.4 kB", "3.1 MB". Uses 1024 steps.
function Util.FormatBytes(bytes)
  bytes = bytes or 0
  if bytes < 1024 then
    return string.format("%d B", bytes)
  elseif bytes < 1024 * 1024 then
    return string.format("%.1f kB", bytes / 1024)
  else
    return string.format("%.1f MB", bytes / (1024 * 1024))
  end
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

-- ── Secret-safe chat printer (Ka0s standard events-frames-taint-§8) ──────────────────────────
-- In combat, retail protects combat-sensitive returns (unit absorb/health totals, threat, some
-- aura amounts) as "secret" values. A secret survives tostring() AND the `..` operator (which
-- silently propagates secretness), but RAISES the instant it reaches table.concat. Because every
-- chat line ends in a table.concat, an unguarded secret both spams a Lua error and — inside a
-- repeating ticker — can freeze the feature until /reload. Detection MUST probe the operation that
-- actually rejects a secret (table.concat), NOT `..`: a `..`-based probe reports a secret as safe.
local function probeConcat(v) return table.concat({ v }) end
function NS.IsConcatSafe(v)
  return (pcall(probeConcat, v))
end

-- Concat-safe stringifier used by every line the addon emits. Ordinary values → tostring(v); an
-- un-concatenable (secret) value → the sentinel "<secret>", so the surrounding table.concat can
-- never raise. nil and booleans are handled up front (table.concat rejects a boolean element too,
-- but booleans are never secret, so they must not be masked).
function NS.SafeToString(v)
  if v == nil then return "nil" end
  if type(v) == "boolean" then return tostring(v) end
  if NS.IsConcatSafe(v) then return tostring(v) end
  return "<secret>"
end

-- The single shared chat printer. Prepends the cyan NS.PREFIX tag (slash-commands-§4) and
-- space-joins each SafeToString'd arg, mirroring print(). Every file that emits chat does
-- `local print = NS.Print` so call sites stay `print("message")` — never the global print(), never
-- a hand-written tag, never raw `..`/tostring on an arg. Real name is NS.Util.print; NS.Print is
-- reclaimed from it after the AceConsole embed (core/LootHistory.lua, architecture-§2).
function NS.Print(...)
  local n = select("#", ...)
  local parts = { NS.PREFIX }
  for i = 1, n do parts[i + 1] = NS.SafeToString((select(i, ...))) end
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(table.concat(parts, " "))
  end
end
Util.print = NS.Print
