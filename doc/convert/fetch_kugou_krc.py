# -*- coding: utf-8 -*-
"""Fetch and verify the two matched Kugou KRC timing sources.

Without --verify, download and archive SONG1/2.krc plus manifest.json.
With --verify, use only the archived files. Card checks compare WAV format and
length, sung-row text and existing line starts; lyric text is never printed.
"""
import argparse
import base64
import difflib
import hashlib
import json
import re
import tempfile
import urllib.request
import wave
from datetime import datetime, timezone
from pathlib import Path

from generate_music_lyrics import read_lrc
from prepare_scrolling_lyrics import decode_krc, krc_rows

HERE = Path(__file__).resolve().parent
SOURCE_DIR = HERE / "krc_sources"
TRACKS = {
    1: {
        "title": "手写的从前",
        "display_title": "手写的从前 - 周杰伦",
        "artist": "周杰伦",
        "album": "哎呦，不错哦",
        "song_page_url": "https://www.kugou.com/song-36/3wrexd8.html",
        "audio_hash": "2920d0149ad73fac588c264539f7927f",
        "krc_id": "313546430",
        "accesskey": "BAB9487478304869D29A09286A74F8ED",
        "source": "酷狗官方推荐歌词",
        "duration_ms": 297000,
        "expected_wav_seconds": 297.564,
        "expected_rows": 65,
        "expected_cues": 690,
        "expected_glyphs": 239,
        "expected_card_matches": 63,
    },
    2: {
        "title": "米兰的小铁匠",
        "display_title": "米兰的小铁匠 - 周杰伦",
        "artist": "周杰伦",
        "album": "八度空间",
        "song_page_url": "https://www.kugou.com/song-36/41mf76.html",
        "audio_hash": "8a6185d930dfb90a62ba4be72aadd61a",
        "krc_id": "136841172",
        "accesskey": "752C805D06632B4AF39BBFE5BDEA1D15",
        "source": "酷狗官方推荐歌词",
        "duration_ms": 240753,
        "expected_wav_seconds": 240.601,
        "expected_rows": 60,
        "expected_cues": 526,
        "expected_glyphs": 149,
        "expected_card_matches": 59,
    },
}


def download_url(meta):
    return ("https://lyrics.kugou.com/download?ver=1&client=pc"
            f"&id={meta['krc_id']}&accesskey={meta['accesskey']}"
            "&fmt=krc&charset=utf-8")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def tag(source, name):
    match = re.search(rf"^\[{re.escape(name)}:([^\r\n]*)\]", source, re.M)
    return match[1] if match else ""


def normalized(text):
    return "".join(text.split())


def compare_card_lrc(path, rows):
    card_rows = read_lrc(Path(path), max_chars=31)
    krc_text = [normalized(text) for _, text, _ in rows]
    card_text = [normalized(text) for _, text in card_rows]
    matcher = difflib.SequenceMatcher(a=krc_text, b=card_text, autojunk=False)
    pairs = []
    for a, b, length in matcher.get_matching_blocks():
        pairs.extend((a + i, b + i) for i in range(length))
    deltas = [rows[a][0] - card_rows[b][0] * 10 for a, b in pairs]
    return len(pairs), deltas


def verify_wav(path, expected_seconds):
    with wave.open(str(path), "rb") as wav:
        if (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) != (2, 2, 48000):
            raise ValueError(f"{path.name}: expected 48-kHz 16-bit stereo WAV")
        seconds = wav.getnframes() / wav.getframerate()
    if abs(seconds - expected_seconds) > 0.001:
        raise ValueError(f"{path.name}: WAV length differs from the verified source")
    return seconds


def inspect_source(number, source_dir=SOURCE_DIR, card_root=None):
    meta = TRACKS[number]
    path = Path(source_dir) / f"SONG{number}.krc"
    raw = path.read_bytes()
    if raw[:4] != b"krc1":
        raise ValueError(f"{path.name}: KRC signature mismatch")
    clear = decode_krc(path)
    for key, tag_name in (("title", "ti"), ("artist", "ar"),
                          ("album", "al"), ("audio_hash", "hash")):
        actual = tag(clear, tag_name)
        if actual.lower() != meta[key].lower():
            raise ValueError(f"{path.name}: unexpected {tag_name} metadata")
    if int(tag(clear, "offset") or 0) != 0:
        raise ValueError(f"{path.name}: nonzero offset requires explicit review")
    if int(tag(clear, "manualoffset") or 0) != 0:
        raise ValueError(f"{path.name}: nonzero manual offset is not supported")

    rows, quality = krc_rows(path)
    rows = sorted(rows, key=lambda row: row[0])
    cues = sum(len(text) for _, text, _ in rows)
    glyphs = len(set(" ?" + meta["display_title"] +
                     "".join(text for _, text, _ in rows)))
    if quality != 1 or len(rows) != meta["expected_rows"] or cues != meta["expected_cues"]:
        raise ValueError(f"{path.name}: unexpected KRC row/cue count")
    if glyphs != meta["expected_glyphs"] or glyphs > 256:
        raise ValueError(f"{path.name}: unexpected glyph count {glyphs}")

    result = {
        "krc_sha256": digest(raw),
        "rows": len(rows),
        "cues": cues,
        "glyphs": glyphs,
    }
    if card_root is not None:
        card_root = Path(card_root)
        result["wav_seconds"] = verify_wav(
            card_root / f"SONG{number}.WAV", meta["expected_wav_seconds"])
        matches, deltas = compare_card_lrc(card_root / f"SONG{number}.LRC", rows)
        if matches not in (meta["expected_card_matches"], meta["expected_rows"]) or not deltas:
            raise ValueError(f"{path.name}: card lyric alignment changed")
        if min(deltas) < 0 or max(deltas) > 9:
            raise ValueError(f"{path.name}: line timing is not the verified zero-offset version")
        result["matched_card_rows"] = matches
        result["max_line_delta_ms"] = max(deltas)
    return result


def fetch_all(card_root, source_dir=SOURCE_DIR):
    source_dir = Path(source_dir)
    source_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = source_dir / "manifest.json"
    previous = {}
    if manifest_path.is_file():
        previous = json.loads(manifest_path.read_text(encoding="utf-8"))
    report = {}
    with tempfile.TemporaryDirectory(dir=source_dir) as temporary:
        for number, meta in TRACKS.items():
            request = urllib.request.Request(
                download_url(meta), headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = json.load(response)
            if payload.get("status") != 200 or payload.get("error_code") != 0:
                raise RuntimeError(f"SONG{number}: KRC download failed")
            if str(payload.get("id")) != meta["krc_id"] or payload.get("fmt") != "krc":
                raise ValueError(f"SONG{number}: KRC response identity mismatch")
            raw = base64.b64decode(payload["content"], validate=True)
            candidate = Path(temporary) / f"SONG{number}.krc"
            candidate.write_bytes(raw)
            result = inspect_source(number, candidate.parent, card_root)
            target = source_dir / f"SONG{number}.krc"
            if target.is_file():
                if target.read_bytes() != raw:
                    raise ValueError(f"refusing to replace a different archived source: {target}")
            else:
                candidate.replace(target)
            report[str(number)] = {**meta, **result, "download_url": download_url(meta)}
    fetched_at = previous.get("fetched_at")
    if not fetched_at:
        fetched_at = datetime.now(timezone.utc).isoformat()
    manifest = {"fetched_at": fetched_at, "tracks": report}
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2),
                             encoding="utf-8")
    return manifest


def verify_all(card_root, source_dir=SOURCE_DIR):
    source_dir = Path(source_dir)
    manifest = json.loads((source_dir / "manifest.json").read_text(encoding="utf-8"))
    for number in TRACKS:
        result = inspect_source(number, source_dir, card_root)
        saved = manifest["tracks"][str(number)]
        for key, value in result.items():
            # The card may legitimately be the old LRC or the new full-KRC LRC.
            if key != "matched_card_rows" and saved.get(key) != value:
                raise ValueError(f"SONG{number}: archived manifest mismatch for {key}")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--card-root", type=Path, default=Path("E:/"))
    parser.add_argument("--sources", type=Path, default=SOURCE_DIR)
    parser.add_argument("--verify", action="store_true", help="offline; do not download or rewrite sources")
    args = parser.parse_args()
    manifest = verify_all(args.card_root, args.sources) if args.verify else fetch_all(
        args.card_root, args.sources)
    for number in TRACKS:
        track = manifest["tracks"][str(number)]
        print(f"SONG{number} KRC OK: {track['rows']} rows, {track['cues']} cues, "
              f"{track['glyphs']} glyphs, line delta <= {track['max_line_delta_ms']} ms")


if __name__ == "__main__":
    main()
