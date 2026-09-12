# 02 — Candidates: LibKa0s v1.29.0 → v1.30.0

Sources, in the order the procedure requires:

```sh
git -C ../LibKa0s log --oneline v1.29.0..v1.30.0
#   e369e0f The v1.30.0 release record, re-taken on the review-fixed tree
#   e5f6906 Kit 16 review: double release raises, the release wipe, RegisterEvent validates, a per-build event registry
#   aaef20a The v1.30.0 release record
#   7aaf1fe Kit 16: AceGUI:Release, AceEvent's event half on an embed, Printf, and the runner's mode in every consumer
git -C ../LibKa0s show v1.30.0:CHANGELOG.md   # the "## v1.30.0 — 2026-09-12" block
```

No major's minor moved, so no `docs/api/<Major>/version-*-docs.md` changed. The kit's contract is in
`docs/api/testkit/version-16-docs.md` and in `testkit/README.md` → *The Ace fakes, and the shims they
replace* (both at the tag).

## Class A — reached this addon on the re-vendor alone

| Kit 16 item | Evidence | Why nothing is offered |
|---|---|---|
| `AceGUI:Release` / `widget:Release()` (LibKa0s#27) | `CHANGELOG.md` v1.30.0, *`AceGUI:Release` (#27)*; `testkit/mock_base.lua` at the tag | This addon has no local Release model, and neither its source nor `libs/LibKa0s/` calls `AceGUI:Release` (`grep -rn ':Release(' core modules settings` finds nothing). No test reads `__released`. Delivered, nothing to delete. |
| The runner-mode case in `VendorSync.register` (LibKa0s#28) | `CHANGELOG.md` v1.30.0, *the runner's recorded mode, in every consumer (#28)*; `testkit/vendor_sync.lua` at the tag | `tests/test_vendor_sync.lua` is one call, `VendorSync.register(_G.LH_TEST, {})`, so it picks the case up with no edit. The runner is recorded `100755` (`git ls-files -s -- tests/_kit/run-automated-tests.sh`), so it passes. This is the +1: 720 → 721. |
| `Printf` beside `Print` on the `NewAddon` target (LibKa0s#30) | `CHANGELOG.md` v1.30.0, *`Printf` beside `Print` (#30)* | The addon reclaims `NS.Print` after `NewAddon` (`core/LootHistory.lua:13`) and publishes no `NS.Printf` anywhere in `core/`, `modules/` or `settings/`, so there is nothing to take back. The kit-stamped `NS.Printf` sits unused, exactly as AceConsole's does in the client. |

## Class B — host change required

### B1. Delete the local AceEvent event-half shim and fire the kit's recorded handler (LibKa0s#29)

- **What.** Kit 16's `AceEvent:Embed` stamps `RegisterEvent` / `UnregisterEvent` /
  `UnregisterAllEvents` on every target and records per target on `t.__events`.
- **Evidence.** `CHANGELOG.md` v1.30.0, *AceEvent's event half on an embed (#29)*, and its
  *Adoption* paragraph: "**LootHistory is the one red.** … Delete that shim and fire the recorded
  handler, `target.__events[event](event, ...)`." `testkit/mock_base.lua` at the tag: `embedEvents`
  and the `AceEvent-3.0` `Embed`.
- **Files.** `tests/wow_mock.lua` (the *AceEvent's EVENT half* block and `M.__fireAceEvent`),
  `tests/test_browser.lua` (*browser: a combat transition re-applies visibility through the private
  event target*), `docs/testing.md` (the paragraph that described the shim).
- **Why it cannot wait.** It is not optional. The shim stamped its own `RegisterEvent` only when
  `rawget(obj, "RegisterEvent") == nil`, and at kit 16 that is never true, so its registry stays
  empty and `__fireAceEvent` returns 0. Measured on this branch after the copy and before any edit:
  `719 passed, 2 failed, 0 skipped, 721 total`. One red was this case; the other was the vendor
  gate reading a provenance line not yet rolled.
- **Recommendation.** Adopt, in the re-vendor commit. Test-only code.
- **Blast radius.** Replaces test code the addon owns; touches no production file. The production
  registration (`modules/Browser.lua:1285-1286`, two function handlers on `B.__ev`) passes the kit's
  new CallbackHandler-style validation as it stands.

## Not candidates, and why

- **The `NewAddon` wrapper** (`tests/wow_mock.lua`, *the message bus*). Kit 16's `NewAddon` stamps
  the event half but still does not embed the message half (`RegisterMessage` / `SendMessage`), so
  the wrapper that calls `AceEvent:Embed` on the addon object stays. It is not a decline, since kit
  16 offers no replacement. The kit keeps `registry[target]` across the second `Embed`, so events
  `NewAddon` recorded survive it, and `tests/test_attribution.lua`'s reads of `NS.addon.__events`
  stay green.
- **The `aceGUI.Create` wrapper** (`SetTitle`, `frame:GetStringWidth`). Unrelated to #27–#30.

## Class C — whole-module adoption

None. No major moved, and the one unconsumed major (Perf) is the settled `performance-§12`
no-combat-path exemption in `docs/ARCHITECTURE.md` → *Documented deviations*. Nothing in v1.30.0
moves its premise.
