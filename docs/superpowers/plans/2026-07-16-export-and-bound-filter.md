# Export button + Bound filter — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Replace the redundant player-scope toggle with an Export modal (CSV now, AI later), and add a Bound multi-select filter to the History browser.

**Architecture:** A new `modules/Export.lua` (`NS.Export`) owns the export modal, CSV serialization, a Wowhead-link builder, and a stub AI prompt, plus its own copy window. `core/Database.lua` gains a `bound` query clause; `modules/BrowserTable.lua` gains `OrderedFilteredRecords()`; `modules/Browser.lua` drops the player toggle, adds the Export button and the Bound dropdown, and wires `bound` through the saved-view lifecycle.

**Tech Stack:** Lua 5.1, Ace3, WoW 12.0.7 client API, headless `lua tests/run.lua` + `luacheck .`.

## Global Constraints

- Target client WoW 12.0.7 (Midnight); Retail-only; English-only; Ace3 throughout.
- Account-wide storage only; no per-character profiles.
- Compat firewall: any varying API in `core/Compat.lua` (none expected here).
- Every user-setting mutation goes through `Schema:Set` — N/A here (filters/views are runtime state, already carved out like window geometry).
- Never bump the version.
- When the test suite changes: regenerate `docs/test-cases.md` and bump the README `tests` badge in the same change.
- Run `lua tests/run.lua` and `luacheck .` before every commit.

---

### Task 1: Bound query clause in Database

**Files:**
- Modify: `core/Database.lua` (`QueryList`, ~81-136)
- Test: `tests/test_database.lua`

**Interfaces:**
- Produces: `filter.bound` — a set table `{ [token]=true }` where token ∈ `NONE|BOE|BOP|ACCOUNT|WARBAND`; `NONE` matches records with `r.bound == nil`. Non-table `filter.bound` is ignored.

- [ ] **Step 1: Write failing tests** in `tests/test_database.lua` (after the existing Query tests):

```lua
test("Database: QueryList bound=NONE matches unbound records", function()
  local recs = {
    { bound = nil, itemID = 1 }, { bound = "BOE", itemID = 2 }, { bound = "BOP", itemID = 3 },
  }
  local out = NS.Database:QueryList(recs, { bound = { NONE = true } })
  assertEqual(#out, 1)
  assertEqual(out[1].itemID, 1)
end)

test("Database: QueryList bound set unions tokens", function()
  local recs = {
    { bound = nil, itemID = 1 }, { bound = "BOE", itemID = 2 },
    { bound = "ACCOUNT", itemID = 3 }, { bound = "WARBAND", itemID = 4 },
  }
  local out = NS.Database:QueryList(recs, { bound = { BOE = true, WARBAND = true } })
  assertEqual(#out, 2)
end)

test("Database: QueryList ignores non-table bound filter", function()
  local recs = { { bound = "BOE", itemID = 2 }, { bound = nil, itemID = 1 } }
  local out = NS.Database:QueryList(recs, { bound = "BOE" })
  assertEqual(#out, 2)  -- scalar bound ignored, all returned
end)
```

- [ ] **Step 2: Run to verify fail:** `lua tests/run.lua` → the three new tests FAIL.

- [ ] **Step 3: Implement.** In `QueryList`, add near the other set locals:

```lua
  local boundSet = type(filter.bound) == "table" and filter.bound or nil
```

and in the per-record loop, after the `mapID` block and before the `from` check:

```lua
    if ok and boundSet and not boundSet[r.bound or "NONE"] then ok = false end
```

- [ ] **Step 4: Run:** `lua tests/run.lua` → all pass. `luacheck .` → clean.

- [ ] **Step 5: Commit** (task green).

---

### Task 2: `BrowserTable:OrderedFilteredRecords()`

**Files:**
- Modify: `modules/BrowserTable.lua` (near `BuildDisplayList`, ~525)
- Test: `tests/test_browsertable.lua`

**Interfaces:**
- Produces: `BrowserTable:OrderedFilteredRecords()` → array of record tables (the filtered set in current sort/group order, group headers dropped). Uses `self.filter`, `self.groupBy`, `self.sortKey`, `self.sortAsc`.

- [ ] **Step 1: Write failing test** in `tests/test_browsertable.lua`:

```lua
test("BrowserTable: OrderedFilteredRecords returns filtered rows in order, no headers", function()
  local BT = NS.BrowserTable
  local saved = { filter = BT.filter, groupBy = BT.groupBy }
  NS.db.global.history = {
    { ts = 300, itemID = 3, quality = 4, source = "KILL", char = "A" },
    { ts = 100, itemID = 1, quality = 2, source = "KILL", char = "A" },
    { ts = 200, itemID = 2, quality = 4, source = "KILL", char = "A" },
  }
  BT.groupBy, BT.sortKey, BT.sortAsc = "none", "date", true
  BT:SetFilter({ quality = { [4] = true } })
  local out = BT:OrderedFilteredRecords()
  assertEqual(#out, 2)                 -- only the two epics
  assertEqual(out[1].itemID, 2)        -- ts 200 before ts 300 ascending
  assertEqual(out[2].itemID, 3)
  BT.filter, BT.groupBy = saved.filter, saved.groupBy
end)
```

- [ ] **Step 2: Run to verify fail:** `lua tests/run.lua` → FAIL (method nil).

- [ ] **Step 3: Implement** in `modules/BrowserTable.lua` after `BuildDisplayList`:

```lua
-- The filtered records in current sort/group order (group headers dropped) — the "Current View"
-- dataset the Export modal serializes. Mirrors what the table shows on screen.
function BrowserTable:OrderedFilteredRecords()
  local out = {}
  for _, entry in ipairs(self:BuildDisplayList()) do
    if entry.kind == "row" then out[#out + 1] = entry.record end
  end
  return out
end
```

- [ ] **Step 4: Run:** `lua tests/run.lua` → pass. `luacheck .` → clean.

- [ ] **Step 5: Commit** (task green).

---

### Task 3: Export module — serialization (CSV, Wowhead link, labels) + tests

**Files:**
- Create: `modules/Export.lua`
- Modify: `LootHistory.toc` (add `modules\Export.lua` after `BrowserTable.lua`)
- Modify: `tests/run.lua` (add `Export.lua` to `loadAll`; add `test_export.lua` to `SUITE_FILES`)
- Create: `tests/test_export.lua`

**Interfaces:**
- Produces:
  - `NS.Export:BoundLabel(token)` → friendly label string (`Not Bound` for `nil`/`"NONE"`).
  - `NS.Export:WowheadLink(record)` → URL string, or `""` when nothing usable.
  - `NS.Export:CSV(records)` → full CSV string (header + rows, `\r\n` terminated).
- Consumes: `NS.Database:Export` field order; `NS.Util.FormatDate(ts)`.

- [ ] **Step 1: Create `modules/Export.lua`** (serialization half; UI added in Task 4):

```lua
local addonName, NS = ...
NS.Export = NS.Export or {}
local E = NS.Export

-- Friendly bind-state labels, matching the Bound column's tooltip legend. nil/"NONE" = Not Bound.
local BOUND_LABEL = {
  NONE = "Not Bound", BOE = "Bind on Equip", BOP = "Bind on Pickup",
  ACCOUNT = "Account Bound", WARBAND = "Warbound",
}
function E:BoundLabel(token) return BOUND_LABEL[token or "NONE"] or tostring(token) end

-- CSV columns: the 19 export-contract fields (Database:Export order) + two derived columns.
local FIELDS = {
  "ts", "char", "classFile", "itemID", "itemLink", "itemName", "quality", "itemLevel", "bound",
  "sellPrice", "itemType", "itemSubType", "quantity", "source", "sourceDetail", "zone", "mapID",
  "subzone", "confidence",
}
local HEADER = {}
for i, f in ipairs(FIELDS) do HEADER[i] = f end
HEADER[#HEADER + 1] = "date"
HEADER[#HEADER + 1] = "wowheadLink"

-- Build a Wowhead item URL from a record's itemLink, carrying bonus IDs (the modifiers Wowhead
-- needs to reconstruct the exact item). Falls back to a bare item=<id>, or "" when nothing usable.
function E:WowheadLink(record)
  record = record or {}
  local itemStr = record.itemLink and record.itemLink:match("|?H?item:([%-%d:]+)")
  local id, bonuses
  if itemStr then
    local parts = {}
    for n in itemStr:gmatch("([%-%d]*):?") do parts[#parts + 1] = n end
    id = tonumber(parts[1])
    -- Field 13 = numBonusIDs; fields 14..13+n = bonus IDs (1-based over the item: payload).
    local numBonus = tonumber(parts[13]) or 0
    if numBonus > 0 then
      local b = {}
      for i = 14, 13 + numBonus do if parts[i] and parts[i] ~= "" then b[#b + 1] = parts[i] end end
      if #b > 0 then bonuses = table.concat(b, ":") end
    end
  end
  id = id or tonumber(record.itemID)
  if not id then return "" end
  local url = "https://www.wowhead.com/item=" .. id
  if bonuses then url = url .. "?bonus=" .. bonuses end
  return url
end

-- RFC-4180 field quoting: wrap on comma/quote/CR/LF; double embedded quotes.
local function csvField(v)
  if v == nil then return "" end
  local s = tostring(v)
  if s:find('[,"\r\n]') then s = '"' .. s:gsub('"', '""') .. '"' end
  return s
end

-- Serialize records to a CSV string (header + one row each). ts stays epoch; a derived DD-MMM-YYYY
-- `date` column and a `wowheadLink` column are appended; `bound` is emitted as its friendly label.
function E:CSV(records)
  local lines = { table.concat(HEADER, ",") }
  for _, r in ipairs(records or {}) do
    local cells = {}
    for i, f in ipairs(FIELDS) do
      local v = r[f]
      if f == "bound" then v = self:BoundLabel(r.bound) end
      cells[i] = csvField(v)
    end
    cells[#cells + 1] = csvField(NS.Util.FormatDate(r.ts))
    cells[#cells + 1] = csvField(self:WowheadLink(r))
    lines[#lines + 1] = table.concat(cells, ",")
  end
  return table.concat(lines, "\r\n") .. "\r\n"
end
```

- [ ] **Step 2: Register the module.** In `LootHistory.toc`, add after the `modules\BrowserTable.lua` line:

```
modules\Export.lua
```

In `tests/run.lua`, add `"modules/Export.lua",` to the `loadAll` list (after `"modules/BrowserTable.lua",`) and `"test_export.lua"` to `SUITE_FILES` (after `"test_browsertable.lua",`).

- [ ] **Step 3: Create `tests/test_export.lua`:**

```lua
local T = _G.LH_TEST
local NS = T.NS
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

test("Export: BoundLabel maps tokens and nil", function()
  assertEqual(NS.Export:BoundLabel(nil), "Not Bound")
  assertEqual(NS.Export:BoundLabel("NONE"), "Not Bound")
  assertEqual(NS.Export:BoundLabel("BOE"), "Bind on Equip")
  assertEqual(NS.Export:BoundLabel("WARBAND"), "Warbound")
end)

test("Export: WowheadLink with bonus IDs", function()
  local link = "|cffa335ee|Hitem:210501:0:0:0:0:0:0:0:0:0:0:0:0:3:6652:1498:11144:::|h[X]|h|r"
  assertEqual(NS.Export:WowheadLink({ itemLink = link }),
    "https://www.wowhead.com/item=210501?bonus=6652:1498:11144")
end)

test("Export: WowheadLink without bonuses is bare", function()
  local link = "|cff9d9d9d|Hitem:6948:0:0:0:0:0:0:0:0:0:0:0:0:0:::|h[Hearthstone]|h|r"
  assertEqual(NS.Export:WowheadLink({ itemLink = link }), "https://www.wowhead.com/item=6948")
end)

test("Export: WowheadLink falls back to itemID, then empty", function()
  assertEqual(NS.Export:WowheadLink({ itemID = 12345 }), "https://www.wowhead.com/item=12345")
  assertEqual(NS.Export:WowheadLink({}), "")
end)

test("Export: CSV header has all fields plus date + wowheadLink", function()
  local csv = NS.Export:CSV({})
  local header = csv:match("^(.-)\r\n")
  assertTrue(header:find("^ts,char,"), "starts with ts,char")
  assertTrue(header:find(",subzone,confidence,date,wowheadLink$") ~= nil, "ends with derived cols")
end)

test("Export: CSV row emits friendly bound + quotes commas", function()
  local rec = { ts = 1000, itemName = "Sword, Big", bound = "BOP", itemID = 7 }
  local csv = NS.Export:CSV({ rec })
  assertTrue(csv:find('"Sword, Big"', 1, true) ~= nil, "quotes the comma field")
  assertTrue(csv:find("Bind on Pickup", 1, true) ~= nil, "friendly bound label")
end)

test("Export: CSV date column is FormatDate(ts)", function()
  local rec = { ts = 1000, itemID = 1 }
  local csv = NS.Export:CSV({ rec })
  assertTrue(csv:find(NS.Util.FormatDate(1000), 1, true) ~= nil, "date column present")
end)
```

- [ ] **Step 4: Run:** `lua tests/run.lua` → all pass. `luacheck .` → clean.

- [ ] **Step 5: Commit** (task green).

---

### Task 4: Export module — modal UI + copy window + AI stub

**Files:**
- Modify: `modules/Export.lua`

**Interfaces:**
- Produces: `NS.Export:Open(providers)` where `providers = { allData = fn, currentView = fn }`, each returning a record array. Builds the modal once, then shows it.
- Consumes: `NS.Browser:ApplySkin`, `NS.Browser:MakeCloseButton`; `NS.Constants.FONT_MONO`.

Note: no headless unit test (frame construction needs the client); verified via smoke test (`docs/smoke-tests.md`). Keep the file luacheck-clean.

- [ ] **Step 1: Append the UI half to `modules/Export.lua`.** A skinned modal with a Data Set dropdown, two buttons, and Export's own copy window. The Data Set dropdown and buttons are built with small local factories (Export does NOT import Browser's file-local `MakeDropdown`, keeping the copy window independent per design):

```lua
-- ── Export modal ────────────────────────────────────────────────────────────────
local WHITE = "Interface\\Buttons\\WHITE8X8"
local frame, copyFrame
local providers            -- { allData = fn, currentView = fn }, set by :Open
local dataset = "allData"  -- current Data Set selection

-- Export's OWN copy window (deliberately not shared with the debug copy window, so its layout can
-- change independently). Read-only multiline EditBox: Ctrl+C to copy, Esc to close.
local function EnsureCopyFrame()
  if copyFrame then return copyFrame end
  copyFrame = CreateFrame("Frame", "LootHistoryExportCopyWindow", UIParent, "BackdropTemplate")
  copyFrame:SetSize(640, 420)
  copyFrame:SetPoint("CENTER")
  copyFrame:SetFrameStrata("FULLSCREEN")
  copyFrame:EnableMouse(true)
  copyFrame:SetMovable(true)
  copyFrame:SetClampedToScreen(true)

  local tbar = CreateFrame("Frame", nil, copyFrame)
  tbar:SetPoint("TOPLEFT", 1, -1); tbar:SetPoint("TOPRIGHT", -1, -1); tbar:SetHeight(26)
  tbar:EnableMouse(true); tbar:RegisterForDrag("LeftButton")
  tbar:SetScript("OnDragStart", function() copyFrame:StartMoving() end)
  tbar:SetScript("OnDragStop", function() copyFrame:StopMovingOrSizing() end)
  local t = tbar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("CENTER"); t:SetText("Export \226\128\148 Ctrl+C, then Esc")

  if NS.Browser and NS.Browser.MakeCloseButton then
    NS.Browser:MakeCloseButton(tbar, function() copyFrame:Hide() end)
      :SetPoint("RIGHT", tbar, "RIGHT", -6, 0)
  end

  local scroll = CreateFrame("ScrollFrame", "LootHistoryExportCopyScroll", copyFrame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -30); scroll:SetPoint("BOTTOMRIGHT", -28, 10)
  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetFont(NS.Constants.FONT_MONO, 10, "")
  edit:SetAutoFocus(false)
  edit:SetWidth(590)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); copyFrame:Hide() end)
  scroll:SetScrollChild(edit)
  copyFrame.scroll, copyFrame.edit = scroll, edit

  if NS.Browser and NS.Browser.ApplySkin then NS.Browser:ApplySkin(copyFrame) end
  copyFrame:Hide()
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "LootHistoryExportCopyWindow") end
  return copyFrame
end

local function ShowCopy(text)
  local f = EnsureCopyFrame()
  f.edit:SetWidth(f.scroll:GetWidth() > 0 and f.scroll:GetWidth() or 590)
  f.edit:SetText(text)
  f.edit:SetCursorPosition(0)
  f:Show(); f.edit:SetFocus(); f.edit:HighlightText()
end

-- The records for the current Data Set selection (empty array if the provider is missing).
local function selectedRecords()
  local fn = providers and providers[dataset]
  return (fn and fn()) or {}
end

-- Small flat-skin button matching the Browser bar buttons; `enabled=false` greys it and disables click.
local function makeButton(parent, text, width, onClick, enabled)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(width, 24)
  b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                  insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  b:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
  b:SetBackdropBorderColor(0.24, 0.24, 0.27, 0.9)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("CENTER"); fs:SetText(text)
  if enabled == false then
    fs:SetTextColor(0.5, 0.5, 0.5)
    b:SetScript("OnEnter", function(self2)
      GameTooltip:SetOwner(self2, "ANCHOR_BOTTOM"); GameTooltip:AddLine("Coming soon", 0.9, 0.9, 0.9); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  else
    b:SetScript("OnEnter", function() fs:SetTextColor(1, 0.82, 0) end)
    b:SetScript("OnLeave", function() fs:SetTextColor(1, 1, 1) end)
    b:SetScript("OnClick", onClick)
  end
  return b
end

-- Two-option Data Set selector (All Data / Current View) — a simple flat button that cycles.
local DATASETS = { { "allData", "All Data" }, { "currentView", "Current View" } }
local function makeDatasetToggle(parent)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(160, 24)
  b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                  insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  b:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
  b:SetBackdropBorderColor(0.24, 0.24, 0.27, 0.9)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", 8, 0)
  local function paint()
    for _, d in ipairs(DATASETS) do if d[1] == dataset then fs:SetText("Data set: " .. d[2]) end end
  end
  b:SetScript("OnClick", function()
    dataset = (dataset == "allData") and "currentView" or "allData"
    paint()
  end)
  paint()
  return b
end

local function EnsureFrame()
  if frame then return frame end
  frame = CreateFrame("Frame", "LootHistoryExportWindow", UIParent, "BackdropTemplate")
  frame:SetSize(320, 150)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("FULLSCREEN")
  frame:EnableMouse(true); frame:SetMovable(true); frame:SetClampedToScreen(true)

  local tbar = CreateFrame("Frame", nil, frame)
  tbar:SetPoint("TOPLEFT", 1, -1); tbar:SetPoint("TOPRIGHT", -1, -1); tbar:SetHeight(26)
  tbar:EnableMouse(true); tbar:RegisterForDrag("LeftButton")
  tbar:SetScript("OnDragStart", function() frame:StartMoving() end)
  tbar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
  local t = tbar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("CENTER"); t:SetText("Export")
  if NS.Browser and NS.Browser.MakeCloseButton then
    NS.Browser:MakeCloseButton(tbar, function() frame:Hide() end)
      :SetPoint("RIGHT", tbar, "RIGHT", -6, 0)
  end

  local toggle = makeDatasetToggle(frame)
  toggle:SetPoint("TOP", 0, -36)

  local csvBtn = makeButton(frame, "Export to CSV", 140, function()
    ShowCopy(E:CSV(selectedRecords()))
  end, true)
  csvBtn:SetPoint("TOPLEFT", 16, -72)

  local aiBtn = makeButton(frame, "Export to AI", 140, nil, false)
  aiBtn:SetPoint("TOPRIGHT", -16, -72)

  if NS.Browser and NS.Browser.ApplySkin then NS.Browser:ApplySkin(frame) end
  frame:Hide()
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "LootHistoryExportWindow") end
  return frame
end

-- Build (once) and show the export modal, wiring the dataset providers.
function E:Open(p)
  providers = p or {}
  EnsureFrame():Show()
end

-- Placeholder for the AI-report export (built later): returns a prompt string bundling `records`.
function E:AIPrompt(records)  -- luacheck: ignore
  return ""
end
```

- [ ] **Step 2: Run:** `lua tests/run.lua` → still all pass (module loads headlessly; UI is lazy). `luacheck .` → clean (add `-- luacheck: ignore` on unused params like `records`/`addonName` if flagged).

- [ ] **Step 3: Commit** (task green).

---

### Task 5: Browser — remove player toggle, add Export button + Bound filter

**Files:**
- Modify: `modules/Browser.lua`

**Interfaces:**
- Consumes: `NS.Export:Open`, `NS.BrowserTable:OrderedFilteredRecords`.

- [ ] **Step 1: Remove the player toggle.**
  - Delete the `PLAYER_OPTIONS` table (~391-394).
  - Delete the `dd.player` block in `BuildHistory` (~804-812).
  - In `SetCharSet`, delete the whole `if dd.player then ... end` block (~596-610); keep `if dd.char then dd.char:SetSelected(filter or {}) end` and the trailing `ApplyFilter()`.

- [ ] **Step 2: Add the Bound option set** near the other static option tables (after `DATE_OPTIONS`):

```lua
local BOUND_OPTIONS = {
  { value = "all", label = "Bound: All" },
  { value = "NONE", label = "Not Bound" },
  { value = "BOE", label = "Bind on Equip" },
  { value = "BOP", label = "Bind on Pickup" },
  { value = "ACCOUNT", label = "Account Bound" },
  { value = "WARBAND", label = "Warbound" },
}
```

- [ ] **Step 3: Wire `bound` into the view lifecycle.**
  - In `STOCK_VIEW`, add `bound = "all",` (a scalar "all"; `asSet` normalizes it to empty).
  - In `CaptureView`, add: `bound = setToFilter(dd and dd.bound._selected) or {},`
  - In `ApplyView`, in the `if dd then` block add `dd.bound:SetSelected(asSet(view.bound))`, and after the other `self.activeFilter.*` assignments add `self.activeFilter.bound = setToFilter(asSet(view.bound))`.

- [ ] **Step 4: Build the Bound dropdown** in `BuildHistory`, inserted between `dd.date` and `dd.quality`. Re-anchor Quality to sit after Bound:

```lua
  dd.bound = MakeDropdown(bar, 96)
  dd.bound:SetPoint("LEFT", dd.date, "RIGHT", 6, 0)
  dd.bound:SetMulti(true)
  dd.bound:SetOptions(BOUND_OPTIONS)
  dd.bound.onMultiSelect = function(set)
    B.activeFilter.bound = setToFilter(set)
    ApplyFilter()
  end
```

  Change the `dd.quality` anchor from `dd.date` to `dd.bound`:

```lua
  dd.quality:SetPoint("LEFT", dd.bound, "RIGHT", 6, 0)
```

- [ ] **Step 5: Add the Export button** in `BuildHistory`, replacing the removed player dropdown's slot (row 2, right):

```lua
  local exportBtn = makeBarButton(bar, "Export", 164, function()
    NS.Export:Open({
      allData     = function() return NS.Database:Export({}) end,
      currentView = function()
        return (NS.BrowserTable and NS.BrowserTable.OrderedFilteredRecords
          and NS.BrowserTable:OrderedFilteredRecords()) or {}
      end,
    })
  end, "Export your loot history to CSV or an AI report.")
  exportBtn:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, ROW2)
```

- [ ] **Step 6: Run:** `lua tests/run.lua` → pass. `luacheck .` → clean. Grep to confirm no dangling `dd.player` / `PLAYER_OPTIONS` references:

```bash
grep -n 'dd.player\|PLAYER_OPTIONS' modules/Browser.lua   # expect no output
```

- [ ] **Step 7: Commit** (task green).

---

### Task 6: Docs, test inventory, README badge

**Files:**
- Modify: `docs/browser.md`, `docs/ARCHITECTURE.md`
- Regenerate: `docs/test-cases.md`
- Modify: `README.md` (tests badge)

- [ ] **Step 1: Update `docs/browser.md`** — document the Export button + modal (CSV, AI placeholder, Data Set All/Current View) and the Bound filter; remove the player-toggle description. Note the new row-2 order Date · Bound · Quality · Type · Source · Zone · Character.

- [ ] **Step 2: Update `docs/ARCHITECTURE.md`** — add `Export` to the module map (owns export modal, CSV/Wowhead serialization, AI stub; called directly by Browser, no bus message).

- [ ] **Step 3: Regenerate the test inventory:**

```bash
lua tests/run.lua --list > docs/test-cases.md
```

- [ ] **Step 4: Bump the README `tests` badge** to the new total (read the `Total` line from `docs/test-cases.md`; update the `tests-<N>` number in `README.md`).

- [ ] **Step 5: Verify green:** `lua tests/run.lua` → all pass; `luacheck .` → clean.

- [ ] **Step 6: Commit** (task green).

---

## Self-Review

- **Spec coverage:** player toggle removal + Export button (T5); Export modal/CSV/Wowhead/AI stub/copy window (T3, T4); Bound filter UI + view wiring (T5); Bound query clause (T1); Current View ordering (T2); date column + friendly bound label (T3); tests (T1-T3); docs + badge + TOC (T3, T6). All covered.
- **Placeholder scan:** none — every code step is concrete.
- **Type consistency:** `providers.{allData,currentView}` used identically in T4/T5; `filter.bound` set form consistent T1/T5; `OrderedFilteredRecords` name consistent T2/T5; `E:CSV`/`E:WowheadLink`/`E:BoundLabel` consistent T3/T4/tests.
