# 02 — Deviations

Audited against **Ka0s WoW Addon Standard v2.39.0 (2026-09-07)**, resolved from `WowAddonStandards`
master `7e609f5`. Prefix **`LH-`**, reused; new findings this run start at **LH-55** because
`LH-01…LH-54` are spent across five prior audit runs and four review bundles. Evidence for every row is
in `03_EVIDENCE.md`, and every figure quoted here is the one quoted there.

**Grade is impact, not rule strength** (`AUDIT.md` step 5). A doc-only or config-only failure is Low
even where the rule is a MUST, and the row still names the MUST.

---

## Headline

| | Count | Basis |
|---|---|---|
| **Root deviations** | **6** | roots only; dependents excluded |
| **Total incl. dependents** | **7** | roots + 1 `derived from` row |
| **MUST failures (roots)** | **4** | LH-52, LH-55, LH-56, LH-57 |
| **MUST failures (incl. dependents)** | **4** | the one dependent fails a SHOULD |

By impact — **High 0 · Medium 0 · Low 4 (roots) / 5 (incl. dependents) · Info 2.**

**Verdict: minor deviations.** Nothing a user, their SavedVariables or their session can hit today.
Nine of the ten rows the 2026-09-07 run raised are closed; one survives; four are new, and three of
those four exist only because v2.39.0 made a rule mechanically checkable that had been prose.

---

## Against the prior run (`docs/audits/2026-09-07/`) — 9 roots / 10 total, all Low

| Prior ID | Section | Status this run |
|---|---|---|
| `LH-01 … LH-44` | (four earlier runs) | Still closed. |
| `LH-45` | `packaging` | **CLOSED.** Both mechanical checks pass: the strong-form sweep over every root dot-entry prints nothing. `.gitattributes`, `.pkgmeta`, `.superpowers` and `.pytest_cache` are all named (`.pkgmeta:9,10,19,20`). Scheduled as `LOOTHISTORY-A-01` → `M2-19`. |
| `LH-46` | `line-endings-§1`, `line-endings-§7` | **CLOSED.** The nine strays are gone: property (e) measures **0**. `.gitattributes` is byte-for-byte the §5 canonical client-bound body at 81 lines. Scheduled as `LOOTHISTORY-R-15` → `M4-10`. |
| `LH-47` | `documentation-§3` | **CLOSED.** `docs/ARCHITECTURE.md:419-427` now records issue #21's decline in `## Documented deviations` — as prose beneath the table rather than a row, on the stated ground that a row cites a `filename-§N` and `options-ui` names no `SetRenderer` — and answers the question LH-47 asked: the General page **is** on `O.SetRenderer` (`settings/Panel.lua:1027`) and what survives is the narrower `ctx._priHost`. Scheduled as `LOOTHISTORY-A-03` → `M5-02`. |
| `LH-48` | `documentation-§3`, `localization-§3` | **CLOSED.** The `localization-§1` register row exists, Decided **2026-09-08**, trigger *"The first non-English locale file added to `locales/`"* (`docs/ARCHITECTURE.md:398`). `localization-§3`'s terminal compliant state is now reached. Scheduled as `LOOTHISTORY-A-04` → `M5-02`. |
| `LH-49` | `automated-tests-§4` | **CLOSED.** `RESULTS.md` was regenerated whole at commit `830b425`; its four standing prose sections now read 714 cases (`:37`), 58 lint files (`:48`) and *"Current as of `20260908-181338`"* (`:64`), all matching its own newest table row (`:26`). `settings/Panel.lua` has its own band disposition (`:84`). Scheduled as `LOOTHISTORY-R-11` → `M5-01`. **Not re-filed for the three-hour drift** that `M4c-06` (`5600e08`) opened afterwards — 719/59/13879 against the record's 714/58/13670 — because the checkpoint is release, not commit, and no release run exists; the drift is recorded in `03_EVIDENCE.md` as the playbook's drift measurement. |
| `LH-50` | `automated-tests-§5` | **CLOSED by fix-forward.** `docs/automated-tests/20260908-181338/ANALYSIS.md` exists. The two older bundles are frozen and were deliberately not retro-fitted. Scheduled as `LOOTHISTORY-A-06` → `M5-01`, disposition *fix-forward*. |
| `LH-51` | `documentation-§1` | **CLOSED.** `## Unreleased` and `## Auction-house pricing` are both gone; the README's nine H2s are the canonical set in the canonical order. Scheduled as `LOOTHISTORY-A-07` → `M5-03`. |
| **`LH-52`** | `automated-tests-§4` (anti-pattern #53) | **STILL OPEN — see below.** Scheduled as `LOOTHISTORY-A-08` → `M5-01`. |
| `LH-53` | `library-stack-§8` | **CLOSED.** All three marks route through the catalog with the Blizzard paths demoted to the fallback rung: `NS.IconMarkup("circle-check", READY, …)` and `NS.IconMarkup("ban", NOTREADY, …)` (`settings/Panel.lua:510,512`), and `(NS.Icon and NS.Icon("info")) or INFO_ICON` (`:745`). Scheduled as `LOOTHISTORY-A-09` → `M4-23`. |
| `LH-54` | `documentation-§3`, `audit-review-history` | **CLOSED.** The `sessionOnly` row is retired into a named paragraph citing `options-ui-§12`/`§15` as the rules that closed it (`docs/ARCHITECTURE.md:400-408`). Scheduled as `LOOTHISTORY-A-10` → `M5-02`. |

---

## Root deviations

| ID | Section | Strength | Grade | Deviation | Fix direction |
|---|---|---|---|---|---|
| **LH-52** *(carried)* | `automated-tests-§4` (anti-pattern #53) | **MUST NOT** | Low | **A watch-list disposition still names itself next and still has nothing tracking it.** `modules/Analytics.lua`'s Band row has read *"Peel next"* since `20260804-233322` — **six** consecutive recorded runs — and the regenerated row now says so in its own words (`docs/automated-tests/RESULTS.md:81`): *"Nothing tracks it, and that is the gap this cell has now reported five times running … the remaining honest move is an owned issue, and `M5-07` is where this plan files what it decided not to do."* **`M5-07` ran on 2026-09-08 and filed 25 issues across nine repositories; two landed in this repo — #28 and #29 — and neither is the Analytics peel.** `gh issue list --state all --limit 200` shows no open issue for it. §4's shelf-life clock counts **release** runs and all eight bundles carry `"release": null`, so the letter of the rule has not started; #53's substance is exactly this. | Open a `state:triaged` issue with a `severity:` label naming the peel seam — renderers versus the formatting/segmenting helpers — and repoint the band Disposition at its number. Or do the peel. One of the two; the third option is what this row is. |
| **LH-55** *(new)* | `localization-§5` | **MUST** | Low | **62 British spellings in authored text, across 27 files.** v2.39.0 publishes the canonical `BRITISH` / `ALLOWED` lists, so this is now a reproducible count rather than a reading. Run whole and with `ALLOWED` removed as whole words first, the sweep hits ten distinct substrings: `centre` ×17, `colour` ×13, `behaviour` ×7, `memois` ×5, `honour` ×5, `cancelled` ×5, `labelled` ×4, `licence` ×3, `travelled` ×2, `normalis` ×1. Worst files: `docs/smoke-tests.md` (11), `docs/settings-panel.md` (5), `docs/ARCHITECTURE.md` (4), `core/ItemSetup.lua` (4). **No hit is a shipped player-facing string** — every Lua hit is a comment except four in test names and assertion messages — which is why this is Low and not Medium. It is filed as **one** rolled-up finding: the fix is one sweep, and per-file rows would inflate a single act into 27. | Sweep the ten substrings across the 27 files, US-spelling each, then regenerate `docs/test-cases.md` (its one hit at `:723` mirrors a test name at `tests/test_panel.lua:831`). Leave `locales/`-bound Blizzard symbols alone — there are none among the hits. Consider vendoring the §5 lists as a suite gate so the next one is caught by the runner rather than by an audit. |
| **LH-56** *(new)* | `toc-file-§5` | **MUST** | Low | **`core\CoreSetup.lua`'s load-bearing TOC position carries no annotation.** `core/CoreSetup.lua:180` resolves `NS.PREFIX` **at file scope** — `local printer = lib:New({ prefix = NS.PREFIX })` — from `core/Namespace.lua:10`. TOC `:45` (Namespace) precedes TOC `:48` (CoreSetup), so the order is dependency-correct, but `LootHistory.toc:48` is a bare `core\CoreSetup.lua` with nothing at the line. The constraint is written **inside the file** (`core/CoreSetup.lua:29`) — §5 requires it at the TOC line, which is where a reader reordering the listing is looking. Moving it fails the way §5 describes: silently, and only in the client. | Add a comment above `LootHistory.toc:48` naming what resolves: *"LOAD-BEARING POSITION: `lib:New{ prefix = NS.PREFIX }` runs at file scope, so `core\Namespace.lua` must have published `NS.PREFIX` first."* One line. |
| **LH-57** *(new)* | `toc-file-§5` | **MUST** | Low | **`core\DebugLogSetup.lua`'s load-bearing TOC position carries no annotation.** `core/DebugLogSetup.lua:90` sits inside the `lib:New({…})` table constructor evaluated at file load and reads `font = NS.Constants.FONT_MONO`, resolved by `core/Constants.lua:64`. TOC `:44` (Constants) precedes TOC `:51` (DebugLogSetup) — dependency-correct, unannotated. The file states the constraint at `core/DebugLogSetup.lua:17`; the TOC does not. Filed as its own row because `toc-file-§5`'s grading is explicit: *"one MUST row, one row per position."* | Add a comment above `LootHistory.toc:51`: *"LOAD-BEARING POSITION: the descriptor reads `NS.Constants.FONT_MONO` at `:New` time, so `core\Constants.lua` must be above."* One line, and it lands in the same commit as LH-56's. |
| **LH-60** *(new)* | `documentation-§3` | SHOULD | Info | **The hub is 458 lines against the ~400 SHOULD.** Reported as shape rather than arithmetic, per the section's own instruction. Every mandated section **has** spilled — the largest are *Settings schema* (58 lines), *Standards compliance* (55) and *Documented deviations* (55), all inside the ~60 MUST — so the file is long because it carries four register tables and five ratified deviation rows, not because a section is being used as storage. `documentation-§3` says the failure the numbers catch is 1071 lines, not 412. Recorded so a future run measures the trend rather than rediscovering the number. | Nothing this cycle. If it passes ~500, spill *Standards compliance* to a topic doc — it is the one section with no canonical Tier 1 home and the one most likely to keep growing. |
| **LH-61** *(new)* | `packaging` | **MUST** (weak form) / passes the strong form | Info | **`.pkgmeta` omits `.claude` from an ignore list that `packaging` names it in.** §28's template enumerates `.claude` as a dev-only agent-tooling directory that MUST be ignored. This repo does not list it — deliberately, with the reason written at `.pkgmeta:11-18`: no `.claude/` exists here, and *"naming one that does not is how a sibling repo's identical filing was rejected this cycle."* §29 makes the **strong** form the real check — every root dot-entry **present in the repo** named or justified — and that sweep prints **zero** unaccounted entries. Graded Info rather than Low, and not counted as a MUST failure, because the check that has teeth passes and the omission is a recorded decision, not a gap. Reported so the tension between §28's flat list and §29's presence-scoped rule is visible rather than re-litigated every cycle. | Nothing here. If it is worth settling, settle it upstream: `packaging-§28`'s list is either a template or a checklist, and it currently reads as both. |

**`LH-59` is deliberately unused.** It was assigned to *"the repo ships no `localization-§5` spelling
gate"* and withdrawn on reading the section: §5 binds **every mechanical gate** to use the published
lists whole, and does not require that a gate exist. There is nothing to file. The ID is retired rather
than reused, so a future run does not find a row under it that says something else.

### Dependents — excluded from the headline tally

| ID | Section | Strength | Grade | Deviation | Fix direction |
|---|---|---|---|---|---|
| **LH-58** *(new)* | `toc-file-§5` | SHOULD | Low | *derived from LH-56.* **Four TOC groups do not say that their positions are conventional.** `# Libraries` (`:15`), `# Locales` (`:29`), `# Defaults` (`:57`) and `# Settings` (`:70`) carry no statement that the lines under them are free to move. `# Core (Compat loads first)` and `# Modules (Attribution before Collector)` each name their one constraint, and `core\EnvSetup.lua` (`:34-35`) is the model — it says the position is conventional and why. §5 grades this **once per file**, never per line, and never as a MUST. Kept as a dependent of LH-56 because it is the same file, the same annotation pass and the same commit. | In the LH-56/LH-57 commit, add one line per unannotated group saying the positions under it are conventional. Four lines. |

---

## Recorded deviations — accepted, not counted

Read before anything was filed. `audit-review-history` binds this run three times, and v2.39.0 adds
the third: **every row's re-check trigger evaluated against the tree, and every evidence id resolved.**
Both were done; results below.

| Rule | Decided | Issue | Trigger evaluated against the tree | Status |
|---|---|---|---|---|
| `architecture-§5` — five unbounded/ordered structures written direct to `db.global` | 2026-07-17 | #14 (resolves) | *"`options-ui` gains a set/list widget maker, or any of these five acquires a fixed schema row."* **Not fired.** `libs/LibKa0s/OptionsWidgets.lua` at v1.27.0 publishes no multi-check/set/list maker; `O.RenderGrid(ctx, items)` (`:1820`) still takes no `parent`. | **Accepted.** |
| `performance-§12` — no perf harness wired | 2026-08-05 | #22 (resolves, `state:will-not-do`) | *"The first `OnUpdate` handler, repeating ticker, or in-combat event handler doing real work."* **Not fired.** Zero `SetScript("OnUpdate"` sites, zero `C_Timer.NewTicker`, 13 event registrations and 5 one-shot timers — all re-measured today and all matching `docs/performance.md:53,73`. | **Accepted.** Issue #29 (`state:will-not-do`, 2026-09-08) records a declined *withdrawal* of this exemption; the exemption it declines to withdraw already has this row, so no second row is owed. |
| `options-ui-§12` — three reset controls, three blast radii | 2026-09-02 | — | *"The maintainer rules on one of the two reconciliations."* **Not fired.** | **Accepted.** A live maintainer decision; not re-litigated. |
| `options-ui-§1` — inverted set pickers drawn by the host | 2026-08-01 | #20 (resolves, `state:will-not-do`) | *"`LibKa0s-Options-1.0` gains a multi-check / set maker with a `parent`."* **Not fired** — same read as the first row. | **Accepted.** |
| `localization-§1` — English only | **2026-09-08** | — | *"The first non-English locale file added to `locales/`."* **Not fired** — `locales/` holds only `enUS.lua`. | **Accepted, new this cycle.** This is `LH-48`'s closure and it makes `localization-§3`'s terminal compliant state reached. |

**No register row cites a rule the standard has since changed.** The one that did — the `sessionOnly`
row — was retired on 2026-09-08 into a named paragraph (`docs/ARCHITECTURE.md:400-408`) citing
`options-ui-§12`/`§15`, which is exactly what `LH-54` asked for.

**No `state:will-not-do` issue is unrecorded.** Issues #18, #19, #20, #21, #22 and #29 are the six
declines in the store; #20 and #22 carry rows, #19, #21 and #29 are covered by the two retirement
paragraphs and the `performance-§12` row respectively, and #18 (*Add a serialized v2 export format*) is
a declined **feature**, not a declined rule, so it owes no row.

**`docs/pending/LEDGER.md` is absent** and so is `docs/pending/`. Every issue carries a `state:` and a
`severity:` label; no `[status]` title prefix survives.
