# Show the song structure of one LSDj song slot: where song rows start, and which rows hold an HFF.
# usage: lsdj_song_info.py file.sav SLOT      (SLOT is 1-based, as in `make songs`)
# SPDX-License-Identifier: GPL-2.0-or-later
import sys
DEF_INSTR = bytes([0xA8,0,0,0xFF,0,0,3,0,0,0xD0,0,0,0,0xF3,0,0])
DEF_WAVE  = bytes([0x8E,0xCD,0xCC,0xBB,0xAA,0xA9,0x99,0x88,0x87,0x76,0x66,0x55,0x54,0x43,0x32,0x31])

def decompress(sav, slot):
    first = next(j for j in range(191) if sav[0x8141 + j] == slot)
    pos, out = 0x8200 + first * 0x200, bytearray()
    while True:
        b = sav[pos]; pos += 1
        if b == 0xC0:                       # run-length
            v = sav[pos]; pos += 1
            if v == 0xC0: out.append(0xC0)
            else: out += bytes([v]) * sav[pos]; pos += 1
        elif b == 0xE0:                     # special
            v = sav[pos]; pos += 1
            if v == 0xE0: out.append(0xE0)
            elif v == 0xF1: out += DEF_INSTR * sav[pos]; pos += 1
            elif v == 0xF0: out += DEF_WAVE * sav[pos]; pos += 1
            elif v == 0xFF: return bytes(out)
            else: pos = 0x8200 + (v - 1) * 0x200   # continue in block v (1-based)
        else:
            out.append(b)

sav = open(sys.argv[1], "rb").read()
slot = int(sys.argv[2]) - 1
name = sav[0x8000 + slot*8 : 0x8008 + slot*8].split(b"\0")[0].decode("latin-1")
s = decompress(sav, slot)
ok = len(s) == 0x8000 and s[0x1E78:0x1E7A] == s[0x3E80:0x3E82] == s[0x7FF0:0x7FF2] == b"rb"
print(f"song {slot+1} {name}: {len(s)} bytes decoded, rb markers {'OK' if ok else 'BAD'}")
if not ok: sys.exit(1)

rows = [[s[0x1290 + r*4 + c] for c in range(4)] for r in range(256)]
used = [r for r in range(256) if any(x != 0xFF for x in rows[r])]
# sections = runs of non-empty rows
secs, start = [], None
for r in range(257):
    filled = r < 256 and r in used
    if filled and start is None: start = r
    if not filled and start is not None: secs.append((start, r - 1)); start = None
print("song row sections (hex):", ", ".join(f"{a:02X}-{b:02X}" for a, b in secs) or "none")

# Command ids (LSDj 9.x, alphabetical): 0 none, 1 A, 2 B, 3 C, 4 D, 5 E, 6 F, 7 G, 8 H, 9 K, 10 L, 11 M,
# 12 O, 13 P, 14 R, 15 S, 16 T, 17 V, 18 W, 19 Z
CMD_H = 8
# HFF: phrase command H with value $FF -> chains using that phrase -> song rows using that chain
hff_phrases = {p for p in range(255) for st in range(16)
               if s[0x4000 + p*16 + st] == CMD_H and s[0x4FF0 + p*16 + st] == 0xFF}
hff_chains = {c for c in range(128) for st in range(16) if s[0x2080 + c*16 + st] in hff_phrases}
hff_rows = sorted({r for r in range(256) for c in range(4) if rows[r][c] in hff_chains})
print("phrases with HFF:", " ".join(f"{p:02X}" for p in sorted(hff_phrases)) or "none")
print("song rows reaching an HFF chain:", " ".join(f"{r:02X}" for r in hff_rows) or "none")

# HFF can also live in instrument tables (2 command columns, 32 tables x 16 steps)
hff_tables = sorted({t for t in range(32) for st in range(16) for cmd, val in ((0x3680, 0x3880), (0x3A80, 0x3C80))
                     if s[cmd + t*16 + st] == CMD_H and s[val + t*16 + st] == 0xFF})
print("tables with HFF:", " ".join(f"{t:02X}" for t in hff_tables) or "none")
