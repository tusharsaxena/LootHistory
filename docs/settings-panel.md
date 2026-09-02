# Settings panel — schema-driven Blizzard canvas

The settings surface is registered into Blizzard's **Settings** UI as a parent category with **one** subcategory. The canvas itself is **`LibKa0s-Options-1.0`**: `settings/OptionsSetup.lua` builds the instance (`lib:New`) and publishes it as `NS.Options`, and `settings/Panel.lua` takes it as the file-scope upvalue `O` (`Panel.lua:10`) and supplies only what is genuinely this addon's — the page builder, the renderer, and the three bespoke bodies (the id-lists, the AH price table, the landing page).

**One sub-page, six tabs.** There were three sub-pages until R6 — General, Filters and AH Price — each with its own strip, and one of the three drew no strip at all. A player looking for a setting had to guess which of the three held it, and the strip-less one looked broken beside the other two. Filters and AH Price are **tabs on General's strip** now, their bodies unchanged, and their two `RegisterCanvasLayoutSubcategory` calls are gone.

* A **parent category** ("Ka0s Loot History") renders the **landing page** — logo, one-line tagline, and the slash-command list. The library registers it (`registerMain`, `Options.lua:785`) and draws its body through the descriptor's `buildMain` hook (`OptionsSetup.lua:140`), which late-binds to `P.BuildMain` (`Panel.lua:924`) because `settings/Panel.lua` loads *after* the setup file. This is the target of `/lh config` and a right-click on the minimap button.
* A **General subcategory** holds everything else (`O.RegisterOptionsPage`, `Panel.lua`). Its header reads `Ka0s Loot History |A forwardarrow|a General`, and its strip is six tabs: **Master controls · Collection · Filters · AH Price · Interface · Maintenance**.

Every canvas frame comes from `O.CreatePanel` (`Options.lua:345`). The **main canvas is a named frame** — `LootHistorySettingsPanel`, passed as the descriptor's `mainPanelName` (`OptionsSetup.lua:100`) — so `/framestack` attributes it to this addon and two addons cannot collide on it; it was anonymous before the adoption. `CreatePanel` also stamps the three Blizzard canvas callbacks: `OnCommit` and `OnRefresh` are inert by design (writes land immediately through `Schema:Set`, and `SetRenderer` already owns re-show), while **`OnDefault` is a forwarder** into `panel.defaultsOnClick` (`Options.lua:375`) rather than an assignment — every page parks its handler *after* `CreatePanel` returns, so an assignment would capture `nil` forever. That is what makes the Blizzard Settings window's own **footer** Defaults control work; it was dead before.

Both pages share the same gold header design, built by `buildHeader` (`Options.lua:309`): a `GameFontNormalHuge` title on the left (breadcrumbed as `<Brand> ▸ <Page>` on every subcategory via `STRINGS.BREADCRUMB_SEP`, `Options.lua:207`), an `Options_HorizontalDivider` atlas tinted to the title's own font color underneath (`Options.lua:328`), and — on the subcategory — a `Defaults` button pinned top-right.

That button is an AceGUI `Button` (options-ui-§5), so its handler is wired with `SetCallback("OnClick", …)`, not `:SetScript` — but it is **built lazily, on the panel's first `OnShow`** (`O.EnsureDefaultsButton`, `Options.lua:429`), never at registration time. `buildHeader` only records the intent (`panel.wantsDefaultsButton`, `Options.lua:337`) and the click handler is parked on the panel as `panel.defaultsOnClick` until the button exists. The reason is a load-order race: AceGUI is a **shared** library that UI-skinning addons restyle by hooking `RegisterAsWidget`, and `P:Register()` runs in `OnInitialize` (ADDON_LOADED) — a widget created there can miss the hook and keep Blizzard's stock red-stone `UI-Panel-Button-Up` art for the session, which is exactly why the lazily-built page-body buttons looked right while this one did not. First `OnShow` is after every addon has loaded, so the race is gone. Do not "simplify" it back to registration time (anti-patterns #42).

`O.CreatePanel` returns the `ctx` table (`{ panel, body, scroll, refreshers, lastGroup, pageKey }`, `Options.lua:398`) that every layout helper threads through; the page builder adds this addon's own `ctx.rebuilders` list on top. `ctx.scroll` is the AceGUI `ScrollFrame` hosting the widgets, created lazily on first widget add (`O.EnsureScroll`, `Options.lua:506`). The General ctx is stashed at `P.general` — the only one now — and `P:Refresh` calls `O.RefreshScalars`, which sweeps every registered page.

Three fields on that ctx are this addon's and outlive a render: **`ctx._priHost`** (the AH price table's pooled host frame, parked on the panel while another tab is on screen), **`ctx._priRows`** (its eleven reusable row slots) and **`ctx._priList`** (the live reorder controller, cancelled at the top of every render). A fourth, **`ctx.activeSubTab`**, is the Filters tab's secondary-strip selection, keyed by the primary tab and never persisted. All four are explained under *The Filters tab* and *The AH Price tab* below.

If `LibKa0s-Options-1.0` is missing, `settings/OptionsSetup.lua:53` publishes a **no-op page registry** rather than erroring: every member `settings/Panel.lua` reaches for still answers, and `/lh config` prints the shared `NS.LIBKA0S_MISSING` cause with "so the settings panel is unavailable." appended.

## `NS.Schema.Schema` is the single source of truth

`settings/Schema.lua` declares every option as a row in one flat array. Each row:

```lua
{
  path    = "settings.qualityThreshold",  -- dotted db.global path (account-wide, NOT .profile)
  default = 1,
  type    = "bool"|"number"|"table",      -- the LIBRARY dispatches on this
  widget  = "CheckBox"|"Dropdown"|"Slider"|"MultiCheck",  -- declarative; see below
  page    = "General",                    -- the canvas SUBCATEGORY (the library's pageKey)
  group   = "Collection",                 -- the TAB within that page (options-ui-§13)
  label   = "Minimum quality",
  tooltip = "Only record items at or above this quality.",
  values  = C.QUALITY_OPTIONS,            -- { {value=, text=}, … } for enum rows
  min, max,                               -- Slider bounds
  wide    = true,  invert = true,         -- host-drawn MultiCheck flags
  solo    = true,                         -- render alone in the left half of its own line
  skipRender = true,                      -- stays in the schema; the host draws it bespoke
  onChange = function(v) … end,           -- side-effect hook (usually a bus message)
}
```

The **row vocabulary is LibKa0s's** (`Schema.lua:32`), and four names moved when it was adopted — none of which would have failed loudly: `type = "boolean"` → `"bool"`, `options` → `values` (with each entry's `label` → `text`, in `core/Constants.lua:88` / `:110`), `soloRow` → `solo`, `panelSkip` → `skipRender`. A row that kept an old spelling does not error; it silently vanishes from its page and answers ERR_TYPE on every `set`. `tooltip` deliberately did **not** move: the library reads `tooltip` first and its own `desc` second (`OptionsWidgets.lua:41`). `widget`, `wide`, `invert`, `sessionOnly`, `fmt`, `get`, `set` and `onChange` stay this addon's — note that `widget` and `wide` are now **declarative only**: the renderer dispatches on `type` and reads neither, so they are documentation plus a hint for a future host-drawn control, not switches anything acts on. `invert` is the one of the three that is still read — by `makeMultiCheck`.

The same row drives four surfaces — panel widget, `/lh get`, `/lh set`, and `/lh list|reset` (see [slash-dispatch.md](slash-dispatch.md)). **Adding an option = one schema row.** UI widget, slash CLI, and reset wire themselves.

**Sixteen rows ship today**, on one schema-backed page across five schema tabs (the sixth tab, Filters, holds no rows at all):

| Page | Tab | Rows | Paths, in declaration order |
|---|---|---|---|
| General | **Master controls** | 6 | `settings.enabled`, `settings.visibility`, `settings.scale`, `settings.alpha`, `settings.locked`, `state.debugConsole` |
| General | **Collection** | 4 | `settings.qualityThreshold`, `settings.recordCurrency`, `settings.excludeQuestItems`, `settings.excludedSources` |
| General | **AH Price** | 2 | `settings.auction.enabled`, `settings.auction.capture` |
| General | **Interface** | 3 | `settings.windowScale`, `settings.rowHeight`, `minimap.hide` |
| General | **Maintenance** | 1 | `settings.retentionDays` |

The **Master controls** block is **composed, never hand-written**: `O.MasterControls` (`OptionsCompose.lua:337`) emits the canonical eight — six rows plus the closing button pair — from one declaration in `settings/Schema.lua`, which is what stops nine addons drifting into nine orders (options-ui-§15). This addon passes `prefix = "settings."`, its own `defaults` (so `defaults/Global.lua` stays the one declaration site for every shipped value) and both reset handlers; it is **not** `frameless`, because `modules/Browser.lua` and `modules/Export.lua` both call `SetMovable(true)`, so it draws all four frame-only rows. What the composer does not know — this addon's `onChange` hooks, the `fmt` the CLI prints a scale with, and the console toggle's `get`/`set` — is stamped onto the emitted rows by path (`stamp`, `Schema.lua`), never typed into a second copy of the block.

`settings.excludedSources` and `settings.auction.capture` are rows that draw no widget on the generic path (the first is `type = "table"`, the second carries `skipRender`); both are host-drawn from `afterGroup`. `settings.auction.capture` also **declares the "Price sources" subsection heading** — `startSubgroup` runs before the `skipRender` check, so a row that draws nothing still opens its subsection, which is how the price table gets a heading without a builder drawing one (options-ui-§7). The **Maintenance** tab is the sanctioned exemption from the two-controls-per-tab rule, exempted **by name** in `tests/test_schema.lua`: its one stored row shares the tab with two bespoke controls that have no path — the live storage readout and **Purge history…**.

**Session-only rows.** Most rows persist to `NS.db.global`, but a row marked `sessionOnly = true` carries `get`/`set` accessors and is **never written to the DB** — `Schema:Set` routes to `row.set` instead of `WritePath` (`Schema.lua:229`), `Schema:Get` reads `row.get` (`Schema.lua:242`), and `Register` skips its default check. `state.debugConsole` (label "Debug console", `Schema.lua:139`) is the one such row: it toggles the debug console **window's visibility** via `NS.DebugLog:Show/Hide/IsShown` — *not* the `NS.State.debug` logging flag (that stays non-schema, set via `/lh debug on|off`). It mirrors `/lh debug` (no-arg); the console's `onVisibilityChanged` seam calls back so the checkbox stays in sync when the window is toggled elsewhere — including with Esc or the × button, which never synced before the console moved onto `LibKa0s-DebugLog-1.0`. This is a flagged deviation from schema-persist-everything (see [ARCHITECTURE.md](ARCHITECTURE.md#standards-compliance)).

## Widget primitives and the two-column render

`O.RenderRows` (`OptionsWidgets.lua:1442`) walks a list of rows and pairs them into 50%/50% Flow lines inside the shared `ScrollFrame`; `O.RenderSchema` (`OptionsWidgets.lua:1483`) is the thin wrapper that fetches one page's rows from the descriptor's `rowsForPage` (`OptionsSetup.lua:116`), which matches `pageKey` against the row's **`page`** — not its `group`, which is now the tab within that page. It matched `group` while every page held exactly one section and the two were the same string; General spans **six** tabs now, and matching on group would hand `RenderTabbedSchema` one tab's rows and let it conclude the page has one section. A `group` change flushes the pending row and emits a section `Heading` (centered `GameFontNormalLarge` label flanked by dividers; `O.Section`, `OptionsWidgets.lua:652`). `row.wide` is **not** read on this path — the engine's full-width flag belongs to `O.RenderGrid`'s item shape (`OptionsWidgets.lua:1401`), which this addon never calls, and of its two `wide` rows only `settings.auction.capture` carries `skipRender` — `settings.excludedSources` draws nothing on this path because it is `type = "table"`, which `O.RenderField` does not dispatch, and is host-drawn from `afterGroup`; a `row.solo` row flushes any half-filled pending line and then sits alone on its row (`OptionsWidgets.lua:1465`) — **no row in this addon carries it any more**: `state.debugConsole` did, and the argument was positional (it sat between the Enable/Hide-minimap pair and the Window scale row), so it went the first time the tabs moved it. It has moved once more since: options-ui-§15 puts the console toggle on **Master controls**, where `O.MasterControls` emits it as the sixth ordinary row and it pairs with **Lock frame** (see [The Master controls tab](#the-master-controls-tab)) — the composer sets `solo` on nothing; a `row.skipRender` row is walked but not drawn (`OptionsWidgets.lua:1464`). **Every row renders under its own `pcall`** (`OptionsWidgets.lua:155`): one corrupt saved value costs that row and prints `settings row '<path>' failed to render`, where it used to take the whole page down mid-way from inside AceGUI's layout pass. Page *builders* are guarded the same way, one at a time (`buildPage`, `Options.lua:764`).

`O.RenderField` (`OptionsWidgets.lua:1310`) dispatches on `row.type`, and returns nil for a type it does not know rather than erroring:

| row shape | AceGUI primitive | Maker |
|---|---|---|
| `type = "bool"` | `CheckBox` | `makeCheckbox` (`OptionsWidgets.lua:1100`) |
| `type = "number"` **with** `values` | `Dropdown` (a numeric enum) | `makeDropdown` (`OptionsWidgets.lua:1178`) |
| `type = "number"` without | `Slider` (`row.min`/`max`) | `makeSlider` (`OptionsWidgets.lua:1121`) |
| `type = "string"` | `Dropdown`, or `EditBox` with `dialogControl` | `makeDropdown` / `makeEditBox` (`OptionsWidgets.lua:1220`) |
| `type = "color"` | `ColorPicker` | `makeColorPicker` (`OptionsWidgets.lua:1240`) |
| `type = "table"` (this addon's MultiCheck) | `InlineGroup` of `CheckBox`es | **host-drawn** `makeMultiCheck` (`Panel.lua:60`) |

The number split is inferred from `values`, not opted into, so the panel and the CLI read the row the same way — `/lh set` on a numeric enum refuses an off-list value rather than clamping between two labels (`OptionsWidgets.lua:1326`). Only three of the five makers are reachable from this addon's schema today; `string` and `color` rows do not exist here.

**The inverted muted-source picker is declined from the library, deliberately.** `settings.excludedSources` stores a **set of muted sources** but renders `invert = true` as "Record data from", so a *checked* box means "record this source" and the stored value is the logical inverse of the box state — none of the five makers, and a sixth for one host's one shape is not worth the surface. The row therefore carries no rendered widget of the library's; it is drawn by `makeMultiCheck` (`Panel.lua:60`) from the **`afterGroup` hook** (`AFTER_GROUP`, `Panel.lua:817`), which fires once per render after that group's last row is flushed (`OptionsWidgets.lua:219`) — i.e. exactly where the generic path used to put it. `AFTER_GROUP` is hoisted to file scope, which the engine explicitly supports: its one-shot bookkeeping lives in call-local sets (`firedAfter` / `firedPair`), so a second render of the same page fires every entry again instead of silently dropping it.

Each maker pushes a **refresher closure** onto `ctx.refreshers` so the widget can re-sync its display after a Defaults reset or a `/lh set`; `O.ClearScroll` **reassigns** that table (`Options.lua:551`) so a released widget's refresher cannot outlive its widget. Tooltips attach via `O.AttachTooltip` (`OptionsWidgets.lua:612`), which handles both AceGUI widgets (`SetCallback`) and plain frames (`HookScript`).

## The tab strip (options-ui-§13)

The General page is **six tabs**, and it is the whole panel: every page in this addon except the landing page (which options-ui-§13 exempts by name, along with Profiles) draws a strip, and there is only one left to draw one.

| Tab | Body | Rows |
|---|---|---|
| **Master controls** | schema rows + the composer's closing button pair | 6 |
| **Collection** | schema rows + the host-drawn inverted source picker | 4 |
| **Filters** | bespoke: a **secondary strip** over three id-lists | 0 |
| **AH Price** | schema toggle + the pooled price-source reorder table | 2 |
| **Interface** | schema rows | 3 |
| **Maintenance** | schema row + the storage readout and **Purge history…** | 1 |

| | Before R6 | After |
|---|---|---|
| **General** | strip: Collection (5) · Interface (4) · Maintenance (1) | strip: **Master controls** (6) · **Collection** (4) · **Filters** · **AH Price** (2) · **Interface** (3) · **Maintenance** (1) |
| **Filters** | its own sub-page, strip: Blacklist · Whitelist · Currencies | a **tab** on General, with those three as a **secondary** strip inside the scroll |
| **AH Price** | its own sub-page, one group, **no strip** | a **tab** on General |
| **Landing** | logo, tagline, slash rows | unchanged (exempt, options-ui-§13) |

**The strip is drawn by hand, not by `O.RenderTabbedSchema`.** That function derives its tab list from the rows' `group`, which is exactly right for a page whose every section is rows — and cannot name a tab whose body is a dynamic list of item ids. So `GENERAL_TABS` (`settings/Panel.lua`) declares the six in strip order, each entry either a schema **group** (rendered by the same `O.RenderRows(..., { noHeadings = true })` call the library would have made) or a `build` function; `O.TabStrip` draws the strip and `onSelect` re-enters `renderGeneral` through `O.RefreshPanel(ctx, true)`. `tests/test_panel.lua` derives the tab list from **both** sides and compares them, so a group added to the schema and not to `GENERAL_TABS` is a red case rather than a section that renders nowhere.

Six things about the strip are worth writing down because each is a decision that could be re-made wrongly:

* **Master controls is first, under that exact name** (options-ui-§15). It is simultaneously the rows' `group`, the tab's label and the `afterGroup` key its closing button pair hangs off — the group name *is* the hook key, so renaming the group detaches the hook and nothing errors. `settings/Schema.lua` publishes both ends (`S.MASTER_GROUP`, `S.MasterAfterGroup`) rather than spelling the literal twice.
* **`afterGroup` is where a host-drawn block goes, not the renderer's tail.** A block appended after the rows would land at the bottom of *every* tab rather than inside the one it belongs to. Four tabs have one: Master controls (the reset pair, the composer's own), Collection (the muted-source picker), AH Price (the price table) and Maintenance (the storage readout + purge).
* **`pairWith` is gone.** Its one entry attached **Reset Everything** to the right half of the `settings.windowScale` row, and the hook only fires while its path is the lone widget on its line. That button is the Master controls tab's **Reset all settings** now, drawn by the composer's own hook.
* **Subsection headings are not suppressed.** `noHeadings` suppresses the *group* heading, because under a strip the tab is it — but a tab that mixes control types has no tab left to name each kind with (options-ui-§7). Two tabs are mixed and each carries two headings, every one of them declared by a row: **AH Price** (**Pricing** above the toggle, **Price sources** above the table) and **Interface** (**Window** over the two sliders that size the History window, **Minimap** over the button toggle — a different surface, so a second subject under one label). No other tab is a mix: `tests/test_panel.lua` states the expected heading list for all six, empty lists included, so a heading that appears where none belongs is as red as one that vanishes.
* **The wrap is selection-invariant, and this page proves it rather than assuming the library does.** Six labels is wide enough to wrap on a narrowed Settings window, and options-ui-§13 makes the invariant a testing MUST: the reserved band and every tab's y offset are the same numbers for every value of the selection, or the whole page shifts under the player on each click. The geometry is `O.TabStrip`'s, but the strip is this page's, so `tests/test_panel.lua` pins it here — forcing a two-row wrap and comparing the band and all six anchors across all six selections, and separately pinning that the row pitch comes from the **unselected** tab art. The half that makes it mean anything is in `tests/wow_mock.lua`, which answers a **taller** height for the selected-state atlas; §13 says in as many words that a harness answering one height for every atlas "is green against nothing".

* **No banner and no page-header block (options-ui-§14).** This addon is account-wide: every path resolves against `NS.db.global`, there is no AceDB `profile` section, no per-window state, and nothing for a banner to be a picker *for*; and nothing on the page applies to every tab. `H.PageBanner` and `H.PageHeader` are stubbed on the degraded path for surface parity and neither is called on the live one.

## The Master controls tab

The tab every Ka0s addon opens on, in the same order, under the same words (options-ui-§15). It is composed by `O.MasterControls` from one declaration in `settings/Schema.lua`; nothing on it is hand-written.

| | |
|---|---|
| Enable Loot History (`settings.enabled`) | General visibility (`settings.visibility`) |
| Master scale (`settings.scale`) | Master alpha (`settings.alpha`) |
| Lock frame (`settings.locked`) | Debug console (`state.debugConsole`) |
| **Reset position** | **Reset all settings** |

Four of the six rows and one of the two buttons are **new settings**, and each is honoured by drawing code rather than merely declared:

* **General visibility** — `Browser:VisibilityAllows` reads the four modes against `InCombatLockdown()`; `B:Show` refuses (and says why) when the setting forbids the window, `B:Toggle` routes through it, and `B:ApplyVisibility` hides a window the setting has stopped allowing on the two combat transitions, registered on the Browser's own private bus target. It never *opens* the window: "Only in combat" is a permission, not an instruction to pop a 1100px browser over a pull. This addon never shipped a *show only in combat* checkbox, so the key is **new rather than migrated** — the "old" state is its absence, and AceDB merges the shipped `"always"` in.
* **Master scale / Master alpha** — `Browser:ApplyChrome(frame, windowScale)` applies `scale × windowScale` and `alpha` to the History window, and `Export:ApplyChrome` takes the master alone for the export modal (it has no per-window scale). They are **addon-wide**, and `settings.windowScale` is the History window's own and **multiplies on top** — options-ui-§15 is explicit that the two are different settings and must not be conflated, so `windowScale` stayed on the Interface tab rather than being promoted.
* **Lock frame** — gates the two `OnDragStart` handlers (`modules/Browser.lua`'s title bar and `modules/Export.lua`'s), rather than calling `SetMovable(false)`: the setting says "stop the frame being **dragged**", which is a gesture, and un-setting movability would also break `StopMovingOrSizing` on a drag already in flight.
* **Reset position** — a real button over `NS.Browser:ResetWindow()`. It used to be folded into the General page's **Defaults** handler, where a player asking for defaults also got their window recentred and a player who only wanted the recentre had no way to ask.

**Debug console** and **Reset all settings** are **moves, not additions**. The console toggle was the Interface tab's second checkbox; the reset was the Maintenance tab's **Reset Everything** button. Each is now declared in exactly one place, which `tests/test_schema.lua` counts rather than merely finds.

**Reset all settings** is options-ui-§12's global reset verbatim: the same `KA0S_LOOTHISTORY_RESETALL` confirm, the same second canonical wording (the one for an addon with **no** AceDB `profile` section), and the same `Slash:ResetEverything` — wipe `db.global` in place, merge the declared defaults back, drop `savedView` to stock and recentre the window. Only the label and the tab moved.

## The `Schema:Set` write seam

Every setting mutation — panel widget and `/lh set` alike — routes through `NS.Schema:Set(path, value)` (`Schema.lua:223`). The library never learns a path or a database: the descriptor hands it `get` / `set` / `applyDefault` closures over this seam (`OptionsSetup.lua:109`), which is what guarantees a panel click takes exactly the path a slash command does.

1. **validate** — reject unknown paths; run the row's optional `validate`.
2. **write** — `WritePath` into `NS.db.global`, storing a `deepcopy` of the value so a reset can't alias the DB to a shared default table (e.g. the `{}` default of `excludedSources`; `Schema.lua:215`). `sessionOnly` rows skip this and apply through `row.set`.
3. **onChange** — fire the row's hook. Most publish a `Ka0s_LootHistory_SettingsChanged` bus message; `windowScale`/`minimap.hide` reach into the Browser, `retentionDays` triggers `Database:PruneOld`.

`Schema:Get` reads back from `NS.db.global` (`Schema.lua:243`). Because widgets never touch the DB directly, the CLI and the panel can never diverge. (The Browser's window geometry, saved view, the `blacklist`/`whitelist`/`currencyBlacklist` id lists and the auction `priority` cascade are the deliberate carve-outs — they persist straight to `NS.db.global`, not through `Schema:Set`; see [schema.md](schema.md) and [common-tasks.md](common-tasks.md).)

## Combat-gated, lazily rendered body

Rendering is **deferred to a page's first `OnShow`**, and the library owns *when*: `O.SetRenderer` (`Options.lua:671`) installs the `OnShow` script, builds the Defaults button, and renders on first show and again only when a refresh marked the page dirty while it was hidden (`Options.lua:723`). At registration time (`PLAYER_LOGIN`) `ctx.body` has zero width, so a List-layout pass would size every full-width child to zero. **Both** pages go through it now — `renderGeneral` and the landing page's `P.BuildMain` — and each begins with `O.ClearScroll` (`Options.lua:540`), because a renderer the library may re-run must be idempotent. The AH Price page used to be the exception and no longer is; see *The AH Price tab* below for how its pooling survived the change.

Opening the panel is combat-gated in **two** places. `O.OpenOptionsPanel` (`Options.lua:874`) refuses while `InCombatLockdown()` and prints the refusal — `P:Open` is a one-line delegate — and the `SetRenderer` `OnShow` refuses as well (`Options.lua:678`), closing the Settings window so the refusal is legible. That second guard is real coverage: the Blizzard **AddOns-sidebar** path reaches a page without going through `OpenOptionsPanel` at all, which is exactly the route a user takes mid-fight. Neither defers-and-replays: Blizzard's category switch is protected, so calling it under lockdown taints the panel for the session (options-ui-§2), and a panel that opens itself the instant combat drops steals focus during recovery. A **tab click is not guarded** and must not be (options-ui-§13): redrawing widgets inside a panel that is already open was never a protected action. (The standalone browser window is separately non-secure and *not* combat-gated — that is the standalone-windows pattern, distinct from this options-ui-§2 canvas panel.)

## The Maintenance tab's bespoke body

`renderHistory` (`Panel.lua`) draws the rest of the **Maintenance** tab, from `AFTER_GROUP["Maintenance"]` rather than from the page renderer (see the tab-strip section above for why that distinction is load-bearing): a live stats label paired with a **Purge history…** button. It draws **no `O.Section` heading** — the tab is the heading, and a "History" heading inside a tab called Maintenance is the page saying it twice.

* **Stats label** reads from `Database:StorageStats` (`Database.lua:761`) — record count, span in days since the earliest record, and an **estimated** SavedVariables byte size rendered via `Util.FormatBytes` (WoW gives addons no way to read the real on-disk size, hence the `≈` and "(estimated)").
* **Purge history…** (the ellipsis signals a confirm) opens the `KA0S_LOOTHISTORY_PURGE` StaticPopup, which calls `Database:Purge` on accept (popup at `Slash.lua:8`). It is a **purge**, deliberately not folded into *reset settings* — options-ui-§12 keeps the two separate acts separately confirmed.
* **Reset Everything is gone from this tab.** It *was* the global reset, so options-ui-§15 puts it on the Master controls tab as **Reset all settings**, and two buttons over one act is exactly what this pass exists to remove.
* **Live refresh** — the stats re-compute while the panel is open. `renderHistory` registers on a **private `NS.NewBusTarget()`** for `HistoryChanged` / `RecordAdded`, never on the shared `NS.bus` as `self` — CallbackHandler keys callbacks by `(message, target)`, so sharing a target would clobber the Browser/Analytics consumers of the same messages (see [common-tasks.md](common-tasks.md)). The listener is registered **once**, but the label is not: every tab click builds a new one and hands the old back to AceGUI's pool. So the registration closes over **`P.__stats`**, reassigned on every render, rather than over the first render's `refreshStats` — which would have repainted a released widget forever while the live label went stale.

## The Defaults button

One page, so one **Defaults** button, and options-ui-§13 is explicit that its blast radius **must not narrow to the visible tab**. `P:RestoreDefaults` therefore covers what the three pages' three buttons used to, in one act:

* every schema row **plus** the three id-lists — `Slash:CliResetAll`, which wraps the library's row walk because `NS.Filters`' lists are user settings with no schema row;
* the **auction cascade**, a carve-out array the row walk cannot see, cleared and refilled **in place** so the price table's closures keep the same table reference;
* a structural `O.RefreshPanel(ctx, true)`, because the price table and the id-lists repaint off rebuilders rather than off refreshers.

It **does not move the window** any more. That was folded in when there was nowhere else to put it; **Reset position** is its own button on the Master controls tab now, so "Defaults" no longer quietly does a second thing its label never named (options-ui-§12/§15).

(The library's own `O.RestoreDefaults` / `O.RestoreAllDefaults`, `Options.lua:559` / `:595`, are unused here for exactly that reason: this page does not reset a plain page's worth of schema rows and nothing else. See [schema.md](schema.md#reset-semantics) for the full scope matrix.)

## The Filters tab — blacklist / whitelist (issue #14)

Deliberately non-schema: a dynamic list of item ids has no Schema row to express, so `buildFiltersTab` builds custom AceGUI against the library's `EnsureScroll` / `AddSpacer` instead of rendering schema rows. Three id-lists, exactly one on screen at a time, divided by a **secondary tab strip** (`O.SubTabStrip`) drawn inside the scroll as ordinary page content. The tab is called *Filters*, so no sub-tab repeats the word — *Blacklisted currencies* is **Currencies**, because the only currency list there is *is* a blacklist:

* **Blacklist** — ids that are never recorded when looted from now on. Point-in-time: existing rows are left untouched (delete them from the history table if you want them gone).
* **Whitelist** — ids that are always recorded, bypassing the quality / source / quest gates. Also point-in-time: removing an id from the whitelist stops future rescues but does not touch rows already recorded under it.
* **Currencies** — currency ids (Valorstones, crests, Honor, …) that are never recorded, on the same point-in-time terms.

**Why a *secondary* strip and not three more primary tabs.** Three id-lists are a list of like subjects *inside* one category, which is what options-ui-§13 defines a secondary strip for. The primary strip is pinned in the page's chrome band and does not scroll; a secondary strip belongs to the content it divides and scrolls with it, and pinning a second band would double the chrome and push every tab's page down for a division that is not page-wide. The selection is **the host's state**, kept as `ctx.activeSubTab` keyed by the primary tab's key (`"Filters"`) — so leaving the tab and coming back returns to the list you were on — and it is **session state, never persisted**, exactly like `ctx.activeTab`. A pointer naming a list the tab no longer has heals to the first rather than rendering blank. The library's `__subTabKids` ledger is drained by `ClearScroll` **before** it releases the host frame, which is what stops the buttons riding a pooled frame into another render.

Each sub-tab is a description + an **add row** (an `EditBox` accepting a bare id **or** a shift-clicked link, parsed by `NS.Filters:ParseItemID` / `:ParseCurrencyID`, plus an `Add` button) + a **Clear all** button (confirm-gated → `Filters:ClearList`, for emptying one list without a full reset) + a **live list** (`rebuildFilterList`) of the current ids, each a label (`NS.Compat.ItemNameQuality` resolves the name; a background `LoadItem` fills in names not yet cached) with a **Remove** button. Adds/removes go through `NS.Filters` (`modules/Filters.lua`), which mutates copy-on-write and fires `SettingsChanged` + `HistoryChanged`. The tab live-rebuilds its list on a **private `NS.NewBusTarget()`** (`HistoryChanged`), so the History right-click **Blacklist item** action reflects here immediately while the panel is open.

The lists are **core app logic** and act point-in-time, so there is intentionally no user-facing blacklist/whitelist *display* filter in the browser — blacklisting an id only stops future captures, and whitelisting an id only rescues future loots that would otherwise fail the gate; neither list ever hides or restores an already-stored row.

### Structural refresh is gated (options-ui-§11)

There are **two tiers**, and only one of them is the library's. `O.RefreshScalars` (`Options.lua:491`) runs a page's refreshers in place; `O.RefreshAllPanels` (`Options.lua:487`) re-runs its declared renderer, and either way a hidden page is only flagged dirty and redrawn on its next `OnShow`. On top of that this addon keeps its own **rebuilders** list and `runRebuilders` for the id-lists and the price table, because a rebuild there is not a re-render of the whole page.

`rebuildFilterList` is a **structural** rebuild — it `ReleaseChildren()`s the list and recreates a widget per id — so it registers as a rebuilder, not a scalar refresher, and runs only on **first paint**, on an **on-screen edit** (Add / Remove), and on the **next `OnShow` after an off-screen change**. Running it on *every* `OnShow` (as the page originally did) meant an AceGUI teardown+rebuild of every list on every tab click; with a large blacklist that stalled the client for ~1s — **anti-pattern #39**, the same freeze fixed in Ka0s Consumable Master. The gate: the `HistoryChanged` listener repaints immediately while the page `IsShown()`, otherwise sets **`ctx._dirty`** — the library's own flag, the one `O.SetRenderer`'s `OnShow` actually reads; a page-local `ctx.dirty` alongside it is written and never read (LH-A-27).

**`ctx.rebuilders` is reassigned on every render**, beside the library's reassignment of `ctx.refreshers`, so a rebuilder registered once inside a build-only branch would be dropped the first time the reader left its tab and came back. Both the id-list rebuilder and the price-table rebuilder are therefore registered on **every** pass, not only on the pass that built the widgets.

### The AH Price tab — frame-light, pooled slots, dragged

One unified table (`buildAuctionTable`) — one row per known `"provider:key"` source, columns `[handle] [tick] [Addon] [Price Module (+ⓘ)] [On ☑] [Status]`. It replaced the old Data Collection + Priority sections, and the redesign was forced by a **Blizzard-canvas stall**: the old page built ~213 AceGUI frames (11 priority rows × label/`Icon`/checkbox widgets, plus an 11-row capture checklist), and the Settings canvas does a **super-linear pass over a panel's frames on tab-transition**, so *leaving* the AH Price page froze the client ~1.7s (measured; General at 87 frames never tripped it). The fix is structural, not a refresh-gate: every text column is a **FontString** (a region, not a frame), only the checkbox, the ⓘ and the library's drag handle are real frames, and the row slots + their frames are **created once and reused** — `refreshAuctionTable` repaints them in place on every toggle / drag / Defaults, never re-allocating.

The single per-row **Enabled** checkbox writes `settings.auction.capture` (collect **and** rank in one flag — an unticked source is neither collected nor ranked; there is no separate disabled-set). Rows sort into three partitions, natural cascade order preserved within each: **Collecting** (ticked + addon installed) on top, then **Not collecting**, then **Addon not installed**. The Status column is colour-coded in muted green/yellow/red; the ⓘ trails each Price Module label (positioned per-row from its text width); a not-installed source reads unchecked and non-interactive.

**The cascade is dragged, not clicked** (options-ui-§18). The ▲▼ arrows are gone — anti-pattern #75, two clicks per position with no feedback about where an item is going — and `LibKa0s-Widgets-1.0`'s `ReorderList` owns the gesture, the copy that follows the cursor, the insertion line, the index arithmetic, the drag handle and the **bounded box behind every row**. This addon draws none of that and must not: a host-drawn row fill beside the library's is the double chrome the shared widget exists to prevent. Four consequences worth knowing:

* **Each slot is a real `Frame` now**, not a set of regions on one host — the widget anchors its handle to it, fades it to 0.35 while it is carried, and parents the box to it. The pooling is unchanged: the slots are still created once and repainted in place.
* **The handle owns a 30px gutter at the row's far left** and every column offset is measured from beyond it. The width is **read** off `lib.ROW_BOX.HANDLE_W` through `NS.ReorderRowBox()` rather than restated (options-ui-§8); without the library it answers nil and the gutter is zero, because there is no handle to reserve one for.
* **Only the Collecting partition is draggable**, and `boundary = nActive` is what enforces it rather than hope. Every row is still *registered* — an inert one is still a place a drag can land, still counts for the arithmetic, and still gets its box, in the `dimmed` variant.
* **`onMove(from, to)` is a splice to index**, one write and one repaint. `AuctionPrice:MovePriorityWithin(subset, from, to)` re-lays the collecting tags into their **own** slots in the stored cascade, so a four-position drag is one mutation and the sources you are *not* collecting never move. It replaced the pairwise `SwapPriorityTags`, which is gone.
* **`list:Cancel()` runs at the TOP of `renderGeneral`**, before `O.ClearScroll` and before the first widget of the new pass exists. Handles and boxes are pooled, and a controller released *after* the page has started rebuilding is reclaiming chrome from widgets that already belong to something else — options-ui-§18 names this as the single most common way this adoption goes wrong.

**How the pooling survived the merge.** The page kept its own `OnShow` before R6 precisely because `SetRenderer`'s contract is "re-run me and I redraw the page", i.e. a `ClearScroll` that releases every AceGUI child — and eleven pooled slots parented to an AceGUI `SimpleGroup` would have been orphaned onto a frame handed back to the pool. As a tab it has no `OnShow` of its own to keep. So the **host is a raw frame this addon owns for the session** (`ctx._priHost`), created once, parked on the panel and hidden while another tab is on screen, and re-parented to a fresh full-width placeholder each time its own tab is drawn. It is never an AceGUI child, so `ClearScroll` cannot reclaim it; nothing is allocated twice and nothing is released. `tests/test_panel.lua` pins all three halves — the same slot table, the same row frames, and the host hidden the moment another tab is drawn.

## The landing page's command rows

`buildMainContent` (`Panel.lua:747`) draws the logo, the tagline, a "Slash Commands" heading and one label per verb. Those rows now come from `NS.Slash:LandingRows()` (`Slash.lua:294`), i.e. from `LibKa0s-Slash-1.0`'s own `FormatRow` — the same formatter the chat help uses. This page used to carry a private copy of it, and the two had silently drifted: single spaces around the em dash instead of double, no color span wrapping the dash, and a white description instead of a bare one. Deliberate and user-visible; do not "fix" it back ([LIBKA0S-09](https://github.com/tusharsaxena/LootHistory/issues/24)).

## Ka0s options-ui-§6/§8/§10 details this panel implements

**Paired ACTION-button inset (`BUTTON_PAIR_REL = 0.492`).** The one cell-filling action button this file still makes — **Purge history…** — comes from `makePairButton` at the library's relative width `O.BUTTON_PAIR_REL` (`Options.lua:76`, re-exported on the instance at `Options.lua:178`), *not* `0.5`. A button whose fill reaches the cell's right edge has its right border shaved by the `ScrollFrame` clip; the ~0.8% inset clears it (options-ui-§6/§8). Label-inset controls (CheckBox / Dropdown / Slider) stay at `0.5` — their label gutter already reserves the space, so they're immune (options-ui-§10). The maker stays host-side because the library's `O.InlineButtonPair` builds its own Flow row, and this addon's use needs a bare button to drop into a row someone else owns. The Master controls tab's **Reset position** / **Reset all settings** pair *is* `O.InlineButtonPair`, drawn by the composer's own hook and at the same inset.

**Always-shown, inert-when-fits scrollbar (options-ui-§10).** `lib.PatchAlwaysShowScrollbar` (`OptionsScroll.lua:83`) rebinds the AceGUI `ScrollFrame`'s `FixScroll` per instance — applied by `EnsureScroll` to every scroll it creates (`Options.lua:347`) — so the scrollbar is shown **once and stays shown**, reserving the 20px right gutter permanently. Stock `FixScroll` hides the bar and reclaims the gutter when content fits, which would shift the body width between the short landing page and the taller General page. The override keeps the gutter reserved so every page's body shares one right-edge x-coordinate; when content fits it parks the thumb at the top and disables the bar and its step buttons (grayed, `OptionsScroll.lua:113`). Because `scrollBarShown` stays permanently true (`OptionsScroll.lua:135`), the override **also** rebinds `MoveScroll` per instance to no-op when the page fits (`OptionsScroll.lua:171`) — otherwise AceGUI's stock wheel handler (which only gates on `scrollBarShown`) would drift the parked thumb on a short page with nothing to scroll (smoke-test S-4). The original math is otherwise mirrored (note AceGUI's swapped names: `height` = visible frame height, `viewheight` = content height). Everything is undone in `OnRelease` (`OptionsScroll.lua:180`), because AceGUI pools ScrollFrames across every addon in the session and a patch that rode a recycled widget into another addon would be this addon's bug in someone else's panel.
