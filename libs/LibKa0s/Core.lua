-- LibKa0s-Core-1.0 — the two seams every other module in this library sits on.
--
-- They have nothing to do with each other except that both are tiny, stateless, and shared by
-- everything: the SECRET-SAFE SEAM (a value that WoW protects in combat survives tostring() and
-- the `..` operator, and raises only inside table.concat — so every line an addon emits has to be
-- rendered through a detector that probes the operation which actually rejects it), and the WINDOW
-- CHROME SEAM (a debug console and a perf panel that draw their own lookalike backdrops drift
-- apart one hex digit at a time; sharing the values makes a host's windows read as one addon).
--
-- Everything on the cross-module path is a stateless lib-level function. Only the chat printer is
-- instance-shaped, and no printer is ever handed between modules: a stateless function that exists
-- at minor 1 still exists at minor 9, which is what makes "a Core from any vendored copy works
-- with a DebugLog from any other" true by construction rather than by discipline.
--
-- Depends on LibStub and nothing else, deliberately — no Ace3, so the lib is adoptable by addons
-- that are not on the Ace substrate.

local MAJOR, MINOR = "LibKa0s-Core-1.0", 7
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

-- Which version of each FILE in this major is actually live, so version skew is discoverable at
-- runtime rather than by reading source. LibStub resolves one winner per major, but a major spanning
-- several files can end up with files from different vendored copies — and with six addons each
-- carrying their own copy, "which panel is attached to which probe?" is a question someone will need
-- answered from in-game. Not reset on upgrade: a newer file writes its own key over the old value.
-- Every file in this major MUST register here, and its number MUST rise on every released change to
-- that file. See docs/releasing.md.
lib.MODULES = lib.MODULES or {}
lib.MODULES.Core = MINOR

-- ── the secret-safe seam ───────────────────────────────────────────────────────────────────

-- What an un-renderable value renders as. Exported rather than left as a literal so a host's tests,
-- its documentation and this implementation cannot drift apart.
lib.SECRET = "<secret>"

-- Secret-value guard. In combat, WoW protects combat-sensitive returns (e.g.
-- UnitGetTotalAbsorbs("player") and AbbreviateNumbers() of it) as "secret" values. A secret
-- survives tostring() AND the `..` operator (which silently propagates the secretness) but RAISES
-- `invalid value (secret) ... for 'concat'` the moment it reaches `table.concat`. Since every
-- chat and debug line ends in a table.concat, an unguarded secret both spams a Lua error AND — when
-- it happens inside a repeating repaint ticker — kills the ticker so the display freezes until
-- /reload.
--
-- Detection MUST probe the operation that actually rejects a secret: `table.concat`, NOT `..`.
-- `pcall(function() return v .. "" end)` reports a secret as *safe* (the operator doesn't raise),
-- which is the bug that let a secret slip through. Concat a one-element table — exactly what the
-- printers do downstream — so the probe fails on precisely what the real call fails on. A public
-- `issecretvalue()` exists as of 12.0, but this pcall probe is kept as a version-agnostic detector
-- that tests the exact operation (`table.concat`) that rejects a secret.
local function probeConcat(v) return table.concat({ v }) end

--- True when `v` can survive the table.concat every emitted line ends in.
function lib.IsConcatSafe(v)
  return (pcall(probeConcat, v))
end

--- Concat-safe stringifier for every line an addon emits. Ordinary values -> tostring(v); an
--- un-concatenable (secret) value -> lib.SECRET, so the surrounding table.concat can never raise.
--- nil and booleans are handled up front — table.concat also rejects a boolean element, but they
--- are never secret, so they must not be masked. Real secrets are numbers/strings, which the concat
--- probe catches. (A bare table would also probe unsafe and render as the sentinel, but no call
--- site passes bare tables — every arg is a string/number log fragment.)
function lib.SafeToString(v)
  if v == nil then return "nil" end
  if type(v) == "boolean" then return tostring(v) end
  if lib.IsConcatSafe(v) then return tostring(v) end
  return lib.SECRET
end

-- ── the window chrome seam ─────────────────────────────────────────────────────────────────

-- The one skin every Ka0s window wears: a flat 1px BLACK outer edge with a 1px light-gray highlight
-- synthesized just inside it (the "double edge"), a gold title, and a gray divider under the title
-- bar. Every color travels in the same table as the backdrop fields because they are one decision:
-- a copy that took the backdrop but not the colors is exactly the drift this exists to prevent.
-- WoW's backdrop system reads only the fields it knows, so the extra keys are inert when the table
-- is handed to SetBackdrop.
--
-- WHY THESE VALUES, and not the 12px UI-Tooltip-Border this shipped with through v1.2.0: two hosts
-- (BankLedger and LootHistory) had already arrived at this treatment independently for their own
-- windows and passed `applySkin` to keep their consoles matching them, while the three hosts on the
-- library default kept the tooltip border. Side by side, the five consoles did not read as one suite
-- of addons — which is the entire thing a shared skin exists to deliver. The definition moved to
-- where the majority of the surface already was. See standalone-windows in the Ka0s WoW Addon
-- Standard, which now specifies these values normatively.
lib.SKIN = {
  bgFile = "Interface\\Buttons\\WHITE8x8",
  -- A flat white texture TINTED black by `border` below, not border art: art at edgeSize 12 reads
  -- as a soft brown frame, and the Ka0s window edge is a hard 1px line.
  edgeFile = "Interface\\Buttons\\WHITE8x8",
  edgeSize = 1,
  insets = { left = 1, right = 1, top = 1, bottom = 1 },
  bg = { 0.06, 0.06, 0.08, 0.92 },
  border = { 0, 0, 0, 1 },
  -- The three that used to be unexpressible. They are not backdrop fields — an inner-border child
  -- frame, a FontString tint and a texture color are CALLS — which is why `ApplySkin` grew to make
  -- them rather than the table growing to describe them.
  innerBorder = { 0.24, 0.24, 0.27, 0.85 },
  divider     = { 0.24, 0.24, 0.27, 0.85 },
  title       = { 1.0, 0.82, 0.0 },
}

-- The two accents that are not backdrop fields and not the inner border: a FontString tint and a
-- texture color. Described as data rather than written out twice so the type-not-truthiness guard
-- below exists exactly once. `n` is the argument COUNT and is not cosmetic — a title takes three
-- components and a divider takes four, and collapsing them to one arity drops the divider's alpha.
local ACCENTS = {
  { key = "title",   method = "SetTextColor",    n = 3 },
  { key = "divider", method = "SetColorTexture", n = 4 },
}

-- The backdrop proper: the table itself, then the two colors it carries. Guarded on the key being
-- a table so a caller passing a plain WoW backdrop table (no `bg`, no `border`) gets a plain
-- backdrop rather than a raise midway through building someone's window.
local function applyBackdrop(frame, skin)
  frame:SetBackdrop(skin)
  if type(skin.bg) == "table" then
    frame:SetBackdropColor(skin.bg[1], skin.bg[2], skin.bg[3], skin.bg[4])
  end
  if type(skin.border) == "table" then
    frame:SetBackdropBorderColor(skin.border[1], skin.border[2], skin.border[3], skin.border[4])
  end
end

-- The 1px inner highlight, inset one pixel on both axes so it sits INSIDE the black edge rather
-- than on top of it. Built ONCE per frame and returned thereafter: ApplySkin is called again
-- whenever a window is re-skinned, and a second child frame would stack a second line on the same
-- pixel.
--
-- Decided on the TYPE of what the frame answered, never on its truthiness. A frame is a table with
-- a metatable, and this library cannot assume what that metatable does with a key it has never
-- heard of: a consumer's test mock answers EVERY key with a function, so `frame.innerBorder` read
-- back truthy, `if not frame.innerBorder` never fired, and the tint below then indexed a function
-- and raised — taking fourteen of that addon's cases down on the first re-vendor.
local function ensureInnerBorder(frame, skin)
  if type(frame.innerBorder) ~= "table" then
    local inner = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    if type(inner) == "table" then
      if inner.SetPoint then
        inner:SetPoint("TOPLEFT", 1, -1)
        inner:SetPoint("BOTTOMRIGHT", -1, 1)
      end
      if inner.SetBackdrop then
        inner:SetBackdrop({ edgeFile = skin.edgeFile, edgeSize = 1 })
      end
      frame.innerBorder = inner
    end
  end
  return frame.innerBorder
end

-- Synthesize the highlight if it is not there yet, then re-tint it on every call.
local function applyInnerBorder(frame, skin)
  if type(skin.innerBorder) ~= "table" or type(CreateFrame) ~= "function" then return end
  local inner = ensureInnerBorder(frame, skin)
  if type(inner) == "table" and type(inner.SetBackdropBorderColor) == "function" then
    inner:SetBackdropBorderColor(skin.innerBorder[1], skin.innerBorder[2],
      skin.innerBorder[3], skin.innerBorder[4])
  end
end

-- Both accents are optional on the FRAME, not just in the skin: the copy window and the perf panel
-- carry a title and no divider, and a bare frame carries neither. Same type-not-truthiness rule as
-- the inner border, for the same reason.
local function applyAccents(frame, skin)
  for _, a in ipairs(ACCENTS) do
    local c, target = skin[a.key], frame[a.key]
    if type(c) == "table" and type(target) == "table" and type(target[a.method]) == "function" then
      target[a.method](target, unpack(c, 1, a.n))
    end
  end
end

--- Wear the skin. A no-op on a frame with no SetBackdrop — a frame created without the
--- BackdropTemplate inherit is undecorated, not broken, and a missing skin is not worth erroring
--- over in the middle of building someone's window.
---
--- `skin` is optional and defaults to `lib.SKIN`. It exists so a host that overrides the skin —
--- DebugLog's descriptor `skin` field is the only one today — reaches THIS implementation rather
--- than a second copy of the same five calls somewhere else, which is how a title tint ends up
--- applied on one window and not its twin.
---
--- Every step past the backdrop is guarded on the key being present, so a caller passing a plain
--- WoW backdrop table (no `bg`, no `innerBorder`, …) gets a plain backdrop rather than a raise
--- midway through building a window that is not yet hidden or Esc-wired.
function lib.ApplySkin(frame, skin)
  if not frame or not frame.SetBackdrop then return end
  skin = type(skin) == "table" and skin or lib.SKIN

  applyBackdrop(frame, skin)
  applyInnerBorder(frame, skin)
  applyAccents(frame, skin)
end

-- What the close control is drawn at, and how much of that slot the art fills. The slot is the
-- click target, unchanged at 18 since minor 1 -- every window in the collection is laid out around
-- it. The art is inset because a glyph that reaches its own edges reads far heavier than the title
-- beside it; the icon set is drawn to be legible well below this.
local CLOSE_SIZE = 18
local CLOSE_ART  = 12

-- Gray at rest, red under the pointer. The × has read this way since minor 1 and the texture keeps
-- it: a close control is the one button in a window whose hover state should say "this one ends
-- what you are looking at".
local CLOSE_REST = { 0.7, 0.7, 0.72 }
local CLOSE_HOT  = { 1, 0.3, 0.3 }

--- The close control a Ka0s window closes with. Returns nil when CreateFrame is unavailable (a
--- headless harness, or a load path with no UI), for the same reason ApplySkin degrades: a close
--- button is worth doing without, not worth erroring over.
---
--- TWO LOOKS, AND WHICH ONE YOU GET DEPENDS ON WHETHER YOU SAY WHO YOU ARE. Pass `addonName` and it
--- draws this collection's own `close` icon out of `LibKa0s-Media-1.0`; omit it and you get the
--- multiplication sign this function has always drawn.
---
--- The argument exists because a texture path is absolute from `Interface\AddOns\` and this
--- library is VENDORED -- there is no one path to it, and a copy cannot know which addon folder it
--- was copied into. Core cannot ask Media for a path without being told the answer to that, and it
--- must not guess: a wrong texture path draws nothing and raises nothing.
---
--- The × is therefore not a legacy spelling to be migrated away from. It is what a caller that has
--- not been updated still gets, what a host without the Media module gets, and what every window
--- gets on an install missing the art -- all three of which are the same code path, which is why
--- there is no separate degraded branch to keep working.
---
--- @param parent table
--- @param onClick function
--- @param addonName string  optional. The caller's own addon folder name, from its first vararg.
--- @return table|nil
function lib.MakeCloseButton(parent, onClick, addonName)
  if type(CreateFrame) ~= "function" then return nil end
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(CLOSE_SIZE, CLOSE_SIZE)

  -- Resolved at CALL time, not at load: Core is the first file in LibKa0s.xml and Media the second,
  -- so a load-time lookup here would answer nil for the life of the session.
  local media = addonName and LibStub and LibStub("LibKa0s-Media-1.0", true)
  local path = media and media.Icon and media.Icon(addonName, "close")

  if path then
    local tex = b:CreateTexture(nil, "OVERLAY")
    tex:SetPoint("CENTER")
    tex:SetSize(CLOSE_ART, CLOSE_ART)
    tex:SetTexture(path)
    -- Tinted rather than recolored: the art ships WHITE precisely so a multiply lands on whatever
    -- the caller wants, and here that is the same two colors the glyph has always used.
    tex:SetVertexColor(CLOSE_REST[1], CLOSE_REST[2], CLOSE_REST[3])
    b:SetScript("OnEnter", function() tex:SetVertexColor(CLOSE_HOT[1], CLOSE_HOT[2], CLOSE_HOT[3]) end)
    b:SetScript("OnLeave", function() tex:SetVertexColor(CLOSE_REST[1], CLOSE_REST[2], CLOSE_REST[3]) end)
    b.icon = tex
  else
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("CENTER")
    fs:SetText("\195\151")  -- multiplication sign ×
    fs:SetTextColor(CLOSE_REST[1], CLOSE_REST[2], CLOSE_REST[3])
    b:SetScript("OnEnter", function() fs:SetTextColor(CLOSE_HOT[1], CLOSE_HOT[2], CLOSE_HOT[3]) end)
    b:SetScript("OnLeave", function() fs:SetTextColor(CLOSE_REST[1], CLOSE_REST[2], CLOSE_REST[3]) end)
    b.glyph = fs
  end

  b:SetScript("OnClick", onClick)
  return b
end

-- ── the stored-color reader ────────────────────────────────────────────────────────────────

-- Absence tested with `== nil` rather than `or`, and written ONCE rather than eight times. A stored
-- `false` survives as false instead of being swallowed, and lizard counts every `or` short-circuit
-- as a decision — so one named helper is one decision where the chain would be eight.
local function pick(v, d)
  if v == nil then return d end
  return v
end

--- Read a stored color and return four NUMBERS, never a table.
---
--- The collection persists colors in BOTH shapes and neither can be retired without migrating
--- users' SavedVariables, so a reader that handles both is permanent rather than transitional:
---
---   keyed       { r = , g = , b = , a = }   -- AbsorbTracker, KickCD, the Slash parser's output
---   positional  { r,   g,   b,   a   }      -- what the Ka0s options color widget writes
---
--- Rules, in order:
---   1. A non-table (nil included) yields the four defaults, unchanged.
---   2. Any of c.r / c.g / c.b present means the KEYED shape wins for ALL FOUR channels — so a
---      `{ r = 1 }` cannot silently borrow its green from c[2].
---   3. Otherwise the positional shape.
---   4. Each channel falls back INDEPENDENTLY, so a three-element color still gets its alpha.
---
--- The defaults are per-channel parameters and are deliberately NOT defaulted here: the call sites
--- disagree today (0,0,0,1 for a chat echo, 1,1,1,1 for a swatch, a per-widget tint elsewhere), and
--- inventing a house default would silently recolor one of them.
function lib.RGBA(c, dr, dg, db, da)
  if type(c) ~= "table" then return dr, dg, db, da end
  if c.r ~= nil or c.g ~= nil or c.b ~= nil then
    return pick(c.r, dr), pick(c.g, dg), pick(c.b, db), pick(c.a, da)
  end
  return pick(c[1], dr), pick(c[2], dg), pick(c[3], db), pick(c[4], da)
end

-- ── the class color, and the swatch it defers to ───────────────────────────────────────────
--
-- Every addon in the collection is growing a "use class color" companion beside every color
-- swatch it draws (options-ui-§17), and each was about to answer the same three questions its own
-- way. They ARE the same three questions, and answering them differently is how a collection stops
-- reading as one author's work: a bar that keeps its alpha under a class color beside a border
-- that does not.
--
-- Three implementations existed before this one and two of them disagreed about the SOURCE:
-- AbsorbTracker read `C_ClassColor.GetClassColor`, PanelMaster and MultiMeters read
-- `RAID_CLASS_COLORS`. PanelMaster's recorded argument wins, and it is not a coin toss --
-- RAID_CLASS_COLORS is the table every other UI on the player's screen is already reading, so it
-- is what the unit frames next to ours are showing. One source, here, once.

--- Does `c` carry all three channels as numbers?
---
--- A palette entry that half-knows a class -- a table with a hex string and nothing else -- is not
--- a color, and two thirds of one is worse than none.
local function hasChannels(c)
  return type(c) == "table"
     and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number"
end

-- The PLAYER's own class cannot change inside a session, so it is looked up once. NO OTHER UNIT IS
-- EVER CACHED: target and focus change class every time the player retargets, and a per-unit cache
-- would need invalidating on PLAYER_TARGET_CHANGED and PLAYER_FOCUS_CHANGED to save one table
-- index. Cached on SUCCESS ONLY, which is what lets a class the client has not answered for yet
-- resolve on the next read rather than being pinned nil for the session.
local playerColor

--- The class color for a unit, or NIL.
---
--- NIL IS AN ANSWER. An NPC, an unresolvable unit, a unit whose class the client has not answered
--- for -- none of them is a color, and substituting one (white, gray, anything) invents a hue
--- nobody chose, appearing only in the cases nobody tests. Every caller falls through to the
--- stored swatch instead; see ResolveColor.
---
--- @param unit string|nil   a unit token; nil or omitted means the player
--- @return number|nil r, number|nil g, number|nil b
function lib.ClassColor(unit)
  local isPlayer = (unit == nil or unit == "player")
  if isPlayer and playerColor then
    return playerColor.r, playerColor.g, playerColor.b
  end
  if type(UnitClass) ~= "function" then return nil end

  -- pcall'd because the token is the CALLER'S: a unit string the client rejects raises rather than
  -- answering nil, and one bad token must cost this color rather than the frame being repainted.
  local ok, _, token = pcall(UnitClass, unit or "player")
  if not ok or type(token) ~= "string" then return nil end

  local c = type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[token] or nil
  if not hasChannels(c) then return nil end
  if isPlayer then playerColor = c end
  return c.r, c.g, c.b
end

--- Forget the memoized player color. Suite seam, and the one thing a session cannot need.
function lib.__ResetClassColor() playerColor = nil end

--- Resolve a stored swatch through its class-color companion. Four numbers out, always.
---
--- Three rules, and all three were already unanimous across the three implementations this
--- replaces -- written down in none of them, which is why they are stated here:
---
---   1. THE CONFIGURED ALPHA SURVIVES THE MODE. No class-color source carries an alpha, so the
---      swatch's is always the one used -- which is also why the swatch is never disabled.
---   2. AN UNRESOLVABLE CLASS FALLS THROUGH TO THE STORED SWATCH, never to a default color.
---   3. The swatch is read under BOTH modes, so it is never grayed and never `disabledIf`
---      (options-ui-§17, anti-patterns #74): setting the color before turning the mode on is the
---      normal order of operations, and a disabled control makes it a two-visit job.
---
--- The stored value goes through lib.RGBA, so both persisted shapes -- keyed and positional --
--- work here exactly as they do everywhere else in this collection. A host with a codec of its own
--- may decode first; it does not have to.
---
--- @param stored table|nil  the stored swatch, keyed or positional
--- @param on any            the companion checkbox's stored value
--- @param unit string|nil   the unit the SURFACE DESCRIBES; nil means the player
--- @return number r, number g, number b, number a
function lib.ResolveColor(stored, on, unit)
  local r, g, b, a = lib.RGBA(stored, 1, 1, 1, 1)
  if not on then return r, g, b, a end
  local cr, cg, cb = lib.ClassColor(unit)
  if cr == nil then return r, g, b, a end
  return cr, cg, cb, a
end

-- ── the prefixed chat printer ──────────────────────────────────────────────────────────────

--- Build a printer for one host.
---
--- Descriptor:
---   prefix  string|function  required. The tag, VERBATIM — never synthesized from an abbreviation,
---                            because the collection's tags differ in case, color and trailing
---                            space. A function is re-read on EVERY call, which is what lets a host
---                            whose prefix constant is defined in a file that loads later pass
---                            `function() return NS.PREFIX end` instead of capturing nil forever.
---   sep     string           optional, default " ". Separates the prefix from the body; a tag that
---                            carries its own trailing space passes "".
---   sink    function(line)   optional, default DEFAULT_CHAT_FRAME:AddMessage. Injectable because
---                            hosts that route their chat through the global `print` capture at
---                            exactly that seam in their headless harnesses.
---
--- The returned printer's methods are plain functions, not methods: a host does
--- `local print = NS.Print` at file scope and calls it bare, so they must not need a self.
function lib:New(d)
  d = type(d) == "table" and d or {}

  local prefix = d.prefix
  local prefixIsFn = type(prefix) == "function"
  if not prefixIsFn and type(prefix) ~= "string" then
    error(MAJOR .. ":New requires descriptor.prefix — the tag verbatim, as a string or as a " ..
      "function returning one", 2)
  end

  local sep = type(d.sep) == "string" and d.sep or " "
  local sink = type(d.sink) == "function" and d.sink or nil

  local printer = {}

  -- The tag is resolved here rather than above so a function prefix answers with whatever the host
  -- has set by now. A prefix that has not resolved yet emits the body alone: a line reading
  -- "nil something happened" is worse than an untagged one, and this is the load-order window the
  -- function form exists to survive.
  local function emit(body)
    -- Spelled out rather than folded into an `and`/`or`: a function prefix that answers nil would
    -- fall through such a chain to the function value itself and concatenate as one.
    local tag = prefix
    if prefixIsFn then tag = prefix() end
    local line = (tag == nil or tag == "") and body or (tag .. sep .. body)
    if sink then
      sink(line)
    elseif DEFAULT_CHAT_FRAME then
      DEFAULT_CHAT_FRAME:AddMessage(line)
    end
  end

  --- Space-joined, prefix-tagged, secret-safe. Mirrors print()'s shape so a host's existing naked
  --- print(...) call sites keep working once `print` is bound to this.
  function printer.Print(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do parts[i] = lib.SafeToString((select(i, ...))) end
    emit(table.concat(parts, " "))
  end

  --- format() over pre-stringified arguments, so a secret reaching a %s slot renders as the
  --- sentinel instead of raising on its way to the chat frame.
  function printer.Format(fmt, ...)
    local n = select("#", ...)
    if n == 0 then emit(lib.SafeToString(fmt)) return end
    local parts = {}
    for i = 1, n do parts[i] = lib.SafeToString((select(i, ...))) end
    emit(lib.SafeToString(fmt):format(unpack(parts)))
  end

  return printer
end
