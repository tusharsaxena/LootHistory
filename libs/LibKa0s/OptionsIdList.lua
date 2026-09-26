-- LibKa0s-Options-1.0 — the id surface's second half: the editable id list (O.IdList), one line
-- per entry under an O.IdInput line.
--
-- Peeled out of OptionsWidgets.lua at OptionsIdList minor 1 (issue #32), with OptionsIds.lua beside
-- it; see that file's header for why the id surface is two files and how the two are called in.
-- Everything here is the entry line and its layout -- the delete control, the help mark, the
-- columns and the floors they are measured against, and the uncached-item batches -- and it reaches
-- OptionsIds.lua's input and helpers only through the table lib.__AttachIds returns.
--
-- Part of the Options major rather than a major of its own, and guarded with the same multi-file
-- idiom as OptionsIds.lua.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

-- Minor 1: the id list, moved here from OptionsWidgets.lua (issue #32) with no change in behavior.
local IDLIST_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own — see OptionsScroll.lua for why the
-- file's own counter is not enough.
if lib.__idListMinor and lib.__idListMinor >= IDLIST_MINOR
  and lib.__idListShellMinor == lib.MINOR then return end
lib.__idListMinor      = IDLIST_MINOR
lib.__idListShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsIdList = IDLIST_MINOR

local L = lib.LAYOUT

--- Attach O.IdList to one instance. Called by lib.__AttachWidgets with what lib.__AttachIds
--- returned: `ids` carries every local of OptionsIds.lua and OptionsWidgets.lua the list reaches.
function lib.__AttachIdList(O, d, ids)
  local print, refused = ids.print, ids.refused
  local startRow, renderRowGuarded = ids.startRow, ids.renderRowGuarded
  local ID_MAIN_REL, ID_ACTION_REL, ID_GRAY = ids.ID_MAIN_REL, ids.ID_ACTION_REL, ids.ID_GRAY
  local idKind, kindWords, nameColor, idText = ids.idKind, ids.kindWords, ids.nameColor, ids.idText
  local callHost, disableIfRender, underDisable = ids.callHost, ids.disableIfRender, ids.underDisable
  local entryNamed, drawIdInput = ids.entryNamed, ids.drawIdInput

  -- ── the id list's entry line (minor 16) ──────────────────────────────────────────────────
  --
  -- The name and action widths (ID_MAIN_REL, ID_ACTION_REL) are the input line's, from
  -- OptionsIds.lua: an entry line uses the same two widths, name then action.
  local ID_ICON_SIZE  = 16

  -- `removeStyle = "icon"` (minor 21): an X at the LEFT of each entry, the atlas ConsumableMaster's
  -- delete button wears, about the size of the entry's own icon; the name takes the rest of the line.
  --
  -- FOUR numbers, and they are not the same kind of number. ID_REMOVE_SIZE is the ART: 16px of
  -- atlas, the size of the entry's own icon. ID_REMOVE_HIT is the FRAME that art sits in, and it is
  -- deliberately bigger. AceGUI's Icon centers its texture horizontally and hangs it 5px below the
  -- frame's top (`image:SetPoint("TOP", 0, -5)` in the constructor of
  -- AceGUI-3.0's widgets/AceGUIWidget-Icon.lua) and sizes the frame to the art plus 10 when the
  -- widget carries no label (`SetImageSize` in the same file), so a 26px frame wraps the 16px art in
  -- exactly 5px on all four sides and the click target is 26x26. A frame the size of its own art
  -- would leave the delete control edge to edge with the 16px spell icon the name beside it draws --
  -- two adjacent textures, one of which deletes the row -- and would cut the click target down to
  -- 16x26. Minor 23's 0.06 of the row was wider than that; HOW MUCH wider is not sayable in this
  -- file, and that is the point rather than an omission. A fraction is a width only once the row's
  -- CONTENT width is known, and the paragraph under ID_COLUMNS_MAX below states that that width
  -- follows the panel, which is not knowable here and is measured nowhere in this repository. So
  -- minor 23's target was whatever the player's canvas happened to make it, and 26 is the same
  -- target at every canvas. ID_REMOVE_REL is neither art nor frame: it is what
  -- the NAME gives up so the frame has somewhere to sit, and it is a fraction because the name is.
  -- It is 0.08 rather than minor 23's 0.06 so that reserve still covers a 26px frame at two
  -- columns -- the arithmetic is under ID_COLUMNS_MAX.
  local ID_REMOVE_REL    = 0.08
  local ID_REMOVE_ATLAS  = "transmog-icon-remove"
  local ID_REMOVE_SIZE   = 16
  local ID_REMOVE_HIT    = 26
  -- The gutter between one entry and the next inside a shared row (minor 24), as a fraction of the
  -- whole line. AceGUI's Flow butts its children edge to edge, so a gap between two entries has to
  -- be a widget; this is what each entry gives up to draw one. Nothing is drawn at one column.
  -- See entryGutter.
  local ID_COL_GAP_REL   = 0.04
  -- The art an entry lights up in under the cursor at more than one column. The same texture the id
  -- suggestion lines use (SUGGEST_HIGHLIGHT, in OptionsIds.lua), so "the row under the cursor"
  -- looks the same everywhere on the id surface. See entryHighlight.
  local ID_ENTRY_HILITE  = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
  -- `columns` (minor 24): entries per Flow row, packed row-major. Every relative width above is
  -- divided by the column count, so one column is an exact fraction of the line an entry used to
  -- have to itself and the line still sums to the same 0.98 -- at two columns an entry is
  -- 0.37 + 0.10 with a 0.02 gutter after it, or the X and 0.43 + 0.02 in the icon style. The
  -- divisor is the only thing that changes: the X, the icon, the name and the gray id are laid out
  -- by the same code at every column count, so they line up ACROSS columns for the same reason they
  -- line up down a single one.
  --
  -- THE CAP IS TWO. AceGUI sets the arithmetic; the width that arithmetic is measured against is a
  -- CONSERVATIVE CHOICE rather than a measurement, and this comment says which is which.
  --
  -- THE ARITHMETIC. A Label that has been given an image moves the image ON TOP, centered, with the
  -- name wrapped underneath, whenever the frame leaves it under 200px beside that image --
  -- `if (width - imagewidth) < 200`, AceGUI-3.0's UpdateImageAnchor
  -- (widgets/AceGUIWidget-Label.lua), which the InteractiveLabel an entry is drawn with hijacks
  -- whole. An entry carrying an icon therefore needs ID_ICON_SIZE + 200 = 216px of label, and a
  -- label is a fraction of the row, so each count has a CONTENT width below which it is not a
  -- narrower layout but a DIFFERENT one: 216 * cols / the style's label fraction. The icon style
  -- has a second floor beside it, because the X's frame is absolute and the names have to leave
  -- room for it -- cols * ID_REMOVE_HIT <= content * (1 - 0.90), or 260 * cols. The wider of the
  -- two floors, per style:
  --
  --   cols | default style | icon style
  --      1 |     277px     |    260px
  --      2 |     584px     |    520px
  --      3 |     876px     |    780px
  --      4 |    1168px     |   1040px
  --
  -- WHAT THAT WIDTH IS, AND WHERE THE NUMBER COMES FROM. It is the CONTENT width, not the panel's.
  -- A page's widgets are laid out inside the AceGUI ScrollFrame that anchorScroll anchors
  -- (Options.lua:877-883), which insets the scroll from the panel body by L.CONTENT_LEFT and
  -- L.CONTENT_RIGHT -- 12 and 28, declared as PADDING_X - 4 and PADDING_X + 12 at
  -- Options.lua:187-188 -- and OptionsScroll.lua's always-shown-scrollbar patch then takes a
  -- further GUTTER of 20 off the content width (OptionsScroll.lua:34 and :67-76, forced on every
  -- one of these scrolls at Options.lua:929). Content is therefore the panel's width LESS 60, and
  -- the 0.98 these widths sum to is the clip inset on top of that.
  --
  -- The PANEL's width is not knowable HERE, at file scope, and nothing in this repo has a constant
  -- for it. It is whatever Blizzard's settings canvas gives a registered category at the player's
  -- resolution and UI scale. So the cap is a conservative CEILING, not a measurement. Two columns
  -- want 584px of content -- 644px of panel -- which is comfortably inside every settings canvas
  -- this collection draws a page into. Three wants 876px of content and 936px of panel, which is
  -- past a settings canvas rather than near it. Two is the last count that is safe without knowing
  -- the number.
  --
  -- A CEILING IS NOT THE WHOLE ANSWER, and the floors above are why. A count the width cannot pay
  -- for is not a narrower list: it is a column of icons stacked over wrapped names, and in the icon
  -- style a delete control pushed onto a row of its own -- the one failure mode nothing reported.
  -- At DRAW time the width IS knowable, because the ScrollFrame the list is drawn into carries the
  -- very number AceGUI's Flow will lay the row out against; fitIdColumns reads it and drops the
  -- count a column at a time until the table below is paid. The cap bounds what a host may ASK for;
  -- the draw-time check decides what a given canvas actually gets. The table stays here because it
  -- is the arithmetic both of them are made of.
  --
  -- Flat rather than style-aware on purpose. `removeStyle` is the host's choice about a delete
  -- control, and a cap that moved with it would hand two lists of the same width two different
  -- maxima over a difference the player cannot see -- and would still be wrong for the entries in
  -- either list that have no icon at all, which are the only ones the 200px rule does not bind.
  -- tests/test_options_idlist_layout.lua pins both the number and this arithmetic.
  local ID_COLUMNS_MAX   = 2
  -- AceGUI's own threshold, named so the floors above are DERIVED rather than asserted. A Label
  -- that has been given an image moves the image on top of a wrapped name whenever the frame
  -- leaves it under this much beside the image -- `if (width - imagewidth) < 200`, UpdateImageAnchor
  -- at AceGUI-3.0's widgets/AceGUIWidget-Label.lua:19-32. See entryMinContent.
  local ID_LABEL_MIN     = 200
  -- The per-entry HELP MARK (minor 28, resized and tinted at minor 29): a small information glyph
  -- between the delete control and the name, carrying whatever the host has to say about that
  -- entry that is not its name.
  --
  -- WHY IT EXISTS. The alternative already here is `note`, a full-width second line -- and a
  -- second line cannot share a Flow row, so a noted entry takes a row of its own and punches a
  -- hole in a multi-column grid. A host with something to say about MANY entries therefore had to
  -- choose between saying it and keeping its columns. The mark says it in a tooltip, costs the row
  -- a fixed ID_HELP_HIT and nothing else, and leaves every entry the same shape as every other.
  --
  -- THE NUMBERS WERE THE DRAG HANDLE'S AND ARE NOT ANY MORE (minor 29). `lib.DRAG_HANDLE.HELP` is
  -- 8px of art in an 18px frame (LibKa0s/WidgetsDragHandle.lua:108-110), and minor 28 restated that
  -- pair here so two "?" controls of different sizes could not read as one of them being wrong.
  -- What that reasoning missed is that the handle's frame IS the strip's full height -- it has a
  -- ceiling -- and a settings row has none. The two textures an entry already draws, the delete X's
  -- atlas and the entry's own icon, are both ID_ICON_SIZE, so an 8px mark between them reads as
  -- half-drawn rather than as small, which is exactly what the owner reported against minor 28.
  --
  -- So the art is 14: under the 16 beside it, so it is plainly a mark and not a third icon, and
  -- well over the 8 that could not be read. The frame is the art plus 10, which is the rule
  -- ID_REMOVE_HIT is built on and the same 5px ring: AceGUI's Icon centers its texture and hangs it
  -- 5px below the frame's top (widgets/AceGUIWidget-Icon.lua, quoted at ID_REMOVE_HIT), so art + 10
  -- leaves exactly 5px on all four sides. The DRAG HANDLE'S MARK IS UNCHANGED -- it keeps 8-in-18
  -- because its strip still has that ceiling -- and the two are no longer one number restated in
  -- two files, which is why this paragraph replaces "if one moves, move the other" rather than
  -- keeping it. Widening the frame is not free: it is absolute, so it moves the floor
  -- entryMinContent builds, and ID_HELP_REL below pays for it.
  local ID_HELP_SIZE     = 14
  local ID_HELP_HIT      = 24
  -- Resting gold, the brighten under the cursor, and the flat gray an entry with nothing to say
  -- wears. A DIMMED MARK IS STILL DRAWN, and that is the point of it: the column stays put, so the
  -- names beside it line up whether or not an entry has anything behind its mark.
  local ID_HELP_TINT     = { 0.82, 0.65, 0.21 }
  local ID_HELP_OVER     = { 1, 1, 1 }
  local ID_HELP_DIM      = { 0.35, 0.35, 0.36 }
  -- SEVERITY IS THE HOST'S TO DECLARE (minor 29), because this file reads the lines as opaque
  -- strings: "this aura can never match" and "also in two other categories" are the same type here
  -- and two different answers to a player. `entry.help.level` names which one (entryHelpLevel), and
  -- a name this table does not know reads as the default gold rather than raising or blanking.
  --
  -- TWO LEVELS, because the owner asked the id surface two questions: is this row dead (red), and
  -- is there something to know about a working one (gold). `info` is spelled as the SAME table as
  -- ID_HELP_TINT rather than as a second triple, so "an entry that names no level" and "an entry
  -- that names info" cannot drift into two golds.
  --
  -- RED RATHER THAN ID_WARN (1, 0.5, 0). That is the status line's failure color and it is orange:
  -- beside ID_HELP_TINT's gold, at ID_HELP_SIZE, in one column and one row apart, orange is a shade
  -- of the same answer rather than a different one.
  local ID_HELP_BLOCKED  = { 0.90, 0.24, 0.24 }
  local ID_HELP_LEVELS   = { blocked = ID_HELP_BLOCKED, info = ID_HELP_TINT }
  -- What the NAME gives up for the mark, as a fraction, on the same footing as ID_REMOVE_REL: the
  -- frame is absolute, so this only has to cover it at the widths the list is drawn at, and
  -- entryMinContent below is what actually guarantees it.
  --
  -- 0.09 RATHER THAN MINOR 28's 0.05, and that 0.05 was a REGRESSION rather than a taste. The floor
  -- entryMinContent builds out of it is `cols * ID_HELP_HIT / ID_HELP_REL`, which at 0.05 and two
  -- columns was 720px of CONTENT -- against the 584 the ID_COLUMNS_MAX block above derives for two
  -- columns and calls comfortable, and the 876 it calls past a settings canvas. 720 is a 780px
  -- panel. So fitIdColumns did exactly what it promises and dropped EVERY helped list to one
  -- column: setting `help` on a single entry collapsed the owner's two-column spell list, and the
  -- mark rather than the canvas was what took it.
  --
  -- HOW 0.09 IS DERIVED. The reserve has to buy the mark's frame no later than the floor the row is
  -- already paying, so that adopting `help` never decides a column count on its own:
  --
  --   cols * ID_HELP_HIT / h  <=  (ID_ICON_SIZE + ID_LABEL_MIN) / entryNameRel(true, cols, true)
  --
  -- At two columns in the icon style that is 48 / h <= 432 / (0.86 - h), i.e. h >= 0.086. 0.09 is
  -- the next hundredth up, and it lands the mark on the same per-column budget the X already has:
  -- ID_REMOVE_HIT over its 0.10 of the line is 260px of content per column, ID_HELP_HIT over 0.09
  -- is 267.
  --
  -- WHAT IT COSTS, both ways round. A helped two-column list in the ICON style now wants 561px of
  -- content (the LABEL floor, not the mark's, which is 533) against 520 unhelped -- 41px, and
  -- inside the 584 above. In the DEFAULT style it wants 665px, a ~725px panel, and that one is NOT
  -- reachable at any reserve: the minimum of max(432/(0.74 - h), 2*ID_HELP_HIT/h) is ~649 whatever
  -- h is, because the Remove button's own 0.20 is already out of the line. A host that wants help
  -- AND two columns draws the X (`removeStyle = "icon"`), and the O.IdList doc says so.
  local ID_HELP_REL      = 0.09
  -- THE DEFAULT ART IS THIS LIBRARY'S OWN (minor 29). `media/icons/info.tga` ships inside the
  -- vendored payload, is published as "info" in LibKa0s-Media-1.0's ICONS (Media.lua:92-96), and is
  -- what ConsumableMaster already draws for this exact job (`KCM.Icon("info")`, its
  -- settings/Category.lua:641). It is also WHITE with its shape entirely in the alpha channel
  -- (Media.lua's "WHITE, AND THAT IS A CONTRACT"), which is what makes the tints above mean
  -- anything: a texture is tinted by MULTIPLYING, so white art becomes gold or red, while the
  -- Blizzard fallback below is a blue disc with its `i` baked into the color channels and can only
  -- be darkened. The severity colors are muted on that rung, and saying so is the point of it.
  --
  -- REACHED ACROSS A MAJOR, WHICH IS WHY IT TAKES A NAME. `Media.Icon` builds an absolute
  -- `Interface\AddOns\<addon>\...` path and a VENDORED copy cannot know which addon folder it was
  -- copied into (Media.lua's "WHY THIS TAKES AN ADDON NAME"), so the host says: the Options
  -- descriptor's optional `addonName`, read through LibStub's silent form at draw time -- the same
  -- bargain Core.MakeCloseButton (Core.lua:239-242) and DebugLog's makeIconButton
  -- (DebugLog.lua:179-182) already strike for the same art. NOTHING IS COPIED ACROSS THE SEAM: this
  -- file names the major and asks, so a payload with Options and no Media is still a working
  -- payload. See idHelpIcon for the ladder and what each rung answers.
  local ID_HELP_ICON     = "info"
  -- The same last rung the drag handle's mark falls back to (its HELP_FALLBACK), so a host that
  -- passes no `helpIcon` and names no addon gets the client's own information glyph rather than a
  -- blank square. Reached whenever the rung above cannot answer: no `addonName`, no Media major, or
  -- a Media that does not know the icon name.
  local ID_HELP_FALLBACK = "Interface\\FriendsFrame\\InformationIcon"

  -- Uncached items. `itemLoads[id]` counts the asks this instance has made for an id, capped at
  -- ITEM_LOAD_TRIES: an id the client does not have never loads, and past five asks (two seconds
  -- at LoadItem's 0.4) the entry stays "Unknown item N" rather than asking for ever.
  -- `loadBatches[ctx]` is the ids asked for since that page's last check, `{ [id] = kind }`: one
  -- LoadItem callback per batch, however many ids join it, so twenty uncached ids cost one check
  -- and at most one redraw rather than twenty page renders in the same frame.
  local ITEM_LOAD_TRIES = 5
  local itemLoads = {}
  local loadBatches = setmetatable({}, { __mode = "k" })

  --- Draw the list again after its shape changed: the host's own `ctx.rebuild` when it set one,
  --- else the library's STRUCTURAL sweep -- an add or a remove changes which lines exist.
  local function rebuildIdList(ctx)
    if type(ctx.rebuild) == "function" then return callHost(ctx.rebuild) end
    O.RefreshAllPanels()
  end

  --- An entry's `suffix` (minor 25), or nil: a host-composed aside short enough to sit INSIDE the
  --- label, after the gray id and in the same gray. Anything that is not a non-empty string is
  --- nil, exactly as `note` reads, so an entry that never heard of the field draws what minor 24
  --- drew, byte for byte.
  ---
  --- The host composes the words and the widget only concatenates them. That is also the whole
  --- escaping story, and it is the one `note` already tells: a host string is never a pattern and
  --- never a replacement here -- `fillText` is the only gsub on this path and it runs over the
  --- library's own templates, with the host's values arriving as the RETURN of its replacement
  --- function, where `%` is an ordinary byte. So a `%` or a `%%` in a suffix is drawn as typed.
  --- A `|c` is drawn as typed for the opposite reason: nothing strips it, so the client reads it
  --- as the color escape it is. A host that wants a literal pipe writes `||`, as it must anywhere
  --- else it hands the client text.
  local function entrySuffix(entry)
    local s = entry and entry.suffix
    if type(s) ~= "string" or s == "" then return nil end
    return s
  end

  --- The text an entry's label reads: its name (an item's in its quality color) and its id in
  --- gray, or "Unknown <kind> <id>" -- then, from minor 25, the entry's `suffix` after it in the
  --- same gray.
  ---
  --- INSIDE the label rather than under it, which is the whole difference between this and `note`.
  --- A note is a second full-width Label and costs a noted entry its place in a shared row
  --- (entryNoted); a suffix is bytes on the end of a string the row was already drawing, so it
  --- costs a row nothing and two suffixed entries still pair up. Reach for `note` for a sentence
  --- and `suffix` for a few words -- "(also in 1)", a count, a tag.
  ---
  --- It is drawn in ID_GRAY so the NAME stays the bright thing on the row, and it lands after the
  --- id rather than before it so the two gray runs read as one tail. The cost is the truncation
  --- order at more than one column: word wrap is off there (entryNoWrap) and the client cuts the
  --- tail, so a name already too long for its column loses its suffix first and its id second. That
  --- is the right order -- the suffix is the least of the three -- but it is why a suffix is a few
  --- words and why the API document carries the character budget rather than leaving a host to
  --- find the ceiling by overrunning it.
  local function entryLabel(spec, k, id, name, suffix)
    local text
    if type(name) == "string" and name ~= "" then
      local color = nameColor(k, id)
      if color then name = color .. name .. "|r" end
      text = name .. " " .. ID_GRAY .. "(" .. tostring(id) .. ")|r"
    else
      text = idText(spec, "unknown", { noun = (kindWords(k)), id = id })
    end
    if suffix then text = text .. " " .. ID_GRAY .. suffix .. "|r" end
    return text
  end

  local askItem

  --- A batch's check, LoadItem's callback: redraw once if any name arrived, and ask again, as a
  --- fresh batch under one new callback, for each id still unnamed with asks left. Asked before
  --- the redraw, so the redraw finds them already pending and asks nothing twice.
  local function settleBatch(ctx, Item)
    local batch = loadBatches[ctx]
    loadBatches[ctx] = nil
    if not batch then return end
    local landed = false
    for id, k in pairs(batch) do
      if entryNamed(k, id) then landed = true else askItem(ctx, Item, k, id) end
    end
    if landed then rebuildIdList(ctx) end
  end

  --- Ask for one item into `ctx`'s batch: the first id of a batch carries the check, the rest only
  --- ask. Nothing for an id already pending there, or out of asks.
  askItem = function(ctx, Item, k, id)
    local asked = itemLoads[id] or 0
    local batch = loadBatches[ctx]
    if asked >= ITEM_LOAD_TRIES or (batch and batch[id]) then return end
    itemLoads[id] = asked + 1
    if batch then
      batch[id] = k
      Item.LoadItem(id)
    else
      loadBatches[ctx] = { [id] = k }
      Item.LoadItem(id, function() settleBatch(ctx, Item) end)
    end
  end

  --- Ask the client to load an item the list could not name; the list is drawn again once a check
  --- finds it named. Through LibKa0s-Item-1.0, looked up at call time so its load order does not
  --- matter; a payload without it leaves the entry unnamed rather than raising.
  local function loadEntry(ctx, k, id)
    if not k.loads then return end
    local Item = LibStub and LibStub("LibKa0s-Item-1.0", true)
    if not (Item and Item.LoadItem) then return end
    askItem(ctx, Item, k, id)
  end

  --- The client's own tooltip for the entry: GameTooltip's per-kind method, or a host kind's
  --- `tooltip(tooltip, id)` function.
  --- `owner`, when the caller passes one, is the frame GameTooltip hangs off instead of the label.
  --- At one column the label's right edge IS the list's right edge, so ANCHOR_RIGHT puts the
  --- tooltip outside the list and nothing is covered. At more than one a column-one label's right
  --- edge is the middle of the list, and the same anchor drops the tooltip squarely over column
  --- two -- over the entries the reader is on their way to, which is the worst thing it could
  --- cover. The caller hands over the ROW instead, which spans the full width at every column
  --- count: the same rule as before, applied to the widget that still reaches the edge.
  ---
  --- NOT under the hovered label. The obvious alternative -- SetOwner(row, "ANCHOR_NONE") and a
  --- hand-placed TOPLEFT on the label's BOTTOMLEFT, so the tooltip opens in the hovered entry's own
  --- column -- buys the sibling column and pays for it with every row BELOW the cursor, which is the
  --- same content by the same argument. The debug window already shipped that and took it back:
  --- `tests/test_debuglog.lua` ("dbg: an icon control carries NO tooltip") pins the removal of minor
  --- 9's under-the-control tooltip because it covered the first line of the log every time the
  --- pointer crossed the title bar. Hand-placing also takes the position away from the client, so a
  --- row near the bottom of the scroll needs a flip decided from `GetBottom()` against the shown
  --- tooltip's height -- geometry the headless fake cannot answer: `GetBottom` falls through the
  --- stub metatable and comes back as the frame itself, and `GetHeight` answers 0 until a test
  --- arms it with `__setGeom` (tests/_kit/mock_base.lua). The flip would be arithmetic on a table
  --- in the fake, i.e. a branch that could only ever be checked in game. ANCHOR_RIGHT off the widget that reaches the panel edge is the convention everywhere else
  --- here too (OptionsTabs.lua's tab tooltip, Widgets.lua's). A host that genuinely wants it
  --- elsewhere gets a spec-level anchor, the way WidgetsDragHandle's `tooltipAnchor` does it.
  ---
  --- What answers "which of the two entries is this?" is not the anchor but entryHighlight, which
  --- was added for exactly that and is the other half of this decision.
  local function entryTooltip(lbl, k, id, owner)
    local anchor = (owner and (owner.frame or owner)) or lbl.frame or lbl
    lbl:SetCallback("OnEnter", function()
      local method = k.tooltip
      if not GameTooltip then return end
      if type(method) == "string" then method = GameTooltip[method] end
      if type(method) ~= "function" then return end
      GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
      method(GameTooltip, id)
      GameTooltip:Show()
    end)
    lbl:SetCallback("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  end

  --- The entry's right-hand widget: a checkbox for a toggle entry (a starter the host can switch
  --- off without forgetting it), else Remove, which rebuilds the list once the host has removed it.
  local function entryAction(ctx, spec, entry, line, cols)
    local w
    if entry.toggle then
      w = O.AceGUI:Create("CheckBox")
      w:SetLabel(spec.toggleLabel or "")
      w:SetValue(entry.on and true or false)
      w:SetCallback("OnValueChanged", function(_, _, value)
        if not callHost(spec.onToggle, entry.id, value and true or false) and refused() then
          w:SetValue(entry.on and true or false)   -- refused in combat (minor 23): put it back
        end
      end)
    else
      w = O.AceGUI:Create("Button")
      w:SetText(idText(spec, "remove"))
      w:SetCallback("OnClick", function()
        if callHost(spec.onRemove, entry.id) then rebuildIdList(ctx) end
      end)
    end
    w:SetRelativeWidth(ID_ACTION_REL / (cols or 1))
    disableIfRender(ctx, w)
    line:AddChild(w)
  end

  --- Whether `entry` has anything behind its help mark.
  ---
  --- A LIST WITH NO HELP ANYWHERE DRAWS NO MARKS AT ALL -- asked once per render, not per entry,
  --- so a host that never sets `help` pays nothing and its rows are exactly what minor 27 drew.
  --- Within a list that DOES use it, every entry gets a mark whether or not it has lines, because
  --- a column that appears and disappears per row is not a column.
  local function entryHelpLines(entry)
    local help = type(entry) == "table" and entry.help or nil
    if type(help) == "string" and help ~= "" then return { help } end
    if type(help) == "table" and help[1] ~= nil then return help end
    return nil
  end

  --- Does any entry in this list carry help? See entryHelpLines for why this is a list-level
  --- question rather than a per-entry one.
  local function listHasHelp(entries)
    if type(entries) ~= "table" then return false end
    for _, entry in ipairs(entries) do
      if entryHelpLines(entry) then return true end
    end
    return false
  end

  --- The texture every mark in this list is drawn with: what the host named, else this library's
  --- own `info` art, else the client's glyph. The constants say why the middle rung exists and why
  --- it takes an addon name; this is the ladder.
  ---
  --- RESOLVED ONCE PER INSTANCE, not per mark and not at file load. Per mark would repeat a LibStub
  --- lookup for every entry of every render for an answer that cannot change. At load it would
  --- assume a file order across two majors, which is the assumption Core.MakeCloseButton refuses
  --- for the same art (LibKa0s/Core.lua:239-242). The consequence is that a Media major arriving
  --- AFTER the first helped list is drawn is not picked up until a reload -- true, and not a case:
  --- every file of this payload is loaded by one LibKa0s.xml before any panel exists.
  ---
  --- `false` rather than nil for "the ladder fell through", because nil is the not-asked-yet state:
  --- a host with no `addonName` would otherwise re-ask, and re-fail, on every mark forever.
  local idHelpDefault
  local function idHelpIcon(spec)
    local given = type(spec) == "table" and spec.helpIcon or nil
    if type(given) == "string" and given ~= "" then return given end
    if idHelpDefault == nil then
      local host = type(d.addonName) == "string" and d.addonName ~= "" and d.addonName or nil
      local media = host and LibStub and LibStub("LibKa0s-Media-1.0", true)
      idHelpDefault = (media and media.Icon and media.Icon(host, ID_HELP_ICON)) or false
    end
    return idHelpDefault or ID_HELP_FALLBACK
  end

  --- The tint one entry's mark wears, and the level name it came from: the host's `help.level`, the
  --- default gold when it names none, and the flat gray when the entry has no lines at all.
  ---
  --- THE LEVEL RIDES THE LINES, on the table that carries them, rather than on a second
  --- `entry.helpLevel` beside them. One field is one host call site -- a host builds an entry's
  --- lines in one place, and a severity in a second field is a second thing to keep in step with
  --- them, which is the shape that goes stale. It also cannot disagree with itself: there is no
  --- entry whose level says "blocked" and whose lines were cleared. The cost, and it is a real one:
  --- the one-line STRING form cannot carry a level, so a host that wants one writes
  --- `help = { level = "blocked", "..." }` -- the list form it would have reached for on its second
  --- line anyway.
  ---
  --- BACKWARD COMPATIBLE BY CONSTRUCTION. `level` is a hash key on a table this file only ever
  --- reads as an ARRAY (`#lines`, and the loop in entryHelp), so an entry written against minor 28
  --- -- a plain string, or a plain list of strings -- answers ID_HELP_TINT here and draws exactly
  --- what it drew. So does a level name this library does not know: an unknown name is a host
  --- typo or a host that is newer than its vendored copy, and neither is worth a raise or a blank
  --- mark when the honest answer is the mark minor 28 already drew.
  local function entryHelpLevel(entry, lines)
    if not lines then return ID_HELP_DIM, nil end
    local help = type(entry) == "table" and entry.help or nil
    local level = type(help) == "table" and help.level or nil
    if type(level) ~= "string" then return ID_HELP_TINT, nil end
    return ID_HELP_LEVELS[level] or ID_HELP_TINT, level
  end

  --- The entry's information mark: an Icon between the delete control and the name, tinted by the
  --- host's level when it gave it something to say and flat gray when it did not.
  ---
  --- AN ICON RATHER THAN A BUTTON, unlike the drag handle's mark, because everything else on this
  --- row is an AceGUI widget in a Flow and a raw CreateFrame would not be laid out by it. The
  --- consequence is that hover has to come off the Icon's own OnEnter/OnLeave rather than off
  --- frame scripts, which is what the callbacks below are.
  ---
  --- THE TOOLTIP IS THE HOST'S LINES AND NOTHING ELSE. The entry's own name is the title, because
  --- a tooltip with no title floating beside a row reads as belonging to the row above it. A mark
  --- with no lines gets NO tooltip at all -- not an empty one -- so hovering it is silent rather
  --- than answering with a blank frame.
  local function entryHelp(ctx, spec, entry, line, name, lines)
    local h = O.AceGUI:Create("Icon")
    h:SetImageSize(ID_HELP_SIZE, ID_HELP_SIZE)
    h:SetWidth(ID_HELP_HIT)
    local tex = h.image
    local tint, level = entryHelpLevel(entry, lines)
    local path = idHelpIcon(spec)
    if type(tex) == "table" then
      if tex.SetTexture then tex:SetTexture(path) end
      if tex.SetVertexColor then tex:SetVertexColor(tint[1], tint[2], tint[3]) end
    end
    -- THE MARKERS, and why there are five of them. A harness's fake Icon has no texture object at
    -- all (`h.image` is nil, tests/_kit/mock_base.lua's makeWidget), so every SetTexture and
    -- SetVertexColor above is dead there and nothing about the mark's ART or COLOR is readable
    -- from the widget -- the same reason the X records `__removeAtlas`. `__helpLines` and
    -- `__helpTint` are what it was given, `__helpLevel` is the name the host used (recorded even
    -- when this library does not know it, so a typo is visible rather than merely gold),
    -- `__helpIcon` is the rung the art ladder settled on, and `__helpTintNow` is the only one a
    -- hover moves: it is what makes "the mark goes back to ITS OWN color, not to gold" assertable
    -- with no vertex color to read. Size and frame need no marker -- SetImageSize and SetWidth are
    -- recorder fields already.
    h.__helpLines = lines
    h.__helpTint = tint
    h.__helpLevel = level
    h.__helpIcon = path
    h.__helpTintNow = tint
    if lines then
      h:SetCallback("OnEnter", function()
        h.__helpTintNow = ID_HELP_OVER
        if type(tex) == "table" and tex.SetVertexColor then
          tex:SetVertexColor(ID_HELP_OVER[1], ID_HELP_OVER[2], ID_HELP_OVER[3])
        end
        if not GameTooltip then return end
        GameTooltip:SetOwner(h.frame or h, "ANCHOR_RIGHT")
        GameTooltip:SetText(name or tostring(entry.id), 1, 1, 1)
        for i = 1, #lines do
          GameTooltip:AddLine(lines[i], 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
      end)
      h:SetCallback("OnLeave", function()
        -- THIS ENTRY'S OWN TINT, not ID_HELP_TINT. Minor 28 could name the constant because gold
        -- was the only lit color there was; with levels that hardcode turns a red mark gold the
        -- first time the cursor crosses it and leaves it that way, which is a defect a player sees
        -- and no status line reports.
        h.__helpTintNow = tint
        if type(tex) == "table" and tex.SetVertexColor then
          tex:SetVertexColor(tint[1], tint[2], tint[3])
        end
        if GameTooltip then GameTooltip:Hide() end
      end)
    end
    disableIfRender(ctx, h)
    line:AddChild(h)
  end

  --- The X's HIGHLIGHT texture, moved from the art onto the frame, so that what lights up under
  --- the cursor is what a click actually hits.
  ---
  --- AceGUI's Icon anchors its highlight to the IMAGE -- `highlight:SetAllPoints(image)`, in the
  --- Constructor of AceGUI-3.0's widgets/AceGUIWidget-Icon.lua, right after that texture is
  --- created -- while the thing that takes the click is the FRAME: the same constructor calls
  --- `frame:EnableMouse(true)` and puts its OnClick script on the frame, not on the image. The art
  --- is ID_REMOVE_SIZE and the frame is ID_REMOVE_HIT, so everything the wider frame adds around
  --- the X is live and unlit. On a control that DELETES the row that is exactly the wrong way
  --- round: the ring reads as the gap between the X and the spell icon beside it, and a click on
  --- what looks like a gap removes an entry with nothing having lit up first. Anchoring the
  --- highlight to the frame makes the lit rectangle and the clickable rectangle the same
  --- rectangle, which is the only thing that tells the player where the control ends.
  ---
  --- FOUND BY WALKING THE REGIONS, because the texture is not reachable any other way: Icon's
  --- constructor puts only `label`, `image`, `frame` and `type` on the widget table (same file),
  --- and the highlight is a plain CreateTexture on the HIGHLIGHT draw layer rather than the
  --- button's own highlight texture, so `GetHighlightTexture` does not answer it either. A client
  --- that stopped building it, or a harness whose fake frame has no regions, finds nothing here
  --- and the X is drawn exactly as it was.
  ---
  --- RESTORED ON RELEASE, as entryNoWrap's FontString is and for the same reason. AceGUI pools
  --- this Icon across every addon in the session, and Icon's OnAcquire sets the height, the width,
  --- the label, the image and the image size and says nothing about the highlight's anchors (the
  --- `OnAcquire` method in the file above), so an X that simply left it re-anchored would hand the
  --- next consumer of that pooled Icon a highlight stretched over its whole frame -- on a default
  --- Icon, whose OnAcquire asks for a 110px frame around a 64px image, a lit border nobody asked
  --- for. AceGUI:Release fires "OnRelease" on the widget before it clears its callbacks
  --- (AceGUI-3.0.lua's Release), which is where the texture goes back onto the image.
  ---
  --- `__removeHitLit` records what was asked for, the way `__removeAtlas` records the delete art,
  --- for a harness whose fake Icon has no textures to anchor.
  local function entryRemoveLit(x)
    x.__removeHitLit = true
    local frame, img = x.frame, x.image
    if type(frame) ~= "table" or type(frame.GetRegions) ~= "function" then return end
    if type(img) ~= "table" or type(img.SetAllPoints) ~= "function" then return end
    local hl
    local regions = { frame:GetRegions() }
    for i = 1, #regions do
      local r = regions[i]
      if type(r) == "table" and r ~= img and type(r.GetDrawLayer) == "function"
        and type(r.SetAllPoints) == "function" and type(r.ClearAllPoints) == "function"
        and r:GetDrawLayer() == "HIGHLIGHT" then
        hl = r
        break
      end
    end
    if not hl then return end
    hl:ClearAllPoints()
    hl:SetAllPoints(frame)
    x:SetCallback("OnRelease", function()
      hl:ClearAllPoints()
      hl:SetAllPoints(img)
    end)
  end

  --- The entry's X (`removeStyle = "icon"`, minor 21): a small Icon widget at the LEFT of the line,
  --- wearing ID_REMOVE_ATLAS, whose click calls onRemove and rebuilds the list once the host has
  --- removed the entry. Its tooltip is the `remove` string, so a host's `strings.remove` names it. A
  --- toggle entry is drawn no differently: under this style the host sends none.
  local function entryRemoveIcon(ctx, spec, entry, line)
    local x = O.AceGUI:Create("Icon")
    x:SetImageSize(ID_REMOVE_SIZE, ID_REMOVE_SIZE)
    local tex = x.image
    if type(tex) == "table" and tex.SetAtlas then tex:SetAtlas(ID_REMOVE_ATLAS) end
    x.__removeAtlas = ID_REMOVE_ATLAS   -- the art it wears, for a host's suite (a fake draws none)
    -- A FLOOR, NOT A FRACTION, AND WIDER THAN THE ART IT CARRIES. ID_REMOVE_REL is what the NAME
    -- beside the X gives up for it -- the label's width already subtracts it -- and the X's own
    -- frame is absolute. A relative width is multiplied by the row at layout time, so
    -- ID_REMOVE_REL / cols shrinks with the column count and with the canvas, and an Icon anchors
    -- its texture TOP-centered rather than clipping it: a frame narrower than the art does not
    -- shrink the X, it spills it over whatever is next to it. Only an absolute width can promise
    -- otherwise, so the X takes one at every column count, this one included.
    --
    -- The absolute number is ID_REMOVE_HIT, not ID_REMOVE_SIZE. The art is 16px and so is the spell
    -- icon the name beside it draws, so a frame the size of its art puts two 16x16 textures flush
    -- against each other, one of which deletes the row, and leaves a click target exactly 16px wide.
    -- Minor 23's fraction gave a wider one than that, by an amount this file deliberately does not
    -- quote: 0.06 is a width only once the row's CONTENT width is known, and that width follows the
    -- panel, which is not knowable here (the paragraph under ID_COLUMNS_MAX says so, and nothing in
    -- this repository measures it). At 26 the Icon's own geometry centers the art with 5px on
    -- every side -- the same 5px AceGUI already leaves above and below it -- so the hit area is
    -- 26x26, the gap to the spell icon is real, and nothing about it moves with `cols`. What that
    -- 26x26 LIGHTS is entryRemoveLit's business, just above: AceGUI lights the art alone,
    -- so without it the 5px ring this width buys is live and dark.
    x:SetWidth(ID_REMOVE_HIT)
    entryRemoveLit(x)
    x:SetCallback("OnClick", function()
      if callHost(spec.onRemove, entry.id) then rebuildIdList(ctx) end
    end)
    O.AttachTooltip(x, idText(spec, "remove"), nil)
    disableIfRender(ctx, x)
    line:AddChild(x)
  end

  --- The width of an entry's NAME, as a fraction of the whole line. What the line has (0.98) less
  --- what the delete control takes -- the X's reserve in the icon style, the action widget's own
  --- width in the default one -- less the gutter that separates this entry from the next, all
  --- divided by the column count. At one column there is no neighbor and so no gutter: the default
  --- style comes out at minor 23's 0.78 exactly, and the icon style at 0.90 rather than minor 23's
  --- 0.92, because ID_REMOVE_REL grew by 0.02 to cover the X's wider frame.
  local function entryNameRel(iconStyle, cols, hasHelp)
    local base = iconStyle and (ID_MAIN_REL + ID_ACTION_REL - ID_REMOVE_REL) or ID_MAIN_REL
    if cols > 1 then base = base - ID_COL_GAP_REL end
    -- The help mark comes out of the NAME, as the X does, and only in a list that draws one.
    if hasHelp then base = base - ID_HELP_REL end
    return base / cols
  end

  --- The gap between one entry and the next inside a shared row.
  ---
  --- AceGUI's Flow butts its children edge to edge -- a child is anchored TOPLEFT to the previous
  --- child's TOPRIGHT with no x offset (`frame:SetPoint("TOPLEFT", children[i-1].frame,
  --- "TOPRIGHT", 0, frameoffset - lastframeoffset)`, AceGUI-3.0.lua's Flow layout) -- so a gap has
  --- to be a widget. Without one the default style reads [name][Remove][name][Remove] with the
  --- first Remove flush against the name it does NOT belong to, and the icon style puts entry
  --- two's X against the end of entry one's name.
  ---
  --- Drawn at the END of every entry rather than between them, which keeps each entry's share of
  --- the row exactly 0.98 / cols: the name gives the gutter up, and the trailing entry's gutter is
  --- dead space inside the clip inset the 0.98 already leaves. Nothing at all is drawn at one
  --- column, where the entry has the row to itself.
  local function entryGutter(line, cols)
    if cols <= 1 then return end
    local g = O.AceGUI:Create("SimpleGroup")
    g:SetLayout(nil)
    g:SetRelativeWidth(ID_COL_GAP_REL / cols)
    g:SetHeight(1)
    line:AddChild(g)
  end

  --- ONE LINE TALL, ALWAYS, at more than one column.
  ---
  --- AceGUI's Flow centers the widgets of a row on each other by alignoffset -- `frameoffset =
  --- child.alignoffset or (frameheight / 2)`, and the next child is anchored
  --- `frameoffset - lastframeoffset` off its neighbor's TOPRIGHT (AceGUI-3.0.lua's Flow layout) --
  --- so one entry whose name wrapped to a second line moves every widget in the row beside it.
  --- That is not an uneven row, it is a broken grid: the two names and the two delete controls
  --- stop lining up. An entry's name and its gray id are one FontString, so the fix is on that
  --- FontString -- word wrap off, and the client truncates the tail rather than wrapping it.
  ---
  --- RESTORED ON RELEASE, BY entryRelease RATHER THAN HERE. AceGUI pools this widget across every
  --- addon in the session and Label's OnAcquire does not reset word wrap -- it sets the width, the
  --- text, the image and its size, the color, the font object and the two justifications, and never
  --- touches SetWordWrap (`OnAcquire` in AceGUI-3.0's widgets/AceGUIWidget-Label.lua) -- so a list
  --- that simply left it off would hand
  --- the next consumer of that pooled label a label that no longer wraps. The FontString that has
  --- to be put back is this function's to find, so it RETURNS it and entryRelease does the
  --- restoring, together with everything else this label owes its pool. It cannot be two
  --- callbacks: WidgetBase.SetCallback stores one handler per event NAME (`self.events[name] =
  --- func`, AceGUI-3.0.lua), so a second SetCallback("OnRelease") on the same widget REPLACES the
  --- first rather than chaining with it, and whichever half was installed earlier would silently
  --- stop happening.
  ---
  --- One column is untouched. The entry has the whole row, a wrapped name pushes nothing sideways,
  --- and a list that passes no `columns` draws exactly what minor 23 drew.
  ---
  --- `__wordWrap` records what was asked for, the way `__removeAtlas` records the delete art: a
  --- harness whose AceGUI fake has no FontString behind the widget can still assert the rule. Such
  --- a fake takes the early return below -- the marker is set BEFORE it, and entryRelease clears it
  --- whether or not there was a FontString to hand back.
  local function entryNoWrap(lbl)
    lbl.__wordWrap = false
    local fs = lbl.label
    if type(fs) ~= "table" or type(fs.SetWordWrap) ~= "function" then return nil end
    fs:SetWordWrap(false)
    return fs
  end

  --- Light the entry under the cursor, at more than one column.
  ---
  --- The tooltip hangs off the whole ROW there rather than off the label, so that it cannot cover
  --- the column beside it (see entryTooltip) -- which means it can open a long way from the name
  --- the cursor is actually on, with nothing saying which of the two entries in the row it
  --- describes. An InteractiveLabel already ships a HIGHLIGHT-layer texture over its own frame; it
  --- draws nothing until a caller names one, so naming one is the whole change, and the lit name
  --- is what gives the tooltip an owner the eye can find.
  ---
  --- The TEXTURE needs nothing on release: InteractiveLabel's OnAcquire calls SetHighlight with no
  --- argument (`OnAcquire` in AceGUI-3.0's widgets/AceGUIWidget-InteractiveLabel.lua), which clears
  --- it for the next consumer of the pooled widget. The MARKER below does need clearing, and
  --- entryRelease is where that happens -- see there.
  ---
  --- `__highlight` records the art, as `__removeAtlas` does, for a harness whose fake has no
  --- SetHighlight to call.
  local function entryHighlight(lbl)
    lbl.__highlight = ID_ENTRY_HILITE
    if type(lbl.SetHighlight) == "function" then lbl:SetHighlight(ID_ENTRY_HILITE) end
  end

  --- The ONE "OnRelease" an entry's label gets, and everything that has to happen inside it.
  ---
  --- WHY ONE. WidgetBase.SetCallback stores a handler by event name (`self.events[name] = func`,
  --- AceGUI-3.0.lua), so callbacks do not chain: a second SetCallback("OnRelease") on this label
  --- would throw the first one away. Word wrap and the markers are therefore restored and cleared
  --- from the same handler, and nothing else in this file may hang another "OnRelease" on an entry
  --- label.
  ---
  --- WHY THE MARKERS. AceGUI:Release wipes the widget's userdata and its events and then nils a
  --- FIXED list of fields -- width, relWidth, height, relHeight, noAutoHeight and the frame's own
  --- width and height (`AceGUI:Release` in AceGUI-3.0.lua). Keys an ADDON invented are not on that
  --- list, so `__wordWrap` and `__highlight` ride the widget into the pool and are still on it when
  --- the next Create hands it out -- to this list, to another list in this addon, or to another
  --- addon entirely, because the pool is per-widget-type and shared by everything that loaded
  --- AceGUI. The functional state is already safe without this (the FontString is handed back right
  --- here, and OnAcquire clears the highlight texture); it is the markers that leak, and a leaked
  --- marker is not a cosmetic wart. tests/test_options_idlist_layout.lua asserts the one-column contract
  --- as "no marker on the label", so a marker that survived a release turns that case into one that
  --- passes or fails on POOL ORDER rather than on what the render asked for.
  ---
  --- `fs` is entryNoWrap's FontString, or nil when the label has none -- a harness fake, or any
  --- future label whose text is not a FontString. Nil is not a reason to skip the callback: the
  --- marker was set before entryNoWrap's early return and still has to come off.
  ---
  --- Hanging this on SetCallback is safe for the same reason landingLogo's is: AceGUI:Release fires
  --- "OnRelease" BEFORE it clears the events table, and fires it with the widget as the first
  --- argument and the event name as the second (`WidgetBase.Fire` in AceGUI-3.0.lua) -- which is
  --- where `w` below comes from, so the handler clears the markers on the widget it was fired for.
  local function entryRelease(lbl, fs)
    lbl:SetCallback("OnRelease", function(w)
      if fs and type(fs.SetWordWrap) == "function" then fs:SetWordWrap(true) end
      w.__wordWrap = nil
      w.__highlight = nil
    end)
  end

  --- One entry, drawn into `line`. `cols` is how many entries share that Flow row (1 unless the
  --- host asked for more): every relative width the entry claims is divided by it, and nothing
  --- else about the entry changes.
  local function idLine(ctx, spec, k, entry, line, cols, hasHelp)
    local name, icon
    cols = cols or 1
    local iconStyle = spec.removeStyle == "icon"
    if type(k.info) == "function" then name, icon = k.info(entry.id) end
    if name == nil then loadEntry(ctx, k, entry.id) end
    if iconStyle then entryRemoveIcon(ctx, spec, entry, line) end
    -- BETWEEN THE DELETE AND THE NAME, in a list that uses help at all. The order a player reads
    -- is [X] [?] [icon] Name (id): the destructive control first, then the one that explains the
    -- row, then the row itself.
    if hasHelp then entryHelp(ctx, spec, entry, line, name, entryHelpLines(entry)) end
    local lbl = O.AceGUI:Create("InteractiveLabel")
    -- Before the text, not after: SetText runs AceGUI's UpdateImageAnchor, which measures the
    -- string's height. Measuring it once as a wrapped string and once more as a clipped one is a
    -- height that is briefly wrong for no reason.
    -- LIT AT EVERY COLUMN COUNT (minor 28). It was `cols > 1` only, on the reasoning that a
    -- one-column tooltip already hangs off the name and needs no second owner -- but the lit name
    -- is not only a tooltip's owner, it is the feedback that says which row the cursor is on, and
    -- a one-column list wants that as much as a two-column one. It also made a NOTED entry, which
    -- is drawn at one column inside a two-column list, the only unlit row on the page.
    --
    -- Word wrap is still turned off only at more than one column: at one the entry has the row to
    -- itself and a wrapped name pushes nothing sideways.
    local fs = (cols > 1) and entryNoWrap(lbl) or nil
    entryHighlight(lbl)
    entryRelease(lbl, fs)
    lbl:SetText(entryLabel(spec, k, entry.id, name, entrySuffix(entry)))
    if icon then
      lbl:SetImage(icon)
      lbl:SetImageSize(ID_ICON_SIZE, ID_ICON_SIZE)
    end
    lbl:SetRelativeWidth(entryNameRel(iconStyle, cols, hasHelp))
    entryTooltip(lbl, k, entry.id, cols > 1 and line or nil)
    line:AddChild(lbl)
    -- The note: a second line under the name, in the gray the id already uses, for a host that has
    -- something to say about this entry (why it is or is not drawn, say). Its own line rather than
    -- a suffix, because a note is a sentence and a name is a name. `entry.suffix` (minor 25) is
    -- the lighter option beside it and is already inside the label above; the two are independent,
    -- and an entry carrying both keeps the suffix inline and still takes its own full-width row.
    if type(entry.note) == "string" and entry.note ~= "" then
      local n = O.AceGUI:Create("Label")
      n:SetText(ID_GRAY .. entry.note .. "|r")
      n:SetRelativeWidth(ID_MAIN_REL)
      line:AddChild(n)
    end
    if not iconStyle then entryAction(ctx, spec, entry, line, cols) end
    entryGutter(line, cols)
  end

  --- Does this entry carry a note? A note is a SECOND line under the name, which is why it is
  --- asked about outside idLine: a Flow row cannot hold a wrapped second line in one column and a
  --- neighbor beside it, so under `columns` a noted entry takes a row of its own at full width
  --- (`RenderGrid`'s `wide`, and for the same reason). That keeps the note's own contract exactly
  --- what W17 wrote -- a full-width gray line under the name -- and keeps the grid square, at the
  --- cost of one short row wherever a noted entry lands.
  local function entryNoted(entry)
    return type(entry.note) == "string" and entry.note ~= ""
  end

  --- Entries per Flow row: 1 unless the host asked for more, floored, and clamped into
  --- 1..ID_COLUMNS_MAX. Anything that is not a number reads as 1, so a spec that never heard of
  --- this option takes the single-column path exactly as it did at minor 23.
  local function idColumns(spec)
    local n = tonumber(spec.columns)
    if not n then return 1 end
    n = math.floor(n)
    if n < 1 then return 1 end
    if n > ID_COLUMNS_MAX then return ID_COLUMNS_MAX end
    return n
  end

  --- Roll a shared Flow row back to the children it held before a failing entry began drawing into
  --- it. Without this the per-entry guard would still cost only the entry's LINE -- but at more
  --- than one column that line is shared, so the half-built widgets of an entry whose lookup raised
  --- would be drawn beside the neighbor that succeeded. AceGUI's own ReleaseChildren does exactly
  --- this, newest first; a Release that itself raises is absorbed, since the point of being here at
  --- all is that something already raised.
  local function trimChildren(line, keep)
    local kids = line.children
    if type(kids) ~= "table" then return end
    for i = #kids, keep + 1, -1 do
      local child = table.remove(kids, i)
      if type(child) == "table" and type(child.Release) == "function" then pcall(child.Release, child) end
    end
  end

  --- What `line` already holds, so a failing entry can be trimmed back to it. A container with no
  --- children list at all (a host's fake, an AceGUI that changed shape) reads as empty, which makes
  --- the trim a no-op rather than a second raise inside the guard.
  local function childCount(line)
    local kids = line.children
    return type(kids) == "table" and #kids or 0
  end

  --- How many entries this entry's row holds: the list's column count, or 1 for a noted entry,
  --- which takes a full-width row of its own (see entryNoted).
  local function entryColumns(entry, columns)
    if columns > 1 and entryNoted(entry) then return 1 end
    return columns
  end

  --- The CONTENT width one of this list's Flow rows will be laid out against, or nil when this
  --- render cannot know it.
  ---
  --- `content.width`, NOT `scroll.frame:GetWidth()`, and the difference is the whole point. Flow
  --- measures every child against exactly one number -- `local width = content.width or
  --- content:GetWidth() or 0`, AceGUI-3.0.lua's Flow layout -- so that is the number a floor has to
  --- be compared with. The ScrollFrame's own frame is WIDER than it: AceGUI's ScrollFrame sets
  --- `content.width = width - (self.scrollBarShown and 20 or 0)` in OnWidthSet
  --- (widgets/AceGUIContainer-ScrollFrame.lua), and OptionsScroll.lua's always-shown-scrollbar patch
  --- forces that subtraction on whether the bar is needed or not (its forceGutter, and FixScroll
  --- re-forces it). Measuring the frame would hand every check 20px the row does not have. The
  --- fallback to `content:GetWidth()` is Flow's own, for the same reason Flow has it.
  ---
  --- NIL IS A REAL ANSWER AND IT MEANS "CHANGE NOTHING". The number arrives from OnWidthSet, which
  --- this library forwards by hand off the scroll frame's OnSizeChanged (Options.lua's EnsureScroll)
  --- because the ScrollFrame is parented to a Blizzard frame rather than to an AceGUI container that
  --- would size it. A page drawn before its panel has ever been given a size has not had that fire,
  --- and a harness whose AceGUI is a fake has no geometry at all; both read as nil or 0. Neither may
  --- narrow a list. Collapsing a working two-column list because nobody has measured the canvas yet
  --- would be a worse failure than the silent one this measurement exists to catch, and an
  --- unmeasurable width is exactly the state every render was in before this check existed.
  local function idContentWidth(scroll)
    local content = type(scroll) == "table" and scroll.content or nil
    if type(content) ~= "table" then return nil end
    local w = content.width
    if w == nil and type(content.GetWidth) == "function" then
      local ok, got = pcall(content.GetWidth, content)
      w = ok and got or nil
    end
    w = tonumber(w)
    if not w or w <= 0 then return nil end
    return w
  end

  --- The narrowest CONTENT width at which `cols` columns still draw the layout they promise, in the
  --- style asked for. The two floors the ID_COLUMNS_MAX block tabulates, written as code from the
  --- same constants so the table up there and the check down here cannot drift apart.
  ---
  --- THE LABEL FLOOR, both styles. An entry's name is an InteractiveLabel carrying the entry's icon,
  --- and AceGUI moves that image on TOP of a wrapped name unless the frame leaves ID_LABEL_MIN
  --- beside it (AceGUIWidget-Label.lua:19-32, quoted at the constant). The name holds entryNameRel
  --- of the row, so the row needs (icon + threshold) / that fraction before the entry is a line at
  --- all rather than a stack.
  ---
  --- THE X FLOOR, icon style only, and it is the one this function was written for. The X's frame is
  --- ABSOLUTE (ID_REMOVE_HIT; entryRemoveIcon says why it cannot be relative), so `cols` of them
  --- cost cols * that many pixels flat however narrow the row gets -- while what the names left for
  --- them is a fraction of the row. That fraction is the same at every column count: each column's
  --- name gives up ID_REMOVE_REL / cols, and the gutters come out of the names too, so the line
  --- always keeps 1 - (ID_MAIN_REL + ID_ACTION_REL) + ID_REMOVE_REL for the delete controls.
  --- Below that width Flow shrinks nothing -- it WRAPS, starting a new row as soon as
  --- `(framewidth) + usedwidth > width` (AceGUI-3.0.lua's Flow layout) -- so the trailing gutter,
  --- and then the last X, drop onto a row of their own and the grid stops being a grid.
  local function entryMinContent(iconStyle, cols, hasHelp)
    local floor = (ID_ICON_SIZE + ID_LABEL_MIN) / entryNameRel(iconStyle, cols, hasHelp)
    if iconStyle then
      local reserve = 1 - (ID_MAIN_REL + ID_ACTION_REL) + ID_REMOVE_REL
      floor = math.max(floor, cols * ID_REMOVE_HIT / reserve)
    end
    -- THE MARK'S FRAME IS ABSOLUTE TOO, so it needs the same treatment the X gets above: `cols` of
    -- them cost cols * ID_HELP_HIT flat, out of the fraction the names gave up for them. Without
    -- this the fit would pass a width that pays for the X and not for the mark, and the grid would
    -- break in the one place nothing reports.
    --
    -- SINCE MINOR 29 THIS IS NOT THE BINDING FLOOR at the counts the cap allows, and that is by
    -- construction rather than by luck: ID_HELP_REL was chosen so this lands UNDER the label floor
    -- above it (533 against 561 at two columns in the icon style -- the derivation is at the
    -- constant). The max stays anyway, because it is the only thing that would catch the next
    -- change to either number, which is exactly what minor 28 did not have.
    if hasHelp then
      floor = math.max(floor, cols * ID_HELP_HIT / ID_HELP_REL)
    end
    return floor
  end

  --- How many columns THIS render can pay for: the count the host asked for, dropped one column at
  --- a time while the measured content width is under entryMinContent, and never below one.
  ---
  --- A NARROWER LIST IS A CORRECT LIST; A BROKEN GRID IS NOT. That is the whole trade. One column of
  --- full-width entries is what every list drew before `columns` existed and is never wrong, only
  --- longer. Two columns on a canvas that cannot pay for them is icons stacked over wrapped names
  --- and, in the icon style, a delete control on a line of its own -- which no status line reports,
  --- which no host can see from its spec, and which the cap alone cannot prevent, because the cap is
  --- a guess about the canvas and this is a reading of it.
  ---
  --- UNMEASURED MEANS UNCHANGED. With no width to compare against (idContentWidth answering nil) the
  --- host's count is drawn exactly as it was before this check existed.
  ---
  --- MEASURED ONCE, AT DRAW TIME. A canvas that NARROWS afterwards is not re-fitted: the
  --- OnSizeChanged forwarder O.EnsureScroll installs re-runs the Flow layout at the new width
  --- (OnWidthSet / OnHeightSet / DoLayout / FixScroll) but never re-runs the page builder, and
  --- the fitted count is already baked into every child's relative width by then. So a player
  --- who drags the panel narrower after the page is drawn keeps the count the draw chose, until
  --- something re-renders the list. Left as is deliberately -- a re-fit would mean rebuilding a
  --- page on a drag, which is a far larger promise than this finding asked for.
  local function fitIdColumns(scroll, spec, columns, hasHelp)
    if columns <= 1 then return columns end
    local width = idContentWidth(scroll)
    if not width then return columns end
    local iconStyle = spec.removeStyle == "icon"
    while columns > 1 and width < entryMinContent(iconStyle, columns, hasHelp) do
      columns = columns - 1
    end
    return columns
  end

  --- The entry lines: `columns` entries per Flow row, filled row-major (1 2 / 3 4 / 5 6), each row
  --- added to the scroll once it is full and the last one added however full it is -- an odd count
  --- leaves the final row half empty rather than stretching the entry across it, because every
  --- width is relative to the row and none of them is asked to fill it.
  ---
  --- Guarded per ENTRY, as ChoiceGrid guards per row, and that is the property the row sharing has
  --- to be careful with: an entry whose kind lookup raises is trimmed back out of the row it was
  --- drawing into, so it costs itself and neither the neighbor already in that row nor the entries
  --- after it. With nothing else in the row yet, the row itself is dropped, which is exactly what
  --- minor 16 did with the one line an entry had to itself.
  ---
  --- Returns one line per entry DRAWN, in entry order; an entry that failed to draw has none. At
  --- more than one column the same row object is returned once per entry packed into it, so
  --- `lines[i]` is still the row carrying the i-th drawn entry.
  ---
  --- The count is FITTED to the canvas first (fitIdColumns): the host asks for a maximum, and a
  --- panel too narrow to pay for it is drawn at the count it can pay for rather than at the count
  --- it was asked for. That is a decision about THIS render, which is why it is taken here, where
  --- the scroll is, and not in idColumns, which reads the spec and nothing else.
  local function drawIdEntries(ctx, scroll, spec, k, entries, columns)
    -- Asked ONCE for the whole list, not per entry: see entryHelpLines. A list where no entry
    -- carries help draws no marks, claims no width for them and is byte-identical to minor 27.
    local hasHelp = listHasHelp(entries)
    columns = fitIdColumns(scroll, spec, columns, hasHelp)
    local lines, pending, filled = {}, nil, 0
    local function flush()
      if pending then scroll:AddChild(pending) end
      pending, filled = nil, 0
    end
    for _, entry in ipairs(entries) do
      if type(entry) == "table" and entry.id ~= nil then
        local cols = entryColumns(entry, columns)
        -- A full-width entry starts its own row, so anything half-packed goes out ahead of it.
        if cols == 1 and filled > 0 then flush() end
        local line = pending or startRow(O)
        local held = childCount(line)
        if renderRowGuarded(print, tostring(entry.id), idLine, ctx, spec, k, entry, line, cols, hasHelp) then
          lines[#lines + 1] = line
          pending, filled = line, filled + 1
          if filled >= cols then flush() end
        else
          trimChildren(line, held)
          if filled == 0 then
            -- Nothing else ever went into this row, and it was never added to the scroll -- so no
            -- ReleaseChildren anywhere will ever reach it. Hand it back here or the SimpleGroup
            -- leaks out of AceGUI's pool for the life of the session, one per failing entry that
            -- happened to be first in its row. Guarded for the same reason trimChildren is: the
            -- reason we are here at all is that something already raised.
            if type(line.Release) == "function" then pcall(line.Release, line) end
            pending = nil
          end
        end
      end
    end
    flush()
    return lines
  end

  --- The host's entries, or none: a raising entries() is reported and costs the lines, not the
  --- input, so the player can still add.
  local function listEntries(spec)
    if type(spec.entries) ~= "function" then return {} end
    local ok, list = pcall(spec.entries)
    if not ok then
      print(lib.STRINGS.ROW_FAILED:format(tostring(spec.heading or spec.label or "id list"),
        tostring(list)))
      return {}
    end
    return type(list) == "table" and list or {}
  end

  local function drawIdList(ctx, scroll, spec)
    if spec.heading then
      O.Section(ctx, spec.heading)
      ctx.lastGroup = spec.heading
    end
    drawIdInput(ctx, scroll, spec, rebuildIdList)

    local k = idKind(spec.kind)
    local entries = listEntries(spec)
    if #entries == 0 and spec.emptyText then O.TextRow(ctx, spec.emptyText) end
    local lines = drawIdEntries(ctx, scroll, spec, k, entries, idColumns(spec))
    O.AddSpacer(scroll, L.ROW_VSPACER)
    if scroll.DoLayout then scroll:DoLayout() end
    return lines
  end

  --- An editable id list (minor 16): an optional heading, the O.IdInput line, then one line per
  --- entry -- icon, name and id in gray ("Unknown spell 12345" when the client cannot name it),
  --- optionally a note line under the name in the same gray (K-3, drawn only when the entry
  --- carries one), then Remove, or a checkbox for a toggle entry. An item's name is drawn in its quality color
  --- once the client answers one; spell and currency names are plain. An item the client has not cached is asked
  --- for through LibKa0s-Item-1.0's LoadItem. Every id a render asks for joins one batch, checked
  --- once 0.4 s later: the list is drawn again once if any of them is named by then, and an id
  --- still unnamed is asked for again, up to five asks in all.
  ---
  --- spec = everything O.IdInput takes, plus:
  ---   entries     = function() -> ordered { { id =, toggle = bool?, on = bool?, note = string?,
  ---                 suffix = string? }, ... };
  ---   onRemove    = function(id), from an entry's Remove;
  ---   onToggle    = function(id, on), from a toggle entry's checkbox;
  ---   heading     = optional section heading, drawn with O.Section;
  ---   emptyText   = optional line drawn when there are no entries;
  ---   toggleLabel = optional label beside a toggle entry's checkbox;
  ---   removeStyle = optional, minor 21: "icon" draws a small X at the LEFT of every entry (the
  ---                 `transmog-icon-remove` atlas, tooltip `remove`) in place of the right-hand
  ---                 Remove button or checkbox; a click calls onRemove and rebuilds. Absent, the list
  ---                 is drawn exactly as before;
  ---   columns     = optional, minor 24: entries per line, packed row-major -- 1 2 / 3 4 / 5 6.
  ---                 Default 1, which draws exactly what minor 23 drew. Each entry's widths are
  ---                 divided by the count, so a two-column line is two 0.49 entries and still sums
  ---                 to 0.98; an odd count leaves the last row half empty rather than stretching the
  ---                 entry. Floored and clamped into 1..ID_COLUMNS_MAX, which is 2 and is AceGUI's
  ---                 number rather than a taste -- see the constant for the arithmetic. A
  ---                 non-number reads as 1. It is a MAXIMUM, not a promise: the count is measured
  ---                 against the width the render actually has (fitIdColumns) and drops toward one
  ---                 when the panel cannot pay for it, because a narrower list is a correct list
  ---                 and a wrapped grid is not. A render that cannot measure its width draws the
  ---                 count as asked. An entry with a `note` takes a full-width row of its
  ---                 own whatever the count, because the note is a second line under the name and
  ---                 cannot share a Flow row with a neighbor. At MORE THAN ONE COLUMN an entry
  ---                 name does NOT wrap: `entryNoWrap` turns word wrap off on the label's
  ---                 FontString, so the client truncates instead. That is not a preference, it is
  ---                 what keeps the grid: AceGUI's Flow center-aligns siblings by `alignoffset`
  ---                 (AceGUI-3.0.lua), so one wrapped two-line name in column one pushes the
  ---                 WHOLE of column two down and the names and the X icons in that row stop
  ---                 lining up. One line per entry, or no grid.
  ---                 THE COST, stated because it is the id that pays it: the name and the gray
  ---                 `(id)` are one FontString and truncation cuts the TAIL, so an entry too long
  ---                 for its column shows part of its name and NO ID AT ALL -- not a shortened
  ---                 one. The entry's tooltip still names it; the id is only on the row. A host
  ---                 whose ids must always be readable asks for one column, which still wraps
  ---                 exactly as it did at minor 23;
  ---                 A `suffix` is the opposite trade and is the FIRST thing truncation takes:
  ---                 it is appended to that same FontString after the id, so an entry that already
  ---                 overruns its column loses the suffix, then the id, then its own tail. That is
  ---                 the right order and it is why a suffix is a few words -- the character budget
  ---                 is in the API document;
  ---   helpIcon    = optional, minor 28: the texture every help mark in this list is drawn with.
  ---                 Since minor 29 the default is this library's own `info` art, resolved out of
  ---                 LibKa0s-Media-1.0 from the Options descriptor's `addonName` -- so a host that
  ---                 names itself gets the collection's glyph and needs this field only to draw
  ---                 something else. With no `addonName`, no Media major, or a Media that does not
  ---                 know the name, the mark falls back to the client's own information glyph, and
  ---                 the level tints below are muted there because that art is not white;
  ---   strings     = as O.IdInput's, plus remove and unknown.
  ---
  --- An entry may carry, beside its id:
  ---   note   = string, minor 17: a SECOND full-width Label under the name, in the id's gray, for a
  ---            sentence about the entry. A noted entry takes a full-width row of its own whatever
  ---            the column count;
  ---   suffix = string, minor 25: a few words drawn INSIDE the label, after the gray id and in the
  ---            same gray -- `Renewing Mist (119611) (also in 1)`. It adds no line and no row, so a
  ---            suffixed entry still pairs up under `columns`; it is truncated first at more than
  ---            one column; and it is concatenated, never formatted, so a `%` or a `|c` in it
  ---            reaches the client exactly as the host wrote it. The full story belongs in the
  ---            entry TOOLTIP, which the host already owns. Both may be set on one entry: the note
  ---            still wins its own full-width row and the suffix still rides the name.
  ---   help   = string | { string, ... }, minor 28: the lines behind the entry's information mark,
  ---            a small tinted glyph drawn between the delete control and the name. A LIST-LEVEL
  ---            question, not a per-entry one: a list where NO entry carries help draws no marks at
  ---            all and claims no width for them, and a list where ANY entry does gives EVERY entry
  ---            a mark -- dimmed, and answering no tooltip, on the ones with nothing to say --
  ---            because a column that appears and disappears down the list is not a column. The
  ---            entry's own name is the tooltip's title and the host's lines are its body. It adds
  ---            no line and no row, so a helped entry still pairs up under `columns`, but it does
  ---            raise that count's floor, because the mark's frame is absolute: a helped
  ---            two-column list in the ICON style wants ~561px of content where an unhelped one
  ---            wants 520, and in the DEFAULT style ~665px, which is past what a settings canvas
  ---            hands a page. A host that wants help AND two columns draws the X
  ---            (`removeStyle = "icon"`); the arithmetic is at ID_HELP_REL;
  ---            level = optional, minor 29, a key on the LIST form: "blocked" tints the mark red
  ---            (this entry can never match) and "info" the default gold (something to know about a
  ---            working one). The library cannot tell one kind of line from another, which is why
  ---            the host says. A level name this library does not know, and a `help` that is a
  ---            plain string or a plain list, both read as the default gold -- which is what minor
  ---            28 drew, so nothing written against it changes.
  ---
  --- The host owns storage: the widget calls back and never writes a path. After an add or a remove
  --- it redraws through `ctx.rebuild` when the host set one, else O.RefreshAllPanels(). A toggle
  --- redraws nothing -- the checkbox already shows the new state.
  ---
  --- Returns one line per entry drawn, in entry order; an entry that failed to draw has no line.
  --- With `columns` above 1 the same row object is returned once per entry packed into it, so
  --- `lines[i]` is still the row carrying the i-th drawn entry. Nil, drawing nothing, with no
  --- AceGUI.
  function O.IdList(ctx, spec)
    local scroll = O.EnsureScroll(ctx)
    if not scroll then return end
    spec = spec or {}
    return underDisable(ctx, spec.disabled, drawIdList, ctx, scroll, spec)
  end
end
