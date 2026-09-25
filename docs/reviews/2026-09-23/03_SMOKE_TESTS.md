# LootHistory — In-Client Smoke Tests (2026-09-23)

This checklist covers only what the game client can verify. The headless suites already ran in
Step 0 (see 01 → Measurement run). After the changes land, re-run them once as a pre-flight check:

```
~/.claude/wow-addon/bin/ka0s-bounded lua5.1 tests/run.lua    # expect ~866 passed, 0 failed
~/.claude/wow-addon/bin/ka0s-bounded luacheck .              # expect 0 / 0
```

## Pre-flight

1. Use a Retail client, `## Interface: 120100` (12.1.0). Copy the working tree to
   `Interface/AddOns/LootHistory/` and keep `libs/LibKa0s/` in place.
2. Type `/console scriptErrors 1`, then `/reload`. Keep BugSack or the default error frame visible.
3. Back up `WTF/Account/<acct>/SavedVariables/LootHistory.lua` before starting. Several steps
   inspect stored rows.
4. Turn on the debug trace with `/lh debug on`, then open the console with `/lh debug`. Most checks
   below read `[Attr]`, `[Open]` and `[Prune]` lines.
5. You need a character that can run a Mythic+ key, or at least enter and leave a dungeon. For S-003
   you need gathering professions and a currency the account has not seen yet.

## Per-change tests

### S-001 — C-001: keystone context ends when you leave the instance

- **Setup:** a keystone in your bags. The History window open on the History tab, sorted by Date.
- **Steps:**
  1. Start the key (`CHALLENGE_MODE_START`). In the console, confirm
     `[Attr] keystone start +N (GameObject loot → MPLUS)`.
  2. Finish the key, or at least one boss, and loot the end chest. Confirm the new row reads Source
     **Mythic+**.
  3. Note what `/run print(C_ChallengeMode.GetActiveKeystoneInfo())` prints after completion. This
     verifies the unverified `0` note in F-001.
  4. Leave the instance (teleport out). Confirm `[Attr] keystone context cleared (left instance)`.
  5. In the open world, mine a node or pick an herb, **without** `/reload`.
- **Expected:** the gathered item's row reads Source **Container**, not **Mythic+**. The Insights
  keystone breakdown does not grow.
- **Pass / Fail:** PASS only if step 2 is Mythic+, **and** step 5 is Container, **and** no Lua error
  appeared.
- **Regression variant:** zone between sub-areas inside the dungeon during the key, then loot the
  chest. It must still read Mythic+. `ZONE_CHANGED_NEW_AREA` fires inside, and the instance guard
  must hold the context.

### S-002 — C-002: encounter detail on boss loot (and a check that F-002 is real)

- **Setup:** any dungeon or raid boss you can loot from the corpse. Normal difficulty is fine.
- **Steps:**
  1. Pull and kill the boss. In the console, note the order of `[Attr] encounter end` and
     `[Open] LOOT_OPENED …`.
  2. Loot the corpse.
  3. `/reload`, then open `LootHistory.lua` in SavedVariables and look at the new row's
     `sourceDetail`. There is no export verb, and the CSV does not export `sourceDetail`.
- **Expected, after the change:** `sourceDetail` carries `encounterID` and `difficulty`.
- **Pass / Fail:** PASS if the fields are present. If step 1 shows `LOOT_OPENED` **before**
  `encounter end`, record that: F-002 is then not reproduced and C-002 should be reverted or dropped.

### S-003 — C-003: first-ever currency gets a Type subcategory

- **Setup:** loot any currency first, so the category cache gets built this session. Then find a
  currency this account has **never** held.
- **Steps:** loot the new currency and open the History window.
- **Expected:** the row's Type subcategory (the currency header, e.g. the expansion name) is filled
  in, not blank.
- **Pass / Fail:** PASS if the subtype is non-empty without a `/reload`.

### S-004 — C-004: shortening retention asks before deleting

- **Setup:** history with records older than 7 days, and retention at *Never*.
- **Steps:**
  1. Settings → General → History → *Keep history for* → **7 days**.
  2. When the confirm appears, click **No**.
  3. Confirm the row count is unchanged: look at the *Database size* readout, or the History footer.
  4. `/reload`. Type `/lh debug on` immediately, because the debug flag is session-only and off
     after a reload. Then wait about 5 s.
- **Expected:**
  - Step 1 shows a popup naming N records.
  - Step 2 prints `retention set; N older records will be removed at your next login.`
  - Step 3 shows no change in count.
  - After step 4, the console shows `[Prune] retention 7d: removed N rows` (if `debug on` landed
    inside the 5 s window), and the row count has dropped by N either way.
- **Pass / Fail:** PASS only if no record disappears before step 4.
- **Variant:** repeat with **Yes**. The records go immediately, and the History window repaints.

### S-005 — C-005: degraded refusal line (library absent)

- **Setup:** rename `libs/LibKa0s/LibKa0s.xml` to `LibKa0s.xml.off`. In SavedVariables, set
  `settings.enabled = false` with the game closed. Then log in.
- **Steps:** type `/lh show`.
- **Expected:** exactly one line, `[LH] Ka0s Loot History is disabled — enable it with /lh enable`,
  with `/lh enable` in gold.
- **Pass / Fail:** PASS if it is one line in exactly that shape. **Restore the XML afterward.**

### S-006 — C-006: Insights and export cost (no perf harness, so memory is the proxy)

- **Setup:** a large history, 5k+ rows. Use `/lh test` if the live history is small; the synthetic
  dataset is large. AH pricing on, with at least one provider installed.
- **Steps:**
  1. `/run collectgarbage("collect"); print(collectgarbage("count"))`.
  2. Open Insights and switch the date range three times.
  3. `/run print(collectgarbage("count"))`.
  4. Do the same before and after the change, on the same machine and the same dataset.
- **Expected:** the post-change delta in step 3 is lower than the pre-change delta. Record both numbers
  in 05. Also use the History window's Export button over the full set: the CSV must be identical before and after, apart
  from the C-011 label change.
- **Pass / Fail:** PASS if the CSV is unchanged (modulo C-011) **and** the memory delta did not grow.
  This proxy is noisy, so do not claim a percentage from it.
- **Also:** reorder the AH price table in Settings, then export. The `auctionSource` column must follow
  the new order. That checks the compiled plan was refreshed.

### S-007 — C-009: *Lock frame* also stops resizing

- **Steps:** tick *Lock frame*, then drag the History window's bottom-right grip.
- **Expected:** the window neither moves nor resizes. Untick the box and the grip resizes again.
- **Pass / Fail:** PASS if the size is unchanged while locked.

### S-008 — C-011, C-012, C-013: labels and tooltip

1. Export both CSVs, the History one and the Insights one. The bound labels read the same in both:
   "Bind on Pickup" / "Not Bound", and so on.
2. Hover over the minimap button. The first line is `Ka0s Loot History` (from `NS.BRAND`), and it
   offers "show/hide".
3. `/lh disable`, then hover again. The left-click line is replaced by the gray disabled line.
   `/lh enable` afterwards.
4. Degraded path (reuse S-005's setup): open Settings → General → Filters. If it renders, click
   Defaults. The chat line names the number of ids cleared.

### S-009 — C-014, C-015: repair and export copy

- **C-014:** smoke-testable only by hand-editing a row to have an `itemLink` and no `itemID`. Optional;
  the headless case covers it.
- **C-015:** no in-client effect. The headless case covers it.

## Regression suite

- [ ] `/reload` clean: no Lua errors, and the `[LH]` tag is cyan.
- [ ] Fresh SavedVariables (move `LootHistory.lua` aside): the defaults populate, the minimap button
      shows, and `/lh` opens the settings panel.
- [ ] The login sequence `ADDON_LOADED` → `PLAYER_LOGIN` → `PLAYER_ENTERING_WORLD` shows no errors.
      Debug is off after a reload, so the 5 s `[Prune]` and bound-repair lines only show if
      `/lh debug on` is typed first.
- [ ] Loot a normal mob, a container from your bags, a vendor purchase and a mail attachment. They
      record as Kill / Container / Vendor / Mail.
- [ ] Combat enter and leave with the window open under each *Visibility* setting. Test mode ends on
      combat start and prints one line.
- [ ] `/lh disable`: loot a mob, and **no** row is recorded. The window is refused, and the minimap
      left-click prints the refusal. Right-click still opens settings. Then `/lh enable`: loot again,
      and the row is recorded.
- [ ] Settings panel: open every tab and toggle each option once. Defaults and *Reset all settings*
      popups appear. The minimap button stays hidden across *Reset all settings* if you had hidden it.
- [ ] **Cross-addon:** with the other Ka0s addons loaded, type each root and confirm it reaches its own
      addon: `/at`, `/am`, `/bl`, `/cm`, `/kcd`, `/lh`, `/mm`, `/pm`, `/pc` and `/wg`. Then open
      Settings → AddOns: every addon appears exactly once, and each multi-page addon's pages appear
      once each.

## Taint-specific tests

No taint findings were raised. The five `hooksecurefunc` hooks are unchanged. As a spot check, buy
from a vendor and take mail in combat-adjacent situations, and confirm no
`Interface action failed because of an AddOn` message appears.

## Localization sanity

Not applicable. The addon is English-only, as a documented deviation (`localization-§1` row in
ARCHITECTURE.md), and no change touches a localized pattern.

## Sign-off

| ID | Tested? | Pass/Fail | Notes |
|---|---|---|---|
| C-001 / S-001 | | | |
| C-002 / S-002 | | | Record the event order, even on FAIL |
| C-003 / S-003 | | | |
| C-004 / S-004 | | | |
| C-005 / S-005 | | | Restore `LibKa0s.xml` after |
| C-006 / S-006 | | | Before/after `collectgarbage` numbers |
| C-007 | n/a (headless) | | |
| C-008 | n/a (headless) | | |
| C-009 / S-007 | | | |
| C-010 | n/a (comments/docs) | | |
| C-011 / S-008.1 | | | |
| C-012 / S-008.2-3 | | | |
| C-013 / S-008.4 | | | |
| C-014 / C-015 | n/a (headless) | | |
| Regression suite | | | |
