import XCTest
@testable import Echoelmusic

/// #983 S3 — `deepTech`, the first of the three genres the founder's 2026-09-04 ask named that the
/// roster did not have ("richtig gute Bass und Pad etc Loops für Deep tech, dark minimal, deep
/// house, psy prog House"). Every claim its case doc makes is measured here, in the BLOCKING bundle,
/// because a genre doc is the line the next session plans from and this file has retracted
/// genre-doc superlatives three times already (`GenreBatchFourVoicingTests`).
///
/// Nothing here pins a SOUND. What is pinned is the STRUCTURE the doc claims: the voicing is new,
/// the figure and the bass patch come together, the picker reaches it, and the count homes that
/// name the roster size moved with it.
///
/// NEEDS-FOUNDER-VERIFY: Genre "Deep Tech", Loop-Modus, ruhig sitzen — liest sich die terzlose
/// Shell als "deep" (Gewicht ohne Dur/Moll-Farbe), und TREIBEN die Achtel im Bass, statt wie ein
/// Metronom zu ticken?
///
/// ⚠️ THE INSTRUCTION BELONGS ON THIS LINE, not in the plan. `scripts/founder-verify.py` walks
/// Sources/, Tests/ and CLAUDE.md — NOT `scratchpads/` ("session prose, not asks"). This header
/// first shipped with the marker carrying no question at all, only a pointer to a plan file the
/// tool cannot read, so the printed checklist gained an entry the founder could not act on. That
/// is worse than no entry: it costs a glance on every walk and settles nothing.
///
/// ⚠️ AND THIS PARAGRAPH IS NOT ITSELF AN ASK — it is prose ABOUT the marker (#753). The tool's
/// NOT-ASKS split keys on a DETERMINER immediately in front, so a sentence like this one must be
/// phrased to end in "the" before naming the NEEDS-FOUNDER-VERIFY marker, or it is counted as a
/// 54th job. Measured after writing: the first draft of this very paragraph was counted.
final class GenreDeepTechTests: XCTestCase {

    func testDeepTechIsOfferedInTheElectronicSection() {
        XCTAssertTrue(MusicStyle.offered.contains(.deepTech), "built but not offered — a doorless genre")
        XCTAssertEqual(MusicStyle.deepTech.category, .electronic)
        XCTAssertTrue(MusicStyle.Category.electronic.offeredGenres.contains(.deepTech),
                      "offered, but the picker section it belongs to does not list it")
        XCTAssertEqual(MusicStyle.deepTech.displayName, "Deep Tech")
    }

    /// `[0, 4, 6]` on natural minor = root + fifth + ♭7, no third — and no other arm has it.
    func testTheThirdLessMinorSeventhShellIsNewToTheRoster() {
        let profile = MusicStyle.deepTech.harmonicProfile
        XCTAssertEqual(profile.chordTones, [0, 4, 6])
        XCTAssertEqual(profile.progression, [0, 5])
        XCTAssertEqual(profile.padOctave, 4)
        XCTAssertFalse(profile.arpeggiated, "arpeggiated would bypass the `.stab` articulation")
        XCTAssertFalse(profile.sustained, "sustained would suppress the authored bass figure")
        XCTAssertEqual(MusicStyle.deepTech.scale, .minor)
        let copies = MusicStyle.allCases.filter { $0 != .deepTech && $0.harmonicProfile.chordTones == [0, 4, 6] }
        XCTAssertTrue(copies.isEmpty, "the case doc says no other arm carries [0, 4, 6]; found \(copies)")
    }

    func testDeepTechStabsOnTheBeatAtAHouseTempo() {
        XCTAssertEqual(MusicStyle.deepTech.beatArchetype, .fourOnFloor)
        XCTAssertEqual(MusicStyle.deepTech.chordArticulation, .stab)
        XCTAssertEqual(MusicStyle.deepTech.tempoRange, 124...128)
        XCTAssertEqual(MusicStyle.deepTech.defaultTempo, 126)
        XCTAssertEqual(MusicStyle.deepTech.swing, 0.08, accuracy: 0.0001)
        XCTAssertLessThan(MusicStyle.deepTech.swing, MusicStyle.techHouse.swing,
                          "the doc claims a straighter shuffle than tech house")
    }

    /// The half of the ask the pad cannot carry: the figure AND its own instrument, together.
    func testDeepTechDrivesEighthsOnItsOwnBass() {
        XCTAssertEqual(MusicStyle.deepTech.bassGrammar, .drivingEighths)
        let bass = try? XCTUnwrap(MusicStyle.deepTech.bassPatch)
        XCTAssertEqual(bass?.name, "Deep Bass")
        XCTAssertEqual(MusicStyle.deepTech.synthPatch.name, "Deep Shell")
        XCTAssertNotEqual(bass?.id, MusicStyle.techHouse.bassPatch?.id,
                          "shares tech house's figure, must not share its bass patch identity")
    }

    /// The pad brightness axis the patch doc claims: minimal (0.24) < deep tech (0.28) < tech house (0.34).
    func testThePadSitsBetweenTheMinimalStabAndTheHouseShellOnBrightness() {
        XCTAssertLessThan(MusicStyle.minimalTechno.synthPatch.brightness, MusicStyle.deepTech.synthPatch.brightness)
        XCTAssertLessThan(MusicStyle.deepTech.synthPatch.brightness, MusicStyle.techHouse.synthPatch.brightness)
    }

    /// The FX doc's three ordering claims, each against the arm it names.
    func testTheFXPresetKeepsItsNeighboursSuperlativesTrue() {
        let deep = MusicStyle.deepTech.fxPreset
        let tech = MusicStyle.techHouse.fxPreset
        let minimal = MusicStyle.minimalTechno.fxPreset
        XCTAssertLessThan(deep.delayFeedback, minimal.delayFeedback, "minimal keeps the longest four-on-floor tail")
        XCTAssertLessThan(deep.reverbDamping, tech.reverbDamping, "tech house keeps its damping rank")
        XCTAssertGreaterThan(deep.reverbRoom, minimal.reverbRoom)
        XCTAssertLessThan(deep.reverbRoom, tech.reverbRoom)
        XCTAssertFalse(deep.chorusEnabled, "no chorus — width would blur the bass")
    }

    /// Romance's caption count is pinned in `MoodKnobsSayWhatTheyDoTests`; this states the half
    /// that keeps deep tech OUT of that count — the shell already has the seventh.
    func testTheShellAlreadyCarriesTheSeventhSoTheRomanceCountIsUnchanged() {
        XCTAssertTrue(MusicStyle.deepTech.harmonicProfile.chordTones.contains(6))
    }
}
