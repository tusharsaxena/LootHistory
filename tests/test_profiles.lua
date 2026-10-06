-- tests/test_profiles.lua — profiles (docs/profiles.md).
--
-- Every setting but one lives in the active AceDB profile; the loot history, the retention that
-- prunes it (owner decision D6), its repair bookkeeping, the schema stamp and LibDBIcon's table
-- stay account-wide. Four things are pinned here:
--
--   * the v8->v9 migration that moved every stored setting out of db.global into the `Default`
--     profile (savedvariables-§1): values land, global is cleared, recorded data is untouched, and
--     a second run is a no-op;
--   * the v9->v10 migration that lifts `retentionDays` back out of every profile into
--     `global.retentionDays`, from either stored shape, keeping the value that deletes the least;
--   * retention is account-wide: it reads and writes global, and no profile event prunes, counts
--     or confirms against the history;
--   * the ONE adopt path the three profile events share (NS.OnProfileEvent, core/LootHistory.lua):
--     reads follow the profile, the latch follows its switch, every setting's effect is re-applied,
--     and each event logs exactly one line (debug-logging-§10);
--   * the Profiles page (settings/Profiles.lua, options-ui-§3) and the reset veto it shares.
--   * the `/lh profile` verb (LibKa0s Slash minor 17): its COMMANDS row, the list, a switch through
--     the adopt path, the already-current and unknown-name refusals, quotes, and combat.
--
-- Every case leaves the harness on `Default`, with no other profile stored and Default's contents
-- put back, because the suites after this one read state the earlier ones seeded.

local T = _G.LH_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- ── helpers ───────────────────────────────────────────────────────────────────────────────────

--- Run `fn(db)` and then put the harness back: on `Default`, every other profile deleted, Default's
--- contents restored in place, the latch and the confirmed retention re-read.
local function onProfiles(fn)
  local db = NS.db
  local saved = NS.Util.DeepCopy(db.profile)
  local ok, err = pcall(fn, db)
  if db:GetCurrentProfile() ~= "Default" then db:SetProfile("Default") end
  for _, name in ipairs(db:GetProfiles()) do
    if name ~= "Default" then db:DeleteProfile(name) end
  end
  local p = db.profile
  for k in pairs(p) do p[k] = nil end
  for k, v in pairs(saved) do p[k] = v end
  NS.OnEnabledChanged()
  NS.Schema:SyncRetention()
  if not ok then error(err, 0) end
end

--- Every line the debug console logged while `fn` ran, with logging on. The buffer is swapped for a
--- fresh one for the act: it is capped and shifts when full, so an index taken before can miss.
local function loggedDuring(fn)
  local saved = NS.DebugLog.buffer
  NS.DebugLog.buffer = {}
  NS.State.debug = true
  local ok, err = pcall(fn)
  NS.State.debug = false
  local logged = NS.DebugLog.buffer
  NS.DebugLog.buffer = saved
  if not ok then error(err, 0) end
  return logged
end

--- The bus messages sent while `fn` ran, as "message:reason" strings.
local function sentDuring(fn)
  local sent = {}
  local realSend = NS.bus.SendMessage
  NS.bus.SendMessage = function(self, msg, a, ...)
    sent[#sent + 1] = tostring(msg) .. ":" .. tostring(a)
    return realSend(self, msg, a, ...)
  end
  local ok, err = pcall(fn)
  NS.bus.SendMessage = realSend
  if not ok then error(err, 0) end
  return sent
end

local function count(list, want)
  local n = 0
  for _, v in ipairs(list) do if v == want then n = n + 1 end end
  return n
end

-- ── the v8 -> v9 -> v10 migrations (savedvariables-§1) ────────────────────────────────────────────────

--- A pre-profiles SavedVariables file at schema v8: every setting, the id lists and the saved view
--- in `global`, beside the history and LibDBIcon's table.
local function legacySv()
  return {
    global = {
      schemaVersion = 8,
      history = { { ts = 1, itemID = 11 }, { ts = 2, itemID = 12 } },
      minimap = { hide = true, minimapPos = 200 },
      settings = {
        qualityThreshold = 4, recordCurrency = false, retentionDays = 90,
        window = { point = "TOP", x = 1, y = 2, w = 900, h = 600 },
        auction = { capture = { ["auctionator:minbuyout"] = false },
                    priority = { "tsm:dbmarket", "auctionator:minbuyout" } },
      },
      blacklist = { [5] = true }, whitelist = { [6] = true }, currencyBlacklist = { [7] = true },
      savedView = { groupBy = "source" },
    },
  }
end

--- Run the real runner against `db`, with the harness's own db put back however it ends.
local function migrate(db)
  local real = NS.db
  NS.db = db
  local ok, err = pcall(NS.RunMigrations, NS)
  NS.db = real
  if not ok then error(err, 0) end
end

test("Migrate v8->v9: every stored setting lands in the Default profile and leaves global", function()
  -- AceDB as the client has it at InitDB: nothing has read db.profile yet, so the profile does not
  -- exist in the raw file and the step creates it.
  -- red under: a step that copies without clearing, clears without copying, or writes anywhere but
  -- the raw `Default` profile.
  local sv = legacySv()
  migrate({ global = sv.global, sv = sv })
  local d = sv.profiles and sv.profiles.Default
  assertTrue(d ~= nil, "the Default profile was created")
  assertEqual(d.settings.qualityThreshold, 4)
  assertEqual(d.settings.recordCurrency, false, "a stored false survives the move")
  assertEqual(d.settings.window.point, "TOP", "the window geometry moved with the settings")
  assertEqual(d.settings.auction.priority[1], "tsm:dbmarket", "the cascade order moved as stored")
  assertTrue(d.blacklist[5] and d.whitelist[6] and d.currencyBlacklist[7], "the three id lists moved")
  assertEqual(d.savedView.groupBy, "source", "the saved view moved")
  for _, key in ipairs({ "settings", "blacklist", "whitelist", "currencyBlacklist", "savedView" }) do
    assertEqual(sv.global[key], nil, key .. " is cleared from global")
  end
  -- ...all but the retention, which v10 lifts straight back to the account (D6).
  assertEqual(d.settings.retentionDays, nil, "no profile holds the retention")
  assertEqual(sv.global.retentionDays, 90, "the stored retention is the account's")
  assertEqual(sv.global.schemaVersion, 13)
end)

test("Migrate v8->v9: recorded data and the minimap table stay account-wide, untouched", function()
  local sv = legacySv()
  local history, minimap = sv.global.history, sv.global.minimap
  migrate({ global = sv.global, sv = sv })
  assertTrue(sv.global.history == history and #history == 2, "the loot history is not a setting")
  assertTrue(sv.global.minimap == minimap, "LibDBIcon's table stays global (launcher-§3)")
  assertEqual(minimap.hide, true)
  assertEqual(minimap.minimapPos, 200)
end)

test("Migrate v8->v9: over a profile AceDB already filled, a stored value wins and an unstored key keeps its default", function()
  -- The kit's AceDB fake reads db.profile at New, so the Default profile already holds every
  -- default when the step runs. A value the account stored lands over it; a key it never stored
  -- (AceDB's logout strip removed it for equaling the default) keeps the default.
  -- red under: a step that replaces the settings table whole, dropping every unstored default.
  local sv = legacySv()
  local db = mocks.LibStub("AceDB-3.0"):New(sv, NS.defaults, true)
  migrate(db)
  local s = db.profile.settings
  assertEqual(s.qualityThreshold, 4)
  assertEqual(s.rowHeight, NS.defaults.profile.settings.rowHeight, "an unstored key keeps its default")
  assertEqual(s.auction.capture["auctionator:minbuyout"], false, "the stored deselection wins")
  assertEqual(s.auction.capture["tsm:dbmarket"], true, "the rest of the shipped set is kept")
  assertEqual(db.profile.blacklist[5], true)
end)

test("Migrate v8->v9: a second run is a no-op", function()
  -- Idempotent twice over: the stamp stops the runner, and with the stamp forced back the step
  -- finds nothing left in global to move.
  local sv = legacySv()
  local db = { global = sv.global, sv = sv }
  migrate(db)
  local after = NS.Util.DeepCopy(sv.profiles)
  migrate(db)
  sv.global.schemaVersion = 8
  local lines = {}
  local savedDebug, savedFlag = NS.Debug, NS.State.debug
  NS.Debug = function(tag, fmt, ...) lines[#lines + 1] = tag .. " " .. fmt:format(...) end
  NS.State.debug = true
  local ok, err = pcall(migrate, db)
  NS.Debug, NS.State.debug = savedDebug, savedFlag
  if not ok then error(err, 0) end
  assertEqual(sv.global.schemaVersion, 13)
  assertEqual(sv.profiles.Default.settings.qualityThreshold, after.Default.settings.qualityThreshold)
  assertEqual(sv.profiles.Default.savedView.groupBy, "source")
  assertEqual(sv.global.retentionDays, 90, "the retention stayed the account's")
  local moved, lifted
  for _, l in ipairs(lines) do
    moved = moved or l:match("^Migrate v8 %-> v9, (%d+) rows touched")
    lifted = lifted or l:match("^Migrate v9 %-> v10, (%d+) rows touched")
  end
  assertEqual(moved, "0", "the re-run moved nothing")
  assertEqual(lifted, "0", "and lifted nothing")
end)

--- A SavedVariables file this branch's first v9 step wrote: the retention was per profile then, so
--- it sits in the `Default` profile the step created and in any profile a character wrote it into.
local function v9Sv(profiles)
  return {
    global = { schemaVersion = 9, history = { { ts = 1, itemID = 11 } }, minimap = { hide = false } },
    profiles = profiles,
  }
end

test("Migrate v9->v10: a retention stored in the profiles moves to global and leaves every profile", function()
  -- D6. red under: a step that copies without clearing, reads only the `Default` profile, or
  -- takes whichever profile it happens to walk first rather than the value that deletes the least.
  local sv = v9Sv({
    Default = { settings = { retentionDays = 7, qualityThreshold = 3 } },
    Raid    = { settings = { retentionDays = 60 } },
    Empty   = {},
  })
  local history = sv.global.history
  migrate({ global = sv.global, sv = sv })
  assertEqual(sv.global.retentionDays, 60, "the longer window is the account's")
  assertEqual(sv.profiles.Default.settings.retentionDays, nil, "Default no longer holds it")
  assertEqual(sv.profiles.Raid.settings.retentionDays, nil, "nor does any other profile")
  assertEqual(sv.profiles.Default.settings.qualityThreshold, 3, "every other setting stays put")
  assertTrue(sv.global.history == history and #history == 1, "the history is untouched")
  assertEqual(sv.global.schemaVersion, 13)
end)

test("Migrate v9->v10: keep Always (0) wins over any day count", function()
  local sv = v9Sv({
    Default = { settings = { retentionDays = 365 } },
    Alt     = { settings = { retentionDays = 0 } },
  })
  migrate({ global = sv.global, sv = sv })
  assertEqual(sv.global.retentionDays, 0, "the move must never shorten what is kept")
end)

test("Migrate v9->v10: a retention still under global.settings is lifted too, and the empty table goes", function()
  -- The pre-profiles shape, left in place when the v9 step had no raw file to move it through.
  local g = { schemaVersion = 9, history = {}, settings = { retentionDays = 14 } }
  migrate({ global = g })
  assertEqual(g.retentionDays, 14)
  assertEqual(g.settings, nil, "nothing is left under global.settings")
end)

test("Migrate v9->v10: a second run is a no-op, and a file with no stored retention keeps its own", function()
  local sv = v9Sv({ Default = { settings = { retentionDays = 45 } } })
  local db = { global = sv.global, sv = sv }
  migrate(db)
  sv.global.schemaVersion = 9
  local lines = {}
  local savedDebug, savedFlag = NS.Debug, NS.State.debug
  NS.Debug = function(tag, fmt, ...) lines[#lines + 1] = tag .. " " .. fmt:format(...) end
  NS.State.debug = true
  local ok, err = pcall(migrate, db)
  NS.Debug, NS.State.debug = savedDebug, savedFlag
  if not ok then error(err, 0) end
  assertEqual(sv.global.retentionDays, 45, "the re-run left the account's retention alone")
  local lifted
  for _, l in ipairs(lines) do lifted = lifted or l:match("^Migrate v9 %-> v10, (%d+) rows touched") end
  assertEqual(lifted, "0", "the re-run lifted nothing")

  local fresh = v9Sv({ Default = { settings = { qualityThreshold = 2 } } })
  fresh.global.retentionDays = 21
  migrate({ global = fresh.global, sv = fresh })
  assertEqual(fresh.global.retentionDays, 21, "no stored profile value, so nothing overwrote global")
end)

-- ── reads follow the active profile ───────────────────────────────────────────────────────────

test("Profiles: every read and write resolves against the ACTIVE profile", function()
  -- red under: a seam root still pointed at db.global, or one captured at load instead of asked.
  onProfiles(function(db)
    NS.Schema:Set("settings.qualityThreshold", 2)
    NS.Filters:AddBlacklist(9001)
    db:SetProfile("Alt")
    assertEqual(NS.Schema:Get("settings.qualityThreshold"), 1, "a new profile starts at the default")
    assertEqual(NS.Filters:Count(NS.Filters:Blacklist()), 0, "and with its own empty lists")
    NS.Schema:Set("settings.qualityThreshold", 4)
    db:SetProfile("Default")
    assertEqual(NS.Schema:Get("settings.qualityThreshold"), 2, "Default kept its own value")
    assertTrue(NS.Filters:Blacklist()[9001], "and its own list")
    db:SetProfile("Alt")
    assertEqual(NS.Schema:Get("settings.qualityThreshold"), 4, "Alt kept its own value")
  end)
end)

test("Profiles: the loot history is shared by every profile", function()
  onProfiles(function(db)
    local history = NS.db.global.history
    local n = #history
    db:SetProfile("Alt")
    assertTrue(NS.db.global.history == history, "a switch leaves the history where it is")
    assertEqual(NS.Database:Count(), n)
    db:CopyProfile("Default")
    db:ResetProfile()
    assertEqual(NS.Database:Count(), n, "neither a copy nor a reset reaches it")
  end)
end)

-- ── the adopt path ────────────────────────────────────────────────────────────────────────────

test("Profiles: a switch re-applies every setting through the one adopt path", function()
  -- The Collector re-reads its gate, the History window re-reads its geometry and view, and the
  -- one SettingsChanged("profile") message goes out for every other reactor.
  -- red under: a handler that only re-syncs the latch, which is what this addon had before.
  onProfiles(function(db)
    db:SetProfile("Alt")
    NS.Schema:Set("settings.qualityThreshold", 4)
    db:SetProfile("Default")
    NS.Schema:Set("settings.qualityThreshold", 1)

    local C = NS.Collector
    local wasEnabled = C._enabled
    if not wasEnabled then C:Enable() end
    local adopted, realAdopt = 0, NS.Browser.AdoptProfile
    NS.Browser.AdoptProfile = function(...) adopted = adopted + 1; return realAdopt(...) end
    local ok, err = pcall(function()
      local sent = sentDuring(function() db:SetProfile("Alt") end)
      assertEqual(count(sent, NS.MSG.SETTINGS_CHANGED .. ":profile"), 1,
        "one profile message: " .. table.concat(sent, " | "))
      assertEqual(adopted, 1, "the History window re-read the new profile once")
      local seen
      local savedGet, savedShould = NS.Compat.GetItemInfo, C.ShouldRecord
      NS.Compat.GetItemInfo = function() return 211296, "X", 2, 0 end
      C.ShouldRecord = function(_, _, _, _, cfg) seen = cfg.qualityThreshold; return false, "quality" end
      local ok2, err2 = pcall(function()
        NS.Attribution:Stamp("KILL", nil, "CERTAIN")
        C:OnChatMsgLoot(nil, string.format(mocks.LOOT_ITEM_SELF,
          "|cffa335ee|Hitem:211296::::::::80:::::|h[X]|h|r"))
      end)
      NS.Compat.GetItemInfo, C.ShouldRecord = savedGet, savedShould
      if not ok2 then error(err2, 0) end
      assertEqual(seen, 4, "the Collector's gate reads the new profile's threshold")
    end)
    NS.Browser.AdoptProfile = realAdopt
    if not wasEnabled then C:Disable() end
    if not ok then error(err, 0) end
  end)
end)

test("Profiles: a switch, a copy and a reset each refresh every open settings panel once", function()
  -- The Filters tab's id lists and the AH Price table are drawn off the profile's own tables, so an
  -- open panel has to be re-rendered against the new profile (options-ui: a profile callback
  -- refreshes an open panel).
  -- red under: an adopt path that drops the NS.Options.RefreshAllPanels call, which would leave an
  -- open panel showing the old profile's lists.
  onProfiles(function(db)
    local O = NS.Options
    local realRefresh, refreshed = O.RefreshAllPanels, 0
    O.RefreshAllPanels = function(...) refreshed = refreshed + 1; return realRefresh(...) end
    local ok, err = pcall(function()
      db:SetProfile("Alt")
      assertEqual(refreshed, 1, "the switch refreshed the open panels")
      NS.Schema:Set("settings.qualityThreshold", 3)
      db:SetProfile("Default")
      refreshed = 0
      db:CopyProfile("Alt")
      assertEqual(refreshed, 1, "the copy refreshed the open panels")
      refreshed = 0
      db:ResetProfile()
      assertEqual(refreshed, 1, "the reset refreshed the open panels")
    end)
    O.RefreshAllPanels = realRefresh
    if not ok then error(err, 0) end
  end)
end)

test("Profiles: a switch to a profile where the addon is off stands it down, and back brings it up", function()
  -- `settings.enabled` is profile-scoped, so the latch follows the profile (slash-commands-§7).
  -- red under: an adopt path that re-applies settings but never re-reads the switch.
  onProfiles(function(db)
    db:SetProfile("Off")
    NS.Schema:Set("settings.enabled", false)
    db:SetProfile("Default")
    assertFalse(NS.Lifecycle:IsHeld(NS.HOLD_DISABLED), "Default is on")
    db:SetProfile("Off")
    assertTrue(NS.AddonIsOff(), "the stored switch is the new profile's")
    assertTrue(NS.Lifecycle:IsHeld(NS.HOLD_DISABLED), "the latch took the disabled hold")
    db:SetProfile("Default")
    assertFalse(NS.Lifecycle:IsHeld(NS.HOLD_DISABLED), "and released it on the way back")
  end)
end)

test("Profiles: each profile event logs exactly one line, worded by the event", function()
  -- debug-logging-§10: a switch is the [Profile] trace; a copy and a reset replace the profile
  -- wholesale and are one [Set] line each. A reset driven straight at the db (AceDBOptions' own
  -- Reset Profile) was counted by nothing, so its line carries no count rather than a wrong one.
  onProfiles(function(db)
    local function linesOf(fn)
      local out = {}
      for _, line in ipairs(loggedDuring(fn)) do
        if line:find("[Profile]", 1, true) or line:find("[Set]", 1, true) then out[#out + 1] = line end
      end
      return out
    end
    local l = linesOf(function() db:SetProfile("Alt") end)
    assertEqual(#l, 1, table.concat(l, " | "))
    assertTrue(l[1]:find("[Profile] switched to profile 'Alt'", 1, true) ~= nil, l[1])
    NS.Schema:Set("settings.qualityThreshold", 3)
    db:SetProfile("Default")
    l = linesOf(function() db:CopyProfile("Alt") end)
    assertEqual(#l, 1, table.concat(l, " | "))
    assertTrue(l[1]:find("[Set] copied profile 'Alt' \226\134\146 'Default'", 1, true) ~= nil, l[1])
    assertEqual(NS.Schema:Get("settings.qualityThreshold"), 3, "the copy landed")
    l = linesOf(function() db:ResetProfile() end)
    assertEqual(#l, 1, table.concat(l, " | "))
    assertTrue(l[1]:find("[Set] reset profile 'Default' to defaults", 1, true) ~= nil, l[1])
    assertTrue(l[1]:find("rows)", 1, true) == nil, "an uncounted reset names no count: " .. l[1])
  end)
end)

-- ── the `profile` verb (LibKa0s Slash minor 17) ─────────────────────────────────────────────────
--
-- `/lh profile` lists the profiles and `/lh profile <name>` switches to an existing one. The
-- behavior is the library's (Sl:CliProfile); what is this addon's is the COMMANDS row, the store it
-- hands the descriptor (`profiles = NS.db`), the live-while-disabled choice and the one log line
-- the adopt path writes when the switch lands. The disabled pins are in tests/test_disabled.lua,
-- the library-absent stub's in tests/test_slash_degraded.lua.

local Sl = NS.Slash

--- Every chat line `fn` printed, in order, tags included.
local function chatDuring(fn)
  local cf, out = mocks.DEFAULT_CHAT_FRAME, {}
  local old = cf.AddMessage
  cf.AddMessage = function(_, line) out[#out + 1] = line end
  local ok, err = pcall(fn)
  cf.AddMessage = old
  if not ok then error(err, 0) end
  return out
end

local function tagged(line) return NS.PREFIX .. " " .. line end

--- The stored profile names, sorted and joined: the witness that nothing was created.
local function storedProfiles(db)
  local names = db:GetProfiles()
  table.sort(names)
  return table.concat(names, ",")
end

test("profile verb: a COMMANDS row after resetall, and the whole verb order pinned", function()
  -- red under: a missing row, one placed away from the settings verbs, or a changed description.
  local order = {}
  for i, c in ipairs(NS.COMMANDS) do order[i] = c[1] end
  assertEqual(table.concat(order, " "), "show hide toggle config enable disable version get set "
    .. "list reset resetall profile holdings debug diagnostics perf test purge help")
  assertEqual(#NS.COMMANDS, 20, "twenty verbs")
  assertEqual(NS.COMMANDS[13][2], "List profiles, or switch to one: profile <name>")
end)

test("profile verb: help prints the header and one row per verb, profile among them", function()
  local out = chatDuring(function() Sl:PrintHelp() end)
  assertEqual(#out, 1 + #NS.COMMANDS, table.concat(out, " | "))
  local found = 0
  for _, line in ipairs(out) do
    if line:find("/lh profile", 1, true) and line:find("List profiles, or switch to one", 1, true) then
      found = found + 1
    end
  end
  assertEqual(found, 1, "the profile row is in the help index once")
end)

test("profile verb: bare /lh profile lists every profile, sorted, current marked, then the hint", function()
  -- red under: a descriptor with no `profiles` field (the list reads "Profiles are not available.").
  onProfiles(function(db)
    db:SetProfile("zeta")
    db:SetProfile("Alt")
    local out = chatDuring(function() Sl:OnSlash("profile") end)
    assertEqual(table.concat(out, "\n"), table.concat({
      tagged("|cff33ff99Profiles|r"),
      tagged("  Alt (current)"),
      tagged("  Default"),
      tagged("  zeta"),
      tagged("/lh profile <name> switches profile"),
    }, "\n"))
    for _, line in ipairs(out) do
      assertTrue(line:sub(-1) ~= ":", "no trailing colon (slash-commands-§4): " .. line)
    end
  end)
end)

test("profile verb: /lh profile <name> switches, and the adopt path logs the one switch line", function()
  -- red under: a verb that switched without the store's callback (no [Profile] line, no adopt).
  onProfiles(function(db)
    db:SetProfile("Alt")
    NS.Schema:Set("settings.qualityThreshold", 4)
    db:SetProfile("Default")
    NS.Schema:Set("settings.qualityThreshold", 1)
    local out
    local logged = loggedDuring(function()
      out = chatDuring(function() Sl:OnSlash("profile Alt") end)
    end)
    assertEqual(table.concat(out, " | "), tagged("Switched to profile 'Alt'."))
    assertEqual(db:GetCurrentProfile(), "Alt")
    assertEqual(NS.Schema:Get("settings.qualityThreshold"), 4, "reads follow the new profile")
    local switched = 0
    for _, line in ipairs(logged) do
      if line:find("[Profile] switched to profile 'Alt'", 1, true) then switched = switched + 1 end
    end
    assertEqual(switched, 1, "one switch line, from the host's profile handler")
  end)
end)

test("profile verb: the current profile answers 'Already on', and switches nothing", function()
  onProfiles(function(db)
    local out = chatDuring(function() Sl:OnSlash("profile Default") end)
    assertEqual(table.concat(out, " | "), tagged("Already on profile 'Default'."))
    assertEqual(db:GetCurrentProfile(), "Default")
  end)
end)

test("profile verb: an unknown name is refused with a did-you-mean and the list, and nothing is created", function()
  -- Profile names are case-sensitive, so `alt` is not `Alt`. AceDB's SetProfile creates whatever
  -- it is handed, which is how a typo would become a stray profile.
  onProfiles(function(db)
    db:SetProfile("Alt")
    db:SetProfile("Default")
    local before = storedProfiles(db)
    local out = chatDuring(function() Sl:OnSlash("profile alt") end)
    assertEqual(out[1], tagged("No profile named 'alt'."))
    assertEqual(out[2], tagged("Did you mean 'Alt'?"))
    assertEqual(out[3], tagged("|cff33ff99Profiles|r"))
    assertEqual(#out, 6, table.concat(out, " | "))
    assertEqual(db:GetCurrentProfile(), "Default", "no switch")
    assertEqual(storedProfiles(db), before, "no profile created")
  end)
end)

test("profile verb: surrounding quotes are stripped, and inner spaces and case are kept", function()
  onProfiles(function(db)
    db:SetProfile("My Alt")
    db:SetProfile("Default")
    local out = chatDuring(function() Sl:OnSlash('profile "My Alt"') end)
    assertEqual(table.concat(out, " | "), tagged("Switched to profile 'My Alt'."))
    assertEqual(db:GetCurrentProfile(), "My Alt")
    out = chatDuring(function() Sl:OnSlash("profile 'Default'") end)
    assertEqual(table.concat(out, " | "), tagged("Switched to profile 'Default'."))
  end)
end)

test("profile verb: in combat the switch is refused, and the list still answers", function()
  onProfiles(function(db)
    db:SetProfile("Alt")
    db:SetProfile("Default")
    local real = mocks.InCombatLockdown
    mocks.InCombatLockdown = function() return true end
    local ok, err = pcall(function()
      local out = chatDuring(function() Sl:OnSlash("profile Alt") end)
      assertEqual(table.concat(out, " | "), tagged("Can't switch profiles in combat."))
      assertEqual(db:GetCurrentProfile(), "Default")
      out = chatDuring(function() Sl:OnSlash("profile") end)
      assertEqual(out[1], tagged("|cff33ff99Profiles|r"))
    end)
    mocks.InCombatLockdown = real
    if not ok then error(err, 0) end
  end)
end)

-- ── retention is account-wide (owner decision D6) ──────────────────────────────────────────────

--- Run `fn(g)` with the account's history and retention saved and put back however it ends.
local function keepingHistory(fn)
  local g = NS.db.global
  local savedHistory, savedDays = g.history, g.retentionDays
  local ok, err = pcall(fn, g)
  g.history, g.retentionDays = savedHistory, savedDays
  NS.Schema:SyncRetention()
  if not ok then error(err, 0) end
end

test("Profiles: retention reads and writes global, and a switch never changes it", function()
  -- red under: a retention row whose root is the active profile again, which gives each profile
  -- its own window over the one shared history.
  keepingHistory(function(g)
    g.history = {}
    onProfiles(function(db)
      assertTrue(NS.Schema:Set("settings.retentionDays", 90))
      assertEqual(g.retentionDays, 90, "the write landed in db.global")
      assertEqual(db.profile.settings.retentionDays, nil, "and not in the profile")
      db:SetProfile("Alt")
      assertEqual(NS.Schema:Get("settings.retentionDays"), 90, "a new profile reads the same value")
      assertTrue(NS.Schema:Set("settings.retentionDays", 14))
      db:SetProfile("Default")
      assertEqual(NS.Schema:Get("settings.retentionDays"), 14, "a write under Alt is Default's too")
      assertEqual(db.profile.settings.retentionDays, nil)
    end)
  end)
  -- The player is told on the History tab, where the row is: its tooltip says account-wide.
  local tip = NS.Schema:FindRow("settings.retentionDays").tooltip
  assertTrue(tip:find("Account-wide", 1, true) ~= nil, "the tooltip marks it account-wide: " .. tip)
end)

test("Profiles: the login prune reads the account-wide retention, never a profile's", function()
  -- A stray per-profile value (a file from before v10, or a hand edit) must not decide what goes.
  -- red under: Database:PruneOld reading NS.db.profile.settings.retentionDays.
  keepingHistory(function(g)
    onProfiles(function(db)
      local now, day = os.time(), 86400
      g.history = { { ts = now - 40 * day, itemID = 1 }, { ts = now - day, itemID = 2 } }
      g.retentionDays = 30
      db.profile.settings.retentionDays = 0   -- "keep Always", in the wrong store
      assertEqual(NS.Database:PruneOld(), 1, "the prune used the account's 30 days")
      assertEqual(#g.history, 1)
    end)
  end)
end)

test("Profiles: a switch, a copy and a reset leave the loot history untouched and never prune", function()
  -- D6: a profile event never deletes or prunes history. The history holds records a 7-day
  -- retention WOULD drop, so any prune, count or confirm on the adopt path shows up here.
  -- red under: an adopt path that calls Database:PruneOld or the retention confirm, or a profile
  -- reset (AceDBOptions' Reset Profile, /lh resetall) that moves the account's retention.
  keepingHistory(function(g)
    onProfiles(function(db)
      local now, day = os.time(), 86400
      local history = { { ts = now - 40 * day, itemID = 1 }, { ts = now - 20 * day, itemID = 2 },
                        { ts = now - 3600, itemID = 3 } }
      g.history, g.retentionDays = history, 7
      NS.Schema:SyncRetention()
      local D, M = NS.Database, mocks
      local realPrune, realCount, realShow = D.PruneOld, D.CountOlderThan, M.StaticPopup_Show
      local pruned, counted, shown = 0, 0, 0
      D.PruneOld = function(...) pruned = pruned + 1; return realPrune(...) end
      D.CountOlderThan = function(...) counted = counted + 1; return realCount(...) end
      M.StaticPopup_Show = function() shown = shown + 1 end
      local ok, err = pcall(function()
        db:SetProfile("Alt")
        NS.Schema:Set("settings.qualityThreshold", 3)
        db:SetProfile("Default")
        db:CopyProfile("Alt")
        db:ResetProfile()
        NS.Slash:CliResetAll()
        db:SetProfile("Alt")
      end)
      D.PruneOld, D.CountOlderThan, M.StaticPopup_Show = realPrune, realCount, realShow
      if not ok then error(err, 0) end
      assertEqual(pruned, 0, "no profile event pruned")
      assertEqual(counted, 0, "or counted records against a retention")
      assertEqual(shown, 0, "or raised a confirm")
      assertTrue(g.history == history and #history == 3, "every record is still there")
      assertEqual(g.retentionDays, 7, "and the account's retention did not move")
    end)
  end)
end)

-- ── the Profiles page (options-ui-§3) ─────────────────────────────────────────────────────────

test("Profiles page: the global reset's veto keeps only the session-only rows, never the Profiles page", function()
  -- options-ui-§3/§12, named once and shared by the Options descriptor and the library-less reset.
  local S = NS.Schema
  for _, row in ipairs(S.Schema) do
    assertEqual(S.VetoedFromResetAll(row), not row.sessionOnly, row.path)
  end
  assertTrue(S.VetoedFromResetAll({ path = "x", sessionOnly = true, page = "Profiles" }),
    "nothing on the Profiles page is a reset's to touch")
end)

test("Profiles page: without AceDBOptions the page opts out, and nothing is registered", function()
  -- Headless there is no AceDBOptions, AceConfig or AceConfigDialog: the builder answers nil,
  -- which the registry treats as an opt-out rather than a failure.
  assertEqual(NS.ProfilesPage.Build({}), nil)
  assertEqual(mocks.__subcategories["Profiles"], nil)
end)

test("Profiles page: AceDBOptions' table over this db, drawn by AceConfigDialog into a Profiles canvas", function()
  -- red under: an options table built over a different db, a page with a Defaults button, or a
  -- renderer that leaves a pooled (hidden) container unshown.
  local libs = mocks.__libs
  local registered, opened = {}, {}
  libs["AceDBOptions-3.0"] = { GetOptionsTable = function(_, db) return { type = "group", db = db } end }
  libs["AceConfig-3.0"] = { RegisterOptionsTable = function(_, app, opts) registered[app] = opts end }
  libs["AceConfigDialog-3.0"] = {
    Open = function(_, app, container) opened[#opened + 1] = { app = app, container = container } end,
  }
  -- The mock's SimpleGroup is born shown, which would pass a renderer that never shows it. The
  -- client's AceGUI:Create hands back a POOLED group, which AceGUI:Release hid before pooling, so
  -- the builder is given one in that state: every SimpleGroup it creates arrives hidden.
  local savedAceGUI = NS.AceGUI
  local realAceGUI = savedAceGUI or libs["AceGUI-3.0"]
  local created
  NS.AceGUI = setmetatable({
    Create = function(_, wtype)
      local w = realAceGUI:Create(wtype)
      if wtype == "SimpleGroup" then w.frame:Hide(); created = w end
      return w
    end,
  }, { __index = realAceGUI })
  local ok, err = pcall(function()
    local category = NS.ProfilesPage.Build({})
    NS.AceGUI = savedAceGUI
    assertTrue(category ~= nil, "the page registered")
    local opts = registered["LootHistory-Profiles"]
    assertTrue(opts ~= nil and opts.db == NS.db, "the options table is AceDBOptions' over NS.db")
    local panel = mocks.__subcategories["Profiles"]
    assertTrue(panel ~= nil, "the canvas is registered under the name Profiles")
    local ctx = NS.ProfilesPage.ctx
    assertTrue(created ~= nil and not created.frame:IsShown(), "the pooled container starts hidden")
    -- The library records the option at CreatePanel and builds the button on the first show
    -- (libs/LibKa0s/Options.lua, O.EnsureDefaultsButton), so both halves are read.
    assertEqual(ctx.panel.wantsDefaultsButton, false, "the page declares no Defaults button")
    ctx.panel:Show()
    ctx.panel:__fire("OnShow")
    assertEqual(#opened, 1, "the first show opens the profile manager once")
    assertEqual(opened[1].app, "LootHistory-Profiles")
    assertTrue(opened[1].container == created, "AceConfigDialog fills the page's own container")
    assertTrue(created.frame:IsShown(), "the render showed the pooled container")
    assertEqual(ctx.panel.defaultsBtn, nil, "no Defaults button: AceDBOptions carries Reset Profile")
  end)
  NS.AceGUI = savedAceGUI
  libs["AceDBOptions-3.0"], libs["AceConfig-3.0"], libs["AceConfigDialog-3.0"] = nil, nil, nil
  mocks.__subcategories["Profiles"] = nil
  if NS.ProfilesPage.ctx then NS.ProfilesPage.ctx.panel:Hide() end
  if not ok then error(err, 0) end
end)

-- ── the v11 -> v12 migration: Show transfers defaults on ───────────────────────────────────────────
test("Migrate v11->v12: an explicit showTransfers = false is dropped from every profile", function()
  -- red under: a step that skips non-Default profiles, or leaves the stored false in place.
  local sv = {
    global = { schemaVersion = 11, history = {}, minimap = { hide = false } },
    profiles = {
      Default = { settings = { showTransfers = false, qualityThreshold = 3 } },
      Raid    = { settings = { showTransfers = true } },
      Empty   = {},
    },
  }
  migrate({ global = sv.global, sv = sv })
  assertEqual(sv.profiles.Default.settings.showTransfers, nil, "the stored false is gone, the default applies")
  assertEqual(sv.profiles.Default.settings.qualityThreshold, 3, "every other setting stays put")
  assertEqual(sv.profiles.Raid.settings.showTransfers, true, "a stored true is kept")
  assertEqual(sv.global.schemaVersion, 13)
end)

test("Migrate v11->v12: a false set after the step stays false; a re-run changes nothing", function()
  local sv = {
    global = { schemaVersion = 11, history = {}, minimap = { hide = false } },
    profiles = { Default = { settings = { showTransfers = false } } },
  }
  migrate({ global = sv.global, sv = sv })
  sv.profiles.Default.settings.showTransfers = false   -- the player turns it off afterwards
  migrate({ global = sv.global, sv = sv })
  assertEqual(sv.profiles.Default.settings.showTransfers, false, "an at-version DB is not walked again")
end)

test("Defaults: Show transfers is on for a new profile", function()
  assertEqual(NS.defaults.profile.settings.showTransfers, true)
end)
