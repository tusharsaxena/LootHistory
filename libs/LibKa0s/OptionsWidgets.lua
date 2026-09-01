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

local WIDGETS_MINOR = 12
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
end

--- Claim a host hook for `key`, or nil if there is none or it has already run this render.
---
--- The lookup and the marking are ONE step on purpose. RenderRows honours two hook tables — pairWith
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
    local pair = takeOnce(pairWith, firedPair, row.path)
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

--- The three atlas slices: two end caps at their NATURAL atlas size, and a middle stretched
--- horizontally between their inner edges. A tab narrower than the two caps would draw them
--- overlapping rather than tearing, which is why TAB_MIN_W is comfortably wider than either.
---
--- Returns the ART's height, which is NOT the button's. The art is anchored to the button's
--- BOTTOM and takes the atlas's own size, so a 37px button carrying 28px of art has nine empty
--- pixels along its top. That number is only knowable from the client -- an atlas has no size
--- until one is resolved -- and it is what a second row of tabs has to be packed by, or the empty
--- strip is drawn as a gap between the rows.
--- @return number|nil  the cap atlas's height in pixels, or nil where none can be measured
local function drawTabSlices(b, atlas)
  local artH
  local left = tabTexture(b, "BACKGROUND")
  if left then
    if left.SetAtlas then left:SetAtlas(atlas[1], true) end
    left:SetPoint("BOTTOMLEFT")
    local h = left.GetHeight and left:GetHeight()
    if type(h) == "number" and h > 0 then artH = h end
  end

  local right = tabTexture(b, "BACKGROUND")
  if right then
    if right.SetAtlas then right:SetAtlas(atlas[3], true) end
    right:SetPoint("BOTTOMRIGHT")
  end

  local mid = tabTexture(b, "BACKGROUND")
  if mid and left and right then
    if mid.SetAtlas then mid:SetAtlas(atlas[2], true) end
    mid:SetPoint("TOPLEFT",  left,  "TOPRIGHT")
    mid:SetPoint("TOPRIGHT", right, "TOPLEFT")
  end

  return artH
end

--- The dark backing behind the label, inset so it never touches the caps' lit edges. It stops
--- 3px higher on the selected tab, which is half of how the two states differ.
local function drawTabFill(b, active)
  local bg = tabTexture(b, "BACKGROUND", -2)
  if not bg then return end
  bg:SetPoint("BOTTOMLEFT", TAB_BG_INSET, 0)
  bg:SetPoint("TOPRIGHT", -TAB_BG_INSET, TAB_BG_TOP[active])
  if bg.SetColorTexture then bg:SetColorTexture(1, 1, 1, 1) end
  gradient(bg, TAB_BG_BOTTOM_COLOR, TAB_BG_TOP_COLOR)
end

--- One of the two glows. They are the same gradient at different heights on different layers:
--- the HIGHLIGHT one is drawn by the client on mouseover only, the BACKGROUND one is lit for as
--- long as the tab is selected. Only one is ever on, which is why `on` is a parameter rather
--- than a second function.
local function drawTabGlow(b, layer, sublevel, top, on)
  local tex = tabTexture(b, layer, sublevel)
  if not tex then return end
  tex:SetPoint("BOTTOMLEFT", TAB_BG_INSET, 0)
  tex:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", -TAB_BG_INSET, top)
  setGlow(tex, on)
  gradient(tex, TAB_GLOW_BOTTOM, TAB_GLOW_TOP)
end

--- Draw one tab button's art: three atlas slices, a dark backing, and the two glows.
---
--- Split four ways rather than written straight through, because every texture path in this file
--- carries the same two guards and a single function wearing all of them measured past the CCN
--- ceiling the release gate enforces. Every texture is a child of `b`, so they share the button's
--- lifecycle: releaseLedger hides and unparents `b` and the art goes with it -- no separate
--- ledger entry needed for any of them.
--- @return number|nil  the art's own height, for the strip to pack its rows by
local function drawTabArt(b, active)
  local artH = drawTabSlices(b, TAB_ATLAS[active])
  drawTabFill(b, active)
  drawTabGlow(b, "HIGHLIGHT",  nil, TAB_HL_TOP,  not active)
  drawTabGlow(b, "BACKGROUND", -1,  TAB_SEL_TOP, active)

  -- The empty strip along the button's top is not part of the tab and must not be clickable:
  -- a wrapped strip packs the next row by the ART's height, so row 2's button overlaps row 1's
  -- art by exactly that many pixels, and without this it would swallow clicks meant for row 1.
  if artH and b.SetHitRectInsets then b:SetHitRectInsets(0, 0, L.TAB_H - artH, 0) end

  return artH
end

--- The tab's label, anchored to the tab's BOTTOM rather than its centre.
---
--- A tab is taller than its text by design -- the extra height is the foot that overlaps the
--- content panel -- so a centred label would float in the middle of the overlap instead of
--- sitting on the tab's face. The selected tab lifts its label 2px and brightens the font, which
--- is the other half of how the two states differ.
local function setTabLabel(b, active, text)
  local fs = b.CreateFontString and b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  if fs and b.SetFontString then
    b:SetFontString(fs)
    if fs.ClearAllPoints then fs:ClearAllPoints() end
    if fs.SetPoint then fs:SetPoint("BOTTOM", 0, TAB_LABEL_Y[active]) end
  end
  b:SetNormalFontObject(active and _G.GameFontHighlightSmall or _G.GameFontNormalSmall)
  b:SetHighlightFontObject(_G.GameFontHighlightSmall)
  b:SetDisabledFontObject(_G.GameFontHighlightSmall)
  if b.SetPushedTextOffset then b:SetPushedTextOffset(0, 0) end
  b:SetText(text or "")
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
local function drawContentPanel(ctx)
  if not (ctx.body and ctx.chrome) then return end
  local panel = CreateFrame("Frame", nil, ctx.body)
  if panel.SetFrameLevel and ctx.body.GetFrameLevel then
    local level = ctx.body:GetFrameLevel()
    if type(level) == "number" then panel:SetFrameLevel(level) end
  end
  -- Vertically it hangs off the chrome, so it follows the band when a strip wraps to a second
  -- row. Horizontally it is anchored to the BODY, not the chrome: the box has to be wider than
  -- the content column it encloses, or the scrollbar is painted on its right edge and the
  -- left-hand labels butt against its left one.
  panel:SetPoint("TOPLEFT",     ctx.chrome, "BOTTOMLEFT",  -(L.CONTENT_LEFT - L.PANEL_LEFT), 0)
  panel:SetPoint("TOPRIGHT",    ctx.chrome, "BOTTOMRIGHT",   L.CONTENT_RIGHT - L.PANEL_RIGHT, 0)
  panel:SetPoint("BOTTOMLEFT",  ctx.body,   "BOTTOMLEFT",    L.PANEL_LEFT,  L.PANEL_BOTTOM)
  panel:SetPoint("BOTTOMRIGHT", ctx.body,   "BOTTOMRIGHT",  -L.PANEL_RIGHT, L.PANEL_BOTTOM)

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

--- Attach the widget makers and the flow engine to one instance. Called at the end of lib:New, so
--- every host gets its own closures over its own descriptor.
function lib.__AttachWidgets(O, d)
  local print = d.print or function() end

  local function get(path) return d.get(path) end

  -- Write a row's value through the host's single write seam, then re-sync every widget on every
  -- panel. That is what makes paired controls just work: a "Use Class Color" toggle flips and its
  -- matching swatch grays out on the same frame. AceGUI's SetValue does not fire OnValueChanged,
  -- so this cannot recurse.
  --
  -- SCALARS, not the structural tier. Writing a value does not change which rows exist, and a
  -- rebuild on every checkbox click would tear down and recreate every widget on the page — which
  -- is exactly what the two-tier split exists to avoid.
  local function set(row, value)
    d.set(row.path, value)
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

  --- Release everything a page parked in its chrome band -- the banner AND the strip.
  ---
  --- Two ledgers, one release, because the two have different LIFETIMES: a tab click redraws the
  --- strip alone and drains __tabKids itself, while only a full page render redraws the banner.
  --- Draining both here is what keeps the page-wide teardown total without making the strip's
  --- ledger a second copy of it -- when TabStrip appended to both, __chromeKids grew by one entry
  --- per tab click, forever, holding buttons already hidden and unparented.
  local function releaseChrome(ctx)
    releaseLedger(ctx, "__chromeKids")
    releaseLedger(ctx, "__tabKids")
  end
  O.__releaseChrome = releaseChrome

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

  --- One tab button: art, state, handler, and its measured width.
  ---
  --- Lifted out of TabStrip's loop because the loop is the only interesting thing left in that
  --- function -- packing widths into rows -- and a button's construction is six unrelated
  --- decisions that were making one function read as two.
  ---
  --- The ACTIVE tab is the DISABLED one, which is how Blizzard's own tab groups mark selection
  --- and is why it needs no second piece of art to say so: a disabled button does not highlight
  --- on hover and does not fire, so clicking the tab you are already on cannot re-render the
  --- page you are already looking at.
  ---
  --- @return table  the button frame
  --- @return number its measured width, in pixels
  local function makeTab(ctx, tab, active, onSelect)
    local b = CreateFrame("Button", nil, ctx.chrome)
    b:SetHeight(L.TAB_H)
    -- One level above the chrome, so a tab's art draws OVER the content panel's top edge rather
    -- than under it -- which is what lets the selected tab merge into the page below it.
    if b.GetFrameLevel and b.SetFrameLevel then
      local level = b:GetFrameLevel()
      if type(level) == "number" then b:SetFrameLevel(level + 1) end
    end

    setTabLabel(b, active, tab.label)
    local artH = drawTabArt(b, active)

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
    if tab.tooltip then O.AttachTooltip(b, tab.label, tab.tooltip) end

    return b, labelWidth(b.GetFontString and b:GetFontString()), artH
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
  --- The strip's own width: the chrome's, which is the body inset by CONTENT_LEFT/RIGHT. Zero
  --- until the canvas has laid itself out, which is the whole subject of replaceOnResize below.
  local function chromeWidth(ctx)
    local w = ctx.chrome and ctx.chrome.GetWidth and ctx.chrome:GetWidth()
    if type(w) ~= "number" or w <= 0 then return L.TAB_MIN_W end
    return w
  end

  --- How far apart two rows of tabs sit: the ART's height, so a wrapped row is FLUSH with the
  --- one above it rather than separated by the empty strip along each button's top. Falls back to
  --- the button height where nothing can be measured -- a headless harness, or a client that
  --- answered no size for the atlas -- which is the pre-measurement behavior with no gap.
  local function rowPitch(ctx)
    local h = ctx.__tabArtH
    if type(h) ~= "number" or h <= 0 or h > L.TAB_H then return L.TAB_H end
    return h
  end

  local function placeTabs(ctx, buttons, widths, available)
    ctx.__tabPlacedAt = available

    local top = ctx.__bannerHeight or 0
    local pitch = rowPitch(ctx)
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

    -- Only the strip's own buttons, never the banner: the banner is drawn first and a blanket
    -- release here would take it with them.
    releaseLedger(ctx, "__tabKids")
    ctx.__tabLayout = nil

    local buttons, widths = {}, {}
    ctx.__tabArtH = nil
    for i, tab in ipairs(spec.tabs) do
      local b, w, artH = makeTab(ctx, tab, tab.key == spec.value, spec.onSelect)
      buttons[i] = b
      widths[i]  = w
      ctx.__tabArtH = ctx.__tabArtH or artH
      ctx.__tabKids[#ctx.__tabKids + 1] = b
    end

    -- The panel is built before the tabs are placed, because it anchors to the chrome's BOTTOM
    -- and SetChromeHeight is what moves that edge; built after, it would still land correctly,
    -- but the ledger order would no longer say which of the two owns the separator.
    drawContentPanel(ctx)

    ctx.__tabLayout = { buttons = buttons, widths = widths }
    placeTabs(ctx, buttons, widths, chromeWidth(ctx))
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
      local btn = O.AceGUI:Create("Button")
      btn:SetText(spec.text or "")
      btn:SetRelativeWidth(L.BUTTON_PAIR_REL)
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

    local function readValue() return get(row.path) and true or false end

    cb:SetValue(readValue())
    local function refresh() cb:SetValue(readValue()) end

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

    local function refresh()
      local v = get(row.path)
      -- A corrupt SavedVariable would otherwise hand AceGUI a nil or a string and blow up the
      -- layout pass, taking the whole page with it.
      if type(v) ~= "number" then v = row.default or row.min or 0 end
      s:SetValue(v)
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

    local function applyList()
      local items, order = {}, {}
      for i, item in ipairs(enumList(row)) do
        items[item.value] = item.text
        order[i] = item.value
      end
      dd:SetList(items, order)
    end
    applyList()
    dd:SetValue(get(row.path))

    local function refresh()
      applyList()                            -- media lists grow as other addons register into them
      dd:SetValue(get(row.path))
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
    eb:SetText(get(row.path) or "")

    local function refresh() eb:SetText(get(row.path) or "") end

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

    local function readColor() return decodeColor(get(row.path)) end

    cp:SetColor(readColor())

    local function applyDisabled()
      if row.disabledIf then
        cp:SetDisabled(get(row.disabledIf) and true or false)
      end
    end
    applyDisabled()

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
      d.set(row.path, encodeColor(r, g, b, a))
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

  function O.RenderRows(ctx, rows, afterGroup, pairWith, opts)
    local scroll = O.EnsureScroll(ctx)
    if not scroll then return end
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

      if not row.skipRender then
        if row.solo and pendingCount > 0 then
          flushRow()
        end

        pendingRow, pendingCount =
          drawRow(O, ctx, row, pendingRow, pendingCount, pairWith, firedPair, print)

        if row.solo or pendingCount >= 2 then flushRow() end
      end

      endGroup(ctx, afterGroup, firedAfter, row, rows[i + 1], flushRow)
    end
    flushRow()
    if scroll.DoLayout then scroll:DoLayout() end
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
  --- Returns the group names, in tab order. A page with fewer than two groups draws no strip --
  --- a single tab is chrome for its own sake, and its band would push the page down for nothing.
  ---
  --- With no AceGUI there is nothing to draw AT ALL: EnsureScroll answers nil and every maker in
  --- this file refuses, so this reports an empty tab list and draws nothing -- which is what
  --- RenderSchema would also have done, reached or not. The fallback that matters is the
  --- single-group one above it, not this.
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
    if #groups < 2 then
      O.RenderSchema(ctx, pageKey, afterGroup, pairWith)
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
