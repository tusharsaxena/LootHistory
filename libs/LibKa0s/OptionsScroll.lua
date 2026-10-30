-- LibKa0s-Options-1.0 — the always-visible scrollbar patch, the settings chrome's skin owner (minor
-- 5), and the font preload (at the foot of the file; each has its own header).
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

-- Minor 5: the page's skin owner (the Options descriptor's `addonName`, once that addon called
-- LibKa0s-Skin-1.0's RegisterOwner): the always-shown bar's thumb takes the owner's scroll tints, and
-- the chrome helpers every Options file paints through (LK-07 of the skinning run).
-- Minor 6: `lib.__AttachSkinAce`, the bridge to LibKa0s-Skin-1.0's AceGUI rows (SkinAce.lua), and
-- the owner's skin switch re-renders the open pages ONE FRAME LATER, so a release gives every row
-- back stock and a re-acquire paints it in the new skin (LK-08 of the skinning run).
-- Minor 7: the chrome paints nothing while the owner ignores its settings panel (LibKa0s-Skin-1.0
-- minor 5's __PanelSkinned); the instance's listener is still installed from the owner's facade,
-- so turning the exception off re-renders the open pages in the skin, and turning it on hands every
-- chrome target the owner's skin painted back as it was (lib.__chromeRelease): no reload. And a
-- page's backdrop is never the page itself, which a bare CreateTexture stub answers.
-- Minor 8: a released bar is handed back through lib.__chromeUnpaint, not only untracked: the skin's
-- ScrollBar fades the bar's own knob art (SkinPaintControls minor 7), and the pooled widget must get
-- it back.
-- Minor 9: `O.__tipColor`, the one color every tooltip line the chrome writes takes (the owner's
-- tooltip token while the chrome is skinned, else the literal it replaces; LK-06d of
-- Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_LIBRARY_FOLLOWUPS, ruling R-5, DECISIONS D-14).
-- Still minor 9 (LK-06c of the same run, ruling R-5, decisions D-07 and D-14): `O.__hoverArt`, the
-- one paint for hover art the chrome keeps outside a primitive (the id list entry, the id
-- suggestion row): `list.hoverArt` while the chrome is skinned, the client's art otherwise and on a
-- give-back. `__chromeAway`'s comments say what it does: since SkinPaint minor 6 no skin is special,
-- so it answers the facade wherever `__chromeSkin` does, Ka0s Default included.
local SCROLL_MINOR = 9
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
---
--- `owner` (minor 5) is optional: the page's skin owner. For a registered one the thumb's two tints
--- are painted again through its facade (`S.ScrollBar(bar, { state = "on" | "off" })`) after this
--- patch's own, and the bar is given back to the library on release, since the widget is pooled.
--- Without one, the patch tints exactly as minor 4 did.
function lib.PatchAlwaysShowScrollbar(scroll, owner)
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
    -- The skin's tints over the patch's own, for a registered owner (minor 5); nothing otherwise.
    if owner ~= nil and scrollbar and lib.__chromePaint then
      lib.__chromePaint(owner, "ScrollBar", scrollbar, { state = action == "Enable" and "on" or "off" })
    end
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
    -- Handed back as it was (minor 8): the skin fades the bar's knob art under its flat knob, and a
    -- pooled bar only untracked would reach the next addon with no knob at all.
    if owner ~= nil and scrollbar and lib.__chromeUnpaint then lib.__chromeUnpaint(scrollbar) end
    if scrollbar and scrollbar.Enable then scrollbar:Enable() end
    if upBtn   and upBtn.Enable   then upBtn:Enable()   end
    if downBtn and downBtn.Enable then downBtn:Enable() end
    if origOnRelease then origOnRelease(self) end
  end
end

-- ── the settings chrome's skin owner (minor 5) ─────────────────────────────────────────────
--
-- WHOSE SKIN A PAGE WEARS. The Options descriptor's `addonName` (the host's folder name) names the
-- page's owner, and it counts only once that addon called LibKa0s-Skin-1.0's `RegisterOwner`: every
-- collection host already passes `addonName` (OptionsIdList minor 3), and a host that never adopted
-- skins must keep drawing exactly what it drew. So an unregistered name, no name and a client with no
-- Skin major all paint today's settings chrome, call for call, and only a registered owner's page is
-- painted again through its facade, AFTER the chrome's own paint (a superset: a primitive a loaded
-- copy lacks leaves the page as drawn, and on Ka0s Default the primitive repeats today's colors).
--
-- WHY IT LIVES IN THIS FILE. Every Options file paints through these helpers, and the two band files
-- that need them most (Options.lua and OptionsTabs.lua) may take no new member before their peel
-- (CLAUDE.md's band). This file is already where Options.lua's overflow went (the font preload, minor
-- 24) and is attached with the descriptor, so the instance half below can close over `addonName`.
--
-- REPAINTING. A primitive records what it painted (Skin:Track), so a skin switch repaints the tabs,
-- the rail, the drawers, the cover, the popup and the thumbs on its own. What a page draws per
-- render from a token read (the id list's help marks, the keybind rows) is redrawn by the instance's
-- one OnLooksChanged listener, which re-renders the shown pages (O.RefreshAllPanels marks a hidden
-- one dirty), after repainting each page's header and backdrop.

--- The Skin major, or nil.
local function skinMajor()
  return LibStub and LibStub("LibKa0s-Skin-1.0", true) or nil
end

--- `owner`'s skin facade when it is a REGISTERED skin owner, else nil: Core's question
--- (`__SkinFacade`, Core minor 13), asked at call time. No Core of that minor answers nil.
local function ownerFacade(owner)
  local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
  local fn = core and core.__SkinFacade
  if type(fn) ~= "function" then return nil end
  return fn(owner)
end

--- The facade the chrome paints with: ownerFacade's, or nil while the owner ignores its settings
--- panel (minor 7; a Skin copy before minor 5 has no such exception).
function lib.__chromeSkin(owner)
  local S = ownerFacade(owner)
  if not S then return nil end
  local Skin = skinMajor()
  if Skin and type(Skin.__PanelSkinned) == "function" and not Skin:__PanelSkinned(owner) then return nil end
  return S
end

--- `owner`'s facade when the chrome is skinned (lib.__chromeSkin's answer), else nil. It was the
--- question "does the owner wear a skin other than Ka0s Default?", asked before a page drew something
--- Ka0s Default never drew; since SkinPaint minor 6 `P.isDefault` answers false always, no skin is
--- special and Ka0s Default draws all of it too, which is what the retired stock look (ruling R-2)
--- asks. Kept, and kept asking `P.isDefault`, because a Skin copy older than that minor still
--- answers true for Ka0s Default, and its callers (the id list's help mark, the keybind rows, the Skin
--- tab's muted labels, the page's backdrop) then draw that copy's Ka0s Default as it did.
function lib.__chromeAway(owner)
  local S = lib.__chromeSkin(owner)
  if not S then return nil end
  local Skin = skinMajor()
  local P = Skin and Skin.__P
  if not (P and type(P.isDefault) == "function") then return nil end
  if P.isDefault(owner) then return nil end
  return S
end

--- Forget `target` in the Skin major's frame registry, so the owner that painted it (a pooled frame
--- now drawn for no owner) no longer repaints it. Every chrome dress repaints each property a
--- primitive touches before it is called, so nothing needs putting back.
function lib.__chromeGiveBack(target)
  local Skin = skinMajor()
  if Skin and type(Skin.painted) == "table" and Skin.painted[target] and type(Skin.Untrack) == "function" then
    Skin:Untrack(target)
  end
  lib.__chromeTargets[target] = nil
end

-- Every chrome target a skin painted, and for which owner (weak): what lib.__chromeRelease hands back.
lib.__chromeTargets = lib.__chromeTargets or setmetatable({}, { __mode = "k" })

--- Put `target` back as it was before the skin painted it, from the Skin major's record (its saved
--- alpha, fonts, colors and backdrop; every Ka0s region hidden), and forget it. Minor 7.
function lib.__chromeUnpaint(target)
  local Skin = skinMajor()
  local P = Skin and Skin.__P
  local rec = Skin and type(Skin.painted) == "table" and Skin.painted[target]
  if rec and P and type(P.unpaint) == "function" then pcall(P.unpaint, rec, target) end
  lib.__chromeGiveBack(target)
end

--- Hand back every chrome target `owner`'s skin painted: the panel exception turned on (minor 7).
function lib.__chromeRelease(owner)
  local mine = {}
  for target, o in pairs(lib.__chromeTargets) do
    if o == owner then mine[#mine + 1] = target end
  end
  for _, target in ipairs(mine) do lib.__chromeUnpaint(target) end
end

--- Paint `target` with primitive `prim` of `owner`'s facade (`opts` its argument) when `owner` is a
--- registered skin owner; otherwise give the target back: as it was, when this owner's skin painted
--- it and the owner now ignores its panel (minor 7), else lib.__chromeGiveBack. Answers the facade
--- or nil. A primitive the loaded Skin copy lacks paints nothing.
function lib.__chromePaint(owner, prim, target, opts)
  local S = lib.__chromeSkin(owner)
  if not S then
    if lib.__chromeTargets[target] == owner and ownerFacade(owner) then
      lib.__chromeUnpaint(target)
    else
      lib.__chromeGiveBack(target)
    end
    return nil
  end
  local fn = S[prim]
  if type(fn) == "function" then
    fn(target, opts)
    lib.__chromeTargets[target] = owner
  end
  return S
end

--- The page canvas's header and backdrop for a registered owner: the title in the skin's title role,
--- the divider atlas tinted `title.text` (Ka0s Default's gold is the title font's, as minor 1 tinted
--- it), and, wherever lib.__chromeAway answers (every skin, Ka0s Default included, since SkinPaint
--- minor 6), an opaque backdrop from `win.bg` at full alpha under everything the page draws, so a
--- light skin stays legible over the client's settings window. A texture rather than S.Panel.
--- Put a page's header and backdrop back as the client drew them (minor 7): the title from its
--- record, the divider's own tint, the backdrop hidden.
local function unpaintPage(panel)
  if panel.title then lib.__chromeUnpaint(panel.title) end
  local div, prior = panel.divider, panel.__ka0sDividerPrior
  if div and div.SetVertexColor and prior then div:SetVertexColor(prior[1], prior[2], prior[3], prior[4]) end
  local bg = panel.__ka0sSkinBg
  if bg then bg:Hide() end
end

--- The divider atlas tinted `title.text`, its own tint recorded the first time (unpaintPage's).
local function tintDivider(S, panel)
  local div = panel.divider
  local r, g, b = S.Color("title.text")
  if not (div and div.SetVertexColor and r) then return end
  if not panel.__ka0sDividerPrior and div.GetVertexColor then
    panel.__ka0sDividerPrior = { div:GetVertexColor() }
  end
  div:SetVertexColor(r, g, b)
end

--- The page's opaque `win.bg` backdrop, made once; hidden when the owner's skin draws none.
local function pageBackdrop(owner, S, panel)
  local bg = panel.__ka0sSkinBg
  local br, bgG, bb = S.Color("win.bg")
  if not (lib.__chromeAway(owner) and br) then
    if bg then bg:Hide() end
    return
  end
  if not bg and panel.CreateTexture then
    bg = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
    -- A bare stub answers the frame itself (SkinPaint's P.tex refuses the same): never keep the
    -- page as its own backdrop, whose Show and Hide would show and hide the page (minor 7).
    if bg == panel then bg = nil end
    if bg then
      bg:SetAllPoints(panel)
      panel.__ka0sSkinBg = bg
    end
  end
  if bg then
    bg:SetColorTexture(br, bgG, bb, 1)
    bg:Show()
  end
end

local function paintPage(owner, panel)
  local S = lib.__chromeSkin(owner)
  if not S then
    if ownerFacade(owner) then unpaintPage(panel) end
    return
  end
  if panel.title then
    S.Text(panel.title, "title")
    lib.__chromeTargets[panel.title] = owner
  end
  tintDivider(S, panel)
  pageBackdrop(owner, S, panel)
end

--- Hand an instance's `O.AceGUI` to LibKa0s-Skin-1.0's AceGUI rows (SkinAce.lua's
--- `__AttachSkinAce`, minor 6), which wraps it in a proxy that paints every widget it creates for the
--- descriptor's `addonName` once that addon is a registered skin owner. Options.lua's lib:New and
--- OptionsRegistry.lua's CreateOptionsPanel call it after each resolve of AceGUI. Without the Skin
--- major, without SkinAce.lua, without an AceGUI or without a registered owner, `O.AceGUI` is left
--- exactly as it was. Internal.
function lib.__AttachSkinAce(O, d)
  local Skin = skinMajor()
  local attach = Skin and Skin.__AttachSkinAce
  if type(attach) ~= "function" then return end
  local ok, err = pcall(attach, O, d)
  if not ok then
    local h = type(geterrorhandler) == "function" and geterrorhandler()
    if type(h) == "function" then h(err) end
  end
end

--- Put the patch and the chrome's skin helpers on an instance. Called from lib:New, so a host reaches
--- the patch the same way it reaches every other member -- the patch itself is stateless and
--- lib-level, because a scroll widget is shared pool property. The `__chrome*` members are internal:
--- the other Options files reach them at call time, and a copy without this file paints no skin.
function lib.__AttachScroll(O, d)
  O.PatchAlwaysShowScrollbar = lib.PatchAlwaysShowScrollbar

  local owner = type(d) == "table" and type(d.addonName) == "string" and d.addonName or nil
  -- The pages whose header and backdrop the listener repaints (weak: a page is never collected in
  -- the client, but a suite's are).
  local pages = setmetatable({}, { __mode = "k" })
  local hooked = false

  -- The structural re-render a skin switch owes the open pages, one frame later (minor 6): an
  -- AceGUI row is never repainted in place (SkinAce.lua), so the switch releases every row, which
  -- gives it back stock, and re-acquires it, which paints the new skin (or nothing, on Ka0s
  -- Default). Deferred so it runs once per frame however many switches land in it, and outside the
  -- click that made the switch.
  local renderPending = false
  local function rerender()
    renderPending = false
    if O.RefreshAllPanels then O.RefreshAllPanels() end
  end

  local function onLooks()
    -- The panel exception on: every chrome target this owner's skin painted goes back first.
    if not lib.__chromeSkin(owner) then lib.__chromeRelease(owner) end
    for panel in pairs(pages) do pcall(paintPage, owner, panel) end
    if renderPending then return end
    local after = C_Timer and C_Timer.After
    if type(after) ~= "function" then return rerender() end
    renderPending = true
    after(0, rerender)
  end

  --- The page owner's facade, or nil (nil too while it ignores its settings panel); the first call
  --- for a registered owner installs the instance's one OnLooksChanged listener, from the facade
  --- itself, so the exception's end re-renders the pages.
  function O.__chromeSkin()
    local F = owner and ownerFacade(owner) or nil
    if F and not hooked and type(F.OnLooksChanged) == "function" then
      hooked = true
      F.OnLooksChanged(onLooks)
    end
    return F and lib.__chromeSkin(owner) or nil
  end

  --- lib.__chromeAway for this instance's owner: the facade wherever the chrome is skinned.
  function O.__chromeAway()
    if not O.__chromeSkin() then return nil end
    return lib.__chromeAway(owner)
  end

  --- A tooltip line's color (minor 9): the owner's color token `token` while the chrome is
  --- skinned, read at hover so a switch reaches the next one; else `r, g, b`, the literal the line
  --- drew before, which is what an owner-less page and an owner ignoring its settings panel get. One
  --- helper for every line the chrome writes (O.AttachTooltip, the drawer head, the nav entry, the
  --- tab, the key button, the id list's help mark); a line that names no color stays the client's.
  function O.__tipColor(token, r, g, b)
    local S = O.__chromeSkin()
    local c = S and type(S.Token) == "function" and S.Token(token) or nil
    if type(c) == "table" and c[1] and c[2] and c[3] then return c[1], c[2], c[3] end
    return r, g, b
  end

  --- Hover art `tex` (an ADD highlight the client draws in its own color) for this page: while the
  --- chrome is skinned and the owner's `list.hoverArt` is a color, desaturated and tinted with it,
  --- read at the call; otherwise, and always with `back` (a pooled widget handed on), the art as the
  --- client draws it, not desaturated and untinted. For hover art outside a primitive (the id list
  --- entry, the id suggestion row); the drawer head's and the nav entry's go through S.Drawer and
  --- S.NavItem. Not a texture: nothing.
  function O.__hoverArt(tex, back)
    if type(tex) ~= "table" or type(tex.GetObjectType) ~= "function" then return end
    local ok, kind = pcall(tex.GetObjectType, tex)
    if not ok or kind ~= "Texture" then return end
    local S = not back and O.__chromeSkin() or nil
    local c = S and type(S.Token) == "function" and S.Token("list.hoverArt") or nil
    local tinted = type(c) == "table" and c[1] ~= nil
    if type(tex.SetDesaturated) == "function" then tex:SetDesaturated(tinted) end
    if tinted then tex:SetVertexColor(c[1], c[2], c[3]) else tex:SetVertexColor(1, 1, 1) end
  end

  --- lib.__chromePaint for this instance's owner.
  function O.__chromePaint(prim, target, opts)
    O.__chromeSkin()
    return lib.__chromePaint(owner, prim, target, opts)
  end

  --- Skin one page canvas (Options.lua's CreatePanel): now, and on every show, so an owner that
  --- registers after the page was built still gets it. Nothing for a host with no addonName.
  function O.__skinPage(panel)
    if not owner or type(panel) ~= "table" then return end
    pages[panel] = true
    if panel.HookScript then
      panel:HookScript("OnShow", function()
        O.__chromeSkin()
        paintPage(owner, panel)
      end)
    end
    O.__chromeSkin()
    paintPage(owner, panel)
  end
end

-- ── the font preload (minor 17) ────────────────────────────────────────────────────────────
--
-- AceGUI-3.0-SharedMediaWidgets' `LSM30_Font` builds its pull-out list on OPEN, running
-- `SetFont(face); SetText(name)` on one row per registered face. The client loads a font file on
-- its first reference, and text set with a face that is not loaded yet draws blank until something
-- sets it again — so the first open of any font dropdown in a session showed a blank row for every
-- face nothing had used yet (third-party LSM faces, mostly), and the second open was fine. The
-- widget is upstream and vendored, so it is not the thing to change; what the library can do is
-- have every face loaded before a dropdown can be opened, which is after a panel has been shown.
--
-- WHEN: a settings panel's show, never load or PLAYER_LOGIN. Loading every face costs memory, and
-- some of Blizzard's CJK faces are large; a player who never opens settings must not pay for it.
-- Opening a font dropdown would load every face anyway, so a player who does open settings pays
-- nothing extra, only earlier. The two call sites are in Options.lua's `lib:New` —
-- `O.SetRenderer`'s OnShow and `O.CreatePanel`'s hook — and each says why it is where it is.
--
-- WHY THIS MAJOR and not Media.lua: the trigger is the panel lifecycle, which this major owns and
-- Media.lua has none of; `getLSM` is already on this major's descriptor; and `LSM30_Font` is the
-- dialogControl this major's own `O.FontGroup` writes. Media.lua's `RegisterLSM` puts faces IN;
-- this is about the widget that lists them.
--
-- WHY THIS FILE (Options minor 24, SCROLL_MINOR 4): it lived in Options.lua from minor 17 to 23 and
-- moved here, unchanged, to keep the shell under layout-§1's 1500-line cap. Like the scrollbar
-- patch above it is stateless lib-level code with no instance half, and the shell's callers already
-- looked it up on `lib` at call time and did nothing when it was absent — so a partial copy missing
-- this file shows its pages with no preload, which is what minor 16 did, and never errors.
--
-- LIBRARY-LEVEL STATE, on `lib`, so every host instance shares it and a LibStub minor upgrade keeps
-- it: every vendored copy in the session is handed the same `lib`, so a client running five Ka0s
-- addons loads each face once, not five times. It is read through `preloadState()` at call time and
-- never captured, and `lib.__PreloadFonts` is looked up on `lib` at call time by both of its callers
-- — an instance built by an older copy, and the LSM callback — so after an upgrade the newest code
-- is what runs.

local function preloadState()
  lib.__fontPreload = lib.__fontPreload or { paths = {} }
  return lib.__fontPreload
end
preloadState()

--- The one frame the strings hang off. Shown, at full alpha and parented to UIParent — the client
--- may skip work for a hidden or fully transparent region, and a frame parented to a page would be
--- hidden with it — but 1x1 and parked off the left edge of the screen, so it is never seen.
local function preloadFrame(state)
  if state.frame then return state.frame end
  if type(CreateFrame) ~= "function" then return nil end
  local f = CreateFrame("Frame", nil, UIParent)
  if not f then return nil end
  f:SetSize(1, 1)
  if UIParent then f:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -64, 0) end
  f:SetAlpha(1)
  f:Show()
  state.frame = f
  return f
end

--- Load one face: a FontString per distinct PATH, since several LSM keys can name one file. The path
--- is marked BEFORE it is tried, so a face the client refuses is tried once, not on every show; and
--- the two calls are pcall'd together, because a SetFont that fails without raising leaves a string
--- whose SetText raises instead.
local function preloadPath(state, f, path)
  if type(path) ~= "string" or path == "" or state.paths[path] then return false end
  state.paths[path] = true
  local fs = f:CreateFontString(nil, "BACKGROUND")
  if not fs then return false end
  fs:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  return (pcall(function()
    fs:SetFont(path, 12, "")
    fs:SetText("Aa")
  end))
end

--- Faces registered after the first preload — an addon that loads on demand, or registers late —
--- are loaded as they arrive. ONE subscription for the library, whichever host's show made it: the
--- target is the shared state table, and CallbackHandler keeps one callback per (event, target).
local function subscribeLate(state, LSM)
  if state.subscribed or type(LSM.RegisterCallback) ~= "function" then return end
  state.subscribed = pcall(LSM.RegisterCallback, state, "LibSharedMedia_Registered",
    function(_, mediatype)
      if mediatype ~= "font" then return end
      local preload = lib.__PreloadFonts
      if type(preload) == "function" then pcall(preload, LSM) end
    end)
end

--- Load every LibSharedMedia face not loaded yet, then subscribe (once) to faces registered later.
--- Answers how many faces this call loaded. Anything that is not an LSM with a `HashTable` — `nil`
--- included — answers 0 and creates nothing, and so does a client with no `CreateFrame`, in which
--- case nothing is marked and the next call tries again.
---
--- @param LSM table|nil  LibSharedMedia-3.0, as the host's `getLSM()` returns it.
--- @return number
function lib.__PreloadFonts(LSM)
  if type(LSM) ~= "table" or type(LSM.HashTable) ~= "function" then return 0 end
  local ok, fonts = pcall(LSM.HashTable, LSM, "font")
  if not ok or type(fonts) ~= "table" then return 0 end
  local state = preloadState()
  local f = preloadFrame(state)
  if not f then return 0 end
  local n = 0
  for _, path in pairs(fonts) do
    if preloadPath(state, f, path) then n = n + 1 end
  end
  subscribeLate(state, LSM)
  return n
end
