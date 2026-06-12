// GenreFXTests.swift
// Echoel — guards the per-genre effect presets. Every genre must define a sane,
// in-range effect space, and applying a preset must configure the chain — with
// the delay time resolved as a real, BPM-locked musical division.

import XCTest
@testable import Echoelmusic

final class GenreFXTests: XCTestCase {

    func testEveryStyleHasADelaySpace() {
        // The whole point of the preset is the genre's signature space; every
        // genre currently leads with a tempo-synced delay.
        for style in MusicStyle.allCases {
            XCTAssertTrue(style.fxPreset.delayEnabled, "\(style) should define a delay space")
        }
    }

    func testPresetParamsAreInRange() {
        for style in MusicStyle.allCases {
            let fx = style.fxPreset
            for (label, v) in [("delayMix", fx.delayMix), ("delayFeedback", fx.delayFeedback),
                               ("delayTone", fx.delayTone), ("delaySpread", fx.delaySpread),
                               ("delayWow", fx.delayWow), ("delayDrive", fx.delayDrive),
                               ("chorusDepth", fx.chorusDepth), ("chorusMix", fx.chorusMix),
                               ("phaserDepth", fx.phaserDepth), ("phaserMix", fx.phaserMix)] {
                XCTAssertTrue((0...1).contains(v), "\(style).\(label) = \(v) out of 0...1")
            }
            // Feedback must stay below self-oscillation.
            XCTAssertLessThan(fx.delayFeedback, 0.95, "\(style) delay feedback must be stable")
            // Modulation rates within the chorus/phaser LFO window [0.05, 8].
            XCTAssertTrue((0.05...8).contains(fx.chorusRate), "\(style) chorusRate")
            XCTAssertTrue((0.05...8).contains(fx.phaserRate), "\(style) phaserRate")
        }
    }

    func testGenresHaveDistinctSpaces() {
        // Dub's long swung ping-pong must not equal trap's short dry slap, etc.
        // Count distinct presets without requiring Hashable (Equatable only).
        var distinct: [GenreFXPreset] = []
        for style in MusicStyle.allCases where !distinct.contains(style.fxPreset) {
            distinct.append(style.fxPreset)
        }
        XCTAssertGreaterThan(distinct.count, 1, "genres must not all share one effect space")
        XCTAssertNotEqual(MusicStyle.dubTechno.fxPreset, MusicStyle.trap.fxPreset)
    }

    func testApplyResolvesDelayTimeToBPM() {
        // A dotted-quarter at 120 BPM = 0.75 s. The dub preset uses dotted quarter,
        // so applying at 120 must land the chain's delay time there.
        let chain = EchoelFXChain()
        let expected = TempoSyncOption(.quarter, .dotted).seconds(bpm: 120)
        MusicStyle.dubTechno.fxPreset.apply(to: chain, bpm: 120)
        XCTAssertTrue(chain.delayEnabled)
        XCTAssertEqual(Double(chain.delay.timeSeconds), expected, accuracy: 0.001)
        XCTAssertEqual(chain.delay.mode, .pingPong)
    }

    func testApplyClampsLongDelayToBuffer() {
        // A half-note at a very slow tempo exceeds the 2 s delay buffer and must
        // be clamped, never overrun.
        let chain = EchoelFXChain()
        MusicStyle.sciFi.fxPreset.apply(to: chain, bpm: 40) // half note = 3 s → clamp
        XCTAssertLessThanOrEqual(chain.delay.timeSeconds, 2.0)
        XCTAssertGreaterThan(chain.delay.timeSeconds, 0)
    }

    func testApplyTogglesChorusAndPhaserPerGenre() {
        let chain = EchoelFXChain()

        // sci-fi: phaser on, chorus off.
        MusicStyle.sciFi.fxPreset.apply(to: chain, bpm: 120)
        XCTAssertTrue(chain.phaserEnabled, "sci-fi should sweep a phaser")
        XCTAssertFalse(chain.chorusEnabled, "sci-fi has no chorus")

        // vaporwave: chorus on, phaser off — and re-applying must flip the stale
        // phaser flag back off (apply is a full state write, not additive).
        MusicStyle.vaporwave.fxPreset.apply(to: chain, bpm: 120)
        XCTAssertTrue(chain.chorusEnabled, "vaporwave should wash a chorus")
        XCTAssertFalse(chain.phaserEnabled, "vaporwave has no phaser; stale flag must clear")
        XCTAssertEqual(chain.delay.mode, .tape, "vaporwave uses tape echo")
    }

    func testLimiterStaysEnabledAfterApply() {
        // The safety brick-wall must never be switched off by a preset.
        let chain = EchoelFXChain()
        MusicStyle.psytrance.fxPreset.apply(to: chain, bpm: 145)
        XCTAssertTrue(chain.limiterEnabled, "the safety limiter must survive a preset")
    }
}
