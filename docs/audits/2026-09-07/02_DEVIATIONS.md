# 02 — Deviations

Audited against **Ka0s WoW Addon Standard v2.38.0 (2026-09-02)**. Prefix **`LH-`**, reused; new
findings this run start at **LH-45** because LH-01…LH-44 are spent across the four prior runs and the
three review bundles. Evidence for every row is in `03_EVIDENCE.md`.

**Grade is impact, not rule strength** (`AUDIT.md` step 5). A doc-only or config-only failure is Low
even where the rule is a MUST, and the row still names the MUST.

---

## Headline

| | Count | Basis |
|---|---|---|
| **Root deviations** | **9** | roots only; dependents excluded |
| **Total incl. dependents** | **10** | roots + 1 `derived from` row |
| **MUST failures (roots)** | **8** | LH-45, 46, 47, 48, 49, 51, 52, 54 |
| **MUST failures (incl. dependents)** | **8** | the one dependent fails a SHOULD |

By impact — **High 0 · Medium 0 · Low 9 (roots) / 10 (incl. dependents) · Info 0.**

**Verdict: minor deviations.** Nothing a user, their SavedVariables or their session can hit today.
Every root is a config file, a record file, a README heading or a missing register row. The reason
that is the whole list is that the addon closed almost everything the last run raised (see
*Recurrence* below) and has adopted the v2 settings panel, the shared media catalog and the
vendored-payload gate in full.

---

## Recurrence against the prior run (`docs/audits/2026-08-05/`)

| Prior ID | Section | Status this run |
|---|---|---|
| `LH-01 … LH-18` | (2026-07-12 / 2026-07-18) | Still closed. |
| `LH-19` | `documentation-§5` | **CLOSED.** The repo-wide retired-`§N.M` sweep over live paths returns **zero** hits. |
| `LH-20 … LH-26` | `performance` | **RECORDED DEVIATION, accepted.** Now a ratified `performance-§12` row in `docs/ARCHITECTURE.md` (Decided 2026-08-05, issue #22) with a committed sweep and a stated re-check trigger. **Not counted.** |
| `LH-27` | `options-ui-§11` | **CLOSED.** The page uses the library's `ctx._dirty`, the flag `SetRenderer`'s OnShow actually reads. |
| `LH-28` | `savedvariables-§2` | **CLOSED.** Every schema row's `default` reads `G.<path>`; the composer is handed `defaults` for the same reason. |
| `LH-29` | `testing-§9` | **CLOSED.** `tests/test_harness.lua` pins the TOC derivation, path existence, `libs/` leakage, the suite inventory in both directions, and duplicates. |
| `LH-30` | `standalone-windows` | **CLOSED.** `B:ApplySkin` delegates to `Core.ApplySkin`; only host-specific fields remain in `B.SKIN`. |
| `LH-31` | — | Retired by the standard in v2.19.0; correctly absent. |
| `LH-32` | `documentation-§4` | **CLOSED.** `docs/pending/LEDGER.md` is gone; decisions are GitHub issues carrying `state:` labels. |
| `LH-33` | `layout-§3` | **CLOSED.** `media/logos/wowhead-logo.png` no longer ships. |
| `LH-34` | `savedvariables-§2` | **CLOSED.** `AUCTION_PRIORITY_DEFAULT` has one declaration, `core/Constants.lua:153`, which `defaults/Global.lua:67` loops over. |
| `LH-35` | `architecture-§4` | **CLOSED.** No `or NS.bus` tail survives; both sites carry the reason it was removed. |
| `LH-36` | `automated-tests-§3` | **CLOSED.** `docs/testing.md:176-185` and `docs/automated-tests/README.md:21-41` both state the release gate and the NOT-EVALUATED skip. |
| `LH-37` | `automated-tests-§4` | **CLOSED.** The band disposition no longer cites the retired `LH-31`. |
| `LH-38` | `documentation-§2` | **CLOSED.** `CLAUDE.md` is a 65-line stub with the six mandated items. |
| `LH-39` | `testing-§8` | **CLOSED.** Degraded-path cases now span six suite files. |
| `LH-40` | `testing-§11` | **CLOSED.** The kit reports a missing sibling as `T.skip` with its reason; today it found the checkout and both cases ran (`0 skipped`). |
| `LH-41` | `performance-§8` | **CLOSED.** `docs/perf-runs/` is gone; the exemption ships no capture store. |
| `LH-42` | `slash-commands-§2` | **RECORDED DEVIATION, accepted.** Now the ratified `options-ui-§12` register row (Decided 2026-09-02). **Not counted.** |
| `LH-43` | `architecture-§5` | **CLOSED.** `S:Register` fires; the dead conjunct is gone and `settings/Schema.lua:394-403` explains why. |
| `LH-44` | `lint` | **CLOSED.** The redundant `-- luacheck: ignore addonName` directive is gone. |

---

## Root deviations

| ID | Section | Strength | Grade | Deviation | Fix direction |
|---|---|---|---|---|---|
| **LH-45** *(new)* | `packaging` | **MUST** | Low | **`.pkgmeta`'s ignore list does not account for every root dot-entry.** The strong-form rule requires every root dotfile/dot-directory present in the repo to appear in `ignore:` or be justified in a comment beside it. Four are unaccounted: `.gitattributes` and `.pkgmeta` (both **tracked**, so both ship into the packaged AddOn today), and `.superpowers/` and `.pytest_cache/` (untracked, so they do not ship from a clone — but the enumeration is exactly what goes stale the next time a tool writes a dot-directory). `.gitattributes` is named verbatim in the section's template and is the one straightforward omission. | Add `- .gitattributes`, `- .claude`, `- .superpowers` to `.pkgmeta`'s `ignore:` block per the template, plus `- .pytest_cache` and a one-line comment covering `.pkgmeta` itself. One file, five lines. |
| **LH-46** *(new)* | `line-endings-§1`, `line-endings-§7` | **MUST** | Low | **Nine tracked files disagree with the declared `eol=crlf` pin.** `.gitattributes` is correct and canonical; the working tree is not renormalized against it. Two of the nine sit inside the frozen `docs/revendor/2026-08-25/` bundle, which is never edited — say so rather than leaving the number unexplained. Files are deliberately **not** enumerated: the fix is one action, and a per-file list inflates the tally. | `git add --renormalize .` followed by a fresh checkout, in one commit, then re-run the check in `03_EVIDENCE.md` and expect `0`. |
| **LH-47** *(new)* | `documentation-§3` | **MUST** | Low | **A ratified decline lives only as a closed `state:will-not-do` issue, with no register row.** Issue [#21](https://github.com/tusharsaxena/LootHistory/issues/21) declines putting the AH Price page on `LibKa0s-Options-1.0`'s `SetRenderer` contract and reasons it at length ("closed by design: it records a settled refusal"), but `docs/ARCHITECTURE.md` → `## Documented deviations` has no row for it and `## Standards compliance` does not cover it either. The issue store is a working queue; the register is where a reader looks, and *a deviation not in the register is not ratified*. The R6 revamp may have superseded the decline — the whole General page now goes through `SetRenderer` (`settings/Panel.lua:990`) while the AH tab keeps its own pooled host — which makes the missing row worse, not better: nothing records which of the two is true. | Either file the register row (Rule, What differs, Why citing #21, Decided, Re-check trigger), or close #21 as superseded with a note saying the page is on `SetRenderer` now and the survivor is the pooled host. Do one; do not leave it unrecorded. |
| **LH-48** *(new)* | `documentation-§3`, `localization-§3` | **MUST** (register) / SHOULD (routing) | Low | **The English-only decision is recorded in a code comment, not in the register.** `locales/enUS.lua:7-9` states the addon ships English only and calls it "an accepted scope decision, not an oversight"; no user-facing string routes through `NS.L`. `localization-§3` gives that decision a **terminal compliant state** — but only when it is *"a row in its `## Documented deviations` register citing `localization-§1`, with a re-check trigger: the first non-English locale file added to `locales/`"*. There is no such row, so the routing SHOULD is formally still open and the next audit re-files it. Both MUSTs are met: `NS.L` is exported (`locales/enUS.lua:5`) and `enUS.lua` ships with no dead keys. | Add the register row citing `localization-§1`, Decided today, trigger *"the first non-English locale file added to `locales/`"*. One table row closes the rule permanently. |
| **LH-49** *(new)* | `automated-tests-§4` (anti-pattern #51) | **MUST** | Low | **`docs/automated-tests/RESULTS.md`'s prose and watch list are stale by two runs and by the working tree.** The table's newest row is `20260825-103428` (644/644 tests, 28 lint files, 12116 NLOC), but the Test-suite section still reads *"594 cases, 0 skipped"* (`:33`), the Lint section still reads *"Clean over 23 files"* (`:58`), and the watch list is headed *"Current state as of `20260807-114650`"* (`:91`). Against the code today the drift is wider still: the suite is at **699**, `lizard` reports **13222 NLOC / 1761 functions**, and **`settings/Panel.lua` has newly entered `layout-§1`'s 1000–1500 band at 1004 LOC** — a fourth band file the record does not list. The checkpoint is release, not commit, so this is a finding about the release process, not about gating commits. | Cut a fresh four-suite bundle with `tests/_kit/run-automated-tests.sh` so the table, the band table and the generated lead-in are regenerated together, and rewrite the four standing prose sections against the numbers the new run actually produced. |
| **LH-50** *(new)* | `automated-tests-§5` | SHOULD | Low | *derived from LH-49.* **Two bundles whose numbers moved carry no `ANALYSIS.md`**: `docs/automated-tests/20260807-110451/` and `docs/automated-tests/20260825-103428/`. §5 makes the write-up a MUST at release and a SHOULD *"for any run whose verdict is not green or whose numbers moved"*; `20260825-103428` moved tests 594 → 644 and NLOC 11479 → 12116. No run in the record is a release run (every manifest carries `"release": null`), so the MUST has not bitten. Kept as a dependent because the fix is the same act as LH-49 — the next bundle is written with its analysis. | Write the analysis with the LH-49 bundle, following the uniform prompt in the standard's root `AUTOMATED_TESTS.md`, reporting complexity with totals **and** averages. |
| **LH-51** *(new)* | `documentation-§1` | **MUST** | Low | **The README carries two H2 sections the canonical structure does not name.** `## Unreleased` (`README.md:36`) sits between the description and `## What's new in 1.2.0`, holding two shipped-but-unreleased entries — a second changelog beside the two the structure already mandates (`## What's new`, `## Version History`), and the exact "one history" failure the section names. `## Auction-house pricing` (`:141`) sits between `## Usage` and `## How attribution works`, splitting items 7 and 8 of the fixed order. Everything else about the README is exact: badge row, bare standard badge, no library inventory, no placeholders, tests badge in sync. | Fold the `## Unreleased` bullets into the next version bump's `## What's new` + `## Version History` rows and delete the heading; fold `## Auction-house pricing` into `## How attribution works` or into `docs/` as engineer material. |
| **LH-52** *(new)* | `automated-tests-§4` (anti-pattern #53) | **MUST NOT** | Low | **A watch-list disposition has stopped being a decision.** `modules/Analytics.lua` has read *"peel next"* since `20260804-233322` — **five** consecutive recorded runs, including today's un-bundled state — with no line moved and **no deviation ID tracking it**. The record says so itself (`RESULTS.md:100-105`, `:143`): *"a disposition that has named itself next for four consecutive runs is a decision that has stopped being one. Either peel it or file it in the issue store with an owner."* The **letter** of §4's shelf life counts *release* runs and none exist, so the clock has not started; the **substance** is exactly what #53 describes, and no issue exists for it. | Open a `state:triaged` issue with a `severity:` label naming the peel seam (renderers vs formatting/segmenting helpers) and point the watch-list disposition at that issue number — or do the peel. |
| **LH-53** *(new)* | `library-stack-§8` | SHOULD | Low | **Three one-off Blizzard marks where the shared catalog has entries, with no reason recorded.** `settings/Panel.lua:459-461` hard-codes `Interface\RaidFrame\ReadyCheck-Ready`, `…\ReadyCheck-NotReady` and `Interface\FriendsFrame\InformationIcon` for the AH price table's collecting tick, its off mark and its per-row ⓘ. `LibKa0s-Media-1.0`'s `ICONS` catalog carries `circle-check`, `cancel` and `info`, and every other art site in the addon already goes through `NS.Icon(name)` with a Blizzard path only as the degraded fallback. These three take no `NS.Icon` and carry no comment. Contrast `modules/Browser.lua:1048-1053`, where the size-grabber's Blizzard art is a **recorded** decision — that one is compliant and is not filed. | Route the three through `NS.Icon("circle-check") / NS.Icon("cancel") / NS.Icon("info")` keeping the current paths as the degraded fallback, or write the one-line reason beside them the way the size grabber does. |
| **LH-54** *(new)* | `documentation-§3`, `audit-review-history` | **MUST NOT** | Low | **A register row's re-check trigger has fired and the row is now a graveyard entry.** The second `architecture-§5` row (`docs/ARCHITECTURE.md:392`) records the schema's `sessionOnly` row kind as a deviation, with the trigger *"The standard names a session-only row kind (then this is compliant, not a deviation)"*. The standard now does: `options-ui-§15` makes the debug console *"a session-only row (debug-logging)"* mandatory on the Master controls tab, and `options-ui-§12` requires the global reset to sweep *"session-only rows, whose storage is their own `set()` rather than the db … a debug console toggle"*. The behavior is permitted and in part mandated outright, so the row is one the register **MUST** retire. | Retire the row into the *"Retired, deliberately not rows"* paragraph that already follows the table, citing `options-ui-§12` / `options-ui-§15` as the rules that closed it. |

---

## Recorded deviations — accepted, not counted

Read before anything was filed, per `AUDIT.md`. Each cites its rule, its issue and its Decided date,
and each carries a re-check trigger a reader can evaluate.

| Rule | Decided | Issue | Status this run |
|---|---|---|---|
| `architecture-§5` (direct `db.global` writes for five unbounded/ordered structures) | 2026-07-17 | #14 | **Accepted.** Trigger has not fired: `options-ui` still has no set/list widget maker. |
| `architecture-§5` (the `sessionOnly` row kind) | 2026-07-17 | — | **Accepted, but the trigger has fired** — see **LH-54**. |
| `performance-§12` (no perf harness wired) | 2026-08-05 | #22 | **Accepted.** Confirmed today: zero `SetScript("OnUpdate")` sites, no repeating ticker, no in-combat handler doing real work. |
| `options-ui-§12` (three reset controls, three blast radii) | 2026-09-02 | — | **Accepted.** A live maintainer decision with both reconciliations spelled out; not re-litigated here. |
| `options-ui-§1` (inverted set pickers drawn by the host) | 2026-08-01 | #20 | **Accepted.** Trigger has not fired: no multi-check/set maker with a `parent` in v1.25.0. |

No register row cites a rule the standard has changed **other than** the `sessionOnly` row above.
No surviving `[status]` title prefix in the issue store; every issue carries a `state:` and a
`severity:` label. Four issue titles (#23–#26) are a bare `LIBKA0S-NN:` with nothing after the colon
— a cosmetic migration artefact, not a `state:` duplicate, and not filed.
