# 01 — Current state

**Run:** 2026-09-07. **Addon:** Ka0s Loot History (`LootHistory`), version `1.2.0` (`LootHistory.toc:5`).
**Audited against:** **Ka0s WoW Addon Standard v2.38.0 (2026-09-02)** — resolved by `curl` from
`https://raw.githubusercontent.com/tusharsaxena/WowAddonStandards/master/standards/STANDARDS.md`,
plus all **26** section files its Sections list links (`standards/standards/*.md`), plus
`AUDIT.md` and `standards/ADDONS.md`. Rule set: the **addon** set — this repo ships a `.toc`.
**Prefix:** `LH-` (assigned 2026-07-12, reused). New IDs this run start at **LH-45** (LH-01…LH-44 are spent).

Head commit `6d3c2de` (Merge branch `feat/settings-revamp-v2`). Working tree clean apart from an
unrelated untracked `docs/reviews/2026-09-07/` produced by a concurrent review run; this audit
touched nothing but the folder it sits in.

---

## Layout, TOC and libraries

Modular layout exactly as `layout-§1`: `core/ defaults/ locales/ modules/ settings/ tests/ docs/ libs/ media/`.
Twenty-eight linted source files. Casing is `layout-§2`-conformant.

`LootHistory.toc` carries every mandated field in order (`toc-file-§1`): `Interface: 120007`,
`Title`, `Notes`, `Author`, `Version`, `IconTexture`, `SavedVariables: LootHistoryDB`, `OptionalDeps`,
`DefaultState`, `Category-enUS: Misc`, `X-License: MIT`, `X-Standard`, `X-Curse-Project-ID: 1607560`.
Section comments are the canonical `# Libraries → # Locales → # Core → # Defaults → # Modules → # Settings`.

`toc-file-§5` **position annotations are present and specific**, not "order matters" boilerplate:
`:37-39` (ItemSetup publishes `NS.Item`, whose `QualityLabel` `core/Constants.lua` calls at file
load), `:41-42` (MediaSetup publishes `NS.MediaFont`, read by `Constants` to resolve `FONT_MONO`),
`:71-74` (OptionsSetup before Schema, because `Schema` calls `NS.Options.MasterControls` at file
load). Conventional positions are marked as such (`:34-35`, `:49`, `:52`).

Vendored libraries load first; `libs\LibKa0s\LibKa0s.xml` is listed **once** at `:27`, after Ace3 —
no individual module `.lua` lines (`toc-file-§4/§5`, anti-pattern #48).

## Shared subsystems — descriptors and stubs, not hand-rolls

The addon owns no console, widget maker, dispatcher or test framework. Eight `LibStub(..., true)`
seams, each with a degradation stub:

| Seam | File:line |
|---|---|
| `LibKa0s-Core-1.0` | `core/CoreSetup.lua:39` |
| `LibKa0s-DebugLog-1.0` | `core/DebugLogSetup.lua:25` |
| `LibKa0s-Env-1.0` | `core/EnvSetup.lua:41` |
| `LibKa0s-Item-1.0` | `core/ItemSetup.lua:27` |
| `LibKa0s-Media-1.0` | `core/MediaSetup.lua:57` |
| `LibKa0s-Pool-1.0` | `core/PoolSetup.lua:22` |
| `LibKa0s-Widgets-1.0` | `core/WidgetsSetup.lua:85` |
| `LibKa0s-Options-1.0` | `settings/OptionsSetup.lua:47` |

No `core/PerfSetup.lua` — that is the ratified `performance-§12` no-combat-path exemption, a register
row in `docs/ARCHITECTURE.md` decided 2026-08-05 (issue #22).

The one close-button wrapper is `core/CoreSetup.lua:168`; every call site reaches it through
`NS.MakeCloseButton` / `B:MakeCloseButton` (`modules/Browser.lua:88-90, :994`, `modules/Export.lua:465`).

## Settings panel

One canvas sub-page, `General`, registered through `O.RegisterOptionsPage` (`settings/Panel.lua:985`)
and drawn by `O.SetRenderer(ctx, renderGeneral)` (`:990`). The page draws a primary tab strip via
`O.TabStrip` (`settings/Panel.lua:903`) over five tabs — **Master controls**, Capture, AH Price,
Interface, History — with `Master controls` first because `settings/Schema.lua:313-315` splices the
composed block at the head of the array. The block itself comes from `O.MasterControls{…}`
(`settings/Schema.lua:68`), so the canonical row set is composed, not hand-written.

The Filters tab carries a **secondary** strip through `O.SubTabStrip` (`settings/Panel.lua:399`),
drawn as ordinary scroll content, its selection kept per primary tab in `ctx.activeSubTab` and never
persisted (`:376-411`). No third level. No page banner and no chrome block — recorded at
`settings/Panel.lua:875-877` as a deliberate consequence of the addon being account-wide.

`General visibility` is a four-value dropdown and is a **new** key, not a migrated boolean —
`defaults/Global.lua:23-27` states that this addon never shipped a *show only in combat* checkbox, so
no `schemaVersion` bump is owed. No color rows, no `disabledIf`, no `LSM30_*` control, no reorder
arrows: `options-ui-§16/§17/§18`'s content checks are vacuous or already satisfied here — the AH
cascade is dragged through the shared `ReorderList` (`settings/Panel.lua:450-455`, `:574`).

## Storage, events, taint

One global, `LootHistoryDB`, account-wide under `.global`; `schemaVersion = 1`
(`defaults/Global.lua:10`). Migration runner `NS:RunMigrations` at `core/Database.lua:125` runs
before any read and stamps only steps that applied. Single write seam `S:Set`
(`settings/Schema.lua:363`) with validate → deepcopy → write → `onChange`; `sessionOnly` rows skip
the DB write. Boot validation `S:Register` (`settings/Schema.lua:401`) is live — its formerly dead
`row.default == nil` conjunct is gone and the reason is written down at `:394-403`.

Thirteen `RegisterEvent` call sites, **no** `SetScript("OnUpdate")` anywhere, seven one-shot
`C_Timer.After` uses. Two `SetMovable(true)` frames (`modules/Browser.lua:944`,
`modules/Export.lua:439`), both non-secure, both on `UISpecialFrames` (`modules/Browser.lua:1086`,
`modules/Export.lua:500`). One `InCombatLockdown` read (`modules/Browser.lua:1134`) driving the
visibility dropdown. No global writes outside the two declared in `.luacheckrc:42-45`.

## Root docs and `docs/`

`README.md` carries all five badges in canonical order (`:3-7`), the standard badge **bare** at `:6`,
no bundled-library inventory, no `## Libraries`/`## Credits` heading, no angle-bracket placeholders,
no `%20`. Tests badge reads `699%2F699`, which matches `docs/test-cases.md`'s `**Total** | **699**`
and the live run. It also carries two sections the canonical structure does not name —
`## Unreleased` (`:36`) and `## Auction-house pricing` (`:141`).

`CLAUDE.md` is a 65-line stub with all six mandated items, including the provenance line at `:51`
(`Bundles [LibKa0s](…) v1.25.0 (MIT)`) — in `CLAUDE.md`, not `README.md`. `DEPENDENCIES.md` present.

`docs/` ships **all six Tier 1 docs** under their canonical names, **four of seven Tier 2** docs with
the other three carrying explicit *Not applicable* rows, the verification-and-record set
(`testing.md`, `smoke-tests.md`, `test-cases.md`, `performance.md`, `automated-tests/README.md`,
`automated-tests/RESULTS.md` — four unconditional plus the exemption's shape), and one Tier 3 doc
(`browser.md`). `## Documentation map` (`docs/ARCHITECTURE.md:331`) covers every one of the sixteen
`.md` files under `docs/` exactly once and names the five frozen/generated directories once each.
No `file-index.md`, no `conventions.md`, no `complexity.md`, no `docs/perf-runs/`, no
`docs/pending/LEDGER.md`, no `TODO.md`, no non-canonical Tier 1/2 filename.

Hub shape: `docs/ARCHITECTURE.md` is **434 lines** with thirteen `##` sections, the largest of which
(*Settings schema*, `:93-151`) is 58 lines. Every mandated section is under the ~60-line spill line
and has spilled its detail to its topic doc; the file is marginally over the ~400-line SHOULD. Per
`AUDIT.md`'s instruction not to argue the arithmetic on a hub whose sections have all spilled, this
is recorded and not filed.

`## Documented deviations` (`:377`) carries **five ratified rows**: two `architecture-§5`
(direct-`db.global` carve-outs; the `sessionOnly` row kind), `performance-§12` (no perf harness),
`options-ui-§12` (three reset blast radii) and `options-ui-§1` (inverted set pickers). Each has a
Rule, a Why citing its issue, a Decided date and a re-check trigger.

## `.gitattributes`

Present at the root, 40 lines, the canonical **client-bound** body. The pin is
`* text=auto eol=crlf` (`:26`), the mandatory `*.sh text eol=lf` carve-out is at `:34`, and 20 lines
end in ` binary`. The body matches the collection's canonical client-bound file.

## Suites, as observed today

- `luacheck .` — **0 warnings / 0 errors in 28 files**.
- `lua tests/run.lua` — **699 passed, 0 failed, 0 skipped, 699 total**.
- `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .` — **0 warnings**, 13222 NLOC, 1761 functions,
  avg CCN 2.2, max CCN 15.
- `diff -r ../LibKa0s@v1.25.0/LibKa0s libs/LibKa0s` — **empty**.
- `diff -r ../LibKa0s@v1.25.0/testkit tests/_kit` — **empty**.
