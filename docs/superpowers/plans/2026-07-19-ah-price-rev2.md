# AH-Price Rev 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Evolve the (unmerged) Rev-1 AH-price feature into: a nested multi-source price map, runtime-configurable capture set + selection priority, `sellPrice`→`vendorPrice` rename with migration, `value = max(auction, vendor)`, full-detail CSV, gather-time debug, and AI-template table fixes.

**Architecture:** `auctionPrice` becomes `{ provider = { key = copper } }`. `AuctionPrice:GatherAll` captures every configured key; `AuctionPrice:Pick` selects one via a configurable ordered `provider:key` priority list; `Util.RecordValue` returns `max(pickedAuction, vendorPrice)`. In-game/Insights/AI use the single computed price; CSV explodes all captured keys.

**Tech Stack:** Lua 5.1 (Ace3, headless `tests/run.lua`), Python 3 stdlib (`tools/build_report.py`), luacheck.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-07-18-ah-price-integration-design.md` — the **Revision 2** section is authoritative.
- **Branch:** continue on `feature/ah-price-integration` (unmerged). Incremental auto-commit authorized (one commit per task when green).
- **Field names (fixed):** record has `vendorPrice` (copper/unit) and `auctionPrice` (nested map `provider→key→copper`, nil if none). `priceSource` is **removed**.
- **Canonical key list** lives in `core/Constants.lua` as `C.AUCTION_KEYS` (drives capture menu, GatherAll, CSV columns, priority defaults). Tag format: `provider..":"..key` (e.g. `"tsm:dbmarket"`).
- **Default capture set:** `auctionator:minbuyout`, `tsm:dbmarket`, `tsm:dbminbuyout`, `tsm:dbregionmarketavg`, `tsm:dbregionminbuyoutavg`, `oribos:market`, `oribos:region`.
- **Value rule:** `RecordValue(r) = max(Pick(r.auctionPrice), r.vendorPrice)` when both exist; else whichever exists; else nil.
- **Selection:** `Pick` walks the configurable ordered priority list (`settings.auction.priority`, an array carve-out) and returns the first `provider:key` present in the record's map. Reordering re-picks live (point-in-time data, live selection — intended).
- **Migration:** `schemaVersion` 2→3 renames `sellPrice`→`vendorPrice` on load (non-destructive).
- **Surfaces:** in-game browser, Insights, AI export use the single computed auction price + value. Only CSV explodes per-key sub-columns.
- **Hard rules:** never bump addon version; account-wide storage; Compat firewall stays Blizzard-only (AH shims stay in `AuctionPrice`). Third-party globals already allowlisted in `.luacheckrc`.
- **Verify each task:** `lua tests/run.lua` (exit 0) AND `luacheck .` (0 errors, 0 warnings). Python tasks: `python3 -m pytest tools/tests/ -q`.
- **Test inventory/badge** batched into the final task.

---

## File Structure

**Modify:** `core/Constants.lua` (`C.AUCTION_KEYS`, capture defaults), `core/Database.lua` (migration, Export allowlist, Stats comment), `core/Util.lua` (`RecordValue`), `modules/AuctionPrice.lua` (GatherAll/Pick/capabilities), `modules/Collector.lua` (capture + debug), `defaults/Global.lua` (auction defaults), `settings/Schema.lua` (capture MultiCheck; drop old rows), `settings/Panel.lua` (priority reorder UI), `modules/BrowserTable.lua` (columns + test-gen), `modules/Export.lua` (dynamic CSV), `tools/build_report.py` (vendorPriceRaw), `docs/ai-export-guideline.md`, `docs/ai-export-template.html`, `README.md`, docs. Plus the corresponding `tests/*`.

---

## Task R1: vendorPrice rename + v2→v3 migration

**Files:** `core/Database.lua` (migration ~13-28, Export allowlist :164, Stats comment :176), `modules/Collector.lua` (:52,:101,:106,:109), `modules/BrowserTable.lua` (:168-169 vendor col, :378 test-gen), `modules/Export.lua` (:90-91), `core/Util.lua` (RecordValue), tests: `test_stats.lua`, `test_export.lua`, `test_collector.lua`, `test_browsertable.lua`, `test_util.lua`, and a new migration test in `test_database.lua`.

**Interfaces:** Produces record field `vendorPrice` (was `sellPrice`) everywhere; `NS:RunMigrations` gains a v2→v3 step.

- [ ] **Step 1: Migration test (RED)** — add to `tests/test_database.lua`:

```lua
test("Migrate: v2->v3 renames sellPrice to vendorPrice", function()
  local g = NS.db.global
  g.schemaVersion = 2
  g.history = { { itemName = "X", sellPrice = 250, quantity = 1 } }
  NS:RunMigrations()
  assertEqual(g.schemaVersion, 3)
  assertEqual(g.history[1].vendorPrice, 250)
  assertEqual(g.history[1].sellPrice, nil)
end)
```

- [ ] **Step 2: Run → FAIL** (`vendorPrice` nil / schema stays 2). `lua tests/run.lua`.

- [ ] **Step 3: Add the migration** — in `core/Database.lua` `RunMigrations`, after the v1→v2 block:

```lua
  -- v2 -> v3: rename per-record sellPrice -> vendorPrice (non-destructive; value preserved).
  if g.schemaVersion < 3 then
    local n = 0
    for _, r in ipairs(g.history or {}) do
      if r.sellPrice ~= nil then r.vendorPrice = r.sellPrice; r.sellPrice = nil; n = n + 1 end
    end
    g.schemaVersion = 3
    if NS.State.debug and NS.Debug then NS.Debug("Migrate", "%s", NS.MigrationSummary(2, 3, n)) end
  end
```

- [ ] **Step 4: Rename the field everywhere.** Replace `sellPrice` with `vendorPrice` at these record-field sites (NOT the Compat API local, which legitimately reads the API's sellPrice return):
  - `modules/Collector.lua:52` record field; `:106` env key; `:109` env assignment. Keep the `GetItemExtras` return local named `sellPrice` (:101) but assign it to `vendorPrice = sellPrice` in the env table.
  - `core/Database.lua:164` Export allowlist (`vendorPrice = r.vendorPrice`); `:176` comment.
  - `modules/BrowserTable.lua:168-169` (`FormatMoney(r.vendorPrice)`, `r.vendorPrice or 0`); `:378` test-gen key `vendorPrice =`.
  - `modules/Export.lua:90-91` (`"vendorPrice"`/`"vendorPriceRaw"`, `money(r.vendorPrice)`, `r.vendorPrice`).
  - `core/Util.lua` `RecordValue` fallback `record.sellPrice` → `record.vendorPrice` (interim; rewritten in R4).
  - All `tests/*` fixtures/asserts using `sellPrice` → `vendorPrice`, including the Export header-order assertion (`sellPrice,sellPriceRaw` → `vendorPrice,vendorPriceRaw`).

- [ ] **Step 5: Run → GREEN.** `lua tests/run.lua` all pass; `luacheck .` 0/0. Grep `grep -rn "sellPrice" --include=*.lua modules core settings tests defaults` should show only the Compat API local (`core/Compat.lua`) and the Collector `GetItemExtras` local — no record-field uses.

- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat(schema): rename sellPrice->vendorPrice with v2->v3 migration"`

---

## Task R2: AuctionPrice — capability keys, GatherAll, Pick

**Files:** `core/Constants.lua` (add `C.AUCTION_KEYS`, `C.AUCTION_CAPTURE_DEFAULT`, `C.AUCTION_PRIORITY_DEFAULT`), `modules/AuctionPrice.lua` (rewrite), test: `tests/test_auctionprice.lua`.

**Interfaces:**
- Consumes: `NS.db.global.settings.auction.capture` (set of tags; default `C.AUCTION_CAPTURE_DEFAULT`), `...auction.priority` (array; default `C.AUCTION_PRIORITY_DEFAULT`), `...auction.enabled`.
- Produces: `AuctionPrice:GatherAll(itemLink, itemID) -> map|nil` (`{provider={key=copper}}`); `AuctionPrice:Pick(map) -> price|nil, tag|nil`.

- [ ] **Step 1: Constants** — add to `core/Constants.lua`:

```lua
-- Every AH price data point the addon can capture. tag = provider..":"..key. Drives the capture
-- menu, GatherAll's fetch loop, the CSV sub-columns, and the priority defaults.
C.AUCTION_KEYS = {
  { provider = "auctionator", key = "minbuyout",            label = "Auctionator \226\128\148 Min buyout" },
  { provider = "tsm",         key = "dbmarket",             label = "TSM \226\128\148 Market value" },
  { provider = "tsm",         key = "dbminbuyout",          label = "TSM \226\128\148 Min buyout" },
  { provider = "tsm",         key = "dbregionmarketavg",    label = "TSM \226\128\148 Region market avg" },
  { provider = "tsm",         key = "dbregionminbuyoutavg", label = "TSM \226\128\148 Region min-buyout avg" },
  { provider = "tsm",         key = "dbhistorical",         label = "TSM \226\128\148 Historical" },
  { provider = "tsm",         key = "dbrecent",             label = "TSM \226\128\148 Recent" },
  { provider = "tsm",         key = "dbregionhistorical",   label = "TSM \226\128\148 Region historical" },
  { provider = "tsm",         key = "dbregionsaleavg",      label = "TSM \226\128\148 Region sale avg" },
  { provider = "oribos",      key = "market",               label = "OribosExchange \226\128\148 Market" },
  { provider = "oribos",      key = "region",               label = "OribosExchange \226\128\148 Region" },
}
-- Curated defaults (which keys are captured, and the selection priority order).
C.AUCTION_CAPTURE_DEFAULT = {
  ["auctionator:minbuyout"] = true, ["tsm:dbmarket"] = true, ["tsm:dbminbuyout"] = true,
  ["tsm:dbregionmarketavg"] = true, ["tsm:dbregionminbuyoutavg"] = true,
  ["oribos:market"] = true, ["oribos:region"] = true,
}
C.AUCTION_PRIORITY_DEFAULT = {
  "tsm:dbmarket", "auctionator:minbuyout", "oribos:market",
  "tsm:dbminbuyout", "tsm:dbregionmarketavg", "tsm:dbregionminbuyoutavg", "oribos:region",
}
```

- [ ] **Step 2: Rewrite tests (RED)** — replace `tests/test_auctionprice.lua` cascade tests with GatherAll/Pick tests. Key cases (use the `withGlobals`/stub helpers already in the file):

```lua
test("AuctionPrice: GatherAll collects all captured keys into a nested map", function()
  withGlobals({
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return 48000 end } } },
    TSM_API = {
      ToItemString = function() return "i:1" end,
      GetCustomPriceValue = function(k) return ({ dbmarket=50000, dbminbuyout=47000,
        dbregionmarketavg=52000, dbregionminbuyoutavg=51500 })[k] end,
    },
    OEMarketInfo = function(_i, t) t.market = 51000; t.region = 53000 end,
  }, function()
    local m = NS.AuctionPrice:GatherAll(LINK, 210501)
    assertEqual(m.auctionator.minbuyout, 48000)
    assertEqual(m.tsm.dbmarket, 50000)
    assertEqual(m.tsm.dbregionminbuyoutavg, 51500)
    assertEqual(m.oribos.region, 53000)
  end)
end)

test("AuctionPrice: Pick walks the priority list, first present wins", function()
  local map = { tsm = { dbminbuyout = 47000 }, oribos = { market = 51000 } }
  -- default priority is tsm:dbmarket, auctionator:minbuyout, oribos:market, tsm:dbminbuyout, ...
  local price, tag = NS.AuctionPrice:Pick(map)
  assertEqual(price, 51000); assertEqual(tag, "oribos:market")  -- dbmarket/auctionator absent
end)

test("AuctionPrice: Pick respects a reordered priority list", function()
  NS.db.global.settings.auction = { enabled = true, priority = { "tsm:dbminbuyout", "oribos:market" } }
  local price, tag = NS.AuctionPrice:Pick({ tsm = { dbminbuyout = 47000 }, oribos = { market = 51000 } })
  assertEqual(price, 47000); assertEqual(tag, "tsm:dbminbuyout")
  NS.db.global.settings.auction = nil
end)

test("AuctionPrice: GatherAll only captures keys in the capture set", function()
  NS.db.global.settings.auction = { enabled = true, capture = { ["oribos:market"] = true } }
  withGlobals({ OEMarketInfo = function(_i, t) t.market = 51000; t.region = 53000 end,
                Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return 48000 end } } } },
  function()
    local m = NS.AuctionPrice:GatherAll(LINK, 210501)
    assertEqual(m.oribos.market, 51000)
    assertEqual(m.auctionator, nil)       -- not in capture set
    assertEqual(m.oribos.region, nil)     -- not in capture set
  end)
  NS.db.global.settings.auction = nil
end)

test("AuctionPrice: GatherAll returns nil when nothing gathered / disabled", function()
  assertEqual(NS.AuctionPrice:GatherAll(LINK, 210501), nil)
  NS.db.global.settings.auction = { enabled = false }
  withGlobals({ OEMarketInfo = function(_i, t) t.market = 1 end }, function()
    assertEqual(NS.AuctionPrice:GatherAll(LINK, 210501), nil)
  end)
  NS.db.global.settings.auction = nil
end)
```

- [ ] **Step 3: Run → FAIL** (GatherAll/Pick undefined).

- [ ] **Step 4: Rewrite `modules/AuctionPrice.lua`:**

```lua
local addonName, NS = ...   -- luacheck: ignore addonName
NS.AuctionPrice = NS.AuctionPrice or {}
local AuctionPrice = NS.AuctionPrice

-- Reads AH prices for a just-looted item from installed pricing addons. Captures EVERY configured
-- price key into a nested map (provider -> key -> copper); a read-time Pick selects one via the
-- configurable priority list. Presence-gated + pcall-guarded per provider (third-party boundary —
-- deliberately not in core/Compat.lua).

-- One fetch per provider (batches that provider's captured keys). Each returns a { key = copper } sub-map
-- (only positive prices), or nil. `keys` is the set of key-names wanted for that provider.
local function fetchAuctionator(keys, itemLink, itemID)
  if not keys["minbuyout"] then return nil end
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not api then return nil end
  local price
  if itemID and api.GetAuctionPriceByItemID then price = api.GetAuctionPriceByItemID(addonName, itemID)
  elseif itemLink and api.GetAuctionPriceByItemLink then price = api.GetAuctionPriceByItemLink(addonName, itemLink) end
  if price and price > 0 then return { minbuyout = price } end
  return nil
end

local function fetchTSM(keys, itemLink)
  if not (TSM_API and TSM_API.GetCustomPriceValue and TSM_API.ToItemString) then return nil end
  local itemStr = TSM_API.ToItemString(itemLink)
  if not itemStr then return nil end
  local out
  for key in pairs(keys) do
    local price = TSM_API.GetCustomPriceValue(key, itemStr)
    if price and price > 0 then out = out or {}; out[key] = price end
  end
  return out
end

local function fetchOribos(keys, itemLink, itemID)
  if type(OEMarketInfo) ~= "function" then return nil end
  local info = {}
  OEMarketInfo(itemLink or itemID, info)
  local out
  if keys["market"] and info.market and info.market > 0 then out = out or {}; out.market = info.market end
  if keys["region"] and info.region and info.region > 0 then out = out or {}; out.region = info.region end
  return out
end

local PROVIDER_FETCH = { auctionator = fetchAuctionator, tsm = fetchTSM, oribos = fetchOribos }

local function cfg()
  local s = NS.db and NS.db.global and NS.db.global.settings and NS.db.global.settings.auction
  if s and s.enabled == false then return nil end
  local capture = (s and s.capture) or NS.Constants.AUCTION_CAPTURE_DEFAULT
  local priority = (s and s.priority) or NS.Constants.AUCTION_PRIORITY_DEFAULT
  return capture, priority
end

-- Group the capture set (tags) into { provider = { key = true } }.
local function wantedByProvider(capture)
  local out = {}
  for tag, on in pairs(capture) do
    if on then
      local prov, key = tag:match("^(.-):(.+)$")
      if prov and key then out[prov] = out[prov] or {}; out[prov][key] = true end
    end
  end
  return out
end

-- Capture every configured key. Returns { provider = { key = copper } } or nil if empty.
function AuctionPrice:GatherAll(itemLink, itemID)
  local capture = (cfg())
  if not capture then return nil end
  local wanted = wantedByProvider(capture)
  local map
  for prov, keys in pairs(wanted) do
    local fetch = PROVIDER_FETCH[prov]
    if fetch then
      local ok, sub = pcall(fetch, keys, itemLink, itemID)
      if ok and sub and next(sub) then map = map or {}; map[prov] = sub end
    end
  end
  return map
end

-- Select one price from the map via the priority list. Returns price, tag ("provider:key").
function AuctionPrice:Pick(map)
  if type(map) ~= "table" then return nil, nil end
  local _, priority = cfg()
  priority = priority or NS.Constants.AUCTION_PRIORITY_DEFAULT
  for _, tag in ipairs(priority) do
    local prov, key = tag:match("^(.-):(.+)$")
    local v = prov and key and map[prov] and map[prov][key]
    if v then return v, tag end
  end
  return nil, nil
end
```

- [ ] **Step 5: Run → GREEN**; `luacheck .` 0/0.

- [ ] **Step 6: Commit** — `git commit -am "feat(auction): GatherAll (all keys) + Pick (priority select); capability keys"`

---

## Task R3: capture the map at loot + debug line

**Files:** `modules/Collector.lua` (BuildRecord :52-54, OnChatMsgLoot :101-113), `core/Database.lua` Export allowlist (:164), test `tests/test_collector.lua`.

- [ ] **Step 1: Test (RED)** — in `tests/test_collector.lua`:

```lua
test("Collector: BuildRecord stores the auctionPrice map, no priceSource", function()
  local rec = NS.Collector:BuildRecord("[L]", 1, { source = "KILL", confidence = "CERTAIN" },
    { ts = 1, vendorPrice = 10, auctionPrice = { tsm = { dbmarket = 500 } } })
  assertEqual(rec.auctionPrice.tsm.dbmarket, 500)
  assertEqual(rec.priceSource, nil)
  assertEqual(rec.vendorPrice, 10)
end)
```

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Update `BuildRecord`** — replace the Rev-1 `auctionPrice`/`priceSource` lines (:53-54) with:

```lua
    vendorPrice  = env.vendorPrice,  -- vendor sell price (copper, per unit)
    auctionPrice = env.auctionPrice, -- nested map provider->key->copper, or nil
```
(Remove the `priceSource` field entirely.)

- [ ] **Step 4: Update `OnChatMsgLoot`** — replace the Rev-1 lookup (:102) and env keys:

```lua
  local itemLevel, bound, sellPrice, itemType, itemSubType = NS.Compat.GetItemExtras(link)
  local auctionPrice = NS.AuctionPrice:GatherAll(link, itemID)
  ...
      vendorPrice = sellPrice, auctionPrice = auctionPrice,
      itemType = itemType, itemSubType = itemSubType, ...
```
Then add the debug line after `NS.Database:Add(record)` (near the existing `[Loot]` debug):

```lua
  if NS.State.debug and NS.Debug then
    local parts = {}
    if auctionPrice then
      for prov, sub in pairs(auctionPrice) do
        for k, v in pairs(sub) do parts[#parts + 1] = prov .. ":" .. k .. "=" .. tostring(v) end
      end
    end
    table.sort(parts)
    local pp, ptag = NS.AuctionPrice:Pick(auctionPrice)
    NS.Debug("AHPrice", "%s | gathered: %s | pick: %s(%s)", tostring(itemName),
      (#parts > 0 and table.concat(parts, " ") or "none"), tostring(pp or "-"), tostring(ptag or "-"))
  end
```

- [ ] **Step 5: Export allowlist** — `core/Database.lua:164`: emit `vendorPrice = r.vendorPrice, auctionPrice = r.auctionPrice,` (drop `priceSource`).

- [ ] **Step 6: Run → GREEN**; `luacheck .` 0/0.

- [ ] **Step 7: Commit** — `git commit -am "feat(auction): capture full price map at loot + gather/pick debug"`

---

## Task R4: RecordValue = max(auction, vendor)

**Files:** `core/Util.lua`, `tests/test_util.lua`.

- [ ] **Step 1: Test (RED)** — replace the Rev-1 RecordValue test with:

```lua
test("Util: RecordValue = max(pickedAuction, vendorPrice), else whichever exists", function()
  NS.db.global.settings.auction = { enabled = true, priority = { "tsm:dbmarket" } }
  assertEqual(NS.Util.RecordValue({ vendorPrice = 10, auctionPrice = { tsm = { dbmarket = 500 } } }), 500)
  assertEqual(NS.Util.RecordValue({ vendorPrice = 800, auctionPrice = { tsm = { dbmarket = 500 } } }), 800) -- vendor higher
  assertEqual(NS.Util.RecordValue({ vendorPrice = 10 }), 10)                       -- no auction
  assertEqual(NS.Util.RecordValue({ auctionPrice = { tsm = { dbmarket = 500 } } }), 500) -- no vendor
  assertEqual(NS.Util.RecordValue({}), nil)
  NS.db.global.settings.auction = nil
end)
```

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Rewrite RecordValue** in `core/Util.lua`:

```lua
-- Derived per-unit worth: the higher of the picked auction price and the vendor price (auction can
-- be below vendor). Pick chooses WHICH auction number via the priority list. nil if neither exists.
function Util.RecordValue(record)
  if record == nil then return nil end
  local a = record.auctionPrice and NS.AuctionPrice:Pick(record.auctionPrice) or nil
  local v = record.vendorPrice
  if a and v then return math.max(a, v) end
  return a or v
end
```

- [ ] **Step 4: Run → GREEN** (Stats/Export tests still pass — they seed vendor-only or map rows). `luacheck .` 0/0.

- [ ] **Step 5: Commit** — `git commit -am "feat(value): RecordValue = max(pickedAuction, vendorPrice)"`

---

## Task R5: settings — capture checklist + priority carve-out (schema/defaults/constants)

**Files:** `settings/Schema.lua` (drop Rev-1 auction rows, add capture MultiCheck), `defaults/Global.lua` (auction defaults), `core/Constants.lua` (`C.AUCTION_CAPTURE_OPTIONS`), `modules/AuctionPrice.lua` (priority accessors), tests `test_schema.lua`.

- [ ] **Step 1: Capture options constant** — in `core/Constants.lua` after `C.AUCTION_KEYS`:

```lua
C.AUCTION_CAPTURE_OPTIONS = {}
for i, k in ipairs(C.AUCTION_KEYS) do
  C.AUCTION_CAPTURE_OPTIONS[i] = { value = k.provider .. ":" .. k.key, label = k.label }
end
```
Remove the now-unused `C.AUCTION_PRIORITY_OPTIONS` and `C.TSM_SOURCE_OPTIONS`.

- [ ] **Step 2: Defaults** — replace the Rev-1 `settings.auction` table in `defaults/Global.lua` with:

```lua
    auction = {
      enabled = true,
      capture = {   -- which price keys to gather (set of tags)
        ["auctionator:minbuyout"] = true, ["tsm:dbmarket"] = true, ["tsm:dbminbuyout"] = true,
        ["tsm:dbregionmarketavg"] = true, ["tsm:dbregionminbuyoutavg"] = true,
        ["oribos:market"] = true, ["oribos:region"] = true,
      },
      priority = {  -- ordered provider:key selection list (carve-out; reordered via the panel UI)
        "tsm:dbmarket", "auctionator:minbuyout", "oribos:market",
        "tsm:dbminbuyout", "tsm:dbregionmarketavg", "tsm:dbregionminbuyoutavg", "oribos:region",
      },
    },
```

- [ ] **Step 3: Schema rows** — in `settings/Schema.lua`, **remove** the seven Rev-1 auction rows (enabled/tsmSource/auctionator/priorityAuctionator/tsm/priorityTSM/oribos/priorityOribos) and replace with two:

```lua
  { path = "settings.auction.enabled", default = true, type = "boolean", widget = "CheckBox",
    group = "Auction House Price", label = "Enable AH pricing",
    tooltip = "Gather auction-house prices at loot time from installed pricing addons." },
  { path = "settings.auction.capture", default = NS.Constants.AUCTION_CAPTURE_DEFAULT, type = "table",
    widget = "MultiCheck", wide = true, group = "Auction House Price", label = "Capture these prices",
    options = NS.Constants.AUCTION_CAPTURE_OPTIONS },
```
(`settings.auction.priority` is a carve-out array — NOT a schema row — managed by the panel UI in R6. Document it in `docs/saved-variables.md` alongside `blacklist`/`savedView`.)

- [ ] **Step 4: Priority accessors** — in `modules/AuctionPrice.lua` add helpers the panel will use:

```lua
function AuctionPrice:GetPriority()
  local s = NS.db.global.settings.auction
  s.priority = s.priority or {}
  return s.priority
end
function AuctionPrice:MovePriority(index, delta)   -- delta = -1 up / +1 down
  local p = self:GetPriority()
  local j = index + delta
  if index < 1 or index > #p or j < 1 or j > #p then return false end
  p[index], p[j] = p[j], p[index]
  return true
end
```

- [ ] **Step 5: Tests** — update `test_schema.lua`: assert `settings.auction.capture` row exists (group "Auction House Price", widget MultiCheck) and the old rows are gone; assert `Schema:Default("settings.auction.capture")["tsm:dbmarket"] == true`. Add an AuctionPrice test for `MovePriority` swap bounds.

- [ ] **Step 6: Run → GREEN** (watch for `S:Register` "missing default"). `luacheck .` 0/0.

- [ ] **Step 7: Commit** — `git commit -am "feat(settings): capture checklist + priority carve-out; drop Rev-1 rows"`

---

## Task R6: settings panel — priority reorder UI

**Files:** `settings/Panel.lua` (extend the Auction subcategory's OnShow to render the capture MultiCheck via `renderSchema{only=...}` PLUS a custom priority list below it).

**Model:** the existing Filters custom list (`makeFilterSection`/`buildFilters`, `settings/Panel.lua:445-514`) — a heading, a live list of rows, and per-row buttons, with a `refresh` closure. Build an analogous `buildAuctionPriority(ctx)` that renders each entry of `NS.AuctionPrice:GetPriority()` as a row showing the tag's label with **▲/▼ buttons** calling `NS.AuctionPrice:MovePriority(i, ∓1)` then refreshing.

- [ ] **Step 1:** In the Auction subcategory `OnShow` (added in Rev-1 Task 5), after `renderSchema(actx, nil, { only = "Auction House Price" })`, call a new `buildAuctionPriority(actx)`.

- [ ] **Step 2:** Implement `buildAuctionPriority(ctx)` mirroring `makeFilterSection`: a section heading "Price priority (drag order top = preferred)", then for each `i, tag` in `NS.AuctionPrice:GetPriority()` a row with a label (resolve the tag → its `C.AUCTION_KEYS` label; fall back to the raw tag) and two small buttons (▲ = `MovePriority(i,-1)`, ▼ = `MovePriority(i,1)`) that on click mutate and re-run the section's `refresh`. Reuse the file's existing `makePairButton`/button helpers and `scroll:AddChild` pattern. Register the refresh in `ctx.refreshers`.

- [ ] **Step 3: Verify** — `luacheck .` 0/0; `lua tests/run.lua` green (Panel loads). In-game smoke (deferred): the Auction sub-page shows the capture checkboxes + a reorderable priority list; ▲/▼ reorder and persist.

- [ ] **Step 4: Commit** — `git commit -am "feat(settings): reorderable AH price-priority list on the Auction sub-page"`

---

## Task R7: browser — auction column uses Pick; test-gen map

**Files:** `modules/BrowserTable.lua` (:170-173 auction col, :379-380 test-gen), test `tests/test_browsertable.lua`.

- [ ] **Step 1: Test (RED)** — update the auction-column test:

```lua
test("BrowserTable: auction column shows the picked price from the map", function()
  NS.db.global.settings.auction = { enabled = true, priority = { "tsm:dbmarket" } }
  assertEqual(NS.BrowserTable:CellText("auction", { auctionPrice = { tsm = { dbmarket = 12345 } } }),
    NS.Util.FormatMoney(12345))
  assertEqual(NS.BrowserTable:CellText("auction", {}), "")
  NS.db.global.settings.auction = nil
end)
```

- [ ] **Step 2: Run → FAIL** (valueFn indexes a number).

- [ ] **Step 3: Implement** — `modules/BrowserTable.lua` auction column (:170-173):

```lua
  { key = "auction", label = "AH", width = 72, align = "RIGHT",
    desc = "Auction-house price per unit at loot time (chosen by your price-priority order).",
    valueFn = function(r) return NS.Util.FormatMoney((NS.AuctionPrice:Pick(r.auctionPrice))) end,
    sortFn = function(r) return (NS.AuctionPrice:Pick(r.auctionPrice)) or 0 end },
```
Test-gen (:379-380): replace the scalar `auctionPrice`/`priceSource` lines with a synthetic map (drop priceSource):

```lua
      auctionPrice = (rng(100) <= 70) and {
        tsm = { dbmarket = (q * q + 1) * (600 + rng(6000)) + rng(1500),
                dbminbuyout = (q * q + 1) * (400 + rng(5000)) },
        oribos = { market = (q * q + 1) * (500 + rng(6000)) },
      } or nil,
```

- [ ] **Step 4: Run → GREEN**; `luacheck .` 0/0.

- [ ] **Step 5: Commit** — `git commit -am "feat(browser): AH column shows the priority-picked price"`

---

## Task R8: CSV — vendor + computed + dynamic per-key columns

**Files:** `modules/Export.lua` (COLUMNS + E:CSV), test `tests/test_export.lua`.

**Design:** static columns (…, `vendorPrice`, `vendorPriceRaw`, `auctionPrice`, `auctionPriceRaw`, `value`, `valueRaw`, `auctionSource`, then dynamic) + one raw column per `C.AUCTION_KEYS` entry named `auc_<provider>_<key>` reading `r.auctionPrice[provider][key]`. `auctionPrice`/`Raw` = `Pick`; `auctionSource` = Pick's tag; `value` = `RecordValue`.

- [ ] **Step 1: Test (RED)** — update the header-order assertion and add a map test. New static block after `vendorPriceRaw`: `auctionPrice,auctionPriceRaw,value,valueRaw,auctionSource,` then the `auc_*` columns (in `C.AUCTION_KEYS` order): `auc_auctionator_minbuyout,auc_tsm_dbmarket,...,auc_oribos_region`. Assert a row with a map emits the picked price under `auctionPriceRaw`, the tag under `auctionSource`, and the right raw sub-columns.

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Implement** — in `modules/Export.lua`, replace the Rev-1 auction columns (:92-96) with the computed columns and append dynamic ones built from `NS.Constants.AUCTION_KEYS`:

```lua
  { "vendorPrice",    function(r) return money(r.vendorPrice) end },
  { "vendorPriceRaw", function(r) return r.vendorPrice end },
  { "auctionPrice",   function(r) return money((NS.AuctionPrice:Pick(r.auctionPrice))) end },
  { "auctionPriceRaw",function(r) return (NS.AuctionPrice:Pick(r.auctionPrice)) end },
  { "value",          function(r) return money(NS.Util.RecordValue(r)) end },
  { "valueRaw",       function(r) return NS.Util.RecordValue(r) end },
  { "auctionSource",  function(r) return select(2, NS.AuctionPrice:Pick(r.auctionPrice)) end },
```
Then, after the static `COLUMNS` table is defined, append the per-key columns:

```lua
for _, k in ipairs(NS.Constants.AUCTION_KEYS) do
  local prov, key = k.provider, k.key
  COLUMNS[#COLUMNS + 1] = { "auc_" .. prov .. "_" .. key,
    function(r) return r.auctionPrice and r.auctionPrice[prov] and r.auctionPrice[prov][key] or nil end }
end
```
(Insert this loop before `HEADER` is built at :104-105 so the dynamic columns are included; if the `wowheadLink` column must stay last, insert the loop between the `auctionSource`/vendor block and the `wowheadLink` entry instead — keep `wowheadLink` final. Choose placement so header stays deterministic and `wowheadLink` is last.)

- [ ] **Step 4:** Update the InsightsCSV comment/label only if it still says "vendor"; the `Value` summary already uses `t.totalValue` (correct). No functional InsightsCSV change beyond that.

- [ ] **Step 5: Run → GREEN**; `luacheck .` 0/0.

- [ ] **Step 6: Commit** — `git commit -am "feat(export): CSV exposes computed + all captured per-key auction columns"`

---

## Task R9: AI assembler + guideline — vendorPriceRaw

**Files:** `tools/build_report.py` (:47 mapping), `docs/ai-export-guideline.md` (mapping table `v` row), tests `tools/tests/test_build_report.py`.

- [ ] **Step 1:** In `build_report.py` `parse_history_csv`, change `"v": int(r["sellPriceRaw"])` → `"v": int(r["vendorPriceRaw"])`, and the `val` fallback `int(r["sellPriceRaw"])` → `int(r["vendorPriceRaw"])`. Any test fixture/CSV header using `sellPriceRaw` → `vendorPriceRaw`.

- [ ] **Step 2:** In `docs/ai-export-guideline.md`, the mapping table `v` row source `sellPriceRaw` → `vendorPriceRaw`.

- [ ] **Step 3: Run** `python3 -m pytest tools/tests/ -q` → all pass (update fixtures as needed). Also `lua tests/run.lua` unaffected.

- [ ] **Step 4: Commit** — `git commit -am "feat(ai): assembler + guideline read vendorPriceRaw"`

---

## Task R10: AI template — fit columns, time format, Vendor/Auction columns

**Files:** `docs/ai-export-template.html`.

- [ ] **Step 1: Time format** — `timeCell` (:852): change `+" &middot; "+` to `+" "+` → `p[0]+" "+p[1]+" "+r.t` (renders `17 Jul 12:55`).

- [ ] **Step 2: Columns** — in `COL` (:962-969): rename the two trailing columns and reorder to `..., Zone, Vendor, Auction`:

```js
  {h:"Vendor",k:function(r){return r.v||0;},s:true,right:true},
  {h:"Auction",k:function(r){return r.a||0;},s:true,right:true}];
```
In the row-builder `<tr>` (:972-981): the last two `<td>`s must become **Vendor** then **Auction** (matching COL): Vendor renders `moneyFull(r.v)`, Auction renders `(r.a!=null?moneyFull(r.a):'—')`. (Currently they are AH=`r.a` then Value=`moneyFull(rowVal(r))` — swap semantics: 2nd-last = vendor `r.v`, last = auction `r.a`.)

- [ ] **Step 3: Fit the columns** — reduce the table font (`table{... font-size:11.5px ...}` at ~:266, e.g. to `10.5px`) and rebalance the `<colgroup>` widths (:448-451, 12 `<col>`s) so the total fits the table without overflow (trim the wide Item/Character/Zone columns a little; keep Vendor/Auction ~92px). Bump/keep `min-width` consistent. The goal: no horizontal overflow at default width.

- [ ] **Step 4: Verify** via the assembler against the edited local template (build a tiny export with the R8 CSV header incl. `vendorPriceRaw`), expect PASS; open the report and confirm: time reads `17 Jul 12:55`, the last two columns are **Vendor** then **Auction** with correct numbers, and nothing overflows. Also `python3 -m pytest tools/tests/ -q` green.

- [ ] **Step 5: Commit** — `git commit -am "fix(ai-template): fit columns, plain time format, Vendor+Auction columns"`

---

## Task R11: README user section + docs + inventory + badge

**Files:** `README.md`, `docs/data-model.md`, `docs/ARCHITECTURE.md`, `docs/testing.md`, `docs/saved-variables.md`, `docs/test-cases.md`, README badge.

- [ ] **Step 1: README** — add a plain-language "Auction-house pricing" section: it reads prices from **Auctionator, TSM, and OribosExchange** (whichever you have installed) when you loot; you choose which price counts most via a **priority list** in settings; each drop's **value** is the higher of its vendor price and its auction price. No field names / internals.

- [ ] **Step 2: docs** — update `docs/data-model.md` (auctionPrice nested map, vendorPrice, no priceSource, value=max, v2→v3 migration), `docs/ARCHITECTURE.md` (GatherAll/Pick, configurable capture/priority), `docs/saved-variables.md` (`settings.auction.priority` array carve-out), `docs/testing.md` (any suite count if changed).

- [ ] **Step 3: Inventory + badge** — `lua tests/run.lua --list > docs/test-cases.md`; set README `Tests` badge to the actual `lua tests/run.lua` total.

- [ ] **Step 4: Final gates** — `lua tests/run.lua` all pass; `luacheck .` 0/0; `python3 -m pytest tools/tests/ -q` all pass.

- [ ] **Step 5: Commit** — `git commit -am "docs(auction): README user guide, data-model/architecture, inventory + badge"`

---

## Self-Review

- **Spec coverage:** R2.1 model→R1/R3; R2.2 keys→R2; R2.3 value+Pick→R2/R4; R2.4 GatherAll→R2/R3; R2.5 settings→R5/R6; R2.6 surfaces→R7 (browser)/R8 (CSV)/R9 (AI); R2.7 debug→R3; R2.8 migration→R1; R2.9 template→R10; R2.10 docs/README→R11.
- **Type consistency:** `GatherAll→map|nil`, `Pick(map)→price,tag`, `RecordValue→number|nil` used identically across Collector/Util/BrowserTable/Export; `C.AUCTION_KEYS` tag format `provider:key` consistent in Constants/AuctionPrice/Export/priority defaults.
- **Deferred:** in-game smoke tests for the priority reorder UI (R6) and the browser column (R7); template visual confirm via assembler PASS + open (R10). Test-inventory/badge batched to R11.
