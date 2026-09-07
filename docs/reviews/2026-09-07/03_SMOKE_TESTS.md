# 03 — Manual smoke tests (in-client)

Execute **after** the changes in `02_PROPOSED_CHANGES.md` have been applied. Everything here needs a logged-in game client; everything that runs headless already ran in Step 0 and is recorded in `01_FINDINGS.md`'s measurement block.

---

## Pre-flight

**One command line, not a suite section.** Before logging in, from the repo root:

```sh
lua tests/run.lua       # expect: 704 passed, 0 failed, 0 skipped, 704 total
luacheck .              # expect: 0 warnings / 0 errors
```

If either is not green, stop — nothing below is meaningful.

**Client setup.**

1. Retail only. `LootHistory.toc:1` declares `## Interface: 120007`; confirm the client build matches (`/run print((select(4, GetBuildInfo())))`).
2. Copy the addon folder to `Interface/AddOns/LootHistory/`. No other Ka0s addon needs to be present.
3. `/console scriptErrors 1` — Lua errors must surface as popups, not be swallowed.
4. Have `/etrace` available for the event checks in R-3.
5. **Character requirements:** any max-level character with (a) access to a target dummy for combat transitions, (b) at least one currency in the log — Conquest, Valorstones, anything — and (c) an existing loot history of **≥ 200 rows** for the estimate checks. If the history is empty, run `/lh test` first to populate the synthetic preview set, then clear it before the SavedVariables checks.
6. **Two SavedVariables states are needed.** Take a copy of `WTF/Account/<ACCT>/SavedVariables/LootHistory.lua` **before** starting, so the migration regression (R-5) can be run against a pre-change DB.

---

## C-01 + C-02 — the database-size estimate counts every string field

**Change covered:** C-01 — `estimateRecordBytes` no longer truncates on a nil field.

**Setup:** log in with an existing history containing at least one **currency** row. Confirm one exists: `/lh set settings.recordCurrency true`, then loot any currency (a world-quest turn-in, a dungeon completion, a vendor refund) so at least one `currencyID` row is stored. `/reload`.

**Steps:**

1. Note the current value: `/run local s=LootHistoryDB and true; print("open the window")` — then `/lh show` and read the footer line at the bottom of the History window: `Database ≈ <size>`.
2. Record that number.
3. `/lh config` → **General** page. Read the storage line under the record count: `Database size: ≈ <size>  (estimated)`.
4. Confirm the two agree with each other.
5. Compare against the pre-change build's number for the **same** SavedVariables file (from the backup taken in pre-flight, loaded on the old build).

**Expected:**

- Steps 1 and 3 report the **same** figure.
- The figure is **strictly larger** than the pre-change build's for the same history — this is the fix landing. For a history with N currency rows the increase is roughly N × (the currency name + zone + character-key + type + subtype lengths), so a few dozen bytes per currency row.
- No Lua error popup at any point.

**Pass / Fail:** PASS iff the window footer and the settings line agree **and** the value has risen relative to the pre-change build on identical data. FAIL if the two surfaces disagree, if the number is unchanged, or if anything errors.

---

## C-03 — the settings panel no longer re-walks the history once per looted item

**Change covered:** C-03 — the panel's `RecordAdded` listener is coalesced.

**Setup:** history of **≥ 2000 rows** (the effect scales with history size — with a small history the difference is unobservable). `/lh set settings.qualityThreshold 0` so nothing is gated out. Find a pull that drops several items at once — a trash pack in any current dungeon on Normal, or a herb/ore node cluster.

**Steps:**

1. `/reload`.
2. `/lh config` and leave the settings canvas **open on the General page**.
3. `/run collectgarbage("collect"); print("KB before:", collectgarbage("count"))` — record the number.
4. Without closing the panel, kill a trash pack that drops **at least 5 items** and autoloot them.
5. `/run print("KB after:", collectgarbage("count"))` — record the number.
6. Repeat steps 1–5 on the **pre-change** build for comparison.

**Expected:**

- The KB delta across the loot burst is **lower** on the changed build than on the pre-change build. Exact figures will vary with history size; the direction is what is being tested.
- The storage line on the General page still updates — within ~0.2 s of the last drop, not instantly. A visible lag of a fraction of a second is **correct**, not a failure.
- No Lua error.

**Caveat to record with the result:** `collectgarbage("count")` measures the whole Lua heap, not this addon's share, so another addon allocating during the same window contaminates it. Run with only LootHistory enabled if the numbers look noisy.

**Pass / Fail:** PASS iff the storage line still updates after the burst **and** the KB delta is not larger than the pre-change build's. FAIL if the line stops updating (the coalescer is dropping work rather than collapsing it) or if it errors.

---

## C-06 — `Attribution:Enable` wires everything it claims to

**Change covered:** C-06 — the new integration case. The in-client half confirms the wiring is real, not just asserted against a mock.

**Setup:** `/lh debug on` (session logging; the console window is separate). `/lh debug` to open the console so the `[Attr]` lines are visible.

**Steps — one per registration, each producing an `[Attr] stamp` line:**

1. **KILL** — kill any mob and loot it. Expect `[Attr] consume -> KILL (CERTAIN)`.
2. **CONTAINER** — open a lockbox or a container item from your bags. Expect a `container-open` stamp then `consume -> CONTAINER`.
3. **VENDOR** — buy anything from a merchant. Expect `vendor-buy` then `consume -> VENDOR`.
4. **MAIL** — take an item from an AH mail. Expect `mail-ah` (or `mail-take` for a player mail) then the corresponding source.
5. **QUEST** — turn in any quest with an item reward. Expect `quest-reward` then `consume -> QUEST`.
6. **TRADE** — complete a trade with another player. Expect `trade-complete` then `consume -> TRADE`.
7. **ENCOUNTER** — pull a raid or dungeon boss. Expect `ENCOUNTER_START` to populate the encounter context; the boss's loot should carry an `encounterID` in its `[Loot]` detail.
8. **M+** — start a keystone. Expect the keystone context to stamp, and chest loot to resolve `MPLUS`.
9. **DECONSTRUCT** — Disenchant, Mill or Prospect something. Expect `deconstruct:DISENCHANT` (or MILLING / PROSPECTING) then that source on the resulting materials.
10. **ROLL** — win a group-loot roll. Expect `roll-won` then `consume -> ROLL`.

**Expected:** every one of the ten produces its stamp line and its loot resolves to the named source, not `OTHER (INFERRED)`.

**Pass / Fail:** PASS iff all ten resolve to their intended source. Any that falls through to `OTHER` is a FAIL and names exactly which registration or hook is not firing — which is the whole point of the case C-06 adds.

---

## C-09 — the NBSP-widened trims still resolve warbound state

**Change covered:** C-09 — the two localized-text scanners.

**Setup:** this needs a **non-enUS client**. Set the game client to **deDE** (Battle.net → Game Settings → Game Language) and restart. Log in on the same character.

**Steps:**

1. `/lh debug on`, `/lh debug` to open the console.
2. Loot or acquire a **warbound** item — any Warbound Cache, or an item whose German tooltip reads *"Wird an die Kriegsschar gebunden"* / *"…bis angelegt"*.
3. `/lh show` and find the row. Read its **Bound** column lock mark and hover it for the legend.
4. Deconstruct something (Mahlen / Prospektieren, including a **Massen-** variant) and check the console for the deconstruct stamp.

**Expected:**

- The warbound item's Bound column shows `WARBAND` or `WARBAND_UE`, not blank and not `BOE`.
- The Mass-variant deconstruct produces `deconstruct:MILLING` / `deconstruct:PROSPECTING`, not a fall-through to `OTHER`.
- Repeat step 2 on **frFR** if available.

**Pass / Fail:** PASS iff the warbound state resolves and the deconstruct family matches on the non-enUS client. Restore the client to enUS afterwards.

---

## C-10 — the corrected degraded-install help

**Change covered:** C-10 item 4 — `config` is now listed as unavailable on a degraded install.

**Setup:** **rename** `Interface/AddOns/LootHistory/libs/LibKa0s/` to `libs/LibKa0s.disabled/` so `LibStub` cannot resolve any LibKa0s major. Restore it immediately after this section.

**Steps:**

1. Log in. Expect **no** Lua error popup at load — the seams must degrade, not raise.
2. Read the chat frame for the one-time notice: `[LH] The LibKa0s library is missing from this installation of Ka0s Loot History (expected in libs/LibKa0s); running on reduced built-in fallbacks.`
3. Type `/lh` with no arguments.
4. Type `/lh config`.
5. Type `/lh show`, then `/lh hide`.
6. Type `/lh debug on`, then `/lh debug`.
7. Restore the folder name and `/reload`.

**Expected:**

- Step 1: no error popup; the addon loads.
- Step 3: the help header names the absence, and the listed verbs are the ones that still work — `show`, `hide`, `toggle`, `debug`, `test`, `purge`. **`config` must NOT be listed** (that is the C-10 fix).
- Step 4: `config` still *works as a command* and prints `…so the settings panel is unavailable.` — it declines honestly rather than erroring.
- Step 5: the History window opens and closes.
- Step 6: `/lh debug on` prints `…so the debug console window is unavailable.` and the logging flag still flips; `/lh debug` is a safe no-op.
- Step 7: full functionality returns.

**Pass / Fail:** PASS iff no error at any step, `config` is absent from the help list, and every listed verb actually works.

---

## Regression suite

Not tied to any one change; these cover behaviour the change-set could plausibly break.

### R-1 — clean load and reload

1. Fresh login → `/reload` → `/reload` again. **Expected:** no Lua error popup at any point; the `[LH]` prefix appears on every printed line.
2. `/etrace` and confirm `ADDON_LOADED` → `PLAYER_LOGIN` → `PLAYER_ENTERING_WORLD` complete with no error.

### R-2 — first-time defaults

1. Log out. Delete `WTF/Account/<ACCT>/SavedVariables/LootHistory.lua` **and** `.lua.bak`.
2. Log in. `/lh list`. **Expected:** every setting reports its shipped default (`settings.enabled = true`, `settings.qualityThreshold = 1`, `settings.excludeQuestItems = true`, `settings.recordCurrency = true`, `settings.retentionDays = 30`, `settings.visibility = always`, `settings.rowHeight = 18`).
3. `/lh show`. **Expected:** the window opens, the table is empty, the footer reads `Database ≈ 0 B` (or the empty-history equivalent), and the settings General page reads `No items collected yet.`
4. `/reload`, then `/run print(LootHistoryDB.global.schemaVersion)`. **Expected:** `8` — a fresh DB walks the whole guarded chain and stamps the head.

### R-3 — combat enter/leave with the window open

1. `/lh set settings.visibility always`. `/lh show`. Engage a target dummy. **Expected:** the window stays up; no error; no `Interface action failed because of an AddOn` red text.
2. `/lh set settings.visibility outOfCombat`. Engage the dummy. **Expected:** the window **hides** on `PLAYER_REGEN_DISABLED`. Leave combat. **Expected:** it does **not** reopen by itself — that is documented behaviour (`modules/Browser.lua:1124-1128`), not a bug.
3. `/lh set settings.visibility inCombat`. Out of combat, `/lh show`. **Expected:** the chat line `the window is hidden by the General visibility setting.` and no window. Engage the dummy, then `/lh show`. **Expected:** it opens.
4. `/lh set settings.visibility never`. `/lh show`. **Expected:** the refusal line, no window.
5. Restore `always`.

### R-4 — the settings panel, opened both ways, every control touched

1. `/lh config`. **Expected:** the canvas opens on this addon's category.
2. Esc → **Options** → **AddOns** → **Ka0s Loot History**. **Expected:** the same page, no error, no duplicate category.
3. Walk the **General** page's tab strip: **Master controls**, then every other tab. On each, toggle every checkbox, move every slider to both ends, open every dropdown and pick each value, and drag one row in the AH price cascade.
4. Walk the **Filters** tabs (Blacklist / Whitelist / Currencies). Add an id, remove it, clear the list from the confirm dialog.
5. **Expected throughout:** no Lua error; every change is reflected by `/lh get <path>` immediately; the tab strip geometry does not shift as the selection moves.

### R-5 — saved-variable migration across a real reload

1. Restore the **pre-change** `LootHistory.lua` backup from pre-flight.
2. `/run print(LootHistoryDB.global.schemaVersion)` before anything else — record it.
3. `/lh debug on`, `/reload`, `/lh debug` and read the `[Migrate]` lines.
4. **Expected:** one `v<n> -> v<n+1>, <k> rows touched` line per step that ran, ending at `schemaVersion = 8`. No rows lost — `/run print(#LootHistoryDB.global.history)` before and after must match (every migration is non-destructive).
5. Wait 25 seconds after login and read the console for `bound repair: <f> fixed, <p> pending, <c> candidates (attempt <n>)` — two passes, at +5 s and +20 s.

### R-6 — the global reset is total, and the CLI reset is not

1. With a populated history: `/lh resetall`. **Expected:** settings return to defaults and the filter lists clear, but `/run print(#LootHistoryDB.global.history)` is **unchanged** — this form is non-destructive.
2. `/lh config` → **Master controls** → **Reset all settings**. Confirm the popup. **Expected:** the verbatim warning text, and after accepting, `#LootHistoryDB.global.history == 0`, the window recentred, the view back to stock, and the chat line `this addon reset to defaults.`
3. `/reload`. **Expected:** the reset persisted; no error.

### R-7 — capture still works end to end

1. `/lh set settings.enabled true`, `/lh set settings.qualityThreshold 1`.
2. Loot several items of mixed quality and at least one currency.
3. `/lh show`. **Expected:** every kept item appears with its source, quality colour, ilvl where applicable, bound mark and (if a price addon is installed) an AH price. Currency rows appear with `Type = Currency`.
4. `/lh set settings.qualityThreshold 3` and loot a white item. **Expected:** it is **not** recorded, and with `/lh debug on` the console shows `[Drop] … reason=quality`.
5. Restore the threshold.

---

## Sign-off

| ID | Tested? | Pass/Fail | Notes |
|---|---|---|---|
| C-01 | | | Estimate rises on identical data; both surfaces agree |
| C-02 | | | (headless — covered by the pre-flight suite) |
| C-03 | | | GC delta not larger; storage line still updates |
| C-04 | | | (documentation — no in-client step) |
| C-05 | | | (decision — no in-client step) |
| C-06 | | | All ten attribution paths resolve |
| C-07 | | | (headless — covered by the pre-flight suite) |
| C-08 | | | (headless — covered by the pre-flight suite) |
| C-09 | | | deDE warbound + Mass-variant deconstruct |
| C-10 | | | Degraded help omits `config`; nothing errors |
| C-11 | | | (mechanical — pre-flight suite is the check) |
| R-1 | | | Clean load / double reload |
| R-2 | | | Fresh defaults, schemaVersion 8 |
| R-3 | | | All four visibility modes across combat |
| R-4 | | | Panel both entry points, every control |
| R-5 | | | Migration chain, no rows lost, repair passes |
| R-6 | | | `resetall` non-destructive vs. global reset total |
| R-7 | | | End-to-end capture incl. currency and drop reasons |
