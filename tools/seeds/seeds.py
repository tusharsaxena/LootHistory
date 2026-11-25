#!/usr/bin/env python3
"""tools/seeds/seeds.py: re-validate Loot History's deconstruct seeds against one wago.tools build.

WHAT THIS IS
    The seed-validation tool `/dev-copilot:validate-seeds LootHistory <flavor>` runs, under the
    contract in docs/validate-seeds.md. A flavor is a client: `retail` reads wago.tools product
    `wow`, `forever` reads product `wowf`, each client's own tables and never a filtered copy of the
    other's (clients-§5, clients-§10). Every shipped id is checked against one pinned build, and what
    the build has that a list lacks is proposed. Each proposal and each flag needs a ruling, recorded
    as data in tools/seeds/<flavor>_rulings.json, keyed by list and id, never by build, so a re-run
    on a later build shows only what is new.

    The lists it reads (modules/Attribution.lua's header is the precedent):
        ids     DECONSTRUCT_IDS[<flavor>]       spell id -> DISENCHANT | MILLING | PROSPECTING
        names   NAME_SEEDS_BY_CLIENT[<flavor>]  the name-family seeds (`dropLast` = a mass stem)
        sim     modules/SimDrivers.lua D.SPELLS the simulator's casts (checked against `ids` only)

    A source belongs to one profession's skill line (SkillLine, every child folded to its root by
    ParentSkillLineID): Disenchant to Enchanting (333), Milling to Inscription (773), Prospecting to
    Jewelcrafting (755). WoW Forever's Milling and Prospecting are EMPTY BY DECISION (D15, ruling R2):
    the forever flavor checks and proposes Disenchant alone, and records in `info` whether the build
    has the other two lines at all.

    The family a source's spell names belong to, on the build's enUS names:
        DISENCHANT   plain "Disenchant" or "Disenchanting"
        MILLING      plain "Milling", expansion "<X> Milling", mass "Mass Mill <Herb>"
        PROSPECTING  plain "Prospecting", expansion "<X> Prospecting", mass "Mass Prospect <Ore>"

    Candidates (key `ids:<spell>`, ruled accept or reject): a spell on the source's profession line
    (SkillLineAbility) whose name is in the source's family, absent from `ids`. Its note says which
    shape it is (plain, expansion or mass), which is what the header's enumeration rule reads.

    Flags (key `shipped:<kind>:<list>:<id>`):
        ids    gone     the build's SpellName has no row for it                 keep | remove
               family   its name is not in its source's family                  keep | remove
               line     SkillLineAbility files it, but never under its profession keep | remove
               unlined  no SkillLineAbility row at all (a retired or base spell) keep | remove
        names  gone     as above                                                keep | fix
               token    its name does not make the stem its role needs: a plain seed must be the
                        bare family word, a `dropLast` seed "Mass Mill|Prospect <one word>"  keep | fix
               unlisted the seed's id is not in `ids` under the same source     keep | fix
        sim    unlisted the simulator's cast is not in `ids` under its source   keep | fix
    `remove` is applied by `apply`; `fix` is a hand edit, and `apply` refuses while the shipped file
    still holds the subject of a flag ruled `fix`.

THE STEPS (docs/validate-seeds.md has them per flavor)
    python3 -I tools/seeds/seeds.py status [--flavor retail|forever]
    python3 -I tools/seeds/seeds.py derive --flavor F --bundle B --date D [--build V] [--replay]
    python3 -I tools/seeds/seeds.py check  --bundle B
    python3 -I tools/seeds/seeds.py rule   --tsv FILE --bundle B
    python3 -I tools/seeds/seeds.py report --bundle B --date D
    python3 -I tools/seeds/seeds.py apply  --bundle B --date D

    `derive` pins one build (the client's newest live non-bgdl build, or --build), fetches each table
    at `?build=` with the User-Agent `LootHistory-seed-check`, streams it into tools/seeds/.cache/
    <build>/ (git-ignored), and freezes the rows it reads as the bundle's raw/*.csv.gz (SpellName and
    SkillLineAbility cut to the three professions' spells and the shipped ids, so a bundle stays
    small), with SOURCES.md and candidates.json. `--replay` re-derives from the bundle's raw/ alone.
    `rule` is the only writer of the rulings file. `check` exits 1 while anything is unruled.
    `report` writes RULINGS.md. `apply` refuses while anything is unruled, writes the accepted ids and
    the ruled removals into DECONSTRUCT_IDS with the file's own line endings, and changes nothing on a
    second run. The date is always an argument; nothing here reads the clock.

    Copied in shape from Quick Comms' and Drop Watcher's tools/seeds/seeds.py (patterns, never an
    import across repos). Whether a shared helper should carry the build pin, the cache, the bundle
    and the rulings is LibKa0s#91. No ForeverDB step: spells are client data, which DB2 holds.

Python 3.8+ and its standard library only. Dev-only: never loaded by the client, and .pkgmeta
ignores tools/.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import io
import json
import re
import shutil
import sys
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
RESEARCH = ROOT / "docs" / "seed-research"
CACHE = HERE / ".cache"
ATTRIBUTION = Path("modules") / "Attribution.lua"
SIM_DRIVERS = Path("modules") / "SimDrivers.lua"

BUILDS_URL = "https://wago.tools/api/builds"
TABLE_URL = "https://wago.tools/db2/{}/csv?build={}"
USER_AGENT = "LootHistory-seed-check"
CHUNK = 1 << 20
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

SOURCES = ("DISENCHANT", "MILLING", "PROSPECTING")
PROFESSION = {"DISENCHANT": 333, "MILLING": 773, "PROSPECTING": 755}
PROFESSION_NAME = {333: "Enchanting", 773: "Inscription", 755: "Jewelcrafting"}
# (shape, pattern) per source, tried in order; the first match names the shape.
FAMILY = {
    "DISENCHANT": (("plain", re.compile(r"^Disenchant(?:ing)?$")),),
    "MILLING": (("plain", re.compile(r"^Milling$")), ("expansion", re.compile(r"^\S.* Milling$")),
                ("mass", re.compile(r"^Mass Mill \S"))),
    "PROSPECTING": (("plain", re.compile(r"^Prospecting$")), ("expansion", re.compile(r"^\S.* Prospecting$")),
                    ("mass", re.compile(r"^Mass Prospect \S"))),
}
# The stem a `dropLast` seed must leave once its last word is gone (seedToken, Attribution.lua).
MASS_STEM = {"MILLING": "Mass Mill", "PROSPECTING": "Mass Prospect"}

TABLES = (
    ("SpellName", "the name of every shipped id and of every profession-line spell (the family match)"),
    ("SkillLineAbility", "which skill line teaches a spell: the profession a source belongs to"),
    ("SkillLine", "ParentSkillLineID, to fold an expansion's child line into its profession"),
)
COLUMNS = {
    "SpellName": ("ID", "Name_lang"),
    "SkillLineAbility": ("ID", "SkillLine", "Spell"),
    "SkillLine": ("ID", "DisplayName_lang", "ParentSkillLineID"),
}
FLAVORS = {
    "retail": {
        "product": "wow", "client": "Retail", "sources": SOURCES,
        # (table, id column, id, column, value): game facts a thin or wrong export fails on.
        "sentinels": (
            ("SpellName", "ID", "13262", "Name_lang", "Disenchant"),
            ("SkillLine", "ID", "333", "DisplayName_lang", "Enchanting"),
            ("SkillLine", "ID", "773", "DisplayName_lang", "Inscription"),
            ("SkillLine", "ID", "755", "DisplayName_lang", "Jewelcrafting"),
            ("SkillLineAbility", "Spell", "13262", "SkillLine", "333"),
        ),
    },
    "forever": {
        "product": "wowf", "client": "WoW Forever", "sources": ("DISENCHANT",),
        "sentinels": (
            ("SpellName", "ID", "13262", "Name_lang", "Disenchant"),
            ("SkillLine", "ID", "333", "DisplayName_lang", "Enchanting"),
            ("SkillLineAbility", "Spell", "13262", "SkillLine", "333"),
        ),
    },
}

LIST_KEYS = ("ids", "names", "sim")
CANDIDATE_RULINGS = ("accept", "reject")
FLAG_KINDS = {"ids": ("gone", "family", "line", "unlined"), "names": ("gone", "token", "unlisted"),
              "sim": ("unlisted",)}
FLAG_RULINGS = {"ids": ("keep", "remove"), "names": ("keep", "fix"), "sim": ("keep", "fix")}
KEY = re.compile(r"^(?:shipped:(?P<kind>[a-z]+):)?(?P<list>[a-z]+):(?P<id>\d+)$")


def fail(msg: str) -> None:
    """Stop loudly: a thin or partial derivation must never look like a result."""
    raise SystemExit("FAIL: " + msg)


def log(msg: str) -> None:
    print(msg, file=sys.stderr)


# ---------------------------------------------------------------------------
# Files: bytes in, bytes out, line endings kept
# ---------------------------------------------------------------------------

def read_text(path: Path) -> tuple[str, str]:
    """`(text with LF, the file's terminator)`: CRLF when the file has one, else LF."""
    raw = path.read_bytes().decode("utf-8")
    eol = "\r\n" if "\r\n" in raw else "\n"
    return raw.replace("\r\n", "\n"), eol


def write_text(path: Path, text: str, eol: str = "\n") -> None:
    """Write `text` (LF inside) with terminator `eol`, as bytes, so no platform default applies."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.replace("\r\n", "\n").replace("\n", eol).encode("utf-8"))


def repo_eol(path: Path) -> str:
    """The terminator .gitattributes pins for a new file: LF for .py and .sh, CRLF otherwise."""
    return "\n" if path.suffix in (".py", ".sh") else "\r\n"


def write_json(path: Path, doc) -> None:
    write_text(path, json.dumps(doc, indent=1, sort_keys=True, ensure_ascii=False) + "\n", repo_eol(path))


# ---------------------------------------------------------------------------
# wago.tools: one build, cached, streamed
# ---------------------------------------------------------------------------

def _open(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    return urllib.request.urlopen(req, timeout=180)


def live_build(product: str) -> dict:
    """The product's newest build the builds API lists that is not a background download."""
    with _open(BUILDS_URL) as r:
        builds = json.load(r)
    for b in builds.get(product) or ():
        if not b.get("is_bgdl"):
            return b
    fail("the builds API lists no live build for product " + product)
    return {}


def fetch_table(table: str, build: str, cache: Path) -> Path:
    """The table's CSV at `build`, from the cache or streamed into it. The export must name the
    build asked for (its Content-Disposition), or the run fails: wago answers the newest build,
    PTR included, when `?build=` is empty or unknown."""
    path = cache / build / (table + ".csv")
    if path.exists():
        return path
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".part")
    with _open(TABLE_URL.format(table, urllib.parse.quote(build))) as r:
        named = re.search(r'filename="[^"]*?\.([0-9.]+)\.csv"', r.headers.get("Content-Disposition") or "")
        if not named or named.group(1) != build:
            fail("%s's export is not build %s (Content-Disposition %r)"
                 % (table, build, r.headers.get("Content-Disposition")))
        with tmp.open("wb") as f:
            shutil.copyfileobj(r, f, CHUNK)
    tmp.replace(path)
    return path


def read_csv(path: Path, columns, opener=open) -> list[dict]:
    """A table's rows, only the columns named, every one of which must be in the header."""
    with opener(path, "rt", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        missing = [c for c in columns if c not in (reader.fieldnames or ())]
        if missing:
            fail("%s has no column %s" % (path.name, ", ".join(missing)))
        rows = [{c: row[c] for c in columns} for row in reader]
    if not rows:
        fail(path.name + " is empty")
    return rows


def freeze_rows(rows: list[dict], columns, member: Path) -> None:
    """The rows as a deterministic gzipped CSV (mtime 0, so a re-freeze is byte-identical)."""
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=list(columns), lineterminator="\n")
    w.writeheader()
    w.writerows(rows)
    member.parent.mkdir(parents=True, exist_ok=True)
    with member.open("wb") as out:
        with gzip.GzipFile(filename="", mode="wb", fileobj=out, compresslevel=9, mtime=0) as dst:
            dst.write(buf.getvalue().encode("utf-8"))


# ---------------------------------------------------------------------------
# The seed files
# ---------------------------------------------------------------------------

IDS_START = "local DECONSTRUCT_IDS = { retail = {"
IDS_ENTRY = re.compile(r'\[(?P<id>\d+)\]\s*=\s*"(?P<src>[A-Z]+)"')
NAMES_START = "local NAME_SEEDS_BY_CLIENT = {"
NAME_ENTRY = re.compile(r'\{\s*source\s*=\s*"(?P<src>[A-Z]+)",\s*id\s*=\s*(?P<id>\d+)'
                        r'(?P<drop>,\s*dropLast\s*=\s*true)?\s*\}')
SIM_LINE = re.compile(r"^\s*(?P<client>retail|forever)\s*=\s*\{(?P<body>[^}]*)\},?\s*$")
SIM_ENTRY = re.compile(r"(?P<verb>[a-z]+)\s*=\s*(?P<id>\d+)")
SIM_SOURCE = {"disenchant": "DISENCHANT", "milling": "MILLING", "prospecting": "PROSPECTING"}


def ids_block(text: str) -> dict[str, tuple[int, int]]:
    """`{flavor: (first line, last line)}` (inclusive, 0-based) of DECONSTRUCT_IDS' two tables:
    Retail's runs from the opening line to the line that opens `forever = {`, which also closes it,
    and Forever's is that one line."""
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if line.strip() == IDS_START:
            for j in range(i + 1, len(lines)):
                if re.match(r"^\s*\},\s*forever\s*=\s*\{.*\}\s*\}\s*$", lines[j]):
                    return {"retail": (i, j), "forever": (j, j)}
            break
    fail("no `%s ... }, forever = { ... } }` table in %s" % (IDS_START, ATTRIBUTION))
    return {}


def read_ids(text: str, flavor: str) -> dict[int, str]:
    lines = text.split("\n")
    first, last = ids_block(text)[flavor]
    out: dict[int, str] = {}
    for n, line in enumerate(lines[first:last + 1], first):
        part = line
        if flavor == "retail" and n == last:
            part = line.split("forever", 1)[0]
        elif flavor == "forever":
            part = line.split("forever", 1)[1]
        for m in IDS_ENTRY.finditer(part):
            ident = int(m.group("id"))
            if ident in out:
                fail("DECONSTRUCT_IDS.%s lists %d twice" % (flavor, ident))
            if m.group("src") not in SOURCES:
                fail("DECONSTRUCT_IDS.%s files %d under unknown source %s" % (flavor, ident, m.group("src")))
            out[ident] = m.group("src")
        rest = IDS_ENTRY.sub("", part.split("--", 1)[0])
        if re.search(r"[0-9\"]", rest):
            fail("DECONSTRUCT_IDS.%s: a line holds something other than [id] = \"SOURCE\": %r" % (flavor, line))
    if not out:
        fail("DECONSTRUCT_IDS.%s is empty" % flavor)
    return out


def read_names(text: str, flavor: str) -> list[dict]:
    lines = text.split("\n")
    try:
        start = next(i for i, x in enumerate(lines) if x.strip() == NAMES_START)
    except StopIteration:
        fail("no `%s` table in %s" % (NAMES_START, ATTRIBUTION))
    inside, out = False, []
    for line in lines[start + 1:]:
        s = line.split("--", 1)[0].strip()
        if not inside:
            if s == "%s = {" % flavor:
                inside = True
            elif s == "}":
                break
            continue
        if s in ("},", "}"):
            break
        if not s:
            continue
        m = NAME_ENTRY.search(s)
        if not m:
            fail("NAME_SEEDS_BY_CLIENT.%s: a line is not { source = .., id = .. }: %r" % (flavor, line))
        out.append({"id": int(m.group("id")), "source": m.group("src"), "dropLast": bool(m.group("drop"))})
    if not out:
        fail("NAME_SEEDS_BY_CLIENT.%s is empty or missing" % flavor)
    return out


def read_sim(text: str, flavor: str) -> dict[int, str]:
    for line in text.split("\n"):
        m = SIM_LINE.match(line)
        if m and m.group("client") == flavor:
            out = {}
            for e in SIM_ENTRY.finditer(m.group("body")):
                if e.group("verb") not in SIM_SOURCE:
                    fail("D.SPELLS.%s: unknown cast %s" % (flavor, e.group("verb")))
                out[int(e.group("id"))] = SIM_SOURCE[e.group("verb")]
            return out
    fail("no `%s = { ... }` row of D.SPELLS in %s" % (flavor, SIM_DRIVERS))
    return {}


def shipped(flavor: str, root: Path) -> dict:
    attribution, _eol = read_text(root / ATTRIBUTION)
    sim, _eol = read_text(root / SIM_DRIVERS)
    return {"ids": read_ids(attribution, flavor), "names": read_names(attribution, flavor),
            "sim": read_sim(sim, flavor)}


# ---------------------------------------------------------------------------
# Derive: candidates and flags
# ---------------------------------------------------------------------------

def shape(source: str, name: str) -> str | None:
    """Which of the source's family shapes `name` is (plain, expansion or mass), else None."""
    for kind, pattern in FAMILY[source]:
        if pattern.search(name or ""):
            return kind
    return None


def _flag(kind, lst, ident, name, shipped_as, why):
    return {"key": "shipped:%s:%s:%d" % (kind, lst, ident), "kind": kind, "list": lst, "id": ident,
            "name": name, "shipped": shipped_as, "why": why}


def _cand(ident, name, source, notes):
    return {"key": "ids:%d" % ident, "list": "ids", "id": ident, "name": name, "source": source, "notes": notes}


def check_sentinels(flavor: str, t: dict[str, list[dict]]) -> None:
    missing = []
    for table, idcol, ident, col, value in FLAVORS[flavor]["sentinels"]:
        if not any(r[idcol] == ident and r[col] == value for r in t[table]):
            missing.append("%s %s=%s with %s=%s" % (table, idcol, ident, col, value))
    if missing:
        fail("%s sentinels missing (a thin or wrong export): %s" % (flavor, "; ".join(missing)))


def profession_of(skill_lines: dict[int, dict]):
    """A function folding a skill line to its root (ParentSkillLineID, a bounded walk)."""
    def root(line: int) -> int:
        for _ in range(8):
            parent = int((skill_lines.get(line) or {}).get("ParentSkillLineID") or 0)
            if not parent:
                break
            line = parent
        return line
    return root


def index(t: dict[str, list[dict]]):
    """`(names {spell: name}, lines {spell: {root profession lines}})` over the tables."""
    names = {int(r["ID"]): r["Name_lang"] for r in t["SpellName"]}
    root = profession_of({int(r["ID"]): r for r in t["SkillLine"]})
    lines: dict[int, set[int]] = {}
    for r in t["SkillLineAbility"]:
        lines.setdefault(int(r["Spell"]), set()).add(root(int(r["SkillLine"])))
    return names, lines


def derive(flavor: str, t: dict[str, list[dict]], seeds: dict) -> dict:
    check_sentinels(flavor, t)
    names, lines = index(t)
    sources = FLAVORS[flavor]["sources"]
    flags, cands = [], []
    ids = seeds["ids"]
    for ident in sorted(ids):
        src, name = ids[ident], names.get(ident)
        if name is None:
            flags.append(_flag("gone", "ids", ident, "", src, "SpellName has no row %d" % ident))
            continue
        if shape(src, name) is None:
            flags.append(_flag("family", "ids", ident, name, src, "%r is not a %s family name" % (name, src)))
        on = lines.get(ident)
        if not on:
            flags.append(_flag("unlined", "ids", ident, name, src, "no SkillLineAbility row teaches it"))
        elif PROFESSION[src] not in on:
            flags.append(_flag("line", "ids", ident, name, src, "taught under skill line(s) %s, not %s (%d)" % (
                ", ".join(map(str, sorted(on))), PROFESSION_NAME[PROFESSION[src]], PROFESSION[src])))
    for seed in seeds["names"]:
        ident, src, name = seed["id"], seed["source"], names.get(seed["id"])
        role = "dropLast" if seed["dropLast"] else "plain"
        if ids.get(ident) != src:
            flags.append(_flag("unlisted", "names", ident, name or "", src + " " + role,
                               "DECONSTRUCT_IDS does not file %d under %s" % (ident, src)))
        if name is None:
            flags.append(_flag("gone", "names", ident, "", src + " " + role, "SpellName has no row %d" % ident))
            continue
        if seed["dropLast"]:
            stem = re.sub(r"\s+\S+\s*$", "", name).strip()
            if stem != MASS_STEM.get(src):
                flags.append(_flag("token", "names", ident, name, src + " " + role,
                                   "its stem is %r; a %s dropLast seed needs %r" % (stem, src, MASS_STEM.get(src))))
        elif shape(src, name) != "plain":
            flags.append(_flag("token", "names", ident, name, src + " " + role,
                               "%r is not the bare %s family word" % (name, src)))
    for ident, src in sorted(seeds["sim"].items()):
        if ids.get(ident) != src:
            flags.append(_flag("unlisted", "sim", ident, names.get(ident) or "", src,
                               "DECONSTRUCT_IDS does not file %d under %s" % (ident, src)))
    for spell in sorted(lines):
        if spell in ids:
            continue
        for src in sources:
            if PROFESSION[src] in lines[spell]:
                kind = shape(src, names.get(spell, ""))
                if kind:
                    cands.append(_cand(spell, names[spell], src, ["shape " + kind,
                                       "taught under %s (%d)" % (PROFESSION_NAME[PROFESSION[src]], PROFESSION[src])]))
    have = {int(r["ID"]) for r in t["SkillLine"]}
    info = {"professionLines": {PROFESSION_NAME[p]: (p in have) for p in sorted(PROFESSION.values())},
            "outOfScope": [s for s in SOURCES if s not in sources]}
    order = {k: i for i, k in enumerate(LIST_KEYS)}
    flags.sort(key=lambda f: (order[f["list"]], f["kind"], f["id"]))
    return {"candidates": cands, "flags": flags, "info": info}


# ---------------------------------------------------------------------------
# Bundles
# ---------------------------------------------------------------------------

def load_candidates(bundle: Path) -> dict:
    path = bundle / "candidates.json"
    if not path.exists():
        fail("%s has no candidates.json: run derive first" % bundle)
    return json.loads(path.read_text(encoding="utf-8"))


def bundles(root: Path, flavor: str) -> list[Path]:
    """Every bundle of the flavor under `root`, oldest first (dates sort by name)."""
    return sorted(p for p in root.glob("*-" + flavor) if (p / "candidates.json").exists())


def status_line(live: str, found: list[Path]) -> str:
    """`CURRENT <build> (<bundle>)`, or `NEW <build> ...`: the first word is what the command reads."""
    if not found:
        return "NEW %s (no bundle yet)" % live
    built = load_candidates(found[-1])["build"]
    if built == live:
        return "CURRENT %s (%s)" % (live, found[-1].name)
    return "NEW %s (last ruled %s, %s)" % (live, built, found[-1].name)


def cut(t: dict[str, list[dict]], seeds: dict) -> dict[str, list[dict]]:
    """The rows `derive` reads: SkillLine whole; SkillLineAbility's rows on a source's profession
    and the shipped ids' rows; SpellName's rows for those spells. Derive on the cut equals derive on
    the whole export, so a replay from raw/ reproduces the run."""
    root = profession_of({int(r["ID"]): r for r in t["SkillLine"]})
    shipped_ids = set(seeds["ids"]) | {s["id"] for s in seeds["names"]} | set(seeds["sim"])
    wanted = set(PROFESSION.values())
    sla = [r for r in t["SkillLineAbility"]
           if int(r["Spell"]) in shipped_ids or root(int(r["SkillLine"])) in wanted]
    spells = {int(r["Spell"]) for r in sla} | shipped_ids
    return {"SkillLine": t["SkillLine"], "SkillLineAbility": sla,
            "SpellName": [r for r in t["SpellName"] if int(r["ID"]) in spells]}


def sources_md(doc: dict) -> str:
    fl = FLAVORS[doc["flavor"]]
    lines = ["# Sources: seed validation, %s, %s" % (doc["flavor"], doc["date"]), "",
             "Generated by `tools/seeds/seeds.py derive`. Frozen: never edited after the run.", "",
             "| Field | Value |", "| --- | --- |",
             "| Flavor | `%s` (%s, wago.tools product `%s`) |" % (doc["flavor"], fl["client"], fl["product"]),
             "| Build | `%s` |" % doc["build"],
             "| Build created (builds API) | %s |" % (doc.get("buildCreated") or "not recorded (pinned by --build)"),
             "| Run date | %s |" % doc["date"],
             "| Builds API | <%s> |" % BUILDS_URL,
             "| User-Agent | `%s` |" % USER_AGENT,
             "| Sources checked | %s |" % ", ".join(fl["sources"]), "",
             "## Tables", "", "| Table | Why | URL | Rows kept |", "| --- | --- | --- | --- |"]
    for table, why in TABLES:
        lines.append("| `%s` | %s | <%s> | %d |" % (table, why, TABLE_URL.format(table, doc["build"]),
                                                 doc["rows"][table]))
    lines += ["", "The gzipped exports in `raw/` hold only the columns `tools/seeds/seeds.py` reads, and only "
              "the rows `derive` reads: SkillLine whole, and SkillLineAbility and SpellName cut to the "
              "Enchanting, Inscription and Jewelcrafting spells and the shipped ids. Replay offline with "
              "`derive --replay`.", "",
              "## Counts", "",
              "%d shipped ids checked, %d candidates, %d flags." % (doc["checked"], len(doc["candidates"]),
                                                                    len(doc["flags"])), ""]
    return "\n".join(lines)


def derive_bundle(flavor: str, bundle: Path, date: str, build: str | None, replay: bool,
                  cache: Path, root: Path) -> dict:
    fl = FLAVORS[flavor]
    raw = bundle / "raw"
    created = None
    if replay:
        old = load_candidates(bundle)
        if old["flavor"] != flavor:
            fail("%s is a %s bundle" % (bundle, old["flavor"]))
        build, created = old["build"], old.get("buildCreated")
    elif build is None:
        b = live_build(fl["product"])
        build, created = b["version"], b.get("created_at")
    seeds = shipped(flavor, root)
    tables = {}
    for table, _why in TABLES:
        member = raw / (table + ".csv.gz")
        if replay:
            if not member.exists():
                fail("--replay: %s has no raw/%s.csv.gz" % (bundle, table))
            tables[table] = read_csv(member, COLUMNS[table], gzip.open)
        else:
            tables[table] = read_csv(fetch_table(table, build, cache), COLUMNS[table])
    if not replay:
        check_sentinels(flavor, tables)
        tables = cut(tables, seeds)
        for table, _why in TABLES:
            freeze_rows(tables[table], COLUMNS[table], raw / (table + ".csv.gz"))
    result = derive(flavor, tables, seeds)
    checked = len(seeds["ids"]) + len(seeds["names"]) + len(seeds["sim"])
    doc = {"flavor": flavor, "product": fl["product"], "build": build, "buildCreated": created, "date": date,
           "tool": "tools/seeds/seeds.py derive", "checked": checked,
           "counts": {k: len(seeds[k]) for k in LIST_KEYS},
           "rows": {k: len(v) for k, v in tables.items()}, **result}
    write_json(bundle / "candidates.json", doc)
    write_text(bundle / "SOURCES.md", sources_md(doc), "\r\n")
    return doc


# ---------------------------------------------------------------------------
# Rulings
# ---------------------------------------------------------------------------

def rulings_path(flavor: str, here: Path = HERE) -> Path:
    return here / ("%s_rulings.json" % flavor)


def load_rulings(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def all_keys(doc: dict) -> list[str]:
    return [c["key"] for c in doc["candidates"]] + [f["key"] for f in doc["flags"]]


def unruled(doc: dict, rulings: dict) -> list[str]:
    return [k for k in all_keys(doc) if k not in rulings]


def set_ruling(rulings: dict, key: str, ruling: str, reason: str) -> None:
    m = KEY.match(key)
    if not m or m.group("list") not in LIST_KEYS:
        fail("key %r is not ids:<id> or shipped:<kind>:<list>:<id>" % key)
    kind, lst = m.group("kind"), m.group("list")
    if kind is None and lst != "ids":
        fail("key %r: only the ids list has candidates" % key)
    if kind and kind not in FLAG_KINDS[lst]:
        fail("key %r: unknown flag kind %r for list %s" % (key, kind, lst))
    allowed = FLAG_RULINGS[lst] if kind else CANDIDATE_RULINGS
    if ruling not in allowed:
        fail("ruling for %s must be %s; got %r" % (key, " or ".join(allowed), ruling))
    reason = (reason or "").strip()
    if not reason or "\n" in reason:
        fail("reason for %s must be one non-empty line" % key)
    rulings[key] = {"ruling": ruling, "reason": reason}


def read_tsv(path: Path) -> list[tuple[str, str, str]]:
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 3:
            fail("%s: a ruling line is key<TAB>ruling<TAB>reason; got %r" % (path, line))
        out.append((parts[0].strip(), parts[1].strip(), parts[2].strip()))
    return out


# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------

PER_LINE = 3


def edit_ids(text: str, flavor: str, add: list[tuple[int, str]], drop: set[int]) -> tuple[str, list[str]]:
    """DECONSTRUCT_IDS.retail with `drop` taken out and `add` put in, each new entry on a new line
    after its source's last line (PER_LINE to a line, at the block's indent). Forever's one-line
    table is a hand edit (apply refuses before it gets here)."""
    lines = text.split("\n")
    first, last = ids_block(text)[flavor]
    changes = []
    have = read_ids(text, flavor)
    emptied = set()
    for n in range(first + 1, last):   # Retail's entries sit between its opening and closing lines
        line = lines[n]
        for m in list(IDS_ENTRY.finditer(line)):
            if int(m.group("id")) in drop:
                changes.append("-%s" % m.group("id"))
        edited = re.sub(r'\[(\d+)\]\s*=\s*"[A-Z]+",?[ \t]*',
                        lambda m: "" if int(m.group(1)) in drop else m.group(0), line)
        if edited != line:
            lines[n] = edited.rstrip()
            if not lines[n].strip():
                emptied.add(n)
    # A body line the removals emptied goes; the first and last lines, and any blank line the file
    # already had, stay.
    body = [i for i in range(first + 1, last) if i not in emptied]
    keep = lines[:first + 1] + [lines[i] for i in body] + lines[last:]
    lines, last = keep, first + 1 + len(body)
    indent = next((re.match(r"^\s*", lines[i]).group(0) for i in range(first + 1, last)
                   if IDS_ENTRY.search(lines[i])), "  ")
    new = [(i, s) for i, s in sorted(add) if i not in have]
    for src in SOURCES:
        rows = [i for i, s in new if s == src]
        if not rows:
            continue
        at = max((i for i in range(first + 1, last) if '"%s"' % src in lines[i]), default=last - 1)
        chunk = [", ".join('[%d] = "%s"' % (i, src) for i in rows[k:k + PER_LINE]) + ","
                 for k in range(0, len(rows), PER_LINE)]
        lines[at + 1:at + 1] = [indent + c for c in chunk]
        last += len(chunk)
        changes += ["+%d" % i for i in rows]
    return "\n".join(lines), changes


def plan(doc: dict, rulings: dict, seeds: dict) -> tuple[list[dict], list[dict]]:
    """`(accepted candidates, flags ruled remove)`; refuses while anything is unruled, on a Forever
    write (a hand edit), and while a flag ruled `fix` still describes the shipped file."""
    left = unruled(doc, rulings)
    if left:
        fail("apply refused: %d key(s) unruled (check lists them)" % len(left))
    adds = [c for c in doc["candidates"] if rulings[c["key"]]["ruling"] == "accept"]
    drops = [f for f in doc["flags"] if rulings[f["key"]]["ruling"] == "remove"]
    if doc["flavor"] != "retail" and (adds or drops):
        fail("apply refused: DECONSTRUCT_IDS.forever is a hand edit (docs/validate-seeds.md, Rules)")
    for f in doc["flags"]:
        if rulings[f["key"]]["ruling"] != "fix":
            continue
        lst, ident = f["list"], f["id"]
        still = (any(s["id"] == ident for s in seeds["names"]) if lst == "names" else ident in seeds["sim"])
        if still:
            fail("apply refused: %s is ruled fix and the shipped file still holds it; make the hand edit, "
                 "then `derive --replay`" % f["key"])
    return adds, drops


def apply_bundle(doc: dict, rulings: dict, root: Path) -> list[str]:
    flavor = doc["flavor"]
    seeds = shipped(flavor, root)
    adds, drops = plan(doc, rulings, seeds)
    path = root / ATTRIBUTION
    text, eol = read_text(path)
    new, changes = edit_ids(text, flavor, [(c["id"], c["source"]) for c in adds], {f["id"] for f in drops})
    if new != text:
        write_text(path, new, eol)
    return ["%s DECONSTRUCT_IDS.%s: %s" % (ATTRIBUTION.as_posix(), flavor, " ".join(changes))] if changes else []


# ---------------------------------------------------------------------------
# RULINGS.md
# ---------------------------------------------------------------------------

def _cell(text) -> str:
    return str(text if text is not None else "").replace("|", "\\|")


def rulings_md(doc: dict, rulings: dict, date: str) -> str:
    tally: dict[str, int] = {}
    for k in all_keys(doc):
        r = rulings.get(k, {}).get("ruling", "unruled")
        tally[r] = tally.get(r, 0) + 1
    lines = ["# Rulings: seed validation, %s, %s (build %s)" % (doc["flavor"], doc["date"], doc["build"]), "",
             "Generated by `tools/seeds/seeds.py report` on %s from this bundle's `candidates.json` and "
             "`tools/seeds/%s_rulings.json`. Do not edit by hand." % (date, doc["flavor"]), "",
             "%d shipped ids checked; %d candidates, %d flags: %s." % (
                 doc["checked"], len(doc["candidates"]), len(doc["flags"]),
                 ", ".join("%d %s" % (n, r) for r, n in sorted(tally.items())) or "none"), ""]
    left = unruled(doc, rulings)
    if left:
        lines += ["## Unruled: %d" % len(left), ""] + ["- `%s`" % k for k in left] + [""]
    lines += ["## Candidates: %d" % len(doc["candidates"]), ""]
    if doc["candidates"]:
        lines += ["| Id | Name | Source | Notes | Ruling | Reason |", "| --- | --- | --- | --- | --- | --- |"]
        for c in doc["candidates"]:
            r = rulings.get(c["key"], {})
            lines.append("| `%d` | %s | %s | %s | %s | %s |" % (
                c["id"], _cell(c["name"]), c["source"], _cell("; ".join(c["notes"])),
                r.get("ruling", "**unruled**"), _cell(r.get("reason", ""))))
    else:
        lines.append("None.")
    lines += ["", "## Shipped-id flags: %d" % len(doc["flags"]), ""]
    if doc["flags"]:
        lines += ["| Kind | List | Id | Build name | Shipped as | Why | Ruling | Reason |",
                  "| --- | --- | --- | --- | --- | --- | --- | --- |"]
        for f in doc["flags"]:
            r = rulings.get(f["key"], {})
            lines.append("| %s | %s | `%d` | %s | %s | %s | %s | %s |" % (
                f["kind"], f["list"], f["id"], _cell(f["name"]), _cell(f["shipped"]), _cell(f["why"]),
                r.get("ruling", "**unruled**"), _cell(r.get("reason", ""))))
    else:
        lines.append("None.")
    info = doc.get("info") or {}
    lines += ["", "## Build facts", "",
              "Profession lines present: %s." % ", ".join(
                  "%s %s" % (k, "yes" if v else "no") for k, v in sorted((info.get("professionLines") or {}).items())),
              "Sources out of this flavor's scope: %s." % (", ".join(info.get("outOfScope") or ()) or "none"), ""]
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def _date(value: str) -> str:
    if not DATE_RE.match(value):
        raise argparse.ArgumentTypeError("a date is YYYY-MM-DD; got %r" % value)
    return value


def cmd_status(args) -> int:
    for flavor in ([args.flavor] if args.flavor else list(FLAVORS)):
        line = status_line(live_build(FLAVORS[flavor]["product"])["version"], bundles(args.research, flavor))
        print(line if args.flavor else "%s: %s" % (flavor, line))
    return 0


def cmd_derive(args) -> int:
    doc = derive_bundle(args.flavor, args.bundle, args.date, args.build, args.replay, args.cache_dir, args.root)
    left = unruled(doc, load_rulings(args.rulings or rulings_path(args.flavor)))
    for key in LIST_KEYS:
        log("  %-6s %3d shipped, %d candidates, %d flags" % (
            key, doc["counts"][key], sum(c["list"] == key for c in doc["candidates"]),
            sum(f["list"] == key for f in doc["flags"])))
    log("%s build %s: %d shipped ids checked, %d candidates, %d flags, %d unruled" % (
        args.flavor, doc["build"], doc["checked"], len(doc["candidates"]), len(doc["flags"]), len(left)))
    return 0


def _bundle_rulings(args) -> tuple[dict, Path]:
    doc = load_candidates(args.bundle)
    return doc, args.rulings or rulings_path(doc["flavor"])


def cmd_rule(args) -> int:
    doc, path = _bundle_rulings(args)
    known = set(all_keys(doc))
    rulings = load_rulings(path)
    todo = read_tsv(args.tsv)
    if not todo:
        fail("%s holds no ruling" % args.tsv)
    for key, ruling, reason in todo:
        if key not in known:
            fail("%s is not a candidate or flag in %s/candidates.json" % (key, args.bundle))
        set_ruling(rulings, key, ruling, reason)
    write_text(path, json.dumps(rulings, indent=2, sort_keys=True, ensure_ascii=False) + "\n", "\r\n")
    log("Recorded %d ruling(s) in %s" % (len(todo), path))
    return 0


def cmd_check(args) -> int:
    doc, path = _bundle_rulings(args)
    left = unruled(doc, load_rulings(path))
    if not left:
        print("OK: every candidate and flag in %s is ruled." % args.bundle.name)
        return 0
    rows = {r["key"]: r for r in doc["candidates"] + doc["flags"]}
    print("%d unruled:" % len(left))
    for key in left:
        print("  %s  %s [%s]" % (key, rows[key]["name"], rows[key].get("why") or "; ".join(rows[key]["notes"])))
    return 1


def cmd_report(args) -> int:
    doc, path = _bundle_rulings(args)
    write_text(args.bundle / "RULINGS.md", rulings_md(doc, load_rulings(path), args.date), "\r\n")
    log("Wrote %s" % (args.bundle / "RULINGS.md"))
    return 0


def cmd_apply(args) -> int:
    doc, path = _bundle_rulings(args)
    changes = apply_bundle(doc, load_rulings(path), args.root)
    for line in changes:
        log("  " + line)
    log("%d change(s) (%s, build %s, %s)" % (len(changes), doc["flavor"], doc["build"], args.date))
    return 0


def parse_args(argv):
    p = argparse.ArgumentParser(description="Re-validate Loot History's deconstruct seeds against a wago.tools build.",
                                epilog="The contract: docs/validate-seeds.md.")
    p.add_argument("--rulings", type=Path, default=None, help="the rulings file (default: per flavor)")
    p.add_argument("--root", type=Path, default=ROOT, help="the repo root the seed files are under")
    p.add_argument("--cache-dir", type=Path, default=CACHE, help="the per-build download cache")
    sub = p.add_subparsers(dest="command", required=True)
    s = sub.add_parser("status", help="is there a live build newer than the newest bundle?")
    s.add_argument("--flavor", choices=sorted(FLAVORS))
    s.add_argument("--research", type=Path, default=RESEARCH, help="where the bundles are")
    d = sub.add_parser("derive", help="fetch or replay the tables; write raw/, SOURCES.md, candidates.json")
    d.add_argument("--flavor", choices=sorted(FLAVORS), required=True)
    d.add_argument("--bundle", type=Path, required=True)
    d.add_argument("--date", type=_date, required=True)
    d.add_argument("--build", default=None, help="pin this build instead of the live one")
    d.add_argument("--replay", action="store_true", help="read only the bundle's raw/, no network")
    r = sub.add_parser("rule", help="record rulings (the only writer of the rulings file)")
    r.add_argument("--tsv", type=Path, required=True, help="key<TAB>ruling<TAB>reason lines")
    r.add_argument("--bundle", type=Path, required=True)
    for name, helptext in (("check", "exit 1 while anything is unruled"),
                           ("report", "write the bundle's RULINGS.md"),
                           ("apply", "write accepted ids and ruled removals into DECONSTRUCT_IDS")):
        c = sub.add_parser(name, help=helptext)
        c.add_argument("--bundle", type=Path, required=True)
        if name != "check":
            c.add_argument("--date", type=_date, required=True)
    args = p.parse_args(argv)
    if getattr(args, "replay", False) and args.build:
        p.error("--replay takes the build from the bundle; drop --build")
    return args


def main(argv=None) -> int:
    args = parse_args(argv)
    return {"status": cmd_status, "derive": cmd_derive, "rule": cmd_rule, "check": cmd_check,
            "report": cmd_report, "apply": cmd_apply}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
