# Testing

WoW runs **Lua 5.1**, so the headless suite targets Lua 5.1 too. Two gates guard every commit: the unit tests (`lua tests/run.lua`) and the linter (`luacheck .`). Both must be green — see [The green gate](#the-green-gate). For in-client, end-to-end scenarios that the headless harness can't reach — real `CHAT_MSG_LOOT` capture, the browser window, minimap button, combat-gated settings panel — see [smoke-tests.md](smoke-tests.md).

## The harness

`lua tests/run.lua`, run **from the repo root**, is the whole show. Most of it is not this repo's: the test registry, the assertions, the `--list` renderer, the source loader and the universal half of the WoW-API mock all come from the **shared LibKa0s test kit**, vendored byte-for-byte at `tests/_kit/` (see [The vendor gate](#the-vendor-gate)). What stays here is only what is genuinely per-addon.

`tests/run.lua` does four things:

1. Builds a fresh WoW-API mock set via `tests/wow_mock.lua` — a thin **extender** over `tests/_kit/mock_base.lua`, and a builder, so each run gets one isolated environment.
2. Loads every file of `LibKa0s.xml` in XML order, then every addon source file **derived from the TOC** via `Loader.tocFiles("LootHistory.toc")`, into a shared `NS` table. Then calls `NS:InitDB()`, `NS.Schema:Register()` and `NS.Panel:Register()` — mirroring the in-game load plus `OnInitialize`.
3. Exposes the kit's registry and assertions merged into the `_G.LH_TEST` handoff table via `Kit.expose` (`NS`, `mocks`, `Loader`, `addonFiles`, `suites`, `test`, `assertEqual`, `assertTrue`, `assertFalse`, `assertNil`, `assertNear`, `assertError`, `fail`, `skip`, `assertSuiteInventory`, `assertSurfaceParity`).
4. Hands the suite list to `Kit.run`, which loads each suite, runs every registered case under `pcall`, prints `PASS`/`FAIL` per case and a `N passed, N failed, N total` tail, and exits non-zero if anything failed.

The addon load list is **derived from the TOC rather than hand-maintained**, which is what stops the runner's order drifting from the client's. `libs\` lines are skipped (the client pulls those through their own XML, which the loader cannot see), so the vendored LibKa0s files are the one list still spelled out explicitly — and `tests/test_libka0s.lua` cross-checks its length against `LibKa0s.xml`.

The derivation itself is pinned (testing-§9). `tests/run.lua` publishes the exact table it handed the loader as `T.addonFiles`, and `tests/test_harness.lua` compares it against a fresh derivation, checks every derived path is on disk, and checks no `libs/` path leaked in. The same suite pins the **suite list** in both directions through `Kit.assertSuiteInventory` — `Kit.run` applies that gate implicitly, but a named case is what puts a row in [test-cases.md](test-cases.md), so a reader can tell a gate that ran from one that was opted out of.

### The loader

`tests/_kit/loader.lua` `loadfile`s each source path and `setfenv`s the chunk into an environment whose `__index` resolves WoW globals to the mock set first, then falls back to real `_G`, and whose `__newindex` lands writes in `_G` so a SavedVariables global or a `StaticPopupDialogs` registration behaves like the real client. Each addon chunk is called with `("LootHistory", NS)` — exactly the `local addonName, NS = ...` header every file expects — and each library chunk with no arguments, exactly as the client calls it.

### The mock

`tests/_kit/mock_base.lua` owns the universal half: frames (with recorded script handlers and a `__fire` seam), timers, `LibStub` with a real `NewLibrary` and strict about the silent flag, the Ace fakes, a fireable AceGUI widget factory, and the Blizzard Settings canvas recorder. `tests/wow_mock.lua` adds only what this addon touches — the loot and currency global strings, the item and currency APIs, the inline-markup helpers, the character identity its suites assert on, and three local extensions:

- **The AceEvent embed.** The kit's `AceAddon` fake does not embed the message bus, because not every host asks for it. This addon does (`NewAddon(NS, name, "AceEvent-3.0", …)`), and `NS.bus` *is* that object, so `NewAddon` is wrapped locally to model the real embed.
- **Frames that remember their size.** The kit's stub answers `0` from `GetWidth` forever. `LibKa0s-DebugLog-1.0` *derives* the console's Copy/Clear title-bar offsets from the width of the close button this addon supplies (24, where Core's is 18), so without a size-recording stub that derivation — the entire reason the `makeCloseButton` descriptor field matters here — is untestable.
- **`GetStringWidth` and `InlineGroup:SetTitle`.** The AH price table positions each row's info icon at `ACOL.module + GetStringWidth() + 6`, and the kit's blanket "any PascalCase method returns the frame" hands that a table; the inverted set picker draws into an AceGUI `InlineGroup`, whose `SetTitle` has no LibKa0s consumer and so is not modeled.

Never edit `tests/_kit/`. A kit problem is a finding to fix in `../LibKa0s` and re-vendor; a local patch is a fork nobody knows about, and the next re-vendor silently reverts it.

Three design choices make the mock earn its keep rather than merely satisfy `require`:

- **It omits several `C_*` APIs on purpose** — e.g. `C_Container`, `C_ChallengeMode`, `C_AuctionHouse`, `C_TooltipInfo`, `C_Spell`. `core/Compat.lua` presence-guards each of these before calling, so their absence drives the compat shims down their **degraded path** every run. The tests therefore prove the fallbacks work, not just the happy path.
- **The message bus is modeled on CallbackHandler**, keyed by `(message, target)`. Registering the same message twice on one target overwrites (only the last survives); `SendMessage` fires once per distinct target. This mirrors the real semantics so a same-target clobber — the exact bug that shipped when the bus was a bare no-op mock — is catchable, and enforces the convention that receivers register on their own `NS.NewBusTarget()`.
- **`C_Texture.GetAtlasInfo` knows only a short whitelist of atlases** (the four class icons the suites use, plus one star). No compat shim reads it — the atlas lookups live in `modules/BrowserTable.lua` and `modules/Analytics.lua` — and both of them branch on the *result*, so a selective registry exercises the found path AND the `CLASS_ICON_TCOORDS` / no-star fallback in the same run. `RAID_CLASS_COLORS` is whitelisted the same way, so the neutral-gray fallback for an unknown class stays under test.

One behavior the kit models that this addon's own mock never did: **AceConsole's `Embed` clobbers a same-named custom `Print`**. `core/LootHistory.lua` reclaims `NS.Print` from `NS.Util.print` because of it (architecture-§2), and that reclaim is now a live assertion rather than a vacuous one.

### Testing UI modules headlessly

`modules/Browser.lua`, `modules/BrowserTable.lua` and `modules/Analytics.lua` are mostly frame
construction, but the decisions inside them — which options a dropdown offers, how a view resolves
into a query filter, how a stacked bar apportions its segments — are pure and worth pinning. Those
helpers are **published on the module table under a leading underscore** (`B._asSet`,
`Analytics._dayKeyList`, …) next to their definitions, so the suite drives the exact function the UI
binds rather than a copy of its logic. The frame work itself — rendering, drag, resize, taint —
stays in [smoke-tests.md](smoke-tests.md), which complements rather than replaces these suites.

### The test framework

`tests/_kit/framework.lua`, shared across the Ka0s collection. `test(name, fn)` registers a case; the assertions are `assertEqual`, `assertTrue`, `assertFalse`, `assertNil`, `assertNear` (never compare computed geometry with `==`) and `assertError` (which returns the message, so a case can assert on *what* raised rather than merely *that* something did). Failures `error` with the caller's line, and the runner catches them per case so one failure never masks the rest.

It is **collect-then-run**: `test()` only records, and nothing executes until `Kit.run`. `--list` is then a pure filter over the same registry and cannot disagree with what actually runs — which is what makes `docs/test-cases.md` authoritative rather than a second code path through the same file.

## The suites

Twenty-five files, loaded in this order (see **[test-cases.md](test-cases.md)** for the full per-case
inventory and the authoritative count):

| Suite | Covers |
|-------|--------|
| `test_mediasetup.lua` | the **`LibKa0s-Media-1.0`** seam (`core/MediaSetup.lua`) — `NS.Icon` answering the vendored, **extensionless** path and `nil` for a name the catalog does not carry, `NS.MediaFont` against the shipped face, `FONT_MONO` equal to `NS.MediaFont(FONT_MONO_NAME)` and no longer naming this addon's deleted `media/fonts/`, `NS.IconMarkup`'s splice and its required fallback, **every mark this addon draws cross-checked against `Media.ICONS` AND against a file in `libs/LibKa0s/media/icons/`** (a rename on either side answers nil, and nil draws nothing), the source re-derived so a name added to a module and not to the list cannot go unchecked, and the degraded load where both seams answer nil and `FONT_MONO` falls back to `STANDARD_TEXT_FONT` |
| `test_constants.lua` | enum + derived-table invariants — `SourceType` key==value (the export contract), `SourceOrder`/`SourceLabel`/`SOURCE_IMPLEMENTED` totality, the derived `SOURCE_OPTIONS`, the quality ladder + retention presets, and the auction key catalog (unique tags, capture options mirror the keys, the priority cascade covers every key exactly once with the captured ones ranked first) |
| `test_util.lua` | pure helpers — time/link/loot-string parsing, table ops, `PlayerKey`; the secret-safe printer (`IsConcatSafe`/`SafeToString`/`NS.Print`, reclaimed from AceConsole) |
| `test_compat.lua` | `NS.Compat` shims — GUID decode, item/map info, degraded fallbacks |
| `test_attribution.lua` | source-resolution engine — context stamp/consume, TTL, confidence |
| `test_filters.lua` | `NS.Filters` blacklist/whitelist id lists — add/remove (mutually exclusive, copy-on-write), `Blacklist`/`Whitelist` set contents, `SortedIDs`, `ParseItemID` |
| `test_auctionprice.lua` | `GatherAll` captures every enabled `provider:key` price into a nested map (per-provider Auctionator/TSM/OribosExchange, `pcall`-guarded so a broken addon is skipped not fatal, gated on the capture set + master switch, `nil` when nothing gathered); `Pick` resolves one via the `settings.auction.priority` cascade (reorder-aware, first present wins); `IsProviderAvailable`; `ReconcilePriority` appends missing / drops unknown tags; `SwapPriorityTags` reorders |
| `test_collector.lua` | `CHAT_MSG_LOOT` gate — self-filter, quality/quest-item threshold, record build |
| `test_database.lua` | Add/Query/Delete/PruneOld, retention rebuild-and-swap |
| `test_stats.lua` | `Stats`/aggregation feeding the Insights tab |
| `test_browser.lua` | the filter bar's pure surface — toolbar/window width floors, `setToFilter`/`asSet` (copy-not-alias, legacy scalar views, the `all` sentinel), every data-driven option builder (distinctness, sort order, blank/missing values, the `Character: Current` preset), and the saved view: `ApplyView`/`CaptureView`/`SaveView`/`ResetView`/`SetCharSet`/`CurrentFilter` |
| `test_browsertable.lua` | filter→group→sort→slice pipeline, group headers/counts + namespaced collapse keys, sort direction rules (numeric vs text, grouped-column click flips group order) and stability under an all-ties sort, cell rendering edges, the column model contract (Character last, Item flexes), test mode + the fixed-seed synthetic dataset's determinism and field invariants, `OrderedFilteredRecords` |
| `test_export.lua` | `Export:CSV` columns/quoting, friendly `bound`/`date`, `WowheadLink` bonus-ID parsing |
| `test_debuglog.lua` | `NS.Debug` tagged format + secret-safe sink, session-only flag, `/lh debug` toggles |
| `test_slash.lua` | the `LibKa0s-Slash-1.0` dispatcher — `/lh list`/`get`/`set`/`reset`/`resetall`/`version` output (slash-commands-§5), `FormatSchemaValue`/`FormatKV`/`BuildListLines`, grouping, Usage/not-found, the type-aware parser (enum refusal, slider clamping, boolean refusal), the `format` hook that keeps a set-valued row from rendering as `<secret>`, and both convergences: `reset` is path-scoped, and `LandingRows`/`HelpRows` are the one formatter differing only by the chat indent |
| `test_schema.lua` | `NS.Schema` rows — `Set` validation + write-through (deep-copied, never aliased), `Get`/`Default`, session-only rows (`state.debugConsole`) never touching `db.global`; plus the schema's own shape: unique paths, defaults matching both their declared type and `defaults/Global.lua`, dropdown defaults being selectable, slider defaults inside their range, every setting round-tripping, and the `NS.COMMANDS` table |
| `test_analytics.lua` | the Insights view's pure charting logic — headline shrink-to-fit, the rank-ordered palette + `paletteMap`, label truncation, `_charStackSegments` (top-N with an `__OTHER__` remainder, drawn in the shared category order, magnitude-preserving), `_buildCharStackRows` scaling/labeling/tips, the day-strip key list (gaps included, capped to the 60 most recent), `sortedByCount` ordering, and the money/class/quality/short-name formatters |
| `test_harness.lua` | the runner's own three lists (testing-§9) — the TOC derivation the loader was actually handed compared against a fresh one, every derived path on disk, no `libs/` leak, and the suite list pinned in both directions by `Kit.assertSuiteInventory` plus a duplicate check the inventory gate cannot see |

Seven of the twenty-five exist because of the LibKa0s adoption:

| Suite | Covers |
|-------|--------|
| `test_panel.lua` | the settings panel, which had **no suite at all** before the `LibKa0s-Options-1.0` adoption — parent + sub-page registration and its idempotence, the deferred first-`OnShow` body render, one widget per non-skipped row at the 50/50 width, `CheckBox`/`Dropdown`/`Slider` dispatch, dropdown lists populated from the row's `values` in declared order, slider bounds, section headings as the schema groups, the three write paths reaching `NS.Schema:Set`, an external write mirrored back by `Refresh`, the inverted muted-source picker in both directions, the lazy Defaults button (asserted **absent** before first show, which is the half that makes it a guard), each page's Defaults handler including the carve-out priority cascade, the AH page's pooled row slots and page filtering, the landing page's command rows matching `lib.FormatRow` byte for byte, and the combat refusal |
| `test_envsetup.lua` | the **`LibKa0s-Env-1.0`** seam (`core/EnvSetup.lua`) — that `NS.Meta` / `NS.Version` / `NS.PlayerMapID` / `NS.Zone` answer what the deleted `Compat` shims answered, that they ask about **this** addon's folder, that those shims are gone, and that `NS.Zone` still answers two strings and never nil |
| `test_itemsetup.lua` | the **`LibKa0s-Item-1.0`** seam (`core/ItemSetup.lua`) — that the four primitives answer what the deleted `Compat` shims answered, that the shims are gone, and that the guessing resolver (`Compat.GetItemInfo` / `Compat.ItemNameQuality`) pointedly **stayed** |
| `test_poolsetup.lua` | the **`LibKa0s-Pool-1.0`** seam (`core/PoolSetup.lua`) — that the seam is wired and that this addon, the one whose chart pool leaked, actually **recycles** rather than allocating a fresh frame per pass |
| `test_libka0s.lua` | the adoption seams themselves — the shared `NS.LIBKA0S_MISSING` cause clause asserted verbatim and on **both** paths, a degraded install exercised by loading every TOC file over a mock set that has never seen `libs/LibKa0s` (rather than by hand-stubbing a branch), the `L`-trap source guard with its own case driving all three spellings, the Core and Options library tripwires that stand in where a module cannot express the trap, module coverage, the silent-flag check on every seam's `LibStub` call, one `Kit.assertSurfaceParity` case per adopted seam (Core, Widgets, Slash, DebugLog, Options) whose degraded arm is a real partial-file-list load rather than a hand-stubbed member, the bare-`/lh` help the degraded dispatcher renders, and vendor fidelity |
| `test_widgets.lua` | the **`LibKa0s-Widgets-1.0`** adoption (`core/WidgetsSetup.lua`) — the seam handing the library its `chevron` and `check` as parameters and deliberately handing it **no** `glyphFont` (with the other half of that decision pinned as source: no option table in this addon sets `glyph`), a **real** row build driven through the library's own `makeMenuRow` by firing a dropdown's actual `OnClick` — never a seeded stand-in row, which is how 553 green library cases sailed over the `FontString:SetText(): Font not set` crash v1.11.0 and v1.11.1 shipped — the highlight and tick painted onto a pooled row, the `isActive` preset row lighting up and its one-click `dd.presets` replacement, a selected character with no option row still counting in the collapsed label, the nine filter-bar instances plus the export modal's picker, the class icon folded into a **label** rather than into an `icon` field the library does not have, `CloseMenu` reached from all three non-click close paths (the window's `OnHide`, `Browser:Hide`, and the export modal's `OnHide`, which had no handler at all before), both hosts' strata proved below `FULLSCREEN`, and the degraded install where the seam answers nil, both surfaces refuse to draw and the addon still comes up |
| `test_vendor_sync.lua` | the vendored-payload gate, adopted from the kit in one line (`tests/_kit/vendor_sync.lua`) — that `libs/LibKa0s/` and `tests/_kit/` are exactly what the LibKa0s repo published at the tag this repo’s `CLAUDE.md` names, with the provenance line read as an **input** rather than hardcoded, one normalization (CR stripped from the working-tree side, because `.gitattributes` pins CRLF while `git show` hands back the LF blob), and a missing `../LibKa0s` sibling reporting a **skip carrying its reason** rather than a pass |

See [module-map.md](module-map.md) for the source files behind each suite and [compat-layer.md](compat-layer.md) for the shims `test_compat` exercises.

## The vendor gate

`libs/LibKa0s/` and `tests/_kit/` are **vendored copies** of a library this project also authors, which makes keeping them in sync an ongoing job rather than a one-time copy. None of the gates above can see a stale one: the library's own suite passes against the library, and this addon's passes against a stale copy that still works. Only a diff can say so.

**Which tag they are compared against is read out of [`../CLAUDE.md`](../CLAUDE.md)**, from the *Bundles [LibKa0s](…) vX.Y.Z (MIT).* line under `## Vendored LibKa0s` — `test_vendor_sync.lua` greps it rather than hardcoding a version, because a provenance line and a payload that disagree is exactly the drift the gate exists to catch. Kit revision 9 moved that input from `README.md` to `CLAUDE.md` and kept **no fallback**, so bumping the line and re-vendoring the bytes must land in the same commit.

Run all four, from this repo's root, with `../LibKa0s` checked out beside it:

```
diff -r --strip-trailing-cr ../LibKa0s/LibKa0s libs/LibKa0s    # content — MUST be empty
diff -r ../LibKa0s/LibKa0s libs/LibKa0s                        # bytes  — SHOULD be empty
diff -r --strip-trailing-cr ../LibKa0s/testkit tests/_kit      # content — MUST be empty
diff -r ../LibKa0s/testkit tests/_kit                          # bytes  — SHOULD be empty
```

Read the difference between each pair, because the two answers mean different things:

- **Both empty.** In sync. Nothing to do.
- **Content differs.** A copy has genuinely **forked**, which is the forbidden state. The fix is to re-vendor whole-folder (`cp -r ../LibKa0s/LibKa0s/. libs/LibKa0s/`), never to hand-patch `libs/` — a local patch is a fork nobody knows about, and the next re-vendor silently reverts it.
- **Content empty, bytes differ.** **Nothing has forked.** The two checkouts merely disagree about line endings. `.gitattributes` pins the whole tree `* text=auto eol=crlf` (line-endings-§2) while git stores the blobs as LF, so a working tree holding either ending round-trips to the same blob and `git status` stays clean on both sides — the state is invisible and self-perpetuating. Renormalize whichever side drifted (`git add --renormalize .`; if the working tree does not flip, delete the affected paths and `git checkout -- .` to pull them back through the filter). Re-vendoring will not converge it, and editing `libs/` to settle it creates a fork to fix a fork that was not there.

Never edit anything under `libs/` or `tests/_kit/`. A library problem is fixed in `../LibKa0s`, released with its file `MINOR` bumped, and re-vendored back — see that repo's `docs/releasing.md`.

## Current status

The authoritative case count and full per-case inventory live in
**[test-cases.md](test-cases.md)** (generated by `lua tests/run.lua --list`). Re-verify the live
pass/fail at any time with the tail of `lua tests/run.lua`.

## Keeping the inventory & badge in sync

Whenever the suite changes — a case added, removed, or renamed, or the pass count moves (which is
exactly what resolving a test failure does) — you **MUST**, as part of the same change:

1. Regenerate the inventory: `lua tests/run.lua --list > docs/test-cases.md`.
2. Update the README `tests` badge (`![tests](https://img.shields.io/badge/tests-<pass>%2F<total>_passing-brightgreen)`)
   to the new count.

The inventory doc and the badge are part of the change, not a follow-up.

## Lint

`luacheck .` — must report **0 warnings / 0 errors** before every commit. Config is `.luacheckrc`: `std = "lua51"`, the WoW globals whitelisted under `read_globals`/`globals`, and `exclude_files = { "libs/", "docs/audits/", "docs/reviews/", "_dev/", "tests/" }` (vendored libraries and the tests themselves are not linted; the `docs/` bundles are Markdown-only anyway). **That figure is scoped, not repo-wide** — it currently covers 28 files, and every LibKa0s seam file (`core/CoreSetup.lua`, `core/DebugLogSetup.lua`, `settings/Slash.lua`, `settings/OptionsSetup.lua`) is inside that set, which is what makes a clean run mean something. To syntax-check a single file without the full suite: `luac -p path/to/file.lua`.

## The green gate

Both checks run before every commit:

```
lua tests/run.lua                                              # all suites green (count: docs/test-cases.md)
luacheck .                                                     # 0 warnings / 0 errors
diff -r --strip-trailing-cr ../LibKa0s/LibKa0s libs/LibKa0s    # vendored library, content
diff -r --strip-trailing-cr ../LibKa0s/testkit tests/_kit      # vendored test kit, content
```

The two diffs need `../LibKa0s` checked out beside this repo; see [The vendor gate](#the-vendor-gate) for the byte-level halves and what each answer means.

A commit ships only when both are green.

## Automated test records — the consolidated run

All four out-of-game suites go through one vendored runner, and every run is recorded
(`automated-tests`):

```sh
tests/_kit/run-automated-tests.sh                            # all four, writes a bundle
tests/_kit/run-automated-tests.sh --suite complexity          # a subset
tests/_kit/run-automated-tests.sh --suite lint --suite tests --no-bundle   # the green gate; writes nothing
```

| Suite | Command | Gates the run + the commit? | Gates the tag? |
|---|---|---|---|
| `lint` | `luacheck .` | **yes** (testing-§4) | **yes** |
| `tests` | `lua tests/run.lua` | **yes** (testing-§4) | **yes** |
| `perf` | `lua tests/perf.lua` | no — recorded only | **yes** — at `pass` |
| `complexity` | `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .` | no — recorded only | **yes** — at `pass`, zero functions above CCN 15 |

**There are two checkpoints, and `perf` and `complexity` answer differently at each.** They never
fail a run and never block a commit: they are measured, recorded and diffed, because a threshold
that fails a run teaches everyone to reach for `--no-verify`, after which the gate protects nothing
and the habit remains. They contribute `amber`, which is a signal rather than a stop. **The tag is
gated on all four suites at `pass` plus zero functions above CCN 15** (automated-tests-§3, *The
release gate*), evaluated by `/wow-addon:bump-version` from the release run's `manifest.json` — not
by the runner, whose exit code is unchanged. **A missing tool is a skip recorded with its reason**,
never a pass, and at the release gate a skip is **NOT EVALUATED** rather than passed.

The runner is **vendored** from `LibKa0s`'s `testkit/`; never edit `tests/_kit/`. A kit fix goes
upstream and is re-vendored.

**At release, not at commit.** A full bundle is produced as part of every version bump, before the
tag, with an `ANALYSIS.md` write-up. Commits are gated on lint + tests only; the **tag** is gated on
all four suites, per the table above.

Results live in [`automated-tests/`](./automated-tests/): `RESULTS.md` is one row per run across all
four suites plus the current complexity watch list — **one file, overwritten in place**, so its git
history is the trend line — and each `<YYYYMMDD-HHMMSS>/` is a frozen bundle of that run's raw
output. Bundles are never edited and never pruned.

`docs/complexity.md` was this addon's standalone complexity report through standard v2.18.0; it is
**retired** — its raw output is each bundle's `complexity.txt` and its trend line is `RESULTS.md`.

## Toolchain install

The suite needs Lua 5.1 and luacheck (Debian/Ubuntu/WSL):

```
sudo apt-get update && sudo apt-get install -y lua5.1 luarocks
sudo luarocks install luacheck
```

`lua` must resolve to the 5.1 interpreter (`lua5.1`). `luac -p` uses the matching 5.1 compiler for single-file syntax checks.

The full toolchain — including `lizard` for the report above, which needs `pipx` rather than `pip`
on Ubuntu 24.04 — lives in the root **[DEPENDENCIES.md](../DEPENDENCIES.md)**, with a verification
command per tool. That file says *what to install*; this one says *how to verify*.

Two environment facts the gate depends on: this repo is reachable at **both** `/home/tushar/GIT/LootHistory/` and `/mnt/d/Profile/Users/Tushar/Documents/GIT/LootHistory/` (the same working copy under WSL — either path works), and **`../LibKa0s` must be checked out beside it** or two of the four vendor-gate diffs cannot run.
