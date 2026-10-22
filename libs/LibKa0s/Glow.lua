-- LibKa0s-Glow-1.0 — the stateless LibCustomGlow-1.0 driver.
--
-- ── WHY THIS EXISTS ──────────────────────────────────────────────────────────────────────────
--
-- Three hosts (DropWatcher, QuickComms, KickCD) mapped the same knobs to the same positional
-- arguments of LibCustomGlow-1.0, and each had to find the same two traps on its own: a
-- `pixelLength` of 0 draws zero-length lines, and a `nil` border flag draws the border. This file is
-- that mapping, once, and nothing else (LibKa0s#56).
--
-- ── THE CONTRACT ─────────────────────────────────────────────────────────────────────────────
--
-- Start(frame, style, knobs, key, frameLevel) -> boolean and Stop(frame, style, key). The style
-- vocabulary is closed: "button", "proc", "pixel", "autocast"; anything else is a quiet no-op.
-- `knobs` carries `color` and the thirteen named knobs (docs/api/Glow/version-1-docs.md); fields it
-- does not name are ignored, so a host passes its whole config table. No defaults: a nil knob
-- reaches LCG as nil and LCG's own value applies.
--
-- ── THE SEVEN TRAPS ──────────────────────────────────────────────────────────────────────────
--
-- 1. `pixelLength` 0 means automatic: LCG computes a length only for nil, so 0, negatives and
--    non-numbers go as nil.
-- 2. `pixelBorder` draws for anything but false (LCG tests `not (border == false)`), and LCG's
--    `startAnim` default is true; both booleans go as `~= false`.
-- 3. ProcGlow_Start calls setmetatable on the options it is handed, so it gets a fresh table per
--    call: never the caller's knobs, never a reused scratch.
-- 4. The button style keeps `color` by reference, so a host must not mutate a color it handed over.
-- 5. The button style has no key: one per frame, and a stop-all stops anyone's. Stop-all only on a
--    frame you own.
-- 6. ButtonGlow_Stop on a visible frame animates out and releases later; a restart inside that
--    window reuses the glow. LCG behavior, transparent here.
-- 7. Combat: LCG's frames are plain children, so nothing here is a protected call.
--
-- ── WHAT IT DELIBERATELY IS NOT ──────────────────────────────────────────────────────────────
--
-- Each with the trigger that would reopen it (docs/api/Glow/version-1-docs.md, "What is not here"):
--   * no knob defaults          — never: the owner's decision; they live in each host's profile;
--   * no ranges, no knob catalog — a fourth host copies the knob table, or one host edits a range
--                                  the others do not;
--   * no STYLES list             — a host that needs the list without its localized labels;
--   * no lifecycle: the unchanged-repaint gate, Apply/Release — the three hosts' gates still differ;
--   * no proc-burst spend        — never: it writes LCG internal state;
--   * no triggers, no class-color resolution, no stop-before-start — host policy;
--   * no Available()             — a host that needs to know resolves LibCustomGlow-1.0 itself;
--   * no clamping                — KickCD's safety policy, not a fact about LCG.
--
-- LibCustomGlow-1.0 is resolved at EVERY call, never captured at load, and each member is
-- presence-checked: the payload cannot carry a consumer-vendored lib, so there is no floor on it.
--
-- Depends on LibStub and LibKa0s-Core-1.0. No Core member is called; the gate keeps the payload's
-- presence a single question.

local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Glow-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.Glow = MINOR

local LCG = "LibCustomGlow-1.0"
local NONE = {}   -- nil or non-table knobs: read nothing, allocate nothing

local function lcg() return LibStub and LibStub(LCG, true) end   -- CALL time, every call

local function num(v) if type(v) == "number" then return v end end
local function len(v) if type(v) == "number" and v > 0 then return v end end

-- START[style](fn, frame, k, key, level): fn is the presence-checked LCG member.
local START_FN = {
  pixel = "PixelGlow_Start", autocast = "AutoCastGlow_Start",
  button = "ButtonGlow_Start", proc = "ProcGlow_Start",
}
local START = {
  pixel = function(fn, frame, k, key, level)
    fn(frame, k.color, num(k.pixelLines), num(k.pixelFrequency), len(k.pixelLength),
      num(k.pixelThickness), num(k.xOffset), num(k.yOffset), k.pixelBorder ~= false, key, level)
  end,
  autocast = function(fn, frame, k, key, level)
    fn(frame, k.color, num(k.autocastParticles), num(k.autocastFrequency), num(k.autocastScale),
      num(k.xOffset), num(k.yOffset), key, level)
  end,
  button = function(fn, frame, k, _, level)
    fn(frame, k.color, num(k.buttonFrequency), level)
  end,
  proc = function(fn, frame, k, key, level)
    fn(frame, {
      color = k.color, startAnim = k.procStartAnim ~= false, duration = num(k.procDuration),
      xOffset = num(k.xOffset), yOffset = num(k.yOffset), key = key, frameLevel = level,
    })
  end,
}

local STOP_FN = {
  button = "ButtonGlow_Stop", pixel = "PixelGlow_Stop",
  autocast = "AutoCastGlow_Stop", proc = "ProcGlow_Stop",
}
local ORDER = { "button", "pixel", "autocast", "proc" }   -- stop-all order

--- Start one style's glow on `frame`. Never stops anything first.
---
--- @param frame table|nil      the frame the effect is drawn around
--- @param style string         "button" | "proc" | "pixel" | "autocast"
--- @param knobs table|nil      color and the named knobs; other fields ignored
--- @param key string|nil       the caller's identity, passed through (unused by "button")
--- @param frameLevel number|nil relative to frame; nil is LCG's own
--- @return boolean  true when LCG's _Start for the style was called
function lib.Start(frame, style, knobs, key, frameLevel)
  local start = START[style]
  if frame == nil or not start then return false end
  local L = lcg()
  local fn = L and L[START_FN[style]]
  if type(fn) ~= "function" then return false end
  start(fn, frame, type(knobs) == "table" and knobs or NONE, key, frameLevel)
  return true
end

local function stopOne(L, frame, style, key)
  local fn = L[STOP_FN[style]]
  if type(fn) ~= "function" then return end
  if style == "button" then fn(frame) else fn(frame, key) end
end

--- Stop a glow on `frame`. A style stops that style only; nil stops all four (button, pixel,
--- autocast, proc). An unknown style string, a nil frame or an absent LCG is a no-op.
---
--- @param frame table|nil
--- @param style string|nil
--- @param key string|nil  passed to every style but "button"
function lib.Stop(frame, style, key)
  if frame == nil or (style ~= nil and not STOP_FN[style]) then return end
  local L = lcg()
  if not L then return end
  if style ~= nil then
    stopOne(L, frame, style, key)
    return
  end
  for i = 1, #ORDER do stopOne(L, frame, ORDER[i], key) end
end
