# Scope

What Ka0s Loot History is, what's in scope, and what's not. The user-facing contract lives in [README.md](../README.md); this doc records the *boundary* decisions — including the ones already litigated and settled — so a fresh contributor can tell whether a feature request is in or out of scope without re-opening them.

## What Ka0s Loot History is

Ka0s Loot History is a WoW addon with two responsibilities: **capture** every item the player personally loots (above a configurable quality threshold), attributing each drop to a **source**; and **browse & analyze** that history in a standalone window with a filter/sort/group table plus an Insights (analytics) view. Storage is account-wide, so loot from every character is browsable together. Designed as a personal loot ledger — not a group-loot / loot-council tool.

Capture is passive and silent: the authoritative "item received (self)" signal is `CHAT_MSG_LOOT`, and peripheral events stamp a short-lived source context the collector consumes (see [attribution.md](attribution.md)). The window is a non-secure standalone frame, independent of the Blizzard options UI; the settings panel is a separate Blizzard Settings canvas. The message contract between collector, database, browser, analytics, and settings is documented in [architecture.md](ARCHITECTURE.md).

Target client: WoW 12.0.7 (Midnight), Retail-only (`## Interface: 120007`). Mainline branch: `master`. English-only.

Display name in the addon list and the Settings panel: `Ka0s Loot History`. The folder, addon ID, slash commands (`/lh`, `/loothistory`), and saved-variable namespace (`LootHistoryDB`) stay unprefixed `LootHistory` for ergonomics. Data and settings live account-wide in `LootHistoryDB.global`.

> Internal-only terms **Collector** (capture) and **Browser** (view) appear in code and docs. User-facing copy says "Loot History", "History", and "Insights" — never those internal terms.

## In scope

- **Passive capture** of every item the player personally loots — self only (items with an itemID; currency is captured separately — see below). A configurable **quality threshold** (default Common+) and an optional **quest-item filter** gate recording; a master enable switch stops all capture.
- **Source attribution** into `Constants.SourceType`: `KILL`, `CONTAINER`, `MAIL`, `TRADE`, `AH`, `QUEST`, `VENDOR`, `MPLUS`, `BONUS_ROLL`, `ROLL`, `CRAFT`, `REFUND`, `DISENCHANT`, `MILLING`, `PROSPECTING`, and an `OTHER` fallback — each tagged `CERTAIN` or `INFERRED` confidence. Every source has a live capture path, so all appear in the **mute** UI (`Constants.SOURCE_IMPLEMENTED`).
- **Currency capture** (Valorstones, crests, etc.) as `Type=Currency` history rows — attributed to the same sources as items, obeying the per-source mute list and a `Record currency` master toggle, but exempt from the quality/quest gates. Surfaced in the History table, a dedicated Insights currency block, and CSV export. Export-to-AI for currency is deferred. (This reverses the earlier "currencies out of scope" decision — ratified 2026-07-21.)
- **Account-wide history** stored as a dense array in `LootHistoryDB.global.history`, with a `char` column so per-character views are a filter, not separate storage. Automatic **retention** prune runs once per session (default 30 days; configurable, including Never).
- **Standalone browser window** — movable, resizable, scale-configurable — with a History table (multi-select filters for quality / type / source / zone / character, a Current/All scope, item-name search, click-to-sort, group-by, and row actions) and an Insights tab (range-scoped breakdowns and top lists). Rendered with pooled/virtualized rows. See [browser.md](browser.md).
- **Schema-driven settings** — one Blizzard Settings canvas plus a `/lh` slash CLI, both mutating through the single `Schema:Set` write seam. See [settings-panel.md](settings-panel.md) and [slash-dispatch.md](slash-dispatch.md).
- **Minimap button** (LibDBIcon + LDB).
- **Export seam** — `Database:Export(filter)` returns a plain array in the forward-compatible v2 export shape.

## Out of scope

These have been considered and explicitly declined for the current version.

- **AI export feature.** v1.x ships the `Database:Export()` seam only; the companion skill that renders the exported data into a formatted document is deferred to v2. The DB shape is designed so it drops in without a schema migration.
- **Gold.** Capture of looted money (copper) is out — high-frequency and its-own-value, better modelled as aggregated Insights tallies than per-drop rows. See the deferred design.
- **Other players' loot / group-loot council data.** The addon is a personal ledger — `CHAT_MSG_LOOT` self-lines only.
- **Cross-account sync or cloud storage.** Storage is local SavedVariables.
- **Per-item human-readable source name.** The old "From" column and its combat-log kill-name cache were removed — for the dominant real-world loot (containers, delves, pushed/quest items) no reliable name resolved, so the column was almost always blank. Records keep the machine-readable `sourceDetail` (npcID / encounterID / keystone level / questID); the human name is not captured or displayed.
- **Localization.** English only. Strings route through `NS.L` with a metatable fallback so the plumbing exists, but no non-English locale ships and localization is a deliberate non-goal for now.

## Resolved design decisions

Load-bearing choices that look like candidates for "improvement" but are intentional. Do not change these without a documented reason (mirrored in [agent-context.md](agent-context.md)).

- **Account-wide storage** (`.global` + a `char` column), not per-character AceDB profiles. Switching would be a schema + query rewrite; the account-wide view is the product.
- **Single-slot attribution context with a fixed TTL.** The source stamp deliberately survives multiple `CHAT_MSG_LOOT` lines from one loot window rather than being consumed by the first line.
- **Non-secure standalone browser window** (Standard standalone-windows). Non-secure by design — no combat-lockdown gate, ESC via `UISpecialFrames`, persisted geometry — not an oversight. This addon is standalone-windows's reference implementation.
- **`Database:Export` field shape.** It is the forward-compatible v2 export contract; the `SourceType` enum stays whole (keys are additive, never renamed) for the same reason.

## Known limitations

Boundaries that are real today but are not deliberate non-goals — they are places the current version stops short.

- **Slow manual click-looting.** The source context uses a fixed `CONTEXT_TTL` (1.5s). Looting items more than ~1.5s apart from a single open window can let later items fall back to `OTHER` / `INFERRED`.
- **Roll-win line assumption.** The `ROLL` source is stamped from `LOOT_ROLL_YOU_WON` ("You won:"). If a client emits the compact "no-spam" roll variant instead, a rolled item falls back to whatever context is fresh (usually the kill/container it dropped from). Verify in-game (smoke §F-009).
- **No upgrade-scoring addon interop** (Pawn / Loot Appraiser). Vendor `vendorPrice` and, since the Rev-2 AH-price integration, auction-house prices from Auctionator / TSM / OribosExchange are both captured — see [ARCHITECTURE.md](ARCHITECTURE.md) and [data-model.md](data-model.md) — but no third-party upgrade/BiS scoring is read.

## Backlog

The backlog lives in the GitHub issue tracker:

  https://github.com/tusharsaxena/LootHistory/issues

Revisiting the single-slot TTL, value/upgrade addon interop, and the v2 AI export are all tracked there. Shipped from the tracker: shared filters across History + Insights (#13), the item-id blacklist/whitelist (#14), and tab-aware Export with an Insights CSV (#15).
