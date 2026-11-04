# -*- coding: utf-8 -*-
"""Prepare PIC1..16.BMP, SONG1..16.WAV and SONG1..16.LRC for a FAT32 card.

Put source files in a directory with these stems. WAV sources may have any
sample format that Python's wave module can read; ffmpeg is used for other
formats and for sample-rate/channel conversion when available.

Usage: python prepare_music_card.py INPUT_DIRECTORY OUTPUT_DIRECTORY
"""

import argparse
import re
import shutil
import subprocess
import tempfile
import wave
from pathlib import Path

from PIL import Image, ImageOps, ImageFont
from generate_music_lyrics import read_lrc, glyph_rows


def _read_card_lrc_text(path):
    path = Path(path)
    raw = path.read_bytes()
    try:
        return raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        try:
            return raw.decode("gb18030")
        except UnicodeDecodeError as exc:
            raise ValueError(f"{path.name}: LRC must be UTF-8 or GB18030 text") from exc


def _validate_card_characters(path, text, field):
    for char in text:
        code = ord(char)
        if (code > 0xffff or 0xd800 <= code <= 0xdfff or code < 32 or
                0x7f <= code <= 0x9f or code in (0xfffe, 0xffff)):
            raise ValueError(
                f"{Path(path).name}: {field} contains unsupported character U+{code:04X}; "
                "only printable Unicode BMP characters are supported")


def _read_card_title_tag(path):
    """Read an optional [ti:] tag; return at most 31 printable BMP characters.

    Standard LRC tags occupy one line. A malformed closing bracket or newline
    cannot inject another tag into the normalized output. The first title tag
    wins, including an explicitly empty title. Artist metadata is not appended.
    """
    for line in _read_card_lrc_text(path).splitlines():
        match = re.match(r"^[ \t]*\[ti:([^\r\n]*)", line, re.IGNORECASE)
        if match:
            title = match.group(1).split("]", 1)[0]
            title = " ".join(title.replace("]", " ").split())
            _validate_card_characters(path, title, "title")
            return title[:31]
    return None


def read_card_title(path):
    """Return the optional cleaned title, or an empty string when absent."""
    return _read_card_title_tag(path) or ""


def _card_lyric_entries(path):
    path = Path(path)
    entries = read_lrc(path, max_chars=31)
    if len(entries) > 158:
        raise ValueError(f"{path.name}: at most 158 timed lines per song")
    if sum(len(line) for _, line in entries) > 3072:
        raise ValueError(f"{path.name}: at most 3072 displayed characters per song")
    for _, line in entries:
        _validate_card_characters(path, line, "lyric")
    return entries


def normalize_card_lrc(path):
    """Return card-ready UTF-8 LRC bytes, preserving optional title metadata.

    Titles use their own 31-character storage and do not consume lyric cue or
    text limits. The complete card file, including its title, must fit 4 KiB.
    """
    path = Path(path)
    title = _read_card_title_tag(path)
    entries = _card_lyric_entries(path)
    normalized = ((f"[ti:{title}]\n" if title is not None else "") + "".join(
        f"[{cs // 6000:02d}:{(cs // 100) % 60:02d}.{cs % 100:02d}]{line}\n"
        for cs, line in entries
    )).encode("utf-8")
    if len(normalized) > 4096:
        raise ValueError(f"{path.name}: UTF-8 LRC must be at most 4096 bytes")
    return normalized


def _card_font_characters(path):
    # Validate the complete normalized file even when called independently of
    # main(), so invalid card files cannot receive an apparently usable font.
    normalize_card_lrc(path)
    return read_card_title(path) + "".join(line for _, line in _card_lyric_entries(path))


def find_stem(folder, stem, suffixes):
    found = [p for p in folder.iterdir() if p.is_file() and
             p.stem.upper() == stem and p.suffix.lower() in suffixes]
    if len(found) > 1:
        raise ValueError(f"more than one source for {stem}: {found}")
    return found[0] if found else None


def write_canonical_wav(source, destination):
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        bundled = Path("D:/app/18_Proteus/Tools/Python/ffmpeg.exe")
        if bundled.is_file():
            ffmpeg = str(bundled)
    with tempfile.TemporaryDirectory() as tmp:
        candidate = source
        if ffmpeg:
            # Some bundled Windows ffmpeg builds cannot open Unicode paths.
            local_source = Path(tmp) / ("source" + source.suffix.lower())
            shutil.copyfile(source, local_source)
            candidate = Path(tmp) / "converted.wav"
            subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                            "-i", str(local_source), "-vn", "-ac", "2", "-ar", "48000",
                            "-c:a", "pcm_s16le", str(candidate)], check=True)
        try:
            with wave.open(str(candidate), "rb") as reader:
                channels = reader.getnchannels()
                rate = reader.getframerate()
                width = reader.getsampwidth()
                compression = reader.getcomptype()
                if (channels, rate, width, compression) != (2, 48000, 2, "NONE"):
                    raise ValueError(f"{source.name}: requires 48 kHz, 16-bit stereo PCM; install ffmpeg to convert")
                frames = reader.readframes(reader.getnframes())
        except (wave.Error, EOFError) as exc:
            raise ValueError(f"{source.name}: cannot read audio; install ffmpeg for this format") from exc
    if not frames or len(frames) % 4:
        raise ValueError(f"{source.name}: empty or incomplete stereo frame")
    with wave.open(str(destination), "wb") as out:
        out.setnchannels(2)
        out.setsampwidth(2)
        out.setframerate(48000)
        out.writeframes(frames)
    with destination.open("rb") as check:
        if check.read(4) != b"RIFF" or check.seek(8) != 8 or check.read(4) != b"WAVE":
            raise RuntimeError("unexpected WAV header")
    return len(frames) // 192000


def write_bmp(source, destination):
    with Image.open(source) as image:
        rgb = ImageOps.fit(image.convert("RGB"), (640, 480), method=Image.Resampling.LANCZOS)
        rgb.save(destination, format="BMP")
    if destination.stat().st_size != 54 + 640 * 480 * 3:
        raise RuntimeError(f"unexpected BMP size: {destination}")


def write_card_font(lyric_paths, destination):
    charset = [" ", "?"]
    for path in lyric_paths:
        for char in _card_font_characters(path):
            if char not in charset:
                charset.append(char)
    if len(charset) > 256:
        raise ValueError(f"FONT.BIN supports 256 unique characters; got {len(charset)}")
    font = ImageFont.truetype("C:/Windows/Fonts/simsun.ttc", 16)
    data = bytearray(b"LFNT" + bytes((2,)) + len(charset).to_bytes(2, "little") + b"\x00")
    for idx in range(256):
        data.extend(ord(charset[idx]).to_bytes(2, "little") if idx < len(charset)
                    else b"\x00\x00")
    for idx in range(256):
        rows = glyph_rows(font, charset[idx]) if idx < len(charset) else [0] * 16
        for row in rows:
            data.extend(row.to_bytes(2, "little"))
    if len(data) != 8712:
        raise RuntimeError("unexpected font file length")
    destination.write_bytes(data)
    return len(charset)


def write_music_fonts(track_lyrics, destination):
    """Use a shared font if it fits; otherwise use four per-track slots."""
    if any(not isinstance(number,int) or not 1<=number<=16 for number in track_lyrics):
        raise ValueError("song numbers must be between 1 and 16")
    charset = set(" ?")
    for path in track_lyrics.values():
        charset.update(_card_font_characters(path))
    if len(charset) <= 256:
        count = write_card_font(list(track_lyrics.values()), destination)
        return f"shared font, {count}/256 glyphs, 8712 bytes"
    counts = []
    data = bytearray()
    with tempfile.TemporaryDirectory() as tmp:
        slots=16 if any(number>4 for number in track_lyrics) else 4
        for number in range(1, slots+1):
            slot = Path(tmp) / f"font{number}.bin"
            paths = [track_lyrics[number]] if number in track_lyrics else []
            counts.append(write_card_font(paths, slot))
            data.extend(slot.read_bytes())
            data.extend(bytes(16384 - 8712))
    destination.write_bytes(data)
    return f"per-track fonts, glyph counts {counts}, {len(data)} bytes; requires matching banked-font bitstream"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    source = args.input.resolve()
    target = args.output.resolve()
    if source == target or source in target.parents:
        raise ValueError("output must be a separate directory outside input")
    if not source.is_dir():
        raise ValueError("input directory does not exist")
    target.mkdir(parents=True, exist_ok=True)

    track_lyrics = {}
    for number in range(1, 17):
        song = find_stem(source, f"SONG{number}",
                         {".wav", ".flac", ".mp3", ".ogg", ".m4a"})
        cover = find_stem(source, f"PIC{number}",
                          {".bmp", ".png", ".jpg", ".jpeg", ".webp"})
        lyric = find_stem(source, f"SONG{number}", {".lrc"})
        if song and not cover:
            raise ValueError(f"SONG{number} has no matching PIC{number} image")
        if cover:
            write_bmp(cover, target / f"PIC{number}.BMP")
            print(f"PIC{number}.BMP ready")
        if song:
            seconds = write_canonical_wav(song, target / f"SONG{number}.WAV")
            print(f"SONG{number}.WAV ready ({seconds} s)")
        if lyric:
            # Keep a normal text LRC on the card. Normalize the timestamp
            # spelling and expand multiple tags so the small hardware parser
            # receives one sorted [mm:ss.xx] timestamp per line.
            normalized = normalize_card_lrc(lyric)
            (target / f"SONG{number}.LRC").write_bytes(normalized)
            track_lyrics[number] = lyric
            print(f"SONG{number}.LRC copied")
    if track_lyrics:
        details = write_music_fonts(track_lyrics, target / "FONT.BIN")
        print(f"FONT.BIN ready ({details}); copy it with the LRC files")
    print("Copy only the generated 8.3-name files to the root of a FAT32 card.")


if __name__ == "__main__":
    main()
