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


if __name__ == "__main__":
    unittest.main()
