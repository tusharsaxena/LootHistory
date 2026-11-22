# 02 Candidates, LibKa0s v1.109.0 -> v1.110.0

Sources: `git -C ../LibKa0s log --oneline v1.109.0..v1.110.0`; LibKa0s CHANGELOG.md's v1.110.0 block; `docs/api/Compat/version-6-docs.md` against `version-5-docs.md`.

**Class A, delivered on the copy alone:** kit revision 60's Forever profile `Enum.BagIndex` (27 members) and `C_Bank.CanViewBank`. This addon's suites build their own client shapes in `tests/wow_mock.lua`, so nothing visible changes.

**Class B, host change required (LibKa0s#101's surfaces, Compat minor 6):**
- `ContainerGroups()` and `CONTAINER_PATTERNS_BY_CLIENT` (version-6-docs.md rows 18 and 23): the shared container groups, replacing this addon's own pattern copy. Adopt: K101-LH-02.
- `CanViewCharacterBank()` (row 19): three-valued; this addon maps nil to readable at the call site (the lead's call 3). Adopt: K101-LH-02.
- `NumPurchasedBankTabs(bankTypeName)` (row 20), replacing `Compat.NumPurchasedCharacterBankTabs`. Adopt: K101-LH-02.
- `BankerKind(interactionType)` (row 21). Adopt: K101-LH-02.
- `UnreadyBankContainers(shape, memory, purchased)` (row 22); the 5 s deadline and the readiness memory stay in this addon (the lead's call 4). Adopt: K101-LH-02.

**Class C, whole-module adoption:** none new in this range.

Any other candidate: none in this range (the release touched `Compat.lua` and the kit only).
