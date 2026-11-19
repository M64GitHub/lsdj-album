# List the songs in LSDj .sav files: slot, name, version, blocks used.
# SPDX-License-Identifier: GPL-2.0-or-later
import sys
for path in sys.argv[1:]:
    d = open(path, "rb").read()
    ok = d[0x813E:0x8140] == b"jk"
    names = []
    for i in range(32):
        raw = d[0x8000 + i*8 : 0x8000 + i*8 + 8]
        if raw[0] == 0:
            continue
        blocks = sum(1 for b in d[0x8141:0x8141+191] if b == i)
        names.append(f"{i+1:2d}:{raw.split(b'\0')[0].decode('latin-1')}(v{d[0x8100+i]},{blocks}blk)")
    print(f"{path}\n  valid={ok} active_slot={d[0x8140]}  songs: {' '.join(names) or '(none)'}")
