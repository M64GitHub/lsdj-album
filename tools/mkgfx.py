# Generate Game Boy graphics for the player screen:
#   logo PNG -> integer-scaled, 4-shade tiles + tile map
#   5x7 font, waveform tiles, LED meter tiles
# usage: mkgfx.py logo.png out_dir   -> out_dir/gfx_const.inc, out_dir/gfx_data.inc
# Shades: 0 = lightest ... 3 = darkest (BGP %11100100). Screen background is shade 3.
# SPDX-License-Identifier: GPL-2.0-or-later
import sys, zlib, struct

def read_png(path):
    d = open(path, "rb").read()
    assert d[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, idat = 8, b""
    while pos < len(d):
        n, t = struct.unpack(">I4s", d[pos:pos+8]); body = d[pos+8:pos+8+n]; pos += 12 + n
        if t == b"IHDR": w, h, bd, ct, _, _, il = struct.unpack(">IIBBBBB", body)
        elif t == b"IDAT": idat += body
    assert bd == 8 and ct in (2, 6) and il == 0, "need 8-bit RGB/RGBA, non-interlaced PNG"
    bpp = 4 if ct == 6 else 3
    raw, stride, rows, prev, p = zlib.decompress(idat), w * bpp, [], bytearray(w * bpp), 0
    for y in range(h):
        f = raw[p]; line = bytearray(raw[p+1:p+1+stride]); p += 1 + stride
        for i in range(stride):
            a = line[i-bpp] if i >= bpp else 0; b = prev[i]; c = prev[i-bpp] if i >= bpp else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2*c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append([tuple(line[x*bpp:x*bpp+bpp]) + ((255,) if bpp == 3 else ()) for x in range(w)])
        prev = line
    return w, h, rows

def shade(px):  # luminance (transparent = black) -> 0 (white) .. 3 (black)
    r, g, b, a = px
    lum = (0.299 * r + 0.587 * g + 0.114 * b) * a / 255
    return 3 - round(lum / 255 * 3)

def encode(tile):  # 8x8 list of shades -> 16 bytes 2bpp
    out = []
    for row in tile:
        lo = hi = 0
        for x, c in enumerate(row):
            lo |= (c & 1) << (7 - x); hi |= (c >> 1) << (7 - x)
        out += [lo, hi]
    return bytes(out)

tiles, index = [], {}
def add(tile):
    b = encode(tile)
    if b not in index: index[b] = len(tiles); tiles.append(b)
    return index[b]

BLACK = [[3] * 8 for _ in range(8)]
assert add(BLACK) == 0

# --- logo ---
w, h, px = read_png(sys.argv[1])
scale = max(1, min(160 // w, 56 // h))
lw, lh = -(-w * scale // 8), -(-h * scale // 8)
ox, oy = (lw * 8 - w * scale) // 2, (lh * 8 - h * scale) // 2
canvas = [[3] * (lw * 8) for _ in range(lh * 8)]
for y in range(h * scale):
    for x in range(w * scale):
        canvas[oy + y][ox + x] = shade(px[y // scale][x // scale])
logo_map = [add([row[tx*8:tx*8+8] for row in canvas[ty*8:ty*8+8]]) for ty in range(lh) for tx in range(lw)]

# --- font (5x7, white on black) ---
FONT = {
 "A":"01110 10001 10001 11111 10001 10001 10001", "B":"11110 10001 10001 11110 10001 10001 11110",
 "C":"01110 10001 10000 10000 10000 10001 01110", "D":"11110 10001 10001 10001 10001 10001 11110",
 "E":"11111 10000 10000 11110 10000 10000 11111", "F":"11111 10000 10000 11110 10000 10000 10000",
 "G":"01110 10001 10000 10111 10001 10001 01111", "H":"10001 10001 10001 11111 10001 10001 10001",
 "I":"01110 00100 00100 00100 00100 00100 01110", "J":"00111 00010 00010 00010 00010 10010 01100",
 "K":"10001 10010 10100 11000 10100 10010 10001", "L":"10000 10000 10000 10000 10000 10000 11111",
 "M":"10001 11011 10101 10101 10001 10001 10001", "N":"10001 10001 11001 10101 10011 10001 10001",
 "O":"01110 10001 10001 10001 10001 10001 01110", "P":"11110 10001 10001 11110 10000 10000 10000",
 "Q":"01110 10001 10001 10001 10101 10010 01101", "R":"11110 10001 10001 11110 10100 10010 10001",
 "S":"01111 10000 10000 01110 00001 00001 11110", "T":"11111 00100 00100 00100 00100 00100 00100",
 "U":"10001 10001 10001 10001 10001 10001 01110", "V":"10001 10001 10001 10001 10001 01010 00100",
 "W":"10001 10001 10001 10101 10101 10101 01010", "X":"10001 10001 01010 00100 01010 10001 10001",
 "Y":"10001 10001 10001 01010 00100 00100 00100", "Z":"11111 00001 00010 00100 01000 10000 11111",
 "0":"01110 10001 10011 10101 11001 10001 01110", "1":"00100 01100 00100 00100 00100 00100 01110",
 "2":"01110 10001 00001 00010 00100 01000 11111", "3":"11111 00010 00100 00010 00001 10001 01110",
 "4":"00010 00110 01010 10010 11111 00010 00010", "5":"11111 10000 11110 00001 00001 10001 01110",
 "6":"00110 01000 10000 11110 10001 10001 01110", "7":"11111 00001 00010 00100 01000 01000 01000",
 "8":"01110 10001 10001 01110 10001 10001 01110", "9":"01110 10001 10001 01111 00001 00010 01100",
 "/":"00001 00010 00010 00100 01000 01000 10000", "-":"00000 00000 00000 11111 00000 00000 00000",
 "x":"00000 00000 10001 01010 00100 01010 10001",
}
charmap = {" ": 0}
for ch, rows in FONT.items():
    g = [[3] * 8 for _ in range(8)]
    for y, bits in enumerate(rows.split()):
        for x, bit in enumerate(bits):
            if bit == "1": g[y][x + 1] = 0
    charmap[ch] = add(g)

# --- waveform tiles: two 4px columns, fill 0,2,4,6,8 px; UP fills from bottom, DN from top ---
def wave_tile(f0, f1, up):
    t = [[3] * 8 for _ in range(8)]
    for half, f in ((0, f0), (1, f1)):
        fill = f * 2
        for k in range(fill):
            y = 7 - k if up else k
            c = 0 if (k == fill - 1 and fill < 8) else 1   # bright edge on the wave's outline
            for x in range(4): t[y][half * 4 + x] = c
    return t
def wave_set(up):
    ids = [len(tiles) + i for i in range(25)]
    for f0 in range(5):
        for f1 in range(5):
            b = encode(wave_tile(f0, f1, up)); index.setdefault(b, None); tiles.append(b)
    return ids[0]
WAVE_UP = wave_set(True)
WAVE_DN = wave_set(False)

# --- LED meter segments: 6x6 block ---
def seg(c):
    t = [[3] * 8 for _ in range(8)]
    for y in range(1, 7):
        for x in range(1, 7): t[y][x] = c
    return t
SEG_OFF = len(tiles); tiles.append(encode(seg(2)))
SEG_PEAK = len(tiles); tiles.append(encode(seg(1)))
SEG_ON = len(tiles); tiles.append(encode(seg(0)))

assert len(tiles) <= 256, f"too many tiles: {len(tiles)}"
out = sys.argv[2]
with open(f"{out}/gfx_const.inc", "w") as f:
    f.write("; generated by tools/mkgfx.py - do not edit\n")
    f.write(f"DEF TILE_BLACK EQU 0\nDEF LOGO_W EQU {lw}\nDEF LOGO_H EQU {lh}\n")
    f.write(f"DEF FONT_0 EQU {charmap['0']}\nDEF WAVE_UP EQU {WAVE_UP}\nDEF WAVE_DN EQU {WAVE_DN}\n")
    f.write(f"DEF SEG_OFF EQU {SEG_OFF}\nDEF SEG_PEAK EQU {SEG_PEAK}\nDEF SEG_ON EQU {SEG_ON}\n")
    for ch, i in charmap.items():
        f.write(f'CHARMAP "{ch}", {i}\n')
with open(f"{out}/gfx_data.inc", "w") as f:
    f.write("; generated by tools/mkgfx.py - do not edit\nSECTION \"gfx_data\", ROM0\nGfxTiles::\n")
    for t in tiles:
        f.write("    db " + ",".join(f"${b:02X}" for b in t) + "\n")
    f.write("GfxTilesEnd::\nLogoMap::\n")
    for r in range(lh):
        f.write("    db " + ",".join(f"${i:02X}" for i in logo_map[r*lw:(r+1)*lw]) + "\n")
print(f"logo {w}x{h} x{scale} -> {lw}x{lh} tiles; {len(tiles)} tiles total "
      f"({len(set(logo_map))} logo, font, 50 wave, 3 meter)")
