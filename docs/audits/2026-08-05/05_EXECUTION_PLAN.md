# 05 — Execution plan

Ordered, checkable remediation steps, grouped into sprints, each tied to its deviation ID. This is
the hand-off to the separate remediation engagement; the audit itself changed no addon code.

**Standing rules for every step below.**

- `lua tests/run.lua` green **and** `luacheck .` 0/0 before every commit (`testing-§4`). No step is
  sized larger than one commit.
- Test-first (`testing-§4`); characterization test **before** any behavior-preserving refactor, run
  against the unrefactored code (`testing-§13`).
- Whenever a case is added, removed or renamed: regenerate `docs/test-cases.md` with
  `lua tests/run.lua --list > docs/test-cases.md` **and** update the README `[tests]` badge in the
  **same** change (`testing-§5`).
- Never edit a frozen artifact — `docs/audits/*`, `docs/automated-tests/<run>/`. Never hand-edit
  `docs/automated-tests/RESULTS.md`'s numbers; it is generated.
- Nothing in Sprint 3 starts until **Sprint 0**'s decision is recorded.

---

## Sprint 0 — The decision (no code)

The seven-MUST perf cluster is a question, not a task. Answer it before anything in Sprint 3 is
scheduled.

- [ ] **S0.1** — Read `docs/pending/LEDGER.md` `LIBKA0S-17` alongside `performance` (adoption
      strength) and `performance-§6`, and choose **Option A** (adopt with a user-confirmed suspend),
      **Option B** (take the contradiction upstream as a `performance` amendment), or **Option C**
      (record a standing accepted deviation). `04_TECHNICAL_DESIGN.md` Group 0 has each design.
      — `LH-20 … LH-26`
- [ ] **S0.2** — Record the choice where the next audit will find it: the LEDGER row, and
      `docs/ARCHITECTURE.md`'s `## Standards compliance` section. Under **Option B**, open the
      upstream issue in `WowAddonStandards` and cite it. Under **Option C**, note that `LH-36`
      becomes **mandatory**, not optional — the release gate's no-`tests/perf.lua` exception has to
      be stated somewhere and rolled forward at every release.
      — `LH-20`, `LH-36`

---

## Sprint 1 — The four independent bugs

Highest value per line in the plan, and all four are unrelated to Sprint 0. Do these first whatever
S0 decides. **One commit each** — none of them may ride inside another's diff.

- [ ] **S1.1** — Add the failing case: the seeded `settings.auction.priority` contains every tag
      derivable from `C.AUCTION_KEYS`, exactly once. Watch it go **red** against current code.
      — `LH-34`
- [ ] **S1.2** — Point `defaults/Global.lua:36-39` at `NS.Constants.AUCTION_PRIORITY_DEFAULT`.
      Confirm the TOC load order resolves it and that the value is **copied**, not aliased, into the
      DB (the `excludedSources` hazard at `settings/Schema.lua:149-151`). S1.1 goes green.
      — `LH-34`
- [ ] **S1.3** — Decide on the migration for existing installs whose stored priority list still has
      seven entries: append any `AUCTION_KEYS` tag missing from it in
      `core/Database.lua:RunMigrations` — **append, never reorder**, the order is a user choice — or
      accept that `ReconcilePriority` fixes them on first AH-Price-page open. Whichever, write the
      reason down.
      — `LH-34`
- [ ] **S1.4** — Add a case that registers a deliberately bad schema row and asserts the boot
      validation warns **through `S:Register`**. Red first.
      — `LH-43`
- [ ] **S1.5** — `settings/Schema.lua:194`: `and` → `or`. Then **read what it now prints** on a
      headless load and in game — every warning is a second finding to triage, not noise to silence.
      If a row legitimately resolves to nothing, widen the `sessionOnly` carve-out at `:193`
      explicitly with a comment; do not narrow the condition back.
      — `LH-43`
- [ ] **S1.6** — Add the outcome case for the hidden-page rebuild: edit a filter list while the
      Filters page is hidden, show it, assert the new row is present. Red first. Assert the
      **outcome**, never `_dirty`.
      — `LH-27`
- [ ] **S1.7** — Route `settings/Panel.lua:329`'s hidden branch through `O.RefreshAllPanels`; delete
      `ctx.dirty` and its clear at `:146`. Verify the AH Price page's `SetRenderer` opt-out
      (`settings/OptionsSetup.lua:22-29`) is unaffected.
      — `LH-27`
- [ ] **S1.8** — Add the degraded-load case: load the addon with AceEvent-3.0 absent and assert no
      two bus receivers share a target. The bus mock already keys by target, so the clobber is
      observable headlessly. Red first.
      — `LH-35`
- [ ] **S1.9** — Drop the `or bus` / `or NS.bus` tail at `modules/Collector.lua:217`,
      `modules/Analytics.lua:657`, `modules/Browser.lua:1366`; guard on the result, following
      `settings/Panel.lua:130-138`. Consider a one-shot explanatory line on
      `core/CoreSetup.lua:53-65`'s pattern.
      — `LH-35`

**Exit:** four bugs closed, four new cases, suite green, inventory and badge regenerated.

---

## Sprint 2 — Harness integrity and the defaults sweep

The gates that are supposed to catch the next one of these.

- [ ] **S2.1** — Split `tests/test_vendor_sync.lua`: one case asserting the sibling checkout is
      reachable, **failing** with the path it looked for; the two sync cases behind it. A machine
      without the sibling gets a runner-recorded **skip with a reason**, never a pass. Correct the
      header's `.gitattributes` claim at `:28-32`.
      — `LH-40`
- [ ] **S2.2** — Capture the derived load list in `tests/run.lua`, publish it via
      `Kit.expose{ loaded = … }` (`:39`), and add `testing-§9`'s three assertions: exact files in
      exact TOC order, every path exists on disk, no `libs/` path leaked in.
      — `LH-29`
- [ ] **S2.3** — Generalize `loadDegraded()` to DebugLog, Slash and Options, driving each assertion
      from the **live** seam's export list rather than a hand-copied member list. Add `HelpHeader`
      to the Slash stub. For `ConsoleCheckbox`, delete it from the DebugLog stub or write down why
      it stays.
      — `LH-39`
- [ ] **S2.4** — Add the standing tripwire: every non-session schema row's `default` equals the
      value at its path in `NS.defaults.global`. Red first.
      — `LH-28`
- [ ] **S2.5** — Consolidate the six duplicated defaults (`settings/Schema.lua:25,52,61,70,77,85`)
      onto `NS.defaults.global`, preferring a data table plus one loop (`performance-§11` shape 3).
      **Test absence with `== nil`, never `or`** — three of the six default to `true`, and an `or`
      layer would resurrect a setting the user turned off (`savedvariables-§5`, anti-pattern #54).
      — `LH-28`
- [ ] **S2.6** — Run both vendor diffs manually once, now that S2.1 makes the suite honest:
      `diff -r ../LibKa0s/LibKa0s libs/LibKa0s` and `diff -r ../LibKa0s/testkit tests/_kit`. Both
      **MUST** be empty. This audit could not run them (single-repo scope), so anti-pattern #45 is
      currently **unverified** rather than clear.
      — `LH-40`

**Exit:** the vendor gate can fail, the load list is pinned, the degraded path is covered per
module, one literal per default, #45 verified.

---

## Sprint 3 — The perf cluster (**gated on Sprint 0**)

Only under **Option A**. Under B or C, skip to Sprint 4 and carry S3's IDs as the recorded decision.
Order is dependency order; do not reorder.

- [ ] **S3.1** — `core/PerfSetup.lua`: silent resolve, guarded `:New`, and a stub answering
      **every** member the addon reaches. TOC-list it after `core/CoreSetup.lua` and before any
      module taking `NS.Perf` as an upvalue. Model the stub on `core/DebugLogSetup.lua:26-72`.
      — `LH-20`
- [ ] **S3.2** — `LootHistory.toc:7` → `## SavedVariables: LootHistoryDB, LootHistoryPerfDB`; hand
      the name to the descriptor; keep the store outside the AceDB tree; bound the ring.
      — `LH-21`
- [ ] **S3.3** — `.luacheckrc`: `debugprofilestop` into `read_globals`, `LootHistoryPerfDB` into
      `globals` with a comment. Land **with** S3.2 so lint never goes red between commits.
      — `LH-26`
- [ ] **S3.4** — Declare the buckets in the descriptor, in report order, with `within` where they
      nest; add the brackets at the real entry points using `performance-§2`'s exact idiom. Add a
      case per bucket proving a real bracket reaches it (`testing-§8`).
      — `LH-20`
- [ ] **S3.5** — Append the `perf` triple to `NS.COMMANDS` (`settings/Schema.lua:213-245`),
      dispatching into the library's entry point and printing through `NS.Print`. Add the row to
      `README.md`'s slash table in the same change.
      — `LH-22`
- [ ] **S3.6** — Implement `suspend`/`resume`: unregister the three event sets, cancel the one-shot
      timers, refuse at the source in the show ladder, restore from **current** state, never persist
      the flag, resume **before** save/report. **Make the data-loss cost explicit** — confirmation
      on suspend, and the step panel stating that window B does not record.
      — `LH-23`
- [ ] **S3.7** — `tests/perf.lua`, outside the gate and **not** in `tests/run.lua`'s suite list.
      Call counts and bytes only, never wall-clock. Ship the **zero-overhead scenario** over the
      `CHAT_MSG_LOOT` path. Derive its load list from the TOC and pin the derivation by reading its
      source (extends S2.2).
      — `LH-24`, `LH-29`
- [ ] **S3.8** — Author `docs/performance.md`: bracketed paths and why, how to run a capture, how to
      read the report, what the harness can and cannot resolve — pointing at the library for the
      shared protocol rather than restating it.
      — `LH-25`
- [ ] **S3.9** — Run a full four-suite bundle and confirm the `perf` column is no longer `skip`.
      — `LH-24`

**Exit:** `perf` passes in the bundle, and the release gate can be met without an exception.

---

## Sprint 4 — Docs and polish

Independent of everything above; safe to land in parallel with Sprint 1 if a second pair of hands is
available.

- [ ] **S4.1** — Add the **release gate** to `docs/testing.md:167-176`,
      `docs/automated-tests/README.md` and `RESULTS.md`'s header note, keeping both checkpoints
      straight: commits on lint + harness only; the **tag** on all four suites plus
      `suites.complexity.warnings == 0`, evaluated by the release command from `manifest.json`,
      never by the runner; a `skip` blocks as NOT EVALUATED. State this addon's standing
      `perf: skip` exception and require it in the release notes until S3.7 lands. **Change the
      generator for `RESULTS.md`, not the file.**
      — `LH-36`
- [ ] **S4.2** — Fix the band-table disposition for `modules/Browser.lua`: an own disposition, or a
      tracked deviation ID that actually tracks its size. Not `LH-31`, which is retired.
      — `LH-37`
- [ ] **S4.3** — Reduce `CLAUDE.md` to the five required items plus the pointer list. Move the
      durable `## Hard rules` content into `docs/ARCHITECTURE.md` where it is not already there;
      delete `## Response style` and the `agent-context.md` essay. **Do not touch
      `## Standards compliance (read first)`.**
      — `LH-38`
- [ ] **S4.4** — Restate `docs/perf-runs/README.md`'s naming as `<YYYY-MM-DD>-ingame-<label>.json`,
      flat. Keep the scenario-note requirement.
      — `LH-41`
- [ ] **S4.5** — Two comment lines: `settings/OptionsSetup.lua:101` → `library-stack-§4`;
      `tests/test_database.lua:390` → `toc-file-§2` / `savedvariables-§1`.
      — `LH-19`
- [ ] **S4.6** — Delete the stale `-- luacheck: ignore addonName` at `modules/AuctionPrice.lua:1`.
      — `LH-44`
- [ ] **S4.7** — Delegate `B:ApplySkin` to `Core.ApplySkin` (silent resolve, guarded), keeping only
      the host-specific fields in `B.SKIN`. Smoke-test **three** windows — the History browser, the
      debug console and its copy window, since `core/DebugLogSetup.lua:117-119` routes the latter two
      through the same seam. Leave the `makeCloseButton` refusal at `:120-131` untouched.
      — `LH-30`
- [ ] **S4.8** — Rename the panel button to `"Reset Everything"` (`settings/Panel.lua:635`), or take
      the separate decision to narrow it to `Sl:CliResetAll`. Update `README.md:162` and
      `docs/smoke-tests.md` in the same change.
      — `LH-42`
- [ ] **S4.9** — Decide the two standing advisories: `docs/pending/LEDGER.md` beside the issue
      tracker (`LH-32`) and the unreferenced `media/logos/wowhead-logo.png` (`LH-33`). Both are
      user calls; record whichever way they go.
      — `LH-32`, `LH-33`

---

## Definition of done

- [ ] Every ID in `02_DEVIATIONS.md` is closed, or carried forward with a recorded decision and a
      reason (Sprint 0's output counts as such for `LH-20 … LH-26`).
- [ ] `luacheck .` 0/0; `lua tests/run.lua` green; `docs/test-cases.md` and the README `[tests]`
      badge regenerated together.
- [ ] `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .` run **verbatim**, and a fresh
      `docs/automated-tests/<run>/` bundle written with its `ANALYSIS.md`.
- [ ] Both vendor diffs run and empty (S2.6) — the check this audit could not perform.
- [ ] `docs/audits/<next-date>/` records the re-audit. **This bundle is frozen and is not edited.**
