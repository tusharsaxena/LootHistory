# tools/ — dev tooling (not shipped in the addon)

Helper scripts for maintaining Ka0s Loot History. **Not part of the addon
payload** — nothing here is listed in the `.toc`. Ratified Standard exception
(see `docs/conventions.md`).

## build_report.py — AI-report assembler + validator

Turns the addon's **Export to AI** prompt plus your analysis-cards file into a
validated, self-contained `report.html`, by filling the fixed template. Stdlib
only — runs in any Python 3.8+ sandbox.

```
python3 tools/build_report.py --prompt prompt.txt --cards cards.html -o report.html
```

- `--prompt` — the pasted export saved to a file (self-extracts HISTORY + INSIGHTS).
  Or pass `--history h.csv --insights i.csv` instead.
- `--cards` — your `<div class="card …">…</div>` blocks for the analysis section.
- `--template` — a local template path; omitted, it downloads the template in full.

It transcribes `H`, cross-checks the parse against INSIGHTS (records, distinct
items, characters, epic+, best iLvl, richest drop, busiest day, and vendor value
= Σ(v×qty)), enforces ≥10 cards, scans for external requests, and confirms the
head/engine/footer are byte-identical to the template — printing PASS/FAIL and
exiting non-zero on any failure.

### Tests

`cd tools && python3 -m unittest discover -s tests`
