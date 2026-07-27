//
//  BioEventPublisher.swift
//  Echoelmusic
//
//  Connects the protected BioEventGraph to the live bus. Polls
//  bus.latestBio at 10 Hz, runs each fresh frame's breath-phase and
//  motion-energy channels through a BioEventGraph instance, and
//  publishes the detected discrete BioEvents back onto
//  EngineBus.bioEvents — the third bus topic, until now empty.
//
//  Heartbeat detection needs a raw continuous waveform (PPG/ECG),
//  which the bus does not carry yet (publishers summarise to HR/HRV
//  before publishing). So this cycle wires the breath-onset and
//  motion-peak detectors, which operate correctly on the summary
//  frame's breathPhase [0..1] and motionEnergy [0..1] channels. A
//  follow-up cycle routes Polar H10 RR-interval timing directly into
//  .heartbeat events (the RR stream IS the beat timing — no waveform
//  detection required).
//
//  Per BioEventGraph SKILL.md: this is a caller / subscriber, it does
//  not touch the protected component's internals.
//

#if canImport(Observation)
import Observation
#endif
import Foundation

@MainActor
@Observable
public final class BioEventPublisher {

    public private(set) var isActive = false

    /// Count of BioEvents published since start — visible proof the
    /// detection chain is producing on the bus.
    public private(set) var eventsPublished: UInt64 = 0

    /// Mach-time of the most recent published event, for UI activity.
    public private(set) var lastEventTimestamp: TimeInterval = 0

    @ObservationIgnored
    private weak var bus: EngineBus?

    /// ONE DETECTOR GRAPH PER SOURCE (#186 follow-up, corrected after review).
    ///
    /// A single shared graph was the bug: its detectors are edge-triggered on the previous
    /// sample, so two sources feeding one graph produce edges that belong to NEITHER —
    /// a camera session ending mid-cycle at 0.3 followed by a HealthKit frame at 0.5 reads
    /// as an inhale. My first fix reset the shared graph whenever the source changed, and
    /// review showed that is WORSE, not better: sources do not take turns. `stopBioSource`
    /// stops camera/strap/demo but NOT `HealthKitBioPublisher`, which is started at the
    /// first bio use of every run and keeps publishing alongside whatever the user picked.
    /// So the bus interleaves, and a reset-on-change would have fired twice per HealthKit
    /// sample, destroying real camera breath edges — the exact "over-eager reset deafens
    /// the detector" failure the tests were written to guard against, one layer up.
    ///
    /// Per-source state removes the class instead of trading one artifact for another:
    /// each source's trajectory stays continuous and interleaving cannot contaminate.
    /// Bounded by `BioSource`'s case count (7), each a small value type.
    ///
    /// It also closes a 5.1.3 hole the first two attempts both missed. A cross-source event
    /// was stamped with the source of the frame that happened to be current when it fired
    /// (below), so a HealthKit-influenced onset could arrive stamped `.cameraPPG` and
    /// therefore PASS `BioEgressPolicy` on its way to the network. Gating events (#186) did
    /// not fix that — the stamp was wrong, not missing. Separating the state does.
    @ObservationIgnored
    private var graphs: [BioSource: BioEventGraph] = [:]

    /// Last frame time SEEN PER SOURCE. Two jobs, both of which the shared field it replaced
    /// got wrong under interleaving: it decides the stale gap below, AND it is the de-dup.
    ///
    /// The de-dup MUST be per-source. `CameraRPPGBioPublisher` republishes its last good
    /// frame during a dropout hold carrying the ORIGINAL `timestamp`, and says so as a
    /// contract at its call site: "consumers that dedupe on `timestamp` now treat a held
    /// republish as a no-op". A single shared `lastFrameTimestamp` honoured that only while
    /// one source published — the moment a HealthKit frame lands between two held camera
    /// republishes, the held frame's timestamp no longer equals the last-seen one and the
    /// same stale sample is fed to the camera's detector again and again. Benign today for
    /// the same three reasons flagged in `tick` (constant phase, zero motion, zero heart),
    /// which is exactly what makes it a latent defect rather than a non-issue.
    @ObservationIgnored
    private var lastFrameTimeBySource: [BioSource: TimeInterval] = [:]

    /// A source silent for longer than this has its detector state cleared before its next
    /// frame: after a documented 68–200 s rPPG stall the stored `previous` describes a
    /// breath from minutes ago, and resuming against it is the same phantom edge as a
    /// source switch. Generous on purpose — this must not fire between normal 10 Hz frames.
    @ObservationIgnored
    private static let staleGap: TimeInterval = 10

    @ObservationIgnored
    private var task: Task<Void, Never>?

    /// Bus poll cadence is 10 Hz; the heartbeat detector's refractory is unused here
    /// (no waveform fed), so 10 is fine.
    @ObservationIgnored
    private static let graphSampleRate: Double = 10

    public init() {}

    public func start(on bus: EngineBus) {
        guard !isActive else { return }
        self.bus = bus
        isActive = true
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let bus = self.bus else { break }
                self.tick(bus)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        isActive = false
        // Detector state does NOT survive a stop. Resuming inside the stale gap against a
        // `previous` from the previous session is the same phantom edge as a source switch,
        // only across a session boundary — and the stale gap cannot catch it, because wall
        // time keeps running while this object does not. `stop()` has no production caller
        // today (the publisher is started once, `EchoelmusicApp.swift:799`), so this closes
        // a trap for whoever adds one rather than fixing a live bug.
        graphs.removeAll()
        lastFrameTimeBySource.removeAll()
    }

    /// Internal, not private, so a test can drive ONE frame deterministically instead of
    /// racing the 10 Hz task — the seam `HealthKitBioPublisher.publishIfFresh(to:)` already
    /// established for exactly this reason. The first cut of this fix called the wiring
    /// "not pinnable"; that was wrong, and the precedent was one file away.
    func tick(_ bus: EngineBus) {
        guard let frame = bus.latestBio else { return }
        let lastSeen = lastFrameTimeBySource[frame.source]
        guard lastSeen != frame.timestamp else { return }

        // Each source gets its OWN detector state (see `graphs`), so an interleaved bus
        // cannot produce an edge spanning two sources. This is the caller's job by
        // contract: `BioEventGraph` is protected and already exposes `reset()`, and its
        // SKILL.md says a wrong output is fixed in the caller, the input data or the
        // threading — never in the component.
        var graph = graphs[frame.source] ?? BioEventGraph(sampleRate: Self.graphSampleRate)

        // A source resuming after a long silence is the same phantom edge as a switch:
        // its stored `previous` describes a breath from minutes ago. Reset only THAT
        // source. (⚠️ `reset()` is not purely suppressive — `MotionPeakDetector` has no
        // `previous`; it is a latched hysteresis, and reset re-ARMS it, so a reset during
        // sustained motion would report a plateau as an onset. Unreachable today: every
        // publisher writes `motionEnergy: 0`. The cycle that adds a real CoreMotion
        // producer must revisit this line. Same shape on the heartbeat side: the first
        // beat after a reset reports `aux = 0` as an inter-beat interval, unreachable
        // only because `cleanedHeart` is passed as 0 below.)
        if let lastSeen, frame.timestamp - lastSeen > Self.staleGap {
            graph.reset()
        }
        lastFrameTimeBySource[frame.source] = frame.timestamp

        let events = graph.process(
            cleanedHeart: 0,            // raw waveform not on the bus yet
            breathPhase: frame.breathPhase,
            motionEnergy: frame.motionEnergy,
            timestamp: frame.timestamp
        )
        graphs[frame.source] = graph

        for event in events {
            // Stamp the provenance of the FRAME these events were derived from (#186).
            // `BioEventGraph` is protected and sees only channel values, so this is the
            // first point in the chain that knows where they came from — and the OSC
            // drain downstream refuses to send anything unstamped.
            bus.publish(bioEvent: event.stamped(source: frame.source))
            eventsPublished &+= 1
            lastEventTimestamp = event.timestamp
        }
    }
}
