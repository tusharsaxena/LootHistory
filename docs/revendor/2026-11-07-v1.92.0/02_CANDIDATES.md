# 02 Candidates, LibKa0s v1.91.0 -> v1.92.0

Sources: `git -C ../LibKa0s log --oneline v1.91.0..v1.92.0`; LibKa0s CHANGELOG.md (v1.92.0 block, lines 15-34 at the tag); the Compat, Slash, Launcher, Perf, Options and testkit API documents named below.

**Class A, delivered on the copy alone**
- Perf minor 16 reads the specialization name through `C_SpecializationInfo.GetSpecializationInfo` first (CHANGELOG.md:33). Reaches a Perf consumer unmodified.
- Kit revision 52's loader stamps every mock set with its client profile, retail by default (CHANGELOG.md:21); a suite with no `KA0S_KIT_CLIENT` runs as before.

**Class B, host change required (candidates)**
1. Compat client helpers `IsForever`, `IsRetail`, `ClientKey`, `ForClient` (CHANGELOG.md:22; docs/api/Compat/version-2-docs.md:58-61). Additive. Touches the addon's own Compat seam.
2. The `clients` descriptor gate on Options pages, tabs, rows and landing sections, Slash commands and schema rows, Launcher `entryClients` and Keybinds bindings (CHANGELOG.md:24-31). Additive; only a feature that differs per client needs it.
3. The kit's `forever` client profile, run with `KA0S_KIT_CLIENT=forever` (docs/api/testkit/version-52-docs.md:25). Additive; needs per-client expectations in the addon's suites.

**Class C, whole-module**: none new in this range. Majors in the payload this addon does not look up: LibKa0s-Glow-1.0 LibKa0s-IconBrowser-1.0 LibKa0s-Toast-1.0 .

**Blockers (3g)**: none.
