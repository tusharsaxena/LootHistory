# Ka0s Loot History

![WoW](https://img.shields.io/badge/WoW-Midnight_12.1.0-purple)
![CurseForge Version](https://img.shields.io/curseforge/v/1607560)
![License](https://img.shields.io/badge/License-MIT-orange)
![Standard](https://img.shields.io/badge/Ka0s-WoW_Addon_Standard-yellow)
![Tests](https://img.shields.io/badge/Tests-961%2F961_passing-green)

Ka0s Loot History is a passive loot tracker for World of Warcraft: Midnight. It records every item you pick up and works out where it came from: a kill, a chest, the mailbox, the auction house. Open the window whenever you like to read back your loot. The **Insights** tab shows the same log broken down by source, value, quality and more.

The history is account-wide. Every character writes to and reads from the same log, and it survives reloads and logouts. You pick a minimum quality, and anything below it is ignored.

Each item is filed under one of these sources:

| Source | What it covers |
| ------ | -------------- |
| Kill | Looting a creature you killed |
| Container | Opening a chest, lockbox, or lootable object |
| Mythic+ | End-of-run and Great Vault chests |
| Bonus Roll | Items from a bonus roll |
| Roll | Items you won on a group-loot roll |
| Quest | Quest rewards |
| Trade | Items received in a trade |
| Mail | Items taken from the mailbox |
| Auction House | Items won at auction |
| Vendor | Items bought from a vendor |
| Craft | Items you created by crafting |
| Refund | Items returned to you by a refund |
| Disenchant / Milling / Prospecting | Items produced by those actions |
| Other | Anything that arrived with no clear source |

Most items are filed straight from what the game reported, and those are marked **Certain**. Sometimes nothing says where an item came from. The addon still records it, under **Other** and marked **Inferred**, rather than dropping it on the floor. Every row shows which of the two it is, so you always know what you're reading.

## Screenshots

**_History browser_**

![History browser](https://media.forgecdn.net/attachments/1936/681/loothistory-screenshot-01-png.png)

![History browser](https://media.forgecdn.net/attachments/1936/682/loothistory-screenshot-02-png.png)

**_Insights panel_**

![Insights panel](https://media.forgecdn.net/attachments/1936/683/loothistory-screenshot-03-png.png)

![Insights panel](https://media.forgecdn.net/attachments/1936/684/loothistory-screenshot-04-png.png)

## Usage

There's nothing to set up. Install it, log in, and it's already recording.

Left-click the minimap button to open the settings. Right-click it for a small options menu with four ticks: **Enabled**, **Locked**, **Test mode** and **Show window**. Show window opens and closes the History window. So does `/lh toggle`, and `/lh show` and `/lh hide` work if you only want one direction. Each tick does exactly what the matching command or setting does. While the addon is switched off, the last three are grayed out until you tick **Enabled** again.

Hover the button to see its status: whether the addon is enabled, whether the window is locked, whether test mode is on, and how many records you have. That works even while the addon is switched off. If you run Titan Panel, ElvUI's data texts or Bazooka, the same button turns up there too and answers the same two clicks. If you'd rather not have the button at all, untick **Minimap button** on the Master controls tab.

Drag the window by its title bar to place it, then lock it once you're happy with where it sits. If it ever ends up somewhere you can't reach, use **Reset position**.

A fresh install has nothing in it to look at, which makes the addon hard to judge. That's what test mode is for. Tick **Test mode** on the Master controls tab, or type `/lh test`, and the window opens with a sample dataset in the table and Insights. It stays on until you turn it off. Entering combat turns it off for you, and it's never saved.

Click a column header to sort. The filter bar narrows what you're looking at by quality, type, source, zone, character or a name search, and **Group by** collapses rows together. History and Insights share that bar, so the table and the charts always show the same slice of your loot instead of quietly disagreeing about which loot they mean. Insights breaks that slice down by source, value, quality and character, and gives currency a section of its own.

When you have a view you like, press **Save** to store its group, sort and filters as your account-wide default. **Clear** goes back to that view, and **Reset** puts the saved view back to stock. Sorting and filters only carry over between sessions if you pressed Save.

Hover a row for the item's own tooltip (currency rows show the currency tooltip). Shift-click it to link it in chat, or right-click for the row menu. **Blacklist item** stops future loots of that item id from being recorded, and leaves the row you clicked exactly where it is. The filter lists take effect from the moment you set them and never edit history you already have. When you want the row itself gone, use **Delete**.

**Export** works on whichever tab you're on. From History it copies your loot rows as CSV. From Insights it copies an analytics summary that mirrors the charts. Both honor the **Data Set** choice, so you get either all your data or just the filtered view in front of you. Nothing leaves the game. The addon can't reach your system clipboard, so it opens a box with the text already selected and you press Ctrl+C.

`/lh disable` turns the addon off and `/lh enable` turns it back on. It's the same switch as **Master controls ▸ Enable Loot History**. When it's off, the addon stops watching for loot, cancels anything it had pending and closes its window. It doesn't stay loaded and quietly ignore what it sees. The slash commands still work while it's off. A bare `/lh` opens the settings panel, `/lh get` and `/lh set` read and repair settings, `/lh debug` and `/lh diagnostics` are there so you can report a problem, and `/lh enable` is always available. Only the commands that drive the window refuse, and their one-line reply tells you how to switch the addon back on.

Everything else is in **Settings ▸ AddOns ▸ Ka0s Loot History**. `/lh` (or `/loothistory`) opens it, and `/lh help` (or `/loothistory help`) lists the commands.

## How attribution works

When an item arrives, the addon looks at what you were just doing. Killing a creature leaves a signal it can read at the moment the loot lands. So do opening a container, turning in a quest, taking mail, trading, buying from a vendor, winning an auction and finishing a Mythic+ run.

If there's a signal, the item goes under that source and is marked **Certain**. If nothing says where the item came from, it goes under **Other** and is marked **Inferred**. That's still a better record than none. Everything from one loot window gets the same source, so a full chest of drops lands together.

### What a drop was worth

Where an item came from is half of what the addon reads when it arrives. The other half is what it's worth, and it reads that at the same moment for the same reason: a price looked up later is a price from a different day.

If you have **Auctionator**, **TSM** or **OribosExchange** installed, the addon reads an auction price for each item the moment you loot it. One of them is enough. With none installed, it skips pricing.

You decide which prices count. **Settings ▸ AH Price** lists every price your installed addons can supply in one table (TSM's market value alongside its region average, for instance). Tick the ones you want and drag them by the handle on each row into the order you trust them in. When more than one has a price for an item, the highest-ranked ticked source wins. Unticked sources, and any whose addon isn't installed, drop to the bottom.

The value shown throughout the History table and Insights is the higher of an item's vendor sell price and its auction price. Nothing ever shows as worth less than a vendor would pay for it.

## FAQ

| Question | Answer |
|----------|--------|
| Does this track loot for my whole account or just one character? | The whole account. There's one shared history with a Character column, and every character adds to and reads from the same log. |
| Does it record other players' loot? | No. Only items **you** pick up. |
| What does the "confidence" marker mean? | Each item is marked **Certain** or **Inferred**. Most are Certain, filed straight from what the game reported. When the source can't be worked out, the addon still keeps the item, files it under **Other** and marks it Inferred. |
| Which sources can I toggle on or off? | Every source it records: Kill, Container, Mythic+, Bonus Roll, Roll, Quest, Trade, Mail, Auction House, Vendor, Disenchant, Milling, Prospecting, Craft and Refund. They're under **Capture ▸ Record data from** in the settings. |
| Will raising the quality threshold hide items I already looted? | No. The threshold only applies to new items. What you've already recorded stays until the retention setting clears it or you delete it by hand. |
| Do I need another addon to see auction values? | Only if you want them. Prices come from **Auctionator**, **TSM** or **OribosExchange** if you have one installed. With none, every value falls back to the vendor sell price. The value shown is always the higher of the two. |
| How do I stop tracking one specific item, or force-track one below my threshold? | Use the **Filters** tab in settings. Blacklist an item (by id, name or a shift-clicked link) to skip it from now on. Whitelist one to always record it, even if it's below your quality threshold, from a muted source, or a quest item. Both lists only affect future loots and never touch rows you already have. |
| Does "Export to CSV" send my loot anywhere? | No. It builds the CSV text and opens a box for you to copy by hand. Nothing leaves the game, and what you do with the copied text is your business. |
| Do my filters and sorting stick between sessions? | Only if you save them. The filter bar's **Save** button stores the current group, sort and filters as your account-wide default view. **Clear** returns to that view, and **Reset** puts the saved view back to stock. |
| How do I wipe everything and start clean? | `/lh purge` deletes all history, and asks you to confirm first. To reset your settings but keep the history, use `/lh resetall`. |
| What is `/lh test` for? | It turns on test mode, which loads a sample dataset into the window and Insights so you can see how they look before you have real loot. The **Test mode** checkbox on the Master controls tab is the same switch. It's never saved, and it clears when you run the command again, untick the box, or enter combat. |
| Does history survive reloads and relogs? | Yes. It's saved, and restored every time you log in. |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Nothing is being recorded. | Check that **Master controls ▸ Enable Loot History** is on. If you expect grays or whites, lower **Capture ▸ Minimum quality**. The source may be turned off under **Record data from**. Quest items are skipped by default, so uncheck **Capture ▸ Exclude quest items** if you want them. The item may also be blacklisted on the **Filters** tab. |
| The minimap button is gone. | It's hidden. Tick **Master controls ▸ Minimap button** back on, or open the window with `/lh toggle`. |
| An item landed under the wrong source (or "Other"). | When nothing tells the addon where an item came from, it falls back to **Other** / **Inferred**. Open the debug console with `/lh debug` to see how an item was filed. |
| The AH Price / value column is blank, or just matches the vendor price. | You need **Auctionator**, **TSM** or **OribosExchange** installed, **AH Price ▸ Enable AH pricing** on, and at least one price source ticked. Even then, a price only shows up once that addon actually has one for the item, which is usually after its next scan. Until then the value falls back to the vendor sell price. |
| I clicked Export to CSV but nothing was copied. | The addon can't write to your system clipboard. A box opens with the text already selected: press **Ctrl+C** to copy, then **Esc** to close. |
| An item I don't want keeps being recorded. | Blacklist it on the **Filters** tab. Type its id or name, or shift-click its link into the box. Future loots are skipped, and rows you already have stay until you delete them. |
| Rows are missing from the table. | A column filter or the search box is probably narrowing it. Press **Clear** on the filter bar to go back to your saved view. Filters and sorting only carry over between sessions if you pressed **Save**. |
| `/lh debug on` doesn't open the debug window. | `on` / `off` control debug **logging**, not the window. Logging is session-only and switches off again after every reload. To show the window, use `/lh debug` with no argument, or the **Master controls ▸ Debug console** toggle. Logging runs fine with the window closed. |
| The window is off-screen or the wrong size. | The addon remembers position, size and scale per account. Adjust **Interface ▸ Window scale**, or drag the window back into view. |
| I want to preview the window but have no loot yet. | Tick **Master controls ▸ Test mode**, or type `/lh test`. Untick it, or run `/lh test` again, to clear it. |
| I want to wipe everything and start over. | `/lh purge` clears all history, after you confirm. `/lh resetall` resets settings without touching your history. |
| Something looks wrong and I want to report it. | Follow [Reporting a bug](#reporting-a-bug) below. |

## Reporting a bug

1. Type `/lh debug on` and reproduce the bug.
2. Type `/lh diagnostics`.
3. If the debug window isn't open, open it with `/lh debug`. Press **Copy**, copy the entire output, and include it with your bug report.

The report is added after the debug trace in the same window, so one copy carries both.

## Issues and feature requests

Bugs and feature requests are tracked at [github.com/tusharsaxena/LootHistory/issues](https://github.com/tusharsaxena/LootHistory/issues). Please file them there rather than in comments. That's where the project's to-do list lives.

## Version History

| Version | Date | Highlights |
|---------|------|------------|
| 1.3.0 | 2026-09-10 | - **General** and **Filters** are now tab strips, with price sources reordered by drag and a **Master controls** group<br>- Fixed the auction-house status colors rendering muted instead of saturated<br>- Attribution wiring and the lifecycle kick gained guard rails against a half-built window<br>- The saved-data byte estimate now counts every field it declares<br>- Updated for game patch 12.1.0 |
| 1.2.0 | 2026-07-26 | - **Currency capture** — currencies recorded as their own rows with a dedicated Insights section, in-game tooltips, quality colors, and blacklisting<br>- **Insights dashboard overhaul** — Loot/Currency sections, per-character companion charts, refreshed source palette and legends<br>- **More loot sources** — Bonus Roll, Craft, Roll, Refund<br>- **Removed Export to AI** — Export to CSV remains for History and Insights |
| 1.1.0 | 2026-07-20 | - **Export to AI** report (Claude — Desktop, Code, and Web); **auction-house values** via Auctionator / TSM / OribosExchange, shown in a new AH Price column with its own settings page; **Blacklist / Whitelist** item filters; a **shared** History/Insights filter bar with new **Bound** and **Sub-Type** filters and **Group by Type**; Insights valued at market price. Plus settings-panel polish — the scrollbar no longer shifts the layout between pages, and Reset All / Purge are no longer clipped. |
| 1.0.2 | 2026-07-12 | - **Exclude quest items** — a new opt-out setting (on by default) that skips the temporary items you pick up during quests. Uncheck it to record them too. |
| 1.0.1 | 2026-07-12 | - Maintenance republish — a packaging-only change to refresh the CurseForge listing. No functional changes. |
| 1.0.0 | 2026-07-12 | - Initial release: passive loot capture with source attribution and a Certain/Inferred confidence marker; account-wide history with a Character column; a standalone browser with filters (quality, type, source, zone, character), name search, sorting, and grouping; an Insights tab with breakdowns and highlights; a settings panel with full `/lh` slash support and per-source toggles; and a minimap button. |
