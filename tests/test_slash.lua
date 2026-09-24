local T = _G.LH_TEST
local NS, test, assertTrue, assertEqual = T.NS, T.test, T.assertTrue, T.assertEqual

local Sl = NS.Slash

-- ── FormatSchemaValue: type-aware, schema-driven value formatting (slash-commands-§5) ──

test("FormatSchemaValue renders booleans as true/false", function()
  assertEqual(Sl.FormatSchemaValue({ type = "bool" }, true), "true")
  assertEqual(Sl.FormatSchemaValue({ type = "bool" }, false), "false")
end)

test("FormatSchemaValue applies a row's fmt to numbers (scale → 1.00x)", function()
  assertEqual(Sl.FormatSchemaValue({ type = "number", fmt = "%.2fx" }, 1.0), "1.00x")
end)

test("FormatSchemaValue leaves plain (enum) numbers raw", function()
  assertEqual(Sl.FormatSchemaValue({ type = "number" }, 30), "30")
  assertEqual(Sl.FormatSchemaValue({ type = "number" }, 1), "1")
end)

test("FormatSchemaValue renders an empty table setting as (none)", function()
  assertEqual(Sl.FormatSchemaValue({ type = "table" }, {}), "(none)")
end)

test("FormatSchemaValue renders a table setting as a sorted key set", function()
  assertEqual(Sl.FormatSchemaValue({ type = "table" }, { MAIL = true, KILL = true }),
    "{KILL, MAIL}")
end)

test("FormatSchemaValue omits falsy keys from a table setting", function()
  assertEqual(Sl.FormatSchemaValue({ type = "table" }, { KILL = true, MAIL = false }),
    "{KILL}")
end)

-- ── FormatKV: shared gold-key / white-value line (slash-commands-§5) ──

test("FormatKV colors the key gold and the value white with a default separator", function()
  assertEqual(Sl.FormatKV("settings.enabled", "true"),
    "|cFFFFFF00settings.enabled|r = |cFFFFFFFFtrue|r")
end)

-- ── BuildListLines: grouped, colored, prefixed list output (slash-commands-§5) ──

local function findLine(lines, needle)
  for _, l in ipairs(lines) do if l:find(needle, 1, true) then return l end end
  return nil
end

-- BuildListLines returns tag-LESS content; NS.Print prepends the cyan tag when CliList prints each.

test("list header is the green 'Available settings' line, no trailing colon", function()
  local lines = Sl:BuildListLines()
  assertEqual(lines[1], "|cff33ff99Available settings|r")
  assertTrue(lines[1]:sub(-1) ~= ":", "header must not end in a colon")
end)

test("list emits azure [group] headers in the declared order", function()
  -- The groups are the settings panel's TABS (options-ui-§13) and `/lh list` reads the same
  -- field, so the CLI's section order is the strip's order by construction. Asserted over the
  -- schema's own declared order rather than a second hand-written list, which is how the two
  -- would drift the next time a tab is renamed.
  local lines = Sl:BuildListLines()
  local want, seen = {}, {}
  for _, row in ipairs(NS.Schema.Schema) do
    if not seen[row.group] then seen[row.group] = true; want[#want + 1] = row.group end
  end
  assertTrue(#want >= 2, "there must be several groups, or the ordering below is vacuous")

  local got = {}
  for _, l in ipairs(lines) do
    local g = l:match("^  |cff3399ff%[(.+)%]|r$")
    if g then got[#got + 1] = g end
  end
  assertEqual(table.concat(got, " | "), table.concat(want, " | "),
    "every group gets a header, in declaration order, in the azure bracket form")
  assertEqual(got[1], "Master controls",
    "Master controls is the General page's FIRST tab (options-ui-§15), so it is the first section "
    .. "the CLI lists too")
end)

test("list value rows use FormatKV under their group, four-space indented", function()
  local lines = Sl:BuildListLines()
  local row = findLine(lines, "settings.enabled")
  assertTrue(row ~= nil, "enabled row present")
  assertEqual(row, "    " .. Sl.FormatKV("settings.enabled",
    Sl.FormatSchemaValue(NS.Schema:FindRow("settings.enabled"), NS.Schema:Get("settings.enabled"))))
end)

test("list renders windowScale with its scale fmt", function()
  NS.Schema:Set("settings.windowScale", 1.0)
  local row = findLine(Sl:BuildListLines(), "settings.windowScale")
  assertTrue(row:find("1.00x", 1, true) ~= nil, "windowScale should render as 1.00x, got: " .. tostring(row))
end)

-- ── get / set: single-line echo, Usage + Setting-not-found (slash-commands-§5) ──

-- settings/Slash.lua captured `local print = NS.Print` at load, so swapping the global `print`
-- won't intercept it. Capture at the sink instead: NS.Print writes to DEFAULT_CHAT_FRAME:AddMessage.
local function capture(fn)
  local out = {}
  local cf = T.mocks.DEFAULT_CHAT_FRAME
  local old = cf.AddMessage
  cf.AddMessage = function(_, msg) out[#out + 1] = msg end
  local ok, err = pcall(fn)
  cf.AddMessage = old
  if not ok then error(err) end
  return out
end

test("CliList prints the header through NS.Print, cyan-tagged", function()
  local out = capture(function() Sl:CliList() end)
  assertEqual(out[1], NS.PREFIX .. " |cff33ff99Available settings|r")
end)

test("/lh get echoes a single FormatKV line for a known path", function()
  NS.Schema:Set("settings.enabled", true)
  local out = capture(function() Sl:CliGet("settings.enabled") end)
  assertEqual(#out, 1, "get prints exactly one line")
  assertEqual(out[1], NS.PREFIX .. " " .. Sl.FormatKV("settings.enabled", "true"))
end)

test("/lh get with no argument prints a Usage line", function()
  local out = capture(function() Sl:CliGet("") end)
  assertEqual(out[1], NS.PREFIX .. " Usage: /lh get <path>")
end)

test("/lh get on an unknown path prints Setting not found", function()
  local out = capture(function() Sl:CliGet("nope.not.real") end)
  assertEqual(out[1], NS.PREFIX .. " Setting not found: nope.not.real")
end)

test("/lh set echoes the stored value read back after writing", function()
  local out = capture(function() Sl:CliSet("settings.enabled false") end)
  assertEqual(out[1], NS.PREFIX .. " " .. Sl.FormatKV("settings.enabled", "false"))
  assertEqual(NS.Schema:Get("settings.enabled"), false, "value was actually written")
  NS.Schema:Set("settings.enabled", true) -- restore
end)

test("/lh set a value the row's validate refuses prints INVALID and leaves the value alone", function()
  -- Slash minor 15: the descriptor's `set` hands the seam's `false, err` back to CliSet, which
  -- prints the refusal instead of echoing the unchanged value as though the write had landed.
  local R = NS.SchemaRuntime
  local probe = { path = "settings.__probe", type = "number", group = "Probe", default = 1,
                  validate = function(v) return v < 5 end }
  R.AddRows({ probe })
  NS.db.global.settings.__probe = 1
  local ok, out = pcall(capture, function() Sl:CliSet("settings.__probe 9") end)
  local stored = NS.db.global.settings.__probe
  for i, row in ipairs(NS.Schema.Schema) do if row == probe then table.remove(NS.Schema.Schema, i); break end end
  R.Reindex()
  NS.db.global.settings.__probe = nil
  if not ok then error(out, 0) end
  assertEqual(out[1], NS.PREFIX .. " Invalid value for settings.__probe", "the refusal names the path")
  for _, line in ipairs(out) do
    assertTrue(not line:find(Sl.FormatKV("settings.__probe", "1"), 1, true), "no echo of the old value")
  end
  assertEqual(stored, 1, "the refused value was not stored")
end)

test("/lh set on an unknown path prints Setting not found", function()
  local out = capture(function() Sl:CliSet("nope.not.real 1") end)
  assertEqual(out[1], NS.PREFIX .. " Setting not found: nope.not.real")
end)

test("/lh get minimap.shown reads the row's SHOWN sense; the old minimap.hide path is unknown",
  function()
    -- launcher-§3 (standard v2.65.0): the CLI path reads in the row's own sense, so a player typing
    -- `/lh get minimap.shown` is told whether the button is shown. The one stored key is still
    -- LibDBIcon's `minimap.hide`, which is why `true` is printed while it holds `false`.
    -- red under: the row still pathed at `minimap.hide`, the shape this addon shipped before.
    local mm = NS.db.global.minimap
    local before = mm.hide
    mm.hide = false
    local got = capture(function() Sl:CliGet("minimap.shown") end)
    local set = capture(function() Sl:CliSet("minimap.hide true") end)
    local after = mm.hide
    mm.hide = before
    assertEqual(got[1], NS.PREFIX .. " " .. Sl.FormatKV("minimap.shown", "true"))
    assertEqual(set[1], NS.PREFIX .. " Setting not found: minimap.hide",
      "the old path answers the unknown-path refusal; a `/lh set minimap.hide` macro must be rewritten")
    assertEqual(after, false, "the refused set wrote nothing")
  end)

test("/lh on a legacy store: hide = true reads minimap.shown false, and a set invents no `shown` key",
  function()
    -- The stored key does NOT move (WS-06 carry-over), so a player whose SavedVariables predate the
    -- rename keeps their hidden button with no migration and no schema-version bump. A stored
    -- `shown` key beside `hide` would be a second copy of one state (anti-pattern #81). Seeded IN
    -- PLACE, because LibDBIcon holds this very table (launcher-§3) and a replacement would orphan it.
    -- red under: the row still pathed at `minimap.hide`, or a set that writes at the row's path.
    local mm = NS.db.global.minimap
    local hide, pos = mm.hide, mm.minimapPos
    mm.hide, mm.minimapPos = true, 200
    local ok, err = pcall(function()
      local out = capture(function() Sl:CliGet("minimap.shown") end)
      assertEqual(out[1], NS.PREFIX .. " " .. Sl.FormatKV("minimap.shown", "false"))
      assertEqual(NS.Launcher:IsShown(), false, "the button stays hidden")
      assertEqual(mm.minimapPos, 200, "the button position is untouched by the read")
      capture(function() Sl:CliSet("minimap.shown false") end)
      assertEqual(mm.hide, true)
      capture(function() Sl:CliSet("minimap.shown true") end)
      assertEqual(mm.hide, false, "the set landed on LibDBIcon's own key")
      assertEqual(mm.minimapPos, 200, "the button position is untouched by the sets")
      assertTrue(mm.shown == nil, "no `shown` key is ever written to the raw store")
    end)
    mm.hide, mm.minimapPos = hide, pos
    if NS.Launcher then NS.Launcher:SetShown(not hide) end
    if not ok then error(err, 0) end
  end)

-- ── version verb (slash-commands-§3) ──

test("/lh version prints the cyan-tagged v<version> line", function()
  local out = capture(function() Sl:CliVersion() end)
  assertEqual(out[1], NS.PREFIX .. " v" .. tostring(NS.version))
end)

test("NS.COMMANDS registers a version verb", function()
  local found
  for _, c in ipairs(NS.COMMANDS) do if c[1] == "version" then found = c end end
  assertTrue(found ~= nil, "a 'version' command must be registered")
end)

-- ── reset verbs: reset / resetall / ResetEverything ──

test("/lh reset on a table setting echoes (none), not a raw table pointer", function()
  -- RENDERED CHANGE (LibKa0s adoption). The reset echo used to be a bespoke
  -- "<path> reset to <value>" sentence; it is now the same FormatKV line every list row, get echo
  -- and set echo uses, so a setting reads identically wherever it is printed. The part that
  -- mattered is unchanged and is what this case has always been about: a set-valued row renders as
  -- "(none)" rather than as "table: 0x...", which now happens through the Slash descriptor's
  -- `format` hook (Slash minor 5) instead of a host-side formatter the library never saw.
  NS.Schema:Set("settings.excludedSources", { KILL = true })
  local out = capture(function() Sl:CliReset("settings.excludedSources") end)
  assertEqual(out[1], NS.PREFIX .. " " .. Sl.FormatKV("settings.excludedSources", "(none)"))
  assertEqual(out[1],
    NS.PREFIX .. " |cFFFFFF00settings.excludedSources|r = |cFFFFFFFF(none)|r")
  assertEqual(Sl.FormatSchemaValue(NS.Schema:FindRow("settings.excludedSources"),
    NS.Schema:Get("settings.excludedSources")), "(none)", "value actually reset to empty")
end)

test("/lh resetall also clears the blacklist and whitelist (non-destructive settings reset)", function()
  NS.Filters:AddBlacklist(101)
  NS.Filters:AddWhitelist(202)
  local out = capture(function() Sl:CliResetAll() end)
  -- RENDERED CHANGE: the acknowledgment is the library's, capital A. The filter-list half is not
  -- the library's and cannot be — the id lists are a structural registry with no schema row, so
  -- NS.Slash:CliResetAll wraps the library verb to clear them (through NS.Filters) first.
  assertEqual(out[1], NS.PREFIX .. " All settings reset to defaults")
  assertEqual(NS.Filters:Count(NS.Filters:Blacklist()), 0, "blacklist cleared")
  assertEqual(NS.Filters:Count(NS.Filters:Whitelist()), 0, "whitelist cleared")
end)

-- debug-logging-§10 (standard v2.44.0): a bulk reset through the helper is ONE [Set] line naming the
-- act, its scope and the rows it actually wrote, and never a per-row [Set] line. `/lh resetall`
-- reaches the library's CliResetAll, whose row walk Slash minor 8 brackets with the descriptor's
-- bulkBegin/bulkEnd; the seam mutes its per-row line between the two.

--- The debug console's [Set] lines an act logs, and how many writes the act sent through the seam. The
--- call count is every row the walk touched; the N in the line is only the rows whose stored value
--- changed, so the two differ whenever a row was already at its default. The buffer is swapped for a
--- fresh one for the act: it is capped and shifts when full, so an index taken before can miss.
--- The same, without re-raising: returns the [Set] lines, the seam writes, the act's pcall
--- result and error, and every line logged (any tag).
local function setLinesProtected(act)
  -- Counted at each row's `validate`, which the seam runs on EVERY write, whichever entry
  -- reached it. The bulk walk calls the runtime's ApplyDefault, which writes through the
  -- runtime's own Set and never through the NS.Schema:Set name, so a spy on that name would
  -- count nothing (LibKa0s-Schema-1.0, docs/revendor/2026-09-23-v1.55.0/03_DECISIONS.md C3).
  local writes, stamped = 0, {}
  for _, row in ipairs(NS.Schema.Schema) do
    local own = row.validate
    stamped[row] = own or false
    row.validate = function(...)
      writes = writes + 1
      if own then return own(...) end
      return true
    end
  end
  local saved = NS.DebugLog.buffer
  NS.DebugLog.buffer = {}
  NS.State.debug = true
  local ok, err = pcall(act)
  NS.State.debug = false
  local logged = NS.DebugLog.buffer
  NS.DebugLog.buffer = saved
  for row, own in pairs(stamped) do row.validate = own or nil end
  local lines = {}
  for _, line in ipairs(logged) do
    if line:find("[Set]", 1, true) then lines[#lines + 1] = line end
  end
  return lines, writes, ok, err, logged
end

local function setLinesDuring(act)
  local lines, writes, ok, err, logged = setLinesProtected(function() capture(act) end)
  if not ok then error(err, 0) end
  return lines, writes, logged
end

--- How many rows a BULK reset actually sends through the write seam.
---
--- NOT `#NS.Schema.Schema` any more. launcher-§3 (standard v2.54.0) exempts `minimap.shown` from
--- every bulk reset, so the walk skips it and it is not one of the rows the seam sees. Derived from
--- `NS.Schema.RESET_EXEMPT` rather than written as a number, so this stays a statement about the
--- veto: an exemption added or dropped moves the expectation with it, and a veto that stopped
--- working shows up here as one row too many.
local function rowsThroughSeam()
  local n = 0
  for _, row in ipairs(NS.Schema.Schema) do
    if not NS.Schema.RESET_EXEMPT[row.path] then n = n + 1 end
  end
  return n
end

--- Bring every row to its default, then move exactly two away from it.
local function twoRowsOffDefault()
  capture(function() Sl:CliResetAll() end)
  NS.Schema:Set("settings.qualityThreshold", 4)
  NS.Schema:Set("settings.recordCurrency", false)
end

test("/lh resetall logs ONE [Set] reset all: N rows line, N the rows whose value changed", function()
  -- N is the rows the act actually wrote (debug-logging-§10): a row already at its default is not
  -- counted, although the walk still sends it through the seam for validation and onChange.
  -- red under: an unbracketed walk (one `[Set] <path> = <value>` per row), N taken from the
  -- library's `count` (every row the walk reached), or the summary under any tag but [Set].
  twoRowsOffDefault()
  local lines, writes = setLinesDuring(function() Sl:CliResetAll() end)
  assertEqual(#lines, 1, "exactly one [Set] line per resetall, got: " .. table.concat(lines, " | "))
  assertEqual(writes, rowsThroughSeam(), "every unexempt row still goes through the seam")
  assertTrue(lines[1]:find("[Set] reset all: 2 rows", 1, true) ~= nil,
    "the one line names the act, the scope and the two rows that changed: " .. lines[1])
end)

test("/lh resetall on settings already at their defaults logs [Set] reset all: 0 rows", function()
  -- The act still happened, so it still logs its one line; it wrote nothing, so N is 0.
  capture(function() Sl:CliResetAll() end)
  local lines = setLinesDuring(function() Sl:CliResetAll() end)
  assertEqual(#lines, 1, "one [Set] line, got: " .. table.concat(lines, " | "))
  assertTrue(lines[1]:find("[Set] reset all: 0 rows", 1, true) ~= nil, lines[1])
end)

test("a bracket opened around resetall logs ONE line, summing the rows both levels changed", function()
  -- A host act that wraps CliResetAll opens a second bracket. The inner bulkEnd must not log: the
  -- line is emitted once, when the depth returns to 0, with the tally of every level.
  -- red under: logging at every bulkEnd (two lines), or resetting the tally per level (N = 1).
  twoRowsOffDefault()
  NS.Schema:Set("settings.recordCurrency", true)   -- one row off default is the inner walk's
  local lines = setLinesDuring(function()
    NS.Schema.BulkBegin("reset", "all")
    NS.Schema:Set("settings.qualityThreshold", 1)  -- the outer level's own write
    NS.Schema:Set("settings.recordCurrency", false)
    Sl:CliResetAll()                               -- the inner level: recordCurrency back to true
    NS.Schema.BulkEnd("reset", "all", 0, nil, { profileReset = false })
  end)
  assertEqual(#lines, 1, "one [Set] line for the nested act, got: " .. table.concat(lines, " | "))
  assertTrue(lines[1]:find("[Set] reset all: 3 rows", 1, true) ~= nil, lines[1])
end)

test("a nested bracket where any level reset the profile logs no bulk line", function()
  -- debug-logging-§10: a whole-profile reset is logged once, by the profile-event handler, and no
  -- bracket adds a second line. This addon has no profile, so the flag is the contract only.
  twoRowsOffDefault()
  local lines = setLinesDuring(function()
    NS.Schema.BulkBegin("reset", "all")
    NS.Schema.BulkBegin("reset", "all")
    NS.Schema:Set("settings.qualityThreshold", 1)
    NS.Schema.BulkEnd("reset", "all", 1, nil, { profileReset = true })
    NS.Schema.BulkEnd("reset", "all", 1, nil, { profileReset = false })
  end)
  assertEqual(#lines, 0, "no [Set] line, got: " .. table.concat(lines, " | "))
  -- And the depth is back at 0: the next single write logs its own line again.
  lines = setLinesDuring(function() NS.Schema:Set("settings.recordCurrency", true) end)
  assertEqual(#lines, 1, "the seam was left muted")
end)

test("/lh reset <path> is still ONE [Set] <path> = <value> line, and not muted", function()
  -- A single-row reset is not a bulk act (debug-logging-§10). Pinned beside the bracket so a mute
  -- that outlived resetall would show up here as a missing line.
  NS.Schema:Set("settings.qualityThreshold", 4)
  local lines = setLinesDuring(function() Sl:CliReset("settings.qualityThreshold") end)
  assertEqual(#lines, 1, "one [Set] line, got: " .. table.concat(lines, " | "))
  assertTrue(lines[1]:find("[Set] settings.qualityThreshold = 1", 1, true) ~= nil, lines[1])
end)

test("/lh resetall typed at the dispatcher logs ONE [Set] reset all: N rows line", function()
  -- The cases above call Sl:CliResetAll directly. This one goes in through Sl:OnSlash, the
  -- function AceConsole calls for a typed `/lh resetall`, so the verb table, the host wrapper
  -- and the library bracket are all on the path.
  -- red under: a `resetall` entry in NS.COMMANDS that reaches an unbracketed walk.
  twoRowsOffDefault()
  local lines, writes = setLinesDuring(function() Sl:OnSlash("resetall") end)
  assertEqual(#lines, 1, "one [Set] line for the typed verb, got: " .. table.concat(lines, " | "))
  assertEqual(writes, rowsThroughSeam(), "every unexempt row still goes through the seam")
  assertTrue(lines[1]:find("[Set] reset all: 2 rows", 1, true) ~= nil, lines[1])
end)

test("a row that raises mid-resetall logs ONE line marked as stopped, re-raises, and unmutes", function()
  -- The library calls bulkEnd with the raised value whenever bulkBegin ran, then re-raises it.
  -- The line still comes, once, counting the rows changed before the raise, and says the reset
  -- stopped, so the count is not read as a finished reset. qualityThreshold comes before
  -- recordCurrency in schema order; recordCurrency is written and counted, then its onChange raises.
  -- red under: a BulkEnd that ignores `err` (no marker), or a seam left muted after the raise.
  twoRowsOffDefault()
  local row = NS.Schema:FindRow("settings.recordCurrency")
  local orig = row.onChange
  row.onChange = function() error("boom", 0) end
  local lines, _, ok, err = setLinesProtected(function() Sl:CliResetAll() end)
  row.onChange = orig
  capture(function() Sl:CliResetAll() end)   -- leave every row at its default
  assertTrue(not ok, "the raising row's error must reach the caller")
  assertEqual(err, "boom", "the error is re-raised unchanged")
  assertEqual(#lines, 1, "one line for the one act, got: " .. table.concat(lines, " | "))
  assertTrue(lines[1]:find("[Set] reset all: 2 rows (stopped by an error)", 1, true) ~= nil,
    "the line counts the rows changed before the raise and is marked: " .. lines[1])

  local after = setLinesDuring(function() NS.Schema:Set("settings.qualityThreshold", 3) end)
  NS.Schema:Set("settings.qualityThreshold", 1)
  assertEqual(#after, 1, "the seam logs again once the raising reset is over")
  assertTrue(after[1]:find("stopped by an error", 1, true) == nil, "the marker does not stick")
end)

test("the host seam clears its mute when a bracketed row raises", function()
  -- Host side, no library in the path: a bracket is opened, a write raises from its onChange, and
  -- BulkEnd is handed the error, as the library does. The seam must log its one marked line and
  -- then log the next single write, unmuted and unmarked.
  -- red under: a BulkEnd that does not unwind the depth when `err` is set.
  capture(function() Sl:CliResetAll() end)
  local row = NS.Schema:FindRow("settings.recordCurrency")
  local orig = row.onChange
  row.onChange = function() error("boom", 0) end
  local lines = setLinesDuring(function()
    NS.Schema.BulkBegin("reset", "all")
    local ok, err = pcall(NS.Schema.Set, NS.Schema, "settings.recordCurrency", false)
    NS.Schema.BulkEnd("reset", "all", 1, err, { profileReset = false })
    assertTrue(not ok, "the row raised")
  end)
  row.onChange = orig
  NS.Schema:Set("settings.recordCurrency", true)
  assertEqual(#lines, 1, "one marked line, got: " .. table.concat(lines, " | "))
  assertTrue(lines[1]:find("[Set] reset all: 1 rows (stopped by an error)", 1, true) ~= nil, lines[1])

  local after = setLinesDuring(function() NS.Schema:Set("settings.qualityThreshold", 3) end)
  NS.Schema:Set("settings.qualityThreshold", 1)
  assertEqual(#after, 1, "the mute cleared: a single write logs its own line")
  assertTrue(after[1]:find("[Set] settings.qualityThreshold = 3", 1, true) ~= nil, after[1])
end)

test("an unpaired BulkEnd at depth 0 logs nothing", function()
  -- A BulkEnd with no open bracket muted nothing, so there is no act to report. Before the guard
  -- it re-logged the last act's stale tally.
  -- red under: a BulkEnd that logs whenever the depth is 0 after it.
  twoRowsOffDefault()
  capture(function() Sl:CliResetAll() end)   -- leaves a tally of 2 behind
  local lines = setLinesDuring(function() NS.Schema.BulkEnd("reset", "all", 0, nil, nil) end)
  assertEqual(#lines, 0, "no line, got: " .. table.concat(lines, " | "))
  lines = setLinesDuring(function() NS.Schema:Set("settings.qualityThreshold", 1) end)
  assertEqual(#lines, 1, "the depth did not go negative: a single write still logs")
end)

test("Reset Everything logs ONE [Set] line for the settings it resets, beside its [Data] line", function()
  -- orchestrator ruling 2026-09-12, correcting the earlier "no [Set] line": this addon has no
  -- profile, so the wholesale wipe of db.global is its reset-profile equivalent (options-ui-§12),
  -- and debug-logging-§10 logs a wholesale replacement ONCE, as a [Set] line worded by the act.
  -- It still writes no row through the seam. N is the stored rows the wipe changes: a row at its
  -- default is not counted, nor is the session-only console row, which lives outside db.global.
  -- red under: no [Set] line, or N counting every stored row rather than the two that differ.
  capture(function() Sl:ResetEverything() end)   -- baseline: every row at its default
  NS.Schema:Set("settings.qualityThreshold", 4)
  NS.Schema:Set("settings.recordCurrency", false)
  local lines, writes, logged = setLinesDuring(function() Sl:ResetEverything() end)
  assertEqual(writes, 0, "Reset Everything wrote rows through Schema:Set")
  assertEqual(#lines, 1, "one [Set] line, got: " .. table.concat(lines, " | "))
  assertTrue(lines[1]:find("[Set] reset account-wide settings to defaults (2 rows)", 1, true) ~= nil,
    lines[1])
  local data = 0
  for _, line in ipairs(logged) do
    if line:find("[Data]", 1, true) then data = data + 1 end
  end
  assertEqual(data, 1, "the [Data] data-purge line is unchanged")
end)

test("Reset Everything purges history and clears settings + filter lists + view + window", function()
  NS.db.global.history = { { id = 1 } }
  NS.db.global.savedView = { groupBy = "source" }
  NS.db.global.settings.window = { point = "TOPLEFT", x = 5, y = 5, w = 800, h = 600 }
  NS.Filters:AddBlacklist(303)
  NS.Schema:Set("settings.qualityThreshold", 4)

  capture(function() Sl:ResetEverything() end)

  assertEqual(#NS.db.global.history, 0, "history purged")
  assertEqual(NS.db.global.savedView, nil, "savedView cleared")
  assertEqual(next(NS.db.global.settings.window), nil, "window geometry cleared")
  assertEqual(NS.Filters:Count(NS.Filters:Blacklist()), 0, "blacklist cleared")
  assertEqual(NS.Schema:Get("settings.qualityThreshold"), 1, "schema setting back to default")
end)

test("Reset Everything is WHOLESALE, not a list of keys somebody kept current", function()
  -- The old body was three enumerations -- a history purge, a schema walk and a filter-list clear
  -- -- which between them happened to cover the whole store. That is the shape that quietly stops
  -- being true: anything a later version writes beside them survives a reset that took everything
  -- around it. options-ui-§12 forbids the key list for exactly that reason.
  --
  -- The probe key is one no enumeration could have named, because it does not exist anywhere in
  -- this addon. If it survives, the reset is still working from a list.
  -- red under: reinstating the purge + CliResetAll + ClearAll composition.
  NS.db.global.__probeNothingNames = { deep = { value = 1 } }

  capture(function() Sl:ResetEverything() end)

  assertEqual(NS.db.global.__probeNothingNames, nil,
    "a key no enumeration names survived the reset")
  -- And the declared defaults came back rather than the store being left empty.
  assertEqual(NS.db.global.settings.qualityThreshold, 1)
  assertEqual(type(NS.db.global.history), "table")
end)

test("Reset Everything keeps db.global's IDENTITY, so nothing is left on a stale table", function()
  -- Modules capture NS.db.global at load. Replacing the table would leave every one of them
  -- pointing at the old one -- and a suite that re-reads NS.db.global on every access cannot see
  -- that. So the wipe is in place, which is what the real library does to a profile.
  -- red under: `db.global = deepcopy(defaults)`.
  local before = NS.db.global
  capture(function() Sl:ResetEverything() end)
  assertEqual(NS.db.global, before, "the store was replaced rather than emptied")
end)

-- debug-logging-§8 (v2.44.0 §10): the global reset discards the recorded history along with the
-- settings, and a purge of recorded data is a data mutation the log must show, like Purge and Delete.
test("Reset Everything logs one [Data] line with the history rows it discarded, and nothing when debug is off",
  function()
    NS.State.debug = false
    NS.db.global.history = { { id = 1 }, { id = 2 } }
    local before = #NS.DebugLog.buffer
    capture(function() Sl:ResetEverything() end)
    assertEqual(#NS.DebugLog.buffer, before, "no line logged when debug off")

    NS.db.global.history = { { id = 1 }, { id = 2 }, { id = 3 } }
    NS.State.debug = true
    before = #NS.DebugLog.buffer
    local ok, err = pcall(capture, function() Sl:ResetEverything() end)
    NS.State.debug = false
    if not ok then error(err, 0) end
    local found
    for i = before + 1, #NS.DebugLog.buffer do
      local line = NS.DebugLog.buffer[i]
      if line:find("[Data]", 1, true) then
        assertTrue(found == nil, "exactly one [Data] line per reset")
        found = line
      end
    end
    assertTrue(found ~= nil, "Reset Everything logged no [Data] line")
    assertTrue(found:find("reset-all removed 3 rows", 1, true) ~= nil, "the line carries the count: " .. found)
  end)

test("Reset Everything copies the declared defaults, so a later write cannot change them", function()
  -- NS.Util.DeepCopy was named here but never defined, so the reset fell back to merging
  -- NS.defaults.global's own sub-tables into the store by reference. After Reset all settings,
  -- db.global.settings WAS the defaults table: the next Schema:Set rewrote the declared default,
  -- and `/lh reset` then "restored" the player's own value.
  -- red under: the defaults merged into the store without a copy.
  capture(function() Sl:ResetEverything() end)
  local aliased = NS.db.global.settings == NS.defaults.global.settings
  NS.Schema:Set("settings.qualityThreshold", 4)
  local shipped = NS.defaults.global.settings.qualityThreshold
  NS.Schema:Set("settings.qualityThreshold", 1)   -- before asserting, so a red run poisons nothing
  assertTrue(not aliased, "db.global.settings is the defaults table itself")
  assertEqual(shipped, 1, "a write after the reset changed the declared default")
end)

-- ── prefix color (slash-commands-§4): the shared tag must be cyan ──

test("NS.PREFIX is the mandated cyan [LH] tag", function()
  assertEqual(NS.PREFIX, "|cff00ffff[LH]|r")
end)

-- ── the LibKa0s-Slash-1.0 seam ───────────────────────────────────────────────────────────────
--
-- Slash is one of the three majors that CAN express the `L` trap, so it carries a real RENDERED
-- assertion. This addon passes no `L`; these cases exist so that stops being true loudly.

local lib = T.mocks.LibStub("LibKa0s-Slash-1.0", true)

test("every Slash string this addon renders resolves to prose, not to a key", function()
  local rendered = {
    Sl:BuildListLines()[1],                                    -- LIST_HEADER
    Sl:HelpHeader(),                                           -- HELP_HEADER + HELP_ALIAS
    capture(function() Sl:CliGet("") end)[1],                  -- USAGE_GET
    capture(function() Sl:CliGet("nope.not.real") end)[1],     -- NOT_FOUND
    capture(function() Sl:CliVersion() end)[1],                -- VERSION
  }
  assertEqual(#rendered, 5, "all five must resolve, or the loop below runs over a short list")
  for _, s in ipairs(rendered) do
    assertTrue(type(s) == "string" and s ~= "", "unresolved string")
    -- The cyan tag and the color codes are stripped so a key would be the only thing left that
    -- could match; without this the pattern could never fire on a tagged line and the case would
    -- be one that cannot fail.
    local bare = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
      :gsub("^%[LH%]%s*", ""):gsub("^%s+", ""):gsub("%s+$", "")
    assertTrue(bare:match("^[A-Z][A-Z0-9_]+$") == nil, "rendered as a raw locale key: " .. bare)
  end
  -- The one that pins it hardest: a real sentence, byte for byte.
  assertEqual(Sl:BuildListLines()[1], "|cff33ff99Available settings|r")
  assertEqual(Sl:BuildListLines()[1], lib.STRINGS.LIST_HEADER)
end)

test("the help header names /loothistory as the alias for /lh", function()
  local header = Sl:HelpHeader()
  assertTrue(header:find("slash commands", 1, true) ~= nil, header)
  assertTrue(header:find("/loothistory", 1, true) ~= nil, "the alias must be named: " .. header)
  assertTrue(header:find("/lh", 1, true) ~= nil, header)
end)

-- ── CONVERGENCE #2: one command-row formatter, chat and panel ────────────────────────────────
--
-- settings/Panel.lua's landing page used to carry its OWN row format — double spaces around the em
-- dash, the dash white-wrapped, the description bare — while this file rendered the same data
-- another way. Both now go through lib.FormatRow. The rows below are what a user sees change.

test("LandingRows and HelpRows are the same rows, differing only by the chat indent", function()
  local landing, help = Sl:LandingRows(), Sl:HelpRows()
  assertEqual(#landing, #NS.COMMANDS, "one row per declared command")
  assertEqual(#help, #landing)
  for i = 1, #landing do
    assertEqual(help[i], "  " .. landing[i],
      "the chat form is the landing form with a two-space indent, nothing else")
  end
end)

test("a command row is gold command, single-spaced em dash, white description", function()
  local first = Sl:LandingRows()[1]
  assertEqual(first, "|cFFFFFF00/lh show|r \226\128\148 |cFFFFFFFFOpen the window|r")
  assertEqual(first, lib.FormatRow("/lh show", "Open the window"))
  -- The divergence that is gone: the old landing form put TWO spaces either side of the dash and
  -- wrapped the dash itself in white while leaving the description uncolored.
  assertTrue(first:find("|r  |cffffffff\226\128\148|r  ", 1, true) == nil,
    "the double-spaced, white-wrapped-dash landing form must not come back")
end)

-- ── CONVERGENCE #1: `reset` takes a path ─────────────────────────────────────────────────────

test("reset is path-scoped and resetall is the global verb (no page-shaped form)", function()
  local out = capture(function() Sl:CliReset("") end)
  assertEqual(out[1], NS.PREFIX .. " Usage: /lh reset <path>")
  -- A tab name is not a path, so it is refused rather than silently resetting a whole section.
  local page = capture(function() Sl:CliReset("Capture") end)
  assertEqual(page[1], NS.PREFIX .. " Setting not found: Capture")
end)

-- ── the type-aware parser this addon did not have ────────────────────────────────────────────

test("set refuses a value outside a numeric enum instead of storing it", function()
  local before = NS.Schema:Get("settings.qualityThreshold")
  local out = capture(function() Sl:CliSet("settings.qualityThreshold 9") end)
  assertEqual(out[1], NS.PREFIX .. " Invalid value for settings.qualityThreshold")
  assertTrue(out[2]:find("allowed values: 0, 1, 2, 3, 4, 5, 7", 1, true) ~= nil, tostring(out[2]))
  assertEqual(NS.Schema:Get("settings.qualityThreshold"), before, "nothing was written")
end)

test("set on the composed key-map enum accepts a mode and refuses anything else", function()
  -- `settings.visibility` is the first row in this addon whose `values` is a KEY MAP plus an
  -- explicit `sorting` rather than an array of { value, text } — the shape O.MasterControls emits.
  -- The library's parser reads both, and the CLI has to agree with the panel about what is
  -- selectable or a `/lh set` writes a mode the dropdown cannot show.
  -- red under: dropping `sorting` (the allowed list would come back in pairs() order), or storing
  -- the label instead of the key.
  local before = NS.Schema:Get("settings.visibility")
  local out = capture(function() Sl:CliSet("settings.visibility inCombat") end)
  local stored = NS.Schema:Get("settings.visibility")
  local invalid = capture(function() Sl:CliSet("settings.visibility sometimes") end)
  local after = NS.Schema:Get("settings.visibility")
  NS.Schema:Set("settings.visibility", before)   -- restored BEFORE the assertions, so a red case
                                                 -- cannot leave the mode set for the suites after it

  assertEqual(stored, "inCombat", "the stored value is the KEY, never the label")
  -- The CLI echoes what it STORED, which for a string enum is the key. The panel is where the
  -- label lives; two renderings of one value is exactly the drift the shared formatter ended.
  assertEqual(out[1], NS.PREFIX .. " " .. Sl.FormatKV("settings.visibility", "inCombat"))

  assertEqual(invalid[1], NS.PREFIX .. " Invalid value for settings.visibility")
  assertTrue(invalid[2]:find("always, inCombat, outOfCombat, never", 1, true) ~= nil,
    "the allowed list must be in the declared sorting, not pairs() order: " .. tostring(invalid[2]))
  assertEqual(after, "inCombat", "the refused value was not written")
end)

test("set clamps a number to its slider range and echoes what was stored", function()
  local out = capture(function() Sl:CliSet("settings.windowScale 99") end)
  assertEqual(NS.Schema:Get("settings.windowScale"), 1.6, "clamped to max")
  assertEqual(out[1], NS.PREFIX .. " " .. Sl.FormatKV("settings.windowScale", "1.60x"),
    "the echo re-reads the stored value, which is the only way a clamp is visible")
  NS.Schema:Set("settings.windowScale", 1.0)
end)

test("set refuses a bool it cannot read rather than silently storing false", function()
  NS.Schema:Set("settings.enabled", true)
  local out = capture(function() Sl:CliSet("settings.enabled maybe") end)
  assertEqual(out[1], NS.PREFIX .. " Invalid value for settings.enabled")
  assertEqual(NS.Schema:Get("settings.enabled"), true, "the old value survives a refused write")
end)

test("the set-valued row renders through the format hook, never as <secret>", function()
  -- type = "table" is not one of the library's four types, so lib.FormatValue would fall through to
  -- Core's SafeToString, probe table.concat, fail, and tell the user a plain settings value is
  -- combat-protected. Slash minor 5's `format` hook is what stops that.
  NS.Schema:Set("settings.excludedSources", { MAIL = true, KILL = true })
  local out = capture(function() Sl:CliGet("settings.excludedSources") end)
  assertEqual(out[1], NS.PREFIX .. " " .. Sl.FormatKV("settings.excludedSources", "{KILL, MAIL}"))
  assertTrue(out[1]:find("<secret>", 1, true) == nil, "the sentinel must not reach the user")
  NS.Schema:Set("settings.excludedSources", {})
end)

test("OnSlash dispatches a host verb and lower-cases only the verb", function()
  local seen
  local saved = NS.COMMANDS[1]
  NS.COMMANDS[1] = { "show", "Open the window", function(rest) seen = rest end }
  Sl:OnSlash("SHOW SomePath")
  NS.COMMANDS[1] = saved
  assertEqual(seen, "SomePath", "rest keeps its case; schema paths are case-sensitive")
end)

test("an unknown verb says so and then prints the help index", function()
  local out = capture(function() Sl:OnSlash("nosuchverb") end)
  assertEqual(out[1], NS.PREFIX .. " unknown command 'nosuchverb'")
  assertEqual(out[2], NS.PREFIX .. " " .. Sl:HelpHeader())
  assertEqual(out[3], NS.PREFIX .. " " .. Sl:HelpRows()[1])
end)

-- ── bare `/lh` opens the settings panel (slash-commands-§4, Slash minor 11) ──────────────────
--
-- A bare `/lh` runs the `config` verb with "", which opens the settings panel on its landing page.
-- `/lh help` is the command index. The config handler is swapped for a spy so the case measures the
-- dispatch, not the Settings API mock.

--- Run `act` with NS.COMMANDS' `config` handler replaced by a spy. Returns every call's argument
--- and the chat lines printed. The handler is restored before anything is asserted.
local function withConfigSpy(act)
  local idx
  for i, entry in ipairs(NS.COMMANDS) do if entry[1] == "config" then idx = i end end
  assertTrue(idx ~= nil, "NS.COMMANDS must register a config verb")
  local saved, calls = NS.COMMANDS[idx], {}
  NS.COMMANDS[idx] = { saved[1], saved[2], function(rest) calls[#calls + 1] = rest end }
  local ok, out = pcall(capture, act)
  NS.COMMANDS[idx] = saved
  if not ok then error(out, 0) end
  return calls, out
end

test("bare /lh runs the config verb with an empty argument and prints no help", function()
  -- red under: a dispatcher that answers bare input with PrintHelp (Slash minor 10 and earlier).
  local calls, out = withConfigSpy(function() Sl:OnSlash("") end)
  assertEqual(#calls, 1, "bare /lh must reach the config handler exactly once")
  assertEqual(calls[1], "", "the config handler is called with an empty rest")
  assertEqual(#out, 0, "bare /lh prints nothing of its own: " .. table.concat(out, " | "))
end)

test("whitespace-only /lh is bare too and runs the config verb", function()
  local calls = withConfigSpy(function() Sl:OnSlash("   \t ") end)
  assertEqual(#calls, 1, "whitespace-only input must reach the config handler")
  assertEqual(calls[1], "")
  calls = withConfigSpy(function() Sl:OnSlash(nil) end)
  assertEqual(#calls, 1, "a nil message is bare as well")
end)

test("the config verb opens the settings panel on its landing page", function()
  -- The handler is NS.Panel:Open, which is O.OpenOptionsPanel, which opens the MAIN category (the
  -- landing page), never the General sub-page.
  local saved, opened = NS.Panel.Open, 0
  NS.Panel.Open = function() opened = opened + 1 end
  local ok, err = pcall(Sl.OnSlash, Sl, "config")
  NS.Panel.Open = saved
  if not ok then error(err, 0) end
  assertEqual(opened, 1, "/lh config must call NS.Panel:Open")
  local src = T.Loader.readFile("settings/Panel.lua")
  local body = src:match("function P:Open%(%)(.-)\nend")
  assertTrue(body ~= nil, "settings/Panel.lua must define P:Open")
  assertTrue(body:find("O.OpenOptionsPanel()", 1, true) ~= nil,
    "P:Open must go to O.OpenOptionsPanel, which opens the main (landing) category")
  assertTrue(body:find("OpenToCategory", 1, true) == nil and body:find("General", 1, true) == nil,
    "P:Open must not aim at a sub-page")
end)

test("/lh help prints the command index and does not run the config verb", function()
  local calls, out = withConfigSpy(function() Sl:OnSlash("help") end)
  assertEqual(#calls, 0, "/lh help must not open the settings panel")
  assertEqual(out[1], NS.PREFIX .. " " .. Sl:HelpHeader())
  assertEqual(#out, 1 + #Sl:HelpRows(), "the header plus one row per command")
  for i, row in ipairs(Sl:HelpRows()) do
    assertEqual(out[i + 1], NS.PREFIX .. " " .. row)
  end
end)

-- The library-less install's cases (the degraded help, the refusal line, enable/disable and
-- resetall on that path) live in tests/test_slash_degraded.lua.

-- ── the two reserved verbs (slash-commands-§2) ────────────────────────────────────────────────

test("/lh enable and /lh disable write the Enable row's path, and hold no state of their own",
  function()
    -- ALIASES, never a second switch. Both write `settings.enabled` -- the stored path the Master
    -- controls "Enable Loot History" checkbox writes -- through the SAME single write seam, so the
    -- row's onChange runs and the checkbox and the verbs can never show the player two answers.
    -- red under: a verb that keeps its own flag (an `NS.enabled` local, a session key, a second
    -- stored key), or one that writes db.global directly around Schema:Set.
    local byName = {}
    for _, cmd in ipairs(NS.COMMANDS) do byName[cmd[1]] = cmd[3] end
    assertTrue(byName.enable ~= nil and byName.disable ~= nil,
      "both reserved verbs must be registered")

    local before = NS.db.global.settings.enabled
    -- Every write is recorded, so "through the seam" is asserted rather than inferred from the
    -- stored value -- which a direct table write would also produce.
    local realSet, writes = NS.Schema.Set, {}
    NS.Schema.Set = function(self, path, value)
      writes[#writes + 1] = { path, value }
      return realSet(self, path, value)
    end
    local ok, err = pcall(function()
      capture(function() byName.disable("") end)
      assertEqual(NS.db.global.settings.enabled, false, "/lh disable turns the addon off")
      capture(function() byName.enable("") end)
      assertEqual(NS.db.global.settings.enabled, true, "/lh enable turns it back on")
    end)
    NS.Schema.Set = realSet
    NS.Schema:Set("settings.enabled", before)
    if not ok then error(err, 0) end

    assertEqual(#writes, 2, "each verb is exactly one write, through Schema:Set")
    assertEqual(writes[1][1], "settings.enabled", "the verb writes the Enable row's own path")
    assertEqual(writes[1][2], false)
    assertEqual(writes[2][1], "settings.enabled")
    assertEqual(writes[2][2], true)

    -- No state of their own: the value the verbs set is the value the row reads back, and there is
    -- no second key beside it.
    assertTrue(NS.db.global.settings.enable == nil and NS.db.global.enabled == nil,
      "no second key was invented beside settings.enabled")
    assertTrue(NS.enabled == nil, "no namespace-level flag either")
  end)

test("/lh enable is the same write as /lh set settings.enabled true, and answers the same line",
  function()
    -- slash-commands-§2 sanctions the long form as "the same write by its long name", and this
    -- addon routes the short form THROUGH it -- so the confirmation is slash-commands-§5's `set`
    -- shape by construction, re-read from the store rather than echoed back.
    -- red under: a hand-written acknowledgment that drifts from the `set` line beside it.
    local byName = {}
    for _, cmd in ipairs(NS.COMMANDS) do byName[cmd[1]] = cmd[3] end
    local before = NS.db.global.settings.enabled

    NS.Schema:Set("settings.enabled", true)
    local short = capture(function() byName.disable("") end)
    NS.Schema:Set("settings.enabled", true)
    local long = capture(function() Sl:CliSet("settings.enabled false") end)

    NS.Schema:Set("settings.enabled", before)
    assertEqual(#short, 1, "one line, got: " .. table.concat(short, " | "))
    assertEqual(short[1], long[1], "the two spellings must answer identically")
    assertTrue(short[1]:find("settings.enabled", 1, true) ~= nil, short[1])
  end)

test("the dispatcher answers while the addon is disabled, so the pair is never one-way", function()
  -- slash-commands-§2. *Disabled* means the addon stands its features down; it does NOT mean it
  -- unregisters its chat command, tears down COMMANDS or drops its dispatcher. An addon that did
  -- any of those has built a switch that only goes one way -- the player turns it off and the verb
  -- that turns it back on no longer exists.
  -- red under: gating Sl:Register, OnSlash or any COMMANDS entry on settings.enabled.
  local before = NS.db.global.settings.enabled
  NS.Schema:Set("settings.enabled", false)
  local ok, err = pcall(function()
    -- Bare `/lh` runs the `config` verb (Slash minor 11), which must still reach the panel.
    local opens = 0
    local realOpen = NS.Panel.Open
    NS.Panel.Open = function() opens = opens + 1 end
    capture(function() Sl:OnSlash("") end)
    NS.Panel.Open = realOpen
    assertEqual(opens, 1, "a bare /lh must still open the settings panel with the addon off")

    for _, verb in ipairs({ "help", "version", "list" }) do
      local out = capture(function() Sl:OnSlash(verb) end)
      assertTrue(#out > 0, "/lh " .. verb .. " answered nothing with the addon disabled")
    end

    -- And the one that matters most: the way back.
    capture(function() Sl:OnSlash("enable") end)
    assertEqual(NS.db.global.settings.enabled, true, "/lh enable must work while disabled")
  end)
  NS.Schema:Set("settings.enabled", before)
  if not ok then error(err, 0) end
end)

-- ── a disabled addon refuses a FEATURE verb (slash-commands-§2, standard v2.54.0) ──────────────
--
-- Acting is the wrong answer twice over: the player asked for something the addon is currently
-- standing down from doing, and a silent no-op leaves them with no clue why nothing happened. So a
-- verb that DRIVES THE ADDON'S FEATURES answers on ONE tagged line that names `/lh enable`, and does
-- nothing else. The gate is ONE gate, wrapped round each feature handler as NS.COMMANDS is built
-- (settings/Schema.lua), so every route into a verb passes it -- the library's dispatcher, the
-- positional walk the library-less install falls back to, and a direct call on the triple.

--- slash-commands-§2's live list, verbatim and spelled out here rather than read off the
--- implementation: a test that imported the addon's own set would agree with it however wrong it
--- got. `perf` is on the list and this addon does not register it (performance-§12), which is why
--- the loop below asks NS.COMMANDS which of these exist rather than assuming all twelve do.
local LIVE_WHILE_DISABLED = {
  "help", "config", "version", "enable", "disable", "debug", "perf",
  "get", "set", "list", "reset", "resetall",
}

--- The ONE refusal line, tagged. Spelled out here rather than read off `Sl.DisabledLine`, because
--- a case that imported the addon's own renderer would agree with it however wrong it got --
--- including if it quietly went back to a per-addon wording. slash-commands-§7 fixes the shape
--- collection-wide: the brand name, an em dash with a single space either side, the command in the
--- help index's gold and carrying its leading slash, no trailing colon and no trailing period.
--- It takes no verb: what a refused player needs is the way back in.
local function refusalFor()
  return NS.PREFIX .. " Ka0s Loot History is disabled \226\128\148 "
    .. "enable it with |cFFFFFF00/lh enable|r"
end

--- Run `act` with the addon switched off, and put the switch back however it ends.
---
--- BOTH WRITES GO THROUGH THE SEAM. Restoring by assignment used to be fine and is not any more:
--- the write is what drives the latch now (slash-commands-§7), so a raw `db.global` restore would
--- put the stored value back and leave the addon STOOD DOWN -- registrations gone, window refused --
--- for every suite that runs after this one.
local function whileDisabled(act)
  local before = NS.db.global.settings.enabled
  NS.Schema:Set("settings.enabled", false)
  local ok, err = pcall(act)
  NS.Schema:Set("settings.enabled", before)
  if not ok then error(err, 0) end
end

--- Replace every seam the five feature verbs reach with a counter, run `act`, put them back.
--- Returns how many times the addon ACTED. This is the half a message-only case cannot see: a verb
--- that printed the refusal and then went on to open the window passes an assertion on the line.
---
--- `purge` is counted at StaticPopup_Show, not at Database.Purge, because the mock DOES define the
--- global (tests/_kit/mock_base.lua) -- so the verb raises its confirm dialog and never reaches the
--- database. A counter on Purge alone would report 0 for a `/lh purge` that put the "Delete ALL"
--- popup in front of a player whose addon is switched off, which is exactly the act being forbidden.
local function countingActs(act)
  local acts = 0
  local function bump() acts = acts + 1 end
  local B, BT, D, M = NS.Browser, NS.BrowserTable, NS.Database, T.mocks
  local realShow, realHide, realToggle = B.Show, B.Hide, B.Toggle
  local realTest, realPurge, realPopup = BT.ToggleTestMode, D.Purge, M.StaticPopup_Show
  B.Show, B.Hide, B.Toggle = bump, bump, bump
  BT.ToggleTestMode = function() acts = acts + 1; return false, false end
  D.Purge, M.StaticPopup_Show = bump, bump
  local ok, err = pcall(act, function() return acts end)
  B.Show, B.Hide, B.Toggle = realShow, realHide, realToggle
  BT.ToggleTestMode, D.Purge, M.StaticPopup_Show = realTest, realPurge, realPopup
  if not ok then error(err, 0) end
  return acts
end

test("a disabled addon refuses each FEATURE verb on ONE line naming /lh enable, and does not act",
  function()
    -- BOTH halves, because either alone is passable by a broken implementation: a case that only
    -- read the line would pass over a verb that printed and then acted anyway, and a case that only
    -- counted the acts would pass over one that went silently inert -- which is the no-op §2 calls
    -- the wrong answer in the first place.
    -- red under: no gate at all, a gate that lets the handler run first, or a refusal that does not
    -- name the way back in.
    -- THE SWITCH IS THROWN OUTSIDE THE COUNTERS, and the nesting order is the whole of why. Writing
    -- `enabled = false` now STANDS THE ADDON DOWN (slash-commands-§7), and a stand-down takes the
    -- History window down with it -- through NS.Browser:Hide, which is one of the seams counted
    -- here. Counting from inside the write would score the stand-down itself as a verb acting.
    local acted
    whileDisabled(function()
      acted = countingActs(function(acts)
        for _, verb in ipairs({ "show", "hide", "toggle", "test", "purge" }) do
          local out = capture(function() Sl:OnSlash(verb) end)
          assertEqual(#out, 1, "/lh " .. verb .. " must answer on exactly one line, got: "
            .. table.concat(out, " | "))
          assertEqual(out[1], refusalFor(), "the refusal is the collection's one line, tagged")
          assertTrue(out[1]:find("/lh enable", 1, true) ~= nil,
            "the one line must name the way back in: " .. out[1])
          assertEqual(acts(), 0, "/lh " .. verb .. " ACTED while the addon was disabled")
        end
      end)
    end)
    assertEqual(acted, 0, "not one of the five feature verbs did any work")
  end)

test("the same feature verbs act normally once the addon is enabled — the gate is not always-on",
  function()
    -- The other side of the case above. A gate that refused whatever the switch said would pass
    -- every assertion up there and break the addon outright.
    -- red under: a guard that reads the wrong sense, or one that reads a flag nothing sets.
    NS.Schema:Set("settings.enabled", true)
    local acted = countingActs(function()
      for _, verb in ipairs({ "show", "hide", "toggle", "test", "purge" }) do
        local out = capture(function() Sl:OnSlash(verb) end)
        assertTrue(out[1] == nil or out[1] ~= refusalFor(),
          "/lh " .. verb .. " refused with the addon switched ON")
      end
    end)
    assertEqual(acted, 5, "each of the five reached its own seam exactly once")
  end)

test("the refusal is never turned on a verb slash-commands-§2 keeps live, /lh enable above all",
  function()
    -- Read literally, "refuse while disabled" takes the whole command surface down with it -- and
    -- with it the verb that turns the addon back on. A player must be able to READ AND REPAIR
    -- SETTINGS and REACH THE PANEL while the addon is off, which is precisely when they are most
    -- likely to need to.
    -- red under: a live set that loses a member, or a gate keyed on anything but the verb name.
    local byName = {}
    for _, cmd in ipairs(NS.COMMANDS) do byName[cmd[1]] = true end
    local g = NS.db.global
    local saved = {}
    for k, v in pairs(g) do saved[k] = v end
    local realOpen = NS.Panel.Open
    NS.Panel.Open = function() end

    -- Arguments that make each verb cheap and side-effect-free where one exists; `resetall` has
    -- none, which is why the whole store is saved above.
    local args = {
      get = "settings.scale", set = "settings.scale 1", reset = "settings.scale", debug = "off",
    }
    local ok, err = pcall(function()
      for _, verb in ipairs(LIVE_WHILE_DISABLED) do
        if byName[verb] then
          -- Re-asserted per verb, because `enable` in this very list turns the addon back on.
          NS.Schema:Set("settings.enabled", false)
          local out = capture(function() Sl:OnSlash(verb .. " " .. (args[verb] or "")) end)
          assertTrue(out[1] ~= refusalFor(),
            "/lh " .. verb .. " must keep answering while the addon is disabled")
        end
      end
      -- And the one that matters most, asserted on its effect rather than on its output.
      NS.Schema:Set("settings.enabled", false)
      capture(function() Sl:OnSlash("enable") end)
      assertEqual(NS.db.global.settings.enabled, true, "/lh enable must still turn the addon on")
    end)
    NS.Panel.Open = realOpen
    for k in pairs(g) do g[k] = nil end
    for k, v in pairs(saved) do g[k] = v end
    if not ok then error(err, 0) end
  end)

-- ── /lh debug events: the rejected-names list is reachable (events-frames-taint-§1) ─────────────
--
-- A refused event name is recorded on NS.RejectedEvents, and a record nobody can read is the same
-- silence one layer down. `/lh debug events` prints it, and says "none" rather than nothing, so a
-- player on a healthy client gets an answer too. The debug window is not toggled by it.

test("/lh debug events prints the rejected event names, or none", function()
  local list = NS.RejectedEvents
  assertTrue(type(list) == "table", "NS.RejectedEvents must be the addon-owned list")
  local saved = {}
  for i, v in ipairs(list) do saved[i] = v end
  local ok, err = pcall(function()
    for i = #list, 1, -1 do list[i] = nil end
    local out = capture(function() Sl:OnSlash("debug events") end)
    assertEqual(out[#out], NS.PREFIX .. " rejected events: none")
    list[1], list[2] = "ENCOUNTER_START", "CHAT_MSG_CURRENCY"
    out = capture(function() Sl:OnSlash("debug events") end)
    assertEqual(out[#out], NS.PREFIX .. " rejected events: ENCOUNTER_START, CHAT_MSG_CURRENCY")
  end)
  for i = #list, 1, -1 do list[i] = nil end
  for i, v in ipairs(saved) do list[i] = v end
  if not ok then error(err, 0) end
end)
