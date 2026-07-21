// FXCharacterTests.swift
// Echoel — the production effect-character palette (Underwater, Telephone, …)
// used when making loops/samples/tracks. Guards the flagship Underwater colour,
// the Auto→genre fallback, filter-stage wiring, and per-character distinctness.

import XCTest
@testable import Echoelmusic

final class FXCharacterTests: XCTestCase {

    func testAutoHasNoPresetAndFallsBackToGenre() {
        XCTAssertNil(FXCharacter.auto.preset, "Auto must defer to the genre preset")

        let chain = EchoelFXChain()
        FXCharacter.auto.apply(to: chain, bpm: 124, genre: .dubTechno)
        // Dub's signature is a ping-pong delay — proves the genre preset was used.
        XCTAssertTrue(chain.delayEnabled)
        XCTAssertEqual(chain.delay.mode, .pingPong)
        XCTAssertFalse(chain.filterEnabled, "dub genre preset does not filter")
    }

    func testUnderwaterIsADeepLowPass() {
        guard let p = FXCharacter.underwater.preset else { return XCTFail("underwater needs a preset") }
        XCTAssertTrue(p.filterEnabled)
        XCTAssertEqual(p.filterMode, .lowpass)
        XCTAssertLessThanOrEqual(p.filterCutoff, 1000, "underwater must be muffled")
        XCTAssertTrue(p.delayEnabled, "underwater has a watery tape delay")
        XCTAssertEqual(p.delayMode, .tape)
        XCTAssertGreaterThan(p.delayWow, 0, "tape wobble is part of the character")
        XCTAssertTrue(p.chorusEnabled, "watery chorus movement")
    }

    func testUnderwaterAppliesToChain() {
        let chain = EchoelFXChain()
        FXCharacter.underwater.apply(to: chain, bpm: 90, genre: .selfObservation)
        XCTAssertTrue(chain.filterEnabled)
        XCTAssertEqual(chain.filterL.mode, .lowpass)
        XCTAssertEqual(chain.filterR.mode, .lowpass)
        XCTAssertEqual(chain.filterL.cutoff, chain.filterR.cutoff, "both channels matched")
        XCTAssertLessThanOrEqual(chain.filterL.cutoff, 1000)
        XCTAssertTrue(chain.limiterEnabled, "safety limiter survives the character")
    }

    func testTelephoneAndMegaphoneAreBandPass() {
        for c in [FXCharacter.telephone, .megaphone] {
            guard let p = c.preset else { return XCTFail("\(c) needs a preset") }
            XCTAssertTrue(p.filterEnabled, "\(c) is a filtered character")
            XCTAssertEqual(p.filterMode, .bandpass, "\(c) is band-limited")
        }
    }

    func testApplyingACharacterClearsAStaleFilter() {
        let chain = EchoelFXChain()
        // Underwater turns the filter ON…
        FXCharacter.underwater.apply(to: chain, bpm: 120, genre: .dubTechno)
        XCTAssertTrue(chain.filterEnabled)
        // …Dream has no filter, so re-applying must clear the stale flag.
        FXCharacter.dream.apply(to: chain, bpm: 120, genre: .dubTechno)
        XCTAssertFalse(chain.filterEnabled, "apply is a full state write, not additive")
    }

    func testEveryCharacterPresetIsInRange() {
        for c in FXCharacter.allCases {
            guard let p = c.preset else { continue }
            XCTAssertTrue((20...20_000).contains(p.filterCutoff), "\(c) cutoff")
            XCTAssertTrue((0...1).contains(p.filterResonance), "\(c) resonance")
            XCTAssertLessThan(p.delayFeedback, 0.95, "\(c) delay stability")
            for (label, v) in [("delayMix", p.delayMix), ("chorusMix", p.chorusMix),
                               ("delayDrive", p.delayDrive), ("delayWow", p.delayWow)] {
                XCTAssertTrue((0...1).contains(v), "\(c).\(label)")
            }
        }
    }

    func testCharactersAreDistinct() {
        var seen: [GenreFXPreset] = []
        for c in FXCharacter.allCases {
            guard let p = c.preset else { continue }
            XCTAssertFalse(seen.contains(p), "\(c) must be a distinct colour")
            seen.append(p)
        }
        XCTAssertGreaterThanOrEqual(seen.count, 5)
    }

    func testCleanResetsAStampedChainToDry() {
        let chain = EchoelFXChain()
        // Stamp Underwater (filter + delay + chorus all ON)…
        FXCharacter.underwater.apply(to: chain, bpm: 120, genre: .dubTechno)
        XCTAssertTrue(chain.filterEnabled && chain.delayEnabled && chain.chorusEnabled)
        // …then Clean must switch every effect off, keeping only the safety limiter.
        FXCharacter.clean.apply(to: chain, bpm: 120, genre: .dubTechno)
        XCTAssertFalse(chain.filterEnabled)
        XCTAssertFalse(chain.delayEnabled)
        XCTAssertFalse(chain.chorusEnabled)
        XCTAssertFalse(chain.phaserEnabled)
        XCTAssertFalse(chain.saturationEnabled, "Clean is truly dry — no warmth drive either")
        XCTAssertTrue(chain.limiterEnabled, "the safety limiter is never disabled by a character")
    }

    func testEveryCharacterHasNameAndBlurb() {
        for c in FXCharacter.allCases {
            XCTAssertFalse(c.displayName.isEmpty, "\(c) name")
            XCTAssertFalse(c.blurb.isEmpty, "\(c) blurb")
        }
    }
}

final class FXChainFilterStageTests: XCTestCase {

    func testFilterDefaultsBypassed() {
        let chain = EchoelFXChain()
        XCTAssertFalse(chain.filterEnabled, "filter must be off by default (no surprise muffling)")
    }

    func testSetFilterMatchesBothChannels() {
        let chain = EchoelFXChain()
        chain.setFilter(mode: .bandpass, cutoff: 1200, resonance: 0.5)
        XCTAssertEqual(chain.filterL.mode, .bandpass)
        XCTAssertEqual(chain.filterR.mode, .bandpass)
        XCTAssertEqual(chain.filterL.cutoff, 1200)
        XCTAssertEqual(chain.filterR.cutoff, 1200)
        XCTAssertEqual(chain.filterL.resonance, 0.5)
        XCTAssertEqual(chain.filterR.resonance, 0.5)
    }

    func testBypassedFilterIsTransparent() {
        // With the filter (and every other stage) off, output equals input.
        let chain = EchoelFXChain()
        chain.saturationEnabled = false
        chain.limiterEnabled = false
        chain.chorusEnabled = false   // chorus defaults ON — disable for true transparency
        let (l, r) = chain.processStereo(0.5, -0.3)
        XCTAssertEqual(l, 0.5, accuracy: 1e-6)
        XCTAssertEqual(r, -0.3, accuracy: 1e-6)
    }

    func testEnabledLowPassAttenuatesNothingAtDC() {
        // A low-pass passes DC (0 Hz) at unity — sanity that the stage is wired
        // and stable, not silent.
        let chain = EchoelFXChain()
        chain.saturationEnabled = false
        chain.limiterEnabled = false
        chain.filterEnabled = true
        chain.setFilter(mode: .lowpass, cutoff: 800, resonance: 0.2)
        var out: Float = 0
        for _ in 0..<2000 { (out, _) = chain.processStereo(1.0, 1.0) } // settle to DC
        XCTAssertEqual(out, 1.0, accuracy: 0.05, "low-pass passes DC near unity")
        XCTAssertFalse(out.isNaN, "filter must stay stable")
    }
}
