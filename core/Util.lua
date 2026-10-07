local _, NS = ...
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

-- Deep-copy a value: tables are copied all the way down, anything else is returned as is.
-- Database:Export copies each record's nested tables through it, so an export never aliases a
-- live SavedVariables row.
function Util.DeepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do out[k] = Util.DeepCopy(val) end
  return out
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

-- DD-MMM-YYYY (e.g. 11-Jul-2026) for the Date column — unambiguous across locales (no US/EU
-- MM/DD confusion).
function Util.FormatDate(ts)
  return date("%d-%b-%Y", ts or 0)
end

-- A date-range key → a `from` epoch timestamp (nil = no lower bound / "all"). "today" is the
-- current calendar day; "7d"/"30d" are rolling windows. Shared by the Browser date filter and
-- the Insights range selector so the two can't drift. 90d/1y were added for the Timeline (spec
-- §8.1); History and Insights offer them too, since the filter is one singleton.
function Util.RangeFrom(range)
  local now = time()
  if range == "today" then
    local t = date("*t", now)
    return now - (t.hour * 3600 + t.min * 60 + t.sec)
  elseif range == "7d" then
    return now - 7 * 86400
  elseif range == "30d" then
    return now - 30 * 86400
  elseif range == "90d" then
    return now - 90 * 86400
  elseif range == "1y" then
    return now - 365 * 86400
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

-- Patterns compiled from client globals, and the globals they were compiled FROM.
--
-- Each pattern set is compiled once per distinct set of source globals, not once per session:
-- another addon may rewrite these globals at runtime. PrettyChat does, on every settings write,
-- profile change, /pc disable|enable and combat boundary (its docs call this handoff H-1), and a
-- set compiled once and never re-checked silently dropped every self-loot and currency record until
-- /reload (PC-R-01). So each set keeps the exact source strings beside it, and every parse compares
-- the live globals against them: plain rawequal compares over the reader's multiple returns, no
-- table and no string built on the hit path (performance-§2 — CHAT_MSG_LOOT is a combat-path event).
-- Any difference, including a global that appeared or disappeared, rebuilds the set.

-- True when the recorded sources `src` still match the live globals the reader returned.
local function sameSources(src, ...)
  if not src then return false end
  for i = 1, select("#", ...) do
    if not rawequal(src[i], (select(i, ...))) then return false end
  end
  return true
end

-- Compile one pattern set. `shapes[i]` describes the i-th global the reader returns (`hasQty`, and
-- an optional self-identifying `source` tag); an absent global is skipped. Returns the patterns
-- and the source strings they came from, positionally, for sameSources.
local function compilePatterns(shapes, ...)
  local out, src = {}, {}
  for i = 1, #shapes do
    local g = (select(i, ...))
    src[i] = g
    if g then
      local s = shapes[i]
      out[#out + 1] = { pattern = toLootPattern(g), hasQty = s.hasQty, source = s.source }
    end
  end
  return out, src
end

-- Self-loot patterns. Quantity-bearing variants come first: their (.+) is greedy, so a single-loot
-- pattern would otherwise swallow the trailing "xN" of a multiple-loot line. Some variants carry a
-- `source` tag: their loot line is itself the authoritative, locale-independent proof of the
-- source — a bonus roll (LOOT_ITEM_BONUS_ROLL_SELF), a crafted item (LOOT_ITEM_CREATED_SELF, "You
-- create"), or a token/vendor refund (LOOT_ITEM_REFUND, "You are refunded") — so the collector
-- attributes them directly to that source rather than reading the peripheral loot context (see
-- docs/data-flow.md). LOOT_SHAPES is positional: entry i describes lootGlobals()'s i-th return.
-- modules/Diagnostics.lua's LOOT_GLOBALS names the same globals; keep the three in step.
local function lootGlobals()
  return LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF_MULTIPLE, LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE,
    LOOT_ITEM_CREATED_SELF_MULTIPLE, LOOT_ITEM_REFUND_MULTIPLE, LOOT_ITEM_SELF, LOOT_ITEM_PUSHED_SELF,
    LOOT_ITEM_BONUS_ROLL_SELF, LOOT_ITEM_CREATED_SELF, LOOT_ITEM_REFUND
end
local LOOT_SHAPES = {
  { hasQty = true },                          -- LOOT_ITEM_SELF_MULTIPLE
  { hasQty = true },                          -- LOOT_ITEM_PUSHED_SELF_MULTIPLE
  { hasQty = true,  source = "BONUS_ROLL" },  -- LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE
  { hasQty = true,  source = "CRAFT" },       -- LOOT_ITEM_CREATED_SELF_MULTIPLE
  { hasQty = true,  source = "REFUND" },      -- LOOT_ITEM_REFUND_MULTIPLE
  { hasQty = false },                         -- LOOT_ITEM_SELF
  { hasQty = false },                         -- LOOT_ITEM_PUSHED_SELF
  { hasQty = false, source = "BONUS_ROLL" },  -- LOOT_ITEM_BONUS_ROLL_SELF
  { hasQty = false, source = "CRAFT" },       -- LOOT_ITEM_CREATED_SELF
  { hasQty = false, source = "REFUND" },      -- LOOT_ITEM_REFUND
}
local lootPatterns, lootSources
function Util.BuildLootPatterns()
  lootPatterns, lootSources = compilePatterns(LOOT_SHAPES, lootGlobals())
  return lootPatterns
end

-- Shared matcher: the first pattern that matches wins.
local function matchPatterns(pats, msg)
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

-- Parse a CHAT_MSG_LOOT line. Returns itemLink, quantity, source for the player's own loot;
-- nil otherwise. `source` is a self-identifying SourceType string ("BONUS_ROLL"/"CRAFT"/"REFUND")
-- for the tagged variants, else nil (the collector then reads the peripheral context).
function Util.ParseSelfLoot(msg)
  if not msg then return nil end
  local pats = lootPatterns
  if not (pats and sameSources(lootSources, lootGlobals())) then pats = Util.BuildLootPatterns() end
  return matchPatterns(pats, msg)
end

-- The roll-won line ("You won: <item>", LOOT_ROLL_YOU_WON) announces that YOU won a group need/
-- greed/transmog roll. It is NOT itself a receipt — no record is written on it; the item arrives a
-- moment later on a normal "You receive loot:" line. The collector uses this to stamp ROLL context
-- so that imminent receive line attributes to the roll rather than inheriting a stale kill/container
-- stamp. Compiled once per distinct LOOT_ROLL_YOU_WON, like the self-loot patterns (false = the
-- global string is absent; a false cached while it was absent is rebuilt once it appears).
local rollWonPattern, rollWonSource
function Util.RollWonPattern()
  rollWonSource = LOOT_ROLL_YOU_WON
  rollWonPattern = rollWonSource and toLootPattern(rollWonSource) or false
  return rollWonPattern
end

-- Returns the item link if `msg` is the player's own roll-won line, else nil.
function Util.ParseRollWon(msg)
  if not msg then return nil end
  local pat = rollWonPattern
  if pat == nil or not rawequal(rollWonSource, LOOT_ROLL_YOU_WON) then pat = Util.RollWonPattern() end
  if not pat then return nil end
  return msg:match(pat)
end

-- Self-currency patterns, from the CHAT_MSG_CURRENCY global strings. Quantity-bearing variants
-- (incl. the bonus/overflow parenthetical forms) come first so the greedy single-pattern (.+) can't
-- swallow a trailing "xN (...)". The overflow global embeds a second %s (the currency name);
-- toLootPattern turns it into a third capture that ParseSelfCurrency simply ignores.
-- A currency-vendor refund returns the currency on THIS channel (not CHAT_MSG_LOOT) as a
-- "You are refunded" line (LOOT_ITEM_REFUND*); like the item refund/craft/bonus-roll lines it is
-- self-identifying, so its `source` tag lets the collector attribute REFUND directly (see Collector).
-- CURRENCY_SHAPES is positional against currencyGlobals(), as LOOT_SHAPES is against lootGlobals().
local function currencyGlobals()
  return CURRENCY_GAINED_MULTIPLE_OVERFLOW, CURRENCY_GAINED_MULTIPLE_BONUS, CURRENCY_GAINED_MULTIPLE,
    LOOT_ITEM_REFUND_MULTIPLE, CURRENCY_GAINED, LOOT_ITEM_REFUND
end
local CURRENCY_SHAPES = {
  { hasQty = true },                          -- CURRENCY_GAINED_MULTIPLE_OVERFLOW
  { hasQty = true },                          -- CURRENCY_GAINED_MULTIPLE_BONUS
  { hasQty = true },                          -- CURRENCY_GAINED_MULTIPLE
  { hasQty = true,  source = "REFUND" },      -- LOOT_ITEM_REFUND_MULTIPLE
  { hasQty = false },                         -- CURRENCY_GAINED
  { hasQty = false, source = "REFUND" },      -- LOOT_ITEM_REFUND
}
local currencyPatterns, currencySources
function Util.BuildCurrencyPatterns()
  currencyPatterns, currencySources = compilePatterns(CURRENCY_SHAPES, currencyGlobals())
  return currencyPatterns
end

-- Parse a CHAT_MSG_CURRENCY line. Returns currencyLink, quantity, source for the player's own
-- currency gain; nil otherwise (another player's line, or a non-currency message). `source` is
-- "REFUND" for a self-identifying refund line, else nil (the collector then reads the context).
function Util.ParseSelfCurrency(msg)
  if not msg then return nil end
  local pats = currencyPatterns
  if not (pats and sameSources(currencySources, currencyGlobals())) then
    pats = Util.BuildCurrencyPatterns()
  end
  return matchPatterns(pats, msg)
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
  -- The window in flight is its NS.After HANDLE, not a boolean. The stand-down cancels every
  -- deferral (NS.CancelDeferrals), and a canceled body never runs -- so a flag cleared only inside
  -- the body stayed set, and this trigger returned early for the rest of the session. The settings
  -- panel's readout coalescer is built once and outlives the stand-down, so `/lh disable` within
  -- one delay of a loot line froze it. A canceled handle therefore counts as no window at all, and
  -- the next trigger after the stand-up arms a fresh one.
  local window
  return function()
    if window and not window.canceled then return end
    -- No C_Timer — headless, or a client old enough to lack it. Run straight through: correct and
    -- slow beats a surface that silently never repaints.
    if not (C_Timer and C_Timer.After) then return fn() end
    -- NS.After rather than C_Timer.After, so a coalesced repaint that is already in flight when the
    -- player switches the addon off is CANCELED rather than left armed to wake up and find a flag
    -- (slash-commands-§7). A repaint timer re-arming ten times a second in combat and then
    -- discovering it has nothing to paint is the single shape that section singles out.
    window = NS.After(delay, function()
      -- Cleared BEFORE the body, not after. A raise inside `fn` would otherwise leave the window
      -- set for the rest of the session and this surface would never repaint again — trading a
      -- slow window for a dead one, which is the worse bug and the harder one to notice.
      window = nil
      fn()
    end)
  end
end

NS.Coalesce = Util.Coalesce

-- Row accessors (timeline-ledger spec §4.1). Rows written before schema v11 carry none of `dir`,
-- `kind`, `holder`; they were all gains, recorded by `char`. No consumer reads the raw fields.
function Util.RowDir(r) return r.dir or "IN" end
function Util.RowKind(r)
  if r.kind then return r.kind end
  if r.itemID == nil and r.currencyID ~= nil then return "CURRENCY" end
  return "ITEM"
end
function Util.RowHolder(r) return r.holder or r.char end

-- CHAT_MSG_MONEY (timeline-ledger spec §5.4 "Gold gains"): the player's own looted money and their
-- party share. The money text is the localized "1 Gold, 2 Silver, 3 Copper" built from
-- GOLD_AMOUNT / SILVER_AMOUNT / COPPER_AMOUNT, any part omitted when zero.
local moneyPatterns, coinPatterns
function Util.BuildMoneyPatterns()
  moneyPatterns, coinPatterns = {}, {}
  for _, g in ipairs({ YOU_LOOT_MONEY_GUILD, LOOT_MONEY_SPLIT, YOU_LOOT_MONEY }) do
    if type(g) == "string" then moneyPatterns[#moneyPatterns + 1] = toLootPattern(g) end
  end
  for mult, g in pairs({ [10000] = GOLD_AMOUNT, [100] = SILVER_AMOUNT, [1] = COPPER_AMOUNT }) do
    if type(g) == "string" then
      local p = g:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1"):gsub("%%%%d", "(%%d+)")
      coinPatterns[#coinPatterns + 1] = { pattern = p, mult = mult }
    end
  end
end

function Util.ParseSelfMoney(msg)
  if not msg then return nil end
  if not moneyPatterns then Util.BuildMoneyPatterns() end
  for _, p in ipairs(moneyPatterns) do
    local text = msg:match(p)
    if text then
      local copper = 0
      for _, c in ipairs(coinPatterns) do
        local n = text:match(c.pattern)
        if n then copper = copper + tonumber(n) * c.mult end
      end
      return copper > 0 and copper or nil
    end
  end
  return nil
end

-- "Name" or "Name-Realm" -> "Name-Realm" on the player's own (normalized) realm. Mail recipients and
-- trade partners are typed or shown without a realm when they share the player's.
function Util.QualifyName(name)
  if not name or name == "" then return nil end
  if name:find("-", 1, true) then return (name:gsub("%s+", "")) end
  local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
  return name .. "-" .. tostring(realm):gsub("%s+", "")
end
