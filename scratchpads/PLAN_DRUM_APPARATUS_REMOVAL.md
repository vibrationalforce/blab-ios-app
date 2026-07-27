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

**`BeatPlayer` has TWO live surfaces** (the first draft of this plan said one — corrected
by review before anyone acted on it):
1. `beatPlayer.pattern` — the PatternEngine: transport, tempo clock, `pattern.transport`,
   `automationPlayer.wire(pattern:)`, `pianoRoll.start(pattern:)`, the bio→tempo mod
   destination, and ~20 sites in `EchoelStudioView`/`WorkspaceField`/`LoopExporter`.
2. the **static** `BeatPlayer.resolveSampleRef`, installed as `timelinePlayer
   .slotSampleSink` in `EchoelmusicApp` and fired from six sites in
   `TimelineRegionPlayer`. This one is easy to miss because it is not `beatPlayer.*`.

**BeatPlayer is not a leftover; its per-instance sampler half is.**

**`SampleBrowserView` is UNREACHABLE.** `sampleBrowserTrack` has exactly three references in
all of `Sources/`: the `@State` declaration, the `.sheet(item:)`, and a comment. **No
setter anywhere.** Its own trigger (the drum channel strip from B5) went with `c9af52b`.

**`ChannelRackView` is UNREACHABLE** — zero instantiation sites since `c9af52b` removed the
embedded mount.

Therefore the sampler members `audition(url:)`, `auditionBundled`, `isCustom`,
`resetSample`, `sampleLabels`, `trigger`, `playPad`, `setFX`, `voices`, `synthVoices`,
`previewVoice`, `loadDefaultSamples` have **no reachable consumer**. This is the trap the
repo keeps hitting: *a slot plus a consumer does not prove reachability — the chain must be
traced to a rendering parent.*

⚠ **`trackNames` IS NOT IN THAT LIST — my first draft put it there and was WRONG.** It has
**four** referencing files, not two, and one of them is the live root surface:
- `ChannelRackView` and `SampleBrowserView` — unreachable (Slice B)
- `BrowserView` — reads `bundledSampleNames`; also uninstantiated, and it was **missing
  from Slice B's delete list**
- **`EchoelStudioView.importMIDI(_:)` — `BeatPlayer.trackNames.count`, in the app's live
  root file**

The distinction that makes this subtle, and the reason a grep-plus-reachability check is
not enough on its own: `importMIDI` is **dead at RUNTIME** (`midiImportPresented` is one of
the setter-less flags) but **live at COMPILE time**. Deleting `trackNames` without deleting
`importMIDI` in the same commit turns the gate red — the exact cycle-burning failure this
slicing exists to avoid.

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
`Studio/BrowserView.swift` (added by review — also uninstantiated, and it reads
`bundledSampleNames`, so leaving it out would red-gate Slice C) · `ChannelRackTests.swift`.

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

**Also in this commit, or the gate goes red:** `importMIDI(_:)` and its `.fileImporter` in
`EchoelStudioView` (the live compile-time consumer of `trackNames` — see the warning above).
That also takes the presentation chain down by one more.

Tests to retire with it: `DrumNoteMapTests`, `LaneVoiceRackTests`,
`KindVoiceAllocatorTests`, `DrumSynthTests`, `PianoRollKindVoiceTests`. **Re-derive the
scope yourself** — the first draft of this plan carried per-file reference counts that a
review could not reproduce (it got a different number for three of the five), because the
counting metric was never stated. A number nobody can check is worse than no number.
`LaneVoiceRackTests` and `KindVoiceAllocatorTests` must be **edited, not deleted** — they
cover live non-drum behaviour too.

⚠ **`Resources/Drums/` IS NOT FREE TO DELETE — it is not just 472 KB of dead weight.**
`BeatPlayer.resolveSampleRef` (live, via `slotSampleSink`) resolves a persisted
`"drum:<Name>"` sample reference to `Resources/Drums/<Name>.wav`. An existing user whose
saved project has `TimelineLane.samplePath == "drum:Kick"` would, after the update, get
`nil` → `setSample(slot:url: nil)` → **a lane that used to sound goes silent, with no error
and no way for them to tell why.** No compile error catches this.
Before deleting the folder, either add a migration, or verify — by tracing
`setLaneSamplePath`'s writers to a rendering parent, which has NOT been done — that no
reachable writer can still create a `drum:` ref, and record that verification here.

---

## Slice D — the persisted enum cases (LAST, and gated)

`LaneVoiceKind.drums` and `TrackInstrument.drums`/`.breakLoop` are **persisted raw values**.
Deleting them breaks decoding of any saved project that carries one. Blocked on the lossy
decode work (#163/#170); until then they stay, and the law is pinned by
`testSlotKindSink_publishesPolyForADrumsLane_becauseDrumsWereRemoved`.

---

## NOT dead — needs a founder answer before anyone touches it

`Clip.drums` / `DrumPattern` is on a **live** path: `TimelineRegionPlayer.loadClip` feeds it
to `pattern.load(steps:accents:)`, and `BioComposer` still GENERATES drum patterns (~34
references). Those drive the step grid while producing no sound.

⚠ **CORRECTION, and I told the founder the wrong thing before catching it.** I wrote that
`MIDIFileExporter` "writes it into exported `.mid`" and asked the founder whether an
exported `.mid` should keep its drum track. **The app cannot export a `.mid` at all today**:
`MIDIFileExporter`'s only call site is `exportMIDI()` in `EchoelStudioView`, and
`exportMIDI()` has NO CALLER — only its definition and a comment (CLAUDE.md records the same
thing). The exporter is intact and tested; what is missing is the door. So the question as
put spent founder attention on a path he cannot reach.

**The real question, correctly framed:** MIDI export is doorless — does he want it back, and
if so, with or without a drum track? Re-asked 2026-07-27. **Do not decide it by deleting
code**, and do not delete `MIDIFileExporter` on the grounds that it is unreachable: it is a
tested exporter one button away from working, which is a different thing from dead code.
