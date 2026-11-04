# -*- coding: utf-8 -*-
"""Convert the batch-2 archived Apple covers to no-resize 24-bit BMPs.

Same rules as batch 1 (prepare_hires_pic_card.py): the only transformation
is Image.open(archive).convert('RGB').save(BMP).  Dimensions and SHA-256 are
cross-checked against cover_sources/manifest_batch2.json, and the manifest's
title/artist are rechecked against the curated accept lists in
fetch_apple_cover_batch2.py so a wrong-song archive can never reach the card.
Output goes to staging_hires_pic_batch2_20261025/.
"""
import argparse
import json
from pathlib import Path

from PIL import Image

from fetch_apple_cover_batch2 import MANIFEST_NAME, TRACKS, norm
from prepare_hires_pic_card import canonical_bmp_bytes, check_bmp, digest

HERE = Path(__file__).resolve().parent
SOURCE_DIR = HERE / "cover_sources"
STAGING_DIR = HERE / "staging_hires_pic_batch2_20261025"


def load_manifest(source_dir=SOURCE_DIR):
    return json.loads((Path(source_dir) / MANIFEST_NAME).read_text(encoding="utf-8"))


def specs_from_manifest(manifest):
    """PICn.BMP -> (number, width, height) for every verified OK slot."""
    specs = {}
    for key, entry in manifest["tracks"].items():
        if entry.get("status") != "OK":
            raise ValueError(f"PIC{key}: manifest slot is not verified OK")
        specs[f"PIC{int(key)}.BMP"] = (int(key), entry["width"], entry["height"])
    if sorted(n for n, _, _ in specs.values()) != sorted(TRACKS):
        raise ValueError("manifest slots differ from the curated track list")
    return specs


def manifest_entry(source_dir, number, width, height, manifest=None):
    """Return the archive path after cross-checking song, dims and hash."""
    source_dir = Path(source_dir)
    manifest = manifest or load_manifest(source_dir)
    entry = manifest["tracks"][str(number)]
    meta = TRACKS[number]
    titles = set(meta["titles"]) | set(meta.get("fallback_titles", set()))
    artists = set(meta["artists"]) | set(meta.get("fallback_artists", set()))
    if norm(entry["title"]) not in {norm(t) for t in titles}:
        raise ValueError(f"PIC{number}: manifest title is not an accepted song title")
    if not any(norm(a) in norm(entry["artist"]) for a in artists):
        raise ValueError(f"PIC{number}: manifest artist is not an accepted artist")
    if (entry.get("width"), entry.get("height")) != (width, height):
        raise ValueError(f"PIC{number}: manifest dimensions differ from the "
                         f"required {width}x{height}")
    archive = source_dir / f"PIC{number}.jpg"
    if digest(archive) != entry.get("jpeg_sha256"):
        raise ValueError(f"PIC{number}: archived JPEG hash differs from the manifest")
    return archive


def convert_one(name, source_dir=SOURCE_DIR, staging_dir=STAGING_DIR, specs=None):
    manifest = load_manifest(source_dir)
    specs = specs or specs_from_manifest(manifest)
    number, width, height = specs[name]
    archive = manifest_entry(source_dir, number, width, height, manifest)
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


def prepare_all(source_dir=SOURCE_DIR, staging_dir=STAGING_DIR):
    source_dir, staging_dir = Path(source_dir), Path(staging_dir)
    source_resolved, staging_resolved = source_dir.resolve(), staging_dir.resolve()
    if (source_resolved == staging_resolved or
            source_resolved in staging_resolved.parents or
            staging_resolved in source_resolved.parents):
        raise ValueError("staging must be separate from the sources")
    staging_dir.mkdir(parents=True, exist_ok=True)
    specs = specs_from_manifest(load_manifest(source_dir))
    return {name: convert_one(name, source_dir, staging_dir, specs) for name in specs}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, default=SOURCE_DIR)
    parser.add_argument("--staging", type=Path, default=STAGING_DIR)
    args = parser.parse_args()
    results = prepare_all(args.sources, args.staging)
    for name, path in sorted(results.items()):
        width, height = Image.open(path).size
        print(f"{name} OK: {width}x{height}, {path.stat().st_size} bytes, "
              f"sha256 {digest(path)}")


if __name__ == "__main__":
    main()
