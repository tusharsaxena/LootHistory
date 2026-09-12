# 03 — Decisions

This run was non-interactive. The orchestrating session gave the owner's answers in advance
(2026-09-12):

- **Adopt** means deleting a local shim only where the kit now provides the same contract and the
  suite stays green, with characterization first.
- **Decline** covers anything that needs a harness migration. Declines are returned to the owner as
  proposed issues, not filed from this run.
- This run files no GitHub issue and pushes nothing.

| # | Candidate | Decision | Record |
|---|---|---|---|
| B1 | Delete the local AceEvent event-half shim (`tests/wow_mock.lua`) and fire the kit's recorded handler in `tests/test_browser.lua` (LibKa0s#29) | **adopt** | Characterized first. After the copy and before any edit, the case was red with *nothing registered the event*. After the edit it is green and the total is 721 passed, 0 failed, 0 skipped. It lands in the re-vendor commit, because a re-vendor without it is red. |

**Declined:** none. No candidate needed a harness migration. The kit's `Embed` reaches this
addon's mock because `tests/wow_mock.lua` wraps the kit's fakes rather than replacing them.

**Unreached:** none.
