# Candidates (LootHistory, LibKa0s v1.68.0 -> v1.68.1)

Sources: `git -C ../LibKa0s log --oneline v1.68.0..v1.68.1` (7 commits, the rename and its release
record), the CHANGELOG `v1.68.1` block (`../LibKa0s/CHANGELOG.md:13-53`), and the `Since` markers
of every major whose minor moved. No major's minor moved, so no `docs/api/<Major>/` document is in
range; the one document that moved is `docs/api/testkit/version-36-docs.md` against
`version-35-docs.md`.

**Zero adoption candidates.** v1.68.1 is a rename-only release: the kit names `/dev-copilot:*`
commands where it named `/wow-addon:*`, and nothing else moves. The interview (Step 6) would have
zero items, so it is skipped, and there is no `03_DECISIONS.md` or `04_EXECUTION_PLAN.md`.

## A. Delivered on the re-vendor alone (not offered)

- **Kit revision 36.** `run-automated-tests.sh` prints `/dev-copilot:bump-version` in the
  `RESULTS.md` lead-in (`version-36-docs.md:35`, `:40-43`); three runner comments and one
  `test_eol.lua` comment follow the rename. This addon's next automated-test run rewrites that one
  `RESULTS.md` line. No member, case, mock or manifest field changes (`:19-23`), so
  `docs/test-cases.md` is unchanged.

## B. Host change required (candidates)

None. No surface was added (`version-36-docs.md:22`; CHANGELOG `v1.68.1`: "no member is added or
removed").

## C. Whole-module adoption

None offered. `LibKa0s-Perf-1.0` is the one major this addon does not look up, and its decline is
settled (the `performance-§12` no-combat-path exemption, `docs/combat-path-sweep.md`). No Perf file
moved in this range, so the premise stands.
