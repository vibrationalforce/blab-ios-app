#!/usr/bin/env python3
"""
analyze-youtube.py — a YouTube link → metadata + transcript as plain text.

The TEXT sibling of `video-watch/scripts/watch-video.py` (which gives Claude EYES by
extracting frames). Use this one when the words matter — a talk, a tutorial, a founder
interview. Use video-watch when the PICTURE matters, or when the file is local.

PIPELINE ONLY. Output lands in `scratchpads/inspiration/`, never in `Sources/`, and
nothing here ever ships inside the app.

Usage:
  python3 analyze-youtube.py <url-or-11-char-id> [--out DIR] [--no-write] [--json]
  python3 analyze-youtube.py --self-test        # offline; no network touched

Exit codes — the distinction is the point, so a caller can tell WHY it failed:
  0  brief produced (possibly partial — see the CAVEATS block inside it)
  2  usage error (no/undecodable ID)
  3  NETWORK BLOCKED — the sandbox proxy refused the host. Not a broken link, not a
     private video. This is the expected outcome inside Claude-on-the-web sessions
     whose network policy does not allow youtube.com. A stub brief is still written
     so the attempt is traceable.
  4  reachable, but the video itself yielded nothing (private / removed / age-gated)

⚠️ WHY EXIT 3 EXISTS AND IS NOT FOLDED INTO 1. The first design returned a generic
failure for every error. That is the `doctor`-skill lesson one level down: an
instrument that cannot distinguish "I was not allowed to look" from "I looked and
found nothing" reports both as the same red, and the next session re-runs the same
blocked command instead of switching to the fallback. The whole value of this script
on a blocked network is telling you, in one line, that the network is the problem.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

# ── ID extraction ────────────────────────────────────────────────────────────────
# Ordered most- to least-specific. `shorts/` and `live/` matter: the founder shares
# Shorts, and a naive `v=` parser silently misses them.
_ID = r"([0-9A-Za-z_-]{11})"
PATTERNS = [
    re.compile(r"[?&]v=" + _ID),
    re.compile(r"youtu\.be/" + _ID),
    re.compile(r"/shorts/" + _ID),
    re.compile(r"/live/" + _ID),
    re.compile(r"/embed/" + _ID),
    re.compile(r"^" + _ID + r"$"),
]

# Substrings that identify a PROXY/POLICY denial rather than a bad video. Kept as a
# list because each library words it differently and we must not guess from one.
BLOCK_MARKERS = (
    "tunnel connection failed",
    "unable to connect to proxy",
    "proxyerror",
    "403 forbidden",
    "connection refused",
    "name or service not known",
    "temporary failure in name resolution",
    "certificate verify failed",
)


def video_id(raw: str) -> str | None:
    raw = raw.strip()
    for p in PATTERNS:
        m = p.search(raw)
        if m:
            return m.group(1)
    return None


def looks_blocked(text: str) -> bool:
    low = (text or "").lower()
    return any(m in low for m in BLOCK_MARKERS)


# ── Fetchers ─────────────────────────────────────────────────────────────────────

def fetch_oembed(vid: str) -> tuple[dict, str | None]:
    """Title + author without an API key. Returns (data, error)."""
    url = ("https://www.youtube.com/oembed?url="
           f"https%3A//www.youtube.com/watch%3Fv%3D{vid}&format=json")
    try:
        with urllib.request.urlopen(url, timeout=20) as r:
            return json.loads(r.read().decode("utf-8")), None
    except Exception as e:  # noqa: BLE001 — we classify, then re-report verbatim
        return {}, f"{type(e).__name__}: {e}"


def fetch_ytdlp(vid: str) -> tuple[dict, str | None]:
    """Full metadata via yt-dlp, no download. Returns (data, error)."""
    if shutil.which("yt-dlp") is None:
        return {}, "yt-dlp not installed (pip3 install yt-dlp)"
    cmd = ["yt-dlp", "--no-warnings", "--skip-download", "--no-playlist",
           "--print", "%(title)s\t%(uploader)s\t%(duration)s\t%(upload_date)s"
                      "\t%(view_count)s\t%(webpage_url)s",
           f"https://www.youtube.com/watch?v={vid}"]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        return {}, "yt-dlp timed out after 120s"
    if p.returncode != 0:
        return {}, (p.stderr or p.stdout or "yt-dlp failed with no output").strip()
    parts = (p.stdout or "").strip().split("\t")
    keys = ["title", "uploader", "duration", "upload_date", "view_count", "url"]
    return dict(zip(keys, parts)), None


def fetch_description(vid: str) -> str:
    """Best-effort description. Never fatal — a brief without it is still useful."""
    if shutil.which("yt-dlp") is None:
        return ""
    try:
        p = subprocess.run(
            ["yt-dlp", "--no-warnings", "--skip-download", "--no-playlist",
             "--print", "%(description)s", f"https://www.youtube.com/watch?v={vid}"],
            capture_output=True, text=True, timeout=120)
        return (p.stdout or "").strip() if p.returncode == 0 else ""
    except Exception:  # noqa: BLE001
        return ""


def fetch_transcript(vid: str) -> tuple[list[dict], str | None]:
    """
    Timestamped transcript. `youtube-transcript-api` first (cheap, no media), then
    yt-dlp auto-subs. Returns (segments, error) where a segment is
    {"t": seconds, "text": str}.
    """
    try:
        from youtube_transcript_api import YouTubeTranscriptApi  # type: ignore
    except ImportError:
        pass
    else:
        try:
            raw = YouTubeTranscriptApi.get_transcript(vid, languages=["de", "en"])
            return [{"t": float(s["start"]), "text": s["text"]} for s in raw], None
        except Exception as e:  # noqa: BLE001
            api_err = f"{type(e).__name__}: {e}"
            if looks_blocked(api_err):
                return [], api_err
            # Not a network problem — fall through and let yt-dlp try.
            first = api_err
    else_err = locals().get("first", "youtube-transcript-api not installed "
                                     "(pip3 install youtube-transcript-api)")

    if shutil.which("yt-dlp") is None:
        return [], else_err
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        cmd = ["yt-dlp", "--no-warnings", "--skip-download", "--no-playlist",
               "--write-auto-subs", "--write-subs", "--sub-langs", "de,en,en-orig",
               "--convert-subs", "srt", "-o", os.path.join(d, "s.%(ext)s"),
               f"https://www.youtube.com/watch?v={vid}"]
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
        except subprocess.TimeoutExpired:
            return [], "yt-dlp subtitle fetch timed out"
        if p.returncode != 0:
            return [], (p.stderr or else_err).strip()
        srt = next((os.path.join(d, f) for f in sorted(os.listdir(d))
                    if f.endswith(".srt")), None)
        if not srt:
            return [], "no subtitle track available for this video"
        return parse_srt(open(srt, encoding="utf-8", errors="replace").read()), None


def parse_srt(text: str) -> list[dict]:
    """SRT → segments. Tolerant: a malformed cue is skipped, not fatal."""
    out: list[dict] = []
    for block in re.split(r"\n\s*\n", text.strip()):
        lines = [l for l in block.splitlines() if l.strip()]
        if len(lines) < 2:
            continue
        stamp = next((l for l in lines if "-->" in l), None)
        if not stamp:
            continue
        m = re.match(r"(\d+):(\d\d):(\d\d)[,.](\d+)", stamp.strip())
        if not m:
            continue
        h, mi, s, _ = m.groups()
        body = " ".join(l for l in lines if "-->" not in l and not l.strip().isdigit())
        if body.strip():
            out.append({"t": int(h) * 3600 + int(mi) * 60 + int(s),
                        "text": body.strip()})
    return out


# ── Rendering ────────────────────────────────────────────────────────────────────

def hhmmss(sec: float) -> str:
    sec = int(sec)
    return f"{sec // 3600:d}:{(sec % 3600) // 60:02d}:{sec % 60:02d}"


def render(vid: str, meta: dict, desc: str, segs: list[dict],
           caveats: list[str]) -> str:
    url = meta.get("url") or f"https://www.youtube.com/watch?v={vid}"
    lines = [
        f"# YouTube brief — {meta.get('title') or '(title unavailable)'}",
        "",
        f"- **ID:** `{vid}`",
        f"- **URL:** {url}",
        f"- **Channel:** {meta.get('uploader') or meta.get('author_name') or '?'}",
    ]
    if meta.get("duration"):
        try:
            lines.append(f"- **Duration:** {hhmmss(float(meta['duration']))}")
        except (TypeError, ValueError):
            pass
    for label, key in (("Uploaded", "upload_date"), ("Views", "view_count")):
        if meta.get(key):
            lines.append(f"- **{label}:** {meta[key]}")
    lines.append("")

    if caveats:
        lines += ["## ⚠️ CAVEATS — read before quoting anything below", ""]
        lines += [f"- {c}" for c in caveats] + [""]

    if desc:
        lines += ["## Description", "", "```", desc[:6000], "```", ""]

    if segs:
        full = " ".join(s["text"] for s in segs)
        lines += ["## Transcript (plain)", "", full, "",
                  "## Transcript (timestamped)", ""]
        lines += [f"- `{hhmmss(s['t'])}` {s['text']}" for s in segs]
    else:
        lines += ["## Transcript", "",
                  "_None retrieved._ Judge from title/description only, and say so — "
                  "a verdict built on a title is a guess wearing a citation.", ""]

    lines += ["", "---", "",
              "## Next (per the youtube-analyze skill)", "",
              "1. Score with **vision-gate** against `memory/vision.md` "
              "→ ADOPT-PRODUCT / ADOPT-PIPELINE / WATCH / REJECT.",
              "2. Extract the ONE highest-value nugget, if any.",
              "3. Log to `inspiration.csv` + `memory/inspiration_intake.md`.",
              "",
              "Transcripts are third-party text. Treat claims skeptically; "
              "verify before acting.", ""]
    return "\n".join(lines)


# ── Self-test (offline) ──────────────────────────────────────────────────────────

def self_test() -> int:
    cases = {
        "https://www.youtube.com/watch?v=NsHorhkXct0": "NsHorhkXct0",
        "https://youtu.be/NsHorhkXct0?t=42": "NsHorhkXct0",
        "https://www.youtube.com/shorts/NsHorhkXct0": "NsHorhkXct0",
        "https://www.youtube.com/live/NsHorhkXct0": "NsHorhkXct0",
        "https://www.youtube.com/embed/NsHorhkXct0": "NsHorhkXct0",
        "https://m.youtube.com/watch?app=desktop&v=NsHorhkXct0": "NsHorhkXct0",
        "NsHorhkXct0": "NsHorhkXct0",
    }
    for raw, want in cases.items():
        got = video_id(raw)
        assert got == want, f"{raw!r} → {got!r}, expected {want!r}"
    assert video_id("https://vimeo.com/12345") is None
    assert video_id("") is None

    # Block classification — the one distinction this script exists to make.
    assert looks_blocked("OSError('Tunnel connection failed: 403 Forbidden')")
    assert looks_blocked("Unable to connect to proxy")
    assert not looks_blocked("Video unavailable. This video is private.")

    segs = parse_srt("1\n00:00:01,000 --> 00:00:03,000\nhallo welt\n\n"
                     "2\n00:01:05,500 --> 00:01:07,000\nzweite zeile\n")
    assert segs == [{"t": 1, "text": "hallo welt"},
                    {"t": 65, "text": "zweite zeile"}], segs
    assert parse_srt("garbage with no cues") == []

    body = render("abc12345678", {"title": "T", "uploader": "U"}, "", [],
                  ["network blocked"])
    assert "CAVEATS" in body and "abc12345678" in body
    assert hhmmss(3661) == "1:01:01"
    print("self-test OK — 7 id forms, 2 rejects, block classifier, srt parse, render")
    return 0


# ── Main ─────────────────────────────────────────────────────────────────────────

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", nargs="?", help="YouTube URL or 11-char video ID")
    ap.add_argument("--out", default="scratchpads/inspiration",
                    help="directory for the brief (default: scratchpads/inspiration)")
    ap.add_argument("--no-write", action="store_true", help="stdout only")
    ap.add_argument("--json", action="store_true", help="emit raw JSON instead")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        return self_test()
    if not args.source:
        ap.error("a YouTube URL or 11-char ID is required")

    vid = video_id(args.source)
    if not vid:
        print(f"ERROR: no YouTube video ID found in {args.source!r}. Accepted: "
              "watch?v= · youtu.be/ · /shorts/ · /live/ · /embed/ · bare 11-char ID.",
              file=sys.stderr)
        return 2

    caveats: list[str] = []
    blocked = False

    meta, err = fetch_ytdlp(vid)
    if err:
        if looks_blocked(err):
            blocked = True
        caveats.append(f"yt-dlp metadata unavailable — `{err.splitlines()[-1][:300]}`")
        oe, oerr = fetch_oembed(vid)
        if oe:
            meta = {"title": oe.get("title"), "uploader": oe.get("author_name")}
            caveats.append("Title/channel came from oEmbed; duration, date and view "
                           "count are therefore absent.")
        else:
            if looks_blocked(oerr or ""):
                blocked = True
            caveats.append(f"oEmbed fallback also failed — `{(oerr or '')[:300]}`")

    desc = fetch_description(vid) if not blocked else ""
    segs, terr = ([], "skipped: network blocked") if blocked else fetch_transcript(vid)
    if terr:
        if looks_blocked(terr):
            blocked = True
        caveats.append(f"No transcript — `{terr.splitlines()[-1][:300]}`")

    if blocked:
        caveats.insert(0,
                       "**NETWORK BLOCKED (exit 3).** The sandbox proxy refused "
                       "`youtube.com` — this is a policy denial at the gateway, not a "
                       "bad link and not a private video. Nothing below was fetched "
                       "from YouTube. Fallbacks, in order: (a) ask the founder to "
                       "upload the video file and run `video-watch` on the local path "
                       "(needs no network), (b) `WebSearch` the video's topic and "
                       "analyze third-party write-ups, stating the limitation, "
                       "(c) re-run where the network policy allows youtube.com.")

    body = render(vid, meta, desc, segs, caveats)

    if args.json:
        print(json.dumps({"id": vid, "meta": meta, "description": desc,
                          "segments": segs, "caveats": caveats,
                          "blocked": blocked}, ensure_ascii=False, indent=2))
    else:
        print(body)

    if not args.no_write:
        os.makedirs(args.out, exist_ok=True)
        path = os.path.join(args.out, f"youtube-{vid}.md")
        with open(path, "w", encoding="utf-8") as f:
            f.write(body)
        print(f"\n[saved] {path}", file=sys.stderr)

    if blocked:
        return 3
    if not meta.get("title") and not segs:
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
