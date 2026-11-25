"""Cases for tools/seeds/seeds.py: invented fixture tables and seed files, never the network.

Run with `python3 -m pytest -q tools/seeds` or `python3 -m unittest discover -s tools/seeds`.
Every spell id and name below is made up (ids from 990000) apart from the sentinel ids the tool
itself checks for (13262 Disenchant and the three profession lines).
"""

from __future__ import annotations

import gzip
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import seeds  # noqa: E402

ATTRIBUTION = """local CLIENT = "retail"\r
local DECONSTRUCT_IDS = { retail = {\r
  [13262] = "DISENCHANT", [990001] = "DISENCHANT",\r
  -- Milling\r
  [990010] = "MILLING", [990011] = "MILLING", [990012] = "MILLING",\r
  [990013] = "MILLING",\r
  -- Prospecting\r
  [990020] = "PROSPECTING",\r
  [990021] = "PROSPECTING",\r
}, forever = { [13262] = "DISENCHANT" } }\r
local DECONSTRUCT_ID = DECONSTRUCT_IDS[CLIENT]\r
local NAME_SEEDS_BY_CLIENT = {\r
  retail = {\r
    { source = "DISENCHANT",  id = 13262 },                    -- "Disenchant"\r
    { source = "MILLING",     id = 990010 },                   -- "Milling"\r
    { source = "MILLING",     id = 990013, dropLast = true },  -- "Mass Mill <Herb>"\r
    { source = "PROSPECTING", id = 990020 },                   -- "Prospecting"\r
  },\r
  forever = {\r
    { source = "DISENCHANT",  id = 13262 },                    -- "Disenchant"\r
  },\r
}\r
"""

SIM = """D.SPELLS = ({\r
  retail = { disenchant = 13262, milling = 990010, prospecting = 990020 },\r
  forever = { disenchant = 13262 },\r
})[Host.SIM_CLIENT]\r
"""

SKILL_LINE = [
    {"ID": "333", "DisplayName_lang": "Enchanting", "ParentSkillLineID": "0"},
    {"ID": "773", "DisplayName_lang": "Inscription", "ParentSkillLineID": "0"},
    {"ID": "755", "DisplayName_lang": "Jewelcrafting", "ParentSkillLineID": "0"},
    {"ID": "9901", "DisplayName_lang": "Invented Inscription", "ParentSkillLineID": "773"},
    {"ID": "9902", "DisplayName_lang": "Invented Cooking", "ParentSkillLineID": "0"},
]
NAMES = {
    13262: "Disenchant", 990001: "Disenchanting",
    990010: "Milling", 990011: "Testland Milling", 990012: "Not A Mill Spell", 990013: "Mass Mill Twoword Herb",
    990020: "Prospecting",
    # 990021 has no row: gone
    990030: "Otherland Milling", 990031: "Mass Mill Inventweed", 990032: "Mass Prospect Fakeore",
    990033: "Disenchant", 990034: "Disenchanting Rod", 990035: "Milling",
}
SLA = [  # (spell, skill line)
    (13262, 333), (990011, 9901), (990012, 9902), (990013, 773),
    (990030, 9901), (990031, 773), (990032, 755), (990033, 333), (990034, 333), (990035, 9902),
]


def tables() -> dict:
    return {
        "SpellName": [{"ID": str(k), "Name_lang": v} for k, v in NAMES.items()],
        "SkillLineAbility": [{"ID": str(i), "SkillLine": str(line), "Spell": str(s)}
                             for i, (s, line) in enumerate(SLA, 1)],
        "SkillLine": [dict(r) for r in SKILL_LINE],
    }


class Repo:
    """A temporary repo root holding the two seed files."""

    def __init__(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "modules").mkdir()
        (self.root / "modules" / "Attribution.lua").write_bytes(ATTRIBUTION.encode())
        (self.root / "modules" / "SimDrivers.lua").write_bytes(SIM.encode())

    def text(self) -> str:
        return (self.root / "modules" / "Attribution.lua").read_bytes().decode()

    def close(self):
        self.tmp.cleanup()


class SeedCase(unittest.TestCase):
    def setUp(self):
        self.repo = Repo()
        self.addCleanup(self.repo.close)

    def derive(self, flavor="retail"):
        return seeds.derive(flavor, tables(), seeds.shipped(flavor, self.repo.root))


class TestRead(SeedCase):
    def test_reads_each_list_per_flavor(self):
        s = seeds.shipped("retail", self.repo.root)
        self.assertEqual(len(s["ids"]), 8)
        self.assertEqual(s["ids"][990013], "MILLING")
        self.assertEqual([(n["id"], n["dropLast"]) for n in s["names"]],
                         [(13262, False), (990010, False), (990013, True), (990020, False)])
        self.assertEqual(s["sim"], {13262: "DISENCHANT", 990010: "MILLING", 990020: "PROSPECTING"})
        f = seeds.shipped("forever", self.repo.root)
        self.assertEqual(f["ids"], {13262: "DISENCHANT"})
        self.assertEqual(f["names"], [{"id": 13262, "source": "DISENCHANT", "dropLast": False}])

    def test_a_line_the_reader_cannot_parse_fails(self):
        path = self.repo.root / "modules" / "Attribution.lua"
        path.write_bytes(self.repo.text().replace('[990013] = "MILLING",', '[990013] = MILLING,').encode())
        with self.assertRaises(SystemExit):
            seeds.shipped("retail", self.repo.root)

    def test_a_duplicate_id_fails(self):
        path = self.repo.root / "modules" / "Attribution.lua"
        path.write_bytes(self.repo.text().replace('[990013] = "MILLING",', '[990010] = "MILLING",').encode())
        with self.assertRaises(SystemExit):
            seeds.shipped("retail", self.repo.root)


class TestDerive(SeedCase):
    def test_flags(self):
        keys = {f["key"] for f in self.derive()["flags"]}
        self.assertIn("shipped:gone:ids:990021", keys)
        self.assertIn("shipped:family:ids:990012", keys)              # a name outside the family
        self.assertIn("shipped:line:ids:990012", keys)                # taught by another profession
        self.assertIn("shipped:unlined:ids:990010", keys)             # no SkillLineAbility row
        self.assertIn("shipped:token:names:990013", keys)             # two-word herb: stem "Mass Mill Twoword"
        self.assertNotIn("shipped:unlined:ids:990011", keys)          # a child line folds to Inscription
        self.assertNotIn("shipped:family:ids:990001", keys)           # "Disenchanting" is in the family

    def test_candidates_are_family_names_on_the_profession_line(self):
        cands = {c["id"]: c for c in self.derive()["candidates"]}
        self.assertEqual(sorted(cands), [990030, 990031, 990032, 990033])
        self.assertEqual(cands[990030]["notes"][0], "shape expansion")
        self.assertEqual(cands[990031]["notes"][0], "shape mass")
        self.assertEqual(cands[990033]["source"], "DISENCHANT")
        # "Disenchanting Rod" is not a family name; a "Milling" taught by Cooking is not Inscription's.
        self.assertNotIn(990034, cands)
        self.assertNotIn(990035, cands)

    def test_sim_and_name_seeds_must_be_listed(self):
        path = self.repo.root / "modules" / "SimDrivers.lua"
        path.write_bytes(SIM.replace("milling = 990010", "milling = 990099").encode())
        keys = {f["key"] for f in self.derive()["flags"]}
        self.assertIn("shipped:unlisted:sim:990099", keys)

    def test_forever_checks_disenchant_alone(self):
        doc = self.derive("forever")
        self.assertEqual([c["id"] for c in doc["candidates"]], [990033])
        self.assertEqual(doc["flags"], [])
        self.assertEqual(doc["info"]["outOfScope"], ["MILLING", "PROSPECTING"])

    def test_a_thin_export_fails_its_sentinels(self):
        t = tables()
        t["SkillLine"] = [r for r in t["SkillLine"] if r["ID"] != "755"]
        with self.assertRaises(SystemExit):
            seeds.derive("retail", t, seeds.shipped("retail", self.repo.root))

    def test_cut_keeps_what_derive_reads(self):
        s = seeds.shipped("retail", self.repo.root)
        whole = seeds.derive("retail", tables(), s)
        self.assertEqual(seeds.derive("retail", seeds.cut(tables(), s), s), whole)
        self.assertNotIn("990035", {r["Spell"] for r in seeds.cut(tables(), s)["SkillLineAbility"]})


class TestRulings(unittest.TestCase):
    def test_legal_rulings(self):
        r = {}
        seeds.set_ruling(r, "ids:990030", "accept", "per-expansion")
        seeds.set_ruling(r, "shipped:gone:ids:990021", "remove", "no row")
        seeds.set_ruling(r, "shipped:token:names:990013", "fix", "hand edit")
        self.assertEqual(len(r), 3)

    def test_illegal_rulings(self):
        for key, ruling in (("ids:990030", "keep"), ("shipped:token:names:990013", "remove"),
                            ("shipped:gone:sim:1", "keep"), ("names:990013", "accept"),
                            ("shipped:nope:ids:1", "keep")):
            with self.assertRaises(SystemExit, msg=key):
                seeds.set_ruling({}, key, ruling, "why")
        with self.assertRaises(SystemExit):
            seeds.set_ruling({}, "ids:1", "accept", "")


class TestApply(SeedCase):
    def rulings(self, doc, **over):
        out = {}
        for c in doc["candidates"]:
            out[c["key"]] = {"ruling": "accept" if c["id"] in (990030, 990031) else "reject", "reason": "x"}
        for f in doc["flags"]:
            ruling = {"ids": "remove" if f["kind"] in ("gone", "family", "line") else "keep",
                      "names": "fix", "sim": "keep"}[f["list"]]
            out[f["key"]] = {"ruling": ruling, "reason": "x"}
        out.update(over)
        return out

    def doc(self):
        d = self.derive()
        d["flavor"] = "retail"
        return d

    def test_refuses_unruled(self):
        with self.assertRaises(SystemExit):
            seeds.apply_bundle(self.doc(), {}, self.repo.root)

    def test_refuses_while_a_fix_is_owed(self):
        doc = self.doc()
        with self.assertRaises(SystemExit):
            seeds.apply_bundle(doc, self.rulings(doc), self.repo.root)

    def test_writes_adds_and_removals_once_and_keeps_crlf(self):
        doc = self.doc()
        rulings = self.rulings(doc)
        path = self.repo.root / "modules" / "Attribution.lua"
        path.write_bytes(self.repo.text().replace("id = 990013, dropLast", "id = 990031, dropLast").encode())
        changes = seeds.apply_bundle(doc, rulings, self.repo.root)
        self.assertEqual(len(changes), 1)
        self.assertIn("-990012", changes[0])
        self.assertIn("-990021", changes[0])
        self.assertIn("+990030", changes[0])
        self.assertIn("+990031", changes[0])
        text = self.repo.text()
        self.assertNotIn("\n", text.replace("\r\n", ""))
        for line in text.split("\r\n"):
            self.assertEqual(line, line.rstrip(), "no trailing whitespace")
        ids = seeds.read_ids(text.replace("\r\n", "\n"), "retail")
        self.assertEqual(ids.get(990030), "MILLING")
        self.assertNotIn(990012, ids)
        self.assertNotIn(990021, ids)
        self.assertEqual(seeds.read_ids(text.replace("\r\n", "\n"), "forever"), {13262: "DISENCHANT"})
        # The emptied Prospecting line is gone (no blank line left), the Milling adds sit after the
        # Milling lines.
        self.assertNotIn("\r\n\r\n", text)
        self.assertEqual(text.count("PROSPECTING"), 2)  # 990020: its entry and its name seed
        self.assertLess(text.index("[990030]"), text.index("-- Prospecting"))
        self.assertEqual(seeds.apply_bundle(doc, rulings, self.repo.root), [])
        self.assertEqual(self.repo.text(), text)

    def test_forever_writes_are_a_hand_edit(self):
        doc = dict(self.derive("forever"), flavor="forever")
        rulings = {c["key"]: {"ruling": "accept", "reason": "x"} for c in doc["candidates"]}
        with self.assertRaises(SystemExit):
            seeds.apply_bundle(doc, rulings, self.repo.root)


class TestBundle(SeedCase):
    def test_derive_freezes_a_replayable_bundle(self):
        cache = self.repo.root / "cache" / "1.2.3.4"
        cache.mkdir(parents=True)
        for name, rows in tables().items():
            cols = seeds.COLUMNS[name]
            body = ",".join(cols) + "\n" + "".join(
                ",".join('"%s"' % r[c] for c in cols) + "\n" for r in rows)
            (cache / (name + ".csv")).write_text(body, encoding="utf-8")
        bundle = self.repo.root / "b" / "2026-01-01-retail"
        doc = seeds.derive_bundle("retail", bundle, "2026-01-01", "1.2.3.4", False, cache.parent, self.repo.root)
        first = (bundle / "candidates.json").read_bytes()
        raw = (bundle / "raw" / "SpellName.csv.gz").read_bytes()
        self.assertTrue(gzip.decompress(raw).startswith(b"ID,Name_lang"))
        again = seeds.derive_bundle("retail", bundle, "2026-01-01", None, True, cache.parent, self.repo.root)
        self.assertEqual(again["candidates"], doc["candidates"])
        self.assertEqual((bundle / "candidates.json").read_bytes(), first)
        self.assertIn(b"1.2.3.4", (bundle / "SOURCES.md").read_bytes())
        self.assertEqual(json.loads(first)["build"], "1.2.3.4")
        self.assertEqual(seeds.status_line("1.2.3.4", [bundle]), "CURRENT 1.2.3.4 (2026-01-01-retail)")
        self.assertTrue(seeds.status_line("1.2.3.5", [bundle]).startswith("NEW 1.2.3.5"))

    def test_report_names_every_key(self):
        doc = dict(self.derive(), flavor="retail", date="2026-01-01", build="1.2.3.4", checked=15)
        md = seeds.rulings_md(doc, {}, "2026-01-01")
        self.assertIn("## Unruled: %d" % len(seeds.all_keys(doc)), md)
        for key in seeds.all_keys(doc):
            self.assertIn("`%s`" % key, md)


if __name__ == "__main__":
    unittest.main()
