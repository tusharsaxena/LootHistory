# Test-Case Inventory + Coverage Badge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a generated `docs/test-cases.md` inventory of every test case, a static X/Y README badge, an update-on-change discipline, and promote all three to a MUST in the Ka0s WoW Addon Standard.

**Architecture:** The addon's headless runner (`tests/run.lua`) gains suite attribution and a non-executing `--list` mode that emits the inventory as Markdown; `docs/test-cases.md` is that command's committed output and the authoritative pass count. `docs/testing.md` drops its stale hard-coded counts and points at the inventory. A static shields.io badge goes in the README. The standard (`WowAddonStandards` repo) gets a new `testing-§5` MUST plus documentation ripple and a version bump. No CI.

**Tech Stack:** Lua 5.1 (headless test harness), shields.io static badges, Markdown docs. Two git repos: `LootHistory` (cwd) and `../../WowAddonStandards` (sibling — absolute path `/mnt/d/Profile/Users/Tushar/Documents/GIT/WowAddonStandards`).

## Global Constraints

- Addon runner targets **Lua 5.1**; run everything from the addon repo root.
- Green gate before any addon commit: `lua tests/run.lua` (all green) **and** `luacheck .` (0 errors). `tests/` is excluded from lint, but run it anyway.
- Suite order is fixed and load-order-sensitive: `test_util, test_compat, test_attribution, test_collector, test_database, test_stats, test_browsertable, test_debuglog, test_slash`.
- Current totals: **166** cases (util 23, compat 11, attribution 20, collector 15, database 33, stats 13, browsertable 15, debuglog 16, slash 20). These will be regenerated, not hand-typed — do not hard-code them into the doc.
- `docs/test-cases.md` is **generated** — the file body is exactly `lua tests/run.lua --list` stdout. Never hand-edit it.
- Badge is **static and hand-maintained**. No CI, no dynamic/endpoint/gist badge, no GitHub Actions.
- Standard version bump is **v1.12.0 → v1.13.0**, date **2026-07-15**.
- Do not restructure unrelated files. Follow existing doc tone.

---

### Task 1: Runner — suite attribution + `--list` mode

**Files:**
- Modify: `tests/run.lua`

**Interfaces:**
- Produces: `lua tests/run.lua --list` → prints the full inventory Markdown to stdout and `os.exit(0)` without running tests. Default `lua tests/run.lua` behaviour (run + `PASS`/`FAIL` + `N passed, N failed, N total` tail + non-zero exit on failure) is unchanged.

> **Note on TDD:** this task modifies the test *runner itself*, so it has no separate unit test — the runner cannot cleanly assert on its own CLI. Verification is running both modes and eyeballing output (Steps 4–6). This is the one justified deviation from the write-a-failing-test-first loop; every later addon task that touches product/doc content keeps normal verification.

- [ ] **Step 1: Add suite tracking to the framework block**

In `tests/run.lua`, replace:

```lua
local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end
```

with:

```lua
local tests = {}
local currentSuite = nil
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn, suite = currentSuite } end
```

- [ ] **Step 2: Drive the suite dofiles through a named loop**

Replace the explicit `dofile("tests/test_*.lua")` block (the nine lines under `-- --- load test suites ---`) with:

```lua
-- --- load test suites (order is load-order-sensitive; keep as-is) ---
local SUITE_FILES = {
  "test_util.lua", "test_compat.lua", "test_attribution.lua",
  "test_collector.lua", "test_database.lua", "test_stats.lua",
  "test_browsertable.lua", "test_debuglog.lua", "test_slash.lua",
}
for _, s in ipairs(SUITE_FILES) do
  currentSuite = s
  dofile("tests/" .. s)
end
currentSuite = nil
```

- [ ] **Step 3: Add the `--list` branch before the run loop**

Immediately **after** the suite-loading loop and **before** the `-- --- run ---` loop, insert:

```lua
-- --- inventory mode: emit docs/test-cases.md and exit without running ---
if arg and arg[1] == "--list" then
  local order, byS = {}, {}
  for _, t in ipairs(tests) do
    if not byS[t.suite] then byS[t.suite] = {}; order[#order + 1] = t.suite end
    local b = byS[t.suite]; b[#b + 1] = t.name
  end
  print("# Test Cases")
  print("")
  print("The full inventory of every headless test case, grouped by suite. This file is the")
  print("**authoritative pass count** for the addon.")
  print("")
  print("**Generated — do not hand-edit.** Regenerate with `lua tests/run.lua --list > docs/test-cases.md`")
  print("whenever the suite changes (see [testing.md](testing.md)).")
  print("")
  for _, s in ipairs(order) do
    local b = byS[s]
    print(string.format("### %s (%d)", s, #b))
    print("")
    for _, n in ipairs(b) do print("- " .. n) end
    print("")
  end
  print("## Totals")
  print("")
  print("| Suite | Cases |")
  print("|-------|------:|")
  for _, s in ipairs(order) do print(string.format("| %s | %d |", s, #byS[s])) end
  print(string.format("| **Total** | **%d** |", #tests))
  os.exit(0)
end
```

- [ ] **Step 4: Verify default mode still passes**

Run: `lua tests/run.lua | tail -3`
Expected: ends with `166 passed, 0 failed, 166 total`.

- [ ] **Step 5: Verify `--list` mode emits the inventory**

Run: `lua tests/run.lua --list | head -20`
Expected: `# Test Cases` header, then `### test_util.lua (23)` and case bullets. No `PASS`/`FAIL` lines.

Run: `lua tests/run.lua --list | tail -14`
Expected: the `## Totals` table ending with `| **Total** | **166** |`.

- [ ] **Step 6: Lint**

Run: `luacheck .`
Expected: `0 warnings / 0 errors`.

- [ ] **Step 7: Commit**

```bash
git add tests/run.lua
git commit -m "test(runner): suite attribution + --list inventory mode"
```

---

### Task 2: Generate `docs/test-cases.md`

**Files:**
- Create: `docs/test-cases.md` (generated)

**Interfaces:**
- Consumes: `lua tests/run.lua --list` from Task 1.

- [ ] **Step 1: Generate the file**

Run: `lua tests/run.lua --list > docs/test-cases.md`

- [ ] **Step 2: Verify it matches the generator (freshness self-check)**

Run: `diff <(lua tests/run.lua --list) docs/test-cases.md && echo IN-SYNC`
Expected: `IN-SYNC` (no diff).

- [ ] **Step 3: Sanity-check the content**

Run: `grep -c '^- ' docs/test-cases.md` → Expected: `166`.
Run: `grep 'Total' docs/test-cases.md` → Expected row contains `**166**`.

- [ ] **Step 4: Commit**

```bash
git add docs/test-cases.md
git commit -m "docs: generated test-case inventory (166 cases)"
```

---

### Task 3: De-duplicate the count in `docs/testing.md` + add the update rule

**Files:**
- Modify: `docs/testing.md`

**Interfaces:**
- Consumes: `docs/test-cases.md` (the authoritative count) from Task 2.

- [ ] **Step 1: Point the suites intro at the inventory**

In `docs/testing.md`, replace the line:

```
Nine files, loaded in this order, **152 tests** total:
```

with:

```
Nine files, loaded in this order (see **[test-cases.md](test-cases.md)** for the full per-case
inventory and the authoritative count):
```

- [ ] **Step 2: Replace the "Current status" section with a pointer**

Replace the whole `## Current status` section:

```
## Current status

`152 passed, 0 failed, 152 total`. Re-verify anytime with the tail of `lua tests/run.lua`.
```

with:

```
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
```

- [ ] **Step 3: Fix the stale count in the green-gate block**

In the `## The green gate` fenced block, replace:

```
lua tests/run.lua     # 152 passed, 0 failed
luacheck .            # 0 warnings / 0 errors in 18 files
```

with:

```
lua tests/run.lua     # all suites green (count: docs/test-cases.md)
luacheck .            # 0 warnings / 0 errors
```

- [ ] **Step 4: Verify no stale count remains**

Run: `grep -n '152' docs/testing.md`
Expected: no output (exit 1).

- [ ] **Step 5: Commit**

```bash
git add docs/testing.md
git commit -m "docs(testing): defer case count to generated inventory + add sync rule"
```

---

### Task 4: README badge + the update rule in `CLAUDE.md` and `agent-context.md`

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `docs/agent-context.md`

- [ ] **Step 1: Add the tests badge to the README badge row**

In `README.md`, the badge row currently is:

```
![wow](https://img.shields.io/badge/WoW-Midnight_12.0.7-orange)
![CurseForge Version](https://img.shields.io/curseforge/v/1607560)
![license](https://img.shields.io/badge/license-MIT-green)
[![Standard](https://img.shields.io/badge/Ka0s-WoW%20Addon%20Standard-blue)](https://github.com/tusharsaxena/WowAddonStandards)
```

Insert the tests badge after the CurseForge line (before `license`):

```
![tests](https://img.shields.io/badge/tests-166%2F166_passing-brightgreen)
```

- [ ] **Step 2: Add the update-rule bullet to `CLAUDE.md` Hard rules**

In `CLAUDE.md`, under the `## Hard rules` list, add this bullet (after the "Debug is session-only" bullet):

```
- **Test inventory & badge stay in sync.** When the suite changes (a case added/removed/renamed, or
  the pass count moves), regenerate `docs/test-cases.md` (`lua tests/run.lua --list > docs/test-cases.md`)
  and update the README `tests` badge count in the same change. See [docs/testing.md](docs/testing.md).
```

- [ ] **Step 3: Add the same rule to `docs/agent-context.md`**

Open `docs/agent-context.md`, find its hard-rules list (the `## Hard rules` section), and add an equivalent bullet at the end of that list:

```
- **Keep the test inventory & README badge in sync.** Any suite change (case added/removed/renamed
  or count moved) MUST regenerate `docs/test-cases.md` via `lua tests/run.lua --list` and update the
  README `tests` badge in the same change. See [testing.md](testing.md) and [test-cases.md](test-cases.md).
```

(If `docs/agent-context.md` labels its rules section differently, add the bullet to that section; match the file's existing bullet style.)

- [ ] **Step 4: Verify tests still green + lint**

Run: `lua tests/run.lua | tail -1 && luacheck .`
Expected: `166 passed, 0 failed, 166 total` and `0 warnings / 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add README.md CLAUDE.md docs/agent-context.md
git commit -m "docs: README tests badge (166/166) + inventory-sync hard rule"
```

---

### Task 5: Standard — new `testing-§5` MUST

**Files:**
- Modify: `/mnt/d/Profile/Users/Tushar/Documents/GIT/WowAddonStandards/standards/standards/testing.md`

> All Task 5–7 commits happen in the **WowAddonStandards** repo, not the addon repo. `cd` into it for git.

- [ ] **Step 1: Append §5 to the testing section**

At the end of `standards/standards/testing.md` (after the current `### 4. TDD & the commit gate`), add:

```markdown
### 5. Test-case inventory & coverage badge

Two visible-coverage artifacts make the suite's health legible; both are **local and
hand-runnable — no CI is required or expected**.

- **MUST** ship **`docs/test-cases.md`** — a **generated** full enumeration of every test case,
  grouped by suite, with per-suite and grand totals. It **MUST** be produced by a non-executing
  `--list` (or equivalent) mode of the headless runner (`lua tests/run.lua --list > docs/test-cases.md`),
  **not** hand-authored, and it is the addon's **authoritative pass count**. Reference implementation
  (in the collection): the loot-history browser's runner grows a `--list` branch that groups the
  registered cases by their originating `test_*.lua` suite and prints the Markdown inventory.
- **MUST** surface a **test-pass badge** in the README badge row (documentation-§1) showing
  **X/Y passing** (passed / total) as a **static** shields.io badge
  (`img.shields.io/badge/tests-<X>%2F<Y>_passing-brightgreen`). **MUST NOT** require CI, a
  dynamic/endpoint badge, or a GitHub Action to produce it.
- **MUST** keep both in lockstep with the suite: whenever a case is added, removed, or renamed, or
  the pass count moves — i.e. **whenever a failing test is resolved** — regenerate `docs/test-cases.md`
  and update the README badge **as part of the same change**, never as a deferred follow-up.

This complements §4: the green gate proves the suite passes on every commit; the inventory and badge
make the coverage **visible and honest**, and are the standing defence against the count drift that
silently creeps into hand-maintained status lines.
```

- [ ] **Step 2: Commit (standards repo)**

```bash
cd /mnt/d/Profile/Users/Tushar/Documents/GIT/WowAddonStandards
git add standards/standards/testing.md
git commit -m "standard(testing): §5 — test-case inventory doc + X/Y coverage badge (MUST, no CI)"
```

---

### Task 6: Standard — documentation ripple

**Files:**
- Modify: `/mnt/d/Profile/Users/Tushar/Documents/GIT/WowAddonStandards/standards/standards/documentation.md`

- [ ] **Step 1: Add the tests badge to the badge-row spec (§1 #2)**

In `documentation.md`, section `### 1`, item **2. Badge row**, extend the ordered badge list to
include the tests badge. Replace the item-2 sentence:

```
2. **Badge row** — in order: a **`[wow]`** interface badge (in lockstep with the TOC `## Interface:`, toc-file-§3); a **published-version** badge (CurseForge/Wago) once published; a **`[license]`** MIT badge; and a badge/line linking the **Ka0s WoW Addon Standard** (<https://github.com/tusharsaxena/WowAddonStandards>). **MUST**.
```

with:

```
2. **Badge row** — in order: a **`[wow]`** interface badge (in lockstep with the TOC `## Interface:`, toc-file-§3); a **published-version** badge (CurseForge/Wago) once published; a **`[tests]`** X/Y pass badge (static shields.io, testing-§5); a **`[license]`** MIT badge; and a badge/line linking the **Ka0s WoW Addon Standard** (<https://github.com/tusharsaxena/WowAddonStandards>). **MUST**.
```

- [ ] **Step 2: Note the inventory + badge in the README Testing section (§1 #11)**

Replace item **11. `## Testing`**:

```
11. **`## Testing`** — **MUST**. How to verify: the headless harness (`lua tests/run.lua`), lint (`luacheck .`), and the in-game smoke-test suite (link `docs/smoke-tests.md`), with a note to run it before tagging a release or after bumping `## Interface:` / refreshing libs (testing, audit-review-history).
```

with:

```
11. **`## Testing`** — **MUST**. How to verify: the headless harness (`lua tests/run.lua`), lint (`luacheck .`), the generated case inventory (`docs/test-cases.md`, testing-§5), and the in-game smoke-test suite (link `docs/smoke-tests.md`), with a note to run it before tagging a release or after bumping `## Interface:` / refreshing libs (testing, audit-review-history). The README's `[tests]` X/Y badge (testing-§5) is hand-maintained alongside the inventory.
```

- [ ] **Step 3: Mark `docs/test-cases.md` as a required topic-detail doc (§3)**

In section `### 3. docs/`, in the "Beyond the trio, **MAY** ship any number of **topic-detail docs**"
paragraph, append this sentence to the end of that paragraph (before the `**MUST NOT** ship a
`TODO.md`` clause if it is in the same sentence; otherwise as its own sentence):

```
One topic-detail doc is **required**, not optional: `docs/test-cases.md`, the generated test-case
inventory (testing-§5).
```

- [ ] **Step 4: Commit (standards repo)**

```bash
cd /mnt/d/Profile/Users/Tushar/Documents/GIT/WowAddonStandards
git add standards/standards/documentation.md
git commit -m "standard(documentation): tests badge in badge row + required test-cases.md doc"
```

---

### Task 7: Standard — context pack + version/date bump

**Files:**
- Modify: `/mnt/d/Profile/Users/Tushar/Documents/GIT/WowAddonStandards/standards/NEW_ADDON_CONTEXT.md`
- Modify: `/mnt/d/Profile/Users/Tushar/Documents/GIT/WowAddonStandards/standards/STANDARDS.md`
- Check/Modify: `/mnt/d/Profile/Users/Tushar/Documents/GIT/WowAddonStandards/standards/EXECUTIVE_SUMMARY.md`

- [ ] **Step 1: Reflect the new requirement in the context pack**

Run: `grep -n 'run.lua\|test\b\|Testing\|badge' /mnt/d/Profile/Users/Tushar/Documents/GIT/WowAddonStandards/standards/NEW_ADDON_CONTEXT.md | head -40`
Then, in the testing/docs guidance of `NEW_ADDON_CONTEXT.md`, add a short line stating that a new
addon **MUST** ship a generated `docs/test-cases.md` inventory (`lua tests/run.lua --list`) and a
static X/Y `[tests]` README badge, kept in sync with the suite (testing-§5). Match the surrounding
prose/bullet style of that file.

- [ ] **Step 2: Bump the standard version + date**

In `STANDARDS.md`, replace the header line:

```
# Ka0s WoW Addon Standard (v1.12.0, 2026-07-15)
```

with:

```
# Ka0s WoW Addon Standard (v1.13.0, 2026-07-15)
```

- [ ] **Step 3: Check EXECUTIVE_SUMMARY for a version/requirement list**

Run: `grep -n 'v1.12\|1.12.0\|testing\|badge\|test-cases' /mnt/d/Profile/Users/Tushar/Documents/GIT/WowAddonStandards/standards/EXECUTIVE_SUMMARY.md`
If it names the version, bump `v1.12.0` → `v1.13.0`. If it enumerates per-section MUSTs, add a
one-line entry for the test-case inventory + badge under the testing section. If neither, leave it.

- [ ] **Step 4: Verify no stale version string remains in the index**

Run: `grep -rn 'v1.12.0' /mnt/d/Profile/Users/Tushar/Documents/GIT/WowAddonStandards/standards/STANDARDS.md`
Expected: no output.

- [ ] **Step 5: Commit (standards repo)**

```bash
cd /mnt/d/Profile/Users/Tushar/Documents/GIT/WowAddonStandards
git add standards/NEW_ADDON_CONTEXT.md standards/STANDARDS.md standards/EXECUTIVE_SUMMARY.md
git commit -m "standard: adopt test-inventory+badge MUST; bump v1.12.0 -> v1.13.0"
```

---

## Self-Review

**Spec coverage:**
- Spec A1 (runner `--list`) → Task 1. ✓
- Spec A2 (`docs/test-cases.md`) → Task 2. ✓
- Spec A3 (de-dup count in `testing.md`) → Task 3. ✓
- Spec A4 (README badge) → Task 4 Step 1. ✓
- Spec A5 (update rule in CLAUDE.md / agent-context.md / testing.md) → Task 3 Step 2 + Task 4 Steps 2–3. ✓
- Spec B1 (testing-§5 MUST) → Task 5. ✓
- Spec B2 (documentation ripple: badge row, testing section, §3 note) → Task 6. ✓
- Spec B3 (NEW_ADDON_CONTEXT) → Task 7 Step 1. ✓
- Spec B4 (STANDARDS version bump + EXECUTIVE_SUMMARY) → Task 7 Steps 2–3. ✓
- Spec B5 (deviation note) → informational; no code. ✓

**Placeholder scan:** No TBD/TODO. Task 7 Steps 1 & 3 are intentionally conditional (grep-then-edit) because the target files' exact structure is verified at edit time — each gives the exact content to add and the match to look for. Acceptable.

**Type consistency:** `--list` flag, `docs/test-cases.md` path, `currentSuite`/`SUITE_FILES` names, and the badge URL shape are used identically across all tasks. Count **166** appears only where regenerated or as the badge seed, never as doc body text.
