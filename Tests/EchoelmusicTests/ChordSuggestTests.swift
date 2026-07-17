// ChordSuggestTests.swift
// Echoel — H2 (PLAN_HARMONY_CORE.md): ChordSuggest core laws + the BioComposer
// wiring (`Input.suggestJourney`).
//
// Pins the laws of the slice:
//   • GOLDEN: `Input.suggestJourney` defaults to false and the false path is
//     the legacy path — compose() output is byte-identical with the field
//     omitted, with it explicitly false, and across repeated calls, over
//     multiple genre archetypes.
//   • RANKING: after a dominant-function chord the top candidate resolves to
//     tonic function (cadence); inside one function class the VoiceLeader
//     distance decides the order (the tie-break); borrowed chords never rank
//     top-1 (they are the tension reservoir).
//   • BORROWINGS: the curated modal-interchange list is derived per key —
//     iv/bVI/bVII in a major key, V-major/Picardy/Neapolitan in a minor key —
//     and a borrowing that is already diatonic is skipped.
//   • DETERMINISM: journeys are seed-stable (own salted stream); different
//     seeds diverge (pinned SplitMix64 draws).
//   • COHERENCE: full coherence always takes the top pick (window 1 — the pure
//     functional cycle T→S→D→T…, never borrowed); low coherence reaches deeper
//     (window 6), so the mean selected rank rises as coherence falls.

import XCTest
@testable import Echoelmusic

final class ChordSuggestTests: XCTestCase {

    private let cMajor = MusicalKey(root: 0, scale: .major)
    private let aMinor = MusicalKey(root: 9, scale: .minor)
    /// A pad-like ranking window (~C3…E5), the kind the composer hands over.
    private let padRegister = 48...76

    // MARK: - Candidates

    func testCandidates_diatonicTriadsWithClassicalFunctions() {
        let diatonic = ChordSuggest.candidates(in: cMajor).filter { !$0.borrowed }
        XCTAssertEqual(diatonic.count, 7, "one third-stack per scale degree")
        let expected: [ChordSuggest.HarmonicFunction] = [
            .tonic,        // I
            .subdominant,  // ii
            .tonic,        // iii
            .subdominant,  // IV
            .dominant,     // V
            .tonic,        // vi
            .dominant      // vii
        ]
        XCTAssertEqual(diatonic.map(\.function), expected)
        XCTAssertTrue(diatonic.allSatisfy { $0.alterations == [0, 0, 0] },
                      "diatonic candidates carry no alterations")
    }

    func testCandidates_curatedBorrowings_majorKey() {
        let borrowed = ChordSuggest.candidates(in: cMajor).filter(\.borrowed)
        let pcSets = borrowed.map { Set(ChordSuggest.pitchClasses(of: $0, in: cMajor)) }
        XCTAssertEqual(borrowed.count, 3)
        XCTAssertTrue(pcSets.contains([5, 8, 0]), "iv (F Ab C) — minor subdominant")
        XCTAssertTrue(pcSets.contains([8, 0, 3]), "bVI (Ab C Eb)")
        XCTAssertTrue(pcSets.contains([10, 2, 5]), "bVII (Bb D F) — back-door dominant")
    }

    func testCandidates_curatedBorrowings_minorKey() {
        let borrowed = ChordSuggest.candidates(in: aMinor).filter(\.borrowed)
        let pcSets = borrowed.map { Set(ChordSuggest.pitchClasses(of: $0, in: aMinor)) }
        XCTAssertEqual(borrowed.count, 3)
        XCTAssertTrue(pcSets.contains([4, 8, 11]), "V major (E G# B) — raised leading tone")
        XCTAssertTrue(pcSets.contains([9, 1, 4]), "I major (A C# E) — Picardy tonic")
        XCTAssertTrue(pcSets.contains([10, 2, 5]), "bII major (Bb D F) — Neapolitan")
    }

    func testCandidates_borrowingAlreadyDiatonic_isSkipped() {
        // In C mixolydian bVII (Bb D F) IS diatonic — the derivation must not
        // duplicate it as a borrowing.
        let mixo = MusicalKey(root: 0, scale: .mixolydian)
        let borrowed = ChordSuggest.candidates(in: mixo).filter(\.borrowed)
        XCTAssertFalse(borrowed.contains {
            Set(ChordSuggest.pitchClasses(of: $0, in: mixo)) == [10, 2, 5]
        })
    }

    // MARK: - Ranking laws

    func testRank_cadence_dominantResolvesToTonic() {
        let cands = ChordSuggest.candidates(in: cMajor)
        guard let five = cands.first(where: { !$0.borrowed && $0.rootDegree == 4 }) else {
            return XCTFail("V candidate missing")
        }
        // A sounding V voicing (G3 B3 D4) — the cadence context.
        let ranked = ChordSuggest.rank(cands, in: cMajor, after: five,
                                       previousVoicing: [55, 59, 62], register: padRegister)
        XCTAssertEqual(ranked.first?.candidate.function, .tonic,
                       "after a dominant the top candidate must resolve to tonic function")
        XCTAssertEqual(ranked.first?.candidate.borrowed, false)
    }

    func testRank_firstChord_favorsTonic() {
        let cands = ChordSuggest.candidates(in: cMajor)
        let ranked = ChordSuggest.rank(cands, in: cMajor, after: nil,
                                       previousVoicing: [], register: padRegister)
        XCTAssertEqual(ranked.first?.candidate.function, .tonic,
                       "a journey opens on the tonic family")
    }

    func testRank_voiceLeadingDistanceBreaksTies() {
        // The tonic-function diatonic candidates after a V chord all carry the
        // same function cost (0) — so their relative order must follow the
        // clamped VoiceLeader head cost exactly (the tie-break law), with the
        // root degree as the final deterministic tie-break.
        let cands = ChordSuggest.candidates(in: cMajor)
        guard let five = cands.first(where: { !$0.borrowed && $0.rootDegree == 4 }) else {
            return XCTFail("V candidate missing")
        }
        let voicing = [55, 59, 62]
        let ranked = ChordSuggest.rank(cands, in: cMajor, after: five,
                                       previousVoicing: voicing, register: padRegister)
        let tonics = ranked
            .filter { $0.candidate.function == .tonic && !$0.candidate.borrowed }
            .map { $0.candidate }
        func distance(_ c: ChordSuggest.Candidate) -> Float {
            let head = VoiceLeader.rankedCandidates(
                from: voicing,
                to: ChordSuggest.pitchClasses(of: c, in: cMajor),
                register: padRegister, spread: 0.5).first?.cost ?? 0
            return Swift.min(Swift.max(head, 0), ChordSuggest.distanceCap)
        }
        let expected = tonics.sorted { a, b in
            let da = distance(a), db = distance(b)
            return da != db ? da < db : a.rootDegree < b.rootDegree
        }
        XCTAssertEqual(tonics, expected,
                       "inside one function class the VoiceLeader distance decides")
    }

    func testRank_borrowedNeverTop() {
        let cands = ChordSuggest.candidates(in: cMajor)
        let contexts: [(ChordSuggest.Candidate?, [Int])] = [
            (nil, []),
            (cands.first { !$0.borrowed && $0.rootDegree == 0 }, [48, 52, 55]),  // after I
            (cands.first { !$0.borrowed && $0.rootDegree == 1 }, [50, 53, 57]),  // after ii
            (cands.first { !$0.borrowed && $0.rootDegree == 4 }, [55, 59, 62])   // after V
        ]
        for (previous, voicing) in contexts {
            let ranked = ChordSuggest.rank(cands, in: cMajor, after: previous,
                                           previousVoicing: voicing, register: padRegister)
            XCTAssertEqual(ranked.first?.candidate.borrowed, false,
                           "the top suggestion stays diatonic — borrowings are the tension reservoir")
        }
    }

    // MARK: - Coherence selection

    func testSelectionWindow_lawAndMonotonicity() {
        XCTAssertEqual(ChordSuggest.selectionWindow(coherence: 1, count: 10), 1)
        XCTAssertEqual(ChordSuggest.selectionWindow(coherence: 0, count: 10),
                       ChordSuggest.maxSelectionWindow)
        XCTAssertEqual(ChordSuggest.selectionWindow(coherence: 0, count: 3), 3,
                       "the window never exceeds the candidate count")
        XCTAssertEqual(ChordSuggest.selectionWindow(coherence: .nan, count: 10), 1,
                       "non-finite coherence fails neutral (consonant)")
        var last = Int.max
        for step in 0...10 {
            let w = ChordSuggest.selectionWindow(coherence: Float(step) / 10, count: 10)
            XCTAssertLessThanOrEqual(w, last, "window shrinks (or holds) as coherence rises")
            last = w
        }
    }

    func testSelectIndex_coherenceMonotonicity_perSeed() {
        // Pointwise: full coherence ALWAYS takes the top pick, so for every seed
        // index(coh 1) = 0 ≤ index(coh 0) — the mean selected rank is monotone.
        // And low coherence really digs below the top: the first SplitMix64
        // draws of seeds 1…16 are all non-zero mod 6 (pinned deterministic
        // values), so every one of these seeds reaches past rank 0.
        for seed in UInt64(1)...16 {
            var rngHigh = SeededRNG(seed: seed)
            var rngLow = SeededRNG(seed: seed)
            let high = ChordSuggest.selectIndex(coherence: 1, count: 10, rng: &rngHigh)
            let low = ChordSuggest.selectIndex(coherence: 0, count: 10, rng: &rngLow)
            XCTAssertEqual(high, 0, "full coherence = the expected consonant top pick")
            XCTAssertGreaterThan(low, 0, "low coherence reaches deeper (pinned draws)")
            XCTAssertLessThan(low, ChordSuggest.maxSelectionWindow)
        }
    }

    // MARK: - Journey

    func testJourney_deterministicPerSeed() {
        let a = ChordSuggest.journey(length: 8, in: cMajor, coherence: 0,
                                     register: padRegister, seed: 1)
        let b = ChordSuggest.journey(length: 8, in: cMajor, coherence: 0,
                                     register: padRegister, seed: 1)
        let c = ChordSuggest.journey(length: 8, in: cMajor, coherence: 0,
                                     register: padRegister, seed: 2)
        XCTAssertEqual(a.count, 8, "a non-empty scale always fills the journey")
        XCTAssertEqual(a, b, "same seed ⇒ same journey")
        // Seeds 1 vs 2: the first salted draws select ranked[4] vs ranked[3] —
        // distinct candidates (pinned SplitMix64 values), so the journeys differ.
        XCTAssertNotEqual(a, c, "different seeds diverge")
    }

    func testJourney_coherenceShapesTheChoice() {
        // Seed 1's first low-coherence pick lands on ranked[4] (pinned draw),
        // while full coherence always takes ranked[0] — the openings differ.
        let calm = ChordSuggest.journey(length: 8, in: cMajor, coherence: 1,
                                        register: padRegister, seed: 1)
        let tense = ChordSuggest.journey(length: 8, in: cMajor, coherence: 0,
                                         register: padRegister, seed: 1)
        XCTAssertNotEqual(calm, tense)
    }

    func testJourney_fullCoherence_isTheFunctionalCycle() {
        // The weight margins make this provable: the capped distance term
        // (0.15 · 8 = 1.2) is strictly below the smallest function step
        // (0.35 · 4 = 1.4) and the borrowed surcharge (3), so at window 1 the
        // journey walks the pure classical circulation T → S → D → T … and
        // never borrows — the expected consonant path a settled body earns.
        for seed: UInt64 in [1, 2, 0x5EED] {
            let journey = ChordSuggest.journey(length: 8, in: cMajor, coherence: 1,
                                               register: padRegister, seed: seed)
            XCTAssertEqual(journey.map(\.function),
                           [.tonic, .subdominant, .dominant, .tonic,
                            .subdominant, .dominant, .tonic, .subdominant],
                           "seed \(seed): full coherence = the functional cycle")
            XCTAssertTrue(journey.allSatisfy { !$0.borrowed },
                          "seed \(seed): full coherence never borrows")
        }
    }

    // MARK: - Alteration mapping (composer rendering contract)

    func testAlterationMapping() {
        let alts = [1, -1, 1]
        XCTAssertEqual(ChordSuggest.alteration(forToneOffset: 0, degreesPerOctave: 7, in: alts), 1)
        XCTAssertEqual(ChordSuggest.alteration(forToneOffset: 2, degreesPerOctave: 7, in: alts), -1)
        XCTAssertEqual(ChordSuggest.alteration(forToneOffset: 4, degreesPerOctave: 7, in: alts), 1)
        XCTAssertEqual(ChordSuggest.alteration(forToneOffset: 6, degreesPerOctave: 7, in: alts), 0,
                       "the 7th stays diatonic — a borrowing only alters its triad")
        XCTAssertEqual(ChordSuggest.alteration(forToneOffset: 7, degreesPerOctave: 7, in: alts), 1,
                       "the octave doubles the (altered) root")
        XCTAssertEqual(ChordSuggest.alteration(forToneOffset: 1, degreesPerOctave: 7, in: alts), 0,
                       "non-stack tones read 0")
        XCTAssertEqual(ChordSuggest.alteration(forToneOffset: 4, degreesPerOctave: 7, in: []), 0,
                       "diatonic chords read 0 everywhere — the legacy arithmetic")
    }

    // MARK: - BioComposer wiring: golden (OFF = legacy, byte-identical)

    private func composerInput(style: MusicStyle = .jazz,
                               coherence: Float = 0.5,
                               seed: UInt64 = 0x5EED,
                               progressionPhase: Int = 0,
                               suggestJourney: Bool = false) -> BioComposer.Input {
        BioComposer.Input(heartRateBPM: 70, hrvNormalized: 0.5, coherence: coherence,
                          breathPhase: 0, breathDepth: 0.5,
                          key: MusicalKey(root: 0, scale: .major),
                          style: style, mode: .studioLocked, lockedTempo: 100,
                          seed: seed, progressionPhase: progressionPhase,
                          suggestJourney: suggestJourney)
    }

    func testSuggestJourneyOff_matchesLegacyPath() {
        // The new field default-false changes NOTHING: an Input built without
        // naming it equals one with an explicit `suggestJourney: false`, note
        // for note, across genre archetypes (chords+lead, signature Fläche,
        // sustained many-chord Fläche).
        for style in [MusicStyle.jazz, .dubTechno, .esotericMeditation] {
            let defaulted = BioComposer.Input(heartRateBPM: 70, hrvNormalized: 0.5,
                                              coherence: 0.5, breathPhase: 0, breathDepth: 0.5,
                                              key: MusicalKey(root: 0, scale: .major),
                                              style: style, mode: .studioLocked,
                                              lockedTempo: 100, seed: 0x5EED)
            let explicit = composerInput(style: style, suggestJourney: false)
            XCTAssertEqual(BioComposer.compose(defaulted), BioComposer.compose(explicit),
                           "\(style): default suggestJourney must equal explicit false (legacy path)")
        }
    }

    func testSuggestJourneyOff_isDeterministic() {
        let a = BioComposer.compose(composerInput())
        let b = BioComposer.compose(composerInput())
        XCTAssertEqual(a, b, "compose must stay deterministic with the H2 field present")
    }

    // MARK: - BioComposer wiring: ON laws

    func testSuggestJourneyOn_isDeterministic() {
        for style in [MusicStyle.jazz, .dubTechno, .esotericMeditation] {
            let a = BioComposer.compose(composerInput(style: style, suggestJourney: true))
            let b = BioComposer.compose(composerInput(style: style, suggestJourney: true))
            XCTAssertEqual(a, b, "\(style): the journey path must be seed-deterministic too")
        }
    }

    func testSuggestJourneyOn_changesTheProgression() {
        // Provable without pinning draws: earlySynth's legacy progression can
        // only ever be [0,0] or [0,4] (a rotation of [0,0]; the neutral default
        // mood never splices — weird 0; the turnaround can only set the last
        // chord to V). At full coherence the journey's second chord is a
        // SUBDOMINANT-function degree (ii or IV — the functional-cycle law),
        // which is neither 0 nor 4, so the second pad section must change.
        let off = BioComposer.compose(composerInput(style: .earlySynth, coherence: 1))
        let on = BioComposer.compose(composerInput(style: .earlySynth, coherence: 1,
                                                   suggestJourney: true))
        XCTAssertNotEqual(off, on, "ON must actually re-choose the progression")
    }

    func testSuggestJourneyOn_journeyAdvancesWithPhase() {
        // The sustained many-chord Fläche holds ONE chord per bar; the phase
        // cursor picks WHICH journey chord. At full coherence phase 0 is a
        // tonic-function chord and phase 2 a dominant-function chord (the
        // functional cycle) — disjoint degree families in a major key, so the
        // pad must differ between the bars.
        let a = BioComposer.compose(composerInput(style: .esotericMeditation, coherence: 1,
                                                  progressionPhase: 0, suggestJourney: true))
        let b = BioComposer.compose(composerInput(style: .esotericMeditation, coherence: 1,
                                                  progressionPhase: 2, suggestJourney: true))
        XCTAssertNotEqual(a, b, "the journey cursor must travel with the phase")
    }

    func testSuggestJourneyOn_keepsContractInvariants() {
        for style in [MusicStyle.jazz, .dubTechno, .esotericMeditation] {
            let off = BioComposer.compose(composerInput(style: style, suggestJourney: false))
            let on = BioComposer.compose(composerInput(style: style, suggestJourney: true))
            XCTAssertFalse(on.notes.isEmpty, "\(style): the journey path must still compose")
            XCTAssertTrue(on.notes.allSatisfy { (0...127).contains($0.pitch) },
                          "\(style): every pitch stays in MIDI range")
            XCTAssertTrue(on.notes.allSatisfy { (0...1).contains($0.velocity) },
                          "\(style): every velocity stays normalized")
            XCTAssertEqual(on.suggestedTempo, off.suggestedTempo,
                           "\(style): tempo is input-derived and must not move with the journey")
        }
    }
}
