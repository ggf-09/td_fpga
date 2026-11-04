# -*- coding: utf-8 -*-
import hashlib
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import apply_krc_timing_card as apply_module
from fetch_kugou_krc import TRACKS
from prepare_music_card import write_card_font
from prepare_scrolling_lyrics import write_track


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def make_template(folder):
    card, staged = folder / "card", folder / "staged"
    card.mkdir()
    staged.mkdir()
    banks = bytearray()
    for number in range(1, 17):
        title = TRACKS[number]["display_title"] if number in TRACKS else f"曲{number}"
        lrc = card / f"SONG{number}.LRC"
        lrc.write_bytes(f"[ti:{title}]\n[00:01.00]旧词{number}\n".encode("utf-8"))
        slot = folder / f"old{number}.bin"
        write_card_font([lrc], slot)
        bank = bytearray(slot.read_bytes())
        bank.extend(bytes(16384 - len(bank)))
        bank[8712:8720] = b"LKT1" + (3).to_bytes(2, "little") + bytes((4, 2))
        banks.extend(bank)
    (card / "FONT.BIN").write_bytes(banks)
    for number in (1, 2):
        (card / f"SONG{number}.WAV").write_bytes(b"test placeholder; WAV check is mocked")

    staged_font = bytearray((card / "FONT.BIN").read_bytes())
    for number in (1, 2):
        slot = folder / f"new{number}.bin"
        write_track(ROOT / "krc_sources" / f"SONG{number}.krc",
                    TRACKS[number]["display_title"], staged / f"SONG{number}.LRC", slot)
        start = (number - 1) * 16384
        staged_font[start:start + 16384] = slot.read_bytes()
    (staged / "FONT.BIN").write_bytes(staged_font)


class KrcTimingCard(unittest.TestCase):
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
        self.card, self.staged = root / "card", root / "staged"
        shutil.copytree(self.template / "card", self.card)
        shutil.copytree(self.template / "staged", self.staged)
        self.backup = root / "backup"
        wav_check = mock.patch.object(apply_module, "verify_wav",
                                      side_effect=lambda path, expected: expected)
        wav_check.start()
        self.addCleanup(wav_check.stop)

    def validate(self):
        return apply_module.validate(self.card, self.staged)

    def test_valid_staging(self):
        self.assertEqual(set(self.validate()), set(apply_module.TARGETS))
        font = (self.staged / "FONT.BIN").read_bytes()
        self.assertEqual((font[8719], font[16384 + 8719]), (1, 1))

    def test_other_bank_change_rejected(self):
        font = bytearray((self.staged / "FONT.BIN").read_bytes())
        font[2 * 16384 + 100] ^= 1
        (self.staged / "FONT.BIN").write_bytes(font)
        with self.assertRaisesRegex(ValueError, "other FONT banks"):
            self.validate()

    def test_estimated_quality_rejected(self):
        font = bytearray((self.staged / "FONT.BIN").read_bytes())
        font[8719] = 2
        (self.staged / "FONT.BIN").write_bytes(font)
        with self.assertRaisesRegex(ValueError, "LKT1"):
            self.validate()

    def test_wrong_timing_payload_rejected(self):
        font = bytearray((self.staged / "FONT.BIN").read_bytes())
        font[9216] ^= 1
        (self.staged / "FONT.BIN").write_bytes(font)
        with self.assertRaisesRegex(ValueError, "timing payload"):
            self.validate()

    def test_wrong_title_rejected(self):
        path = self.staged / "SONG1.LRC"
        raw = path.read_bytes()
        path.write_bytes(b"[ti:wrong]\n" + raw.split(b"\n", 1)[1])
        with self.assertRaisesRegex(ValueError, "title"):
            self.validate()

    def test_apply_backup_and_readback(self):
        original = {name: digest(self.card / name) for name in apply_module.TARGETS}
        apply_module.apply(self.card, self.staged, self.backup)
        for name in apply_module.TARGETS:
            self.assertEqual(digest(self.card / name), digest(self.staged / name))
            self.assertEqual(digest(self.backup / name), original[name])
        self.assertTrue((self.backup / "manifest.json").is_file())

    def test_failed_readback_restores_all_originals(self):
        original = {name: digest(self.card / name) for name in apply_module.TARGETS}
        real_copy = shutil.copyfile

        def corrupt_staged_write(source, destination):
            real_copy(source, destination)
            if Path(source).parent == self.staged and Path(destination).name == "SONG1.LRC":
                with open(destination, "ab") as output:
                    output.write(b"corrupt")

        with mock.patch.object(apply_module.shutil, "copyfile", side_effect=corrupt_staged_write):
            with self.assertRaisesRegex(RuntimeError, "readback mismatch"):
                apply_module.apply(self.card, self.staged, self.backup)
        for name in apply_module.TARGETS:
            self.assertEqual(digest(self.card / name), original[name], name)


if __name__ == "__main__":
    unittest.main()
