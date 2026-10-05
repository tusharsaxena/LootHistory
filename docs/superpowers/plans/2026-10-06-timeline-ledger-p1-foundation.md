# Timeline Ledger — Phase 1 (Foundation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist an account-wide **holdings ledger** (what every character and the warband currently owns: items, currencies, gold), browsable in a new **Holdings** tab, with schema v11 and the one-time **reset recommendation** popup. No gain/loss rows yet (Phase 2) and no Timeline (Phase 3).

**Architecture:** A pure core (`core/Ledger.lua`) defines thing keys and count-map diffing. `modules/Scanner.lua` reads containers through `core/Compat.lua` shims into `{[itemID]=count}` maps. `modules/Holdings.lua` owns `db.global.holdings`. `modules/Reconciler.lua` wires events → dirty bits → (out of combat) scan → `Holdings` → `HOLDINGS_CHANGED`. In Phase 2 the same Reconciler gains the diff→row step. `modules/Browser.lua` gets a tab registry so `modules/HoldingsTab.lua` can register itself.

**Tech Stack:** Lua 5.1 (WoW Retail 12.1.0, Interface 120100), Ace3 (AceDB/AceEvent), vendored LibKa0s v1.68.1, headless harness `lua tests/run.lua` (LibKa0s kit 36), `luacheck .`.

**Spec:** `docs/superpowers/specs/2026-10-06-timeline-ledger-design.md` (§3, §4.2, §4.4, §5.2 (scan triggers only), §5.6 (genesis only), §8.0, §8.2, §9, §10, §11 `trackLedger`).

**Follow-on plans:** `2026-10-06-timeline-ledger-p2-ledger-capture.md` (Reconciler diff→rows, claims, reasons, gold, perf harness, History/Insights) and `2026-10-06-timeline-ledger-p3-timeline.md` (LibKa0s LineChart, daily rollup, Timeline tab). Each is written against the interfaces this plan **Produces**.

## Global Constraints

- Ka0s WoW Addon Standard governs everything. Any deviation: **STOP and flag** (CLAUDE.md). Do not add rows to `## Documented deviations` without the user's say-so.
- Every new file opens `local _, NS = ...` and publishes `NS.X = NS.X or {}`; no globals (`docs/common-tasks.md`).
- Every direct WoW API call goes through `core/Compat.lua` (presence-gated, degrades to nil/0/false) (`docs/compat-layer.md`).
- Every module that registers anything has a real `Disable` that unregisters; it is called from `NS.StandDown` and covered by `tests/test_disabled.lua`.
- Events are registered one-by-one via `NS.SafeRegisterEvent(target, EVENT, fn, NS.RejectedEvents)` on a **private** `NS.NewBusTarget()` target.
- Bus messages are declared once in `core/Constants.lua` `MSG` (strict `Catalog`); exactly one sender each; document in `docs/message-bus.md`.
- Settings rows live in `settings/Schema.lua`, defaults once in `defaults/Profile.lua` / `defaults/Global.lua`; every write through `Schema:Set`.
- `db.global.schemaVersion` default stays **0**; new step appended to `MIGRATIONS`; never edit the runner.
- Combat: event handlers that fire in combat only set dirty bits; work runs on `PLAYER_REGEN_ENABLED`.
- Container ids derived from `Enum.BagIndex` **member names**, never hardcoded numbers (BankLedger lesson).
- Warband holder key is exactly `"§warband"`; characters are `NS.Util.PlayerKey()` (`"Name-Realm"`).
- Files ≤ 1500 lines (`tests/_kit/test_layout_cap.lua`); `modules/Browser.lua` is at 1318 — the registry refactor must not grow it.
- Match surrounding comment density and idiom (this repo comments the *why* heavily). Code blocks below show the logic; add the explanatory comments the neighbors would have.
- Green gate before every commit: `lua tests/run.lua` (all pass) and `luacheck .` (0 warnings / 0 errors). Regenerate `docs/test-cases.md` with `lua tests/run.lua --list > docs/test-cases.md` in any task that adds tests.
- Work trunk-based on `master`; commit at the end of each task only when green. Commit trailer:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01L4XiFWzQrd9ee19aBpkVmt
  ```

## Review Focus

1. **Bank never opened this session** → the stored `bank` / `tabs` counts must be kept, never zeroed by a bag-only scan. Pinned in Task 6 (`Reconciler: bag flush never touches bank column`).
2. **Uncached item names in Holdings search** → a row still appears (name falls back to `item:<id>` / link text) and is retried, never dropped or erroring. Pinned in Task 5 (`Holdings: Search keeps uncached items`).
3. **Combat burst (potions, BAG_UPDATE storm)** → zero scans in combat, exactly one flush after `PLAYER_REGEN_ENABLED`. Pinned in Task 6.
4. **Upgrade with an empty history** (fresh install or post-purge) → no reset popup. Pinned in Task 9.
5. **Two variants of one itemID** (different ilvl) in bags and bank → counts sum per base itemID, no double counting across containers. Pinned in Task 4 (`Scanner: variants sum by itemID`).

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `core/Ledger.lua` | Create | Pure: thing keys, direction/kind enums access, `Diff` over count maps. No WoW API. |
| `core/Util.lua` | Modify | Row accessors `RowDir/RowKind/RowHolder` (legacy defaults). |
| `core/Constants.lua` | Modify | `Dir`, `Kind`, `Container`, `WARBAND_HOLDER`, bag-id groups, `MSG.HOLDINGS_CHANGED`. |
| `core/Compat.lua` | Modify | Container/money/inventory/currency-list/interaction shims. |
| `core/Database.lua` | Modify | Migration v11; `NS.State.upgradedFrom`. |
| `defaults/Global.lua` | Modify | `holdings`, `daily`, `ledgerSince`, `resetPrompt`. |
| `defaults/Profile.lua` | Modify | `settings.trackLedger = true`. |
| `modules/Scanner.lua` | Create | Container reads → count maps + links. |
| `modules/Holdings.lua` | Create | `db.global.holdings` store + query/search API. |
| `modules/Reconciler.lua` | Create | Events, dirty bits, combat deferral, flush, login genesis, `HOLDINGS_CHANGED`. |
| `modules/Browser.lua` | Modify | Tab registry (`B:RegisterTab`). |
| `modules/HoldingsTab.lua` | Create | Holdings tab: model builder (pure) + pooled-row view. |
| `settings/Schema.lua` | Modify | `settings.trackLedger` row. |
| `settings/Slash.lua` | Modify | `KA0S_LOOTHISTORY_LEDGER_RESET` (+ confirm) popups; `/lh holdings <query>`. |
| `core/LootHistory.lua` | Modify | `OnEnterWorld`: login scan + reset offer. |
| `core/LifecycleSetup.lua` | Modify | StandUp/StandDown include Reconciler, HoldingsTab. |
| `LootHistory.toc` | Modify | Add new files in dependency order. |
| `tests/wow_mock.lua` | Modify | Container/money/bank/inventory/currency-list mocks. |
| `tests/test_ledger.lua`, `tests/test_scanner.lua`, `tests/test_holdings.lua`, `tests/test_reconciler.lua`, `tests/test_holdingstab.lua`, `tests/test_resetprompt.lua` | Create | Suites. |
| `tests/run.lua` | Modify | Register suites. |
| `tests/test_database.lua`, `tests/test_profiles.lua`, `tests/test_disabled.lua` | Modify | v11 target; new module in teardown list. |
| docs (`scope.md`, `schema.md`, `module-map.md`, `message-bus.md`, `data-flow.md`, `ARCHITECTURE.md`, `smoke-tests.md`, `browser.md`, `test-cases.md`) | Modify | Task 10. |

---

### Task 1: Pure ledger core and row accessors

**Files:**
- Create: `core/Ledger.lua`
- Modify: `core/Constants.lua` (append after `C.CURRENCY_TYPE`, ~line 52)
- Modify: `core/Util.lua` (append)
- Modify: `LootHistory.toc` (add `core\Ledger.lua` directly after `core\Util.lua`)
- Create: `tests/test_ledger.lua`
- Modify: `tests/run.lua` (add `"test_ledger"` after `"test_util"` in `SUITES`)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `NS.Constants.Dir = { IN="IN", OUT="OUT", MOVE="MOVE" }`
  - `NS.Constants.Kind = { ITEM="ITEM", CURRENCY="CURRENCY", GOLD="GOLD" }`
  - `NS.Constants.Container = { BAGS="bags", EQUIPPED="equipped", BANK="bank", MAIL="mail", AUCTIONS="auctions", TABS="tabs" }`
  - `NS.Constants.WARBAND_HOLDER = "§warband"`
  - `NS.Ledger.ThingKey(kind, id) -> string` (`"g"`, `"c:<id>"`, `"i:<id>"`)
  - `NS.Ledger.ParseThingKey(key) -> kind, id|nil`
  - `NS.Ledger.DirSign = { IN=1, OUT=-1, MOVE=0 }`
  - `NS.Ledger.Diff(old, new) -> { {key=<k>, delta=<n>}, ... }` sorted by key (keys compared with `tostring`), zero deltas omitted; nil maps treated as empty.
  - `NS.Util.RowDir(r) -> "IN"|"OUT"|"MOVE"`, `NS.Util.RowKind(r) -> "ITEM"|"CURRENCY"|"GOLD"`, `NS.Util.RowHolder(r) -> string|nil`

- [ ] **Step 1: Write the failing test** — `tests/test_ledger.lua`

```lua
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

test("Ledger: ThingKey round-trips for every kind", function()
  local L, K = NS.Ledger, NS.Constants.Kind
  assertEqual(L.ThingKey(K.GOLD), "g")
  assertEqual(L.ThingKey(K.CURRENCY, 3008), "c:3008")
  assertEqual(L.ThingKey(K.ITEM, 211296), "i:211296")
  local k, id = L.ParseThingKey("c:3008"); assertEqual(k, K.CURRENCY); assertEqual(id, 3008)
  k, id = L.ParseThingKey("i:211296");     assertEqual(k, K.ITEM);     assertEqual(id, 211296)
  k, id = L.ParseThingKey("g");            assertEqual(k, K.GOLD);     assertEqual(id, nil)
  assertEqual(L.ParseThingKey("x:1"), nil)
end)

test("Ledger: Diff reports signed deltas, sorted, zeros omitted", function()
  local d = NS.Ledger.Diff({ [5] = 3, [2] = 10, [9] = 1 }, { [5] = 3, [2] = 4, [7] = 6 })
  assertEqual(#d, 3)
  assertEqual(d[1].key, 2); assertEqual(d[1].delta, -6)
  assertEqual(d[2].key, 7); assertEqual(d[2].delta, 6)
  assertEqual(d[3].key, 9); assertEqual(d[3].delta, -1)
end)

test("Ledger: Diff treats nil maps as empty", function()
  assertEqual(#NS.Ledger.Diff(nil, nil), 0)
  local d = NS.Ledger.Diff(nil, { [1] = 2 })
  assertEqual(d[1].key, 1); assertEqual(d[1].delta, 2)
end)

test("Ledger: DirSign totals", function()
  local s = NS.Ledger.DirSign
  assertEqual(s.IN, 1); assertEqual(s.OUT, -1); assertEqual(s.MOVE, 0)
end)

test("Util: row accessors give legacy defaults", function()
  local U = NS.Util
  local legacyItem = { itemID = 1, char = "A-Realm" }
  local legacyCur  = { currencyID = 3008, char = "A-Realm" }
  assertEqual(U.RowDir(legacyItem), "IN")
  assertEqual(U.RowKind(legacyItem), "ITEM")
  assertEqual(U.RowKind(legacyCur), "CURRENCY")
  assertEqual(U.RowHolder(legacyItem), "A-Realm")
  local gold = { kind = "GOLD", dir = "OUT", holder = "§warband", char = "A-Realm" }
  assertEqual(U.RowDir(gold), "OUT"); assertEqual(U.RowKind(gold), "GOLD")
  assertEqual(U.RowHolder(gold), "§warband")
end)

test("Constants: ledger enums and warband key", function()
  local C = NS.Constants
  assertEqual(C.WARBAND_HOLDER, "§warband")
  assertEqual(C.Container.TABS, "tabs")
  assertTrue(C.Dir.MOVE == "MOVE" and C.Kind.GOLD == "GOLD")
end)
```

Add `"test_ledger"` to `SUITES` in `tests/run.lua` right after `"test_util"`.

- [ ] **Step 2: Run to verify it fails**

Run: `lua tests/run.lua 2>&1 | tail -20`
Expected: FAIL — `test_ledger` cases error on `NS.Ledger` / `NS.Constants.Kind` being nil (and the harness may also report the suite file present but the TOC unchanged — fine).

- [ ] **Step 3: Implement**

`core/Constants.lua` — append after `C.CURRENCY_TYPE = "Currency"`:

```lua
-- ── Ledger enums (timeline-ledger spec §3/§4.1) ──────────────────────────────────────────────
-- Stored strings, part of the export contract: never rename a member, only append.
C.Dir  = { IN = "IN", OUT = "OUT", MOVE = "MOVE" }
C.Kind = { ITEM = "ITEM", CURRENCY = "CURRENCY", GOLD = "GOLD" }
-- Where a holder keeps a thing. Values are the column keys inside db.global.holdings[h].items[id].
C.Container = {
  BAGS = "bags", EQUIPPED = "equipped", BANK = "bank",
  MAIL = "mail", AUCTIONS = "auctions", TABS = "tabs",
}
-- The virtual holder for the warband bank, warband gold and account-wide currencies. `§` marks a
-- system key (BagSync's convention): code that means "characters" skips keys starting with it.
C.WARBAND_HOLDER = "§warband"
```

`core/Ledger.lua`:

```lua
local _, NS = ...
NS.Ledger = NS.Ledger or {}
local Ledger = NS.Ledger

-- Pure ledger primitives: no WoW API, no SavedVariables. Everything the Reconciler decides is built
-- from these so it can be pinned headless (timeline-ledger spec §5.1).

local KIND_PREFIX = { ITEM = "i:", CURRENCY = "c:" }
local PREFIX_KIND = { i = "ITEM", c = "CURRENCY" }

function Ledger.ThingKey(kind, id)
  if kind == "GOLD" then return "g" end
  return KIND_PREFIX[kind] .. tostring(id)
end

function Ledger.ParseThingKey(key)
  if key == "g" then return "GOLD", nil end
  local p, id = tostring(key):match("^([ic]):(%d+)$")
  if not p then return nil end
  return PREFIX_KIND[p], tonumber(id)
end

Ledger.DirSign = { IN = 1, OUT = -1, MOVE = 0 }

local function byKey(a, b) return tostring(a.key) < tostring(b.key) end

-- Signed per-key change from `old` to `new` ({[key]=count} maps; nil reads as empty). Sorted by key so
-- callers and tests can index the result; a key whose count did not move is omitted.
function Ledger.Diff(old, new)
  old, new = old or {}, new or {}
  local out = {}
  for k, n in pairs(new) do
    local d = n - (old[k] or 0)
    if d ~= 0 then out[#out + 1] = { key = k, delta = d } end
  end
  for k, o in pairs(old) do
    if new[k] == nil and o ~= 0 then out[#out + 1] = { key = k, delta = -o } end
  end
  table.sort(out, byKey)
  return out
end
```

> Note: `tostring` sort means numeric keys sort lexically (`"10" < "2"`). The test above uses single-digit keys; that is intentional — callers only need a *stable* order. Document this in the comment.

`core/Util.lua` — append:

```lua
-- Row accessors (timeline-ledger spec §4.1). Rows written before schema v11 carry none of `dir`,
-- `kind`, `holder`; they were all gains, recorded by `char`. No consumer reads the raw fields.
function Util.RowDir(r) return r.dir or "IN" end
function Util.RowKind(r)
  if r.kind then return r.kind end
  if r.itemID == nil and r.currencyID ~= nil then return "CURRENCY" end
  return "ITEM"
end
function Util.RowHolder(r) return r.holder or r.char end
```

`LootHistory.toc` — add `core\Ledger.lua` on the line after `core\Util.lua` (inside the CONVENTIONAL core run; update that comment's "six" count to "seven" and list Ledger).

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: all suites PASS (test_harness confirms the TOC-derived load list includes `core/Ledger.lua`); luacheck `0 warnings / 0 errors`.

- [ ] **Step 5: Regenerate inventory and commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add core/Ledger.lua core/Constants.lua core/Util.lua LootHistory.toc tests/test_ledger.lua tests/run.lua docs/test-cases.md
git commit -m "feat(ledger): pure thing keys, Diff and row accessors (timeline ledger P1)"
```

---

### Task 2: Schema v11 migration and defaults

**Files:**
- Modify: `core/Database.lua` (append to `MIGRATIONS`, ~line 230; `RunMigrations` records `upgradedFrom`)
- Modify: `defaults/Global.lua`
- Modify: `defaults/Profile.lua` (settings block: `trackLedger = true`)
- Modify: `tests/test_database.lua` (every `10` target → `11`; step list gains `10->11`)
- Modify: `tests/test_profiles.lua` (any pinned `schemaVersion` 10 assertions → 11; grep for `10`)
- Test: add v11 cases to `tests/test_database.lua`

**Interfaces:**
- Consumes: none.
- Produces: `db.global.holdings = {}`, `db.global.daily = {}`, `db.global.ledgerSince` (number|nil), `db.global.resetPrompt` (nil|"reset"|"kept"), `NS.State.upgradedFrom` (number|nil — the stamp before this load's migration, only set when < 11), `NS.SCHEMA_VERSION == 11`, `db.profile.settings.trackLedger` (bool, default true).

- [ ] **Step 1: Write the failing tests** — append to `tests/test_database.lua` after the v9->v10 cases, and change the existing `10` targets to `11` (the `assertEqual(..., 10)` lines in the RunMigrations block and the step string to `"1->2 2->3 3->4 4->5 5->6 6->7 7->8 8->9 9->10 10->11"`).

```lua
test("Migrate: v10->v11 creates the ledger stores and rewrites no rows", function()
  local g = NS.db.global
  local savedH, savedHold, savedDaily, savedSince = g.history, g.holdings, g.daily, g.ledgerSince
  local row = { ts = 1, itemID = 4, char = "A-Realm", quantity = 1 }
  g.history, g.holdings, g.daily, g.ledgerSince = { row }, nil, nil, nil
  g.schemaVersion = 10
  NS.State.upgradedFrom = nil
  NS:RunMigrations()
  assertEqual(g.schemaVersion, 11)
  assertEqual(type(g.holdings), "table")
  assertEqual(type(g.daily), "table")
  assertEqual(type(g.ledgerSince), "number")
  assertEqual(NS.State.upgradedFrom, 10)
  assertTrue(g.history[1] == row)
  assertEqual(row.dir, nil); assertEqual(row.kind, nil); assertEqual(row.holder, nil)
  g.history, g.holdings, g.daily, g.ledgerSince = savedH, savedHold, savedDaily, savedSince
end)

test("Migrate: v11 step is idempotent and keeps existing holdings", function()
  local g = NS.db.global
  local savedHold, savedSince = g.holdings, g.ledgerSince
  g.holdings = { ["A-Realm"] = { money = 5 } }
  g.ledgerSince = 123
  g.schemaVersion = 10
  NS:RunMigrations()
  assertEqual(g.holdings["A-Realm"].money, 5)
  assertEqual(g.ledgerSince, 123)
  g.holdings, g.ledgerSince = savedHold, savedSince
end)

test("Migrate: an already-current DB does not set upgradedFrom", function()
  NS.State.upgradedFrom = nil
  NS.db.global.schemaVersion = 11
  NS:RunMigrations()
  assertEqual(NS.State.upgradedFrom, nil)
end)

test("Defaults: trackLedger defaults on; resetPrompt undeclared", function()
  assertEqual(NS.defaults.profile.settings.trackLedger, true)
  assertEqual(NS.defaults.global.resetPrompt, nil)
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -E "FAIL|v11|passed" | head -20`
Expected: FAIL on the v10→v11 cases and on every updated `11` assertion.

- [ ] **Step 3: Implement**

`core/Database.lua` — append inside `MIGRATIONS`, after the `to = 10` entry:

```lua
  -- v10 -> v11: the timeline ledger (docs/superpowers/specs/2026-10-06-timeline-ledger-design.md
  -- §9.1). Creates the holdings and daily-rollup stores and records when ledger capture began.
  -- REWRITES NO ROW: every legacy row was a gain recorded by `char`, which is exactly what the
  -- NS.Util.Row* accessors default to, so stamping `dir`/`kind`/`holder` would only bloat the file.
  -- Idempotent: an existing store or stamp is kept.
  { to = 11, apply = function(g)
    g.holdings = g.holdings or {}
    g.daily = g.daily or {}
    g.ledgerSince = g.ledgerSince or time()
    return 0
  end },
```

In `NS:RunMigrations`, record the pre-migration stamp **before** the loop:

```lua
  g.schemaVersion = g.schemaVersion or 0
  if g.schemaVersion < 11 then NS.State.upgradedFrom = g.schemaVersion end
```

`defaults/Global.lua` — add inside `NS.defaults.global` after `history = {}` (keep the house comment style; update the stamp comment's "10 today" to "11 today"):

```lua
  -- Timeline ledger stores (schema v11). holdings[holder] is what each character and the virtual
  -- "§warband" holder currently owns; daily[day][holder][thingKey] is the sparse rollup Phase 3 reads.
  holdings = {},
  daily = {},
  -- ledgerSince (ts the v11 step ran) and resetPrompt (nil | "reset" | "kept") are deliberately NOT
  -- declared: AceDB would strip a value equal to its default and backfill it onto old accounts.
```

`defaults/Profile.lua` — in `settings`, after `recordCurrency`:

```lua
    trackLedger      = true,   -- holdings + (Phase 2) gains/losses/transfers/gold; off = legacy gains-only
```

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS, 0/0. If `tests/test_profiles.lua` pins `10`, update those to `11` (grep `schemaVersion` there) and re-run.

- [ ] **Step 5: Commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add core/Database.lua defaults/Global.lua defaults/Profile.lua tests/test_database.lua tests/test_profiles.lua docs/test-cases.md
git commit -m "feat(db): schema v11 — holdings/daily stores, ledgerSince, trackLedger default"
```

---

### Task 3: Compat shims and mock support for containers, money, inventory, currency list

**Files:**
- Modify: `core/Compat.lua` (append a `-- ── Holdings reads ──` section)
- Modify: `core/Constants.lua` (bag-id groups, equip slots)
- Modify: `tests/wow_mock.lua` (container/money/bank/inventory/currency-list fakes)
- Modify: `.luacheckrc` `read_globals` (add `GetMoney`, `GetCursorMoney`, `GetPlayerTradeMoney`, `C_Bank`, `Enum`, `GetInventoryItemID`, `GetInventoryItemLink`, `INVSLOT_FIRST_EQUIPPED`, `INVSLOT_LAST_EQUIPPED` — only those not already present)
- Modify: `docs/compat-layer.md` (surface table rows for each new shim)
- Test: `tests/test_compat.lua` (append)

**Interfaces:**
- Produces:
  - `NS.Constants.BAG_IDS`, `NS.Constants.BANK_IDS`, `NS.Constants.WARBAND_TAB_IDS` (sorted number arrays, derived from `Enum.BagIndex` names)
  - `NS.Constants.EQUIP_SLOTS` (array of inventory slot ids: `INVSLOT_FIRST_EQUIPPED..INVSLOT_LAST_EQUIPPED`, default 1..19)
  - `NS.Compat.GetContainerNumSlots(bagID) -> n` (0 when absent)
  - `NS.Compat.GetContainerSlot(bagID, slot) -> {itemID, link, count}|nil`
  - `NS.Compat.GetMoney() -> copper` (`GetMoney() - GetCursorMoney() - GetPlayerTradeMoney()`, missing parts read 0)
  - `NS.Compat.GetWarbandMoney() -> copper|nil`
  - `NS.Compat.GetInventoryItem(slot) -> itemID|nil, link|nil`
  - `NS.Compat.BagInventorySlot(bagID) -> invSlot|nil` (`C_Container.ContainerIDToInventoryID`)
  - `NS.Compat.ListCurrencies() -> { {id=, quantity=, accountWide=bool}, ... }` (expands collapsed headers, restores them)
  - `NS.Compat.InteractionType(name) -> number|nil` (`Enum.PlayerInteractionType[name]`)
  - Mock seams on `T.mocks`: `__bags[bagID] = { [slot] = {itemID=, link=, count=} }` with `__bagSlots[bagID] = n`; `__money`, `__warbandMoney`, `__inventory[slot] = {itemID=, link=}`, `__currencyList = { {id=, quantity=, accountWide=, header=bool, collapsed=bool} }`.

- [ ] **Step 1: Write the failing tests** — append to `tests/test_compat.lua`

```lua
test("Compat: bag-id groups come from Enum.BagIndex names, type constants excluded", function()
  local C = NS.Constants
  assertEqual(table.concat(C.BAG_IDS, ","), "0,1,2,3,4,5")
  assertEqual(table.concat(C.BANK_IDS, ","), "6,7,8,9,10,11")
  assertEqual(table.concat(C.WARBAND_TAB_IDS, ","), "12,13,14,15,16")
end)

test("Compat: container slot read and empty slot", function()
  local m = T.mocks
  m.__bagSlots[0] = 2
  m.__bags[0] = { [1] = { itemID = 7, link = "|Hitem:7|h[Seven]|h", count = 3 } }
  assertEqual(NS.Compat.GetContainerNumSlots(0), 2)
  local s = NS.Compat.GetContainerSlot(0, 1)
  assertEqual(s.itemID, 7); assertEqual(s.count, 3)
  assertEqual(NS.Compat.GetContainerSlot(0, 2), nil)
  m.__bags[0], m.__bagSlots[0] = {}, 0
end)

test("Compat: GetMoney nets cursor and trade money", function()
  local m = T.mocks
  m.__money, m.__cursorMoney, m.__tradeMoney = 1000, 100, 50
  assertEqual(NS.Compat.GetMoney(), 850)
  m.__cursorMoney, m.__tradeMoney = 0, 0
end)

test("Compat: GetWarbandMoney reads the account bank, nil when API absent", function()
  local m = T.mocks
  m.__warbandMoney = 777
  assertEqual(NS.Compat.GetWarbandMoney(), 777)
  local saved = m.C_Bank; m.C_Bank = nil; _G.C_Bank = nil
  assertEqual(NS.Compat.GetWarbandMoney(), nil)
  m.C_Bank = saved; _G.C_Bank = saved
end)

test("Compat: ListCurrencies expands collapsed headers and restores them", function()
  local m = T.mocks
  m.__currencyList = {
    { header = true, collapsed = true, name = "Midnight" },
    { id = 3008, quantity = 40, accountWide = false },
    { id = 2032, quantity = 5, accountWide = true },
  }
  local list = NS.Compat.ListCurrencies()
  assertEqual(#list, 2)
  assertEqual(list[1].id, 3008); assertEqual(list[1].quantity, 40)
  assertEqual(list[2].accountWide, true)
  assertTrue(m.__currencyList[1].collapsed)   -- restored
end)
```

(If `tests/test_compat.lua` doesn't bind `T` / `assertTrue` locally, add them at its top as the other suites do.)

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -A3 "Compat:" | head -30`
Expected: FAIL (`C.BAG_IDS` nil, `__bags` nil, etc.).

- [ ] **Step 3: Implement the mock** — `tests/wow_mock.lua`, after the currency block:

```lua
  -- ── holdings reads (timeline ledger) ───────────────────────────────────────
  -- Enum.BagIndex as 12.0.7 ships it, INCLUDING the two type constants (-2/-3) the name patterns
  -- must not scoop up (BankLedger's double-count bug).
  M.Enum = M.Enum or {}
  M.Enum.BagIndex = {
    Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5,
    CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8,
    CharacterBankTab_4 = 9, CharacterBankTab_5 = 10, CharacterBankTab_6 = 11,
    AccountBankTab_1 = 12, AccountBankTab_2 = 13, AccountBankTab_3 = 14,
    AccountBankTab_4 = 15, AccountBankTab_5 = 16,
    Characterbanktab = -2, Accountbanktab = -3,
  }
  M.Enum.BankType = { Character = 0, Guild = 1, Account = 2 }
  M.Enum.PlayerInteractionType = { Banker = 8, AccountBanker = 68, MailInfo = 17, Auctioneer = 21, Merchant = 5, GuildBanker = 10 }
  M.__bags, M.__bagSlots = {}, {}
  M.C_Container = M.C_Container or {}
  M.C_Container.GetContainerNumSlots = function(bag) return M.__bagSlots[bag] or 0 end
  M.C_Container.GetContainerItemInfo = function(bag, slot)
    local s = M.__bags[bag] and M.__bags[bag][slot]
    if not s then return nil end
    return { itemID = s.itemID, hyperlink = s.link, stackCount = s.count }
  end
  M.C_Container.ContainerIDToInventoryID = function(bag) if bag >= 1 and bag <= 5 then return 30 + bag end end
  M.__money, M.__cursorMoney, M.__tradeMoney, M.__warbandMoney = 0, 0, 0, 0
  M.GetMoney = function() return M.__money end
  M.GetCursorMoney = function() return M.__cursorMoney end
  M.GetPlayerTradeMoney = function() return M.__tradeMoney end
  M.C_Bank = { FetchDepositedMoney = function(t) if t == 2 then return M.__warbandMoney end end }
  M.INVSLOT_FIRST_EQUIPPED, M.INVSLOT_LAST_EQUIPPED = 1, 19
  M.__inventory = {}
  M.GetInventoryItemID = function(_, slot) return M.__inventory[slot] and M.__inventory[slot].itemID end
  M.GetInventoryItemLink = function(_, slot) return M.__inventory[slot] and M.__inventory[slot].link end
  -- The currency LIST (the window), distinct from the by-id lookups above. Collapsed headers hide
  -- their children from GetCurrencyListSize exactly as the client does.
  M.__currencyList = {}
  local function visible()
    local out, hidden = {}, false
    for _, e in ipairs(M.__currencyList) do
      if e.header then out[#out + 1] = e; hidden = e.collapsed
      elseif not hidden then out[#out + 1] = e end
    end
    return out
  end
  M.C_CurrencyInfo.GetCurrencyListSize = function() return #visible() end
  M.C_CurrencyInfo.GetCurrencyListInfo = function(i)
    local e = visible()[i]; if not e then return nil end
    return { name = e.name, isHeader = e.header or false, isHeaderExpanded = not e.collapsed,
             quantity = e.quantity, isAccountWide = e.accountWide }
  end
  M.C_CurrencyInfo.GetCurrencyListLink = function(i)
    local e = visible()[i]; if e and e.id then return "|Hcurrency:" .. e.id .. "::|h[x]|h" end
  end
  M.C_CurrencyInfo.ExpandCurrencyList = function(i, expand)
    local e = visible()[i]; if e and e.header then e.collapsed = not expand end
  end
```

> The existing currency-category tests read `GetCurrencyListSize/Info/Link` from the earlier mock. Keep those working: if `M.__currencyList` is empty, fall back to the previous three-entry fixture. Implement by seeding `M.__currencyList` with that fixture (`{header=true,name="The War Within"}, {id=3008,...}, {id=2914,...}`) instead of `{}`, and have the new test restore it after mutating.

- [ ] **Step 4: Implement Constants and Compat**

`core/Constants.lua` — append:

```lua
-- ── Container id groups (copied from BankLedger core/Constants.lua, which paid for the lesson) ──
-- Derived BY MEMBER NAME from Enum.BagIndex, never by number: Blizzard renumbers between builds,
-- and 12.0.7 also carries type constants (Characterbanktab = -2, Accountbanktab = -3) a loose
-- pattern would scoop up. Anchored, case-sensitive patterns only.
local GROUP_PATTERNS = {
  BAGS = { "^Backpack$", "^Bag_%d+$", "^ReagentBag$" },
  BANK = { "^Bank$", "^BankBag_%d+$", "^CharacterBankTab_%d+$" },
  TABS = { "^AccountBankTab_%d+$" },
}
local function idsMatching(patterns)
  local seen, ids = {}, {}
  local members = Enum and Enum.BagIndex
  if type(members) == "table" then
    for name, value in pairs(members) do
      if type(value) == "number" then
        for _, pattern in ipairs(patterns) do
          if name:match(pattern) and not seen[value] then seen[value] = true; ids[#ids + 1] = value; break end
        end
      end
    end
  end
  table.sort(ids)
  return ids
end
C.BAG_IDS         = idsMatching(GROUP_PATTERNS.BAGS)
C.BANK_IDS        = idsMatching(GROUP_PATTERNS.BANK)
C.WARBAND_TAB_IDS = idsMatching(GROUP_PATTERNS.TABS)
if #C.BAG_IDS == 0 then C.BAG_IDS = { 0, 1, 2, 3, 4, 5 } end

C.EQUIP_SLOTS = {}
for s = (INVSLOT_FIRST_EQUIPPED or 1), (INVSLOT_LAST_EQUIPPED or 19) do C.EQUIP_SLOTS[#C.EQUIP_SLOTS + 1] = s end
```

> Constants loads before the harness kicks anything, but `Enum` is a mock global by then (mock is built before load). Confirm with the test; if `Enum.BagIndex` is not visible at Constants load time in the client (it is — `Enum` is a client global), nothing changes.

`core/Compat.lua` — append:

```lua
-- ── Holdings reads (timeline ledger, spec §3) ─────────────────────────────────────────────────
function Compat.GetContainerNumSlots(bagID)
  local fn = C_Container and C_Container.GetContainerNumSlots
  return fn and (fn(bagID) or 0) or 0
end

function Compat.GetContainerSlot(bagID, slot)
  local fn = C_Container and C_Container.GetContainerItemInfo
  if not fn then return nil end
  local info = fn(bagID, slot)
  if not info or not info.itemID then return nil end
  return { itemID = info.itemID, link = info.hyperlink, count = info.stackCount or 1 }
end

-- Purse money as the player owns it: copper on the cursor or staged in an open trade window is
-- still theirs (BagSync events.lua's formula).
function Compat.GetMoney()
  if type(GetMoney) ~= "function" then return 0 end
  local cursor = type(GetCursorMoney) == "function" and GetCursorMoney() or 0
  local trade = type(GetPlayerTradeMoney) == "function" and GetPlayerTradeMoney() or 0
  return (GetMoney() or 0) - (cursor or 0) - (trade or 0)
end

function Compat.GetWarbandMoney()
  local fn = C_Bank and C_Bank.FetchDepositedMoney
  local t = Enum and Enum.BankType and Enum.BankType.Account
  if type(fn) ~= "function" or t == nil then return nil end
  return fn(t)
end

function Compat.GetInventoryItem(slot)
  if type(GetInventoryItemID) ~= "function" then return nil end
  local id = GetInventoryItemID("player", slot)
  if not id then return nil end
  return id, type(GetInventoryItemLink) == "function" and GetInventoryItemLink("player", slot) or nil
end

function Compat.BagInventorySlot(bagID)
  local fn = C_Container and C_Container.ContainerIDToInventoryID
  return fn and fn(bagID) or nil
end

function Compat.InteractionType(name)
  local e = Enum and Enum.PlayerInteractionType
  return e and e[name] or nil
end

-- Every currency the character has, with its quantity. The client's list hides the children of a
-- collapsed header, so collapsed headers are expanded for the walk and collapsed again after,
-- last-to-first so indices stay valid (BagSync scanner.lua does the same).
function Compat.ListCurrencies()
  local CI = C_CurrencyInfo
  if not (CI and CI.GetCurrencyListSize and CI.GetCurrencyListInfo and CI.GetCurrencyListLink) then return {} end
  local expanded = {}
  local i = 1
  while i <= CI.GetCurrencyListSize() do
    local info = CI.GetCurrencyListInfo(i)
    if info and info.isHeader and not info.isHeaderExpanded and CI.ExpandCurrencyList then
      CI.ExpandCurrencyList(i, true); expanded[#expanded + 1] = i
    end
    i = i + 1
  end
  local out = {}
  for j = 1, CI.GetCurrencyListSize() do
    local info = CI.GetCurrencyListInfo(j)
    if info and not info.isHeader then
      local id = Compat.CurrencyLinkID(CI.GetCurrencyListLink(j))
      if id then out[#out + 1] = { id = id, quantity = info.quantity or 0, accountWide = info.isAccountWide == true } end
    end
  end
  for k = #expanded, 1, -1 do CI.ExpandCurrencyList(expanded[k], false) end
  return out
end
```

Add the new globals to `.luacheckrc` `read_globals` (only the missing ones). Add one row per shim to the `## Compat.* surface` table in `docs/compat-layer.md` (Wraps / Why columns, same voice as neighbors).

- [ ] **Step 5: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS, 0/0. Existing currency-category tests still PASS (fixture preserved).

- [ ] **Step 6: Commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add core/Compat.lua core/Constants.lua tests/wow_mock.lua tests/test_compat.lua .luacheckrc docs/compat-layer.md docs/test-cases.md
git commit -m "feat(compat): container, money, inventory and currency-list reads for holdings"
```

---

### Task 4: Scanner

**Files:**
- Create: `modules/Scanner.lua`
- Modify: `LootHistory.toc` (after `modules\Filters.lua`, before `modules\Collector.lua`)
- Create: `tests/test_scanner.lua`; register `"test_scanner"` after `"test_compat"` in `tests/run.lua`

**Interfaces:**
- Consumes: Task 3 Compat shims and Constants.
- Produces:
  - `NS.Scanner.ScanContainers(ids) -> counts {[itemID]=n}, links {[itemID]=link}`
  - `NS.Scanner.ScanEquipped() -> counts, links` (equip slots + equipped bag items for bags 1..5)
  - `NS.Scanner.ScanCurrencies() -> charMap {[id]=n}, warbandMap {[id]=n}` (account-wide → warband)
  - `NS.Scanner.ReadMoney() -> copper`; `NS.Scanner.ReadWarbandMoney() -> copper|nil`

- [ ] **Step 1: Write the failing test** — `tests/test_scanner.lua`

```lua
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual = T.test, T.assertEqual

local function withBags(bags, fn)
  local m = T.mocks
  local savedB, savedS = m.__bags, m.__bagSlots
  m.__bags, m.__bagSlots = {}, {}
  for id, slots in pairs(bags) do
    m.__bags[id] = slots
    local n = 0; for s in pairs(slots) do if s > n then n = s end end
    m.__bagSlots[id] = n
  end
  fn()
  m.__bags, m.__bagSlots = savedB, savedS
end

test("Scanner: variants sum by itemID across slots and bags", function()
  withBags({
    [0] = { [1] = { itemID = 50, link = "|Hitem:50::::::::1:::1:100|h[Blade]|h", count = 1 },
            [3] = { itemID = 50, link = "|Hitem:50::::::::1:::1:200|h[Blade]|h", count = 1 } },
    [1] = { [2] = { itemID = 60, link = "|Hitem:60|h[Herb]|h", count = 20 } },
  }, function()
    local counts, links = NS.Scanner.ScanContainers({ 0, 1, 2 })
    assertEqual(counts[50], 2)
    assertEqual(counts[60], 20)
    assertEqual(links[60], "|Hitem:60|h[Herb]|h")
  end)
end)

test("Scanner: equipped slots and equipped bags", function()
  local m = T.mocks
  m.__inventory = { [1] = { itemID = 900, link = "L900" }, [31] = { itemID = 901, link = "L901" } }
  local counts = NS.Scanner.ScanEquipped()
  assertEqual(counts[900], 1)
  assertEqual(counts[901], 1)
  m.__inventory = {}
end)

test("Scanner: currencies split account-wide to warband", function()
  local m = T.mocks
  local saved = m.__currencyList
  m.__currencyList = {
    { header = true, name = "H" },
    { id = 3008, quantity = 40, accountWide = false },
    { id = 2032, quantity = 5, accountWide = true },
    { id = 1, quantity = 0, accountWide = false },
  }
  local char, wb = NS.Scanner.ScanCurrencies()
  assertEqual(char[3008], 40); assertEqual(char[2032], nil)
  assertEqual(wb[2032], 5)
  assertEqual(char[1], nil)   -- zero quantities are not holdings
  m.__currencyList = saved
end)

test("Scanner: money reads", function()
  T.mocks.__money, T.mocks.__warbandMoney = 12345, 999
  assertEqual(NS.Scanner.ReadMoney(), 12345)
  assertEqual(NS.Scanner.ReadWarbandMoney(), 999)
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -A2 "Scanner:" | head`
Expected: FAIL (`NS.Scanner` nil).

- [ ] **Step 3: Implement** — `modules/Scanner.lua`

```lua
local _, NS = ...
NS.Scanner = NS.Scanner or {}
local Scanner = NS.Scanner

-- Container reads -> count maps. Stateless and side-effect free: what to scan and when is the
-- Reconciler's business; this file only answers "what is in these containers right now". Counts are
-- keyed by BASE itemID (spec §3): two ilvl variants of one id are one holding. The first hyperlink
-- seen per id is kept for display (GetItemInfo(id) only knows the base item).

local Compat = NS.Compat

function Scanner.ScanContainers(ids)
  local counts, links = {}, {}
  for _, bagID in ipairs(ids) do
    for slot = 1, Compat.GetContainerNumSlots(bagID) do
      local s = Compat.GetContainerSlot(bagID, slot)
      if s then
        counts[s.itemID] = (counts[s.itemID] or 0) + s.count
        if s.link and not links[s.itemID] then links[s.itemID] = s.link end
      end
    end
  end
  return counts, links
end

local function addEquipped(counts, links, id, link)
  if not id then return end
  counts[id] = (counts[id] or 0) + 1
  if link and not links[id] then links[id] = link end
end

-- Worn gear plus the bag items sitting in the bag slots: swapping either must read as a transfer,
-- not as a loss from bags (Phase 2 classification relies on this column existing).
function Scanner.ScanEquipped()
  local counts, links = {}, {}
  for _, slot in ipairs(NS.Constants.EQUIP_SLOTS) do addEquipped(counts, links, Compat.GetInventoryItem(slot)) end
  for bagID = 1, 5 do
    local inv = Compat.BagInventorySlot(bagID)
    if inv then addEquipped(counts, links, Compat.GetInventoryItem(inv)) end
  end
  return counts, links
end

function Scanner.ScanCurrencies()
  local char, warband = {}, {}
  for _, c in ipairs(Compat.ListCurrencies()) do
    if c.quantity > 0 then
      if c.accountWide then warband[c.id] = c.quantity else char[c.id] = c.quantity end
    end
  end
  return char, warband
end

function Scanner.ReadMoney() return Compat.GetMoney() end
function Scanner.ReadWarbandMoney() return Compat.GetWarbandMoney() end
```

> `ScanEquipped` with the mock: `ContainerIDToInventoryID(1) == 31`, and the test puts item 901 at slot 31. Slot 31 is not in `EQUIP_SLOTS` (1..19), so it is counted once.

Add `modules\Scanner.lua` to the TOC after `modules\Filters.lua`.

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS, 0/0.

- [ ] **Step 5: Commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add modules/Scanner.lua LootHistory.toc tests/test_scanner.lua tests/run.lua docs/test-cases.md
git commit -m "feat(holdings): Scanner reads bags, bank, tabs, equipped, currencies, money"
```

---

### Task 5: Holdings store

**Files:**
- Create: `modules/Holdings.lua`
- Modify: `LootHistory.toc` (after `modules\Scanner.lua`)
- Create: `tests/test_holdings.lua`; register `"test_holdings"` after `"test_scanner"`

**Interfaces:**
- Consumes: `NS.Constants.Container`, `WARBAND_HOLDER`, `Kind`; `NS.Ledger.ThingKey/ParseThingKey`; `NS.Compat.GetItemInfo(link)` (existing: returns `itemID, name, quality, classID`); `NS.Compat.GetCurrencyInfoFromLink` / `C_CurrencyInfo` via existing `NS.Compat.CurrencyQuality`/`CurrencyCategory`.
- Produces (all on `NS.Holdings`):
  - `:Store() -> db.global.holdings`
  - `:Get(holder, create) -> entry|nil` — entry `{ meta={classFile,genesis,partial,lastSeen}, scanned={}, items={}, currency={}, money=nil, links={} }`
  - `:ApplyContainer(holder, container, counts, links, ts) -> changed:boolean` — replaces that container's column for every item; drops zero rows
  - `:ApplyCurrency(holder, map, ts) -> changed` — replaces `currency`
  - `:ApplyMoney(holder, copper, ts) -> changed`
  - `:MarkGenesis(holder, ts)` — sets `meta.genesis` once; `meta.partial = (scanned.bank == nil)` for characters, `(scanned.tabs == nil)` for warband
  - `:ItemCounts(holder) -> {[itemID]=total across containers}`
  - `:Holders() -> sorted array of holder keys` (characters alphabetically, `§warband` last)
  - `:Total(thingKey) -> total, rows` where `rows = { {holder=, count=, containers={[c]=n}|nil, scannedAt=oldest ts of contributing containers} }` sorted by count desc
  - `:Search(filter) -> { {key=, kind=, id=, name=, quality=, itemType=, itemSubType=, total=, holders=rows}, ... }` — filter fields honored: `text` (case-insensitive substring of name), `quality` (set `{[q]=true}`), `itemType` (set), `itemSubType` (set), `char` (set of holder keys; `"§warband"` allowed). Gold row (`key="g"`) included when `text` is empty or matches the localized word "Gold". Sorted by name.
  - `:ForgetHolder(holder) -> boolean`

- [ ] **Step 1: Write the failing test** — `tests/test_holdings.lua`

```lua
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local function fresh() NS.db.global.holdings = {} end
local H = function() return NS.Holdings end

test("Holdings: ApplyContainer replaces one column and keeps others", function()
  fresh()
  H():ApplyContainer("A-Realm", "bags", { [1] = 5, [2] = 1 }, {}, 100)
  H():ApplyContainer("A-Realm", "bank", { [1] = 10 }, {}, 100)
  assertTrue(H():ApplyContainer("A-Realm", "bags", { [1] = 4 }, {}, 200))
  local e = H():Get("A-Realm")
  assertEqual(e.items[1].bags, 4)
  assertEqual(e.items[1].bank, 10)
  assertEqual(e.items[2], nil)               -- item 2 left bags and has no other column
  assertEqual(e.scanned.bags, 200); assertEqual(e.scanned.bank, 100)
end)

test("Holdings: unchanged container reports no change", function()
  fresh()
  H():ApplyContainer("A-Realm", "bags", { [1] = 5 }, {}, 100)
  assertFalse(H():ApplyContainer("A-Realm", "bags", { [1] = 5 }, {}, 150))
end)

test("Holdings: Total sums holders and warband, sorted by count", function()
  fresh()
  H():ApplyContainer("A-Realm", "bags", { [7] = 2 }, {}, 1)
  H():ApplyContainer("B-Realm", "bank", { [7] = 9 }, {}, 1)
  H():ApplyContainer("§warband", "tabs", { [7] = 4 }, {}, 1)
  local total, rows = H():Total("i:7")
  assertEqual(total, 15)
  assertEqual(rows[1].holder, "B-Realm"); assertEqual(rows[1].count, 9)
  assertEqual(rows[3].holder, "A-Realm")
end)

test("Holdings: gold and currency totals", function()
  fresh()
  H():ApplyMoney("A-Realm", 100, 1); H():ApplyMoney("§warband", 50, 1)
  H():ApplyCurrency("A-Realm", { [3008] = 40 }, 1)
  assertEqual((H():Total("g")), 150)
  assertEqual((H():Total("c:3008")), 40)
end)

test("Holdings: genesis is set once; partial until bank seen", function()
  fresh()
  H():ApplyContainer("A-Realm", "bags", { [1] = 1 }, {}, 10)
  H():MarkGenesis("A-Realm", 10)
  H():MarkGenesis("A-Realm", 99)
  local e = H():Get("A-Realm")
  assertEqual(e.meta.genesis, 10); assertTrue(e.meta.partial)
  H():ApplyContainer("A-Realm", "bank", {}, {}, 20)
  H():MarkGenesis("A-Realm", 20)
  assertFalse(e.meta.partial)
end)

test("Holdings: Holders lists characters then warband", function()
  fresh()
  H():ApplyMoney("§warband", 1, 1); H():ApplyMoney("Zed-Realm", 1, 1); H():ApplyMoney("Abe-Realm", 1, 1)
  assertEqual(table.concat(H():Holders(), ","), "Abe-Realm,Zed-Realm,§warband")
end)

test("Holdings: Search keeps uncached items and filters by holder", function()
  fresh()
  H():ApplyContainer("A-Realm", "bags", { [42] = 3 }, {}, 1)          -- no link: uncached
  H():ApplyContainer("B-Realm", "bags", { [43] = 1 }, { [43] = "|Hitem:43|h[Herb]|h" }, 1)
  local all = H():Search({})
  local keys = {}; for _, r in ipairs(all) do keys[r.key] = r end
  assertTrue(keys["i:42"] ~= nil)
  assertTrue(type(keys["i:42"].name) == "string" and #keys["i:42"].name > 0)
  local onlyB = H():Search({ char = { ["B-Realm"] = true } })
  for _, r in ipairs(onlyB) do assertTrue(r.key ~= "i:42") end
end)

test("Holdings: ForgetHolder drops the entry", function()
  fresh()
  H():ApplyMoney("A-Realm", 1, 1)
  assertTrue(H():ForgetHolder("A-Realm"))
  assertEqual(H():Get("A-Realm"), nil)
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -A2 "Holdings:" | head`
Expected: FAIL (`NS.Holdings` nil).

- [ ] **Step 3: Implement** — `modules/Holdings.lua`

```lua
local _, NS = ...
NS.Holdings = NS.Holdings or {}
local Holdings = NS.Holdings

-- The holdings ledger (timeline-ledger spec §4.2): db.global.holdings[holder]. Account-wide; one
-- writer (the Reconciler, through the Apply* calls); every reader goes through this API.

local C = NS.Constants
local WARBAND = C.WARBAND_HOLDER

function Holdings:Store()
  local g = NS.db and NS.db.global
  if not g then return {} end
  g.holdings = g.holdings or {}
  return g.holdings
end

function Holdings:Get(holder, create)
  local s = self:Store()
  local e = s[holder]
  if not e and create then
    e = { meta = {}, scanned = {}, items = {}, currency = {}, links = {} }
    s[holder] = e
  end
  return e
end

function Holdings:ApplyContainer(holder, container, counts, links, ts)
  local e = self:Get(holder, true)
  local changed = false
  for id, row in pairs(e.items) do
    local want = counts[id]
    if row[container] ~= want then
      row[container] = want; changed = true
      if next(row) == nil then e.items[id] = nil end
    end
  end
  for id, n in pairs(counts) do
    local row = e.items[id]
    if not row then row = {}; e.items[id] = row end
    if row[container] ~= n then row[container] = n; changed = true end
  end
  for id, link in pairs(links or {}) do e.links[id] = link end
  e.scanned[container] = ts
  e.meta.lastSeen = ts
  return changed
end

local function sameMap(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

function Holdings:ApplyCurrency(holder, map, ts)
  local e = self:Get(holder, true)
  local changed = not sameMap(e.currency, map)
  e.currency = map
  e.scanned.currency, e.meta.lastSeen = ts, ts
  return changed
end

function Holdings:ApplyMoney(holder, copper, ts)
  local e = self:Get(holder, true)
  local changed = e.money ~= copper
  e.money = copper
  e.scanned.money, e.meta.lastSeen = ts, ts
  return changed
end

function Holdings:MarkGenesis(holder, ts)
  local e = self:Get(holder, true)
  e.meta.genesis = e.meta.genesis or ts
  local gate = (holder == WARBAND) and C.Container.TABS or C.Container.BANK
  e.meta.partial = e.scanned[gate] == nil
end

function Holdings:ItemCounts(holder)
  local e, out = self:Get(holder), {}
  if not e then return out end
  for id, row in pairs(e.items) do
    local n = 0; for _, c in pairs(row) do n = n + c end
    out[id] = n
  end
  return out
end

function Holdings:Holders()
  local chars, hasWarband = {}, false
  for h in pairs(self:Store()) do
    if h == WARBAND then hasWarband = true else chars[#chars + 1] = h end
  end
  table.sort(chars)
  if hasWarband then chars[#chars + 1] = WARBAND end
  return chars
end

-- One holder's count of `thingKey`, with its container split and the oldest scan feeding it.
local function holderCount(e, kind, id)
  if kind == "GOLD" then return e.money or 0, nil, e.scanned.money end
  if kind == "CURRENCY" then return e.currency[id] or 0, nil, e.scanned.currency end
  local row = e.items[id]
  if not row then return 0 end
  local n, oldest, split = 0, nil, {}
  for c, k in pairs(row) do
    n = n + k; split[c] = k
    local t = e.scanned[c]
    if t and (not oldest or t < oldest) then oldest = t end
  end
  return n, split, oldest
end

function Holdings:Total(thingKey, holderSet)
  local kind, id = NS.Ledger.ParseThingKey(thingKey)
  local total, rows = 0, {}
  if not kind then return 0, rows end
  for h, e in pairs(self:Store()) do
    if not holderSet or holderSet[h] then
      local n, split, at = holderCount(e, kind, id)
      if n ~= 0 then
        total = total + n
        rows[#rows + 1] = { holder = h, count = n, containers = split, scannedAt = at }
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.holder < b.holder
  end)
  return total, rows
end

-- Display fields for a thing. Uncached items keep a row: name falls back to the link's bracket text,
-- then to "item:<id>" (Review Focus 2).
local function describe(key, kind, id, link)
  if kind == "GOLD" then return { name = "Gold", itemType = "Gold" } end
  if kind == "CURRENCY" then
    local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
    return { name = (info and info.name) or ("currency:" .. id), quality = NS.Compat.CurrencyQuality(id),
             itemType = C.CURRENCY_TYPE, itemSubType = NS.Compat.CurrencyCategory(id) }
  end
  local _, name, quality = NS.Compat.GetItemInfo(link or ("item:" .. id))
  local itemType, itemSubType
  if C_Item and C_Item.GetItemInfo then
    local _
    _, _, _, _, _, itemType, itemSubType = C_Item.GetItemInfo(link or id)
  end
  return { name = name or ("item:" .. id), quality = quality, itemType = itemType, itemSubType = itemSubType, key = key }
end

local function setPasses(set, v) return not set or next(set) == nil or (v ~= nil and set[v]) end

function Holdings:Search(filter)
  filter = filter or {}
  local holderSet = (filter.char and next(filter.char)) and filter.char or nil
  local text = filter.text and filter.text ~= "" and filter.text:lower() or nil
  local seen, links = {}, {}
  for _, e in pairs(self:Store()) do
    for id in pairs(e.items) do seen["i:" .. id] = true; links[id] = links[id] or e.links[id] end
    for id in pairs(e.currency) do seen["c:" .. id] = true end
    if e.money then seen.g = true end
  end
  local out = {}
  for key in pairs(seen) do
    local kind, id = NS.Ledger.ParseThingKey(key)
    local d = describe(key, kind, id, links[id])
    if (not text or d.name:lower():find(text, 1, true))
      and setPasses(filter.quality, d.quality) and setPasses(filter.itemType, d.itemType)
      and setPasses(filter.itemSubType, d.itemSubType) then
      local total, rows = self:Total(key, holderSet)
      if total ~= 0 then
        out[#out + 1] = { key = key, kind = kind, id = id, name = d.name, quality = d.quality,
          itemType = d.itemType, itemSubType = d.itemSubType, total = total, holders = rows, link = links[id] }
      end
    end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

function Holdings:ForgetHolder(holder)
  local s = self:Store()
  if s[holder] == nil then return false end
  s[holder] = nil
  return true
end
```

> `describe` calls `C_Item.GetItemInfo` directly for type/subtype. Move that read into a `Compat.GetItemTypeInfo(linkOrID) -> itemType, itemSubType` shim (add to `core/Compat.lua` and its doc table) to honor the boundary rule; the code above shows the logic. `C_CurrencyInfo.GetCurrencyInfo` likewise goes through a `Compat.CurrencyName(id)` shim.

Add `modules\Holdings.lua` to the TOC after `modules\Scanner.lua`.

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS, 0/0.

- [ ] **Step 5: Commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add modules/Holdings.lua core/Compat.lua docs/compat-layer.md LootHistory.toc tests/test_holdings.lua tests/run.lua docs/test-cases.md
git commit -m "feat(holdings): account-wide holdings store with totals and search"
```

---

### Task 6: Reconciler (phase-1 scope: keep holdings current) + HOLDINGS_CHANGED + trackLedger row

**Files:**
- Create: `modules/Reconciler.lua`
- Modify: `core/Constants.lua` `MSG` (add `HOLDINGS_CHANGED = "Ka0s_LootHistory_HoldingsChanged"`, sender comment: `modules/Reconciler.lua`)
- Modify: `core/LifecycleSetup.lua` (`StandUp` enables `NS.Reconciler` after Collector; `StandDown` list gains `NS.Reconciler`)
- Modify: `core/LootHistory.lua` `addon:OnEnterWorld` (login scan, 3 s)
- Modify: `settings/Schema.lua` (row `settings.trackLedger`, General ▸ Capture)
- Modify: `LootHistory.toc` (after `modules\Holdings.lua`; Reconciler must load after Collector? No — it only reads `NS.Scanner`/`NS.Holdings` at call time. Place after `modules\Holdings.lua`.)
- Modify: `tests/test_disabled.lua` (add `NS.Reconciler.__ev` to the target list at line ~109; add `NS.Reconciler` wherever modules are enumerated)
- Modify: `tests/test_constants.lua` (pin the new wire string the way the others are pinned)
- Create: `tests/test_reconciler.lua`; register after `"test_collector"`

**Interfaces:**
- Consumes: `NS.Scanner.*`, `NS.Holdings:*`, `NS.Constants.*`, `NS.SafeRegisterEvent`, `NS.NewBusTarget`, `NS.After`, `NS.MSG`.
- Produces (on `NS.Reconciler`):
  - `:Enable()` / `:Disable()` (registers only when `settings.trackLedger` is true; re-evaluates on `SETTINGS_CHANGED` reason `"ledger"`)
  - `:OnEvent(event, ...)` — the single handler every registration routes to (tests call it directly)
  - `:MarkDirty(part, arg)` — `part` ∈ `"bags"` (arg bagID), `"equipped"`, `"money"`, `"currency"`, `"bank"`, `"tabs"`, `"warbandMoney"`
  - `:Flush()` — if `InCombatLockdown()` sets `self.deferred = true` and returns; else scans every dirty part that is currently readable, applies to Holdings, fires `HOLDINGS_CHANGED(holder)` once per changed holder, clears dirty bits. **Phase 2 inserts the diff→rows step inside Flush.**
  - `:LoginScan()` — dirties bags/equipped/currency/money/warbandMoney, flushes, then `Holdings:MarkGenesis(PlayerKey)` and, if warband money was read, `MarkGenesis("§warband")`.
  - `:IsReadable(part) -> boolean` (`bank`/`tabs` only while the Banker/AccountBanker interaction is shown; `warbandMoney` when `Compat.GetWarbandMoney()` returns non-nil; everything else always)
  - `self.dirty` table and `self.readable` table (exposed for tests)
  - Message `NS.MSG.HOLDINGS_CHANGED` payload `(holder)`.
  - Setting `settings.trackLedger` (bool, `SETTINGS_CHANGED` reason `"ledger"`).

- [ ] **Step 1: Write the failing test** — `tests/test_reconciler.lua`

```lua
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local R = function() return NS.Reconciler end
local ME = function() return NS.Util.PlayerKey() end

local function reset()
  NS.db.global.holdings = {}
  local m = T.mocks
  m.__bags, m.__bagSlots, m.__inventory, m.__money = {}, {}, {}, 0
  R().dirty, R().readable, R().deferred = {}, {}, nil
end

local function captureChanged(fn)
  local got, orig = {}, NS.bus.SendMessage
  NS.bus.SendMessage = function(_, msg, a) if msg == NS.MSG.HOLDINGS_CHANGED then got[#got + 1] = a end end
  fn()
  NS.bus.SendMessage = orig
  return got
end

test("Reconciler: BAG_UPDATE only marks dirty; BAG_UPDATE_DELAYED flushes", function()
  reset()
  T.mocks.__bags[0] = { [1] = { itemID = 5, link = "L5", count = 2 } }; T.mocks.__bagSlots[0] = 1
  R():OnEvent("BAG_UPDATE", 0)
  assertTrue(R().dirty.bags ~= nil)
  assertEqual(NS.Holdings:Get(ME()), nil)
  local changed = captureChanged(function() R():OnEvent("BAG_UPDATE_DELAYED"); R():Flush() end)
  assertEqual(NS.Holdings:Get(ME()).items[5].bags, 2)
  assertEqual(changed[1], ME())
end)

test("Reconciler: bag flush never touches bank column", function()
  reset()
  NS.Holdings:ApplyContainer(ME(), "bank", { [5] = 10 }, {}, 1)
  R():MarkDirty("bags", 0); R():Flush()
  assertEqual(NS.Holdings:Get(ME()).items[5].bank, 10)
end)

test("Reconciler: bank is unreadable until the banker interaction shows", function()
  reset()
  T.mocks.__bags[6] = { [1] = { itemID = 8, link = "L8", count = 4 } }; T.mocks.__bagSlots[6] = 1
  R():MarkDirty("bank"); R():Flush()
  assertEqual(NS.Holdings:Get(ME()), nil)
  R():OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", NS.Compat.InteractionType("Banker"))
  R():Flush()
  assertEqual(NS.Holdings:Get(ME()).items[8].bank, 4)
  R():OnEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", NS.Compat.InteractionType("Banker"))
  assertFalse(R():IsReadable("bank"))
end)

test("Reconciler: combat defers every scan to PLAYER_REGEN_ENABLED", function()
  reset()
  local m = T.mocks
  local savedICL = m.InCombatLockdown
  m.InCombatLockdown = function() return true end; _G.InCombatLockdown = m.InCombatLockdown
  m.__money = 500
  for _ = 1, 20 do R():OnEvent("PLAYER_MONEY"); R():OnEvent("BAG_UPDATE", 0); R():OnEvent("BAG_UPDATE_DELAYED") end
  R():Flush()
  assertEqual(NS.Holdings:Get(ME()), nil)
  assertTrue(R().deferred)
  m.InCombatLockdown = savedICL; _G.InCombatLockdown = savedICL
  local changed = captureChanged(function() R():OnEvent("PLAYER_REGEN_ENABLED") end)
  assertEqual(NS.Holdings:Get(ME()).money, 500)
  assertEqual(#changed, 1)
end)

test("Reconciler: LoginScan seeds genesis, partial until bank seen", function()
  reset()
  T.mocks.__money, T.mocks.__warbandMoney = 100, 70
  R():LoginScan()
  local e = NS.Holdings:Get(ME())
  assertTrue(e.meta.genesis ~= nil); assertTrue(e.meta.partial)
  assertEqual(NS.Holdings:Get("§warband").money, 70)
end)

test("Reconciler: account-wide currency lands on the warband holder", function()
  reset()
  local saved = T.mocks.__currencyList
  T.mocks.__currencyList = { { id = 2032, quantity = 5, accountWide = true }, { id = 3008, quantity = 9 } }
  R():MarkDirty("currency"); R():Flush()
  assertEqual(NS.Holdings:Get("§warband").currency[2032], 5)
  assertEqual(NS.Holdings:Get(ME()).currency[3008], 9)
  T.mocks.__currencyList = saved
end)

test("Reconciler: trackLedger off unregisters, on registers again", function()
  NS.Schema:Set("settings.trackLedger", false)
  assertFalse(R()._enabled == true and R().__ev ~= nil)
  NS.Schema:Set("settings.trackLedger", true)
end)
```

> The last case depends on how `test_disabled` brings the addon up; if `Reconciler:Enable` has not been called in this suite's slot, call `R():Enable()` first and assert `R().__ev ~= nil`, then flip the setting and assert `R().__ev == nil`.

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -A2 "Reconciler:" | head -20`
Expected: FAIL (`NS.Reconciler` nil).

- [ ] **Step 3: Implement** — `modules/Reconciler.lua`

```lua
local _, NS = ...
NS.Reconciler = NS.Reconciler or {}
local R = NS.Reconciler

-- Keeps db.global.holdings current (timeline-ledger spec §5.2). Every event only marks a part
-- dirty; Flush does the work, and never in combat (spec §5.2 "Combat"). Phase 2 inserts the
-- diff -> gain/loss/transfer rows step into Flush; this file is shaped for that.

local C = NS.Constants
local CT = C.Container
local WARBAND = C.WARBAND_HOLDER
local DEBOUNCE = 0.35

R.dirty, R.readable = {}, {}

local BANK_INTERACTIONS = { Banker = true, AccountBanker = true }

function R:IsReadable(part)
  if part == "bank" or part == "tabs" then return self.readable.bank == true end
  if part == "warbandMoney" then return NS.Compat.GetWarbandMoney() ~= nil end
  return true
end

function R:MarkDirty(part, arg)
  if part == "bags" then
    self.dirty.bags = self.dirty.bags or {}
    if arg ~= nil then self.dirty.bags[arg] = true end
  else
    self.dirty[part] = true
  end
end

local function scheduleFlush(self)
  if self._pending then return end
  self._pending = NS.After(DEBOUNCE, function() self._pending = nil; self:Flush() end) or nil
end

-- Which bags a "bags" flush reads: the carried bags only. Bank and warband tab bags fire BAG_UPDATE
-- too; they are routed to their own parts in OnEvent so a closed bank is never read as empty.
local function isIn(list, id) for _, v in ipairs(list) do if v == id then return true end end return false end

function R:OnEvent(event, a1)
  if event == "BAG_UPDATE" then
    if isIn(C.BANK_IDS, a1) then self:MarkDirty("bank")
    elseif isIn(C.WARBAND_TAB_IDS, a1) then self:MarkDirty("tabs")
    else self:MarkDirty("bags", a1) end
  elseif event == "BAG_UPDATE_DELAYED" then scheduleFlush(self)
  elseif event == "PLAYER_EQUIPMENT_CHANGED" then self:MarkDirty("equipped"); scheduleFlush(self)
  elseif event == "PLAYER_MONEY" then self:MarkDirty("money"); scheduleFlush(self)
  elseif event == "ACCOUNT_MONEY" then self:MarkDirty("warbandMoney"); scheduleFlush(self)
  elseif event == "CURRENCY_DISPLAY_UPDATE" then self:MarkDirty("currency"); scheduleFlush(self)
  elseif event == "PLAYERBANKSLOTS_CHANGED" then self:MarkDirty("bank"); scheduleFlush(self)
  elseif event == "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" then self:MarkDirty("tabs"); scheduleFlush(self)
  elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
    local shown = event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
    for name in pairs(BANK_INTERACTIONS) do
      if a1 == NS.Compat.InteractionType(name) then
        if shown then
          self.readable.bank = true
          self:MarkDirty("bank"); self:MarkDirty("tabs"); self:MarkDirty("warbandMoney")
          scheduleFlush(self)
        else
          self:Flush()                 -- final read while still readable
          self.readable.bank = nil
        end
      end
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if self.deferred then self.deferred = nil; self:Flush() end
  end
end

-- Scan one dirty part into Holdings. Returns the holder it changed, or nil.
local function flushPart(self, part, me, now)
  local S, H = NS.Scanner, NS.Holdings
  if part == "bags" then
    local c, l = S.ScanContainers(C.BAG_IDS)
    return H:ApplyContainer(me, CT.BAGS, c, l, now) and me
  elseif part == "equipped" then
    local c, l = S.ScanEquipped()
    return H:ApplyContainer(me, CT.EQUIPPED, c, l, now) and me
  elseif part == "bank" then
    local c, l = S.ScanContainers(C.BANK_IDS)
    return H:ApplyContainer(me, CT.BANK, c, l, now) and me
  elseif part == "tabs" then
    local c, l = S.ScanContainers(C.WARBAND_TAB_IDS)
    return H:ApplyContainer(WARBAND, CT.TABS, c, l, now) and WARBAND
  elseif part == "money" then
    return H:ApplyMoney(me, S.ReadMoney(), now) and me
  elseif part == "warbandMoney" then
    local v = S.ReadWarbandMoney()
    return v ~= nil and H:ApplyMoney(WARBAND, v, now) and WARBAND or nil
  end
end

function R:Flush()
  if InCombatLockdown and InCombatLockdown() then self.deferred = true; return end
  local me, now, changed = NS.Util.PlayerKey(), time(), {}
  for part in pairs(self.dirty) do
    if self:IsReadable(part) then
      if part == "currency" then
        local char, wb = NS.Scanner.ScanCurrencies()
        if NS.Holdings:ApplyCurrency(me, char, now) then changed[me] = true end
        if NS.Holdings:ApplyCurrency(WARBAND, wb, now) then changed[WARBAND] = true end
      else
        local h = flushPart(self, part, me, now)
        if h then changed[h] = true end
      end
      self.dirty[part] = nil
    end
  end
  local meta = NS.Holdings:Get(me)
  if meta then meta.meta.classFile = meta.meta.classFile or select(2, UnitClass("player")) end
  for h in pairs(changed) do NS.bus:SendMessage(NS.MSG.HOLDINGS_CHANGED, h) end
end

function R:LoginScan()
  for _, p in ipairs({ "equipped", "money", "currency", "warbandMoney" }) do self:MarkDirty(p) end
  self:MarkDirty("bags", 0)
  self:Flush()
  if self.deferred then return end
  NS.Holdings:MarkGenesis(NS.Util.PlayerKey(), time())
  if NS.Holdings:Get(WARBAND) then NS.Holdings:MarkGenesis(WARBAND, time()) end
end

local EVENTS = {
  "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_MONEY", "ACCOUNT_MONEY",
  "CURRENCY_DISPLAY_UPDATE", "PLAYERBANKSLOTS_CHANGED", "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED",
  "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "PLAYER_REGEN_ENABLED",
}

local function trackLedgerOn()
  local s = NS.db and NS.db.profile and NS.db.profile.settings
  return s and s.trackLedger ~= false
end

function R:Enable()
  if not self._settings then
    self._settings = NS.NewBusTarget()
    self._settings:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function(_, reason)
      if reason == "ledger" then if trackLedgerOn() then self:Enable() else self:DisableCapture() end end
    end)
  end
  if self.__ev or not trackLedgerOn() then return end
  self.__ev = NS.NewBusTarget()
  for _, ev in ipairs(EVENTS) do
    NS.SafeRegisterEvent(self.__ev, ev, function(_, ...) self:OnEvent(ev, ...) end, NS.RejectedEvents)
  end
  self._enabled = true
end

-- Capture off (trackLedger unticked) but the module stays listening for the setting coming back.
function R:DisableCapture()
  if self.__ev then self.__ev:UnregisterAllEvents(); self.__ev = nil end
  self.dirty, self.deferred, self._pending = {}, nil, nil
  self._enabled = nil
end

-- Full stand-down (slash-commands-§7): capture AND the settings listener.
function R:Disable()
  self:DisableCapture()
  if self._settings then self._settings:UnregisterAllMessages(); self._settings = nil end
end
```

> Make `R:LoginScan` scan all `C.BAG_IDS` by marking `"bags"` with no specific id — `flushPart("bags")` already scans every carried bag, so `MarkDirty("bags")` with nil arg suffices; the `0` is harmless. `NS.After` returns nil headless when it ran straight through; the `or nil` keeps `_pending` clear then.

`core/Constants.lua` `MSG`:

```lua
  -- Sender: modules/Reconciler.lua `Flush`. Payload: (holder) — once per holder whose holdings moved.
  HOLDINGS_CHANGED = "Ka0s_LootHistory_HoldingsChanged",
```

`core/LifecycleSetup.lua`: in `StandUp` add `if NS.Reconciler and NS.Reconciler.Enable then NS.Reconciler:Enable() end` after the Collector line; in `StandDown` add `NS.Reconciler` to the `ipairs({ ... })` list.

`core/LootHistory.lua` `addon:OnEnterWorld` — inside the once-per-session guard, add:

```lua
  -- Holdings genesis / login scan (timeline-ledger spec §5.6). Three seconds in, after the item
  -- cache has had a moment; cancellable through NS.CancelDeferrals like the prune.
  NS.After(3, function()
    if NS.Reconciler and NS.Reconciler._enabled then NS.Reconciler:LoginScan() end
  end)
```

`settings/Schema.lua` — after the `recordCurrency` row:

```lua
  { path = "settings.trackLedger", default = PD.settings.trackLedger, type = "bool", widget = "CheckBox",
    page = "General", group = "Capture", label = "Track holdings and losses",
    tooltip = "Keep a ledger of what every character and your warband holds, and (from the next " ..
      "update) every gain, loss and transfer. Off = record loot gains only, as before.",
    onChange = function()
      if NS.bus then NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "ledger") end
    end },
```

Update `docs/schema.md`'s row table for the new setting in Task 10.

- [ ] **Step 4: Update teardown coverage** — in `tests/test_disabled.lua` add `NS.Reconciler.__ev` and `NS.Reconciler._settings` to the targets list (~line 109) and any explicit module enumeration, so stand-down is asserted to leave neither registered.

- [ ] **Step 5: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS, 0/0. `test_constants` pins the new wire string; `test_diagnostics`/`test_debug_coverage` may require a debug line per new subsystem — if they fail naming the Reconciler, add `NS.Debug("Holdings", ...)` lines in `Flush` (guarded by `NS.State.debug`) mirroring Collector's pattern and re-run.

- [ ] **Step 6: Commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add modules/Reconciler.lua core/Constants.lua core/LifecycleSetup.lua core/LootHistory.lua settings/Schema.lua LootHistory.toc tests/test_reconciler.lua tests/test_disabled.lua tests/test_constants.lua tests/run.lua docs/test-cases.md
git commit -m "feat(holdings): Reconciler keeps holdings current; HOLDINGS_CHANGED; trackLedger setting"
```

---

### Task 7: Browser tab registry (refactor, behavior-preserving)

**Files:**
- Modify: `modules/Browser.lua:120-191` (TABS/BuildPane/SelectTab/CreateTabStrip), `:485-491` (ApplyFilter), `:892-899` (OpenExport), `:1014` (pane loop)
- Test: `tests/test_browser.lua` (append)

**Interfaces:**
- Produces:
  - `NS.Browser:RegisterTab(spec)` where `spec = { name=string, order=number, build=function(pane), refresh=function()|nil, export=function(title)|nil, filters=set|nil }`. Must be called before the window is first built (at file load). History (order 10) and Insights (order 20) register inside `Browser.lua`; Holdings registers order 40 (Task 8); Timeline will register order 30 (Phase 3).
  - `NS.Browser:Tabs() -> ordered array of names`
  - `NS.Browser:ActiveTab() -> name`
  - `ApplyFilter` calls the active tab's `refresh` (History's refresh stays the existing `BrowserTable:SetFilter` path, which always runs because the footer count depends on it).

- [ ] **Step 1: Write the failing test** — append to `tests/test_browser.lua`

```lua
test("Browser: tab registry orders History, Insights, then registered tabs", function()
  local names = NS.Browser:Tabs()
  assertEqual(names[1], "History"); assertEqual(names[2], "Insights")
end)

test("Browser: a registered tab builds lazily and refreshes on select", function()
  local built, refreshed = 0, 0
  NS.Browser:RegisterTab{ name = "ZTest", order = 99,
    build = function() built = built + 1 end, refresh = function() refreshed = refreshed + 1 end }
  NS.Browser:Show()
  NS.Browser:SelectTab("ZTest"); NS.Browser:SelectTab("History"); NS.Browser:SelectTab("ZTest")
  assertEqual(built, 1); assertEqual(refreshed, 2)
  assertEqual(NS.Browser:ActiveTab(), "ZTest")
  NS.Browser:SelectTab("History")
  NS.Browser:_UnregisterTabForTest("ZTest")
end)
```

> Registering after the window exists must also work (create pane + tab button on the fly) so tests and late modules are safe; `_UnregisterTabForTest` removes pane/button. Keep it underscored and test-only. Check `test_browser.lua`'s existing show/hide helpers and reuse them instead of `NS.Browser:Show()` if the suite has one.

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -A2 "tab registry\|registered tab"`
Expected: FAIL (`Tabs` nil).

- [ ] **Step 3: Implement** — replace the `-- ── Tabs ──` block:

```lua
-- ── Tabs ──────────────────────────────────────────────────────────────────────
-- A registry rather than a hard-coded pair (timeline-ledger spec §8.0): each tab is a spec its
-- owning module registers. The filter bar and footer stay shared window chrome (issue #13).
local tabSpecs, tabOrder = {}, {}
local lastTab = "History"   -- remembered within a session

local function sortTabs()
  table.sort(tabOrder, function(a, b) return tabSpecs[a].order < tabSpecs[b].order end)
end

function B:Tabs() local out = {}; for i, n in ipairs(tabOrder) do out[i] = n end; return out end
function B:ActiveTab() return lastTab end

local function BuildPane(name)
  local pane = frame.panes[name]
  if pane._built then return end
  pane._built = true
  tabSpecs[name].build(pane)
end
```

`B:RegisterTab(spec)` stores the spec, appends to `tabOrder`, `sortTabs()`, and if `frame` already exists, creates the pane (same anchors as the `EnsureFrame` loop — extract that into `local function CreatePane(name)`) and rebuilds the tab strip buttons (extract `LayoutTabButtons()` from `CreateTabStrip`, positioned by index × 94).

`SelectTab`: loop over `tabOrder`; after `BuildPane(name)` call `local s = tabSpecs[name]; if s.refresh then s.refresh() end`; keep the `UpdateFooter/UpdateDbSize` and debug line.

History and Insights register at file scope, below the functions they reference:

```lua
B:RegisterTab{ name = "History", order = 10,
  build = function(pane) B:BuildTable(pane) end,
  refresh = function()
    if NS.BrowserTable and NS.BrowserTable.Refresh then NS.BrowserTable:Refresh(); B:RefreshFilterOptions() end
  end }
B:RegisterTab{ name = "Insights", order = 20,
  build = function(pane) if NS.Analytics and NS.Analytics.Attach then NS.Analytics:Attach(pane) end end,
  refresh = function() if NS.Analytics and NS.Analytics.Refresh then NS.Analytics:Refresh() end end,
  export = function(title) --[[ move the existing Insights branch of OpenExport here ]] end }
```

`ApplyFilter`: keep the unconditional `BrowserTable:SetFilter` + `UpdateFooter`; replace the Insights-only branch with `local s = tabSpecs[lastTab]; if lastTab ~= "History" and s and s.refresh and frame and frame.panes[lastTab]._built then s.refresh() end`.

`OpenExport`: `local s = tabSpecs[lastTab]; if s and s.export then return s.export(title) end` then the existing History path as the default.

> Net line count of `Browser.lua` must not grow (spec §8.0). Moving the Insights export body into its spec is a move, not an add.

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS (all existing browser/table/analytics/widgets suites unchanged), 0/0. `wc -l modules/Browser.lua` ≤ 1318.

- [ ] **Step 5: Commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add modules/Browser.lua tests/test_browser.lua docs/test-cases.md
git commit -m "refactor(browser): tab registry; History and Insights register as specs"
```

---

### Task 8: Holdings tab

**Files:**
- Create: `modules/HoldingsTab.lua`
- Modify: `LootHistory.toc` (after `modules\AnalyticsCharts.lua`)
- Modify: `core/LifecycleSetup.lua` (enable/disable `NS.HoldingsTab`)
- Modify: `tests/test_disabled.lua` (add `NS.HoldingsTab.__ev`)
- Create: `tests/test_holdingstab.lua`; register after `"test_analytics_layout"`

**Interfaces:**
- Consumes: `NS.Holdings:Search(filter)`, `NS.Browser:RegisterTab`, `NS.Browser:CurrentFilter()` (fields `text`, `quality`, `itemType`, `itemSubType`, `char`), `NS.Pool`, `NS.MSG.HOLDINGS_CHANGED`, `NS.Util.RecordValue` (for value sort; items only).
- Produces:
  - `NS.HoldingsTab.BuildModel(filter, expanded, sortKey) -> lines` — pure. `lines` is a flat array of `{ kind="thing", key=, name=, quality=, total=, value=, expanded=bool }` followed (when expanded) by `{ kind="holder", key=, holder=, count=, containers=, scannedAt= }`. `sortKey` ∈ `"name"|"total"|"value"`.
  - `NS.HoldingsTab.FormatContainers(containers) -> "Bags 12 · Bank 40 · Warband 100"` (fixed order bags, equipped, bank, mail, auctions, tabs; `tabs` labeled "Warband")
  - `NS.HoldingsTab.FormatAge(scannedAt, now) -> "now" | "5 m" | "3 h" | "2 d"`
  - `NS.HoldingsTab:Attach(pane)`, `:Refresh()`, `:Toggle(key)`, `:Enable()`, `:Disable()`
  - Tab registered as `{ name="Holdings", order=40 }`.

- [ ] **Step 1: Write the failing test** — `tests/test_holdingstab.lua`

```lua
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local function seed()
  NS.db.global.holdings = {}
  NS.Holdings:ApplyContainer("A-Realm", "bags", { [7] = 2 }, { [7] = "|Hitem:7|h[Apple]|h" }, 100)
  NS.Holdings:ApplyContainer("B-Realm", "bank", { [7] = 9 }, {}, 50)
  NS.Holdings:ApplyMoney("A-Realm", 10000, 100)
end

test("HoldingsTab: model lists things collapsed by default", function()
  seed()
  local lines = NS.HoldingsTab.BuildModel({}, {}, "name")
  local things = 0
  for _, l in ipairs(lines) do if l.kind == "thing" then things = things + 1 else error("holder line while collapsed") end end
  assertEqual(things, 2)   -- Apple + Gold
end)

test("HoldingsTab: expanding a thing adds one line per holder", function()
  seed()
  local lines = NS.HoldingsTab.BuildModel({}, { ["i:7"] = true }, "total")
  assertEqual(lines[1].key, "g")            -- total sort: gold 10000 first
  local holders = 0
  for _, l in ipairs(lines) do if l.kind == "holder" then holders = holders + 1 end end
  assertEqual(holders, 2)
end)

test("HoldingsTab: character filter narrows holders", function()
  seed()
  local lines = NS.HoldingsTab.BuildModel({ char = { ["B-Realm"] = true } }, { ["i:7"] = true }, "name")
  for _, l in ipairs(lines) do
    if l.kind == "holder" then assertEqual(l.holder, "B-Realm") end
    if l.kind == "thing" then assertTrue(l.key ~= "g") end   -- B has no gold
  end
end)

test("HoldingsTab: container and age formatting", function()
  assertEqual(NS.HoldingsTab.FormatContainers({ tabs = 100, bags = 12, bank = 40 }), "Bags 12 · Bank 40 · Warband 100")
  assertEqual(NS.HoldingsTab.FormatAge(1000, 1030), "now")
  assertEqual(NS.HoldingsTab.FormatAge(1000, 1000 + 3 * 3600), "3 h")
  assertEqual(NS.HoldingsTab.FormatAge(1000, 1000 + 2 * 86400), "2 d")
end)

test("HoldingsTab: tab is registered after History and Insights", function()
  local names = NS.Browser:Tabs()
  assertEqual(names[#names], "Holdings")
end)

test("HoldingsTab: attach builds rows and recycles them on refresh", function()
  seed()
  NS.Browser:Show(); NS.Browser:SelectTab("Holdings")
  local first = NS.HoldingsTab:VisibleRowCount()
  NS.HoldingsTab:Refresh()
  assertEqual(NS.HoldingsTab:VisibleRowCount(), first)
  assertTrue(first >= 2)
  NS.Browser:SelectTab("History")
end)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -A2 "HoldingsTab:" | head`
Expected: FAIL.

- [ ] **Step 3: Implement** — `modules/HoldingsTab.lua`

```lua
local _, NS = ...
NS.HoldingsTab = NS.HoldingsTab or {}
local HT = NS.HoldingsTab

-- The Holdings tab (timeline-ledger spec §8.2): one line per thing with its total; expanding a thing
-- shows each holder with the container split and how stale the oldest contributing scan is.
-- BuildModel is pure and carries all the logic; the view is a pooled list of fixed-height rows.

local ORDER = { "bags", "equipped", "bank", "mail", "auctions", "tabs" }
local LABEL = { bags = "Bags", equipped = "Equipped", bank = "Bank", mail = "Mail", auctions = "AH", tabs = "Warband" }
local ROW_H = 18

function HT.FormatContainers(containers)
  local parts = {}
  for _, c in ipairs(ORDER) do
    if containers and containers[c] then parts[#parts + 1] = LABEL[c] .. " " .. containers[c] end
  end
  return table.concat(parts, " · ")
end

function HT.FormatAge(scannedAt, now)
  if not scannedAt then return "never" end
  local s = (now or time()) - scannedAt
  if s < 60 then return "now" end
  if s < 3600 then return math.floor(s / 60) .. " m" end
  if s < 86400 then return math.floor(s / 3600) .. " h" end
  return math.floor(s / 86400) .. " d"
end

local function valueOf(row)
  if row.kind == "GOLD" then return row.total end
  if row.kind ~= "ITEM" then return 0 end
  local unit = NS.Util.RecordValue and NS.Util.RecordValue({ itemID = row.id, itemLink = row.link }) or 0
  return (unit or 0) * row.total
end

local SORTS = {
  name  = function(a, b) return a.name:lower() < b.name:lower() end,
  total = function(a, b) if a.total ~= b.total then return a.total > b.total end return a.name < b.name end,
  value = function(a, b) if a.value ~= b.value then return a.value > b.value end return a.name < b.name end,
}

function HT.BuildModel(filter, expanded, sortKey)
  local things = NS.Holdings:Search(filter or {})
  for _, t in ipairs(things) do t.value = valueOf(t) end
  table.sort(things, SORTS[sortKey or "name"] or SORTS.name)
  local lines = {}
  for _, t in ipairs(things) do
    local open = expanded and expanded[t.key] or false
    lines[#lines + 1] = { kind = "thing", key = t.key, name = t.name, quality = t.quality,
      total = t.total, value = t.value, expanded = open, thingKind = t.kind }
    if open then
      for _, h in ipairs(t.holders) do
        lines[#lines + 1] = { kind = "holder", key = t.key, holder = h.holder, count = h.count,
          containers = h.containers, scannedAt = h.scannedAt }
      end
    end
  end
  return lines
end
```

View (same file): `HT:Attach(pane)` creates a `UIPanelScrollFrameTemplate` scroll frame and content child exactly like `modules/Analytics.lua` does (read its `Attach` for anchors and skin), a column header row (Name · Total · Value), and an `NS.Pool.New` pool of row buttons. `HT:Refresh()` reads `NS.Browser:CurrentFilter()`, calls `BuildModel(filter, self.expanded, self.sortKey)`, releases all rows to the pool, acquires one per line, and sets:
- thing line: name colored by quality (`NS.Item.QualityColor` or the same helper `BrowserTable` uses), total right-aligned (gold via `GetCoinTextureString` for `key=="g"`), value as money; click toggles `self.expanded[key]` then `Refresh()`.
- holder line: indented 16 px; holder name class-colored (via `NS.Holdings:Get(holder).meta.classFile` + `RAID_CLASS_COLORS`; `§warband` shown as "Warband"), `FormatContainers`, and `FormatAge(scannedAt)` in gray when older than 1 day.
`HT:VisibleRowCount()` returns the number of acquired rows (test seam).
`HT:Enable()` subscribes a private `NS.NewBusTarget()` (`self.__ev`) to `HOLDINGS_CHANGED` → `if self.pane and self.pane:IsShown() then self:Refresh() end`; `HT:Disable()` unregisters it.

Registration at file end:

```lua
NS.Browser:RegisterTab{ name = "Holdings", order = 40,
  build = function(pane) HT:Attach(pane) end,
  refresh = function() HT:Refresh() end }
```

> The filter bar's Date / Source / Bound / Zone dropdowns don't apply here. Phase 1 leaves them visible and ignored; graying per-tab filters is spec §8.0 and lands with the Timeline tab in Phase 3 (note this in `docs/browser.md`).

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS, 0/0.

- [ ] **Step 5: Commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add modules/HoldingsTab.lua LootHistory.toc core/LifecycleSetup.lua tests/test_holdingstab.lua tests/test_disabled.lua tests/run.lua docs/test-cases.md
git commit -m "feat(holdings): Holdings tab with per-holder breakdown and staleness"
```

---

### Task 9: Reset recommendation popup and `/lh holdings`

**Files:**
- Modify: `settings/Slash.lua` (two `StaticPopupDialogs` entries; `NS.OfferLedgerReset`; the `holdings` command)
- Modify: `core/LootHistory.lua` `OnEnterWorld` (offer at +5 s; defer to `PLAYER_REGEN_ENABLED` in combat)
- Modify: `settings/Schema.lua` `NS.COMMANDS` (the `holdings` verb — follow the existing positional command table and `docs/slash-dispatch.md`)
- Create: `tests/test_resetprompt.lua`; register after `"test_slash_degraded"`

**Interfaces:**
- Consumes: `NS.State.upgradedFrom`, `db.global.resetPrompt`, `NS.Database:Purge()`, `NS.Browser:OpenExport()`, `NS.Holdings:Search`.
- Produces:
  - `NS.ShouldOfferLedgerReset(g, upgradedFrom) -> boolean` — true iff `g.resetPrompt == nil` and `upgradedFrom ~= nil and upgradedFrom < 11` and `#g.history > 0`.
  - `NS.OfferLedgerReset()` — shows `KA0S_LOOTHISTORY_LEDGER_RESET` with `%d` = record count; in combat, defers until `PLAYER_REGEN_ENABLED` (one-shot private target).
  - Popups: `KA0S_LOOTHISTORY_LEDGER_RESET` (button1 "Reset history", button2 "Keep history", button3 "Export first"), `KA0S_LOOTHISTORY_LEDGER_RESET_CONFIRM`.
  - `/lh holdings <query>` prints `<name>: <total>` (top 10 matches; "no holdings match" otherwise).

- [ ] **Step 1: Write the failing test** — `tests/test_resetprompt.lua`

```lua
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

test("Reset prompt: offered only for an upgraded, non-empty, undecided DB", function()
  local f = NS.ShouldOfferLedgerReset
  assertTrue(f({ history = { {} } }, 10))
  assertFalse(f({ history = {} }, 10))                         -- empty history: fresh install / purged
  assertFalse(f({ history = { {} } }, nil))                    -- already on v11 before this load
  assertFalse(f({ history = { {} }, resetPrompt = "kept" }, 10))
  assertFalse(f({ history = { {} }, resetPrompt = "reset" }, 10))
end)

test("Reset prompt: dialogs are registered with three choices", function()
  local d = T.mocks.StaticPopupDialogs["KA0S_LOOTHISTORY_LEDGER_RESET"]
  assertTrue(d ~= nil)
  assertTrue(d.button1 ~= nil and d.button2 ~= nil and d.button3 ~= nil)
  assertTrue(d.text:find("gains", 1, true) ~= nil)
  assertTrue(T.mocks.StaticPopupDialogs["KA0S_LOOTHISTORY_LEDGER_RESET_CONFIRM"] ~= nil)
end)

test("Reset prompt: Keep stores the choice; Esc leaves it undecided", function()
  local g = NS.db.global
  g.resetPrompt = nil
  T.mocks.StaticPopupDialogs["KA0S_LOOTHISTORY_LEDGER_RESET"].OnCancel(nil, nil, "clicked")
  assertEqual(g.resetPrompt, "kept")
  g.resetPrompt = nil
  T.mocks.StaticPopupDialogs["KA0S_LOOTHISTORY_LEDGER_RESET"].OnCancel(nil, nil, "override")
  assertEqual(g.resetPrompt, nil)
end)

test("Reset prompt: confirmed reset purges history and keeps holdings", function()
  local g = NS.db.global
  local savedH = g.history
  g.history = { { itemID = 1 }, { itemID = 2 } }
  g.holdings = { ["A-Realm"] = { money = 1, items = {}, currency = {}, links = {}, meta = {}, scanned = {} } }
  g.resetPrompt = nil
  T.mocks.StaticPopupDialogs["KA0S_LOOTHISTORY_LEDGER_RESET_CONFIRM"].OnAccept()
  assertEqual(#g.history, 0)
  assertEqual(g.resetPrompt, "reset")
  assertEqual(g.holdings["A-Realm"].money, 1)
  assertTrue(type(g.ledgerSince) == "number")
  g.history = savedH
end)
```

> StaticPopup `OnCancel(self, data, reason)`: reason is `"clicked"` for button2 and `"override"`/`"timeout"` otherwise; Esc with `hideOnEscape` hides via `StaticPopup_Hide` → `OnHide`, not `OnCancel` — so "Keep" must check `reason == "clicked"`. Button3 is `OnAlt`. Verify these against the client in the smoke test (Task 10) and adjust if 12.x differs.

- [ ] **Step 2: Run to verify failure**

Run: `lua tests/run.lua 2>&1 | grep -A2 "Reset prompt" | head`
Expected: FAIL.

- [ ] **Step 3: Implement** — `settings/Slash.lua`, inside the `if type(StaticPopupDialogs) == "table" then` block:

```lua
  -- The one-time timeline-ledger reset recommendation (spec §9.2). Esc/close decides nothing, so it
  -- is asked again next session; only Keep and a confirmed Reset store a choice.
  StaticPopupDialogs["KA0S_LOOTHISTORY_LEDGER_RESET"] = {
    text = "|cffffd100Loot History has become a full ledger.|r\n\n" ..
      "It now tracks what every character and your warband holds, and will track gains AND losses " ..
      "of items, currencies and gold.\n\n" ..
      "|cffffd100Recommended: start a fresh history.|r Your %d existing records only ever captured " ..
      "gains. Mixed with the new data, any period before today would show income with no spending, " ..
      "so net totals and Insights for those dates overstate what you kept.\n\n" ..
      "|cffffd100If you keep it:|r nothing is lost and older loot stays browsable, but net and loss " ..
      "figures are only accurate from today; ranges that include older dates carry a warning.\n\n" ..
      "|cffffd100If you reset:|r older loot records are deleted permanently. Settings, filters and " ..
      "profiles are kept. Choose Export first for a copy.",
    button1 = "Reset history", button2 = "Keep history", button3 = "Export first",
    OnAccept = function() StaticPopup_Show("KA0S_LOOTHISTORY_LEDGER_RESET_CONFIRM", #NS.db.global.history) end,
    OnCancel = function(_, _, reason)
      if reason == "clicked" then NS.db.global.resetPrompt = "kept"; print("keeping your loot history.") end
    end,
    OnAlt = function()
      NS._ledgerResetAfterExport = true
      if NS.Browser then NS.Browser:Show(); NS.Browser:SelectTab("History"); NS.Browser:OpenExport() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
  }
  StaticPopupDialogs["KA0S_LOOTHISTORY_LEDGER_RESET_CONFIRM"] = {
    text = "Delete %d loot records permanently? This cannot be undone.",
    button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function()
      local g = NS.db.global
      if NS.Database and NS.Database.Purge then NS.Database:Purge() end
      g.resetPrompt, g.ledgerSince = "reset", time()
      print("history reset; the ledger starts now.")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
  }
```

Below the block (module scope):

```lua
function NS.ShouldOfferLedgerReset(g, upgradedFrom)
  return g ~= nil and g.resetPrompt == nil and upgradedFrom ~= nil and upgradedFrom < 11
    and type(g.history) == "table" and #g.history > 0
end

function NS.OfferLedgerReset()
  local g = NS.db and NS.db.global
  if not NS.ShouldOfferLedgerReset(g, NS.State.upgradedFrom) then return end
  if InCombatLockdown and InCombatLockdown() then
    local t = NS.NewBusTarget()
    t:RegisterEvent("PLAYER_REGEN_ENABLED", function() t:UnregisterAllEvents(); NS.OfferLedgerReset() end)
    return
  end
  StaticPopup_Show("KA0S_LOOTHISTORY_LEDGER_RESET", #g.history)
end
```

"Export first" re-offer: in `NS.Export`'s hide path (`modules/Export.lua`, the window's `OnHide`), add `if NS._ledgerResetAfterExport then NS._ledgerResetAfterExport = nil; NS.OfferLedgerReset() end`.

`core/LootHistory.lua` `OnEnterWorld`, inside the guard:

```lua
  NS.After(5, function() if NS.OfferLedgerReset then NS.OfferLedgerReset() end end)
```

`/lh holdings <query>`: add a row to `NS.COMMANDS` following its existing shape (read `settings/Schema.lua` where `NS.COMMANDS` is assigned and `docs/slash-dispatch.md`), handler:

```lua
function Sl:Holdings(query)
  local rows = NS.Holdings:Search({ text = query })
  if #rows == 0 then print("no holdings match '" .. tostring(query or "") .. "'."); return end
  for i = 1, math.min(10, #rows) do
    local r = rows[i]
    print(("%s: %s"):format(r.name, r.key == "g" and GetCoinTextureString(r.total) or tostring(r.total)))
  end
end
```

Add a `test_slash.lua` case: `/lh holdings apple` prints the seeded Apple total (reuse the print-capture helper that suite already uses).

- [ ] **Step 4: Run tests and lint**

Run: `lua tests/run.lua 2>&1 | tail -5 && luacheck .`
Expected: PASS, 0/0 (add `StaticPopup_Show` is already in `read_globals`; add `InCombatLockdown` if missing).

- [ ] **Step 5: Commit**

```bash
lua tests/run.lua --list > docs/test-cases.md
git add settings/Slash.lua settings/Schema.lua core/LootHistory.lua modules/Export.lua tests/test_resetprompt.lua tests/test_slash.lua tests/run.lua docs/test-cases.md
git commit -m "feat(ledger): one-time reset recommendation popup; /lh holdings"
```

---

### Task 10: Documentation and smoke tests for Phase 1

**Files:**
- Modify: `docs/scope.md` — reverse the gold non-goal (line ~213) and restate scope as "a personal ledger of loot, holdings, and (Phase 2) gains/losses"; record decisions D1–D9 with the 2026-10-06 date; min-quality now gates rich loot records (F5).
- Modify: `docs/schema.md` — `db.global.holdings` / `daily` / `ledgerSince` / `resetPrompt` shapes; row fields `dir/kind/holder/from/to` reserved (written from Phase 2); `settings.trackLedger` row; v11 in the migration ladder.
- Modify: `docs/module-map.md` — `core/Ledger.lua`, `modules/Scanner.lua`, `modules/Holdings.lua`, `modules/Reconciler.lua`, `modules/HoldingsTab.lua` with TOC positions.
- Modify: `docs/message-bus.md` — `HOLDINGS_CHANGED` (sender Reconciler; receivers HoldingsTab), per its add-a-message recipe.
- Modify: `docs/data-flow.md` — new "Holdings scan" section (events → dirty → flush; combat deferral; readability).
- Modify: `docs/ARCHITECTURE.md` — module map rows, event-wiring table (eleven new events), slash table (`holdings`), message bus count; update the "Files over the 1500-line cap" census only if a file crosses.
- Modify: `docs/browser.md` — tab registry; Holdings tab.
- Modify: `docs/disabled-state.md` — Reconciler and HoldingsTab teardown.
- Modify: `docs/smoke-tests.md` — add:
  - **LED-1** Fresh login: Holdings shows current character's bags, equipped, gold, currencies; bank shows "never".
  - **LED-2** Open bank: bank and warband tabs populate; warband gold shows; close bank; relog; values persist with ages.
  - **LED-3** Log a second character: both appear; `§warband` appears once as "Warband".
  - **LED-4** Drink 5 potions in combat: no lag; after combat, bag count drops by 5 (one refresh).
  - **LED-5** Upgrade from a v10 DB with history: popup after ~5 s; test Keep, Esc (re-asks next login), Export first (re-asks after export closes), Reset (confirm, history empty, Holdings intact).
  - **LED-6** `C_Bank.FetchDepositedMoney` away from the bank: record whether warband gold reads non-nil (spec §5.6 open check).
  - **LED-7** `/lh holdings <name>` prints totals.
  - **LED-8** Untick "Track holdings and losses": `/etrace` shows no BAG_UPDATE handling by LootHistory; re-tick restores.
- Modify: `docs/test-cases.md` — regenerate.

- [ ] **Step 1:** Make the doc edits above, matching each file's voice and structure. `tests/test_doc_structure.lua` checks ARCHITECTURE sections and anchors — run it.
- [ ] **Step 2:** Run `lua tests/run.lua 2>&1 | tail -5 && luacheck .` — Expected: PASS, 0/0.
- [ ] **Step 3:** Commit.

```bash
lua tests/run.lua --list > docs/test-cases.md
git add docs/
git commit -m "docs: timeline ledger phase 1 — scope reversal, holdings schema, module map, smokes"
```

- [ ] **Step 4:** Hand the in-game smoke list (LED-1..8) to the user; Phase 1 is complete only when they report the smokes passed. Do not start Phase 2 before that.

---

## Spec coverage (Phase 1)

| Spec section | Task |
|---|---|
| §3 holders/containers/thing keys | 1, 3, 5 |
| §4.1 row fields (accessors only; written in P2) | 1 |
| §4.2 holdings store | 5 |
| §4.3 daily rollup (store created; written in P3) | 2 |
| §4.4 bookkeeping | 2, 9 |
| §5.2 triggers (holdings refresh subset) | 6 |
| §5.6 login genesis / partial | 6 |
| §8.0 tab registry | 7 |
| §8.2 Holdings tab (except "Show in Timeline", P3; "Forget character", P3 with Timeline cleanup) | 8 |
| §9 migration + popup | 2, 9 |
| §11 `trackLedger` | 2, 6 |
| §13 F1, F5 docs | 10 |
| Deferred to P2: §5.1/§5.3/§5.4/§5.5 rows, claims, reasons, gold rows, §6, §7, F2 perf harness, F4 export columns | — |
| Deferred to P3: §4.3 writes, §8.1 Timeline, F3 LibKa0s LineChart, per-tab filter graying | — |
