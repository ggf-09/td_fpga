# -*- coding: utf-8 -*-
"""Fetch and verify the two Apple Music hi-res cover sources.

Without --verify, cross-check each track through the iTunes lookup API
(trackName/artistName/collectionName/artwork URL), download the 1200-pixel
artwork and archive PIC1/3.jpg plus manifest.json under cover_sources/.
Apple may serve different bytes on repeat downloads, so the first archived
SHA-256 is authoritative: an existing archive is never overwritten. With
--verify, work offline and check the manifest, dimensions, track metadata
and hashes against the archived JPEGs. The archived JPEG is the only
conversion source for the card tooling.
"""
import argparse
import hashlib
import io
import json
import tempfile
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
SOURCE_DIR = HERE / "cover_sources"
META_FIELDS = ("track_id", "collection_id", "title", "artist", "album",
               "page_url", "artwork_url_100")
TRACKS = {
    1: {
        "track_id": 944321446,
        "collection_id": 944321428,
        "title": "手寫的從前",
        "artist": "周杰倫",
        "album": "哎呦, 不錯哦",
        "page_url": "https://music.apple.com/tw/album/%E6%89%8B%E5%AF%AB%E7%9A%84%E5%BE%9E%E5%89%8D/944321428?i=944321446",
        "artwork_url_100": "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/16/db/ff/16dbff09-0750-29b0-07b7-3fa44f8a556e/dj.nzqvfsza.jpg/100x100bb.jpg",
        "expected_width": 1200,
        "expected_height": 1200,
    },
    3: {
        "track_id": 536009647,
        "collection_id": 536009641,
        "title": "楓",
        "artist": "周杰倫",
        "album": "11月的蕭邦",
        "page_url": "https://music.apple.com/tw/album/%E6%A5%93/536009641?i=536009647",
        "artwork_url_100": "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/9e/35/ad/9e35ad1e-749e-75b6-0539-1e80cea1817b/JAY11.jpg/100x100bb.jpg",
        "expected_width": 1100,
        "expected_height": 1200,
    },
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def hires_url(meta):
    url = meta["artwork_url_100"].replace("100x100bb.jpg", "1200x1200bb.jpg")
    if url == meta["artwork_url_100"]:
        raise ValueError("unexpected 100-pixel artwork URL spelling")
    return url


def lookup_track(meta):
    url = (f"https://itunes.apple.com/lookup?id={meta['track_id']}"
           "&country=tw&entity=song")
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.load(response)
    matches = [r for r in payload.get("results", [])
               if r.get("trackId") == meta["track_id"] and r.get("kind") == "song"]
    if len(matches) != 1:
        raise RuntimeError(f"track {meta['track_id']}: iTunes lookup failed")
    result = matches[0]
    for api_field, key in (("trackName", "title"), ("artistName", "artist"),
                           ("collectionName", "album")):
        if result.get(api_field) != meta[key]:
            raise ValueError(f"track {meta['track_id']}: unexpected {api_field}")
    if result.get("collectionId") != meta["collection_id"]:
        raise ValueError(f"track {meta['track_id']}: unexpected collectionId")
    if result.get("artworkUrl100") != meta["artwork_url_100"]:
        raise ValueError(f"track {meta['track_id']}: artwork URL changed; "
                         "review the new source explicitly")
    return result


def inspect_source(number, source_dir=SOURCE_DIR):
    """Offline check of the archived JPEG; return its actual properties."""
    path = Path(source_dir) / f"PIC{number}.jpg"
    raw = path.read_bytes()
    try:
        with Image.open(io.BytesIO(raw)) as image:
            if image.format != "JPEG" or image.mode != "RGB":
                raise ValueError(f"{path.name}: expected an RGB JPEG source")
            image.load()
            width, height = image.size
    except OSError as exc:
        raise ValueError(f"{path.name}: cannot decode the archived JPEG") from exc
    return {"jpeg_sha256": digest(raw), "jpeg_bytes": len(raw),
            "width": width, "height": height}


def fetch_all(source_dir=SOURCE_DIR):
    source_dir = Path(source_dir)
    source_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = source_dir / "manifest.json"
    previous = {}
    if manifest_path.is_file():
        previous = json.loads(manifest_path.read_text(encoding="utf-8"))
    report = {}
    with tempfile.TemporaryDirectory(dir=source_dir) as temporary:
        for number, meta in TRACKS.items():
            lookup_track(meta)
            url = hires_url(meta)
            request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
            candidate = Path(temporary) / f"PIC{number}.jpg"
            candidate.write_bytes(raw)
            info = inspect_source(number, candidate.parent)
            if (info["width"], info["height"]) != (meta["expected_width"],
                                                   meta["expected_height"]):
                raise ValueError(f"PIC{number}: downloaded artwork is not "
                                 f"{meta['expected_width']}x{meta['expected_height']}")
            target = source_dir / f"PIC{number}.jpg"
            if target.is_file():
                if target.read_bytes() != raw:
                    raise ValueError(f"refusing to replace a different archived source: {target}")
                info = inspect_source(number, source_dir)
            else:
                candidate.replace(target)
            entry = {field: meta[field] for field in META_FIELDS}
            entry.update({"expected_width": meta["expected_width"],
                          "expected_height": meta["expected_height"],
                          **info, "download_url": url})
            report[str(number)] = entry
    fetched_at = previous.get("fetched_at")
    if not fetched_at:
        fetched_at = datetime.now(timezone.utc).isoformat()
    manifest = {"fetched_at": fetched_at, "tracks": report}
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2),
                             encoding="utf-8")
    return manifest


def verify_all(source_dir=SOURCE_DIR, expected_dims=None):
    source_dir = Path(source_dir)
    if expected_dims is None:
        expected_dims = {n: (m["expected_width"], m["expected_height"])
                         for n, m in TRACKS.items()}
    manifest = json.loads((source_dir / "manifest.json").read_text(encoding="utf-8"))
    for number, meta in TRACKS.items():
        entry = manifest["tracks"][str(number)]
        for field in META_FIELDS:
            if entry.get(field) != meta[field]:
                raise ValueError(f"PIC{number}: manifest {field} differs from "
                                 "the verified track metadata")
        info = inspect_source(number, source_dir)
        for key, value in info.items():
            if entry.get(key) != value:
                raise ValueError(f"PIC{number}: archived JPEG {key} differs from the manifest")
        if (info["width"], info["height"]) != tuple(expected_dims[number]):
            raise ValueError(f"PIC{number}: unexpected archived dimensions")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, default=SOURCE_DIR)
    parser.add_argument("--verify", action="store_true",
                        help="offline; do not download or rewrite sources")
    args = parser.parse_args()
    manifest = verify_all(args.sources) if args.verify else fetch_all(args.sources)
    for number in TRACKS:
        track = manifest["tracks"][str(number)]
        print(f"PIC{number} JPEG OK: {track['width']}x{track['height']}, "
              f"{track['jpeg_bytes']} bytes, sha256 {track['jpeg_sha256']}")


if __name__ == "__main__":
    main()
