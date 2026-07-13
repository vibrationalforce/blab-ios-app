#!/usr/bin/env python3
"""
watch-video.py — give Claude eyes on any video.

Turns a LOCAL video file or a VIDEO URL (YouTube / Instagram / TikTok / Vimeo —
anything yt-dlp supports) into a set of evenly-spaced JPEG frames + metadata +
(where available) a transcript, so the agent can Read the frames as images and
actually SEE the content.

PIPELINE ONLY — output lands in a temp/scratch dir, never in Sources/, and the
binary frames are never committed to the repo.

Usage:
  python3 watch-video.py <path-or-url> [--frames N] [--out DIR] [--max-height 720]
  python3 watch-video.py --self-test

Output: a manifest on stdout — metadata, then one "FRAME <path>" line per frame
(the agent Reads those paths as images), plus "SUBS <path>" when subtitles exist.

Deps: ffmpeg/ffprobe (apt-get update && apt-get install -y ffmpeg),
      yt-dlp for URLs (pip3 install yt-dlp).
Network: URL downloads need the proxy to allow the video host. If blocked you get
a clean error — fall back to asking the founder to upload the video file directly
(the local path always works).
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

URL_RE = re.compile(r"^https?://", re.IGNORECASE)


def die(msg: str, code: int = 1):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def need(tool: str, hint: str):
    if shutil.which(tool) is None:
        die(f"{tool} not found. Install: {hint}")


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kw)


def probe(path: str) -> dict:
    out = run(["ffprobe", "-v", "error", "-print_format", "json",
               "-show_format", "-show_streams", path]).stdout
    info = json.loads(out)
    fmt = info.get("format", {})
    v = next((s for s in info.get("streams", []) if s.get("codec_type") == "video"), {})
    a = next((s for s in info.get("streams", []) if s.get("codec_type") == "audio"), None)
    return {
        "duration": float(fmt.get("duration", 0) or 0),
        "width": v.get("width"),
        "height": v.get("height"),
        "vcodec": v.get("codec_name"),
        "has_audio": a is not None,
    }


def download(url: str, out_dir: str, max_height: int) -> tuple[str, dict, str | None]:
    """yt-dlp: video (capped height, mp4 preferred) + auto-subs + metadata."""
    need("yt-dlp", "pip3 install yt-dlp")
    tmpl = os.path.join(out_dir, "video.%(ext)s")
    cmd = ["yt-dlp", "--no-playlist", "--restrict-filenames",
           "-f", f"bv*[height<={max_height}]+ba/b[height<={max_height}]/b",
           "--merge-output-format", "mp4",
           "--write-auto-subs", "--write-subs", "--sub-langs", "de,en,en-orig",
           "--convert-subs", "srt",
           "--print-to-file", "%(title)s\n%(uploader)s\n%(duration)s\n%(webpage_url)s",
           os.path.join(out_dir, "meta.txt"),
           "-o", tmpl, url]
    try:
        run(cmd)
    except subprocess.CalledProcessError as e:
        tail = (e.stderr or "")[-500:]
        die("yt-dlp download failed — likely the network proxy blocks this host, "
            "or the URL needs a login. Fall back: ask for a direct video-file "
            f"upload (local path always works).\n--- yt-dlp said ---\n{tail}")
    video = next((os.path.join(out_dir, f) for f in sorted(os.listdir(out_dir))
                  if f.startswith("video.") and f.split(".")[-1] in
                  ("mp4", "mkv", "webm", "mov")), None)
    if not video:
        die("yt-dlp reported success but no video file landed.")
    meta = {}
    mp = os.path.join(out_dir, "meta.txt")
    if os.path.exists(mp):
        lines = open(mp, encoding="utf-8").read().splitlines()
        keys = ["title", "uploader", "duration", "url"]
        meta = dict(zip(keys, lines))
    subs = next((os.path.join(out_dir, f) for f in sorted(os.listdir(out_dir))
                 if f.endswith(".srt")), None)
    return video, meta, subs


def extract_frames(video: str, out_dir: str, n: int, duration: float) -> list[str]:
    frames = []
    n = max(1, n)
    for i in range(n):
        t = duration * (i + 0.5) / n if duration > 0 else i
        dest = os.path.join(out_dir, f"frame{i:02d}_{t:07.1f}s.jpg")
        run(["ffmpeg", "-loglevel", "error", "-ss", f"{t:.2f}", "-i", video,
             "-frames:v", "1", "-q:v", "3", dest])
        if os.path.exists(dest):
            frames.append(dest)
    return frames


def self_test() -> int:
    need("ffmpeg", "apt-get update && apt-get install -y ffmpeg")
    need("ffprobe", "apt-get update && apt-get install -y ffmpeg")
    with tempfile.TemporaryDirectory() as d:
        sample = os.path.join(d, "t.mp4")
        run(["ffmpeg", "-loglevel", "error", "-f", "lavfi",
             "-i", "testsrc=duration=2:size=320x240:rate=10", sample])
        info = probe(sample)
        assert 1.5 < info["duration"] < 2.5, info
        frames = extract_frames(sample, d, 3, info["duration"])
        assert len(frames) == 3, frames
    print("self-test OK (ffmpeg probe + 3-frame extraction)")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("source", nargs="?", help="local video path or URL")
    ap.add_argument("--frames", type=int, default=0,
                    help="frame count (default: auto ≈1 per 5–10s, 6..16)")
    ap.add_argument("--out", default="", help="output dir (default: mkdtemp)")
    ap.add_argument("--max-height", type=int, default=720)
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        return self_test()
    if not args.source:
        ap.error("source (path or URL) required")

    need("ffmpeg", "apt-get update && apt-get install -y ffmpeg")
    need("ffprobe", "apt-get update && apt-get install -y ffmpeg")

    out_dir = args.out or tempfile.mkdtemp(
        prefix="watchvid-" + hashlib.sha1(args.source.encode()).hexdigest()[:8] + "-")
    os.makedirs(out_dir, exist_ok=True)

    meta, subs = {}, None
    if URL_RE.match(args.source):
        video, meta, subs = download(args.source, out_dir, args.max_height)
    else:
        video = args.source
        if not os.path.exists(video):
            die(f"file not found: {video}")

    info = probe(video)
    dur = info["duration"]
    n = args.frames or min(16, max(6, int(dur / 7.5) or 6))
    frames = extract_frames(video, out_dir, n, dur)

    print("=== VIDEO MANIFEST ===")
    if meta.get("title"):
        print(f"TITLE {meta['title']}")
        print(f"UPLOADER {meta.get('uploader', '?')}")
        print(f"URL {meta.get('url', args.source)}")
    print(f"SOURCE {args.source}")
    print(f"DURATION {dur:.1f}s  RES {info['width']}x{info['height']}  "
          f"AUDIO {'yes' if info['has_audio'] else 'no'}")
    print(f"FRAMES {len(frames)}")
    for f in frames:
        print(f"FRAME {f}")
    if subs:
        print(f"SUBS {subs}")
    else:
        print("SUBS none (no local speech-to-text — judge from frames; "
              "for YouTube, auto-subs usually arrive)")
    print("=== NEXT: Read each FRAME path as an image; Read SUBS if present ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
