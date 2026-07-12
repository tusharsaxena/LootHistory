# Ka0s Loot History — Technical Design

**Status:** Draft for v0.1.0 · **Substrate:** Ace3 · **Tier:** 2 (modular)
**Authoritative conventions:** `CLAUDE.md` (repo conventions cheat-sheet) + the Ka0s WoW Addon Standard v1.3.

This document is engineer-facing. It pins down interfaces, event flows, and data shapes. It intentionally avoids full implementations; snippets are signatures / pseudocode.

---

## 1. Architecture overview

Ka0s Loot History records every item the player loots (above a configurable quality threshold), attributes each drop to a **source** (kill, container, mail, trade, AH, quest, vendor, craft, roll, M+ chest…), and presents the data in a standalone browser window with a filterable/sortable/groupable table plus an insights view.

Core architectural commitments:

| Concern | Decision |
|---|---|
| Tier | **Tier 2 modular** — collector, attribution engine, DB, browser, analytics, settings warrant >8 source files. |
| Substrate | **Ace3** — AceAddon/AceDB/AceEvent/AceTimer/AceConsole/AceGUI. |
| Storage scope | **Account-wide** — history + settings live in `LootHistoryDB.global`. A `char` column distinguishes characters. |
| Namespace | Single private `NS` (`local addonName, NS = ...`). No `_G[addonName]`. |
| Settings | **Schema-as-single-source** — one table drives AceDB defaults, panel widgets, slash dispatch, reset. One write seam `Schema:Set`. |
| Inter-module comms | **Closed message bus** — `Ka0s_LootHistory_*` named messages, one sender each. No cross-module table reach. |
| Compat | All deprecated-API calls routed through `core/Compat.lua`. |

### 1.1 Standards notes (no deviations)

Documented here and echoed in `ARCHITECTURE.md`:

1. **Browser is a non-secure standalone window — follows §6A.** It is a plain `CreateFrame("Frame")` (movable/resizable), not a Blizzard Settings canvas and not a secure/protected frame — so it needs **no combat-lockdown gate** on open, per §6A (Standalone windows / data browsers). The *Settings panel* (options) uses the canonical `Settings.RegisterCanvasLayoutCategory` + lazy AceGUI body and **is** combat-gated per §6.2. This addon is §6A's reference implementation.

> **Slash behavior.** Bare `/lh` **prints help** per §7.4; window display is explicit (`/lh toggle`, `/lh show|hide`).

---

## 2. File & load layout

```
LootHistory/
  LootHistory.toc
  core/
    Compat.lua          -- LOAD FIRST. deprecated-API shims, IsRetail/IsClassic, GUID/loot helpers
    Constants.lua       -- SourceType enum, quality names, retention presets, defaults refs
    Namespace.lua       -- bootstrap shared upvalues; NS.L / NS.C aliases seam
    State.lua           -- runtime state: loot context, session flags, message bus handle
    Util.lua            -- pure helpers (time formatting, link parsing, table ops)
    LootHistory.lua     -- AceAddon:NewAddon(NS, ...); OnInitialize/OnEnable
    Database.lua        -- AceDB init, Add/Query/Delete/Export, retention cleanup
  defaults/
    Global.lua          -- G = global defaults table (history[], settings, schemaVersion)
  locales/
    enUS.lua            -- canonical; NS.L metatable fallback
  settings/
    Schema.lua          -- one row per setting; Schema:Set single write seam
    Panel.lua           -- Settings.RegisterCanvasLayoutCategory + lazy AceGUI body
    Slash.lua           -- AceConsole binding; COMMANDS table; get/set/list/reset + verbs
  modules/
    Collector.lua       -- event subscriptions; quality gate; builds & writes records
    Attribution.lua     -- source-resolution engine; stamps & reads the loot context
    Browser.lua         -- window shell: frame, tabs, filter bar, group-by, minimap/LDB
    BrowserTable.lua     -- virtualized pooled-row table: filter→group→sort→render pipeline
    Analytics.lua       -- insights view: source/quality/time breakdowns, top lists
  media/                -- fonts/textures via LibSharedMedia
  README.md  CLAUDE.md  ARCHITECTURE.md  LICENSE
  .luacheckrc  .pkgmeta
  docs/
    REQUIREMENTS.md  TECHNICAL_DESIGN.md  UX_DESIGN.md  EXECUTION_PLAN.md
```

### 2.1 TOC load order (dependency-correct)

```
# core (Compat first)
core\Compat.lua
core\Constants.lua
core\Namespace.lua
core\State.lua
core\Util.lua
core\LootHistory.lua
core\Database.lua
# defaults + locales
defaults\Global.lua
locales\enUS.lua
# settings
settings\Schema.lua
settings\Panel.lua
settings\Slash.lua
# modules
modules\Attribution.lua
modules\Collector.lua
modules\Browser.lua
modules\BrowserTable.lua
modules\Analytics.lua
```

`Attribution.lua` loads **before** `Collector.lua`: the collector reads the context the attribution engine maintains. Both publish idempotent tables (`NS.X = NS.X or {}`) so ordering is robust regardless.

### 2.2 TOC header (key fields)

```
## Interface: 120007
## Title: Ka0s Loot History
## Notes: Records every item you loot, attributes its source, and browses the history.
## Author: add1kted2ka0s
## Version: 0.1.0
## IconTexture: Interface\Icons\inv_holiday_christmas_present_03
## SavedVariables: LootHistoryDB
## DefaultState: enabled
## Category-enUS: Bags & Inventory
## X-License: MIT
```

> No `## OptionalDeps` — all libraries are vendored in `libs/` and loaded from this TOC's
> file list, so there is no external addon to order load against.

---

## 3. Data model

### 3.1 The loot record

One record per **loot event** (not per item type — every acquisition is a row, keyed only by array position). Timestamps and every column are therefore first-class for sort/filter; aggregation is a *view* concern (group-by), never a storage concern.

```lua
-- a single record in LootHistoryDB.global.history[]
{
  ts          = 1752230400,        -- local epoch seconds (server-local via time())
  char        = "Ka0z-Ravencrest", -- "Name-Realm" of the looter
  itemID      = 211296,
  itemLink    = "|cffa335ee|Hitem:211296::::::::80:...|h[Item Name]|h|r",
  itemName    = "Item Name",       -- denormalized for text search / display without cache
  quality     = 4,                 -- numeric Enum.ItemQuality; denormalized for fast filter/sort
  quantity    = 2,
  source      = "KILL",            -- SourceType enum (Constants.SourceType)
  sourceDetail= { npcID = 214506, encounterID = 2902, difficulty = 16 }, -- optional, source-specific
  zone        = "Nerub-ar Palace",
  mapID       = 2657,
  subzone     = "The Hive",        -- optional
  confidence  = "CERTAIN",         -- CERTAIN | INFERRED
}
```

**Denormalization rationale:**

| Field | Why stored explicitly |
|---|---|
| `itemLink` | **Canonical.** Reconstructs the *exact* tooltip (quality, upgrade track, bonus IDs, crafted stats) via `GameTooltip:SetHyperlink(itemLink)`. Never re-derivable from `itemID` alone. |
| `itemID`, `quality`, `itemName` | Denormalized from the link so the browser can sort/filter/search across thousands of rows **without** parsing links or hitting `GetItemInfo` (which can return nil for uncached items). |
| `mapID` | Stable grouping key; `zone` is the human label but localizes/renames. |
| `confidence` | Surfaces attribution uncertainty in the UI and lets the future export flag INFERRED rows. |

### 3.2 Storage shape & schemaVersion

```lua
-- defaults/Global.lua
G = {
  schemaVersion = 1,
  history = {},          -- array of records, append-only within a session
  settings = { ... },    -- see §9; mirrors Schema defaults
  debug = false,
  minimap = { hide = false },  -- LibDBIcon state
}
```

History is a **dense array** appended on each loot. Deletion (retention or manual) compacts via rebuild (see §6.3) to avoid array holes. Records are plain tables — no metatables — so they serialize cleanly for the deferred export.

### 3.3 Schema versioning

`schemaVersion` is a version stamp on the persisted DB; 0.1.0 ships the initial shape (`1`).

The addon is **unreleased**, so no migration runner ships — there are no old saved variables in
the wild to upgrade. Migrations are a **post-release** concern: when the first schema change lands
after release, add a runner in `core/Database.lua`, call it from `OnInitialize` after `InitDB`, and
have it read `schemaVersion` to upgrade older DBs, e.g.:

```lua
-- (post-release) core/Database.lua
-- if g.schemaVersion < 2 then <transform each record> ; g.schemaVersion = 2 end
```

Any field addition/rename to §3.1 bumps `schemaVersion` and adds a block there at that time.

---

## 4. Attribution engine (centerpiece)

WoW exposes **no single "how did this item arrive"** signal. The engine correlates the authoritative *acquisition* event with a short-lived *source context* stamped by peripheral events.

### 4.1 The authoritative signal: `CHAT_MSG_LOOT`

`CHAT_MSG_LOOT` is the reliable "an item entered a bag" event and carries the **item link + quantity**, but **not** the source. The collector:

1. **Self-filters.** Only the player's own loot is recorded. The message text is matched against the localized self-loot global strings, not other players' lines:
   - `LOOT_ITEM_SELF_MULTIPLE` → `"You receive loot: %s×%d."` (quantity capture)
   - `LOOT_ITEM_SELF` → `"You receive loot: %s."` (quantity = 1)
   - Also the *push* variants for items created/received without a loot window: `LOOT_ITEM_PUSHED_SELF_MULTIPLE` / `LOOT_ITEM_PUSHED_SELF` (e.g. crafted, quest, mail-to-bag).
2. **Parses** the item link and quantity from the captured `%s` / `%d`.
3. **Reads the current loot context** (§4.3). If fresh → adopt its source; else → `OTHER`/`INFERRED`.

Global-string→pattern conversion is done once at load (escape `%s`→`(.+)`, `%d`→`(%d+)`) in `Attribution.lua`, not per message.

> A pattern-building helper turns each `LOOT_ITEM_SELF*` global string into an anchored Lua pattern with capture groups, so the parser is locale-correct without hardcoded English.

### 4.2 The primary context source: `LOOT_OPENED` → GUID decode

When a loot window opens, iterate slots and read `GetLootSourceInfo(slot)` → returns `guid, quantity, ...`. The GUID's **type prefix** decodes the source with high confidence:

| GUID type prefix | Meaning | Stamped source | Extra |
|---|---|---|---|
| `Creature` / `Vehicle` / `Pet` | Killed mob | `KILL` | npcID (parsed from GUID field 6) |
| `GameObject` | World object / chest / node | `CONTAINER` (or `MPLUS` if in a completed keystone, see §4.5) | objectID |
| `Item` | Opened bag item (lockbox, container item) | `CONTAINER` | the container's own itemID/name |
| `Vignette` | Rare/vignette | `KILL` | vignette-derived name |

GUID parsing lives in `Compat.lua`:

```lua
-- Compat.lua
function Compat.DecodeGUID(guid)
  local kind = strsplit("-", guid)              -- "Creature", "GameObject", "Item", ...
  local npcID = tonumber((select(6, strsplit("-", guid))))  -- unit-type GUIDs
  return kind, npcID
end
```

### 4.3 The loot context lifecycle

`State.lootContext` is a single-slot, short-lived record stamped by peripheral events and consumed by `CHAT_MSG_LOOT`:

```lua
-- core/State.lua
NS.State.lootContext = nil   -- { source, name, detail, confidence, expires }

-- Attribution.lua
function Attribution:Stamp(source, name, detail, confidence)
  NS.State.lootContext = {
    source = source, name = name, detail = detail,
    confidence = confidence or "CERTAIN",
    expires = GetTime() + Constants.CONTEXT_TTL,   -- ~1.5s freshness window
  }
end

function Attribution:Consume()  -- called by Collector on CHAT_MSG_LOOT
  local c = NS.State.lootContext
  if c and c.expires >= GetTime() then
    return c.source, c.name, c.detail, c.confidence
  end
  return "OTHER", nil, nil, "INFERRED"
end
```

**Lifecycle:**

```
peripheral event fires  ──► Attribution:Stamp(source, name, detail)
        (LOOT_OPENED, MAIL_*, TRADE_*, MERCHANT_*, QUEST_*, LOOT_ROLL_*, ...)
                                   │  (context valid for CONTEXT_TTL)
CHAT_MSG_LOOT (self)     ──► Attribution:Consume() ──► adopt or OTHER
                                   │
        record written, context left to expire naturally (not cleared,
        so a single loot window emitting N item messages reuses it)
```

The context is intentionally **not** cleared after one consume: a `LOOT_OPENED` yields many `CHAT_MSG_LOOT` lines that all share the source. TTL handles staleness. `LOOT_CLOSED` may pre-expire a `KILL`/`CONTAINER` context to avoid bleeding into an unrelated subsequent loot.

### 4.4 Contextual stampers (events → source)

| Source | Stamped by (events) | Notes |
|---|---|---|
| `KILL` | `LOOT_OPENED` (Creature GUID) | + `encounterID`/`difficulty` from §4.5 |
| `CONTAINER` | `LOOT_OPENED` (Item/GameObject GUID), or `C_Container.UseContainerItem` hook for a lootable bag item | lockboxes, chests, nodes, opened bag/goodie items |
| `MAIL` | `MAIL_INBOX_UPDATE` + `TakeInboxItem`/`AutoLootMailItem` hooked | stamp just before taking attachment |
| `TRADE` | `TRADE_ACCEPT_UPDATE` → complete (`UI_INFO_MESSAGE` = `ERR_TRADE_COMPLETE`) | |
| `AH` | `AUCTION_HOUSE_PURCHASE_COMPLETED` / `C_AuctionHouse` won events | **planned** — no stamper yet; hidden from the mute list (`Constants.SOURCE_IMPLEMENTED`) |
| `VENDOR` | `MERCHANT_SHOW` open + buy (`hooksecurefunc("BuyMerchantItem")` / money-decrease heuristic) | per-source-excludable (noisy) |
| `QUEST` | `GetQuestReward` hook (client turn-in call, stamps before the reward pushes) + `QUEST_TURNED_IN` event (questID detail) | reward items; the event alone fires too late to catch the reward loot line |
| `CRAFT` | player `UNIT_SPELLCAST_SUCCEEDED` for Disenchant/Milling/Prospecting | **partial** — disenchant/mill/prospect stamped; broad recipe crafting deferred (cast time can exceed the TTL, see TODO.md) |
| `ROLL` | `START_LOOT_ROLL` / `LOOT_ROLL_WON` | **planned** — no stamper yet; hidden from the mute list |
| `OTHER` | (fallback) no fresh context | `INFERRED` |

Each stamper is a small handler in `Attribution.lua` registered via AceEvent. Merchant/trade/mail use `hooksecurefunc` on the take/buy calls so the stamp lands immediately before the resulting `CHAT_MSG_LOOT`.

> **Coverage honesty (v0.1.0):** only sources with a live stamper are exposed in the UI. `Constants.SOURCE_IMPLEMENTED` gates the "Record data from" mute list (`Constants.SOURCE_OPTIONS`) so unreachable buckets aren't dead checkboxes; the Browser Source dropdown already self-scopes from live data. `AH`/`ROLL` are **planned** (marked above) — the `SourceType` enum stays whole (export contract) but they can't be recorded until stamped. `CRAFT` is **partial** (disenchant/mill/prospect only; recipe crafting is a TODO). `VENDOR`/`MAIL`/`TRADE` have stampers and were confirmed in-client to record via their `CHAT_MSG_LOOT` self-line (smoke `reviews/2026-07-11/03_SMOKE_TESTS.md §F-001`, passed). BAG_UPDATE-diff capture for the AH/ROLL gaps is tracked as backlog.

> **No per-source name:** the per-source *name* (`sourceName`, the "From" column) was retired — it was blank for the majority of real loot (containers, delves, pushed items) and the combat-log name cache that backed `KILL` names was removed with it. Stampers now set `source`/`sourceDetail` only.

### 4.5 Encounter / difficulty context

`ENCOUNTER_START(encounterID, name, difficultyID, groupSize)` and `ENCOUNTER_END` maintain `State.encounter = { id, name, difficulty }`. When a `KILL` context is stamped inside an active encounter, `sourceDetail.encounterID` / `sourceDetail.difficulty` are attached. `CHALLENGE_MODE_START` / `CHALLENGE_MODE_COMPLETED` maintain `State.keystone = { level }` (read via `Compat.GetActiveKeystoneLevel()`); a `GameObject`/end-of-run loot while a keystone is active/just-completed upgrades `CONTAINER` → `MPLUS` with `sourceDetail.keystoneLevel`.

### 4.6 Confidence

- `CERTAIN` — a specific peripheral event stamped the context within TTL (GUID decode, mail take, trade complete, etc.).
- `INFERRED` — no fresh context; `OTHER`, or a heuristic (e.g. vendor money-decrease) with lower certainty.

Surfaced as a subtle marker in the table and preserved for export.

---

## 5. Collector module

Owns the acquisition path and the quality gate. Thin: attribution does the "where from", collector does the "what + should we keep it".

```lua
-- modules/Collector.lua
function Collector:OnEnable()
  self:RegisterEvent("CHAT_MSG_LOOT", "OnChatMsgLoot")
end

function Collector:OnChatMsgLoot(_, msg, ...)
  if not NS.db.global.settings.enabled then return end
  local link, qty = self:ParseSelfLoot(msg)          -- §4.1; nil if not self-loot
  if not link then return end

  local itemID = C_Item.GetItemInfoInstant(link)
  local _, _, quality = C_Item.GetItemInfo(link)      -- via Compat; may fall back to link-color parse
  if (quality or 0) < NS.db.global.settings.qualityThreshold then return end

  local source, detail, confidence = NS.Attribution:Consume()
  if NS.db.global.settings.excludedSources[source] then return end

  NS.Database:Add({
    ts = time(), char = NS.Util.PlayerKey(),
    itemID = itemID, itemLink = link, itemName = C_Item.GetItemNameByID and ... or link:match("%[(.-)%]"),
    quality = quality, quantity = qty,
    source = source, sourceDetail = detail, confidence = confidence,
    zone = GetZoneText(), mapID = C_Map.GetBestMapForUnit("player"), subzone = GetSubZoneText(),
  })
end
```

- **Quality gate:** `quality >= settings.qualityThreshold` (default `2` = Uncommon/green). Threshold is `Enum.ItemQuality`-numeric.
- **Per-source excludes:** `settings.excludedSources[source] == true` drops the record (mute noisy VENDOR/CRAFT without disabling collection).
- **Uncached items:** if `GetItemInfo` returns nil (item not yet cached), fall back to link-color parse for quality and `[name]` extraction; itemID is always available from `GetItemInfoInstant`. A cached-item retry is unnecessary — the link already carries display data.

---

## 6. Database module

### 6.1 Init

```lua
-- core/Database.lua
function NS:InitDB()
  NS.db = LibStub("AceDB-3.0"):New("LootHistoryDB", NS.defaults, true)
end
```

`NS.defaults = { global = G }` (from `defaults/Global.lua`). Account-wide: all reads/writes target `NS.db.global`.

### 6.2 API

```lua
Database:Add(record)             -- append; fire Ka0s_LootHistory_RecordAdded; return index
Database:Query(filter)           -- return array of records matching filter predicate/spec
Database:Delete(predicate)       -- remove matching; compact; fire HistoryChanged
Database:DeleteAt(index)         -- manual single-row delete from the table UI
Database:Export(filter)          -- return a plain (metatable-free) array — the v2 export seam (§13)
Database:Count()                 -- #history
```

`filter` is a spec table `{ quality=, source=, char=, mapID=, from=, to=, text= }`; `Query` compiles it to a predicate once and scans the array. For v1 dataset sizes (thousands of rows over a retention window) a linear scan per browser refresh is acceptable; if profiling shows cost, add a lazily-rebuilt index keyed by `source`/`char`/day.

### 6.3 Retention cleanup

```lua
-- core/LootHistory.lua (OnEnable) registers PLAYER_ENTERING_WORLD
function NS:OnEnterWorld()
  if NS.State.cleanupDone then return end     -- once per session
  NS.State.cleanupDone = true
  C_Timer.After(5, function() NS.Database:PruneOld() end)  -- defer off the loading spike
end

function Database:PruneOld()
  local days = NS.db.global.settings.retentionDays
  if days == 0 then return end                -- 0 == "Never"
  local cutoff = time() - days * 86400
  local kept = {}
  for _, r in ipairs(NS.db.global.history) do
    if r.ts >= cutoff then kept[#kept+1] = r end
  end
  NS.db.global.history = kept                 -- rebuild = compaction, no holes
  self.bus:SendMessage("Ka0s_LootHistory_HistoryChanged")
end
```

- Runs **once per session** on the first `PLAYER_ENTERING_WORLD`, deferred ~5s to avoid the login/zone spike.
- `retentionDays` presets: `7/14/30/60/90/180/365` and `0` = **Never**. Default **30**.
- Rebuild-and-swap avoids `table.remove` O(n²) shuffling and array holes.

---

## 7. Browser table

`BrowserTable.lua` renders the History tab. It never mutates records — it is a pure view over `Database:Query`.

### 7.1 Virtualized pooled rows (standard §9.6)

Only enough row frames for the visible viewport (+overscan) are created and recycled — a classic object pool:

```lua
local pool = { active = {}, free = {} }
function BrowserTable:AcquireRow() ... end     -- reuse from free or CreateFrame once
function BrowserTable:ReleaseRow(row) ... end
function BrowserTable:HideAll() ... end
```

Row count is bounded by `ceil(viewportHeight / rowHeight) + overscan`, independent of dataset size. A `FauxScrollFrame` (or manual scroll offset) drives which slice of the sorted/grouped list maps onto the pooled rows on each `OnVerticalScroll`.

### 7.2 The query pipeline

Every refresh runs: **filter → group → sort → slice-to-viewport → bind to pooled rows.**

```
records = Database:Query(activeFilter)        -- §6.2 filter spec from the filter bar
displayList = Group(records, groupByKey)      -- §7.4; flat list of {kind="header"|"row", ...}
Sort(displayList, sortColumn, sortDir)        -- §7.3; stable; headers keep their block
visibleSlice = displayList[offset+1 .. offset+visibleRows]
for i, row in pooled rows: Bind(row, visibleSlice[i])
```

Only the **visible slice** touches frames; filter/group/sort operate on lightweight record references, not widgets.

### 7.3 Sort

- Header click sets `sortColumn`; re-clicking the same column toggles `sortDir` (asc↔desc). An arrow glyph marks the active header.
- Sort is **stable** (`table.sort` is not, so decorate with original index as tiebreaker) so equal keys preserve insertion/time order.
- Columns: `Time · Item(name) · Qty · Quality · Source · Zone · Character`. Item sorts by `itemName`; Quality by numeric `quality`; Time by `ts`.

### 7.4 Grouping

`groupByKey ∈ { None, Source, Zone, Character, Quality, Day }`. When not `None`, records are bucketed by the key; each bucket emits a **collapsible header row** (`▶/▼ label — N items`) followed by its rows. Collapsed state per group key is held in `BrowserTable.collapsed[groupValue]`. `Day` buckets by `date("%Y-%m-%d", ts)`. Group headers participate in the same pooled-row rendering (a row is either a header or a data row, discriminated by `kind`).

### 7.5 Per-column filter model

The filter bar (`Browser.lua`) owns widgets that write into `activeFilter`:

| Widget | Filter field |
|---|---|
| Quality dropdown (min quality) | `quality` (>=) |
| Source dropdown (multi) | `source` (set membership) |
| Character dropdown | `char` |
| Zone dropdown | `mapID` |
| Item-name search box | `text` (case-insensitive substring on `itemName`) |
| Date-range selector | `from` / `to` (ts bounds) |

Changing any widget rebuilds the pipeline (§7.2). Dropdown option lists are derived from the current dataset (distinct chars/zones/sources) so they stay relevant.

### 7.6 Row interactions

- **Hover** → `GameTooltip:SetHyperlink(record.itemLink)` (exact tooltip reconstruction).
- **Shift-click item** → insert link into chat edit box.
- **Right-click** → context menu: *Link to chat*, *Delete entry* (`Database:DeleteAt`).

---

## 8. Analytics

`Analytics.lua` renders the Insights tab. All four insights are computed by a single pass over `Database:Query(dateRangeFilter)` (respects the Insights date-range selector, independent of the History tab filters). Charts are **frame-based** (StatusBar-style horizontal bars + FontStrings) — WoW has no charting lib.

| Insight | Computation | Render |
|---|---|---|
| **Source breakdown** | count records per `source`; % of total | horizontal bars, sorted desc, colored per source |
| **Quality distribution** | count per `quality` bucket | bars colored by `ITEM_QUALITY_COLORS` |
| **Loot over time** | bucket by `date("%Y-%m-%d", ts)`; count per day | per-day vertical/horizontal bars across the range |
| **Top zones & Top items** | count per `mapID` and per `itemID`; take top N; flag rarest (highest `quality`) drops | two ranked lists with counts; rarest-drop highlight strip |

Stat cards across the top: total records, distinct items, distinct characters, date span. A single aggregation walk fills a `{ bySource, byQuality, byDay, byZone, byItem, totals }` struct consumed by all widgets, so the tab renders in one O(n) pass.

---

## 9. Settings schema

Schema-as-single-source (standard §4.5). One row per setting drives defaults, panel widget, slash get/set/list/reset, and reset.

```lua
-- settings/Schema.lua
S.Schema = {
  { path="settings.enabled",         default=true, type="boolean", widget="CheckBox",
    label="Enable collection" },
  { path="settings.qualityThreshold",default=2,    type="number",  widget="Dropdown",
    label="Minimum quality", options=Constants.QUALITY_OPTIONS,      -- Common..Legendary
    onChange=function() NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged","quality") end },
  { path="settings.retentionDays",   default=30,   type="number",  widget="Dropdown",
    label="Keep history for", options=Constants.RETENTION_OPTIONS,   -- 7..365, 0=Never
    onChange=function() NS.Database:PruneOld() end },
  { path="settings.excludedSources", default={},   type="table",   widget="MultiCheck",
    label="Don't record from", options=Constants.SOURCE_OPTIONS },   -- mute VENDOR/CRAFT/etc.
  { path="minimap.hide",             default=false, type="boolean", widget="CheckBox",
    label="Hide minimap button",
    onChange=function(v) NS.Browser:SetMinimapHidden(v) end },
  { path="settings.windowScale",     default=1.0,  type="number", min=0.6, max=1.6, widget="Slider",
    label="Window scale",
    onChange=function(v) NS.Browser:SetScale(v) end },
  { path="debug",                    default=false, type="boolean", widget="CheckBox",
    label="Debug logging" },
}
```

> Note: `enabled`, `retentionDays`, etc. live under `global` (account-wide), so schema paths resolve against `NS.db.global`, not `.profile`. `Schema:WritePath` targets `NS.db.global`.

### 9.1 Single write seam

```lua
function S:Set(path, value)
  local row = S:FindRow(path); if not row then return false, "unknown path" end
  if row.validate and not row.validate(value) then return false, "invalid" end
  S:WritePath(NS.db.global, path, value)
  if row.onChange then row.onChange(value) end
  return true
end
```

Panel widgets and slash `set` both call `S:Set`. Boot-time validation asserts every `row.path` resolves against defaults (standard §4.5).

### 9.2 Slash COMMANDS

Registered via AceConsole for **both** `/lh` and `/loothistory`.

```lua
NS.COMMANDS = {
  { name="show",   desc="Open the window",         fn=function() NS.Browser:Show() end },
  { name="hide",   desc="Close the window",        fn=function() NS.Browser:Hide() end },
  { name="toggle", desc="Toggle the window",       fn=function() NS.Browser:Toggle() end },
  { name="config", desc="Open options",            fn=function() NS.Panel:Open() end },
  { name="get",    desc="Get a setting",           fn=function(a) S:CliGet(a) end },
  { name="set",    desc="Set a setting",           fn=function(a) S:CliSet(a) end },
  { name="list",   desc="List settings",           fn=function() S:CliList() end },
  { name="reset",  desc="Reset one setting",       fn=function(a) S:CliReset(a) end },
  { name="resetall",desc="Reset all settings",     fn=function() S:CliResetAll() end },
  { name="debug",  desc="Toggle debug logging",    fn=function() NS.db.global.debug = not NS.db.global.debug end },
  { name="help",   desc="Show this help",          fn=function() S:PrintHelp() end },
}
-- Standard §7.4: empty input prints help. Window display is explicit (toggle/show/hide).
function NS.addon:OnSlash(input)
  if input == nil or input:match("^%s*$") then return S:PrintHelp() end
  local verb, rest = input:match("^(%S+)%s*(.-)$")
  for _, c in ipairs(NS.COMMANDS) do if c.name == verb then return c.fn(rest) end end
  S:PrintHelp()
end
```

Help output is generated from `COMMANDS` (no hand-maintained help string).

---

## 10. Libraries

| Lib | Purpose | Embedding |
|---|---|---|
| LibStub, CallbackHandler-1.0 | Ace3 base | external |
| AceAddon-3.0 | lifecycle | external |
| AceDB-3.0 | SavedVariables | external |
| AceEvent-3.0 | events + message bus | external |
| AceTimer-3.0 | deferred cleanup, throttles | external |
| AceConsole-3.0 | slash registration | external |
| AceGUI-3.0 | **Settings panel body only** (browser table is custom) | external |
| LibSharedMedia-3.0 | fonts/textures for the window | external |
| LibDataBroker-1.1 | LDB launcher object | external |
| LibDBIcon-1.0 | minimap button | external |

**Deferred (v2):** `LibSerialize`, `LibDeflate` for the AI export.

> **Per Ka0s Standard v1.1 (§3.3/§13):** all libraries are **vendored in `libs/` and committed to git** (mandatory suite-wide; externals forbidden). The "Embedding" column above therefore reads "vendored"; `.pkgmeta` declares no `externals:` block. When the v2 export libs land, they are vendored the same way.

---

## 11. Message bus

Closed bus over AceEvent `SendMessage`/`RegisterMessage`. `NS.bus` is the addon object. Each message has exactly one sender.

| Message | Sender | Payload | Consumers |
|---|---|---|---|
| `Ka0s_LootHistory_RecordAdded` | `Database:Add` | `record, index` | Browser (append if visible), Analytics (invalidate cache) |
| `Ka0s_LootHistory_HistoryChanged` | `Database` (prune/delete/bulk) | — | Browser (full rebuild), Analytics (recompute) |
| `Ka0s_LootHistory_SettingsChanged` | `Schema:Set`/onChange | `key` (e.g. "quality") | Collector (refresh threshold upvalue), Browser (rescale) |

Each documented in `ARCHITECTURE.md` with sender/payload/consumers (standard §4.4). No two senders per message; modules never reach into each other's tables.

---

## 12. Compat / taint / performance

**Compat (`core/Compat.lua`)** — every deprecated/flavor-varying API is shimmed here:
- `Compat.DecodeGUID(guid)` — GUID type + npcID.
- `Compat.GetItemInfo` — wraps `C_Item.GetItemInfo` with a link-color fallback for uncached items.
- `Compat.IsRetail/IsClassic` — flavor flags (loot-source and AH APIs differ on Classic; `GetLootSourceInfo` exists on retail — Classic branches degrade `KILL`/`CONTAINER` gracefully).

**Taint** — the addon creates only **non-secure** frames and never touches protected/secure templates, so it introduces no taint. It does **not** `:Hide()` Blizzard frames or replace globals. `hooksecurefunc` is used only for read-side stamping (`BuyMerchantItem`, `TakeInboxItem`) — post-hooks that never alter arguments or return values.

**Performance**
- **Zero work when idle:** the only always-on handler is `CHAT_MSG_LOOT`; it early-returns before any allocation when disabled or when the message isn't self-loot.
- **Hot-path upvalue cache:** `qualityThreshold` / `enabled` / `excludedSources` cached into Collector upvalues, refreshed on `Ka0s_LootHistory_SettingsChanged` (standard §9.7).
- **Debug seam** gated on `NS.db.global.debug`, zero-allocation when off (standard §12).
- **Browser** virtualizes rows (§7.1); filter/group/sort touch record refs, not frames.
- **Pattern compile once** at load; no per-message `gsub`.
- **File LOC cap** 1500 (standard §1.1). `Browser.lua` is split from `BrowserTable.lua` pre-emptively to stay well under.

---

## 13. Deferred export seam (v2)

The AI-export feature is out of scope for v1, but the boundary is built now so it drops in **without migration**:

```lua
-- core/Database.lua  (v1 ships this)
function Database:Export(filter)
  -- returns a plain, metatable-free array of records (optionally filtered),
  -- safe to hand to LibSerialize/LibDeflate or JSON-encode.
  local out = {}
  for _, r in ipairs(self:Query(filter or {})) do
    out[#out+1] = { ts=r.ts, char=r.char, itemID=r.itemID, itemLink=r.itemLink,
                    itemName=r.itemName, quality=r.quality, quantity=r.quantity,
                    source=r.source, sourceDetail=r.sourceDetail,
                    zone=r.zone, mapID=r.mapID, subzone=r.subzone, confidence=r.confidence }
  end
  return out
end
```

The v2 work is purely additive: a new `modules/Export.lua` calls `Database:Export`, compresses with `LibSerialize`+`LibDeflate`, and presents a copy box; the accompanying AI skill consumes the decoded array. Because records are plain tables with stable field names (§3.1) and `schemaVersion` is tracked, the export format is forward-compatible.

---

*End of technical design.*
