local addonName, NS = ...

local AceAddon = LibStub("AceAddon-3.0")
local addon = AceAddon:NewAddon(NS, addonName, "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")
NS.addon = addon
NS.bus = addon   -- closed message bus: SendMessage / RegisterMessage

-- Reclaim NS.Print from AceConsole. NewAddon(NS, …, "AceConsole-3.0") embeds AceConsole's mixins
-- directly onto NS, and its :Print method OVERWRITES the secret-safe, cyan-[LH]-prefixed NS.Print
-- defined in core/Util.lua — after which every `local print = NS.Print` call site would render
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
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  if LSM then LSM:Register("font", "JetBrains Mono", NS.Constants.FONT_MONO) end
  NS:InitDB()
  if NS.Schema and NS.Schema.Register then NS.Schema:Register() end
  if NS.Slash and NS.Slash.Register then NS.Slash:Register() end
  if NS.Panel and NS.Panel.Register then NS.Panel:Register() end
end

function addon:OnEnable()
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnterWorld")
  if NS.Attribution and NS.Attribution.Enable then NS.Attribution:Enable() end
  if NS.Collector and NS.Collector.Enable then NS.Collector:Enable() end
  if NS.Browser and NS.Browser.Enable then NS.Browser:Enable() end
  if NS.State.debug and NS.Debug then NS.Debug("Init", "%s", NS.BootSummary()) end
end

-- Retention cleanup runs once per session, deferred off the login/zone spike.
function addon:OnEnterWorld()
  if NS.State.cleanupDone then return end
  NS.State.cleanupDone = true
  if C_Timer and C_Timer.After then
    C_Timer.After(5, function()
      if NS.Database and NS.Database.PruneOld then NS.Database:PruneOld() end
    end)
  end
end
