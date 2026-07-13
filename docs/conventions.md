# Conventions

Code style and module-level rules — the "cheat-sheet" that applies file-by-file. The mid-level
architecture (module boundaries, the message contract, the Compat firewall, the settings panel)
lives in [module-map.md](module-map.md), [message-bus.md](message-bus.md),
[compat-layer.md](compat-layer.md), and [settings-panel.md](settings-panel.md); this file collects
the small-scale rules those documents assume.

## File preamble

- Every source file begins `local addonName, NS = ...` and hangs its exports off the shared `NS`
  table (`NS.Compat`, `NS.Schema`, `NS.Collector`, …). There is no `_G[addonName]` and no global
  `LootHistory` — nothing in `core/`, `modules/`, `settings/`, `defaults/`, or `locales/` reaches
  the addon through the global table. `addonName` is used only where the loader needs it
  (`AceAddon:NewAddon(NS, addonName, …)` in `core/LootHistory.lua:4`).
- Module tables are created defensively: `NS.X = NS.X or {}` then `local X = NS.X`, so load order
  never depends on which file ran first.

## Settings: schema as the single source of truth

- `settings/Schema.lua` holds one row per user setting, and that table drives four surfaces at
  once — AceDB defaults, the panel widgets, the slash `get`/`set`/`list`/`reset` verbs, and the
  Defaults/Reset-all resets. Add a row and all four gain the setting; never write a parallel
  mutator for a field that already has a row.
- **Every setting mutation routes through `Schema:Set(path, value)`** (`settings/Schema.lua:107`).
  That seam is: look the row up → run its optional `validate` → `WritePath` a **deep copy** of the
  value → fire the row's `onChange`. The deep copy is load-bearing: without it a reset would alias
  the DB to a shared `default` table (e.g. `settings.excludedSources = {}`), and any later in-place
  mutation would poison the default for the rest of the session (see the comment at
  `settings/Schema.lua:95`).
- **Paths resolve against `NS.db.global`, not `.profile`** — storage is account-wide, so
  `Schema:Get`/`:Set` read and write `NS.db.global` directly (`settings/Schema.lua:111`,`:120`).
  Nothing in the addon touches `NS.db.profile`.
- **Carve-out.** The Browser's window geometry (`settings.window` — point/size, `modules/Browser.lua:88`)
  and its saved table view (`savedView`, `modules/Browser.lua:664`) are view/window *runtime* state,
  not user settings. They are persisted straight to `NS.db.global` and intentionally have **no**
  schema row and do **not** go through `Schema:Set`. Don't "fix" this by adding rows for them.

## Messaging: a closed bus, one target per receiver

- Cross-module signalling uses `Ka0s_LootHistory_*` messages on `NS.bus` (the AceAddon object,
  `core/LootHistory.lua:6`) — `RecordAdded`, `HistoryChanged`, `SettingsChanged`. Each message has
  exactly one sender. Modules never reach into another module's tables; they listen for a message.
- **Receivers register on their own target from `NS.NewBusTarget()`** (`core/LootHistory.lua:13`),
  never on the shared `NS.bus`/`NS.addon` as `self`. CallbackHandler keys callbacks by
  `(message, target)`, so two consumers that share a target silently clobber each other — only the
  last registrant of a given message ever fires. The panel's live-stats refresh is the reference
  pattern: it grabs a private target and registers on it (`settings/Panel.lua:361`). Full contract
  in [message-bus.md](message-bus.md).

## Compat firewall

- Every deprecated or version-varying API call lives in `core/Compat.lua`; modules call
  `NS.Compat.X` and never the raw global. This is a Retail-only addon, so shims are gated by a
  direct `C_*`/global **presence check** (e.g. `if C_Map and C_Map.GetBestMapForUnit then …`) that
  degrades to `nil`/`false` when the API is absent — **not** by reading a game-flavor project id.
  There is no `WOW_PROJECT_ID` branching anywhere (`core/Compat.lua:5`). Details in
  [compat-layer.md](compat-layer.md).

## Table rendering: object pooling

- The history table pools row frames — filter → group → sort → slice → **bind** into a fixed set of
  reused rows in `modules/BrowserTable.lua`. Never create one frame per record (Ka0s standard §9.6);
  a 50k-row history must not spawn 50k frames.

## Collector hot-path upvalues

- The collector caches its gate config as file-level upvalues — `enabled`, `qualityThreshold`,
  `excludedSources`, `excludeQuestItems` (`modules/Collector.lua:9`) — so the `CHAT_MSG_LOOT`
  handler reads locals, not a chain of table lookups, on every loot line (Ka0s standard §9.7). They
  are refreshed by `Collector:RefreshUpvalues()` on `Ka0s_LootHistory_SettingsChanged`
  (`modules/Collector.lua:51`). The quest-item gate keys on the locale-independent item class
  (`Constants.ITEMCLASS_QUEST`), never the localized `itemType` string.

## Session-only debug

- Debugging is a **session-only** flag, `NS.State.debug`, default `false`, reset every reload and
  **never persisted** (`core/State.lua:15`) — it is deliberately *not* a schema row. When off,
  `NS.Debug` is a zero-allocation no-op: it returns before formatting anything
  (`modules/DebugLog.lua:243`).
- The flag is independent of the console window's visibility. `/lh debug` toggles the window only;
  `/lh debug on|off` set the logging flag (capture runs even with the window closed); the header's
  `Debug: ON`/`OFF` control flips the same flag (`settings/Schema.lua:150`).
- All debug output goes through `NS.Debug(tag, fmt, ...)` and renders in the tagged format
  `<ts> | [<tag>] <content>` (`D.FormatPlain`, `modules/DebugLog.lua:118`). `tag` is one short word,
  printed verbatim — no padding, no truncation.

## File size cap

- Source files are capped at **1500 LOC** (Ka0s standard §9). The browser is deliberately split
  three ways to respect it — `Browser.lua` (window shell), `BrowserTable.lua` (the pooled table),
  `Analytics.lua` (Insights) — the largest sitting near ~1000 lines.

## Options UI: Blizzard canvas, never AceConfigDialog

- The settings panel is a Blizzard `Settings.RegisterCanvasLayoutCategory` parent (the landing page)
  plus a `RegisterCanvasLayoutSubcategory` "General" body built lazily from raw AceGUI widgets
  (`settings/Panel.lua:421`). **AceConfigDialog is never used for content** — there is no
  AceConfig/AceConfigDialog dependency in the addon at all. `P:Open` is combat-gated
  (`settings/Panel.lua:472`), matching the Ka0s §6 canvas pattern (the standalone browser window
  follows the separate §6A non-secure pattern).

## Panel layout: §6.6 / §6.10 conformance

- **Right-edge inset (§6.6/§6.8).** Cell-filling *action* buttons (Reset All, Purge history) inset
  to `BUTTON_PAIR_REL = 0.492`, not `0.5`, so their right border clears the ScrollFrame's clip
  (`settings/Panel.lua:31`, applied in `makePairButton`, `settings/Panel.lua:202`). Label-inset
  controls (checkbox / dropdown / slider) already reserve that gutter and stay at `0.5` — they are
  immune (§6.10). `BUTTON_PAIR_REL` is the single seam for that width; don't hard-code it per button.
- **Always-shown scrollbar (§6.10).** `installAlwaysShownScrollbar` overrides AceGUI's stock
  `FixScroll` so the panel scrollbar is *always* visible and the 20px right gutter is *always*
  reserved (`settings/Panel.lua:108`). AceGUI would otherwise hide the bar and reclaim the gutter
  when content fits, shifting the body width between a short page and a long one. When there's
  nothing to scroll the override parks the thumb at the top and greys the bar inert, so the body
  width is identical across every subcategory. More on the panel in
  [settings-panel.md](settings-panel.md).
