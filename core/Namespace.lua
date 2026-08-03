local addonName, NS = ...

-- Shared namespace bootstrap. Runs early so common metadata exists regardless of load order.
NS.name = addonName
NS.version = "1.2.0"

-- Shared chat tag. Cyan (00ffff) is the Ka0s Standard house color (slash-commands-§4) — every
-- Ka0s addon prints the same cyan bracketed tag so a user running several recognizes them at a
-- glance. MUST NOT be substituted with another color.
NS.PREFIX = "|cff00ffff[LH]|r"

-- Modules publish themselves idempotently (`NS.X = NS.X or {}`); nothing to wire here yet.
