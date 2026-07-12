local addonName, NS = ...

-- Canonical locale. Metatable fallback returns the key itself, so English strings work
-- untranslated and missing keys never error. Non-enUS files gate with GetLocale().
NS.L = setmetatable(NS.L or {}, { __index = function(_, k) return k end })

-- v1.0.0 ships English-only: no user-facing string routes through NS.L yet — every label,
-- tooltip and message is hardcoded English (an accepted scope decision, not an oversight). The
-- NS.L seam is kept so a future localization pass can wrap strings (`NS.L["Enable collection"]`)
-- and drop enUS overrides here without touching call sites. There is deliberately no `local L`
-- alias until the first string is wrapped, so this file stays luacheck-clean.
--
-- Keys are the English source strings; only overrides need listing, e.g.:
-- NS.L["Enable collection"] = "Enable collection"
