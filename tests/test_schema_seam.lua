-- tests/test_schema_seam.lua — what a write does through the schema seam: the characterization pinned
-- before it moved to LibKa0s-Schema-1.0, the handover, the retention-shortening confirm and the
-- stored-setting guard. Moved out of tests/test_schema.lua, which keeps the row contract.
local T = _G.LH_TEST
local NS, test, assertTrue, assertEqual, assertFalse =
  T.NS, T.test, T.assertTrue, T.assertEqual, T.assertFalse

local S = NS.Schema

-- ── The seam's behavior, pinned before it moved to LibKa0s-Schema-1.0 ───────────────────────────
--
-- Characterization, written BEFORE settings/Schema.lua handed its seam to the library: what one
-- write returns and in what order it logs and reacts on the live build, and on the DEGRADED build
-- (tests/degraded_env.lua, no libs/ loaded) that every writer and runtime reader a player can reach
-- still works. The degraded half is what the host's own stub has to keep true once the library owns
-- the live seam.

--- A degraded namespace with a store seeded from its own shipped defaults, the way AceDB would.
local function degradedWithStore()
  local ns = dofile("tests/degraded_env.lua")()
  -- AceDB is vendored beside the addon, not inside LibKa0s, so a degraded install still has a real
  -- profile store: the kit's AceDB fake, over a fresh SavedVariables table.
  ns.db = T.mocks.LibStub("AceDB-3.0"):New({}, ns.defaults, true)
  return ns
end

test("seam: Set answers true, or false and a reason, in the host's own words", function()
  assertEqual(select("#", S:Set("settings.recordCurrency", true)), 1)
  assertEqual(S:Set("settings.recordCurrency", true), true)
  local ok, err = S:Set("settings.nosuchthing", 1)
  assertEqual(ok, false)
  assertEqual(err, "unknown path: settings.nosuchthing")
  local row = S:FindRow("settings.windowScale")
  row.validate = function() return false end
  local ok2, err2 = S:Set("settings.windowScale", 1.1)
  row.validate = nil
  assertEqual(ok2, false)
  assertEqual(err2, "invalid value")
end)

test("seam: one write logs its [Set] line, then runs onChange, once each", function()
  local row = S:FindRow("settings.recordCurrency")
  local saved, events = row.onChange, {}
  local savedDebug = NS.Debug
  row.onChange = function(v) events[#events + 1] = "onChange " .. tostring(v) end
  NS.Debug = function(tag, fmt, ...) events[#events + 1] = tag .. " " .. fmt:format(...) end
  NS.State.debug = true
  local ok, err = pcall(S.Set, S, "settings.recordCurrency", false)
  NS.State.debug = false
  NS.Debug, row.onChange = savedDebug, saved
  S:Set("settings.recordCurrency", true)
  if not ok then error(err, 0) end
  assertEqual(table.concat(events, " | "), "Set settings.recordCurrency = false | onChange false")
end)

test("seam: on the degraded build a write lands, is copied, reacts, and an unknown path is refused",
  function()
    local ns = degradedWithStore()
    local row = ns.Schema:FindRow("settings.excludedSources")
    local got
    row.onChange = function(v) got = v end
    local live = { KILL = true }
    assertEqual(ns.Schema:Set("settings.excludedSources", live), true)
    live.AH = true
    assertEqual(ns.db.profile.settings.excludedSources.KILL, true, "the write landed")
    assertEqual(ns.db.profile.settings.excludedSources.AH, nil, "as a copy")
    assertTrue(got == live, "onChange got the value as given")
    local ok, err = ns.Schema:Set("settings.nosuchthing", 1)
    assertEqual(ok, false)
    assertEqual(err, "unknown path: settings.nosuchthing")
    assertEqual(ns.db.profile.settings.nosuchthing, nil, "and nothing was stored")
  end)

test("seam: on the degraded build the runtime readers read the store", function()
  local ns = degradedWithStore()
  assertEqual(ns.Schema:Get("settings.rowHeight"), ns.defaults.profile.settings.rowHeight)
  assertFalse(ns.AddonIsOff(), "enabled by default")
  ns.db.profile.settings.enabled = false
  assertTrue(ns.AddonIsOff(), "core/LifecycleSetup.lua reads the switch through the seam")
end)

test("seam: on the degraded build the composed Master controls rows are absent, and refused", function()
  -- The degraded Options stub's MasterControls composes no rows, so the minimap, enable and session
  -- rows do not exist here. A write to one is refused like any unknown path and stores nothing.
  local ns = degradedWithStore()
  assertEqual(ns.Schema:FindRow("minimap.shown"), nil)
  assertEqual(ns.Schema:Set("minimap.shown", false), false)
  assertEqual(ns.db.global.minimap.hide, false, "the store is untouched")
end)

test("seam: on the degraded build ApplyDefault restores, and spares an exempt row only in a sweep",
  function()
    -- The exemption is exercised on a row the degraded build HAS, by naming it in the same
    -- RESET_EXEMPT table the seam reads, and restored before asserting.
    local ns = degradedWithStore()
    local S2, g = ns.Schema, ns.db.profile
    local q, c = S2:FindRow("settings.qualityThreshold"), S2:FindRow("settings.recordCurrency")
    g.settings.qualityThreshold, g.settings.recordCurrency = 4, false
    S2.RESET_EXEMPT[c.path] = c.path   -- row path -> stored path; the same here
    local ok, err = pcall(function()
      S2.BulkBegin("reset", "all")
      S2:ApplyDefault(q)
      S2:ApplyDefault(c)
      S2.BulkEnd("reset", "all", 2, nil, { profileReset = false })
    end)
    local sweptC = g.settings.recordCurrency
    S2:ApplyDefault(c)
    S2.RESET_EXEMPT[c.path] = nil
    if not ok then error(err, 0) end
    assertEqual(g.settings.qualityThreshold, ns.defaults.profile.settings.qualityThreshold)
    assertEqual(sweptC, false, "a sweep never resets an exempt row (launcher-3)")
    assertEqual(g.settings.recordCurrency, true, "a named reset still does")
  end)

test("seam: on the degraded build the reset resets the profile and keeps the hidden minimap button", function()
  -- The global reset is AceDB's ResetProfile on this path too; the button's table is global.
  local ns = degradedWithStore()
  ns.db.profile.settings.qualityThreshold = 4
  ns.db.global.minimap.hide = true
  ns.Slash:CliResetAll()
  assertEqual(ns.db.profile.settings.qualityThreshold, ns.defaults.profile.settings.qualityThreshold)
  assertEqual(ns.db.global.minimap.hide, true, "the profile reset cannot reach the global table")
end)

test("seam: on the degraded build the boot check passes", function()
  local ns = degradedWithStore()
  assertEqual(ns.Schema:Register(), 0)
end)

test("seam: on the degraded build the boot check skips a row that owns its storage", function()
  -- The host stub's R.Validate takes the same skip as the library's: a row with its own get AND
  -- set is not looked up in defaults/Profile.lua. The degraded build composes no minimap row, so the
  -- shape is probed with a row of its own, pulled before asserting.
  -- red under: a stub Validate that calls defaultsRoot without the row, or ignores its answer.
  local ns = degradedWithStore()
  local rows = ns.Schema.Schema
  rows[#rows + 1] = { path = "probe.ownsStorage", type = "bool", default = true,
    get = function() return true end, set = function() end }
  local problems = ns.Schema:Register()
  rows[#rows] = nil
  assertEqual(problems, 0, "a row that owns its storage is not a missing path")
end)

-- ── The seam is LibKa0s-Schema-1.0's ──────────────────────────────────────────────────────────

test("seam: the live runtime is the library's, and the host names reach it", function()
  local lib = T.mocks.LibStub("LibKa0s-Schema-1.0", true)
  assertTrue(lib ~= nil and NS.SchemaLib == lib, "settings/Schema.lua resolved the major")
  local R, hit = NS.SchemaRuntime, nil
  local realSet = R.Set
  R.Set = function(path, value) hit = path; return realSet(path, value) end
  local ok, err = pcall(S.Set, S, "settings.recordCurrency", true)
  R.Set = realSet
  if not ok then error(err, 0) end
  assertEqual(hit, "settings.recordCurrency", "NS.Schema:Set delegates to the runtime's Set")
  assertTrue(S.BulkBegin == R.BulkBegin and S.BulkEnd == R.BulkEnd, "the bracket is the runtime's")
  assertTrue(R.AllRows() == S.Schema, "the rows are held by reference, never copied")
end)

test("seam: a write with no store yet is refused, not raised", function()
  -- Before InitDB there is no db.profile. The old seam indexed nil and raised; the runtime's root
  -- resolver answers `nil, 1`, which it reads as "nowhere, now".
  local saved = NS.db
  NS.db = nil
  local ok, a, b = pcall(S.Set, S, "settings.recordCurrency", false)
  local got = S:Get("settings.recordCurrency")
  NS.db = saved
  assertTrue(ok, "no raise: " .. tostring(a))
  assertEqual(a, false)
  assertTrue(type(b) == "string" and b:find("settings.recordCurrency", 1, true) ~= nil, tostring(b))
  assertEqual(got, nil, "and a read answers nil")
  assertEqual(NS.db.profile.settings.recordCurrency, true, "nothing reached the real store")
end)

test("seam: a bracket counts a closure row's READ-BACK, so a write that did not move counts 0", function()
  -- JC-8. A closure row may store something other than what it was handed (a refused test-mode
  -- start leaves the box unticked). The old tally compared the argument with the value before, and
  -- counted it; the read-back does not, because the row did not move.
  local R = NS.SchemaRuntime
  local probe = { path = "test.readback", default = false, type = "bool", group = "Probe",
                  get = function() return false end, set = function() end }
  R.AddRows({ probe })
  local lines = {}
  local savedDebug = NS.Debug
  NS.Debug = function(tag, fmt, ...) lines[#lines + 1] = tag .. " " .. fmt:format(...) end
  NS.State.debug = true
  local ok, err = pcall(function()
    S.BulkBegin("reset", "probe")
    S:Set("test.readback", true)
    S.BulkEnd("reset", "probe", 1, nil, { profileReset = false })
  end)
  NS.State.debug = false
  NS.Debug = savedDebug
  for i, row in ipairs(S.Schema) do if row == probe then table.remove(S.Schema, i); break end end
  R.Reindex()
  if not ok then error(err, 0) end
  assertEqual(S:FindRow("test.readback"), nil, "the probe is gone again")
  assertEqual(table.concat(lines, " | "), "Set reset probe: 0 rows")
end)

test("seam: Register reports a duplicate path and a row with no group", function()
  -- JC-13: the boot check now validates the rows' shape as well as their paths.
  assertEqual(S:Register(), 0, "the shipped schema must validate clean")
  local first = S.Schema[1]
  S.Schema[#S.Schema + 1] = { path = first.path, default = first.default, type = first.type,
                              group = first.group }
  local dup = S:Register()
  -- The same slot, now a row whose path is new and resolves (the window geometry's table is in
  -- defaults/Global.lua) but which names no group, so the group is the only thing wrong with it.
  S.Schema[#S.Schema] = { path = "settings.window", default = {}, type = "table" }
  local groupless = S:Register()
  S.Schema[#S.Schema] = nil
  assertEqual(dup, 1, "a path declared twice is reported, once")
  assertEqual(groupless, 1, "a row with no group is reported, once")
  assertEqual(S:Register(), 0, "the probes are gone again")
end)

test("seam: on the degraded build the boot check still reports a typo'd path, in its own words", function()
  local ns = degradedWithStore()
  local printed = {}
  local savedPrint = ns.Print
  ns.Print = function(line) printed[#printed + 1] = line end
  ns.Schema.Schema[#ns.Schema.Schema + 1] = { path = "settings.nosuchbranch.typo", default = true,
                                              type = "bool", group = "Probe" }
  local n = ns.Schema:Register()
  ns.Print = savedPrint
  assertEqual(n, 1)
  assertEqual(table.concat(printed, " | "),
    "schema path does not resolve against defaults/Profile.lua: settings.nosuchbranch.typo")
end)

-- ── Keep history for: a shorter retention asks before it deletes (LootHistory-R-04) ─────────────
--
-- The row's onChange used to call Database:PruneOld() on the spot, so a dropdown mis-click or
-- `/lh set settings.retentionDays 7` dropped every older record in the same action. It now counts
-- what the new value would delete and raises KA0S_LOOTHISTORY_PRUNE; Yes prunes, No writes the
-- last confirmed value back through Schema:Set. The kit's StaticPopup_Show is a no-op function, so
-- the popup-present path is the default here; the popup-absent case removes it.

--- Run `fn(shown)` over five seeded rows (three older than 7 days, two fresh) at a confirmed
--- 30-day retention, with StaticPopup_Show spied. History, the setting, the confirmed value, the
--- mock and the print record are all restored before anything raises.
local function withRetentionFixture(fn)
  local M, g = T.mocks, NS.db.global
  local savedHistory, savedDays, savedShow = g.history, g.retentionDays, M.StaticPopup_Show
  local now, day = os.time(), 86400
  g.history = {
    { ts = now - 40 * day, itemID = 1 }, { ts = now - 20 * day, itemID = 2 },
    { ts = now - 10 * day, itemID = 3 }, { ts = now - 2 * day, itemID = 4 },
    { ts = now - 3600, itemID = 5 },
  }
  g.retentionDays = 30   -- account-wide (D6): the row's own get/set read and write it here
  S:SyncRetention()
  local shown = {}
  M.StaticPopup_Show = function(which, a1, a2, data)
    shown[#shown + 1] = { which = which, a1 = a1, a2 = a2, data = data }
  end
  M.__resetPrinted()
  local ok, err = pcall(fn, shown)
  g.history, g.retentionDays, M.StaticPopup_Show = savedHistory, savedDays, savedShow
  S:SyncRetention()
  if not ok then error(err, 0) end
end

test("Retention: a shorter value raises the prune confirm and deletes nothing yet", function()
  -- red under: the old onChange, which pruned to 2 rows before any confirm existed.
  withRetentionFixture(function(shown)
    S:Set("settings.retentionDays", 7)
    assertEqual(#NS.db.global.history, 5, "records were deleted before the player confirmed")
    assertEqual(#shown, 1, "exactly one confirm is raised")
    assertEqual(shown[1].which, "KA0S_LOOTHISTORY_PRUNE")
    assertEqual(shown[1].a1, "7 days", "the confirm names the new retention by its label")
    assertEqual(shown[1].a2, 3, "the confirm names how many records would go")
    assertEqual(shown[1].data and shown[1].data.days, 7)
  end)
end)

test("Retention: accepting the prune confirm deletes the older records", function()
  withRetentionFixture(function()
    S:Set("settings.retentionDays", 7)
    local dlg = T.mocks.StaticPopupDialogs.KA0S_LOOTHISTORY_PRUNE
    assertTrue(dlg ~= nil, "KA0S_LOOTHISTORY_PRUNE is not registered")
    assertEqual(dlg.timeout, 0); assertTrue(dlg.whileDead and dlg.hideOnEscape and dlg.showAlert)
    dlg.OnAccept(nil, { days = 7 })
    assertEqual(#NS.db.global.history, 2)
    assertEqual(NS.db.global.retentionDays, 7)
  end)
end)

test("Retention: declining restores the confirmed value, keeps every record, prints one line", function()
  withRetentionFixture(function(shown)
    S:Set("settings.retentionDays", 7)
    T.mocks.__resetPrinted()
    T.mocks.StaticPopupDialogs.KA0S_LOOTHISTORY_PRUNE.OnCancel(nil, { days = 7 })
    assertEqual(NS.db.global.retentionDays, 30, "the previous retention was not restored")
    assertEqual(#NS.db.global.history, 5, "declining deleted records")
    assertEqual(#shown, 1, "writing the old value back must not raise a second confirm")
    local printed = T.mocks.__printed()
    assertEqual(#printed, 1, "decline prints exactly one line: " .. table.concat(printed, " | "))
    assertTrue(printed[1]:find("retention kept at 30 days; no records were deleted.", 1, true) ~= nil,
      "unexpected decline line: " .. printed[1])
  end)
end)

test("Retention: accepting applies the agreed value even when the store has moved", function()
  -- red under: an accept that pruned to whatever the store held and only recorded `days`.
  withRetentionFixture(function()
    S:Set("settings.retentionDays", 7)
    NS.db.global.retentionDays = 90
    T.mocks.StaticPopupDialogs.KA0S_LOOTHISTORY_PRUNE.OnAccept(nil, { days = 7 })
    assertEqual(NS.db.global.retentionDays, 7, "the store does not hold the agreed value")
    assertEqual(#NS.db.global.history, 2, "the prune did not run at the agreed value")
  end)
end)

test("Retention: re-showing the confirm over an open one does not run the decline", function()
  -- Blizzard's StaticPopup_Show cancels a visible dialog of the same `which` with reason
  -- "override" before re-showing it. red under: an OnCancel that treated that as a No.
  withRetentionFixture(function(shown)
    S:Set("settings.retentionDays", 7)
    S:Set("settings.retentionDays", 14)
    assertEqual(#shown, 2)
    T.mocks.__resetPrinted()
    local dlg = T.mocks.StaticPopupDialogs.KA0S_LOOTHISTORY_PRUNE
    dlg.OnCancel(nil, { days = 7 }, "override")
    assertEqual(NS.db.global.retentionDays, 14, "the override restored the old value")
    assertEqual(#T.mocks.__printed(), 0, "the override printed a decline line")
    dlg.OnAccept(nil, { days = 14 })
    assertEqual(NS.db.global.retentionDays, 14)
    assertEqual(#NS.db.global.history, 3, "the prune did not run at 14 days")
  end)
end)

test("Retention: with no StaticPopup_Show a shorter value prunes at once", function()
  withRetentionFixture(function()
    T.mocks.StaticPopup_Show = nil
    S:Set("settings.retentionDays", 7)
    assertEqual(#NS.db.global.history, 2)
  end)
end)

test("Retention: a value that would delete nothing raises no confirm and prunes nothing", function()
  withRetentionFixture(function(shown)
    S:Set("settings.retentionDays", 60)
    assertEqual(#shown, 0, "a confirm for zero records")
    assertEqual(#NS.db.global.history, 5)
    assertEqual(NS.Database:CountOlderThan(0), 0, "Always counts nothing")
    assertEqual(NS.Database:CountOlderThan(nil), 0)
  end)
end)

-- ── The stored-setting guard (item 020, settings layout) ──────────────────────────────────────
--
-- Item 020 moves, regroups and relabels rows, and nothing else: no stored path, no default, no
-- range and no type may move with them (the owner's rule for that item). Every row's path, type,
-- default and slider range, pinned as they stood BEFORE the layout pass, sorted by path so a row
-- that moves between tabs leaves this list alone. A layout change that also renamed a key, shifted
-- a default or retuned a range is a named failure here rather than a silent migration.
-- red under: renaming a stored path, changing any default (a scalar, or a key of a table default),
-- changing a slider's min/max/step, adding or removing a setting.
local function serialize(v)
  if type(v) ~= "table" then return type(v) == "string" and string.format("%q", v) or tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. serialize(v[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

local STORED_SETTINGS = [[
minimap.shown | bool | true | nil | nil | nil
settings.alpha | number | 1 | 0 | 1 | 0.05
settings.appearance.font | string | "" | nil | nil | nil
settings.appearance.ignoreFonts | bool | false | nil | nil | nil
settings.appearance.ignorePanel | bool | true | nil | nil | nil
settings.appearance.outline | string | "hud" | nil | nil | nil
settings.appearance.pickerSeen | bool | false | nil | nil | nil
settings.appearance.skin | string | "ka0s" | nil | nil | nil
settings.appearance.source | string | "ka0s" | nil | nil | nil
settings.appearance.texture | string | "" | nil | nil | nil
settings.auction.capture | table | {auctionator:minbuyout=true,oribos:market=true,oribos:region=true,tsm:dbmarket=true,tsm:dbminbuyout=true,tsm:dbregionmarketavg=true,tsm:dbregionminbuyoutavg=true} | nil | nil | nil
settings.auction.enabled | bool | true | nil | nil | nil
settings.enabled | bool | true | nil | nil | nil
settings.excludeQuestItems | bool | true | nil | nil | nil
settings.excludedSources | table | {} | nil | nil | nil
settings.locked | bool | false | nil | nil | nil
settings.qualityThreshold | number | 1 | nil | nil | nil
settings.recordCurrency | bool | true | nil | nil | nil
settings.recordGold | bool | true | nil | nil | nil
settings.retentionDays | number | 30 | nil | nil | nil
settings.rollupRetentionDays | number | 0 | nil | nil | nil
settings.rowHeight | number | 18 | 14 | 28 | 1
settings.scale | number | 1 | 0.5 | 2 | 0.05
settings.showTransfers | bool | true | nil | nil | nil
settings.sim.stepDelay | number | 1 | 0.5 | 10 | 0.5
settings.timelineMaxLines | number | 8 | 2 | 16 | 1
settings.trackLedger | bool | true | nil | nil | nil
settings.visibility | string | "always" | nil | nil | nil
settings.windowScale | number | 1 | 0.6 | 1.6 | 0.05
state.debugConsole | bool | false | nil | nil | nil
state.testMode | bool | false | nil | nil | nil
]]

test("Schema: the stored settings (path, type, default, range) are the pinned set", function()
  local lines = {}
  for _, row in ipairs(NS.Schema.Schema) do
    lines[#lines + 1] = table.concat({ row.path, tostring(row.type), serialize(row.default),
      tostring(row.min), tostring(row.max), tostring(row.step) }, " | ")
  end
  table.sort(lines)
  local got = table.concat(lines, "\n") .. "\n"
  assertEqual(got, STORED_SETTINGS, "a stored setting's path, type, default or range moved")
end)

test("Schema: the Capture tooltips name the controls a player can find (item 020)", function()
  -- LOO-L05/L06/L07: one name per control, the dependency said in words, no stale "next update".
  local function tip(path) return NS.Schema:FindRow(path).tooltip end
  assertTrue(tip("settings.recordGold"):find("Needs Track holdings and losses.", 1, true) ~= nil,
    "Record gold must say what it needs")
  assertTrue(tip("settings.trackLedger"):find("next update", 1, true) == nil,
    "the trackLedger tooltip still promises a shipped update")
  assertTrue(tip("settings.recordCurrency"):find("Obeys Record data from; ignores Minimum quality.", 1, true)
    ~= nil, "Record currency must name the two controls by their labels")
  assertEqual(NS.Schema:FindRow("settings.qualityThreshold").label, "Minimum quality")
  for _, path in ipairs({ "settings.qualityThreshold", "settings.excludeQuestItems",
                          "settings.recordCurrency", "settings.excludedSources" }) do
    assertEqual(NS.Schema:FindRow(path).subgroup, "Loot", path .. " subsection")
  end
  for _, path in ipairs({ "settings.trackLedger", "settings.recordGold" }) do
    assertEqual(NS.Schema:FindRow(path).subgroup, "Ledger", path .. " subsection")
  end
end)

test("Schema: Interface and History read as item 020 laid them out", function()
  -- LOO-L01/L02/L03/L12/L13/L-new1/L-new3: placement, labels and tooltip words only.
  local function row(path) return NS.Schema:FindRow(path) end
  local order = {}
  for _, r in ipairs(NS.Schema.Schema) do
    if r.group == "Interface" then order[#order + 1] = r.path end
  end
  assertEqual(table.concat(order, " "), "settings.windowScale settings.rowHeight "
    .. "settings.timelineMaxLines settings.showTransfers settings.sim.stepDelay",
    "Show transfers by default follows Timeline lines on Interface")
  for _, path in ipairs({ "settings.windowScale", "settings.rowHeight", "settings.timelineMaxLines",
                          "settings.showTransfers" }) do
    assertEqual(row(path).subgroup, "History window", path .. " subsection")
  end
  assertEqual(row("settings.windowScale").tooltip,
    "Scale of the History window. Multiplied by Master scale on General > Master controls.")
  assertEqual(row("settings.sim.stepDelay").label, "Simulation step delay (seconds)")
  assertEqual(row("settings.sim.stepDelay").fmt, "%.1fs", "the readout format stays")
  assertTrue(row("settings.sim.stepDelay").tooltip:find("Paces /lh sim: ", 1, true) == 1,
    "the simulator tooltip opens with the slash verb")
  assertEqual(row("settings.rollupRetentionDays").label, "Keep Timeline history for")
  for _, path in ipairs({ "settings.retentionDays", "settings.rollupRetentionDays" }) do
    assertTrue(row(path).tooltip:find("Account-wide: shared by every profile.", 1, true) == 1,
      path .. ": the tooltip opens with the account-wide sentence")
  end
  local keep = row("settings.retentionDays").tooltip
  assertTrue(keep:find("'Always' keeps everything", 1, true) ~= nil, "the tooltip names the Always option")
  assertTrue(keep:find("'Never'", 1, true) == nil, "the tooltip names an option the dropdown lacks")
end)

test("Schema: Test mode keeps the composed tooltip and appends the host's note (item 020)", function()
  -- LOO-L19 (XC-04, U-01): the composer is the only writer of a Master controls row's words; the
  -- host extends them only through MasterControls' `notes`. The stamp no longer overrides it.
  -- red under: a host `tooltip` stamped onto state.testMode again.
  local tip = NS.Schema:FindRow("state.testMode").tooltip
  assertEqual(tip, "Show placeholder content, so the display can be seen and placed without waiting "
    .. "for the real thing. It fills every tab of the History window: History, Insights, Holdings and "
    .. "Timeline.")
end)
