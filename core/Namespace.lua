local addonName, NS = ...

-- Shared namespace bootstrap. Runs early so common metadata exists regardless of load order.
NS.name = addonName
NS.version = "0.1.0"

-- Modules publish themselves idempotently (`NS.X = NS.X or {}`); nothing to wire here yet.
