# PLAN — remove the dead drum apparatus (#167, follow-on to #166)

**Status:** Slice A shipped 2026-07-27. Slices B–D pending.
**Origin:** founder 2026-07-26 "KEINE DRUMS". `c9af52b` cut the SOUND and the mixer strip
and deliberately parked the apparatus: the comment it left in `BeatPlayer.attach(to:)`
says the WAV load was "left in place for exactly one cycle so this change stays small and
reversible; do not build anything new on it." This plan spends that deferral.

---

## Why this is sliced and not done in one commit

There is **no local Swift compiler** — CI is the only oracle, ~4 min per attempt. A single
commit deleting 4 source files plus edits across 8 test files has many independent ways to
fail to compile, and a red gate costs a whole cycle to bisect. Each slice below is
independently green-able and independently revertible.

The Council's split (2026-07-27): stop the *runtime waste* first (visible, near-zero risk),
then delete *files* (bigger diff, zero runtime risk), then touch *persisted enums* last
(smallest diff, highest blast radius).

---

## The reachability facts — traced directly, 2026-07-27

Established by grep against the working tree, not inherited from a report. Re-verify before
acting on any of it; this repo has been bitten by inherited claims twice this week.

**`BeatPlayer`'s only LIVE surface is `.pattern`.** Every reference outside the file is
`beatPlayer.pattern.*` (tempo, transport, `isPlaying`, `glideTempo`, `stop`) plus the two
lifecycle calls. `pattern` is the PatternEngine — the transport and tempo clock that
`pianoRoll.start(pattern:)` drives. **BeatPlayer is not a leftover; its sampler half is.**

**`SampleBrowserView` is UNREACHABLE.** `sampleBrowserTrack` has exactly three references in
all of `Sources/`: the `@State` declaration, the `.sheet(item:)`, and a comment. **No
setter anywhere.** Its own trigger (the drum channel strip from B5) went with `c9af52b`.

**`ChannelRackView` is UNREACHABLE** — zero instantiation sites since `c9af52b` removed the
embedded mount.

Therefore every sampler member of `BeatPlayer` — `audition(url:)`, `auditionBundled`,
`isCustom`, `resetSample`, `sampleLabels`, `trackNames`, `trigger`, `playPad`, `setFX`,
`voices`, `synthVoices`, `previewVoice`, `loadDefaultSamples` — has **no reachable
consumer**. `trackNames` looks live in a grep (two view files read it) but both readers are
themselves unreachable. This is the trap the repo has hit repeatedly: *a slot plus a
consumer does not prove reachability — the chain must be traced to a rendering parent.*

---

## Slice A — stop the launch-time WAV load ✅ SHIPPED 2026-07-27

Deleted `beatPlayer.loadDefaultSamples()` from `EchoelmusicApp`'s startup phase 1/4.

**Effect:** 8 bundled drum WAVs are no longer opened, decoded and held on every launch —
in the most crash-prone window of the app's life, for voices `attach(to:)` no longer wires
to the engine.

**Risk: none reachable.** The only consumers of what it filled are the two unreachable
views. One line plus a comment; trivially revertible.

**Deliberately NOT in this slice:** deleting `loadDefaultSamples()` itself. It still
compiles against `voices`, and removing the method belongs with the members in Slice C.

---

## Slice B — delete the two unreachable views + their tests

`Studio/ChannelRackView.swift` (229) · `Studio/SampleBrowserView.swift` ·
`ChannelRackTests.swift`.

⚠ **Removing `SampleBrowserView` also removes the `.sheet(item: $sampleBrowserTrack)`
modifier**, taking the presentation chain 15 → 14. That is the SAFE direction (the
black-screen law), but it also spends one of the four setter-less slots CLAUDE.md keeps as
a deliberate re-door reservoir. **Decide explicitly, do not let it happen as a side
effect:** either keep the slot by re-pointing it at a future editor in the same commit, or
state in the commit body that the reservoir is down to three and why that is acceptable.

---

## Slice C — delete the dead BeatPlayer half + the three orphan files

`Sequencer/LaneDrumKitVoice.swift` (123) · `Sequencer/DrumSynthVoice.swift` (238) ·
`Sequencer/DrumNoteMap.swift` (119), plus BeatPlayer's sampler members and
`Resources/Drums/` (8 WAVs, ~476 KB off the binary).

Order matters: `LaneDrumKitVoice` is referenced by `extension LaneDrumKitVoice: NoteVoice`
in `PianoRollView.swift`, by `LaneVoiceRack`'s `.drums` arms, by
`KindVoiceAllocator.drumUnits`, and by the `installKindUnitsForTests(kits:)` seam. Those go
in the same commit or nothing compiles.

Tests to retire with it: `DrumNoteMapTests` (38 refs), `LaneVoiceRackTests` (26),
`KindVoiceAllocatorTests` (15), `DrumSynthTests` (11), `PianoRollKindVoiceTests` (7).
`LaneVoiceRackTests` and `KindVoiceAllocatorTests` must be **edited, not deleted** — they
cover live non-drum behaviour too.

---

## Slice D — the persisted enum cases (LAST, and gated)

`LaneVoiceKind.drums` and `TrackInstrument.drums`/`.breakLoop` are **persisted raw values**.
Deleting them breaks decoding of any saved project that carries one. Blocked on the lossy
decode work (#163/#170); until then they stay, and the law is pinned by
`testSlotKindSink_publishesPolyForADrumsLane_becauseDrumsWereRemoved`.

---

## NOT dead — needs a founder answer before anyone touches it

`Clip.drums` / `DrumPattern` is on a **live** path: `TimelineRegionPlayer.loadClip` feeds it
to `pattern.load(steps:accents:)`, `MIDIFileExporter` writes it into exported `.mid`, and
`BioComposer` still GENERATES drum patterns (~34 references). Today those drive the step
grid and the MIDI export while producing no sound.

**The open question is the founder's, not an engineering call:** should an exported `.mid`
still carry a drum track for use in another DAW, or should the generator stop producing one
entirely? Asked 2026-07-27, unanswered. **Do not decide it by deleting code.**
