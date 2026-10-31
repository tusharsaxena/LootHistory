-- tests/test_slash_verbs.lua — the verbs' own paths: bare `/lh`, the two reserved verbs, a disabled
-- addon's refusal, `/lh debug events` and the printer's Format. Moved out of tests/test_slash.lua,
-- whose capture helper is copied below, because settings/Slash.lua binds NS.Print at its load.
local T = _G.LH_TEST
local NS, test, assertTrue, assertEqual = T.NS, T.test, T.assertTrue, T.assertEqual

local Sl = NS.Slash

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

-- ── bare `/lh` opens the settings panel (slash-commands-§3, Slash minor 11) ──────────────────
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

    local before = NS.db.profile.settings.enabled
    -- Every write is recorded, so "through the seam" is asserted rather than inferred from the
    -- stored value -- which a direct table write would also produce.
    local realSet, writes = NS.Schema.Set, {}
    NS.Schema.Set = function(self, path, value)
      writes[#writes + 1] = { path, value }
      return realSet(self, path, value)
    end
    local ok, err = pcall(function()
      capture(function() byName.disable("") end)
      assertEqual(NS.db.profile.settings.enabled, false, "/lh disable turns the addon off")
      capture(function() byName.enable("") end)
      assertEqual(NS.db.profile.settings.enabled, true, "/lh enable turns it back on")
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
    assertTrue(NS.db.profile.settings.enable == nil and NS.db.global.enabled == nil,
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
    local before = NS.db.profile.settings.enabled

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
  local before = NS.db.profile.settings.enabled
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
    assertEqual(NS.db.profile.settings.enabled, true, "/lh enable must work while disabled")
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
--- got. The loop below asks NS.COMMANDS which of these exist rather than assuming all thirteen do;
--- since core/PerfSetup.lua wired the harness, `perf` is among them.
local LIVE_WHILE_DISABLED = {
  "help", "config", "version", "enable", "disable", "debug", "perf", "diagnostics",
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
  local before = NS.db.profile.settings.enabled
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
      assertEqual(NS.db.profile.settings.enabled, true, "/lh enable must still turn the addon on")
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

-- ── Chat lines hand their values to the printer's Format (events-frames-taint-§8) ───────────────
--
-- The count and toggle lines pass their values to NS.Format instead of pre-formatting them before
-- the printer. The bytes a player sees do not change, and these cases pin them.

test("Clear-blacklist confirm and /lh test print their exact lines through the printer", function()
  local F, BT = NS.Filters, NS.BrowserTable
  local realClear, realToggle = F.ClearList, BT.ToggleTestMode
  local nextOn
  F.ClearList = function() return 2 end
  BT.ToggleTestMode = function() return nextOn, true end
  local ok, err = pcall(function()
    local out = capture(function() T.mocks.StaticPopupDialogs.KA0S_LOOTHISTORY_CLEAR_BLACKLIST.OnAccept() end)
    assertEqual(out[#out], NS.PREFIX .. " blacklist cleared (2 ids).")
    nextOn = true
    out = capture(function() Sl:OnSlash("test") end)
    assertEqual(out[#out], NS.PREFIX .. " test mode on")
    nextOn = false
    out = capture(function() Sl:OnSlash("test") end)
    assertEqual(out[#out], NS.PREFIX .. " test mode off")
  end)
  F.ClearList, BT.ToggleTestMode = realClear, realToggle
  if not ok then error(err, 0) end
end)

test("/lh holdings <query> prints the matching name and its account-wide total", function()
  local saved = NS.db.global.holdings
  NS.db.global.holdings = {}
  NS.Holdings:ApplyContainer("A-Realm", "bags", { [7] = 2 }, { [7] = "|Hitem:7|h[Apple]|h" }, 100)
  NS.Holdings:ApplyContainer("B-Realm", "bank", { [7] = 9 }, {}, 50)
  local out = capture(function() Sl:Holdings("item name") end)
  NS.db.global.holdings = {}
  local none = capture(function() Sl:Holdings("item name") end)
  NS.db.global.holdings = saved
  assertEqual(#out, 1)
  -- Exact, prefix included: both lines are pinned byte for byte across their move to the shared
  -- printer's format form (LH-A-12).
  assertEqual(out[1], NS.PREFIX .. " Item Name: 11")
  assertEqual(none[1], NS.PREFIX .. " no holdings match 'item name'.")
end)
