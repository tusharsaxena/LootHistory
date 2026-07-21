# Ka0s Loot History

![WoW](https://img.shields.io/badge/WoW-Midnight_12.0.7-purple)
![CurseForge Version](https://img.shields.io/curseforge/v/1607560)
![License](https://img.shields.io/badge/License-MIT-orange)
[![Standard](https://img.shields.io/badge/Ka0s-WoW_Addon_Standard-yellow)](https://github.com/tusharsaxena/WowAddonStandards)
![Tests](https://img.shields.io/badge/Tests-257%2F257_passing-green)

![Logo](https://media.forgecdn.net/attachments/1788/918/loothistory-logo-jpg.jpg)

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

## What's new in 1.1.0

*   **Export to AI** — a new **Export to AI** button turns your loot into a polished, WoW-themed HTML report, complete with an interactive browser, an Insights dashboard, and a written "what the data says" analysis. It works with **Claude** (Desktop, Code, and Web) today; ChatGPT, Gemini, and other assistants need different handling and are planned for a later release.
*   **Auction-house values** — with Auctionator, TSM, or OribosExchange installed, every drop is now valued at the **higher of its vendor and auction price** and shown in a new **AH Price** column. A dedicated **AH Price** settings page lets you pick and rank which price sources count.
*   **Blacklist & Whitelist** — a new **Filters** page lets you permanently skip items you never want tracked, or force-record items that would normally be ignored — added by item id or shift-clicked link.
*   **Shared, richer filtering** — the filter bar is now **shared** between the History and Insights tabs, so one narrowing applies to both. New **Bound** and **Sub-Type** filters (and a Sub-Type column), plus **Group by Type**, give you finer control.
*   **Insights by real value** — the Insights breakdowns now rank and total your loot by **market value** (auction-or-vendor), not just its vendor sell price.

## Screenshots

**_History browser_**

![History browser](https://media.forgecdn.net/attachments/1804/899/loothistory-screenshot-01-png.png)

![History browser](https://media.forgecdn.net/attachments/1804/900/loothistory-screenshot-02-png.png)

**_Insights_**

![Insights](https://media.forgecdn.net/attachments/1804/901/loothistory-screenshot-03-png.png)

![Insights](https://media.forgecdn.net/attachments/1804/902/loothistory-screenshot-04-png.png)

**_Settings Panel_**

![Settings Panel](https://media.forgecdn.net/attachments/1804/903/loothistory-screenshot-05-png.png)

![Settings Panel](https://media.forgecdn.net/attachments/1804/904/loothistory-screenshot-06-png.png)

## Usage

Install it like any other addon and log in. Recording starts right away — there's nothing to set up. Open the History window by left-clicking the minimap button or typing `/lh`. Click a column header to sort, use the filter bar to narrow the list, pick a **Group by** to collapse rows together, and switch to the **Insights** tab for the analytics view. The filter bar is **shared** between both tabs, so the same narrowing applies to the table and the charts at once — you always know which slice of your loot you're looking at.

The **Export** button follows the tab you're on: on **History** it copies your loot rows out as CSV (everything or just the current filtered view); on **Insights** it copies the analytics summary as a CSV that mirrors the charts. Don't want an item tracked going forward? Right-click its row and choose **Blacklist item** — the clicked row stays put (nothing is deleted or hidden), but future loots of that item are skipped. Delete a row from the table if you want it gone.

### Export to AI

The Export window also has an **Export to AI** button. It copies a ready-made prompt that you paste into **Claude** — Desktop, Code, or Web — to get back a single, self-contained HTML page: a gorgeous, WoW-themed report of your loot with an interactive history browser, an Insights dashboard, and a LLM-written analysis. Copy the prompt (Ctrl+C), paste it into Claude, and it replies with the HTML file; you can then publish it as an Artifact to get a shareable link. 

Unlike Export to CSV, Export to AI always bundles **both** your History and Insights (one report shows everything), and it honours the **Data Set** choice — all data, or just your current filtered view. The **?** beside the button explains the steps in-game. Claude needs **web access enabled**: the prompt links to a design guide it reads to style the report.

Example report: [link](https://claude.ai/public/artifacts/a6d520a4-e7b3-423e-8d7c-0035c52331a5)

> Right now Export to AI is built for _**Claude**_ only — ChatGPT, Gemini, and other LLMs need different handling and are planned for a later release.

#### Screenshots

**_Insights_**

![Insights](https://media.forgecdn.net/attachments/1804/905/loothistory-screenshot-07-png.png)

**_History Browser_**

![History Browser](https://media.forgecdn.net/attachments/1804/906/loothistory-screenshot-08-png.png)

**_LLM Insights_**

![LLM Insights](https://media.forgecdn.net/attachments/1804/907/loothistory-screenshot-09-png.png)

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
| `/lh debug` | Toggle the debug console window. `/lh debug on` / `off` turn debug logging on or off (session-only) — separate from showing the window. |
| `/lh test` | Load a sample dataset into the window and Insights so you can preview them. Run it again to clear. |
| `/lh help` | Show the full command list. |

### Settings panel

Settings live at **Escape → Options → AddOns → Ka0s Loot History** (or `/lh config`). Everything applies to your whole account, and every option can also be changed from chat with `/lh get` and `/lh set`. The **General** page has two groups (below), and **Filters** and **AH Price** each get their own page.

**Master Controls**

*   **Enable collection** — the master on/off switch for recording. Turn it off and nothing new is recorded; your existing history stays, and the window still works.
*   **Hide minimap button** — show or hide the minimap button. Left-click it to open the window, right-click for settings.
*   **Window scale** — resize the History window from 0.6× to 1.6×. Its position and size are remembered separately from this.
*   **Debug console** — show or hide the on-screen debug console. Session-only; resets on reload.

**Data Collection**

*   **Minimum quality** — only record items at or above this quality (default **Common**). Raising it never removes items you've already recorded.
*   **Exclude quest items** — skip the temporary items you pick up during quests. **On by default**; uncheck it to record them too.
*   **Keep history for** — how long to keep records. Older ones are cleared out once per session; choose **Always** to keep everything (default **30 days**).
*   **Record data from** — turn individual sources on or off. Unchecking a source stops it being recorded. Only the sources the addon can actually detect appear here.

**AH Price** (its own page)

*   **Enable AH pricing** — the master on/off switch for reading prices from Auctionator, TSM, and OribosExchange. Turn it off and every drop's value falls back to its vendor sell price.
*   **Price Sources** — one table listing every price your installed addons can supply. **Tick** a source to collect its price at loot time *and* enter it into the ranking; the highest-ranked source you have a price for is the value shown. Reorder ticked sources with the up/down arrows. Each row shows the addon, the price module (with an **ⓘ** explaining what it means), a ✓/✗ tick, and a status — *Collecting data*, *Not collecting data*, or *Addon not installed*. Ticked sources sort to the top, the ones you don't collect fall below them, and anything whose addon isn't installed drops to the bottom, greyed out.

**Filters** (its own page)

*   **Blacklist** — items you never want tracked. Add an item by its id (or shift-click an item link into the box). This is point-in-time: once an id is blacklisted, future loots of it are skipped and never recorded, but rows you've *already* recorded are left exactly where they are — editing the list doesn't touch stored history. Delete a row manually if you want it gone.
*   **Whitelist** — items you always want tracked, even if they'd normally be skipped (below your quality threshold, from a muted source, or a quest item). While an id is whitelisted, every future loot of it is recorded as a normal row, bypassing those gates. Removing the id afterward only stops *future* loots from bypassing the gates again — rows it already added stay put. Adding an item to one list removes it from the other; an id is never on both.

## Auction-house pricing

If you have **Auctionator**, **TSM**, or **OribosExchange** installed, the addon reads an auction price for each item the moment you loot it — whichever of those you have running. You don't need all three; it works with just one, and quietly skips pricing altogether if you have none.

You choose which prices count: **Settings ▸ AH Price** lists every price your installed addons can supply — for example, TSM's market value versus its region average — in one table. Tick the ones you want (a ticked source is both collected *and* ranked) and drag them into your preferred order with the up/down arrows; if more than one has a price for the same item, the highest-ranked ticked source wins. Sources you leave unticked, or whose addon isn't installed, drop to the bottom.

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
| Which sources can I toggle on or off? | Every source the addon records — Kill, Container, Mythic+, Bonus Roll, Roll, Quest, Trade, Mail, Auction House, Vendor, Disenchant, Milling, Prospecting, Craft, and Refund — can be turned on or off individually under **Data Collection → Record data from**. |
| Will raising the quality threshold hide items I already looted? | No. The threshold only affects new items. What you've already recorded stays until it's cleared by the retention setting or deleted by hand. |
| Do I need another addon to see auction values? | Only if you want them. Prices come from **Auctionator**, **TSM**, or **OribosExchange** if you have one installed; with none, every value falls back to the vendor sell price. The value shown is always the higher of the vendor and auction price. |
| How do I stop tracking one specific item — or force-track one below my threshold? | Use **Settings ▸ Filters**. Blacklist an item's id to skip it from now on; whitelist one to always record it even when it's below your quality threshold, from a muted source, or a quest item. Both are point-in-time: they change future loots only and never touch rows you've already recorded. |
| What does "Export to AI" do — does it send my loot anywhere? | No. It builds a text report (your history plus the Insights summary and instructions) and opens a box for you to copy by hand. Nothing leaves the game; you paste it into an AI chat yourself. **Export to CSV** works the same way. |
| Do my filters and sorting stick between sessions? | Only if you save them. The filter bar's **Save** button stores the current group, sort, and filters as your account-wide default view; **Clear** returns to that view, and **Reset** drops the saved view back to stock. |
| How do I wipe everything and start clean? | `/lh purge` deletes all history (with a confirmation). To reset your settings but keep the history, use `/lh resetall`. |
| What is `/lh test` for? | It loads a sample dataset into the window and Insights so you can see how they look without real loot. It's temporary, never saved, and clears when you run it again. |
| Does history survive reloads and relogs? | Yes. Your history is saved and restored every time you log in. |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Nothing is being recorded. | Check that **Master Controls → Enable collection** is on. If you expect greys or whites, lower **Data Collection → Minimum quality**. The source may be turned off under **Record data from**. Quest items are skipped by default — uncheck **Exclude quest items** to record them. The item may also be blacklisted under **Settings ▸ Filters**. |
| The minimap button is gone. | It's hidden. Turn **Master Controls → Hide minimap button** off, or open the window with `/lh toggle`. |
| An item landed under the wrong source (or "Other"). | When nothing tells the addon where an item came from, it falls back to **Other** / **Inferred**. Open the debug console with `/lh debug` to see how an item was filed. |
| The AH Price / value column is blank, or just matches the vendor price. | You need **Auctionator**, **TSM**, or **OribosExchange** installed, **AH Price → Enable AH pricing** on, and at least one price source ticked. Even then a price only appears once that addon actually has one for the item (for example after its next scan); until then the value falls back to the vendor sell price. |
| I clicked Export to CSV / Export to AI but nothing was copied. | The addon can't write to your system clipboard. A box opens with the text already selected — press **Ctrl+C** to copy it, then **Esc** to close. |
| An item I don't want keeps being recorded. | Blacklist its id under **Settings ▸ Filters** (or shift-click its link into the box). Future loots are skipped; rows you've already recorded stay until you delete them. |
| Rows are missing from the table. | A column filter or the search box is probably narrowing it. Press **Clear** on the filter bar to return to your saved view. Filters and sorting only persist between sessions if you pressed **Save**. |
| `/lh debug on` doesn't open the debug window. | `on` / `off` control debug **logging** (session-only, off after every reload), not the window. Show the window with `/lh debug` (no argument) or the **Master Controls → Debug console** toggle; logging can run with the window closed. |
| The window is off-screen or the wrong size. | Its position, size, and scale are remembered per account. Adjust **Master Controls → Window scale**, or drag it back into view. |
| I want to preview the window but have no loot yet. | Run `/lh test` to load a sample dataset, then `/lh test` again to clear it. |
| I want to wipe everything and start over. | `/lh purge` clears all history (with confirmation). `/lh resetall` resets settings without touching your history. |

## Issues and feature requests

Bugs and feature requests are tracked at [github.com/tusharsaxena/LootHistory/issues](https://github.com/tusharsaxena/LootHistory/issues). Please file them there rather than in comments — it's the single place the project's to-do list lives.

## Version History

| Version | Date | Highlights |
|---------|------|------------|
| 1.1.0 | 2026-07-20 | **Export to AI** report (Claude — Desktop, Code, and Web); **auction-house values** via Auctionator / TSM / OribosExchange, shown in a new AH Price column with its own settings page; **Blacklist / Whitelist** item filters; a **shared** History/Insights filter bar with new **Bound** and **Sub-Type** filters and **Group by Type**; Insights valued at market price. Plus settings-panel polish — the scrollbar no longer shifts the layout between pages, and Reset All / Purge are no longer clipped. |
| 1.0.2 | 2026-07-12 | **Exclude quest items** — a new opt-out setting (on by default) that skips the temporary items you pick up during quests. Uncheck it to record them too. |
| 1.0.1 | 2026-07-12 | Maintenance republish — a packaging-only change to refresh the CurseForge listing. No functional changes. |
| 1.0.0 | 2026-07-12 | Initial release: passive loot capture with source attribution and a Certain/Inferred confidence marker; account-wide history with a Character column; a standalone browser with filters (quality, type, source, zone, character), name search, sorting, and grouping; an Insights tab with breakdowns and highlights; a settings panel with full `/lh` slash support and per-source toggles; and a minimap button. |
