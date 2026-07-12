# Ka0s Loot History — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship v0.1.0 of Ka0s Loot History — passively record every item the player loots with attributed source, browse it in a filter/sort/group window, and view source/quality/time analytics.

**Architecture:** Tier-2 Ace3 addon. A **Collector** parses `CHAT_MSG_LOOT` (self only) and writes records to an account-wide AceDB array; an **Attribution** engine stamps a short-lived source context from peripheral events (loot GUID decode, mail, trade, AH, vendor, quest, roll, M+). A **Browser** (custom non-secure frame) renders a virtualized pooled-row table plus a frame-based **Analytics** view. Pure logic is unit-tested headless; UI via in-game smoke tests.

**Tech Stack:** Lua 5.1, Ace3 (AceAddon/DB/Event/Timer/Console/GUI), LibSharedMedia-3.0, LibDataBroker-1.1, LibDBIcon-1.0. Headless test harness: plain Lua 5.1 + WoW-API mocks (busted-compatible).

## Global Constraints

- **Standard:** Ka0s WoW Addon Standard v1.3 — MUST comply fully (the standalone window follows §6A; no deviations).
- **Namespace:** every file starts `local addonName, NS = ...`. No `_G[addonName]`.
- **SavedVariables:** `LootHistoryDB`, single global, account-wide data in `.global`, with `schemaVersion`.
- **Slash:** `/lh` and `/loothistory` via AceConsole `:RegisterChatCommand`. No raw `SLASH_*`.
- **Schema-as-single-source:** one Schema table drives defaults + panel + slash; one write seam `Schema:Set`.
- **Message bus:** `Ka0s_LootHistory_*`, exactly one sender per message.
- **Compat firewall:** all deprecated/flavor-varying APIs in `core/Compat.lua`; no inline `WOW_PROJECT_ID`.
- **Libs:** Ace3 + LibSharedMedia + LibDataBroker-1.1 + LibDBIcon-1.0 are **vendored in `libs/`** and committed (Ka0s Standard v1.1 — mandatory; externals forbidden). `.pkgmeta` declares no externals.
- **File cap:** 1500 LOC per `.lua`.
- **License:** MIT. **Author:** add1kted2ka0s. **TOC Title:** `Ka0s Loot History`.
- **Debug:** persistent (`NS.db.global.debug`), zero-allocation when off, `/lh debug`.
- **Slash (standard-compliant):** bare `/lh` prints help; window display is explicit (`/lh show|hide|toggle`). *(Earlier revisions toggled on no-arg — that deviation was removed.)*
- **§6A:** Browser is a non-secure standalone window (no combat gate) per §6A; the Settings panel keeps the §6 combat-gated canvas pattern.

**Source-of-truth docs:** `docs/REQUIREMENTS.md`, `docs/TECHNICAL_DESIGN.md`, `docs/UX_DESIGN.md`. Task references like "(TD §4)" point at TECHNICAL_DESIGN sections.

---

## File structure (locked)

```
LootHistory.toc · .pkgmeta · .luacheckrc · LICENSE · README.md · CLAUDE.md · ARCHITECTURE.md
core/      Compat · Constants · Namespace · State · Util · LootHistory · Database
defaults/  Global
locales/   enUS
settings/  Schema · Panel · Slash
modules/   Attribution · Collector · Browser · BrowserTable · Analytics
tests/     wow_mock.lua · run.lua · loader.lua · test_util.lua · test_attribution.lua
           test_database.lua · test_stats.lua
docs/      REQUIREMENTS · TECHNICAL_DESIGN · UX_DESIGN · EXECUTION_PLAN
reviews/<DATE>/  (5-artifact bundle, created at review time)
```

**Testing model:**
- **Unit (headless):** pure modules loaded via `tests/loader.lua` (calls each file's chunk with `("LootHistory", NS)` and mocked globals from `wow_mock.lua`). Covers Util, Compat.DecodeGUID/parsing, Attribution context logic, Database Query/Delete/Prune/Export, Stats aggregation. Run: `lua tests/run.lua`.
- **Lint:** `luacheck .` MUST pass clean before every commit.
- **Smoke (in-game):** documented steps per UI milestone; results archived in the review bundle. UI code is not unit-tested.

Each task below ends with: write/adjust unit test (where logic is pure) → run `lua tests/run.lua` → `luacheck .` → commit. Milestones that add UI end with a scripted in-game smoke test instead of a unit test.

---

## Milestone 0 — Scaffold & test harness (addon loads, `/lh` responds)

**Deliverable:** The addon loads in-game with no errors, `/lh toggle` toggles an (empty placeholder) frame, `/lh debug` works, and `lua tests/run.lua` runs green on a trivial Util test.

### Task 0.1 — Repo skeleton & metadata
**Files:** Create `LootHistory.toc`, `.pkgmeta`, `.luacheckrc`, `LICENSE` (MIT full text), empty `media/`, `libs/` (empty).
- TOC per TD §2.2 (Interface `120007`, Title `Ka0s Loot History`, SavedVariables `LootHistoryDB`, Category-enUS `Bags & Inventory`, X-License MIT; no OptionalDeps — all libs vendored). Files listed in TD §2.1 load order.
- `.pkgmeta` externals: LibStub, CallbackHandler-1.0, AceAddon/DB/Event/Timer/Console/GUI-3.0, LibSharedMedia-3.0, LibDataBroker-1.1, LibDBIcon-1.0. `ignore:` reviews/_dev/docs internal.
- `.luacheckrc` std lua51, `globals = { "LootHistoryDB" }`, read_globals for the WoW APIs used (C_Item, C_Map, GetLootSourceInfo, time, GetZoneText, GetSubZoneText, hooksecurefunc, GetInboxHeaderInfo, UnitName, etc.).
**Test:** `luacheck .` passes (no lua files yet → trivially clean). **Deliverable:** metadata committed.

### Task 0.2 — Headless test harness
**Files:** Create `tests/wow_mock.lua` (stub table of WoW globals: `time`, `GetTime`, `C_Item`, `C_Map`, `GetLootSourceInfo`, `strsplit`, `GetZoneText`, `GetSubZoneText`, `UnitName`, `LOOT_ITEM_SELF*` global strings, `ITEM_QUALITY_COLORS`, `date`), `tests/loader.lua` (loads a source file with shared `NS` + injected globals), `tests/run.lua` (test registry + runner + assert helpers), `tests/test_util.lua` (one trivial assert).
**Test:** `lua tests/run.lua` → 1 passing test. **Deliverable:** harness committed.

### Task 0.3 — Core bootstrap (Compat, Constants, Namespace, State, Util skeleton)
**Files:** Create `core/Compat.lua` (IsRetail/IsClassic + stub shims), `core/Constants.lua` (SourceType, SourceOrder, Confidence, QUALITY_OPTIONS, RETENTION_OPTIONS, CONTEXT_TTL, SOURCE_OPTIONS), `core/Namespace.lua`, `core/State.lua` (lootContext=nil, encounter/keystone/session flags), `core/Util.lua` (PlayerKey, time-format helpers).
**Interfaces produced:** `NS.SourceType`, `NS.Confidence`, `NS.Constants.*`, `NS.State`, `NS.Util.PlayerKey()`.
**Test:** `tests/test_util.lua` asserts `Constants.SourceType.KILL == "KILL"` and `Util.PlayerKey()` returns `Name-Realm` (mock UnitName). **Deliverable:** committed.

### Task 0.4 — AceAddon registration, Database init, defaults, locale
**Files:** Create `core/LootHistory.lua` (`AceAddon:NewAddon(NS, addonName, "AceEvent-3.0","AceTimer-3.0","AceConsole-3.0")`, OnInitialize→InitDB/Schema:Register/Panel:Register, OnEnable→register PLAYER_ENTERING_WORLD), `core/Database.lua` (InitDB, `NS.defaults`), `defaults/Global.lua` (G table: schemaVersion=1, history={}, settings mirror of Schema defaults, debug=false, minimap={hide=false}), `locales/enUS.lua` (NS.L metatable fallback). (Unreleased addon → no migration runner; migrations are a post-release concern.)
**Test:** headless — load Database with mocked AceDB shim; assert `NS.db.global.schemaVersion == 1` and `history` is an empty table after InitDB. **Deliverable:** committed.

### Task 0.5 — Settings schema, slash dispatch, placeholder window
**Files:** Create `settings/Schema.lua` (Schema rows per TD §9, `Schema:Set` write seam to `NS.db.global`, boot validation, `NS.COMMANDS`), `settings/Slash.lua` (register `lh`+`loothistory`, `OnSlash` with no-arg→`PrintHelp`, verb dispatch, generated help), `settings/Panel.lua` (canvas category registration; lazy body stub), and a minimal `modules/Browser.lua` stub exposing `Browser:Toggle/Show/Hide` that creates a bare frame.
**Interfaces produced:** `NS.Schema:Set(path,value)`, `NS.COMMANDS`, `NS.Browser:Toggle/Show/Hide`.
**Test:** headless — assert `Schema:Set("settings.qualityThreshold", 4)` writes `NS.db.global.settings.qualityThreshold==4` and calls onChange; assert unknown path returns false. **Smoke:** in-game `/lh` prints help; `/lh toggle` opens/closes the bare frame; `/lh debug` toggles; `/lh help` lists verbs; `/reload` persists SV.
**Milestone 0 acceptance:** loads clean (no Lua errors), `/lh` prints help and `/lh toggle` toggles the frame, `luacheck` clean, `lua tests/run.lua` green.

---

## Milestone 1 — Capture pipeline (records get written with attributed source)

**Deliverable:** Killing a mob / opening a container / taking mail / completing a trade above the quality threshold writes a correct record (verified via `/lh debug` output and a temporary count print), respecting the quality gate and per-source excludes.

### Task 1.1 — Loot-string self-parse (Util)
**Files:** Modify `core/Util.lua` (add `Util.BuildLootPatterns()` converting `LOOT_ITEM_SELF*` global strings to anchored Lua patterns once; `Util.ParseSelfLoot(msg) → itemLink, quantity | nil`), `tests/test_util.lua`.
**Interfaces produced:** `Util.ParseSelfLoot(msg)`.
**Test (TDD):** cases — "You receive loot: [link]." → link, 1; "You receive loot: [link]×3." → link, 3; other-player line → nil; push variant → link, qty. Run headless. **Deliverable:** committed.

### Task 1.2 — GUID decode & item/map compat (Compat)
**Files:** Modify `core/Compat.lua` (`Compat.DecodeGUID(guid) → kind, npcID`; `Compat.GetItemInfo(link)` with link-color quality fallback; `Compat.GetBestMapForUnit`/zone helpers), `tests/test_util.lua` or new `tests/test_compat.lua`.
**Interfaces produced:** `Compat.DecodeGUID`, `Compat.GetItemInfo`.
**Test (TDD):** `DecodeGUID("Creature-0-...-214506-...")` → "Creature", 214506; `"GameObject-..."` → "GameObject", nil; `"Item-..."` → "Item", nil. **Deliverable:** committed.

### Task 1.3 — Attribution context lifecycle
**Files:** Create `modules/Attribution.lua` (`Attribution:Stamp(source,name,detail,confidence)` → `State.lootContext` with `expires=GetTime()+CONTEXT_TTL`; `Attribution:Consume()` → source/name/detail/confidence or OTHER/INFERRED when stale), `tests/test_attribution.lua`.
**Interfaces produced:** `NS.Attribution:Stamp`, `NS.Attribution:Consume`.
**Test (TDD):** stamp then consume within TTL → returns stamped; advance mock `GetTime` past TTL → consume returns OTHER/INFERRED; consume with no stamp → OTHER/INFERRED. **Deliverable:** committed.

### Task 1.4 — Attribution stampers (events → context)
**Files:** Modify `modules/Attribution.lua` (register + handle `LOOT_OPENED` GUID decode → KILL/CONTAINER/MPLUS per TD §4.2/§4.5; `ENCOUNTER_START/END`, `CHALLENGE_MODE_START/COMPLETED` context; MAIL/TRADE/AH/VENDOR/QUEST/ROLL stampers per TD §4.4 using AceEvent + `hooksecurefunc` on `TakeInboxItem`/`BuyMerchantItem`). Add a testable pure helper `Attribution:ResolveLootSource(guid, state) → source, detail` so GUID→source is unit-testable without events.
**Interfaces produced:** `Attribution:ResolveLootSource(guid, state)`.
**Test (TDD):** creature GUID → KILL(+npcID); creature GUID while `state.encounter` set → KILL with encounter detail; GameObject GUID while `state.keystone` active → MPLUS(+keystoneLevel); GameObject GUID otherwise → CONTAINER; Item GUID → CONTAINER. **Deliverable:** committed.

### Task 1.5 — Collector: gate, build, write
**Files:** Modify `modules/Collector.lua` (register `CHAT_MSG_LOOT`; `OnChatMsgLoot`: enabled check, `Util.ParseSelfLoot`, quality gate via `Compat.GetItemInfo`, `Attribution:Consume`, excluded-source check, build record with zone/mapID/subzone/ts/char, `Database:Add`; `RefreshUpvalues` cache of enabled/threshold/excludes + subscribe `Ka0s_LootHistory_SettingsChanged`). Extract a pure `Collector:BuildRecord(link, qty, ctx, env)` for testing.
**Interfaces produced:** `Collector:BuildRecord(link, qty, ctx, env)`.
**Test (TDD):** BuildRecord returns all fields correctly populated; quality below threshold → record rejected (test the gate predicate); excluded source → rejected. **Smoke:** in-game, loot a green from a kill → `/lh debug` shows `source=KILL confidence=CERTAIN`; loot from a lockbox → CONTAINER; grey below threshold → not recorded.
**Milestone 1 acceptance:** records written with correct source/quality/zone; gate + excludes honored; harness green; luacheck clean.

---

## Milestone 2 — Data layer: query, delete, retention, stats

**Deliverable:** `Database:Query/Delete/Prune/Export` and `Database:Stats` fully implemented and unit-tested; retention cleanup runs once per session.

### Task 2.1 — Database Add + RecordAdded message
**Files:** Modify `core/Database.lua` (`Database:Add(record)` append + `bus:SendMessage("Ka0s_LootHistory_RecordAdded", record, index)`; `Database:Count`), `tests/test_database.lua`.
**Interfaces produced:** `Database:Add`, `Database:Count`.
**Test (TDD):** Add appends, Count increments, message fired (spy on mock bus). **Deliverable:** committed.

### Task 2.2 — Query filter engine
**Files:** Modify `core/Database.lua` (`Database:Query(filter)` compiling `{quality,source,char,mapID,from,to,text}` to a predicate; `Database:Export(filter)` deep plain copy per TD §13), `tests/test_database.lua`.
**Interfaces produced:** `Database:Query`, `Database:Export`.
**Test (TDD):** seed mixed records; filter by quality>= , by source, by char, by mapID, by from/to ts, by case-insensitive text substring; empty filter returns all; Export returns metatable-free copies with all fields. **Deliverable:** committed.

### Task 2.3 — Delete & retention prune
**Files:** Modify `core/Database.lua` (`Database:DeleteAt(index)`, `Database:Delete(pred)`, `Database:PruneOld()` rebuild-and-swap using `settings.retentionDays`, 0=Never; both fire `HistoryChanged`), wire `NS:OnEnterWorld` once-per-session guard in `core/LootHistory.lua`, `tests/test_database.lua`.
**Interfaces produced:** `Database:DeleteAt`, `Database:Delete`, `Database:PruneOld`.
**Test (TDD):** DeleteAt removes correct row & compacts; PruneOld with days=30 drops records older than cutoff, keeps newer; days=0 keeps everything; HistoryChanged fired. **Deliverable:** committed.

### Task 2.4 — Stats aggregation
**Files:** Modify `core/Database.lua` (`Database:Stats(filter) → {bySource,byQuality,byDay,byZone,byItem,totals{records,distinctItems,distinctChars,firstTs,lastTs}}` single O(n) pass), `tests/test_stats.lua`.
**Interfaces produced:** `Database:Stats`.
**Test (TDD):** seed records; assert bySource counts, byQuality counts, byDay buckets (via mock `date`), top zones/items ordering, distinctItems/distinctChars, first/last ts. **Deliverable:** committed.
**Milestone 2 acceptance:** all data-layer unit tests green; retention verified; luacheck clean.

---

## Milestone 3 — Browser window & table

**Deliverable:** `/lh` opens a movable/resizable window; History tab shows records in a virtualized table with sortable headers, working filters, grouping, hover tooltips, and right-click delete/link.

### Task 3.1 — Window shell, tabs, position/scale persistence
**Files:** Modify `modules/Browser.lua` (backdrop frame, drag-move, resize grip w/ min clamp, `SetClampedToScreen`, saved `settings.window` pos/size, tab strip History/Insights with lazy content build, `SetScale` from `ui.scale`, subscribe `SettingsChanged`).
**Smoke:** window opens, moves, resizes, remembers pos/size/scale across `/reload`; tabs switch.

### Task 3.2 — Pooled-row table skeleton + column headers
**Files:** Create `modules/BrowserTable.lua` (row object pool Acquire/Release/HideAll; column config `{key,label,width,align,valueFn,sortFn}`; FauxScrollFrame; `Refresh()` runs Query→bind visible slice).
**Interfaces produced:** `BrowserTable:Refresh()`, `BrowserTable:SetFilter(filter)`.
**Smoke:** table lists current records with all 8 columns; scrolling recycles rows (no lag with 1000+ seeded records).

### Task 3.3 — Sort
**Files:** Modify `modules/BrowserTable.lua` (header click sets sortCol; re-click toggles dir; stable sort w/ index tiebreaker; arrow glyph on active header).
**Smoke:** each column sorts asc/desc; Time/Quality/Qty sort numerically, Item/Source/Zone/Character lexically; equal keys keep time order.

### Task 3.4 — Grouping
**Files:** Modify `modules/BrowserTable.lua` (group-by None/Source/Zone/Character/Quality/Day → flat display list of header/row entries; collapsible headers w/ counts; collapsed-state map; Day via `date("%Y-%m-%d",ts)`).
**Smoke:** grouping by each key shows collapsible headers with correct counts; collapse/expand works; sort applies within groups.

### Task 3.5 — Filter bar
**Files:** Modify `modules/Browser.lua` (quality/source/character/zone dropdowns from distinct dataset values, item-name search box, group-by dropdown, clear button → write `activeFilter`, call `BrowserTable:SetFilter`), footer "Showing X of Y".
**Smoke:** each filter narrows rows; text search substring works; clear resets; footer counts correct; empty-state message when no matches.

### Task 3.6 — Row interactions + confidence marker
**Files:** Modify `modules/BrowserTable.lua` (hover→`GameTooltip:SetHyperlink`; shift-click→`ChatEdit_InsertLink`; right-click menu Link-to-chat / Delete→`Database:DeleteAt`+Refresh; INFERRED rows show subtle marker per UX_DESIGN).
**Smoke:** tooltip matches item; link inserts to chat; delete removes row & persists; INFERRED entries visibly marked.
**Milestone 3 acceptance:** full History tab usable; smooth with large data; no taint/Lua errors.

---

## Milestone 4 — Insights (analytics)

**Deliverable:** Insights tab shows stat cards + Source breakdown, Quality distribution, Loot over time, Top zones/items, scoped by a date-range selector.

### Task 4.1 — Insights layout + stat cards + date range
**Files:** Create `modules/Analytics.lua` (build on Insights tab; date-range selector Today/7d/30d/All → filter; stat cards from `Database:Stats`).
**Smoke:** cards show correct totals; date range changes recompute.

### Task 4.2 — Frame-based charts
**Files:** Modify `modules/Analytics.lua` (Source breakdown horizontal bars w/ % + source colors; Quality distribution bars w/ `ITEM_QUALITY_COLORS`; Loot-over-time per-day bars; Top zones + Top items ranked lists w/ counts, epic+ highlight). Subscribe `RecordAdded`/`HistoryChanged` to invalidate+recompute when visible.
**Smoke:** each visual matches the seeded data; live-updates when a new loot arrives while open; recompute on range change.
**Milestone 4 acceptance:** all four analytics render correctly and update; one O(n) aggregation pass per render.

---

## Milestone 5 — Settings panel, minimap, polish

**Deliverable:** Full options panel wired to the Schema; LibDBIcon minimap button; slash CLI complete.

### Task 5.1 — Options panel body
**Files:** Modify `settings/Panel.lua` (lazy AceGUI body driven by Schema: enable toggle, quality dropdown, per-source excludes multi-check, retention dropdown, minimap toggle, scale slider, debug toggle; combat-lockdown gate on open; all writes via `Schema:Set`).
**Smoke:** every control reflects & mutates settings; changing quality/excludes affects capture; scale/minimap toggles apply live; `/lh config` opens it; combat defers open.

### Task 5.2 — Minimap button (LibDBIcon + LDB)
**Files:** Modify `modules/Browser.lua` (LDB launcher: left-click Toggle, tooltip w/ record count; `LibDBIcon:Register` w/ `db.global.minimap`; `Browser:SetMinimapHidden`).
**Smoke:** minimap button toggles window; hide toggle from settings works; persists across `/reload`.

### Task 5.3 — Slash CLI completeness
**Files:** Modify `settings/Slash.lua` (`get/set/list/reset/resetall` over Schema; generated `help`; `show/hide/toggle/config/debug`). Add `tests/test_database.lua` or `test_util.lua` coverage for any pure CLI parse helper.
**Test/Smoke:** `/lh set collection.qualityThreshold 4`, `/lh get ...`, `/lh list`, `/lh reset ...`, `/lh resetall` all behave; help generated from COMMANDS.
**Milestone 5 acceptance:** settings fully functional; minimap works; CLI complete; luacheck clean; harness green.

---

## Milestone 6 — Docs, review, release v0.1.0

### Task 6.1 — ARCHITECTURE.md & README.md
**Files:** Create `ARCHITECTURE.md` (Overview, Module Map, Settings Schema, Message Bus table w/ sender/payload/consumers, Slash Commands table, Event Subscriptions, Taint Notes, Standards compliance, Known Limitations) and `README.md` (Title, badges, Description, Features, Installation, Usage/slash table, Configuration, Version History). Sync CLAUDE.md TODOs.
**Test:** run `wow-addon:sync-docs` drift check (5-claim). **Deliverable:** committed.

### Task 6.2 — Review bundle & version stamp
**Files:** Run `wow-addon:review` → `reviews/<DATE>/` 5-artifact bundle; address blockers; confirm `## Version: 0.1.0` consistent (TOC/README/CLAUDE). Final `luacheck .` + `lua tests/run.lua`.
**Status:** DONE — review run (`reviews/2026-07-11/`), all findings addressed; `luacheck .` 0/0, `lua tests/run.lua` green (85); version `0.1.0` consistent; in-client smoke (`03_SMOKE_TESTS.md`) **passed** (F-001 confirmed VENDOR/MAIL/TRADE record via `CHAT_MSG_LOOT`).
**Deliverable:** v0.1.0 shipped at `## Version: 0.1.0` / `NS.version`. (No git tag — versioning is by the TOC stamp, by choice.)

---

## Backlog (post-v0.1.0)

- [ ] **Tune attribution (M1 follow-up).** In-game smoke (2026-07-11) confirmed KILL attribution + quality gate, but surfaced two refinements:
  1. **Context lifetime.** Context is stamped once on `LOOT_OPENED` with a fixed 1.5s TTL, so *slow manual click-looting* (>1.5s between items in one window) lets later items fall back to `OTHER`/`INFERRED`. Consider keeping the context alive *while the loot window is open* — re-stamp/extend on each loot, expire on `LOOT_CLOSED` — instead of a fixed TTL. NOTE: CLAUDE.md flags the single-slot TTL as a deliberate design; revisit that note if changing.
  2. ~~**Source-name resolution.**~~ RESOLVED BY REMOVAL: the "From" column and its `sourceName` field were retired — the name was blank for the majority of real loot (containers, delves, pushed items), and the combat-log death-name cache that backed `KILL` names was removed with it. Attribution now records `source`/`sourceDetail` only.
- [ ] **Addon interop.** Integrate with value/upgrade addons and show their data as columns/annotations:
  - **Auctionator / TSM / other AH addons** — show market/AH value per item (fallback chain across whichever is installed).
  - **Pawn** — show an **upgrade arrow** when the looted gear was an upgrade *at the time of looting* (evaluate against the character's equipped gear then and store the verdict on the record, since "now" may differ).
  - **Loot Appraiser** and any other appraisal addons — pull their value estimates where available.
  - All optional deps: degrade gracefully when the addon isn't present.
- [ ] **Column chooser.** Let the user reorder and show/hide table columns (the `BrowserTable.COLUMNS` model already carries per-column metadata; add a settings/table-header UI and persist the order + visibility).
- [ ] **Purge history in Settings.** A "Clear all history" button (with confirm) in the options panel — mirrors the `/lh purge` slash command already implemented.
- [ ] **Bundle a monospace font** (e.g. Fira Mono) in `media/` and register it via LibSharedMedia, for the debug console (WoW ships no monospace; the console currently uses the default font, whose tabular digits keep timestamps aligned).
- [ ] **Configurable window styling.** The browser window ships a flat "ElvUI-like" default skin (1px black border + subtle inner line + dark flat background + gold title + red close glyph), centralized in `modules/Browser.lua`'s `SKIN` table and `B:ApplySkin(frame)`. Add settings to let the user customize **border** (color/thickness), **background** (color/alpha), and **font** (via LibSharedMedia), driven off that table with live re-skin. New Schema rows under an "Appearance" section; `ApplySkin` already exists as the single re-skin seam.
- [ ] **More analytics (Insights expansion).** The current Insights tab covers source / quality / loot-over-time breakdowns plus top zones/items. Add further views driven off `Database:Stats` (single O(n) pass), e.g.: per-character comparison, item-value totals over time (once addon interop lands), loot rate (drops per hour/session), quality mix trend, rarest/most-valuable drops, and per-source yield. New charts should reuse the existing frame-based chart primitives in `modules/Analytics.lua` and the date-range scoping.
- [ ] **AI export + companion skill** (the deferred v2 feature; `Database:Export()` seam already in place).

## Self-review — spec coverage map

| Requirement (REQUIREMENTS.md) | Task(s) |
|---|---|
| FR-C1..C5 capture/self-filter/quality gate/enable | 1.1, 1.5, 5.1 |
| FR-C6..C8 record fields / itemLink / name | 1.5 (BuildRecord), 2.1 |
| FR-C9..C12 attribution + confidence + excludes | 1.2–1.5 |
| FR-C13..C14 retention + Never | 2.3 |
| FR-C15..C17 account-wide storage + schemaVersion | 0.4, 2.1 |
| FR-B1..B4 window/open/tabs/scale | 3.1, 5.2 |
| FR-B5..B14 table columns/sort/filter/group/menu/empty/inferred/virtualized | 3.2–3.6 |
| FR-B15..B21 analytics | 4.1–4.2 |
| FR-S1..S5 settings/schema/slash/debug | 0.5, 5.1, 5.3 |
| NFR-1..7 standards/perf/multiflavor/taint/l10n/LOC/export-ready | 0.1–0.4, 1.5, 2.2, 3.2, 6.x |
| §7.4 slash + §6A window | 0.5 (slash), 3.1 (non-secure window) |

All FR/NFR map to at least one task. No orphan requirements.
