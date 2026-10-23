Delta: LibKa0s v1.75.1 -> v1.75.2 (span: v1.75.1 v1.75.2)

Written by `LH-RV` of the 2026-10-23 run alongside `docs/revendor/2026-10-23-v1.76.0/`, per
`/dev-copilot:wow-revendor-libka0s` Step 3h: two tags this addon vendored had no bundle.

    horizon=$(ls -1 docs/revendor | sort | head -1 | cut -c1-10)
    # payload commits since the horizon, plus CLAUDE.md commits that roll the provenance line,
    # mapped to the tag their CLAUDE.md names -> vendored.txt
    # each bundle's tag(s) -> recorded.txt
    grep -vxF -f recorded.txt vendored.txt
    v1.75.1
    v1.75.2

    git log --oneline -- libs/LibKa0s tests/_kit CLAUDE.md   (the two re-vendors)
    7df4a87 Re-vendor LibKa0s v1.75.2 (SimPanel minor 4)
    d04e849 Re-vendor LibKa0s v1.75.1 (SimPanel minor 3)
