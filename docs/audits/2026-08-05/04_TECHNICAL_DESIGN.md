# 04 — Technical design (remediation)

How to close each gap in `02_DEVIATIONS.md`. Keyed to deviation IDs. This is a **design**, not a
change: the audit is read-only and the work is a separate engagement, ordered in
`05_EXECUTION_PLAN.md`.

Everything here holds to the same rules the addon is audited against — in particular
`testing-§4` (test-first), `testing-§13` (characterization before a behavior-preserving refactor),
`performance-§11` (permitted refactor shapes) and `library-stack-§7` (anything missing from a
LibKa0s module goes upstream as an **additive** descriptor field, never a local patch).

---

## Group 0 — The decision that has to come first: `LH-20 … LH-26`

Seven of the thirteen MUSTs are one question, and **no code should be written for any of them until
it is answered.** The question is not "is Perf worth wiring here" — the repo already answered that,
with reasoning, at `docs/pending/LEDGER.md` `LIBKA0S-17`. It is: **does `performance`'s
MUST-for-the-wiring survive an addon whose `suspend` destroys user data?**

The standard says the wiring MUST exist *"explicitly independent of whether the addon has a hot
path"*, and the LEDGER's counter-argument is not a shrug — `performance-§6` requires the host to be
inert for the whole of measurement window B, and for this addon inert means **not recording loot
that drops during that fight**. `performance-§7` forbids producing the second arm by disabling the
addon, so there is no escape route through the protocol. A diagnostic that damages the thing it
measures is the one shape the section's own reasoning does not cover.

Three outcomes, and each has a different design:

### Option A — adopt the wiring, with a user-confirmed suspend

The full chain, in dependency order:

1. **`core/PerfSetup.lua`** (new). Standard shape, TOC-listed **before** any module taking
   `local Perf = NS.Perf` as a load-time upvalue — i.e. immediately after `core/CoreSetup.lua` and
   before `core/Database.lua`:

   ```lua
   local lib = LibStub and LibStub("LibKa0s-Perf-1.0", true)
   if not lib then
     NS.Perf = { on = false, Note = function() end, --[[ + every member the slash layer touches ]] }
     return
   end
   NS.Perf = lib:New({ … })
   ```

   The stub must answer **every** member the addon reaches — the gate field `on`, the sink `Note`,
   and whatever the `perf` verb and the show-decision ladder call. A stub missing one is a crash
   moved to a rarer code path (`performance-§1`). Model it on `core/DebugLogSetup.lua:26-72`, which
   is the repo's best example.
2. **`LH-21`** — `## SavedVariables: LootHistoryDB, LootHistoryPerfDB` (`LootHistory.toc:7`), the
   name handed to the descriptor, the store kept outside the AceDB tree.
3. **`LH-26`** — `.luacheckrc`: `debugprofilestop` into `read_globals`, `LootHistoryPerfDB` into
   `globals` with a comment beside `LootHistoryDB`'s. Land this **with** step 2 so the lint gate
   never goes red in between.
4. **`LH-22`** — the `perf` triple appended to `NS.COMMANDS` (`settings/Schema.lua:213-245`),
   dispatching into the library's command entry point and printing the returned lines through
   `NS.Print`. The library **must not** register the verb. `README.md`'s slash table gains the same
   row in the same change (`documentation-§1` item 7).
5. **`LH-23`** — `suspend`/`resume` in the descriptor. Unregister the Collector / Attribution /
   Browser event sets, cancel the three one-shot `C_Timer` calls, refuse at the source in the
   show-decision ladder rather than hiding frames; restore from **current** state on resume; never
   persist the flag; resume **before** saving or reporting. **The data-loss objection is handled
   here, in the host, and it must be handled explicitly**: the suspend path warns and requires
   confirmation, and the `perf` verb's step panel states that window B does not record. Nothing
   about that is invisible to the user.
6. **`LH-24`** — `tests/perf.lua`, outside the green gate, never in `tests/run.lua`'s suite list.
   Assertions on call counts and bytes allocated only, isolated by a full collect either side.
   Ship the **zero-overhead scenario** over the `CHAT_MSG_LOOT` capture path — that is
   `performance-§2`'s required evidence, not a nice-to-have. Derive its load list from the TOC and
   pin the derivation by reading its source (`testing-§9`), which is `LH-29`'s second half.
7. **Buckets.** `performance-§3` wants declared buckets in report order, and a bucket no bracket
   reaches is *"a lie in every report"*. Declare few and real: the `CHAT_MSG_LOOT` capture path
   (`modules/Collector.lua`), attribution resolution (`modules/Attribution.lua`), and the browser
   repaint (`modules/BrowserTable.lua` row bind), the last two `within` nothing since they do not
   nest. Do **not** bracket a settings read. Pin each with a case (`testing-§8`).
8. **`LH-25`** — `docs/performance.md`, pointing at the library for the shared protocol rather than
   restating it, plus **`LH-41`**'s naming correction in `docs/perf-runs/README.md` (which is
   independent — see below).

**Risk.** This is the largest change in the plan by an order of magnitude and it touches the
capture path, which is the addon's reason to exist. `performance-§2`'s bracket idiom is exact for a
reason: `local t0 = Perf.on and debugprofilestop()` … `if t0 then Perf.Note(key, debugprofilestop() - t0) end`,
one upvalue read and one boolean test when off. Any deviation — an `NS` lookup, a key built ahead of
time, a table per call — is anti-pattern #43 and the zero-overhead scenario is what proves it did not
happen.

### Option B — take the contradiction upstream

Draft a `performance` amendment covering the hot-path-free / suspend-destructive case: what an addon
that cannot honestly suspend owes instead. Likely shape — the wiring MUST stands minus `suspend`,
with the addon declaring `suspend = false` in the descriptor and the harness reporting single-arm
captures as such. Record the outcome here either way; a decline with no upstream trace becomes an
undocumented deviation at the next audit.

### Option C — record it as a standing accepted deviation

The status quo, made explicit rather than implicit: the LEDGER row stays, and the addon's own docs
say plainly that `performance` is un-adopted and why. **This is not free under v2.21.0**: the
release gate treats `perf: skip` as a gate that did not pass, and the narrow exception for an addon
shipping no `tests/perf.lua` **MUST be stated in the release notes** (`automated-tests-§3`). That
sentence has to exist somewhere and be rolled forward at each release — which makes `LH-36`
mandatory under this option rather than merely tidy.

**None of `LH-20 … LH-26` should be started before this is chosen.** They are one change with seven
IDs, and half-landing it (a `PerfDB` global with no writer, a `perf` verb with no run) is worse than
not starting.

---

## Group 1 — Independent bugs (`LH-34`, `LH-43`, `LH-27`, `LH-35`)

These four are unrelated to Group 0, small, and each has a user-visible or correctness consequence
today. They are the highest value-per-line work in the plan.

### `LH-34` — the drifted AH priority cascade

**Shape.** Delete the literal from `defaults/Global.lua:36-39` and reference the constant:

```lua
priority = NS.Constants.AUCTION_PRIORITY_DEFAULT,   -- one literal, in core/Constants.lua
```

exactly as `settings.auction.capture` already references `AUCTION_CAPTURE_DEFAULT`.

**Ordering constraint.** `defaults/Global.lua` loads **after** `core/Constants.lua` in the TOC
(`:36-43` vs `:45-46`), so the reference resolves. Confirm rather than assume, and confirm the value
is **copied** rather than aliased into the DB — `settings/Schema.lua:149-151` already documents this
exact hazard for `excludedSources`, and an aliased ordered list mutated by the panel's up/down
arrows would poison the constant for the session.

**Test.** Do not merely assert the two literals are equal — that pins the symptom. Assert the
invariant `AuctionPrice:Pick` depends on: **every** tag derivable from `C.AUCTION_KEYS` appears
exactly once in the seeded priority list. That case fails today, passes after the fix, and keeps
failing if someone adds a twelfth key to `AUCTION_KEYS` and forgets the ordering.

**Risk.** A user whose stored `settings.auction.priority` was seeded with the 7-entry list keeps it
— AceDB does not re-seed an existing table. The four missing tags therefore stay missing for
existing installs, and `ReconcilePriority` (`settings/Panel.lua:431`) is the only thing that would
add them, on AH-Price-page open. If that matters, add a migration step in
`core/Database.lua:RunMigrations` appending any `AUCTION_KEYS` tag absent from the stored list —
**append, never reorder**, since the order is a user choice.

### `LH-43` — the unreachable boot validation

**Shape.** `settings/Schema.lua:194`, `and` → `or`. One character class.

**Risk, and it is the interesting part.** The branch has never run. Flipping it may light up rows
that were silently non-resolving all along — which is the entire point, but it means the change is
"fix the operator **and then read what it prints**", not "fix the operator". Run the suite and a
headless load, and treat every warning it emits as a second finding to triage. If some row
legitimately has no `db.global` path (the `sessionOnly` carve-out at `:193` already handles the
known one), widen that carve-out explicitly with a comment rather than narrowing the condition back.

**Test.** Register a deliberately bad row through `S:Register` and assert the warning is emitted —
**through the boot path**, not by re-asserting the rule the way `tests/test_schema.lua:130-138`
does. That existing case is what let this hide; leave it, and add the one that drives the seam.

### `LH-27` — the dead `ctx.dirty` flag

**Shape.** Stop shadowing the library's bookkeeping. `settings/Panel.lua:329`'s hidden-page branch
routes through `O.RefreshAllPanels` (whose refresh context sets `_dirty` on every hidden ctx) rather
than writing a host-private field; `:146`'s clear and the field itself are deleted.

The host's `rebuilders` list then says only *what* to draw and the library owns *when* — which is
what `options-ui-§11` describes and what the AH Price page's own `OnShow` opt-out
(`settings/OptionsSetup.lua:22-29`) is deliberately carved out of. **Check that carve-out is
unaffected**: the AH Price page does not go through `SetRenderer`, so it must not start depending on
`_dirty` either.

**Test.** Pin the outcome, never the flag: edit a filter list while the Filters page is hidden, show
it, assert the new row is there. A case asserting `ctx._dirty == true` would pass against a library
that renamed the field and still not redraw.

### `LH-35` — the bus fallback

**Shape.** Three one-line changes plus a guard:

```lua
local ev = NS.NewBusTarget()
if ev then
  self.__ev = ev
  ev:RegisterMessage(…)
end
```

at `modules/Collector.lua:217`, `modules/Analytics.lua:657`, `modules/Browser.lua:1366`. The model
is `settings/Panel.lua:130-138`, which already does exactly this.

**Behavior when AceEvent is absent.** Today: three receivers on one target, two of them silently
dead. After: three receivers not registered, and the modules that depend on those messages do not
update. Neither is good, but the second is *honest* and matches how every other LibKa0s-absent path
in this addon behaves. Consider routing an explanatory line through `NS.LIBKA0S_MISSING`'s
sibling — a one-shot notice, on the same pattern as `core/CoreSetup.lua:53-65`.

**Test.** `testing-§8`'s degraded-load technique applies directly: load the addon with AceEvent
missing and assert no two receivers share a target. The bus mock already keys by target
(`architecture-§4`, anti-pattern #33), so the clobber is observable headlessly — which is the whole
reason that mock-fidelity rule exists.

---

## Group 2 — Defaults consolidation (`LH-28`)

**Shape.** Each schema row's `default` reads out of `NS.defaults.global` rather than restating a
literal. Six rows: `settings/Schema.lua:25,52,61,70,77,85`.

Prefer a small read helper over six hand-written path walks — this is `performance-§11`'s permitted
shape 3 (a data table plus one loop) and it removes decisions rather than relocating them. **It is
also the exact refactor `savedvariables-§5` / anti-pattern #54 warns about**: whatever the helper
does, it must test absence with `== nil`, never `or`. `settings.enabled`, `excludeQuestItems` and
`recordCurrency` all default to `true`, so an `or` layer would silently resurrect a setting the user
turned off, and `0`-truthiness means the numeric rows a reader spot-checks would all look fine.

**Ordering.** Land **after** `LH-34`. `LH-34` is a bug fix with a user-visible consequence and
deserves its own reviewable diff; `LH-28` is a mechanical sweep over the same file, and
`performance-§11`'s rule against hiding a behavior change inside a mechanical refactor applies
directly.

**Test.** One case asserting every non-session row's `default` equals the value at its path in
`NS.defaults.global`. That case is the standing tripwire against re-divergence, and it is what would
have caught `LH-34` two releases ago.

---

## Group 3 — Test-harness integrity (`LH-29`, `LH-39`, `LH-40`)

### `LH-29` — pin the derivation

`tests/run.lua` captures the derived list, publishes it via `Kit.expose{ loaded = … }` (`:39`), and
a suite adds `testing-§9`'s three assertions: the loader was fed exactly the TOC's files in the
TOC's order (compare against a fresh `Loader.tocFiles` derivation), every derived path exists on
disk, and no `libs/` path leaked in. Home: `tests/test_libka0s.lua`, or a new `tests/test_runner.lua`
if that suite is getting long. Extend to `tests/perf.lua`'s list **by reading its source** once
`LH-24` lands — the gate does not run it, which is precisely why its list is the one that rots.

### `LH-39` — degraded coverage per module

Generalize `loadDegraded()` (`tests/test_libka0s.lua:51-58`) from Core to all four adopted modules.
The strongest form drives the assertion from the **live** seam's export list rather than a
hand-copied member list, so a member added to a seam next year fails the case instead of quietly
widening the gap. Add `HelpHeader` to the Slash stub. For `ConsoleCheckbox`, either delete it from
the DebugLog stub or write down why it is there — `AUDIT.md` is explicit that a stub omitting (or
carrying) a member **with the reason written down** is a decision rather than a gap, and the cheapest
fix here is the comment.

### `LH-40` — make the vendor gate fail when it cannot look

`testing-§11` is unambiguous: *"MUST fail, not pass, when the gate cannot run"*. Split
`tests/test_vendor_sync.lua` into one case that asserts the sibling checkout is reachable — failing
with the path it looked for — and the two sync cases behind it. If a machine without the sibling
must stay green, that is a **skip the runner records with its reason**, not a passing test case.
Correct the header's `.gitattributes` claim at `:28-32` in the same change.

**Why this one matters more than its severity suggests:** it is the check that catches anti-pattern
#45, whose defining property is that **both repos stay green** while the copies diverge. A gate that
also stays green when it cannot look has the same failure mode as the bug it exists to catch.

---

## Group 4 — Docs (`LH-36`, `LH-37`, `LH-38`, `LH-41`, `LH-19`, `LH-44`)

All small, all independent of Groups 0–3, and all safely landable in one documentation pass.

- **`LH-36`** — add the release-gate half to `docs/testing.md:167-176`,
  `docs/automated-tests/README.md` and `docs/automated-tests/RESULTS.md`'s header note. The wording
  must keep both checkpoints straight: **commits** are gated on lint + the harness and nothing else
  (a threshold on every commit is routed around with `--no-verify`); the **tag** is gated on all
  four suites plus `suites.complexity.warnings == 0`, evaluated by the release command from the
  run's `manifest.json`, never by the runner — whose exit code is deliberately unchanged because the
  same script is the commit gate. A `skip` blocks as NOT EVALUATED. State this addon's standing
  `perf: skip` exception explicitly, and require it in the release notes until `LH-24` lands.
  **Caution:** `RESULTS.md` is generated. Change it where the generator reads it, not by hand.
- **`LH-37`** — either disposition `modules/Browser.lua` on its own terms (it is genuinely peelable
  at the dropdown-widget-kit seam, which the existing disposition already names) or open a tracked
  deviation for it and cite that ID. Same generated-file caution.
- **`LH-38`** — reduce `CLAUDE.md` to the five required items plus the pointer list. The `## Hard
  rules` content is durable and mostly already duplicated in `docs/ARCHITECTURE.md`'s Module map /
  Settings schema / Message bus sections — move what is not, delete what is. Drop `## Response
  style` and the `agent-context.md` essay; the latter argues at length against a file that has not
  existed here for four standard versions, which is itself the drift the stub rule exists to
  prevent. **Do not touch `## Standards compliance (read first)`** — it is one of the three required
  places (`documentation-§6`) and it is correct.
- **`LH-41`** — restate `docs/perf-runs/README.md`'s convention as
  `<YYYY-MM-DD>-ingame-<label>.json`, flat. Keep the "say what the client was doing" requirement,
  as a field in the record or a sibling note. Independent of Group 0 — fixable today.
- **`LH-19`** — two comment lines: `settings/OptionsSetup.lua:101` `§3.4` → `library-stack-§4`;
  `tests/test_database.lua:390` `§2.2/§5.1` → `toc-file-§2` / `savedvariables-§1`.
- **`LH-44`** — delete the stale `-- luacheck: ignore addonName` at `modules/AuctionPrice.lua:1`.
  Verify `luacheck .` stays 0/0 (it will — `.luacheckrc:14` covers the case globally and the
  variable is used anyway).

---

## Group 5 — Behavior-adjacent polish (`LH-30`, `LH-42`)

### `LH-30` — delegate the window edge

`modules/Browser.lua` reaches Core via `LibStub("LibKa0s-Core-1.0", true)` and `B:ApplySkin` calls
`Core.ApplySkin(frame, skinOverride)`, keeping only the host-specific fields (`titleBarH`,
`tabStripH`, `contentGap`, `defaultH`, `minH`, `tabActive`, `tabIdle`) in `B.SKIN`.

**Behavior-neutral by construction today** — `core/CoreSetup.lua:10-19` records that the two agree
value for value as of Core minor 3 — which is exactly why it is worth doing now rather than after
they disagree.

**Two constraints.** Core must be resolved with the silent flag and guarded, so the degraded path
still draws *something*; and `core/DebugLogSetup.lua:117-119` routes the library's own console
through `B:ApplySkin`, so the change reaches two more windows than it looks like it does. Smoke-test
all three (`docs/smoke-tests.md`), and keep `core/DebugLogSetup.lua:120-131`'s deliberate refusal of
`makeCloseButton` untouched — that is a compliance result, not an oversight.

### `LH-42` — the "Reset All" button

Cheapest correct fix: rename to `"Reset Everything"` at `settings/Panel.lua:635`. The alternative —
narrowing it to `Sl:CliResetAll` and leaving history destruction to `/lh purge` — is a **behavior
change** and needs its own decision; the button has meant "settings and history" for three releases
and someone may rely on it. Either way, `README.md:162`'s Troubleshooting row and
`docs/smoke-tests.md`'s entry move in the same change.

---

## Cross-cutting risks

- **`RESULTS.md` is generated.** `LH-36` and `LH-37` both touch it. `performance-§10` is explicit
  that a **hand-edited** record is worse than a wrong one, because it reads as measured. Change the
  generator, then regenerate — never edit the numbers, and never edit a frozen bundle.
- **Frozen artifacts.** `docs/audits/*` and `docs/automated-tests/<run>/` are never edited after the
  fact. Remediation writes a **new** bundle; it does not amend this one.
- **The green gate stays green at every step.** `testing-§4`: `lua tests/run.lua` + `luacheck .`
  before every commit. Every step in `05_EXECUTION_PLAN.md` is sized to be committable on its own.
- **Regenerate the inventory and the badge together.** Several steps add cases. `testing-§5`
  requires `lua tests/run.lua --list > docs/test-cases.md` and the README `[tests]` badge to move in
  the **same** change, never as a follow-up.
- **The vendor diff was not run this run.** Before any release, run both halves manually — or land
  `LH-40` first, which makes the suite answer honestly and removes the need to remember.
