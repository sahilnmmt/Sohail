#!/usr/bin/env python3
"""Tile the PPM files written by render_faces into one PNG (stdlib only).

    python3 contact_sheet.py <ppm_dir> <out.png>
"""
import struct
import sys
import zlib
from pathlib import Path


def read_ppm(path):
    data = path.read_bytes()
    parts = data.split(maxsplit=4)
    if parts[0] != b"P6" or parts[3] != b"255":
        raise ValueError(f"{path}: not an 8-bit P6 PPM")
    w, h = int(parts[1]), int(parts[2])
    return w, h, parts[4][: w * h * 3]


def write_png(path, w, h, rgb):
    rows = b"".join(b"\x00" + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body))

    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


def main():
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    images = [read_ppm(p) for p in sorted(src.glob("*.ppm"))]
    if not images:
        sys.exit(f"no .ppm files in {src}")
    w, h = images[0][0], images[0][1]
    cols, gap = 5, 6
    rows = (len(images) + cols - 1) // cols
    sw, sh = cols * (w + gap) + gap, rows * (h + gap) + gap
    sheet = bytearray(b"\x40" * (sw * sh * 3))  # grey frame around each tile
    for i, (iw, ih, px) in enumerate(images):
        ox, oy = gap + (i % cols) * (w + gap), gap + (i // cols) * (h + gap)
        for y in range(ih):
            start = ((oy + y) * sw + ox) * 3
            sheet[start:start + iw * 3] = px[y * iw * 3:(y + 1) * iw * 3]
    write_png(out, sw, sh, bytes(sheet))


if __name__ == "__main__":
    main()
