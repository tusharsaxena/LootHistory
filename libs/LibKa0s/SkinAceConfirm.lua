-- LibKa0s-Skin-1.0 — SkinAceConfirm: AceConfigDialog's confirmation box, for a Ka0s profile page.
--
-- ── WHY IT IS A FILE OF ITS OWN AND NOT MORE OF SkinPaintExtras.lua ──────────────────────────
--
-- Because of `layout-§1`. SkinPaintExtras.lua was 1217 lines, in the band past its re-check trigger,
-- and this section was the seam its census row named, "to a file of its own paired on the Skin
-- shell" (FU-L2 of Ka0sAddonsCommonTasks docs/2026-11-06-FOLLOWUPS_V1_91). It moved here at
-- SkinPaintExtras minor 19, unchanged: the same internal members (`__AceConfirmArm`,
-- `__AceConfirmRaised`, `__AceConfirmHidden`) and the same registry (`__aceConfirm`). Part of the
-- same major, paired on the shell's minor (`__confirmMinor` / `__confirmShellMinor`), and it paints
-- with SkinPaint.lua's helpers (`lib.__P`), so it attaches only when that file attached to the same
-- shell. SkinAce's PaintAceTree, its one caller, resolves `__AceConfirmArm` at call time, so a
-- payload without this file leaves the box stock.

local lib = LibStub and LibStub("LibKa0s-Skin-1.0", true)
if not lib then return end   -- the shell refused (no Core, or below its floor): nothing to attach to
if lib.__paintShellMinor ~= lib.MINOR or not lib.__P then return end   -- no helpers from this copy

local CONFIRM_MINOR = 1
-- Minor 1: the confirmation box, moved here unchanged from SkinPaintExtras.lua (its minor 19).
if lib.__confirmMinor and lib.__confirmMinor >= CONFIRM_MINOR
  and lib.__confirmShellMinor == lib.MINOR then return end
lib.__confirmMinor      = CONFIRM_MINOR
lib.__confirmShellMinor = lib.MINOR

lib.MODULES = lib.MODULES or {}
lib.MODULES.SkinAceConfirm = CONFIRM_MINOR

local prim, P = lib.prim, lib.__P

-- ── AceConfigDialog's confirmation box, for a Ka0s profile page (cause A4) ─────────────────────
--
-- AceConfigDialog keeps ONE popup for the client, and AceDBOptions-3.0 hands every database the SAME
-- `args` table, so neither can be written to for one addon. What is one addon's alone is the group
-- AceDBOptions made for its database. So the first PaintAceTree of a page gives that group its own
-- `args` with its own `delete` row, equal to the shared one but for a `confirm` function that says
-- "this delete is ours" and answers true, which is what AceConfigDialog read from the shared row. No
-- other row moves, and the group keeps it across every redraw of the page; a client-wide table is
-- never written, and an AceDBOptions upgrade taking the shared `args` back only means the next
-- PaintAceTree does this again.
--
-- The box paints when its text is set: AceConfigDialog sets it right after that `confirm`, and
-- measures it right after, so the skin's font is the one it measures. Text set with nothing armed
-- is someone else's use of the box, which is never modal, so a box of ours still open gives itself
-- back first. Hiding gives it back too: every part, recorded by the primitives, and the registry
-- forgets them, so the box is stock when it next opens. The hooks are inert while nothing is painted.
--
-- It is part of the settings panel: nothing paints while the owner ignores its panel. A box another
-- skinning addon already took is left to it. This lives here, not in SkinAce.lua, to keep that file
-- out of layout-§1's 1000-line band; SkinAce's PaintAceTree is the one caller.

local WEAK_KEYS = { __mode = "k" }
-- `rows`: a row of ours -> its owner. `hooked`: a popup -> true. `armed`: the owner whose delete is
-- raising the box right now. `painted`: true while the box wears a skin.
lib.__aceConfirm = lib.__aceConfirm or { rows = setmetatable({}, WEAK_KEYS), hooked = setmetatable({}, WEAK_KEYS) }
local confirmBox = lib.__aceConfirm

local OTHER_SKIN_MARKS = { "isSkinned", "backdrop", "template" }

local function copyTable(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

--- The box's four painted parts, as a list, or nil when AceConfigDialog no longer builds them.
local function confirmParts(popup)
  local text, accept, cancel = P.field(popup, "text", "FontString"), rawget(popup, "accept"), rawget(popup, "cancel")
  if not (text and P.isFrame(accept) and P.isFrame(cancel)) then return nil end
  return { popup, text, accept, cancel }
end

local function takenByOtherSkin(parts)
  for _, part in ipairs(parts) do
    for _, mark in ipairs(OTHER_SKIN_MARKS) do
      if rawget(part, mark) ~= nil then return true end
    end
  end
  return false
end

local function giveConfirmBack(popup)
  confirmBox.painted = nil
  for _, part in ipairs(confirmParts(popup) or {}) do
    local rec = lib.painted[part]
    if rec then
      P.unpaint(rec, part)
      lib:Untrack(part)
    end
  end
end

--- The box for `owner`: `popup.*`, the body text, two buttons, and the client's border faded.
local function paintConfirm(owner, popup)
  local parts = confirmParts(popup)
  if not parts or takenByOtherSkin(parts) then return end
  local text, accept, cancel = parts[2], parts[3], parts[4]
  confirmBox.painted = true
  prim.Panel(owner, popup, { popup = true })
  local rec = lib.painted[popup]
  for _, child in ipairs({ popup:GetChildren() }) do
    if child ~= accept and child ~= cancel and not lib.__ours[child] then P.fade(rec, child) end
  end
  prim.Text(owner, text, "body")
  prim.Button(owner, accept)
  prim.Button(owner, cancel)
end

--- The box's text was set: paint it for an armed owner, else give back whatever it wears. Internal.
function lib.__AceConfirmRaised(popup)
  local owner = confirmBox.armed
  confirmBox.armed = nil
  if owner then return paintConfirm(owner, popup) end
  if confirmBox.painted then giveConfirmBack(popup) end
end

--- The box hid. Internal.
function lib.__AceConfirmHidden(popup)
  confirmBox.armed = nil
  if confirmBox.painted then giveConfirmBack(popup) end
end

--- A hook's body must never raise into AceConfigDialog's own code path.
local function guarded(fn, arg)
  local ok, err = pcall(fn, arg)
  if ok then return end
  local handler = type(geterrorhandler) == "function" and geterrorhandler()
  if type(handler) == "function" then handler("LibKa0s-Skin-1.0 confirm box: " .. tostring(err)) end
end

local function hookConfirm(popup, text)
  if confirmBox.hooked[popup] then return end
  confirmBox.hooked[popup] = true
  hooksecurefunc(text, "SetText", function() guarded(lib.__AceConfirmRaised, popup) end)
  popup:HookScript("OnHide", function(self) guarded(lib.__AceConfirmHidden, self) end)
end

--- `owner`'s delete is about to raise the box.
local function armConfirm(owner)
  local dialog = LibStub("AceConfigDialog-3.0", true)
  local popup = dialog and dialog.popup
  if not P.isFrame(popup) then return end
  local parts = confirmParts(popup)
  if not parts then return end
  hookConfirm(popup, parts[2])
  confirmBox.armed = lib:__PanelSkinned(owner) and owner or nil
end

--- The group holding row `user.option` when that row is AceDBOptions' delete, and its key.
local function deleteRowOf(user)
  local option, path = user.option, user.path
  if type(option) ~= "table" or option.set ~= "DeleteProfile" or type(path) ~= "table" then return nil end
  local group = user.options
  for i = 1, #path - 1 do
    group = type(group) == "table" and type(group.args) == "table" and group.args[path[i]] or nil
  end
  if type(group) ~= "table" or type(group.args) ~= "table" then return nil end
  return group, path[#path]
end

--- True when `group` is the table AceDBOptions made for one database, which nobody else reads.
local function ownGroup(group)
  local dbo = LibStub("AceDBOptions-3.0", true)
  local tables = dbo and dbo.optionTables
  local handler = group.handler
  return type(tables) == "table" and type(handler) == "table" and handler.db ~= nil
    and tables[handler.db] == group
end

--- For PaintAceTree: when `widget` is AceDBOptions' delete row on `owner`'s page, give the row's
--- group its own row that arms the box. Not while it has one, and never on a table AceDBOptions
--- did not make for one database. Internal.
function lib.__AceConfirmArm(owner, widget)
  local user = rawget(widget, "userdata")
  if type(user) ~= "table" then return end
  local group, key = deleteRowOf(user)
  if not group or key == nil then return end
  local row = group.args[key]
  if type(row) ~= "table" or confirmBox.rows[row] or not ownGroup(group) then return end
  local mine = copyTable(row)
  mine.confirm = function()
    guarded(armConfirm, owner)
    return true
  end
  local args = copyTable(group.args)
  args[key] = mine
  confirmBox.rows[mine] = owner
  group.args = args
end
