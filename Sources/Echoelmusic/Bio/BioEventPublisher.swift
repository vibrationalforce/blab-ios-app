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

    @ObservationIgnored
    private var graph: BioEventGraph

    @ObservationIgnored
    private var task: Task<Void, Never>?

    @ObservationIgnored
    private var lastFrameTimestamp: TimeInterval = -1

    public init() {
        // Bus poll cadence is 10 Hz; the heartbeat detector's
        // refractory is unused here (no waveform fed), so 10 is fine.
        self.graph = BioEventGraph(sampleRate: 10)
    }

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
    }

    private func tick(_ bus: EngineBus) {
        guard let frame = bus.latestBio else { return }
        guard frame.timestamp != lastFrameTimestamp else { return }
        lastFrameTimestamp = frame.timestamp

        let events = graph.process(
            cleanedHeart: 0,            // raw waveform not on the bus yet
            breathPhase: frame.breathPhase,
            motionEnergy: frame.motionEnergy,
            timestamp: frame.timestamp
        )

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
