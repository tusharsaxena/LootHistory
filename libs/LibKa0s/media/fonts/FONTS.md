# The faces in this folder

Each face's source, its copyright as its own name table reads, its license and any owner ruling it
ships on. `Media.lua`'s `FONTS` table is the catalog, keyed by the LibSharedMedia key.
`tools/artwork/fonts.py` in the LibKa0s repository pins the SHA-256 of what each face is taken from:
a face copied unchanged is pinned byte for byte, and an instanced face (Nunito, Vollkorn, Bitter,
Oxanium, Inter) through its upstream variable font and the axis values it is cut at, not its own
bytes. JetBrains Mono came with the library and that tool does not cover it.

Every face here stays in the payload whether or not a skin names it (owner, 2026-10-31).

The license files that exist sit beside the faces. A face with no license file names this record as
its `license`, because nothing that could be shipped grants it.

## SIL Open Font License 1.1

Each family's `*-OFL.txt` is upstream's text. Source: google/fonts at a pinned commit, except
JetBrains Mono, which came with the library from Mythic Meters.

| File | Key | Family source | Copyright (name table) | License file |
|---|---|---|---|---|
| `JetBrainsMono-Regular.ttf` | JetBrains Mono | <https://github.com/JetBrains/JetBrainsMono> | Copyright 2020 The JetBrains Mono Project Authors | `JetBrainsMono-OFL.txt` |
| `Nunito-Regular.ttf` | Ka0s Nunito | <https://github.com/googlefonts/nunito> | Copyright 2014 The Nunito Project Authors | `Nunito-OFL.txt` |
| `Nunito-SemiBold.ttf` | Ka0s Nunito SemiBold | as above | as above | `Nunito-OFL.txt` |
| `Vollkorn-Regular.ttf` | Ka0s Vollkorn | <https://github.com/FAlthausen/Vollkorn-Typeface> | Copyright 2018 The Vollkorn Project Authors | `Vollkorn-OFL.txt` |
| `Vollkorn-Bold.ttf` | Ka0s Vollkorn Bold | as above | as above | `Vollkorn-OFL.txt` |
| `Bitter-Regular.ttf` | Ka0s Bitter | <https://github.com/solmatas/BitterPro> | Copyright 2011 The Bitter Project Authors | `Bitter-OFL.txt` |
| `Bitter-Bold.ttf` | Ka0s Bitter Bold | as above | as above | `Bitter-OFL.txt` |
| `Philosopher-Regular.ttf` | Ka0s Philosopher | <https://github.com/alexeiva/philosopher> | Copyright 2011 The Philosopher Project Authors | `Philosopher-OFL.txt` |
| `Philosopher-Bold.ttf` | Ka0s Philosopher Bold | as above | as above | `Philosopher-OFL.txt` |
| `Oxanium-SemiBold.ttf` | Ka0s Oxanium SemiBold | <https://github.com/sevmeyer/oxanium> | Copyright 2019 The Oxanium Project Authors | `Oxanium-OFL.txt` |
| `Oxanium-Bold.ttf` | Ka0s Oxanium Bold | as above | as above | `Oxanium-OFL.txt` |
| `Inter-Regular.ttf` | Ka0s Inter | <https://github.com/rsms/inter> | Copyright 2020 The Inter Project Authors | `Inter-OFL.txt` |
| `Inter-SemiBold.ttf` | Ka0s Inter SemiBold | as above | as above | `Inter-OFL.txt` |
| `FiraSans-Regular.ttf` | Ka0s Fira Sans | <https://github.com/mozilla/Fira> | Digitized data copyright 2012-2016, The Mozilla Foundation and Telefonica S.A. | `FiraSans-OFL.txt` |
| `FiraSans-Medium.ttf` | Ka0s Fira Sans Medium | as above | as above | `FiraSans-OFL.txt` |
| `FiraSans-SemiBold.ttf` | Ka0s Fira Sans SemiBold | as above | as above | `FiraSans-OFL.txt` |
| `AtkinsonHyperlegible-Regular.ttf` | Ka0s Atkinson | <https://www.brailleinstitute.org/freefont/> | Copyright 2020 Braille Institute of America, Inc. | `AtkinsonHyperlegible-OFL.txt` |
| `AtkinsonHyperlegible-Bold.ttf` | Ka0s Atkinson Bold | as above | as above | `AtkinsonHyperlegible-OFL.txt` |

Nunito, Vollkorn, Bitter, Oxanium and Inter are changed from the originals: static instances cut from upstream's
variable fonts at the weights named, each renamed for its weight, no glyph edited. Their license files
say so above the license text.

## Apache License 2.0

The five faces come unchanged from the Sorted add-on in the owner's WoW install, and each name table
reads "Licensed under the Apache License, Version 2.0". `OpenSans-Apache-2.0.txt` is that text. "Open
Sans is a trademark of Google and may be registered in certain jurisdictions."

| File | Key | Copyright (name table) |
|---|---|---|
| `OpenSans-Regular.ttf` | Ka0s Open Sans | Digitized data copyright (c) 2010-2011, Google Corporation. |
| `OpenSans-Bold.ttf` | Ka0s Open Sans Bold | Digitized data copyright (c) 2010-2011, Google Corporation. |
| `OpenSans-CondBold.ttf` | Ka0s Open Sans Condensed | Digitized data copyright (c) 2010-2011, Google Corporation. |
| `OpenSans-Light.ttf` | Ka0s Open Sans Light | Digitized data copyright (c) 2010-2011, Google Corporation. |
| `OpenSans-Semibold.ttf` | Ka0s Open Sans Semibold | Digitized data copyright (c) 2011, Google Corporation. |

## Under the author's terms

| File | Key | Source | Copyright (name table) | License file |
|---|---|---|---|---|
| `Prototype-Regular.ttf` | Ka0s Prototype | <https://www.dafont.com/prototype.font>, v2.0 (2001), unchanged | Copyright 2001, free for personal use, freely distributed with Prototype.txt | `Prototype.txt` |

Not under the OFL. The author's `Prototype.txt` ships beside it unchanged, as it asks. Shipped on the
owner's ruling of 2026-10-30.

## Shipped on an owner ruling, against or without license terms

None of these faces has a license that allows this redistribution. Each ships on the owner's ruling
alone, and that ruling is the only ground it ships on. Each is byte for byte the file named.

| File | Key | Source | Copyright (name table) | License file |
|---|---|---|---|---|
| `Expressway-Bold.ttf` | Ka0s Expressway | The owner's SharedMedia pack, Expressway Rg Bold 2.100 | (c) 2005 Typodermic. Do not distribute. | `Expressway-EULA.pdf` |
| `FrizQuadrataTT-Regular.ttf` | Ka0s Friz Quadrata TT | DialogueUI add-on, `Fonts/frizqt__.ttf` | (c) Copyright 1997 International Typeface Corporation. All rights reserved. | none |
| `SegoeUI-Regular.ttf` | Ka0s Segoe UI | Sorted add-on, `Textures/segoeui.ttf` | (c) 2018 Microsoft Corporation. All Rights Reserved. | none |
| `SegoeUI-Bold.ttf` | Ka0s Segoe UI Bold | Sorted add-on, `Textures/segoeuib.ttf` | as above | none |
| `SegoeUI-Semilight.ttf` | Ka0s Segoe UI Light | Sorted add-on, `Textures/segoeuisl.ttf` | as above | none |
| `SegoeUI-Semibold.ttf` | Ka0s Segoe UI Semibold | Sorted add-on, `Textures/seguisb.ttf` | as above | none |
| `Emblem-Regular.ttf` | Ka0s Emblem | AbstractFramework add-on, `Media/Fonts/Emblem.ttf` | From the WSI-Font Collection. Copyright (c)1994 Weatherly Systems, Inc. All Rights Reserved. Redistribution strictly prohibited. | none |
| `DorisPP-Bold.ttf` | Ka0s Doris PP | SharedMedia add-on, `fonts/doris_pp/DorisPP.ttf` | Copyright (c) 1993 Ares Software Corp. All rights reserved. | none |
| `AvantGarde-Regular.ttf` | Ka0s Avant Garde | EllesmereUI add-on, `media/fonts/Avant Garde Naowh.ttf` | Copyright (c) 1990-2009 ParaType, Inc. All Rights Reserved. ITC Avangard Gothic is a registered trade mark of International Typeface Corporation. | none |

**Expressway.** By Ray Larabie, Typodermic (<https://www.dafont.com/expressway.font>). Its name table reads "Do not distribute", and the Typodermic Desktop EULA 2026 puts
embedding in software outside the free license. The owner's ruling of 2026-10-30: "Ship it anyways."
The EULA (`Expressway-EULA.pdf`) and its quick guide (`Expressway-EULA-Guide.html`) ship beside it as
the record of the terms that ruling overrode. Expressway is a trademark of Typodermic.

**Segoe UI.** Its license record reads "Microsoft supplied font. You may use this font to create,
display, and print content as permitted by the license terms or terms of use, of the Microsoft
product, service, or content in which this font was included", and ends "Any other use is prohibited."
Segoe is a trademark of the Microsoft group of companies. The owner ruled on 2026-10-31 to ship all
four weights, told of the Microsoft ownership, the public repositories and the size. The name table
also credits the Biblical Hebrew layout logic to Ralph Hancock and John Hudson (copyright 2003 and
2007), open source under the MIT License, whose full text is in the font's own license record.

**Avant Garde.** Its license record says "You have no right to share the font with service bureau, if
you have not got special license" and "You have no right to embed this font into document for
commercial purposes without special license", and its name table calls it "a property of ParaType,
Inc." Shipped on the owner's ruling of 2026-10-31.

**Friz Quadrata.** The name table records no license. The copyright stays ITC's. Shipped on the owner's ruling of 2026-10-31.

**Emblem.** The name table says "Redistribution strictly prohibited." Shipped on the owner's ruling of
2026-10-31.

**Doris PP.** The name table records no license, and FontChameleon is a trademark of Ares Software
Corp. Shipped on the owner's ruling of 2026-10-31.

## Family notes

Prototype, Atkinson Hyperlegible, Friz Quadrata, Emblem and Doris PP have no Cyrillic, so `Media.lua`
registers them for western clients only. Every other family has the Russian alphabet.
