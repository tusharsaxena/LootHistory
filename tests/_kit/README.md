# LibKa0s testkit

The shared headless test harness for the Ka0s addon collection: the test registry and assertions,
the source loader, and the universal half of the WoW-API mock.

## It is not a library

`testkit/` is **not** a LibStub major and **must never ship**.

- It has no `MAJOR`/`MINOR`, registers nothing with LibStub, and is never loaded by the client. The
  per-file-minor rule in `library-stack` does not apply to it, and a standards audit **MUST NOT**
  flag the missing version registry.
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
diff -r testkit <Addon>/tests/_kit             # must be empty
cd <Addon> && lua tests/run.lua && luacheck .
```

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
5. **Model the awkward real behaviour, not the convenient one.** AceDB's `copyDefaults` merges in
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
