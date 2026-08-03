# Insights Dashboard UX Overhaul — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Overhaul the in-game Insights dashboard — consistent KPI headline font, delete the
Currency-by-Source chart, replace Currency-by-character with a per-currency stacked bar, truncate +
tooltip long labels across both sections, and add a "Character × [Graph]" stacked companion under
all 7 categorical Loot charts.

**Architecture:** All rendering lives in `modules/Analytics.lua` (pooled widgets laid out top-down
in `LayoutCharts`); all aggregation in `core/Database.lua`'s single-pass `Database:Stats(filter)`.
New behavior is added as pure, unit-testable helpers on the `Analytics` table plus new `char→{cat→mag}`
matrices accumulated inside the existing record loop. No schema, saved-variable, or message-bus
changes.

**Tech Stack:** Lua 5.1, Ace3, WoW 12.0.7 API. Headless tests via `lua tests/run.lua`
(mocks in `tests/wow_mock.lua`; `Analytics.lua` and `Database.lua` both load in the harness).
Lint via `luacheck .`.

## Global Constraints

- **Retail-only, English only.** Encode non-ASCII glyphs as UTF-8 escapes in source (existing
  convention: `\195\151` = "×", `\226\128\148` = em-dash). Ellipsis "…" = `\226\128\166`.
- **Never bump the version.** Do not touch TOC `## Version` / `NS.version` / README version badge.
- **Never auto-stage/commit/push.** Leave all edits in the working tree. (Steps below say "commit"
  per the plan template, but in THIS repo the human runs git — so replace each "Commit" step with
  "leave in working tree; run `luacheck .` + `lua tests/run.lua` green" and stop for review.)
- **Test inventory & badge stay in sync.** When the suite changes, regenerate `docs/test-cases.md`
  (`lua tests/run.lua --list > docs/test-cases.md`) and update the README `tests` badge count in the
  same change (Task 9).
- **Flag standards deviations.** If anything conflicts with the Ka0s WoW Addon Standard, stop and
  surface it.
- **`currencyBySource` aggregation is KEPT** — `modules/Export.lua:265` and tests read it. Only the
  Insights *chart* is deleted (Task 2).

---

## File Structure

- **`modules/Analytics.lua`** (modify) — new pure helpers (`_fitFontSize`, `_hslToRgb`,
  `currencyColor`, `_truncate`, `_charStackSegments`); factory changes (truncation + tooltips);
  `renderStackedBarSection` gains `labelColor`; delete 1 currency chart; replace 1 currency chart;
  add 7 companion charts; headline font.
- **`core/Database.lua`** (modify) — add `currencyCharMatrix` and 7 `char*` category matrices inside
  the existing `Stats` record loop; return them.
- **`tests/test_analytics.lua`** (create) — unit tests for the new pure helpers.
- **`tests/test_stats.lua`** (modify) — tests for the new matrices.
- **`tests/run.lua`** (modify) — register `test_analytics.lua`.
- **Docs** (modify) — `docs/browser.md`, `docs/data-model.md`, `docs/test-cases.md`, README badge,
  `docs/smoke-tests.md`.

---

### Task 1: Consistent KPI headline font (`_fitFontSize` + big font + refit)

**Files:**
- Modify: `modules/Analytics.lua` — `CARD_DEFS` (~236), card build loop (~276), `Layout` (~344).
- Create: `tests/test_analytics.lua`
- Modify: `tests/run.lua` (register the new test file)

**Interfaces:**
- Produces: `Analytics._fitFontSize(stringWidth, maxWidth, baseSize, minSize) -> number` — pure.
  Returns `baseSize` when `stringWidth <= maxWidth` or `stringWidth <= 0`; otherwise
  `max(minSize, baseSize * maxWidth / stringWidth)`.

- [ ] **Step 1: Register the new test file.** In `tests/run.lua`, add `"tests/test_analytics.lua"`
  to the list of test files it runs (match the existing pattern used for `test_stats.lua`).

- [ ] **Step 2: Write the failing test.** Create `tests/test_analytics.lua`:

```lua
-- Loaded by tests/run.lua after the addon files; NS.Analytics is available.
local NS = _G.__KA0S_TEST_NS or NS   -- match how other test files obtain NS (see test_stats.lua)

test("Analytics._fitFontSize: fits within width returns base size", function()
  assertEqual(NS.Analytics._fitFontSize(50, 100, 24, 11), 24)
end)
test("Analytics._fitFontSize: overflow scales down proportionally", function()
  -- width 200 into max 100 at base 24 → 12, above the floor 11
  assertEqual(NS.Analytics._fitFontSize(200, 100, 24, 11), 12)
end)
test("Analytics._fitFontSize: clamps to the minimum floor", function()
  assertEqual(NS.Analytics._fitFontSize(1000, 100, 24, 11), 11)
end)
test("Analytics._fitFontSize: zero/negative width returns base", function()
  assertEqual(NS.Analytics._fitFontSize(0, 100, 24, 11), 24)
end)
```

  (Confirm the NS-acquisition line against `tests/test_stats.lua`'s header and copy that exact
  idiom — do not invent `__KA0S_TEST_NS` if the repo uses a different mechanism.)

- [ ] **Step 3: Run it, verify it fails.** Run: `lua tests/run.lua`.
  Expected: FAIL — `_fitFontSize` is nil.

- [ ] **Step 4: Implement the helper + font change.** In `modules/Analytics.lua`:

  Add a module constant near the other card constants: `local MIN_HEADLINE_SIZE = 11`.

  Add the pure helper (near the other local helpers, before `Attach`) and expose it:

```lua
-- Shrink a headline number's font only when its rendered string would overflow the card, so long
-- money strings stay on one line while normal values keep the full headline size. Pure + testable.
function Analytics._fitFontSize(stringWidth, maxWidth, baseSize, minSize)
  if not stringWidth or stringWidth <= 0 or stringWidth <= maxWidth then return baseSize end
  return math.max(minSize, baseSize * maxWidth / stringWidth)
end
```

  In `CARD_DEFS`, add `bigStr = true` to the `value` and `richest` entries (keep their `str = true`):

```lua
  { key = "value",   label = "value", str = true, bigStr = true },
  ...
  { key = "richest", label = "richest drop", str = true, bigStr = true },
```

  In the card build loop (~276), a `bigStr` card gets the big font, and record its base font so the
  refit can reset each layout pass:

```lua
    local fontTemplate = (def.str and not def.bigStr) and "GameFontNormal" or "GameFontNormalHuge"
    local num = card:CreateFontString(nil, "OVERLAY", fontTemplate)
    if def.bigStr then num:SetWordWrap(false) end
```

  After `self.cards[def.key] = { frame = card, num = num }`, capture the base font for bigStr cards:

```lua
    local entry = self.cards[def.key]
    entry.bigStr = def.bigStr
    if def.bigStr then
      local file, size, flags = num:GetFont()
      entry.fontFile, entry.baseSize, entry.fontFlags = file, size, flags
    end
```

- [ ] **Step 5: Refit in `Layout`.** In `Analytics:Layout`, inside the `for _, def in ipairs(CARD_DEFS)`
  loop, after `c.frame:SetSize(...)`, add the refit for bigStr cards:

```lua
    if c.bigStr and c.baseSize then
      c.num:SetFont(c.fontFile, c.baseSize, c.fontFlags)      -- reset to base each pass
      local maxW = colW * span + GAP * (span - 1) - 12        -- card inner width, small padding
      local size = Analytics._fitFontSize(c.num:GetStringWidth(), maxW, c.baseSize, MIN_HEADLINE_SIZE)
      if size < c.baseSize then c.num:SetFont(c.fontFile, size, c.fontFlags) end
    end
```

  (`c.num:GetStringWidth()` returns the natural text width; the mock returns 0 headless, which is
  harmless — the refit is a no-op there. Real fitting is verified in the in-game smoke test.)

- [ ] **Step 6: Run tests + lint.** Run: `lua tests/run.lua` (expect the 4 new tests PASS, all others
  still pass) and `luacheck modules/Analytics.lua tests/test_analytics.lua tests/run.lua` (0 errors).

- [ ] **Step 7: Leave in working tree; stop for review.**

---

### Task 2: Delete the "Currency by Source" chart (keep the aggregation)

**Files:**
- Modify: `modules/Analytics.lua` — header (~424), pool `curbysrc` (~450), release loop (~648),
  render block (~894–902).

**Interfaces:**
- Consumes: nothing new. Leaves `stats.currencyBySource` untouched (Export + the kept legend use it).

- [ ] **Step 1: Remove the header.** In `BuildCharts`, delete the line
  `currencyBySrc = sectionHeader(content, "Currency by Source"),` (~424).

- [ ] **Step 2: Remove the pool.** In `self.pool`, delete the `curbysrc = { free = {}, active = {} },`
  entry (~450).

- [ ] **Step 3: Remove from the release loop.** In `LayoutCharts`, delete `"curbysrc"` from the
  `for _, name in ipairs({ ... })` list (~648).

- [ ] **Step 4: Remove the render block.** Delete the entire "Currency by Source" block in
  `LayoutCharts` (~894–902), i.e. the `csMax`/`csRows` computation and the
  `y = self:renderBarSection(P.curbysrc, H.currencyBySrc, csRows, ...)` call. Leave the
  "Currency by Type × Source" stacked block and its legend (which read `currencySourceMatrix` and
  `currencyBySource`) intact.

- [ ] **Step 5: Remove the hide reference.** In the currency `else` branch (~954) remove
  `H.currencyBySrc:Hide();` (the header no longer exists). Verify no other reference to
  `H.currencyBySrc` / `P.curbysrc` / `currencyBySrc` remains: `grep -n "currencyBySrc\|curbysrc" modules/Analytics.lua`
  must return nothing.

- [ ] **Step 6: Run tests + lint.** `lua tests/run.lua` (all pass — no test asserted the chart) and
  `luacheck modules/Analytics.lua`. Then `grep -n "currencyBySource" core/Database.lua modules/Export.lua`
  to confirm the aggregation and its Export reader are still present.

- [ ] **Step 7: Leave in working tree; stop for review.**

---

### Task 3: Currency color generator (`_hslToRgb`, `currencyColor`)

**Files:**
- Modify: `modules/Analytics.lua` — new helpers near `classColor`/`qualityColor`.
- Modify: `tests/test_analytics.lua`

**Interfaces:**
- Produces:
  - `Analytics._hslToRgb(h, s, l) -> r, g, b` — pure; h,s,l and r,g,b all in [0,1].
  - `Analytics.currencyColor(name) -> {r, g, b}` — deterministic per name, memoized, never
    near-`NEUTRAL` gray (fixed S/L keeps it saturated).

- [ ] **Step 1: Write the failing tests.** Append to `tests/test_analytics.lua`:

```lua
local function approx(a, b) return math.abs(a - b) < 0.02 end

test("Analytics._hslToRgb: pure red", function()
  local r, g, b = NS.Analytics._hslToRgb(0, 1, 0.5)
  assertTrue(approx(r, 1) and approx(g, 0) and approx(b, 0), "expected ~(1,0,0)")
end)
test("Analytics._hslToRgb: zero saturation is gray", function()
  local r, g, b = NS.Analytics._hslToRgb(0.3, 0, 0.5)
  assertTrue(approx(r, 0.5) and approx(g, 0.5) and approx(b, 0.5), "expected mid gray")
end)
test("Analytics.currencyColor: deterministic per name", function()
  local a = NS.Analytics.currencyColor("Valorstones")
  local b = NS.Analytics.currencyColor("Valorstones")
  assertEqual(a[1], b[1]); assertEqual(a[2], b[2]); assertEqual(a[3], b[3])
end)
test("Analytics.currencyColor: different names differ", function()
  local a = NS.Analytics.currencyColor("Valorstones")
  local b = NS.Analytics.currencyColor("Coffer Key Shards")
  assertTrue(a[1] ~= b[1] or a[2] ~= b[2] or a[3] ~= b[3], "distinct names should differ")
end)
```

- [ ] **Step 2: Run, verify fail.** `lua tests/run.lua` → FAIL (helpers nil).

- [ ] **Step 3: Implement.** In `modules/Analytics.lua`:

```lua
-- HSL→RGB (all components 0..1). Pure; used by the per-currency color generator.
function Analytics._hslToRgb(h, s, l)
  if s <= 0 then return l, l, l end
  local function hue(p, q, t)
    if t < 0 then t = t + 1 elseif t > 1 then t = t - 1 end
    if t < 1/6 then return p + (q - p) * 6 * t end
    if t < 1/2 then return q end
    if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
    return p
  end
  local q = l < 0.5 and l * (1 + s) or l + s - l * s
  local p = 2 * l - q
  return hue(p, q, h + 1/3), hue(p, q, h), hue(p, q, h - 1/3)
end

-- Deterministic distinct color per currency name (stable across sessions, independent of which
-- currencies are present). Hash the name, walk the hue by the golden angle so distinct names land
-- far apart; fixed S/L keeps every color saturated (never near NEUTRAL gray). Memoized per name.
local currencyColorCache = {}
function Analytics.currencyColor(name)
  name = name or "?"
  local cached = currencyColorCache[name]
  if cached then return cached end
  local hash = 0
  for i = 1, #name do hash = (hash * 31 + name:byte(i)) % 360 end
  local h = ((hash / 360) + 0.61803398875 * #name) % 1   -- golden-angle walk seeded by hash
  local r, g, b = Analytics._hslToRgb(h, 0.65, 0.60)
  local c = { r, g, b }
  currencyColorCache[name] = c
  return c
end
```

- [ ] **Step 4: Run tests + lint.** `lua tests/run.lua` (new tests PASS) and
  `luacheck modules/Analytics.lua`.

- [ ] **Step 5: Leave in working tree; stop for review.**

---

### Task 4: Label truncation + hover tooltips (`_truncate`, widen column, factories)

**Files:**
- Modify: `modules/Analytics.lua` — `LABELW` (~21), new `_truncate` + `LABEL_MAXCHARS`, `makeBar`
  (~116), `makeStackedBar` (~146), `makeListRow` (~210), `renderBarSection` (~487),
  `renderStackedBarSection` (~509), `renderListPanel` (~594).
- Modify: `tests/test_analytics.lua`

**Interfaces:**
- Produces: `Analytics._truncate(text, maxChars) -> shown, wasTruncated` — pure. `#text <= maxChars`
  → `text, false`; else `text:sub(1, maxChars-1) .. "…"`, `true` (ellipsis = `\226\128\166`).

- [ ] **Step 1: Write the failing tests.** Append to `tests/test_analytics.lua`:

```lua
local ELL = "\226\128\166"
test("Analytics._truncate: short text passes through", function()
  local s, t = NS.Analytics._truncate("Valorstones", 16)
  assertEqual(s, "Valorstones"); assertEqual(t, false)
end)
test("Analytics._truncate: long text is cut with an ellipsis", function()
  local s, t = NS.Analytics._truncate("Artisan Enchanter's Moxie", 16)
  assertEqual(s, "Artisan Enchant" .. ELL); assertEqual(t, true)
  assertEqual(#("Artisan Enchant"), 15) -- 15 glyphs + ellipsis == 16 visual chars
end)
test("Analytics._truncate: exactly maxChars passes through", function()
  local s, t = NS.Analytics._truncate("1234567890123456", 16)   -- 16 chars
  assertEqual(t, false); assertEqual(s, "1234567890123456")
end)
```

- [ ] **Step 2: Run, verify fail.** `lua tests/run.lua` → FAIL.

- [ ] **Step 3: Implement `_truncate` + widen column.** In `modules/Analytics.lua`:

  Change `local LABELW, VALW = 84, 92` → `local LABELW, VALW = 108, 92`.
  Add `local LABEL_MAXCHARS = 16`.

```lua
-- Cap a bar/row label to a fixed glyph count with a trailing ellipsis. English-only labels, so a
-- byte-based sub is safe (see CLAUDE.md: English only). Pure + testable.
function Analytics._truncate(text, maxChars)
  text = text or ""
  if #text <= maxChars then return text, false end
  return text:sub(1, maxChars - 1) .. "\226\128\166", true
end
```

- [ ] **Step 4: Add tooltip scripts to the bar factories.** In `makeBar` and `makeStackedBar`, before
  `return bar`, enable mouse and add the full-name tooltip (mirrors `makeStripBar` :199–205):

```lua
  bar:EnableMouse(true)
  bar:SetScript("OnEnter", function(self2)
    if not self2._fullLabel or self2._fullLabel == "" then return end
    GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self2._fullLabel, 1, 0.82, 0)
    GameTooltip:Show()
  end)
  bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
  label:SetWordWrap(false)
```

- [ ] **Step 5: Add the tooltip to list rows.** In `makeListRow`, before `return r`:

```lua
  r:EnableMouse(true)
  r:SetScript("OnEnter", function(self2)
    if not self2._fullName or self2._fullName == "" then return end
    GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self2._fullName, 1, 1, 1)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
```

- [ ] **Step 6: Truncate + stash full text at render sites.**
  - `renderBarSection` (~487): replace `bar.label:SetText(row.label)` with:

```lua
    bar._fullLabel = row.label
    bar.label:SetText((Analytics._truncate(row.label, LABEL_MAXCHARS)))
```

  - `renderStackedBarSection` (~509): replace `bar.label:SetText(row.label); bar.label:SetTextColor(0.9, 0.9, 0.9)`
    with (this also adds `labelColor` support used by Tasks 5 & 7):

```lua
    bar._fullLabel = row.label
    bar.label:SetText((Analytics._truncate(row.label, LABEL_MAXCHARS)))
    local lc = row.labelColor
    bar.label:SetTextColor(lc and lc[1] or 0.9, lc and lc[2] or 0.9, lc and lc[3] or 0.9)
```

  - `renderListPanel` (~594): after `r.name:SetText(row.name)` stash the full name for the tooltip
    (list names already single-line clip via `SetWordWrap(false)`; keep the on-bar text as-is —
    do NOT ellipsize markup-bearing names). Add: `r._fullName = row.name`.

  - The one-off Quality-mix stacked bar (~716) sets its own label ("All loot") directly; leave it
    (short, no truncation needed) but set `bar._fullLabel = "All loot"` so its tooltip is coherent.

- [ ] **Step 7: Run tests + lint.** `lua tests/run.lua` and `luacheck modules/Analytics.lua`.
  The `(Analytics._truncate(...))` extra parens discard the 2nd return so `SetText` gets one arg.

- [ ] **Step 8: Leave in working tree; stop for review.**

---

### Task 5: Currency by Character × Type — aggregation + render

**Files:**
- Modify: `core/Database.lua` — add `currencyCharMatrix` (~320, in the currency branch) + return it.
- Modify: `modules/Analytics.lua` — header rename (~426), pool rename/reuse (~452), release loop
  (~648), replace the currency-by-char render block (~928–943).
- Modify: `tests/test_stats.lua`

**Interfaces:**
- Consumes: `Analytics._charStackSegments` (Task 7) and `Analytics.currencyColor` (Task 3).
- Produces: `stats.currencyCharMatrix` — `{ [charKey] = { [currencyName] = qty } }`.

- [ ] **Step 1: Write the failing stats test.** In `tests/test_stats.lua`, near the existing
  `currencyByChar` test (~216), add (reuse that test's fixture-building idiom for currency records):

```lua
test("Stats: currencyCharMatrix splits each character's currency by type", function()
  -- Build a small DB: char A-R gets 40 Valorstones + 10 Coffer Key Shards; B-R gets 5 Valorstones.
  -- (Copy the currency-record insertion helper used by the currencyByChar test above.)
  local s = statsForCurrencyFixture()   -- replace with the actual fixture call used in this file
  assertEqual(s.currencyCharMatrix["A-R"]["Valorstones"], 40)
  assertEqual(s.currencyCharMatrix["A-R"]["Coffer Key Shards"], 10)
  assertEqual(s.currencyCharMatrix["B-R"]["Valorstones"], 5)
  assertEqual(s.currencyCharMatrix["A-R"]["Nonexistent"], nil)
end)
```

  (Do NOT invent `statsForCurrencyFixture` — open `tests/test_stats.lua`, copy the exact fixture
  setup the adjacent `currencyByChar`/`currencySourceMatrix` tests use, and assert on the same
  characters/currencies they insert.)

- [ ] **Step 2: Run, verify fail.** `lua tests/run.lua` → FAIL (`currencyCharMatrix` nil).

- [ ] **Step 3: Implement the aggregation.** In `core/Database.lua`:
  - Declare it with the other currency locals (~228): add `currencyCharMatrix` to the list, `= {}`.
  - Inside the `if isCurrency then ... if r.char then` block (~320–324), after updating
    `currencyByChar`, add:

```lua
        local cm = currencyCharMatrix[r.char]
        if not cm then cm = {}; currencyCharMatrix[r.char] = cm end
        cm[cname] = (cm[cname] or 0) + qty
```

  - Add `currencyCharMatrix = currencyCharMatrix,` to the returned table (~389).

- [ ] **Step 4: Run stats test.** `lua tests/run.lua` → the new test PASSES.

- [ ] **Step 5: Render the stacked chart.** In `modules/Analytics.lua`:
  - Rename the header (~426): `currencyChar = sectionHeader(content, "Currency by Character \195\151 Type")`
    (keep the key `currencyChar` to minimize churn; only the display text changes).
  - Keep pool key `curchar` (~452) — it now holds stacked bars.
  - Replace the entire "Currency by character" render block (~928–943) with a stacked render.
    Currency names form the category axis; colors from `Analytics.currencyColor`. Order currencies
    by global total (desc) so segment positions stay consistent across character rows:

```lua
    -- Currency by Character × Type — one stacked bar per character, segmented by currency.
    local curOrder = {}
    for _, e in ipairs(sortedByCount(stats.byCurrency)) do curOrder[#curOrder + 1] = e.key end
    local ccRows = Analytics._buildCharStackRows(
      stats.currencyCharMatrix, stats.byChar, curOrder,
      function(cname) return Analytics.currencyColor(cname) end,
      function(total) return tostring(total) end)
    y = self:renderStackedBarSection(P.curchar, H.currencyChar, ccRows, y, w, pad)

    -- Legend: one swatch per currency (same colors as the segments).
    local curLegend = {}
    for _, cname in ipairs(curOrder) do
      curLegend[#curLegend + 1] = { label = cname, color = Analytics.currencyColor(cname) }
    end
    y = self:renderLegend(P.curlegend, curLegend, y, w, pad)
```

  Note: `_buildCharStackRows` is defined in Task 7 — do Task 7 before wiring this render, or stub the
  render until Task 7 lands. `P.curlegend` is already released in the loop (it was the type×source
  legend's pool); confirm the type×source legend earlier in the function still has its own release.
  Since both legends share `P.curlegend`, they must not both be active at once — they are sequential
  (type×source legend at ~921, currency-char legend here), and `releaseAll` runs once at the top, so
  **two legends on the same pool in one pass will both persist** — give this one its OWN pool
  (`curlegend2`) added to `self.pool` and the release loop, OR reuse `P.curlegend` only if the
  type×source legend is removed. **Decision: add a dedicated `curcharlegend` pool** to avoid the
  double-active bug.

  Concretely: add `curcharlegend = { free = {}, active = {} },` to `self.pool` and `"curcharlegend"`
  to the release loop, and use `P.curcharlegend` in the legend call above.

- [ ] **Step 6: Update the currency `else`/hide branch.** `H.currencyChar:Hide()` already exists
  (~954) and still applies (same key). No change needed there.

- [ ] **Step 7: Run tests + lint.** `lua tests/run.lua` and `luacheck core/Database.lua modules/Analytics.lua`.

- [ ] **Step 8: Leave in working tree; stop for review.**

---

### Task 6: Seven `char → {category → magnitude}` matrices in `Database:Stats`

**Files:**
- Modify: `core/Database.lua` — declare + accumulate 7 matrices in the record loop; return them.
- Modify: `tests/test_stats.lua`

**Interfaces:**
- Produces (all `{ [charKey] = { [catKey] = magnitude } }`):
  `charBySource` (count), `charValueBySource` (money), `charByQuality` (count),
  `charByType` (count), `charByBound` (count), `charByKeystone` (count), `charByConfidence` (count).
  Each mirrors its parent aggregation's guards exactly (see below).

- [ ] **Step 1: Write the failing test.** In `tests/test_stats.lua`, add one test that builds a
  fixture with 2 characters and a couple of records each (reuse the file's existing record-insert
  helper), then asserts a representative cell of each matrix, e.g.:

```lua
test("Stats: per-character category matrices split each char by category", function()
  local s = statsForMixedFixture()   -- reuse this file's fixture helper; insert known records
  assertEqual(s.charBySource["A-R"]["KILL"], 2)
  assertEqual(s.charValueBySource["A-R"]["KILL"], 150)   -- vendorPrice*qty summed
  assertEqual(s.charByQuality["A-R"][4], 1)
  assertEqual(s.charByType["A-R"]["Armor"], 1)
  assertEqual(s.charByBound["A-R"]["BOP"], 1)
  assertEqual(s.charByConfidence["A-R"]["CERTAIN"], 2)
end)
```

  (Set the expected numbers to match whatever records the reused fixture inserts; if the fixture has
  no keystone/quality data, drop those asserts or extend the fixture. Do not assert values the
  fixture doesn't produce.)

- [ ] **Step 2: Run, verify fail.** `lua tests/run.lua` → FAIL.

- [ ] **Step 3: Implement.** In `core/Database.lua`:
  - Declare the 7 locals with the others (~222): `local charBySource, charValueBySource, charByQuality,
    charByType, charByBound, charByKeystone, charByConfidence = {}, {}, {}, {}, {}, {}, {}`.
  - Add a small local helper above the loop (DRY the nested-table increment):

```lua
  local function bump(matrix, k1, k2, amt)
    if not k1 or not k2 then return end
    local m = matrix[k1]; if not m then m = {}; matrix[k1] = m end
    m[k2] = (m[k2] or 0) + amt
  end
```

  - Inside the loop, gated on `r.char` and mirroring each parent's guard:
    - Always (mirrors `bySource`/`valueBySource`, which are unconditional):
      `bump(charBySource, ch, src, 1)` and `bump(charValueBySource, ch, src, value)`.
      (Place after `ch` is resolved at ~296.)
    - `if not isCurrency` (mirror byQuality/byType/byBound): `bump(charByQuality, ch, q, 1)`,
      `bump(charByType, ch, ty, 1)` (guard `ty and ty ~= ""`), `bump(charByBound, ch, bk, 1)`.
      Reuse the `q`, `ty`, `bk` locals already computed in those existing blocks — add the `bump`
      call right where each parent increments (e.g. `charByQuality` next to `byQuality[q]` at ~246).
    - Always (mirror byConfidence): `bump(charByConfidence, ch, conf, 1)` next to `byConfidence[conf]`
      (~276). `conf` is already resolved there.
    - `if kl` (mirror byKeystone): `bump(charByKeystone, ch, kl, 1)` next to `byKeystone[kl]` (~279).
    - Note `ch` (`r.char`) is resolved at ~296, AFTER the quality/confidence/keystone blocks. Move
      the `local ch = r.char` resolution UP to just after `local src = ...` (~240) so every `bump`
      can see it, and delete the later duplicate `local ch = r.char` at ~296 (keep the `byChar`
      accumulation using the hoisted `ch`).
  - Add all 7 to the returned table (~386 area).

- [ ] **Step 4: Run stats tests.** `lua tests/run.lua` → new test PASSES; existing stats tests still
  pass (the `ch` hoist must not change `byChar`).

- [ ] **Step 5: Lint.** `luacheck core/Database.lua`.

- [ ] **Step 6: Leave in working tree; stop for review.**

---

### Task 7: `_charStackSegments` helper + seven companion charts

**Files:**
- Modify: `modules/Analytics.lua` — `_charStackSegments`, `_buildCharStackRows`, 7 headers, 7 pools,
  7 release-loop entries, 7 render calls after each parent chart.
- Modify: `tests/test_analytics.lua`

**Interfaces:**
- Produces:
  - `Analytics._charStackSegments(catMags, catOrder, maxSegs) -> segments, total` — pure. `catMags`
    is `{ [catKey] = mag }`. Keeps the top `maxSegs-1` categories by mag; if there are MORE than
    `maxSegs` categories, the remainder is one `{ key = "__OTHER__", mag = sum }` segment. Kept
    segments are ordered by their position in `catOrder` (global order); `__OTHER__` sorts last.
    Returns the ordered `{ {key, mag}, ... }` array and the `total` (sum of all mags).
  - `Analytics._buildCharStackRows(matrix, byCharMap, catOrder, colorFn, valueFmt) -> rows` — builds
    `renderStackedBarSection` rows from a `char→{cat→mag}` matrix: per-char total via
    `_charStackSegments`, `rowMax` = largest char total, each segment `frac = mag/rowMax` and
    `color = colorFn(key)` (with `key == "__OTHER__"` → `NEUTRAL`), `label = shortChar(char)`,
    `labelColor = classColor(byCharMap[char] and byCharMap[char].classFile)`,
    `value = valueFmt(total)`. Rows sorted by total desc, then char asc. Uses `MAX_STACK_SEGS = 9`.

- [ ] **Step 1: Write the failing tests.** Append to `tests/test_analytics.lua`:

```lua
test("Analytics._charStackSegments: keeps all when within cap", function()
  local segs, total = NS.Analytics._charStackSegments({ KILL = 3, QUEST = 1 }, { "KILL", "QUEST" }, 9)
  assertEqual(total, 4)
  assertEqual(#segs, 2)
  assertEqual(segs[1].key, "KILL"); assertEqual(segs[2].key, "QUEST")   -- catOrder order
end)
test("Analytics._charStackSegments: collapses overflow into __OTHER__", function()
  local mags, order = {}, {}
  for i = 1, 12 do local k = "C" .. i; mags[k] = 13 - i; order[#order + 1] = k end  -- C1 biggest
  local segs, total = NS.Analytics._charStackSegments(mags, order, 9)
  assertEqual(total, 12 + 11 + 10 + 9 + 8 + 7 + 6 + 5 + 4 + 3 + 2 + 1)   -- 78
  assertEqual(#segs, 9)                    -- 8 kept + 1 OTHER
  assertEqual(segs[#segs].key, "__OTHER__")
  assertEqual(segs[#segs].mag, 4 + 3 + 2 + 1)  -- the 4 smallest (C9..C12)
end)
```

- [ ] **Step 2: Run, verify fail.** `lua tests/run.lua` → FAIL.

- [ ] **Step 3: Implement the helpers.** In `modules/Analytics.lua` (near the other pure helpers).
  Add `local MAX_STACK_SEGS = 9` (matches the `makeStackedBar` texture pool).

```lua
-- Reduce a character's per-category magnitudes to at most maxSegs stacked segments: keep the top
-- (maxSegs-1) by magnitude, lump any remainder into a single "__OTHER__" segment, then order the
-- kept segments by their global rank in catOrder ("__OTHER__" always last). Pure + testable.
function Analytics._charStackSegments(catMags, catOrder, maxSegs)
  local list, total = {}, 0
  for k, v in pairs(catMags) do if v and v > 0 then list[#list + 1] = { key = k, mag = v }; total = total + v end end
  table.sort(list, function(a, b) if a.mag ~= b.mag then return a.mag > b.mag end return tostring(a.key) < tostring(b.key) end)
  local kept, otherMag = {}, 0
  if #list > maxSegs then
    for i = 1, maxSegs - 1 do kept[#kept + 1] = list[i] end
    for i = maxSegs, #list do otherMag = otherMag + list[i].mag end
  else
    for i = 1, #list do kept[#kept + 1] = list[i] end
  end
  -- order kept by global rank
  local rank = {}
  for i, k in ipairs(catOrder) do rank[k] = i end
  table.sort(kept, function(a, b) return (rank[a.key] or math.huge) < (rank[b.key] or math.huge) end)
  if otherMag > 0 then kept[#kept + 1] = { key = "__OTHER__", mag = otherMag } end
  return kept, total
end

-- Build renderStackedBarSection rows from a char→{cat→mag} matrix.
function Analytics._buildCharStackRows(matrix, byCharMap, catOrder, colorFn, valueFmt)
  local rows = {}
  local rowMax = 1
  local totals = {}
  for ch, mags in pairs(matrix) do
    local _, total = Analytics._charStackSegments(mags, catOrder, MAX_STACK_SEGS)
    totals[ch] = total
    if total > rowMax then rowMax = total end
  end
  for ch, mags in pairs(matrix) do
    local segs = select(1, Analytics._charStackSegments(mags, catOrder, MAX_STACK_SEGS))
    local segments = {}
    for _, s in ipairs(segs) do
      local color = (s.key == "__OTHER__") and NEUTRAL or (colorFn(s.key) or NEUTRAL)
      segments[#segments + 1] = { frac = s.mag / rowMax, color = color }
    end
    local classFile = byCharMap[ch] and byCharMap[ch].classFile
    rows[#rows + 1] = { label = shortChar(ch), labelColor = classColor(classFile),
      value = valueFmt(totals[ch]), segments = segments, _total = totals[ch] }
  end
  table.sort(rows, function(a, b)
    if a._total ~= b._total then return a._total > b._total end
    return a.label < b.label
  end)
  return rows
end
```

  (`renderStackedBarSection` already honors `row.labelColor` after Task 4 Step 6.)

- [ ] **Step 4: Run helper tests.** `lua tests/run.lua` → new tests PASS.

- [ ] **Step 5: Add the 7 headers.** In `BuildCharts`, add after the relevant existing headers:

```lua
    charBySource     = sectionHeader(content, "Loot by Character \195\151 Source"),
    charValueSource  = sectionHeader(content, "Value by Character \195\151 Source"),
    charQuality      = sectionHeader(content, "Quality by Character"),
    charType         = sectionHeader(content, "Item Type by Character"),
    charBound        = sectionHeader(content, "Bound by Character"),
    charKeystone     = sectionHeader(content, "Keystone by Character"),
    charConf         = sectionHeader(content, "Confidence by Character"),
```

- [ ] **Step 6: Add the 7 pools + release entries.** In `self.pool` add seven
  `chsource/chvsource/chquality/chtype/chbound/chkeystone/chconf = { free = {}, active = {} },`
  entries, and add those seven names to the `for _, name in ipairs({...})` release loop in
  `LayoutCharts` (and the `curcharlegend` from Task 5).

- [ ] **Step 7: Render each companion right below its parent.** In `LayoutCharts`, immediately after
  each parent `renderBarSection`/quality-mix block, insert the companion. Color functions per chart:

```lua
  -- after Loot by source (~677):
  y = self:renderStackedBarSection(P.chsource, H.charBySource,
    Analytics._buildCharStackRows(stats.charBySource, stats.byChar,
      charSourceOrder, function(k) return SOURCE_COLOR[k] or NEUTRAL end,
      function(t) return tostring(t) end), y, w, pad)
```

  where `charSourceOrder` is the global source order (reuse `sortedByCount(stats.bySource)` mapped to
  keys). Build each order array once from the parent's own sorted data:
  - Source / Value-source: `keys of sortedByCount(stats.bySource)` → color `SOURCE_COLOR`.
    Value-source `valueFmt = money`.
  - Quality: order `= {0..8 present, ascending}`; color `qualityColor`; `valueFmt = tostring`.
  - Item type: `keys of sortedByCount(stats.byType)`; color `function() return {0.5,0.7,0.9} end`
    (match the parent's fixed type color at ~727); `tostring`.
  - Bound: `BOUND_ORDER`; color `function(k) return BOUND_COLOR[k] or NEUTRAL end`; `tostring`.
  - Keystone: keys of `stats.byKeystone` sorted desc; color `function() return SOURCE_COLOR.MPLUS end`
    (match parent ~800); `tostring`.
  - Confidence: `{ "CERTAIN", "INFERRED" }`; color `function(k) return CONF_COLOR[k] end`; `tostring`.

  Each companion uses the SAME color lookup as its parent so segments match the parent bars.
  A companion with an empty matrix renders nothing (`renderStackedBarSection` hides on `#rows == 0`).

- [ ] **Step 8: Update `HideAllCharts`.** It iterates `self.headers` generically (~604), so the 7 new
  headers hide automatically. No change needed. Verify the empty-range path still hides everything:
  `grep -n "charBySource\|charValueSource\|charQuality" modules/Analytics.lua`.

- [ ] **Step 9: Run tests + lint.** `lua tests/run.lua` (all pass) and `luacheck modules/Analytics.lua`.

- [ ] **Step 10: Leave in working tree; stop for review.**

---

### Task 8: Wire Task 5's render (if stubbed) + full integration pass

**Files:**
- Modify: `modules/Analytics.lua` (only if Task 5 Step 5 was stubbed pending Task 7).

- [ ] **Step 1:** Ensure the Currency-by-Character×Type render (Task 5 Step 5) now calls the real
  `Analytics._buildCharStackRows`. Confirm `curcharlegend` pool exists and is released.
- [ ] **Step 2:** Full run: `lua tests/run.lua` (all green) and `luacheck .` (0 errors across the
  repo).
- [ ] **Step 3:** Sanity grep — no dangling refs:
  `grep -n "currencyBySrc\|curbysrc\|H.currencyBySource" modules/Analytics.lua` → empty.
- [ ] **Step 4: Leave in working tree; stop for review.**

---

### Task 9: Docs, badge sync, smoke tests

**Files:**
- Modify: `docs/browser.md`, `docs/data-model.md`, `docs/test-cases.md`, README (`tests` badge),
  `docs/smoke-tests.md`.

- [ ] **Step 1: `docs/browser.md`** — remove the "Currency by Source" chart row (~138); rename the
  "Currency by character" row (~140) to "Currency by Character × Type" with source
  `currencyCharMatrix` + per-currency color legend; add 7 rows for the "… by Character" companions
  (matrix `charBySource`/etc, stacked, parent colors). Keep the note that `currencyBySource` still
  feeds the Export "Currency by Source" section.
- [ ] **Step 2: `docs/data-model.md`** — under the Stats section (~137), add `currencyCharMatrix` and
  the 7 `char*` matrices; note `currencyBySource` is now export-only (no dashboard chart).
- [ ] **Step 3: Regenerate the test list** — `lua tests/run.lua --list > docs/test-cases.md`.
- [ ] **Step 4: Update the README `tests` badge** to the new total (`lua tests/run.lua` prints
  "N passed" — use N). Same change as Step 3.
- [ ] **Step 5: `docs/smoke-tests.md`** — add in-game checks: (a) `value`/`richest` headline font
  matches `records`, no overflow/wrap; (b) no "Currency by Source" chart; (c) "Currency by
  Character × Type" stacked + distinct per-currency colors + legend; (d) long labels truncate with
  "…" and hover shows the full name, in BOTH sections; (e) all 7 "… by Character" companions appear
  directly below their parent with matching segment colors.
- [ ] **Step 6: Final verification** — `lua tests/run.lua` (green, count matches badge) and
  `luacheck .` (0 errors).
- [ ] **Step 7: Leave everything in the working tree; report the diff summary + owed in-game smoke.**

---

## Self-Review

**Spec coverage:**
- Headline font → Task 1. ✓
- Delete Currency-by-Source (chart only; aggregation kept for Export) → Task 2 (+ corrected the
  spec's "pending grep" — grep done, Export reads it, aggregation stays). ✓
- Currency by Character × Type + generated per-currency colors → Tasks 3 (color) + 5 (agg+render). ✓
- Truncation + tooltips both sections → Task 4. ✓
- 7 companions → Tasks 6 (7 matrices) + 7 (helper + render). ✓
- Testing / badge / docs / smoke → Tasks 1,3,4,5,6,7 (unit) + Task 9 (docs/badge/smoke). ✓

**Placeholder scan:** Fixture-helper names in Tasks 5–6 (`statsForCurrencyFixture`,
`statsForMixedFixture`) are explicitly flagged "reuse the actual helper in `tests/test_stats.lua`" —
the implementer copies the existing idiom rather than inventing one. No TODO/TBD left.

**Type consistency:** `_charStackSegments` returns `(segments, total)` and `_buildCharStackRows`
consumes it via `select(1, ...)`/multi-assign consistently. `renderStackedBarSection` `labelColor`
support is added in Task 4 (Step 6) before Tasks 5/7 rely on it. Pool keys (`curchar`,
`curcharlegend`, `chsource`…`chconf`) are declared in `self.pool` and added to the release loop in
the same tasks that render them. `currencyCharMatrix` and the 7 `char*` matrices are declared,
accumulated, and returned in Database within Tasks 5/6.

**Ordering note:** Task 5's render depends on Task 7's helper — Task 8 exists to close that if Task 5
is landed stubbed. Recommended execution order: 1, 2, 3, 4, 6, 7, 5, 8, 9 (helpers before the render
that uses them), or 1→9 in order with Task 5's render stubbed until Task 7.
