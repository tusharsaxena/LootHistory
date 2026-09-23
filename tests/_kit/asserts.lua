-- testkit/asserts.lua — the assertions and the surface-parity gate, peeled out of framework.lua.
--
-- WHY A SEPARATE FILE (kit revision 26). `framework.lua` crossed `layout-§1`'s 1500-line cap at kit
-- revision 25, and this is the seam that was already there: every member below is a pure function
-- of its arguments and the one piece of state it owns (the surface source), and nothing here reads
-- the registry, the runner or the suite inventory. Moving it changes no behavior. `framework.lua`
-- loads this chunk ONCE, at the point where the block used to stand and before `Kit.expose`, so
-- every member is on the kit table exactly when it was before.
--
-- SHAPE. The file returns `function(Kit)`, which installs its members on the kit table it is handed
-- and returns the two things `framework.lua` itself still needs and must not reach through a public
-- member: `fail`, and a reader for whether a surface source is registered yet. It is not a module a
-- suite loads on its own: `framework.lua` is the entry point, and this file vendors beside it in the
-- same folder.

return function(Kit)

  -- ── assertions ─────────────────────────────────────────────────────────────────────────────
  --
  -- `level + 1` on every failure so the reported line is the CALLER's, not this file's.

  local function fail(msg, level) error(msg, (level or 1) + 1) end
  Kit.fail = fail

  local function fmt(v)
    if type(v) == "table" then return "<table>" end
    return tostring(v)
  end

  function Kit.assertEqual(got, want, msg)
    if got ~= want then
      fail((msg or "assertEqual") ..
        string.format(" (expected %s, got %s)", fmt(want), fmt(got)), 1)
    end
  end

  function Kit.assertTrue(c, msg) if not c then fail(msg or "assertTrue failed", 1) end end
  function Kit.assertFalse(c, msg) if c then fail(msg or "assertFalse failed", 1) end end

  function Kit.assertNil(v, msg)
    if v ~= nil then fail((msg or "assertNil") .. " (got " .. fmt(v) .. ")", 1) end
  end

  --- Float comparison with an explicit tolerance. Never compare computed geometry with `==`.
  function Kit.assertNear(got, want, tolerance, msg)
    tolerance = tolerance or 1e-6
    if type(got) ~= "number" or math.abs(got - want) > tolerance then
      fail((msg or "assertNear") ..
        string.format(" (expected %s +/- %s, got %s)", fmt(want), fmt(tolerance), fmt(got)), 1)
    end
  end

  --- Assert that calling fn raises. Returns the error message so a caller can assert on its text —
  --- an assertion that something raised, without checking WHAT, passes just as happily on a typo in
  --- the test itself.
  function Kit.assertError(fn, msg)
    local ok, err = pcall(fn)
    if ok then fail(msg or "assertError: expected an error, got none", 1) end
    return tostring(err)
  end

  --- Assert that calling fn raises, AND that the raised text contains `needle` (plain text, not a
  --- pattern). Returns the error message. The statement-position form of `assertError` (kit
  --- revision 26): `testing-§12` does not accept "it raised" as proof, since a case that checks only
  --- that passes on a raise from the wrong line, or from a typo in the case itself. Both failures
  --- name the needle, and a mismatch names the raised text too, so a red run shows the real message.
  function Kit.assertErrorMatches(fn, needle, msg)
    local prefix = msg and (msg .. ": ") or ""
    local ok, err = pcall(fn)
    if ok then
      fail(prefix .. ("assertErrorMatches: expected an error containing %q, got no error")
        :format(tostring(needle)), 1)
    end
    err = tostring(err)
    if not err:find(needle, 1, true) then
      fail(prefix .. ("assertErrorMatches: expected an error containing %q, got %q")
        :format(tostring(needle), err), 1)
    end
    return err
  end

  -- ── the surface source ─────────────────────────────────────────────────────────────────────
  --
  -- `Kit.assertSurfaceParity(stub, "LibKa0s-Options-1.0")` names a live surface instead of building
  -- one, which is what turns a parity case into three lines a repo will actually write. The kit
  -- cannot resolve that name on its own: it has no LibStub, no mock and no addon namespace, and
  -- `_G.LibStub` is not it either — the loader hands each chunk a mocked environment rather than
  -- writing into `_G` (`loader.lua`), so a kit that reached for the global would resolve nothing
  -- headlessly and say the stub was fine.
  --
  -- So the harness supplies the source, once, and it takes either shape a harness naturally has:
  --
  --   * a CALLABLE — `Kit.setSurfaceSource(mocks.LibStub)`. Called as `src(name, true)`, which is
  --     LibStub's own silent-lookup signature. This answers the LIBRARY TABLE for a major.
  --   * a TABLE — `Kit.setSurfaceSource{ ["LibKa0s-Options-1.0"] = NS.Helpers }`. A map of name to
  --     live surface, for the far commoner case where the stub mirrors an INSTANCE rather than the
  --     library table. Every `settings/OptionsSetup.lua` degradation arm in this collection stubs
  --     `NS.Helpers`, which is what `lib:New(descriptor)` returned — a surface the kit could never
  --     have built for itself, because it needs the host's descriptor.
  --
  -- `Kit.expose` wires the callable shape automatically when the exposed table carries a mock with a
  -- LibStub on it, so a repo whose stubs mirror library tables registers nothing. Anything else is
  -- one explicit line in the runner, and the assertion FAILS rather than passes when the name does
  -- not resolve — see the bargain in `assertSuiteInventory`.

  local surfaceSource

  --- Register where `Kit.assertSurfaceParity(stub, name)` looks a live surface up, and return the
  --- source that was registered before — so a case that swaps it can put the old one back.
  ---
  --- `src` is a callable, a table, or nil to unregister.
  function Kit.setSurfaceSource(src)
    local previous = surfaceSource
    surfaceSource = src
    return previous
  end

  --- Is `v` reachable as a function call — a plain function, or a table with a `__call`?
  local function callable(v)
    if type(v) == "function" then return true end
    local mt = type(v) == "table" and getmetatable(v)
    return (mt and mt.__call) ~= nil
  end

  --- The live surface registered under `name`, or nil plus why not.
  local function resolveSurface(name)
    if surfaceSource == nil then
      return nil, ("no surface source is registered, so %q cannot be resolved and this gate cannot "
        .. "run — call Kit.setSurfaceSource(mocks.LibStub) or "
        .. "Kit.setSurfaceSource{ [%q] = <the live surface> } in the runner"):format(name, name)
    end
    local live
    if callable(surfaceSource) then
      local ok, got = pcall(surfaceSource, name, true)
      if not ok then
        return nil, ("the surface source raised on %q: %s"):format(name, tostring(got))
      end
      live = got
    else
      live = surfaceSource[name]
    end
    if type(live) ~= "table" then
      return nil, ("the surface source answers %s for %q, not a table — either the name is wrong or "
        .. "the live surface never loaded"):format(type(live), name)
    end
    return live
  end

  -- ── a library constant a degradation stub carries verbatim ────────────────────────────────
  --
  -- `slash-commands-§1` lets a library-absent Slash stub carry exactly one library string verbatim
  -- (`LibKa0s-Slash-1.0`'s `DISABLED_LINE_FORMAT`), on condition that a case pins the copy against
  -- the live library. The surface source is where the live half is looked up, but a runner that
  -- maps the name to an INSTANCE (AbsorbTracker and WhatGroup map "LibKa0s-Slash-1.0" to
  -- `NS.Slash.__cli`, for the parity gate) hands back a table that does not carry a LIB-level
  -- constant. So a member the source's answer lacks is read off the harness's LibStub instead,
  -- which `Kit.expose` records whenever the exposed table carries one, whatever source is set.

  local libraryFallback

  --- Record the LibStub `assertLibraryConstant` falls back to (framework.lua's `Kit.expose`).
  local function setLibraryFallback(ls) libraryFallback = ls end

  --- Read a dotted `path` ("STRINGS.NO_DEFAULT") off table `t`, or nil.
  local function readPath(t, path)
    for part in tostring(path):gmatch("[^%.]+") do
      if type(t) ~= "table" then return nil end
      t = t[part]
    end
    return t
  end

  --- The live value of `memberPath` on major `name`: the registered source first, then LibStub.
  --- Returns the value, or nil plus why not.
  local function resolveConstant(name, memberPath)
    local live, why = resolveSurface(name)
    local v = live and readPath(live, memberPath)
    if v ~= nil then return v end
    if callable(libraryFallback) then
      local ok, lib = pcall(libraryFallback, name, true)
      v = ok and type(lib) == "table" and readPath(lib, memberPath) or nil
      if v ~= nil then return v end
      if not live and not (ok and type(lib) == "table") then
        return nil, ("%q did not resolve to a live library (%s; LibStub has no such major)")
          :format(name, why)
      end
    elseif not live then
      return nil, ("%q did not resolve to a live library (%s)"):format(name, why)
    end
    return nil, ("%q resolved, but carries no member %s"):format(name, tostring(memberPath))
  end

  local function quote(v)
    if type(v) == "string" then return ("%q"):format(v) end
    return fmt(v)
  end

  --- Assert that `value` — a degradation stub's copy of a library constant — is byte-equal to the
  --- live library's `memberPath` (dotted, e.g. "DISABLED_LINE_FORMAT" or "STRINGS.NO_DEFAULT") on
  --- major `majorName`. Fails naming the major and the path when either does not resolve, and
  --- naming BOTH strings when they differ, so a red run shows exactly which byte drifted.
  function Kit.assertLibraryConstant(value, majorName, memberPath, msg)
    local prefix = (msg and (msg .. ": ") or "") .. "assertLibraryConstant: "
    local live, why = resolveConstant(majorName, memberPath)
    if live == nil then fail(prefix .. why, 1) end
    if value ~= live then
      fail(prefix .. ("%s %s is %s, but the copy is %s")
        :format(tostring(majorName), tostring(memberPath), quote(live), quote(value)), 1)
    end
  end

  -- ── the public surface of a live module ────────────────────────────────────────────────────

  --- LibStub bookkeeping. Present on every registered major, carried by no degradation stub in this
  --- collection, and rightly so: `MAJOR` and `MINOR` are how the LIBRARY answers "which copy am I",
  --- and a stub that answered them would be claiming to be the library it is standing in for.
  local BOOKKEEPING = { MAJOR = true, MINOR = true, MODULES = true }

  --- The public members of a live surface, sorted, as `{ { name = ..., kind = <type> }, ... }`.
  ---
  --- Two exclusions, and they are the difference between a gate that gets adopted and one that does
  --- not. `BOOKKEEPING` above, and every `__`-prefixed key: those are the module's own internals —
  --- `__AttachWidgets`, `__widgetsMinor`, `__panelProbeMinor` — reached by a sibling file inside the
  --- same major and by nothing else. Reported raw, the Options major alone would hand a stub author
  --- ten divergences that are all correct omissions, and a gate whose first run is ten false
  --- positives is a gate that gets an `ignore` list the size of its own output.
  function Kit.publicMembers(t)
    local members = {}
    if type(t) ~= "table" then return members end
    for k, v in pairs(t) do
      if type(k) == "string" and not BOOKKEEPING[k] and k:sub(1, 2) ~= "__" then
        members[#members + 1] = { name = k, kind = type(v) }
      end
    end
    table.sort(members, function(a, b) return a.name < b.name end)
    return members
  end

  --- Assert that a degraded-path stub carries the whole surface of the live module.
  ---
  --- Two calling forms:
  ---
  ---   assertSurfaceParity(live, degraded, label, ignore)   -- two tables, compared key for key
  ---   assertSurfaceParity(stub, majorName, ignore)         -- the live half is looked up by name
  ---
  --- The second is selected by a STRING in the second position, and is the one a degradation case
  --- should use: it names the surface instead of rebuilding it, and it compares only the PUBLIC
  --- members (`Kit.publicMembers`), which is what a stub is actually obliged to carry. The first form
  --- compares every key of `live` and is unchanged — a repo comparing two namespaces it built itself
  --- decides for itself what belongs in them.
  ---
  --- `live` is the real thing; `degraded` is what the addon falls back to when the library is not
  --- there. Three of this collection's surviving High findings are one omitted stub member: a stub
  --- returns without assigning `FormatKV`, so the command raises on exactly the degraded path the
  --- stub exists to survive.
  ---
  --- Two divergences are reported:
  ---   * a key present in `live` and ABSENT from `degraded`;
  ---   * a key that is a FUNCTION live and something else degraded — `false`, a table, a string.
  ---     `Helpers.RefreshAllPanels = UI and UI.RefreshAllPanels` is the shape: when `UI` is nil the
  ---     assignment yields nil and the key is simply absent (caught by the first rule); when `UI` is
  ---     present but the member is not, or the guard yields `false`, the key IS there and the call
  ---     site raises anyway. A check that only asks "is the key set?" waves that through.
  ---
  --- EVERY divergence goes into ONE message, not the first. A stub written from a stale surface is
  --- typically wrong in several places, and one-at-a-time is one test run per missing member.
  ---
  --- `ignore` encodes "this member is live-only, on purpose" as data — either as a set
  --- (`{ Foo = true }`) or as an array (`{ "Foo" }`). An intentional omission and a bug are otherwise
  --- indistinguishable, and the usual resolution for that is to delete the case.
  function Kit.assertSurfaceParity(live, degraded, label, ignore)
    -- Form two: `(stub, majorName, ignore)`. A string in the second position is unambiguous — the
    -- first form's second argument is the degraded table, and its third is the label.
    local byName = type(degraded) == "string"
    local publicOnly
    if byName then
      local name = degraded
      local resolved, why = resolveSurface(name)
      if not resolved then fail(name .. ": " .. why, 1) end
      degraded, ignore, label, live = live, label, name, resolved
      publicOnly = true
    end

    label = label or "surface"
    if type(live) ~= "table" then fail(label .. ": the live surface is not a table", 1) end
    if type(degraded) ~= "table" then fail(label .. ": the degraded surface is not a table", 1) end

    local skip = {}
    for k, v in pairs(ignore or {}) do
      if v == true then skip[k] = true else skip[v] = true end
    end

    local keys = {}
    if publicOnly then
      for _, member in ipairs(Kit.publicMembers(live)) do
        if not skip[member.name] then keys[#keys + 1] = member.name end
      end
    else
      for k in pairs(live) do
        if not skip[k] then keys[#keys + 1] = k end
      end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

    local problems = {}
    for _, k in ipairs(keys) do
      local lv, dv = live[k], degraded[k]
      if dv == nil then
        problems[#problems + 1] = ("%s is missing (live: %s)"):format(tostring(k), type(lv))
      elseif type(lv) == "function" and type(dv) ~= "function" then
        problems[#problems + 1] =
          ("%s is a function live but %s degraded"):format(tostring(k), type(dv))
      end
    end

    if #problems > 0 then
      fail(("%s: the degraded stub diverges from the live surface in %d place(s) — %s")
        :format(label, #problems, table.concat(problems, "; ")), 1)
    end
  end

  --- What `framework.lua` needs back: its own `fail`, whether a surface source is registered
  --- (`Kit.expose` wires one only when nothing is), and where to record the LibStub fallback.
  return {
    fail = fail,
    surfaceSource = function() return surfaceSource end,
    setLibraryFallback = setLibraryFallback,
  }

end
