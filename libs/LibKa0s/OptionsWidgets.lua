-- LibKa0s-Options-1.0 — the schema-row -> AceGUI translation and the two-column flow engine.
--
-- Each maker reads through the descriptor's `get`, writes through its `set`, registers a refresher
-- closure so an external write re-syncs the widget, and adds itself to the container it was given.
-- RenderField dispatches by row.type; RenderRows lays an explicit row list into 50/50 flow rows
-- with section headings and spacers; RenderSchema is the thin per-page wrapper.
--
-- Part of the Options major rather than a major of its own, and guarded with the same multi-file
-- idiom as OptionsScroll.lua: a flow engine paired with a shell from a different vendored copy
-- would lay pages out wrong with nothing to notice it.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

-- Minor 14 takes the tab strip's buttons and the page's content panel from LibKa0s-Pool-1.0
-- instead of building them on every click, so the pool is a hard FLOOR here and not a nicety.
-- Absent or too old, this file is absent rather than half-wired: the alternative -- falling back
-- to allocating per click -- is precisely the leak this minor exists to end, and it would fall
-- back in silence. Both files ship in one payload and whole-folder vendoring is mandatory, so a
-- host that trips this floor has a broken copy rather than an unlucky one. The floor is also
-- unreachable in a well-formed tree: Pool.lua and Options.lua both gate on LibKa0s-Core-1.0 and
-- Pool.lua loads first in LibKa0s.xml, so a payload with no pool has no Options major to attach
-- to either and `lib` above is already nil.
local Pool = LibStub and LibStub("LibKa0s-Pool-1.0", true)
local NEEDS_POOL = 1
if not Pool or (Pool.MINOR or 0) < NEEDS_POOL then return end

local WIDGETS_MINOR = 16
-- Paired on the SHELL's minor as well as this file's own — see OptionsScroll.lua for why the
-- file's own counter is not enough.
if lib.__widgetsMinor and lib.__widgetsMinor >= WIDGETS_MINOR
  and lib.__widgetsShellMinor == lib.MINOR then return end
lib.__widgetsMinor      = WIDGETS_MINOR
lib.__widgetsShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsWidgets = WIDGETS_MINOR

local L = lib.LAYOUT

-- Live-preview color drags fire at up to 60 Hz. 50 ms is slow enough that a sustained drag costs
-- a handful of writes a second rather than sixty, and fast enough that the preview still tracks
-- the cursor.
local COLOR_THROTTLE = 0.05
-- Live-slider commits reuse the color picker's throttle: a 60 Hz drag would otherwise fan a
-- refresh pass out across every registered panel sixty times a second.
local DRAG_THROTTLE  = COLOR_THROTTLE

-- The tooltip BODY. `tooltip` is the name every Ka0s host's schema declares; `desc` is the one
-- this library invented, and it is kept because two shipped hosts use it. Reading only `desc`
-- blanked the body on every widget of any host on the standard's own shape — the label still
-- renders, so it failed silently and only in game.
local function tooltipBody(row)
  return row.tooltip or row.desc
end

-- The two-column split. Not BUTTON_PAIR_REL: a schema widget's label sits above its control, so it
-- has no border to be clipped and takes the honest half.
local HALF = 0.5

local function applyWidth(widget, relativeWidth)
  if relativeWidth then
    widget:SetRelativeWidth(relativeWidth)
  else
    widget:SetFullWidth(true)
  end
end

-- Both enum shapes the collection actually declares, normalized to one ordered list of
-- { value =, text = }.
--
--   ordered array   { { value = "SHORT", text = "Short" }, ... }   the Ka0s options schema
--   key map         { SHORT = "Short", LONG = "Long" }             AceGUI's own SetList shape
--   key set         { SHORT = true, LONG = true }                  the degenerate key map
--
-- The array is identified by its FIRST element being a table carrying `value`; nothing else in
-- play can look like that, so the two are distinguishable without a declared discriminator.
-- Array POSITION is the order — that is the entire point of the shape — so `sorting` is ignored
-- there. A key map keeps the existing rule: `sorting` if the row declares one, else sorted keys.
--
-- Evaluated at call time, not at load: a host's media list is populated by another addon and is
-- not knowable when the schema row is declared.
--
-- Duplicated verbatim in Slash.lua and OptionsWidgets.lua rather than hoisted into Core. The two
-- readers MUST agree — a CLI that accepts a value the dropdown cannot display is worse than
-- either being wrong alone — but hoisting would raise NEEDS_CORE in two majors, and
-- docs/releasing.md is explicit that a floor raise is a breaking change to the VENDORING: every
-- consumer carrying a stale Core.lua would lose both majors outright. The agreement is pinned by
-- a cross-major parity case instead, which is the cheaper guarantee.
local function enumList(row)
  local v = type(row.values) == "function" and row.values() or row.values
  if type(v) ~= "table" then return {} end

  if type(v[1]) == "table" and v[1].value ~= nil then
    local out = {}
    for i, item in ipairs(v) do
      out[i] = { value = item.value, text = item.text or tostring(item.value) }
    end
    return out
  end

  local keys = {}
  if type(row.sorting) == "table" then
    for i, k in ipairs(row.sorting) do keys[i] = k end
  else
    for k in pairs(v) do keys[#keys + 1] = k end
    -- Mixed key types would raise on a bare `<`. Homogeneous string keys sort exactly as before.
    table.sort(keys, function(a, b)
      if type(a) == type(b) then return a < b end
      return tostring(a) < tostring(b)
    end)
  end
  local out = {}
  for i, k in ipairs(keys) do
    -- `true` is the SET shape, and rendering it as the label is how a key set becomes a dropdown
    -- of entries all reading "true". The key is the only honest label such a row has.
    local text = v[k]
    out[i] = { value = k, text = type(text) == "string" and text or tostring(k) }
  end
  return out
end

local function snapToStep(value, mn, step)
  if not (step and step > 0) then return value end
  return math.floor((value - mn) / step + 0.5) * step + mn
end

-- ── the shared row plumbing ──────────────────────────────────────────────────────────────────
--
-- File-locals rather than closures inside the makers: they are created once at load and take the
-- instance as an argument, so nothing is allocated per render.

--- Apply a _G font-object NAME to an AceGUI text widget's FontString.
---
--- Guarded three ways because all three misses are real: AceGUI's Label only grows its `.label`
--- once it has been laid out, a widget mock may have neither, and a font object a client does not
--- ship resolves to nil. None of them may cost the page. The NAME is taken rather than the object
--- because a host declares its landing spec at file scope, where the font globals may not exist yet.
local function applyLabelFont(widget, fontName)
  if not fontName then return end
  local fs = widget.label
  if fs and fs.SetFontObject and _G[fontName] then
    fs:SetFontObject(_G[fontName])
  end
end

--- One full-width Flow row — the container the two-column engine packs a pair of widgets into.
--- Byte-identical in RenderGrid and RenderRows before it was hoisted here.
local function startRow(O)
  local r = O.AceGUI:Create("SimpleGroup")
  r:SetLayout("Flow")
  r:SetFullWidth(true)
  return r
end

--- Render one row (or one bespoke item) through `fn`, absorbing a raise and reporting it against
--- the row's path. Vararg because the two callers pass different argument shapes: a schema row goes
--- through O.RenderField(ctx, row, parent, relW), a bespoke item through its own
--- make(ctx, parent, relW).
---
--- Each ROW is guarded, not just the page. One corrupt saved value, or one `values` function that
--- raises because the media library it queries is half-loaded, used to take the whole page down
--- from inside AceGUI's layout pass — every row after it never drew, and the user saw a panel that
--- simply stopped mid-way with no error naming the row. The page-level guard added in Options minor
--- 3 catches a raising BUILDER; this catches a raising ROW, which is the more common failure and
--- the one a host cannot pre-empt.
local function renderRowGuarded(printer, path, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    printer(lib.STRINGS.ROW_FAILED:format(tostring(path or "?"), tostring(err)))
  end
  return ok
end

--- Emit a section heading when `row` opens a group the page has not drawn yet, and advance the
--- tracker. The previous group's tail row is flushed FIRST, or the heading lands above a widget
--- that belongs above IT.
---
--- `noHeadings` skips the O.Section call for a page whose sections are drawn as tabs instead
--- (options-ui-§13) -- but the flush and the tracker advance happen either way, or a later
--- group would be treated as a continuation of this one and the boundary flush between them
--- would never happen.
local function startGroup(O, ctx, row, flushRow, noHeadings)
  if not (row.group and row.group ~= ctx.lastGroup) then return end
  flushRow()
  if not noHeadings then O.Section(ctx, row.group) end
  ctx.lastGroup = row.group
  -- A subgroup belongs to ONE group. Leaving the tracker set across a group boundary would swallow
  -- the first subsection heading of the next group whenever the two happened to share a name --
  -- "Border" under Bars and "Border" under Tooltip is the shape the collection is about to be full
  -- of (options-ui-§16).
  ctx.lastSubgroup = nil
end

--- Emit a SUBSECTION heading when `row` opens a subgroup its group has not drawn yet, and advance
--- the tracker. The pending line is flushed FIRST, exactly as it is for a group heading, or the
--- heading lands packed beside a widget that belongs above it.
---
--- The sibling of startGroup, and deliberately NOT suppressed by `noHeadings`. That flag exists
--- because on a tabbed page the TAB is the group's heading -- but a tab that mixes control types
--- (a bar block, a background block and a border block, all under one label) has to say where one
--- stops and the next starts, and there is no tab left to name them with (options-ui-§7). So
--- `group` is what the strip partitions on and `subgroup` is what breaks a tab up inside itself;
--- a page uses either, both, or neither, and the tab list stays derivable from `group` alone.
---
--- ONE HEADING WIDGET IN THE COLLECTION: O.Section, the same AceGUI Heading every other header
--- uses. A hand-rolled colored label standing in for it is anti-patterns #71.
local function startSubgroup(O, ctx, row, flushRow)
  if not (row.subgroup and row.subgroup ~= ctx.lastSubgroup) then return end
  flushRow()
  O.Section(ctx, row.subgroup)
  ctx.lastSubgroup = row.subgroup
end

--- Does `row` have to start a fresh line?
---
--- Three fields, one question, hoisted out of the loop so the loop reads as the decision rather
--- than as the disjunction. They differ only in what happens AFTER the line opens -- see the field
--- list on O.RenderRows.
local function opensLine(row)
  return row.solo or row.wide or row.startsLine
end

--- Draw one row across BOTH columns, alone on its line. `nil` relative width is what applyWidth
--- turns into SetFullWidth, so no maker knows this case exists.
local function drawWide(O, ctx, row, pendingRow, printer)
  if not pendingRow then pendingRow = startRow(O) end
  renderRowGuarded(printer, row.path, O.RenderField, ctx, row, pendingRow, nil)
  return pendingRow
end

--- Claim a host hook for `key`, or nil if there is none or it has already run this render.
---
--- The lookup and the marking are ONE step on purpose. RenderRows honors two hook tables — pairWith
--- and afterGroup — and both are "fire at most once per render, and only if it actually fired";
--- splitting the two halves is how a caller ends up marking a hook it never ran, or running one it
--- already marked. `fired` is the LIBRARY's call-local ledger, never the host's table: see the note
--- in O.RenderRows for why consuming the host's entries silently breaks a second render.
local function takeOnce(hooks, fired, key)
  if not (hooks and key) then return nil end
  local hook = hooks[key]
  if not hook or fired[key] then return nil end
  fired[key] = true
  return hook
end

--- Draw one schema row into the pending Flow line, then attach its pairWith partner if it has one.
--- Returns the line and its widget count, because both advance and the caller decides on them.
---
--- The partner attaches only while the row is the LONE widget on its line: attaching to a line that
--- already holds two would make it three-wide and break the 50/50 split for the rest of the page.
--- A row whose render RAISED never counted, so it cannot pull a partner onto the line either.
local function drawRow(O, ctx, row, pendingRow, pendingCount, pairWith, firedPair, printer)
  if not pendingRow then pendingRow = startRow(O) end
  if renderRowGuarded(printer, row.path, O.RenderField, ctx, row, pendingRow, HALF) then
    pendingCount = pendingCount + 1
  end
  if pendingCount == 1 then
    -- A bound row (OptionsCompose's `spec.bind`) has no path, so it is keyed by its record field.
    local pair = takeOnce(pairWith, firedPair, row.path or row.field)
    if pair then
      pair(ctx, pendingRow)
      pendingCount = pendingCount + 1
    end
  end
  return pendingRow, pendingCount
end

--- Close out a group on its LAST row — the next row opens a different group, or there is no next
--- row — by running the host's afterGroup hook for it. The counterpart to startGroup, and the loop
--- reads as the pair: open the group, draw the row, close the group.
---
--- The pending line is flushed FIRST. afterGroup draws buttons, and they belong on a fresh line
--- rather than packed into the empty half of the group's tail row.
local function endGroup(ctx, afterGroup, firedAfter, row, nextRow, flushRow)
  if not (row.group and (not nextRow or nextRow.group ~= row.group)) then return end
  local after = takeOnce(afterGroup, firedAfter, row.group)
  if not after then return end
  flushRow()
  after(ctx)
end

-- ── the landing page ─────────────────────────────────────────────────────────────────────────
--
-- Three blocks, one file-local each, assembled by O.BuildLandingPage. Promoted out of three hosts
-- that each carried a function literally named Helpers.BuildMainContent rendering the same page
-- with the same four constants; the only differences were the logo path and where the one-liner
-- came from, which is why both are spec DATA here.

--- The logo block. A full-width SimpleGroup with its layout suppressed, holding a texture anchored
--- TOPLEFT at its native size, so the art renders pixel-exact and left-aligned regardless of how
--- wide the panel is.
---
--- The `.frame` handle and the texture it hands back are both guarded, for the same reason every
--- other widget touch in this file is: an AceGUI widget mock has no backing frame, and a
--- CreateTexture that answers nil is the shape a stubbed one takes. It matters MORE here than
--- elsewhere — BuildLandingPage runs under the renderer's pcall, so one raise on the logo prints
--- RENDER_FAILED and costs the notes and every section too, i.e. the whole page for the sake of a
--- picture. The group and its spacer are added either way, so a missing texture leaves a gap where
--- the art goes rather than re-flowing everything under it.
---
--- A TEXTURE OUTLIVES THE WIDGET THAT DREW IT, and that is the whole reason this is not three
--- lines. AceGUI POOLS its widget frames: Release hides a frame and hands the same one back on the
--- next Create. A texture created on it is not a widget, so nothing releases it and nothing hides
--- it — it rides the frame into the pool and reappears the next time that frame is handed out. So
--- a host with a logo grew a SECOND logo partway down its own landing page, intermittently,
--- depending only on pool order: the stale texture belonged to a SimpleGroup being used for
--- something else entirely. BuildLandingPage's ClearScroll cannot help, because there is no widget
--- there to clear.
---
--- Two halves, and both are needed. The texture is kept ON the frame and reused, so a frame that
--- comes back for another logo cannot accumulate a second one; and it is hidden when the widget is
--- released, so a frame that comes back for anything else does not show it. `SetCallback` is safe
--- here because AceGUI fires "OnRelease" BEFORE it clears a widget's callbacks, and this one is set
--- fresh on every acquisition.
local function landingLogo(O, scroll, spec)
  if not spec.logo then return end

  local size  = spec.logoSize or L.LANDING_LOGO
  local group = O.AceGUI:Create("SimpleGroup")
  group:SetLayout(nil)
  group:SetFullWidth(true)
  group:SetHeight(size)

  local frame = group.frame
  local tex   = frame and frame.__ka0sLandingLogo
  if not tex and frame and frame.CreateTexture then
    tex = frame:CreateTexture(nil, "ARTWORK")
    frame.__ka0sLandingLogo = tex
  end
  if tex then
    tex:SetTexture(spec.logo)
    tex:SetSize(size, size)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    tex:Show()
    group:SetCallback("OnRelease", function() tex:Hide() end)
  end
  scroll:AddChild(group)

  O.AddSpacer(scroll, L.LANDING_GAP_LOGO)
end

--- The one-liner under the logo.
---
--- Resolved at RENDER time when it is a function, because the usual source is the TOC's Notes field
--- and a host that declares its spec at file scope cannot read that yet. An empty or absent
--- one-liner skips the Label AND its spacer together — a lone gap under the logo reads as a broken
--- margin rather than as a missing sentence.
local function landingNotes(O, ctx, scroll, spec)
  local notes = spec.notes
  if type(notes) == "function" then notes = notes() end
  if type(notes) ~= "string" or notes == "" then return end

  O.TextRow(ctx, notes, { fontObject = "GameFontHighlight" })
  O.AddSpacer(scroll, L.LANDING_GAP_DESC)
end

--- One heading plus its rows, per section.
---
--- `rows` is a FUNCTION, not an array, so a re-render picks up a command registered since the spec
--- was declared: the list a host passes here is generated from its command table, which grows as
--- other files load.
---
--- The heading goes through O.Section, which already emits SECTION_BOTTOM_SPACER under it — the
--- same 6 the three hosts spelled MAIN_GAP_BELOW_HEAD, and what LANDING_GAP_HEAD names. A second
--- spacer here would double that gap. ctx.lastGroup is advanced for the same reason RenderRows
--- advances it: it is what puts SECTION_TOP_SPACER above the SECOND heading and not above the first.
local function landingSections(O, ctx, spec)
  for _, section in ipairs(spec.sections or {}) do
    O.Section(ctx, section.heading)
    ctx.lastGroup = section.heading
    for _, line in ipairs(section.rows and section.rows() or {}) do
      O.TextRow(ctx, line)
    end
  end
end

-- ── tab strip art (options-ui-§13) ──────────────────────────────────────────────────────────
--
-- The CLIENT'S OWN modern tab atlases, and the client's own inner-frame art under them. Every
-- number and every anchor below is lifted from OPie's `Libs/TenSettings.lua` (`minitab_new`,
-- `minitab_select`, `container_new`), which is the reference implementation this strip is meant
-- to look like -- with one deliberate departure: OPie chains its tabs rightward from the frame's
-- right edge, and this strip packs them left to right, because a wrapping strip has to grow
-- downward from a fixed origin and the left edge is the one our content column already uses.
--
-- Copied rather than approximated on purpose. A tab is a piece of client chrome a player already
-- recognizes, so a near-miss reads worse than a drawn control that never claimed to be one --
-- which is exactly how the previous two attempts here failed: first flat fills with gold borders,
-- then the OLD `Interface/OptionsFrame/` tab textures, whose sloped transparent shoulders made a
-- 4px gap look like twelve.
local TAB_ATLAS = {
  [false] = { "Options_Tab_Left",        "Options_Tab_Middle",        "Options_Tab_Right"        },
  [true]  = { "Options_Tab_Active_Left", "Options_Tab_Active_Middle", "Options_Tab_Active_Right" },
}

-- THE STRIP'S GEOMETRY IS SELECTION-INVARIANT (options-ui-§13, anti-patterns #70). Nothing about
-- where a tab lands, how many rows the strip wraps into, or how tall a band it reserves may depend
-- on WHICH tab is selected. That is a rule and not a preference: the content panel hangs off the
-- chrome's bottom edge, so a band that moves with the selection moves and resizes the whole page
-- under it, and the player sees the page shift when they click a tab.
--
-- IT WAS BROKEN EXACTLY THERE. TabStrip recorded the pitch from the FIRST tab it drew, whichever
-- that happened to be, and the selected tab is cut from `Options_Tab_Active_*` while the rest come
-- from `Options_Tab_*` -- two families the client does not draw at the same height. So on a page
-- whose strip WRAPS, selecting tab 1 packed the rows by the active art and selecting any other
-- packed them by the inactive art. Reported from a client against ConsumableMaster's Macros page
-- (three wrapped rows; the gap on one tab alone) and again on its Macro Bar page. Nothing failed:
-- a harness that answers one height for every atlas cannot see it.
--
-- So the pitch is measured ONCE, from the INACTIVE cap atlas, on a throwaway texture -- never read
-- back off a tab that was just drawn in whichever state it happened to be in. The inactive family
-- and not max(active, inactive) because the inactive height is what every unselected tab is drawn
-- from, and wrapped rows sitting FLUSH is what minor 12 was for; the selected tab's art then stands
-- a pixel or two proud into the row above, which is the direction TAB_BG_TOP and TAB_LABEL_Y
-- already lift it deliberately.
--
-- Measured rather than declared because an atlas has no height until the client resolves one, and
-- CACHED ON SUCCESS ONLY, so a call made before it resolves -- a headless harness, a client
-- mid-load -- cannot pin the fallback for the session.
local measuredArtH
local probeFrame

--- The probe texture: one frame, one texture, kept for the life of the session.
local function probeTexture()
  probeFrame = probeFrame or CreateFrame("Frame", nil, UIParent)
  if probeFrame.Hide then probeFrame:Hide() end
  local tex = probeFrame.__ka0sTabProbe
  if not tex and probeFrame.CreateTexture then
    tex = probeFrame:CreateTexture(nil, "BACKGROUND")
    probeFrame.__ka0sTabProbe = tex
  end
  return tex
end

--- How far apart two rows of tabs sit: the UNSELECTED tab art's own height, so a wrapped row is
--- FLUSH with the one above it rather than separated by the empty strip along each button's top.
--- Falls back to the button height where nothing can be measured, which is the pre-measurement
--- behavior with no gap.
--- @return number  the pitch a wrapped strip's rows are packed by, and its hit-rect inset
local function tabArtHeight()
  if measuredArtH then return measuredArtH end

  local h
  local tex = probeTexture()
  if tex and tex.SetAtlas then
    tex:SetAtlas(TAB_ATLAS[false][1], true)
    h = tex.GetHeight and tex:GetHeight()
  end

  if type(h) == "number" and h > 0 and h <= L.TAB_H then
    measuredArtH = h
    return h
  end
  return L.TAB_H
end

--- Forget the measurement AND the frame it was taken on. A suite seam, and the one thing a live
--- session cannot need: an atlas does not change size mid-session.
local function resetTabArtHeight()
  measuredArtH, probeFrame = nil, nil
end
-- The page's content box. Its TOP EDGE is the tab/content separator (options-ui-§13) -- there is
-- no hairline rule any more, because in this design the divider is a real panel edge that the
-- selected tab's foot sits on, which is the whole reason the strip reads as attached to the page
-- rather than floating above it.
local PANEL_ATLAS = "Options_InnerFrame"
-- The atlas is one piece of frame art with the good corner on its right, so it is drawn TWICE --
-- each half spanning an outer edge to the panel's midpoint, the left half horizontally MIRRORED
-- by a reversed u range. That is what keeps both corners crisp instead of stretching one across
-- the whole width. OPie's trick and OPie's numbers.
local PANEL_SEAM_U = 0.64

-- Per-state geometry, all of it OPie's. The label rides 2px higher on the selected tab, and the
-- dark backing stops 3px lower, so a selected tab reads as standing slightly proud of the row.
local TAB_LABEL_Y = { [false] = 6,   [true] = 8   }
local TAB_BG_TOP  = { [false] = -15, [true] = -12 }
-- The hover glow and the selected glow are the same gradient at different heights; which of the
-- two is visible is a color-texture toggle, not a Show/Hide, because they live on different
-- layers (HIGHLIGHT vs BACKGROUND) and only the HIGHLIGHT one is drawn on mouseover at all.
local TAB_HL_TOP   = 12
local TAB_SEL_TOP  = 16
local TAB_BG_INSET = 2

local TAB_BG_BOTTOM_COLOR = { r = 0.10, g = 0.10, b = 0.10, a = 0.85 }
local TAB_BG_TOP_COLOR    = { r = 0.15, g = 0.15, b = 0.15, a = 0.85 }
local TAB_GLOW_BOTTOM     = { r = 1,    g = 1,    b = 1,    a = 0.15 }
local TAB_GLOW_TOP        = { r = 0,    g = 0,    b = 0,    a = 0    }

-- The banner/strip hairline keeps a dim-gold, low-alpha treatment (options-ui-§14): a separator
-- between two pieces of chrome should disappear rather than read. It is the LAST drawn rule in
-- this file -- the strip's own separator became the content panel's edge.
local CHROME_RULE_COLOR   = { 1, 0.82, 0, 0.16 }

--- Create and color one 1px edge texture. Guarded like every other texture path in this file --
--- a headless mock's CreateTexture can answer an inert table with no SetColorTexture -- so a
--- caller gets nil rather than a half-built texture to keep positioning.
local function edgeTexture(parent, layer, color)
  local tex = parent.CreateTexture and parent:CreateTexture(nil, layer)
  if not (tex and tex.SetColorTexture) then return nil end
  tex:SetColorTexture(color[1], color[2], color[3], color[4])
  return tex
end

--- Create one texture on `b`, or nil when this frame cannot make them.
---
--- Guarded like every other texture path in this file: a headless mock's CreateTexture can answer
--- an inert table, so a caller gets nil rather than a half-built texture to keep positioning.
local function tabTexture(b, layer, sublevel)
  local tex = b.CreateTexture and b:CreateTexture(nil, layer, nil, sublevel)
  if not (tex and tex.SetPoint) then return nil end
  return tex
end

--- Apply a vertical gradient, bottom color first. Split out only because every call site needs
--- the same two guards and the modern table-color signature is easy to get subtly wrong.
local function gradient(tex, bottom, top)
  if tex and tex.SetGradient then tex:SetGradient("VERTICAL", bottom, top) end
end

--- Show or hide one of the two glow textures. They are toggled by color rather than by
--- Show/Hide because that is how OPie does it and because a hidden HIGHLIGHT texture and a
--- transparent one are not the same thing to the mouseover machinery.
local function setGlow(tex, on)
  if tex and tex.SetColorTexture then
    if on then tex:SetColorTexture(1, 1, 1, 1) else tex:SetColorTexture(0, 0, 0, 0) end
  end
end

--- A tab button's six textures, created ONCE and kept on the button as `__ka0sTabArt`.
---
--- The split into a create half and a dress half is the whole of minor 14 at the texture level.
--- A pooled button that rebuilt its art on every dress would trade a frame leak for a texture
--- leak: WoW destroys neither, and a texture created on a recycled frame rides that frame back
--- into the pool -- the failure this file already documents for the landing-page logo. So the
--- STATE-INDEPENDENT half lives here (which textures exist, and every anchor a selection cannot
--- move) and only the state-dependent half is re-applied per dress.
---
--- The three slices are two end caps at their NATURAL atlas size and a middle stretched
--- horizontally between their inner edges. A tab narrower than the two caps would draw them
--- overlapping rather than tearing, which is why TAB_MIN_W is comfortably wider than either.
---
--- It MEASURES NOTHING. The art is anchored to the button's BOTTOM and takes the atlas's own size,
--- so a 37px button carrying 28px of art has nine empty pixels along its top -- but that number is
--- tabArtHeight's to answer, from a state no click can change, and reading it back off a tab drawn
--- in whichever state it happened to be in is the defect this file's atlas section describes.
local function newTabArt(b)
  local art = {}
  art.left  = tabTexture(b, "BACKGROUND")
  art.right = tabTexture(b, "BACKGROUND")
  art.mid   = tabTexture(b, "BACKGROUND")
  if art.left  then art.left:SetPoint("BOTTOMLEFT")   end
  if art.right then art.right:SetPoint("BOTTOMRIGHT") end
  if art.mid and art.left and art.right then
    art.mid:SetPoint("TOPLEFT",  art.left,  "TOPRIGHT")
    art.mid:SetPoint("TOPRIGHT", art.right, "TOPLEFT")
  end

  -- The dark backing behind the label, and the two glows. Their anchors DO move with the
  -- selection, so they are set in the dress half rather than here.
  art.fill = tabTexture(b, "BACKGROUND", -2)
  art.hl   = tabTexture(b, "HIGHLIGHT")
  art.sel  = tabTexture(b, "BACKGROUND", -1)
  return art
end

--- Re-aim the three slices at one state's atlas family.
---
--- Left, right, then middle, which is the order the slices were CREATED in and the order a suite
--- reads them back in -- the family check reads slice 1 and expects the left cap.
local function dressTabSlices(art, atlas)
  if art.left  and art.left.SetAtlas  then art.left:SetAtlas(atlas[1],  true) end
  if art.right and art.right.SetAtlas then art.right:SetAtlas(atlas[3], true) end
  if art.mid   and art.mid.SetAtlas   then art.mid:SetAtlas(atlas[2],   true) end
end

--- The dark backing behind the label, inset so it never touches the caps' lit edges. It stops
--- 3px higher on the selected tab, which is half of how the two states differ.
local function dressTabFill(bg, active)
  if not bg then return end
  if bg.ClearAllPoints then bg:ClearAllPoints() end
  bg:SetPoint("BOTTOMLEFT", TAB_BG_INSET, 0)
  bg:SetPoint("TOPRIGHT", -TAB_BG_INSET, TAB_BG_TOP[active])
  if bg.SetColorTexture then bg:SetColorTexture(1, 1, 1, 1) end
  gradient(bg, TAB_BG_BOTTOM_COLOR, TAB_BG_TOP_COLOR)
end

--- One of the two glows. They are the same gradient at different heights on different layers:
--- the HIGHLIGHT one is drawn by the client on mouseover only, the BACKGROUND one is lit for as
--- long as the tab is selected. Only one is ever on, which is why `on` is a parameter rather
--- than a second function.
local function dressTabGlow(b, tex, top, on)
  if not tex then return end
  if tex.ClearAllPoints then tex:ClearAllPoints() end
  tex:SetPoint("BOTTOMLEFT", TAB_BG_INSET, 0)
  tex:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", -TAB_BG_INSET, top)
  setGlow(tex, on)
  gradient(tex, TAB_GLOW_BOTTOM, TAB_GLOW_TOP)
end

--- Put one tab button's art into the state it is being drawn in: the atlas family, the backing's
--- height, and which of the two glows is lit.
---
--- Split four ways rather than written straight through, because every texture path in this file
--- carries the same two guards and a single function wearing all of them measured past the CCN
--- ceiling the release gate enforces. Every texture is a child of `b` and travels with it into
--- the pool and back out, so no ledger entry is needed for any of them.
local function dressTabArt(b, active)
  local art = b.__ka0sTabArt
  if not art then return end
  dressTabSlices(art, TAB_ATLAS[active])
  dressTabFill(art.fill, active)
  dressTabGlow(b, art.hl,  TAB_HL_TOP,  not active)
  dressTabGlow(b, art.sel, TAB_SEL_TOP, active)

  -- The empty strip along the button's top is not part of the tab and must not be clickable: a
  -- wrapped strip packs the next row by the ART's height, so row 2's button overlaps row 1's art by
  -- exactly that many pixels, and without this it would swallow clicks meant for row 1.
  --
  -- THE SAME NUMBER THE ROWS ARE PACKED BY, for every button including the selected one. Taken off
  -- each tab's own art it was the inactive height on the unselected tabs and the active height on
  -- the selected one, so the invariant this comment states held for all but one button per strip.
  if b.SetHitRectInsets then b:SetHitRectInsets(0, 0, L.TAB_H - tabArtHeight(), 0) end
end

--- The tab's label, anchored to the tab's BOTTOM rather than its center, in the UNSELECTED font.
---
--- A tab is taller than its text by design -- the extra height is the foot that overlaps the
--- content panel -- so a centered label would float in the middle of the overlap instead of
--- sitting on the tab's face.
---
--- IT DOES NOT APPLY THE SELECTED FONT, and that is the whole reason it and setTabFont are two
--- functions. A tab's WIDTH is measured off this FontString, and a measurement taken under a font
--- that depends on the selection is a wrap index that depends on the selection -- the same defect
--- the pitch had (options-ui-§13). The two fonts are the same size today, so no wrap index moves;
--- pinning the order is what keeps that true rather than lucky.
local function setTabLabel(b, text)
  -- The FontString is made ONCE and then re-used, for the same reason the art is: a dressed
  -- button is a button that already has one, and a second CreateFontString per click would leak a
  -- string per click on a frame that is never destroyed. `false` rather than nil marks "this frame
  -- cannot make one", so a headless stub is not re-asked on every dress.
  if b.__ka0sTabLabel == nil then
    local fs = b.CreateFontString and b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if fs and b.SetFontString then
      b:SetFontString(fs)
      if fs.ClearAllPoints then fs:ClearAllPoints() end
    end
    b.__ka0sTabLabel = fs or false
  end
  b:SetNormalFontObject(_G.GameFontNormalSmall)
  b:SetHighlightFontObject(_G.GameFontHighlightSmall)
  b:SetDisabledFontObject(_G.GameFontHighlightSmall)
  if b.SetPushedTextOffset then b:SetPushedTextOffset(0, 0) end
  b:SetText(text or "")
end

--- The other half of how the two states differ: the selected tab lifts its label 2px and brightens
--- the font. Applied AFTER the label has been measured, never before.
local function setTabFont(b, active)
  local fs = b.GetFontString and b:GetFontString()
  if fs and fs.SetPoint then
    if fs.ClearAllPoints then fs:ClearAllPoints() end
    fs:SetPoint("BOTTOM", 0, TAB_LABEL_Y[active])
  end
  if active then b:SetNormalFontObject(_G.GameFontHighlightSmall) end
end

--- The page's content box (options-ui-§13): the client's inner-frame art, spanning the content
--- column from the bottom of the chrome band to the bottom of the page.
---
--- **Its top edge is the tab/content separator.** The strip draws no rule of its own — the
--- selected tab's foot lands on this panel's top edge and merges into it, which is the whole
--- reason a row of buttons reads as tabs attached to a page rather than as chrome floating above
--- one. A 1px line cannot do that job; it was tried, and it read as disconnected.
---
--- Drawn only by TabStrip, so an UNTABBED page — every page in eight of the nine consumers — is
--- untouched and keeps rendering exactly as it always has.
---
--- The frame is parented to `ctx.body` and anchored to `ctx.chrome`'s bottom, so it follows the
--- band automatically when a strip wraps to a second row. It is forced to the body's OWN frame
--- level: a child frame otherwise sits one level above its parent, which would put this art in
--- front of the scroll it is supposed to sit behind.
---
--- This half BUILDS one, and is the pool's factory; drawContentPanel below is what a render calls.
local function newContentPanel(ctx)
  local panel = CreateFrame("Frame", nil, ctx.body)
  if panel.SetFrameLevel and ctx.body.GetFrameLevel then
    local level = ctx.body:GetFrameLevel()
    if type(level) == "number" then panel:SetFrameLevel(level) end
  end

  -- Two halves meeting at the panel's midpoint, the left one mirrored by a reversed u range.
  local leftHalf = panel.CreateTexture and panel:CreateTexture(nil, "BACKGROUND")
  if leftHalf and leftHalf.SetAtlas and leftHalf.SetTexCoord then
    leftHalf:SetAtlas(PANEL_ATLAS)
    leftHalf:SetPoint("TOPLEFT")
    leftHalf:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", 0, 0)
    leftHalf:SetTexCoord(1, PANEL_SEAM_U, 0, 1)
  end

  local rightHalf = panel.CreateTexture and panel:CreateTexture(nil, "BACKGROUND")
  if rightHalf and rightHalf.SetAtlas and rightHalf.SetTexCoord then
    rightHalf:SetAtlas(PANEL_ATLAS)
    rightHalf:SetPoint("TOPRIGHT")
    rightHalf:SetPoint("BOTTOMLEFT", panel, "BOTTOM", 0, 0)
    rightHalf:SetTexCoord(PANEL_SEAM_U, 1, 0, 1)
  end

  return panel
end

--- Acquire the page's content panel and anchor it under the chrome band.
---
--- ONE PANEL PER PAGE, acquired from a pool of one rather than built per click. A pool for a
--- single object looks like ceremony and is not: the panel is created by the same tab click that
--- creates the buttons, so it leaked on exactly the same schedule, and giving it its own pool is
--- what lets one release seam hand back everything a click borrowed.
---
--- The anchors are re-stated on every acquire rather than only at construction. They cost four
--- SetPoints once per render, and stating them here is what keeps the panel's whole contract --
--- where its four corners land -- readable in one place instead of split across a lifetime.
local function drawContentPanel(ctx)
  if not (ctx.body and ctx.chrome) then return end
  ctx.__panelPool = ctx.__panelPool or Pool.New()
  local panel = Pool.Acquire(ctx.__panelPool, function() return newContentPanel(ctx) end)

  -- Vertically it hangs off the chrome, so it follows the band when a strip wraps to a second
  -- row. Horizontally it is anchored to the BODY, not the chrome: the box has to be wider than
  -- the content column it encloses, or the scrollbar is painted on its right edge and the
  -- left-hand labels butt against its left one.
  panel:SetPoint("TOPLEFT",     ctx.chrome, "BOTTOMLEFT",  -(L.CONTENT_LEFT - L.PANEL_LEFT), 0)
  panel:SetPoint("TOPRIGHT",    ctx.chrome, "BOTTOMRIGHT",   L.CONTENT_RIGHT - L.PANEL_RIGHT, 0)
  panel:SetPoint("BOTTOMLEFT",  ctx.body,   "BOTTOMLEFT",    L.PANEL_LEFT,  L.PANEL_BOTTOM)
  panel:SetPoint("BOTTOMRIGHT", ctx.body,   "BOTTOMRIGHT",  -L.PANEL_RIGHT, L.PANEL_BOTTOM)

  ctx.__tabKids[#ctx.__tabKids + 1] = panel
end

--- The hairline rule between the banner and the tab strip (options-ui-§14), spanning the
--- chrome's full width. Parked in the BANNER's own ledger (`ctx.__chromeKids`), not the strip's:
--- only a full page render redraws the banner, so a tab click alone must never touch this
--- texture the way it touches `ctx.__tabKids`.
local function drawChromeDivider(ctx, rawBannerHeight)
  local tex = edgeTexture(ctx.chrome, "ARTWORK", CHROME_RULE_COLOR)
  if not tex then return end
  local y = -(rawBannerHeight + L.CHROME_DIVIDER_GAP_TOP)
  tex:SetPoint("TOPLEFT",  ctx.chrome, "TOPLEFT",  0, y)
  tex:SetPoint("TOPRIGHT", ctx.chrome, "TOPRIGHT", 0, y)
  tex:SetHeight(L.CHROME_DIVIDER_H)
  ctx.__chromeKids[#ctx.__chromeKids + 1] = tex
end

-- ── id resolution (minor 16) ──────────────────────────────────────────────────────────────
--
-- What O.ResolveId, O.IdInput and O.IdList use to turn typed text into an id. Pure, and at file
-- scope for that reason: nothing here touches a widget or an instance, so it is built once at load.
--
-- THE CLIENT APIS ARE READ AT CALL TIME, and every one is guarded. A client without C_Spell (or a
-- harness that cleared it) degrades to id-only input: a number or a link still resolves, a name
-- finds nothing, and nothing raises.

--- A spell by id, or by a name the client knows: its id, name and icon, spelled as the client
--- spells it. The client's name lookup ignores case, so a player typing in lower case is served.
local function spellLookup(key)
  local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(key)
  if type(info) ~= "table" then return nil end
  return info.spellID, info.name, info.iconID
end
local function spellInfo(id)
  local _, name, icon = spellLookup(id)
  return name, icon
end

--- An item's id and icon from GetItemInfoInstant, which needs no cache; its name from
--- GetItemNameByID, which does. An uncached item answers its icon and no name.
local function itemInstant(key)
  if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
  local id, _, _, _, icon = C_Item.GetItemInfoInstant(key)
  return id, icon
end
local function itemName(id)
  if not (C_Item and C_Item.GetItemNameByID) then return nil end
  return C_Item.GetItemNameByID(id)
end
local function itemInfo(id)
  local _, icon = itemInstant(id)
  return itemName(id), icon
end
local function itemByName(text)
  local id, icon = itemInstant(text)
  if not id then return nil end
  return id, itemName(id) or text, icon
end

--- The color code an item's name is drawn in: the client's quality for the id, through its own
--- ITEM_QUALITY_COLORS palette. Nil, for a plain name, while the item is uncached (the client
--- answers no quality until it is) or the palette has no entry; the redraw a load triggers colors
--- it. The palette is read at call time, as LibKa0s-Item-1.0 reads it: it may be unpopulated when
--- this file loads.
local function itemQualityColor(id)
  local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
  local color = type(quality) == "number" and type(ITEM_QUALITY_COLORS) == "table"
    and ITEM_QUALITY_COLORS[quality]
  return type(color) == "table" and type(color.hex) == "string" and color.hex or nil
end

--- A currency has no client name lookup, so a name reaches one only through the host's
--- candidates. An empty name is the client's answer for an id it does not have.
local function currencyInfo(id)
  local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
  if type(info) ~= "table" or type(info.name) ~= "string" or info.name == "" then return nil end
  return info.name, info.iconFileID
end

-- One row per kind: what a message calls it, the link type it parses, how an id is named, how a
-- name is looked up, which GameTooltip method shows it, and whether an unnamed one can be loaded.
-- A kind the host names that is not here, or no kind at all, is ID_ONLY: numbers only.
local ID_KINDS = {
  spell    = { noun = "spell", plural = "spells", link = "spell", info = spellInfo,
               byName = spellLookup, tooltip = "SetSpellByID" },
  item     = { noun = "item", plural = "items", link = "item", info = itemInfo,
               byName = itemByName, tooltip = "SetItemByID", loads = true },
  currency = { noun = "currency", plural = "currencies", link = "currency", info = currencyInfo,
               tooltip = "SetCurrencyByID" },
}
local ID_ONLY = { noun = "entry", plural = "entries" }

-- The kinds whose entry names are drawn in a color, keyed by the kind table itself so a host's own
-- kind table never matches: an item's quality color. A spell and a currency are drawn plain.
local NAME_COLOR = { [ID_KINDS.item] = itemQualityColor }

--- The kind table for `kind`: a host's own table as given, a named kind, or ID_ONLY.
local function idKind(kind)
  if type(kind) == "table" then return kind end
  return ID_KINDS[kind] or ID_ONLY
end

--- What a message calls `k`, singular and plural. A host kind names itself or reads as "entry".
local function kindWords(k)
  local noun = k.noun or ID_ONLY.noun
  return noun, k.plural or (k.noun and k.noun .. "s") or ID_ONLY.plural
end

-- The widgets' words. A literal table, as lib.STRINGS is: the library carries no locale, and a
-- host that has one passes `spec.strings` with any of these keys. `{name}` tokens rather than
-- format specifiers, so a translation can put the words in its own order -- Lua 5.1's
-- string.format has no positional arguments.
local ID_TEXT = {
  add       = "Add",
  remove    = "Remove",
  empty     = "Type an id, a link or a name.",
  notFound  = "No {noun} named '{text}'.",
  ambiguous = "Several {plural} are named '{text}' \226\128\148 pick one from the list, or use the id.",
  unknown   = "Unknown {noun} {id}",
  looking   = "Looking up {plural}\226\128\166",
  nameHint  = "",
  more      = "+{count} more",
}

-- The named kinds' own words, over ID_TEXT's: a notFound that says where a name can come from, and
-- the hint it ends with (`{hint}`, filled from the `nameHint` key, so a host that rewords the hint
-- rewords both). Keyed by the kind table, as NAME_COLOR is, so a host's own kind never matches.
-- The client has no item-name search: GetItemInfoInstant(name) answers only for an item the player
-- carries or carried this session, and C_Spell.GetSpellInfo(name) only for a spell in the player's
-- own spellbook. Anything else reaches a name through the host's candidates alone.
local KIND_TEXT = {
  [ID_KINDS.item] = {
    notFound = "No item named '{text}' that the game can find. {hint}",
    nameHint = "Names work for items you carry (or carried this session) and ones this list "
      .. "knows; otherwise use the id or shift-click a link.",
  },
  [ID_KINDS.spell] = {
    notFound = "No spell named '{text}' in your spellbook. {hint}",
    nameHint = "Names work for spells in your spellbook and ones this list knows; otherwise use "
      .. "the id or shift-click a link.",
  },
  [ID_KINDS.currency] = {
    notFound = "No currency named '{text}' that this list knows. {hint}",
    nameHint = "Currency names work only for the currencies this list knows; otherwise use the id "
      .. "or shift-click a link.",
  },
}

--- A word for `key` in `kind`'s own set, or nil for the shared default.
local function kindText(kind, key)
  local row = KIND_TEXT[idKind(kind)]
  return row and row[key]
end

--- Fill `{name}` tokens from `fields`; a token with no field is left as written.
local function fillText(template, fields)
  return (tostring(template):gsub("{(%a+)}", function(key)
    local v = fields[key]
    if v ~= nil then return tostring(v) end
  end))
end

local function parseNumber(text)
  return tonumber(text:match("^(%d+)$"))
end

--- The id in a link of `link`'s type -- a chat link (`|Hspell:123:...`) or the bare form
--- (`spell:123`). Kind-specific on purpose: an item link typed into a spell list is not a spell.
local function parseLink(link, text)
  if not link then return nil end
  return tonumber(text:match("|H" .. link .. ":(%d+)") or text:match("^" .. link .. ":(%d+)"))
end

--- Whether typed text is a name: not a number, and not a link of any type. Only a name can match
--- an id another candidate shares, so only a name waits on IdInput's lookup; a number or a link
--- names one id and never waits. Read off the text alone, so it holds for a host kind's resolver.
local function isNameText(text)
  return not (parseNumber(text) or text:find("|H%a+:%d") or text:match("^%a+:%d+$"))
end

local function byClientName(k, text)
  if type(k.byName) ~= "function" then return nil end
  return k.byName(text)
end

--- The host's candidate ids, or none: a raising candidates() is a host bug, and it costs the name
--- step rather than the click.
local function candidateIds(candidates)
  if type(candidates) ~= "function" then return {} end
  local ok, list = pcall(candidates)
  if not ok or type(list) ~= "table" then return {} end
  return list
end

--- A case-insensitive exact name match over the host's candidates. Two DISTINCT ids with the
--- name are ambiguous -- taking the first would hand the player one they may not have meant --
--- and one id listed twice is still one.
local function byCandidates(k, text, candidates)
  if type(k.info) ~= "function" then return nil, "notFound" end
  local want = text:lower()
  local hitId, hitName, hitIcon
  for _, id in ipairs(candidateIds(candidates)) do
    local name, icon = k.info(id)
    if type(name) == "string" and name:lower() == want and id ~= hitId then
      if hitId then return nil, "ambiguous" end
      hitId, hitName, hitIcon = id, name, icon
    end
  end
  if hitId then return hitId, hitName, hitIcon end
  return nil, "notFound"
end

--- The client's name hit, unless a candidate with a DIFFERENT id carries the same name. The client
--- answers one id for a name several share (an item's crafted-quality ranks), so the hit alone
--- would hand the player one rank they did not pick.
local function unlessShared(k, text, candidates, id, name, icon)
  local other, why = byCandidates(k, text, candidates)
  if why == "ambiguous" or (other ~= nil and other ~= id) then return nil, "ambiguous" end
  return id, name, icon
end

local RESOLVE_REASONS = { empty = true, notFound = true, ambiguous = true }

--- A host kind's own resolver, handed everything typed: a number, a link or a name. It answers
--- `id, name, icon`, or `nil, reason`; a raise or an unknown reason reads as not found.
local function customResolve(k, text, candidates)
  local ok, id, a, b = pcall(k.resolve, text, candidates)
  if not ok then return nil, "notFound" end
  if id ~= nil then return id, a, b end
  return nil, RESOLVE_REASONS[a] and a or "notFound"
end

--- Resolve typed text to an id (minor 16). Pure; published as O.ResolveId.
---
--- `kind` is "spell", "item" or "currency", or a host table `{ resolve = function(text,
--- candidates) -> id, name, icon | nil, reason; info = function(id) -> name, icon; noun; plural;
--- tooltip; loads }` whose resolver replaces every step below. `loads = true` with an `info` says
--- the kind's ids are items the client loads, so IdInput pre-warms and looks up its candidates as
--- it does the item kind's. The order, for a named kind:
---   1. a number (`21562`);
---   2. a link of the kind's own type (`|Hspell:21562:...`, or the bare `spell:21562`);
---   3. the client's name lookup (spells and items; currencies have none);
---   4. a case-insensitive exact name over the ids `candidates()` returns.
--- A name is "ambiguous" when two DISTINCT ids carry it: two candidates, or the client's hit at
--- step 3 and a different candidate (an item's crafted-quality ranks share one name).
--- Returns `id, name, icon` -- a number the client cannot name still resolves, with no name, which
--- is the degraded mode -- or `nil, reason` with reason "empty", "notFound" or "ambiguous".
local function resolveId(kind, text, candidates)
  if type(text) == "number" then text = tostring(text) end
  text = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
  if text == "" then return nil, "empty" end
  local k = idKind(kind)
  if type(k.resolve) == "function" then return customResolve(k, text, candidates) end

  local id = parseNumber(text) or parseLink(k.link, text)
  if id then
    if type(k.info) ~= "function" then return id end
    return id, k.info(id)
  end
  local found, name, icon = byClientName(k, text)
  if found then return unlessShared(k, text, candidates, found, name, icon) end
  return byCandidates(k, text, candidates)
end

-- The most unnamed candidates one lookup, or one build's pre-warm, asks the client for. A host's
-- candidate list can be a whole bag or an expansion's consumables; asking for thousands of items
-- at once floods the client's item-data queue for one typed name. Past the cap, the widget's next
-- window (a lookup) or next build (a pre-warm) moves on to the later candidates.
local ID_LOOKUP_CAP = 200

--- Whether this client can both load an item and name one: without either, an unnamed item stays
--- unnamed, and there is nothing to wait for.
local function itemLoadable()
  return C_Item and C_Item.GetItemNameByID and C_Item.RequestLoadItemDataByID and true or false
end

--- Whether the kind cannot name `id` yet. A raising lookup reads as named, so it is not asked for.
local function unnamedId(k, id)
  local ok, name = pcall(k.info, id)
  return ok and (type(name) ~= "string" or name == "")
end

--- The unnamed candidates, as O.UnnamedCandidates answers them, past every id the set `skip` holds.
--- Each id it examines goes into the set `mark` when one is given, so a caller passing one table
--- as both examines each id once, and a later call moves on to the ids after the cap.
local function unnamedIds(kind, candidates, skip, mark)
  local k, out, seen = idKind(kind), {}, {}
  if not (k.loads and type(k.info) == "function" and itemLoadable()) then return out end
  skip = skip or {}
  for _, id in ipairs(candidateIds(candidates)) do
    if type(id) == "number" and not seen[id] and not skip[id] then
      seen[id] = true
      if mark then mark[id] = true end
      if unnamedId(k, id) then out[#out + 1] = id end
      if #out >= ID_LOOKUP_CAP then break end
    end
  end
  return out
end

--- The candidates of a kind the client loads (items) that it cannot name yet: numbers, each once,
--- in the host's order, at most ID_LOOKUP_CAP of them. Pure; published as O.UnnamedCandidates.
--- A host kind loads when it declares `loads = true` and an `info`. None for a spell, a currency,
--- any other host kind, a raising candidates(), or a client that cannot load an item.
local function unnamedCandidates(kind, candidates)
  return unnamedIds(kind, candidates)
end

-- ── suggestions while typing (minor 16, issue #31) ────────────────────────────────────────
--
-- What IdInput's dropdown lists as the player types. Pure, and at file scope for the reason id
-- resolution is. The client has no item-name or spell-name search, so every row is an id something
-- already knows: the host's candidates(), plus what the client enumerates cheaply for the kind --
-- the items in the player's bags, the spells in the spellbook. A currency, or a host's own kind,
-- has the candidates alone.

-- At most this many rows under the box; a longer list ends in a "+N more" line.
local SUGGEST_ROWS = 10
-- A name suggests nothing under two typed characters; digits match ids from the first one.
local SUGGEST_MIN_NAME = 2
-- The most ids one render's index holds, the host's candidates first. Each is named once, on the
-- render's first keystroke; every later keystroke scans those cached names with no client call, and
-- re-reads at most ID_LOOKUP_CAP of the ids the client could not name yet.
local SUGGEST_INDEX_CAP = 2000
-- The pause after the last keystroke before the list is worked out again, in seconds.
local SUGGEST_DEBOUNCE = 0.1
-- The client's own small icon for a crafted or reagent quality tier, inline.
local QUALITY_ATLAS = "|A:Professions-Icon-Quality-Tier%d-Small:14:14|a"

--- Every item id in the backpack and the equipped bags (the reagent bag too, where the client has
--- one), slot by slot.
local function scanBags(C, out)
  local last = tonumber(NUM_TOTAL_EQUIPPED_BAG_SLOTS) or tonumber(NUM_BAG_SLOTS) or 4
  for bag = 0, last do
    for slot = 1, tonumber(C.GetContainerNumSlots(bag)) or 0 do
      local id = C.GetContainerItemID(bag, slot)
      if type(id) == "number" then out[#out + 1] = id end
    end
  end
end

--- The item ids the player carries. None on a client without C_Container; a raise ends the scan
--- where it raised.
local function bagItemIds()
  local C, out = C_Container, {}
  if C and C.GetContainerNumSlots and C.GetContainerItemID then pcall(scanBags, C, out) end
  return out
end

--- One skill line's spells: its Spell and FutureSpell slots, never a flyout or a pet action.
local function scanSpellLine(B, line, bank, spellTypes, out)
  local info = B.GetSpellBookSkillLineInfo(line)
  if type(info) ~= "table" then return end
  local first = tonumber(info.itemIndexOffset) or 0
  for slot = first + 1, first + (tonumber(info.numSpellBookItems) or 0) do
    local item = B.GetSpellBookItemInfo(slot, bank)
    if type(item) == "table" and type(item.spellID) == "number" and spellTypes[item.itemType] then
      out[#out + 1] = item.spellID
    end
  end
end

--- The player's own spellbook bank, every skill line. Enum is read at call time, with the client's
--- values as the fallback.
local function scanSpellBook(B, out)
  local E = Enum
  local bank = E and E.SpellBookSpellBank and E.SpellBookSpellBank.Player or 0
  local types = E and E.SpellBookItemType or {}
  local spellTypes = { [types.Spell or 1] = true, [types.FutureSpell or 2] = true }
  for line = 1, tonumber(B.GetNumSpellBookSkillLines()) or 0 do
    scanSpellLine(B, line, bank, spellTypes, out)
  end
end

--- The spell ids in the player's spellbook. None on a client without C_SpellBook's enumeration.
local function spellBookIds()
  local B, out = C_SpellBook, {}
  if B and B.GetNumSpellBookSkillLines and B.GetSpellBookSkillLineInfo and B.GetSpellBookItemInfo then
    pcall(scanSpellBook, B, out)
  end
  return out
end

--- A quality tier from one of the client's two tier lookups, or nil. A raise reads as none.
local function qualityTier(fn, id)
  if type(fn) ~= "function" then return nil end
  local ok, tier = pcall(fn, id)
  if ok and type(tier) == "number" and tier > 0 then return tier end
end

--- An item's rank: its crafted-quality tier, else its reagent-quality tier, as the number a row
--- sorts by and the client's tier icon it shows. Nil for an item with neither, or a client without
--- C_TradeSkillUI.
local function itemRank(id)
  local T = C_TradeSkillUI
  if not T then return nil end
  local tier = qualityTier(T.GetItemCraftedQualityByItemInfo, id)
    or qualityTier(T.GetItemReagentQualityByItemInfo, id)
  if tier then return tier, QUALITY_ATLAS:format(tier) end
end

--- A spell's rank: the client's subtext ("Rank 2", "Racial"), shown as the client words it and
--- sorted by the number in it. Nil for a spell with none, or a client without GetSpellSubtext.
local function spellRank(id)
  local fn = C_Spell and C_Spell.GetSpellSubtext
  if type(fn) ~= "function" then return nil end
  local ok, text = pcall(fn, id)
  if not ok or type(text) ~= "string" or text == "" then return nil end
  return tonumber(text:match("%d+")) or 0, text
end

-- The named kinds' client source and rank, keyed by the kind table as NAME_COLOR is, so a host's
-- own kind -- whose ids need not be the client's -- has neither.
local SUGGEST_KIND = {
  [ID_KINDS.item]  = { sources = bagItemIds, rank = itemRank },
  [ID_KINDS.spell] = { sources = spellBookIds, rank = spellRank },
}

--- The ids one render's index covers: the host's candidates, then the kind's client source;
--- numbers only, each once, at most SUGGEST_INDEX_CAP.
local function suggestIds(k, candidates)
  local out, seen = {}, {}
  local function take(list)
    for _, id in ipairs(list) do
      if #out >= SUGGEST_INDEX_CAP then return end
      if type(id) == "number" and not seen[id] then
        seen[id] = true
        out[#out + 1] = id
      end
    end
  end
  take(candidateIds(candidates))
  if SUGGEST_KIND[k] then take(SUGGEST_KIND[k].sources()) end
  return out
end

--- One row's worth of `id`, or nil while the kind cannot name it. A raising lookup reads as
--- unnamed.
local function suggestEntry(k, id)
  local ok, name, icon = pcall(k.info, id)
  if not ok or type(name) ~= "string" or name == "" then return nil end
  local e = { id = id, name = name, lower = name:lower(), icon = icon }
  if SUGGEST_KIND[k] then e.rank, e.rankLabel = SUGGEST_KIND[k].rank(id) end
  return e
end

--- One render's index: the named entries, and the ids still unnamed. Empty for a kind with no
--- `info`, which has nothing to name a row with.
local function buildSuggestIndex(k, candidates)
  local index = { entries = {}, unnamed = {} }
  if type(k.info) ~= "function" then return index end
  for _, id in ipairs(suggestIds(k, candidates)) do
    local e = suggestEntry(k, id)
    if e then index.entries[#index.entries + 1] = e else index.unnamed[#index.unnamed + 1] = id end
  end
  return index
end

--- Read the index's unnamed ids again, the first ID_LOOKUP_CAP of them: IdInput's pre-warm or
--- lookup may have landed them since. The ones now named join the entries.
local function nameUnnamed(k, index)
  local still = {}
  for i, id in ipairs(index.unnamed) do
    local e = i <= ID_LOOKUP_CAP and suggestEntry(k, id)
    if e then index.entries[#index.entries + 1] = e else still[#still + 1] = id end
  end
  index.unnamed = still
end

--- How well the lower-case name `lower` matches the lower-case `text`: 1 the whole name, 2 its
--- start, 3 the start of a word inside it, 4 anywhere in it; nil for no match.
local function nameTier(lower, text)
  if lower == text then return 1 end
  local at = lower:find(text, 1, true)
  if not at then return nil end
  if at == 1 then return 2 end
  while at do
    if lower:sub(at - 1, at - 1):find("[^%w']") then return 3 end
    at = lower:find(text, at + 1, true)
  end
  return 4
end

--- The dropdown's order: by tier, then shorter names first, then by name, then by rank (none is
--- 0), then by id. One name's ranks tie on everything before rank, so they sit together.
local function suggestBefore(a, b)
  if a.tier ~= b.tier then return a.tier < b.tier end
  if #a.lower ~= #b.lower then return #a.lower < #b.lower end
  if a.lower ~= b.lower then return a.lower < b.lower end
  local ra, rb = a.rank or 0, b.rank or 0
  if ra ~= rb then return ra < rb end
  return a.id < b.id
end

--- The length of `text` in characters rather than bytes: a UTF-8 continuation byte is not one.
local function charCount(text)
  return #(text:gsub("[\128-\191]", ""))
end

--- The entries whose id starts with `digits`, ascending.
local function byIdPrefix(entries, digits)
  local out = {}
  for _, e in ipairs(entries) do
    if tostring(e.id):sub(1, #digits) == digits then out[#out + 1] = e end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

--- The entries the trimmed `text` suggests, in the dropdown's order: ids by prefix for digits,
--- names by tier otherwise, and nothing for a name under SUGGEST_MIN_NAME characters.
local function matchSuggestions(entries, text)
  if text:match("^%d+$") then return byIdPrefix(entries, text) end
  if charCount(text) < SUGGEST_MIN_NAME then return {} end
  local want, out = text:lower(), {}
  for _, e in ipairs(entries) do
    e.tier = nameTier(e.lower, want)
    if e.tier then out[#out + 1] = e end
  end
  table.sort(out, suggestBefore)
  return out
end

--- Attach the widget makers and the flow engine to one instance. Called at the end of lib:New, so
--- every host gets its own closures over its own descriptor.
function lib.__AttachWidgets(O, d)
  -- The SHELL's sink (`O.__print`), not a second one built from the same descriptor. What stood
  -- here was `d.print or function() end`, which discarded every diagnostic in this file for any
  -- host that passed no printer — that is, for every host relying on the library's own
  -- chat-frame fallback, which is the fallback that exists precisely so these lines stay visible.
  -- The `or` arms survive for composition order alone: this is called from the end of lib:New, so
  -- `O.__print` is always there, and a caller that attached the maker set to some other table
  -- should fall silent rather than raise.
  local print = O.__print or d.print or function() end

  -- A ROW WITH NO PATH IS READ AND WRITTEN THROUGH ITS OWN get / set (minor 15). That is the flow
  -- engine's half of OptionsCompose.lua's record-backed arm: a composed block bound to a registry
  -- record rather than to settings carries `get()` and `set(value)` closures and no `path`. The
  -- gate is `path == nil`, not "has a get": a row WITH a path goes through the descriptor exactly as
  -- it always has, whatever other fields a host's schema happens to give it, so no path-keyed row
  -- anywhere in the collection can change behavior because of this.
  local function read(row)
    if row.path == nil and type(row.get) == "function" then return row.get() end
    return d.get(row.path)
  end
  -- Another key read on a row's behalf -- `disabledIf`. A path-less row resolves it through its own
  -- `get(key)`, which reads that field of the same record; a path row reads the settings path.
  local function readKey(row, key)
    if row.path == nil and type(row.get) == "function" then return row.get(key) end
    return d.get(key)
  end
  local function write(row, value)
    if row.path == nil and type(row.set) == "function" then return row.set(value) end
    return d.set(row.path, value)
  end

  -- Is `row` drawn disabled? `pageDisabled` is RenderRows' `opts.disabled`, snapshotted by the
  -- maker at BUILD time and never re-read from the ctx: the flag is cleared when that render
  -- returns, so a refresher reading it live would lift a disabled page's dimming on the first
  -- write anywhere, and a later render's flag could reach an earlier page's widgets.
  --
  -- `disabledIf` is a settings path (read through readKey, so a composed row reads its record) or,
  -- from minor 16, a predicate `function(row) -> bool`. A predicate that raises reads as enabled:
  -- the refresher is pcall'd by the sweep anyway, and a raise at build would cost the whole row
  -- for the sake of its dimming.
  local function isDisabled(row, pageDisabled)
    if pageDisabled then return true end
    local cond = row.disabledIf
    if type(cond) == "function" then
      local ok, v = pcall(cond, row)
      return (ok and v) and true or false
    end
    return readKey(row, cond) and true or false
  end

  local function noop() end

  --- Apply `row`'s disabled state to `widget` now, and hand back the function its refresher calls
  --- to re-apply it (minor 16; the color picker's private copy of this was the only one before).
  ---
  --- A row with no `disabledIf`, drawn outside a disabled render, is NEVER touched: it gets a no-op.
  --- Calling SetDisabled(false) on it would re-enable, on the next write anywhere, a widget the
  --- host disabled itself -- five hosts call SetDisabled on their own widgets.
  local function bindDisabled(ctx, row, widget)
    local pageDisabled = ctx.__renderDisabled and true or false
    if row.disabledIf == nil and not pageDisabled then return noop end
    if type(widget.SetDisabled) ~= "function" then return noop end
    local function apply() widget:SetDisabled(isDisabled(row, pageDisabled)) end
    apply()
    return apply
  end

  -- Write a row's value through the host's single write seam, then re-sync every widget on every
  -- panel. That is what makes paired controls just work: a "Use Class Color" toggle flips and its
  -- matching swatch grays out on the same frame. AceGUI's SetValue does not fire OnValueChanged,
  -- so this cannot recurse.
  --
  -- SCALARS, not the structural tier. Writing a value does not change which rows exist, and a
  -- rebuild on every checkbox click would tear down and recreate every widget on the page — which
  -- is exactly what the two-tier split exists to avoid.
  local function set(row, value)
    write(row, value)
    O.RefreshScalars()
  end

  -- Color storage is the HOST's shape, not the library's. AbsorbTracker stores {r=,g=,b=,a=};
  -- KickCD stores arrays. Picking a winner would force one of them to translate at every read site
  -- in the addon, so the codec is a descriptor option with the named-key form as the default.
  local function decodeColor(c)
    if type(d.colorDecode) == "function" then return d.colorDecode(c) end
    if type(c) ~= "table" then c = {} end
    return c.r or 1, c.g or 1, c.b or 1, c.a or 1
  end
  local function encodeColor(r, g, b, a)
    if type(d.colorEncode) == "function" then return d.colorEncode(r, g, b, a) end
    return { r = r, g = g, b = b, a = a or 1 }
  end

  -- ── tooltips and spacers ─────────────────────────────────────────────────────────────────

  --- Works on AceGUI widgets (via SetCallback) and on plain Blizzard frames (via HookScript),
  --- anchoring on widget.frame when the target is an AceGUI widget.
  function O.AttachTooltip(widget, label, tooltip)
    if not widget then return end
    local anchor = widget.frame or widget
    if not anchor then return end

    local function show()
      if not GameTooltip then return end
      GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
      if label and label ~= "" then
        GameTooltip:SetText(label, 1, 1, 1)
      end
      if tooltip and tooltip ~= "" then
        GameTooltip:AddLine(tooltip, nil, nil, nil, true)
      end
      GameTooltip:Show()
    end
    local function hide() if GameTooltip then GameTooltip:Hide() end end

    if widget.SetCallback then
      widget:SetCallback("OnEnter", show)
      widget:SetCallback("OnLeave", hide)
    elseif widget.HookScript then
      widget:HookScript("OnEnter", show)
      widget:HookScript("OnLeave", hide)
    end
  end

  --- An invisible full-width row. Used between sections, between widget rows, and between blocks
  --- on a host's landing page.
  function O.AddSpacer(scroll, height)
    local sp = O.AceGUI:Create("SimpleGroup")
    sp:SetLayout(nil)
    sp:SetFullWidth(true)
    sp:SetHeight(height)
    scroll:AddChild(sp)
    return sp
  end

  --- A section heading: an AceGUI Heading, which renders as a label flanked by side dividers, so
  --- one widget delivers both the separator and the title.
  function O.Section(ctx, label)
    local scroll = O.EnsureScroll(ctx)
    if not scroll then return end

    -- Only between sections, never above the first: a leading gap reads as a broken top margin.
    if ctx.lastGroup ~= nil then
      O.AddSpacer(scroll, L.SECTION_TOP_SPACER)
    end

    local h = O.AceGUI:Create("Heading")
    h:SetText(label)
    h:SetFullWidth(true)
    h:SetHeight(L.SECTION_HEADING_H)
    if h.label and h.label.SetFontObject and _G.GameFontNormalLarge then
      h.label:SetFontObject(_G.GameFontNormalLarge)
    end
    scroll:AddChild(h)

    O.AddSpacer(scroll, L.SECTION_BOTTOM_SPACER)
    return h
  end

  --- Pack tab widths into rows that fit `available`. Pure arithmetic and no widgets, so the
  --- wrap rule -- the thing that decides whether a page's strip is one row or two -- is
  --- checkable without a measured font.
  ---
  --- A tab wider than the whole strip is placed alone rather than dropped: the split only fires
  --- when the row already holds something, so every index in `widths` comes back in exactly one
  --- row. Losing one would lose a whole section of a page with nothing said about it.
  ---
  --- @param widths number[]    each tab's pixel width, in tab order
  --- @param available number   usable width of the strip
  --- @param gap number         horizontal gap between two tabs sharing a row
  --- @return number[][]        rows of 1-based indices into `widths`, in order
  function O.__layoutTabs(widths, available, gap)
    local rows, row, used = {}, {}, 0
    for i = 1, #widths do
      local need = (#row > 0) and (gap + widths[i]) or widths[i]
      if #row > 0 and used + need > available then
        rows[#rows + 1] = row
        row, used, need = {}, 0, widths[i]
      end
      row[#row + 1] = i
      used = used + need
    end
    if #row > 0 then rows[#rows + 1] = row end
    return rows
  end

  --- Where every tab lands, as pure arithmetic over numbers.
  ---
  --- Pure for the same reason __layoutTabs is: the harness no-ops SetPoint and answers 0 from
  --- GetWidth, so a rows-to-pixels mapping computed inline is a mapping nothing can check --
  --- which is exactly how a strip once shipped drawn on top of its own banner, with every test
  --- passing.
  ---
  --- `top` is the band already spoken for above the strip (the banner's height, or 0).
  --- @return table  { { index, x, y, width } … }, in tab order
  --- @return number the number of rows the strip wrapped into
  function O.__tabPlacement(widths, available, gap, top, rowPitch)
    local rows = O.__layoutTabs(widths, available, gap)
    local out = {}
    for r, indices in ipairs(rows) do
      local x = 0
      local y = -(top + (r - 1) * rowPitch)
      for _, i in ipairs(indices) do
        out[#out + 1] = { index = i, x = x, y = y, width = widths[i] }
        x = x + widths[i] + gap
      end
    end
    return out, #rows
  end

  --- The banner's own measured (or floor) height, widened by the small gap, the hairline rule
  --- and the second gap that separate it from the tab strip (options-ui-§14). Pure, and a
  --- sibling of __tabPlacement rather than arithmetic folded into PageBanner, so the widening of
  --- the band is checkable without a measured font or a live texture.
  ---
  --- Zero in, zero out: a page that draws no banner has nothing for a divider to separate, so
  --- placeTabs' `top` (which reads this straight off ctx.__bannerHeight) stays exactly 0 for a
  --- tabs-only page, same as before this seam existed.
  function O.__bannerBand(rawHeight)
    rawHeight = tonumber(rawHeight) or 0
    if rawHeight <= 0 then return 0 end
    return rawHeight + L.CHROME_DIVIDER_GAP_TOP + L.CHROME_DIVIDER_H + L.CHROME_DIVIDER_GAP_BOTTOM
  end

  --- The strip's own reserved band: the total height to hand SetChromeHeight, banner included.
  --- A sibling of __tabPlacement for the same reason __bannerBand is -- the arithmetic that
  --- decides whether the page's first row of settings lands under the strip or on top of it has
  --- to be checkable without a live frame.
  ---
  --- It is also where the content panel's TOP EDGE lands, because the panel anchors to the
  --- chrome's bottom and this number IS the chrome's height. The strip used to reserve one extra
  --- pixel here for a hairline it drew itself; the panel replaced the hairline, and the pixel
  --- went with it -- a panel drawn BELOW the band must not also be reserved INSIDE it.
  --- @return number  the band height to reserve, banner included
  function O.__tabBand(top, rowCount, tabH, rowPitch)
    rowCount = math.max(tonumber(rowCount) or 1, 1)
    return top + ((rowCount - 1) * rowPitch) + tabH
  end

  --- Hide, unparent and forget every widget in one of a page's chrome ledgers.
  local function releaseLedger(ctx, key)
    for _, f in ipairs(ctx[key] or {}) do
      f:Hide()
      f:SetParent(nil)
    end
    ctx[key] = {}
  end

  --- Give the strip's furniture back: every tab button and the content panel returned to the pool
  --- they came from, and the ledger that names them emptied.
  ---
  --- NOT releaseLedger, and the difference is the whole of minor 14. releaseLedger hides and
  --- UNPARENTS, which is correct for a widget nothing will hand out again and wrong for one that
  --- will -- an unparented button coming back off a free list is a button drawn onto nothing. The
  --- pool hides and parks; the parent is the page's own chrome, which outlives every render.
  ---
  --- `__tabKids` survives as the strip's LEDGER even though it no longer owns the release: it is
  --- what a suite reads to ask what this render drew, in the order it drew it, and the buttons
  --- have to be discoverable somewhere that is not the pool's internals.
  local function releaseTabs(ctx)
    if ctx.__tabPool   then Pool.ReleaseAll(ctx.__tabPool)   end
    if ctx.__panelPool then Pool.ReleaseAll(ctx.__panelPool) end
    ctx.__tabKids = {}
  end

  --- Release everything a page parked in its chrome band -- the banner AND the strip.
  ---
  --- Two seams, one release, because the two have different LIFETIMES: a tab click redraws the
  --- strip alone and releases its own furniture, while only a full page render redraws the banner.
  --- Draining both here is what keeps the page-wide teardown total without making the strip's
  --- ledger a second copy of it -- when TabStrip appended to both, __chromeKids grew by one entry
  --- per tab click, forever, holding buttons already hidden and unparented.
  local function releaseChrome(ctx)
    releaseLedger(ctx, "__chromeKids")
    releaseTabs(ctx)
  end
  O.__releaseChrome = releaseChrome

  --- Release a secondary strip's buttons. NOT folded into releaseChrome, because a sub-strip is not
  --- chrome: it is drawn INSIDE the scroll, parented to a frame the host added as an AceGUI child.
  --- That is exactly why it needs its own seam -- ClearScroll's ReleaseChildren returns that parent
  --- to AceGUI's pool, and a button still parented to it is a widget outliving the render that drew
  --- it, the same failure this file documents for the landing logo. SubTabStrip drains its own
  --- ledger on entry, which covers REDRAWING a strip; this covers the case it cannot see -- a page
  --- moving to a tab that draws no secondary strip at all, so SubTabStrip never runs to drain it.
  local function releaseSubTabs(ctx)
    releaseLedger(ctx, "__subTabKids")
  end
  O.__releaseSubTabs = releaseSubTabs

  -- The measured pitch, and the seam that forgets it. Published because the invariant a suite has
  -- to pin is "the band and every row offset are the same for every value of the selection", and
  -- that is unassertable without the one number both are built from. The reset exists for the
  -- harness alone: a session cannot want it, because the atlas does not change size mid-session.
  O.__tabArtHeight      = tabArtHeight
  O.__resetTabArtHeight = resetTabArtHeight

  --- Measure a label, in pixels, or fall back to the floor width.
  ---
  --- Guarded twice over. A FontString may not be there at all (an inert widget in a headless
  --- harness), and a mock's catch-all metatable answers a capitalized call with the frame
  --- itself -- so a `GetStringWidth` that "worked" could still hand back a table, and the
  --- arithmetic below would raise inside a layout pass. Type-check the answer, not the method.
  local function labelWidth(fs)
    if not (fs and fs.GetStringWidth) then return L.TAB_MIN_W end
    local w = fs:GetStringWidth()
    if type(w) ~= "number" or w <= 0 then return L.TAB_MIN_W end
    return math.max(L.TAB_MIN_W, w + (L.TAB_PAD_X * 2))
  end

  --- The tab's tooltip, wired ONCE at construction and re-aimed on every dress.
  ---
  --- O.AttachTooltip is the seam every other widget in this file uses, and it is the wrong one
  --- here for one reason: a raw Button has no AceGUI SetCallback, so it takes that function's
  --- HookScript arm -- and HookScript ACCUMULATES. A pooled button re-dressed on every click
  --- would grow a fresh pair of handlers per click, which is the same unbounded growth in scripts
  --- that minor 14 removes in frames. One SetScript pair is re-settable by construction, and
  --- reading the strings off the button rather than closing over them is what lets a tab that no
  --- longer HAS a tooltip actually lose the one it was last dressed with.
  local function attachTabTooltip(b)
    if not b.SetScript then return end
    b:SetScript("OnEnter", function()
      if not (GameTooltip and b.__ka0sTabTip) then return end
      GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
      if b.__ka0sTabTipLabel and b.__ka0sTabTipLabel ~= "" then
        GameTooltip:SetText(b.__ka0sTabTipLabel, 1, 1, 1)
      end
      GameTooltip:AddLine(b.__ka0sTabTip, nil, nil, nil, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
      if GameTooltip then GameTooltip:Hide() end
    end)
  end

  --- A bare tab button: the frame, its art and its label, and nothing that depends on WHICH tab it
  --- is or whether that tab is selected. The pool's factory.
  ---
  --- Split from dressTab because a strip is redrawn on every click of it and WoW destroys no
  --- frame: everything a click can be made to REUSE has to be created somewhere a click does not
  --- reach. What is left below is genuinely per-tab, and re-applying it is cheap.
  ---
  --- `parent` is the frame the button hangs off: `ctx.chrome` for the pinned primary strip, the
  --- host's own frame for a secondary one drawn inside the scroll (options-ui-§13).
  ---
  --- @return table  the button frame
  local function newTabButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(L.TAB_H)
    -- One level above the parent, so a tab's art draws OVER the content panel's top edge rather
    -- than under it -- which is what lets the selected tab merge into the page below it.
    if b.GetFrameLevel and b.SetFrameLevel then
      local level = b:GetFrameLevel()
      if type(level) == "number" then b:SetFrameLevel(level + 1) end
    end
    b.__ka0sTabArt = newTabArt(b)
    attachTabTooltip(b)
    return b
  end

  --- Put one button into the state of one tab: label, art, selection, handler and tooltip.
  ---
  --- EVERY field is re-applied, including the ones this tab does not use, because the button may
  --- have been dressed as a different tab a moment ago. A dress that only ever ADDED would leave
  --- the previous tab's tooltip on a tab that has none and the previous tab's handler under a
  --- label that no longer matches it -- which is the failure mode a pool trades for a leak if the
  --- dress is written as though the object were new.
  ---
  --- OnClick is re-set rather than hooked, and that is the same point: the handler closes over
  --- THIS dress's `active` and `tab.key`, so a button carrying the previous dress's closure would
  --- fire the wrong tab's selection.
  ---
  --- The ACTIVE tab is the DISABLED one, which is how Blizzard's own tab groups mark selection
  --- and is why it needs no second piece of art to say so: a disabled button does not highlight
  --- on hover and does not fire, so clicking the tab you are already on cannot re-render the
  --- page you are already looking at.
  ---
  --- @return number  its measured width, in pixels
  local function dressTab(b, tab, active, onSelect)
    -- LABEL, MEASURE, THEN STATE. The width is taken under the unselected font and the pitch under
    -- the unselected atlas, so neither can move when the player clicks a different tab.
    setTabLabel(b, tab.label)
    local width = labelWidth(b.GetFontString and b:GetFontString())
    setTabFont(b, active)
    dressTabArt(b, active)

    b:SetEnabled(not active)
    b:SetScript("OnClick", function()
      -- Belt AND braces. A disabled Button does not fire OnClick in the client, so this guard
      -- is redundant there -- but the invariant is worth stating where it can be read, and it
      -- keeps the handler correct if anything ever re-enables the button without redrawing
      -- the strip. It is also the only thing a harness can assert against, since a mock's
      -- SetEnabled cannot suppress a directly-fired script.
      if active then return end
      if onSelect then pcall(onSelect, tab.key) end
    end)
    b.__ka0sTabTipLabel, b.__ka0sTabTip = tab.label, tab.tooltip

    return width
  end

  --- Pack `buttons` into their wrapped rows, draw the baseline under the last one, and reserve
  --- the band those rows plus the baseline need.
  ---
  --- The band is reserved AFTER the wrap is known, never before: a strip that reserved one row
  --- and then laid out two would put its second row on top of the page's first widget. `top`
  --- already carries the banner's own gap/rule/gap (options-ui-§14) -- ctx.__bannerHeight is
  --- O.__bannerBand's OUTPUT, not the raw dropdown height -- so this function never re-derives
  --- that arithmetic itself.
  --- CREATES NOTHING. Every widget it touches already exists, which is what makes it safe to run
  --- again on a later frame -- see repaceOnResize below.
  --- A strip's usable width: the chrome's for the primary one, the host's frame for a secondary
  --- one. Zero until the canvas has laid itself out, which is the whole subject of replaceOnResize
  --- below.
  local function frameWidth(frame)
    local w = frame and frame.GetWidth and frame:GetWidth()
    if type(w) ~= "number" or w <= 0 then return L.TAB_MIN_W end
    return w
  end

  local function placeTabs(ctx, buttons, widths, available)
    ctx.__tabPlacedAt = available

    local top = ctx.__bannerHeight or 0
    -- ONE NUMBER, MEASURED ONCE, from a state no click can change (options-ui-§13). It feeds both
    -- the row offsets and the band, and both are read again by SetChromeHeight to re-anchor the
    -- scroll and the content panel -- which is why a pitch that varied with the selection moved
    -- the whole page.
    local pitch = tabArtHeight()
    local placement, rowCount =
      O.__tabPlacement(widths, available, L.TAB_GAP, top, pitch)
    for _, p in ipairs(placement) do
      local b = buttons[p.index]
      b:SetWidth(p.width)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", ctx.chrome, "TOPLEFT", p.x, p.y)
      b:Show()
    end

    O.SetChromeHeight(ctx, O.__tabBand(top, rowCount, L.TAB_H, pitch))
  end

  --- Re-run the wrap the first time the chrome learns how wide it actually is.
  ---
  --- THE BUG THIS FIXES: `ctx.chrome` has zero width until the settings canvas has laid itself
  --- out, and the FIRST page a player opens is rendered before that happens. `placeTabs` read
  --- `0`, fell back to `TAB_MIN_W`, and every tab wrapped onto its own row -- a vertical stack of
  --- tabs that healed itself the moment you clicked any of them, because by the second render the
  --- width was real. `O.EnsureDefaultsButton` already carries a note about `ctx.body` having zero
  --- width at enable time; this is the same client behavior reaching a second piece of chrome.
  ---
  --- A width cannot be computed from config instead: it is the canvas's, and the canvas is
  --- Blizzard's. So the strip re-places itself when the width arrives, which is what
  --- `OnSizeChanged` is for.
  ---
  --- Two things keep this from looping. The handler ignores everything but a CHANGE in width, and
  --- `placeTabs` records the width it used -- so the height change that `SetChromeHeight` causes,
  --- which fires this same script, is a no-op. And the hook is installed once per panel, because
  --- `ctx` outlives every render while the buttons do not: the handler reads the CURRENT layout
  --- out of `ctx` rather than closing over one strip's buttons, which would otherwise pin a
  --- released set of buttons alive forever and re-place them after they were hidden.
  local function replaceOnResize(ctx)
    if ctx.__tabResizeHooked then return end
    if not (ctx.chrome and ctx.chrome.SetScript) then return end
    ctx.__tabResizeHooked = true
    ctx.chrome:SetScript("OnSizeChanged", function(_, width)
      if type(width) ~= "number" or width <= 0 then return end
      if ctx.__tabPlacedAt == width then return end
      local layout = ctx.__tabLayout
      if layout then placeTabs(ctx, layout.buttons, layout.widths, width) end
    end)
  end

  --- A pinned tab strip in the page's chrome band (options-ui-§13). One tab per section.
  ---
  --- `spec` = { tabs = { { key, label, tooltip } }, value, onSelect }. Returns the buttons in
  --- tab order, or nil having drawn nothing.
  function O.TabStrip(ctx, spec)
    if not (ctx and ctx.chrome and spec and type(spec.tabs) == "table" and #spec.tabs > 0) then
      return nil
    end
    if not O.AceGUI then return nil end

    -- Only the strip's own furniture, never the banner: the banner is drawn first and a blanket
    -- release here would take it with them.
    releaseTabs(ctx)
    ctx.__tabLayout = nil

    -- ONE POOL PER PAGE, held on the ctx rather than on this file, because ctx.chrome is the
    -- parent every button in it is created under and a pool shared between two panels would hand
    -- one page's chrome a button parented to another's. ctx outlives every render, which is the
    -- same property replaceOnResize below relies on.
    ctx.__tabPool = ctx.__tabPool or Pool.New()
    local factory = function() return newTabButton(ctx.chrome) end

    local buttons, widths = {}, {}
    for i, tab in ipairs(spec.tabs) do
      local b = Pool.Acquire(ctx.__tabPool, factory)
      buttons[i] = b
      widths[i]  = dressTab(b, tab, tab.key == spec.value, spec.onSelect)
      ctx.__tabKids[#ctx.__tabKids + 1] = b
    end

    -- The panel is built before the tabs are placed, because it anchors to the chrome's BOTTOM
    -- and SetChromeHeight is what moves that edge; built after, it would still land correctly,
    -- but the ledger order would no longer say which of the two owns the separator.
    drawContentPanel(ctx)

    ctx.__tabLayout = { buttons = buttons, widths = widths }
    placeTabs(ctx, buttons, widths, frameWidth(ctx.chrome))
    replaceOnResize(ctx)
    return buttons
  end

  --- The page banner (options-ui-§14): which instance this page is editing, and the picker for
  --- it, pinned above the strip and the scroll.
  ---
  --- It carries the PICKER rather than a label, and it is the ONLY picker: a page that already
  --- had one deletes it. Two controls over one piece of session state is a synchronisation
  --- problem the design invented and would then own forever -- here there is one value, read at
  --- render time, and the structural refresh the write already triggers repaints every panel.
  ---
  --- Draw it BEFORE the strip. It records its own share of the band in `ctx.__bannerHeight` --
  --- widened by O.__bannerBand to include the small gap, the hairline rule and the second gap
  --- that separate the banner from the strip (options-ui-§14) -- which TabStrip's placeTabs adds
  --- to the rows it reserves for itself; called the other way round, the strip's reservation
  --- would not know about it.
  ---
  --- `spec` = { label, list, order, value, onSelect, tooltip }. Returns the dropdown, or nil
  --- having drawn nothing.
  function O.PageBanner(ctx, spec)
    if not (ctx and ctx.chrome and spec) then return nil end
    local AceGUI = O.AceGUI
    if not AceGUI then return nil end

    releaseChrome(ctx)

    local dd = AceGUI:Create("Dropdown")
    dd:SetLabel(spec.label or "")
    dd:SetList(spec.list or {}, spec.order)
    dd:SetValue(spec.value)
    dd:SetCallback("OnValueChanged", function(_, _, key)
      -- pcall'd for the reason every host callback in this file is: a selection handler reaches
      -- into live addon state, and a raise inside AceGUI's own dispatch takes the click handling
      -- of every widget on the frame with it.
      if spec.onSelect then pcall(spec.onSelect, key) end
    end)
    if dd.frame then
      dd.frame:SetParent(ctx.chrome)
      dd.frame:ClearAllPoints()
      dd.frame:SetPoint("TOPLEFT",  ctx.chrome, "TOPLEFT",  0, 0)
      dd.frame:SetPoint("TOPRIGHT", ctx.chrome, "TOPRIGHT", 0, 0)
      dd.frame:Show()
      ctx.__chromeKids[#ctx.__chromeKids + 1] = dd.frame

      -- Measured, not forced: a Dropdown WITH a label is taller than the floor because AceGUI
      -- renders the label above the control, and forcing L.BANNER_H used to clip it. Type-check
      -- the answer rather than the method -- a mock's catch-all metatable can answer a
      -- capitalized call with the frame itself, the same trap labelWidth guards against above.
      --
      -- Reserved only here, with the frame that justifies it: a widget with no backing frame
      -- parented nothing and occupies no band, so it must not claim one either. This repo's own
      -- harness is exactly the case that produces a frameless AceGUI widget.
      local h = dd.frame.GetHeight and dd.frame:GetHeight()
      if type(h) ~= "number" or h < L.BANNER_H then h = L.BANNER_H end

      -- The hairline rule sits at the raw height, never the widened one -- it separates the
      -- banner from what comes after it, so it has to be measured off the banner's own bottom
      -- edge rather than off a band that already includes it.
      drawChromeDivider(ctx, h)

      local band = O.__bannerBand(h)
      ctx.__bannerHeight = band
      O.SetChromeHeight(ctx, band)
    end
    O.AttachTooltip(dd, spec.label, spec.tooltip)

    return dd
  end

  --- A host-drawn block pinned above the tab strip and the scroll, in the band the page banner
  --- occupies (options-ui-§14). The library owns the band arithmetic; the host owns everything
  --- inside the frame it is handed.
  ---
  --- This exists because controls that apply to EVERY tab must sit above the strip. A control that
  --- governs the whole page but is drawn under one tab reads as belonging to that tab, and it
  --- disappears the moment the player clicks a different one -- creating the thing the page edits,
  --- choosing which one is being edited, and the acts that apply to it whole (enable, unlock, copy,
  --- reset, delete) are all page-wide. O.PageBanner draws exactly one Dropdown and is documented as
  --- the page's ONLY picker, so what is generalized here is the BAND, not the banner.
  ---
  --- `spec` = { height = <number>, build = function(ctx, frame) end, divider = <boolean, default
  --- true> }. Returns the frame, or nil having drawn nothing.
  ---
  --- A page draws AT MOST ONE chrome block: this and O.PageBanner both release `__chromeKids` and
  --- both write ctx.__bannerHeight, so the second call wins rather than stacking a second band. A
  --- page that needs a picker AND other page-wide controls puts the picker inside this frame and
  --- does not call PageBanner.
  ---
  --- Draw it BEFORE the strip, for the reason PageBanner gives: the strip's reservation reads
  --- ctx.__bannerHeight, and called the other way round it would not know about it.
  function O.PageHeader(ctx, spec)
    if not (ctx and ctx.chrome and spec) then return nil end
    local height = tonumber(spec.height)
    if not (height and height > 0) then return nil end

    releaseChrome(ctx)

    local frame = CreateFrame("Frame", nil, ctx.chrome)
    frame:SetPoint("TOPLEFT",  ctx.chrome, "TOPLEFT",  0, 0)
    frame:SetPoint("TOPRIGHT", ctx.chrome, "TOPRIGHT", 0, 0)
    frame:SetHeight(height)
    frame:Show()
    ctx.__chromeKids[#ctx.__chromeKids + 1] = frame

    -- The hairline sits at the RAW height, never the widened band: it separates the block from
    -- what comes after it, so it is measured off the block's own bottom edge.
    if spec.divider ~= false then drawChromeDivider(ctx, height) end

    local band = O.__bannerBand(height)
    ctx.__bannerHeight = band
    O.SetChromeHeight(ctx, band)

    -- pcall'd and REPORTED, for the reason every host callback in this file is: the builder reaches
    -- into live addon state, and a raise inside the render pass would cost the strip and the whole
    -- page under it rather than the block.
    if type(spec.build) == "function" then
      local ok, err = pcall(spec.build, ctx, frame)
      if not ok then print(lib.STRINGS.HEADER_FAILED:format(tostring(err))) end
    end

    return frame
  end

  --- A SECONDARY tab strip, drawn inside the scroll as ordinary page content (options-ui-§13).
  ---
  --- The primary strip is pinned in the chrome band and does not scroll; a secondary strip belongs
  --- to the content it divides, so it scrolls with it. Pinning a second band would double the
  --- chrome and push the page down twice for a division that is not page-wide.
  ---
  --- `spec` = { tabs = { { key, label, tooltip } }, value, onSelect }. Returns the buttons in tab
  --- order and the total height the strip occupies, so the host can size the frame it handed in --
  --- or nil having drawn nothing. It draws NO content panel: the page already has one.
  ---
  --- THE STATE KEY IS THE HOST'S, not ctx.activeTab -- `spec.value` and `spec.onSelect` are the
  --- whole contract, and the library reads neither back. The convention this establishes for the
  --- collection is `ctx.activeSubTab` as a TABLE keyed by the primary tab's key, so switching
  --- category and back remembers the subject you were on and a stale pointer heals per category.
  --- Session state either way, and never persisted (options-ui-§13).
  function O.SubTabStrip(ctx, parent, spec)
    if not (ctx and parent and spec and type(spec.tabs) == "table" and #spec.tabs > 0) then
      return nil
    end
    if not O.AceGUI then return nil end

    -- Its own ledger, released on entry exactly as TabStrip releases __tabKids: a secondary strip
    -- is redrawn whenever its category is, and buttons left parented to the host's frame would
    -- stack -- with the older set on top, swallowing the clicks.
    releaseLedger(ctx, "__subTabKids")

    -- NOT POOLED, unlike the primary strip's, and the asymmetry is the parent. A secondary strip
    -- hangs off a frame the HOST added as an AceGUI child, which ClearScroll gives back to AceGUI's
    -- own pool -- so its buttons have to be unparented on release, and an unparented button is one
    -- a free list could only ever hand back drawn onto nothing. The two-tier render means a sub
    -- strip is rebuilt only when its category is, not on every click within it.
    local buttons, widths = {}, {}
    for i, tab in ipairs(spec.tabs) do
      local b = newTabButton(parent)
      buttons[i] = b
      widths[i]  = dressTab(b, tab, tab.key == spec.value, spec.onSelect)
      ctx.__subTabKids[#ctx.__subTabKids + 1] = b
    end

    -- The SAME selection-invariant pitch the primary strip packs by, and `top` is 0 because there
    -- is no banner above a strip that is already inside the page.
    local pitch = tabArtHeight()
    local placement, rowCount =
      O.__tabPlacement(widths, frameWidth(parent), L.TAB_GAP, 0, pitch)
    for _, place in ipairs(placement) do
      local b = buttons[place.index]
      b:SetWidth(place.width)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", parent, "TOPLEFT", place.x, place.y)
      b:Show()
    end

    return buttons, O.__tabBand(0, rowCount, L.TAB_H, pitch)
  end

  --- A full-width line of text: one AceGUI Label added to the page's scroll, left-justified.
  ---
  --- `opts` is optional: `opts.fontObject` is a _G font-object NAME ("GameFontHighlight"), applied
  --- only when both the FontString and the global exist; `opts.justify` defaults to "LEFT".
  --- Returns nil, having drawn nothing, when AceGUI or the scroll is absent.
  ---
  --- This owns the `if w.label and w.label.SetJustifyH` / SetFontObject guard pair ONCE. That pair
  --- was written out per text widget per host — 28 times across six repos — and every copy is a
  --- place for one of the two halves to be forgotten, which fails silently and only in game.
  function O.TextRow(ctx, text, opts)
    local scroll = O.EnsureScroll(ctx)
    if not scroll then return end

    opts = opts or {}
    local w = O.AceGUI:Create("Label")
    w:SetFullWidth(true)
    w:SetText(text)
    applyLabelFont(w, opts.fontObject)
    if w.label and w.label.SetJustifyH then
      w.label:SetJustifyH(opts.justify or "LEFT")
    end
    scroll:AddChild(w)
    return w
  end

  --- Render a whole landing-page body: logo, one-liner, then a heading and its rows per section.
  ---
  --- `spec`:
  ---   logo      string             texture path. Omitted = no logo block.
  ---   logoSize  number             defaults to LAYOUT.LANDING_LOGO.
  ---   notes     string|function()  the one-liner; a function is called at RENDER time.
  ---   sections  array of { heading = string, rows = function() -> array of string }
  ---
  --- The last host-side copy in a stack this major already owns end to end: EnsureScroll,
  --- ClearScroll, AddSpacer and Section are all here, the rows come from LibKa0s-Slash-1.0's one
  --- command-row formatter, and buildMain(ctx) is already the descriptor seam the page hangs off.
  --- Three hosts kept a private body over it and drifted, which is the same class of drift — one
  --- level up — that the shared row formatter exists to end.
  function O.BuildLandingPage(ctx, spec)
    -- The renderer owns the clear, not the registry: a landing page is re-rendered on every
    -- re-show, and stacking a second copy of the logo under the first is what happens without it.
    O.ClearScroll(ctx)
    local scroll = O.EnsureScroll(ctx)
    if not scroll then return end

    spec = spec or {}
    landingLogo(O, scroll, spec)
    landingNotes(O, ctx, scroll, spec)
    landingSections(O, ctx, spec)
  end

  --- Two side-by-side action buttons (not settings) sharing one Flow row, each inset to
  --- BUTTON_PAIR_REL so the right one clears the ScrollFrame's clip rectangle (options-ui-§8).
  --- Each spec is { text, tooltip, onClick }.
  function O.InlineButtonPair(ctx, leftSpec, rightSpec)
    local scroll = O.EnsureScroll(ctx)
    if not scroll then return end

    local row = O.AceGUI:Create("SimpleGroup")
    row:SetLayout("Flow")
    row:SetFullWidth(true)
    row:SetHeight(28)

    local function makeBtn(spec)
      if not spec then return end

      -- AT BUILD TIME, and once. OptionsCompose emits the master group's two resets whether or
      -- not the host spec carried onResetAll/onResetPosition, so a spec that forgot one hands
      -- the player a button that looks live and swallows the click below. Saying so on the
      -- click instead would only tell the one person who pressed it, and tell them again every
      -- press; said here it lands once, in the log of whoever opened the panel, which is the
      -- author. Report and render, exactly as EMPTY_DROPDOWN does further down: dropping the
      -- button would leave a half-empty pair that reads as an intended layout.
      if type(spec.onClick) ~= "function" then
        print(lib.STRINGS.DEAD_BUTTON:format(tostring(spec.text or "")))
      end

      local btn = O.AceGUI:Create("Button")
      btn:SetText(spec.text or "")
      btn:SetRelativeWidth(L.BUTTON_PAIR_REL)
      -- Inside a RenderRows call carrying `opts.disabled` (minor 16) -- an afterGroup hook on a
      -- page drawn disabled -- the buttons are part of that page and are disabled with it.
      if ctx.__renderDisabled then btn:SetDisabled(true) end
      btn:SetCallback("OnClick", function()
        if not spec.onClick then return end
        -- pcall'd and REPORTED. A host's button body reaches into live addon state, and a raise
        -- here would propagate into AceGUI's own dispatch and take the click handling of every
        -- widget on the frame down with it.
        local ok, err = pcall(spec.onClick)
        if not ok then
          print(lib.STRINGS.BUTTON_FAILED:format(tostring(err)))
        end
      end)
      O.AttachTooltip(btn, spec.text, spec.tooltip)
      row:AddChild(btn)
    end

    makeBtn(leftSpec)
    makeBtn(rightSpec)
    scroll:AddChild(row)
    O.AddSpacer(scroll, L.ROW_VSPACER)
    return row
  end

  -- ── the five makers ──────────────────────────────────────────────────────────────────────

  local function makeCheckbox(ctx, row, parent, relativeWidth)
    parent = parent or O.EnsureScroll(ctx)
    local cb = O.AceGUI:Create("CheckBox")
    cb:SetLabel(row.label or row.path)
    applyWidth(cb, relativeWidth)

    local function readValue() return read(row) and true or false end

    cb:SetValue(readValue())
    local applyDisabled = bindDisabled(ctx, row, cb)
    local function refresh()
      cb:SetValue(readValue())
      applyDisabled()
    end

    cb:SetCallback("OnValueChanged", function(_, _, value)
      set(row, value and true or false)
    end)

    O.AttachTooltip(cb, row.label, tooltipBody(row))
    parent:AddChild(cb)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return cb
  end

  local function makeSlider(ctx, row, parent, relativeWidth)
    parent = parent or O.EnsureScroll(ctx)
    local s = O.AceGUI:Create("Slider")
    s:SetLabel(row.label or row.path)
    s:SetSliderValues(row.min or 0, row.max or 1, row.step or 1)
    -- Read from the row rather than hardcoded: a 0-1 ratio row renders as a percentage, which is
    -- the whole reason the field exists in the schema.
    s:SetIsPercent(row.isPercent and true or false)
    applyWidth(s, relativeWidth)

    local applyDisabled = bindDisabled(ctx, row, s)
    local function refresh()
      local v = read(row)
      -- A corrupt SavedVariable would otherwise hand AceGUI a nil or a string and blow up the
      -- layout pass, taking the whole page with it.
      if type(v) ~= "number" then v = row.default or row.min or 0 end
      s:SetValue(v)
      applyDisabled()
    end

    local function commitSlider(value)
      -- Snapped relative to `min`, not to zero: a step that does not divide min evenly would
      -- otherwise commit values the slider can never reach by dragging.
      set(row, snapToStep(value, row.min or 0, row.step or 0))
    end

    s:SetCallback("OnMouseUp", function(_, _, value) commitSlider(value) end)

    -- Opt-in live commit, per descriptor or per row. A page whose number rows drive something the
    -- user can see while dragging — a bar's width, a button's scale — has no preview without it,
    -- and there was no hook to ask for one. The default stays release-only, so an unchanged host
    -- is untouched.
    --
    -- Throttled through the same re-armed single timer the color picker uses, rather than the
    -- per-frame write a host would write by hand. Live commits snap to the row's step exactly as
    -- the release commit does, or the release would silently correct what the drag stored.
    local liveCommit = row.commitOn or d.sliderCommit
    if liveCommit == "change" then
      local pendingValue, dragTimer
      s:SetCallback("OnValueChanged", function(_, _, value)
        if type(d.scheduleTimer) ~= "function" then return commitSlider(value) end
        pendingValue = value
        if dragTimer then return end
        dragTimer = d.scheduleTimer(function()
          dragTimer = nil
          local v = pendingValue
          pendingValue = nil
          if v ~= nil then commitSlider(v) end
        end, DRAG_THROTTLE)
      end)
    end

    O.AttachTooltip(s, row.label, tooltipBody(row))
    parent:AddChild(s)
    refresh()
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return s
  end

  local function makeDropdown(ctx, row, parent, relativeWidth)
    parent = parent or O.EnsureScroll(ctx)
    -- A row may ask for an in-tree widget (LSM30_* for a media swatch or font preview). Fall back
    -- to the stock Dropdown when it is not registered — AceGUI-3.0-SharedMediaWidgets is optional,
    -- and the option must still render (no swatch, but usable) rather than erroring on an unknown
    -- type. Both share enough interface that the rest of this function is unchanged either way.
    local widgetType = row.dialogControl or "Dropdown"
    if widgetType ~= "Dropdown" and not O.AceGUI:GetWidgetVersion(widgetType) then
      widgetType = "Dropdown"
    end
    local dd = O.AceGUI:Create(widgetType)
    dd:SetLabel(row.label or row.path)
    applyWidth(dd, relativeWidth)

    -- A `type = "string"` row with no `values` AND no `dialogControl` is a free-text field that
    -- forgot to say so: the dispatch below sends it here and the player gets a dropdown that opens
    -- on nothing. Opting in with `dialogControl = "EditBox"` stays the rule -- see makeEditBox for
    -- why free text is not inferred from a missing list -- and this line is what makes forgetting
    -- it visible instead of silent.
    --
    -- ONLY when `row.values` is nil. An LSM-backed closure that legitimately answers empty before
    -- the media library has registered anything must NOT warn; that deferred case is the whole
    -- reason the opt-in exists.
    if row.values == nil and #enumList(row) == 0 then
      print(lib.STRINGS.EMPTY_DROPDOWN:format(tostring(row.path or row.field)))
    end

    local function applyList()
      local items, order = {}, {}
      for i, item in ipairs(enumList(row)) do
        items[item.value] = item.text
        order[i] = item.value
      end
      dd:SetList(items, order)
    end
    applyList()
    dd:SetValue(read(row))

    local applyDisabled = bindDisabled(ctx, row, dd)
    local function refresh()
      applyList()                            -- media lists grow as other addons register into them
      dd:SetValue(read(row))
      applyDisabled()
    end

    dd:SetCallback("OnValueChanged", function(_, _, value) set(row, value) end)

    O.AttachTooltip(dd, row.label, tooltipBody(row))
    parent:AddChild(dd)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return dd
  end

  -- The fifth type. Ships in -1.0 because adding a widget TYPE later is additive, but retrofitting
  -- one into a dispatch table already frozen by the major is not. Opted into with
  -- `dialogControl = "EditBox"` rather than inferred from a missing `values` list: inference would
  -- silently turn a row whose values function returned empty into a free-text field.
  local function makeEditBox(ctx, row, parent, relativeWidth)
    parent = parent or O.EnsureScroll(ctx)
    local eb = O.AceGUI:Create("EditBox")
    eb:SetLabel(row.label or row.path)
    applyWidth(eb, relativeWidth)
    if row.maxLetters then eb:SetMaxLetters(row.maxLetters) end
    eb:SetText(read(row) or "")

    local applyDisabled = bindDisabled(ctx, row, eb)
    local function refresh()
      eb:SetText(read(row) or "")
      applyDisabled()
    end

    -- OnEnterPressed only, never OnTextChanged: committing per keystroke would fire the row's
    -- onChange on every letter typed.
    eb:SetCallback("OnEnterPressed", function(_, _, text) set(row, text) end)

    O.AttachTooltip(eb, row.label, tooltipBody(row))
    parent:AddChild(eb)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return eb
  end

  local function makeColorPicker(ctx, row, parent, relativeWidth)
    parent = parent or O.EnsureScroll(ctx)
    local cp = O.AceGUI:Create("ColorPicker")
    cp:SetLabel(row.label or row.path)
    -- Default TRUE. The old `row.hasAlpha and true or false` made a declared `false`
    -- indistinguishable from an absent field, so no host could express "no alpha" even
    -- deliberately — while the codec below models alpha as a first-class component of every
    -- color it stores (`a or 1` on write, `c.a or 1` on read). Suppressing the slider by default
    -- contradicted the codec: a stored alpha the user could never reach. A host that wants the
    -- old behavior now writes `hasAlpha = false`, which it can say for the first time.
    cp:SetHasAlpha(row.hasAlpha ~= false)
    applyWidth(cp, relativeWidth)

    local function readColor() return decodeColor(read(row)) end

    cp:SetColor(readColor())

    local applyDisabled = bindDisabled(ctx, row, cp)

    local function refresh()
      cp:SetColor(readColor())
      applyDisabled()
    end

    -- AceGUI's ColorPicker fires OnValueChanged during a drag (live preview) and OnValueConfirmed
    -- on confirm or cancel (with the original color). The drag is throttled so a sustained one
    -- does not repaint at 60 Hz; the confirm commits immediately, so a cancel snaps back to the
    -- pre-drag color without waiting on the throttle window.
    --
    -- Deliberately does NOT call RefreshAllPanels: a sustained drag would re-traverse every widget
    -- on every panel every 50 ms. This is the one maker that declines the refresh.
    local function commit(r, g, b, a)
      write(row, encodeColor(r, g, b, a))
    end

    -- A single re-armed timer over a reused args table, so a 60 Hz drag produces O(1) garbage
    -- rather than sixty closures and sixty tables a second. The timer is the host's (the
    -- descriptor's scheduleTimer), because embedding AceTimer here would be this library's second
    -- dependency-budget breach.
    local pendingArgs
    local timer
    local function throttledCommit(r, g, b, a)
      if type(d.scheduleTimer) ~= "function" then return commit(r, g, b, a) end
      pendingArgs = pendingArgs or {}
      pendingArgs[1], pendingArgs[2], pendingArgs[3], pendingArgs[4] = r, g, b, a
      if timer then return end
      timer = d.scheduleTimer(function()
        timer = nil
        local p = pendingArgs
        pendingArgs = nil
        if p then commit(p[1], p[2], p[3], p[4]) end
      end, COLOR_THROTTLE)
    end

    cp:SetCallback("OnValueChanged",   function(_, _, r, g, b, a) throttledCommit(r, g, b, a) end)
    cp:SetCallback("OnValueConfirmed", function(_, _, r, g, b, a) commit(r, g, b, a) end)

    O.AttachTooltip(cp, row.label, tooltipBody(row))
    parent:AddChild(cp)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return cp
  end

  --- Dispatch by row.type. Returns nil for a type it does not know, rather than erroring: a
  --- misspelled type in a host's schema must cost that one row, not the whole page.
  function O.RenderField(ctx, row, parent, relativeWidth)
    if row.type == "bool"   then return makeCheckbox(ctx, row, parent, relativeWidth)    end
    if row.type == "number" then
      -- A number carrying a `values` list is an ENUM, not a range, and Slash.lua has said so
      -- since -1.0: its parseNumber refuses a value outside the list rather than clamping, and
      -- its comment calls the shape "a NUMERIC dropdown" and warns that clamping "lands BETWEEN
      -- two entries, and the renderer then has no label for what is stored". That renderer did
      -- not exist — this line is it. Until now the two majors read one row as two different
      -- things, and a host with such a row got a CLI that validated an enum and a panel that drew
      -- a slider over it.
      --
      -- INFERRED from `values`, not opted into with a `dialogControl`, because Slash infers too
      -- and an opt-in would leave the two disagreeing for every row that declares `values` and
      -- nothing else. The enumList duplication comment above states the requirement outright: the
      -- two readers MUST agree. Safe in the failure direction — a values function that answers
      -- empty falls through to the slider, which is exactly the old behavior.
      if #enumList(row) > 0 then return makeDropdown(ctx, row, parent, relativeWidth) end
      return makeSlider(ctx, row, parent, relativeWidth)
    end
    if row.type == "string" then
      if row.dialogControl == "EditBox" then
        return makeEditBox(ctx, row, parent, relativeWidth)
      end
      return makeDropdown(ctx, row, parent, relativeWidth)
    end
    if row.type == "color"  then return makeColorPicker(ctx, row, parent, relativeWidth) end
  end

  --- A non-schema checkbox wired to caller-supplied get/set instead of a settings path. For
  --- runtime-only, never-persisted toggles (a debug console's show/hide) that must NOT become
  --- saved settings — so they cannot go through makeCheckbox, which reads and writes a stored
  --- path. Registers a refresher so RefreshAllPanels re-reads live state when the thing it mirrors
  --- is changed elsewhere. spec = { label, tooltip, get, set }.
  function O.SessionCheckbox(ctx, parent, relativeWidth, spec)
    parent = parent or O.EnsureScroll(ctx)
    local cb = O.AceGUI:Create("CheckBox")
    cb:SetLabel(spec.label)
    applyWidth(cb, relativeWidth)

    cb:SetValue(spec.get() and true or false)
    -- Part of a page drawn disabled when drawn from inside it (minor 16), like InlineButtonPair.
    if ctx.__renderDisabled then cb:SetDisabled(true) end
    local function refresh() cb:SetValue(spec.get() and true or false) end

    cb:SetCallback("OnValueChanged", function(_, _, value)
      spec.set(value and true or false)
    end)

    O.AttachTooltip(cb, spec.label, spec.tooltip)
    parent:AddChild(cb)
    ctx.refreshers[#ctx.refreshers + 1] = refresh
    return cb
  end

  -- ── the two-column flow engine ───────────────────────────────────────────────────────────
  --
  -- Widgets are paired into 50/50 Flow rows, each row wrapped in a full-width SimpleGroup so
  -- AceGUI's layout pass gives both children exactly half the panel width and breaks them onto the
  -- same line. Section headings span the full width, and every row is followed by a small vertical
  -- spacer.
  --
  --   solo        render this row alone in the left half of its own line. For visual pivots.
  --   wide        render this row alone at FULL width, spanning both columns. NOT what `solo`
  --               does -- solo renders alone in the LEFT HALF -- and named to match RenderGrid's
  --               field of the same meaning rather than redefining solo, which would silently
  --               widen every solo row in nine shipped addons.
  --   startsLine  flush the pending line BEFORE this row, so a declared pair -- a color swatch and
  --               its "use class color" companion (options-ui-§17), the first row of a composed
  --               group -- is guaranteed to land as [left][right] and can never be split across
  --               two lines by an odd number of widgets above it. Without it the parity of every
  --               pair is a property of how many rows happen to precede it, which is a thing every
  --               author was counting by hand.
  --   subgroup    a heading drawn INSIDE a group (options-ui-§7). `group` is what a tabbed page
  --               partitions its strip on; `subgroup` is what breaks one tab into named blocks
  --               when it mixes control types. Drawn even under `noHeadings`, which suppresses the
  --               GROUP heading only.
  --   skipRender  keep the row in the schema (so resets and the CLI still see it) but let the host
  --               draw it bespoke — a header checkbox, say.
  --   afterGroup  { [groupName] = fn(ctx) } fired once PER RENDER, after that group's last row is
  --               flushed, so inline action buttons always start on a fresh line. The table is
  --               read-only to the library: hoist it to a constant and re-render freely.
  --   pairWith    { [path] = maker(ctx, rowGroup) } attaches a non-schema widget as the RIGHT half
  --               of a named path's row. Once per render (and, like afterGroup, never mutated),
  --               and only when that path is currently the lone
  --               widget on its row — attaching to a row that already has two would make it
  --               three-wide and break the 50/50 split for the rest of the page.
  --   opts        { noHeadings = true } suppresses the automatic Section heading, for a page
  --               whose sections are drawn as tabs instead (options-ui-§13). Omitted by every
  --               untabbed caller, which is why it is a fifth argument rather than a field on
  --               the ctx: a page's tabbedness is a property of THIS render, and a ctx flag
  --               would leak it into the next one.
  --               { disabled = true } (minor 16) draws every widget of the call disabled -- the
  --               rows, and the buttons an afterGroup or pairWith hook draws -- for a page whose
  --               subject does not apply (a Bars page over an icons container). It rides on
  --               `ctx.__renderDisabled` for the call's duration only, for the reason just given.
  --   disabledIf  (a row field) a settings path, or from minor 16 a predicate function(row) ->
  --               bool, whose truth draws the row disabled. Honored by every maker (only the
  --               color picker read it before minor 16) and re-evaluated on every refresh.

  --- Render an EXPLICIT list of rows. Taking a list rather than a page key is what lets a host
  --- render a filtered subset (a mirrored unit's partition) through the same engine.
  --- Lay out arbitrary widgets two per row, in the order given.
  ---
  --- The sibling of RenderRows, and deliberately not the same function. RenderRows is
  --- SCHEMA-driven: it walks declared rows, emits a Section when `group` changes, and pairs them
  --- automatically. This one is CALLER-driven — the caller decides what goes in each cell and in
  --- what order, and a cell may be a schema row or a bespoke widget.
  ---
  --- That distinction is what a host needs for a list whose LENGTH is not known from the schema:
  --- one checkbox per macro, per unit, per spell. Every such list was previously a hand-rolled
  --- copy of this loop in the host, which is exactly the duplication this library exists to end.
  ---
  --- Each item is either a schema row, or `{ make = function(ctx, parent, relativeWidth) end }`
  --- for a bespoke widget. `wide = true` breaks the item onto its own full-width row.
  function O.RenderGrid(ctx, items)
    local scroll = O.EnsureScroll(ctx)
    if not scroll then return end
    local pendingRow, pendingCount = nil, 0

    local function flushRow()
      if pendingRow then
        scroll:AddChild(pendingRow)
        O.AddSpacer(scroll, L.ROW_VSPACER)
        pendingRow, pendingCount = nil, 0
      end
    end

    -- Guarded per item, for the same reason RenderRows guards per row: a bespoke `make` reaches
    -- into live addon state, and a raise inside AceGUI's layout pass would cost every item after
    -- it.
    local function renderInto(item, parent, relativeWidth)
      if type(item.make) == "function" then
        return renderRowGuarded(print, item.path, item.make, ctx, parent, relativeWidth)
      end
      return renderRowGuarded(print, item.path, O.RenderField, ctx, item, parent, relativeWidth)
    end

    for _, item in ipairs(items) do
      if item.wide then
        flushRow()
        local r = startRow(O)
        renderInto(item, r, nil)
        scroll:AddChild(r)
        O.AddSpacer(scroll, L.ROW_VSPACER)
      else
        if not pendingRow then pendingRow = startRow(O) end
        if renderInto(item, pendingRow, HALF) then
          pendingCount = pendingCount + 1
        end
        if pendingCount >= 2 then flushRow() end
      end
    end
    flushRow()
  end

  -- ── the choice grid (minor 16) ───────────────────────────────────────────────────────────
  --
  -- One radio cell per column, then the row's label across what is left of the line. The label
  -- gives back CHOICE_CLIP_INSET for the reason BUTTON_PAIR_REL sits under half: the widget that
  -- ends at the right edge is clipped by the ScrollFrame's clip rectangle (options-ui-§8), and a
  -- line summing to exactly 1 can wrap its last cell on a float rounding.
  local CHOICE_CELL_REL   = 0.12
  local CHOICE_CLIP_INSET = 0.02
  -- The label column's heading when the host names none. A literal, as lib.STRINGS' own are: the
  -- library carries no locale, and a host that has one passes `labelHeader`.
  local CHOICE_LABEL_HEADER = "Category"

  local function choiceLabelRel(columnCount)
    return math.max(1 - columnCount * CHOICE_CELL_REL - CHOICE_CLIP_INSET, CHOICE_CELL_REL)
  end

  --- The header line: each column's label over its cells, then the label column's heading.
  local function choiceHeader(scroll, columns, labelHeader)
    local line = startRow(O)
    for _, col in ipairs(columns) do
      local lbl = O.AceGUI:Create("Label")
      lbl:SetText(col.label or tostring(col.value))
      lbl:SetRelativeWidth(CHOICE_CELL_REL)
      line:AddChild(lbl)
    end
    local lbl = O.AceGUI:Create("Label")
    lbl:SetText(labelHeader or CHOICE_LABEL_HEADER)
    lbl:SetRelativeWidth(choiceLabelRel(#columns))
    line:AddChild(lbl)
    scroll:AddChild(line)
  end

  --- One radio cell: lit while the row holds this column's value, writing it on a click.
  ---
  --- AceGUI toggles a CheckBox on every click, a radio-typed one included, so a click on the lit
  --- cell arrives as `false`. That is not a choice -- a radio cannot be clicked off -- so it
  --- re-lights the cell and writes nothing, rather than sweeping every panel for a no-op write.
  --- SetType is guarded because a host's own AceGUI fake may not carry it; the radio's look is
  --- cosmetic, and the exclusive behavior is this function's, not the widget's.
  local function choiceCell(ctx, row, col, line)
    local cb = O.AceGUI:Create("CheckBox")
    if cb.SetType then cb:SetType("radio") end
    cb:SetLabel("")
    cb:SetRelativeWidth(CHOICE_CELL_REL)

    local function lit() return read(row) == col.value end
    cb:SetValue(lit())
    local applyDisabled = bindDisabled(ctx, row, cb)
    ctx.refreshers[#ctx.refreshers + 1] = function()
      cb:SetValue(lit())
      applyDisabled()
    end

    cb:SetCallback("OnValueChanged", function()
      if lit() then cb:SetValue(true) return end
      set(row, col.value)
    end)
    O.AttachTooltip(cb, row.label, col.label)
    line:AddChild(cb)
  end

  --- Fill one row's line: its cells, then its label carrying the row's tooltip. The label dims
  --- with the cells, so a disabled row reads as disabled across the whole line.
  local function choiceLine(ctx, row, columns, line)
    for _, col in ipairs(columns) do choiceCell(ctx, row, col, line) end
    local lbl = O.AceGUI:Create("InteractiveLabel")
    lbl:SetText(row.label or row.path)
    lbl:SetRelativeWidth(choiceLabelRel(#columns))
    local applyDisabled = bindDisabled(ctx, row, lbl)
    if applyDisabled ~= noop then ctx.refreshers[#ctx.refreshers + 1] = applyDisabled end
    O.AttachTooltip(lbl, row.label, tooltipBody(row))
    line:AddChild(lbl)
  end

  --- The grid's body, under the disable flag O.ChoiceGrid holds for it.
  local function drawChoiceGrid(ctx, scroll, spec)
    local columns = spec.columns or {}
    if spec.heading then
      O.Section(ctx, spec.heading)
      ctx.lastGroup = spec.heading
    end
    choiceHeader(scroll, columns, spec.labelHeader)

    -- Guarded per line, as RenderRows guards per row: a row whose `get` raises costs that line
    -- and is reported, and every line after it still draws. A half-built line is not added.
    local lines = {}
    for _, row in ipairs(spec.rows or {}) do
      local line = startRow(O)
      if renderRowGuarded(print, row.path or row.label, choiceLine, ctx, row, columns, line) then
        scroll:AddChild(line)
        lines[#lines + 1] = line
      end
    end
    O.AddSpacer(scroll, L.ROW_VSPACER)
    if scroll.DoLayout then scroll:DoLayout() end
    return lines
  end

  --- A matrix of radio cells over rows that share one value list (minor 16): a header line of
  --- column labels, then one line per row -- a radio per column, then the row's label with its
  --- tooltip. A category that is Default, Whitelist or Blacklist is the shape it exists for.
  ---
  --- spec = {
  ---   rows        = schema rows: `path` (or a path-less `get`/`set`), `label`, `tooltip`/`desc`,
  ---                 `disabledIf`. Read and written through the same seam as every maker, so a
  ---                 click runs RefreshScalars and every cell re-syncs. The rows should carry
  ---                 `skipRender` so the flow engine leaves them to the grid; the grid draws them
  ---                 regardless, and they stay in the schema for the CLI and the resets.
  ---   columns     = ordered { { value =, label = }, ... }. A stored value no column carries
  ---                 lights no cell: guessing a column would hide the stale value behind a choice.
  ---   heading     = optional section heading, drawn with O.Section.
  ---   labelHeader = optional heading for the label column ("Category" when absent).
  ---   disabled    = optional; draws every cell disabled, as RenderRows' `opts.disabled` does. A
  ---                 grid drawn inside a disabled render inherits that render's flag either way.
  --- }
  ---
  --- Returns the row lines (full-width Flow SimpleGroups) in row order; a row that failed to draw
  --- has no line. Nil, drawing nothing, with no AceGUI.
  function O.ChoiceGrid(ctx, spec)
    local scroll = O.EnsureScroll(ctx)
    if not scroll then return end
    spec = spec or {}
    local outer = ctx.__renderDisabled
    ctx.__renderDisabled = (spec.disabled or outer) and true or nil
    local ok, res = pcall(drawChoiceGrid, ctx, scroll, spec)
    ctx.__renderDisabled = outer
    if not ok then error(res, 0) end
    return res
  end

  -- ── the id input and the id list (minor 16) ─────────────────────────────────────────────
  --
  -- The edit box and the button beside it sum to 0.98, not 1, for the reason BUTTON_PAIR_REL sits
  -- under half: the widget that ends at the right edge is clipped by the ScrollFrame's clip
  -- rectangle (options-ui-§8). An entry line uses the same two widths, name then action.
  local ID_MAIN_REL   = 0.78
  local ID_ACTION_REL = 0.20
  local ID_ICON_SIZE  = 16
  -- The status line's failure color, and the gray an entry's id is drawn in after its name.
  local ID_WARN_R, ID_WARN_G, ID_WARN_B = 1, 0.5, 0
  local ID_GRAY = "|cff808080"

  O.ResolveId = resolveId
  O.UnnamedCandidates = unnamedCandidates
  -- The default name hints, per named kind, for a host's tooltip. A copy per instance, so a host
  -- that rewrites one changes its own and no other host's; the widgets read `spec.strings.nameHint`
  -- and their own defaults, never this table.
  O.ID_NAME_HINT = {}
  for name, k in pairs(ID_KINDS) do O.ID_NAME_HINT[name] = KIND_TEXT[k].nameHint end

  -- A typed NAME, while some item candidates are still unnamed, is looked up whether or not it
  -- found an id: a hit may be one rank of a name an unnamed candidate also carries. Those items
  -- are asked for, a window of at most ID_LOOKUP_CAP at a time, and the text is tried once more
  -- when they land. Each window's wait is bounded as IdList's is -- a check 0.4 s after each ask,
  -- at most LOOKUP_ROUNDS asks -- and a lookup runs at most LOOKUP_WINDOWS windows. The status
  -- line reads the neutral `looking` words in the meantime.
  local LOOKUP_ROUNDS = 5
  local LOOKUP_WINDOWS = 5
  local ID_NEUTRAL_R, ID_NEUTRAL_G, ID_NEUTRAL_B = 1, 1, 1
  -- The candidate ids this instance's pre-warm has examined: each is read, and asked for if the
  -- client cannot name it, once a session, however many renders draw the input.
  local prewarmed = {}
  -- The ids a lookup asked for LOOKUP_ROUNDS times without their landing: retired or invalid.
  -- Every later window passes over them, so they cannot hold the cap for good.
  local deadIds = {}

  -- Uncached items. `itemLoads[id]` counts the asks this instance has made for an id, capped at
  -- ITEM_LOAD_TRIES: an id the client does not have never loads, and past five asks (two seconds
  -- at LoadItem's 0.4) the entry stays "Unknown item N" rather than asking for ever.
  -- `loadBatches[ctx]` is the ids asked for since that page's last check, `{ [id] = kind }`: one
  -- LoadItem callback per batch, however many ids join it, so twenty uncached ids cost one check
  -- and at most one redraw rather than twenty page renders in the same frame.
  local ITEM_LOAD_TRIES = 5
  local itemLoads = {}
  local loadBatches = setmetatable({}, { __mode = "k" })

  local function idText(spec, key, fields)
    local t = spec.strings and spec.strings[key] or kindText(spec.kind, key) or ID_TEXT[key]
    return fillText(t, fields or {})
  end

  --- Call a host callback, reporting a raise rather than letting it into AceGUI's dispatch.
  --- Answers whether it ran and returned.
  local function callHost(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, err = pcall(fn, ...)
    if not ok then print(lib.STRINGS.BUTTON_FAILED:format(tostring(err))) end
    return ok
  end

  --- Draw the list again after its shape changed: the host's own `ctx.rebuild` when it set one,
  --- else the library's STRUCTURAL sweep -- an add or a remove changes which lines exist.
  local function rebuildIdList(ctx)
    if type(ctx.rebuild) == "function" then return callHost(ctx.rebuild) end
    O.RefreshAllPanels()
  end

  --- Disable `widget` when it is drawn inside a disabled render, as InlineButtonPair does.
  local function disableIfRender(ctx, widget)
    if ctx.__renderDisabled and widget.SetDisabled then widget:SetDisabled(true) end
  end

  --- Run `fn` with `ctx.__renderDisabled` held for the call, as O.ChoiceGrid does: set by
  --- `disabled` or inherited, restored on the way out, a raise included.
  local function underDisable(ctx, disabled, fn, ...)
    local outer = ctx.__renderDisabled
    ctx.__renderDisabled = (disabled or outer) and true or nil
    local ok, a, b, c, e = pcall(fn, ...)
    ctx.__renderDisabled = outer
    if not ok then error(a, 0) end
    return a, b, c, e
  end

  --- Write the status line, remembering what it says: AceGUI's Label has no getter, and a raising
  --- onAdd puts back what was there.
  local function showStatus(parts, text)
    parts.shown = text
    parts.status:SetText(text)
  end

  local function trimmed(text)
    return type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
  end

  -- The suggestion dropdown's answer to a refused shared name, defined with the dropdown below.
  local offerRanks

  --- Say why nothing was added, in orange; the text stays so the player can correct it. A name
  --- several ids share is refused with "pick one from the list", so the list is put up for it.
  local function reportFailure(spec, parts, reason, typed)
    local noun, plural = kindWords(idKind(spec.kind))
    showStatus(parts, idText(spec, reason, { noun = noun, plural = plural, text = typed,
                                             hint = idText(spec, "nameHint") }))
    if parts.status.SetColor then parts.status:SetColor(ID_WARN_R, ID_WARN_G, ID_WARN_B) end
    if reason == "ambiguous" then offerRanks(parts, typed) end
  end

  --- Hand a resolved id to the host. The box and the status line are cleared BEFORE onAdd, because
  --- a host whose onAdd redraws the page has released both into AceGUI's pool by the time it
  --- returns, and the pool may already have handed them to the new render. Nothing touches either
  --- widget after a clean onAdd. A raising one adds nothing, so the text goes back and the status
  --- line reads `restore`. Then `sub.afterAdd` -- IdList's rebuild.
  local function addResolved(ctx, spec, parts, id, sub, restore)
    showStatus(parts, "")
    parts.edit:SetText("")
    if callHost(spec.onAdd, id) then
      if sub.afterAdd then sub.afterAdd(ctx) end
      return
    end
    parts.edit:SetText(type(sub.text) == "string" and sub.text or sub.typed)
    showStatus(parts, restore)
  end

  --- Whether the kind names `id` yet. A raising lookup reads as not yet.
  local function entryNamed(k, id)
    if type(k.info) ~= "function" then return false end
    local ok, name = pcall(k.info, id)
    return ok and type(name) == "string" and name ~= ""
  end

  --- Ask the client for items: through LibKa0s-Item-1.0's LoadItem when it is loaded (the first id
  --- carries `cb`), else straight through C_Item, with C_Timer for `cb`. `cb`, when given, runs once,
  --- 0.4 s on, whether or not they arrived. Answers false, asking nothing, on a client that cannot
  --- ask -- or cannot call back, when a callback is wanted.
  local function requestItems(ids, cb)
    if not (C_Item and C_Item.RequestLoadItemDataByID) then return false end
    if cb and not (C_Timer and C_Timer.After) then return false end
    local Item = LibStub and LibStub("LibKa0s-Item-1.0", true)
    local load = Item and Item.LoadItem
    for i, id in ipairs(ids) do
      if load then load(id, i == 1 and cb or nil) else C_Item.RequestLoadItemDataByID(id) end
    end
    if cb and not load then C_Timer.After(0.4, cb) end
    return true
  end

  --- Ask, once a session per instance, for the item candidates the client cannot name yet, so a
  --- name among them resolves on the first try. At most ID_LOOKUP_CAP a build, each build moving on
  --- past the ids the last one examined, so a redraw reads no candidate twice; nothing waits.
  local function prewarm(spec)
    if type(spec.candidates) ~= "function" then return end
    local fresh = unnamedIds(spec.kind, spec.candidates, prewarmed, prewarmed)
    if #fresh > 0 then requestItems(fresh) end
  end

  --- The last try: the same text once more, now its candidates have had their chance to load. No
  --- second lookup -- it adds, or it says why.
  local function finishLookup(ctx, spec, parts, sub)
    local id, reason = resolveId(spec.kind, sub.typed, spec.candidates)
    if id == nil then return reportFailure(spec, parts, reason, sub.typed) end
    addResolved(ctx, spec, parts, id, sub, "")
  end

  --- Whether the box still holds what was submitted. A widget with no getter is taken at its word.
  local function stillTyped(parts, typed)
    if not parts.edit.GetText then return true end
    return trimmed(parts.edit:GetText()) == typed
  end

  --- The ids of `ids` the kind still cannot name.
  local function stillUnnamed(k, ids)
    local out = {}
    for _, id in ipairs(ids) do
      if not entryNamed(k, id) then out[#out + 1] = id end
    end
    return out
  end

  --- Ask for the lookup's next window: the unnamed candidates no earlier window gave up on, at most
  --- ID_LOOKUP_CAP. Answers false, asking nothing, when there are none or the client cannot ask.
  local function askWindow(spec, lookup)
    local ids = unnamedIds(spec.kind, spec.candidates, deadIds)
    if #ids == 0 then return false end
    lookup.ids, lookup.rounds, lookup.windows = ids, 0, lookup.windows + 1
    return requestItems(ids, lookup.check)
  end

  --- A lookup's check, 0.4 s after each ask. Nothing for a lookup a newer submit or a release has
  --- dropped; a box the player has typed over drops it and clears the looking line. Otherwise it
  --- waits while any id of the window is still unnamed and asks have not run out -- retrying as
  --- soon as ONE lands could add one rank of a name the next rank to land also carries. An id still
  --- unnamed when the asks run out is dead, and the next window moves past it. With no window left,
  --- the text is tried once more.
  local function checkLookup(ctx, spec, parts, lookup)
    if parts.lookup ~= lookup then return end
    if not stillTyped(parts, lookup.sub.typed) then
      parts.lookup = nil
      return showStatus(parts, "")
    end
    lookup.rounds = lookup.rounds + 1
    local waiting = stillUnnamed(idKind(spec.kind), lookup.ids)
    if #waiting > 0 and lookup.rounds < LOOKUP_ROUNDS then
      lookup.ids = waiting
      if requestItems(waiting, lookup.check) then return end
    end
    for _, id in ipairs(waiting) do deadIds[id] = true end
    if lookup.windows < LOOKUP_WINDOWS and askWindow(spec, lookup) then return end
    parts.lookup = nil
    finishLookup(ctx, spec, parts, lookup.sub)
  end

  --- Start a lookup for a typed name: answers false, starting none, when no candidate is unnamed
  --- (bar the dead) or the client cannot ask.
  local function startLookup(ctx, spec, parts, sub)
    local lookup = { windows = 0, sub = sub }
    lookup.check = function() checkLookup(ctx, spec, parts, lookup) end
    parts.lookup = lookup
    if not askWindow(spec, lookup) then
      parts.lookup = nil
      return false
    end
    local noun, plural = kindWords(idKind(spec.kind))
    showStatus(parts, idText(spec, "looking", { noun = noun, plural = plural, text = sub.typed }))
    if parts.status.SetColor then parts.status:SetColor(ID_NEUTRAL_R, ID_NEUTRAL_G, ID_NEUTRAL_B) end
    return true
  end

  --- Resolve what was typed and hand the id to the host. A NAME -- one that found an id or found
  --- nothing -- while some candidates are still unnamed is looked up first (startLookup): a hit may
  --- be one rank of a name an unnamed candidate shares. A number or a link never waits. Any other
  --- failure says why on the status line. A submit replaces any lookup still pending.
  local function submitId(ctx, spec, parts, text, afterAdd)
    parts.lookup = nil
    parts.offer = nil
    local sub = { text = text, typed = trimmed(text), afterAdd = afterAdd }
    local id, reason = resolveId(spec.kind, sub.typed, spec.candidates)
    local byName = (id ~= nil or reason == "notFound") and isNameText(sub.typed)
    if byName and startLookup(ctx, spec, parts, sub) then return end
    if id ~= nil then return addResolved(ctx, spec, parts, id, sub, parts.shown or "") end
    reportFailure(spec, parts, reason, sub.typed)
  end

  -- ── the suggestion dropdown (minor 16, issue #31) ────────────────────────────────────────
  --
  -- One dropdown per instance, built the first time it shows and shared by every IdInput the
  -- instance draws: only the box the player is typing in shows one. `suggest.owner` is that box's
  -- parts. The ten rows and the "+N more" line are built with the frame and reused for every
  -- list, so a redraw of the page builds no frame. It is parented to UIParent at FULLSCREEN_DIALOG
  -- strata and clamped to the screen, so the settings panel's scroll frame cannot clip it and it
  -- draws above the panel. Escape, focus leaving the box, the box hiding with its panel, and the
  -- box's release close it, and drop an update still waiting on the debounce. A shared name the
  -- box refuses puts its ranks up to pick from. Plain frames, nothing protected: none of it is
  -- refused in combat.
  local SUGGEST_ROW_H = 18
  local SUGGEST_PAD   = 6
  local SUGGEST_ICON  = 16
  local SUGGEST_MIN_W = 260
  local SUGGEST_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
  local SUGGEST_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  }
  local ARROW_STEP = { UP = -1, DOWN = 1 }
  local suggest = {}
  -- The frames already hooked, per script. AceGUI pools its widgets, so a box another page drew
  -- is hooked once, and every hook finds its box through `boxParts`.
  local hookedFrames = setmetatable({}, { __mode = "k" })
  -- The box each hooked frame was drawn for last: its input frame and its own frame both map to
  -- that box's parts, so a hook acts for the render the pooled frame belongs to now.
  local boxParts = setmetatable({}, { __mode = "k" })

  --- Close the dropdown if `parts` owns it, and drop any update still waiting on the debounce.
  local function closeSuggest(parts)
    parts.suggestSeq = (parts.suggestSeq or 0) + 1
    parts.sel = nil
    if suggest.owner ~= parts then return end
    suggest.owner = nil
    if suggest.frame then suggest.frame:Hide() end
  end

  --- Add a picked row's id the way a typed add goes: the box and the status line cleared, then
  --- onAdd, then IdList's rebuild. A pick names one id, so no lookup runs.
  local function pickSuggestion(parts, entry)
    closeSuggest(parts)
    parts.lookup = nil
    parts.offer = nil
    local text = parts.edit.GetText and parts.edit:GetText() or ""
    addResolved(parts.ctx, parts.spec, parts, entry.id,
      { text = text, typed = trimmed(text), afterAdd = parts.afterAdd }, parts.shown or "")
  end

  --- The keyboard highlight: the row's own highlight texture, locked on. `selected` records it.
  local function markRow(row, on)
    row.selected = on
    if on then row:LockHighlight() else row:UnlockHighlight() end
  end

  --- A line at row position `i`: an icon, then the label, left-aligned on one line.
  local function newSuggestLine(frame, i, font)
    local line = CreateFrame("Button", nil, frame)
    line:SetHeight(SUGGEST_ROW_H)
    local y = -SUGGEST_PAD - (i - 1) * SUGGEST_ROW_H
    line:SetPoint("TOPLEFT", frame, "TOPLEFT", SUGGEST_PAD, y)
    line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SUGGEST_PAD, y)
    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetSize(SUGGEST_ICON, SUGGEST_ICON)
    line.icon:SetPoint("LEFT", line, "LEFT", 2, 0)
    line.label = line:CreateFontString(nil, "OVERLAY", font)
    line.label:SetPoint("LEFT", line, "LEFT", SUGGEST_ICON + 6, 0)
    line.label:SetPoint("RIGHT", line, "RIGHT", -2, 0)
    line.label:SetJustifyH("LEFT")
    line.label:SetWordWrap(false)
    line:Hide()
    return line
  end

  --- A row the player can click: it adds its entry for whichever box owns the dropdown then.
  local function newSuggestRow(frame, i)
    local row = newSuggestLine(frame, i, "GameFontHighlightSmall")
    row:SetHighlightTexture(SUGGEST_HIGHLIGHT, "ADD")
    row:SetScript("OnClick", function(self)
      local owner = suggest.owner
      if owner and self.entry then pickSuggestion(owner, self.entry) end
    end)
    return row
  end

  --- The dropdown, built once per instance.
  local function suggestFrame()
    if suggest.frame then return suggest.frame end
    local f = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    if f.SetBackdrop then
      f:SetBackdrop(SUGGEST_BACKDROP)
      f:SetBackdropColor(0, 0, 0, 0.92)
    end
    f.rows = {}
    for i = 1, SUGGEST_ROWS do f.rows[i] = newSuggestRow(f, i) end
    -- The "+N more" line: a label, not a choice.
    f.more = newSuggestLine(f, SUGGEST_ROWS + 1, "GameFontDisableSmall")
    f.more:EnableMouse(false)
    f:Hide()
    suggest.frame = f
    return f
  end

  --- A row's text: the name (an item's in its quality color), its rank where it has one, and its
  --- id in gray -- which is all that tells two unranked ids of one name apart.
  local function suggestLabel(k, e)
    local name = e.name
    local color = NAME_COLOR[k] and NAME_COLOR[k](e.id)
    if color then name = color .. name .. "|r" end
    if e.rankLabel then name = name .. " " .. e.rankLabel end
    return name .. " " .. ID_GRAY .. "(" .. tostring(e.id) .. ")|r"
  end

  --- Show `entry` on `row`, or hide the row for none. `entry` and `labelText` record what it shows.
  local function fillRow(k, row, entry)
    row.entry = entry
    markRow(row, false)
    if not entry then
      row.labelText = nil
      return row:Hide()
    end
    row.labelText = suggestLabel(k, entry)
    row.label:SetText(row.labelText)
    row.icon:SetTexture(entry.icon)
    row:Show()
  end

  local function fillMore(spec, more, left)
    if left <= 0 then
      more.labelText = nil
      return more:Hide()
    end
    more.labelText = idText(spec, "more", { count = left })
    more.label:SetText(more.labelText)
    more:Show()
  end

  --- The box's width in the dropdown's own units: a panel scaled apart from UIParent draws the box
  --- at another scale than the dropdown. A scale the client does not answer is taken as the same.
  local function boxWidth(f, anchor)
    local width = anchor and anchor.GetWidth and anchor:GetWidth()
    if type(width) ~= "number" then return 0 end
    local from = anchor.GetEffectiveScale and anchor:GetEffectiveScale()
    local to = f.GetEffectiveScale and f:GetEffectiveScale()
    if type(from) == "number" and type(to) == "number" and from > 0 and to > 0 then
      return width * from / to
    end
    return width
  end

  --- Size the dropdown to `lines` lines and hang it under the box's input.
  local function placeSuggest(f, edit, lines)
    local anchor = edit.editbox or edit.frame
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    f:SetWidth(math.max(boxWidth(f, anchor), SUGGEST_MIN_W))
    f:SetHeight(lines * SUGGEST_ROW_H + 2 * SUGGEST_PAD)
  end

  local function showSuggestions(parts, matches)
    local f = suggestFrame()
    suggest.owner, parts.matches, parts.sel = parts, matches, nil
    local k = idKind(parts.spec.kind)
    for i, row in ipairs(f.rows) do fillRow(k, row, matches[i]) end
    local rows = math.min(#matches, SUGGEST_ROWS)
    fillMore(parts.spec, f.more, #matches - rows)
    placeSuggest(f, parts.edit, rows + (#matches > rows and 1 or 0))
    f:Show()
  end

  --- Up and Down move the highlight over the rows, wrapping; from none, Down takes the first row
  --- and Up the last. The "+N more" line is never highlighted.
  local function moveSelection(parts, step)
    local n = math.min(#(parts.matches or {}), SUGGEST_ROWS)
    if n == 0 then return end
    local sel = parts.sel
    if sel then sel = (sel - 1 + step) % n + 1 elseif step > 0 then sel = 1 else sel = n end
    parts.sel = sel
    for i, row in ipairs(suggest.frame.rows) do markRow(row, i == sel) end
  end

  --- The parts owning the dropdown, when `frame` is its box's input or its box's frame.
  local function ownerOf(frame)
    local o = boxParts[frame]
    if o and suggest.owner == o then return o end
  end

  --- Whether the pointer is over the dropdown: focus lost to a click on a row keeps it open for
  --- the click. Only a real `true` counts.
  local function pointerOnSuggest()
    local f = suggest.frame
    return f ~= nil and f.IsMouseOver ~= nil and f:IsMouseOver() == true
  end

  --- Whether `parts` may show the dropdown: not released, not hidden since its panel last showed,
  --- and holding the keys. Shown again is read off the frame, because AceGUI's EditBox sets its own
  --- frame's OnShow script and would drop a hook there. Only a real `false` from HasFocus counts as
  --- the keys being elsewhere.
  local function canSuggest(parts)
    if parts.released then return false end
    if parts.hidden then
      local f = parts.edit.frame
      if not (f and f.IsVisible and f:IsVisible() == true) then return false end
      parts.hidden = nil
    end
    local input = parts.edit.editbox
    return not (input and input.HasFocus and input:HasFocus() == false)
  end

  --- Work the list out for `text` and show it, or close the dropdown when nothing matches. The
  --- render's index is built on its first keystroke; each later one re-reads the unnamed items.
  local function updateSuggest(parts, text)
    local k = idKind(parts.spec.kind)
    if not parts.index then
      parts.index = buildSuggestIndex(k, parts.spec.candidates)
    elseif k.loads then
      nameUnnamed(k, parts.index)
    end
    local matches = matchSuggestions(parts.index.entries, trimmed(text))
    if #matches > 0 then return showSuggestions(parts, matches) end
    -- Whichever box showed it, the player is typing here now.
    if suggest.owner then closeSuggest(suggest.owner) end
  end

  --- A shared name refused (reportFailure, from a submit or a lookup's last try): its ranks are
  --- listed for the player to pick from, and listed again when focus comes back to a box still
  --- holding the name. Refused by Add, the box gets the keys back first, so Up, Down and Enter
  --- reach the list. Enter with nothing highlighted refuses again, so no rank is added unpicked.
  offerRanks = function(parts, typed)
    parts.offer = typed
    if parts.refocus and parts.edit.SetFocus then parts.edit:SetFocus() end
    if canSuggest(parts) then updateSuggest(parts, typed) end
  end

  --- Focus back in a box: a refused shared name it still holds lists its ranks again.
  local function reoffer(parts)
    if not parts.offer or suggest.owner == parts then return end
    if not stillTyped(parts, parts.offer) then
      parts.offer = nil
      return
    end
    if canSuggest(parts) then updateSuggest(parts, parts.offer) end
  end

  --- Focus lost to a click on the dropdown. A row's click picks and closes it; a click anywhere
  --- else on it (the backdrop, the "+N more" line) would leave it open under a box without the
  --- keys, where Escape cannot reach it. So the box takes them back on the next frame, unless a
  --- pick has closed the dropdown by then.
  local function refocusLater(parts)
    local function refocus()
      local input = parts.edit.editbox
      if suggest.owner == parts and not parts.released and input and input.SetFocus then
        input:SetFocus()
      end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, refocus) else refocus() end
  end

  local function hookOnce(frame, script, fn)
    if not (frame and frame.HookScript) then return end
    local done = hookedFrames[frame] or {}
    hookedFrames[frame] = done
    if done[script] then return end
    done[script] = true
    frame:HookScript(script, fn)
  end

  --- The keys, the focus and the hiding AceGUI's EditBox has no callback for, hooked once per
  --- pooled frame on its input frame and its own frame. Each hook acts for the box its frame was
  --- drawn for last, and the arrows only while that box owns the dropdown. Leaving -- Escape,
  --- focus lost, the frame hidden -- drops that box's pending update whether or not it shows the
  --- dropdown yet, so a debounce cannot put one up under a box the player has left. A host's AceGUI
  --- without the input frame gets no keys, and the mouse still picks.
  local function hookBox(edit)
    hookOnce(edit.editbox, "OnArrowPressed", function(self, key)
      local o = ownerOf(self)
      if o and ARROW_STEP[key] then moveSelection(o, ARROW_STEP[key]) end
    end)
    hookOnce(edit.editbox, "OnEscapePressed", function(self)
      local p = boxParts[self]
      if p then closeSuggest(p) end
    end)
    hookOnce(edit.editbox, "OnEditFocusLost", function(self)
      local p = boxParts[self]
      if not p then return end
      if suggest.owner == p and pointerOnSuggest() then return refocusLater(p) end
      closeSuggest(p)
    end)
    hookOnce(edit.editbox, "OnEditFocusGained", function(self)
      local p = boxParts[self]
      if p then reoffer(p) end
    end)
    hookOnce(edit.frame, "OnHide", function(self)
      local p = boxParts[self]
      if not p then return end
      p.hidden = true
      closeSuggest(p)
    end)
  end

  --- A keystroke: the list is worked out SUGGEST_DEBOUNCE after the last one, for the text then,
  --- if the box is still there to show it under.
  local function onTyped(parts, text)
    parts.suggestSeq = (parts.suggestSeq or 0) + 1
    parts.offer = nil
    local seq = parts.suggestSeq
    local function run()
      if parts.suggestSeq == seq and canSuggest(parts) then updateSuggest(parts, text) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(SUGGEST_DEBOUNCE, run) else run() end
  end

  local function drawIdInput(ctx, parent, spec, afterAdd)
    local group = startRow(O)
    local eb = O.AceGUI:Create("EditBox")
    eb:SetLabel(spec.label or "")
    eb:SetRelativeWidth(ID_MAIN_REL)
    -- AceGUI's EditBox grows its own Okay button on a change; Add is the button here.
    if eb.DisableButton then eb:DisableButton(true) end
    local add = O.AceGUI:Create("Button")
    add:SetText(idText(spec, "add"))
    add:SetRelativeWidth(ID_ACTION_REL)
    local status = O.AceGUI:Create("Label")
    status:SetFullWidth(true)
    status:SetText("")
    disableIfRender(ctx, eb)
    disableIfRender(ctx, add)

    local parts = { edit = eb, status = status, ctx = ctx, spec = spec, afterAdd = afterAdd }
    -- The hooks find the box from its frames; a pooled frame answers for this render from now on.
    if eb.editbox then boxParts[eb.editbox] = parts end
    if eb.frame then boxParts[eb.frame] = parts end
    -- A released box drops its pending lookup and its suggestions: AceGUI's pool may hand the box
    -- and its status line to another page before the lookup's check or the debounce runs.
    eb:SetCallback("OnRelease", function()
      parts.lookup = nil
      parts.released = true
      closeSuggest(parts)
    end)
    eb:SetCallback("OnTextChanged", function(_, _, text) onTyped(parts, text) end)
    -- Enter takes the highlighted row; with none, it submits what was typed, as it always has --
    -- so a name several ranks share is still refused, never one rank added for the player.
    eb:SetCallback("OnEnterPressed", function(_, _, text)
      if suggest.owner == parts and parts.sel then
        return pickSuggestion(parts, parts.matches[parts.sel])
      end
      closeSuggest(parts)
      submitId(ctx, spec, parts, text, afterAdd)
    end)
    add:SetCallback("OnClick", function()
      closeSuggest(parts)
      -- A shared name refused here hands the box the keys, so the list it puts up can be picked.
      parts.refocus = true
      submitId(ctx, spec, parts, eb.GetText and eb:GetText() or "", afterAdd)
      parts.refocus = nil
    end)
    hookBox(eb)
    O.AttachTooltip(eb, spec.label, spec.tooltip)
    O.AttachTooltip(add, spec.label, spec.tooltip)
    group:AddChild(eb)
    group:AddChild(add)
    group:AddChild(status)
    parent:AddChild(group)
    prewarm(spec)
    return group, eb, add, status
  end

  --- One line an id is added through (minor 16): an edit box taking a number, a shift-clicked link
  --- or a name, an Add button beside it, and a status line under both. Enter or Add resolves the
  --- text through O.ResolveId and hands the id to `spec.onAdd`; the widget never writes a path, so
  --- the host owns storage and its shape. The box and the status line are cleared before onAdd
  --- runs, so onAdd may redraw the page synchronously; a raising onAdd gets both back. It does NOT
  --- redraw anything after an add -- a host that draws its own rows redraws them itself. O.IdList
  --- is this plus the entry lines, and it does.
  ---
  --- Item candidates the client has not cached have no name to match. Drawing the input asks for up
  --- to 200 of them (each id read once a session per instance; the next build moves on to the next
  --- ones), and a typed name -- found or not -- while some are unnamed is looked up: they are asked
  --- for again, 200 a window, the status line reads `looking`, and the text is tried once more when
  --- they land (five asks at 0.4 s a window, at most five windows; an id that never lands is
  --- skipped from then on). A number or a link never waits. A new submit, a box the player types
  --- over, or a released box drops the lookup.
  ---
  --- spec = {
  ---   kind       = "spell" | "item" | "currency", or a host table (see O.ResolveId);
  ---   onAdd      = function(id), called once per successful add;
  ---   candidates = optional function() -> ids, searched by name when the client cannot look one up;
  ---   label, tooltip = the edit box's label and both widgets' tooltip;
  ---   strings    = optional overrides of the words (add, empty, notFound, ambiguous, looking,
  ---                nameHint);
  ---   disabled   = optional; drawn disabled, as ChoiceGrid's is. A disabled render is inherited.
  --- }
  ---
  --- `parent` defaults to the page's scroll. Returns the group, the edit box, the button and the
  --- status label; nil, drawing nothing, with no AceGUI.
  function O.IdInput(ctx, parent, spec)
    parent = parent or O.EnsureScroll(ctx)
    if not (parent and O.AceGUI) then return nil end
    spec = spec or {}
    return underDisable(ctx, spec.disabled, drawIdInput, ctx, parent, spec, nil)
  end

  --- The text an entry's label reads: its name (an item's in its quality color) and its id in
  --- gray, or "Unknown <kind> <id>".
  local function entryLabel(spec, k, id, name)
    if type(name) == "string" and name ~= "" then
      local color = NAME_COLOR[k] and NAME_COLOR[k](id)
      if color then name = color .. name .. "|r" end
      return name .. " " .. ID_GRAY .. "(" .. tostring(id) .. ")|r"
    end
    return idText(spec, "unknown", { noun = (kindWords(k)), id = id })
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
  local function entryTooltip(lbl, k, id)
    local anchor = lbl.frame or lbl
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
  local function entryAction(ctx, spec, entry, line)
    local w
    if entry.toggle then
      w = O.AceGUI:Create("CheckBox")
      w:SetLabel(spec.toggleLabel or "")
      w:SetValue(entry.on and true or false)
      w:SetCallback("OnValueChanged", function(_, _, value)
        callHost(spec.onToggle, entry.id, value and true or false)
      end)
    else
      w = O.AceGUI:Create("Button")
      w:SetText(idText(spec, "remove"))
      w:SetCallback("OnClick", function()
        if callHost(spec.onRemove, entry.id) then rebuildIdList(ctx) end
      end)
    end
    w:SetRelativeWidth(ID_ACTION_REL)
    disableIfRender(ctx, w)
    line:AddChild(w)
  end

  local function idLine(ctx, spec, k, entry, line)
    local name, icon
    if type(k.info) == "function" then name, icon = k.info(entry.id) end
    if name == nil then loadEntry(ctx, k, entry.id) end
    local lbl = O.AceGUI:Create("InteractiveLabel")
    lbl:SetText(entryLabel(spec, k, entry.id, name))
    if icon then
      lbl:SetImage(icon)
      lbl:SetImageSize(ID_ICON_SIZE, ID_ICON_SIZE)
    end
    lbl:SetRelativeWidth(ID_MAIN_REL)
    entryTooltip(lbl, k, entry.id)
    line:AddChild(lbl)
    entryAction(ctx, spec, entry, line)
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
    -- Guarded per line, as ChoiceGrid guards per row: an entry whose lookup raises costs its line.
    local lines = {}
    for _, entry in ipairs(entries) do
      if type(entry) == "table" and entry.id ~= nil then
        local line = startRow(O)
        if renderRowGuarded(print, tostring(entry.id), idLine, ctx, spec, k, entry, line) then
          scroll:AddChild(line)
          lines[#lines + 1] = line
        end
      end
    end
    O.AddSpacer(scroll, L.ROW_VSPACER)
    if scroll.DoLayout then scroll:DoLayout() end
    return lines
  end

  --- An editable id list (minor 16): an optional heading, the O.IdInput line, then one line per
  --- entry -- icon, name and id in gray ("Unknown spell 12345" when the client cannot name it),
  --- then Remove, or a checkbox for a toggle entry. An item's name is drawn in its quality color
  --- once the client answers one; spell and currency names are plain. An item the client has not cached is asked
  --- for through LibKa0s-Item-1.0's LoadItem. Every id a render asks for joins one batch, checked
  --- once 0.4 s later: the list is drawn again once if any of them is named by then, and an id
  --- still unnamed is asked for again, up to five asks in all.
  ---
  --- spec = everything O.IdInput takes, plus:
  ---   entries     = function() -> ordered { { id =, toggle = bool?, on = bool? }, ... };
  ---   onRemove    = function(id), from an entry's Remove;
  ---   onToggle    = function(id, on), from a toggle entry's checkbox;
  ---   heading     = optional section heading, drawn with O.Section;
  ---   emptyText   = optional line drawn when there are no entries;
  ---   toggleLabel = optional label beside a toggle entry's checkbox;
  ---   strings     = as O.IdInput's, plus remove and unknown.
  ---
  --- The host owns storage: the widget calls back and never writes a path. After an add or a remove
  --- it redraws through `ctx.rebuild` when the host set one, else O.RefreshAllPanels(). A toggle
  --- redraws nothing -- the checkbox already shows the new state.
  ---
  --- Returns the entry lines in order; an entry that failed to draw has no line. Nil, drawing
  --- nothing, with no AceGUI.
  function O.IdList(ctx, spec)
    local scroll = O.EnsureScroll(ctx)
    if not scroll then return end
    spec = spec or {}
    return underDisable(ctx, spec.disabled, drawIdList, ctx, scroll, spec)
  end

  --- The flow engine's loop, under the disable flag RenderRows holds for it.
  local function flowRows(ctx, scroll, rows, afterGroup, pairWith, opts)
    local pendingRow, pendingCount = nil, 0

    -- The one-shot bookkeeping below is the LIBRARY's, and it lives in these two call-local sets
    -- rather than in the caller's tables. Consuming the caller's entries would make a second render
    -- of the same page \226\128\148 a unit switch, a ClearScroll + re-render \226\128\148 silently drop every inline
    -- button and every paired widget, for any host that hoisted its table to a file-level constant.
    local firedAfter, firedPair = {}, {}

    local function flushRow()
      if pendingRow then
        scroll:AddChild(pendingRow)
        O.AddSpacer(scroll, L.ROW_VSPACER)
        pendingRow, pendingCount = nil, 0
      end
    end

    for i, row in ipairs(rows) do
      startGroup(O, ctx, row, flushRow, opts and opts.noHeadings)
      startSubgroup(O, ctx, row, flushRow)

      if not row.skipRender then
        if opensLine(row) and pendingCount > 0 then flushRow() end

        if row.wide then
          pendingRow = drawWide(O, ctx, row, pendingRow, print)
          flushRow()
        else
          pendingRow, pendingCount =
            drawRow(O, ctx, row, pendingRow, pendingCount, pairWith, firedPair, print)
          if row.solo or pendingCount >= 2 then flushRow() end
        end
      end

      endGroup(ctx, afterGroup, firedAfter, row, rows[i + 1], flushRow)
    end
    flushRow()
    if scroll.DoLayout then scroll:DoLayout() end
  end

  function O.RenderRows(ctx, rows, afterGroup, pairWith, opts)
    local scroll = O.EnsureScroll(ctx)
    if not scroll then return end
    -- `opts.disabled` (minor 16) holds `ctx.__renderDisabled` for exactly this call: every maker
    -- snapshots it at build, and InlineButtonPair / SessionCheckbox read it, so a widget an
    -- afterGroup or pairWith hook draws is disabled with the page. A nested call with no opts of
    -- its own INHERITS the outer flag, since its widgets are part of the same disabled page, and
    -- the outer value is restored on the way out -- a raise included, or the flag would be
    -- stranded on the ctx and dim the next render. The raise still propagates, as it always has.
    local outer = ctx.__renderDisabled
    ctx.__renderDisabled = ((opts and opts.disabled) or outer) and true or nil
    local ok, err = pcall(flowRows, ctx, scroll, rows, afterGroup, pairWith, opts)
    ctx.__renderDisabled = outer
    if not ok then error(err, 0) end
  end

  --- The per-page wrapper. `ctx.unit` is passed through as the host's filter argument, which is
  --- how a per-unit page renders only the selected unit's rows.
  function O.RenderSchema(ctx, pageKey, afterGroup, pairWith)
    O.RenderRows(ctx, d.rowsForPage(pageKey, ctx.unit) or {}, afterGroup, pairWith)
  end

  --- Render one page as a tab strip over its sections (options-ui-§13).
  ---
  --- The partition is by `group`, IN DECLARATION ORDER, and one tab is exactly one group. There
  --- is no second field naming a tab, for the reason options-ui-§1 gives against a second
  --- widget selector: a tab list declared apart from the rows is a list that goes stale the
  --- first time a section is renamed, and nothing would say so.
  ---
  --- Returns the group names, in tab order.
  ---
  --- A ONE-GROUP PAGE DRAWS ITS STRIP TOO, as of OptionsWidgets minor 13. It did not until then:
  --- "a single tab is chrome for its own sake" is a true sentence about one page and the wrong rule
  --- for a panel (options-ui-§13). A player moving between pages meets a strip on most of them and
  --- bare rows on the rest, and the page that lost its strip is the one that looks broken -- and
  --- the tab is also the only thing naming the group once `noHeadings` has suppressed the heading,
  --- so the fallback took the section's name off the page as well. The one exemption is a page the
  --- host does not render through this engine at all, which today is the AceConfig-drawn Profiles
  --- page: it needs no mechanism here, because it never reaches this function. No opt-out flag is
  --- offered -- a flag is a thing an addon can set for the wrong reason, and there would be no way
  --- to see it in a test.
  ---
  --- A page with NO groups is a different decision: there is nothing to name a tab with, and a
  --- strip of zero tabs is not a strip. That is an authoring defect (anti-patterns #69), so it is
  --- REPORTED and then rendered untabbed -- a blank page under an empty strip is a worse failure
  --- than a strip-less one.
  ---
  --- With no AceGUI there is nothing to draw AT ALL: EnsureScroll answers nil and every maker in
  --- this file refuses, so this reports an empty tab list and draws nothing -- which is what
  --- RenderRows would also have done, reached or not.
  function O.RenderTabbedSchema(ctx, pageKey, afterGroup, pairWith)
    local rows = d.rowsForPage(pageKey, ctx.unit) or {}

    local groups, seen = {}, {}
    for _, row in ipairs(rows) do
      if row.group and not seen[row.group] then
        seen[row.group] = true
        groups[#groups + 1] = row.group
      end
    end

    if not O.AceGUI then return {} end
    if #groups == 0 then
      print(lib.STRINGS.NO_GROUPS:format(tostring(pageKey)))
      O.RenderRows(ctx, rows, afterGroup, pairWith)
      return groups
    end

    -- A tab pointing at a group this page no longer has renders an empty page under a strip,
    -- so a stale pointer heals to the first rather than being trusted. Cheap enough to check on
    -- every render, and the alternative is a page that is blank until the user clicks something.
    if not (ctx.activeTab and seen[ctx.activeTab]) then
      ctx.activeTab = groups[1]
    end

    local tabs = {}
    for i, name in ipairs(groups) do tabs[i] = { key = name, label = name } end

    O.TabStrip(ctx, {
      tabs  = tabs,
      value = ctx.activeTab,
      onSelect = function(key)
        if key == ctx.activeTab then return end
        ctx.activeTab = key
        -- The same re-render path a change of subject takes (ClearScroll then a fresh
        -- render), but that path carries no combat refusal to inherit -- options-ui-§2's
        -- guard lives in the panel's OnShow and covers the category switch Blizzard protects.
        -- Redrawing widgets inside an already-open panel was never a protected action, so a
        -- tab click needs no guard here and none is added (options-ui-§13).
        O.ClearScroll(ctx)
        O.RenderTabbedSchema(ctx, pageKey, afterGroup, pairWith)
      end,
    })

    local active = {}
    for _, row in ipairs(rows) do
      if row.group == ctx.activeTab then active[#active + 1] = row end
    end
    O.RenderRows(ctx, active, afterGroup, pairWith, { noHeadings = true })

    return groups
  end
end
