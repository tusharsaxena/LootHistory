# Design — Holdings in the tooltip, and a public API (#34)

**Date:** 2026-11-27
**Branch:** `feat/2026-11-27-34-tooltip-holdings` (M1 of the stacked run; base M0, the LibKa0s v1.118.0 re-vendor)
**Issue:** [#34](https://github.com/tusharsaxena/LootHistory/issues/34)
**Plan:** [`../plans/2026-11-27-tooltip-toasts-farm.md`](../plans/2026-11-27-tooltip-toasts-farm.md), rows M1.1 to M1.6
**Mockups:** [`2026-11-27-tooltip-toasts-farm-mockups.html`](2026-11-27-tooltip-toasts-farm-mockups.html), the #34 section (owner-approved, v4)
**Status:** Architect's design; ready to build task by task. One item needs an owner ruling (section 14).


> **Owner ruling, 2026-11-27 (supersedes every Tooltip-tab mention below, sections 3.2, 7.3, 7.4, 12 and 14).**
> options-ui-§13 is honoured, not deviated from: there is **no Tooltip tab**. The five `settings.tooltip.*`
> rows are a subgroup titled "Holdings in tooltips" on the existing **Interface** tab, so General keeps its
> eight tabs and `settings/Panel.lua`'s eight-tab comment stays true. No Documented deviations row is
> written. (#38's Toasts and #39's Farm get settings pages of their own beside General, plan D23.)

## 1. Summary

Every item and currency tooltip gets a **Ka0s Loot History** block. It lists who on the account holds
the thing and where they keep it. Each container is drawn as a LibKa0s catalog icon with a count
beside it. The logged-in character's counts come from live client reads, every other holder's from
the holdings ledger (`db.global.holdings`). A stale container gets a dim age. A Total line closes the
block. A new **Tooltip** tab on General carries five settings. The block is hidden while **Track
holdings and losses** is off, and while the addon is disabled.

The same tally is published to other addons as **`LootHistory.API.v1`**. Every answer is a copy, and
a `HoldingsChanged` callback relays the ledger's own change message.

Owner decisions implemented (plan *Decisions* table):

| Id | What this design does with it |
|---|---|
| D2 | Live reads for the logged-in character: bags and bank through `C_Item.GetItemCount` diffs, and the warband bank (Retail) through the same diffs on the `§warband` line. Currencies come from `C_CurrencyInfo`. Every other holder, and every container the client cannot read live (equipped, mail, auctions), comes from the store. Section 5.3 reconciles D2's wording with the mockup's. |
| D3 | `settings.trackLedger` off hides the block entirely, and the API answers empty (sections 6.1 and 8.4). |
| D4 | Containers are drawn as `gi:` catalog icons plus a count, never as words. The icons go on the `CLAUDE.md` `LibKa0s icons:` line and into the vendored `media/icons/` in the same commit (section 6.4). |
| D5 | `_G.LootHistory = { API = NS.API }`, published with `rawset`. `NS.API.v1` carries the functions listed in section 8. Every answer is a copy. The callback relay uses CallbackHandler. The contract is written in `docs/ARCHITECTURE.md`. |

## 2. Scope

**In scope**

- An Item and a Currency `TooltipDataProcessor` post call, registered once per session.
- A holdings tally per thing (base itemID or currencyID), per holder and per container, with a live
  overlay for the logged-in character and the warband bank. The tally is cached and invalidated on
  `HOLDINGS_CHANGED`.
- The tooltip block: header, one line per holder that holds some, container icons and counts, a dim
  stale age, the Total rule, a modifier-only mode, a never-twice guard, and forbidden, comparison and
  secret guards.
- Five settings rows on a new General tab, **Tooltip**.
- The public API v1 and its `HoldingsChanged` relay.
- Compat members for every client read above, classified for the simulator seam.
- Tests, docs and smoke rows on Retail and WoW Forever.

**Out of scope**

- Gold tooltips. There is no money tooltip data type, and gold stays on the Holdings tab.
- Guild bank holdings. The ledger does not track them (plan D9 scope).
- Comparison (shopping) tooltips. They are skipped, so the block never appears two or three times.
- A settings toggle for comparison tooltips. The skip is fixed.
- Toasts (#38) and farm mode (#39). They reuse the tally later, but nothing here is built for them.
- Upstreaming the post-call helpers into LibKa0s. D1 rules it out; section 14 flags it as a
  promotion candidate.

## 3. Files

### 3.1 New files

| File | Responsibility |
|---|---|
| `modules/HoldingsTally.lua` | `NS.HoldingsTally`. The per-thing tally over the **saved** store, with a per-id cache, plus the live overlay composed on every call. It owns one private bus target, `__ev` (`HOLDINGS_CHANGED`, plus `SETTINGS_CHANGED` for the `ledger` and `profile` reasons), which wipes the cache. `Enable` / `Disable`. It is pure apart from the Compat reads. |
| `modules/HoldingsTip.lua` | `NS.HoldingsTip`. The two post calls (installed once, latch `_hooked`), the guard ladder, the never-twice marks, the re-entrancy guard, the block's rows and their paint through `Compat.AppendTooltipRows`, the hot-path settings cache, and the `tooltipBlock` perf bracket. It owns one private bus target, `__ev` (`SETTINGS_CHANGED`, for the `tooltip`, `ledger` and `profile` reasons). `Enable` / `Disable`. |
| `modules/HoldingsAPI.lua` | `NS.API.v1`, `NS.HoldingsAPI`. Builds the v1 table, publishes `_G.LootHistory` at file load, binds CallbackHandler, and relays the change message. It owns one private bus target, `__ev` (`HOLDINGS_CHANGED`, plus `SETTINGS_CHANGED` for `ledger` and `profile`). `Enable` / `Disable`. |
| `tests/mock_tooltip_data.lua` | An opt-in `TooltipDataProcessor` double, ported from `../DropWatcher/tests/mock_tooltip_data.lua` and extended with `Enum.TooltipDataType.Currency`. Not under `tests/_kit/`. |
| `tests/test_compat_tooltip.lua` | The Compat members in section 4. |
| `tests/test_holdings_tally.lua` | The tally (section 5). |
| `tests/test_holdings_tip.lua` | The block (section 6) and the settings rows' effect. |
| `tests/test_holdings_api.lua` | The API (section 8). |

### 3.2 Changed files

| File | Change |
|---|---|
| `core/Compat.lua` | The members in section 4: about 170 lines, which takes the file from 1098 to about 1270, still under the layout-§1 cap of 1500. |
| `core/CompatClient.lua` | Publishes `Compat.IsSecret` (PURE): the file's local `isSecret`, so `core/Compat.lua` can call it at call time. |
| `core/SimSeam.lua` | The new members join `PURE` (section 4.4). The header's "the four hook installers" becomes "the hook installers". |
| `core/Constants.lua` | Adds `C.TOOLTIP_MODIFIER_OPTIONS`, `C.TIP_ICONS`, `C.TIP_ICON_FALLBACK`, `C.TIP_CACHE_MAX = 128`, `C.TIP_ICON_SIZE = 12` and `C.API_VERSION = 1`. The `C.FEATURE_CLIENTS` comment adds the tooltip's warband split to `warbandBank`'s list. |
| `core/LifecycleSetup.lua` | Stand-down and stand-up steps (section 9.1). The header's carve-out paragraph names the third funnel. |
| `core/PerfSetup.lua` | Adds the `tooltipBlock` bucket, last. The header's "five handlers" becomes six. |
| `modules/Holdings.lua` | Adds `Holdings:SavedStore()` (section 5.1). |
| `defaults/Profile.lua` | Adds `settings.tooltip = { enabled = true, containers = true, warband = true, totalMin2 = true, modifier = "none" }`. |
| `settings/Schema.lua` | Five rows, group `Tooltip` (section 7). |
| `settings/Panel.lua` | Adds `{ key = "Tooltip" }` to `GENERAL_TABS` after `Interface`. The "Eight tabs, the options-ui-§13 budget" comment is rewritten (section 14). |
| `LootHistory.toc` | Three module lines (section 3.3). |
| `.luacheckrc` | Adds `TooltipDataProcessor` to `read_globals`. |
| `CLAUDE.md` | The `LibKa0s icons:` line gains six `gi:` names (section 6.4). |
| `libs/LibKa0s/media/icons/` | Re-copied from the v1.118.0 tag and re-pruned: the six `gi:` TGAs plus `game-icons/LICENSE-game-icons.txt` and `game-icons/AUTHORS.txt`. |
| `README.md` | Feature bullets, a Game-icons credit (a library-stack-§7 MUST, CC BY 3.0), the tests badge count. |
| tests: `test_sim_seam.lua`, `test_compat_routing.lua`, `test_perf.lua`, `test_disabled.lua`, `test_schema.lua`, `test_panel.lua` (via `panel_support.lua` `STRIP`), `test_holdings.lua`, `test_constants.lua`, `test_client_shape.lua`, `run.lua` | Section 11. |
| docs | Section 12. |

### 3.3 TOC placement

Directly below `modules\HoldingsTab.lua` and above `modules\TimelineModel.lua`, in this order:

```
# CONVENTIONAL: the holdings tally (#34). Reads NS.Holdings, NS.Compat and NS.Constants at call
# time only; kept beside the Holdings tab because both read the same store.
modules\HoldingsTally.lua
# LOAD-BEARING POSITION: binds NS.HoldingsTally and NS.Perf as file-scope upvalues at load (the
# tooltip post call's hot path, events-frames-taint-§7 / performance-§2); modules\HoldingsTally.lua
# and core\PerfSetup.lua must be above.
modules\HoldingsTip.lua
# LOAD-BEARING POSITION: binds NS.HoldingsTally at load, and publishes _G.LootHistory (public-api) at
# file load so an addon reading it at its own PLAYER_LOGIN finds it. modules\HoldingsTally.lua must
# be above.
modules\HoldingsAPI.lua
```

`HoldingsTip` and `HoldingsAPI` take `NS.HoldingsTally` as a load-time local. That is a module table,
not a Compat member, so `test_compat_routing.lua`'s capture scan does not apply. Every Compat member
is read as `NS.Compat.X(...)` at call time (H1). Nothing needs to load above `core\SimSeam.lua`, because
no new Compat member is defined outside `core/Compat.lua` or `core/CompatClient.lua`.

## 4. Compat additions

All of these are defined in `core/Compat.lua`, except `Compat.IsSecret`, which is in
`core/CompatClient.lua`. Both files load above `core/SimSeam.lua`, so `NS.SimSeam:Unwrapped()` stays
empty (H2). Every member is presence-gated and never raises on a client or harness that lacks the API.

### 4.1 Tooltip post calls and id readers (all PURE)

```lua
--- Register fn(tooltip, data) as a post call of every tooltip of data type `typeName`
--- ("Item", "Currency"): TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType[typeName], fn).
--- The enum member is resolved BY NAME (client-quirks-§5 Q18). The client keeps the call for the
--- session (there is no removal), so the caller registers once and gates its own body (slash-commands-§7).
--- @return boolean  false: no TooltipDataProcessor, no AddTooltipPostCall, no such data type, or fn not a function
function Compat.HookTooltipType(typeName, fn)

--- The item a post call's data names: data.id, else the id in data.hyperlink ("item:(%d+)").
--- Only those two fields are read, never a line's text (client-quirks-§5 Q17). Each passes through
--- Compat.IsSecret first. nil for a secret, a non-table, a non-positive or missing id.
--- @return number|nil
function Compat.TooltipItemID(data)

--- The currency a post call's data names: data.id, else Compat.CurrencyLinkID(data.hyperlink).
--- The same guards.
--- @return number|nil
function Compat.TooltipCurrencyID(data)

--- A table with AddLine and AddDoubleLine whose IsForbidden() is not true.
--- @return boolean
function Compat.TooltipWritable(tip)

--- ShoppingTooltip1/2 and ItemRefShoppingTooltip1/2, by frame name ("ShoppingTooltip%d$"); false for
--- an unnamed or secret-named tooltip.
--- @return boolean
function Compat.IsComparisonTooltip(tip)
```

Behavior on each client:

- **Retail 12.x.** Both data types exist. `data.id` is the itemID or the currencyID.
- **WoW Forever 1.x.** `TooltipDataProcessor` and the Item type are assumed present, because
  DropWatcher uses them, but that has never been probed (`../DropWatcher/docs/forever-quirks.md:206`).
  The Currency type is unverified. A missing type makes `HookTooltipType` answer false, and that
  block simply never draws. Probes FOREVER-17 and FOREVER-18 settle it (section 12).

### 4.2 Painting (PURE: the tooltip family only draws)

```lua
--- Append rows to a tooltip someone else owns, then tip:Show() so it lays itself out again. Never
--- SetOwner, never PlaceTooltip: the block does not own the tooltip (standalone-windows, Tooltip placement).
--- rows[i] = { left = string, right = string|nil,
---             lt = token|nil, lr, lg, lb = number|nil,   -- left color: a meaning color the caller read, else gtip token lt, else "gtip.body"
---             rt = token|nil }                            -- right color token, default "gtip.value"
--- A row with no `right` is AddLine(left, r, g, b); otherwise AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb).
--- Colors come from tip(token) at call time (THE ONE PLACE comment, core/Compat.lua:732).
--- @param n number  how many leading entries of `rows` to paint (rows is a reused scratch array)
--- @return boolean
function Compat.AppendTooltipRows(tip, rows, n)

--- `text` wrapped in the skin token's color as a |cff escape built from the token's components
--- (the kit's isBuilder shape: no typed color byte). Used only for the dim stale age inside a right column.
--- @return string
function Compat.TooltipTint(token, text)

--- A count with the client's digit grouping (BreakUpLargeNumbers: "1,205"), else tostring(n).
--- @return string
function Compat.FormatCount(n)
```

The `THE ONE PLACE` comment above `tip(token)` is widened to say that `AppendTooltipRows` is the
second painter, alongside the `Show*` helpers.

### 4.3 Live reads (WRAPPED: the simulated player is the real player, so live is right with no provider)

```lua
--- What the logged-in character holds of base item `itemID`, read live.
---   carried  = C_Item.GetItemCount(itemID, false, false, false, false)
---   withBank = C_Item.GetItemCount(itemID, true,  false, true,  false)
---   withAcct = C_Item.GetItemCount(itemID, true,  false, true,  true)   -- only where C.FEATURE.warbandBank
---   worn     = how many of NS.Constants.EQUIP_SLOTS and the bag inventory slots (Compat.BagInventorySlot
---              over C.BAG_IDS) answer Compat.GetInventoryItem(slot) == itemID
--- @return number|nil bags     max(0, carried - worn)      (the client's count includes worn gear; DropWatcher CompatItem.lua:66-78)
--- @return number|nil bank     max(0, withBank - carried)
--- @return number|nil account  max(0, withAcct - withBank), nil where there is no warband bank
--- Each part is nil when its GetItemCount call is absent, secret or not a number. All three are nil
--- for a non-number id. C_Item.GetItemCount answers per base itemID, which is the store's key (Scanner.lua:5-8).
function Compat.LiveItemCounts(itemID)

--- C_CurrencyInfo.GetCurrencyInfo(id).quantity, a plain number, else nil.
function Compat.CurrencyQuantity(currencyID)

--- "shift" / "ctrl" / "alt" -> IsShiftKeyDown / IsControlKeyDown / IsAltKeyDown; false otherwise.
function Compat.ModifierDown(key)

--- RAID_CLASS_COLORS[classFile] as r, g, b; nil for nil, an unknown class, or no table.
function Compat.ClassColor(classFile)
```

On both clients, the extra `GetItemCount` arguments are ignored where the client does not take them.
On Forever, `account` is always nil because of the `C.FEATURE.warbandBank` gate (clients-§4). The
Forever arity, whether bag-slot bags are counted, and whether `includeBank` answers away from a
banker are all unprobed. FOREVER-17 and TIP-9 cover them, and the tally's zero-suspect rule
(section 5.3) makes a wrong guess fall back to the store rather than show 0.

### 4.4 Sim-seam classification

- `core/SimSeam.lua` `PURE` gains `HookTooltipType`, `TooltipItemID`, `TooltipCurrencyID`,
  `TooltipWritable`, `IsComparisonTooltip`, `AppendTooltipRows`, `TooltipTint`, `FormatCount` and
  `IsSecret`.
- WRAPPED, the default: `LiveItemCounts`, `CurrencyQuantity`, `ModifierDown`, `ClassColor`.
- `tests/test_sim_seam.lua` `CLASSIFIED` gains all thirteen, with the same classes.
- `tests/test_compat_routing.lua` `BANNED` gains bare `TooltipDataProcessor`, `C_Item.GetItemCount`
  and `RAID_CLASS_COLORS` reads in `modules/`, each with `use =` its Compat member. That scan runs
  over shipped `modules/` files only. `modules/AnalyticsFormat.lua:96` reads `RAID_CLASS_COLORS`
  today, so in the same commit that read moves to `NS.Compat.ClassColor`, with a characterization
  test first.

## 5. The tally (`modules/HoldingsTally.lua`)

### 5.1 Which store

- Add `Holdings:SavedStore()` to `modules/Holdings.lua`. It returns `NS.db.global.holdings`, creating
  it the way `Store()` does, or `{}` before `InitDB`. It never returns the simulator's session table,
  and never test mode's sample.
- The tally and the API read only through `SavedStore()`, so test mode (`NS.State.testHoldings`) and
  `/lh sim` (`NS.SimStores.holdings`) never leak into a tooltip or into another addon. During a
  simulation, the tooltip shows the real saved ledger plus live counts.
- The `Holdings.lua` header (lines 6-10) adds a line saying that the tooltip and the API read the
  saved store.

### 5.2 Data structure

There are two caches, keyed by numeric id, so no thing-key string is built on the hot path. Each
cache is the thing key split by its kind (`i:` and `c:`):

```lua
T._items[itemID]         = entry
T._currencies[currencyID] = entry
entry = {
  rows  = { row, ... },   -- every holder in SavedStore with a nonzero stored count, PLUS the live holders
                          -- (me = NS.Util.PlayerKey(), and §warband) even at zero, so the overlay can lift them
  count = n,              -- #rows
  gen   = T._gen,         -- the wipe generation it was built under
  -- the renderer's replay memo (section 6.3) lives here too: sig, cfgVer, tintSig, lines, nLines
}
row = {
  holder = key, isMe = bool, isWarband = bool,
  classFile = e.meta.classFile or nil,
  stored = { [container] = n } or nil,   -- items: a COPY of e.items[id] (the store's table is never handed out); currency: nil
  storedCount = n,                        -- items: sum of stored; currency: e.currency[id] or 0
  scanned = e.scanned,                    -- a reference, read only by the tally (never escapes to the API)
}
```

- **Base-itemID matching.** The tooltip's `data.id` is the item's itemID, which is the base id.
  `e.items` is keyed by base itemID (Scanner.lua:5-8), and `C_Item.GetItemCount(itemID)` counts every
  variant of that id. So an ilvl or bonus-id variant matches its base. No link parsing goes past
  `item:(%d+)`.
- **Which holders.** Every key in `SavedStore()`, including characters on another realm and the
  `§warband` holder. Forgotten holders are absent from the store, so they are absent here.
- **Size bound.** When `#cache` would exceed `C.TIP_CACHE_MAX` (128) entries, both maps are wiped
  before the insert. This keeps memory bounded on a long AH browsing session.
- **Invalidation.** `T:Invalidate()` replaces both maps with fresh tables (`T._gen = T._gen + 1`). It is called:
  - on `HOLDINGS_CHANGED`, for any holder (the Reconciler is the one sender: Reconciler.lua:741, :939, :954);
  - on `SETTINGS_CHANGED` with reason `ledger` or `profile` (trackLedger can flip);
  - in `T:Disable()`.

  The live overlay is never cached, so the player's own bag changes need no event: they are read
  again on the next post call. Others' counts change only on a flush, and a flush never runs in
  combat (Reconciler.lua:794-797), so a stale cache entry in combat is impossible.

### 5.3 Composing a call: the live overlay

`T:Item(itemID)` and `T:Currency(currencyID)` return `total, rows, n`. `rows` is a module-level scratch
array of reused output tables, valid until the next call; every caller copies or paints it before
calling again. Output row: `{ holder, isMe, isWarband, classFile, count, containers, staleContainer, staleAt }`.
`containers` is a reused per-output-row table, or nil for currencies.

Items:

1. `bags, bank, account = NS.Compat.LiveItemCounts(itemID)`: one call, three or four client reads.
2. For each cached row, write the output containers:
   - **me**: `bags` = the live bags (else stored); `bank` = `resolve(bank, stored.bank, R:IsReadable("bank"))`;
     `equipped`, `mail` and `auctions` = stored.
   - **§warband** (Retail only, `C.FEATURE.warbandBank`): `tabs` = `resolve(account, stored.tabs, R:IsReadable("tabs"))`.
   - **everyone else**: stored, unchanged.
3. `count` = the sum of the containers. Rows with a count of 0 are dropped.

`resolve(live, stored, readable)` is the zero-suspect rule:

```
live == nil                          -> stored                (no API, secret, Forever)
readable                             -> live                  (at the banker the client is authoritative)
live == 0 and (stored or 0) > 0      -> stored                (the client has not loaded that bank this session;
                                                               mirrors ruling R8's bank guard, Reconciler.lua:96-99)
otherwise                            -> live
```

`NS.Reconciler:IsReadable` is read at call time. With the ledger off the tally never runs (section
6.1), so a Reconciler with its capture down is never asked.

**D2 vs the mockup.** D2 lists the warband bank among the live reads. The mockup's prose says "the
Warband reads from the holdings ledger". This design does both: the Warband line *is* the store's
`§warband` entry, and only its `tabs` column is overlaid by the live diff, with the store as the
fallback. Bank and warband contents change only at a banker, so away from one the two answers agree
whenever the client has the data. The live read wins only where it knows more, for example a warband
bank changed from another PC. This is a recorded best-judgement call, not an open question.

Currencies:

- `q = NS.Compat.CurrencyQuantity(id)`.
- If `NS.Compat.CurrencyIsAccountWide(id)`, the live holder is `§warband`, matching
  `Scanner.ScanCurrencies`' split (Scanner.lua:48-56). Otherwise it is me.
- The live holder's count = `q` when non-nil, else stored. Other holders keep their stored counts.

### 5.4 Staleness

- `DAY = 86400`, the Holdings tab's rule (HoldingsTab.lua:21 and :447).
- For each output row, consider the containers whose value came **from the store**:
  - for a character: `bags`, `equipped`, `bank`, `mail` and `auctions`;
  - for `§warband`: `tabs`.

  A live-overlaid container is never stale. Among those containers, take the one with the oldest
  `scanned[c]` timestamp at or past `now - DAY`. Its name goes in `staleContainer` and its timestamp
  in `staleAt`. A container with no scan at all ("never") is not reported: a partial holder stays
  the Holdings tab's concern, which keeps the block short.
- At most one stale container per line.
- Only this unit is shown, from `NS.HoldingsTab.FormatAge(staleAt, now)` read at call time. At or
  past one day it always reads `N d`.
- Currencies: the row is stale when `scanned.currency` is at or past one day old and the row is not
  the live holder. `staleContainer = nil`, and the age alone is drawn.

### 5.5 Sorting

Characters first, by `count` descending and then `holder` ascending. `§warband` goes last, as in
`Holdings:Holders()` (Holdings.lua:141-149). The sort runs in place on the scratch array with one
comparator defined at file scope (no closure per call).

### 5.6 Allocation discipline

- A cache hit allocates nothing.
- A miss allocates the entry and its rows once.
- Output rows and their `containers` tables are pooled by index in the scratch array and cleared with
  a fixed key loop over `C.Container`, never `wipe` plus re-add.
- No string concatenation happens in the tally.

## 6. The tooltip block (`modules/HoldingsTip.lua`)

### 6.1 The guard ladder, cheapest first

```lua
local function onTooltip(tip, data, kind)            -- kind: 1 = item, 2 = currency
  if NS.IsStoodDown() then return false end           -- disabled, or any hold (perf capture included)
  if not cfg.active then return false end             -- settings.tooltip.enabled and trackLedger ~= false (D3)
  if not Compat.TooltipWritable(tip) then return false end
  if Compat.IsComparisonTooltip(tip) then return false end
  local id = kind == 1 and Compat.TooltipItemID(data) or Compat.TooltipCurrencyID(data)
  if not id then return false end                     -- secret or absent id: nothing is written
  local mark = kind == 1 and id or -id                -- one weak map, no allocation
  if shownOn[tip] == mark then return false end       -- NEVER TWICE per show
  if cfg.modifier ~= "none" and not Compat.ModifierDown(cfg.modifier) then return false end
  ... tally, rows, paint ...
  watch(tip); shownOn[tip] = mark
  return true
end
```

- `Compat` here means `NS.Compat`, read at call time (H1).
- `cfg` is one module-level table: the hot-path upvalue cache (events-frames-taint-§7), refreshed by
  `HT:RefreshConfig()` on `Enable` and on `SETTINGS_CHANGED` with reason `tooltip`, `ledger` or
  `profile`. `cfg.active = s.tooltip.enabled ~= false and s.trackLedger ~= false`.
  `cfg.cfgVer` increments on every refresh.
- **Never twice.**
  - `shownOn` is a weak-keyed map. `watch(tip)` hooks, once per tooltip, `OnHide` and (when
    `HasScript("OnTooltipCleared")`) `OnTooltipCleared`, both clearing `shownOn[tip]`.
  - The `watched` set is weak-keyed too.
  - The client's own refresh (clear, then refill, about 5 a second) writes the block again. A repost
    with no clear writes nothing.
  - This is DropWatcher's pattern (ItemSearchTip.lua:1293-1336).
- **Re-entrancy.** `HT.OnTooltip(tip, data, kind)` wraps `onTooltip` in a `busy` flag and `pcall`, and
  re-raises after it releases the flag. A post call that arrives while one runs (another addon's
  scan tooltip filled from inside ours) writes nothing. This is DropWatcher's pattern
  (ItemSearchTip.lua:1344-1366).
- **Perf.** `local Perf = NS.Perf` at file load. Shape A (performance-§2) around the whole
  `HT.OnTooltip` body:

  ```lua
  local t0 = Perf.on and debugprofilestop()
  ...
  if t0 then Perf.Note("tooltipBlock", debugprofilestop() - t0) end
  ```

### 6.2 Rows

The block is painted through `NS.Compat.AppendTooltipRows(tip, rows, n)` from a reused scratch array:

1. A spacer: `{ left = " " }`.
2. The header: `{ left = NS.BRAND, lt = "gtip.title" }`. `NS.BRAND` is "Ka0s Loot History".
3. One row per tally output row, after filtering:
   - `cfg.warband == false` drops the `§warband` row. That includes an account-wide currency, whose
     block is then empty and not drawn.
   - **Left: the name.**
     - `§warband` uses `C.ACCOUNT.holder` ("Warband" on Retail, "Account" on Forever) in the meaning
       color `sem.warbandAlt`, as the Holdings tab does (HoldingsTab.lua:326). It is passed as
       `lr, lg, lb` from `NS.SkinRGB`.
     - A character uses its short name, `holder:match("^[^-]+")` (Analytics.lua's `shortChar` rule;
       a Forever key has no hyphen and stays whole). When two rows in the same block share a short
       name, both show their full key, so alts with one name on two realms never merge.
     - Color: `NS.Compat.ClassColor(classFile)`, else the `gtip.body` token. `classFile` may be
       missing for an old holder (Reconciler.lua:737 stamps it only on that character's own flush).
   - **Right**, colored `gtip.value`:
     - `cfg.containers` on, items: for each container in `ORDER` with a count above 0, the icon
       markup then `Compat.FormatCount(n)`, joined by two spaces. `ORDER` is `bags, equipped, bank,
       mail, auctions`, plus `tabs` where `C.FEATURE.warbandBank`, the Holdings tab's order
       (HoldingsTab.lua:16-17).
     - `cfg.containers` off, or a currency: `Compat.FormatCount(count)`.
     - When stale, append two spaces, then
       `Compat.TooltipTint("gtip.muted", mutedIcon(staleContainer) .. " " .. HT.FormatAge(staleAt, now))`.
       For a currency there is no icon.
4. **The Total row**, `{ left = "Total", lt = "gtip.title", right = FormatCount(sum of the shown rows' counts), rt = "gtip.value" }`.
   It is added when at least one holder row is shown and either `cfg.totalMin2 == false` or two or
   more holder rows are shown.

No holder rows means no block: not even the header is written, and the tooltip is not touched.

The mockup writes the stale age as a word ("bank 3 d"). D4 rules out words for containers, so the
age is drawn as the container's icon, tinted `gtip.muted`, followed by the age. That keeps D4 and the
mockup's intent of a dim age per stale container.

### 6.3 The replay fast path

The client rebuilds a hovered item tooltip about 5 times a second, which is the cost that matters.
The entry (section 5.2) memoizes its last painted lines:

- `sig` is the live tuple: `bags`, `bank`, `account` for items, `q` for currencies.
- `cfgVer` is the settings version.
- `tintSig` is the `gtip.value` r, g, b triple. A skin switch changes it, so no skin message is
  needed (tokens are read at call time, skinning-§9).
- `now` is bucketed to the minute, so ages roll over.
- `lines` and `nLines` hold the left, right, color and token fields of the row tables last built.

When all four signatures match, the post call repaints `lines` as they are: no tally composition,
no concatenation, only the `AddLine` / `AddDoubleLine` calls. Any mismatch rebuilds the lines and
stores the new signatures.

Icon markup is built once per tint. `HT._icons[container]` and `HT._mutedIcons[container]` hold
`NS.IconMarkup(C.TIP_ICONS[c], C.TIP_ICON_FALLBACK, C.TIP_ICON_SIZE, r, g, b)`, rebuilt when the
`gtip.value` or `gtip.muted` triple changes.

### 6.4 Icons (D4)

`C.TIP_ICONS` (Game-icons, CC BY 3.0; the names the mockup lists, each verified present at LibKa0s
`v1.118.0` under `LibKa0s/media/icons/game-icons/`):

| Container | Catalog name |
|---|---|
| `bags` | `gi:knapsack` |
| `equipped` | `gi:chest-armor` |
| `bank` | `gi:bank` |
| `mail` | `gi:envelope` |
| `auctions` | `gi:gavel` |
| `tabs` (Retail) | `gi:locked-chest` |

- `C.TIP_ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"`. It exists on both clients and
  falls in the texture gate's allowed `interface/icons/` category.
- `C.TIP_ICON_SIZE = 12`. The marks are white catalog art tinted from tokens, never from literals.
- `gi:locked-chest` is declared on both clients. The vendor gate is per repo, not per client, and
  Forever never draws it because `ORDER` has no `tabs` there.

**Declaration and vendoring**, in the same commit as the first draw (D4, library-stack-§7):

1. In `CLAUDE.md` line 61, append, keeping Open Iconic alphabetical and the `gi:` group sorted after it:
   `…, unlock, volume-high, gi:bank, gi:chest-armor, gi:envelope, gi:gavel, gi:knapsack, gi:locked-chest.`
2. The vendored folder is already pruned, and the sibling checkout is one commit past the tag, so
   re-copy from the **tag** and prune with the **tag's** tool:

   ```
   S=<scratchpad>/lk-v1.118.0 && mkdir -p "$S"
   git -C ../LibKa0s archive v1.118.0 LibKa0s/media/icons tools testkit | tar -x -C "$S"
   rm -rf libs/LibKa0s/media/icons && cp -r "$S/LibKa0s/media/icons" libs/LibKa0s/media/icons
   lua "$S/tools/prune-icons.lua" .
   ```

   The prune refuses an unknown name and then deletes nothing. It keeps
   `game-icons/LICENSE-game-icons.txt` and `game-icons/AUTHORS.txt`, because a `gi:` icon is declared.
   `media/sounds/` is not touched: no sounds line means none, and the vendored copy already holds none.
3. Add to the README Credits: "Container icons in the tooltip come from [game-icons.net](https://game-icons.net)
   (CC BY 3.0) by their authors listed in `libs/LibKa0s/media/icons/game-icons/AUTHORS.txt`, changed
   from the original: rasterized and recolored white." This is a MUST for Game-icons (DropWatcher
   README.md:142 is the precedent wording).
4. `tests/test_vendor_sync.lua` must pass, and smoke ICON-8 must pass in game. An undeclared name
   draws blank with every suite green, so the smoke row is the only witness.
5. EOL: restore `CLAUDE.md` and every text file written through tools after the commit
   (`rm <path> && git checkout -- <path>`, project memory), then re-run the gate.

Also add "the holdings tooltip's six container marks" to the `CLAUDE.md` sentence that lists the
marks the addon passes in.

### 6.5 Install and lifecycle

- `HT:Enable()`:
  - creates `__ev` and registers `SETTINGS_CHANGED`;
  - calls `RefreshConfig()`;
  - on first use only (`_hooked` latch), `NS.Compat.HookTooltipType("Item", fnItem)` and
    `NS.Compat.HookTooltipType("Currency", fnCur)`;
  - records `self._hookedItem` and `self._hookedCurrency` for diagnostics and tests.
- `HT:Disable()`:
  - unregisters `__ev` (`UnregisterAllMessages`, then nil);
  - clears `shownOn` and the memo (`HT._icons = {}`);
  - leaves the hooks in place. They cannot be removed, and their bodies return at the `IsStoodDown`
    rung.
- `fnItem = function(tip, data) HT.OnTooltip(tip, data, 1) end` (and `2` for currencies) are defined
  once, at file scope.

## 7. Settings

### 7.1 Defaults (`defaults/Profile.lua`, under `settings`)

```lua
-- The holdings block in item and currency tooltips (#34). New keys with defaults: AceDB merges them
-- into every existing profile, so no migration is owed.
tooltip = { enabled = true, containers = true, warband = true, totalMin2 = true, modifier = "none" },
```

### 7.2 Rows (`settings/Schema.lua`)

The five rows sit directly after the `settings.sim.stepDelay` row (the last `Interface` row) and
before the `-- ── General ▸ History ──` block. All are `page = "General"`, `group = "Tooltip"`, with
no `subgroup` (one subject, so options-ui-§7 asks for no headings). They are declared in this order,
so they pair two per line:

| Path | Type / widget | Default | Label | Tooltip |
|---|---|---|---|---|
| `settings.tooltip.enabled` | `bool` / `CheckBox` | `true` | Show holdings in item and currency tooltips | "List who on your account holds the item or currency under the mouse, and how many. Needs Track holdings and losses." |
| `settings.tooltip.containers` | `bool` / `CheckBox` | `true` | Show where each holder keeps it | "Split each holder's count into bags, equipped, bank, mail and auction house" .. (`C.FEATURE.warbandBank` and ", and the warband bank" or "") .. ", each shown as an icon and a count. Needs Track holdings and losses." |
| `settings.tooltip.warband` | `bool` / `CheckBox` | `true` | "Include the " .. `C.ACCOUNT.holder` | "Add a line for what your " .. `C.ACCOUNT.holder:lower()` .. " holds" .. (warbandBank and ": the warband bank and account-wide currencies" or ": account-wide currencies") .. ". Needs Track holdings and losses." |
| `settings.tooltip.totalMin2` | `bool` / `CheckBox` | `true` | Show the Total only with 2 or more holders | "Off: a Total line closes every block, even with one holder. Needs Track holdings and losses." |
| `settings.tooltip.modifier` | `string` / `Dropdown`, `values = C.TOOLTIP_MODIFIER_OPTIONS`, `solo = true` | `"none"` | Only while holding | "Show the block only while this key is held. None: always. Needs Track holdings and losses." |

- `C.TOOLTIP_MODIFIER_OPTIONS = { { value = "none", text = "None" }, { value = "shift", text = "Shift" }, { value = "ctrl", text = "Ctrl" }, { value = "alt", text = "Alt" } }`.
  This is the ordered-array shape (Constants.lua:248-253): `text`, not `label`.
- Every row's `onChange` is `if NS.bus then NS.bus:SendMessage(NS.MSG.SETTINGS_CHANGED, "tooltip") end`.
  That adds one new reason string, `tooltip`.
- Every default is `PD.settings.tooltip.<x>` (savedvariables-§2, architecture-§5). The CLI path comes
  free: `/lh set settings.tooltip.modifier shift`.

### 7.3 The tab

- `settings/Panel.lua` `GENERAL_TABS` gets `{ key = "Tooltip" }` between `{ key = "Interface" }` and
  `{ key = "History" }`.
- The strip becomes: Master controls, Capture, Filters, AH price, Interface, **Tooltip**, History,
  Skin, Keybindings. That is nine tabs (section 14).
- Each row's label is sentence case (options-ui-§21). "Warband" and "Account" are the game's proper
  nouns.

### 7.4 Tests that pin rows and tabs

- `tests/test_schema.lua`:
  - `PARTITION` inserts `{ "Tooltip", 5 }` after `{ "Interface", 5 }`.
  - `NUMBER_WORD` gains `thirty-four` to `forty`.
  - The row total moves from 33 to **38**.
- `tests/panel_support.lua` `STRIP` inserts `Tooltip` after `Interface`. Then `tests/test_panel.lua`'s
  "whole strip, in order" and "every schema group has a tab" cases pass.
- The doc count claims (`COUNT_CLAIMS`) all become thirty-eight, or 38 where the doc writes a numeral
  (section 12).

## 8. Public API v1 (`modules/HoldingsAPI.lua`)

### 8.1 Publication

```lua
local addonName, NS = ...
NS.API = NS.API or {}
NS.API.v1 = NS.API.v1 or {}
local api = NS.API.v1
-- ... members ...
rawset(_G, addonName, { API = NS.API })   -- public-api: only `API`, never NS or NS.API itself
```

- `rawset` needs no `.luacheckrc` entry. `core/LauncherSetup.lua:164` is the precedent.
- The global is SETUP. It survives a stand-down; its answers go empty instead (section 8.4).
- Nothing else is ever published at `_G.LootHistory` (architecture-§1).

### 8.2 Functions, all dot-called

| Signature | Returns |
|---|---|
| `api.Version()` | `1` (`C.API_VERSION`), always, even while unavailable. |
| `api.IsAvailable()` | `true` when the addon is up and the ledger is on (section 8.4). |
| `api.Holders()` | A new array of holder keys from `SavedStore()`: characters sorted ascending, then `"§warband"` last when present. `{}` while unavailable. |
| `api.HolderInfo(holder)` | `{ name, realm, class, isWarband, isCurrent, lastSeen, partial }` or nil. `name` and `realm` split at the first `-` (Retail `"Name-Realm"`); on Forever `realm = nil` and `name` = the key. For `§warband`: `name = C.ACCOUNT.holder`, `realm = nil`, `isWarband = true`. `class` = `meta.classFile` (may be nil). `lastSeen` = `meta.lastSeen`. `partial` = `meta.partial == true`. nil for an unknown holder, a non-string, or while unavailable. |
| `api.ItemCount(itemID)` | `total, perHolder`, where `perHolder = { [holder] = { [container] = n } }`. Only nonzero containers appear, the container keys are `C.Container`'s values, and every holder is included (the tooltip's Warband toggle does not apply). Live overlay as in section 5.3. While unavailable, or for a non-number id: `nil, {}`. An id nobody holds: `0, {}`. |
| `api.CurrencyCount(currencyID)` | `total, { [holder] = n }`. The same rules. |
| `api.Money(holder)` | Copper. With `holder` nil: the sum over every holder. The current character reads `NS.Compat.GetMoney()` live. `§warband` reads `NS.Compat.GetWarbandMoney()` live when non-nil, else stored. Others are stored (`e.money or 0`). nil for an unknown holder or while unavailable. |
| `api.Holdings(holder)` | A deep copy, `{ items = { [itemID] = { [container] = n } }, currency = { [id] = n }, money = copper, links = { [itemID] = link }, scanned = { [container] = ts }, meta = { genesis, partial, completeAt, lastSeen, classFile } }`. Stored values only, with no live overlay: it is a snapshot of the ledger. `escrow` and `meta.bankSlots` are internal and are left out. nil for an unknown holder or while unavailable. |
| `api.Scanned(holder)` | A copy of `e.scanned` (`{ bags = ts, bank = ts, …, money = ts, currency = ts }`), or nil. |
| `api.RegisterCallback(owner, "HoldingsChanged", fn)` | CallbackHandler semantics: `fn` is a function or a method name on `owner`. It is called as `fn(event, holder)`. `holder` is the holder key that changed, or nil for "everything may have changed" (availability flipped). |
| `api.UnregisterCallback(owner, "HoldingsChanged")` | CallbackHandler semantics. |

The "every answer is a copy" rule, as tested:

- Every table returned is freshly allocated.
- No returned table is, or contains, a table reachable from `db.global.holdings`, the tally cache or
  the scratch arrays.
- A consumer writing into an answer changes nothing the next call returns.

### 8.3 The callback relay

- **Binding.** `HoldingsAPI._BindCallbacks()` is idempotent and runs at file load. It resolves
  `LibStub("CallbackHandler-1.0", true)`. When present, it calls
  `CBH:New(api, "RegisterCallback", "UnregisterCallback", false)`, which embeds the two methods into
  `api` and keeps `HoldingsAPI._registry`.
- **Degraded.** When CallbackHandler is absent (the headless default: the loader skips `libs\`, and the
  kit's LibStub has no CallbackHandler entry), `api.RegisterCallback` and `api.UnregisterCallback` are
  no-op functions that return false, so the v1 shape is the same on both arms. This is the
  testing-§8 degraded arm: a real partial load, not a stub planted by a test. The suite loads
  `libs/CallbackHandler-1.0/CallbackHandler-1.0.lua` through the mock LibStub's real `NewLibrary`,
  then calls `_BindCallbacks()` for the live arm.
- **The receiver.** `HoldingsAPI:Enable()` creates `__ev` and registers two messages:
  - `NS.MSG.HOLDINGS_CHANGED` → `if not NS.Sim:IsActive() then fire(holder) end`. A simulation's
    flushes concern its session store, which the API never reads.
  - `NS.MSG.SETTINGS_CHANGED` → for `ledger` or `profile`, `fire(nil)` when `IsAvailable()` differs
    from the last answer seen.
- `fire(h)` is `HoldingsAPI._registry and HoldingsAPI._registry:Fire("HoldingsChanged", h)`.
  `CallbackHandler.Fire` is not `NS.bus:SendMessage`, so the Reconciler stays the one sender of
  `HOLDINGS_CHANGED` (architecture-§4), and this module is one more receiver.
- `Enable` and `Disable` each `fire(nil)` once, so consumers re-query across a stand-down.
- `Disable` unregisters `__ev`. Third-party registrations stay on the registry, and they go quiet
  because the relay is down.

### 8.4 Availability

`available = not NS.IsStoodDown() and not NS.AddonIsOff() and trackLedgerOn()`.

- `trackLedgerOn()` is `s ~= nil and s.trackLedger ~= false` on `NS.db.profile.settings`.
- `trackLedger` is **per profile** while holdings are account-wide, so the answer can differ by the
  logged-in character's profile. The contract says so.
- A perf capture (any hold) also reads unavailable.

### 8.5 The `docs/ARCHITECTURE.md` contract section

Add a new `## Public API (v1)` section after `## Slash commands`. It covers:

1. The access path, `local api = LootHistory and LootHistory.API and LootHistory.API.v1`, and the
   version rule: semver-stable, and a break ships as `v2` beside `v1` (public-api).
2. The function table from section 8.2, with every return shape.
3. Copies only: what a consumer may and may not rely on.
4. Live versus stored: which holder and container come from where, and the zero-suspect fallback.
5. Availability: disabled, perf capture, `trackLedger` off, and the fact that the setting is per profile.
6. `HoldingsChanged`: payload, when it fires (once per changed holder after a flush, nil on an
   availability flip, never during `/lh sim`), and that the logged-in character's own bag moves fire
   after the Reconciler's debounced flush, never mid-combat.
7. The holder keys: `"Name-Realm"` on Retail, `"First Surname"` on Forever, and `"§warband"`.
8. Client notes: no `tabs` container on Forever, and the account holder named "Account" there.

## 9. Disabled state, perf, taint and per-client posture

### 9.1 Disabled state (slash-commands-§7)

- `STAND_DOWN_STEPS` adds `method("HoldingsTally", "Disable"), method("HoldingsTip", "Disable"),
  method("HoldingsAPI", "Disable")` directly after `method("Rollup", "Disable")`.
- `STAND_UP_STEPS` adds `method("HoldingsTally", "Enable"), method("HoldingsTip", "Enable"),
  method("HoldingsAPI", "Enable")` directly after `method("Timeline", "Enable")`.
- Three new receivers, each on its own target, are all actually unregistered on stand-down. Their
  message names are already in `OWNED`; the per-target assertion is in each new suite and in
  `featureTargets()`.
- **The hooks are the third one-way funnel.** `AddTooltipPostCall` and the `OnHide` /
  `OnTooltipCleared` `HookScript`s have no removal. They are the rule's "hook that cannot be undone",
  so each body gates itself on `NS.IsStoodDown()` first.
  - The `HookScript` bodies only clear a weak mark. They draw nothing and write nothing, so they
    have no gate.
  - The `core/LifecycleSetup.lua` header (lines 41-45), `docs/disabled-state.md`, and
    ARCHITECTURE's *The disabled state* and *Taint notes* each name this third funnel next to the two
    `hooksecurefunc` funnels.
- **Not a `HOOK_ROWS` row.** HOOK_ROWS is the capture seam: the simulator replays it, and
  `test_dispatch.lua` pins 18 rows with owners `Attribution,AttributionOut`.
- **No SavedVariables writes.** Nothing in this feature writes SavedVariables.
- **What survives.** `_G.LootHistory` survives as setup, and its answers go empty.

### 9.2 Perf (performance-§2, §3)

- `core/PerfSetup.lua` `buckets` appends
  `{ key = "tooltipBlock" },   -- HoldingsTip.OnTooltip (every item/currency tooltip build, ~5/s while hovered, in combat too)`.
- `BUCKET_ORDER` becomes `lootLine,currencyLine,moneyLine,spellCast,ledgerEvent,tooltipBlock`.
- `tests/test_perf.lua` updates the literal, and its `exercise()` drives one item post call through
  the double so the bucket is reached.
- `docs/combat-path-sweep.md` gains a "Hooks and post calls" census row. A post call runs in combat,
  and the sweep says that needs a bucket.
- `docs/performance.md` *The buckets* gains a row.
- `tests/perf.lua` adds an offline scenario: a 200-holder store, 1000 `T:Item` cold builds and 1000
  warm replays. It is recorded, not gated.

### 9.3 Taint and secrets (events-frames-taint-§3, §8; client-quirks-§5 Q17, Q18)

- Observe by post call; never replace a Blizzard function. No MoneyFrame.
- Read only `data.id` and `data.hyperlink`, each through `Compat.IsSecret` first. Line text is never
  read, compared or concatenated.
- `tip:Show()` after appending is what Blizzard's own post calls do. GameTooltip is not a protected
  frame, so this is legal in combat.
- The block never calls `SetOwner` or `PlaceTooltip` and never restyles the backdrop. ARCHITECTURE's
  *Tooltip placement* → *Left as they are* gains "the holdings block appended to any item or currency
  tooltip (#34): it places nothing."
- Enum members are resolved by name (`Enum.TooltipDataType[typeName]`).

### 9.4 Per-client (clients-§3, §4, §6)

- No new `C.FEATURE` key. The warband split rides `C.FEATURE.warbandBank`:
  - `ORDER`'s `tabs` and `gi:locked-chest` draw;
  - `LiveItemCounts`' `account` part;
  - the `tabs` overlay;
  - the `containers` and `warband` tooltips' wording.
- ARCHITECTURE *Per-client features*: the `warbandBank` row's text adds "the holdings tooltip's
  warband-bank icon, live count and wording". Its *Gated in* list adds `modules/HoldingsTip.lua`
  (`ORDER`), `modules/HoldingsTally.lua` (the overlay), `core/Compat.lua` (`LiveItemCounts`) and
  `settings/Schema.lua`. `tests/test_client_shape.lua` keeps checking that the row names the feature.
- The account holder and the "Include the Account" row serve both clients through `C.ACCOUNT`.

## 10. Standards that bind this design

- **public-api** (one section): `NS.API.v1`; `_G[addonName] = { API = NS.API }` via `rawset`; the v1
  contract in ARCHITECTURE.md; semver-stable, with v2 as a sibling.
- **architecture-§1**: nothing but the public-api wrapper at `_G[addonName]`.
- **architecture-§4**: closed bus; no new message; one sender of `HOLDINGS_CHANGED`; each receiver on
  its own target; the bus docs list every consumer.
- **architecture-§5**: the schema row is the single source of truth for the five settings.
- **savedvariables-§2**: defaults are declared once, in `defaults/Profile.lua`.
- **compat** (the firewall), plus this repo's H1/H2 sim-seam contract: every client read in
  `core/Compat.lua`, read at call time, classified in `CLASSIFIED`.
- **clients-§3**: no client detection outside Compat. **clients-§4**: the warband split is gated by
  `C.FEATURE.warbandBank`. **clients-§6**: both kit profiles are green, with presence and absence
  tested.
- **client-quirks-§5** (Q17 secret tooltip text, Q18 enum by name).
- **slash-commands-§7**: total stand-down; the one-way hook carve-out with gated bodies; the
  conformance suite.
- **events-frames-taint-§3** (post-hook, never replace), **§7** (hot-path upvalue cache), **§8**
  (secret values never compared unguarded).
- **performance-§2** (Shape A, `Perf` as a load-time upvalue, no allocation while dormant) and
  **§3** (every bracket has a declared bucket, in order, reached in the suite).
- **skinning-§1 / §9**: every color from `gtip.*` or `sem.*` tokens at call time; no typed literal
  (kit `test_skin_values`); icon tints from tokens.
- **library-stack-§7**, the icon subset: declare, vendor only what is declared, attribution travels
  with the set, README credit (a MUST for Game-icons). **library-stack-§8**: catalog art first, with a
  Blizzard fallback under every call.
- **standalone-windows**, *Tooltip placement*: an appended block owns no placement.
- **options-ui-§13** (one tab per group, a tab holds at least two lines, at most eight tabs is a
  SHOULD: see section 14), **§15** (Master controls stays first), **§21** (sentence case).
- **layout-§1**: every file under 1500 lines; the feature is three new modules rather than growth of
  `Holdings.lua` or `HoldingsTab.lua`.
- **lint**: luacheck 0/0; one `read_globals` addition; no top-level ignore.
- **testing-§8** (the degraded arm from a real partial load), **§12** (each case can fail: the double
  models clear and refill), **§15** (bounded runs).
- **documentation-§3**: the docs hub, the count claims and the documentation map kept in step.

## 11. Test plan

Characterization comes first wherever existing code changes. Each pin below is written, and seen
green against today's code, before the change lands.

**Characterization, before the changes**

- `test_holdings.lua`:
  - `ActiveStore` answers `testHoldings` while test mode is on.
  - `Store` answers the sim table while `NS.SimStores.holdings` is set.

  Then the new `SavedStore` case: it answers `db.global.holdings` in **both** of those states.
- `test_analytics*`: the class color of a known class and of a missing class, pinned before
  `AnalyticsFormat` moves its `RAID_CLASS_COLORS` read to `Compat.ClassColor`.

**`tests/mock_tooltip_data.lua`**, the double:

- `TooltipDataProcessor.AddTooltipPostCall(type, fn)`, keeping the fns per type with no removal.
- `Enum.TooltipDataType = { Item = 0, Currency = 25 }`, with each member removable per case.
- Named stand-in tooltips: `GetName`, `AddLine`, `AddDoubleLine` (recording
  `__lines { text, right, r, g, b, rr, rg, rb }`), `NumLines`, `ClearLines`, `Show`, `IsForbidden`,
  `HookScript`, `HasScript`.
- Drivers:
  - `show(tip, type, data)`: clear, fire `OnTooltipCleared`, write a client line, run the post calls;
  - `refresh` (clear and refill);
  - `repost` (no clear);
  - `hide` (`OnHide`).

**`test_compat_tooltip.lua`**, on both profiles:

- `HookTooltipType`:
  - true for Item and Currency;
  - false with no `TooltipDataProcessor`, with no `Enum.TooltipDataType.Currency`, and with a
    non-function fn.
- `TooltipItemID` and `TooltipCurrencyID`: the id from `data.id`; from a hyperlink; nil for a secret
  id (via the kit's secret double); nil for a secret hyperlink; nil for a non-table.
- `TooltipWritable`: false when forbidden and false without `AddLine`. `IsComparisonTooltip`: the
  four names.
- `LiveItemCounts`:
  - worn subtraction;
  - the bank diff;
  - account is nil on Forever and while the feature is off;
  - a secret count gives nil for that part.
- `CurrencyQuantity`. `ModifierDown`: each key.
- `AppendTooltipRows`:
  - colors equal `NS.Skin.Color(token)`;
  - a meaning color passes through;
  - `Show` is called;
  - it never calls `SetOwner`.
- `TooltipTint`: built from the token's components. `FormatCount` with and without `BreakUpLargeNumbers`.

**`test_holdings_tally.lua`**

- Three characters and the warband, with items in several containers. Expect: per-holder counts,
  per-container splits, sort order, `§warband` last, and zero holders dropped.
- Base-itemID: a stored base id matches the tooltip id.
- Live overlay:
  - my bags come from `LiveItemCounts`;
  - my bank comes from live when readable;
  - live 0 with stored 5, away from the bank, reads 5 (zero-suspect);
  - live 7 with stored 5, away from the bank, reads 7;
  - equipped, mail and auctions always come from the store;
  - `tabs` is overlaid on Retail and untouched on Forever.
- Currencies: a character currency goes live on me; an account-wide one goes live on `§warband`.
- Staleness:
  - a stored container 3 days old gives `staleContainer = "bank"` and the age `3 d`;
  - a live-overlaid container is never stale;
  - a never-scanned container is not reported;
  - with two stale containers, the oldest wins.
- Cache:
  - a second call allocates no entry (the same entry table);
  - `HOLDINGS_CHANGED` wipes it;
  - `SETTINGS_CHANGED("ledger")` wipes it;
  - the cap of 128 wipes it;
  - `Disable` wipes it.
- The saved store only: test mode on, or a sim store set, gives the same answer as off.
- The target: `__ev` is registered while up and nil after `Disable`.

**`test_holdings_tip.lua`**

- An item block:
  - spacer, header (`gtip.title`), holder lines and Total, in order;
  - class color, with the fallback `gtip.body` when `classFile` is missing;
  - the Warband word and `sem.warbandAlt`;
  - icons drawn with `NS.IconMarkup` and the `C.TIP_ICONS` names.
- A currency block: plain numbers and no icons.
- The Total rule:
  - one holder with `totalMin2` on: no Total;
  - one holder with it off: a Total;
  - two holders: a Total.
- `containers` off: one count per holder. `warband` off: no Warband line, and an account-wide
  currency draws no block at all.
- Short names: two `Ann-RealmA` and `Ann-RealmB` rows show their full keys. Under the Forever
  profile, keys stay whole.
- D3: `trackLedger` off gives no lines, and turning it back on brings them back.
- Stood down (`NS.StandDown()`) gives no lines; stood up again, they draw.
- Modifier `shift`: nothing without shift; the block with shift.
- Never twice:
  - a `repost` adds no second block;
  - a `refresh` (clear and refill) draws exactly one fresh block;
  - after `hide`, the next show draws.
- Guards:
  - a forbidden tooltip, a comparison tooltip, a secret id and an absent id each write nothing;
  - a re-entrant post call from inside the paint writes nothing, and an error inside releases `busy`.
- Replay:
  - with unchanged live counts, the second refresh makes no `NS.IconMarkup` call and no tally compose;
  - a changed live count rebuilds;
  - a skin switch (kit `skin_switch`) changes the colors on the next refresh.
- No `SetOwner` or `PlaceTooltip` is called on the tooltip (`tests/tip_spy.lua`).
- Forever profile: `ORDER` has no `tabs`, no `gi:locked-chest` markup is ever built, and "Account"
  replaces "Warband".
- The settings rows: each `onChange` sends `SETTINGS_CHANGED("tooltip")`, and `cfg` refreshes.

**`test_holdings_api.lua`**

- Shape: `_G.LootHistory` has exactly one key, `API`. `LootHistory.API.v1` has exactly the eleven
  function names. `Version() == 1`.
- Every function's return shape, for a known holder, an unknown holder and a bad argument.
- Copies: mutate every returned table, then the next call and `db.global.holdings` are unchanged; no
  returned table is `rawequal` to any store table.
- Live: `ItemCount`'s answer for me equals the tally's. `Money()` sums live and stored.
- Unavailable (stood down, `settings.enabled` false, `trackLedger` false): the documented empty
  answers, with `Version()` still 1.
- The degraded arm (default headless, no CallbackHandler): `RegisterCallback` is a function that
  returns false and raises nothing.
- The live arm (the suite loads `libs/CallbackHandler-1.0/CallbackHandler-1.0.lua`, then
  `_BindCallbacks()`):
  - a registered fn receives `("HoldingsChanged", holder)` on a Reconciler flush and on `ForgetHolder`;
  - nothing during an active sim;
  - `(…, nil)` on a `trackLedger` flip, and on Disable and Enable;
  - nothing after `UnregisterCallback`;
  - the relay never calls `NS.bus:SendMessage`.
- The target: `__ev` is registered while up and nil after `Disable`.

**Existing suites updated**

- `test_sim_seam.lua`: `CLASSIFIED` gains the thirteen members.
- `test_compat_routing.lua`: `BANNED` gains three patterns.
- `test_perf.lua`: `BUCKET_ORDER` and `exercise`.
- `test_disabled.lua`:
  - `featureTargets()` adds `NS.HoldingsTally.__ev`, `NS.HoldingsTip.__ev` and `NS.HoldingsAPI.__ev`;
  - `fillAll` records the three modules;
  - both lifecycle order strings gain the three steps;
  - step 6, "firing every event … draws nothing", also drives an item post call through the double
    and asserts no line.
- `test_schema.lua` and `panel_support.lua`, as in section 7.4.
- `test_constants.lua`: pins `C.TOOLTIP_MODIFIER_OPTIONS`' shape and `C.TIP_ICONS`' six names.
- `test_client_shape.lua`: still green with the edited row.
- `run.lua`: adds `test_compat_tooltip` after `test_compat_client`, `test_holdings_tally` after
  `test_holdings`, `test_holdings_tip` after `test_holdingstab`, and `test_holdings_api` after
  `test_disabled`, because it needs the whole addon up. Every new suite cleans up the double it
  installs.

**Forever profile** (`KA0S_KIT_CLIENT=forever lua tests/run.lua`): every new suite runs, and the
client-specific cases assert:

- no `tabs` and `account == nil`;
- the `"Account"` words and the "Include the Account" label;
- `HookTooltipType("Currency")` false when the double drops the Currency member, with items still
  drawing;
- whole holder keys.

**Gate:** `lua tests/run.lua`, `KA0S_KIT_CLIENT=forever lua tests/run.lua`,
`~/.claude/dev-copilot/bin/ka0s-bounded luacheck .` and `python3 -m pytest -q tools/seeds`, all at 0.
Then the EOL restore, and the gate again.

## 12. Doc updates

- **`docs/ARCHITECTURE.md`**:
  - *Module map*: three modules.
  - *Per-client features*: the `warbandBank` row (section 9.4).
  - *Settings schema*: "Thirty-eight rows ship today", and the strip list with nine tabs.
  - *Message bus* table: `SETTINGS_CHANGED` adds the `tooltip` reason and three consumers;
    `HOLDINGS_CHANGED` consumers become HoldingsTab, Timeline, HoldingsTally (cache) and HoldingsAPI
    (relay).
  - New `## Public API (v1)` (section 8.5).
  - *The disabled state*: the third funnel and the three stand-down steps.
  - *Tooltip placement* → *Left as they are*: one entry.
  - *Taint notes*: post calls and secret-safe id reads.
  - *Documented deviations*: the options-ui-§13 row if the owner rules it (section 14).
- **`docs/module-map.md`**:
  - three module entries;
  - `Schema.lua — 38 rows, one per setting`;
  - "**thirty-eight** rows";
  - both per-tab breakdowns with `Tooltip 5`.
- **`docs/schema.md`** *The rows*: five rows.
- **`docs/settings-panel.md`**:
  - "One sub-page, nine tabs" (lines 5 and 8);
  - the *What each tab covers* table gains a Tooltip row;
  - "**Thirty-eight rows ship today**";
  - the row table.
- **`docs/message-bus.md`**:
  - the table rows (lines 11 and 12);
  - line 46's stale "The one receiver is HoldingsTab" becomes the four receivers;
  - line 49's reason list becomes exact: `enabled`, `quality`, `questfilter`, `ammofilter`,
    `currency`, `excludes`, `ledger`, `view`, `chrome`, `tooltip`, plus `profile` from `AdoptProfile`.
    That fixes the existing drift in the same commit.
- **`docs/disabled-state.md`**: *What stands down* gains three rows; the funnels paragraph names the
  third.
- **`docs/performance.md`** *The buckets*: `tooltipBlock`. **`docs/combat-path-sweep.md`**: the
  hooks and post calls census.
- **`docs/compat-layer.md`**: the new members and their classes.
- **`docs/forever-quirks.md`** *LootHistory-specific quirks*, two open-probe entries:
  - the tooltip post calls (Item, Currency) on Forever;
  - `C_Item.GetItemCount`'s arity and bank behavior on Forever.
- **`docs/smoke-tests.md`**: a new `## Holdings tooltip` section after *Ledger capture*, plus Index
  entries:

  | Id | Check |
  |---|---|
  | **TIP-1** | Hover a bag item held by two characters: the block, class colors, icons and counts, the Total. |
  | **TIP-2** | An item only this character holds: no Total, given the default. |
  | **TIP-3** | A currency, both character and account-wide (Retail: the Warband line). |
  | **TIP-4** | Move a stack from bags to bank at a banker: the counts change live, before any reload. |
  | **TIP-5** | An alt whose bank was read more than a day ago: a dim bank icon and `N d`. |
  | **TIP-6** | The five settings rows each take effect; "Only while holding: Shift". |
  | **TIP-7** | Track holdings and losses off: no block. `/lh disable`: no block. Re-enable: back. |
  | **TIP-8** | The block on AH, chat link, loot window, quest reward, and another addon's tooltip; nothing on the comparison tooltips; no doubled block while hovering for 10 s. |
  | **TIP-9** | Retail: away from the bank after `/reload`, the bank count equals the Holdings tab's (it is not 0). |
  | **API-1** | `/dump LootHistory.API.v1.ItemCount(<id>)` matches the tooltip. |
  | **API-2** | A test addon's `RegisterCallback` fires on a bag move. |
  | **API-3** | `/lh disable`: `IsAvailable()` is false and `Holders()` is `{}`. |
  | **ICON-8** | The six (Forever: five) container marks draw, none blank. |
  | **FOREVER-17** | Item tooltip block on Forever, with counts equal to the bags (probes `GetItemCount`'s arity and its worn and bag-slot counting). |
  | **FOREVER-18** | Currency tooltip block on Forever, or its documented absence. |

- **`docs/test-cases.md`**: regenerate with `lua tests/run.lua --list > docs/test-cases.md`.
- **`README.md`**:
  - features: "Holdings in tooltips: who on your account holds an item or currency, and where", and
    "A public API for other addons (`LootHistory.API.v1`)";
  - Credits: Game-icons (section 6.4);
  - the Tests badge count, from the final run.
- **`CLAUDE.md`**: the icons line and the marks sentence (section 6.4).

## 13. Implementation tasks (plan rows)

Each task ends with the gate green, a commit and the plan ledger row updated in that commit.

**M1.1 — Compat** (`core/Compat.lua`, `core/CompatClient.lua`, `core/SimSeam.lua`, `.luacheckrc`,
`tests/mock_tooltip_data.lua`, `tests/test_compat_tooltip.lua`, `tests/test_sim_seam.lua`,
`tests/test_compat_routing.lua`, `tests/run.lua`, `modules/AnalyticsFormat.lua` and its
characterization pin).

- Proving assertions:
  - every case in `test_compat_tooltip` passes on both profiles;
  - `Unwrapped()` is empty;
  - the `CLASSIFIED` snapshot matches;
  - `BANNED` finds no bare read in `modules/`;
  - the Analytics class-color pin is unchanged.

**M1.2 — Tally** (`modules/Holdings.lua` `SavedStore`, `modules/HoldingsTally.lua`, `LootHistory.toc`,
`tests/test_holdings.lua`, `tests/test_holdings_tally.lua`, `core/Constants.lua` `TIP_CACHE_MAX`,
`core/LifecycleSetup.lua` for the Tally step, `tests/test_disabled.lua` for the Tally step and target).

- Proving assertions:
  - the `SavedStore` characterization;
  - every tally case, including zero-suspect, staleness and cache identity;
  - the lifecycle order strings include `HoldingsTally:Disable` and `:Enable`.

**M1.3 — Tooltip block, settings and icons** (`modules/HoldingsTip.lua`, `LootHistory.toc`,
`core/Constants.lua`, `core/PerfSetup.lua`, `core/LifecycleSetup.lua`, `defaults/Profile.lua`,
`settings/Schema.lua`, `settings/Panel.lua`, `CLAUDE.md`, `libs/LibKa0s/media/icons/`, `README.md`
credits, `tests/test_holdings_tip.lua`, `tests/test_perf.lua`, `tests/test_disabled.lua`,
`tests/test_schema.lua`, `tests/panel_support.lua`, `tests/test_constants.lua`, and the count-claim
docs that `test_schema` reads: ARCHITECTURE, settings-panel, module-map).

- Proving assertions:
  - every `test_holdings_tip` case on both profiles;
  - `tooltipBlock` reached;
  - `PARTITION` 38 with Tooltip 5;
  - `STRIP` with nine tabs;
  - stand-down draws nothing;
  - `test_vendor_sync` green with the new declaration;
  - `test_skin_values` green (no typed color, no literal `|cff`).

**M1.4 — Public API** (`modules/HoldingsAPI.lua`, `LootHistory.toc`, `core/LifecycleSetup.lua`,
`core/Constants.lua` `API_VERSION`, `tests/test_holdings_api.lua`, `tests/test_disabled.lua`,
`tests/run.lua`, `docs/ARCHITECTURE.md` `## Public API (v1)`).

- Proving assertions:
  - the global's shape (one key);
  - eleven functions;
  - copy isolation;
  - both CallbackHandler arms;
  - sim silence;
  - unavailable answers;
  - the relay never sends on the bus.

**M1.5 — Docs** (everything in section 12 not already landed with its code; `docs/test-cases.md` regen;
the README features and badge).

- Proving assertions:
  - `test_doc_structure` green;
  - `test_schema` count claims green;
  - `test_client_shape` green;
  - the smoke Index lists the new ids.

M1.6, the review pass and push, follows the plan as written.

## 14. Deviations to flag (the owner decides)

| Rule | What differs | Why | Options |
|---|---|---|---|
| `options-ui-§13` (SHOULD: at most eight tab labels on a page) | The General strip goes from 8 to **9** tabs with Tooltip, and to 11 once #38's Toasts and #39's Farm land. `settings/Panel.lua:653` calls eight "the budget". | The owner-approved mockup draws a Tooltip tab beside Toasts and Farm. The standard permits a wrapped second row and says it is not a defect, but the SHOULD is still exceeded. | (a) **Accept**: add a register row to ARCHITECTURE *Documented deviations* (`options-ui-§13`, "General holds 9 tabs (11 after M3/M4)", "the mockup's Tooltip / Toasts / Farm tabs; owner ruling 2026-11-27", re-check trigger: "the General page adopts a nav rail, or a tab is merged"), and rewrite the Panel.lua comment. **This design builds (a) and writes the row; it needs the owner's confirmation.** (b) Fold the five rows into Interface as a `subgroup = "Tooltip"`, which keeps eight and departs from the mockup. (c) Adopt `O.NavRail` for General, which is a larger change better done with M3 and M4. |

**Flags, not deviations.** Each is recorded so nothing is decided silently:

- **slash-commands-§7 wording.** The carve-out reads "a hook that cannot be undone", with
  `hooksecurefunc` as its example. `AddTooltipPostCall` and `HookScript` are equally one-way, so this
  design treats them as inside the carve-out and gates their bodies. If the owner reads the rule as
  covering `hooksecurefunc` alone, that is an upstream clarification to the standard, not a change here.
- **library-stack-§7 promotion candidate.** The post-call helpers (install by type name, id readers,
  writable and comparison guards, never-twice marks, re-entrancy guard) now have two consumers with
  the same semantics, DropWatcher and LootHistory. That clears promotion bar 1. D1 keeps them
  host-side in Compat, which is compliant. Recommendation: file a LibKa0s issue during M1.6 rather
  than duplicate a third time.
- **D2 against the mockup's prose.** Resolved in section 5.3: the store is the base, live overlays
  it, and the store is the zero-suspect fallback. No owner action needed unless they disagree.
- **The mockup's "bank 3 d" word.** Rendered as the muted container icon plus the age, to honor D4
  (section 6.2).
- **The `HoldingsAPI` relay and the bus.** It is a receiver that re-fires through its own
  CallbackHandler registry, not a second sender, so architecture-§4 holds.

## 15. Known limitations (to record in ARCHITECTURE *Known limitations*)

- An alt's stored counts are as fresh as its last flush. A bank never visited is not flagged in the
  tooltip; the Holdings tab shows it as partial.
- The live warband-bank and bank diffs depend on the client having the bank data. When it answers 0
  where the store says otherwise, the store wins until the next banker visit.
- Forever's post-call types and `GetItemCount` arity are assumed until FOREVER-17 and FOREVER-18 pass.
- `trackLedger` is per profile: an alt on a profile with the ledger off sees no block, and its API
  answers are empty.
