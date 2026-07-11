local addonName, NS = ...
NS.Panel = NS.Panel or {}
local P = NS.Panel
local categoryID

-- Blizzard Settings canvas entry point. Body is built lazily on first OnShow (Milestone 5).
function P:Register()
  if categoryID then return end
  if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
  local frame = CreateFrame("Frame")
  frame.OnCommit = function() end
  frame.OnDefault = function() if NS.Schema.CliResetAll then NS.Slash:CliResetAll() end end
  frame.OnRefresh = function() end
  local category = Settings.RegisterCanvasLayoutCategory(frame, "Ka0s Loot History")
  category.ID = addonName
  Settings.RegisterAddOnCategory(category)
  categoryID = category:GetID()
  frame:SetScript("OnShow", function() P:BuildBody(frame) end)
end

function P:BuildBody(frame)
  if frame.__built then return end
  frame.__built = true
  -- Full AceGUI options body is built in Milestone 5.
end

function P:Open()
  if InCombatLockdown and InCombatLockdown() then
    print("|cff33ff99" .. addonName .. "|r Can't open settings in combat.")
    return
  end
  if Settings and Settings.OpenToCategory and categoryID then
    Settings.OpenToCategory(categoryID)
  end
end
