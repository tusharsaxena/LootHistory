# M3 design: loot toast feeds (#38)

**Date:** 2026-11-27
**Branch:** `feat/2026-11-27-38-loot-toasts` (M3 of the stacked run; base M2, `feat/2026-11-27-rep-appearance-capture`)
**Issue:** [#38](https://github.com/tusharsaxena/LootHistory/issues/38)
**Plan:** `docs/superpowers/plans/2026-11-27-tooltip-toasts-farm.md`, rows M3.1 to M3.7; decisions D6, D7, D9 to D14, D23
**Mockups:** `docs/superpowers/specs/2026-11-27-tooltip-toasts-farm-mockups.html:272-471` (the #38 section, owner-approved v4)
**Builds on:** M1 `docs/superpowers/specs/2026-11-27-34-tooltip-holdings-design.md` (Compat live reads, the holdings
tally, `C.TIP_ICONS`) and M2 `2026-11-27-rep-appearance-capture-design.md` (the `REPUTATION` and `APPEARANCE`
capture paths and `Attribution:Peek`).
**Status:** Architect's design. M3.1 can start now. **M3.3 onwards waits for the owner's ruling on deviation
X1** (section 15). Line anchors are from the tree at `4e64d17` plus the M1 working tree. `core/Compat.lua` was
under concurrent edit while this was written, so re-check every anchor before you edit.

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
| T2 | **The feed host is this addon's own frames, built on LibKa0s parts** (Skin facade, tokens, composers, Pool, Media, Widgets `DragHandle`/`TestStrip`), not `LibKa0s-Toast-1.0` v4. This needs the owner's ruling, X1. | Toast v4 cannot do T1 (it presents at the tail, `libs/LibKa0s/Toast.lua:436-441`, and the oldest is the head that holds the saved point, `:277-288`). It hides a frame on expiry with no hook, so no fade-out (`:461-485`). It re-anchors every follower on reflow, so no pin (`:285-287`). It has no in-place update, so a merge would replay the enter animation. Its countdown is private (`:155-195`). Its own "not here" table rules out fade and per-toast position (`LibKa0s/docs/api/Toast/version-4-docs.md:227-238`). D1 rules out an upstream change. |
| T3 | **One ticker per feed drives all motion** (enter, hold, fade, pulse, countdown bar, smooth reposition): an `OnUpdate` that is set only while the feed has a row in motion or a timer running, and cleared when it is idle. No AnimationGroups. | One deterministic clock that headless tests can step (`feed:_tick(dt)`). A merge restarts the hold without replaying the enter. Pause is one flag. The idle cost is zero (performance-§2). |
| T4 | **Pin on hover freezes the whole feed** while the pointer is over any of its rows: no row moves, no row fades, a merge updates its row in place, and new gains wait in the feed's queue. On leave, everything resumes. With Pin off, hovering pauses only that row's fade. | The mockup's "pins the row in place" (`mockups.html:333`) holds only if nothing else moves under the pointer either. RLF's skip-the-pinned-anchor approach lets rows overlap. |
| T5 | **A full feed drops its oldest toast** to make room (a 0.2 s fade, or instantly when Fade is 0). | A loot feed is about the newest gain. Queueing behind a full stack would show stale loot. |
| T6 | **Highlight glow is drawn by the host**: an `ADD`-blend edge texture in the skin's `glow.color` (fallback `sem.gold`), pulsing in alpha through the ticker. No `LibKa0s-Glow-1.0`. | That driver needs `LibCustomGlow-1.0` (`LibKa0s/docs/api/Glow/version-2-docs.md:34-39`, `:151-153`), which `libs/` does not carry. Adoption is optional (library-stack-§7, `standards/library-stack.md:121`), and an edge tint is not the LibCustomGlow mapping that #47 guards. Section 15, note N3. |
| T7 | **Default sounds are None** for all four highlights. | The mockup's "Ka0s Chime" and "Blizzard" are examples (`mockups.html` lede: "Names and numbers are examples"). No such sound ships in `libs/LibKa0s/media/sounds/`, which is empty. |
| T8 | Hiding Blizzard's chat lines hides a kind's lines **only while some enabled feed shows that kind**, and only the player's own loot/currency/money lines. | Without this, hiding the XP lines with no feed showing XP would leave the player blind to XP. The mockup's row ("Chat lines for loot · currency · money · XP · reputation · skill") stays one checkbox. |
| T9 | **Dedupe across chat and diff uses feed claims** owned by GainFeed, separate from `R.claims`. | A quality-gated item posts no Reconciler claim (`modules/Collector.lua:151-159`). The diff then writes it as a row (M0 spec D2), and that would toast it a second time. |
| T10 | The **attribution consume moves above the record switches** on the currency and money lines, so a gain toasts with its source. It consumes whatever the switches say. | The source must not depend on toast settings (one answer per question). Section 6.2 covers the behaviour change. |
| T11 | Every chat handler gains a **secret guard**: a secret `msg` writes `[Drop] reason=secret` and returns. | Fixes an existing gap (`core/Util.lua:223-228` matches with no guard) that the taps widen. client-quirks-§2. |
| T12 | Plain click: `B:ShowGain(gain)` opens History, selects the History tab and puts the gain's name in Search. It does this whether or not the gain has a row. Its other filters are left alone. XP and skill have no rows, so a plain click on them does nothing. | D14. History has no scroll-to-row API (`modules/BrowserTable.lua:854-869`), and searching by name is the existing pattern (`modules/BrowserViews.lua:295-303`). |
| T13 | **Upgrade rule** (D9): see section 7.4. Armour has to match the class's armour type on Retail, or the equipped piece's subclass on Forever. A weapon has to match the equipped weapon's subclass. A two-slot item compares against the lower equipped ilvl. An empty slot gets no line. | It avoids "a mage sees plate" without a proficiency API. Forever classes change armour type at level 40, so on Forever the equipped piece is the reference. |
| T14 | Forever skill-ups count only the **profession lines** in `C.PROFESSION_SKILL_LINES`, deduplicated on `parentSkillLineID`. | Forever lists weapon skills, which rise all the time, and lists every profession twice (`docs/forever-quirks.md:172-177`). |
| T15 | Feed names are fixed: **Main feed**, **Progress feed** (defaults: reputation, experience and skill-ups at Top Center, growing down) and **Third feed** (all kinds, Top Left). | `mockups.html:359`, `:381`. Fixed keys keep the schema static, so the CLI, the resets and the Defaults all see ordinary rows. |

### 1.2 Scope

- **In:** GainFeed and its taps; the Progress observer (XP, skill-ups); three feeds; row content; style, motion and
  behaviour; the Toasts page; test toasts, test mode and the sim; unlock and drag; Blizzard-duplicate hiding;
  disabled state, perf and taint posture; docs.
- **Out:** farm mode (M4 subscribes to GAIN). Item tooltips on toast hover. Guild bank counts (D9). Party loot and
  rolls (D7). Item and money losses (D7). A slash verb for toasts (every setting is already reachable through
  `/lh set`). Renaming feeds. More than three feeds.

---

## 2. Files

### 2.1 New

| File | Responsibility | Est. lines |
|---|---|---|
| `core/CompatGain.lua` | New `NS.Compat` members (section 3). It is its own file because `core/Compat.lua` is at 1326 lines and M2 adds about 120; this file keeps both under the layout-§1 cap of 1500. | 230 |
| `modules/GainFeed.lua` | `NS.GainFeed`: the only `GAIN` sender, the reused scratch payload, `wants`/`on`, the feed claims, the diff tap helper, and `Recompute` → `SyncCapture` fan-out. | 260 |
| `modules/Progress.lua` | `NS.Progress`: the XP and skill-up observer. Rows registered only while the feed wants `XP`/`SKILL`. | 260 |
| `modules/ToastModel.lua` | `NS.ToastModel`: pure. Feed config snapshot, filters, merge key and merge, the entry pool, the price, cap, upgrade and line builders, the slot/nudge geometry and the layout offsets, lifecycle phase maths. No frames. | 520 |
| `modules/ToastRow.lua` | `NS.ToastRow`: builds one pooled row frame (regions made once) and paints an entry onto it through the Skin facade. | 420 |
| `modules/ToastFeed.lua` | `NS.Toasts`: the three feed containers, the GAIN receiver, the queue, the ticker, clicks, pin, combat hold and click-through, unlock and drag, test mode and the sim strips, and Enable/Disable. | 640 |
| `modules/ToastSample.lua` | `NS.ToastSample`: a fixed sample gain set per kind for test mode, the per-feed Test act and the unlocked view. It never goes through GAIN. | 140 |
| `modules/ToastBlizz.lua` | `NS.ToastBlizz`: alert-event suppression and the chat message filters, each with an exact restore. | 200 |
| `settings/SchemaToasts.lua` | `NS.SchemaToasts.Rows()`: builds every Toasts row (three feeds times the per-feed set, plus two page-wide rows) from one per-feed builder. | 420 |
| `settings/PanelToasts.lua` | The Toasts page: the banner picker plus the *Add feed* action, the tab strip, the General tab's acts, the Hide sources multi-check, Reset style to skin and Reset feed. | 330 |
| `tests/test_gain_feed.lua`, `tests/test_progress.lua`, `tests/test_toast_model.lua`, `tests/test_toast_feed.lua`, `tests/test_toast_blizz.lua`, `tests/test_panel_toasts.lua` | Section 13. | |

### 2.2 Changed

| File | Change |
|---|---|
| `modules/Collector.lua` | Taps on the three chat lines, the secret guard, the currency and money reorder (section 6.2), and `local GainFeed = NS.GainFeed` at load. |
| `modules/Reconciler.lua` | The `writeNet` tap (section 6.3). `GainFeed:HoldClaims` beside `L.HoldClaims` in `R:Flush` (`:809-812`). |
| `modules/Reputation.lua`, `modules/Appearance.lua` (M2) | The taps, and **`SyncCapture`**: rows are registered while the record switch is on **or** `GainFeed.wants[kind]`, and the record switch then gates only `Add` (section 6.4, an amendment to M2 §5). |
| `modules/BrowserViews.lua` | `B:ShowGain(gain)` (T12), beside `B:ShowTimeline` (`:295-303`). |
| `modules/BrowserTable.lua` | `SetTestMode` (`:~420-447`) also calls `NS.Toasts:SetTestMode(on)` after its own switch succeeds. |
| `core/Constants.lua` | `MSG.GAIN`; `C.GainKind`; `C.LAYERS.STRATA.ALERT = "HIGH"` plus the header stack comment (frame-layering-§5); the `C.TOAST_*` constants (section 4.3); `C.PROFESSION_SKILL_LINES`; `C.CLASS_ARMOR`; `C.BLIZZ_ALERT_EVENTS`; `C.BLIZZ_CHAT_EVENTS`. |
| `core/SimSeam.lua` | Classifies the new members (section 3.2). The header's GUARDED paragraph names `ListSkillLines` beside `ListCurrencies`. |
| `core/LifecycleSetup.lua` | Stand-up and stand-down steps (section 10.1). |
| `core/PerfSetup.lua` | Buckets `gainSend`, `toastPaint`, `xpEvent` and `skillScan`, appended last (`:63-69`). |
| `core/SkinSetup.lua` | Owner tokens for the kind colours (section 8.4) in `Skin:RegisterOwner(addonName, { tokens = ... })` (`:802-806`), and the degraded `NS.SKIN_FALLBACK` entries for them. |
| `core/WidgetsSetup.lua` | `NS.MakeDragHandle(parent, spec)` over `W.DragHandle` (nil when degraded), beside `NS.MakeTestStrip` (`:325`). |
| `defaults/Profile.lua` | `settings.toasts` (section 9.2). |
| `settings/Schema.lua` | Appends `NS.SchemaToasts.Rows()` to `S.Schema` before `SchemaLib:New` (`:~870`). The page/group header comment (`:32-37`) now says there are two pages. The Test mode note says "and the toast feeds". |
| `settings/Panel.lua` | Publishes `P._makeMultiCheck`. `P:Register` registers the Toasts page after General and before Profiles (`:789-810`). |
| `modules/SimWorld.lua`, `modules/SimDrivers.lua`, `modules/SimScenario.lua`, `modules/Sim.lua` | Section 11. |
| `LootHistory.toc` | Section 2.3. |
| `.luacheckrc` | `read_globals` gains `UnitXP`, `UnitXPMax`, `UnitLevel`, `IsXPUserDisabled`, `GetMaxPlayerLevel`, `GetProfessions`, `GetProfessionInfo`, `C_SkillInfo`, `C_MountJournal`, `C_TransmogCollection`, `GetDetailedItemLevelInfo`, `HandleModifiedItemClick`, `ChatFrameUtil`, `ChatFrame_AddMessageEventFilter`, `ChatFrame_RemoveMessageEventFilter`, `AlertFrame`, `PlaySoundFile`, `GetCursorPosition`, `UIParent`, as each is first read. |
| tests, docs | Sections 13 and 14. |

`CLAUDE.md`'s `LibKa0s icons:` line gains nothing. The toasts reuse M1's six `gi:` container marks (`C.TIP_ICONS`)
and the declared `chevron-up` (the upgrade arrow).

### 2.3 TOC placement

```
core\CompatClient.lua
# LOAD-BEARING POSITION: adds members to NS.Compat at file load (the gain feed's client reads, #38).
# Below core\Compat.lua, whose table it extends; ABOVE core\SimSeam.lua, which wraps every member in
# place at its own load, so a member defined below the seam escapes it (H2, NS.SimSeam:Unwrapped()).
core\CompatGain.lua
core\SimSeam.lua
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
# CONVENTIONAL: pure toast maths (#38); binds NS.Constants at load only.
modules\ToastModel.lua
# LOAD-BEARING POSITION: binds NS.ToastModel and NS.Skin as file-scope locals at load;
# modules\ToastModel.lua and core\SkinSetup.lua must be above.
modules\ToastRow.lua
# LOAD-BEARING POSITION: binds NS.ToastModel, NS.ToastRow and NS.Perf at load; appends its regen
# rows to NS.EVENT_ROWS at file load. modules\ToastModel.lua and modules\ToastRow.lua must be above.
modules\ToastFeed.lua
# CONVENTIONAL: the sample gains; reached from NS.Toasts at call time only.
modules\ToastSample.lua
# CONVENTIONAL: Blizzard-duplicate hiding; reads NS.GainFeed and NS.Util at call time only.
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
above Collector and Progress below Appearance. In `tests/run.lua`, the load order mirrors the TOC.

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

--- Add / remove a chat message event filter: ChatFrameUtil.AddMessageEventFilter when present,
--- else ChatFrame_AddMessageEventFilter (and the matching Remove). Answers false when neither exists.
function Compat.AddChatFilter(event, fn)   --> bool             (PURE)
function Compat.RemoveChatFilter(event, fn) --> bool            (PURE)

--- AlertFrame event suppression: for each name in `events`, when AlertFrame:IsEventRegistered(name)
--- answers true, UnregisterEvent it and record it in `into`; Restore re-registers exactly `into`'s
--- names, in the same order, and wipes it.
function Compat.SuppressAlertEvents(events, into) --> n         (PURE)
function Compat.RestoreAlertEvents(into)          --> n         (PURE)

--- UIParent's width and height, and its effective scale (for the nudge from a drag), plain numbers.
function Compat.ScreenRect()               --> w, h, scale
```

### 3.2 Sim-seam classification

- **PURE** (`core/SimSeam.lua`): `ModifiedLinkClick`, `PlayMediaSound`, `AddChatFilter`, `RemoveChatFilter`,
  `SuppressAlertEvents`, `RestoreAlertEvents`, `ScreenRect`.
- **GUARDED:** `ListSkillLines`. It expands and collapses skill headers, which is UI state, so during a session it
  answers the world's `skills` and never walks.
- **WRAPPED** (the default): `PlayerXP`, `ProfessionSkills`, `CurrencyCap`, `ItemEquipInfo`, `ItemLevelOf`,
  `EquippedLink`, `IsMountItem`, `IsUncollectedLook`, `CurrencyLink`, `CurrencyIcon`.
- `tests/test_sim_seam.lua` `CLASSIFIED` gains all nineteen (with `ItemIcon`, WRAPPED). `tests/test_compat_routing.lua` `BANNED` gains bare
  reads in `modules/` of `UnitXP`, `UnitXPMax`, `GetProfessions`, `GetProfessionInfo`, `C_SkillInfo`,
  `GetInventoryItemLink`, `HandleModifiedItemClick`, `PlaySoundFile`, `AlertFrame`, `ChatFrame_AddMessageEventFilter`
  and `ChatFrameUtil`, each with `use =` its member.

### 3.3 Verification gates (events-frames-taint-§9)

`AlertFrame`, the alert event names in `C.BLIZZ_ALERT_EVENTS`, and both chat-filter API names are not in the kit's
lists (`tests/_kit/client_globals_live.lua` has neither `ChatFrame_AddMessageEventFilter` nor `ChatFrameUtil`). M3.6
cites each one against a commit-pinned `wow-ui-source` (Retail, and the `forever` branch where one exists) in
`docs/ARCHITECTURE.md` *Taint notes*, before the rows ship. A name that does not resolve is skipped at run time (the
members are presence-gated). `/lh debug probe` lists `AlertFrame`, the filter API, `GetProfessionInfo`'s seventh
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
C.TOAST_SLOT_INSET   = 40      -- px from the screen edge a slot's point sits at before the nudge
C.TOAST_NUDGE_MAX    = 2000
C.TOAST_DROP_FADE    = 0.2     -- the fade of a toast dropped by a full feed or a right-click
C.TOAST_SLIDE_TIME   = 0.15    -- smooth reposition
C.TOAST_PULSE_TIME   = 0.4
C.TOAST_COUNT_SETTLE = 0.5     -- counts re-read once this long after the paint (client-quirks-§3)
C.TOAST_SOUND_GAP    = 1       -- at most one highlight sound per feed per second
C.TOAST_HOLD_MAX     = 20      -- combat-held gains kept per feed (oldest dropped)
C.TOAST_PRICE_OPTIONS = { { value = "none", text = "None" }, { value = "vendor", text = "Vendor" },
  { value = "ah", text = "AH" }, { value = "both", text = "Vendor + AH" }, { value = "highest", text = "Highest" } }
C.TOAST_QUALITY_OPTIONS -- built like C.QUALITY_OPTIONS (core/Constants.lua:272-278) over 0..5; text for 0 is
                        -- "Poor (everything)", the rest "<colored quality> and above"
C.TOAST_ENTER_OPTIONS = { none, fade, slideLeft "Slide from left", slideRight, slideUp, slideDown }
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

## 7. The toast model (`modules/ToastModel.lua`, pure)

### 7.1 Feed config snapshot

`M.Config(fid)` reads `NS.db.profile.settings.toasts.feeds[fid]` into a cached flat table `cfg[fid]`, rebuilt on
`SETTINGS_CHANGED` (`toasts`, `profile`, `enabled`) by `NS.Toasts`. Draw paths read only `cfg`, never the profile.
`cfg.kinds` is keyed by `C.GainKind`. `cfg.hideSources` is the set.

### 7.2 Filter (`M.Accepts(cfg, g)`)

The gain passes when all of these hold: `cfg.enabled`; `cfg.kinds[g.kind]`; `g.kind ~= "ITEM"` or `(g.quality or
0) >= cfg.minQuality`; `not (g.source and cfg.hideSources[g.source])`; `g.kind ~= "APPEARANCE"` or `g.dir == "IN"`;
and `g.kind ~= "GOLD" and g.kind ~= "ITEM"` or `g.dir == "IN"`, which is D7's no item or money losses (the taps
already send only IN for those).

### 7.3 Entries, keys and merge

- **The entry** is a pooled table (`M.NewEntry()` takes from a free list, `M.FreeEntry(e)` wipes it and returns it)
  holding a copy of the payload fields the row needs, plus the row state: `key`, `qty`, `value`, `lastAt`, `t` (the
  phase clock), `phase`, `pulse`, `highlight`, `paintedAt`, `y` and `targetY`, and `frame`.
- **Keys** (`M.Key(g)`): ITEM `"i:"..id`; CURRENCY `"c:"..id`; GOLD `"g"`; REPUTATION `"r:"..id..":"..dir`; XP
  `"x"`; SKILL `"s:"..id`; APPEARANCE `"a"`. All appearances share one key, so a burst reads "x3" with the latest
  name.
- **Merge** (`M.Merge(feed, g, now)`). A live or queued entry with the same `key` and `now - e.lastAt <= cfg.merge`
  (and `cfg.merge > 0`) takes the merge:
  - It sums `qty`, and `value` too. It refreshes the fields that move with each gain (`standing`, `level`, `cur`,
    `max`, `new`) and keeps the original `old` on SKILL.
  - It sets `lastAt = now`, and restarts the hold: `t = cfg.enter`, which skips the enter. When `cfg.pulse` is on
    it sets `pulse = C.TOAST_PULSE_TIME`.
  - It moves the entry to index 1 (the newest slot, D13). Under a pin freeze (T4) it stays where it is.
  - It answers the entry.
  - Otherwise `nil`, and the caller makes a new entry.
- **Absorbing an appearance into its item.** An APPEARANCE gain whose `itemID` matches a live ITEM entry inside the
  merge window does not make an appearance entry. It sets `e.newLook = true` and `e.highlight = "appearance"` on the
  item entry, with a repaint and a pulse. An ITEM gain that arrives while an APPEARANCE entry for its itemID is live
  takes that flag and frees the appearance entry. `M.Absorb(feed, g)` does both and answers true when it consumed
  the gain.

### 7.4 Content builders (`M.Lines(cfg, e, out)`, filling a reused `out`)

| Field | Rule |
|---|---|
| `title` | ITEM, CURRENCY, APPEARANCE: `name` in the quality colour (meaning colour, skinning-§9). REPUTATION: `name` in kind colour `rep`. XP: `"+%s XP"` in kind colour `xp`. SKILL: `name` in kind colour `skill`, then the new rank, then `"+N"` in `sem.good`. GOLD: `Util.FormatMoney(qty)` (coloured coins, `.gc .sc .cc` in the mockup) |
| `count` | `"x"..qty` for ITEM and CURRENCY; nil otherwise. It is drawn in `sem.gold` while `pulse > 0` |
| `prefix` | REPUTATION `"‹"..label.."›"`, XP `"‹"..level.."›"`, drawn dim (`hud.label`) |
| `counts` (`cfg.counts`) | ITEM: M1's `NS.HoldingsTally:Item(itemID)`, the logged-in holder's `bags`, `bank` and (Retail) warband `tabs`, while `trackLedger` is on; else `Compat.LiveItemCounts(itemID)` (M1 §4.3). Each nonzero part is a `C.TIP_ICONS` mark plus a count. GOLD: `Compat.GetMoney()` with the bags mark, plus the warband's stored money (`NS.Holdings:Get("§warband").money`, Retail with ledger on) with the tabs mark. CURRENCY: the cap line below |
| `cap` | CURRENCY: `q, max, earned, uses = Compat.CurrencyCap(id)`. With `max`, the text is `FormatCount(uses and earned or q).." / "..FormatCount(max)` and the ratio `r = (uses and earned or q)/max`; colour `sem.bad` when `r >= 0.9`, `sem.warn` when `r >= 0.7`, else `hud.label`. Without `max`, the text is `FormatCount(q)` |
| `progress` | REPUTATION: `FormatCount(standing).." / "..FormatCount(threshold)` when both are numbers (as M2's `FactionSnapshot` reports them; check against M2's final shape in M3.4). XP: `("%.1f%% of level"):format(cur/max*100)`; on `levelUp` the text is `"Level "..level` |
| `source` (`cfg.source`) | `C.SourceLabel[source]`, drawn in `hud.label`. Shown for ITEM, CURRENCY, GOLD, APPEARANCE and REPUTATION |
| `value` | ITEM only, by `cfg.price`. `vendor = sellPrice * qty`, where `sellPrice` is the 3rd return of `Compat.GetItemExtras(link)`. `ah = Pick(GatherAll(link, itemID)) * qty`, taken from `record.auctionPrice` when the gain was recorded and gathered lazily otherwise. `none` gives nothing. `vendor` gives `"Vendor "..fmt(vendor)`. `ah` gives `"AH "..fmt(ah)`. `both` gives both on one line (left vendor, right AH). `highest` gives `"Value "..fmt(max(vendor, ah))`. A zero or missing part is left out. GatherAll runs only when the entry passed the filter and the mode needs AH |
| `ilvl` (`cfg.ilvl`) | ITEM: the 1st return of `Compat.GetItemExtras(link)` (weapons and armour only), drawn in the icon's top-left corner |
| `upgrade` | ITEM, when `cfg.hl.upgrade`. The rule is T13: see `M.Upgrade` below. The text is the `chevron-up` mark (in `sem.good`) and `"+"..diff.." over equipped"` |
| `subtitle` | APPEARANCE: `"Appearance collected"`. An item with `newLook` gets the same line under its value line |
| `highlight` | the first that applies, in this order: `mount` (`Compat.IsMountItem`), `legendary` (quality 5), `upgrade`, `appearance` (`newLook`, or `Compat.IsUncollectedLook(link)` on Retail). Each needs its `cfg.hl.*` switch |

`M.Upgrade(equipLoc, classID, subclassID, ilvl, quality, classFile, equippedFn)` answers `diff` or nil:

- The item must be equippable gear: `equipLoc ~= ""` and in `C.EQUIP_LOC_SLOTS`, a new constant mapping each
  `INVTYPE_*` to its slot or slots (`INVTYPE_FINGER` → {11, 12}, `INVTYPE_TRINKET` → {13, 14},
  `INVTYPE_WEAPON` → {16, 17}, ... — RLF's `equipSlotMap` contents, written fresh).
- For each slot, `link = equippedFn(slot)`. Any empty slot gives nil (no line). Equipped ilvl is
  `Compat.ItemLevelOf(link)`, and a two-slot item takes the **lower** of the two.
- Armour (`classID == 4`, subclass 1 to 4) must have a subclass equal to `C.CLASS_ARMOR[classFile]` on Retail, and
  to the equipped piece's subclass on Forever. A weapon (`classID == 2`) must have a subclass equal to the equipped
  piece's.
- Following RLF (`Features/ItemLoot/ItemLoot.lua:266-279`), a Poor item over a better equipped piece, or a Common
  item over one above Common, gives nil.
- `diff = ilvl - equippedIlvl`. It answers `diff` when `diff > 0`, else nil. An equal ilvl is never an upgrade,
  because the stat-delta check RLF uses is Retail-only and costly.

### 7.5 Geometry

- **The container's point** is `M.SlotOffset(slot, x, y)`. It answers `point, ox, oy` with `ox = x + inset.x`,
  `oy = y + inset.y`. The inset is `C.TOAST_SLOT_INSET` pointing inward from each edge the slot touches (LEFT
  column `+inset`, RIGHT column `-inset`, CENTER column 0; TOP row `-inset`, BOTTOM row `+inset`, MID row 0). The
  container is set with `SetPoint(point, UIParent, point, ox, oy)`.
- **The row stack** comes from `M.Layout(feed)`, which sets `e.targetY` for entry index `i` (1 = newest). For
  grow up: `y_1 = 0` and `y_i = y_{i-1} + h_{i-1} + gap`, rows anchored `BOTTOM` on the container's `BOTTOM`. For
  grow down: `y_i = -(sum of h + gap)` with rows anchored `TOP` on `TOP`. The rows fill the container's width, so
  the horizontal position is always 0. `h_i = max(cfg.rowHeight, pad*2 + lineCount * lineHeight)`, where
  `lineHeight = fontSize + 2` for the title line and `fontSize2 + 2` for each secondary line.
- **The nudge from a drag** comes from `M.NudgeFromRect(slot, left, bottom, right, top, screenW, screenH)`. It takes
  the container rect in UIParent units and answers `x, y` such that `M.SlotOffset(slot, x, y)` reproduces the rect,
  each clamped to `±C.TOAST_NUDGE_MAX`.
- **Alignment and icon side.** `cfg.align == "right"` right-justifies every text line and puts the right-hand
  fields (source tag, AH part) on the left. `cfg.iconSide == "right"` puts the icon on the row's right edge and
  insets the text from the left by `pad`. Both are inputs to `ToastRow.Layout`, as in the mockup's flipped rows
  (`mockups.html:281-302`).

### 7.6 Lifecycle phases (`M.Advance(e, cfg, dt, paused)`)

`t` runs only while not `paused` (pinned, or hovered with Pin off). It answers `alpha`, `dx`, `dy`, `bar` and
`done`:

- `phase = "enter"` while `t < cfg.enterTime`, with `k = t / enterTime` eased out. Fade gives `alpha = k`. A slide
  gives an offset of `(1-k) * dist`, where `dist` is the feed width (left/right) or the row height (up/down); the
  sign comes from the direction. None gives `enterTime = 0`.
- `"hold"` while `t < enter + hold`, with `alpha = 1` and `bar = 1 - (t - enter) / hold`.
- `"fade"` while `t < enter + hold + fade`, with `alpha = 1 - (t - enter - hold) / fade` and `bar = 0`.
- `done` past that. A dropped or right-clicked entry has its `phase` forced to `"drop"`, fading over
  `C.TOAST_DROP_FADE` from its current alpha.
- `pulse` counts down independently, even while paused, so a merge under a pin still pulses. The border alpha is
  `0.6 + 0.4 * sin(pulse / PULSE_TIME * pi)`.
- The highlight glow alpha loops `0.35 + 0.35 * sin(GetTime() * 4)` while `e.highlight` is set.

---

## 8. Rows and feeds (frames)

### 8.1 Containers (`modules/ToastFeed.lua`)

- One `Frame` per feed, `"LootHistoryToastFeed_"..fid`, parent `UIParent`. Strata `C.LAYERS.STRATA.ALERT`
  (`"HIGH"`, frame-layering-§1 T5, interactive). Not toplevel, clamped to screen. Its width is `cfg.width` and its
  height 1. It is the parent of every row in the feed. It is built lazily on the feed's first gain, first test or
  first unlock.
- `C.LAYERS` becomes `STRATA = { WINDOW = "HIGH", ALERT = "HIGH", MODAL = "DIALOG", POPUP = "FULLSCREEN_DIALOG" }`.
  The header stack comment gains a line: `HIGH ALERT  the three toast feeds (#38), not toplevel, clamped; peer of
  the History window, which keeps its own toplevel raise`. `LEVEL` stays empty: every toast part is a region (a
  texture or font string) on the row frame, or the library's drag handle and strip, which set their own levels.
  The "empty on purpose" sentence stays true.
- `grep -rn 'SetFrameStrata("' modules` still finds nothing. The feed reads `C.LAYERS.STRATA.ALERT`.

### 8.2 Row frame (`modules/ToastRow.lua`)

`ToastRow.Build(parent)` makes a `Frame` with `BackdropTemplate` and `EnableMouse(true)`, and creates once:

- `bg` (BACKGROUND), and `edge` (the backdrop's edge, or the skin Shell's).
- `glow` (OVERLAY, `ADD` blend, the `WHITE8X8` edge strips from `NS.Skin` primitives). It is hidden unless
  highlighted.
- `icon` (ARTWORK) with an `iconBorder` texture, and the `ilvl` font string over its corner.
- The font strings `title`, `count`, `prefix`, `line2L`, `line2R`, `line3L`, `line3R`, and `sub`.
- `bar` (OVERLAY texture, 2 px, along the foot). It is hidden unless `cfg.timerBar`.
- Scripts are set once: `OnEnter`, `OnLeave` and `OnMouseUp` call `NS.Toasts:_RowEnter/Leave/Up(self, button)`.

Rows come from `NS.Pool.NewKeyed()` per feed (`core/PoolSetup.lua:24`; Pool minor 2, `AcquireKeyed(pool,
e.key, factory)`). The factory is `ToastRow.Build(container)`. A merge keeps its frame, because the key is the
same. Release is per row through a small free list kept on the feed (Pool has no single-key release, so
`ToastFeed` keeps `feed.free` and `feed.byKey` itself and uses Pool only for `ReleaseAllKeyed` on Clear and on
stand-down).

`ToastRow.Paint(row, e, cfg, lines)` runs inside a Shape-A bracket `toastPaint`.

- **Background.** When `cfg.bgColorFromSkin`: `NS.Skin.Shell(row, { noTopBar = true, noBands = true })` (the
  skin's panel look, repainted on a skin switch through the Skin record). Otherwise by `cfg.bgType`:
  - `none`: no fill.
  - `solid`: `WHITE8X8` tinted `cfg.bgColor`.
  - `gradient`: `bg:SetGradient("HORIZONTAL", c1, c2)`, using `cfg.bgColor` and `cfg.bgColor2`.
  - `texture`: `LSM:Fetch("background", cfg.bgTexture)` tinted `cfg.bgColor`.
  - When the companion is off, the frame's Shell record is replaced with `{ keepEdge = true, noTopBar = true,
    noBands = true }`, so a skin repaint leaves the host fill alone (Skin doc §135).
- **Border.** `style, show, size = NS.Skin.BarBorder(cfg.borderStyle, true, cfg.borderSize,
  cfg.borderStyleFromSkin)`. Colour precedence (skinning-§6, "class and meaning colours come first"):
  `cfg.borderByQuality` and `e.quality` → the quality colour; then `cfg.useClassColorBorder` → the player's class
  colour (`Compat.ClassColor`); then `cfg.borderColorFromSkin` → `S.Token("bar.border")`; else `cfg.borderColor`.
  While `pulse > 0` the border alpha follows 7.6. While a highlight is set, `glow` shows in
  `S.Token("glow.color") or S.Token("sem.gold")`.
- **Fonts.** Every string goes through `NS.Skin.HudFont(fs, { face = S.Resolve("hud.font", cfg.font,
  cfg.fontFromSkin), size = S.HudFontSize(isTitle and cfg.fontSize or cfg.fontSize2), flags =
  S.FontFlags(cfg.fontFlags), shadow = cfg.fontShadow, shadowFromSkin = cfg.fontShadowFromSkin })`. Text colour:
  meaning colours first (quality, `sem.good`/`sem.bad`/`sem.warn`, coin colours), then the kind colours, then
  `cfg.useClassColorFont` → class, then `cfg.fontColorFromSkin` → `S.HudTextColor()`, else `cfg.fontColor`.
  Secondary lines use `S.HudLabelColor()` where they carry no meaning colour.
- **Icon.** ITEM: `Compat.ItemIcon(itemID)` (`C_Item.GetItemIconByID`; added to `core/CompatGain.lua` as a WRAPPED member, the
  nineteenth), else the `?` icon. CURRENCY: `Compat.CurrencyIcon`. GOLD: the coin icon `NS.Icon("coins")` if
  declared, else the client's `Interface\\Icons\\INV_Misc_Coin_01`, which is game art and needs no skin row.
  REPUTATION, XP and SKILL use fixed game-art icons from a constant `C.TOAST_KIND_ICON`. The icon border takes the
  quality colour (meaning) where there is one, else the row's border colour.
- **Counts icons.** `NS.IconMarkup(C.TIP_ICONS[container], nil, iconPx)`, the M1 markup helper
  (`core/MediaSetup.lua:127`).
- **Layout.** `ToastRow.Layout(row, cfg, lines)` places the icon by `iconSide` and the text block by `align`,
  using `cfg.iconSize`, `cfg.padding` and the row height from 7.5, and answers `h`.
- **The settle re-read.** At `paintedAt + C.TOAST_COUNT_SETTLE`, the ticker repaints only the `counts`/`cap` line
  once (client-quirks-§3, state lags its own event).

A skin switch is handled by `NS.Skin.OnLooksChanged(function() NS.Toasts:Repaint() end)` at file load
(`modules/Timeline.lua:610` precedent). It repaints every live row.

### 8.3 The receiver and the queue

`Toasts:OnGain(g)` is the GAIN handler on its private target `__gain`. For each feed `f` in `C.TOAST_FEEDS` with
`M.Accepts(cfg[f], g)`, in this order:

- `M.Absorb` → stop.
- `M.Merge` → repaint that row, re-layout, start the ticker, stop.
- Otherwise build a new entry. If the feed is in a pin freeze, or it is combat and `not cfg.showInCombat`, it goes
  on `feed.waiting`: merged there too, capped at `C.TOAST_HOLD_MAX`, oldest dropped. Otherwise it is presented.

`present(feed, e)`:

1. If `#feed.live >= cfg.shown`, the last live entry becomes `phase = "drop"` (T5).
2. Insert at index 1, acquire a row, paint it (this is where the lazy GatherAll and GetItemExtras reads happen),
   set `t = 0`, lay out, start the ticker.
3. Play the highlight sound when one applies: `cfg.hl[kind].sound ~= ""`, and the last sound for this feed was more
   than `C.TOAST_SOUND_GAP` ago → `Compat.PlayMediaSound(key)`.

`feed.waiting` drains in arrival order when the freeze ends (OnLeave of the last hovered row) and at
`PLAYER_REGEN_ENABLED`.

### 8.4 Kind colours (owner tokens)

`core/SkinSetup.lua` registers owner tokens on `Skin:RegisterOwner(addonName, { ..., tokens = TOAST_TOKENS })`.
The names follow the owner-token rule in `LibKa0s/docs/api/Skin/` (`SkinOwnerTokens.lua` minor 1); check the
spelling at M3.5.

| Token | Default (Ka0s Default) | Role |
|---|---|---|
| `toast.xp` | the mockup's `#e58cff` as `{0.898, 0.549, 1, 1}` | XP title |
| `toast.rep` | `sem.info`'s value | reputation name (M2 ruling A9's colour) |
| `toast.skill` | `#7aa7ff` as `{0.478, 0.655, 1, 1}` | skill name |

Each feed's `colors.xp`, `colors.rep` and `colors.skill` rows (section 9) carry `<key>FromSkin` companions, true by
default, that read these tokens. The literal defaults sit in `core/SkinSetup.lua` as the owner's token defaults.
That is the named skinning-§1 home for an owner colour, so it needs no allow row. The swatch defaults in
`defaults/Profile.lua` get `Kit.skinValues.rows` entries (cause `TOAST-STYLE`, why: "a player's override swatch,
drawn only while its FromSkin companion is off").

### 8.5 Ticker (T3)

`feed.ticker` is the container's `OnUpdate`. It is set when a row enters, merges, drops, pulses or moves, and
cleared when nothing is moving, nothing is pulsing or highlighted, no countdown is running, and nothing is waiting
on a settle re-read. A feed with only sticky rows (test mode) and no highlight clears it too. Each frame, for each
live entry:

1. `M.Advance` → `row:SetAlpha(alpha)`. Re-anchor only when `dx`/`dy` changed (the enter slide).
2. The countdown bar width, when `cfg.timerBar`.
3. Smooth reposition when `cfg.smooth`: `e.y` moves toward `e.targetY` over `C.TOAST_SLIDE_TIME`, and the row is
   re-anchored only while it moves. When `cfg.smooth` is off, `e.y = e.targetY` at once.
4. `done` → release the row, free the entry, re-layout.

`paused` is `feed.frozen` (a pin freeze) or `e.hovered and not cfg.pin`. Combat does not pause.

### 8.6 Clicks, hover, combat

- **`OnEnter`.** `e.hovered = true`; when `cfg.pin`, `feed.frozen = true`. **`OnLeave`:** clears them, and when no
  row in the feed is hovered, unfreezes and drains `waiting`.
- **`OnMouseUp(button)`.** While the feed is unlocked, the left button is ignored (it drags). Otherwise:
  - right → `phase = "drop"` (dismiss);
  - left with a modifier down (`Compat.ModifierDown("shift")` or `"ctrl"`, M1) → `Compat.ModifiedLinkClick(e.link
    or (e.kind == "CURRENCY" and Compat.CurrencyLink(e.id)))`. Shift links the item in chat and ctrl opens the
    dressing room (the client's own handling, both clients);
  - plain left → `NS.Browser:ShowGain(e)` (T12).
- **Combat.** The rows `"Toasts"`: `PLAYER_REGEN_DISABLED` → for each feed with `cfg.clickThrough`,
  `row:EnableMouse(false)` on every live row and on every row acquired until regen. `PLAYER_REGEN_ENABLED` → the
  mouse back on, drain `waiting`. Toast frames are not protected, so these calls are legal in combat
  (events-frames-taint-§2). They are registered while any feed is enabled (`Toasts:SyncRows()`).
- **`B:ShowGain(e)`** (`modules/BrowserViews.lua`). It returns when `e.kind == "XP" or e.kind == "SKILL"`.
  Otherwise it runs `self:Show()`, `self:SelectTab("History")`, and if `B:ActiveTab() == "History"`,
  `self:SetSearchText(e.kind == "GOLD" and "Gold" or e.name)`. Show already refuses while stood down or hidden by
  the visibility setting (`modules/Browser.lua:837-861`).

### 8.7 Unlock and drag

- Unlock is session state, `NS.State.toastUnlocked[fid]`, never stored (it is like the History window's lock, not a
  setting). It is toggled by the General tab's *Unlock* act.
- When unlocked: the container gets `SetMovable(true)`, a drag handle from `NS.MakeDragHandle(container, { label =
  C.TOAST_FEED_LABEL[fid] .. (testOrSim and " " .. tag or ""), ... })` docked on its top edge (frame-layering-§2
  chrome), and, when the feed is empty, the sticky sample set (preview-mode, *SHOULD trigger the preview while
  unlocked*).
- The handle's drag runs `container:StartMoving()` and `StopMovingOrSizing()`. Then `x, y =
  M.NudgeFromRect(cfg.slot, container:GetLeft(), ...)` is written through `NS.Schema:SetMany({ {P.."x", x},
  {P.."y", y} })`, and the container is re-anchored from the slot (7.5).
- When the handle's label carries the TEST or SIM tag, the feed's strip is hidden (preview-mode v2.114.0 allows
  this).
- Re-locking hides the handle and clears the unlocked preview. Combat start re-locks every feed and refuses unlock
  while in combat (the drag would move a frame mid-pull; this follows the History window's lock behaviour).
- A degraded install (no `DragHandle`) has no drag. The nudge rows still move the feed.

### 8.8 Test mode, the Test act, the sim marker

- **Test mode** (`state.testMode`, the Master controls checkbox). `BrowserTable:SetTestMode(on)` calls
  `NS.Toasts:SetTestMode(on)`. On: each enabled feed shows `ToastSample.ForFeed(fid)`, one sample per enabled kind,
  sticky (they never advance past hold), painted through the normal `present`/`Paint` path (preview-mode,
  same-render-path SHOULD). The amber strip comes from `NS.MakeTestStrip(container, NS.L["Test mode"], "test",
  "hud")` (`core/WidgetsSetup.lua:325`), on the top edge. Off, or combat start (the existing end of test mode), the
  samples clear. Live gains still toast during test mode, above the samples.
- **The Test act** (per feed, on the General tab). It runs `ToastSample.ForFeed(fid)` once through the normal
  lifecycle (not sticky), as a one-shot preview, and it works while the feed is disabled so the player can see a
  look before enabling it. It is refused in combat.
- **Sim.** While `NS.Sim:IsActive()`, every feed with live rows carries `NS.MakeTestStrip(container, NS.L["Sim
  mode"], "sim", "hud")` (the cyan strip). Simulated gains arrive through GAIN like real ones (section 11), so the
  toasts are the real render path. `NS.Sim:AddListener` (`modules/SimPanel.lua` precedent) shows and hides the strip.
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
- **Defaults** (the page button) restores every Toasts row of all three feeds plus the two page-wide rows. Tooltip:
  "Restore every setting of all three toast feeds, and the Blizzard-duplicate options, to their defaults. Other
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
    bgColorFromSkin = true, useClassColorBg = false, bgType = "solid",
    bgColor = { r = 0.07, g = 0.08, b = 0.1, a = 0.92 }, bgColor2 = { r = 0.12, g = 0.13, b = 0.16, a = 0.92 },
    bgTexture = "Solid",
    borderStyle = "None", borderSize = 1, borderColor = { r = 0.23, g = 0.24, b = 0.28, a = 1 },
    useClassColorBorder = false, borderStyleFromSkin = true, borderColorFromSkin = true, borderByQuality = false,
    font = "", fontSize = 13, fontSize2 = 11, fontColor = { r = 0.9, g = 0.89, b = 0.84, a = 1 },
    useClassColorFont = false, fontFlags = "@skin", fontShadow = { r = 0, g = 0, b = 0, a = 1 },
    fontFromSkin = true, fontColorFromSkin = true, fontShadowFromSkin = true,
    width = 320, rowHeight = 48, iconSize = 36, padding = 6, gap = 5,
    colors = { xp = { r = 0.898, g = 0.549, b = 1, a = 1 }, xpFromSkin = true,
               rep = { r = 0.31, g = 0.55, b = 1, a = 1 }, repFromSkin = true,
               skill = { r = 0.478, g = 0.655, b = 1, a = 1 }, skillFromSkin = true },
    enter = "slideRight", enterTime = 0.3, hold = 5, fade = 1, pulse = true, timerBar = false, smooth = true,
    shown = 5, merge = 3, showInCombat = true, clickThrough = false, pin = true,
  }
  for k, v in pairs(over) do f[k] = v end
  return f
end
-- in settings:
toasts = {
  hideAlerts = false, hideChat = false,
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
| `x` / `y` | number, slider ±2000 step 1 | Nudge X / Nudge Y | "Pixels from the slot. Dragging the unlocked feed writes this." |
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

- subgroup **Background**: `O.ColorPair{ prefix = P, key = "bgColor", companionKey = "useClassColorBg", label =
  "Background color", page = "Toasts", group = "Style", subgroup = "Background", defaults = <feed's>, extra = {
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
still while the pointer is over it."). Then the subgroup **Hide Blizzard duplicates (all feeds)**, with the two
page-wide rows (no `feed` stamp, drawn under every feed's Behavior tab):

| Path | Label | Tooltip |
|---|---|---|
| `settings.toasts.hideAlerts` | Loot and money alert toasts | "Hide the game's own loot and money pop-ups. Turned off, or with the addon disabled, they come back." |
| `settings.toasts.hideChat` | Chat lines for loot, currency, money, XP, reputation and skill | "Hide your own lines of these kinds in chat, for each kind a feed shows. Loot History still records them: it reads the event, not the chat frame." |

`NS.SchemaToasts.Rows()` answers `feedRows("main")`, `feedRows("progress")`, `feedRows("extra")` and the two
page-wide rows, all in one array, and Schema.lua appends it. `NS.SchemaForPage`-style filtering is done in
`PanelToasts` (rows of `page == "Toasts"` with `row.feed == nil or row.feed == selected`). The slash CLI reaches
every row as an ordinary path, for example `/lh set settings.toasts.feeds.progress.enabled true`.

### 9.4 Counts

Each feed emits about 74 rows (General 7, Content 21, Style 34, Motion 7, Behavior 5), so 222 across the three plus
2 page-wide rows. `tests/test_panel_toasts.lua` pins the per-feed set by equality, not by a typed count: every feed
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
- `Toasts:Enable()`: the `__gain` target (GAIN), the `__ev` target (SETTINGS_CHANGED: `toasts`, `profile`,
  `enabled`), `RefreshConfig`, `SyncRows`.
- `Toasts:Disable()`: unregister both targets and the rows; for each feed clear the ticker
  (`SetScript("OnUpdate", nil)`), `ReleaseAllKeyed` the rows, free the entries, hide the container, the handle and
  the strip; clear `NS.State.toastUnlocked`.
- `ToastBlizz:Enable()` runs `Apply()`. `ToastBlizz:Disable()` restores the alert events and removes every chat
  filter.

Disabled-state matrix (`docs/disabled-state.md`): with the addon disabled, no observer row is registered, no feed
frame is shown, no OnUpdate runs, the Blizzard alerts and chat lines are the client's own, and the Toasts page
renders under the library's disabled notice (`opts.disabledFor`, as General's tabs do).

### 10.2 Blizzard duplicates (`modules/ToastBlizz.lua`)

- `Apply()` is idempotent, called from `Enable`, from `GainFeed:Recompute` and on the reason `toasts`.
  - `wantAlerts = settings.toasts.hideAlerts and GainFeed.on`. It is on → `Compat.SuppressAlertEvents(
    C.BLIZZ_ALERT_EVENTS, self._suppressed)` when not yet suppressed; off → `Compat.RestoreAlertEvents(
    self._suppressed)`.
  - The chat filters: for each event of `C.BLIZZ_CHAT_EVENTS` in array order (§5's deterministic order), the
    filter is added when `hideChat` and `GainFeed.toastWants[kindOf(event)]`, else removed. `_filters[event]`
    tracks it, so add and remove are never doubled.
- `C.BLIZZ_ALERT_EVENTS = { "SHOW_LOOT_TOAST", "SHOW_LOOT_TOAST_UPGRADE", "SHOW_LOOT_TOAST_LEGENDARY_LOOTED" }`.
  Each name is verified at M3.6 (3.3), and one that AlertFrame does not register is skipped by the member.
- `C.BLIZZ_CHAT_EVENTS = { { "CHAT_MSG_LOOT", "ITEM", "loot" }, { "CHAT_MSG_CURRENCY", "CURRENCY", "currency" },
  { "CHAT_MSG_MONEY", "GOLD", "money" }, { "CHAT_MSG_COMBAT_XP_GAIN", "XP" }, { "CHAT_MSG_COMBAT_FACTION_CHANGE",
  "REPUTATION" }, { "CHAT_MSG_SKILL", "SKILL" } }`.
- **The filter**, one file-local function per parse kind: `function(_, _, msg) if NS.Compat.IsSecret(msg) then
  return false end return NS.Util.ParseSelfLoot(msg) ~= nil end`. It does the same with `ParseSelfCurrency` and
  `ParseSelfMoney`. It never hides a roll-won line or another player's line. XP, faction and skill lines are always
  the player's own, so their filter returns true for a non-secret message. A filter returns only `true` or `false`.
  It never edits the message (events-frames-taint-§5: never replace AddMessage).
- **Restore.** Stand-down, the setting off, or the kind leaving every feed removes the filter.
  `RemoveMessageGroup` is never used, so nothing is written to the player's saved chat setup, and an uninstall
  leaves chat whole.
- **Taint.** No Blizzard function is replaced and no Blizzard table is written. `AlertFrame:UnregisterEvent`/
  `RegisterEvent` are frame method calls, which store no addon value on the frame. Section 15, X2, covers §5's
  SHOULD.

### 10.3 Perf (performance-§2, §3)

| Bucket | Bracketed | Notes |
|---|---|---|
| `gainSend` | `GainFeed:Send` | the bus fan-out, the receivers included |
| `toastPaint` | `ToastRow.Paint` | the lazy GatherAll/GetItemExtras sit inside |
| `xpEvent` | `Progress:OnXP` | |
| `skillScan` | Progress's `scan` | |

- The feed's OnUpdate is not bracketed per frame. Its cost is bounded (≤ 10 rows of arithmetic and SetAlpha) and
  it is absent when idle. `tests/test_toast_feed.lua` pins that `OnUpdate` is nil on an idle feed.
- `tests/perf.lua` gains a scenario: 200 loot lines into one feed with merge on. The budget matches `lootLine`'s
  (the existing table in `docs/performance.md`).
- `docs/combat-path-sweep.md` gains rows: the GAIN tap (one field test while off), `OnGain` (filter + merge, no
  allocation on a merge, one pooled entry on a new toast), the paint (lazy prices), the ticker.

### 10.4 Taint and secrets

- No secure frames and no protected calls. `EnableMouse` and `Show` on toast frames are legal in combat.
- `HandleModifiedItemClick` and `DressUpItemLink` run from a click script, which is the normal insecure path.
- Secrets: the chat guards (T11), `Compat.PlayerXP` (Forever's secret `UnitStat` family, `docs/forever-quirks.md:
  100-112`), and every C read in 3.1. A secret is never a table key. Entry keys are built from numeric ids that
  were already checked.

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
| Chat filters | `ChatFrameUtil.AddMessageEventFilter` or the global | the same resolution; FOREVER-T2 |
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
  `C.BLIZZ_ALERT_EVENTS` it registers, the chat-filter API name, `GetProfessionInfo`'s returns for each profession
  (Retail), and `ListSkillLines` (Forever). `docs/forever-probes.md` lists FOREVER-T1 (alerts), T2 (chat filter),
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

| Suite | Cases |
|---|---|
| `test_gain_feed.lua` | GAIN sent only by GainFeed (a source scan: no other `SendMessage(NS.MSG.GAIN` in `modules/`); the scratch is the same table on every send, every field reset; `wants` from feed enabled × kinds, appearance gated by feature; `on` false → observers send nothing; a recorded chat gain posts no feed claim; a gated chat gain posts one when the ledger is on, none when off; a diff gain consumed by the feed claim sends nothing, a remainder sends `qty = rest`; HoldClaims across a 10 s combat deferral prevents a double toast; diff exclusions (holder ≠ me, HOLDER_MOVE reasons, UNTRACKED/forceReason, drift, silent, `dlt < 0`); `recorded` matches `RowAllowed`; `sim` flag; Disable clears everything; Recompute calls SyncCapture on the three observers and ToastBlizz:Apply |
| `test_progress.lua` | `XPDelta` table (same level, one level up, two levels up reads short, level down, unseeded, zero); capped/max level → no send; secret read keeps the baseline and reseeds on regen; source QUEST (with detail) / KILL in combat / OTHER; skill first scan seeds only; Retail rise sends old/new/max; Forever dedupe of the pair, allowlist drops weapon skills, in-combat scan deferred to regen; rows registered only while wanted, per owner; Disable unregisters and resets |
| `test_toast_model.lua` | `Accepts` matrix (kinds, minQuality items only, hideSources, losses refused except REPUTATION); keys per kind; merge inside and outside the window, merge 0 off, sums qty and value, restarts at `t = enter`, sets pulse, moves to index 1, stays put under freeze; appearance absorption both orders; cap colours at 69/70/89/90%; price lines for all five modes with and without AH, a recorded gain reuses `record.auctionPrice` (GatherAll not called); `Upgrade` matrix (armour type Retail/Forever, weapon subclass, two-slot lower, empty slot nil, Poor/Common rules, equal ilvl nil); `SlotOffset` for all nine slots; `NudgeFromRect` round-trips `SlotOffset` for all nine; `Layout` grow up/down offsets with mixed heights; `Advance` phase boundaries, pause, drop fade, pulse under pause; the entry pool reuses tables |
| `test_toast_feed.lua` | container strata reads `C.LAYERS.STRATA.ALERT`; no SetFrameLevel call; new gain → one row, newest at index 1; a full feed drops the oldest; merge keeps the frame (same row object); right-click dismiss; shift/ctrl → `Compat.ModifiedLinkClick` called with the link; currency shift uses `CurrencyLink`; plain click → `B:ShowGain` (spy), not for XP/SKILL; left-click ignored while unlocked; pin freeze queues new gains and drains on leave; showInCombat off holds and drains at regen, capped at HOLD_MAX; clickThrough → EnableMouse(false) in combat on live and newly acquired rows, true after; OnUpdate nil on an idle feed and set while moving; test mode shows samples sticky with the amber strip and clears on off and on combat start; the Test act runs once and works on a disabled feed, refused in combat; the sim strip shows during a session; the unlocked empty feed shows samples and the handle; drag writes x/y via SetMany; Disable clears tickers, rows and handles; skin OnLooksChanged repaints live rows; a highlight sound plays once per SOUND_GAP |
| `test_toast_blizz.lua` | suppress records only the registered events, restore re-registers exactly those in order; filters added in `C.BLIZZ_CHAT_EVENTS` order and removed; a loot filter hides a self line and passes another player's line and a roll-won line; a secret message passes; a kind no feed shows is not filtered (T8); setting off → removed; addon stand-down → restored and removed; no filter API → nothing raises |
| `test_panel_toasts.lua` | banner lists three feeds, Add feed enables the next and selects it, prints when none left; the strip is General, Content, Style, Motion, Behavior; picking a feed keeps the tab; each tab draws only the selected feed's rows plus the two page-wide rows under Behavior; every feed emits the same leaves in the same order; every emitted path has a default in `defaults/Profile.lua` equal to the row's; every `FromSkin` companion defaults true; Reset style to skin sets exactly the companions; Reset feed resets only that feed; slot onChange sets grow and clears x/y; appearance rows absent on Forever; Defaults tooltip text |

### 13.3 Existing suites touched

- `test_constants.lua`: pin `GAIN`'s wire string by driving `GainFeed:Send`. The `C.LAYERS` keys.
- `test_sim_seam.lua` / `test_compat_routing.lua`: section 3.2.
- `test_dispatch.lua`: the SNAPSHOT/order gains the Progress and Toasts rows.
- `test_disabled.lua`: stand-down → no Progress/Toasts rows, feeds hidden, Blizzard restored, `GainFeed.on`
  false; stand-up → back.
- `test_perf.lua`: the four buckets; the `_lootLine` zero-overhead baseline with the feed off is unchanged.
- `test_reputation.lua` / `test_appearance.lua` (M2): the SyncCapture matrix (switch × feed); the feed sees a rep
  loss with the ledger off and a muted source; appearance OUT never sends.
- `test_sim.lua`: D.XP/D.Skill, INTERFERENCE, Prepare/stop reseed.
- `test_surface_parity.lua`: `NS.MakeDragHandle`'s degraded nil path; the facade members used (`Shell`, `BarBorder`,
  `HudFont`, `HudFontSize`, `FontFlags`, `HudTextColor`, `HudLabelColor`, `Token`, `Resolve`, `OnLooksChanged`) are
  already in the stub (`core/SkinSetup.lua:605-617`).
- `test_skin_values.lua` (kit): the `TOAST-STYLE` allow rows. `test_skin_switch.lua` (kit): declare the toast row
  surface (a painted row under the probe skin must change bg, border, text and glow).
- `test_schema.lua`: `COUNT_CLAIMS` for the doc row counts.
- `test_client_shape.lua`: as section 11.
- `test_browser*.lua`: `B:ShowGain` sets the search and the tab, and refuses while stood down.

---

## 14. Doc updates

- `docs/ARCHITECTURE.md`: the module map (GainFeed, Progress, Toast*, CompatGain); the per-client table (11); the
  message bus table row for GAIN; the event subscriptions (Progress, Toasts rows); Frame layering (a pointer line,
  ALERT); Taint notes (3.3 citations, 10.2); Documented deviations (X1, X2, when ratified); Known limitations (15.2);
  the Documentation map entries for any new page.
- `docs/message-bus.md`: the table, the payload section, the private-target list (`GainFeed.__ev`,
  `Toasts.__gain`, `Toasts.__ev`), "observers call GainFeed" next to the Filters precedent (`:79-81`).
- `docs/module-map.md`, `docs/data-flow.md` (the tap points of section 5, the feed claims, the T10 reorder),
  `docs/schema.md` (the Toasts rows, how they are built per feed, the `feed` stamp), `docs/settings-panel.md` (the
  Toasts page, banner, tabs, acts), `docs/disabled-state.md` (10.1), `docs/performance.md` and
  `docs/combat-path-sweep.md` (10.3), `docs/midnight-quirks.md:5` (LH now guards secret chat payloads; it still
  holds no secret), `docs/forever-probes.md` (12), `docs/debug.md` (the Gain and Toast tags), `docs/browser.md`
  (ShowGain), `docs/smoke-tests.md` (TOAST-1..n: each kind on each client, slots and nudge, drag, merge/pulse, pin,
  combat hold and click-through, clicks, every style override and Reset to skin under three skins, hide Blizzard on
  and off and on disable, test mode, sim strip, Forever skill-ups and alert probe), `docs/test-cases.md` (regen),
  `README.md` (features, the tests badge count).

---

## 15. Deviations to flag (the owner decides)

### 15.1 Needs a ruling

**X1. `library-stack-§7` / `anti-patterns #47`: the feed is not hosted on `LibKa0s-Toast-1.0`.** #47 forbids
hand-rolling what a LibKa0s module provides (`standards/anti-patterns.md:53`; `standards/library-stack.md:339`),
and Toast is "the alert-toast shell" (`library-stack.md:99`). T2 lists the six approved behaviours Toast v4 cannot
meet: newest at the anchor, fade-out, pin in place, an exact countdown, merge without re-entering, smooth
reposition. Three of them are impossible without a library change, which D1 rules out. Three ways forward:

1. **Accepted deviation (the architect's recommendation).** Add a register row: `| library-stack-§7 (anti-patterns
   #47) | The loot toast feeds (#38) are this addon's own frames (modules/ToastFeed.lua, ToastRow.lua) built on
   LibKa0s Skin, Options composers, Pool, Media and Widgets, not LibKa0s-Toast-1.0 | Toast v4 shows the oldest at
   the anchor, hides on expiry with no fade or hook, re-anchors hovered toasts, keeps its countdown private and has
   no in-place update; the owner-approved feed (mockups v4) needs all six (spec M3 §1.1 T2) | <date> | Toast gains
   newest-at-anchor, fade-out, an in-place update and a time-left read, or a second Ka0s addon needs a merging loot
   feed (then promote the feed engine, library-stack-§7 bars). |`
2. **A change to the standard.** A ruling that a merging, animated feed of rows is a different shape from a
   one-payload alert shell, so #47 does not reach it. That is an upstream change to `library-stack.md`'s Toast row.
3. **A Toast minor 5** (fade-out, an expire hook, a time-left read). This contradicts D1, and newest-at-head and pin
   risk promotion bar 2. Not recommended for this run.

M3.1 and M3.2 can proceed. **M3.3 waits for this ruling.** M3.2 records the decision as the register row (or the
upstream link) in its commit.

**X2. `events-frames-taint-§5`: chat hiding uses a message event filter, not a GLOBALSTRING override.** §5 says to
prefer overriding the `_G` strings. Here that would break capture, because `core/Util.lua:223-228` compiles the
loot patterns from those globals and `modules/SimDrivers.lua:14-16` formats lines from them. The filter keeps §5's
MUSTs: it never replaces AddMessage, it registers in a fixed order, it passes secret messages through, it hides only
the player's own lines, and it is removed on disable. Ruling needed: a register row (`| events-frames-taint-§5 |
Hide chat duplicates (#38) via ChatFrame message event filters | the GLOBALSTRING override would change the strings
the loot parser and the simulator compile from | <date> | the parser stops reading the globals |`), or an upstream
note that §5's SHOULD yields where the addon parses those strings.

### 15.2 Recorded so a reviewer does not re-raise them (no ruling needed)

- **options-ui-§13/§14 and the mockup's feed tabs.** The mockup's top strip becomes the banner picker (9.1). That
  is conformance, which is what D23's "No deviation" means.
- **options-ui-§14, page-wide rows under one tab.** The two *Hide Blizzard duplicates (all feeds)* rows are drawn on
  every feed's Behavior tab, under a heading that says "all feeds". They are not acts on the selected instance and
  do not govern every tab, so the band rule does not take them. The mockup puts them there (`mockups.html:438`).
- **N3, the glow (T6).** It is the host's edge pulse in the skin's `glow.color`. It does not adopt
  `LibKa0s-Glow-1.0`, which needs `LibCustomGlow-1.0` vendored. Adopting it later is a library plus vendor
  decision, and once adopted, this edge pulse is removed (library-stack-§7, a parallel copy is #47).
- **skinning-§9 typed defaults.** The swatch defaults carry `TOAST-STYLE` allow rows. The kind colours are owner
  tokens.
- **The M2 amendment (5.4).** Registration becomes "record switch **or** feed wants". That is a design change to
  M2's §5, not a standards deviation, and #85 still holds.
- **T10's attribution reorder** is a behaviour change, pinned by characterization tests.
- **events-frames-taint-§9.** The Blizzard symbols are verified at M3.6 (3.3) and gated by presence until then.

### 15.3 Known limitations (to record in ARCHITECTURE)

- Gains that come only through the diff (mail, vendor, AH, quest rewards with no chat line, every non-loot gold)
  are seen only while **Track holdings and losses** is on, and arrive after combat ends.
- A jump of more than one level in one XP event reads short.
- A chat line that arrives after its diff has already committed toasts twice (4.4).
- A History click searches by name. The History view's other filters (character, date, direction, the default
  minimum-quality floor) can still hide the row.
- Retail skill-ups on an expansion child line depend on what `GetProfessionInfo` reports (smoke probe).
- With the addon disabled, nothing reaches the feeds.

---

## 16. Task breakdown (plan rows)

Each task ends green on the four-command gate, with one commit and its ledger row updated in that commit. EOL is
repaired after each commit (plan `## Gate`).

| Task | Contents |
|---|---|
| **M3.1** Gain feed | (a) Characterization tests (13.1). (b) `core/CompatGain.lua` (3.1), its TOC line, SimSeam classes, routing BANNED. (c) `C.GainKind`, `MSG.GAIN`, the `C.TOAST_*` constants used by GainFeed, `C.PROFESSION_SKILL_LINES`. (d) `modules/GainFeed.lua` with feed claims and Recompute. (e) The Collector taps, the secret guards, the T10 reorder (the flipped characterization cases). (f) The Reconciler `writeNet` tap, `RowAllowed`, HoldClaims. (g) M2's Reputation/Appearance taps and SyncCapture. (h) `modules/Progress.lua` (XP, skills), its rows, TOC, lifecycle steps, perf buckets `gainSend`/`xpEvent`/`skillScan`. (i) The sim providers, seeds, drivers, scenario steps, INTERFERENCE, Prepare/stop, probe events. (j) `settings.toasts` defaults (needed for `wants`). Tests: `test_gain_feed`, `test_progress`, `test_constants`, `test_dispatch`, `test_sim`, `test_reputation`, `test_appearance`. If this commit grows too large, split it into M3.1a (a-g, j) and M3.1b (h, i) |
| **M3.2** Host decision | Record X1's ruling. When it is option 1, add the register row in `docs/ARCHITECTURE.md` and cite this spec's T2. A short `docs/` note keeps the spike findings (the Toast v4 limits with `Toast.lua` line anchors). No code. If the owner picks option 2 or 3, stop and re-plan M3.3-M3.5 against the ruling |
| **M3.3** Feed engine | `modules/ToastModel.lua` (7.1-7.3, 7.5, 7.6), `modules/ToastFeed.lua` (8.1, 8.3, 8.5-8.7 without style), a minimal `ToastRow` (icon, title, count; the skin Shell), `C.LAYERS.ALERT` plus the header comment, `NS.MakeDragHandle`, `B:ShowGain`, lifecycle steps, the TOC lines. Tests: `test_toast_model` (keys, merge, geometry, phases), `test_toast_feed` (rows, clicks, pin, combat, unlock, Disable), `test_disabled`, `test_browser*` |
| **M3.4** Row content | 7.4 in full: counts icons, cap colouring, price modes with lazy GatherAll, ilvl badge, upgrade rule, the highlights and sounds, per-kind lines (rep, XP, skill, appearance, money), absorb, the settle re-read, the `toastPaint` bucket. Tests: `test_toast_model` (content), `test_toast_feed` (sound gap, absorb) |
| **M3.5** Style + motion | 8.2's style application (background, border precedence, fonts, kind colours via owner tokens), the skin repaint, enter fade and slide, hold/fade, pulse, the timer bar, smooth reposition, the glow. The `TOAST-STYLE` skin_values rows and the skin_switch surface. Tests: `test_toast_feed` (style, motion), the kit skin suites |
| **M3.6** Settings, test, Blizzard | `settings/SchemaToasts.lua`, `settings/PanelToasts.lua`, the Schema.lua append, `P._makeMultiCheck`, page registration, the acts (Test, Unlock, Reset feed, Reset style to skin, Add feed), test mode wiring through `BrowserTable:SetTestMode`, `ToastSample`, the sim strip, `modules/ToastBlizz.lua`, the 3.3 verification with citations in Taint notes, the X2 row if ruled. Tests: `test_panel_toasts`, `test_toast_blizz`, `test_schema`, `test_client_shape`, `test_perf` (scenario) |
| **M3.7** Docs + review + push | Section 14 in full, the smoke rows, the test-cases regen, the README. A review-pass workflow and its fixes. Push M3. Do not merge |

## 17. Open questions for the owner

Only the two rulings above (X1 before M3.3, X2 before M3.6) block the build. Every other choice is ruled in 1.1 and
can be reversed cheaply: T4 (pin freezes the feed), T5 (a full feed drops the oldest), T7 (no default sounds) and
T8 (chat hiding follows the shown kinds) are each one condition or one default.
