-- tests/test_profiles.lua — profiles (docs/profiles.md).
--
-- Every setting lives in the active AceDB profile; the loot history, its repair bookkeeping, the
-- schema stamp and LibDBIcon's table stay account-wide. Three things are pinned here:
--
--   * the v8->v9 migration that moved every stored setting out of db.global into the `Default`
--     profile (savedvariables-§1): values land, global is cleared, recorded data is untouched, and
--     a second run is a no-op;
--   * the ONE adopt path the three profile events share (NS.OnProfileEvent, core/LootHistory.lua):
--     reads follow the profile, the latch follows its switch, every setting's effect is re-applied,
--     and each event logs exactly one line (debug-logging-§10);
--   * the Profiles page (settings/Profiles.lua, options-ui-§3) and the reset veto it shares.
--
-- Every case leaves the harness on `Default`, with no other profile stored and Default's contents
-- put back, because the suites after this one read state the earlier ones seeded.

local T = _G.LH_TEST
local NS, mocks = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- ── helpers ───────────────────────────────────────────────────────────────────────────────────

--- Run `fn(db)` and then put the harness back: on `Default`, every other profile deleted, Default's
--- contents restored in place, the latch and the confirmed retention re-read from it.
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

-- ── the v8 -> v9 migration (savedvariables-§1) ────────────────────────────────────────────────

--- A pre-profiles SavedVariables file at schema v8: every setting, the id lists and the saved view
--- in `global`, beside the history and LibDBIcon's table.
local function legacySv()
  return {
    global = {
      schemaVersion = 8,
      history = { { ts = 1, itemID = 11 }, { ts = 2, itemID = 12 } },
      minimap = { hide = true, minimapPos = 200 },
      settings = {
        qualityThreshold = 4, recordCurrency = false,
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
  assertEqual(sv.global.schemaVersion, 9)
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
  assertEqual(sv.global.schemaVersion, 9)
  assertEqual(sv.profiles.Default.settings.qualityThreshold, after.Default.settings.qualityThreshold)
  assertEqual(sv.profiles.Default.savedView.groupBy, "source")
  local moved
  for _, l in ipairs(lines) do moved = moved or l:match("^Migrate v8 %-> v9, (%d+) rows touched") end
  assertEqual(moved, "0", "the re-run moved nothing")
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

test("Profiles: a switch to a shorter retention asks before deleting, and No keeps every record", function()
  -- The history is account-wide, so the new profile's retention has never been confirmed against
  -- it. It goes through the same confirm a change would (S:AdoptRetention), and No writes the
  -- confirmed retention into the new profile, so the next login deletes nothing either.
  -- red under: an adopt path that only re-seeds the confirmed value, which would let the next
  -- login prune everything older than the new profile's retention, unasked.
  onProfiles(function(db)
    local g, M = NS.db.global, mocks
    local savedHistory, savedShow = g.history, M.StaticPopup_Show
    local now, day = os.time(), 86400
    g.history = { { ts = now - 40 * day, itemID = 1 }, { ts = now - 20 * day, itemID = 2 },
                  { ts = now - 3600, itemID = 3 } }
    local shown = {}
    M.StaticPopup_Show = function(which, _, a2, data)
      shown[#shown + 1] = { which = which, a2 = a2, data = data }
    end
    local ok, err = pcall(function()
      NS.Schema:Set("settings.retentionDays", 0)   -- Default keeps everything, confirmed at once
      db:SetProfile("Week")
      -- The profile holds a week, stored in some earlier session; nothing here confirms it.
      NS.db.profile.settings.retentionDays = 7
      db:SetProfile("Default")
      shown = {}
      db:SetProfile("Week")
      assertEqual(#shown, 1, "the switch asked before anything was deleted")
      assertEqual(shown[1].which, "KA0S_LOOTHISTORY_PRUNE")
      assertEqual(#g.history, 3, "nothing was deleted on the switch")
      NS.Schema:ConfirmRetention(shown[1].data.days, false)
      assertEqual(NS.Schema:Get("settings.retentionDays"), 0,
        "No wrote the confirmed retention into the new profile")
      assertEqual(#g.history, 3, "and kept every record")
    end)
    g.history, M.StaticPopup_Show = savedHistory, savedShow
    if not ok then error(err, 0) end
  end)
end)

test("Profiles: a switch to a profile with the same retention asks nothing", function()
  onProfiles(function(db)
    local M = mocks
    local savedShow, shown = M.StaticPopup_Show, 0
    M.StaticPopup_Show = function() shown = shown + 1 end
    local ok, err = pcall(function() db:SetProfile("Alt") end)
    M.StaticPopup_Show = savedShow
    if not ok then error(err, 0) end
    assertEqual(shown, 0)
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
  local ok, err = pcall(function()
    local category = NS.ProfilesPage.Build({})
    assertTrue(category ~= nil, "the page registered")
    local opts = registered["LootHistory-Profiles"]
    assertTrue(opts ~= nil and opts.db == NS.db, "the options table is AceDBOptions' over NS.db")
    local panel = mocks.__subcategories["Profiles"]
    assertTrue(panel ~= nil, "the canvas is registered under the name Profiles")
    local ctx = NS.ProfilesPage.ctx
    ctx.panel:Show()
    ctx.panel:__fire("OnShow")
    assertEqual(#opened, 1, "the first show opens the profile manager once")
    assertEqual(opened[1].app, "LootHistory-Profiles")
    assertTrue(opened[1].container.frame:IsShown(), "the container AceConfigDialog fills is shown")
    assertTrue(panel.defaultsOnClick == nil, "no Defaults button: AceDBOptions carries Reset Profile")
  end)
  libs["AceDBOptions-3.0"], libs["AceConfig-3.0"], libs["AceConfigDialog-3.0"] = nil, nil, nil
  mocks.__subcategories["Profiles"] = nil
  if NS.ProfilesPage.ctx then NS.ProfilesPage.ctx.panel:Hide() end
  if not ok then error(err, 0) end
end)
