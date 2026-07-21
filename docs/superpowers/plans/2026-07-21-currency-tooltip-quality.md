# Currency Tooltip + Quality Colour Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** In the History browser, (1) show the in-game currency tooltip on hover over a currency row, and (2) colour the currency Name + fill the Quality column using the currency's quality tier — storing quality at capture, and backfilling existing rows once via a migration.

**Architecture:** A currency's quality tier comes from `C_CurrencyInfo`. Store it on the record at capture (`record.quality`). The History table already colours the Item/Quality cells via `qualityColor(r.quality)` and shows the Quality label, so once quality is stored those work with no render change. A one-time `v3 → v4` schema migration backfills `quality` on currency rows looted before this change. The row hover gains a currency branch using `GameTooltip:SetCurrencyByID`.

**Tech stack:** Lua 5.1, Ace3, headless `lua tests/run.lua` + `luacheck`.

**Design source:** approved in conversation 2026-07-21 (store-at-capture + one-time migration backfill; no render-time fallback).

## Global Constraints

- **Branch `feature/currency-capture`** (rides with the currency feature). Never `master`.
- Account-wide storage; **Compat firewall** — the currency-quality lookup is presence-gated in `core/Compat.lua`. Backfill runs in-game only (C_CurrencyInfo), best-effort (unresolvable ids stay nil).
- Migration is **idempotent + non-destructive** (only fills a nil `quality` on `currencyID` rows), following the existing `RunMigrations` v1→v2→v3 pattern; bump the stamp to 4.
- Currency stays **excluded from the Insights quality-distribution chart** (already guarded on `currencyID`); storing quality does not change that.
- Run `lua tests/run.lua` (0 failures) + `luacheck .` (0/0) before every commit. No version bump (the addon `## Version` — the DB `schemaVersion` is a different thing and DOES go to 4). English only. Regenerate `docs/test-cases.md` + bump the README Tests badge in Q3.

---

### Task 1: Store currency quality at capture + v3→v4 backfill migration

**Files:**
- Modify: `tests/wow_mock.lua` (add `quality` to the `C_CurrencyInfo.GetCurrencyInfo` mock)
- Modify: `core/Compat.lua` (`CurrencyQuality`)
- Modify: `modules/Collector.lua` (store `quality` on the currency record)
- Modify: `core/Database.lua` (`RunMigrations` v3→v4)
- Modify: `tests/test_compat.lua`, `tests/test_collector.lua`, `tests/test_util.lua` (schemaVersion), `tests/test_database.lua` (migration)

**Interfaces produced:** `NS.Compat.CurrencyQuality(currencyID) -> number | nil`.

- [ ] **Step 1: Add `quality` to the currency mock**

In `tests/wow_mock.lua`, in the `M.C_CurrencyInfo` table, update the `GetCurrencyInfo` function so it returns a `quality` (use `4` = Epic, matching typical currencies):

```lua
    GetCurrencyInfo = function(id)
      local name = M.__currencyNames[id]
      if not name then return nil end
      return { name = name, iconFileID = 100000 + id, quantity = 0, quality = 4 }
    end,
```

(If `GetCurrencyInfo` is not yet present in the mock, add it with the body above.)

- [ ] **Step 2: Write the failing tests**

In `tests/test_compat.lua`:

```lua
test("Compat: CurrencyQuality returns the tier, nil when unknown", function()
  assertEqual(NS.Compat.CurrencyQuality(3008), 4)
  assertEqual(NS.Compat.CurrencyQuality(999999), nil)
  assertEqual(NS.Compat.CurrencyQuality(nil), nil)
end)
```

In `tests/test_database.lua`:

```lua
test("Migrations: v3->v4 backfills currency-record quality", function()
  local g = NS.db.global
  local savedVer, savedHist = g.schemaVersion, g.history
  g.history = {
    { currencyID = 3008, itemName = "Valorstones", itemType = "Currency", quantity = 5 }, -- no quality
    { itemID = 111, itemName = "Sword", quality = 4 },                                     -- item untouched
    { currencyID = 2914, itemName = "Crest", itemType = "Currency", quality = 3 },         -- already set
  }
  g.schemaVersion = 3
  NS:RunMigrations()
  assertEqual(g.schemaVersion, 4)
  assertEqual(g.history[1].quality, 4)   -- backfilled from the mock (Epic)
  assertEqual(g.history[2].quality, 4)   -- item unchanged
  assertEqual(g.history[3].quality, 3)   -- already-set currency unchanged
  g.history, g.schemaVersion = savedHist, savedVer   -- restore shared state
end)
```

In `tests/test_collector.lua`, update the existing currency capture test "Collector: end-to-end records a currency line as Type=Currency": change the `assertEqual(r.quality, nil)` line to:

```lua
  assertEqual(r.quality, 4)   -- currency quality now stored at capture (from C_CurrencyInfo mock)
```

In `tests/test_util.lua`, the "Database: InitDB creates account-wide store" test asserts `assertEqual(NS.db.global.schemaVersion, 3)` — change it to:

```lua
  assertEqual(NS.db.global.schemaVersion, 4)
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `lua tests/run.lua 2>&1 | grep -E "CurrencyQuality|v3->v4|schemaVersion|Type=Currency|FAIL"`
Expected: FAILs — `CurrencyQuality` missing, migration not present (schemaVersion stays 3), capture doesn't store quality.

- [ ] **Step 4: Add `Compat.CurrencyQuality`**

In `core/Compat.lua`, next to `CurrencyName` / `GetCurrencyInfoFromLink`:

```lua
-- Quality tier (Enum.ItemQuality) for a currency id, from C_CurrencyInfo; nil when uncached/absent.
-- Colours the currency name + fills the Quality column, and drives the v3->v4 backfill migration.
function Compat.CurrencyQuality(currencyID)
  if not currencyID then return nil end
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if info then return info.quality end
  end
  return nil
end
```

- [ ] **Step 5: Store quality on the currency record**

In `modules/Collector.lua`, in `OnChatMsgCurrency`, add `quality` to the `record` table literal (e.g. right after `currencyID = currencyID,` / near `itemName`):

```lua
    quality = NS.Compat.CurrencyQuality(currencyID),
```

- [ ] **Step 6: Add the v3→v4 migration**

In `core/Database.lua`, in `NS:RunMigrations`, after the `if g.schemaVersion < 3 then … end` block, add:

```lua
  -- v3 -> v4: backfill currency-record quality (rows with currencyID but no quality) from
  -- C_CurrencyInfo, so the History browser can colour the currency name + fill the Quality column
  -- for currencies looted before quality was captured. In-game only (C_CurrencyInfo); a currency the
  -- client can't resolve at init stays nil. Non-destructive.
  if g.schemaVersion < 4 then
    local n = 0
    for _, r in ipairs(g.history or {}) do
      if r.currencyID and r.quality == nil then
        local q = NS.Compat.CurrencyQuality(r.currencyID)
        if q ~= nil then r.quality = q; n = n + 1 end
      end
    end
    g.schemaVersion = 4
    if NS.State.debug and NS.Debug then NS.Debug("Migrate", "%s", NS.MigrationSummary(3, 4, n)) end
  end
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `lua tests/run.lua 2>&1 | tail -2 && luacheck . 2>&1 | tail -2`
Expected: all pass; luacheck clean. (If another test hardcodes `schemaVersion == 3` or a currency `quality == nil`, update it to the new value — grep `schemaVersion` and currency `quality` assertions to be sure.)

- [ ] **Step 8: Commit**

```bash
git add tests/wow_mock.lua core/Compat.lua modules/Collector.lua core/Database.lua tests/test_compat.lua tests/test_collector.lua tests/test_util.lua tests/test_database.lua
git commit -m "feat(currency): store quality at capture + v3->v4 backfill migration"
```

---

### Task 2: Currency tooltip on row hover

**Files:**
- Modify: `modules/BrowserTable.lua` (row `OnEnter`)

**Note:** frame code — NOT headless-unit-tested. Verify with `luacheck .` (0/0) and `lua tests/run.lua` (module loads, 0 failures). Visual behavior is smoke-tested (Q3 adds the step).

- [ ] **Step 1: Add the currency branch to the hover handler**

In `modules/BrowserTable.lua`, replace the row `OnEnter` script (currently gated on `e.record.itemLink`) so it also shows the currency tooltip for currency rows:

```lua
  row:SetScript("OnEnter", function(self2)
    local e = self2.entry
    if not (e and e.kind == "row") then return end
    local r = e.record
    local shown = false
    if r.itemLink then
      GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(r.itemLink)
      shown = true
    elseif r.currencyID and GameTooltip.SetCurrencyByID then
      GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
      GameTooltip:SetCurrencyByID(r.currencyID)
      shown = true
    end
    if shown then
      if r.confidence == "INFERRED" then
        GameTooltip:AddLine("Source inferred (uncertain).", 0.62, 0.62, 0.62)
      end
      GameTooltip:AddLine("Shift-click to link \194\183 right-click for options", 0.5, 0.5, 0.5)
      GameTooltip:Show()
    end
  end)
```

(Preserve the existing `OnLeave` handler that hides the tooltip.)

- [ ] **Step 2: Verify load + lint**

Run: `luacheck . 2>&1 | tail -2 && lua tests/run.lua 2>&1 | tail -2`
Expected: luacheck 0/0; all tests pass (module loads).

- [ ] **Step 3: Commit**

```bash
git add modules/BrowserTable.lua
git commit -m "feat(currency): in-game currency tooltip on History row hover"
```

---

### Task 3: Docs, smoke, badge

**Files:** `docs/data-model.md`, `docs/scope.md`, `docs/smoke-tests.md`, `docs/superpowers/specs/2026-07-21-currency-capture-design.md`, `docs/test-cases.md`, `README.md`.

- [ ] **Step 1: Update the docs**

- `docs/superpowers/specs/2026-07-21-currency-capture-design.md` §3: the record shape comment says `quality … = nil` — amend to note currency now stores its `C_CurrencyInfo` quality (for the name colour + Quality column), still excluded from item-centric quality aggregates.
- `docs/data-model.md`: note currency records now carry `quality` (the currency's tier), and the `v3 → v4` migration backfills it for pre-existing rows.
- `docs/scope.md`: extend the currency bullet to mention the coloured name + Quality column + hover tooltip.

- [ ] **Step 2: Add smoke steps**

In `docs/smoke-tests.md`, add to the currency scenario: hovering a currency row shows the **in-game currency tooltip**; the currency **Name is quality-coloured** and the **Quality column shows the tier**; after a `/reload` the **v3→v4 migration backfills** quality on currency rows looted before this change (older rows go from white/blank to coloured/filled). If the `schemaVersion` is quoted anywhere in §1 as an old value, update it to `4`.

- [ ] **Step 3: Regenerate inventory + bump badge**

Run `lua tests/run.lua --list > docs/test-cases.md`, read the new `| **Total** | **N** |`, set the README Tests badge to `N/N` (do NOT touch the version badge/number).

- [ ] **Step 4: Verify + commit**

Run `lua tests/run.lua` (0 failures) + `luacheck .` (0/0); confirm badge == inventory total.

```bash
git add docs/data-model.md docs/scope.md docs/smoke-tests.md docs/superpowers/specs/2026-07-21-currency-capture-design.md docs/test-cases.md README.md
git commit -m "docs(currency): quality colour + tooltip + backfill migration; smoke + badge"
```

---

## Self-Review

- **Coverage:** quality store+migration (Task 1), tooltip (Task 2), docs/badge (Task 3) — matches the approved design (store-at-capture + one-time migration backfill; tooltip via SetCurrencyByID). ✓
- **Breaking-test callouts:** Task 1 explicitly updates the two existing assertions that storing quality / bumping schemaVersion invalidates (`test_collector` currency `quality`, `test_util` `schemaVersion`), and reminds the implementer to grep for others. ✓
- **Placeholder scan:** none. ✓
- **Type consistency:** `CurrencyQuality(currencyID) -> number|nil`, `record.quality`, `schemaVersion == 4` used consistently across Tasks 1-3. ✓
