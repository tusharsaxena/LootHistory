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

-- ── the strings that DO route through NS.L (localization-§1) ───────────────────────────────────

--- The refusal a FEATURE verb answers with while the addon is disabled (slash-commands-§2). ONE
--- line, and it names `/lh enable`, because a player who has just been told "no" needs the way back
--- in the same breath — a refusal that does not name it is a switch that only goes one way.
--- `%s` is the verb the player typed, so the line says which command did nothing.
NS.L.SLASH_DISABLED_VERB =
  "/lh %s does nothing while the addon is disabled — /lh enable turns it back on."
