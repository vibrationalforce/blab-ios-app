# Watch Clip (Echoel) — analyse a device screen-recording

The founder iterates from device media: `echoel_diag.log` text (see `device-log-triage`)
AND short screen-recordings / clips of the app running. This skill is the VIDEO twin —
it lets the agent actually SEE a clip instead of guessing (NO third-party "watch" skill,
nothing leaves the sandbox). Native distillation of the claude-video idea.

## ⛔ FIRST: `ffmpeg` IS NOT ON THE PATH — get it before anything else

This file said "using only the pre-installed `ffmpeg`/`ffprobe`" and that was **false in the
remote container**: `which ffmpeg ffprobe` → nothing, `import cv2` → ImportError. Measured
2026-08-12 while triaging three founder clips, which is the worst moment to find out. A skill
that names a tool the environment does not have does not fail loudly — it reads as "there is
nothing to see", which is the doctor-Section-B defect this repo already pays for elsewhere.

One line fixes it, and the binary is a wheel payload, so nothing is compiled and nothing but
PyPI is contacted:

```bash
python3 -m pip install --quiet imageio-ffmpeg
FF=$(python3 -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())")
```

Use `"$FF"` everywhere the steps below write `ffmpeg`. **There is no `ffprobe` in that wheel** —
`"$FF" -hide_banner -i "$V" 2>&1 | grep -E "Duration|Stream #"` gives the same duration,
resolution, fps and codec, so probe with that instead. If `ffmpeg` IS on the PATH in some other
environment, skip all of this and use it directly.

## When to use

The founder attaches an `.mp4`/`.mov`/`.gif` (a screen recording, a bug repro, a UI
flow, or an inspiration clip) and asks what's in it / what's wrong / what to build.

## Steps

- [ ] Probe it: `"$FF" -hide_banner -i "$V" 2>&1 | grep -E "Duration|Stream #"`.
      Portrait ~9:19.5 = an iPhone screen recording. ⚠️ **Portrait does NOT mean it is Echoel.**
      Measured 2026-08-12: all three clips the founder sent that day were 480×1042 iPhone
      recordings and none of them showed the app — they were Instagram reels about AI tooling.
      Read the contact sheet before routing anything as a bug.
- [ ] Extract to the scratchpad (never the repo). Overview first, then detail:
      - Contact sheet (one image, whole clip): `"$FF" -y -v error -i "$V" -vf "fps=1,scale=340:-1,tile=4x4" "$D/contact.jpg"`.
        Size the tile to the DURATION — 4x4 up to 16 s, 5x6 for ~28 s, 6x6 for ~33 s. Too few
        cells silently drops the tail of the clip; too many pad it with black.
      - Per-second full-res frames for detail: `"$FF" -y -v error -i "$V" -vf "fps=1" "$D/f_%02d.jpg"`.
      - Denser sampling for a fast bug (e.g. a flash/freeze): `fps=4`.
- [ ] `Read` the contact sheet for the flow, then `Read` the 2–3 key full-res frames
      (the moment of the bug / the screen in question) — small on-screen text needs
      full res, not the thumbnail.
- [ ] Read the on-screen **version string** (Echoelmusic header shows `vX.Y.Z (build)`).
      Confirm the fix you're verifying is actually IN that build (same rule as
      `device-log-triage` — a fix pushed AFTER that build is not on the founder's device).
- [ ] If the audio matters (does it SOUND right?), extract it: `"$FF" -y -v error -i "$V" -vn -ac 1 "$D/a.wav"`.
      There is no speech-to-text here; describe what's asked from the frames + founder text.

## Route the finding

- [ ] A visible freeze / menu that won't open while bio runs → `swiftui-render-safety`
      (10 Hz `@Observable` read in an ancestor — audit the parent/root).
- [ ] A black screen at launch / flash → `swiftui-render-safety` (sheet-chain metadata).
- [ ] Wrong pitch / silence / route glitch → `avaudio-route-resilience` / `device-log-triage`.
- [ ] A UI/layout ask or "build this" → describe what's on screen precisely, then the
      smallest Ralph change; if it's a marketing/inspiration clip, extract only the
      concrete idea, ignore the growth-hackery.

## Output

- [ ] One line: what the clip shows + the build/version.
- [ ] Then the routed root-cause + smallest fix, or the concrete idea to build.
- [ ] State honestly whether a fix is compile-verified (CI) vs device-verified (needs a
      new clip on the built version).
