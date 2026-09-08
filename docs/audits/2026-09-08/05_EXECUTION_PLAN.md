# 05 — Execution Plan

Hand-off to the separate remediation engagement. Every step names its deviation ID. Figures here are
the same ones `02_DEVIATIONS.md` and `03_EVIDENCE.md` carry — **62** British-spelling hits across
**27** files, **2** unannotated load-bearing TOC positions, **4** unannotated conventional groups,
**719** suite cases, **59** lint files — and the three documents are read as one.

**Total work: two sprints, four steps, two GitHub issues (one here, one upstream).** Nothing here changes behavior.

---

## Sprint 1 — the three rows nobody else will catch (LH-56, LH-57, LH-58, LH-52)

Small, mechanical, and first because none of it depends on anything.

### Step 1 — annotate the two load-bearing TOC positions — `LH-56`, `LH-57`, `LH-58`

**Files:** `LootHistory.toc` only.

- [ ] Above `LootHistory.toc:48` (`core\CoreSetup.lua`), add the load-bearing comment naming
      `lib:New{ prefix = NS.PREFIX }` at file scope and `core\Namespace.lua` as what must precede it.
      Draft text in `04_TECHNICAL_DESIGN.md`.
- [ ] Above `LootHistory.toc:51` (`core\DebugLogSetup.lua`), add the load-bearing comment naming
      `NS.Constants.FONT_MONO` read at `:New` time and `core\Constants.lua` as what must precede it.
- [ ] Add one conventional-position line under each of the four unannotated group headers —
      `:15` `# Libraries`, `:29` `# Locales`, `:57` `# Defaults`, `:70` `# Settings` — following the
      form at `:34-35`. (`LH-58`, the SHOULD.)
- [ ] Leave the in-file blocks at `core/CoreSetup.lua:29` and `core/DebugLogSetup.lua:17` alone. They
      carry the full reasoning; the TOC carries the one sentence.

**Acceptance:** every position that resolves something at file scope carries a comment at its TOC line
naming what resolves. Re-derive the denominator the way `03_EVIDENCE.md` §9 did — read the seam files
and `core/Constants.lua`, do not count TOC lines — and confirm it is four, with four annotated.

**Green gate:** `lua tests/run.lua` → 719/0/0. `luacheck .` → 0/0 over 59 files.

### Step 2 — give the Analytics watch-list disposition an owner — `LH-52`

- [ ] `gh issue create` in this repo, labels `state:triaged` and `severity:low`. Title names the file
      and the seam, e.g. *"Peel modules/Analytics.lua: split the renderers from the formatting and
      segmenting helpers"*. Body: the file is 1178 lines in `layout-§1`'s on-notice band with zero
      warned functions, so this is size and not density; the seam is chart/section renderers versus
      the helpers they call; the peel was unblocked by the `Database:Stats` work and has been named
      *"next"* across six recorded runs.
- [ ] Edit **only** the Disposition cell at `docs/automated-tests/RESULTS.md:81` to name the issue
      number and drop *"Nothing tracks it"*. Everything else in that file is generated; the Disposition
      is `automated-tests-§4`'s one authored cell, so this edit is sanctioned.
- [ ] Do **not** touch the other three Band rows. Their *Accepted* dispositions are current.

**Acceptance:** `gh issue list --label "state:triaged"` returns the new issue, and
`RESULTS.md:81` names its number. Anti-pattern #53 closed.

**Note on durability:** the next runner pass regenerates `RESULTS.md` whole and carries the Disposition
forward verbatim **while the entry is unchanged**. It blanks the moment `Analytics.lua`'s LOC moves.
Keep the substance in the issue; the cell carries the number and one sentence.

---

## Sprint 2 — the dialect sweep (LH-55)

Bigger, and the only step with a regeneration in it. Runs second so the generated inventory is
regenerated once rather than twice.

### Step 3 — US-spell the 27 files — `LH-55`

Work in three passes, in this order, so the generated file is touched last.

- [ ] **Pass A — docs prose and `DEPENDENCIES.md` (29 hits, 9 files).** `docs/smoke-tests.md` (11), `docs/settings-panel.md`
      (5), `docs/ARCHITECTURE.md` (4), `docs/schema.md` (3), `docs/compat-layer.md` (2),
      `docs/testing.md`, `docs/performance.md`, `docs/module-map.md` (1 each), plus `DEPENDENCIES.md`
      (1). Read each line; do not blind-substitute.
- [ ] **Pass B — source and test comments (31 hits, 17 files).** `core/ItemSetup.lua` (4), `settings/Schema.lua` (3),
      `modules/Browser.lua` (3), `modules/Export.lua` (2), `modules/AuctionPrice.lua` (2),
      `core/MediaSetup.lua`, `core/Compat.lua`, `settings/Panel.lua` (1 each), and nine test files — `test_panel.lua` (2 of its 3 here, the third in Pass C),
      `test_itemsetup.lua` (3), `test_schema.lua` (2), `test_browser.lua` (2), and one each in
      `test_widgets.lua`, `test_mediasetup.lua`, `test_libka0s.lua`, `test_envsetup.lua`,
      `test_analytics.lua`.
- [ ] **Pass C — the one generated mirror (2 hits, 2 files).** Fix the test **name** at `tests/test_panel.lua:831`
      (`cancelled` → `canceled`), then regenerate:
      `lua tests/run.lua --list > docs/test-cases.md`. Do not hand-edit `docs/test-cases.md:723`.
- [ ] Re-run the §8 sweep from `03_EVIDENCE.md`, same scope (81 tracked `.lua`/`.md`/`.toc` files,
      `libs/`, `tests/_kit/` and the five frozen/generated `docs/` directories excluded), same lists
      copied whole from `localization.md:192-227` with `ALLOWED` removed as whole words first.
      **Expect `TOTAL HITS: 0`.**

**Acceptance:** the sweep returns zero over the same 81 files. `lua tests/run.lua` → 719/0/0 with one
renamed case. `luacheck .` → 0/0 over 59 files. `grep -c '^- ' docs/test-cases.md` → 719, and
`README.md:7`'s badge still reads `719%2F719` — a rename does not move the count, so an unchanged badge
is the correct outcome and a changed one means something else moved.

**Do not touch:** `libs/`, `tests/_kit/`, `locales/enGB.lua` (does not exist), and the frozen bundles
under `docs/audits/`, `docs/reviews/`, `docs/revendor/`, `docs/superpowers/` and
`docs/automated-tests/<run>/`. Those are the four exclusions `localization-§5` names, and rewriting a
frozen bundle would be a worse deviation than the one being fixed.

### Step 4 — propose the gate upstream — follow-on to `LH-55`

- [ ] Open an issue on `LibKa0s` proposing a test-kit gate carrying `localization-§5`'s `BRITISH` and
      `ALLOWED` lists **whole**, with the four exclusions named directory by directory in the gate
      itself. **Do not write a per-repo gate** — a private list is precisely what §5 was amended to
      stop, and it names two repos whose private lists went green over a real defect.
- [ ] Not a blocker for anything above. Filed so the sweep does not have to be re-run by hand next
      cycle.

---

## Not scheduled

| ID | Why |
|---|---|
| `LH-60` | Info. The hub is 458 lines against a ~400 SHOULD, every mandated section has spilled, and the largest is 58 lines against a ~60 MUST. `documentation-§3` tells an audit to report the shape and not argue the arithmetic. If it passes ~500, spill `## Standards compliance` — that decision is pre-made in `04_TECHNICAL_DESIGN.md`. |
| `LH-61` | Info. `packaging`'s strong-form check passes with zero unaccounted entries. Adding `- .claude` for a directory that does not exist would assert something untrue about the repo. The tension between §28's flat list and §29's presence-scoped check is upstream work in `WowAddonStandards`, not work here. |

---

## Sequencing summary

```
Sprint 1   Step 1  LH-56, LH-57, LH-58   LootHistory.toc            comments only
           Step 2  LH-52                 gh issue + RESULTS.md:81   one cell
Sprint 2   Step 3  LH-55                 27 files + 1 regeneration
           Step 4  (follow-on)           LibKa0s issue              no repo change
```

Steps 1 and 2 are independent of each other and of Step 3. Step 3 must precede any future
`run-automated-tests.sh` pass, or the inventory regenerates twice. Step 4 blocks nothing.

## What a re-audit should expect

| Row | After this plan |
|---|---|
| Root deviations | **0** open, from **6** |
| Total incl. dependents | **0**, from **7** |
| MUST failures | **0**, from **4** |
| Info observations | `LH-60`, `LH-61` — expected to recur as Info until the standard or the hub moves; both should be re-confirmed, not re-graded |
