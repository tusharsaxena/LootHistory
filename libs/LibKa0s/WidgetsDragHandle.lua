-- LibKa0s-Widgets-1.0 — the unlocked drag handle: a labeled strip with its marks ([?][settings][close]
-- from minor 15), dragged to move the frame it belongs to. Each minor's notes sit above DRAG_MINOR.
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
-- never calls SetPoint, SetShown, Show, Hide or SetWidth of its own accord (one exception from
-- minor 8, widened at minor 10, THE RE-FIT below) — both hosts defer
-- layout work around a protected frame to PLAYER_REGEN_ENABLED, and a widget that re-measured
-- itself on a timer or on an event would poke that frame from inside the library, where neither
-- host's combat contract can see it. `ApplyWidth` is a method the host calls, not a pass the
-- widget runs.
--
-- THE RE-FIT (minor 8, LK-09 of Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK,
-- decision D-12). A strip's width is measured in its label's face, and an owned strip's face is its
-- skin's: a skin switch, "Ignore fonts" or the outline setting changes the face under a width the
-- host measured in the old one, and a wider face truncated the title (the owner's image-43..45).
-- So once the HOST has fitted a strip (its first ApplyWidth), each repaint of the strip's skin
-- re-applies that same fit, with the floor the host last passed, in the new face. The width is
-- still the host's call: the widget only repeats the host's own last one, and a strip the host
-- never fitted is never sized. A host that sizes its strip itself (AuraMaster caps it and shortens
-- the name) passes `spec.onRefit`, which is called instead, under pcall, after every repaint. A
-- host that sizes the strip itself with SetWidth or SetSize after an ApplyWidth ends the default
-- re-fit until its next ApplyWidth: its own width is never overridden by a fit it no longer made
-- (AuraMaster's capped strips, which call SetWidth on one path and ApplyWidth on the other).
-- COMBAT: the re-fit can run in combat, because a repaint can (a skin pick is refused there, but an
-- external restyle is not). That is safe for the strip itself, which is not a protected frame, and
-- the measure reads through `spec.number`; it rests on no consumer anchoring a protected frame to
-- the strip (ConsumableMaster's bar sits beside its strip, not on it). A host that ever does MUST
-- pass `spec.onRefit` and defer the work to PLAYER_REGEN_ENABLED itself.
-- THE SHOW (minor 10, LK-M2-68, LibKa0s#68). A fit made at build is only as good as that moment: an
-- addon face the client has not loaded measures wrong (OptionsMedia.lua's FACES LOAD BEFORE THEY
-- DRAW), and the host may scale its frame later. KickCD's cast bar fits once, at build. So a strip
-- the default re-fit covers repeats the host's last fit each time it shows, out of combat only,
-- since a shown strip can follow a protected parent's state driver. `spec.onRefit` hosts size on
-- their own show path and are not called here.
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

-- Minor 5: `spec.level` (an offset over the parent's frame level, applied at birth before the
-- marks are built), `handle:ApplyLevel()` and `spec.ignoreParentAlpha` (frame-layering-§2, §3).
-- Minor 6: `spec.owner`, a registered skin owner: the strip's fill, edge, label and mark tints come
-- from that owner's skin (`handle.bg`, `handle.edge`, `text.accent`, `icon.tint`, `icon.hot`) and
-- follow its switches. Without one, or for an unregistered name, the strip is minor 5's.
-- Minor 7 (LK-08 of Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_LIBRARY_FOLLOWUPS, the owner's ruling
-- R-7, DECISIONS D-14): an owned strip's tooltip bands take its skin's tooltip colors, read at hover:
-- the title `gtip.title`, the body `gtip.value`, the footer `gtip.footer`. Ka0s Default's are the
-- gold, white and 0.6 gray minor 6 drew, an entry's own color still wins, and an owner-less strip's
-- tooltip is minor 6's.
-- Still minor 7 (LK-06a of the same run, ruling R-5, decisions D-02 and D-13; the shell's THE SCOPE
-- SWITCHES): an owned strip's label is drawn in its skin's body face (Oxanium under Ka0s Default)
-- and MEASURED in that face, so "Ignore fonts" gives it the template back, live; a host's
-- `spec.labelFont` is never touched. `spec.panel = true` puts the strip on its owner's settings page:
-- while that owner ignores its settings panel the strip is minor 5's, live both ways.
-- Minor 8 (LK-09 of Ka0sAddonsCommonTasks docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK, decision D-12):
-- the label's width is measured unbounded where the client can (GetUnboundedStringWidth), ceiled,
-- and Measure() adds `DRAG_HANDLE.FIT_SLACK` (2 px), so a fractional width, pixel snapping or an
-- outline never trips the ellipsis on an exact fit. The measurer sits on a SHOWN host parked off
-- screen (a hidden one may never load the face it is asked to measure) and wears the label's own
-- font: its font object, or its path, size and flags where it has none. A fitted strip re-fits
-- after each skin repaint, and `spec.onRefit` replaces that re-fit (THE RE-FIT above).
-- Minor 9: ApplyLevel and the repaint name their two marks, with no throwaway table per call
-- (LK-M2-PEEL of Ka0sAddonsCommonTasks docs/2026-10-31-FINDINGS_REMEDIATION).
-- Minor 10 (LK-M2-68 of the same run, LibKa0s#68): the measurer's host takes the strip's effective
-- scale for each measure (dhMatchScale), the measured text is written fresh, and a fitted strip
-- fits again on show (THE SHOW above). A strip at UIParent's scale measures what it did.
-- Minor 11 (cause L6 of Ka0sAddonsCommonTasks docs/2026-11-01-FULL_SKINNING): an owned strip with no
-- host art draws the Ka0s `info` and `close` icons on its marks, live on a repaint (dhMarkArt).
-- Minor 12 (cause L8 of Ka0sAddonsCommonTasks docs/2026-11-01-FULL_SKINNING): an owned strip wears the
-- skin's body face over a host's `spec.labelFont`, which is what Ignore fonts gives back.
-- Minor 13 (SF2-L1 of Ka0sAddonsCommonTasks docs/2026-11-06-REVENDOR_LIBKA0S_V1_89): the strip's own
-- four edges are one PHYSICAL pixel at any UI scale, re-sized on a scale change, through the shell's
-- lib.__pixelLine (Widgets minor 25), where they were one UI unit. A host's `spec.edge` is unchanged.
-- Minor 14 (LK-92B of Ka0sAddonsCommonTasks docs/2026-11-16-LIBKA0S_ISSUES_75_PLUS, LibKa0s#92): the
-- tooltip half (the descriptor's bands, its owner and the placement hook) peeled, unchanged, to
-- WidgetsDragHandleTip.lua, read through lib.__dragTipKit at hover time; then the strip's tooltip, and
-- its marks', attaches centered above the strip through LibKa0s-Tooltip-1.0 (below only without
-- room above: SR-L1 of the same bundle's smoke round 1), owned by UIParent, and `tooltipOwner`, `tooltipAnchor` and a descriptor's `owner` and
-- `anchor` are retired (accepted, not read). WidgetsDragHandleTip.lua's WHERE IT OPENS.
-- Also minor 14 (LK-86 of the same run, LibKa0s#86): `spec.settings` (true, or a function) opts the
-- strip into a settings mark, the close mark's twin, left of the X (else of the "?"), opening
-- `spec.onSettings` or the function, else the owner's registered opener (Core minor 18's
-- OpenSettings). Opt-in for this run: a third mark on every HUD strip would widen it at re-vendor.
-- Also minor 14 (SR-L2, smoke round 1, ruling 3): a mark with no host descriptor shows the library's
-- words (WidgetsDragHandleTip.lua's lib.DRAG_HANDLE_STRINGS, `spec.L`).
-- Minor 15 (AF-LK-01 of Ka0sAddonsCommonTasks docs/2026-11-19-ADOPTION_FEEDBACK, the owner's feedback on
-- the adoption smoke, image 6): the marks read [?][settings][close] left to right, the X in the corner
-- where the "?" sat, the window header's order (WidgetsHeader.lua: extras, settings, close). The
-- settings mark is standard: built unless `spec.settings == false`. The X still needs `spec.onClose`,
-- since only the host knows what closing its display means, and every host MUST pass one (the
-- standard's HUD header rule); a strip without it shows no X. The marks sit closer: each frame is
-- HELP_HIT = 14 wide (the strip's full HEIGHT tall), so the arts have 6px of air between them where
-- they had 10, and the corner art keeps its 9px from the strip's edge (HELP_INSET 6, the header's
-- PAD + its gutter). RESERVE is still 29; each further mark adds 14 where it added 18. The tints are
-- the window header's (WidgetsHeader.lua's paint, Core.MakeCloseButton): `icon.tint` at rest, the
-- "?" and the gear `text.link` under the pointer, the X `close.rest` / `close.hot`; the "?" lights on
-- every strip, as a header mark does. ApplyLevel re-levels the settings mark too (LibKa0s#96).
-- Minor 16 (SD-LK-97.5 and 97.1, LibKa0s#97): a host's `spec.edge` is called again, under pcall,
-- with the new `handle.edge` on each repaint; a strip runs the shell's owner check.
local DRAG_MINOR = 16
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
-- HELP_HIT is the WIDTH of the FRAME the art sits in, and it is deliberately bigger than the art;
-- the frame's height is the full strip HEIGHT. This control is the only right-click affordance on
-- AuraMaster's strip and it opens a settings page, so it has to stay easy to hit; a frame the size
-- of its own 8px art is an 8x8 target. The same fix was made to O.IdList's remove icon one layer
-- down (OptionsWidgets.lua, ID_REMOVE_SIZE 16 inside ID_REMOVE_HIT 26): art shrinks, frame does not,
-- and the difference is a gutter the art is centered in. Through minor 14 the frame was 18 square,
-- a 5px gutter all round, so three marks side by side put 10px of air between their arts, which the
-- owner read as gaps (AF-LK-01, image 6). From minor 15 it is 14 wide: a 3px gutter left and right,
-- 6px of air between two arts (the window header's 12px of air at its 12px art, brought down toward
-- this 8px art), and the frames still abut, so the strip has no dead pixel between its marks.
--
-- HELP_CLEAR is the empty space the strip keeps between the label's BOUND and the mark's INK. It is
-- the number the complaint was actually about: before this widget existed both copies spent
-- PAD / 2 + HELP - HELP_INSET = 8px there, and because the mark's own footprint appeared on both
-- sides of that expression, shrinking the art from 14 to 12 left the 8 exactly where it was. It is
-- spelled out here so it can be changed on its own.
--
-- RESERVE is what falls out of the three: what each side of the label keeps clear, and therefore
-- half of everything Measure() adds to the label. It is computed rather than typed so it cannot
-- drift from its own terms. At minor 15 HELP_INSET moved 4 -> 6 as HELP_HIT moved 18 -> 14, so the
-- corner art still sits HELP_INSET + HELP_GUTTER = 9px from the strip's edge (the window header's
-- PAD 6 plus its (18 - 12) / 2 gutter) and RESERVE is still 6 + 14 - 3 + 12 = 29: a strip with one
-- mark is exactly as wide as it was.
lib.DRAG_HANDLE = {
  HEIGHT     = 18,   -- the strip's height
  GAP        = 2,    -- the gap a host leaves between the strip and the frame it moves
  HELP       = 8,    -- the mark's ART: the texture's edge
  HELP_HIT   = 14,   -- the mark's FRAME width, the click target (minor 15; 18 through 14); height is HEIGHT
  HELP_INSET = 6,    -- px from the strip's right edge to the corner mark's FRAME (minor 15; 4 through 14)
  HELP_CLEAR = 12,   -- px of empty space between the label's bound and the leftmost mark's art
  FIT_SLACK  = 2,    -- minor 8: px Measure() adds to the label, so an exact fit never truncates
}

-- The gutter the art is centered in, and the reserve each side of the label gives up.
--
-- NOT FLOORED, and that is a correctness point rather than a tidy-up. The art is placed by
-- SetPoint CENTER, which splits HELP_HIT - HELP in half exactly; a floored gutter would advertise
-- a clearance the layout does not draw the moment those two numbers differ by an odd amount. The
-- arithmetic below and dhMarkFrame's SetPoint now say the same thing at every pair of values.
lib.DRAG_HANDLE.HELP_GUTTER =
  (lib.DRAG_HANDLE.HELP_HIT - lib.DRAG_HANDLE.HELP) / 2
lib.DRAG_HANDLE.RESERVE =
  lib.DRAG_HANDLE.HELP_INSET
  + lib.DRAG_HANDLE.HELP_HIT
  - lib.DRAG_HANDLE.HELP_GUTTER
  + lib.DRAG_HANDLE.HELP_CLEAR

-- THE MARKS' ORDER AND PITCH (minor 15). Left to right [?][settings][close], the window header's
-- order: the X in the corner at HELP_INSET, the gear's frame against the X's, the "?"'s against the
-- gear's (or against whichever of the two was built). Each mark is the same HELP_HIT frame around
-- the same HELP art. CLOSE_GAP is the px between two neighboring FRAMES, not two arts; at 0 the arts
-- sit 2 * HELP_GUTTER = 6px apart (10px through minor 14, with 18px frames). Through minor 14 the
-- order was [settings][close][?], the X and the gear left of the "?".
--
-- ONLY THE "?" IS IN RESERVE. RESERVE is what a strip with the "?" alone keeps clear, byte for byte
-- what minor 2 drew; each further mark (the X, the gear) adds HELP_HIT + CLOSE_GAP on EACH side
-- (dhReserve below), so the label stays centered and the clearance in front of the leftmost ink is
-- still HELP_CLEAR.
lib.DRAG_HANDLE.CLOSE_GAP = 0

-- The last rung of the help mark's ladder, beside CHEVRON_FALLBACK and for the same reason: a host
-- with no LibKa0s-Media passes no `helpIcon` and still gets a mark.
local HELP_FALLBACK = "Interface\\FriendsFrame\\InformationIcon"

-- The close mark's last rung, for the same reason: a host with no LibKa0s-Media passes no
-- `closeIcon` and still gets an X.
local CLOSE_FALLBACK = "Interface\\Buttons\\UI-StopButton"

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
-- AND IT LIGHTS ON HOVER, IN THE WINDOW HEADER'S COLORS (minor 15, AF-LK-01, the owner's images 7-9).
-- Through minor 14 the marks went full white (`icon.hot`) under the cursor, and the "?" only where
-- the host wired a right-click. The owner asked that a strip's marks look exactly like a window
-- header's (WidgetsHeader.lua), so the four colors are that file's and Core.MakeCloseButton's: at
-- rest `icon.tint` (Ka0s Default's 0.7 gray, which the chevron also wears); the "?" and the gear
-- under the pointer `text.link` (Ka0s Default's gold-orange, the header's HOT); the X at rest
-- `close.rest` (every skin's is its `icon.tint`) and under the pointer `close.hot` (the red). The
-- "?" lights on every strip, a host click or not: a header mark lights whatever is behind it, and
-- the "?" always answers the pointer with its tooltip and the strip's drag.
local HELP_TINT      = { 0.7, 0.7, 0.72 }   -- WidgetsHeader.lua's REST, Ka0s Default's `icon.tint`
local HELP_TINT_OVER = { 1, 0.5, 0 }        -- WidgetsHeader.lua's HOT, Ka0s Default's `text.link`
local CLOSE_TINT_OVER = { 1, 0.3, 0.3 }     -- Core.MakeCloseButton's CLOSE_HOT, `close.hot`

--- One mark's art: the host's, an owned strip's Ka0s icon (minor 11), else the client rung.
local function dhMarkArt(handle, spec, field, name, fallback)
  return spec[field] or lib.__ownedMark(spec.owner, name, handle.__panel) or fallback
end

-- The strip's colors as one palette (minor 6): these for a strip with no skin owner, the owner's
-- tokens for one with (dhPalette). Every paint reads the handle's palette, never a literal.
-- The tooltip bands' colors are the palette's too (minor 7): `title`, `body` and `footer`.
-- The X's pair is `closeTint` and `closeOver` (minor 15).
local DH_PAL = { bg = { 0, 0, 0, 0.75 }, edge = { 1, 0.82, 0, 0.6 }, label = { 1, 0.82, 0 },
                 tint = HELP_TINT, over = HELP_TINT_OVER, closeTint = HELP_TINT, closeOver = CLOSE_TINT_OVER,
                 title = { 1, 0.82, 0 }, body = { 1, 1, 1 }, footer = { 0.6, 0.6, 0.6 } }

--- The palette for `owner` and the Skin major, or the default palette and nil when `owner` is not a
--- registered skin owner (or the shell predates the check). The default palette with the Skin major
--- while a panel-scoped strip's owner ignores its settings panel (`panel`, minor 7).
local function dhPalette(owner, panel)
  local skinOf = lib.__skinOf
  local Skin = type(skinOf) == "function" and skinOf(owner) or nil
  if not Skin then return DH_PAL, nil end
  local panelOff = lib.__panelOff
  if type(panelOff) == "function" and panelOff(Skin, owner, panel) then return DH_PAL, Skin end
  local function tok(name, fallback) return Skin:Token(owner, name) or fallback end
  return { bg = tok("handle.bg", DH_PAL.bg), edge = tok("handle.edge", DH_PAL.edge),
           label = tok("text.accent", DH_PAL.label), tint = tok("icon.tint", HELP_TINT),
           over = tok("text.link", HELP_TINT_OVER), closeTint = tok("close.rest", HELP_TINT),
           closeOver = tok("close.hot", CLOSE_TINT_OVER), title = tok("gtip.title", DH_PAL.title),
           body = tok("gtip.value", DH_PAL.body), footer = tok("gtip.footer", DH_PAL.footer) }, Skin
end

-- ONE face, read by the code that DRAWS the label and by the code that MEASURES it. An earlier
-- draft drew the label in a hardcoded face and measured it in a separate `spec.measureFont`, so a
-- host that set one and not the other measured a width the strip did not draw and could run its
-- own label into the mark. `spec.labelFont` now sets both or neither.
local LABEL_FONT_DEFAULT = "GameFontNormalSmall"

-- The measuring FontStrings, one per face, never anchored to anything, on one host frame.
--
-- LOAD-BEARING, NOT TIDY. AuraMaster's label hangs off the strip, the strip off an anchor, and an
-- anchor attached to an engine container inherits its SECRET geometry -- reading the label's own
-- width answered a secret number and the width arithmetic raised out of combat. Measuring on a
-- string parented to a hidden frame of ours on UIParent is what that host already had to do, and
-- it is the widget's now. Module state, and safe: each is written and read inside one call.
--
-- THE HOST IS SHOWN, OFF SCREEN (minor 8). It was hidden, and the library's own font preload says
-- why that is wrong: the client may skip work for a hidden or fully transparent region
-- (OptionsScroll.lua's preloadFrame), so a first measure could come back in a fallback face. It is
-- parked the way preloadFrame parks its own: 1x1, alpha 1, shown, at TOPRIGHT of UIParent's TOPLEFT.
local measurers = {}
local measureHost

--- The one host every measuring FontString hangs off, built on first use.
local function dhMeasureHost()
  if measureHost then return measureHost end
  local host = CreateFrame("Frame", nil, UIParent)
  if not (host and host.CreateFontString) then return nil end
  if host.SetSize then host:SetSize(1, 1) end
  if host.SetPoint and UIParent then host:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -64, 0) end
  if host.SetAlpha then host:SetAlpha(1) end
  if host.Show then host:Show() end
  measureHost = host
  return host
end

--- The FontString a label is measured on, in `face` (default `GameFontNormalSmall`), and its host.
--- A test replaces this function to measure on a stand-in.
--- @return table|nil, table|nil  nil when the client cannot make one, which is a width of 0, not a raise
function lib.__DragHandleMeasurer(face)
  face = face or LABEL_FONT_DEFAULT
  if measurers[face] then return measurers[face], measureHost end
  if not CreateFrame then return nil end
  local host = dhMeasureHost()
  if not host then return nil end
  local fs = host:CreateFontString(nil, "OVERLAY", face)
  if not (fs and fs.GetStringWidth) then return nil end
  measurers[face] = fs
  return fs, host
end

--- A host's numeric guard if it passed one, and a plain `tonumber` otherwise. AuraMaster passes
--- `NS.Secrets.NumberOr`; without it the guard is decorative in exactly the host that needs it.
local function dhNumber(spec, v, fallback)
  if spec.number then return spec.number(v, fallback) end
  return tonumber(v) or fallback
end

-- Measurers wearing a skin face a label lent them (minor 7), so the next plain measure resets them.
local lent = setmetatable({}, { __mode = "k" })

--- Whether a font object still draws the path, size and flags a label answers (an object that
--- answers no path draws whatever it draws, and counts as the same).
local function dhObjectDraws(obj, path, size, flags)
  if type(obj.GetFont) ~= "function" then return true end
  local oPath, oSize, oFlags = obj:GetFont()
  return oPath == nil or (oPath == path and oSize == size and (oFlags or "") == (flags or ""))
end

--- Lend the measurer the label's own skin font (minor 7): its font object, or (minor 8) its path,
--- size and flags where the skin set it by path. Answers true when it lent one.
---
--- The object is lent only while it still draws what the label draws. In the client a FontString
--- built from a template keeps answering that template as its font object after SetFont(path),
--- so the label's own GetFont() is compared with the object's, and a mismatch lends the path.
local function dhLendFont(fs, label)
  local obj = label.GetFontObject and label:GetFontObject()
  local path, size, flags
  if label.GetFont then path, size, flags = label:GetFont() end
  local byPath = type(path) == "string" and type(size) == "number" and size > 0 and fs.SetFont
  if type(obj) == "table" and fs.SetFontObject then
    if not byPath or dhObjectDraws(obj, path, size, flags) then
      fs:SetFontObject(obj)
      return true
    end
  end
  if not byPath then return false end
  fs:SetFont(path, size, flags)
  return true
end

--- The measured string's width: unbounded where the client answers it (minor 8: a bounded string
--- answers its bound, not its text), the plain width otherwise.
local function dhRawWidth(fs)
  local unbounded = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
  if type(unbounded) == "number" then return unbounded end
  return fs:GetStringWidth()
end

--- Put the measuring host at the strip's effective scale (minor 10). The label is drawn at that
--- scale and every host scales its strip's parent, while the host sits on UIParent, so a client
--- that snaps glyph advances to device pixels answered a width for another scale: modeled over the
--- shipped faces that overran FIT_SLACK. An unreadable scale (a secret one reads 0 through the
--- host's guard) measures at UIParent's.
local function dhMatchScale(spec, handle, host)
  if not (host and host.SetScale and handle and handle.GetEffectiveScale) then return end
  if not (UIParent and UIParent.GetEffectiveScale) then return end
  local want = dhNumber(spec, handle:GetEffectiveScale(), 0)
  local base = dhNumber(spec, UIParent:GetEffectiveScale(), 0)
  host:SetScale((want > 0 and base > 0) and want / base or 1)
end

--- The width `text` takes in the label's face, ceiled, or 0 when nothing can be measured. The face
--- is the one the label is DRAWN in; see LABEL_FONT_DEFAULT. A label in its skin's face (minor 7)
--- lends the measurer its font first: the measurer is shared per template, so it is put back on
--- the template for the next label that wears none. The text is cleared first (minor 10): text set
--- before its face loaded stays as it was until it is set again, and the last measure may be the
--- same string.
local function dhLabelWidth(spec, text, label, handle)
  local fs, host = lib.__DragHandleMeasurer(spec.labelFont)
  if not fs then return 0 end
  dhMatchScale(spec, handle, host)
  local fonted = lib.__fonted
  if label and fonted and fonted[label] and dhLendFont(fs, label) then
    lent[fs] = true
  elseif lent[fs] and fs.SetFontObject then
    fs:SetFontObject(spec.labelFont or LABEL_FONT_DEFAULT)
    lent[fs] = nil
  end
  fs:SetText("")
  fs:SetText(text or "")
  return math.ceil(dhNumber(spec, dhRawWidth(fs), 0))
end

--- Four 1px strips rather than a BackdropTemplate, and that is not a style choice. Under an anchor
--- attached to another frame the strip's size can read secret, and SetBackdrop does arithmetic on
--- the size on every set and every resize. Four rectangles read nothing. A host that has its own
--- edge painter passes it as `spec.edge` and gets its own pixels. Answers the strips it drew
--- (minor 6), so a skinned strip recolors them rather than drawing four more. `size` is PHYSICAL
--- pixels (minor 13) through the shell's lib.__pixelLine; UI units under a shell without it.
local function dhDrawEdge(frame, size, r, g, b, a)
  local line = lib.__pixelLine
  if not frame.CreateTexture then return end
  local out = {}
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
    if type(line) == "function" then line(tex, frame, e[3], size)
    elseif e[3] then tex:SetHeight(size) else tex:SetWidth(size) end
    tex:SetColorTexture(r, g, b, a)
    out[#out + 1] = tex
  end
  return out
end

--- The tooltip half lives in WidgetsDragHandleTip.lua (peeled at minor 14), read at call time
--- through lib.__dragTipKit so the newest copy of that file is this handle's. A shell whose copy
--- has not attached it shows no tooltip. `DH_PAL` is the bands' palette for a handle with none.
local function dhShowTooltip(handle, frame, spec, t, key)
  local kit = lib.__dragTipKit
  if not t and key and kit and kit.default then t = kit.default(spec, key) end   -- minor 14, SR-L2
  if kit then kit.show(handle, frame, spec, t, DH_PAL) end
end

local function dhHideTooltip()
  local kit = lib.__dragTipKit
  if kit then kit.hide() end
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

--- One mark's frame (minor 15): a Button HELP_HIT wide and the strip's full HEIGHT tall, anchored
--- RIGHT against `beside`'s LEFT at CLOSE_GAP (the mark to its right), else in the strip's corner at
--- HELP_INSET, wearing the strip's own drag scripts so a drag that starts on a mark moves the frame
--- like one that starts on the strip, and holding HELP art at CENTER in the resting `tint`. nil
--- where the client cannot make the frame.
---
--- A FRAME WIDER THAN ITS ART, AND AS TALL AS THE STRIP. See lib.DRAG_HANDLE for why those are two
--- numbers, and HELP_TINT for the colors.
local function dhMarkFrame(handle, beside, art, tint)
  local D = lib.DRAG_HANDLE
  local btn = CreateFrame("Button", nil, handle)
  if not (btn and btn.SetSize) then return nil end
  btn:SetSize(D.HELP_HIT, D.HEIGHT)
  if beside then
    btn:SetPoint("RIGHT", beside, "LEFT", -D.CLOSE_GAP, 0)
  else
    btn:SetPoint("RIGHT", handle, "RIGHT", -D.HELP_INSET, 0)
  end
  btn:RegisterForDrag("LeftButton")
  btn:SetScript("OnDragStart", handle:GetScript("OnDragStart"))
  btn:SetScript("OnDragStop", handle:GetScript("OnDragStop"))
  local icon = btn.CreateTexture and btn:CreateTexture(nil, "OVERLAY")
  if icon and icon.SetTexture then
    icon:SetSize(D.HELP, D.HELP)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    icon:SetTexture(art)
    dhTint(icon, tint)
    btn.icon = icon
  end
  return btn
end

--- A mark's hover: `over` (a palette key) and the tooltip on enter, `rest` and no tooltip on leave.
--- The tints are read from the handle's palette at fire time (minor 6), so a skin switch reaches the
--- next hover.
local function dhMarkHover(handle, btn, spec, t, key, rest, over)
  btn:SetScript("OnEnter", function()
    dhTint(btn.icon, handle.__pal[over])
    dhShowTooltip(handle, btn, spec, t, key)
  end)
  btn:SetScript("OnLeave", function()
    dhTint(btn.icon, handle.__pal[rest])
    dhHideTooltip()
  end)
end

--- The close mark, built only for a host that passes `spec.onClose`; nil otherwise, and nil where
--- the client cannot make the frame. Every host MUST pass one (minor 15: the standard's HUD header
--- rule); only the host knows what closing its display means, so the library draws no X it could
--- not honor.
---
--- THE CORNER MARK (minor 15), where the "?" sat through minor 14: the window header's order puts
--- close outermost. It rests in `close.rest` and lights `close.hot`, as Core.MakeCloseButton's X.
---
--- THE CLICK IS THE LEFT BUTTON'S. A left click calls `spec.onClose`; a right click is passed to
--- `spec.onRightClick` when the host wired one, as the "?" passes it, so the X is not a dead zone
--- for the strip's own right-click either. With no right-click the X registers the left alone. A
--- drag is not a click: the client does not fire OnClick for a press that became a drag. Its tooltip
--- is `spec.closeTooltip`, falling back to `spec.tooltip`, read on every hover.
local function dhBuildClose(handle, spec)
  if not spec.onClose then return nil end
  local btn = dhMarkFrame(handle, nil, dhMarkArt(handle, spec, "closeIcon", "close", CLOSE_FALLBACK),
    handle.__pal.closeTint)
  if not btn then return nil end
  dhMarkHover(handle, btn, spec, spec.closeTooltip or spec.tooltip, "CLOSE_TIP", "closeTint", "closeOver")
  if spec.onRightClick then
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  else
    btn:RegisterForClicks("LeftButtonUp")
  end
  btn:SetScript("OnClick", function(_, button)
    if button == "LeftButton" then
      spec.onClose()
    elseif button == "RightButton" and spec.onRightClick then
      spec.onRightClick()
    end
  end)
  return btn
end

-- The settings mark's last rung (minor 14), as CLOSE_FALLBACK is the X's.
local SETTINGS_FALLBACK = "Interface\\Buttons\\UI-OptionsButton"

--- The settings mark's click: `spec.settings` when it is a function, else `spec.onSettings`, else the
--- owner's registered opener (Core minor 18), each under pcall.
local function dhOpenSettings(spec)
  local fn = type(spec.settings) == "function" and spec.settings or spec.onSettings
  if type(fn) == "function" then
    local ok, err = pcall(fn)
    if not ok and type(geterrorhandler) == "function" then geterrorhandler()(err) end
    return
  end
  local core = LibStub("LibKa0s-Core-1.0", true)
  if core and type(core.OpenSettings) == "function" then core.OpenSettings(spec.settingsOwner or spec.owner) end
end

--- Whether this strip carries the settings mark: every strip from minor 15 (opt-in at 14) unless the
--- host passes `spec.settings = false`. Read by the builder and by dhReserve, so they cannot disagree.
local function dhHasSettings(spec)
  return spec.settings ~= false
end

--- The settings mark (minor 14; standard from minor 15): the X's twin in frame, art size, drag
--- scripts and right-click pass-through, anchored against the X (else in the corner), resting in
--- `icon.tint` and lighting `text.link`, the window header's gear. Its tooltip is
--- `spec.settingsTooltip`, falling back to `spec.tooltip`.
local function dhBuildSettings(handle, spec)
  if not dhHasSettings(spec) then return nil end
  local btn = dhMarkFrame(handle, handle.close,
    dhMarkArt(handle, spec, "settingsIcon", "settings", SETTINGS_FALLBACK), handle.__pal.tint)
  if not btn then return nil end
  dhMarkHover(handle, btn, spec, spec.settingsTooltip or spec.tooltip, "SETTINGS_TIP", "tint", "over")
  if spec.onRightClick then btn:RegisterForClicks("LeftButtonUp", "RightButtonUp") else btn:RegisterForClicks("LeftButtonUp") end
  btn:SetScript("OnClick", function(_, button)
    if button == "LeftButton" then return dhOpenSettings(spec) end
    if button == "RightButton" and spec.onRightClick then spec.onRightClick() end
  end)
  return btn
end

--- The help mark: a fixed icon rather than a line of hint text, so a one-element strip is not
--- forced wider by prose. The LEFTMOST mark from minor 15, against the gear (else the X, else the
--- corner).
---
--- It takes the strip's drag scripts (dhMarkFrame), so a drag that starts on the "?" moves the frame
--- instead of landing in a dead zone, and it passes a right-click through when the host registered
--- one. It lights `text.link` under the pointer on every strip (minor 15; through 14 it lit only
--- where `spec.onRightClick` was wired, in `icon.hot`). Its tooltip is `spec.helpTooltip` when the
--- host wrote a second descriptor and `spec.tooltip` when it did not, read on every hover rather
--- than captured here.
local function dhBuildHelp(handle, spec)
  local help = dhMarkFrame(handle, handle.settings or handle.close,
    dhMarkArt(handle, spec, "helpIcon", "info", HELP_FALLBACK), handle.__pal.tint)
  if not help then return nil end
  dhMarkHover(handle, help, spec, spec.helpTooltip or spec.tooltip, "HELP_TIP", "tint", "over")
  dhSetClick(help, spec, false)
  return help
end

--- What each side of the label keeps clear on THIS strip: RESERVE (the "?"), plus HELP_HIT +
--- CLOSE_GAP for each further mark, the X where the host passed `onClose` and the gear unless it
--- passed `settings = false` (minor 15). Read by dhBuildLabel and by Measure, so the bound the label
--- truncates at and the width the strip is given cannot disagree.
local function dhReserve(spec)
  local D = lib.DRAG_HANDLE
  local r = D.RESERVE
  if spec.onClose then r = r + D.HELP_HIT + D.CLOSE_GAP end
  if dhHasSettings(spec) then r = r + D.HELP_HIT + D.CLOSE_GAP end
  return r
end

--- The strip's own chrome: a dark fill and a 1px gold edge, both guarded on the ANSWER rather than
--- on the method, because a headless mock's CreateTexture can hand back nil.
local function dhBuildChrome(handle, spec)
  local pal = handle.__pal
  local bg = handle.CreateTexture and handle:CreateTexture(nil, "BACKGROUND")
  if bg and bg.SetColorTexture then
    bg:SetAllPoints(handle)
    bg:SetColorTexture(pal.bg[1], pal.bg[2], pal.bg[3], pal.bg[4])
    handle.bg = bg
  end
  local e = pal.edge
  handle.__edgeFn = type(spec.edge) == "function" and spec.edge or nil
  if handle.__edgeFn then return spec.edge(handle, 1, e[1], e[2], e[3], e[4]) end
  handle.__edges = dhDrawEdge(handle, 1, e[1], e[2], e[3], e[4])
end

--- The label's face (minor 7): the skin's body face while the strip is skinned, the template back
--- otherwise. A host's `spec.labelFont` is that template (minor 12).
local function dhFontLabel(handle, owner, Skin)
  local skinFont = lib.__skinFont
  if not handle.label or type(skinFont) ~= "function" then return end
  skinFont(handle.label, owner, handle.__pal ~= DH_PAL and Skin or nil,
    handle.__labelFont or LABEL_FONT_DEFAULT)
end

--- THE RE-FIT (minor 8): the host's `spec.onRefit(handle)` under pcall where it passed one, else
--- the host's own last fit again (ApplyWidth with its last floor) once the host has fitted the strip.
local function dhRefit(handle)
  local onRefit = handle.__onRefit
  if onRefit then
    local ok, err = pcall(onRefit, handle)
    if not ok and type(geterrorhandler) == "function" then geterrorhandler()(err) end
    return
  end
  if handle.__fitted then handle:ApplyWidth(handle.__fitFloor) end
end

--- The marks' art again, for a panel-scoped strip: its Scope may have moved since the build (minor 11).
local function dhMarksArt(handle)
  local spec = handle.__markSpec
  if not spec then return end
  local h, c = handle.help and handle.help.icon, handle.close and handle.close.icon
  if h then h:SetTexture(dhMarkArt(handle, spec, "helpIcon", "info", HELP_FALLBACK)) end
  if c then c:SetTexture(dhMarkArt(handle, spec, "closeIcon", "close", CLOSE_FALLBACK)) end
  local g = handle.settings and handle.settings.icon
  if g then g:SetTexture(dhMarkArt(handle, spec, "settingsIcon", "settings", SETTINGS_FALLBACK)) end
end

--- Repaint a skinned strip from its owner's skin (minor 6): re-run after each skin switch, then
--- re-fit it in its new face (minor 8). A host's own `spec.edge` painter is called again with the new
--- color (minor 16), so it recolors what it drew.
local function dhRepaint(handle, owner)
  local pal, Skin = dhPalette(owner, handle.__panel)
  handle.__pal = pal
  dhFontLabel(handle, owner, Skin)
  if handle.bg then handle.bg:SetColorTexture(pal.bg[1], pal.bg[2], pal.bg[3], pal.bg[4]) end
  local e = pal.edge
  for _, tex in ipairs(handle.__edges or {}) do tex:SetColorTexture(e[1], e[2], e[3], e[4]) end
  local ok, err = true, nil
  if handle.__edgeFn then ok, err = pcall(handle.__edgeFn, handle, 1, e[1], e[2], e[3], e[4]) end
  if not ok and type(geterrorhandler) == "function" then geterrorhandler()(err) end
  if handle.label then handle.label:SetTextColor(pal.label[1], pal.label[2], pal.label[3]) end
  if handle.help then dhTint(handle.help.icon, pal.tint) end
  if handle.close then dhTint(handle.close.icon, pal.closeTint) end
  if handle.settings then dhTint(handle.settings.icon, pal.tint) end
  dhMarksArt(handle)
  dhRefit(handle)
end

--- The centered gold label, or nil where the client cannot make a FontString. Drawn in the same
--- face dhLabelWidth measures in -- see LABEL_FONT_DEFAULT, which is the whole point of the field.
---
--- BOUNDED ON BOTH SIDES, NOT JUST CENTERED, and the bound is the strip's reserve (dhReserve:
--- RESERVE, widened by each further mark: the X, the gear) -- the same number Measure() spends on
--- each side of the label. A FontString with a CENTER point and nothing else has no
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
  local reserve = dhReserve(spec)
  label:SetPoint("LEFT", handle, "LEFT", reserve, 0)
  label:SetPoint("RIGHT", handle, "RIGHT", -reserve, 0)
  if label.SetJustifyH then label:SetJustifyH("CENTER") end
  if label.SetWordWrap then label:SetWordWrap(false) end
  if label.SetMaxLines then label:SetMaxLines(1) end
  local c = handle.__pal.label
  label:SetTextColor(c[1], c[2], c[3])
  handle.label = label
  return label
end

--- The two drag scripts, set on the strip -- and copied onto every mark by dhMarkFrame, which reads
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

--- One mark, where the client built it, at `level`.
local function dhLevelMark(mark, level)
  if mark and mark.SetFrameLevel then mark:SetFrameLevel(level) end
end

--- THE LEVEL (minor 5). With a numeric `spec.level`, the handle's frame level becomes the parent's
--- level plus that offset, read through the host's numeric guard: a secret or non-number answer
--- reads 0 and is never computed on. Answers the level written, or nil when there was nothing to
--- write -- no spec.level, or a client without the methods. `parent` is the constructor's at birth
--- and the handle's CURRENT parent (GetParent) in ApplyLevel, so a re-parented strip follows.
---
--- WHY AN OFFSET. A child is born at its parent's level + 1, and a display that builds its content
--- after its strip, or raises its content's levels, draws that content OVER the strip a player must
--- find to drag it (frame-layering-§2, XS-05). An offset over the parent survives the parent
--- moving; an absolute number does not.
local function dhLevel(handle, spec, parent)
  if type(spec.level) ~= "number" then return nil end
  if not handle.SetFrameLevel then return nil end
  local raw = parent and parent.GetFrameLevel and parent:GetFrameLevel()
  local base = dhNumber(spec, raw, 0)
  if type(base) ~= "number" then base = 0 end
  local lvl = base + spec.level
  handle:SetFrameLevel(lvl)
  return lvl
end

--- PARENT ALPHA (minor 5). A display that fades its content does not fade the strip: true calls
--- SetIgnoreParentAlpha(true) on the handle, and the marks are its children and follow it.
local function dhParentAlpha(handle, spec)
  if spec.ignoreParentAlpha ~= true then return end
  if type(handle.SetIgnoreParentAlpha) == "function" then handle:SetIgnoreParentAlpha(true) end
end

--- THE HOST'S OWN WIDTH (minor 8). SetWidth and SetSize on the instance clear the fit, so a host
--- that sizes the strip itself after an ApplyWidth is not re-fitted over (THE RE-FIT at the top).
--- Each calls the frame's own method; ApplyWidth goes through SetWidth and then re-marks the fit.
local function dhShadowSizing(handle)
  for _, name in ipairs({ "SetWidth", "SetSize" }) do
    local raw = handle[name]
    if type(raw) == "function" then
      handle[name] = function(self, ...)
        self.__fitted = nil
        return raw(self, ...)
      end
    end
  end
end

--- THE SHOW (minor 10, at the top of the file): repeat the host's last fit when the strip shows.
local function dhFitOnShow(handle)
  if not handle.HookScript then return end
  handle:HookScript("OnShow", function(self)
    if not self.__fitted or self.__onRefit then return end
    if InCombatLockdown and InCombatLockdown() then return end
    self:ApplyWidth(self.__fitFloor)
  end)
end

--- The methods a host calls. Attached per instance, because every field of the spec is.
local function dhAttachMethods(handle, spec)
  dhShadowSizing(handle)
  --- Re-text the strip. The width is NOT applied here: a host decides when it may touch geometry.
  function handle:SetLabel(text)
    self.__label = text or ""
    if self.label then self.label:SetText(self.__label) end
    return self
  end

  --- The strip's natural width: the label (ceiled, plus FIT_SLACK from minor 8), plus what each
  --- side of it keeps clear. The reserve is spent TWICE -- once on the right, where it pays for the marks' inset, their frames and the
  --- clearance in front of the leftmost art, and once on the left as the matching empty gap, which
  --- is what keeps the label optically centered. Both hosts wrote this expression out; neither
  --- does now.
  function handle:Measure()
    return dhLabelWidth(spec, self.__label, self.label, self) + lib.DRAG_HANDLE.FIT_SLACK + dhReserve(spec) * 2
  end

  --- What each side of the label keeps clear on this strip: DRAG_HANDLE.RESERVE for the "?", plus
  --- HELP_HIT + CLOSE_GAP for the X and again for the gear (minor 15). Published so a host that reasons about the
  --- strip's width reads the number rather than restating the arithmetic.
  function handle:Reserve()
    return dhReserve(spec)
  end

  --- Set the width to the natural one, floored by `minWidth` -- ConsumableMaster's bar width,
  --- AuraMaster's element size. Called by the host; from minor 8 the widget repeats the host's
  --- last call, with the same floor, after each repaint of its skin (THE RE-FIT at the top).
  --- The flags are written after the SetWidth below, because the host's own SetWidth (the shadow
  --- dhShadowSizing puts on the instance) clears them.
  function handle:ApplyWidth(minWidth)
    local w = math.max(self:Measure(), dhNumber(spec, minWidth, 0))
    self:SetWidth(w)
    self.__fitted, self.__fitFloor = true, minWidth
    return w
  end

  --- Re-apply `spec.level` (minor 5) over the parent's CURRENT level, and set every mark (the "?",
  --- the X and, from minor 15, the gear: LibKa0s#96) to the handle's level + 1 explicitly. A host calls it after it re-levels or re-parents the handle's
  --- parent -- SetParent re-derives levels (XS-18) -- never only in a memoized restyle that may
  --- skip it. Without a numeric spec.level it writes nothing and answers false.
  function handle:ApplyLevel()
    local lvl = dhLevel(self, spec, self.GetParent and self:GetParent())
    if not lvl then return false end
    dhLevelMark(self.help, lvl + 1)
    dhLevelMark(self.close, lvl + 1)
    dhLevelMark(self.settings, lvl + 1)   -- minor 15, LibKa0s#96
    return true
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
---   onClose     function|nil      minor 3. Builds the close mark (an X), from minor 15 in the
---                                 strip's corner (rightmost), and calls this on its left click.
---                                 Every host MUST pass one (the standard's HUD header rule): it
---                                 hides or disables the display and keeps its settings. Without it
---                                 no X is built, never a mark that does nothing.
---   closeIcon   string|nil        resolved texture path for the X; nil falls back.
---   settings    true|function|false|nil minor 14 (LibKa0s#86). The settings mark, left of the X
---                                 (else in the corner); a left click calls the function, else
---                                 `onSettings`, else LibKa0s-Core-1.0's OpenSettings(`settingsOwner`
---                                 or `owner`), the opener the addon's launcher registered. Standard
---                                 from minor 15: built unless this is `false` (opt-in at 14).
---   onSettings  function|nil      minor 14. What the settings mark opens, unless `settings` is one.
---   settingsOwner string|nil      minor 14. The registry key, where it is not `owner`.
---   settingsIcon string|nil       minor 14. Resolved texture path for the mark; nil falls back.
---   settingsTooltip table|nil     minor 14. The mark's own descriptor; `tooltip` without it, and
---                                 DRAG_HANDLE_STRINGS.SETTINGS_TIP without either.
---   closeTooltip table|nil        a descriptor of the tooltip shape, shown by the X alone; the X
---                                 shows `tooltip` without it, else Tooltip's CloseTip (minor 14).
---   tooltip     table|nil         the descriptor the STRIP shows, and the mark's too unless
---                                 `helpTooltip` says otherwise:
---                                   { title, body = {…}, footer = {…}, owner, anchor, place }
---                                 (`owner` and `anchor` retired at minor 14, `place` at Tip minor 2:
---                                 accepted, not read)
---                                 every band entry may be a string, a function called on each
---                                 hover whose nil return drops the line, or a
---                                 { <either>, r, g, b } table carrying its own color. No tooltip
---                                 on the strip without this (its marks: DRAG_HANDLE_STRINGS).
---   helpTooltip table|nil         a SECOND descriptor, of the same shape, shown by the help mark
---                                 alone. A host with one tooltip for both frames writes only
---                                 `tooltip` and this stays absent; ConsumableMaster titles its
---                                 strip "Consumable Master" and its mark "Macro bar", with
---                                 different bodies and different anchors, and writes both.
---   tooltipOwner string|nil       RETIRED at minor 14 (accepted, not read). Every tooltip is owned
---                                 by UIParent at ANCHOR_NONE and attached centered above the strip
---                                 (LibKa0s-Tooltip-1.0's PlaceAttached; WidgetsDragHandleTip.lua).
---   tooltipAnchor string|nil      RETIRED at minor 14, as `tooltipOwner`.
---   tooltipPlace function|nil     minor 4. RETIRED at WidgetsDragHandleTip minor 2 (accepted, never
---                                 called; deprecated, a host drops it): the strip's tooltip and its
---                                 marks' always attach centered above the strip, below only without
---                                 room. Through Tip minor 1 it was called after Show and kept its
---                                 point on a literal `true`. A descriptor's `place` is retired with it.
---   edge        function|nil      the host's own 1px edge painter, called as
---                                 edge(frame, size, r, g, b, a). Defaults to four strips of ours.
---                                 Called again with an owned strip's new `handle.edge` on each
---                                 repaint (minor 16), so it recolors what it drew, never adds more.
---   number      function|nil      number(v, fallback) -- a secret-safe numeric guard.
---   labelFont   string|nil        the font object the label is DRAWN in AND measured in.
---                                 Defaults to "GameFontNormalSmall".
---   level       number|nil        minor 5. The handle's frame level as an OFFSET over
---                                 parent:GetFrameLevel(), applied at birth before the
---                                 marks are built, so the marks are born at handle + 1. nil
---                                 keeps minor 4's implicit parent + 1. See handle:ApplyLevel().
---   ignoreParentAlpha boolean|nil minor 5. true calls SetIgnoreParentAlpha(true) on the handle, so
---                                 a display that fades its content does not fade the strip a
---                                 player must find. The marks are its children and follow it.
---   owner       string|nil        minor 6. A registered skin owner (the addon folder name): the
---                                 strip's colors follow that owner's skin, its tooltip's
---                                 band colors too from minor 7 (`gtip.title`, `gtip.value`,
---                                 `gtip.footer`). Not a tooltip owner -- that is `tooltipOwner` and
---                                 a descriptor's own `owner`. From minor 7 the label is drawn and
---                                 measured in that skin's body face; `labelFont` is then its
---                                 template, which Ignore fonts gives back (minor 12).
---   panel       boolean|nil       minor 7. true: the strip sits on the owner's settings page, so
---                                 while the owner ignores its settings panel it is minor 5's.
---   onRefit     function|nil      minor 8. onRefit(handle), called under pcall after every repaint
---                                 of the owner's skin INSTEAD of the default re-fit (ApplyWidth
---                                 with the host's last floor), for a host that sizes or shortens
---                                 the strip itself. Never called on an owner-less strip.
---   L           table|nil         minor 14 (SR-L2): HELP_TIP, CLOSE_TIP, SETTINGS_TIP, rawget.
--- @return table|nil handle  nil with no parent and nil in a process with no CreateFrame
function lib.DragHandle(parent, spec)
  spec = spec or {}
  if not (parent and CreateFrame) then return nil end

  local handle = CreateFrame("Button", spec.name, parent)
  if not (handle and handle.SetHeight) then return nil end
  handle:SetHeight(lib.DRAG_HANDLE.HEIGHT)
  local Skin
  handle.__panel, handle.__labelFont = spec.panel == true, spec.labelFont
  handle.__onRefit = type(spec.onRefit) == "function" and spec.onRefit or nil
  handle.__markSpec = handle.__panel and spec or nil
  handle.__pal, Skin = dhPalette(spec.owner, handle.__panel)
  -- Before anything is built on it: the marks are born at the handle's level + 1.
  dhLevel(handle, spec, parent)
  dhParentAlpha(handle, spec)
  dhBuildChrome(handle, spec)
  dhBuildLabel(handle, spec)
  dhFontLabel(handle, spec.owner, Skin)

  handle:EnableMouse(true)
  handle:RegisterForDrag("LeftButton")

  dhSetDragScripts(handle, spec)
  handle:SetScript("OnEnter", function() dhShowTooltip(handle, handle, spec, spec.tooltip) end)
  handle:SetScript("OnLeave", dhHideTooltip)
  dhSetClick(handle, spec, true)

  -- Right to left (minor 15): the X in the corner, the gear against it, the "?" leftmost.
  handle.close = dhBuildClose(handle, spec)
  handle.settings = dhBuildSettings(handle, spec)
  handle.help = dhBuildHelp(handle, spec)
  dhAttachMethods(handle, spec)
  dhFitOnShow(handle)
  handle:SetLabel(spec.label)
  if Skin then lib.__onSkin(Skin, spec.owner, handle, dhRepaint) end
  if type(lib.__checkOwner) == "function" then lib.__checkOwner(handle, parent, spec.owner, "DragHandle") end
  -- See "WHAT THE HOST STILL OWNS" at the top: the one visibility call this file makes, at birth,
  -- because a strip with no width and no anchor point would otherwise flash.
  handle:Hide()
  return handle
end
