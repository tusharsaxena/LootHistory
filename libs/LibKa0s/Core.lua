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

local MAJOR, MINOR = "LibKa0s-Core-1.0", 2
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

-- The one skin every Ka0s window wears. `bg` and `border` travel in the same table as the backdrop
-- fields because the three calls are one decision: a copy that took the backdrop but not the
-- colors is exactly the drift this exists to prevent. WoW's backdrop system reads only the fields
-- it knows, so the two extra keys are inert when the table is handed to SetBackdrop.
lib.SKIN = {
  bgFile = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
  bg = { 0.06, 0.06, 0.07, 0.95 },
  border = { 0, 0, 0, 1 },
}

--- Wear the skin. A no-op on a frame with no SetBackdrop — a frame created without the
--- BackdropTemplate inherit is undecorated, not broken, and a missing skin is not worth erroring
--- over in the middle of building someone's window.
function lib.ApplySkin(frame)
  if not frame or not frame.SetBackdrop then return end
  frame:SetBackdrop(lib.SKIN)
  frame:SetBackdropColor(lib.SKIN.bg[1], lib.SKIN.bg[2], lib.SKIN.bg[3], lib.SKIN.bg[4])
  frame:SetBackdropBorderColor(lib.SKIN.border[1], lib.SKIN.border[2], lib.SKIN.border[3],
    lib.SKIN.border[4])
end

--- The thin × a Ka0s window closes with. Returns nil when CreateFrame is unavailable (a headless
--- harness, or a load path with no UI), for the same reason ApplySkin degrades: a close button is
--- worth doing without, not worth erroring over.
function lib.MakeCloseButton(parent, onClick)
  if type(CreateFrame) ~= "function" then return nil end
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(18, 18)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  fs:SetPoint("CENTER")
  fs:SetText("\195\151")  -- multiplication sign ×
  fs:SetTextColor(0.7, 0.7, 0.72)
  b:SetScript("OnEnter", function() fs:SetTextColor(1, 0.3, 0.3) end)
  b:SetScript("OnLeave", function() fs:SetTextColor(0.7, 0.7, 0.72) end)
  b:SetScript("OnClick", onClick)
  return b
end

-- ── the prefixed chat printer ──────────────────────────────────────────────────────────────

--- Build a printer for one host.
---
--- Descriptor:
---   prefix  string|function  required. The tag, VERBATIM — never synthesised from an abbreviation,
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
