-- tests/panel_support.lua — the panel suites' shared render helpers.
--
-- Extracted when tests/test_panel.lua crossed layout-§1's 1500-line cap and the Filters-tab cases
-- peeled off into tests/test_panel_filters.lua. Both suites drive the SAME panel objects, so the
-- helpers cannot simply be copied into each file: `rendered` is a cache of each panel's FIRST
-- render, and a second copy of it would be empty. The body is deferred to the page's first OnShow
-- and never rebuilt wholesale, so the suite that showed the page second would record a widget slice
-- of zero widgets and every assertion reading it would pass vacuously.
--
-- So this module is a SINGLETON, and the guard below is the whole reason it is a module at all.
-- `dofile` runs the file again on every call; stashing the table on the sandbox global makes the
-- second suite receive the first suite's cache instead of a fresh one. The global is namespaced and
-- resets with the environment, like everything else the kit builds.
if rawget(_G, "__LH_PANEL_SUPPORT") then return rawget(_G, "__LH_PANEL_SUPPORT") end

local T = _G.LH_TEST
local mocks = T.mocks

local AceGUI = mocks.__libs["AceGUI-3.0"]

--- Fire a panel's OnShow and return the widgets its BODY is built from, in creation order.
---
--- Every page body is deferred to its first OnShow and then never rebuilt wholesale, so a second
--- call creates nothing. The first render's widget slice is therefore cached per panel and handed
--- back on every later call — which is what lets each case reach the same live widget the user
--- would click, rather than an empty list that would make the assertions below vacuous.
local rendered = {}
local function show(panel)
  local before = #AceGUI.__created
  -- Show() as well as firing the handler. The mock tracks visibility without firing OnShow, and the
  -- refresh fan-out deliberately skips a page that is not on screen (it flags it dirty instead), so
  -- a page that was never Shown would silently ignore every Refresh and the cases below would pass
  -- on a panel that does nothing.
  panel:Show()
  panel:__fire("OnShow")
  if not rendered[panel] then
    local out = {}
    for i = before + 1, #AceGUI.__created do out[#out + 1] = AceGUI.__created[i] end
    rendered[panel] = out
  end
  return rendered[panel]
end

--- Click a page's tab by position and return the widgets that render built, in creation order.
---
--- BY POSITION, not by name: the strip's buttons come back from the library in tab order, so an
--- index plus an assertion on `ctx.activeTab` pins the ORDER of the strip as well as its contents.
--- Clicking the tab you are already on is a no-op in the library (the active tab is the disabled
--- one), so tab 1 is reached through `show` instead.
---
--- Every caller clicks back to tab 1 before it returns. The `show` cache above hands back the
--- FIRST render's widget slice, which is tab 1's, and a page parked on another tab would make
--- every later case reach for widgets that are no longer on screen.
local function clickTab(panel, ctx, index)
  show(panel)
  local layout = ctx.__tabLayout
  T.assertTrue(layout ~= nil and layout.buttons ~= nil, "the page drew no tab strip")
  T.assertTrue(layout.buttons[index] ~= nil, "there is no tab " .. index .. " on the strip")
  local before = #AceGUI.__created
  layout.buttons[index]:__fire("OnClick")
  local out = {}
  for i = before + 1, #AceGUI.__created do out[#out + 1] = AceGUI.__created[i] end
  return out
end

--- Back to the first tab, and REPOINT the `show` cache at the widgets that click just built.
---
--- Not bookkeeping: a tab click runs ClearScroll, which hands every widget back to AceGUI's pool
--- and REASSIGNS `ctx.refreshers`. A case that then reached the cached first-render checkbox would
--- be holding a released widget whose refresher no longer exists — and `Panel:Refresh` would look
--- like it had stopped working when in fact the test was looking at last render's page.
local function homeTab(ctx)
  local layout = ctx.__tabLayout
  if not (layout and layout.buttons and layout.buttons[1]) then return end
  local panel = ctx.panel
  local before = #AceGUI.__created
  layout.buttons[1]:__fire("OnClick")
  if #AceGUI.__created > before then
    local out = {}
    for i = before + 1, #AceGUI.__created do out[#out + 1] = AceGUI.__created[i] end
    rendered[panel] = out
  end
end

local function widgetsOfType(list, wtype)
  local out = {}
  for _, w in ipairs(list) do if w.type == wtype then out[#out + 1] = w end end
  return out
end

local function findByLabel(list, label)
  for _, w in ipairs(list) do
    if w.labelText == label or w.text == label then return w end
  end
end


-- The strip, in order. Stated here rather than derived from the thing the assertion reads, so a tab
-- that moves is a NAMED failure rather than a shorter list that still agrees with itself.
--
-- Six tabs, five of them schema groups and one of them a bespoke body — which is why the page draws
-- its strip by hand instead of through O.RenderTabbedSchema: that one derives its tab list from
-- `group`, and a dynamic list of item ids has no rows to declare one.
--
-- THE NAMES AND THE ORDER ARE SHARED WITH KA0S BANK LEDGER, whose strip is these six minus AH Price
-- — Master controls, Capture, Interface, History, Filters. The two addons keep the same shape of
-- record and a player compares their panels directly, so a subject carries one name across both:
-- Collection became Capture and Maintenance became History, and AH Price, which is this addon's
-- alone, sits directly after Capture.
local STRIP = {
  "Master controls", "Capture", "AH Price", "Interface", "History", "Filters",
}

--- The strip position of a named tab, so a case can say WHICH tab it means and still click by
--- position. The index still comes from STRIP — declared above, independently of the page — so a
--- tab that moves is still a named failure; what this removes is the second, silent copy of the
--- order that a bare `clickTab(panel, ctx, 5)` was.
local function tabAt(name)
  for i, tab in ipairs(STRIP) do if tab == name then return i end end
  T.assertTrue(false, "no tab named " .. tostring(name) .. " on the strip")
end

local M = {
  AceGUI         = AceGUI,
  show           = show,
  clickTab       = clickTab,
  homeTab        = homeTab,
  widgetsOfType  = widgetsOfType,
  findByLabel    = findByLabel,
  STRIP          = STRIP,
  tabAt          = tabAt,
}

rawset(_G, "__LH_PANEL_SUPPORT", M)
return M
