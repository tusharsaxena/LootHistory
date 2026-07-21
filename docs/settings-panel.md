# Settings panel — schema-driven Blizzard canvas

The settings surface is registered into Blizzard's **Settings** UI as a parent category with two subcategories, all built by `createPanel` in `settings/Panel.lua`:

* A **parent category** ("Ka0s Loot History") renders the **landing page** — logo, one-line tagline, and the slash-command list (`Settings.RegisterCanvasLayoutCategory`). This is the target of `/lh config` and a right-click on the minimap button.
* A **General subcategory** holds the schema-driven settings (`Settings.RegisterCanvasLayoutSubcategory`). Its header reads `Ka0s Loot History |A forwardarrow|a General`.
* A **Filters subcategory** holds the blacklist / whitelist management UI (issue #14) — a custom, non-schema page (see below).

All share the same gold header design: a `GameFontNormalHuge` title on the left, an `Options_HorizontalDivider` atlas tinted to the title's gold underneath (`Panel.lua:69`), and — on the General subcategory only — a `Defaults` button pinned top-right (an AceGUI `Button`, so its handler is wired with `defaultsBtn:SetCallback("OnClick", …)`, not `:SetScript`; `Panel.lua:597`).

`createPanel` returns a `ctx` table (`{ panel, body, scroll, refreshers, lastGroup }`) that every layout helper threads through. `ctx.scroll` is the AceGUI `ScrollFrame` hosting the schema widgets, created lazily on first widget add (`ensureScroll`, `Panel.lua:174`). The General ctx is stashed at `P.general` so `P:Refresh` can re-sync widgets after a slash-cmd write.

## `NS.Schema.Schema` is the single source of truth

`settings/Schema.lua` declares every option as a row in one flat array. Each row:

```lua
{
  path    = "settings.qualityThreshold",  -- dotted db.global path (account-wide, NOT .profile)
  default = 1,
  type    = "number"|"boolean"|"table",
  widget  = "CheckBox"|"Dropdown"|"Slider"|"MultiCheck",
  group   = "Data Collection",            -- section-heading text
  label   = "Minimum quality",
  tooltip = "Only record items at or above this quality.",
  options = C.QUALITY_OPTIONS,            -- { {value=, label=}, … } for Dropdown/MultiCheck
  min, max,                               -- Slider bounds
  wide    = true,  invert = true,         -- MultiCheck-only flags
  onChange = function(v) … end,           -- side-effect hook (usually a bus message)
}
```

The same row drives four surfaces — panel widget, `/lh get`, `/lh set`, and `/lh list|reset` (see [slash-dispatch.md](slash-dispatch.md)). **Adding an option = one schema row.** UI widget, slash CLI, and reset wire themselves.

Eleven rows ship today (`Schema.lua:11`): `settings.enabled`, `minimap.hide`, `state.debugConsole`, `settings.windowScale` (Master Controls); `settings.qualityThreshold`, `settings.retentionDays`, `settings.recordCurrency`, `settings.excludeQuestItems`, `settings.excludedSources` (Data Collection); `settings.auction.enabled`, `settings.auction.capture` (AH Price — the latter carries `panelSkip`, driven by the price table rather than a rendered widget).

**Session-only rows.** Most rows persist to `NS.db.global`, but a row marked `sessionOnly = true` carries `get`/`set` accessors and is **never written to the DB** — `Schema:Set` routes to `row.set` instead of `WritePath`, `Schema:Get` reads `row.get`, and `Register` skips its default check. `state.debugConsole` (label "Debug console") is the one such row: it toggles the debug console **window's visibility** via `NS.DebugLog:Show/Hide/IsShown` — *not* the `NS.State.debug` logging flag (that stays non-schema, set via `/lh debug on|off`). It mirrors `/lh debug` (no-arg); `DebugLog` calls `NS.Panel:Refresh()` on show/hide so the checkbox stays in sync when the window is toggled elsewhere. This is a flagged deviation from schema-persist-everything (see [agent-context.md](agent-context.md)).

## Widget primitives and the two-column render

`renderSchema` (`Panel.lua:297`) walks `NS.Schema.Schema` and pairs rows into 50%/50% Flow lines inside the shared `ScrollFrame`. A `group` change flushes the pending row and emits a section `Heading` (centred `GameFontNormalLarge` label flanked by dividers; `section`, `Panel.lua:195`). A `MultiCheck` or `row.wide` row takes a full-width line of its own; a `row.soloRow` row flushes any half-filled pending line and then sits alone on its row (used by `state.debugConsole`, so the Master Controls section reads `[Enable collection] [Hide minimap button]` / `[Debug console]` / `[Window scale]`). Widgets dispatch by `row.widget`:

| `widget` | AceGUI primitive | Maker |
|---|---|---|
| `CheckBox` | `CheckBox` | `makeCheckbox` (`Panel.lua:222`) |
| `Dropdown` | `Dropdown` (list from `row.options`) | `makeDropdown` (`Panel.lua:233`) |
| `Slider` | `Slider` (`row.min`/`max`) | `makeSlider` (`Panel.lua:247`) |
| `MultiCheck` | `InlineGroup` of `CheckBox`es | `makeMultiCheck` (`Panel.lua:263`) |

A `wide` / `MultiCheck` row breaks onto its own full-width line. `settings.excludedSources` is the one MultiCheck: it stores a **set of muted sources**, but renders `invert = true` as "Record data from", so a *checked* box means "record this source" and the stored value is the logical inverse of the box state (`Panel.lua:276`).

Each maker pushes a **refresher closure** onto `ctx.refreshers` so the widget can re-sync its display after a Defaults reset or a `/lh set`. Tooltips attach via `attachTooltip` (`Panel.lua:38`), which handles both AceGUI widgets (`SetCallback`) and plain frames (`HookScript`).

## The `Schema:Set` write seam

Every setting mutation — panel widget and `/lh set` alike — routes through `NS.Schema:Set(path, value)` (`Schema.lua:124`):

1. **validate** — reject unknown paths; run the row's optional `validate`.
2. **write** — `WritePath` into `NS.db.global`, storing a `deepcopy` of the value so a reset can't alias the DB to a shared default table (e.g. the `{}` default of `excludedSources`; `Schema.lua:101`).
3. **onChange** — fire the row's hook. Most publish a `Ka0s_LootHistory_SettingsChanged` bus message; `windowScale`/`minimap.hide` reach into the Browser, `retentionDays` triggers `Database:PruneOld`.

`Schema:Get` reads back from `NS.db.global`. Because widgets never touch the DB directly, the CLI and the panel can never diverge. (The Browser's window geometry, saved view, and the `blacklist`/`whitelist` id lists are the deliberate carve-outs — they persist straight to `NS.db.global`, not through `Schema:Set`; see [saved-variables.md](saved-variables.md) and [conventions.md](conventions.md).)

## Combat-gated, lazily rendered body

Schema rendering is **deferred to the panel's `OnShow`** (a `local rendered = false` guard, `Panel.lua:599`). At registration time (`PLAYER_LOGIN`) `ctx.body` has zero width, so a List-layout pass would size every full-width child to zero. `OnShow` renders once, calls `ctx.scroll:DoLayout()`, and thereafter only re-runs `P:Refresh` to re-sync values. Opening the panel is combat-gated: `P:Open` refuses while `InCombatLockdown()` and prints a notice (`Panel.lua:639`). (The standalone browser window is separately non-secure and *not* combat-gated — that is the standalone-windows pattern, distinct from this options-ui-§2 canvas panel.)

## History maintenance section

`renderHistory` (`Panel.lua:336`) appends a "History" section unique to this addon: a live stats label paired with a **Purge history…** button.

* **Stats label** reads from `Database:StorageStats` (`Database.lua:383`) — record count, span in days since the earliest record, and an **estimated** SavedVariables byte size rendered via `Util.FormatBytes` (WoW gives addons no way to read the real on-disk size, hence the `≈` and "(estimated)"; `Panel.lua:365`).
* **Purge history…** (the ellipsis signals a confirm) opens the `KA0S_LOOTHISTORY_PURGE` StaticPopup, which calls `Database:Purge` on accept (`Panel.lua:348`, popup at `Slash.lua:8`).
* **Live refresh** — the stats re-compute while the panel is open. `renderHistory` registers on a **private `NS.NewBusTarget()`** (`Panel.lua:376`) for `HistoryChanged` / `RecordAdded`, never on the shared `NS.bus` as `self` — CallbackHandler keys callbacks by `(message, target)`, so sharing a target would clobber the Browser/Analytics consumers of the same messages (see [conventions.md](conventions.md)).

## Reset All companion

`renderSchema` accepts a `companions` map keyed by row `path`; the General panel passes one entry for `settings.windowScale` that adds a **Reset All** button into that same row. It opens the `KA0S_LOOTHISTORY_RESETALL` StaticPopup → `Slash:ResetEverything`, the **total destructive reset**: it wipes history, restores every setting, clears the blacklist/whitelist, drops `savedView` to stock, and recenters the window, then refreshes the panel. The header's own **Defaults** button (`P:RestoreDefaults`) calls the non-destructive `CliResetAll` path — schema settings + filter lists only, no history/view/window. See [saved-variables.md](saved-variables.md#reset-semantics) for the full scope matrix.

## Filters subcategory — blacklist / whitelist (issue #14)

A **second subcategory, "Filters"**, is a deliberately non-schema page: a dynamic list of item ids has no Schema widget to express, so `buildFilters` builds custom AceGUI instead of `renderSchema`. One page, two sections (`makeFilterSection`):

* **Blacklist** — ids that are never recorded when looted from now on. Point-in-time: existing rows are left untouched (delete them from the history table if you want them gone).
* **Whitelist** — ids that are always recorded, bypassing the quality / source / quest gates. Also point-in-time: removing an id from the whitelist stops future rescues but does not touch rows already recorded under it.

Each section is a heading + description + an **add row** (an `EditBox` accepting a bare item id **or** a shift-clicked item link, parsed by `NS.Filters:ParseItemID`, plus an `Add` button) + a **Clear all** button (confirm-gated → `Filters:ClearList`, for emptying the list without a full settings reset) + a **live list** (`rebuildFilterList`) of the current ids, each a label (`NS.Compat.ItemNameQuality` resolves the name; a background `LoadItem` fills in names not yet cached) with a **Remove** button. Adds/removes go through `NS.Filters` (`modules/Filters.lua`), which mutates copy-on-write and fires `SettingsChanged` + `HistoryChanged`. The page live-rebuilds both lists on a **private `NS.NewBusTarget()`** (`HistoryChanged`), so the History right-click **Blacklist item** action reflects here immediately while the panel is open.

### Structural refresh is gated (options-ui-§11)

`rebuildFilterList` is a **structural** rebuild — it `ReleaseChildren()`s the list and recreates a widget per id — so it is registered as a **rebuilder**, not a scalar refresher, and runs only on **first paint**, on an **on-screen edit** (Add / Remove), and on the **next `OnShow` after an off-screen change**. Running it on *every* `OnShow` (as the page originally did) meant an AceGUI teardown+rebuild of both lists on every tab click; with a large blacklist that stalled the client for ~1s — **anti-pattern #39**, the same freeze fixed in Ka0s Consumable Master. The gate: the `HistoryChanged` bus listener repaints immediately while the page `IsShown()`, otherwise sets `fctx.dirty`; `OnShow` calls `runRebuilders` only when first-rendered or dirty, then clears the flag. Scalar widgets (there are none on Filters today, but the AH Price page's master `enabled` checkbox) refresh **in place** via `ctx.refreshers` every `OnShow`; only structural row rebuilds are gated.

### AH Price table — frame-light, reused slots

The **AH Price** page is a single unified table (`buildAuctionTable`) — one row per known `"provider:key"` source, columns `[tick] [Addon] [Price Module (+ⓘ)] [Order ▲▼] [On ☑] [Status]`. It replaced the old Data Collection + Priority sections, and the redesign was forced by a **second Blizzard-canvas stall**: the old page built ~213 AceGUI frames (11 priority rows × label/`Icon`/checkbox widgets, plus an 11-row capture checklist), and the Settings canvas does a **super-linear pass over a panel's frames on tab-transition**, so *leaving* the AH Price page froze the client ~1.7s (measured; General at 87 frames never tripped it). The fix is structural, not a refresh-gate: every text column is a **FontString** (a region, not a frame), only the checkbox / ⓘ / arrows are real frames, and the row slots + their frames are **created once and reused** — `refreshAuctionTable` repaints them in place on every toggle/reorder/Defaults, never re-allocating — keeping the page to ~50 frames. The single per-row **Enabled** checkbox writes `settings.auction.capture` (collect **and** rank in one flag — an unticked source is neither collected nor ranked; there is no separate disabled-set). Rows sort into three groups, natural priority order preserved within each: **Collecting** (ticked + addon installed) on top, then **Not collecting**, then **Addon not installed** — each dimmed further, only the Collecting group carries working reorder arrows. The Status column is colour-coded in muted green/yellow/red; the ⓘ trails each Price Module label (positioned per-row from its text width); a not-installed source reads unchecked and non-interactive. `refreshAuctionTable` is registered as a rebuilder (fired on the page's own on-screen edits and by Defaults); its data has no off-screen mutation path, so it never needs the dirty flag.

Like every subcategory, the Filters page also carries a top-right **Defaults** button (options-ui-§5). Here it means "reset the filters to their stock state" — both lists empty — so it is confirm-gated (`KA0S_LOOTHISTORY_CLEAR_FILTERS`) and clears **both** lists at once via `NS.Filters:ClearAll`, distinct from the two per-section **Clear all** buttons which each empty one list. It live-refreshes through the same `HistoryChanged` listener.

The lists are **core app logic** and act point-in-time, so there is intentionally no user-facing blacklist/whitelist *display* filter in the browser — blacklisting an id only stops future captures, and whitelisting an id only rescues future loots that would otherwise fail the gate; neither list ever hides or restores an already-stored row.

## Ka0s options-ui-§6/§8/§10 details this panel implements

**Paired ACTION-button inset (`BUTTON_PAIR_REL = 0.492`).** Both cell-filling action buttons — Reset All and Purge — are created by `makePairButton` (`Panel.lua:214`) at relative width `0.492`, *not* `0.5`. A button whose fill reaches the cell's right edge has its right border shaved by the `ScrollFrame` clip; the ~0.8% inset clears it (options-ui-§6/§8). Label-inset controls (CheckBox / Dropdown / Slider) stay at `0.5` — their label gutter already reserves the space, so they're immune (options-ui-§10).

**Always-shown, inert-when-fits scrollbar (options-ui-§10).** `installAlwaysShownScrollbar` (`Panel.lua:109`) rebinds the AceGUI `ScrollFrame`'s `FixScroll` per instance so the scrollbar is shown **once and stays shown**, reserving the 20px right gutter permanently. Stock `FixScroll` hides the bar and reclaims the gutter when content fits, which would shift the body width between the short landing page and the taller General page. The override keeps the gutter reserved so every page's body shares one right-edge x-coordinate; when content fits it parks the thumb at the top and disables the bar and its step buttons (greyed). Because `scrollBarShown` stays permanently true, the override **also** rebinds `MoveScroll` per instance to no-op when the page fits — otherwise AceGUI's stock wheel handler (which only gates on `scrollBarShown`) would drift the parked thumb on a short page with nothing to scroll (smoke-test S-4). The original math is otherwise mirrored (note AceGUI's swapped names: `height` = visible frame height, `viewheight` = content height).
