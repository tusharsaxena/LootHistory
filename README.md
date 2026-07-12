# Ka0s Loot History

![wow](https://img.shields.io/badge/WoW-Midnight_12.0.7-orange)
![CurseForge Version](https://img.shields.io/curseforge/v/1530802)
![license](https://img.shields.io/badge/license-MIT-green)

**Records every item you loot, attributes where it came from, and lets you browse and analyze
your loot history — account-wide.**

Ka0s Loot History quietly watches what you pick up, works out the **source** of each drop (a
mob kill, a container, mail, a trade, the auction house, a quest, a vendor, a craft, a group
roll, or a Mythic+ chest), and stores it across all your characters. Open a standalone window
to filter, sort, and group the full history, or switch to **Insights** for source, vendor-value,
quality, character, and time breakdowns plus your top zones, items, and most valuable drops.

---

## Features

- **Passive capture** — records loot automatically from `CHAT_MSG_LOOT`; no clicking, no upkeep.
- **Source attribution** — every drop is tagged Kill / Container / Mythic+ / Quest / Trade / Mail /
  Auction House / Vendor / Disenchant / Milling / Prospecting / Other, with a **confidence** marker
  for inferred sources.
- **Account-wide history** — one shared log across all characters, with a Character column.
- **Quality threshold** — only record at or above a quality you choose (Poor → Legendary).
- **Per-source muting** — turn off recording for sources you don't care about.
- **Browser window** — movable, resizable, scale-aware; a virtualized table that stays smooth
  with thousands of records.
- **Filter / sort / group** — by quality, source, character, zone, or item-name search; sort any
  column; group by source, zone, character, quality, or day.
- **Row actions** — hover for the item tooltip, shift-click to link in chat, right-click to link
  or delete.
- **Insights** — stat & highlight cards (records, vendor value, best/richest drop, busiest day)
  plus breakdowns by source, **vendor value** (by source, over time, top items by value),
  quality, item type, bound type, character, hour of day, weekday, Mythic+ keystone level, and
  attribution confidence, with top zones / items — all scoped by a date range and updated live.
- **Retention** — auto-drop records older than a chosen age, or keep everything forever.
- **Minimap button** — left-click opens the window, right-click opens settings.
- **Export-ready** — a forward-compatible `Database:Export()` seam for the v2 AI export feature.

---

## Installation

**From a package site (CurseForge / Wago):** install through your addon manager as usual.

**Manual:**

1. Download or clone this repository.
2. Copy the `LootHistory` folder into `World of Warcraft/_retail_/Interface/AddOns/`.
3. Ensure the folder is named `LootHistory` and contains `LootHistory.toc`.
4. Restart WoW or `/reload`. Enable **Ka0s Loot History** on the character-select AddOns list.

All required libraries are bundled in `libs/` — there are no separate dependencies to install.

---

## Usage

Open the window with the minimap button or a slash command. `/lh` and `/loothistory` are
interchangeable.

| Command | What it does |
|---|---|
| `/lh` | Show the command help |
| `/lh show` · `/lh hide` · `/lh toggle` | Open · close · toggle the window |
| `/lh config` | Open the settings panel |
| `/lh get <path>` | Print a setting's value |
| `/lh set <path> <value>` | Change a setting |
| `/lh list` | List every setting and its value |
| `/lh reset <path>` | Reset one setting to its default |
| `/lh resetall` | Reset all settings to defaults |
| `/lh purge` | Delete ALL recorded history (asks to confirm) |
| `/lh debug` | Toggle the debug console (session-only) |
| `/lh test` | Toggle a preview of every item-binding type in the table (session-only) |
| `/lh help` | Show the full command list |

Inside the window: click a column header to sort, use the filter bar to narrow results, pick a
**Group by** to collapse rows, and switch to the **Insights** tab for analytics.

---

## Configuration

Open with `/lh config` (or right-click the minimap button). Settings are account-wide.

**Master Controls**
- **Enable collection** — master on/off for recording.
- **Hide minimap button** — show or hide the LibDBIcon button.
- **Window scale** — 0.6–1.6× scaling of the browser window.

**Data Collection**
- **Minimum quality** — only record items at or above this quality (default: Common).
- **Keep history for** — retention window; older records are pruned once per session. Choose
  *Always* to keep everything (default: 30 days).
- **Record data from** — per-source toggles; unchecking a source stops recording it.

Everything the panel does is also available from the slash CLI (`/lh set`, `/lh get`, …).

---

## Version History

| Version | Notes |
|---|---|
| 0.1.0 | Initial release — passive capture with source attribution, account-wide history, filter/sort/group browser, Insights analytics, settings panel + slash CLI, minimap button. |

---

## About

- **Author:** add1kted2ka0s
- **License:** [MIT](LICENSE)
- **Slash:** `/lh`, `/loothistory`
- **Saved variables:** `LootHistoryDB` (account-wide)

For the engineering reference (module map, message bus, event wiring, taint notes), see
[`ARCHITECTURE.md`](ARCHITECTURE.md).
