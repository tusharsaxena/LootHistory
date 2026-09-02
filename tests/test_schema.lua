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
    -- lived on Collection and the console on Interface; both MOVED. FindRow answers the first
    -- match, so a duplicate would be invisible to it — count instead.
    for _, want in ipairs(MASTER_ROWS) do
      local n = 0
      for _, row in ipairs(NS.Schema.Schema) do if row.path == want[1] then n = n + 1 end end
      assertEqual(n, 1, want[1] .. " is declared " .. n .. " times")
    end
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
    -- dropdown cannot select. The behaviour half (an absent stored value still resolving to a
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
  for _, row in ipairs(S.Schema) do
    if not row.sessionOnly then
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

-- Both enum shapes the flow engine's own `enumList` reads, normalised to one list of values. This
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

test("Schema: only the session-only rows carry their own get/set", function()
  for _, row in ipairs(S.Schema) do
    if row.get or row.set then
      assertTrue(row.sessionOnly, row.path .. " overrides get/set but is persisted")
    end
  end
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

test("Schema: the settings CLI verbs are all present", function()
  local byName = {}
  for _, cmd in ipairs(NS.COMMANDS) do byName[cmd[1]] = true end
  for _, verb in ipairs({ "get", "set", "list", "reset", "resetall", "help" }) do
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
    { "Master controls", 6 }, { "Collection", 4 }, { "AH Price", 2 },
    { "Interface", 3 }, { "Maintenance", 1 },
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
  -- A tab over one control is a click that reveals a single dropdown. General's Maintenance is
  -- the one exemption and it is exempted BY NAME, never by loosening the rule: its single stored
  -- row (Keep history for) shares the tab with three BESPOKE controls that have no path and
  -- cannot be rows — the live storage readout, "Purge history…" and "Reset Everything"
  -- (settings/Panel.lua renderHistory).
  -- red under: a tab losing rows until one is left, or a new one-row group.
  local EXEMPT = { ["Maintenance"] = true }
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
  for segment in src:gmatch("Master controls %d+.-Maintenance %d+") do
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
