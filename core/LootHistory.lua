local addonName, NS = ...

local AceAddon = LibStub("AceAddon-3.0")
local addon = AceAddon:NewAddon(NS, addonName, "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")
NS.addon = addon
NS.bus = addon   -- closed message bus: SendMessage / RegisterMessage

-- Reclaim NS.Print from AceConsole. NewAddon(NS, …, "AceConsole-3.0") embeds AceConsole's mixins
-- directly onto NS, and its :Print method OVERWRITES the secret-safe, cyan-[LH]-prefixed NS.Print
-- published by core/CoreSetup.lua — after which every `local print = NS.Print` call site would render
-- AceConsole's green "|cff33ff99<msg>|r:" form (no tag, trailing colon) and lose secret-safety. The
-- embed never touches NS.Util.print, so restore the real printer from it (architecture-§2).
if NS.Util and NS.Util.print then NS.Print = NS.Util.print end

-- Bus-receiver factory. A module that CONSUMES Ka0s_LootHistory_* messages must register on its
-- OWN AceEvent target, never on the shared bus-as-self: CallbackHandler keys callbacks by
-- (message, target), so two consumers that share a target silently clobber each other — only the
-- last registrant of a given message ever receives it. Each call returns a fresh AceEvent-embedded
-- table (nil if AceEvent is unavailable); SendMessage on NS.bus still fans out to every target.
function NS.NewBusTarget()
  local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
  if not AceEvent then return nil end
  local t = {}
  AceEvent:Embed(t)
  return t
end

function addon:OnInitialize()
  -- The LibSharedMedia registration that used to sit here is gone: core/MediaSetup.lua does it at
  -- FILE LOAD through the library, which is where it belonged. This ran at ADDON_LOADED, after
  -- core/Constants.lua had already resolved a path and settings/Schema.lua had already built rows
  -- naming the face -- a window in which a stored default named a font LSM had not yet heard of.
  NS:InitDB()
  -- The "Keep history for" confirm's baseline: the stored retention is the confirmed one.
  if NS.Schema and NS.Schema.SyncRetention then NS.Schema:SyncRetention() end
  if NS.Schema and NS.Schema.Register then NS.Schema:Register() end
  if NS.Slash and NS.Slash.Register then NS.Slash:Register() end
  if NS.Panel and NS.Panel.Register then NS.Panel:Register() end
  -- AFTER NS:InitDB, and that is the whole of the ordering: the launcher hands LibDBIcon
  -- `db.global.minimap` at this moment (launcher-§3), and the table does not exist before InitDB.
  -- Idempotent by the library's own design, so a second call from a login handler would build no
  -- second button; there is only this one.
  if NS.Launcher then NS.Launcher:Register() end
  -- AFTER NS:InitDB, which is what makes `NS.db` exist to register callbacks on. AceDB's profile
  -- callbacks are one of the things a disabled addon KEEPS (slash-commands-§7): a profile switch
  -- can flip the stored enable path with no verb and no checkbox touched, and the latch has to
  -- re-evaluate when it does.
  NS.BindLifecycle()
end

-- ── the profile events: ONE adopt path (savedvariables-§1, debug-logging-§10) ─────────────────
--
-- A switch, a copy and a reset all land here through NS.BindLifecycle (core/LifecycleSetup.lua).
-- Each one hands the addon a profile it has not seen yet, so each one does the same four things, in
-- this order:
--
--   1. Migrations. None: every MIGRATIONS step runs on the account-wide store at load, before any
--      profile is read, and no step is profile-scoped (core/Database.lua). A profile created later
--      is born in today's shape, so there is nothing to carry it through.
--   2. The latch. `settings.enabled` is profile-scoped, so the switch the new profile holds is the
--      one the latch follows, before anything rebuilds against it (slash-commands-§7).
--   3. One line (debug-logging-§10), worded by the event. A reset and a copy replace the profile's
--      rows wholesale, so each is one [Set] line and no bulk bracket adds a second; a switch
--      rewrites no row and is the [Profile] trace.
--   4. Every setting's effect, re-applied: the History window (geometry, saved view, chrome,
--      visibility, row height), the Collector's upvalues through NS.Schema:AdoptProfile (the one
--      SettingsChanged message), and every open settings panel.
--
-- What this path NEVER does is touch the loot history (owner decision D6). The history and the
-- retention that prunes it are account-wide, outside every profile, so no event here counts,
-- confirms or prunes a record; the only prune is the login one in addon:OnEnterWorld below.

local function currentProfile()
  return (NS.db and NS.db.GetCurrentProfile and NS.db:GetCurrentProfile()) or "?"
end

--- The one line. The reset count is TAKEN whatever the debug state, so a count never outlives its
--- reset, and taking it is also what tells an open bulk bracket that this act reset the profile.
local function traceProfileEvent(event, source)
  local R = NS.SchemaRuntime
  local count = event == "OnProfileReset" and R and R.ConsumeResetCount and R.ConsumeResetCount() or nil
  if not (NS.State.debug and NS.Debug) then return end
  if event == "OnProfileReset" and count then
    NS.Debug("Set", "reset profile '%s' to defaults (%d rows)", currentProfile(), count)
  elseif event == "OnProfileReset" then
    NS.Debug("Set", "reset profile '%s' to defaults", currentProfile())
  elseif event == "OnProfileCopied" then
    NS.Debug("Set", "copied profile '%s' \226\134\146 '%s'", tostring(source), currentProfile())
  else
    NS.Debug("Profile", "switched to profile '%s'", currentProfile())
  end
end

--- `key` is AceDB's third argument: the profile switched TO, or the SOURCE of a copy; nil on a reset.
function NS.OnProfileEvent(event, key)
  NS.OnEnabledChanged()
  traceProfileEvent(event, key)
  if NS.Browser and NS.Browser.AdoptProfile then NS.Browser:AdoptProfile() end
  -- The one SettingsChanged("profile") every setting's reactor already listens to
  -- (docs/message-bus.md). Through the Schema module, the message's one sender.
  if NS.Schema and NS.Schema.AdoptProfile then NS.Schema:AdoptProfile() end
  -- STRUCTURAL: the Filters tab's lists and the AH Price table are drawn off the profile's tables.
  if NS.Options and NS.Options.RefreshAllPanels then NS.Options.RefreshAllPanels() end
end

--- Come up, and then take the stored hold if the player has this addon switched off.
---
--- TWO CALLS, IN THIS ORDER, and the order is the contract rather than a style. `NS.StandUp` is the
--- ONE place the registrations live -- the same function the latch calls on the way back up -- so
--- the load path and the checkbox path can never build different addons. `Set` then re-reads the
--- stored switch: on an enabled install the hold set stays empty and nothing else happens, and on a
--- disabled one the latch fires the edge and `NS.StandDown` takes back down what this just built.
--- Building and immediately tearing down looks wasteful and is the cheap half of the trade -- the
--- alternative is a second, load-only spelling of "what does this addon register", which is exactly
--- the parallel mechanism anti-patterns #85 names.
---
--- Never `NS.Lifecycle:Release(...)` here, and never a bare stand-up: the only route out of the
--- disabled state is releasing the hold that caused it.
function addon:OnEnable()
  NS.StandUp()
  NS.Lifecycle:Set(NS.HOLD_DISABLED, NS.AddonIsOff())
  -- No [Init] line here: the debug flag is session-only and off at login, so a boot-time summary
  -- would always be gated off and never render. It rides the DebugLog:SetEnabled seam instead,
  -- emitted when capture is actually enabled (debug-logging-§5/§8).
end

-- Retention cleanup runs once per session, deferred off the login/zone spike. The warbound-state
-- repair rides the same deferral and then runs again a little later: it needs the item cache, which
-- is cold at login, and the first pass is what warms it (see Database:RepairBoundStates).
function addon:OnEnterWorld()
  if NS.State.cleanupDone then return end
  NS.State.cleanupDone = true
  -- THROUGH NS.After, NOT C_Timer.After, and that is not a refactor for tidiness. Both of these
  -- are SavedVariables writes on a fuse lit by a game event, and `C_Timer.After` cannot be put out:
  -- a player who switched the addon off inside those first five seconds got the retention prune
  -- anyway, from a game event, while it was disabled -- the exact shape slash-commands-§7 forbids.
  -- NS.CancelDeferrals, which NS.StandDown calls, reaches these handles.
  NS.After(5, function()
    if NS.Database and NS.Database.PruneOld then NS.Database:PruneOld() end
    if NS.Database and NS.Database.RepairBoundStates then NS.Database:RepairBoundStates() end
    -- The Timeline's rollup: seed once (holdings that predate it), then prune by its own retention.
    -- After the 3 s login scan, so the seed reads this login's holdings.
    if NS.Rollup and NS.Rollup._hook then
      NS.Rollup:SeedOnce(time())
      NS.Rollup:Prune(time())
    end
  end)
  NS.After(20, function()
    if NS.Database and NS.Database.RepairBoundStates then NS.Database:RepairBoundStates() end
  end)
  -- Holdings genesis / login scan (timeline-ledger spec §5.6). Three seconds in, after the item
  -- cache has had a moment; cancelable through NS.CancelDeferrals like the prune.
  NS.After(3, function()
    if NS.Reconciler and NS.Reconciler._enabled then NS.Reconciler:LoginScan() end
  end)
  -- One-time reset recommendation (spec 9.2); in combat it holds for PLAYER_REGEN_ENABLED.
  NS.After(5, function() if NS.OfferLedgerReset then NS.OfferLedgerReset() end end)
end
