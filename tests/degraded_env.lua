-- tests/degraded_env.lua — builds a SECOND addon environment with LibKa0s absent.
--
-- LibKa0s is vendored, so it can go missing: a partial unzip, a user pruning libs/, a packager that
-- dropped the folder. Every setup file in this addon carries a degradation stub for that case, and
-- the only honest way to exercise those stubs is a real load without the library — a hand-stub after
-- the fact cannot reproduce a file that failed to finish loading.
--
-- Lifted out of tests/test_libka0s.lua, where it was a file-scope local, when M4-09 moved the parity
-- cases into tests/test_surface_parity.lua: two suites now need the same environment and a second
-- copy of the builder is a second thing to keep in step. It is NOT part of the vendored kit under
-- tests/_kit/ — that folder must stay byte-identical to LibKa0s/testkit — and it is not a suite, so
-- tests/run.lua does not list it; callers dofile it the way they dofile tests/wow_mock.lua.
--
-- Returns `ns, lines`: the namespace the load built, and every line the addon printed while it did.
-- The chat capture is part of the environment rather than an extra the caller wires up, because the
-- one-shot degradation notice is emitted DURING the load — a caller that installed its own
-- AddMessage afterwards would have missed it.
--
-- Nothing here calls InitDB or CreateOptionsPanel, so the shared suite's SavedVariables globals are
-- untouched.
return function()
  local Loader = dofile("tests/_kit/loader.lua")
  -- A fresh loader table per dofile, so this environment sets its own addonName.
  Loader.addonName = "LootHistory"
  local mocks = dofile("tests/wow_mock.lua")()
  local lines = {}
  mocks.DEFAULT_CHAT_FRAME.AddMessage = function(_, line) lines[#lines + 1] = line end
  local ns = {}
  -- libs/LibKa0s/*.lua deliberately not loaded: nothing registers any of the majors, and the mock's
  -- LibStub answers nil for each exactly as the real client would. So this environment exercises
  -- every setup file's degradation path at once, as a load rather than as a hand-stub.
  --
  -- The list is the TOC's, in the TOC's order, and it is the WHOLE list. Both halves matter: whole,
  -- because the load-order hazard this environment exists to catch is a page file calling a helper
  -- at FILE LOAD (settings/Schema.lua reaches NS.Options.MasterControls that way); and the TOC's own
  -- order, because a list that reordered the setup files would let a hoisted lookup pass here and
  -- fail in the client.
  Loader.loadAll(Loader.tocFiles("LootHistory.toc"), ns, mocks)
  return ns, lines
end
