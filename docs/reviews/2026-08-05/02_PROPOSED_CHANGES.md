# 02 — Proposed changes (HLD + LLD)

Derived from `01_FINDINGS.md`. Standard resolved for this review: **Ka0s WoW Addon Standard
v2.21.0 (2026-08-04)**, fetched from
`https://raw.githubusercontent.com/tusharsaxena/WowAddonStandards/master` (index plus all 26 section
files under `standards/standards/`). Every change below was checked against it; the rules that
shaped or vetoed a choice are cited inline as `filename-§N`.

**No change in this document targets a path under `libs/` or `tests/_kit/`.** There are no
`[upstream]` findings in this review, so there is no upstream change-set section — the vendored
`libs/LibKa0s/` and `tests/_kit/` copies were verified byte-identical to `../LibKa0s` at `v1.7.0` by
`tests/test_vendor_sync.lua`, and no defect was found in either.

---

## HLD — themes

### Theme A — One declaration per default (F-001, F-002)

Two independent statements of the same default value is a drift generator, and the addon already has
one live drift (the AH priority cascade) plus a runtime check that would have caught it but cannot
fire. The theme is to collapse `defaults/Global.lua`'s auction block onto `core/Constants.lua`'s
constants, repair the boot check so it actually validates, and widen the suite's equality case to
cover the table rows and the carve-out array it currently steps around.

*Rationale.* `savedvariables-§2` makes the defaults file the single place a default is hard-coded and
has schema rows reference those constants. Today the direction is inverted for the auction block: the
constants are authoritative for the schema and the panel, and the defaults file re-types them by
hand.

*Alternatives considered.*
- **Call `ReconcilePriority` from `InitDB`.** Rejected: it repairs the symptom on every login while
  leaving two declarations in place, and it moves a settings mutation into the migration path where
  `savedvariables-§1`'s "normalize before any history read" contract does not want it.
- **Delete `AUCTION_PRIORITY_DEFAULT` and make the defaults file authoritative.** Rejected:
  `settings/Panel.lua:768` and `modules/AuctionPrice.lua:53,91` read the constant, and
  `core/Constants.lua` is where `AUCTION_KEYS` — the thing the cascade is an ordering *of* — already
  lives. Cohesion wins.
- **Deep-compare defaults against constants in `Register` and print on mismatch.** Rejected as the
  *primary* fix: it is a runtime warning for a condition the type system of the repo (one constant,
  referenced twice) can make impossible. Kept only as the widened test.

*Trade-off.* `defaults/Global.lua` becomes slightly less self-describing — a reader has to follow one
hop to see the actual tag list. Mitigated with a comment naming the constant.

### Theme B — The degraded install is a first-class install (F-003, F-006, F-010)

Three separate places where the "library or API is missing" path is looser than the healthy one: a
fallback that re-creates a forbidden pattern, a stub whose member set is maintained by hand, and a
fallback that answers a question with less than it knows. The theme is to make the degraded path
obey the same rules and be checked by the same kind of test.

*Rationale.* `architecture-§4` and `anti-patterns #32` are unconditional — there is no "unless
AceEvent is missing" clause. `anti-patterns #47` makes the stub, not the implementation, the addon's
half of the library contract, so the stub's surface is exactly as load-bearing as a descriptor field.

*Alternative considered.* **Leave the `or bus` fallbacks alone because AceEvent is vendored.**
Rejected: the whole point of the fallback is the install where the vendoring failed, and in that
install it does the forbidden thing silently. Registering nothing is strictly better — the addon
loses live settings propagation, which is what it has already lost, instead of losing collection
correctness, which it had not.

### Theme C — Say what a green case actually proved (F-005)

One narrow change: two cases that can pass vacuously should name the condition in their titles and
report the skip. The inventory (`docs/test-cases.md`) is generated from those titles, so the name is
the only place a reader of the inventory can learn it.

*Rationale.* `testing-§12` (unfalsifiable cases). This is the sanctioned shape of the fix — disclose,
never weaken.

### Theme D — Truthful comments and labels (F-004, F-007, F-008)

Three cosmetic corrections that each cost a reader real time: a UI label that promises a settings
reset and delivers a history wipe, two comments naming a reader that does not exist, and a lint
suppression for a warning that cannot occur.

### Theme E — Deferred (F-009)

Not proposed for this cycle. See `05_FINAL_SUMMARY.md` "Known follow-ups".

---

## LLD — change-set

### C-01 — Single-source the auction defaults `[F-001]`

**Files:** `defaults/Global.lua`

`core/Constants.lua` loads before `defaults/Global.lua` in the TOC (`LootHistory.toc`, `# Core` block
then `# Defaults` block), so `NS.Constants` is available.

Before (`defaults/Global.lua:29-40`):

```lua
    auction = {
      enabled = true,
      capture = {
        ["auctionator:minbuyout"] = true, ["tsm:dbmarket"] = true, ["tsm:dbminbuyout"] = true,
        ["tsm:dbregionmarketavg"] = true, ["tsm:dbregionminbuyoutavg"] = true,
        ["oribos:market"] = true, ["oribos:region"] = true,
      },
      priority = {
        "tsm:dbmarket", "auctionator:minbuyout", "oribos:market",
        "tsm:dbminbuyout", "tsm:dbregionmarketavg", "tsm:dbregionminbuyoutavg", "oribos:region",
      },
    },
```

After — one declaration, copied so AceDB's merge can never hand a caller the constant itself:

```lua
    auction = {
      enabled = true,
      -- ONE declaration. core/Constants.lua owns both tables (it also owns AUCTION_KEYS, which the
      -- cascade is an ordering of); this file copies them so the stored value is never an alias of
      -- the constant. savedvariables-§2: a default is hard-coded in exactly one place.
      capture  = copySet(NS.Constants.AUCTION_CAPTURE_DEFAULT),
      priority = copyArray(NS.Constants.AUCTION_PRIORITY_DEFAULT),
    },
```

with two four-line file-local helpers above `NS.defaults.global`. The copy is not optional:
`modules/AuctionPrice.lua:121-136` (`ReconcilePriority`) and `settings/Panel.lua:768-771` rewrite the
priority array **in place**, so an aliased default would be mutated for the session.

**Risk:** a fresh install now stores 11 priority tags instead of 7. Existing installs are unaffected
(AceDB does not re-seed a present key) and continue to be repaired by `ReconcilePriority` when the AH
Price page is opened — which is the current behavior, not a new one. No migration step is needed:
nothing reads a *position* out of the array, only membership and order, and both are already
reconciled.

**Standards conformance:** implements `savedvariables-§2`. Does not introduce an `or`-default
(`savedvariables-§5` / `anti-patterns #54`) — the values are assigned unconditionally at declaration.

### C-02 — Make `Schema:Register`'s boot check able to fail `[F-002]`

**Files:** `settings/Schema.lua`

Before (`:194`):

```lua
    if not row.sessionOnly and S:ReadPath(g, row.path) == nil and row.default == nil then
```

After:

```lua
    -- `or`, not `and`: a path with no entry in defaults/Global.lua is a defect whether or not the
    -- row also carries its own `default`, and the `and` form could never fire (every row declares
    -- one). See docs/reviews/2026-08-05, F-002.
    if not row.sessionOnly and (S:ReadPath(g, row.path) == nil or row.default == nil) then
```

**Risk:** the branch becomes reachable, so a genuine drift now prints one line at login through
`NS.Print`. That is the intent. `tests/test_schema.lua:130-138` already proves no such row exists
today, so the line cannot appear on a correct build.

**Standards conformance:** the message goes through the file-scope `local print = NS.Print`
(`settings/Schema.lua:5`), i.e. the cyan `[LH]` tagged, secret-safe printer — `slash-commands-§4`,
`events-frames-taint-§8`. A raw `print` here would be `anti-patterns #35`'s neighbourhood.

### C-03 — Remove the shared-bus fallback at both receivers `[F-003]`

**Files:** `modules/Collector.lua`, `modules/Browser.lua`

Before — `modules/Collector.lua:494`:

```lua
  self.__ev = NS.NewBusTarget() or bus
  self.__ev:RegisterMessage("Ka0s_LootHistory_SettingsChanged", function(_, _reason)
```

After:

```lua
  -- No `or bus` fallback: two receivers on the shared object is last-registrant-wins
  -- (architecture-§4, anti-patterns #32), and Browser:Enable registers the same message right
  -- after this one. With AceEvent absent the addon loses live settings propagation, which is
  -- strictly better than losing it silently in the collector only.
  self.__ev = NS.NewBusTarget()
  if self.__ev then
    self.__ev:RegisterMessage("Ka0s_LootHistory_SettingsChanged", function(_, _reason)
      self:RefreshUpvalues()
    end)
  end
```

Same shape at `modules/Browser.lua:1366-1369` for its three registrations, matching
`settings/Panel.lua:130-138`'s existing `if ev then` treatment.

**Risk:** none on a normal install (`NS.NewBusTarget` returns a fresh embed whenever AceEvent
resolves, and AceEvent is TOC-loaded at `LootHistory.toc`'s `# Libraries` block). Behavior changes
only in the install where AceEvent is missing, and changes from "wrong" to "absent".

**Standards conformance:** implements `architecture-§4` / `anti-patterns #32`.

### C-04 — Relabel the panel's destructive reset `[F-004]`

**Files:** `settings/Panel.lua`

`settings/Panel.lua:635` — `makePairButton("Reset All", …)` → `makePairButton("Reset Everything…", …)`.
The ellipsis follows the file's own convention for confirm-gated actions (`"Purge history…"`,
`settings/Panel.lua:103`). The popup body (`settings/Slash.lua:20`) already spells out what it does
and is unchanged; `/lh resetall` is unchanged.

**Risk:** cosmetic only. `tests/test_panel.lua` asserts on the landing/General page contents — the
button text is checked there if at all; the smoke test covers the rendered label.

**Standards conformance:** `slash-commands-§3` reserves `resetall`'s meaning collection-wide; this
change removes the label that contradicts it. Rejected alternative: **make `/lh resetall` purge
history too** — that would put the collection-reserved verb out of step with every sibling addon,
which is the deviation the rule exists to prevent.

### C-05 — Disclose the vendor-sync skip in the case names `[F-005]`

**Files:** `tests/test_vendor_sync.lua`

`:138` → `test("libs/LibKa0s matches the release the README names, when the sibling checkout is
present", …)`; `:144` → `test("tests/_kit matches the kit that shipped with that release, when the
sibling checkout is present", …)`. In both bodies, replace the bare `if not tag then return end`
with a one-line note printed through the kit's own output before returning, so a skipped run says so
in the log as well as in the name.

**Risk:** `docs/test-cases.md` must be regenerated in the same change (`testing-§7`) — the case
titles are the inventory. The pass **count** does not move (still 579), so the README `[Tests]`
badge does not move.

**Standards conformance:** `testing-§12`. Explicitly **not** proposed: deleting the guard, or making
a missing sibling fail the suite — the file's header at `:7-12` gives the correct reason it must not.

### C-06 — Check every stub's surface, not just Core's `[F-006]`

**Files:** `tests/test_libka0s.lua`, `settings/Slash.lua`, `core/DebugLogSetup.lua`

Add one case: for each of the four seam files, grep the addon's own `.lua` files under `core/`,
`modules/` and `settings/` for `NS.<Seam>[.:]<member>` (and, for Options, the `local O = NS.Options`
alias used in `settings/Panel.lua:10`), and assert the degraded stub's table answers every member
found. Then act on what it reports:

- `settings/Slash.lua:141` — add `Sl.HelpHeader = function() return "" end` to the degraded branch.
- `core/DebugLogSetup.lua:84-91` — remove `ConsoleCheckbox` from the stub once the case confirms no
  addon file calls it (the console checkbox is the `state.debugConsole` schema row).

**Risk:** the grep-based case is source-reading, like the existing `L`-trap case at
`tests/test_libka0s.lua:135-158`, so it inherits that case's tolerance for spelling. Keep it
conservative — a member it cannot see is a member it does not assert, never a false red.

**Standards conformance:** `anti-patterns #47` (the stub is the reviewed half of the contract);
`testing-§8` (this is integration coverage over the addon's own wiring, not a re-test of library
behavior). The stub gains **no** re-implemented library formatter — `HelpHeader` returns empty, it
does not render a header.

### C-07 — Correct two comments and drop one suppression `[F-007, F-008]`

**Files:** `settings/Slash.lua`, `modules/AuctionPrice.lua`

- `settings/Slash.lua:111-112` and `:165-167`: replace "settings/Panel.lua and the suite" with "the
  suite" (the true and still-sufficient reason these stay public).
- `modules/AuctionPrice.lua:1`: `local addonName, NS = ...   -- luacheck: ignore addonName` →
  `local addonName, NS = ...` (used at `:17-18`).

**Risk:** none. `luacheck .` must stay at 0/0 — verified today that `addonName` is read, so removing
the suppression cannot produce an unused-variable warning.

**Standards conformance:** `lint`. No new suppression is introduced anywhere.

### C-08 — Print the still-working verbs on a degraded install `[F-010]`

**Files:** `settings/Slash.lua`

In the degraded `Sl:OnSlash` (`:150-157`), when no `NS.COMMANDS` entry matches, print the cause
clause **and then** one line per host verb, built from `NS.COMMANDS`' own `{ name, description }`
positions rather than a second hard-coded list.

**Risk:** the seven host verbs are not the seven the healthy help renders — the schema verbs
(`get`/`set`/`list`/`reset`/`resetall`/`version`/`help`) are in `NS.COMMANDS` too but answer
`unavailable()`. Print the whole table and let each verb speak for itself; do not filter, or the
filter becomes a second list to maintain.

**Standards conformance:** `NS.LIBKA0S_MISSING` stays verbatim — `tests/test_libka0s.lua:30-34` pins
it and the whole point of the clause is that it reads identically from every Ka0s addon. The rows are
**not** rendered through a locally re-implemented `FormatRow` (`anti-patterns #47`): with the library
absent there is nothing to converge on, so a plain `"  <name> — <desc>"` is correct here and must not
be back-ported into the healthy path.

---

## Test and inventory movement expected from this change-set

| Change | Cases added | Pass count | `docs/test-cases.md` | README `[Tests]` badge |
|---|---|---|---|---|
| C-01 | +1 (defaults priority == `AUCTION_PRIORITY_DEFAULT`), +1 (widen `:140` to table rows) | 579 → **581** | regenerate | update |
| C-02 | +1 (`Register` prints for a row absent from defaults) | +1 → **582** | regenerate | update |
| C-03 | +1 (each receiver owns a distinct target; none is `NS.bus`) | +1 → **583** | regenerate | update |
| C-05 | 0 (titles change) | 583 | **regenerate — titles moved** | unchanged |
| C-06 | +1 (every stub answers every member called) | +1 → **584** | regenerate | update |
| C-08 | +1 (degraded bare `/lh` lists the host verbs) | +1 → **585** | regenerate | update |

`testing-§7`: `docs/test-cases.md` and the badge move **in the same change** that moves the count —
never as a follow-up. Regeneration is `lua tests/run.lua --list > docs/test-cases.md`; it is never
hand-edited.

## Complexity movement expected

None of C-01…C-08 adds a branch to a function on the CCN watch. `settings/Schema.lua:194` gains one
decision (`and` → `and (… or …)`) inside `S:Register`, which today is far below the cap. The next
release's `lizard` regeneration should confirm the six functions at CCN 15 are unmoved and the
warning count stays 0 — a note for the release run (`/wow-addon:bump-version`), not a task here.
