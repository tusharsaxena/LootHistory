# Better Debug Messages — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the debug console full coverage of the addon's main functional flows, log every settings change once, and coalesce per-item/per-slot spam into one summary line per pass — then codify coverage + anti-spam + settings-logging as MUST rules in the Ka0s WoW Addon Standard.

**Architecture:** The line format, the `NS.Debug(tag, fmt, …)` sink, the zero-alloc gate, secret-safe stringification, and the on/off flag already exist and stay untouched. This work only (a) adds gated one-line traces at new flow sites, (b) collapses existing per-slot spam into one summary, (c) removes one redundant echo, and (d) edits the standard in the sibling `WowAddonStandards` repo. Where a summary has non-trivial string logic, it is extracted into a **pure formatter** so it can be unit-tested headlessly; the emission (gated `NS.Debug` call) sits at the frame/event site.

**Tech Stack:** Lua 5.1, Ace3, headless test harness (`lua tests/run.lua`), `luacheck`.

## Global Constraints

- **Verbosity is a flat on/off flag** (`NS.State.debug`). No log levels/tiers.
- **Every debug line goes through `NS.Debug(tag, fmt, …)`** — never `print()`, never a bespoke format. The format `<HH:MM:SS> | [<Tag>] <content>` is produced by `DebugLog.FormatColored`/`FormatPlain` and MUST NOT be reproduced by hand.
- **Zero-alloc when off:** the `if not (NS.State and NS.State.debug) then return end` (or `if NS.State.debug and NS.Debug then`) gate MUST be the first thing at every call site; no `string.format`, concat, or table build before it.
- **Secret-safe:** `NS.Debug` routes every `...` arg through `NS.SafeToString`; call sites pass values as `%s`, never `%d`/`%f`.
- **Account-wide storage** (`NS.db.global`); never per-character.
- **Session-only debug flag** — never persisted.
- **No auto-commit (CLAUDE.md hard rule).** Do NOT `git add`/`commit`/`push` yourself. Each task ends green (tests + lint); the **user** commits at the checkpoint (via `/wow-addon:commit` or manually). "Commit" steps below are the user's gate, not yours.
- **Green gate before every checkpoint:** `lua tests/run.lua` exits 0 AND `luacheck .` reports 0 errors.
- **Two repos:** Tasks 1–5, 7 touch `LootHistory`. Task 6 touches `WowAddonStandards` (`../WowAddonStandards`).

**Tag inventory after this plan:** kept — `Loot`, `Drop`, `Attr`, `Open`, `Mail`, `Cast`, `Set`, `Debug`; added — `Init`, `Migrate`, `Prune`, `Data`, `UI`, `Table`, `Insights`; removed — `Cfg`. `Open` = the game loot window (attribution); `UI` = the addon's own browser window.

**Test helper (used throughout):** assert the last plain-text line in the buffer contains a substring:

```lua
local function lastLine() return NS.DebugLog.buffer[#NS.DebugLog.buffer] end
local function bufferHas(sub)
  for _, l in ipairs(NS.DebugLog.buffer) do if l:find(sub, 1, true) then return true end end
  return false
end
```

Enable capture with `NS.State.debug = true`; assert zero-alloc with `NS.State.debug = false` then check `#NS.DebugLog.buffer` is unchanged.

---

### Task 1: Database mutations return counts and emit `[Prune]` / `[Data]`

**Files:**
- Modify: `core/Database.lua` — `Database:PruneOld` (lines ~348-359), `Database:Purge` (309-312), `Database:DeleteAt` (283-289)
- Test: `tests/test_database.lua`

**Interfaces:**
- Produces:
  - `Database:PruneOld()` → returns `removed` (number). Emits `[Prune] retention <days>d: removed <n> rows` when it runs (days > 0).
  - `Database:Purge()` → returns `removed` (number). Emits `[Data] purge-all removed <n> rows`.
  - `Database:DeleteAt(index)` → returns `boolean` (unchanged). Emits `[Data] deleted row @<ts>` on success.
- Consumes: `NS.Debug`, `NS.State.debug`, `NS.db.global`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_database.lua`:

```lua
test("Database: PruneOld returns removed count and logs [Prune]", function()
  seed()                                   -- existing seed() helper in this file
  NS.db.global.settings.retentionDays = 30
  NS.State.debug = true
  local before = #NS.DebugLog.buffer
  local removed = NS.Database:PruneOld()
  assertTrue(type(removed) == "number", "PruneOld returns a number")
  assertTrue(#NS.DebugLog.buffer > before, "a [Prune] line was logged")
  assertTrue(NS.DebugLog.buffer[#NS.DebugLog.buffer]:find("[Prune]", 1, true) ~= nil,
    "last line is tagged [Prune]")
  NS.State.debug = false
end)

test("Database: PruneOld is zero-alloc and silent when debug is off", function()
  seed()
  NS.db.global.settings.retentionDays = 30
  NS.State.debug = false
  local before = #NS.DebugLog.buffer
  NS.Database:PruneOld()
  assertEqual(#NS.DebugLog.buffer, before, "no line logged when debug off")
end)

test("Database: Purge returns removed count and logs [Data]", function()
  seed()
  NS.State.debug = true
  local n = NS.Database:Purge()
  assertTrue(type(n) == "number" and n > 0, "Purge returns the removed count")
  assertTrue(NS.DebugLog.buffer[#NS.DebugLog.buffer]:find("[Data]", 1, true) ~= nil,
    "last line is tagged [Data]")
  NS.State.debug = false
end)

test("Database: DeleteAt logs [Data] with the deleted row's ts", function()
  seed()
  NS.State.debug = true
  local ts = NS.db.global.history[1].ts
  assertTrue(NS.Database:DeleteAt(1))
  assertTrue(NS.DebugLog.buffer[#NS.DebugLog.buffer]:find("[Data]", 1, true) ~= nil,
    "last line is tagged [Data]")
  assertTrue(NS.DebugLog.buffer[#NS.DebugLog.buffer]:find(tostring(ts), 1, true) ~= nil,
    "the deleted row's ts appears in the line")
  NS.State.debug = false
end)
```

> If `seed()` is named differently in this file, use the existing seeding helper (the file already has deterministic-seed prune/delete tests around lines 173-228).

- [ ] **Step 2: Run tests to verify they fail**

Run: `lua tests/run.lua`
Expected: FAIL — `PruneOld`/`Purge` return `nil`; no `[Prune]`/`[Data]` lines.

- [ ] **Step 3: Implement the changes**

`Database:PruneOld` — count and return removed, emit gated:

```lua
function Database:PruneOld()
  local days = NS.db.global.settings.retentionDays
  if not days or days == 0 then return 0 end
  local cutoff = time() - days * 86400
  local history = NS.db.global.history
  local kept = {}
  for _, r in ipairs(history) do
    if (r.ts or 0) >= cutoff then kept[#kept + 1] = r end
  end
  local removed = #history - #kept
  NS.db.global.history = kept
  fireHistoryChanged()
  if NS.State.debug and NS.Debug then
    NS.Debug("Prune", "retention %sd: removed %s rows", tostring(days), tostring(removed))
  end
  return removed
end
```

`Database:Purge`:

```lua
function Database:Purge()
  local removed = #NS.db.global.history
  NS.db.global.history = {}
  fireHistoryChanged()
  if NS.State.debug and NS.Debug then
    NS.Debug("Data", "purge-all removed %s rows", tostring(removed))
  end
  return removed
end
```

`Database:DeleteAt` — read the ts before removal:

```lua
function Database:DeleteAt(index)
  local history = NS.db.global.history
  if type(index) ~= "number" or index < 1 or index > #history then return false end
  local ts = history[index] and history[index].ts
  table.remove(history, index)
  fireHistoryChanged()
  if NS.State.debug and NS.Debug then
    NS.Debug("Data", "deleted row @%s", tostring(ts))
  end
  return true
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `lua tests/run.lua`
Expected: PASS (all, including the pre-existing `PruneOld`/`Purge`/`DeleteAt` tests — the new return values are additive; the existing prune test at ~203 asserts kept rows, unaffected).

- [ ] **Step 5: Lint**

Run: `luacheck core/Database.lua tests/test_database.lua`
Expected: 0 errors.

- [ ] **Step 6: Checkpoint — hand to user for commit** (do NOT commit yourself). Suggested message: `feat(debug): Database mutations return counts and emit [Prune]/[Data]`.

---

### Task 2: Coalesce `LOOT_OPENED` per-slot spam into one summary

**Files:**
- Modify: `modules/Attribution.lua` — `Attribution:OnLootOpened` (lines ~131-153)
- Test: `tests/test_attribution.lua`

**Interfaces:**
- Consumes: `GetNumLootItems`, `GetLootSourceInfo` (mockable), `self:ResolveLootSource`, `self:Stamp`.
- Produces: exactly **one** `[Open]` line per `OnLootOpened` call. On resolve: `LOOT_OPENED <n> slots -> <source> (<detail>)` (the `(<detail>)` suffix omitted when detail is nil). Deconstruct-kept and no-GUID paths keep their single existing summary lines.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_attribution.lua`:

```lua
test("OnLootOpened logs ONE coalesced summary, not one line per slot", function()
  local oNum, oSrc = mocks.GetNumLootItems, mocks.GetLootSourceInfo
  mocks.GetNumLootItems = function() return 5 end
  mocks.GetLootSourceInfo = function() return "Creature-0-0-0-0-31146-000000AAAA" end
  NS.State.debug = true
  local before = #NS.DebugLog.buffer
  NS.Attribution:OnLootOpened()
  local added = 0
  for i = before + 1, #NS.DebugLog.buffer do
    if NS.DebugLog.buffer[i]:find("[Open]", 1, true) then added = added + 1 end
  end
  assertEqual(added, 1, "exactly one [Open] line for a 5-slot window")
  assertTrue(NS.DebugLog.buffer[#NS.DebugLog.buffer]:find("5 slots ->", 1, true) ~= nil,
    "the summary reports the slot count")
  NS.State.debug = false
  mocks.GetNumLootItems, mocks.GetLootSourceInfo = oNum, oSrc
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/run.lua`
Expected: FAIL — current code logs per-slot; for 5 slots it would log 1 line only because it `return`s after the first slot with a GUID. **Read carefully:** the current loop `return`s at the first slot that resolves, so it already emits ≤1 line — but that line is `slot=%s guid=%s -> %s`, not a slot-count summary. The test fails on the missing `"5 slots ->"` substring. Confirm the failure is the substring, then proceed.

- [ ] **Step 3: Implement the summary**

Replace the loop body in `OnLootOpened` (keep the deconstruct-kept guard above it and the no-GUID summary below it):

```lua
  local n = (GetNumLootItems and GetNumLootItems()) or 0
  for slot = 1, n do
    local guid = GetLootSourceInfo and GetLootSourceInfo(slot)
    if guid then
      local source, detail = self:ResolveLootSource(guid, State)
      if NS.State.debug and NS.Debug then
        NS.Debug("Open", "LOOT_OPENED %s slots -> %s%s", tostring(n), tostring(source),
          detail and (" (" .. tostring(detail) .. ")") or "")
      end
      self:Stamp(source, detail, Constants.Confidence.CERTAIN, "LOOT_OPENED")
      return
    end
  end
  if NS.State.debug and NS.Debug then NS.Debug("Open", "LOOT_OPENED (%s slots, no source GUID)", n) end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `lua tests/run.lua`
Expected: PASS. Confirm the existing deconstruct test (~152-158) still passes (it stubs a 1-slot Item GUID and asserts context is kept — unaffected by the log wording).

- [ ] **Step 5: Lint**

Run: `luacheck modules/Attribution.lua tests/test_attribution.lua`
Expected: 0 errors.

- [ ] **Step 6: Checkpoint — hand to user for commit.** Suggested: `refactor(debug): coalesce LOOT_OPENED per-slot spam into one summary`.

---

### Task 3: Remove the redundant `[Cfg]` settings echo

**Files:**
- Modify: `modules/Collector.lua` — the `SettingsChanged` handler (lines ~106-112)
- Test: `tests/test_collector.lua`

**Interfaces:**
- Consumes: `Ka0s_LootHistory_SettingsChanged` message; `self:RefreshUpvalues()`.
- Produces: no `[Cfg]` line. `Schema:Set`'s single `[Set] <path> = <value>` remains the sole settings-change trace.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_collector.lua`:

```lua
test("Collector SettingsChanged does not emit a redundant [Cfg] echo", function()
  NS.State.debug = true
  local before = #NS.DebugLog.buffer
  NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "test")
  for i = before + 1, #NS.DebugLog.buffer do
    assertTrue(NS.DebugLog.buffer[i]:find("[Cfg]", 1, true) == nil,
      "no [Cfg] line after a settings change")
  end
  NS.State.debug = false
end)
```

> This test requires `Collector:Enable()` to have run so the handler is registered. If the collector isn't enabled in the headless harness, register the handler in a `before`/setup the file already uses, or call `NS.Collector:Enable()` guarded by `pcall` at the top of the test. Check the top of `tests/test_collector.lua` for the existing enable pattern and match it.

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/run.lua`
Expected: FAIL — a `[Cfg]` line is currently emitted.

- [ ] **Step 3: Implement — drop the echo**

Replace the handler registration in `Collector:Enable`:

```lua
  self.__ev:RegisterMessage("Ka0s_LootHistory_SettingsChanged", function(_, reason)
    self:RefreshUpvalues()
  end)
```

(The `reason` param is retained for signature stability even though it's now unused; luacheck permits an unused callback arg named `reason` only if your `.luacheckrc` doesn't flag it — if luacheck complains, rename it to `_reason` or `...`.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `lua tests/run.lua`
Expected: PASS.

- [ ] **Step 5: Lint**

Run: `luacheck modules/Collector.lua tests/test_collector.lua`
Expected: 0 errors. If it flags the unused `reason`, change the signature to `function(_, _reason)`.

- [ ] **Step 6: Checkpoint — hand to user for commit.** Suggested: `refactor(debug): drop redundant [Cfg] echo; [Set] is the sole settings trace`.

---

### Task 4: Lifecycle traces — `[Init]` boot summary + `[Migrate]` seam

**Files:**
- Modify: `core/Database.lua` — add `NS.BootSummary`, `NS.MigrationSummary`; wire `[Migrate]` into `RunMigrations`
- Modify: `core/LootHistory.lua` — emit `[Init]` in `OnEnable`
- Test: `tests/test_database.lua`

**Interfaces:**
- Produces:
  - `NS.BootSummary()` → string `DB ready schemaVersion=<v> records=<n>` (pure; reads `NS.db.global`).
  - `NS.MigrationSummary(from, to, rows)` → string `v<from> -> v<to>, <rows> rows touched` (pure).
  - `[Init]` line emitted once in `addon:OnEnable`.
  - `[Migrate]` line emitted inside `RunMigrations`' upgrade branch (dormant until a real v→v+1 migration lands — the seam ships ready, matching the existing dormant-migration comment).

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_database.lua`:

```lua
test("NS.BootSummary reports schemaVersion and record count", function()
  seed()
  NS.db.global.schemaVersion = 1
  local s = NS.BootSummary()
  assertTrue(s:find("schemaVersion=1", 1, true) ~= nil, "reports schemaVersion")
  assertTrue(s:find("records=", 1, true) ~= nil, "reports record count")
end)

test("NS.MigrationSummary formats from/to/rows", function()
  assertEqual(NS.MigrationSummary(1, 2, 1423), "v1 -> v2, 1423 rows touched")
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `lua tests/run.lua`
Expected: FAIL — `BootSummary`/`MigrationSummary` are nil.

- [ ] **Step 3: Implement the pure formatters** in `core/Database.lua` (near `RunMigrations`):

```lua
-- Pure boot summary for the [Init] line. Reads current DB state; no side effects.
function NS.BootSummary()
  local g = NS.db and NS.db.global
  local v = g and g.schemaVersion or 0
  local n = (g and g.history and #g.history) or 0
  return ("DB ready schemaVersion=%s records=%s"):format(tostring(v), tostring(n))
end

-- Pure migration summary for the [Migrate] line.
function NS.MigrationSummary(from, to, rows)
  return ("v%s -> v%s, %s rows touched"):format(tostring(from), tostring(to), tostring(rows))
end
```

Wire `[Migrate]` into the (dormant) upgrade branch of `RunMigrations`:

```lua
function NS:RunMigrations()
  local g = NS.db and NS.db.global
  if not g then return end
  g.schemaVersion = g.schemaVersion or 1
  -- future: when a real upgrade lands, bump and log, e.g.:
  --   if g.schemaVersion < 2 then
  --     local n = migrateV1toV2(g)            -- returns rows touched
  --     g.schemaVersion = 2
  --     if NS.State.debug and NS.Debug then NS.Debug("Migrate", NS.MigrationSummary(1, 2, n)) end
  --   end
end
```

> The `[Migrate]` emission is intentionally inside the dormant branch — there is no v1→v2 migration yet, so it never fires today. The *formatter* is what this task tests and locks in; the seam ships ready, exactly as the existing migration-seam comment prescribes.

Emit `[Init]` in `core/LootHistory.lua` `addon:OnEnable` (after the modules enable):

```lua
function addon:OnEnable()
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnterWorld")
  if NS.Attribution and NS.Attribution.Enable then NS.Attribution:Enable() end
  if NS.Collector and NS.Collector.Enable then NS.Collector:Enable() end
  if NS.Browser and NS.Browser.Enable then NS.Browser:Enable() end
  if NS.State.debug and NS.Debug then NS.Debug("Init", "%s", NS.BootSummary()) end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `lua tests/run.lua`
Expected: PASS.

- [ ] **Step 5: Lint**

Run: `luacheck core/Database.lua core/LootHistory.lua tests/test_database.lua`
Expected: 0 errors.

- [ ] **Step 6: Checkpoint — hand to user for commit.** Suggested: `feat(debug): [Init] boot summary and [Migrate] seam`.

---

### Task 5: View flow — `[Table]`, `[Insights]`, `[UI]`

**Files:**
- Modify: `modules/BrowserTable.lua` — add `BrowserTable.RenderSummary`; emit `[Table]` in `Refresh` (lines ~808-812)
- Modify: `modules/Analytics.lua` — add `Analytics.SummaryLine`; emit `[Insights]` in `Refresh`
- Modify: `modules/Browser.lua` — emit `[UI]` in window show/hide and `SelectTab` (line ~124)
- Test: `tests/test_browsertable.lua`

**Interfaces:**
- Produces:
  - `BrowserTable.RenderSummary(matchCount, total, filterCount, groupBy, sortKey, sortAsc)` → string `rendered <m>/<t> rows (group=<g>, sort=<key> <asc|desc>, filters=<k>)` (pure).
  - `Analytics.SummaryLine(range, count)` → string `computed range=<range>, <count> records` (pure).
  - `[Table]` one line per `Refresh` pass; `[Insights]` one line per `Refresh`; `[UI]` one line per window show/hide/tab switch.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_browsertable.lua`:

```lua
test("BrowserTable.RenderSummary is a single coalesced line", function()
  local s = NS.BrowserTable.RenderSummary(84, 1423, 2, "zone", "date", false)
  assertTrue(s:find("84/1423 rows", 1, true) ~= nil, "reports matched/total")
  assertTrue(s:find("group=zone", 1, true) ~= nil, "reports group")
  assertTrue(s:find("sort=date desc", 1, true) ~= nil, "reports sort key + direction")
  assertTrue(s:find("filters=2", 1, true) ~= nil, "reports active filter count")
  assertTrue(s:find("\n") == nil, "one line only, no newline")
end)
```

Add to `tests/test_stats.lua` (or `test_browsertable.lua` if Analytics has no test file):

```lua
test("Analytics.SummaryLine formats range and count", function()
  assertEqual(NS.Analytics.SummaryLine("30d", 1423), "computed range=30d, 1423 records")
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `lua tests/run.lua`
Expected: FAIL — `RenderSummary`/`SummaryLine` are nil.

- [ ] **Step 3: Implement the pure formatters + gated emission**

`modules/BrowserTable.lua` — add the formatter and call it at the end of `Refresh`:

```lua
-- Pure one-line render summary for the [Table] trace. filterCount = number of active
-- filter keys; sortAsc drives the direction word. No frames, no side effects.
function BrowserTable.RenderSummary(matchCount, total, filterCount, groupBy, sortKey, sortAsc)
  return ("rendered %s/%s rows (group=%s, sort=%s %s, filters=%s)"):format(
    tostring(matchCount), tostring(total), tostring(groupBy or "none"),
    tostring(sortKey), sortAsc and "asc" or "desc", tostring(filterCount or 0))
end

function BrowserTable:Refresh()
  if not self.frame then return end
  self.displayList = self:BuildDisplayList()
  self:Bind()
  if NS.State.debug and NS.Debug then
    local total = #(NS.Database:ActiveHistory() or {})
    local fc = 0
    for _ in pairs(self.filter or {}) do fc = fc + 1 end
    NS.Debug("Table", "%s", BrowserTable.RenderSummary(
      self.matchCount or 0, total, fc, self.groupBy, self.sortKey, self.sortAsc))
  end
end
```

`modules/Analytics.lua` — add the formatter and emit at the end of `Analytics:Refresh` (find `function Analytics:Refresh()` near line ~322; add before its final `end`):

```lua
-- Pure one-line summary for the [Insights] trace.
function Analytics.SummaryLine(range, count)
  return ("computed range=%s, %s records"):format(tostring(range), tostring(count))
end
```

At the end of `Analytics:Refresh`, after the stats are computed (use the record count already available there — e.g. the length of the queried stats set or `stats.count`; use the variable the function already holds, do not re-query):

```lua
  if NS.State.debug and NS.Debug then
    NS.Debug("Insights", "%s", Analytics.SummaryLine(self.range, <recordCount>))
  end
```

> Replace `<recordCount>` with the count variable already present in `Refresh` (the `Database:Stats` result exposes a total; grep `Refresh` for the existing count/`#` before wiring — do not add a second `Database:Stats` pass, that would double the work on every recompute).

`modules/Browser.lua` — emit `[UI]` at the window show/hide and in `SelectTab`:

- In `SelectTab(name)` (line ~124), after the tab is switched:

```lua
  if NS.State.debug and NS.Debug then NS.Debug("UI", "tab -> %s", tostring(name)) end
```

- On the main window's `OnShow`/`OnHide` scripts (grep `Browser.lua` for where the main frame is shown/toggled — the LDB launcher / `:Toggle` seam), add gated lines:

```lua
  if NS.State.debug and NS.Debug then NS.Debug("UI", "window shown") end   -- OnShow
  if NS.State.debug and NS.Debug then NS.Debug("UI", "window hidden") end  -- OnHide
```

> The `[UI]` emissions live in frame scripts that the headless harness does not drive, so they are verified by lint + in-game smoke (Task 7), not a unit test. Only the pure formatters are unit-tested.

- [ ] **Step 4: Run tests to verify they pass**

Run: `lua tests/run.lua`
Expected: PASS.

- [ ] **Step 5: Lint**

Run: `luacheck modules/BrowserTable.lua modules/Analytics.lua modules/Browser.lua tests/test_browsertable.lua tests/test_stats.lua`
Expected: 0 errors.

- [ ] **Step 6: Checkpoint — hand to user for commit.** Suggested: `feat(debug): [Table]/[Insights]/[UI] view-flow traces`.

---

### Task 6: Codify the MUST rules in the Ka0s Standard

**Files:**
- Modify: `../WowAddonStandards/standards/standards/debug-logging.md` — add three subsections
- Modify: `../WowAddonStandards/standards/STANDARDS.md` — bump version + date

**Interfaces:** none (documentation).

- [ ] **Step 1: Add three normative subsections to `debug-logging.md`**

Insert after §4 (The sink), renumbering the later sections' `§N` references is **not** required (cross-refs use `filename-§N` and the existing sections are referenced by their headings, but check for any `debug-logging-§5`/`§6`/`§7` cross-refs elsewhere in the standard first — see Step 3). Add:

```markdown
### 5. Coverage — trace the main functional flows (MUST)

Debug **MUST** trace the addon's **main functional flows**, so a log read back after a repro
tells the story of what the addon did. At minimum:

- **Lifecycle** — load/enable (a one-line boot summary: schema version, record/row count),
  schema **migration** (only when one actually runs), and retention/**prune**.
- **The core capture / compute flow** — the addon's reason for existing (e.g. an item recorded,
  a cast resolved), including the **not-recorded** decisions that explain a missing entry.
- **All data mutations** — user-initiated purge/delete and any bulk rewrite of stored data.
- **View open / recompute** — the main window opening, tab switches, and each table/analytics
  **recompute** (as one summary line — see §6).
- **Every settings change** — see §7.

Each flow event is **one gated line**, tagged (§3). Coverage is judged by "could I reconstruct
what happened from the log?", not by line count.

### 6. Coalescing — one summary line per pass, never per item (MUST NOT)

A debug sink on a repeating path (a bag scan, a loot window's slots, a table re-render on every
filter keystroke, a per-frame tick) **MUST NOT** emit one line per item/slot/frame. It **MUST**
collapse to **one summary line per pass**, carrying the counts and the scanned/affected detail in
that single line — e.g. `Scanned 42 items, 3 new` with the id lists appended, or
`rendered 84/1423 rows (group=zone, sort=date desc, filters=2)`. The per-item trace is spam: it
buries the signal and, on a hot path, is a measurable cost even gated.

The string-building for the summary **MUST** stay behind the debug gate (the zero-alloc rule, §4):
build the id lists / summary only when debug is on. *(Reference pattern in the collection: an
auto-discovery pass that fired one "no match" line per bag item on every bag update was collapsed
to a single tagged summary line per pass, with the per-item zero-match trace dropped and the list
building moved behind the gate.)*

### 7. Settings changes — log once, at the single write seam (MUST)

Every settings mutation **MUST** be logged **once**, at the schema's single write seam
(schema-as-single-source; the `Set` path), as `[Set] <path> = <value>`. Downstream reactors
(modules handling the settings-changed message) **MUST NOT** re-echo the same change — a second
`[Cfg] …` line for a change already shown by `[Set]` is redundant spam. A reactor logs **only** a
material *effect* the reader cannot infer from the `[Set]` line (e.g. "capture disabled"), never a
restatement of the new value.
```

Renumber the existing §5 (Enabled-state), §6 (Copy/Clear), §7 (Fallback) to §8, §9, §10.

- [ ] **Step 2: Bump the standard version + date**

In `../WowAddonStandards/standards/STANDARDS.md`, the first heading currently reads
`# Ka0s WoW Addon Standard (v1.10.0, 2026-07-14)`. Bump to the next **minor** (new normative MUST
content is a feature-level change): `# Ka0s WoW Addon Standard (v1.11.0, 2026-07-15)`.

- [ ] **Step 3: Fix any dangling cross-references**

Run from the standards repo root:

```bash
cd ../WowAddonStandards && grep -rn "debug-logging-§[567]" standards/
```

For every hit, add 3 to the number (§5→§8, §6→§9, §7→§10) to match the renumbering. Expected: the
known reference to the enabled-state/session-only rule (was `debug-logging-§5`) becomes
`debug-logging-§8`; the anti-patterns and options-ui files are the likely locations. If there are
no hits, nothing to fix.

- [ ] **Step 4: Verify**

Run: `cd ../WowAddonStandards && grep -n "v1.11.0" standards/STANDARDS.md` — expect the bumped line.
Re-read `debug-logging.md` end to end: sections number 1–10 with no gaps or duplicates.

- [ ] **Step 5: Checkpoint — hand to user for commit** (this is the `WowAddonStandards` repo — a separate commit there). Suggested: `standards(debug-logging): MUST-DO coverage, coalescing, settings-logging (v1.11.0)`.

---

### Task 7: Docs sync + full verification

**Files:**
- Modify: `docs/ARCHITECTURE.md` and/or `docs/agent-context.md` — if either lists the debug tag set or debug behavior, update it to the new inventory (add `Init`/`Migrate`/`Prune`/`Data`/`UI`/`Table`/`Insights`, remove `Cfg`)
- Modify: `docs/smoke-tests.md` — add the debug smoke steps below

**Interfaces:** none.

- [ ] **Step 1: Grep the docs for stale debug references**

```bash
grep -rn "\[Cfg\]\|Cfg\b\|debug tag\|LOOT_OPENED slot" docs/
```

Update any list of tags to the new inventory; fix any doc that describes the old per-slot
`LOOT_OPENED` logging or the `[Cfg]` echo.

- [ ] **Step 2: Add the debug smoke checklist to `docs/smoke-tests.md`**

```markdown
### Debug console coverage (debug on: `/lh debug on`, open with `/lh debug`)
- Log in → one `[Init]` line (schemaVersion + record count).
- Loot a threshold item → one `[Loot]`; a sub-threshold item → one `[Drop]`.
- Open a corpse/chest with many slots → exactly one `[Open] LOOT_OPENED N slots -> …`, not N lines.
- Change a setting (panel or `/lh set …`) → exactly one `[Set] <path> = <value>`, no `[Cfg]`.
- `/lh purge` (confirm) → one `[Data] purge-all removed N rows`; delete a row → one `[Data] deleted row @…`.
- Open the browser → `[UI] window shown`; switch to Insights → `[UI] tab -> Insights` + one `[Insights] computed …`.
- Type in the table's search / change group/sort → one `[Table] rendered M/T rows (…)` per change, never per row.
```

- [ ] **Step 3: Full green gate**

Run: `lua tests/run.lua` — expect exit 0, all tests pass.
Run: `luacheck .` — expect 0 errors.

- [ ] **Step 4: In-game smoke** — follow the checklist added in Step 2 on a live client; confirm every bullet, especially the "one line, not N" coalescing bullets.

- [ ] **Step 5: Checkpoint — hand to user for commit.** Suggested: `docs: debug tag inventory + coverage smoke steps`.

---

## Self-Review

**Spec coverage:**
- "Standardize the format" — already MUST (`debug-logging §3`); Global Constraints reaffirm it, no code task needed. ✓
- Capture key flow events — Task 4 (Init/Migrate/Prune), Task 1 (Prune/Data), Task 5 (UI/Table/Insights). ✓
- Capture all settings changes — Task 3 (single `[Set]` seam, echo removed); reaffirmed in standard Task 6 §7. ✓
- Consolidate spam — Task 2 (LOOT_OPENED), Task 5 (Table/Insights one-per-pass). ✓
- Make it a MUST in the standard — Task 6 (§5/§6/§7 + version bump). ✓
- Flat on/off, no levels — Global Constraints + no level plumbing anywhere. ✓
- No auto-commit / two repos — Global Constraints + per-task user checkpoints; Task 6 is the standards repo. ✓

**Placeholder scan:** Two deliberate lookups remain and are explicitly bounded, not TBDs: (a) Task 5's `<recordCount>` — instructs grepping the existing `Analytics:Refresh` count variable rather than adding a second `Stats` pass; (b) Task 3's collector-enable setup — instructs matching the file's existing enable pattern. Both are "use what's already there" directions with the exact constraint stated, not missing content.

**Type consistency:** `RenderSummary`, `SummaryLine`, `BootSummary`, `MigrationSummary` are named identically at definition and call sites. `PruneOld`/`Purge` now return numbers (additive; existing `DeleteAt`→bool, `Delete`→number unchanged). Tag strings match the inventory table exactly.
