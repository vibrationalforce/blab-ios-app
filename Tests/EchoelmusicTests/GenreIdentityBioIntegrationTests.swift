#if canImport(Accelerate)
// GenreIdentityBioIntegrationTests.swift
// Echoelmusic — end-to-end regression guard for task #81 ("Genre-Identität überlebt die
// Calm-Konvergenz"). Unit tests already lock the two anchor primitives (bioBaseFilterCutoff
// v333, bioBaseBrightness v334) at the EchoelDDSP level. This test proves the WHOLE chain —
// a real genre SynthPatch → apply(to:) → applyBioReactive under CALM biofeedback — keeps
// every genre timbrally distinct instead of collapsing toward one shared sound.
//
// Why it matters: before v333/v334, applyBioReactive drove filterCutoff toward an ABSOLUTE
// 200+coh·1600 (≤1800 Hz) and brightness toward an ABSOLUTE ~0.43, both patch-independent —
// so with the body calm EVERY genre converged to the same cutoff + brightness. The killer
// assertions here are the CROSS-GENRE SPREAD: under the old bug the spread would be ~0.

import XCTest
@testable import Echoelmusic

final class GenreIdentityBioIntegrationTests: XCTestCase {

    /// Drive a fresh synth through a genre's patch + a long calm-bio settle, return the
    /// bio-active (cutoff, brightness) the render would actually use.
    private func settledTimbre(for style: MusicStyle) -> (cutoff: Float, brightness: Float) {
        let synth = EchoelDDSP()
        style.synthPatch.apply(to: synth)
        // Calm body: high coherence, neutral HR/HRV — the exact regime where the old
        // absolute code collapsed every genre together.
        for _ in 0..<600 {
            synth.applyBioReactive(coherence: 0.9, hrvVariability: 0.5, heartRate: 0.5)
        }
        return (synth.filterCutoff, synth.brightness)
    }

    func testEveryGenreKeepsDistinctTimbreUnderCalmBio() {
        let timbres = MusicStyle.allCases.map { settledTimbre(for: $0) }
        XCTAssertGreaterThan(timbres.count, 5, "expected the full genre set")

        let cutoffs = timbres.map { $0.cutoff }
        let brights = timbres.map { $0.brightness }

        // CROSS-GENRE SPREAD survives the calm-bio path (the old absolute code would flatten
        // both of these to ~0). The thresholds are well inside the real patch spread
        // (cutoffs ~800–6500 Hz, brightness ~0.1–0.75) yet far above the old converged ~0.
        let cutoffSpread = (cutoffs.max() ?? 0) - (cutoffs.min() ?? 0)
        let brightSpread = (brights.max() ?? 0) - (brights.min() ?? 0)
        // Thresholds are far above the old converged ~0 yet comfortably below the real spread
        // (e.g. doom cutoff 1400→~1680 vs futuristic 3200→~3840 alone spans ~2160 Hz; brightness
        // ~0.32 vs ~0.63). Conservative bounds so the guard is meaningful but never flaky.
        XCTAssertGreaterThan(cutoffSpread, 800,
            "Genre filter cutoffs collapsed toward one value under calm bio (spread \(cutoffSpread) Hz)")
        XCTAssertGreaterThan(brightSpread, 0.22,
            "Genre brightness collapsed toward one value under calm bio (spread \(brightSpread))")
    }

    func testBrightAndDarkGenresStayOrderedUnderCalmBio() {
        // A deliberately bright genre must stay clearly brighter/more-open than a deliberately
        // dark one after the calm-bio settle — ordering the old absolute code destroyed.
        let bright = settledTimbre(for: .futuristic)   // patch cutoff 3200, brightness ~0.51
        let dark   = settledTimbre(for: .doom)         // patch cutoff 1400, brightness ~0.32
        XCTAssertGreaterThan(bright.cutoff, dark.cutoff + 500,
            "bright genre lost its open filter relative to the dark genre under calm bio")
        XCTAssertGreaterThan(bright.brightness, dark.brightness + 0.15,
            "bright genre lost its spectral brightness relative to the dark genre under calm bio")
    }
}

#endif
