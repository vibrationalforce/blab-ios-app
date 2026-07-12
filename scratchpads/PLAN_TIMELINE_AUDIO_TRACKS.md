# PLAN — Timeline Audio Tracks ("funktionierende Spuren aller Funktionen")

**Founder directive (2026-07-11):** "funktionierend Spuren aller Funktionen" —
the arrange timeline must play *all* track kinds, not just MIDI. Investigated
2026-07-12 (autonomous). This is the map so the next **device cycle** is fast
and safe; it was NOT wired blind because the audio side needs on-device
verification (no local Swift build here) and the founder's "zukunftsfähig und
stabil" bar forbids shipping untested audio-graph code.

## Ground truth (what already exists — reuse, don't rebuild)

- **Pure scheduling is done + tested.** `TimelineScheduling.laneEvent(in:laneID:fromTick:toTick:)`
  and `.activeRegion(...)` are lane-agnostic — they already resolve onsets/active
  regions for AUDIO lanes (`TimelineDocument.audioLaneIDs` exists). No new
  scheduling math needed.
- **`TimelineRegionPlayer` rides the transport** (reorg P3) and on each roll-lane
  onset loads the clip via `loadClip` — but `loadClip` handles ONLY
  `clip.drums` / `clip.melody` (MIDI). Audio lanes are ignored. THIS is the wiring gap.
- **File→sound paths are proven:**
  - `AudioClipPlayer` (`Sequencer/AudioClipPlayer.swift`) — control-plane
    `AVAudioPlayerNode`, attaches additively into the master mix, `load(url:)` +
    `play(region: AudioClipRegion)` (trim/loop/gain). Tested timing math in
    `AudioClipRegion`. Never touches the render path.
  - `BeatPlayer.audition(url:)` — a one-shot preview voice (used by the timeline's
    tap-to-audition, `ArrangeTimelineView:437`). Simpler, fire-and-forget.
- **mediaRef resolves today** via `ArrangeTimelineView.mediaURL(clip)` =
  `URL(fileURLWithPath: clip.mediaRef)`, existence-checked (absolute path only;
  "extend here when import lands"). `BeatPlayer` already handles security-scoped
  **bookmark data** (`BeatPlayer.swift:340–366`) — the durable-reference pattern to copy.

## The two real gaps (why it's a multi-step, device-verified feature)

1. **No audio-clip CREATION / durable persistence.** `AudioClipView` plays a
   *transient* security-scoped import; it never saves a launchable `Clip(kind:.audio,
   mediaRef:)`. `Clip.mediaRef` is read by the resolver but NOTHING writes it. So
   today there are no audio clips on the timeline to play — wiring playback alone
   would be a no-op (honest, bit-identical, but pointless until creation lands).
   Also `AudioClipRegion` (trim/loop/gain) is NOT attached to `Clip` — an audio
   region would play the whole file until this is modelled.
2. **Audio-graph wiring needs a device.** A per-lane `AudioClipPlayer` pool
   attached to `AudioEngine`, triggered on onset — control-plane, but attach/detach
   + timing must be heard on hardware. `audio-thread-reviewer` MANDATORY even though
   it's control-plane (node attach happens off the render thread).

## Ordered path (each = one safe, gate-verified cycle; audio steps need device)

- [ ] **A1. Durable audio-clip capture (pure + persistence, testable).** Import in
      `AudioClipView` → copy the file into the App Group (or store bookmark data)
      → save `Clip(kind:.audio, mediaRef: <durable ref>)` into `ClipStore`.
      Extend `mediaURL` to resolve bookmark refs (mirror `BeatPlayer`'s stale-refresh).
      Unit-test the ref round-trip. No timeline change yet. **Off-by-default: adds a
      Save button; existing flows untouched.**
- [ ] **A2. `AudioClipRegion` on `Clip` (pure).** Add optional trim/loop/gain to the
      audio clip (Codable, back-compat decode → full-file default). Tests. Unwired.
- [ ] **A3. Player pool + audio-lane playback in `TimelineRegionPlayer` (DEVICE).**
      Give the player weak `AudioEngine` access + a small `[laneID: AudioClipPlayer]`
      pool. In `transportStep`, iterate `doc.audioLaneIDs`; on each `.load` onset
      resolve mediaRef→URL, `attach`+`load`+`play(region:)`; on `.clear` stop that
      lane's node. Reuse the EXISTING `laneEvent` onset detection. Respect
      `document.effectiveGain(for: laneID)` (mute/solo parity with the audition tap).
      OFF-BY-DEFAULT: only fires during opt-in "Play timeline"; no clips → no-op →
      bit-identical. `audio-thread-reviewer` + on-device audible check. NEEDS-FOUNDER-VERIFY.
- [ ] **A4. Multi-lane MIDI (DEVICE).** Same shape for 2+ MIDI lanes → per-lane voices
      (today only the first roll lane sounds). Separate cycle.

## Safe interim (deployable WITHOUT a device — if the founder wants visible motion)

- Adaptive H/V polish (layout-only, render-safe, size-class in a LEAF like
  `ChannelRackView`'s proven v170 pattern): master mix strip-cards + weather
  Klang/Bild groups side-by-side in landscape, stacked in portrait. Serves
  "passendes adaptives Design für horizontal und Vertikal" without touching audio.
  Still wants the founder's eye for "passend", but cannot regress (revertible layout).

## Why not blind-wire A3 now
No local Swift build + no device = the audio graph can't be heard/verified here.
`stabil` + "never claim blind sensory changes as done" ⇒ A3/A4 wait for a device
session. A1/A2 are pure/persistence and CAN be done autonomously next.
