# AI Export — design (issue #12)

**Goal.** Add an **Export to AI** path beside the existing Export to CSV: one pasteable prompt that
makes any popular AI tool (Claude / ChatGPT / Gemini) render a **single self-contained HTML report**
of the user's loot — an interactive history browser, an Insights dashboard, and an AI-written
"What the data says" section — in a WoW-themed dark design. Closes #12 (the deferred v2 AI export;
the `Database:Export()` seam is already in place).

## Locked decisions

- **Report title is literal**: `Ka0s Loot History — <realm>, <date range>`. (Flavor left to the LLM
  section, not the title.)
- **LLM section = observations + suggestions** (patterns *and* gameplay/economy advice).
- **Dataset**: embed the **full** selected dataset; when the History CSV is very large, the prompt
  carries a short note suggesting *Current View* to trim. Honors the modal's **Data Set** (All Data /
  Current View) for **both** History and Insights.
- **Prompt = pure pointer.** The prompt embeds the two CSVs + a link to a design guideline committed
  in the repo; the AI fetches and follows it. The guideline (not the prompt) carries the rich design
  system and the embedded logo data-URIs, so the prompt stays small. *Tradeoff (flagged & accepted):*
  a tool with web access disabled produces a generic report; the help dialog states web access is
  required.
- **Guideline lives at** `docs/ai-export-guideline.md`; the prompt references its **raw** URL.
- **Logos**: real `loothistory.logo.jpg` downscaled to `media/logos/loothistory.logo.256.jpg`;
  Wowhead's transparent `media/logos/wowhead-logo.png`. Small data-URI copies of both are embedded in
  the **guideline** (not the addon), so generated reports stay self-contained. Repo originals untouched.

## Design language (summary; full spec lives in the guideline)

Void-dark WoW theme: near-black base with arcane-purple + Sin'dorei-crimson glow, gold hairline
accents. Display type = inscriptional serif via **system fonts only** (Palatino/Book Antiqua →
Georgia); body = system sans; data = system mono. **No web fonts, no CDNs, no external requests** —
required for a self-contained file (and a Claude artifact's CSP). **Quality-color is the organizing
system** (item names, quality chart, richest-drops); **class colors** for characters everywhere;
**bind-state colors** mirror the addon (`BrowserTable.lua`: Unbound grey, Soulbound green, Account
orange, Warbound blue, BoE off-white). Charts are **inline SVG/CSS only** — magnitude rankings use one
gold hue; only Quality and Character charts use semantic palettes, each directly labeled (passes the
dataviz CVD checks). Signature: the real logo in the hero + a WoW **item-tooltip on hover**.

**Layout discipline (hard rule).** The guideline MUST make the generated report enforce a single
content width and **zero horizontal overflow**: one max-width container with uniform padding shared by
every section; `box-sizing:border-box` globally; `min-width:0` on flex/grid children; `max-width:100%`
on media; long tokens wrap (`overflow-wrap:anywhere`); wide content (tables, charts) scrolls inside its
own `overflow-x:auto` wrapper, never the page; decorative glows are painted via `background-image`,
never an absolutely-positioned element that extends past its box. Acceptance: `documentElement.scrollWidth
=== clientWidth` and no panel's `scrollWidth` exceeds its `clientWidth`.

**Sections** (all filter-aware, labeled, tooltipped): Hero + KPI strip → Filter bar (Character /
Source / Quality / Type / Subtype / Zone / search / group) + sticky quick-nav → **Insights** (source,
bind-state, quality, item-type, character, top-zones, activity-over-time, GitHub-style weekday×hour
heatmap, richest drops, most-looted) → **History browser** (sortable / groupable / filterable table,
quality-colored item links w/ tooltips, class-colored chars, Type+Subtype, source badges, Wowhead
rocket link) → **What the data says** (≥10 AI-written cards) → Footer (CurseForge + GitHub CTAs,
Blizzard disclaimer). The reference mockup is reproduced from the sample export.

## Data contract (what the prompt embeds)

Two CSV blocks, produced by the existing serializers for the selected Data Set:

- **History CSV** — `NS.Export:CSV(records)`; columns: `ts,date,time,char,classFile,itemID,itemName,
  quality,qualityRaw,itemLevel,bound,sellPrice,sellPriceRaw,itemType,itemSubType,quantity,source,zone,
  wowheadLink`.
- **Insights CSV** — `NS.Export:InsightsCSV(stats)`; sectioned analytics dump (Summary, By Source, By
  Quality, By Item Type, By Bound Type, By Character, By Weekday, By Hour, By Keystone, Attribution
  Confidence, Top Zones, Top Items by Count/Value, By Day).

The guideline documents both schemas so the LLM maps columns → panels deterministically.

## Prompt shape (built by the addon)

```
<short framing: you are given a Ka0s Loot History export; produce ONE self-contained HTML file>
<design guideline — fetch & follow: RAW_URL>
<one-line: honor the data; realm/date-range come from the data; self-contained, no external requests>
<optional large-dataset note>

=== HISTORY (CSV) ===
<history csv for selected dataset>

=== INSIGHTS (CSV) ===
<insights csv for selected dataset>
```

`RAW_URL = https://raw.githubusercontent.com/tusharsaxena/LootHistory/master/docs/ai-export-guideline.md`

## Addon changes

- **`Export.lua`**
  - `E:AIPrompt(historyCSV, insightsCSV, opts)` → pure function returning the prompt string (framing +
    guideline URL + both CSV blocks + large-dataset note). Unit-tested.
  - **Modal**: activate the **Export to AI** button (was a disabled placeholder). On click it builds
    both CSVs for the selected Data Set and shows the prompt in the existing copy window (`ShowCopy`).
  - Add a small **help "?"** glyph beside the AI button → a help popup (own frame) explaining: what it
    does, that the AI tool needs **web access**, paste targets (Claude/ChatGPT/Gemini), and that the
    output is one self-contained HTML file (Claude can publish it as an artifact).
  - The modal config gains an `ai` provider pair (history + insights, each All Data / Current View) so
    the AI button works regardless of which tab opened the modal. Export-to-CSV stays tab-specific.
- **`Browser.lua` `B:OpenExport`** — always supply both History and Insights providers to the modal
  (CSV uses the active tab's; AI uses both), preserving the shared filter for Current View.

## New repo artifacts

- `docs/ai-export-guideline.md` — the design system + section spec + data-contract + embedded logo
  data-URIs. Single source of truth the prompt points to.
- `media/logos/loothistory.logo.256.jpg`, `media/logos/wowhead-logo.png` — already added.

## Docs / tests / packaging

- **Tests** (`tests/test_export.lua`): `AIPrompt` includes the guideline URL, both CSV section markers,
  the embedded History + Insights CSV content, and the large-dataset note when over threshold.
- **README**: new "Export to AI" subsection under Usage (how to use + example link — *user to provide
  the example link later*).
- **Docs sync**: ARCHITECTURE.md (Export module note), regenerate `docs/test-cases.md` + README `tests`
  badge count in the same change (per CLAUDE.md).

## Standards check

Export registers no bus message (called directly) — unchanged. `AIPrompt` is a pure serializer like
`CSV`/`InsightsCSV`. No new saved-variables, no Schema change (the AI export has no persisted setting).
Help popup is a plain frame reusing the Browser skin. No `WOW_PROJECT_ID` branching. No apparent
deviation from the Ka0s Standard; flag if any surfaces during build.

## Non-goals (YAGNI)

- No in-game HTML rendering or preview; the addon only produces the prompt text.
- No network calls from the addon; no persisting the last prompt.
- No new slash command (the modal is the entry point). Revisit only if requested.
