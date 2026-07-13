# Slash dispatch

One ordered table drives the entire slash UX: `NS.COMMANDS` in `settings/Schema.lua:140`. Each row is `{ name, desc, fn }` — the same rows dispatch verbs and generate help text, so adding a command is a one-row append.

`/lh` and `/loothistory` are both registered through AceConsole's `RegisterChatCommand` (`settings/Slash.lua:39`) and dispatch to the same `Sl:OnSlash` handler — `/loothistory` is the long-form alias; all help text and docs use the short form.

The dispatcher (`Sl:OnSlash`, `settings/Slash.lua:47`):

- Bare `/lh` → `Sl:PrintHelp` (standard §7.4). Window display is **explicit** — bare `/lh` prints help, never opens the window; use `/lh toggle` or `/lh show|hide`.
- `/lh <known>` → runs that row's `fn(rest)`.
- `/lh <unknown>` → `unknown command '<verb>'` then the help index.

Only the verb is lower-cased (`verb:lower()`); the remainder (`rest`) keeps its original case, so schema paths like `settings.qualityThreshold` survive unchanged through `/lh set <path> <value>`. The `debug` handler additionally lower-cases its own `on`/`off` subargument.

Every chat line is prefixed with `NS.PREFIX` — a green `|cff33ff99[LH]|r` banner (`core/Namespace.lua:9`).

## Command table

| Verb | Action | Notes |
|---|---|---|
| *(none)* | Print the help / command index | `Sl:PrintHelp`; iterates `NS.COMMANDS`. |
| `show` | Open the window | `NS.Browser:Show()`. |
| `hide` | Close the window | `NS.Browser:Hide()`. |
| `toggle` | Toggle the window | `NS.Browser:Toggle()`. |
| `config` | Open the Settings panel | `NS.Panel:Open()`. See [settings-panel.md](settings-panel.md). |
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

`Sl:PrintHelp` (`settings/Slash.lua:62`) prints a version/alias header — `v<NS.version> slash commands (/loothistory is an alias for /lh)` — then one prefixed row per `NS.COMMANDS` entry: a gold command, an em-dash, and a white description. Because the help index and the dispatcher read the same table, they can never drift.

## Schema-reflecting CLI

`get` / `set` / `list` / `reset` are thin CLI mirrors of the settings Schema (`settings/Schema.lua`); they resolve against `NS.db.global` and route all writes through the `Schema:Set` seam, so a CLI write and a panel widget behave identically (validate → deep-copy → `onChange`). See [settings-panel.md](settings-panel.md) and [saved-variables.md](saved-variables.md).

- **`get <path>`** — `Sl:CliGet` (`settings/Slash.lua:72`). Prints `<path> = <value>` via `Schema:Get`. With no path it falls through to `CliList`.
- **`set <path> <value>`** — `Sl:CliSet` (`settings/Slash.lua:79`). Looks up the row with `Schema:FindRow`; rejects an unknown path. Coerces the raw string by the row's declared `type`: `number` via `tonumber` (rejects non-numbers), `boolean` from `true`/`1`/`on`/`yes`. The coerced value goes to `Schema:Set`, which validates and fires the row's `onChange`; on failure it prints `error: <err>`.
- **`list`** — `Sl:CliList` (`settings/Slash.lua:105`). Iterates `Schema.Schema` and prints `<path> = <value>` for each row. New settings appear automatically as schema rows are added.
- **`reset <path>`** — `Sl:CliReset` (`settings/Slash.lua:112`). Resolves the row's default with `Schema:Default` (deep-copied), writes it via `Schema:Set`, and prints `<path> reset to <default>`. Rejects an unknown path.
- **`resetall`** — `Sl:CliResetAll` (`settings/Slash.lua:121`). Walks every schema row, writing each back to its `default`, and prints `all settings reset to defaults`. This is settings-only and **has no confirmation prompt** — it does not delete recorded history.

## Session-only `debug`

The `debug` handler (`settings/Schema.lua:150`) drives the debug console independently of the logging flag:

- `/lh debug` → `DebugLog:Toggle()` — flips the console **window** only; the logging flag is untouched.
- `/lh debug on` / `/lh debug off` → `DebugLog:SetEnabled(true/false)` — sets the session-only logging flag `NS.State.debug`. Capture runs even with the window closed.

The flag is never persisted to SavedVariables and resets to off on every `/reload`. `debug` is deliberately **not** a Schema row (`settings/Schema.lua:65`). See [testing.md](testing.md) for the debug console and the `/lh test` synthetic dataset.

## Confirm dialogs

Two `StaticPopupDialogs` entries are registered once at load, in-game only (`settings/Slash.lua:10`):

- **`KA0S_LOOTHISTORY_PURGE`** — the confirm behind `/lh purge`. The `purge` command calls `StaticPopup_Show("KA0S_LOOTHISTORY_PURGE")` (`settings/Schema.lua:164`); accepting runs `Database:Purge()` and prints `history purged`. If `StaticPopup_Show` is unavailable (headless), it purges directly. The Settings panel's "Purge history" button raises the same popup (`settings/Panel.lua:335`).
- **`KA0S_LOOTHISTORY_RESETALL`** — the confirm behind the Settings panel's **"Reset All"** button (`settings/Panel.lua:454`), *not* the `resetall` slash verb. Accepting runs `Sl:ResetEverything` (`settings/Slash.lua:33`), which wipes history (`Database:Purge`) **and** restores every setting (`CliResetAll`), then refreshes the panel. This is the destructive both-at-once reset; the `/lh resetall` verb only resets settings and prompts for nothing.

See [saved-variables.md](saved-variables.md) for what `purge` and the reset actions clear in `LootHistoryDB.global`.
