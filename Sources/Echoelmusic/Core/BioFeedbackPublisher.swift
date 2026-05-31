//
//  BioFeedbackPublisher.swift
//  Echoelmusic — Core (app side)
//
//  App-side producer for the BioFeedbackManager bridge. Polls EngineBus's
//  latest bio frame OFF the audio thread (~1 Hz on the main actor) and
//  publishes it into the App Group so the AUv3 extension can read it.
//  Lives in its own file (separate from BioFeedbackManager) because it depends
//  on EngineBus + PollingLoop — types the AUv3 target does NOT compile. The
//  AUv3 includes only the Foundation-only BioFeedbackManager.
//

import Foundation
#if canImport(Observation)
import Observation

@MainActor
@Observable
public final class BioFeedbackPublisher {

    @ObservationIgnored public let manager: BioFeedbackManager
    @ObservationIgnored private weak var bus: EngineBus?
    @ObservationIgnored private let loop = PollingLoop()

    public init(manager: BioFeedbackManager = BioFeedbackManager()) {
        self.manager = manager
    }

    public func start(publishingFrom bus: EngineBus) {
        self.bus = bus
        loop.start(interval: .seconds(1)) { [weak self] in
            guard let self, let frame = self.bus?.latestBio else { return }
            self.manager.publish(BioVitals(
                heartRateBPM: frame.heartRateBPM,
                hrvNormalized: frame.hrvNormalized,
                breathPhase: frame.breathPhase,
                coherence: frame.coherence,
                timestamp: frame.timestamp
            ))
        }
    }

    public func stop() { loop.stop() }
}
#endif
