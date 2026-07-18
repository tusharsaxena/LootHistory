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


REAL_TEMPLATE = os.path.join(os.path.dirname(__file__), "..", "..",
                             "docs", "ai-export-template.html")


class TestRealTemplate(unittest.TestCase):
    def _cards(self):
        return "\n".join('<div class="card sp4">c%d</div>' % i for i in range(10))

    def _splice_real(self):
        with open(REAL_TEMPLATE, encoding="utf-8") as f:
            tpl = f.read()
        _, rows = br.parse_history_csv(HISTORY)
        return tpl, br.splice(tpl, "Frostmourne", br.emit_h_body(rows), self._cards())

    def test_llm_section_divs_stay_balanced(self):
        _, out = self._splice_real()
        sec = out[out.index(br.SEC):out.index(br.SEC_END, out.index(br.SEC))]
        self.assertEqual(sec.count("<div"), sec.count("</div>"),
                         "llm section <div>/</div> must stay balanced after splice")

    def test_card_count_and_verbatim_hold_on_real_template(self):
        tpl, out = self._splice_real()
        self.assertEqual(br.card_count(out), 10)
        self.assertEqual(br.verify_verbatim(tpl, out), [])


if __name__ == "__main__":
    unittest.main()
