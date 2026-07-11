local addonName, NS = ...

local AceAddon = LibStub("AceAddon-3.0")
local addon = AceAddon:NewAddon(NS, addonName, "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")
NS.addon = addon
NS.bus = addon   -- closed message bus: SendMessage / RegisterMessage

function addon:OnInitialize()
  NS:InitDB()
  NS:RunMigrations()
  if NS.Schema and NS.Schema.Register then NS.Schema:Register() end
  if NS.Slash and NS.Slash.Register then NS.Slash:Register() end
  if NS.Panel and NS.Panel.Register then NS.Panel:Register() end
end

function addon:OnEnable()
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnterWorld")
  if NS.Attribution and NS.Attribution.Enable then NS.Attribution:Enable() end
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
