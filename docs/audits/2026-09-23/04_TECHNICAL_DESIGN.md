# 04 — Technical design

Remediation for the 20 roots and 1 dependent in `02_DEVIATIONS.md`. Nothing here changes a stored path, a
SavedVariables shape or the command surface; no migration is required by any of it. Three items need an upstream
change first (LH-69 in LibKa0s's test kit; LH-75 and, optionally, LH-76 as standard proposals), and the design says so
at each.

---

## A. Upstream (LibKa0s / WowAddonStandards) — land before the addon-side work

### LH-69 — the runner cannot record the `performance-§12` skip reason

**Where:** `LibKa0s/testkit/run-automated-tests.sh` (vendored here byte-identically as `tests/_kit/…`; `testing-§1`
forbids a local edit). Today `:343-344` sets `NOTE[perf]` to reason (1) whenever `tests/perf.lua` is absent, and the RESULTS
generator (`:838-841`) prints that the skip is *not* the exemption.

**Shape of the change (library):** before falling back to reason (1), detect a ratified exemption and emit reason (2):
- read `docs/ARCHITECTURE.md`'s `## Documented deviations` table for a row whose Rule cell is `` `performance-§12` `` (the
  register is the single home, `documentation-§3`, so it is the right input and needs no new per-repo file); or accept an
  explicit override (env var / flag) for repos whose register cannot be parsed;
- set `skipReason` to `performance-§12 no-combat-path exemption (ratified; docs/ARCHITECTURE.md → Documented deviations)`
  and branch the RESULTS *Perf* standing section on it.
- Kit case: a fixture repo with the row → reason (2); without → reason (1); a malformed register fails loudly rather than
  silently picking (1).

**Addon side after re-vendor:** nothing to write. The next four-suite run records reason (2). Frozen bundles are not
touched.

### LH-75 — versioning-git's defaults stamp vs the AceDB backfill case (standard)

The addon keeps `schemaVersion = 1` in defaults on purpose; `versioning-git` says increment it. `open-evolutions` already
records the hard case. Proposal upstream: have `versioning-git` defer to the migration-stamp ruling (or state that the
**runner's** highest `to` is the version and the defaults value is the pre-migration floor). Until that lands, the addon
ratifies its choice with a register row (section C).

### LH-76 (optional) — resize grip vs the catalog

If the collection genuinely standardizes on Blizzard's `UI-ChatIM-SizeGrabber` for window corners (the comment at
`modules/Browser.lua:1042-1046` says the other addons draw it), that is a `standalone-windows` / `library-stack-§8`
statement to make upstream, once. Otherwise the addon adopts `resize` locally (section B). Either path closes LH-76; the
upstream path closes it for every addon at once.

---

## B. Code (addon)

### LH-65 — combat visibility read from the wrong signal

`modules/Browser.lua`:
- `B:VisibilityAllows(inCombat)` takes an optional explicit edge. When `nil`, derive it from
  `UnitAffectingCombat("player")` (display logic, `events-frames-taint-§2`), not `InCombatLockdown()`.
- The `PLAYER_REGEN_DISABLED` handler calls `B:ApplyVisibility(true)`; `PLAYER_REGEN_ENABLED` calls `B:ApplyVisibility(false)`;
  `ApplyVisibility(inCombat)` forwards to `VisibilityAllows(inCombat)`.
- `modules/BrowserTable.lua:543` (`testModeRefusal`) uses `UnitAffectingCombat("player")` for the same reason.
- `.luacheckrc` gains `UnitAffectingCombat` in `read_globals`.

Tests (`tests/test_browser.lua`): with *Only out of combat* and the mock's `InCombatLockdown` returning `false`, fire
`PLAYER_REGEN_DISABLED` through `M.__fire` and assert the window hid (red under: reading `InCombatLockdown()`); mirror for
*Only in combat* on `PLAYER_REGEN_ENABLED`. Smoke test: set *Only out of combat*, open the window, pull a dummy — the
window must hide at the pull.

### LH-64 — per-event isolation and a rejected-name record

New helper in `core/LifecycleSetup.lua` (the seam that already owns stand-down bookkeeping) or `core/Util.lua`:

```lua
NS.RejectedEvents = {}                      -- event name -> error text, session-only
function NS.SafeRegister(target, event, handler, unit)
  if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
    NS.RejectedEvents[event] = "not valid on this client"; return false
  end
  local ok, err = pcall(function()
    if unit then target:RegisterUnitEvent(event, unit) else target:RegisterEvent(event, handler) end
  end)
  if not ok then NS.RejectedEvents[event] = tostring(err) end
  return ok
end
```

Route every block through it: `modules/Attribution.lua:349-355` (and keep `self.__events` as the list of names that
**did** register, so `Disable` unregisters exactly those), `:369`, `modules/Collector.lua:218-219`,
`modules/Browser.lua:1246/1252`, `core/LifecycleSetup.lua:112`. Surface the record: `/lh debug events` (a structured dump
topic, `debug-logging-§4` MAY) printing the rejected names, and one clause in the `[Init]` summary when the set is
non-empty. `.luacheckrc` gains `C_EventUtils`.

Tests: kit mock's `M.__badEvents = { ENCOUNTER_START = true }` → the six other Attribution events still register, the
rejected list names `ENCOUNTER_START`, `/lh debug events` prints it; `tests/test_disabled.lua` still reaches an empty set.

### LH-66 — literal message names in tests

Replace the nine literals with `NS.MSG.RECORD_ADDED` / `HISTORY_CHANGED` / `SETTINGS_CHANGED`; in
`tests/test_harness.lua` declare `local PROBE = "Ka0s_LootHistory_HarnessProbe"` once and use it at `:145-147`/`:149`.
`tests/test_constants.lua`'s literal assertions stay (they pin the wire strings).

### LH-68 — parity cases for five stubs

Add to `tests/test_surface_parity.lua`, each loading the degraded arm from `tests/degraded_env.lua`:
- **Env** — members from `grep -nE "^\s*function NS\.(Meta|Version|PlayerMapID|Zone)\b|^NS\.(Meta|Version|PlayerMapID|Zone) *=" core/EnvSetup.lua`.
- **Item** — `NS.Item` live vs degraded, members from `grep -ohE "NS\.Item[:.][A-Za-z_]+" core modules settings`.
- **Media** — `NS.Icon` / `NS.MediaFont` / `NS.IconMarkup` present and functions on both arms.
- **Pool** — `NS.Pool` live vs degraded, members from `grep -ohE "NS\.Pool[:.][A-Za-z_]+" …`.
- **Lifecycle** — `NS.Lifecycle` live vs degraded, members from `grep -ohE "NS\.Lifecycle[:.][A-Za-z_]+" …`, ignoring
  library-only members the addon never calls (named with the grep that proves it).
Regenerate `docs/test-cases.md` and the README badge in the same change (`testing-§5`).

### LH-76 — resize grip (addon path)

`modules/Browser.lua:1047-1048`: `local mark = NS.Icon and NS.Icon("resize")`; if present, set it as the normal texture
(white, tinted like the other title-bar marks) with a hover tint; else fall back to the Blizzard grabber. Or, if the
maintainer prefers the Blizzard corner, the register row in section C. The choice is the maintainer's; both close LH-76.

### LH-77 — pre-formatting (optional, SHOULD)

When `settings/Slash.lua:40/51/62/76` and `settings/Schema.lua:785` are next touched, pass values as arguments to
`print(...)` rather than formatting first.

---

## C. Register rows (docs/ARCHITECTURE.md → `## Documented deviations`)

Three departures argued only in comments get rows (each `| Rule | What differs | Why | Decided | Re-check trigger |`):

| Rule | What differs | Why (cite) | Re-check trigger |
|---|---|---|---|
| `localization-§4` (LH-74) | Deconstruct attribution falls back to a name-family match against **client-locale** names derived from seed spell ids | Per-herb/ore Mass Mill/Prospect ids are not enumerable; names come from ids on the same client, so no English literal and no locale breakage (`modules/Attribution.lua:20-50`, issue #2) | Blizzard exposes a stable token/category for deconstruct casts, or the id set becomes enumerable |
| `versioning-git` (LH-75) | `defaults/Global.lua` holds `schemaVersion = 1`; the runner's highest `to` (8) is the live version | A seeded stamp would mark a fresh install as migrated and mask a legacy account under AceDB's backfill (`defaults/Global.lua:8-12`; `open-evolutions` *Migration-stamp ownership*) | The standard rules on migration-stamp ownership |
| `library-stack-§8` (LH-76, only if the Blizzard grabber is kept) | Resize grip draws `UI-ChatIM-SizeGrabber` instead of the catalog `resize` mark | Matches the collection's window corners (`modules/Browser.lua:1042-1046`) | The standard names the grip either way, or the catalog `resize` mark is adopted collection-wide |

---

## D. Docs and records

- **LH-62** — one consolidated bundle `docs/revendor/<date>-v1.53.0/` with `01_DELTA.md` (first line naming the span
  `v1.15.0 → v1.53.0`; a table of the 25 unrecorded tags with the commit that vendored each, from
  `git log --format='%h %ad %s' --date=short -- libs/LibKa0s`) and `05_SUMMARY.md` (what was adopted in those commits, and
  that nothing else was deliberated). No per-tag folders.
- **LH-56 / LH-57 / LH-63 / LH-58** — TOC comments only (one commit): load-bearing comments above `:48`, `:56`, `:87`;
  a one-line *conventional* note on `# Locales`, `# Defaults` and the plain `# Core` run; reword `:57` (Pool) as conventional.
- **LH-60** — spill *Settings schema*'s named-state and registry paragraphs (`docs/ARCHITECTURE.md:118-160`) into
  `schema.md` (a *Named non-setting state and registries* section), leave a ≤15-line summary with one link; move *The
  disabled state* body to a Tier 3 `disabled-state.md` (registered in `### Addon-specific`), leaving a summary + one link.
  Target < 400 lines.
- **LH-67** — rename the 12 cases in `tests/test_disabled.lua` to `slash-commands-§7 step N: …`; regenerate
  `docs/test-cases.md`; `.pkgmeta` cites `packaging`.
- **LH-70** — cut `docs/performance.md` to one screen (brackets nothing; (c) applies; where the sweep lives; what re-arms);
  move the sweep to `docs/combat-path-sweep.md` (Tier 3, registered) and update the register row's Why link.
- **LH-71** — README *Usage*: move the enable/disable/slash-surface sentences up into the body; close on one sentence.
  De-AI pass (`documentation-§1`).
- **LH-72** — swap `CLAUDE.md`'s `## Vendored LibKa0s` and `## Green gate`.
- **LH-73** — re-point `DEPENDENCIES.md:49/53/112`; restate the load-bearing set at `docs/ARCHITECTURE.md:42-48` and in
  `docs/module-map.md` to match the TOC comments; `:207` cites `slash-commands-§3`; `:447` trigger → "21 shims".
- **LH-52** — open a `state:triaged` / `severity:low` issue for the Analytics peel (seam: renderers vs
  formatting/segmenting helpers); at the next run, set the Disposition to *already tracked as #N*.

---

## Risks and ordering

- **LH-65** changes a visible behavior (the window now hides at the pull under *Only out of combat*). That is the
  setting's documented meaning, but it is a behavior change: call it out in the next release's Version History.
- **LH-64** must keep `Attribution:Disable` symmetric: unregister only what registered, or the stand-down suite goes red.
  Run `tests/test_disabled.lua` before and after.
- **LH-69** is gated on a LibKa0s release; do not hand-edit `RESULTS.md` in the meantime (`automated-tests-§4`).
- Every TOC / doc change is behavior-neutral; land them before the code sprint so later diffs stay small.
- Re-vendoring LibKa0s for LH-69 is a **new** re-vendor commit and needs its own `docs/revendor/<date>-v<tag>/` bundle —
  do not let LH-62's fix create LH-62 again.
