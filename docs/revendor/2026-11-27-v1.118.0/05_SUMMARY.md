# Summary

- LibKa0s v1.114.0 -> v1.118.0 (base from `CLAUDE.md:60`). Minors moved: ForeverDB 1 -> 4, Media 13 -> 14;
  kit revision 62 -> 65.
- Delivered free (class A): nothing visible to this addon.
- Blockers fixed in the re-vendor commit: version pins in `tests/test_libka0s.lua`, and the peel of its
  release cases into `tests/test_libka0s_releases.lua` at the layout cap.
- Icons: declaration kept (23); prune removed the rest of the catalog and all 362 sound files. Credits unchanged.
- Adopted: none. Declined: none filed (owner pre-decided; see 03).
- Gate: `lua tests/run.lua` 2185 passed / 0 failed / 1 skipped; `KA0S_KIT_CLIENT=forever lua tests/run.lua`
  2164 passed / 0 failed / 22 skipped; `luacheck .` 0/0; `pytest tools/seeds` 17 passed.
