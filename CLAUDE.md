# CLAUDE.md — Ka0s Loot History

Agent context for this repo. Read this first, then `docs/TECHNICAL_DESIGN.md` for depth.

---

## What this addon is

**Ka0s Loot History** records every item the player loots (above a configurable quality threshold), attributes each drop to a **source** (kill / container / mail / trade / AH / quest / vendor / disenchant / milling / prospecting / craft / roll / M+ chest / other), stores it account-wide, and presents it in a standalone browser window with a filter/sort/group table plus an insights (analytics) view.

- **Slash:** `/lh`, `/loothistory`
- **SavedVariables:** `LootHistoryDB` (account-wide; data + settings live in `.global`)
- **Author:** add1kted2ka0s · **License:** MIT
- A future version adds AI export; v1 ships an export-ready DB seam only.

> Internal-only terms **Collector** (capture) and **Browser** (view) are used in code/docs. User-facing copy says "Loot History", "History", "Insights".

---

## Stack & tier

- **Substrate:** Ace3 — AceAddon / AceDB / AceEvent / AceTimer / AceConsole / AceGUI.
- **Extra libs:** LibSharedMedia-3.0 (fonts), LibDataBroker-1.1 + LibDBIcon-1.0 (minimap). LibSerialize/LibDeflate deferred to the v2 export.
- **Tier: 2 (modular)** — collector, attribution engine, DB, browser, analytics, settings warrant >8 files.
- All libraries are **vendored in `libs/`** and committed (per Ka0s Standard v1.1 — vendoring is mandatory suite-wide; `.pkgmeta` externals are forbidden). Do not delete `libs/` or switch to externals.

---

## Layout & key files

```
core/
  Compat.lua        -- LOAD FIRST. flavor flags + all deprecated/varying API shims (GUID decode, item/map info)
  Constants.lua     -- SourceType enum, quality/retention option tables, TTLs, defaults refs
  Namespace.lua     -- bootstrap shared upvalues (NS.L, NS.C aliases)
  State.lua         -- runtime state: lootContext, encounter/keystone context, session flags
  Util.lua          -- pure helpers (time fmt, link/loot-string parsing, table ops, PlayerKey)
  LootHistory.lua   -- AceAddon:NewAddon(NS,...); OnInitialize/OnEnable; PLAYER_ENTERING_WORLD
  Database.lua      -- AceDB init, Add/Query/Delete/Export, retention prune
defaults/Global.lua -- G = global defaults (history[], settings, schemaVersion, minimap)
locales/enUS.lua    -- canonical strings; NS.L metatable fallback
settings/
  Schema.lua        -- one row per setting; Schema:Set single write seam; COMMANDS table
  Panel.lua         -- Settings.RegisterCanvasLayoutCategory + lazy AceGUI body (combat-gated)
  Slash.lua         -- AceConsole binding for /lh + /loothistory; dispatch from COMMANDS
modules/
  Attribution.lua   -- source-resolution engine; stamps & consumes the loot context (loads before Collector)
  Collector.lua     -- CHAT_MSG_LOOT handler; self-filter + quality gate; builds & writes records
  Browser.lua       -- window shell: frame, tabs, filter bar, group-by control, minimap/LDB
  BrowserTable.lua  -- virtualized pooled-row table: filter→group→sort→slice→bind pipeline
  Analytics.lua     -- Insights tab: cards + value/source/quality/type/char/time breakdowns + top lists
  DebugLog.lua      -- session-only debug console window (Copy/Clear); mirrors NS.Debug output
docs/               -- REQUIREMENTS, TECHNICAL_DESIGN, UX_DESIGN, EXECUTION_PLAN
```

Load order (TOC): `core/Compat` → rest of `core/` → `defaults/` → `locales/` → `settings/` → `modules/` (Attribution before Collector).

---

## Conventions cheat-sheet (Ka0s standard)

1. Every file begins `local addonName, NS = ...`. No `_G[addonName]`.
2. **Schema-as-single-source** — `settings/Schema.lua` drives AceDB defaults, panel widgets, slash get/set/list/reset. Every user *setting* mutation goes through `Schema:Set(path, value)` (validate → write → deep-copy → onChange). Paths resolve against `NS.db.global` (account-wide), not `.profile`. **Carve-out:** the Browser's window geometry (`settings.window`) and saved table view (`savedView`) are view/window runtime state persisted directly to `NS.db.global` — they are intentionally *not* Schema rows and do not route through `Schema:Set`.
3. **Closed message bus** — `Ka0s_LootHistory_*` messages, exactly one sender each. No cross-module table reach. (`RecordAdded`, `HistoryChanged`, `SettingsChanged`.)
4. **Compat firewall** — every deprecated/flavor-varying API call lives in `core/Compat.lua`; modules call `NS.Compat.X`. No inline `WOW_PROJECT_ID` branching.
5. **Attribution model** — `CHAT_MSG_LOOT` is the authoritative "item received (self)" signal; peripheral events stamp a short-lived `State.lootContext` that the collector consumes. Fallback = `OTHER`/`INFERRED`. See TECHNICAL_DESIGN §4. Only sources with a live stamper are exposed: `Constants.SOURCE_IMPLEMENTED` gates the mute UI — `AH`/`CRAFT`/`ROLL` are enum'd but not yet stamped (the `SourceType` enum stays whole as the export contract).
6. **Object pooling** for the table (standard §9.6). Never one frame per record.
7. **Hot-path upvalues** — collector caches `enabled`/`qualityThreshold`/`excludedSources`, refreshed on `SettingsChanged` (standard §9.7).
8. **Session-only debug** toggle (`NS.State.debug`, default off, resets every reload — not persisted), zero-allocation when off, `/lh debug`. It tracks the debug console's visibility: `/lh debug` toggles the console; closing the console (X or ESC) turns debug off. The same applies to `/lh test` (`BrowserTable.testMode`, session-only).
9. Files capped at 1500 LOC. Browser deliberately split into Browser/BrowserTable/Analytics.
10. Options via Blizzard `Settings.RegisterCanvasLayoutCategory` + lazy raw AceGUI body. Never AceConfigDialog for content.

---

## Standards compliance (no deviations)

Documented in `ARCHITECTURE.md` and `docs/REQUIREMENTS.md §8`. Surface-specific notes:

1. **The standalone browser window follows §6A** (Standalone windows / data browsers): a non-secure `CreateFrame` — no combat-lockdown gate, ESC via `UISpecialFrames`, persisted position/size/scale, one `SKIN`/`ApplySkin` re-skin seam. Ka0s Loot History is §6A's reference implementation. The *Settings panel* separately follows the §6 combat-gated canvas pattern.

> Bare `/lh` **prints help** (standard-compliant, §7.4). Window display is explicit: `/lh toggle` or `/lh show|hide`.

(Vendored libs follow Standard v1.1 — vendoring is the suite-wide rule.)

---

## Data model (one record per loot event)

`{ ts, char, classFile, itemID, itemLink, itemName, quality, itemLevel, bound, sellPrice, itemType, itemSubType, quantity, source, sourceDetail, zone, mapID, subzone, confidence }`

- `itemLink` is canonical (exact tooltip). The denormalized item fields (`itemID`, `itemName`, `quality`, `itemLevel`, `bound`, `sellPrice`, `itemType`, `itemSubType`) back fast table ops; `classFile` is the locale-independent class token for coloring.
- History is a dense array in `LootHistoryDB.global.history`; deletion/retention rebuild-and-swap (no holes).
- `source ∈ Constants.SourceType`; `confidence ∈ { CERTAIN, INFERRED }`.

---

## Git workflow (Ka0s standard)

- **No feature branches unless explicitly asked.** Work trunk-based: commit feature work directly to the default branch (`master`). Do **not** run `git checkout -b` / `git switch -c` on your own — only create a branch when the user asks for one. (Commit timing still follows the sub-milestone rule: commit when a plan Task is done and green, not at every checkpoint.)
- **Never push** unless the user asks; the user pushes when ready.

---

## Local dev & tests

WoW runs **Lua 5.1**, so tests target it. Install the toolchain locally (Debian/Ubuntu/WSL):

```
sudo apt-get update && sudo apt-get install -y lua5.1 luarocks
sudo luarocks install luacheck
```

- **Unit tests (headless):** `lua tests/run.lua` from the repo root — loads all source via `tests/loader.lua` + WoW-API mocks in `tests/wow_mock.lua`.
- **Lint:** `luacheck .` — must report **0 errors** before every commit (config in `.luacheckrc`).
- **Syntax-check one file:** `luac -p path/to/file.lua`.

---

## Current status / TODO

- [x] Planning docs complete: REQUIREMENTS · TECHNICAL_DESIGN · UX_DESIGN · EXECUTION_PLAN · CLAUDE.
- [x] Milestone 0 — scaffold, headless test harness, loadable Tier-2 skeleton.
- [x] Milestone 1 — capture pipeline (self-parse, GUID decode, attribution, collector gate/build/write).
- [x] Milestone 2 — data layer (Add/Query/Delete/PruneOld/Stats/Export), retention.
- [x] Milestone 3 — browser window + virtualized table (sort, group, filter, row actions).
- [x] Milestone 4 — Insights analytics (range selector, stat cards, frame-based charts).
- [x] Milestone 5 — settings panel, slash CLI, minimap button (LibDBIcon + LDB).
- [x] Milestone 6 — `ARCHITECTURE.md` + `README.md` authored (Task 6.1); `wow-addon:review` run (`reviews/2026-07-11/`) and **all findings F-001…F-013 addressed** (Task 6.2). `luacheck .` = 0/0, `lua tests/run.lua` green (85), `## Version: 0.1.0` consistent.
- [x] In-client smoke tests (`reviews/2026-07-11/03_SMOKE_TESTS.md`) **passed** — F-001 confirmed VENDOR/MAIL/TRADE record via `CHAT_MSG_LOOT`. **0.1.0 complete.** (No git tag by choice; version is stamped in the TOC / `NS.version`.)

---

## Do not change without reason

- The **account-wide** storage decision (`.global`, `char` column). Switching to per-character profiles is a schema + query rewrite.
- The **attribution context TTL / single-slot** design — it deliberately survives multiple `CHAT_MSG_LOOT` lines from one loot window.
- The **standalone non-secure browser window** (follows §6A) — non-secure by design, not an oversight.
- `Database:Export` field shape — it is the forward-compatible v2 export contract.
