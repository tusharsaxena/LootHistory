# Design — Auction-House Price Integration

**Date:** 2026-07-18
**Branch:** `feature/ah-price-integration`
**Issue:** [#8 — Addon interop: integrate with value/upgrade addons](https://github.com/tusharsaxena/LootHistory/issues/8) (AH-value half only; Pawn is out of scope)
**Status:** Approved for planning

## 1. Summary

Ka0s Loot History records vendor sell price (`sellPrice`, copper, per unit) on every
loot record. This feature adds an **auction-house price** snapshot captured at loot time by
reading from installed AH-pricing addons via their public Lua APIs, plus a derived **value**
(auction-price-if-present-else-vendor) used as the headline worth of a drop throughout the UI,
exports, and analytics.

Everything is a **point-in-time snapshot**, consistent with the addon's existing philosophy:
`auctionPrice` is captured at loot and never recomputed; `value` is derived from the two stored
snapshot fields (`auctionPrice`, `sellPrice`).

## 2. Scope

**In scope**

- Read AH price at loot time from a **fall-through cascade** of three addons.
- Store `auctionPrice` (copper, per unit) and `priceSource` (provenance tag) on each record.
- A derived `value = auctionPrice or sellPrice` (per unit), surfaced everywhere.
- New "AH" column in the in-game browser (after vendor).
- Insights analytics switch from vendor value to `value`.
- CSV export gains auction/value/priceSource columns.
- AI export (guideline, `build_report.py`, HTML template, prompt) becomes three-price-type aware.
- User-configurable cascade (enable/disable per addon, priority order, TSM source key) via Schema.
- Tests + docs.

**Out of scope**

- Pawn / upgrade-arrow interop (the other half of issue #8 — separate future work).
- RECrystallize (not on CurseForge; dropped from the cascade).
- Auctioneer (no Midnight 12.0.x build — dead on Retail).
- Backfilling historical AH prices (impossible — old records keep `auctionPrice = nil`).

## 3. Addon research outcome (steps 1–3)

Four AH addons are alive on Midnight 12.0.x with a readable Lua price API; we integrate the
**top three by install base** and exclude RECrystallize.

| Addon | CF downloads (2026-07-18) | Price call | Returns | Freshness |
|---|---|---|---|---|
| Auctionator | ~194.7M | `Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID)` | copper realm min-buyout, or nil | days (cap 21) |
| TSM | ~62.3M | `TSM_API.GetCustomPriceValue(key, itemString)` (`key` default `"dbmarket"`) | copper, or nil+err | none at runtime |
| OribosExchange | ~3.07M | `OEMarketInfo(itemLinkOrID, tbl)` → `tbl.market` (fallback `tbl.region`) | copper, nil field = unknown | `age` (sec), `days` |

All three calls are **synchronous** (they read local addon DBs), so capture needs no async plumbing.

**Cascade order (default):** Auctionator → TSM → OribosExchange — ordered by install base, i.e.
"most likely to be installed, probed first." User-customizable (§7).

**TSM price key (default):** `dbmarket` (smoothed ~14-day market value, widest coverage).
User-customizable to `dbminbuyout`, `dbregionmarketavg`, etc. (§7).

**Semantics caveat (accepted):** the "auction price" meaning varies by source — Auctionator is a
spot **min-buyout**, TSM `dbmarket` and Oribos `market` are **market values**. `priceSource` records
which basis produced each number, so the mix is transparent downstream.

## 4. Data model

New fields on the loot record (`Collector:BuildRecord`, `modules/Collector.lua`):

| Field | Type | Meaning |
|---|---|---|
| `auctionPrice` | number \| nil | AH price in **copper, per unit**, snapshotted at loot. `nil` when no enabled addon returned a price. |
| `priceSource` | string \| nil | Provenance tag: `"auctionator"`, `"tsm:dbmarket"` (key reflects the configured source), `"oribos:market"`. `nil` when no price. |

**`value` is derived, not stored** (open item #1 → derived). A helper
`NS.Util.RecordValue(r) = r.auctionPrice or r.sellPrice` (may be nil if both are nil) is the single
definition of a drop's per-unit worth. Rationale: `value` is fully determined by two already-stored
snapshot fields, so persisting it would be redundant state that can drift, and it would force a data
migration. It still appears as a "value column" everywhere; it is simply computed on read.

**Migration:** none required. Old records have no `auctionPrice` (nil) and therefore
`RecordValue` falls back to `sellPrice` automatically. `schemaVersion` is **not** bumped.

**Export allowlist:** `Database:Export` (`core/Database.lua`) must add `auctionPrice` and
`priceSource` to its explicit field allowlist so they survive export/round-trip.

## 5. Price capture — the cascade

New module **`modules/AuctionPrice.lua`**, published as `NS.AuctionPrice` (follows the module-
publishing pattern; registers its own `NS.NewBusTarget()` if it needs bus messages — it likely does
not, being a pure query helper).

**Public surface**

```
NS.AuctionPrice:Lookup(itemLink, itemID) -> price:number|nil, sourceTag:string|nil
```

**Behavior**

1. If `auction.enabled` is false, return `nil, nil`.
2. Build the ordered list of **enabled** providers, sorted by configured priority.
3. For each provider in order, call its presence-gated shim; the first non-nil price wins and its
   tag is returned.
4. Return `nil, nil` if none produced a price.

**Provider shims** (all in `AuctionPrice.lua`, each presence-gated; open item #2 → new module, not
Compat.lua — Compat stays Blizzard-API-only):

- **Auctionator:** guard `Auctionator and Auctionator.API and Auctionator.API.v1`; call
  `GetAuctionPriceByItemID(callerID, itemID)` (callerID = addon name). Returns copper or nil.
- **TSM:** guard `TSM_API`; `itemString = TSM_API.ToItemString(itemLink)`; then
  `TSM_API.GetCustomPriceValue(configuredKey, itemString)` wrapped in `pcall` (it errors on bad
  input). Returns copper or nil. Tag = `"tsm:<key>"`.
- **OribosExchange:** guard `OEMarketInfo`; call `OEMarketInfo(itemLink, tbl)`; read `tbl.market`,
  fall back to `tbl.region`. Tag = `"oribos:market"` or `"oribos:region"`.

**Capture site:** `Collector:BuildRecord` calls `NS.AuctionPrice:Lookup(itemLink, itemID)` right
after `GetItemExtras`, writing `auctionPrice` and `priceSource` into the record. `itemLink` is
available immediately from `CHAT_MSG_LOOT`; `itemID` is derived as it is today.

## 6. In-game browser (step 6)

`modules/BrowserTable.lua`:

- New `COLUMNS` entry `key = "auction"`, `label = "AH"`, width ~72, `align = "RIGHT"`,
  `valueFn = NS.Util.FormatMoney(r.auctionPrice)`, `sortFn = r.auctionPrice or 0`.
- Inserted **after the `vendor` entry and before the `char` entry** (honors the documented "new
  columns before Character" rule).
- Add `"auction"` to the `NUMERIC_SORT` set (descending-first like vendor).
- The `/lh test` data generator adds a synthetic `auctionPrice` (and a plausible `priceSource`)
  alongside the synthetic `sellPrice`.
- **Window sizing:** the browser window's default width and `minResize`/min-width must grow to
  accommodate the extra ~72px column so the table doesn't clip or force horizontal crowding. Adjust
  wherever the window's size/`SetResizeBounds` (or equivalent) and the default geometry are defined,
  and confirm the saved-geometry carve-out still restores sanely (a user's persisted narrower width
  should be clamped up to the new minimum on load).

The browser shows the **AH** column only (per step 6); `value` is an Insights/export concept.

## 7. Settings (Schema-driven)

All auction settings live on their **own settings sub-page/category** titled **"Auction House
Price"** (or similar), separate from the existing settings groups, so the ~8 new rows don't crowd the
current panel. Implementation must first confirm how the settings panel groups/sub-pages are built
from `settings/Schema.lua` (category/group field, AceConfig `type="group"`, or the panel's own
sectioning) and add the new sub-page through that existing mechanism — not a bespoke one.

New rows in `settings/Schema.lua` (drive AceDB defaults, panel widgets, and slash CLI; all mutations
via `Schema:Set`), grouped under the new sub-page:

- `auction.enabled` — master toggle (default true).
- Per addon (Auctionator, TSM, Oribos): an **enable** toggle (default all true) and a **priority**
  select (1/2/3; defaults 1/2/3 respectively = install-base order).
- `auction.tsmSource` — select of TSM keys (`dbmarket` default; `dbminbuyout`,
  `dbregionmarketavg`, and other common keys).

`AuctionPrice:Lookup` reads these to build the ordered enabled-provider list. Because prices are
snapshotted at loot, changing any of these affects only **future** loots — consistent with the
point-in-time model.

## 8. Insights analytics (step 7)

`core/Database.lua` `Database:Stats` replaces `sellPrice × quantity` with `RecordValue(r) × quantity`
in every rollup: `totalValue`, `valueBySource`, `valueByDay`, `valueByZone`, `byItem.value`,
`byChar.value`, `richestDrop`, `topItemsByValue`.

`modules/Analytics.lua` relabels the vendor-value card and chart headers ("Vendor value by source",
"Vendor value over time", richest, top items by value) to **"value"** wording. Vendor value is no
longer surfaced as its own distinct metric (open item → "replace").

## 9. CSV export (step 8)

`modules/Export.lua` history `COLUMNS`, immediately after `sellPrice`/`sellPriceRaw`:

- `auctionPrice` (formatted `money`) + `auctionPriceRaw` (copper)
- `value` (formatted `money`, via `RecordValue`) + `valueRaw` (copper)
- `priceSource` (string; empty when nil)

`E:InsightsCSV` value rows switch to `RecordValue`-based totals to match Insights (§8).

## 10. AI export (steps 9–10)

- **`docs/ai-export-guideline.md`** — extend the column contract with short keys: `a` (auction,
  copper), `val` (value, copper), `src` (priceSource). Rewrite value-math notes so LLM insights
  compute worth on `val`. Add a "three price types" section: **vendor** = guaranteed sell floor,
  **auction** = market snapshot at loot (may be nil), **value** = best-available worth
  (`auction or vendor`) — and when to use each.
- **`tools/build_report.py`** — map `a`/`val`/`src` in the CSV→JSON row builder; aggregate and
  cross-check on `value` (replacing the vendor aggregate as the headline, keeping vendor available);
  update footer summaries and validation.
- **`docs/ai-export-template.html`** — add the AH column to the history table, switch the value
  tiles and Insights section to `value`, add the new short keys to the sample row objects and COL
  list.
- **`E:AIPrompt`** (`modules/Export.lua`) — embed the updated CSV and add the three-price-type
  framing so the model knows which price to use where.

## 11. Tests & docs (hard rules)

- **New** `tests/test_auctionprice.lua` — cascade order, per-addon enable/disable, priority
  reordering, presence-gating (addon absent → nil), fall-through to next provider, first-hit-wins,
  provenance tag correctness, disabled master toggle.
- **Mocks** — add stub `TSM_API`, `Auctionator.API.v1`, and `OEMarketInfo` to `tests/wow_mock.lua`.
- **Update** `tests/test_stats.lua` (value math via `RecordValue`, incl. mixed auction/vendor/nil
  rows), `tests/test_export.lua` (new header + formatting), `tests/test_browsertable.lua` (AH
  column), `tools/tests/test_build_report.py` (value aggregation/cross-checks).
- Regenerate `docs/test-cases.md` (`lua tests/run.lua --list > docs/test-cases.md`) and bump the
  README `tests` badge count in the same change.
- Run `lua tests/run.lua` and `luacheck .` green before each commit.
- **Docs** — update `docs/data-model.md` (new fields + derived value), `docs/ARCHITECTURE.md`
  (AuctionPrice module, cascade), and record the open-item #2 resolution (third-party integration
  boundaries are outside Compat's scope) in the relevant doc.

## 12. Standards note (deviation rule)

The Compat-firewall rule (`core/Compat.lua` holds every varying/deprecated **Blizzard** API, gated
by `C_*`/global presence) was consulted. Third-party addon APIs (`TSM_API`, `Auctionator`,
`OEMarketInfo`) are a **different category** — external integrations, not WoW API version drift. Per
the user's decision (open item #2), their presence-gated shims live in the new `AuctionPrice` module,
and Compat stays Blizzard-only. This boundary is not currently addressed by the Ka0s Standard; the
resolution is recorded here and in `docs/ARCHITECTURE.md` rather than changing the standard.

## 13. Resolved decisions

| # | Decision | Choice |
|---|---|---|
| Cascade scope | How many addons | Full cascade of top 3 (Auctionator, TSM, Oribos); drop RECrystallize |
| Priority order | Probe order | By install base: Auctionator → TSM → OribosExchange (user-customizable) |
| TSM source | Which key | `dbmarket` default, user-configurable |
| Provenance | Store source? | Yes — compact `priceSource` tag |
| Insights | Replace vs both | Replace vendor value with `value` |
| Open #1 | value stored vs derived | Derived (`NS.Util.RecordValue`) |
| Open #2 | shim location | New `AuctionPrice` module (Compat stays Blizzard-only) |
| Open #3 | field names | `auctionPrice` + `priceSource` |

## 14. Risks / notes

- **Item cache timing:** the AH lookups need `itemLink`/`itemID`, both present at `CHAT_MSG_LOOT`
  time; no dependency on `GetItemInfo` being cached. If a provider's own DB isn't loaded yet it
  simply returns nil and the cascade falls through — graceful.
- **API stability:** Auctionator's `GetAuctionAge…` is outside its documented v1 set; we do **not**
  depend on it (freshness isn't used in the chosen install-base order), so no exposure.
- **Provenance drift:** `priceSource` for TSM embeds the configured key at capture time, so records
  captured under different TSM-key settings remain self-describing.

---

# Revision 2 — Multi-source price capture, configurable selection, vendor rename, template fixes

**Date:** 2026-07-19
**Status:** Approved for planning (supersedes the Rev-1 parts noted below)
**Applies on top of:** the implemented Rev-1 branch `feature/ah-price-integration` (unmerged).

Rev 1 stored a single first-hit auction price (`auctionPrice` number + `priceSource` tag). Rev 2
captures **every** price data point from **every** available addon into a nested map, and makes both
*what is captured* and *which captured value is used* configurable at runtime — reordering the
selection re-picks the entire history/Insights view live. It also renames `sellPrice`→`vendorPrice`,
explodes all captured sub-prices into the CSV, adds gather-time debug, and fixes the AI template's
History table.

## R2.1 Data model

```lua
{
  vendorPrice  = 3737,               -- RENAMED from sellPrice (copper, per unit)
  auctionPrice = {                   -- nested map: provider -> { priceKey -> copper }; nil if none gathered
    auctionator = { minbuyout = 48000 },
    tsm = { dbmarket=50000, dbminbuyout=47000, dbregionmarketavg=52000, dbregionminbuyoutavg=51500 },
    oribos = { market=51000, region=53000 },
  },
  -- priceSource: REMOVED (the shown source is recomputed at read time)
}
```

- **`vendorPrice`** replaces `sellPrice` everywhere (record, capture, stats, export, browser, tests, docs).
- **`auctionPrice`** is a two-level map (provider → priceKey → copper). Only prices actually gathered
  appear; a provider/key absent for an item is simply omitted. `nil` (or empty) when nothing gathered.
- **`priceSource` is dropped.** The "shown" auction price is derived at read time (R2.3).
- **No auctionPrice migration needed** (Rev-1's scalar shape never shipped — branch is unmerged).

## R2.2 Available price data points (research)

Curated capture set per addon and the full menu the capture-config exposes:

| Provider | priceKey | Meaning | In default capture set |
|---|---|---|---|
| `auctionator` | `minbuyout` | realm lowest buyout (its only auction statistic) | ✅ |
| `tsm` | `dbmarket` | smoothed ~14d realm market value | ✅ |
| `tsm` | `dbminbuyout` | last-scan realm lowest buyout | ✅ |
| `tsm` | `dbregionmarketavg` | region market average | ✅ |
| `tsm` | `dbregionminbuyoutavg` | region avg of min-buyouts | ✅ |
| `tsm` | `dbhistorical`, `dbrecent`, `dbregionhistorical`, `dbregionsaleavg` | other realm/region copper prices | ⬜ available, off by default |
| `oribos` | `market` | realm market value | ✅ |
| `oribos` | `region` | region market value | ✅ |

TSM `dbregionsalerate` (decimal) and `dbregionsoldperday` (count) are **not** copper prices and are
excluded from the menu. TSM `dbglobal*` variants exist but are omitted from the default menu.

## R2.3 Selection (read-time `Pick`)

`NS.AuctionPrice:Pick(auctionPriceMap) -> price, tag` walks the configured **priority list of
`provider:key` entries** and returns the first entry present in the map (e.g. `(50000, "tsm:dbmarket")`).

- **Point-in-time data, live selection:** the prices are snapshotted at loot, but *which* one is shown
  follows the current priority setting — reordering the list re-picks every historical row instantly.
- **`value` = the higher of vendor and the picked auction price.** `Pick` chooses *which* auction
  number to use (priority list, unchanged); the final value then takes the **max** of that and
  `vendorPrice`, because an item's auction price can legitimately be *below* its vendor price and the
  drop's worth is the best you could realize:

  ```lua
  function NS.Util.RecordValue(r)
    local a = NS.AuctionPrice:Pick(r.auctionPrice)   -- picked auction price (copper) or nil
    local v = r.vendorPrice                           -- copper or nil
    if a and v then return math.max(a, v) end         -- both present → higher wins
    return a or v                                     -- else whichever exists (or nil)
  end
  ```

  This is the single "value" definition used by Stats / browser / CSV `value` / AI `val` / template
  `rowVal`. (Reads `vendorPrice`; migration guarantees it exists.)

## R2.4 Capture (`AuctionPrice`)

- `NS.AuctionPrice:GatherAll(itemLink, itemID) -> map` queries every **configured-to-capture**
  `provider:key`, presence-gated + pcall-guarded per provider. TSM issues one `GetCustomPriceValue`
  per captured TSM key; Auctionator one call; Oribos one `OEMarketInfo` (yields market+region). Returns
  the nested map (nil/empty when nothing found). Called from `Collector` at loot; result stored on the record.
- Provider capability tables declare each provider's known keys (drives the capture menu + fetch loop).
- Rev-1's `AuctionPrice:Lookup` (first-hit) is replaced by `GatherAll` + `Pick`.

## R2.5 Settings (reworks Rev-1 tasks 4–5)

The Rev-1 rows (per-provider enable, per-provider priority dropdowns, `tsmSource`) are **replaced** by:

- `auction.enabled` — master toggle (kept).
- **Capture set** — a checklist of every known `provider:key`; checked entries are gathered. Default =
  the ✅ set in R2.2. (Schema-backed; rendered on the Auction House Price sub-page.)
- **Computation priority** — an **ordered list of `provider:key` entries**; first present wins in
  `Pick`. Rendered as a custom ordered-list widget (up/down rows) on the sub-page, modeled on the
  existing Filters list UI (AceConfig can't reorder natively). Stored as an array carve-out under
  `NS.db.global.settings.auction` (documented, like `blacklist`/`savedView`).

Only captured keys can meaningfully appear in the priority list; a priority entry whose key isn't
captured simply never matches.

## R2.6 Surfaces

- **In-game browser, Insights, Export-to-AI:** use the single **computed** auction price (`Pick`) and
  `value` (`RecordValue`). Field rename `sellPrice`→`vendorPrice` threads through. (In-game column
  labels/order unchanged in this rev; only the value source changes.)
- **Export-to-CSV (full detail):** columns become `vendorPrice`/`vendorPriceRaw`, computed
  `auctionPrice`/`auctionPriceRaw`, `value`/`valueRaw`, `auctionSource` (picked tag), **plus one raw
  column per captured `provider:key`** (e.g. `auc_tsm_dbmarket`, `auc_oribos_region`). The auction
  sub-columns are **dynamic** — generated from the capture set, sorted deterministically.
- **AI assembler (`build_report.py`):** reads the renamed `vendorPriceRaw` for `v` and the computed
  `auctionPriceRaw`/`valueRaw` for `a`/`val`; the dynamic sub-columns are CSV-only and ignored by the AI.

## R2.7 Debug at loot

Add a debug line at capture logging **every** gathered `provider:key = price` and the `Pick` result
(the selected tag+price), next to the existing `[Loot]` line. Emits only when `NS.State.debug`.

## R2.8 Migration

`schemaVersion` v2 → v3: for each record, `r.vendorPrice = r.sellPrice; r.sellPrice = nil`
(non-destructive rename — no value lost). Idempotent; runs once at init before any read.

## R2.9 AI template (`docs/ai-export-template.html`) fixes

The template's rendered **History browser** tab (screenshot: the "Insights / History browser / What
the data says" report):

1. **Fit the columns:** the current last column overflows the table. Fix by **reducing the table font
   and rebalancing column widths** so all columns fit inside the table (chosen approach — not
   row-wrapping, not resizing the page window).
2. **Time format:** `17 Jul · 12:55` → `17 Jul 12:55` (replace the `·` separator with a space).
3. **"Value" column → "Vendor":** the current last column renders the *computed* value (`rowVal`);
   repoint it to **`vendorPrice`** (via the `v` row key) and rename the header **"Vendor"**.
4. **"AH" column → "Auction".**
5. **Order:** … **Vendor** (second-last), **Auction** (last).

(The hero "Value harvested" total and the Insights charts continue to use the derived value via
`rowVal` — only the two table columns change to show the raw vendor/auction prices.)

## R2.10 Tests & docs

- New/updated unit tests: `GatherAll` (multi-key, presence-gating, pcall), `Pick` (priority order,
  fallthrough, missing-key), capture-config + priority-config plumbing, the v2→v3 migration, the
  dynamic CSV columns, `RecordValue` on the map shape. Update every `sellPrice` test to `vendorPrice`.
- Regenerate `docs/test-cases.md` + README badge; update `docs/data-model.md`, `docs/ARCHITECTURE.md`,
  `docs/ai-export-guideline.md` (the `v` key now comes from `vendorPriceRaw`), `docs/testing.md`.
- **README end-user section (plain language, no internals):** a new user-facing section in `README.md`
  explaining AH pricing — which addons are supported (Auctionator, TSM, OribosExchange), that it reads
  their price data at loot time, how the **priority list** decides which auction price is shown, and
  how the **overall value** is computed (the higher of vendor price and auction price). Written for a
  player, not a developer — no field names, code, or map internals.

## R2.11 Resolved decisions (Rev 2)

| # | Decision | Choice |
|---|---|---|
| Structure | scalar vs map | Nested `provider → key → copper` map |
| Value rule | auction-else-vendor vs max | `value = max(pickedAuction, vendorPrice)` when both exist; else whichever exists |
| Capture set | which keys | Curated default (Auctionator minbuyout; TSM dbmarket/dbminbuyout/dbregionmarketavg/dbregionminbuyoutavg; Oribos market/region); **configurable** |
| Selection | how chosen | Configurable ordered `provider:key` priority list, `Pick` first-present-wins, live |
| priceSource | keep? | Dropped (derived at read) |
| Vendor field | rename? | `sellPrice`→`vendorPrice` + v2→v3 migration |
| CSV | detail | All captured sub-prices as separate dynamic columns; everything else uses computed price |
| Gather scope | present vs enabled | Gather all configured-to-capture keys from present providers |
| Template fit | approach | Shrink table font + rebalance widths |

---

# Revision 3 — AH Price settings UX overhaul + template auction data

**Date:** 2026-07-19
**Status:** Approved for planning
**Applies on top of:** Rev-2 (branch `feature/ah-price-integration`, unmerged).
**Reuse reference:** the user's own `../ConsumableMaster` addon — all row icons there are Blizzard
textures referenced by name (no bundled media), reused here by name.

## R3.1 Settings sub-page rename
"Auction House Price" subcategory → **"AH Price"** (the canvas subcategory display name, the schema
`group` string, the General-skip filter, and the Defaults handler's group check).

## R3.2 Icons (all Blizzard textures, no media copied)
- Up/down arrows: `Interface\ChatFrame\UI-ChatIcon-ScrollUp-Up` / `...-ScrollDown-Up` (fixes the
  broken `▲`/`▼` text glyphs — Friz Quadrata renders them as tofu boxes).
- Data-collected status: green check `Interface\RaidFrame\ReadyCheck-Ready` / red X `...-NotReady`.
- Info: `Interface\FriendsFrame\InformationIcon`, tooltip via `GameTooltip` SetOwner/SetText/AddLine(wrap)
  on OnEnter/OnLeave.

## R3.3 Data Collection section (was the "Capture these prices" MultiCheck)
Rendered as a **custom nested list** (not the stock MultiCheck), grouped by provider display name
(**Auctionator**, **Tradeskill Master**, **Oribos Exchange**), each key a checkbox toggling the
capture set (`settings.auction.capture`), with an **info (i) icon** per key whose tooltip explains the
data point. The capture data stays schema-backed (`settings.auction.capture`, for defaults/slash), but
the panel renders this custom section instead of the MultiCheck widget (the schema row is skipped in
`renderSchema` for the panel and rendered custom).

## R3.4 Priority section
- Heading renamed to **"Priority (top = preferred)"**.
- Each row: `[status ✓/✗]  [Addon Source]  [Data Source]  [▲]  [▼]  [☑ enabled]`:
  - **Two label columns** — addon source (provider display name) and data source (short key label),
    e.g. `Tradeskill Master | Market Value`.
  - **Texture arrows** (R3.2) reordering via the existing `MovePriority`.
  - **Enable checkbox** — include/exclude this entry from selection (new state; see R3.5).
  - **Status ✓/✗** — green check if this entry's source is in the capture set, red X if not (an
    uncollected entry can never win). Read-only, from the capture set.
- A **legend**: `✓ collected   ✗ not collected`.

## R3.5 Data-model addition — priority enable/disable
`settings.auction.priorityDisabled = { [tag] = true }` (default empty; a carve-out alongside
`priority`). `AuctionPrice:Pick` **skips** tags present in `priorityDisabled`. Helpers
`AuctionPrice:IsPriorityEnabled(tag)` / `SetPriorityEnabled(tag, on)`. The ordered `priority` array is
unchanged. The Defaults button clears `priorityDisabled` too.

## R3.6 Explanatory text (per the reference screenshot)
Short intros: **Data Collection** = which prices are recorded on every drop (more = more to compare,
small storage cost); **Priority** = of the collected prices, which one is shown as *the* auction price
(top wins), independent of collection, and only ranks what's collected.

## R3.7 Constants additions
`C.AUCTION_PROVIDER_NAMES = { auctionator="Auctionator", tsm="Tradeskill Master", oribos="Oribos Exchange" }`.
Each `C.AUCTION_KEYS` entry gains `data` (short data-source label, e.g. "Market Value", "Min Buyout")
and `desc` (info-tooltip text explaining the data point).

## R3.8 Template sample auction data
In `docs/ai-export-template.html`'s sample `H` array, for every row whose `b` is `"Not Bound"` or
`"Bind on Equip"`, inject `a = round(v × r)` where r is a random multiplier in [2.0, 10.0] (one
decimal), and `val = max(a, v)` — so the Auction column populates and the report's value/charts reflect
it. Done by a one-off transform script over the rows; other bind types get no `a` (Auction shows "—").
The sample `H` block is not byte-verified by the assembler, so this is safe.

## R3.9 Resolved decisions (Rev 3)
| Decision | Choice |
|---|---|
| Priority enable state | `priorityDisabled` set carve-out; Pick skips disabled |
| Status ✓/✗ meaning | read from capture set (collected vs not) — not new state |
| Icon widgets | Blizzard textures via AceGUI Icon widgets (no ConsumableMaster files ported) |
| Template `a` rows | Not Bound + Bind on Equip only; also set `val = max(a,v)` |
| Priority label | split into Addon Source + Data Source columns |

---

# Revision 4 — AH Price settings UI polish

**Date:** 2026-07-19
**Status:** Approved for planning (batch of visual refinements on the Rev-3 "AH Price" page).
**Note:** all icons remain Blizzard textures (no media). In-game rendering is smoke-tested only, so exact
px values are best-effort and refined during the user's smoke pass.

## R4.1 Data Collection section (`buildAuctionCapture`)
- **Indent** the per-key checkbox rows a little under their provider heading (heading stays flush-left).
- **More vertical spacing above** each provider heading.
- **Info (ⓘ) icon follows the label text** (small gap) rather than sitting in a fixed column — size each
  checkbox to its rendered label width so the icon trails the text.
- **Addon-not-detected:** if a provider's global isn't present (`AuctionPrice:IsProviderAvailable(provider)`
  false), mark its heading "(not installed)", **disable** its checkboxes (non-interactable), and **mute**
  its label fonts — a clear visual that data can't be collected from it.

## R4.2 Priority section (`rebuildPriorityList` / `buildAuctionPriority`)
- **Bring the Data-source column closer to the Addon column:** narrow the Addon column and widen the Data
  column by the same amount so the arrows/enable checkbox keep their position.
- **Column headers** above the list (muted, matching the row columns), with a gap kept to the legend.
- **All sources present, uncollected at the bottom:** the priority list shows **every** `AUCTION_KEYS`
  source. Sources not currently collected (capture off) render at the **bottom**, muted, with no reorder
  arrows (they can never win). Collected sources render on top in priority order with working ▲/▼ that
  reorder among the collected group only.

## R4.3 Data-model / helper additions
- Expand `C.AUCTION_PRIORITY_DEFAULT` to all 11 `AUCTION_KEYS` tags — the 7 default-collected first, the 4
  default-uncollected last.
- `AuctionPrice:IsProviderAvailable(provider)` — true iff that addon's global(s) are present.
- `AuctionPrice:ReconcilePriority()` — ensures the stored `priority` array contains every known tag
  (appends any missing at the end; drops unknown). Called from `GetPriority`/render so all sources always
  appear even after the default expansion (no migration; branch unmerged).
- `AuctionPrice:SwapPriorityTags(tagA, tagB)` — swap two tags' positions in the `priority` array (so the
  partitioned display's ▲/▼ reorder collected sources correctly).

## R4.4 Resolved decisions (Rev 4)
| Decision | Choice |
|---|---|
| #17 completeness | Priority shows all 11 sources; uncollected sink to the bottom (muted, no arrows); collected keep arrows |
| #14 "closer" | Narrow Addon col + widen Data col equally (arrows/enable fixed) |
| #19 not-detected | Heading "(not installed)" + disabled checkboxes + muted fonts |
| Priority default | Expanded to all 11 (default-collected first, default-uncollected last) |
