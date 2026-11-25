# 02 Candidates, LibKa0s v1.113.0 -> v1.114.0

Sources: `git -C ../LibKa0s log --oneline v1.113.0..v1.114.0`; LibKa0s CHANGELOG.md's v1.114.0 block; `docs/api/ForeverDB/version-1-docs.md` (new) and `docs/api/DebugLog/version-23.12.1.5-docs.md` against `version-23.11.1.5-docs.md`.

**Class A, delivered on the copy alone:**
- DebugLogDiagnostics 12: `/lh debug diagnostics`'s report names ForeverDB among the running majors and prints a `ForeverDB:` line (present, loaded, version, plus build and hash when loaded). It never loads the data addon.
- Kit revision 62's regenerated Forever name set. This addon's suites build their own client shapes in `tests/wow_mock.lua`, so nothing visible changes.

**Class B, host change required:** none. The DebugLog major gained no member.

**Class C, whole-module adoption:**
- `LibKa0s-ForeverDB-1.0` (version-1-docs.md, *Lib-level surface*), the reader of WoW Forever's optional ForeverDB data addon. For this addon: the History browser's item tooltip gains "Drops from" (the top three sources, with chances) and "Sold by" (the lowest vendor price seen), through `ItemSources`, `NPC` and `VendorPrice`. It is additive: no code this addon owns is replaced. Recommendation: adopt, as the owner already decided (the run's `03_SPEC.md` §8 answer 1 and §9).

No other new surface arrived in this range.
