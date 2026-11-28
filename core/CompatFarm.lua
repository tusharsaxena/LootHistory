local _, NS = ...
-- core/CompatFarm.lua — the farm session's client reads (#39, farm spec
-- docs/superpowers/specs/2026-11-27-39-farm-mode-design.md §11.6): every source GUID of a loot slot,
-- the player's AFK flag, a quest's title, and the logout-family hook installer. Its own file so
-- core/Compat.lua and its split siblings stay under their layout-§1 re-check; the rules are
-- core/Compat.lua's: globals read bare at call time, never captured at load; a secret is never
-- compared, concatenated or indexed; a missing API answers its documented absent value, never a raise.
--
-- LOAD-BEARING POSITION: in the compat family (below core/CompatClient.lua, whose IsSecret every
-- member here asks at call time, and below core/CompatGain.lua) and straight before
-- core/SimSeam.lua, which wraps every NS.Compat member at file load and classes HookLogoutFamily
-- PURE; below the seam these members would escape it.

NS.Compat = NS.Compat or {}
local Compat = NS.Compat

-- One loot slot's GUIDs, written into `out` from index 1. GetLootSourceInfo answers
-- guid1, qty1, guid2, qty2, ...: an AoE loot slot carries one pair per corpse.
local function writeGUIDs(out, ...)
  local k = 0
  for i = 1, select("#", ...), 2 do
    local guid = select(i, ...)
    if guid ~= nil then
      k = k + 1
      out[k] = guid
    end
  end
  return k
end

--- Every source GUID of loot slot `slot`, written into `out[1..k]`; the tail a previous call left
--- is wiped. Answers k (0 when the API is absent or the slot has no source). A GUID may be a secret:
--- the caller asks Compat.IsSecret before it decodes one.
function Compat.LootSourceGUIDs(slot, out)
  local k = 0
  if type(GetLootSourceInfo) == "function" then k = writeGUIDs(out, GetLootSourceInfo(slot)) end
  for i = #out, k + 1, -1 do out[i] = nil end
  return k
end

--- UnitIsAFK("player") as a plain boolean; nil when the API is absent or the answer is a secret or
--- not a boolean (the caller then changes nothing).
function Compat.IsPlayerAFK()
  if type(UnitIsAFK) ~= "function" then return nil end
  local afk = UnitIsAFK("player")
  if Compat.IsSecret(afk) or type(afk) ~= "boolean" then return nil end
  return afk
end

--- C_QuestLog.GetTitleForQuestID(questID) when it is a plain non-empty string, else nil (both
--- clients carry it, per the kit's client lists).
function Compat.QuestTitle(questID)
  local QL = C_QuestLog
  if not (questID and QL and QL.GetTitleForQuestID) then return nil end
  local title = QL.GetTitleForQuestID(questID)
  if Compat.IsSecret(title) or type(title) ~= "string" or title == "" then return nil end
  return title
end

-- The logout family (farm spec §5.4): the calls that mean "this character is leaving" and the ones
-- that take it back. A reload is a cancel: the session survives it.
local INTENT = { "Logout", "Quit", "ForceQuit" }
local CANCEL = { "CancelLogout", "ReloadUI" }

--- PURE (an installer, never simulated): post-hooks `Logout`, `Quit` and `ForceQuit` with
--- `onIntent`, and `CancelLogout`, `ReloadUI` and `C_UI.Reload` with `onCancel`, each through
--- Compat.HookSecure / HookSecureMember (presence-gated; there is no un-hook, so each body gates
--- itself on NS.IsStoodDown). Answers how many were installed.
function Compat.HookLogoutFamily(onIntent, onCancel)
  local n = 0
  for _, name in ipairs(INTENT) do
    if Compat.HookSecure(name, onIntent) then n = n + 1 end
  end
  for _, name in ipairs(CANCEL) do
    if Compat.HookSecure(name, onCancel) then n = n + 1 end
  end
  if Compat.HookSecureMember(C_UI, "Reload", onCancel) then n = n + 1 end
  return n
end
