# 02 — Proposed Changes (HLD + LLD) · Ka0s Loot History

Design doc for addressing `01_FINDINGS.md`. Change IDs (`C-00x`) map back to finding IDs.

---

## HLD — themes

### T1. Make attribution coverage honest (F-001)
**Rationale:** the UI and design doc advertise 11 sources; only 7 are wired, and 3 of those depend
on unverified `CHAT_MSG_LOOT` behavior. The fix is *coverage honesty*, not necessarily full
capture: either implement the missing stampers or scope the UI/enum to what actually works.

**Options considered:**
- **(a) Implement AH/CRAFT/ROLL stampers + verify VENDOR/MAIL/TRADE** — most complete, but
  BAG_UPDATE-diffing for vendor/mail/trade is a real subsystem and out of scope for a 0.1.0
  review-fix. Rejected as the immediate move.
- **(b) Scope the shipped surface to verified sources** — mark AH/CRAFT/ROLL (and any of
  VENDOR/MAIL/TRADE that don't fire) as "planned", hide them from the mute list and Source
  dropdown until wired, and keep the enum stable (export contract). **Chosen for now.**
- **(c) Do nothing, just document** — cheapest, but leaves dead filter buckets in the user's face.
  Rejected.

**Decision:** Do (b) for the shipped UI + a smoke test that empirically classifies each flow
(03 §F-001), and file (a) as a tracked backlog item. Keep `Constants.SourceType` unchanged (export
contract, per CLAUDE "do not change"). Add a `Constants.SOURCE_IMPLEMENTED` set that the mute list
and Source dropdown filter against, so the enum stays whole while the UI only shows reachable
sources.

### T2. Tighten the Compat firewall and de-duplicate helpers (F-002, F-005)
**Rationale:** one place per flavor-varying API and per shared helper. Low-risk consolidation that
pays back on the next flavor bump.

### T3. Harden the settings write-path (F-003)
**Rationale:** the single-write-path is only safe if it never hands out live references to the
defaults. Deep-copy table values on write/default so resets can't alias.

### T4. Cleanup + honesty passes (F-004, F-006 through F-013)
**Rationale:** dead code, stale comments, a UX desync, and doc/TOC hygiene. Individually trivial;
grouped so they land in one cleanup commit.

---

## LLD — change-set

### C-001 — Scope attribution UI to reachable sources (covers F-001)
**Files:** `core/Constants.lua`, `settings/Schema.lua` (mute options), `modules/Browser.lua`
(`sourceOptions`), `modules/Attribution.lua` (comment), `docs/TECHNICAL_DESIGN.md`.
- Add to `Constants.lua`:
  ```lua
  -- Sources with a live capture path today. AH/CRAFT/ROLL are specified in TD §4 but not yet
  -- stamped; VENDOR/MAIL/TRADE are gated on the smoke-test result (03 §F-001).
  C.SOURCE_IMPLEMENTED = { KILL=true, CONTAINER=true, MPLUS=true, QUEST=true,
                           VENDOR=true, MAIL=true, TRADE=true, OTHER=true }
  ```
- `Constants.SOURCE_OPTIONS` build loop: skip entries not in `SOURCE_IMPLEMENTED` (keep
  `SourceType`/`SourceOrder`/`SourceLabel` whole — export contract).
- Browser `sourceOptions()` already derives from live data, so it self-scopes; no change needed
  there except confirming the Group-by "Source" still works.
- **If** the smoke test shows VENDOR/MAIL/TRADE never fire, drop them from `SOURCE_IMPLEMENTED`
  too and open the backlog item for BAG_UPDATE-diff capture.
- **Risk:** low. Enum unchanged; only the *option lists* shrink. Update the one attribution comment
  and TD table to say "planned" for unimplemented rows.

### C-002 — Route challenge-mode map id through Compat (covers F-002)
**Files:** `modules/Attribution.lua`, `core/Compat.lua` (optional new wrapper).
- Replace inline `C_Map.GetBestMapForUnit("player")` in `OnChallengeModeStart` with
  `NS.Compat.GetPlayerMapID()`.
- Wrap the keystone read: add `Compat.GetActiveKeystoneLevel()` returning
  `C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo and (C_ChallengeMode.GetActiveKeystoneInfo())`
  or `nil`; call it from both `OnChallengeModeStart` and `OnChallengeModeCompleted`.
- **Risk:** low; behavior-preserving.

### C-003 — Deep-copy table values in the write-path (covers F-003)
**Files:** `settings/Schema.lua`.
- Add a small `deepcopy` local; in `S:Set`, if `type(value)=="table"` store a copy; in
  `S:Default`, return a copy of table-typed defaults.
  ```lua
  local function dc(v) if type(v)~="table" then return v end
    local t={} for k,val in pairs(v) do t[k]=dc(val) end return t end
  -- S:Set:   S:WritePath(NS.db.global, path, dc(value))
  -- S:Default: return dc(row and row.default)
  ```
- **Risk:** low; `excludedSources` is the only table setting. Confirm `makeMultiCheck` still round-
  trips (it copies anyway, so it stays correct).

### C-004 — Consolidate duplicated helpers (covers F-005)
**Files:** `core/Util.lua`, `modules/Browser.lua`, `modules/Analytics.lua`, `core/Compat.lua`,
`modules/Attribution.lua`.
- Add `Util.RangeFrom(rangeKey)` (today/7d/30d/all → `from` ts) and replace the local `dateFrom`
  (Browser) and `rangeFrom` (Analytics). Keep the "all"→nil contract.
- Delete Attribution's local `UNIT_KINDS`; reference a single set. Cleanest: expose
  `Compat.IsUnitGUIDKind(kind)` or `Compat.UNIT_KINDS`, and have both `DecodeGUID` and
  `ResolveLootSource` use it.
- **Risk:** low; covered by existing Analytics/Attribution unit tests. Add a `Util.RangeFrom` unit
  test.

### C-005 — Sync the player-scope toggle with specific-character filters (covers F-006)
**Files:** `modules/Browser.lua` (`SetCharFilter`).
- When `char` is set and `char ~= currentKey()`, the Player toggle should read a neutral third
  state rather than "All players". Two acceptable fixes:
  - **(a)** Add a `"custom"` display option to `dd.player` (label e.g. "Character: <name>") shown
    when a specific non-current char is active; or
  - **(b)** Blank the player toggle label when the char dropdown holds a specific value.
- Chosen: **(b)** — smaller. Set `dd.player` to show `"—"`/empty (no active scope) when a specific
  non-current char is chosen; "Current player"/"All players" only when the char filter is `nil` or
  exactly the current key.
- **Risk:** low; cosmetic-only. Verify `ClearFilters`/`ApplyView` reset it to "current".

### C-006 — Remove dead helpers (covers F-007)
**Files:** `core/Util.lua`. Delete `Util.FormatTime` and `Util.TableCount`. Grep first
(already confirmed zero callers). **Risk:** none.

### C-007 — Seed collector upvalue to the schema default (covers F-008)
**Files:** `modules/Collector.lua:9`. `qualityThreshold` seed `2 → 1`. **Risk:** none.

### C-008 — Fix stale comment (covers F-009)
**Files:** `modules/BrowserTable.lua:240`. `"/lh testmode"` → `"/lh test"`. **Risk:** none.

### C-009 — Document the non-schema persisted state (covers F-010)
**Files:** `CLAUDE.md` (or `docs/TECHNICAL_DESIGN.md`) + a comment in `Browser.lua`.
- Add one line to the Schema-as-single-source convention: "`savedView` and `settings.window` are
  view/window runtime state persisted directly by the Browser; they are intentionally not schema
  rows." **Risk:** none.

### C-010 — Drop the dead keystone map id (covers F-011)
**Files:** `modules/Attribution.lua:130`, `core/State.lua:11` comment. Either remove `mapID` from
the `State.keystone` table or thread it into the MPLUS detail. Chosen: remove (nothing reads it).
**Risk:** none.

### C-011 — TOC / CRLF hygiene (covers F-012)
**Files:** `LootHistory.toc`, new `.gitattributes` (optional).
- Confirm `## Interface: 120007` against the shipping client; correct if it's a typo. Optionally
  add `.gitattributes` (`*.lua text eol=crlf`, `*.xml text eol=crlf`) if the team wants CRLF pinned
  — note this is a *new* convention, not enforcement of an existing one. **Risk:** low.

### C-012 — (Deferred) combat-log name-cache cost (covers F-013)
No code change now; captured as a backlog note. If profiling (03 perf spot-check) shows the
per-line handler is meaningful in raid, gate registration behind a "recent loot-eligible kill"
heuristic. **Risk:** n/a (deferred).

---

## Roll-up

| Change | Findings | Files (primary) |
|--------|----------|-----------------|
| C-001 | F-001 | Constants.lua, Browser.lua, TD |
| C-002 | F-002 | Attribution.lua, Compat.lua |
| C-003 | F-003 | Schema.lua |
| C-004 | F-005 | Util.lua, Browser.lua, Analytics.lua, Compat.lua, Attribution.lua |
| C-005 | F-006 | Browser.lua |
| C-006 | F-007 | Util.lua |
| C-007 | F-008 | Collector.lua |
| C-008 | F-009 | BrowserTable.lua |
| C-009 | F-010 | CLAUDE.md, Browser.lua |
| C-010 | F-011 | Attribution.lua, State.lua |
| C-011 | F-012 | LootHistory.toc, .gitattributes |
| C-012 | F-013 | (deferred) |

**Not addressed by code:** F-004 (localization) is a scope decision — recommend an explicit
"English-only for 0.1.0" note plus removing the unused `local L` warning, rather than a wholesale
L-wrapping pass in this cycle. Tracked as a follow-up.
