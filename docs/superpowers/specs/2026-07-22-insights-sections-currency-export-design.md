# Insights Loot/Currency sections + full currency export — design

*Design spec · 2026-07-22 · branch `feature/insights-sections-currency-export`*

## Goal

Reorganise the in-game **Insights** tab into two clearly divided sections — **Loot** and
**Currency** — augment the Currency section with better charts, and propagate the currency changes
through **both** data exports (Insights CSV and the full **Export to AI** report, closing the
long-deferred `TODO(currency-ai)`).

Purely additive/reorganising: no capture, message-bus, or saved-variable schema changes.

## Decisions (ratified with the user)

- **Currency by Source** bar length = **total quantity** summed across currencies (consistent with the
  rest of the currency section, which sums quantity).
- **Shared source palette**: improve the global `SOURCE_COLOR` map to be more distinct (applies to
  "Loot by source" and both currency-source charts alike) and add the two sources currently missing
  from it — **REFUND** and **BONUS_ROLL** (today they fall back to grey).
- **Currency Collected** bars use a **single neutral colour** (a magnitude chart, not per-currency).
- **No** separate "Top currencies" ranked-list panel (the Currency Collected bar chart covers it).
- **Export to AI**: **full** currency support, folded into this spec.

## Non-goals

- No new capture logic, no new record fields (the `bound`/`quality`/`currencyID` currency fields already
  exist). No message-bus changes. No AceDB schema bump.
- No redesign of the loot charts themselves — they are only regrouped under the Loot divider.

---

## Part 1 — In-game Insights (`modules/Analytics.lua`)

### 1a. Section dividers

New local helper `sectionDivider(parent, text)` renders a **centered gold title flanked by horizontal
rule lines**, full content width (the "Slash Commands" separator style). It returns a frame with the
same show/hide/anchor contract as the existing `sectionHeader` so `LayoutCharts` can position it on the
`y` cursor and `HideAllCharts` can hide it.

Two dividers are created in `BuildCharts` and stored on `self` (e.g. `self.lootDivider`,
`self.currencyDivider`).

### 1b. Layout order (single scrolling column, `LayoutCharts`)

```
[ stat cards ]                              (unchanged, above the chart column)
──────────────  LOOT  ──────────────
Loot by source · Value by source · Quality distribution · Quality mix ·
Loot by item type · Loot by bound type · Loot by character ·
Loot over time · Value over time · Loot by hour · Loot by weekday ·
Mythic+ by keystone · Attribution confidence ·
Top items by value / Top items by count / Top zones     ← MOVED up (were rendered last)
────────────  CURRENCY  ────────────        (entire section hidden when no currency)
Currency Collected · Currency by Source · Currency by Type × Source (+ legend) ·
Currency by character · Currency over time
```

The Loot divider renders whenever `stats.totals.records > 0`. The ranked-list panels (Top items by
value / Top items by count / Top zones), currently rendered **after** the currency block, move up to
close the Loot section (before the Currency divider). The Currency divider + all currency charts hide
when `stats.currencyTotals.events == 0`.

### 1c. Currency charts

- **Currency Collected** (replaces the `renderListPanel` list): a `renderBarSection` chart — one bar
  per currency (y-axis), `frac = qty / maxCurrencyQty`, value = amount, **single neutral colour**
  (`NEUTRAL`). Sorted qty desc.
- **Currency by Source** (new): a `renderBarSection` chart — one bar per source, `frac = srcQty /
  maxSrcQty`, value = total qty, coloured from the shared `SOURCE_COLOR`. Data from the new
  `stats.currencyBySource` (see Part 2). Sorted qty desc.
- **Currency by Type × Source** (renamed from "Currency by source"): the existing
  `renderStackedBarSection` (one stacked bar per currency, segments coloured by source), unchanged in
  data. Header text becomes `"Currency by Type × Source"`. A **legend** is rendered directly beneath
  it.
- **Currency by character** / **Currency over time**: unchanged, kept in the section.

The `Currency — N types — biggest: …` highlight text becomes a small grey subtitle line under the
Currency divider (was the block header).

### 1d. Legend

New helper `renderLegend(pool, rows, y, w, pad)` renders a wrap of **colour-swatch + source-label**
entries under the Type × Source chart. Rows = the union of sources present in the currency data, sorted
by total qty desc (same order/colour as Currency by Source, so the two read as one key). Uses a small
frame pool like the other renderers.

### 1e. Palette (`SOURCE_COLOR`)

Redesign the RGB values for distinctness on the dark background and **add `REFUND` and `BONUS_ROLL`**.
Actual colours chosen following the **dataviz** skill's categorical-palette guidance (distinct hues,
adequate separation, readable fills). The set of source keys to cover:
`KILL, CONTAINER, MPLUS, ROLL, BONUS_ROLL, QUEST, TRADE, MAIL, AH, VENDOR, CRAFT, DISENCHANT, MILLING,
PROSPECTING, REFUND, OTHER`.

---

## Part 2 — New stat (`core/Database.lua`, `Database:Stats`)

Add **`currencyBySource`** — a `{ [sourceKey] = totalQuantity }` map, summed across all currencies
(i.e. `Σ_currency currencySourceMatrix[currency][source]`, or accumulated directly during the currency
pass). Pure, unit-tested alongside the existing currency stats. No other stat changes.

---

## Part 3 — Insights CSV (`modules/Export.lua`, `E:InsightsCSV`)

- Rename the existing per-currency×source section label **`"Currency by Source"` →
  `"Currency by Type x Source"`** (rows keep the `"<currency> / <source>"` label form).
- Add a new **`"Currency by Source"`** section from `stats.currencyBySource` (source label → total qty),
  sorted qty desc.
- Currency Collected / Currency by Character / Currency by Day / Summary currency rows: unchanged.

Pure function, extended unit tests.

---

## Part 4 — Export to AI (full currency)

### 4a. `modules/Export.lua`

- `AICSV` **stops dropping currency rows** (remove the `r.currencyID == nil` filter).
- `AI_COLUMNS` **re-includes `currencyID`** (remove it from the exclusion). Drop the `TODO(currency-ai)`
  note.
- Result: the HISTORY CSV handed to the AI now carries currency rows with a populated `currencyID`.

### 4b. `docs/ai-export-guideline.md`

- Add currency to the **data contract**: a currency row has `id = null`, `currencyID` set,
  `type = "Currency"`, `quality` = currency tier, `bound` label applies, and **no** `il`/`v`/`a`/`val`
  (all `null`). Add the `H` key **`cid`** ← `currencyID`.
- State that currency rows are **excluded** from every item worth/KPI/chart and instead drive a
  dedicated **Currency** section.
- Add the new currency INSIGHTS sections to the section list (`Currency Collected`,
  `Currency by Source`, `Currency by Type x Source`, `Currency by Character`, `Currency by Day`).
- Bump the guideline rev line.

### 4c. `docs/ai-export-template.html` (engine JS + sample)

- Add **`cid`** to the `H` row model.
- **Guard every item-centric computation** to skip currency rows (`r.cid != null`): the value/ilvl/
  quality/type/bound charts, top-items, top-zones, and the Σ(val×qty) worth KPIs. `records` still
  counts all rows; item-only KPIs (distinct items, epic+, best iLvl, richest drop) stay item-only.
- Add a **Currency** subsection to the Insights tab mirroring the in-game section: Currency Collected,
  Currency by Source, Currency by Type × Source, Currency by character, Currency by day — computed
  client-side from the currency rows in `H`.
- Render currency rows in the **History table** with blank item-only cells (name coloured by currency
  quality, source/zone/char/qty populated).
- Refresh the shipped **sample `H`** with a couple of currency rows so the template's own sample report
  exercises the currency path.

### 4d. `tools/build_report.py`

- Map the `currencyID` CSV column into `H` as `cid` (null for item rows).
- **Exclude currency rows** from the item cross-checks: distinct items, epic+, best iLvl, richest drop,
  and **Σ(val×qty)** value — currency rows have no value dimension. `records` count includes them.
- Keep PASS/FAIL green; extend the assembler's own tests if it has them.

---

## Testing

- **Headless Lua** (`lua tests/run.lua`): new `currencyBySource` stat test; extended `E:InsightsCSV`
  tests (renamed section + new section); `AICSV` now includes currency rows + `currencyID` column
  (update the item-only assertions). Keep luacheck 0/0.
- **`build_report.py`**: if it has a test harness, add a currency-row fixture and assert the value
  cross-check ignores currency; otherwise a manual assembler run on a currency-bearing export.
- **In-game smoke** (`docs/smoke-tests.md` §7 Insights + §6a Export): the two dividers; every loot chart
  under Loot; the four currency charts + legend under Currency; Insights CSV currency sections; the AI
  export now carrying currency end-to-end (assembler PASS on a currency-bearing export, report shows a
  Currency section).
- **Test inventory + badge**: regenerate `docs/test-cases.md` and bump the README `tests` badge per the
  CLAUDE.md hard rule.

## Docs to update

- `docs/browser.md` and/or `docs/data-model.md`: Insights section reorg + `currencyBySource`.
- `docs/smoke-tests.md`: §7 and §6a as above.
- `docs/ai-export-guideline.md`: as in 4b.

## Phasing (execution)

1. **In-game Insights** — dividers, reorder, currency charts, legend, palette, `currencyBySource` stat
   (+ tests). Independently verifiable in-game.
2. **Insights CSV** — rename + new section (+ tests).
3. **AI `Export.lua`** — currency into HISTORY/AI CSVs (+ tests).
4. **AI report assets** — guideline + template engine + `build_report.py` (the heavy, isolated phase).

Each phase lands green (tests + luacheck) before the next.

## Risks / open points

- **Palette distinctness** with 16 source keys on a dark background is the main visual risk — dataviz
  guidance mitigates; the legend + self-labeled Currency-by-Source bars make colours legible even if two
  hues are close.
- **AI template engine** is the largest, most intricate change (1151-line self-contained HTML). Isolated
  as the final phase; the sample-data refresh + an assembler PASS on a currency export is the gate.
- Summing different currencies into one "Currency by Source" total is intentionally a magnitude view,
  not a like-for-like comparison (ratified).
