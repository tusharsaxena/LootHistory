# 05 — Execution plan

Ordered, checkable remediation for `docs/audits/2026-09-07/`. Every step names its deviation ID and
its verification. Read with `02_DEVIATIONS.md` and `04_TECHNICAL_DESIGN.md` — the figures in all three
are the same figures.

**Scope of the whole plan: one source file, three lines** (`settings/Panel.lua:459-461`, and only if
the maintainer picks the catalog over the current art). Everything else is config, records and
documentation.

**Standing gate for every step:** `luacheck .` at `0/0` and `lua tests/run.lua` green
(**699 passed, 0 failed, 0 skipped** as of this audit).

---

## Sprint 0 — the whitespace sweep, alone

Its own sprint because a wide whitespace diff must not carry anything else inside it.

| # | Step | IDs | Files | Verify |
|---|---|---|---|---|
| 0.1 | `git add --renormalize .`, commit alone, then re-checkout so the working tree matches the index. Commit message states that two of the nine files sit in the frozen `docs/revendor/2026-08-25/` bundle and that only line endings change. | **LH-46** | 9 tracked files | The `03_EVIDENCE.md` §1.7 (e) command prints **`0`**. Gate green across the commit. |

_Commit:_ one, `chore: renormalize the working tree against the CRLF pin (LH-46)`.

---

## Sprint 1 — the register, in one edit

The three register acts land together. A register repaired in three commits is three chances to leave
it half-done.

| # | Step | IDs | Files | Verify |
|---|---|---|---|---|
| 1.1 | Delete the `sessionOnly` row (`docs/ARCHITECTURE.md:392`) and add its retirement sentence to the *"Retired, deliberately not rows"* paragraph (`:397-404`), citing `options-ui-§15` and `options-ui-§12` as the rules that closed it. | **LH-54** | `docs/ARCHITECTURE.md` | The table has no `sessionOnly` row; the retired paragraph names it with both rules. |
| 1.2 | Rewrite `## Standards compliance`'s third paragraph (`:311-316`), which still calls the same thing *"raised and flagged … still open for the next standards-audit"* — now false. | **LH-54** | `docs/ARCHITECTURE.md` | No surviving sentence describes the `sessionOnly` kind as an open deviation. |
| 1.3 | Add the `localization-§1` row, Decided 2026-09-07, trigger *"The first non-English locale file added to `locales/`"*. Shorten `locales/enUS.lua:7-9` to point at the row instead of restating the argument. | **LH-48** | `docs/ARCHITECTURE.md`, `locales/enUS.lua` | The row exists with all five columns. `localization-§3`'s state 2 is now satisfied, so the next audit records it as accepted rather than re-filing the routing SHOULD. |
| 1.4 | **Decide issue #21 and record the decision.** Either add an `options-ui-§1` row (Why citing #21 and the measured ~1.7 s tab-transition freeze, Decided **2026-08-01**, trigger naming what would end it), or close #21 with a comment saying R6 superseded it because the General page now runs through `O.SetRenderer` (`settings/Panel.lua:990`). Not both, not neither. | **LH-47** | `docs/ARCHITECTURE.md` or the issue store | `gh issue view 21` either cites a register row or is closed as superseded; no `state:will-not-do` issue declining a standards rule is left without a home. |

_Commit:_ one, `docs(register): retire the fired sessionOnly row, record English-only, resolve #21 (LH-47/48/54)`.

**Note the ordering:** 1.4 is the only step in this plan that needs a **maintainer decision** rather
than an edit. If that decision is not available, do 1.1–1.3 and leave 1.4 open with its ID — do not
invent an answer for it.

---

## Sprint 2 — config and the README

| # | Step | IDs | Files | Verify |
|---|---|---|---|---|
| 2.1 | Bring `.pkgmeta`'s `ignore:` to the template: add `.gitattributes`, `.claude`, `.superpowers`, `.pytest_cache`, each with the template's comment; add a one-line comment above `package-as:` covering `.pkgmeta` itself. | **LH-45** | `.pkgmeta` | Both loops in `03_EVIDENCE.md` §1.8 print nothing but `UNACCOUNTED — .git`. |
| 2.2 | Fold `## Auction-house pricing` (`README.md:141-147`) into `## How attribution works` (`:149`) as a subsection, or move it under `docs/` and link it from `## Usage`. | **LH-51** | `README.md` | `grep -n '^## ' README.md` yields only `documentation-§1` headings. |
| 2.3 | Route the three AH-table marks through the catalog with the Blizzard paths as the `or` fallback — **or** write the reason beside them the way `modules/Browser.lua:1048-1051` does. Add one `tests/test_panel.lua` case pinning the fallback when `NS.Icon` is absent. | **LH-53** | `settings/Panel.lua:459-461`, `tests/test_panel.lua` | Gate green; case count moves 699 → 700 and `docs/test-cases.md` is regenerated in the same change. |

_Commit:_ two — `pkg: account for every root dot-entry (LH-45)` and
`docs+settings: README structure and the shared icon catalog (LH-51/53)`.

---

## Sprint 3 — the record catches up with the code

Runs **after** Sprint 0 and Sprint 2, or it measures a tree that is about to change underneath it.

| # | Step | IDs | Files | Verify |
|---|---|---|---|---|
| 3.1 | Open a `state:triaged` / `severity:low` issue for `modules/Analytics.lua`'s peel, naming the renderers-vs-helpers seam the record already identifies. | **LH-52** | issue store | The issue exists; the band-table disposition can now cite it. |
| 3.2 | Run `tests/_kit/run-automated-tests.sh`. The table row, band table and generated lead-in are **regenerated, never hand-edited**. | **LH-49** | new `docs/automated-tests/<stamp>/`, `RESULTS.md` | The newest row matches today's `lizard` and suite output to the digit. |
| 3.3 | Rewrite `RESULTS.md`'s four standing prose sections — Test suite (`:33`, currently 594), Lint (`:58`, currently 23 files), Perf, Complexity watch list (`:91`, currently *"as of 20260807-114650"*) — against the numbers the new run produced. Give `settings/Panel.lua` (1004 LOC) its **own disposition** as a newly-crossed band file, and point `modules/Analytics.lua`'s at 3.1's issue. | **LH-49**, **LH-52** | `RESULTS.md` | No prose figure contradicts the table; the band table lists **four** files; nothing newly crossed lacks a disposition. |
| 3.4 | Write the new bundle's `ANALYSIS.md` from the root `AUTOMATED_TESTS.md` prompt: each suite's artifact linked from the row that reports it, complexity with **totals and averages both**. Do not retro-fit analyses into the two frozen bundles that lack one. | **LH-50** | `<stamp>/ANALYSIS.md` | The file exists and every number in it cites a file in its own directory. |

_Commit:_ one, `test(record): fresh four-suite bundle and an honest watch list (LH-49/50/52)`.

---

## Sprint 4 — the release that names the unreleased work

Not a deviation of its own, but it is where **LH-51**'s substance is discharged and it is the gate at
which `automated-tests-§6` finally bites.

| # | Step | IDs | Files | Verify |
|---|---|---|---|---|
| 4.1 | Run `wow-addon:bump-version`. The two `## Unreleased` bullets (`README.md:36-40`) become the new `## What's new in <next>` and the new top `## Version History` row; the heading goes; the TOC `## Version:` and the `[wow]`/`[tests]` badges move in the same change. | **LH-51** | `README.md`, `LootHistory.toc` | `## Unreleased` is gone; `## What's new` names the new version and matches the top Version History row. |
| 4.2 | Cut the **release** bundle before the tag, with `"release"` set. Its `ANALYSIS.md` is a **MUST** at this checkpoint, and the release notes **MUST** name the `performance-§12` exemption out loud, because `perf` is NOT EVALUATED rather than passed. | — | `docs/automated-tests/<stamp>/` | All four suites at `pass` with `perf` explicitly exempted in the notes; zero functions above CCN 15 (today: max 15, warnings 0). |

_Commit:_ per `wow-addon:bump-version`.

---

## Definition of done

- `03_EVIDENCE.md` §1.7 (e) prints `0`; §1.8's loops print only `UNACCOUNTED — .git`.
- `docs/ARCHITECTURE.md`'s register carries no row whose trigger has fired, one row per live
  ratified decision, and no `state:will-not-do` issue declining a rule sits outside it.
- `RESULTS.md`'s prose, its table and the working tree agree; every band file has a disposition and
  the one that has read *"peel next"* for five runs has an issue number.
- `grep -n '^## ' README.md` yields only `documentation-§1` headings, in its order.
- `luacheck .` `0/0`, `lua tests/run.lua` green, both `diff -r` against LibKa0s v1.25.0 still empty,
  `lizard` still reporting zero warnings.

---

## What is explicitly out of scope

Wiring a performance harness (ratified `performance-§12` exemption, re-confirmed today), restructuring
the 434-line hub whose sections have all spilled, re-litigating the four register rows whose triggers
have not fired, and any edit under `libs/LibKa0s/` or `tests/_kit/`.
