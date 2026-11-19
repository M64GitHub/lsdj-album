# gif.py out.gif SCALE frame1.png frame2.png ...
# Animated GIF from gbshot screenshots (any integer scale of 160x144). Frames
# are reduced to 160x144, scaled by SCALE, and stored as changed rectangles
# only, so a mostly static screen stays small. 30 fps, loops forever.
# SPDX-License-Identifier: GPL-2.0-or-later
import struct, sys, zlib


def read_png(path):  # 8-bit RGB, filter 0 rows (as written by gbshot)
    d = open(path, "rb").read()
    pos, idat = 8, b""
    while pos < len(d):
        n, t = struct.unpack(">I4s", d[pos:pos + 8])
        body = d[pos + 8:pos + 8 + n]
        pos += 12 + n
        if t == b"IHDR":
            w, h = struct.unpack(">II", body[:8])
        elif t == b"IDAT":
            idat += body
    raw = zlib.decompress(idat)
    stride = w * 3 + 1
    assert all(raw[y * stride] == 0 for y in range(h)), "expects unfiltered rows (gbshot output)"
    return w, h, raw, stride


def to_gb(path, palette):  # -> 160x144 palette indices
    w, h, raw, stride = read_png(path)
    s = w // 160
    px = []
    for y in range(144):
        row = raw[y * s * stride + 1:]
        for x in range(160):
            c = bytes(row[x * s * 3:x * s * 3 + 3])
            if c not in palette:
                palette[c] = len(palette)
                assert len(palette) <= 4, "more than 4 colours"
            px.append(palette[c])
    return px


def lzw(data, min_size):
    clear, eoi = 1 << min_size, (1 << min_size) + 1
    out, acc, nbits = bytearray(), 0, 0

    def emit(code):
        nonlocal acc, nbits
        acc |= code << nbits
        nbits += size
        while nbits >= 8:
            out.append(acc & 255)
            acc >>= 8
            nbits -= 8

    def reset():
        return {bytes([i]): i for i in range(clear)}, eoi + 1, min_size + 1

    table, nxt, size = reset()
    emit(clear)
    w = b""
    for k in data:
        wk = w + bytes([k])
        if wk in table:
            w = wk
            continue
        emit(table[w])
        if nxt < 4096:
            table[wk] = nxt
            nxt += 1
            if nxt > (1 << size) and size < 12:
                size += 1
        else:
            emit(clear)
            table, nxt, size = reset()
        w = bytes([k])
    emit(table[w])
    emit(eoi)
    if nbits:
        out.append(acc & 255)
    return bytes(out)


def blocks(b):
    return b"".join(bytes([len(b[i:i + 255])]) + b[i:i + 255] for i in range(0, len(b), 255)) + b"\0"


out, scale, files = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
palette = {}
frames = [to_gb(f, palette) for f in files]
colours = sorted(palette, key=palette.get) + [b"\0\0\0"] * (4 - len(palette))
W, H = 160 * scale, 144 * scale

gif = bytearray(b"GIF89a" + struct.pack("<HHBBB", W, H, 0xF1, 0, 0) + b"".join(colours))
gif += b"\x21\xFF\x0BNETSCAPE2.0\x03\x01\x00\x00\x00"           # loop forever
prev = None
for i, px in enumerate(frames):
    if prev is None:
        x0, y0, x1, y1 = 0, 0, 160, 144
    else:
        diff = [j for j in range(160 * 144) if px[j] != prev[j]]
        if not diff:
            diff = [0]
        ys = [j // 160 for j in diff]
        xs = [j % 160 for j in diff]
        x0, y0, x1, y1 = min(xs), min(ys), max(xs) + 1, max(ys) + 1
    data = bytearray()
    for y in range(y0 * scale, y1 * scale):
        line = px[(y // scale) * 160:(y // scale) * 160 + 160]
        data += bytes(line[x // scale] for x in range(x0 * scale, x1 * scale))
    delay = 3 if i % 3 else 4                                    # ~30 fps
    gif += b"\x21\xF9\x04\x04" + struct.pack("<H", delay) + b"\0\0"  # keep previous frame
    gif += b"\x2C" + struct.pack("<HHHHB", x0 * scale, y0 * scale, (x1 - x0) * scale, (y1 - y0) * scale, 0)
    gif += b"\x02" + blocks(lzw(data, 2))
    prev = px
gif += b"\x3B"
open(out, "wb").write(gif)
print(f"{out}: {len(frames)} frames, {W}x{H}, {len(gif) // 1024} KB")
