local _, NS = ...

-- Canonical locale. Metatable fallback returns the key itself, so English strings work
-- untranslated and missing keys never error. Non-enUS files gate with GetLocale().
NS.L = setmetatable(NS.L or {}, { __index = function(_, k) return k end })

-- The addon ships English-only and nearly every label, tooltip and message is still hardcoded
-- English (an accepted scope decision, not an oversight). The NS.L seam is kept so a future
-- localization pass can wrap those strings (`NS.L["Enable collection"]`) and drop enUS overrides
-- here without touching call sites.
--
-- Keys are the English source strings; only overrides need listing, e.g.:
-- NS.L["Enable collection"] = "Enable collection"

-- ── the disabled refusal is NOT one of them, and that is the rule rather than an omission ─────
--
-- This file carried `NS.L.SLASH_DISABLED_VERB` until the v1.41.0 adoption. slash-commands-§7 makes
-- the one line a disabled addon prints the COLLECTION's wording and not the addon's -- one shape,
-- built by LibKa0s-Slash-1.0 from the brand name and the slash -- and the library's own descriptor
-- says in as many words that the `L` override does not reach it. Eleven addons each wording it
-- slightly differently is the drift the shared printer exists to end, so the string is gone from
-- here rather than translated here. `NS.Slash.DisabledLine` is where it comes from now.
