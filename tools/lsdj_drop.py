# Copy an LSDj .sav, removing the given song slots (1-based) from the file table.
# SPDX-License-Identifier: GPL-2.0-or-later
import sys
src, dst, *slots = sys.argv[1:]
d = bytearray(open(src, "rb").read())
assert d[0x813E:0x8140] == b"jk", "not an LSDj save"
for s in map(int, slots):
    i = s - 1
    d[0x8000 + i*8 : 0x8000 + i*8 + 8] = bytes(8)   # name
    d[0x8100 + i] = 0                                  # version
    for j in range(191):                               # free its blocks
        if d[0x8141 + j] == i:
            d[0x8141 + j] = 0xFF
open(dst, "wb").write(d)
