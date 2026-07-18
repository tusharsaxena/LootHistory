# AI Export fix v3 — deterministic assembler + guideline hardening

**Branch:** `feat/ai-export-fix-v3`
**Date:** 2026-07-18
**Supersedes/extends:** [2026-07-17-ai-export-design.md](2026-07-17-ai-export-design.md) (the original "Export to AI"
pure-pointer design). This spec does **not** change that design's data path; it removes deterministic
work from the consuming LLM and closes guideline gaps surfaced by a real build.

## Problem

An execution log of Claude Code building a report from the pasted "Export to AI" prompt showed the
build took ~10 minutes, the large majority of it **deterministic mechanical work the model performed
by hand**, plus a handful of guideline ambiguities it had to resolve empirically.

Observed from the log:

- **The dataset was re-emitted to disk by hand — the single slowest step (~5 min).** The
  "Write the full HISTORY CSV to disk and count rows" step spans `05:44:43` → `05:49:30` (~4m47s).
  Writing a file and `wc -l` are instant; the ~5 minutes is the **model generating 262 CSV rows as
  output tokens** into a heredoc — re-typing, verbatim, data it was already handed in the pasted
  prompt. The cost is output-token re-emission, not disk I/O or parsing.
- **Ad-hoc scripts, regenerated every run.** `gen.py` transcribed the HISTORY CSV back into the `H`
  JS array (a pure CSV→JSON round-trip of the addon's own data); `splice.py` spliced cards + `H` into
  the template.
- **Validation ran four times** because the trailing-comma strip and the `\n];` slice boundary had
  live bugs the model debugged in-flight; a `diff <(...)` process-substitution call also failed
  (default shell is not bash).
- **Guideline gaps requiring guesswork:**
  - **F1 (material):** "Vendor value" aggregation is unspecified. Summing `v` alone (2064g 98s 28c)
    mismatched INSIGHTS; the true KPI is `Σ(v × qty)` (2095g 58s 7c). The model had to discover this.
  - **F2 (ambiguous):** the addon prompt (`modules/Export.lua`, `AIPrompt`) tells the builder to
    hand-title the report with a date range "from the data"; the guideline says leave the title alone
    because the engine derives it at runtime. Direct contradiction — a builder following only the
    prompt gets the end date wrong.
  - **F4 (minor):** template sample rows use trailing commas (valid JS, invalid strict JSON) →
    validation friction.
  - **F5 (minor):** counting cards by grepping the token `card` double-counts a CSS `::before` rule.
- **F3 (tooling / latent bug):** the ~169KB template truncated on a size-capped web fetch and needed a
  full `curl`. Claude Code recovered; a plain ChatGPT/Gemini fetch that caps below 168KB would
  **silently** fail the "reproduce verbatim" contract.

**Core insight:** the only genuinely non-deterministic, LLM-suited step is **step 3 — writing the
analysis cards.** Transcription, splice, validation, and title derivation are all mechanical.

## Decisions (agreed)

1. **Ship an assembler script only** — keep the ratified CSV-based prompt/data path unchanged. The
   determinism and speed win comes from a shipped, tested tool that code-capable agents run, plus
   guideline fixes that help chat-only models too.
2. **Template fetch:** document a full download and shrink only where provably safe.
3. **Tooling home:** a new `tools/` directory (Python), **ratified as a Standard exception** —
   dev-tooling, not part of the shipped addon payload (`.toc`). Record the resolution in `docs/`.

## Design

### 0. Eliminate dataset re-emission — the ~5-minute step (highest-value fix)

The slowest step in the log was the model re-typing the entire dataset into a heredoc so a script
could read it. The data must reach disk **without passing back through the model's output**. Note this
is a *delivery/workflow* fix, not a data-path change — the CSV prompt format is unchanged.

- **Primary: file delivery.** Recommend, in both `docs/ai-export-guideline.md` and the addon help text
  (`modules/Export.lua` help frame and the `?` button), that the user hand the export to the AI **as a
  file** — upload/attach it in ChatGPT / Gemini / Claude, or in Claude Code paste it (large pastes are
  auto-stored as a file). It is then on disk from the start; the agent reads the path. Zero
  re-emission.
- **Guardrail: an explicit "do not re-emit" rule** in the guideline's run-code path — do **not**
  reproduce the dataset via a heredoc or a `Write`; point `build-report.py --prompt` at the file the
  environment already has.
- **Tool self-extracts** both `=== HISTORY ===` / `=== INSIGHTS ===` blocks and counts rows itself, so
  the model never splits, retypes, or counts the data.
- **Known limit:** if an agent is handed the data *only* as inline chat text and its harness does not
  auto-file large pastes, some re-emission is unavoidable — which is why file delivery is the primary
  recommendation, not merely an optimization.

Net: the data-to-disk step drops from ~thousands of output tokens (~5 min) to one short command line.

### 1. `tools/build-report.py` — deterministic assembler + validator

Stdlib-only (`argparse`, `urllib`, `json`, `csv`, `re`) so it runs unmodified in any code sandbox
(Claude Code container, ChatGPT code interpreter). No third-party installs.

**Interface**

```
python3 tools/build-report.py --prompt prompt.txt --cards cards.html -o report.html
                              [--template PATH]   # default: full download of the raw URL
                              [--history h.csv --insights i.csv]  # alt inputs to --prompt
```

- `--prompt` is the pasted addon output; the script self-extracts the `=== HISTORY (CSV) ===` and
  `=== INSIGHTS (CSV) ===` blocks (delimiters emitted by `E:AIPrompt`).
- `--cards` is the LLM-authored `<div class="card …">…</div>` block for `<section id="llm">`.
- `--template` defaults to a **full** download of
  `https://raw.githubusercontent.com/tusharsaxena/LootHistory/refs/heads/master/docs/ai-export-template.html`
  (no fetch cap); a local path override is accepted.

**Deterministic transform**

- CSV → `H`, exact key order `{d,t,c,cl,id,n,q,qr,il,b,v,ty,st,qty,s,z,wh}` per the guideline table;
  `il` → `null` when blank; numeric fields coerced; `c` = name part, `REALM` = realm suffix of `char`.
- Emit `H` as **valid JSON, one object per line, no trailing commas** (removes F4 from the output).
- Splice by string markers: replace the `const H = [ … ];` body and the `<section id="llm">` sample
  cards; leave `const REALM = "…";` set to the derived realm. Everything else byte-untouched.

**Validation (prints a PASS/FAIL report; non-zero exit on any failure)**

- `H` row count; every row has exact key order; `H` parses as strict JSON.
- Cross-check against the INSIGHTS block: records, distinct items, characters, epic+ count, best
  item level, richest drop, busiest day, and **vendor value = Σ(v × qty)** (F1).
- Card count via a real selector (`<div class="card`) — not the bare token (F5); assert ≥ 10.
- No external load-time requests (`<script src`, `<link href`, `@import`, `url(http`, `fetch(`,
  `XMLHttpRequest`, `<img src`, `@font-face`); http(s) URLs limited to click-through hrefs.
- Head (before the cards) and engine/footer tail (from `];` to EOF) **byte-identical to template**.

### 2. `tools/tests/test_build_report.py` — unit tests

Small fixture (a handful of HISTORY + INSIGHTS rows + the expected `H`) proving: CSV→H mapping and key
order, `il` null handling, `REALM` derivation, vendor value = Σ(v×qty), trailing-comma-free output,
the external-request scan (positive and negative), and the head/tail verbatim check against a stub
template. Pure stdlib `unittest`; runnable via `python3 -m unittest` from `tools/`.

**Suite wiring:** the addon's `lua tests/run.lua` remains the addon test battery unchanged. The Python
tests are a separate, additive check (documented in `docs/testing.md`); no cross-language coupling.

### 3. Guideline + prompt fixes

`docs/ai-export-guideline.md`:

- New **"If you can run code"** subsection pointing at `tools/build-report.py` (fetch it or run it
  in-repo), with the existing manual steps kept as the chat-only fallback.
- **F1:** state value KPIs aggregate as `Σ(v × qty)`; the engine does all money math.
- **F3:** the template is ~169KB — download it in full (`curl`/`wget`); a size-capped fetch truncates
  it and breaks the verbatim contract.
- **F4:** trailing-comma caveat (the assembler emits valid JSON; a manual builder must strip before a
  strict `JSON.parse`).
- **F5:** count cards by `<div class="card`, not the token `card`.

`modules/Export.lua` (`AIPrompt`):

- **F2:** remove the "title the report literally … taking the realm and date range from the data"
  instruction that contradicts the guideline; align it with "the engine derives the title, hero, and
  date range — leave them alone." Data path (the two CSVs) is otherwise unchanged. Update
  `tests/test_export.lua` expectations accordingly.

### 4. Template shrink (conservative, optional)

Strip only provably-safe whitespace / blank-line runs; re-verify the engine loads and the report
renders unchanged; update line anchors in docs (`docs/*` reference specific line numbers). If the byte
saving is marginal versus the risk to the verbatim contract, **stop and report** rather than ship the
shrink. The full-download documentation (F3) is the primary mitigation; the shrink is a nice-to-have.

### 5. Standards deviation record

`tools/` (Python dev-tooling) is ratified as a Standard exception — not part of the shipped addon
payload. Record the resolution in `docs/` (a dated note under `docs/audits/2026-07-18/` or a line in
`docs/conventions.md`) per the CLAUDE.md deviation rule, and update the README/`docs/testing.md` to
mention the tooling and how to run its tests.

## Out of scope

- No change to the addon's data path (no pre-built `H` block in the prompt; CSV stays).
- No change to the engine, styling, or the report's runtime behavior.
- No version bump (per repo rule; only on explicit instruction).

## Success criteria

- A code-capable agent produces a valid report from the pasted prompt with **one** `build-report.py`
  invocation — no ad-hoc scripts, no multi-pass validation debugging.
- The dataset is never re-emitted to disk by the model: the guideline + addon help recommend file
  delivery and forbid heredoc/`Write` reproduction of the data, so the former ~5-minute step is gone.
- `build-report.py` exits non-zero and explains itself on any contract violation.
- Python unit tests pass; `lua tests/run.lua` and `luacheck .` stay green.
- The guideline no longer contains the F1/F2/F4/F5 ambiguities; F3 is documented.
- The `tools/` exception is recorded in `docs/`.
