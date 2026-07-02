---
name: youtube-analyze
description: >
  Turn a YouTube link into text (metadata + transcript) so it can be scored against the
  Echoel vision. Use when the founder shares a YouTube URL and asks "what's useful in here
  for the project?", "analyze this video", or drops a link as inspiration. PIPELINE ONLY —
  it feeds the Knowledge Funnel (vision-gate + inspiration ledger); it never ships in the
  app and never touches Sources/.
---

# youtube-analyze — a YouTube link → an on-vision verdict

The founder shares videos as inspiration. This skill fetches the video's **metadata +
transcript** as plain text, then routes the content through the **vision-gate** so the repo
absorbs what's useful without drifting. It is the video sibling of the deep-research/
screenshot intake already in `memory/inspiration_intake.md`.

## Procedure

1. **Fetch** — run the tool with the URL or 11-char ID:
   ```bash
   python3 scripts/analyze-youtube.py "<url-or-id>"        # → prints a Markdown brief,
                                                            #   saves scratchpads/inspiration/youtube-<id>.md
   python3 scripts/analyze-youtube.py --self-test          # offline sanity check (ID parsing)
   ```
   - Runtime deps auto-detected; install on demand:
     `pip3 install youtube-transcript-api` (transcript) and optionally `pip3 install yt-dlp`
     (full description/date/views; oEmbed title+author is the fallback).
   - **Network:** the tool needs outbound access to `youtube.com`. Restrictive sandboxes
     (incl. some Claude-on-the-web network policies) BLOCK `youtube.com` at the proxy — you'll
     get a clean `403 / CONNECT tunnel failed` error. When that happens, either (a) run it in a
     session/machine where YouTube is reachable, or (b) fall back to `WebSearch` for the video's
     topic + third-party write-ups and analyze from those (state the limitation honestly).

2. **Read** the saved brief — title, author, description, full + timestamped transcript.

3. **Score** with the **vision-gate** skill against `memory/vision.md` + the 8 founder
   principles. Assign a tier: ADOPT-PRODUCT / ADOPT-PIPELINE / WATCH / REJECT. Most external
   videos (dev tooling, growth, generic AI) are PIPELINE or WATCH — a video rarely becomes an
   app feature. Extract the ONE highest-value nugget, if any.

4. **Log** — append a row to `inspiration.csv` and a bullet under a dated section in
   `memory/inspiration_intake.md` (source = "YouTube: <title> (<id>)"). Never silently expand
   app scope; if a verdict would change the roadmap, surface it and get founder confirmation.

## Guardrails

- **PIPELINE only.** Nothing here — the script, the transcript, the verdict — ever lands in
  `Sources/`. It informs decisions and marketing; the code stays the truth.
- Brand/overclaim rules from vision-gate apply to anything we adopt from a video (no wellness/
  esoteric/quantum/AGI, open standards preferred, accessibility-first).
- Transcripts are third-party text; treat claims skeptically and verify before acting.
