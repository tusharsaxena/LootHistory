-- tests/mock_tooltip_data.lua — an opt-in test double of the client's TooltipDataProcessor, for the
-- holdings block on item and currency tooltips (#34; spec docs/superpowers/specs/
-- 2026-11-27-34-tooltip-holdings-design.md, section 11). Ported from Drop Watcher's
-- tests/mock_tooltip_data.lua and extended with the Currency data type. The kit (tests/_kit/) models
-- no tooltip data processor, so this addon keeps its own, outside the vendored folder.
--
--   local TDP = dofile("tests/mock_tooltip_data.lua")
--   local tdp = TDP.install(T.mocks)             -- plants TooltipDataProcessor and the data types
--   local tip = tdp.tooltip("GameTooltip")       -- a named stand-in tooltip (or ShoppingTooltip1, ...)
--   tdp.show(tip, "Item", { id = 990101 })       -- the client fills it, then runs the Item post calls
--   tdp.texts(tip)                               -- its lines' texts, left and right joined by " | "
--   tdp.uninstall()                              -- puts the mock's own fields back
--
-- WHAT IS MODELED, after the client (Retail's TooltipDataProcessor, which WoW Forever is assumed to
-- carry, FOREVER-17 / FOREVER-18):
--   * TooltipDataProcessor.AddTooltipPostCall(type, fn) keeps `fn` for the data type; there is no
--     removal. handle.postCalls[type] lists them in order.
--   * Enum.TooltipDataType = { Item = 0, Currency = 25 }; handle.dropType("Currency") removes a
--     member for a case (a client without it), and uninstall puts the table back.
--   * handle.show(tip, typeName, data) is one fill: the tooltip is cleared (its lines emptied and its
--     OnTooltipCleared script run, as ClearLines does), shown, its one client line written, then every
--     post call of that type runs with (tip, data); data defaults to { type = <type>, id = 1 }.
--     handle.refresh is the same fill again (clear and refill). handle.repost runs the post calls
--     again WITHOUT a clear (another addon processing the same data twice). handle.hide runs OnHide.
--   * A stand-in tooltip (handle.tooltip(name)) is a mock frame with GetName, AddLine and
--     AddDoubleLine recording `__lines` ({ text, right, r, g, b, rr, rg, rb }), NumLines, ClearLines,
--     Show and Hide, IsForbidden answering `forbidden`, and the base frame's HookScript / HasScript.
--     `shows` counts Show calls and `owners` every SetOwner (the block must never call it).
-- Nothing else of a tooltip is modeled: no reader reads a line's text, so none is offered.

local TDP = {}

TDP.TYPES = { Item = 0, Currency = 25 }

local function decorate(M, tip, name)
  tip.__name = name
  tip.__lines = {}
  tip.forbidden = false
  tip.shows = 0
  tip.owners = {}
  tip.GetName = function(self) return self.__name end
  tip.IsForbidden = function(self) return self.forbidden == true end
  tip.AddLine = function(self, text, r, g, b)
    self.__lines[#self.__lines + 1] = { text = text, r = r, g = g, b = b }
  end
  tip.AddDoubleLine = function(self, left, right, r, g, b, rr, rg, rb)
    self.__lines[#self.__lines + 1] = { text = left, right = right, r = r, g = g, b = b, rr = rr, rg = rg, rb = rb }
  end
  tip.NumLines = function(self) return #self.__lines end
  tip.ClearLines = function(self)
    self.__lines = {}
    self:__fire("OnTooltipCleared")
  end
  tip.HasScript = function() return true end
  tip.SetOwner = function(self, owner, anchor) self.owners[#self.owners + 1] = { owner, anchor } end
  tip.Show = function(self)
    self.__shown, self.shows = true, self.shows + 1
    return self
  end
  tip.Hide = function(self)
    if self.__shown then
      self.__shown = false
      self:__fire("OnHide")
    end
    return self
  end
  tip.IsShown = function(self) return self.__shown == true end
  if name then M[name] = tip end
  return tip
end

--- Install the double on a finished mock; answers the handle (see the header).
--- @param M table the mock
--- @return table
function TDP.install(M)
  local saved = { tdp = rawget(M, "TooltipDataProcessor"), enum = rawget(M, "Enum"), names = {} }
  local enum = setmetatable({}, { __index = saved.enum })
  enum.TooltipDataType = {}
  for k, v in pairs(TDP.TYPES) do enum.TooltipDataType[k] = v end
  M.Enum = enum
  local h = { postCalls = {} }
  M.TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn)
      h.postCalls[kind] = h.postCalls[kind] or {}
      local list = h.postCalls[kind]
      list[#list + 1] = fn
    end,
  }

  function h.tooltip(name)
    if name and saved.names[name] == nil then saved.names[name] = { v = rawget(M, name) } end
    return decorate(M, M.__stubFrame(), name)
  end

  function h.dropType(typeName)
    enum.TooltipDataType[typeName] = nil
  end

  local function post(tip, typeName, data)
    local kind = TDP.TYPES[typeName]
    data = data or { type = kind, id = 1 }
    for _, fn in ipairs(h.postCalls[kind] or {}) do fn(tip, data) end
  end

  function h.show(tip, typeName, data)
    tip:ClearLines()
    tip:Show()
    tip:AddLine(typeName .. " " .. tostring(data and data.id))
    post(tip, typeName, data)
  end
  h.refresh = h.show

  function h.repost(tip, typeName, data)
    post(tip, typeName, data)
  end

  function h.hide(tip)
    tip:Hide()
  end

  function h.texts(tip)
    local out = {}
    for i, line in ipairs(tip.__lines) do
      out[i] = line.right and (tostring(line.text) .. " | " .. tostring(line.right)) or tostring(line.text)
    end
    return out
  end

  function h.count(typeName)
    return #(h.postCalls[TDP.TYPES[typeName]] or {})
  end

  function h.uninstall()
    M.TooltipDataProcessor = saved.tdp
    M.Enum = saved.enum
    for name, s in pairs(saved.names) do M[name] = s.v end
  end

  return h
end

return TDP
