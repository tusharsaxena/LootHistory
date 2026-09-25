# LootHistory — Proposed Changes (2026-09-23)

The standard these changes were checked against is **Ka0s WoW Addon Standard v2.64.0 (2026-09-23)**.
The index and all 27 section files came from `raw.githubusercontent.com` through `curl`, and they
match the local checkout at `e68795f`. Rule references use the `filename-§N` form.

## HLD — themes

### T1 — Attribution context must end when the situation that caused it ends (F-001, F-002)

The attribution engine has two kinds of state. The single-slot loot context is scoped by a TTL. The
two rolling contexts, keystone and encounter, are scoped by events. Each of those two gets the scoping
wrong, in opposite directions:

- **Keystone** outlives its instance and never ends.
- **Encounter** ends before the loot it was meant to annotate.

**Proposed fix:**

- The keystone gets an explicit end: leaving the challenge-mode instance, or `CHALLENGE_MODE_RESET`.
- The encounter gets a short post-kill grace window, and the grace window reuses the existing TTL
  machinery rather than a new timer.

**Alternatives rejected:**

- **Clearing the keystone on `CHALLENGE_MODE_COMPLETED`.** This breaks the reward-chest attribution
  the code deliberately keeps (`modules/Attribution.lua:236`).
- **Using `PLAYER_ENTERING_WORLD` on the shared `NS.addon` target.** AceEvent keys handlers by
  `(event, target)`, so this would silently replace `addon:OnEnterWorld` (`core/LifecycleSetup.lua:112`).
- **A `NS.After` timer for the encounter grace.** A timer is another thing to cancel on stand-down.
  Storing an `expires` stamp is simpler, and `Attribution:Disable` already clears the state.

### T2 — Capture-time data must not depend on a stale session snapshot (F-003, F-015)

A persisted field should never be written from a cache that cannot see the thing being written. The
currency-category map gets a rebuild on miss. The warbound repair gets an id-from-link fallback.

### T3 — Destructive effects are confirm-gated or deferred, everywhere (F-004, F-014)

The addon already confirm-gates purge and reset-all. Retention-shrink is the one destructive path
without a gate.

**Proposed fix:** keep the setting write immediate, since it is the single write seam
(`architecture-§5`). Move the prune to the existing deferred login prune, or to an explicit confirm,
and print one line saying which.

**Alternative rejected:** a second retention row, `pending`, beside the real one. That is two answers
to one question.

### T4 — Degradation stubs answer honestly and copy nothing (F-005, F-008, F-014)

On the path where the library is absent, the stubs re-spell things the library owns: a refusal line
and two line formatters. `library-stack-§7` bounds what a stub may copy (no formatters, no layout
constants) and anti-pattern #47 bounds what a host may re-implement.

**Proposed fix:** the stubs build their text from the same parts the library uses, or return plain
`tostring` values. No stub carries a library format string.

### T5 — Hoist loop-invariant work out of full-history passes (F-006, F-016, F-018)

`Database:QueryList` already states the rule that loop-invariant work comes out of the loop
(`core/Database.lua:307-313`). `AuctionPrice:Pick`, `accumulateTime` and the collector gate are not
following it yet.

**Proposed fix:** a compiled priority plan refreshed on `SettingsChanged`, following
`events-frames-taint-§7`'s hot-path upvalue pattern, plus a per-day cache inside a single `Stats` pass.

**Alternative rejected:** caching `RecordValue` on the record itself. That would write derived data
into SavedVariables, and it would go stale when the priority changes.

**Measurement:** no offline runner exists, and the `performance-§12` deviation is recorded. The
evidence for this theme is therefore an ad-hoc headless micro-benchmark over a synthetic history,
which is **not committed**, plus the in-client check in 03. Do not claim a figure without its record.

### T6 — Test inventory covers the addon's wiring, not the library's units (F-007)

This is `testing-§8`. It deletes four cases and keeps the integration cases.

### T7 — Hygiene: comments, doc citations and vocabularies (F-009, F-010, F-011, F-012, F-013, F-017)

These are mechanical. None of them changes stored data.

## Upstream change-set

**None.** No finding lives under `libs/` or `tests/_kit/`, and vendor sync is clean. No entry below
targets either path.

## LLD — change-set per finding

### C-001 — End the keystone context on instance exit (F-001) — `modules/Attribution.lua`, `core/Compat.lua`

1. **`core/Compat.lua`:** add a presence-guarded shim.

   ```lua
   -- Is the player inside a 5-player dungeon instance right now? The keystone context is
   -- meaningful only there. False when the API is absent.
   function Compat.InPartyInstance()
     if type(IsInInstance) ~= "function" then return false end
     local inInstance, instanceType = IsInInstance()
     return inInstance and instanceType == "party" or false
   end
   ```

2. **`modules/Attribution.lua`:** add a handler and register it.

   ```lua
   function Attribution:OnZoneChanged()
     if State.keystone and not NS.Compat.InPartyInstance() then
       State.keystone = nil
       if NS.State.debug and NS.Debug then NS.Debug("Attr", "keystone context cleared (left instance)") end
     end
   end
   function Attribution:OnChallengeModeReset()
     State.keystone = nil
   end
   ```

   In `Attribution:Enable`, register `ZONE_CHANGED_NEW_AREA` and `CHALLENGE_MODE_RESET` on `bus`.
   Neither `(event, target)` pair is used anywhere else today; check with
   `grep -rn 'RegisterEvent("ZONE_CHANGED_NEW_AREA"\|CHALLENGE_MODE_RESET' core modules settings`.
   Append both to `self.__events`, so `Disable` unregisters them. This is `slash-commands-§7`: the
   teardown list comes from the registration list and is never typed a second time.

3. **`:238`:** guard against a completion-time `0`.

   ```lua
   local lvl = NS.Compat.GetActiveKeystoneLevel()
   State.keystone.level = (lvl and lvl > 0) and lvl or State.keystone.level
   ```

- **Tests** (`tests/test_attribution.lua`):
  - Add a case: keystone set, `OnZoneChanged` with `InPartyInstance` stubbed false → `State.keystone == nil`.
    Its comment reads `-- red under: an OnZoneChanged that does not clear`.
  - Add the mirror case: stubbed true → kept, so the reward chest still resolves to `MPLUS`.
  - Add a case for `CHALLENGE_MODE_RESET`.
  - Update `:396` `Enable registers seven bus events…` to **nine**. This is an intended count change,
    not a weakened test.
  - `tests/test_disabled.lua`'s registration-set assertions pick up the two new events automatically.
    Confirm that they do.
- **Inventory:** +3 cases. **`docs/test-cases.md` and the README `[tests]` badge move in the same
  commit** (`testing-§5`).
- **Docs:** `docs/data-flow.md:88` and `docs/midnight-quirks.md:22` describe the context's lifetime.
  Update both to say when it ends.
- **Risk:** `ZONE_CHANGED_NEW_AREA` fires inside the dungeon too, for sub-zone moves. The
  `InPartyInstance` guard keeps the context there. Loading out of the instance fires it with a
  non-party instance type. Verify in-client (S-001).
- **Standards:** the new shim lives in Compat, the compat firewall (`compat`). The event is registered
  on the module's existing path and torn down by the same list (`slash-commands-§7`). No new parallel
  teardown.

### C-002 — Encounter grace window (F-002) — `modules/Attribution.lua`

- `OnEncounterEnd(_, encounterID, encounterName, difficultyID, groupSize, success)`:
  - On `success == 1`, keep `State.encounter` and stamp
    `State.encounter.expires = GetTime() + Constants.ENCOUNTER_GRACE`, using a new constant of about
    60 s in `core/Constants.lua`.
  - On a wipe, clear it.
- `ResolveLootSource`: treat `state.encounter` as live when `not e.expires or e.expires >= GetTime()`.
  Keep the function pure by passing `now` in the `state` arg in tests.
- **Tests:** add a case "loot opened after a successful ENCOUNTER_END within grace carries encounterID"
  and one for "after grace, it does not". **+2 cases**, and the badge and inventory move.
- **Alternative, if the in-client check (S-002) shows the loot order is not what F-002 assumes:**
  close F-002 as not-reproduced, and make no code change.

### C-003 — Rebuild the currency-category cache on miss (F-003) — `core/Compat.lua`

```lua
function Compat.CurrencyCategory(currencyID)
  if not currencyID then return nil end
  if not currencyCategoryCache then buildCurrencyCategoryCache() end
  local hit = currencyCategoryCache[currencyID]
  if hit == nil and not currencyCategoryCache.__rebuiltFor then
    buildCurrencyCategoryCache()
    currencyCategoryCache.__rebuiltFor = currencyID   -- one rebuild per miss-burst
    hit = currencyCategoryCache[currencyID]
  end
  return hit
end
```

- A cleaner alternative: nil the cache on `CURRENCY_DISPLAY_UPDATE`. That adds an event registration,
  which then has to join the stand-down list, so the rebuild-on-miss form is preferred. Store the
  sentinel in a local rather than a key if a string key inside an id map feels off.
- **Tests:** `tests/test_compat.lua` gets a mock list that gains an id after the first call. Assert
  that the second call resolves. **+1 case.**

### C-004 — Retention shrink no longer deletes in the same click (F-004) — `settings/Schema.lua`

- `onChange` for `settings.retentionDays` changes as follows:
  1. It computes how many records the new value would drop, without dropping them. Add
     `Database:CountOlderThan(days)`.
  2. If that count is 0, it does nothing.
  3. Otherwise it shows a `StaticPopup`, `KA0S_LOOTHISTORY_PRUNE`, worded with N. On accept it runs
     `PruneOld`. On decline it prints
     `retention set; N older records will be removed at your next login.`
     The existing deferred login prune then applies it.
- Headless or no `StaticPopup_Show`: keep today's immediate prune, matching how `purge` falls back
  (`settings/Schema.lua:788-792`).
- **The write itself still goes through `Schema:Set`, unchanged** (`architecture-§5`).
- **Tests:** no case pins the row's `onChange` today. `grep -n retentionDays tests/*.lua` finds only
  `PruneOld` itself (`tests/test_database.lua:309`, `:323`) and panel rendering. So the `onChange`
  behavior is new coverage, and it needs two cases in `tests/test_schema.lua`:
  - popup present: nothing is pruned until accept. Use a recorded `StaticPopup_Show` mock, and add
    `-- red under: onChange calling PruneOld directly`.
  - popup absent: today's immediate prune.
  - **+2 cases.**
- Wording follows the confirm style `options-ui-§12` uses for the other destructive popups.
- **Risk:** low. The stored value and the login prune are unchanged.

### C-005 — The Slash stub builds its refusal line from the library's parts (F-005) — `settings/Slash.lua`

```lua
Sl.DisabledLine = function()
  return ("%s is disabled \226\128\148 enable it with |cFFFFFF00%s|r"):format(NS.BRAND, "/lh enable")
end
```

- **This is the minimal fix.** The format string stays, and its comment gets corrected. The lighter
  option is `Kit`-level parity: add a test comparing the stub's output to
  `lib.DISABLED_LINE_FORMAT:format(NS.BRAND, "/lh enable")`, loaded with the library present. It
  would go red on any future drift.
- **Rejected:** removing the degraded refusal outright. `slash-commands-§7` keeps a feature-verb
  refusal even while disabled.
- **Note:** on this path, `enable` itself is unavailable (`:282-286`). The line is now well-formed but
  still points at a verb that declines. That is inherent to a library-less install. Document it in
  the stub comment rather than inventing a second wording.
- **Tests:** add a parity case in `tests/test_slash.lua`'s degraded block. **+1 case.**

### C-006 — Compiled AH priority plan and a per-day cache (F-006, F-016, F-018) — `modules/AuctionPrice.lua`, `core/Database.lua`, `modules/Collector.lua`

1. **`AuctionPrice`:**
   - Add a module-local `plan` (an array of `{prov, key, tag}`), rebuilt by `AuctionPrice:RefreshPlan()`.
   - Call it from `ReconcilePriority`, from `MovePriorityWithin`, and on `SETTINGS_CHANGED`. It gets
     its own bus target and joins the stand-down list, like the Collector's.
   - `Pick` walks `plan`, with no `match` and no `cfg()` per call. `enabled == false` is read once
     into the plan's `off` flag.
2. **`accumulateTime`:** add a `dayCache` local to one `Stats` call (`ts // 86400` → `{day, wday}`).
   This keeps one `date("*t")` per distinct calendar day. The hour still needs `date("*t")` or
   `(ts % 86400)` adjusted for the local offset. Keep `date("*t")` for the hour when it is uncached,
   because local-time correctness matters more than the allocation.
3. **`Collector`:** add a module-level `gateCfg` table filled in `RefreshUpvalues`. Each call sets only
   `gateCfg.itemID = itemID`.
4. **`PruneOld`:** call `fireHistoryChanged()` only when `removed > 0`.

- **Evidence:** an ad-hoc headless micro-benchmark gives `collectgarbage("count")` before and after a
  `Stats` call over a synthetic 20k history with pricing on. It is not committed, and it is **not**
  a `tests/perf.lua`, which remains a recorded deviation. The in-client check is S-006. Name the numbers
  in 05 only if they were measured.
- **Tests:**
  - Existing `Pick` and `Stats` cases must stay green. They pin the behavior.
  - Add one case: after `MovePriorityWithin`, `Pick` honors the new order. This proves the plan
    rebuilt. `-- red under: a plan not refreshed on reorder.`
  - Add one case: a `PruneOld` that removes 0 sends no `HistoryChanged`. `-- red under: unconditional fire.`
    The negative assertion needs a recorded-message spy, and the case must show the spy records a
    positive send first.
  - **+2 cases.**
- **Complexity:** `AuctionPrice@156-180` is `AuctionPrice:MovePriorityWithin`, which is at CCN 15 in
  the fresh lizard run. C-006 adds one `RefreshPlan()` call at its tail and no branch, so its CCN
  should not move. **Do not add a guard inside it**, because that would push it to 16, over the
  release gate. `Pick` itself is not on the watch list. The next release's regeneration will confirm
  this. It is a note for the release, not a task to run here.

### C-007 — Remove the duplicated library formatter cases (F-007) — `tests/test_debuglog.lua`

- Delete `:10-28`, which are the four `FormatPlain`/`FormatColored` cases. Keep `FONT_MONO` and the
  `NS.Debug` integration cases.
- **Inventory: −4 cases.** Move `docs/test-cases.md` and the README badge in the same commit.
- **This is not "deleting a test to turn a suite green".** Those cases are green today. They belong
  to LibKa0s's suite (`testing-§8`).

### C-008 — The DebugLog stub stops carrying library format strings (F-008) — `core/DebugLogSetup.lua`

```lua
FormatPlain   = function(_, _, msg) return tostring(msg) end,
FormatColored = function(_, _, msg) return tostring(msg) end,
```

- Or drop both and add them to the surface-parity `ignore` list, with the reason written down. Either
  way, run `tests/test_surface_parity.lua` first to see which of the two it accepts.
- **Standards:** a stub may not copy formatters (`library-stack-§7`, no-copy bound; anti-pattern #47).

### C-009 — The resize grip honors *Lock frame* (F-009) — `modules/Browser.lua`

- `grip:SetScript("OnMouseDown", function() if B:IsLocked() then return end frame:StartSizing("BOTTOMRIGHT") end)`.
- Update `docs/settings-panel.md:40` and `:191` to read "dragged or resized".
- `OnMouseUp` still calls `StopMovingOrSizing`, which is harmless when no sizing started.

### C-010 — Comment and doc hygiene (F-010, F-011) — `settings/Schema.lua`, `settings/Slash.lua`, `core/Util.lua`, `docs/midnight-quirks.md`

- Reword `Schema.lua:759-760` and `Slash.lua:279` so they name `NS.AddonIsOff` / the latch as the
  flag's reader.
- Move `Util.lua:14` to sit above `SplitPath`, and delete the stale `:38` line.
- Re-point `midnight-quirks.md:9` to `:234` and `:64` to `:98-104`.

### C-011 — One bound vocabulary (F-012) — `modules/Export.lua`, `core/Database.lua`

- **Exports:** pick one label set for both. The row CSV's "Bind on Pickup / Bind on Equip / Not Bound"
  matches the Bound column's tooltip legend, so it wins. `BOUND_LABEL_CSV` then reads from
  `BOUND_LABEL`, with `UNBOUND` mapped to `NONE`.
- **Sentinels:** **leave them as they are, and document them.** `"NONE"` is the Browser filter's
  stored key (`modules/Browser.lua:245`, persisted in `savedView.bound`). `"UNBOUND"` keys
  Analytics and BrowserTable styling (`modules/Analytics.lua:56-64`, `modules/BrowserTable.lua:40-48`).
  Renaming either one migrates a saved view or touches three modules, and neither fixes anything a
  player can see. Add one comment at `core/Database.lua:357` and one at `:524` that name the other
  sentinel and say why the two differ.
- **Tests:** `tests/test_export.lua:217` pins `A-Realm / Unbound` in the Insights CSV. If the label
  set is unified on the row-CSV wording, that expectation changes to `Not Bound`. That is an intended
  output change: update it in the same commit and name it in 05's behavior list.

### C-012 — Launcher tooltip (F-013) — `core/LauncherSetup.lua`

- `tt:AddLine(NS.BRAND, 1, 0.82, 0)`.
- Change the left-click line to "Left-click: show/hide the history window".
- When `NS.AddonIsOff()`, replace the left-click line with the gray line
  `"Disabled — /lh enable to turn it back on"`. **Rejected:** building that text by hand. The line has
  to come from `NS.Slash.DisabledLine()` minus the tag, so there is still one wording.

### C-013 — The degraded `CliResetAll` reports what it did (F-014) — `settings/Slash.lua`

- Print `filters reset (N ids cleared); other settings need the LibKa0s library.` in place of the bare
  `unavailable()`. Use the counted return of `Filters:ClearAll()`.

### C-014 — Warbound repair can warm a link-only row (F-015) — `core/Database.lua`

- `NS.Item.LoadItem(r.itemID or NS.Item.ItemIDFromLink(r.itemLink))`.
- **Tests:** add a case with a link-only pending row. The spy on `C_Item.RequestLoadItemDataByID`
  sees the parsed id. **+1 case.**

### C-015 — Make the export copy actually plain (F-017) — `core/Database.lua`

- `auctionPrice = r.auctionPrice and NS.Util.DeepCopy(r.auctionPrice)`, and the same for `sourceDetail`.
- This is export-only, so the cost is paid once per export.

## Standards conformance, per change

| Change | Conformance note |
|---|---|
| C-001 | `compat` (shim in Compat), `slash-commands-§7` (new registrations on the recorded teardown list, no second teardown path, anti-pattern #85). Registering on the shared target was checked: it does not collide. |
| C-002 | No new registrations. State stays inside the existing `Disable` clear. |
| C-003 | `compat`. No new event registration, so `slash-commands-§7` is untouched. |
| C-004 | `architecture-§5`: the write still goes through `Schema:Set`. The destructive effect moves into a confirm, in the same style as purge and reset-all (`options-ui-§12`). |
| C-005, C-008, C-013 | `library-stack-§7` stub bounds, anti-pattern #47. The line shape is `slash-commands-§7`'s. |
| C-006 | `events-frames-taint-§7`. The new bus target joins the stand-down (`slash-commands-§7`). No perf-harness adoption is implied: the `performance-§12` deviation stands. |
| C-007 | `testing-§8`. The inventory and badge move in the same change (`testing-§5`). |
| C-009, C-010, C-011, C-012, C-014, C-015 | No rule constrains these beyond what is noted in each entry. None of them introduces a deviation. |

**Net inventory movement if all land:**

| Change | Cases |
|---|---|
| C-001 | +3 |
| C-002 | +2 |
| C-003 | +1 |
| C-004 | +2 |
| C-005 | +1 |
| C-006 | +2 |
| C-007 | −4 |
| C-014 | +1 |
| **Total** | **+8, giving 866** |

Treat 866 as an estimate. The authoritative figure is the `--list` output after the changes land.
