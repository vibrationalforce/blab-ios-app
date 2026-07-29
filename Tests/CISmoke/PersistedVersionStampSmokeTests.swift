// PersistedVersionStampSmokeTests.swift
// Echoel — the last three content-bearing formats carry a version stamp (#189 slice 5),
// in the BLOCKING bundle.
//
// WHAT THESE GUARD, and it is exactly one thing that cannot be seen by reading the structs:
// the stamp is a stored property that NO code ever assigns, and its only job is to be
// EMITTED by the synthesized encoder. If synthesis quietly skipped it, the format would be
// unstamped while every doc comment claimed otherwise — a decorative stamp, which is worse
// than none, because a later migration would branch on a key that was never written.
//
// `Arrangement` is the one with a REAL failure mode here rather than a theoretical one: it
// has an EXPLICIT `CodingKeys`, so its case had to be added by hand. The other two have
// synthesized `CodingKeys` that extend themselves. Forgetting the hand-written case is a
// silent no-op, and this file is the only place that would catch it.
//
// Asserted against raw JSON throughout. Decoding the value back would pass even if the key
// were never written, because the property's default would supply it.

import XCTest
@testable import Echoelmusic

final class PersistedVersionStampSmokeTests: XCTestCase {

    private func stamp(of data: Data) throws -> Int? {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return object["schemaVersion"] as? Int
    }

    // MARK: - The stamps are really written

    /// THE ONE WITH THE HAND-WRITTEN `CodingKeys` CASE. `Arrangement` is also the only one
    /// of the three that is a DOCUMENT — `ArrangementStore` persists a single `Arrangement`,
    /// so this stamp versions the file itself rather than one element of an array.
    func testTheArrangementDocumentWritesItsStamp() throws {
        let data = try JSONEncoder().encode(Arrangement())
        XCTAssertEqual(try stamp(of: data), Arrangement.currentSchemaVersion,
                       "the explicit CodingKeys must list the case — otherwise it is decorative")
    }

    /// The user's timbre library. Per patch, since `PatchStore` persists a bare array.
    func testAPatchWritesItsStamp() throws {
        let data = try JSONEncoder().encode(SynthPatch(name: "Take"))
        XCTAssertEqual(try stamp(of: data), SynthPatch.currentSchemaVersion)
    }

    /// Per mood, same reason.
    func testAMoodWritesItsStamp() throws {
        let data = try JSONEncoder().encode(MoodPreset(name: "Calm"))
        XCTAssertEqual(try stamp(of: data), MoodPreset.currentSchemaVersion)
    }

    // MARK: - Nothing already saved is lost

    /// A song saved before the stamp existed still loads with its sections. `Arrangement`'s
    /// decoder is additive, so this should hold — but "should" is what every silent
    /// data-loss bug in this repo was built on, and adding a key is exactly the moment to
    /// stop assuming.
    func testAPreVersioningArrangementKeepsItsSections() throws {
        let json = """
        {"sections":[{"id":"00000000-0000-0000-0000-0000000000a1",
                      "name":"Intro","colorIndex":1,"lengthBars":4}]}
        """
        let song = try JSONDecoder().decode(Arrangement.self, from: Data(json.utf8))
        XCTAssertEqual(song.sections.count, 1)
        XCTAssertEqual(song.sections.first?.name, "Intro")
        XCTAssertEqual(song.totalBars, 4)
        XCTAssertEqual(song.schemaVersion, Arrangement.currentSchemaVersion,
                       "absent stamp reads as current here — the value is not provenance")
    }

    /// A patch saved before the stamp existed still loads with its timbre intact. This is
    /// the type whose decoder already cost one live data-loss fix (#95).
    func testAPreVersioningPatchKeepsItsTimbre() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-0000000000b1","name":"Old",
         "brightness":0.7,"harmonicity":0.5}
        """
        let patch = try JSONDecoder().decode(SynthPatch.self, from: Data(json.utf8))
        XCTAssertEqual(patch.name, "Old")
        XCTAssertEqual(patch.brightness, 0.7, accuracy: 1e-6)
        XCTAssertEqual(patch.harmonicity, 0.5, accuracy: 1e-6)
    }

    /// Same for a mood.
    func testAPreVersioningMoodKeepsItsValues() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-0000000000c1","name":"Old","darkness":0.9}
        """
        let mood = try JSONDecoder().decode(MoodPreset.self, from: Data(json.utf8))
        XCTAssertEqual(mood.name, "Old")
        XCTAssertEqual(mood.darkness, 0.9, accuracy: 1e-6)
    }

    /// Round-trip stays lossless with the key added — the guard that nothing was displaced
    /// on the way out. `Arrangement` earns it most: its `CodingKeys` was edited by hand.
    func testAFullArrangementRoundTripsUnchanged() throws {
        let song = Arrangement(sections: [
            ArrangementSection(clipID: UUID(), name: "Verse", colorIndex: 2, lengthBars: 8),
            ArrangementSection(name: "Gap", lengthBars: 2)
        ])
        let round = try JSONDecoder().decode(Arrangement.self,
                                             from: JSONEncoder().encode(song))
        XCTAssertEqual(round, song, "a section field displaced by the new key shows up here")
    }

    // MARK: - The one that was ALREADY versioned

    /// `FXPreset` is deliberately NOT given a `schemaVersion`: it has carried its own
    /// `schema: Int` since long before this task, callers assign it, and the factory presets
    /// ship `3`. Pinned here because a list in a doc comment claimed it was unstamped — the
    /// claim was wrong, and a future session reading that list would otherwise "fix" it by
    /// adding a SECOND version field, leaving two disagreeing numbers in one file.
    func testTheFXPresetKeepsItsOwnOlderVersionFieldAndGainsNoSecondOne() throws {
        // Built by decoding rather than by calling the ~40-argument memberwise init: the
        // decoder defaults every field, so `{}` is a valid preset and the test does not
        // break every time a stage is added to the chain.
        let preset = try JSONDecoder().decode(FXPreset.self, from: Data("{}".utf8))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(preset))
                as? [String: Any])
        XCTAssertNotNil(object["schema"] as? Int, "its existing version field must stay")
        XCTAssertNil(object["schemaVersion"],
                     "one version field per format — do not add a competing second one")
    }
}
