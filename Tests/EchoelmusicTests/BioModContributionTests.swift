// BioModContributionTests.swift
// Item 2 — "Bio-Modulation live sichtbar", data layer (cycle 2a).
// The PURE builder that turns the enabled FX modulation routes + the current bio
// frame into the per-route live contributions a leaf view will show ("your breath
// is at 0.7, pushing Filter Cutoff +4200 Hz"). Deterministic → tested without the
// 30 Hz driver or any UI. Also the publish-throttle predicate (10 Hz out of 30 Hz)
// that keeps the observation load low (menu-freeze law).

import XCTest
import Foundation
@testable import Echoelmusic

final class BioModContributionTests: XCTestCase {

    private func frame(coherence: Float = 0, breathPhase: Float = 0,
                       heartRate: Float = 60) -> BioSampleFrame {
        BioSampleFrame(timestamp: 0, heartRateBPM: heartRate, hrvNormalized: 0,
                       breathRate: 12, breathPhase: breathPhase, coherence: coherence,
                       motionEnergy: 0, source: .cameraPPG)
    }

    func testContribution_bioRoute_signalAndOffset() {
        // Coherence 0.6 → Reverb Mix, unipolar depth 0.5, linear curve.
        // signal01 = raw normalized coherence = 0.6 (range 0…1).
        // offset = signal·depth·span = 0.6·0.5·1 = 0.30.
        let route = FXModRoute(carrier: .bio(.coherence), target: .reverbMix,
                               depth: 0.5, bipolar: false)
        let out = FXModulation.contributions(routes: [route], frame: frame(coherence: 0.6), now: 0)
        XCTAssertEqual(out.count, 1)
        let c = out[0]
        XCTAssertEqual(c.id, route.id)
        XCTAssertEqual(c.carrierName, "Coherence")
        XCTAssertEqual(c.targetName, "Reverb Mix")
        XCTAssertEqual(c.signal01, 0.6, accuracy: 1e-5)
        XCTAssertEqual(c.offset, 0.30, accuracy: 1e-5)
    }

    func testContribution_disabledRoute_excluded() {
        let on  = FXModRoute(carrier: .bio(.coherence), target: .reverbMix, enabled: true)
        let off = FXModRoute(carrier: .bio(.breathPhase), target: .filterCutoff, enabled: false)
        let out = FXModulation.contributions(routes: [on, off], frame: frame(coherence: 0.5), now: 0)
        XCTAssertEqual(out.map(\.id), [on.id])   // only the enabled route appears
    }

    func testContribution_bioRoute_noFrame_presentButZero() {
        // No body yet: the route still appears (so the row reads "waiting"), at zero.
        let route = FXModRoute(carrier: .bio(.coherence), target: .reverbMix,
                               depth: 0.5, bipolar: false)
        let out = FXModulation.contributions(routes: [route], frame: nil, now: 0)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].signal01, 0, accuracy: 1e-6)
        XCTAssertEqual(out[0].offset, 0, accuracy: 1e-6)
    }

    func testContribution_bioRoute_noFrame_BIPOLAR_alsoReportsZero() {
        // The unipolar case above passed even when the frameless offset was computed
        // from signal 0 (0·depth·span == 0), which is why this went unnoticed. BIPOLAR
        // is the one that broke: (0·2−1)·depth·span·0.5 is a FULL NEGATIVE excursion,
        // so the panel showed a large negative contribution — e.g. −4480 Hz on a
        // coherence→filterCutoff route — for a route contributing nothing at all.
        // The driver SKIPS a bio route with no frame (`guard let frame else { continue }`
        // in FXBioModulator), leaving the base value, so the readout was contradicting
        // the very engine it exists to report on.
        let route = FXModRoute(carrier: .bio(.coherence), target: .filterCutoff,
                               depth: 0.5, bipolar: true)
        let out = FXModulation.contributions(routes: [route], frame: nil, now: 0)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].signal01, 0, accuracy: 1e-6)
        XCTAssertEqual(out[0].offset, 0, accuracy: 1e-6,
                       "a route the driver skips must report zero, whatever its polarity")
    }

    func testContribution_bipolarWithAFrame_isNotFlattened() {
        // Guard against over-correcting: with a frame present the bipolar formula must
        // still run, so a below-midpoint signal reads negative. (This one passes both
        // before and after the fix — it is a regression fence, not a falsifier.)
        let route = FXModRoute(carrier: .bio(.coherence), target: .reverbMix,
                               depth: 1, bipolar: true)
        XCTAssertEqual(FXModulation.contributions(routes: [route],
                                                  frame: frame(coherence: 0), now: 0)[0].offset,
                       -0.5, accuracy: 1e-5)
        XCTAssertEqual(FXModulation.contributions(routes: [route],
                                                  frame: frame(coherence: 1), now: 0)[0].offset,
                       0.5, accuracy: 1e-5)
    }

    func testContribution_lfoRoute_usesPhaseNotFrame() {
        // LFO at 1 Hz, now = 0 → phase 0 → unipolar 0.5. Independent of the (nil) frame.
        let route = FXModRoute(carrier: .lfo, target: .tremoloDepth,
                               depth: 1, bipolar: false, lfoRateHz: 1)
        let out = FXModulation.contributions(routes: [route], frame: nil, now: 0)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].carrierName, "LFO")
        XCTAssertEqual(out[0].signal01, 0.5, accuracy: 1e-5)
    }

    func testContributions_preserveRouteOrder() {
        let a = FXModRoute(carrier: .bio(.heartRate), target: .filterCutoff)
        let b = FXModRoute(carrier: .bio(.breathPhase), target: .reverbMix)
        let out = FXModulation.contributions(routes: [a, b], frame: frame(), now: 0)
        XCTAssertEqual(out.map(\.id), [a.id, b.id])
    }

    func testShouldPublish_throttle() {
        // 30 Hz tick, everyN = 3 → publish on ticks 3,6,9… (≈10 Hz), skip between.
        XCTAssertTrue(FXModulation.shouldPublish(tick: 3, everyN: 3))
        XCTAssertTrue(FXModulation.shouldPublish(tick: 6, everyN: 3))
        XCTAssertFalse(FXModulation.shouldPublish(tick: 4, everyN: 3))
        XCTAssertFalse(FXModulation.shouldPublish(tick: 5, everyN: 3))
        XCTAssertFalse(FXModulation.shouldPublish(tick: 10, everyN: 0))   // guard: no div-by-zero
    }
}
