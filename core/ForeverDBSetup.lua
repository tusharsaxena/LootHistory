local _, NS = ...

-- core/ForeverDBSetup.lua — wires the addon into LibKa0s-ForeverDB-1.0 (library-stack-§7,
-- WowAddonStandards clients-§11; SF-LH-02, LibKa0s#105).
--
-- ForeverDB is WoW Forever's optional data addon (QuestieDB, VMaNGOS, cMaNGOS and pfQuest merged):
-- who drops an item and how often, who sells it and for how much. This addon reads it for one thing,
-- the History table's item tooltip (modules/ItemSources.lua), and only through the library's major,
-- which is the one place that knows ForeverDB's positional rows and the one place that loads it.
-- Nothing in this addon touches the `ForeverDB` global or calls C_AddOns.LoadAddOn for it.
--
-- OPTIONAL FOR EVERY PLAYER. The TOC lists ForeverDB under `## OptionalDeps` and `.pkgmeta` under
-- `optional-dependencies`, never as required. Without it the addon is unchanged, and the setting's
-- row says the feature needs it.
--
-- ── WHAT A DEGRADED INSTALL GETS ─────────────────────────────────────────────────────────────
--
-- The major's documented stand-in (docs/api/ForeverDB/version-1-docs.md, *Degradation*): every
-- member answers its all-absent value, so `Available()` says "missing" and the tooltip adds nothing.
-- A host does not re-read ForeverDB on its own when the library is absent; that is the library's job.

local FDB = LibStub and LibStub("LibKa0s-ForeverDB-1.0", true)

local function none() return nil end

NS.ForeverDB = FDB or {
  Available     = function() return false, "missing" end,
  IsLoaded      = function() return false end,
  Status        = function() return { present = false, loaded = false } end,
  Meta          = none,
  NPC           = none,
  Item          = none,
  Quest         = none,
  ItemSources   = none,
  VendorPrice   = function() return nil, nil end,
  Spots         = none,
  TrainerSpells = none,
}
