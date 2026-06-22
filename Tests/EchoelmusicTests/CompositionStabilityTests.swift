// CompositionStabilityTests.swift
// Echoel — completeness & stability sweep across the WHOLE musical space, the
// founder's "alle Tonarten, Tonsysteme … Vollständigkeit, Stabilität" requirement.
// Pure (no clock/audio): exhaustively composes every genre × scale × root × a few
// bio states and asserts the hard invariants hold everywhere (valid + in-key +
// in-bar + deterministic), and that every tone system yields a finite retune table
// for every root. A crash or out-of-range note anywhere fails the build.

import XCTest
@testable import Echoelmusic

final class CompositionStabilityTests: XCTestCase {

    private func input(coherence: Float, hr: Float, key: MusicalKey,
                       style: MusicStyle, mode: ComposerMode, seed: UInt64) -> BioComposer.Input {
        BioComposer.Input(heartRateBPM: hr, hrvNormalized: 0.5, coherence: coherence,
                          breathPhase: 0.25, breathDepth: 0.6, key: key,
                          style: style, mode: mode, lockedTempo: 120, seed: seed)
    }

    private func assertValid(_ comp: BioComposition, key: MusicalKey,
                             style: MusicStyle, file: StaticString = #filePath, line: UInt = #line) {
        // Drum grid is always a well-formed 8×16 (even ambient, which is all-false).
        XCTAssertEqual(comp.drumSteps.count, 8, "drum tracks", file: file, line: line)
        XCTAssertEqual(comp.drumAccents.count, 8, "accent tracks", file: file, line: line)
        XCTAssertTrue(comp.drumSteps.allSatisfy { $0.count == 16 }, "16 steps", file: file, line: line)
        XCTAssertTrue(comp.drumAccents.allSatisfy { $0.count == 16 }, "16 accents", file: file, line: line)
        XCTAssertTrue(comp.suggestedTempo.isFinite && comp.suggestedTempo > 0, "tempo>0", file: file, line: line)

        for n in comp.notes {
            XCTAssertTrue((0...127).contains(n.pitch), "MIDI range", file: file, line: line)
            XCTAssertGreaterThanOrEqual(n.startStep, 0, "startStep≥0", file: file, line: line)
            XCTAssertLessThan(n.startStep, 16, "startStep<16", file: file, line: line)
            XCTAssertGreaterThanOrEqual(n.lengthSteps, 1, "len≥1", file: file, line: line)
            XCTAssertLessThanOrEqual(n.startStep + n.lengthSteps, 16, "stays in bar", file: file, line: line)
            XCTAssertTrue((0...1).contains(n.velocity) && n.velocity.isFinite, "vel∈[0,1]", file: file, line: line)
            XCTAssertTrue(key.contains(n.pitch), "every note in key", file: file, line: line)
        }
    }

    /// Every genre × scale × root × bio state × mode composes to valid, in-key,
    /// in-bar, deterministic music. ~10k takes; pure so it runs fast.
    func testEveryGenreScaleRootIsStableAndInKey() {
        let bioStates: [(coh: Float, hr: Float)] = [(0.05, 115), (0.95, 55)]   // aroused vs settled
        for style in MusicStyle.allCases {
            for scale in Scale.allCases {
                for root in 0..<12 {
                    let key = MusicalKey(root: root, scale: scale)
                    for (coh, hr) in bioStates {
                        for mode in [ComposerMode.studioLocked, .flowFree] {
                            let inp = input(coherence: coh, hr: hr, key: key,
                                            style: style, mode: mode, seed: 0xA11CE)
                            let a = BioComposer.compose(inp)
                            assertValid(a, key: key, style: style)
                            // Determinism: identical inputs + seed → identical output.
                            XCTAssertEqual(a, BioComposer.compose(inp),
                                           "\(style)/\(scale)/root \(root) must be deterministic")
                        }
                    }
                }
            }
        }
    }

    /// Beat genres always carry drums; ambient self-observation never does — across
    /// the whole key space.
    func testBeatVsAmbientDrumContractHoldsEverywhere() {
        for style in MusicStyle.allCases {
            for root in 0..<12 {
                let comp = BioComposer.compose(
                    input(coherence: 0.5, hr: 80, key: MusicalKey(root: root, scale: .minor),
                          style: style, mode: .studioLocked, seed: 7))
                XCTAssertEqual(comp.hasDrums, style.isBeatDriven,
                               "\(style) drum presence must match isBeatDriven")
            }
        }
    }

    // MARK: - Tone systems

    /// Every tone system yields a finite 12-entry retune table for every root, and
    /// 12-TET is a true no-op (all ~0) — the "all tone systems, complete + stable" bar.
    func testEveryToneSystemRetunesEveryRootFinitely() {
        for system in TuningSystem.library {
            for root in 0..<12 {
                let cents = system.pitchClassCents(root: root)
                XCTAssertEqual(cents.count, 12, "\(system.name): 12 pitch classes")
                for c in cents {
                    XCTAssertTrue(c.isFinite, "\(system.name) root \(root): finite cents")
                    XCTAssertLessThanOrEqual(abs(c), 1300, "\(system.name): sane cent magnitude")
                }
            }
        }
    }

    func testTwelveTETIsExactlyNeutral() {
        let edo12 = TuningSystem.named("edo12")
        for root in 0..<12 {
            for c in edo12.pitchClassCents(root: root) {
                XCTAssertEqual(c, 0, accuracy: 1e-6, "12-TET must not retune anything")
            }
        }
    }
}
