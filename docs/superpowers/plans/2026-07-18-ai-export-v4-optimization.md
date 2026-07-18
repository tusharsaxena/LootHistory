# AI Export v4 — Speed / Trust Optimization Plan

> **Status: IMPLEMENTED** on branch `feat/ai-export-v4` (2026-07-18). All four levers landed; Python
> 42/42, Lua 225/225, luacheck clean; a HISTORY-only build verified end-to-end against the real template.
> Guideline stamp → `v1.1.0 rev4`. Not yet committed — left in the working tree for the user to commit.

**Goal:** Cut the wall-clock and wasted effort of an *already-healthy* AI-export run by removing
redundant verification passes, shrinking the fallback data re-emission, preferring an already-filed
paste, and fixing a stale-cache recovery step that doesn't actually work. Approved scope: levers
**A + B + C + D**, with **full trust** on lever A (per user ruling, 2026-07-18).

## Context — why (and the load-bearing caveat)

Source: the v2.3 execution log of a 315-row build (`execution-log-v2.3.html`) plus the addon-generated
prompt.

**The log's per-step timestamps are self-estimated, not measured.** Its header claims ~11 min; the real
run was ~112 min. Its own note says wall-clock instrumentation was unavailable and timestamps are
"approximate and monotonic … spaced to preserve production order." So specific durations read off it
(e.g. "`cp` took 50 s", "the write took 4 min") are the model's invented spacing, **not** measurements.
We therefore optimize **structure** (step count + token volume), not the fabricated seconds. Lever **E**
(real instrumentation) is deferred but noted — without it we cannot *prove* a speedup.

Two structural wastes are real regardless of timing:

1. **Triple verification.** The model reconciled the 8 Summary metrics in Python *before* running the
   assembler, the assembler reconciled them again (its PASS), and the model ran *another* independent
   self-containment check *after*. Two of three are duplication, invited by permissive guideline wording
   ("you do not need to re-run those checks").
2. **Fallback re-emission of data the tool ignores.** The export arrived inline, so the model rewrote
   HISTORY + **all** of INSIGHTS to `export.txt`. But the assembler only ever reads the INSIGHTS
   **Summary** section — the `By Source / By Quality / Top Items / By Day` tail (~230 lines here) is
   parsed and never used. F6 in the log proves it: the model dropped that tail by accident and the build
   still PASSed.

## Global constraints

- **Stdlib only** in `tools/build_report.py`.
- **Never bump the addon version** (TOC / `NS.version` / README). This plan bumps only the *guideline*
  stamp → `v1.1.0 rev4`.
- **Flag standards deviations.** None identified so far (see Standards note). If implementation surfaces
  one, stop and flag per CLAUDE.md.
- Keep the substrings `stale` and `web_fetch` in the addon prompt (`tests/test_export.lua` asserts them).

## The four levers

### A — Forbid re-verification  *(guideline prose; fixes the "doesn't trust data" behavior)*

- **File:** `docs/ai-export-guideline.md`, the existing "trust the PASS" paragraph.
- **Change:** rewrite from permissive to imperative:
  - Run the assembler **exactly once**. Its **PASS is the complete and only validation** — it already
    checks records / distinct / chars / epic+ / best iLvl / richest / busiest / vendor = Σ(v×qty), card
    count, external requests, literal escapes, sample-name leak, and byte-identical head/engine/footer.
  - Do **NOT** reconcile the data yourself — **not** in Python before running, **not** after. No
    independent Summary recompute; no post-run self-containment scan.
  - **Trust the inputs.** HISTORY and INSIGHTS are authoritative (the addon computed them). Re-deriving
    any figure by hand is forbidden and adds nothing.
- **Trade-off (accepted — full trust):** if the tool ever has a bug or the paste was silently truncated,
  there is no second net. Mitigation: the tool's internal validation *is* the net; the drift case is
  covered by lever B keeping the Summary cross-check on the one path where transcription can drift.

### B — Shrink the fallback re-emission  *(guideline + `build_report.py` + Python tests)*

- **Guideline:** in the write-once branch, state that you only need the **HISTORY block + the INSIGHTS
  `Summary` rows**. The rest of INSIGHTS is a card-writing reference already in context — do **not**
  re-type it. (Cite F6: the tail is unused by the assembler.)
- **`tools/build_report.py`:** make the INSIGHTS block **optional**.
  - `extract_blocks`: if the `=== INSIGHTS (CSV) ===` marker is absent, return `insights=""`/`None`
    instead of raising. HISTORY marker stays required.
  - `build_report`: when INSIGHTS absent, skip `validate_against_insights` (still print figures computed
    from HISTORY). When present (even Summary-only), validate as today.
  - PASS summary must still print (figures come from HISTORY, not INSIGHTS).
- **Tests (`tools/tests/test_build_report.py`):**
  - Summary-only INSIGHTS → validates + PASS.
  - No INSIGHTS block → builds, PASS, validation skipped.
  - Update `test_extract_blocks` expectations for the relaxed INSIGHTS requirement.

### C — Prefer the already-filed paste  *(guideline prose)*

- **File:** `docs/ai-export-guideline.md`, the "get the export onto disk" step.
- **Change:** lead with — first check whether the platform already filed the paste (an uploads dir, or a
  path the tool handed you) and point `--prompt` at **that** file directly, writing nothing. Only if it
  genuinely isn't on disk, fall back to the write-once path (HISTORY + Summary, per lever B).

### D — Fix the stale-cache recovery  *(addon prompt + guideline + Lua test)*

- **`modules/Export.lua` (`AIPrompt`):** the "re-fetch it once" remedy doesn't bust the cache (and was
  blocked as a `PERMISSIONS_ERROR` in the log). Replace with: fetch a fresh copy via a
  **cache-bypassing** method — a code-container `curl`/`wget`, or a `?v=<n>` query-string bust — rather
  than re-issuing the same cached `web_fetch`. Keep `stale` and `web_fetch` in the text.
- **Guideline:** mirror the same cache-bust wording wherever the stale-cache note appears.
- **`tests/test_export.lua`:** existing asserts (`stale`, `web_fetch`) still pass. Optionally add an
  assert for the cache-bust token (`curl`/`cache`). If a *new* test case is added, regenerate
  `docs/test-cases.md` and the README `tests` badge in the same change (CLAUDE.md hard rule).

## Version, badges, standards

- Guideline stamp → `*Guideline v1.1.0 rev4 · <date>*`. **No addon version bump.**
- Python suite has no cited count in `docs/testing.md` — no doc number to sync. New Python cases don't
  touch the Lua badge.
- Lua badge / `docs/test-cases.md`: only if a Lua case is added/renamed (lever D optional assert).
- **Standards note:** no deviation from the Ka0s WoW Addon Standard identified. "Trust the tool / forbid
  re-verification" is a guideline-authoring choice; optional-INSIGHTS is internal tooling. Nothing to
  flag today.

## Deferred (not in this plan)

- **E — real instrumentation.** Needed to *prove* a speedup; the current log can't. Decide a measurement
  method before/after a future run.
- The **execution-log deliverable** is extra scope the user requests per-run; a normal report build omits
  it. Not a code change — a usage note.

## Suggested build order

1. Lever B tooling (`build_report.py` + tests) — self-contained, gives the green gate to build on.
2. Lever A + B + C guideline prose (one pass over `docs/ai-export-guideline.md`) + rev4 stamp.
3. Lever D (`Export.lua` + guideline mirror + `test_export.lua`).
4. Run `python3 -m unittest discover -s tests` (in `tools/`), `lua tests/run.lua`, `luacheck .`.
