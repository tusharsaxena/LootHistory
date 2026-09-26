local T = _G.LH_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- ── THE DISABLED STATE IS TOTAL (slash-commands-§7) ───────────────────────────────────────────
--
-- The conformance suite that section makes a MUST, and it exists because a definition with no test
-- is what produced eleven draw gates. This addon shipped one of them: `settings.enabled` was an
-- upvalue modules/Collector.lua read at the top of OnChatMsgLoot, and CHAT_MSG_LOOT stayed
-- registered — so the client went on walking the registration list on every loot line in the raid,
-- building the argument frame and entering Lua for an addon the player had switched off.
--
-- EVERY NEGATIVE CASE HERE ASSERTS ON THE REGISTRATION SET, through the kit's recording mock, and
-- never on a handler's return value. That is the whole design of the file rather than a preference:
-- an early return is exactly what a draw gate does, so a suite written against one CERTIFIES the
-- thing it exists to catch. `M.__registrations()` removes an entry on the matching unregister, which
-- is what makes "nothing is registered" falsifiable in the useful direction.
--
-- AND `M.__fire` RATHER THAN `__fire` ON A FRAME. A frame's OnEvent runs whether or not the frame
-- ever registered, so a case that only fires an event passes against broken code. `M.__fire`
-- dispatches to the LIVE registration set and nothing else, which is what the client does.

local ENABLED = "settings.enabled"

--- Write the switch through the addon's SINGLE WRITE SEAM, never by calling a teardown function.
--- §7 step 2 asks for exactly this: the test has to exercise the route the checkbox and the verb
--- take, because a suite that called `NS.StandDown()` directly would pass on an addon whose
--- checkbox was wired to nothing.
local function setEnabled(v) NS.Schema:Set(ENABLED, v) end

--- A registration as a comparable string, WITHOUT its target's identity.
---
--- The target is deliberately left out. Three of the four registration owners subscribe on a
--- PRIVATE bus target built fresh by `NS.NewBusTarget()` (core/LootHistory.lua), so a stand-up
--- produces new tables holding the same subscriptions — and a comparison keyed on table identity
--- would report a correct restoration as a total mismatch. What §7 asks is that the addon watches
--- the same things again, which is what this compares.
local function key(r)
  return (r.kind or "?") .. ":" .. tostring(r.event) .. ":" .. tostring(r.unit)
end

local function regSet()
  local out = {}
  for _, r in ipairs(M.__registrations()) do out[#out + 1] = key(r) end
  table.sort(out)
  return out
end

local function setOf(list)
  local t = {}
  for _, v in ipairs(list) do t[v] = (t[v] or 0) + 1 end
  return t
end

--- Which of `want`'s entries are missing from `got`, as a readable line.
local function missing(want, got)
  local have, out = setOf(got), {}
  for _, k in ipairs(want) do
    if not have[k] then out[#out + 1] = k end
  end
  return table.concat(out, ", ")
end

--- The registrations this ADDON owns, named rather than counted. §7 asks for the assertion "by
--- count AND by name", and a count alone passes an addon that unregistered the cheap seven and kept
--- the expensive one. Spelled out here rather than derived from the modules, because a list read off
--- the implementation agrees with it however wrong it gets.
local OWNED = {
  "event:PLAYER_ENTERING_WORLD:nil",
  "event:CHAT_MSG_LOOT:nil",
  "event:CHAT_MSG_CURRENCY:nil",
  "event:LOOT_OPENED:nil",
  "event:ENCOUNTER_START:nil",
  "event:ENCOUNTER_END:nil",
  "event:CHALLENGE_MODE_START:nil",
  "event:CHALLENGE_MODE_COMPLETED:nil",
  "event:TRADE_ACCEPT_UPDATE:nil",
  "event:QUEST_TURNED_IN:nil",
  "event:ZONE_CHANGED_NEW_AREA:nil",
  "event:CHALLENGE_MODE_RESET:nil",
  "event:PLAYER_REGEN_DISABLED:nil",
  "event:PLAYER_REGEN_ENABLED:nil",
  "unit:UNIT_SPELLCAST_SUCCEEDED:player",
  "message:Ka0s_LootHistory_SettingsChanged:nil",
  "message:Ka0s_LootHistory_HistoryChanged:nil",
  "message:Ka0s_LootHistory_RecordAdded:nil",
}

--- WHAT SURVIVES, AND WHY THE SET IS NOT SIMPLY EMPTY. §7 exempts a short named list as SETUP
--- rather than feature, and one item on it registers: the settings PANEL's body subscribes to the
--- history bus so its counts stay live (settings/Panel.lua). The panel stays listed in Blizzard's
--- tree with its Enable checkbox live while the addon is off — that registration is what replaces
--- the things a disabled addon can no longer do for itself — so it is not a survivor of the
--- stand-down, it is one of the things the stand-down is defined not to reach.
---
--- The statement is therefore made in two halves, and together they are as strong as "empty": every
--- registration this addon OWNS is gone, and NOTHING that survives is a game event. The panel
--- subscribes to messages only, so a game-event survivor of any kind is the draw gate.
--- The five TARGETS this addon registers on, as a set, read off the addon itself.
---
--- KEYED BY TARGET AND NOT BY NAME, because the addon and the settings panel subscribe to the SAME
--- three message names — `SettingsChanged`, `HistoryChanged`, `RecordAdded` — and a survey that
--- dropped the target could not tell the Browser's live subscription from the panel's. Captured
--- while the addon is UP, and then reused after it goes down: a stand-down that nils its handle
--- without unregistering still has its registrations counted here, because this set remembers the
--- table even after the module forgets it.
local function featureTargets()
  local t = {}
  for _, target in ipairs({ NS.addon, NS.Collector.__ev, NS.Browser.__ev, NS.Analytics.__ev,
                            NS.Attribution.__spellFrame }) do
    if target then t[target] = true end
  end
  return t
end

--- Every live registration held by one of `targets`, by name, sorted.
---
--- ONE EXCLUSION, and it is about the harness rather than the addon: `NS.addon` is also `NS.bus`,
--- the shared message bus, and a suite that ran earlier can leave a probe subscribed to it. The
--- addon itself subscribes to NO message on that target — every module uses a private bus target
--- (core/LootHistory.lua's NS.NewBusTarget), precisely so two consumers cannot clobber each other —
--- so a message there is somebody else's and never a survivor of this stand-down. Its game EVENTS
--- are very much this addon's and are counted.
local function liveOn(targets)
  local out = {}
  for _, r in ipairs(M.__registrations()) do
    if targets[r.target] and not (r.target == NS.addon and r.kind == "message") then
      out[#out + 1] = key(r)
    end
  end
  table.sort(out)
  return out
end

--- Every LIVE registration that is a game event rather than a message — the half of the set the
--- setup exemption cannot account for.
local function liveGameEvents()
  local out = {}
  for _, r in ipairs(M.__registrations()) do
    if r.kind ~= "message" then out[#out + 1] = key(r) end
  end
  table.sort(out)
  return out
end

--- Bring the addon up the way the client does — `addon:OnEnable`, not a fan-out of Enable calls —
--- and open the window, so there is something drawn to take down.
---
--- FIRST, CLOSE EVERY SETTINGS PAGE AN EARLIER SUITE LEFT ON SCREEN. Since LibKa0s v1.46.1 the
--- library's combat lock (options-ui-§2) registers PLAYER_REGEN_DISABLED / _ENABLED while one of its
--- pages is on screen, and correctly keeps them while that page stays up — a stood-down addon's
--- settings window stays usable, and its lock with it. The panel suites show pages and never close
--- them, so without this the baseline would carry the library's two REGEN registrations, which are
--- not this addon's and are not a survivor of the stand-down. The kit mock's Hide fires no script,
--- hence the explicit OnHide that lets the library let go.
local function bringUp()
  local optionsLib = M.LibStub("LibKa0s-Options-1.0", true)
  for ctx in pairs(optionsLib and optionsLib.__shownPages or {}) do
    ctx.panel:Hide()
    ctx.panel:__fire("OnHide")
  end
  setEnabled(true)
  NS.addon:OnEnable()
  NS.Analytics:Enable()
  NS.Browser:Show()
end

local function shownNames()
  local t = {}
  for _, f in ipairs(M.__shownFrames()) do t[f] = true end
  return t
end

-- ── 1. baseline ───────────────────────────────────────────────────────────────────────────────

test("slash-commands-§7 step 1: enabled, the addon registers a NON-EMPTY set and draws", function()
  -- An addon that registers nothing when enabled passes every later assertion trivially, which is
  -- why §7 makes this step 1 rather than an implied precondition.
  bringUp()
  local R_on = regSet()
  assertTrue(#R_on > 0, "the enabled addon registered nothing at all")
  assertEqual(missing(OWNED, R_on), "",
    "the enabled addon is missing registrations this suite is written against")
end)

-- ── 2/3. the registration set is empty ────────────────────────────────────────────────────────

test("slash-commands-§7 step 3: disabling UNREGISTERS every event, unit-event and message the addon owns",
  function()
    -- THE ASSERTION THE WHOLE SUITE EXISTS FOR, and the one that reddens a draw gate. It is
    -- deliberately NOT written as "call a handler and assert it returned early": that is the draw
    -- gate passing its own test.
    -- red under: drop the UnregisterAllEvents / UnregisterEvent calls from NS.StandDown and the
    -- three modules' Disable, and put modules/Collector.lua's `if not enabled then return end`
    -- back — the addon behaves identically from the outside and every entry below survives.
    bringUp()
    local targets = featureTargets()
    assertEqual(missing(OWNED, liveOn(targets)), "",
      "the baseline is not what this case is written against")
    setEnabled(false)
    assertEqual(table.concat(liveOn(targets), ", "), "",
      "these registrations survived the disabled state")
    assertEqual(table.concat(liveGameEvents(), ", "), "",
      "a GAME EVENT is still registered: the setup exemption reaches messages, never these")
    setEnabled(true)
  end)

-- ── 4. nothing is left to wake up ─────────────────────────────────────────────────────────────

test("slash-commands-§7 step 4: every deferral the addon armed is CANCELED, not left to find a flag",
  function()
    -- The retention prune is the case that makes this more than bookkeeping: it is a
    -- SavedVariables write on a five-second fuse lit by PLAYER_ENTERING_WORLD, and `C_Timer.After`
    -- cannot be put out. A player who switched the addon off inside those five seconds got the
    -- write anyway, from a game event, while it was disabled.
    --
    -- MEASURED AS A DELTA. The kit's live-timer set is shared with every suite that ran before this
    -- one, so the absolute count is not this addon's to assert; what is this addon's is that the
    -- deferrals it armed are gone again.
    bringUp()
    local before = #M.__timers()
    NS.State.cleanupDone = false
    assertTrue(M.__fire("PLAYER_ENTERING_WORLD") > 0, "the login handler must be registered")
    assertTrue(#M.__timers() > before, "PLAYER_ENTERING_WORLD must arm the retention deferrals")

    setEnabled(false)
    assertEqual(#M.__timers(), before, "a deferral was left armed on a stood-down addon")
    setEnabled(true)
  end)

-- ── 5. every frame is hidden, and stays hidden ────────────────────────────────────────────────

test("slash-commands-§7 step 5: the window goes down, and the SHOW LADDER is what keeps it down", function()
  -- §7 asks for hiding enforced AT THE SOURCE rather than imperatively, for the reason
  -- performance-§6 already gives about suspend: hidden frames come back. A combat transition, a
  -- settings change or the next ApplyVisibility re-shows the window behind the switch's back, and
  -- the addon is then visibly running while it claims to be off.
  -- F_on IS A DELTA, and it has to be: the settings panel's canvases are built and shown by the
  -- suites that ran before this one, and they are SETUP — §7 keeps the panel listed and live while
  -- the addon is off, which is what replaces the things it can no longer do for itself. What this
  -- case owns is the frames BRINGING THE ADDON UP put on the screen.
  setEnabled(false)
  local before = shownNames()
  bringUp()
  local F_on = {}
  for f in pairs(shownNames()) do
    if not before[f] then F_on[f] = true end
  end
  assertTrue(next(F_on) ~= nil, "bringing the addon up must draw something for this to be about")
  assertTrue(NS.Browser:GetWindow() ~= nil and NS.Browser:GetWindow():IsShown(),
    "the window must be up before this asks whether it goes down")

  setEnabled(false)
  for f in pairs(F_on) do
    assertFalse(f:IsShown(), "a frame that was shown is still shown on a disabled addon")
  end
  -- The source, not the symptom: every route into the window asks this one question.
  assertFalse(NS.Browser:VisibilityAllows(),
    "the show ladder must answer NO while the addon is stood down")
  NS.Browser:Show()
  assertTrue(NS.Browser:GetWindow() == nil or not NS.Browser:GetWindow():IsShown(),
    "the window came back on a disabled addon")
  setEnabled(true)
end)

-- ── 6. fire everything anyway ─────────────────────────────────────────────────────────────────

test("slash-commands-§7 step 6: firing every event it used to watch writes nothing, prints nothing, draws nothing",
  function()
    -- The client will not fire these, because nothing is registered — but a SURVIVOR would get
    -- them, and this is what says so. The combat-entry event is named explicitly because it is the
    -- one the collection's worst live example rides: an addon that writes `locked = true` and
    -- prints a line to chat on entering combat WHILE DISABLED, which is the failure in its purest
    -- form — the player's evidence that the addon is off is the absence of exactly that line.
    -- red under: any registration left in place by NS.StandDown; every one of them makes `M.__fire`
    -- reach a handler again, and the three surveys below stop being empty.
    bringUp()
    local R_on = M.__registrations()
    setEnabled(false)

    local shownBefore = shownNames()
    M.__resetSvWrites()
    M.__resetPrinted()

    local ran = 0
    for _, r in ipairs(R_on) do
      if r.kind ~= "message" then ran = ran + M.__fire(r.event) end
    end
    ran = ran + M.__fire("PLAYER_REGEN_DISABLED")

    assertEqual(ran, 0, "an event reached a handler on a stood-down addon")
    local writes = {}
    for _, w in ipairs(M.__svWrites()) do writes[#writes + 1] = w.path end
    assertEqual(table.concat(writes, ", "), "",
      "a game event wrote SavedVariables while the addon was disabled")
    assertEqual(table.concat(M.__printed(), " | "), "",
      "a game event printed to chat while the addon was disabled")
    for _, f in ipairs(M.__shownFrames()) do
      assertTrue(shownBefore[f], "a game event shed a frame onto the screen while disabled")
    end
    setEnabled(true)
  end)

-- ── 7. the slash surface, which is UNCHANGED ──────────────────────────────────────────────────

--- slash-commands-§2's live set, verbatim, and spelled out rather than read off the addon. The
--- standard narrowed this to `enable` and `help` at v2.56.0 and REVERSED it at v2.57.0: every one of
--- these answers normally while disabled, and so does the bare `/lh`, which opens the panel. That
--- last one is the case that settled it.
local RESERVED = {
  "help", "config", "version", "enable", "disable", "debug", "perf", "diagnostics",
  "get", "set", "list", "reset", "resetall",
}

--- The addon's own FEATURE verbs — the ones §2's SHOULD refuses. This addon takes that SHOULD, so
--- the suite pins the choice and it cannot drift silently.
local FEATURE = { "show", "hide", "toggle", "test", "purge" }

local function capture(fn)
  local cf = M.DEFAULT_CHAT_FRAME
  local old, out = cf.AddMessage, {}
  cf.AddMessage = function(_, line) out[#out + 1] = line end
  local ok, err = pcall(fn)
  cf.AddMessage = old
  if not ok then error(err, 0) end
  return out
end

test("slash-commands-§7 step 7: every RESERVED verb still answers, and the bare /lh opens the panel",
  function()
    -- STEP 7 IS NOT THE STAND-DOWN — steps 1-6 are, and a green step 7 says nothing about whether
    -- the addon is inert. What it says is that the addon is still REACHABLE: a player has to be
    -- able to read and repair settings, and to reach the panel, while it is off, which is precisely
    -- when they are most likely to need to.
    bringUp()
    local byName = {}
    for _, c in ipairs(NS.COMMANDS) do byName[c[1]] = true end
    local args = { get = "settings.scale", set = "settings.scale 1", reset = "settings.scale",
                   debug = "off" }
    local realOpen, opens = NS.Panel.Open, 0
    NS.Panel.Open = function() opens = opens + 1 end
    local saved = {}
    for k, v in pairs(NS.db.global) do saved[k] = v end

    local ok, err = pcall(function()
      for _, verb in ipairs(RESERVED) do
        if byName[verb] then
          -- Re-asserted per verb, because `enable` in this very list turns the addon back on.
          setEnabled(false)
          local out = capture(function() NS.Slash:OnSlash(verb .. " " .. (args[verb] or "")) end)
          assertTrue(out[1] ~= NS.PREFIX .. " " .. NS.Slash.DisabledLine(),
            "/lh " .. verb .. " was refused, and §2 MUSTs that it keeps answering")
        end
      end
      -- The bare command, which is the case the reversal turned on.
      setEnabled(false)
      local was = opens
      capture(function() NS.Slash:OnSlash("") end)
      assertEqual(opens, was + 1, "the bare /lh must open the settings panel while disabled")
      -- And the way back, asserted on its effect rather than its output.
      capture(function() NS.Slash:OnSlash("enable") end)
      assertEqual(NS.Schema:Get(ENABLED), true, "/lh enable must still turn the addon on")
    end)

    NS.Panel.Open = realOpen
    for k in pairs(NS.db.global) do NS.db.global[k] = nil end
    for k, v in pairs(saved) do NS.db.global[k] = v end
    if not ok then error(err, 0) end
    setEnabled(true)
  end)

test("slash-commands-§7 step 7: every FEATURE verb refuses on ONE line and reaches no write seam", function()
  -- The other half of step 7, and the addon's answer to §2's SHOULD pinned so it cannot drift. Both
  -- halves are asserted because either alone is passable by a broken implementation: a case that
  -- only read the line would pass over a verb that printed and then acted anyway.
  bringUp()
  setEnabled(false)
  local realSet, writes = NS.Schema.Set, 0
  NS.Schema.Set = function(...) writes = writes + 1; return realSet(...) end
  local ok, err = pcall(function()
    for _, verb in ipairs(FEATURE) do
      local out = capture(function() NS.Slash:OnSlash(verb) end)
      assertEqual(#out, 1, "/lh " .. verb .. " must answer on exactly ONE line, got: "
        .. table.concat(out, " | "))
      assertEqual(out[1], NS.PREFIX .. " " .. NS.Slash.DisabledLine(),
        "the refusal is the collection's one line, not a wording of this addon's")
    end
  end)
  NS.Schema.Set = realSet
  if not ok then error(err, 0) end
  assertEqual(writes, 0, "a refused feature verb reached the write seam")
  setEnabled(true)
end)

test("slash-commands-§7 step 7: the live set the COMMANDS table gates on IS the library's own", function()
  -- The restatement in settings/Schema.lua exists because that table is built at file load, before
  -- the library is resolved, and because it has to gate the library-LESS dispatcher too. This is
  -- what stops the copy drifting from `lib.LIVE_VERBS` — in particular back to v2.56.0's narrowed
  -- `{ enable, help, disable }`, which is what Slash minor 12 shipped and minor 13 reversed.
  local lib = M.LibStub("LibKa0s-Slash-1.0", true)
  assertTrue(lib ~= nil and type(lib.LIVE_VERBS) == "table", "the library must publish LIVE_VERBS")
  local libSet = setOf(lib.LIVE_VERBS)
  for _, verb in ipairs(RESERVED) do
    assertTrue(libSet[verb] ~= nil, "the library's live set is missing " .. verb)
  end
  assertEqual(#lib.LIVE_VERBS, #RESERVED, "the two sets must be the same thirteen verbs")
  for _, verb in ipairs(FEATURE) do
    assertTrue(libSet[verb] == nil, verb .. " is a feature verb and must not be on the live set")
  end
end)

test("slash-commands-§7 step 7: both diagnostics forms write a full report while stood down", function()
  -- debug-logging-§14: a disabled addon is the one a player is most likely to be reporting, so the
  -- report runs from the stand-down itself, not from a flag this case set. It reads state only, so
  -- the registration set it leaves is the stood-down one.
  bringUp()
  setEnabled(false)
  local D = NS.DebugLog
  local before = regSet()
  local ok, err = pcall(function()
    for _, form in ipairs({ "diagnostics", "debug diagnostics" }) do
      local mark = #D.buffer
      -- red under: `diagnostics` left off LIVE_WHILE_DISABLED, which turns the row into a feature
      -- verb and prints the refusal line instead; or a debug handler that refuses while disabled.
      capture(function() NS.Slash:OnSlash(form) end)
      local began, ended
      for i = mark + 1, #D.buffer do
        if D.buffer[i]:find("Ka0s Loot History diagnostics begin", 1, true) then began = i end
        if D.buffer[i]:find("Ka0s Loot History diagnostics end:", 1, true) then ended = i end
      end
      assertTrue(began ~= nil and ended ~= nil and ended > began, "/lh " .. form .. " wrote a whole report")
      -- red under: a capture section that prints the (empty) wiring of a stood-down addon.
      local says
      for i = began, ended do
        if D.buffer[i]:find("capture: stood down", 1, true) then says = true end
      end
      assertTrue(says, "/lh " .. form .. ": the capture section says the addon is stood down")
    end
    assertEqual(table.concat(regSet(), ","), table.concat(before, ","),
      "the report registered something on a stood-down addon")
  end)
  setEnabled(true)
  if not ok then error(err, 0) end
end)

-- ── 8. the launcher ───────────────────────────────────────────────────────────────────────────

test("slash-commands-§7 step 8: the left click opens the panel and writes nothing; the menu grays every feature",
  function()
    -- launcher-§2 (standard v2.67.0, Launcher minor 4). The left button opens the settings panel in
    -- either state -- the panel is setup, and where the addon is switched back on -- so it prints no
    -- refusal. The right button opens the options menu, where Enabled stays live and Locked, Test
    -- mode and Show window are grayed with "enable the addon first": features refuse while off, and
    -- a grayed entry calls no handler and writes nothing, even when a client dispatches it anyway.
    bringUp()
    local object = NS.Launcher and NS.Launcher:Object()
    assertTrue(object ~= nil, "tests/test_launcher.lua runs first and leaves the object registered")
    setEnabled(false)

    local realToggle, toggles = NS.Browser.Toggle, 0
    local realOpen, opens = NS.Panel.Open, 0
    NS.Browser.Toggle = function() toggles = toggles + 1 end
    NS.Panel.Open = function() opens = opens + 1 end
    local MENU = dofile("tests/mock_menu.lua")(M)
    M.__resetSvWrites()

    local out = capture(function() object.OnClick(object, "LeftButton") end)
    local menuOut = capture(function()
      object.OnClick(object, "RightButton")
      for _, prefix in ipairs({ "Locked", "Test mode", "Show window" }) do MENU.last:ForceClick(prefix) end
    end)
    MENU.remove()
    NS.Browser.Toggle, NS.Panel.Open = realToggle, realOpen

    assertEqual(#out, 0, "the left click speaks no refusal, got: " .. table.concat(out, " | "))
    assertEqual(opens, 1, "left-click must open the settings panel while disabled")
    assertTrue(MENU.last ~= nil, "right-click must open the options menu while disabled")
    assertTrue(MENU.last:Find("Enabled").enabled, "Enabled is the off switch and stays live")
    for _, prefix in ipairs({ "Locked", "Test mode", "Show window" }) do
      assertEqual(MENU.last:Find(prefix).enabled, false, prefix .. " must be grayed while disabled")
    end
    assertEqual(#menuOut, 0, "a grayed entry prints nothing, got: " .. table.concat(menuOut, " | "))
    assertEqual(toggles, 0, "a grayed Show window must not reach the window")
    assertEqual(#M.__svWrites(), 0, "a launcher click wrote SavedVariables on a disabled addon")
    setEnabled(true)
  end)

-- ── 9. restoration, from CURRENT state ────────────────────────────────────────────────────────

test("slash-commands-§7 step 9: re-enabling restores the registration set, and from the settings as they are NOW",
  function()
    -- performance-§6's restore-from-current-state rule, which §7 applies to this latch in full: the
    -- stand-up rebuilds from the enabled set AS IT IS, never from a snapshot taken when the hold
    -- was acquired, so a setting changed while the addon was off comes back correctly.
    bringUp()
    local R_on = regSet()
    setEnabled(false)
    setEnabled(true)
    assertEqual(missing(R_on, regSet()), "", "these registrations did not come back")
    assertEqual(#regSet(), #R_on, "the rebuilt set is a different size from the one that went down")
    assertEqual(missing(OWNED, liveOn(featureTargets())), "",
      "and every registration this addon owns is among them")

    -- The same cycle with ONE setting changed while the addon is down. `visibility` is the one this
    -- addon can be asked about directly: it IS the show ladder's other rung, so an addon rebuilt
    -- from a stale snapshot answers the old value here.
    local before = NS.Schema:Get("settings.visibility")
    setEnabled(false)
    NS.Schema:Set("settings.visibility", "never")
    setEnabled(true)
    assertFalse(NS.Browser:VisibilityAllows(),
      "the stand-up read a snapshot rather than the setting as it is now")
    NS.Schema:Set("settings.visibility", before)
    assertTrue(NS.Browser:VisibilityAllows(), "and it follows the setting back")
  end)

-- ── 10. the latch ─────────────────────────────────────────────────────────────────────────────

test("slash-commands-§7 step 10: releasing ONE hold does not resurrect an addon the other is still holding down",
  function()
    -- The trap, and the whole reason `LibKa0s-Lifecycle-1.0` is a hold set rather than a boolean.
    -- `/lh disable` is a live verb, so a player can switch the addon off DURING a suspended perf
    -- arm; `/lh enable` is live too. A resume that called a bare StandUp would bring the addon back
    -- mid-capture and silently ruin the run.
    --
    -- This addon declines LibKa0s-Perf (performance-§12), so nothing in it takes the `perf` hold
    -- today. The invariant is the latch's rather than the addon's, and it is driven here directly
    -- so that arming the harness later is a registration and not a rewrite.
    -- red under: an `enable` path that calls NS.StandUp() directly instead of releasing the hold,
    -- or a perf resume that does — either one stands the addon up under a player who switched it
    -- off, and the registration set below comes back non-empty.
    bringUp()
    local lc, targets = NS.Lifecycle, featureTargets()
    local function down(why) assertEqual(table.concat(liveOn(targets), ", "), "", why) end
    local function up(why) assertEqual(missing(OWNED, liveOn(featureTargets())), "", why) end

    -- perf first, then disabled.
    lc:Hold(NS.HOLD_PERF)
    down("taking the perf hold must stand the addon down")
    setEnabled(false)
    lc:Release(NS.HOLD_PERF)
    down("releasing perf resurrected an addon the player had disabled")
    assertTrue(lc:IsHeld(NS.HOLD_DISABLED), "the disabled hold is still taken")
    setEnabled(true)
    up("the last hold released, the addon stands up")

    -- and the other order.
    targets = featureTargets()
    setEnabled(false)
    lc:Hold(NS.HOLD_PERF)
    setEnabled(true)
    down("enabling resurrected an addon the perf harness was holding down")
    assertEqual(table.concat(lc:Holds(), ","), NS.HOLD_PERF, "only the perf hold is left")
    lc:Release(NS.HOLD_PERF)
    up("the last hold released, the addon stands up")
    assertEqual(#lc:Holds(), 0, "no hold outlives this case")
  end)

test("slash-commands-§7: the latch persists NOTHING, and the stored switch is the only thing that does",
  function()
    -- The `perf` hold is session-only and the `disabled` hold is re-taken at load from the stored
    -- enable path, which is why the latch itself writes nothing: a hold persisted across a reload
    -- would leave a player's addon dead with no visible cause.
    bringUp()
    M.__resetSvWrites()
    NS.Lifecycle:Hold(NS.HOLD_PERF)
    NS.Lifecycle:Release(NS.HOLD_PERF)
    local paths = {}
    for _, w in ipairs(M.__svWrites()) do paths[#paths + 1] = w.path end
    assertEqual(table.concat(paths, ", "), "", "the latch wrote to SavedVariables")
  end)

