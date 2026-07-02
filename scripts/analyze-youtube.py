#!/usr/bin/env python3
"""analyze-youtube.py — pull a YouTube video's metadata + transcript for the
Echoel inspiration funnel.

PIPELINE ONLY. This is dev tooling for the Knowledge Funnel (memory/inspiration_intake.md
+ .claude/skills/vision-gate/). It NEVER ships in the app and NEVER touches Sources/.
Its job: turn a YouTube link into plain text so Claude can read it and score it against
memory/vision.md (ADOPT-PRODUCT / ADOPT-PIPELINE / WATCH / REJECT).

Usage:
    python3 scripts/analyze-youtube.py <url-or-id> [--lang en de] [--no-save] [--json]
    python3 scripts/analyze-youtube.py --self-test      # offline: verify ID parsing

Output: a Markdown brief on stdout, and (unless --no-save) saved to
    scratchpads/inspiration/youtube-<id>.md

Runtime deps (auto-detected; install on demand):
    pip3 install youtube-transcript-api       # transcript (required)
    pip3 install yt-dlp                        # richer metadata (optional; oEmbed fallback)

NETWORK: needs outbound access to youtube.com. Some sandboxes (incl. Claude-on-the-web
with a restrictive network policy) BLOCK youtube.com at the proxy — you'll see a 403 /
"CONNECT tunnel failed". Run this where YouTube is reachable (a local machine, or a web
session started with an open network policy). PyPI is usually reachable even when YT is not.
"""
from __future__ import annotations
import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SAVE_DIR = REPO / "scratchpads" / "inspiration"

# Accept the common URL shapes + a bare 11-char ID.
_ID_RE = re.compile(r"^[A-Za-z0-9_-]{11}$")
_URL_PATTERNS = [
    re.compile(r"[?&]v=([A-Za-z0-9_-]{11})"),          # watch?v=ID
    re.compile(r"youtu\.be/([A-Za-z0-9_-]{11})"),       # youtu.be/ID
    re.compile(r"/embed/([A-Za-z0-9_-]{11})"),          # /embed/ID
    re.compile(r"/shorts/([A-Za-z0-9_-]{11})"),         # /shorts/ID
    re.compile(r"/live/([A-Za-z0-9_-]{11})"),           # /live/ID
]


def extract_id(s: str) -> str | None:
    """Pull an 11-char video ID from a URL or return a bare ID unchanged."""
    s = s.strip()
    if _ID_RE.match(s):
        return s
    for pat in _URL_PATTERNS:
        m = pat.search(s)
        if m:
            return m.group(1)
    return None


def _is_network_block(err: Exception) -> bool:
    text = f"{type(err).__name__}: {err}".lower()
    return any(k in text for k in ("403", "connect tunnel", "proxy", "forbidden",
                                   "connection", "timed out", "ssl", "resolve"))


def fetch_metadata(video_id: str) -> dict:
    """Title/author/description. Prefer yt-dlp (full description); fall back to oEmbed."""
    # yt-dlp: richest (description, upload date, duration, view count).
    try:
        import yt_dlp  # type: ignore
        opts = {"quiet": True, "skip_download": True, "no_warnings": True}
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(f"https://www.youtube.com/watch?v={video_id}", download=False)
        return {
            "title": info.get("title"),
            "author": info.get("uploader") or info.get("channel"),
            "upload_date": info.get("upload_date"),
            "duration_s": info.get("duration"),
            "view_count": info.get("view_count"),
            "description": info.get("description"),
            "source": "yt-dlp",
        }
    except ImportError:
        pass
    except Exception as e:  # noqa: BLE001 — surface, don't crash the whole run
        if _is_network_block(e):
            raise
    # oEmbed fallback: title + author only, no key needed.
    import urllib.request
    url = f"https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v={video_id}&format=json"
    with urllib.request.urlopen(url, timeout=20) as r:  # noqa: S310
        data = json.loads(r.read().decode("utf-8"))
    return {"title": data.get("title"), "author": data.get("author_name"),
            "description": None, "source": "oembed"}


def fetch_transcript(video_id: str, langs: list[str]) -> list[dict]:
    """Return [{text,start,duration}] using whichever API the installed lib exposes."""
    from youtube_transcript_api import YouTubeTranscriptApi
    # Modern API (>=1.0): instance .fetch(); older: classmethod .get_transcript().
    if hasattr(YouTubeTranscriptApi, "fetch") and not hasattr(YouTubeTranscriptApi, "get_transcript"):
        fetched = YouTubeTranscriptApi().fetch(video_id, languages=langs)
        return [{"text": s.text, "start": s.start, "duration": s.duration} for s in fetched]
    # Legacy fallback.
    raw = YouTubeTranscriptApi.get_transcript(video_id, languages=langs)  # type: ignore[attr-defined]
    return [{"text": x["text"], "start": x["start"], "duration": x["duration"]} for x in raw]


def _fmt_ts(seconds: float) -> str:
    s = int(seconds)
    return f"{s // 60:d}:{s % 60:02d}"


def build_markdown(video_id: str, meta: dict, transcript: list[dict] | None,
                   transcript_err: str | None) -> str:
    url = f"https://www.youtube.com/watch?v={video_id}"
    out = [f"# YouTube brief — {meta.get('title') or video_id}", "",
           f"- **URL:** {url}",
           f"- **Author:** {meta.get('author') or '—'}"]
    if meta.get("upload_date"):
        out.append(f"- **Uploaded:** {meta['upload_date']}")
    if meta.get("duration_s"):
        out.append(f"- **Duration:** {_fmt_ts(meta['duration_s'])}")
    if meta.get("view_count"):
        out.append(f"- **Views:** {meta['view_count']:,}")
    out.append(f"- **Metadata source:** {meta.get('source', '—')}")
    out += ["", "## Description", "", (meta.get("description") or "_(none available)_"), ""]
    out += ["## Transcript", ""]
    if transcript:
        # Full plain-text transcript, plus a light timestamped view every ~30 s so we can
        # cite moments when we file the vision-gate verdict.
        out.append("### Plain text")
        out.append("")
        out.append(" ".join(seg["text"].replace("\n", " ") for seg in transcript))
        out += ["", "### Timestamped (every ~30 s)", ""]
        next_mark = 0.0
        for seg in transcript:
            if seg["start"] >= next_mark:
                out.append(f"- **{_fmt_ts(seg['start'])}** {seg['text'].strip()}")
                next_mark = seg["start"] + 30
    else:
        out.append(f"_No transcript: {transcript_err or 'unavailable'}_")
    out += ["", "---", "",
            "> Next step: score this against `memory/vision.md` via the **vision-gate** "
            "skill, then log the verdict to `inspiration.csv` + `memory/inspiration_intake.md`."]
    return "\n".join(out)


def self_test() -> int:
    cases = {
        "https://www.youtube.com/watch?v=V2RIVnGCy74": "V2RIVnGCy74",
        "https://youtu.be/V2RIVnGCy74?t=42": "V2RIVnGCy74",
        "https://www.youtube.com/embed/V2RIVnGCy74": "V2RIVnGCy74",
        "https://www.youtube.com/shorts/V2RIVnGCy74": "V2RIVnGCy74",
        "V2RIVnGCy74": "V2RIVnGCy74",
        "https://example.com/nope": None,
    }
    ok = True
    for inp, want in cases.items():
        got = extract_id(inp)
        flag = "ok " if got == want else "FAIL"
        if got != want:
            ok = False
        print(f"[{flag}] {inp!r} -> {got!r} (want {want!r})")
    print("SELF-TEST", "PASSED" if ok else "FAILED")
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser(description="Fetch a YouTube video's metadata + transcript.")
    ap.add_argument("target", nargs="?", help="YouTube URL or 11-char video ID")
    ap.add_argument("--lang", nargs="+", default=["en", "de"], help="preferred transcript languages")
    ap.add_argument("--no-save", action="store_true", help="print only; don't write the .md file")
    ap.add_argument("--json", action="store_true", help="emit raw JSON instead of Markdown")
    ap.add_argument("--self-test", action="store_true", help="offline: verify ID parsing and exit")
    args = ap.parse_args()

    if args.self_test:
        return self_test()
    if not args.target:
        ap.error("provide a YouTube URL or video ID (or --self-test)")

    video_id = extract_id(args.target)
    if not video_id:
        print(f"error: could not parse a video ID from {args.target!r}", file=sys.stderr)
        return 2

    # Metadata (best-effort; a network block here is fatal for the whole run).
    try:
        meta = fetch_metadata(video_id)
    except Exception as e:  # noqa: BLE001
        if _is_network_block(e):
            print(f"error: cannot reach YouTube (network policy blocks it here?): {e}\n"
                  f"Run where youtube.com is reachable — see the header of this script.",
                  file=sys.stderr)
            return 3
        meta = {"title": None, "author": None, "description": None, "source": f"error: {e}"}

    # Transcript (non-fatal: a video may simply have captions disabled).
    transcript, transcript_err = None, None
    try:
        transcript = fetch_transcript(video_id, args.lang)
    except ImportError:
        transcript_err = "youtube-transcript-api not installed (pip3 install youtube-transcript-api)"
    except Exception as e:  # noqa: BLE001
        transcript_err = f"{type(e).__name__}: {e}"
        if _is_network_block(e):
            print(f"error: cannot reach YouTube for the transcript: {e}", file=sys.stderr)
            return 3

    if args.json:
        payload = {"id": video_id, "meta": meta, "transcript": transcript,
                   "transcript_error": transcript_err}
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        return 0

    md = build_markdown(video_id, meta, transcript, transcript_err)
    print(md)
    if not args.no_save:
        SAVE_DIR.mkdir(parents=True, exist_ok=True)
        dest = SAVE_DIR / f"youtube-{video_id}.md"
        dest.write_text(md, encoding="utf-8")
        print(f"\n[saved] {dest.relative_to(REPO)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
