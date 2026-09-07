# 04 — Technical design

Remediation for the nine roots and one dependent in `02_DEVIATIONS.md`. Keyed by ID. Nothing here
touches addon behavior: **not one `.lua` line under `core/`, `modules/` or `defaults/` changes**, and
the only source file in scope at all is `settings/Panel.lua`, for three texture constants.

Read against `02_DEVIATIONS.md` as one document — every figure quoted here is the figure quoted there.

---

## LH-45 — `.pkgmeta` accounts for every root dot-entry

**File:** `.pkgmeta` (one file, five lines).

The `ignore:` block at `:6-12` currently lists `.luacheckrc`, `.gitignore`, `docs`, `tests`, `_dev`,
`"*.bak"` and two `media/logos/` globs. Bring it to the section's template and satisfy the strong
form in the same edit:

```yaml
ignore:
  - .luacheckrc
  - .gitignore
  - .gitattributes   # dev-only: the repo's line-ending policy (line-endings)
  - .claude          # dev-only: agent tooling; never loaded by the client
  - .superpowers     # dev-only: agent tooling; never loaded by the client
  - .pytest_cache    # dev-only: pytest's cache, written by the dev toolchain
  - docs
  - tests
  - _dev
  - "*.bak"
```

`.claude/` does not exist in this repo today; listing it anyway is what the enumeration exists for —
the entry costs one line and survives the day the directory appears. `.pkgmeta` itself is the
packager's own input and stays shipped; add a one-line comment above `package-as:` saying so, so the
strong-form check has an answer for every entry rather than a silent exception.

**Risk:** none. The packager ignores unknown-but-absent paths.
**Verify:** re-run both loops from `03_EVIDENCE.md` §1.8; the first prints nothing and the second
prints only `UNACCOUNTED — .git`.

---

## LH-46 — renormalize the working tree against the declared pin

**Files:** nine tracked files, none named here on purpose.

`.gitattributes` is already correct and canonical, so this is a one-command repair, not a policy
change:

```sh
git add --renormalize .
git commit -m "chore: renormalize the working tree against the CRLF pin (LH-46)"
# then a fresh checkout of the affected paths so the working tree matches the index
git rm --cached -r . -q && git reset --hard
```

Two of the nine live inside the frozen `docs/revendor/2026-08-25/` bundle. Renormalizing them changes
line endings only — no content, no rewritten history — so it does not breach the frozen-run rule,
which forbids *editing* a bundle's substance. Say so in the commit message so a later reader does not
read the diff as a frozen bundle being touched.

**Risk:** low, but the diff is wide. Do it in its **own commit**, before anything else in this plan,
so no substantive change is buried inside a whitespace sweep. `luacheck .` and `lua tests/run.lua`
must both stay green across it; `tests/_kit/vendor_sync.lua` already strips CR from the working-tree
side before comparing, so the vendored-payload gate is unaffected either way.

**Verify:** the `03_EVIDENCE.md` §1.7 (e) command prints `0`.

---

## LH-47 / LH-48 / LH-54 — three register acts, one edit to one table

**File:** `docs/ARCHITECTURE.md`, `## Documented deviations` (`:377-396`) and the *"Retired,
deliberately not rows"* paragraph that follows it (`:397-404`).

These three are separate findings with separate causes, but they are one edit to one table and should
land together — a register that is repaired in three commits is three chances to leave it half-done.

**LH-54 — retire the fired row.** Delete the second `architecture-§5` row (`:392`) from the table and
add a sentence to the retired paragraph, in the shape the two entries already there use: the
`sessionOnly` row kind is now named by `options-ui-§15` (*"Debug console belongs here, as a
session-only row"*) and by `options-ui-§12` (the reset walk **MUST** keep session-only rows), so
there is nothing left to deviate from. Also trim the third paragraph of `## Standards compliance`
(`:311-316`), which still describes the same thing as *"raised and flagged … still open for the next
standards-audit"* — that sentence is now false and is the second copy the retirement has to reach.

**LH-48 — add the localization row.** `localization-§3` names the exact shape:

```markdown
| `localization-§1` | No user-facing string routes through `NS.L`; every label, tooltip and message is hardcoded English. | The addon ships English only. Both of `localization-§3`'s MUSTs are met — `NS.L` is exported (`locales/enUS.lua:5`) and `enUS.lua` ships with no dead keys — and `localization-§3` makes *English-only, recorded* a terminal compliant state. | 2026-09-07 | The first non-English locale file added to `locales/`. |
```

Then shorten `locales/enUS.lua:7-9`'s comment to point at the row rather than restating the argument,
so the decision has one home.

**LH-47 — resolve the unregistered decline.** Two acceptable outcomes; pick one and write it down.

- *If the decline still stands* — the AH Price tab keeps its own pooled row host outside the
  library's `ClearScroll` lifecycle — add a row citing `options-ui-§1`, Why citing issue #21 and the
  measured ~1.7 s tab-transition freeze, Decided 2026-08-01 (the original decision date, not today),
  and a trigger naming what would end it (`RenderGrid`/the renderer contract gaining a `parent`, or
  the page's frame count dropping below the freeze threshold).
- *If R6 superseded it* — the whole General page now runs through `O.SetRenderer`
  (`settings/Panel.lua:990`) — close #21 with a comment saying so and add nothing. The comment is the
  record; the register stays clean.

The one unacceptable outcome is the present state, where neither is true and nothing says which.

**Risk:** none — documentation only. **Verify:** the register has five rows again (one retired, one
added, one possibly added), each with a Rule, a Decided date and a trigger a reader can evaluate; and
`gh issue view 21` either points at a register row or is closed as superseded.

---

## LH-49 / LH-50 — cut a fresh bundle and rewrite the standing prose

**Files:** a new `docs/automated-tests/<stamp>/` bundle plus `docs/automated-tests/RESULTS.md`.

`RESULTS.md` is **generated** and its numbers must never be hand-edited (`automated-tests-§4`,
`performance-§10`) — a hand-edited record is worse than a stale one because it reads as measured. So
the fix is to **run the runner**, not to correct the file:

```sh
tests/_kit/run-automated-tests.sh
```

That regenerates the table row, the band table and the runner-authored lead-in. What the runner does
**not** write, and what this step owes by hand, is the four standing prose sections — Test suite,
Lint, Perf, Complexity watch list — which today read 594 cases (`:33`), 23 lint files (`:58`) and
*"Current state as of 20260807-114650"* (`:91`) against a table whose newest row is
`20260825-103428`. Rewrite each against the numbers the new run produced, and say in the Complexity
section that `settings/Panel.lua` has **newly** entered the 1000–1500 band at 1004 LOC with its own
disposition — `automated-tests-§4` requires a disposition for anything that newly crossed, and a
regeneration that yields none *"has performed the ritual and skipped the point"*.

**LH-50** rides the same run: write the bundle's `ANALYSIS.md` from the uniform prompt in the
standard's root `AUTOMATED_TESTS.md`, linking each suite's artifact from the row that reports it and
reporting complexity with **totals and averages both**. Do not retro-fit analyses into the two frozen
bundles that lack one — those are frozen; the debt is discharged going forward.

**Ordering constraint:** run this **after** LH-46, or the renormalization will move NLOC and lint
file counts underneath a bundle that has just been cut.

**Risk:** none to the addon. **Verify:** the newest `RESULTS.md` row matches today's `lizard` and
suite output to the digit; the band table lists four files; the bundle carries an `ANALYSIS.md`.

---

## LH-51 — README back to the canonical structure

**File:** `README.md`.

`## Unreleased` (`:36-40`) holds two genuinely user-facing entries — the Insights pool leak and the
coalesced repaint. They are not deleted; they are **promoted**. The next version bump
(`wow-addon:bump-version`) is where they belong: they become the new `## What's new in <next>`
bullets and the new top `## Version History` row, in the same change that moves the TOC `## Version:`
and the `[wow]`/`[tests]` badges. Then the `## Unreleased` heading goes. Until that bump, the
addon has shipped work that no release names — which is the substance behind this finding as much as
the heading is.

`## Auction-house pricing` (`:141-147`) is player-facing content in the wrong slot. Fold it into
`## How attribution works` (`:149`) as a short subsection, or — if it reads as engineer material —
move it under `docs/` and link it from `## Usage`. Do not simply reorder it; the canonical list has
no slot for it.

**Risk:** none. **Verify:** `grep -n '^## ' README.md` yields only headings from
`documentation-§1`'s list, in its order.

---

## LH-52 — give the watch-list entry an owner

**Files:** the issue store, then `docs/automated-tests/RESULTS.md`'s band-table disposition (via the
generator, in the LH-49 run).

`modules/Analytics.lua` is 1178 LOC and has read *"peel next"* for five recorded runs. Two paths:

- **Track it.** Open an issue titled for the peel, labeled `state:triaged` and `severity:low`, body
  naming the seam the record already identifies — split the chart **renderers** from the
  **formatting/segmenting** helpers — and repoint the disposition at that issue number. This is the
  cheap path and it is what `automated-tests-§4`'s *"already tracked as `<deviation-id>`"* clause is
  for.
- **Do it.** `modules/Analytics.lua` is 921 NLOC across 78 functions with avg CCN 2.5 and no warned
  function, so the peel is a file split rather than a complexity refactor. If it is done, it is done
  under `performance-§11`: named helpers a reader would recognize, no dispatch table moved *into* a
  function, and `tests/test_analytics.lua`'s 62 cases pinning behavior across the move.

Note the honest position in whichever record carries it: the **letter** of the three-release shelf
life has not been reached, because no run in the record is a release run. The finding is on the
substance.

**Risk:** none on the tracking path.

---

## LH-53 — three marks through the catalog

**File:** `settings/Panel.lua:459-461` — the only source change in this plan.

```lua
-- before
local READY     = "Interface\\RaidFrame\\ReadyCheck-Ready"
local NOTREADY  = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local INFO_ICON = "Interface\\FriendsFrame\\InformationIcon"

-- after: catalog first, Blizzard art as the degraded fallback, exactly as every other
-- art site in this addon already does (modules/BrowserTable.lua:80, :105, :259-260)
local READY     = (NS.Icon and NS.Icon("circle-check")) or "Interface\\RaidFrame\\ReadyCheck-Ready"
local NOTREADY  = (NS.Icon and NS.Icon("cancel"))       or "Interface\\RaidFrame\\ReadyCheck-NotReady"
local INFO_ICON = (NS.Icon and NS.Icon("info"))         or "Interface\\FriendsFrame\\InformationIcon"
```

**One ordering constraint that matters:** these are **file-scope** locals in `settings/Panel.lua`,
which the TOC loads at `:78`, well below `core/MediaSetup.lua` at `:43`, so `NS.Icon` is resolved by
then. `NS.Icon` answering `nil` is a real answer on a degraded install (`core/MediaSetup.lua:49`), and
the `or` tail is what handles it — do not drop it.

If the maintainer prefers the current art — the ReadyCheck tick is a recognizably Blizzard "collecting"
signal and the catalog's `circle-check` may read differently at 12 px — that is equally compliant, but
then write the reason beside them the way `modules/Browser.lua:1048-1051` does for the size grabber.
A recorded decision closes this; silence does not.

**Risk:** cosmetic only. `tests/test_panel.lua` and `tests/test_mediasetup.lua` already exercise the
`NS.Icon`-answers-nil path; add one case asserting the three constants fall back when `NS.Icon` is
absent, so the degraded shape is pinned rather than assumed.

---

## What this plan deliberately does not do

- **It does not re-open the five ratified register rows.** Four are accepted with unfired triggers;
  the fifth is retired by LH-54 because its trigger fired, not because the decision was wrong.
- **It does not wire a performance harness.** `performance-§12`'s exemption is ratified, its
  criterion (a) sweep is committed, and today's re-check confirms it: zero `SetScript("OnUpdate")`
  sites, no repeating ticker, no in-combat handler doing real work.
- **It does not restructure `docs/ARCHITECTURE.md` for length.** 434 lines with every mandated
  section under the spill line is the shape `AUDIT.md` says to report and not to file.
- **It does not touch `libs/LibKa0s/` or `tests/_kit/`.** Both diff empty against v1.25.0; a local
  edit to either is anti-pattern #47 and would break the kit's own byte-identity assertion.
