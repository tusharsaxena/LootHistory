# Ka0s Loot History — AI Report Guideline

*Guideline v1.1.0 rev6 · 2026-07-18*

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

1. **Get the export onto disk without retyping it.** **First check whether the paste is already a file** —
   many environments auto-store a large paste or an upload (an uploads directory, or a path the tool hands
   you: ChatGPT / Gemini / Claude Desktop attachments, Claude Code's auto-filed paste). If it is, point
   `--prompt` at **that file directly and write nothing** — this is by far the fastest path, and it skips
   all re-emission. **Only if the export truly is not on disk** (inline chat text your environment did not
   file), write it **once, verbatim** — never regenerate the rows. In that write-once case you only need
   the **HISTORY block plus the INSIGHTS `Summary` rows**: the assembler cross-checks nothing else, so do
   **not** re-type the rest of INSIGHTS (`By Source`, `By Quality`, `Top Items…`, `By Day`, …) — it's a
   card-writing reference you already have in context, and re-emitting it is wasted work.
2. Download `build_report.py` (the URL above) into that working directory.
3. Write your analysis cards (see **Write the analysis cards** below) to `cards.html`.
4. Run:
   `python3 build_report.py --prompt export.txt --cards cards.html -o report.html`
   It self-extracts the `=== HISTORY (CSV) ===` block and, if present, the `=== INSIGHTS (CSV) ===` block
   (INSIGHTS is optional — it only drives the Summary cross-check; a HISTORY-only file still builds a full
   report and PASSes), builds `H`, downloads the template in full, splices your cards,
   and validates everything — record count, distinct items, characters, epic+, best iLvl, richest drop,
   busiest day, **value = Σ(val×qty)**, ≥10 cards, no external requests, no literal `\u`/`\x`
   escapes in your cards, and a byte-for-byte head/engine/footer match against the template. It prints
   **PASS/FAIL** and exits non-zero on any issue. Fix what it reports and re-run.
   (In a repo checkout the script is at `tools/build_report.py`; `--template PATH` accepts a local copy.)

Then output the report per the **Output contract** below.

### Run it once, and trust it — do not re-verify

The assembler is **first-party, deterministic, and unit-tested**, and its **PASS is the complete and only
validation you need.** It already reconciles every Summary figure (records, distinct items, characters,
epic+, best iLvl, richest drop, busiest day, value = Σ(val×qty)), counts your cards, and scans for
external requests, literal escapes, and template sample-name leaks — and prints an itemized checklist of
each.

- **Trust the inputs.** HISTORY and INSIGHTS were computed by the addon and are authoritative — do not
  second-guess or re-derive them.
- **Do NOT reconcile the data yourself — not before running the tool, not after.** No independent Python
  recount of the Summary figures, no post-run self-containment re-scan, no "cheap insurance" double-check.
  The tool already does every one of these; repeating them by hand is **forbidden** and adds nothing but
  wasted time.
- **A green PASS is done.** Cite its checklist and move on. Only a **FAIL** warrants action — fix exactly
  what it names and re-run.

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
`\u25c6` (the assembler rejects those). Vary the ◆ tag, the count, and the prose. The Section III grid is
a **fixed 2-up layout** — every card is exactly half-width and any `sp4` / `sp6` / `sp8` class is ignored,
so don't try to size cards. In your prose, colour character names with `style="color:var(--c-<class>)"`
and render item names exactly like the sample cards do — a quality-coloured `.il` **span** that carries
the tooltip in `data-tt` (no link, no `href`; the pipe order is
`name|quality|ilvl|bind|Type — Subtype|sell|source`):

```html
<span class="il qt-<quality>" data-tt="Name|quality|ilvl|bind|Type — Subtype|Ng Ns Nc|Source">Name</span>
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
  while **writing** the analysis cards. The assembler reads only the **`Summary`** section (for its
  cross-check); every other INSIGHTS section is purely a reading aid — never re-type them into the export
  file (see step 1).

> **Three price types.** Each row carries **`v`** (vendor sell price — a guaranteed floor),
> **`a`** (auction price snapshot at loot — may be `null`), and **`val`** (the derived value:
> `a` if present, else `v`). **Use `val` for every worth/gold KPI and ranking** — aggregate as
> **Σ(val × qty)**, not Σ(val). The engine does this for you; the assembler cross-checks the
> INSIGHTS **Value** row against Σ(val×qty). Reserve `v` for "what a vendor pays" callouts and
> `a` for explicit market-price commentary.

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
{d, t, c, cl, id, n, q, qr, il, b, v, a, val, ty, st, qty, s, z, wh, src}
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
| `v`  | `vendorPriceRaw`  | copper (number) — the engine does **all** money math |
| `a`  | `auctionPriceRaw` | copper (number) or `null` — AH price snapshot at loot; `null` when no addon had one |
| `val`| `valueRaw`      | copper (number) — **the value to use for worth**: auction price if present, else vendor |
| `ty` | `itemType`      | |
| `st` | `itemSubType`   | |
| `qty`| `quantity`      | number |
| `s`  | `source`        | UPPER: `KILL CONTAINER MAIL TRADE AH QUEST VENDOR DISENCHANT MPLUS OTHER` (a blank source → `OTHER`) |
| `z`  | `zone`          | |
| `wh` | `wowheadLink`   | the ready-made URL |
| `src`| `priceSource`   | e.g. `"tsm:dbmarket"`, `"auctionator"`, `"oribos:market"`; blank when no AH price |

You compute and lay out **nothing** here — just faithfully transcribe every row.

The sample rows in the template end each line with a trailing comma (valid JavaScript). If you emit `H`
yourself, either match that style or — better — emit a strict-JSON array (no trailing comma) so your own
`JSON.parse` validation passes cleanly. When counting your analysis cards, match `<div class="card` —
grepping the bare token `card` also hits a CSS rule and over-counts.

### 3 — Write the analysis cards

Same as **Write the analysis cards** above — delete the sample cards and write ≥10 of your own. Then
follow the **Output contract** above.
