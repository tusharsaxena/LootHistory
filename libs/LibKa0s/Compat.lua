-- LibKa0s-Compat-1.0 -- the version-variant client readers two or more Ka0s addons wrote the same
-- way, and the secret-value seam every one of them has to ask before it compares.
--
-- -- WHY THIS EXISTS ---------------------------------------------------------------------------
--
-- Nine addons carry a `core/Compat.lua` and two of them also carry a `core/Secrets.lua`. Most of
-- that is honestly addon-specific. What is not is a small set of two-rung ladders over APIs
-- Blizzard has already moved once -- `C_Spell` in 11.0,
-- `C_SpecializationInfo` in 12.0 -- plus the three questions 12.0's secrets system forces on every
-- guard: is this value secret, may this context look at it, may it be a table key. Those shapes
-- were written two to four times each, and the copies drifted in the ways copies do: two addons read
-- the deprecated `GetSpellInfo` global's rank as the icon, one compared a possibly-secret spell name
-- with "" (a raise in combat), one read a legacy `isEnabled` of 0 as enabled. This major is the one
-- copy, with the drift resolved in writing.
--
-- -- WHY IT IS NARROW --------------------------------------------------------------------------
--
-- Nine members, not the union of nine files. `LibKa0s/Env.lua` records that the WIDE extraction was
-- measured and rejected, and that record stays true: a container reader is BankLedger's, a mail
-- decoder is LootHistory's, and a damage-meter reader is MultiMeters'. A member is here only when
-- two or more addons have a PRODUCTION caller for it and every copy agrees on what the right answer
-- is (library-stack-§7). What was looked at and left out, and why, is the rejection record below and
-- in docs/api/Compat/version-1-docs.md, "What is not here":
--
--   * consumers DISAGREE about correctness: spell known/available (WhatGroup's namespaced answer
--     is final, KickCD's ladder is either-says-yes); cast info (KickCD overrides
--     notInterruptible for a unit the player cannot attack, PartyFrameEnhanced does not); a secret
--     boolean handed to a C-side setter (gated in one addon, deliberately ungated in another); a
--     GCD-floored cooldown remainder (WhatGroup policy, built on GetSpellCooldown here); the item
--     resolver (already recorded by LibKa0s-Item-1.0: one host guesses, one refuses);
--   * two consumers but no content: the StatusBar interpolation enum read and the numeric rule
--     formatter constructor are each one presence guard -- the optional-object-guard shape
--     library-stack-§7 names as what NOT to promote;
--   * one consumer: everything else in the nine files.
--
-- -- THE RULES EVERY MEMBER OBEYS --------------------------------------------------------------
--
--   1. Globals are read BARE and at CALL time. Never through an explicit global-table lookup and
--      never captured into an upvalue at load. The headless kit resolves a bare name through its
--      mock first, so a suite can remove a rung after load and watch the ladder move; an explicit
--      global-table lookup steps around the mock and tests a client nobody runs.
--   2. Namespaced rung first, deprecated global second, the member's documented no-answer value
--      last. "Absent" is the house presence test `ns and ns.fn`.
--   3. The first rung that EXISTS is authoritative -- a nil from it is the answer -- for every
--      reader but GetSpellName, where the first rung that ANSWERS wins. Two rungs reading the same
--      spell data can only disagree about presence, so falling through cannot hide a disagreement.
--   4. A value that may be secret is returned untouched. The only operations performed on a client
--      value are type(), truthiness of a timing (legal on a secret number; only a secret BOOLEAN may
--      not be tested), a comparison ONLY after IsSecret has said no, and the two plain-boolean
--      cooldown flags inherited unchanged from the copies.
--   5. Spell members take a number or a string (the client's own spellIdentifier domain). Any
--      other type, nil included, answers the no-answer value without calling a single rung.
--   6. No pcall. A client defect raises where it happens instead of reading as silence.
--   7. Arity is exact (every member but GetSpecializationInfo, which is the client's passthrough),
--      so a caller spreading a result into the last argument of a C call never forwards a stray.
--
-- -- DEGRADATION: TWO KINDS OF MEMBER, TWO STUB RULES --------------------------------------------
--
-- A host resolves this with LibStub("LibKa0s-Compat-1.0", true) and needs a stand-in when it is
-- absent. The library cannot ship that stand-in -- it would live in the payload that is absent.
--
--   * READERS (GetSpellInfo .. GetSpecializationInfo): the stub answers the ALL-RUNGS-ABSENT value
--     (nil, or 0, 0, false, 1, false). Every caller already handles those, because they are the
--     documented contract. A stub that re-implemented the top rung would re-create the duplication.
--   * GUARDS (IsSecret, CanAccess, IsSafeKey): the stub MUST re-implement the three-line body. "The
--     library is absent" is not "the client has no secrets system": a stub answering IsSecret ->
--     false on a 12.x client sends a secret into a comparison and raises in combat, on exactly the
--     degraded path the stub exists to survive. That copy is a deliberate, documented duplication
--     and carries a comment at the host saying so.
--
-- Internal calls go through file locals, never back through `lib.X`: the table is shared by every
-- addon that loaded this copy, and one host monkeypatching `lib.IsSecret` must not change what
-- another host's GetSpellName answers.
--
-- Depends on LibStub and LibKa0s-Core-1.0, and on no addon framework. No Core member is called --
-- the gate is there so that a host holding a partial payload gets every module absent rather than
-- a working half. Core's IsConcatSafe / SafeToString answer a DIFFERENT question (will
-- table.concat take this value) and stay the rendering path; the guards here decide comparability.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Compat-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.Compat = MINOR

-- -- the secret seam ---------------------------------------------------------------------------

--- Whether `v` is a secret value. False on a client without the secrets system.
local function isSecret(v)
  local fn = issecretvalue
  if not fn then return false end
  return fn(v) and true or false
end

--- Whether `v` is a secret value.
---
--- The client's own test, normalized to a boolean. On a client that predates 12.0 nothing is ever
--- secret, so the answer is false rather than an error about a nil global. Any value is accepted,
--- nil included.
---
--- @param v any
--- @return boolean
function lib.IsSecret(v)
  return isSecret(v)
end

--- Whether the current execution context may look at `v` -- the question that decides whether a
--- comparison or arithmetic on it is legal.
---
--- Distinct from IsSecret: a value can be secret and still accessible. `canaccessvalue` is asked
--- where it exists; without it the answer is "accessible unless known secret", and with neither
--- global every value is accessible.
---
--- @param v any
--- @return boolean
function lib.CanAccess(v)
  local fn = canaccessvalue
  if fn then return fn(v) and true or false end
  return not isSecret(v)
end

--- Whether `v` may be used as a TABLE KEY right now.
---
--- IsSecret and NOT CanAccess, on purpose: the key restriction is about the value being secret at
--- all, not about whether this context may read it, and those two answers differ. nil is never a
--- key. The secret test runs FIRST so no secret ever meets a comparison, even with nil; the answer
--- is identical to the copies' `v == nil` first ordering on every input.
---
--- @param v any
--- @return boolean
function lib.IsSafeKey(v)
  if isSecret(v) then return false end
  return v ~= nil
end

-- -- spells --------------------------------------------------------------------------------------

--- Whether `id` is in the client's spellIdentifier domain (an id, a name or a link). type() is
--- legal on a secret, so this guard is secret-safe.
local function isSpellId(id)
  local t = type(id)
  return t == "number" or t == "string"
end

--- Basic spell info: `name, iconID, castTime, minRange, maxRange, spellID` (exactly six values), or
--- a single nil.
---
--- `C_Spell.GetSpellInfo`'s table is flattened in that order and is authoritative -- a nil table
--- is the answer. Where only the deprecated global exists it is REMAPPED from its real shape,
--- `name, rank, icon, castTime, minRange, maxRange, spellID`: the rank is dropped, because reading it
--- as the icon is the defect two of the copies shipped.
---
--- @param id number|string
--- @return string|nil name, number iconID, number castTime, number minRange, number maxRange, number spellID
function lib.GetSpellInfo(id)
  if not isSpellId(id) then return nil end
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(id)
    if not info then return nil end
    return info.name, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID
  end
  if GetSpellInfo then
    local name, _, icon, castTime, minRange, maxRange, spellID = GetSpellInfo(id)
    if not name then return nil end
    return name, icon, castTime, minRange, maxRange, spellID
  end
  return nil
end

--- Whether a name rung has answered: a secret (returned untouched, and it ends the ladder) or a
--- plain non-empty string. IsSecret is asked BEFORE the comparison with "", because comparing a
--- secret raises in combat.
local function nameAnswers(n)
  if isSecret(n) then return true end
  return type(n) == "string" and n ~= ""
end

--- A spell's localized name, or nil (exactly one value; it may be a secret string).
---
--- Three rungs, and the first one that ANSWERS wins: `C_Spell.GetSpellName`, then the name field of
--- `C_Spell.GetSpellInfo`, then the deprecated global's first return. nil or a plain "" from a rung
--- falls through to the next. This is the one reader where fall-through is right: every rung reads
--- the same spell data, so they can disagree only about whether the data is there yet.
---
--- @param id number|string
--- @return string|nil
function lib.GetSpellName(id)
  if not isSpellId(id) then return nil end
  if C_Spell and C_Spell.GetSpellName then
    local n = C_Spell.GetSpellName(id)
    if nameAnswers(n) then return n end
  end
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(id)
    local n = info and info.name
    if nameAnswers(n) then return n end
  end
  if GetSpellInfo then
    local n = GetSpellInfo(id)
    if nameAnswers(n) then return n end
  end
  return nil
end

--- The file id of a spell's icon, or nil (exactly one value).
---
--- `C_Spell.GetSpellTexture` is authoritative where it exists; its second return (the original icon)
--- is dropped so the result can be spread straight into SetTexture.
---
--- @param id number|string
--- @return number|nil
function lib.GetSpellTexture(id)
  if not isSpellId(id) then return nil end
  if C_Spell and C_Spell.GetSpellTexture then
    return (C_Spell.GetSpellTexture(id))
  end
  if GetSpellTexture then
    return (GetSpellTexture(id))
  end
  return nil
end

--- A spell's cooldown: `startTime, duration, isEnabled, modRate, isActive` -- ALWAYS five values.
---
--- `startTime`, `duration` and `modRate` may be secret in combat. They are returned untouched: pass
--- them to a C-side setter (Cooldown:SetCooldown) or gate with IsSecret before any arithmetic.
--- `isActive` is the plain boolean to decide "is it on cooldown" with.
---
--- The legacy global has no isActive; it is derived from duration, and only after IsSecret has said
--- the duration is plain. Its `isEnabled` historically answered 1 or 0, and 0 reads DISABLED here
--- (nil still reads enabled). No rung at all, a nil info table, and an identifier outside the
--- domain all answer the inert tuple `0, 0, false, 1, false`.
---
--- @param id number|string
--- @return number startTime, number duration, boolean isEnabled, number modRate, boolean isActive
function lib.GetSpellCooldown(id)
  if not isSpellId(id) then return 0, 0, false, 1, false end
  if C_Spell and C_Spell.GetSpellCooldown then
    local info = C_Spell.GetSpellCooldown(id)
    if not info then return 0, 0, false, 1, false end
    return info.startTime or 0,
           info.duration or 0,
           info.isEnabled ~= false,
           info.modRate or 1,
           info.isActive == true
  end
  if GetSpellCooldown then
    local s, d, e, m = GetSpellCooldown(id)
    local active = type(d) == "number" and not isSecret(d) and d > 0
    return s or 0, d or 0, (e ~= false and e ~= 0), m or 1, active
  end
  return 0, 0, false, 1, false
end

-- -- specialization ----------------------------------------------------------------------------

--- The player's active specialization index, or nil (exactly one value).
---
--- `C_SpecializationInfo.GetSpecialization` is authoritative where it exists; the deprecated global
--- where it does not.
---
--- @return number|nil
function lib.GetSpecialization()
  if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
    return (C_SpecializationInfo.GetSpecialization())
  end
  if GetSpecialization then
    return (GetSpecialization())
  end
  return nil
end

--- Specialization info for a spec index: the rung's OWN returns, unmodified and variable in count
--- (on the client `specID, name, description, icon, role, primaryStat, ...`), or a single nil.
---
--- The one member whose arity is not fixed: every copy passed the multi-return through and the
--- callers read positions one and two, so fixing an arity here would invent a contract nobody asked
--- for. A nil or false index answers nil without calling the client with it.
---
--- @param index number
--- @return any ...
function lib.GetSpecializationInfo(index)
  if not index then return nil end
  if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
    return C_SpecializationInfo.GetSpecializationInfo(index)
  end
  if GetSpecializationInfo then
    return GetSpecializationInfo(index)
  end
  return nil
end
