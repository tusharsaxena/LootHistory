# 02 — Candidates

## What v1.25.0 added

One surface, in one file.

**`O.MasterControls` takes `leadButton = { text, tooltip, onClick }`** —
`LibKa0s/docs/api/Options/version-14.13.2.3-docs.md`, *"`leadButton` … is ONE act of the
host's own, closing the tab beside the resets"*. One act of the host's own, drawn beside
`options-ui-§15`'s reset buttons: into the pair's empty right half on a **frameless**
addon, or on its own row above the full pair on a **framed** one.

It exists because §15 fixes the resets' wording and the composer is the only thing that
writes it, so an addon wanting a button beside them had to keep a second copy of
*"Reset all settings"* in its own source. PrettyChat's *Test* is the caller it was cut for.

## Classification for this addon

| Class | Meaning | This release |
|---|---|---|
| A — delivered | reaches the addon on the copy alone | — |
| B — host change | a new surface to call | `leadButton`, **not applicable here** |
| C — whole module | a major this addon does not consume | — |

**`leadButton` is not offered, and the reason is structural rather than a preference.**
This addon passes the composer's `afterGroup` tail through unchanged — it has no single
page-wide act of its own sitting beside the resets for the seam to place. A `leadButton`
with nothing to put in it is a field set to nil.

**No candidates. No interview, and nothing filed as a decline** — a decline is a decision
about work that was offered, and nothing was.

If this addon later grows one page-wide verb that belongs beside the resets, this is the
seam for it, and it needs no library change: the field is already in the payload this run
carried down.
