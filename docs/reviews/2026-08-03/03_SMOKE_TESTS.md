# Ka0s Loot History — Manual Smoke Tests (2026-08-03)

Run **after** the changes in `02_PROPOSED_CHANGES.md` are applied. One section per change ID.
Fill in the sign-off table at the bottom.

---

## Pre-flight

1. **Build / install.** Copy the repo (minus `docs/`, `tests/`, `.luacheckrc` — the `.pkgmeta`
   `ignore:` set) to `World of Warcraft/_retail_/Interface/AddOns/LootHistory/`.
   Confirm `LootHistory.toc` reads `## Interface: 120007` and, after C-006,
   `## SavedVariables: LootHistoryDB, LootHistoryPerfDB`.
2. **Client.** Retail only (the addon declares no other flavor). Any character; several tests need
   **two different characters** and at least one needs a **target dummy** (Stormwind, Valdrakken or
   Dornogal training dummies) for the combat checks.
3. **Make failures visible.**
   - `/console scriptErrors 1` then `/reload` — a Lua error must pop, not swallow.
   - Keep `/etrace` handy for the event checks (`CHAT_MSG_LOOT`, `ADDON_LOADED`).
   - Turn the addon's own tracing on for the capture tests: `/lh debug on`, then `/lh debug` to open
     the console window.
4. **Headless gate first.** `lua tests/run.lua` must print `0 failed` before you install anything.
   After C-006, `lua tests/perf.lua` runs separately and is **not** part of that count.
5. **Baseline SavedVariables.** Before starting, copy
   `WTF/Account/<ACCOUNT>/SavedVariables/LootHistory.lua` somewhere safe. Several tests below ask you
   to inspect it after a `/reload` (SavedVariables are only written on logout/reload).

---

## C-001 — Hidden Filters page rebuilds on next open

**Change covered:** C-001 — off-screen structural changes now reach the Filters sub-page.

**Setup:** fresh session; at least one item in the history (loot anything, or run `/lh test`, note an
id, then `/lh test` again and loot for real). Settings window closed.

**Steps:**
1. `/lh config` → click **Filters**. Confirm the three sections render (Blacklist, Whitelist,
   Blacklisted currencies) and note which ids are listed under **Blacklist**.
2. Press `Escape` to close the Settings window entirely.
3. `/lh show` to open the History window. Right-click any row with a real item → **Blacklist item**.
   Confirm the chat line `[LH] blacklisted <name>. Manage in Settings ▸ Filters.`
4. `/lh config` → click **Filters**.

**Expected:** the id you just blacklisted is present in the Blacklist section's list, with a
**Remove** button. No Lua error.

**Pass / Fail:** PASS iff the new id is visible on first open in step 4 without any further click,
tab switch or `/reload`. FAIL if the list is unchanged from step 1.

**Regression half:** repeat steps 1–4 but leave the Settings window **open** on the Filters page in
step 3 (use the History window's right-click menu with both windows visible). The list must update
immediately, exactly as before this change.

---

## C-002 — Live stats survive a page re-render

**Change covered:** C-002 — the History-stats subscription no longer holds a released widget.

**Setup:** at least 5 records in the history. Settings window closed.

**Steps:**
1. `/lh config` → **General**. Scroll to the **History** section and note the line
   `N items collected over D days.` and `Database size: ≈ …`.
2. Press `Escape`.
3. `/lh set settings.windowScale 1.1` — a scalar write while the page is hidden, which is what marks
   it for re-render.
4. `/lh config` → **General**. Confirm the History section renders and the numbers are correct.
5. Without closing Settings, loot an item (or `/lh purge`-free alternative: delete a row from the
   History window's right-click menu).

**Expected:** the `N items collected …` line updates in place in step 5. No other label anywhere on
the General page changes text unexpectedly (that is the recycled-widget symptom). No Lua error.

**Pass / Fail:** PASS iff the stats line tracks the change in step 5 **and** no unrelated control on
the page shows the storage text.

---

## C-003 — Preview mode is read-only

**Change covered:** C-003 — mutating row actions are disabled in test mode.

**Setup:** note your current blacklist contents (`/lh config` → Filters, or the settings page list).

**Steps:**
1. `/lh test`. The History window opens with the red **TEST MODE** badge beside the title.
2. Right-click any row.
3. Observe the four menu entries.
4. Click each of **Blacklist item**, **Blacklist currency** and **Delete** in turn (they should not
   respond).
5. Click **Link to chat** on a row (this one stays enabled).
6. `/lh test` again to clear preview mode. `/lh config` → **Filters**.

**Expected:**
- Step 3: **Blacklist item**, **Blacklist currency** and **Delete** render gray (disabled);
  **Link to chat** renders normal.
- Step 4: no chat line, no menu dismissal, no row disappears, no Lua error.
- Step 6: the Blacklist list is **identical** to the pre-test contents — no ids in the
  100001–100030 range.

**Pass / Fail:** PASS iff no synthetic id reaches the blacklist and Delete is inert in preview mode.

---

## C-004 — Coalesced repaint + allocation-free byte estimate

**Change covered:** C-004 — per-loot repaint debounce and `estimateRecordBytes`.

**Setup:** a character with a reasonably large history (≥500 records; use a well-used main, or run
the addon for a session). History window **open** on the **History** tab.

**Steps:**
1. `/run collectgarbage("collect"); print(collectgarbage("count"))` — record the number (kB).
2. Go to a mass-loot situation: clear a pack of ~10 mobs with auto-loot on, or open a full mailbox
   with `Take All`.
3. Watch the window's footer (`Showing X of Y`) and the bottom-right `Database ≈ …` figure.
4. `/run collectgarbage("collect"); print(collectgarbage("count"))` — record again.

**Expected:**
- No visible hitch on each individual loot line.
- The footer counts and the `Database ≈` figure settle to the correct final values within ~1 second
  of the last loot (a short lag is the intended debounce, not a bug).
- Step 4's number is meaningfully closer to step 1's than on the pre-change build (the per-record
  table churn is gone). Record both numbers in the sign-off notes.

**Pass / Fail:** PASS iff the final `Showing X of Y` and `Database ≈` values are correct and no
frame-rate hitch is felt per loot line.

---

## C-005 — Insights relayout is throttled

**Change covered:** C-005 — `OnSizeChanged` no longer relayouts every frame.

**Setup:** history with ≥200 records spanning ≥7 days (or `/lh test`). History window open.

**Steps:**
1. Click the **Insights** tab. Confirm the cards and every chart section render.
2. Grab the bottom-right resize grip and drag the window from minimum width to near full screen and
   back, **slowly**, over ~5 seconds.
3. Release the grip.
4. Switch to **History** and back to **Insights**.

**Expected:** the drag is smooth (no per-frame stall); charts settle to the new width within one
frame of release; every bar, legend, strip and list panel is correctly positioned afterwards — no
overlapping labels, no chart anchored off the right edge. No Lua error.

**Pass / Fail:** PASS iff the drag is smooth **and** the final layout is identical to what a fresh
open at that width produces (verify by `/reload` and reopening at the same size).

---

## C-006 — Performance harness wiring

**Change covered:** C-006 — `LibKa0s-Perf-1.0` adoption.

**Setup:** fresh login, no combat.

**Steps:**
1. `/lh perf` with no arguments.
2. Follow the guided step panel to run a **clean arm** capture: enter combat on a training dummy,
   fight for ~60 seconds with the History window open on the Insights tab, leave combat.
3. Follow the panel to the **suspended arm**: confirm the addon goes inert **without** a `/reload`
   (the History window must refuse to open, or open empty per the show-decision ladder — whichever
   the descriptor implements), then repeat the same 60-second dummy fight.
4. Let the panel resume the addon and emit the report.
5. `/reload`, then inspect `WTF/Account/<ACCOUNT>/SavedVariables/LootHistory.lua`.
6. Run `lua tests/perf.lua` from the repo.

**Expected:**
- Step 1 prints a `[LH]`-tagged entry line and opens the step panel; it does **not** require an
  argument to be useful.
- Step 3: no `/reload` is needed to suspend, and the addon genuinely stops working (no new records
  captured during the suspended arm — verify with `/lh debug on` beforehand: no `[Loot]` lines).
- Step 4: the addon is **resumed before** the report is printed/saved.
- Step 5: the file contains **two** globals — `LootHistoryDB` and `LootHistoryPerfDB` — and the perf
  ring is **outside** the AceDB tree (not under `LootHistoryDB`).
- Step 6: the offline scenario runner passes and reports the **zero-overhead** scenario (a dormant
  bracket allocates nothing).
- The report names every declared bucket, and **no declared bucket reports zero samples** after a
  capture that exercised its path.

**Pass / Fail:** PASS iff all six bullets hold. Any declared-but-never-reached bucket is a FAIL.

**Degraded-install check (same change):** rename `libs/LibKa0s/` to `libs/LibKa0s_off/`, `/reload`.
The addon must load with no Lua error, print the single `[LH] The LibKa0s library is missing …` line,
still record loot, and `/lh perf` must answer with an honest unavailable line rather than erroring.
Rename it back and `/reload`.

---

## C-007 / C-008 — Defaults and schema stamp

**Change covered:** C-007 (single source for the AH defaults), C-008 (schema stamp ships current).

**Setup:** **fresh SavedVariables.** Log out, move `LootHistory.lua` out of
`WTF/Account/<ACCOUNT>/SavedVariables/`, log back in.

**Steps:**
1. `/lh get settings.auction.capture` — note the tags.
2. `/lh config` → **AH Price**. Read the price-source table top to bottom and note the **Order**.
3. `/lh reset settings.auction.capture`, then `/lh get settings.auction.capture` again.
4. Click the AH Price page's **Defaults** button. Re-read the Order.
5. `/reload`, then inspect `LootHistoryDB.global.schemaVersion` in the saved file.

**Expected:**
- Steps 1 and 3 return the **same** seven tags.
- Steps 2 and 4 produce the **same** 11-row order (all `AUCTION_KEYS` present exactly once).
- Step 5: `schemaVersion` is the current head value (8 at the time of writing), not 1.

**Pass / Fail:** PASS iff fresh-install, `/lh reset` and the Defaults button all agree.

**Existing-DB half:** restore your backed-up `LootHistory.lua`, hand-edit
`LootHistoryDB.global.schemaVersion` to `1`, log in with `/lh debug on` already set from a prior
session (or set it and re-`/reload`, then re-check the console buffer). The `[Migrate]` lines must
show the walk `v1 -> v2` … `v7 -> v8`, and no history row may be lost — compare the record count
before and after in the settings **History** section.

---

## C-009 / C-010 / C-011 / C-012 — Polish

**C-009 (comment only):** no in-client test. Verify by reading `settings/OptionsSetup.lua:99` — it
must use the `filename-§N` form and no `§N.M`.

**C-010 — one mark:**
1. Confirm the minimap button's icon matches the addon logo shown on the settings landing page.
2. `Escape` → **AddOns** → find **Ka0s Loot History** in the list; its icon must be the same mark.
3. `/lh config` — the landing page logo is the same mark.
**Pass / Fail:** PASS iff all three places show one mark.

**C-011 — `/lh test` exit does not open the window:**
1. `/lh test` (window opens, TEST MODE badge shown).
2. Close the window with the × glyph.
3. `/lh test` again.
**Expected:** the window stays closed; the chat line reads `[LH] test mode off`. Reopen with
`/lh show` and confirm the badge is gone and real history is shown.
**Pass / Fail:** PASS iff step 3 leaves the window closed.

**C-012 — stub symmetry and bus targets:**
1. With `libs/LibKa0s/` renamed away (see C-006's degraded check), run `/lh help`, `/lh list`,
   `/lh get settings.enabled`, `/lh set settings.enabled false`, `/lh resetall`. Each must print an
   honest `[LH] … unavailable` line; **none** may raise a Lua error.
2. Rename it back, `/reload`. Open the History window, open Settings ▸ General (leave both up), and
   toggle **Enable collection** off then on. All three subscribers must react: the Collector stops
   and resumes recording (verify with `/lh debug on` and a loot), the browser footer stays live, and
   the Insights tab refreshes.
**Pass / Fail:** PASS iff (1) errors nowhere and (2) all three subscribers react — a single
non-reacting consumer is the bus-clobber symptom.

---

## Regression suite (not tied to one change)

| # | Check | Expected |
|---|---|---|
| R1 | `/reload` three times in a row | No Lua error popup; window and settings reopen cleanly |
| R2 | Delete `LootHistory.lua`, log in fresh | Defaults populate; `/lh list` shows every schema row with a sane value; no error |
| R3 | Cold boot event order via `/etrace` | `ADDON_LOADED` → `PLAYER_LOGIN` → `PLAYER_ENTERING_WORLD` with no errors; retention prune and bound repair fire ~5s and ~20s after entering world |
| R4 | Enter and leave combat with the History window, the Insights tab and the debug console all open | No error; no frame vanishes; combat does not break the display |
| R5 | Open **Escape → Options → AddOns → Ka0s Loot History** *while in combat* on a dummy | The Settings window closes and the addon prints the combat-refused line (options-ui-§2) — it must **refuse**, not render half a page |
| R6 | Open every settings page and toggle every option at least once | Every write takes effect and survives `/reload`; no error |
| R7 | Switch characters (log to a second toon on the same account) | Account-wide history and settings carry over; the Character filter offers both characters |
| R8 | `/lh purge` → confirm | History empties, footer reads `Showing 0 of 0`, settings History section reads `No items collected yet.` |
| R9 | `/lh resetall` → confirm | Every setting returns to default, the three filter lists clear, history is untouched |
| R10 | Loot an item, a currency, a quest item, a warbound item, and take an AH mail | Five correctly-attributed rows (or correctly-dropped, per the gate) — verify each in the debug console |
| R11 | Resize the History window to its minimum and maximum | No column truncation, no toolbar overlap, geometry survives `/reload` |
| R12 | Export from both tabs, both Data Set options | Four CSVs open in the copy window; header row present; Ctrl+C copies |

---

## Localization sanity

Not required. The addon ships English-only by an explicit, documented scope decision
(`locales/enUS.lua:7-11`), no string routes through `NS.L`, and this review raised **no** `[locale]`
findings. If a locale pass is ever done, re-run C-003, C-007 and R10 under deDE.

---

## Performance spot-checks

Tied to C-004, C-005 and C-006.

| Check | Command | When |
|---|---|---|
| Allocation delta | `/run collectgarbage("collect"); print(collectgarbage("count"))` before and after the C-004 mass-loot sequence | C-004 |
| Frame time under resize | `/console scriptProfile 1` → `/reload` → drag-resize on the Insights tab for 5s → `/run UpdateAddOnCPUUsage(); print(GetAddOnCPUUsage("LootHistory"))` | C-005 |
| Bucket report | `/lh perf` two-arm capture per C-006 | C-006 |

Record before/after numbers in the notes column below — they become the "Performance impact" section
of `05_FINAL_SUMMARY.md`.

---

## Sign-off

| ID | Tested? | Pass/Fail | Notes |
|---|---|---|---|
| C-001 | | | |
| C-002 | | | |
| C-003 | | | |
| C-004 | | | before kB / after kB: |
| C-005 | | | CPU before / after: |
| C-006 | | | bucket report attached? |
| C-007 | | | |
| C-008 | | | |
| C-009 | | | (read-only check) |
| C-010 | | | |
| C-011 | | | |
| C-012 | | | |
| R1–R12 | | | |
