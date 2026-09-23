local _, NS = ...

-- LibKa0s-Lifecycle-1.0 seam: ONE latch, many reasons to be inert (slash-commands-§7).
--
-- ── WHAT THIS IS FOR ──────────────────────────────────────────────────────────────────────────
--
-- "Disabled" used to be a DRAW GATE in this addon, and in the ten beside it: `settings.enabled`
-- was one upvalue modules/Collector.lua read at the top of OnChatMsgLoot, and everything else
-- carried on exactly as before. CHAT_MSG_LOOT stayed registered, so the client still walked the
-- registration list on every loot line in the raid, still built the argument frame, still entered
-- Lua, and still ran the comparison that decided to leave. The addon had not stopped watching --
-- it had stopped reacting -- and the dispatch it went on paying is precisely what a player
-- switching it off is trying to stop paying. The owner rejected that shape in those words
-- (anti-patterns #85), and slash-commands-§7 is the numbered MUST that replaced it.
--
-- ── WHY A LATCH AND NOT A BOOLEAN ─────────────────────────────────────────────────────────────
--
-- There is more than one reason to be inert, and the interesting state is the one a boolean cannot
-- hold: two of them at once. Releasing the perf harness's hold on an addon the PLAYER has switched
-- off must not bring it back to life under them, and a `disable` that stands the addon up on its
-- way past must not end a capture. So both are named HOLDS on one latch: stood down while at least
-- one hold is taken, stood up only when the last is released. There is deliberately no StandUp
-- member on the library instance -- a bare stand-up is the bug the latch exists to prevent.
--
-- THIS ADDON TAKES ONE HOLD TODAY. It declines LibKa0s-Perf (performance-§12, recorded in
-- ARCHITECTURE.md -> Documented deviations), so nothing here ever takes `perf`. The key is still
-- published and the latch still honors it, because the invariant is the library's and not this
-- addon's: tests/test_disabled.lua drives both holds through it, and the day the harness is armed
-- the wiring is a registration rather than a rewrite.
--
-- ── WHAT STANDS DOWN, AND WHAT DOES NOT ───────────────────────────────────────────────────────
--
-- Down: every event this addon registered (the AceAddon target's own, the three modules' private
-- bus targets, Attribution's per-unit spell frame), every deferred timer it owns, and every frame
-- it draws -- refused AT THE SOURCE, in NS.Browser's own show ladder, because a frame hidden
-- imperatively comes back on the next combat transition or settings change.
--
-- Up, because it is SETUP and not a feature: the chat command and the dispatcher, NS.COMMANDS,
-- the settings categories and the panel body, the AceDB handle and its profile callbacks, and the
-- launcher's registration. Without those, `/lh enable` would not exist and the switch would only
-- go one way.
--
-- The one carve-out on the teardown side is `hooksecurefunc`, which has no un-hook: the three
-- merchant/mail hooks and the two in core/Compat.lua gate their own bodies instead, at
-- NS.Attribution:Stamp, which is the single funnel every one of them lands in.

local Lifecycle = LibStub and LibStub("LibKa0s-Lifecycle-1.0", true)

-- ── cancelable deferrals ─────────────────────────────────────────────────────────────────────
--
-- `C_Timer.After` cannot be canceled, and slash-commands-§7 asks for every timer CANCELED rather
-- than left armed to wake up and find a flag. So every deferral this addon owns goes through here:
-- a `C_Timer.NewTimer` handle where the client has one, tracked in a live set, and dropped on the
-- way down. The retention prune is the case that made this load-bearing -- it is a SavedVariables
-- write on a five-second fuse lit by PLAYER_ENTERING_WORLD, and a player who switched the addon
-- off in those five seconds got the write anyway, from a game event, while it was disabled.
local live = {}

--- Defer `fn` by `delay` seconds, cancellably. Returns the handle, or nil when the deferral ran
--- straight through (headless, or a client too old for C_Timer).
function NS.After(delay, fn)
  if not (C_Timer and C_Timer.After) then fn(); return nil end
  local h = {}
  local function body()
    live[h] = nil
    if h.canceled then return end
    fn()
  end
  if C_Timer.NewTimer then h.timer = C_Timer.NewTimer(delay, body) else C_Timer.After(delay, body) end
  live[h] = true
  return h
end

--- Drop every deferral still waiting. Both halves matter: the flag stops a `C_Timer.After` fallback
--- body that is already queued, and `Cancel` takes the handle out of the client's own ticker list
--- so nothing is left to wake up at all.
function NS.CancelDeferrals()
  for h in pairs(live) do
    h.canceled = true
    if h.timer and h.timer.Cancel then h.timer:Cancel() end
    live[h] = nil
  end
end

-- ── the two host callbacks ────────────────────────────────────────────────────────────────────

--- Tear the addon down to setup. Idempotent: every module guards its own teardown, so this is safe
--- on an addon that never came up (the load path calls it when the stored switch is already off).
function NS.StandDown()
  -- The AceAddon target's OWN registrations -- PLAYER_ENTERING_WORLD plus the two Collector and
  -- seven Attribution events that register through it. UnregisterAllEvents reaches every one; it
  -- does not touch messages, and this target subscribes to none.
  if NS.addon and NS.addon.UnregisterAllEvents then NS.addon:UnregisterAllEvents() end
  for _, m in ipairs({ NS.Collector, NS.Attribution, NS.Browser, NS.Analytics }) do
    if m and m.Disable then m:Disable() end
  end
  NS.CancelDeferrals()
  -- Hidden here as well as refused in the ladder, and both are needed: the ladder stops the window
  -- coming back, this takes down the one that is already up.
  if NS.CloseMenu then NS.CloseMenu() end
  if NS.Browser and NS.Browser.Hide then NS.Browser:Hide() end
  if NS.Export and NS.Export.Hide then NS.Export:Hide() end
  -- The debug console is a diagnostic surface and `/lh debug` keeps answering while the addon is
  -- off (slash-commands-§7), so this hides the window without gating the verb that reopens it.
  if NS.DebugLog and NS.DebugLog.Hide then NS.DebugLog:Hide() end
end

--- Rebuild FROM CURRENT STATE, never from a snapshot taken on the way down: a setting changed while
--- the addon was off has to be the setting that comes back (performance-§6).
function NS.StandUp()
  if NS.addon and NS.addon.RegisterEvent then
    NS.addon:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnterWorld")
  end
  if NS.Attribution and NS.Attribution.Enable then NS.Attribution:Enable() end
  if NS.Collector and NS.Collector.Enable then NS.Collector:Enable() end
  if NS.Browser and NS.Browser.Enable then NS.Browser:Enable() end
  if NS.Analytics and NS.Analytics.Enable then NS.Analytics:Enable() end
end

-- ── the latch ─────────────────────────────────────────────────────────────────────────────────

if Lifecycle then
  NS.HOLD_DISABLED = Lifecycle.HOLD_DISABLED
  NS.HOLD_PERF     = Lifecycle.HOLD_PERF
  NS.Lifecycle = Lifecycle:New({
    name      = "LootHistory",
    standDown = function() NS.StandDown() end,
    standUp   = function() NS.StandUp() end,
    -- Late-bound like every other seam's: core/LootHistory.lua reclaims NS.Print from AceConsole
    -- after this file has run.
    print     = function(line) NS.Print(line) end,
  })
else
  -- Degrade, not error, and not by absence either. Every caller below reaches the latch on the
  -- ordinary enable/disable path, so an absent one would leave the switch doing nothing at all --
  -- which is the one failure mode worse than the draw gate this file replaced. The stand-in is the
  -- hold SET and the two edges, which is the whole of the contract this addon uses; it is not a
  -- second teardown path, because it drives the same NS.StandDown and NS.StandUp.
  NS.HOLD_DISABLED, NS.HOLD_PERF = "disabled", "perf"
  local held, down = {}, false
  local function edge()
    local any = next(held) ~= nil
    if any == down then return false end
    down = any
    if any then NS.StandDown() else NS.StandUp() end
    return true
  end
  NS.Lifecycle = {
    name = "LootHistory",
    Hold       = function(_, key) held[key] = true; return edge() end,
    Release    = function(_, key) held[key] = nil; return edge() end,
    Set        = function(self, key, v) if v then return self:Hold(key) else return self:Release(key) end end,
    IsHeld     = function(_, key) return held[key] == true end,
    IsDown     = function() return down end,
    Reevaluate = function() return edge() end,
    Holds      = function()
      local out = {}
      for k in pairs(held) do out[#out + 1] = k end
      table.sort(out)
      return out
    end,
    PrintHolds = function() return false end,
  }
end

--- Is the addon standing down -- for ANY reason. The show ladder and the launcher ask this; the
--- slash gate asks NS.AddonIsOff instead, because a perf capture is not a reason to refuse a verb.
function NS.IsStoodDown()
  return NS.Lifecycle and NS.Lifecycle:IsDown() or false
end

--- The stored enable path, read through the Schema READ seam so the verbs, the Master controls
--- checkbox and this can never answer from two places. Guarded because the table exists only after
--- NS:InitDB, and a read before that is not a disabled addon -- it is an unbuilt one.
function NS.AddonIsOff()
  if not (NS.db and NS.db.global and NS.Schema) then return false end
  return NS.Schema:Get("settings.enabled") == false
end

--- The one place the stored switch reaches the latch. The Master controls checkbox's onChange, the
--- `enable` / `disable` verbs (which are that same write by its long name) and the profile
--- callbacks all land here, so there is exactly one branch and nobody writes it backwards.
function NS.OnEnabledChanged()
  NS.Lifecycle:Set(NS.HOLD_DISABLED, NS.AddonIsOff())
end

--- AceDB's profile callbacks can flip the stored path with no verb and no checkbox touched, so the
--- latch re-reads it and re-evaluates. This addon stores everything in `global` and declares no
--- `profile` section at all (docs/schema.md), so the callbacks are a belt slash-commands-§7 asks
--- for rather than a live path here -- but they are the cheap half of "a profile switch can flip
--- `enabled`", and an addon that grows a profile later inherits the wiring rather than the bug.
function NS.BindLifecycle()
  local db = NS.db
  if not (db and db.RegisterCallback) then return false end
  local function onProfile()
    NS.Lifecycle:Set(NS.HOLD_DISABLED, NS.AddonIsOff())
    NS.Lifecycle:Reevaluate()
  end
  db.RegisterCallback(NS, "OnProfileChanged", onProfile)
  db.RegisterCallback(NS, "OnProfileCopied",  onProfile)
  db.RegisterCallback(NS, "OnProfileReset",   onProfile)
  return true
end
