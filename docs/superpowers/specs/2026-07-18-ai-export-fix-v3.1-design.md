# AI Export fix v3.1 — force adoption of the shipped assembler

**Branch:** `feat/ai-export-fix-v3.1`
**Date:** 2026-07-18
**Supersedes/extends:** [2026-07-18-ai-export-fix-v3-design.md](2026-07-18-ai-export-fix-v3-design.md).
v3 shipped the deterministic assembler (`tools/build_report.py`) and hardened the guideline. This spec
does **not** change any of that machinery; it fixes the one thing v3 could not verify at build time —
**that a code-capable agent actually uses the tool** — plus two guideline hardenings the user asked for.

## Problem

A fresh execution log (`execution-log-v2.1.html`, 18 Jul 2026, ~13 min) of a code-capable agent building
a report from the pasted "Export to AI" prompt shows the v3 success criteria were **empirically not met.**
Timeline of facts:

- The final v3 commit landed on `origin/master` at **07:31 UTC**; the run's first action fetched the
  **current** guideline at **07:45 UTC**. So the agent read the guideline that already contains the
  "Fastest path — if you can run code → run `build_report.py`" section.
- **The agent ignored the tool and hand-rolled the entire pipeline anyway:** it materialised
  `history.csv` by hand (`cat > history.csv`), wrote its own `build_h.py` and `splice.py`, reconciled
  INSIGHTS by hand, and introduced **two new self-inflicted defects** in its own scripts —
  **F6** (an over-eager assertion) and **F7** (analysis-card glyphs written as literal `◆` because
  the cards were embedded in a Python raw string).

Re-bucketing the log's seven findings against the current repo:

| # | Log finding | Real status |
|---|-------------|-------------|
| F2 | "Vendor value = Σ(v×qty) not stated" | Already in the guideline (Value-math note) **and** enforced by the tool. Agent missed the note *and* bypassed the tool. |
| F4 | Template truncated on `web_fetch`, needed `curl` | Already documented; the tool downloads it in full. Symptom of going manual. |
| F5 | Trailing commas invalid JSON | Already documented; the tool emits clean JSON. Symptom of going manual. |
| F6 | Assertion fired too early | Self-inflicted in a hand-rolled script. Impossible if the tool is used. |
| F7 | Card glyphs as literal escapes | Self-inflicted in a hand-rolled script. Impossible if the tool is used (`--cards` takes an HTML file, not a Python string). |
| F3 | Title date-range "tension" | Not a real conflict — `modules/Export.lua:230` already says "leave the title alone." The agent *misread* "the engine derives the date range from the data" as an instruction to hand-title. Wording-clarity nit only. |
| F1 | HISTORY "By Source" ≠ INSIGHTS "By Source" by one row; records 301 vs 302 | **Not a real addon bug — a model hand-count slip.** Both blocks come from *one* deterministic pass: `Database:Export` (HISTORY) and `Database:Stats` (INSIGHTS) both iterate `self:Query({})` and read the same `r.source`, written once at loot time by `Attribution:Stamp` and never re-derived on read (`core/Database.lua:211/217/229/245`). The HISTORY row count *is* `#records`; `Summary,Records` *is* `#records` from the same query. So the two blocks cannot truly disagree — the log's `110/34` vs `109/35` and `301` vs `302` are the agent's own off-by-one re-derivation, the same hand-work class as F6/F7 that the tool does mechanically. F1 therefore **reinforces** the adoption thesis rather than being a separate bug. See §6 for the one genuine (latent) parity nit found nearby. |

**Core insight:** 6 of 7 findings (all but the F3 wording nit) reduce to "the agent did not run the tool
we already ship" — including F1, whose "disagreement" is just the hand-count the tool does mechanically. The slow
step and the truncated fetch the user flagged are the same story — both vanish the moment the tool runs
(`--prompt` self-extracts both CSVs; `load_template` downloads the full 169 KB itself, no `web_fetch`).
So v3.1 is a **behavioural-adoption** fix, not a new-code fix: make the tool the mandatory, first,
unmissable path and remove every "manual" affordance that lets a capable agent wander off it.

The pasted prompt also confirms the addon prompt (`AIPrompt`) contains **no pointer to the tool at all** —
it only says "follow the guideline." The tool exists solely in the fetched guideline, which the agent
skimmed. Hence a pointer belongs in the prompt too (read before the guideline).

## Decisions (agreed with user)

1. **Direction: force adoption.** No new pipeline scripts — v3 already built them. Weight goes on making
   the agent run `build_report.py`.
2. **Force level: mandatory ("MUST").** A code-capable agent MUST run the tool; hand-transcription,
   hand-written splice/build scripts, and `web_fetch` of the template are explicitly forbidden. The
   manual path is relabelled a fallback for genuinely code-incapable environments only.
3. **Prompt pointer: yes (belt & suspenders).** Add a tool pointer to `AIPrompt` in `modules/Export.lua`
   and update `tests/test_export.lua`. Caveat recorded: prompt text is baked into the installed addon,
   so it only reaches runs after the user updates in-game; the live-fetched guideline is the immediate
   lever.
4. **F1 is a model miscount, not a bug** (see the table and §6). Do not chase it as a data-correctness
   defect. The only real thing found nearby — a latent nil-`source` parity gap between `Export` and
   `Stats` — is folded into v3.1 as a trivial one-liner (§6), not a separate branch.

## Design

### 1. Guideline restructure — tool-first, manual demoted (`docs/ai-export-guideline.md`)

- **New hard directive block at the very top**, before "Before you start":
  > **If you can run code — Claude Code, Claude Desktop with code execution, ChatGPT code interpreter,
  > any Python sandbox — you MUST build the report with `tools/build_report.py`. Do NOT hand-transcribe
  > the CSV into `H`. Do NOT write your own build / splice / validation scripts. Do NOT `web_fetch` the
  > template. One command does the transcription, the splice, the full download, and all validation.**
- Keep the "Fastest path — if you can run code" instructions (fetch/run the tool, write `cards.html`,
  the one command), immediately under the directive, tightened to a numbered recipe.
- **Move the entire "How to build the report (manual)" section to the end** and retitle it
  **"Fallback — ONLY if you cannot run code at all."** Content unchanged; it is now clearly the
  exception, so an agent cannot skim into it as the primary recipe.
- Net structure: directive → tool recipe → data contract / cards authoring (needed by both paths) →
  output contract → fallback (manual) → the data you're given.

### 2. Template-fetch prohibition (user ask #1)

- In the fallback path, replace the soft "download it in full" wording with an explicit prohibition:
  > **NEVER `web_fetch` the template — it is ~169 KB and a size-capped fetch silently truncates it,
  > which breaks the byte-for-byte contract. Use `curl -o` / `wget`. Better: run the tool and you never
  > fetch the template at all — it downloads the full file for you.**
- In the tool path the agent never touches the template, so directive #1 is the primary mitigation.

### 3. Kill the slow dataset-to-disk step (user ask #2)

The slowest step in the log (`cat > history.csv`) is slow because the agent **re-emits the entire
dataset as output tokens.** The data must reach disk **without passing back through the model's output.**

- **Loud primary instruction, in both the guideline and the addon help/`?` popup:** hand the export to
  the AI **as a file** — upload/attach it (ChatGPT / Gemini / Claude Desktop) or paste it in Claude Code
  (large pastes auto-file). **Do not paste it inline** if the tool can attach a file. Then point
  `build_report.py --prompt` at that file.
- **Run-code guardrail (guideline):** never reproduce the dataset via a heredoc, `cat >`, or a `Write`;
  `--prompt` self-extracts both `=== HISTORY (CSV) ===` / `=== INSIGHTS (CSV) ===` blocks and counts
  rows itself.
- **Honest limit (unchanged from v3, stated plainly):** if the user pastes inline **and** the
  environment does not auto-file large pastes, the model must write the file once — unavoidable. That is
  exactly why file-attachment is the loud primary instruction, not merely an optimisation.

### 4. Addon prompt pointer (`modules/Export.lua` `AIPrompt`)

- Add one line near the top of the pasted prompt, e.g.:
  *"If you can run code, the guideline points to a ready-made assembler (`tools/build_report.py`) — run
  that to build and validate the report in one command; do not hand-build it."*
- Keep the existing rules block (title/hero, self-contained, CSV contract) unchanged.
- Update `tests/test_export.lua` expectations for the new line. Confirm the Lua **case count** does not
  change (an assertion edit, not a new/removed case) → README `tests` badge and `docs/test-cases.md`
  only regenerate if the count actually moves.

### 5. Fold the F7 footgun into the tool (`tools/build_report.py`)

- Using `--cards cards.html` already prevents F7 (cards live in an HTML file, not a Python raw string).
  Add a **defensive validator**: fail with a clear message if the cards file contains literal
  `\uXXXX` / `\xNN` escape sequences (i.e. a backslash-`u`/`x` that was meant to be a real glyph),
  since a rendered report must never show `◆` in place of `◆`.
- Add one unit test in `tools/tests/test_build_report.py` (positive: literal escapes rejected; negative:
  real UTF-8 glyphs pass). Keep it stdlib `unittest`.

### 6. nil-`source` parity between HISTORY and INSIGHTS (`core/Database.lua`) — the one real F1-adjacent nit

Tracing F1 surfaced a genuine (latent) asymmetry: for a row whose `source` is nil/blank,
`Database:Stats` coerces it — `local src = r.source or "OTHER"` (`Database.lua:245`) → counts as **Other**
— while `Database:Export` writes it raw — `source = r.source` (`Database.lua:217`) → the HISTORY CSV cell
is **blank**. That is the *only* way the two export blocks could actually diverge, and it does not bite
today (no blank-`source` row observed in the pasted data), but it is a correctness gap.

- Fix: make `Database:Export` coerce `source = r.source or "OTHER"`, matching `Stats`, so the two blocks
  are guaranteed source-consistent regardless of data.
- Guard it with a `tests/` unit case: a record with nil `source` exports as `OTHER` (not blank) and its
  By-Source bucket matches what `Stats` reports. This may add one Lua test case → if the case count
  moves, regenerate `docs/test-cases.md` and bump the README `tests` badge in the same change.
- This is a data-path *consistency* fix, not a schema or behaviour change; the CSV contract is unchanged
  (a source column that was already meant to be one of the SourceType labels).

## Out of scope

- **Chasing F1 as a data-correctness bug** — it is a model hand-count artifact (see the table and §6),
  fully addressed by forcing the tool; there is nothing to fix in the aggregation itself beyond the §6
  nil-`source` parity one-liner.
- No change to the addon data path (CSV stays; no pre-built `H` in the prompt).
- No engine, styling, or runtime-behaviour change. No version bump.

## Success criteria

- The guideline leads with a MUST-use-the-tool directive; the manual steps are clearly a
  code-incapable fallback moved to the end. A skimming agent hits the directive first.
- The guideline forbids `web_fetch` of the template and names `curl`/`wget`, and the tool path removes
  the fetch entirely.
- File-delivery ("attach as a file, don't paste inline; never heredoc/`Write` the data") is stated
  loudly in both the guideline and the addon help, with the inline-paste limit stated honestly.
- `modules/Export.lua` `AIPrompt` carries a tool pointer; `tests/test_export.lua` passes; the Lua case
  count is unchanged (or the badge/`test-cases.md` are regenerated if it moved).
- `build_report.py` rejects a cards file containing literal `\u`/`\x` escapes, with a test proving it.
- `Database:Export` coerces nil `source` → `OTHER` (matching `Stats`), with a Lua test proving HISTORY
  and INSIGHTS stay source-consistent for a blank-`source` row.
- `luacheck .` clean, `lua tests/run.lua` green, `python3 -m unittest discover -s tools/tests` green;
  test-cases.md/badge regenerated if the Lua case count moved.
- F1 recorded in the spec as a non-bug (model miscount), so it is not re-chased later.
