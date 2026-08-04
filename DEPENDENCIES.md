# Dependencies

Everything you need installed to run, develop, test or release **Ka0s Loot History**, with commands
that work on **WSL2 / Ubuntu** — the environment this addon is developed in. Required by
`documentation-§7` of the [Ka0s WoW Addon Standard](https://github.com/tusharsaxena/WowAddonStandards).

This file answers **what to install**. [`docs/testing.md`](docs/testing.md) answers **how to verify**;
neither repeats the other. Every entry below names the evidence for itself — a file:line, an import,
or a documented command. Nothing is listed on a hunch.

---

## 1. Runtime (in-game) — what a player needs

**World of Warcraft (Retail), interface 120007 — Midnight 12.0.7.** Evidence:
`LootHistory.toc:1` (`## Interface: 120007`), mirrored by the README's `[wow]` badge
(`README.md:3`).

**Nothing else.** Every library the addon uses is **vendored** under `libs/` and committed, so the
player installs one addon and no dependencies. `LootHistory.toc:8` declares
`## OptionalDeps: Ace3, LibStub, CallbackHandler-1.0, LibSharedMedia-3.0, LibDataBroker-1.1, LibDBIcon-1.0`
— that line exists only to fix **load order** when a player happens to have those libraries as
standalone addons; the copies under `libs/` (loaded at `LootHistory.toc:16-27`) are what the addon
actually uses (`library-stack`). There is no `## Dependencies` line, and there must not be one.

### Optional in-game integrations (addons, not tooling)

The AH-price columns read three third-party addons **if they are installed**, and are silently
skipped if not. Each is presence-gated at the call site, so none of them is required:

| Addon | Global probed | Evidence |
|-------|---------------|----------|
| Auctionator | `Auctionator.API.v1` | `modules/AuctionPrice.lua:14`, `:103` |
| TradeSkillMaster | `TSM_API.GetCustomPriceValue` / `.ToItemString` | `modules/AuctionPrice.lua:24`, `:105` |
| OribosExchange | `OEMarketInfo` | `modules/AuctionPrice.lua:36`, `:107` |

All three are whitelisted in `.luacheckrc:20` as `read_globals` with the comment "third-party
AH-pricing addon globals (presence-gated)". Each fetch is `pcall`-guarded, so a broken provider is
skipped rather than fatal. They are deliberately **not** in the TOC's `## OptionalDeps` — the addon
never touches them at load, only when a price is gathered.

---

## 2. Development — what a contributor installs

| Tool | Version | Why it is needed | Verify |
|------|---------|------------------|--------|
| **Lua** | **5.1 — a hard requirement** | The headless harness `setfenv`s every loaded chunk into a mock environment (`tests/_kit/loader.lua:31`, `:50`). `setfenv` was **removed in Lua 5.2**, so the suite does not run on 5.2+ — this is a requirement, not a preference. It also matches the client: WoW runs Lua 5.1 (`docs/testing.md:3`). | `lua -v` → `Lua 5.1.x` |
| **luacheck** | any recent (developed against 1.2.0) | The lint gate, `luacheck .`, must report 0 warnings / 0 errors before every commit (`docs/testing.md:129`, `docs/testing.md:137`). Config is `.luacheckrc`. | `luacheck --version` |
| **lizard** | any recent (developed against 1.23.0) | Generates `docs/complexity.md` at release (`performance-§10`; see "The complexity report" in [`docs/testing.md`](docs/testing.md)). **Optional** — its absence means the committed report is stale, not that the addon is broken. | `lizard --version` |
| **git** | any recent | Beyond version control: `tests/test_vendor_sync.lua:53` shells out to `git -C ../LibKa0s show` / `ls-tree` to prove the vendored payload matches the LibKa0s tag the README names. Without `git` on `PATH` those cases skip rather than fail. | `git --version` |
| **A POSIX shell with `ls`** | any | `tests/test_vendor_sync.lua:89` lists a directory with `ls -A` (Lua 5.1 has no directory API and this repo does not depend on LuaFileSystem). A `dir /b` fallback exists for `cmd.exe`; under WSL2 the `ls` path is the one taken. | `ls --version` |
| **`../LibKa0s` checked out beside this repo** | matching the tag the README names | Not a package — a **sibling git checkout**. Two of the four vendor-gate diffs and the `test_vendor_sync` suite compare `libs/LibKa0s/` and `tests/_kit/` against it (`tests/test_vendor_sync.lua:38`, `docs/testing.md:93-100`, `docs/testing.md:157`). Everything else passes without it. | `ls ../LibKa0s/LibKa0s` |

### Install (WSL2 / Ubuntu)

```bash
# Lua 5.1 + luacheck
sudo apt update
sudo apt install -y lua5.1 luarocks git
sudo luarocks install luacheck
```

`lua` must resolve to the 5.1 interpreter. On Ubuntu, `lua5.1` installs as `lua5.1`; if plain `lua`
is missing or points elsewhere, link it:

```bash
sudo update-alternatives --install /usr/bin/lua lua /usr/bin/lua5.1 100
```

`lizard` is a Python tool, and **`pip install lizard` fails on Ubuntu 24.04**: that release marks the
system Python `EXTERNALLY-MANAGED` (PEP 668), so `pip` refuses with
`error: externally-managed-environment`. Use `pipx`, which is the instruction that works:

```bash
sudo apt install -y pipx
pipx ensurepath          # then restart the shell, or: export PATH="$HOME/.local/bin:$PATH"
pipx install lizard
```

The documented alternative, if you would rather not use `pipx`, is to override the guard explicitly:

```bash
pip3 install --user --break-system-packages lizard
```

### Verify the whole toolchain

```bash
lua -v                   # Lua 5.1.x   <- 5.2+ will not run the suite
luacheck --version
lizard --version
git --version
```

---

## 3. Release / assets

**Nothing extra.** There is no build step, no bundler, no code generation, and no asset pipeline:

- Packaging is done by the **CurseForge packager** from `.pkgmeta`, which pulls no externals —
  `.pkgmeta:3-4` states plainly that libraries are vendored in-tree and shipped as-is. Nothing is
  fetched or compiled at package time.
- The art and font under `media/` (`media/logos/*.tga|jpg`, `media/screenshots/*.png`,
  `media/fonts/JetBrainsMono-Regular.ttf` + its `OFL.txt`) are committed **assets, not
  dependencies**: nothing regenerates them, so no image or font tooling is needed.
- The generated docs are produced by tools already listed above —
  `lua tests/run.lua --list > docs/test-cases.md` (`docs/testing.md:121`) and the `lizard`
  invocation in `performance-§10`.

**Python is not a dependency of this addon.** Two things on disk suggest otherwise and both are
residue: `.gitignore:8-10` ignores `__pycache__/` for a `tools/` directory that does not exist, and
an untracked `.pytest_cache/` sits at the root. There are **no** `.py` files in the repo and nothing
imports Python. The only Python in the picture is `lizard`'s own interpreter, which `pipx` manages
for you.

---

## 4. Commands this repo is verified with

Run from the repo root. See [`docs/testing.md`](docs/testing.md) for what each one means and what to
do when it disagrees.

```bash
lua tests/run.lua                                              # headless suite — all green
luacheck .                                                     # 0 warnings / 0 errors
diff -r --strip-trailing-cr ../LibKa0s/LibKa0s libs/LibKa0s    # vendored library, content
diff -r --strip-trailing-cr ../LibKa0s/testkit tests/_kit      # vendored test kit, content
lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .              # complexity report (release only)
```

The first two are the commit gate. The two diffs need `../LibKa0s` beside this repo. The `lizard`
run is a **release** step and is never a commit gate (`performance-§10`).

---

## Keeping this file honest

`documentation-§7` makes this a **MUST NOT drift** document, checked at release with the rest of the
doc set (`documentation-§5`). A new script, a new import, or a dropped tool changes this file **in
the same change** — a dependency list that is wrong is what makes a new contributor's first hour
their last. Listing a library here does not license fetching it at build time: libraries stay
vendored and committed (`library-stack`, `packaging`).
