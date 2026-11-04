# -*- coding: utf-8 -*-
"""Validate, back up and apply the SONG1/2 KRC timing update.

Dry-run by default. Only SONG1.LRC, SONG2.LRC and FONT.BIN are written.
The staged timing payload is independently recomputed from the archived KRC.
Any post-write mismatch restores all three originals.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

from fetch_kugou_krc import TRACKS, verify_wav
from generate_music_lyrics import read_lrc
from prepare_music_card import normalize_card_lrc, read_card_title
from prepare_scrolling_lyrics import krc_rows

HERE = Path(__file__).resolve().parent
BANK_SIZE = 16384
LKT1_OFFSET = 8712
TIMING_OFFSET = 9216
TARGETS = ["SONG1.LRC", "SONG2.LRC", "FONT.BIN"]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def expected_payload(source, lrc):
    rows, quality = krc_rows(source)
    rows = sorted(rows, key=lambda row: row[0])
    entries = read_lrc(lrc, max_chars=31)
    if quality != 1 or len(entries) != len(rows):
        raise ValueError(f"{lrc.name}: KRC row count mismatch")
    payload = bytearray()
    for (cs, text), (_, source_text, times) in zip(entries, rows):
        if text != source_text or len(times) != len(text):
            raise ValueError(f"{lrc.name}: KRC text differs from the staged LRC")
        for ms in times:
            tick = (max(0, ms - cs * 10) + 39) // 40
            if tick > 255:
                raise ValueError(f"{lrc.name}: row timing exceeds 10.2 seconds")
            payload.append(tick)
    return entries, bytes(payload)


def validate(card, staged, sources=HERE / "krc_sources"):
    card, staged, sources = Path(card), Path(staged), Path(sources)
    card_resolved, staged_resolved = card.resolve(), staged.resolve()
    if card_resolved == staged_resolved or card_resolved in staged_resolved.parents:
        raise ValueError("staging must be separate from the card")
    for name in TARGETS:
        if not (card / name).is_file() or not (staged / name).is_file():
            raise ValueError(f"missing card or staged file: {name}")
    manifest = json.loads((sources / "manifest.json").read_text(encoding="utf-8"))
    old_font = (card / "FONT.BIN").read_bytes()
    new_font = (staged / "FONT.BIN").read_bytes()
    if len(old_font) != 16 * BANK_SIZE or len(new_font) != len(old_font):
        raise ValueError("FONT.BIN must contain sixteen 16-KiB banks")

    for number in range(3, 17):
        start = (number - 1) * BANK_SIZE
        if new_font[start:start + BANK_SIZE] != old_font[start:start + BANK_SIZE]:
            raise ValueError(f"SONG{number}: other FONT banks must remain unchanged")

    for number in (1, 2):
        meta = TRACKS[number]
        name = f"SONG{number}.LRC"
        source = sources / f"SONG{number}.krc"
        if digest(source) != manifest["tracks"][str(number)]["krc_sha256"]:
            raise ValueError(f"SONG{number}: archived KRC hash differs from the manifest")
        verify_wav(card / f"SONG{number}.WAV", meta["expected_wav_seconds"])
        if (read_card_title(card / name) != meta["display_title"] or
                read_card_title(staged / name) != meta["display_title"]):
            raise ValueError(f"{name}: unexpected card or staged title")
        raw = (staged / name).read_bytes()
        if len(raw) > 4096 or normalize_card_lrc(staged / name) != raw:
            raise ValueError(f"{name}: invalid size or non-canonical LRC")
        entries, payload = expected_payload(source, staged / name)
        if (len(entries) != meta["expected_rows"] or
                len(payload) != meta["expected_cues"] or len(entries) > 158 or
                len(payload) > 3072):
            raise ValueError(f"{name}: unexpected row or character count")

        bank = new_font[(number - 1) * BANK_SIZE:number * BANK_SIZE]
        if bank[:4] != b"LFNT":
            raise ValueError(f"{name}: invalid LFNT bank")
        glyph_count = int.from_bytes(bank[5:7], "little")
        if glyph_count != meta["expected_glyphs"] or glyph_count > 256:
            raise ValueError(f"{name}: unexpected glyph count {glyph_count}")
        glyphs = {int.from_bytes(bank[8 + i * 2:10 + i * 2], "little")
                  for i in range(glyph_count)}
        required = {ord(char) for char in meta["display_title"] +
                    "".join(text for _, text in entries)}
        if not required.issubset(glyphs):
            raise ValueError(f"{name}: title or lyric glyph is missing")
        if (bank[LKT1_OFFSET:LKT1_OFFSET + 4] != b"LKT1" or
                int.from_bytes(bank[LKT1_OFFSET + 4:LKT1_OFFSET + 6], "little") != len(payload) or
                bank[LKT1_OFFSET + 6] != 4 or bank[LKT1_OFFSET + 7] != 1):
            raise ValueError(f"{name}: invalid LKT1 count, quantum or KRC quality")
        if TIMING_OFFSET + len(payload) > BANK_SIZE:
            raise ValueError(f"{name}: timing payload exceeds the bank")
        if bank[TIMING_OFFSET:TIMING_OFFSET + len(payload)] != payload:
            raise ValueError(f"{name}: timing payload differs from the archived KRC")
    return {name: digest(staged / name) for name in TARGETS}


def apply(card, staged, backup, sources=HERE / "krc_sources"):
    card, staged, backup = Path(card), Path(staged), Path(backup)
    if backup.exists():
        raise ValueError(f"backup directory already exists: {backup}")
    staged_hashes = validate(card, staged, sources)
    original_hashes = {name: digest(card / name) for name in TARGETS}
    backup.mkdir(parents=True, exist_ok=False)
    for name in TARGETS:
        shutil.copyfile(card / name, backup / name)
        if digest(backup / name) != original_hashes[name]:
            raise RuntimeError(f"backup verification failed: {name}; card not changed")
    (backup / "manifest.json").write_text(json.dumps({
        "card_root": str(card), "staged_root": str(staged),
        "original_sha256": original_hashes, "staged_sha256": staged_hashes,
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    try:
        for name in TARGETS:
            shutil.copyfile(staged / name, card / name)
        for name in TARGETS:
            if digest(card / name) != staged_hashes[name]:
                raise RuntimeError(f"card readback mismatch: {name}")
    except Exception:
        for name in TARGETS:
            shutil.copyfile(backup / name, card / name)
        for name in TARGETS:
            if digest(card / name) != original_hashes[name]:
                raise RuntimeError(f"rollback verification failed: {name}")
        raise
    validate(card, staged, sources)
    return backup


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--card-root", type=Path, default=Path("E:/"))
    parser.add_argument("--staging", type=Path, default=HERE / "staging_krc12_20261025")
    parser.add_argument("--sources", type=Path, default=HERE / "krc_sources")
    parser.add_argument("--backup", type=Path,
                        default=HERE.parent.parent / "backups" / "card_before_krc12_timing_20261025")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if not args.apply:
        hashes = validate(args.card_root, args.staging, args.sources)
        print(f"DRY-RUN OK: {len(hashes)} files validated; card not changed")
        return
    backup = apply(args.card_root, args.staging, args.backup, args.sources)
    print(f"UPDATED AND READ BACK: {len(TARGETS)} files; backup: {backup}")


if __name__ == "__main__":
    main()
