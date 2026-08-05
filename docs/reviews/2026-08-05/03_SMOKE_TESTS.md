# 03 — Manual smoke tests (in-client)

Run **after** the changes in `02_PROPOSED_CHANGES.md` have been applied. Everything in this file
needs a logged-in game client; the headless suites (lint, `tests/run.lua`, `lizard`) already ran in
Step 0 of the review and are not repeated here.

**One pre-flight command line, then log in:**

```
luacheck . && lua5.1 tests/run.lua
```

Both must be clean/green before you install the build. If they are not, stop — nothing below is
meaningful against a red tree.

---

## Pre-flight (in-client setup)

1. Copy the addon folder to `.../World of Warcraft/_retail_/Interface/AddOns/LootHistory`. The TOC
   declares `## Interface: 120007` — confirm the client is on that build (`/run print(select(4,
   GetBuildInfo()))`).
2. `/console scriptErrors 1` so Lua errors raise a visible popup instead of failing silently.
3. Any retail character will do for most of this. Two sections need more:
   - **AH price tests (T1)** need at least one of Auctionator / TSM / OribosExchange installed and
     loaded; without one, T1 runs in its "not installed" arm, which is still worth doing.
   - **Combat tests (R5)** need a target dummy (Stormwind, Valdrakken and Dornogal all have them).
4. Take a copy of `WTF/Account/<ACCOUNT>/SavedVariables/LootHistory.lua` before you start — several
   tests below deliberately reset settings.
5. `/lh debug on` opens the session log; several expectations below are debug-console lines. Turn it
   off again where a test says so.

---

## T1 — C-01: a CLI-enabled price source is actually used

**Change covered:** C-01 — single-source the auction defaults (F-001).

**Setup.** A **fresh** SavedVariables for this addon: log out, delete
`SavedVariables/LootHistory.lua`, log back in. Do **not** open the settings panel yet — the point of
this test is that the fix works without the AH Price page ever having repaired anything. TSM
installed and its price data loaded.

**Steps.**
1. `/lh list` — find the `settings.auction.capture` row and note its value.
2. `/lh set settings.auction.capture tsm:dbhistorical` (or whichever CLI spelling the schema CLI
   accepts for adding a tag to the set — check `/lh get settings.auction.capture` after, and adjust
   the set so `tsm:dbhistorical` is the **only** enabled key).
3. `/lh debug on`.
4. Loot any item that TSM has a historical price for (vendor trash from a mob is fine; if the item
   has no TSM data the test proves nothing — pick a common tradeable).
5. Read the `[AHPrice]` line in the debug console.
6. `/lh show`, find the row, read the **Value** column.

**Expected.** The `[AHPrice]` debug line reads `gathered: tsm:dbhistorical=<n>` and
`pick: <n>(tsm:dbhistorical)` — **not** `pick: -(-)`. The Value column shows a non-blank money
amount for that row.

**Pass / Fail.** PASS iff `pick:` names `tsm:dbhistorical` with a number. FAIL if `pick:` is `-(-)`
while `gathered:` shows the price — that is exactly the pre-fix defect.

**Regression arm (do this too).** Repeat from a fresh SavedVariables **without** step 2, loot an
item, and confirm `pick:` names one of the seven default-collected tags. The change must not alter
default behavior.

---

## T2 — C-01/C-02: fresh-install defaults are complete and the boot check is silent

**Change covered:** C-01, C-02 (F-001, F-002).

**Setup.** Fresh SavedVariables again (delete, relog).

**Steps.**
1. Watch the chat frame during login.
2. `/lh get settings.auction.capture` and `/lh list`.
3. Open **Esc → Options → AddOns → Ka0s Loot History → AH Price**.
4. Count the rows in the price table and read the Order column for the four TSM entries that are
   *not* collected by default (Historical, Recent, Region historical, Region sale avg).

**Expected.** No `[LH] schema path missing default: …` line at login. The AH Price table shows 11
rows. The four uncollected TSM entries appear in the "Not collecting data" group, below the
collecting ones, in that order.

**Pass / Fail.** PASS iff no `schema path missing default` line appears **and** the table shows all
11 sources. Any such chat line at login is a FAIL and names the offending path — that is C-02 doing
its job and C-01 having missed something.

---

## T3 — C-04: the two resets are distinguishable and do what they say

**Change covered:** C-04 (F-004).

**Setup.** A profile with **at least 20 recorded loot rows** (`/lh test` on, then off, does not
count — use real history, or loot a dozen greys). Note the count from `/lh show`'s footer.

**Steps.**
1. Change two settings away from stock: `/lh set settings.qualityThreshold 3` and
   `/lh set settings.retentionDays 90`.
2. `/lh resetall`. Read the chat acknowledgement.
3. `/lh show` — read the footer record count.
4. `/lh get settings.qualityThreshold`.
5. Close the window. Open **Esc → Options → AddOns → Ka0s Loot History → General**. Find the button
   to the right of the *Window scale* slider.
6. Click it. Read the confirmation dialog. Click **No**.
7. Click it again and click **Yes**. Read the chat lines, then `/lh show`.

**Expected.**
- After step 2: settings acknowledged as reset; step 3's record count is **unchanged**; step 4
  returns `1`.
- Step 5's button reads **`Reset Everything…`** (with the ellipsis) — **not** `Reset All`.
- Step 6's dialog text names both halves: *"Reset ALL Ka0s Loot History settings AND delete ALL
  recorded history? This cannot be undone."* Clicking No changes nothing (record count unchanged).
- After step 7: the record count is **0** and the window is back at screen center.

**Pass / Fail.** PASS iff the button label is `Reset Everything…`, `/lh resetall` left the history
intact, and the button's Yes path emptied it. FAIL on any label reading `Reset All`, or on
`/lh resetall` changing the record count.

---

## T4 — C-08: a degraded install still tells you what works

**Change covered:** C-08 (F-010), and the F-006 stub work incidentally.

**Setup.** **Rename** `Interface/AddOns/LootHistory/libs/LibKa0s` to `libs/LibKa0s_disabled` and
`/reload`. (Rename, do not delete — you are putting it back in step 6.)

**Steps.**
1. Watch chat during load. Expect nothing yet.
2. Type `/lh`.
3. Type `/lh show`.
4. Type `/lh config`.
5. Type `/lh debug on`, then `/lh debug`.
6. Rename the folder back and `/reload`.

**Expected.**
- Step 2: the first line is the cyan `[LH]` tag plus *"The LibKa0s library is missing from this
  installation of Ka0s Loot History (expected in libs/LibKa0s); running on reduced built-in
  fallbacks."*, said **exactly once**, followed by one line per verb in the command table.
- Step 3: the History window **opens and works** — filters, table, Insights tab.
- Step 4: one line ending *"…, so the settings panel is unavailable."*
- Step 5: `/lh debug on` prints *"…, so the debug console window is unavailable."*; `/lh debug`
  does not raise.
- No Lua error popup at any point, including load.
- Step 6: everything back to normal, cause clause gone.

**Pass / Fail.** PASS iff the verb list appears after the cause clause, the window opens, and no
error popup fires. FAIL on any `attempt to call a nil value` / `attempt to index a nil value`.

---

## T5 — C-03: settings changes still propagate to the collector

**Change covered:** C-03 (F-003). Verifies the fallback removal did not break the healthy path.

**Setup.** `/lh debug on`. Somewhere you can farm low-quality loot quickly.

**Steps.**
1. `/lh set settings.qualityThreshold 0` and loot a grey item. Confirm a `[Loot]` line appears.
2. Without reloading, open **Esc → Options → … → General** and set **Minimum quality** to
   *Epic and above* with the dropdown.
3. Loot another grey item.
4. Without reloading, tick a source off in **Record data from** (e.g. untick *Kill*), then kill
   something and loot it.
5. `/lh set settings.enabled false`, loot something, then `/lh set settings.enabled true`.

**Expected.** Step 3 produces a `[Drop] … reason=quality` line and **no** `[Loot]` line — i.e. the
panel edit reached the collector without a reload. Step 4 produces `reason=source`. Step 5's middle
loot produces neither line (collection off). This is the exact propagation the shared-target clobber
would have broken.

**Pass / Fail.** PASS iff every step produces the stated debug line **in the same session**, with no
`/reload` anywhere in the sequence.

---

## Regression suite (not tied to one change)

| # | Check | Expected |
|---|---|---|
| R1 | `/reload` with the window open on the History tab | Window returns closed; no error; `/lh show` restores position, size, scale and saved view |
| R2 | First login on a **fresh** SavedVariables | Defaults populate; `/lh list` prints every row with a value; no error at `ADDON_LOADED` → `PLAYER_LOGIN` → `PLAYER_ENTERING_WORLD` |
| R3 | Wait ~25s after login on a profile with a few hundred rows | The two deferred passes (`+5s` prune + bound repair, `+20s` bound repair) run without a visible hitch; with `/lh debug on`, a `[Migrate] bound repair: …` line appears |
| R4 | Open every settings page: landing, General, Filters, AH Price; toggle **every** control once | No error; each toggle is reflected by `/lh get <path>`; navigating away from AH Price does not stall the client |
| R5 | Enter combat on a dummy with the History window and the settings panel both open; leave combat | No `Interface action failed because of an AddOn`; `/lh config` while in combat refuses with a chat line rather than opening or erroring |
| R6 | Minimap button: left-click, right-click, then tick **Hide minimap button** | Left opens the window, right opens settings, ticking hides the button immediately (no reload); tooltip record count matches the footer |
| R7 | `/lh test` on → browse both tabs → `/lh test` off | Synthetic dataset appears with a Test-Mode badge; real history is untouched (record count returns to its prior value) |
| R8 | Export from both tabs (History and Insights) | Copy window opens with CSV text; the History CSV's `value` column agrees with the on-screen Value column for a spot-checked row |
| R9 | Blacklist an item id via the Filters page, then loot that item | `[Drop] … reason=blacklist`, no new row, in the same session with no reload |

---

## Performance spot-checks

This addon ships **no** `tests/perf.lua` and adopts no `LibKa0s-Perf` major, so there is no `/lh
perf` capture protocol to follow and nothing to commit under `docs/perf-runs/`. F-009 is the only
perf-tagged finding and it is deferred, so no perf change is being verified here. If you want a
number anyway for R3 or R4:

```
/run collectgarbage("collect"); local a=collectgarbage("count"); <do the flow>; print(collectgarbage("count")-a)
```

Treat the result as orientation only — a single before/after on a shared Lua heap is not a
measurement, and this checklist makes no claim on it.

---

## Sign-off

| ID | Tested? | Pass/Fail | Notes |
|---|---|---|---|
| C-01 (T1, T2) | | | |
| C-02 (T2) | | | |
| C-03 (T5) | | | |
| C-04 (T3) | | | |
| C-05 | n/a — headless | | verified by `lua5.1 tests/run.lua` pre-flight |
| C-06 (T4) | | | |
| C-07 | n/a — headless | | verified by `luacheck .` pre-flight |
| C-08 (T4) | | | |
| R1–R9 | | | |
