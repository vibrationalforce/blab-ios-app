//
//  BioEgressPolicy.swift
//  Echoelmusic — Sync
//
//  Pure, testable rule for which bio SOURCES may stream off the device
//  (OSC / ADM-OSC bio frames to user-chosen network targets).
//
//  App Store Guideline 5.1.3: data obtained from the HealthKit store may not be
//  shared with third parties — and once a UDP packet leaves the phone to a
//  user-typed host, we can no longer vouch for where it lands. So the network
//  senders forward ONLY Echoel's OWN measurements (camera rPPG, BLE strap,
//  front-camera face expression, the demo generator) and never frames sourced from
//  Apple Health / Watch / ring bridges. For face expression only the abstracted
//  [0..1] channels egress — never the image. Mirrors the non-circular pattern of
//  `HealthWritePolicy.isWritableSource`
//  (which gates the opposite direction: what we write INTO Health).
//
//  DISCRETE EVENTS ARE GATED TOO (#186, 2026-07-27) — and the honest reason is narrower
//  than the first version of this note claimed, so it is spelled out rather than asserted.
//  This header used to say events "need no gate today". The STRUCTURE that claim rested on
//  was wrong: `BioEventPublisher.tick` reads `bus.latestBio` regardless of source and feeds
//  `frame.breathPhase` / `frame.motionEnergy` into a graph whose detector state is shared
//  across sources. But the DATA today is not Health-store data:
//    · `motionEnergy` is hardcoded `0` on the HealthKit frame → a motion peak (needs ≥0.6)
//      can never fire from that source.
//    · `breathPhase` is a constant `0.5` there — its only writer in `EchoelBioEngine` sits
//      inside `startFallbackMode()`, which is mutually exclusive with the HealthKit path.
//      Inhale needs `previous < 0.5`, exhale needs `previous > 0.8`; neither can trigger.
//    · `breathRate` IS real Health-store data, but the graph is never fed it.
//    · `cleanedHeart` is passed as `0`, so graph heartbeats do not fire at all.
//  So no Health-store VALUE has actually left the device through this path. What could:
//  the shared `BreathPhaseDetector.previous` is not reset when the source changes, so a
//  camera session leaving it at e.g. 0.3 followed by a HealthKit frame at 0.5 fires one
//  inhale event — a cross-source state artifact, carrying a placeholder, ungated.
//  The gate is therefore DEFENCE-IN-DEPTH plus that one artifact: it costs nothing, and it
//  means a future publisher that carries real Health-derived channels into the graph is
//  covered on arrival instead of needing someone to remember this file.
//  Do not re-introduce an "events are exempt" claim; equally, do not overstate it as an
//  active leak — both errors have now been made in this exact paragraph.
//

import Foundation

public enum BioEgressPolicy {

    /// Whether frames from this source may be sent off-device. Only sources
    /// Echoel measures itself (or synthesizes, for the demo) pass; anything
    /// read out of the HealthKit store stays on the device (5.1.3).
    public static func allowsEgress(_ source: BioSource) -> Bool {
        switch source {
        case .ble, .cameraPPG, .faceCam, .fallback:
            // faceCam is measured on-device like rPPG; only the abstracted [0..1]
            // expression channels egress (never the image), same principle as PPG.
            return true
        case .healthKit, .watch, .oura:
            return false
        }
    }

    /// Whether this discrete event may be sent off-device (#186).
    ///
    /// It lives HERE, not inline in `OSCSender`, for a reason found by review: the first
    /// cut inlined the guard and the test re-implemented it, so the test passed even with
    /// the production guard deleted — a tautology wearing a regression test's clothes.
    /// One symbol, called by both.
    ///
    /// An UNSTAMPED event (`source == nil`) is refused. `BioEventGraph` is a protected
    /// component that cannot know provenance, so its events arrive unstamped and are
    /// stamped by whoever publishes them; failing closed means a producer that forgets
    /// goes silent rather than leaking.
    public static func allowsEgress(_ event: BioEvent) -> Bool {
        guard let source = event.source else { return false }
        return allowsEgress(source)
    }
}
