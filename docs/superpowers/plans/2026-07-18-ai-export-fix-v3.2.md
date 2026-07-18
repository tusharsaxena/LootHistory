# AI Export fix v3.2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the residual wasted-effort and doubt a *healthy* AI-export run still shows — ship a sample-name leak scan and an itemized PASS in the assembler, neutralize a stale template title, annotate the sample blocks, add three guideline lines, and make the in-game prompt self-recover from a stale guideline copy.

**Architecture:** Four surfaces, each independently testable. The assembler (`tools/build_report.py`) gains two pure helpers + an info-returning `build_report`; the template loses a stale static title and gains two "replace-wholesale" comments; the guideline gains three prose lines; the in-game `AIPrompt` gains a stale-cache self-check. No pipeline scripts are added — the tool already has them.

**Tech Stack:** Python 3.8+ stdlib (assembler + `unittest`), Lua 5.1 headless harness (`tests/run.lua`), Markdown/HTML docs.

## Global Constraints

- **Stdlib only** in `tools/build_report.py` — no third-party imports (runs in any code sandbox).
- **Do not change** the existing final `PASS — wrote %s (%d bytes)` line or the `FAIL — %d issue(s):` block — additive output only.
- **`verify_verbatim` must still pass** on the real template after every template edit (head/mid/tail byte-identical).
- **Tool stdout stays ASCII-safe** for the new checklist (use `|`, `>=`, `sum(v*qty)`) — the header keeps the existing em-dash style. Avoid `·`/`Σ`/`×`/`≥` to dodge Windows cp1252 encode errors.
- **Never bump the version**; no engine/style/data-path change.
- **Lua case count must not move** — Task 5 edits assertions inside an existing `test(...)` block. Only regenerate `docs/test-cases.md` + README `tests` badge if the count actually changes.
- Run before considering done: `python3 -m unittest discover -s tools/tests` · `lua tests/run.lua` · `luacheck .` — all green.
- Commit trailers on every commit:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01PaUpVRwgBPMjNmFQd9Aj4Q
  ```

---

### Task 1: Sample-name leak scan (spec §A1)

**Files:**
- Modify: `tools/build_report.py` — add `SAMPLE_C_RE`, `sample_names()`, `scan_sample_leak()`; wire into `build_report()`
- Test: `tools/tests/test_build_report.py` — add `TestSampleLeak`

**Interfaces:**
- Consumes: `H_OPEN`, `H_CLOSE` (module globals, already defined), `card` files passed to `build_report`.
- Produces: `sample_names(template) -> list[str]` (sorted, distinct); `scan_sample_leak(cards, names) -> list[str]` (leaked names, empty == clean). `build_report` return arity is UNCHANGED in this task (still `(html, errs)`).

- [ ] **Step 1: Write the failing tests**

Add to `tools/tests/test_build_report.py` (after the `TestCardEscapesEndToEnd` class, before `if __name__`):

```python
class TestSampleLeak(unittest.TestCase):
    def test_sample_names_extracted_from_template_h(self):
        tpl = STUB_TEMPLATE.replace('{"old":1}',
                                    '{"c":"Stormhoof"},\n{"c":"Ragebrand"}')
        self.assertEqual(br.sample_names(tpl), ["Ragebrand", "Stormhoof"])

    def test_sample_names_empty_when_no_c_key(self):
        # STUB's sample H has no "c" key -> nothing to leak-scan against.
        self.assertEqual(br.sample_names(STUB_TEMPLATE), [])

    def test_scan_sample_leak_flags_leaked_name(self):
        cards = '<div class="card sp6"><p>Ragebrand looted a lot.</p></div>'
        self.assertEqual(br.scan_sample_leak(cards, ["Stormhoof", "Ragebrand"]),
                         ["Ragebrand"])

    def test_scan_sample_leak_clean_for_real_names(self):
        cards = '<div class="card sp6"><p>Aellâ and Chopstîx.</p></div>'
        self.assertEqual(br.scan_sample_leak(cards, ["Stormhoof", "Ragebrand"]), [])

    def test_real_template_sample_names_include_known_pseudonyms(self):
        with open(REAL_TEMPLATE, encoding="utf-8") as f:
            names = br.sample_names(f.read())
        self.assertIn("Stormhoof", names)
        self.assertIn("Ragebrand", names)

    def test_main_fails_when_card_leaks_a_sample_name(self):
        d = tempfile.mkdtemp()
        tpl = STUB_TEMPLATE.replace('{"old":1}', '{"c":"Stormhoof"}')
        bad = NEW_CARDS.replace("NEW ONE", "Stormhoof NEW ONE")
        for name, data in (("prompt.txt", PROMPT), ("cards.html", bad),
                           ("tpl.html", tpl)):
            with open(os.path.join(d, name), "w", encoding="utf-8") as f:
                f.write(data)
        code = br.main(["--prompt", os.path.join(d, "prompt.txt"),
                        "--cards", os.path.join(d, "cards.html"),
                        "--template", os.path.join(d, "tpl.html"),
                        "-o", os.path.join(d, "r.html"), "--min-cards", "2"])
        self.assertEqual(code, 1)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd tools && python3 -m unittest tests.test_build_report.TestSampleLeak -v`
Expected: FAIL with `AttributeError: module 'build_report' has no attribute 'sample_names'`.

- [ ] **Step 3: Add the helpers and wire them in**

In `tools/build_report.py`, immediately after the `REALM_RE = re.compile(...)` line (just before `def _card_span`), add:

```python
SAMPLE_C_RE = re.compile(r'"c":"([^"]+)"')


def sample_names(template):
    """Distinct sample character names inside the template's OWN sample H block
    (F6). Data-driven so it stays correct if the shipped sample is ever swapped —
    used to catch a stale-sample name leaking into hand-authored cards."""
    s = template.index(H_OPEN) + len(H_OPEN)
    e = template.index(H_CLOSE, s)
    return sorted(set(SAMPLE_C_RE.findall(template[s:e])))


def scan_sample_leak(cards, names):
    """Sample character names that leaked into the analysis cards — a sign the
    cards were edited from the samples instead of replaced wholesale. Scoped to
    the cards (the one hand-authored region); the real H legitimately holds real
    names. Returns the offending names (empty == clean)."""
    return [n for n in names if n in cards]
```

Then in `build_report()`, insert the leak check between the escape scan and the verbatim check:

```python
    errs += ["literal escape in cards (use the real glyph, not %s): %s" % (x, x)
             for x in scan_card_escapes(cards)]
    errs += ["sample-data leak (cards edited from the template sample, not "
             "replaced wholesale): " + x
             for x in scan_sample_leak(cards, sample_names(template))]
    errs += verify_verbatim(template, html)
    return html, errs
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd tools && python3 -m unittest tests.test_build_report -v`
Expected: PASS (the new `TestSampleLeak` and all pre-existing tests).

- [ ] **Step 5: Commit**

```bash
git add tools/build_report.py tools/tests/test_build_report.py
git commit -m "feat(tools): sample-name leak scan in the assembler (F6)

<trailers>"
```

---

### Task 2: Itemized PASS output (spec §A2)

**Files:**
- Modify: `tools/build_report.py` — add `computed_figures()`, `_print_pass_summary()`; `build_report()` returns `(html, errs, info)`; `main()` prints the checklist on success
- Test: `tools/tests/test_build_report.py` — add `TestPassSummary`; add `io`/`contextlib` imports

**Interfaces:**
- Consumes: `rows` (from `parse_history_csv`), `_fmt_money` (existing), the `info` dict.
- Produces: `computed_figures(rows) -> dict` with keys `records, distinct, characters, epic_plus, best_ilvl, richest, busiest_day, busiest_n, vendor`. `build_report(...) -> (html, errs, info)`; `info` keys: `figures, cards, min_cards, external, escapes, leak`. (No test calls `build_report` directly, so the arity change is safe; `main` is the only caller and is updated here.)

- [ ] **Step 1: Write the failing test**

Add near the top of `tools/tests/test_build_report.py`, with the other imports:

```python
import io
import contextlib
```

Add this class (after `TestSampleLeak`, before `if __name__`):

```python
class TestPassSummary(unittest.TestCase):
    def test_computed_figures(self):
        _, rows = br.parse_history_csv(HISTORY)
        f = br.computed_figures(rows)
        self.assertEqual(f["records"], 3)
        self.assertEqual(f["distinct"], 2)
        self.assertEqual(f["characters"], 2)
        self.assertEqual(f["epic_plus"], 1)
        self.assertEqual(f["best_ilvl"], 246)
        self.assertEqual(f["vendor"], 100000 * 1 + 100 * 5 + 100 * 3)

    def test_build_report_returns_info(self):
        tpl = STUB_TEMPLATE
        _, rows = br.parse_history_csv(HISTORY)
        html, errs, info = br.build_report(PROMPT, NEW_CARDS, tpl, min_cards=2)
        self.assertEqual(errs, [])
        self.assertEqual(info["cards"], 2)
        self.assertEqual(info["leak"], [])
        self.assertEqual(info["figures"]["records"], 3)

    def test_main_prints_itemized_checklist_on_pass(self):
        d = tempfile.mkdtemp()
        for name, data in (("prompt.txt", PROMPT), ("cards.html", NEW_CARDS),
                           ("tpl.html", STUB_TEMPLATE)):
            with open(os.path.join(d, name), "w", encoding="utf-8") as f:
                f.write(data)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            code = br.main(["--prompt", os.path.join(d, "prompt.txt"),
                            "--cards", os.path.join(d, "cards.html"),
                            "--template", os.path.join(d, "tpl.html"),
                            "-o", os.path.join(d, "r.html"), "--min-cards", "2"])
        s = buf.getvalue()
        self.assertEqual(code, 0)
        self.assertIn("checks green", s)
        self.assertIn("Records 3", s)
        self.assertIn("Vendor", s)
        self.assertIn("sample-leak none", s)
        self.assertIn("PASS — wrote", s)   # original line intact
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools && python3 -m unittest tests.test_build_report.TestPassSummary -v`
Expected: FAIL — `computed_figures` missing / `build_report` returns 2 values not 3.

- [ ] **Step 3: Implement**

In `tools/build_report.py`, add `computed_figures` just before `def build_report`:

```python
def computed_figures(rows):
    """The reconciliation figures the tool checks, for the PASS summary."""
    ils = [o["il"] for o in rows if o["il"] is not None]
    counts = {}
    for o in rows:
        counts[o["d"]] = counts.get(o["d"], 0) + 1
    busiest_day, busiest_n = "", 0
    if counts:
        busiest_day = max(counts, key=counts.get)
        busiest_n = counts[busiest_day]
    return {
        "records": len(rows),
        "distinct": len({o["id"] for o in rows}),
        "characters": len({o["c"] for o in rows}),
        "epic_plus": sum(1 for o in rows if o["qr"] >= 4),
        "best_ilvl": max(ils) if ils else None,
        "richest": max((o["v"] for o in rows), default=0),
        "busiest_day": busiest_day,
        "busiest_n": busiest_n,
        "vendor": sum(o["v"] * o["qty"] for o in rows),
    }
```

Replace the body of `build_report` from the `n = card_count(html)` line through `return` with:

```python
    n = card_count(html)
    if n < min_cards:
        errs.append("analysis cards: %d found, need >= %d" % (n, min_cards))
    ext = scan_external(html)
    errs += ["external request: " + x for x in ext]
    esc = scan_card_escapes(cards)
    errs += ["literal escape in cards (use the real glyph, not %s): %s" % (x, x)
             for x in esc]
    leak = scan_sample_leak(cards, sample_names(template))
    errs += ["sample-data leak (cards edited from the template sample, not "
             "replaced wholesale): " + x for x in leak]
    errs += verify_verbatim(template, html)
    info = {
        "figures": computed_figures(rows),
        "cards": n, "min_cards": min_cards,
        "external": ext, "escapes": esc, "leak": leak,
    }
    return html, errs, info
```

Add `_print_pass_summary` just before `def main`:

```python
def _print_pass_summary(info):
    f = info["figures"]
    best = f["best_ilvl"] if f["best_ilvl"] is not None else "n/a"
    print("PASS — checks green:")
    print("  vs INSIGHTS: Records %d | Distinct %d | Chars %d | Epic+ %d | "
          "Best iLvl %s | Richest %s | Busiest %s(%d) | Vendor sum(v*qty) %s"
          % (f["records"], f["distinct"], f["characters"], f["epic_plus"],
             best, _fmt_money(f["richest"]), f["busiest_day"], f["busiest_n"],
             _fmt_money(f["vendor"])))
    none = lambda xs: "none" if not xs else ",".join(xs)
    print("  cards %d (min %d) | external %s | escapes %s | sample-leak %s | "
          "head/engine/footer byte-identical"
          % (info["cards"], info["min_cards"], none(info["external"]),
             none(info["escapes"]), none(info["leak"])))
```

In `main`, update the call site and success branch:

```python
    html, errs, info = build_report(prompt_text, cards, template, args.min_cards)

    with open(args.out, "w", encoding="utf-8") as f:
        f.write(html)

    if errs:
        print("FAIL — %d issue(s):" % len(errs))
        for e in errs:
            print("  - " + e)
        return 1
    _print_pass_summary(info)
    print("PASS — wrote %s (%d bytes)" % (args.out, len(html.encode("utf-8"))))
    return 0
```

- [ ] **Step 4: Run the full tool suite**

Run: `cd tools && python3 -m unittest discover -s tests -v`
Expected: PASS — all classes green, including `TestPassSummary`, `TestEndToEnd`, `TestCardEscapesEndToEnd` (they call `main`, whose success path now prints the checklist but still returns 0).

- [ ] **Step 5: Commit**

```bash
git add tools/build_report.py tools/tests/test_build_report.py
git commit -m "feat(tools): itemized PASS checklist so agents stop re-verifying

<trailers>"
```

---

### Task 3: Neutralize stale title + annotate sample blocks (spec §B1, §B2)

**Files:**
- Modify: `docs/ai-export-template.html` — line 6 `<title>`; two HTML comments
- Test: `tools/tests/test_build_report.py` — add two assertions to `TestRealTemplate`

**Interfaces:**
- Consumes: nothing new. Produces: nothing new — this task only changes shipped template bytes and proves the change + that `verify_verbatim` still holds.

- [ ] **Step 1: Write the failing test**

Add to the `TestRealTemplate` class in `tools/tests/test_build_report.py`:

```python
    def test_static_title_is_neutral_placeholder(self):
        with open(REAL_TEMPLATE, encoding="utf-8") as f:
            tpl = f.read()
        self.assertIn("<title>Ka0s Loot History</title>", tpl)
        self.assertNotIn("12–17 Jul", tpl)

    def test_sample_blocks_carry_replace_wholesale_note(self):
        with open(REAL_TEMPLATE, encoding="utf-8") as f:
            tpl = f.read()
        self.assertIn("REPLACES", tpl)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools && python3 -m unittest tests.test_build_report.TestRealTemplate -v`
Expected: FAIL — the title still carries `— Frostmourne, 12–17 Jul 2026`; no `REPLACES` comment yet.

- [ ] **Step 3: Edit the template**

In `docs/ai-export-template.html`:

1. **Title (line 6)** — replace:
   `<title>Ka0s Loot History — Frostmourne, 12–17 Jul 2026</title>`
   with:
   `<title>Ka0s Loot History</title>`

2. **Sample-cards comment** — immediately before the `<section id="llm">` opening tag, add on its own line:
   `<!-- SAMPLE analysis cards: the assembler REPLACES this <section> wholesale. Never hand-edit — edited samples ship stale numbers. -->`

3. **Sample-data comment** — immediately before the `const H = [` line, add on its own line:
   `<!-- SAMPLE data: the assembler REPLACES REALM + the H array wholesale. Never hand-edit. -->`

(Both comments sit outside the byte-replaced card span and the `H` span, in regions `verify_verbatim` compares template-to-output identically — so they persist in output and the head/mid checks still pass.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd tools && python3 -m unittest tests.test_build_report -v`
Expected: PASS — `TestRealTemplate` (new title/annotation assertions **and** the existing `test_card_count_and_verbatim_hold_on_real_template` / `test_llm_section_divs_stay_balanced`) all green.

- [ ] **Step 5: Commit**

```bash
git add docs/ai-export-template.html tools/tests/test_build_report.py
git commit -m "fix(export): neutralize stale static title; mark samples replace-wholesale (F3/F6)

<trailers>"
```

---

### Task 4: Guideline lines (spec §C1, §C2, §C3)

**Files:**
- Modify: `docs/ai-export-guideline.md`

**Interfaces:** none — prose only.

- [ ] **Step 1: Add the version stamp (C3)**

In `docs/ai-export-guideline.md`, immediately after the H1 title line (`# Ka0s Loot History — AI Report Guideline`), insert a blank line then:

```markdown
*Guideline v3.2 · 2026-07-18*
```

- [ ] **Step 2: Add the trust-the-PASS line (C1)**

At the end of the numbered assembler recipe — right after the line `Then output the report per the **Output contract** below.` — add a new paragraph:

```markdown
The tool's **PASS** already reconciles every Summary figure (records, distinct items, characters,
epic+, best iLvl, richest drop, busiest day, vendor value = Σ(v×qty)), counts your cards, and scans for
external requests, literal escapes, and template sample-name leaks — and it prints an itemized checklist
of each. You do **not** need to re-run those checks by hand; trust the checklist and cite it.
```

- [ ] **Step 3: Add the title-placeholder line (C2)**

In the **Output contract** section, extend the `<title>`/hero bullet so it ends with:

```markdown
  The static `<title>` shipped in the template is only a placeholder — the engine overwrites the title,
  realm, and date range at load from the data. Never hand-edit it, even if the placeholder's date range
  looks wrong.
```

- [ ] **Step 4: Verify the doc renders and self-check the wording**

Run: `grep -n "v3.2\|itemized checklist\|placeholder" docs/ai-export-guideline.md`
Expected: three matches, one per added line. Re-read them in context for flow.

- [ ] **Step 5: Commit**

```bash
git add docs/ai-export-guideline.md
git commit -m "docs(export): trust-the-PASS + title-placeholder + v3.2 stamp in the guideline

<trailers>"
```

---

### Task 5: In-game prompt stale-cache self-check (spec §D1)

**Files:**
- Modify: `modules/Export.lua` — `AIPrompt` (the "If you can run code" paragraph, lines ~227–231)
- Test: `tests/test_export.lua` — extend the existing `Export: AIPrompt embeds …` case

**Interfaces:**
- Consumes: nothing new. Produces: the prompt string now contains the tokens `stale` and `web_fetch`. This is an assertion edit inside an existing `test(...)` — **the Lua case count does not change.**

- [ ] **Step 1: Write the failing assertions**

In `tests/test_export.lua`, inside the `test("Export: AIPrompt embeds guideline URL, both CSV blocks, and framing", …)` block, before its closing `end)`, add:

```lua
  assertTrue(p:find("stale", 1, true) ~= nil,
    "warns that a guideline copy without the tool is a stale cache")
  assertTrue(p:find("web_fetch", 1, true) ~= nil,
    "forbids web_fetch of the template in the prompt itself")
```

- [ ] **Step 2: Run to verify it fails**

Run: `lua tests/run.lua 2>&1 | grep -i "export: aiprompt embeds"`
Expected: that case FAILS (no `stale` / `web_fetch` token in the prompt yet).

- [ ] **Step 3: Edit `AIPrompt`**

In `modules/Export.lua`, replace the current "If you can run code" paragraph lines:

```lua
    "If you can run code (Claude Code, Claude Desktop with code, ChatGPT code interpreter): the guideline",
    "has you build with the shipped assembler tools/build_report.py — run that in ONE command; do not",
    "hand-transcribe the data or write your own build/splice scripts. Hand this export to the AI as a FILE",
    "(attach/upload it, or paste in Claude Code which auto-files a large paste) and point the tool at it —",
    "do not retype the data.",
```

with:

```lua
    "If you can run code (Claude Code, Claude Desktop with code, ChatGPT code interpreter): the guideline",
    "has you build with the shipped assembler tools/build_report.py — run that in ONE command; do not",
    "hand-transcribe the data or write your own build/splice scripts. Hand this export to the AI as a FILE",
    "(attach/upload it, or paste in Claude Code which auto-files a large paste) and point the tool at it —",
    "do not retype the data. The guideline you fetch describes that assembler; if the copy you receive",
    "does not mention build_report.py you fetched a stale CDN cache — re-fetch it once, and either way",
    "THIS prompt is authoritative: the assembler builds, validates, AND downloads the template itself in",
    "one command, so never web_fetch the template.",
```

- [ ] **Step 4: Run the Lua suite**

Run: `lua tests/run.lua`
Expected: all green, including the extended `Export: AIPrompt embeds …` case.

- [ ] **Step 5: Confirm the case count is unchanged**

Run: `lua tests/run.lua --list | wc -l`
Compare against the count on `master` (`git stash` not needed — just note the number in the plan run). Expected: **unchanged** (assertion edit, not a new case). If — and only if — it moved, regenerate `docs/test-cases.md` (`lua tests/run.lua --list > docs/test-cases.md`) and update the README `tests` badge count in this same commit.

- [ ] **Step 6: Commit**

```bash
git add modules/Export.lua tests/test_export.lua
git commit -m "feat(export): stale-cache self-check + template-fetch ban in the AI prompt (F1/F4)

<trailers>"
```

---

### Task 6: Full verification + end-to-end rebuild (spec Success criteria)

**Files:**
- Create (scratch, not committed): a `cards.html` with ≥10 cards + the pasted v3.2 export saved to `export.txt`, under the scratchpad dir
- Modify: only `docs/test-cases.md` + `README.md` badge **if** the Lua count moved in Task 5 (expected: no)

**Interfaces:** none — this is the integration gate.

- [ ] **Step 1: Run all three suites**

Run:
```bash
cd tools && python3 -m unittest discover -s tests && cd ..
lua tests/run.lua
luacheck .
```
Expected: tool suite OK, Lua suite all-pass, luacheck `0 warnings / 0 errors`.

- [ ] **Step 2: End-to-end rebuild from the real v3.2 export**

Save the pasted export (the `=== HISTORY (CSV) ===` + `=== INSIGHTS (CSV) ===` blocks from the task) to `<scratchpad>/export.txt`, write a `<scratchpad>/cards.html` with **at least 10** `<div class="card …">` blocks using real glyphs (no `\u` escapes) and no template sample names, then run against the local template:

```bash
python3 tools/build_report.py \
  --prompt <scratchpad>/export.txt \
  --cards  <scratchpad>/cards.html \
  --template docs/ai-export-template.html \
  -o <scratchpad>/report.html
```

Expected stdout:
```
PASS — checks green:
  vs INSIGHTS: Records 305 | Distinct 111 | Chars 7 | Epic+ 87 | Best iLvl 272 | Richest 80g 63s 1c | Busiest 13-Jul-2026(91) | Vendor sum(v*qty) 2354g 87s 37c
  cards N (min 10) | external none | escapes none | sample-leak none | head/engine/footer byte-identical
PASS — wrote <scratchpad>/report.html (…)
```

- [ ] **Step 3: Spot-check the emitted report**

Run:
```bash
grep -c '<title>Ka0s Loot History</title>' <scratchpad>/report.html   # 1 — neutral title
grep -Eic 'Stormhoof|Ragebrand|Grimfrost|Mistpaw' <scratchpad>/report.html  # 0 — no leak
```
Expected: `1` then `0`.

- [ ] **Step 4: Docs sync gate (conditional)**

If the Task 5 Lua case count moved (it should not have), regenerate and stage `docs/test-cases.md` + the README `tests` badge. Otherwise skip — no docs change.

- [ ] **Step 5: Final commit (only if Step 4 produced changes)**

```bash
git add docs/test-cases.md README.md
git commit -m "docs(tests): regenerate inventory + badge after v3.2 export changes

<trailers>"
```

If Step 4 was a no-op, there is nothing to commit here — the branch is complete.

---

## Self-Review

**Spec coverage:** §A1 → Task 1; §A2 → Task 2; §B1/§B2 → Task 3; §C1/§C2/§C3 → Task 4; §D1 → Task 5; Success criteria (three suites + end-to-end rebuild + docs-sync-if-moved) → Task 6. All sections mapped.

**Placeholder scan:** No TBD/TODO; every code step shows full code; the only conditional ("regenerate if the count moved") is a genuine branch with the exact command given, not a vague instruction.

**Type consistency:** `sample_names`/`scan_sample_leak` (Task 1) are consumed by `build_report` in Task 2 with matching signatures; `computed_figures` keys used in `_print_pass_summary` match the dict defined in Task 2; `build_report` 3-tuple `(html, errs, info)` is produced and consumed only in Task 2's `main`. The AIPrompt tokens asserted in Task 5 (`stale`, `web_fetch`) match the inserted prose.
