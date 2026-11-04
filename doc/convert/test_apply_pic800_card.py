# -*- coding: utf-8 -*-
"""Safety tests for the 800x600 card apply (all 16 PIC files)."""
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from PIL import Image

import apply_pic800_card as apply_mod
from fetch_apple_cover_batch2 import MANIFEST_NAME, TRACKS as TRACKS_B2
from fetch_apple_cover_sources import META_FIELDS, TRACKS as TRACKS_B1
from prepare_hires_pic_card import digest
from prepare_pic800_card import NUMBERS, prepare_all

DIMS = (648, 480)


def make_jpeg(path, seed):
    image = Image.new("RGB", DIMS, (seed * 7 % 256, seed * 13 % 256, seed * 29 % 256))
    image.save(path, format="JPEG", quality=90)


class Pic800ApplyTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.card = root / "card"
        self.sources = root / "sources"
        self.staging = root / "staging"
        self.backup = root / "backup"
        for directory in (self.card, self.sources):
            directory.mkdir()
        for number in NUMBERS:
            make_jpeg(self.sources / f"PIC{number}.jpg", number)
        tracks_b1, tracks_b2 = {}, {}
        for number in NUMBERS:
            archive = self.sources / f"PIC{number}.jpg"
            if number in (1, 3):
                meta = TRACKS_B1[number]
                tracks_b1[str(number)] = {
                    **{field: meta[field] for field in META_FIELDS},
                    "width": meta["expected_width"],
                    "height": meta["expected_height"],
                    "jpeg_sha256": digest(archive),
                }
            else:
                meta = TRACKS_B2[number]
                tracks_b2[str(number)] = {
                    "status": "OK", "fallback": False,
                    "title": sorted(meta["titles"])[0],
                    "artist": sorted(meta["artists"])[0],
                    "album": "test", "track_id": number, "collection_id": number,
                    "page_url": "", "artwork_url_100": "", "download_url": "",
                    "width": DIMS[0], "height": DIMS[1],
                    "jpeg_sha256": digest(archive),
                    "jpeg_bytes": archive.stat().st_size,
                }
        (self.sources / "manifest.json").write_text(
            json.dumps({"tracks": tracks_b1}), encoding="utf-8")
        (self.sources / MANIFEST_NAME).write_text(
            json.dumps({"fetched_at": "test", "tracks": tracks_b2}), encoding="utf-8")
        prepare_all(self.sources, self.staging)
        for name in apply_mod.TARGETS:
            (self.card / name).write_bytes(b"old" + name.encode())
        self.sentinel_menu = self.card / "MENU.BMP"
        self.sentinel_menu.write_bytes(b"original menu")
        self.sentinel_wav = self.card / "SONG1.WAV"
        self.sentinel_wav.write_bytes(b"original wav")

    def tearDown(self):
        self.tmp.cleanup()

    def originals(self):
        return {name: digest(self.card / name) for name in apply_mod.TARGETS}

    def test_dry_run_validates_without_touching_card(self):
        before = self.originals()
        hashes = apply_mod.validate(self.card, self.staging, self.sources)
        self.assertEqual(len(hashes), 16)
        self.assertEqual(self.originals(), before)

    def test_tampered_staging_rejected(self):
        path = self.staging / "PIC7.BMP"
        raw = bytearray(path.read_bytes())
        raw[-1] ^= 0xFF
        path.write_bytes(bytes(raw))
        with self.assertRaises(ValueError):
            apply_mod.validate(self.card, self.staging, self.sources)

    def test_wrong_dimensions_rejected(self):
        path = self.staging / "PIC9.BMP"
        Image.new("RGB", (640, 480)).save(path, format="BMP")
        with self.assertRaises(ValueError):
            apply_mod.validate(self.card, self.staging, self.sources)

    def test_existing_backup_refuses(self):
        before = self.originals()
        self.backup.mkdir()
        with self.assertRaises(ValueError):
            apply_mod.apply(self.card, self.staging, self.backup, self.sources)
        self.assertEqual(self.originals(), before)

    def test_corrupt_write_rolls_back_everything(self):
        before = self.originals()
        before_menu = digest(self.sentinel_menu)
        real_copy = shutil.copyfile

        def corrupting_copy(src, dst):
            real_copy(src, dst)
            if (Path(src).parent == self.staging and
                    Path(dst).parent == self.card and
                    Path(dst).name == "PIC7.BMP"):
                Path(dst).write_bytes(b"corrupted")

        apply_mod.shutil.copyfile = corrupting_copy
        try:
            with self.assertRaises(RuntimeError):
                apply_mod.apply(self.card, self.staging, self.backup, self.sources)
        finally:
            apply_mod.shutil.copyfile = real_copy
        self.assertEqual(self.originals(), before)
        self.assertEqual(digest(self.sentinel_menu), before_menu)

    def test_success_writes_only_targets(self):
        before_menu = digest(self.sentinel_menu)
        before_wav = digest(self.sentinel_wav)
        apply_mod.apply(self.card, self.staging, self.backup, self.sources)
        for name in apply_mod.TARGETS:
            self.assertEqual(digest(self.card / name),
                             digest(self.staging / name))
        self.assertEqual(digest(self.sentinel_menu), before_menu)
        self.assertEqual(digest(self.sentinel_wav), before_wav)
        self.assertTrue((self.backup / "manifest.json").is_file())


if __name__ == "__main__":
    unittest.main()
