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
function Util.FormatMoney(copper, coinHeight)
  copper = copper or 0
  if copper <= 0 then return "" end
  if GetCoinTextureString then
    -- coinHeight (optional) sizes the gold/silver/copper icon glyphs; nil = client default.
    return GetCoinTextureString(copper, coinHeight)
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
-- swallow the trailing "xN" of a multiple-loot line. Some variants carry a `source` tag: their
-- loot line is itself the authoritative, locale-independent proof of the source — a bonus roll
-- (LOOT_ITEM_BONUS_ROLL_SELF), a crafted item (LOOT_ITEM_CREATED_SELF, "You create"), or a token/
-- vendor refund (LOOT_ITEM_REFUND, "You are refunded") — so the collector attributes them directly
-- to that source rather than reading the peripheral loot context (see docs/data-flow.md).
local lootPatterns
function Util.BuildLootPatterns()
  local specs = {
    { g = LOOT_ITEM_SELF_MULTIPLE,             hasQty = true },
    { g = LOOT_ITEM_PUSHED_SELF_MULTIPLE,      hasQty = true },
    { g = LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE,  hasQty = true,  source = "BONUS_ROLL" },
    { g = LOOT_ITEM_CREATED_SELF_MULTIPLE,     hasQty = true,  source = "CRAFT" },
    { g = LOOT_ITEM_REFUND_MULTIPLE,           hasQty = true,  source = "REFUND" },
    { g = LOOT_ITEM_SELF,                      hasQty = false },
    { g = LOOT_ITEM_PUSHED_SELF,               hasQty = false },
    { g = LOOT_ITEM_BONUS_ROLL_SELF,           hasQty = false, source = "BONUS_ROLL" },
    { g = LOOT_ITEM_CREATED_SELF,              hasQty = false, source = "CRAFT" },
    { g = LOOT_ITEM_REFUND,                    hasQty = false, source = "REFUND" },
  }
  local out = {}
  for _, s in ipairs(specs) do
    if s.g then
      out[#out + 1] = { pattern = toLootPattern(s.g), hasQty = s.hasQty, source = s.source }
    end
  end
  lootPatterns = out
  return out
end

-- Parse a CHAT_MSG_LOOT line. Returns itemLink, quantity, source for the player's own loot;
-- nil otherwise. `source` is a self-identifying SourceType string ("BONUS_ROLL"/"CRAFT"/"REFUND")
-- for the tagged variants, else nil (the collector then reads the peripheral context).
function Util.ParseSelfLoot(msg)
  if not msg then return nil end
  local pats = lootPatterns or Util.BuildLootPatterns()
  for _, p in ipairs(pats) do
    if p.hasQty then
      local link, qty = msg:match(p.pattern)
      if link then return link, tonumber(qty) or 1, p.source end
    else
      local link = msg:match(p.pattern)
      if link then return link, 1, p.source end
    end
  end
  return nil
end

-- The roll-won line ("You won: <item>", LOOT_ROLL_YOU_WON) announces that YOU won a group need/
-- greed/transmog roll. It is NOT itself a receipt — no record is written on it; the item arrives a
-- moment later on a normal "You receive loot:" line. The collector uses this to stamp ROLL context
-- so that imminent receive line attributes to the roll rather than inheriting a stale kill/container
-- stamp. Compiled once, like the self-loot patterns (false = the global string is absent).
local rollWonPattern
function Util.RollWonPattern()
  rollWonPattern = LOOT_ROLL_YOU_WON and toLootPattern(LOOT_ROLL_YOU_WON) or false
  return rollWonPattern
end

-- Returns the item link if `msg` is the player's own roll-won line, else nil.
function Util.ParseRollWon(msg)
  if not msg then return nil end
  local pat = rollWonPattern
  if pat == nil then pat = Util.RollWonPattern() end
  if not pat then return nil end
  return msg:match(pat)
end

-- Self-currency patterns, compiled once from the CHAT_MSG_CURRENCY global strings. Quantity-bearing
-- variants (incl. the bonus/overflow parenthetical forms) come first so the greedy single-pattern
-- (.+) can't swallow a trailing "xN (...)". The overflow global embeds a second %s (the currency
-- name); toLootPattern turns it into a third capture that ParseSelfCurrency simply ignores.
-- A currency-vendor refund returns the currency on THIS channel (not CHAT_MSG_LOOT) as a
-- "You are refunded" line (LOOT_ITEM_REFUND*); like the item refund/craft/bonus-roll lines it is
-- self-identifying, so its `source` tag lets the collector attribute REFUND directly (see Collector).
local currencyPatterns
function Util.BuildCurrencyPatterns()
  local specs = {
    { g = CURRENCY_GAINED_MULTIPLE_OVERFLOW, hasQty = true },
    { g = CURRENCY_GAINED_MULTIPLE_BONUS,    hasQty = true },
    { g = CURRENCY_GAINED_MULTIPLE,          hasQty = true },
    { g = LOOT_ITEM_REFUND_MULTIPLE,         hasQty = true,  source = "REFUND" },
    { g = CURRENCY_GAINED,                   hasQty = false },
    { g = LOOT_ITEM_REFUND,                  hasQty = false, source = "REFUND" },
  }
  local out = {}
  for _, s in ipairs(specs) do
    if s.g then out[#out + 1] = { pattern = toLootPattern(s.g), hasQty = s.hasQty, source = s.source } end
  end
  currencyPatterns = out
  return out
end

-- Parse a CHAT_MSG_CURRENCY line. Returns currencyLink, quantity, source for the player's own
-- currency gain; nil otherwise (another player's line, or a non-currency message). `source` is
-- "REFUND" for a self-identifying refund line, else nil (the collector then reads the context).
function Util.ParseSelfCurrency(msg)
  if not msg then return nil end
  local pats = currencyPatterns or Util.BuildCurrencyPatterns()
  for _, p in ipairs(pats) do
    if p.hasQty then
      local link, qty = msg:match(p.pattern)
      if link then return link, tonumber(qty) or 1, p.source end
    else
      local link = msg:match(p.pattern)
      if link then return link, 1, p.source end
    end
  end
  return nil
end

-- The secret-safe stringifier (NS.IsConcatSafe / NS.SafeToString) and the shared cyan-[LH] chat
-- printer (NS.Print / NS.Util.print) used to live here. They are now LibKa0s-Core-1.0's, wired in
-- core/CoreSetup.lua — which loads immediately after this file and before every consumer that
-- captures the printer at file scope. Behavior is unchanged, including the "<secret>" sentinel.

-- Collapse a burst of calls into one deferred run.
--
-- WHY THIS EXISTS. `Database:Add` fires `RecordAdded` on the bus for every looted item, and with
-- the browser open that reached a full BrowserTable rebuild, seven filter-dropdown builders each
-- scanning the whole dataset, a StorageStats pass with a per-record byte estimate, and — on the
-- Insights tab — a full Analytics refresh. Roughly NINE O(history) passes per loot line. Loot
-- fires mid-pull, and the browser is a plain non-secure frame that can be open through a boss
-- kill, so the worst case is an ordinary one: a big history, a multi-drop kill, and the window up.
--
-- The window is short on purpose. This is not a throttle that drops work; it is a coalescer that
-- performs the work ONCE for a burst, so the surface is at most one delay behind the data and
-- never wrong for longer than that.
--
-- @param fn function  the work to run at most once per window
-- @param delay number  seconds to wait before running
-- @return function  the trigger; call it as often as you like
function Util.Coalesce(fn, delay)
  local pending = false
  return function()
    if pending then return end
    -- No C_Timer — headless, or a client old enough to lack it. Run straight through: correct and
    -- slow beats a surface that silently never repaints.
    if not (C_Timer and C_Timer.After) then return fn() end
    pending = true
    C_Timer.After(delay, function()
      -- Cleared BEFORE the body, not after. A raise inside `fn` would otherwise leave the flag
      -- set for the rest of the session and this surface would never repaint again — trading a
      -- slow window for a dead one, which is the worse bug and the harder one to notice.
      pending = false
      fn()
    end)
  end
end

NS.Coalesce = Util.Coalesce
