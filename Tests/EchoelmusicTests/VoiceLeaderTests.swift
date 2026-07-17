// VoiceLeaderTests.swift
// Echoel — H1 (Harmony-Core, scratchpads/PLAN_HARMONY_CORE.md): the PURE
// voice-leading resolver that picks the inversion/register of a target chord
// with minimal total voice movement. Laws pinned here:
//   • distance minimization (C→F keeps the common tone, moves the rest stepwise)
//   • common-tone preservation (rebate beats an equal-movement restructure)
//   • strictness-1 optimality (the result's cost ≤ every enumerated candidate)
//   • spread monotonicity (ambitus grows weakly with `spread`)
//   • determinism (same inputs + seed ⇒ identical output, no Date/random)
//   • bounds (empty previous / empty chord / 1 voice / 1 pitch class)
//   • register containment (every returned pitch lies inside `register`)

import XCTest
@testable import Echoelmusic

final class VoiceLeaderTests: XCTestCase {

    private let register = 48...84   // C3…C6 — the pad's realistic working range

    // MARK: - Distance minimization (the audible law)

    func testResolve_CtoF_keepsCommonToneAndMovesMinimally() {
        // C major (C4 E4 G4) → F major: classical voice leading keeps C, moves
        // E→F (1 st) and G→A (2 st): [60, 65, 69], NOT a parallel jump to [65,69,72].
        let voiced = VoiceLeader.resolve(from: [60, 64, 67],
                                         to: [65, 69, 72],   // F A C in any octave
                                         register: register,
                                         strictness: 1, spread: 0.5)
        XCTAssertEqual(voiced, [60, 65, 69])
    }

    func testResolve_CtoG_movesToNearestInversion() {
        // C major (C4 E4 G4) → G major: keep G, B and D fall in below: [59, 62, 67].
        let voiced = VoiceLeader.resolve(from: [60, 64, 67],
                                         to: [55, 59, 62],   // G B D
                                         register: register,
                                         strictness: 1, spread: 0.5)
        XCTAssertEqual(voiced, [59, 62, 67])
    }

    func testResolve_sameChordIsIdentity() {
        // Target = the sounding chord ⇒ zero movement beats everything.
        let prev = [60, 64, 67]
        let voiced = VoiceLeader.resolve(from: prev, to: [0, 4, 7],
                                         register: register,
                                         strictness: 1, spread: 0.5)
        XCTAssertEqual(voiced, prev)
    }

    // MARK: - Common-tone preservation

    func testResolve_commonToneResultHasNoHigherCostThanRestructure() {
        // The chosen voicing's cost must beat the "parallel shift" voicing that
        // shares no tones — the rebate makes held tones explicitly cheaper.
        let prev = [60, 64, 67]
        let ranked = VoiceLeader.rankedCandidates(from: prev, to: [5, 9, 0],
                                                  register: register, spread: 0.5)
        guard let best = ranked.first else { return XCTFail("no candidates") }
        XCTAssertTrue(best.voicing.contains(60), "common tone C must be held")
        // Every candidate that holds no common tone costs strictly more.
        for cand in ranked where Set(cand.voicing).isDisjoint(with: prev) {
            XCTAssertGreaterThan(cand.cost, best.cost)
        }
    }

    func testMovementCost_rebatesCommonTones() {
        // Identical total |Δ|, but one side holds a common tone → cheaper.
        let withCommon = VoiceLeader.movementCost(from: [60, 64], to: [60, 66])   // Δ=2, 1 common
        let without = VoiceLeader.movementCost(from: [60, 64], to: [61, 65])      // Δ=2, 0 common
        XCTAssertLessThan(withCommon, without)
    }

    // MARK: - Strictness-1 optimality (property over the small enumeration)

    func testResolve_strictness1_isCostOptimal() {
        let cases: [(prev: [Int], chord: [Int])] = [
            ([60, 64, 67], [5, 9, 0]),        // C → F
            ([60, 64, 67], [7, 11, 2]),       // C → G
            ([57, 60, 65], [0, 3, 7]),        // F → Cm
            ([50, 57, 62, 66], [2, 6, 9, 1]), // D7-ish 4 voices
        ]
        for c in cases {
            let ranked = VoiceLeader.rankedCandidates(from: c.prev, to: c.chord,
                                                      register: register, spread: 0.5)
            let voiced = VoiceLeader.resolve(from: c.prev, to: c.chord,
                                             register: register,
                                             strictness: 1, spread: 0.5)
            guard let best = ranked.first else { return XCTFail("no candidates") }
            XCTAssertEqual(voiced, best.voicing, "strictness 1 must take the ranked optimum")
            for cand in ranked {
                XCTAssertGreaterThanOrEqual(cand.cost, best.cost,
                                            "ranked head must be the global cost minimum")
            }
        }
    }

    // MARK: - Spread (close ↔ open voicing)

    private func ambitus(_ v: [Int]) -> Int { (v.max() ?? 0) - (v.min() ?? 0) }

    func testResolve_spreadGrowsAmbitus() {
        // Empty previous isolates the spread term (no movement cost): the chosen
        // ambitus must grow weakly with spread, strictly across the endpoints.
        let close = VoiceLeader.resolve(from: [], to: [0, 4, 7], register: register,
                                        strictness: 1, spread: 0)
        let mid = VoiceLeader.resolve(from: [], to: [0, 4, 7], register: register,
                                      strictness: 1, spread: 0.5)
        let open = VoiceLeader.resolve(from: [], to: [0, 4, 7], register: register,
                                       strictness: 1, spread: 1)
        XCTAssertLessThanOrEqual(ambitus(close), ambitus(mid))
        XCTAssertLessThanOrEqual(ambitus(mid), ambitus(open))
        XCTAssertLessThan(ambitus(close), ambitus(open))
    }

    func testResolve_spreadZeroFromEmptyIsCompactAndCentered() {
        // "Leeres previous → kompakte Grundlage um die Register-Mitte."
        let voiced = VoiceLeader.resolve(from: [], to: [0, 4, 7], register: register,
                                         strictness: 1, spread: 0)
        XCTAssertEqual(voiced.count, 3)
        XCTAssertLessThanOrEqual(ambitus(voiced), 12, "spread 0 ⇒ close position")
        let mean = Double(voiced.reduce(0, +)) / Double(voiced.count)
        let center = Double(register.lowerBound + register.upperBound) / 2
        XCTAssertLessThanOrEqual(abs(mean - center), 8, "sits around the register centre")
        XCTAssertEqual(Set(voiced.map { $0 % 12 }), [0, 4, 7], "covers every chord tone")
    }

    // MARK: - Determinism (no Date, no SystemRandom)

    func testResolve_isDeterministic() {
        for strictness: Float in [0, 0.4, 1] {
            let a = VoiceLeader.resolve(from: [60, 64, 67], to: [5, 9, 0],
                                        register: register,
                                        strictness: strictness, spread: 0.3, seed: 42)
            let b = VoiceLeader.resolve(from: [60, 64, 67], to: [5, 9, 0],
                                        register: register,
                                        strictness: strictness, spread: 0.3, seed: 42)
            XCTAssertEqual(a, b)
        }
    }

    func testResolve_looseStrictnessStaysAdmissible() {
        // strictness 0 may pick a non-optimal candidate (seed-selected), but the
        // result must still be one of the enumerated chord voicings.
        let ranked = VoiceLeader.rankedCandidates(from: [60, 64, 67], to: [5, 9, 0],
                                                  register: register, spread: 0.5)
        let all = Set(ranked.map { $0.voicing })
        for seed: UInt64 in [0, 1, 7, 99] {
            let voiced = VoiceLeader.resolve(from: [60, 64, 67], to: [5, 9, 0],
                                             register: register,
                                             strictness: 0, spread: 0.5, seed: seed)
            XCTAssertTrue(all.contains(voiced), "loose pick must remain a real chord voicing")
        }
    }

    // MARK: - Bounds

    func testResolve_emptyChordReturnsPreviousClampedToRegister() {
        let voiced = VoiceLeader.resolve(from: [30, 60, 100], to: [],
                                         register: register,
                                         strictness: 1, spread: 0.5)
        XCTAssertEqual(voiced, [48, 60, 84])
    }

    func testResolve_emptyPreviousAndEmptyChordIsEmpty() {
        XCTAssertEqual(VoiceLeader.resolve(from: [], to: [], register: register,
                                           strictness: 1, spread: 0.5), [])
    }

    func testResolve_singleVoiceSinglePitchClass_picksNearestOctave() {
        // One voice on C4 moving to pitch class G: G3 (55, distance 5) beats
        // G4 (67, distance 7).
        let voiced = VoiceLeader.resolve(from: [60], to: [7], register: register,
                                         strictness: 1, spread: 0.5)
        XCTAssertEqual(voiced, [55])
    }

    func testResolve_voiceCountFollowsPrevious() {
        // 4 previous voices onto a triad: 4 voices out, all 3 pitch classes
        // covered (the 4th doubles one at another octave — never a unison).
        let voiced = VoiceLeader.resolve(from: [55, 60, 64, 67], to: [5, 9, 0],
                                         register: register,
                                         strictness: 1, spread: 0.5)
        XCTAssertEqual(voiced.count, 4)
        XCTAssertEqual(Set(voiced.map { $0 % 12 }), [5, 9, 0])
        XCTAssertEqual(Set(voiced).count, 4, "no unison duplicates")
    }

    func testResolve_noOctaveDuplicatesWhenVoicesFitPitchClasses() {
        // 3 voices onto 3 pitch classes ⇒ every pitch class exactly once.
        let voiced = VoiceLeader.resolve(from: [60, 64, 67], to: [5, 9, 0],
                                         register: register,
                                         strictness: 1, spread: 0.5)
        XCTAssertEqual(Set(voiced.map { ($0 % 12 + 12) % 12 }).count, 3)
    }

    // MARK: - Register containment

    func testResolve_allPitchesStayInRegister() {
        let cases: [(prev: [Int], chord: [Int], reg: ClosedRange<Int>)] = [
            ([60, 64, 67], [5, 9, 0], 48...84),
            ([], [0, 4, 7], 60...63),            // narrower than the chord needs
            ([20, 21], [2, 7], 48...60),         // previous far below the register
            ([90, 95, 99], [0, 3, 7], 48...60),  // previous far above the register
        ]
        for c in cases {
            let voiced = VoiceLeader.resolve(from: c.prev, to: c.chord, register: c.reg,
                                             strictness: 1, spread: 0.5)
            XCTAssertFalse(voiced.isEmpty)
            for p in voiced {
                XCTAssertTrue(c.reg.contains(p), "\(p) outside \(c.reg)")
            }
        }
    }

    // MARK: - NaN safety

    func testResolve_nonFiniteControlsFallBackToNeutral() {
        let nan = VoiceLeader.resolve(from: [60, 64, 67], to: [5, 9, 0],
                                      register: register,
                                      strictness: .nan, spread: .nan)
        let neutral = VoiceLeader.resolve(from: [60, 64, 67], to: [5, 9, 0],
                                          register: register,
                                          strictness: 1, spread: 0.5)
        XCTAssertEqual(nan, neutral, "NaN controls read as strict + spread-neutral")
        for p in nan { XCTAssertTrue(register.contains(p)) }
    }
}
