# Ka0s Loot History

![WoW](https://img.shields.io/badge/WoW-Midnight_12.0.7-purple)
![CurseForge Version](https://img.shields.io/curseforge/v/1607560)
![License](https://img.shields.io/badge/License-MIT-orange)
[![Standard](https://img.shields.io/badge/Ka0s-WoW%20Addon%20Standard-yellow)](https://github.com/tusharsaxena/WowAddonStandards)
![Tests](https://img.shields.io/badge/Tests-241%2F241_passing-green)

> Maintainer tooling lives in [`tools/`](tools/) (dev-only, not shipped) — see [`tools/README.md`](tools/README.md).

![alt text](https://media.forgecdn.net/attachments/1788/918/loothistory-logo-jpg.jpg)

Ka0s Loot History is a passive loot tracker for **World of Warcraft: Midnight**. It quietly records every item you pick up and works out where each one came from — a kill, a chest, the mailbox, the auction house, and so on. Open its window any time to browse your full loot history, or switch to the **Insights** tab to see it broken down by source, value, quality, and more.

Your history is account-wide, so every character adds to and reads from the same log, and it survives reloads and logouts. You pick a minimum quality to record, and anything below it is ignored.

Every item you pick up is filed under a source:

| Source | What it covers |
| ------ | -------------- |
| Kill | Looting a creature you killed |
| Container | Opening a chest, lockbox, or lootable object |
| Mythic+ | End-of-run and Great Vault chests |
| Quest | Quest rewards |
| Trade | Items received in a trade |
| Mail | Items taken from the mailbox |
| Auction House | Items won at auction |
| Vendor | Items bought from a vendor |
| Disenchant / Milling / Prospecting | Items produced by those actions |
| Other | Anything that arrived with no clear source |

Most items are filed with certainty, straight from what the game reported. When there's no clear signal, the item is still recorded — filed under **Other** and marked as a best guess rather than dropped. Each row shows whether its source is **Certain** or **Inferred** so you can tell the two apart.

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

Install it like any other addon and log in. Recording starts right away — there's nothing to set up. Open the History window by left-clicking the minimap button or typing `/lh`. Click a column header to sort, use the filter bar to narrow the list, pick a **Group by** to collapse rows together, and switch to the **Insights** tab for the analytics view. The filter bar is **shared** between both tabs, so the same narrowing applies to the table and the charts at once — you always know which slice of your loot you're looking at.

The **Export** button follows the tab you're on: on **History** it copies your loot rows out as CSV (everything or just the current filtered view); on **Insights** it copies the analytics summary as a CSV that mirrors the charts. Don't want an item tracked going forward? Right-click its row and choose **Blacklist item** — the clicked row stays put (nothing is deleted or hidden), but future loots of that item are skipped. Delete a row from the table if you want it gone.

### Export to AI

The Export window also has an **Export to AI** button. It copies a ready-made prompt that you paste into a web-enabled AI chat — **Claude, ChatGPT, or Gemini** — to get back a single, self-contained HTML page: a gorgeous, WoW-themed report of your loot with an interactive history browser, an Insights dashboard, and an AI-written "What the data says" analysis. Copy the prompt (Ctrl+C), paste it into the AI, and it replies with the HTML file; in Claude you can publish it as an Artifact to get a shareable link.

Unlike Export to CSV, Export to AI always bundles **both** your History and Insights (one report shows everything), and it honours the **Data Set** choice — all data, or just your current filtered view. The **?** beside the button explains the steps in-game. The AI tool needs **web access enabled**: the prompt links to a design guide the AI reads to style the report.

> Example report: _(link coming soon)_

### Slash commands

`/lh` is the short form; `/loothistory` does exactly the same thing.

| Command | What it does |
|---------|--------------|
| `/lh` | Show the list of commands. |
| `/lh show` / `hide` / `toggle` | Open, close, or flip the History window. |
| `/lh config` | Open the settings panel. |
| `/lh version` | Show the addon version. |
| `/lh list` | List every setting and its current value. |
| `/lh get <path>` | Show one setting's value (e.g. `/lh get settings.qualityThreshold`). |
| `/lh set <path> <value>` | Change a setting. Out-of-range numbers are clamped; invalid choices are rejected. |
| `/lh reset <path>` | Reset one setting to its default. |
| `/lh resetall` | Reset every setting to its default. |
| `/lh purge` | Delete all recorded history (asks you to confirm first). |
| `/lh debug` | Toggle the debug console window. `/lh debug on` / `off` sets it directly. |
| `/lh test` | Load a sample dataset into the window and Insights so you can preview them. Run it again to clear. |
| `/lh help` | Show the full command list. |

### Settings panel

Settings live at **Escape → Options → AddOns → Ka0s Loot History** (or `/lh config`). Everything applies to your whole account, and every option can also be changed from chat with `/lh get` and `/lh set`. The **General** page has three groups (below), and a separate **Filters** page manages the blacklist/whitelist:

**Master Controls**

*   **Enable collection** — the master on/off switch for recording. Turn it off and nothing new is recorded; your existing history stays, and the window still works.
*   **Hide minimap button** — show or hide the minimap button. Left-click it to open the window, right-click for settings.
*   **Window scale** — resize the History window from 0.6× to 1.6×. Its position and size are remembered separately from this.

**Data Collection**

*   **Minimum quality** — only record items at or above this quality (default **Common**). Raising it never removes items you've already recorded.
*   **Exclude quest items** — skip the temporary items you pick up during quests. **On by default**; uncheck it to record them too.
*   **Keep history for** — how long to keep records. Older ones are cleared out once per session; choose **Always** to keep everything (default **30 days**).
*   **Record data from** — turn individual sources on or off. Unchecking a source stops it being recorded. Only the sources the addon can actually detect appear here.

**Auction House Price**

*   **Enable AH pricing** — the master on/off switch for reading prices from Auctionator, TSM, and OribosExchange. Turn it off and every drop's value falls back to its vendor sell price.
*   **Capture these prices** — pick exactly which prices to gather at loot time (e.g. TSM's market value versus its region average).
*   **Priority list** — the order the addon checks when more than one captured price is available for the same item; drag to reorder. The first price found on the list wins.

**Filters** (its own page)

*   **Blacklist** — items you never want tracked. Add an item by its id (or shift-click an item link into the box). This is point-in-time: once an id is blacklisted, future loots of it are skipped and never recorded, but rows you've *already* recorded are left exactly where they are — editing the list doesn't touch stored history. Delete a row manually if you want it gone.
*   **Whitelist** — items you always want tracked, even if they'd normally be skipped (below your quality threshold, from a muted source, or a quest item). While an id is whitelisted, every future loot of it is recorded as a normal row, bypassing those gates. Removing the id afterward only stops *future* loots from bypassing the gates again — rows it already added stay put. Adding an item to one list removes it from the other; an id is never on both.

## Auction-house pricing

If you have **Auctionator**, **TSM**, or **OribosExchange** installed, the addon reads an auction price for each item the moment you loot it — whichever of those you have running. You don't need all three; it works with just one, and quietly skips pricing altogether if you have none.

You choose which price counts most: **Settings ▸ Auction House Price** has a priority list, so if more than one pricing addon has a price for an item, the one higher on your list wins. You can also choose exactly **which prices to capture** — for example, TSM's market value versus its region average — if you want to be picky about the source.

Every drop's **value**, shown throughout the History table and Insights, is simply the **higher of its vendor sell price and its auction price** — so a valuable item never reads as worth less than what a vendor would pay for it.

## How attribution works

Whenever you receive an item, the addon looks at what you were just doing to decide where it came from. Killing a creature, opening a container, turning in a quest, taking mail, trading, buying from a vendor, winning an auction, finishing a Mythic+ run — each of these leaves a signal the addon reads at the moment the loot arrives.

If a signal is there, the item is filed under that source and marked **Certain**. If nothing tells it where the item came from, the addon files it under **Other** and marks it **Inferred**, rather than losing the record. Everything from one loot window is filed under the same source, so a full chest of drops all land together.

## FAQ

| Question | Answer |
|----------|--------|
| Does this track loot for my whole account or just one character? | The whole account. There's one shared history with a Character column, so every character adds to and reads from the same log. |
| Does it record other players' loot? | No. Only items **you** pick up are recorded. |
| What does the "confidence" marker mean? | Each item is marked **Certain** or **Inferred**. Most are Certain, filed straight from what the game reported. When the source can't be worked out, the item is still kept — filed under **Other** and marked Inferred. |
| Why don't I see Roll or Craft as recording toggles? | Those two sources exist in the data, but the addon can't detect them live yet, so they aren't shown as toggles. Every source it can detect can be turned on or off under **Data Collection → Record data from**. |
| Will raising the quality threshold hide items I already looted? | No. The threshold only affects new items. What you've already recorded stays until it's cleared by the retention setting or deleted by hand. |
| How do I wipe everything and start clean? | `/lh purge` deletes all history (with a confirmation). To reset your settings but keep the history, use `/lh resetall`. |
| What is `/lh test` for? | It loads a sample dataset into the window and Insights so you can see how they look without real loot. It's temporary, never saved, and clears when you run it again. |
| Does history survive reloads and relogs? | Yes. Your history is saved and restored every time you log in. |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Nothing is being recorded. | Check that **Master Controls → Enable collection** is on. If you expect greys or whites, lower **Data Collection → Minimum quality**. The source may be turned off under **Record data from**. Quest items are skipped by default — uncheck **Exclude quest items** to record them. |
| The minimap button is gone. | It's hidden. Turn **Master Controls → Hide minimap button** off, or open the window with `/lh toggle`. |
| An item landed under the wrong source (or "Other"). | When nothing tells the addon where an item came from, it falls back to **Other** / **Inferred**. Turn on the debug console with `/lh debug` to see how an item was filed. |
| The window is off-screen or the wrong size. | Its position, size, and scale are remembered per account. Adjust **Master Controls → Window scale**, or drag it back into view. |
| I want to preview the window but have no loot yet. | Run `/lh test` to load a sample dataset, then `/lh test` again to clear it. |
| I want to wipe everything and start over. | `/lh purge` clears all history (with confirmation). `/lh resetall` resets settings without touching your history. |

## Issues and feature requests

Bugs and feature requests are tracked at [github.com/tusharsaxena/LootHistory/issues](https://github.com/tusharsaxena/LootHistory/issues). Please file them there rather than in comments — it's the single place the project's to-do list lives.

## Version History

| Version | Date | Highlights |
|---------|------|------------|
| 1.1.0 | 2026-07-12 | Settings panel polish — the scrollbar no longer shifts the layout between pages, and the Reset All / Purge buttons are no longer cut off at the edge. |
| 1.0.0 | 2026-07-12 | Initial release: passive loot capture with source attribution and a Certain/Inferred confidence marker; account-wide history with a Character column; a standalone browser with filters (quality, type, source, zone, character), name search, sorting, and grouping; an Insights tab with breakdowns and highlights; a settings panel with full `/lh` slash support and per-source toggles; and a minimap button. |
