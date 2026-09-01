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
  assertEqual(got[1], "Collection", "Collection is the first tab and the first list section")
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

test("/lh set on an unknown path prints Setting not found", function()
  local out = capture(function() Sl:CliSet("nope.not.real 1") end)
  assertEqual(out[1], NS.PREFIX .. " Setting not found: nope.not.real")
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
  -- the library's and cannot be — the two item-id lists are a storage carve-out with no schema row,
  -- so NS.Slash:CliResetAll wraps the library verb to clear them first.
  assertEqual(out[1], NS.PREFIX .. " All settings reset to defaults")
  assertEqual(NS.Filters:Count(NS.Filters:Blacklist()), 0, "blacklist cleared")
  assertEqual(NS.Filters:Count(NS.Filters:Whitelist()), 0, "whitelist cleared")
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
  local page = capture(function() Sl:CliReset("Collection") end)
  assertEqual(page[1], NS.PREFIX .. " Setting not found: Collection")
end)

-- ── the type-aware parser this addon did not have ────────────────────────────────────────────

test("set refuses a value outside a numeric enum instead of storing it", function()
  local before = NS.Schema:Get("settings.qualityThreshold")
  local out = capture(function() Sl:CliSet("settings.qualityThreshold 9") end)
  assertEqual(out[1], NS.PREFIX .. " Invalid value for settings.qualityThreshold")
  assertTrue(out[2]:find("allowed values: 0, 1, 2, 3, 4, 5, 7", 1, true) ~= nil, tostring(out[2]))
  assertEqual(NS.Schema:Get("settings.qualityThreshold"), before, "nothing was written")
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
