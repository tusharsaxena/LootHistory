-- LibKa0s-Options-1.0 — the page's CHROME: the tab strip, the page banner, the header block and
-- the secondary strip, plus the client art all four are drawn from.
--
-- Peeled out of OptionsWidgets.lua at v1.39.0 (issue #16), along the seam that file was already
-- built along rather than a new one: the chrome half and the widget half do not reach into each
-- other. Every module-scope local the members below use lives in the art block in this file, and
-- none of them was referenced from the makers, the id surface or the flow engine — the cut is
-- along a line that already existed.
--
-- Since minor 2 it also carries the combat lock's page chrome (options-ui-§2): the one event frame
-- the lock listens on, the cover over a page and the level that puts it above the strip. The lock's
-- logic -- the predicate, the dispatcher, the refusal -- is the shell's (Options.lua minor 22).
--
-- WHAT IS HERE AND WHAT IS NOT. Here: the geometry (`__layoutTabs`, `__tabPlacement`,
-- `__bannerBand`, `__tabBand`), the four release seams, the pooled tab button and its dress, the
-- wrap-and-place pass, and the four public surfaces — `TabStrip`, `PageBanner`, `PageHeader`,
-- `SubTabStrip`, and since minor 4 the tabbed page itself, `RenderTabbedSchema`, which moved here
-- from OptionsWidgets.lua and gained host tabs, a disabled notice and a chrome hook. Not here:
-- everything a schema row becomes. The tabbed page reaches the flow engine (`O.RenderRows`,
-- `O.TextRow`) through the instance, the same seam a host calls it through.
--
-- Part of the Options major rather than a major of its own, and guarded with the same multi-file
-- idiom as OptionsWidgets.lua, OptionsCompose.lua and OptionsScroll.lua: a strip from one vendored
-- copy paired with a shell from another would reserve a chrome band the shell anchors nothing to,
-- and nothing would say so.

local lib = LibStub and LibStub("LibKa0s-Options-1.0", true)
if not lib then return end

-- The same hard FLOOR OptionsWidgets.lua declares, and for the same reason: the tab strip's
-- buttons and the page's content panel come from LibKa0s-Pool-1.0 rather than being built on every
-- click (Options minor 14). Absent or too old, this file is absent rather than half-wired -- the
-- alternative, falling back to allocating per click, is precisely the leak that minor ended, and it
-- would fall back in silence. The floor is unreachable in a well-formed tree: Pool.lua and
-- Options.lua both gate on LibKa0s-Core-1.0 and Pool.lua loads first in LibKa0s.xml, so a payload
-- with no pool has no Options major to attach to either and `lib` above is already nil.
local Pool = LibStub and LibStub("LibKa0s-Pool-1.0", true)
local NEEDS_POOL = 1
if not Pool or (Pool.MINOR or 0) < NEEDS_POOL then return end

-- Minor 4: the banner's Dropdown, the header's frame and the divider's texture are reused or
-- released per page rather than minted on every full render (review finding LibKa0s-R-02).
-- The same minor takes O.RenderTabbedSchema in from OptionsWidgets.lua, with its `opts` argument,
-- and gives O.PageBanner its `action` button (AuraMaster-R-04).
local TABS_MINOR = 4
-- Paired on the SHELL's minor as well as this file's own — see OptionsScroll.lua for why the
-- file's own counter is not enough.
if lib.__tabsMinor and lib.__tabsMinor >= TABS_MINOR
  and lib.__tabsShellMinor == lib.MINOR then return end
lib.__tabsMinor      = TABS_MINOR
lib.__tabsShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.OptionsTabs = TABS_MINOR

local L = lib.LAYOUT

-- ── the combat cover's library half (minor 2) ──────────────────────────────────────────────
--
-- The lock itself -- the predicate, the dispatcher, the per-instance hooks -- is Options.lua's
-- (minor 22; read its note first). What lives here is the page chrome it draws with: the ONE event
-- frame the library listens on, and the arithmetic that puts a cover above everything a page draws.
--
-- The frame is created once for the process, hidden, and kept across a LibStub upgrade
-- (`lib.__combatFrame`); its handler looks `lib.__OnCombatEvent` up when the event arrives, so the
-- newest copy's dispatcher is the one that runs. The handler is re-set on every load that gets this
-- far, so an upgrade replaces an older copy's closure as well.
--
-- REGISTERED ONLY WHILE A PAGE IS SHOWN (minor 3). v1.46.0 registered PLAYER_REGEN_* at load, for
-- the life of the process: every host -- a stood-down one included, with no settings page open --
-- then owned two live registrations and a second REGEN dispatcher beside its own, which is what
-- each consumer's stand-down suite counts. Now a page's show registers both events and the last
-- page's hide lets go of them. A page shown mid-combat is locked off InCombatLockdown(), which is
-- all the predicate needs; the registration it makes is what hears the end of that combat.

local function combatEventFrame()
  if lib.__combatFrame then return lib.__combatFrame end
  if type(CreateFrame) ~= "function" then return nil end
  local f = CreateFrame("Frame")
  if not f then return nil end
  f:Hide()
  lib.__combatFrame = f
  return f
end

-- Every ctx whose page is on screen, across every host. Weak-keyed: a ctx nobody holds is gone.
lib.__shownPages = lib.__shownPages or setmetatable({}, { __mode = "k" })

local function onScreen(ctx)
  local panel = ctx.panel
  if not panel then return false end
  local probe = panel.IsVisible or panel.IsShown
  return probe == nil or probe(panel) and true or false
end

--- Drop every page no longer on screen, then register the two events if any page is left, or let
--- go of them -- and of PLAYER_REGEN_DISABLED's flag, which nothing will clear once unregistered --
--- if none is. The predicate still answers InCombatLockdown() for a page shown later.
function lib.__syncCombatEvents()
  local f = lib.__combatFrame
  for ctx in pairs(lib.__shownPages) do
    if not onScreen(ctx) then lib.__shownPages[ctx] = nil end
  end
  local any = next(lib.__shownPages) ~= nil
  if f then
    if any then
      f:RegisterEvent("PLAYER_REGEN_DISABLED")
      f:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
      f:UnregisterEvent("PLAYER_REGEN_DISABLED")
      f:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
  end
  if not any then lib.__combatLocked = false end
end

--- The dispatcher (Options minor 22; here, beside the registration, from minor 3). The events are
--- first re-synced to the pages on screen: with none left the library lets go of them and of the
--- flag and does nothing else, so an event that reaches it anyway -- a stand-down suite fires every
--- event at every frame that ever owned one -- draws, renders and prints nothing. Otherwise
--- PLAYER_REGEN_DISABLED locks, PLAYER_REGEN_ENABLED unlocks, and every host's hook runs, each
--- pcall'd so one host's page cannot keep another's cover up.
function lib.__OnCombatEvent(event)
  lib.__syncCombatEvents()
  if next(lib.__shownPages) == nil then return end
  if event == "PLAYER_REGEN_DISABLED" then
    lib.__combatLocked = true
  elseif event == "PLAYER_REGEN_ENABLED" then
    lib.__combatLocked = false
  else
    return
  end
  local locked = lib.__combatLocked
  for hook in pairs(lib.__combatHooks) do pcall(hook, locked) end
end

--- A page came on screen: watch combat. Asked of the page rather than taken from the OnShow that
--- called this, so a show that did not leave the page on screen registers nothing.
function lib.__pageShown(ctx)
  if not onScreen(ctx) then return end
  lib.__shownPages[ctx] = true
  local f = lib.__combatFrame
  if f then
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
  end
end

--- A page went off screen: let go of combat if it was the last.
function lib.__pageHidden(ctx)
  lib.__shownPages[ctx] = nil
  lib.__syncCombatEvents()
end

do
  local f = combatEventFrame()
  if f then
    f:SetScript("OnEvent", function(_, event)
      local dispatch = lib.__OnCombatEvent
      if type(dispatch) == "function" then dispatch(event) end
    end)
  end
  -- An older copy (v1.46.0) registered for good at load; this lets go unless a page is shown.
  lib.__syncCombatEvents()
end

-- The cover's frame level: the deepest level under the page, plus one, and never less than
-- COVER_LEVEL_FLOOR above the page itself -- the floor covers a descendant whose level moves after
-- the walk (an AceGUI widget that raises its own frame). Capped at the client's frame-level
-- ceiling. A walk rather than a constant because the tab buttons already sit two levels above
-- the chrome frame they hang off (newTabButton's +1), and AceGUI nests a scroll's rows several
-- levels deep: any fixed small offset is a number some page's furniture will one day draw over.
local COVER_LEVEL_FLOOR = 100
local MAX_FRAME_LEVEL = 10000

local function levelOf(frame)
  local level = frame.GetFrameLevel and frame:GetFrameLevel()
  return type(level) == "number" and level or 0
end

local function deepestLevel(frame, skip, seen)
  local top = levelOf(frame)
  if type(frame.GetChildren) ~= "function" then return top end
  for _, kid in ipairs({ frame:GetChildren() }) do
    if type(kid) == "table" and kid ~= skip and kid ~= frame and not seen[kid] then
      seen[kid] = true
      local level = deepestLevel(kid, skip, seen)
      if level > top then top = level end
    end
  end
  return top
end

--- The level `cover` takes over `panel`, computed when the cover goes up over a page on screen.
--- @return number
function lib.__coverLevel(panel, cover)
  local floor = levelOf(panel) + COVER_LEVEL_FLOOR
  local want = math.max(floor, deepestLevel(panel, cover, {}) + 1)
  return math.min(want, MAX_FRAME_LEVEL)
end

--- Does `frame` sit under `ancestor`? A bounded walk up GetParent.
--- @return boolean
function lib.__descendsFrom(frame, ancestor)
  local f = frame
  for _ = 1, 64 do
    if f == nil then return false end
    if f == ancestor then return true end
    local parent = f.GetParent and f:GetParent()
    if parent == f then return false end
    f = parent
  end
  return false
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
--- Drawn only by TabStrip, so an UNTABBED page is
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
--- chrome's full width. Listed in the BANNER's own ledger (`ctx.__chromeKids`), not the strip's:
--- only a full page render redraws the banner, so a tab click alone must never touch this
--- texture the way it touches `ctx.__tabKids`.
---
--- ONE TEXTURE PER PAGE (minor 4), built on the first render that draws a rule and kept on the
--- ctx as `ctx.__ruleTex`. Until minor 4 every full render created a fresh texture and the release
--- hid it and called SetParent(nil) on it: the client never destroys a region, so that was one
--- texture per render for the life of the session, and SetParent(nil) on a Region is not a call
--- the client promises to honor. The release now only hides it, and this re-anchors and shows it.
local function drawChromeDivider(ctx, rawBannerHeight)
  local tex = ctx.__ruleTex
  if not tex then
    tex = edgeTexture(ctx.chrome, "ARTWORK", CHROME_RULE_COLOR)
    if not tex then return end
    ctx.__ruleTex = tex
  end
  local y = -(rawBannerHeight + L.CHROME_DIVIDER_GAP_TOP)
  tex:SetPoint("TOPLEFT",  ctx.chrome, "TOPLEFT",  0, y)
  tex:SetPoint("TOPRIGHT", ctx.chrome, "TOPRIGHT", 0, y)
  tex:SetHeight(L.CHROME_DIVIDER_H)
  tex:Show()
  ctx.__chromeKids[#ctx.__chromeKids + 1] = tex
end

--- Attach the chrome surfaces to one instance, beside the widget makers and the flow engine.
---
--- Takes the descriptor since minor 4, for ONE field: `d.rowsForPage`, which the tabbed page reads.
--- Nothing here reads a setting or writes one; the host callbacks it calls are the ones its own
--- specs carry (`onSelect`, `onClick`, `build`, and the tabbed page's `opts` hooks). Through minor
--- 3 it took no descriptor at all, because it had no page to render.
function lib.__AttachTabs(O, d)
  -- The SHELL's sink (`O.__print`), exactly as OptionsWidgets.lua takes it and for the reason that
  -- file records: a second sink built from the descriptor would discard every diagnostic in this
  -- file for any host relying on the library's own chat-frame fallback -- which is the fallback
  -- that exists precisely so these lines stay visible. This is called from the end of lib:New, so
  -- `O.__print` is always there; the `or` arm is for a caller that attached the chrome to some
  -- other table, which should fall silent rather than raise.
  local print = O.__print or function() end

  -- ── the combat cover (minor 2) ──────────────────────────────────────────────────────────

  --- The cover over one page (Options.lua's CreatePanel calls this, out of combat): a plain,
  --- non-secure Frame over the whole canvas -- header band, chrome and tab strip included -- that
  --- takes the mouse and the wheel, so nothing under it can be clicked, dragged or scrolled, with a
  --- dim and one centered gray line. Hidden until the lock puts it up. It never touches keyboard
  --- propagation: a frame that swallowed keys would take the Escape that closes the window.
  function O.__buildCover(panel)
    local cover = CreateFrame("Frame", nil, panel)
    cover:SetAllPoints(panel)
    cover:EnableMouse(true)
    cover:EnableMouseWheel(true)
    cover:SetScript("OnMouseWheel", function() end)
    local dim = cover:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints(cover)
    dim:SetColorTexture(0, 0, 0, 0.6)
    local line = cover:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    line:SetPoint("CENTER", cover, "CENTER", 0, 0)
    line:SetTextColor(0.667, 0.667, 0.667)
    line:SetText(lib.STRINGS.COMBAT_LOCKED)
    -- Recorded as a plain field too, as panel.titleText is: a headless FontString cannot be read.
    cover.__text = lib.STRINGS.COMBAT_LOCKED
    -- HELD by the cover (minor 3), not left to locals. The client keeps a region alive through its
    -- parent, but a harness whose CreateTexture / CreateFontString hand back tracked objects does
    -- not: two unreferenced regions per page were garbage that a collection could take between two
    -- counts of what is on screen, and a stand-down suite read that as a frame appearing or going.
    cover.__dim, cover.__line = dim, line
    cover:Hide()
    return cover
  end

  --- At the start of combat, close an AceGUI pullout the player left open on one of `panels` (the
  --- instance's pages). AceGUI marks an open dropdown as its focused widget, and ClearFocus closes
  --- the pullout -- which is parented to UIParent, so the cover cannot reach it. Only a widget
  --- under one of these pages: another addon's dropdown is not the library's to close. A color
  --- picker is Blizzard's frame and is left alone; the write seam refuses what it commits.
  function O.__releaseOwnedFocus(panels)
    local AceGUI = O.AceGUI
    local w = AceGUI and AceGUI.FocusedWidget
    if not (w and w.frame and type(AceGUI.ClearFocus) == "function") then return end
    for _, ctx in ipairs(panels) do
      if lib.__descendsFrom(w.frame, ctx.panel) then
        pcall(AceGUI.ClearFocus, AceGUI)
        return
      end
    end
  end

  --- The refusal every control in this file asks (minor 2): Options.lua's, when the shell has it.
  local function refused()
    return O.__combatRefused ~= nil and O.__combatRefused()
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

  --- Hide, unparent and forget every widget in one of a page's ledgers. Since minor 4 only the
  --- secondary strip's buttons go through here: they are raw Buttons no pool will hand out again.
  --- The chrome band's three kinds of furniture are each released by what owns them, in
  --- releaseChrome below.
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

  --- Give the previous render's banner Dropdown back to AceGUI (minor 4).
  ---
  --- Called at the END of the render that replaces it, never from releaseChrome, and that is the
  --- whole reason the widget is held aside as `ctx.__staleBanner` rather than released on the way
  --- in. A banner's selection is a change of subject, so the render replacing it very often runs
  --- INSIDE its OnValueChanged callback; released on the way in, it is back in AceGUI's pool in
  --- time for this same render's `Create("Dropdown")` -- ours, or one a PageHeader builder makes
  --- -- to hand it straight back out, re-initialized, with its own callback still on the stack.
  ---
  --- The banner's action Button (minor 4) is held and released the same way, beside it: a create
  --- act re-renders the page from inside the button's own OnClick.
  local function releaseStaleBanner(ctx)
    local w, b = ctx.__staleBanner, ctx.__staleBannerButton
    ctx.__staleBanner, ctx.__staleBannerButton = nil, nil
    local AceGUI = O.AceGUI
    if not (AceGUI and AceGUI.Release) then return end
    if w then AceGUI:Release(w) end
    if b then AceGUI:Release(b) end
  end

  --- Release everything a page parked in its chrome band -- the banner AND the strip.
  ---
  --- Two seams, one release, because the two have different LIFETIMES: a tab click redraws the
  --- strip alone and releases its own furniture, while only a full page render redraws the banner.
  --- Draining both here is what keeps the page-wide teardown total without making the strip's
  --- ledger a second copy of it -- when TabStrip appended to both, __chromeKids grew by one entry
  --- per tab click, forever, holding buttons already hidden and unparented.
  ---
  --- BY OWNER, NOT BY LEDGER (minor 4). Until minor 4 this hid and unparented whatever
  --- `__chromeKids` listed and forgot it, so every full render of a banner or header page left one
  --- Dropdown or raw Frame and one texture behind for good (review finding LibKa0s-R-02). Each of
  --- the three now goes back to what owns it: the banner's Dropdown to AceGUI (hidden now, released
  --- by releaseStaleBanner once the replacement is drawn), the header's frame to the page's
  --- `ctx.__headerPool`, and the divider's one texture hidden in place. `__chromeKids` stays as the
  --- ledger a suite reads to ask what this render drew; it no longer owns a release.
  local function releaseChrome(ctx)
    local banner = ctx.__bannerDropdown
    if banner then
      -- Two releases with no render between them: the older stale widget has nobody left to wait
      -- for, and holding only one slot is what keeps this from growing a list of its own.
      releaseStaleBanner(ctx)
      if banner.frame then banner.frame:Hide() end
      ctx.__staleBanner, ctx.__bannerDropdown = banner, nil
      local button = ctx.__bannerButton
      if button and button.frame then button.frame:Hide() end
      ctx.__staleBannerButton, ctx.__bannerButton = button, nil
    end
    if ctx.__headerPool then Pool.ReleaseAll(ctx.__headerPool) end
    if ctx.__ruleTex then ctx.__ruleTex:Hide() end
    ctx.__chromeKids = {}
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
      -- Refused in combat (minor 2): options-ui-§13 as of the standard's v2.60.0 -- a tab switch
      -- is a structural re-render, and the lock covers the strip. The library owns the refusal;
      -- a host adds no tab guard of its own.
      if refused() then return end
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

  -- The banner's action button (minor 4). AceGUI's labeled Dropdown anchors its CONTROL 14px below
  -- its frame's top (AceGUIWidget-DropDown's SetLabel), and an unlabeled one at 0; the button levels
  -- with the control, not the label. 24 is AceGUI's Button frame height, and the pair gap is half
  -- the gutter between the band's two halves.
  local ACTION_Y_LABELED = 14
  local ACTION_H         = 24
  local ACTION_PAIR_GAP  = 4

  --- The action Button in the banner's right half, or nil when the spec has none.
  local function drawBannerAction(ctx, action, labeled)
    if type(action) ~= "table" then return nil end
    local btn = O.AceGUI:Create("Button")
    ctx.__bannerButton = btn
    btn:SetText(action.text or "")
    btn:SetCallback("OnClick", function()
      -- A create act is a change of subject, so it is refused in combat as the picker is.
      if refused() then return end
      if type(action.onClick) ~= "function" then return end
      local ok, err = pcall(action.onClick)
      if not ok then print(lib.STRINGS.BUTTON_FAILED:format(tostring(err))) end
    end)
    if btn.frame then
      local y = labeled and -ACTION_Y_LABELED or 0
      btn.frame:SetParent(ctx.chrome)
      btn.frame:ClearAllPoints()
      btn.frame:SetPoint("TOPLEFT",  ctx.chrome, "TOP",      ACTION_PAIR_GAP, y)
      btn.frame:SetPoint("TOPRIGHT", ctx.chrome, "TOPRIGHT", 0,               y)
      btn.frame:SetHeight(ACTION_H)
      btn.frame:Show()
      ctx.__chromeKids[#ctx.__chromeKids + 1] = btn.frame
    end
    -- Guarded for the reason the picker's tooltip is: O.AttachTooltip is the widget half's.
    if O.AttachTooltip then O.AttachTooltip(btn, action.text, action.tooltip) end
    return btn
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
  --- had one deletes it. Two controls over one piece of session state is a synchronization
  --- problem the design invented and would then own forever -- here there is one value, read at
  --- render time, and the structural refresh the write already triggers repaints every panel.
  ---
  --- Draw it BEFORE the strip. It records its own share of the band in `ctx.__bannerHeight` --
  --- widened by O.__bannerBand to include the small gap, the hairline rule and the second gap
  --- that separate the banner from the strip (options-ui-§14) -- which TabStrip's placeTabs adds
  --- to the rows it reserves for itself; called the other way round, the strip's reservation
  --- would not know about it.
  ---
  --- `spec` = { label, list, order, value, onSelect, tooltip, action }. Returns the dropdown, or nil
  --- having drawn nothing, and the action's Button as a second value when there is one.
  ---
  --- `action` (minor 4) = { text, tooltip, onClick }: a Button in the band's RIGHT half, level with
  --- the dropdown's control, and the picker takes the left half. It is the picker+create band
  --- options-ui-§14 describes -- the act that makes a new subject, beside the choice of subject --
  --- which a host otherwise builds inside PageHeader's frame by hand. `onClick` is pcall'd, and
  --- refused in combat as the picker's selection is.
  function O.PageBanner(ctx, spec)
    if not (ctx and ctx.chrome and spec) then return nil end
    local AceGUI = O.AceGUI
    if not AceGUI then return nil end

    releaseChrome(ctx)

    -- Held on the ctx under a LIBRARY-PRIVATE key (minor 4), so the next releaseChrome can give it
    -- back. Not `ctx.__bannerWidget`: hosts write that field themselves -- to this dropdown, to a
    -- picker of their own built inside PageHeader's frame, and to nil before a render -- and a
    -- release keyed on it would either lose this widget or release one the host owns.
    local dd = AceGUI:Create("Dropdown")
    ctx.__bannerDropdown = dd
    local btn = drawBannerAction(ctx, spec.action, (spec.label or "") ~= "")
    -- Both replacements exist, so neither old widget can be handed back to this render.
    releaseStaleBanner(ctx)
    dd:SetLabel(spec.label or "")
    dd:SetList(spec.list or {}, spec.order)
    dd:SetValue(spec.value)
    dd:SetCallback("OnValueChanged", function(_, _, key)
      -- pcall'd for the reason every host callback in this file is: a selection handler reaches
      -- into live addon state, and a raise inside AceGUI's own dispatch takes the click handling
      -- of every widget on the frame with it. Refused in combat (minor 2), putting the
      -- dropdown back: a banner's selection is a change of subject, a structural re-render.
      if refused() then
        dd:SetValue(spec.value)
        return
      end
      if spec.onSelect then pcall(spec.onSelect, key) end
    end)
    if dd.frame then
      dd.frame:SetParent(ctx.chrome)
      dd.frame:ClearAllPoints()
      dd.frame:SetPoint("TOPLEFT",  ctx.chrome, "TOPLEFT",  0, 0)
      if btn then
        dd.frame:SetPoint("TOPRIGHT", ctx.chrome, "TOP", -ACTION_PAIR_GAP, 0)
      else
        dd.frame:SetPoint("TOPRIGHT", ctx.chrome, "TOPRIGHT", 0, 0)
      end
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
    -- Guarded, and it is the only call in this file that crosses to the widget half.
    -- O.AttachTooltip is OptionsWidgets.lua's, and the two files are paired on the shell's minor
    -- rather than on each other's -- so a vendored copy carrying one and not the other is a state
    -- LibStub cannot detect. A banner with no tooltip is a smaller failure than a banner that
    -- raises while drawing.
    if O.AttachTooltip then O.AttachTooltip(dd, spec.label, spec.tooltip) end

    return dd, btn
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
  --- A page draws AT MOST ONE chrome block: this and O.PageBanner both release the chrome band and
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

    -- ONE FRAME PER PAGE (minor 4), from a pool of one held on the ctx, for the reason
    -- drawContentPanel gives for its panel: until minor 4 this was a CreateFrame per render, and
    -- the client never destroys a frame. The pool hides and parks it; the parent is the page's own
    -- chrome, which outlives every render. What the host's builder put INSIDE it is the host's to
    -- release, as it always was -- the frame coming back is the same one, so a host that
    -- creates raw regions into it on every build stacks them, where AceGUI widgets it Releases do not.
    ctx.__headerPool = ctx.__headerPool or Pool.New()
    local chrome = ctx.chrome
    local frame = Pool.Acquire(ctx.__headerPool, function() return CreateFrame("Frame", nil, chrome) end)
    frame:ClearAllPoints()
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
    -- After the builder, not before: a builder that makes a Dropdown of its own must not be handed
    -- back the banner's, which may still be running its callback (see releaseStaleBanner).
    releaseStaleBanner(ctx)

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

  -- ── the tabbed page (minor 4, moved from OptionsWidgets.lua) ─────────────────────────────────
  -- Only over a flow engine: the widget half attaches first and leaves an untabbed fallback, which
  -- this replaces. Without that half, one that raised on its first O.RenderRows is worse than none.
  if not (d and O.RenderRows) then return end

  local NO_OPTS = {}

  --- The page's groups in declaration order, and each group's rows.
  local function partition(rows)
    local groups, byGroup = {}, {}
    for _, row in ipairs(rows) do
      local g = row.group
      if g ~= nil then
        if not byGroup[g] then byGroup[g], groups[#groups + 1] = {}, g end
        byGroup[g][#byGroup[g] + 1] = row
      end
    end
    return groups, byGroup
  end

  --- Put a host tab ahead of the tab `before` names, or last when this render draws no such tab.
  local function placeTab(tabs, entry, before)
    for i, t in ipairs(tabs) do
      if before ~= nil and t.key == before then return table.insert(tabs, i, entry) end
    end
    tabs[#tabs + 1] = entry
  end

  --- The strip: one tab per group, then the host's tabs. A host tab keyed by a group takes that
  --- group's place (and may relabel it) rather than adding a second tab. An entry with no key or
  --- no render function is not a tab.
  local function collectTabs(groups, byGroup, hostTabs)
    local tabs, index, bespoke = {}, {}, {}
    for i, name in ipairs(groups) do
      tabs[i] = { key = name, label = name }
      index[name] = tabs[i]
    end
    for _, t in ipairs(type(hostTabs) == "table" and hostTabs or NO_OPTS) do
      if type(t) == "table" and t.key ~= nil and type(t.render) == "function" then
        bespoke[t.key] = t
        local own = index[t.key]
        if own then
          own.label, own.tooltip = t.label or own.label, t.tooltip
        elseif not byGroup[t.key] then
          local entry = { key = t.key, label = t.label or tostring(t.key), tooltip = t.tooltip }
          index[t.key] = entry
          placeTab(tabs, entry, t.before)
        end
      end
    end
    return tabs, bespoke
  end

  --- Keep the active tab when this render draws it, else heal to the first. A pointer at a tab
  --- the page no longer has would render an empty page under a strip.
  local function settleActiveTab(ctx, tabs)
    for _, t in ipairs(tabs) do if t.key == ctx.activeTab then return end end
    ctx.activeTab = tabs[1].key
  end

  --- `disabledFor(cfg)`, guarded: a raising predicate reads as enabled, as a row's disabledIf does.
  local function pageDisabled(opts)
    if type(opts.disabledFor) ~= "function" then return false end
    local ok, answer = pcall(opts.disabledFor, opts.cfg)
    return (ok and answer) and true or false
  end

  --- The notice over a page drawn disabled, and a row gap under it. A string, or a function of
  --- `opts.cfg` answering one; the host colors it with an escape sequence if it wants a color.
  local function drawDisabledNotice(ctx, opts)
    local notice = opts.disabledNotice
    if type(notice) == "function" then
      local ok, text = pcall(notice, opts.cfg)
      notice = ok and text or nil
    end
    if type(notice) ~= "string" or notice == "" or not O.TextRow then return end
    O.TextRow(ctx, notice, { fontObject = "GameFontHighlightSmall" })
    local scroll = O.EnsureScroll(ctx)
    if scroll and O.AddSpacer then O.AddSpacer(scroll, L.ROW_VSPACER) end
  end

  --- A host tab's render under the page's disable, as RenderRows' `opts.disabled` holds it: every
  --- maker reads `ctx.__renderDisabled`, restored on the way out, a raise included.
  local function renderHostTab(ctx, tab, rows, disabled)
    local outer = ctx.__renderDisabled
    ctx.__renderDisabled = (disabled or outer) and true or nil
    local ok, err = pcall(tab.render, ctx, rows)
    ctx.__renderDisabled = outer
    if not ok then error(err, 0) end
    local scroll = O.EnsureScroll(ctx)
    if scroll and scroll.DoLayout then scroll:DoLayout() end
  end

  --- Everything under the strip: `chrome`, the disabled notice, then the tab's content.
  local function renderBody(ctx, opts, tab, rows, flow)
    local disabled = pageDisabled(opts)
    if type(opts.chrome) == "function" then opts.chrome(ctx) end
    if disabled then drawDisabledNotice(ctx, opts) end
    if tab then
      renderHostTab(ctx, tab, rows, disabled)
    elseif rows then
      O.RenderRows(ctx, rows, flow.afterGroup, flow.pairWith,
        { noHeadings = flow.noHeadings, disabled = disabled })
    end
  end

  --- Render one page as a tab strip over its sections (options-ui-§13). The partition is by
  --- `group`, IN DECLARATION ORDER, one tab per group, and no second field names a tab: a tab list
  --- declared apart from the rows goes stale the first time a section is renamed (options-ui-§1).
  --- Returns the group names in tab order and (minor 4) every drawn tab's key in strip order.
  ---
  --- A ONE-GROUP PAGE DRAWS ITS STRIP TOO (OptionsWidgets minor 13): a page that lost its strip is
  --- the one that looks broken, and the tab is the only thing naming the group once `noHeadings`
  --- has suppressed the heading. No opt-out flag. A page with NO groups and no host tabs has nothing
  --- to name a tab with: an authoring defect (anti-patterns #69), REPORTED and rendered untabbed.
  --- With no AceGUI it reports an empty tab list and draws nothing.
  ---
  --- `opts` (minor 4, every field optional), for the pages five hosts hand-built around this:
  ---   tabs            { { key, label, tooltip, before, render = function(ctx, rows) } } host
  ---                   tabs drawn by their own callback. One keyed by a group takes that group's
  ---                   place in the strip and is handed the group's rows; any other is placed
  ---                   ahead of the tab `before` names, or last, and is handed nil.
  ---   cfg             the subject this render edits, handed to `disabledFor` and `disabledNotice`.
  ---   disabledFor     function(cfg) answering true to draw the page disabled: `disabledNotice`
  ---                   above the rows, and every row (a host tab's widgets through
  ---                   `ctx.__renderDisabled`) disabled. The rows are still drawn.
  ---   disabledNotice  a string, or function(cfg) answering one, drawn in the small font.
  ---   chrome          function(ctx), called once per render after the strip and before the
  ---                   notice and the rows: a line that belongs above every tab. A banner is not
  ---                   chrome here -- draw it before calling this, as PageBanner says.
  --- A tab click re-renders with the same `opts`.
  function O.RenderTabbedSchema(ctx, pageKey, afterGroup, pairWith, opts)
    opts = type(opts) == "table" and opts or NO_OPTS
    local rows = d.rowsForPage(pageKey, ctx.unit) or {}
    local groups, byGroup = partition(rows)
    if not O.AceGUI then return {}, {} end

    local tabs, bespoke = collectTabs(groups, byGroup, opts.tabs)
    if #tabs == 0 then
      print(lib.STRINGS.NO_GROUPS:format(tostring(pageKey)))
      renderBody(ctx, opts, nil, rows, { afterGroup = afterGroup, pairWith = pairWith })
      return groups, {}
    end
    settleActiveTab(ctx, tabs)

    O.TabStrip(ctx, {
      tabs  = tabs,
      value = ctx.activeTab,
      onSelect = function(key)
        if key == ctx.activeTab then return end
        ctx.activeTab = key
        -- The re-render a change of subject takes. In combat the tab button refuses the click.
        O.ClearScroll(ctx)
        O.RenderTabbedSchema(ctx, pageKey, afterGroup, pairWith, opts)
      end,
    })

    local active = ctx.activeTab
    renderBody(ctx, opts, bespoke[active], byGroup[active],
      { afterGroup = afterGroup, pairWith = pairWith, noHeadings = true })

    local keys = {}
    for i, t in ipairs(tabs) do keys[i] = t.key end
    return groups, keys
  end
end
