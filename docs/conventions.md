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
- **Every setting mutation routes through `Schema:Set(path, value)`** (`settings/Schema.lua:160`).
  That seam is: look the row up → run its optional `validate` → `WritePath` a **deep copy** of the
  value → fire the row's `onChange`. The deep copy is load-bearing: without it a reset would alias
  the DB to a shared `default` table (e.g. `settings.excludedSources = {}`), and any later in-place
  mutation would poison the default for the rest of the session (see the comment at
  `settings/Schema.lua:160`).
- **Paths resolve against `NS.db.global`, not `.profile`** — storage is account-wide, so
  `Schema:Get`/`:Set` read and write `NS.db.global` directly (`settings/Schema.lua:180`,`:168`).
  Nothing in the addon touches `NS.db.profile`.
- **Carve-outs.** The Browser's window geometry (`settings.window` — point/size), its saved table view
  (`savedView`), the `blacklist`/`whitelist`/`currencyBlacklist` id lists (owned by `NS.Filters`,
  `modules/Filters.lua`), and the `settings.auction.priority` cascade (owned by `NS.AuctionPrice`) are
  runtime/data state, not user settings. They are persisted straight to
  `NS.db.global` and intentionally have **no** schema row and do **not** go through `Schema:Set` — a
  dynamic id-set or an ordered list can't be a schema widget. Don't "fix" this by adding rows for them. See
  [saved-variables.md](saved-variables.md) for the full carve-out list and the standards note.

## Messaging: a closed bus, one target per receiver

- Cross-module signaling uses `Ka0s_LootHistory_*` messages on `NS.bus` (the AceAddon object,
  `core/LootHistory.lua:6`) — `RecordAdded`, `HistoryChanged`, `SettingsChanged`. Each message has
  exactly one sender. Modules never reach into another module's tables; they listen for a message.
- **Receivers register on their own target from `NS.NewBusTarget()`** (`core/LootHistory.lua:20`),
  never on the shared `NS.bus`/`NS.addon` as `self`. CallbackHandler keys callbacks by
  `(message, target)`, so two consumers that share a target silently clobber each other — only the
  last registrant of a given message ever fires. The panel's live-stats refresh is the reference
  pattern: it grabs a private target and registers on it (`settings/Panel.lua:123`). Full contract
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
  (`modules/Collector.lua:223`). The quest-item gate keys on the locale-independent item class
  (`Constants.ITEMCLASS_QUEST`), never the localized `itemType` string.

## Chat output: one shared secret-safe printer

- Every chat line goes through the single shared printer `NS.Print` — LibKa0s-Core-1.0's, published
  under that name (and as `NS.Util.print`) by the `core/CoreSetup.lua` seam (`core/CoreSetup.lua:97`,
  `:103`). Each file that emits chat does `local print = NS.Print` and calls `print("message")` —
  **never** the global `print()`, **never** a hand-written `NS.PREFIX` tag, **never**
  `..`-concatenated args. `NS.Print` prepends the cyan `NS.PREFIX` tag (slash-commands-§4) and routes
  each arg through `NS.SafeToString` — also the library's, republished at `core/CoreSetup.lua:92` —
  so a combat-protected "secret" value logs as `<secret>` instead of raising (events-frames-taint-§8).
- **`core/CoreSetup.lua` must load before every file that captures the printer at file scope**
  (`modules/Browser.lua`, `settings/Schema.lua`, `settings/Slash.lua`, `settings/Panel.lua` all do
  `local print = NS.Print` at load), and after `core/Namespace.lua`, which defines the `NS.PREFIX`
  string the seam hands the library. It also publishes `NS.LIBKA0S_MISSING`, the one shared cause
  clause every other LibKa0s seam appends its own consequence to; each seam degrades to a stub
  rather than erroring when the vendored library is absent.
- Because `NewAddon(NS, …, "AceConsole-3.0")` embeds an AceConsole `:Print` that would clobber the
  shared printer, `core/LootHistory.lua` **reclaims** `NS.Print = NS.Util.print` right after
  `NewAddon` (`core/LootHistory.lua:13`, architecture-§2). Publishing to both keys is what makes that
  reclaim restore the library printer rather than undo the seam. Don't reorder that.

## Session-only debug

- Debugging is a **session-only** flag, `NS.State.debug`, default `false`, reset every reload and
  **never persisted** (`core/State.lua:15`) — it is deliberately *not* a schema row. When off,
  `NS.Debug` is a zero-allocation no-op: it returns before building the argument table
  (`D.Debug`, `libs/LibKa0s/DebugLog.lua:511`). The console is LibKa0s-DebugLog-1.0's; the sink is
  bound bare — never as a method — onto `NS.Debug` by the `core/DebugLogSetup.lua` seam
  (`core/DebugLogSetup.lua:135`), which is also where `NS.DebugLog` is instantiated.
- The flag is independent of the console window's visibility. `/lh debug` toggles the window only;
  `/lh debug on|off` set the logging flag (capture runs even with the window closed,
  `settings/Schema.lua:224`); the header's `Debug: ON`/`OFF` control flips the same flag
  (`libs/LibKa0s/DebugLog.lua:353`). The flag stays the **host's** throughout — the descriptor hands
  the library `isEnabled`/`setEnabled` closures over `NS.State.debug` (`core/DebugLogSetup.lua:87`)
  so the slash verb, the panel and the console header all read one truth. The window's *visibility*
  is the separate `state.debugConsole` session-only schema row (`settings/Schema.lua:43`).
- All debug output goes through `NS.Debug(tag, fmt, ...)` and renders in the tagged format
  `<ts> | [<tag>] <content>` (`lib.FormatPlain`, `libs/LibKa0s/DebugLog.lua:93`; the colored console
  variant is `lib.FormatColored`, `:101`). `tag` is one short word, printed verbatim — no padding,
  no truncation.
- `NS.Debug` is **secret-safe** (events-frames-taint-§8): every `...` arg is routed through
  `NS.SafeToString` before it reaches `string.format`, so a combat-protected "secret" value logs as
  `<secret>` rather than crashing the sink. Because args arrive pre-stringified, its format strings
  use `%s` for every placeholder (never `%d`/`%f`).

## File size cap

- Source files are capped at **1500 LOC** (Ka0s standard layout-§1). The browser is deliberately split
  three ways to respect it — `Browser.lua` (window shell), `BrowserTable.lua` (the pooled table),
  `Analytics.lua` (Insights) — the largest, `Browser.lua`, sitting near ~1370 lines.

## Media: Blizzard defaults, with one ratified font exception

- **Fonts, textures, and borders default to Blizzard-shipped media.** Text uses stock `GameFont*`
  font objects (and `STANDARD_TEXT_FONT` for the window close glyph, `modules/Browser.lua:85`);
  every texture resolves to a Blizzard built-in or atlas (`Interface\Buttons\WHITE8X8`,
  `UI-CheckBox-Check`, `UI-Classes-Circles`, atlas `Options_HorizontalDivider`, …); borders are
  `WHITE8X8` drawn as 1px edges, colored from `Core.SKIN` via `B:ApplySkin`’s delegation to
  `NS.ApplySkin` (`modules/Browser.lua:75`, `core/CoreSetup.lua`); `modules/Browser.lua:23`’s own
  `SKIN` table carries only the tab colors and layout heights.
  The one non-Blizzard asset outside media is the addon's own logo on the settings landing page
  (`LOGO_PATH`, `settings/Panel.lua:23`, drawn at `:579`) — branding art, not a re-skinnable surface.
- **Ratified exception — the monospace console font (audited 2026-07-17).** The debug console and
  the export/debug copy boxes render in the vendored **JetBrains Mono** (`Constants.FONT_MONO`,
  `core/Constants.lua:58`). The console gets it as the DebugLog descriptor's `font` field
  (`core/DebugLogSetup.lua:82`), which the library holds on the descriptor and applies when the
  console frame is first built (`EnsureFrame`) — to the log frame, the line counter and the copy box
  (`libs/LibKa0s/DebugLog.lua:367`,`:416`,`:474`); the export copy
  box sets it directly (`modules/Export.lua:346`). This is a **deliberate,
  ratified deviation** from Blizzard-default-only: WoW ships **no monospace font object**, and
  column-aligned copy/paste text needs one. The font is OFL-licensed and vendored at
  `media/fonts/`; init registers it with LibSharedMedia (`core/LootHistory.lua:30`) purely to
  *publish* it — nothing reads a font setting. Do not re-flag this as a standards deviation.
- **No LSM media pickers, by design.** There is no font/texture/border user setting; LSM is used
  only for the registration above (no `Fetch`/`List`). Making the shared edge user-configurable is
  a tracked post-1.0.0 idea (`modules/Browser.lua:17`) that now belongs at the LibKa0s seam, not a
  gap to close now.

## Options UI: Blizzard canvas, never AceConfigDialog

- The settings panel is a Blizzard `Settings.RegisterCanvasLayoutCategory` parent (the landing page)
  plus three `RegisterCanvasLayoutSubcategory` bodies — General, Filters, AH Price — built lazily
  from raw AceGUI widgets. The canvas shell, the page registry, the lazy Defaults button, the five
  widget makers and the two-column flow engine are LibKa0s-Options-1.0's, wired in
  `settings/OptionsSetup.lua`; `settings/Panel.lua` registers the three pages and owns their bodies
  (`settings/Panel.lua:717`). **AceConfigDialog is never used for content** — there is no
  AceConfig/AceConfigDialog dependency in the addon at all. `P:Open` delegates to
  `O.OpenOptionsPanel` (`settings/Panel.lua:791`), whose combat gate lives in the library
  (`libs/LibKa0s/Options.lua:637`) and now also fires on a page's `OnShow`
  (`libs/LibKa0s/Options.lua:463`), so reaching a page straight from the Blizzard AddOns sidebar is
  refused too. It refuses rather than deferring-and-replaying, matching the Ka0s options-ui-§2 canvas
  pattern (the standalone browser window follows the separate standalone-windows non-secure pattern).

## Panel layout: options-ui-§6/§10 conformance

- **Right-edge inset (options-ui-§6/§8).** Cell-filling *action* buttons (Reset Everything, Purge history) inset
  to `BUTTON_PAIR_REL = 0.492`, not `0.5`, so their right border clears the ScrollFrame's clip. The
  constant is the library's (`libs/LibKa0s/Options.lua:76`), re-exported on the instance as
  `O.BUTTON_PAIR_REL` and read by this addon's own `makePairButton` (`settings/Panel.lua:35`).
  Label-inset controls (checkbox / dropdown / slider) already reserve that gutter and stay at `0.5` —
  they are immune (options-ui-§10). `BUTTON_PAIR_REL` is the single seam for that width; don't
  hard-code it per button.
- **Always-shown scrollbar (options-ui-§10).** `PatchAlwaysShowScrollbar` overrides AceGUI's stock
  `FixScroll` so the panel scrollbar is *always* visible and the 20px right gutter is *always*
  reserved (`libs/LibKa0s/OptionsScroll.lua:83`, applied to every ScrollFrame `O.EnsureScroll`
  creates, `libs/LibKa0s/Options.lua:322`). AceGUI would otherwise hide the bar and reclaim the gutter
  when content fits, shifting the body width between a short page and a long one. When there's
  nothing to scroll the override parks the thumb at the top and grays the bar inert, so the body
  width is identical across every subcategory. More on the panel in
  [settings-panel.md](settings-panel.md).

## Minimum-quality threshold: a non-monotonic Heirloom option (ratified exception)

- **Ratified exception (2026-07-20).** The "Minimum quality" setting is a *monotonic floor* — the
  collector records loot where `quality >= threshold` (`modules/Collector.lua`, `gateReason`), so a
  clean ladder would run Poor(0) → Legendary(5) and stop. `C.QUALITY_OPTIONS`
  (`core/Constants.lua:88`) nonetheless appends **Heirloom (id 7)** after Legendary at the user's
  explicit request. Because Heirloom's item-quality id (7) sorts *above* Legendary(5) and
  Artifact(6), selecting it floors capture at 7 — recording **only Heirlooms and WoW Tokens** and
  gating out Epics/Legendaries. That is the intended, user-chosen behavior, **not** a bug: do not
  "correct" the ladder back to 0–5, and do not re-flag it as a standards deviation. Artifact(6) and
  Token(8) remain omitted (no meaningful floor). Each entry's `text` colors only the quality name,
  via the same `ITEM_QUALITY_COLORS` tint the History Browser uses.
