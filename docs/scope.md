# Scope

What Ka0s Loot History is, what's in scope, and what's not. The user-facing contract lives in [README.md](../README.md); this doc records the *boundary* decisions — including the ones already litigated and settled — so a fresh contributor can tell whether a feature request is in or out of scope without re-opening them.

## What Ka0s Loot History is

Ka0s Loot History is a WoW addon with two responsibilities: **capture** every item the player personally loots (above a configurable quality threshold), attributing each drop to a **source**; and **browse & analyze** that history in a standalone window with a filter/sort/group table plus an Insights (analytics) view. Storage is account-wide, so loot from every character is browsable together. Designed as a personal loot ledger — not a group-loot / loot-council tool.

Capture is passive and silent: the authoritative "item received (self)" signal is `CHAT_MSG_LOOT`, and peripheral events stamp a short-lived source context the collector consumes (see [attribution.md](attribution.md)). The window is a non-secure standalone frame, independent of the Blizzard options UI; the settings panel is a separate Blizzard Settings canvas. The message contract between collector, database, browser, analytics, and settings is documented in [architecture.md](architecture.md).

Target client: WoW 12.0.7 (Midnight), Retail-only (`## Interface: 120007`). Mainline branch: `master`. English-only.

Display name in the addon list and the Settings panel: `Ka0s Loot History`. The folder, addon ID, slash commands (`/lh`, `/loothistory`), and saved-variable namespace (`LootHistoryDB`) stay unprefixed `LootHistory` for ergonomics. Data and settings live account-wide in `LootHistoryDB.global`.

> Internal-only terms **Collector** (capture) and **Browser** (view) appear in code and docs. User-facing copy says "Loot History", "History", and "Insights" — never those internal terms.

## In scope

- **Passive capture** of every item the player personally loots — self only, items only (anything with an itemID). A configurable **quality threshold** (default Uncommon+) and an optional **quest-item filter** gate recording; a master enable switch stops all capture.
- **Source attribution** into `Constants.SourceType`: `KILL`, `CONTAINER`, `MAIL`, `TRADE`, `AH`, `QUEST`, `VENDOR`, `MPLUS`, `DISENCHANT`, `MILLING`, `PROSPECTING`, plus `CRAFT` / `ROLL` (enum'd, not yet stamped) and an `OTHER` fallback — each tagged `CERTAIN` or `INFERRED` confidence. Users may **mute** individual sources; only sources with a live stamper (`Constants.SOURCE_IMPLEMENTED`) appear in the mute UI.
- **Account-wide history** stored as a dense array in `LootHistoryDB.global.history`, with a `char` column so per-character views are a filter, not separate storage. Automatic **retention** prune runs once per session (default 30 days; configurable, including Never).
- **Standalone browser window** — movable, resizable, scale-configurable — with a History table (multi-select filters for quality / type / source / zone / character, a Current/All scope, item-name search, click-to-sort, group-by, and row actions) and an Insights tab (range-scoped breakdowns and top lists). Rendered with pooled/virtualized rows. See [browser.md](browser.md).
- **Schema-driven settings** — one Blizzard Settings canvas plus a `/lh` slash CLI, both mutating through the single `Schema:Set` write seam. See [settings-panel.md](settings-panel.md) and [slash-dispatch.md](slash-dispatch.md).
- **Minimap button** (LibDBIcon + LDB).
- **Export seam** — `Database:Export(filter)` returns a plain array in the forward-compatible v2 export shape.

## Out of scope

These have been considered and explicitly declined for the current version.

- **AI export feature.** v1.x ships the `Database:Export()` seam only; the companion skill that renders the exported data into a formatted document is deferred to v2. The DB shape is designed so it drops in without a schema migration.
- **Gold and currencies.** Capture is scoped to items (anything with an itemID). Tracking currency or money is out.
- **Other players' loot / group-loot council data.** The addon is a personal ledger — `CHAT_MSG_LOOT` self-lines only.
- **Cross-account sync or cloud storage.** Storage is local SavedVariables.
- **Per-item human-readable source name.** The old "From" column and its combat-log kill-name cache were removed — for the dominant real-world loot (containers, delves, pushed/quest items) no reliable name resolved, so the column was almost always blank. Records keep the machine-readable `sourceDetail` (npcID / encounterID / keystone level / questID); the human name is not captured or displayed.
- **Localization.** English only. Strings route through `NS.L` with a metatable fallback so the plumbing exists, but no non-English locale ships and localization is a deliberate non-goal for now.

## Resolved design decisions

Load-bearing choices that look like candidates for "improvement" but are intentional. Do not change these without a documented reason (mirrored in [agent-context.md](agent-context.md)).

- **Account-wide storage** (`.global` + a `char` column), not per-character AceDB profiles. Switching would be a schema + query rewrite; the account-wide view is the product.
- **Single-slot attribution context with a fixed TTL.** The source stamp deliberately survives multiple `CHAT_MSG_LOOT` lines from one loot window rather than being consumed by the first line.
- **Non-secure standalone browser window** (Standard standalone-windows). Non-secure by design — no combat-lockdown gate, ESC via `UISpecialFrames`, persisted geometry — not an oversight. This addon is standalone-windows's reference implementation.
- **`Database:Export` field shape.** It is the forward-compatible v2 export contract; the `SourceType` enum stays whole (including the not-yet-stamped `CRAFT` / `ROLL`) for the same reason.

## Known limitations

Boundaries that are real today but are not deliberate non-goals — they are places the current version stops short.

- **Partial source coverage.** `ROLL` and `CRAFT` are in the `SourceType` enum but have no stamper yet, so they are hidden from the mute list. `CRAFT` is reserved for broad recipe crafting, whose cast time can exceed the context TTL. Deconstruct abilities stamp their own `DISENCHANT` / `MILLING` / `PROSPECTING` source, and `AH` is stamped from Auction-House mail.
- **Slow manual click-looting.** The source context uses a fixed `CONTEXT_TTL` (1.5s). Looting items more than ~1.5s apart from a single open window can let later items fall back to `OTHER` / `INFERRED`.
- **No value / upgrade addon interop** (Auctionator / TSM / Pawn / Loot Appraiser). Vendor `sellPrice` is captured, but no third-party market value or upgrade scoring is read.

## Backlog

The post-1.0.0 backlog lives in the GitHub issue tracker (issues #1–#12):

  https://github.com/tusharsaxena/LootHistory/issues

BAG_UPDATE-diff capture for the `ROLL` gap, revisiting the single-slot TTL, value/upgrade addon interop, and the v2 AI export are all tracked there.
