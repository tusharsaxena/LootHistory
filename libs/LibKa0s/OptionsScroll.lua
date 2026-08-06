-- LibKa0s-Options-1.0 — the always-visible scrollbar patch.
--
-- AceGUI's stock ScrollFrame.FixScroll auto-hides the scrollbar when the content fits inside the
-- viewport. Across a settings panel's tabs that means a short page shows no scrollbar while a long
-- one does, and the body's right edge jumps sideways by the 20px gutter as you click between them.
-- This override always keeps the bar and its gutter shown, grays it out with the thumb parked at
-- the top when there is nothing to scroll, and persists the gutter so every page's content ends at
-- the same x.
--
-- Part of the Options major rather than a major of its own: it exists only to serve
-- Options.EnsureScroll, which calls it after every ScrollFrame it creates. Guarded with the
-- standard multi-file idiom — if an older Options.lua won the LibStub race, or a newer patch is
-- already attached, this file is a no-op.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

local SCROLL_MINOR = 3
-- Paired on the SHELL's minor as well as this file's own. The scroll counter alone is not enough:
-- two vendored copies can ship the same scroll minor over different Options.lua minors, and then
-- the higher shell wins the LibStub race while the first-loaded copy's patch stays attached to it.
-- Recording which shell the attached patch was built against makes a copy re-attach whenever the
-- shell underneath it changed. Same reasoning as PerfPanel's __panelProbeMinor.
if lib.__scrollMinor and lib.__scrollMinor >= SCROLL_MINOR
  and lib.__scrollShellMinor == lib.MINOR then return end
lib.__scrollMinor      = SCROLL_MINOR
lib.__scrollShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsScroll = SCROLL_MINOR

-- The gutter AceGUI reserves for a visible scrollbar. Everything below keeps the layout as if the
-- bar were always visible, which is the whole point.
local GUTTER = 20

-- Thumb tints. Full white when the bar is live; a dimmed gray when there is nothing to scroll, so
-- "shown but inert" reads differently from "shown and usable".
local THUMB_ON  = { 1, 1, 1, 1 }
local THUMB_OFF = { 0.5, 0.5, 0.5, 0.6 }

-- Call an optional method on an optional object. TRUTHINESS, deliberately, not
-- `type(...) == "function"`: every handle below can legitimately be nil (a headless scrollbar has
-- no thumb and no step buttons), and the fixtures assign plain fields, so a type test would change
-- what ships.
local function callIf(obj, method, ...)
  if obj and obj[method] then obj[method](obj, ...) end
end

-- The scrollbar's thumb texture, when it has one to give.
local function thumbOf(scrollbar)
  return scrollbar and scrollbar.GetThumbTexture and scrollbar:GetThumbTexture() or nil
end

-- The two step buttons Blizzard parents to a NAMED scrollbar, found the only way there is: by
-- name. A nameless bar (which is what a headless one is) has neither, and nil is a valid answer
-- everywhere they are used.
local function stepButtons(scrollbar)
  local sbName = scrollbar and scrollbar.GetName and scrollbar:GetName() or nil
  if not sbName then return nil, nil end
  return _G[sbName .. "ScrollUpButton"] or nil, _G[sbName .. "ScrollDownButton"] or nil
end

-- Lay the widget out as if the bar were always visible: bar shown, the scrollframe pulled in by the
-- gutter, and the content width inset to match. The same three blocks appear inside the FixScroll
-- override below and are deliberately NOT shared with it — that one re-checks `self.scrollBarShown`
-- first and only re-forces the layout when something else un-shown it.
local function forceGutter(scroll, scrollbar)
  scroll.scrollBarShown = true
  if scrollbar then scrollbar:Show() end
  if scroll.scrollframe then
    scroll.scrollframe:SetPoint("BOTTOMRIGHT", -GUTTER, 0)
  end
  if scroll.content and scroll.content.original_width then
    scroll.content.width = scroll.content.original_width - GUTTER
  end
end

--- Patch one AceGUI ScrollFrame in place. Idempotent, and reversible on OnRelease.
---
--- The marker is `_ka0sAlwaysScrollbar` rather than a per-addon name: AceGUI pools ScrollFrames
--- across every addon in the session, so two addons carrying differently-named markers would each
--- patch a widget the other had already patched, stacking two overrides on one FixScroll.
function lib.PatchAlwaysShowScrollbar(scroll)
  if not scroll or scroll._ka0sAlwaysScrollbar then return end
  scroll._ka0sAlwaysScrollbar = true

  local origFixScroll  = scroll.FixScroll
  local origMoveScroll = scroll.MoveScroll
  local origOnRelease  = scroll.OnRelease

  -- Kept on the widget as well as in the closure. OnRelease restores from the upvalues, but a test
  -- (and a developer with /dump) has no way to see whether the stock implementation was preserved
  -- at all, and "the patch quietly lost the original" fails silently — the widget just never gets
  -- its own behavior back when AceGUI recycles it.
  scroll.__stockFixScroll = origFixScroll

  local scrollbar      = scroll.scrollbar
  local thumb          = thumbOf(scrollbar)
  local upBtn, downBtn = stepButtons(scrollbar)

  local currentEnabled

  -- ONE parameterized apply for both directions. The two used to be written out as mirror images,
  -- which is four optional-object dances twice over, and mirrored branches drift apart one guard at
  -- a time. Call ORDER is the contract here and is unchanged: bar, thumb tint, up, down.
  local function applyState(action, tint)
    callIf(scrollbar, action)
    callIf(thumb, "SetVertexColor", unpack(tint))
    callIf(upBtn, action)
    callIf(downBtn, action)
  end

  local function setEnabled(want)
    if currentEnabled == want then return end
    currentEnabled = want
    if not scrollbar then return end

    if want then
      applyState("Enable", THUMB_ON)
    else
      -- Unguarded and BEFORE the disable, unlike everything applyState does: parking the thumb at
      -- the top is what makes a shown-but-inert bar read as inert.
      scrollbar:SetValue(0)
      applyState("Disable", THUMB_OFF)
    end
  end

  forceGutter(scroll, scrollbar)

  scroll.FixScroll = function(self)
    if self.updateLock then return end
    self.updateLock = true

    if not self.scrollBarShown then
      self.scrollBarShown = true
      self.scrollbar:Show()
      self.scrollframe:SetPoint("BOTTOMRIGHT", -GUTTER, 0)
      if self.content.original_width then
        self.content.width = self.content.original_width - GUTTER
      end
    end

    local status = self.status or self.localstatus
    local height, viewheight = self.scrollframe:GetHeight(), self.content:GetHeight()
    local offset = status.offset or 0

    if viewheight < height + 2 then
      setEnabled(false)
      self.scrollbar:SetValue(0)
      self.scrollframe:SetVerticalScroll(0)
      status.offset = 0
    else
      setEnabled(true)
      local value = (offset / (viewheight - height) * 1000)
      if value > 1000 then value = 1000 end
      self.scrollbar:SetValue(value)
      self:SetScroll(value)
      if value < 1000 then
        self.content:ClearAllPoints()
        self.content:SetPoint("TOPLEFT",  0, offset)
        self.content:SetPoint("TOPRIGHT", 0, offset)
        status.offset = offset
      end
    end

    self.updateLock = nil
  end

  -- A disabled bar must not respond to the mouse wheel either, or the page scrolls with no visible
  -- indication that anything moved.
  scroll.MoveScroll = function(self, value)
    if currentEnabled == false then return end
    if origMoveScroll then return origMoveScroll(self, value) end
  end

  -- AceGUI pools ScrollFrames. A widget handed back still carrying this override would take it
  -- into whichever addon recycles it next, which is how a patch escapes the addon that installed
  -- it. Everything set above is undone here, including the marker, so a re-acquired widget
  -- re-patches cleanly.
  scroll.OnRelease = function(self)
    self.FixScroll  = origFixScroll
    self.MoveScroll = origMoveScroll
    self.OnRelease  = origOnRelease
    self._ka0sAlwaysScrollbar = nil
    self.__stockFixScroll     = nil
    currentEnabled  = nil
    if thumb and thumb.SetVertexColor then thumb:SetVertexColor(unpack(THUMB_ON)) end
    if scrollbar and scrollbar.Enable then scrollbar:Enable() end
    if upBtn   and upBtn.Enable   then upBtn:Enable()   end
    if downBtn and downBtn.Enable then downBtn:Enable() end
    if origOnRelease then origOnRelease(self) end
  end
end

--- Put the patch on an instance. Called from lib:New, so a host reaches it the same way it reaches
--- every other member — the function itself is stateless and lib-level, because a scroll widget is
--- shared pool property and nothing about patching one depends on which host asked.
function lib.__AttachScroll(O)
  O.PatchAlwaysShowScrollbar = lib.PatchAlwaysShowScrollbar
end
