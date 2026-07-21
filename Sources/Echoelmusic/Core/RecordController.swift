// RecordController.swift
// Record system — the device glue that drives the pure TakeRecorder from the live
// clock and commits its takes onto the timeline. Engine-free (Foundation + Core only:
// Transport, ClipStore, TimelineStore, EngineBus) so it compiles + unit-tests on every
// platform; the MIDI tee is installed by the app (kept off this file so it stays
// portable). Flow: arm() → the next transport step starts a take at that tick →
// external MIDI notes + bio samples stream in → transport Stop finalizes the take into
// one Clip per armed lane + a region on that lane.

import Foundation
import Observation

/// Anything that can capture microphone audio to a file for the span of one
/// take. Kept as a narrow protocol (not a direct `MultiTrackRecorder` import)
/// so `RecordController` stays Engine-free per the file law above — the app
/// wires a real recorder in; a test wires a spy in. `stop()` returns the
/// finished file + its measured length, or nil if nothing was captured (e.g.
/// `start()` never actually produced a file).
@MainActor
public protocol AudioTakeRecording: AnyObject {
    func start()
    func stop() async -> (url: URL, seconds: Double)?
}

@MainActor
@Observable
public final class RecordController {

    /// Lit while a take is armed/capturing (drives the Record button state).
    public private(set) var isRecording = false

    @ObservationIgnored private var recorder = TakeRecorder()
    @ObservationIgnored private weak var transport: Transport?
    @ObservationIgnored private weak var timeline: TimelineStore?
    @ObservationIgnored private weak var clips: ClipStore?
    @ObservationIgnored private weak var bus: EngineBus?
    @ObservationIgnored private var armed = false
    @ObservationIgnored private var lastTick = 0

    /// Task #13 (PLAN_AUDIO_LANE_RECORDING_2026-07-21.md, S1): an injected mic
    /// recorder for real audio-lane capture. nil (the default, and the shipped
    /// wiring unless `FeatureFlags.audioLaneRecording` is on) keeps every branch
    /// below inert — behavior byte-identical to before this recorder existed.
    @ObservationIgnored private weak var audioRecorder: (any AudioTakeRecording)?
    /// The one audio lane `audioRecorder` is capturing for the in-flight take,
    /// if any (today's recorder captures a single mic stream — the first armed
    /// audio lane wins; see `RecordPlan.armedAudioLaneIDs`).
    @ObservationIgnored private var recordingAudioLaneID: UUID?
    /// The async tail of the last `stop()` (awaiting the audio file + committing
    /// every take) — nil once it has finished, or when the last take had no
    /// audio leg. Exposed (non-`private`) purely so a test can await the SAME
    /// work `commitOnStop` fires-and-forgets, instead of racing it.
    @ObservationIgnored private(set) var pendingFinish: Task<Void, Never>?

    public init() {}

    /// Wire to the live clock + stores. Call once at startup after the transport is
    /// relayed by PatternEngine. Subscribes to the transport step (start take + poll
    /// bio) and stop (commit). The app installs the MIDI tee → `recordNoteOn/Off`.
    /// `audioRecorder` is the S1 mic-capture hook (nil = no audio recording, the
    /// default and today's shipped behavior).
    public func wire(transport: Transport, timeline: TimelineStore, clips: ClipStore, bus: EngineBus,
                      audioRecorder: (any AudioTakeRecording)? = nil) {
        self.transport = transport
        self.timeline = timeline
        self.clips = clips
        self.bus = bus
        self.audioRecorder = audioRecorder
        transport.addStepSubscriber("record", priority: 950) { [weak self] pos in
            self?.onStep(pos)
        }
        transport.addStopSubscriber("record") { [weak self] in
            self?.commitOnStop()
        }
    }

    private var currentTick: Int {
        (transport?.position.absoluteStep ?? 0) * TimelineTime.ticksPerTransportStep
    }

    /// True when at least one lane is armed + recordable (Record button enablement).
    public func hasArmedTarget() -> Bool {
        guard let timeline else { return false }
        return !RecordPlan.targets(in: timeline.document).isEmpty
    }

    /// Arm record mode. Capture begins on the next transport step while the clock runs
    /// (the UI starts the PatternEngine right after). No-op if nothing is armed.
    public func arm() {
        guard hasArmedTarget() else { return }
        armed = true
        isRecording = true
    }

    /// Cancel an armed/running take without committing anything.
    public func cancel() {
        armed = false
        recorder.cancel()
        isRecording = false
        if let audioRecorder, recordingAudioLaneID != nil {
            recordingAudioLaneID = nil
            Task { _ = await audioRecorder.stop() }
        }
    }

    // MARK: - Fed by the app's MIDI tee (no-op unless a take is running)

    public func recordNoteOn(pitch: Int, velocity: Float) {
        recorder.noteOn(pitch: pitch, velocity: velocity, atTick: currentTick)
    }

    public func recordNoteOff(pitch: Int) {
        recorder.noteOff(pitch: pitch, atTick: currentTick)
    }

    // MARK: - Clock hooks

    private func onStep(_ pos: TransportPosition) {
        guard armed else { return }
        let tick = pos.absoluteStep * TimelineTime.ticksPerTransportStep
        lastTick = tick
        if !recorder.isRecording {
            guard let timeline else { return }
            var targets = RecordPlan.targets(in: timeline.document)
            // S1 (flag-gated, task #13): an injected audio recorder plus an armed
            // .audioInput lane starts a real mic capture alongside any MIDI/bio
            // take. `captureImplemented`/`RecordPlan.targets` deliberately still
            // exclude .audioInput — the Record-button's honest gate is unchanged —
            // so with no audioRecorder wired (today's default) this is a no-op.
            if let audioRecorder, let audioLaneID = RecordPlan.armedAudioLaneIDs(in: timeline.document).first {
                targets.append((laneID: audioLaneID, source: .audioInput))
                recordingAudioLaneID = audioLaneID
                audioRecorder.start()
            }
            guard !targets.isEmpty else { return }
            recorder.start(targets: targets, anchorTick: tick)
        }
        // Poll bio into any armed bio lane each step (the recorder decimates internally).
        if let frame = bus?.usableBio() {
            let value = bioNormalized(bpm: Double(frame.heartRateBPM),
                                      breathRate: Double(frame.breathRate))
            recorder.captureBio(value: Double(value), atTick: tick)
        }
    }

    private func commitOnStop() {
        // Re-entrancy guard: Transport.stop() has no "already stopped" check and
        // other callers (e.g. the app's route-loss handler) can invoke it again
        // while the FIRST stop's audio finish is still in flight — without this,
        // that second call would see `recorder.isRecording` still true (the take
        // isn't finished yet) and `recordingAudioLaneID` already nil, take the
        // synchronous branch, and `recorder.finish()` the take out from under the
        // pending Task — silently dropping the mic file that's still being awaited.
        guard pendingFinish == nil else { return }
        guard recorder.isRecording else { armed = false; isRecording = false; return }
        armed = false
        isRecording = false
        let stopTick = lastTick
        if let audioRecorder, let laneID = recordingAudioLaneID {
            recordingAudioLaneID = nil
            // The mic file only finalizes after an async stop — commit waits for
            // it so the audio take lands in the SAME batch as any MIDI/bio takes,
            // exactly like a synchronous commit would have. The transport's stop
            // subscriber (this function) must stay synchronous, so the tail is a
            // tracked, fire-and-continue Task rather than an `await` here.
            pendingFinish = Task { @MainActor [weak self] in
                await self?.finishWithAudio(audioRecorder, laneID: laneID, atTick: stopTick)
                self?.pendingFinish = nil
            }
        } else {
            commit(recorder.finish(atTick: stopTick), atTick: stopTick)
        }
    }

    /// Awaits the mic file for `laneID`, feeds it into the pure recorder, and
    /// commits every take from this stop (audio + any MIDI/bio in the same
    /// take). Not `private` so a test can await it directly instead of racing
    /// the fire-and-continue `Task` `commitOnStop` spawns. `tick` is the stop
    /// tick CAPTURED at stop time — `self.lastTick` must not be read here
    /// instead, since a new take may already have started (and moved it) by
    /// the time the `await` below returns.
    func finishWithAudio(_ audioRecorder: any AudioTakeRecording, laneID: UUID, atTick tick: Int) async {
        if let result = await audioRecorder.stop() {
            recorder.captureAudio(laneID: laneID, mediaRef: result.url.path, durationSeconds: result.seconds)
        }
        commit(recorder.finish(atTick: tick), atTick: tick)
    }

    private func commit(_ takes: [RecordedTake], atTick stopTick: Int) {
        guard let clips, let timeline else { return }
        for take in takes {
            // Captured clips live in a free ClipStore slot (the region resolves its
            // clipID there). If the 8-slot grid is full, skip honestly — a dedicated
            // take container is a later cycle.
            guard let slot = clips.slots.firstIndex(where: { $0 == nil }) else { continue }
            clips.setClip(at: slot, take.clip)
            timeline.addRegion(TimelineRegion(
                laneID: take.laneID,
                clipID: take.clip.id,
                startTick: take.startTick,
                lengthTicks: Self.takeLength(fromAnchor: take.startTick, toStop: stopTick)))
        }
    }

    /// Region length: the captured span rounded UP to whole bars (minimum one bar), so
    /// a recorded take reads as clean bars on the grid. Pure — unit-testable.
    static func takeLength(fromAnchor anchor: Int, toStop stop: Int) -> Int {
        let span = max(0, stop - anchor)
        let bars = max(1, (span + TimelineTime.ticksPerBar - 1) / TimelineTime.ticksPerBar)
        return bars * TimelineTime.ticksPerBar
    }
}
