# 02 — Deviations

Audited against **Ka0s WoW Addon Standard v2.8.0 (2026-07-18)**. Prefix **`LH-`** (reused from the
first audit). IDs are stable across runs. Sections are cited in the current **`filename-§N`** form.
Evidence for every row is in `03_EVIDENCE.md`; remediation in `04_TECHNICAL_DESIGN.md` /
`05_EXECUTION_PLAN.md`.

## Recurrence of the prior run (`docs/audits/2026-07-12/`)

`LH-01 … LH-12` are all **still closed** — re-verified this run (see `03_EVIDENCE.md §Prior`). They
keep their IDs; none recur. New findings this run start at **LH-13**.

## Summary

**MUST failures: 3** (LH-13, LH-14, LH-15) · **SHOULD failures: 4** (LH-16, LH-17, LH-18, LH-19).
Verdict: **minor deviations.** No core-path (capture / storage / read) defects. **LH-13 is flagged
as a probable standard-internal contradiction** — the resolution may be an upstream standards fix
rather than an addon change (per the CLAUDE.md deviation rule, the user decides).

| ID | Section | Severity | Deviation | Fix direction |
|----|---------|----------|-----------|---------------|
| LH-13 | `toc-file-§5` (AP #28) | MUST | TOC file-listing `#`-section order is `Libraries → Core → Defaults → Locales → Settings → Modules`; toc-file-§5 mandates `Libraries → Locales → Core → Defaults → Modules → Settings` (Locales before Core; Settings last). **NB:** this contradicts `layout-§1`'s load order (`core → defaults → locales → settings → modules`), which the TOC *does* follow — the two standard sections disagree. | **Flag to user for classification.** Either (a) reorder the TOC section comments to toc-file-§5 (moving Locales above Core and Settings below Modules) *if the dependency order permits*, or (b) raise it upstream as a `toc-file-§5` ↔ `layout-§1` contradiction and record an accepted deviation here. Recommend (b) first — the addon's order is dependency-correct and matches layout-§1. |
| LH-14 | `options-ui-§2` | MUST | Combat panel-open refusal prints `"Can't open settings in combat."` — not the canonical **grey** notice text `"cannot open settings during combat — Blizzard's category-switch is protected"`. (The refusal itself is correct: it returns, does not call `Settings.OpenToCategory`, does not defer.) | Change `P:Open`'s lockdown branch to print the canonical text wrapped in a grey colour code (e.g. `\|cff808080…\|r`) through `NS.Print`; keep the early `return`. Add a locale key for the string. |
| LH-15 | `documentation-§2` / `documentation-§6` (AP #34) | MUST | Root `CLAUDE.md`'s standards section is titled `## Standards compliance`, not the required `## Standards compliance (read first)`. (Substance — stop-and-flag, user classifies, record resolution — is present.) | Rename the heading to `## Standards compliance (read first)`; confirm the body matches the documentation-§6 canonical wording. One-line edit. |
| LH-16 | `packaging` | SHOULD | Root `tools/` (dev-only Python + `tools/__pycache__/`, `tools/tests/`) is not in `.pkgmeta` `ignore:`, so it ships to players. packaging requires dev-only material be ignored (docs/tests/_dev already are). | Add `- tools` to the `.pkgmeta` `ignore:` list (and consider `- .superpowers`, `- .gitattributes`, `- .pkgmeta` if not already dropped by the packager). |
| LH-17 | `lint` | SHOULD | `.luacheckrc` `exclude_files = { "libs/", "_dev/", "tests/" }` omits `docs/audits/` and `docs/reviews/` from the standard template's exclude list. Harmless today (no `.lua` under `docs/`) but drifts from the template and would lint a future `.lua` dropped there. | Set `exclude_files = { "libs/", "docs/audits/", "docs/reviews/", "_dev/", "tests/" }` (optionally add `"tools/"`). |
| LH-18 | `options-ui-§5` | SHOULD | The `Filters` subcategory is created with `defaultsButton = false`, so it lacks the top-right **Defaults** button options-ui-§5 specifies for subcategories. (The `General` subcategory has one.) | Either add a Defaults button to the Filters subcategory (wired to a lists-reset, e.g. `NS.Filters:ClearAll` behind a confirm), or record an accepted deviation with a reason (the page manages id-lists via its own per-list "Clear all", not schema rows). |
| LH-19 | `documentation-§5` | SHOULD | Doc/comment drift from the standard's v1.5.0 renumbering: 13 code comments and 2 `CLAUDE.md` lines cite retired global `§N.M`/`§6A` numbers (`§7.4`, `§6.8`, `§6.6/§6.8`, `§6.10`, `§9.7`, `§2.2/§5.1`, `§8`, `§15.2`, `§14A`) instead of the current `filename-§N` form. Many other comments already use the new form, so it is a partial sweep. | Rewrite the stale citations to `filename-§N` (`§7.4`→`slash-commands-§4`, `§6.8`→`options-ui-§8`, `§6.10`→`options-ui-§10`, `§6.6`→`options-ui-§6`, `§9.7`→`events-frames-taint-§7`, `§2.2/§5.1`→`toc-file-§2`/`savedvariables-§1`, `§8`→`debug-logging`, `§15.2`→`documentation-§2`, `§14A`→`testing`). Comment-only edits. |

## Notes on scope

- **Sanctioned exceptions (NOT flagged):** the vendored JetBrains Mono debug font
  (debug-logging-§2) and the addon logo (options-ui-§6 / layout-§3) — both explicitly whitelisted by
  the standard.
- **`X-Wago-ID` / `X-WoWI-ID` absence is compliant** under v2.8.0 (now MAY; the addon is not listed
  on those platforms). Not a deviation.
- **README `### Export to AI` subsection** under `## Usage` (ordered before `### Slash commands`) is
  an *addition* not forbidden by documentation-§1 (the two mandated subsections are both present);
  left as an observation, not a deviation.
