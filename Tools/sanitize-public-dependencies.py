#!/usr/bin/env python3
"""Remove local build paths from distributed FFmpeg dependency metadata."""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
strip = subprocess.check_output(["xcrun", "--find", "strip"], text=True).strip()
for library in root.glob("Vendor/**/*.a"):
    subprocess.run([strip, "-S", str(library)], check=True, capture_output=True)
    data = library.read_bytes()
    # FFmpeg stores configure's installation prefix in read-only strings.
    # Equal-length replacements preserve archive offsets and machine code.
    pattern = rb"/Users/[^\x00\r\n\t\x20]+/Vendor/(iphoneos|iphonesimulator)"
    for match in list(re.finditer(pattern, data)):
        original = match.group(0)
        public = b"/build/" + b"_" * (len(original) - len(b"/build/NegiFlick/Vendor/") - len(match.group(1)))
        public += b"NegiFlick/Vendor/" + match.group(1)
        assert len(original) == len(public)
        data = data.replace(original, public)
    assert b"/Users/" not in data, library
    library.write_bytes(data)

for config in root.glob("Vendor/*/lib/pkgconfig/*.pc"):
    lines = []
    for line in config.read_text().splitlines():
        if line.startswith("prefix="): line = "prefix=${pcfiledir}/../.."
        elif line.startswith("libdir="): line = "libdir=${prefix}/lib"
        elif line.startswith("includedir="): line = "includedir=${prefix}/include"
        lines.append(line)
    config.write_text("\n".join(lines) + "\n")
print("Dependency debug paths removed; pkg-config paths are relocatable.")
