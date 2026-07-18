# 04 — Technical Design (Remediation)

How to close the seven open deviations. Keyed to `02_DEVIATIONS.md` IDs. This audit is **read-only** —
nothing here has been applied; it is the design a follow-up remediation engagement executes under the
green gate (`lua tests/run.lua` + `luacheck .`).

Overall risk is **low**: five items are comment/config/copy edits, one is a small options-panel
addition, and one (LH-13) is likely a standards-process decision rather than a code change. No change
touches capture, storage, attribution, or the read path.

---

## LH-13 — TOC file-listing section order (`toc-file-§5`) · **decision first, then maybe TOC edit**

**The crux is a standard-internal contradiction.** `toc-file-§5` mandates section order
`Libraries → Locales → Core → Defaults → Modules → Settings` and asserts it "matches the load order
(layout-§1)"; but `layout-§1` states the load order is `core → defaults → locales → settings →
modules`. These disagree on (a) Locales-vs-Core and (b) Settings-vs-Modules. The addon follows
`layout-§1` exactly and its order is dependency-correct.

Per the CLAUDE.md **Deviation rule**, this is precisely a "user decides: fix the addon, or fix the
standard" case. Two candidate resolutions:

- **Path A (recommended) — raise upstream as a standards defect.** File it against
  `WowAddonStandards` (`toc-file-§5` ↔ `layout-§1` order conflict). Likely outcome: `toc-file-§5` is
  corrected to match `layout-§1` (`Libraries → Core → Defaults → Locales → Settings → Modules`), at
  which point the addon is already compliant. Record an **accepted deviation** here in the interim.
- **Path B — reorder the TOC to the literal `toc-file-§5` text.** Move `# Locales` above `# Core`
  and `# Settings` below `# Modules`. **Feasibility check required first:** loading `locales/enUS.lua`
  before `core/*` is safe (it only sets `NS.L`), but loading `settings/*` **after** `modules/*` means
  modules must not read `NS.Schema`/`NS.COMMANDS` at *file-load* time. They currently don't (schema is
  consumed at runtime via `onChange`/dispatch), so Path B is technically achievable — but it would put
  the addon *out* of step with `layout-§1` and with the rest of the collection's load order. **Do not
  take Path B without the user's explicit call**, because it trades one MUST-conformance for another.

**Files:** `LootHistory.toc` (only if Path B). **Tests:** none (TOC ordering isn't unit-testable);
covered by smoke-test "clean load, no Lua error, `/lh` prints help".

---

## LH-14 — Canonical grey combat notice (`options-ui-§2`) · **low risk**

Replace the lockdown branch string in `P:Open` with the canonical grey notice.

```lua
-- settings/Panel.lua, in P:Open()
if InCombatLockdown and InCombatLockdown() then
  print("|cff808080" .. L["cannot open settings during combat — Blizzard's category-switch is protected"] .. "|r")
  return
end
```

- Add the English string to `locales/enUS.lua` as its own key (localization-§2, English-string key).
- Keep the early `return`; do **not** add a `PLAYER_REGEN_ENABLED` replay (options-ui-§2 forbids
  defer-and-replay).
- `NS.Print` prepends the cyan `[LH]` tag; the grey `|cff808080…|r` colours only the body — the
  standard's "grey notice" intent.

**Files:** `settings/Panel.lua`, `locales/enUS.lua`. **Tests:** the message is a chat side effect;
optionally assert `P:Open` early-returns (does not call `Settings.OpenToCategory`) when a mocked
`InCombatLockdown` returns true.

---

## LH-15 — CLAUDE heading `(read first)` (`documentation-§2`/`-§6`) · **trivial**

Rename `## Standards compliance` → `## Standards compliance (read first)` in root `CLAUDE.md`, and
sanity-check the body against the documentation-§6 canonical wording (the stop-and-flag rule + the
two-way classification + "when in doubt, treat conformance as a hard requirement and ask"). The
substance is already present, so this is a heading edit plus optional wording alignment.

**Files:** `CLAUDE.md`. **Tests:** none (doc).

---

## LH-16 — Ignore `tools/` in packaging (`packaging`) · **trivial**

Add `tools/` to `.pkgmeta` `ignore:` so the dev-only Python tooling never ships:

```yaml
ignore:
  - .luacheckrc
  - .gitignore
  - docs
  - tests
  - tools          # dev-only export tooling (Python) — not shipped
  - _dev
  - "*.bak"
```

Optionally also drop `.superpowers`, `.gitattributes`, and `.pkgmeta` itself if the packager doesn't
already. **Files:** `.pkgmeta`. **Tests:** none.

---

## LH-17 — lint exclude the audit/review dirs (`lint`) · **trivial**

Align `.luacheckrc` `exclude_files` with the template:

```lua
exclude_files = { "libs/", "docs/audits/", "docs/reviews/", "_dev/", "tests/" }
```

(Optionally add `"tools/"`.) Re-run `luacheck .` to confirm it stays 0/0. **Files:** `.luacheckrc`.

---

## LH-18 — Filters subcategory Defaults button (`options-ui-§5`) · **low risk / or accept**

Two options — pick one with the user:

- **Add the button.** Flip `createPanel("LootHistoryFiltersPanel", "Filters", { defaultsButton = true })`
  and wire `fctx.panel.defaultsBtn:SetCallback("OnClick", …)` to a confirm-gated lists reset
  (`NS.Filters:ClearAll()` behind a new `StaticPopup`, mirroring the existing Clear-all confirms in
  `settings/Slash.lua`). Reuse `buildHeader`'s existing AceGUI-Button path (already compliant with
  options-ui-§5's AceGUI-button rule).
- **Accept the deviation.** The Filters page holds no schema rows — it manages dynamic id-sets with
  their own per-list "Clear all" buttons — so a header Defaults button is arguably redundant. If the
  user prefers, record an accepted deviation (in this bundle + a one-line note in
  `docs/settings-panel.md`) with that reason.

**Files:** `settings/Panel.lua` (+ `settings/Slash.lua` for a popup) *or* docs only. **Tests:** if
added, none new (UI wiring; covered by smoke test).

---

## LH-19 — Sweep retired `§N.M` citations (`documentation-§5`) · **trivial, mechanical**

Rewrite the 15 stale citations (listed in `03_EVIDENCE.md §LH-19`) to `filename-§N`:

| Old | New |
|-----|-----|
| `§7.4` | `slash-commands-§4` |
| `§6.8` | `options-ui-§8` |
| `§6.6` | `options-ui-§6` |
| `§6.10` | `options-ui-§10` |
| `§9.7` | `events-frames-taint-§7` |
| `§2.2/§5.1` | `toc-file-§2` / `savedvariables-§1` |
| `§6A` | `standalone-windows` |
| `§8` (attribution comment) | `debug-logging` |
| `§15.2` | `documentation-§2` |
| `§14A` | `testing` |

Comment/doc-only edits across `core/Namespace.lua`, `core/Database.lua`, `modules/Collector.lua`,
`modules/Browser.lua`, `modules/Attribution.lua`, `settings/Panel.lua`, `settings/Slash.lua`,
`CLAUDE.md`. **Tests:** none (comments). Re-run the green gate after (comment edits shouldn't move it).

---

## Cross-cutting notes

- **Shared-file collisions:** `settings/Panel.lua` is touched by LH-14, LH-18, LH-19; `.pkgmeta`/
  `.luacheckrc` by LH-16/LH-17; `CLAUDE.md` by LH-15/LH-19. Sequence these on one branch/worktree to
  avoid churn (see `05_EXECUTION_PLAN.md`).
- **Green gate:** run `lua tests/run.lua` (expect 224/224) and `luacheck .` (expect 0/0) after each
  sprint; commit only on green (versioning-git, testing).
- **No version bump** is warranted by these edits (no user-facing behaviour change beyond a reworded
  combat notice); leave `## Version` / `NS.version` / README untouched unless the user says otherwise.
