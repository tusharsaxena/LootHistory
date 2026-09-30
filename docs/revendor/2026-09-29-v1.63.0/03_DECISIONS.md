# Decisions (LootHistory)

- **C1 (the profile verb):** adopted, by item SP-LH-02 of
  `Ka0sAddonsCommonTasks/docs/2026-09-29-SMOKE_REWORK_AND_PROFILE_VERB/` (spec S3, owner decisions
  D1-D3). Only the Slash minor 17 profile surface is adopted. The candidate-adoption interview and
  the issue filing of this procedure are out of scope for that rollout, so nothing is declined and
  no issue is filed.
- The adoption is its own commit after the re-vendor, `SP-LH-02: /lh profile via CliProfile`: the
  descriptor passes `profiles`, `NS.COMMANDS` gains a `profile` row, the host passes
  `lib.LIVE_VERBS` plus `"profile"` as `liveVerbs`, and the degraded Slash stub carries
  `CliProfile` and `ProfileSwitch`.
- The re-vendor commit needs no stub change: the parity case stays green on the copy alone.
