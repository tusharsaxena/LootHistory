-- LibKa0s-Lifecycle-1.0 — the stand-down latch: one addon, many reasons to be inert, ONE way down
-- and ONE way back up.
--
-- Every addon in this collection already owns the machinery to make itself genuinely inert. It was
-- built for the perf module's second arm — unregister the events, cancel the tickers, let the show
-- ladder answer no — and it is tested, and it works. Disable declined to use it: eleven addons
-- implement "disabled" as a draw gate, so the frames go away and the client still walks the
-- addon's registration list on every UNIT_AURA in a twenty-five-man raid, still builds the
-- argument frame, still enters Lua, still runs the comparison that decides to leave. That cost is
-- precisely what a player switching an addon off is trying to stop paying, and it is invisible
-- from every surface they can see — which is how the draw gate survived eleven audits looking
-- identical to standing down.
--
-- The fix is not a second teardown path beside the perf one. A second path is the anti-pattern:
-- two mechanisms that both mean "be inert" drift, and the day they disagree the addon is half
-- down — some events unregistered, some frames still drawn — which is a state nobody designed and
-- no test covers. The fix is that BOTH reasons become NAMED HOLDS on the one latch this file is.
--
-- WHY A LATCH AND NOT A BOOLEAN. Two independent reasons to be down means four states, and the
-- interesting one is the state a boolean cannot represent: the addon is perf-suspended AND the
-- player has disabled it, the perf run finishes, and `resume` runs. With a boolean, resume writes
-- `false` and the addon comes back to life under a player who switched it off. With a hold set,
-- releasing `perf` leaves `disabled` taken, the set is still non-empty, and nothing is rebuilt.
-- RELEASING ONE HOLD MUST NOT RESURRECT AN ADDON THE OTHER IS STILL HOLDING DOWN, and that
-- sentence is the whole reason this major exists.
--
-- WHAT THIS FILE DELIBERATELY DOES NOT DO. It does not know what a frame is, what an event is, or
-- what the host stores. It owns the SET and the EDGE and nothing else: the host's `standDown` is
-- what unregisters, and the host's `standUp` is what rebuilds — from CURRENT state, never from a
-- snapshot taken on the way down, because a setting can be changed while the addon is down and the
-- rebuild has to reflect the setting as it is now (performance-§6). There is no `:StandUp()`
-- member, and its absence is a feature: a bare stand-up is exactly the bug the latch exists to
-- prevent, so the only route out is releasing the hold that put the addon down.
--
-- It persists NOTHING. No SavedVariables reference, no state that survives a reload. The
-- `disabled` hold is re-taken at load from the stored enable path, because surviving a reload is
-- the entire point of that setting; the `perf` hold is session-only and re-taking it across a
-- reload would leave a player's addon dead with no visible cause.
--
-- Depends on LibStub and LibKa0s-Core-1.0, and on no addon framework.

-- The Core floor, declared even though not one member of Core is called below. It is a
-- LOAD-PAYLOAD check, not a dependency check (library-stack-§7): a host holding a partial vendored
-- copy — Core missing, or older than this file was built against — must end up with EVERY module
-- of the payload absent rather than with a working Lifecycle beside an absent Slash. A mixed set is
-- the state that raises in the client and nowhere else, because the missing half is only reached on
-- the path the degradation arm exists for. Returning before NewLibrary is what makes the absence
-- uniform, so the host's own stub answers for all of it.
local core = LibStub and LibStub("LibKa0s-Core-1.0", true)
local NEEDS_CORE = 1
if not core or (core.MINOR or 0) < NEEDS_CORE then return end   -- no NewLibrary; module absent

local MAJOR, MINOR = "LibKa0s-Lifecycle-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR

-- Which version of each FILE in this major is actually live, so version skew is discoverable at
-- runtime rather than by reading source. See docs/releasing.md.
lib.MODULES = lib.MODULES or {}
lib.MODULES.Lifecycle = MINOR

-- ── the reserved keys ──────────────────────────────────────────────────────────────────────
--
-- The key space belongs to the host; these two do not, because two majors and every host in the
-- collection have to spell them the same way or the latch silently holds two different addons
-- down for two different reasons. `disabled` is taken from the stored enable path and persists
-- across a reload by being re-taken at load; `perf` is taken by LibKa0s-Perf-1.0's suspend arm and
-- is session-only. Exported rather than left as literals so LibKa0s-Perf-1.0, a host's stand-down
-- wiring and a conformance suite all read the same string rather than three copies of it.
lib.HOLD_DISABLED = "disabled"
lib.HOLD_PERF     = "perf"

--- Create the latch for one addon. ONE INSTANCE PER ADDON — a second instance is a second latch
--- with its own hold set, which is the parallel-lifecycle anti-pattern arriving by accident.
---
--- Descriptor fields:
---   name       string    required. The addon folder name. Diagnostic output only: nothing here
---                        branches on it, and nothing here prints it unless a line is asked for.
---   standDown  function  required. Called with NO arguments when the hold set goes from EMPTY to
---                        NON-EMPTY. The host does its teardown here — every RegisterEvent,
---                        RegisterUnitEvent, RegisterMessage and RegisterBucketEvent it owns
---                        actually unregistered, every timer and OnUpdate canceled, its show
---                        ladder answering no at the source.
---   standUp    function  required. Called with NO arguments when the hold set goes from
---                        NON-EMPTY to EMPTY. The host rebuilds FROM CURRENT STATE.
---   print      function  optional. The host's tagged printer, used only by :PrintHolds(). The
---                        library emits nothing on its own — a latch that announced every edge
---                        would narrate a perf run and a profile switch into a player's chat.
function lib:New(descriptor)
  local d = type(descriptor) == "table" and descriptor or {}
  if type(d.name) ~= "string" or d.name == "" then
    error(MAJOR .. ":New requires descriptor.name — the addon folder name", 2)
  end
  if type(d.standDown) ~= "function" then
    error(MAJOR .. ":New requires descriptor.standDown — the host's teardown", 2)
  end
  if type(d.standUp) ~= "function" then
    error(MAJOR .. ":New requires descriptor.standUp — the host's rebuild, from current state", 2)
  end

  -- The set, and a count beside it. The count is not an optimization: `next(holds) == nil` would
  -- answer the same question, and the count is what makes :IsDown() a plain comparison that no
  -- amount of key churn can make lie.
  local holds, taken = {}, 0
  -- What the host was last TOLD. It is not `taken > 0` — it is the edge the callbacks have
  -- actually seen — and keeping the two separate is what makes an edge fire exactly once.
  local down = false

  local LC = {}
  LC.name = d.name

  --- Fire the edge, if there is one. Returns true when a callback ran.
  ---
  --- THE SET IS ALREADY MUTATED WHEN THIS IS CALLED, and `down` is updated BEFORE the callback is
  --- invoked rather than after. That ordering is a hard invariant with a test: a host callback that
  --- raises must not leave the latch inconsistent. Update-after would mean a throwing `standUp`
  --- leaves the latch believing the addon is still down with an empty hold set, so the next
  --- `Hold` fires no `standDown` and the addon is stranded half-alive with no hold to release.
  --- Update-before means a throwing `standUp` still leaves the set empty and the latch up: the
  --- error reaches the host's own error handler, and the NEXT hold behaves correctly.
  local function edge()
    local wanted = taken > 0
    if wanted == down then return false end
    down = wanted
    if wanted then d.standDown() else d.standUp() end
    return true
  end

  --- Take `key`. A key already held is a NO-OP and MUST NOT call `standDown` again — two modules
  --- reaching the same conclusion is the ordinary case, not an error, and a second teardown on a
  --- torn-down addon is how an unregister loop over a table that is already empty becomes an
  --- unregister loop over a table someone rebuilt in between.
  ---
  --- Returns true when this call is what stood the addon down.
  function LC:Hold(key)
    if type(key) ~= "string" or key == "" then
      error(MAJOR .. ":Hold requires a non-empty string key", 2)
    end
    if holds[key] then return false end
    holds[key], taken = true, taken + 1
    return edge()
  end

  --- Release `key`. A key that is not held is a NO-OP and MUST NOT call `standUp`: that is the
  --- bare stand-up this major exists to make unreachable, and it is reachable by accident every
  --- time a teardown path releases a hold it never took.
  ---
  --- Returns true when this call is what stood the addon back up.
  function LC:Release(key)
    if type(key) ~= "string" or key == "" then
      error(MAJOR .. ":Release requires a non-empty string key", 2)
    end
    if not holds[key] then return false end
    holds[key], taken = nil, taken - 1
    return edge()
  end

  --- Hold or release by a boolean, which is the shape a settings onChange actually has. A host
  --- binds its enable path to `lc:Set("disabled", not enabled)` and never writes the branch itself
  --- — a branch written per host is a branch one host writes backwards.
  function LC:Set(key, held)
    if held then return self:Hold(key) end
    return self:Release(key)
  end

  function LC:IsHeld(key) return holds[key] == true end

  --- Is the addon stood down — is the hold set non-empty? The question LibKa0s-Perf-1.0 asks
  --- instead of keeping a `suspended` boolean of its own, and the question a host's show ladder
  --- asks at its first rung.
  function LC:IsDown() return taken > 0 end

  --- A FRESH sorted array of the held keys, for tests and debug output. Fresh and sorted are both
  --- load-bearing: handing back the internal table would let a caller mutate the hold set by
  --- writing to what looks like a report, and `pairs` order is not an order — a suite asserting on
  --- an unsorted list passes or fails on someone else's hash seed.
  function LC:Holds()
    local out = {}
    for key in pairs(holds) do out[#out + 1] = key end
    table.sort(out)
    return out
  end

  --- Re-run the empty/non-empty decision, firing a callback only on an ACTUAL edge. Idempotent, so
  --- a host may call it as often as it likes.
  ---
  --- What it is for: a profile switch. AceDB's OnProfileChanged / OnProfileCopied / OnProfileReset
  --- can flip the stored enable path under the addon without any verb or checkbox being touched,
  --- so the host re-reads the path, calls `:Set("disabled", not enabled)` and then this — and gets
  --- a stand-down or a stand-up only if the new profile actually disagrees with the old one.
  function LC:Reevaluate() return edge() end

  --- The ONE line this library ever prints, and only when a host asks for it. Held keys or
  --- `(none)`, through the host's own tagged printer so it carries the host's prefix like every
  --- other line the addon emits. A latch that narrated its own edges would print into a player's
  --- chat on every perf window and every profile switch.
  function LC:PrintHolds()
    if type(d.print) ~= "function" then return false end
    local list = self:Holds()
    d.print(("%s: %s"):format(taken > 0 and "stood down, holds" or "up, no holds",
      #list > 0 and table.concat(list, ", ") or "(none)"))
    return true
  end

  return LC
end
