-- LibKa0s-Widgets-1.0 — the unlocked drag handle: a labeled strip with a help mark, dragged to move
-- the frame it belongs to.
--
-- ── WHY THIS IS A LIBRARY AND NOT TWO COPIES ─────────────────────────────────────────────────
--
-- AuraMaster drew one per container (modules/Anchors.lua) and ConsumableMaster drew one over its
-- macro bar (modules/MacroBar.lua), and the two were the same widget twice: the same 18px strip,
-- the same 2px gap, the same 24px of padding, the same centered gold GameFontNormalSmall label,
-- the same help Button at RIGHT, -4 taking its icon from the host's `help` art with the same
-- Blizzard texture as its last rung, and the same `label + PAD + HELP * 2` width. Two copies of a
-- widget is two skins to keep in step — the argument the dropdown was lifted under, and the
-- argument `lib.ROW_BOX` was published under one layer down. A drag handle over a frame the player
-- moves is the same sentence one frame up from a draggable row.
--
-- ── WHY IT IS A FILE OF ITS OWN AND NOT MORE OF Widgets.lua ──────────────────────────────────
--
-- Because of `layout-§1`'s 1500-line cap and nothing else. This surface written into Widgets.lua
-- took that file to 1540 lines, which is a breach needing a disposition; the file was already in
-- the 1000–1500 band at 1232. It is NOT a major of its own: it is part of `LibKa0s-Widgets-1.0`,
-- guarded with the same multi-file idiom OptionsWidgets.lua, OptionsTabs.lua, OptionsCompose.lua
-- and OptionsScroll.lua use under the Options shell, so a handle from one vendored copy can never
-- pair with a shell from another without saying so. A new major would have cost a
-- `core/<Name>Setup.lua` seam in all eleven consumers, nine of which will never draw a handle.
--
-- ── WHAT THE HOST STILL OWNS ─────────────────────────────────────────────────────────────────
--
-- Every string, where the strip sits, when it shows, whether a drag is allowed, what a right-click
-- means, and where the moved frame's position is saved. After the constructor returns, this file
-- never calls SetPoint, SetShown, Show, Hide or SetWidth of its own accord — both hosts defer
-- layout work around a protected frame to PLAYER_REGEN_ENABLED, and a widget that re-measured
-- itself on a timer or on an event would poke that frame from inside the library, where neither
-- host's combat contract can see it. `ApplyWidth` is a method the host calls, not a pass the
-- widget runs.
--
-- THE ONE EXCEPTION IS BIRTH, and it is deliberate rather than an oversight: the constructor ends
-- on handle:Hide(). A strip is born with no width and no anchor point, because placing and sizing
-- it are the host's calls, so a handle that returned visible would flash a zero-width box at the
-- parent's center until the host's first pass. AuraMaster's own copy hid its handle in the same
-- breath it built it. Nothing here shows it again; the host says when.
--
-- Depends on LibStub and on the Widgets shell, and on no addon framework. Like the shell, it takes
-- no dependency on LibKa0s-Media-1.0 and cannot: a vendored copy does not know which addon folder
-- it sits in, so the help mark's art arrives as a resolved path (`spec.helpIcon`).

local lib = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
if not lib then return end

local DRAG_MINOR = 2
-- Paired on the SHELL's minor as well as this file's own: a handle that attached to an older shell
-- would publish `lib.DragHandle` beside a `lib.MODULES` the shell owns, and nothing would say the
-- two came from different vendored copies.
if lib.__dragMinor and lib.__dragMinor >= DRAG_MINOR
  and lib.__dragShellMinor == lib.MINOR then return end
lib.__dragMinor      = DRAG_MINOR
lib.__dragShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.WidgetsDragHandle = DRAG_MINOR

-- The canonical values, published for the same reason `lib.ROW_BOX`'s are: a host that copies them
-- back into its own constants file is the drift this replaces.
--
-- ── THE MARK IS AN ART SIZE INSIDE A FRAME SIZE, AND THEY ARE NOT THE SAME NUMBER ────────────
--
-- HELP is the ART: 8px of texture, fixed, and it is not derived from anything at runtime. The
-- precedent it matches is still the dropdown's chevron -- `arrow:SetSize(12, 12)` at `RIGHT, -4`,
-- Widgets.lua:331-333 -- but it matches it in INK rather than in BOX, which is the correction this
-- number carries and the reason 12 was not the answer either.
--
-- A BOX IS NOT A WEIGHT. The chevron's art is the collection's `chevron-down`, whose glyph inks 44
-- of its 64 rows, so a 12px box of it draws 8.25px of mark; this mark's art is `help`, whose "?"
-- inks all 64. Both measurements are of the catalog TGAs, which is what both hosts resolve; the
-- Blizzard fallback below is a filled disc and is certainly no more inset than the "?". A 12px box of
-- THIS art is 12px of drawn mark, half again the chevron it was said to match, and both copies'
-- 14 was 14. Beside the small label face's cap height -- FRIZQT__ at 10px, a cap of roughly 7px --
-- 12px of ink measures about 1.7x the text it annotates, which is the owner's complaint stated as
-- a number. At 8 the ink is the chevron's ink, about 1.1x that cap, and the strip stops being led
-- by its "?".
--
-- 8 IS A FLOOR AND NOT A DIRECTION OF TRAVEL. Below it the "?" loses the gap between its hook and
-- its dot at 100% UI scale, and a mark nobody can read is the same failure from the other side.
-- The click target does not move with the art (HELP_HIT), so shrinking it costs no hittability.
--
-- The cap height above is the REASON for a fixed number, not an input to one. An earlier draft
-- computed the art from the label's font height and capped it at 12 -- a derivation in name only,
-- since the cap equalled the default, and it rested on an unevidenced, locale-dependent claim
-- about GameFontNormalSmall. Nothing here reads a font.
--
-- HELP_HIT is the FRAME the art sits in, and it is deliberately bigger -- the full strip height.
-- This control is the only right-click affordance on AuraMaster's strip and it opens a settings
-- page, so it has to stay easy to hit; a frame the size of its own 8px art is an 8x8 target. The
-- same fix was made to O.IdList's remove icon one layer down (OptionsWidgets.lua, ID_REMOVE_SIZE
-- 16 inside ID_REMOVE_HIT 26): art shrinks, frame does not, and the difference is a gutter the art
-- is centered in. Here that gutter is (18 - 8) / 2 = 5px on all four sides.
--
-- HELP_CLEAR is the empty space the strip keeps between the label's BOUND and the mark's INK. It is
-- the number the complaint was actually about: before this widget existed both copies spent
-- PAD / 2 + HELP - HELP_INSET = 8px there, and because the mark's own footprint appeared on both
-- sides of that expression, shrinking the art from 14 to 12 left the 8 exactly where it was. It is
-- spelled out here so it can be changed on its own.
--
-- RESERVE is what falls out of the three: what each side of the label keeps clear, and therefore
-- half of everything Measure() adds to the label. It is computed rather than typed so it cannot
-- drift from its own terms.
lib.DRAG_HANDLE = {
  HEIGHT     = 18,   -- the strip's height
  GAP        = 2,    -- the gap a host leaves between the strip and the frame it moves
  HELP       = 8,    -- the mark's ART: the texture's edge
  HELP_HIT   = 18,   -- the mark's FRAME: the click target, the full strip height
  HELP_INSET = 4,    -- px from the strip's right edge to the mark's FRAME
  HELP_CLEAR = 12,   -- px of empty space between the label's bound and the mark's art
}

-- The gutter the art is centered in, and the reserve each side of the label gives up.
--
-- NOT FLOORED, and that is a correctness point rather than a tidy-up. The art is placed by
-- SetPoint CENTER, which splits HELP_HIT - HELP in half exactly; a floored gutter would advertise
-- a clearance the layout does not draw the moment those two numbers differ by an odd amount. The
-- arithmetic below and dhBuildHelp's SetPoint now say the same thing at every pair of values.
lib.DRAG_HANDLE.HELP_GUTTER =
  (lib.DRAG_HANDLE.HELP_HIT - lib.DRAG_HANDLE.HELP) / 2
lib.DRAG_HANDLE.RESERVE =
  lib.DRAG_HANDLE.HELP_INSET
  + lib.DRAG_HANDLE.HELP_HIT
  - lib.DRAG_HANDLE.HELP_GUTTER
  + lib.DRAG_HANDLE.HELP_CLEAR

-- The last rung of the help mark's ladder, beside CHEVRON_FALLBACK and for the same reason: a host
-- with no LibKa0s-Media passes no `helpIcon` and still gets a mark.
local HELP_FALLBACK = "Interface\\FriendsFrame\\InformationIcon"

-- THE OTHER HALF OF THE SAME COMPLAINT: how loud the mark is, not only how big. Both copies drew
-- the mark at full white -- the brightest thing on a strip whose own label is gold (1, 0.82, 0) on
-- a dark fill -- so the annotation out-shouted the text it annotates. The chevron does not: it
-- carries `arrow:SetVertexColor(0.7, 0.7, 0.72)` at Widgets.lua:335, set by the widget rather than
-- by the host, which is what makes shared white art wear the widget's gray instead of its own. The
-- mark takes the same tint from the same place.
--
-- VERTEX COLOR AND NOT ALPHA. Alpha would fade the mark toward the fill behind it, which changes
-- what it composites over; multiplying white art by a gray is what the chevron does and what the
-- catalog's art is built for (every icon is white with its shape in the alpha channel). The mark's
-- alpha stays 1.
--
-- AND IT BRIGHTENS ON HOVER WHERE A CLICK IS WIRED, which the chevron has no need of because the
-- whole dropdown is the button. Here the mark is its own Button -- a right-click opens AuraMaster's
-- Containers page -- so a mark dimmed at rest with no response to the cursor would read as
-- decoration. Full white on OnEnter, back to the resting tint on OnLeave.
--
-- BUT ONLY WHERE ONE IS. ConsumableMaster passes no `onRightClick`, and a mark that lit up under
-- the cursor there would be promising a control nothing is behind -- the same defect from the
-- other side. The over-tint is chosen from `spec.onRightClick` in dhBuildHelp, so the hover
-- response and the click register or decline together.
local HELP_TINT      = { 0.7, 0.7, 0.72 }
local HELP_TINT_OVER = { 1, 1, 1 }

-- ONE face, read by the code that DRAWS the label and by the code that MEASURES it. An earlier
-- draft drew the label in a hardcoded face and measured it in a separate `spec.measureFont`, so a
-- host that set one and not the other measured a width the strip did not draw and could run its
-- own label into the mark. `spec.labelFont` now sets both or neither.
local LABEL_FONT_DEFAULT = "GameFontNormalSmall"

-- The measuring FontStrings, one per face, never anchored to anything.
--
-- LOAD-BEARING, NOT TIDY. AuraMaster's label hangs off the strip, the strip off an anchor, and an
-- anchor attached to an engine container inherits its SECRET geometry -- reading the label's own
-- width answered a secret number and the width arithmetic raised out of combat. Measuring on a
-- string parented to a hidden frame of ours on UIParent is what that host already had to do, and
-- it is the widget's now. Module state, and safe: each is written and read inside one call.
local measurers = {}

--- The hidden FontString a label is measured on, in `face` (default `GameFontNormalSmall`).
--- A test replaces this function to measure on a stand-in.
--- @return table|nil  nil when the client cannot make one, which is a width of 0, not a raise
function lib.__DragHandleMeasurer(face)
  face = face or LABEL_FONT_DEFAULT
  if measurers[face] then return measurers[face] end
  if not CreateFrame then return nil end
  local host = CreateFrame("Frame", nil, UIParent)
  if not (host and host.CreateFontString) then return nil end
  if host.Hide then host:Hide() end
  local fs = host:CreateFontString(nil, "OVERLAY", face)
  if not (fs and fs.GetStringWidth) then return nil end
  measurers[face] = fs
  return fs
end

--- A host's numeric guard if it passed one, and a plain `tonumber` otherwise. AuraMaster passes
--- `NS.Secrets.NumberOr`; without it the guard is decorative in exactly the host that needs it.
local function dhNumber(spec, v, fallback)
  if spec.number then return spec.number(v, fallback) end
  return tonumber(v) or fallback
end

--- The width `text` takes in the label's face, or 0 when nothing can be measured. The face is the
--- one the label is DRAWN in; see LABEL_FONT_DEFAULT.
local function dhLabelWidth(spec, text)
  local fs = lib.__DragHandleMeasurer(spec.labelFont)
  if not fs then return 0 end
  fs:SetText(text or "")
  return dhNumber(spec, fs:GetStringWidth(), 0)
end

--- Four 1px strips rather than a BackdropTemplate, and that is not a style choice. Under an anchor
--- attached to another frame the strip's size can read secret, and SetBackdrop does arithmetic on
--- the size on every set and every resize. Four rectangles read nothing. A host that has its own
--- edge painter passes it as `spec.edge` and gets its own pixels.
local function dhDrawEdge(frame, size, r, g, b, a)
  if not frame.CreateTexture then return end
  local plan = {
    { "TOPLEFT",    "TOPRIGHT",    true  },
    { "BOTTOMLEFT", "BOTTOMRIGHT", true  },
    { "TOPLEFT",    "BOTTOMLEFT",  false },
    { "TOPRIGHT",   "BOTTOMRIGHT", false },
  }
  for _, e in ipairs(plan) do
    local tex = frame:CreateTexture(nil, "BORDER")
    if not (tex and tex.SetColorTexture) then return end
    tex:SetPoint(e[1], frame, e[1], 0, 0)
    tex:SetPoint(e[2], frame, e[2], 0, 0)
    if e[3] then tex:SetHeight(size) else tex:SetWidth(size) end
    tex:SetColorTexture(r, g, b, a)
  end
end

--- One tooltip entry, EVALUATED NOW rather than captured at build time, with the color it asked
--- for. Three shapes, and the third is the reason there is a shape at all:
---
---   "text"                    used as it stands, in its band's color
---   function() -> string|nil  called on every hover; a nil return drops the line entirely
---   { <either>, r, g, b }     the same, in a color of its own rather than its band's
---
--- The function form is what lets ConsumableMaster's footer say "Locked. Unlock the bar…" or
--- "Lock the bar…" from the same handle. The colored form is what lets AuraMaster keep its
--- conditional "Attached — set its offsets on the Layout page." line GOLD where it sits today: it
--- is a body line, in a white band, and a shape whose bands were each one color would have
--- recolored it on adoption or pushed it into the gray footer with a blank line above it.
--- @return string|nil text, number|nil r, number|nil g, number|nil b
local function dhEntry(v)
  local r, g, b
  if type(v) == "table" then v, r, g, b = v[1], v[2], v[3], v[4] end
  if type(v) == "function" then v = v() end
  if v == nil then return nil end
  return v, r, g, b
end

--- The lines of one band that survive this hover, in order, each carrying the color it will be
--- drawn in. Nothing is drawn here, because whether the footer's blank spacer is drawn at all
--- depends on how many came back.
local function dhBand(entries, r, g, b)
  local out
  for _, entry in ipairs(entries or {}) do
    local s, er, eg, eb = dhEntry(entry)
    if s then
      out = out or {}
      out[#out + 1] = { s, er or r, eg or g, eb or b }
    end
  end
  return out
end

--- Own the tooltip for THIS hover, by the frame actually under the cursor.
---
--- The OWNER is the host's call and it is a correctness knob, not a style one. AuraMaster's anchor
--- inherits DisableUntrustedLayoutScriptsTemplate and the restriction reaches every frame under it,
--- so the client refuses SetOwner on the strip or the mark ("Anchoring disallowed as dependent
--- object would inherit forbidden aspects"); it must own by UIParent at the cursor. ConsumableMaster
--- owns by the hovered frame -- ANCHOR_TOP off the strip, ANCHOR_TOPRIGHT off the mark, which is
--- why the descriptor may carry its own `owner` and `anchor` and not only the spec.
local function dhOwnTooltip(tip, frame, spec, t)
  local owner = t.owner or spec.tooltipOwner
  if owner == "cursor" then
    tip:SetOwner(UIParent, "ANCHOR_CURSOR")
  else
    tip:SetOwner(frame, t.anchor or spec.tooltipAnchor or "ANCHOR_TOP")
  end
end

--- The three-band shape both copies built out of different text: a gold title, white wrapped body
--- lines, then -- only when at least one survives -- a blank spacer and gray footer lines. Drawn
--- for `frame`, which is the frame hovered and therefore the frame a non-cursor owner owns by.
local function dhShowTooltip(frame, spec, t)
  local tip = GameTooltip
  if not (t and tip and tip.SetOwner and tip.SetText) then return end
  dhOwnTooltip(tip, frame, spec, t)
  local title, tr, tg, tb = dhEntry(t.title)
  tip:SetText(title or "", tr or 1, tg or 0.82, tb or 0)
  for _, l in ipairs(dhBand(t.body, 1, 1, 1) or {}) do tip:AddLine(l[1], l[2], l[3], l[4], true) end
  local footer = dhBand(t.footer, 0.6, 0.6, 0.6)
  if footer then
    tip:AddLine(" ")
    for _, l in ipairs(footer) do tip:AddLine(l[1], l[2], l[3], l[4], true) end
  end
  tip:Show()
end

local function dhHideTooltip()
  if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
end

--- NO CLICK REGISTRATION AT ALL without a handler, on either frame. ConsumableMaster's strip has
--- no right-click action, and a button registered for a click it does nothing with swallows it.
local function dhSetClick(frame, spec, gated)
  if not spec.onRightClick then return end
  frame:RegisterForClicks("RightButtonUp")
  frame:SetScript("OnClick", function(_, button)
    if gated and button ~= "RightButton" then return end
    spec.onRightClick()
  end)
end

--- Tint the mark, guarded on the METHOD as well as the texture: a headless mock's CreateTexture
--- can hand back something that draws nothing and answers nothing.
local function dhTint(icon, tint)
  if not (icon and icon.SetVertexColor) then return end
  icon:SetVertexColor(tint[1], tint[2], tint[3])
end

--- The help mark: a fixed icon rather than a line of hint text, so a one-element strip is not
--- forced wider by prose.
---
--- A BIG FRAME AROUND A SMALL TEXTURE. The Button is HELP_HIT square -- the strip's full height --
--- and the art is HELP square, centered, leaving HELP_GUTTER on every side. See lib.DRAG_HANDLE
--- for why those are two numbers, and HELP_TINT for why the art is dimmed rather than white.
---
--- It TAKES THE STRIP'S OWN DRAG SCRIPTS, so a drag that starts on the "?" moves the frame instead
--- of landing in a dead zone -- AuraMaster's copy did that and ConsumableMaster's did not -- and it
--- passes a right-click through when the host registered one. Its tooltip is `spec.helpTooltip`
--- when the host wrote a second descriptor and `spec.tooltip` when it did not, read on every hover
--- rather than captured here.
local function dhBuildHelp(handle, spec)
  local D = lib.DRAG_HANDLE
  local help = CreateFrame("Button", nil, handle)
  if not (help and help.SetSize) then return nil end
  help:SetSize(D.HELP_HIT, D.HELP_HIT)
  help:SetPoint("RIGHT", handle, "RIGHT", -D.HELP_INSET, 0)
  help:RegisterForDrag("LeftButton")
  help:SetScript("OnDragStart", handle:GetScript("OnDragStart"))
  help:SetScript("OnDragStop", handle:GetScript("OnDragStop"))
  local icon = help.CreateTexture and help:CreateTexture(nil, "OVERLAY")
  if icon and icon.SetTexture then
    icon:SetSize(D.HELP, D.HELP)
    icon:SetPoint("CENTER", help, "CENTER", 0, 0)
    icon:SetTexture(spec.helpIcon or HELP_FALLBACK)
    dhTint(icon, HELP_TINT)
    help.icon = icon
  end
  -- HOVER FEEDBACK FOLLOWS THE CLICK, and nothing else. The brighten is the line that says this
  -- mark is a control; on a host that wired no click it was advertising an action that does not
  -- exist. ConsumableMaster registers none -- dhSetClick above declines to register a click for
  -- the same reason -- so its mark stays at the resting tint and is what it actually is there: the
  -- anchor of a second tooltip. A host that passes `onRightClick` still gets the full-white
  -- response the control earns.
  local overTint = spec.onRightClick and HELP_TINT_OVER or HELP_TINT
  help:SetScript("OnEnter", function()
    dhTint(help.icon, overTint)
    dhShowTooltip(help, spec, spec.helpTooltip or spec.tooltip)
  end)
  help:SetScript("OnLeave", function()
    dhTint(help.icon, HELP_TINT)
    dhHideTooltip()
  end)
  dhSetClick(help, spec, false)
  return help
end

--- The strip's own chrome: a dark fill and a 1px gold edge, both guarded on the ANSWER rather than
--- on the method, because a headless mock's CreateTexture can hand back nil.
local function dhBuildChrome(handle, spec)
  local bg = handle.CreateTexture and handle:CreateTexture(nil, "BACKGROUND")
  if bg and bg.SetColorTexture then
    bg:SetAllPoints(handle)
    bg:SetColorTexture(0, 0, 0, 0.75)
    handle.bg = bg
  end
  local paintEdge = spec.edge or dhDrawEdge
  paintEdge(handle, 1, 1, 0.82, 0, 0.6)
end

--- The centered gold label, or nil where the client cannot make a FontString. Drawn in the same
--- face dhLabelWidth measures in -- see LABEL_FONT_DEFAULT, which is the whole point of the field.
---
--- BOUNDED ON BOTH SIDES, NOT JUST CENTERED, and the bound is RESERVE -- the same number Measure()
--- spends on each side of the label. A FontString with a CENTER point and nothing else has no
--- width of its own and grows both ways out of the strip, so a label longer than the strip runs
--- under the mark and past the gold edge. There are three ways to get one, and none of them is
--- exotic: a host floors the width at something narrower than the text (AuraMaster floors at one
--- element, ConsumableMaster at the bar), a host calls SetLabel with a longer string and does not
--- call ApplyWidth again -- which SetLabel deliberately does not do for it, because geometry beside
--- a protected frame is the host's to schedule -- and a client that cannot build a measurer at all
--- measures 0 while still drawing the real string. Bounded, the label truncates inside its own
--- reserve in every one of them and the mark keeps its clearance.
---
--- SetWordWrap(false) is what makes that a truncation rather than a second line: a bounded
--- FontString wraps by default, and a two-line label inside an 18px strip is its own bug. Both are
--- guarded on the method -- an older client, or a mock, need not have either.
local function dhBuildLabel(handle, spec)
  local face = spec.labelFont or LABEL_FONT_DEFAULT
  local label = handle.CreateFontString and handle:CreateFontString(nil, "OVERLAY", face)
  if not (label and label.SetPoint) then return nil end
  local reserve = lib.DRAG_HANDLE.RESERVE
  label:SetPoint("LEFT", handle, "LEFT", reserve, 0)
  label:SetPoint("RIGHT", handle, "RIGHT", -reserve, 0)
  if label.SetJustifyH then label:SetJustifyH("CENTER") end
  if label.SetWordWrap then label:SetWordWrap(false) end
  if label.SetMaxLines then label:SetMaxLines(1) end
  label:SetTextColor(1, 0.82, 0)
  handle.label = label
  return label
end

--- The two drag scripts, set on the strip -- and copied onto the mark by dhBuildHelp, which reads
--- them back off the strip rather than being handed them.
local function dhSetDragScripts(handle, spec)
  handle:SetScript("OnDragStart", function()
    if spec.canDrag and not spec.canDrag() then return end
    local mf = spec.moveFrame
    if not (mf and mf.StartMoving) then return end
    mf:StartMoving()
    handle.__dragging = true
    if spec.onDragStart then spec.onDragStart() end
  end)
  handle:SetScript("OnDragStop", function()
    if not handle.__dragging then return end
    handle.__dragging = nil
    local mf = spec.moveFrame
    if mf and mf.StopMovingOrSizing then mf:StopMovingOrSizing() end
    if spec.onDragStop then spec.onDragStop() end
  end)
end

--- The three methods a host calls. Attached per instance, because every field of the spec is.
local function dhAttachMethods(handle, spec)
  --- Re-text the strip. The width is NOT applied here: a host decides when it may touch geometry.
  function handle:SetLabel(text)
    self.__label = text or ""
    if self.label then self.label:SetText(self.__label) end
    return self
  end

  --- The strip's natural width: the label, plus what each side of it keeps clear. RESERVE is spent
  --- TWICE -- once on the right, where it pays for the mark's inset, its frame and the clearance
  --- in front of its art, and once on the left as the matching empty gap, which is what keeps the
  --- label optically centered. Both hosts wrote this expression out; neither does now.
  function handle:Measure()
    return dhLabelWidth(spec, self.__label) + lib.DRAG_HANDLE.RESERVE * 2
  end

  --- Set the width to the natural one, floored by `minWidth` -- ConsumableMaster's bar width,
  --- AuraMaster's element size. Called by the host, never by the widget.
  function handle:ApplyWidth(minWidth)
    local w = math.max(self:Measure(), dhNumber(spec, minWidth, 0))
    self:SetWidth(w)
    return w
  end
end

--- Build the strip a player drags a frame by.
---
--- @param parent table   the frame the strip is parented to
--- @param spec table
---   label       string            REQUIRED. The strip's centered text, already localized.
---   moveFrame   table             REQUIRED. The frame StartMoving/StopMovingOrSizing are called
---                                 on -- the host's anchor, or the bar itself.
---   name        string|nil        global frame name; anonymous without one. A named handle is
---                                 reachable from a macro, so a host that had one keeps it.
---   helpIcon    string|nil        resolved texture path for the mark; nil falls back.
---   canDrag     function|nil      asked at OnDragStart; a false answer moves nothing.
---   onDragStart function|nil      called once the move has started.
---   onDragStop  function|nil      called once it has stopped -- where a host saves the position.
---   onRightClick function|nil     without it NEITHER the strip NOR the mark registers for clicks.
---   tooltip     table|nil         the descriptor the STRIP shows, and the mark's too unless
---                                 `helpTooltip` says otherwise:
---                                   { title, body = {…}, footer = {…}, owner, anchor }
---                                 every band entry may be a string, a function called on each
---                                 hover whose nil return drops the line, or a
---                                 { <either>, r, g, b } table carrying its own color. No tooltip
---                                 without this.
---   helpTooltip table|nil         a SECOND descriptor, of the same shape, shown by the help mark
---                                 alone. A host with one tooltip for both frames writes only
---                                 `tooltip` and this stays absent; ConsumableMaster titles its
---                                 strip "Consumable Master" and its mark "Macro bar", with
---                                 different bodies and different anchors, and writes both.
---   tooltipOwner string|nil       the default for both descriptors: "cursor" owns by UIParent at
---                                 ANCHOR_CURSOR; anything else owns by the FRAME HOVERED -- the
---                                 strip on the strip, the mark on the mark. A descriptor's own
---                                 `owner` wins. See dhOwnTooltip -- this is correctness.
---   tooltipAnchor string|nil      the default "self" anchor point, overridden by a descriptor's
---                                 own `anchor`. Defaults to "ANCHOR_TOP".
---   edge        function|nil      the host's own 1px edge painter, called as
---                                 edge(frame, size, r, g, b, a). Defaults to four strips of ours.
---   number      function|nil      number(v, fallback) -- a secret-safe numeric guard.
---   labelFont   string|nil        the font object the label is DRAWN in AND measured in.
---                                 Defaults to "GameFontNormalSmall".
--- @return table|nil handle  nil with no parent and nil in a process with no CreateFrame
function lib.DragHandle(parent, spec)
  spec = spec or {}
  if not (parent and CreateFrame) then return nil end

  local handle = CreateFrame("Button", spec.name, parent)
  if not (handle and handle.SetHeight) then return nil end
  handle:SetHeight(lib.DRAG_HANDLE.HEIGHT)
  dhBuildChrome(handle, spec)
  dhBuildLabel(handle, spec)

  handle:EnableMouse(true)
  handle:RegisterForDrag("LeftButton")

  dhSetDragScripts(handle, spec)
  handle:SetScript("OnEnter", function() dhShowTooltip(handle, spec, spec.tooltip) end)
  handle:SetScript("OnLeave", dhHideTooltip)
  dhSetClick(handle, spec, true)

  handle.help = dhBuildHelp(handle, spec)
  dhAttachMethods(handle, spec)
  handle:SetLabel(spec.label)
  -- See "WHAT THE HOST STILL OWNS" at the top: the one visibility call this file makes, at birth,
  -- because a strip with no width and no anchor point would otherwise flash.
  handle:Hide()
  return handle
end
