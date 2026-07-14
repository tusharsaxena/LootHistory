# Slash dispatch

One ordered table drives the entire slash UX: `NS.COMMANDS` in `settings/Schema.lua:142`. Each row is `{ name, desc, fn }` — the same rows dispatch verbs and generate help text, so adding a command is a one-row append.

`/lh` and `/loothistory` are both registered through AceConsole's `RegisterChatCommand` (`settings/Slash.lua:36`) and dispatch to the same `Sl:OnSlash` handler — `/loothistory` is the long-form alias; all help text and docs use the short form.

The dispatcher (`Sl:OnSlash`, `settings/Slash.lua:44`):

- Bare `/lh` → `Sl:PrintHelp` (standard §7.4). Window display is **explicit** — bare `/lh` prints help, never opens the window; use `/lh toggle` or `/lh show|hide`.
- `/lh <known>` → runs that row's `fn(rest)`.
- `/lh <unknown>` → `unknown command '<verb>'` then the help index.

Only the verb is lower-cased (`verb:lower()`); the remainder (`rest`) keeps its original case, so schema paths like `settings.qualityThreshold` survive unchanged through `/lh set <path> <value>`. The `debug` handler additionally lower-cases its own `on`/`off` subargument.

Every chat line routes through the single shared printer **`NS.Print`** (`core/Util.lua`), which prepends the mandated **cyan** `NS.PREFIX` `|cff00ffff[LH]|r` banner (`core/Namespace.lua:12`) and secret-stringifies each argument (events-frames-taint-§8) so a combat-protected "secret" value logs as `<secret>` instead of raising. Every file that emits chat does `local print = NS.Print` — call sites never call the global `print()`, never hand-write the tag, and never `..`-concatenate args before the printer. `NS.Print` is reclaimed from AceConsole's `:Print` mixin after `NewAddon` (`core/LootHistory.lua`, architecture-§2). Cyan is the Ka0s house colour every addon shares for its chat tag (slash-commands-§4).

## Command table

| Verb | Action | Notes |
|---|---|---|
| *(none)* | Print the help / command index | `Sl:PrintHelp`; iterates `NS.COMMANDS`. |
| `show` | Open the window | `NS.Browser:Show()`. |
| `hide` | Close the window | `NS.Browser:Hide()`. |
| `toggle` | Toggle the window | `NS.Browser:Toggle()`. |
| `config` | Open the Settings panel | `NS.Panel:Open()`. See [settings-panel.md](settings-panel.md). |
| `version` | Print the addon version | `Sl:CliVersion`; reads the TOC `## Version` (constant fallback). |
| `get <path>` | Print one setting's current value | Schema-driven; `Sl:CliGet`. |
| `set <path> <value>` | Type-aware write to one setting | Schema-driven; `Sl:CliSet`. |
| `list` | Dump every schema-driven setting with its current value | Schema-driven; `Sl:CliList`. |
| `reset <path>` | Reset one setting to its default | Schema-driven; `Sl:CliReset`. |
| `resetall` | Reset **all** settings to defaults | `Sl:CliResetAll`. No confirmation; settings only (does not touch history). |
| `debug [on\|off]` | Toggle the debug console window; `on`/`off` set the logging flag | Session-only. See below. |
| `test` | Toggle a synthetic preview dataset (table + Insights) | Session-only; `BrowserTable:ToggleTestMode`. |
| `purge` | Delete ALL loot history | Confirm dialog. See below. |
| `help` | Print the generated command index | `Sl:PrintHelp`. |

## Generated help

`Sl:PrintHelp` (`settings/Slash.lua:59`) prints a version/alias header — `v<NS.version> slash commands (/loothistory is an alias for /lh)` — then one prefixed row per `NS.COMMANDS` entry: a gold command, an em-dash, and a white description. Because the help index and the dispatcher read the same table, they can never drift.

## Schema-reflecting CLI

`get` / `set` / `list` / `reset` are thin CLI mirrors of the settings Schema (`settings/Schema.lua`); they resolve against `NS.db.global` and route all writes through the `Schema:Set` seam, so a CLI write and a panel widget behave identically (validate → deep-copy → `onChange`). See [settings-panel.md](settings-panel.md) and [saved-variables.md](saved-variables.md).

`list`, `get`, and `set` share the Ka0s canonical output shape (slash-commands-§5), produced by two shared helpers so the three can never drift: `Sl.FormatSchemaValue(row, v)` — the type-aware, schema-driven value formatter (a row's optional `fmt` formats numbers, e.g. `windowScale` `%.2fx` → `1.00x`; booleans → `true`/`false`; a table setting → a sorted `{a, b}` key set or `(none)`; enums stay raw) — and `Sl.FormatKV(path, valueStr)` — the coloured `key = value` line (gold key, white value, default separator).

- **`get <path>`** — `Sl:CliGet`. Prints the single-line `FormatKV` echo for the path. A missing/empty argument prints `Usage: /lh get <path>`; an unknown path prints `Setting not found: <path>`.
- **`set <path> <value>`** — `Sl:CliSet`. Looks up the row with `Schema:FindRow` (unknown → `Setting not found: <path>`). Coerces the raw string by the row's declared `type`: `number` via `tonumber` (rejects non-numbers), `boolean` from `true`/`1`/`on`/`yes`. The coerced value goes to `Schema:Set`, which validates and fires the row's `onChange`; on failure it prints `error: <err>`. On success it **reads back the stored value** and echoes it via `FormatKV`, so the line reflects any clamping/coercion.
- **`list`** — `Sl:CliList` (via the pure, testable `Sl:BuildListLines`). Prints a green `Available settings` header, then one azure `[group]` header per schema group in a declared order (LootHistory's single-panel section headers stand in for the standard's `[page]` headers), then an indented `FormatKV` row per setting. New settings appear automatically as schema rows are added.
- **`reset <path>`** — `Sl:CliReset` (`settings/Slash.lua:183`). Resolves the row's default with `Schema:Default` (deep-copied), writes it via `Schema:Set`, and prints `<path> reset to <default>`. Rejects an unknown path.
- **`resetall`** — `Sl:CliResetAll` (`settings/Slash.lua:192`). Walks every schema row, writing each back to its `default`, and prints `all settings reset to defaults`. This is settings-only and **has no confirmation prompt** — it does not delete recorded history.

## Session-only `debug`

The `debug` handler (`settings/Schema.lua:153`) drives the debug console independently of the logging flag:

- `/lh debug` → `DebugLog:Toggle()` — flips the console **window** only; the logging flag is untouched.
- `/lh debug on` / `/lh debug off` → `DebugLog:SetEnabled(true/false)` — sets the session-only logging flag `NS.State.debug`. Capture runs even with the window closed.

The flag is never persisted to SavedVariables and resets to off on every `/reload`. `debug` is deliberately **not** a Schema row (`settings/Schema.lua:67`). See [testing.md](testing.md) for the debug console and the `/lh test` synthetic dataset.

## Confirm dialogs

Two `StaticPopupDialogs` entries are registered once at load, in-game only (`settings/Slash.lua:7`):

- **`KA0S_LOOTHISTORY_PURGE`** — the confirm behind `/lh purge`. The `purge` command calls `StaticPopup_Show("KA0S_LOOTHISTORY_PURGE")` (`settings/Schema.lua:166`); accepting runs `Database:Purge()` and prints `history purged`. If `StaticPopup_Show` is unavailable (headless), it purges directly. The Settings panel's "Purge history" button raises the same popup (`settings/Panel.lua:347`).
- **`KA0S_LOOTHISTORY_RESETALL`** — the confirm behind the Settings panel's **"Reset All"** button (`settings/Panel.lua:466`), *not* the `resetall` slash verb. Accepting runs `Sl:ResetEverything` (`settings/Slash.lua:30`), which wipes history (`Database:Purge`) **and** restores every setting (`CliResetAll`), then refreshes the panel. This is the destructive both-at-once reset; the `/lh resetall` verb only resets settings and prompts for nothing.

See [saved-variables.md](saved-variables.md) for what `purge` and the reset actions clear in `LootHistoryDB.global`.
