#!/usr/bin/env python3
"""Ka0s Loot History — deterministic AI-report assembler + validator.

Turns the pasted "Export to AI" prompt (HISTORY + INSIGHTS CSV blocks) plus an
LLM-authored analysis-cards file into a validated, self-contained report.html by
filling the fixed template. Stdlib only — runs unmodified in any code sandbox.
"""
import argparse
import csv
import io
import json
import re
import sys
import urllib.request

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


CARD_ESCAPE_RE = re.compile(r"\\u[0-9a-fA-F]{4}|\\x[0-9a-fA-F]{2}")


def scan_card_escapes(cards):
    """Literal \\uXXXX / \\xNN escape sequences in the cards file (F7): a sign
    the cards were embedded as a raw/escaped string, so a glyph like the ◆ tag
    was written as its 6-char escape instead of the real character. Returns the
    offending tokens (empty list => clean)."""
    return CARD_ESCAPE_RE.findall(cards)


GRID_OPEN = '<div class="grid">'
H_OPEN = "const H = [\n"
H_CLOSE = "\n];"
REALM_RE = re.compile(r'const REALM = "[^"]*";')

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


def _card_span(html):
    """(start, end) of the sample-card region: from just after the grid's
    opening tag to the grid's OWN matching </div>. Scans <div> nesting forward
    so a grid wrapped in other <div>s (as in the real template) is handled — a
    plain rindex would wrongly pick an enclosing wrapper's close."""
    s = html.index(SEC)
    go = html.index(GRID_OPEN, s) + len(GRID_OPEN)
    depth, i = 1, go
    while depth > 0:
        nxt_open = html.find("<div", i)
        nxt_close = html.find("</div>", i)
        if nxt_close == -1:
            raise ValueError("unbalanced <div> after grid open")
        if nxt_open != -1 and nxt_open < nxt_close:
            depth += 1
            i = nxt_open + 4
        else:
            depth -= 1
            i = nxt_close + 6
    return go, i - 6


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
    errs += ["literal escape in cards (use the real glyph, not %s): %s" % (x, x)
             for x in scan_card_escapes(cards)]
    errs += ["sample-data leak (cards edited from the template sample, not "
             "replaced wholesale): " + x
             for x in scan_sample_leak(cards, sample_names(template))]
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
