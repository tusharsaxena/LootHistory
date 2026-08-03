# Insights Dashboard UX Overhaul — Design Spec

**Date:** 2026-07-25
**Scope:** In-game Insights analytics view only. No export/CSV/AI-report changes.
**Primary files:** `modules/Analytics.lua` (render), `core/Database.lua` (`Database:Stats`
aggregations). No changes to the message bus, schema, or saved variables.

---

## 1. Goals

Five independent UX changes to the Insights dashboard, all requested from in-game screenshots:

1. **Consistent headline font** on the KPI cards — `value` and `richest drop` currently render
   smaller than the rest.
2. **Delete** the "Currency by Source" chart.
3. **Replace** "Currency by character" with **"Currency by Character × Type"** — a per-character
   stacked bar split by individual currency, each currency a distinct color.
4. **Label truncation + hover tooltips** on every text label that can overflow, across **both** the
   Loot and Currency sections. Labels currently wrap to a 2nd line and clump together.
5. **"Character × [Graph]" companions** — for **all 7 categorical Loot bar charts**, add a stacked
   bar immediately below the existing chart, keyed by character on the Y axis, segmented by that
   graph's categories with the graph's existing segment colors.

## 2. Non-goals (YAGNI)

- No changes to strips (over-time / hour / weekday), list panels (top zones/items), or the KPI card
  *values* themselves — only the KPI *font*.
- No new user settings, no persistence, no schema entries.
- No currency-color map in `core/Constants.lua` — currency colors are generated at render time
  (§6.3), not a stored palette.
- No changes to the AI report / CSV export path (`modules/Export.lua`, `tools/build_report.py`).
- "Loot by character" and "Currency by Character × Type" do **not** get their own Character×
  companion (they are already character-keyed).

---

## 3. Current-state reference (grounding)

All line numbers are as of this spec's date.

- **KPI cards:** `CARD_DEFS` at `Analytics.lua:236–247`. Big-number font chosen per-card at
  `Analytics.lua:276`: `def.str and "GameFontNormal" or "GameFontNormalHuge"`. Cards with
  `str = true` (`value` :240, `richest` :244, `date range` :245, `busiest day` :246) get the small
  font. Card text is set in `UpdateCards` (`:314–331`), which never touches font.
- **Simple bar:** factory `makeBar` (`:116–131`), positioner `positionBar` (`:133–143`), renderer
  `renderBarSection` (`:472–496`). Label column width `LABELW = 84`, value column `VALW = 92`
  (`:21`). Label set at `:487` with **no truncation, no tooltip**.
- **Stacked bar:** factory `makeStackedBar` (`:146–161`, 9 segment textures), positioner
  `positionStacked` (`:164–183`, per-segment `SetColorTexture` at `:176`), renderer
  `renderStackedBarSection` (`:502–515`).
- **List rows:** `makeListRow` (`:210–221`, already `SetWordWrap(false)` at :214),
  `renderListPanel` (`:590+`).
- **Section headers** declared in `BuildCharts` (`:407–428`); **widget pools** in `self.pool`
  (`:441–453`); **render order + data binding** in `LayoutCharts` (`:644–960`), whose pool-release
  loop (`:646–650`) enumerates every section key.
- **Color maps:** `SOURCE_COLOR` (`:38–47`, 16-key), `NEUTRAL` (`:23`), `qualityColor()`
  (`:86–90`), `classColor()` (`:79–83`, per-character via `RAID_CLASS_COLORS`), `BOUND_COLOR`
  (`:53–56`), `CONF_COLOR` (`:61`). `shortChar(key)` (`:93`) trims `Name-Realm`→`Name`.
- **Aggregations:** `Database:Stats(filter)` (`Database.lua:218–398`). Existing per-character:
  `byChar` (`:296–306`), `currencyByChar` (`:320–324`). Existing type×source matrix:
  `currencySourceMatrix` (`:314–316`).

---

## 4. Change 1 — Consistent headline font

**Problem:** `value` and `richest drop` carry `str = true` → `GameFontNormal` (~12pt) vs the
`GameFontNormalHuge` (~24pt) used by numeric cards.

**Fix:** These two cards should render at the big Huge size like `records`. But their values are long
money strings with inline coin textures (e.g. `10378🪙 31🪙 57🪙`) that can overflow a quarter-width
card at Huge size.

**Approach — big font + shrink-to-fit guard:**

1. Add a per-card flag `bigStr = true` to the `value` (`:240`) and `richest` (`:244`) defs. Leave
   `date range` (:245) and `busiest day` (:246) as-is — they are the wide bottom-row cards, are much
   longer, and were **not** flagged by the user.
2. At card creation (`:276`), a card that is `def.str` **and** `def.bigStr` gets
   `GameFontNormalHuge` (the big font) instead of `GameFontNormal`.
3. Add a shrink-to-fit helper applied when the card text is set in `UpdateCards`:
   after `num:SetText(...)`, if `num:GetStringWidth() > (cardInnerWidth)`, scale the font down via
   `num:SetFont(file, size * cardInnerWidth / stringWidth, flags)` (read current font with
   `num:GetFont()`), clamped to a sensible floor (≈ the old Normal size). Normal-length values render
   at full Huge size matching the other cards; only an unusually long money string shrinks, and it
   never clips or wraps.
   - `cardInnerWidth` = card width minus a small horizontal padding (cards are anchored
     TOP/LEFT/RIGHT with 6–8px insets; reuse the existing inset constant).

**Testable seam:** extract the shrink math into a pure helper
`Analytics._fitFontSize(stringWidth, maxWidth, baseSize, minSize) -> size` so it can be unit-tested
headlessly without a live FontString.

## 5. Change 2 — Delete "Currency by Source"

Remove all four touch points:

- Header `currencyBySrc` (`BuildCharts`, `:424`).
- Pool `curbysrc` (`self.pool`, `:450`) and its entry in the release loop (`:646–650`).
- The `renderBarSection` call for it in `LayoutCharts` (~`:900–902`).
- Aggregation `currencyBySource` in `Database:Stats` (`:318`) and its entry in the returned table
  (`:381–397`) — **only if** nothing else reads it (verify via grep across `modules/`, `tools/`,
  `tests/`; if the export path reads it, keep the aggregation and only drop the chart). Default
  assumption: it is chart-only and gets removed.

## 6. Change 3 — "Currency by Character × Type" (replaces "Currency by character")

**Replaces** the existing per-character total bar (`currencyByChar`, rendered `Analytics.lua:928–943`)
with a **stacked bar per character**: Y axis = character (`shortChar`), one segment per individual
currency, segment width ∝ that currency's quantity for the character, each currency a distinct color.
A wrapped legend of currency swatches follows (reuse `renderLegend` / `makeSwatch`, `:223–232`,
as "Currency by Type × Source" does at `:921–926`).

### 6.1 Data — new aggregation `currencyCharMatrix`

In `Database:Stats`, alongside `currencyByChar` (`:320–324`), build:

```
currencyCharMatrix[charKey] = { [currencyName] = qty, ... }   -- charKey = "Name-Realm"
currencyCharClass[charKey]  = classFile                        -- for label color (optional)
```

Keep `currencyByChar` too (it still carries per-char totals used for row ordering / the value
column), or derive the row total by summing the matrix — implementer's choice; prefer summing the
matrix to avoid a second pass. Return the new field(s) in the stats table (`:381–397`).

### 6.2 Render

New header `currencyCharType = sectionHeader(content, "Currency by Character \195\151 Type")`
(replacing `currencyChar` at `:426`), new pool key (rename `curchar` → keep the key, repurpose to
stacked). In `LayoutCharts`, replace the old `renderBarSection` currency-by-char block with a
`renderStackedBarSection` call:

- Rows sorted by character total qty desc.
- Each row's `segments` = its currencies sorted by qty desc, `frac = qty / rowMaxTotal`,
  `color = currencyColor(currencyName)` (§6.3).
- Row label = `shortChar(charKey)`, truncated per §7; value = formatted row total.

**Segment cap:** `makeStackedBar` supports **9** segments (`:158–159`). A character may hold more
than 9 currencies. Rule: take the **top 8 currencies by qty**, aggregate the remainder into a 9th
**"Other"** segment colored `NEUTRAL`. This mirrors the existing 9-segment ceiling and prevents
silent truncation. (If raising the ceiling is trivial we may bump the pool to e.g. 12; default is the
top-8 + Other rule to stay within the proven widget.)

### 6.3 Currency colors — generated stable palette

No stored palette. Add a helper `currencyColor(name) -> {r,g,b}`:

- Deterministic hue from the currency **name** (stable across sessions, independent of sort order or
  which currencies are present): hash the name to a float in `[0,1)`, then walk the hue by the
  **golden angle** (0.61803… increments) seeded by the hash so distinct names land far apart on the
  wheel. Fixed saturation/lightness tuned for the dark UI (e.g. S≈0.65, L≈0.60).
- Convert HSL→RGB with a small pure helper `Analytics._hslToRgb(h,s,l) -> r,g,b`.
- Memoize per name in a module-local cache table so a currency keeps one color within a session and
  across every chart that shows it.
- `NEUTRAL` is reserved for the "Other" aggregate segment (§6.2) — the generator must not emit a
  near-neutral gray; the fixed S/L above avoids that.

**Testable seam:** `_hslToRgb` and the name→hue hash are pure and unit-tested (determinism +
distinctness of a few sample names).

## 7. Change 4 — Label truncation + tooltips (both sections)

Applies to every overflow-prone text label: simple-bar labels (`makeBar`), stacked-bar labels
(`makeStackedBar`), and list-row names (`makeListRow`) — in **both** Loot and Currency sections.

### 7.1 Widen the label column

`LABELW = 84 → 108` (`:21`). `VALW` unchanged. `positionBar`/`positionStacked` already derive
`trackW` from `LABELW`, so the track shrinks by 24px automatically; no other geometry edits.

### 7.2 Fixed character cap + ellipsis

- Add module constant `LABEL_MAXCHARS = 16` (final value tuned so 16 chars of the label font fit
  within `LABELW = 108`; if 16 is visibly too wide in-game we adjust the constant — single knob).
- Pure helper `Analytics._truncate(text, maxChars) -> shown, wasTruncated`:
  - If `#text <= maxChars` → return `text, false`.
  - Else return `text:sub(1, maxChars - 1) .. "…"`, `true`. (Uses `…` U+2026, encoded as the UTF-8
    escape `"\226\128\166"` to stay ASCII-safe in source, matching the existing `\195\151` "×"
    convention.)
  - Byte-based `sub` is acceptable: labels are English item/currency/source/character names
    (CLAUDE.md: English only), so multibyte truncation risk is negligible; note it in the code
    comment.
- Every label assignment (`renderBarSection` :487, `renderStackedBarSection`, `renderListPanel`, and
  the new currency/companion renderers) runs the source name through `_truncate` before `SetText`.
  Also set `SetWordWrap(false)` on `makeBar`/`makeStackedBar` labels (list rows already do) so a
  non-truncated-but-still-wide label clips rather than wraps.

### 7.3 Hover tooltip with the full name

Add `OnEnter`/`OnLeave` scripts that show a `GameTooltip` with the **full untruncated** label:

- Add the scripts once in the factories (`makeBar`, `makeStackedBar`) — the strip bars already do
  this at `:199–205`, follow that pattern. Store the full text on the frame each render
  (`bar._fullLabel = row.label`) and read it in `OnEnter`.
- `OnEnter`: `GameTooltip:SetOwner(self, "ANCHOR_RIGHT")`, `AddLine(self._fullLabel, 1, 0.82, 0)`,
  `Show()`. `OnLeave`: `GameTooltip:Hide()`.
- Only meaningful when truncated, but showing it always is harmless and simpler; optionally guard on
  `bar._truncated` to suppress the tooltip for short labels. **Decision: always show** (simplest,
  and confirming the full name on hover is never wrong).
- List rows (`makeListRow`) get the same treatment; they already disable wrap, so only the tooltip +
  `_truncate` are new.

## 8. Change 5 — "Character × [Graph]" companions (7 charts)

For each of the 7 categorical Loot bar charts, render a **stacked bar** directly below the existing
chart: Y = character (`shortChar`), segments = that graph's categories, colors = that graph's
existing per-category colors.

### 8.1 The 7 charts and their category/color source

| # | Existing chart | Stats field today | Category axis | Segment color source |
|---|----------------|-------------------|---------------|----------------------|
| 1 | Loot by source | `bySource` | source | `SOURCE_COLOR` |
| 2 | Value by source | `valueBySource` | source | `SOURCE_COLOR` |
| 3 | Quality distribution | `byQuality` | quality | `qualityColor()` |
| 4 | Loot by item type | `byType` | item type | (existing type color; if none, a stable local map) |
| 5 | Loot by bound type | `byBound` | bound | `BOUND_COLOR` |
| 6 | Keystone | `byKeystone` | keystone | (existing keystone color / `SOURCE_COLOR` fallback) |
| 7 | Confidence | `byConfidence` | confidence | `CONF_COLOR` |

For #2 the segment magnitude is **value** (money), not count; the value column formats money.
For #4/#6, verify the existing renderer's color choice at their current render sites and reuse the
exact same lookup so the companion's colors match the parent chart segment-for-segment.

### 8.2 Data — 7 new `char → {category → magnitude}` matrices

In `Database:Stats`, in the **same record loop** that already builds `bySource`, `byChar`, etc.,
accumulate seven matrices keyed by `charKey`:

```
charBySource[char][srcKey]      += 1                 -- count
charValueBySource[char][srcKey] += itemValue         -- money
charByQuality[char][quality]    += 1
charByType[char][typeKey]       += 1
charByBound[char][boundKey]     += 1
charByKeystone[char][kKey]      += 1
charByConfidence[char][confKey] += 1
```

One extra table-write per record per matrix — negligible cost, single pass, no new iteration over the
dataset. Also stash `charClass[char] = classFile` (already available where `byChar` is built) for the
row label color. Return all seven in the stats table.

**Category ordering within a stacked row:** to keep segment colors readable and the top-N/9-segment
rule consistent, order each row's segments by the **global** category ranking (same order the parent
chart uses), and apply the same **top-8 + "Other"** rule from §6.2 when a character spans more than 9
categories (only realistically possible for source/type). This keeps a given source/quality in a
consistent visual position across character rows.

### 8.3 Render — 7 new sections

For each chart, in `BuildCharts` add a header (e.g. `charBySource = sectionHeader(content,
"Loot by Character \195\151 Source")`), add a pool key in `self.pool`, add it to the release loop,
and in `LayoutCharts` call `renderStackedBarSection` **immediately after** the parent chart's render
block. Titles: "Loot by Character × Source", "Value by Character × Source", "Quality by Character",
"Item Type by Character", "Bound by Character", "Keystone by Character", "Confidence by Character"
(final wording confirmable during review; "× " uses `\195\151`).

Row label = `shortChar` (truncated per §7, with tooltip); label color = `classColor(charClass[char])`
matching "Loot by character". Value column = row total (count, or money for the value chart).

### 8.4 Section length

This roughly doubles the Loot section height (7 extra stacked charts). Accepted by the user.
No lazy-loading / collapsing — charts render as the rest do. If scroll performance is a concern it is
out of scope for this spec (the pane already renders ~20 sections).

---

## 9. Data-model summary (`Database:Stats`)

**Added:** `currencyCharMatrix` (+ optional `currencyCharClass`); `charBySource`,
`charValueBySource`, `charByQuality`, `charByType`, `charByBound`, `charByKeystone`,
`charByConfidence` (+ `charClass`).
**Removed:** `currencyBySource` (§5, pending the grep check).
**Unchanged:** everything else. All additions accumulate inside the existing single record-loop.

## 10. Rendering-model summary (`Analytics.lua`)

**New pure helpers (unit-tested):** `_fitFontSize`, `_hslToRgb`, `currencyColor` (name→color, via
hash+golden-angle+`_hslToRgb`, memoized), `_truncate`.
**New constants:** `LABEL_MAXCHARS = 16`; `LABELW 84→108`.
**Factory changes:** `makeBar` + `makeStackedBar` gain `SetWordWrap(false)` on the label and
`OnEnter`/`OnLeave` full-name tooltips; `makeListRow` gains the tooltip.
**Section wiring:** delete 1 currency section; convert 1 currency section to stacked; add 7 Loot
companion sections — each touching `BuildCharts` (header), `self.pool` (pool), the release loop, and
`LayoutCharts` (render call).

---

## 11. Testing

Headless Lua suite (`lua tests/run.lua`) — WoW frame APIs aren't available headless, so tests target
the **pure helpers and the aggregations**, not FontString/GameTooltip behavior (those are covered by
the in-game smoke test).

New unit tests:

1. `_truncate`: under-cap passes through unchanged; over-cap yields `maxChars` glyphs ending in `…`
   and `wasTruncated = true`; boundary at exactly `maxChars`.
2. `_hslToRgb`: known HSL→RGB conversions (red/green/blue/gray) within tolerance.
3. `currencyColor`: deterministic (same name → same color across calls); distinct sample names →
   visibly different hues; never returns near-`NEUTRAL`.
4. `_fitFontSize`: string within width → base size; string wider than max → scaled size
   proportional and ≥ floor; never exceeds base.
5. `Database:Stats` new matrices: with a small fixture DB, `currencyCharMatrix` and the seven
   `char*` matrices contain the expected per-character breakdown; row totals equal the sum of their
   segments; the top-8+Other rule collapses correctly when >9 categories.
6. Removal: assert `stats.currencyBySource` is gone (or, if kept for export, that the chart no longer
   references it — whichever the grep in §5 dictates).

**CLAUDE.md test-sync rule:** these add cases, so the pass count moves — regenerate
`docs/test-cases.md` (`lua tests/run.lua --list > docs/test-cases.md`) and bump the README `tests`
badge in the **same** change. Run `luacheck .` (0 errors) before commit.

**In-game smoke (owed, per project convention):** verify headline font parity + no overflow;
Currency-by-Source gone; Currency-by-Character×Type stacked + legend with distinct currency colors;
label truncation + hover tooltips across both sections; all 7 Loot companions present below their
parents with matching segment colors. Add to `docs/smoke-tests.md`.

## 12. Standards / risk notes

- **No standards deviation identified.** All changes stay within the existing render/aggregation
  patterns, the closed message bus is untouched, storage is unchanged. If implementation surfaces a
  deviation (e.g. a new color map that ought to live in the standard), flag per CLAUDE.md before
  proceeding.
- **Risk — segment ceiling:** the 9-texture stacked-bar cap is handled by top-8+Other (§6.2/§8.2);
  do not silently drop categories.
- **Risk — `value` card shrink floor:** `_fitFontSize` must clamp to a readable minimum so an extreme
  money string never becomes unreadably tiny; if it hits the floor and still overflows, it clips
  (acceptable, matches other cards' behavior).
- **Risk — performance:** 7 extra matrices are single-pass table writes; 7 extra chart sections add
  layout cost but no new data iteration. Acceptable.
