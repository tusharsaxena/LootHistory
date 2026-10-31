-- LibKa0s-Skin-1.0 — owner tokens: an addon's own named colors (or any token value), registered with
-- `RegisterOwner(owner, { tokens = ... })` and laid over the owner's table in `__Tokens`, and the
-- slot remap a primitive's `opts.tokens` asks for (`__Remap`, `__RemapName`).
--
-- Peeled out of Skin.lua at its minor 11, unchanged (LK-M2-PEEL of Ka0sAddonsCommonTasks
-- docs/2026-10-31-FINDINGS_REMEDIATION), on the seam CLAUDE.md's band census named for that file:
-- the block has the clearest boundary in the engine. The history is Skin.lua's header (minor 7).
--
-- WHO CALLS IN. Skin.lua's RegisterOwner calls `lib.__takeTokens`, and its `__Tokens` calls
-- `lib.__withOwnTokens`; SkinPaint.lua's P.remap calls `lib:__Remap`. Skin.lua hands over the three
-- locals this file shares with it, `lib.__tokenHelpers`. Nothing else crosses the cut. A copy
-- without this file takes no owner token, and Skin.lua's one-line `__Remap` leaves every slot as it was.
--
-- A file of `LibKa0s-Skin-1.0` rather than a major of its own, paired on the shell's minor as
-- SkinDefs.lua is, so a block from one vendored copy never attaches to an engine from another.

local lib = LibStub and LibStub("LibKa0s-Skin-1.0", true)
if not lib then return end   -- the shell refused (no Core, or below its floor): nothing to attach to

-- Minor 1: the owner-token block, moved here unchanged from Skin.lua (its minor 11).
local TOKENS_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own: see SkinDefs.lua.
if lib.__tokensMinor and lib.__tokensMinor >= TOKENS_MINOR
  and lib.__tokensShellMinor == lib.MINOR then return end
lib.__tokensMinor      = TOKENS_MINOR
lib.__tokensShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.SkinOwnerTokens = TOKENS_MINOR

local MAJOR = lib.MAJOR
local kindOf, overlay, report = lib.__tokenHelpers.kindOf, lib.__tokenHelpers.overlay, lib.__tokenHelpers.report

-- ── taking them (minor 7) ───────────────────────────────────────────────────────────────────

--- True when `name` is a library token (a `lib.SCHEMA` name). With no SkinDefs.lua loaded nothing is.
local function isSchemaName(name)
  local idx = lib.__schemaIndex
  return idx ~= nil and idx[name] ~= nil
end

--- True when `ns` (a name's first dotted segment) is a library token family (`text`, `sem`,
--- `gtip`, ...: the first segment of any `lib.SCHEMA` name), so a later SkinDefs minor may add a
--- library token under it. The set is built once per schema index.
local function isFamily(ns)
  local idx = lib.__schemaIndex
  if idx == nil then return false end
  if lib.__famFrom ~= idx then
    local fam = {}
    for n in pairs(idx) do fam[n:match("^[^%.]+")] = true end
    lib.__fam, lib.__famFrom = fam, idx
  end
  return lib.__fam[ns] == true
end

--- Why `name` cannot be an owner token's name, or nil: it needs a dot inside it, and its namespace
--- is never a library token family, so no later library token can take it.
local function nameProblem(name)
  if type(name) ~= "string" or not name:find("^[^%.].*%.") or name:sub(-1) == "." then
    return "a name carries the owner's namespace and a dot (\"dw.upgrade\")"
  end
  local ns = name:match("^[^%.]+")
  if isSchemaName(name) or isFamily(ns) then return "its namespace, " .. ns .. ", is a library token family" end
  return nil
end

-- The Lua type a schema kind's value has.
local KIND_TYPE = { color = "table", colors = "table", string = "string", number = "number", bool = "boolean" }

--- Why `def` cannot be an owner token's definition, or nil. A `follow` token's kind must agree
--- with the default's type (a color never follows `font.body`).
local function defProblem(def)
  if type(def) ~= "table" then return "the definition is not a table { default, follow, skins }" end
  if def.default == nil then return "it has no default (Ka0s Default's value)" end
  local follow = def.follow
  if follow ~= nil and not (type(follow) == "string" and (lib.__schemaIndex == nil or isSchemaName(follow))) then
    return "follow names no library token"
  end
  local want = follow and KIND_TYPE[kindOf(follow)]
  if want and want ~= type(def.default) then
    return "follow is a " .. kindOf(follow) .. " token and the default a " .. type(def.default)
  end
  if def.skins ~= nil and type(def.skins) ~= "table" then return "skins is not a table" end
  return nil
end

--- Why owner token `name` with definition `def` cannot be taken, or nil when it can.
local function tokenProblem(name, def)
  return nameProblem(name) or defProblem(def)
end

--- Refuse owner token `name` and log it once per owner and name: through the owner's `opts.log`
--- when it gave one, else to the client's error handler.
local function refuseToken(o, owner, name, why, verb)
  local seen = lib.__tokRefused[owner] or {}
  lib.__tokRefused[owner] = seen
  local key = tostring(name)
  if seen[key] then return end
  seen[key] = why
  local line = MAJOR .. ": " .. owner .. " token " .. key .. " " .. (verb or "refused") .. ": " .. why
  if type(o.log) ~= "function" then return report(line) end
  local ok, err = pcall(o.log, line)
  if not ok then report(err) end
end

--- A definition's `skins` as taken: an entry whose value's type is not the default's is refused
--- (logged once, the rest kept); a key no registered skin carries is kept, for a skin registered
--- later, and logged once, since it is most often a misspelling.
local function takeSkins(o, owner, name, def)
  if def.skins == nil then return nil end
  local out, want = {}, type(def.default)
  for k, v in pairs(def.skins) do
    local at = name .. ".skins." .. tostring(k)
    if v ~= false and type(v) ~= want then
      refuseToken(o, owner, at, "the value is a " .. type(v) .. " and the default a " .. want)
    else
      if not lib.skins[k] then refuseToken(o, owner, at, "no registered skin has this key", "kept") end
      out[k] = v
    end
  end
  return out
end

--- Take a registration's owner tokens onto the record: each good name added or replaced, each bad
--- one refused. Nothing when `tokens` is not a table.
function lib.__takeTokens(o, owner, tokens)
  if type(tokens) ~= "table" then return end
  o.tokens = o.tokens or {}
  for name, def in pairs(tokens) do
    local why = tokenProblem(name, def)
    if why then
      refuseToken(o, owner, name, why)
    else
      o.tokens[name] = { default = def.default, follow = def.follow, skins = takeSkins(o, owner, name, def) }
    end
  end
  o.tokGen = (o.tokGen or 0) + 1
end

--- True when `name` names a token `owner` can read: a library token, or one of the owner's own
--- tokens. Anything else (a name no token carries, or a value where a name belongs) answers false,
--- logged once per owner, `where` and name (opts.log, else the client's error handler). The question
--- a primitive's `opts.tokens` remap asks of each slot (SkinPaint minor 11). Internal.
function lib:__RemapName(owner, name, where)
  local o = self.owners[owner]
  if type(name) == "string" then
    if self.__schemaIndex == nil or isSchemaName(name) then return true end
    if o and o.tokens and o.tokens[name] then return true end
  end
  if o then
    local label = tostring(where) .. " " .. (type(name) == "string" and name or "<" .. type(name) .. ">")
    refuseToken(o, owner, label, "the remap names no token (a library or owner token NAME)")
  end
  return false
end

--- One owner token's value under `key` (a skin key, or "eui"), reading the follow token from `t`.
--- Ka0s Default answers the default, unless the owner's font or texture override moved the follow
--- token (`t` against the un-overridden `base`): then the override; a skin its own entry (`false` is
--- none, unless the token is a bool); otherwise, and always under eui, the follow token's value,
--- else the default.
local function ownValue(def, key, t, base)
  if key == lib.DEFAULT then
    local f = def.follow and t[def.follow]
    if f ~= nil and f ~= base[def.follow] then return f end
    return def.default
  end
  local v
  if key ~= "eui" and def.skins then v = def.skins[key] end
  if v ~= nil and v ~= false then return v end
  if v == false then
    if type(def.default) == "boolean" then return false end
    return nil
  end
  local f = def.follow and t[def.follow]
  if f ~= nil then return f end
  return def.default
end

--- `t` with `owner`'s owner tokens over it (minor 7): `t` itself when the owner registered none,
--- else a derived copy cached on (t, key, the owner's token generation). `base` is `t` without the
--- overrides.
function lib.__withOwnTokens(owner, t, key, base)
  local o = lib.owners[owner]
  local own = o and o.tokens
  if not own or next(own) == nil then return t end
  local c = lib.__ownTok[owner]
  if c and c.from == t and c.key == key and c.gen == o.tokGen then return c.t end
  local out = {}
  overlay(out, t)
  for name, def in pairs(own) do out[name] = ownValue(def, key, t, base) end
  lib.__ownTok[owner] = { from = t, key = key, gen = o.tokGen, t = out }
  return out
end

-- A remapped slot whose named token resolves to nil: the view answers nil, not the primitive's own.
local NONE = {}

local function orNone(v) if v == nil then return NONE end return v end

--- `T` seen through a caller's slot remap (LK-02; SkinPaint minor 11's P.remap): `tokens` is the
--- caller's `opts.tokens`, `{ [slot] = token name }`; `slots` maps each slot the primitive has to the
--- library token it paints from; `fills` names the slots that are fills, whose `<token>Top` /
--- `<token>Bottom` gradient pair follows the named token's (none when it has none). A slot whose
--- name is not a token the owner can read, or whose token is not a color (`bar.texture`), is left
--- as it was and logged once (`__RemapName`, from `where`). Answers `T` itself when nothing is remapped, else a read-only view over it. Internal.
function lib:__Remap(owner, T, tokens, slots, fills, where)
  if type(tokens) ~= "table" or next(tokens) == nil then return T end
  local ov
  for slot, target in pairs(slots) do
    local name = tokens[slot]
    local at = tostring(where) .. "." .. slot
    local ok = name ~= nil and self:__RemapName(owner, name, at)
    local v = ok and T[name]
    if ok and v ~= nil and type(v) ~= "table" then   -- a string, number or bool token: no color
      local o = self.owners[owner]
      if o then refuseToken(o, owner, at .. " " .. name, "the remap names a " .. type(v) .. " token, not a color") end
    elseif ok then
      ov = ov or {}
      ov[target] = orNone(T[name])
      if fills and fills[slot] then
        ov[target .. "Top"], ov[target .. "Bottom"] = orNone(T[name .. "Top"]), orNone(T[name .. "Bottom"])
      end
    end
  end
  if not ov then return T end
  return setmetatable({}, { __index = function(_, k)
    local v = ov[k]
    if v == NONE then return nil end
    if v ~= nil then return v end
    return T[k]
  end })
end
