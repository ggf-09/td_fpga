"""Card-title normalization and shared/banked LFNT coverage regressions."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

CONVERT = Path(__file__).resolve().parents[2] / "doc" / "convert"
sys.path.insert(0, str(CONVERT))
import prepare_music_card as card


class CardMetadataTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent)
        self.folder = Path(self.tmp.name)
        # These tests check maps, limits and layout. They do not depend on a
        # particular computer's installed font or on rasterization differences.
        self.font = patch.object(card.ImageFont, "truetype", return_value=object())
        self.rows = patch.object(card, "glyph_rows", return_value=[0] * 16)
        self.tempdir = patch.object(tempfile, "tempdir", str(self.folder))
        self.font.start()
        self.rows.start()
        self.tempdir.start()

    def tearDown(self):
        self.rows.stop()
        self.font.stop()
        self.tempdir.stop()
        self.tmp.cleanup()

    def source(self, text, name="SONG1.LRC", encoding="utf-8"):
        path = self.folder / name
        path.write_bytes(text.encode(encoding))
        return path

    @staticmethod
    def timed(text):
        return "".join(f"[{i // 60:02d}:{i % 60:02d}.00]{text[p:p+31]}\n"
                       for i, p in enumerate(range(0, len(text), 31)))

    @staticmethod
    def font_map(data, start=0):
        assert data[start:start+4] == b"LFNT"
        count = int.from_bytes(data[start+5:start+7], "little")
        return {chr(int.from_bytes(data[start+8+2*i:start+10+2*i], "little"))
                for i in range(count)}

    def test_bom_title_and_normalized_lrc(self):
        source = self.source("[ti: 新歌名 ]\r\n[ar:不要附加]\r\n"
                             "[0:02.1][0:01.200]歌词\r\n", encoding="utf-8-sig")
        self.assertEqual(card.read_card_title(source), "新歌名")
        self.assertEqual(card.normalize_card_lrc(source).decode("utf-8"),
                         "[ti:新歌名]\n[00:01.20]歌词\n[00:02.10]歌词\n")
        dest = self.folder / "FONT.BIN"
        card.write_card_font([source], dest)
        self.assertTrue(set("新歌名歌词").issubset(self.font_map(dest.read_bytes())))

    def test_gb18030_and_case_insensitive_title(self):
        source = self.source("[TI:中文歌名]\n[00:01.00]歌词\n", encoding="gb18030")
        self.assertEqual(card.read_card_title(source), "中文歌名")
        self.assertIn("[ti:中文歌名]\n".encode(), card.normalize_card_lrc(source))

    def test_empty_title_and_no_tag_compatibility(self):
        source = self.source("[ti: ]\n[00:01.00]歌词\n")
        self.assertEqual(card.read_card_title(source), "")
        self.assertEqual(card.normalize_card_lrc(source), "[ti:]\n[00:01.00]歌词\n".encode())
        source = self.source("[00:01.00]歌词\n")
        self.assertEqual(card.read_card_title(source), "")
        self.assertEqual(card.normalize_card_lrc(source), "[00:01.00]歌词\n".encode())

    def test_title_31_character_truncation(self):
        title = "".join(chr(0x4e00+i) for i in range(40))
        source = self.source(f"[ti:{title}]\n[00:01.00]词\n")
        self.assertEqual(card.read_card_title(source), title[:31])
        normalized = card.normalize_card_lrc(source).decode()
        self.assertEqual(normalized.splitlines()[0], f"[ti:{title[:31]}]")
        dest = self.folder / "FONT.BIN"
        card.write_card_font([source], dest)
        self.assertNotIn(title[31], self.font_map(dest.read_bytes()))

    def test_brackets_and_newlines_cannot_inject_metadata(self):
        source = self.source("[ti:  标题\t 名 ]残留]\n另起一行]\n[ar:歌手]\n[00:01.00]词\n")
        normalized = card.normalize_card_lrc(source).decode()
        self.assertEqual(normalized, "[ti:标题 名]\n[00:01.00]词\n")
        source = self.source("[ti:标题\n另起一行]\n[00:01.00]词\n")
        self.assertEqual(card.read_card_title(source), "标题")
        self.assertEqual(card.normalize_card_lrc(source).decode(), "[ti:标题]\n[00:01.00]词\n")

    def test_reject_non_bmp_title_even_beyond_truncation(self):
        source = self.source("[ti:" + "歌" * 31 + "😀]\n[00:01.00]词\n")
        with self.assertRaisesRegex(ValueError, "title.*U\\+1F600"):
            card.normalize_card_lrc(source)
        source = self.source("[ti:歌名]\n[00:01.00]😀\n")
        with self.assertRaisesRegex(ValueError, "lyric.*U\\+1F600"):
            card.normalize_card_lrc(source)
        source = self.source("[ti:歌\x00名]\n")
        with self.assertRaisesRegex(ValueError, "title.*U\\+0000"):
            card.read_card_title(source)

    def test_shared_font_includes_title_only_characters(self):
        p1 = self.source("[ti:独有标题]\n[00:01.00]词\n")
        p2 = self.source("[ti:另外名字]\n[00:01.00]词\n", "SONG2.LRC")
        dest = self.folder / "FONT.BIN"
        self.assertIn("shared", card.write_music_fonts({1:p1, 2:p2}, dest))
        self.assertEqual(len(dest.read_bytes()), 8712)
        self.assertTrue(set("独有标题另外名字词").issubset(self.font_map(dest.read_bytes())))

    def test_banked_fonts_include_each_tracks_title(self):
        chars1 = "".join(chr(0x4e00+i) for i in range(140))
        chars2 = "".join(chr(0x4f00+i) for i in range(140))
        p1 = self.source("[ti:䀀]\n" + self.timed(chars1))
        p2 = self.source("[ti:䀁]\n" + self.timed(chars2), "SONG2.LRC")
        dest = self.folder / "FONT.BIN"
        self.assertIn("per-track", card.write_music_fonts({1:p1, 2:p2}, dest))
        data = dest.read_bytes()
        self.assertEqual(len(data), 65536)
        self.assertTrue(set(chars1+"䀀").issubset(self.font_map(data, 0)))
        self.assertTrue(set(chars2+"䀁").issubset(self.font_map(data, 16384)))
        self.assertNotIn("䀁", self.font_map(data, 0))
        self.assertEqual(self.font_map(data, 32768), set(" ?"))
        self.assertEqual(self.font_map(data, 49152), set(" ?"))

    def test_title_can_exceed_per_track_font_limit(self):
        chars = "".join(chr(0x4e00+i) for i in range(254))
        source = self.source("[ti:䀀]\n" + self.timed(chars))
        with self.assertRaisesRegex(ValueError, "256 unique characters; got 257"):
            card.write_music_fonts({1:source}, self.folder / "FONT.BIN")

    def test_title_does_not_consume_cue_or_text_limits(self):
        title = "歌" * 31
        body = "".join(f"[{i // 60:02d}:{i % 60:02d}.00]词\n" for i in range(126))
        source = self.source(f"[ti:{title}]\n" + body)
        self.assertEqual(card.normalize_card_lrc(source).count(b"["), 127)
        source = self.source(f"[ti:{title}]\n" + self.timed("x" * 2048))
        self.assertTrue(card.normalize_card_lrc(source).startswith(f"[ti:{title}]\n".encode()))

    def test_extended_158_cue_and_3072_text_limits(self):
        body = "".join(f"[{i // 60:02d}:{i % 60:02d}.00]词\n" for i in range(158))
        source = self.source("[ti:名]\n" + body)
        self.assertEqual(card.normalize_card_lrc(source).count(b"["),159)
        body += "[02:38.00]词\n"
        source = self.source("[ti:名]\n" + body)
        with self.assertRaisesRegex(ValueError, "158 timed lines"):
            card.normalize_card_lrc(source)
        source = self.source("[ti:名]\n" + self.timed("x" * 3073))
        with self.assertRaisesRegex(ValueError, "3072 displayed characters"):
            card.normalize_card_lrc(source)

    def test_complete_long_english_subtitles(self):
        body="".join(f"[{i//60:02d}:{i%60:02d}.00]"+"x"*18+"\n" for i in range(132))
        source=self.source("[ti:完整]\n"+body)
        normalized=card.normalize_card_lrc(source)
        self.assertEqual(normalized.count(b"["),133)
        self.assertEqual(normalized.count(b"x"),2376)

    def test_library_16_banks_keep_global_slot_numbers(self):
        first=self.source(self.timed("".join(chr(0x4e00+i) for i in range(150))),"SONG1.LRC")
        last=self.source("[ti:终曲]\n"+self.timed("".join(chr(0x5000+i) for i in range(150))),"SONG16.LRC")
        target=self.folder/"FONT.BIN"
        card.write_music_fonts({1:first,16:last},target)
        data=target.read_bytes()
        self.assertEqual(len(data),262144)
        self.assertIn("终",self.font_map(data,15*16384))
        self.assertNotIn("终",self.font_map(data,0))
        self.assertEqual(self.font_map(data,4*16384),set(" ?"))

    def test_library_shared_font_still_supports_track16(self):
        source=self.source("[ti:终]\n[00:00.00]曲\n","SONG16.LRC")
        target=self.folder/"FONT.BIN"
        card.write_music_fonts({16:source},target)
        self.assertEqual(target.stat().st_size,8712)
        self.assertTrue(set("终曲").issubset(self.font_map(target.read_bytes())))

    def test_library_rejects_slots_outside_1_to_16(self):
        source=self.source("[00:00.00]词\n")
        for number in [0,17]:
            with self.assertRaisesRegex(ValueError,"1 and 16"):
                card.write_music_fonts({number:source},self.folder/"FONT.BIN")

    def test_complete_file_4096_byte_limit_includes_title(self):
        body = self.timed("词" * (39*31))
        source = self.source(body)
        self.assertLess(len(card.normalize_card_lrc(source)), 4096)
        source = self.source("[ti:" + "歌" * 31 + "]\n" + body)
        with self.assertRaisesRegex(ValueError, "4096 bytes"):
            card.normalize_card_lrc(source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
