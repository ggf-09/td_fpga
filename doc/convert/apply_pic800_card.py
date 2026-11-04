# -*- coding: utf-8 -*-
"""Validate, back up and apply the 800x600 cover re-encode (all 16 PICs).

Dry-run by default.  Only PIC1.BMP..PIC16.BMP are written; WAV, FLAC, LRC,
FONT.BIN and MENU.BMP are never touched.  Staged bytes must equal a fresh
800x600 re-encode of the manifest-verified archived JPEG.  All 16 current
card files are backed up and hash-checked first; any post-write mismatch
restores every target from the backup.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

from prepare_hires_pic_card import check_bmp
from prepare_pic800_card import (NUMBERS, OUT_H, OUT_W, pic800_bmp_bytes,
                                 verified_archive)

HERE = Path(__file__).resolve().parent
TARGETS = [f"PIC{n}.BMP" for n in NUMBERS]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def validate(card, staged, sources=HERE / "cover_sources"):
    card, staged, sources = Path(card), Path(staged), Path(sources)
    card_resolved, staged_resolved = card.resolve(), staged.resolve()
    if card_resolved == staged_resolved or card_resolved in staged_resolved.parents:
        raise ValueError("staging must be separate from the card")
    if len(TARGETS) != 16:
        raise ValueError("specs must cover exactly the 16 PIC files")
    for name in TARGETS:
        if not (card / name).is_file() or not (staged / name).is_file():
            raise ValueError(f"missing card or staged file: {name}")
    hashes = {}
    for name, number in zip(TARGETS, NUMBERS):
        archive = verified_archive(sources, number)
        staged_path = staged / name
        check_bmp(staged_path, OUT_W, OUT_H)
        if staged_path.read_bytes() != pic800_bmp_bytes(archive):
            raise ValueError(f"{name}: staged BMP does not match the archived "
                             "JPEG 800x600 re-encode")
        hashes[name] = digest(staged_path)
    return hashes


def apply(card, staged, backup, sources=HERE / "cover_sources"):
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
    parser.add_argument("--staging", type=Path,
                        default=HERE / "staging_pic800_20261026")
    parser.add_argument("--sources", type=Path, default=HERE / "cover_sources")
    parser.add_argument("--backup", type=Path,
                        default=HERE.parent.parent / "backups" / "card_before_pic800_20261026")
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
