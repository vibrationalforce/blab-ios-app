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
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
@Observable
public final class BioFeedbackPublisher {

    @ObservationIgnored public let manager: BioFeedbackManager
    @ObservationIgnored private weak var bus: EngineBus?
    @ObservationIgnored private let loop = PollingLoop()
    // Throttle widget reloads — WidgetKit budgets refreshes, so nudge at most
    // once every 10 s even though we publish vitals at ~1 Hz.
    @ObservationIgnored private var lastWidgetReload: Date = .distantPast

    public init(manager: BioFeedbackManager = BioFeedbackManager()) {
        self.manager = manager
    }

    public func start(publishingFrom bus: EngineBus) {
        self.bus = bus
        loop.start(interval: .seconds(1)) { [weak self] in
            // Only forward FRESH vitals to the widget/AUv3 — don't keep pushing a
            // frozen frame to the lock-screen glance after the source has dropped.
            guard let self, let frame = self.bus?.freshBio() else { return }
            self.manager.publish(BioVitals(
                heartRateBPM: frame.heartRateBPM,
                hrvNormalized: frame.hrvNormalized,
                breathPhase: frame.breathPhase,
                coherence: frame.coherence,
                timestamp: frame.timestamp
            ))
            self.reloadWidgetsIfDue()
        }
    }

    public func stop() { loop.stop() }

    /// Nudge WidgetKit to refresh the bio glance, no more than once per 10 s.
    private func reloadWidgetsIfDue() {
        #if canImport(WidgetKit)
        let now = Date()
        guard now.timeIntervalSince(lastWidgetReload) >= 10 else { return }
        lastWidgetReload = now
        WidgetCenter.shared.reloadTimelines(ofKind: "EchoelBioWidget")
        #endif
    }
}
#endif
