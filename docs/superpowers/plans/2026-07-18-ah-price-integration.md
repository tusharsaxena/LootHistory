# AH-Price Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture an auction-house price snapshot on every loot record (via a fall-through cascade over Auctionator → TSM → OribosExchange), derive a `value` (auction-or-vendor), and surface both through the browser, Insights, CSV, and AI export.

**Architecture:** A new presence-gated `NS.AuctionPrice` module owns the cascade and reads user settings (enable/order/TSM-key). `Collector:BuildRecord` writes `auctionPrice` + `priceSource` snapshots. `NS.Util.RecordValue(r) = auctionPrice or sellPrice` is the single derived-value definition consumed everywhere. Insights/exports switch their value math from `sellPrice` to `RecordValue`.

**Tech Stack:** Lua 5.1 (Ace3, headless test harness `tests/run.lua`), Python 3 stdlib (`tools/build_report.py`), luacheck.

## Global Constraints

- **Design spec:** `docs/superpowers/specs/2026-07-18-ah-price-integration-design.md` — authoritative; this plan implements it.
- **Point-in-time:** `auctionPrice`/`priceSource` are snapshots captured at loot, never recomputed. `value` is derived, never stored. No `schemaVersion` bump, no migration.
- **Field names (fixed):** `auctionPrice` (copper, per unit, number|nil), `priceSource` (string|nil, e.g. `"auctionator"`, `"tsm:dbmarket"`, `"oribos:market"`).
- **Cascade default order:** Auctionator → TSM → OribosExchange. RECrystallize and Auctioneer are excluded.
- **Third-party shims** live in `modules/AuctionPrice.lua`, presence-gated — NOT in `core/Compat.lua` (which stays Blizzard-API-only).
- **Schema-as-single-source:** every user setting is a `settings/Schema.lua` row mutated via `Schema:Set`; defaults duplicated in `defaults/Global.lua`; options in `core/Constants.lua`.
- **Hard rules:** never bump `## Version`; never auto-stage/commit outside the sanctioned per-task commit; account-wide storage only. Incremental auto-commit IS authorized for this feature (user grant) — commit once per task when green.
- **Verify before commit each task:** `lua tests/run.lua` (exit 0) AND `luacheck .` (0 errors). Python tasks also run `python3 -m pytest tools/tests/ -q` (or `python3 tools/tests/test_build_report.py`).
- **Test inventory:** after the final task, regenerate `docs/test-cases.md` (`lua tests/run.lua --list > docs/test-cases.md`) and bump the README `tests` badge count in the same commit.

---

## File Structure

**Create:**
- `modules/AuctionPrice.lua` — cascade + presence-gated provider shims + settings resolution. Publishes `NS.AuctionPrice`.
- `tests/test_auctionprice.lua` — cascade/gating/provenance unit tests.

**Modify:**
- `core/Util.lua` — add `Util.RecordValue`.
- `modules/Collector.lua` — capture `auctionPrice`/`priceSource` in `BuildRecord` + `OnChatMsgLoot`.
- `core/Database.lua` — `Export` allowlist + `Stats` value math via `RecordValue`.
- `core/Constants.lua` — `AUCTION_PRIORITY_OPTIONS`, `TSM_SOURCE_OPTIONS`.
- `defaults/Global.lua` — `settings.auction` defaults.
- `settings/Schema.lua` — auction rows (group `"Auction House Price"`).
- `settings/Panel.lua` — group-filter in `renderSchema` + register the new subcategory.
- `modules/BrowserTable.lua` — `auction` column + `NUMERIC_SORT` + test-data gen.
- `modules/Analytics.lua` — relabel vendor-value → value.
- `modules/Export.lua` — CSV columns + InsightsCSV label + `AIPrompt` framing.
- `tools/build_report.py` — `a`/`val`/`src` keys, value cross-check, PASS summary.
- `docs/ai-export-guideline.md` — data contract + value math + three-price section.
- `docs/ai-export-template.html` — `rowVal` value source, auction column, labels.
- `tests/run.lua` — register `modules/AuctionPrice.lua` (load list) + `test_auctionprice.lua` (suite list).
- The addon `.toc` file(s) — add `modules/AuctionPrice.lua` in load order (before `modules/Collector.lua`).
- `tests/test_stats.lua`, `tests/test_export.lua`, `tests/test_browsertable.lua`, `tools/tests/test_build_report.py` — coverage updates.
- `tests/wow_mock.lua` — (only if a shared provider stub is preferred; tests may inject globals locally instead).
- `docs/data-model.md`, `docs/ARCHITECTURE.md`, `docs/test-cases.md`, `README.md` — docs + inventory.

---

## Phase 0 — Foundations (helper, module, capture)

### Task 1: `Util.RecordValue` helper

**Files:**
- Modify: `core/Util.lua` (after `Util.FormatMoney`, ~line 71)
- Test: `tests/test_util.lua`

**Interfaces:**
- Produces: `NS.Util.RecordValue(record) -> number|nil` — returns `record.auctionPrice` if non-nil, else `record.sellPrice`, else `nil`.

- [ ] **Step 1: Write the failing test** — append to `tests/test_util.lua`:

```lua
test("Util: RecordValue prefers auctionPrice, falls back to sellPrice, else nil", function()
  assertEqual(NS.Util.RecordValue({ auctionPrice = 500, sellPrice = 10 }), 500)
  assertEqual(NS.Util.RecordValue({ sellPrice = 10 }), 10)
  assertEqual(NS.Util.RecordValue({ auctionPrice = 0, sellPrice = 10 }), 0) -- 0 is a real price, not nil
  assertEqual(NS.Util.RecordValue({}), nil)
end)
```

- [ ] **Step 2: Run to verify it fails**

Run: `lua tests/run.lua`
Expected: FAIL (attempt to call `RecordValue` (a nil value)).

- [ ] **Step 3: Implement** — in `core/Util.lua` after `Util.FormatMoney`:

```lua
-- Derived per-unit worth of a record: the auction price snapshot if we captured one,
-- else the vendor sell price, else nil. The single definition of "value" (never stored;
-- see docs/data-model.md). Note: 0 is a real captured price, so test against nil, not falsiness.
function Util.RecordValue(record)
  if record == nil then return nil end
  local a = record.auctionPrice
  if a ~= nil then return a end
  return record.sellPrice
end
```

- [ ] **Step 4: Run to verify it passes** — `lua tests/run.lua` → PASS; `luacheck .` → 0 errors.

- [ ] **Step 5: Commit**

```bash
git add core/Util.lua tests/test_util.lua
git commit -m "feat(value): add Util.RecordValue (auction-or-vendor derived value)"
```

---

### Task 2: `AuctionPrice` cascade module

**Files:**
- Create: `modules/AuctionPrice.lua`
- Modify: `tests/run.lua` (load list + suite list), the addon `.toc`
- Test: `tests/test_auctionprice.lua`

**Interfaces:**
- Consumes: `NS.db.global.settings.auction` (Task 4 supplies live defaults; until then the module tolerates a missing table by treating the feature as enabled with the default order).
- Produces: `NS.AuctionPrice:Lookup(itemLink, itemID) -> price:number|nil, sourceTag:string|nil`.

**Design notes (implement exactly):**
- Canonical provider order + tags: `auctionator` (1), `tsm` (2), `oribos` (3).
- Read settings via a local resolver `cfg()` returning `{ enabled, providers = { {id,enabled,priority,tag,fetch} … sorted }, tsmSource }`. Missing `settings.auction` ⇒ all enabled, canonical order, `tsmSource="dbmarket"`.
- Sort enabled providers by `(priority, canonicalIndex)` (ties broken by canonical index) for determinism.
- Each provider `fetch(itemLink, itemID, tsmSource) -> price|nil, tag|nil`, presence-gated, wrapped so a provider error never propagates.

- [ ] **Step 1: Write the failing test** — create `tests/test_auctionprice.lua`:

```lua
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- Provider globals are injected per-test and torn down so cases don't leak into each other.
local function withGlobals(g, fn)
  local saved = {}
  for k, v in pairs(g) do saved[k] = _G[k]; _G[k] = v end
  local ok, err = pcall(fn)
  for k in pairs(g) do _G[k] = saved[k] end
  if not ok then error(err, 0) end
end

local LINK = "|cffa335ee|Hitem:210501:::::::::::::|h[Test]|h|r"

-- Auctionator stub: returns a price only for itemID 210501.
local function auctionatorStub(price)
  return { Auctionator = { API = { v1 = {
    GetAuctionPriceByItemID = function(_, id) return id == 210501 and price or nil end,
    GetAuctionPriceByItemLink = function(_, _link) return price end,
  } } } }
end

test("AuctionPrice: Auctionator hit returns price + tag", function()
  withGlobals(auctionatorStub(1234), function()
    local p, tag = NS.AuctionPrice:Lookup(LINK, 210501)
    assertEqual(p, 1234)
    assertEqual(tag, "auctionator")
  end)
end)

test("AuctionPrice: falls through Auctionator(nil) to TSM", function()
  withGlobals({
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return nil end } } },
    TSM_API = {
      ToItemString = function(_link) return "i:210501" end,
      GetCustomPriceValue = function(key, itemStr)
        if key == "dbmarket" and itemStr == "i:210501" then return 5000 end
        return nil
      end,
    },
  }, function()
    local p, tag = NS.AuctionPrice:Lookup(LINK, 210501)
    assertEqual(p, 5000)
    assertEqual(tag, "tsm:dbmarket")
  end)
end)

test("AuctionPrice: falls through to OribosExchange", function()
  withGlobals({
    OEMarketInfo = function(_item, tbl) tbl.market = 777; tbl.region = 999 end,
  }, function()
    local p, tag = NS.AuctionPrice:Lookup(LINK, 210501)
    assertEqual(p, 777)
    assertEqual(tag, "oribos:market")
  end)
end)

test("AuctionPrice: no providers present returns nil, nil", function()
  local p, tag = NS.AuctionPrice:Lookup(LINK, 210501)
  assertEqual(p, nil)
  assertEqual(tag, nil)
end)

test("AuctionPrice: a provider that errors is skipped, not fatal", function()
  withGlobals({
    TSM_API = { ToItemString = function() error("boom") end, GetCustomPriceValue = function() end },
    OEMarketInfo = function(_item, tbl) tbl.market = 42 end,
  }, function()
    local p, tag = NS.AuctionPrice:Lookup(LINK, 210501)
    assertEqual(p, 42)
    assertEqual(tag, "oribos:market")
  end)
end)

test("AuctionPrice: disabled master switch returns nil", function()
  NS.db.global.settings.auction = { enabled = false }
  withGlobals(auctionatorStub(1234), function()
    local p = NS.AuctionPrice:Lookup(LINK, 210501)
    assertEqual(p, nil)
  end)
  NS.db.global.settings.auction = nil
end)

test("AuctionPrice: priority reorder puts TSM first", function()
  NS.db.global.settings.auction = {
    enabled = true, tsmSource = "dbmarket",
    auctionator = true, tsm = true, oribos = true,
    priorityAuctionator = 2, priorityTSM = 1, priorityOribos = 3,
  }
  withGlobals({
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return 111 end } } },
    TSM_API = { ToItemString = function() return "i:1" end, GetCustomPriceValue = function() return 222 end },
  }, function()
    local p, tag = NS.AuctionPrice:Lookup(LINK, 210501)
    assertEqual(p, 222)
    assertEqual(tag, "tsm:dbmarket")
  end)
  NS.db.global.settings.auction = nil
end)
```

- [ ] **Step 2: Register the module and suite** — in `tests/run.lua`, add `"modules/AuctionPrice.lua",` to the `Loader.loadAll` list **before** `"modules/Collector.lua"`, and add `"test_auctionprice.lua",` to `SUITE_FILES`.

- [ ] **Step 3: Run to verify it fails**

Run: `lua tests/run.lua`
Expected: FAIL (`NS.AuctionPrice` is nil / cannot index).

- [ ] **Step 4: Implement** — create `modules/AuctionPrice.lua`:

```lua
local addonName, NS = ...   -- luacheck: ignore addonName
NS.AuctionPrice = NS.AuctionPrice or {}
local AuctionPrice = NS.AuctionPrice

-- Reads AH price for a just-looted item from installed pricing addons, in a user-configurable
-- fall-through cascade (Auctionator -> TSM -> OribosExchange by default). Third-party integration
-- boundary — presence-gated here, deliberately NOT in core/Compat.lua (Blizzard-API-only). Every
-- provider call is wrapped so a broken/absent addon degrades to nil and the cascade continues.
-- Returns copper price + a compact provenance tag; both nil when no enabled provider has a price.

-- ── Provider fetchers (each: (itemLink, itemID, tsmSource) -> price|nil, tag|nil) ──
local function fetchAuctionator(itemLink, itemID)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not api then return nil end
  local price
  if itemID and api.GetAuctionPriceByItemID then
    price = api.GetAuctionPriceByItemID(addonName, itemID)
  elseif itemLink and api.GetAuctionPriceByItemLink then
    price = api.GetAuctionPriceByItemLink(addonName, itemLink)
  end
  if price then return price, "auctionator" end
  return nil
end

local function fetchTSM(itemLink, _itemID, tsmSource)
  if not (TSM_API and TSM_API.GetCustomPriceValue and TSM_API.ToItemString) then return nil end
  local key = tsmSource or "dbmarket"
  local itemStr = TSM_API.ToItemString(itemLink)
  if not itemStr then return nil end
  local price = TSM_API.GetCustomPriceValue(key, itemStr)
  if price and price > 0 then return price, "tsm:" .. key end
  return nil
end

local function fetchOribos(itemLink, itemID)
  if type(OEMarketInfo) ~= "function" then return nil end
  local info = {}
  OEMarketInfo(itemLink or itemID, info)
  if info.market and info.market > 0 then return info.market, "oribos:market" end
  if info.region and info.region > 0 then return info.region, "oribos:region" end
  return nil
end

-- Canonical providers (order = install-base default). settingKey/priorityKey index settings.auction.
local PROVIDERS = {
  { id = "auctionator", settingKey = "auctionator", priorityKey = "priorityAuctionator", fetch = fetchAuctionator },
  { id = "tsm",         settingKey = "tsm",         priorityKey = "priorityTSM",         fetch = fetchTSM },
  { id = "oribos",      settingKey = "oribos",      priorityKey = "priorityOribos",      fetch = fetchOribos },
}

-- Resolve live settings into an ordered, enabled provider list. Missing settings.auction ⇒
-- feature on, canonical order, dbmarket.
local function resolve()
  local s = NS.db and NS.db.global and NS.db.global.settings and NS.db.global.settings.auction
  if s and s.enabled == false then return nil end
  local tsmSource = (s and s.tsmSource) or "dbmarket"
  local list = {}
  for i, p in ipairs(PROVIDERS) do
    local enabled = not s or s[p.settingKey] ~= false     -- default enabled
    if enabled then
      local priority = (s and tonumber(s[p.priorityKey])) or i
      list[#list + 1] = { fetch = p.fetch, priority = priority, canon = i }
    end
  end
  table.sort(list, function(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.canon < b.canon
  end)
  return list, tsmSource
end

-- Public: first enabled provider (in priority order) that returns a price wins.
function AuctionPrice:Lookup(itemLink, itemID)
  local list, tsmSource = resolve()
  if not list then return nil, nil end
  for _, p in ipairs(list) do
    local ok, price, tag = pcall(p.fetch, itemLink, itemID, tsmSource)
    if ok and price then return price, tag end
  end
  return nil, nil
end
```

- [ ] **Step 5: Run to verify it passes** — `lua tests/run.lua` → PASS; `luacheck .` → 0 errors.

- [ ] **Step 6: Add to the TOC** — open the addon `.toc` file (repo root, e.g. `LootHistory.toc` / `LootHistory_Mainline.toc`) and add `modules/AuctionPrice.lua` on its own line **before** `modules/Collector.lua`. (If multiple TOCs exist, update each.)

- [ ] **Step 7: Commit**

```bash
git add modules/AuctionPrice.lua tests/test_auctionprice.lua tests/run.lua *.toc
git commit -m "feat(auction): add AuctionPrice cascade module (Auctionator/TSM/Oribos)"
```

---

### Task 3: Capture auctionPrice at loot + export allowlist

**Files:**
- Modify: `modules/Collector.lua:41-63` (`BuildRecord`), `modules/Collector.lua:99-107` (`OnChatMsgLoot`)
- Modify: `core/Database.lua:161-168` (`Export` allowlist)
- Test: `tests/test_collector.lua`

**Interfaces:**
- Consumes: `NS.AuctionPrice:Lookup` (Task 2), `env.auctionPrice`, `env.priceSource`.
- Produces: records carry `auctionPrice`, `priceSource`.

- [ ] **Step 1: Write the failing test** — append to `tests/test_collector.lua`:

```lua
test("Collector: BuildRecord carries auctionPrice + priceSource from env", function()
  local rec = NS.Collector:BuildRecord("[Link]", 2,
    { source = "KILL", confidence = "CERTAIN" },
    { ts = 1, sellPrice = 10, auctionPrice = 500, priceSource = "tsm:dbmarket" })
  assertEqual(rec.auctionPrice, 500)
  assertEqual(rec.priceSource, "tsm:dbmarket")
  assertEqual(rec.sellPrice, 10)
end)
```

- [ ] **Step 2: Run to verify it fails** — `lua tests/run.lua` → FAIL (`rec.auctionPrice` is nil).

- [ ] **Step 3: Implement `BuildRecord`** — in `modules/Collector.lua`, add two fields to the returned table (after the `sellPrice` line, keeping alignment):

```lua
    sellPrice    = env.sellPrice,   -- vendor sell price (copper, per unit)
    auctionPrice = env.auctionPrice, -- AH price snapshot (copper, per unit); nil if no provider
    priceSource  = env.priceSource,  -- provenance tag, e.g. "tsm:dbmarket"; nil if no price
```

- [ ] **Step 4: Wire the lookup in `OnChatMsgLoot`** — in `modules/Collector.lua`, after the `GetItemExtras` line (~99) add the lookup, and pass both fields into the env table:

```lua
  local itemLevel, bound, sellPrice, itemType, itemSubType = NS.Compat.GetItemExtras(link)
  local auctionPrice, priceSource = NS.AuctionPrice:Lookup(link, itemID)
  local zone, subzone = NS.Compat.GetZone()
  local classFile = select(2, UnitClass("player"))
  local record = self:BuildRecord(link, qty,
    { source = source, sourceDetail = sourceDetail, confidence = confidence },
    { ts = time(), char = NS.Util.PlayerKey(), classFile = classFile,
      itemID = itemID, itemName = itemName, quality = quality, itemLevel = itemLevel, bound = bound,
      sellPrice = sellPrice, auctionPrice = auctionPrice, priceSource = priceSource,
      itemType = itemType, itemSubType = itemSubType,
      zone = zone, mapID = NS.Compat.GetPlayerMapID(), subzone = subzone })
```

- [ ] **Step 5: Add to Export allowlist** — in `core/Database.lua:Export`, add the two fields to the copied record (beside `sellPrice`):

```lua
      sellPrice = r.sellPrice, auctionPrice = r.auctionPrice, priceSource = r.priceSource,
      itemType = r.itemType, itemSubType = r.itemSubType,
```

- [ ] **Step 6: Run to verify it passes** — `lua tests/run.lua` → PASS; `luacheck .` → 0 errors.

- [ ] **Step 7: Commit**

```bash
git add modules/Collector.lua core/Database.lua tests/test_collector.lua
git commit -m "feat(auction): capture auctionPrice/priceSource at loot + export them"
```

---

## Phase 1 — Settings (schema, defaults, panel sub-page)

### Task 4: Constants, defaults, and Schema rows

**Files:**
- Modify: `core/Constants.lua` (after the existing `_OPTIONS` blocks)
- Modify: `defaults/Global.lua:19-27` (`settings` table)
- Modify: `settings/Schema.lua` (append rows before the closing `}` of `S.Schema`)
- Test: `tests/test_schema.lua`

**Interfaces:**
- Produces: settings paths `settings.auction.enabled`, `.auctionator`, `.tsm`, `.oribos`, `.priorityAuctionator`, `.priorityTSM`, `.priorityOribos`, `.tsmSource`; constants `C.AUCTION_PRIORITY_OPTIONS`, `C.TSM_SOURCE_OPTIONS`.

- [ ] **Step 1: Write the failing test** — append to `tests/test_schema.lua`:

```lua
test("Schema: auction rows exist with the Auction House Price group and defaults", function()
  local NS2 = NS
  local row = NS2.Schema:FindRow("settings.auction.enabled")
  assertTrue(row ~= nil, "settings.auction.enabled row missing")
  assertEqual(row.group, "Auction House Price")
  assertEqual(NS2.Schema:Default("settings.auction.enabled"), true)
  assertEqual(NS2.Schema:Default("settings.auction.tsmSource"), "dbmarket")
  assertEqual(NS2.Schema:Default("settings.auction.priorityTSM"), 2)
end)
```

- [ ] **Step 2: Run to verify it fails** — `lua tests/run.lua` → FAIL (row nil).

- [ ] **Step 3: Add constants** — in `core/Constants.lua`, after the existing option blocks:

```lua
-- Auction cascade priority slots (1 = probed first).
C.AUCTION_PRIORITY_OPTIONS = {
  { value = 1, label = "1st" }, { value = 2, label = "2nd" }, { value = 3, label = "3rd" },
}
-- TSM price sources exposed to GetCustomPriceValue (see docs/ai-export-guideline.md / TSM docs).
C.TSM_SOURCE_OPTIONS = {
  { value = "dbmarket",          label = "Market value (dbmarket)" },
  { value = "dbminbuyout",       label = "Min buyout (dbminbuyout)" },
  { value = "dbregionmarketavg", label = "Region market avg (dbregionmarketavg)" },
  { value = "dbhistorical",      label = "Historical (dbhistorical)" },
}
```

- [ ] **Step 4: Add defaults** — in `defaults/Global.lua`, inside the `settings = { … }` table (after `window = {}`):

```lua
    window           = {},     -- persisted position/size
    auction = {                -- AH-price cascade (see modules/AuctionPrice.lua)
      enabled = true,
      auctionator = true, tsm = true, oribos = true,
      priorityAuctionator = 1, priorityTSM = 2, priorityOribos = 3,
      tsmSource = "dbmarket",
    },
```

- [ ] **Step 5: Add Schema rows** — in `settings/Schema.lua`, insert before the closing `}` of `S.Schema` (after the `excludedSources` row):

```lua
  -- ── Auction House Price ──  (own settings sub-page; see settings/Panel.lua)
  { path = "settings.auction.enabled", default = true, type = "boolean", widget = "CheckBox",
    group = "Auction House Price", label = "Enable AH pricing",
    tooltip = "Record an auction-house price on each loot, read from installed pricing addons." },
  { path = "settings.auction.tsmSource", default = "dbmarket", type = "string", widget = "Dropdown",
    group = "Auction House Price", label = "TSM price source", options = C.TSM_SOURCE_OPTIONS,
    tooltip = "Which TSM price the cascade requests when it reaches TSM." },

  { path = "settings.auction.auctionator", default = true, type = "boolean", widget = "CheckBox",
    group = "Auction House Price", label = "Use Auctionator",
    tooltip = "Include Auctionator in the price cascade." },
  { path = "settings.auction.priorityAuctionator", default = 1, type = "number", widget = "Dropdown",
    group = "Auction House Price", label = "Auctionator priority", options = C.AUCTION_PRIORITY_OPTIONS,
    tooltip = "Cascade position for Auctionator (1 = probed first)." },

  { path = "settings.auction.tsm", default = true, type = "boolean", widget = "CheckBox",
    group = "Auction House Price", label = "Use TSM",
    tooltip = "Include TradeSkillMaster in the price cascade." },
  { path = "settings.auction.priorityTSM", default = 2, type = "number", widget = "Dropdown",
    group = "Auction House Price", label = "TSM priority", options = C.AUCTION_PRIORITY_OPTIONS,
    tooltip = "Cascade position for TSM (1 = probed first)." },

  { path = "settings.auction.oribos", default = true, type = "boolean", widget = "CheckBox",
    group = "Auction House Price", label = "Use OribosExchange",
    tooltip = "Include OribosExchange in the price cascade." },
  { path = "settings.auction.priorityOribos", default = 3, type = "number", widget = "Dropdown",
    group = "Auction House Price", label = "OribosExchange priority", options = C.AUCTION_PRIORITY_OPTIONS,
    tooltip = "Cascade position for OribosExchange (1 = probed first)." },
```

- [ ] **Step 6: Run to verify it passes** — `lua tests/run.lua` → PASS (`S:Register` prints no "missing default"); `luacheck .` → 0 errors.

- [ ] **Step 7: Commit**

```bash
git add core/Constants.lua defaults/Global.lua settings/Schema.lua tests/test_schema.lua
git commit -m "feat(settings): auction cascade schema rows, defaults, constants"
```

---

### Task 5: Panel — dedicated "Auction House Price" subcategory

**Files:**
- Modify: `settings/Panel.lua` (`renderSchema` ~297-330; registration ~594-647)

**Interfaces:**
- Consumes: schema rows with `group == "Auction House Price"` (Task 4).
- Produces: a new settings subcategory rendering only the auction group; the General subcategory no longer shows it.

**Design:** add an optional `opts` arg to `renderSchema(ctx, companions, opts)` where `opts.only` (string) renders only that group and `opts.skip` (set) skips groups. General passes `{ skip = { ["Auction House Price"] = true } }`; the new subcategory passes `{ only = "Auction House Price" }`.

- [ ] **Step 1: Add filtering to `renderSchema`** — change the signature and the loop guard:

```lua
local function renderSchema(ctx, companions, opts)
  opts = opts or {}
  local scroll = ensureScroll(ctx)
  local pendingRow
  -- … (flushRow / startRow unchanged) …

  for _, row in ipairs(NS.Schema.Schema) do
    if opts.only and row.group ~= opts.only then goto continue end
    if opts.skip and row.group and opts.skip[row.group] then goto continue end
    if row.group and row.group ~= ctx.lastGroup then
      flushRow(); section(ctx, row.group); ctx.lastGroup = row.group
    end
    -- … (existing per-row widget dispatch unchanged) …
    ::continue::
  end
  -- … (trailing flushRow unchanged) …
end
```

(If the existing loop body isn't `goto`-friendly, wrap the per-row body in `if include then … end` instead — `local include = not ((opts.only and row.group ~= opts.only) or (opts.skip and row.group and opts.skip[row.group]))`.)

- [ ] **Step 2: Skip the auction group in General** — in the General `OnShow` (~604), pass the skip option to the existing `renderSchema(ctx, { … })` call:

```lua
      renderSchema(ctx, {
        ["settings.windowScale"] = function(parentRow) … end,   -- unchanged companion
      }, { skip = { ["Auction House Price"] = true } })
```

- [ ] **Step 3: Register the new subcategory** — after the Filters subcategory block (~647), add:

```lua
  -- Auction House Price subcategory = the AH-price cascade settings (own page).
  local actx = createPanel("LootHistoryAuctionPanel", "Auction House Price", { defaultsButton = true })
  P.auction = actx
  if actx.panel.defaultsBtn then
    actx.panel.defaultsBtn:SetCallback("OnClick", function()
      for _, r in ipairs(NS.Schema.Schema) do
        if r.group == "Auction House Price" then NS.Schema:Set(r.path, NS.Schema:Default(r.path)) end
      end
      for _, fn in ipairs(actx.refreshers) do pcall(fn) end
    end)
  end
  local aRendered = false
  actx.panel:SetScript("OnShow", function()
    if not aRendered then
      aRendered = true
      renderSchema(actx, nil, { only = "Auction House Price" })
      if actx.scroll and actx.scroll.DoLayout then actx.scroll:DoLayout() end
    end
    for _, fn in ipairs(actx.refreshers) do pcall(fn) end
  end)
  Settings.RegisterCanvasLayoutSubcategory(mainCategory, actx.panel, "Auction House Price")
```

- [ ] **Step 4: Verify** — `luacheck .` → 0 errors; `lua tests/run.lua` → PASS (Panel is smoke-tested in-game, not unit-tested; ensure no load error). In-game smoke: `/lh config` → confirm an "Auction House Price" sub-page appears with 8 controls, and the General page no longer lists them.

- [ ] **Step 5: Commit**

```bash
git add settings/Panel.lua
git commit -m "feat(settings): render auction settings on their own sub-page"
```

---

## Phase 2 — In-game browser

### Task 6: AH column + window width + test data

**Files:**
- Modify: `modules/BrowserTable.lua:166-176` (COLUMNS), `:197` (NUMERIC_SORT), `:365-385` (test-data gen)
- Test: `tests/test_browsertable.lua`

**Interfaces:**
- Consumes: `record.auctionPrice`, `NS.Util.FormatMoney`.
- Produces: a `"auction"` column between `vendor` and `char`.

- [ ] **Step 1: Write the failing test** — append to `tests/test_browsertable.lua`:

```lua
test("BrowserTable: auction column formats auctionPrice and sorts numerically", function()
  assertEqual(NS.BrowserTable:CellText("auction", { auctionPrice = 12345 }),
    NS.Util.FormatMoney(12345))
  assertEqual(NS.BrowserTable:CellText("auction", {}), "")   -- FormatMoney(nil) => ""
  -- column ordering: auction sits immediately before char (last), after vendor.
  local keys = {}
  for _, c in ipairs(NS.BrowserTable.COLUMNS) do keys[#keys + 1] = c.key end
  local vi, ai, ci
  for i, k in ipairs(keys) do
    if k == "vendor" then vi = i elseif k == "auction" then ai = i elseif k == "char" then ci = i end
  end
  assertTrue(vi and ai and ci and vi < ai and ai < ci, "expected vendor < auction < char")
end)
```

- [ ] **Step 2: Run to verify it fails** — `lua tests/run.lua` → FAIL (`CellText("auction", …)` returns "").

- [ ] **Step 3: Insert the column** — in `modules/BrowserTable.lua`, between the `vendor` entry and the `char` entry:

```lua
  { key = "vendor", label = "Vendor", width = 72, align = "RIGHT",
    desc = "Vendor sell price per unit.",
    valueFn = function(r) return NS.Util.FormatMoney(r.sellPrice) end,
    sortFn = function(r) return r.sellPrice or 0 end },
  { key = "auction", label = "AH", width = 72, align = "RIGHT",
    desc = "Auction-house price per unit at loot time (from your AH pricing addon).",
    valueFn = function(r) return NS.Util.FormatMoney(r.auctionPrice) end,
    sortFn = function(r) return r.auctionPrice or 0 end },
  -- Character is always the last column (see order note above).
```

- [ ] **Step 4: Register numeric sort** — update line 197:

```lua
local NUMERIC_SORT = { date = true, time = true, ilvl = true, qty = true, quality = true, vendor = true, auction = true }
```

- [ ] **Step 5: Seed synthetic data** — in `BuildTestData`'s record table (~365-385), after the `sellPrice` line add:

```lua
      sellPrice = (q * q + 1) * (200 + rng(1800)) + rng(500), -- wide, quality-skewed value spread
      auctionPrice = (rng(100) <= 70) and ((q * q + 1) * (600 + rng(6000)) + rng(1500)) or nil,
      priceSource = (rng(100) <= 70) and ({ "auctionator", "tsm:dbmarket", "oribos:market" })[rng(3)] or nil,
```

(70% of synthetic rows get an AH price so the column and the derived value are exercised; the rest fall back to vendor.)

- [ ] **Step 6: Window-width verification** — no production change needed: `MinFrameWidth()` sums column widths, so the new 72px column raises it from ~1132 to ~1212 (> the 1160 floor at `Browser.lua:977`), and `RestoreWindow`'s `math.max(B._minW, saved.w)` clamp (`Browser.lua:101`) widens any persisted-narrower geometry. Add a guard test to `tests/test_browsertable.lua`:

```lua
test("BrowserTable: MinFrameWidth accounts for the AH column (>= 1212)", function()
  assertTrue(NS.BrowserTable:MinFrameWidth() >= 1212,
    "AH column must widen the frame past the old 1160 floor")
end)
```

- [ ] **Step 7: Run to verify it passes** — `lua tests/run.lua` → PASS; `luacheck .` → 0 errors. In-game smoke: open the browser, confirm the **AH** column shows between Vendor and Character, sorts high→low on first click, and the window opens wide enough to show it.

- [ ] **Step 8: Commit**

```bash
git add modules/BrowserTable.lua tests/test_browsertable.lua
git commit -m "feat(browser): add AH price column after Vendor"
```

---

## Phase 3 — Insights (value replaces vendor value)

### Task 7: `Database:Stats` value math via `RecordValue`

**Files:**
- Modify: `core/Database.lua:175-176` (comment), `:190` (value)
- Test: `tests/test_stats.lua`

**Interfaces:**
- Consumes: `NS.Util.RecordValue`.
- Produces: unchanged `Stats` struct, but every value field now aggregates `RecordValue(r)×qty`.

- [ ] **Step 1: Write the failing test** — append to `tests/test_stats.lua`:

```lua
test("Stats: value uses auctionPrice when present, else sellPrice", function()
  local recs = {
    { ts = 1, quality = 3, quantity = 2, sellPrice = 10, auctionPrice = 100, source = "KILL", itemID = 1, char = "A-R" },
    { ts = 2, quality = 3, quantity = 1, sellPrice = 50,                      source = "KILL", itemID = 2, char = "A-R" },
  }
  NS.State.testRecords = recs
  local s = NS.Database:Stats()
  NS.State.testRecords = nil
  -- 100*2 (auction) + 50*1 (vendor fallback) = 250
  assertEqual(s.totals.totalValue, 250)
  assertEqual(s.valueBySource.KILL, 250)
  assertEqual(s.totals.richestDrop.value, 200)   -- the auction-priced stack
end)
```

- [ ] **Step 2: Run to verify it fails** — `lua tests/run.lua` → FAIL (totalValue == 70, using sellPrice only).

- [ ] **Step 3: Implement** — in `core/Database.lua:Stats`, change the per-record value line (190):

```lua
    local value = (NS.Util.RecordValue(r) or 0) * qty
```

And update the header comment (175-176) to read: `"Value" is the derived value: (auctionPrice or sellPrice) × quantity (captured at loot time).`

- [ ] **Step 4: Run to verify it passes** — `lua tests/run.lua` → PASS. Existing `test_stats` cases (seeded with `sellPrice` only, no `auctionPrice`) still pass because `RecordValue` falls back to `sellPrice`.

- [ ] **Step 5: Commit**

```bash
git add core/Database.lua tests/test_stats.lua
git commit -m "feat(insights): Stats value = auction-or-vendor via RecordValue"
```

---

### Task 8: Analytics relabel (vendor value → value)

**Files:**
- Modify: `modules/Analytics.lua:216` (card label), `:362,:369` (chart headers), `:85` (comment)

**Interfaces:** none (label-only; charts already read the value maps that Task 7 repopulated).

- [ ] **Step 1: Relabel the value card** — line 216:

```lua
  { key = "value",   label = "value", str = true },
```

- [ ] **Step 2: Relabel the chart section headers** — lines 362 and 369:

```lua
    vsource = sectionHeader(content, "Value by source"),
```
```lua
    vtime   = sectionHeader(content, "Value over time (per day)"),
```

- [ ] **Step 3: Freshen the comment** — line ~85, change "Vendor value → display string" to "Value → display string".

- [ ] **Step 4: Verify** — `lua tests/run.lua` → PASS; `luacheck .` → 0 errors. In-game smoke: Insights tab shows "value", "Value by source", "Value over time"; the headline value KPI reflects auction-inclusive totals.

- [ ] **Step 5: Commit**

```bash
git add modules/Analytics.lua
git commit -m "feat(insights): relabel vendor value → value in Analytics"
```

---

## Phase 4 — CSV export

### Task 9: CSV columns + InsightsCSV label

**Files:**
- Modify: `modules/Export.lua:87-88` (history COLUMNS), `:157` (InsightsCSV label)
- Test: `tests/test_export.lua`

**Interfaces:**
- Consumes: `record.auctionPrice`, `record.priceSource`, `NS.Util.RecordValue`, the module-local `money()`.
- Produces: new CSV columns `auctionPrice,auctionPriceRaw,value,valueRaw,priceSource` after `sellPriceRaw`.

- [ ] **Step 1: Update the failing header tests** — in `tests/test_export.lua`, change the header-order assertion (~36) to:

```lua
  assertEqual(header,
    "ts,date,time,char,classFile,itemID,itemName,quality,qualityRaw,itemLevel,bound," ..
    "sellPrice,sellPriceRaw,auctionPrice,auctionPriceRaw,value,valueRaw,priceSource," ..
    "itemType,itemSubType,quantity,source,zone,wowheadLink")
```

And add a value-formatting test:

```lua
test("Export: CSV auction/value columns — auction present and vendor fallback", function()
  local withAuc = NS.Export:CSV({ { sellPrice = 10, auctionPrice = 500, priceSource = "tsm:dbmarket", quantity = 1 } })
  assertTrue(withAuc:find("0g 5s 0c", 1, true) ~= nil, "auction 500c formatted")
  assertTrue(withAuc:find("tsm:dbmarket", 1, true) ~= nil, "priceSource present")
  -- value falls back to vendor when no auction price
  local noAuc = NS.Export:CSV({ { sellPrice = 10, quantity = 1 } })
  local dataLine = select(2, noAuc:match("^(.-)\r\n(.-)\r\n"))
  assertTrue(dataLine:find(",10,", 1, true) ~= nil or dataLine:find("10$", 1) ~= nil, "valueRaw == sellPrice")
end)
```

- [ ] **Step 2: Run to verify it fails** — `lua tests/run.lua` → FAIL (header mismatch).

- [ ] **Step 3: Implement history columns** — in `modules/Export.lua` `COLUMNS`, replace the `sellPriceRaw` line with `sellPriceRaw` + the five new columns:

```lua
  { "sellPrice",    function(r) return money(r.sellPrice) end },
  { "sellPriceRaw", function(r) return r.sellPrice end },
  { "auctionPrice", function(r) return money(r.auctionPrice) end },
  { "auctionPriceRaw", function(r) return r.auctionPrice end },
  { "value",        function(r) return money(NS.Util.RecordValue(r)) end },
  { "valueRaw",     function(r) return NS.Util.RecordValue(r) end },
  { "priceSource",  function(r) return r.priceSource end },
```

- [ ] **Step 4: Relabel InsightsCSV summary** — line 157, change `"Vendor value"` to `"Value"`:

```lua
  row("Summary", "Value", nil, t.totalValue or 0)
```

(Also update the InsightsCSV header comment at ~113-114 from "vendor value" to "value".) If `tests/test_export.lua` asserts the `"Vendor value"` label anywhere, update it to `"Value"`.

- [ ] **Step 5: Run to verify it passes** — `lua tests/run.lua` → PASS; `luacheck .` → 0 errors.

- [ ] **Step 6: Commit**

```bash
git add modules/Export.lua tests/test_export.lua
git commit -m "feat(export): add auction/value/priceSource CSV columns; value label"
```

---

## Phase 5 — AI export

> **Note:** the running AI prompt fetches `docs/ai-export-guideline.md` and `tools/build_report.py` from the **master** raw URL, so these changes only reach live exports once merged to master. The addon-side `E:AIPrompt` (Task 13) is authoritative in the prompt regardless.

### Task 10: Guideline data contract + three-price section

**Files:**
- Modify: `docs/ai-export-guideline.md` (row-keys ~162, mapping table ~167-186, value-math note ~126-129)

- [ ] **Step 1: Extend the row-key list** — line ~162:

```js
{d, t, c, cl, id, n, q, qr, il, b, v, a, val, ty, st, qty, s, z, wh, src}
```

- [ ] **Step 2: Extend the mapping table** — after the `v` row (~179) add:

```markdown
| `a`  | `auctionPriceRaw` | copper (number) or `null` — AH price snapshot at loot; `null` when no addon had one |
| `val`| `valueRaw`      | copper (number) — **the value to use for worth**: auction price if present, else vendor |
| `src`| `priceSource`   | e.g. `"tsm:dbmarket"`, `"auctionator"`, `"oribos:market"`; blank when no AH price |
```

- [ ] **Step 3: Rewrite the value-math note** — replace the block at ~126-129:

```markdown
> **Three price types.** Each row carries **`v`** (vendor sell price — a guaranteed floor),
> **`a`** (auction price snapshot at loot — may be `null`), and **`val`** (the derived value:
> `a` if present, else `v`). **Use `val` for every worth/gold KPI and ranking** — aggregate as
> **Σ(val × qty)**, not Σ(val). The engine does this for you; the assembler cross-checks the
> INSIGHTS **Value** row against Σ(val×qty). Reserve `v` for "what a vendor pays" callouts and
> `a` for explicit market-price commentary.
```

- [ ] **Step 4: Bump the guideline revision** — line 3, advance the `rev` (e.g. `rev4` → `rev5`) and date. Do NOT change the addon version.

- [ ] **Step 5: Commit**

```bash
git add docs/ai-export-guideline.md
git commit -m "docs(ai): guideline gains auction/value/priceSource keys + three-price math"
```

---

### Task 11: Assembler `build_report.py`

**Files:**
- Modify: `tools/build_report.py:16-17` (HKEYS), `:36-54` (mapping), `:130-158` (validate), `:304-324` (figures), `:356-366` (summary)
- Test: `tools/tests/test_build_report.py`

**Interfaces:**
- Produces: `H` rows carry `a`/`val`/`src`; the Value cross-check uses INSIGHTS `"Value"` = Σ(val×qty).

- [ ] **Step 1: Write the failing test** — append to `tools/tests/test_build_report.py` (match the file's existing style):

```python
def test_history_row_has_auction_value_source():
    csv = ("date,time,char,classFile,itemID,itemName,quality,qualityRaw,itemLevel,bound,"
           "sellPrice,sellPriceRaw,auctionPrice,auctionPriceRaw,value,valueRaw,priceSource,"
           "itemType,itemSubType,quantity,source,zone,wowheadLink\r\n"
           "12-Jul-2026,20:37,Stormhoof-Ravencrest,SHAMAN,1,Thing,Rare,3,,Not Bound,"
           "1g 0s 0c,10000,5g 0s 0c,50000,5g 0s 0c,50000,tsm:dbmarket,"
           "Armor,Mail,2,KILL,Zone,https://wowhead.com/item=1\r\n")
    _realm, rows = build_report.parse_history_csv(csv)
    assert rows[0]["a"] == 50000
    assert rows[0]["val"] == 50000
    assert rows[0]["src"] == "tsm:dbmarket"

def test_value_crosscheck_uses_val_times_qty():
    rows = [{"v": 10000, "a": 50000, "val": 50000, "qty": 2, "id": 1, "c": "X", "qr": 3, "il": None, "d": "d"}]
    insights = {("Summary", "Value"): {"count": "", "value": "10g 0s 0c"}}   # wrong on purpose (want 100g)
    errs = build_report.validate_against_insights(rows, insights)
    assert any("Value" in e for e in errs)
```

- [ ] **Step 2: Run to verify it fails** — `python3 -m pytest tools/tests/test_build_report.py -q` → FAIL (KeyError `a` / no Value check).

- [ ] **Step 3: Extend HKEYS** — line 16-17:

```python
HKEYS = ["d", "t", "c", "cl", "id", "n", "q", "qr", "il", "b",
         "v", "a", "val", "ty", "st", "qty", "s", "z", "wh", "src"]
```

- [ ] **Step 4: Extend the row mapping** — in `parse_history_csv`, add after the `"v"` entry:

```python
            "v": int(r["sellPriceRaw"]),
            "a": _int_or_none(r.get("auctionPriceRaw")),
            "val": _int_or_none(r.get("valueRaw")) if (r.get("valueRaw") or "").strip() != ""
                   else int(r["sellPriceRaw"]),
            "ty": r["itemType"],
            "st": r["itemSubType"],
            "qty": int(r["quantity"]),
            "s": (r["source"] or "").strip().upper(),
            "z": r["zone"],
            "wh": r["wowheadLink"],
            "src": (r.get("priceSource") or "").strip(),
```

- [ ] **Step 5: Switch the value cross-check** — in `validate_against_insights`, replace the "Vendor value" block (152-158) with:

```python
    # Value = sum(val * qty)  — the derived auction-or-vendor worth
    s = summ("Value")
    if s and s["value"]:
        computed = sum(o["val"] * o["qty"] for o in rows)
        if computed != parse_money(s["value"]):
            errs.append("Value: computed %s, INSIGHTS says %s"
                        % (_fmt_money(computed), s["value"]))
```

- [ ] **Step 6: Update `computed_figures` + summary** — in `computed_figures` (323) rename the aggregate:

```python
        "value": sum(o["val"] * o["qty"] for o in rows),
```

and in `_print_pass_summary` (362-366) change the label/format from `Vendor sum(v*qty)` / `f["vendor"]` to `Value sum(val*qty)` / `f["value"]`.

- [ ] **Step 7: Run to verify it passes** — `python3 -m pytest tools/tests/test_build_report.py -q` → PASS. (If the suite has an end-to-end test that builds against the shipped template, it will also need the template from Task 12; run Task 12 before the full suite, or gate that test on a local `--template`.)

- [ ] **Step 8: Commit**

```bash
git add tools/build_report.py tools/tests/test_build_report.py
git commit -m "feat(ai): assembler maps auction/value/source; Value = Σ(val×qty)"
```

---

### Task 12: Template engine — value source + auction column

**Files:**
- Modify: `docs/ai-export-template.html` — `rowVal` (~849), `COL` (~962-967), row builder (~970-977), colgroup/CSS (~262-266, 440-453), hero label (~387), bar/richest captions (~892,911,914,929)

**Design:** everything routes value through `rowVal`, so one edit switches the whole report to the derived value; the auction column is additive.

- [ ] **Step 1: Switch `rowVal` to the derived value** — line ~849:

```js
function rowVal(r){return ((r.val!=null?r.val:(r.v||0)))*(r.qty||1);}
```

- [ ] **Step 2: Add the Auction column to `COL`** — insert before the `Value` entry (line ~967):

```js
  {h:"AH",k:function(r){return r.a||0;},s:true,right:true},
  {h:"Value",k:function(r){return rowVal(r);},s:true,right:true}];
```

- [ ] **Step 3: Add the Auction cell to the row builder** — in the `<tr>` template (~977), insert before the final Value `<td>`:

```js
    '<td class="num">'+(r.a!=null?moneyFull(r.a):'—')+'</td>'+
    '<td>'+esc(r.z)+'</td><td class="num">'+moneyFull(rowVal(r))+'</td></tr>';
```

Wait — the Zone `<td>` precedes Value. Insert the AH cell **after** Zone and **before** Value so it matches `COL` order (…, Zone, AH, Value). Confirm against the current line and place the new `<td>` immediately before the Value `<td>`.

- [ ] **Step 4: Fix column widths** — the table uses `table-layout:fixed` with a `<colgroup>` (see CSS note ~262 and the markup near `<thead><tr id="rpt-thead">` ~453). Read lines 440-460: if a static `<colgroup>` exists, add one `<col>` for the AH column (mirror the Vendor/Value width) and bump the table `min-width:1010px` (line 266) by ~70px. If widths are `td:nth-child(...)` rules, add a rule for the new column index and shift the Value index by one.

- [ ] **Step 5: Relabel value copy** — hero label (~387) `Vendor value harvested` → `Value harvested`; bar/richest captions (~892 "vendor value", ~911, ~914, ~929) → "value". These are display strings only.

- [ ] **Step 6: Verify the template still builds** — regenerate a report from real data through the assembler with the **local** template, and open it:

```bash
# Build a tiny sample export.txt with the Task 9 CSV columns, then:
python3 tools/build_report.py --prompt /tmp/export.txt --cards /tmp/cards.html \
  --template docs/ai-export-template.html -o /tmp/report.html
```

Expected: `PASS` (head/engine/footer byte-identical — the assembler downloads the same template only when `--template` is omitted; with `--template docs/ai-export-template.html` it validates against your edited copy). Open `/tmp/report.html`: the History table shows an **AH** column after Zone/before Value, the hero reads "Value harvested", and value bars/richest reflect `val`. The shipped sample rows (which carry only `v`) render with a blank AH cell and value == vendor — acceptable.

- [ ] **Step 7: Commit**

```bash
git add docs/ai-export-template.html
git commit -m "feat(ai): template shows AH column and uses derived value everywhere"
```

---

### Task 13: `E:AIPrompt` three-price framing

**Files:**
- Modify: `modules/Export.lua:217-258` (`AIPrompt` framing lines)

- [ ] **Step 1: Add the price-type guidance** — in `AIPrompt`, after the existing "Two datasets follow…" rule line (~244), add:

```lua
    "- Each HISTORY row carries THREE prices: vendor (v), auction (a, may be blank), and value",
    "  (val = auction-if-present-else-vendor). Use VALUE for every worth/gold figure and ranking;",
    "  mention vendor or auction only when specifically contrasting them. The engine aggregates Σ(val×qty).",
```

- [ ] **Step 2: Verify** — `lua tests/run.lua` → PASS (if `test_export.lua` asserts prompt substrings, extend it to check the new line); `luacheck .` → 0 errors.

- [ ] **Step 3: Commit**

```bash
git add modules/Export.lua
git commit -m "feat(ai): prompt explains vendor/auction/value and when to use each"
```

---

## Phase 6 — Docs, inventory, badge

### Task 14: Docs + test-cases + README badge

**Files:**
- Modify: `docs/data-model.md`, `docs/ARCHITECTURE.md`, `docs/test-cases.md`, `README.md`

- [ ] **Step 1: Update `docs/data-model.md`** — document `auctionPrice` (copper, per unit, nil), `priceSource` (provenance tag), and that `value` is derived (`Util.RecordValue`, not stored, no schema bump). Note old records have `auctionPrice=nil` and thus value=vendor.

- [ ] **Step 2: Update `docs/ARCHITECTURE.md`** — add the `AuctionPrice` module to the module map and the cascade to the data-flow; record the standards resolution: third-party pricing-addon shims live in `AuctionPrice` (presence-gated), deliberately outside `core/Compat.lua` (Blizzard-API-only), a boundary the Ka0s Standard does not currently address.

- [ ] **Step 3: Regenerate the test inventory** — `lua tests/run.lua --list > docs/test-cases.md`.

- [ ] **Step 4: Bump the README tests badge** — set the `tests` badge count to the new total printed by `lua tests/run.lua` (added cases: util, auctionprice ×7, collector, schema, browsertable ×2, stats, export). Do NOT touch the version badge.

- [ ] **Step 5: Final verification** — `lua tests/run.lua` → all PASS; `luacheck .` → 0 errors; `python3 -m pytest tools/tests/ -q` → PASS.

- [ ] **Step 6: Commit**

```bash
git add docs/data-model.md docs/ARCHITECTURE.md docs/test-cases.md README.md
git commit -m "docs(auction): data-model, architecture, test inventory + badge"
```

---

## Self-Review

**Spec coverage:**
- §4 data model → Tasks 1, 3 (fields + export allowlist), derived value Task 1.
- §5 cascade → Task 2 (module + shims + settings resolution + pcall guard).
- §6 browser column + window sizing → Task 6.
- §7 settings sub-page → Tasks 4, 5.
- §8 Insights → Tasks 7, 8.
- §9 CSV → Task 9.
- §10 AI export (guideline/assembler/template/prompt) → Tasks 10-13.
- §11 tests/docs → every task's tests + Task 14.
- §12 standards note → Task 14 Step 2.

**Type consistency:** `Util.RecordValue(record)→number|nil` used identically in Stats (Task 7), Export (Task 9), and mirrored by `val` in the assembler (Task 11) and `rowVal` (Task 12). Provider `fetch(itemLink,itemID,tsmSource)→price,tag` and `Lookup(itemLink,itemID)→price,tag` consistent between Tasks 2 and 3. Settings paths `settings.auction.*` consistent between Tasks 4 (schema/defaults) and 2/5 (reader/panel).

**Placeholder scan:** the only deferred specifics are the addon `.toc` filename (Task 2 Step 6 — enumerate at execution) and the template colgroup/nth-child mechanism (Task 12 Step 4 — read 440-460 and branch). Both are explicit "read then apply" steps, not vague hand-waves.
