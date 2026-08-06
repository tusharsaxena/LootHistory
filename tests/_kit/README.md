# LibKa0s testkit

The shared headless test harness for the Ka0s addon collection: the test registry and assertions,
the source loader, the universal half of the WoW-API mock, and the consolidated automated-test
runner.

**The full surface — every function, every mock seam, every fidelity rule — is documented in the
LibKa0s repo under `docs/api/testkit/`, one document per kit revision:**
<https://github.com/tusharsaxena/LibKa0s/tree/master/docs/api/testkit>. This file covers what the kit
*is* and how to vendor it; that directory is the reference, and is the source of truth.

The link is absolute on purpose. This file is byte-identical in eight places — here, this repo's
`tests/_kit/`, and each consumer's — so a relative path that resolved from one would be broken in
the other seven.

## `run-automated-tests.sh`

The collection's consolidated automated-test runner, and the only executable in the kit. It runs the
four out-of-game suites and records every result as one frozen bundle under
`docs/automated-tests/<YYYYMMDD-HHMMSS>/`, then rolls the run into `docs/automated-tests/RESULTS.md`
(see `automated-tests` in the standard).

```sh
tests/_kit/run-automated-tests.sh                            # all four, writes a bundle
tests/_kit/run-automated-tests.sh --suite lint --suite tests # a subset
tests/_kit/run-automated-tests.sh --no-bundle                # print only, write nothing
```

It lives here rather than in each addon for the same reason the rest of the kit does: it must be
byte-identical everywhere, and the vendoring gate below already enforces exactly that. Two things
about it are load-bearing:

- **`lint` and `tests` gate; `perf` and `complexity` do not.** They are measured, recorded and
  diffed, never used to fail the run. `performance-§9`/`§10` are explicit that a wall-clock or
  complexity threshold which fails a run teaches everyone to reach for `--no-verify`, after which
  the gate protects nothing and the habit remains.
- **A missing tool is a skip, not a failure**, and a skip is recorded as one — so a green run that
  actually measured nothing cannot read as a green run that measured everything.

**It is LF, and it must stay LF.** Every other file in this collection is CRLF, pinned by
`.gitattributes`. A `#!/usr/bin/env bash` line followed by CRLF makes the kernel look for an
interpreter literally named `bash\r`, so a CRLF-pinned repo that ships a `.sh` **MUST** carve it out
with `*.sh text eol=lf` — here and in every consumer. Without that line the vendored copy is broken
on every checkout, not in one contributor's.

## `vendor_sync.lua`

The consumer-side vendored-payload gate: it asserts that a repo's `libs/LibKa0s/` and `tests/_kit/`
are exactly what LibKa0s published at the tag that repo's `CLAUDE.md` says it bundles. It used to be
~150 lines copy-pasted into six repos with a one-line delta, which is six chances to fix any one
problem six different ways.

```lua
-- tests/test_vendor_sync.lua
local VendorSync = dofile("tests/_kit/vendor_sync.lua")
VendorSync.register(_G.AT_TEST, {})
```

A factory rather than auto-registration, so the consumer keeps its own test global and its own case
names — the names are what `docs/test-cases.md` counts, and swapping a hand-copied gate for this one
must not move a repo's numbers.

Two things about it living here are deliberate: the gate is **inside the payload it checks**, so a
locally patched `tests/_kit/` breaks the gate's own byte-identity assertion; and **LibKa0s cannot run
it** — there is no sibling to compare against from inside the library repo, which is why
`tests/test_kitsync.lua` is the library-side equivalent.

When the sibling checkout is absent the cases report **SKIP** with the reason, never PASS. Its
comparison contract, including the one line-ending normalization and why it exists, is stated in the
file's own header. Read that header before changing anything about how the bytes are compared.

## It is not a library

`testkit/` is **not** a LibStub major and **must never ship**.

- It has no `MAJOR`/`MINOR`, registers nothing with LibStub, and is never loaded by the client. The
  per-file-minor rule in `library-stack` does not apply to it, and a standards audit **MUST NOT**
  flag the missing version registry.
- It does carry a plain revision integer, `Kit.VERSION` at the top of `framework.lua`, exposed to
  suites as `KIT_VERSION`. That is **not** a LibStub minor and does not make this a library:
  nothing registers it, no load order depends on it, and two copies never negotiate — the vendoring
  gate below is byte-identity, not version comparison. It answers the one question byte-identity
  cannot answer alone: *which* kit is a given consumer holding. One number covers every file in the
  folder, because they vendor as one folder and are never adopted separately.
- It is vendored to `<Addon>/tests/_kit/`, not to `libs/`. `libs/` is the ship payload inside
  `#@no-lib-strip@`; anything there gets zipped. Under `tests/` the **existing** `- tests` entry in
  every addon's `.pkgmeta` already excludes it, so adopting the kit needs no packaging change and
  leaves no new ignore rule for the next scaffold to forget.
- It lives beside the shipping `LibKa0s/` folder rather than inside it, because `docs/releasing.md`
  defines that folder as "the payload and nothing else".

## Vendoring

Same discipline as the library itself:

```sh
cp -r testkit/. <Addon>/tests/_kit/
chmod +x <Addon>/tests/_kit/run-automated-tests.sh   # cp does not always carry the bit
diff -r testkit <Addon>/tests/_kit             # must be empty
cd <Addon> && lua tests/run.lua && luacheck .
```

The consumer's `.gitattributes` needs `*.sh text eol=lf` before the first re-vendor, or the runner
arrives CRLF and cannot execute.

Run the first two from the library repo's root, the same cwd `docs/releasing.md` assumes — the two
files give the same commands and must not disagree about where you are standing.

Never edit `tests/_kit/` in a consumer. A kit problem is a finding to fix here and re-vendor; a
local patch is a fork nobody knows about, and the next re-vendor silently reverts it.

LibKa0s is a consumer on the same terms as every addon: it reaches its own kit through
`tests/_kit/` rather than into `testkit/` directly, so `diff -r testkit tests/_kit` is the same gate
here as it is downstream, and a kit change that would break a consumer breaks this repo first.

## What a consuming `tests/run.lua` looks like

The runner keeps only what is genuinely per-addon: the load list, the lifecycle kick, and the suite
list.

```lua
local Kit    = dofile("tests/_kit/framework.lua")
local Loader = dofile("tests/_kit/loader.lua")
local mocks  = dofile("tests/wow_mock.lua")()   -- the addon's own extender

Loader.addonName = "AbsorbTracker"
local NS = {}
-- Libs first, and every file of LibKa0s.xml spelled out in XML order: the TOC pulls them through
-- the XML, so Loader.tocFiles cannot see them.
Loader.loadAll({ "libs/LibKa0s/Core.lua", ... , "libs/LibKa0s/PerfPanel.lua" }, NS, mocks)
Loader.loadAll(Loader.tocFiles("AbsorbTracker.toc"), NS, mocks)

NS:InitDB()
NS.CreateOptionsPanel()

_G.AT_TEST = Kit.expose{ NS = NS, mocks = mocks }

Kit.run{ dir = "tests/", suites = { "test_schema", ... } }
```

`Kit.expose` merges `test` and the assertions into the table you pass, so each repo keeps its own
global name (`AT_TEST`, `LK_TEST`, `KICKCD_TEST`, …) and its own extra keys, and **no existing suite
file has to change** when a repo adopts the kit.

## What an addon's `tests/wow_mock.lua` looks like

A thin extender over the base. Plain per-key overwrite — the base builder returns a fresh table per
call, so there is no merge machinery to reason about.

```lua
local base = dofile("tests/_kit/mock_base.lua")

return function()
  local M = base()
  M.__absorbs = {}
  M.UnitGetTotalAbsorbs = function(unit) return M.__absorbs[unit] or 0 end
  M.C_ClassColor = { GetClassColor = function() return { r = 1, g = 1, b = 1 } end }
  return M
end
```

Use `M.__stubFrame()` to build extra frame-shaped objects and `M.__libs` to register additional
library fakes (AceDBOptions, LibSharedMedia) without reaching through LibStub's closure.

## Fidelity rules

These are why this is one file rather than eight. Each exists because a friendlier mock already hid
a real bug.

1. **A stub that silently succeeds is worse than no stub.** If production code branches on a return
   value, the mock must return something a branch can distinguish.
2. **Getters used in arithmetic or concatenation must return real numbers and strings.** The
   always-shown-scrollbar patch multiplies `GetHeight()` and concatenates `GetName()`; both raise on
   a table, which is what the metatable's blanket "return the frame" would hand them.
3. **Anything a test needs to observe must be recorded, not no-opped.** Event registration, script
   handlers, widget creation order. A no-op `RegisterUnitEvent` lets a widened or dropped per-unit
   event filter pass the entire suite.
4. **Anything a test needs to drive must be fireable.** `__fire` on frames and on AceGUI widgets is
   what makes a lazy first-`OnShow` render and an `OnValueChanged` write path reachable at all.
5. **Model the awkward real behavior, not the convenient one.** AceDB's `copyDefaults` merges in
   place; AceConsole's `Embed` clobbers a same-named custom `Print`. Both are reproduced, because
   both have already caused a real bug.

## Known divergence, deliberately kept

`CreateTexture` and `CreateFontString` answer from the frame stub's metatable and therefore return
**the frame itself**, not a distinct object. WhatGroup's and KickCD's own mocks make them distinct
and treat that as a correctness requirement — and they are right.

It is kept because changing it is not a harness change. AbsorbTracker's `tests/perf.lua` memoises
frame proxies specifically *because* `bar.valueText` and `bar.statusBar` are the same table, so
distinct objects move its `api/iter` figure — which is the parity gate for library extractions — and
`tests/test_display.lua` counts `Show`/`Hide` calls that currently land on one shared object.
LibKa0s's own `PerfPanel.lua` carries a `__label`/`__state` workaround for the same reason.

Fixing it is a deliberate change with its own test updates and a fresh parity baseline. It is
tracked, not forgotten.
