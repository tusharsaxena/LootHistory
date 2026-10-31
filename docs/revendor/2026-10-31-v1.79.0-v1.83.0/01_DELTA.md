Delta: LibKa0s v1.79.0 -> v1.83.0 (span: v1.79.0 v1.81.0 v1.82.0 v1.83.0)

Written by `FX-LH-DOCS` of the 2026-10-31 findings remediation, per `/dev-copilot:wow-revendor-libka0s`:
four tags this addon vendored had no bundle. The newest recorded bundle is `2026-10-25-v1.78.0`.

    git log --format='%h %s' -G'^Bundles \[LibKa0s\]' -- CLAUDE.md
    c5fc579 LH-F01: Re-vendor LibKa0s v1.83.0, move the outline default to hud, drop the font credits
    051a788 LH-01: Re-vendor LibKa0s v1.82.0 with the skin verb, the Font outline and the facade's two answers
    75c31cd LH-RV: Re-vendor LibKa0s v1.81.0 from the local tag
    5487bf2 LH-02: Re-vendor LibKa0s v1.79.0 from the local tag
    cd757c4 LH-01: Re-vendor LibKa0s v1.79.0 from the skin-overrides-picker branch

    git log --oneline -- libs/LibKa0s tests/_kit   (the re-cuts of v1.83.0, same provenance line)
    1952c06 LH-RV3: Take the re-cut LibKa0s v1.83.0 (LK-A3, the skin picker's rows)
    59dc56d LH-RV2: Take the re-cut LibKa0s v1.83.0 (LK-A1, LK-A2)

v1.80.0 is not in the span's vendored list: the provenance line went from v1.79.0 to v1.81.0, so this
addon never carried that tag on its own. Its changes arrived inside v1.81.0.
