# 02 — Deviations

Audited against **Ka0s WoW Addon Standard v2.17.1 (2026-08-03)**. Prefix **`LH-`** (reused from the
first audit, 2026-07-12). IDs are stable across runs; new findings this run start at **LH-20**.

**Provenance:** the standard was fetched from the raw GitHub URLs and verified byte-identical to the
canonical checkout at `/mnt/d/…/WowAddonStandards` (clean tree, HEAD `2141229`). `AUDIT.md` and three
section files were re-fetched fresh this run and diffed empty. No rule below is reconstructed from
memory. See `01_CURRENT_STATE.md` for the full provenance record.

Evidence for every row is in `03_EVIDENCE.md`; remediation in `04_TECHNICAL_DESIGN.md` /
`05_EXECUTION_PLAN.md`.

---

## Recurrence of the prior run (`docs/audits/2026-07-18/`)

| Prior ID | Section | Status this run |
|---|---|---|
| `LH-01 … LH-12` | (2026-07-12) | Still closed. |
| `LH-13` | `toc-file-§5` | **Closed.** The TOC now uses `Libraries → Locales → Core → Defaults → Modules → Settings` (`LootHistory.toc:15-60`). The `toc-file-§5` ↔ `layout-§1` contradiction the prior run flagged is unresolved **upstream**, but the addon now satisfies the more specific TOC rule. |
| `LH-14` | `options-ui-§2` | **Closed.** The combat refusal is the library's now (`settings/Panel.lua:787-792`); the host wires no second open path. |
| `LH-15` | `documentation-§2/§6` | **Closed.** `CLAUDE.md:11` reads `## Standards compliance (read first)`. |
| `LH-16` | `packaging` | **Closed.** `tools/` no longer exists in the repo. |
| `LH-17` | `lint` | **Closed.** `.luacheckrc:4` now excludes `docs/audits/` and `docs/reviews/`. |
| `LH-18` | `options-ui-§5` | **Closed.** All three subcategories are created with `defaultsButton = true` (`settings/Panel.lua:712,722,749`). |
| `LH-19` | `documentation-§5` | **RECURS (partial).** Two retired `§N.M` citations survive the sweep. Keeps its ID. |

---

## Summary

**MUST failures: 10** · **SHOULD failures: 3** · **Advisory (MAY): 2**

**Verdict: major deviations** — driven almost entirely by **one cause**: `LibKa0s-Perf-1.0` and the
whole `performance` section are un-adopted (LH-20 … LH-26, seven of the ten MUSTs). That decision is
**recorded** in the repo as a deliberate `wont-do` (`docs/pending/LEDGER.md:70`, LIBKA0S-17) with
substantive reasoning, so it is a **knowingly accepted deviation** rather than an oversight — but
`performance`'s adoption strength is **MUST for the wiring**, explicitly independent of whether the
addon has a hot path ("*some addons have almost no hot path*"), so the audit must record it. Its
resolution is a **user decision**: adopt the wiring, or take the contradiction upstream and change
the standard.

The three remaining MUSTs (LH-27, LH-28, LH-29) are ordinary, small, and independent of that.

Outside the perf cluster the addon is in strong shape: both LibKa0s vendor diffs are empty, `luacheck
.` is 0/0, the suite is 563/563 green, the degraded path is tested by real load, US English is clean,
the printer/bus/schema/Compat seams are all correct, and the window edge matches the normative table
value-for-value.

---

## MUST

| ID | Section | Severity | Deviation | Fix direction |
|----|---------|----------|-----------|---------------|
| **LH-20** | `performance-§1` (AP #47 inverse) | MUST | **`LibKa0s-Perf-1.0` is not wired.** There is no `core/PerfSetup.lua`, no `NS.Perf` instance built from a descriptor, and no degradation stub. The module's source *is* vendored (`libs/LibKa0s/Perf.lua`, `PerfPanel.lua`) and loaded by the runner — it is simply never adopted. Recorded as an accepted `wont-do` at `docs/pending/LEDGER.md:70`. | Add `core/PerfSetup.lua` on the standard shape: `local lib = LibStub and LibStub("LibKa0s-Perf-1.0", true)`, `NS.Perf = lib:New(descriptor)` guarded by `if lib`, else a stub carrying `on` and `Note` plus whatever the slash layer touches. TOC-list it **before** any module taking `local Perf = NS.Perf`. Declare a minimal bucket set (see LH-23/`04`). **Or** take the decline upstream as a proposed `performance` amendment for hot-path-free addons and record the outcome. |
| **LH-21** | `performance-§5`, `toc-file-§2`, `savedvariables-§4` | MUST | **`LootHistoryPerfDB` is not declared.** `LootHistory.toc:7` reads `## SavedVariables: LootHistoryDB` — one global where `toc-file-§2` requires **exactly two**, in order. The capture ring has no store. | `## SavedVariables: LootHistoryDB, LootHistoryPerfDB`, and hand the **name** to the Perf descriptor. Keep it outside the AceDB tree. Blocked on LH-20. |
| **LH-22** | `performance-§4`, `slash-commands-§2` | MUST | **The reserved `perf` verb is absent** from `NS.COMMANDS` (`settings/Schema.lua:213-245`). `/lh perf` currently prints `unknown command 'perf'` + help. `perf` is reserved collection-wide and MUST be registered by the addon's own table. | Add `{ "perf", "Measure performance — try `/lh perf` for the workflow", function(rest) … end }` dispatching into the library's command entry point, printing the returned lines through `NS.Print`. Blocked on LH-20. |
| **LH-23** | `performance-§6` | MUST | **No suspend/resume host contract.** Nothing unregisters the addon's eleven events, cancels queued work, or gates its show-decision ladder on a suspended flag, so the harness's second measurement arm cannot be produced. | Implement `suspend`/`resume` in the Perf descriptor: unregister the Collector/Attribution/Browser event sets, cancel pending `C_Timer` work, refuse at the source in the show ladder; restore from **current** state on resume; never persist the flag. **Note the LEDGER's objection is real** — suspending this addon drops loot during window B. The honest resolution is a documented, user-confirmed suspend, or an upstream amendment. Blocked on LH-20. |
| **LH-24** | `performance-§9`, `performance-§2` | MUST | **`tests/perf.lua` is absent.** The offline scenario runner is missing, and with it the **zero-overhead scenario** `performance-§2` names as the *required evidence* that instrumentation is free when off. | Add `tests/perf.lua`, run as `lua tests/perf.lua`, **outside** the green gate (not in `tests/run.lua`'s suite list). Assert only on call counts and bytes allocated, never wall-clock. Ship the zero-overhead scenario over the `CHAT_MSG_LOOT` capture path. Derive its load list from the TOC (testing-§9). Blocked on LH-20. |
| **LH-25** | `documentation-§3` | MUST | **Two required topic-detail docs are missing:** `docs/performance.md` (which paths are bracketed and why, how to run a capture, how to read the report) and `docs/perf-runs/README.md` (the standing capture store's naming, schema summary and pointer to the library's contract). | Author both. `docs/perf-runs/` is standing and cumulative, not tied to one investigation. Blocked on LH-20. |
| **LH-26** | `lint`, `performance-§2`, `performance-§5` | MUST | **`.luacheckrc` is missing both perf entries**: `debugprofilestop` is absent from `read_globals` (performance-§2 names it explicitly, because bracket call sites are addon code and *are* linted) and `LootHistoryPerfDB` is absent from `globals` (performance-§5 requires it declared with a comment, like `LootHistoryDB`). | Add `"debugprofilestop"` to `read_globals` and `LootHistoryPerfDB` (with its comment) to `globals`. One-line each. Blocked on LH-20/LH-21. |
| **LH-27** | `options-ui-§11` (AP #39 adjacent) | MUST | **The off-screen structural-rebuild flag is written and never read.** `settings/Panel.lua:321` sets `ctx.dirty = true` when a filter list changes while the Filters page is hidden, and `settings/Panel.lua:138` clears it — but **nothing anywhere reads `ctx.dirty`**. The library's own re-render gate is `ctx._dirty`, which the host never writes. Net effect: a backgrounded Filters page **never rebuilds on its next `OnShow`**, which is the exact behavior options-ui-§11 makes a MUST ("*flag every other rendered panel dirty and rebuild it lazily on its next `OnShow`*"). Independently found as `F-001` in `docs/reviews/2026-08-03/`. | Stop shadowing the library's bookkeeping. Route the off-screen branch through the library's public refresh entry point (`O.RefreshAllPanels`, whose `refreshCtx` sets `_dirty` on every hidden ctx) so the library owns *when* a page redraws and the host's `rebuilders` list only says *what* to draw. Delete the dead `ctx.dirty` field. Add a case pinning the outcome (list edited while hidden → next `OnShow` shows it), not the private flag. |
| **LH-28** | `savedvariables-§2` | MUST | **Default values are hardcoded in two places.** `defaults/Global.lua:21-27` declares `enabled = true`, `qualityThreshold = 1`, `excludeQuestItems = true`, `recordCurrency = true`, `retentionDays = 30`, `windowScale = 1.0`; `settings/Schema.lua:25,52,61,70,77,85` restates each as a row `default =` literal. savedvariables-§2 makes the defaults file the **only** place a default is hardcoded and says schema rows must *reference* those constants. The two can drift silently — AceDB seeds from one, `reset`/`resetall`/the Defaults button from the other. (`settings.auction.capture` already does it right, referencing `NS.Constants.AUCTION_CAPTURE_DEFAULT` at `settings/Schema.lua:109`.) | Make each schema row's `default` read the value out of `NS.defaults.global` (or a shared constant), so there is one literal per setting. Add a case asserting every non-session row's `default` equals the value at its path in `NS.defaults.global` — which is also the tripwire against a future re-divergence. |
| **LH-29** | `testing-§9` | MUST | **The runner's TOC derivation is not pinned by cases.** `tests/run.lua:30` derives correctly via `Loader.tocFiles`, but the suite carries none of the three assertions testing-§9 requires: that the runner fed the loader **exactly** the TOC's files in the TOC's order (publish what it loaded through `Kit.expose` and compare against a fresh derivation), that every derived path **exists on disk**, and that **no `libs/` path leaked in**. `Kit.expose` today publishes `NS`, `mocks` and `Loader` but not the loaded list (`tests/run.lua:39`). Both failure modes this guards are silent: a renamed suite is *skipped, not failed*, and an omitted library file silently makes the suite measure the degradation stub. | Capture the derived list in `tests/run.lua`, publish it through `Kit.expose{ loaded = … }`, and add the three cases to a suite (`tests/test_libka0s.lua` or a new `tests/test_runner.lua`). Extend to `tests/perf.lua`'s list by **reading its source** for the derivation call once LH-24 lands. |

## SHOULD

| ID | Section | Severity | Deviation | Fix direction |
|----|---------|----------|-----------|---------------|
| **LH-19** *(recurring)* | `documentation-§5` | SHOULD | **Two retired global `§N.M` citations survive** the v1.5.0 renumbering sweep: `settings/OptionsSetup.lua:99` cites *"Ka0s standard §3.4"* and `tests/test_database.lua:363` cites *"Ka0s Standard §2.2/§5.1"*. Every other citation in the repo is already in `filename-§N` form. (The `§6.2`/`§6.3` references under `docs/superpowers/specs/` are those design docs' **own** internal section numbers, not standard citations — correctly not counted.) | Rewrite: `§3.4` → `library-stack-§4`; `§2.2/§5.1` → `toc-file-§2` / `savedvariables-§1`. Comment-only edits. |
| **LH-30** | `standalone-windows-§2` | SHOULD | **The host skin restates the normative edge values instead of delegating.** `modules/Browser.lua:20-33` declares a private `SKIN` table and `:66-86` an `ApplySkin` that draws the backdrop, the black outer edge, the once-built inner-highlight child, the title tint and the divider tint by hand. The values are **exactly right** — they match the normative table component for component — so this is *not* the drift case the section is chiefly aimed at, and the section explicitly says a host re-skin seam is "not a deviation and is often necessary". What it also says is that such a helper **SHOULD delegate to `Core.ApplySkin` rather than restate** the values: a restated constant is the copy that goes stale the next time the standard retunes the edge. | Reach Core through `LibStub("LibKa0s-Core-1.0", true)` and have `B:ApplySkin` call `Core.ApplySkin(frame, skinOverride)`, keeping the host seam as the one place the addon's own windows are skinned and keeping only the genuinely host-specific fields (`titleBarH`, `tabStripH`, `contentGap`, `defaultH`, `minH`, `tabActive`, `tabIdle`) in `B.SKIN`. Behavior-neutral today by construction. |
| **LH-31** | `performance-§10` | SHOULD | **`docs/complexity.md` is not shipped.** No `lizard` report over the addon's own source (excluding `libs/`) is committed. Three files sit in the 1000–1500 LOC "on notice" band (`modules/Browser.lua` 1314, `modules/Analytics.lua` 1180, `modules/BrowserTable.lua` 1040), which is exactly the situation the report exists to inform. | Run `lizard` over `core/ defaults/ locales/ modules/ settings/` and commit `docs/complexity.md`, stating in the file that it is generated and how. **MUST NOT** gate commits on it. Absent tooling means the report is stale, not that the addon is non-compliant — so this is genuinely a SHOULD. |

## Advisory (MAY / observation)

| ID | Section | Level | Observation |
|----|---------|-------|-------------|
| **LH-32** | `documentation-§4` (spirit) | MAY | `docs/pending/LEDGER.md` is a checked-in, tool-maintained backlog of deferred and declined items running alongside the GitHub issue tracker. documentation-§4 names **`TODO.md`** specifically and this is not that file, so it is **not** recorded as a deviation — but its rationale ("two backlogs drift… a checked-in backlog competes with the issue tracker") applies. It is also load-bearing right now: it is where LH-20's decline is recorded, which is the standard's own prescribed home for an accepted deviation. Raised only so the tension is on the record; **no action recommended without a user decision.** |
| **LH-33** | `layout-§3`, `packaging` | MAY | `media/logos/wowhead-logo.png` ships to players but is referenced by **nothing** in the addon — its only mentions are in a retired plan doc (`docs/superpowers/plans/2026-07-17-ai-export.md:140,146`) for the "Export to AI" feature that `README.md:172` records as **removed in 1.2.0**. It is in a correctly typed subfolder, and WoW cannot load `.png` at runtime anyway, so no rule is broken — it is dead weight in the shipped package. Delete it with the rest of the AI-export residue, or keep it deliberately. |

---

## Notes on scope — what was checked and deliberately **not** flagged

- **The four un-wired-looking subsystems are compliance, not gaps.** There is no
  `modules/DebugLog.lua`, no widget-maker file, no dispatcher and no hand-written test framework in
  this repo **because they are `LibKa0s` modules**. What the addon owns — a descriptor plus a
  degradation stub per module, in `core/CoreSetup.lua`, `core/DebugLogSetup.lua`,
  `settings/OptionsSetup.lua` and `settings/Slash.lua` — is present, correct, and cited in
  `01_CURRENT_STATE.md` / `03_EVIDENCE.md`. **Anti-pattern #47 is clear.**
- **The Options stub's load-completing shape is correct and is not an inconsistency.**
  `settings/OptionsSetup.lua:37-64` publishes `LSMValues` real-enough for file load and no-ops the
  rest, exactly as options-ui-§1's documented exception prescribes. Flagging it would be a false
  positive.
- **Both vendor diffs are empty** (`diff -r ../LibKa0s/LibKa0s libs/LibKa0s` and
  `diff -r ../LibKa0s/testkit tests/_kit`), so **#45 and #48 are clear** and the TOC lists the single
  aggregate `libs\LibKa0s\LibKa0s.xml`.
- **The debug console's JetBrains Mono font and the addon logo are sanctioned exceptions**
  (debug-logging-§2, options-ui-§5 / layout-§3) and are explicitly **not** flagged as shipped art.
- **The host's own 24×24 close glyph is sanctioned.** standalone-windows-§2 lets a host draw its own
  × on **its own** windows, and `core/DebugLogSetup.lua:125-130` deliberately declines to push it
  onto the library's console — the exact split the section draws. This is a **compliance result**,
  not a deviation.
- **The AH Price page opting out of `O.SetRenderer`** (`settings/Panel.lua:738-747`) is a documented
  deviation with a measured justification (~1.7 s freeze from an AceGUI teardown of eleven pooled raw
  row slots). Recorded as an observation; not raised.
- **`preview-mode` is N/A** (no positionable display) and **`public-api` is N/A** (no public
  surface). `testing-§10` (versioning suite) is N/A — this addon publishes no LibStub major.
- **testing-§12 (falsification) is UNVERIFIED, not failed.** No suite carries a `red under:` comment,
  but the section states explicitly that mutation testing leaves no repo artifact and that an audit
  **MUST NOT** record its absence as a deviation. Recorded as unverified.
- **`defaults/Global.lua` without a `defaults/Profile.lua` is compliant.** The addon has no profile
  tree by design; `layout-§1` sanctions `Global.lua` for global defaults. The separate LH-28 finding
  is about *duplication*, not about the filename.
- **`toc-file-§5` vs `layout-§1`.** The two sections still disagree on section/load order. The addon
  follows `toc-file-§5`. Not counted as a deviation either way; flagged upstream in LH-13's closure
  note.
