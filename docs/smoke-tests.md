# Smoke tests

Manual end-to-end smoke tests for **Ka0s Loot History** (v1.2.0). Run before claiming a non-trivial
change works, before tagging a release, and after refreshing `libs/` or bumping `## Interface:`. The
headless harness (`lua tests/run.lua` + `luacheck .`, see [testing.md](testing.md)) covers the pure
logic; everything below can only be verified **in-game** on the live client — **Retail (Midnight
12.0.7 / Interface 120007)**.

Companion docs:

- Headless test harness + what each suite covers: [testing.md](testing.md).
- What each slash verb dispatches to: [slash-dispatch.md](slash-dispatch.md).
- Source-resolution model (how a drop gets its source + confidence): [attribution.md](attribution.md).
- Window/table internals referenced throughout: [browser.md](browser.md).
- Settings panel widgets + the options-ui-§10 scrollbar/button rules: [settings-panel.md](settings-panel.md).

## Conventions

- **`/reload`** is the abbreviation used below for `/console reloadui`.
- **BugSack / BugGrabber** (or the stock Lua error frame, `/console scriptErrors 1`) is the primary
  regression signal — a clean run is "no errors thrown at any point".
- **Chat banner** — every line the addon prints starts with a cyan `[LH]` (`NS.PREFIX`). A line
  missing the banner, or a doubled `[LH][LH]`, is a bug.
- **Slash roots** — `/lh` and `/loothistory` are equivalent; the examples use `/lh`. **Bare `/lh`
  prints the help index** (slash-commands-§4) — it does *not* open the window; use `/lh toggle|show|hide`.
- **"Loot at/above threshold"** means loot an item whose quality is ≥ the `Minimum quality` setting
  (default Common). `CHAT_MSG_LOOT` (self lines only) is the authoritative capture signal — anything
  that produces a "You receive loot:" line is a candidate: mob kills, containers/nodes, vendor buys,
  mail attachments, completed trades, quest rewards, M+ end-chests.
- **"Pass"** lines describe what success looks like; if a step says "should X" and X does not happen,
  the smoke test failed.

## Suite

| # | Area | Surfaces | Scenario |
|---|------|----------|----------|
| 1 | Cold load | TOC load order, `OnInitialize`/`OnEnable`, help printer | [Fresh install + first login](#1-fresh-install--first-login) |
| 2 | Window | standalone-windows frame, ESC, position/size/scale persistence | [The history window](#2-the-history-window) |
| 3 | Capture + attribution | `CHAT_MSG_LOOT`, gates, source stamping | [Capture + source attribution](#3-capture--source-attribution) |
| 4 | Gates | Quality threshold, quest-item gate, source mute | [Collection gates](#4-collection-gates) |
| 5 | History table | Filter / sort / group / search / row actions | [History table operations](#5-history-table-operations) |
| 6 | Saved view | Save / Reset / Clear, character scope | [Saved view + character scope](#6-saved-view--character-scope) |
| 6a | Export | Tab-aware CSV copy window, All Data / Current View | [Export](#6a-export) |
| 7 | Insights | Shared filter scope, cards, breakdowns | [Insights tab](#7-insights-tab) |
| 8 | Test mode | Synthetic dataset drives both tabs | [`/lh test` synthetic preview](#8-lh-test-synthetic-preview) |
| 9 | Settings panel | Schema widgets ↔ CLI parity | [Settings panel + CLI parity](#9-settings-panel--cli-parity) |
| 10 | Panel chrome | options-ui-§10 scrollbar + paired buttons, confirm dialogs | [Panel chrome + confirm dialogs](#10-panel-chrome--confirm-dialogs) |
| 11 | Minimap | LibDBIcon show/hide, click actions | [Minimap button](#11-minimap-button) |
| 12 | Debug console | `/lh debug` window + session-only logging | [Debug console](#12-debug-console) |
| 13 | Retention | `PruneOld` on login + onChange | [Retention prune](#13-retention-prune) |
| 14 | SavedVariables | `schemaVersion` after logout | [SavedVariables integrity](#14-savedvariables-integrity) |
| 15 | Debug console coverage | Tag inventory + coalesced-line spam checks | [Debug console coverage](#15-debug-console-coverage) |
| 16 | Blacklist & whitelist | Capture gate (point-in-time) + Filters management UI | [Blacklist & whitelist](#16-blacklist--whitelist) |

---

### 1. Fresh install + first login

**Setup.** Quit WoW. Delete `WTF/Account/<ACCOUNT>/SavedVariables/LootHistoryDB.lua` (and the
`.lua.bak` if present). Confirm the addon is enabled in the character-select AddOns list as **Ka0s
Loot History**.

**Steps.**
- Log in to a character.
- Run `/reload`, then `/lh`.

**Pass.**
- Login and `/reload` complete with **no Lua errors**. Every TOC file loads (locales first, then
  `core/` with Compat first, defaults, then modules with Attribution before Collector, and settings last).
- **Load-order regression check** (the 2026-07-18 TOC reorder, audit LH-13). The TOC section order is
  `Libraries → Locales → Core → Defaults → Modules → Settings`, so `settings/` now loads *after*
  `modules/`. Confirm nothing depends on that having been the other way round: no Lua error on login
  or `/reload`, `/lh` prints the help index (above), and **Ka0s Loot History appears in the Blizzard
  options list** (Esc → Options → AddOns) with its General / Filters / AH Price sub-pages present.
  The headless suite loads in this same order, but the real TOC load path is not unit-testable.
- `/lh` (bare) prints the **help index** — the version line plus one `/lh <cmd> — <desc>` row per
  `NS.COMMANDS` entry (show/hide/toggle/config/version/get/set/list/reset/resetall/debug/test/purge/help — fourteen). Every
  line carries the cyan `[LH]` banner. The window does **not** open.
- `LootHistoryDB` is present on disk after `/reload` with a `global` table holding `history = {}`,
  `settings`, `minimap`, and `schemaVersion = 5`. (The seed value is 1; `NS:RunMigrations` — invoked
  from `InitDB` before any read — applies the v1→v2, v2→v3, v3→v4, and v4→v5 migrations back-to-back
  on a brand-new DB immediately, so the value persisted after the very first init is already 5. The
  v3→v4 currency-quality and v4→v5 currency-bound backfills touch 0 rows here since `history` is
  empty.)
- `/lh list` shows the seeded defaults: `settings.enabled = true`, `settings.qualityThreshold = 1`,
  `settings.retentionDays = 30`, `settings.windowScale = 1`, `settings.excludeQuestItems = true`,
  `settings.excludedSources = table: …` (empty), `minimap.hide = false`.

### 2. The history window

The standalone window follows the Standard's standalone-windows section: a non-secure `CreateFrame`, ESC-closable via
`UISpecialFrames`, with persisted position/size/scale. It is **not** combat-gated.

**Setup.** Any character with the addon loaded.

**Steps.**
- `/lh toggle` (opens), `/lh toggle` (closes).
- `/lh show`, then `/lh hide`.
- `/lh show`, then press **ESC**.
- `/lh show`. Drag the title bar to a new position; drag the bottom-right resize grip to a new size;
  `/lh set windowScale 1.3`.
- `/reload`, then `/lh show`.
- Enter combat (auto-attack a dummy) with the window open; click a row; drag/resize.

**Pass.**
- `toggle` flips visibility; `show`/`hide` are explicit. The window opens at the History tab (the
  last-used tab is remembered within a session).
- **ESC closes the window** (it is registered in `UISpecialFrames`), and any open filter dropdown menu
  closes with it.
- After `/reload`, the window reopens at the **dragged position**, the **resized dimensions** (never
  below the minimum width that fits all columns), and **1.3× scale** — position/size persist in
  `settings.window`, scale in `settings.windowScale`.
- In combat: **no** "Interface action failed because of an AddOn" red error. The window stays fully
  usable (non-secure by design). `/lh config` in combat is the *only* combat-blocked path (see §9).

### 3. Capture + source attribution

The empirical source matrix. Record PASS/FAIL per row; each looted item should appear as a new
**History** row with the expected **Source** and a confidence of `CERTAIN` or `INFERRED`. Only
sources with a live stamper are exercised here — see [attribution.md](attribution.md).

**Setup.** Retail character with bag space; nearby vendor; mail with an item attachment; a trade
partner if available; a quest with an item reward; optionally a M+ keystone.

**Steps (loot, then `/lh show` → History and read the Source column).**

| # | Action | Expected Source | Confidence |
|---|--------|-----------------|------------|
| 1 | Kill a mob and loot the corpse | **Kill** | CERTAIN |
| 2 | Open a chest / lockbox / herb or ore node | **Container** | CERTAIN |
| 3 | Turn in a quest with an item reward | **Quest** | CERTAIN |
| 4 | Buy an item from a vendor | **Vendor** | CERTAIN/INFERRED |
| 5 | Take an item attachment from mail | **Mail** | CERTAIN/INFERRED |
| 6 | Complete a trade that gives you an item | **Trade** | CERTAIN/INFERRED |
| 7 | Loot a Mythic+ end-of-run chest | **Mythic+** | CERTAIN |
| 8 | Spend a bonus/seal roll on a boss kill | **Bonus Roll** | CERTAIN |
| 9 | Win a group need/greed/transmog roll | **Roll** | CERTAIN |
| 10 | Craft an item (any tradeskill "You create") | **Craft** | CERTAIN |
| 11 | Refund a **currency**-paid vendor purchase within the buyback timer (get the currency back) | **Refund** — a `Type=Currency` row for the returned currency | CERTAIN |
| 12 | Loot currency (M+ chest, world quest, PvP, etc.) with **Record currency** on | **Currency** row, `Type=Currency`, source from context | CERTAIN |

**Pass.**
- Rows 1-3 attribute to Kill/Container/Quest. Rows 4-7 record with the listed source (these were the
  F-001 in-client confirmations for VENDOR/MAIL/TRADE via `CHAT_MSG_LOOT`).
- Rows 8/10 attribute from the self-identifying loot line itself (bonus loot / "You create"),
  overriding any stale kill/container context. **Row 11 (Refund)** is confirmed in-client: refunding a
  currency-paid purchase returns the currency on `CHAT_MSG_CURRENCY` as a *"You are refunded: [currency]xN"*
  line (not `CHAT_MSG_LOOT`), so it records as a `Type=Currency` row with `source=Refund`, CERTAIN —
  overriding the stale `VENDOR` stamp from the purchase. With debug on (§12) it logs `[Currency] … src=REFUND`.
  (Refunds that return an **item** are not yet exercised — tracked as a follow-up issue.) §F-009: **Row 9 is the one to
  watch** — the `ROLL` source is stamped from the `LOOT_ROLL_YOU_WON` ("You won:") line that precedes
  the item's receive line. With debug on (§12), confirm a `[Attr] stamp ROLL via roll-won` line
  appears just before the item's `[Loot] … src=ROLL`. If instead the item records as the boss's
  Kill/Container source, the client is emitting the compact "no-spam" roll variant and the ROLL path
  needs a follow-up (see ARCHITECTURE Known limitations).
- Any loot the engine can't attribute falls back to **Source = Other**, confidence `INFERRED` — never
  a Lua error, never a missing row.
- The denormalized columns render correctly: item link (exact tooltip), quality color, iLvl, bound
  glyph (BoE/BoP/Warbound/Warbound-until-equipped), the Vendor and AH price columns, type, zone,
  and the Character column (class icon + class color).
- With debug on (§12), a currency loot logs `[Currency] <name> x<n> id=<id> src=<source>` and adds a
  `Type=Currency` row (blank iLvl/Vendor/AH cells; the Type filter isolates it). Turning
  off **Record currency** stops new currency rows; muting a source stops that source's currency too.
  The Insights tab shows a **Currency** block (top currencies, currency-by-type×source stacked bars,
  currency-by-character×type, currency-over-time). §F-010: verify the currency **category** (SubType) reads
  a real header like "The War Within" — if it's blank, `Compat.CurrencyCategory` couldn't resolve the
  currency-list headers on this client and needs a look.
- **Currency quality (name color + Quality column).** The currency row's **Name** cell is colored by
  its own `C_CurrencyInfo` quality tier (not blank/white), and the **Quality** column shows that
  tier's label — the same rendering the History table already gives item rows. Hovering the row shows
  the **in-game currency tooltip** (`GameTooltip:SetCurrencyByID`), not an item tooltip and not a
  blank tooltip.
- **Currency bound glyph.** The currency row shows a **Bound** lock glyph (not blank): **blue/Warbound**
  for a Warband-transferable currency (tooltip *"Warband Transferable"*, e.g. Timewarped Badge) and
  **green/Bind on Pickup** for a non-transferable one (e.g. Nebulous Voidcore). Captured at loot time
  from `C_CurrencyInfo.isAccountTransferable` (`Compat.CurrencyBound`).
- **v3→v4 backfill.** With currency rows already in history from **before** this change (looted while
  on an older build, so their `quality` is nil), run `/reload`. After reload, those older currency
  rows go from **white/blank Name + blank Quality** to **colored Name + filled Quality** — the
  migration backfilled `quality` in place without adding or removing any rows. (If no pre-change
  currency rows are available, this step can be skipped — see §14 for the schema-stamp confirmation.)
- **v4→v5 backfill (bound).** Same idea for the Bound column: currency rows captured **before** the
  bound change have `bound = nil` (blank/faint-gray glyph). After `/reload`, the v4→v5 migration
  backfills each resolvable currency's bound in place — Warband-transferable → **blue/Warbound**, else
  **green/Bind on Pickup** — with no rows added or removed.

> **Field-confirmed 2026-07-22** (basic flows, in-client): currency capture (`Type=Currency` rows) and
> the currency-vendor **refund → `source=Refund`** flow both verified working. **Still owed:** the new
> **currency bound glyph** at capture + the **v4→v5 bound backfill** (added after this test pass), plus
> the §F-010 currency-category (SubType) resolution and the Insights currency block layout.

### 4. Collection gates

Three independent gates run before a record is written (`Collector:ShouldRecord`).

**Setup.** Open Settings (`/lh config`).

**Steps.**
- **Quality:** set `Minimum quality` to **Rare**. Loot a Common/Uncommon item, then a Rare+ item.
- **Quest items:** leave **Exclude quest items** checked. Loot a Quest-type item (a quest objective
  drop). Uncheck it and loot another Quest-type item.
- **Source mute:** in **Record data from**, uncheck **Kill**. Kill a mob and loot it. Re-check Kill.

**Pass.**
- Below-threshold loot is **dropped** (no row); Rare+ records. With debug on (§12) a `[Drop]` line
  names the reason (`quality`).
- With **Exclude quest items** on, Quest-class items are dropped (`reason=quest`, keyed on the
  locale-independent item class `12`, not the localized type string); unchecking it lets them record.
- With **Kill** unchecked, kill loot is dropped (`reason=source`); re-checking restores capture. The
  mute list offers **every source** — Kill, Container, Mythic+, Bonus Roll, Roll, Quest, Trade, Mail,
  Auction House, Vendor, Disenchant, Milling, Prospecting, Craft, Refund, Other — now that all have a
  live capture path.
- All three gates react **live** to the setting change (upvalues refresh on `SettingsChanged`); no
  `/reload` needed.

### 5. History table operations

**Setup.** A history with a spread of sources, zones, qualities, and characters (or use `/lh test`,
§8). `/lh show` → History tab.

**Steps.**
- **Sort:** click each column header (Date, Time, iLvl, Item, Qty, Quality, Type, SubType, Source, Zone,
  Vendor, Character); click again to flip ascending/descending. The active column shows a sort arrow.
- **Group by:** cycle the **Group by** dropdown through None / Day / Quality / Type / Source / Zone /
  Character. Collapse and expand a group header (left-click).
- **Filters:** exercise each row-2 dropdown — **Date** (single-select: All / Today / Last 7 days /
  Last 30 days), and the multi-select **Bound**, **Quality**, **Type**, **SubType**, **Source**,
  **Zone**, **Character** (pick two values in one, confirm the collapsed label reads "N selected").
- **Zone filter:** open **Zone** in a history that includes a multi-floor dungeon (Halls of Atonement,
  Dire Maul, The Deadmines …). Confirm each zone name appears **exactly once** — the menu keys on the
  name, not `mapID`, so a dungeon's floors no longer list one entry each — and that picking it shows
  every row looted anywhere in that zone. If any row has no captured zone, one **Unknown** entry
  appears and selects exactly those rows.
- **Saved view upgrade:** with a view saved before this change (its Zone filter stored map ids),
  `/reload` and re-open the browser. The Zone dropdown must come back selecting the same zones by
  name (schema v7→v8), never silently unfiltered.
- **Bound filter:** open **Bound** and pick **Not Bound**, then add **Bind on Equip**. The five
  options (Not Bound / Bind on Equip / Bind on Pickup / Warbound / Warbound Until Equipped) match
  the Bound column's header-tooltip legend. Confirm the visible rows' lock colors match the selected states, and that
  **Not Bound** matches rows with no lock.
- **Search:** type into **Search items…**; clear it.
- **Row actions:** right-click a row → context menu (**Link to chat**, **Delete**). Shift-left-click a
  row. Hover a row.

**Pass.**
- Every sort direction and every group mode renders without error; the group order mirrors the column
  order (Day, Quality, Type, Source, Zone, Character).
- Each filter narrows the visible rows; the footer reads **"Showing X of Y"** (bottom-left) and
  updates live as filters change. Multi-select filters combine (intersection with the others).
- The footer's bottom-right reads **"Database ≈ <size>"** (e.g. `≈ 12.4 kB`), right-aligned, matching
  the settings panel's storage estimate. It does **not** change as filters change (it tracks stored
  history, not the filtered view); it updates after looting a new item or deleting a row.
- Search matches item names; clearing it restores the unsearched set.
- Right-click **Delete** removes the row (fires `HistoryChanged`; the table + footer refresh and the
  array is rebuilt dense, no holes). **Link to chat** and **Shift-click** both insert the item link
  into the chat edit box. Hovering shows the item tooltip.

### 6. Saved view + character scope

The saved "view" = group + sort + column filters incl. Bound (NOT the character scope, which is a
session default of "current player"), persisted to `savedView`.

**Setup.** History with loot from **≥2 characters** on the account.

**Steps.**
- Set a distinctive group/sort/filter combination (include a **Bound** selection). Click **Save**.
- Change the filters, then click **Clear**.
- Click **Reset**.
- **Character** dropdown (row-2): open it — the window is scoped to the current player on open. Add a
  second character, then clear back to the current player only.
- `/reload`, `/lh show`.

**Pass.**
- **Save** stores the current group/sort/filters (including Bound) as the account default ("view saved
  as default.").
- **Clear** returns filters/group/sort to the saved view and the character scope to the current player.
- **Reset** drops the saved view back to stock defaults ("view reset to stock defaults.").
- The **Bound selection survives Save → Clear → reload** as part of the view.
- After `/reload`, the window opens on the **saved view + current player**: the Character dropdown's
  collapsed button reads **"Character: Current"** and its menu lights that entry gold. This must hold
  **even on a character with no recorded loot** (the footer reads "Showing 0 of N") — a stale build read
  "Character: All" there, because the character had no data row to build a menu option from. There is no
  longer a Current/All-players toggle — the Character dropdown alone controls scope.

### 6a. Export

**Setup.** A history with a spread of items (or `/lh test`, §8). `/lh show`.

The **Export** button is **tab-aware** (issue #15): it lives in the shared filter bar, and what it
exports depends on which tab is showing.

**Steps (History tab).**
- On the **History** tab, click **Export** (right of row 2). The modal header reads **Export History**.
- Leave the **Data set** dropdown on **All Data** and click **Export to CSV**. Review the copy window;
  press Ctrl+C, Esc.
- Reopen Export, pick **Current View** (apply a filter first so it differs), then **Export to CSV** again.

**Steps (Insights tab).**
- Switch to the **Insights** tab, click **Export**. The modal header reads **Export Insights**.
- Export **All Data** and **Current View** (with a filter applied) to CSV in turn.

**Pass.**
- **History export** — the CSV copy window opens with the loot-row header
  (`ts,date,time,char,classFile,itemID,currencyID,itemName,quality,qualityRaw,itemLevel,bound,vendorPrice,vendorPriceRaw,auctionPrice,auctionPriceRaw,value,valueRaw,auctionSource,itemType,itemSubType,quantity,source,zone,auc_auctionator_minbuyout,auc_tsm_dbmarket,auc_tsm_dbminbuyout,auc_tsm_dbregionmarketavg,auc_tsm_dbregionminbuyoutavg,auc_tsm_dbhistorical,auc_tsm_dbrecent,auc_tsm_dbregionhistorical,auc_tsm_dbregionsaleavg,auc_oribos_market,auc_oribos_region,wowheadLink`)
  and one row per record. `date` reads DD-MMM-YYYY and `time` reads HH:MM; `quality` is a label beside
  numeric `qualityRaw`; `vendorPrice`/`auctionPrice`/`value` read `Ng Ns Nc` beside their copper `*Raw`
  columns (`auctionPrice`/`auctionPriceRaw` blank when no captured price is selectable by the priority
  list); `value` is the derived worth (the higher of the picked auction price and `vendorPrice`);
  `auctionSource` is the picked price's provenance tag (e.g. `tsm:dbmarket`), blank when unpriced; the
  `auc_<provider>_<key>` columns are the raw copper value the addon actually captured for every
  configured price key, independent of which one was picked; `bound` is a friendly label; comma-bearing
  item names are quoted; `wowheadLink` is a `wowhead.com/item=…` URL (with `?bonus=…` when the item has
  bonus IDs). Currency rows carry `currencyID` (and leave `itemID` blank) alongside the same columns as
  item rows. `itemLink`, `sourceDetail`, `mapID`, `subzone`, `confidence` are **not** exported.
- **Insights export** — the CSV instead has the analytics header `Section,Label,Count,Value` and
  mirrors the Insights panel **exactly**: a **Summary** block (records, distinct items, characters,
  value, active days, epic+, best iLvl, richest, date range, busiest day — the KPI cards), then
  **By Source**, **By Character x Source**, **By Quality**, **By Character x Quality**, **By Item Type**,
  **By Character x Item Type**, **By Bound Type**, **By Character x Bound Type**, **By Character**,
  **By Weekday**, **By Hour**, **Top Zones**, **Top Items by Count / Value**, **By Day**, and — when the
  range has currency loot — **Currency Collected** (qty per currency), **Currency by Type x Source**
  (one row per currency × source), **Currency by Character x Type**, and **Currency by Day**. Values
  render `Ng Ns Nc`. The **`… x …`** sections are the per-character companions (`Char / Category` rows;
  the source variant also carries its value). All loot sections are **items-only** (currency counts
  only in its own Currency sections), so a character's total tallies across them. Confirm the export
  has **no** By Keystone, Attribution Confidence, Currency by Source, flat Currency by Character, or
  currency Summary rows — the dashboard dropped those, so the export does too.
- **All Data** covers the whole (visible) history; **Current View** honors the **shared filter** — so
  narrowing the filter bar shrinks *both* the History and the Insights export.
- Text is auto-highlighted; Ctrl+C copies; Esc closes.
- Both the modal and the copy window open **centered on the History window** (not the screen).

### 7. Insights tab

**Setup.** A history spanning several days (or `/lh test`, §8). `/lh show` → **Insights** tab.

**Steps.**
- Adjust the **shared filter bar** (Date dropdown, or any column filter / search).
- Read the stat cards and scroll the breakdown sections.

**Pass.**
- Insights has **no range selector of its own** (issue #13): the shared filter bar scopes **all** cards
  and charts. Changing the Date dropdown, a column filter, or the search box on the Insights tab
  re-scopes the whole view live; switching tabs keeps the same filter, so the History table and the
  Insights charts always show the same slice. The empty state (a filter matching nothing) hides the
  chart sections cleanly instead of erroring.
- The stat cards populate: **records, distinct items, characters, value, active days, epic+
  drops, best drop (ilvl), richest drop, date range, busiest day**. "Value" is the derived worth
  (the higher of the picked auction price and `vendorPrice`) `× quantity` — not raw vendor price alone.
- **Headline font parity.** All KPI card values — including **value**, **richest drop**, **date range**,
  and **busiest day** — render at the **same big size** as **records** / **distinct items** (no card is
  smaller than the others). A long value stays on **one line**: it shrinks just enough to fit the card,
  never wraps or clips off the edge.
- **Smaller coin glyphs.** The gold/silver/copper icons in Insights money strings (value card, richest
  drop, Value By Source, etc.) are **~25% smaller** than before — less chunky next to the text.
- **Bigger, thicker section dividers.** The gold **LOOT** and **CURRENCY** separator titles are **~50%
  larger** and their flanking rule lines **~25% thicker** than the sub-section headers.
- **Title Case + renamed titles.** Every sub-section title is Title Case (e.g. "Loot By Source",
  "Loot By Hour Of Day", "Top Items By Count"). The companions read **"Loot By Character × Source /
  Quality / Item Type / Bound Type"** (and **"Value By Character × Source"**); the quality parent is
  **"Loot By Quality"**.
- The breakdown sections sit under two full-width dividers — a centered gold **LOOT** title, then the
  item charts and ranked lists, then a centered gold **CURRENCY** title. Under **LOOT**, in order:
  **Loot By Character** (now the **first** chart), **Loot By Source**, **Loot By Character × Source**,
  **Value By Source**, **Value By Character × Source**, **Loot By Quality**, **Loot By Character ×
  Quality**, **Loot By Item Type**, **Loot By Character × Item Type**, **Loot By Bound Type**, **Loot By
  Character × Bound Type**, **Loot Over Time**, **Value Over Time**, **Loot By Hour Of Day**, **Loot By
  Weekday**, then **Top Zones / Top Items By Count / Top Items By Value**. Confirm the old **Quality
  mix**, **Mythic+ loot by keystone level**, and **Attribution confidence** charts are **gone** (the
  keystone/confidence data remains in the Export).
- **"… × Character" companions.** Immediately below each of the five categorical loot charts sits its
  matching **stacked** companion — Loot By Character × Source / Quality / Item Type / Bound Type, and
  Value By Character × Source — character on the Y axis, segments reusing the parent chart's category
  colors. A companion with no data hides itself.
- **Colored item-type / weekday / currency bars.** "Loot By Item Type", "Loot By Weekday", and
  "Currency Collected" bars are now **distinctly colored per category** (item type / day / currency),
  not a single flat color. Item-type and currency colors match their × Character companions.
- **Bar-colored labels.** On single-bar charts the row label text is colored to **match its bar**
  (e.g. Loot By Source labels take each source's color). Exceptions keep their own color: Loot By
  Quality (quality color) and per-character bars (class color). Stacked-bar labels are unchanged.
- **Palette + non-adjacency.** Categories without a predefined color (item types, currencies,
  weekdays) draw from a standard **inverse-VIBGYOR** palette assigned by sort rank, so **no two similar
  colors sit next to each other** in a chart or legend (contrast the old look where adjacent
  currencies could be near-identical).
- **Companion segment order.** In each × Character companion the stacked segments run in the **same
  order as the parent chart's Y axis** — e.g. Loot By Character × Bound Type segments follow the same
  order the bars appear in Loot By Bound Type; Value By Character × Source follows the value-desc order.
- **Legends below every categorical chart.** Every single-bar categorical chart (Loot by source, Value
  by source, Quality distribution, Loot by item type, Loot by bound type, Currency Collected) **and**
  every stacked companion now shows a **color-swatch legend** beneath it. Each legend's swatches
  **start at the bars' left edge**, aligned under the bars (not under the text-label column).
- **Legend label truncation.** Long legend labels (e.g. "Artisan Enchanter's Moxie", "Midnight
  Enchanting Knowledge") are **truncated with a "…"** so chips don't overlap; hovering a legend chip
  shows the **full label**.
- **Totals tally (items-only LOOT).** Currency is **excluded** from the LOOT charts, so a character's
  total in **Loot by character** equals the sum of that character's segments in **Loot by Character ×
  Source**, **Bound by Character**, **Quality by Character**, etc. (e.g. if Chopstix reads 384 in Loot
  by character, its Bound-by-Character segments sum to 384). The headline **records** KPI still counts
  currency (so it can exceed the Loot-by-source total); the CURRENCY section carries all currency.
- **Label truncation + tooltips.** In both LOOT and CURRENCY sections, a long row label (currency /
  source / item-type / character name) is **cut to ~16 chars with a "…"** instead of wrapping to a
  second line, and **hovering the row label shows a tooltip with the full name**. Confirm the
  previously clumped 2-line labels (e.g. "Artisan Enchanter's Moxie") now sit on one line.
- **Every tooltip carries its value.** Hover a horizontal bar row, a stacked-bar row, a ranked-list row
  (Top Zones / Top Items / Top by Value) and a bar-section legend chip: each reads
  **"&lt;full label&gt;:  &lt;value&gt;"**, and the value matches the number printed on that row
  (money rows keep their coin glyphs). Check one row whose label is ellipsised and one whose value
  column is clipped — the tooltip must show both in full. The only label-only tooltips are the legend
  chips under the "… by Character" companion charts, which have no single value.
- **Cursor-anchored tooltips.** Every Insights hover tooltip (row labels and segments) appears just
  **above-and-right of the cursor**, not pinned to the row's far-right edge.
- **Per-segment tooltips.** Hovering an individual colored segment of any stacked bar (Character ×
  Source, Currency by Type × Source, Currency by Character × Type, Quality mix, etc.) shows a tooltip
  naming that segment: **"&lt;category&gt;: &lt;value&gt;"** (e.g. "Kill: 45", "Valorstones: 40").
- Loot an item, then a currency (or use `/lh test`, §8, which seeds both) with Insights open on a
  history/filter that includes currency loot: the **CURRENCY** divider appears below **LOOT** (the old
  "Currency — N types — biggest: …" summary line is **gone**), followed by
  **Currency Collected** (one distinctly-colored bar per currency, length = qty, with a legend),
  **Currency by Type × Source** (one *stacked* bar per currency, segments colored by the source it
  came from, with a source **legend** below), and **Currency by Character × Type** (one *stacked* bar per character,
  one segment per currency, **each currency a distinct color**, with a per-currency **legend**
  below), then **Currency over time** (a per-day strip). Confirm the old **Currency by Source** bar
  chart is **gone** and the old flat "Currency by character" bar is **replaced** by the stacked
  Character × Type chart. Narrow the filter to a range with **no** currency loot (e.g. a single day
  before you started collecting currency) and confirm the whole **CURRENCY** block — divider included —
  disappears cleanly while **LOOT** still renders.
- Looting an item with Insights open updates the cards live (the tab reacts to `RecordAdded`).

### 8. `/lh test` synthetic preview

Test mode is session-only and drives **both** tabs (the `ActiveHistory` seam swaps in the synthetic
dataset for Query/Stats/CurrentRecords).

**Steps.**
- `/lh test` (chat prints "test mode on"). `/lh show`.
- Inspect the **History** tab, then the **Insights** tab.
- `/lh test` again (prints "test mode off").
- `/reload`.

**Pass.**
- Test mode on: a bright-red **TEST MODE** badge sits beside the window title; the table fills with
  synthetic rows (spanning several synthetic characters), the filter dropdowns rebuild from the test
  data, and the History view opens on the stock view + **All players** (the test chars differ from the
  current one). Insights reflects the same synthetic dataset.
- Test mode off: the badge clears, the table returns to the **live** history, and the view returns to
  the saved view + Current player.
- After `/reload`, test mode is **off** (it is never persisted).

### 9. Settings panel + CLI parity

Every user setting is a Schema row that drives the AceDB default, the panel widget, and the slash
get/set/list/reset — one write seam (`Schema:Set`). See [settings-panel.md](settings-panel.md).

**Setup.** Open Settings twice-over: `/lh config` **and** ESC → Options → AddOns → **Ka0s Loot
History** (both must land on the same category).

**Steps.**
- Toggle **Enable collection**; run `/lh get settings.enabled`.
- Drag the **Window scale** slider; run `/lh get settings.windowScale`. Then `/lh set windowScale 1.5`
  and watch the slider.
- Change **Minimum quality**, **Keep history for**, and toggle checkboxes in **Record data from** and
  **Hide minimap button** / **Exclude quest items**.
- **Debug console** (Master Controls, on its own row below Enable/Hide-minimap): check it — the debug
  console **window** opens; uncheck it — the window hides. Confirm it does **not** change the debug
  **logging** state (`/lh get state.debugConsole` reports window visibility; logging is still governed
  by `/lh debug on|off`). Toggle the window via `/lh debug` (no arg) and the console's own close
  button — the checkbox tracks it. Reload: the checkbox is unchecked (session-only, never persisted).
- `/lh list` — spot-check every panel row is present with its current value.
- `/lh set windowScale 9` (out of range); `/lh set windowScale abc` (non-number).
- `/lh reset settings.qualityThreshold`; `/lh reset settings.excludedSources`.
- Mid-combat (auto-attack a dummy): `/lh config`.

**Pass.**
- Each panel write and each `/lh set` write the **same** value and fire `SettingsChanged`; an open
  panel widget reflects a slash write live, and vice-versa. `/lh get` echoes the stored value.
- `/lh list` enumerates every Schema row (`settings.enabled`, `minimap.hide`, `state.debugConsole`,
  `settings.windowScale`, `settings.qualityThreshold`, `settings.excludeQuestItems`,
  `settings.retentionDays`, `settings.excludedSources`).
- The **Debug console** checkbox reflects the console window's visibility (not the logging flag),
  never persists across a reload, and stays in sync when the window is toggled by `/lh debug` or the
  window's close button.
- Out-of-range numbers clamp to the row's `min`/`max` (windowScale bounds 0.6–1.6); a non-number
  prints "expected a number" and is rejected.
- `/lh reset <path>` returns that one row to its default (deep-copied — resetting
  `settings.excludedSources` never aliases the shared default table, so a later mute doesn't poison
  it).
- Mid-combat `/lh config` prints a one-line "can't open in combat" message and does **not** open the
  panel (the Blizzard category switch is protected); out of combat it opens on the Ka0s Loot History
  category. Both `/lh config` and the ESC → Options path reach it.

### 10. Panel chrome + confirm dialogs

Covers the options-ui-§10 always-shown scrollbar and the un-clipped paired action buttons, plus the two
destructive-action confirm dialogs.

**Setup.** `/lh config` → the panel body.

**Steps.**
- Observe the right-edge vertical **scrollbar** on a page that fits without scrolling.
- Find the **Reset All** button (right of the Window-scale slider) and the **Purge history…** button
  (right of the storage-stats label). Check each button's right border.
- Click **Purge history…** → in the confirm dialog, click **No/Cancel**, then run it again and confirm.
- Click **Reset All** → confirm dialog.
- `/lh purge` from chat.

**Pass.**
- The scrollbar is **always shown**: on a short page the bar renders parked at the top and **grayed /
  disabled** (it does not auto-hide), so the right gutter is always reserved and the body's left/right
  margins **don't jump** between a short and a long subpage.
- **Reset All** and **Purge history…** each draw their **full right border** (not shaved by the scroll
  gutter) and line up cleanly with their left-hand neighbor — no spill past the panel edge
  (`BUTTON_PAIR_REL` pairing via `makePairButton`).
- **Purge history…** raises `KA0S_LOOTHISTORY_PURGE` ("Delete ALL … records? This cannot be undone.");
  Cancel leaves the data intact, Accept wipes history and prints "history purged."
- **Reset All** raises `KA0S_LOOTHISTORY_RESETALL` ("Reset ALL … settings AND delete ALL recorded
  history?"); Accept wipes history **and** restores every setting to default, then refreshes the panel.
- `/lh purge` raises the same purge dialog as the button.

### 11. Minimap button

The LibDataBroker launcher registered through LibDBIcon-1.0. Visibility lives in `minimap.hide`.

**Steps.**
- Locate the minimap button; hover it.
- Left-click it; right-click it.
- Settings → check **Hide minimap button**; uncheck it.
- `/reload`.

**Pass.**
- The tooltip shows "Ka0s Loot History" + a live record count ("N records") + the click hints.
- **Left-click toggles** the history window; **right-click opens Settings**.
- **Hide minimap button** hides the icon immediately; unchecking shows it. The state **persists across
  `/reload`** (LibDBIcon owns the `minimap` table the setting writes).

### 12. Debug console

Session-only logging (`NS.State.debug`, default off, never persisted). The window and the logging flag
are **independent**.

**Steps.**
- `/lh debug` (bare) → the console window toggles open.
- `/lh debug on`; loot something at/above threshold. `/lh debug off`.
- Close the console window, `/lh debug on`, loot again, then `/lh debug` to reopen the window.
- In the console: press **Copy**, then **Clear**; press **ESC**; toggle the header **Debug: ON/OFF**.
- With logging on and the window full of lines: **drag the right-edge scrollbar** up and down, and
  **mousewheel** over the log. Watch the **bottom-right line counter** (`N / 500 lines`) as new lines
  arrive and after **Clear**.
- `/reload`.

**Pass.**
- The right-edge **scrollbar** scrolls the log; dragging the thumb and the mousewheel stay in sync
  (moving one moves the other's position). The thumb sits at the **bottom** when viewing the newest
  line and at the **top** for the oldest. When every line fits, the track is still shown but inert.
- The **bottom status bar** reads `N / 500 lines`, ticking up as lines are captured (capped at 500),
  and resetting to `0 / 500 lines` after **Clear**.
- Bare `/lh debug` toggles the console **window only** (logging flag untouched).
- `/lh debug on` enables logging; loot emits a tagged `<ts> | [Loot] …` line (and gated drops emit
  `[Drop] …`). `/lh debug off` stops logging. Logging runs **even with the window closed** — reopening
  the window shows the lines captured while it was hidden.
- Each state change prints a color-coded chat ack — `[LH] debug logging |cff40ff40ON|r` (green) /
  `|cffff4040OFF|r` (red) — and appends a console line at **both** transitions: `[Debug] logging enabled`
  on enable (immediately followed by the `[Init]` summary, below) and `[Debug] logging disabled` on disable.
- **Copy** opens an editbox of plain text; **Clear** empties the log; **ESC** closes the window; the
  header **Debug: ON/OFF** toggle flips the same session flag as `/lh debug on|off` (same ack + lines).
- After `/reload`, debug logging is back **off** and the console is closed.

### 13. Retention prune

**Setup.** A history containing records older than a short retention window (or edit timestamps via
`/lh test` data plus a short `retentionDays`).

**Steps.**
- Settings → set **Keep history for** to a short value (e.g. 7 days) with older records present.
- Watch the History table / record count.
- `/reload` and wait ~5 seconds after login.

**Pass.**
- Setting a shorter retention fires the row's `onChange` → `PruneOld`, dropping records older than the
  window immediately (rebuild-and-swap, no holes); the table and footer refresh.
- `PruneOld` also runs **~5s after login** (`PLAYER_ENTERING_WORLD` deferred), so stale records are
  pruned on a fresh session even without touching the setting.
- **"Always"** retention keeps everything (no prune). No error at either prune path.

### 14. SavedVariables integrity

**Steps.**
- After playing/looting a session, fully **log out** (character select is enough to flush
  SavedVariables; a full quit is safest).
- Open `WTF/Account/<ACCOUNT>/SavedVariables/LootHistoryDB.lua`.

**Pass.**
- `LootHistoryDB["global"]["schemaVersion"] = 5` — `RunMigrations` (invoked from `InitDB`) applied
  the v1→v2 (strips the retired `viaWhitelist` field), v2→v3 (`sellPrice` → `vendorPrice`), v3→v4
  (backfills currency-record `quality` from `C_CurrencyInfo`), and v4→v5 (backfills currency-record
  `bound` from `C_CurrencyInfo`) migrations and bumped the stamp to 5; re-running it on an already-v5
  DB is a no-op (idempotent).
- `history` is a dense array of loot records (each with the full field set: `ts`, `char`, `classFile`,
  `itemID`, `itemLink`, `quality`, `source`, `confidence`, …); `settings`, `minimap`, and `savedView`
  (if saved) are present. Session-only state (`debug`, `testRecords`) is **absent**.

### 15. Debug console coverage

Confirms every debug tag fires and, critically, that the coalescing seams really emit **one line,
not N** per event. Enable with `/lh debug on`, open the console with `/lh debug`, then:

- Enable debug (`/lh debug on` or the header toggle) → one `[Init]` line **on enable, not at login**
  (the flag is session-only and off at login): `[Init] LootHistory v<ver>, schema v<n>, profile 'Default', <r> records`.
- Loot a threshold item → one `[Loot]`; a sub-threshold item → one `[Drop]`.
- Open a corpse/chest with many slots → exactly one `[Open] LOOT_OPENED N slots -> …`, not N lines.
- Change a setting (panel or `/lh set …`) → exactly one `[Set] <path> = <value>`, no `[Cfg]`.
- `/lh purge` (confirm) → one `[Data] purge-all removed N rows`; delete a row → one `[Data] deleted row @…`.
- Open the browser → `[UI] window shown`; switch to Insights → `[UI] tab -> Insights` + one `[Insights] computed …`.
- Type in the table's search / change group/sort → one `[Table] rendered M/T rows (…)` per change, never per row.
- Add/remove a blacklist or whitelist id (with debug on) → one `[Filters] blacklist=B whitelist=W` line.

### 16. Blacklist & whitelist

Covers the item-id filter lists (issue #14): the capture gate and the Settings ▸ Filters management
UI. This is **point-in-time** filtering — editing either list only changes what happens to *future*
loots; it never touches rows already stored. **Setup:** a real history with at least one repeated item.

**Steps.**
- In the History tab, right-click a row and choose **Blacklist item**. Note the popup's **gold border**.
- Open **Settings ▸ Filters** (`/lh config` → Filters). In the **Blacklist** section, note the item.
- Loot that same item again (or `/lh test` won't help here — use a live drop).
- In the Filters page, click **Remove** on that item, then loot the item once more.
- In the **Whitelist** section, add an item id that would normally be dropped (below your quality
  threshold, or from a muted source), then loot it so a row appears.
- Now **Remove** that id from the whitelist and re-check the History table.
- Add an id to the Blacklist that is already on the Whitelist (or vice-versa).
- Enter garbage (e.g. `abc`) into an add box and submit.
- **Refresh perf (anti-pattern #39):** with a non-trivial blacklist (a dozen+ ids), click away to
  another subcategory and back to **Filters** several times in a row. Then, with the panel closed,
  right-click **Blacklist item** on a History row, and re-open **Filters**.

**Pass.**
- **Blacklist item** (right-click) adds the id to the blacklist, but the **clicked row stays in the
  table** — blacklisting only stops *future* captures; it never hides or deletes what's already
  stored. A chat line confirms "blacklisted …".
- While blacklisted, looting that item records **nothing new** (no new row; a
  `[Drop] … reason=blacklist` line with debug on). Existing rows of that id are unaffected throughout.
- Clicking **Remove** in the Filters page brings **nothing back** — nothing was ever hidden, so there
  is nothing to restore. Looting the item again afterward records normally, confirming the gate is
  lifted for future loots only.
- A **whitelisted** id records **even when it would normally be dropped** (below threshold / muted
  source / quest item) — the new row appears as a normal, plain row.
- **Removing** that id from the whitelist afterward leaves the row(s) it added **exactly where they
  are** — nothing is hidden or deleted. Only *future* loots of that id go back through the normal
  gates (and are dropped again if they don't pass).
- Adding an id to one list **removes it from the other** (an id is never on both). The Filters page's
  two lists update live; each entry shows the item name (or `Item <id>` until the client caches it)
  with a **Remove** button; the empty state reads `(none)`.
- Garbage input is rejected with a chat hint and adds nothing.
- To remove existing rows of a blacklisted (or any) item, use the row's **Delete** action — list
  membership never does this for you.
- The lists are **account-wide** and survive `/reload`; there is **no** blacklist/whitelist option in
  the browser's filter dropdowns (it is core logic, not a user-selectable display filter).
- **Refresh perf:** repeatedly re-opening the Filters tab is **instant** — no per-click stutter or
  freeze even with a long blacklist (the list rebuild is gated to first paint / on-screen edits /
  dirty, per options-ui-§11; re-showing an unchanged page does no AceGUI teardown+rebuild). After a
  right-click **Blacklist item** made while the page was closed, re-opening Filters shows the new id
  (the off-screen change flagged the page dirty, so the next `OnShow` repaints exactly once).

**Currency blacklist.** Separate id-set from the item blacklist/whitelist above (keyed by
currencyID, no currency whitelist). In the History tab, right-click a currency row and choose
**Blacklist currency**. Loot that same currency again — no new row records. Open **Settings ▸
Filters ▸ Blacklisted currencies**; the id appears with its name resolved. Click **Remove** on it,
then loot the currency again — it records normally. Re-add it and use **Clear all** on the
currencies section (confirm popup) — the list empties and future loots of it record again.

### 17. LibKa0s adoption

Four of LibKa0s's five majors are wired here — `Core` (the printer), `DebugLog` (the console),
`Slash` (the dispatcher and CLI) and `Options` (the settings canvas). Everything in this section is
invisible to the headless gate: the degraded install, whether a raw locale key reaches the screen,
and whether anything on the panel moved. See [pending/LEDGER.md](pending/LEDGER.md) LIBKA0S-01
through LIBKA0S-17 for what was adopted and what was declined.

**17a. The degraded install.** Rename `Interface/AddOns/LootHistory/libs/LibKa0s` to
`libs/LibKa0s.off` and `/reload`.

1. **Zero Lua errors.** Not one, at load or after. This is the whole point of the branch.
2. Type `/lh list`. The output must be **complete** — every schema row, grouped, exactly as it reads
   with the library present. (The list is generated from `NS.Schema.Schema`, which the library never
   owned, so a truncated list means a stub answered where it should have deferred.)
3. The **first** line the addon prints carries the notice:
   `[LH] The LibKa0s library is missing from this installation of Ka0s Loot History (expected in
   libs/LibKa0s); running on reduced built-in fallbacks.`
   Print several more lines (`/lh version`, `/lh get settings.enabled`) — the notice must appear
   **exactly once** for the session, not on every line.
4. `/lh debug on` still flips logging (the flag is this addon's, not the library's) and says
   `…, so the debug console window is unavailable.` `/lh config` says
   `…, so the settings panel is unavailable.` Each sentence starts with the **same cause clause**,
   word for word, as step 3 — that is deliberate: a user running several Ka0s addons on a broken
   install should read one explanation, not four.
5. Loot something. It still records — capture never depended on the library.
6. **Rename the folder back** and `/reload` before continuing.

**17b. The `L` trap — no SCREAMING_SNAKE on screen.** This addon passes no locale table to any
descriptor, so every library string should render as English prose. A regression renders the *key*
instead, for every string at once, and only in game.

Walk the whole surface and confirm **not one** all-caps underscored token is visible:

- `/lh` (the help index): the header reads `v1.2.0 — slash commands (/loothistory is an alias for
  /lh)` and each row is a gold `/lh <verb>`, an em dash, a white description — **not** `HELP_HEADER`
  or `UNKNOWN_COMMAND`.
- `/lh list`, `/lh get settings.enabled`, `/lh set settings.enabled maybe` (which must refuse),
  `/lh reset settings.windowScale`, `/lh resetall`.
- `/lh debug` → the console window: the title reads **Loot History — Debug**, the header toggle
  reads **Debug: ON** / **Debug: OFF**, the buttons read **Copy** and **Clear**, the status line
  reads `N / 500 lines`, and the copy window's title reads **Copy log — Ctrl+C, then Esc**.
- **Settings ▸** each of the four pages: the Defaults button reads **Defaults**; every checkbox,
  dropdown and slider label is English.

**17c. Nothing moved (the parity check).** The layout constants and the breadcrumb separator were
already identical to the library's, so **anything that looks different here is the finding**.

1. Open **Settings ▸ Ka0s Loot History**. The landing page shows the logo, the tagline, a **Slash
   Commands** heading and one row per command.
2. **The one deliberate change:** those landing rows now use the same formatter the chat help does —
   **single** spaces around the em dash, the dash no longer white-wrapped, the description white.
   They previously had double spaces and a bare description. Everything else on the page is
   unchanged.
3. Click through **General**, **Filters** and **AH Price**. Each header reads
   `Ka0s Loot History ▸ <Page>` with the gold divider under it and a **Defaults** button top-right.
   The two-column pairing is unchanged: Enable collection | Hide minimap button, then Debug console
   alone, then Window scale | Reset All; then Minimum quality | Keep history for, then Record
   currency | Exclude quest items, then the full-width **Record data from** grid.
4. The scrollbar is present and grayed on a short page, live on a long one, and **the body's right
   edge does not shift** as you click between pages (options-ui-§10).
5. On **AH Price**, click away to another page and back several times. There must be **no freeze** —
   that page's eleven row slots are pooled, and `SetRenderer` is deliberately declined on it for
   exactly this reason (LIBKA0S-15).

**17d. What the library newly fixes.** Three of these never worked before; confirm they do now.

1. **The Settings window's own footer Defaults control.** Open **Settings ▸ Ka0s Loot History ▸
   General**, change **Minimum quality**, then use the Blizzard Settings window's *own* defaults
   control at the bottom (not the header button). It must reset, exactly as the header **Defaults**
   button does. It did nothing before.
2. **The combat guard on the sidebar path.** Enter combat (a target dummy is enough). Open the
   Blizzard **AddOns** list and click **Ka0s Loot History ▸ General** directly. The Settings window
   closes and chat says
   `cannot open settings during combat — Blizzard's category-switch is protected`. Previously only
   `/lh config` was guarded and this path was not. `/lh config` in combat must refuse the same way.
   Leave combat: both work again, and **nothing replays itself** — the panel must not open on its
   own the moment combat drops.
3. **Esc syncs the console checkbox.** Open the console (`/lh debug`), then open **Settings ▸
   General** and confirm **Debug console** is ticked. Close the console with **Esc** (or its **×**),
   then look at the checkbox again — it must now be unticked. It used to stay stale, because only
   the addon's own `Show`/`Hide` synced it.

**17e. The console's own chrome.** As of LibKa0s v1.3.0 this IS the library's style too — the Ka0s
window edge is specified normatively in standalone-windows and `Core.SKIN` carries it, so the
three sibling addons that used to draw a 12px tooltip border now match. Put two Ka0s consoles on
screen at once and they must be indistinguishable. Open `/lh debug` and confirm: the
flat 1px black border with the subtle lighter inner line, the **gold** title, the gray divider under
the title bar — and Core's **thin 18×18 ×** in the top-right, the same one every other Ka0s addon's
console wears. It is deliberately **not** this addon's own 24×24 class-colored glyph: the History
window keeps that one, and these two windows are the library's (standalone-windows — the edge is
shared across every Ka0s window, the close control on a library-drawn window is the library's).
**Copy** and **Clear** sit to its left with an even gap; none of the three overlaps. Check the copy
window (**Copy**) as well — it takes the same ×.

**17f. Destructive verbs still ask.** `reset` is path-scoped and always was here, so nothing lost a
guard — but check both entry points of each destructive action anyway:

- `/lh purge` → confirm popup. Cancel: history intact. **Settings ▸ General ▸ Purge history…** →
  the same popup.
- **Settings ▸ General ▸ Reset All** → the "settings AND history" popup. Cancel: nothing changes.
- **Settings ▸ Filters ▸ Defaults** → the clear-all-filters popup, and each list's own **Clear all**
  → its own popup.
- `/lh resetall` is non-destructive (settings + the id-lists only, history untouched) and correctly
  does **not** ask.

---

## When to run which subset

- **Pre-commit (capture/attribution edits):** 1, 3, 4. Anything touching `modules/Collector.lua`,
  `modules/Attribution.lua`, or `core/Compat.lua` needs the source matrix.
- **Browser / table edits:** 2, 5, 6, 6a, 7, 8. `modules/Browser.lua` / `BrowserTable.lua` /
  `Analytics.lua` / `Export.lua` — the shared filter bar and tab-aware Export cross all of these.
- **Settings / schema edits:** 9, 10, plus §4's mute/quality gates for any new Data-Collection row.
- **Blacklist/whitelist edits:** 16, plus §4 (the capture gate) — `modules/Filters.lua`,
  `modules/Collector.lua`, `settings/Panel.lua`'s Filters page.
- **LibKa0s / library edits:** 17, plus 9, 10 and 12. Anything touching `core/CoreSetup.lua`,
  `core/DebugLogSetup.lua`, `settings/Slash.lua`, `settings/OptionsSetup.lua` or a re-vendor of
  `libs/LibKa0s/` — and **always** 17a, which is the only check that a degraded install still works.
- **Pre-release / TOC bump:** the **entire suite** — the 17 scenarios span every system the addon
  owns. Always finish with the headless gate green: `luacheck .` (0/0) and `lua tests/run.lua` (see
  [testing.md](testing.md)).
- **Debug/logging edits:** 12, 15. Anything touching `NS.Debug` call sites or
  `core/DebugLogSetup.lua` needs the tag-coverage + coalescing checklist — and 17b, since the
  console's strings are the library's now.

If a smoke test fails, capture the offending line from BugSack / the Lua error frame plus the exact
slash sequence that produced it, and file an issue at the tracker referenced in
[README.md](../README.md).
