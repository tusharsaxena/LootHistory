# Currency Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture looted **currency** (not gold) into the account-wide history, attributed to the same sources as items, and surface it in the History table, Insights, and CSV export.

**Architecture:** Currency records live in the same `global.history` array, reusing existing columns (`Type = "Currency"`, `SubType = <live category>`, `quantity`) with a new `currencyID` field as the structural signal (`itemID == nil && currencyID ~= nil`). A new `CHAT_MSG_CURRENCY` handler parses the line, reuses the existing attribution context for the source, and writes a currency record through a slim gate (master toggle + source mute; no quality/quest/blacklist gate). `Database:Stats` becomes currency-aware so currency enriches activity charts but never pollutes item-centric ones. Insights, the History table, and CSV export get null-safe / currency-aware additions. Export-to-AI is deferred.

**Tech Stack:** Lua 5.1, WoW Retail API (Ace3), headless `lua tests/run.lua` harness + `luacheck`.

**Spec:** `docs/superpowers/specs/2026-07-21-currency-capture-design.md`

## Global Constraints

- **Work on branch `feature/currency-capture`** (already created and checked out). Never commit to `master`.
- **Account-wide storage only** — currency records go in `LootHistoryDB.global.history`; the toggle in `.global.settings`. Never per-character profiles.
- **Compat firewall** — every `C_CurrencyInfo`/new API access lives in `core/Compat.lua`, gated by a direct presence check, degrading to `nil`/`false` when absent. No `WOW_PROJECT_ID` branching.
- **Schema-as-single-source** — the `recordCurrency` setting is a `settings/Schema.lua` row; all reads/writes go through `Schema:Get`/`Schema:Set`. Add its default to `defaults/Global.lua`.
- **Closed message bus** — do not add new `Ka0s_LootHistory_*` messages; reuse `RecordAdded`/`HistoryChanged`.
- **English only.** No localization work.
- **Never bump the version** (`## Version`, `NS.version`, README badge/history).
- **Run `lua tests/run.lua` (0 failures) and `luacheck .` (0 warnings/errors) before every commit.**
- **Test inventory + badge stay in sync:** when the suite changes, regenerate `docs/test-cases.md` (`lua tests/run.lua --list > docs/test-cases.md`) and update the README `Tests-<n>/<n>` badge in the same change (done in Task 9).
- **Currency record shape (canonical — every task depends on this):**
  ```lua
  { ts, char, classFile, zone, mapID, subzone,        -- shared with items
    source, sourceDetail, confidence,                 -- shared (attribution reuse)
    currencyID  = <number>,                            -- structural signal
    itemName    = <currency name>,                     -- reuses the name column
    itemType    = "Currency",                          -- Constants.CURRENCY_TYPE
    itemSubType = <category string | nil>,             -- live game category
    quantity    = <number>,
    -- itemID / itemLink / quality / itemLevel / bound / vendorPrice / auctionPrice = nil
  }
  ```

---

### Task 1: Currency line parser (`Util.ParseSelfCurrency`)

**Files:**
- Modify: `tests/wow_mock.lua` (add currency global strings)
- Modify: `.luacheckrc` (declare the new read-globals)
- Modify: `core/Util.lua` (add `BuildCurrencyPatterns` + `ParseSelfCurrency`)
- Test: `tests/test_util.lua`

**Interfaces:**
- Produces: `NS.Util.ParseSelfCurrency(msg) -> currencyLink (string), quantity (number)` for the player's own currency line; `nil` otherwise. Reuses the file-local `toLootPattern` helper already in `core/Util.lua`.

- [ ] **Step 1: Add currency global strings to the mock**

In `tests/wow_mock.lua`, after the existing `LOOT_ROLL_YOU_WON` line added earlier (search for `LOOT_ROLL_YOU_WON`), add:

```lua
  -- Currency gain strings (CHAT_MSG_CURRENCY). Single has no qty; multiples carry xN, and the
  -- bonus/overflow variants append a parenthetical (the overflow one embeds a second %s = the
  -- currency name, which the parser ignores).
  M.CURRENCY_GAINED = "You receive currency: %s"
  M.CURRENCY_GAINED_MULTIPLE = "You receive currency: %sx%d"
  M.CURRENCY_GAINED_MULTIPLE_BONUS = "You receive currency: %sx%d (Bonus Objective)"
  M.CURRENCY_GAINED_MULTIPLE_OVERFLOW = "You receive currency: %sx%d (You've earned the maximum amount of %s)"
```

- [ ] **Step 2: Declare the new globals in `.luacheckrc`**

In `.luacheckrc`, in the `read_globals` list, right after the `LOOT_ROLL_YOU_WON` entry added earlier, add:

```lua
  "CURRENCY_GAINED", "CURRENCY_GAINED_MULTIPLE",
  "CURRENCY_GAINED_MULTIPLE_BONUS", "CURRENCY_GAINED_MULTIPLE_OVERFLOW",
```

- [ ] **Step 3: Write the failing test**

In `tests/test_util.lua`, inside the existing `do ... end` block that defines `local LINK = ...` and the `ParseSelfLoot` tests (right before the block's closing `end`), add:

```lua
  local CURR = "|cffffffff|Hcurrency:3008::|h[Valorstones]|h|r"

  test("Util: ParseSelfCurrency single currency line -> link, qty 1", function()
    local link, qty = NS.Util.ParseSelfCurrency(string.format(T.mocks.CURRENCY_GAINED, CURR))
    assertEqual(link, CURR)
    assertEqual(qty, 1)
  end)

  test("Util: ParseSelfCurrency multiple currency line -> link, qty N", function()
    local link, qty = NS.Util.ParseSelfCurrency(string.format(T.mocks.CURRENCY_GAINED_MULTIPLE, CURR, 45))
    assertEqual(link, CURR)
    assertEqual(qty, 45)
  end)

  test("Util: ParseSelfCurrency bonus + overflow variants -> link, qty", function()
    local l1, q1 = NS.Util.ParseSelfCurrency(string.format(T.mocks.CURRENCY_GAINED_MULTIPLE_BONUS, CURR, 10))
    assertEqual(l1, CURR); assertEqual(q1, 10)
    local l2, q2 = NS.Util.ParseSelfCurrency(
      string.format(T.mocks.CURRENCY_GAINED_MULTIPLE_OVERFLOW, CURR, 5, "Valorstones"))
    assertEqual(l2, CURR); assertEqual(q2, 5)
  end)

  test("Util: ParseSelfCurrency ignores item loot and other players", function()
    assertEqual(NS.Util.ParseSelfCurrency(string.format(T.mocks.LOOT_ITEM_SELF, LINK)), nil)
    assertEqual(NS.Util.ParseSelfCurrency("Someone receives currency: " .. CURR), nil)
  end)
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -E "ParseSelfCurrency|FAIL"`
Expected: FAILs with an error like `attempt to call ... 'ParseSelfCurrency' (a nil value)`.

- [ ] **Step 5: Implement the parser**

In `core/Util.lua`, immediately after the `Util.ParseRollWon` function (search for `function Util.ParseRollWon`), add:

```lua
-- Self-currency patterns, compiled once from the CHAT_MSG_CURRENCY global strings. Quantity-bearing
-- variants (incl. the bonus/overflow parenthetical forms) come first so the greedy single-pattern
-- (.+) can't swallow a trailing "xN (...)". The overflow global embeds a second %s (the currency
-- name); toLootPattern turns it into a third capture that ParseSelfCurrency simply ignores.
local currencyPatterns
function Util.BuildCurrencyPatterns()
  local specs = {
    { g = CURRENCY_GAINED_MULTIPLE_OVERFLOW, hasQty = true },
    { g = CURRENCY_GAINED_MULTIPLE_BONUS,    hasQty = true },
    { g = CURRENCY_GAINED_MULTIPLE,          hasQty = true },
    { g = CURRENCY_GAINED,                   hasQty = false },
  }
  local out = {}
  for _, s in ipairs(specs) do
    if s.g then out[#out + 1] = { pattern = toLootPattern(s.g), hasQty = s.hasQty } end
  end
  currencyPatterns = out
  return out
end

-- Parse a CHAT_MSG_CURRENCY line. Returns currencyLink, quantity for the player's own currency
-- gain; nil otherwise (another player's line, or a non-currency message).
function Util.ParseSelfCurrency(msg)
  if not msg then return nil end
  local pats = currencyPatterns or Util.BuildCurrencyPatterns()
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
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `lua tests/run.lua 2>&1 | tail -2 && luacheck . 2>&1 | tail -2`
Expected: all tests pass; luacheck reports 0 warnings / 0 errors.

- [ ] **Step 7: Commit**

```bash
git add core/Util.lua tests/test_util.lua tests/wow_mock.lua .luacheckrc
git commit -m "feat(currency): parse CHAT_MSG_CURRENCY self-lines"
```

---

### Task 2: Compat currency shims

**Files:**
- Modify: `tests/wow_mock.lua` (mock `C_CurrencyInfo`)
- Modify: `core/Compat.lua` (add `CurrencyLinkID`, `GetCurrencyInfoFromLink`, `CurrencyCategory`)
- Test: `tests/test_compat.lua`

**Interfaces:**
- Produces:
  - `NS.Compat.CurrencyLinkID(link) -> currencyID (number) | nil` — parsed from the link, locale-independent.
  - `NS.Compat.GetCurrencyInfoFromLink(link) -> currencyID, name, iconFileID` — id + name from the link (name enriched by `C_CurrencyInfo` when present); `iconFileID` nil when the API is absent.
  - `NS.Compat.CurrencyCategory(currencyID) -> category (string) | nil` — the currency's list-header group, cached per session; nil when unresolved / API absent.

- [ ] **Step 1: Mock `C_CurrencyInfo` in the harness**

In `tests/wow_mock.lua`, near the other `C_*` mocks (search for `C_Item` or add a new block before `return M`), add:

```lua
  -- Currency API mock. GetCurrencyListSize / GetCurrencyListInfo / GetCurrencyListLink model a tiny
  -- currency window: one expansion header ("The War Within") then two currencies under it, so the
  -- category resolver has headers to walk. GetCurrencyInfoFromLink returns name + icon by id.
  M.__currencyNames = { [3008] = "Valorstones", [2914] = "Weathered Harbinger Crest" }
  M.C_CurrencyInfo = {
    GetCurrencyListSize = function() return 3 end,
    GetCurrencyListInfo = function(i)
      if i == 1 then return { name = "The War Within", isHeader = true } end
      if i == 2 then return { name = M.__currencyNames[3008], isHeader = false } end
      if i == 3 then return { name = M.__currencyNames[2914], isHeader = false } end
      return nil
    end,
    GetCurrencyListLink = function(i)
      if i == 2 then return "|Hcurrency:3008::|h[Valorstones]|h" end
      if i == 3 then return "|Hcurrency:2914::|h[Weathered Harbinger Crest]|h" end
      return nil
    end,
    GetCurrencyInfoFromLink = function(link)
      local id = tonumber(link and link:match("|?H?currency:(%d+)"))
      if not id then return nil end
      return { name = M.__currencyNames[id], iconFileID = 100000 + id }
    end,
  }
```

- [ ] **Step 2: Write the failing test**

Create/append to `tests/test_compat.lua` (if the file already has a header `local T = _G.LH_TEST` etc., just append the tests):

```lua
test("Compat: CurrencyLinkID parses the id from a currency link", function()
  assertEqual(NS.Compat.CurrencyLinkID("|cffffffff|Hcurrency:3008::|h[Valorstones]|h|r"), 3008)
  assertEqual(NS.Compat.CurrencyLinkID("|Hitem:12345::|h[Nope]|h"), nil)
  assertEqual(NS.Compat.CurrencyLinkID(nil), nil)
end)

test("Compat: GetCurrencyInfoFromLink returns id, name, icon", function()
  local id, name, icon = NS.Compat.GetCurrencyInfoFromLink("|Hcurrency:3008::|h[Valorstones]|h")
  assertEqual(id, 3008)
  assertEqual(name, "Valorstones")
  assertEqual(icon, 100000 + 3008)
end)

test("Compat: CurrencyCategory resolves a currency to its list header", function()
  assertEqual(NS.Compat.CurrencyCategory(3008), "The War Within")
  assertEqual(NS.Compat.CurrencyCategory(2914), "The War Within")
  assertEqual(NS.Compat.CurrencyCategory(999999), nil)   -- unknown id -> nil
end)
```

If `tests/test_compat.lua` does not exist, create it with this header first:

```lua
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse
```

(and confirm `"test_compat.lua"` is listed in `tests/run.lua`'s `SUITE_FILES` — it already is.)

- [ ] **Step 3: Run the test to verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -E "Currency|FAIL"`
Expected: FAILs — `CurrencyLinkID`/`GetCurrencyInfoFromLink`/`CurrencyCategory` are nil.

- [ ] **Step 4: Implement the shims**

In `core/Compat.lua`, before the final `GetAddOnMetadata` function (or at the end of the file, before nothing — just append near the other item helpers), add:

```lua
-- Currency id parsed from a |Hcurrency:ID:...|h link. Locale-independent; nil when absent.
function Compat.CurrencyLinkID(link)
  if not link then return nil end
  return tonumber(link:match("|?H?currency:(%d+)"))
end

-- Resolve a currency link to id, name, iconFileID. Id + name come from the link itself (so this
-- works headlessly / before the client caches the currency); C_CurrencyInfo enriches name + icon
-- when present. icon is nil when the API is absent.
function Compat.GetCurrencyInfoFromLink(link)
  local id = Compat.CurrencyLinkID(link)
  local name = link and link:match("%[(.-)%]")
  local icon
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfoFromLink then
    local info = C_CurrencyInfo.GetCurrencyInfoFromLink(link)
    if info then
      name = info.name or name
      icon = info.iconFileID
    end
  end
  return id, name, icon
end

-- currencyID -> category (the currency window's expansion/type header, e.g. "The War Within").
-- Built once by walking the currency list and tracking the most recent header, then cached for the
-- session. nil when the API is absent or the id isn't in the list. Cheap after the first call.
local currencyCategoryCache
local function buildCurrencyCategoryCache()
  currencyCategoryCache = {}
  local api = C_CurrencyInfo
  if not (api and api.GetCurrencyListSize and api.GetCurrencyListInfo and api.GetCurrencyListLink) then
    return
  end
  local header
  for i = 1, (api.GetCurrencyListSize() or 0) do
    local info = api.GetCurrencyListInfo(i)
    if info then
      if info.isHeader then
        header = info.name
      else
        local id = Compat.CurrencyLinkID(api.GetCurrencyListLink(i))
        if id and header then currencyCategoryCache[id] = header end
      end
    end
  end
end
function Compat.CurrencyCategory(currencyID)
  if not currencyID then return nil end
  if not currencyCategoryCache then buildCurrencyCategoryCache() end
  return currencyCategoryCache[currencyID]
end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `lua tests/run.lua 2>&1 | tail -2 && luacheck . 2>&1 | tail -2`
Expected: all pass; luacheck clean.

- [ ] **Step 6: Commit**

```bash
git add core/Compat.lua tests/test_compat.lua tests/wow_mock.lua
git commit -m "feat(currency): Compat shims for currency link + category"
```

---

### Task 3: `recordCurrency` setting + `Currency` type constant

**Files:**
- Modify: `core/Constants.lua` (add `C.CURRENCY_TYPE`)
- Modify: `defaults/Global.lua` (add `recordCurrency` default)
- Modify: `settings/Schema.lua` (add the schema row)
- Modify: `docs/settings-panel.md` (row-count claim)
- Test: `tests/test_schema.lua`

**Interfaces:**
- Produces: `NS.Constants.CURRENCY_TYPE == "Currency"`; schema path `settings.recordCurrency` (bool, default true) readable via `NS.Schema:Get`/settable via `NS.Schema:Set`, broadcasting `Ka0s_LootHistory_SettingsChanged` with reason `"currency"`.

- [ ] **Step 1: Add the constant**

In `core/Constants.lua`, after the `ITEMCLASS_QUEST` line (search for `C.ITEMCLASS_QUEST`), add:

```lua
-- The itemType string used for currency records (they reuse the item Type/SubType columns). Real
-- items never carry this GetItemInfo type, so it doubles as a display label and a Type-filter value.
C.CURRENCY_TYPE = "Currency"
```

- [ ] **Step 2: Add the default**

In `defaults/Global.lua`, in the `settings = { ... }` block, after the `excludeQuestItems` line, add:

```lua
    recordCurrency   = true,   -- record looted currency (Type=Currency rows); source-muted like items
```

- [ ] **Step 3: Write the failing test**

In `tests/test_schema.lua`, add:

```lua
test("Schema: recordCurrency row exists, defaults true, settable", function()
  assertEqual(NS.Schema:Default("settings.recordCurrency"), true)
  assertEqual(NS.defaults.global.settings.recordCurrency, true)
  assertTrue(NS.Schema:Set("settings.recordCurrency", false))
  assertEqual(NS.Schema:Get("settings.recordCurrency"), false)
  NS.Schema:Set("settings.recordCurrency", true)   -- restore default
end)

test("Constants: CURRENCY_TYPE is \"Currency\"", function()
  assertEqual(NS.Constants.CURRENCY_TYPE, "Currency")
end)
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -E "recordCurrency|CURRENCY_TYPE|FAIL"`
Expected: FAILs — the row/constant don't exist yet.

- [ ] **Step 5: Add the schema row**

In `settings/Schema.lua`, in the `-- ── Data Collection ──` group, immediately after the `settings.excludeQuestItems` row (the one whose `onChange` sends `"questfilter"`), add:

```lua
  { path = "settings.recordCurrency", default = true, type = "boolean", widget = "CheckBox",
    group = "Data Collection", label = "Record currency",
    tooltip = "Record looted currency (Valorstones, crests, etc.) as Type=Currency rows. " ..
      "Obeys the per-source mute list; ignores the minimum-quality filter.",
    onChange = function()
      if NS.bus then NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "currency") end
    end },
```

- [ ] **Step 6: Update the settings-panel row-count doc**

In `docs/settings-panel.md`, find the line starting `Ten rows ship today (`Schema.lua:11`):` and change `Ten rows` to `Eleven rows`, and insert `settings.recordCurrency` into the listed Data-Collection paths (after `settings.excludeQuestItems`):

```markdown
Eleven rows ship today (`Schema.lua:11`): `settings.enabled`, `minimap.hide`, `state.debugConsole`, `settings.windowScale` (Master Controls); `settings.qualityThreshold`, `settings.excludeQuestItems`, `settings.recordCurrency`, `settings.retentionDays`, `settings.excludedSources` (Data Collection); `settings.auction.enabled`, `settings.auction.capture` (AH Price — the latter carries `panelSkip`, driven by the price table rather than a rendered widget).
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `lua tests/run.lua 2>&1 | tail -2 && luacheck . 2>&1 | tail -2`
Expected: all pass; luacheck clean.

- [ ] **Step 8: Commit**

```bash
git add core/Constants.lua defaults/Global.lua settings/Schema.lua docs/settings-panel.md tests/test_schema.lua
git commit -m "feat(currency): recordCurrency setting + Currency type constant"
```

---

### Task 4: Collector currency capture

**Files:**
- Modify: `modules/Collector.lua` (upvalue, `OnChatMsgCurrency`, event registration)
- Test: `tests/test_collector.lua`

**Interfaces:**
- Consumes: `Util.ParseSelfCurrency`, `Compat.GetCurrencyInfoFromLink`, `Compat.CurrencyCategory`, `Attribution:Consume`, `Constants.CURRENCY_TYPE`, `Database:Add`.
- Produces: `Collector:OnChatMsgCurrency(_, msg)` — writes one currency record (canonical shape from Global Constraints) when `enabled` and `recordCurrency` are on and the source is not muted.

- [ ] **Step 1: Write the failing tests**

In `tests/test_collector.lua`, after the ROLL end-to-end test added earlier (search for `stamps ROLL for the receive line`), add:

```lua
local CURRENCY_LINK = "|cffffffff|Hcurrency:3008::|h[Valorstones]|h|r"

test("Collector: end-to-end records a currency line as Type=Currency", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.State.lootContext = nil
  NS.db.global.settings.qualityThreshold = 5   -- high: proves currency ignores the quality gate
  NS.db.global.settings.recordCurrency = true
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("MPLUS", { keystoneLevel = 12 }, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgCurrency(nil, string.format(mocks.CURRENCY_GAINED_MULTIPLE, CURRENCY_LINK, 45))
  assertEqual(NS.Database:Count(), before + 1)
  local r = NS.Database:History()[NS.Database:Count()]
  assertEqual(r.itemType, "Currency")
  assertEqual(r.currencyID, 3008)
  assertEqual(r.itemName, "Valorstones")
  assertEqual(r.quantity, 45)
  assertEqual(r.source, "MPLUS")
  assertEqual(r.confidence, "CERTAIN")
  assertEqual(r.itemID, nil)
  assertEqual(r.quality, nil)

  NS.db.global.settings.qualityThreshold = 2   -- restore
  NS.Collector:RefreshUpvalues()
end)

test("Collector: recordCurrency off drops currency", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.global.settings.recordCurrency = false
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("MPLUS", nil, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgCurrency(nil, string.format(mocks.CURRENCY_GAINED, CURRENCY_LINK))
  assertEqual(NS.Database:Count(), before)

  NS.db.global.settings.recordCurrency = true   -- restore
  NS.Collector:RefreshUpvalues()
end)

test("Collector: a muted source drops its currency too", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.global.settings.recordCurrency = true
  NS.db.global.settings.excludedSources = { MPLUS = true }
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("MPLUS", nil, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgCurrency(nil, string.format(mocks.CURRENCY_GAINED, CURRENCY_LINK))
  assertEqual(NS.Database:Count(), before)

  NS.db.global.settings.excludedSources = {}   -- restore
  NS.Collector:RefreshUpvalues()
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `lua tests/run.lua 2>&1 | grep -E "currency line|recordCurrency off|muted source|FAIL"`
Expected: FAILs — `OnChatMsgCurrency` is nil.

- [ ] **Step 3: Add the `recordCurrency` upvalue**

In `modules/Collector.lua`, change the hot-path upvalue line (line 9):

```lua
local enabled, qualityThreshold, excludedSources, excludeQuestItems = true, 1, {}, false
```

to:

```lua
local enabled, qualityThreshold, excludedSources, excludeQuestItems = true, 1, {}, false
local recordCurrency = true
```

And in `Collector:RefreshUpvalues`, after the `excludeQuestItems = s.excludeQuestItems` line, add:

```lua
  recordCurrency = s.recordCurrency
```

- [ ] **Step 4: Add the currency handler**

In `modules/Collector.lua`, immediately after the `OnChatMsgLoot` function (before `function Collector:Enable()`), add:

```lua
-- CHAT_MSG_CURRENCY: currency loot. Reuses the same attribution context as items (currency fires in
-- the same loot window), but takes a slimmer gate — the recordCurrency master toggle + the per-source
-- mute list only; the quality threshold, quest filter, and itemID blacklist don't apply to currency.
function Collector:OnChatMsgCurrency(_, msg)
  if not enabled or not recordCurrency then return end
  local link, qty = NS.Util.ParseSelfCurrency(msg)
  if not link then return end

  local currencyID, name = NS.Compat.GetCurrencyInfoFromLink(link)
  if not currencyID then return end

  local source, sourceDetail, confidence = NS.Attribution:Consume()
  if excludedSources[source] then
    if NS.State.debug and NS.Debug then
      NS.Debug("Drop", "currency %s src=%s reason=source", tostring(name), tostring(source))
    end
    return
  end

  local zone, subzone = NS.Compat.GetZone()
  local record = {
    ts = time(), char = NS.Util.PlayerKey(), classFile = select(2, UnitClass("player")),
    currencyID = currencyID, itemName = name,
    itemType = NS.Constants.CURRENCY_TYPE, itemSubType = NS.Compat.CurrencyCategory(currencyID),
    quantity = qty,
    source = source, sourceDetail = sourceDetail, confidence = confidence,
    zone = zone, mapID = NS.Compat.GetPlayerMapID(), subzone = subzone,
  }
  NS.Database:Add(record)

  if NS.State.debug and NS.Debug then
    NS.Debug("Currency", "%s x%s id=%s src=%s conf=%s",
      tostring(name), tostring(qty), tostring(currencyID), source, confidence)
  end
end
```

- [ ] **Step 5: Register the event**

In `modules/Collector.lua`, in `Collector:Enable`, after the `CHAT_MSG_LOOT` registration line, add:

```lua
  bus:RegisterEvent("CHAT_MSG_CURRENCY", function(_, msg) self:OnChatMsgCurrency(_, msg) end)
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `lua tests/run.lua 2>&1 | tail -2 && luacheck . 2>&1 | tail -2`
Expected: all pass; luacheck clean.

- [ ] **Step 7: Commit**

```bash
git add modules/Collector.lua tests/test_collector.lua
git commit -m "feat(currency): capture CHAT_MSG_CURRENCY into history"
```

---

### Task 5: Currency-aware `Database:Stats`

**Files:**
- Modify: `core/Database.lua` (`Stats`)
- Test: `tests/test_stats.lua`

**Interfaces:**
- Produces, added to the `Database:Stats(filter)` return table:
  - `byCurrency` — `{ [currencyName] = totalQuantity }`
  - `currencySourceMatrix` — `{ [currencyName] = { [source] = quantity } }`
  - `currencyByChar` — `{ [char] = { char, classFile, quantity } }`
  - `currencyByDay` — `{ [dayKey] = totalQuantity }`
  - `currencyTotals` — `{ distinct = number, events = number, biggestHaul = { name, quantity } | nil }`
- Guarantees: currency records (`r.currencyID ~= nil`) are **excluded** from `byQuality`, `byType`, `byBound`, `byItem`/`distinctItems`/`topItems`/`topItemsByValue`, `epicPlus`, `bestDrop`, `richestDrop`; **included** in `bySource`, `byDay`, `byHour`, `byWeekday`, `byChar`, `byZone` counts. Row sums of `currencySourceMatrix[name]` equal `byCurrency[name]`.

- [ ] **Step 1: Write the failing test**

In `tests/test_stats.lua`, add:

```lua
test("Stats: currency enriches activity charts but not item charts", function()
  local recs = {
    { ts = 1000, char = "A-R", classFile = "MAGE", source = "KILL", confidence = "CERTAIN",
      itemID = 111, itemName = "Sword", quality = 4, itemLevel = 500, itemType = "Weapon",
      itemSubType = "Sword", bound = "BOP", quantity = 1, zone = "Z1" },
    { ts = 1000, char = "A-R", classFile = "MAGE", source = "MPLUS", confidence = "CERTAIN",
      currencyID = 3008, itemName = "Valorstones", itemType = "Currency",
      itemSubType = "The War Within", quantity = 40, zone = "Z1" },
    { ts = 1000, char = "B-R", classFile = "ROGUE", source = "QUEST", confidence = "CERTAIN",
      currencyID = 3008, itemName = "Valorstones", itemType = "Currency", quantity = 10, zone = "Z1" },
    { ts = 1000, char = "A-R", classFile = "MAGE", source = "MPLUS", confidence = "CERTAIN",
      currencyID = 2914, itemName = "Crest", itemType = "Currency", quantity = 3, zone = "Z1" },
  }
  NS.State.testRecords = recs
  local s = NS.Database:Stats({})
  NS.State.testRecords = nil

  -- Item-centric aggregates ignore currency:
  assertEqual(s.totals.distinctItems, 1)            -- only the Sword
  assertEqual(s.byQuality[4], 1)                    -- currency (nil quality) not bucketed as 0
  assertTrue(s.byQuality[0] == nil)
  assertTrue(s.byType["Currency"] == nil)           -- currency kept out of the item-type chart
  assertTrue(s.byType["Weapon"] == 1)
  assertEqual(s.epicPlus, 1)

  -- Activity charts include currency records (4 records total across 3 sources):
  assertEqual(s.totals.records, 4)
  assertEqual(s.bySource["MPLUS"], 2)               -- two currency records from M+
  assertEqual(s.bySource["QUEST"], 1)

  -- Currency aggregates:
  assertEqual(s.byCurrency["Valorstones"], 50)      -- 40 + 10
  assertEqual(s.byCurrency["Crest"], 3)
  assertEqual(s.currencySourceMatrix["Valorstones"]["MPLUS"], 40)
  assertEqual(s.currencySourceMatrix["Valorstones"]["QUEST"], 10)
  assertEqual(s.currencyByChar["A-R"].quantity, 43) -- 40 + 3
  assertEqual(s.currencyByDay[os.date("%Y-%m-%d", 1000)], 53)
  assertEqual(s.currencyTotals.distinct, 2)
  assertEqual(s.currencyTotals.events, 3)
  assertEqual(s.currencyTotals.biggestHaul.name, "Valorstones")
  assertEqual(s.currencyTotals.biggestHaul.quantity, 40)
end)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -E "currency enriches|FAIL"`
Expected: FAILs (e.g. `byCurrency` is nil, or `distinctItems` is 3).

- [ ] **Step 3: Add currency accumulators + guard the item aggregates**

In `core/Database.lua` `Database:Stats`, after the existing local declarations block (after the `local bestDrop, richestDrop` line), add:

```lua
  local byCurrency, currencySourceMatrix, currencyByChar, currencyByDay = {}, {}, {}, {}
  local currencyDistinct, currencyEvents = 0, 0
  local biggestHaul
```

Then, inside the `for _, r in ipairs(records) do` loop, restructure so item-only aggregates skip currency. Replace the block from `local q = r.quality or 0` down through the `byChar` accumulation (the section that builds `byQuality`, `byType`, `byBound`, `byItem`, and the highlights) — keep `bySource`, `valueBySource`, `byDay`, `byHour`, `byWeekday`, `byZone`, `byConfidence`, `byKeystone`, and `byChar` **counting all records** — but wrap the strictly item-centric ones in `if not isCurrency`. Concretely, at the top of the loop body (right after `local value = (NS.Util.RecordValue(r) or 0) * qty`) add:

```lua
    local isCurrency = r.currencyID ~= nil
```

Then wrap **only** these existing lines in `if not isCurrency then ... end`:
- the `byQuality[q] = ...` + `if q >= 4 then epicPlus ...` pair,
- the `local ty = r.itemType ...; byType[ty] ...` block,
- the `local bk = r.bound ...; byBound[bk] ...` block,
- the `local id = r.itemID ... byItem ... distinctItems ...` block,
- the two highlight blocks (`bestDrop` and `richestDrop`).

Leave `bySource`, `valueBySource`, `byDay`/`valueByDay`, `byHour`, `byWeekday`, `byZone`/`valueByZone`, `byConfidence`, `byKeystone`, and the `byChar` block **outside** the guard (they count currency too).

Then, still inside the loop, after the `byChar` block, add the currency accumulation:

```lua
    if isCurrency then
      currencyEvents = currencyEvents + 1
      local cname = r.itemName or ("currency " .. tostring(r.currencyID))
      if byCurrency[cname] == nil then currencyDistinct = currencyDistinct + 1 end
      byCurrency[cname] = (byCurrency[cname] or 0) + qty

      local m = currencySourceMatrix[cname]
      if not m then m = {}; currencySourceMatrix[cname] = m end
      m[src] = (m[src] or 0) + qty

      if r.char then
        local cc = currencyByChar[r.char]
        if cc then cc.quantity = cc.quantity + qty
        else currencyByChar[r.char] = { char = r.char, classFile = r.classFile, quantity = qty } end
      end

      if r.ts then
        local cday = date("%Y-%m-%d", r.ts)
        currencyByDay[cday] = (currencyByDay[cday] or 0) + qty
      end

      if not biggestHaul or qty > biggestHaul.quantity then
        biggestHaul = { name = cname, quantity = qty }
      end
    end
```

Note: `src` and `qty` are already defined earlier in the loop body (`local src = r.source or "OTHER"` and `local qty = r.quantity or 1`). The `byQuality`-adjacent `local q` may now live inside the `if not isCurrency` block — that's fine, `q` isn't used after it.

- [ ] **Step 4: Add the currency aggregates to the return table**

In the `return { ... }` at the end of `Database:Stats`, add these keys (e.g. right after the `byHour = ..., byWeekday = ..., byKeystone = ..., byConfidence = ...` line):

```lua
    byCurrency = byCurrency, currencySourceMatrix = currencySourceMatrix,
    currencyByChar = currencyByChar, currencyByDay = currencyByDay,
    currencyTotals = { distinct = currencyDistinct, events = currencyEvents, biggestHaul = biggestHaul },
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `lua tests/run.lua 2>&1 | tail -2 && luacheck . 2>&1 | tail -2`
Expected: all pass; luacheck clean.

- [ ] **Step 6: Commit**

```bash
git add core/Database.lua tests/test_stats.lua
git commit -m "feat(currency): currency-aware Database:Stats aggregates"
```

---

### Task 6: Insights currency block (Analytics)

**Files:**
- Modify: `modules/Analytics.lua` (pools/headers/panels, a stacked-bar-section renderer, the currency section in `LayoutCharts`, release + hide wiring)

**Interfaces:**
- Consumes: `stats.byCurrency`, `stats.currencySourceMatrix`, `stats.currencyByChar`, `stats.currencyByDay`, `stats.currencyTotals`, and `stats.totals.firstTs/lastTs`.
- Note: Analytics builds live frames, so it is **not** headless-unit-tested (matching the module's existing convention); verify via `luacheck` (loads clean) + the in-game smoke test added in Task 9.

- [ ] **Step 1: Add the stacked-bar-section renderer**

In `modules/Analytics.lua`, after the existing `renderBarSection` function (search for `function Analytics:renderBarSection`), add:

```lua
-- Render a section where each row is a horizontal STACKED bar (one per currency). rows: ordered
--   { label, value (string), segments = { {frac (0..1 of the track), color = {r,g,b}}, ... } }.
-- `frac`s are already max-relative (the caller divides by the largest currency total), so the
-- longest bar fills the track and each segment is that source's share of the track. Empty → skipped.
function Analytics:renderStackedBarSection(pool, header, rows, y, w, pad)
  if #rows == 0 then header:Hide(); return y end
  header:ClearAllPoints(); header:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y); header:Show()
  y = y - 18
  local innerW = w - pad * 2
  for _, row in ipairs(rows) do
    local bar = acquire(pool, function() return makeStackedBar(self.content) end)
    bar.label:SetText(row.label); bar.label:SetTextColor(0.9, 0.9, 0.9)
    bar.value:SetText(row.value); bar.value:SetTextColor(0.8, 0.8, 0.82)
    positionStacked(bar, self.content, pad, y, innerW, row.segments)
    y = y - (BAR_H + BAR_GAP)
  end
  return y - SECTION_GAP
end
```

- [ ] **Step 2: Register the currency headers, panels, and pools**

In `modules/Analytics.lua`, in `BuildCharts`, add to the `self.headers = { ... }` table these entries (e.g. after `conf = ...`). Four headers — one per titled currency section (the `currencyTitle` slot's text is overwritten at render time to carry the highlights):

```lua
    currencyTitle = sectionHeader(content, "Currency"),
    currencySrc   = sectionHeader(content, "Currency by source"),
    currencyChar  = sectionHeader(content, "Currency by character"),
    currencyTime  = sectionHeader(content, "Currency over time (per day)"),
```

After the `self.itemValuePanel = listPanel(...)` line, add:

```lua
  self.currencyPanel = listPanel(content, "Currency collected")
  self.currencyStrip = CreateFrame("Frame", nil, content)
```

In the `self.pool = { ... }` table, add these pools (e.g. after `itemval = ...`):

```lua
    curlist = { free = {}, active = {} }, cursrc = { free = {}, active = {} },
    curchar = { free = {}, active = {} }, curday = { free = {}, active = {} },
```

- [ ] **Step 3: Release the currency pools each layout**

In `LayoutCharts`, in the `for _, name in ipairs({ ... }) do releaseAll(P[name]) end` list, append the four new pool names:

```lua
                          "conf", "zone", "item", "itemval",
                          "curlist", "cursrc", "curchar", "curday" }) do
```

- [ ] **Step 4: Hide the currency widgets in the empty state**

In `HideAllCharts`, after the `self.zonePanel:Hide(); self.itemPanel:Hide(); self.itemValuePanel:Hide()` line, add:

```lua
  self.currencyPanel:Hide(); self.currencyStrip:Hide()
```

(The `for _, h in pairs(self.headers)` loop already hides all four currency headers; these lines cover the panel + strip.)

- [ ] **Step 5: Render the currency block**

In `LayoutCharts`, immediately **before** the `-- Ranked lists — two half-width columns:` comment (near the end), insert:

```lua
  -- ── Currency ──────────────────────────────────────────────────────────────────
  local ct = stats.currencyTotals or { distinct = 0, events = 0 }
  if ct.events and ct.events > 0 then
    -- Block title carries the highlights (distinct types + biggest single haul).
    local title = "Currency"
    if ct.distinct then title = title .. string.format("  \226\128\148  %d type%s", ct.distinct, ct.distinct == 1 and "" or "s") end
    if ct.biggestHaul then title = title .. string.format("  \226\128\148  biggest: %s +%d", ct.biggestHaul.name, ct.biggestHaul.quantity) end
    H.currencyTitle:SetText(title)
    H.currencyTitle:ClearAllPoints(); H.currencyTitle:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y); H.currencyTitle:Show()
    y = y - 22

    -- Top currencies by quantity (ranked list, full width).
    local curRows = {}
    for _, e in ipairs(sortedByCount(stats.byCurrency)) do
      curRows[#curRows + 1] = { name = e.key, right = tostring(e.count) }
    end
    local hCur = self:renderListPanel(P.curlist, self.currencyPanel, curRows, y, w - pad * 2, pad, 70)
    y = y - hCur - SECTION_GAP

    -- Currency by source: one stacked bar per currency, segments coloured by source.
    local curMax = 1
    for _, total in pairs(stats.byCurrency) do if total > curMax then curMax = total end end
    local stackRows = {}
    for _, e in ipairs(sortedByCount(stats.byCurrency)) do
      local perSrc = stats.currencySourceMatrix[e.key] or {}
      local order = {}
      for srcKey in pairs(perSrc) do order[#order + 1] = srcKey end
      table.sort(order, function(a, b) return (perSrc[a] or 0) > (perSrc[b] or 0) end)
      local segs = {}
      for _, srcKey in ipairs(order) do
        segs[#segs + 1] = { frac = (perSrc[srcKey] or 0) / curMax, color = SOURCE_COLOR[srcKey] or NEUTRAL }
      end
      stackRows[#stackRows + 1] = { label = e.key, value = tostring(e.count), segments = segs }
    end
    y = self:renderStackedBarSection(P.cursrc, H.currencySrc, stackRows, y, w, pad)

    -- Currency by character (class-coloured bars).
    local ccList, ccMax = {}, 1
    for _, ce in pairs(stats.currencyByChar) do
      ccList[#ccList + 1] = ce
      if ce.quantity > ccMax then ccMax = ce.quantity end
    end
    table.sort(ccList, function(a, b)
      if a.quantity ~= b.quantity then return a.quantity > b.quantity end
      return a.char < b.char
    end)
    local ccRows = {}
    for _, ce in ipairs(ccList) do
      ccRows[#ccRows + 1] = { label = shortChar(ce.char), color = classColor(ce.classFile),
        frac = ce.quantity / ccMax, value = tostring(ce.quantity) }
    end
    y = self:renderBarSection(P.curchar, H.currencyChar, ccRows, y, w, pad)

    -- Currency over time (per-day strip of total currency quantity).
    local ckeys = dayKeyList(stats.totals.firstTs, stats.totals.lastTs)
    local curDayB = {}
    for _, k in ipairs(ckeys) do
      local c = stats.currencyByDay[k] or 0
      curDayB[#curDayB + 1] = { info = k .. ":  " .. c, count = c, label = shortDay(k) }
    end
    y = self:renderStrip(P.curday, H.currencyTime, self.currencyStrip, curDayB, y, w, pad)
  else
    self.currencyPanel:Hide(); self.currencyStrip:Hide()
  end
```

- [ ] **Step 6: Verify it loads clean**

Run: `luacheck . 2>&1 | tail -2 && lua tests/run.lua 2>&1 | tail -2`
Expected: luacheck 0/0; all existing tests still pass (Analytics render isn't unit-tested, but the module must load without syntax/global errors).

- [ ] **Step 7: Commit**

```bash
git add modules/Analytics.lua
git commit -m "feat(currency): Insights currency block (top/by-source/by-char/over-time)"
```

---

### Task 7: History table null-safety for currency

**Files:**
- Modify: `modules/BrowserTable.lua` (quality cell + group-by-quality label)
- Test: `tests/test_browsertable.lua`

**Interfaces:**
- Guarantees: the `quality` column `valueFn` returns `""` for a currency row (nil quality), not a misleading "Poor". Grouping by quality labels currency rows with an empty/`Currency` bucket rather than "Poor".

- [ ] **Step 1: Write the failing test**

In `tests/test_browsertable.lua`, add:

```lua
test("BrowserTable: quality column is blank for a currency row", function()
  local colByKey = {}
  for _, c in ipairs(NS.BrowserTable.COLUMNS) do colByKey[c.key] = c end
  local currencyRow = { currencyID = 3008, itemName = "Valorstones", itemType = "Currency", quantity = 40 }
  local itemRow = { itemID = 111, itemName = "Sword", quality = 4 }
  assertEqual(colByKey.quality.valueFn(currencyRow), "")           -- no misleading "Poor"
  assertEqual(colByKey.quality.valueFn(itemRow), NS.Compat.QualityLabel(4))
  assertEqual(colByKey.type.valueFn(currencyRow), "Currency")      -- Type filter works
end)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -E "blank for a currency|FAIL"`
Expected: FAIL — `valueFn(currencyRow)` returns `"Poor"`, not `""`.

- [ ] **Step 3: Make the quality cell null-safe**

In `modules/BrowserTable.lua`, in `BrowserTable.COLUMNS`, change the `quality` column's `valueFn` from:

```lua
    valueFn = function(r) return NS.Compat.QualityLabel(r.quality) end,
```

to:

```lua
    valueFn = function(r) return r.quality ~= nil and NS.Compat.QualityLabel(r.quality) or "" end,
```

- [ ] **Step 4: Guard the group-by-quality label**

In `modules/BrowserTable.lua`, in the group-label logic (search for `elseif groupBy == "quality" then`), change:

```lua
    label = NS.Compat.QualityLabel(r.quality); raw = "q" .. tostring(r.quality or 0)
```

to:

```lua
    label = r.quality ~= nil and NS.Compat.QualityLabel(r.quality) or "\226\128\148"; raw = "q" .. tostring(r.quality or "-")
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `lua tests/run.lua 2>&1 | tail -2 && luacheck . 2>&1 | tail -2`
Expected: all pass; luacheck clean.

- [ ] **Step 6: Commit**

```bash
git add modules/BrowserTable.lua tests/test_browsertable.lua
git commit -m "feat(currency): null-safe quality cell for currency rows"
```

---

### Task 8: CSV export — currency column + Insights sections

**Files:**
- Modify: `modules/Export.lua` (`currencyID` column, null-safe quality cell, `AI_COLUMNS` exclusion, currency Insights CSV sections, `TODO(currency-ai)`)
- Test: `tests/test_export.lua`

**Interfaces:**
- Guarantees: `E:CSV` includes a `currencyID` column and blanks the `quality` label for currency rows; `E:AICSV` omits `currencyID`; `E:InsightsCSV` emits `Currency Collected`, `Currency by Source` (one row per currency×source), `Currency by Character`, `Currency by Day`, and `Summary` rows for `Distinct currencies` + `Biggest haul`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_export.lua`, add:

```lua
test("Export: CSV emits a currency row with currencyID and blank item cells", function()
  local rows = { { ts = 1000, char = "A-R", currencyID = 3008, itemName = "Valorstones",
                   itemType = "Currency", itemSubType = "The War Within", quantity = 40,
                   source = "MPLUS", zone = "Z1" } }
  local csv = NS.Export:CSV(rows)
  local header = csv:match("^[^\r\n]+")
  assertTrue(header:find("currencyID", 1, true) ~= nil, "header has currencyID column")
  local dataLine = select(3, csv:find("\r\n(.-)\r\n"))
  assertTrue(csv:find(",3008,", 1, true) ~= nil or csv:find(",3008\r", 1, true) ~= nil, "currencyID value present")
  assertTrue(csv:find("Valorstones", 1, true) ~= nil, "currency name present")
  -- quality label must be blank (not "Poor") for the currency row
  assertTrue(csv:find(",Poor,", 1, true) == nil, "no misleading Poor quality for currency")
end)

test("Export: AICSV omits the currencyID column", function()
  local csv = NS.Export:AICSV({ { ts = 1, itemID = 1, itemName = "x", quantity = 1, source = "KILL" } })
  local header = csv:match("^[^\r\n]+")
  assertTrue(header:find("currencyID", 1, true) == nil, "AI CSV must not carry currencyID")
end)

test("Export: InsightsCSV includes currency sections", function()
  local stats = {
    totals = { records = 0 },
    byCurrency = { Valorstones = 50 },
    currencySourceMatrix = { Valorstones = { MPLUS = 40, QUEST = 10 } },
    currencyByChar = { ["A-R"] = { char = "A-R", quantity = 43 } },
    currencyByDay = { ["2026-07-21"] = 53 },
    currencyTotals = { distinct = 1, events = 2, biggestHaul = { name = "Valorstones", quantity = 40 } },
  }
  local csv = NS.Export:InsightsCSV(stats)
  assertTrue(csv:find("Currency Collected,Valorstones,50", 1, true) ~= nil, "top currencies row")
  assertTrue(csv:find("Currency by Source,Valorstones / MPLUS,40", 1, true) ~= nil, "currency x source row")
  assertTrue(csv:find("Distinct currencies", 1, true) ~= nil, "summary distinct row")
  assertTrue(csv:find("Biggest haul", 1, true) ~= nil, "summary biggest-haul row")
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `lua tests/run.lua 2>&1 | grep -E "currency row with currencyID|AICSV omits|InsightsCSV includes currency|FAIL"`
Expected: FAILs (no currencyID column; no currency sections).

- [ ] **Step 3: Add the `currencyID` column + null-safe quality cell to `COLUMNS`**

In `modules/Export.lua`, in the `COLUMNS` table, change the `quality` row from:

```lua
  { "quality",      function(r) return NS.Compat.QualityLabel(r.quality) end },
```

to:

```lua
  { "quality",      function(r) return r.quality ~= nil and NS.Compat.QualityLabel(r.quality) or "" end },
```

And add a `currencyID` column right after the `itemID` column:

```lua
  { "currencyID",   function(r) return r.currencyID end },
```

- [ ] **Step 4: Exclude `currencyID` from the AI column set**

In `modules/Export.lua`, in the `AI_COLUMNS` build loop, change:

```lua
for _, c in ipairs(COLUMNS) do
  if not c[1]:find("^auc_") then
```

to also drop `currencyID` (AI export is deferred — see the design's §10):

```lua
-- TODO(currency-ai): teach ai-export-guideline.md + the report template about currency rows, then
-- stop excluding currencyID here so Export-to-AI can carry currency. Until then the AI path is
-- item-only and its output is unchanged by this feature.
for _, c in ipairs(COLUMNS) do
  if not c[1]:find("^auc_") and c[1] ~= "currencyID" then
```

- [ ] **Step 5: Add the currency sections to `InsightsCSV`**

In `modules/Export.lua`, in `E:InsightsCSV`, immediately before the final `return table.concat(lines, "\r\n") .. "\r\n"`, add:

```lua
  -- Currency (issue: currency capture). Top currencies by quantity, then one row per currency×source,
  -- then per-character and per-day, plus the highlight summary rows.
  section("Currency Collected", rankedRows(stats.byCurrency))
  local matrix = stats.currencySourceMatrix or {}
  local curNames = {}
  for cname in pairs(matrix) do curNames[#curNames + 1] = cname end
  table.sort(curNames)
  for _, cname in ipairs(curNames) do
    local perSrc, srcs = matrix[cname], {}
    for s in pairs(perSrc) do srcs[#srcs + 1] = s end
    table.sort(srcs, function(a, b) return (perSrc[a] or 0) > (perSrc[b] or 0) end)
    for _, s in ipairs(srcs) do
      row("Currency by Source", cname .. " / " .. (NS.Constants.SourceLabel[s] or s), perSrc[s])
    end
  end
  local curCharRows = {}
  for _, ce in pairs(stats.currencyByChar or {}) do
    curCharRows[#curCharRows + 1] = { label = ce.char, count = ce.quantity }
  end
  table.sort(curCharRows, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return tostring(a.label) < tostring(b.label)
  end)
  section("Currency by Character", curCharRows)
  local curDayKeys = {}
  for day in pairs(stats.currencyByDay or {}) do curDayKeys[#curDayKeys + 1] = day end
  table.sort(curDayKeys)
  for _, day in ipairs(curDayKeys) do row("Currency by Day", day, stats.currencyByDay[day]) end
  local ctot = stats.currencyTotals or {}
  row("Summary", "Distinct currencies", ctot.distinct or 0)
  if ctot.biggestHaul then
    row("Summary", "Biggest haul", ctot.biggestHaul.name .. " +" .. ctot.biggestHaul.quantity)
  end
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `lua tests/run.lua 2>&1 | tail -2 && luacheck . 2>&1 | tail -2`
Expected: all pass; luacheck clean.

- [ ] **Step 7: Commit**

```bash
git add modules/Export.lua tests/test_export.lua
git commit -m "feat(currency): CSV export (currencyID column + Insights sections)"
```

---

### Task 9: Docs, scope reversal, smoke tests, test badge

**Files:**
- Modify: `docs/scope.md` (currency in-scope; gold + AI deferred)
- Modify: `docs/attribution.md` (currency capture path)
- Modify: `docs/data-model.md` (record shape + Type=Currency note)
- Modify: `docs/smoke-tests.md` (currency smoke test)
- Modify: `docs/test-cases.md` (regenerate)
- Modify: `README.md` (test badge count only)

**Interfaces:** none (docs).

- [ ] **Step 1: Reverse the scope decision**

In `docs/scope.md`, under `## Out of scope`, change the `**Gold and currencies.**` bullet from:

```markdown
- **Gold and currencies.** Capture is scoped to items (anything with an itemID). Tracking currency or money is out.
```

to:

```markdown
- **Gold.** Capture of looted money (copper) is out — high-frequency and its-own-value, better modelled as aggregated Insights tallies than per-drop rows. See the deferred design.
```

Then add, under the `## Passive capture`/in-scope list (after the source-attribution bullet), a currency bullet:

```markdown
- **Currency capture** (Valorstones, crests, etc.) as `Type=Currency` history rows — attributed to the same sources as items, obeying the per-source mute list and a `Record currency` master toggle, but exempt from the quality/quest gates. Surfaced in the History table, a dedicated Insights currency block, and CSV export. Export-to-AI for currency is deferred. (This reverses the earlier "currencies out of scope" decision — ratified 2026-07-21.)
```

- [ ] **Step 2: Document the capture path**

In `docs/attribution.md`, after the "Self-identifying loot lines" / "Roll wins" additions near the top, add a short paragraph:

```markdown
### Currency

Currency rides a parallel signal: `CHAT_MSG_CURRENCY` → `Collector:OnChatMsgCurrency` →
`Util.ParseSelfCurrency`. It reuses the **same peripheral context** as items (`Attribution:Consume`)
for its source, since currency is delivered inside the same loot window. Currency records carry
`currencyID` + `itemType = "Currency"` (never an `itemID`), take a slimmer gate (the `recordCurrency`
master toggle + the per-source mute list; no quality/quest/blacklist gate), and are stored in the same
`global.history` array. See [data-model.md](data-model.md) and the currency-capture spec.
```

- [ ] **Step 3: Note the record shape in data-model.md**

In `docs/data-model.md`, after the SourceType block, add a short note:

```markdown
### Currency records

A currency loot is stored as a history record with `currencyID` (the structural signal),
`itemType = "Currency"`, `itemSubType = <live currency category>`, `itemName` (currency name) and
`quantity`; all item-only fields (`itemID`, `itemLink`, `quality`, `itemLevel`, `bound`, prices) are
nil. `itemID == nil && currencyID ~= nil` distinguishes a currency row. Currency is excluded from the
item-centric Insights charts (quality/ilvl/bound/top-items/value) but counts in the activity charts
(by source/day/character) and drives its own currency Insights sections.
```

- [ ] **Step 4: Add the currency smoke test**

In `docs/smoke-tests.md`, in the source-attribution table (the one whose rows end with the Roll/Craft/Refund entries added earlier), append:

```markdown
| 12 | Loot currency (M+ chest, world quest, PvP, etc.) with **Record currency** on | **Currency** row, `Type=Currency`, source from context | CERTAIN |
```

And after that section's **Pass.** notes, add:

```markdown
- With debug on (§12), a currency loot logs `[Currency] <name> x<n> id=<id> src=<source>` and adds a
  `Type=Currency` row (blank iLvl/Bound/Quality/Vendor/AH cells; the Type filter isolates it). Turning
  off **Record currency** stops new currency rows; muting a source stops that source's currency too.
  The Insights tab shows a **Currency** block (top currencies, currency-by-source stacked bars,
  currency-by-character, currency-over-time). §F-010: verify the currency **category** (SubType) reads
  a real header like "The War Within" — if it's blank, `Compat.CurrencyCategory` couldn't resolve the
  currency-list headers on this client and needs a look.
```

- [ ] **Step 5: Regenerate the test inventory + bump the badge**

Run: `lua tests/run.lua --list > docs/test-cases.md`

Then read the new total from the last line of `docs/test-cases.md` (the `| **Total** | **<n>** |` row) and update `README.md`: change the `![Tests](https://img.shields.io/badge/Tests-<old>%2F<old>_passing-green)` badge so both numbers equal `<n>`.

- [ ] **Step 6: Final verification**

Run: `lua tests/run.lua 2>&1 | tail -2 && luacheck . 2>&1 | tail -2`
Expected: all pass; luacheck 0/0. Confirm the README badge number equals the `--list` total.

- [ ] **Step 7: Commit**

```bash
git add docs/scope.md docs/attribution.md docs/data-model.md docs/smoke-tests.md docs/test-cases.md README.md
git commit -m "docs(currency): scope reversal, capture docs, smoke tests, badge"
```

---

## Self-Review

**Spec coverage:**
- §2 data model → Tasks 3 (constant), 4 (record build). ✓
- §3 record shape → Global Constraints + Task 4. ✓
- §4 capture path (event/parse/compat/attribution/gate) → Tasks 1, 2, 4. ✓
- §5 gates → Task 4 (master toggle + source mute; skips quality/quest/blacklist). ✓
- §6 currency-aware Stats (exclusions + 5 aggregates) → Task 5. ✓
- §7 Insights block (cards/top/stacked-by-source/by-char/over-time) → Task 6. ✓
- §8 History table null-safety → Task 7. ✓
- §9 settings/schema → Task 3. ✓
- §10 Export (CSV currencyID + null-safe + AI exclusion + Insights sections + TODO) → Task 8. ✓
- §11 standards/scope reversal → Task 9. ✓
- §12 testing → tests folded into Tasks 1–8; regen/badge in Task 9. ✓
- §13 footprint → matches Task file lists. ✓

**Placeholder scan:** the only `TODO` is the intentional `TODO(currency-ai)` code marker (Task 8, a tracked deferral). No "TBD"/"implement later"/"add error handling" placeholders. ✓ Task 6 uses four dedicated currency headers (one per titled section) — no header reuse hacks.

**Type consistency:** `currencyID`, `itemType="Currency"` (`Constants.CURRENCY_TYPE`), `itemSubType`, `quantity`, and the stats keys `byCurrency` / `currencySourceMatrix` / `currencyByChar` / `currencyByDay` / `currencyTotals{distinct,events,biggestHaul{name,quantity}}` are used identically across Tasks 4→5→6→8. `ParseSelfCurrency(msg)->link,qty` and `GetCurrencyInfoFromLink(link)->id,name,icon` signatures match between producer and consumer tasks. ✓
