# 01 — Delta: LibKa0s v1.24.0 → v1.25.0

Taken **from the tag**, never from the sibling working tree:
`git -C ../LibKa0s archive v1.25.0 LibKa0s testkit`. This addon's
`tests/test_vendor_sync.lua` resolves the tag its provenance line names and compares
both payloads against it file by file, so a copy from a dirty checkout passes a local
`diff -r` and then fails the gate.

## 3a — Claimed version, before this run

```
grep -n '[Bb]undles' LootHistory/CLAUDE.md
```

> Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) **v1.24.0** (MIT).

## 3b — Actual version, before this run

`OptionsCompose.lua` carried `COMPOSE_MINOR = 1`. The line and the bytes **agreed**:
nothing had been rolled without its payload, in either direction.

## 3c — Per-file minor delta

Read from the tag's `LibKa0s/LibKa0s.xml`, not from a fixed table.

| File | Constant | v1.24.0 | v1.25.0 |
|---|---|---|---|
| `OptionsCompose.lua` | `COMPOSE_MINOR` | 1 | **2** |
| every other shipped file | — | unchanged | unchanged |

**No cross-major skew.** One file moved; the rest are byte-identical, so there is no
consumer carrying a new module over an old one.

## 3d — Both diffs, both directions

```
diff -r --strip-trailing-cr <tag>/LibKa0s LootHistory/libs/LibKa0s   # 1 file: OptionsCompose.lua
diff -r --strip-trailing-cr <tag>/testkit LootHistory/tests/_kit     # empty
```

Content-dirty in exactly one file, which is the release. **No `Only in` lines** — nothing
was removed upstream, so no deletion inside `libs/` is warranted by this run.

## 3e — Consumption map

```
grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua' | grep -v /libs/ | grep -v /tests/
```

Majors reached from this addon's own source: Core DebugLog Env Item Media Options Perf Pool Slash Widgets 

## 3f — Kit revision, and the pairing rule

`Kit.VERSION = 14` on both sides — **unchanged in this release**. Both payloads are still
copied whole in the same commit, which is the rule rather than an optimisation: from
revision 11 on, `vendor_sync.lua` stopped treating `media` as a file and stopped
normalising line endings across binaries, and the two payloads move together so a
consumer can never hold a kit that cannot compare the library it ships.
