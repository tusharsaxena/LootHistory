-- testkit/skin_switch.lua — the skin-switch check behind tests/_kit/test_skin_switch.lua (kit
-- revision 50, FS-GATE of Ka0sAddonsCommonTasks docs/2026-11-01-FULL_SKINNING): does a painted
-- surface change when the skin does? It spies on the drawing setters a surface calls while the skin
-- flips, because a getter compared with itself proves nothing.
--
-- THE PROBE. A skin giving every token a value of its own (W.probeTokens). A real skin cannot do
-- this job: real skins share tokens on purpose (`icon.arrow` is `hud.label`, `menu.text` is
-- `text.body`), and some leave a token at Ka0s Default's value, so a surface drawing the right token
-- reads as unchanged, and one drawing the wrong token reads as right. ConsumableMaster's flip test
-- showed the way with a local probe; this one covers the whole schema. A color is unique across the
-- schema and off Ka0s Default; a number moves by one; a bool flips; a string takes another skin's
-- value, because a font or bar key has to resolve, and stays put only where every skin agrees.
--
-- THE FLIP. Ka0s Default, probe, Ka0s Default, probe, one more repaint, Ka0s Default: four real
-- switches, so a host's repaint path runs each time. The first settles: a region a lazy paint makes on
-- it is spied from then on. The rest are compared, setter by setter, on what each object was last
-- given. Nothing is called "painted" that the host did not draw in response to the switch.
--
-- THE TWO HOME FLIPS ARE THE NOISE FLOOR. A setter that moves for its own reasons (a counter's
-- SetText, a fade's SetAlpha, a fresh table with a field that changes) would read as the skin. So a
-- key the two home flips disagree on is dropped from the comparison: the skin was the same both
-- times, so the skin did not move it, and a surface with nothing else left did not change. The
-- repaint under the probe, whose draws are not read, puts the home flips an odd distance apart: at
-- an even distance, something that alternates per paint would agree with itself at home and differ
-- under the probe. A host that skips an unchanged repaint loses nothing by it.
--
-- THE TWO PASSES. "clear": Scope cleared and companions on, every surface changes. "ignored": the
-- owner's Scope ignored and companions off, a surface marked `scope` or carrying a `companion` is
-- excluded, because the rules say it stays stock or stored there, and every other surface still has
-- to change.
--
-- The probe is unregistered and the owner's choice and Scope put back whatever a surface does.

local W = {}

--- The probe's key, for as long as a pass runs.
W.PROBE_KEY = "__kitProbe"

--- The setters that put something on the screen.
W.SETTERS = {
  "SetTextColor", "SetColorTexture", "SetVertexColor", "SetGradient", "SetDesaturated", "SetAlpha",
  "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor",
  "SetStatusBarColor", "SetStatusBarTexture", "SetTexture", "SetAtlas",
  "SetNormalTexture", "SetPushedTexture", "SetHighlightTexture", "SetDisabledTexture", "SetCheckedTexture",
  "SetFont", "SetFontObject", "SetShadowColor", "SetShadowOffset",
  "SetText", "SetFormattedText", "AddLine", "AddDoubleLine",
}

-- ── the probe ────────────────────────────────────────────────────────────────────────────────

--- Color number `n`, unique for n below 4096: each hex digit of `n` is a channel, a step of 0.04
--- apart, so two colors differ by more than any rounding a comparison does.
local function colorOf(n)
  local r = 0.1 + (n % 16) * 0.04
  local g = 0.1 + (math.floor(n / 16) % 16) * 0.04
  local b = 0.1 + (math.floor(n / 256) % 16) * 0.04
  return { r, g, b, 0.9 }
end

--- Another skin's value for token `name`, or nil when every skin holds `base`.
local function otherValue(Skin, name, base)
  for _, def in ipairs(Skin:Skins()) do
    local v = Skin:ResolveSkin(def.key)[name]
    if v ~= nil and v ~= base then return v end
  end
  return nil
end

local KIND = {
  color = function(ctx) return colorOf(ctx.next()) end,
  colors = function(ctx, _, base)
    local out = {}
    for i = 1, type(base) == "table" and #base or 3 do out[i] = colorOf(ctx.next()) end
    return out
  end,
  number = function(_, _, base) return (type(base) == "number" and base or 0) + 1 end,
  bool = function(_, _, base) return not base end,
  string = function(ctx, name, base) return otherValue(ctx.Skin, name, base) or base or "" end,
}

--- Every schema token with a value of its own.
function W.probeTokens(Skin)
  local n, tokens = 0, {}
  local base = Skin:ResolveSkin(Skin.DEFAULT)
  local ctx = { Skin = Skin, next = function() n = n + 1; return n end }
  for _, entry in ipairs(Skin.SCHEMA) do
    tokens[entry.name] = KIND[entry.kind](ctx, entry.name, base[entry.name])
  end
  return tokens
end

local function registerProbe(Skin)
  Skin:RegisterSkin({ key = W.PROBE_KEY, label = "Probe", tokens = W.probeTokens(Skin) })
end

local function unregisterProbe(Skin)
  Skin.skins[W.PROBE_KEY] = nil
  for i = #Skin.__order, 1, -1 do
    if Skin.__order[i] == W.PROBE_KEY then table.remove(Skin.__order, i) end
  end
  Skin.__resolved = {}
end

-- ── the spies ────────────────────────────────────────────────────────────────────────────────

local function fmt(v, depth)
  local t = type(v)
  if t == "number" then return ("%.3f"):format(v) end
  if t ~= "table" then return t == "function" and "fn" or tostring(v) end
  if depth > 2 then return "{...}" end
  local keys, parts = {}, {}
  for k in pairs(v) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local val = v[k]
    if val == nil then val = v[tonumber(k)] end
    parts[#parts + 1] = k .. "=" .. fmt(val, depth + 1)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function fmtArgs(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = fmt((select(i, ...)), 0) end
  return table.concat(parts, " ")
end

--- `obj`'s method `name`, or nil. The kit's paint recorder raises on a method a region does not
--- model, which is its right and no business of a spy that only asks.
local function methodOf(obj, name)
  local ok, fn = pcall(function() return obj[name] end)
  return ok and type(fn) == "function" and fn or nil
end

--- The tables a walker answers for `obj`, or none: a mock that answers a frame for any method is
--- taken at its word, since the walk keeps a seen set.
local function kin(obj, method, out)
  local fn = methodOf(obj, method)
  if not fn then return end
  local got = { pcall(fn, obj) }
  for i = 2, #got do
    if type(got[i]) == "table" then out[#out + 1] = got[i] end
  end
end

--- Put the spies on `obj`.
local function spyOn(rec, obj)
  rec.n = rec.n + 1
  local id = rec.n
  rec.ids[obj] = id
  for _, name in ipairs(W.SETTERS) do
    local fn = methodOf(obj, name)
    if fn then
      local had = rawget(obj, name)
      rec.undos[#rec.undos + 1] = function() rawset(obj, name, had) end
      rawset(obj, name, function(self, ...)
        rec.log[id .. ":" .. name] = fmtArgs(...)
        return fn(self, ...)
      end)
    end
  end
end

--- Watch `obj`, its regions, its children and a NineSlice. `seen` is one walk's: a later walk reads
--- a known object's family again, for what a paint made since.
local function watch(rec, obj, seen)
  if type(obj) ~= "table" or seen[obj] then return end
  seen[obj] = true
  if not rec.ids[obj] then spyOn(rec, obj) end
  local family = {}
  kin(obj, "GetRegions", family)
  kin(obj, "GetChildren", family)
  if type(rawget(obj, "NineSlice")) == "table" then family[#family + 1] = rawget(obj, "NineSlice") end
  for _, other in ipairs(family) do watch(rec, other, seen) end
end

--- Spy on the drawing setters of `objects` and everything under them. Answers `{ log, undo, watch }`:
--- `log` maps "id:Setter" to the last arguments, `watch(objects)` takes in regions made since, and
--- `undo()` takes every spy off.
function W.spy(objects)
  local rec = { n = 0, ids = {}, undos = {}, log = {} }
  function rec.watch(list)
    local seen = {}
    for _, obj in ipairs(list) do watch(rec, obj, seen) end
  end
  function rec.undo()
    for _, undo in ipairs(rec.undos) do undo() end
    rec.undos = {}
  end
  rec.watch(objects)
  return rec
end

-- ── one surface ──────────────────────────────────────────────────────────────────────────────

--- Switch the owner to `key`, let the host redraw, and answer what was drawn.
local function flip(run, key)
  run.rec.log = {}
  run.Skin:SetChoice(run.owner, "ka0s", key)
  if run.surface.paint then run.surface.paint(unpack(run.frames)) end
  run.rec.watch(run.frames)
  return run.rec.log
end

local function isEmpty(t) return next(t) == nil end

--- One more paint under the skin that holds, its draws not read: a surface with no `paint` has only
--- the library's own listeners, which a repaint of nothing does not reach.
local function repaint(run)
  run.rec.log = {}
  if run.surface.paint then run.surface.paint(unpack(run.frames)) end
end

--- `log` without the keys `a` and `b`, two draws of one skin, disagree on.
local function steady(log, a, b)
  local out = {}
  for key, args in pairs(log) do
    if a[key] == b[key] then out[key] = args end
  end
  return out
end

--- True when a key in `a` draws something else in `b`, or is not drawn there.
local function differs(a, b)
  for key, args in pairs(a) do
    if b[key] ~= args then return true end
  end
  return false
end

local function setterNames(log)
  local seen, names = {}, {}
  for key in pairs(log) do
    local name = key:match(":(.+)$")
    if not seen[name] then seen[name] = true; names[#names + 1] = name end
  end
  table.sort(names)
  return table.concat(names, ", ")
end

--- The four flips over a built surface. Answers a problem, or nil.
local function compare(run)
  local Skin, name = run.Skin, run.surface.name
  flip(run, W.PROBE_KEY)
  local home = flip(run, Skin.DEFAULT)
  local probe = flip(run, W.PROBE_KEY)
  repaint(run)
  local again = flip(run, Skin.DEFAULT)
  if isEmpty(home) and isEmpty(probe) then
    return ("%s drew nothing on a skin switch: no drawing setter ran, so it does not repaint, or "
      .. "its build answered the wrong object"):format(name)
  end
  local base, seen = steady(home, home, again), steady(probe, home, again)
  if differs(base, seen) or differs(seen, base) then return nil end
  if isEmpty(base) then
    return ("%s did not change on a skin switch: all it drew (%s) moved between two draws of one skin, "
      .. "so none of it follows the skin"):format(name, setterNames(home))
  end
  return ("%s did not change on a skin switch (%s drew the same under the probe)"):format(name, setterNames(home))
end

--- One built, spied and compared pass. Only "clear" reaches a companion: "ignored" excludes the
--- surfaces that carry one, so its surfaces have no companion to hold off.
local function pass(facts, Skin, surface, ignore)
  local rec
  local ok, problem = pcall(function()
    Skin:SetIgnore(facts.owner, ignore, ignore)
    Skin:SetChoice(facts.owner, "ka0s", Skin.DEFAULT)
    if surface.companion then surface.companion(true) end
    local frames = { surface.build() }
    rec = W.spy(frames)
    return compare({ Skin = Skin, owner = facts.owner, surface = surface, frames = frames, rec = rec })
  end)
  if rec then rec.undo() end
  if ok then return problem end
  return ("%s raised: %s"):format(tostring(surface.name), tostring(problem))
end

local function skinOf(facts)
  if type(facts.skin) == "function" then return facts.skin() end
  return facts.skin
end

--- Run one surface. `mode` "clear" asks every surface; "ignored" holds the Scope ignored and
--- companions off. Answers a problem or nil, and, as its second value, true for a surface the pass
--- excludes. The owner's choice and Scope come back as they were.
function W.runSurface(facts, surface, mode)
  local ignored = mode == "ignored"
  if ignored and (surface.scope or surface.companion) then return nil, true end
  local Skin = skinOf(facts)
  local source, skin = Skin:GetChoice(facts.owner)
  local panel, fonts = Skin:GetIgnore(facts.owner)
  registerProbe(Skin)
  local problem = pass(facts, Skin, surface, ignored)
  Skin:SetChoice(facts.owner, source, skin)
  Skin:SetIgnore(facts.owner, panel, fonts)
  unregisterProbe(Skin)
  if facts.reset then facts.reset() end
  return problem
end

-- ── the facts ────────────────────────────────────────────────────────────────────────────────

local SCOPES = { panel = true, fonts = true }

local function surfaceProblem(s, seen)
  if type(s) ~= "table" or type(s.name) ~= "string" or s.name == "" then return "a surface has no name" end
  if seen[s.name] then return ("surface %q is declared twice"):format(s.name) end
  seen[s.name] = true
  if type(s.build) ~= "function" then return ("surface %q has no build"):format(s.name) end
  if s.scope ~= nil and not SCOPES[s.scope] then
    return ("surface %q has scope %q: panel, fonts or nothing"):format(s.name, tostring(s.scope))
  end
  if s.companion ~= nil and type(s.companion) ~= "function" then
    return ("surface %q has a companion that is no function(on)"):format(s.name)
  end
  return nil
end

--- What is wrong with the host's facts, in reading order.
function W.factsProblems(facts)
  local out = {}
  if type(facts.owner) ~= "string" or facts.owner == "" then out[#out + 1] = "no owner: the addon folder name" end
  local Skin = skinOf(facts)
  if type(Skin) ~= "table" then
    out[#out + 1] = "no skin: LibKa0s-Skin-1.0, or a function answering it"
  elseif facts.owner and not Skin:IsOwner(facts.owner) then
    out[#out + 1] = ("owner %q is not registered"):format(tostring(facts.owner))
  end
  if type(facts.surfaces) ~= "table" or #facts.surfaces == 0 then
    out[#out + 1] = "no painted surface is declared"
    return out
  end
  local seen = {}
  for _, s in ipairs(facts.surfaces) do
    local problem = surfaceProblem(s, seen)
    if problem then out[#out + 1] = problem end
  end
  return out
end

return W
