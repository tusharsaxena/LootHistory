# 04 — Execution plan

One adopted candidate, B1. It cannot ship in a commit of its own, because the re-vendor alone is
red: the kit-16 `Embed` switches the local shim off. The library's own adoption note says the same
("Delete the shims in the re-vendor commit"). So the re-vendor commit carries all of it:

1. **Characterization, before any edit.** Copy both payloads whole from `v1.30.0` and run
   `lua tests/run.lua`. Expected and observed: `browser: a combat transition re-applies visibility
   through the private event target` fails with *nothing registered the event*. The kit vendor-sync
   case also fails until the provenance line moves. `719 passed, 2 failed, 0 skipped, 721 total`.
2. **Provenance.** `CLAUDE.md:51` goes from v1.29.0 to v1.30.0. The same release is quoted in
   `docs/testing.md` → *When these diffs are supposed to be non-empty*.
3. **`tests/wow_mock.lua`.** Delete the *AceEvent's EVENT half* block: the `rawget`-guarded
   `Embed` wrap, its shared `eventRegistry` and `M.__fireAceEvent`. Leave a four-line pointer to the
   kit contract. Correct the `NewAddon` wrapper's comment, since the kit's `AceAddon` fake now
   stamps the event half and still omits only the message half.
4. **`tests/test_browser.lua`.** The case reads `B.__ev.__events`, asserts that each of the two
   events is registered with a **function** handler on that private target, and fires it as
   CallbackHandler does, `handler(event)`. The assertion that proves it is `ran == 2` on a stubbed
   `B.ApplyVisibility`. The case still goes red if the registration moves to `NS.bus`, because the
   kit records per target and `B.__ev.__events` would then be empty. It also goes red if the
   registration is dropped.
5. **`docs/testing.md`.** Replace the *AceEvent's EVENT half* local-extension bullet with a
   paragraph saying the kit owns it.
6. **Count.** The kit adds one case (the runner's recorded mode), 720 → 721. Regenerate
   `docs/test-cases.md` with `lua tests/run.lua --list` and move the README `[tests]` badge in the
   same commit.
7. **Line endings.** Repair any LF straggler in the touched paths
   (`git add <p> && rm <p> && git checkout -- <p>`), then re-run the gate, including
   `tests/_kit/test_eol.lua`'s case.
8. **Gate.** `lua tests/run.lua` shows all passing with 0 skipped, and `luacheck .` shows 0/0. Then
   one commit. Nothing is pushed.
