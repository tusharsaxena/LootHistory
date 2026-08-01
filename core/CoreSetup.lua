local addonName, NS = ...

-- LibKa0s-Core-1.0 seam: the secret-safe stringifier and the shared cyan-[LH] chat printer.
--
-- These two were this addon's own until now (core/Util.lua), and they were already the reference
-- implementation — the same `table.concat` probe and the same "<secret>" sentinel the library
-- ships. Adopting Core is therefore a pure refactor at the seam: every rendered byte is unchanged,
-- and what is gained is that one implementation now serves the whole collection.
--
-- The WINDOW CHROME half of Core (SKIN / MakeCloseButton / ApplySkin) is deliberately NOT adopted.
-- This addon draws every window with its own flat 1px WHITE8X8 double border, a synthesised inner
-- border, a gold title tint and a 24x24 class-coloured close glyph (modules/Browser.lua) — a
-- different design from Core's 12px UI-Tooltip-Border and 18x18 fixed-red x. Taking Core's skin
-- would redesign the History window; the console keeps this addon's chrome through DebugLog's
-- applySkin / makeCloseButton descriptor hooks instead. See docs/pending/LEDGER.md, LIBKA0S-02.
--
-- ── LOAD ORDER (all four constraints bind; see docs/module-map.md) ──────────────────────────────
--   AFTER  core/Namespace.lua   — NS.PREFIX is the tag, passed verbatim as a plain string.
--   AFTER  core/Util.lua        — that file publishes NS.Util, which this one writes `print` onto.
--   BEFORE core/LootHistory.lua — its AceConsole reclaim reads NS.Util.print back over NS.Print
--                                 (architecture-§2). Publishing to BOTH keys is what makes that
--                                 reclaim restore the library printer rather than undo this seam.
--   BEFORE every file taking the printer as a load-time upvalue — modules/Browser.lua,
--                                 settings/Schema.lua, settings/Slash.lua, settings/Panel.lua each
--                                 do `local print = NS.Print` at file scope, so a later seam would
--                                 leave them holding the old function while appearing to work.

local lib = LibStub and LibStub("LibKa0s-Core-1.0", true)

-- The shared cause clause, defined here because core/CoreSetup.lua is the first of the LibKa0s
-- seams the TOC loads and every later seam appends its own consequence to it. Set OUTSIDE the
-- `if not lib` branch on purpose: the other seams read it on BOTH paths, so a degraded install and
-- a healthy one give the same explanation of WHY and differ only in WHAT is unavailable.
NS.LIBKA0S_MISSING = "The LibKa0s library is missing from this installation of Ka0s Loot History " ..
  "(expected in libs/LibKa0s)"

if not lib then
  -- A missing vendored library must degrade, not error at load: recording loot does not need a
  -- shared printer. The stub therefore has to answer EVERY member this addon calls — five keys,
  -- across ~40 call sites and four load-time upvalue captures — because a partial stub fails later
  -- and further from the cause than a Lua error at load would.
  local function safeToString(v)
    if v == nil then return "nil" end
    if type(v) == "boolean" then return tostring(v) end
    if (pcall(function() return table.concat({ v }) end)) then return tostring(v) end
    return "<secret>"
  end

  -- Announced ONCE, on the first line the addon prints, rather than at load: a notice emitted
  -- during ADDON_LOADED lands before the chat frame is showing anything a user reads.
  local announced = false
  local function emit(line)
    if not announced then
      announced = true
      if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(NS.PREFIX .. " " .. NS.LIBKA0S_MISSING ..
          "; running on reduced built-in fallbacks.")
      end
    end
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(line) end
  end

  NS.IsConcatSafe = function(v) return (pcall(function() return table.concat({ v }) end)) end
  NS.SafeToString = safeToString
  NS.Print = function(...)
    local parts = { NS.PREFIX }
    for i = 1, select("#", ...) do parts[i + 1] = safeToString((select(i, ...))) end
    emit(table.concat(parts, " "))
  end
  NS.Format = function(fmt, ...)
    local n = select("#", ...)
    if n == 0 then return NS.Print(fmt) end
    local parts = {}
    for i = 1, n do parts[i] = safeToString((select(i, ...))) end
    NS.Print(safeToString(fmt):format(unpack(parts)))
  end
  NS.Util = NS.Util or {}
  NS.Util.print = NS.Print
  return
end

-- ── the live seam ──────────────────────────────────────────────────────────────────────────────

-- Lib-level and stateless, so they are published by reference rather than wrapped. Identical in
-- behaviour to the implementations they replace, down to the sentinel: `lib.SECRET` is "<secret>",
-- which is the string docs/conventions.md and ~6 test cases already name.
NS.IsConcatSafe = lib.IsConcatSafe
NS.SafeToString = lib.SafeToString

-- `prefix` is the plain string, not the function form: core/Namespace.lua defines NS.PREFIX two
-- files earlier, so there is no load-order window to survive. `sep` is left at its default single
-- space because the tag carries none of its own ("|cff00ffff[LH]|r").
local printer = lib:New({ prefix = NS.PREFIX })

-- Plain functions, never methods — every consumer does `local print = NS.Print` at file scope and
-- calls it bare, so neither may need a `self`.
NS.Print  = printer.Print
NS.Format = printer.Format

-- The real name. core/LootHistory.lua restores NS.Print from here after AceConsole's Embed
-- clobbers it, so this assignment is what makes the reclaim reach the library printer.
NS.Util = NS.Util or {}
NS.Util.print = NS.Print
