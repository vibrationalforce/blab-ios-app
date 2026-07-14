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

    public init() {}

    /// Wire to the live clock + stores. Call once at startup after the transport is
    /// relayed by PatternEngine. Subscribes to the transport step (start take + poll
    /// bio) and stop (commit). The app installs the MIDI tee → `recordNoteOn/Off`.
    public func wire(transport: Transport, timeline: TimelineStore, clips: ClipStore, bus: EngineBus) {
        self.transport = transport
        self.timeline = timeline
        self.clips = clips
        self.bus = bus
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
            let targets = RecordPlan.targets(in: timeline.document)
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
        guard recorder.isRecording else { armed = false; isRecording = false; return }
        let takes = recorder.finish(atTick: lastTick)
        commit(takes)
        armed = false
        isRecording = false
    }

    private func commit(_ takes: [RecordedTake]) {
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
                lengthTicks: Self.takeLength(fromAnchor: take.startTick, toStop: lastTick)))
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
