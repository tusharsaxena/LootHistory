local addonName, NS = ...

-- core/EnvSetup.lua — wires the addon into LibKa0s-Env-1.0 (library-stack-§7).
--
-- The seam where `/lh version` and the where-am-I stamp on every stored loot row come from.
--
-- ── WHAT THIS REPLACED ───────────────────────────────────────────────────────────────────────
--
-- Three shims out of core/Compat.lua: the map-id read, the zone read and the TOC-metadata reader.
-- The metadata one had been written ELEVEN times across nine addons before the library had it — six
-- copies in a core/Compat.lua in four different spellings, and five more inlined at the call site
-- where no audit of the shim files would ever have found them. Not one of the eleven behaved
-- differently from any other, and the map/zone pair here was byte-identical to BankLedger's. That
-- sameness is the whole case: it is what makes these the library's business rather than this
-- addon's, and it is why Compat KEEPS the rest of its surface — the loot and quest hooks, the mail
-- and GUID decoders, the quality/bind cluster and the currency readers, which are genuinely this
-- addon's and behave like nobody else's.
--
-- ── WHY THE LIBRARY HAS TO BE TOLD OUR NAME ──────────────────────────────────────────────────
--
-- Same reason core/MediaSetup.lua passes it: LibKa0s is VENDORED, so a copy cannot know which addon
-- folder it sits in. `addonName` is the FIRST VARARG every TOC-loaded file gets — not the `## Title`
-- and not a hand-typed literal. Here those read "LootHistory" and "Ka0s Loot History", and only the
-- first is the folder. A wrong name reads some other addon's manifest, or none at all, and answers
-- nil without raising a thing.
--
-- ── WHY THE FALLBACKS ARE WRITTEN OUT RATHER THAN LEFT TO ANSWER nil ─────────────────────────
--
-- Because this is a seam, not a feature. An install missing LibKa0s must get exactly what this
-- addon got before the library existed: every helper below repeats the ladder its deleted shim ran,
-- minus the pre-C_AddOns metadata rung no admitted client can reach (see NS.Meta), so such an
-- install still reads its own TOC and still stamps its own zone. Nothing here is
-- resolved at load beyond the LibStub lookup, so this file's TOC position is conventional — it sits
-- next to core/Compat.lua, whose shims it took over.
--
-- ── WHAT THE SEAM MUST NOT CHANGE ────────────────────────────────────────────────────────────
--
-- Any answer. All three shims already agreed with the library rung for rung, so a difference in
-- what comes back here is a defect in the adoption rather than an improvement — most sharply for
-- NS.Zone, whose "" is load-bearing (see its own note). tests/test_envsetup.lua pins all of it.
--
-- The map and zone ladders live in core/Compat.lua again, as Compat.PlayerMapID / Compat.Zone (still
-- Env-first), because LibKa0s-Sim-1.0's answer seam wraps Compat members and reaches nothing else
-- (LootHistory#37). NS.PlayerMapID / NS.Zone stay here as call-time forwarders, so no caller moved.

local Env = LibStub and LibStub("LibKa0s-Env-1.0", true)

--- One field of this addon's TOC manifest, or nil.
---
--- NIL IS A REAL ANSWER, twice over: the library may be absent AND the client may expose no reader
--- at all, which is exactly what a headless run looks like. A field the TOC does not carry also
--- answers nil on a perfectly healthy client. Callers that need a value supply their own.
---
--- Two rungs: the library, then `C_AddOns.GetAddOnMetadata`. There is deliberately no third rung
--- on the bare global `GetAddOnMetadata`: every client this addon's `## Interface` admits serves the
--- manifest through C_AddOns only, so that rung could never reach a working call, and compat
--- (standard v2.65.0) says a dead rung is deleted rather than shimmed. tests/test_envsetup.lua pins
--- that a stray global is not consulted.
---
--- @param field string  a TOC key: "Version", "Title", "Notes", "Author", …
--- @return string|nil
function NS.Meta(field)
  if Env then return Env.GetAddOnMetadata(addonName, field) end
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    return C_AddOns.GetAddOnMetadata(addonName, field)
  end
  return nil
end

--- This addon's version string, preferring the TOC over the fallback constant. Never nil.
---
--- The fallback stays visible HERE rather than inside the library because which constant this addon
--- falls back to is genuinely its own business — and because a packaged addon whose TOC can be read
--- should never report the constant somebody forgot to edit (slash-commands-§3).
---
--- `NS.version` is read at CALL time, not captured as an upvalue: core/Namespace.lua publishes it
--- and loads after this file.
---
--- @return string
function NS.Version()
  if Env then return Env.Version(addonName, NS.version) or "?" end
  return NS.Meta("Version") or NS.version or "?"
end

--- The player's current UI map id, or nil. A call-time forwarder to NS.Compat.PlayerMapID, which
--- holds the Env-then-C_Map ladder so LibKa0s-Sim-1.0's answer seam can reach it (LootHistory#37).
--- Best-effort by design: modules/Collector.lua stores whatever this answers.
---
--- @return number|nil
function NS.PlayerMapID()
  return NS.Compat.PlayerMapID()
end

--- Zone and subzone. ALWAYS two strings; "" when the client has no text yet. A call-time forwarder
--- to NS.Compat.Zone, which holds the ladder and documents why the "" is load-bearing
--- (core/Database.lua:944 and the Browser's Zone column bucket it with nil).
---
--- @return string zone, string subzone
function NS.Zone()
  return NS.Compat.Zone()
end
