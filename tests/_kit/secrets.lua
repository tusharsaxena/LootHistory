-- testkit/secrets.lua — the shared secret-value simulator (kit revision 38).
--
-- WHY. While WoW 12.0's combat restriction is active, many values the client hands an addon arrive
-- as SECRET VALUES: tainted code may store one, pass it, put it in a table value and hand it to a
-- widget, and may not compare it, do arithmetic on it, concatenate it, index it or call it. A suite
-- that "proves" an addon never inspects a secret proves nothing with a plain number, because a plain
-- number satisfies every assertion a secret would have failed. Every consumer that tested a secret
-- path wrote its own simulator; this is the one the kit ships.
--
-- SURFACE, all on the kit table, all additive:
--
--   Kit.SECRET_ERROR          "secret value", the marker every trap's message carries. Match on it
--                             (Kit.assertErrorMatches) rather than on the whole message.
--   Kit.secret(v)             a wrapper table standing for `v` as a secret. nil passes through
--                             unchanged: absent and present-but-opaque are different facts.
--   Kit.isSecret(v)           true only for a wrapper Kit.secret minted.
--   Kit.reveal(v)             the plain value behind a wrapper; the identity on anything else. What a
--                             native seam (a StatusBar, a formatter) may do, and what a suite uses to
--                             assert what a widget was handed.
--   Kit.installSecretValue()  sets the global `issecretvalue` to a function answering Kit.isSecret,
--                             and returns a restore function that puts back whatever global was there
--                             before, nil included. Call the restore in the case's teardown.
--
-- NOTHING INSTALLS `issecretvalue` BY DEFAULT. `mock_base.lua`'s build does not touch it, so a client
-- without the global stays modeled and no consumer's behavior changes on re-vendor. A suite that
-- wants the global asks for it.
--
-- TRAPPED: `+ - * / % ^` with the secret on either side, unary `-`, `..` on either side, indexing,
-- field assignment, calling, and `<`, `<=` and `==` between two wrappers. `..` is stricter than the
-- client (where it yields a secret string) on purpose: it is the operation a refactor reaches for.
--
-- WHAT LUA 5.1 CANNOT TRAP, stated rather than pretended. A suite that needs one of these must
-- assert it explicitly:
--
--   * A BOOLEAN TEST (`if s then`, `s and x`, `not s`) has no metamethod. A table is truthy, so it
--     always succeeds here and raises in the client.
--   * `==` AGAINST A NON-TABLE (`s == 0`, `s == nil`) is answered false by the VM without consulting
--     `__eq`, which 5.1 runs only when both operands are tables sharing the metamethod.
--   * `tostring(s)` is not trapped (the client permits it too, yielding a secret string). Note that
--     5.1's `string.format("%s", s)` raises on any table, with Lua's own text.
--   * `#s`: 5.1 consults `__len` only for userdata, never for a table, so `#s` answers 0 here. The
--     metamethod is set anyway, so the trap is live on an interpreter that honors it.
--   * A COMPARISON BETWEEN A SECRET AND A PLAIN VALUE (`s < 5`) raises, but with Lua's own "attempt
--     to compare" text: the VM rejects mixed operand types before any metamethod. Match the marker
--     with two secrets.
--   * `type(s)` answers "table", where the client answers the underlying type.
--   * A secret used as a table KEY is ordinary Lua and cannot be trapped.
--
-- ONE REGISTRY, PROCESS-WIDE. The registry of wrappers and their shared metatable live in
-- `package.loaded`, created by the first load and reused by every later one, so a secret minted under
-- one mock build, or under one load of the kit (a suite that `dofile`s `framework.lua` gets a second
-- kit table), is recognized under the next, and `==` between wrappers from two loads still reaches
-- the trap. The registry is weak-keyed, so a wrapper nothing holds is collected.
--
-- SHAPE. Returns `function(Kit)`, which installs the members above on the kit table it is handed.
-- `framework.lua` loads it once, from its own folder, beside `asserts.lua` and `inventory.lua`; it is
-- not a module a suite loads on its own.

local STATE_KEY = "ka0s.testkit.secrets"
local SECRET_ERROR = "secret value"

local function sharedState()
  local state = package.loaded[STATE_KEY]
  if type(state) == "table" then return state end
  state = { registry = setmetatable({}, { __mode = "k" }) }
  local function trap(op)
    return function()
      error(("%s: %s on a secret value; tainted code may store, pass, table-value and widget-set "
        .. "a secret and may do nothing else"):format(SECRET_ERROR, op), 2)
    end
  end
  state.meta = {
    __lt = trap("<"), __le = trap("<="), __eq = trap("=="),
    __add = trap("+"), __sub = trap("-"), __mul = trap("*"), __div = trap("/"),
    __mod = trap("%"), __pow = trap("^"), __unm = trap("unary -"),
    __concat = trap(".."), __len = trap("#"),
    __index = trap("indexing"), __newindex = trap("field assignment"), __call = trap("a call"),
    __tostring = function() return "<secret>" end,
  }
  package.loaded[STATE_KEY] = state
  return state
end

return function(Kit)
  local state = sharedState()
  local registry, meta = state.registry, state.meta

  Kit.SECRET_ERROR = SECRET_ERROR

  function Kit.secret(v)
    if v == nil then return nil end
    local s = setmetatable({}, meta)
    registry[s] = { value = v }
    return s
  end

  function Kit.isSecret(v)
    return registry[v] ~= nil
  end

  function Kit.reveal(v)
    local box = registry[v]
    if box then return box.value end
    return v
  end

  function Kit.installSecretValue()
    local before = rawget(_G, "issecretvalue")
    rawset(_G, "issecretvalue", function(v) return Kit.isSecret(v) end)
    return function() rawset(_G, "issecretvalue", before) end
  end
end
