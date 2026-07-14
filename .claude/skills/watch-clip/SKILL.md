# Watch Clip (Echoel) — analyse a device screen-recording

The founder iterates from device media: `echoel_diag.log` text (see `device-log-triage`)
AND short screen-recordings / clips of the app running. This skill is the VIDEO twin —
it lets the agent actually SEE a clip instead of guessing, using only the pre-installed
`ffmpeg`/`ffprobe` (NO third-party "watch" skill, NO dependency, nothing leaves the
sandbox). Native distillation of the claude-video idea.

## When to use

The founder attaches an `.mp4`/`.mov`/`.gif` (a screen recording, a bug repro, a UI
flow, or an inspiration clip) and asks what's in it / what's wrong / what to build.

## Steps

- [ ] Probe it: `ffprobe -v error -show_entries format=duration,size:stream=width,height,codec_name -of default=noprint_wrappers=1 "$V"`.
      Portrait ~9:19.5 = an iPhone screen recording of Echoel.
- [ ] Extract to the scratchpad (never the repo). Overview first, then detail:
      - Contact sheet (one image, whole clip): `ffmpeg -y -i "$V" -vf "fps=1,scale=380:-1,tile=4x4" "$D/contact.jpg"` (raise tile to 5x5/6x6 for >16 s).
      - Per-second full-res frames for detail: `ffmpeg -y -i "$V" -vf "fps=1" "$D/f_%02d.jpg"`.
      - Denser sampling for a fast bug (e.g. a flash/freeze): `fps=4`.
- [ ] `Read` the contact sheet for the flow, then `Read` the 2–3 key full-res frames
      (the moment of the bug / the screen in question) — small on-screen text needs
      full res, not the thumbnail.
- [ ] Read the on-screen **version string** (Echoelmusic header shows `vX.Y.Z (build)`).
      Confirm the fix you're verifying is actually IN that build (same rule as
      `device-log-triage` — a fix pushed AFTER that build is not on the founder's device).
- [ ] If the audio matters (does it SOUND right?), extract it: `ffmpeg -y -i "$V" -vn -ac 1 "$D/a.wav"`.
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
