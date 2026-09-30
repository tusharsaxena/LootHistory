# Candidates (LootHistory)

| # | Surface | What it offers | Blast radius |
|---|---|---|---|
| C1 | Slash minor 17: descriptor `profiles`, `Sl:CliProfile(rest)`, `Sl:ProfileSwitch(name)` (`docs/api/Slash/version-17-docs.md`, "The profile verb") | `/lh profile` lists the profiles with the current one marked; `/lh profile <name>` switches to an existing profile and never creates one. | Additive: one descriptor field, one COMMANDS row, two stub members. |

`lib.ProfileNames(store)` is reached only through `CliProfile` here; the addon has no profile
sub-tree of its own to route through it.
