# 02 Candidates, LibKa0s v1.92.0 -> v1.93.0

Sources: `git -C ../LibKa0s log --oneline v1.92.0..v1.93.0`; LibKa0s CHANGELOG.md, v1.93.0 block; docs/api/testkit/version-53-docs.md; the Options version document for key 37.5.45.3.7.2.9.17.3.1.4.19.13.5.5.8.7.11.1.1.4.

**Class A, delivered on the copy alone**
- OptionsTabs minor 17 and the new OptionsHeader minor 1: the header block and sub-strip moved out of OptionsTabs.lua, no behavior change.
- Kit revision 53: the `client_globals` suite, the missing-globals gate. It reaches every consumer unmodified once wired in tests/run.lua and is the only host change this release needs.

**Class B, host change required (candidates)**: none. Nothing in this range adds a surface a host calls.

**Class C, whole-module**: none new. Majors in the payload this addon does not look up: LibKa0s-Glow-1.0 LibKa0s-IconBrowser-1.0 LibKa0s-Toast-1.0 .

**Blockers (3g)**: none.
