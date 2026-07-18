# Ka0s Loot History — AI Report Guideline

*Guideline v3.2 · 2026-07-18*

You are turning a **Ka0s Loot History** loot export into a **single, self-contained, interactive HTML
report**. You do **not** design or build the report from scratch — you **fill in a ready-made
template**. The template already carries the entire look, the charts, the History browser, the
filters, the tooltips, and the embedded logos; keeping it fixed is the whole point, so every report
comes out consistent and correct. This document is the authoritative spec — follow it exactly.

## ⚠️ If you can run code, you MUST use the assembler — do not hand-build

If you are in **any** environment that can run code — Claude Code, Claude Desktop with code execution,
ChatGPT code interpreter, or any Python sandbox — you **must** build the report with the shipped
assembler `tools/build_report.py`. In that mode:

- **Do NOT** hand-transcribe the CSV into the `H` array.
- **Do NOT** write your own build / splice / validation scripts.
- **Do NOT** `web_fetch` the template (it is ~169 KB and a size-capped fetch silently truncates it).
- **Do NOT** retype the dataset into a heredoc or a file-write.

One command does the transcription, the full template download, the splice, and all validation. Every
one of those steps by hand is slow and error-prone; the tool is deterministic and tested. Only if you
**cannot** run code at all, use the manual **Fallback** at the end of this document.

## Run the assembler (the required path when you can run code)

`tools/build_report.py`
(<https://raw.githubusercontent.com/tusharsaxena/LootHistory/refs/heads/master/tools/build_report.py>)

1. **Get the export onto disk without retyping it.** Best: have the user **attach/upload the export as a
   file** (ChatGPT / Gemini / Claude Desktop), or paste it in **Claude Code**, which auto-stores a large
   paste as a file. Use that file directly. If you were only handed the export as inline chat text and
   your environment did not file it, write it to disk **once, verbatim** — never regenerate the rows.
2. Download `build_report.py` (the URL above) into that working directory.
3. Write your analysis cards (see **Write the analysis cards** below) to `cards.html`.
4. Run:
   `python3 build_report.py --prompt export.txt --cards cards.html -o report.html`
   It self-extracts both the `=== HISTORY (CSV) ===` and `=== INSIGHTS (CSV) ===` blocks (so you never
   split, retype, or count the data), builds `H`, downloads the template in full, splices your cards,
   and validates everything — record count, distinct items, characters, epic+, best iLvl, richest drop,
   busiest day, **vendor value = Σ(v×qty)**, ≥10 cards, no external requests, no literal `\u`/`\x`
   escapes in your cards, and a byte-for-byte head/engine/footer match against the template. It prints
   **PASS/FAIL** and exits non-zero on any issue. Fix what it reports and re-run.
   (In a repo checkout the script is at `tools/build_report.py`; `--template PATH` accepts a local copy.)

Then output the report per the **Output contract** below.

The tool's **PASS** already reconciles every Summary figure (records, distinct items, characters, epic+,
best iLvl, richest drop, busiest day, vendor value = Σ(v×qty)), counts your cards, and scans for external
requests, literal escapes, and template sample-name leaks — and it prints an itemized checklist of each.
You do **not** need to re-run those checks by hand; trust the checklist and cite it.

## Write the analysis cards — ***CRITICAL*** (both paths)

This is the **one part of the report that is NOT data-driven and NOT produced by the engine** — the tool
cannot write it for you. The template ships **sample** cards inside `<section id="llm">` **only to lock
the look & feel**. You **must** delete the samples and write **at least 10 cards of your own**, from your
own analysis of the data — patterns, standout drops, rhythm, economy, crafting, character spotlights,
keystone, warband flow, recommendations. Keep each card's shape:

```html
<div class="card sp6"><div class="llm-tag">◆ Your Tag</div><h3>Your headline</h3><p>…</p></div>
```

Write the real glyph (`◆`, accented names like `Chopstîx`) directly — **never** a literal escape such as
`\u25c6` (the assembler rejects those). Vary the ◆ tag, the size (`sp4` / `sp6` / `sp8`), the count, and
the prose. In your prose, colour character names with `style="color:var(--c-<class>)"` and render item
names as links exactly like the sample cards do:

```html
<a class="il qt-<quality>" href="<wowheadLink>" target="_blank" rel="noopener"
   data-tt="Name|quality|ilvl|bind|Type — Subtype|Ng Ns Nc|Source">Name</a>
```

No disclaimers. Use the **INSIGHTS** block as a fast reference while writing (it also carries attribution
confidence and keystone levels that are good narrative material and are not in the HISTORY rows).

## Output contract (non-negotiable)

- Output **only** the HTML — no prose before or after.
- **Fully self-contained**: all CSS and JS inline, **no external requests** (no CDNs, web fonts, remote
  images, `fetch`/XHR). System fonts + the embedded data-URIs only. The file must open straight from
  disk and publish as a Claude Artifact (whose CSP blocks every external host).
- **Do not restyle, rename classes, or alter the engine.** Your only freedom is the data and the
  analysis prose.
- The `<title>` and hero `<h1>` come out as `Ka0s Loot History` with the realm + date range derived by
  the engine — leave that alone. (The engine derives the title, realm and date range at runtime from the
  data; do not hand-edit them.) The static `<title>` shipped in the template is only a placeholder — the
  engine overwrites the title, realm, and date range at load from the data. Never hand-edit it, even if
  the placeholder's date range looks wrong.

## The data you're given

Two CSV blocks follow the prompt (both for the user's selected Data Set — All Data or Current View):

- **HISTORY** — one row per drop. This becomes `H`.
- **INSIGHTS** — a pre-computed sectioned summary (`Summary`, `By Source`, `By Quality`, `By Item
  Type`, `By Bound Type`, `By Character`, `By Weekday`, `By Hour`, `By Keystone`, `Attribution
  Confidence`, `Top Zones`, `Top Items by Count`, `Top Items by Value`, `By Day`). The engine
  recomputes the charts from `H`, so you do **not** need INSIGHTS for them — use it as a fast reference
  while **writing** the analysis cards.

> **Value math.** Every value/gold KPI aggregates as **Σ(v × qty)**, not Σ(v) — stacked rows (e.g. a
> potion ×40) multiply. The engine does this for you; if you validate a parse against the INSIGHTS
> **Vendor value**, remember to multiply by `qty` or you will chase a phantom gap. (The assembler
> already checks this.)

---

## Fallback — ONLY if you cannot run code at all

Everything above is the required path. Use the steps below **only** in a chat-only tool with no code
execution. They reproduce, by hand, exactly what `build_report.py` does.

### 1 — Fetch the template verbatim

<https://raw.githubusercontent.com/tusharsaxena/LootHistory/refs/heads/master/docs/ai-export-template.html>

It is a **complete, working sample report** (~169 KB). **NEVER `web_fetch` it** — a size-capped fetch
silently truncates it, and you cannot reproduce a file you only partly received. Download it in full with
`curl -o` / `wget`. Reproduce it **exactly** — every byte of the `<head>`, the `<style>`, the engine
`<script>`, the embedded logo / Wowhead data-URIs, and all markup and class names — and change **only**
the two things in steps 2 and 3. Do not restyle, rename classes, add libraries, or touch the engine.

### 2 — Replace the sample data (`REALM` + `H`)

Near the end of the file is the data block:

```js
const REALM = "Frostmourne";
const H = [ /* …sample rows… */ ];
```

Replace `REALM` with the export's realm, and `H` with **one object per HISTORY row**. The engine
renders the title, KPIs, **every** Insights chart, the facet filters, and the History table from `H`
alone, so the **keys must match exactly**:

```js
{d, t, c, cl, id, n, q, qr, il, b, v, ty, st, qty, s, z, wh}
```

Map them from the **HISTORY** CSV columns:

| key  | from CSV        | notes |
|------|-----------------|-------|
| `d`  | `date`          | e.g. `"12-Jul-2026"` |
| `t`  | `time`          | 24-hour `"HH:MM"`, e.g. `"20:37"` |
| `c`  | `char`          | **name part only** — strip `-Realm`; take `REALM` from the realm part |
| `cl` | `classFile`     | UPPER: `WARRIOR PALADIN DEATHKNIGHT SHAMAN WARLOCK MONK DRUID HUNTER MAGE PRIEST ROGUE DEMONHUNTER EVOKER` |
| `id` | `itemID`        | number |
| `n`  | `itemName`      | |
| `q`  | `quality`       | label: `Poor Common Uncommon Rare Epic Legendary Heirloom` |
| `qr` | `qualityRaw`    | number 0–7 |
| `il` | `itemLevel`     | number, or `null` if blank |
| `b`  | `bound`         | label: `Not Bound`, `Bind on Equip`, `Bind on Pickup`, `Account Bound`, `Warbound` |
| `v`  | `sellPriceRaw`  | copper (number) — the engine does **all** money math |
| `ty` | `itemType`      | |
| `st` | `itemSubType`   | |
| `qty`| `quantity`      | number |
| `s`  | `source`        | UPPER: `KILL CONTAINER MAIL TRADE AH QUEST VENDOR DISENCHANT MPLUS OTHER` (a blank source → `OTHER`) |
| `z`  | `zone`          | |
| `wh` | `wowheadLink`   | the ready-made URL |

You compute and lay out **nothing** here — just faithfully transcribe every row.

The sample rows in the template end each line with a trailing comma (valid JavaScript). If you emit `H`
yourself, either match that style or — better — emit a strict-JSON array (no trailing comma) so your own
`JSON.parse` validation passes cleanly. When counting your analysis cards, match `<div class="card` —
grepping the bare token `card` also hits a CSS rule and over-counts.

### 3 — Write the analysis cards

Same as **Write the analysis cards** above — delete the sample cards and write ≥10 of your own. Then
follow the **Output contract** above.
