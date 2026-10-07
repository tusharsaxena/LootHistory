-- LibKa0s-Widgets-1.0 -- the autocomplete: a suggestion list that hangs directly under a host's
-- EditBox, the same width and in the box's own gray skin, filled by a host provider as the player
-- types, and picked from with the mouse or the keyboard.
--
-- -- WHY IT IS IN THE LIBRARY ------------------------------------------------------------------
--
-- Two consumers want the same thing with the same semantics: LootHistory's search box on every tab
-- and BankLedger's search box, both a flat-skinned EditBox over an item list, both wanting "type a
-- few letters, pick the item". That is library-stack-7's promotion bar. Two copies of a list that
-- must look like part of the box it hangs from is two skins to keep in step.
--
-- -- WHY IT IS A FILE OF ITS OWN AND NOT MORE OF Widgets.lua ------------------------------------
--
-- For the reason WidgetsDragHandle.lua gives: one file per widget keeps each under layout-1's
-- 1500-line cap, and a secondary file paired on the SHELL's minor cannot attach to a shell from
-- another vendored copy without saying so.
--
-- -- HOW IT MEETS THE HOST'S BOX: HOOKS, NEVER SCRIPTS -------------------------------------------
--
-- The host's box already has its own OnTextChanged (its filter), OnEnterPressed and
-- OnEscapePressed (usually ClearFocus). Every script here is HOOKED, so the host's handler runs
-- first and keeps running; nothing the host set is replaced. Hooks cannot be removed, so they are
-- installed ONCE per box and dispatch to whichever handle owns the box now: a second Autocomplete
-- on the same box releases the first, and a released handle's hooks do nothing.
--
-- Because the host's Enter usually clears focus BEFORE the Enter hook runs, losing focus does not
-- close the list on the spot: the close waits one frame, so an Enter or Tab still finds the row the
-- player selected. Losing focus to a press on the list itself does not close it at all: the box
-- takes the keys back on the next frame, and the row's own click (on the release) picks and closes.
--
-- -- WHAT THE HOST STILL OWNS -------------------------------------------------------------------
--
-- What the rows say (the provider), what a pick does (onPick: the widget never writes the box's
-- text), and the box itself. The list registers no event and arms no OnUpdate; its only timers are
-- the typing debounce and the one-frame focus checks, all through C_Timer.After, read at call time.
--
-- Depends on LibStub and on the Widgets shell, and on no addon framework.

local lib = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
if not lib then return end

local AUTOCOMPLETE_MINOR = 1
-- Paired on the SHELL's minor as well as this file's own, as WidgetsDragHandle.lua is.
if lib.__autocompleteMinor and lib.__autocompleteMinor >= AUTOCOMPLETE_MINOR
  and lib.__autocompleteShellMinor == lib.MINOR then return end
lib.__autocompleteMinor      = AUTOCOMPLETE_MINOR
lib.__autocompleteShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.WidgetsAutocomplete = AUTOCOMPLETE_MINOR

local WHITE = "Interface\\Buttons\\WHITE8X8"
local min, max = math.min, math.max

--- The list's published chrome and timing. READ, never restated. BORDER and BG are the house flat
--- skin (the dropdown's and the search box's own), used only when the box answers no backdrop
--- colors of its own; MIN_BG_ALPHA keeps the rows legible over whatever the list covers.
lib.AUTOCOMPLETE = {
  MAX_ROWS = 8, ROW_H = 18, DEBOUNCE = 0.15, MIN_CHARS = 1,
  PAD = 1, OVERLAP = 1, ICON = 14, TEXT_INSET = 6, STRATA = "FULLSCREEN_DIALOG",
  MIN_BG_ALPHA = 0.95, FONT = "GameFontHighlightSmall",
  BORDER = { 0.24, 0.24, 0.27, 0.9 }, BG = { 0.1, 0.1, 0.12, 0.9 },
  TEXT = { 0.9, 0.9, 0.9 }, HIGHLIGHT = { 1, 0.82, 0, 0.15 },
}
local AC = lib.AUTOCOMPLETE

-- The box each hooked EditBox is owned by now, and the boxes already hooked. Weak-keyed: a box the
-- host drops takes its entries with it.
local owners = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })

-- -- small readers -------------------------------------------------------------------------------

local function after(delay, fn)
  if C_Timer and C_Timer.After then C_Timer.After(delay, fn) else fn() end
end

--- Four numbers from a color getter, or the fallback. A headless frame answers its own table for a
--- getter it does not model, so every value is type-checked.
local function rgba(r, g, b, a, fallback)
  if type(r) == "number" and type(g) == "number" and type(b) == "number" then
    return r, g, b, type(a) == "number" and a or 1
  end
  return fallback[1], fallback[2], fallback[3], fallback[4]
end

local function boxColor(box, getter, fallback)
  local fn = box[getter]
  if type(fn) ~= "function" then return fallback[1], fallback[2], fallback[3], fallback[4] end
  local r, g, b, a = fn(box)
  return rgba(r, g, b, a, fallback)
end

--- A row's text color: `{ r, g, b }`, or a table with `.r .g .b` (a ColorMixin, an
--- ITEM_QUALITY_COLORS entry), or the list's plain text color.
local function itemColor(c)
  if type(c) ~= "table" then return AC.TEXT[1], AC.TEXT[2], AC.TEXT[3] end
  local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
  if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
  return AC.TEXT[1], AC.TEXT[2], AC.TEXT[3]
end

local function boxText(box)
  local t = box.GetText and box:GetText()
  return type(t) == "string" and t or ""
end

local function longEnough(h, text)
  local trimmed = text:match("^%s*(.-)%s*$") or ""
  return #trimmed >= h.__minChars
end

-- In the client both answer a boolean; a headless frame answers its own table, read as false.
local function hasFocus(box) return box.HasFocus ~= nil and box:HasFocus() == true end
local function pointerOn(f) return f ~= nil and f.IsMouseOver ~= nil and f:IsMouseOver() == true end

-- -- the frame -----------------------------------------------------------------------------------

local function markRow(row, on)
  row.__selected = on
  if on then row:LockHighlight() else row:UnlockHighlight() end
end

local function makeRow(h, i)
  local list, rh = h.__list, h.__rowH
  local row = CreateFrame("Button", nil, list)
  row:SetHeight(rh)
  local y = -AC.PAD - (i - 1) * rh
  row:SetPoint("TOPLEFT", list, "TOPLEFT", AC.PAD, y)
  row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -AC.PAD, y)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(AC.HIGHLIGHT[1], AC.HIGHLIGHT[2], AC.HIGHLIGHT[3], AC.HIGHLIGHT[4])
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(AC.ICON, AC.ICON)
  row.icon:SetPoint("LEFT", row, "LEFT", AC.TEXT_INSET - 2, 0)
  -- Created WITH a template: a FontString with no face raises on its first SetText in the client.
  row.label = row:CreateFontString(nil, "OVERLAY", h.__font)
  row.label:SetJustifyH("LEFT")
  row.label:SetWordWrap(false)
  row.__index = i
  row:SetScript("OnClick", function(self) h:__Pick(self.__index) end)
  return row
end

--- Built on the first list that shows. Parented to the box, so it takes the box's scale and hides
--- with it; anchored to both bottom corners, so it is the box's width and follows every resize
--- with no handler of its own; raised to its own strata, so the rows below the box cannot cover it.
local function ensureList(h)
  if h.__list then return h.__list end
  local box = h.__box
  local list = CreateFrame("Frame", nil, box, "BackdropTemplate")
  list:SetFrameStrata(h.__strata)
  list:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, AC.OVERLAP)
  list:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, AC.OVERLAP)
  list:EnableMouse(true)
  list:Hide()
  h.__list = list
  return list
end

--- The box's own skin, read on every show: a host that restyles its box restyles its list.
local function skin(h)
  local list, box = h.__list, h.__box
  if not list.SetBackdrop then return end
  list:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  local r, g, b, a = boxColor(box, "GetBackdropColor", AC.BG)
  list:SetBackdropColor(r, g, b, max(a, AC.MIN_BG_ALPHA))
  list:SetBackdropBorderColor(boxColor(box, "GetBackdropBorderColor", AC.BORDER))
end

-- EVERY field is written on every paint: the rows are pooled across lists, so a field left alone
-- leaks the previous list's icon or color onto this one. The icon's visibility is set BEFORE the
-- row is shown (the API document's *Behavior a host must know*, on the headless kit).
local function paintRow(h, row, item)
  row.__item = item
  local icon = item.icon
  if icon ~= nil then row.icon:SetTexture(icon) end
  row.icon:SetShown(icon ~= nil)
  row.label:ClearAllPoints()
  row.label:SetPoint("LEFT", row, "LEFT", icon ~= nil and (AC.ICON + AC.TEXT_INSET + 2) or AC.TEXT_INSET, 0)
  row.label:SetPoint("RIGHT", row, "RIGHT", -AC.TEXT_INSET, 0)
  row.__text = tostring(item.text or "")
  row.label:SetText(row.__text)
  row.label:SetTextColor(itemColor(item.color))
  markRow(row, false)
  row:SetHeight(h.__rowH)
  row:Show()
end

local function render(h, items)
  local list = ensureList(h)
  skin(h)
  local n = min(#items, h.__maxRows)
  local shown = {}
  for i = 1, n do
    local row = h.__rows[i]
    if not row then
      row = makeRow(h, i)
      h.__rows[i] = row
    end
    -- A bare string from a provider reads as a row with that text and nothing else.
    local item = items[i]
    if type(item) ~= "table" then item = { text = tostring(item) } end
    shown[i] = item
    paintRow(h, row, item)
  end
  for i = n + 1, #h.__rows do h.__rows[i]:Hide() end
  list:SetHeight(n * h.__rowH + 2 * AC.PAD)
  h.__items, h.__sel, h.__open = shown, nil, true
  list:Show()
end

-- -- the handle ----------------------------------------------------------------------------------

local Handle = {}
Handle.__index = Handle

local function live(h) return h.__enabled and not h.__released end

--- Drop any update still waiting on the debounce, and any one-frame check still pending.
local function cancelPending(h) h.__seq = h.__seq + 1 end

function Handle:Close()
  cancelPending(self)
  if self.__sel and self.__rows[self.__sel] then markRow(self.__rows[self.__sel], false) end
  self.__sel, self.__items, self.__open = nil, {}, false
  if self.__list then self.__list:Hide() end
end

function Handle:IsShown() return self.__open == true end

--- Ask the provider now, for the box's text now, and show what it answers (or close on nothing).
function Handle:Refresh()
  if not live(self) then return end
  cancelPending(self)
  local text = boxText(self.__box)
  if not longEnough(self, text) then return self:Close() end
  local items = self.__provider(text)
  if type(items) ~= "table" or #items == 0 then return self:Close() end
  render(self, items)
end

function Handle:SetEnabled(on)
  self.__enabled = on and true or false
  if not self.__enabled then self:Close() end
end

function Handle:Release()
  self:Close()
  self.__released = true
  self.__provider, self.__onPick = nil, nil
  if owners[self.__box] == self then owners[self.__box] = nil end
end

--- Pick the row at `i`: close first, so a host's onPick that writes the box's text (or clears it)
--- meets a closed list, then hand the host the item exactly as its provider answered it.
function Handle:__Pick(i)
  if not live(self) then return end
  local item = self.__open and self.__items[i]
  if not item then return end
  local onPick = self.__onPick
  self:Close()
  if onPick then onPick(item) end
end

function Handle:__Move(step)
  if not self.__open then return end
  local n = #self.__items
  if n == 0 then return end
  local cur = self.__sel
  if cur and self.__rows[cur] then markRow(self.__rows[cur], false) end
  local nxt
  if step > 0 then nxt = min((cur or 0) + 1, n) else nxt = (cur and cur > 1) and (cur - 1) or nil end
  self.__sel = nxt
  if nxt then markRow(self.__rows[nxt], true) end
end

-- -- the box's hooks -----------------------------------------------------------------------------

--- A keystroke: the list is worked out DEBOUNCE after the last one. The keyboard selection goes at
--- once, because until the debounce runs the rows are the old text's.
local function onTyped(h)
  cancelPending(h)
  if h.__sel and h.__rows[h.__sel] then markRow(h.__rows[h.__sel], false) end
  h.__sel = nil
  if not longEnough(h, boxText(h.__box)) then return h:Close() end
  local seq = h.__seq
  after(h.__debounce, function()
    if h.__seq == seq then h:Refresh() end
  end)
end

local function onFocusLost(h)
  -- A debounce still waiting is dropped either way: no list goes up under a box the player left.
  cancelPending(h)
  if not h.__open then return end
  local seq = h.__seq
  if pointerOn(h.__list) then
    -- A press on the list: the box takes the keys back, and a row's click picks on the release.
    return after(0, function()
      if h.__seq == seq and h.__open and h.__box.SetFocus then h.__box:SetFocus() end
    end)
  end
  -- Anywhere else: closed on the next frame, after an Enter or Tab hook that runs behind the host's
  -- own ClearFocus has had the selected row.
  after(0, function()
    if h.__seq == seq and not hasFocus(h.__box) then h:Close() end
  end)
end

local function dispatch(fn)
  return function(box, ...)
    local h = owners[box]
    if h and live(h) then fn(h, ...) end
  end
end

local HOOKS = {
  OnTextChanged = function(h, userInput)
    -- A host's own SetText (a cleared box after a pick, a restored saved view) is not typing.
    if userInput then return onTyped(h) end
    h:Close()
  end,
  OnArrowPressed = function(h, key)
    if key == "DOWN" then h:__Move(1) elseif key == "UP" then h:__Move(-1) end
  end,
  OnEnterPressed = function(h)
    if h.__open and h.__sel then return h:__Pick(h.__sel) end
    h:Close()
  end,
  OnTabPressed = function(h)
    if h.__open then h:__Pick(h.__sel or 1) end
  end,
  OnEscapePressed = function(h) h:Close() end,
  OnEditFocusLost = onFocusLost,
  OnEditFocusGained = function(h)
    if not h.__open and longEnough(h, boxText(h.__box)) then onTyped(h) end
  end,
  OnHide = function(h) h:Close() end,
}
local HOOK_ORDER = { "OnTextChanged", "OnArrowPressed", "OnEnterPressed", "OnTabPressed",
  "OnEscapePressed", "OnEditFocusLost", "OnEditFocusGained", "OnHide" }

local function hookBox(box)
  if hooked[box] then return end
  hooked[box] = true
  for _, script in ipairs(HOOK_ORDER) do box:HookScript(script, dispatch(HOOKS[script])) end
end

local function positive(v, fallback)
  return (type(v) == "number" and v > 0) and v or fallback
end

--- One autocomplete under `editBox`. See the API document for `opts`. Answers a handle, or nil with
--- no client, no box that can be hooked, or no provider.
function lib.Autocomplete(editBox, opts)
  if type(CreateFrame) ~= "function" then return nil end
  if type(editBox) ~= "table" or type(editBox.HookScript) ~= "function" then return nil end
  opts = opts or {}
  if type(opts.provider) ~= "function" then return nil end
  local h = setmetatable({
    __box = editBox, __provider = opts.provider, __onPick = opts.onPick,
    __maxRows = positive(opts.maxRows, AC.MAX_ROWS), __rowH = positive(opts.rowHeight, AC.ROW_H),
    __debounce = max(AC.DEBOUNCE, type(opts.debounce) == "number" and opts.debounce or 0),
    __minChars = positive(opts.minChars, AC.MIN_CHARS),
    __font = opts.font or AC.FONT, __strata = opts.strata or AC.STRATA,
    __rows = {}, __items = {}, __seq = 0, __enabled = true, __open = false,
  }, Handle)
  local previous = owners[editBox]
  if previous then previous:Release() end
  owners[editBox] = h
  hookBox(editBox)
  return h
end
