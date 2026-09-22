local addonName, NS = ...

-- Shared namespace bootstrap. Runs early so common metadata exists regardless of load order.
NS.name = addonName
NS.version = "1.3.0"

-- THE BRAND NAME, in plain text, and it is one string because it is read from three places that
-- must agree: the LDB object's `label`, which a broker display prints beside ten others
-- (launcher-§1); the Slash descriptor's `brandName`; and through that, the one refusal line a
-- disabled addon prints (slash-commands-§7). Deliberately NOT the TOC `## Title` -- a Title may
-- carry color escapes and this string is dropped into a colored line, so it MUST NOT contain an
-- escape sequence of any kind. Not the folder name either: `LootHistory` is an identifier.
NS.BRAND = "Ka0s Loot History"

-- Shared chat tag. Cyan (00ffff) is the Ka0s Standard house color (slash-commands-§4) — every
-- Ka0s addon prints the same cyan bracketed tag so a user running several recognizes them at a
-- glance. MUST NOT be substituted with another color.
NS.PREFIX = "|cff00ffff[LH]|r"

-- Modules publish themselves idempotently (`NS.X = NS.X or {}`); nothing to wire here yet.
