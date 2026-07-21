# Currency Blacklist Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Let the user blacklist specific currencies (never record them), with parity to the item blacklist — managed via a History row right-click action and a Filters-panel section.

**Architecture:** A new account-wide `db.global.currencyBlacklist = { [currencyID]=true }` carve-out (separate from the itemID `blacklist`/`whitelist` because the numeric namespaces collide). Point-in-time, like the item lists — future captures only. The Collector's currency gate drops a blacklisted currency. `NS.Filters` grows currency-blacklist methods mirroring the item ones (blacklist only — no currency whitelist). UI: a "Blacklist currency" row action + a "Currencies" section in the Filters panel.

**Tech stack:** Lua 5.1, Ace3, headless `lua tests/run.lua` + `luacheck`.

**Design source:** approved in conversation 2026-07-21 (blacklist-only; right-click + Filters-panel management; point-in-time; row menu only *adds*, removal via the panel).

## Global Constraints

- **Branch `feature/currency-capture`** (rides with the currency feature). Never `master`.
- **Account-wide carve-out storage:** `db.global.currencyBlacklist`, mutated through `NS.Filters` copy-on-write (fresh table each write — never mutate an AceDB default in place), NOT a Schema row (like `blacklist`/`whitelist`/`window`). Add its default `{}` to `defaults/Global.lua`.
- **Point-in-time:** blacklisting a currency affects only future captures; stored rows are never hidden or deleted.
- **Closed message bus:** reuse `Filters:_notify` (re-cache Collector upvalues + fire `HistoryChanged` via Database's emitter). No new bus messages.
- **Compat firewall:** the currency-name lookup is presence-gated in `core/Compat.lua`.
- Run `lua tests/run.lua` (0 failures) + `luacheck .` (0/0) before every commit. No version bump. English only.
- Regenerate `docs/test-cases.md` + bump the README Tests badge in Task 4.

---

### Task 1: Storage + Filters currency-blacklist API + Compat.CurrencyName

**Files:**
- Modify: `defaults/Global.lua` (add `currencyBlacklist = {}`)
- Modify: `core/Compat.lua` (`CurrencyName`)
- Modify: `modules/Filters.lua` (currency-blacklist methods + `ParseCurrencyID`; include in `ClearList`/`ClearAll`)
- Test: `tests/test_filters.lua`, `tests/test_compat.lua`

**Interfaces produced:**
- `NS.Filters:CurrencyBlacklist() -> set`
- `NS.Filters:IsCurrencyBlacklisted(id) -> bool`
- `NS.Filters:AddCurrencyBlacklist(id) -> bool` (true when it changed)
- `NS.Filters:RemoveCurrencyBlacklist(id) -> bool`
- `NS.Filters:ParseCurrencyID(input) -> number | nil` (currency link or bare number)
- `NS.Compat.CurrencyName(currencyID) -> string | nil`

- [ ] **Step 1: Write the failing tests**

In `tests/test_filters.lua`, add:

```lua
test("Filters: currency blacklist add / remove / query", function()
  NS.db.global.currencyBlacklist = {}
  assertFalse(NS.Filters:IsCurrencyBlacklisted(3008))
  assertTrue(NS.Filters:AddCurrencyBlacklist(3008))
  assertTrue(NS.Filters:IsCurrencyBlacklisted(3008))
  assertFalse(NS.Filters:AddCurrencyBlacklist(3008))   -- already present -> no change
  assertTrue(NS.Filters:RemoveCurrencyBlacklist(3008))
  assertFalse(NS.Filters:IsCurrencyBlacklisted(3008))
  assertFalse(NS.Filters:RemoveCurrencyBlacklist(3008)) -- absent -> no change
end)

test("Filters: currency blacklist is independent of the item id lists", function()
  NS.db.global.blacklist = {}; NS.db.global.currencyBlacklist = {}
  NS.Filters:AddBlacklist(3008)            -- item id 3008
  NS.Filters:AddCurrencyBlacklist(3008)    -- currency id 3008 (same number, different namespace)
  assertTrue(NS.Filters:IsBlacklisted(3008))
  assertTrue(NS.Filters:IsCurrencyBlacklisted(3008))
  NS.Filters:RemoveCurrencyBlacklist(3008)
  assertTrue(NS.Filters:IsBlacklisted(3008))          -- item list untouched
  assertFalse(NS.Filters:IsCurrencyBlacklisted(3008))
  NS.db.global.blacklist = {}
end)

test("Filters: ClearList and ClearAll include the currency blacklist", function()
  NS.db.global.currencyBlacklist = {}; NS.db.global.blacklist = {}; NS.db.global.whitelist = {}
  NS.Filters:AddCurrencyBlacklist(3008); NS.Filters:AddCurrencyBlacklist(2914)
  assertEqual(NS.Filters:ClearList("currencyBlacklist"), 2)
  assertFalse(NS.Filters:IsCurrencyBlacklisted(3008))
  NS.Filters:AddBlacklist(1); NS.Filters:AddWhitelist(2); NS.Filters:AddCurrencyBlacklist(3008)
  local removed = NS.Filters:ClearAll()
  assertEqual(removed, 3)
  assertFalse(NS.Filters:IsCurrencyBlacklisted(3008))
end)

test("Filters: ParseCurrencyID reads a currency link or a bare number", function()
  assertEqual(NS.Filters:ParseCurrencyID("|cffffffff|Hcurrency:3008::|h[Valorstones]|h|r"), 3008)
  assertEqual(NS.Filters:ParseCurrencyID("  2914  "), 2914)
  assertEqual(NS.Filters:ParseCurrencyID("|Hitem:5::|h[x]|h"), nil)   -- an item link is not a currency
  assertEqual(NS.Filters:ParseCurrencyID("abc"), nil)
end)
```

In `tests/test_compat.lua`, add:

```lua
test("Compat: CurrencyName resolves via C_CurrencyInfo, nil when unknown", function()
  assertEqual(NS.Compat.CurrencyName(3008), "Valorstones")
  assertEqual(NS.Compat.CurrencyName(999999), nil)
  assertEqual(NS.Compat.CurrencyName(nil), nil)
end)
```

- [ ] **Step 2: Add the `GetCurrencyInfo` mock accessor by id**

The `C_CurrencyInfo` mock (added earlier in `tests/wow_mock.lua`) has `GetCurrencyInfoFromLink` but the name-by-id path needs `GetCurrencyInfo`. In `tests/wow_mock.lua`, inside the `M.C_CurrencyInfo = { ... }` table, add a `GetCurrencyInfo` function:

```lua
    GetCurrencyInfo = function(id)
      local name = M.__currencyNames[id]
      if not name then return nil end
      return { name = name, iconFileID = 100000 + id, quantity = 0 }
    end,
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `lua tests/run.lua 2>&1 | grep -E "currency blacklist|CurrencyName|ParseCurrencyID|FAIL"`
Expected: FAILs — the new methods don't exist.

- [ ] **Step 4: Add `Compat.CurrencyName`**

In `core/Compat.lua`, next to `GetCurrencyInfoFromLink` / `CurrencyCategory`, add:

```lua
-- Display name for a currency id (nil when uncached / API absent). Used by the Filters panel to
-- label a stored currency-blacklist entry.
function Compat.CurrencyName(currencyID)
  if not currencyID then return nil end
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if info then return info.name end
  end
  return nil
end
```

- [ ] **Step 5: Add the Filters currency-blacklist API**

In `modules/Filters.lua`:

(a) After `function F:Whitelist() ... end`, add:

```lua
-- Currency blacklist — currency ids that must NOT be recorded when looted (point-in-time, like the
-- item lists). Stored separately from the item blacklist because itemID and currencyID share the
-- numeric namespace. Blacklist only: there is no currency whitelist.
function F:CurrencyBlacklist() return currentSet("currencyBlacklist") end
function F:IsCurrencyBlacklisted(id)
  id = tonumber(id)
  return id ~= nil and currentSet("currencyBlacklist")[id] == true
end
```

(b) After the `F:AddWhitelist`/`RemoveWhitelist` definitions, add a plain add (no sibling list to reconcile) + reuse `_remove`:

```lua
-- Add / remove a currency id on the currency blacklist. No sibling reconciliation (blacklist only).
function F:AddCurrencyBlacklist(id)
  id = tonumber(id)
  if not id then return false end
  local target = currentSet("currencyBlacklist")
  if target[id] then return false end
  local t = setCopy(target); t[id] = true; NS.db.global.currencyBlacklist = t
  self:_notify("currencyBlacklist")
  return true
end
function F:RemoveCurrencyBlacklist(id) return self:_remove("currencyBlacklist", id) end
```

(c) In `F:ClearList`, widen the guard to accept the new key:

```lua
  if listKey ~= "blacklist" and listKey ~= "whitelist" and listKey ~= "currencyBlacklist" then return 0 end
```

(d) In `F:ClearAll`, include the currency blacklist in the count and the wipe:

```lua
function F:ClearAll()
  local removed = self:Count(self:Blacklist()) + self:Count(self:Whitelist())
    + self:Count(self:CurrencyBlacklist())
  if removed == 0 then return 0 end
  NS.db.global.blacklist = {}
  NS.db.global.whitelist = {}
  NS.db.global.currencyBlacklist = {}
  self:_notify("clearall")
  return removed
end
```

(e) After `F:ParseItemID`, add:

```lua
-- Extract a currency id from free-form input: a bare number, or a currency link the user shift-
-- clicked. Returns a number, or nil. (A currency add-box is unambiguously for currencies, so a bare
-- number is treated as a currencyID; an item link does not match.)
function F:ParseCurrencyID(input)
  if type(input) == "number" then return input end
  if type(input) ~= "string" then return nil end
  input = input:match("^%s*(.-)%s*$")
  local fromLink = input:match("|Hcurrency:(%d+)") or input:match("^currency:(%d+)")
  if fromLink then return tonumber(fromLink) end
  return tonumber(input)
end
```

- [ ] **Step 6: Add the default**

In `defaults/Global.lua`, next to the `blacklist = {}` / `whitelist = {}` lines, add:

```lua
  currencyBlacklist = {},  -- { [currencyID] = true } — currencies never recorded on capture
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `lua tests/run.lua 2>&1 | tail -2 && luacheck . 2>&1 | tail -2`
Expected: all pass; luacheck clean.

- [ ] **Step 8: Commit**

```bash
git add defaults/Global.lua core/Compat.lua modules/Filters.lua tests/test_filters.lua tests/test_compat.lua tests/wow_mock.lua
git commit -m "feat(currency): currency-blacklist storage + Filters API"
```

---

### Task 2: Collector honors the currency blacklist

**Files:**
- Modify: `modules/Collector.lua`
- Test: `tests/test_collector.lua`

**Interfaces:** Consumes `NS.Filters` list via the Collector's upvalue cache. Currency gate becomes: `enabled` + `recordCurrency` + not source-muted + **not currency-blacklisted**.

- [ ] **Step 1: Write the failing test**

In `tests/test_collector.lua`, after the existing currency tests, add:

```lua
test("Collector: a blacklisted currency is dropped, records after un-blacklisting", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.global.settings.recordCurrency = true
  NS.db.global.currencyBlacklist = {}
  NS.Filters:AddCurrencyBlacklist(3008)     -- the mock currency id
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("MPLUS", nil, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgCurrency(nil, string.format(mocks.CURRENCY_GAINED, CURRENCY_LINK))
  assertEqual(NS.Database:Count(), before)   -- blacklisted -> dropped

  NS.Filters:RemoveCurrencyBlacklist(3008)
  NS.Collector:RefreshUpvalues()
  NS.Collector:OnChatMsgCurrency(nil, string.format(mocks.CURRENCY_GAINED, CURRENCY_LINK))
  assertEqual(NS.Database:Count(), before + 1)
end)
```

(`CURRENCY_LINK` is the local already defined earlier in this test file by the currency-capture tests: `"|cffffffff|Hcurrency:3008::|h[Valorstones]|h|r"`.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -E "blacklisted currency|FAIL"`
Expected: FAIL — the currency is still recorded.

- [ ] **Step 3: Cache the currency blacklist upvalue**

In `modules/Collector.lua`, change the currency upvalue line (near line 10):

```lua
local recordCurrency = true
```
to:
```lua
local recordCurrency = true
local currencyBlacklist = {}
```

In `Collector:RefreshUpvalues`, after `recordCurrency = s.recordCurrency`, add:

```lua
  currencyBlacklist = g.currencyBlacklist or {}
```

- [ ] **Step 4: Gate on it in `OnChatMsgCurrency`**

In `modules/Collector.lua`, in `OnChatMsgCurrency`, right after the `if not currencyID then return end` line, add:

```lua
  if currencyBlacklist[currencyID] then
    if NS.State.debug and NS.Debug then
      NS.Debug("Drop", "currency %s id=%s reason=blacklist", tostring(name), tostring(currencyID))
    end
    return
  end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `lua tests/run.lua 2>&1 | tail -2 && luacheck . 2>&1 | tail -2`
Expected: all pass; luacheck clean.

- [ ] **Step 6: Commit**

```bash
git add modules/Collector.lua tests/test_collector.lua
git commit -m "feat(currency): drop blacklisted currencies on capture"
```

---

### Task 3: UI — right-click action + Filters panel section

**Files:**
- Modify: `modules/BrowserTable.lua` (row menu "Blacklist currency")
- Modify: `settings/Panel.lua` (Currencies filter section + a currency name label + clear popup registration)
- Modify: `core/LootHistory.lua` or wherever `StaticPopupDialogs` are registered — search for `KA0S_LOOTHISTORY_CLEAR_BLACKLIST` and add a `KA0S_LOOTHISTORY_CLEAR_CURRENCY` sibling.

**Note:** frame code — NOT headless-unit-tested. Verify with `luacheck .` (0/0) and `lua tests/run.lua` (module loads, 0 failures). Visual behavior is smoke-tested (Task 4 adds the step).

- [ ] **Step 1: Add the row-menu action**

In `modules/BrowserTable.lua`, in `BrowserTable:ShowRowMenu`, in the `items` table, add a "Blacklist currency" entry after the "Blacklist item" entry (it is enabled only for currency rows, so item rows show the disabled/absent state cleanly — follow the same `enabled` pattern):

```lua
    -- Blacklist this currency: stop recording future loots of this currency id. Point-in-time.
    { label = "Blacklist currency", enabled = record.currencyID ~= nil, fn = function()
        if NS.Filters and NS.Filters:AddCurrencyBlacklist(record.currencyID) and NS.Print then
          NS.Print(("blacklisted %s. Manage in Settings \226\150\184 Filters."):format(
            record.itemName or ("currency " .. tostring(record.currencyID))))
        end
      end },
```

- [ ] **Step 2: Add a currency-name label helper in the panel**

In `settings/Panel.lua`, near `filterEntryLabel` (the item-name label used by `rebuildFilterList`), add a currency variant that resolves the name via `NS.Compat.CurrencyName`, else `"Currency <id>"`:

```lua
-- Label for a currency-blacklist entry: the currency's name (grey id suffix), or a placeholder.
local function currencyEntryLabel(id)
  local name = NS.Compat.CurrencyName and NS.Compat.CurrencyName(id)
  if not name then return "|cffaaaaaaCurrency " .. id .. "|r" end
  return name .. "  |cff808080(" .. id .. ")|r"
end
```

- [ ] **Step 3: Generalize `rebuildFilterList` + `makeFilterSection` for the currency list**

The cleanest approach: parameterize the two functions on a small descriptor rather than the `listKey == "blacklist"` branches. In `settings/Panel.lua`:

- In `rebuildFilterList`, replace the hardcoded item set/label/remove with currency-aware branches keyed on `listKey == "currencyBlacklist"`:
  - set: `NS.Filters:CurrencyBlacklist()` when `listKey == "currencyBlacklist"`, else the existing item lists.
  - label: `currencyEntryLabel(id)` when currency, else `filterEntryLabel(...)`.
  - remove: `NS.Filters:RemoveCurrencyBlacklist(id)` when currency.
- In `makeFilterSection`, the add-box `submit()` uses `NS.Filters:ParseCurrencyID` + `NS.Filters:AddCurrencyBlacklist` when `listKey == "currencyBlacklist"` (box label "Add currency id or link"), else the existing item path. The Clear popup uses `"KA0S_LOOTHISTORY_CLEAR_CURRENCY"` for the currency section.
- In `buildFilters`, add a third section after whitelist:

```lua
  makeFilterSection(ctx, "currencyBlacklist", "Blacklisted currencies",
    "Currencies here are never recorded when looted from now on (Valorstones, crests, Honor, etc.). "
    .. "Point-in-time — existing rows are left untouched.")
```

Keep each branch minimal and mirror the existing item code exactly; do not restructure unrelated parts of the panel.

- [ ] **Step 4: Register the clear-confirm popup**

Find where `KA0S_LOOTHISTORY_CLEAR_BLACKLIST` / `KA0S_LOOTHISTORY_CLEAR_WHITELIST` are registered in `StaticPopupDialogs` (grep the repo). Add a `KA0S_LOOTHISTORY_CLEAR_CURRENCY` entry mirroring the blacklist one, whose `OnAccept` calls `NS.Filters:ClearList("currencyBlacklist")` and reports the count.

- [ ] **Step 5: Verify load + lint**

Run: `luacheck . 2>&1 | tail -2 && lua tests/run.lua 2>&1 | tail -2`
Expected: luacheck 0/0; all tests still pass (the panel/menu are frame code — they must load without error).

- [ ] **Step 6: Commit**

```bash
git add modules/BrowserTable.lua settings/Panel.lua core/LootHistory.lua
git commit -m "feat(currency): blacklist-currency row action + Filters panel section"
```

(Adjust the `git add` file list to wherever the StaticPopup is actually registered.)

---

### Task 4: Docs, smoke test, badge

**Files:** `docs/data-model.md`, `docs/attribution.md` (or the currency capture note), `docs/scope.md`, `docs/smoke-tests.md`, `docs/test-cases.md`, `README.md`, and the `Filters.lua` header comment (already covered by the code comments in Task 1 — only touch docs/ here).

- [ ] **Step 1: Document the currency blacklist**

- `docs/data-model.md`: note `global.currencyBlacklist` as a carve-out set alongside `blacklist`/`whitelist`, keyed by currencyID, point-in-time, blacklist-only.
- `docs/scope.md`: extend the currency in-scope bullet (or the existing blacklist/whitelist mention) to note currencies can be blacklisted (no currency whitelist).
- The currency section of `docs/attribution.md` (added in the capture feature): add that the currency gate also drops currency-blacklisted ids.

- [ ] **Step 2: Add a smoke step**

In `docs/smoke-tests.md`, in the Blacklist & whitelist section (§16) or the currency scenario, add: right-click a currency row → **Blacklist currency**; that currency stops recording; it appears under **Settings ▸ Filters ▸ Blacklisted currencies** (name resolved), removable there; Clear-all works.

- [ ] **Step 3: Regenerate inventory + bump badge**

Run `lua tests/run.lua --list > docs/test-cases.md`, read the new `| **Total** | **N** |`, and set the README Tests badge to `N/N`.

- [ ] **Step 4: Verify + commit**

Run `lua tests/run.lua` (0 failures) + `luacheck .` (0/0); confirm badge == inventory total.

```bash
git add docs/data-model.md docs/scope.md docs/attribution.md docs/smoke-tests.md docs/test-cases.md README.md
git commit -m "docs(currency): document currency blacklist + smoke + badge"
```

---

## Self-Review

- **Coverage:** storage+API (T1), capture gate (T2), UI both entry points (T3), docs/badge (T4) — matches the approved design (blacklist-only, right-click + panel, point-in-time). ✓
- **Placeholder scan:** none. The Task-3 StaticPopup file is "grep to locate" — a real lookup, not a placeholder; the entry to add is fully specified. ✓
- **Type consistency:** `currencyBlacklist` set shape `{[currencyID]=true]}`, `AddCurrencyBlacklist`/`RemoveCurrencyBlacklist`/`IsCurrencyBlacklisted`/`ParseCurrencyID`/`CurrencyName` names used identically across T1→T2→T3. ✓
