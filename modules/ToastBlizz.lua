local _, NS = ...
NS.ToastBlizz = NS.ToastBlizz or {}
local TB = NS.ToastBlizz
local C = NS.Constants

-- Hiding Blizzard's own loot and money alert toasts (#38, toast spec
-- docs/superpowers/specs/2026-11-27-38-loot-toasts-design.md §10.2; D14, D25). Off by default
-- (`settings.toasts.hideAlerts`), and fully restored on disable: the switch off, the gain feed off
-- (no feed enabled) or the addon stood down all re-register exactly the events this file took away,
-- in the order it took them. Chat-line hiding is out of scope (D25).
--
-- TAINT: no Blizzard function is replaced and no Blizzard table is written. AlertFrame's
-- UnregisterEvent / RegisterEvent are frame method calls, which store no addon value on the frame
-- (docs/ARCHITECTURE.md Taint notes cites AlertFrame and each event on both clients). Both go through
-- core/CompatGain.lua's presence-gated members, so a client without AlertFrame, or without one of the
-- events registered, suppresses nothing and raises nothing.
--
-- Reads NS.GainFeed, NS.Compat and the profile at call time only.

TB._suppressed = TB._suppressed or {}   -- the event names suppressed now, in order

local function wanted()
  local s = NS.db and NS.db.profile and NS.db.profile.settings
  local on = s and s.toasts and s.toasts.hideAlerts == true
  return on and TB._up == true and NS.GainFeed ~= nil and NS.GainFeed.on == true
end

--- Suppress or restore, as the switch and the gain feed say. Idempotent: called from Enable, from
--- GainFeed:Recompute (every `toasts`, `profile` and `enabled` write) and from Disable.
function TB.Apply()
  local list = TB._suppressed
  if wanted() then
    if #list == 0 then NS.Compat.SuppressAlertEvents(C.BLIZZ_ALERT_EVENTS, list) end
  elseif #list > 0 then
    NS.Compat.RestoreAlertEvents(list)
  end
  return #list
end

--- Stand-up (core/LifecycleSetup.lua, after Toasts).
function TB:Enable()
  if not NS.addon then return end
  self._up = true
  self.Apply()
end

--- Stand-down (the first step after SimStop): the alerts back while everything else is still up.
function TB:Disable()
  self._up = nil
  self.Apply()
end
