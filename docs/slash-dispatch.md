# Slash dispatch

One ordered table drives the entire slash UX: `NS.COMMANDS` in `settings/Schema.lua:213`. Each row is a **positional triple** — `{ name, description, handler }`, the shape `LibKa0s-Slash-1.0` reads — and the same rows dispatch verbs, generate the chat help *and* render the settings landing page, so adding a command is still a one-row append.

The table stays the **host's** and is passed into the library rather than owned by it, and that is the load-bearing decision in this seam rather than squeamishness: the settings landing page renders these same rows (`settings/Panel.lua:608`), so if the slash major owned the table, the options major drawing that page would have to resolve the slash major to read it — a real dependency cycle between two majors at load time. The table crossing between them as plain data is what keeps them independent. Each handler takes the rest of the line verbatim (never a `self`), so the seven verbs that are genuinely this addon's — `show` / `hide` / `toggle` / `config` / `debug` / `test` / `purge` — never leave the host, and adopting the library could not break them.

`/lh` and `/loothistory` are both registered through AceConsole's `RegisterChatCommand` (`Sl:Register`, `settings/Slash.lua:238`) and dispatch to the same `Sl:OnSlash` handler — `/loothistory` is the long-form alias; all help text and docs use the short form.

The dispatcher is the library's (`libs/LibKa0s/Slash.lua:586`), bound onto `NS.Slash` by name at `settings/Slash.lua:208` because ~20 call sites across the schema table, the settings panel and the suite already reach for `NS.Slash:CliList()` and friends:

- Bare `/lh` → `Sl:PrintHelp` (standard slash-commands-§4). Window display is **explicit** — bare `/lh` prints help, never opens the window; use `/lh toggle` or `/lh show|hide`.
- `/lh <known>` → runs that row's `entry[3](rest)`.
- `/lh <unknown>` → `unknown command '<verb>'` then the help index.

Only the verb is lower-cased; the remainder (`rest`) keeps its original case *and* its internal spacing, so schema paths like `settings.qualityThreshold` survive unchanged through `/lh set <path> <value>`. The `debug` handler additionally lower-cases its own `on`/`off` subargument (`settings/Schema.lua:227`).

Every chat line routes through the single shared printer **`NS.Print`**, published from `LibKa0s-Core-1.0` in `core/CoreSetup.lua:97`, which prepends the mandated **cyan** `NS.PREFIX` `|cff00ffff[LH]|r` banner (`core/Namespace.lua:10`) and secret-stringifies each argument (events-frames-taint-§8) so a combat-protected "secret" value logs as `<secret>` instead of raising. Every file that emits chat does `local print = NS.Print` — call sites never call the global `print()`, never hand-write the tag, and never `..`-concatenate args before the printer. The dispatcher reaches it **late-bound** (`print = function(line) NS.Print(line) end`, `settings/Slash.lua:176`) so it survives `core/LootHistory.lua`'s reclaim of `NS.Print` from AceConsole's `:Print` mixin (architecture-§2). Cyan is the Ka0s house color every addon shares for its chat tag (slash-commands-§4).

## What is the library's, and what stays here

The dispatcher, the help header, the help rows, `LandingRows`, `BuildListLines`, `CliList` / `CliGet` / `CliSet` / `CliReset` / `CliVersion` (and the `CliResetAll` the host wrapper below delegates to), the two formatters (`lib.FormatRow`, `lib.FormatKV`) and the type-aware parser are all `LibKa0s-Slash-1.0`'s, wired through one `lib:New(descriptor)` call at `settings/Slash.lua:170`. The descriptor points the schema verbs at this addon's single write seam (`get`/`set`/`findRow`/`allRows`/`applyDefault` → `NS.Schema`), overrides `groupKey` to `row.group` (this addon is single-panel and has no concept of the library's default `row.page`), and passes the `format` hook.

Host-owned, and each for a reason:

- the six `StaticPopupDialogs` confirms (`settings/Slash.lua:7`) — this addon's destructive gates, never the library's;
- `Sl:ResetEverything` (`settings/Slash.lua:85`) — the total-reset *composition* behind the panel's "Reset Everything" button (named apart from the `resetall` verb on purpose — it also purges history);
- `Sl:CliResetAll` (`settings/Slash.lua:233`) — a **wrapper**, not a re-export, because the `blacklist` / `whitelist` / `currencyBlacklist` id-lists are a storage carve-out with no schema row, so the library's row walk cannot see them;
- `Sl.FormatSchemaValue` (`settings/Slash.lua:113`) — passed as the descriptor's `format` hook (Slash **minor 5**), holding **only** the `type = "table"` branch and handing everything else straight back to `lib.FormatValue`;
- `Sl:Register` (`settings/Slash.lua:238`) — the chat-command registration.

If the library is absent, `settings/Slash.lua`'s `if not lib then` branch degrades rather than errors: `/lh` is still registered, the seven host verbs still dispatch through the same positional walk, and every library-owned verb answers `NS.LIBKA0S_MISSING` plus its own consequence — *"…, so the slash command interface is unavailable."*

A **bare `/lh` prints help on that path too** (slash-commands-§3), listing the seven verbs that still work — `show`, `hide`, `toggle`, `config`, `debug`, `test`, `purge` — under a header carrying the shared cause clause. The list is rendered by **subtraction** from `NS.COMMANDS` (the seven verbs that went through the library are named in one set), so adding a host verb cannot leave the degraded help behind. The stub also exports `HelpHeader`, which the live seam publishes and it did not: `tests/test_libka0s.lua`'s `Kit.assertSurfaceParity` case is what now holds the two surfaces to the same member set.

## Command table

| Verb | Action | Notes |
|---|---|---|
| *(none)* | Print the help / command index | `Sl:PrintHelp`; iterates `NS.COMMANDS`. |
| `show` | Open the window | `NS.Browser:Show()`. |
| `hide` | Close the window | `NS.Browser:Hide()`. |
| `toggle` | Toggle the window | `NS.Browser:Toggle()`. |
| `config` | Open settings | `NS.Panel:Open()`. See [settings-panel.md](settings-panel.md). |
| `version` | Print addon version | `Sl:CliVersion`; reads the TOC `## Version` (constant fallback). |
| `get <path>` | Get a setting value | Schema-driven; `Sl:CliGet`. |
| `set <path> <value>` | Set a setting value (type-aware) | Schema-driven; `Sl:CliSet`. |
| `list` | List all settings with their current values | Schema-driven; `Sl:CliList`. |
| `reset <path>` | Reset one setting | Schema-driven; `Sl:CliReset`. |
| `resetall` | Reset **all** settings | `Sl:CliResetAll`. No confirmation; settings + the three id-lists, non-destructive (does not touch history, savedView, or window geometry). |
| `debug [on\|off]` | Toggle window; `on`/`off` set logging | Session-only. See below. |
| `test` | Toggle a synthetic preview dataset (table + Insights) | Session-only; `BrowserTable:ToggleTestMode`. |
| `purge` | Delete ALL loot history (asks to confirm) | Confirm dialog. See below. |
| `help` | Show this help | `Sl:PrintHelp`. |

## Generated help

`Sl:PrintHelp` prints the header from `Dispatcher:HelpHeader()` (`libs/LibKa0s/Slash.lua:462`) — version, an **em dash**, then the alias clause composed from the descriptor's `slashAliases`:

```
[LH] v1.2.0 — slash commands (|cFFFFFF00/loothistory|r is an alias for |cFFFFFF00/lh|r)
```

then one prefixed row per `NS.COMMANDS` entry, each **indented two spaces** so it sits under that header (`Sl:HelpRows`, `libs/LibKa0s/Slash.lua:456`). A row is a gold command, an em dash with a **single space either side**, and a white description — upper-case hex, because that is the library's:

```
[LH]   |cFFFFFF00/lh show|r — |cFFFFFFFFOpen the window|r
```

**Convergence — one command-row formatter, chat and panel.** The settings landing page used to carry its own version of that row: double spaces around the em dash, the dash itself wrapped in white, the description left bare — divergent from the chat help two files away for no reason anyone recorded. Both now render through `lib.FormatRow` (`libs/LibKa0s/Slash.lua:68`) via `Sl:LandingRows` (`settings/Slash.lua:225`), which is the chat form minus the indent — a leading indent reads as a mistake on a panel label, not as structure. User-visible on the landing page: single spaces, no color span on the dash, the description now white. Deliberate; do not "fix" it back (`docs/pending/LEDGER.md`, LIBKA0S-09).

Because the help index, the landing page and the dispatcher all read the same table, they can never drift.

## Schema-reflecting CLI

`get` / `set` / `list` / `reset` are thin CLI mirrors of the settings Schema (`settings/Schema.lua`); they resolve against `NS.db.global` and route all writes through the `Schema:Set` seam, so a CLI write and a panel widget behave identically (validate → deep-copy → `onChange`). See [settings-panel.md](settings-panel.md) and [schema.md](schema.md).

`list`, `get`, `set` and `reset` share the Ka0s canonical output shape (slash-commands-§5), produced by two shared helpers so the four can never drift:

- **`Sl.FormatKV(path, valueStr)`** — re-exported straight from `lib.FormatKV` (`libs/LibKa0s/Slash.lua:74`): the colored `key = value` line, gold key, white value, no trailing colon. Identical in shape to what this file used to own, with the hex digits now in the library's **upper** case — `|cFFFFFF00settings.enabled|r = |cFFFFFFFFtrue|r`.
- **`Sl.FormatSchemaValue(row, v)`** — the type-aware value renderer. `type = "table"` is not one of the library's four types, so `lib.FormatValue` would fall through to Core's `SafeToString`, probe `table.concat`, fail, and answer `<secret>` — telling a user that `settings.excludedSources` is combat-protected. That one branch lives here (a sorted `{KILL, MAIL}` key set, or `(none)` when empty) and everything else is handed back to `lib.FormatValue` (`libs/LibKa0s/Slash.lua:138`): a row's optional `fmt` formats numbers (`windowScale` `%.2fx` → `1.00x`), booleans → `true`/`false`, enums stay raw. It is wired in as the descriptor's `format` hook, so the CLI and the settings panel cannot render the same value two ways.

- **`get <path>`** — `Sl:CliGet`. Prints the single-line `FormatKV` echo for the path. A missing argument prints `Usage: /lh get <path>`; an unknown path prints `Setting not found: <path>`.
- **`set <path> <value>`** — `Sl:CliSet`. Looks up the row (unknown → `Setting not found: <path>`), parses the raw text by the row's declared `type` through `lib.ParseValue` (see below), writes it via `Schema:Set` — which validates and fires the row's `onChange` — then **re-reads the stored value** and echoes it via `FormatKV`, which is the only way a clamp is visible to the user. A missing argument prints `Usage: /lh set <path> <value>  (try /lh list)`.
- **`list`** — `Sl:CliList` (via the pure, testable `Sl:BuildListLines`, `libs/LibKa0s/Slash.lua:489`). Prints a green `|cff33ff99Available settings|r` header, then one azure `  |cff3399ff[group]|r` header per schema group **in declaration order** (LootHistory's single-panel section headers stand in for the standard's `[page]` headers, via the descriptor's `groupKey`), then a four-space-indented `FormatKV` row per setting. New settings appear automatically as schema rows are added. These two headers keep their **lower**-case hex deliberately — only the command-row and key/value formatters converged on upper case, and recasing the rest would be a user-visible change nobody asked for.
- **`reset <path>`** — `Sl:CliReset` (`libs/LibKa0s/Slash.lua:554`). Resolves and applies the row's default through `Schema:Default` (deep-copied) + `Schema:Set`, then echoes the **same `FormatKV` line** every list row, get echo and set echo uses — `|cFFFFFF00settings.excludedSources|r = |cFFFFFFFF(none)|r`, not a bespoke `<path> reset to <value>` sentence. The path is not lower-cased (folding it would resolve a setting the user did not name). A missing argument prints `Usage: /lh reset <path>`; an unknown path prints `Setting not found: <path>`.
- **`resetall`** — `Sl:CliResetAll`. Clears the `blacklist` / `whitelist` / `currencyBlacklist` id-lists via `Filters:ClearAll` **first**, then walks every schema row back to its default and acknowledges `All settings reset to defaults` (capital A, the library's string), so the last line printed reads as the summary of everything that happened. This is **non-destructive** (**no confirmation prompt**) — it does not delete recorded history, and leaves `savedView` / window geometry alone. See [schema.md](schema.md#reset-semantics).

**Convergence — `reset` takes a path, at no cost.** The library's `reset` is deliberately path-scoped with no page-shaped form (a page is a property of a settings panel, and every such panel already carries a Defaults button). This addon was already path-scoped and already had `resetall`, so nothing was lost and no confirmation popup had to be re-anchored: the destructive verb here is `/lh purge` (and the panel's "Reset Everything"), both still routed through `StaticPopup_Show`. A page name is refused rather than silently resetting a section — `/lh reset Master Controls` answers `Setting not found: Master`.

### The type-aware parser

`lib.ParseValue` (`libs/LibKa0s/Slash.lua:332`) replaces bare coercion, on the principle that a CLI which silently accepts a value it cannot honor is worse than one that refuses. Failure prints `Invalid value for <path>` and then the reason on a two-space-indented second line; the old value survives untouched.

- **`bool`** — `true`/`1`/`on`/`yes` and `false`/`0`/`off`/`no`. Anything else is **refused** rather than silently stored as `false`: `/lh set settings.enabled maybe` → `Invalid value for settings.enabled` / `  expected true/false/on/off/1/0/yes/no`.
- **`number`, plain (a `Slider` row)** — **clamped** to the row's `min`/`max`, because a user typing a scale larger than the panel allows means "as large as it goes". `/lh set settings.windowScale 99` stores `1.6` and echoes `settings.windowScale = 1.60x`.
- **`number`, enumerated (a `Dropdown` row with `values`)** — **constrained**, not clamped: clamping would land between two entries and the renderer would have no label for what is stored. `/lh set settings.qualityThreshold 9` → `Invalid value for settings.qualityThreshold` / `  allowed values: 0, 1, 2, 3, 4, 5, 7`.
- **`table`** (the two set-valued rows, `settings.excludedSources` and `settings.auction.capture`) — readable but not writable from the CLI; the parser answers `unknown setting type 'table'`. They are edited from the Data Collection / AH Price pages of the settings panel.

## Session-only `debug`

The `debug` handler (`settings/Schema.lua:224`) drives the debug console independently of the logging flag:

- `/lh debug` → `DebugLog:Toggle()` — flips the console **window** only; the logging flag is untouched.
- `/lh debug on` / `/lh debug off` → `DebugLog:SetEnabled(true/false)` — sets the session-only logging flag `NS.State.debug`. Capture runs even with the window closed.

`NS.DebugLog` is `LibKa0s-DebugLog-1.0`, wired in `core/DebugLogSetup.lua`. The flag is never persisted to SavedVariables and resets to off on every `/reload`; the logging flag is deliberately **not** a Schema row (`settings/Schema.lua:116`), while the console **window's** visibility *is* — the session-only `state.debugConsole` row. See [testing.md](testing.md) for the debug console and the `/lh test` synthetic dataset.

## Confirm dialogs

Six `StaticPopupDialogs` entries are registered once at load, in-game only (`settings/Slash.lua:7`):

- **`KA0S_LOOTHISTORY_PURGE`** — the confirm behind `/lh purge`. The `purge` command calls `StaticPopup_Show("KA0S_LOOTHISTORY_PURGE")` (`settings/Schema.lua:239`); accepting runs `Database:Purge()` and prints `history purged`. If `StaticPopup_Show` is unavailable (headless), it purges directly. The Settings panel's "Purge history…" button raises the same popup (`settings/Panel.lua:96`).
- **`KA0S_LOOTHISTORY_RESETALL`** — the confirm behind the Settings panel's **"Reset Everything"** button, *not* the `resetall` slash verb. (The dialog key keeps its historical name; the button label does not, because one name for two different effects is what the label change fixes.) Accepting runs `Sl:ResetEverything` (`settings/Slash.lua:85`), which wipes history (`Database:Purge`), restores every setting **and** clears the filter lists (`CliResetAll`), then drops `savedView` to stock (`Browser:ResetView`) and recenters the window (`Browser:ResetWindow`), then refreshes the panel. This is the total destructive reset; the `/lh resetall` verb only resets settings + the id-lists and prompts for nothing.
- **`KA0S_LOOTHISTORY_CLEAR_BLACKLIST`** / **`KA0S_LOOTHISTORY_CLEAR_WHITELIST`** / **`KA0S_LOOTHISTORY_CLEAR_CURRENCY`** — the confirms behind the Filters sub-page's per-list **"Clear all"** buttons (item blacklist, whitelist, and the currency blacklist). Accepting calls `Filters:ClearList(<list>)`; the panel refreshes via its `HistoryChanged` listener. Non-destructive — clearing a list only empties its id-set; stored history is untouched (blacklisting affected future captures only).
- **`KA0S_LOOTHISTORY_CLEAR_FILTERS`** — the confirm behind the Filters subcategory's top-right **"Defaults"** button (its default state is empty lists). Accepting calls `Filters:ClearAll()`, clearing the blacklist, whitelist, **and** currency blacklist in one action; the panel refreshes via the same `HistoryChanged` listener. Non-destructive — stored history is untouched.

See [schema.md](schema.md) for what `purge` and the reset actions clear in `LootHistoryDB.global`.
