# -*- coding: utf-8 -*-
"""Search, verify and archive Apple Music hi-res covers for the remaining
fourteen PIC slots (PIC2, PIC4..PIC16).

Batch 1 (PIC1/PIC3) used fixed track IDs.  This batch discovers each track
through the iTunes search API, then locks the chosen trackId/collectionId/
artwork URL into cover_sources/manifest_batch2.json.  A track is accepted
only when the normalized title and artist both match the accept lists below;
otherwise the slot is reported NEEDS_REVIEW with the best candidates printed
and nothing is archived for it.  Downloaded artwork must satisfy the FPGA
decoder envelope (640..2048 pixels per axis) and is archived bytes-once:
an existing archive with different content is never overwritten.

--verify works offline: it rechecks manifest, JPEG bytes and dimensions.
"""
import argparse
import hashlib
import io
import json
import tempfile
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
SOURCE_DIR = HERE / "cover_sources"
MANIFEST_NAME = "manifest_batch2.json"
USER_AGENT = {"User-Agent": "Mozilla/5.0"}

# title/artist accept lists cover simplified/traditional and duo spellings.
TRACKS = {
    2:  {"query": "米兰的小铁匠 周杰伦",
         "titles": {"米兰的小铁匠", "米蘭的小鐵匠"},
         "artists": {"周杰伦", "周杰倫"},
         "album_hint": "八度"},
    4:  {"query": "日不落 蔡依林",
         "titles": {"日不落"},
         "artists": {"蔡依林"},
         "album_hint": "特务J"},
    5:  {"query": "小半 陈粒",
         "titles": {"小半"},
         "artists": {"陈粒", "陳粒"},
         "album_hint": "小梦大半"},
    6:  {"query": "九万字 黄诗扶",
         "titles": {"九万字", "九萬字"},
         "artists": {"黄诗扶", "黃詩扶"},
         "album_hint": "九万"},
    7:  {"query": "南山南 马頔",
         "titles": {"南山南"},
         "artists": {"马頔", "馬頔"},
         "album_hint": "孤岛"},
    8:  {"query": "答案 杨坤 郭采洁",
         "titles": {"答案"},
         "artists": {"杨坤", "楊坤"},
         "album_hint": "答案"},
    9:  {"query": "董小姐 宋冬野",
         "titles": {"董小姐"},
         "artists": {"宋冬野"},
         "album_hint": "安和桥"},
    10: {"query": "追光者 岑宁儿",
         "titles": {"追光者", "追光者(電視劇《夏至未至》插曲)",
                    "追光者(电视剧《夏至未至》插曲)"},
         "artists": {"岑宁儿", "岑寧兒"},
         "album_hint": "夏至未至"},
    11: {"query": "虚拟 陈粒",
         "titles": {"虚拟", "虛擬"},
         "artists": {"陈粒", "陳粒"},
         "album_hint": "小梦大半"},
    12: {"query": "素颜 龙千里",
         "titles": {"素颜", "素顏"},
         "artists": {"龙千里", "龍千里"},
         "album_hint": "素颜",
         "fallback_query": "素颜 许嵩 何曼婷",
         "fallback_titles": {"素颜", "素顏", "素顏(with何曼婷)", "素颜(with何曼婷)"},
         "fallback_artists": {"许嵩", "許嵩", "何曼婷"}},
    13: {"query": "Sugar Maroon 5",
         "titles": {"Sugar"},
         "artists": {"Maroon 5", "Maroon5", "魔力红", "魔力紅"},
         "album_hint": "V",
         "country": "us"},
    14: {"query": "心似烟火 陈壹千",
         "titles": {"心似烟火", "心似煙火"},
         "artists": {"陈壹千", "陳壹千"},
         "album_hint": "心似",
         "fallback_query": "心似烟火 王小草",
         "fallback_artists": {"王小草"}},
    15: {"query": "牵丝戏 银临",
         "titles": {"牵丝戏", "牽絲戲"},
         "artists": {"银临", "銀臨", "Aki阿杰"},
         "album_hint": "牵丝"},
    16: {"query": "白羊 曲肖冰",
         "titles": {"白羊"},
         "artists": {"曲肖冰"},
         "album_hint": "白羊",
         "fallback_query": "白羊 徐秉龙",
         "fallback_artists": {"徐秉龙", "徐秉龍"}},
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def norm(text):
    return "".join(str(text or "").split()).casefold()


def get_json(url, timeout=30):
    request = urllib.request.Request(url, headers=USER_AGENT)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def search_tracks(query, country="tw"):
    term = urllib.parse.quote(query)
    url = (f"https://itunes.apple.com/search?term={term}&entity=song"
           f"&country={country}&limit=25")
    return [r for r in get_json(url).get("results", []) if r.get("kind") == "song"]


def pick_candidate(meta, query, artists, titles=None):
    """Return (best, ranked) — best is None when nothing matches exactly."""
    accepted = {norm(t) for t in (titles or meta["titles"])}
    ranked = []
    for result in search_tracks(query, meta.get("country", "tw")):
        title = norm(result.get("trackName"))
        artist = norm(result.get("artistName"))
        album = norm(result.get("collectionName"))
        if title not in accepted:
            continue
        if not any(norm(a) in artist for a in artists):
            continue
        score = 10
        if norm(meta["album_hint"]) and norm(meta["album_hint"]) in album:
            score += 3
        if result.get("trackTimeMillis", 0) > 60_000:
            score += 1
        ranked.append((score, result))
    ranked.sort(key=lambda item: -item[0])
    return (ranked[0][1] if ranked else None), ranked


def hires_url(url100):
    url = url100.replace("100x100bb.jpg", "1200x1200bb.jpg")
    if url == url100:
        raise ValueError("unexpected 100-pixel artwork URL spelling")
    return url


def inspect_jpeg(raw, name):
    try:
        with Image.open(io.BytesIO(raw)) as image:
            if image.format != "JPEG" or image.mode != "RGB":
                raise ValueError(f"{name}: expected an RGB JPEG source")
            image.load()
            width, height = image.size
    except OSError as exc:
        raise ValueError(f"{name}: cannot decode the downloaded JPEG") from exc
    if not (640 <= width <= 2048 and 480 <= height <= 2048):
        raise ValueError(f"{name}: {width}x{height} is outside the FPGA "
                         "decoder envelope 640..2048 x 480..2048")
    return {"jpeg_sha256": digest(raw), "jpeg_bytes": len(raw),
            "width": width, "height": height}


def fetch_one(number, meta, work_dir):
    best, ranked = pick_candidate(meta, meta["query"], meta["artists"])
    used_fallback = False
    if best is None and meta.get("fallback_query"):
        best, ranked = pick_candidate(meta, meta["fallback_query"],
                                      meta["fallback_artists"],
                                      meta.get("fallback_titles"))
        used_fallback = best is not None
    if best is None:
        preview = [(r.get("trackName"), r.get("artistName"),
                    r.get("collectionName"), r.get("trackId"))
                   for _, r in ranked[:5]]
        return {"status": "NEEDS_REVIEW", "candidates": preview}
    url = hires_url(best["artworkUrl100"])
    request = urllib.request.Request(url, headers=USER_AGENT)
    with urllib.request.urlopen(request, timeout=60) as response:
        raw = response.read()
    candidate = Path(work_dir) / f"PIC{number}.jpg"
    candidate.write_bytes(raw)
    info = inspect_jpeg(raw, candidate.name)
    target = SOURCE_DIR / f"PIC{number}.jpg"
    if target.is_file():
        if target.read_bytes() != raw:
            raise ValueError(f"refusing to replace a different archived source: {target}")
    else:
        candidate.replace(target)
    return {"status": "OK", "fallback": used_fallback,
            "track_id": best["trackId"], "collection_id": best["collectionId"],
            "title": best["trackName"], "artist": best["artistName"],
            "album": best["collectionName"],
            "page_url": best.get("trackViewUrl", ""),
            "artwork_url_100": best["artworkUrl100"],
            "download_url": url, **info}


def fetch_all():
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    manifest_path = SOURCE_DIR / MANIFEST_NAME
    previous = {}
    if manifest_path.is_file():
        previous = json.loads(manifest_path.read_text(encoding="utf-8"))
    tracks = dict(previous.get("tracks", {}))
    review = {}
    with tempfile.TemporaryDirectory(dir=SOURCE_DIR) as temporary:
        for number, meta in TRACKS.items():
            key = str(number)
            if key in tracks and tracks[key].get("status") == "OK":
                path = SOURCE_DIR / f"PIC{number}.jpg"
                if path.is_file():
                    info = inspect_jpeg(path.read_bytes(), path.name)
                    if all(tracks[key].get(k) == v for k, v in info.items()):
                        print(f"PIC{number}: archived source already verified, skip")
                        continue
                    raise ValueError(f"PIC{number}: archived bytes differ from manifest")
            result = fetch_one(number, meta, temporary)
            if result["status"] == "OK":
                tracks[key] = result
                print(f"PIC{number}: {result['title']} / {result['artist']} / "
                      f"{result['album']} -> {result['width']}x{result['height']}"
                      + (" (fallback original version)" if result["fallback"] else ""))
            else:
                review[key] = result
                print(f"PIC{number}: NEEDS_REVIEW candidates={result['candidates']}")
            time.sleep(1)  # be polite to the search API
    fetched_at = previous.get("fetched_at") or datetime.now(timezone.utc).isoformat()
    manifest = {"fetched_at": fetched_at, "tracks": tracks}
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2),
                             encoding="utf-8")
    if review:
        raise SystemExit(f"slots needing manual review: {sorted(review)}")
    return manifest


def verify_all():
    manifest = json.loads((SOURCE_DIR / MANIFEST_NAME).read_text(encoding="utf-8"))
    for number in TRACKS:
        entry = manifest["tracks"][str(number)]
        if entry.get("status") != "OK":
            raise ValueError(f"PIC{number}: manifest slot is not verified OK")
        path = SOURCE_DIR / f"PIC{number}.jpg"
        info = inspect_jpeg(path.read_bytes(), path.name)
        for key, value in info.items():
            if entry.get(key) != value:
                raise ValueError(f"PIC{number}: archived JPEG {key} differs from the manifest")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true",
                        help="offline; do not download or rewrite sources")
    args = parser.parse_args()
    manifest = verify_all() if args.verify else fetch_all()
    ok = [int(n) for n, t in manifest["tracks"].items() if t.get("status") == "OK"]
    print(f"verified slots: {sorted(ok)}")


if __name__ == "__main__":
    main()
