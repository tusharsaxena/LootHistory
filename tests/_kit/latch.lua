-- testkit/latch.lua — the slash-commands-§7 step-10 hold-ordering helper (kit revision 39).
--
-- WHY. Step 10 of the disabled-state conformance suite is the latch case: take the perf hold and
-- set `enabled = false`, release perf, assert the addon is STILL down; then the reverse order. It is
-- the trap the two-hold latch exists for (a resume or an enable that calls a bare stand-up brings the
-- addon back under the other hold), and every addon in the collection wrote it by hand, each with
-- its own seams. This is the one form the kit ships.
--
-- SURFACE, on the kit table and published by `Kit.expose`:
--
--   Kit.assertLatchHoldOrder(opts)
--
--     opts.lifecycle   the latch: an object answering Hold(key), Release(key) and IsHeld(key) —
--                      the addon's `LibKa0s-Lifecycle-1.0` instance (NS.Lifecycle)
--     opts.perfHold    the perf hold's key, normally `LibKa0s-Lifecycle-1.0`'s HOLD_PERF ("perf")
--     opts.setEnabled  function(bool): the addon's single enable write seam, the one the
--                      `/<slash> enable` and `disable` verbs and the settings toggle all reach
--     opts.regSet      function(): the live registration set, as an array. An entry is a string
--                      key, or a table shaped like `M.__registrations()`'s rows
--                      ({ target, kind, event, unit }), keyed by all four
--     opts.key         optional function(entry) -> string, overriding how an entry is keyed
--     opts.label       optional string, leading every failure message (the addon's name)
--
--   Order A: capture R_on (asserted non-empty); hold perf; setEnabled(false); release perf; assert
--   the set is EMPTY ("still stood down"); setEnabled(true); assert the set equals R_on.
--   Order B: setEnabled(false); hold perf; setEnabled(true); assert EMPTY; release perf; assert the
--   set equals R_on.
--
--   "Equals R_on" is compared BY KEY, sorted, never by count alone: a stand-up that rebuilds the
--   same number of registrations under different names or units is the snapshot-rebuild defect
--   (performance-§6's restore-from-current-state rule seen from the other side).
--
-- RESTORE. Each order runs under pcall. Whatever happens, the helper releases the perf hold and
-- calls setEnabled(true) before returning or re-raising, so a failing order leaves no hold taken and
-- the next case starts from an enabled addon. A failure names its order ("order A" / "order B").
--
-- THE HOLD IS TAKEN DIRECTLY. In a real addon the perf hold arrives through `LibKa0s-Perf-1.0`'s
-- P.Suspend. The invariant under test is the latch's, not the harness's, so the helper holds and
-- releases through the latch object, as the hand-written cases it replaces did; a suite that wants
-- the P.Suspend route as well drives it in a case of its own.
--
-- WHAT IT DOES NOT DO. It never reaches into the addon's namespace (every seam is injected), and it
-- does not replace the testing-§12 falsification comment: the consumer keeps its
-- `-- red under: ...` line at the call site, naming the defect that turns its own case red.
--
-- SHAPE. Returns `function(Kit)`, which installs the member on the kit table it is handed.
-- `framework.lua` loads it once, from its own folder, beside `secrets.lua`; it is not a module a
-- suite loads on its own.

return function(Kit)
  local function keyOf(entry, custom)
    if custom then return tostring(custom(entry)) end
    if type(entry) == "table" then
      return table.concat({ tostring(entry.target), tostring(entry.kind), tostring(entry.event),
                            tostring(entry.unit) }, "|")
    end
    return tostring(entry)
  end

  local function keys(list, custom)
    local out = {}
    for i, entry in ipairs(list or {}) do out[i] = keyOf(entry, custom) end
    table.sort(out)
    return out
  end

  local REQUIRED = {
    { "lifecycle", "table" }, { "perfHold", "string" }, { "setEnabled", "function" }, { "regSet", "function" },
  }

  --- Run slash-commands-§7 step 10 against one addon's latch, in both orders. Raises on the first
  --- failed assertion, naming the order; returns the sorted key list of R_on on success.
  function Kit.assertLatchHoldOrder(opts)
    if type(opts) ~= "table" then Kit.fail("assertLatchHoldOrder: opts must be a table", 2) end
    for _, req in ipairs(REQUIRED) do
      if type(opts[req[1]]) ~= req[2] then
        Kit.fail("assertLatchHoldOrder: opts." .. req[1] .. " must be a " .. req[2], 2)
      end
    end
    local lc, perf, setEnabled = opts.lifecycle, opts.perfHold, opts.setEnabled
    local prefix = (opts.label and (tostring(opts.label) .. ": ") or "") .. "slash-commands-§7 step 10, "
    local function current() return keys(opts.regSet(), opts.key) end

    local R_on = current()
    if #R_on == 0 then
      Kit.fail(prefix .. "baseline: R_on must be non-empty - an addon that registers nothing when "
        .. "enabled passes every later assertion trivially", 2)
    end
    local want = table.concat(R_on, "\n")

    local function down(order, why)
      local now = current()
      if #now ~= 0 then
        error(prefix .. order .. ": " .. why .. " (still registered: " .. table.concat(now, ", ") .. ")", 0)
      end
    end
    local function up(order, why)
      local got = table.concat(current(), "\n")
      if got ~= want then
        error(prefix .. order .. ": " .. why .. " - the registration set differs from R_on (wanted ["
          .. table.concat(R_on, ", ") .. "], got [" .. table.concat(current(), ", ") .. "])", 0)
      end
    end

    local function restore()
      pcall(lc.Release, lc, perf)
      pcall(setEnabled, true)
    end

    local function run(order, body)
      local ok, err = pcall(body, order)
      restore()
      if not ok then error(err, 0) end
    end

    run("order A (perf held first)", function(order)
      lc:Hold(perf)
      setEnabled(false)
      lc:Release(perf)
      down(order, "releasing perf resurrected an addon the player had disabled")
      setEnabled(true)
      up(order, "the last hold released, the addon must stand up")
    end)

    run("order B (disabled first)", function(order)
      setEnabled(false)
      lc:Hold(perf)
      setEnabled(true)
      down(order, "enabling resurrected an addon the perf hold was holding down")
      if not lc:IsHeld(perf) then error(prefix .. order .. ": the perf hold is no longer taken", 0) end
      lc:Release(perf)
      up(order, "the last hold released, the addon must stand up")
    end)

    return R_on
  end
end
