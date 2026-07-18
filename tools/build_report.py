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
