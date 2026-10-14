#!/bin/sh
# Makes the default font, Inter-Regular-subset.ttf, from Inter's release:
#
#   https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip
#   sha256 9883fdd4a49d4fb66bd8177ba6625ef9a64aa45899767dde3d36aa425756b11e
#
# its extras/ttf/Inter-Regular.ttf (sha256 40d692fce188e4471e2b3cba937be967
# 878f631ad3ebbbdcd587687c7ebe0c82), subset with fonttools' pyftsubset to
# Basic Latin, Latin-1, Latin Extended-A, General Punctuation, currency
# signs, arrows, the trademark sign and the replacement character, keeping
# kerning and dropping hinting, which glyphs drawn from distance fields do
# not use. Inter's license (OFL.txt, from the release's LICENSE.txt) names
# no Reserved Font Name, so the subset keeps Inter's name. Last, the GPOS
# Extension lookups that hold most of Inter's kerning are unwrapped
# (unwrap_extensions.py), since stb_truetype reads kerning only from plain
# Pair Adjustment lookups.
#
#   sh make_subset.sh path/to/Inter-Regular.ttf       (fonttools installed)
set -e
pyftsubset "$1" \
    --unicodes="U+0020-007E,U+00A0-017F,U+2000-206F,U+20A0-20BF,U+2122,U+2190-2195,U+FFFD" \
    --layout-features="kern" \
    --no-hinting \
    --output-file="$(dirname "$0")/Inter-Regular-subset.ttf"
python3 "$(dirname "$0")/unwrap_extensions.py" "$(dirname "$0")/Inter-Regular-subset.ttf"
