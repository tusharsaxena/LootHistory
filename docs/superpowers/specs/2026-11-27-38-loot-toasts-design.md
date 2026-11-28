# M3 design: loot toast feeds (#38)

**Date:** 2026-11-27
**Branch:** `feat/2026-11-27-38-loot-toasts` (M3 of the stacked run; base M2, `feat/2026-11-27-rep-appearance-capture`)
**Issue:** [#38](https://github.com/tusharsaxena/LootHistory/issues/38)
**Plan:** `docs/superpowers/plans/2026-11-27-tooltip-toasts-farm.md`, rows M3.1 to M3.7; decisions D6, D7, D9 to D14, D23
**Mockups:** `docs/superpowers/specs/2026-11-27-tooltip-toasts-farm-mockups.html:272-471` (the #38 section, owner-approved v4)
**Builds on:** M1 `docs/superpowers/specs/2026-11-27-34-tooltip-holdings-design.md` (Compat live reads, the holdings
tally, `C.TIP_ICONS`) and M2 `2026-11-27-rep-appearance-capture-design.md` (the `REPUTATION` and `APPEARANCE`
capture paths and `Attribution:Peek`).
**Status:** Architect's design, **aligned at M3.2 to `LibKa0s-Feed-1.0`** (D24; vendored as `v1.119.0
(unreleased, branch feat/2026-11-27-feed)`; contract `LibKa0s/docs/api/Feed/version-1.1.1.1-docs.md`, the
*Feed doc*, which wins over this spec where they differ). No ruling is open. Line anchors are from the tree at
`4e64d17` plus the M1 working tree; re-check every anchor before you edit.

---


> **Owner rulings, 2026-11-27 (supersede the spec text they touch).**
> - **X1 → extend LibKa0s upstream (plan D24).** The feed is NOT built from the addon's own frames and no
>   library-stack-§7 deviation row is written. A new plan task **M3.0** adds a feed capability to LibKa0s in the
>   sibling repo `../LibKa0s` (a Toast minor 5 feed mode, or a new `LibKa0s-Feed-1.0` major, whichever the
>   M3.0 design shows fits the library's conventions) covering the six missing behaviours: newest at the
>   anchor, fade-out, pin in place on hover, an exact countdown bar, merge without replaying the entry, smooth
>   reposition (plus whatever else this spec's engine section needs from a host-agnostic feed: slots, grow,
>   alignment/icon side, style overrides over the owner's skin, enter animations, pulse). It lands on a LibKa0s
>   branch and is vendored here in the **unreleased** provenance form (`v1.118.0 (unreleased, branch <name>)`,
>   CLAUDE.md "Vendored LibKa0s"); the tag is cut only when the owner gives the merge go-ahead. Every
>   addon-specific part (kinds, row content, settings, gain feed) stays in this addon.
> - **M3.2 alignment (2026-11-28).** M3.0 chose the new major `LibKa0s-Feed-1.0`. Sections 2, 7, 8, 10, 13 to 16
>   now build on its API: the library owns containers, slots, grow, alignment/icon side, merge window, stacking,
>   hover pin, timer bar, enter/fade/slide, pulse, smooth reposition, glow, style over the skin, unlock/drag, the
>   strips and the preview; the addon owns the gain feed, kinds, filters, the content builders, settings,
>   sounds, alert hiding, click actions through the Feed's callbacks, and the sim. The seam is
>   `core/FeedSetup.lua`. Section 15.2 lists every place the old text gave way to the Feed contract.
> - **X2 → skip (plan D25).** Hiding Blizzard's **chat lines** is dropped from scope entirely: no message
>   filter, no global-string override, no chat rows. Hiding Blizzard's loot/money **alert toasts** stays
>   (D14), off by default, restored on disable.

## 1. Goal and decisions

Up to three on-screen **toast feeds** show every gain the addon can observe: items, money, currencies,
reputation (gain and loss), appearances (Retail), experience and profession skill-ups. The feeds read gains
**before** the capture filters and the minimum quality. Each feed has its own place on screen, its own kinds and
filters, its own look (the skin unless overridden), its own motion and its own behaviour. Main ships enabled; two
more feeds ship disabled.

| Id | What M3 does with it |
|---|---|
| D6 | One pre-gate **gain feed** (`modules/GainFeed.lua`), the only sender of `NS.MSG.GAIN`. Toasts are on by default (the Main feed is enabled). Toast-only filters: a minimum quality (default Poor) and a hidden-source list (default empty). |
| D7 | Kinds `ITEM`, `GOLD`, `CURRENCY`, `REPUTATION` (gain and loss), `APPEARANCE` (collected only, Retail), `XP`, `SKILL`. No item or money losses, no party loot, no roll rows. |
| D9 | Row content: icon, quality-coloured name, `xN`, bag/bank/warband counts as icons, a source tag, a value line by price mode (None, Vendor, AH, Vendor + AH, Highest; default Vendor + AH), an ilvl badge, an upgrade line, highlights (mount, legendary, upgrade, new appearance) with a glow and an optional LSM sound, and currency cap colouring (70% warn, 90% bad). |
| D10 | A 3x3 slot picker plus an X/Y nudge, Grow up or down, text alignment left (default) or right, icon side left (default) or right. Main defaults to Bottom Right, growing up. |
| D11 | Three fixed feeds: `main` (enabled), `progress` and `extra` (disabled). Each has its own rows for every setting. |
| D12 | Skin by default. Each part has a `FromSkin` companion and an override (background, border, font, sizes, kind colours), plus a per-feed **Reset style to skin** act. |
| D13 | Enter none, fade or slide (4 directions) with an enter time; hold, then fade; a pulse when a count rises; an optional countdown bar; smooth reposition. A repeat inside the merge window (default 3 s) replaces the toast with the summed one at the newest slot. |
| D14 | Shown at once, show in combat (default on), click-through in combat, pin on hover, shift-click link, ctrl-click dressing room, right-click dismiss, plain click opens History searched for the gain. Optional hiding of Blizzard's loot/money alerts and of the matching chat lines, off by default and fully restored on disable. |
| D23 | A **Toasts** settings page of its own, between General and Profiles. Its tab strip holds the sections and its banner picks the feed (section 9.1 explains why the mockup's feed tabs become the banner). No deviation. |

### 1.1 Architect's rulings (within the owner's decisions)

| # | Ruling | Why |
|---|---|---|
| T1 | **The newest toast sits at the anchor** and older ones move away from it in the Grow direction. Bottom Right growing Up puts the newest at the bottom. | `mockups.html:303` ("▲ newest at the bottom · Bottom Right slot"). D13's "summed one at the newest slot" is the same slot. |
| T2 | **The feed host is `LibKa0s-Feed-1.0`** (D24, ruling X1), through the seam `core/FeedSetup.lua` (`NS.NewFeed`, `NS.FeedStub`). Not `LibKa0s-Toast-1.0` v4, and not this addon's own frames. | Toast v4 cannot do T1 (it presents at the tail, `libs/LibKa0s/Toast.lua:436-441`, and the oldest is the head that holds the saved point, `:277-288`). It hides a frame on expiry with no hook, so no fade-out (`:461-485`). It re-anchors every follower on reflow, so no pin (`:285-287`). It has no in-place update, so a merge would replay the enter animation. Its countdown is private (`:155-195`). Its own "not here" table rules out fade and per-toast position (`LibKa0s/docs/api/Toast/version-4-docs.md:227-238`). The owner ruled the upstream extension (D24, superseding D1 for this need), and M3.0 shipped it as a new major. |
| T3 | **The Feed's one clock drives all motion** (enter, hold, fade, pulse, countdown bar, smooth reposition): armed only while a row needs a tick (`Stats().awake`), no AnimationGroups. The host adds no OnUpdate. | Feed doc *Motion: one clock and the phase machine*. A merge restarts the hold without replaying the enter. The idle cost is zero (performance-§2). Headless cases step it through the internal `__Step(dt)` seam after checking it exists. |
| T4 | **Pin on hover freezes the whole feed** (the Feed's `motion.pin = true`; `false` pauses only the hovered row) while the pointer is over any of its rows: no row moves, no row fades, a merge updates its row in place, and new gains wait in the feed's queue. On leave, everything resumes. With Pin off, hovering pauses only that row's fade. | The mockup's "pins the row in place" (`mockups.html:333`) holds only if nothing else moves under the pointer either. RLF's skip-the-pinned-anchor approach lets rows overlap. |
| T5 | **A full feed drops its oldest toast** to make room (the Feed's only overflow policy, its `DROP_FADE`). | A loot feed is about the newest gain. Queueing behind a full stack would show stale loot. |
| T6 | **Highlight glow is the Feed's**: the content sets `spec.highlight = true` and the Feed draws its `ADD`-blend edge in the skin's glow colour (then `sem.gold`), breathing on its clock. No `LibKa0s-Glow-1.0`. | That driver needs `LibCustomGlow-1.0` (`LibKa0s/docs/api/Glow/version-2-docs.md:34-39`, `:151-153`), which `libs/` does not carry. Adoption is optional (library-stack-§7, `standards/library-stack.md:121`), and an edge tint is not the LibCustomGlow mapping that #47 guards. Section 15.2, the glow. |
| T7 | **Default sounds are None** for all four highlights. | The mockup's "Ka0s Chime" and "Blizzard" are examples (`mockups.html` lede: "Names and numbers are examples"). No such sound ships in `libs/LibKa0s/media/sounds/`, which is empty. |
| T8 | *Withdrawn by D25* (chat-line hiding is out of scope). Was: hide a kind's chat lines only while some enabled feed shows that kind. | The mockup's chat-lines row is not built. |
| T9 | **Dedupe across chat and diff uses feed claims** owned by GainFeed, separate from `R.claims`. | A quality-gated item posts no Reconciler claim (`modules/Collector.lua:151-159`). The diff then writes it as a row (M0 spec D2), and that would toast it a second time. |
| T10 | The **attribution consume moves above the record switches** on the currency and money lines, so a gain toasts with its source. It consumes whatever the switches say. | The source must not depend on toast settings (one answer per question). Section 6.2 covers the behaviour change. |
| T11 | Every chat handler gains a **secret guard**: a secret `msg` writes `[Drop] reason=secret` and returns. | Fixes an existing gap (`core/Util.lua:223-228` matches with no guard) that the taps widen. client-quirks-§2. |
| T12 | Plain click: `B:ShowGain(gain)` opens History, selects the History tab and puts the gain's name in Search. It does this whether or not the gain has a row. Its other filters are left alone. XP and skill have no rows, so a plain click on them does nothing. | D14. History has no scroll-to-row API (`modules/BrowserTable.lua:854-869`), and searching by name is the existing pattern (`modules/BrowserViews.lua:295-303`). |
| T13 | **Upgrade rule** (D9): see section 7.4. Armour has to match the class's armour type on Retail, or the equipped piece's subclass on Forever. A weapon has to match the equipped weapon's subclass. A two-slot item compares against the lower equipped ilvl. An empty slot gets no line. | It avoids "a mage sees plate" without a proficiency API. Forever classes change armour type at level 40, so on Forever the equipped piece is the reference. |
| T14 | Forever skill-ups count only the **profession lines** in `C.PROFESSION_SKILL_LINES`, deduplicated on `parentSkillLineID`. | Forever lists weapon skills, which rise all the time, and lists every profession twice (`docs/forever-quirks.md:172-177`). |
| T15 | Feed names are fixed: **Main feed**, **Progress feed** (defaults: reputation, experience and skill-ups at Top Center, growing down) and **Third feed** (all kinds, Top Left). | `mockups.html:359`, `:381`. Fixed keys keep the schema static, so the CLI, the resets and the Defaults all see ordinary rows. |

### 1.2 Scope

- **In:** GainFeed and its taps; the Progress observer (XP, skill-ups); three feeds; row content; style, motion and
  behaviour; the Toasts page; test toasts, test mode and the sim; unlock and drag; Blizzard alert hiding (no chat-line hiding, D25);
  disabled state, perf and taint posture; docs.
- **Out:** farm mode (M4 subscribes to GAIN). Item tooltips on toast hover. Guild bank counts (D9). Party loot and
  rolls (D7). Item and money losses (D7). A slash verb for toasts (every setting is already reachable through
  `/lh set`). Renaming feeds. More than three feeds.

---

## 2. Files

The toasts are drawn by **`LibKa0s-Feed-1.0`** (D24; vendored at `v1.119.0 (unreleased, branch
feat/2026-11-27-feed)`, contract `LibKa0s/docs/api/Feed/version-1.1.1.1-docs.md`, cited below as *Feed doc*). The
library owns the containers, slots, grow, alignment and icon side, the merge window, stacking and the full-feed
drop, hover pin, the countdown bar, enter/hold/fade/slide, the pulse, smooth reposition, the glow, style
application over the owner's skin, unlock and drag, the test/sim strip and the preview. This addon owns the gain
feed, the kinds, the filters, the content builders that turn a gain into the Feed's row spec, the settings, the
sounds, Blizzard alert hiding, the click actions (through the Feed's callbacks) and the sim. Nothing in the first
list is rebuilt here (anti-pattern #47).

### 2.1 New

| File | Responsibility | Est. lines |
|---|---|---|
| `core/CompatGain.lua` | New `NS.Compat` members (section 3). It is its own file because `core/Compat.lua` and its split siblings are near the layout-§1 re-check; this keeps every file under 1500. | 200 |
| `core/FeedSetup.lua` | **The LibKa0s-Feed-1.0 seam** (section 8.1). Resolves `LibStub("LibKa0s-Feed-1.0", true)` silently at load and publishes `NS.FeedLib` (the library table or nil), `NS.NewFeed(d)` (sets `d.owner = addonName`, answers `Feed:New(d)`, or `NS.FeedStub` when the major is absent) and `NS.FeedStub`, the instance stub of the Feed doc's *The degradation stub* table, member for member. | 60 |
| `modules/GainFeed.lua` | `NS.GainFeed`: the only `GAIN` sender, the reused scratch payload, `wants`/`on`, the feed claims, the diff tap helper, and `Recompute` → `SyncCapture` fan-out. | 260 |
| `modules/Progress.lua` | `NS.Progress`: the XP and skill-up observer. Rows registered only while the feed wants `XP`/`SKILL`. | 260 |
| `modules/ToastModel.lua` | `NS.ToastModel`: pure. The host config snapshot (`M.Config`), the three descriptor getters (`M.LayoutFor`, `M.MotionFor`, `M.StyleFor`) that map profile leaves onto the Feed's `layout`, `motion` and `style` keys, the filter (`M.Accepts`), the merge key (`M.Key`), the payload copy and its spare list (`M.NewPayload`, `M.FreePayload`), the merge reducer handed to the Feed as `d.merge` (`M.Merge`), and the appearance absorb (`M.Absorb`). No frames. | 320 |
| `modules/ToastContent.lua` | `NS.ToastContent`: pure. `TC.Content(fid, spec, payload, key)`, behind the Feed's `d.content` callback (one closure per feed), filling the Feed's reused row spec (`icon`, `tint`, `badge`, `title`, `count`, `prefix`, `lines[1..3]`, `sub`, `highlight`) from a payload: the price, cap, counts, progress and upgrade builders and the per-kind lines (section 7.4). Replaces the old `ToastRow.lua`, whose frame work is now the library's. | 380 |
| `modules/ToastFeed.lua` | `NS.Toasts`: builds the three Feed instances through `NS.NewFeed`, the GAIN receiver and its routing, the sounds, the click handler, the combat rows (`Hold`/`Release`, `SetClickThrough`, `SetLocked(true)`), unlock, the test mode, the Test act and the sim strip, and Enable/Disable. | 330 |
| `modules/ToastSample.lua` | `NS.ToastSample`: a fixed sample payload set per kind for test mode, the per-feed Test act and the unlocked view. It never goes through GAIN. | 140 |
| `modules/ToastBlizz.lua` | `NS.ToastBlizz`: alert-event suppression with an exact restore (chat-line hiding is out of scope, D25). | 90 |
| `settings/SchemaToasts.lua` | `NS.SchemaToasts.Rows()`: builds every Toasts row (three feeds times the per-feed set, plus one page-wide row) from one per-feed builder. | 400 |
| `settings/PanelToasts.lua` | The Toasts page: the banner picker plus the *Add feed* action, the tab strip, the General tab's acts, the Hide sources multi-check, Reset style to skin and Reset feed. | 330 |
| `tests/test_gain_feed.lua`, `tests/test_progress.lua`, `tests/test_toast_model.lua`, `tests/test_toast_content.lua`, `tests/test_toast_feed.lua`, `tests/test_toast_blizz.lua`, `tests/test_panel_toasts.lua` | Section 13. | |

### 2.2 Changed

| File | Change |
|---|---|
| `modules/Collector.lua` | Taps on the three chat lines, the secret guard, the currency and money reorder (section 5.2), and `local GainFeed = NS.GainFeed` at load. |
| `modules/Reconciler.lua` | The `writeNet` tap (section 5.3). `GainFeed:HoldClaims` beside `L.HoldClaims` in `R:Flush` (`:809-812`). |
| `modules/Reputation.lua`, `modules/Appearance.lua` (M2) | The taps, and **`SyncCapture`**: rows are registered while the record switch is on **or** `GainFeed.wants[kind]`, and the record switch then gates only `Add` (section 5.4, an amendment to M2 §5). |
| `modules/BrowserViews.lua` | `B:ShowGain(gain)` (T12), beside `B:ShowTimeline` (`:295-303`). |
| `modules/BrowserTable.lua` | `SetTestMode` (`:~420-447`) also calls `NS.Toasts:SetTestMode(on)` after its own switch succeeds. |
| `core/Constants.lua` | `MSG.GAIN`; `C.GainKind`; the `C.TOAST_*` constants (section 4.3); `C.PROFESSION_SKILL_LINES`; `C.CLASS_ARMOR`; `C.BLIZZ_ALERT_EVENTS`. **No `C.LAYERS.STRATA` key**: the addon never sets a strata on a toast frame (the container takes the Feed's `STRATA`, `"HIGH"`, Feed doc *Frame layering*); the header stack comment (frame-layering-§5) gains one pointer line for it. |
| `core/SimSeam.lua` | Classifies the new members (section 3.2). The header's GUARDED paragraph names `ListSkillLines` beside `ListCurrencies`. |
| `core/LifecycleSetup.lua` | Stand-up and stand-down steps (section 10.1). |
| `core/PerfSetup.lua` | Buckets `gainSend`, `toastPaint`, `xpEvent` and `skillScan`, appended last (`:63-69`). |
| `core/SkinSetup.lua` | Owner tokens for the kind colours (section 8.4) in `Skin:RegisterOwner(addonName, { tokens = ... })` (`:802-806`), and the degraded `NS.SKIN_FALLBACK` entries for them. |
| `defaults/Profile.lua` | `settings.toasts` (section 9.2). |
| `settings/Schema.lua` | Appends `NS.SchemaToasts.Rows()` to `S.Schema` before `SchemaLib:New` (`:~870`). The page/group header comment (`:32-37`) now says there are two pages. The Test mode note says "and the toast feeds". |
| `settings/Panel.lua` | Publishes `P._makeMultiCheck`. `P:Register` registers the Toasts page after General and before Profiles (`:789-810`). |
| `modules/SimWorld.lua`, `modules/SimDrivers.lua`, `modules/SimScenario.lua`, `modules/Sim.lua` | Section 12. |
| `LootHistory.toc` | Section 2.3. |
| `.luacheckrc` | `read_globals` gains `UnitXP`, `UnitXPMax`, `UnitLevel`, `IsXPUserDisabled`, `GetMaxPlayerLevel`, `GetProfessions`, `GetProfessionInfo`, `C_SkillInfo`, `C_MountJournal`, `C_TransmogCollection`, `GetDetailedItemLevelInfo`, `HandleModifiedItemClick`, `AlertFrame`, `PlaySoundFile`, as each is first read. |
| `tests/test_libka0s.lua` | **M3.3:** the case *"the nine adopted majors all resolved, and the seams are wired to them"* becomes *"the ten adopted majors ..."*: `LibKa0s-Feed-1.0` joins its major list and it asserts `type(NS.NewFeed) == "function"` and `type(NS.FeedStub) == "table"`; `core/FeedSetup.lua` joins the silent-flag case's path list. The rename regenerates `docs/test-cases.md` in that commit. |
| `tests/test_surface_parity.lua` | **M3.3:** the instance parity pair against a live feed, `T.assertSurfaceParity(liveFeed, NS.FeedStub, "Feed instance")` and the reverse (Feed doc *The degradation stub*). |
| tests, docs | Sections 13 and 14. |

Not changed (the old engine needed them, the Feed does not): `core/WidgetsSetup.lua` (no `NS.MakeDragHandle`; the
Feed docks a Widgets `DragHandle` itself, and its strip through `SetStrip`), `core/PoolSetup.lua` (the Feed pools
its own rows).

`CLAUDE.md`'s `LibKa0s icons:` line gains nothing. The toasts reuse M1's six `gi:` container marks (`C.TIP_ICONS`)
and the declared `chevron-up` (the upgrade arrow); the Feed draws no library icon and the drag handle's `move`
is already declared.

### 2.3 TOC placement

```
core\CompatClient.lua
...
# LOAD-BEARING POSITION: adds members to NS.Compat at file load (the gain feed's client reads, #38).
# Below core\Compat.lua, whose table it extends; ABOVE core\SimSeam.lua, which wraps every member in
# place at its own load, so a member defined below the seam escapes it (H2, NS.SimSeam:Unwrapped()).
core\CompatGain.lua
core\SimSeam.lua
...
core\PoolSetup.lua
# The LibKa0s-Feed seam (#38). CONVENTIONAL: it resolves the major (libs\LibKa0s\LibKa0s.xml, above)
# and publishes NS.NewFeed / NS.FeedStub; nothing calls NS.NewFeed at load (modules\ToastFeed.lua
# builds its feeds from Toasts:Enable). Kept beside the other LibKa0s seams.
core\FeedSetup.lua
core\LootHistory.lua
...
modules\AttributionOut.lua
# LOAD-BEARING POSITION: the gain feed (#38), the one sender of Ka0s_LootHistory_Gain. Collector,
# Reputation, Appearance, Progress and Reconciler bind NS.GainFeed as a file-scope local at load (the
# capture hot path tests one field, events-frames-taint-§7), so it must be above all five; it binds
# NS.Perf (core\PerfSetup.lua) and NS.Ledger (core\Ledger.lua), which are above.
modules\GainFeed.lua
modules\Collector.lua
modules\Reputation.lua
modules\Appearance.lua
# CONVENTIONAL as a load position, kept directly below the M2 observers on purpose: its capture rows
# append to NS.EVENT_ROWS at file load and row order is TOC order, which this keeps equal to the
# stand-up order (core\LifecycleSetup.lua). Binds NS.GainFeed at load (above).
modules\Progress.lua
...
modules\TestData.lua
# CONVENTIONAL: pure toast config, filter and merge (#38); binds NS.Constants at load only.
modules\ToastModel.lua
# CONVENTIONAL: pure row content (#38); binds NS.Constants at load only, every other read at call time.
modules\ToastContent.lua
# LOAD-BEARING POSITION: binds NS.ToastModel, NS.ToastContent and NS.Perf as file-scope locals at
# load and appends its combat rows to NS.EVENT_ROWS at file load; modules\ToastModel.lua and
# modules\ToastContent.lua must be above. NS.NewFeed (core\FeedSetup.lua) is read at call time.
modules\ToastFeed.lua
# CONVENTIONAL: the sample payloads; reached from NS.Toasts at call time only.
modules\ToastSample.lua
# CONVENTIONAL: Blizzard alert hiding; reads NS.GainFeed and NS.Compat at call time only.
modules\ToastBlizz.lua
modules\SimWorld.lua
...
settings\OptionsSetup.lua
# LOAD-BEARING POSITION: settings\Schema.lua appends NS.SchemaToasts.Rows() to its row array at file
# load, before the Schema runtime is built, so this must be above it; it calls NS.Options' composers
# (O.FontGroup / BorderGroup / ColorPair) and reads both defaults tables at load, so
# settings\OptionsSetup.lua and defaults\ must be above.
settings\SchemaToasts.lua
settings\Schema.lua
...
settings\PanelAuction.lua
# LOAD-BEARING POSITION: binds settings\Panel.lua's P._makeMultiCheck as a file-scope local at load;
# settings\Panel.lua must be above. Its builder is registered from P:Register at call time.
settings\PanelToasts.lua
settings\Profiles.lua
```

M2 puts `modules\Reputation.lua` and `modules\Appearance.lua` straight after Collector (M2 §5). M3 inserts GainFeed
above Collector and Progress below Appearance. `tests/run.lua` derives its load order from the TOC
(`Loader.tocFiles`), so it needs no list edit.

---

## 3. Compat additions (`core/CompatGain.lua`)

Every member checks the API is present and never raises when a client or the harness lacks it. Every value read
from the client goes through `Compat.IsSecret` (M1, `core/CompatClient.lua:83`). A secret answers nil, and nothing
secret is stored.

### 3.1 Members

```lua
--- cur, max, level of the player's experience; nil when any read is absent, secret or not a number.
--- `capped` true when IsXPUserDisabled() or level >= GetMaxPlayerLevel() (both clients).
function Compat.PlayerXP()                 --> cur, max, level, capped

--- Retail: the professions GetProfessions() names, read with GetProfessionInfo(i) (no UI state).
--- Fills and answers the module scratch `out` = { [skillLine] = { name, rank, max } }; nil where absent.
function Compat.ProfessionSkills(out)      --> out | nil      (WRAPPED; Retail path)

--- Forever: walks C_SkillInfo.GetNumSkillLines / GetSkillLineInfo(i), expanding a collapsed header with
--- C_SkillInfo.ExpandSkillHeader and collapsing it again afterwards (as ListCurrencies does,
--- core/Compat.lua:1162). Keeps only rows whose skillID or parentSkillLineID is in
--- C.PROFESSION_SKILL_LINES, keyed on parentSkillLineID or skillID, and takes the larger rank of a pair.
function Compat.ListSkillLines(out)        --> out | nil      (GUARDED)

--- quantity, max, earnedTotal, usesEarned for a currency from C_CurrencyInfo.GetCurrencyInfo(id):
--- max = maxQuantity (0 -> nil); usesEarned = useTotalEarnedForMaxQty; earnedTotal = totalEarned.
function Compat.CurrencyCap(id)            --> qty, max, earned, usesEarned

--- itemEquipLoc, classID, subclassID from C_Item.GetItemInfoInstant(link or id); nil when absent.
function Compat.ItemEquipInfo(linkOrID)    --> equipLoc, classID, subclassID

--- The effective item level of a link: C_Item.GetDetailedItemLevelInfo, else the global.
function Compat.ItemLevelOf(link)          --> number | nil

--- The link in an equipment slot: GetInventoryItemLink("player", slot); nil when empty or secret.
function Compat.EquippedLink(slot)         --> link | nil

--- True when C_MountJournal.GetMountFromItem(itemID) answers a mount id (both clients).
function Compat.IsMountItem(itemID)        --> bool

--- Retail only (C.FEATURE.appearances): C_TransmogCollection.PlayerHasTransmogByItemInfo(link) == false
--- for an equippable link; nil on Forever or when unanswerable.
function Compat.IsUncollectedLook(link)    --> bool | nil

--- HandleModifiedItemClick(link): shift inserts the link in chat, ctrl opens the dressing room.
--- Answers whether the client handled it. PURE (UI action, never simulated).
function Compat.ModifiedLinkClick(link)    --> bool

--- C_CurrencyInfo.GetCurrencyLink(id, qty), for the shift-click on a currency toast.
function Compat.CurrencyLink(id)           --> link | nil

--- C_CurrencyInfo.GetCurrencyInfo(id).iconFileID, a plain number, else nil (new: no icon reader exists today).
function Compat.CurrencyIcon(id)           --> fileID | nil

--- LibSharedMedia sound `key` ("" = none) played on the Master channel via PlaySoundFile.
function Compat.PlayMediaSound(key)        --> bool             (PURE)

--- C_Item.GetItemIconByID(itemID), a plain fileID, else nil (the item toast's icon, section 7.4).
function Compat.ItemIcon(itemID)           --> fileID | nil

--- AlertFrame event suppression: for each name in `events`, when AlertFrame:IsEventRegistered(name)
--- answers true, UnregisterEvent it and record it in `into`; Restore re-registers exactly `into`'s
--- names, in the same order, and wipes it.
function Compat.SuppressAlertEvents(events, into) --> n         (PURE)
function Compat.RestoreAlertEvents(into)          --> n         (PURE)
```

Not built (M3.2): `AddChatFilter`/`RemoveChatFilter` (chat-line hiding is out of scope, D25) and `ScreenRect`
(the Feed turns a drag into the nudge itself, `onMoved`).

### 3.2 Sim-seam classification

- **PURE** (`core/SimSeam.lua`): `ModifiedLinkClick`, `PlayMediaSound`, `SuppressAlertEvents`, `RestoreAlertEvents`.
- **GUARDED:** `ListSkillLines`. It expands and collapses skill headers, which is UI state, so during a session it
  answers the world's `skills` and never walks.
- **WRAPPED** (the default): `PlayerXP`, `ProfessionSkills`, `CurrencyCap`, `ItemEquipInfo`, `ItemLevelOf`,
  `EquippedLink`, `IsMountItem`, `IsUncollectedLook`, `CurrencyLink`, `CurrencyIcon`, `ItemIcon`.
- `tests/test_sim_seam.lua` `CLASSIFIED` gains all sixteen. `tests/test_compat_routing.lua` `BANNED` gains bare
  reads in `modules/` of `UnitXP`, `UnitXPMax`, `GetProfessions`, `GetProfessionInfo`, `C_SkillInfo`,
  `GetInventoryItemLink`, `HandleModifiedItemClick`, `PlaySoundFile` and `AlertFrame`, each with `use =` its member.

### 3.3 Verification gates (events-frames-taint-§9)

`AlertFrame` and the alert event names in `C.BLIZZ_ALERT_EVENTS` are not in the kit's lists
(`tests/_kit/client_globals_live.lua`). M3.6
cites each one against a commit-pinned `wow-ui-source` (Retail, and the `forever` branch where one exists) in
`docs/ARCHITECTURE.md` *Taint notes*, before the rows ship. A name that does not resolve is skipped at run time (the
members are presence-gated). `/lh debug probe` lists `AlertFrame`, `GetProfessionInfo`'s seventh
return and the Forever skill-list shape (section 12).

---

## 4. The gain feed (`modules/GainFeed.lua`)

### 4.1 Message

`core/Constants.lua` `MSG` gains:

```lua
  -- Sender: modules/GainFeed.lua `GainFeed:Send`, ONLY. Payload: (gain) -- a reused scratch table, valid
  -- only during the synchronous send; a receiver copies what it keeps. Fired for every gain the addon
  -- observes, BEFORE the capture filters (#38 D6). Receivers: NS.Toasts (#38), NS.Farm (#39).
  GAIN = "Ka0s_LootHistory_Gain",
```

`C.GainKind = { ITEM = "ITEM", GOLD = "GOLD", CURRENCY = "CURRENCY", REPUTATION = "REPUTATION", APPEARANCE =
"APPEARANCE", XP = "XP", SKILL = "SKILL" }`. The first five equal the `C.Kind` strings. `XP` and `SKILL` are **not**
added to `C.Kind`, because they are never record kinds (D8).

### 4.2 Payload (one scratch table, reset per send)

| Field | Kinds | Value |
|---|---|---|
| `kind` | all | a `C.GainKind` |
| `dir` | all | `"IN"`; `"OUT"` only for a reputation loss |
| `id` | all but GOLD, XP | itemID / currencyID / factionID / sourceID (appearance) / skillLine |
| `qty` | all | a positive integer: the count, copper, reputation delta (absolute), XP, or skill rise |
| `link`, `name`, `quality`, `icon` | as available | `icon` is a fileID/path where the source answers one, else nil (the row resolves it at paint) |
| `classID` | ITEM | from `Compat.GetItemInfo` |
| `source`, `sourceDetail`, `confidence` | all | a `C.SourceType`, as captured |
| `origin` | all | `"chat"`, `"diff"` or `"event"` |
| `recorded` | all | true when the capture path wrote a History row for this gain |
| `gated` | all | the drop reason (`"quality"`, `"blacklist"`, `"recordCurrency-off"`, ...) or nil |
| `sim` | all | `NS.Sim:IsActive()` |
| `label`, `rank`, `standing`, `threshold`, `repType`, `accountWide` | REPUTATION | from `Compat.FactionSnapshot` (M2 §3.2) |
| `itemID`, `newLook` | APPEARANCE | the source's item and M2's `newLook` |
| `level`, `levelUp`, `cur`, `max` | XP | after the change |
| `old`, `new`, `max` | SKILL | ranks before and after; the cap |

`GainFeed.FIELDS` is the array of every field name above. `Begin(kind)` sets each one to nil (a loop, with no
allocation), then sets `kind`, `dir = "IN"` and `sim`, and returns the scratch table. `Send(g)` runs the Shape-A
bracket `gainSend` around `NS.bus:SendMessage(NS.MSG.GAIN, g)`.

### 4.3 `wants` and `on`

```lua
GainFeed.wants = { ITEM = false, GOLD = false, CURRENCY = false, REPUTATION = false, APPEARANCE = false,
                   XP = false, SKILL = false }   -- the table identity never changes (load-time upvalue)
GainFeed.on    = false                          -- any wants[k]
GainFeed.toastWants = { ... same keys ... }     -- the feed part alone (ToastBlizz's T8 reads it)
```

`GainFeed:Recompute()`: for each kind, `toastWants[k]` is true when some feed `f` has `f.enabled` and
`f.kinds[k]`. APPEARANCE stays false unless `C.FEATURE.appearances`. Then `wants[k] = toastWants[k] or
self._farm[k]`, and `on` = any `wants`. Then it calls `NS.Reputation:SyncCapture()`,
`NS.Appearance:SyncCapture()`, `NS.Progress:SyncCapture()` and `NS.ToastBlizz:Apply()` (all looked up at call time
and presence-checked). `GainFeed:SetFarm(kindsSet|nil)` is M4's entry: it stores `_farm` (nil means none) and calls
`Recompute`. Its private bus target `__ev` listens to `SETTINGS_CHANGED` for the reasons `toasts`, `profile` and
`enabled`, and calls `Recompute`.

Constants (`core/Constants.lua`):

```lua
C.TOAST_FEEDS        = { "main", "progress", "extra" }
C.TOAST_FEED_LABEL   = { main = "Main feed", progress = "Progress feed", extra = "Third feed" }
C.TOAST_KIND_KEYS    = { item = "ITEM", money = "GOLD", currency = "CURRENCY", reputation = "REPUTATION",
                         appearance = "APPEARANCE", xp = "XP", skill = "SKILL" }  -- settings leaf -> GainKind
C.TOAST_SLOTS        = { "TOPLEFT","TOP","TOPRIGHT","LEFT","CENTER","RIGHT","BOTTOMLEFT","BOTTOM","BOTTOMRIGHT" }
C.TOAST_SLOT_LABEL   = { TOPLEFT = "Top Left", TOP = "Top Center", TOPRIGHT = "Top Right", LEFT = "Mid Left",
                         CENTER = "Mid Center", RIGHT = "Mid Right", BOTTOMLEFT = "Bottom Left",
                         BOTTOM = "Bottom Center", BOTTOMRIGHT = "Bottom Right" }
C.TOAST_SLOT_GROW    = { TOPLEFT = "down", TOP = "down", TOPRIGHT = "down", LEFT = "down", CENTER = "down",
                         RIGHT = "down", BOTTOMLEFT = "up", BOTTOM = "up", BOTTOMRIGHT = "up" }
C.TOAST_NUDGE_MAX    = 600     -- = LibKa0s-Feed-1.0 NUDGE_MAX (pinned by test); the nudge sliders' range
C.TOAST_SHOWN_MAX    = 10      -- = Feed SHOWN_MAX (pinned by test); the "Shown at once" slider's top
C.TOAST_COUNT_SETTLE = 0.5     -- motion.settle: the Feed re-runs content once this long after the paint (client-quirks-§3)
C.TOAST_SOUND_GAP    = 1       -- at most one highlight sound per feed per second
-- No inset, drop-fade, slide, pulse or hold-cap constants: those are the Feed's (SLOT_INSET, DROP_FADE,
-- SLIDE_TIME, PULSE_TIME, MAX_QUEUE; section 15.2).
C.TOAST_PRICE_OPTIONS = { { value = "none", text = "None" }, { value = "vendor", text = "Vendor" },
  { value = "ah", text = "AH" }, { value = "both", text = "Vendor + AH" }, { value = "highest", text = "Highest" } }
C.TOAST_QUALITY_OPTIONS -- built like C.QUALITY_OPTIONS (core/Constants.lua:272-278) over 0..5; text for 0 is
                        -- "Poor (everything)", the rest "<colored quality> and above"
C.TOAST_ENTER_OPTIONS = { none, fade, left "Slide from left", right, up, down }   -- the Feed's motion.enter values
C.TOAST_GROW_OPTIONS / C.TOAST_SIDE_OPTIONS -- { up "Up", down "Down" } / { left "Left", right "Right" }
C.PROFESSION_SKILL_LINES = { [129]=1,[164]=1,[165]=1,[171]=1,[182]=1,[185]=1,[186]=1,[197]=1,[202]=1,
                             [333]=1,[356]=1,[393]=1 }   -- vanilla profession skill lines (Forever, T14)
C.EQUIP_LOC_SLOTS = { INVTYPE_HEAD = {1}, INVTYPE_NECK = {2}, INVTYPE_SHOULDER = {3}, INVTYPE_CLOAK = {15},
  INVTYPE_CHEST = {5}, INVTYPE_ROBE = {5}, INVTYPE_WRIST = {9}, INVTYPE_HAND = {10}, INVTYPE_WAIST = {6},
  INVTYPE_LEGS = {7}, INVTYPE_FEET = {8}, INVTYPE_FINGER = {11, 12}, INVTYPE_TRINKET = {13, 14},
  INVTYPE_WEAPON = {16, 17}, INVTYPE_2HWEAPON = {16}, INVTYPE_WEAPONMAINHAND = {16}, INVTYPE_WEAPONOFFHAND = {17},
  INVTYPE_SHIELD = {17}, INVTYPE_HOLDABLE = {17}, INVTYPE_RANGED = {16, 18}, INVTYPE_RANGEDRIGHT = {16, 18} }
  -- (18 = the Forever ranged slot; Retail answers no item there, so the lower-of-two rule ignores an empty 18 only on Retail)
C.CLASS_ARMOR = { WARRIOR=4, PALADIN=4, DEATHKNIGHT=4, HUNTER=3, SHAMAN=3, EVOKER=3, ROGUE=2, DRUID=2,
                  MONK=2, DEMONHUNTER=2, PRIEST=1, MAGE=1, WARLOCK=1 }   -- Retail armour subclass per class
```

`C.PROFESSION_SKILL_LINES` is a hand list of game ids. It is a small static fixture, not `tools/seeds` data, as
the sim's item fixture is. M3.2's probe confirms it against the Forever skill list (section 12, FOREVER-T3).

### 4.4 Feed claims (T9)

- `GainFeed.claims = {}` uses the `Ledger.PostClaim` shape (`core/Ledger.lua:163-211`).
- **Post.** On a chat gain that wrote **no** row (`recorded` false), while `NS.db.profile.settings.trackLedger` is
  on: `Ledger.PostClaim(self.claims, Ledger.ThingKey(kind, id), qty, nil, GetTime())`. GOLD uses
  `ThingKey("GOLD")`, which is `"g"`. A recorded gain needs no feed claim, because the Reconciler's own claim takes
  its diff before `writeNet` (`modules/Reconciler.lua:427-441`).
- **Consume.** In the diff tap: `rest = Ledger.ConsumeClaim(self.claims, key, dlt, clock)`. Only `rest > 0` is sent.
- **Combat.** `GainFeed:HoldClaims(since, now)` calls `Ledger.HoldClaims(self.claims, since, now)`. `R:Flush`
  calls it on the same line as its own `L.HoldClaims` (`modules/Reconciler.lua:809-812`).
- **Prune.** `Ledger.PruneClaims(self.claims, clock)` runs at the top of the diff tap's first call in each flush
  (`flushBody`, `:720`).
- **The window left open.** A chat line that arrives after a commit that already waited the CLAIM_WAIT hold
  (1.5 s) toasts twice. This is rare, and the Reconciler has the same exposure. It goes under Known limitations.

### 4.5 Lifecycle

- `GainFeed:Enable()` creates `__ev`, then calls `Recompute()`.
- `GainFeed:Disable()` sets every `wants`/`toastWants` to false, `on = false`, `_farm = nil`, wipes `claims`, and
  unregisters `__ev`. It does **not** call `SyncCapture`: the stand-down disables those modules itself.
- `GainFeed:ResetState()` (sim Prepare and stop) wipes `claims`.

---

## 5. Tap points: where each kind enters

Every tap is `if GainFeed.on and GainFeed.wants.K then ... end`, so a feed that is off costs one upvalue read, one
field read and one test. That keeps `tests/perf.lua`'s `_lootLine` baseline (`modules/Collector.lua:207`) where it is.

### 5.1 `CHAT_MSG_LOOT` (`lootLine`, `modules/Collector.lua:161-200`)

The order becomes:

0. **New:** `if NS.Compat.IsSecret(msg) then traceLineDrop("loot", "secret") return end` (T11).
1. ParseRollWon: unchanged, with no gain (D7).
2. ParseSelfLoot, GetItemInfo, `resolveLootSource`: unchanged. `Consume` runs here once, as today.
3. ShouldRecord.
4. **On a refusal:** `traceLootDrop(...)`, then `feedItem(link, qty, itemID, itemName, quality, classID, source,
   sourceDetail, confidence, false, nil, reason)`, then return.
5. **On a pass:** build, `Add`, `claim`, then `feedItem(..., true, record, nil)`.

`feedItem` is a file-local: `Begin("ITEM")`, fill, `Send`, and when `not recorded` post the feed claim (4.4). It
calls neither `GetItemExtras` nor `GatherAll`. The row resolves those lazily (section 7).

### 5.2 `CHAT_MSG_CURRENCY` and `CHAT_MSG_MONEY` (the reorder, T10)

`currencyLine` (`modules/Collector.lua:270-304`) becomes:

```
secret guard -> ParseSelfCurrency -> GetCurrencyInfoFromLink (unresolved: drop) ->
id = Compat.ListedCurrencyID(linkID, name); if not id and trackLedger: drop "unlisted" (as today, no gain, no Consume)
id = id or linkID
source = currencySource(directSource)                 -- MOVED up: consumes even when the switches drop the line
feedCurrency(id, name, qty, source, ...)              -- the tap; recorded/gated fixed after the gates below
if not recordCurrency            -> drop "recordCurrency-off" (feed claim posted)
if currencyBlacklist[id]         -> drop "blacklist"          (feed claim posted)
if excludedSources[source]       -> drop "source"             (feed claim posted)
record, Add, claim
```

The single function `listedCurrency` (`:224-238`) becomes two checks, the listed-id resolution and the blacklist,
with the `[Drop]` lines as before. For the tap to carry `recorded`/`gated`, it runs **after** the decision:
compute `gatedReason` (nil when it records) first, then write or drop, then call `feedCurrency(..., recorded,
record, gatedReason)` once at the end. The order above lists the decisions in sequence.

`moneyLine` (`:316-342`): secret guard → ParseSelfMoney → `Consume` (**moved** above the gold-off gate) → the
decision (`trackLedger and recordGold`) → write and claim, or drop → `feedMoney(copper, source, ...,
recorded, record, gated)`.

**The behaviour change.** With `recordCurrency` off, a currency blacklisted, or `recordGold`/`trackLedger` off, the
loot window's count now goes down for that line. Today it stays at the count the window opened with
(`modules/Attribution.lua:182-191`), so later lines in the same window could read a stale window. The new count
matches the window's real slots. **Characterization tests come first** (section 13.1): they pin today's behaviour,
then the commit flips the two named cases on purpose.

### 5.3 The diff (`writeNet`, `modules/Reconciler.lua:661-669`)

```lua
local function writeNet(self, plan, now, clock)
  local me = NS.Util.PlayerKey()
  for holder, net in pairs(plan.net) do
    for key, dlt in pairs(net) do
      local dir = dlt > 0 and "IN" or "OUT"
      local reason = self:ReasonFor(holder, key, dir, clock)
      if dlt > 0 and holder == me and GainFeed.on and not (self.forceReason or self.drift)
         and not L.HOLDER_MOVE_REASON[reason] then
        GainFeed:FromDiff(key, dlt, reason, clock, linkFor(holder, select(2, L.ParseThingKey(key))))
      end
      self:Write(holder, key, dir, reason, math.abs(dlt), now)
    end
  end
end
```

- `ReasonFor` is called once, as today. Its value is now held in a local.
- `linkFor` is called only for an `i:` key; `FromDiff` gets nil for the others.
- `self.silent` (genesis) returns before `writeNet` (`:673`), so it needs no test here.
- `GainFeed:FromDiff(key, dlt, reason, clock, link)` does the following. It parses the key. It returns unless
  `wants[kind]`. It consumes feed claims (4.4) and returns unless `rest > 0`. Then it fills the payload: ITEM
  (link, `Compat.GetItemInfo`), CURRENCY (`Compat.CurrencyName`, `CurrencyQuality`), or GOLD; `source = reason`,
  `origin = "diff"`. `recorded` is true when `rowAllowed` would pass. It cannot see that local, so it is computed
  the same way through `NS.Reconciler:RowAllowed(kind, id)`, which this task publishes as a method over the local
  (`:542-554`). Then `Send`.
- The diff never runs in combat (`:806-809`), so these gains arrive after the pull (Known limitations).

### 5.4 Reputation and Appearance (M2 modules)

- **Reputation** (`repEvent`, M2 §3.4). The tap goes after step 3 (the delta is known and nonzero) and before
  step 4 (ledger-off) and step 5 (the excludedSources mute). It runs `s, d, c = Peek-based source` (M2 §4), then
  `feedRep(dir, factionID, |d|, name, label, rank, standing, threshold, repType, accountWide, s, d, c)`. After
  that, the record path continues unchanged. `recorded` and `gated` are filled in after the decision, as on the
  currency line: the tap call moves to the end of `repEvent`, with the gate reasons collected in order.
- **Appearance** (`appearanceEvent`, M2 §3.5). The tap goes after step 2 (the duplicate check), **IN only**. It
  computes `newLook` before the ledger and mute gates, then `feedAppearance(sourceID, itemID, link, name,
  quality, newLook, source...)`.
- **SyncCapture (the amendment to M2 §5).** `want = recordReputation or GainFeed.wants.REPUTATION` (Appearance:
  `recordAppearances or GainFeed.wants.APPEARANCE`, and `C.FEATURE.appearances` always). `want and not _captured`
  calls `EnableCapture()`; `not want and _captured` calls `DisableCapture()`. Each module's own `SETTINGS_CHANGED`
  listener calls `SyncCapture()` where M2 called Enable or DisableCapture directly. Inside `repEvent` and
  `appearanceEvent`, the record switch now gates only the `Add` path, with `[Drop] reason=record-off`. With both the
  switch and the feed off, the rows are unregistered (#85 holds).
- The rep baseline is seeded on `EnableCapture`, as M2 does, so a feed turned on mid-session starts with a fresh
  baseline and no phantom gain.

### 5.5 Experience and skill-ups (`modules/Progress.lua`)

```
NS.EventRow("Progress", "bus", "PLAYER_XP_UPDATE", function(_, unit) Progress:OnXP(unit) end, "player")
NS.EventRow("Progress", "bus", "PLAYER_LEVEL_UP",  function()        Progress:OnXP("player") end)
NS.EventRow("Progress", "bus", "SKILL_LINES_CHANGED", function() Progress:RequestScan() end)
NS.EventRow("Progress", "bus", "CHAT_MSG_SKILL",      function() Progress:RequestScan() end)  -- trigger only; payload never read
NS.EventRow("Progress", "bus", "PLAYER_REGEN_ENABLED", function() Progress:OnRegen() end)
```

Registration is split into two owners so each kind registers only while it is wanted: `"ProgressXP"` for the first
two rows, and `"ProgressSkill"` for the next three plus `PLAYER_REGEN_ENABLED`. `SyncCapture()` registers or
unregisters each owner against `GainFeed.wants.XP` and `GainFeed.wants.SKILL`.

**XP algorithm** (`Progress.XPDelta(old, new)`, pure):

```
old = { cur, max, level }, new = { cur, max, level }
nil old or nil new                -> nil, "unseeded"
new.level > old.level             -> (old.max - old.cur) + new.cur   -- one level; more read short (Known limitations)
new.level == old.level            -> new.cur - old.cur
otherwise                         -> nil, "level-down"
delta <= 0                        -> nil, "none"
```

`OnXP("player")` runs in a Shape-A bracket `xpEvent`. It reads `cur, max, level, capped = Compat.PlayerXP()`. A nil
read keeps the last plain baseline, sets `_xpStale = true` and returns; `OnRegen` reseeds. When the delta is
positive and not `capped`, it sends `XP` (qty = delta, `level`, `levelUp = new.level > old.level`, `cur`, `max`)
with the M2 rep source rule: Peek QUEST keeps QUEST with its detail and CERTAIN; in combat it is KILL/INFERRED;
otherwise OTHER/INFERRED. It always reseeds after. The baseline is seeded in `SyncCapture` on enable, and on
`PLAYER_ENTERING_WORLD` through `Progress:Seed()`, which `core/LifecycleSetup.lua`'s `OnEnterWorld` calls.

**Skill scan.** `RequestScan()` is `NS.Coalesce(scan, 0.5)` (`core/Util.lua:332`). `scan()` runs in a bracket
`skillScan`:

- On Retail it calls `Compat.ProfessionSkills(cur)`. On Forever, in combat it sets `_scanOwed = true` and returns
  (the walk is UI state; `OnRegen` runs it), and out of combat it calls `Compat.ListSkillLines(cur)`.
- For each `cur[line]` with `prev[line]` present and `cur.rank > prev.rank`, it sends `SKILL` (id = line, `name`,
  `old = prev.rank`, `new = cur.rank`, `max`, `qty = new - old`, source OTHER/INFERRED).
- It then copies `cur` into `prev`. Both are reused tables, with one entry per profession created once.
- The first scan after enable only seeds `prev`, so the first skill-up is never zero (RLF's bug,
  `Features/Professions/Professions.lua:130-156`).

`ResetState()` wipes the baselines and `_scanOwed`. `Disable()` unregisters both owners and calls `ResetState()`.

---

## 6. Behaviour shared by every observer

- **The bus has one sender.** Only `GainFeed:Send` calls `SendMessage(NS.MSG.GAIN)`. Observers call the GainFeed
  methods, just as `Filters` calls `Database:FireHistoryChanged` (`docs/message-bus.md:79-81`).
- **No allocation on the hot path** (events-frames-taint-§7). The scratch payload is reused. A feed claim is
  allocated only for a gated chat gain with the ledger on. XP and skill use reused tables.
- **The debug log.** One `Gain` line per send behind `NS.State.debug`: `Gain "%s %s x%d src=%s origin=%s rec=%s
  gated=%s"`. `docs/debug.md` gains the `Gain` and `Toast` tags.

---

## 7. The toast model (`modules/ToastModel.lua` and `modules/ToastContent.lua`, pure)

Geometry (slot offsets, the row stack, the nudge from a drag) and the lifecycle phases (enter, hold, fade, drop,
pulse, the bar, the glow's breath) are the Feed's (Feed doc *Placement*, *Motion: one clock and the phase
machine*). The addon keeps only what decides **what** a row says and **which** feed takes a gain.

### 7.1 Config snapshot and the descriptor getters

- `M.Config(fid)` reads `NS.db.profile.settings.toasts.feeds[fid]` into a cached flat table `cfg[fid]` for the
  host's own reads (kinds keyed by `C.GainKind`, `minQuality`, `hideSources` as a set, `price`, `ilvl`, `counts`,
  `source`, `hl`, `colors`, `showInCombat`, `clickThrough`, `enabled`). It is rebuilt on `SETTINGS_CHANGED`
  (`toasts`, `profile`, `enabled`) by `NS.Toasts`, which then calls each feed's `Refresh()`. Draw paths read only
  `cfg`, never the profile.
- The three getters are the Feed descriptor's `layout`, `motion` and `style` fields (Feed doc *The descriptor
  `d`*). Each fills one reused table per feed from the profile and answers it. The Feed reads them only on the
  first build and on `Refresh()`, never per frame.

| Getter | Feed key ← profile leaf (`settings.toasts.feeds[fid].*`) |
|---|---|
| `M.LayoutFor(fid)` | `slot` ← `slot`; `x`, `y` ← `x`, `y`; `grow` ← `grow == "down" and "DOWN" or "UP"`; `shown` ← `shown`; `width`, `rowHeight`, `iconSize`, `padding`, `gap` ← the same leaves; `align` ← `align`; `iconSide` ← `iconSide` |
| `M.MotionFor(fid)` | `enter` ← `enter` (stored in the Feed's own vocabulary, `"none"`, `"fade"`, `"left"`, `"right"`, `"up"`, `"down"`); `enterTime` ← `enterTime`; `hold` ← `hold`; `fadeTime` ← `fade`; `mergeWindow` ← `merge`; `pulse`, `timerBar`, `smooth`, `pin` ← the same leaves; `rightDismiss` ← `true` (D14, not a setting); `settle` ← `C.TOAST_COUNT_SETTLE` |
| `M.StyleFor(fid)` | `bgColorFromSkin`, `bgType`, `bgColor`, `bgColor2`, `bgTexture`; `borderStyleFromSkin`, `borderStyle`, `borderSize`, `borderColorFromSkin`, `borderColor` ← the same leaves; `borderTint` ← `borderByQuality`; `borderClass` ← `useClassColorBorder`; `fontFromSkin`, `font`, `fontSize`, `fontSize2`, `fontFlags`, `fontShadowFromSkin`, `fontShadow`, `fontColorFromSkin`, `fontColor` ← the same leaves; `fontClass` ← `useClassColorFont`; `fontSizeFromSkin` ← `false` (font size stays a stored value, Options' cause L11, so the player's sizes draw). The countdown bar and the glow take no rows: their `*FromSkin` keys are left out, so the Feed's defaults (`true`, the skin) apply |

The exact leaf names of the composed groups are read off the emitted rows at M3.6 (section 9.2); the getter's
right-hand side follows them. `tests/test_toast_model.lua` pins each mapping against a profile fixture.

### 7.2 Filter (`M.Accepts(cfg, g)`)

The gain passes when all of these hold: `cfg.enabled`; `cfg.kinds[g.kind]`; `g.kind ~= "ITEM"` or `(g.quality or
0) >= cfg.minQuality`; `not (g.source and cfg.hideSources[g.source])`; `g.kind ~= "APPEARANCE"` or `g.dir == "IN"`;
and `g.kind ~= "GOLD" and g.kind ~= "ITEM"` or `g.dir == "IN"`, which is D7's no item or money losses (the taps
already send only IN for those).

### 7.3 Keys, payloads, the merge reducer and the absorb

- **Keys** (`M.Key(g)`): ITEM `"i:"..id`; CURRENCY `"c:"..id`; GOLD `"g"`; REPUTATION `"r:"..id..":"..dir`; XP
  `"x"`; SKILL `"s:"..id`; APPEARANCE `"a"`. All appearances share one key, so a burst reads "x3" with the latest
  name. The key is the Feed's `Push(key, payload)` key, so the Feed's merge window (`mergeWindow`) does the
  matching.
- **The payload** (`M.NewPayload(g)`). The GAIN table is a reused scratch, and the Feed stores the payload
  untouched (Feed doc *The payload and the row spec*), so each feed that accepts a gain gets its own copy of the
  fields the content needs (`kind`, `dir`, `id`, `qty`, `link`, `name`, `quality`, `icon`, `classID`, `source`,
  `recorded`, `record`, the per-kind fields of 4.2) plus host state `value`, `newLook` and `highlight`. It takes a
  table from a spare list when one is there. `M.FreePayload(p)` wipes it back onto that list.
- **The merge reducer** (`M.Merge(old, new, key)`, the descriptor's `d.merge`). It sums `qty` (and `value`),
  refreshes the fields that move with each gain (`standing`, `level`, `levelUp`, `cur`, `max`, `new`), keeps the
  original `old` on SKILL, carries `newLook`/`highlight` forward, frees `new` onto the spare list and answers
  `old`. Everything else in a merge (the window, the hold restart with no replayed enter, the pulse, the move to
  the newest slot, staying put under a freeze, the repaint) is the Feed's (Feed doc *Merge in place*).
- **Pool accounting.** A merge allocates nothing once warm (the reducer returns the spare). A new toast keeps its
  payload until the Feed lets the row go, and Feed-1.0 has no close callback (Feed doc *What is not here*, "A
  close-reason callback"), so that payload is never handed back to the spare list: it is collected. That is one
  small table per new toast per feed, never per frame (section 15.2).
- **Push outcomes** (`NS.Toasts`, 8.3): `"new"` → the sound; `"merged"` and `"queued"` → nothing more; `false` →
  `M.FreePayload(payload)` (the Feed kept nothing).
- **Absorbing an appearance into its item** (`M.Absorb(feed, g)`, answers true when it consumed the gain). An
  APPEARANCE gain whose `itemID` matches the payload `feed:Get("i:"..itemID)` answers sets `p.newLook = true` and
  `p.highlight = "appearance"` on it and calls `feed:Repaint("i:"..itemID)`. An ITEM gain that arrives while
  `feed:Get("a")` answers a payload with the same `itemID` and `qty == 1` sets the flag on the new item payload and
  calls `feed:Dismiss("a")`. `Repaint` carries no pulse (Feed doc: `Update` and `Repaint` are "no hold restart, no
  pulse, no move"), so an absorb shows as the glow and the extra line, not a pulse (section 15.2).

### 7.4 Content builders (`NS.ToastContent`, `TC.Content(fid, spec, payload, key)`)

`TC.Content` sits behind the descriptor's `d.content`. The Feed wipes the spec (and its three `lines` tables) before each
call and runs it under `pcall` on present, merge, `Update`, `Repaint`, `RepaintAll`, a skin switch and the settle
re-read (Feed doc). It answers nothing (draw) or `false` (skip). `fid` comes from the per-feed closure that is the
descriptor's `content` (8.2), and it reads `cfg = M.Config(fid)`. Spec fields:

| Spec field | Rule |
|---|---|
| `icon` | ITEM: `payload.icon`, else `Compat.ItemIcon(id)` (WRAPPED, 3.1), else the `?` icon. CURRENCY: `Compat.CurrencyIcon(id)`. GOLD: `Interface\\Icons\\INV_Misc_Coin_01` (game art). REPUTATION, XP, SKILL, APPEARANCE: `C.TOAST_KIND_ICON[kind]` (game art) |
| `tint` | the quality colour (meaning, skinning-§6) for ITEM, CURRENCY, APPEARANCE; nil otherwise. The Feed draws it on the icon edge, and on the row border when `style.borderTint` (`borderByQuality`) is on |
| `badge` | `cfg.ilvl` and ITEM weapons/armour: the 1st return of `Compat.GetItemExtras(link)` |
| `title`, `titleColor` | ITEM, CURRENCY, APPEARANCE: `name` in the quality colour. REPUTATION: `name` in kind colour `rep`. XP: `"+%s XP"` in kind colour `xp`. SKILL: `name` in kind colour `skill`, then the new rank, then `"+N"` in `sem.good` (inline colour codes). GOLD: `Util.FormatMoney(qty)` (coloured coins). A kind colour is `S.Color(C.TOAST_TOKENS[<kind>])` (`lh.toast.<kind>`) while `cfg.colors.<kind>FromSkin`, else the stored swatch |
| `count` | `"x"..qty` for ITEM and CURRENCY; nil otherwise. `countColor` is left nil, so the Feed draws the count in the glow colour while the row pulses |
| `prefix`, `prefixColor` | REPUTATION `"‹"..label.."›"`, XP `"‹"..level.."›"`; colour nil (the Feed's label colour) |
| `lines[1]` | left: the counts (`cfg.counts`) or the cap or the progress (below); right: the source tag (`cfg.source`, `C.SourceLabel[source]`) for ITEM, CURRENCY, GOLD, APPEARANCE and REPUTATION |
| `lines[2]` | ITEM: the value line by `cfg.price`: `both` → left `"Vendor "..fmt(vendor)`, right `"AH "..fmt(ah)`; `vendor`/`ah`/`highest` → left only; `none` → nothing |
| `lines[3]` | ITEM with `cfg.hl.upgrade` and an `M.Upgrade` answer: left `NS.IconMarkup(chevron-up)` in `sem.good` plus `"+"..diff.." over equipped"` |
| `sub` | APPEARANCE, and an item with `newLook`: `"Appearance collected"` |
| `highlight` | `true` when the first that applies of `mount` (`Compat.IsMountItem`), `legendary` (quality 5), `upgrade`, `appearance` (`newLook`, or `Compat.IsUncollectedLook(link)` on Retail) has its `cfg.hl.*` switch on; the Feed draws the glow. The highlight name is stored on the payload (`p.highlight`) for the sound |

The builders behind the lines are unchanged from the M3 design:

- **counts** (`cfg.counts`). ITEM: M1's `NS.HoldingsTally:Item(itemID)`, the logged-in holder's `bags`, `bank` and
  (Retail) warband `tabs`, while `trackLedger` is on; else `Compat.LiveItemCounts(itemID)` (M1 §4.3). Each nonzero
  part is `NS.IconMarkup(C.TIP_ICONS[container], nil, iconPx)` plus a count. GOLD: `Compat.GetMoney()` with the
  bags mark, plus the warband's stored money (`NS.Holdings:Get("§warband").money`, Retail with ledger on) with the
  tabs mark. These are re-read by the Feed's settle call (`motion.settle`, client-quirks-§3).
- **cap** (CURRENCY). `q, max, earned, uses = Compat.CurrencyCap(id)`. With `max`, the text is
  `FormatCount(uses and earned or q).." / "..FormatCount(max)` and `r = (uses and earned or q)/max`; colour
  `sem.bad` when `r >= 0.9`, `sem.warn` when `r >= 0.7`, else nil. Without `max`, `FormatCount(q)`.
- **progress**. REPUTATION: `FormatCount(standing).." / "..FormatCount(threshold)` when both are numbers (M2's
  `FactionSnapshot` shape). XP: `("%.1f%% of level"):format(cur/max*100)`; on `levelUp` the text is
  `"Level "..level`.
- **value** (ITEM). `vendor = sellPrice * qty` (`Compat.GetItemExtras(link)`'s 3rd return). `ah =
  Pick(GatherAll(link, itemID)) * qty`, from `record.auctionPrice` when the gain was recorded, gathered lazily
  otherwise, and only when the mode needs AH. The result is cached on the payload (`p.value`, `p.vendor`, `p.ah`)
  so a repaint or the settle call does not gather again; the merge reducer sums them. A zero or missing part is
  left out.

`TC.Upgrade(equipLoc, classID, subclassID, ilvl, quality, classFile, equippedFn)` answers `diff` or nil:

- The item must be equippable gear: `equipLoc ~= ""` and in `C.EQUIP_LOC_SLOTS`.
- For each slot, `link = equippedFn(slot)`. Any empty slot gives nil (no line). Equipped ilvl is
  `Compat.ItemLevelOf(link)`, and a two-slot item takes the **lower** of the two.
- Armour (`classID == 4`, subclass 1 to 4) must have a subclass equal to `C.CLASS_ARMOR[classFile]` on Retail, and
  to the equipped piece's subclass on Forever. A weapon (`classID == 2`) must have a subclass equal to the equipped
  piece's.
- Following RLF (`Features/ItemLoot/ItemLoot.lua:266-279`), a Poor item over a better equipped piece, or a Common
  item over one above Common, gives nil.
- `diff = ilvl - equippedIlvl`. It answers `diff` when `diff > 0`, else nil.

### 7.5 What the library owns instead

| Old spec part | Now | Feed member or key |
|---|---|---|
| `M.SlotOffset`, `C.TOAST_SLOT_INSET` | the Feed's placement (inset `SLOT_INSET`, 20) | `layout.slot`, `layout.x/y` |
| `M.Layout` (row stack, mixed heights) | the Feed's stack (a row grows by `fontSize2 + 2` per filled line) | `layout.*`, the spec's `lines`/`sub` |
| `M.NudgeFromRect`, `Compat.ScreenRect` | the Feed's drag stop | `onMoved(x, y)` |
| `M.Advance`, the ticker (T3) | the Feed's one clock | `motion.*`, `Stats().awake` |
| entry pool, `feed.live`, `feed.waiting` | the Feed's entries and waiting list | `Push`, `Get`, `Hold`/`Release`, `maxQueue` |
| merge window, move to newest, freeze | the Feed | `motion.mergeWindow`, `motion.pin`, `d.merge` |
| full feed drops oldest (T5) | the Feed (no overflow option) | `layout.shown` |

---

## 8. Feeds on LibKa0s-Feed-1.0

### 8.1 The seam (`core/FeedSetup.lua`)

```lua
local addonName, NS = ...
local Feed = LibStub and LibStub("LibKa0s-Feed-1.0", true)   -- silent: a missing major degrades
NS.FeedLib = Feed                                            -- the constants (SLOTS, NUDGE_MAX, SHOWN_MAX), or nil
NS.FeedStub = { ... }   -- the Feed doc's *The degradation stub* table, member for member
function NS.NewFeed(d)
  if not Feed then return NS.FeedStub end
  d.owner = addonName   -- rows, handle and strips follow this addon's skin owner
  return Feed:New(d)
end
```

- Every stub member answers what an empty, locked feed answers (`Push` → `false`, `Get` → nil, `Update`,
  `Repaint`, `Dismiss` → `false`, `Preview` → `0`, `SetLocked`/`IsLocked` → `true`, `Visible` → `{}`, `Stats` →
  the all-zero table with `locked = true`, `Frame` → nil, the rest nothing). One stub serves all three feeds; it is
  stateless.
- Parity: `tests/test_surface_parity.lua` builds a live feed (`NS.FeedLib:New{ content = function() end }`) and runs
  `T.assertSurfaceParity(liveFeed, NS.FeedStub, "Feed instance")` and the reverse. `__Step` is outside the parity
  surface.
- The schema reads no Feed constant at load (it loads before any feed exists and must load without the major):
  `C.TOAST_SLOTS`, `C.TOAST_NUDGE_MAX = 600` and `C.TOAST_SHOWN_MAX = 10` are constants, and
  `tests/test_toast_model.lua` pins each equal to `NS.FeedLib.SLOTS`, `NUDGE_MAX` and `SHOWN_MAX`.

### 8.2 The three feeds (`modules/ToastFeed.lua`)

`Toasts:Enable()` builds each feed once (later Enables reuse the instance; `Clear()` made it reusable):

```lua
feeds[fid] = NS.NewFeed({
  name    = "LootHistoryToastFeed_" .. fid,
  content = function(spec, p, key) return TC.Content(fid, spec, p, key) end,   -- inside the toastPaint bracket
  merge   = M.Merge,
  layout  = function() return M.LayoutFor(fid) end,
  motion  = function() return M.MotionFor(fid) end,
  style   = function() return M.StyleFor(fid) end,
  onClick = function(p, button, key) Toasts:_Click(fid, p, button, key) end,
  onMoved = function(x, y) Toasts:_Moved(fid, x, y) end,
  strings = { HANDLE = L[C.TOAST_FEED_LABEL[fid]], HANDLE_TIP = L["Drag to move this feed. Lock it again on the Toasts page."] },
  debug   = function(tag, fmt, ...) NS.Debug(tag, fmt, ...) end,
})
```

- The closures are made once per feed at its first Enable, not per gain.
- Nothing is built until the first `Push`, `Preview` or `SetLocked(false)` (Feed doc *The constructor*), so a
  disabled feed costs one table.
- The container's strata is the Feed's `STRATA` (`"HIGH"`, frame-layering-§1 T5), its levels and its rows' bands
  are the Feed's (Feed doc *Frame layering*). The addon calls no `SetFrameStrata`/`SetFrameLevel` on a toast frame;
  `grep -rn 'SetFrameStrata("' modules` still finds nothing.
- A skin switch needs no host wiring: the Feed subscribes `OnLooksChanged` on the owner's facade and runs
  `RepaintAll` itself.
- `onEnter`/`onLeave` are not passed (item tooltips on hover are out of scope, 1.2).

### 8.3 The receiver

`Toasts:OnGain(g)` is the GAIN handler on its private target `__gain`. For each feed `f` in `C.TOAST_FEEDS` with
`M.Accepts(cfg[f], g)`, in order:

1. `M.Absorb(feeds[f], g)` → next feed.
2. `p = M.NewPayload(g)`; `res = feeds[f]:Push(M.Key(g), p)`.
3. `res == "new"` and `p.highlight` and `cfg.hl[p.highlight .. "Sound"] ~= ""` and the feed's last sound was more
   than `C.TOAST_SOUND_GAP` ago → `Compat.PlayMediaSound(key)` (the Feed doc: "The host plays its own sound on
   `"new"`").
4. `res == false` → `M.FreePayload(p)`.

Everything else (the merge, the queue while frozen or held, the drain of the newest `shown` in arrival order, the
drop of the oldest past `shown`) is `Push`'s contract.

### 8.4 Kind colours (owner tokens)

`core/SkinSetup.lua` registers owner tokens on `Skin:RegisterOwner(addonName, { ..., tokens = TOAST_TOKENS })`.
The names follow the owner-token rule in `LibKa0s/docs/api/Skin/` (`SkinOwnerTokens.lua` minor 1): they carry
this owner's namespace, `lh.`, never a library token family (M3.5; the names live in `C.TOAST_TOKENS`).

| Token | Default (Ka0s Default) | Role |
|---|---|---|
| `lh.toast.xp` | the mockup's `#e58cff` as `{0.898, 0.549, 1, 1}`, no `follow` | XP title |
| `lh.toast.rep` | `sem.info`'s value `{0.3, 0.8, 1, 1}`, `follow = "sem.info"` | reputation name (M2 ruling A9's colour) |
| `lh.toast.skill` | `#7aa7ff` as `{0.478, 0.655, 1, 1}`, no `follow` | skill name |

Each feed's `colors.xp`, `colors.rep` and `colors.skill` rows (section 9) carry `<key>FromSkin` companions, true by
default, that read these tokens; `ToastContent` resolves them into the spec's `titleColor` (the Feed takes the
spec's colour first, meaning first). The literal defaults sit in `core/SkinSetup.lua` as the owner's token
defaults, the named skinning-§1 home for an owner colour. The swatch defaults in `defaults/Profile.lua` (the kind
swatches and the Feed style swatches `bgColor`, `bgColor2`, `borderColor`, `fontColor`) need no `Kit.skinValues.rows`
entry: the kit's scanner leaves `defaults/` out by path (its `defaults swatch` rule, the companion-off look) and
`core/SkinSetup.lua` out as the seam, so a `TOAST-STYLE` row would match nothing and fail as stale (M3.5).

### 8.5 Clicks and combat

- **`Toasts:_Click(fid, p, button, key)`** (the Feed's `onClick`; the Feed has already handled a right-click
  dismiss, `motion.rightDismiss = true`, and swallowed the left button while unlocked):
  - left with a modifier down (`Compat.ModifierDown("shift")` or `"ctrl"`, M1) → `Compat.ModifiedLinkClick(p.link
    or (p.kind == "CURRENCY" and Compat.CurrencyLink(p.id)))`. Shift links in chat, ctrl opens the dressing room;
  - plain left → `NS.Browser:ShowGain(p)` (T12);
  - any other button → nothing.
- **Combat rows** `"Toasts"` (registered while any feed is enabled, `Toasts:SyncRows()`):
  - `PLAYER_REGEN_DISABLED` → for each built feed: `SetLocked(true)` (the Feed refuses a new unlock in combat by
    itself; the host owns the re-lock, Feed doc *Input*), and `NS.State.toastUnlocked[fid] = nil`; when
    `cfg.clickThrough`, `SetClickThrough(true)`; when `not cfg.showInCombat`, `Hold()`.
  - `PLAYER_REGEN_ENABLED` → `SetClickThrough(false)` and `Release()` on each.
- **`B:ShowGain(p)`** (`modules/BrowserViews.lua`). It returns when `p.kind == "XP" or p.kind == "SKILL"`.
  Otherwise it runs `self:Show()`, `self:SelectTab("History")`, and if `B:ActiveTab() == "History"`,
  `self:SetSearchText(p.kind == "GOLD" and "Gold" or p.name)`. Show already refuses while stood down or hidden by
  the visibility setting (`modules/Browser.lua:837-861`).

### 8.6 Unlock and drag

- Unlock is session state, `NS.State.toastUnlocked[fid]`, never stored. The General tab's *Unlock* act calls
  `Toasts:SetUnlocked(fid, on)`: `locked = feeds[fid]:SetLocked(not on)`, and `toastUnlocked[fid] = not locked`. A
  refused unlock (combat, or no Widgets) answers locked; the act prints `L["The feed cannot be unlocked now."]`.
- While unlocked and empty (`Stats().live == 0`), `Preview(ToastSample.ForFeed(fid))` shows the sticky sample set
  (preview-mode, *SHOULD trigger the preview while unlocked*); re-locking calls `ClearPreview()`.
- The Feed docks the `DragHandle` with `d.strings.HANDLE` on the stack's far edge, turns the drag stop into the
  clamped nudge for the current slot and re-anchors. `Toasts:_Moved(fid, x, y)` writes it through
  `NS.Schema:SetMany({ { P.."x", x }, { P.."y", y } })`; the resulting `SETTINGS_CHANGED` runs `Refresh()`, which
  re-reads the same values.
- A degraded install (no Widgets, or no Feed) has no drag. The nudge rows still move the feed.

### 8.7 Test mode, the Test act, the sim marker

- **Test mode** (`state.testMode`). `BrowserTable:SetTestMode(on)` calls `NS.Toasts:SetTestMode(on)`. On: each
  enabled feed runs `Preview(ToastSample.ForFeed(fid))` (one sample per enabled kind, sticky, the same present and
  paint path, preview-mode's same-render-path rule) and `SetStrip("test", NS.L["Test mode"])`. Off, or combat start
  (the existing end of test mode): `ClearPreview()` and `SetStrip(nil)`. Live gains still push during test mode;
  preview rows take no merge and no `Get`.
- **The Test act** (per feed, General tab). It pushes each `ToastSample.ForFeed(fid)` payload with a nil key
  (`Push(nil, p)`, never merging, the normal lifecycle, not sticky), as a one-shot preview, and it works while the
  feed is disabled. It is refused in combat by the host.
- **Sim.** While `NS.Sim:IsActive()`, every enabled feed carries `SetStrip("sim", NS.L["Sim mode"])`; the sim strip
  wins over the test strip while both apply (one strip per feed). `NS.Sim:AddListener` (`modules/SimPanel.lua`
  precedent) sets and clears it. Simulated gains arrive through GAIN like real ones (section 12), so the toasts are
  the real render path.
- Samples never go through GAIN, so M4's farm tally never counts them.

---

## 9. Settings

### 9.1 The page (D23, options-ui-§13/§14)

The mockup draws "Main feed | Progress | + Add feed" as tabs (`mockups.html:359`). Under options-ui-§13 a tab is a
section, and options-ui-§14 says a page that edits **one instance out of many** MUST carry the picker in its band
("the banner carries the picker", "the banner is the ONLY picker"). So the feed choice is the **banner** and the
strip holds the sections. This is CombatTrail's Lanes page shape (`../CombatTrail/settings/Lanes.lua:1-33`,
`:592-621`): one row per feed and setting, each stamped `feed = fid`, filtered by the banner's session-state pick.
This is how D23 is honoured with no deviation.

- **Banner.** `O.PageBanner(ctx, { label = "Feed", list = C.TOAST_FEED_LABEL, order = C.TOAST_FEEDS, value =
  selected, tooltip = "The feed every tab below edits.", onSelect = Select, action = { text = "Add feed",
  tooltip = "Turn on the next feed that is off, and edit it.", onClick = AddFeed } })`. `selected` is session state
  (default `"main"`). Picking a feed keeps the tab (§14). `AddFeed` sets the first disabled feed's `enabled` to
  true through `NS.Schema:Set` and selects it. When none is left, it prints "All three feeds are on." and changes
  nothing.
- **Tabs (five):** `General`, `Content`, `Style`, `Motion`, `Behavior`. That is within the eight-tab budget.
  General is first and carries the acts (§14's General escape).
- **General tab acts** (host-drawn after its rows, `O.InlineButtonPair`): **Test** / **Unlock** (Unlock's text is
  *Lock* while unlocked), then **Reset feed…** (a confirm; every row of this feed back to its default via
  `NS.Schema:ApplyDefault` per row, inside one `bulkBegin`/`bulkEnd`) / nothing.
- **Style tab act:** **Reset style to skin** (D12). It sets every `FromSkin` companion of the selected feed to
  `true` in one `SetMany` (the list `NS.SchemaToasts.STYLE_COMPANIONS`, read off the emitted rows' paths), and
  leaves the stored picks in place.
- **Hide sources** (`hideSources`) is a `MultiCheck` row drawn by `P._makeMultiCheck` from the Content tab's
  `afterSubgroup` hook, the same inverted-set picker as `settings.excludedSources`
  (`settings/Panel.lua:~600`). It falls under the existing `options-ui-§1` register row
  (`docs/ARCHITECTURE.md:682`), whose text gains "and each toast feed's Hide sources".
- **Defaults** (the page button) restores every Toasts row of all three feeds plus the page-wide row. Tooltip:
  "Restore every setting of all three toast feeds, and the Blizzard alert option, to their defaults. Other
  pages are not changed. Key bindings are not changed." General's global reset still resets them as part of the
  profile.
- The page is registered from `P:Register` between General and Profiles: `O.RegisterOptionsPage("Toasts",
  "Toasts", NS.ToastsPage.Build)`.

### 9.2 Defaults (`defaults/Profile.lua`)

```lua
-- The loot toast feeds (#38). New keys: AceDB merges them into every profile, no migration owed.
local function feed(over)
  local f = {
    enabled = false, slot = "BOTTOMRIGHT", x = 0, y = 0, grow = "up", align = "left", iconSide = "left",
    kinds = { item = true, money = true, currency = true, reputation = true, appearance = true, xp = true, skill = true },
    price = "both", ilvl = true, counts = true, source = true, minQuality = 0, hideSources = {},
    hl = { mount = true, mountSound = "", legendary = true, legendarySound = "",
           upgrade = true, upgradeSound = "", appearance = true, appearanceSound = "" },
    bgColorFromSkin = true, bgType = "solid",
    bgColor = { r = 0.07, g = 0.08, b = 0.1, a = 0.92 }, bgColor2 = { r = 0.12, g = 0.13, b = 0.16, a = 0.92 },
    bgTexture = "Solid",
    borderStyle = "None", borderSize = 1, borderColor = { r = 0.23, g = 0.24, b = 0.28, a = 1 },
    useClassColorBorder = false, borderStyleFromSkin = true, borderColorFromSkin = true, borderByQuality = false,
    font = "", fontSize = 13, fontSize2 = 11, fontColor = { r = 0.9, g = 0.89, b = 0.84, a = 1 },
    useClassColorFont = false, fontFlags = "@skin", fontShadow = true,
    fontFromSkin = true, fontColorFromSkin = true, fontShadowFromSkin = true,
    width = 320, rowHeight = 48, iconSize = 36, padding = 6, gap = 5,
    colors = { xp = { r = 0.898, g = 0.549, b = 1, a = 1 }, xpFromSkin = true,
               rep = { r = 0.31, g = 0.55, b = 1, a = 1 }, repFromSkin = true,
               skill = { r = 0.478, g = 0.655, b = 1, a = 1 }, skillFromSkin = true },
    enter = "right", enterTime = 0.3, hold = 5, fade = 1, pulse = true, timerBar = false, smooth = true,
    shown = 5, merge = 3, showInCombat = true, clickThrough = false, pin = true,
  }
  for k, v in pairs(over) do f[k] = v end
  return f
end
-- in settings:
toasts = {
  hideAlerts = false,
  feeds = {
    main     = feed{ enabled = true, slot = "BOTTOMRIGHT", x = -220, y = 180, grow = "up" },
    progress = feed{ slot = "TOP", x = 0, y = -160, grow = "down",
                     kinds = { item = false, money = false, currency = false, reputation = true,
                               appearance = false, xp = true, skill = true } },
    extra    = feed{ slot = "TOPLEFT", x = 0, y = -120, grow = "down" },
  },
},
```

The Main nudge (-220, +180) is the mockup's example for its Bottom Right slot (`mockups.html:345`). It clears the
default bag and micro bars. The leaf names of the composed groups (`bgColor`, `useClassColorBg`, `bgColorFromSkin`,
`border*`, `font*`) must match what `O.ColorPair`/`O.BorderGroup`/`O.FontGroup` emit. Read them off the emitted
rows at M3.6, and `tests/test_panel_toasts.lua` pins that each emitted path has a default
(`LibKa0s/docs/api/Options/...-docs.md:48`). `borderStyle = "None"` together with `borderStyleFromSkin = true` means
"the skin's border". With the companion off it means none (skinning-§6, a default that means "no border" says
`None`).

### 9.3 Rows (`settings/SchemaToasts.lua`)

`feedRows(fid)` emits the rows below with `path = "settings.toasts.feeds."..fid.."."..leaf`, `page = "Toasts"`,
`feed = fid`, `default = PD.settings.toasts.feeds[fid].<leaf>`, `onChange = function() NS.bus:SendMessage(
NS.MSG.SETTINGS_CHANGED, "toasts") end` (stamped onto the composer rows too). `shownWhen` (options-ui-§22) is noted
where a row only applies to one choice. Rows are declared in this order, and the order is the layout. All labels
are sentence case (options-ui-§21).

**Group `General`**

| Leaf | Type / widget | Label | Tooltip (abridged) |
|---|---|---|---|
| `enabled` | bool | Enable this feed | "Show this feed. Off, it draws nothing, and gains it would show are not watched for it." |
| subgroup **Placement** | | | |
| `slot` | string / Dropdown `C.TOAST_SLOT_LABEL` in `C.TOAST_SLOTS` order, solo | Screen slot | "One of nine places on screen; the nudge moves it from there. Picking a slot sets its growth direction and clears the nudge." `onChange` also `SetMany` `grow = C.TOAST_SLOT_GROW[v]`, `x = 0`, `y = 0` |
| `x` / `y` | number, slider ±`C.TOAST_NUDGE_MAX` (600) step 1 | Nudge X / Nudge Y | "Pixels from the slot. Dragging the unlocked feed writes this." |
| `grow` | string / Dropdown `C.TOAST_GROW_OPTIONS` | Grow | "Which way older toasts move as new ones arrive. The newest is always nearest the slot." |
| `align` | string / Dropdown `C.TOAST_SIDE_OPTIONS` | Text alignment | "Left is the default. Right flips each line." |
| `iconSide` | string / Dropdown `C.TOAST_SIDE_OPTIONS` | Icon side | "Left is the default." |

**Group `Content`**

| Leaf | Type | Label | Notes |
|---|---|---|---|
| subgroup **Kinds on this feed** | | | |
| `kinds.item` … `kinds.skill` | bool ×7 | Items, Money, Currencies, Reputation, Appearances, Experience, Skill-ups | `kinds.appearance`: `clients = C.FEATURE_CLIENTS.appearances` |
| subgroup **Content** | | | |
| `price` | string / Dropdown `C.TOAST_PRICE_OPTIONS`, solo | Prices | "The value line on item toasts. AH needs a pricing addon. Highest is the larger of the two." `shownWhen kinds.item` |
| `ilvl` / `counts` / `source` | bool | Item level badge / Counts / Source tag | |
| `minQuality` | number / Dropdown `C.TOAST_QUALITY_OPTIONS` | Minimum quality | "Items below this never toast here. Recording is not changed." |
| `hideSources` | table / MultiCheck, wide, `invert = false`, values `C.SOURCE_OPTIONS` | Hide sources | host-drawn (9.1) |
| subgroup **Highlights and sounds** | | | |
| `hl.mount` + `hl.mountSound` | bool + string `dialogControl = "Ka0sMedia_Sound"`, values = LSM sounds led by `[""] = "None"` (the RangeMaster `soundValues` shape) | Mounts / Sound | sound `shownWhen hl.mount` |
| `hl.legendary` (+Sound) | | Legendaries / Sound | |
| `hl.upgrade` (+Sound) | | Upgrades / Sound | "An item above what you wear in its slot, of an armour type you wear." |
| `hl.appearance` (+Sound) | | New appearances / Sound | `clients = C.FEATURE_CLIENTS.appearances` |

**Group `Style`**

- subgroup **Background**: `O.ColorPair{ prefix = P, key = "bgColor", omit = { useClassColorBg = true }` (the Feed
  has no class fill, section 15.2)`, label = "Background color", page = "Toasts", group = "Style", subgroup = "Background", defaults = <feed's>, extra = {
  bgType (string Dropdown none/solid/gradient/texture, label "Type", disabledIf bgColorFromSkin), bgColor2 (color,
  "Gradient end color", shownWhen bgType == "gradient"), bgTexture (string `dialogControl =
  "Ka0sMedia_Background"`, values `O.LSMValues("background")`, "Texture", shownWhen bgType == "texture") } }`.
- subgroup **Border**: `O.BorderGroup{ prefix = P, fromSkin = "bar", page, group = "Style", subgroup = "Border",
  defaults, extra = { borderByQuality (bool, "Use the quality color", tooltip: "Item and currency toasts take
  their quality's color; it wins over the class color.") } }`.
- subgroup **Text**: `O.FontGroup{ prefix = P, fromSkin = true, flagsFromSkin = true, page, group = "Style",
  subgroup = "Text", defaults, extra = { fontSize2 (number 8-24, "Secondary size") } }`.
- subgroup **Size**: `width` (number 200-600 step 1, "Width"), `rowHeight` (24-96, "Row height", "The least
  height; a toast with more lines is taller."), `iconSize` (16-64, "Icon size"), `padding` (0-16, "Padding"),
  `gap` (0-20, "Gap").
- subgroup **Kind colors**: `colors.xp` (color, "Experience") + `colors.xpFromSkin` (bool, "Use the skin's
  color"), and the same for `colors.rep` ("Reputation") and `colors.skill` ("Skill-ups"). There is no class-colour
  companion, because a kind colour is not a class surface. Each swatch row is `disabledIf` its companion.

**Group `Motion`**: `enter` (Dropdown `C.TOAST_ENTER_OPTIONS`, "Enter"), `enterTime` (0-1 step 0.05, "Enter
time", shownWhen enter ~= "none"), `hold` (1-30 step 0.5, "Hold"), `fade` (0-5 step 0.1, "Then fade over"),
`pulse` (bool, "Pulse when a count rises"), `timerBar` (bool, "Countdown timer bar"), `smooth` (bool, "Slide rows
smoothly when they move").

**Group `Behavior`**: `shown` (1-10, "Shown at once"), `merge` (0-10 step 0.5, "Merge repeats within", "0
turns merging off."), `showInCombat` (bool, "Show in combat", "Off: gains in combat wait and show when it ends."),
`clickThrough` (bool, "Click-through in combat"), `pin` (bool, "Pin a row while hovered", "The whole feed holds
still while the pointer is over it."). Then the subgroup **Hide Blizzard alerts (all feeds)**, with the one
page-wide row (no `feed` stamp, drawn under every feed's Behavior tab):

| Path | Label | Tooltip |
|---|---|---|
| `settings.toasts.hideAlerts` | Loot and money alert toasts | "Hide the game's own loot and money pop-ups. Turned off, or with the addon disabled, they come back." |

`NS.SchemaToasts.Rows()` answers `feedRows("main")`, `feedRows("progress")`, `feedRows("extra")` and the
page-wide row, all in one array, and Schema.lua appends it. `NS.SchemaForPage`-style filtering is done in
`PanelToasts` (rows of `page == "Toasts"` with `row.feed == nil or row.feed == selected`). The slash CLI reaches
every row as an ordinary path, for example `/lh set settings.toasts.feeds.progress.enabled true`.

### 9.4 Counts

Each feed emits about 73 rows (General 7, Content 21, Style 33, Motion 7, Behavior 5), so 219 across the three plus
1 page-wide row. `tests/test_panel_toasts.lua` pins the per-feed set by equality, not by a typed count: every feed
emits the same leaves in the same order. The Retail and Forever counts differ by the two appearance rows per feed.
`tests/test_schema.lua`'s General `PARTITION` and row total do not change.

---

## 10. Lifecycle, disabled state, perf, taint

### 10.1 Stand-up and stand-down (`core/LifecycleSetup.lua:170-215`)

- `STAND_UP_STEPS`: `method("GainFeed", "Enable")` **before** `method("Collector", "Enable")`, so
  `wants` is computed before any observer registers. `method("Progress", "Enable")` goes after M2's
  `method("Appearance", "Enable")`. `method("Toasts", "Enable")` and `method("ToastBlizz", "Enable")` go after
  `method("Timeline", "Enable")`.
- `STAND_DOWN_STEPS`: `method("ToastBlizz", "Disable")` goes first after `SimStop`, so the suppression is restored
  while everything else is still up. `method("Progress", "Disable")` goes after M2's Appearance step.
  `method("Toasts", "Disable")` and `method("GainFeed", "Disable")` go after `method("Rollup", "Disable")`. The
  `UnregisterAllEvents` comment adds "Progress's five and Toasts' two".
- `Toasts:Enable()`: builds the three feed instances once through `NS.NewFeed` (8.2), the `__gain` target (GAIN),
  the `__ev` target (SETTINGS_CHANGED: `toasts`, `profile`, `enabled` → `RefreshConfig`, then each feed's
  `Refresh()`), `SyncRows`.
- `Toasts:Disable()`: unregister both targets and the rows; `Clear()` on each feed (every row released and hidden,
  the waiting list emptied, the clock disarmed, hover and freeze cleared, the strip and the handle hidden, locked
  again; Feed doc); wipe `NS.State.toastUnlocked`.
- `ToastBlizz:Enable()` runs `Apply()`. `ToastBlizz:Disable()` restores the alert events.

Disabled-state matrix (`docs/disabled-state.md`): with the addon disabled, no observer row is registered, no feed
row is shown, every feed's `Stats().awake` is false (no OnUpdate runs), the Blizzard alerts are the client's own,
and the Toasts page renders under the library's disabled notice (`opts.disabledFor`, as General's tabs do).

### 10.2 Blizzard alerts (`modules/ToastBlizz.lua`)

Chat-line hiding is out of scope (D25): no message filter, no global-string override, no `C.BLIZZ_CHAT_EVENTS`,
no `hideChat` row.

- `Apply()` is idempotent, called from `Enable`, from `GainFeed:Recompute` and on the reason `toasts`.
  `wantAlerts = settings.toasts.hideAlerts and GainFeed.on`. On → `Compat.SuppressAlertEvents(C.BLIZZ_ALERT_EVENTS,
  self._suppressed)` when not yet suppressed; off → `Compat.RestoreAlertEvents(self._suppressed)`.
- `C.BLIZZ_ALERT_EVENTS = { "SHOW_LOOT_TOAST", "SHOW_LOOT_TOAST_UPGRADE", "SHOW_LOOT_TOAST_LEGENDARY_LOOTED" }`.
  Each name is verified at M3.6 (3.3), and one that AlertFrame does not register is skipped by the member.
- **Taint.** No Blizzard function is replaced and no Blizzard table is written. `AlertFrame:UnregisterEvent`/
  `RegisterEvent` are frame method calls, which store no addon value on the frame.

### 10.3 Perf (performance-§2, §3)

| Bucket | Bracketed | Notes |
|---|---|---|
| `gainSend` | `GainFeed:Send` | the bus fan-out, the receivers (and so every `Push`) included |
| `toastPaint` | the `content` closure around `ToastContent.Content` | the lazy GatherAll/GetItemExtras sit inside; the Feed calls it on present, merge, repaint and settle, never per frame |
| `xpEvent` | `Progress:OnXP` | |
| `skillScan` | Progress's `scan` | |

- The Feed's clock is not bracketed by the host. Its cost is the library's (an unparented frame, armed only while a
  row needs a tick, Feed doc *Motion*). `tests/test_toast_feed.lua` pins `Stats().awake == false` on an idle feed
  and after `Clear()`.
- `tests/perf.lua` gains a scenario: 200 loot lines into one feed with merge on. The budget matches `lootLine`'s
  (the existing table in `docs/performance.md`).
- `docs/combat-path-sweep.md` gains rows: the GAIN tap (one field test while off), `OnGain` (filter, then `Push`:
  no allocation on a merge, one payload table on a new toast), the content call (lazy prices), and a pointer to the
  Feed's clock.

### 10.4 Taint and secrets

- No secure frames and no protected calls. Everything the Feed calls on its frames is legal in combat (Feed doc
  *Input*); `SetLocked(false)` is refused in combat by the library.
- `HandleModifiedItemClick` and `DressUpItemLink` run from a click script, which is the normal insecure path.
- Secrets: the chat guards (T11), `Compat.PlayerXP` (Forever's secret `UnitStat` family, `docs/forever-quirks.md:
  100-112`), and every C read in 3.1. A secret is never a table key. Feed keys are built from numeric ids that were
  already checked, and the Feed never reads into a payload.

---

## 11. Per-client behaviour

| Area | Retail 12.x | WoW Forever 1.x |
|---|---|---|
| Appearances kind, highlight and absorb | on (`C.FEATURE.appearances`) | rows dropped by the registry (`clients`); never wanted |
| Warband bank counts / warband money | shown (`C.FEATURE.warbandBank`) | absent |
| Skill-ups | `GetProfessions` + `GetProfessionInfo` (seventh return = skillLine); child line probed | `C_SkillInfo` walk, GUARDED, out of combat, `C.PROFESSION_SKILL_LINES`, parent dedupe (T14) |
| Upgrade armour gate | `C.CLASS_ARMOR[classFile]` | the equipped piece's subclass |
| XP | `UnitXP`/`UnitXPMax`/`UnitLevel`, max level `GetMaxPlayerLevel` | the same (present, kit lists); secrets guarded |
| Alert suppression | AlertFrame events (verified M3.6) | presence-gated; FOREVER-T1 probes it |
| Currency cap | `maxQuantity` / `useTotalEarnedForMaxQty` | the same fields where present; nil → no ratio |

`docs/ARCHITECTURE.md`'s per-client table (`:62`) gains these rows. `tests/test_client_shape.lua` checks that the
appearance rows are absent on Forever.

## 12. Simulator and probes

- **Providers** (`modules/SimWorld.lua` PROVIDERS, `:481-528`):
  - `{ "PlayerXP", function(w) return w.xp.cur, w.xp.max, w.xp.level, w.xp.capped end }`
  - `{ "ProfessionSkills", fill(out) from w.skills }`
  - `{ "ListSkillLines", same }`
  - `{ "CurrencyCap", from w.currencies[id].max/earned }`
- **World seeds** (clients-§5, by ClientKey): `xp = { cur = 1000, max = 50000, level = 70 (Retail) / 40 (Forever) }`;
  `skills = { [186] = { name = "Mining", rank = 300, max = 300 }, [185] = { "Cooking", 150, 300 } }` (Forever ids;
  Retail uses its child line ids from the fixture). `max` is added on one fixture currency (`2,000`) so the cap
  colours show.
- **Drivers** (`modules/SimDrivers.lua`, change the world first, then fire):
  - `D.XP(delta)` adds `delta` to `w.xp.cur`. While `cur >= max` it does `cur -= max`, `level += 1`,
    `max = floor(max * 1.1)`, and fires `PLAYER_LEVEL_UP(level)`. Then it fires `PLAYER_XP_UPDATE("player")`.
  - `D.Skill(line, rise)` raises `w.skills[line].rank` (capped at `max`), then fires `SKILL_LINES_CHANGED`. It never
    sends chat text.
- **Scenarios** (`modules/SimScenario.lua`): the quest scenario's turn-in is followed by `D.XP(1500)`, after M2's
  rep step. The gathering steps of the loot scenario gain `D.Skill(186, 1)`.
- **Real-event split** (`modules/Sim.lua:163-166`): `INTERFERENCE` gains `PLAYER_XP_UPDATE`, `PLAYER_LEVEL_UP` and
  `SKILL_LINES_CHANGED`. `SELF_LINE` gains `CHAT_MSG_SKILL = function() return true end`.
- **Session state (H4).** Toasts write no saved data. `Host.Prepare` (`:262-279`) adds
  `NS.GainFeed:ResetState()`, `NS.Progress:ResetState()` and `NS.Progress:Seed(true)` (from the world). A stop step
  runs `NS.GainFeed:ResetState(); NS.Progress:ResetState(); NS.Progress:Seed()` (live reseed) after
  `releaseStores`. The feeds are not cleared at stop, so simulated toasts fade out normally. The cyan strip goes
  when the session ends.
- **Probe** (`modules/Probe.lua:50-56` `P.EVENTS`): append `PLAYER_XP_UPDATE`, `PLAYER_LEVEL_UP`,
  `SKILL_LINES_CHANGED` and `CHAT_MSG_SKILL`. Add a probe line for `AlertFrame` presence and which
  `C.BLIZZ_ALERT_EVENTS` it registers, `GetProfessionInfo`'s returns for each profession
  (Retail), and `ListSkillLines` (Forever). `docs/forever-probes.md` lists FOREVER-T1 (alerts),
  T3 (skill lines vs `C.PROFESSION_SKILL_LINES`) and T4 (XP reads plain in combat).

---

## 13. Test plan

Characterization first. Every behaviour change gets a red case before its commit flips it.

### 13.1 Characterization (M3.1, before any edit)

- `tests/test_collector.lua`. A currency line with `recordCurrency` off leaves the loot window's `left` unchanged
  (today). A money line with `recordGold` off leaves `left` unchanged (today). A secret `msg` raises nothing today
  (pin the current outcome). Then M3.1 flips the first two to "consumes one" and adds `[Drop] reason=secret`.
- `tests/test_reconciler.lua`. `writeNet` calls `ReasonFor` once per key (pin it, so the local refactor cannot
  double-call).

### 13.2 New suites

Host tests drive **live** Feed instances from the vendored major (the headless loader loads `LibKa0s.xml`). A case
that steps the clock reaches the internal seam only after checking it exists (`if feed.__Step then
feed:__Step(dt) end`, Feed doc *Instance members*); the Feed's own behaviour (phases, geometry, merge mechanics,
pin) is the library's suite's, so host cases assert only what the host decides and what it passes in.

| Suite | Cases |
|---|---|
| `test_gain_feed.lua` | GAIN sent only by GainFeed (a source scan: no other `SendMessage(NS.MSG.GAIN` in `modules/`); the scratch is the same table on every send, every field reset; `wants` from feed enabled × kinds, appearance gated by feature; `on` false → observers send nothing; a recorded chat gain posts no feed claim; a gated chat gain posts one when the ledger is on, none when off; a diff gain consumed by the feed claim sends nothing, a remainder sends `qty = rest`; HoldClaims across a 10 s combat deferral prevents a double toast; diff exclusions (holder ≠ me, HOLDER_MOVE reasons, UNTRACKED/forceReason, drift, silent, `dlt < 0`); `recorded` matches `RowAllowed`; `sim` flag; Disable clears everything; Recompute calls SyncCapture on the three observers and ToastBlizz:Apply |
| `test_progress.lua` | `XPDelta` table (same level, one level up, two levels up reads short, level down, unseeded, zero); capped/max level → no send; secret read keeps the baseline and reseeds on regen; source QUEST (with detail) / KILL in combat / OTHER; skill first scan seeds only; Retail rise sends old/new/max; Forever dedupe of the pair, allowlist drops weapon skills, in-combat scan deferred to regen; rows registered only while wanted, per owner; Disable unregisters and resets |
| `test_toast_model.lua` | `Accepts` matrix (kinds, minQuality items only, hideSources, losses refused except REPUTATION); keys per kind; `NewPayload` copies every needed field and never aliases the GAIN scratch, reuses a spare; `Merge` sums qty and value, refreshes the moving fields, keeps SKILL `old`, frees `new` and answers `old`; `Absorb` both orders through `Get`/`Repaint`/`Dismiss` on a live feed; `LayoutFor`/`MotionFor`/`StyleFor` map every leaf (grow case, `fade` → `fadeTime`, `merge` → `mergeWindow`, `rightDismiss` true, `settle`, `borderByQuality` → `borderTint`, the class toggles, `fontSizeFromSkin` false) and answer the same table each call; `C.TOAST_SLOTS`, `C.TOAST_NUDGE_MAX`, `C.TOAST_SHOWN_MAX` equal `NS.FeedLib.SLOTS`, `NUDGE_MAX`, `SHOWN_MAX` |
| `test_toast_content.lua` | the spec per kind (icon, tint, badge, title and colours, count with nil `countColor`, prefix, the three lines, sub, highlight); cap colours at 69/70/89/90%; price lines for all five modes with and without AH, a recorded gain reuses `record.auctionPrice` (GatherAll not called), a repaint does not gather again; `Upgrade` matrix (armour type Retail/Forever, weapon subclass, two-slot lower, empty slot nil, Poor/Common rules, equal ilvl nil); the highlight order; kind colours from the owner token while FromSkin, the swatch otherwise; a raising read answers no line, never raises |
| `test_toast_feed.lua` | three feeds built through `NS.NewFeed` with `owner = "LootHistory"`'s folder name and the descriptor fields of 8.2; a gain routes to each accepting feed only (`Visible()`); `"new"` plays the highlight sound once per SOUND_GAP, `"merged"` plays none; a `false` push frees the payload; `_Click`: shift/ctrl → `Compat.ModifiedLinkClick` with the link, currency shift uses `CurrencyLink`, plain left → `B:ShowGain` (spy), not for XP/SKILL; combat rows: regen-disabled locks every feed, sets click-through and `Hold()` per setting (`Stats().clickThrough`, `held`), regen-enabled releases; `SetUnlocked` refused in combat answers locked; unlocked empty feed previews samples, re-lock clears them; `_Moved` writes x/y via SetMany; test mode previews and sets the test strip, off and combat start clear; the Test act pushes once (non-sticky) and works on a disabled feed, refused in combat; the sim strip wins while a session runs; `SETTINGS_CHANGED` runs `Refresh()` on each feed (a getter call count); Disable `Clear()`s every feed (`Stats()` all zero, `awake` false); with `NS.NewFeed` answering `NS.FeedStub` (Feed absent) every path runs and nothing raises |
| `test_toast_blizz.lua` | suppress records only the registered events, restore re-registers exactly those in order; setting off → restored; `GainFeed.on` false → restored; addon stand-down → restored; no AlertFrame → nothing raises |
| `test_panel_toasts.lua` | banner lists three feeds, Add feed enables the next and selects it, prints when none left; the strip is General, Content, Style, Motion, Behavior; picking a feed keeps the tab; each tab draws only the selected feed's rows plus the page-wide row under Behavior; every feed emits the same leaves in the same order; every emitted path has a default in `defaults/Profile.lua` equal to the row's; every `FromSkin` companion defaults true; Reset style to skin sets exactly the companions; Reset feed resets only that feed; slot onChange sets grow and clears x/y; the nudge sliders span `±C.TOAST_NUDGE_MAX`; the enter dropdown values are the Feed's vocabulary; appearance rows absent on Forever; Defaults tooltip text |

### 13.3 Existing suites touched

- `test_libka0s.lua` (M3.3): *"the ten adopted majors all resolved, and the seams are wired to them"*, with
  `LibKa0s-Feed-1.0` and the `NS.NewFeed`/`NS.FeedStub` asserts; `core/FeedSetup.lua` in the silent-flag paths.
- `test_surface_parity.lua` (M3.3): the Feed instance parity pair (8.1).
- `test_constants.lua`: pin `GAIN`'s wire string by driving `GainFeed:Send`.
- `test_sim_seam.lua` / `test_compat_routing.lua`: section 3.2.
- `test_dispatch.lua`: the SNAPSHOT/order gains the Progress and Toasts rows.
- `test_disabled.lua`: stand-down → no Progress/Toasts rows, every feed `Stats()` empty and asleep, Blizzard alerts
  restored, `GainFeed.on` false; stand-up → back.
- `test_perf.lua`: the four buckets; the `_lootLine` zero-overhead baseline with the feed off is unchanged.
- `test_reputation.lua` / `test_appearance.lua` (M2): the SyncCapture matrix (switch × feed); the feed sees a rep
  loss with the ledger off and a muted source; appearance OUT never sends.
- `test_sim.lua`: D.XP/D.Skill, INTERFERENCE, Prepare/stop reseed.
- `test_skin_values.lua` (kit): no new row (8.4: the kit's path rules cover the defaults and the seam). The rows are library-drawn, so no host
  `test_skin_switch` surface is declared for them; the skin switch is the Feed's (`OnLooksChanged` → `RepaintAll`).
- `test_schema.lua`: `COUNT_CLAIMS` for the doc row counts.
- `test_client_shape.lua`: as section 11.
- `test_browser*.lua`: `B:ShowGain` sets the search and the tab, and refuses while stood down.

---

## 14. Doc updates

- `docs/ARCHITECTURE.md`: the module map (FeedSetup, GainFeed, Progress, ToastModel, ToastContent, ToastFeed,
  ToastSample, ToastBlizz, CompatGain); the per-client table (11); the message bus table row for GAIN; the event
  subscriptions (Progress, Toasts rows); Frame layering (a pointer line: the toast containers are LibKa0s-Feed-1.0's,
  `STRATA` HIGH, library-owned); Taint notes (3.3 citations, 10.2); Known limitations (15.3); the Documentation map
  entries for any new page. No Documented-deviations row (D24, D25 need none).
- `docs/module-map.md`: `core/FeedSetup.lua` beside the other seams, and the LibKa0s paragraph's count of wired
  majors (`Feed` joins the wired list; it leaves the "ship in the payload but are not wired" list's neighbours
  alone) and the payload's major total, both re-counted against `libs/LibKa0s/LibKa0s.xml` at M3.3.
- `docs/message-bus.md`: the table, the payload section, the private-target list (`GainFeed.__ev`,
  `Toasts.__gain`, `Toasts.__ev`), "observers call GainFeed" next to the Filters precedent (`:79-81`).
- `docs/data-flow.md` (the tap points of section 5, the feed claims, the T10 reorder), `docs/schema.md` (the Toasts
  rows, how they are built per feed, the `feed` stamp, the leaf → Feed key map of 7.1), `docs/settings-panel.md`
  (the Toasts page, banner, tabs, acts), `docs/disabled-state.md` (10.1), `docs/performance.md` and
  `docs/combat-path-sweep.md` (10.3), `docs/midnight-quirks.md:5` (LH now guards secret chat payloads; it still
  holds no secret), `docs/forever-probes.md` (12), `docs/debug.md` (the `Gain` and `Feed` tags), `docs/browser.md`
  (ShowGain), `docs/smoke-tests.md` (TOAST-1..n: each kind on each client, slots and nudge, drag, merge/pulse, pin,
  combat hold and click-through, clicks, every style override and Reset to skin under three skins, hide alerts on
  and off and on disable, test mode, sim strip, the degraded install with the Feed files removed, Forever skill-ups
  and alert probe), `docs/test-cases.md` (regen), `README.md` (features, the tests badge count).

---

## 15. Deviations

### 15.1 Rulings (closed)

- **X1 → D24.** The feed host is `LibKa0s-Feed-1.0`, promoted by the owner's ruling (Feed doc *Why this exists: the
  promotion record*). Conformant under library-stack-§7; no register row. anti-pattern #47 is honoured by consuming
  every Feed behaviour rather than rebuilding it, and by `NS.FeedStub` for the degraded install.
- **X2 → D25.** Chat-line hiding is dropped, so events-frames-taint-§5 is not reached and no row is owed.

### 15.2 Recorded so a reviewer does not re-raise them (no ruling needed)

- **options-ui-§13/§14 and the mockup's feed tabs.** The mockup's top strip becomes the banner picker (9.1). That
  is conformance, which is what D23's "No deviation" means.
- **options-ui-§14, a page-wide row under one tab.** The *Hide Blizzard alerts (all feeds)* row is drawn on every
  feed's Behavior tab, under a heading that says "all feeds" (`mockups.html:438`).
- **The glow (T6).** It is the Feed's ADD-blend edge in the skin's glow colour, not `LibKa0s-Glow-1.0` (which
  needs `LibCustomGlow-1.0`); the Feed doc's *Style over the skin* records the same choice.
- **skinning-§9 typed defaults.** The swatch defaults sit in `defaults/`, which the kit's skin_values scanner
  leaves out by path (`defaults swatch`), so they carry no allow row. The kind colours are owner tokens.
- **The M2 amendment (5.4)** and **T10's attribution reorder**: design changes pinned by tests, not deviations.
- **events-frames-taint-§9.** The Blizzard alert symbols are verified at M3.6 (3.3) and gated by presence until then.
- **Alignment choices made at M3.2** (each the smallest choice inside the standard and the Feed contract):
  - Slot inset 20 px and nudge clamp ±600 are the Feed's (`SLOT_INSET`, `NUDGE_MAX`); the old 40 px and ±2000 are
    gone, and the nudge sliders span ±600. Main's default nudge (-220, +180) is inside it.
  - Pulse time 0.6 s, slide 0.15 s, drop fade 0.2 s and the waiting cap 10 are the Feed's defaults; the old
    `C.TOAST_PULSE_TIME`, `C.TOAST_SLIDE_TIME`, `C.TOAST_DROP_FADE` and `C.TOAST_HOLD_MAX` (20) are not defined.
    The drain shows only the newest `shown` anyway.
  - `enter` is stored in the Feed's vocabulary (`"right"`, not `"slideRight"`), so the getter maps nothing.
  - `fontShadow` is a bool (the Feed's key and FontGroup's toggle), not a colour.
  - The background ColorPair omits its class-colour companion (`useClassColorBg`): the Feed's style has no class
    fill, and a companion no reader resolves is a dead control (Options doc).
  - `fontSizeFromSkin = false` is passed, so the stored sizes draw (font size stays a stored value).
  - The handle label carries no TEST/SIM tag; the Feed stacks the strip beyond the handle instead.
  - An appearance absorbed into its item repaints without a pulse (`Repaint` has none).
  - A new toast's payload is collected, not pooled: Feed-1.0 has no close callback (LIBKA0S, a capability gap
    the Feed doc lists under *What is not here*; re-check when a close-reason callback ships).
- **Choices made at M3.5** (style and motion):
  - The kind tokens are `lh.toast.xp`, `lh.toast.rep` and `lh.toast.skill` (the owner's namespace; `toast.` would be
    no owner's and could become a library family). Experience and skill keep the mockup's hue under every skin;
    reputation follows `sem.info`. The degraded facade has no owner tokens, so it draws the stored swatch.
  - `M.MotionFor` leaves out an `enter` word outside the Feed's six, so the Feed's own default applies.
  - `M.StyleFor` leaves out an empty `font` (the profile's "the skin's own"), so the Feed resolves the face itself.
  - No `TOAST-STYLE` skin_values rows: `defaults/` and `core/SkinSetup.lua` are outside the kit's scan (8.4).

- **Choices made at M3.6** (settings, test toasts, alert hiding):
  - The background keeps its Use class color companion (`useClassColorBgColor`, default off), and the
    gradient end is its own `O.ColorPair` with `useClassColorBgColor2`: options-ui-§17 gives every
    swatch a class companion and exempts only a palette. The Feed has no class fill, so `M.StyleFor`
    resolves it (class first, then the skin, then the swatch; a resolved class turns `bgColorFromSkin`
    off). The kind colors are the palette exemption, and no swatch carries `disabledIf` (anti-pattern
    #74), so the kind swatches are not `disabledIf` their companions as 9.3 said.
  - The Content tab's middle subsection is **Details**, not "Content": a subgroup heading must not
    repeat its tab (options-ui-§7, `tests/test_panel.lua`). Hide sources closes Details.
  - Media rows (sounds, font, border, background texture) carry `widget = "MediaPicker"`.
  - Unlock refused (combat, no Widgets) prints its line and redraws nothing.
  - `Compat.AlertEventsRegistered` (PURE) is added for the probe's `alerts` part; modules/ may not
    read `AlertFrame` (the routing ban).
  - The perf scenario `toastMerge200` is recorded, not gated: the repaint builds strings; the merge's
    zero allocation is the model suite's.
  - The schema count claims and the per-tab breakdown gates count the General page; the Toasts rows
    (75 per feed, three feeds, plus `hideAlerts`) are pinned per feed by `tests/test_panel_toasts.lua`.

### 15.3 Known limitations (to record in ARCHITECTURE)

- Gains that come only through the diff (mail, vendor, AH, quest rewards with no chat line, every non-loot gold)
  are seen only while **Track holdings and losses** is on, and arrive after combat ends.
- A jump of more than one level in one XP event reads short.
- A chat line that arrives after its diff has already committed toasts twice (4.4).
- A History click searches by name. The History view's other filters (character, date, direction, the default
  minimum-quality floor) can still hide the row.
- Retail skill-ups on an expansion child line depend on what `GetProfessionInfo` reports (smoke probe).
- With the addon disabled, nothing reaches the feeds. Without the Feed major, no toast draws (the stub).

---

## 16. Task breakdown (plan rows)

Each task ends green on the four-command gate, with one commit and its ledger row updated in that commit. EOL is
repaired after each commit (plan `## Gate`).

| Task | Contents |
|---|---|
| **M3.1** Gain feed | (a) Characterization tests (13.1). (b) `core/CompatGain.lua` (3.1), its TOC line, SimSeam classes, routing BANNED. (c) `C.GainKind`, `MSG.GAIN`, the `C.TOAST_*` constants used by GainFeed, `C.PROFESSION_SKILL_LINES`. (d) `modules/GainFeed.lua` with feed claims and Recompute. (e) The Collector taps, the secret guards, the T10 reorder (the flipped characterization cases). (f) The Reconciler `writeNet` tap, `RowAllowed`, HoldClaims. (g) M2's Reputation/Appearance taps and SyncCapture. (h) `modules/Progress.lua` (XP, skills), its rows, TOC, lifecycle steps, perf buckets `gainSend`/`xpEvent`/`skillScan`. (i) The sim providers, seeds, drivers, scenario steps, INTERFERENCE, Prepare/stop, probe events. (j) `settings.toasts` defaults as 9.2 (needed for `wants`). Tests: `test_gain_feed`, `test_progress`, `test_constants`, `test_dispatch`, `test_sim`, `test_reputation`, `test_appearance`. If this commit grows too large, split it into M3.1a (a-g, j) and M3.1b (h, i) |
| **M3.2** Host alignment | Done: the host is LibKa0s-Feed-1.0 (D24); this spec aligned to its API. No code |
| **M3.3** Feed seam + wiring | `core/FeedSetup.lua` (8.1: `NS.FeedLib`, `NS.NewFeed`, `NS.FeedStub`) and its TOC line; `test_libka0s` "nine" → "ten adopted majors" with the Feed asserts and the silent-flag path; the `test_surface_parity` instance pair; `modules/ToastModel.lua` (7.1 `Config`, `LayoutFor`, `MotionFor` (and a pass-through `StyleFor` of the stored leaves), 7.2 `Accepts`, 7.3 `Key`, `NewPayload`/`FreePayload`, `Merge`); a minimal `modules/ToastContent.lua` (`icon`, `tint`, `title`, `count`); `modules/ToastFeed.lua` (8.2 the three `NS.NewFeed` descriptors, 8.3 `OnGain` → `Push`, 8.5 `onClick` → `_Click` and the combat rows → `SetLocked(true)`/`SetClickThrough`/`Hold`/`Release`, 8.6 `SetLocked`/`onMoved`/`Preview` while unlocked, `Refresh` on SETTINGS_CHANGED, `Clear` on Disable); `B:ShowGain`; the lifecycle steps; the frame-layering pointer comment; the TOC lines. Tests: `test_toast_model` (filters, keys, payload, merge reducer, getters, constants vs `NS.FeedLib`), `test_toast_feed` (routing, clicks, combat, unlock, refresh, Disable, the stub path), `test_disabled`, `test_browser*`, docs/test-cases regen |
| **M3.4** Row content | `modules/ToastContent.lua` in full (7.4): the spec's `badge`, `prefix`, `lines[1..3]`, `sub`, `highlight`; counts icons, cap colouring, price modes with lazy GatherAll cached on the payload, the upgrade rule, the per-kind lines (rep, XP, skill, appearance, money); `M.Absorb` through `Get`/`Repaint`/`Dismiss`; the highlight sounds on `Push == "new"` with `C.TOAST_SOUND_GAP`; `motion.settle = C.TOAST_COUNT_SETTLE` for the counts re-read; the `toastPaint` bracket around the `content` closure. Tests: `test_toast_content`, `test_toast_model` (absorb), `test_toast_feed` (sound gap, settle passes through `MotionFor`) |
| **M3.5** Style + motion mapping | `M.StyleFor` complete (7.1: the background, border, font and text-colour keys, `borderTint` ← `borderByQuality`, `borderClass`, `fontClass`, `fontSizeFromSkin = false`) and `M.MotionFor` complete (enter vocabulary, `fadeTime`, `mergeWindow`, `pulse`, `timerBar`, `smooth`, `pin`, `rightDismiss`); the kind-colour owner tokens in `core/SkinSetup.lua` (8.4) and their use in `ToastContent`; no skin_values row (8.4). Nothing is drawn by the host: style application, the skin repaint, enter/fade/slide, hold/fade, pulse, the timer bar, smooth reposition and the glow are the Feed's. Tests: `test_toast_model` (every style/motion key from a fixture, FromSkin on and off), `test_toast_content` (kind colours), the kit `test_skin_values` |
| **M3.6** Settings, test, Blizzard | `settings/SchemaToasts.lua` (9.3, leaves per 9.2, names read off the composers' emitted rows and fed back into 7.1's map), `settings/PanelToasts.lua`, the Schema.lua append, `P._makeMultiCheck`, page registration, the acts (Test → `Push(nil, p)`, Unlock → `SetUnlocked`, Reset feed, Reset style to skin, Add feed), test mode through `BrowserTable:SetTestMode` → `Preview`/`SetStrip("test")`, `ToastSample`, the sim strip → `SetStrip("sim")`, `modules/ToastBlizz.lua` (alerts only, 10.2), the 3.3 verification with citations in Taint notes, the perf scenario. Tests: `test_panel_toasts`, `test_toast_blizz`, `test_toast_feed` (test mode, Test act, sim strip), `test_schema`, `test_client_shape`, `test_perf` (scenario) |
| **M3.7** Docs + review + push | Section 14 in full, the smoke rows, the test-cases regen, the README. A review-pass workflow and its fixes. Push M3. Do not merge |

## 17. Open questions for the owner

None block the build. Every choice is ruled in 1.1 or recorded in 15.2 and can be reversed cheaply: T5 (a full feed
drops the oldest) is the Feed's only overflow policy, and T7 (no default sounds) is one default.
