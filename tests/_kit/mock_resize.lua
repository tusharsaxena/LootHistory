-- testkit/mock_resize.lua — a frame's resize surface (revision 33).
--
-- LibKa0s v1.64.0 makes the debug console, every copy window and the perf panel resizable from a
-- bottom-right grip (`Core.MakeResizable`). Until this revision every one of the calls that takes
-- answered from `mock_base.lua`'s metatable, which hands back the frame itself: `IsResizable()` and
-- `IsUserPlaced()` came back truthy whatever the frame had been told, `GetResizeBounds()` answered a
-- table where the client answers four numbers, and nothing remembered that sizing ever started.
-- A suite could not tell a resizable window from a fixed one (fidelity rules 1 and 3).
--
-- What is modeled, and the client behavior each one follows:
--
--   * `SetResizable` / `IsResizable` — a boolean, false until set, as a new frame is in the client.
--   * `SetResizeBounds` / `GetResizeBounds` — the four numbers as given, answered as four numbers.
--     A frame never bounded answers four zeros.
--   * `StartSizing(point)` — records the point and a count, and marks the frame USER-PLACED, as
--     `StartMoving` below does. The client flags a frame the player moved or sized so that its
--     layout cache (`layout-local.txt`) keeps the frame's anchor and size across a /reload, and a
--     window that wants neither to survive has to clear the flag after `StopMovingOrSizing`. That
--     is the edge LibKa0s's grip handles, so the mock has to reproduce the flag or a suite cannot
--     see the grip handle it.
--   * `StartMoving` — the same flag, and nothing else. Through revision 32 it was a metatable no-op.
--   * `StopMovingOrSizing` — clears the in-progress point and counts the stop.
--   * `SetUserPlaced` / `IsUserPlaced` — a boolean, false until something sets it.
--
-- What is NOT modeled, deliberately. `StartSizing` does not change the frame's size: in the client
-- the size follows the cursor frame by frame, and a suite that wants a new size states it
-- (`__setGeom`) and fires `OnSizeChanged` itself, the way the Options suites already drive a
-- relayout. `SetSize` / `SetWidth` / `SetHeight` stay undefined and so do not fire `OnSizeChanged`:
-- `mock_base.lua` leaves the setters off the frame on purpose, so a test can rawset a recorder over
-- one and rawset nil to restore, and the client runs `OnSizeChanged` from its layout pass rather
-- than inside the setter, so a synchronous fire would be a re-entrancy the client never has.
-- Neither the client's raise on sizing a frame that is not resizable nor its layout cache itself is
-- modeled; a /reload cannot be simulated headlessly, and the in-game smoke checks own that edge.
--
-- Loaded by `mock_base.lua` from its own folder, like `mock_events.lua`, and a file of its own for
-- the same reason: `mock_base.lua` sits near `layout-§1`'s 1500-line cap. It answers one function,
-- `decorateFrame(f)`, which every tracked frame passes through as it is made.

local Resize = {}

--- Give one frame the recording resize surface. Plain fields, so a suite can read them directly:
--- `__resizable`, `__resizeBounds`, `__sizing` (the point while sizing), `__sizingCount`,
--- `__stopCount` and `__userPlaced`.
function Resize.decorateFrame(f)
  f.__resizable, f.__userPlaced = false, false
  f.__sizingCount, f.__stopCount = 0, 0

  function f:SetResizable(v) self.__resizable = not not v; return self end
  function f:IsResizable() return self.__resizable end

  function f:SetResizeBounds(minW, minH, maxW, maxH)
    self.__resizeBounds = { minW, minH, maxW, maxH }
    return self
  end
  function f:GetResizeBounds()
    local b = self.__resizeBounds
    if not b then return 0, 0, 0, 0 end
    return b[1], b[2], b[3], b[4]
  end

  function f:StartSizing(point)
    self.__sizing = point or "BOTTOMRIGHT"
    self.__sizingCount = self.__sizingCount + 1
    self.__userPlaced = true
    return self
  end
  function f:StartMoving() self.__userPlaced = true; return self end
  function f:StopMovingOrSizing()
    self.__sizing = nil
    self.__stopCount = self.__stopCount + 1
    return self
  end

  function f:SetUserPlaced(v) self.__userPlaced = not not v; return self end
  function f:IsUserPlaced() return self.__userPlaced end
  return f
end

return Resize
