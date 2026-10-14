"""Rewrites a font's GPOS Extension lookups (type 9) as the lookups they
wrap, in place. stb_truetype reads GPOS kerning only from Pair Adjustment
lookups (type 2) and skips extensions, which Inter puts most of its
kerning in; a subset is small enough to need no 32-bit offsets.

    python unwrap_extensions.py font.ttf
"""

import sys

from fontTools.ttLib import TTFont


def main(path):
    font = TTFont(path)
    unwrapped = 0
    for lookup in font["GPOS"].table.LookupList.Lookup:
        if lookup.LookupType != 9:
            continue
        lookup.LookupType = lookup.SubTable[0].ExtensionLookupType
        lookup.SubTable = [s.ExtSubTable for s in lookup.SubTable]
        unwrapped += 1
    font.save(path)
    print(f"{path}: {unwrapped} extension lookups unwrapped")


if __name__ == "__main__":
    main(sys.argv[1])
