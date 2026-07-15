# Design — Test-case inventory doc + coverage badge (addon + standard)

**Date:** 2026-07-15
**Status:** Approved design, pre-implementation
**Scope:** two repos — the **LootHistory** addon, and the **WowAddonStandards** standard (a source-of-truth change).

## Problem

The addon has a headless test suite (currently **166** cases across 9 suites) but no single
document that enumerates *which* cases exist, and no at-a-glance signal of test health in the
README. Worse, the counts that *are* recorded have already drifted: `docs/testing.md` claims
"152 tests" / `152 passed` while the runner actually reports **166**. Hand-maintained counts rot.

The user wants:

1. A `docs/test-cases.md` enumerating **all** test cases that exist.
2. A documented instruction to **update that doc every time the test cases fail** (i.e. whenever
   the suite changes while resolving a failure).
3. A README **badge** showing test coverage as **X/Y pass**.
4. All of the above promoted to a **MUST** in the Ka0s WoW Addon Standard.

**No CI.** (Considered and explicitly rejected — overkill for these projects.) The badge is
hand-maintained; the inventory doc is generated on demand by a local command.

## Decisions (locked)

- **Generator, not hand-authored.** Enumerating 166 case names by hand is exactly what drifts.
  `docs/test-cases.md` is produced by a `--list` mode of the existing runner and committed.
- **Full enumeration.** Every individual case name, grouped under its suite, with per-suite and
  grand totals — literally "all the test cases that exist".
- **Single source of truth for the count.** `docs/test-cases.md` owns the authoritative pass count.
  `docs/testing.md` drops its own `152` numbers and points at the inventory (this fixes the
  existing drift by construction).
- **Static, hand-maintained badge.** A shields.io static badge in the README, consistent with the
  repo's other static badges (wow / license / Standard). Updated by hand when the count changes.
- **No CI.** Enforcement is documented discipline (the update-on-change rule), not a pipeline.

---

## Part A — LootHistory addon

### A1. Runner: suite attribution + `--list` mode

`tests/run.lua` changes (small, contained):

- **Attribute each test to its suite.** The runner `dofile`s the 9 suites in a fixed order and
  accumulates all `test(name, fn)` registrations into one flat list. Add suite tracking: before
  each suite `dofile`, record the suite filename and snapshot `#tests`, so every registered case
  knows its originating suite. (Implementation detail — snapshot boundaries around each `dofile`,
  or set a `currentSuite` upvalue that `test()` stamps onto the record. Either is fine; the
  boundary-snapshot approach needs no change to `test()`.)
- **`--list` mode.** When invoked as `lua tests/run.lua --list`, the runner does **not** execute
  tests — it emits `docs/test-cases.md`'s body to stdout as Markdown: one `### <suite>.lua (N)`
  heading per suite, each case name as a bullet, followed by the totals table and grand total.
- **Default mode is unchanged** — `lua tests/run.lua` still runs everything and prints
  `PASS/FAIL` + the `N passed, N failed, N total` tail and the non-zero exit gate.

The `--list` output is deterministic (suite order fixed, registration order preserved) so
regenerating and diffing is stable.

### A2. `docs/test-cases.md` (new)

Generated file, committed. Structure:

```
# Test Cases

<one-line intro: what this is, and the command that regenerates it>

### test_util.lua (23)
- <case name>
- ...

### test_compat.lua (11)
...

## Totals

| Suite | Cases |
|-------|------:|
| test_util | 23 |
| ...   | ... |
| **Total** | **166** |
```

Suite counts at time of writing (grand total **166**):

| Suite | Cases |
|-------|------:|
| test_util | 23 |
| test_compat | 11 |
| test_attribution | 20 |
| test_collector | 15 |
| test_database | 33 |
| test_stats | 13 |
| test_browsertable | 15 |
| test_debuglog | 16 |
| test_slash | 20 |
| **Total** | **166** |

This file is the **authoritative pass count** for the addon.

### A3. `docs/testing.md` — de-duplicate the count

- Remove the stale hard-coded numbers ("Nine files … **152 tests**", the `152 passed …` status
  line, the `# 152 passed` comment in the green-gate block).
- Replace the "The suites" table's count claim and the "Current status" section with a pointer to
  `docs/test-cases.md` for the authoritative inventory and count. Keep the harness/loader/mock/
  framework prose (the "how"); `test-cases.md` is the "what".
- Add the **update-on-change rule** here (see A5).

### A4. README badge (static, hand-maintained)

Add a tests badge to the README badge row (per the standard's badge-row order — after the
published-version badge, near license):

```markdown
![tests](https://img.shields.io/badge/tests-166%2F166_passing-brightgreen)
```

Rendered: `tests | 166/166 passing`. Updated by hand whenever the count changes.

### A5. The update-on-change discipline (documented rule)

The trigger the user described — *update the doc every time the test cases fail* — documented as a
hard rule in **three** agent-facing places, phrased so the intent is unambiguous:

> Whenever the test suite changes — a case added, removed, or renamed, or the pass count moves
> (which is exactly what resolving a test failure does) — regenerate `docs/test-cases.md` via
> `lua tests/run.lua --list` **and** update the README `tests` badge count to match. The inventory
> doc and the badge are part of the change, not a follow-up.

Placed in:

- `CLAUDE.md` — a bullet under **Hard rules**.
- `docs/agent-context.md` — the working brief's hard-rules/testing area.
- `docs/testing.md` — its own short section (the natural home for the "how").

---

## Part B — WowAddonStandards (source-of-truth change)

This promotes the addon-side work to a normative **MUST** for every Ka0s addon. **No CI is
mandated** — the standard requires the inventory doc, the badge, and the update rule, all locally
maintained.

### B1. `standards/standards/testing.md` — new subsection §5

Add **§5 — Test-case inventory & coverage badge (MUST)**:

- **MUST** ship `docs/test-cases.md` — a **generated** full enumeration of every test case, grouped
  by suite, with per-suite and grand totals. It **MUST** be produced by a `--list` (or equivalent)
  mode of the headless runner, not hand-authored, and is the **authoritative pass count** for the
  addon.
- **MUST** surface an **X/Y pass** tests badge in the README (static shields.io badge, in the badge
  row). Hand-maintained; **MUST NOT** require CI.
- **MUST** keep both in sync: whenever the suite changes (a case added/removed/renamed or the count
  moves — i.e. whenever a failing test is resolved), regenerate `docs/test-cases.md` and update the
  README badge **as part of the same change**.
- Cross-reference: this complements testing-§4 (TDD & the commit gate) — the green gate proves the
  suite passes; the inventory + badge make the coverage *visible and honest*.

### B2. `standards/standards/documentation.md` — ripple

- **Badge row (§1 #2):** add the **tests X/Y badge** to the canonical badge-row order.
- **Testing section (§1 #11):** note that the README Testing section references the generated
  `docs/test-cases.md` inventory and that the badge is hand-maintained.
- **`docs/` set (§3):** `docs/test-cases.md` is currently in the "MAY ship topic-detail docs"
  bucket, which §3 says the standard does *not* fix. Since testing-§5 now **requires** it, add a
  one-line note in §3 that `docs/test-cases.md` is a **required** topic-detail doc (see testing-§5),
  resolving the tension. **(Flag for user at review: keep it as a noted required topic-detail doc,
  vs. promote it into the canonical trio in §3 — recommend the former, lighter, note.)**

### B3. `standards/NEW_ADDON_CONTEXT.md` — template pack

The context pack derives from the standard (STANDARDS.md: "NEW_ADDON_CONTEXT.md template content
derives from this standard"). Add the inventory-doc + badge + update-rule expectations to the
pack's testing/docs guidance so newly-scaffolded addons are born compliant.

### B4. `standards/STANDARDS.md` — version + date bump

Per the standard's own rule ("When the standard changes, bump the date and version"), bump
**v1.12.0 → v1.13.0**, date **2026-07-15**. (Additive normative requirement → minor bump.)
The `EXECUTIVE_SUMMARY.md` and any MUST-enumerating surfaces are checked and updated if they list
per-section requirements.

### B5. Deviation-rule note

The LootHistory addon and the standard are updated **together** in this work, so the addon does not
become non-compliant. Other existing Ka0s addons will surface this new MUST on their next
`wow-addon:standards-audit` — expected and acceptable (the standard is the living source of truth).

---

## Out of scope (YAGNI)

- CI of any kind (workflow, freshness gate, dynamic/endpoint badge, gist). Explicitly rejected.
- Line-coverage measurement (the request is test **pass-count** X/Y, not % lines covered).
- Auto-updating the README badge count from the runner (badge is hand-maintained by decision).

## Verification

- `lua tests/run.lua` — still green, `166 passed, 0 failed, 166 total`.
- `lua tests/run.lua --list` — emits the inventory; committed `docs/test-cases.md` matches it.
- `luacheck .` — 0 errors (runner change stays lint-clean; `tests/` is excluded from lint anyway).
- README badge renders `166/166 passing`; `docs/testing.md` no longer carries a competing count.
- Standard: testing-§5 present; documentation.md badge-row/§3 updated; NEW_ADDON_CONTEXT.md +
  STANDARDS.md version bumped.
