# AI Export fix v3.2 — deterministic polish + stale-cache resilience

**Branch:** `feat/ai-export-fix-v3.2`
**Date:** 2026-07-18
**Extends:** [2026-07-18-ai-export-fix-v3.1-design.md](2026-07-18-ai-export-fix-v3.1-design.md)
(v3 shipped the deterministic assembler; v3.1 forced adoption of it). This spec does **not** change
that machinery — it removes the residual wasted-effort and doubt a healthy run still shows.

## Problem — a *healthy* run this time

A fresh execution log (`execution-log-v3.2.html`, 18 Jul 2026, ~9 min) of a code-capable agent building
a report from the pasted "Export to AI" prompt shows v3.1's adoption fix **worked**: unlike the prior
run (which hand-rolled its own splice/build scripts and injected two defects, F6/F7), this agent **used
`build_report.py` and it PASSed on the first invocation with zero self-inflicted defects.** Every
reconciled metric matched to the copper (records 305, distinct 111, chars 7, epic+ 87, best iLvl 272,
richest 80g 63s 1c, busiest 13-Jul(91), vendor Σ(v×qty) 2354g 87s 37c).

So this round is **polish on a working pipeline**, not a rescue. Re-bucketing the log's six findings
against the current repo:

| # | Log finding | Real status → action |
|---|-------------|----------------------|
| F1 | "Guideline never mentions the assembler" | **Stale GitHub-raw CDN cache.** The run fetched the guideline ~6 min after the v3.1 push; raw caches ~5 min, so the agent got the pre-v3.1 copy. The live guideline leads with the assembler mandate (verified: 11 hits for `build_report`/`assembler`). No content bug → make the prompt self-checking so a stale copy self-recovers (§D). |
| F4 | Template truncates on `web_fetch`, needed `curl` | Same stale-cache symptom + fallback-only caveat. The tool downloads the template itself. Folded into §D's prompt directive (never web_fetch the template). |
| F3 | Static `<title>` reads 12–17, data runs 12–18 | Real but cosmetic — the engine overwrites the title at load from `H`. The stale static value (matching the old 301-row sample) cost the agent reasoning. Fix: neutralize it (§B1) + one guideline line (§C2). |
| F6 | Template ships a stale 301-row pseudonymised sample; agent hand-scanned for leaks | The agent ran a sample-name leak scan the tool lacks. Ship it in the tool (§A1) + annotate the sample blocks (§B2). |
| F5 | Export arrived as a paste, not a file | Inherent to the handoff; already the loud primary instruction in guideline + help. No further fix. |
| F2 | Prior run's dataset/vendor issues | Recorded as **resolved**; no action. |

**Two efficiency costs not filed as findings but visible in the timeline:**

- The agent re-derived the **entire** INSIGHTS reconciliation (09:15:40) **and** a post-build integrity
  sweep (09:17:52) — every check of which the tool already performs — because a bare `PASS` did not tell
  it *what* had been verified. → itemize the PASS output (§A2).
- The agent fetched and read the full 332-line tool source before running it (prudent, ~1 min). A soft
  guideline line ("the tool is tested; run it directly") is included in §C but not over-invested in.

**Core insight:** every remaining item is either (a) a stale-cache artifact that self-recovers once the
prompt is self-checking, or (b) redundant agent work caused by the tool under-reporting what it already
does. Weight goes on making the tool's output authoritative and the prompt resilient to a stale guideline
— **no new pipeline scripts** (v3 already built them; the only new tool code is the leak scan the agent
proved it wants).

## Decisions (agreed with user)

1. **Scope: deterministic polish + anti-stale-cache.** Not just analysis; not a version-number handshake.
2. **Anti-stale-cache = content self-check, not a version number.** A version handshake needs a bump on
   every guideline edit or it emits false "stale" warnings; a content self-check ("does the guideline you
   fetched mention the assembler?") is self-maintaining and matches exactly what the agent already notices.
   A human-facing date stamp is still added to the guideline (informational, not compared).
3. **Leave the 301-row sample data as-is, annotated.** Regenerating it to the current 305-row cut is
   cosmetic (the engine overwrites) and a large diff — out of scope. B1 (neutral title) + B2 (annotation)
   cover the risk.

## Design

### A. Tool — `tools/build_report.py`

**A1. Sample-name leak scan (closes F6).**
- Add `sample_names(template)` — parse the distinct `"c":"…"` values inside the template's **original**
  sample `H` block (`const H = [ … ];`). Data-driven so it survives a future sample swap. Today's set:
  `Stormhoof, Ragebrand, Grimfrost, Mistpaw`.
- Add `scan_sample_leak(cards, names)` — return any sample name that appears in the **cards** text. Scope
  to the cards (the one hand-authored, replaceable region a stale-sample leak lands in), **not** the `H`
  array, which legitimately holds real character names and could collide.
- Wire into `build_report()`: compute `names` from the template before the splice, then
  `errs += ["sample-data leak (card edited instead of replaced?): " + x for x in scan_sample_leak(cards, names)]`.
- Tests in `tools/tests/test_build_report.py`: a card mentioning `Ragebrand` fails; real names pass.

**A2. Itemized PASS output (kills the two redundant verification passes).**
- On success in `main()`, before the existing `PASS — wrote …` line, print a compact checklist of what
  was reconciled and scanned, echoing the computed values, e.g.:
  ```
  PASS — checks green:
    vs INSIGHTS: Records 305 · Distinct 111 · Chars 7 · Epic+ 87 · Best iLvl 272 · Richest 80g63s1c · Busiest 13-Jul(91) · Vendor Σ(v×qty) 2354g87s37c
    cards 13 (≥10) · external none · escapes none · sample-leak none · head/engine/footer byte-identical
  PASS — wrote report.html (185989 bytes)
  ```
- To surface the reconciled values, have `validate_against_insights` (or a light wrapper) also return the
  computed figures it checked, so the checklist reports real numbers, not just "ok". Keep it stdlib, no
  new deps.
- The existing final `PASS — wrote %s (%d bytes)` line is **unchanged** (any test asserting on it stays
  green); the checklist is strictly additive and only prints on success.

### B. Template — `docs/ai-export-template.html`

**B1. Neutralize the stale static title (closes F3).**
- `<title>Ka0s Loot History — Frostmourne, 12–17 Jul 2026</title>` → `<title>Ka0s Loot History</title>`.
- The engine sets the full realm + date range from `H` at runtime; a neutral placeholder never goes stale
  and removes the "is 12–17 wrong?" doubt. The `<title>` is in the head verbatim region, so template and
  output remain byte-identical — the `verify_verbatim` head check still passes.

**B2. Annotate the sample blocks "replace wholesale — never hand-edit".**
- One HTML comment immediately before the sample cards inside `<section id="llm">`, and one immediately
  before `const H = [`, marking them assembler-replaced sample data. Placement respects `verify_verbatim`:
  the card-region comment sits in the replaced region (guidance for a reader, absent from output); the
  `H` comment sits in the mid verbatim region (persists in output, matches template) — neither breaks the
  byte-for-byte contract.

### C. Guideline — `docs/ai-export-guideline.md`

- **C1.** After the assembler recipe: "The tool's PASS already reconciles every Summary figure, counts
  your cards, and scans for external requests, literal escapes, and sample-name leaks — you do not need to
  re-verify its output by hand."
- **C2.** In the output-contract title bullet and the fallback: "the static `<title>` is a placeholder the
  engine overwrites at load from the data — never hand-edit it" (kills F3 for the fallback path too).
- **C3.** A human-facing stamp near the top: `Guideline v3.2 · 2026-07-18` (informational; not compared).

### D. In-game prompt — `modules/Export.lua` `AIPrompt` (anti-stale-cache, the durable lever)

- In the "If you can run code" paragraph, add a self-check + template-fetch prohibition, roughly:
  *"The guideline you fetch describes this assembler; if the copy you receive does not mention
  `build_report.py`, you fetched a stale CDN cache — re-fetch it once, and either way this prompt is
  authoritative: the assembler builds, validates, and downloads the template itself in one command — never
  web_fetch the template."*
- This turns the agent's exact "the guideline doesn't mention the tool" observation into a defined
  recovery instead of a probe-and-doubt, and folds the template-fetch prohibition into the prompt so it
  holds even when the guideline is stale.
- Keep the existing rules block (title/hero, self-contained, CSV contract) intact; keep additions tight.
- Update `tests/test_export.lua` expectations. This is an **assertion edit, not a new/removed case** — the
  Lua case count should not move; regenerate `docs/test-cases.md` and bump the README `tests` badge **only
  if** the count actually changes.
- **Honest limit (per v3.1):** the prompt is baked into the installed addon, so it only reaches in-game
  exports after the user updates. It is the durable lever; the live guideline (C1/C2) is the immediate one.

## Out of scope

- **Regenerating the 301-row sample** to the current 305-row cut — cosmetic (engine overwrites); B1 + B2
  cover the risk.
- Chasing F1/F4 as content bugs — stale-cache artifacts handled by D.
- No new pipeline scripts, no engine/style change, no version bump, no data-path change.

## Success criteria

- `build_report.py` fails a build whose cards leak a template sample name, with a test proving it; real
  names pass.
- On success the tool prints an itemized checklist of every reconciled figure and scan, above the
  unchanged `PASS — wrote …` line.
- The template's static `<title>` is `Ka0s Loot History` (no stale date); the sample blocks carry a
  "replace wholesale" annotation; `verify_verbatim` still passes.
- The guideline carries the trust-the-PASS line, the title-placeholder line, and a v3.2 date stamp.
- `modules/Export.lua` `AIPrompt` carries the stale-cache self-check + template-fetch prohibition;
  `tests/test_export.lua` passes; Lua case count unchanged (or badge/`test-cases.md` regenerated if moved).
- `python3 -m unittest discover -s tools/tests` green, `lua tests/run.lua` green, `luacheck .` clean.
- End-to-end: rebuilding from the pasted v3.2 export prints the itemized PASS, reports no sample leak, and
  emits the neutral static title.
