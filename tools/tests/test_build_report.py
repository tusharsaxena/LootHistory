import contextlib
import io
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
            "b": "Bind on Pickup", "v": 100000, "a": None, "val": 100000,
            "ty": "Weapon", "st": "Sword",
            "qty": 1, "s": "KILL", "z": "Town", "wh": "https://wh/111",
            "src": "",
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
    "Summary,Value,,10g 8s 0c\r\n"
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
        self.assertIn("Summary,Value", ins)

    def test_extract_blocks_history_only(self):
        # v4: INSIGHTS is optional. A HISTORY-only prompt yields insights "".
        hist, ins = br.extract_blocks("intro\n" + br.HISTORY_MARK + "\n" + HISTORY)
        self.assertTrue(hist.startswith("ts,date,time"))
        self.assertEqual(ins, "")

    def test_extract_blocks_missing_history_raises(self):
        with self.assertRaises(ValueError):
            br.extract_blocks("no markers here at all")

    def test_parse_money(self):
        self.assertEqual(br.parse_money("10g 8s 0c"), 100800)
        self.assertEqual(br.parse_money("0g 0s 7c"), 7)

    def test_parse_insights_lookup(self):
        ins = br.parse_insights(INSIGHTS)
        self.assertEqual(ins[("Summary", "Records")]["count"], "3")
        self.assertEqual(ins[("Summary", "Value")]["value"], "10g 8s 0c")


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

    def test_insights_crosscheck_detects_value_mismatch(self):
        bad = dict(self.ins)
        bad[("Summary", "Value")] = {"count": "", "value": "99g 0s 0c"}
        errs = br.validate_against_insights(self.rows, bad)
        self.assertTrue(any("Value" in e for e in errs))

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

    def test_sample_cards_use_span_il_not_anchor_links(self):
        # The guideline tells the AI to render card item names exactly like the
        # samples: a quality-colored .il SPAN carrying data-tt, never an <a href>
        # wowhead link (the engine's table uses <a class="il"> — cards do not).
        # Guards the guideline<->template contract and keeps cards link-free.
        with open(REAL_TEMPLATE, encoding="utf-8") as f:
            tpl = f.read()
        sec = tpl[tpl.index(br.SEC):tpl.index(br.SEC_END, tpl.index(br.SEC))]
        self.assertIn('<span class="il ', sec)
        self.assertNotIn('<a class="il', sec)
        self.assertNotIn('href="http', sec)

    def test_static_title_is_neutral_placeholder(self):
        with open(REAL_TEMPLATE, encoding="utf-8") as f:
            tpl = f.read()
        self.assertIn("<title>Ka0s Loot History</title>", tpl)
        self.assertNotIn("12–17 Jul", tpl)

    def test_sample_blocks_carry_replace_wholesale_note(self):
        with open(REAL_TEMPLATE, encoding="utf-8") as f:
            tpl = f.read()
        self.assertIn("REPLACES", tpl)


class TestCardEscapes(unittest.TestCase):
    def test_real_glyphs_and_accents_pass_clean(self):
        cards = ('<div class="card sp6"><div class="llm-tag">◆ The week</div>'
                 '<p>Aellâ ran with Chopstîx — nice.</p></div>')
        self.assertEqual(br.scan_card_escapes(cards), [])

    def test_literal_unicode_escape_is_flagged(self):
        # F7: cards embedded as a raw string leave "◆" as 6 literal chars.
        cards = '<div class="card sp6"><div class="llm-tag">\\u25c6 The week</div></div>'
        found = br.scan_card_escapes(cards)
        self.assertIn("\\u25c6", found)

    def test_literal_hex_escape_is_flagged(self):
        cards = '<div class="card sp6"><p>Aell\\xe2 the warrior</p></div>'
        self.assertTrue(br.scan_card_escapes(cards))


class TestCardEscapesEndToEnd(unittest.TestCase):
    def _run(self, cards_text):
        d = tempfile.mkdtemp()
        for name, data in (("prompt.txt", PROMPT), ("cards.html", cards_text),
                           ("tpl.html", STUB_TEMPLATE)):
            with open(os.path.join(d, name), "w", encoding="utf-8") as f:
                f.write(data)
        return br.main(["--prompt", os.path.join(d, "prompt.txt"),
                        "--cards", os.path.join(d, "cards.html"),
                        "--template", os.path.join(d, "tpl.html"),
                        "-o", os.path.join(d, "r.html"), "--min-cards", "2"])

    def test_main_fails_on_literal_escape_in_cards(self):
        bad = NEW_CARDS.replace("NEW ONE", "\\u25c6 NEW ONE")
        self.assertEqual(self._run(bad), 1)

    def test_main_passes_on_real_glyph_in_cards(self):
        good = NEW_CARDS.replace("NEW ONE", "◆ NEW ONE")
        self.assertEqual(self._run(good), 0)


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


class TestPassSummary(unittest.TestCase):
    def test_computed_figures(self):
        _, rows = br.parse_history_csv(HISTORY)
        f = br.computed_figures(rows)
        self.assertEqual(f["records"], 3)
        self.assertEqual(f["distinct"], 2)
        self.assertEqual(f["characters"], 2)
        self.assertEqual(f["epic_plus"], 1)
        self.assertEqual(f["best_ilvl"], 246)
        self.assertEqual(f["value"], 100000 * 1 + 100 * 5 + 100 * 3)

    def test_build_report_returns_info(self):
        html, errs, info = br.build_report(PROMPT, NEW_CARDS, STUB_TEMPLATE,
                                           min_cards=2)
        self.assertEqual(errs, [])
        self.assertEqual(info["cards"], 2)
        self.assertEqual(info["leak"], [])
        self.assertEqual(info["figures"]["records"], 3)

    def test_build_report_without_insights_block(self):
        # v4 lever B: a HISTORY-only prompt (no INSIGHTS) still builds & passes;
        # the cross-check is simply skipped and the flag records that.
        prompt = "intro\n" + br.HISTORY_MARK + "\n" + HISTORY
        html, errs, info = br.build_report(prompt, NEW_CARDS, STUB_TEMPLATE,
                                           min_cards=2)
        self.assertEqual(errs, [])
        self.assertFalse(info["insights_present"])
        self.assertEqual(info["figures"]["records"], 3)
        self.assertIn('"c":"Aria"', html)

    def test_summary_only_insights_still_validates(self):
        # A Summary-only INSIGHTS (the v4 minimal fallback) cross-checks cleanly.
        summary_only = (
            "Section,Label,Count,Value\r\n"
            "Summary,Records,3,\r\n"
            "Summary,Value,,10g 8s 0c\r\n"
        )
        prompt = (br.HISTORY_MARK + "\n" + HISTORY +
                  br.INSIGHTS_MARK + "\n" + summary_only)
        _, errs, info = br.build_report(prompt, NEW_CARDS, STUB_TEMPLATE,
                                        min_cards=2)
        self.assertEqual(errs, [])
        self.assertTrue(info["insights_present"])

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
        self.assertIn("Value", s)
        self.assertIn("sample-leak none", s)
        self.assertIn("PASS — wrote", s)   # original line intact


def test_history_row_has_auction_value_source():
    csv_text = ("date,time,char,classFile,itemID,itemName,quality,qualityRaw,itemLevel,bound,"
                "sellPrice,sellPriceRaw,auctionPrice,auctionPriceRaw,value,valueRaw,priceSource,"
                "itemType,itemSubType,quantity,source,zone,wowheadLink\r\n"
                "12-Jul-2026,20:37,Stormhoof-Ravencrest,SHAMAN,1,Thing,Rare,3,,Not Bound,"
                "1g 0s 0c,10000,5g 0s 0c,50000,5g 0s 0c,50000,tsm:dbmarket,"
                "Armor,Mail,2,KILL,Zone,https://wowhead.com/item=1\r\n")
    _realm, rows = br.parse_history_csv(csv_text)
    assert rows[0]["a"] == 50000
    assert rows[0]["val"] == 50000
    assert rows[0]["src"] == "tsm:dbmarket"


def test_richest_crosscheck_uses_val_times_qty_stack_total_mixed_auction():
    # Finding 1: richest-drop cross-check must key off val*qty (auction-or-vendor
    # stack-total), not the raw per-unit vendor "v". Row A has no auction price
    # (val falls back to v) and qty 1; row B has an auction price with qty 3, so
    # its stack-total (30000*3=90000c) dwarfs its own per-unit v (2000c) and A's
    # v (5000c) — a max(v)-based check would wrongly pick 5000c here.
    rows = [
        {"v": 5000, "a": None, "val": 5000, "qty": 1,
         "id": 1, "c": "A", "qr": 1, "il": None, "d": "d"},
        {"v": 2000, "a": 30000, "val": 30000, "qty": 3,
         "id": 2, "c": "A", "qr": 1, "il": None, "d": "d"},
    ]
    # correct richest = max(val*qty) = max(5000*1, 30000*3) = 90000c = "9g 0s 0c"
    good = {("Summary", "Richest drop"): {"count": "", "value": "9g 0s 0c"}}
    assert br.validate_against_insights(rows, good) == []

    wrong = {("Summary", "Richest drop"): {"count": "", "value": "1g 0s 0c"}}
    errs = br.validate_against_insights(rows, wrong)
    assert any("Richest drop" in e for e in errs)


def test_computed_figures_richest_uses_val_times_qty():
    rows = [
        {"v": 5000, "a": None, "val": 5000, "qty": 1,
         "id": 1, "c": "A", "qr": 1, "il": None, "d": "d"},
        {"v": 2000, "a": 30000, "val": 30000, "qty": 3,
         "id": 2, "c": "A", "qr": 1, "il": None, "d": "d"},
    ]
    f = br.computed_figures(rows)
    assert f["richest"] == 90000


def test_value_crosscheck_uses_val_times_qty():
    rows = [{"v": 10000, "a": 50000, "val": 50000, "qty": 2, "id": 1, "c": "X", "qr": 3, "il": None, "d": "d"}]
    # computed = val * qty = 50000 * 2 = 100000c = "10g 0s 0c"; deliberately
    # mismatched here (brief's original "10g 0s 0c" fixture value is actually
    # equal to the computed figure, so it could never fail — bumped to 99g to
    # produce a genuine mismatch).
    insights = {("Summary", "Value"): {"count": "", "value": "99g 0s 0c"}}
    errs = br.validate_against_insights(rows, insights)
    assert any("Value" in e for e in errs)


if __name__ == "__main__":
    unittest.main()
