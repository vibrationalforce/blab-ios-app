import XCTest
@testable import Echoelmusic

/// #983 S4 — `darkMinimal`, the second genre of the founder's 2026-09-04 ask. Its case doc is a
/// list of DIFFERENCES from `minimalTechno`, because the plan's first draft (a `[0, 4]` dyad at
/// swing 0.02, saturation 0.12) would have gone red on three blocking claims that batch 4 pinned
/// for minimal — the only dyad, the smallest non-zero swing, the cleanest beat-driven chain. Each
/// of those neighbours' claims is re-asserted here from the newcomer's side, so the next genre
/// cannot quietly take them either.
///
/// NEEDS-FOUNDER-VERIFY: Genre "Dark Minimal", Loop-Modus — klingt der weite Quint-Stapel eine
/// Oktave tiefer DUNKEL, ohne zu matschen, und hörst Du den ♭II-Wechsel als Spannung?
/// (Instruction on the line on purpose — see the note in `GenreDeepTechTests`.)
final class GenreDarkMinimalTests: XCTestCase {

    func testDarkMinimalIsOfferedInTheElectronicSection() {
        XCTAssertTrue(MusicStyle.offered.contains(.darkMinimal), "built but not offered — a doorless genre")
        XCTAssertEqual(MusicStyle.darkMinimal.category, .electronic)
        XCTAssertTrue(MusicStyle.Category.electronic.offeredGenres.contains(.darkMinimal))
        XCTAssertEqual(MusicStyle.darkMinimal.displayName, "Dark Minimal")
    }

    /// Root · fifth · fifth-an-octave-up on phrygian, three notes, no third — and minimal stays the only dyad.
    func testTheWideOpenFifthIsNewAndLeavesMinimalItsDyad() {
        let profile = MusicStyle.darkMinimal.harmonicProfile
        XCTAssertEqual(profile.chordTones, [0, 4, 11])
        XCTAssertEqual(profile.progression, [0, 1], "i → ♭II is where the dark comes from")
        XCTAssertEqual(profile.padOctave, 3, "an octave under every other stabbing techno genre")
        XCTAssertFalse(profile.arpeggiated)
        XCTAssertFalse(profile.sustained)
        XCTAssertEqual(MusicStyle.darkMinimal.scale, .phrygian)
        let copies = MusicStyle.allCases.filter { $0 != .darkMinimal && $0.harmonicProfile.chordTones == [0, 4, 11] }
        XCTAssertTrue(copies.isEmpty, "the case doc says no other arm carries [0, 4, 11]; found \(copies)")
        let dyads = MusicStyle.allCases.filter { $0.harmonicProfile.chordTones.count == 2 }
        XCTAssertEqual(dyads, [.minimalTechno], "minimal's only-dyad claim must survive this genre")
        XCTAssertFalse(profile.chordTones.contains(6), "no seventh — Romance's count grows by one here")
    }

    func testDarkMinimalIsMachineStraightAndStabsOnTheBeat() {
        XCTAssertEqual(MusicStyle.darkMinimal.swing, 0)
        XCTAssertGreaterThan(MusicStyle.minimalTechno.swing, 0, "minimal keeps the smallest NON-ZERO swing")
        XCTAssertEqual(MusicStyle.darkMinimal.beatArchetype, .fourOnFloor)
        XCTAssertEqual(MusicStyle.darkMinimal.chordArticulation, .stab)
        XCTAssertEqual(MusicStyle.darkMinimal.tempoRange, 126...131)
        XCTAssertEqual(MusicStyle.darkMinimal.defaultTempo, 129)
    }

    /// Minimal's figure, its own sub — and the sub keeps "Minimal Sub" its darkest/lowest claim.
    func testDarkMinimalSharesMinimalsFigureOnItsOwnSub() throws {
        XCTAssertEqual(MusicStyle.darkMinimal.bassGrammar, .sparseSub)
        let dark = try XCTUnwrap(MusicStyle.darkMinimal.bassPatch)
        let minimal = try XCTUnwrap(MusicStyle.minimalTechno.bassPatch)
        XCTAssertEqual(dark.name, "Dark Sub")
        XCTAssertNotEqual(dark.id, minimal.id)
        XCTAssertGreaterThan(dark.filterCutoff, minimal.filterCutoff, "Minimal Sub keeps the lowest cutoff")
        XCTAssertGreaterThan(dark.brightness, minimal.brightness, "Minimal Sub keeps the darkest patch")
        XCTAssertEqual(MusicStyle.darkMinimal.synthPatch.name, "Dark Edge")
        XCTAssertLessThan(MusicStyle.darkMinimal.synthPatch.brightness, MusicStyle.minimalTechno.synthPatch.brightness,
                          "the PAD is the darkest of the stabbing family")
        XCTAssertGreaterThan(MusicStyle.darkMinimal.synthPatch.attack, MusicStyle.minimalTechno.synthPatch.attack,
                             "a Fläche with an edge swells; the minimal stab clicks")
    }

    /// Every FX number was placed against a neighbour's documented claim — re-asserted from this side.
    func testTheFXPresetLeavesEveryNeighbourClaimStanding() {
        let dark = MusicStyle.darkMinimal.fxPreset
        let minimal = MusicStyle.minimalTechno.fxPreset
        XCTAssertGreaterThan(dark.saturation, minimal.saturation, "minimal keeps the cleanest beat-driven chain")
        XCTAssertLessThan(dark.delayFeedback, minimal.delayFeedback, "minimal keeps the longest four-on-floor tail")
        XCTAssertGreaterThan(dark.delayTone, MusicStyle.deepDrone.fxPreset.delayTone, "deepDrone keeps the darkest tone")
        XCTAssertLessThan(dark.reverbDamping, MusicStyle.deepDrone.fxPreset.reverbDamping, "deepDrone keeps the most damped hall")
        XCTAssertGreaterThan(dark.reverbDamping, MusicStyle.techHouse.fxPreset.reverbDamping,
                             "techHouse's damping comment says it now ranks sixth, behind this genre")
        XCTAssertFalse(dark.chorusEnabled)
    }

    /// #984b — THE WIDE STACK MUST SURVIVE THE ENGINE, not just the profile table.
    ///
    /// `[0, 4, 11]` is the only voicing in the file whose top index exceeds the scale length, so
    /// it is the only one that depends on `MusicalKey.degree` WRAPPING rather than clamping. The
    /// pad loop in `BioComposer.composeHarmonic` builds each pitch as
    /// `key.degree(rootDegree + tone, octave:) + ChordSuggest.alteration(forToneOffset: tone, …)`,
    /// and this claim drives exactly those two pure functions with this genre's tones. It does NOT
    /// run the composer — say so rather than imply an end-to-end proof.
    ///
    /// WHAT IT PROTECTS: an "obvious simplification" that clamps a chord tone to
    /// `degreesPerOctave`, or that indexes the alteration table without wrapping. Either would
    /// silently collapse the octave-and-a-half stack into a plain fifth — the genre would still
    /// generate, still pass every other claim here, and simply stop being wide. Measured on the
    /// shipping arithmetic: root C, PHRYGIAN (this genre's scale), padOctave 3 → C3 · G3 · G4.
    ///
    /// ⛔ THE FIRST VERSION OF THIS COMMENT SAID "natural minor" — in BOTH the doc line and the
    /// assertion message — and this genre is phrygian. The pitches were still right, and that is
    /// exactly why it survived: phrygian [0,1,3,5,7,8,10] and natural minor [0,2,3,5,7,8,10]
    /// DIFFER ONLY AT DEGREE 1, which `[0, 4, 11]` never touches, so both scales produce
    /// 48 · 55 · 67 and no assertion could tell them apart. The code was never wrong (it reads
    /// `MusicStyle.darkMinimal.scale`); only the label a future reader plans from was. GESETZ: a
    /// worked example must name the input it actually used, because the arithmetic agreeing is
    /// not evidence that the description does.
    func testTheWideStackSurvivesTheDegreeAndAlterationMathematics() {
        let key = MusicalKey(root: 0, scale: MusicStyle.darkMinimal.scale)
        let tones = MusicStyle.darkMinimal.harmonicProfile.chordTones
        let octave = MusicStyle.darkMinimal.harmonicProfile.padOctave
        let pitches = tones.map { key.degree($0, octave: octave) }

        XCTAssertEqual(Set(pitches).count, 3, "the stack collapsed to \(pitches) — three distinct pitches are the genre")
        XCTAssertEqual(pitches, pitches.sorted(), "the stack must ascend: \(pitches)")
        XCTAssertGreaterThan((pitches.max() ?? 0) - (pitches.min() ?? 0), 12,
                             "the stack spans \((pitches.max() ?? 0) - (pitches.min() ?? 0)) semitones, "
                             + "not more than an octave — \"wide\" is what separates it from a plain fifth")
        XCTAssertEqual(pitches, [48, 55, 67], "root C, phrygian, padOctave 3 → C3 · G3 · G4")

        // Degree 11 is degree 4 an octave up, so it must take the SAME alteration; an unwrapped
        // table lookup would hand it a different accidental and bend the top voice out of key.
        //
        // ⛔ THE ALTERATION TABLE HERE IS CHOSEN, NOT ARBITRARY, and the first draft got it wrong
        // in the way that matters: it used `[1, 0, 0, 0]`, where the entry for stack position 4
        // (index 4/2 = 2) is ZERO. Both sides of the comparison were 0, so the assertion held
        // whether or not the wrap existed — a claim that cannot fail is not a guard. The table
        // below puts the 1 at index 2, so an unwrapped lookup (tone 11 is odd → the `t % 2 == 0`
        // guard rejects it → 0) reads 0 against the wrapped 1 and the claim goes red.
        let alts = [0, 0, 1, 0]
        let altAtEleven = ChordSuggest.alteration(
            forToneOffset: 11, degreesPerOctave: key.degreesPerOctave, in: alts)
        XCTAssertEqual(altAtEleven,
                       ChordSuggest.alteration(forToneOffset: 4,
                                               degreesPerOctave: key.degreesPerOctave, in: alts),
                       "tone 11 and tone 4 are the same scale degree an octave apart and must be "
                       + "altered alike")
        XCTAssertEqual(altAtEleven, 1,
                       "the table entry this claim rests on is 0, so the comparison above passes "
                       + "vacuously. Pick a table whose stack-position-4 entry is non-zero.")
    }
}
