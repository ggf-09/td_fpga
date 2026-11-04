# -*- coding: utf-8 -*-
"""Re-encode all 16 verified Apple cover archives as 800x600 24-bit BMPs.

Reason (2026-10-26 board feedback): 1200x1200 covers are ~4.3MB each, so a
page crossing reloads ~17MB through the shared SD streamer and the page
router holds audio/video until the whole page commits - 6..8s of black.
800x600 cuts each file to 1,440,054 bytes (~2s per page crossing) while the
FPGA still performs a real 800x600 -> 640x480 load-time scale, so the
on-screen result and the resolution OSD story are unchanged.  This is a
card-side re-encode only; the RTL and the bitstream are not touched.

Safety chain is identical to the hi-res batches: each archived JPEG must
pass its own manifest cross-check (batch 1: PIC1/PIC3 against
cover_sources/manifest.json; batch 2: the rest against
manifest_batch2.json) including the SHA-256 pin, then the BMP is validated
field by field and its pixels must equal a fresh resize of the archive.
Output goes to staging_pic800_20261026/.
"""
import argparse
import io
import json
from pathlib import Path

from PIL import Image

from fetch_apple_cover_sources import TRACKS as TRACKS_B1
from prepare_hires_pic_card import (check_bmp, digest,
                                    manifest_entry as entry_b1)
from prepare_hires_pic_batch2 import (load_manifest as load_manifest_b2,
                                      manifest_entry as entry_b2,
                                      specs_from_manifest)

HERE = Path(__file__).resolve().parent
SOURCE_DIR = HERE / "cover_sources"
STAGING_DIR = HERE / "staging_pic800_20261026"
OUT_W, OUT_H = 800, 600
BATCH1 = (1, 3)
NUMBERS = list(range(1, 17))


def pic800_bmp_bytes(archive):
    """The only permitted conversion: verified archive -> 800x600 BMP."""
    with Image.open(archive) as image:
        if image.format != "JPEG" or image.mode != "RGB":
            raise ValueError(f"{Path(archive).name}: expected an RGB JPEG archive")
        # 直接拉伸到800x600（不加黑边），与FPGA输出端的拉伸规则一致；
        # LANCZOS在同一Pillow版本下是确定性的，apply校验可逐字节复算。
        rgb = image.convert("RGB").resize((OUT_W, OUT_H), Image.LANCZOS)
        buffer = io.BytesIO()
        rgb.save(buffer, format="BMP")
    return buffer.getvalue()


def verified_archive(source_dir, number, manifest_b2=None):
    """Return the archive path after the slot's own manifest cross-check."""
    source_dir = Path(source_dir)
    if number in BATCH1:
        meta = TRACKS_B1[number]
        return entry_b1(source_dir, number,
                        meta["expected_width"], meta["expected_height"])
    manifest_b2 = manifest_b2 or load_manifest_b2(source_dir)
    specs = specs_from_manifest(manifest_b2)
    _, width, height = specs[f"PIC{number}.BMP"]
    return entry_b2(source_dir, number, width, height, manifest_b2)


def convert_one(number, source_dir=SOURCE_DIR, staging_dir=STAGING_DIR,
                manifest_b2=None):
    name = f"PIC{number}.BMP"
    archive = verified_archive(source_dir, number, manifest_b2)
    data = pic800_bmp_bytes(archive)
    if len(data) != 54 + OUT_W * OUT_H * 3:
        raise RuntimeError(f"{name}: unexpected 800x600 BMP size {len(data)}")
    destination = Path(staging_dir) / name
    destination.write_bytes(data)
    check_bmp(destination, OUT_W, OUT_H)
    with Image.open(archive) as image:
        source_pixels = image.convert("RGB").resize((OUT_W, OUT_H),
                                                    Image.LANCZOS).tobytes()
    with Image.open(destination) as image:
        if image.convert("RGB").tobytes() != source_pixels:
            raise RuntimeError(f"{name}: BMP pixels differ from the archive resize")
    return destination


def prepare_all(source_dir=SOURCE_DIR, staging_dir=STAGING_DIR):
    source_dir, staging_dir = Path(source_dir), Path(staging_dir)
    source_resolved, staging_resolved = source_dir.resolve(), staging_dir.resolve()
    if (source_resolved == staging_resolved or
            source_resolved in staging_resolved.parents or
            staging_resolved in source_resolved.parents):
        raise ValueError("staging must be separate from the sources")
    staging_dir.mkdir(parents=True, exist_ok=True)
    manifest_b2 = load_manifest_b2(source_dir)
    return {number: convert_one(number, source_dir, staging_dir, manifest_b2)
            for number in NUMBERS}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, default=SOURCE_DIR)
    parser.add_argument("--staging", type=Path, default=STAGING_DIR)
    args = parser.parse_args()
    results = prepare_all(args.sources, args.staging)
    for number, path in sorted(results.items()):
        width, height = Image.open(path).size
        print(f"PIC{number}.BMP OK: {width}x{height}, {path.stat().st_size} bytes, "
              f"sha256 {digest(path)}")


if __name__ == "__main__":
    main()
