# Ka0s Loot History — UX Design

**Status:** Approved v1 (2026-07-11) · derives from `REQUIREMENTS.md`, pairs with `TECHNICAL_DESIGN.md`
**Scope:** the standalone window (History + Insights), settings panel, minimap launcher, and all interactions.

User-facing vocabulary only: **Loot History** (the addon), **History** (the table tab),
**Insights** (the analytics tab). The internal terms *Collector* / *Browser* never appear in the UI.

---

## 1. Design principles

- **Browser-first.** The window is the product; opening it is one keystroke/click. Settings are secondary.
- **Dense but legible.** A loot log is inherently tabular — many rows, scannable columns, quality color as the primary visual anchor (matches how players already read loot).
- **No surprises.** Passive capture is silent; nothing pops up while playing. The window only appears when asked.
- **Native feel.** Blizzard-style backdrop, quality colors from `ITEM_QUALITY_COLORS`, LibSharedMedia fonts, standard tooltip on hover. It should feel like part of the Ka0s suite, not a foreign UI.
- **Honest data.** `INFERRED`-source rows are subtly marked so the user trusts the `CERTAIN` ones.

---

## 2. The window

A single movable, resizable frame. Non-secure (usable in combat).

```
┌───────────────────────────────────────────────────────────────────────┐
│  Ka0s Loot History                                          [ ⚙ ] [ X ] │  ← title bar (drag to move)
├───────────────────────────────────────────────────────────────────────┤
│  ┌ History ┐  ┌ Insights ┐                                             │  ← tab strip
│  ├─────────┴──────────────────────────────────────────────────────────┤
│  │ [Quality ▾] [Source ▾] [Character ▾] [Zone ▾]  [🔍 item name…]      │  ← filter bar
│  │ Group by: [ None ▾ ]                                  [ Clear ✕ ]   │
│  ├──────┬───────────────────┬────┬────────┬─────────┬────────┬────────┤
│  │ Time │ Item              │ Qty│ Quality│ Source  │ From   │ Zone   │  ← sortable header
│  ├──────┼───────────────────┼────┼────────┼─────────┼────────┼────────┤
│  │ 14:02│ ⬛ [Epic Sword]    │  1 │ Epic   │ ⚔ Kill  │ Broodt…│ Nerub… │  ← pooled data rows
│  │ 14:01│ ⬛ [Linen Cloth]   │  5 │ Common │ ⚔ Kill  │ Trash  │ Nerub… │
│  │ 13:47│ ⬛ [Flask]         │  2 │ Uncom. │ 📦 Cont.│ Chest  │ Nerub… │
│  │  …                                                                  │  ← virtualized scroll
│  ├───────────────────────────────────────────────────────────────────┤
│  │ 1,284 of 3,902 records                          Last 30 days ▾      │  ← footer
│  └───────────────────────────────────────────────────────────────────┘
└───────────────────────────────────────────────────────────────────────┘
```

- **Title bar:** addon name; gear icon opens the Settings panel; X closes the window (does not disable collection). Drag the bar to move; position and size are persisted in `LootHistoryDB.global.settings.window` (account-wide, across sessions).
- **Resize grip:** bottom-right; min size clamps so headers stay readable. Row count adapts to height (virtualized).
- **Scale:** governed by `settings.windowScale` (0.6–1.6).
- **Default open size:** ~820×520 at scale 1.0 — eight columns visible without horizontal scroll.

---

## 3. History tab

### 3.1 Columns

| Column | Content | Sort key | Align |
|---|---|---|---|
| **Time** | `HH:MM` (today) or `MM/DD HH:MM` (older); tooltip shows full local datetime | `ts` | left |
| **Item** | item icon + quality-colored `[Name]`; `INFERRED` rows get a small dim dot before the icon | `itemName` | left, flex |
| **Qty** | quantity (blank if 1 for calm density, or shown — configurable later; v1 shows always) | `quantity` | right |
| **Quality** | quality label, quality-colored | `quality` (numeric) | left |
| **Source** | source icon + short label (Kill/Container/Mail/Trade/AH/Quest/Vendor/Craft/Roll/M+/Other) | `source` | left |
| **Zone** | zone name; subzone in tooltip | `zone` | left |
| **Character** | `Name` (realm in tooltip); shown when account has >1 character | `char` | left |

- The **Character** column auto-hides when only one character has records (reduces noise for single-char users); it always exists as a filter.
- Long text truncates with an ellipsis; the full value is in the row tooltip / item tooltip.

### 3.2 Sorting

- Click a header to sort by it; the active header shows a ▲/▼ glyph. Re-click toggles direction.
- Default sort: **Time, descending** (newest first).
- Sort is stable — equal keys keep time order.

### 3.3 Filtering

The filter bar sits above the header. All filters combine with AND:

The five column dropdowns (Quality / Type / Source / Zone / Character) are **multi-select**: each
item toggles on click (a ✓ marks it), the menu stays open so several can be picked in one visit,
and the "…: All" row clears the whole set. The collapsed button summarizes as `…: All`, the single
label, or `…: N selected`.

- **Quality ▾** — "All / Common / Uncommon / Rare / Epic / Legendary"; each item tinted its quality
  colour. Filters the **exact** qualities selected (not "and above" — that's the recording threshold
  in Settings, a separate control).
- **Type ▾** — the item types present in the data.
- **Source ▾** — the source types present in the data.
- **Zone ▾** — the zones present in the data.
- **Character ▾** — the characters present; each item shows its inline class icon and class colour.
  Paired with a **Current / All players** scope toggle (right of the bar) that shares the same
  filter — selecting specific characters reads back as "N characters" on the toggle.
- **🔍 search box** — case-insensitive substring match on item name; updates as you type.
- **Clear ✕** — resets every filter back to the saved view and the scope to Current player.

Dropdown option lists are derived from the current dataset, so they never show empty/irrelevant choices.

### 3.4 Grouping

- **Group by ▾** — None / Source / Zone / Character / Quality / Day.
- When grouping is on, rows are bucketed under **collapsible headers**: `▼ Kill — 412 items` (click to collapse to `▶`). Counts reflect the active filter.
- Group order: by count descending (Source/Zone/Character/Quality) or chronological (Day, newest first). Collapse state is remembered while the window stays open.

### 3.5 Row interactions

- **Hover** any row → the full item tooltip (`GameTooltip:SetHyperlink`), plus a second line with exact loot time and subzone.
- **Shift-click** the item → inserts the item link into the chat edit box.
- **Right-click** the row → context menu:
  - *Link to chat*
  - *Delete this entry* (removes the single record; the footer count updates)

### 3.6 Footer

- Left: `<visible> of <total> records` (reflects filters).
- Right: **date-range selector** (Today / 7 days / 30 days / All) scoping the table (mirrors the Insights range control, but independent per tab).

### 3.7 Empty & loading states

- **No records at all:** centered message — "No loot recorded yet. Go kill something." with a hint that collection is active (or a warning + button if collection is disabled).
- **No matches for filters:** "No records match your filters." + a *Clear filters* button.

---

## 4. Insights tab

A vertically scrolling panel of frame-based visualizations. A **date-range selector**
(Today / 7d / 30d / All) at the top scopes everything below.

```
┌ Insights ─────────────────────────────────────────────────────────────┐
│  Range: [ 30 days ▾ ]                                                   │
│  ┌─────────┐ ┌─────────┐ ┌───────────┐ ┌───────────────┐               │
│  │ 3,902   │ │  418    │ │    5      │ │ Jun 11–Jul 11 │  ← stat cards  │
│  │ records │ │ items   │ │ chars     │ │ date range    │               │
│  └─────────┘ └─────────┘ └───────────┘ └───────────────┘               │
│                                                                        │
│  Loot by source                                                        │
│  Kill      ████████████████████████░░░░░░  62%                         │
│  Container ██████████░░░░░░░░░░░░░░░░░░░░░  24%                         │
│  Roll      ████░░░░░░░░░░░░░░░░░░░░░░░░░░░   8% …                       │
│                                                                        │
│  Quality distribution                                                  │
│  Uncommon  ██████████████████░░░░  1,880   (green bar)                 │
│  Rare      ████████░░░░░░░░░░░░░░    920   (blue bar) …                │
│                                                                        │
│  Loot over time (per day)                                              │
│  ▁▂▅▇▃▂▁▄█▆▂▁▃▅▇…                                                       │
│                                                                        │
│  ┌ Top zones ───────────┐   ┌ Top items ─────────────────┐            │
│  │ Nerub-ar Palace  902 │   │ [Linen Cloth]          220 │            │
│  │ Azj-Kahet        640 │   │ [Weathered Crest]      140 │            │
│  │ …                    │   │ ★ [Epic Sword]          3  │ ← rare hi-lite│
│  └──────────────────────┘   └────────────────────────────┘            │
└────────────────────────────────────────────────────────────────────────┘
```

- **Stat cards:** total records, distinct items, distinct characters, covered date span.
- **Loot by source:** horizontal bars, sorted descending, each colored per source, with % and count.
- **Quality distribution:** horizontal bars colored with the quality colors, showing counts.
- **Loot over time:** compact per-day bar strip across the selected range; hover a bar for the day + count.
- **Top zones / Top items:** two ranked lists (top 10). In Top items, epic+ drops get a ★ highlight so rare finds stand out from bulk mats.
- All widgets recompute when the range changes; rendering reuses pooled bar frames.

---

## 5. Settings panel

Registered in the Blizzard **Settings** UI (`Settings.RegisterCanvasLayoutCategory`),
body built lazily with raw AceGUI, combat-lockdown-gated on open. Opened via the window's
gear icon or `/lh config`.

Sections and controls:

- **Collection**
  - *Enable loot collection* (checkbox, master switch)
  - *Minimum quality to record* (dropdown: Common / Uncommon / Rare / Epic / Legendary — default Uncommon)
  - *Don't record from* (checklist of sources to mute, e.g. Vendor, Craft — default none muted)
- **History**
  - *Keep history for* (dropdown: 7 / 14 / 30 / 60 / 90 / 180 / 365 days / Never — default 30 days)
  - Helper text: "Older records are removed automatically when you log in."
- **Interface**
  - *Show minimap button* (checkbox)
  - *Window scale* (slider 0.6–1.6)
- **Advanced**
  - *Debug logging* (checkbox)
  - *Reset all settings* (button → confirm)

Each control writes through `Schema:Set`; changes apply immediately (scale live-updates the window, minimap toggles the button, retention change triggers a prune).

---

## 6. Minimap / launcher

- LibDBIcon-1.0 minimap button with the addon icon.
- **Left-click:** toggle the window.
- **Right-click:** open Settings.
- **Tooltip:** addon name + line "N records • last: <item> <time ago>" + click hints.
- Hideable via *Show minimap button* (the LDB launcher still works for Titan/ElvUI databroker displays).

---

## 7. Visual language

- **Backdrop:** dark Blizzard-style panel with a subtle border (LibSharedMedia-registered texture; falls back to a Blizzard default).
- **Quality color** is the dominant accent — item names and quality labels use `ITEM_QUALITY_COLORS`.
- **Source icons:** small consistent glyphs per source (kill = crossed swords, container = box, mail = envelope, trade = handshake, AH = coin, quest = "?", vendor = bag, craft = anvil/hammer, roll = dice, M+ = keystone, other = dot). Reuse Blizzard atlas icons where available (via Compat) to avoid shipping art.
- **Typography:** one UI font via LibSharedMedia; header row slightly bolder; monospace-ish alignment for the Time and Qty columns.
- **INFERRED marker:** a small dim dot before the item; tooltip explains "source inferred".
- **Row striping:** alternating subtle row backgrounds for scanability; hover highlight; selected-row highlight on right-click.

---

## 8. Interaction summary

| Action | Result |
|---|---|
| `/lh` | Show help |
| `/lh show` / `hide` / `toggle` | Explicit window control |
| `/lh config` | Open Settings |
| Minimap left / right click | Toggle window / open Settings |
| Click column header | Sort by column (toggle direction) |
| Filter dropdowns / search | Narrow the visible rows |
| Group by | Bucket rows under collapsible headers |
| Hover row | Item tooltip + loot detail |
| Shift-click item | Link to chat |
| Right-click row | Link to chat / delete entry |
| Change date range (footer / Insights) | Rescope table / analytics |

---

## 9. Accessibility & polish

- All interactive controls have hover tooltips explaining their effect.
- Color is never the *only* signal: quality also shows as a text label; source shows an icon *and* a word; INFERRED shows a marker *and* a tooltip.
- Keyboard: `Escape` closes the window when focused (registered as a special frame in `UISpecialFrames` so it participates in the standard close-stack).
- The window remembers its last tab within a session.

---

## 10. Deferred (v2) UX

- An **Export** affordance (button in the window or a `/lh export` verb) that opens a copy box with the serialized history, paired with the AI companion skill. Not shown in v1; the layout leaves room in the title bar / settings for it.

---

*End of UX design.*
