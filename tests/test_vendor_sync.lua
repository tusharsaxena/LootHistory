-- tests/test_vendor_sync.lua — the vendored-payload gate, now one line of adoption
-- instead of ~150 hand-copied ones. The implementation lives in the payload it
-- checks, at `tests/_kit/vendor_sync.lua`, so a local patch to the kit breaks the
-- kit's own byte-identity assertion — which is the right outcome, because the fix
-- for a kit problem is upstream and re-vendor, never a local edit.
--
-- WHAT IT CHECKS: that `libs/LibKa0s/` and `tests/_kit/` in this repo are exactly
-- what the LibKa0s repo published at the tag THIS REPO'S `CLAUDE.md` says it
-- bundles.
--
-- THE PROVENANCE LINE IS AN INPUT, NOT A CONSTANT. It is read out of CLAUDE.md
-- rather than hardcoded: a provenance line and a vendored payload that disagree
-- is precisely the drift this file exists to catch, so the claim has to be the
-- thing under test. Bump the line and the bytes in the same commit. Kit revision
-- 9 moved that input out of README.md, which is the player's page and no longer
-- carries a library inventory at all, and there is deliberately no fallback: a
-- repo that re-vendors without moving its line fails here rather than sitting
-- half-migrated with two lines that can disagree. This repo writes the line
-- under `## Vendored LibKa0s`; `provenanceFile` already defaults to CLAUDE.md,
-- so no override.
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
-- CASE NAMES ARE INVENTORY. `docs/test-cases.md` pins them, so the kit moving a
-- name is a change visible outside `tests/_kit/`: revision 9 renamed the first
-- case from "the README says" to "CLAUDE.md says", and the inventory has to be
-- regenerated in the same commit. The count does not move — a rename is not a
-- count change.

local VendorSync = dofile("tests/_kit/vendor_sync.lua")

VendorSync.register(_G.LH_TEST, {})
