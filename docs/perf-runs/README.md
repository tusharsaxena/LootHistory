# In-game perf runs

The standing store for **in-game** performance captures. A script cannot produce one: a human runs
the addon's perf capture in a live client and exports the record, so these live here rather than in
an automated-test bundle. Offline scenarios are the other half and belong to the run that produced
them, under [`../automated-tests/`](../automated-tests/).

## What is here

Nothing yet. **No in-game capture has been recorded for this addon**, and that is a gap rather than
a clean result — the addon also ships no `tests/perf.lua`, so the offline half is a standing `skip`
in [`../automated-tests/RESULTS.md`](../automated-tests/RESULTS.md) too. Between them, there is no
recorded evidence of this addon's runtime cost from either side, and `performance-§9`'s
zero-overhead claim — that bracketed instrumentation is free when capture is off — has never been
demonstrated here.

## Recording one

One folder per capture, `<YYYYMMDD-HHMMSS>/`, holding the exported record and a short note saying
what was being done in the client while it ran (idle in a city, a raid pull, a loot-heavy dungeon
clear) — a number with no scenario attached cannot be compared to the next one. Captures are frozen
once written, on the same terms as an automated-test bundle: if a reading was wrong, the next one
says so.
