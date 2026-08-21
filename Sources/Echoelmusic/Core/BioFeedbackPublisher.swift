//
//  BioFeedbackPublisher.swift
//  Echoelmusic — Core (app side)
//
//  App-side producer for the BioFeedbackManager bridge. Publishes EngineBus's
//  latest USABLE bio frame into the App Group so the AUv3 extension (live
//  bio params in third-party hosts), the Widget, and the Watch app can read it.
//
//  App-Group-Puls-Brücke (2026-07-17): this type owns NO timer. It is driven
//  by the app's ONE existing 10 Hz control-plane tick
//  (BioReactiveSynthVoice.onPollTick, wired in EchoelmusicApp) via
//  `publishTick()` — the "no new timer, no per-frame MainActor hop" law.
//  Writes are deduped per frame timestamp, so the actual write rate is
//  min(source frame rate, 10 Hz).
//
//  Lives in its own file (separate from BioFeedbackManager) because it depends
//  on EngineBus + BioEgressPolicy — types the AUv3 target does NOT compile.
//  The AUv3/Widget/Watch include only the Foundation-only BioFeedbackManager.
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
    @ObservationIgnored private var isPublishing = false
    @ObservationIgnored private var lastPublishedTimestamp: TimeInterval = -1
    // Throttle widget reloads — WidgetKit budgets refreshes, so nudge at most
    // once every 10 s even though vitals publish at up to 10 Hz.
    @ObservationIgnored private var lastWidgetReload: Date = .distantPast

    public init(manager: BioFeedbackManager = BioFeedbackManager()) {
        self.manager = manager
    }

    /// Arm publishing from `bus`. Idempotent; actual writes happen on the
    /// shared 10 Hz tick via `publishTick()`.
    ///
    /// Publishing stays armed in the BACKGROUND (2026-07-17): the bridge's
    /// headline scenario is a third-party host (GarageBand/AUM) in the
    /// foreground with Echoel backgrounded but still measuring via the
    /// audio / bluetooth-central background modes. While the process is
    /// suspended no tick fires, so an armed-but-suspended publisher costs
    /// nothing.
    public func start(publishingFrom bus: EngineBus) {
        self.bus = bus
        isPublishing = true
    }

    /// Disarm (kept for future lifecycle needs; nothing calls it since the
    /// background-stop was removed for the AUv3 bridge — see `start`).
    public func stop() { isPublishing = false }

    /// Called from the app's existing 10 Hz poll tick. Publishes the bus's
    /// freshest USABLE frame (per-source freshness window — the same values
    /// `usableBio()` hands the composer; a dropped sensor publishes nothing,
    /// so the extension's own ~2 s gate then lets the host params rest).
    /// Per-frame timestamp dedupe ⇒ never rewrites an unchanged frame.
    public func publishTick() {
        guard isPublishing,
              let frame = bus?.usableBio(),
              frame.timestamp != lastPublishedTimestamp else { return }
        lastPublishedTimestamp = frame.timestamp
        manager.publish(Self.vitals(from: frame))
        reloadWidgetsIfDue()
    }

    /// Pure frame→payload mapping (unit-tested). 5.1.3: only Echoel's OWN measurements
    /// (camera rPPG / BLE strap / demo) are marked `egressAllowed` — the exact
    /// `BioEgressPolicy` rule the OSC/ADM-OSC senders apply. HealthKit-store frames
    /// still reach the App Group for the first-party Widget/Watch.
    ///
    /// ⛔ THIS PARAGRAPH JUSTIFIED THE GATE IN THE PRESENT TENSE WITH A TARGET THAT IS GONE
    /// (#632b). It said "the AUv3 pushes these values into HOST-VISIBLE AUParameters … the
    /// AUv3 refuses them (see EchoelmusicAudioUnit.pullSharedVitals)". `project.yml` records
    /// the AUv3 removal at 2026-07-24 and declares five targets, none of them an audio unit;
    /// `git grep -n "pullSharedVitals" -- Sources` returns TWO COMMENTS AND NO CODE — this
    /// one and `Core/BioModulationMap.swift`.
    ///
    /// ⭐ THE GATE STAYS, and its reason is now the one that still exists: `BioEgressPolicy` is
    /// ONE policy shared with the OSC/ADM-OSC senders (#416), and those senders ship. Keeping
    /// the flag correct here is what lets a future host-visible surface — an AUv3 rebuilt, a
    /// remote peer — inherit the rule instead of re-deriving it. A dead REASON does not make a
    /// live RULE dead; it makes the rule look conditional on something a reader cannot find.
    public nonisolated static func vitals(from frame: BioSampleFrame) -> BioVitals {
        BioVitals(
            heartRateBPM: frame.heartRateBPM,
            hrvNormalized: frame.hrvNormalized,
            breathPhase: frame.breathPhase,
            coherence: frame.coherence,
            timestamp: frame.timestamp,
            breathRate: frame.breathRate,
            egressAllowed: BioEgressPolicy.allowsEgress(frame.source),
            // The fourth chamber of the #627 law: the Widget and the Watch print these
            // numbers as a body. `.fallback` IS egress-allowed (it is nobody's pulse, so
            // it cannot leak one) — which is exactly why the provenance has to travel
            // SEPARATELY: `egressAllowed == true` says "safe to show", never "measured".
            synthetic: frame.source.isSynthetic
        )
    }

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
