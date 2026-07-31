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

> **EYES: use the `video-watch` skill** (2026-07-13) when the VISUALS matter or the
> founder uploads a video file — it extracts frames Claude reads as images (local
> files need zero network; URL path shares this skill's network caveat). This skill
> remains the text/transcript path.
>
> **`scripts/analyze-youtube.py` NOW EXISTS** (2026-07-31). The note that stood here —
> "does not exist in this folder yet — prefer video-watch until it lands" — was true for
> two and a half weeks while the Procedure below documented the script as if it shipped.
> A skill that instructs a session to run a file that is not there costs that session a
> full detour before it discovers why.
>
> ⚠️ **AND THE THING THAT ACTUALLY BLOCKS YOU IS THE NETWORK, NOT THE SCRIPT.** Verified
> 2026-07-31 in this environment: `youtube.com` is refused at the agent-proxy gateway
> (`403 to CONNECT`, visible in `curl -sS "$HTTPS_PROXY/__agentproxy/status"` under
> `recentRelayFailures`). ALL THREE paths fail identically — `yt-dlp`, Python `urllib`
> (oEmbed), and the harness `WebFetch` tool. Do not spend a cycle trying a fourth; they
> share one egress. This is an ENVIRONMENT NETWORK POLICY chosen when the remote
> environment was created, so the real fix is the founder's, not the code's:
> https://code.claude.com/docs/en/claude-code/web

The founder shares videos as inspiration. This skill fetches the video's **metadata +
transcript** as plain text, then routes the content through the **vision-gate** so the repo
absorbs what's useful without drifting. It is the video sibling of the deep-research/
screenshot intake already in `memory/inspiration_intake.md`.

## Procedure

1. **Fetch** — run the tool from the repo root with the URL or 11-char ID:
   ```bash
   python3 .claude/skills/youtube-analyze/scripts/analyze-youtube.py "<url-or-id>"
   #   → prints a Markdown brief, saves scratchpads/inspiration/youtube-<id>.md
   python3 .claude/skills/youtube-analyze/scripts/analyze-youtube.py --self-test
   #   → offline; touches no network. 7 URL forms (incl. /shorts/ and /live/), 2 rejects,
   #     the block classifier, the SRT parser, the renderer.
   ```
   Accepts `watch?v=` · `youtu.be/` · `/shorts/` · `/live/` · `/embed/` · a bare 11-char ID.

   **READ THE EXIT CODE — it is the whole point of the tool.**

   | Code | Meaning | What you do |
   |---|---|---|
   | 0 | brief produced (check its CAVEATS block — it may be partial) | analyse |
   | 2 | no usable video ID in the argument | fix the argument |
   | 3 | **NETWORK BLOCKED at the proxy** — not a bad link, not a private video | go to the fallbacks |
   | 4 | reachable but empty (private / removed / age-gated) | tell the founder; nothing to analyse |

   A stub brief is written even on 3, so a blocked attempt stays traceable instead of
   vanishing. ⛔ Exit 3 is deliberately NOT folded into a generic failure: an instrument
   that reports "I was not allowed to look" and "I looked and found nothing" as the same
   red makes the next session re-run the blocked command instead of switching path. That
   is the `doctor` skill's law applied to this tool.

   - Optional deps, both auto-detected, both only useful once the network allows YouTube:
     `pip3 install youtube-transcript-api` (cheap transcript, no media download) and
     `pip3 install yt-dlp` (description/date/views + auto-subs as the transcript fallback).

2. **Fallbacks when you get exit 3** — in this order, and say WHICH one you used:
   - **(a) Ask for the file.** The founder uploads the video; run `video-watch` on the
     local path. Zero network, always works, and it gives you the PICTURE — which for a
     demo or a UI-inspiration clip is worth more than the transcript anyway.
   - **(b) `WebSearch` the video's TOPIC** (not the ID — ⛔ verified 2026-07-31: searching
     the bare 11-char ID returns unrelated pages, because IDs are not indexed as text).
     You need the title or subject from the founder for this to work at all.
   - **(c) Re-run where the policy allows `youtube.com`.**
   Whichever you use, state the limitation in the verdict. A tier assigned from a title
   is a guess wearing a citation.

3. **Read** the saved brief — title, author, description, full + timestamped transcript.

4. **Score** with the **vision-gate** skill against `memory/vision.md` + the 8 founder
   principles. Assign a tier: ADOPT-PRODUCT / ADOPT-PIPELINE / WATCH / REJECT. Most external
   videos (dev tooling, growth, generic AI) are PIPELINE or WATCH — a video rarely becomes an
   app feature. Extract the ONE highest-value nugget, if any.

5. **Log** — append a row to `inspiration.csv` and a bullet under a dated section in
   `memory/inspiration_intake.md` (source = "YouTube: <title> (<id>)"). Never silently expand
   app scope; if a verdict would change the roadmap, surface it and get founder confirmation.

## Guardrails

- **PIPELINE only.** Nothing here — the script, the transcript, the verdict — ever lands in
  `Sources/`. It informs decisions and marketing; the code stays the truth.
- Brand/overclaim rules from vision-gate apply to anything we adopt from a video (no wellness/
  esoteric/quantum/AGI, open standards preferred, accessibility-first).
- Transcripts are third-party text; treat claims skeptically and verify before acting.
