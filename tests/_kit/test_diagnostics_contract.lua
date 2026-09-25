-- testkit/test_diagnostics_contract.lua — the diagnostics dump's dispatcher contract
-- (debug-logging-§14), run against the consumer's own slash dispatcher.
--
-- WHAT IT PROVES. The half of the rule that lives in each addon rather than in the library: that
-- exactly the two forms, `/<slash> diagnostics` and `/<slash> debug diagnostics`, run the report;
-- that both still run it while the addon is disabled; that the report appends after what is already
-- in the console rather than clearing it; that it lands with debug logging off and leaves the flag
-- off; that both markers carry the addon's brand and the end marker counts the lines between them;
-- and that `debug diag`, `diag` and any name this addon retired do not run it. What one report
-- writes is the library's own suite's business (LibKa0s `tests/test_debuglog_diagnostics.lua`);
-- the addon's own suite adds its domain sections.
--
-- IT SHIPS IN THE KIT because the alternative was eleven hand copies of the same eight assertions,
-- which is how every other gate in this collection drifted before the kit carried it.
--
-- WIRING, in the consumer's `tests/run.lua`, before `Kit.run`:
--
--   Kit.diagnostics = {
--     brand       = "Ka0s Aura Master",               -- the descriptor's brandName
--     dispatch    = function(line) ... end,            -- run "/<slash> <line>" through the
--                                                      -- addon's own slash handler
--     console     = function() return NS.DebugLog end, -- the live LibKa0s-DebugLog instance
--     setDebug    = function(on) ... end,              -- write the debug flag directly, no chat
--     setDisabled = function(off) ... end,             -- stand the addon down (true) or up (false)
--     retired     = { "dump" },                        -- optional: this addon's own retired names
--     reset       = function() ... end,                -- optional: run before every case
--   }
--   Kit.run{ dir = "tests/", suites = { ..., { name = "test_diagnostics_contract",
--     dir = "tests/_kit/" } } }
--
-- Declared by the pair like every other kit suite (testing-§9), so the suite inventory goes red
-- until it is wired. Until the addon has its report, `Kit.diagnostics` is unset and the suite
-- registers ONE declared skip that names the rule, rather than failing: a consumer re-vendors the
-- kit before it writes its report, and the re-vendor commit has to stay green. The skip is in the
-- run's output and in `docs/test-cases.md`, so an addon that never wires it is visible, and the
-- standard's audit check reads for it.
--
-- It takes the kit as its chunk argument rather than reading the exposed table, for the reason
-- `test_eol.lua` and `test_layout_cap.lua` do: that table's global name belongs to the consumer.

local Kit = ...
local test, fail = Kit.test, Kit.fail

local RULE = "debug-logging-§14"

-- The words no addon may use for the report, always checked; `retired` adds the addon's own.
local NEVER = { "diag", "dx" }

local facts = Kit.diagnostics

if facts == nil then
  test("diagnostics contract: " .. RULE, nil, "Kit.diagnostics is not set in the runner, so this "
    .. "repo's dispatcher is not wired to the shared contract yet. Every Ka0s addon owes "
    .. RULE .. "'s report; wire Kit.diagnostics once the report exists")
  return
end

if type(facts) ~= "table" then
  fail("diagnostics contract: Kit.diagnostics is the consumer-facts table — { brand, dispatch, "
    .. "console, setDebug, setDisabled } — not a " .. type(facts), 1)
end

-- ── the consumer facts ─────────────────────────────────────────────────────────────────────

local REQUIRED = {
  brand = "string", dispatch = "function", console = "function", setDebug = "function",
  setDisabled = "function",
}

local function checkFacts()
  local missing = {}
  for key, kind in pairs(REQUIRED) do
    if type(facts[key]) ~= kind then missing[#missing + 1] = key .. " (a " .. kind .. ")" end
  end
  table.sort(missing)
  if #missing > 0 then
    fail("diagnostics contract: Kit.diagnostics is missing " .. table.concat(missing, ", "), 3)
  end
  local D = facts.console()
  if type(D) ~= "table" or type(D.buffer) ~= "table" then
    fail("diagnostics contract: Kit.diagnostics.console() must answer the live DebugLog "
      .. "instance, the table whose `buffer` the report is written into", 3)
  end
  return D
end

local BEGIN = "[Diag] ==== " .. tostring(facts.brand) .. " diagnostics begin ===="
local END   = "[Diag] ==== " .. tostring(facts.brand) .. " diagnostics end: "

--- Every buffer index holding a begin marker.
local function begins(D)
  local at = {}
  for i, line in ipairs(D.buffer) do
    if line:find(BEGIN, 1, true) then at[#at + 1] = i end
  end
  return at
end

--- Before every case: the consumer's own reset, logging off, the addon standing up.
local function fresh()
  if type(facts.reset) == "function" then facts.reset() end
  facts.setDisabled(false)
  facts.setDebug(false)
  return checkFacts()
end

--- Dispatch `line` and answer whether it wrote exactly one new report.
local function runs(D, line)
  local before = #begins(D)
  facts.dispatch(line)
  return #begins(D) == before + 1
end

--- Run `fn`, then stand the addon back up whatever happened.
local function whileDisabled(fn)
  facts.setDisabled(true)
  local ok, err = pcall(fn)
  facts.setDisabled(false)
  if not ok then error(err, 0) end
end

local FORMS = { "diagnostics", "debug diagnostics" }

-- ── the cases ──────────────────────────────────────────────────────────────────────────────

test("diagnostics contract: both forms run the report", function()
  local D = fresh()
  for _, form in ipairs(FORMS) do
    Kit.assertTrue(runs(D, form), "/<slash> " .. form .. " wrote one report")
  end
end)

test("diagnostics contract: the debug word is matched in any case", function()
  local D = fresh()
  Kit.assertTrue(runs(D, "debug DIAGNOSTICS"), "/<slash> debug DIAGNOSTICS wrote one report")
end)

test("diagnostics contract: both markers carry the brand and the end counts the report", function()
  local D = fresh()
  facts.dispatch("diagnostics")
  local at = begins(D)
  Kit.assertTrue(#at > 0, "the begin marker reads `" .. BEGIN .. "`")
  local first = at[#at]
  local last = #D.buffer
  -- The report is the last thing written, so its end marker is the buffer's last line.
  local n = tonumber(D.buffer[last]:match("diagnostics end: (%d+) line%(s%) ====$") or "")
  Kit.assertTrue(D.buffer[last]:find(END, 1, true) ~= nil,
    "the last line is the end marker, `" .. END .. "N line(s) ====`: " .. tostring(D.buffer[last]))
  Kit.assertEqual(n, last - first + 1, "N counts every report line, both markers included")
end)

test("diagnostics contract: the report appends after what the console already holds", function()
  local D = fresh()
  local probe = "diagnostics-contract probe line"
  D:Add("Probe", probe)
  facts.dispatch("diagnostics")
  -- red under: a report that calls Clear() before it writes
  local kept
  for i, line in ipairs(D.buffer) do
    if line:find(probe, 1, true) then kept = i end
  end
  Kit.assertTrue(kept ~= nil, "the line written before the report survives it")
  local at = begins(D)
  Kit.assertTrue(#at > 0 and at[#at] > kept, "and the report follows it")
end)

test("diagnostics contract: the report lands with logging off and leaves it off", function()
  local D = fresh()
  facts.setDebug(false)
  -- red under: a report written through the gated D.Debug sink, or one that switches logging on
  Kit.assertTrue(runs(D, "diagnostics"), "the report landed with the flag off")
  Kit.assertFalse(D:IsEnabled(), "and the flag is still off")
end)

test("diagnostics contract: both forms run while the addon is disabled", function()
  local D = fresh()
  whileDisabled(function()
    for _, form in ipairs(FORMS) do
      -- red under: diagnostics missing from the dispatcher's live list, or a debug handler that
      -- refuses while disabled
      Kit.assertTrue(runs(D, form), "/<slash> " .. form .. " wrote one report while disabled")
    end
  end)
end)

test("diagnostics contract: no other name runs the report", function()
  local D = fresh()
  local words = {}
  for _, w in ipairs(NEVER) do words[#words + 1] = w end
  for _, w in ipairs(type(facts.retired) == "table" and facts.retired or {}) do
    words[#words + 1] = tostring(w)
  end
  for _, word in ipairs(words) do
    Kit.assertFalse(runs(D, "debug " .. word), "/<slash> debug " .. word .. " ran the report")
    Kit.assertFalse(runs(D, word), "/<slash> " .. word .. " ran the report")
  end
end)
