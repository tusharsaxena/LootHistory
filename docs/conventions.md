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
- **Every setting mutation routes through `Schema:Set(path, value)`** (`settings/Schema.lua:109`).
  That seam is: look the row up → run its optional `validate` → `WritePath` a **deep copy** of the
  value → fire the row's `onChange`. The deep copy is load-bearing: without it a reset would alias
  the DB to a shared `default` table (e.g. `settings.excludedSources = {}`), and any later in-place
  mutation would poison the default for the rest of the session (see the comment at
  `settings/Schema.lua:97`).
- **Paths resolve against `NS.db.global`, not `.profile`** — storage is account-wide, so
  `Schema:Get`/`:Set` read and write `NS.db.global` directly (`settings/Schema.lua:113`,`:121`).
  Nothing in the addon touches `NS.db.profile`.
- **Carve-outs.** The Browser's window geometry (`settings.window` — point/size), its saved table view
  (`savedView`), and the `blacklist`/`whitelist` item-id lists (owned by `NS.Filters`,
  `modules/Filters.lua`) are runtime/data state, not user settings. They are persisted straight to
  `NS.db.global` and intentionally have **no** schema row and do **not** go through `Schema:Set` — a
  dynamic id-set can't be a schema widget. Don't "fix" this by adding rows for them. See
  [saved-variables.md](saved-variables.md) for the full carve-out list and the standards note.

## Messaging: a closed bus, one target per receiver

- Cross-module signalling uses `Ka0s_LootHistory_*` messages on `NS.bus` (the AceAddon object,
  `core/LootHistory.lua:6`) — `RecordAdded`, `HistoryChanged`, `SettingsChanged`. Each message has
  exactly one sender. Modules never reach into another module's tables; they listen for a message.
- **Receivers register on their own target from `NS.NewBusTarget()`** (`core/LootHistory.lua:20`),
  never on the shared `NS.bus`/`NS.addon` as `self`. CallbackHandler keys callbacks by
  `(message, target)`, so two consumers that share a target silently clobber each other — only the
  last registrant of a given message ever fires. The panel's live-stats refresh is the reference
  pattern: it grabs a private target and registers on it (`settings/Panel.lua:373`). Full contract
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
  reused rows in `modules/BrowserTable.lua`. Never create one frame per record (Ka0s standard standalone-windows);
  a 50k-row history must not spawn 50k frames.

## Collector hot-path upvalues

- The collector caches its gate config as file-level upvalues — `enabled`, `qualityThreshold`,
  `excludedSources`, `excludeQuestItems` (`modules/Collector.lua:9`) — so the `CHAT_MSG_LOOT`
  handler reads locals, not a chain of table lookups, on every loot line (Ka0s standard events-frames-taint-§7). They
  are refreshed by `Collector:RefreshUpvalues()` on `Ka0s_LootHistory_SettingsChanged`
  (`modules/Collector.lua:51`). The quest-item gate keys on the locale-independent item class
  (`Constants.ITEMCLASS_QUEST`), never the localized `itemType` string.

## Chat output: one shared secret-safe printer

- Every chat line goes through the single shared printer `NS.Print` (`core/Util.lua`). Each file
  that emits chat does `local print = NS.Print` and calls `print("message")` — **never** the global
  `print()`, **never** a hand-written `NS.PREFIX` tag, **never** `..`-concatenated args. `NS.Print`
  prepends the cyan `NS.PREFIX` tag (slash-commands-§4) and routes each arg through `NS.SafeToString`
  so a combat-protected "secret" value logs as `<secret>` instead of raising (events-frames-taint-§8).
- Because `NewAddon(NS, …, "AceConsole-3.0")` embeds an AceConsole `:Print` that would clobber the
  Util printer, `core/LootHistory.lua` **reclaims** `NS.Print = NS.Util.print` right after `NewAddon`
  (architecture-§2). Don't reorder that.

## Session-only debug

- Debugging is a **session-only** flag, `NS.State.debug`, default `false`, reset every reload and
  **never persisted** (`core/State.lua:15`) — it is deliberately *not* a schema row. When off,
  `NS.Debug` is a zero-allocation no-op: it returns before formatting anything
  (`modules/DebugLog.lua:249`).
- The flag is independent of the console window's visibility. `/lh debug` toggles the window only;
  `/lh debug on|off` set the logging flag (capture runs even with the window closed); the header's
  `Debug: ON`/`OFF` control flips the same flag (`settings/Schema.lua:153`).
- All debug output goes through `NS.Debug(tag, fmt, ...)` and renders in the tagged format
  `<ts> | [<tag>] <content>` (`D.FormatPlain`, `modules/DebugLog.lua:119`). `tag` is one short word,
  printed verbatim — no padding, no truncation.
- `NS.Debug` is **secret-safe** (events-frames-taint-§8): every `...` arg is routed through
  `NS.SafeToString` before it reaches `string.format`, so a combat-protected "secret" value logs as
  `<secret>` rather than crashing the sink. Because args arrive pre-stringified, its format strings
  use `%s` for every placeholder (never `%d`/`%f`).

## File size cap

- Source files are capped at **1500 LOC** (Ka0s standard layout-§1). The browser is deliberately split
  three ways to respect it — `Browser.lua` (window shell), `BrowserTable.lua` (the pooled table),
  `Analytics.lua` (Insights) — the largest sitting near ~1000 lines.

## Media: Blizzard defaults, with one ratified font exception

- **Fonts, textures, and borders default to Blizzard-shipped media.** Text uses stock `GameFont*`
  font objects (and `STANDARD_TEXT_FONT` for the window close glyph, `modules/Browser.lua:65`);
  every texture resolves to a Blizzard built-in or atlas (`Interface\Buttons\WHITE8X8`,
  `UI-CheckBox-Check`, `UI-Classes-Circles`, atlas `Options_HorizontalDivider`, …); borders are
  `WHITE8X8` drawn as 1px edges, coloured from the flat `SKIN` table (`modules/Browser.lua:19`).
  The one non-Blizzard asset outside media is the addon's own logo in the settings panel
  (`settings/Panel.lua:530`) — branding art, not a re-skinnable surface.
- **Ratified exception — the monospace console font (audited 2026-07-17).** The debug console and
  the export/debug copy boxes render in the vendored **JetBrains Mono** (`Constants.FONT_MONO`,
  used at `modules/DebugLog.lua:93`,`:191` and `modules/Export.lua:305`). This is a **deliberate,
  ratified deviation** from Blizzard-default-only: WoW ships **no monospace font object**, and
  column-aligned copy/paste text needs one. The font is OFL-licensed and vendored at
  `media/fonts/`; init registers it with LibSharedMedia (`core/LootHistory.lua:30`) purely to
  *publish* it — nothing reads a font setting. Do not re-flag this as a standards deviation.
- **No LSM media pickers, by design.** There is no font/texture/border user setting; LSM is used
  only for the registration above (no `Fetch`/`List`). Making the flat `SKIN` user-configurable is
  a tracked post-1.0.0 idea (`modules/Browser.lua:14`), not a gap to close now.

## Options UI: Blizzard canvas, never AceConfigDialog

- The settings panel is a Blizzard `Settings.RegisterCanvasLayoutCategory` parent (the landing page)
  plus a `RegisterCanvasLayoutSubcategory` "General" body built lazily from raw AceGUI widgets
  (`settings/Panel.lua:433`). **AceConfigDialog is never used for content** — there is no
  AceConfig/AceConfigDialog dependency in the addon at all. `P:Open` is combat-gated
  (`settings/Panel.lua:484`), matching the Ka0s options-ui-§2 canvas pattern (the standalone browser window
  follows the separate standalone-windows non-secure pattern).

## Panel layout: options-ui-§6/§10 conformance

- **Right-edge inset (options-ui-§6/§8).** Cell-filling *action* buttons (Reset All, Purge history) inset
  to `BUTTON_PAIR_REL = 0.492`, not `0.5`, so their right border clears the ScrollFrame's clip
  (`settings/Panel.lua:31`, applied in `makePairButton`, `settings/Panel.lua:214`). Label-inset
  controls (checkbox / dropdown / slider) already reserve that gutter and stay at `0.5` — they are
  immune (options-ui-§10). `BUTTON_PAIR_REL` is the single seam for that width; don't hard-code it per button.
- **Always-shown scrollbar (options-ui-§10).** `installAlwaysShownScrollbar` overrides AceGUI's stock
  `FixScroll` so the panel scrollbar is *always* visible and the 20px right gutter is *always*
  reserved (`settings/Panel.lua:109`). AceGUI would otherwise hide the bar and reclaim the gutter
  when content fits, shifting the body width between a short page and a long one. When there's
  nothing to scroll the override parks the thumb at the top and greys the bar inert, so the body
  width is identical across every subcategory. More on the panel in
  [settings-panel.md](settings-panel.md).
