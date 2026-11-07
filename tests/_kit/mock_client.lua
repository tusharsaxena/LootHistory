-- testkit/mock_client.lua -- the kit's client profiles: which game client the mock set pretends to be.
--
-- There are exactly two. `retail` is the default and is the LIVE Retail shape: `WOW_PROJECT_ID` is
-- 1 (`WOW_PROJECT_MAINLINE`) and `WOW_PROJECT_CAMELOT` is nil, because the constant does not exist
-- on Retail. `forever` is WoW Forever (client 1.60.1, build 70790, interface 16001), where
-- `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT == 18`.
--
-- A third "neither constant exists" client is deliberately NOT a profile. A case that wants it sets
-- the mocks directly, so the unusual shape is visible in the case that needs it.
--
-- `Loader` applies the profile once to every mock set it builds an environment for, so a suite sees
-- the profile without asking. `KA0S_KIT_CLIENT=forever lua tests/run.lua` runs the whole suite
-- under Forever; an unknown value raises rather than falling back to retail, because a typo that
-- silently ran the default would report green for a profile that never ran.

local MockClient = {}

local PROFILES = {
  retail = {
    consts = { WOW_PROJECT_ID = 1, WOW_PROJECT_MAINLINE = 1, WOW_PROJECT_CAMELOT = false },
    build  = { "12.1.5", "70783", "Nov  3 2026", 120105 },
    absent = { "SetDesaturation" },
  },
  forever = {
    consts = { WOW_PROJECT_ID = 18, WOW_PROJECT_MAINLINE = 1, WOW_PROJECT_CAMELOT = 18 },
    build  = { "1.60.1", "70790", "Nov  3 2026", 16001 },
    absent = { "GetSpecialization", "GetSpecializationInfo", "GetActiveSpecGroup", "GetTalentInfo",
               "SetDesaturation" },
  },
}

local active

local function resolve(name)
  name = name or os.getenv("KA0S_KIT_CLIENT") or "retail"
  if not PROFILES[name] then
    error('MockClient: unknown client profile "' .. tostring(name) .. '" (expected "retail" or "forever")', 3)
  end
  return name
end

--- Stamp the profile `name` (default: `KA0S_KIT_CLIENT`, else "retail") onto the mock set `mocks`.
--- Returns the resolved name. An unknown name raises.
function MockClient.apply(mocks, name)
  name = resolve(name)
  local profile = PROFILES[name]
  for key, value in pairs(profile.consts) do
    if value == false then mocks[key] = nil else mocks[key] = value end
  end
  local build = profile.build
  mocks.GetBuildInfo = function() return build[1], build[2], build[3], build[4] end
  for _, key in ipairs(profile.absent) do mocks[key] = nil end
  active = name
  return name
end

--- The profile last applied, or the one a fresh apply would choose. "retail" | "forever".
function MockClient.current()
  return active or resolve(nil)
end

return MockClient
