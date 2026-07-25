# PLAN — non-finite guard on the clip/player path (2026-07-25)

Follow-up to the output-boundary series (`93df160` … `df54ac2`, all gates green).
That series closed every `AVAudioSourceNode` render block. This plan covers the
OTHER family of `masterMixer` inputs, which `AudioOutputGuard`'s header now names
explicitly as the most likely remaining entry point.

## Why this is real, not theoretical

`AVAudioPlayerNode`s feeding `masterMixer` replay buffers **we** wrote, carrying
**user-imported audio that no finiteness check has touched**:

- `AudioClipPlayer.swift:139-156` — fade envelope baked into the decoded buffer.
- `AudioClipPlayer.swift:218-228` (`scheduleStretched`) — `WSOLAStretcher` output
  copied into a fresh PCM buffer.
- `TimelineAudioSink.swift:209` — same WSOLA output, cached per `BeatsKey`.

A float32 file carrying NaN/inf bit patterns survives decode, survives the fade
multiply (`NaN * g == NaN`), survives WSOLA, and reaches `masterMixer`. From there
it poisons the recursive `AutoMixChain` EQ, and `EchoelLimiter.processStereo`
converts `inf` to NaN (see `AudioOutputGuard`'s header). This is the SAME threat
model that justified `SamplerVoice`'s sweep — arriving by a different door.

## THE FORK — where to sweep

**Option A — at schedule time**, immediately before each of the 5 `scheduleBuffer`
calls (`AudioClipPlayer` ×2, `TimelineAudioSink` ×1, `AudioEngine` ×2).
- + One obvious choke point per node; impossible to miss a new filler.
- − `TimelineAudioSink`'s buffer is **cached** (`beatsBuffers[BeatsKey]`) and
  rescheduled on every qualifying onset. A 5-minute stereo clip is ~28.8M samples;
  re-sweeping that per schedule is pure waste on the MainActor.

**Option B — at fill time**, once per buffer, where its contents are finalised.
- + O(n) exactly once per buffer; contents cannot change between schedules.
- − Three separate fill sites to get right, and a future filler could skip it.

**DECISION: B, with A for `AudioEngine`'s two generic entry points.**
`schedulePlayback`/`scheduleLoopPlayback` accept a buffer from an arbitrary caller,
so they have no fill site to attach to — those are one-shot playback paths where a
single pass is correct and cheap. Everything with a known filler sweeps at fill.

## Scope — and one path that CANNOT be covered, stated up front

`TimelineAudioSink.swift:268` uses `scheduleSegment(file:startingFrame:frameCount:)`,
which streams **straight from the `AVAudioFile`**. There is no intermediate buffer
of ours to sweep. Covering it would mean decoding the file ourselves purely to
sanitise it — a real cost on the main lane playback path for a fault nobody has
reported.

**This is deliberately left uncovered, and must be written into the doc as such.**
Do NOT let the next session's coverage note read as if the clip path is closed.
The honest statement after this plan lands: *buffers we build are swept; audio
streamed directly from a file by `scheduleSegment` is not.*

## Slices

1. **Helper.** `AudioOutputGuard.sweepNonFinite(_ buffer: AVAudioPCMBuffer)` in a
   NEW file `Sources/Echoelmusic/Audio/AudioOutputGuard+PCMBuffer.swift`, wrapped
   in `#if canImport(AVFoundation)`.
   NOT in `DSP/AudioOutputGuard.swift`: that file is Foundation-only by hygiene
   (`project.yml:162`), and the AUv3-isolation rule that motivated it is retired but
   the hygiene is still worth keeping. Guard `floatChannelData == nil` (integer
   formats cannot be non-finite) and honour `frameLength`, not `frameCapacity`.
   Tests first, mirroring `AudioOutputGuardTests`: bit-exact on finite audio,
   per-sample replacement, respects `frameLength`, multi-channel, nil-channel-data.

2. **Fill sites.** `AudioClipPlayer` (after the fade bake; inside
   `scheduleStretched` after the channel copy) and `TimelineAudioSink` (where the
   `beatsBuffers` entry is built).

3. **Generic entry points.** `AudioEngine.schedulePlayback` +
   `scheduleLoopPlayback`.

4. **Doc.** Update `AudioOutputGuard`'s coverage paragraph: the player-node family
   moves from "uncovered, deliberately named" to "buffers we build are swept",
   and `scheduleSegment` streaming becomes the named remaining gap.

## Constraints

- All of this is CONTROL PLANE (MainActor / offline render), not the audio thread —
  the audio-thread cost argument does not apply, but the MainActor stall does, which
  is the whole reason for the fill-vs-schedule fork above.
- Finite audio must stay bit-identical. No clamping. Same rule as the scalar guard.
- Reviewers: `audio-thread-reviewer` (graph correctness, buffer lifetime/aliasing —
  does an in-place sweep of a cached buffer race a node still reading it?) and
  `code-reviewer` (compile, no local Swift toolchain).

## Open question for the reviewer, NOT to be hand-waved

`TimelineAudioSink`'s cached buffer may be swept while a node still holds it from a
previous `scheduleBuffer`. Sweeping at FILL time (before first schedule) avoids
that entirely — confirm the fill site genuinely precedes every schedule of that
entry, or the sweep must move back to schedule time and eat the cost.
