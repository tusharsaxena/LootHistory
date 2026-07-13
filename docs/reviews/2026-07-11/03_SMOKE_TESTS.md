# 03 — Smoke Tests · Ka0s Loot History

Manual in-client checklist to run **after** the `02_PROPOSED_CHANGES.md` changes are applied.
Confirms each fix and guards against regressions. Also runs the headless suite as a gate.

---

## Pre-flight

1. **Build/install:** copy the addon folder to `Interface/AddOns/LootHistory`. Confirm the TOC
   `## Interface:` matches your client build (see F-012); a mismatched value shows the addon as
   "out of date" unless "Load out of date AddOns" is checked.
2. **Client:** retail (Mainline) for the full source-attribution matrix; a Classic client for the
   flavor-degradation regression only.
3. **Errors visible:** `/console scriptErrors 1`. Optionally `/etrace` to watch event flow, and
   `/dump` for quick DB inspection.
4. **Headless gate (repo root):**
   ```
   luacheck .          # expect 0 errors (the enUS.lua W211 should be gone after F-004 cleanup)
   lua tests/run.lua   # expect "N passed, 0 failed"
   ```
5. **Fresh state option:** to test first-run defaults, back up and delete
   `WTF/Account/<acct>/SavedVariables/LootHistoryDB.lua`.

---

## Per-change tests

### F-001 / C-001 — Attribution coverage is honest
- **Change covered:** unreachable sources no longer advertised; verify which flows actually record.
- **Setup:** fresh or existing SavedVariables; retail character with bags space, some mail with an
  item attachment, a vendor nearby, and (if possible) a trade partner and a crafting profession.
- **Steps (empirical source matrix — record PASS/FAIL per row):**
  1. Kill a mob and loot the corpse → `/lh show`, History tab. Expect a row with **Source = Kill**.
  2. Open a chest / lockbox / herb node and loot it → expect **Source = Container**.
  3. Turn in a quest with an item reward → expect **Source = Quest**.
  4. Buy an item from a vendor (`BuyMerchantItem`) → check for a new row; note its Source (Vendor?
     Other? or **no row at all**).
  5. Take an item attachment from mail → check for a new row and its Source.
  6. Complete a trade that gives you an item → check for a new row and its Source.
  7. Craft an item → check for a new row and its Source (expected **Other/Container**, since no
     CRAFT stamper).
  8. Win a group-loot roll → check its Source (expected not "Roll").
  9. Open the settings panel → "Record data from" mute list. Confirm it lists **only** implemented
     sources (post-C-001): Kill, Container, Mythic+, Quest, Vendor, Mail, Trade, Other — **not**
     AH/Craft/Roll.
- **Expected:** rows 1-3 record with the correct source. Rows 4-8 document the *actual* behavior;
  the mute list matches `SOURCE_IMPLEMENTED`. No Lua errors.
- **Pass/Fail:** PASS if Kill/Container/Quest attribute correctly, the mute list shows only
  implemented sources, and the observed behavior of rows 4-8 is recorded (and, if any of
  VENDOR/MAIL/TRADE record nothing, they were removed from `SOURCE_IMPLEMENTED`).

### F-002 / C-002 — Challenge-mode map id via Compat
- **Setup:** retail, a Mythic+ keystone (or CHALLENGE_MODE zone).
- **Steps:** 1) Start a keystone. 2) Complete it and loot the Great Vault/end chest.
- **Expected:** the chest loot attributes **Source = Mythic+**; no Lua error from
  `OnChallengeModeStart`/`Completed`. On a **Classic** client, entering any zone throws no error
  (guards degrade cleanly).
- **Pass/Fail:** PASS if MPLUS attribution still works retail and no error on Classic.

### F-003 / C-003 — Reset does not alias defaults
- **Setup:** any character.
- **Steps:** 1) In settings, uncheck several sources in "Record data from" (mutes them).
  2) `/lh resetall`. 3) `/lh get settings.excludedSources` (or reopen the panel). 4) Toggle a
  source again, then `/lh reset settings.excludedSources`, toggle again.
- **Expected:** after resetall the mute set is empty and the panel shows all sources recorded;
  repeated reset/toggle cycles never leave a "sticky" muted source and never error.
- **Pass/Fail:** PASS if the excludedSources set round-trips cleanly across multiple resets.

### F-004 — Localization note (no functional change)
- **Steps:** `luacheck locales/enUS.lua`.
- **Expected:** the `W211 unused variable L` warning is gone (either `L` removed or used).
- **Pass/Fail:** PASS if luacheck is clean.

### F-005 / C-004 — Shared range/kind helpers
- **Setup:** history spanning several days (or `/lh test`).
- **Steps:** 1) History tab → Date dropdown: cycle Today / Last 7 days / Last 30 days / All.
  2) Insights tab → Range: Today / 7 days / 30 days / All.
- **Expected:** both surfaces filter identically to before; the footer "Showing X of Y" and the
  Insights cards update. No error.
- **Pass/Fail:** PASS if both date/range selectors behave as before and `lua tests/run.lua`
  (incl. the new `Util.RangeFrom` test) is green.

### F-006 / C-005 — Player-scope toggle sync
- **Setup:** history containing loot from **≥2 characters** on your account (or `/lh test`, which
  seeds multiple synthetic characters — but note test chars aren't the current char).
- **Steps:** 1) Open History. 2) Player toggle → "All players". 3) Character dropdown → pick a
  specific character that is NOT the current one. 4) Observe the Player toggle. 5) Click "Clear".
- **Expected:** after step 3 the Player toggle no longer falsely reads "All players" (shows a
  neutral/blank or "current-character-specific" state per C-005); after Clear it returns to
  "Current player".
- **Pass/Fail:** PASS if the two controls never contradict each other.

### F-007 / C-006 — Dead helpers removed
- **Steps:** `grep -rn "FormatTime\|TableCount" core modules settings tests` → no matches;
  `lua tests/run.lua` green.
- **Pass/Fail:** PASS if gone and tests pass.

### F-008 / C-007, F-009 / C-008, F-010 / C-009, F-011 / C-010 — Cleanup
- **Steps:** 1) `/reload`, `/lh test` (badge + preview rows appear). 2) Read the touched comments.
  3) `/lh show`, start/finish a keystone (no error from the trimmed keystone table).
- **Expected:** `/lh test` still toggles the preview; no behavioral change from the comment/seed/
  doc edits; no error from removing `keystone.mapID`.
- **Pass/Fail:** PASS if test mode and MPLUS attribution are unaffected.

### F-012 / C-011 — TOC
- **Steps:** launch the client; confirm the addon loads and is **not** flagged out-of-date
  (or that the flag is expected for your build).
- **Pass/Fail:** PASS if the interface version is correct for the target client.

---

## Regression suite (run every cycle)

1. **Clean load:** delete `LootHistoryDB.lua`, log in. No error at ADDON_LOADED → PLAYER_LOGIN →
   PLAYER_ENTERING_WORLD. Defaults populate: `/lh list` shows enabled=true, qualityThreshold=1,
   retentionDays=30, windowScale=1, excludedSources={}.
2. **`/reload`** with data present → window position/size/scale and `savedView` restore; no error.
3. **Capture path:** kill/loot several items → rows appear live in an open History window; the
   minimap tooltip record count increments; Insights cards update while the tab is open.
4. **Combat enter/leave:** enter combat with the History window open → no error, window stays
   usable (non-secure §6A). `/lh config` in combat prints "Can't open settings in combat."; out of
   combat it opens the panel. Esc → Options → Ka0s Loot History also opens it.
5. **Table ops:** sort every column (asc/desc), group by each mode (Source/Zone/Character/Quality/
   Day), collapse/expand a group, search, quality/type/source/zone/date filters, Save/Reset/Clear
   view, row right-click → Link + Delete, Shift-click → link to chat.
6. **Settings panel:** open it, toggle every widget once (Enable, Hide minimap, Window scale slider,
   Minimum quality, Keep history for, each source checkbox), press Defaults, press Reset All
   (confirm dialog), Purge history (confirm dialog). Stats line updates live.
7. **Retention:** set "Keep history for" to a short value with old records present → `PruneOld`
   drops them (fires on the setting's onChange and 5s after login).
8. **Debug console:** `/lh debug` opens the console and enables logging; loot something → a line
   appears; Copy → editbox with plain text; Clear empties it; Esc closes and disables logging.
9. **Minimap:** left-click toggles the window, right-click opens settings; "Hide minimap button"
   hides/shows it and persists across `/reload`.

## Taint-specific tests
No taint findings. Confirm the non-secure design holds: enter combat, open/close the History
window, click rows, drag/resize — expect **no** "Interface action failed because of an AddOn" red
text. Confirm `/lh config` AND Esc → Options both open the settings category.

## Localization sanity
Only relevant if F-004 is actioned beyond the luacheck cleanup. If any string is wrapped in
`L[...]`, switch the client to deDE or frFR and re-run the tests for the affected surfaces,
watching for missing-key fallbacks (they should render the English key, never nil).

## Performance spot-checks
- **Insights refresh:** with a large history (thousands of rows via repeated `/lh test` data or a
  real DB), `/run collectgarbage("count")` before and after cycling all four Insight ranges;
  expect no unbounded growth (pools reused).
- **Combat-log handler (F-013):** `/console scriptProfile 1` → `/reload` → run a dummy-pack raid
  pull → `/run UpdateAddOnCPUUsage()` → `/dump GetAddOnCPUUsage("LootHistory")`. Note the cost of
  the `COMBAT_LOG_EVENT_UNFILTERED` handler for the backlog decision.

---

## Sign-off

| ID | Tested? | Pass/Fail | Notes |
|----|---------|-----------|-------|
| F-001 / C-001 | | | source matrix result: |
| F-002 / C-002 | | | |
| F-003 / C-003 | | | |
| F-004 | | | |
| F-005 / C-004 | | | |
| F-006 / C-005 | | | |
| F-007 / C-006 | | | |
| F-008 / C-007 | | | |
| F-009 / C-008 | | | |
| F-010 / C-009 | | | |
| F-011 / C-010 | | | |
| F-012 / C-011 | | | |
| Regression suite | | | |
| Perf spot-checks | | | |
