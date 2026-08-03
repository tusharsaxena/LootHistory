# Insights Loot/Currency sections + full currency export — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize the in-game Insights tab into Loot/Currency sections with improved currency charts, and propagate currency end-to-end through both data exports (Insights CSV + the full Export-to-AI report).

**Architecture:** Additive changes to `modules/Analytics.lua` (dividers, reorder, currency charts, legend, palette), one new stat in `core/Database.lua`, Insights-CSV + AI-CSV changes in `modules/Export.lua`, and full currency handling in the AI report assets (`docs/ai-export-guideline.md`, `docs/ai-export-template.html`, `tools/build_report.py`). No capture, message-bus, or AceDB-schema changes.

**Tech Stack:** Lua 5.1 (headless tests via `lua tests/run.lua`, lint via `luacheck .`), Python 3 stdlib (`tools/build_report.py`, tests via `python3 -m pytest tools/tests/` or `python3 -m unittest`), self-contained HTML/JS report engine.

## Global Constraints

- **Never bump the addon version** (TOC/NS.version/README) — not part of this work.
- **Account-wide storage only**; no schema/saved-variable changes here.
- **luacheck must stay 0 warnings / 0 errors** across all 21 files after every Lua task.
- **`lua tests/run.lua` must stay green** after every Lua task.
- **`build_report.py` must PASS** on both the shipped sample and a currency-bearing export after Phase 4.
- **Test inventory + badge stay in sync**: after the suite changes, regenerate `docs/test-cases.md` (`lua tests/run.lua --list > docs/test-cases.md`) and bump the README `tests` badge count in the same change (final task).
- **Source keys** (16): `KILL CONTAINER MPLUS ROLL BONUS_ROLL QUEST TRADE MAIL AH VENDOR CRAFT DISENCHANT MILLING PROSPECTING REFUND OTHER`.
- Commit after each task. Do NOT push. Work stays on branch `feature/insights-sections-currency-export`.

---

## Phase 1 — In-game Insights (Analytics + new stat)

### Task 1: `currencyBySource` stat

**Files:**
- Modify: `core/Database.lua:228-331` (`Database:Stats` — currency accumulation) and `:378-395` (return struct)
- Test: `tests/test_stats.lua`

**Interfaces:**
- Produces: `stats.currencyBySource` — a `{ [sourceKey]=totalQuantity }` map (sum of currency `quantity` per record `source`, across all currencies). Consumed by Analytics Task 4 and Export Task (Phase 2).

- [ ] **Step 1: Write the failing test** (append to `tests/test_stats.lua`)

```lua
test("Stats: currencyBySource sums currency quantity per source across currencies", function()
  NS.db.global.history = {
    { ts = T1, char = "A-Realm", currencyID = 10, itemName = "Badge",
      quantity = 30, source = "VENDOR" },
    { ts = T1, char = "A-Realm", currencyID = 10, itemName = "Badge",
      quantity = 20, source = "REFUND" },
    { ts = T2, char = "A-Realm", currencyID = 11, itemName = "Voidcore",
      quantity = 4, source = "VENDOR" },
  }
  local s = NS.Database:Stats({})
  assertEqual(s.currencyBySource.VENDOR, 34)   -- 30 badge + 4 voidcore
  assertEqual(s.currencyBySource.REFUND, 20)
  assertEqual(s.currencyBySource.KILL, nil)
end)
```
(`T1`/`T2` are the module-level timestamps already defined at the top of `tests/test_stats.lua`.)

- [ ] **Step 2: Run it, verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -i "currencyBySource\|failed"`
Expected: FAIL (`s.currencyBySource` is nil → indexing error / mismatch).

- [ ] **Step 3: Implement** — in `core/Database.lua`, add the accumulator local near line 228 and populate it in the `isCurrency` branch, then return it.

Add to the locals block (near line 228, beside `byCurrency`):
```lua
  local currencyBySource = {}
```
Inside `if isCurrency then` (after the `m[src] = ...` matrix line, ~line 315):
```lua
      currencyBySource[src] = (currencyBySource[src] or 0) + qty
```
Add to the returned table (beside `currencySourceMatrix`, ~line 385):
```lua
    currencyBySource = currencyBySource,
```

- [ ] **Step 4: Run tests + lint**

Run: `lua tests/run.lua 2>&1 | tail -1 && luacheck core/Database.lua 2>&1 | tail -1`
Expected: all pass; luacheck OK.

- [ ] **Step 5: Commit**

```bash
git add core/Database.lua tests/test_stats.lua
git commit -m "feat(insights): add currencyBySource stat (source -> total qty)"
```

---

### Task 2: Section dividers + layout reorder

> Analytics layout is frame-based with no headless harness (matching the existing module). Gate = `luacheck` 0/0 + the in-game smoke listed in Step 4.

**Files:**
- Modify: `modules/Analytics.lua` — add `sectionDivider` helper (near `sectionHeader`, ~line 337); create two dividers in `BuildCharts` (~line 359-386); position them + reorder in `LayoutCharts` (~line 576-857); hide them in `HideAllCharts` (~line 536).

**Interfaces:**
- Produces: `self.lootDivider`, `self.currencyDivider` (frames with `:Show()/:Hide()/:ClearAllPoints()/:SetPoint()` and a `.fs` FontString), mirroring the `sectionHeader` contract.

- [ ] **Step 1: Add the `sectionDivider` helper** (after `sectionHeader`, ~line 343)

```lua
-- Full-width section divider: centered gold title flanked by horizontal rule lines (the
-- "Slash Commands" separator look). Returns a frame; caller anchors its TOPLEFT on the y cursor.
local function sectionDivider(parent, text)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(18)
  local lineL = f:CreateTexture(nil, "ARTWORK")
  lineL:SetColorTexture(1, 0.82, 0, 0.35)
  lineL:SetHeight(1)
  local lineR = f:CreateTexture(nil, "ARTWORK")
  lineR:SetColorTexture(1, 0.82, 0, 0.35)
  lineR:SetHeight(1)
  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("CENTER", f, "CENTER", 0, 0)
  fs:SetTextColor(1, 0.82, 0)
  fs:SetText(text)
  f.fs = fs
  -- lines fill the space either side of the centered label (8px gap)
  lineL:SetPoint("LEFT", f, "LEFT", 0, 0)
  lineL:SetPoint("RIGHT", fs, "LEFT", -8, 0)
  lineR:SetPoint("LEFT", fs, "RIGHT", 8, 0)
  lineR:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  return f
end
```

- [ ] **Step 2: Create the dividers in `BuildCharts`** (after the `self.headers = {...}` block, ~line 384, beside `self.currencyPanel`)

```lua
  self.lootDivider = sectionDivider(content, "LOOT")
  self.currencyDivider = sectionDivider(content, "CURRENCY")
```

- [ ] **Step 3: Hide them in `HideAllCharts`** (add to the body, ~line 540)

```lua
  self.lootDivider:Hide(); self.currencyDivider:Hide()
```

- [ ] **Step 4: Position dividers + reorder ranked lists in `LayoutCharts`.**

(a) At the very top of the chart rendering (right after `local H, total = self.headers, ...`, ~line 592), render the LOOT divider first:
```lua
  self.lootDivider:ClearAllPoints()
  self.lootDivider:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y)
  self.lootDivider:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -pad, y)
  self.lootDivider:Show()
  y = y - 24
```

(b) **Move the ranked-lists block** (currently lines ~810-856, "Top items by value / count / Top zones") to render **before** the Currency block. Cut that whole block and paste it immediately after the Attribution-confidence chart (after `y = self:renderBarSection(P.conf, H.conf, rows, y, w, pad)`, ~line 742) and before the `-- ── Currency ──` comment. The block already returns/advances `y`; keep its internal `return y` removed — it must fall through to the currency code. **Change**: the final line of that moved block is `return y` (line 857) → replace with `-- (fall through to Currency)` since currency now renders after it.

(c) Just before the Currency block renders (at the `if ct.events and ct.events > 0 then`, ~line 746), render the CURRENCY divider inside the `if` (so it hides with the section):
```lua
    self.currencyDivider:ClearAllPoints()
    self.currencyDivider:SetPoint("TOPLEFT", self.content, "TOPLEFT", pad, y)
    self.currencyDivider:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -pad, y)
    self.currencyDivider:Show()
    y = y - 24
```
And in the matching `else` (no currency, ~line 806) add:
```lua
    self.currencyDivider:Hide()
```

(d) The Currency block currently `return y` is implicit at function end; ensure `LayoutCharts` ends with `return y` after the (now-final) currency code. The moved ranked-list block's old `return y` is gone (b), so the function's single `return y` is the last line of the currency block region — confirm one `return y` remains at the end of `LayoutCharts`.

- [ ] **Step 5: Lint + in-game smoke**

Run: `luacheck modules/Analytics.lua 2>&1 | tail -1`
Expected: OK.
In-game smoke (record in commit msg): `/lh show` → Insights. A **LOOT** divider appears below the stat cards; all loot charts + the Top items/zones panels sit under it; a **CURRENCY** divider appears below them; currency charts under it. With no currency, the CURRENCY divider is absent. No Lua errors.

- [ ] **Step 6: Commit**

```bash
git add modules/Analytics.lua
git commit -m "feat(insights): LOOT/CURRENCY section dividers; move ranked lists into Loot"
```

---

### Task 3: "Currency Collected" bar chart (replaces the list)

**Files:**
- Modify: `modules/Analytics.lua` — the Currency block (~line 755-761), the pool key list (~line 578-580), `BuildCharts` header table (~line 374), `HideAllCharts` (~line 540).

- [ ] **Step 1: Add a header + drop the list panel usage.** In `BuildCharts` `self.headers`, add:
```lua
    currencyCollected = sectionHeader(content, "Currency Collected"),
```
Keep `self.currencyPanel` allocation for now (removed if unused after Task; safe to leave — but to avoid a dead frame, delete the `self.currencyPanel = listPanel(...)` line ~385 and its `curlist` pool usage, and remove `self.currencyPanel:Hide()` refs in HideAllCharts/Currency-else).

- [ ] **Step 2: Add `curcollected` to the pool release list** (~line 580), and remove `curlist`:
```lua
  for _, name in ipairs({ "source", "vsource", "quality", "qmix", "itype", "bound", "char",
                          "day", "vday", "hour", "weekday", "keystone", "conf", "zone", "item", "itemval",
                          "curcollected", "cursrc", "curchar", "curday" }) do
```

- [ ] **Step 3: Replace the "Top currencies" list render (~line 755-761)** with a bar section:
```lua
    -- Currency Collected — one bar per currency, length = qty relative to the largest, neutral color.
    local curMax = 1
    for _, curTotal in pairs(stats.byCurrency) do if curTotal > curMax then curMax = curTotal end end
    local collectedRows = {}
    for _, e in ipairs(sortedByCount(stats.byCurrency)) do
      collectedRows[#collectedRows + 1] =
        { label = e.key, color = NEUTRAL, frac = e.count / curMax, value = tostring(e.count) }
    end
    y = self:renderBarSection(P.curcollected, H.currencyCollected, collectedRows, y, w, pad)
```

- [ ] **Step 4: Lint + smoke**

Run: `luacheck modules/Analytics.lua 2>&1 | tail -1`
Expected: OK.
Smoke: the "Currency collected" list is now a neutral-color horizontal bar chart titled "Currency Collected", one bar per currency, sorted qty desc.

- [ ] **Step 5: Commit**

```bash
git add modules/Analytics.lua
git commit -m "feat(insights): Currency Collected as a horizontal bar chart"
```

---

### Task 4: "Currency by Source" chart (new)

**Files:**
- Modify: `modules/Analytics.lua` — Currency block (after Currency Collected), pool list, headers, HideAllCharts.

**Interfaces:**
- Consumes: `stats.currencyBySource` (Task 1).

- [ ] **Step 1: Add header** in `self.headers`:
```lua
    currencyBySrc = sectionHeader(content, "Currency by Source"),
```
Add `"curbysrc"` to the pool release list (Step 2 pattern from Task 3).

- [ ] **Step 2: Render, right after Currency Collected:**
```lua
    -- Currency by Source — one bar per source, length = total qty relative to the largest.
    local csMax = 1
    for _, q in pairs(stats.currencyBySource or {}) do if q > csMax then csMax = q end end
    local csRows = {}
    for _, e in ipairs(sortedByCount(stats.currencyBySource or {})) do
      csRows[#csRows + 1] = { label = NS.Constants.SourceLabel[e.key] or e.key,
        color = SOURCE_COLOR[e.key] or NEUTRAL, frac = e.count / csMax, value = tostring(e.count) }
    end
    y = self:renderBarSection(P.curbysrc, H.currencyBySrc, csRows, y, w, pad)
```

- [ ] **Step 3: Lint + smoke** — `luacheck modules/Analytics.lua`; smoke: a "Currency by Source" bar chart appears, one source per bar, colored by source, total-quantity length.

- [ ] **Step 4: Commit**
```bash
git add modules/Analytics.lua
git commit -m "feat(insights): Currency by Source chart (total qty per source)"
```

---

### Task 5: Rename stacked chart → "Currency by Type × Source" + legend

**Files:**
- Modify: `modules/Analytics.lua` — header text (~line 375), add `renderLegend` helper + a legend pool, render legend under the stacked chart.

- [ ] **Step 1: Rename the header** in `self.headers` (~line 375):
```lua
    currencySrc   = sectionHeader(content, "Currency by Type \195\151 Source"),
```
(`\195\151` = "×".)

- [ ] **Step 2: Add a `makeSwatch` + `renderLegend` helper** (near the other `make*`/`render*` helpers, ~line 198/420). A legend row = color swatch + label, wrapped across the width.

```lua
local function makeSwatch(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(14)
  local sw = f:CreateTexture(nil, "ARTWORK"); sw:SetSize(10, 10)
  sw:SetPoint("LEFT", f, "LEFT", 0, 0)
  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", sw, "RIGHT", 4, 0); fs:SetTextColor(0.8, 0.8, 0.82)
  f.sw, f.fs = sw, fs
  return f
end
```
```lua
-- Render a wrapped legend of color-swatch + label chips. rows = { { label, color = {r,g,b} } }.
function Analytics:renderLegend(pool, rows, y, w, pad)
  local x, rowY, chipW = pad, y, 120
  for _, row in ipairs(rows) do
    if x + chipW > w - pad then x = pad; rowY = rowY - 16 end
    local chip = acquire(pool, function() return makeSwatch(self.content) end)
    chip.sw:SetColorTexture(row.color[1], row.color[2], row.color[3], 0.95)
    chip.fs:SetText(row.label)
    chip:ClearAllPoints(); chip:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, rowY)
    chip:SetWidth(chipW); chip:Show()
    x = x + chipW
  end
  return rowY - 16 - SECTION_GAP
end
```
Add `"curlegend"` to the pool release list.

- [ ] **Step 3: Render the legend right after the stacked chart** (`y = self:renderStackedBarSection(P.cursrc, H.currencySrc, stackRows, y, w, pad)`), using the same source order/colors as Currency by Source:
```lua
    local legendRows = {}
    for _, e in ipairs(sortedByCount(stats.currencyBySource or {})) do
      legendRows[#legendRows + 1] = { label = NS.Constants.SourceLabel[e.key] or e.key,
        color = SOURCE_COLOR[e.key] or NEUTRAL }
    end
    y = self:renderLegend(P.curlegend, legendRows, y, w, pad)
```

- [ ] **Step 4: Lint + smoke** — `luacheck modules/Analytics.lua`; smoke: the stacked chart is titled "Currency by Type × Source" and a color legend (swatch + source name) sits under it, colors matching Currency by Source.

- [ ] **Step 5: Commit**
```bash
git add modules/Analytics.lua
git commit -m "feat(insights): rename stacked currency chart to Type x Source + add legend"
```

---

### Task 6: More-distinct shared `SOURCE_COLOR` palette (+ REFUND, BONUS_ROLL)

**Files:**
- Modify: `modules/Analytics.lua:26-35` (`SOURCE_COLOR`).

- [ ] **Step 1: Load the dataviz skill** for categorical-palette guidance (distinct hues, dark-background readability) BEFORE choosing values. Run: invoke `Skill dataviz`.

- [ ] **Step 2: Replace `SOURCE_COLOR`** with a 16-key, visually-distinct palette (add `REFUND`, `BONUS_ROLL`; keep OTHER neutral). Values are `{r,g,b}` 0–1. Choose per dataviz guidance; example distinct set:

```lua
local SOURCE_COLOR = {
  KILL       = { 0.86, 0.31, 0.31 }, CONTAINER  = { 0.90, 0.62, 0.24 },
  MPLUS      = { 0.63, 0.40, 0.92 }, ROLL       = { 0.30, 0.72, 0.52 },
  BONUS_ROLL = { 0.36, 0.62, 0.98 }, QUEST      = { 0.95, 0.80, 0.30 },
  TRADE      = { 0.28, 0.78, 0.80 }, MAIL       = { 0.58, 0.72, 0.86 },
  AH         = { 0.92, 0.52, 0.78 }, VENDOR     = { 0.62, 0.66, 0.72 },
  CRAFT      = { 0.52, 0.82, 0.42 }, DISENCHANT = { 0.78, 0.42, 0.92 },
  MILLING    = { 0.44, 0.68, 0.30 }, PROSPECTING= { 0.36, 0.60, 0.86 },
  REFUND     = { 0.94, 0.46, 0.30 }, OTHER      = { 0.55, 0.55, 0.60 },
}
```

- [ ] **Step 3: Lint + smoke** — `luacheck modules/Analytics.lua`; smoke: Loot by source, Currency by Source, and the Type×Source legend all use the new distinct colors, and Refund/Bonus Roll are no longer gray.

- [ ] **Step 4: Commit**
```bash
git add modules/Analytics.lua
git commit -m "style(insights): more-distinct shared source palette; add REFUND/BONUS_ROLL"
```

---

## Phase 2 — Insights CSV

### Task 7: Insights CSV currency sections

**Files:**
- Modify: `modules/Export.lua:257-289` (`E:InsightsCSV` currency block).
- Test: `tests/test_export.lua`.

**Interfaces:**
- Consumes: `stats.currencyBySource` (Task 1).

- [ ] **Step 1: Write the failing tests** (append to `tests/test_export.lua`; reuse the file's `insightsStats()` helper — extend it if needed to include `currencyBySource` and a `currencySourceMatrix`).

```lua
test("Export: InsightsCSV renames the per-currency breakdown to Currency by Type x Source", function()
  local s = insightsStats()
  s.currencySourceMatrix = { Badge = { VENDOR = 30, REFUND = 20 } }
  s.currencyBySource = { VENDOR = 34, REFUND = 20 }
  local csv = NS.Export:InsightsCSV(s)
  assertTrue(csv:find("Currency by Type x Source,Badge / Vendor", 1, true) ~= nil)
  assertTrue(csv:find("\r\nCurrency by Source,", 1, true) ~= nil)   -- the new source-total section exists
end)

test("Export: InsightsCSV Currency by Source rows carry the source total qty", function()
  local s = insightsStats()
  s.currencyBySource = { VENDOR = 34, REFUND = 20 }
  local csv = NS.Export:InsightsCSV(s)
  assertTrue(csv:find("Currency by Source,Vendor,34", 1, true) ~= nil)
  assertTrue(csv:find("Currency by Source,Refund,20", 1, true) ~= nil)
end)
```

- [ ] **Step 2: Run, verify fail** — `lua tests/run.lua 2>&1 | grep -i "Currency by\|failed"`. Expected FAIL.

- [ ] **Step 3: Implement.** In `E:InsightsCSV` currency block (~line 260-271):
  - Change the section label string `"Currency by Source"` (the per-currency×source loop, line 269) to `"Currency by Type x Source"`.
  - After that loop, add a new section from `currencyBySource`:
```lua
  section("Currency by Source", rankedRows(stats.currencyBySource, srcLabel))
```
(`srcLabel` and `rankedRows` are already defined above in the function.)

- [ ] **Step 4: Run tests + lint** — `lua tests/run.lua 2>&1 | tail -1 && luacheck modules/Export.lua 2>&1 | tail -1`. Expected pass/OK.

- [ ] **Step 5: Commit**
```bash
git add modules/Export.lua tests/test_export.lua
git commit -m "feat(export): Insights CSV — rename to Type x Source + add Currency by Source"
```

---

## Phase 3 — Export to AI: currency into the CSVs

### Task 8: AI history CSV carries currency

**Files:**
- Modify: `modules/Export.lua:120-159` (`AI_COLUMNS` build + `E:AICSV`).
- Test: `tests/test_export.lua`.

- [ ] **Step 1: Write the failing tests** (append):

```lua
test("Export: AICSV header includes currencyID (currency now supported)", function()
  local header = NS.Export:AICSV({}):match("^(.-)\r\n")
  assertTrue(header:find("currencyID", 1, true) ~= nil)
end)

test("Export: AICSV keeps currency rows", function()
  local csv = NS.Export:AICSV({
    { ts = 1, char = "A-R", currencyID = 42, itemName = "Badge", quality = 3,
      quantity = 7, source = "VENDOR", itemType = "Currency" },
  })
  assertTrue(csv:find("Badge", 1, true) ~= nil)   -- currency row is present, not dropped
end)
```

- [ ] **Step 2: Run, verify fail** — `lua tests/run.lua 2>&1 | grep -i "currency\|failed"`. Expected FAIL (header lacks currencyID; row dropped).

- [ ] **Step 3: Implement.**
  - In the `AI_COLUMNS` builder (~line 128-131) remove the `and c[1] ~= "currencyID"` clause so it becomes:
```lua
for _, c in ipairs(COLUMNS) do
  if not c[1]:find("^auc_") then
    AI_COLUMNS[#AI_COLUMNS + 1] = c
    AI_HEADER[#AI_HEADER + 1] = c[1]
```
  - In `E:AICSV` (~line 154-159) drop the currency filter — serialize all records:
```lua
function E:AICSV(records)
  return serializeCSV(records, AI_COLUMNS, AI_HEADER)
end
```
  - Remove the `TODO(currency-ai)` comment block (~line 124-126) and the "AI export is item-only …" comment (~line 152-153); replace with a one-line note that AI now carries currency.
  - Update the existing AICSV header test (~line 44-52) if it asserted `currencyID` is absent — flip that expectation.

- [ ] **Step 4: Run tests + lint** — `lua tests/run.lua 2>&1 | tail -1 && luacheck modules/Export.lua 2>&1 | tail -1`. Expected pass/OK.

- [ ] **Step 5: Commit**
```bash
git add modules/Export.lua tests/test_export.lua
git commit -m "feat(export): AI history CSV now carries currency rows + currencyID"
```

---

## Phase 4 — AI report assets (guideline + assembler + template)

### Task 9: `build_report.py` — accept + reconcile currency

**Files:**
- Modify: `tools/build_report.py` (`HKEYS`, `parse_history_csv`, `validate_against_insights`, `computed_figures`).
- Test: `tools/tests/test_build_report.py`.

**Interfaces:**
- Produces: `H` rows gain a `cid` key (null for item rows). Item cross-checks (distinct items, epic+, best iLvl, richest, Σ(val×qty)) exclude currency rows; `records`/`characters`/`busiest day` include them.

- [ ] **Step 1: Write failing tests** (append to `tools/tests/test_build_report.py`; follow its existing fixture style).

```python
def test_currency_row_parses_and_excludes_from_item_checks():
    hist = (
        "ts,date,time,char,classFile,itemID,currencyID,itemName,quality,qualityRaw,"
        "itemLevel,bound,vendorPrice,vendorPriceRaw,auctionPrice,auctionPriceRaw,value,"
        "valueRaw,auctionSource,itemType,itemSubType,quantity,source,zone,wowheadLink\r\n"
        "1,12-Jul-2026,20:00,Hero-Rlm,MAGE,555,,Sword,Epic,4,207,Bind on Pickup,"
        "1g 0s 0c,10000,,,1g 0s 0c,10000,,Weapon,Sword,1,KILL,Zone,http://x\r\n"
        "2,12-Jul-2026,20:01,Hero-Rlm,MAGE,,42,Badge,Rare,3,,Warbound,"
        ",,,,,,,,Currency,The War Within,50,VENDOR,Zone,\r\n"
    )
    realm, rows = build_report.parse_history_csv(hist)
    assert len(rows) == 2
    assert rows[1]["cid"] == 42 and rows[1]["id"] is None
    fig = build_report.computed_figures(rows)
    assert fig["records"] == 2          # currency counts as a record
    assert fig["distinct"] == 1         # but not as a distinct item
    assert fig["epic_plus"] == 1        # currency (Rare) not counted
    assert fig["value"] == 10000        # currency contributes 0 value
```

- [ ] **Step 2: Run, verify fail** — `cd tools && python3 -m pytest tests/test_build_report.py -k currency -q` (or `python3 -m unittest` per the file's style). Expected FAIL (`int(r["itemID"])` raises on the blank currency itemID).

- [ ] **Step 3: Implement** in `tools/build_report.py`:
  - `HKEYS` (line 16): insert `"cid"` after `"id"`.
  - `parse_history_csv` row dict: change `"id": int(r["itemID"])` → `"id": _int_or_none(r["itemID"])`; add `"cid": _int_or_none(r.get("currencyID"))`; make `"qr": _int_or_none(r["qualityRaw"])` (currency `qr` may be blank).
  - `validate_against_insights`:
    - Distinct items: `len({o["id"] for o in rows if o["id"] is not None})`.
    - Epic+: `sum(1 for o in rows if o["cid"] is None and (o["qr"] or 0) >= 4)`.
    - Richest: `max((o["val"] * o["qty"] for o in rows if o["cid"] is None), default=0)`.
  - `computed_figures`: same three exclusions (`distinct`, `epic_plus`, `richest`); `value` already sums all but currency `val==0` so it's unaffected — leave as `sum(o["val"] * o["qty"] for o in rows)`.

- [ ] **Step 4: Run tests** — `cd tools && python3 -m pytest tests/ -q` (all green). Also re-run the shipped-sample build once to confirm no regression: `python3 build_report.py --template ../docs/ai-export-template.html --history <sample> --insights <sample> --cards <sample-cards> -o /tmp/r.html` — or the repo's existing sample invocation in the tests.

- [ ] **Step 5: Commit**
```bash
git add tools/build_report.py tools/tests/test_build_report.py
git commit -m "feat(ai-export): build_report.py parses currency rows, excludes from item checks"
```

---

### Task 10: Report template engine — currency support

> No JS unit harness. Gate = `build_report.py` PASS on a currency-bearing export (produced from a real `/lh` export or a hand-built CSV) **and** the shipped sample still PASS, plus a visual open of the output.

**Files:**
- Modify: `docs/ai-export-template.html` (engine `<script>`, lines ~800-1150, and the sample `H` block).

- [ ] **Step 1: Add `cid` to the sample `H` + a couple of currency sample rows** near `const H = [` so the template's own sample exercises currency (item rows get `cid:null`; currency rows: `id:null, cid:<n>, il:null, v:0, a:null, val:0, ty:"Currency", st:<category>, q:<tier>, b:<bound>`).

- [ ] **Step 2: Guard item-only computations to skip currency (`r.cid!=null`).** Mirror the in-game Stats semantics exactly (charts the addon computes item-only must exclude currency; charts it computes over all rows keep all):
  - `renderKPIs` (line 872-873): guard the item-only trio —
```js
  rows.forEach(function(r){days[r.d]=1;chars[r.c]=1;byDay[r.d]=(byDay[r.d]||0)+1;
    if(r.cid==null){items[r.id]=1;if(r.qr>=4)epic++;if(r.il>best)best=r.il;}});
```
  - `renderInsights`: **exclude currency** from Bind state (896), Quality (900), Item types (904), and Richest/Most-looted (`byItem`, 927) — build those from `rows.filter(function(r){return r.cid==null;})`. **Keep all rows** for Where-loot-came-from (source, 891), Loot-by-character (907), Top zones (913), Activity-over-time (917), heatmap (924) — matching in-game `bySource`/`byChar`/`byZone`/`byDay`/`byHour` which count every record.
  - `renderHoard` (880): unchanged (currency `val==0`).

- [ ] **Step 3: Add a Currency subsection to `renderInsights`** (append cards before `$("#rpt-insights").innerHTML=out.join('')`), computed from `var cur=rows.filter(function(r){return r.cid!=null;});` — render only when `cur.length`:
  - **Currency Collected** — `bars()` of `groupBy(cur, function(r){return r.n;})` by qty, neutral fill.
  - **Currency by Source** — `bars()` of currency qty grouped by `srcName(r.s)`, colored via a source→color map (add a `SRCCOLOR` JS object mirroring the Lua `SOURCE_COLOR`, hex form).
  - **Currency by Type × Source** — a stacked/segmented bar per currency (or, to reuse `bars()`, one grouped card per currency); include a small legend of source colors.
  - Reuse the existing `bars()`/`toplist()` helpers where possible; keep classes/styling intact (no new CSS).

- [ ] **Step 4: Render currency rows in the History table.** In `rowHTML` (971), branch on `r.cid!=null`: name cell = currency name colored by quality (no `href`, since `r.wh` is empty — render a `<span class="il qt-<q>">` not an `<a>`); iLvl/Vendor/Auction cells show `—`; Type="Currency", Subtype=category, Source badge + Zone as normal. Ensure `dataTT`/`ilink` are not called with a broken link for currency (guard `ilink` or add `curName(r)`).

- [ ] **Step 5: Build + validate.** Produce a currency-bearing export (in-game `/lh` → Export → AI on an account with currency, or hand-craft `history.csv` + `insights.csv`), then:
```bash
cd tools && python3 build_report.py --template ../docs/ai-export-template.html \
  --history /tmp/cur_history.csv --insights /tmp/cur_insights.csv --cards /tmp/cards.html -o /tmp/cur_report.html
```
Expected: **PASS** (Records include currency; Distinct/Epic+/Value reconcile item-only). Open `/tmp/cur_report.html`: Insights shows a Currency section; the History table lists currency rows cleanly; no console errors.
Also re-run the shipped-sample build to confirm no regression.

- [ ] **Step 6: Commit**
```bash
git add docs/ai-export-template.html
git commit -m "feat(ai-export): report engine renders currency (charts, table, KPIs guarded)"
```

---

### Task 11: Update the AI export guideline

**Files:**
- Modify: `docs/ai-export-guideline.md` (data-contract table ~line 203-231, INSIGHTS section list ~line 157-159, rev line ~line 3).

- [ ] **Step 1: Add currency to the data contract.**
  - Add the `H` key row: `| `cid` | `currencyID` | number, or `null` for item rows |`.
  - Note a **currency row** has `id=null`, `cid` set, `il/v/a/val = null/0`, `q`=currency tier, `b`=bound label, `ty="Currency"`; it is **excluded** from every item worth/KPI/chart and drives the Currency section instead.
  - Add the currency INSIGHTS sections to the list (line ~157-159): `Currency Collected`, `Currency by Source`, `Currency by Type x Source`, `Currency by Character`, `Currency by Day`.
  - Bump the rev line (line 3), e.g. `rev7 → rev8`, with today's date.

- [ ] **Step 2: Verify no stale "item-only" claims remain** — `grep -ni "item-only\|currency" docs/ai-export-guideline.md` and reconcile.

- [ ] **Step 3: Commit**
```bash
git add docs/ai-export-guideline.md
git commit -m "docs(ai-export): teach the guideline about currency rows + sections"
```

---

## Phase 5 — Docs, inventory, badge

### Task 12: Docs + test inventory + badge

**Files:**
- Modify: `docs/browser.md` and/or `docs/data-model.md` (Insights reorg + `currencyBySource`), `docs/smoke-tests.md` (§7 Insights + §6a Export), `docs/test-cases.md` (regenerate), `README.md` (tests badge).

- [ ] **Step 1: Update `docs/smoke-tests.md`** §7 (the two dividers; loot charts under Loot; the four currency charts + legend under Currency) and §6a (Insights CSV currency sections; AI export now carries currency end-to-end — assembler PASS on a currency export, report shows a Currency section).

- [ ] **Step 2: Update `docs/browser.md` / `docs/data-model.md`** — note the Insights Loot/Currency sections and the `currencyBySource` stat.

- [ ] **Step 3: Regenerate the inventory + bump the badge.**
```bash
lua tests/run.lua --list > docs/test-cases.md
```
Then update the README `tests` badge count to the new total (`lua tests/run.lua 2>&1 | tail -1`).

- [ ] **Step 4: Full verification** — `lua tests/run.lua 2>&1 | tail -1 && luacheck . 2>&1 | tail -1 && (cd tools && python3 -m pytest tests/ -q)`. Expected: all green, luacheck 0/0.

- [ ] **Step 5: Commit**
```bash
git add docs/ README.md
git commit -m "docs(insights): document Loot/Currency sections + currency exports; sync tests badge"
```

---

## Self-review (planner)

- **Spec coverage:** dividers+reorder (T2) · Currency Collected (T3) · Currency by Source (T4, uses T1 stat) · Type×Source rename+legend (T5) · palette (T6) · `currencyBySource` stat (T1) · Insights CSV (T7) · AI history CSV currency (T8) · build_report.py (T9) · template engine (T10) · guideline (T11) · docs/badge (T12). All spec sections mapped.
- **Type consistency:** `stats.currencyBySource` (map source→qty) defined in T1, consumed by T4/T5/T7; `cid` key defined in T9, consumed by T10; header keys `currencyCollected`/`currencyBySrc`/`currencySrc` consistent across BuildCharts + LayoutCharts.
- **No placeholders:** each code step shows the actual diff; UI-only tasks (no harness) state the luacheck + explicit in-game smoke gate; template task gates on the assembler PASS + visual open.
- **Ordering note:** in-game `bySource`/`byChar`/`byZone`/`byDay` count *all* records (incl. currency) today; the plan preserves that (report mirrors it) so assembler cross-checks stay green — a deliberate, ratified consistency choice, not a bug.
