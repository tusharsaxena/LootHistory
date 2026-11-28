local addonName, NS = ...
NS.Browser = NS.Browser or {}
local B = NS.Browser
local frame
local print = NS.Print   -- secret-safe, [LH]-prefixed shared printer (events-frames-taint-§8)
local L = NS.L           -- locales/enUS.lua: the test-mode badge and strip strings route through it

-- The window GEOMETRY this addon owns: every height the layout is measured from. No color is here.
-- The window's look is the player's skin (the Skin tab; core/SkinSetup.lua's NS.Skin, over
-- LibKa0s-Skin-1.0): the edge, the title bar, the close control, the tab labels and
-- underline, the bar's buttons and the footer all read its tokens and follow a skin switch with no
-- reload. Ka0s Default is the look this window always had.
local SKIN = {
  titleBarH   = 30,
  tabStripH   = 26,
  contentGap  = 14,    -- vertical spacing between the tab strip and the pane content
  defaultH    = 700,   -- opening height — shows the full Insights view without scrolling
  minH        = 460,   -- minimum height (content scrolls below this)
}
B.SKIN = SKIN

-- ── Toolbar geometry (single source of truth) ──────────────────────────────────
-- The filter bar's controls are MEASURED, not fixed: modules/BrowserFilterBar.lua sizes every
-- control from the widest label it can show, so no label wraps, and B:ToolbarSpan answers the span
-- those widths need (row 2's eight dropdowns, or row 1's Group + Direction + a minimum Search if
-- that is ever wider; the floor widths until the bar is built). The window floor adds an 8px gap,
-- Export's EXPORT_MIN and the 12px pane margins, so at the toolbar floor row 2 fits exactly at its
-- base widths. Wider than that, B:LayoutFilterBar scales every row-2 control by one ratio so the
-- bar always ends 6px in from the right border, as it starts on the left (P6 Task 3).
local EXPORT_MIN  = 120                                                    -- Export never narrower than this
B._EXPORT_MIN = EXPORT_MIN   -- Export's base width in the filter bar's layout
local BAR_INSET   = 6        -- the filter bar host's left and right inset (EnsureFrame)

-- Minimum (and default-open) window width: the wider of the column-derived table floor
-- (BrowserTable:MinFrameWidth) and the toolbar-fit floor (the dropdown span + an 8px gap + a
-- minimum Export + 12px pane margins). Shared by EnsureFrame and the resize grip.
function B:MinWidth()
  local colW = (NS.BrowserTable and NS.BrowserTable.MinFrameWidth and NS.BrowserTable:MinFrameWidth())
    or 822
  return math.max(colW, self:ToolbarSpan() + 8 + EXPORT_MIN + 2 * BAR_INSET)
end

-- Wear the shared Ka0s window edge. Every value this used to spell out — the WHITE8x8 backdrop at
-- edgeSize 1 with 1px insets, the {0.06,0.06,0.08,0.92} fill, the black border, the
-- {0.24,0.24,0.27,0.85} inner highlight and divider, the {1,0.82,0} title — is Core.SKIN, byte for
-- byte, and Core.ApplySkin makes the same calls in the same order, including building the
-- inner-border child exactly once. Delegated rather than restated so a re-skin lands on every Ka0s
-- window at once (standalone-windows).
--
-- NS.ApplySkin is core/CoreSetup.lua's seam: the library's on a working install, and that file's
-- own pre-library copy when libs/LibKa0s is missing, so the window wears the same edge either way.
-- Guarded anyway, because this is the only file that skins a frame this addon owns. The seam is
-- kept as a method because four windows reach the edge through it — EnsureFrame here, both export
-- copy windows (modules/Export.lua) and the debug console (core/DebugLogSetup.lua's applySkin).
-- `skin` is forwarded even though nothing in this addon passes one today. A forwarder must carry
-- every argument its target takes (anti-patterns #64): lib.ApplySkin(frame, skin) accepts an
-- override table, and a one-argument passthrough drops it silently -- the call still runs, the
-- window still gets an edge, and the override simply never arrives.
--
-- With no `skin` the frame goes to the skin's Shell (NS.Skin.Shell, LibKa0s-Skin-1.0): the same
-- Core.ApplySkin call on Ka0s Default, object for object, and the player's skin otherwise; the
-- frame is recorded for this addon's owner, so a skin switch repaints it live. `opts` is Shell's
-- (`noTopBar` for a window whose title bar paints its own fill). No window here asks for Shell's
-- `bottomBar`: the History footer is the library's W.Footer, which has no fill (AD-89-LH).
-- A caller's own `skin` table still reaches NS.ApplySkin, as before: it overrides the skin.
-- Degraded, NS.Skin.Shell is core/SkinSetup.lua's, which routes to NS.ApplySkin.
function B:ApplySkin(f, skin, opts)
  if skin ~= nil then
    if NS.ApplySkin then NS.ApplySkin(f, skin) end
    return
  end
  if NS.Skin then NS.Skin.Shell(f, opts) elseif NS.ApplySkin then NS.ApplySkin(f) end
end

-- The close control every window this addon owns wears -- the History browser, the export modal
-- and the export copy window. It is Core's, reached through core/CoreSetup.lua's NS.MakeCloseButton
-- so the addon folder name is passed and the shared `close` mark is what draws; on an install
-- missing LibKa0s the same seam answers with the 24x24 class-colored multiplication sign this
-- addon drew before, which is the degraded look and not a second design.
--
-- Kept as a method rather than retired because three call sites and docs/browser.md name it, and
-- because it is the one place to change if this addon ever wants a different control again.
function B:MakeCloseButton(parent, onClick)
  if not NS.MakeCloseButton then return nil end
  return NS.MakeCloseButton(parent, onClick)
end

-- The title-bar marks of every window this addon owns, the History browser and the export modal
-- (AD-86-LH, LibKa0s#86; standalone-windows *Title-bar controls*, standard v2.113.0): W.HeaderButtons
-- through core/WidgetsSetup.lua's NS.MakeHeaderButtons, left to right settings · close (the close alone on a companion), the close
-- still B:MakeCloseButton's (the one wrapper) and the settings mark opening this addon's settings
-- through the launcher's registered opener. `companion` true marks a companion window (the export
-- modal, which belongs to the History browser): W.HeaderButtons' `companion = true` (WidgetsHeader 2,
-- LibKa0s v1.112.0) builds the close alone, with no settings mark and no waiver reason
-- (standalone-windows, *Settings is on every window but a companion*, standard v2.119.0; FB-LH-01).
-- `extras` are W.HeaderButtons' own, left of the settings mark: the History window passes its lock
-- (AF-HDR-LH). On a degraded install (no HeaderButtons) the close alone, 6 px in from the bar's
-- right, as before. Sets `win.closeButton`, `win.settingsButton` (nil on a companion),
-- `win.lockButton` (the `lock` extra, if any) and answers the S.Header `right` list (outermost first).
function B:MakeTitleMarks(bar, win, onClose, companion, extras)
  local hb = NS.MakeHeaderButtons and NS.MakeHeaderButtons(bar, {
    close = onClose, frame = win, companion = companion == true or nil, extras = extras,
    makeClose = function(parent, onClick) return B:MakeCloseButton(parent, onClick) end,
  })
  if hb then
    win.closeButton, win.settingsButton = hb.close, hb.settings
    win.lockButton = hb.extras and hb.extras.lock
    return hb.right
  end
  local close = B:MakeCloseButton(bar, onClose)
  if close then close:SetPoint("RIGHT", bar, "RIGHT", -6, 0) end
  win.closeButton = close
  return { close }
end

-- The History window's lock mark (AF-HDR-LH; standalone-windows *Which marks a window owes*, standard
-- v2.115.0: a primary window's header carries close, settings and lock). The catalog's `lock` while
-- locked and `unlock` while not, its tooltip what a click does. The click runs `/lh unlock` or
-- `/lh lock`, the verbs the launcher's Locked entry also runs, and they write `settings.locked`
-- through the single seam; that row's onChange (SETTINGS_CHANGED) repaints the mark through
-- B:OnSettingsChanged, as B:AdoptProfile does on a profile switch. W.HeaderButtons evaluates `icon`
-- and `tip` once, at build, so the repaint is the host's.
local function lockFace()
  if B:IsLocked() then return "lock", NS.L["Unlock the window"] end
  return "unlock", NS.L["Lock the window"]
end

--- The History window's `lock` extra, painted for the lock as it stands now.
local function lockExtra()
  local icon, tip = lockFace()
  return { key = "lock", icon = icon, tip = tip, onClick = function() B:ToggleLock() end }
end

--- A fresh `lock` extra for another window of this addon that owes the mark (the farm panel, #39):
--- the same art, tooltip and verbs as the History window's, so every lock mark is one path.
function B.LockExtra() return lockExtra() end

--- Flip the lock through the verbs: `/lh unlock` while locked, `/lh lock` while not.
function B:ToggleLock()
  if NS.RunVerb then NS.RunVerb(B:IsLocked() and "unlock" or "lock") end
end

--- Repaint one header mark's art (catalog `icon`) and tooltip; a no-op with no mark. W.HeaderButtons
--- evaluates both once, at build, so a mark whose face follows a state is repainted by its host.
function B:PaintMark(mark, icon, tip)
  if not mark then return end
  local path = NS.Icon and NS.Icon(icon)
  if mark.icon and path then mark.icon:SetTexture(path) end
  mark.__tip = tip
  -- The library reads __tip only on hover, so a tooltip already open on this mark is rewritten now.
  local gt = GameTooltip
  if gt and type(gt.IsOwned) == "function" and gt:IsOwned(mark) then
    local enter = mark:GetScript("OnEnter")
    if enter then enter(mark) end
  end
end

--- Repaint `mark` (any window's lock extra) for the lock as it stands.
function B:PaintLockMarkOn(mark)
  local icon, tip = lockFace()
  B:PaintMark(mark, icon, tip)
end

--- Repaint the History window's lock mark for the lock as it stands; a no-op with no mark.
function B:PaintLockMark()
  local f = B:GetWindow()
  B:PaintLockMarkOn(f and f.lockButton)
end

-- ── Window position/size persistence ──────────────────────────────────────────
-- settings.window = { point, x, y, w, h } relative to UIParent.
--
-- NOTE: settings.window and savedViews (see savedViewOrStock, modules/BrowserViews.lua) are named non-setting state
-- (architecture-§5): no control chooses them and no row addresses them, so this module owns them and
-- writes them directly rather than through Schema:Set. Every writer and the act that reaches it are
-- named in docs/ARCHITECTURE.md → Settings schema; a new writer goes on that list too.

local function SaveWindow()
  if not frame then return end
  local point, _, _, x, y = frame:GetPoint(1)
  NS.db.profile.settings.window = {
    point = point, x = x, y = y,
    w = frame:GetWidth(), h = frame:GetHeight(),
  }
end

local function RestoreWindow()
  local w = NS.db and NS.db.profile.settings.window
  frame:ClearAllPoints()
  if w and w.point then
    frame:SetPoint(w.point, UIParent, w.point, w.x or 0, w.y or 0)
    if w.w and w.h then
      frame:SetSize(math.max(B._minW or 0, w.w), math.max(B._minH or 0, w.h))
    end
  else
    -- Default (fresh install / after a settings reset): dead-center of the screen, H and V.
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  -- The client's OnSizeChanged re-lays the filter bar out too; this covers a size that did not
  -- change (and is a no-op then).
  B:LayoutFilterBar(frame:GetWidth() - 2 * BAR_INSET)
end

-- ── Tabs ──────────────────────────────────────────────────────────────────────
-- A registry, not a hard-coded pair (timeline-ledger spec §8.0): each tab is a spec its owning
-- module registers -- { name, order, build(pane), refresh(), export(title), filters, suggest(text),
-- pick(item) }, plus the optional view hooks `stock` (fields laid over the stock view),
-- `captureView(v)` and `applyView(view)` (the tab's own fields, P11). The filter bar and footer are
-- shared window chrome (EnsureFrame, issue #13); a pane holds only its view, and each tab keeps its
-- own filter state on that one bar (see "Per-tab views" in modules/BrowserViews.lua).
local tabSpecs, tabOrder = {}, {}
local lastTab = "History"   -- remembered within a session
-- Shared chrome heights; panes sit between the filter bar and the footer. The footer's is the
-- library's FOOTER.HEIGHT (24, NS.FooterHeight), read where it is published, never copied here
-- (standalone-windows' *Window chrome geometry*, AD-89-LH).
local FILTERBAR_H, FILTER_GAP = 46, 8

function B:Tabs() local out = {}; for i, n in ipairs(tabOrder) do out[i] = n end; return out end
function B:ActiveTab() return lastTab end
-- A registered tab's spec (nil for none): how modules/BrowserViews.lua reads the registry this file owns.
function B._tabSpec(name) return tabSpecs[name] end

-- Lazily let the owning module build its pane content the first time it's shown.
local function BuildPane(name)
  local pane = frame.panes[name]
  if not pane._built then pane._built = true; tabSpecs[name].build(pane) end
end

-- THE BODY OFFSET (AD-88-LH; preview-mode's *Where the strip sits*, standard v2.110.0). The mode
-- strip (test or simulation) is docked by the library directly under the title bar, and while one
-- shows everything below the title bar moves down by that strip's `BodyOffset()` (its own height):
-- the 1px divider the tab strip hangs from, the filter bar and every pane. 0 while none shows, and
-- always 0 on a degraded install, which builds no strip.
local function bodyOffset()
  for _, strip in ipairs({ frame.testStrip, frame.simStrip }) do
    if strip and strip:IsShown() and strip.BodyOffset then return strip:BodyOffset() end
  end
  return 0
end

-- Where a pane sits: between the shared filter bar and the shared footer, and `bodyOffset()` lower
-- while a mode strip shows (LootHistory#36). Re-run on every pane by relayBody.
local function anchorPane(pane)
  local top = SKIN.titleBarH + SKIN.tabStripH + SKIN.contentGap + FILTERBAR_H + FILTER_GAP + bodyOffset()
  pane:ClearAllPoints()
  pane:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -top)
  pane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, NS.FooterHeight())
end

-- Lay every band below the title bar out again at the current body offset: the divider (and the
-- tab strip under it), the filter bar and the panes. The strips' `onOffset` and B:UpdateTestStrip
-- call it, so a show or hide of a strip by either path moves the body.
local function relayBody()
  if not frame then return end
  local off = bodyOffset()
  local divider, titleBar = frame.dividerBar, frame.titleBar
  if divider and titleBar then
    divider:ClearAllPoints()
    divider:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -off)
    divider:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, -off)
  end
  local host = frame.filterHost
  if host then
    local barTop = SKIN.titleBarH + SKIN.tabStripH + SKIN.contentGap + off
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT",  frame, "TOPLEFT",   BAR_INSET, -barTop)
    host:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -BAR_INSET, -barTop)
  end
  for _, pane in pairs(frame.panes or {}) do anchorPane(pane) end
end

-- One content pane, filling between the shared filter bar and the shared footer.
local function CreatePane(name)
  local pane = CreateFrame("Frame", nil, frame)
  anchorPane(pane)
  pane:Hide(); frame.panes[name] = pane
end

function B:SelectTab(name)
  if not (frame and tabSpecs[name]) then return end
  -- Per-tab views (P11): the outgoing tab's live state is parked and the incoming tab's put on the
  -- shared bar before the tab's controls are grayed and its options rebuilt. A re-select of the
  -- active tab (Show) keeps what is on the bar.
  if name ~= lastTab then
    B._stashLive(lastTab)
    lastTab = name
    B._restoreLive(name)
  end
  B:ApplyTabFilters(name)
  for _, t in ipairs(tabOrder) do
    local active = (t == name)
    frame.panes[t]:SetShown(active)
    NS.Skin.SetTabSelection(frame.tabs[t], active)
  end
  BuildPane(name)
  -- Refresh the shown view against the shared filter, then the shared footer/DB size (issue #13).
  if tabSpecs[name].refresh then tabSpecs[name].refresh() end
  B:UpdateFooter()
  B:UpdateDbSize()
  if NS.State.debug and NS.Debug then NS.Debug("UI", "tab -> %s", tostring(name)) end
end

-- Strip on first call, missing buttons, then every button placed by index (late tabs re-flow it).
local function LayoutTabButtons()
  local strip = frame.tabStrip
  if not strip then
    strip = CreateFrame("Frame", nil, frame)
    strip:SetPoint("TOPLEFT", frame.dividerBar, "BOTTOMLEFT", 6, -2)
    strip:SetPoint("TOPRIGHT", frame.dividerBar, "BOTTOMRIGHT", -6, -2)
    strip:SetHeight(SKIN.tabStripH)
    frame.tabStrip, frame.tabs = strip, {}
  end
  for i, name in ipairs(tabOrder) do
    local tab = frame.tabs[name]
    if not tab then
      tab = CreateFrame("Button", nil, strip); tab:SetSize(90, SKIN.tabStripH)
      tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      tab.label:SetPoint("CENTER"); tab.label:SetText(name)
      tab:SetScript("OnClick", function() B:SelectTab(name) end)
      -- The skin's Tab: backing, edge, underline and label, repainted by the library on a switch.
      -- SelectTab moves the selection. The tokens are tab.*, drawn for this backing, so tab.text
      -- reads on it in every skin (cause A1 of the full skinning run; the look moves a little on
      -- Ka0s Default, which gains the backing).
      NS.Skin.Tab(tab, { text = tab.label, selected = name == lastTab })
      frame.tabs[name] = tab
    end
    tab:ClearAllPoints(); tab:SetPoint("LEFT", (i - 1) * 94, 0)
  end
end

-- Meant for file load, before the window is built; a later call creates the pane + button on the spot.
function B:RegisterTab(spec)
  if not tabSpecs[spec.name] then tabOrder[#tabOrder + 1] = spec.name end
  tabSpecs[spec.name] = spec
  table.sort(tabOrder, function(a, b) return tabSpecs[a].order < tabSpecs[b].order end)
  if frame then if not frame.panes[spec.name] then CreatePane(spec.name) end; LayoutTabButtons() end
end

-- Test-only: drop a tab, its pane and its button; an active one falls back to History.
function B:_UnregisterTabForTest(name)
  for i, n in ipairs(tabOrder) do if n == name then table.remove(tabOrder, i); break end end
  tabSpecs[name] = nil
  if lastTab == name then lastTab = "History" end
  B._forgetLive(name)
  if not frame then return end
  for _, set in ipairs({ frame.panes, frame.tabs }) do if set[name] then set[name]:Hide(); set[name] = nil end end
  LayoutTabButtons()
end

-- ── Filter bar ──────────────────────────────────────────────────────────────────
-- Compact custom dropdowns + search box matching the flat skin (no Blizzard UIDropDownMenu,
-- so the look stays consistent and there's no protected-call taint surface). All filter
-- changes write B.activeFilter and push it to BrowserTable:SetFilter; group-by drives
-- BrowserTable:SetGroupBy. A footer reports "Showing X of Y".

B.activeFilter = {}

-- THE DROPDOWNS ARE THE LIBRARY'S. Everything that used to stand here -- a MakeDropdown factory,
-- a FULLSCREEN_DIALOG singleton popup with pooled rows, a full-screen click-catcher and six
-- helpers, about two hundred lines -- is now LibKa0s-Widgets-1.0, reached through
-- core/WidgetsSetup.lua's NS.MakeDropdown / NS.CloseMenu. This file was where the widget was
-- written, and it was the third copy of it in the collection; the library carries the two seams
-- this addon's Character filter needs (`opt.isActive` and `dd.presets`, both new at Widgets minor
-- 4 and both ported upstream from here), so the adoption lost nothing. The one behavior that
-- lived here and has no library equivalent is `opt.icon`: a class icon is now folded into the
-- option's LABEL as inline markup, which the library measures (see charOptions in BrowserWidgets.lua).
--
-- NS.MakeDropdown answers nil on an install with no library, and BuildFilterBar
-- (modules/BrowserFilterBar.lua) refuses to draw rather than building dead controls -- see the
-- guard at the top of it.

-- The dropdown-option kit lives in modules/BrowserWidgets.lua, loaded directly above this file:
-- the quality tint, the Bound labels, `dataset`, `withAll` and the seven option builders. Bound here
-- as file-scope locals so the footer, RefreshFilterOptions and OnSettingsChanged call them as before.
local dataset = B._dataset
local sourceOptions, charOptions = B._options.source, B._options.char
local typeOptions, subtypeOptions = B._options.itemType, B._options.itemSubType
local zoneOptions, qualityOptions, boundOptions = B._options.zone, B._options.quality, B._options.bound

-- True while a simulation runs (modules/Sim.lua's NS.Sim, or its inert stub without the library).
local function simulating() return NS.Sim ~= nil and NS.Sim:IsActive() end

-- While a simulation runs the footer leads with where it stands (preview-mode's footer marker):
-- `Simulating: loot · step 2/3`, ahead of the usual count.
function B:UpdateFooter()
  if not self._footer then return end
  local shown = (NS.BrowserTable and NS.BrowserTable.matchCount) or 0
  local total = #dataset()
  local text = ("Showing %d of %d"):format(shown, total)
  if simulating() then
    local st = NS.Sim:Status()
    text = L["Simulating: %s \194\183 step %d/%d"]:format(tostring(st.scenario), st.pos or 0, st.total or 0)
      .. "  \194\183  " .. text
  end
  self._footer:SetText(text)
end

-- Estimated SavedVariables size of the stored history (the same estimate the settings panel
-- shows, Database:StorageStats). Recomputed only when history changes or the window (re)opens —
-- never on a filter keystroke, since filtering can't change what's stored. "~" marks the estimate:
-- U+2248 is missing from Expressway and Philosopher, which drew it as a box (the owner's image-19;
-- ruling D-19 of the skin fonts and feedback run, tests/test_glyphs.lua).
function B:UpdateDbSize()
  if not self._dbFooter then return end
  local bytes = (NS.Database and NS.Database.StorageStats and NS.Database:StorageStats().bytes) or 0
  self._dbFooter:SetText(("Database ~%s"):format(NS.Util.FormatBytes(bytes)))
end

-- Recompute the data-driven dropdowns (source/type/char/zone) from the current dataset.
function B:RefreshFilterOptions()
  local dd = self._dd
  if not dd then return end
  dd.bound:SetOptions(boundOptions())
  dd.quality:SetOptions(qualityOptions())
  dd.source:SetOptions(sourceOptions())
  dd.type:SetOptions(typeOptions())
  dd.subtype:SetOptions(subtypeOptions())
  local spec = tabSpecs[lastTab]
  local holders = spec ~= nil and spec.charSource == "holders"
  local charOpts = charOptions(holders)
  dd.char:SetOptions(charOpts)
  -- One Character control, two option sources: on a source switch, drop picks the new list lacks.
  if self._charHolders ~= nil and self._charHolders ~= holders then self:PruneCharSet(charOpts) end
  self._charHolders = holders
  dd.zone:SetOptions(zoneOptions())
end

-- The two marks' words, colors and strip flavors: test mode's bright red badge and amber strip, and
-- the simulation's own cyan for both.
local TEST_MARK = { badge = "TEST MODE", color = { 1, 0.15, 0.15 }, kind = "test",
  strip = "TEST MODE: a sample loot history, not yours. Combat ends it." }
local SIM_MARK = { badge = "SIM", color = { 0.3, 0.8, 1 }, kind = "sim",
  strip = "SIM: an invented world drives the real capture. Nothing is saved. /lh sim stop ends it." }

-- The strip that marks a mode: the simulation's own strip, or test mode's. nil on a degraded install.
local function modeStripFor(sim)
  if sim then return frame.simStrip end
  return frame.testStrip
end

-- The preview marks (preview-mode): one strip per mode docked directly under the title bar
-- (LootHistory#36, AD-88-LH), the library's amber test flavor or its cyan simulation flavor
-- (LootHistory#37), and the badge beside the window title, which is drawn only when the mode's strip
-- does not exist (a degraded install; the header-word rule, standard v2.87.0). The modes exclude each
-- other (modules/Sim.lua refuses a start in test mode; BrowserTable refuses test mode while one
-- runs), so at most one strip shows. A strip takes room, so the body below the title bar moves down
-- by its BodyOffset while it shows and back up when it goes (relayBody).
-- A Sim listener (modules/SimPanel.lua) calls this on every simulation transition.
function B:UpdateTestStrip()
  if not (frame and frame.testBadge) then return end
  local sim = simulating()
  local on = sim or (NS.BrowserTable and NS.BrowserTable.testMode) or false
  local mark = sim and SIM_MARK or TEST_MARK
  local strip = modeStripFor(sim)
  frame.testBadge:SetText(L[mark.badge])
  frame.testBadge:SetTextColor(mark.color[1], mark.color[2], mark.color[3])
  frame.testBadge:SetShown(on and strip == nil)
  if frame.testStrip then frame.testStrip:SetShown(on and not sim) end
  if frame.simStrip then frame.simStrip:SetShown(on and sim) end
  relayBody()
end

-- Reset the persisted window geometry (named non-setting state, see the NOTE above SaveWindow) and recenter the
-- live frame. Reached from the Master controls "Reset position" button. "Reset all settings" does not
-- call it: the geometry lives in the profile, and the profile reset brings it back (options-ui-§12).
function B:ResetWindow()
  if NS.db and NS.db.profile and NS.db.profile.settings then
    NS.db.profile.settings.window = {}
  end
  if frame then
    frame:ClearAllPoints()
    RestoreWindow()   -- empty geometry → RestoreWindow centers the frame
  end
end

--- The History window's half of the profile adopt path (NS.OnProfileEvent, core/LootHistory.lua).
--- Everything the window draws from the profile is re-read from the NEW one: its geometry, the
--- active tab's saved view (or its stock view when the profile has none; every other tab's parked
--- state is forgotten, so each opens on the new profile's view when next shown), its row height and
--- its chrome. A
--- window that was never built has nothing to re-read; its first build reads the new profile.
--- Test mode keeps its stock view: the preview is session state, not the profile's.
function B:AdoptProfile()
  -- The farm panel (#39) first, built or not: it re-reads its geometry, minimized state, lock mark,
  -- chrome and visibility from the new profile (it answers at once when it was never built).
  if NS.FarmPanel and NS.FarmPanel.AdoptProfile then NS.FarmPanel:AdoptProfile() end
  if not frame then return end
  frame:ClearAllPoints()
  RestoreWindow()
  if not (NS.BrowserTable and NS.BrowserTable.testMode) then
    B._forgetLive()
    self:ApplyView(B._savedViewOrStock(), "current")
  end
  if NS.BrowserTable and NS.BrowserTable.Bind then NS.BrowserTable:Bind() end
  B:ApplyChrome(frame, NS.db.profile.settings.windowScale)
  B:PaintLockMark()
  B:ApplyVisibility()
end
-- Attach the virtualized History table to its pane (issue #13: the pane now holds only the table;
-- the filter bar + footer are shared chrome). The table reads B.activeFilter through
-- BrowserTable.filter, already set by the shared bar's ApplyView.
function B:BuildTable(pane)
  local host = CreateFrame("Frame", nil, pane)
  host:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
  host:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
  if NS.BrowserTable and NS.BrowserTable.Attach then
    NS.BrowserTable:Attach(host)
  end
end

-- The built-in tabs. History's filter push stays ApplyFilter's unconditional half (the footer needs it).
-- Both offer the item and currency names their rows hold, and a pick puts the name in Search
-- (B.SuggestNames / B.PickName, modules/BrowserFilterBar.lua, which loads after this file).
B:RegisterTab{ name = "History", order = 10,
  suggest = function(text) return B.SuggestNames(text) end,
  pick = function(item) B.PickName(item) end,
  build = function(pane) B:BuildTable(pane) end,
  refresh = function() if NS.BrowserTable and NS.BrowserTable.Refresh then NS.BrowserTable:Refresh(); B:RefreshFilterOptions() end end }
B:RegisterTab{ name = "Insights", order = 20,
  suggest = function(text) return B.SuggestNames(text) end,
  pick = function(item) B.PickName(item) end,
  build = function(pane) if NS.Analytics and NS.Analytics.Attach then NS.Analytics:Attach(pane) end end,
  refresh = function() if NS.Analytics and NS.Analytics.Refresh then NS.Analytics:Refresh() end end,
  export = function(title) NS.Export:Open({ title = title,   -- the analytics summary, same filter
    providers = { allData = function() return NS.Database:Stats({}) end,
                  currentView = function() return NS.Database:Stats(B:CurrentFilter("Insights")) end },
    csv = function(stats) return NS.Export:InsightsCSV(stats) end }) end }

-- ── Frame construction ─────────────────────────────────────────────────────────

-- Each mode strip's tooltip: what the rows under it are and what ends the mode.
-- The lines are in the skin's `gtip.body`, the color every skin keeps legible on Blizzard's own dark
-- GameTooltip (which no skin restyles). Read at each hover, so a switch needs no repaint.
local function tipLine(text)
  local r, g, b = NS.SkinColor("gtip.body")
  GameTooltip:AddLine(text, r, g, b)
end

local function testTip()
  GameTooltip:SetText(L["Test mode"])
  tipLine(L["Shows: sample loot, holdings and timeline"])
  tipLine(L["Ended by: combat, /lh test, the launcher menu"])
end

local function simTip()
  GameTooltip:SetText(L["SIM"])
  tipLine(L["Shows: what the real capture recorded from an invented world, this session only"])
  tipLine(L["Ended by: /lh sim stop, real loot, a group, an instance, combat"])
end

-- One mode strip of `mark`'s kind and text, docked by the library directly under the title bar
-- (`dock = "title"`, Widgets minor 27; never anchored here), with `tip` on hover; its show and hide
-- relay the body (`onOffset`). nil on a degraded install (no Widgets library).
local function buildModeStrip(mark, tip, win, onOffset)
  win = win or frame
  local dock = { titleBar = win.titleBar, window = win, onOffset = onOffset or function() relayBody() end }
  local strip = NS.MakeTestStrip(win, L[mark.strip], mark.kind, dock)
  if not strip then return nil end
  strip:EnableMouse(true)
  -- The strip is CHROME: its tooltip attached and centered above it (AD-92-LH).
  strip:HookScript("OnEnter", function(self)
    NS.Compat.OwnTooltip(self)
    tip()
    GameTooltip:Show()
    NS.Compat.PlaceTooltip(self, "chrome")
  end)
  strip:HookScript("OnLeave", function() GameTooltip:Hide() end)
  return strip
end

--- The simulation's strip for another window of this addon (the farm panel, #39): the same cyan band,
--- words and tooltip as the History window's, docked under `win.titleBar`, `onOffset` its relayout.
--- nil on a degraded install. B.SIM_MARK is its badge's word and color for the same window.
function B.MakeSimStrip(win, onOffset) return buildModeStrip(SIM_MARK, simTip, win, onOffset) end
B.SIM_MARK = SIM_MARK

local function EnsureFrame()
  if frame then return frame end

  frame = CreateFrame("Frame", "LootHistoryWindow", UIParent, "BackdropTemplate")
  -- Default size == minimum size: wide enough for every column, so it can grow but never
  -- shrink into horizontal overflow. B:MinWidth() is the single source of truth — the wider of
  -- the column-derived table floor (BrowserTable:MinFrameWidth) and the toolbar-fit floor (the
  -- measured dropdown span + an 8px gap + a min Export 120 + 12px pane margins). The filter bar
  -- scales to fill whatever width the window has (B:LayoutFilterBar), so the window may shrink to
  -- whichever floor is larger. The floor is taken here from the bar's floor widths and taken AGAIN
  -- once BuildFilterBar has measured its labels (below).
  local minW = B:MinWidth()
  local minH = SKIN.minH
  B._minW, B._minH = minW, minH
  frame:SetSize(minW, SKIN.defaultH)  -- open at the (taller) default; can shrink to minH
  -- The on-demand window tier (frame-layering-§1, NS.Constants.LAYERS): HIGH, the Settings panel's
  -- strata. Toplevel, so it is raised when shown and when clicked, and comes up over Settings when
  -- Test mode or the key binding opens it with Settings already up (frame-layering-§4).
  frame:SetFrameStrata(NS.Constants.LAYERS.STRATA.WINDOW)
  frame:SetToplevel(true)
  frame:EnableMouse(true)   -- capture clicks over the whole window; no click-through to the world
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  -- Resizable, and its bounds, come from the corner grip below (NS.MakeResizable).

  -- Title bar (also the drag handle), flat, with no line beneath it (R4-SEP).
  local titleBar = CreateFrame("Frame", nil, frame)
  titleBar:SetPoint("TOPLEFT", 1, -1)
  titleBar:SetPoint("TOPRIGHT", -1, -1)
  titleBar:SetHeight(SKIN.titleBarH)
  titleBar:EnableMouse(true)
  titleBar:RegisterForDrag("LeftButton")
  -- Lock frame (options-ui-§15) gates the DRAG, not the frame's movability: SetMovable(false) would
  -- also break StopMovingOrSizing on a drag already in flight, and the setting says "stop the frame
  -- being dragged", which is a gesture rather than a capability.
  titleBar:SetScript("OnDragStart", function()
    if B:IsLocked() then return end
    frame:StartMoving()
  end)
  titleBar:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    SaveWindow()
  end)
  frame.titleBar = titleBar

  local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("CENTER")
  title:SetText("Ka0s Loot History")
  frame.title = title

  -- The badge beside the title: bright-red TEST MODE or cyan SIM, shown only while that mode
  -- is on and its strip does not exist (a degraded install); otherwise the strip is the marker.
  local testBadge = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  testBadge:SetPoint("LEFT", title, "RIGHT", 10, 0)
  testBadge:SetText(L[TEST_MARK.badge])
  testBadge:SetTextColor(TEST_MARK.color[1], TEST_MARK.color[2], TEST_MARK.color[3])
  testBadge:Hide()
  frame.testBadge = testBadge

  -- The title bar's fill (none on Ka0s Default) through the skin's TitleBar. The title text is
  -- not handed over: it is the window's `frame.title`, which the Shell below already paints in the
  -- title color and font, and painting it twice would be a second call for one color.
  NS.Skin.TitleBar(titleBar)

  -- No line under the title bar (R4-SEP of Ka0sAddonsCommonTasks docs/2026-11-03-SMOKE_ROUND4,
  -- the owner's "no separator line below header" in every window, like the Skin Tester's
  -- showroom). The 1px frame stays, empty, because the tab strip anchors under it
  -- (LayoutTabButtons), so the layout does not move. Held as `dividerBar` rather than the edge's
  -- `divider` field, which names a texture to tint.
  local divider = CreateFrame("Frame", nil, frame)
  divider:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
  divider:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  divider:SetHeight(1)
  frame.dividerBar = divider

  -- The title-bar marks, lock · settings · close (AD-86-LH, AF-HDR-LH): B:MakeTitleMarks above. The
  -- History window is HIGH strata, the settings panel's own, so it stays up when settings opens.
  local marks = B:MakeTitleMarks(titleBar, frame, function() B:Hide() end, nil, { lockExtra() })

  -- The header on the window's title band (R5-WIN of Ka0sAddonsCommonTasks
  -- docs/2026-11-03-SMOKE_ROUND5, items 2 and 5): S.Band is the band at Shell's own inset and
  -- title.height in every skin, and S.Header gives the title bar its rect and anchors the title by
  -- title.align and the marks at W.HeaderButtons' offsets (the close 6 px in from the right,
  -- settings the close's width and 6 px further in), each at the band's vertical middle. Recorded, so a skin switch places them again.
  -- The anchors HeaderButtons laid are the degraded install's, whose facade Header does nothing.
  NS.Skin.Header(frame, { title = title, right = marks, bars = { titleBar } })

  -- Shared window chrome (issue #13): one singleton filter bar above both panes, and one shared
  -- footer below them. Layout from the top: title bar · mode strip (while one shows) · tab strip ·
  -- content gap · FILTER BAR · panes · FOOTER. The panes now hold only their view (table / charts).
  local barTop = SKIN.titleBarH + SKIN.tabStripH + SKIN.contentGap
  frame.panes = {}
  for _, name in ipairs(tabOrder) do CreatePane(name) end   -- one content pane per registered tab
  LayoutTabButtons()   -- builds the tab strip on its first call

  -- Shared singleton filter bar host, anchored below the tab strip and above the panes.
  local filterHost = CreateFrame("Frame", nil, frame)
  filterHost:SetPoint("TOPLEFT",  frame, "TOPLEFT",   BAR_INSET, -barTop)
  filterHost:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -BAR_INSET, -barTop)
  filterHost:SetHeight(FILTERBAR_H)
  frame.filterHost = filterHost

  -- The mode strips (LootHistory#36 #37, LibKa0s#48): one per mode, the library's amber test band
  -- and its cyan simulation band, each docked directly under the title bar (AD-88-LH) and shown by
  -- B:UpdateTestStrip while its mode is on. nil on a degraded install, where the title badge alone
  -- marks the mode. The library draws no tooltip, so each strip's is hooked here.
  frame.testStrip = buildModeStrip(TEST_MARK, testTip)
  frame.simStrip = buildModeStrip(SIM_MARK, simTip)

  -- Shared footer (AD-89-LH; standalone-windows' *The footer*, standard v2.110.0): the library's
  -- W.Footer through NS.MakeFooter, FOOTER.HEIGHT (24) tall, no fill under a hairline in the skin's
  -- `divider`, both lines in its `text.muted`. "Showing X of Y" is the left line and the estimated
  -- DB size the right one; both track the shared filter, so they read the same on either tab.
  -- `grip`: the resize grip below is built on the footer's corner, and the right line starts
  -- FOOTER.GRIP in, clear of it. Degraded, NS.MakeFooter's bare footer keeps both lines.
  local foot = NS.MakeFooter(frame, { grip = true })
  frame.footer = foot
  B._footer = foot.left
  B._dbFooter = foot.right

  -- Build the shared filter controls, populate their options, and apply the saved view (opens
  -- scoped to the current player). The table/charts attach lazily per tab and pick up this filter.
  B:BuildFilterBar(filterHost)
  -- The bar has measured its labels, so the toolbar floor is final only now. The grip below and
  -- RestoreWindow both clamp to it, which widens a size saved by a build with narrower controls.
  -- The table's Qty column is measured here too (gold amounts at the row font), since the column
  -- floor is summed from the column widths.
  if NS.BrowserTable and NS.BrowserTable.MeasureColumns then NS.BrowserTable:MeasureColumns(frame) end
  minW = B:MinWidth()
  B._minW = minW
  frame:SetWidth(minW)
  B:RefreshFilterOptions()
  B:ApplyView(B._savedViewOrStock(), "current")
  B:UpdateDbSize()

  -- Resize grip, bottom-right: Core.MakeResizable through the seam (#33). The library draws the
  -- client's chat size grabber, the same corner every window in the collection wears, tinted by
  -- `icon.grip` for the owner named here (false in Ka0s Default, so the art stays the client's).
  --   * minHeight is passed on purpose: the library's default floor is the CURRENT size, and the
  --     window opens at SKIN.defaultH, so leaving it out would raise the floor from minH to 700.
  --   * Lock frame gates the resize as well as the title-bar drag (canResize, read at every press):
  --     the grip stays drawn and does nothing while locked, and a refused press saves nothing.
  --   * The save and the table refresh run once per release (onResizeStop). Never onResize, which
  --     also runs on every OnSizeChanged -- every frame of a drag, and RestoreWindow's SetSize. The
  --     live relayout during a drag is the scroll frames' own OnSizeChanged.
  NS.MakeResizable(frame, {
    owner = addonName,
    gripParent = foot,   -- in the footer's bottom-right corner, which is the window's (W.Footer)
    minWidth = minW,
    minHeight = minH,
    canResize = function() return not B:IsLocked() end,
    onResizeStop = function()
      SaveWindow()
      if NS.BrowserTable and NS.BrowserTable.Refresh then NS.BrowserTable:Refresh() end
    end,
  })
  -- The filter bar follows the window's width live, every frame of a drag (P6 Task 3): anchors and
  -- widths only, skipped when the width did not change. Its own hook rather than MakeResizable's
  -- opts.onResize (which the library also runs off a hooked OnSizeChanged): onResize stays unused,
  -- per the note above, and this relayout is cheap enough for every size tick.
  frame:HookScript("OnSizeChanged", function(_, w) B:LayoutFilterBar(w - 2 * BAR_INSET) end)

  -- Close any open dropdown menu whenever the window hides (covers the ESC/UISpecialFrames
  -- path, which calls frame:Hide() directly instead of B:Hide()). Also the single seam for the
  -- [UI] show/hide trace — fires once per visibility change regardless of call path (B:Show/
  -- B:Hide, ESC, or a raw frame:Hide()).
  frame:HookScript("OnShow", function()
    if NS.State.debug and NS.Debug then NS.Debug("UI", "window shown") end
    -- An open is a view open (debug-logging-§8): the first [Table] / [Insights] summary after it
    -- lands even when it matches the last one logged, which the change gate would otherwise hold.
    if NS.BrowserTable and NS.BrowserTable.ResetRenderTrace then NS.BrowserTable.ResetRenderTrace() end
    if NS.Analytics and NS.Analytics.ResetRenderTrace then NS.Analytics.ResetRenderTrace() end
    -- Give the pending bound-state repair another pass here. By the time the user opens the
    -- window the item cache is warm, which is exactly what the login passes may have lacked —
    -- and this is the moment the wrong lock color would be looked at. No-op once it completes.
    if NS.Database and NS.Database.RepairBoundStates then NS.Database:RepairBoundStates() end
  end)
  frame:HookScript("OnHide", function()
    -- The popup is a process-wide singleton parented to UIParent; this frame's own Hide cannot
    -- reach it. This is also the Escape / UISpecialFrames path. The row context menu is the same
    -- shape (a UIParent child) and closes here too, so neither popup outlives its window.
    NS.CloseMenu()
    if NS.BrowserTable and NS.BrowserTable.HideMenu then NS.BrowserTable:HideMenu() end
    if NS.State.debug and NS.Debug then NS.Debug("UI", "window hidden") end
  end)

  -- The window edge through the skin's Shell. `noTopBar`: the title bar paints its own fill
  -- (TitleBar, above). No `bottomBar`: the footer has no fill of its own (W.Footer, AD-89-LH).
  B:ApplySkin(frame, nil, { noTopBar = true })
  RestoreWindow()
  B:ApplyChrome(frame, NS.db and NS.db.profile.settings.windowScale)
  frame:Hide()

  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "LootHistoryWindow")
  end
  return frame
end

-- ── Master controls: the addon-wide chrome (options-ui-§15) ────────────────────
--
-- `settings.scale`, `settings.alpha`, `settings.locked` and `settings.visibility` govern EVERY
-- frame this addon draws — the History window and the export modal — which is what makes them the
-- master rows rather than a second copy of `settings.windowScale`. That one is the History window's
-- OWN scale and MULTIPLIES on top of the master, exactly as a per-instance row is meant to: a
-- player who has sized this window relative to the rest of their UI keeps that relationship when
-- they scale the addon as a whole.
--
-- They live here, on the module that owns this addon's window chrome, and modules/Export.lua
-- borrows them the same way it already borrows MakeCloseButton and the browser anchor.

--- The addon-wide scale, alpha and lock, with the shipped values as the floor.
function B:MasterChrome()
  local s = (NS.db and NS.db.profile and NS.db.profile.settings) or {}
  return s.scale or 1.0, s.alpha or 1.0, s.locked and true or false
end

--- True while the frames are locked and a drag must not start.
function B:IsLocked()
  return select(3, B:MasterChrome())
end

--- Apply the addon-wide scale and opacity to one of this addon's top-level frames.
--- `windowScale` is that frame's OWN per-window scale, or nil for a frame that has none.
function B:ApplyChrome(f, windowScale)
  if not f then return end
  local scale, alpha = B:MasterChrome()
  f:SetScale(scale * (windowScale or 1.0))
  f:SetAlpha(alpha)
end

--- The stored General visibility mode, "always" when nothing is stored yet.
local function visibilityMode()
  return (NS.db and NS.db.profile and NS.db.profile.settings
          and NS.db.profile.settings.visibility) or "always"
end

--- Whether the History window is allowed on screen right now (the General visibility dropdown).
---
--- The window is opened on demand — a slash verb, the minimap button, a keybind — so honoring the
--- setting means REFUSING to show and hiding a window the setting has stopped allowing. It never
--- opens the window by itself: "Only in combat" is a permission, not an instruction to pop a
--- 1100px browser over a pull.
---
--- `inCombat` is the combat edge when a transition calls in (true from PLAYER_REGEN_DISABLED, false
--- from PLAYER_REGEN_ENABLED); nil everywhere else, and the player's combat flag answers.
function B:VisibilityAllows(inCombat)
  -- THE FIRST RUNG, and it is the whole of slash-commands-§7's "hidden AT THE SOURCE". A window
  -- taken down imperatively comes back: the next combat transition, the next settings change or
  -- the next `ApplyVisibility` re-shows it behind the switch's back, and the addon is then visibly
  -- running while it claims to be off. Refusing here means every route into the window -- the verb,
  -- the minimap click, the tab restore, the visibility dropdown -- answers no from one place.
  if NS.IsStoodDown and NS.IsStoodDown() then return false end
  local mode = visibilityMode()
  if mode == "never"  then return false end
  if mode == "always" then return true end
  -- A display decision, so never the combat-lockdown flag (events-frames-taint-§2):
  -- PLAYER_REGEN_DISABLED fires BEFORE lockdown engages, so at the pull the lockdown still reads
  -- false and "Only out of combat" would leave the window up for the whole fight. The edge itself
  -- is the state; off an edge, Compat.PlayerInCombat() is the display-side read.
  if inCombat == nil then
    inCombat = NS.Compat.PlayerInCombat()
  end
  if mode == "inCombat" then return inCombat end
  return not inCombat   -- "outOfCombat"
end

--- Hide the window if the visibility setting no longer allows it. Called on every combat
--- transition (which passes the edge through as `inCombat`) and whenever the dropdown is written.
---
--- The one [UI] line names the setting that took the window down, so a window that "vanished at
--- the pull" reads as the choice it was (debug-logging-§8, state edges). An edge that changes
--- nothing logs nothing.
function B:ApplyVisibility(inCombat)
  if frame and frame:IsShown() and not B:VisibilityAllows(inCombat) then
    if NS.State.debug and NS.Debug then
      NS.Debug("UI", "window hidden by visibility=%s (%s)", tostring(visibilityMode()),
        inCombat == nil and "setting changed" or ("combat=" .. tostring(inCombat)))
    end
    frame:Hide()
  end
end

function B:Show()
  -- Silently, and only here: a stood-down addon's refusal is the DISPATCHER's one line, and a
  -- second line from the show ladder underneath it would be the two-line lecture §7 forbids. The
  -- visibility refusal below still speaks, because that one is about a setting the player chose.
  -- Both refusals still leave one gated [UI] line naming the guard (debug-logging-§8): the chat
  -- rule above is about the player's chat, and the log is where "nothing opened" gets its answer.
  if NS.IsStoodDown and NS.IsStoodDown() then
    if NS.State.debug and NS.Debug then NS.Debug("UI", "open refused: stood down") end
    return
  end
  if not B:VisibilityAllows() then
    if NS.State.debug and NS.Debug then
      NS.Debug("UI", "open refused: visibility=%s", tostring(visibilityMode()))
    end
    print("the window is hidden by the General visibility setting.")
    return
  end
  local f = EnsureFrame()
  f:Show()
  -- Eager-build the History pane so the table attaches and matchCount is fresh — the shared footer
  -- (issue #13) then reads correctly even when the window opens straight onto the Insights tab.
  BuildPane("History")
  B:SelectTab(lastTab)
  B:UpdateTestStrip()
end

function B:Hide()
  -- Belt and braces, and the braces are the load-bearing half: the frame's own OnHide hook (in
  -- BuildWindow, beside the RepairBoundStates kick) already calls NS.CloseMenu, so `frame:Hide()`
  -- below reaches the popup through it. That hook is what covers Escape and every other close
  -- path; this call only covers the case where the frame was never built.
  NS.CloseMenu()
  if NS.BrowserTable and NS.BrowserTable.HideMenu then NS.BrowserTable:HideMenu() end
  if frame then frame:Hide() end
end

function B:Toggle()
  -- Routed through B:Show rather than f:Show, so the visibility refusal covers the toggle and the
  -- minimap click too. Only the frame that already exists can be hidden, so a refused open never
  -- builds one.
  if frame and frame:IsShown() then frame:Hide() else B:Show() end
end

-- The History window frame (or nil if never built). Lets sibling modules (e.g. Export) anchor
-- their own popups to the browser window rather than the screen.
function B:GetWindow() return frame end

--- Test-only: put `f` in the window's place (nil: none built yet) and answer the one it replaced, so
--- tests/test_skin_chrome.lua can build a fresh window under the kit's paint recorder and put the
--- session's window back afterwards.
function B:_SwapWindowForTest(f)
  local old = frame
  frame = f
  return old
end

--- The per-window scale row's onChange. Goes through ApplyChrome so the master scale is applied in
--- the same breath — a per-window scale set on its own would otherwise discard it.
function B:SetScale(v)
  B:ApplyChrome(frame, v)
end

-- React to settings changes (master chrome + window scale + visibility) while the window
-- exists. The export modal is reached from here rather than from a bus target of its own: it is
-- built lazily and may not exist, and E:Open re-applies on every open regardless.
function B:OnSettingsChanged()
  B:ApplyChrome(frame, NS.db.profile.settings.windowScale)
  B:PaintLockMark()
  if NS.Export and NS.Export.ApplyChrome then NS.Export:ApplyChrome() end
  B:ApplyVisibility()
  -- The farm panel (#39) follows the same master rows: its chrome, its lock mark and visibility (F9).
  local FP = NS.FarmPanel
  if FP and FP.OnChromeChanged then FP:OnChromeChanged() end
  -- The MINIMAP BUTTON is deliberately not re-applied here any more. It is the Master controls
  -- "Minimap button" row, and that row's set drives NS.Launcher:SetShown through this addon's
  -- single write seam (settings/Schema.lua) the instant it is flipped -- so re-asserting it on
  -- every unrelated chrome message would be a second writer of one state (launcher-§3).
  -- The minimum-quality floor follows the setting live while the window is up.
  if frame and frame:IsShown() and B.activeFilter then
    B._applyQualityFloor(B.activeFilter)
    if B._dd and B._dd.quality then B._dd.quality:SetOptions(qualityOptions()) end
    B._applyFilter()
  end
end

-- Keep the browser current when the underlying history changes (new loot, a row delete, retention
-- prune, or a blacklist/whitelist edit — issue #14). The shared filter bar + footer (issue #13)
-- refresh on either tab; the table repaints only when it's the visible tab. Insights live-refreshes
-- itself through its own bus subscription.
function B:OnHistoryChanged()
  if not (frame and frame:IsShown()) then return end
  if lastTab == "History" and NS.BrowserTable and NS.BrowserTable.Refresh then
    NS.BrowserTable:Refresh()
  end
  self:RefreshFilterOptions()
  self:UpdateFooter()
  self:UpdateDbSize()
end

-- Subscribe once the addon (bus) is available.
function B:Enable()
  if NS.bus and not self._enabled then
    self._enabled = true
    -- Private bus target (never the shared bus-as-self) so these don't clobber the Collector's
    -- SettingsChanged or Analytics' RecordAdded/HistoryChanged handlers. See NS.NewBusTarget.
    -- No `or NS.bus` tail: NS.NewBusTarget returns nil ONLY when AceEvent-3.0 is unresolvable, and
    -- core/LootHistory.lua:4's NewAddon(NS, addonName, "AceEvent-3.0", …) errors first in exactly
    -- that case, so NS.bus never exists and the `if NS.bus` guard above never opens.
    B.__ev = NS.NewBusTarget()
    B.__ev:RegisterMessage(NS.MSG.SETTINGS_CHANGED, function() B:OnSettingsChanged() end)
    B.__ev:RegisterMessage(NS.MSG.HISTORY_CHANGED, function() B:OnHistoryChanged() end)
    -- COALESCED, and only this one (issue #27). `OnHistoryChanged` is nine full-history passes —
    -- a BrowserTable rebuild, seven dropdown builders each scanning the whole dataset, and a
    -- StorageStats byte estimate — and RecordAdded fires once per LOOTED ITEM, mid-pull, on a
    -- frame that can be open through a boss kill. A multi-drop kill with a long history paid that
    -- price once per drop.
    --
    -- `HistoryChanged` above stays immediate on purpose: it is a delete, a prune or a
    -- blacklist edit — a deliberate user action that arrives one at a time and should repaint at
    -- once. Only the automatic, bursty message needs collapsing.
    B.__ev:RegisterMessage(NS.MSG.RECORD_ADDED,
      NS.Coalesce(function() B:OnHistoryChanged() end, NS.Constants.RECORD_ADDED_COALESCE))
    -- The two transitions the General visibility dropdown is about. Only ever HIDES: a window the
    -- setting stops allowing goes away, and one it starts allowing is still the player's to open.
    -- The combat start also ends test mode (preview-mode, options-ui-§15): no sample row may sit
    -- over real loot in a fight. EndTestModeForCombat never opens the window.
    -- Per event through Core's helper (events-frames-taint-§1): a refused name costs only itself.
    NS.SafeRegisterEvent(B.__ev, "PLAYER_REGEN_DISABLED", function()
      B:ApplyVisibility(true)
      if NS.FarmPanel and NS.FarmPanel.ApplyVisibility then NS.FarmPanel:ApplyVisibility(true) end
      if NS.BrowserTable and NS.BrowserTable.EndTestModeForCombat then
        NS.BrowserTable:EndTestModeForCombat()
      end
    end, NS.RejectedEvents)
    NS.SafeRegisterEvent(B.__ev, "PLAYER_REGEN_ENABLED", function()
      B:ApplyVisibility(false)
      if NS.FarmPanel and NS.FarmPanel.ApplyVisibility then NS.FarmPanel:ApplyVisibility(false) end
    end, NS.RejectedEvents)
  end
end

--- The stand-down half of Enable (slash-commands-§7). The private bus target carries all five
--- registrations -- three messages and the two combat transitions -- so it goes wholesale, and the
--- coalescing RecordAdded trigger goes with it: an armed repaint timer that wakes to find nothing
--- to paint is the shape §7 singles out as the most expensive one.
---
--- The window itself is taken down by NS.StandDown, and kept down by the first rung of
--- B:VisibilityAllows. This function only stops the subscriptions.
function B:Disable()
  if not self._enabled then return end
  -- Nothing to unregister for the suggestion list (it holds no event, message or OnUpdate), but an
  -- open one goes, and its pending debounce with it.
  if self._autocomplete then self._autocomplete:Close() end
  if B.__ev then
    B.__ev:UnregisterAllMessages()
    B.__ev:UnregisterAllEvents()
    B.__ev = nil
  end
  self._enabled = nil
end
