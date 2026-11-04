# -*- coding: utf-8 -*-
"""Validate, back up and apply the staged artist-title card update.

Dry-run by default. Use --apply to update exactly SONG1..16.LRC, FONT.BIN
and MENU.BMP. Any post-write mismatch restores all eighteen originals.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image
from prepare_music_card import read_card_title

HERE = Path(__file__).resolve().parent
BANK_SIZE = 16384
LFNT_SIZE = 8712
TARGETS = [f"SONG{n}.LRC" for n in range(1, 17)] + ["FONT.BIN", "MENU.BMP"]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def validate(card, staged, artists_path):
    card, staged = Path(card), Path(staged)
    artists = json.loads(Path(artists_path).read_text(encoding="utf-8"))
    old_font = (card / "FONT.BIN").read_bytes()
    new_font = (staged / "FONT.BIN").read_bytes()
    if len(old_font) != 16 * BANK_SIZE or len(new_font) != len(old_font):
        raise ValueError("FONT.BIN must contain sixteen 16-KiB banks")
    for number in range(1, 17):
        name = f"SONG{number}.LRC"
        old = (card / name).read_bytes()
        new = (staged / name).read_bytes()
        if old.split(b"\n", 1)[1] != new.split(b"\n", 1)[1]:
            raise ValueError(f"{name}: lyric body differs from the card")
        old_title = read_card_title(card / name)
        new_title = read_card_title(staged / name)
        suffix = " - " + artists[str(number)]
        expected = old_title if old_title.endswith(suffix) else old_title + suffix
        if new_title != expected or len(new_title) > 31 or len(new) > 4096:
            raise ValueError(f"{name}: invalid staged title or size")
        start = (number - 1) * BANK_SIZE
        bank = new_font[start:start + BANK_SIZE]
        if bank[:4] != b"LFNT" or int.from_bytes(bank[5:7], "little") > 256:
            raise ValueError(f"{name}: invalid LFNT bank or too many glyphs")
        if bank[LFNT_SIZE:] != old_font[start + LFNT_SIZE:start + BANK_SIZE]:
            raise ValueError(f"{name}: LKT1/timing tail differs from the card")
    with Image.open(staged / "MENU.BMP") as menu:
        if menu.format != "BMP" or menu.size != (640, 480):
            raise ValueError("MENU.BMP must be a 640x480 BMP")
        menu.verify()
    if (staged / "MENU.BMP").stat().st_size != 921654:
        raise ValueError("MENU.BMP has an unexpected size")
    for name in TARGETS:
        if not (card / name).is_file() or not (staged / name).is_file():
            raise ValueError(f"missing source or staged file: {name}")
    return {name: digest(staged / name) for name in TARGETS}


def apply(card, staged, backup, artists_path):
    card, staged, backup = Path(card), Path(staged), Path(backup)
    if backup.exists():
        raise ValueError(f"backup directory already exists: {backup}")
    staged_hashes = validate(card, staged, artists_path)
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
    validate(card, staged, artists_path)
    return backup


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--card-root", type=Path, default=Path("E:/"))
    parser.add_argument("--staging", type=Path,
                        default=HERE / "staging_artist_20261025")
    parser.add_argument("--artists", type=Path, default=HERE / "card_artists.json")
    parser.add_argument("--backup", type=Path,
                        default=HERE.parent.parent / "backups" / "card_before_artist_20261025")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if not args.apply:
        hashes = validate(args.card_root, args.staging, args.artists)
        print(f"DRY-RUN OK: {len(hashes)} files validated; card not changed")
        return
    backup = apply(args.card_root, args.staging, args.backup, args.artists)
    print(f"UPDATED AND READ BACK: {len(TARGETS)} files; backup: {backup}")


if __name__ == "__main__":
    main()
