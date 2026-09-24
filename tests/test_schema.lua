local T = _G.LH_TEST
local NS, test, assertTrue, assertEqual, assertFalse =
  T.NS, T.test, T.assertTrue, T.assertEqual, T.assertFalse

-- The "Debug console" checkbox is a SESSION-ONLY schema row: it renders in the panel like any
-- setting, but its value is backed by the debug console window's visibility (get/set → NS.DebugLog),
-- never written to NS.db.global. These tests pin that mechanism (independent of real frame state by
-- stubbing NS.DebugLog's Show/Hide/IsShown).

local function withDebugLogSpies(fn)
  local D = NS.DebugLog
  local realShow, realHide, realIsShown = D.Show, D.Hide, D.IsShown
  local calls, shown = { show = 0, hide = 0 }, false
  D.Show = function() calls.show = calls.show + 1; shown = true end
  D.Hide = function() calls.hide = calls.hide + 1; shown = false end
  D.IsShown = function() return shown end
  local ok, err = pcall(fn, calls, function() return shown end, function(v) shown = v end)
  D.Show, D.Hide, D.IsShown = realShow, realHide, realIsShown
  if not ok then error(err) end
end

test("Schema: debugConsole row is session-only, on the Master controls tab", function()
  -- MOVED, not copied (options-ui-§15: "Debug console belongs here, as a session-only row, not as
  -- a bespoke checkbox bolted onto some other section"). It sat on Interface until this pass; the
  -- assertion below is what stops a second declaration appearing back there.
  local row = NS.Schema:FindRow("state.debugConsole")
  assertTrue(row ~= nil, "state.debugConsole row missing")
  assertTrue(row.sessionOnly == true, "row not marked sessionOnly")
  assertEqual(row.page, "General")
  assertEqual(row.group, "Master controls")
  assertEqual(row.label, "Debug console")
  -- The path is spelled VERBATIM and unprefixed, which is the one thing the composer had to be
  -- told: session state lives outside the block's own `settings.` prefix, and a row that composed
  -- to `settings.debugConsole` would be a new stored key nothing reads.
  assertEqual(row.path, "state.debugConsole")
  assertTrue(row.solo == nil, "the tab pairs this row with Lock frame; solo would break the line")
end)

-- ── The Master controls tab (options-ui-§15) ──────────────────────────────────

-- The canonical set, in the canonical order, at the canonical paths. Stated here rather than
-- derived from the rows the assertion reads, so a row that vanishes is a NAMED failure.
--
-- This addon is NOT frameless — modules/Browser.lua and modules/Export.lua both call
-- SetMovable(true) — so it is entitled to all eight, and the four frame-only rows must be present.
local MASTER_ROWS = {
  { "settings.enabled",    "Enable Loot History" },
  { "settings.visibility", "General visibility" },
  { "settings.scale",      "Master scale" },
  { "settings.alpha",      "Master alpha" },
  { "settings.locked",     "Lock frame" },
  { "state.debugConsole",  "Debug console" },
  -- The launcher-§3 row, composed from `minimapPath` since LibKa0s v1.39.0. It opens the FOURTH
  -- line and Test mode pairs beside it, which is not a layout preference: EVERY addon has a
  -- minimap button and only SOME have a test mode, so the always-present row takes column 1 and
  -- the optional one pairs to its right (options-ui-§15).
  { "minimap.hide",        "Minimap button" },
  { "state.testMode",      "Test mode" },
}

test("Schema: Master controls is the FIRST group on the General page", function()
  -- red under: declaring any other group ahead of it, which is exactly the shape options-ui-§15
  -- calls anti-pattern #68 ("a General page whose first tab is something else").
  local first
  for _, row in ipairs(NS.Schema.Schema) do
    if row.page == "General" then first = row.group; break end
  end
  assertEqual(first, "Master controls")
  assertEqual(NS.Schema.MASTER_GROUP, "Master controls",
    "the literal the afterGroup hook is keyed under must be the same string")
end)

test("Schema: the Master controls tab holds exactly the canonical rows, in canonical order",
  function()
    -- red under: reordering the block, renaming a row, omitting one this addon is entitled to, or
    -- splicing an addon-specific row into the middle of it.
    local got = {}
    for _, row in ipairs(NS.Schema.Schema) do
      if row.group == "Master controls" then got[#got + 1] = { row.path, row.label } end
    end
    assertEqual(#got, #MASTER_ROWS, "the block is " .. #got .. " rows, not " .. #MASTER_ROWS)
    for i, want in ipairs(MASTER_ROWS) do
      assertEqual(got[i][1], want[1], "row " .. i .. " is at the wrong path")
      assertEqual(got[i][2], want[2], "row " .. i .. " has the wrong label")
    end
  end)

test("Schema: every canonical row is declared ONCE — nothing was copied here, it was moved",
  function()
    -- The hard rule of the whole pass: never two controls over one setting. `settings.enabled`
    -- lived on Capture (then called Collection) and the console on Interface; both MOVED. FindRow answers the first
    -- match, so a duplicate would be invisible to it — count instead.
    for _, want in ipairs(MASTER_ROWS) do
      local n = 0
      for _, row in ipairs(NS.Schema.Schema) do if row.path == want[1] then n = n + 1 end end
      assertEqual(n, 1, want[1] .. " is declared " .. n .. " times")
    end
  end)

test("Schema: the fourth line is [Minimap button] [Test mode], composed and in that order",
  function()
    -- options-ui-§15 + launcher-§3 (standard v2.53.0, LibKa0s compose minor 7). The line below
    -- Lock frame / Debug console holds the two opt-in rows, and WHICH ONE OPENS IT is fixed: the
    -- minimap row is always present and takes column 1, the test mode pairs beside it. Test mode
    -- therefore carries NO `startsLine` at all now -- not `false`, absent, which is the shape every
    -- second-column row has and the shape the flow engine's `opensLine` reads.
    -- red under: either path dropped from the spec, the two swapped, a row hand-written back into
    -- the block, a Test mode that persists or has no default (Reset all settings could not end it),
    -- or the composer's generic tooltip left in place.
    local S = NS.Schema
    local consoleAt, minimapAt, testAt
    for i, row in ipairs(S.Schema) do
      if row.path == "state.debugConsole" then consoleAt = i end
      if row.path == "minimap.hide" then minimapAt = i end
      if row.path == "state.testMode" then testAt = i end
    end
    assertTrue(minimapAt ~= nil, "minimap.hide row missing")
    assertTrue(testAt ~= nil, "state.testMode row missing")
    assertEqual(minimapAt, consoleAt + 1, "Minimap button comes directly after Debug console")
    assertEqual(testAt, minimapAt + 1, "Test mode pairs directly after Minimap button")

    local mm = S.Schema[minimapAt]
    assertEqual(mm.type, "bool")
    assertEqual(mm.label, "Minimap button")
    assertEqual(mm.group, "Master controls")
    assertTrue(mm.startsLine == true, "Minimap button opens the line")
    assertTrue(mm.sessionOnly == nil,
      "STORED, not session-only: a button the player hid stays hidden across a reload")
    assertTrue(mm.default == true,
      "the row's own sense is SHOWN, so its default is true while the stored `hide` is false")

    local row = S.Schema[testAt]
    assertEqual(row.type, "bool")
    assertEqual(row.label, "Test mode")
    assertEqual(row.group, "Master controls")
    assertTrue(row.sessionOnly == true, "row not marked sessionOnly")
    assertTrue(row.startsLine == nil,
      "Test mode pairs beside Minimap button now, so it carries no startsLine key")
    assertTrue(row.default == false, "default = false, so a reset ends it")
    assertEqual(S:Default("state.testMode"), false)
    assertTrue(type(row.get) == "function" and type(row.set) == "function",
      "the host binds get/set, as it does for the console row")
    assertTrue(type(row.tooltip) == "string" and row.tooltip:find("/lh test", 1, true) ~= nil,
      "the tooltip is this addon's own, not the composer's generic one: " .. tostring(row.tooltip))
  end)

test("Schema: Test mode is never written to db.global, and ships no stored default", function()
  local BT = NS.BrowserTable
  NS.db.global.state = nil
  local realSet = BT.SetTestMode
  local asked = {}
  BT.SetTestMode = function(self, on) asked[#asked + 1] = on; self.testMode = on and true or false; return true end
  local ok, err = pcall(function()
    NS.Schema:Set("state.testMode", true)
    assertEqual(NS.Schema:Get("state.testMode"), true)
    NS.Schema:Set("state.testMode", true)   -- already on: nothing to switch
    NS.Schema:Set("state.testMode", false)
    assertEqual(NS.Schema:Get("state.testMode"), false)
  end)
  BT.SetTestMode, BT.testMode = realSet, false
  if not ok then error(err, 0) end
  assertEqual(#asked, 2, "the set switches only when the value differs")
  assertTrue(NS.db.global.state == nil, "session-only row must not persist to db.global")
  assertTrue(NS.defaults.global.state == nil, "nothing in defaults/Global.lua for a session row")
end)

test("Schema: General visibility is a four-value dropdown, not a boolean", function()
  -- options-ui-§15: a boolean can only ever answer two of the four. This addon never shipped a
  -- "show only in combat" checkbox, so there is nothing to migrate — the key is new and an install
  -- from before this release reads back the shipped default through AceDB's own merge, which the
  -- case below pins.
  local row = NS.Schema:FindRow("settings.visibility")
  assertTrue(row ~= nil, "settings.visibility row missing")
  assertEqual(row.type, "string")
  local seen = {}
  for _, key in ipairs(row.sorting) do seen[key] = row.values[key] end
  for _, key in ipairs({ "always", "inCombat", "outOfCombat", "never" }) do
    assertTrue(type(seen[key]) == "string" and seen[key] ~= "",
      "the dropdown does not offer " .. key)
  end
  assertEqual(#row.sorting, 4, "four values, no more")
  assertEqual(row.default, "always")
end)

test("Schema: a profile written before this release gets visibility from the shipped defaults",
  function()
    -- The migration case, in the shape this addon's storage actually takes. `settings.visibility`
    -- is a NEW key rather than a re-typed one, so the "old" state is its ABSENCE — there was never
    -- a `show only in combat` boolean here to rewrite — and what a player who never saw the row
    -- must get is the shipped default that AceDB merges in, not nil.
    -- red under: dropping the key from defaults/Global.lua, or declaring it as anything the
    -- dropdown cannot select. The behavior half (an absent stored value still resolving to a
    -- visible window) is pinned in tests/test_browser.lua.
    assertEqual(NS.defaults.global.settings.visibility, "always")
    local row = NS.Schema:FindRow("settings.visibility")
    assertEqual(row.values[NS.defaults.global.settings.visibility] ~= nil, true,
      "the shipped default must be one of the four the dropdown offers")
  end)

test("Schema: setting debugConsole toggles the window, never writes db.global", function()
  NS.db.global.state = nil
  withDebugLogSpies(function(calls)
    NS.Schema:Set("state.debugConsole", true)
    assertEqual(calls.show, 1, "Set(true) should Show the console window")
    assertEqual(calls.hide, 0)
    NS.Schema:Set("state.debugConsole", false)
    assertEqual(calls.hide, 1, "Set(false) should Hide the console window")
  end)
  assertTrue(NS.db.global.state == nil, "session-only row must not persist to db.global")
end)

test("Schema: getting debugConsole reflects the window visibility", function()
  withDebugLogSpies(function(_, _, setShown)
    setShown(true)
    assertEqual(NS.Schema:Get("state.debugConsole"), true)
    setShown(false)
    assertEqual(NS.Schema:Get("state.debugConsole"), false)
  end)
end)

test("Schema: a normal (persisted) row still writes db.global", function()
  NS.Schema:Set("settings.enabled", false)
  assertEqual(NS.db.global.settings.enabled, false, "normal row must persist to db.global")
  assertEqual(NS.Schema:Get("settings.enabled"), false)
  NS.Schema:Set("settings.enabled", true) -- restore default
end)

test("Schema: auction rows exist with the AH Price group and defaults", function()
  local NS2 = NS
  local row = NS2.Schema:FindRow("settings.auction.enabled")
  assertTrue(row ~= nil, "settings.auction.enabled row missing")
  assertEqual(row.group, "AH Price")
  assertEqual(NS2.Schema:Default("settings.auction.enabled"), true)
end)

test("Schema: auction capture is a MultiCheck row; Rev-1 provider/priority rows are gone", function()
  local NS2 = NS
  local row = NS2.Schema:FindRow("settings.auction.capture")
  assertTrue(row ~= nil, "settings.auction.capture row missing")
  assertEqual(row.group, "AH Price")
  assertEqual(row.widget, "MultiCheck")
  assertEqual(NS2.Schema:Default("settings.auction.capture")["tsm:dbmarket"], true)

  assertTrue(NS2.Schema:FindRow("settings.auction.tsmSource") == nil, "tsmSource row should be removed")
  assertTrue(NS2.Schema:FindRow("settings.auction.auctionator") == nil, "auctionator row should be removed")
  assertTrue(NS2.Schema:FindRow("settings.auction.priorityAuctionator") == nil, "priorityAuctionator row should be removed")
  assertTrue(NS2.Schema:FindRow("settings.auction.tsm") == nil, "tsm row should be removed")
  assertTrue(NS2.Schema:FindRow("settings.auction.priorityTSM") == nil, "priorityTSM row should be removed")
  assertTrue(NS2.Schema:FindRow("settings.auction.oribos") == nil, "oribos row should be removed")
  assertTrue(NS2.Schema:FindRow("settings.auction.priorityOribos") == nil, "priorityOribos row should be removed")
end)

test("Schema: recordCurrency row exists, defaults true, settable", function()
  assertEqual(NS.Schema:Default("settings.recordCurrency"), true)
  assertEqual(NS.defaults.global.settings.recordCurrency, true)
  assertTrue(NS.Schema:Set("settings.recordCurrency", false))
  assertEqual(NS.Schema:Get("settings.recordCurrency"), false)
  NS.Schema:Set("settings.recordCurrency", true)   -- restore default
end)

test("Constants: CURRENCY_TYPE is \"Currency\"", function()
  assertEqual(NS.Constants.CURRENCY_TYPE, "Currency")
end)

-- ── Schema shape: the invariants the panel, the CLI and AceDB all rely on ──────

local S = NS.Schema

test("Schema: every row is uniquely pathed and fully described", function()
  local seen = {}
  for _, row in ipairs(S.Schema) do
    assertTrue(type(row.path) == "string" and row.path ~= "", "a row has no path")
    assertFalse(seen[row.path], row.path .. " is defined twice")
    seen[row.path] = true
    assertTrue(type(row.label) == "string" and row.label ~= "", row.path .. " has no label")
    assertTrue(type(row.page) == "string" and row.page ~= "", row.path .. " has no panel page")
    assertTrue(type(row.group) == "string" and row.group ~= "", row.path .. " has no panel group")
    assertTrue(type(row.widget) == "string" and row.widget ~= "", row.path .. " has no widget")
  end
end)

test("Schema: every row's default matches its declared type", function()
  -- The declared type is LibKa0s's vocabulary rather than Lua's: both majors dispatch on "bool",
  -- and "table" is this addon's own set-valued type that neither of them knows (it is rendered
  -- through the Slash descriptor's `format` hook and drawn by a host-owned MultiCheck).
  local LUA_TYPE = { bool = "boolean", number = "number", table = "table", string = "string" }
  for _, row in ipairs(S.Schema) do
    local want = LUA_TYPE[row.type]
    assertTrue(want ~= nil,
      row.path .. " declares a type no LibKa0s major reads: " .. tostring(row.type))
    assertEqual(type(row.default), want, row.path .. "'s default is the wrong type")
  end
end)

test("Schema: FindRow resolves a known path and rejects an unknown one", function()
  assertEqual(S:FindRow("settings.enabled").path, "settings.enabled")
  assertEqual(S:FindRow("settings.nosuchthing"), nil)
  assertEqual(S:FindRow(nil), nil)
end)

test("Schema: every persisted path resolves against the shipped defaults", function()
  -- This is Register's boot check, asserted rather than merely printed.
  for _, row in ipairs(S.Schema) do
    if not row.sessionOnly then
      assertTrue(S:ReadPath(NS.defaults.global, row.path) ~= nil,
        row.path .. " has no entry in defaults/Global.lua")
    end
  end
end)

test("Schema: Register reports a typo'd path even when the row declares a default", function()
  -- LH-R-02 / LH-A-43. Register's condition used to end `and row.default == nil`, and no shipped
  -- row satisfies that — all eleven declare a non-nil default (two declare `false`) — so the whole
  -- boot check was structurally dead and a typo'd path was reported by nothing. The probe below
  -- carries a default ON PURPOSE: that is precisely the case the old conjunct could not see.
  -- Restoring `and row.default == nil` turns this red.
  assertEqual(S:Register(), 0, "the shipped schema must validate clean")
  S.Schema[#S.Schema + 1] = { path = "settings.nosuchbranch.typo", default = true, type = "bool" }
  local unresolved = S:Register()
  S.Schema[#S.Schema] = nil   -- pulled before asserting, so a failure cannot poison later suites
  assertTrue(unresolved > 0, "a typo'd path must be reported even though the row has a default")
  assertEqual(S:Register(), 0, "the probe row must be gone again")
end)

-- Structural equality. `assertEqual` compares a table by identity, which is why the case below
-- used to skip every `type = "table"` row: the set-valued defaults are two separate literals and an
-- identity check could only ever fail. Skipping them is what let the AH lists drift apart
-- unobserved (LH-R-01), so the rows are compared by shape instead of excluded.
local function deepEqual(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

test("Schema: the shipped default equals the schema's declared default", function()
  -- Two sources of the same truth; a drift would make a reset change the value silently. Table
  -- rows are included and compared by shape — see deepEqual above.
  --
  -- `minimap.hide` is compared INVERTED rather than skipped, which is the whole point of naming it:
  -- the row's default is its own sense (SHOWN = true) and defaults/Global.lua ships LibDBIcon's key
  -- (hide = false). They are one fact in two senses, so the pair is still checked -- flip either
  -- side alone and this goes red exactly as it would for any other row (launcher-§3).
  for _, row in ipairs(S.Schema) do
    if row.path == "minimap.hide" then
      assertEqual(S:ReadPath(NS.defaults.global, row.path), not row.default,
        "minimap.hide: the shipped `hide` must be the inverse of the row's SHOWN default")
    elseif not row.sessionOnly then
      local shipped = S:ReadPath(NS.defaults.global, row.path)
      if row.type == "table" then
        assertTrue(deepEqual(shipped, row.default),
          row.path .. " disagrees with defaults/Global.lua")
      else
        assertEqual(shipped, row.default, row.path .. " disagrees with defaults/Global.lua")
      end
    end
  end
end)

test("Schema: the AH priority cascade is declared once, in core/Constants.lua", function()
  -- LH-R-01. `settings.auction.priority` is a carve-out array with no schema row, so the case
  -- above cannot reach it — and defaults/Global.lua used to restate it as a second literal that
  -- had drifted to 7 of the 11 tags. It is now filled from AUCTION_PRIORITY_DEFAULT, which is the
  -- only place the cascade is written down. Re-splitting the two turns this red.
  local declared = NS.Constants.AUCTION_PRIORITY_DEFAULT
  local shipped  = NS.defaults.global.settings.auction.priority
  assertTrue(shipped ~= declared,
    "the shipped default must be a copy — an alias lets a reorder rewrite the constant")
  assertEqual(#shipped, #declared,
    "defaults/Global.lua ships " .. #shipped .. " cascade entries, Constants declares " .. #declared)
  for i, tag in ipairs(declared) do
    assertEqual(shipped[i], tag, "cascade entry " .. i .. " disagrees with defaults/Global.lua")
  end
end)

-- Both enum shapes the flow engine's own `enumList` reads, normalized to one list of values. This
-- addon shipped only the ARRAY form ({ { value =, text = }, ... }) until the composed `visibility`
-- row arrived carrying the KEY-MAP form ({ [value] = label } plus an explicit `sorting`), and a
-- check written against one shape silently skips every row in the other — which is the same
-- vacuous-pass this file exists to avoid.
local function enumValues(row)
  local v = row.values
  if type(v) ~= "table" then return {} end
  if type(v[1]) == "table" and v[1].value ~= nil then
    local out = {}
    for i, item in ipairs(v) do out[i] = item.value end
    return out
  end
  local out = {}
  for _, key in ipairs(row.sorting or {}) do out[#out + 1] = key end
  if #out == 0 then for key in pairs(v) do out[#out + 1] = key end end
  return out
end

test("Schema: every dropdown row offers values, and its default is one of them", function()
  for _, row in ipairs(S.Schema) do
    if row.widget == "Dropdown" then
      local values = enumValues(row)
      assertTrue(#values > 0, row.path .. " has no values")
      local found = false
      for _, value in ipairs(values) do if value == row.default then found = true end end
      assertTrue(found, row.path .. "'s default is not a selectable option")
    end
  end
end)

test("Schema: a key-map enum declares an explicit sorting, so its order is not pairs() order",
  function()
    -- red under: dropping `sorting` from the composed visibility row. `pairs()` over a hash is
    -- unordered, so the four modes would come out in a different order on a different run — which
    -- is a dropdown whose entries move between sessions.
    for _, row in ipairs(S.Schema) do
      if row.widget == "Dropdown" and type(row.values) == "table" and row.values[1] == nil then
        assertTrue(type(row.sorting) == "table" and #row.sorting > 0,
          row.path .. " is a key-map enum with no sorting")
        for _, key in ipairs(row.sorting) do
          assertTrue(row.values[key] ~= nil, row.path .. ": sorting names " .. key .. ", values does not")
        end
        local n = 0
        for _ in pairs(row.values) do n = n + 1 end
        assertEqual(n, #row.sorting, row.path .. ": sorting and values disagree about how many")
      end
    end
  end)

test("Schema: every MultiCheck row offers values", function()
  for _, row in ipairs(S.Schema) do
    if row.widget == "MultiCheck" then
      assertEqual(row.type, "table", row.path .. " must store a set")
      assertTrue(#row.values > 0, row.path .. " has no values")
    end
  end
end)

test("Schema: the slider default sits inside its own bounds", function()
  for _, row in ipairs(S.Schema) do
    if row.widget == "Slider" then
      assertTrue(type(row.min) == "number" and type(row.max) == "number", row.path .. " has no range")
      assertTrue(row.min < row.max, row.path .. "'s range is inverted")
      assertTrue(row.default >= row.min and row.default <= row.max,
        row.path .. "'s default is outside its slider")
    end
  end
end)

--- The ONE stored row entitled to its own accessors, and why. `minimap.hide` is the launcher-§3
--- row: the checkbox says SHOWN and LibDBIcon's key says HIDDEN, so the value the row carries is
--- the inverse of the value the store carries and a straight WritePath of the row's value would
--- store the opposite of what was ticked. The inversion is the accessors, and there is deliberately
--- no second key beside `hide` for the row to address instead (anti-pattern #81).
---
--- Named rather than dropped from the check: the rule this case enforces -- a stored row does not
--- get to route around the write seam -- is still the rule, and the next row that wants an exemption
--- has to be argued for here.
local STORED_ROWS_WITH_ACCESSORS = { ["minimap.hide"] = true }

test("Schema: only the session-only rows carry their own get/set", function()
  for _, row in ipairs(S.Schema) do
    if row.get or row.set then
      assertTrue(row.sessionOnly or STORED_ROWS_WITH_ACCESSORS[row.path],
        row.path .. " overrides get/set but is persisted")
    end
  end
end)

test("Schema: the Minimap button row's accessors invert onto LibDBIcon's own `hide` key", function()
  -- launcher-§3. The row's boolean is SHOWN; the stored key is HIDDEN; there is ONE boolean and no
  -- `minimap.show` beside it. Driven through Schema:Set/Get, which is the single write seam the
  -- panel checkbox, `/lh set`, `/lh reset` and `/lh resetall` all take.
  -- red under: dropping the inversion, storing the row's own sense, or a second key appearing.
  local before = NS.db.global.minimap.hide

  assertTrue(S:Set("minimap.hide", false))
  assertEqual(NS.db.global.minimap.hide, true, "unticked means HIDDEN in the store")
  assertEqual(S:Get("minimap.hide"), false, "and the row reads back what was ticked")

  assertTrue(S:Set("minimap.hide", true))
  assertEqual(NS.db.global.minimap.hide, false, "ticked means NOT hidden")
  assertEqual(S:Get("minimap.hide"), true)

  assertTrue(NS.db.global.minimap.show == nil,
    "no second key beside `hide`: one state, and LibDBIcon writes it too")

  -- The declared default is the row's sense, SHOWN, and a reset restores the button.
  assertEqual(S:Default("minimap.hide"), true)
  S:Set("minimap.hide", S:Default("minimap.hide"))
  assertEqual(NS.db.global.minimap.hide, false)

  NS.db.global.minimap.hide = before
end)

-- ── Path plumbing ──────────────────────────────────────────────────────────────

test("Schema.ReadPath walks a nested path and stops safely at a missing branch", function()
  local root = { settings = { auction = { enabled = true } } }
  assertEqual(S:ReadPath(root, "settings.auction.enabled"), true)
  assertEqual(S:ReadPath(root, "settings.nope.enabled"), nil)
  assertEqual(S:ReadPath(root, "settings.auction.enabled.deeper"), nil,
    "walking through a non-table returns nil rather than erroring")
end)

test("Schema.WritePath creates the intermediate tables it needs", function()
  local root = {}
  S:WritePath(root, "a.b.c", 42)
  assertEqual(root.a.b.c, 42)
end)

test("Schema.WritePath replaces a non-table sitting in the way", function()
  local root = { a = "scalar" }
  S:WritePath(root, "a.b", 1)
  assertEqual(root.a.b, 1)
end)

-- ── Get / Set / Default ────────────────────────────────────────────────────────

test("Schema.Set refuses an unknown path and reports why", function()
  local ok, err = S:Set("settings.nosuchthing", true)
  assertFalse(ok)
  assertTrue(err:find("unknown path", 1, true) ~= nil)
end)

test("Schema.Set stores a deep copy, never a reference to the caller's table", function()
  local live = { KILL = true }
  S:Set("settings.excludedSources", live)
  live.AH = true   -- a later mutation of the caller's table must not reach the DB
  assertEqual(NS.db.global.settings.excludedSources.AH, nil)
  assertEqual(NS.db.global.settings.excludedSources.KILL, true)
  S:Set("settings.excludedSources", {})
end)

test("Schema.Default hands out a copy of a table default, not the shared one", function()
  local a, b = S:Default("settings.excludedSources"), S:Default("settings.excludedSources")
  assertTrue(a ~= b, "two resets must not share one table")
  a.KILL = true
  assertEqual(S:Default("settings.excludedSources").KILL, nil, "the schema default is unpoisoned")
end)

test("Schema.Default returns nil for an unknown path", function()
  assertEqual(S:Default("settings.nosuchthing"), nil)
end)

test("Schema.Set runs the row's onChange with the new value", function()
  local row = S:FindRow("settings.windowScale")
  local saved, got = row.onChange, nil
  row.onChange = function(v) got = v end
  S:Set("settings.windowScale", 1.25)
  row.onChange = saved
  assertEqual(got, 1.25)
  S:Set("settings.windowScale", S:Default("settings.windowScale"))
end)

test("Schema.Set honors a row's validate guard and leaves the DB untouched", function()
  local row = S:FindRow("settings.windowScale")
  local before = S:Get("settings.windowScale")
  row.validate = function(v) return v ~= 99 end
  local ok, err = S:Set("settings.windowScale", 99)
  row.validate = nil
  assertFalse(ok)
  assertEqual(err, "invalid value")
  assertEqual(S:Get("settings.windowScale"), before, "a rejected value is not written")
end)

test("Schema.Get on an unknown path reads through rather than erroring", function()
  assertEqual(S:Get("settings.nosuchthing"), nil)
end)

test("Schema: every setting round-trips through Set then Get", function()
  for _, row in ipairs(S.Schema) do
    if not row.sessionOnly then
      local before = S:Get(row.path)
      if row.type == "bool" then
        S:Set(row.path, not before)
        assertEqual(S:Get(row.path), not before, row.path .. " did not round-trip")
      elseif row.type == "number" then
        local probe = row.values and row.values[#row.values].value
          or (row.min and (row.min + row.max) / 2) or 7
        S:Set(row.path, probe)
        assertEqual(S:Get(row.path), probe, row.path .. " did not round-trip")
      end
      S:Set(row.path, before)
      if row.type ~= "table" then   -- table values are stored as deep copies, so compare by value
        assertEqual(S:Get(row.path), before, row.path .. " did not restore")
      end
    end
  end
end)

-- ── Slash command table ────────────────────────────────────────────────────────

test("Schema: every declared command is uniquely named and dispatchable", function()
  local seen = {}
  for _, cmd in ipairs(NS.COMMANDS) do
    -- Positional { name, description, handler } triples: the shape LibKa0s-Slash-1.0 reads. The
    -- table stays the host's and is passed in, so the options major can render the same rows
    -- without either library resolving the other.
    local name, desc, fn = cmd[1], cmd[2], cmd[3]
    assertTrue(type(name) == "string" and name ~= "", "a command has no name")
    assertFalse(seen[name], name .. " is declared twice")
    seen[name] = true
    assertTrue(type(desc) == "string" and desc ~= "", name .. " has no help text")
    assertEqual(type(fn), "function", name .. " has no handler")
  end
end)

test("Schema: the reserved verbs are all present", function()
  -- slash-commands-§2's reserved set, minus `perf` (this addon declines LibKa0s-Perf) -- reserved
  -- always, registered when wired, so its absence here is a decline rather than a gap.
  -- red under: dropping `enable` or `disable`, which would leave the Master controls Enable row
  -- with no CLI spelling and the collection with one addon whose reserved set is short.
  local byName = {}
  for _, cmd in ipairs(NS.COMMANDS) do byName[cmd[1]] = true end
  for _, verb in ipairs({ "get", "set", "list", "reset", "resetall", "help", "config", "version",
                          "debug", "enable", "disable" }) do
    assertTrue(byName[verb], "/lh " .. verb .. " is missing")
  end
end)


-- ── The page / tab partition (options-ui-§13) ──────────────────────────────────
--
-- Every page's tabs, in the order O.RenderTabbedSchema draws them, and how many CONTROLS each
-- holds. Stated here rather than derived from the schema the assertion reads, so a row that
-- drifts into another tab is a NAMED failure rather than a shorter list that still agrees with
-- itself.
--
-- Counts are ROWS, which on this addon's two schema pages is not the same as widgets:
-- `settings.excludedSources` is a `type = "table"` row the generic renderer cannot draw (the
-- host draws it from afterGroup), and `settings.auction.capture` carries `skipRender`. Both are
-- still rows, still writable from `/lh set`, and still counted here — the panel-side truth is
-- tests/test_panel.lua's business.
local PARTITION = {
  ["General"] = {
    { "Master controls", 8 }, { "Capture", 4 }, { "AH Price", 2 },
    { "Interface", 2 }, { "History", 1 },
  },
}

test("Schema: every page's tabs are the designed ones, in order, at the designed size", function()
  -- red under: moving a row to another tab, reordering a group, splitting a group's rows so they
  -- are no longer contiguous (which prints the same tab twice), or adding a row to a page with
  -- nothing here to say so.
  local pages, seenPage = {}, {}
  for _, row in ipairs(S.Schema) do
    if not seenPage[row.page] then seenPage[row.page] = true; pages[#pages + 1] = row.page end
  end
  assertEqual(#pages, 1,
    "ONE schema-backed page: R6 deprecated the Filters and AH Price sub-pages into General")

  for _, page in ipairs(pages) do
    assertTrue(PARTITION[page] ~= nil, page .. " is a page the partition table does not describe")
    local order, counts, seen = {}, {}, {}
    for _, row in ipairs(S.Schema) do
      if row.page == page then
        if not seen[row.group] then
          -- A group that opens twice means its rows are not contiguous, which draws its heading
          -- (or its tab) a second time. Caught here rather than by the count, which would still
          -- add up.
          seen[row.group] = true
          order[#order + 1] = row.group
        end
        counts[row.group] = (counts[row.group] or 0) + 1
      end
    end

    local want = {}
    for i, pair in ipairs(PARTITION[page]) do want[i] = pair[1] end
    assertEqual(table.concat(order, " | "), table.concat(want, " | "), page .. ": tab order")
    for _, pair in ipairs(PARTITION[page]) do
      assertEqual(counts[pair[1]], pair[2], page .. " / " .. pair[1] .. ": control count")
    end
  end
end)

test("Schema: a group's rows are contiguous, so no tab is drawn twice", function()
  -- The half the partition table cannot state: RenderTabbedSchema walks the rows IN ORDER and
  -- opens a tab the first time it sees a group. A row filed under a group the page has already
  -- left gets its own second tab with the same name.
  local closed, current = {}, nil
  for _, row in ipairs(S.Schema) do
    local key = row.page .. "\1" .. row.group
    if key ~= current then
      assertFalse(closed[key], row.path .. " reopens " .. row.page .. " / " .. row.group ..
        " after the page has left it")
      closed[key] = true
      current = key
    end
  end
end)

test("Schema: no tab holds fewer than two controls", function()
  -- A tab over one control is a click that reveals a single dropdown. General's History is
  -- the one exemption and it is exempted BY NAME, never by loosening the rule: its single stored
  -- row (Keep history for) shares the tab with three BESPOKE controls that have no path and
  -- cannot be rows — the live storage readout, "Purge history…" and "Reset Everything"
  -- (settings/Panel.lua renderHistory).
  -- red under: a tab losing rows until one is left, or a new one-row group.
  local EXEMPT = { ["History"] = true }
  local counts, pageOf = {}, {}
  for _, row in ipairs(S.Schema) do
    counts[row.group] = (counts[row.group] or 0) + 1
    pageOf[row.group] = row.page
  end
  for group, n in pairs(counts) do
    if not EXEMPT[group] then
      assertTrue(n >= 2, pageOf[group] .. " / " .. group .. " holds only " .. n)
    end
  end
end)

test("Schema: a tab name never repeats the page it sits on", function()
  -- On a page called Bars, "Bar background" carries nothing the strip has not already said. There
  -- is no exemption left: "AH Price" used to be a page whose one group had the same name, and the
  -- merge into General removed the collision rather than excusing it.
  for _, row in ipairs(S.Schema) do
    assertFalse(row.group:lower():find(row.page:lower(), 1, true) ~= nil,
      row.page .. " / " .. row.group .. ": the tab repeats its page")
  end
end)

test("Schema: every row carries a group, so no page can render strip-less", function()
  -- options-ui-§13 / anti-pattern #69: a page whose rows declare no group cannot draw a strip, and
  -- the engine reports it and renders the page untabbed. Three lines, and it is the check that
  -- catches a row added without one.
  -- red under: dropping `group` from any row.
  for _, row in ipairs(S.Schema) do
    assertTrue(type(row.group) == "string" and row.group ~= "",
      row.path .. " carries no group, so its page would render untabbed")
  end
end)

test("Schema: no color row exists, so the class-color companion rule has nothing to bind to",
  function()
    -- options-ui-§17 in the shape it takes here: this addon paints no user-chosen color at all —
    -- the item-quality and status hues are the client's and the addon's own palettes, neither of
    -- which is a picker. The loop is written anyway, so that the DAY a swatch is added it must
    -- arrive with its companion beside it and without `disabledIf`, rather than this rule being
    -- rediscovered.
    -- red under: adding a `type = "color"` row without a `useClassColor*` bool immediately after
    -- it, or putting `disabledIf` on one.
    local colors = 0
    for i, row in ipairs(S.Schema) do
      assertTrue(row.disabledIf == nil or row.type ~= "color",
        row.path .. ": a color row must never be disabled (anti-pattern #74)")
      if row.type == "color" then
        colors = colors + 1
        local nxt = S.Schema[i + 1]
        assertTrue(nxt ~= nil and nxt.type == "bool" and nxt.label == "Use class color",
          row.path .. " has no class-color companion immediately after it")
        assertTrue(row.startsLine == true,
          row.path .. " must start its line, or the pair can be split across two")
        assertTrue(nxt.classColorSource == row.classColorSource
          and (row.classColorSource == "player" or row.classColorSource == "unit"),
          row.path .. ": both halves must declare the same classColorSource")
      end
    end
    assertEqual(colors, 0, "this addon ships no color rows; if that changed, say so here")
  end)

test("Schema: every slider declares a step it can actually be dragged to", function()
  -- SetSliderValues(min, max, row.step or 1): a slider row with no `step` declares a step of ONE.
  -- Window scale shipped that way on a 0.6..1.6 range — a control a player could only drag to its
  -- two ends. The commit path snaps against `row.step or 0` instead, so nothing stored was ever
  -- wrong; only the widget was unusable, which is exactly the class of bug no assertion saw.
  for _, row in ipairs(S.Schema) do
    if row.widget == "Slider" then
      assertTrue(type(row.step) == "number" and row.step > 0,
        row.path .. " is a slider with no step")
      assertTrue((row.max - row.min) / row.step >= 4,
        row.path .. "'s step gives it fewer than five positions")
    end
  end
end)

-- ── the docs' row counts are the schema's row count ──────────────────────────────────────────

-- Every place a Tier-1/Tier-2 doc states how many rows ship, as { file, pattern, spelled }. The
-- pattern captures the number; `spelled` says whether it is a word or a numeral.
--
-- This is a COUNT-CLAIM gate, and it exists because the claim drifted: master said "Twelve rows
-- ship today" with twelve rows, this pass moved the schema to sixteen and wrote seventeen into four
-- documents — each of them directly above a table that listed sixteen. A number in prose has
-- nothing to disagree with until something compares it, so this is that something.
local NUMBER_WORD = {
  ten = 10, eleven = 11, twelve = 12, thirteen = 13, fourteen = 14, fifteen = 15,
  sixteen = 16, seventeen = 17, eighteen = 18, nineteen = 19, twenty = 20,
}

local COUNT_CLAIMS = {
  { "docs/ARCHITECTURE.md",   "\n(%a+) rows ship today, on %*%*one%*%* schema%-backed page" },
  { "docs/settings-panel.md", "%*%*(%a+) rows ship today%*%*" },
  { "docs/module-map.md",     "Schema%.lua%s+— (%d+) rows, one per setting" },
  { "docs/module-map.md",     "`NS%.Schema` %(alias `S`%): %*%*(%a+)%*%* rows, one per setting" },
}

test("Schema: every doc that counts the rows counts the same number the schema ships", function()
  -- red under: adding or removing a schema row without touching the docs, and equally under
  -- rewriting one of these four numbers to something the schema does not ship.
  local want = #S.Schema
  assertTrue(want > 0, "the schema is empty")
  for _, claim in ipairs(COUNT_CLAIMS) do
    local path, pattern = claim[1], claim[2]
    local src = T.Loader.readFile(path)
    local found = src:match(pattern)
    assertTrue(found ~= nil, path .. ": no row-count claim matched " .. pattern)
    local n = tonumber(found) or NUMBER_WORD[found:lower()]
    assertTrue(n ~= nil, path .. ": '" .. found .. "' is not a number this gate can read")
    assertEqual(n, want, path .. " claims " .. found .. " rows; the schema ships " .. want)
  end
end)

test("Schema: the docs' per-tab breakdown is the schema's own partition", function()
  -- The other half of the same drift: a total can be corrected while the breakdown beside it stays
  -- wrong, and a breakdown is what a reader actually navigates by.
  -- red under: moving a row between tabs, or editing the module-map sentence away from the schema.
  local live, order = {}, {}
  for _, row in ipairs(S.Schema) do
    if not live[row.group] then live[row.group] = 0; order[#order + 1] = row.group end
    live[row.group] = live[row.group] + 1
  end
  local src = T.Loader.readFile("docs/module-map.md")
  -- A breakdown is one run of "<Tab> <n>" pairs; each is pulled out whole first, so a number that
  -- happens to follow a tab's name elsewhere in the file cannot answer for it. The file states the
  -- breakdown TWICE — once in the source tree, once in the per-file entry — and EVERY occurrence is
  -- checked, because one of two homes going stale while the other is corrected is precisely the
  -- drift this exists to catch.
  local found = 0
  for segment in src:gmatch("Master controls %d+.-History %d+") do
    found = found + 1
    for _, group in ipairs(order) do
      local n = tonumber(segment:match(group:gsub("%p", "%%%0") .. " (%d+)"))
      assertEqual(n, live[group], "docs/module-map.md breakdown " .. found ..
        " disagrees with the schema on " .. group)
    end
    -- Filters is a real tab with no rows, so it must NOT appear in a breakdown of row counts.
    assertTrue(segment:match("Filters") == nil,
      "breakdown " .. found .. " counts ROWS, and the Filters tab has none")
  end
  assertTrue(found >= 2, "docs/module-map.md must still state the per-tab breakdown in both its "
    .. "source tree and its per-file entry (found " .. found .. ")")
end)

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
  ns.db = { global = NS.Util.DeepCopy(ns.defaults.global) }
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
    assertEqual(ns.db.global.settings.excludedSources.KILL, true, "the write landed")
    assertEqual(ns.db.global.settings.excludedSources.AH, nil, "as a copy")
    assertTrue(got == live, "onChange got the value as given")
    local ok, err = ns.Schema:Set("settings.nosuchthing", 1)
    assertEqual(ok, false)
    assertEqual(err, "unknown path: settings.nosuchthing")
    assertEqual(ns.db.global.settings.nosuchthing, nil, "and nothing was stored")
  end)

test("seam: on the degraded build the runtime readers read the store", function()
  local ns = degradedWithStore()
  assertEqual(ns.Schema:Get("settings.rowHeight"), ns.defaults.global.settings.rowHeight)
  assertFalse(ns.AddonIsOff(), "enabled by default")
  ns.db.global.settings.enabled = false
  assertTrue(ns.AddonIsOff(), "core/LifecycleSetup.lua reads the switch through the seam")
end)

test("seam: on the degraded build the composed Master controls rows are absent, and refused", function()
  -- The degraded Options stub's MasterControls composes no rows, so the minimap, enable and session
  -- rows do not exist here. A write to one is refused like any unknown path and stores nothing.
  local ns = degradedWithStore()
  assertEqual(ns.Schema:FindRow("minimap.hide"), nil)
  assertEqual(ns.Schema:Set("minimap.hide", false), false)
  assertEqual(ns.db.global.minimap.hide, false, "the store is untouched")
end)

test("seam: on the degraded build ApplyDefault restores, and spares an exempt row only in a sweep",
  function()
    -- The exemption is exercised on a row the degraded build HAS, by naming it in the same
    -- RESET_EXEMPT table the seam reads, and restored before asserting.
    local ns = degradedWithStore()
    local S2, g = ns.Schema, ns.db.global
    local q, c = S2:FindRow("settings.qualityThreshold"), S2:FindRow("settings.recordCurrency")
    g.settings.qualityThreshold, g.settings.recordCurrency = 4, false
    S2.RESET_EXEMPT[c.path] = true
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
    assertEqual(g.settings.qualityThreshold, ns.defaults.global.settings.qualityThreshold)
    assertEqual(sweptC, false, "a sweep never resets an exempt row (launcher-3)")
    assertEqual(g.settings.recordCurrency, true, "a named reset still does")
  end)

test("seam: on the degraded build Reset all settings keeps the hidden minimap button", function()
  local ns = degradedWithStore()
  local g = ns.db.global
  g.settings.qualityThreshold = 4
  g.minimap.hide = true
  ns.Slash:ResetEverything()
  assertEqual(ns.db.global.settings.qualityThreshold, ns.defaults.global.settings.qualityThreshold)
  assertEqual(ns.db.global.minimap.hide, true, "carried across the wipe through ReadPath/WritePath")
end)

test("seam: on the degraded build the boot check passes", function()
  local ns = degradedWithStore()
  assertEqual(ns.Schema:Register(), 0)
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
  assertTrue(S.SameValue == lib.SameValue, "and so is the stored-value equality")
  assertTrue(R.AllRows() == S.Schema, "the rows are held by reference, never copied")
end)

test("seam: a write with no store yet is refused, not raised", function()
  -- Before InitDB there is no db.global. The old seam indexed nil and raised; the runtime's root
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
  assertEqual(NS.db.global.settings.recordCurrency, true, "nothing reached the real store")
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
    "schema path does not resolve against defaults/Global.lua: settings.nosuchbranch.typo")
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
  local savedHistory, savedDays, savedShow = g.history, g.settings.retentionDays, M.StaticPopup_Show
  local now, day = os.time(), 86400
  g.history = {
    { ts = now - 40 * day, itemID = 1 }, { ts = now - 20 * day, itemID = 2 },
    { ts = now - 10 * day, itemID = 3 }, { ts = now - 2 * day, itemID = 4 },
    { ts = now - 3600, itemID = 5 },
  }
  g.settings.retentionDays = 30
  S:SyncRetention()
  local shown = {}
  M.StaticPopup_Show = function(which, a1, a2, data)
    shown[#shown + 1] = { which = which, a1 = a1, a2 = a2, data = data }
  end
  M.__resetPrinted()
  local ok, err = pcall(fn, shown)
  g.history, g.settings.retentionDays, M.StaticPopup_Show = savedHistory, savedDays, savedShow
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
    assertEqual(NS.db.global.settings.retentionDays, 7)
  end)
end)

test("Retention: declining restores the confirmed value, keeps every record, prints one line", function()
  withRetentionFixture(function(shown)
    S:Set("settings.retentionDays", 7)
    T.mocks.__resetPrinted()
    T.mocks.StaticPopupDialogs.KA0S_LOOTHISTORY_PRUNE.OnCancel(nil, { days = 7 })
    assertEqual(NS.db.global.settings.retentionDays, 30, "the previous retention was not restored")
    assertEqual(#NS.db.global.history, 5, "declining deleted records")
    assertEqual(#shown, 1, "writing the old value back must not raise a second confirm")
    local printed = T.mocks.__printed()
    assertEqual(#printed, 1, "decline prints exactly one line: " .. table.concat(printed, " | "))
    assertTrue(printed[1]:find("retention kept at 30 days; no records were deleted.", 1, true) ~= nil,
      "unexpected decline line: " .. printed[1])
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
