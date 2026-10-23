"""Converts the VMForMac boot logo PNG into the 24-bit BMP edk2's LogoDxe embeds.

Usage: python3 -I png2bmp.py <in.png> <out.bmp>

Standard library only (zlib + struct), so it runs in the build venv without
extra packages. Accepts what xtask-icon (tiny-skia) writes: 8-bit RGBA or RGB,
non-interlaced. Transparent pixels are composited onto black, the firmware's
background, because the HII image format has no alpha.
"""

import struct
import sys
import zlib


def read_png(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path}: not a PNG")
    pos, idat, ihdr = 8, b"", None
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
    if ihdr is None:
        raise SystemExit(f"{path}: no IHDR")
    width, height, depth, color, _comp, _filt, interlace = ihdr
    if depth != 8 or color not in (2, 6) or interlace != 0:
        raise SystemExit(f"{path}: need 8-bit RGB/RGBA, non-interlaced PNG")
    bpp = 4 if color == 6 else 3
    raw = zlib.decompress(idat)
    stride = width * bpp
    rows, prev = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        ftype = raw[start]
        line = bytearray(raw[start + 1:start + 1 + stride])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if ftype == 1:
                line[i] = (line[i] + a) & 0xFF
            elif ftype == 2:
                line[i] = (line[i] + b) & 0xFF
            elif ftype == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 0xFF
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
            elif ftype != 0:
                raise SystemExit(f"{path}: bad filter {ftype}")
        rows.append(bytes(line))
        prev = line
    return width, height, bpp, rows


def write_bmp(path, width, height, bpp, rows):
    row_size = (width * 3 + 3) & ~3
    pixels = bytearray()
    for line in reversed(rows):  # BMP rows are stored bottom-up
        out = bytearray()
        for x in range(width):
            r, g, b = line[x * bpp], line[x * bpp + 1], line[x * bpp + 2]
            alpha = line[x * bpp + 3] if bpp == 4 else 255
            # Straight alpha over black.
            out += bytes(((b * alpha + 127) // 255, (g * alpha + 127) // 255, (r * alpha + 127) // 255))
        out += b"\0" * (row_size - len(out))
        pixels += out
    header = struct.pack("<2sIHHI", b"BM", 54 + len(pixels), 0, 0, 54)
    info = struct.pack("<IiiHHIIiiII", 40, width, height, 1, 24, 0, len(pixels), 2835, 2835, 0, 0)
    with open(path, "wb") as f:
        f.write(header + info + pixels)


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: png2bmp.py <in.png> <out.bmp>")
    write_bmp(sys.argv[2], *read_png(sys.argv[1]))


if __name__ == "__main__":
    main()
