-- LibKa0s-Env-1.0 — the handful of client facts every Ka0s addon reads, read one way.
--
-- ── WHY THIS EXISTS ──────────────────────────────────────────────────────────────────────────
--
-- `GetAddOnMetadata` was written ELEVEN times across nine addons before this module. Six copies
-- sat in a `core/Compat.lua`, in four different spellings — two-space and four-space indent, the
-- parameter called `field` and `key`, globals reached bare and through `_G.` — and the other five
-- were the same six-line ladder inlined at the call site, invisible to anyone auditing the shim
-- files. Not one of the eleven behaved differently from any other.
--
-- That is the whole case. There is no addon-specific behavior here to descriptor-ise and no
-- plausible future in which one host needs a different answer, which is what separates this from
-- the `Compat` extraction that was tested against the evidence and rejected: a container reader is
-- BankLedger's, a mail decoder is LootHistory's, and this is nobody's.
--
-- ── WHY Version IS A MEMBER AND NOT A CALL SITE'S PROBLEM ────────────────────────────────────
--
-- Because the eleven call sites overwhelmingly want one thing — the addon's own version, for an
-- About page, a slash banner or a perf descriptor — and they spelled the fallback nine different
-- ways getting it (`or NS.version or "?"`, `or NS.VERSION`, `or ""`). A bare metadata passthrough
-- would have preserved every one of those spellings. The fallback stays VISIBLE at the call site,
-- as an argument, because which constant an addon falls back to is genuinely its own business.
--
-- ── WHY IT TAKES AN ADDON NAME ───────────────────────────────────────────────────────────────
--
-- Same reason `LibKa0s-Media-1.0` does: this library is VENDORED, so there is no one path to it
-- and a copy cannot know which addon folder it was copied into. `...` carries the addon name only
-- for a file the TOC loads directly, and `LibKa0s.xml` is loaded from inside `libs/`. The host has
-- its name verbatim as the first vararg of every file it loads, so it passes it.
--
-- Depends on LibStub and LibKa0s-Core-1.0, and on no addon framework. No Core member is called —
-- the gate is there so that a host holding a partial payload gets every module absent rather than
-- a working half, and "is LibKa0s here?" stays one question.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Env-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.Env = MINOR

-- ── the TOC manifest ─────────────────────────────────────────────────────────────────────

--- One field of an addon's TOC manifest, or nil.
---
--- The reader moved under `C_AddOns` in 10.x and the bare global is deprecated but still present,
--- so both rungs are live: the namespaced one wherever it exists, the global where it does not,
--- and nil where neither does. Nil is a real answer — a field the TOC does not carry answers nil
--- on a perfectly healthy client — so a caller that needs a value supplies its own.
---
--- @param addonName string  the addon FOLDER name, from the host's first vararg
--- @param field string      a TOC key: "Version", "Title", "Notes", "Author", …
--- @return string|nil
function lib.GetAddOnMetadata(addonName, field)
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    return C_AddOns.GetAddOnMetadata(addonName, field)
  end
  if GetAddOnMetadata then
    return GetAddOnMetadata(addonName, field)
  end
  return nil
end

--- An addon's own version string.
---
--- Prefers the TOC, because that is what the packager stamped; `fallback` is what the host had
--- before this module and is usually a constant somebody has to remember to edit. Returning the
--- constant in preference would make a correctly packaged addon report a stale number.
---
--- @param addonName string
--- @param fallback string|nil  the host's own constant, used only when the TOC cannot be read
--- @return string|nil
function lib.Version(addonName, fallback)
  local v = lib.GetAddOnMetadata(addonName, "Version")
  if v ~= nil and v ~= "" then return v end
  return fallback
end

-- ── where the player is ──────────────────────────────────────────────────────────────────

--- The player's current UI map id, or nil.
---
--- Best-effort by design: a map id is a stamp on a stored record, and a record with no map id is
--- worth more than a raise during a zone transition.
---
--- @return number|nil
function lib.GetPlayerMapID()
  if C_Map and C_Map.GetBestMapForUnit then
    return C_Map.GetBestMapForUnit("player")
  end
  return nil
end

--- The player's zone and subzone labels.
---
--- ALWAYS TWO STRINGS, and `""` rather than nil is the contract rather than an accident. Consumers
--- bucket `""` with nil deliberately in storage and in their zone filters, and they wrote that
--- decision down; a library that "improved" this to nil would silently move stored rows between
--- buckets on the first re-render after an upgrade.
---
--- @return string zone, string subzone
function lib.GetZone()
  local zone = (GetZoneText and GetZoneText()) or ""
  local subzone = (GetSubZoneText and GetSubZoneText()) or ""
  return zone, subzone
end
