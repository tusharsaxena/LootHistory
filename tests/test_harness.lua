-- The harness's own guard rail: the three lists tests/run.lua maintains, pinned.
--
-- testing-§9 names three lists a repo keeps in load order — the TOC (what the client reads), the
-- runner's derivation of it, and the suite list — and only the first is read by anything outside
-- the gate. The other two fail SILENTLY: a derivation that drifts loads a different addon than the
-- client does, and a suite on disk that nobody declared runs zero cases while looking, in the repo,
-- exactly like a suite that runs. The count does not fall; it simply never rose.
--
-- The vendored-library list is pinned separately, against LibKa0s.xml, in tests/test_libka0s.lua
-- ("every file of LibKa0s.xml is vendored and loads") — that list is not derived from the TOC,
-- because Loader.tocFiles skips every `libs\` line by design.

local T = _G.LH_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue
local Loader = T.Loader

-- ── the addon's own load list, as the loader was actually handed it ──────────────────────────
--
-- T.addonFiles is the very table tests/run.lua passed to Loader.loadAll — not a re-derivation. A
-- case that derived the list a second time and compared it with itself could not fail.

test("Harness: the runner fed the loader exactly the TOC's files, in the TOC's order", function()
  local fed   = T.addonFiles
  local fresh = Loader.tocFiles("LootHistory.toc")
  assertTrue(type(fed) == "table", "tests/run.lua must publish the list it loaded as addonFiles")
  assertTrue(#fresh > 0, "LootHistory.toc derived no files at all")
  assertEqual(#fed, #fresh, "the runner loaded " .. #fed .. " addon files but LootHistory.toc "
    .. "names " .. #fresh .. " — the runner is not loading what the client loads")
  for i = 1, #fresh do
    assertEqual(fed[i], fresh[i], "load-order drift at position " .. i .. ": the runner loaded "
      .. tostring(fed[i]) .. " where LootHistory.toc has " .. tostring(fresh[i]))
  end
end)

test("Harness: every path the runner derived from the TOC exists on disk", function()
  for i, path in ipairs(T.addonFiles) do
    local f = io.open(path, "r")
    assertTrue(f ~= nil, "LootHistory.toc names " .. path .. " (position " .. i .. ") but the "
      .. "file is not on disk — the client would fail to load it too")
    if f then f:close() end
  end
end)

test("Harness: no libs/ path leaked into the TOC-derived list", function()
  -- The vendored library is loaded from its own explicit list, in LibKa0s.xml's order. A `libs\`
  -- line reaching the derived list would load the library a second time, in TOC order, silently
  -- re-registering majors at whatever order the TOC happens to spell.
  for _, path in ipairs(T.addonFiles) do
    assertTrue(path:lower():match("^libs[\\/]") == nil,
      "a vendored-library path leaked into the TOC derivation: " .. path)
  end
end)

-- ── the suite list ───────────────────────────────────────────────────────────────────────────

test("Harness: the suite list matches tests/test_*.lua in both directions", function()
  -- Kit.run applies this gate implicitly because tests/run.lua passes an explicit `dir`. Calling it
  -- as a named case is what puts a row in docs/test-cases.md: an implicit gate is invisible to a
  -- reader of the inventory, who cannot tell a gate that ran from one that was opted out of.
  T.assertSuiteInventory("tests/", T.suites)
end)

test("Harness: the runner's suite list has no duplicates", function()
  -- A duplicate is invisible to the inventory gate — both directions are satisfied — but it loads
  -- the suite twice, registering every one of its cases twice and inflating the pass count.
  local seen = {}
  for _, suite in ipairs(T.suites) do
    assertTrue(not seen[suite], "duplicate suite in tests/run.lua: " .. tostring(suite))
    seen[suite] = true
  end
end)

-- ── the runner's lifecycle kick ────────────────────────────────────────────────────────
--
-- The fourth list, and the one that had drifted: tests/run.lua's comment says it does "the
-- lifecycle kick the client's OnInitialize does", and for a while it did not — addon:OnInitialize
-- calls four things and the runner called three, silently omitting NS.Slash:Register. Every suite
-- below it therefore measured an addon initialized differently from the shipped one, which is the
-- exact silent-drift class testing-§9 names.
--
-- Derived from core/LootHistory.lua rather than typed out here, for the same reason the load list
-- is derived from the TOC: a second hand-written copy of OnInitialize's body would drift in step
-- with the first. Parsing the body catches drift in BOTH directions — a step dropped from the
-- runner and a step added to OnInitialize that the runner never learned about.

local function onInitializeCalls()
  local f = io.open("core/LootHistory.lua", "r")
  assertTrue(f ~= nil, "core/LootHistory.lua is not readable — OnInitialize cannot be derived")
  local calls, inside = {}, false
  for line in f:lines() do
    if line:match("^function%s+addon:OnInitialize%s*%(%)") then
      inside = true
    elseif inside and line:match("^end") then
      break
    elseif inside then
      -- Comments first: OnInitialize's body carries a four-line note about the media registration
      -- that used to live here, and prose must never be mistaken for a call.
      local code = line:gsub("%-%-.*$", "")
      -- One pattern for both shapes, so matches come back in source order. `NS:InitDB(` captures
      -- "NS:InitDB"; `NS.Schema:Register(` captures "NS.Schema:Register". The `if NS.Schema and
      -- NS.Schema.Register then` guards are not followed by `(` and so are not calls.
      for expr in code:gmatch("(NS[%.:][%w_]+:?[%w_]*)%s*%(") do
        calls[#calls + 1] = expr
      end
    end
  end
  f:close()
  return calls
end

test("Harness: the runner's lifecycle kick is exactly what addon:OnInitialize calls, in order", function()
  local kicked  = T.lifecycle
  local derived = onInitializeCalls()
  assertTrue(type(kicked) == "table", "tests/run.lua must publish its lifecycle kick as T.lifecycle")
  assertTrue(#derived > 0, "no calls were derived from addon:OnInitialize — the parse is broken, "
    .. "not the runner")
  assertEqual(#kicked, #derived, "the runner kicks " .. #kicked .. " step(s) ("
    .. table.concat(kicked, ", ") .. ") but addon:OnInitialize calls " .. #derived .. " ("
    .. table.concat(derived, ", ") .. ") — the suite is initializing a different addon than the "
    .. "client does")
  for i = 1, #derived do
    assertEqual(kicked[i], derived[i], "lifecycle drift at step " .. i .. ": the runner calls "
      .. tostring(kicked[i]) .. " where addon:OnInitialize calls " .. tostring(derived[i]))
  end
end)
