# -*- coding: utf-8 -*-
"""Convert the archived Apple cover JPEGs to no-resize 24-bit BMPs.

The only transformation is Image.open(archive).convert('RGB').save(BMP):
no resize, ImageOps.fit, crop or upscale. The archived JPEG SHA-256 must
match cover_sources/manifest.json. Every BMP header field is checked and
the PIL readback pixels must equal the archived JPEG pixel for pixel.
The old 640x480 prepare_music_card.py tooling is left untouched.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path

from PIL import Image
from fetch_apple_cover_sources import META_FIELDS, TRACKS

HERE = Path(__file__).resolve().parent
SOURCE_DIR = HERE / "cover_sources"
STAGING_DIR = HERE / "staging_hires_pic13_20261025"
SPECS = {f"PIC{number}.BMP": (number, meta["expected_width"], meta["expected_height"])
         for number, meta in TRACKS.items()}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def manifest_entry(source_dir, number, width, height):
    """Return the archive path after cross-checking metadata, dims and hash."""
    source_dir = Path(source_dir)
    manifest = json.loads((source_dir / "manifest.json").read_text(encoding="utf-8"))
    entry = manifest["tracks"][str(number)]
    meta = TRACKS[number]
    for field in META_FIELDS:
        if entry.get(field) != meta[field]:
            raise ValueError(f"PIC{number}: manifest {field} differs from "
                             "the verified track metadata")
    if (entry.get("width"), entry.get("height")) != (width, height):
        raise ValueError(f"PIC{number}: manifest dimensions differ from the "
                         f"required {width}x{height}")
    archive = source_dir / f"PIC{number}.jpg"
    if digest(archive) != entry.get("jpeg_sha256"):
        raise ValueError(f"PIC{number}: archived JPEG hash differs from the manifest")
    return archive


def check_bmp(path, width, height):
    """Field-by-field BMP validation plus a PIL readback check."""
    path = Path(path)
    raw = path.read_bytes()
    if len(raw) < 54:
        raise ValueError(f"{path.name}: too small for a BMP header")
    if raw[:2] != b"BM":
        raise ValueError(f"{path.name}: missing BM signature")
    if int.from_bytes(raw[2:6], "little") != len(raw):
        raise ValueError(f"{path.name}: declared file size mismatch")
    if int.from_bytes(raw[10:14], "little") != 54:
        raise ValueError(f"{path.name}: pixel data offset must be 54")
    if int.from_bytes(raw[14:18], "little") < 40:
        raise ValueError(f"{path.name}: DIB header must be at least 40 bytes")
    if int.from_bytes(raw[26:28], "little") != 1:
        raise ValueError(f"{path.name}: planes must be 1")
    if int.from_bytes(raw[28:30], "little") != 24:
        raise ValueError(f"{path.name}: must be 24-bit")
    if int.from_bytes(raw[30:34], "little") != 0:
        raise ValueError(f"{path.name}: compression must be 0")
    actual_width = int.from_bytes(raw[18:22], "little", signed=True)
    actual_height = int.from_bytes(raw[22:26], "little", signed=True)
    if actual_height <= 0:
        raise ValueError(f"{path.name}: height must be positive (bottom-up)")
    if (actual_width, actual_height) != (width, height):
        raise ValueError(f"{path.name}: unexpected dimensions "
                         f"{actual_width}x{actual_height}")
    stride = ((width * 3 + 3) // 4) * 4
    if len(raw) != 54 + stride * height:
        raise ValueError(f"{path.name}: expected {54 + stride * height} bytes "
                         f"for {width}x{height}, got {len(raw)}")
    with Image.open(path) as image:
        if image.format != "BMP" or image.size != (width, height):
            raise ValueError(f"{path.name}: PIL readback dimensions mismatch")
        image.load()
        if image.mode != "RGB":
            raise ValueError(f"{path.name}: PIL readback must be RGB")


def canonical_bmp_bytes(archive, width, height):
    """The only permitted conversion: open, convert('RGB'), save as BMP."""
    with Image.open(archive) as image:
        if image.format != "JPEG" or image.mode != "RGB":
            raise ValueError(f"{Path(archive).name}: expected an RGB JPEG archive")
        rgb = image.convert("RGB")
        if rgb.size != (width, height):
            raise ValueError(f"{Path(archive).name}: unexpected archive dimensions "
                             f"{rgb.size}; refusing to resize")
        buffer = io.BytesIO()
        rgb.save(buffer, format="BMP")
    return buffer.getvalue()


def convert_one(name, source_dir=SOURCE_DIR, staging_dir=STAGING_DIR, specs=SPECS):
    number, width, height = specs[name]
    archive = manifest_entry(source_dir, number, width, height)
    data = canonical_bmp_bytes(archive, width, height)
    destination = Path(staging_dir) / name
    destination.write_bytes(data)
    check_bmp(destination, width, height)
    with Image.open(archive) as image:
        source_pixels = image.convert("RGB").tobytes()
    with Image.open(destination) as image:
        if image.convert("RGB").tobytes() != source_pixels:
            raise RuntimeError(f"{name}: BMP pixels differ from the archived JPEG")
    return destination


def prepare_all(source_dir=SOURCE_DIR, staging_dir=STAGING_DIR, specs=SPECS):
    source_dir, staging_dir = Path(source_dir), Path(staging_dir)
    source_resolved, staging_resolved = source_dir.resolve(), staging_dir.resolve()
    if (source_resolved == staging_resolved or
            source_resolved in staging_resolved.parents or
            staging_resolved in source_resolved.parents):
        raise ValueError("staging must be separate from the sources")
    staging_dir.mkdir(parents=True, exist_ok=True)
    results = {}
    for name in specs:
        path = convert_one(name, source_dir, staging_dir, specs)
        results[name] = (path, path.stat().st_size)
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, default=SOURCE_DIR)
    parser.add_argument("--staging", type=Path, default=STAGING_DIR)
    args = parser.parse_args()
    results = prepare_all(args.sources, args.staging)
    for name, (path, size) in results.items():
        width, height = Image.open(path).size
        print(f"{name} OK: {width}x{height}, {size} bytes, sha256 {digest(path)}")


if __name__ == "__main__":
    main()
