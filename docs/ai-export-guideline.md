# Ka0s Loot History — AI Report Guideline

You are turning a **Ka0s Loot History** loot export into a **single, self-contained, interactive HTML
report**. You do **not** design or build the report from scratch — you **fill in a ready-made
template**. The template already carries the entire look, the charts, the History browser, the
filters, the tooltips, and the embedded logos; keeping it fixed is the whole point, so every report
comes out consistent and correct. This document is the authoritative spec — follow it exactly.

## Before you start — get the data onto disk, don't retype it

The export you were given (the two CSV blocks below) can be large. If you are working in a tool that
can run code, **do not reproduce the data by typing it into a heredoc or a file-write** — that wastes
minutes re-emitting data you already have. Instead, use the copy that is already on disk: an uploaded/
attached file, or the file your environment created for a large paste. If the user pasted the export
inline, ask them to attach it as a file. Then point the assembler (below) at that file.

## Fastest path — if you can run code

This repo ships a deterministic assembler that does the transcription, splice, and validation for you:

`tools/build_report.py` (<https://raw.githubusercontent.com/tusharsaxena/LootHistory/refs/heads/master/tools/build_report.py>)

1. Save the pasted export to a file (or use the attached file) — do **not** retype it.
2. Write your analysis cards (step 3 below) to `cards.html`.
3. Run: `python3 build_report.py --prompt export.txt --cards cards.html -o report.html`
   It self-extracts both CSVs, builds `H`, splices your cards, validates everything (including
   vendor value = Σ(v×qty)), and prints PASS/FAIL. Fix any reported issue and re-run.

If you **cannot** run code, follow the manual steps below.

## How to build the report (manual)

### 1 — Fetch the template verbatim

<https://raw.githubusercontent.com/tusharsaxena/LootHistory/refs/heads/master/docs/ai-export-template.html>

It is a **complete, working sample report** (~169 KB). **Download it in full** (e.g. `curl -o` /
`wget`) — a size-capped fetch silently truncates it, and you cannot reproduce a file you only partly
received. Reproduce it **exactly** — every byte of the `<head>`, the `<style>`, the engine `<script>`,
the embedded logo / Wowhead data-URIs, and all markup and class names — and change **only** the two
things in steps 2 and 3. Do not restyle, rename classes, add libraries, or touch the engine.

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
| `s`  | `source`        | UPPER: `KILL CONTAINER MAIL TRADE AH QUEST VENDOR DISENCHANT MPLUS OTHER` |
| `z`  | `zone`          | |
| `wh` | `wowheadLink`   | the ready-made URL |

You compute and lay out **nothing** here — just faithfully transcribe every row.

The sample rows in the template end each line with a trailing comma (valid JavaScript). If you emit
`H` yourself, either match that style or — better — emit a strict-JSON array (no trailing comma) so
your own `JSON.parse` validation passes cleanly (F4). When counting your analysis cards, match
`<div class="card` — grepping the bare token `card` also hits a CSS rule and over-counts (F5).

> **Value math (F1).** Every value/gold KPI aggregates as **Σ(v × qty)**, not Σ(v) — stacked rows
> (e.g. a potion ×40) multiply. The engine does this for you; if you validate your parse against the
> INSIGHTS **Vendor value**, remember to multiply by `qty` or you will chase a phantom gap.

### 3 — Hand-write the "What the data says" section — ***CRITICAL***

The template ships **sample** cards inside `<section id="llm">` **only to lock the look & feel**. This
is the one part of the report that is **NOT data-driven and NOT produced by the engine**: you **must**
delete the samples and write **at least 10 cards of your own**, from your own analysis of the data —
patterns, standout drops, rhythm, economy, crafting, character spotlights, keystone, warband flow,
recommendations. Keep each card's shape:

```html
<div class="card sp6"><div class="llm-tag">◆ Your Tag</div><h3>Your headline</h3><p>…</p></div>
```

Vary the ◆ tag, the size (`sp4` / `sp6` / `sp8`), the count, and the prose. In your prose, colour
character names with `style="color:var(--c-<class>)"` and render item names as links exactly like the
sample cards do:

```html
<a class="il qt-<quality>" href="<wowheadLink>" target="_blank" rel="noopener"
   data-tt="Name|quality|ilvl|bind|Type — Subtype|Ng Ns Nc|Source">Name</a>
```

No disclaimers.

## Output contract (non-negotiable)

- Output **only** the HTML — no prose before or after.
- **Fully self-contained**: all CSS and JS inline, **no external requests** (no CDNs, web fonts, remote
  images, `fetch`/XHR). System fonts + the embedded data-URIs only. The file must open straight from
  disk and publish as a Claude Artifact (whose CSP blocks every external host).
- **Do not restyle, rename classes, or alter the engine.** Your only freedom is the data (step 2) and
  the analysis prose (step 3).
- The `<title>` and hero `<h1>` come out as `Ka0s Loot History` with the realm + date range derived by
  the engine — leave that alone.

## The data you're given

Two CSV blocks follow this prompt (both for the user's selected Data Set — All Data or Current View):

- **HISTORY** — one row per drop, columns as tabled above. This becomes `H`.
- **INSIGHTS** — a pre-computed sectioned summary (`Summary`, `By Source`, `By Quality`, `By Item
  Type`, `By Bound Type`, `By Character`, `By Weekday`, `By Hour`, `By Keystone`, `Attribution
  Confidence`, `Top Zones`, `Top Items by Count`, `Top Items by Value`, `By Day`). The engine
  recomputes the charts from `H`, so you do **not** need INSIGHTS for them — use it as a fast reference
  while **writing** the analysis (step 3). It also carries a few things not present in HISTORY rows
  (e.g. attribution confidence and keystone levels) that are good narrative material.
