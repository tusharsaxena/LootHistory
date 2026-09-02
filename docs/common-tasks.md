# Common tasks

Recipes for the changes made most often in this addon, plus the house rules every one of them obeys.
The mid-level architecture — module boundaries, the message contract, the Compat firewall, the
settings panel — lives in [module-map.md](module-map.md), [message-bus.md](message-bus.md),
[compat-layer.md](compat-layer.md) and [settings-panel.md](settings-panel.md); this file is the "how
do I actually do it" page.

The house rules below were `docs/conventions.md` until standard v2.23.0 retired that filename. They
live here rather than in `ARCHITECTURE.md` because every recipe on this page depends on them, and a
rule you have to open another file to find is a rule that gets broken.

## Recipes

### Add a setting

One row, one file, four surfaces. A row in `settings/Schema.lua` drives the AceDB default, the panel
widget, the slash `get`/`set`/`list`/`reset` verbs, and the Defaults/Reset-all resets at once — so
**never** write a parallel mutator for a field that already has a row.

1. Add the shipped value to `defaults/Global.lua` under `global.settings.*`. That is the **one**
   declaration site (`savedvariables-§2`).
2. Add the row to `S.Schema` in `settings/Schema.lua`. Its `default` **reads** `G.settings.<path>`
   rather than restating the literal — two literals for one value is exactly how the AH cascade
   drifted (LH-R-01), and `tests/test_schema.lua`'s "shipped default equals the schema's declared
   default" case can only catch a drift while two things exist to compare.
3. Use the **library's** row vocabulary, not the pre-adoption names: `type = "bool"` (not
   `"boolean"`), `values` with each entry's `text` (not `options`/`label`), `solo` (not `soloRow`),
   `skipRender` (not `panelSkip`). An unmapped field is **not an error** — it is a row that silently
   vanishes from a page, or a `set` that answers `ERR_TYPE`. `tooltip` deliberately did *not* move:
   the library reads `tooltip` first and its own `desc` second.
4. `page` names the canvas SUBCATEGORY the row is edited on — there is exactly one, `"General"` —
   and is what the descriptor's `rowsForPage` matches on; `group` names the **tab** within it
   (options-ui-§13) and `subgroup` a subsection heading *inside* a tab (options-ui-§7, and **not**
   suppressed by the strip). `settings/Panel.lua` partitions the page's rows by `group` in
   declaration order, so a group's rows MUST be contiguous — and a **new group needs an entry in
   `GENERAL_TABS`** in the matching position, or it renders nowhere (`tests/test_panel.lua` compares
   the two). Row order within a group drives the two-column pairing; `wide` forces a full-width row
   and `startsLine` flushes the pending line before one.
5. Give the row an `onChange` if anything must react — typically
   `NS.bus:SendMessage("Ka0s_LootHistory_SettingsChanged", "<key>")`, which is what makes the
   collector re-cache its hot-path upvalues.

Paths resolve against `NS.db.global`, never `.profile`. If the value is a dynamic id-set or an
ordered list, it is a **carve-out**, not a row — see the carve-out rules below and
[schema.md](schema.md).

### Add a slash command

Append to `NS.COMMANDS`. The dispatch in `settings/Slash.lua` **walks `NS.COMMANDS`** rather than
naming verbs, precisely so a new entry needs no second edit. Regenerate the README's command table
with `/wow-addon:sync-docs`.

### Add a locale string

Add the key to `locales/enUS.lua` and reference it through `L["…"]` — never a bare literal in panel
or chat code (`localization-§1`).

### Add a message

Pick the name `Ka0s_LootHistory_<Thing>`, give it **exactly one sender**, and register receivers on
their own target from `NS.NewBusTarget()` — never on the shared `NS.bus`/`NS.addon` as `self`. Record
it in [message-bus.md](message-bus.md) in the same change. The one-target rule is not style: see
below.

### Add a migration

Append **one entry** to the module-level `MIGRATIONS` array in `core/Database.lua:19` — never edit the
runner. Array order is run order, the runner stamps `schemaVersion` only *after* `apply` returns, and
every step must be idempotent. Anything needing a warm item cache cannot run inline at
`ADDON_LOADED`; hand it to the deferred repair instead. Full contract in [schema.md](schema.md).

## House rules

### File preamble

- Every source file begins `local addonName, NS = ...` and hangs its exports off the shared `NS`
  table (`NS.Compat`, `NS.Schema`, `NS.Collector`, …). There is no `_G[addonName]` and no global
  `LootHistory` — nothing in `core/`, `modules/`, `settings/`, `defaults/`, or `locales/` reaches
  the addon through the global table. `addonName` is used only where the loader needs it
  (`AceAddon:NewAddon(NS, addonName, …)` in `core/LootHistory.lua:4`).
- Module tables are created defensively: `NS.X = NS.X or {}` then `local X = NS.X`, so load order
  never depends on which file ran first.

### Settings: schema as the single source of truth

- `settings/Schema.lua` holds one row per user setting, and that table drives four surfaces at
  once — AceDB defaults, the panel widgets, the slash `get`/`set`/`list`/`reset` verbs, and the
  Defaults/Reset-all resets. Add a row and all four gain the setting; never write a parallel
  mutator for a field that already has a row.
- **Every setting mutation routes through `Schema:Set(path, value)`** (`settings/Schema.lua:223`).
  That seam is: look the row up → run its optional `validate` → `WritePath` a **deep copy** of the
  value → fire the row's `onChange`. The deep copy is load-bearing: without it a reset would alias
  the DB to a shared `default` table (e.g. `settings.excludedSources = {}`), and any later in-place
  mutation would poison the default for the rest of the session (see the comment at
  `settings/Schema.lua:223`).
- **Paths resolve against `NS.db.global`, not `.profile`** — storage is account-wide, so
  `Schema:Get`/`:Set` read and write `NS.db.global` directly (`settings/Schema.lua:240`, `:231`).
  Nothing in the addon touches `NS.db.profile`.
- **Carve-outs.** The Browser's window geometry (`settings.window` — point/size), its saved table view
  (`savedView`), the `blacklist`/`whitelist`/`currencyBlacklist` id lists (owned by `NS.Filters`,
  `modules/Filters.lua`), and the `settings.auction.priority` cascade (owned by `NS.AuctionPrice`) are
  runtime/data state, not user settings. They are persisted straight to
  `NS.db.global` and intentionally have **no** schema row and do **not** go through `Schema:Set` — a
  dynamic id-set or an ordered list can't be a schema widget. Don't "fix" this by adding rows for them. See
  [schema.md](schema.md) for the full carve-out list and the standards note.

### Messaging: a closed bus, one target per receiver

- Cross-module signaling uses `Ka0s_LootHistory_*` messages on `NS.bus` (the AceAddon object,
  `core/LootHistory.lua:6`) — `RecordAdded`, `HistoryChanged`, `SettingsChanged`. Each message has
  exactly one sender. Modules never reach into another module's tables; they listen for a message.
- **Receivers register on their own target from `NS.NewBusTarget()`** (`core/LootHistory.lua:20`),
  never on the shared `NS.bus`/`NS.addon` as `self`. CallbackHandler keys callbacks by
  `(message, target)`, so two consumers that share a target silently clobber each other — only the
  last registrant of a given message ever fires. The panel's live-stats refresh is the reference
  pattern: it grabs a private target and registers on it (`settings/Panel.lua:171`). Full contract
  in [message-bus.md](message-bus.md).

### Compat firewall

- Every deprecated or version-varying API call lives in `core/Compat.lua`; modules call
  `NS.Compat.X` and never the raw global. This is a Retail-only addon, so shims are gated by a
  direct `C_*`/global **presence check** (e.g. `if C_Map and C_Map.GetBestMapForUnit then …`) that
  degrades to `nil`/`false` when the API is absent — **not** by reading a game-flavor project id.
  There is no `WOW_PROJECT_ID` branching anywhere (`core/Compat.lua:5`). Details in
  [compat-layer.md](compat-layer.md).

### Table rendering: object pooling

- The history table pools row frames — filter → group → sort → slice → **bind** into a fixed set of
  reused rows in `modules/BrowserTable.lua`. Never create one frame per record (Ka0s standard standalone-windows);
  a 50k-row history must not spawn 50k frames.

### Collector hot-path upvalues

- The collector caches its gate config as file-level upvalues — `enabled`, `qualityThreshold`,
  `excludedSources`, `excludeQuestItems` (`modules/Collector.lua:9`) — so the `CHAT_MSG_LOOT`
  handler reads locals, not a chain of table lookups, on every loot line (Ka0s standard events-frames-taint-§7). They
  are refreshed by `Collector:RefreshUpvalues()` on `Ka0s_LootHistory_SettingsChanged`
  (`modules/Collector.lua:223`). The quest-item gate keys on the locale-independent item class
  (`Constants.ITEMCLASS_QUEST`), never the localized `itemType` string.

### Chat output: one shared secret-safe printer

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

### Session-only debug

- Debugging is a **session-only** flag, `NS.State.debug`, default `false`, reset every reload and
  **never persisted** (`core/State.lua:15`) — it is deliberately *not* a schema row. When off,
  `NS.Debug` is a zero-allocation no-op: it returns before building the argument table
  (`D.Debug`, `libs/LibKa0s/DebugLog.lua:633`). The console is LibKa0s-DebugLog-1.0's; the sink is
  bound bare — never as a method — onto `NS.Debug` by the `core/DebugLogSetup.lua` seam
  (`core/DebugLogSetup.lua:135`), which is also where `NS.DebugLog` is instantiated.
- The flag is independent of the console window's visibility. `/lh debug` toggles the window only;
  `/lh debug on|off` set the logging flag (capture runs even with the window closed,
  `settings/Schema.lua:301`); the header's `Debug: ON`/`OFF` control flips the same flag
  (`libs/LibKa0s/DebugLog.lua:473`). The flag stays the **host's** throughout — the descriptor hands
  the library `isEnabled`/`setEnabled` closures over `NS.State.debug` (`core/DebugLogSetup.lua:87`)
  so the slash verb, the panel and the console header all read one truth. The window's *visibility*
  is the separate `state.debugConsole` session-only schema row (`settings/Schema.lua:139`).
- All debug output goes through `NS.Debug(tag, fmt, ...)` and renders in the tagged format
  `<ts> | [<tag>] <content>` (`lib.FormatPlain`, `libs/LibKa0s/DebugLog.lua:114`; the colored console
  variant is `lib.FormatColored`, `:122`). `tag` is one short word, printed verbatim — no padding,
  no truncation.
- `NS.Debug` is **secret-safe** (events-frames-taint-§8): every `...` arg is routed through
  `NS.SafeToString` before it reaches `string.format`, so a combat-protected "secret" value logs as
  `<secret>` rather than crashing the sink. Because args arrive pre-stringified, its format strings
  use `%s` for every placeholder (never `%d`/`%f`).

### File size cap

- Source files are capped at **1500 LOC** (Ka0s standard layout-§1). The browser is deliberately split
  three ways to respect it — `Browser.lua` (window shell), `BrowserTable.lua` (the pooled table),
  `Analytics.lua` (Insights) — the largest, `Browser.lua`, sitting near ~1370 lines.

### Media: the shared LibKa0s payload, then Blizzard defaults

- **Art comes from `LibKa0s-Media-1.0` first, Blizzard second, and never from this addon.**
  `core/MediaSetup.lua` publishes `NS.Icon(name)`, `NS.MediaFont(name)` and
  `NS.IconMarkup(name, fallback, size)`; the paths point into the **vendored library payload**
  (`libs/LibKa0s/media/`), and they are **extensionless** — the client appends the extension, and a
  path carrying `.tga` is one of the two spellings that draw nothing (the other is `"|T" .. nil`,
  which is why `IconMarkup` demands a fallback). **`nil` is a real answer twice over**: no library,
  or no such name. Every call site therefore keeps the Blizzard rung it drew before, underneath —
  the client lock-atlas ladder in `modules/BrowserTable.lua`, and — for the dropdown chevron and
  the multi-select tick — the ladder inside `LibKa0s-Widgets-1.0` itself, which falls to
  `Arrow-Down-Up` and `UI-CheckBox-Check` when `core/WidgetsSetup.lua` hands it a nil path, `UI-Plus/MinusButton-Up` behind the group chevrons. **A mark this addon needs but the catalog lacks is added upstream in LibKa0s,
  never drawn locally** (anti-patterns #63): today that is a save/disk mark and a minus to pair
  with `add`, and until they exist the surfaces stay as they are.
- **The resize grip is Blizzard's on purpose, not by fallback.** The corner draws
  `UI-ChatIM-SizeGrabber-Up`/`-Highlight` with no catalog rung above it, because every other
  window in the collection draws that grabber and a window corner is not a place to be
  distinctive. The catalog's `resize` mark is a directionless two-headed arrow that reads as a
  control sitting ON the window rather than as part of its corner; it was tried here and
  reverted.
- **Everything else defaults to Blizzard-shipped media.** Text uses stock `GameFont*`
  font objects (and `STANDARD_TEXT_FONT` for the degraded close glyph in `core/CoreSetup.lua`);
  every remaining texture resolves to a Blizzard built-in or atlas (`Interface\Buttons\WHITE8X8`,
  `UI-Classes-Circles`, atlas `Options_HorizontalDivider`, …); borders are
  `WHITE8X8` drawn as 1px edges, colored from `Core.SKIN` via `B:ApplySkin`’s delegation to
  `NS.ApplySkin` (`modules/Browser.lua:76`, `core/CoreSetup.lua`); `modules/Browser.lua:20`’s own
  `SKIN` table carries only the tab colors and layout heights.
  The one non-Blizzard asset outside media is the addon's own logo on the settings landing page
  (`LOGO_PATH`, `settings/Panel.lua:23`, drawn at `:653`) — branding art, not a re-skinnable surface.
- **The monospace face is the library's now — the per-addon exception is retired.** The debug
  console and the export/debug copy boxes render in **JetBrains Mono**
  (`Constants.FONT_MONO`, resolved at file load from `NS.MediaFont(Constants.FONT_MONO_NAME)`).
  WoW still ships no monospace font object, so one still has to come from somewhere — but as of
  LibKa0s v1.10 it comes from the **library payload** rather than from this addon's own `media/`,
  and `media/fonts/` is deleted. The console gets the path as the DebugLog descriptor's `font`
  field (`core/DebugLogSetup.lua`); the export copy box sets it directly (`modules/Export.lua`).
  `core/MediaSetup.lua` registers the face with LibSharedMedia **at file load** — the registration
  used to run from `OnInitialize`, which is `ADDON_LOADED`, long after `core/Constants.lua` has
  resolved a path and `settings/Schema.lua` has built its rows. **The fallback is a real client
  font**: `SetFont` accepts a path to a file that is not there, fails to load it, and the text
  simply does not draw, so a degraded install gets `STANDARD_TEXT_FONT` and never a dead path.
- **No LSM media pickers, by design.** There is no font/texture/border user setting; LSM is used
  only for the registration above (no `Fetch`/`List`). Making the shared edge user-configurable is
  a tracked post-1.0.0 idea (`modules/Browser.lua:17`) that now belongs at the LibKa0s seam, not a
  gap to close now.

### Options UI: Blizzard canvas, never AceConfigDialog

- The settings panel is a Blizzard `Settings.RegisterCanvasLayoutCategory` parent (the landing page)
  plus **one** `RegisterCanvasLayoutSubcategory` body — General, a six-tab strip — built lazily from
  raw AceGUI widgets. There were three sub-pages until R6 folded Filters and AH Price into tabs. The
  canvas shell, the page registry, the lazy Defaults button, the five widget makers, the two-column
  flow engine and the schema composers are LibKa0s-Options-1.0's, wired in
  `settings/OptionsSetup.lua`; `settings/Panel.lua` registers the page and owns its bodies.
  **AceConfigDialog is never used for content** — there is no
  AceConfig/AceConfigDialog dependency in the addon at all. `P:Open` delegates to
  `O.OpenOptionsPanel` (`settings/Panel.lua:990`), whose combat gate lives in the library
  (`libs/LibKa0s/Options.lua:875`) and now also fires on a page's `OnShow`
  (`libs/LibKa0s/Options.lua:678`), so reaching a page straight from the Blizzard AddOns sidebar is
  refused too. It refuses rather than deferring-and-replaying, matching the Ka0s options-ui-§2 canvas
  pattern (the standalone browser window follows the separate standalone-windows non-secure pattern).

### Panel layout: options-ui-§6/§10 conformance

- **Right-edge inset (options-ui-§6/§8).** Cell-filling *action* buttons (Purge history, and the
  Master controls tab's Reset position / Reset all settings pair) inset
  to `BUTTON_PAIR_REL = 0.492`, not `0.5`, so their right border clears the ScrollFrame's clip. The
  constant is the library's (`libs/LibKa0s/Options.lua:106`), re-exported on the instance as
  `O.BUTTON_PAIR_REL` and read by this addon's own `makePairButton` (`settings/Panel.lua:35`).
  Label-inset controls (checkbox / dropdown / slider) already reserve that gutter and stay at `0.5` —
  they are immune (options-ui-§10). `BUTTON_PAIR_REL` is the single seam for that width; don't
  hard-code it per button.
- **Always-shown scrollbar (options-ui-§10).** `PatchAlwaysShowScrollbar` overrides AceGUI's stock
  `FixScroll` so the panel scrollbar is *always* visible and the 20px right gutter is *always*
  reserved (`libs/LibKa0s/OptionsScroll.lua:83`, applied to every ScrollFrame `O.EnsureScroll`
  creates, `libs/LibKa0s/Options.lua:506`). AceGUI would otherwise hide the bar and reclaim the gutter
  when content fits, shifting the body width between a short page and a long one. When there's
  nothing to scroll the override parks the thumb at the top and grays the bar inert, so the body
  width is identical across every subcategory. More on the panel in
  [settings-panel.md](settings-panel.md).

### Minimum-quality threshold: a non-monotonic Heirloom option (ratified exception)

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
