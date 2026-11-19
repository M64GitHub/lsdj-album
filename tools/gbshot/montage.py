# montage.py out.png COLS a.png b.png ... - put gbshot screenshots side by side (contact sheet)
# SPDX-License-Identifier: GPL-2.0-or-later
import sys, zlib, struct
def read(path):
    d = open(path, "rb").read(); pos, idat = 8, b""
    while pos < len(d):
        n, t = struct.unpack(">I4s", d[pos:pos+8]); body = d[pos+8:pos+8+n]; pos += 12 + n
        if t == b"IHDR": w, h = struct.unpack(">II", body[:8])
        elif t == b"IDAT": idat += body
    raw = zlib.decompress(idat)
    return w, h, [raw[y*(w*3+1)+1:(y+1)*(w*3+1)] for y in range(h)]
out, cols, files = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
imgs = [read(f) for f in files]; w, h = imgs[0][0], imgs[0][1]; gap = 6
rows = -(-len(imgs) // cols); W, H = cols * w + (cols - 1) * gap, rows * h + (rows - 1) * gap
canvas = [bytearray(b"\xff\x00\xff" * W) for _ in range(H)]
for i, (_, _, px) in enumerate(imgs):
    ox, oy = (i % cols) * (w + gap), (i // cols) * (h + gap)
    for y in range(h): canvas[oy + y][ox*3:(ox+w)*3] = px[y]
raw = b"".join(b"\0" + bytes(r) for r in canvas)
def chunk(t, b): return struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b))
open(out, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
