# AI Export fix v3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the deterministic mechanical work (CSV→`H` transcription, splice, multi-pass validation) out of the report-building LLM into a shipped, unit-tested `tools/build_report.py`, and close the guideline gaps (F1–F5) plus the ~5-minute dataset re-emission (§0) surfaced by a real execution log.

**Architecture:** A stdlib-only Python assembler+validator (`tools/build_report.py`) that self-extracts the two CSV blocks from the pasted addon prompt, transcribes HISTORY → the `H` JS array (valid JSON, exact key order), cross-checks the parse against the INSIGHTS block, splices `H`+`REALM`+the LLM's analysis cards into the template, and validates the output (card count, no external requests, head/tail byte-identical to template). The addon's CSV data path is unchanged; the guideline gains a "run-code" path and a file-delivery recommendation, and one contradictory prompt line is fixed in `modules/Export.lua`.

**Tech Stack:** Python 3 (stdlib only: `argparse`, `csv`, `json`, `re`, `urllib`, `unittest`); Lua 5.1 (existing addon + `tests/run.lua`); Markdown docs.

## Global Constraints

- **Python: stdlib only.** No third-party imports — the tool must run unmodified in any code sandbox (Claude Code container, ChatGPT code interpreter). Target Python 3.8+.
- **Module filename is `build_report.py`** (underscore, not the spec's hyphenated prose form) so `tools/tests/` can `import build_report`. All CLI/doc examples use `python3 tools/build_report.py`.
- **`H` is emitted as valid JSON** — one object per line, keys in exact order `d,t,c,cl,id,n,q,qr,il,b,v,ty,st,qty,s,z,wh`, **no trailing comma** on the last row (this removes F4 from the output).
- **Never bump the version** (TOC, `NS.version`, README badge/history) — not part of this work.
- **`tools/` is a ratified Standard exception** (dev-tooling, not shipped in the `.toc` payload); Task 8 records it in `docs/`.
- **Addon test gate unchanged:** `lua tests/run.lua` and `luacheck .` must stay green. Python tests are an additive, separate check.
- **Commits:** end every commit message with the two trailers:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01PaUpVRwgBPMjNmFQd9Aj4Q
  ```
- **Template markers (verbatim, in `docs/ai-export-template.html`):** `const REALM = "Frostmourne";`, `const H = [\n` … `\n];`, `<section id="llm">` … `</section>`, and `<div class="grid">` (the card container).
- **Prompt block delimiters (emitted by `E:AIPrompt`):** `=== HISTORY (CSV) ===` and `=== INSIGHTS (CSV) ===`.

---

## File Structure

- `tools/build_report.py` — the assembler+validator (library functions + `main` CLI). One responsibility: turn a prompt file + a cards file + the template into a validated `report.html`.
- `tools/tests/__init__.py` — empty; makes `tests` a package for `python3 -m unittest`.
- `tools/tests/test_build_report.py` — unit + end-to-end tests with inline fixtures (no external files).
- `tools/README.md` — one-screen usage note for the tool (also linked from the guideline).
- `docs/ai-export-guideline.md` — **Modify:** add the run-code path, §0 file-delivery + no-re-emit, and the F1/F3/F4/F5 clarifications.
- `modules/Export.lua` — **Modify:** F2 (remove the contradictory hand-title lines from `AIPrompt`) and add the file-delivery line to the help frame.
- `tests/test_export.lua` — **Modify:** update the `AIPrompt` assertion to match the F2 change.
- `docs/testing.md` — **Modify:** add a short "Tooling tests (Python)" section.
- `docs/conventions.md` — **Modify:** record the `tools/` Standard exception.
- `README.md` — **Modify:** one line pointing at `tools/` and how to run its tests.
- `docs/ai-export-template.html` — **Modify (Task 9, conservative/optional):** safe whitespace shrink, or stop-and-report.

---

## Interfaces (the public surface of `tools/build_report.py`)

Later tasks rely on these exact names/signatures:

- `HKEYS = ["d","t","c","cl","id","n","q","qr","il","b","v","ty","st","qty","s","z","wh"]`
- `parse_history_csv(text: str) -> tuple[str, list[dict]]` — returns `(realm, rows)`; each `row` is an ordered dict with keys `HKEYS`.
- `emit_h_body(rows: list[dict]) -> str` — the JSON rows joined by `,\n`, **no trailing comma**.
- `extract_blocks(prompt_text: str) -> tuple[str, str]` — returns `(history_csv, insights_csv)`.
- `parse_insights(text: str) -> dict` — `{(section, label): {"count": str, "value": str}}`.
- `parse_money(s: str) -> int` — `"10g 8s 0c"` → `100800`.
- `validate_against_insights(rows: list[dict], insights: dict) -> list[str]` — list of mismatch messages (empty = OK).
- `card_count(html: str) -> int` — count of `<div class="card` inside `<section id="llm">`.
- `scan_external(html: str) -> list[str]` — labels of any external load-time request found.
- `splice(template: str, realm: str, h_body: str, cards: str) -> str`.
- `verify_verbatim(template: str, output: str) -> list[str]` — head/mid/tail byte-identity (REALM line masked).
- `main(argv: list[str]) -> int` — CLI entry; returns process exit code.

**Test command (all tasks):** from repo root — `cd tools && python3 -m unittest tests.test_build_report -v`
(single test: `cd tools && python3 -m unittest tests.test_build_report.TestX.test_y -v`).

---

### Task 1: Scaffold `tools/` + CSV→H transform

**Files:**
- Create: `tools/build_report.py`
- Create: `tools/tests/__init__.py`
- Create: `tools/tests/test_build_report.py`

**Interfaces:**
- Produces: `HKEYS`, `parse_history_csv`, `emit_h_body`.

- [ ] **Step 1: Create the test package marker**

Create `tools/tests/__init__.py` as an empty file.

- [ ] **Step 2: Write the failing tests**

Create `tools/tests/test_build_report.py`:

```python
import json
import unittest

import build_report as br

HISTORY = (
    "ts,date,time,char,classFile,itemID,itemName,quality,qualityRaw,itemLevel,"
    "bound,sellPrice,sellPriceRaw,itemType,itemSubType,quantity,source,zone,wowheadLink\r\n"
    "100,12-Jul-2026,20:00,Aria-Frostmourne,mage,111,Big Sword,Epic,4,246,"
    "Bind on Pickup,10g 0s 0c,100000,Weapon,Sword,1,KILL,Town,https://wh/111\r\n"
    "200,12-Jul-2026,21:00,Aria-Frostmourne,mage,222,Herb,Common,1,,"
    "Not Bound,0g 1s 0c,100,Tradeskill,Herb,5,KILL,Field,https://wh/222\r\n"
    "300,13-Jul-2026,22:00,Bob-Frostmourne,warrior,222,Herb,Common,1,,"
    "Not Bound,0g 1s 0c,100,Tradeskill,Herb,3,OTHER,Field,https://wh/222\r\n"
)


class TestCsvToH(unittest.TestCase):
    def test_realm_and_row_count(self):
        realm, rows = br.parse_history_csv(HISTORY)
        self.assertEqual(realm, "Frostmourne")
        self.assertEqual(len(rows), 3)

    def test_first_row_mapping_and_key_order(self):
        _, rows = br.parse_history_csv(HISTORY)
        self.assertEqual(list(rows[0].keys()), br.HKEYS)
        self.assertEqual(rows[0], {
            "d": "12-Jul-2026", "t": "20:00", "c": "Aria", "cl": "MAGE",
            "id": 111, "n": "Big Sword", "q": "Epic", "qr": 4, "il": 246,
            "b": "Bind on Pickup", "v": 100000, "ty": "Weapon", "st": "Sword",
            "qty": 1, "s": "KILL", "z": "Town", "wh": "https://wh/111",
        })

    def test_blank_itemlevel_is_null(self):
        _, rows = br.parse_history_csv(HISTORY)
        self.assertIsNone(rows[1]["il"])

    def test_source_and_class_uppercased(self):
        _, rows = br.parse_history_csv(HISTORY)
        self.assertEqual(rows[2]["s"], "OTHER")
        self.assertEqual(rows[2]["cl"], "WARRIOR")

    def test_emit_h_body_is_valid_json_no_trailing_comma(self):
        _, rows = br.parse_history_csv(HISTORY)
        body = br.emit_h_body(rows)
        self.assertFalse(body.rstrip().endswith(","))
        parsed = json.loads("[" + body + "]")
        self.assertEqual(len(parsed), 3)
        self.assertEqual(parsed[0]["c"], "Aria")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd tools && python3 -m unittest tests.test_build_report -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'build_report'`.

- [ ] **Step 4: Implement the transform**

Create `tools/build_report.py`:

```python
#!/usr/bin/env python3
"""Ka0s Loot History — deterministic AI-report assembler + validator.

Turns the pasted "Export to AI" prompt (HISTORY + INSIGHTS CSV blocks) plus an
LLM-authored analysis-cards file into a validated, self-contained report.html by
filling the fixed template. Stdlib only — runs unmodified in any code sandbox.
"""
import csv
import io
import json

HKEYS = ["d", "t", "c", "cl", "id", "n", "q", "qr", "il", "b",
         "v", "ty", "st", "qty", "s", "z", "wh"]


def _int_or_none(s):
    s = (s or "").strip()
    return int(s) if s != "" else None


def parse_history_csv(text):
    """(realm, rows). rows are ordered dicts keyed by HKEYS; realm is the most
    common '-Realm' suffix of the char column (first-seen wins ties)."""
    reader = csv.DictReader(io.StringIO(text))
    rows, realms = [], []
    for r in reader:
        char = r["char"]
        name, _, realm = char.rpartition("-")
        if name == "":            # no '-' present
            name, realm = char, ""
        realms.append(realm)
        rows.append({
            "d": r["date"],
            "t": r["time"],
            "c": name,
            "cl": (r["classFile"] or "").strip().upper(),
            "id": int(r["itemID"]),
            "n": r["itemName"],
            "q": r["quality"],
            "qr": int(r["qualityRaw"]),
            "il": _int_or_none(r["itemLevel"]),
            "b": r["bound"],
            "v": int(r["sellPriceRaw"]),
            "ty": r["itemType"],
            "st": r["itemSubType"],
            "qty": int(r["quantity"]),
            "s": (r["source"] or "").strip().upper(),
            "z": r["zone"],
            "wh": r["wowheadLink"],
        })
    realm = ""
    if realms:
        realm = max(sorted(set(realms), key=realms.index),
                    key=realms.count)
    return realm, rows


def emit_h_body(rows):
    """JSON rows, one per line, joined by ',\\n' — NO trailing comma."""
    lines = [json.dumps(o, ensure_ascii=False, separators=(",", ":"))
             for o in rows]
    return ",\n".join(lines)
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd tools && python3 -m unittest tests.test_build_report -v`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
cd /mnt/d/Profile/Users/Tushar/Documents/GIT/LootHistory
git add tools/build_report.py tools/tests/__init__.py tools/tests/test_build_report.py
git commit -F - <<'MSG'
feat(tools): CSV->H transform for the AI-report assembler

New tools/build_report.py: parse_history_csv + emit_h_body turn the HISTORY CSV
into the H JS array (exact key order, il-null handling, valid JSON with no
trailing comma). Stdlib-only; unit-tested.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PaUpVRwgBPMjNmFQd9Aj4Q
MSG
```

---

### Task 2: Prompt block extraction + INSIGHTS parsing

**Files:**
- Modify: `tools/build_report.py`
- Modify: `tools/tests/test_build_report.py`

**Interfaces:**
- Consumes: (none new)
- Produces: `extract_blocks`, `parse_insights`, `parse_money`.

- [ ] **Step 1: Add the failing tests**

Append to `tools/tests/test_build_report.py` (before the `if __name__` guard):

```python
INSIGHTS = (
    "Section,Label,Count,Value\r\n"
    "Summary,Records,3,\r\n"
    "Summary,Distinct items,2,\r\n"
    "Summary,Characters,2,\r\n"
    "Summary,Vendor value,,10g 8s 0c\r\n"
    "Summary,Epic+ drops,1,\r\n"
    "Summary,Best drop iLvl,246,\r\n"
    "Summary,Richest drop,,10g 0s 0c\r\n"
    "Summary,Busiest day,12-Jul-2026 (2),\r\n"
)

PROMPT = (
    "You are given a WoW loot-history export.\n"
    "=== HISTORY (CSV) ===\n" + HISTORY +
    "=== INSIGHTS (CSV) ===\n" + INSIGHTS
)


class TestExtractAndInsights(unittest.TestCase):
    def test_extract_blocks(self):
        hist, ins = br.extract_blocks(PROMPT)
        self.assertTrue(hist.startswith("ts,date,time"))
        self.assertIn("Big Sword", hist)
        self.assertNotIn("=== INSIGHTS", hist)
        self.assertTrue(ins.startswith("Section,Label"))
        self.assertIn("Vendor value", ins)

    def test_parse_money(self):
        self.assertEqual(br.parse_money("10g 8s 0c"), 100800)
        self.assertEqual(br.parse_money("0g 0s 7c"), 7)

    def test_parse_insights_lookup(self):
        ins = br.parse_insights(INSIGHTS)
        self.assertEqual(ins[("Summary", "Records")]["count"], "3")
        self.assertEqual(ins[("Summary", "Vendor value")]["value"], "10g 8s 0c")
```

- [ ] **Step 2: Run to verify failure**

Run: `cd tools && python3 -m unittest tests.test_build_report.TestExtractAndInsights -v`
Expected: FAIL — `AttributeError: module 'build_report' has no attribute 'extract_blocks'`.

- [ ] **Step 3: Implement extraction + INSIGHTS parsing**

Add to `tools/build_report.py` (after `emit_h_body`; add `import re` to the top imports):

```python
HISTORY_MARK = "=== HISTORY (CSV) ==="
INSIGHTS_MARK = "=== INSIGHTS (CSV) ==="


def extract_blocks(prompt_text):
    """Split the pasted prompt into (history_csv, insights_csv)."""
    if HISTORY_MARK not in prompt_text or INSIGHTS_MARK not in prompt_text:
        raise ValueError("prompt is missing the HISTORY/INSIGHTS markers")
    after_h = prompt_text.split(HISTORY_MARK, 1)[1]
    history, insights = after_h.split(INSIGHTS_MARK, 1)
    return history.strip("\n") + "\n", insights.strip("\n") + "\n"


def parse_money(s):
    """'10g 8s 0c' -> copper int. Missing parts default to 0."""
    m = re.search(r"(-?\d+)\s*g\s*(\d+)\s*s\s*(\d+)\s*c", s or "")
    if not m:
        return 0
    g, si, c = (int(x) for x in m.groups())
    return g * 10000 + si * 100 + c


def parse_insights(text):
    """{(section, label): {'count': str, 'value': str}}."""
    out = {}
    reader = csv.DictReader(io.StringIO(text))
    for r in reader:
        out[(r["Section"], r["Label"])] = {
            "count": (r.get("Count") or "").strip(),
            "value": (r.get("Value") or "").strip(),
        }
    return out
```

- [ ] **Step 4: Run to verify pass**

Run: `cd tools && python3 -m unittest tests.test_build_report -v`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add tools/build_report.py tools/tests/test_build_report.py
git commit -F - <<'MSG'
feat(tools): prompt block extraction + INSIGHTS parsing

extract_blocks splits the pasted prompt on the === HISTORY/INSIGHTS === markers
so the tool self-extracts both CSVs (the model never splits or retypes them);
parse_insights + parse_money read the summary for cross-checking.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PaUpVRwgBPMjNmFQd9Aj4Q
MSG
```

---

### Task 3: Validation — INSIGHTS cross-check, card count, external-request scan

**Files:**
- Modify: `tools/build_report.py`
- Modify: `tools/tests/test_build_report.py`

**Interfaces:**
- Consumes: `HKEYS`, `parse_history_csv`, `parse_insights`, `parse_money`.
- Produces: `validate_against_insights`, `card_count`, `scan_external`.

- [ ] **Step 1: Add the failing tests**

Append to `tools/tests/test_build_report.py`:

```python
GOOD_HTML = (
    '<section id="llm"><div class="grid">'
    '<div class="card sp6">one</div>'
    '<div class="card sp4">two</div>'
    "</div></section>"
    '<a href="https://www.wowhead.com/item=111">Big Sword</a>'
)
BAD_HTML = (
    '<section id="llm"><div class="card sp6">only</div></section>'
    '<script src="https://cdn.example.com/x.js"></script>'
    '<link href="https://x/y.css" rel="stylesheet">'
)


class TestValidation(unittest.TestCase):
    def setUp(self):
        _, self.rows = br.parse_history_csv(HISTORY)
        self.ins = br.parse_insights(INSIGHTS)

    def test_insights_crosscheck_clean(self):
        self.assertEqual(br.validate_against_insights(self.rows, self.ins), [])

    def test_insights_crosscheck_detects_vendor_mismatch(self):
        bad = dict(self.ins)
        bad[("Summary", "Vendor value")] = {"count": "", "value": "99g 0s 0c"}
        errs = br.validate_against_insights(self.rows, bad)
        self.assertTrue(any("Vendor value" in e for e in errs))

    def test_card_count(self):
        self.assertEqual(br.card_count(GOOD_HTML), 2)

    def test_scan_external_clean(self):
        self.assertEqual(br.scan_external(GOOD_HTML), [])

    def test_scan_external_flags_script_and_link(self):
        found = br.scan_external(BAD_HTML)
        self.assertIn("script src", found)
        self.assertIn("<link href>", found)
```

- [ ] **Step 2: Run to verify failure**

Run: `cd tools && python3 -m unittest tests.test_build_report.TestValidation -v`
Expected: FAIL — `AttributeError: ... 'validate_against_insights'`.

- [ ] **Step 3: Implement validation**

Add to `tools/build_report.py`:

```python
SEC = '<section id="llm">'
SEC_END = "</section>"

EXTERNAL_PATTERNS = [
    (r"<script[^>]+src=", "script src"),
    (r"<link[^>]+href=", "<link href>"),
    (r"@import", "@import"),
    (r"url\(\s*https?:", "url(http)"),
    (r"\bfetch\s*\(", "fetch()"),
    (r"XMLHttpRequest", "XHR"),
    (r"<img[^>]+src=", "<img src>"),
    (r"@font-face", "@font-face"),
]


def _fmt_money(c):
    return "%dg %ds %dc" % (c // 10000, (c % 10000) // 100, c % 100)


def validate_against_insights(rows, insights):
    """Cross-check the transcribed rows against the INSIGHTS Summary.
    Returns a list of human-readable mismatch messages (empty == OK)."""
    errs = []

    def summ(label):
        return insights.get(("Summary", label))

    def check_count(label, actual):
        s = summ(label)
        if s and s["count"] != "" and str(actual) != s["count"]:
            errs.append("%s: computed %s, INSIGHTS says %s"
                        % (label, actual, s["count"]))

    check_count("Records", len(rows))
    check_count("Distinct items", len({o["id"] for o in rows}))
    check_count("Characters", len({o["c"] for o in rows}))
    check_count("Epic+ drops", sum(1 for o in rows if o["qr"] >= 4))
    ils = [o["il"] for o in rows if o["il"] is not None]
    if ils:
        check_count("Best drop iLvl", max(ils))

    # Vendor value = sum(v * qty)  (F1)
    s = summ("Vendor value")
    if s and s["value"]:
        computed = sum(o["v"] * o["qty"] for o in rows)
        if computed != parse_money(s["value"]):
            errs.append("Vendor value: computed %s, INSIGHTS says %s"
                        % (_fmt_money(computed), s["value"]))

    # Richest drop = max per-unit v
    s = summ("Richest drop")
    if s and s["value"] and rows:
        richest = max(o["v"] for o in rows)
        if richest != parse_money(s["value"]):
            errs.append("Richest drop: computed %s, INSIGHTS says %s"
                        % (_fmt_money(richest), s["value"]))

    # Busiest day: compare the count inside "Day (N)"
    s = summ("Busiest day")
    if s and s["count"]:
        m = re.search(r"\((\d+)\)", s["count"])
        if m:
            counts = {}
            for o in rows:
                counts[o["d"]] = counts.get(o["d"], 0) + 1
            busiest = max(counts.values()) if counts else 0
            if busiest != int(m.group(1)):
                errs.append("Busiest day: computed %d, INSIGHTS says %s"
                            % (busiest, m.group(1)))
    return errs


def card_count(html):
    """Count analysis cards inside the llm section (F5: match the div, not the
    bare 'card' token that also appears in a CSS ::before rule)."""
    start = html.index(SEC)
    end = html.index(SEC_END, start)
    return html[start:end].count('<div class="card')


def scan_external(html):
    return [label for pat, label in EXTERNAL_PATTERNS if re.search(pat, html)]
```

- [ ] **Step 4: Run to verify pass**

Run: `cd tools && python3 -m unittest tests.test_build_report -v`
Expected: PASS (14 tests).

- [ ] **Step 5: Commit**

```bash
git add tools/build_report.py tools/tests/test_build_report.py
git commit -F - <<'MSG'
feat(tools): INSIGHTS cross-check + card-count + external-request validators

validate_against_insights cross-checks the transcribed rows against the INSIGHTS
summary, with Vendor value = sum(v*qty) (F1). card_count matches the card div,
not the bare token (F5). scan_external flags any load-time external request.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PaUpVRwgBPMjNmFQd9Aj4Q
MSG
```

---

### Task 4: Splice + verbatim verification

**Files:**
- Modify: `tools/build_report.py`
- Modify: `tools/tests/test_build_report.py`

**Interfaces:**
- Consumes: `emit_h_body`, `parse_history_csv`.
- Produces: `splice`, `verify_verbatim`.

- [ ] **Step 1: Add the failing tests**

Append to `tools/tests/test_build_report.py`:

```python
STUB_TEMPLATE = (
    '<title>Ka0s Loot History</title>\n'
    "HEAD-CONTENT\n"
    '<section id="llm">\n'
    '  <div class="grid">\n'
    '      <div class="card sp6">SAMPLE A</div>\n'
    '      <div class="card sp6">SAMPLE B</div>\n'
    "  </div>\n"
    "</section>\n"
    "MIDDLE-ENGINE\n"
    'const REALM = "Frostmourne";\n'
    "const H = [\n"
    '{"old":1},\n'
    "];\n"
    "TAIL-ENGINE-FOOTER\n"
)

NEW_CARDS = (
    '      <div class="card sp6">NEW ONE</div>\n'
    '      <div class="card sp4">NEW TWO</div>'
)


class TestSplice(unittest.TestCase):
    def _build(self, realm="Illidan"):
        _, rows = br.parse_history_csv(HISTORY.replace("Frostmourne", realm))
        body = br.emit_h_body(rows)
        return br.splice(STUB_TEMPLATE, realm, body, NEW_CARDS)

    def test_splice_replaces_h_and_realm(self):
        out = self._build()
        self.assertIn('const REALM = "Illidan";', out)
        self.assertNotIn('{"old":1}', out)
        self.assertIn('"c":"Aria"', out)
        # H body is valid JSON, no trailing comma
        s = out.index("const H = [\n") + len("const H = [\n")
        e = out.index("\n];", s)
        self.assertEqual(len(json.loads("[" + out[s:e] + "]")), 3)

    def test_splice_replaces_cards(self):
        out = self._build()
        self.assertNotIn("SAMPLE A", out)
        self.assertIn("NEW ONE", out)
        self.assertEqual(br.card_count(out), 2)

    def test_verify_verbatim_passes_for_clean_splice(self):
        out = self._build()
        self.assertEqual(br.verify_verbatim(STUB_TEMPLATE, out), [])

    def test_verify_verbatim_flags_head_tamper(self):
        out = self._build().replace("HEAD-CONTENT", "HACKED")
        self.assertTrue(br.verify_verbatim(STUB_TEMPLATE, out))
```

- [ ] **Step 2: Run to verify failure**

Run: `cd tools && python3 -m unittest tests.test_build_report.TestSplice -v`
Expected: FAIL — `AttributeError: ... 'splice'`.

- [ ] **Step 3: Implement splice + verbatim check**

Add to `tools/build_report.py`:

```python
GRID_OPEN = '<div class="grid">'
H_OPEN = "const H = [\n"
H_CLOSE = "\n];"
REALM_RE = re.compile(r'const REALM = "[^"]*";')


def _card_span(html):
    s = html.index(SEC)
    go = html.index(GRID_OPEN, s) + len(GRID_OPEN)
    e = html.index(SEC_END, go)
    gc = html.rindex("</div>", go, e)   # the grid's own closing </div>
    return go, gc


def _h_span(html):
    s = html.index(H_OPEN) + len(H_OPEN)
    e = html.index(H_CLOSE, s)
    return s, e


def splice(template, realm, h_body, cards):
    html = template
    cs, ce = _card_span(html)
    html = html[:cs] + "\n" + cards.strip("\n") + "\n  " + html[ce:]
    hs, he = _h_span(html)
    html = html[:hs] + h_body + html[he:]
    html = REALM_RE.sub("const REALM = %s;" % json.dumps(realm), html, count=1)
    return html


def _llm_section_end(html):
    s = html.index(SEC)
    return html.index(SEC_END, s) + len(SEC_END)


def verify_verbatim(template, output):
    """Head (up to the llm section), the region between the llm section and the
    H block (REALM value masked), and the tail (from '];' on) must all be
    byte-identical — i.e. only the cards and the H rows changed."""
    def mask(s):
        return REALM_RE.sub("const REALM = <R>;", s)

    errs = []
    if template[:template.index(SEC)] != output[:output.index(SEC)]:
        errs.append("head before the analysis section differs from template")
    mid_t = mask(template[_llm_section_end(template):template.index(H_OPEN)])
    mid_o = mask(output[_llm_section_end(output):output.index(H_OPEN)])
    if mid_t != mid_o:
        errs.append("region between analysis section and data block differs")
    if template[template.index(H_CLOSE):] != output[output.index(H_CLOSE):]:
        errs.append("engine/footer tail differs from template")
    return errs
```

- [ ] **Step 4: Run to verify pass**

Run: `cd tools && python3 -m unittest tests.test_build_report -v`
Expected: PASS (17 tests).

- [ ] **Step 5: Commit**

```bash
git add tools/build_report.py tools/tests/test_build_report.py
git commit -F - <<'MSG'
feat(tools): marker-based splice + verbatim head/tail verification

splice replaces the H body, the analysis cards, and the REALM value by string
markers; verify_verbatim proves nothing else changed (head, the mid region with
REALM masked, and the engine/footer tail are byte-identical to the template).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PaUpVRwgBPMjNmFQd9Aj4Q
MSG
```

---

### Task 5: CLI wiring + end-to-end test

**Files:**
- Modify: `tools/build_report.py`
- Modify: `tools/tests/test_build_report.py`

**Interfaces:**
- Consumes: all of the above.
- Produces: `build_report(...)` orchestrator + `main(argv)`.

- [ ] **Step 1: Add the failing end-to-end test**

Append to `tools/tests/test_build_report.py`:

```python
import os
import tempfile


class TestEndToEnd(unittest.TestCase):
    def test_main_builds_and_validates(self):
        d = tempfile.mkdtemp()
        pr = os.path.join(d, "prompt.txt")
        cards = os.path.join(d, "cards.html")
        tpl = os.path.join(d, "tpl.html")
        out = os.path.join(d, "report.html")
        with open(pr, "w", encoding="utf-8") as f:
            f.write(PROMPT)
        with open(cards, "w", encoding="utf-8") as f:
            f.write(NEW_CARDS)
        with open(tpl, "w", encoding="utf-8") as f:
            f.write(STUB_TEMPLATE)
        code = br.main(["--prompt", pr, "--cards", cards,
                        "--template", tpl, "-o", out, "--min-cards", "2"])
        self.assertEqual(code, 0)
        html = open(out, encoding="utf-8").read()
        self.assertIn('const REALM = "Frostmourne";', html)
        self.assertIn('"c":"Aria"', html)
        self.assertNotIn("SAMPLE A", html)

    def test_main_fails_on_min_cards(self):
        # STUB has the section but NEW_CARDS supplies only 2 -> below the >=10 gate
        d = tempfile.mkdtemp()
        for name, data in (("prompt.txt", PROMPT), ("cards.html", NEW_CARDS),
                           ("tpl.html", STUB_TEMPLATE)):
            with open(os.path.join(d, name), "w", encoding="utf-8") as f:
                f.write(data)
        code = br.main(["--prompt", os.path.join(d, "prompt.txt"),
                        "--cards", os.path.join(d, "cards.html"),
                        "--template", os.path.join(d, "tpl.html"),
                        "-o", os.path.join(d, "r.html"), "--min-cards", "10"])
        self.assertEqual(code, 1)
```

- [ ] **Step 2: Run to verify failure**

Run: `cd tools && python3 -m unittest tests.test_build_report.TestEndToEnd -v`
Expected: FAIL — `AttributeError: ... 'main'`.

- [ ] **Step 3: Implement the orchestrator + CLI**

Add to `tools/build_report.py` (add `import argparse`, `import sys`, `import urllib.request` to the imports):

```python
TEMPLATE_URL = ("https://raw.githubusercontent.com/tusharsaxena/LootHistory/"
                "refs/heads/master/docs/ai-export-template.html")


def load_template(path_or_none):
    if path_or_none:
        return open(path_or_none, encoding="utf-8").read()
    with urllib.request.urlopen(TEMPLATE_URL) as resp:   # full download, no cap
        return resp.read().decode("utf-8")


def build_report(prompt_text, cards, template, min_cards=10):
    """Returns (html, errors). errors empty => valid report."""
    history_csv, insights_csv = extract_blocks(prompt_text)
    realm, rows = parse_history_csv(history_csv)
    insights = parse_insights(insights_csv)
    errs = list(validate_against_insights(rows, insights))
    html = splice(template, realm, emit_h_body(rows), cards)
    n = card_count(html)
    if n < min_cards:
        errs.append("analysis cards: %d found, need >= %d" % (n, min_cards))
    errs += ["external request: " + x for x in scan_external(html)]
    errs += verify_verbatim(template, html)
    return html, errs


def main(argv=None):
    ap = argparse.ArgumentParser(description="Assemble a Ka0s Loot History AI report.")
    src = ap.add_argument_group("data source (either --prompt, or both CSVs)")
    src.add_argument("--prompt", help="the pasted addon prompt file (self-extracts both CSVs)")
    src.add_argument("--history", help="HISTORY CSV file (alternative to --prompt)")
    src.add_argument("--insights", help="INSIGHTS CSV file (alternative to --prompt)")
    ap.add_argument("--cards", required=True, help="LLM-authored analysis cards HTML")
    ap.add_argument("--template", help="local template path (default: full download)")
    ap.add_argument("-o", "--out", required=True, help="output report path")
    ap.add_argument("--min-cards", type=int, default=10)
    args = ap.parse_args(argv)

    if args.prompt:
        prompt_text = open(args.prompt, encoding="utf-8").read()
    elif args.history and args.insights:
        prompt_text = (HISTORY_MARK + "\n" + open(args.history, encoding="utf-8").read()
                       + "\n" + INSIGHTS_MARK + "\n"
                       + open(args.insights, encoding="utf-8").read())
    else:
        ap.error("provide --prompt, or both --history and --insights")

    cards = open(args.cards, encoding="utf-8").read()
    template = load_template(args.template)
    html, errs = build_report(prompt_text, cards, template, args.min_cards)

    with open(args.out, "w", encoding="utf-8") as f:
        f.write(html)

    if errs:
        print("FAIL — %d issue(s):" % len(errs))
        for e in errs:
            print("  - " + e)
        return 1
    print("PASS — wrote %s (%d bytes)" % (args.out, len(html.encode("utf-8"))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run to verify pass**

Run: `cd tools && python3 -m unittest tests.test_build_report -v`
Expected: PASS (19 tests).

- [ ] **Step 5: Make the script executable and smoke-run `--help`**

```bash
cd /mnt/d/Profile/Users/Tushar/Documents/GIT/LootHistory
chmod +x tools/build_report.py
python3 tools/build_report.py --help
```
Expected: argparse usage text; exit 0.

- [ ] **Step 6: Full-suite regression (both gates)**

```bash
cd /mnt/d/Profile/Users/Tushar/Documents/GIT/LootHistory
lua tests/run.lua | tail -1
luacheck . | tail -1
```
Expected: Lua suite `... passed, 0 failed`; luacheck `0 warnings / 0 errors` (unchanged — no Lua touched yet). Note: `luacheck .` targets Lua; it does not lint `tools/*.py`.

- [ ] **Step 7: Commit**

```bash
git add tools/build_report.py tools/tests/test_build_report.py
git commit -F - <<'MSG'
feat(tools): build_report CLI + end-to-end orchestration

main() self-extracts the CSVs from --prompt (or takes --history/--insights),
transcribes H, splices cards+H+REALM into the template (local --template or a
full download), validates everything, writes report.html, and exits non-zero
with a PASS/FAIL report. End-to-end tested.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PaUpVRwgBPMjNmFQd9Aj4Q
MSG
```

---

### Task 6: `tools/README.md` + guideline rewrite (§0, F1, F3, F4, F5)

**Files:**
- Create: `tools/README.md`
- Modify: `docs/ai-export-guideline.md`

**Interfaces:** none (docs).

- [ ] **Step 1: Write `tools/README.md`**

Create `tools/README.md`:

```markdown
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
```

- [ ] **Step 2: Rewrite the guideline's build section**

In `docs/ai-export-guideline.md`, replace the `## How to build the report` heading and its `### 1 — Fetch the template verbatim` subsection with a new lead-in that adds the file-delivery note, the run-code path, and the F3 full-download warning. Replace this block:

```markdown
## How to build the report

### 1 — Fetch the template verbatim

<https://raw.githubusercontent.com/tusharsaxena/LootHistory/refs/heads/master/docs/ai-export-template.html>

It is a **complete, working sample report**. Reproduce it **exactly** — every byte of the `<head>`,
the `<style>`, the engine `<script>`, the embedded logo / Wowhead data-URIs, and all markup and class
names — and change **only** the two things in steps 2 and 3. Do not restyle, rename classes, add
libraries, or touch the engine.
```

with:

```markdown
## Before you start — get the data onto disk, don't retype it

The export you were given (the two CSV blocks below) can be large. If you are working in a tool that
can run code, **do not reproduce the data by typing it into a heredoc or a file-write** — that wastes
minutes re-emitting data you already have. Instead, use the copy that is already on disk: an uploaded/
attached file, or the file your environment created for a large paste. If the user pasted the export
inline, ask them to attach it as a file. Then point the assembler (below) at that file.

## Fastest path — if you can run code

This repo ships a deterministic assembler that does the transcription, splice, and validation for you:

`tools/build_report.py` (<https://raw.githubusercontent.com/tusharsaxena/LootHistory/refs/heads/master/tools/build_report.py>)

1. Save the pasted export to a file (or use the attached file) — do **not** retype it.
2. Write your analysis cards (step 3 below) to `cards.html`.
3. Run: `python3 build_report.py --prompt export.txt --cards cards.html -o report.html`
   It self-extracts both CSVs, builds `H`, splices your cards, validates everything (including
   vendor value = Σ(v×qty)), and prints PASS/FAIL. Fix any reported issue and re-run.

If you **cannot** run code, follow the manual steps below.

## How to build the report (manual)

### 1 — Fetch the template verbatim

<https://raw.githubusercontent.com/tusharsaxena/LootHistory/refs/heads/master/docs/ai-export-template.html>

It is a **complete, working sample report** (~169 KB). **Download it in full** (e.g. `curl -o` /
`wget`) — a size-capped fetch silently truncates it, and you cannot reproduce a file you only partly
received. Reproduce it **exactly** — every byte of the `<head>`, the `<style>`, the engine `<script>`,
the embedded logo / Wowhead data-URIs, and all markup and class names — and change **only** the two
things in steps 2 and 3. Do not restyle, rename classes, add libraries, or touch the engine.
```

- [ ] **Step 3: Add the F1 vendor-value note**

In `docs/ai-export-guideline.md`, in the `| v | sellPriceRaw | copper (number) — the engine does **all** money math |` table row's surrounding section, append a sentence after the mapping table (after the line `You compute and lay out **nothing** here — just faithfully transcribe every row.`):

```markdown

> **Value math (F1).** Every value/gold KPI aggregates as **Σ(v × qty)**, not Σ(v) — stacked rows
> (e.g. a potion ×40) multiply. The engine does this for you; if you validate your parse against the
> INSIGHTS **Vendor value**, remember to multiply by `qty` or you will chase a phantom gap.
```

- [ ] **Step 4: Add F4 + F5 to the manual step 2 / output contract**

In `docs/ai-export-guideline.md`, immediately after the mapping table's `You compute and lay out **nothing** here` line (and before the F1 blockquote from Step 3), add:

```markdown

The sample rows in the template end each line with a trailing comma (valid JavaScript). If you emit
`H` yourself, either match that style or — better — emit a strict-JSON array (no trailing comma) so
your own `JSON.parse` validation passes cleanly (F4). When counting your analysis cards, match
`<div class="card` — grepping the bare token `card` also hits a CSS rule and over-counts (F5).
```

- [ ] **Step 5: Verify the guideline still reads coherently**

Run: `grep -n -E "Fastest path|manual|169 KB|Σ\(v × qty\)|<div class=\"card" docs/ai-export-guideline.md`
Expected: one hit each for the run-code path, the manual heading, the size note, the F1 note, and the F5 note.

- [ ] **Step 6: Commit**

```bash
git add tools/README.md docs/ai-export-guideline.md
git commit -F - <<'MSG'
docs(export): run-code path, file-delivery, and F1/F3/F4/F5 fixes in guideline

Add the tools/build_report.py fast path + tools/README; tell builders to use the
data file on disk rather than retyping it (the ~5-minute step); document the
~169KB full-download requirement (F3); state vendor value = sum(v*qty) (F1); note
the trailing-comma/JSON caveat (F4) and the correct card-count selector (F5).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PaUpVRwgBPMjNmFQd9Aj4Q
MSG
```

---

### Task 7: F2 — fix the contradictory title instruction in the addon prompt

**Files:**
- Modify: `modules/Export.lua` (`AIPrompt`, ~lines 230-231; help frame ~lines 372-383)
- Modify: `tests/test_export.lua` (~lines 128-137)

**Interfaces:**
- `E:AIPrompt` return string: the two "Title the report literally … date range from the data." lines are removed and replaced with an engine-derives-title line.

- [ ] **Step 1: Update the failing test first**

In `tests/test_export.lua`, replace line 136:

```lua
  assertTrue(p:find("Ka0s Loot History", 1, true) ~= nil, "literal title instruction")
```

with:

```lua
  assertTrue(p:find("<date range>", 1, true) == nil, "no hand-title instruction (F2)")
  assertTrue(p:find("engine derives", 1, true) ~= nil, "states the engine derives the title (F2)")
```

- [ ] **Step 2: Run to verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -A1 "AIPrompt embeds"`
Expected: FAIL — the `engine derives` assertion fails (prompt still says to hand-title).

- [ ] **Step 3: Edit `E:AIPrompt` in `modules/Export.lua`**

Replace these two lines (currently ~230-231):

```lua
    "- Title the report literally: \"Ka0s Loot History \226\128\148 <realm>, <date range>\", taking the realm",
    "  and date range from the data.",
```

with:

```lua
    "- Leave the <title> and hero heading alone: the engine derives the title, realm and date range",
    "  at runtime from the data. Do not hand-edit them.",
```

- [ ] **Step 4: Run to verify the test passes**

Run: `lua tests/run.lua 2>&1 | grep -A1 "AIPrompt embeds"`
Expected: PASS.

- [ ] **Step 5: Add the file-delivery line to the help frame**

In `modules/Export.lua`, in `EnsureHelpFrame`'s `body:SetText(table.concat({ … }, "\n"))` list, change the step-1 line:

```lua
    "1. Click |cffe8c56bExport to AI|r, then Ctrl+C to copy the whole prompt.",
```

to:

```lua
    "1. Click |cffe8c56bExport to AI|r, then Ctrl+C to copy the whole prompt.",
    "   Tip: for a big export, paste it into a text file and |cffe8c56battach that file|r to the",
    "   AI chat instead \226\128\148 it is faster and avoids truncation.",
```

- [ ] **Step 6: Full gate + count check**

```bash
cd /mnt/d/Profile/Users/Tushar/Documents/GIT/LootHistory
lua tests/run.lua | tail -1
luacheck . | tail -1
```
Expected: Lua suite still `224 passed, 0 failed` (the test was edited in place, not added/renamed, so the count is unchanged); luacheck `0 errors`.
If — and only if — the passed **count changed** or a test name changed, regenerate the inventory and bump the README badge:
```bash
lua tests/run.lua --list > docs/test-cases.md
# then edit README.md line 7 badge Tests-<n>%2F<n>_passing to the new number
```

- [ ] **Step 7: Commit**

```bash
git add modules/Export.lua tests/test_export.lua
git commit -F - <<'MSG'
fix(export): resolve F2 title conflict; recommend file-delivery in help

AIPrompt no longer tells the builder to hand-title with a date range "from the
data" — that contradicted the guideline (the engine derives the title/realm/
range at runtime). Help frame now suggests attaching the export as a file for
large exports. test_export updated to assert the new behavior.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PaUpVRwgBPMjNmFQd9Aj4Q
MSG
```

---

### Task 8: Record the `tools/` Standard exception + doc parity

**Files:**
- Modify: `docs/conventions.md`
- Modify: `docs/testing.md`
- Modify: `README.md`

**Interfaces:** none (docs).

- [ ] **Step 1: Record the exception in `docs/conventions.md`**

Append a section to `docs/conventions.md`:

```markdown
## Dev tooling — `tools/` (ratified Standard exception)

The `tools/` directory holds **development-time helper scripts** (currently
`build_report.py`, the AI-report assembler). It is a deliberate exception to the
Ka0s WoW Addon Standard's addon-layout expectations: nothing in `tools/` is
listed in the `.toc` or shipped to players — it exists only to support
maintainers and the "Export to AI" workflow. Python is used (not Lua) so the
same script runs inside an AI code sandbox. Ratified 2026-07-18.
```

- [ ] **Step 2: Add a Python-tooling section to `docs/testing.md`**

Append to `docs/testing.md`:

```markdown
## Tooling tests (Python)

`tools/` ships one dev-time helper, `build_report.py`, with its own stdlib-only
test suite (not part of the Lua green gate, not shipped in the addon):

```
cd tools && python3 -m unittest discover -s tests
```

These cover the CSV→`H` transcription, the INSIGHTS cross-check (including vendor
value = Σ(v×qty)), the splice, and the verbatim head/tail verification.
```

- [ ] **Step 3: Add a `tools/` pointer to `README.md`**

Add one line under the existing testing/badges area of `README.md` (after line 7's Tests badge block or in the contributing/testing section):

```markdown
> Maintainer tooling lives in [`tools/`](tools/) (dev-only, not shipped) — see [`tools/README.md`](tools/README.md).
```

- [ ] **Step 4: Verify no broken internal links / doc parity**

Run:
```bash
cd /mnt/d/Profile/Users/Tushar/Documents/GIT/LootHistory
grep -n "tools/" README.md docs/testing.md docs/conventions.md
ls tools/README.md tools/build_report.py
```
Expected: the pointers resolve to files that exist.

- [ ] **Step 5: Commit**

```bash
git add docs/conventions.md docs/testing.md README.md
git commit -F - <<'MSG'
docs: record tools/ Standard exception + Python tooling tests

Ratify tools/ as a dev-tooling exception (not in the .toc, not shipped) in
conventions.md; document how to run the Python tests in testing.md; point at
tools/ from the README.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PaUpVRwgBPMjNmFQd9Aj4Q
MSG
```

---

### Task 9 (optional): Conservative template shrink

**Files:**
- Modify: `docs/ai-export-template.html`
- Possibly Modify: any `docs/*.md` that cite specific template line numbers.

**Interfaces:** none. **Gate:** stop-and-report if the saving is marginal or the engine is at risk.

- [ ] **Step 1: Measure the safe-whitespace headroom**

```bash
cd /mnt/d/Profile/Users/Tushar/Documents/GIT/LootHistory
python3 - <<'PY'
d = open('docs/ai-export-template.html', encoding='utf-8').read()
import re
blank = len(re.findall(r'\n[ \t]*\n', d))
trail = len(re.findall(r'[ \t]+\n', d))
print("bytes:", len(d), "| blank-line runs:", blank, "| trailing-ws lines:", trail)
PY
```
Decision rule: if stripping trailing whitespace + collapsing blank-line runs saves **< ~5 KB**, or any of it sits inside the `<script>` engine or a `data:` URI, **stop** — do only Step 4 (record the decision) and skip the edit. The F3 full-download note is the real fix; the shrink is a nice-to-have.

- [ ] **Step 2: If worthwhile, strip only trailing whitespace outside script/data-URIs**

Only strip trailing whitespace on lines that are **not** inside the `<script>…</script>` engine and do not contain `data:`. Do not touch blank lines inside the engine (JS can be whitespace-sensitive in template strings). Apply with a reviewed one-off script, then immediately re-verify (Step 3).

- [ ] **Step 3: Verify the report still renders and self-checks pass**

Build a report from the shipped template and confirm it validates:
```bash
cd /mnt/d/Profile/Users/Tushar/Documents/GIT/LootHistory
# Use the tool against the template itself with a tiny synthetic prompt+cards
python3 - <<'PY'
import sys; sys.path.insert(0, 'tools')
import build_report as br
tpl = open('docs/ai-export-template.html', encoding='utf-8').read()
# sanity: markers still present and unique
for m in ('<section id="llm">', '<div class="grid">', 'const H = [\n', '\n];', 'const REALM = "'):
    assert tpl.count(m) >= 1, m
print("markers OK; bytes:", len(tpl))
PY
```
Expected: `markers OK`. Also open the file in a browser (smoke test) and confirm KPIs/charts render.

- [ ] **Step 4: Update any line-number citations + commit**

If any `docs/*.md` cite template line numbers that moved, update them. Then:
```bash
git add docs/ai-export-template.html docs/*.md
git commit -F - <<'MSG'
chore(export): conservative whitespace shrink of the AI template

Strip trailing whitespace outside the engine script and data-URIs; engine,
markup, and byte-diff self-checks unaffected. (Or: recorded that the saving was
marginal and left the template unchanged.)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PaUpVRwgBPMjNmFQd9Aj4Q
MSG
```

---

## Final verification (after all tasks)

- [ ] `cd tools && python3 -m unittest discover -s tests` → all pass.
- [ ] `lua tests/run.lua` → `... passed, 0 failed` (count matches README badge).
- [ ] `luacheck .` → 0 errors.
- [ ] `python3 tools/build_report.py --help` → exits 0.
- [ ] Guideline reads coherently: run-code path first, manual path second, F1/F3/F4/F5 all present.
- [ ] `docs/ai-export-guideline.md` and `modules/Export.lua` agree on the title (engine-derived; no hand-edit).

## Self-review notes (author)

- **Spec coverage:** §0 re-emission → Task 6 (guideline) + Task 7 (help frame); assembler §1 → Tasks 1-5; tests §2 → Tasks 1-5; guideline F1/F3/F4/F5 §3 → Task 6; F2 §3 → Task 7; template shrink §4 → Task 9; standards record §5 → Task 8. All covered.
- **Naming:** the spec's prose `build-report.py` is realized as `build_report.py` (underscore) for importability — noted in Global Constraints; every task uses the underscore form.
- **Type/interface consistency:** `HKEYS`, `parse_history_csv`, `emit_h_body`, `extract_blocks`, `parse_insights`, `parse_money`, `validate_against_insights`, `card_count`, `scan_external`, `splice`, `verify_verbatim`, `build_report`, `main` — used consistently across Tasks 1-5.
