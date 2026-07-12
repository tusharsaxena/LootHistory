local addonName, NS = ...

-- Shared namespace bootstrap. Runs early so common metadata exists regardless of load order.
NS.name = addonName
NS.version = "1.1.0"

-- Chat prefix: short bracketed tag (Ka0s standard §7.4). One shared constant so every
-- module prints identically. Green accent is Loot History's identity.
NS.PREFIX = "|cff33ff99[LH]|r"

-- Modules publish themselves idempotently (`NS.X = NS.X or {}`); nothing to wire here yet.
