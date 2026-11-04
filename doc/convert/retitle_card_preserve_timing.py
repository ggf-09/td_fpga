# -*- coding: utf-8 -*-
"""Retitle card SONG1..16.LRC as "title - artist" without touching timing.

Only the [ti:] line changes in each LRC; every byte after the first line
break (all lyric text and timestamps) is copied verbatim. Each FONT.BIN bank
gets a freshly rendered LFNT glyph region covering the new title plus the
unchanged lyrics, while bytes 8712..16383 (the LKT1 per-character timing
tail) are copied byte-for-byte from the source card's bank. The ordinary
per-character timing generation flow is never re-run.

PIC/WAV/FLAC files are read (PICs feed MENU.BMP) but never modified, and
nothing is written back to the card.

Usage: python retitle_card_preserve_timing.py [--card-root E:\\]
       [--output-dir staging_artist_20261025] [--artists card_artists.json]
"""

import argparse
import codecs
import hashlib
import json
import re
import shutil
import tempfile
from pathlib import Path

from generate_music_lyrics import read_lrc
from prepare_library_menu import build_menu
from prepare_music_card import (read_card_title, write_card_font,
                                _validate_card_characters)

HERE = Path(__file__).resolve().parent
BANK_SIZE = 16384
LFNT_SIZE = 8712
MAX_TITLE_CHARS = 31
MAX_LRC_BYTES = 4096
MAX_GLYPHS = 256


def load_artists(path):
    artists = json.loads(Path(path).read_text(encoding="utf-8"))
    result = {}
    for number in range(1, 17):
        artist = artists.get(str(number), "").strip()
        if not artist:
            raise ValueError(f"card_artists.json: missing artist for track {number}")
        _validate_card_characters(path, artist, "artist")
        result[number] = artist
    return result


def artist_title(title, artist):
    """Add an artist once, so regenerating from an updated card is safe."""
    suffix = f" - {artist}"
    return title if title.endswith(suffix) else title + suffix


def retitle_lrc_bytes(raw, new_title, name):
    """Replace only the [ti:] line; keep every later byte identical."""
    bom, body = b"", raw
    if body.startswith(codecs.BOM_UTF8):
        bom, body = codecs.BOM_UTF8, body[len(codecs.BOM_UTF8):]
    first, sep, rest = body.partition(b"\n")
    if not sep or not re.match(rb"\[ti:[^\]\r\n]*\]", first, re.IGNORECASE):
        raise ValueError(f"{name}: first line must be a [ti:] tag")
    cr = b"\r" if first.endswith(b"\r") else b""
    return bom + b"[ti:" + new_title.encode("utf-8") + b"]" + cr + sep + rest


def build_bank(new_lrc_path, source_bank, scratch, name):
    """Render LFNT for the retitled song; copy the source bank tail verbatim."""
    if len(source_bank) != BANK_SIZE or source_bank[:4] != b"LFNT":
        raise ValueError(f"{name}: source FONT.BIN bank is not a 16-KiB LFNT bank")
    slot = Path(scratch) / "slot.bin"
    glyphs = write_card_font([new_lrc_path], slot)
    lfnt = slot.read_bytes()
    if len(lfnt) != LFNT_SIZE:
        raise RuntimeError("unexpected LFNT length")
    return lfnt + source_bank[LFNT_SIZE:], glyphs


def build(card_root, output_dir, artists_path):
    card_root = Path(card_root).resolve()
    output_dir = Path(output_dir).resolve()
    if output_dir == card_root or card_root in output_dir.parents:
        raise ValueError("output directory must be separate from the card root")
    if not card_root.is_dir():
        raise ValueError(f"card root does not exist: {card_root}")
    artists = load_artists(artists_path)
    source_font = card_root / "FONT.BIN"
    if not source_font.is_file() or source_font.stat().st_size != 16 * BANK_SIZE:
        raise ValueError("card FONT.BIN must contain sixteen 16-KiB banks")
    source_banks = source_font.read_bytes()

    output_dir.mkdir(parents=True, exist_ok=True)
    report = {"tracks": {}, "tails_preserved": True}
    banks = bytearray()
    with tempfile.TemporaryDirectory(dir=output_dir) as scratch:
        for number in range(1, 17):
            name = f"SONG{number}.LRC"
            source_lrc = card_root / name
            if not source_lrc.is_file():
                raise ValueError(f"missing {source_lrc}")
            raw = source_lrc.read_bytes()
            title = read_card_title(source_lrc)
            if not title:
                raise ValueError(f"{name}: no usable [ti:] title on the card")
            new_title = artist_title(title, artists[number])
            _validate_card_characters(name, new_title, "title")
            if len(new_title) > MAX_TITLE_CHARS:
                raise ValueError(
                    f"{name}: retitled heading {new_title!r} exceeds "
                    f"{MAX_TITLE_CHARS} display characters")
            new_raw = retitle_lrc_bytes(raw, new_title, name)
            if len(new_raw) > MAX_LRC_BYTES:
                raise ValueError(f"{name}: retitled LRC exceeds {MAX_LRC_BYTES} bytes")
            new_lrc = output_dir / name
            new_lrc.write_bytes(new_raw)
            # Lyric cues and timestamps must be semantically identical.
            if read_lrc(source_lrc, max_chars=31) != read_lrc(new_lrc, max_chars=31):
                raise RuntimeError(f"{name}: timed lyric entries changed")
            # Everything after the title line must be byte-identical.
            if raw.split(b"\n", 1)[1] != new_raw.split(b"\n", 1)[1]:
                raise RuntimeError(f"{name}: lyric body bytes changed")

            bank, glyphs = build_bank(
                new_lrc, source_banks[(number - 1) * BANK_SIZE:number * BANK_SIZE],
                scratch, name)
            if bank[LFNT_SIZE:] != source_banks[
                    (number - 1) * BANK_SIZE + LFNT_SIZE:number * BANK_SIZE]:
                raise RuntimeError(f"{name}: bank tail was not preserved verbatim")
            banks.extend(bank)
            report["tracks"][number] = {
                "title": new_title, "title_chars": len(new_title),
                "lrc_bytes": len(new_raw), "glyphs": glyphs,
                "sha256": hashlib.sha256(new_raw).hexdigest(),
            }

        font_path = output_dir / "FONT.BIN"
        font_path.write_bytes(bytes(banks))
        report["font_sha256"] = hashlib.sha256(bytes(banks)).hexdigest()

        # MENU.BMP from the original PIC covers plus the retitled LRCs.
        menu_folder = Path(scratch) / "menu"
        menu_folder.mkdir()
        for number in range(1, 17):
            pic = card_root / f"PIC{number}.BMP"
            if pic.is_file():
                shutil.copyfile(pic, menu_folder / f"PIC{number}.BMP")
            shutil.copyfile(output_dir / f"SONG{number}.LRC",
                            menu_folder / f"SONG{number}.LRC")
        build_menu(menu_folder, output_dir / "MENU.BMP")
    report["menu_sha256"] = hashlib.sha256(
        (output_dir / "MENU.BMP").read_bytes()).hexdigest()
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--card-root", type=Path, default=Path("E:/"),
                        help="read-only FAT32 card root (never written)")
    parser.add_argument("--output-dir", type=Path,
                        default=HERE / "staging_artist_20261025")
    parser.add_argument("--artists", type=Path, default=HERE / "card_artists.json")
    args = parser.parse_args()
    report = build(args.card_root, args.output_dir, args.artists)
    for number, info in report["tracks"].items():
        print(f"SONG{number}: {info['title']!r} ({info['title_chars']} chars), "
              f"{info['lrc_bytes']} LRC bytes, {info['glyphs']}/256 glyphs, "
              f"tail preserved, sha256 {info['sha256'][:16]}")
    print(f"FONT.BIN sha256 {report['font_sha256']}")
    print(f"MENU.BMP sha256 {report['menu_sha256']}")
    print(f"Staged in {Path(args.output_dir).resolve()}")


if __name__ == "__main__":
    main()
