# Point-in-time Blacklist/Whitelist — Remove Soft-Add/Soft-Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make blacklist/whitelist strictly point-in-time — a looted item's presence in the DB is decided once, at loot time; nothing hides or resurrects a stored row afterward.

**Architecture:** Remove the `viaWhitelist` per-record flag and the entire read-time hide seam (`Database:VisibleHistory` + the whitelist-orphan index). Capture already does the right thing (blacklist vetoes, whitelist rescues below-gate items). A one-time, non-destructive schema migration (v1→v2) strips the dead `viaWhitelist` field from existing rows; previously-hidden rows simply become visible again.

**Tech Stack:** Lua 5.1, Ace3, headless test harness under `tests/` (`lua tests/run.lua`), `luacheck`.

## Global Constraints

- **Account-wide storage only** — `LootHistoryDB.global`; never per-character profiles.
- **Closed message bus** — the three `Ka0s_LootHistory_*` messages are the only inter-module channel; Database stays the sole sender of `HistoryChanged`.
- **Blacklist/whitelist carve-out is ratified** — the id-sets live in `db.global.{blacklist,whitelist}`, mutated directly (not via `Schema:Set`). Do not change this.
- **Never bump the addon version** (TOC `## Version`, `NS.version`, README badge/history) — not part of this work.
- **Never auto-stage/commit/push** unless a task step explicitly says to commit; the commit steps below are authorized.
- **Test inventory & badge stay in sync** — when the suite changes, regenerate `docs/test-cases.md` and update the README `tests` badge in the same change (Task 6).
- **Local verification before every commit** — `lua tests/run.lua` (exits non-zero on failure) and `luacheck .` (0 errors).
- English only. Retail (WoW 12.0.7), no game-flavor branching.

## Target behavior

| Operation | New behavior |
|---|---|
| Loot a blacklisted item | Dropped at capture — never written. (Already the case.) |
| Loot a whitelisted below-gate item | Written as a plain record — **no** flag. |
| Remove an id from the whitelist | No effect on existing records. |
| Add an id to the blacklist | No effect on existing records — future loots only. |
| Read (browser / export / insights) | Returns raw stored history — no hide. |

## Test harness reference

Test files begin with:
```lua
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse
```
Run a single file's tests via the full suite: `lua tests/run.lua`. There is no per-test CLI filter; run the whole suite and read the summary line.

---

### Task 1: Schema migration v1→v2 — strip the dead `viaWhitelist` field

**Files:**
- Modify: `core/Database.lua:14-24` (`NS:RunMigrations`)
- Test: `tests/test_database.lua` (add one test near the other migration/init coverage)

**Interfaces:**
- Consumes: `NS.db.global.history`, `NS.db.global.schemaVersion`, `NS.MigrationSummary(from,to,rows)` (already exists).
- Produces: after init, `NS.db.global.schemaVersion == 2` and no stored row has a `viaWhitelist` field.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_database.lua`:
```lua
test("Database: RunMigrations v1->v2 strips viaWhitelist and bumps schemaVersion", function()
  NS.db.global.schemaVersion = 1
  NS.db.global.history = {
    { ts = 1, itemID = 4, itemName = "Normal", quality = 3 },
    { ts = 2, itemID = 5, itemName = "Was via whitelist", quality = 0, viaWhitelist = true },
  }
  NS:RunMigrations()
  assertEqual(NS.db.global.schemaVersion, 2)
  assertTrue(NS.db.global.history[2].viaWhitelist == nil)  -- field stripped
  assertEqual(#NS.db.global.history, 2)                    -- nothing deleted
end)
```

- [ ] **Step 2: Run the suite to verify the new test fails**

Run: `lua tests/run.lua`
Expected: FAIL — the row still has `viaWhitelist == true` (migration is a no-op today), and `schemaVersion` stays 1.

- [ ] **Step 3: Implement the migration**

Replace the body of `NS:RunMigrations` (`core/Database.lua:14-24`) with:
```lua
function NS:RunMigrations()
  local g = NS.db and NS.db.global
  if not g then return end
  g.schemaVersion = g.schemaVersion or 1
  -- v1 -> v2: point-in-time filtering (removed soft-add/soft-delete). Strip the retired
  -- per-record `viaWhitelist` flag; rows are never hidden/resurrected after capture. Non-
  -- destructive — no rows are deleted (see docs/superpowers/specs/2026-07-18-*).
  if g.schemaVersion < 2 then
    local n = 0
    for _, r in ipairs(g.history or {}) do
      if r.viaWhitelist ~= nil then r.viaWhitelist = nil; n = n + 1 end
    end
    g.schemaVersion = 2
    if NS.State.debug and NS.Debug then NS.Debug("Migrate", "%s", NS.MigrationSummary(1, 2, n)) end
  end
end
```

- [ ] **Step 4: Run the suite to verify it passes**

Run: `lua tests/run.lua`
Expected: PASS (all tests). Then `luacheck .` → 0 warnings/errors.

- [ ] **Step 5: Commit**

```bash
git add core/Database.lua tests/test_database.lua
git commit -m "feat(filters): v1->v2 migration strips retired viaWhitelist flag"
```

---

### Task 2: Collector — stop stamping `viaWhitelist`

**Files:**
- Modify: `modules/Collector.lua:98-114` (drop the flag), `modules/Collector.lua:23-30` (comment)
- Test: `tests/test_collector.lua:135-160` (rewrite the whitelist end-to-end test)

**Interfaces:**
- Consumes: `Collector:ShouldRecord` (unchanged — still returns `true, "whitelist"` for a rescued item), `NS.Database:Add`, `NS.Database:Count`, `NS.Database:History`.
- Produces: a whitelisted below-gate item is written as a record with **no** `viaWhitelist` field.

- [ ] **Step 1: Rewrite the failing test**

Replace `tests/test_collector.lua:135-160` (the test titled *"Collector: end-to-end whitelist records below threshold, hidden after un-whitelisting"*) with:
```lua
test("Collector: whitelist records below threshold as a plain point-in-time row", function()
  local mocks = T.mocks
  mocks.__now = 0
  NS.db.global.settings.qualityThreshold = 5   -- mock item is quality 4 -> would drop
  NS.Filters:AddWhitelist(211296)
  NS.Collector:RefreshUpvalues()
  NS.Attribution:Stamp("KILL", nil, "CERTAIN")

  local before = NS.Database:Count()
  NS.Collector:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF, LINK))
  assertEqual(NS.Database:Count(), before + 1)   -- whitelisted -> recorded despite the gate

  -- Point-in-time: the row carries NO viaWhitelist annotation.
  local row = NS.Database:History()[NS.Database:Count()]
  assertTrue(row.viaWhitelist == nil)

  -- Removing the id from the whitelist does NOT hide or delete the already-recorded row.
  NS.Filters:RemoveWhitelist(211296)
  assertEqual(NS.Database:Count(), before + 1)                 -- still stored
  assertEqual(#NS.Database:ActiveHistory(), before + 1)        -- still visible

  NS.db.global.settings.qualityThreshold = 2   -- restore
  NS.Collector:RefreshUpvalues()
  NS.Database:Purge()                          -- clean up the synthetic row
end)
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `lua tests/run.lua`
Expected: FAIL — `row.viaWhitelist == nil` assertion fails because Collector still stamps the flag (`row.viaWhitelist == true`).

- [ ] **Step 3: Remove the flag in Collector**

In `modules/Collector.lua`, delete the `viaWhitelist` local (lines 98-101) and the stamp (line 112).

Delete these lines (98-101):
```lua
  -- reason == "whitelist" here means the item ONLY passed because it is whitelisted (it fails the
  -- normal gate). Flag the row so that un-whitelisting the id can hide it again — the "annotation in
  -- the db so the action can be undone" from issue #14. Items that pass the gate normally get no flag.
  local viaWhitelist = (reason == "whitelist") or nil
```

Delete this line (112):
```lua
  record.viaWhitelist = viaWhitelist   -- kept only because whitelisted (issue #14); nil otherwise
```

The `reason` variable from `ShouldRecord` is now unused after the drop check. Change line 87 from:
```lua
  local ok, reason = self:ShouldRecord(quality, source, classID,
```
to keep `reason` (still used in the debug Drop line at 93). **Do not** remove `reason` — it is referenced in the `if not ok` debug branch. Only the `viaWhitelist` local and stamp are removed.

Also update the `ShouldRecord` doc comment (`modules/Collector.lua:26-30`): replace the parenthetical about flagging the row / `Database:VisibleHistory` with point-in-time wording:
```lua
--   true              — passes normally
--   true, "whitelist" — failed the gate but the whitelist forced it in (recorded as a plain
--                       point-in-time row; later whitelist changes never revisit it)
--   false, reason     — dropped ("blacklist"/"quality"/"source"/"quest"), surfaced by the Drop log
```

- [ ] **Step 4: Run the suite to verify it passes**

Run: `lua tests/run.lua`
Expected: PASS. `luacheck .` → 0 (confirm no "unused variable `viaWhitelist`" or similar).

- [ ] **Step 5: Commit**

```bash
git add modules/Collector.lua tests/test_collector.lua
git commit -m "feat(filters): stop stamping viaWhitelist; whitelist writes plain rows"
```

---

### Task 3: Database + State — delete the read-time hide seam

**Files:**
- Modify: `core/Database.lua` — remove `RebuildWhitelistIndex` (52-63), `whitelistOrphanExists` (65-75), `VisibleHistory` (77-98); simplify `ActiveHistory` (105-107); simplify `Add` (114-128); remove `RebuildWhitelistIndex()` calls in `DeleteAt` (382), `Delete` (403), `PruneOld` (465) and the `NS.State.viaWhitelistIDs = {}` line in `Purge` (412); remove the init call at `InitDB` (7).
- Modify: `core/State.lua:18-20` — remove `State.viaWhitelistIDs`.
- Test: `tests/test_database.lua:188-236` — remove the three `VisibleHistory` tests; flip the blacklist-exclusion test.

**Interfaces:**
- Consumes: `NS.State.testRecords`, `NS.db.global.history`.
- Produces: `Database:ActiveHistory()` returns the test dataset if set, else the raw `history` array (no hide, no allocation). `VisibleHistory`, `RebuildWhitelistIndex`, and `NS.State.viaWhitelistIDs` no longer exist.

- [ ] **Step 1: Rewrite the failing tests**

In `tests/test_database.lua`, **delete** these three tests entirely:
- *"Database: VisibleHistory hides blacklisted ids but keeps them in history"* (188-197)
- *"Database: VisibleHistory returns the raw array unchanged when nothing is hidden"* (199-204)
- *"Database: VisibleHistory hides a viaWhitelist row once its id leaves the whitelist"* (206-226)

**Replace** the test *"Database: Query/Stats/Export all exclude blacklisted ids via ActiveHistory"* (228-236) with:
```lua
test("Database: blacklist does NOT hide already-stored rows (point-in-time)", function()
  seed()
  NS.db.global.blacklist = { [3] = true }
  assertEqual(#NS.Database:Query({}), 4)              -- existing rows stay visible
  assertEqual(NS.Database:Stats({}).totals.records, 4)
  assertEqual(#NS.Database:Export({}), 4)
  NS.db.global.blacklist = {}
end)

test("Database: ActiveHistory returns raw history (no hide, same reference)", function()
  seed()
  NS.db.global.blacklist = { [2] = true }
  assertTrue(NS.Database:ActiveHistory() == NS.db.global.history)  -- no allocation, no filtering
  NS.db.global.blacklist = {}
end)
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `lua tests/run.lua`
Expected: FAIL — the new "blacklist does NOT hide" test fails (today `Query` returns 3, not 4, because `VisibleHistory` still filters), and/or the deleted `VisibleHistory` tests are gone so the remaining ones exercise old behavior.

- [ ] **Step 3: Remove the hide seam in `core/Database.lua`**

3a. In `NS:InitDB` (line 4-8), remove line 7:
```lua
  NS.Database:RebuildWhitelistIndex()   -- session index for the whitelist-orphan hide (issue #14)
```
so `InitDB` becomes:
```lua
function NS:InitDB()
  NS.db = LibStub("AceDB-3.0"):New("LootHistoryDB", NS.defaults, true)
  NS:RunMigrations()   -- normalize the persisted schema before any history read
end
```

3b. Delete `Database:RebuildWhitelistIndex` (52-63), the local `whitelistOrphanExists` (65-75), and `Database:VisibleHistory` (77-98) in their entirety — including their leading comment blocks (52-55, 65-66, 77-83).

3c. Replace `Database:ActiveHistory` (100-107) with:
```lua
-- The dataset every read-path query (Query/Stats/Export, and thus the table + Insights tab)
-- resolves against. In Browser test mode this is the synthetic preview dataset published to
-- State by BrowserTable:ToggleTestMode; otherwise it is the live account-wide history. Filtering
-- is point-in-time (decided at capture) — reads never hide stored rows.
function Database:ActiveHistory()
  return (NS.State and NS.State.testRecords) or NS.db.global.history
end
```

3d. Simplify `Database:Add` (113-128) — remove the whitelist-index block (118-123):
```lua
-- Append a record to the account-wide history; fire RecordAdded; return its index.
function Database:Add(record)
  local history = NS.db.global.history
  history[#history + 1] = record
  local index = #history
  if NS.bus then
    NS.bus:SendMessage("Ka0s_LootHistory_RecordAdded", record, index)
  end
  return index
end
```

3e. In `Database:DeleteAt` (377-388), remove line 382:
```lua
  self:RebuildWhitelistIndex()   -- a viaWhitelist row may have gone
```

3f. In `Database:Delete` (392-406), remove line 403:
```lua
  self:RebuildWhitelistIndex()
```

3g. In `Database:Purge` (409-418), remove line 412:
```lua
  NS.State.viaWhitelistIDs = {}
```

3h. In `Database:PruneOld` (454-471), remove line 465:
```lua
  self:RebuildWhitelistIndex()
```

- [ ] **Step 4: Remove `State.viaWhitelistIDs`**

In `core/State.lua`, delete lines 18-20 (the `State.viaWhitelistIDs` declaration and its two comment continuation lines).

- [ ] **Step 5: Guard against stragglers**

Run: `grep -rn "viaWhitelist\|VisibleHistory\|RebuildWhitelistIndex\|whitelistOrphan" --include=*.lua .`
Expected: **no matches in `core/`, `modules/`, `settings/`, `tests/`** (docs are handled in Task 5). If any remain, remove/fix them before continuing.

- [ ] **Step 6: Run the suite to verify it passes**

Run: `lua tests/run.lua`
Expected: PASS. Then `luacheck .` → 0.

- [ ] **Step 7: Commit**

```bash
git add core/Database.lua core/State.lua tests/test_database.lua
git commit -m "feat(filters): delete read-time hide seam; reads return raw history"
```

---

### Task 4: Export test — blacklist no longer omits stored rows

**Files:**
- Test: `tests/test_export.lua:116-126`

**Interfaces:**
- Consumes: `NS.Database:Stats`, `NS.Export:InsightsCSV` (both unchanged; they now see unfiltered history).

- [ ] **Step 1: Rewrite the failing test**

Replace `tests/test_export.lua:116-126` (the test *"Export: InsightsCSV omits blacklisted items (via Stats/ActiveHistory)"*) with:
```lua
test("Export: InsightsCSV includes all stored rows (blacklist is point-in-time)", function()
  NS.db.global.blacklist = {}
  NS.db.global.history = {
    { ts = 1, char = "A-Realm", itemID = 1, itemName = "Kept",  quality = 3, source = "KILL", quantity = 1 },
    { ts = 2, char = "A-Realm", itemID = 2, itemName = "AlsoKept", quality = 3, source = "KILL", quantity = 1 },
  }
  NS.db.global.blacklist = { [2] = true }   -- blacklisting does not hide already-stored rows
  local csv = NS.Export:InsightsCSV(NS.Database:Stats({}))
  assertTrue(csv:find("Summary,Records,2,", 1, true) ~= nil, "both records counted")
  NS.db.global.blacklist = {}
end)
```

- [ ] **Step 2: Run the suite to verify it fails, then passes**

Run: `lua tests/run.lua`
Expected: with Task 3 already merged, this test should **PASS immediately** (Stats now sees both rows). If Task 4 is executed on a tree that still has the old hide, it FAILs first. Either way, end state is PASS. Confirm `luacheck .` → 0.

- [ ] **Step 3: Commit**

```bash
git add tests/test_export.lua
git commit -m "test(export): InsightsCSV counts all stored rows under point-in-time filters"
```

---

### Task 5: UI copy + docs — reword "hidden/restored" to "future loots only"

**Files:**
- Modify: `settings/Panel.lua:386-390` (section comment), `settings/Panel.lua:506-508` (blacklist description string)
- Modify: `modules/BrowserTable.lua:963-971` (right-click "Blacklist item" comment)
- Modify: `docs/ARCHITECTURE.md`, `docs/attribution.md` (prose mentions of soft-add/soft-delete / `viaWhitelist` / issue-#14 hide semantics)

**Interfaces:** none (copy + docs only). No behavior change.

- [ ] **Step 1: Update the Panel sub-page comment**

In `settings/Panel.lua`, replace the comment at 386-390 with:
```lua
-- ── Filters sub-page: blacklist / whitelist item-id management ────────────────────
-- A single sub-page with two sections. Each: a short description, an "add" row (item id or a
-- shift-clicked link) and a live list of current ids with a Remove button per row. The lists are
-- core app logic and act point-in-time: blacklisted ids are dropped at loot time and whitelisted
-- ids are always recorded — neither list ever hides or restores an already-stored row.
```

- [ ] **Step 2: Update the blacklist description string**

In `settings/Panel.lua`, replace the blacklist `makeFilterSection` description (506-508) with:
```lua
  local blRefresh = makeFilterSection(ctx, "blacklist", "Blacklist",
    "Items here are never recorded when looted from now on. Existing rows are left untouched "
    .. "(this only affects future loots — delete old rows from the history table if you want them gone).")
```
Leave the whitelist description (509-511) as-is — it is already accurate ("always recorded … Adding an id to one list removes it from the other.").

- [ ] **Step 3: Update the right-click "Blacklist item" comment**

In `modules/BrowserTable.lua`, replace the comment at 963-965 with:
```lua
    -- Blacklist this item: stop recording future loots of this id. Point-in-time — the row you
    -- clicked (and other existing rows of the same id) stay in the history; use Delete to remove
    -- them. Manage the list in Settings ▸ Filters.
```
Leave the action body (966-971) unchanged — `AddBlacklist` still prevents future captures.

- [ ] **Step 4: Update docs prose**

Run: `grep -rn "viaWhitelist\|soft-add\|soft-delete\|soft add\|soft delete\|VisibleHistory\|issue #14\|hidden from the browser" docs/ARCHITECTURE.md docs/attribution.md`

For each hit, rewrite the surrounding sentence to describe the **point-in-time** model: blacklisted items are dropped at capture and never written; whitelisted below-gate items are written as plain rows; reads return raw history; there is no per-record hide flag and no `VisibleHistory` seam. Remove references to `viaWhitelist`, the whitelist-orphan index, and "already-recorded rows are hidden / restored." Keep the `db.global.{blacklist,whitelist}` carve-out description intact. Do **not** touch `docs/saved-variables.md`'s carve-out entry (still accurate).

- [ ] **Step 5: Verify lint (no code behavior to test)**

Run: `luacheck .`
Expected: 0 warnings/errors.
Run: `lua tests/run.lua`
Expected: PASS (unchanged — copy/docs only).

- [ ] **Step 6: Commit**

```bash
git add settings/Panel.lua modules/BrowserTable.lua docs/ARCHITECTURE.md docs/attribution.md
git commit -m "docs(filters): reword blacklist/whitelist copy to point-in-time semantics"
```

---

### Task 6: Regenerate test inventory + README badge; final verification

**Files:**
- Modify: `docs/test-cases.md` (regenerated), `README.md` (`tests` badge count)

**Interfaces:** none.

- [ ] **Step 1: Regenerate the test-case inventory**

Run: `lua tests/run.lua --list > docs/test-cases.md`
Then inspect: `git diff docs/test-cases.md` — confirm it reflects the removed `VisibleHistory` tests and the renamed collector/export/migration tests.

- [ ] **Step 2: Get the new pass count**

Run: `lua tests/run.lua`
Read the final summary line for the total test count (e.g. `NN passed`). Note the number `NN`.

- [ ] **Step 3: Update the README `tests` badge**

Open `README.md`, find the `tests` badge (a shields.io URL containing a number followed by `passing`, e.g. `tests-137%20passing`). Replace the old number with `NN` from Step 2. If the surrounding prose states a test count, update it to match.

Verify parity: `grep -n "passing" README.md` and confirm the number equals `NN`.

- [ ] **Step 4: Final full verification**

Run: `lua tests/run.lua` → PASS, note count == `NN`.
Run: `luacheck .` → 0 warnings/errors.
Run: `grep -rn "viaWhitelist\|VisibleHistory\|RebuildWhitelistIndex" --include=*.lua .` → no matches.

- [ ] **Step 5: Commit**

```bash
git add docs/test-cases.md README.md
git commit -m "docs(tests): regenerate test inventory and sync README badge"
```

---

## Self-review notes

- **Spec coverage:** capture flag removal (Task 2), read-seam deletion (Task 3), migration (Task 1), UI copy (Task 5), docs (Task 5), test rewrites (Tasks 2/3/4), inventory+badge (Task 6). All spec sections mapped.
- **Type/name consistency:** `ActiveHistory()` is the single surviving read entry after Task 3; every test and consumer references it (not `VisibleHistory`). `NS.State.viaWhitelistIDs`, `RebuildWhitelistIndex`, `whitelistOrphanExists`, and `VisibleHistory` are all removed together in Task 3, with a grep gate (Task 3 Step 5) catching stragglers.
- **Ordering:** the suite stays green after each task's final step. Task 2 runs before Task 3 while `VisibleHistory` still exists but is harmless (no row carries the flag). Task 3 removes it and updates all its callers/tests in one commit.
- **Accepted consequence:** the right-click "Blacklist item" no longer removes the clicked row; comment reworded (Task 5 Step 3), behavior intentional per the "future loots only" decision.
