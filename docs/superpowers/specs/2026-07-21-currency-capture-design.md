# Currency capture — design spec

**Status:** approved design, pre-implementation
**Date:** 2026-07-21
**Branch:** `feature/currency-capture`
**Scope:** capture looted **currency** (not gold) into the account-wide history, surface it in the
History table, Insights, and CSV export. Export-to-AI for currency is explicitly **deferred**.

---

## 1. Goal

Ka0s Loot History records items today. This adds **currency** (Valorstones, crests, Resonance
Crystals, Honor, etc.) as a first-class looted resource, attributed to the same sources, browsable
and exportable alongside items. **Gold is out of scope** for this version (its per-drop volume and
"is-its-own-value" shape are a separate design — see Deferred).

## 2. Decisions (ratified during brainstorming)

- **Currency only, not gold.**
- **Represented with existing columns:** `Type = "Currency"`, `SubType = <live game category>`
  (read from `C_CurrencyInfo`, self-updating each patch). No new `kind` enum.
- **Structural signal:** a new `currencyID` field. `itemID == nil && currencyID ~= nil` is how any
  consumer detects a currency row — never a display-string match.
- **One history array:** currency records live in `global.history` alongside items.
- **Master toggle** `settings.recordCurrency` (bool, **default true**).
- **Gates:** currency obeys the existing **per-source mute list**; it is **exempt** from the item
  min-quality threshold and the quest-item filter. The itemID blacklist simply never matches
  currency (different namespace), so no special-casing.
- **Insights:** currency is **included** in "Loot by source" (a currency loot is a real record), but
  **excluded** from item-centric charts (quality distribution, quality mix, ilvl/best-drop, bound
  type, top-items, distinct-items, value charts) so it can't pollute them.
- **UI scope:** History table + a dedicated Insights currency block + CSV (History + Insights).
- **Export-to-AI: deferred** (see §10).

## 3. Data model

A currency record in `global.history`:

```lua
{
  ts, char, classFile, zone, mapID, subzone,   -- shared, exactly as items
  source, sourceDetail, confidence,            -- shared (attribution reuse)
  currencyID  = 3008,                          -- NEW: the structural signal
  itemName    = "Valorstones",                 -- currency name (reuses the name column)
  itemType    = "Currency",                    -- drives the existing Type filter for free
  itemSubType = "The War Within",              -- live game category, drives SubType filter
  quantity    = 45,                            -- amount looted
  -- itemID / itemLink / quality / itemLevel / bound / vendorPrice / auctionPrice = nil
}
```

Rationale: reusing `itemType`/`itemSubType` means the Browser's self-scoping **Type** and **SubType**
filter dropdowns give "filter to currency" and "group by category" with **zero new UI**. `currencyID`
(not `itemID`) keeps currency out of the item-ID namespace so the blacklist/whitelist can't collide.

## 4. Capture path (mirrors the item path)

1. **Event:** register `CHAT_MSG_CURRENCY` → new `Collector:OnChatMsgCurrency(_, msg)`.
2. **Parse:** new `Util.ParseSelfCurrency(msg)` returns `currencyLink, quantity`. Compiled once from
   `CURRENCY_GAINED` / `CURRENCY_GAINED_MULTIPLE` (plus the `_MULTIPLE_BONUS` / `_MULTIPLE_OVERFLOW`
   parenthetical variants), same anchored-pattern technique as `Util.ParseSelfLoot`. Quantity-bearing
   patterns first (greedy-capture ordering rule).
3. **Resolve:** new Compat shims behind the firewall (Retail-only, presence-gated):
   - `Compat.GetCurrencyInfoFromLink(link)` → `currencyID, name, iconFileID, quantity` via
     `C_CurrencyInfo.GetCurrencyInfoFromLink` / `GetCurrencyInfo`.
   - `Compat.CurrencyCategory(currencyID)` → the currency's list header ("The War Within",
     "Dungeon and Raid", "Player vs. Player", …). Built by scanning the currency-list headers once
     and caching `currencyID → category` per session; falls back to `nil` when unresolved. **This is
     the fiddliest part of the feature.**
4. **Attribute:** reuse `Attribution:Consume()` unchanged — currency fires inside the same loot
   window (`CONTEXT_TTL`), so source/confidence come from the existing context stamp.
5. **Gate + record:** a slimmer currency gate (see §5), then `Database:Add(record)`.

## 5. Gates

Currency uses a currency-aware gate rather than the item `ShouldRecord`:

- `recordCurrency` master toggle off ⇒ drop.
- **Source mute** applies (`excludedSources[source]`).
- **Skip** the quality threshold and the quest-item filter (currency has no quality/classID).
- Blacklist is itemID-keyed ⇒ never matches currency (no special-casing).

The `recordCurrency` flag is cached as a Collector upvalue and refreshed on
`Ka0s_LootHistory_SettingsChanged`, like the other hot-path settings.

## 6. Stats (currency-aware `Database:Stats`)

`Database:Stats(filter)` becomes currency-aware:

- **Item-centric aggregates** (byQuality, quality mix, byBound, byType-as-item, value/valueBySource/
  valueByDay, topItems, topItemsByValue, distinctItems, epicPlus, bestDrop, richestDrop) are computed
  over **item records only** (`currencyID == nil`), so currency can't pollute them.
- **bySource / byDay / byChar / byWeekday / byHour** — a currency loot **counts** as a record in the
  "loot by …" activity charts (currency is genuinely looted). (Currency has no value, so it
  contributes 0 to the value-weighted variants — already handled since `RecordValue` returns nil.)
- **New currency aggregates:**
  - `byCurrency` — `currencyName → total quantity` (per-currency totals; equals the row sums of the
    matrix below).
  - `currencySourceMatrix` — `currencyName → { source → quantity }`: the 2-D per-currency-per-source
    breakdown that drives the stacked chart (§7) and the CSV detail rows (§10).
  - `currencyByChar` — `char → { char, classFile, quantity }`.
  - `currencyByDay` — `dayKey → total currency quantity`.
  - `currencyTotals` — `{ distinct = <count of currency types>, events = <currency record count>,
    biggestHaul = { name, quantity } }`.

## 7. Insights (Analytics)

A currency block, rendered only when the scope contains currency records, reusing the existing pooled
bar/list/strip primitives:

- **Highlight cards:** `distinct currencies`, `biggest haul` (e.g. `Valorstones +500`). (No grand
  total — summing different currencies is meaningless.)
- **Top currencies by quantity** — ranked list (currency name → total quantity).
- **Currency by source (per-currency stacked)** — one horizontal **stacked bar per currency**: bar
  length = that currency's total quantity (relative to the largest currency), segmented and coloured
  by **source** using the same `SOURCE_COLOR` palette as the "Loot by source" chart above (so the
  colours read consistently and no separate legend is needed). This is the per-currency-per-source
  drilldown — one chart shows both how much of each currency you collected *and* where each one came
  from. Reuses the existing `makeStackedBar` / `positionStacked` primitives (today used for the
  quality mix) via a new "stacked bar section" renderer that lays out one stacked bar per row.
- **Currency by character** — bar section, class-coloured, total currency quantity per character
  (the account-wide angle).
- **Currency over time (per day)** — a per-day strip of total currency quantity, normalized to the
  tallest day (reads as *activity*). Respects the shared filter, so narrowing to one currency (e.g.
  name-search "Valorstones") yields a clean single-currency trend; unfiltered shows overall activity.

Deliberately omitted: a grand "total currency" number (meaningless across currencies).

## 8. UI — History table

Currency rows appear automatically. Cell rendering must be **null-safe** for currency:

- Name cell → currency name (optionally its icon); item-only cells (ilvl, bound, quality, value)
  render blank.
- The **Type = Currency** value appears in the existing Type filter (isolate currency); SubType shows
  the category. Bound/Quality filters simply don't offer values for currency (self-scoping).

No new table columns; only null-safety in the existing cell renderers.

## 9. Settings / Schema

One new schema row: `settings.recordCurrency` (bool, default `true`), in the **Data Collection**
group next to `excludeQuestItems`. Flows through `Schema:Set`; appears in the Blizzard panel and the
`/lh` CLI automatically (schema-driven).

## 10. Export

**History CSV (`E:CSV`) — currency rides the same dump:**
- Add a **`currencyID`** column so currency rows are machine-identifiable.
- Make item-only cell functions **null-safe** for currency — in particular the `quality` label must
  render blank (not a misleading "Poor") when `quality` is nil. `value`/`wowheadLink`/price columns
  already blank out for currency.

**Insights CSV (`E:InsightsCSV`) — new flat sections** mirroring §7:
`Currency Collected` (top by qty); `Currency by Source` = one row per **currency × source** pair
(Label = `"<currency> / <source>"`, Count = quantity — the flat serialization of
`currencySourceMatrix`, the drilldown detail); `Currency by Character`; `Currency by Day`
(chronological); plus `Summary` rows for `Distinct currencies` and `Biggest haul`.

**Export-to-AI: deferred.** To keep the AI path byte-for-byte unchanged this version, **exclude
`currencyID` from `AI_COLUMNS`** (same mechanism that already excludes the raw `auc_` columns), so
`E:AICSV` / `E:AIPrompt` output does not change. The AI report engine does not understand currency
rows yet. Leave a `TODO(currency-ai)` marker in `Export.lua` and a one-line backlog note in
`docs/scope.md`.

Both CSVs are produced by the **existing Export modal** buttons (History tab + Insights tab), so no
new export UI.

## 11. Standards / scope

`docs/scope.md` currently lists **currency as explicitly out of scope** ("considered and explicitly
declined"). This design **reverses that decision.** As part of the work, move currency from
"Out of scope" to "In scope" and record the reversal (per the Ka0s deviation rule — a deliberate,
ratified change, not silent). Gold remains explicitly out of scope, now with a pointer to the
deferred design.

## 12. Testing (headless)

The harness has no `C_CurrencyInfo`; Compat shims degrade and are mock-injected via `wow_mock.lua`.

- `Util.ParseSelfCurrency`: single / multiple / `_BONUS` / `_OVERFLOW` lines → link + qty; ignores
  item lines and other players' currency.
- Collector end-to-end: a currency line records a `Type=Currency` / `currencyID` / quantity row with
  source from context; respects the `recordCurrency` master toggle and the source mute; is **not**
  dropped by the quality gate.
- `Database:Stats`: currency **excluded** from quality/ilvl/bound/top-items/value aggregates;
  **included** in bySource/byDay counts; `byCurrency` / `currencySourceMatrix` / `currencyByChar` /
  `currencyByDay` / `currencyTotals` computed correctly (matrix row-sums equal `byCurrency`).
- Schema: `recordCurrency` row exists, defaults true, settable.
- Export: `E:CSV` emits a currency row with `Type=Currency` / `currencyID` / quantity and blank
  item/price/quality cells; `E:InsightsCSV` includes the currency sections — including one
  `Currency by Source` row per currency×source pair — plus summary rows; `E:AICSV` **omits**
  `currencyID` (AI output unchanged).

Update `docs/test-cases.md` (regenerate) and the README test badge in the same change.

## 13. File footprint (approximate)

- `core/Util.lua` — `ParseSelfCurrency` + compiled currency patterns.
- `core/Compat.lua` — `GetCurrencyInfoFromLink`, `CurrencyCategory` (+ cache), presence-gated.
- `core/Constants.lua` — `Type = "Currency"` label constant (if one is needed for consistency).
- `modules/Collector.lua` — `CHAT_MSG_CURRENCY` registration, `OnChatMsgCurrency`, currency gate,
  `recordCurrency` upvalue.
- `core/Database.lua` — currency-aware `Stats` + the five new currency aggregates.
- `modules/Analytics.lua` — currency Insights block (cards + list + per-currency stacked-source
  chart + char bars + over-time strip); a small "stacked bar section" renderer over the existing
  `makeStackedBar` / `positionStacked` primitives.
- `modules/BrowserTable.lua` — null-safe currency cell rendering.
- `modules/Export.lua` — `currencyID` column, null-safe cells, currency Insights CSV sections,
  `AI_COLUMNS` exclusion, `TODO(currency-ai)`.
- `settings/Schema.lua` — `recordCurrency` row.
- `tests/*` + `tests/wow_mock.lua` — new tests + `C_CurrencyInfo` mocks + currency global strings.
- Docs: `scope.md`, `attribution.md`, `data-model.md`, `ai-export-guideline.md` (note only —
  AI deferred), `settings-panel.md`, `smoke-tests.md`, `README.md`, `docs/test-cases.md`.

## 14. Deferred (noted, not built)

- **Gold capture** — high-frequency, is-its-own-value; better as aggregated Insights tallies than
  per-drop rows. Separate design.
- **Export-to-AI for currency** — teach `ai-export-guideline.md` + the HTML report template about
  currency rows, then include `currencyID` in `AI_COLUMNS`. Tracked via `TODO(currency-ai)`.
