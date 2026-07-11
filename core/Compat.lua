local addonName, NS = ...
NS.Compat = NS.Compat or {}
local Compat = NS.Compat

-- Flavor flags. The only place WOW_PROJECT_ID is read; feature code branches on these.
Compat.IsRetail  = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
Compat.IsClassic = (WOW_PROJECT_ID == WOW_PROJECT_CLASSIC)

-- Best-effort current map id for the player (nil if unavailable).
function Compat.GetPlayerMapID()
  if C_Map and C_Map.GetBestMapForUnit then
    return C_Map.GetBestMapForUnit("player")
  end
  return nil
end

-- GUID type + npcID decode and item-info shims land here in Milestone 1.
