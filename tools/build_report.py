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
