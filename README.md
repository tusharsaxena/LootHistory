# Ka0s Loot History

![wow](https://img.shields.io/badge/WoW-Midnight_12.0.7-orange)
![CurseForge Version](https://img.shields.io/curseforge/v/1530802)
![license](https://img.shields.io/badge/license-MIT-green)
[![Standard](https://img.shields.io/badge/Ka0s-WoW%20Addon%20Standard-blue)](https://github.com/tusharsaxena/WowAddonStandards)

![alt text](https://media.forgecdn.net/attachments/1788/918/loothistory-logo-jpg.jpg)

A passive loot-tracking addon for **World of Warcraft: Midnight**. Ka0s Loot History keeps a permanent, account-wide record of every item you loot (above a quality threshold you choose), works out **where each drop came from**, and gives you a standalone window to browse the full history and an Insights view to analyze it — so you always know what you picked up, when, and from what.

Every item you receive is captured passively from the loot stream and attributed to a **source** — a mob kill, a container, mail, a trade, the auction house, a quest, a vendor, a deconstruct action, or a Mythic+ chest — with a **confidence** marker for anything that had to be inferred. History is stored in the **account-wide** saved variables, so it's shared across every character and survives reloads and relogs.

| # | Source | Attributed from | Confidence |
| -- | ------------------------------------ | -------------------------------------------------- | ---------- |
| 1 | Kill | Looting a creature you tagged | Certain |
| 2 | Container | Opening a chest, lockbox, or lootable object | Certain |
| 3 | Mythic+ | End-of-run keystone / Great Vault chest | Certain |
| 4 | Quest | Quest turn-in rewards | Certain |
| 5 | Trade | Items received in a player trade | Certain |
| 6 | Mail | Items taken from the mailbox | Certain |
| 7 | Auction House | Won-auction mail from the AH | Certain |
| 8 | Vendor | Items bought from a vendor | Certain |
| 9 | Disenchant · Milling · Prospecting | The matching deconstruct / profession action | Certain |
| 10 | Other | No live source context at loot time | <strong>Inferred</strong> |

`Roll` and `Craft` are part of the source model (and the forward-compatible export contract) but have no live capture path yet, so they aren't offered as recording toggles.

## Screenshots

**_The History browser_**

![alt text](https://media.forgecdn.net/attachments/1788/920/loothistory-screenshot-01-png.png)

![alt text](https://media.forgecdn.net/attachments/1788/921/loothistory-screenshot-02-png.png)

**_Insights_**

![alt text](https://media.forgecdn.net/attachments/1788/922/loothistory-screenshot-03-png.png)

![alt text](https://media.forgecdn.net/attachments/1788/923/loothistory-screenshot-04-png.png)

**_Settings panel_**

![alt text](https://media.forgecdn.net/attachments/1788/924/loothistory-screenshot-05-png.png)

## Usage

Install the addon with the Addon Manager of your choice (or drop the folder into `Interface/AddOns`) and log in — recording starts immediately, with no setup required. All libraries are bundled in `libs/`, so there are no separate dependencies. Open the History window with the minimap button (left-click) or a slash command; inside it, click a column header to sort, use the filter bar to narrow results, pick a **Group by** to collapse rows, and switch to the **Insights** tab for analytics.

### Slash commands

`/lh` is the short form; `/loothistory` is a long-form alias that accepts the same subcommands.

| Command | What it does |
|---------|--------------|
| `/lh` | Show the command help index. |
| `/lh show` / `hide` / `toggle` | Open / close / flip the History window. |
| `/lh config` | Open the settings panel. |
| `/lh list` | Dump every schema-driven setting and its current value, grouped by section. |
| `/lh get <path>` | Print one setting's value (e.g. `/lh get settings.qualityThreshold`). |
| `/lh set <path> <value>` | Set a setting; flows through the same path the panel widget uses. Numbers clamp to range; dropdowns validate against the option list. |
| `/lh reset <path>` | Reset one setting to its default. |
| `/lh resetall` | Reset every setting to defaults. |
| `/lh purge` | Delete ALL recorded history (asks to confirm). |
| `/lh debug` | Toggle the session-only debug console window. `/lh debug on` / `off` sets the logging flag directly. |
| `/lh test` | Toggle a synthetic preview dataset for the table and Insights (session-only). |
| `/lh help` | Show the full command list. |

### Settings panel

Settings live at **Escape → Options → AddOns → Ka0s Loot History** (or `/lh config`). Everything is account-wide, and every control mirrors to the slash CLI (`/lh get` / `/lh set`). Two groups:

**Master Controls**

*   **Enable collection** — master toggle for recording. When off, no loot is captured; existing history is untouched and the window still works. Persists in saved variables.
*   **Hide minimap button** — show or hide the LibDBIcon minimap button. Left-click opens the window, right-click opens settings.
*   **Window scale** — scale the standalone browser window from 0.6× to 1.6×. Window position and size persist across sessions independently of this setting.

**Data Collection**

*   **Minimum quality** — only record items at or above this quality (Poor → Legendary; default **Common**). Applies at capture time — it never hides records already stored.
*   **Exclude quest items** — skip Quest-type items (the transient objects picked up during quests). **On by default**; uncheck it to record them too. Applies at capture time and keys on the item's class, so it works on any client language.
*   **Keep history for** — retention window. Records older than the chosen age are pruned once per session; choose **Always** to keep everything forever (default **30 days**). Retention is shared account-wide.
*   **Record data from** — per-source recording toggles. Unchecking a source stops recording it. Only sources with a live capture path appear here — `Roll` and `Craft` are enum'd for the export contract but not yet stamped, so they're hidden.

## How attribution works

Every record is built by a short pipeline:

1.  **Detect self-loot** — `CHAT_MSG_LOOT` is the authoritative signal that *you personally* received an item. The collector self-filters to the player and applies the minimum-quality gate, so other players' loot and sub-threshold junk are ignored.
2.  **Resolve the source** — peripheral game events stamp a short-lived *loot context* just before the loot line fires: the creature you looted, the container you opened, the mail / trade / vendor / auction-house interaction, the quest turn-in, or the Mythic+ keystone chest. The collector consumes whatever context is live at the moment of loot.
3.  **Fall back gracefully** — if no context is live, the drop is tagged **Other** with **Inferred** confidence rather than dropped. Everything attributed from a live signal is recorded as **Certain**.
4.  **Store one dense row** — the item link plus denormalized fields (id, name, quality, item level, bound, sell price, type), the resolved source, the zone, the character, and a timestamp go into the account-wide history, ready to filter, group, sort, and analyze.

The loot context is single-slot and short-lived by design — it deliberately survives multiple loot lines from one loot window, so a full container of drops all attribute to the same source.

## FAQ

| Question | Answer |
|----------|--------|
| Does this track loot for my whole account or just one character? | The whole account. There is one shared history log with a Character column, so every character contributes to and reads from the same data. |
| Does it record other players' loot? | No. Only items **you** receive are recorded — the collector self-filters the loot stream to the player. |
| What does the "confidence" marker mean? | Each drop is tagged **Certain** or **Inferred**. Most sources are attributed from a live game signal (a kill, opening a container, a Mythic+ chest, etc.); when no signal is available the drop falls back to an inferred **Other** source so nothing is lost. |
| Why don't I see Roll or Craft as recording toggles? | Those two sources exist in the data model (they're part of the forward-compatible export contract) but don't yet have a live capture path, so they aren't exposed as mute toggles. Every other source can be toggled under **Data Collection → Record data from**. |
| Will raising the quality threshold hide items I already looted? | No. The threshold only affects future captures. Existing records stay until they're pruned by retention or deleted manually. |
| How do I get rid of everything and start clean? | `/lh purge` deletes all recorded history (with a confirmation prompt). To keep history but reset options, use `/lh resetall`. |
| What is `/lh test` for? | It publishes a synthetic dataset to the History table and Insights so you can preview the UI without real loot. It's session-only and never written to disk. |
| Does history survive reloads and relogs? | Yes. Everything lives in the account-wide saved variables (`LootHistoryDB`) and is restored on every login. |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Nothing is being recorded. | (1) Check **Master Controls → Enable collection** is on. (2) The minimum quality may be filtering it — lower **Data Collection → Minimum quality** if you expect greys/whites. (3) The source may be muted under **Data Collection → Record data from**. (4) Quest items are dropped by default — uncheck **Data Collection → Exclude quest items** to record them. |
| The minimap button is gone. | It's hidden. Toggle **Master Controls → Hide minimap button** off, or open the window with `/lh toggle`. |
| A drop landed under the wrong source (or "Other"). | Attribution relies on a short-lived context stamped by peripheral events; when no signal is live at loot time the drop falls back to **Other** / **Inferred**. Enable the debug console with `/lh debug` to see how a capture was attributed. |
| The window is off-screen or the wrong size. | Position, size, and scale persist per account. Adjust **Master Controls → Window scale**, or drag the window back into view; it re-anchors on the next open. |
| I want to preview the UI but I have no loot yet. | Run `/lh test` to load a synthetic dataset into the table and Insights (session-only), then `/lh test` again to clear it. |
| I want to wipe everything and start over. | `/lh purge` clears all history (with confirmation). `/lh resetall` resets settings without touching history. |

## Issues and feature requests

All bugs, feature requests, and outstanding work are tracked at [https://github.com/tusharsaxena/LootHistory/issues](https://github.com/tusharsaxena/LootHistory/issues). Please file new reports there rather than as comments — the issue tracker is the single source of truth for the project's backlog.

## Testing

Unlike most addons, Ka0s Loot History ships a headless unit-test harness that targets WoW's Lua 5.1 runtime. From the repo root:

*   **Unit tests:** `lua tests/run.lua` — loads all source via `tests/loader.lua` against the WoW-API mocks in `tests/wow_mock.lua`.
*   **Lint:** `luacheck .` — must report **0 errors** before every commit (config in `.luacheckrc`).
*   **Syntax-check one file:** `luac -p path/to/file.lua`.

Run these before tagging a release or after refreshing libs / bumping `## Interface:`.

## Version History

| Version | Date | Highlights |
|---------|------|------------|
| 1.0.0 | 2026-07-12 | Initial release: passive `CHAT_MSG_LOOT` capture with source attribution and Certain/Inferred confidence; account-wide history with a Character column; standalone virtualized browser with multi-select filters (quality / type / source / zone / character), item-name search, Current/All scope, click-to-sort, group-by, and row actions (tooltip / link / delete); Insights analytics — stat & highlight cards plus range-scoped breakdowns by source, vendor value, quality, type, bound, character, hour, weekday, keystone level, and confidence, with top zones / items; schema-driven settings panel with full `/lh` slash parity, per-source muting, quality threshold, and retention; minimap button (LibDBIcon + LDB); forward-compatible `Database:Export()` seam for the v2 AI export. |

