#!/usr/bin/env python3
"""Ka0s Loot History — deterministic AI-report assembler + validator.

Turns the pasted "Export to AI" prompt (HISTORY + INSIGHTS CSV blocks) plus an
LLM-authored analysis-cards file into a validated, self-contained report.html by
filling the fixed template. Stdlib only — runs unmodified in any code sandbox.
"""
import csv
import io
import json
import re

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
