-- core/WidgetsSetup.lua
--
-- The LibKa0s-Widgets-1.0 seam: where this addon's flat dropdowns come from.
--
-- ---------------------------------------------------------------------------
-- THIS ADDON WROTE THE WIDGET, AND THAT WAS THE PROBLEM
-- ---------------------------------------------------------------------------
--
-- The control this file leases used to live in modules/Browser.lua: a
-- MakeDropdown factory, a FULLSCREEN_DIALOG singleton popup with pooled rows,
-- a full-screen click-catcher and six helpers, about two hundred lines. It was
-- the third copy of the same widget in the collection -- BankLedger had one and
-- MultiMeters was growing another -- which is three skins to keep in step and
-- three chances for one of them to be restyled while the others are not. The
-- library copy is the same widget: LibKa0s-Widgets-1.0 minor 4 was cut with the
-- two extensions THIS addon's Character filter needed (`opt.isActive` and
-- `dd.presets`) precisely so this adoption would lose nothing.
--
-- ---------------------------------------------------------------------------
-- WHY THE ART IS A PARAMETER
-- ---------------------------------------------------------------------------
--
-- LibKa0s is VENDORED, so the widget's own copy cannot know which addon folder
-- it sits in, and `Media.Icon` needs exactly that to build a texture path (see
-- core/MediaSetup.lua). So the library takes no dependency on Media at all and
-- every piece of art arrives as an argument. Resolving them HERE, once, is what
-- keeps ten call sites from each having their own opinion: the filter bar's nine
-- dropdowns and the export modal's Data Set picker all come through this
-- function. NS.Icon answering nil is a real answer -- the library falls back to
-- the Blizzard chevron and the Blizzard tick, which is what this addon drew
-- before the collection shipped art of its own.
--
-- ---------------------------------------------------------------------------
-- WHY NO glyphFont IS PASSED, AND WHY THAT IS A DECISION
-- ---------------------------------------------------------------------------
--
-- `opts.glyphFont` is a PRECONDITION for any option carrying `opt.glyph`, not a
-- decoration: with no face named the library drops the glyph column entirely,
-- and with a PROPORTIONAL face named the glyph draws as a box. No option this
-- addon builds carries a glyph -- the multi-select tick is inline |T...|t markup
-- the library splices itself, and the Character rows' class icons are inline
-- markup folded into the label string. A face nothing draws in is noise, so none
-- is passed, and tests/test_widgets.lua pins both halves of that: the seam passes
-- no face, and no option table in this addon sets `glyph`.
--
-- ---------------------------------------------------------------------------
-- WHY CloseMenu IS A SEAM AND NOT A frame:Hide()
-- ---------------------------------------------------------------------------
--
-- The popup is a PROCESS-WIDE SINGLETON, built lazily by the first dropdown any
-- Ka0s addon opens and parented to UIParent at FULLSCREEN_DIALOG. It outlives
-- every window that ever dropped it and no host holds a reference to it, so
-- hiding this addon's own frame does not reach it. Every non-click close path
-- this addon has must call NS.CloseMenu(): the History window's OnHide (which is
-- also the Escape/UISpecialFrames path), Browser:Hide (the slash-command close),
-- and the export modal's OnHide (its close button and its own Escape). Miss one
-- and closing that window by that route leaves a menu floating over the game
-- with nothing left to hide it.
--
-- ---------------------------------------------------------------------------
-- WHAT A DEGRADED INSTALL GETS
-- ---------------------------------------------------------------------------
--
-- Nothing, deliberately. NS.MakeDropdown answers nil and the two surfaces that
-- use it REFUSE TO DRAW rather than build a dead control that opens no menu:
-- modules/Browser.lua's BuildFilterBar returns before it publishes B._dd (every
-- reader downstream already guards for that, because the filter paths have
-- always had to work headlessly), and modules/Export.lua's modal declines to
-- build at all and says why through the shared NS.LIBKA0S_MISSING clause.
-- NS.CloseMenu is then a no-op, because there is no menu that could be open.

local _, NS = ...

local W = LibStub and LibStub("LibKa0s-Widgets-1.0", true)

--- One flat-skin dropdown button, or nil when the library is absent.
---
--- NIL IS A REAL ANSWER and the caller must have a plan for it. See the header:
--- a dead control that opens no menu is strictly worse than no control.
---
--- @param parent table   the frame to parent it to
--- @param width number   the collapsed button's width; the menu never drops narrower
--- @return table|nil     the library's dropdown frame
function NS.MakeDropdown(parent, width)
    if not W then return nil end
    return W.Dropdown(parent, width, {
        chevron = NS.Icon and NS.Icon("chevron-down"),
        check   = NS.Icon and NS.Icon("confirm"),
        -- glyphFont deliberately absent -- see the header.
    })
end

--- Close the shared popup menu behind every dropdown in the process, if one is open.
---
--- Safe when no dropdown has ever opened it, safe when it is already hidden, and
--- a no-op on a degraded install. Call it from EVERY non-click close path.
function NS.CloseMenu()
    if W then W.CloseMenu() end
end
