#!/usr/bin/env python3
"""Draw a simple Q icon and write an icns file. Stdlib plus sips and iconutil."""
import pathlib
import subprocess
import sys
import tempfile


def pixel(x, y):
    dx, dy = x - 128, y - 128
    radius = (dx * dx + dy * dy) ** 0.5
    ring = 78 <= radius <= 108
    tail = 128 <= x <= 168 and 128 <= y <= 176 and abs((x - 128) - (y - 136) * 0.7) < 10
    if ring or tail:
        return (196, 163, 90)
    return (28, 26, 23)


def write_ppm(path):
    width = height = 256
    rows = []
    for y in range(height):
        for x in range(width):
            rows.append(pixel(x, y))
    data = b"".join(bytes(rgb) for rgb in rows)
    path.write_bytes(f"P6\n{width} {height}\n255\n".encode() + data)


def main():
    destination = pathlib.Path(sys.argv[1])
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as raw:
        root = pathlib.Path(raw)
        ppm = root / "icon.ppm"
        png = root / "icon.png"
        write_ppm(ppm)
        subprocess.check_call(["sips", "-s", "format", "png", str(ppm), "--out", str(png)], stdout=subprocess.DEVNULL)
        iconset = root / "AppIcon.iconset"
        iconset.mkdir()
        sizes = [16, 32, 64, 128, 256, 512, 1024]
        names = {
            16: ["icon_16x16.png"],
            32: ["icon_16x16@2x.png", "icon_32x32.png"],
            64: ["icon_32x32@2x.png"],
            128: ["icon_128x128.png"],
            256: ["icon_128x128@2x.png", "icon_256x256.png"],
            512: ["icon_256x256@2x.png", "icon_512x512.png"],
            1024: ["icon_512x512@2x.png"],
        }
        for size, filenames in names.items():
            for name in filenames:
                subprocess.check_call(
                    ["sips", "-z", str(size), str(size), str(png), "--out", str(iconset / name)],
                    stdout=subprocess.DEVNULL,
                )
        subprocess.check_call(["iconutil", "-c", "icns", str(iconset), "-o", str(destination)])


if __name__ == "__main__":
    main()
