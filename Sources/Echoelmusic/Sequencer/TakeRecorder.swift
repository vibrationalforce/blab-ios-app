// TakeRecorder.swift
// Record system — the PURE per-lane capture coordinator. Turns live input (MIDI
// notes, bio samples) arriving during a take into one Clip per armed lane when the
// take stops. No engine, no clock, no I/O — the device layer (a RecordController)
// feeds it timestamped events off the transport and commits the returned takes into
// ClipStore + the timeline. Foundation-only, value semantics → unit-tested on every
// platform, exactly like the recorders it drives (MIDINoteRecorder /
// BioAutomationRecorder).

import Foundation

/// One finished take ready to commit: the lane it belongs to, the captured Clip, and
/// the song tick where it starts (so the caller can place a region there).
public struct RecordedTake: Equatable, Sendable {
    public let laneID: UUID
    public let clip: Clip
    public let startTick: Int
    public init(laneID: UUID, clip: Clip, startTick: Int) {
        self.laneID = laneID
        self.clip = clip
        self.startTick = startTick
    }
}

/// Coordinates capture across every armed lane for one take. MIDI-input lanes record
/// notes; bio lanes record an automation lane; audio-input lanes commit the file the
/// device recorder wrote (fed in via `captureAudio` — the PCM tap itself is the thin
/// device layer). Video-capture / none sources are recognised but produce no take here.
public struct TakeRecorder: Sendable {

    public private(set) var isRecording = false
    /// Song tick where the current take began (clips are clip-relative from here).
    public private(set) var anchorTick = 0

    // Per-lane recorders, plus a stable id order so `finish()` output is deterministic.
    private var midi: [UUID: MIDINoteRecorder] = [:]
    private var bio: [UUID: BioAutomationRecorder] = [:]
    private var midiOrder: [UUID] = []
    private var bioOrder: [UUID] = []

    /// One armed audio lane's captured file. The device recorder measures the file on
    /// stop (AVAsset) and hands the absolute mediaRef + duration to `captureAudio`;
    /// this struct stays pure (no PCM, no AVFoundation, no I/O).
    private struct AudioCapture: Equatable, Sendable { let mediaRef: String; let durationSeconds: Double }
    private var audio: [UUID: AudioCapture] = [:]
    private var audioOrder: [UUID] = []

    public init() {}

    /// True once a take is running AND at least one lane is actually capturing.
    public var isCapturing: Bool { isRecording && (!midi.isEmpty || !bio.isEmpty || !audioOrder.isEmpty) }
    /// How many lanes are recording MIDI / bio / audio right now (inspection/tests).
    public var midiLaneCount: Int { midi.count }
    public var bioLaneCount: Int { bio.count }
    public var audioLaneCount: Int { audioOrder.count }

    /// Begin a take. `targets` are the armed, recordable lanes (RecordPlan.targets);
    /// each MIDI-input lane gets a MIDINoteRecorder, each bio lane a
    /// BioAutomationRecorder, both anchored at `anchorTick`. Idempotent-safe: replaces
    /// any prior take state.
    public mutating func start(targets: [(laneID: UUID, source: RecordSource)], anchorTick: Int) {
        isRecording = true
        self.anchorTick = anchorTick
        midi.removeAll(); bio.removeAll(); midiOrder.removeAll(); bioOrder.removeAll()
        audio.removeAll(); audioOrder.removeAll()
        for target in targets {
            switch target.source {
            case .midiInput:
                midi[target.laneID] = MIDINoteRecorder(anchorTick: anchorTick, role: .harmony)
                midiOrder.append(target.laneID)
            case .bio:
                bio[target.laneID] = BioAutomationRecorder(parameter: "bio.arousal", anchorTick: anchorTick)
                bioOrder.append(target.laneID)
            case .audioInput:
                audioOrder.append(target.laneID)   // armed; the file arrives via captureAudio
            case .videoCapture, .none:
                break   // video capture handled by the video lane path; none records nothing
            }
        }
    }

    /// Feed a live note-on (from CoreMIDI input) into every armed MIDI lane, stamped at
    /// the song tick it arrived. No-op unless a take is running.
    public mutating func noteOn(pitch: Int, velocity: Float, atTick tick: Int) {
        guard isRecording else { return }
        for id in midiOrder { midi[id]?.noteOn(pitch: pitch, velocity: velocity, atTick: tick) }
    }

    /// Feed a live note-off into every armed MIDI lane.
    public mutating func noteOff(pitch: Int, atTick tick: Int) {
        guard isRecording else { return }
        for id in midiOrder { midi[id]?.noteOff(pitch: pitch, atTick: tick) }
    }

    /// Feed a normalized bio value (bioNormalized 0…1) into every armed bio lane. The
    /// BioAutomationRecorder decimates internally, so the caller may poll freely.
    public mutating func captureBio(value: Double, atTick tick: Int) {
        guard isRecording else { return }
        for id in bioOrder { bio[id]?.capture(value: value, atTick: tick) }
    }

    /// Commit the file a device-side audio recorder produced for an armed audio lane.
    /// `mediaRef` is the absolute path it wrote (App Group `Media/Audio`), `durationSeconds`
    /// its measured length. No-op unless a take is running and the lane was armed for
    /// audio input. The latest call wins if a lane is committed more than once.
    public mutating func captureAudio(laneID: UUID, mediaRef: String, durationSeconds: Double) {
        guard isRecording, audioOrder.contains(laneID) else { return }
        audio[laneID] = AudioCapture(mediaRef: mediaRef, durationSeconds: durationSeconds)
    }

    /// End the take. Flushes any still-held notes, returns one RecordedTake per lane
    /// that actually captured content (empty takes are dropped), and resets to idle.
    public mutating func finish(atTick tick: Int) -> [RecordedTake] {
        guard isRecording else { return [] }
        var takes: [RecordedTake] = []
        for id in midiOrder {
            guard var rec = midi[id] else { continue }
            rec.flushOpen(atTick: tick)
            let melody = rec.melody()
            guard !melody.notes.isEmpty else { continue }
            takes.append(RecordedTake(
                laneID: id,
                clip: Clip(name: "Take", kind: .midi, melody: melody),
                startTick: anchorTick))
        }
        for id in bioOrder {
            guard let rec = bio[id], rec.hasContent else { continue }
            takes.append(RecordedTake(
                laneID: id,
                clip: Clip(name: "Bio Take", kind: .midi, automation: [rec.lane()]),
                startTick: anchorTick))
        }
        for id in audioOrder {
            // An armed audio lane that never got a file (or an empty ref) drops, exactly
            // like an empty MIDI/bio take — no phantom zero-length clip.
            guard let cap = audio[id], !cap.mediaRef.isEmpty else { continue }
            takes.append(RecordedTake(
                laneID: id,
                clip: AudioClipFactory.clip(name: "Audio Take", mediaRef: cap.mediaRef,
                                            nativeDurationSeconds: cap.durationSeconds),
                startTick: anchorTick))
        }
        isRecording = false
        midi.removeAll(); bio.removeAll(); midiOrder.removeAll(); bioOrder.removeAll()
        audio.removeAll(); audioOrder.removeAll()
        return takes
    }

    /// Abort the take with no takes produced (e.g. transport stopped without commit).
    public mutating func cancel() {
        isRecording = false
        midi.removeAll(); bio.removeAll(); midiOrder.removeAll(); bioOrder.removeAll()
        audio.removeAll(); audioOrder.removeAll()
    }
}
