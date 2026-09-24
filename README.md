# Ka0s Loot History

![WoW](https://img.shields.io/badge/WoW-Midnight_12.1.0-purple)
![CurseForge Version](https://img.shields.io/curseforge/v/1607560)
![License](https://img.shields.io/badge/License-MIT-orange)
![Standard](https://img.shields.io/badge/Ka0s-WoW_Addon_Standard-yellow)
![Tests](https://img.shields.io/badge/Tests-928%2F928_passing-green)

Ka0s Loot History is a passive loot tracker for **World of Warcraft: Midnight**. It records every item you pick up and works out where it came from: a kill, a chest, the mailbox, the auction house. Open the window whenever you like to read back your loot, or switch to the **Insights** tab to see the same log broken down by source, value, quality and more.

The history is account-wide. Every character writes to and reads from the one log, and it survives reloads and logouts. You choose a minimum quality; anything below it is ignored.

Every item is filed under a source:

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

Most items are filed straight from what the game reported, and those are marked **Certain**. When nothing says where an item came from, it is still recorded — filed under **Other** and marked **Inferred** rather than dropped on the floor. The distinction is on every row, so you always know which kind you are reading.

## Screenshots

**_History browser_**

![History browser](https://media.forgecdn.net/attachments/1936/681/loothistory-screenshot-01-png.png)

![History browser](https://media.forgecdn.net/attachments/1936/682/loothistory-screenshot-02-png.png)

**_Insights panel_**

![Insights panel](https://media.forgecdn.net/attachments/1936/683/loothistory-screenshot-03-png.png)

![Insights panel](https://media.forgecdn.net/attachments/1936/684/loothistory-screenshot-04-png.png)

## Usage

On the first run after installing, log in, and the addon is already recording; there is nothing to set up first. Left-click the minimap button to open the History window, or type `/lh toggle` (`/lh show` and `/lh hide` if you want only the one direction). Right-click that same button goes straight to the settings, and if you would rather not have the button at all, untick **Minimap button** on the Master controls tab. The same button turns up in Titan Panel, ElvUI's data texts or Bazooka if you run one; it is the same button, so it answers the same two clicks. Drag the window by its title bar to place it, lock it once you are happy, and use **Reset position** if it ever ends up somewhere you cannot reach. A fresh install has nothing in it to look at, which makes the addon hard to judge, so it has a test mode: tick **Test mode** on the Master controls tab, or type `/lh test`, and the window opens with a sample dataset in the table and Insights. It stays on until you turn it off, entering combat turns it off for you, and it is never saved.

Click a column header to sort. The filter bar narrows what you are looking at — quality, type, source, zone, character, a name search — and **Group by** collapses rows together. That bar is shared with Insights, so the table and the charts always show the same slice of your loot rather than quietly disagreeing about which loot is under discussion. Insights takes that same slice and breaks it down by source, value, quality and character, with a Currency section of its own. When you have a view you like, **Save** stores its group, sort and filters as your account-wide default; **Clear** returns to that view and **Reset** drops the saved view back to stock. Sorting and filters only persist between sessions if you pressed Save.

Rows do more than sit there. Hover one for the item's own tooltip (currency rows show the currency tooltip), shift-click to link it into chat, right-click for the row menu. **Blacklist item** stops future loots of that id being recorded and leaves the row you clicked exactly where it is; the filter lists are point-in-time and never edit history you already have. **Delete** is there for when you want the row itself gone.

**Export** follows whichever tab you are on. From History it copies your loot rows as CSV; from Insights, an analytics summary that mirrors the charts. Either one honors the **Data Set** choice, so it is all your data or just the filtered view in front of you. Nothing leaves the game — the addon can't reach your system clipboard, so it opens a box with the text already selected for you to press Ctrl+C on.

`/lh disable` turns the addon off and `/lh enable` turns it back on; it is the same switch as **Master controls ▸ Enable Loot History**. Switched off, the addon stops watching for loot, cancels anything it had pending and closes its window. It does not stay loaded and ignore what it sees. The slash commands keep working while it is off: a bare `/lh` still opens the settings panel, `/lh get` and `/lh set` still read and repair settings, and `/lh enable` is always there. Only the commands that drive the window refuse, and their one-line reply tells you how to switch the addon back on.

Everything else is configured under **Settings ▸ AddOns ▸ Ka0s Loot History**, which `/lh` (or `/loothistory`) opens; `/lh help` (or `/loothistory help`) lists the commands.

## How attribution works

When an item arrives, the addon looks at what you were just doing. Killing a creature, opening a container, turning in a quest, taking mail, trading, buying from a vendor, winning an auction, finishing a Mythic+ run — each leaves a signal it reads at the moment the loot lands.

If a signal is there, the item is filed under that source and marked **Certain**. If nothing tells it where the item came from, the addon files it under **Other** and marks it **Inferred**, which is a better record than none. Everything from one loot window is filed under the same source, so a full chest of drops lands together.

### What a drop was worth

Attribution is only half of what is read as an item arrives. The other half is its value, and it is read then for the same reason: a price looked up later is a price from a different day.

If you have **Auctionator**, **TSM** or **OribosExchange** installed, an auction price is read for each item the moment you loot it. One is enough. With none of them, pricing is quietly skipped.

Which prices count is your call. **Settings ▸ AH Price** lists every price your installed addons can supply — TSM's market value against its region average, for instance — in one table. Tick the ones you want, and drag them by the handle on each row into the order you trust them in; where more than one has a price for an item, the highest-ranked ticked source wins. Unticked sources, and any whose addon isn't installed, fall to the bottom.

The **value** shown throughout the History table and Insights is the higher of an item's vendor sell price and its auction price, so nothing ever reads as worth less than a vendor would pay for it.

## FAQ

| Question | Answer |
|----------|--------|
| Does this track loot for my whole account or just one character? | The whole account. One shared history with a Character column, so every character adds to and reads from the same log. |
| Does it record other players' loot? | No. Only items **you** pick up. |
| What does the "confidence" marker mean? | Each item is marked **Certain** or **Inferred**. Most are Certain, filed straight from what the game reported. When the source can't be worked out, the item is still kept — filed under **Other** and marked Inferred. |
| Which sources can I toggle on or off? | Every source it records — Kill, Container, Mythic+, Bonus Roll, Roll, Quest, Trade, Mail, Auction House, Vendor, Disenchant, Milling, Prospecting, Craft and Refund — under **Capture ▸ Record data from** in the settings. |
| Will raising the quality threshold hide items I already looted? | No. The threshold only applies to new items. What you have already recorded stays until the retention setting clears it or you delete it by hand. |
| Do I need another addon to see auction values? | Only if you want them. Prices come from **Auctionator**, **TSM** or **OribosExchange** if you have one installed; with none, every value falls back to the vendor sell price. The value shown is always the higher of the two. |
| How do I stop tracking one specific item — or force-track one below my threshold? | The **Filters** tab in settings. Blacklist an item (by id, name or a shift-clicked link) to skip it from now on; whitelist one to record it always, even when it is below your quality threshold, from a muted source, or a quest item. Both are point-in-time: they change future loots only and never touch rows you already have. |
| Does "Export to CSV" send my loot anywhere? | No. It builds the CSV text and opens a box for you to copy by hand. Nothing leaves the game; what you do with the copied text is your business. |
| Do my filters and sorting stick between sessions? | Only if you save them. The filter bar's **Save** button stores the current group, sort and filters as your account-wide default view; **Clear** returns to that view, and **Reset** drops the saved view back to stock. |
| How do I wipe everything and start clean? | `/lh purge` deletes all history, with a confirmation first. To reset your settings but keep the history, `/lh resetall`. |
| What is `/lh test` for? | It turns on test mode, which loads a sample dataset into the window and Insights so you can see how they look without real loot. The **Test mode** checkbox on the Master controls tab is the same switch. It is never saved, and it clears when you run the command again, untick the box, or enter combat. |
| Does history survive reloads and relogs? | Yes. It is saved and restored every time you log in. |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Nothing is being recorded. | Check that **Master controls ▸ Enable Loot History** is on. If you expect grays or whites, lower **Capture ▸ Minimum quality**. The source may be turned off under **Record data from**. Quest items are skipped by default — uncheck **Capture ▸ Exclude quest items** to record them. The item may also be blacklisted on the **Filters** tab. |
| The minimap button is gone. | It's hidden. Tick **Master controls ▸ Minimap button** back on, or open the window with `/lh toggle`. |
| An item landed under the wrong source (or "Other"). | When nothing tells the addon where an item came from, it falls back to **Other** / **Inferred**. Open the debug console with `/lh debug` to see how an item was filed. |
| The AH Price / value column is blank, or just matches the vendor price. | You need **Auctionator**, **TSM** or **OribosExchange** installed, **AH Price ▸ Enable AH pricing** on, and at least one price source ticked. Even then, a price only appears once that addon actually has one for the item — after its next scan, usually. Until then the value falls back to the vendor sell price. |
| I clicked Export to CSV but nothing was copied. | The addon can't write to your system clipboard. A box opens with the text already selected: press **Ctrl+C** to copy, then **Esc** to close. |
| An item I don't want keeps being recorded. | Blacklist it on the **Filters** tab: type its id or name, or shift-click its link into the box. Future loots are skipped; rows you already have stay until you delete them. |
| Rows are missing from the table. | A column filter or the search box is probably narrowing it. Press **Clear** on the filter bar to return to your saved view. Filters and sorting only persist between sessions if you pressed **Save**. |
| `/lh debug on` doesn't open the debug window. | `on` / `off` control debug **logging**, which is session-only and off again after every reload. That is not the window. Show the window with `/lh debug` and no argument, or the **Master controls ▸ Debug console** toggle. Logging runs perfectly well with the window closed. |
| The window is off-screen or the wrong size. | Position, size and scale are remembered per account. Adjust **Interface ▸ Window scale**, or drag it back into view. |
| I want to preview the window but have no loot yet. | Tick **Master controls ▸ Test mode**, or type `/lh test`. Untick it, or run `/lh test` again, to clear it. |
| I want to wipe everything and start over. | `/lh purge` clears all history, with a confirmation. `/lh resetall` resets settings without touching your history. |

## Issues and feature requests

Bugs and feature requests are tracked at [github.com/tusharsaxena/LootHistory/issues](https://github.com/tusharsaxena/LootHistory/issues). Please file them there rather than in comments; it's the single place the project's to-do list lives.

## Version History

| Version | Date | Highlights |
|---------|------|------------|
| 1.3.0 | 2026-09-10 | - **General** and **Filters** are now tab strips, with price sources reordered by drag and a **Master controls** group<br>- Fixed the auction-house status colors rendering muted instead of saturated<br>- Attribution wiring and the lifecycle kick gained guard rails against a half-built window<br>- The saved-data byte estimate now counts every field it declares<br>- Updated for game patch 12.1.0 |
| 1.2.0 | 2026-07-26 | - **Currency capture** — currencies recorded as their own rows with a dedicated Insights section, in-game tooltips, quality colors, and blacklisting<br>- **Insights dashboard overhaul** — Loot/Currency sections, per-character companion charts, refreshed source palette and legends<br>- **More loot sources** — Bonus Roll, Craft, Roll, Refund<br>- **Removed Export to AI** — Export to CSV remains for History and Insights |
| 1.1.0 | 2026-07-20 | - **Export to AI** report (Claude — Desktop, Code, and Web); **auction-house values** via Auctionator / TSM / OribosExchange, shown in a new AH Price column with its own settings page; **Blacklist / Whitelist** item filters; a **shared** History/Insights filter bar with new **Bound** and **Sub-Type** filters and **Group by Type**; Insights valued at market price. Plus settings-panel polish — the scrollbar no longer shifts the layout between pages, and Reset All / Purge are no longer clipped. |
| 1.0.2 | 2026-07-12 | - **Exclude quest items** — a new opt-out setting (on by default) that skips the temporary items you pick up during quests. Uncheck it to record them too. |
| 1.0.1 | 2026-07-12 | - Maintenance republish — a packaging-only change to refresh the CurseForge listing. No functional changes. |
| 1.0.0 | 2026-07-12 | - Initial release: passive loot capture with source attribution and a Certain/Inferred confidence marker; account-wide history with a Character column; a standalone browser with filters (quality, type, source, zone, character), name search, sorting, and grouping; an Insights tab with breakdowns and highlights; a settings panel with full `/lh` slash support and per-source toggles; and a minimap button. |
