-- LibKa0s-Widgets-1.0 — ReorderList: drag a row of a list to a new position, and the row box every
-- draggable row in the collection wears.
--
-- ── WHY IT IS A FILE OF ITS OWN AND NOT MORE OF Widgets.lua ──────────────────────────────────
--
-- Because of `layout-§1`, as for WidgetsDragHandle.lua. Widgets.lua held three widgets at 1303
-- lines, in the 1000–1500 band, and issue #36 named the seam: one file per widget, ReorderList
-- first. It moved here unchanged at Widgets minor 12. It is NOT a major of its own: it is part of
-- `LibKa0s-Widgets-1.0`, guarded with the same multi-file idiom, so a list from one vendored copy
-- can never pair with a shell from another without saying so. It reads nothing of the shell's but
-- `lib`; the handle's fallback art, the one file-level value it shared with the dropdown's, is
-- restated below.
--
-- Depends on LibStub and on the Widgets shell, and on no addon framework. A payload without this
-- file loads whole and simply has no `lib.ReorderList` and no `lib.ROW_BOX`.

local lib = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
if not lib then return end

local REORDER_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own, as WidgetsDragHandle.lua is: a list that
-- attached to an older shell would publish `lib.ReorderList` beside a `lib.MODULES` the shell owns,
-- and nothing would say the two came from different vendored copies.
if lib.__reorderMinor and lib.__reorderMinor >= REORDER_MINOR
  and lib.__reorderShellMinor == lib.MINOR then return end
lib.__reorderMinor      = REORDER_MINOR
lib.__reorderShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.WidgetsReorder = REORDER_MINOR

-- The rung below the handle's injected art: what a host with no LibKa0s-Media draws.
local HANDLE_FALLBACK = "Interface\\Buttons\\UI-SortArrow"

-- ── ReorderList ───────────────────────────────────────────────────────────────────────────────
--
-- Drag a row of a list to a new position. The library owns the GESTURE and everything you see
-- while it is happening; the host owns the rows.
--
-- ── WHERE THE LINE IS DRAWN, AND WHY THERE ────────────────────────────────────────────────────
--
-- The two shipped consumers draw completely different rows. MultiMeters' Columns page is a state
-- glyph and a statistic name; ConsumableMaster's priority list is a live item tooltip, a
-- crafting-quality glyph, a pick star, a score button and a remove button. Neither would accept a
-- widget that owned its row content, and a `render(row, item)` callback wide enough for both is
-- not an abstraction -- it is a hole shaped like two addons.
--
-- So this owns no row content at all. It owns the handle, the copy that follows the cursor, the
-- insertion line, the index arithmetic, the clamp, and nothing else. A host builds its rows however
-- it already does -- AceGUI, raw frames, anything -- hands each one over, and gets `onMove` back.
-- That is also the whole of what was hard: the gesture took four rounds to get right in a client,
-- and the row content took none.
--
-- ── WHAT THE HOST STILL DECIDES ───────────────────────────────────────────────────────────────
--
-- Where the handle sits, how big it is, what art it wears, how tall a row is, whether the list has
-- two groups or one. All parameters. What it does NOT decide is what a drag LOOKS like, because
-- that is the thing every list in the collection should share -- the same ghost at the same alpha,
-- the same gold insertion line, the same fade on the row you picked up.
--
-- ── WHY THE ART ARRIVES AS A PARAMETER ────────────────────────────────────────────────────────
--
-- Same reason `chevron` and `check` do, and it is the reason stated at the top of Widgets.lua:
-- `Media.Icon` takes the CONSUMING ADDON'S name to build a path, and a vendored copy cannot know
-- which addon folder it was copied into. `handleIcon` is a resolved path or nil, and nil falls to a
-- Blizzard texture, so a host with no LibKa0s-Media still gets a working handle.

-- ── WHY THE ROW BOX IS THE WIDGET'S AND NOT THE HOST'S ────────────────────────────────────────
--
-- A DELIBERATE REVERSAL of the paragraph above it, recorded as one. Minor 8 said this widget owns
-- "the handle, the copy that follows the cursor, the insertion line, the index arithmetic, the
-- clamp, and nothing else". It now also owns the ROW BOX -- the faint fill and the hairline border
-- that make a stack of rows read as blocks you can pick up -- because "a draggable row looks like
-- this" is a property of the COLLECTION (options-ui-§18), and a property of the collection cannot
-- live in two consumers' private code. It did: MultiMeters drew a 6% white fill and no border,
-- ConsumableMaster drew nothing at all, and that is the drift.
--
-- The row's CONTENTS are still entirely the consumer's, and nothing about AddRow's content
-- contract changes. What moved is the box UNDER them.

-- The canonical values, published so an audit can read them and a consumer never restates them
-- (options-ui-§8). White and low-alpha rather than a chosen hue, so a box reads the same over
-- whatever the host's page is painted with; the dimmed pair is for a row that is present but not
-- draggable -- MultiMeters' hidden columns, LootHistory's sources it is not collecting.
lib.ROW_BOX = {
  FILL      = { 1, 1, 1, 0.06 },   -- MultiMeters' shipped fill, now everyone's
  FILL_DIM  = { 1, 1, 1, 0.03 },
  EDGE      = { 1, 1, 1, 0.12 },   -- 1px, all four sides; the border nobody had
  EDGE_DIM  = { 1, 1, 1, 0.06 },
  EDGE_SIZE = 1,
  HANDLE_W  = 30,                  -- the left gutter the handle owns; row contents start beyond it
}

-- The one copy carried under the cursor, process-wide. A singleton for the same reason the dropdown
-- menu is one: it lives on UIParent so it can follow the pointer OUT of whatever scroll frame the
-- list sits in, and a per-list copy would clip at the first edge it met.
local ghost

-- Forward-declared: the ghost's OnUpdate is wired when the ghost is built, and the drag it polls is
-- defined further down with the rest of the drag.
local trackDragFromGhost

local function ensureGhost()
  if ghost then return ghost end

  ghost = CreateFrame("Frame", nil, UIParent)
  ghost:SetFrameStrata("TOOLTIP")
  ghost:SetSize(300, 30)
  -- LOAD-BEARING, NOT TIDY: a frame sitting under the pointer that accepts the mouse eats the very
  -- button-release that ends the drag it is drawing.
  ghost:EnableMouse(false)
  ghost:SetAlpha(0.9)
  ghost:Hide()

  ghost.bg = ghost:CreateTexture(nil, "BACKGROUND")
  ghost.bg:SetAllPoints(ghost)
  ghost.bg:SetColorTexture(0.12, 0.12, 0.12, 0.95)

  ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
  ghost.icon:SetSize(18, 18)
  ghost.icon:SetPoint("LEFT", ghost, "LEFT", 8, 0)

  ghost.text = ghost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ghost.text:SetPoint("LEFT", ghost.icon, "RIGHT", 6, 0)
  ghost.text:SetPoint("RIGHT", ghost, "RIGHT", -8, 0)
  ghost.text:SetJustifyH("RIGHT")

  -- THE DRAG'S POLL LIVES HERE, on a frame this library owns, and reads its row at fire time. Until
  -- minor 10 it was `row.frame:SetScript("OnUpdate", ...)` on the HOST's row frame, cleared with
  -- nil at the drop -- which wiped any OnUpdate the host had set there. The ghost is shown for
  -- exactly as long as a drag is in flight, so the client polls it for exactly that long.
  ghost:SetScript("OnUpdate", function(self) trackDragFromGhost(self.__row) end)

  -- `__`-PREFIXED IS INTERNAL, the same contract `dd.__check` carries: published so a suite can
  -- ask whether the carried copy exists, is shown, reads as the right row and follows the cursor,
  -- none of which is reachable from the controller. A host must not touch it -- what it draws is
  -- the one part of a drag this library deliberately does not let a host restyle.
  lib.__DragGhost = ghost

  return ghost
end

--- Put the ghost under the cursor, offset right so the pointer sits ON what it is carrying.
local function moveGhost()
  if not (ghost and ghost:IsShown()) then return end
  local x, y = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  if type(x) ~= "number" or type(y) ~= "number" or type(scale) ~= "number" or scale == 0 then
    return
  end
  ghost:ClearAllPoints()
  ghost:SetPoint("LEFT", UIParent, "BOTTOMLEFT", (x / scale) + 14, y / scale)
end

--- Where a row dropped `rows` rows from `from` lands, clamped to its own group.
---
--- THE CLAMP IS AN INTERACTION RULE, not a safety check, and it only exists when the host says the
--- list has two groups. A flat list clamps to its own ends and nothing else.
local function dropIndex(from, rows, count, boundary)
  local lo, hi = 1, count
  if boundary and boundary > 0 and boundary < count then
    if from <= boundary then hi = boundary else lo = boundary + 1 end
  end

  local to = from + rows
  if to < lo then to = lo end
  if to > hi then to = hi end
  return to
end

--- Is the left button still down? Answers nil when the question cannot be asked.
local function mouseHeld()
  if type(IsMouseButtonDown) ~= "function" then return nil end
  local ok, held = pcall(IsMouseButtonDown, "LeftButton")
  if not ok then return nil end
  return held and true or false
end

-- ── the handle pool ──────────────────────────────────────────────────────────────────────────
--
-- THE LIBRARY OWNS ITS HANDLES. It does not cache them on the frames a host hands over, and the
-- reason is the whole of a bug that shipped:
--
-- Both consumers hand over frames their UI framework POOLS. Caching a handle on one looked right,
-- because the same host gets the same frame back at its next render -- but AceGUI's pool is
-- process-wide and typeless within a widget type. A released container is handed to whatever asks
-- next, and what asked next was a completely unrelated part of the page: a drag handle appeared on
-- "Drag to action bar", on an ID entry row, on a dropdown. The frame's identity is simply not the
-- host's to lend, and a cache keyed on it is a cache keyed on nothing.
--
-- So handles are acquired from a free list here and RELEASED on Cancel -- hidden, unanchored and
-- reparented off the host's frame in one step. A handle can then only ever be visible on a frame
-- this library put it on, during a render it is live for.

-- The BOXES are pooled on exactly the same terms and for exactly the same reason: a box is another
-- frame this library parents to a frame the host pools, so it has to be given back the same way.
local handlePool, boxPool, handleAttic = {}, {}, nil

-- AND SO IS THE INSERTION LINE, from minor 10. Until then it was cached on the container as
-- `__ka0sDropLine`, and both shipped consumers hand over an AceGUI-pooled container -- so the line
-- rode back into AceGUI's pool, colored for the first list that ever drew on it. It is now taken
-- from this free list per DRAG, recolored for the list that is dragging, and given back at the
-- drop and on Cancel.
local linePool = {}

local function atticFrame()
  if not handleAttic then
    handleAttic = CreateFrame("Frame", nil, UIParent)
    handleAttic:Hide()
  end
  return handleAttic
end

--- Give one list of borrowed frames back to its pool: hidden, unanchored, and off the host's frame,
--- in one step. Returns how many were reclaimed.
---
--- Shared by the handles and the boxes rather than written twice, because those three steps are the
--- whole of the contract and a copy that forgot the reparent would fail in the way that is only
--- ever visible on someone else's page.
local function reclaim(borrowed, pool)
  local n = #borrowed
  for i = n, 1, -1 do
    local f = borrowed[i]
    borrowed[i] = nil
    f.__row = nil
    f:Hide()
    f:ClearAllPoints()
    f:SetParent(atticFrame())
    pool[#pool + 1] = f
  end
  return n
end

--- Take an insertion line for one drag onto `container`, painted in `color`.
---
--- A FRAME CARRYING A TEXTURE, not a bare texture. A texture belongs to its own frame's draw layers,
--- so one created on the container draws UNDER every row -- each row is a child frame with its own
--- layers, and a parent's OVERLAY still loses to a child. The line has to be a sibling that
--- outranks them. Answers nil with no container, and the drag then simply draws no line.
local function acquireLine(container, color)
  if not container then return nil end

  local line = table.remove(linePool)
  if not line then
    line = CreateFrame("Frame", nil, atticFrame())
    line:SetHeight(3)
    line.tex = line:CreateTexture(nil, "OVERLAY")
    line.tex:SetAllPoints(line)
  end

  line:SetParent(container)
  -- Guarded on the ANSWER rather than on the method existing: a stub that returns itself for
  -- anything it does not implement answers a table here, and adding to it raises.
  local level = container.GetFrameLevel and container:GetFrameLevel()
  if type(level) == "number" then line:SetFrameLevel(level + 20) end
  -- Every acquire, never once at build: a pooled line last served some other list's color.
  line.tex:SetColorTexture(color[1], color[2], color[3], color[4])
  line:ClearAllPoints()
  line:Hide()
  return line
end

--- Give a list's line back, if it holds one.
local function releaseLine(list)
  if list.line then
    reclaim({ list.line }, linePool)
    list.line = nil
  end
end

-- ── the row box ───────────────────────────────────────────────────────────────────────────────
--
-- A FRAME CARRYING FIVE TEXTURES, not five textures on the host's own frame. Both consumers hand
-- over frames their UI framework POOLS, and a texture is not a widget: nothing releases it and
-- nothing hides it, so one created on a pooled frame rides that frame back into the pool and
-- reappears the next time it is handed out for something else entirely. That failure is already
-- written down in this collection -- see the landing-page logo in LibKa0s/OptionsWidgets.lua -- and
-- a box is the same shape of mistake one widget over. A frame can be reparented off the host's
-- frame in one step, which is exactly what Cancel does with the handles.
--
-- Four edges rather than `SetBackdrop`, because a backdrop needs `BackdropTemplate` at CreateFrame
-- time and a template is a client-version dependency. Four rectangles are not.

--- Build one box's five textures, once, when the frame is first made.
local function buildRowBox(box)
  box.fill = box.CreateTexture and box:CreateTexture(nil, "BACKGROUND")
  if not (box.fill and box.fill.SetColorTexture) then
    box.fill = nil
    return
  end
  box.fill:SetAllPoints(box)

  -- top, bottom, left, right -- each pinned to two corners and given its thickness on the
  -- remaining axis, so the border follows the box however the host sizes the row.
  local plan = {
    { "TOPLEFT",    "TOPRIGHT",    true  },
    { "BOTTOMLEFT", "BOTTOMRIGHT", true  },
    { "TOPLEFT",    "BOTTOMLEFT",  false },
    { "TOPRIGHT",   "BOTTOMRIGHT", false },
  }
  box.edges = {}
  for i, e in ipairs(plan) do
    local tex = box:CreateTexture(nil, "BORDER")
    tex:SetPoint(e[1], box, e[1], 0, 0)
    tex:SetPoint(e[2], box, e[2], 0, 0)
    if e[3] then tex:SetHeight(lib.ROW_BOX.EDGE_SIZE) else tex:SetWidth(lib.ROW_BOX.EDGE_SIZE) end
    box.edges[i] = tex
  end
end

--- Paint one box for the row it is serving THIS render. Separate from building it because a pooled
--- box may have last served a dimmed row and must not carry that over.
local function paintRowBox(box, dimmed)
  if not box.fill then return end
  local R = lib.ROW_BOX
  local fill = dimmed and R.FILL_DIM or R.FILL
  local edge = dimmed and R.EDGE_DIM or R.EDGE
  box.fill:SetColorTexture(fill[1], fill[2], fill[3], fill[4])
  for _, tex in ipairs(box.edges or {}) do
    tex:SetColorTexture(edge[1], edge[2], edge[3], edge[4])
  end
end

-- ── the drag, hoisted out of the controller ───────────────────────────────────────────────────
--
-- These take a ROW and reach the controller through `row.list`, rather than closing over one.
--
-- THAT IS NOT STYLE. The handle is cached on a frame its host POOLS and reused across renders, so
-- a handler closing over the controller that built it would still be calling that controller after
-- it had been Cancel()led -- which is a drag that works exactly once and then freezes. `handle.__row`
-- fixes which row; this fixes which controller. Both halves are needed, and fixing only the first
-- is a bug that still passes a test written against the first.

local function showLine(row, to)
  local list = row.list
  local target = list.rows[to]
  if not (list.line and target) then return end
  local f = target.frame
  list.line:ClearAllPoints()
  -- ANCHORED TO THE TARGET ROW, never positioned by arithmetic. The index comes from the cursor,
  -- but where that index sits on screen is a question only the frames can answer -- and anchoring
  -- asks it without reading a single coordinate back.
  if to <= row.index then
    list.line:SetPoint("BOTTOMLEFT",  f, "TOPLEFT",  0, 0)
    list.line:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 0)
  else
    list.line:SetPoint("TOPLEFT",  f, "BOTTOMLEFT",  0, 0)
    list.line:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, 0)
  end
  list.line:Show()
end

local function finishDrag(row)
  if not row then return end
  local list = row.list

  if ghost and ghost.__row == row then ghost.__row = nil end
  if ghost then ghost:Hide() end
  releaseLine(list)
  if row.frame.SetAlpha then row.frame:SetAlpha(1) end

  if not row.startY then return end
  row.startY  = nil
  row.sawDown = nil
  list.dragging = nil

  local to = dropIndex(row.index, row.rows or 0, #list.rows, list.boundary)
  list.say("drop %d -> %d (%d rows)", row.index, to, row.rows or 0)
  -- A drag that lands where it started is not a reorder, and reporting one would have the host
  -- rewrite its list and repaint for no change at all.
  if to ~= row.index and list.onMove and not list.dead then
    list.onMove(row.index, to)
  end
end

local function trackDrag(row)
  if not row or not row.startY then return end
  local list = row.list

  local _, y = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  if type(y) == "number" and type(scale) == "number" and scale ~= 0 then
    -- +0.5 then floor is round-to-nearest: a row dragged 60% of the way to the next slot has
    -- visibly left its own, and rounding down would drop it back where it started.
    row.rows = math.floor(((row.startY - (y / scale)) / list.stride) + 0.5)
  end

  moveGhost()
  showLine(row, dropIndex(row.index, row.rows or 0, #list.rows, list.boundary))

  -- THE POLL MAY NOT ACT ALONE, and this is why it has to see the button held first. If
  -- IsMouseButtonDown is unavailable, protected, or simply not true yet on the first frame, a poll
  -- that ended the drag on `not held` would finish it with zero rows traveled -- no error, no
  -- message, and indistinguishable from a press that was never received.
  local held = mouseHeld()
  if held then
    row.sawDown = true
  elseif held == false and row.sawDown then
    finishDrag(row)
  end
end
trackDragFromGhost = trackDrag

--- Dress the carried copy as the row it came from and put it under the cursor.
---
--- Its own function because `beginDrag` was doing two jobs -- starting a drag, and drawing one --
--- and the pair came to CCN 17 against a release gate of 15. Splitting on that seam rather than
--- anywhere cheaper: the state machine and the picture it paints are genuinely separable, and this
--- half is the one that grows when the ghost gains a field.
local function raiseGhost(row, list)
  local g = ensureGhost()

  local w = row.frame.GetWidth and row.frame:GetWidth()
  if type(w) == "number" and w > 0 then g:SetWidth(w) end
  g:SetHeight(row.height or list.stride)

  g.icon:SetTexture(row.ghostIcon or list.handleIcon or HANDLE_FALLBACK)
  local ic = row.ghostIconColor or { 1, 1, 1 }
  g.icon:SetVertexColor(ic[1], ic[2], ic[3])

  g.text:SetText(row.ghostText or "")
  local tc = row.ghostTextColor or { 1, 0.82, 0 }
  g.text:SetTextColor(tc[1], tc[2], tc[3])

  g:Show()
  moveGhost()
end

local function beginDrag(row)
  if not row then return end
  local list = row.list
  if row.startY or list.dead then return end

  local _, y = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  if type(y) ~= "number" or type(scale) ~= "number" or scale == 0 then return end

  row.startY  = y / scale
  row.rows    = 0
  row.sawDown = nil
  list.dragging = row
  -- A line left by a drag whose release never arrived goes back before this one takes its own.
  releaseLine(list)
  list.line = acquireLine(list.container, list.color)
  -- The row you picked up fades IN THE LIST, because the copy under the cursor is the one you are
  -- looking at now.
  if row.frame.SetAlpha then row.frame:SetAlpha(0.35) end

  raiseGhost(row, list)
  ghost.__row = row   -- the poll, read at fire time: see ensureGhost
  list.say("grab %d at y=%.1f", row.index, row.startY)
end

--- Build a reorderable list controller.
---
--- One controller per RENDER, not one per list: it holds the rows of the pass that built it, and a
--- repaint builds a new one. `Cancel` on the old one is what stops a drag outliving the list it
--- was describing.
---
--- @param opts table
---   stride     number            row top to next row top, in pixels. Required -- the drop target is
---                                arithmetic on this, never a hit test, so nothing depends on the
---                                rows having been laid out yet.
---   onMove     function(from,to) called once when a drag lands somewhere new. Never called for a
---                                drag that lands where it started.
---   boundary   number|nil        how many rows are in the FIRST group. nil or 0 means one flat
---                                list, which is the common case; MultiMeters' Columns page is the
---                                other one, where shown columns may not be dragged among hidden.
---   handleIcon string|nil        resolved texture path for the handle art; nil falls back.
---   handleSize number|nil        the handle's hit width; its height is the row's. Defaults to
---                                `lib.ROW_BOX.HANDLE_W`, the gutter every list in the collection
---                                gives its handle -- row contents start beyond it.
---   handleInset number|nil       px from the parent's left edge. Defaults to 0.
---   handleColor table|nil        { r, g, b } for the handle at rest. Defaults to a neutral gray.
---   handleHoverColor table|nil   { r, g, b } under the pointer. Defaults to the collection's gold.
---   handleTooltip string|nil     one line shown on hover. No tooltip without it.
---   iconSize   number|nil        the art drawn inside it, defaults to 16.
---   rowBox     boolean|nil       false suppresses the bounded box behind every row. Defaults ON:
---                                the box is half of what makes a list read as blocks you can pick
---                                up (options-ui-§18), and a host that draws its own has to say so
---                                -- and should instead delete its own, or the two fills stack.
---   rowBoxInset number|nil       px the box is inset from the row frame's edges. Defaults to 0.
---   lineColor  table|nil         { r, g, b, a } for the insertion line; defaults to gold.
---   debug      function|nil      called as debug(fmt, ...) on grab and drop.
--- @return table controller
function lib.ReorderList(opts)
  opts = opts or {}

  local list = {
    stride     = opts.stride or 30,
    boundary   = opts.boundary,
    onMove     = opts.onMove,
    handleIcon = opts.handleIcon,
    color      = opts.lineColor or { 1, 0.82, 0, 0.9 },
    rowBox     = opts.rowBox ~= false,
    rows       = {},
    handles    = {},
    boxes      = {},
    dead       = false,
  }

  function list.say(fmt, ...)
    if opts.debug then opts.debug(fmt, ...) end
  end

  -- A GHOST LEFT SHOWN BY A PREVIOUS CONTROLLER IS NOT THIS ONE'S TO INHERIT. Hosts are asked to
  -- Cancel on repaint and both shipped ones do, but the ghost is a process-wide singleton and this
  -- is the one moment where "nothing is being dragged" is known for certain.
  if ghost then ghost:Hide() end

  --- Stop any drag in flight, put the chrome away, and give every handle AND every row box back.
  --- Idempotent.
  ---
  --- A HOST MUST CALL THIS BEFORE IT RENDERS ANYTHING, not merely before it rebuilds the list.
  --- Releasing a handle is what takes it off the host frame it was parented to, and that frame goes
  --- back into the host framework's pool the moment the host clears its page -- so a Cancel that
  --- runs after the page has started rebuilding is a Cancel that runs after some unrelated widget
  --- has already been handed the frame with a live handle still sitting on it.
  function list:Cancel()
    self.dead = true
    if ghost then ghost:Hide() end
    releaseLine(self)

    local row = self.dragging
    if row then
      if ghost and ghost.__row == row then ghost.__row = nil end
      if row.frame.SetAlpha then row.frame:SetAlpha(1) end
      row.startY = nil
    end
    self.dragging = nil

    -- Both ledgers, always, and in one place: a box left on a host's frame is the same bug a
    -- handle left on one is, and a Cancel that reclaimed only half of them would be a fix that
    -- looked complete.
    local handles = reclaim(self.handles, handlePool)
    local boxes   = reclaim(self.boxes, boxPool)
    if handles > 0 or boxes > 0 then
      self.say("released %d handles, %d boxes", handles, boxes)
    end
  end

  --- Build one handle. Called only when the free list is empty.
  local function newHandle()
    local handle = CreateFrame("Button", nil, atticFrame())
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")

    handle.art = handle:CreateTexture(nil, "ARTWORK")
    handle.art:SetPoint("CENTER", handle, "CENTER", 0, 0)

    -- READ AT FIRE TIME, never captured. A pooled handle outlives the controller that last used
    -- it, so a handler closing over either the row or the controller would drive a dead one --
    -- which is a drag that works once and then freezes.
    handle:SetScript("OnMouseDown", function(self) beginDrag(self.__row) end)
    handle:SetScript("OnDragStart", function(self) beginDrag(self.__row) end)
    handle:SetScript("OnMouseUp",   function(self) finishDrag(self.__row) end)
    handle:SetScript("OnDragStop",  function(self) finishDrag(self.__row) end)

    -- GOLD ON HOVER, so the handle says it is a control before you press it. The tint is the
    -- host's to choose and the default is the collection's gold; a host that wants its list's
    -- affordance to match its own palette says so, and one that says nothing matches everyone
    -- else's.
    handle:SetScript("OnEnter", function(self)
      local h = self.__hoverColor
      self.art:SetVertexColor(h[1], h[2], h[3])
      local tip = self.__tooltip
      if tip and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(tip, 1, 1, 1)
        GameTooltip:Show()
      end
    end)
    handle:SetScript("OnLeave", function(self)
      local c = self.__restColor
      self.art:SetVertexColor(c[1], c[2], c[3])
      if GameTooltip then GameTooltip:Hide() end
    end)

    return handle
  end

  --- Put a bounded box behind one row, from the free list or newly built.
  ---
  --- Its own function rather than six lines inside AddRow, because the frame LEVEL is the whole of
  --- it and the reason is not obvious: a child frame sits one level ABOVE its parent, so a box
  --- parented to the row and left at its natural level is a box painted over the row's own label
  --- and glyphs. One level below the row draws it behind everything the row puts on itself, which
  --- is the only place a background belongs. Clamped at zero, because a negative level is not a
  --- thing the client accepts.
  local function attachBox(parent, dimmed)
    local box = table.remove(boxPool)
    if not box then
      box = CreateFrame("Frame", nil, atticFrame())
      buildRowBox(box)
    end
    list.boxes[#list.boxes + 1] = box

    box:SetParent(parent)
    local level = parent.GetFrameLevel and parent:GetFrameLevel()
    if type(level) == "number" and box.SetFrameLevel then
      box:SetFrameLevel(math.max(level - 1, 0))
    end

    local inset = opts.rowBoxInset or 0
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT",     parent, "TOPLEFT",      inset, -inset)
    box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset,  inset)
    paintRowBox(box, dimmed)
    box:Show()
    return box
  end

  --- Register one row, in display order, and get back the handle that drags it.
  ---
  --- `spec.draggable = false` registers the row WITHOUT a handle. The row still counts for indices
  --- and still anchors the insertion line -- it is a place a drag can land, just not one a drag can
  --- start from. MultiMeters' hidden columns are that case: they have an order among themselves
  --- that nobody can act on, and offering a handle for it was offering a gesture with no meaning.
  ---
  --- `spec.dimmed = true` paints that row's box in the muted variant, for a row that is present but
  --- inert. The BOX is drawn for every registered row, draggable or not, and before the handle: a
  --- row you cannot pick up is still one of the blocks the list is made of, and a stack where only
  --- some rows have an edge reads as a rendering fault rather than as a rule.
  function list:AddRow(frame, spec)
    spec = spec or {}

    local row = {
      list           = list,
      frame          = frame,
      index          = #self.rows + 1,
      ghostText      = spec.ghostText,
      ghostIcon      = spec.ghostIcon,
      ghostIconColor = spec.ghostIconColor,
      ghostTextColor = spec.ghostTextColor,
      height         = spec.height,
    }
    self.rows[row.index] = row

    local parent = spec.parent or frame
    if self.rowBox then row.box = attachBox(parent, spec.dimmed) end

    if spec.draggable == false then return nil end

    local handle = table.remove(handlePool) or newHandle()
    self.handles[#self.handles + 1] = handle

    handle.__row        = row
    handle.__restColor  = opts.handleColor or { 0.7, 0.7, 0.7 }
    handle.__hoverColor = opts.handleHoverColor or { 1, 0.82, 0 }
    handle.__tooltip    = opts.handleTooltip

    handle:SetParent(parent)
    handle:SetSize(opts.handleSize or lib.ROW_BOX.HANDLE_W, spec.height or self.stride)
    handle:ClearAllPoints()
    handle:SetPoint("LEFT", parent, "LEFT", opts.handleInset or 0, 0)

    local size = opts.iconSize or 16
    handle.art:SetSize(size, size)
    handle.art:SetTexture(opts.handleIcon or HANDLE_FALLBACK)
    handle.art:SetVertexColor(handle.__restColor[1], handle.__restColor[2], handle.__restColor[3])
    handle:Show()

    row.handle = handle
    return handle
  end

  --- Name the frame the insertion line should live on -- normally the scroll's content frame, or
  --- whatever the rows share as a parent. Call it once, after the rows.
  ---
  --- It NAMES the frame and builds nothing: the line itself is taken from the library's free list
  --- when a drag starts and given back when it ends (minor 10), so nothing is left on a container
  --- the host is about to hand back to its framework's pool.
  function list:Finish(container)
    self.container = container
    self.say("painted %d rows, %d draggable, %d boxed, boundary=%s",
      #self.rows, #self.handles, #self.boxes, tostring(self.boundary or 0))
  end

  return list
end
