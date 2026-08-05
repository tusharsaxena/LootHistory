# 01 — Current state

**Addon:** Ka0s Loot History (`LootHistory`), version **1.2.0** (`LootHistory.toc:5`).
**Audited against:** **Ka0s WoW Addon Standard v2.21.0 (2026-08-04)** — the version stamped at
`standards/STANDARDS.md:1` of the copy fetched for this run.
**Run date:** 2026-08-05. **Deviation prefix:** `LH-` (assigned 2026-07-12; reused).
**Prior runs:** `docs/audits/2026-07-12/`, `docs/audits/2026-07-18/`, `docs/audits/2026-08-04/`
(the last audited against v2.17.1, i.e. **four minor versions ago**; v2.18–v2.21 introduced the
`automated-tests` section, retired `docs/complexity.md`, added the complexity-disposition shelf
life and the **release gate**).

## Provenance of the rules

Fetched verbatim with `curl -fsSL` into a scratch directory and read from disk — no summarizer in
the path:

- `AUDIT.md` (the playbook) — 158 lines.
- `standards/STANDARDS.md` (the index) — 141 lines, front matter `v2.21.0, 2026-08-04`.
- **All 25 section files** discovered by following the index's Sections list and fetched from
  `standards/standards/<name>.md`: `layout`, `toc-file`, `library-stack`, `architecture`,
  `savedvariables`, `options-ui`, `standalone-windows`, `preview-mode`, `slash-commands`,
  `localization`, `events-frames-taint`, `public-api`, `compat`, `debug-logging`, `packaging`,
  `lint`, `testing`, `performance`, `automated-tests`, `documentation`, `audit-review-history`,
  `versioning-git`, `naming-cheatsheet`, `anti-patterns`, `open-evolutions`.

No rule in this bundle is reconstructed from memory. Sections are cited as `filename-§N`; a whole
section by its bare filename. The retired global `§N.M` scheme is not used here.

## Scope constraint on this run

This run was invoked **single-repo**: reading, writing or executing anything inside a sibling repo
under `…/GIT/` was forbidden. One playbook step is therefore **not run** rather than passed — the
standalone `diff -r ../LibKa0s/LibKa0s libs/LibKa0s` and `diff -r ../LibKa0s/testkit tests/_kit`
(`AUDIT.md` step 6). What *was* observed is the addon's own in-suite equivalent
(`tests/test_vendor_sync.lua`), whose two cases ran green — with the caveat recorded as **LH-40**
that those cases also report green when they cannot look. See `03_EVIDENCE.md`.

---

## Layout (`layout`)

The modular layout is present and correct: `core/`, `defaults/`, `locales/`, `modules/`,
`settings/`, plus `libs/`, `media/`, `tests/`, `docs/`. No source is loose at the root
(`LootHistory.toc:16-60`). Folder casing is lowercase throughout; Lua files are PascalCase.

File sizes (`wc -l`), against `layout-§1`'s 1500 cap and 1000–1500 on-notice band:

| File | LOC | Band |
|---|---|---|
| `modules/Browser.lua` | 1372 | on notice |
| `modules/Analytics.lua` | 1180 | on notice |
| `modules/BrowserTable.lua` | 1097 | on notice |
| `core/Database.lua` | 794 | — |
| `settings/Panel.lua` | 801 | — |
| everything else | ≤ 481 | — |

**No file is over the cap.** Three sit in the on-notice band, and all three are dispositioned in
`docs/automated-tests/RESULTS.md`'s band table.

`media/` uses typed subfolders only — `media/fonts/`, `media/logos/`, `media/screenshots/`
(`layout-§3`). The logo ships as `.tga` (runtime) beside `.jpg` (source), as required.

## TOC (`toc-file`)

`LootHistory.toc:1-14` carries the metadata block in **exactly** the `toc-file-§1` field order:
`Interface` → `Title` → `Notes` → `Author` → `Version` → `IconTexture` → `SavedVariables` →
`OptionalDeps` → `DefaultState` → `Category-enUS` → `X-License` → `X-Standard` →
`X-Curse-Project-ID`. No blank lines inside the block; no hard `## Dependencies`.

- Single Retail Interface `120007` (`:1`), matching the README `[wow]` badge `Midnight_12.0.7`
  (`README.md:3`) — `toc-file-§3` lockstep holds.
- `## X-License: MIT` (`:12`), `## X-Standard:` present (`:13`), `## X-Curse-Project-ID: 1607560`
  (`:14`) with no Wago/WoWI lines (correct — not listed there).
- **`## SavedVariables: LootHistoryDB`** (`:7`) — **one** global where `toc-file-§2` requires two.
  This is the perf cluster's TOC symptom (**LH-21**).
- File listing uses `#` section headers in the `toc-file-§5` order Libraries → Locales → Core →
  Defaults → Modules → Settings (`:16,32,35,45,48,58`).
- `libs\LibKa0s\LibKa0s.xml` is listed **once**, as the single aggregate, after Ace3 (`:27`) — no
  individual `LibKa0s` `.lua` line anywhere. `toc-file-§4` / anti-pattern #48 clear on this point.

## Library stack (`library-stack`) and the vendored payload

`libs/` holds LibStub, CallbackHandler-1.0, AceAddon/AceEvent/AceTimer/AceConsole/AceDB/AceGUI-3.0,
LibSharedMedia-3.0, LibDataBroker-1.1, LibDBIcon-1.0 and `LibKa0s/`, all committed. `.pkgmeta`
carries **no `externals:`** and says so in a comment (`.pkgmeta:3-5`).

`libs/LibKa0s/` holds the whole ship folder as `git ls-files` reports it: `Core.lua`,
`DebugLog.lua`, `Options.lua`, `OptionsScroll.lua`, `OptionsWidgets.lua`, `Perf.lua`,
`PerfPanel.lua`, `Slash.lua`, `LibKa0s.xml`, `LICENSE` — **including both files of the multi-file
Options major and both of the Perf major**, i.e. the majors this addon does not wire are vendored
anyway, which is what `library-stack-§7` and anti-pattern #48 ask for. The harness lives at
`tests/_kit/` and **not** under `libs/` (`testing-§1`).

## The LibKa0s seams (what the addon owns)

There is **no** `modules/DebugLog.lua`, no widget-maker file, no addon-local dispatcher and no
hand-written test framework in this repo — because those are library modules. What the addon owns
is a descriptor plus a degradation stub per module, in four setup files. **Anti-pattern #47 is
clear.**

| Module | Seam file | Resolution | Descriptor | Degradation stub |
|---|---|---|---|---|
| `LibKa0s-Core-1.0` | `core/CoreSetup.lua` | `:32` silent `LibStub(..., true)` | `:97` `lib:New{ prefix = NS.PREFIX }` | `:41-84` — five members, announced once |
| `LibKa0s-DebugLog-1.0` | `core/DebugLogSetup.lua` | `:24` | `:74-131` incl. `applySkin`, deliberately **no** `makeCloseButton` (`:120-131`) | `:26-72` — 18 members |
| `LibKa0s-Slash-1.0` | `settings/Slash.lua` | `:103` | `:196-217` | `:129-162` |
| `LibKa0s-Options-1.0` | `settings/OptionsSetup.lua` | `:37` | `:68-116` | `:39-66` — load-completing |
| `LibKa0s-Perf-1.0` | **absent** | — | — | — |

- The **shared cause clause** `NS.LIBKA0S_MISSING` is published on **both** paths
  (`core/CoreSetup.lua:38-39`, deliberately outside the `if not lib` branch), and every later seam
  appends its own consequence to it.
- The Options stub is **load-completing rather than member-answering** (`settings/OptionsSetup.lua:44-64`)
  — publishing `LSMValues` real enough for file load and no-opping the rest. That is
  `options-ui-§1`'s documented exception and is **not** flagged.
- Stub coverage was measured by grepping the call sites (see `03_EVIDENCE.md`): every member the
  **shipped** code reaches on Core, DebugLog, Slash and Options is answered by that module's stub.
  The one asymmetry is test-visible only and is recorded as **LH-39**.
- `LibKa0s-Perf-1.0` is vendored and loaded by the runner but **never adopted** — no
  `core/PerfSetup.lua`, no `NS.Perf`, no stub. Recorded in the repo as a deliberate `wont-do`
  (`docs/pending/LEDGER.md`, `LIBKA0S-17`) with substantive reasoning.

## Architecture (`architecture`)

- Every source file opens `local addonName, NS = ...`; no `_G[addonName]` table.
- AceAddon registration at `core/LootHistory.lua`, with the **AceConsole reclaim**
  (`architecture-§2` / anti-pattern #36) wired through `NS.Util.print`, which `core/CoreSetup.lua:106-107`
  publishes on both paths.
- Closed message bus, three `Ka0s_LootHistory_*` messages, documented in `docs/ARCHITECTURE.md:189-216`.
  Receivers take private targets from `NS.NewBusTarget()` (`core/LootHistory.lua:20`) — but three of
  the five sites fall back to the shared bus with `or bus` (**LH-35**).
- Schema-as-single-source: `settings/Schema.lua` drives AceDB defaults, panel widgets and the CLI;
  every mutation routes through `Schema:Set`. The boot validation exists but its condition is
  unreachable (**LH-43**).

## SavedVariables (`savedvariables`)

`defaults/Global.lua` is the defaults file; `schemaVersion` is declared (`:10`) and
`core/Database.lua` ships a migration runner. Storage is account-wide `global` by design; there is
no profile tree, which `layout-§1` sanctions. Two defaults problems stand: the schema restates six
literals the defaults file already owns (**LH-28**), and the AH priority cascade is declared twice
and has **drifted** (**LH-34**).

## Options UI, standalone windows, slash, debug, compat, locales

- Options: three subcategories plus a landing page, all created with `defaultsButton = true`; the
  always-shown scrollbar, the two-column flow and the lazy body are the library's. The off-screen
  rebuild flag `ctx.dirty` is written and cleared but never read (**LH-27**).
- Standalone window: non-secure `CreateFrame`, `UISpecialFrames`, pooled rows, persisted geometry.
  The edge values match the normative table but are restated rather than delegated (**LH-30**).
- Slash: AceConsole registration for `lh` / `loothistory`, positional-triple `NS.COMMANDS`
  (`settings/Schema.lua:213-245`), cyan `[LH]` tag through `NS.PREFIX`. Fourteen verbs; the
  reserved **`perf`** is missing (**LH-22**).
- Debug: on-screen console from the library, session-only flag, never the chat frame.
- Compat: one `core/Compat.lua` (481 lines) owning every deprecated / varying API; no
  `WOW_PROJECT_ID` branching anywhere.
- Locales: `locales/enUS.lua:5` sets the metatable fallback returning the key. The addon ships
  English-only with the seam kept — an explicit, commented scope decision. US-English spelling is
  clean across authored text (`localization-§5`).

## Testing and lint

- `tests/_kit/` vendored (framework, loader, mock_base, README, `run-automated-tests.sh`),
  `tests/wow_mock.lua` a thin extender, one suite per module, 19 suites.
- `tests/run.lua:30` derives the addon's load list from the TOC via `Loader.tocFiles`, and
  `:17-26` spells out every `LibKa0s.xml` file in XML order. The three derivation assertions
  `testing-§9` requires are still absent (**LH-29**).
- `docs/test-cases.md` is generated by `--list`; the README badge reads `579/579`
  (`README.md:7`) and agrees with the run.
- `.luacheckrc` excludes `libs/`, `docs/audits/`, `docs/reviews/`, `_dev/`, `tests/`; `luacheck .`
  is 0/0 over 23 files.

## Performance (`performance`)

**Un-adopted, wholesale.** No `core/PerfSetup.lua`, no `NS.Perf`, no `LootHistoryPerfDB`, no
`debugprofilestop` in `.luacheckrc`, no `perf` verb, no suspend/resume contract, no `tests/perf.lua`,
no `docs/performance.md`. `docs/perf-runs/README.md` **does** now exist (it did not at the last
audit) and states plainly that nothing has been captured. The whole cluster is **LH-20 … LH-26**,
with the head decision recorded as an accepted `wont-do` at `docs/pending/LEDGER.md` `LIBKA0S-17`.

## Automated-test records (`automated-tests`) — new since the last audit

Adopted, and adopted well. Three frozen bundles under `docs/automated-tests/` (`20260804-182216`,
`20260804-220017`, `20260804-233322`), each with `manifest.json`, `ANALYSIS.md`, `lint.txt`,
`tests.txt`, `test-cases.md`, `complexity.txt`. `RESULTS.md` is a single overwritten file with one
row per run, both totals and averages, and a watch list carried as prose (`None.` — a result) plus
a band table with dispositions. The runner is the vendored `tests/_kit/run-automated-tests.sh`,
mode `0755`, and `.gitattributes:36` carries `*.sh text eol=lf`. **`docs/complexity.md` does not
exist** — correctly retired, and `docs/testing.md:180-181` says so.

Two gaps: the **release gate** introduced in v2.21.0 is stated nowhere (**LH-36**), and the band
table's disposition cites a deviation ID that does not track that file (**LH-37**).

## The root doc set and `docs/` (`documentation`)

Root holds exactly `README.md`, `CLAUDE.md`, `DEPENDENCIES.md` and `LICENSE` — no fourth doc, no
`TODO.md`, no `docs/agent-context.md` anywhere in the repo (anti-patterns #27, #49 clear).

- **`README.md`** — player-facing, canonical order held for every required section: H1 (`:1`),
  the five badges in the exact canonical order and templates including the underscore-spaced
  standard badge (`:3-7`), logo (`:9`), description, `## What's new in 1.2.0` (`:36`) immediately
  above `## Screenshots` (`:43`) and matching the top Version History row, `## Usage` with both
  subsections (`:63,69,89`), `## How attribution works` (`:125`), `## FAQ` (`:131`),
  `## Troubleshooting` (`:148`), `## Issues and feature requests` (`:168`), `## Version History`
  (`:172`). No `## Testing` section. Two extra domain sections are interposed
  (`## Auction-house pricing` `:117`, `## Bundled libraries` `:164`) — recorded as an observation,
  not a deviation.
- **`CLAUDE.md`** — carries the H1, the adherence line (`:9`) and
  `## Standards compliance (read first)` (`:11`), so the three-place standards reference is
  complete. It is **not a stub**, though (**LH-38**).
- **`DEPENDENCIES.md`** — 144 lines, split runtime / development / release-only, `pipx` for the
  PEP 668 case, per-tool verification commands, and a closing "commands this repo is verified
  with". Compliant with `documentation-§7`.
- **`docs/` trio** — `ARCHITECTURE.md` (all eight required sections present), `testing.md`,
  `smoke-tests.md`. All three exist.
- **The five required topic-detail docs** — `test-cases.md` ✅, `performance.md` **❌ missing**,
  `perf-runs/README.md` ✅, `automated-tests/README.md` ✅, `automated-tests/RESULTS.md` ✅.
  Four of five (**LH-25**).

## The three-place standards reference (`documentation-§6`)

| # | Place | State |
|---|---|---|
| 1 | TOC `## X-Standard:` | ✅ `LootHistory.toc:13` |
| 2 | README standard badge | ✅ `README.md:6`, canonical template, underscore spacing |
| 3 | `CLAUDE.md` → `## Standards compliance (read first)` | ✅ `CLAUDE.md:11-22`, with the stop-and-flag rule and the deviation-vs-standard-change choice |

**All three present.** Anti-pattern #34 clear.

## Audit / review history and versioning

`docs/audits/` and `docs/reviews/` both carry dated, frozen bundles (`audit-review-history`).
Version `1.2.0` is semver; the repo works trunk-based; the working tree at the time of this run
carried only the untracked `docs/reviews/2026-08-05/` bundle plus this one.
