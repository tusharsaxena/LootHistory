# Settings panel — schema-driven Blizzard canvas

The settings surface is registered into Blizzard's **Settings** UI as two canvas categories, both built by `createPanel` in `settings/Panel.lua`:

* A **parent category** ("Ka0s Loot History") renders the **landing page** — logo, one-line tagline, and the slash-command list (`Settings.RegisterCanvasLayoutCategory`, `Panel.lua:448`). This is the target of `/lh config` and a right-click on the minimap button.
* A **General subcategory** holds the actual settings (`Settings.RegisterCanvasLayoutSubcategory`, `Panel.lua:468`). Its header reads `Ka0s Loot History |A forwardarrow|a General` (`buildHeader`, `Panel.lua:58`).

Both share the same gold header design: a `GameFontNormalHuge` title on the left, an `Options_HorizontalDivider` atlas tinted to the title's gold underneath (`Panel.lua:67`), and — on the General subcategory only — a `Defaults` button pinned top-right (an AceGUI `Button`, so its handler is wired with `defaultsBtn:SetCallback("OnClick", …)`, not `:SetScript`; `Panel.lua:456`).

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

Seven rows ship today (`Schema.lua:10`): `settings.enabled`, `minimap.hide`, `settings.windowScale` (Master Controls); `settings.qualityThreshold`, `settings.excludeQuestItems`, `settings.retentionDays`, `settings.excludedSources` (Data Collection). Debug is deliberately **not** a schema row — it is a session-only flag (`NS.State.debug`), toggled via `/lh debug on|off`, never persisted (`Schema.lua:67`).

## Widget primitives and the two-column render

`renderSchema` (`Panel.lua:285`) walks `NS.Schema.Schema` and pairs rows into 50%/50% Flow lines inside the shared `ScrollFrame`. A `group` change flushes the pending row and emits a section `Heading` (centred `GameFontNormalLarge` label flanked by dividers; `section`, `Panel.lua:195`). Widgets dispatch by `row.widget`:

| `widget` | AceGUI primitive | Maker |
|---|---|---|
| `CheckBox` | `CheckBox` | `makeCheckbox` (`Panel.lua:222`) |
| `Dropdown` | `Dropdown` (list from `row.options`) | `makeDropdown` (`Panel.lua:233`) |
| `Slider` | `Slider` (`row.min`/`max`) | `makeSlider` (`Panel.lua:247`) |
| `MultiCheck` | `InlineGroup` of `CheckBox`es | `makeMultiCheck` (`Panel.lua:263`) |

A `wide` / `MultiCheck` row breaks onto its own full-width line. `settings.excludedSources` is the one MultiCheck: it stores a **set of muted sources**, but renders `invert = true` as "Record data from", so a *checked* box means "record this source" and the stored value is the logical inverse of the box state (`Panel.lua:274`).

Each maker pushes a **refresher closure** onto `ctx.refreshers` so the widget can re-sync its display after a Defaults reset or a `/lh set`. Tooltips attach via `attachTooltip` (`Panel.lua:38`), which handles both AceGUI widgets (`SetCallback`) and plain frames (`HookScript`).

## The `Schema:Set` write seam

Every setting mutation — panel widget and `/lh set` alike — routes through `NS.Schema:Set(path, value)` (`Schema.lua:109`):

1. **validate** — reject unknown paths; run the row's optional `validate`.
2. **write** — `WritePath` into `NS.db.global`, storing a `deepcopy` of the value so a reset can't alias the DB to a shared default table (e.g. the `{}` default of `excludedSources`; `Schema.lua:101`).
3. **onChange** — fire the row's hook. Most publish a `Ka0s_LootHistory_SettingsChanged` bus message; `windowScale`/`minimap.hide` reach into the Browser, `retentionDays` triggers `Database:PruneOld`.

`Schema:Get` reads back from `NS.db.global`. Because widgets never touch the DB directly, the CLI and the panel can never diverge. (The Browser's window geometry and saved view are the deliberate carve-out — they persist straight to `NS.db.global`, not through `Schema:Set`; see [saved-variables.md](saved-variables.md) and [conventions.md](conventions.md).)

## Combat-gated, lazily rendered body

Schema rendering is **deferred to the panel's `OnShow`** (a `local rendered = false` guard, `Panel.lua:447`). At registration time (`PLAYER_LOGIN`) `ctx.body` has zero width, so a List-layout pass would size every full-width child to zero. `OnShow` renders once, calls `ctx.scroll:DoLayout()`, and thereafter only re-runs `P:Refresh` to re-sync values. Opening the panel is combat-gated: `P:Open` refuses while `InCombatLockdown()` and prints a notice (`Panel.lua:484`). (The standalone browser window is separately non-secure and *not* combat-gated — that is the §6A pattern, distinct from this §6 canvas panel.)

## History maintenance section

`renderHistory` (`Panel.lua:334`) appends a "History" section unique to this addon: a live stats label paired with a **Purge history…** button.

* **Stats label** reads from `Database:StorageStats` (`Database.lua:331`) — record count, span in days since the earliest record, and an **estimated** SavedVariables byte size rendered via `Util.FormatBytes` (WoW gives addons no way to read the real on-disk size, hence the `≈` and "(estimated)"; `Panel.lua:364`).
* **Purge history…** (the ellipsis signals a confirm) opens the `KA0S_LOOTHISTORY_PURGE` StaticPopup, which calls `Database:Purge` on accept (`Panel.lua:346`, popup at `Slash.lua:8`).
* **Live refresh** — the stats re-compute while the panel is open. `renderHistory` registers on a **private `NS.NewBusTarget()`** (`Panel.lua:374`) for `HistoryChanged` / `RecordAdded`, never on the shared `NS.bus` as `self` — CallbackHandler keys callbacks by `(message, target)`, so sharing a target would clobber the Browser/Analytics consumers of the same messages (see [conventions.md](conventions.md)).

## Reset All companion

`renderSchema` accepts a `companions` map keyed by row `path`; the General panel passes one entry for `settings.windowScale` that adds a **Reset All** button into that same row (`Panel.lua:451`). It opens the `KA0S_LOOTHISTORY_RESETALL` StaticPopup → `Slash:ResetEverything` (`Slash.lua:30`), which **wipes history *and* restores every setting to default**, then refreshes the panel. It shares the exact helper `/lh resetall` funnels through, so popup and CLI cannot diverge. The header's own **Defaults** button (`P:RestoreDefaults`, `Panel.lua:427`) calls the same `CliResetAll` path.

## Ka0s §6.6/§6.10 details this panel implements

**Paired ACTION-button inset (`BUTTON_PAIR_REL = 0.492`).** Both cell-filling action buttons — Reset All and Purge — are created by `makePairButton` (`Panel.lua:214`) at relative width `0.492`, *not* `0.5`. A button whose fill reaches the cell's right edge has its right border shaved by the `ScrollFrame` clip; the ~0.8% inset clears it (§6.6/§6.8). Label-inset controls (CheckBox / Dropdown / Slider) stay at `0.5` — their label gutter already reserves the space, so they're immune (§6.10).

**Always-shown, inert-when-fits scrollbar (§6.10).** `installAlwaysShownScrollbar` (`Panel.lua:109`) rebinds the AceGUI `ScrollFrame`'s `FixScroll` per instance so the scrollbar is shown **once and stays shown**, reserving the 20px right gutter permanently. Stock `FixScroll` hides the bar and reclaims the gutter when content fits, which would shift the body width between the short landing page and the taller General page. The override keeps the gutter reserved so every page's body shares one right-edge x-coordinate; when content fits it parks the thumb at the top and disables the bar and its step buttons (greyed). Because `scrollBarShown` stays permanently true, the override **also** rebinds `MoveScroll` per instance to no-op when the page fits — otherwise AceGUI's stock wheel handler (which only gates on `scrollBarShown`) would drift the parked thumb on a short page with nothing to scroll (smoke-test S-4). The original math is otherwise mirrored (note AceGUI's swapped names: `height` = visible frame height, `viewheight` = content height).
