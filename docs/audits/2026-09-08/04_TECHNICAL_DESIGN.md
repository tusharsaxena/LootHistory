# 04 — Technical Design

Remediation for the six roots and one dependent in `02_DEVIATIONS.md`. Keyed to deviation IDs.

**Nothing here touches behavior.** Every change is a comment, a doc word, a TOC annotation or a GitHub
issue. No `.lua` control flow, no schema row, no stored value and no rendered string moves, so the
suite and lint are regression detectors here rather than acceptance criteria — but both still have to
stay green, and `docs/test-cases.md` has to be regenerated once because one test **name** changes.

---

## LH-52 — the Analytics watch-list disposition has no owner

**Section:** `automated-tests-§4`, anti-pattern #53. **Grade:** Low.

### What is actually wrong

Nothing about `modules/Analytics.lua` is a breach. At 1178 lines it sits in `layout-§1`'s 1000–1500
on-notice band, which **is** the compliant state, and it carries no function `lizard` warns on. The
defect is the **Disposition cell**: it has read *"Peel next"* across six recorded runs and names no
owner, which is anti-pattern #53's definition of a disposition that has stopped being a decision. The
row says so about itself.

### Two exits, and only two

1. **File the issue.** `automated-tests-§4` makes the Disposition the one authored cell in a generated
   file, so the cell may name an issue number. Open a `state:triaged` issue with a `severity:low`
   label describing the peel seam concretely — `modules/Analytics.lua` splits into the chart/section
   **renderers** and the **formatting and segmenting helpers** they call — and repoint the cell at it.
2. **Do the peel.** Out of scope for a measurement cycle and explicitly declined for this one
   (`03_SPEC.md` § C22).

**Take (1).** The issue is the artefact the standard asks for; the peel is a design change that wants
its own engagement.

### Shape of the change

- One `gh issue create` with `state:triaged` and `severity:low` labels. Throttle: this is a single
  call, but the collection-wide rule against bulk API writes still applies if it is batched with
  anything else.
- One edit to `docs/automated-tests/RESULTS.md:81`'s Disposition cell, replacing *"Nothing tracks it"*
  with the issue number. **This is the file's one hand-editable cell** — everything else in it is the
  runner's output — so the edit is legitimate and does not make the file hand-maintained.

### Risk

The next `tests/_kit/run-automated-tests.sh` run regenerates `RESULTS.md` whole and **carries the
Disposition forward verbatim while the entry is unchanged**. The entry (file, band, LOC) will change
the moment `Analytics.lua` moves a line, at which point the cell is blanked and the issue link is lost.
Mitigation: put the substance in the issue, not in the cell — the cell carries the number and one
sentence.

---

## LH-55 — 62 British spellings

**Section:** `localization-§5`. **Grade:** Low.

### Shape of the change

One sweep over 27 files, ten substrings. It is mechanical, but three parts are not:

1. **`docs/test-cases.md` is generated.** Its single hit (`:723`) mirrors a **test name** at
   `tests/test_panel.lua:831`. Fix the test name, then regenerate:
   `lua tests/run.lua --list > docs/test-cases.md`. Editing the doc directly would be undone by the
   next regeneration and would put the two out of step in the meantime.
2. **Three hits are inside assertion messages** (`tests/test_itemsetup.lua:96`,
   `tests/test_panel.lua:610`, `:840`). Changing them changes what a failing run prints, which is
   fine, but they must be changed with the surrounding comment so the file reads as one dialect.
3. **`docs/smoke-tests.md` carries 11**, most of them `centre`/`centred` in geometry descriptions a
   human reads while clicking through the client. These are the highest-value fixes for a reader and
   the lowest-risk to make.

**No shipped player-facing string is affected**, so there is no locale-key ripple: `localization-§5`'s
warning that *"a spelling fix in a locale key is a key change"* does not bite, because none of the 62
hits is a key or a rendered label. Confirmed by the comment-stripped sweep in `03_EVIDENCE.md` §8.

### Guard against recurrence

The sweep will drift back. `localization-§5` says every **mechanical gate MUST use the published lists
whole** — it does not mandate that a gate exist, but this repo has 27 files' worth of evidence that
prose enforcement fails here. The right home is `LibKa0s`'s test kit rather than this repo: a private
per-addon list is exactly what §5 was written to stop, and a kit gate would carry the published lists
once for all ten repositories. **Propose it upstream; do not write a local one.** That is a separate
item and is not scheduled here.

### Risk

Low, but real in one direction: a careless `sed 's/colour/color/g'` would rewrite Blizzard symbols if
any were in scope. None are — the sweep's hits are all comment or prose text — but the fix must be
applied per-hit with the line read, not as a blind global substitution across the tree.

---

## LH-56 / LH-57 / LH-58 — TOC position annotations

**Section:** `toc-file-§5`. **Grades:** Low / Low / Low.

### Design

Three edits to one file, `LootHistory.toc`, in one commit. The existing annotations at `:34-35`,
`:37-39`, `:41-42` and `:71-74` are the house style and the new ones copy it: the constraint and its
reason, at the line, naming **what resolves**.

**LH-56 — above `LootHistory.toc:48`:**

```
# LOAD-BEARING POSITION: core\CoreSetup.lua builds the printer at FILE SCOPE
# (`lib:New{ prefix = NS.PREFIX }`), so core\Namespace.lua must have published
# NS.PREFIX above it. Below Namespace and every [LH] chat line loses its tag.
```

**LH-57 — above `LootHistory.toc:51`:**

```
# LOAD-BEARING POSITION: the DebugLog descriptor reads NS.Constants.FONT_MONO at
# :New time, so core\Constants.lua must be above. Below it and the console silently
# falls back to the client font.
```

**LH-58 — one line per unannotated group** at `:15`, `:29`, `:57`, `:70`, saying the positions under
it are conventional. `LootHistory.toc:34-35` is the model — it states the position is free *and why it
is free despite being a seam*, which is the part that stops the next reader re-deriving the graph.

### Why the in-file comments do not already satisfy the MUST

`core/CoreSetup.lua:29` and `core/DebugLogSetup.lua:17` both state the constraint, correctly and in
detail. §5 requires it **at the TOC line** because that is where a maintainer reordering the listing is
looking; a constraint recorded only in the file being moved is invisible at the moment of the move.
Keep both — the in-file blocks carry the full four-constraint reasoning and the TOC line carries the
one sentence.

### Risk

None. Comments only; no line moves.

---

## LH-60 — the hub is 458 lines

**Section:** `documentation-§3`. **Grade:** Info. **No change this cycle.**

Every mandated section has spilled and the largest is 58 lines, inside the ~60 MUST. The file is long
because it legitimately carries four register tables and five ratified deviation rows. `documentation-§3`
says the failure the numbers catch is 1071 lines, and explicitly tells an audit to report the shape
rather than argue the arithmetic.

**If it becomes worth acting on**, the section to spill is `## Standards compliance` (55 lines): it is
the one mandated section with no canonical Tier 1 destination and the one most likely to keep growing,
and it would go to a new Tier 3 page registered in `### Addon-specific`. Recorded here so the decision
is pre-made rather than improvised at the threshold.

---

## LH-61 — `.claude` and `packaging`'s two forms

**Section:** `packaging`. **Grade:** Info. **No change to this repo.**

The strong form passes with zero unaccounted entries. Adding `- .claude` for a directory that does not
exist would satisfy §28's list and weaken the file: it would assert a fact about the repo that is not
true, and the `.pkgmeta` comment at `:11-18` already records that a sibling repo's identical filing was
rejected this cycle for exactly that reason.

The tension is upstream. `packaging-§28` reads as a flat MUST list; `packaging-§29` scopes the real
check to entries **present in the repo** and calls §28 the weak form. Both readings are defensible from
the text, which is why this row exists at all. **If it is worth settling, settle it in
`WowAddonStandards`** — one sentence in §28 saying the list is a template whose entries bind only when
the entry exists. Not a change to this addon.

---

## Ordering constraints

- **LH-55 before any `RESULTS.md` regeneration.** The spelling fix changes a test **name**, which
  changes `docs/test-cases.md` and the generated case inventory in the next run bundle. Doing it after
  a regeneration means regenerating twice.
- **LH-52's `RESULTS.md` edit last**, for the same reason in reverse: it is a hand-edit to the one
  authored cell and should sit on top of whatever the last regeneration produced.
- **LH-56/57/58 are independent** of everything else and can land at any point.
- **LH-60 and LH-61 are no-ops** and order nothing.

## Verification

Green gate after each commit: `lua tests/run.lua` (expect 719/0/0, or 719 with one renamed case after
LH-55) and `luacheck .` (expect 0/0 over 59 files). After LH-55, additionally confirm
`grep -c '^- ' docs/test-cases.md` still equals the run's total and that `README.md:7`'s badge still
matches it — a renamed case does not move the count, so both should be unchanged at 719.
