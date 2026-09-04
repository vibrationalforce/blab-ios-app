import XCTest
@testable import Echoelmusic

/// #983 S4 — `darkMinimal`, the second genre of the founder's 2026-09-04 ask. Its case doc is a
/// list of DIFFERENCES from `minimalTechno`, because the plan's first draft (a `[0, 4]` dyad at
/// swing 0.02, saturation 0.12) would have gone red on three blocking claims that batch 4 pinned
/// for minimal — the only dyad, the smallest non-zero swing, the cleanest beat-driven chain. Each
/// of those neighbours' claims is re-asserted here from the newcomer's side, so the next genre
/// cannot quietly take them either. Sound is the founder's ear (NEEDS-FOUNDER-VERIFY).
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
}
