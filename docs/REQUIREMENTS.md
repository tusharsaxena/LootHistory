# Ka0s Loot History — Requirements

**Status:** Approved v1 requirements (2026-07-11)
**Addon:** Ka0s Loot History (`LootHistory`)
**Author:** add1kted2ka0s · **License:** MIT

---

## 1. Purpose

Ka0s Loot History is a personal loot-tracking addon with two responsibilities:

1. **Capture** — silently record every item the player loots, with rich context (what it was, where, how it arrived, when).
2. **Browse & analyze** — present that history in a searchable, sortable, groupable window with summary analytics.

A third capability — exporting the data to an AI companion skill that renders a formatted document — is **deferred to a later version**. v1 is designed so the export drops in without a schema migration.

> Internal-only terminology: the two subsystems are referred to in code/docs as the **Collector** and the **Browser**. User-facing copy never uses those terms — it uses "Loot History", "History", and "Insights".

---

## 2. Glossary

| Term | Meaning |
|---|---|
| **Loot event** | A single acquisition of one item stack (e.g. `[Bandage] ×5`). One event → one stored record. |
| **Source** | How an item entered the player's inventory (kill, container, mail, trade, …). |
| **Attribution** | The process of resolving the source for a loot event. |
| **Confidence** | Whether attribution was `CERTAIN` (matched a specific event) or `INFERRED` (best-effort fallback). |
| **Retention** | The maximum age of records kept before automatic cleanup. |
| **Quality threshold** | Minimum item quality that is recorded (bloat control). |

---

## 3. Functional requirements — Capture

### 3.1 What is captured
- **FR-C1** Record every item the player personally loots (self only — not other group members' loot).
- **FR-C2** Scope is **items only** (anything with an itemID). Gold and currencies are **out of scope** for v1.
- **FR-C3** A configurable **quality threshold** gates recording. Default: **Uncommon (green) and above** (`quality ≥ 2`). Configurable to Common/Uncommon/Rare/Epic/Legendary.
- **FR-C4** Capture must be **passive and silent** — no chat spam, no popups, negligible performance cost.
- **FR-C5** A master **enable/disable** toggle stops all capture when off.

### 3.2 Data captured per loot event
- **FR-C6** For each event, store:
  - `ts` — loot timestamp (local epoch seconds)
  - `char` — capturing character as `Name-Realm`
  - `itemID`, `itemLink`, `itemName`, `quality`, `quantity`
  - `source` — attributed source enum (see 3.3)
  - `sourceDetail` — optional structured extras (npcID, encounterID, keystone level)
  - `zone`, `mapID`, `subzone` — drop location
  - `confidence` — `CERTAIN` or `INFERRED`
- **FR-C7** `itemLink` is authoritative and must be sufficient to reconstruct the full in-game tooltip (preserves quality, upgrade track, bonus IDs). `itemID`/`itemName`/`quality` are denormalized for fast table operations.
- **FR-C8** Item **name** IS stored (denormalized) to support text search and display without requiring the item to be cached.

### 3.3 Source attribution
- **FR-C9** Attribution must be **as specific as possible**, distinguishing at least these sources:
  `KILL` · `CONTAINER` · `MAIL` · `TRADE` · `AH` · `QUEST` · `VENDOR` · `CRAFT` · `ROLL` · `MPLUS` · `OTHER`.
- **FR-C10** When attribution cannot be determined confidently, the event is still recorded with `source = OTHER` and `confidence = INFERRED` (never dropped).
- **FR-C11** For `KILL` sources, capture creature name and (where available) npcID, plus encounter/difficulty context when in an instance.
- **FR-C12** Users may optionally **mute specific sources** (e.g. `VENDOR`, `CRAFT`) to reduce noise. Muted sources are not recorded.

### 3.4 Retention / cleanup
- **FR-C13** On entering the world (once per session), automatically delete records older than the **retention window**.
- **FR-C14** Retention default: **30 days**. Configurable presets: 7 / 14 / 30 / 60 / 90 / 180 / 365 days and **Never** (disables cleanup).

### 3.5 Storage
- **FR-C15** Data is stored **account-wide** in the addon SavedVariables global namespace (`LootHistoryDB.global`), so history from all characters is browsable together.
- **FR-C16** Records carry a `char` field so per-character views are a filter, not separate storage.
- **FR-C17** SavedVariables must declare a `schemaVersion` version stamp, and a migration runner (`NS:RunMigrations`) ships and is invoked at init (from `InitDB`). 1.0.0 ships the initial shape (`1`); the runner is idempotent and its body only normalizes the stamp today, gaining upgrade steps in place when the first schema change lands.

---

## 4. Functional requirements — Browse

### 4.1 Window
- **FR-B1** A **standalone, movable, resizable** window, independent of the Blizzard options UI.
- **FR-B2** Opened/closed via slash commands (`/lh show|hide|toggle`) and a **minimap button** (LibDBIcon).
- **FR-B3** Two tabs: **History** (the table) and **Insights** (analytics).
- **FR-B4** Window scale is user-configurable.

### 4.2 History table
- **FR-B5** Present records in a tabular format with columns: **Time · Item · Qty · Quality · Source · Source Name · Zone · Character**.
- **FR-B6** The Item column shows the item icon and quality-colored name; hovering shows the full item tooltip.
- **FR-B7** **Sort** by any column (click header; toggles ascending/descending with an arrow indicator).
- **FR-B8** **Filter** by any column: **multi-select** dropdowns for quality (exact qualities), item type, source, zone, and character (plus a Current/All players scope), and a free-text item-name search. A clear-filters control resets all.
- **FR-B9** **Group** by a chosen column (None / Day / Quality / Type / Source / Zone / Character), rendering collapsible group headers with per-group counts.
- **FR-B10** Right-click a row for actions: **link item to chat**, **delete this entry**.
- **FR-B11** Show a footer summary (visible/total record counts).
- **FR-B12** Handle the **empty state** gracefully (no data / no matches).
- **FR-B13** `INFERRED`-confidence entries are visually distinguished (subtle marker) so the user knows the source is a best guess.
- **FR-B14** The table must remain smooth with large datasets (virtualized/pooled rows).

### 4.3 Insights (analytics)
- **FR-B15** Provide a summary stat row (e.g. total records, distinct items, active date range).
- **FR-B16** **Source breakdown** — share of loot per source (horizontal bars with %).
- **FR-B17** **Quality distribution** — counts per quality (colored bars).
- **FR-B18** **Loot over time** — items looted per day (vertical bars).
- **FR-B19** **Top zones** and **Top items** — ranked lists with counts; highlight rarest drops (epic+).
- **FR-B20** A date-range selector scopes the analytics.
- **FR-B21** Visuals are frame-based (no external charting library).

---

## 5. Functional requirements — Settings & commands

- **FR-S1** Options presented via the Blizzard Settings canvas + AceGUI body (Ka0s canonical pattern).
- **FR-S2** Settings are **schema-driven** with a single write seam; the panel and slash commands both mutate through it.
- **FR-S3** Slash verbs `/lh` and `/loothistory`. `/lh` with no args **prints help**; window display is explicit via `/lh show|hide|toggle`.
- **FR-S4** Provide subcommands: `show`, `hide`, `toggle`, `config`, `get`, `set`, `list`, `reset`, `resetall`, `debug`, `help`.
- **FR-S5** A persistent (SavedVariables) debug toggle with zero-allocation logging when off.

---

## 6. Non-functional requirements

- **NFR-1** **Standards compliance** — conforms to the Ka0s WoW Addon Standard v1.3 (Ace3, Tier 2 layout, schema-as-single-source, closed message bus, Compat firewall, MIT, **vendored libs** in `libs/`, `.luacheckrc`). No deviations; the standalone browser window follows §6A (see §8).
- **NFR-2** **Performance** — capture is O(1) per loot event; cleanup runs once per session; the browser uses object pooling and cached upvalues for hot paths.
- **NFR-3** **Multi-flavor** — single TOC with a multi-Interface line; flavor differences isolated in `Compat.lua`.
- **NFR-4** **No taint** — the browser is a non-secure standalone frame; no protected/secure API misuse; no `:Hide()` on Blizzard frames.
- **NFR-5** **Localization-ready** — user-facing strings routed through `NS.L` with metatable fallback.
- **NFR-6** **File size** — every `.lua` file capped at 1500 LOC (peel when exceeded).
- **NFR-7** **Export-ready** — the data layer exposes a clean serialization seam (`Database:Export(filter)` → plain array) for the future AI export.

---

## 7. Out of scope (v1)

- AI export and the accompanying transformation skill (deferred; DB designed to accommodate it without migration).
- Tracking gold and currencies.
- Tracking other players' loot / group loot council data.
- Cross-account sync or cloud storage.

---

## 8. Standards compliance

No deviations. Notes on surfaces that follow the standard explicitly:

| Surface | Standard | Note |
|---|---|---|
| History window — a **standalone non-secure frame**, not a Blizzard Settings canvas. | §6A Standalone windows / data browsers. | §6A governs an addon's own main window; §6 governs the settings panel (which complies separately). Non-secure ⇒ no combat-lockdown gate. This addon is §6A's reference implementation. |

> Note: bare `/lh` **prints help** and window display is explicit (`/lh show|hide|toggle`) — complies with §7.4 ("no-arg = help").

> Note: vendoring all libraries in `libs/` is **not** a deviation. Ka0s Standard **v1.1** (2026-07-11) makes vendoring mandatory suite-wide and forbids `.pkgmeta` externals; this addon complies.

---

## 9. Open questions / future

- Exact analytics date-range presets (today / 7d / 30d / all) — finalize in UX.
- Whether to expose a per-source "mute" UI as individual toggles or a multi-select — finalize in UX.
- v2: AI export format (LibSerialize + LibDeflate compressed string) and companion skill contract.
