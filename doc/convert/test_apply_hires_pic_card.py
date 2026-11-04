# -*- coding: utf-8 -*-
import hashlib
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from PIL import Image

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import apply_hires_pic_card as apply_module
import fetch_apple_cover_sources as fetch_module
import prepare_hires_pic_card as prepare_module

SMALL_SPECS = {"PIC1.BMP": (1, 64, 48), "PIC3.BMP": (3, 40, 48)}
SMALL_DIMS = {number: (width, height)
              for number, width, height in SMALL_SPECS.values()}
SENTINELS = ["PIC2.BMP", "PIC4.BMP", "SONG1.WAV", "SONG3.WAV",
             "SONG1.LRC", "FONT.BIN", "MENU.BMP"]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def make_jpeg(path, size, seed):
    image = Image.new("RGB", size)
    pixels = image.load()
    for y in range(size[1]):
        for x in range(size[0]):
            pixels[x, y] = ((x * 3 + seed) % 256, (y * 5 + seed) % 256,
                            (x + y + seed) % 256)
    image.save(path, format="JPEG", quality=95)


def make_template(folder):
    sources, staged, card = folder / "sources", folder / "staged", folder / "card"
    for path in (sources, staged, card):
        path.mkdir()
    tracks = {}
    for name, (number, width, height) in SMALL_SPECS.items():
        archive = sources / f"PIC{number}.jpg"
        make_jpeg(archive, (width, height), number)
        meta = fetch_module.TRACKS[number]
        entry = {field: meta[field] for field in fetch_module.META_FIELDS}
        entry.update({"jpeg_sha256": digest(archive),
                      "jpeg_bytes": archive.stat().st_size,
                      "width": width, "height": height,
                      "download_url": "https://example.invalid/1200x1200bb.jpg"})
        tracks[str(number)] = entry
    (sources / "manifest.json").write_text(json.dumps(
        {"fetched_at": "2026-10-25T00:00:00+00:00", "tracks": tracks},
        ensure_ascii=False, indent=2), encoding="utf-8")
    for name, (number, _, _) in SMALL_SPECS.items():
        prepare_module.convert_one(name, sources, staged, SMALL_SPECS)
        Image.new("RGB", (8, 8), (number * 10, 0, 0)).save(card / name, format="BMP")
    for sentinel in SENTINELS:
        (card / sentinel).write_bytes(f"sentinel {sentinel}".encode("ascii"))


class HiresPicCard(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template_tmp = tempfile.TemporaryDirectory()
        cls.template = Path(cls.template_tmp.name) / "template"
        cls.template.mkdir()
        make_template(cls.template)

    @classmethod
    def tearDownClass(cls):
        cls.template_tmp.cleanup()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.card, self.staged, self.sources = (root / "card", root / "staged",
                                                root / "sources")
        for name in ("card", "staged", "sources"):
            shutil.copytree(self.template / name, root / name)
        self.backup = root / "backup"

    def validate(self):
        return apply_module.validate(self.card, self.staged, self.sources, SMALL_SPECS)

    def apply(self):
        return apply_module.apply(self.card, self.staged, self.backup,
                                  self.sources, SMALL_SPECS)

    def sentinel_digests(self):
        return {name: digest(self.card / name) for name in SENTINELS}

    def test_valid_staging_dry_run(self):
        before = {name: digest(self.card / name) for name in apply_module.TARGETS}
        self.assertEqual(set(self.validate()), set(apply_module.TARGETS))
        after = {name: digest(self.card / name) for name in apply_module.TARGETS}
        self.assertEqual(before, after)
        self.assertEqual(before["PIC1.BMP"], digest(self.template / "card" / "PIC1.BMP"))

    def test_apply_backup_and_readback(self):
        original = {name: digest(self.card / name) for name in apply_module.TARGETS}
        sentinels = self.sentinel_digests()
        self.apply()
        for name in apply_module.TARGETS:
            self.assertEqual(digest(self.card / name), digest(self.staged / name))
            self.assertEqual(digest(self.backup / name), original[name])
        self.assertTrue((self.backup / "manifest.json").is_file())
        self.assertEqual(self.sentinel_digests(), sentinels)

    def test_wrong_dimensions_rejected(self):
        Image.new("RGB", (32, 32), (1, 2, 3)).save(self.staged / "PIC1.BMP",
                                                   format="BMP")
        with self.assertRaisesRegex(ValueError, "unexpected dimensions"):
            self.validate()

    def test_swapped_dimensions_rejected(self):
        Image.new("RGB", (48, 64), (1, 2, 3)).save(self.staged / "PIC1.BMP",
                                                   format="BMP")
        with self.assertRaisesRegex(ValueError, "unexpected dimensions"):
            self.validate()

    def test_non_24bit_rejected(self):
        raw = bytearray((self.staged / "PIC1.BMP").read_bytes())
        raw[28:30] = (32).to_bytes(2, "little")
        (self.staged / "PIC1.BMP").write_bytes(raw)
        with self.assertRaisesRegex(ValueError, "24-bit"):
            self.validate()

    def test_nonzero_compression_rejected(self):
        raw = bytearray((self.staged / "PIC1.BMP").read_bytes())
        raw[30:34] = (1).to_bytes(4, "little")
        (self.staged / "PIC1.BMP").write_bytes(raw)
        with self.assertRaisesRegex(ValueError, "compression"):
            self.validate()

    def test_staged_pixel_tamper_rejected(self):
        raw = bytearray((self.staged / "PIC3.BMP").read_bytes())
        raw[100] ^= 1
        (self.staged / "PIC3.BMP").write_bytes(raw)
        with self.assertRaisesRegex(ValueError, "does not match the archived"):
            self.validate()

    def test_existing_backup_rejected(self):
        original = {name: digest(self.card / name) for name in apply_module.TARGETS}
        self.backup.mkdir()
        with self.assertRaisesRegex(ValueError, "already exists"):
            self.apply()
        for name in apply_module.TARGETS:
            self.assertEqual(digest(self.card / name), original[name], name)

    def test_failed_readback_restores_both_originals(self):
        original = {name: digest(self.card / name) for name in apply_module.TARGETS}
        sentinels = self.sentinel_digests()
        real_copy = shutil.copyfile

        def corrupt_staged_write(source, destination):
            real_copy(source, destination)
            if (Path(source).parent == self.staged and
                    Path(destination).name == "PIC3.BMP"):
                with open(destination, "ab") as output:
                    output.write(b"corrupt")

        with mock.patch.object(apply_module.shutil, "copyfile",
                               side_effect=corrupt_staged_write):
            with self.assertRaisesRegex(RuntimeError, "readback mismatch"):
                self.apply()
        for name in apply_module.TARGETS:
            self.assertEqual(digest(self.card / name), original[name], name)
        self.assertEqual(self.sentinel_digests(), sentinels)

    def test_offline_verify_ok(self):
        manifest = fetch_module.verify_all(self.sources, SMALL_DIMS)
        self.assertEqual(set(manifest["tracks"]), {"1", "3"})

    def test_offline_verify_manifest_hash_mismatch(self):
        path = self.sources / "manifest.json"
        manifest = json.loads(path.read_text(encoding="utf-8"))
        manifest["tracks"]["1"]["jpeg_sha256"] = "0" * 64
        path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2),
                        encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "differs from the manifest"):
            fetch_module.verify_all(self.sources, SMALL_DIMS)

    def test_offline_verify_archive_tamper_rejected(self):
        archive = self.sources / "PIC3.jpg"
        raw = bytearray(archive.read_bytes())
        raw[-1] ^= 1
        archive.write_bytes(raw)
        with self.assertRaisesRegex(ValueError, "cannot decode|differs from the manifest"):
            fetch_module.verify_all(self.sources, SMALL_DIMS)

    def test_offline_verify_metadata_mismatch_rejected(self):
        path = self.sources / "manifest.json"
        manifest = json.loads(path.read_text(encoding="utf-8"))
        manifest["tracks"]["3"]["title"] = "别的歌"
        path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2),
                        encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "track metadata"):
            fetch_module.verify_all(self.sources, SMALL_DIMS)


if __name__ == "__main__":
    unittest.main()
