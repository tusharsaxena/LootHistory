-- tests/test_vendor_sync.lua — the vendored-payload gate, now one line of adoption
-- instead of ~150 hand-copied ones. The implementation lives in the payload it
-- checks, at `tests/_kit/vendor_sync.lua`, so a local patch to the kit breaks the
-- kit's own byte-identity assertion — which is the right outcome, because the fix
-- for a kit problem is upstream and re-vendor, never a local edit.
--
-- WHAT IT CHECKS: that `libs/LibKa0s/` and `tests/_kit/` in this repo are exactly
-- what the LibKa0s repo published at the tag THIS README says it bundles.
--
-- THE PROVENANCE LINE IS AN INPUT, NOT A CONSTANT. It is read out of README.md
-- rather than hardcoded: a provenance line and a vendored payload that disagree
-- is precisely the drift this file exists to catch, so the claim has to be the
-- thing under test. Bump the line and the bytes in the same commit. This repo
-- writes that line mid-sentence and lowercase, inside the "Bundled libraries"
-- paragraph; the kit's default pattern accepts both casings, so no override.
--
-- ONE NORMALIZATION, AND ONLY ONE: `git show` hands back the stored blob, which
-- is LF, while the working tree is CRLF because `.gitattributes` pins
-- `*.lua text eol=crlf`. CR is stripped from the working-tree side so the file
-- is compared to the blob it round-trips to. Nothing else is normalized — a real
-- fork in content still fails.
--
-- A MISSING SIBLING CHECKOUT REPORTS A SKIP CARRYING ITS REASON, not a pass. The
-- copy this replaced returned early instead, which registered as PASS — "checked,
-- fine" for a comparison that never ran.
--
-- The case names are unchanged from that copy, deliberately: they are what
-- `docs/test-cases.md` counts, and adopting the shared gate must not move them.

local VendorSync = dofile("tests/_kit/vendor_sync.lua")

VendorSync.register(_G.LH_TEST, {})
