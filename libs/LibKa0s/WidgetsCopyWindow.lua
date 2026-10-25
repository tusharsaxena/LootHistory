-- LibKa0s-Widgets-1.0 — CopyWindow: the read-only copy window every "export this" surface in the
-- collection ends in.
--
-- ── WHY IT IS A FILE OF ITS OWN AND NOT MORE OF Widgets.lua ──────────────────────────────────
--
-- Because of `layout-§1`, as for WidgetsReorder.lua. Widgets minor 16 (the skin owner) took
-- Widgets.lua past the 1000-line re-check its band disposition named, and the copy window was the
-- seam that disposition named. It moved here at Widgets minor 16 with its skin half and nothing
-- else changed: `lib.CopyWindow` is the same member with the same descriptor. It is NOT a major of
-- its own: it is part of `LibKa0s-Widgets-1.0`, guarded with the same multi-file idiom, so a copy
-- window from one vendored copy can never pair with a shell from another without saying so. It
-- reads the shell's skin helpers (`lib.__skinOf`, `lib.__onSkin`) and works
-- without them, as minor 15's window, when an older shell lacks them.
--
-- Depends on LibStub, on the Widgets shell and on LibKa0s-Core-1.0 (resolved at call time), and
-- on no addon framework. A payload without this file loads whole and simply has no
-- `lib.CopyWindow`.

local lib = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
if not lib then return end

local COPY_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own, as WidgetsReorder.lua is.
if lib.__copyMinor and lib.__copyMinor >= COPY_MINOR
  and lib.__copyShellMinor == lib.MINOR then return end
lib.__copyMinor      = COPY_MINOR
lib.__copyShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.WidgetsCopyWindow = COPY_MINOR

--- The shell's skin-owner check, or nil when the shell predates it (Widgets minor 16).
local function skinOf(owner)
  local fn = lib.__skinOf
  if type(fn) ~= "function" then return nil end
  return fn(owner)
end

-- ── the copy window ──────────────────────────────────────────────────────────────────────────
--
-- WHY THIS IS HERE. There is no file I/O in WoW. Every "export this" surface in the collection
-- therefore ends in the same thing: a frame holding a multi-line EditBox with the text selected,
-- and an instruction to press Ctrl+C. There were four copies before this member — BankLedger's,
-- LootHistory's, MultiMeters' and the debug log's — and two of them were the same fifty-two lines
-- with the addon name substituted out.
--
-- It lives in Widgets rather than in a major of its own for the same reason the dropdown does:
-- Widgets already owns "a frame this collection kept re-drawing", and the three addons that need
-- this already vendor it. A new major would have bought a fourth vendor sweep for nothing.
--
-- WHAT THE HOST STILL OWNS. The art and the face arrive as DESCRIPTOR FIELDS, not as lookups: a
-- vendored copy cannot know which addon folder it sits in, so it cannot resolve a texture path or
-- ask Media for one without being told the host's name. That is the same bargain
-- LibKa0s-Media-1.0 and Core.MakeCloseButton already strike.

local COPY_DEFAULTS = {
  width = 640, height = 420, fontSize = 10, title = "Export",
  backdrop = { 0.06, 0.06, 0.08, 0.95 },
}

-- The smallest a copy window may be sized down to (minor 11): room for the title bar's centered
-- title and close control and a few lines of text. Capped at the descriptor's own size, so a window
-- declared smaller than this is its own minimum rather than one it could never be built at.
local COPY_MIN_W, COPY_MIN_H = 240, 140
-- The scroll frame's bottom inset. UIPanelScrollFrameTemplate hangs its scroll-down button at the
-- scroll frame's bottom edge, and Core.MakeResizable's grip covers the window's bottom 17 px (16 px
-- square, 1 px in, ten levels up), so at the old 10 px a click on the button's lower part started a
-- resize instead of scrolling. 18 puts the whole button above the grip.
local COPY_SCROLL_BOTTOM = 18

--- The edit box's width for a window `w` wide. The scroll frame's own width once the client has laid
--- it out; before that (or headless) the window's width less the same margin the descriptor's
--- `editWidth` keeps from its `width`, so a resized window keeps the gap the declared one had.
local function copyEditWidth(f, d, w)
  local sw = f.scroll:GetWidth()
  if type(sw) == "number" and sw > 0 then return sw end
  if type(w) == "number" and w > 0 then return w - (d.width - d.editWidth) end
  return d.editWidth
end

--- Fill a caller's descriptor out with the collection's defaults, without mutating theirs.
local function copyDescriptor(d)
  local out = {
    addonName = d.addonName,
    name      = d.name or (d.addonName .. "CopyWindow"),
    width     = d.width or COPY_DEFAULTS.width,
    height    = d.height or COPY_DEFAULTS.height,
    title     = d.title or COPY_DEFAULTS.title,
    font      = d.font,
    fontSize  = d.fontSize or COPY_DEFAULTS.fontSize,
    applySkin = d.applySkin,
    backdrop  = d.backdrop or COPY_DEFAULTS.backdrop,
    hostBackdrop = d.backdrop ~= nil,
    anchorTo  = d.anchorTo,
    -- Optional, minor 7, and NOT defaulted to anything. UIPanelScrollFrameTemplate derives its
    -- scrollbar children's names from its parent's, so an anonymous scroll frame leaves them
    -- unnamed — which is invisible until somebody tries to skin or find one. The debug log's own
    -- copy window had always named it and the three adopters here never had; that difference is
    -- what surfaced when DebugLog minor 12 converged onto this member. Left nil by default so a
    -- caller written before minor 7 keeps exactly the frame it already had rather than silently
    -- acquiring a global.
    scrollName = d.scrollName,
    -- Optional, minor 7. Defaults to Core's x, which is what all four callers want and what three
    -- of them already got. It exists because LibKa0s-DebugLog-1.0 has published a `makeCloseButton`
    -- descriptor field since ITS minor 4, documented as applying to BOTH of its windows — so when
    -- minor 12 converged its copy window onto this member, a hardcoded Core x here would have
    -- quietly narrowed a contract a host had already been told it could rely on.
    makeCloseButton = d.makeCloseButton,
  }
  out.editWidth = d.editWidth or (out.width - 50)
  return out
end

--- Resizable on both axes from minor 11, when the Core under it has the grip (Core minor 9);
--- guarded, so an older Core leaves the fixed window this always was. The descriptor's `width` and
--- `height` stay the size it opens at, and a named window keeps its own size for the session: the
--- frame is built once per handle and never resized on a later Show. The scroll frame is anchored
--- to both corners and follows on its own; the edit box inside it is a scroll CHILD and does not,
--- so its width is set again on every resize.
local function makeCopyResizable(f, d, coreLib)
  if not (coreLib and type(coreLib.MakeResizable) == "function") then return end
  coreLib.MakeResizable(f, {
    minWidth  = math.min(COPY_MIN_W, d.width),
    minHeight = math.min(COPY_MIN_H, d.height),
    onResize  = function(w) f.edit:SetWidth(copyEditWidth(f, d, w)) end,
  })
end

--- The denser fill, again after each skin change of a skinned window (minor 16): the host's own
--- `backdrop` when it passed one, else the owner's `win.bgDense`. Shell repaints the window first.
local function copyDense(f, owner)
  local d, Skin = f.__copyDesc, skinOf(owner)
  if not (d and Skin and f.SetBackdropColor) then return end
  local c = d.hostBackdrop and d.backdrop or Skin:Token(owner, "win.bgDense") or d.backdrop
  f:SetBackdropColor(c[1], c[2], c[3], c[4])
end

--- A registered owner's copy window: the scroll bar painted, the dense fill kept across switches.
local function skinCopy(f, d, owner)
  local Skin = skinOf(owner)
  if not Skin then return end
  local sb = rawget(f.scroll, "ScrollBar")
  if type(sb) == "table" then Skin:For(owner).ScrollBar(sb) end
  f.__copyDesc = d
  if type(lib.__onSkin) == "function" then lib.__onSkin(Skin, owner, f, copyDense) end
  copyDense(f, owner)
end

--- The window's skin: the host's own applySkin, else Core's, then the denser fill. Minor 16: the
--- descriptor's addonName is the skin owner when it registered one (the shell's SKIN OWNERS); a
--- host's own applySkin wins and is never skinned over.
local function paintCopyFrame(f, d, coreLib)
  local owner = (not d.applySkin and skinOf(d.addonName)) and d.addonName or nil
  if d.applySkin then
    d.applySkin(f)
  elseif coreLib and coreLib.ApplySkin then
    coreLib.ApplySkin(f, nil, owner)
  end
  -- Denser than the shared skin. This frame is a wall of small monospace text, and the world
  -- behind it bleeding through costs legibility in a way it does not on a frame showing four
  -- controls.
  if f.SetBackdropColor then
    f:SetBackdropColor(d.backdrop[1], d.backdrop[2], d.backdrop[3], d.backdrop[4])
  end
  if owner then skinCopy(f, d, owner) end
end

--- Build the frame. Called once, lazily, on the first Show — a modal rebuilt per open leaks a
--- frame per open for the life of the session, because frames are never destroyed in WoW.
local function buildCopyFrame(d)
  local f = CreateFrame("Frame", d.name, UIParent, "BackdropTemplate")
  f:SetSize(d.width, d.height)
  f:SetPoint("CENTER")
  -- FULLSCREEN so it sits above the DIALOG-strata modal that opened it. The modal stays visible
  -- underneath, which is what makes "copy this, then pick a different set" one trip rather than two.
  f:SetFrameStrata("FULLSCREEN")
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)

  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", -1, -1)
  bar:SetHeight(26)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() f:StartMoving() end)
  bar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("CENTER")
  title:SetText(d.title)
  f.title = title

  -- Resolved at CALL time rather than at load: Core is the first file in LibKa0s.xml and loads well
  -- before this one, so a load-time lookup would be fine here — but MakeCloseButton itself resolves Media
  -- at call time for exactly this reason, and one rule about when the payload is resolvable is
  -- easier to keep than two.
  local coreLib = LibStub and LibStub("LibKa0s-Core-1.0", true)
  local makeClose = d.makeCloseButton or (coreLib and coreLib.MakeCloseButton)
  if makeClose then
    local close = makeClose(bar, function() f:Hide() end, d.addonName)
    if close then close:SetPoint("RIGHT", bar, "RIGHT", -6, 0) end
  end

  local scroll = CreateFrame("ScrollFrame", d.scrollName, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -30)
  scroll:SetPoint("BOTTOMRIGHT", -28, COPY_SCROLL_BOTTOM)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  -- The face arrives as a PATH. SetFont does not accept a LibSharedMedia name, and a CSV is
  -- columns of digits that only line up in a fixed-width face.
  if d.font then edit:SetFont(d.font, d.fontSize, "") end
  edit:SetAutoFocus(false)
  edit:SetWidth(d.editWidth)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
  scroll:SetScrollChild(edit)

  f.scroll, f.edit = scroll, edit

  paintCopyFrame(f, d, coreLib)

  f:Hide()
  -- By NAME, type-guarded: UISpecialFrames is a list of GLOBAL frame names and the table itself is
  -- not guaranteed to exist outside a real client.
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, d.name)
  end

  makeCopyResizable(f, d, coreLib)
  return f
end

--- A read-only copy window: text in, Ctrl+C out, Esc closes.
---
--- Returns a HANDLE, not a frame, so the frame stays lazy — nothing is created until the first
--- Show, which matters because a host builds this at file load and most sessions never open it.
--- Answers nil with no client and without an `addonName` (which the close control needs to find
--- the collection's own art).
---
--- @param d table  see docs/api/Widgets — addonName is the only required field
--- @return table|nil
function lib.CopyWindow(d)
  if type(d) ~= "table" or type(d.addonName) ~= "string" then return nil end
  if type(CreateFrame) ~= "function" then return nil end

  local desc = copyDescriptor(d)
  local frame
  local win = { __descriptor = desc }

  function win:GetFrame()
    if not frame then frame = buildCopyFrame(desc) end
    return frame
  end

  function win:GetText()
    return frame and frame.edit:GetText() or nil
  end

  function win:Hide()
    if frame then frame:Hide() end
  end

  --- THE ORDER IS LOAD-BEARING: width, then text, then cursor to the top, then show, then focus,
  --- then highlight. Highlighting before the frame is shown selects nothing, and focusing before
  --- the text is set leaves the cursor wherever the last export left it. All four hand-rolled
  --- copies got this right and the fifth author would have had to rediscover it.
  function win:Show(text)
    local f = self:GetFrame()

    -- Re-anchored on EVERY show, not once at build: the popup has to land over the window that
    -- spawned it, wherever the user has since dragged that window.
    f:ClearAllPoints()
    local anchor = desc.anchorTo and desc.anchorTo()
    if anchor and anchor.IsShown and anchor:IsShown() then
      f:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    else
      f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    -- The window's current width, not the declared one: a resized window keeps its edit box.
    f.edit:SetWidth(copyEditWidth(f, desc, f:GetWidth()))
    f.edit:SetText(text or "")
    f.edit:SetCursorPosition(0)
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
    return f
  end

  return win
end
