local addonName, NS = ...

-- Canonical locale. Metatable fallback returns the key itself, so English strings work
-- untranslated and missing keys never error. Non-enUS files gate with GetLocale().
NS.L = setmetatable(NS.L or {}, { __index = function(_, k) return k end })
local L = NS.L

-- Keys are the English source strings; only overrides need listing.
-- L["Enable collection"] = "Enable collection"
