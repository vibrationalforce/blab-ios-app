// TimelineSchemaVersionSmokeTests.swift
// Echoel — the song format's version stamp (#189), in the BLOCKING bundle.
//
// WHY THIS ONE EARNS A GATE. `TimelineDocument` is the file that holds the whole song:
// lanes, regions, arrangement automation. The stamp added here is worthless unless three
// things hold, and each of them is invisible until the day it is too late to check:
//
//  1. A song written by a build that predates the stamp must still LOAD — with its
//     content intact and its provenance honestly reported as 0. If this breaks, the
//     migration the stamp exists to enable has already destroyed what it was protecting.
//  2. Saving must write the CURRENT version, not the provenance the instance carries.
//     A synthesized encoder would have written the old 0 straight back, which makes every
//     re-saved old song permanently indistinguishable from a genuinely ancient one — the
//     stamp would then be decorative.
//  3. A song from a FUTURE build must not be vaporized. Users move between TestFlight
//     builds in both directions; a newer stamp is not corruption.
//
// The stamp is going in FRONT of a known break: #167 deletes the drums, which removes a
// case from the persisted lane enums. This is the only thing that will let a later
// migration tell "written before the drums went" from "written after".

import XCTest
@testable import Echoelmusic

final class TimelineSchemaVersionSmokeTests: XCTestCase {

    /// A song saved before the stamp existed: no `schemaVersion` key at all. The lane
    /// object is copied verbatim from `TimelineDecodeTests.testDocument_laneMissingName_
    /// documentSurvives`, a test that already passes — so if this file ever goes red it is
    /// the stamp that broke, not a lane literal I guessed at.
    private let preVersioningJSON = """
    {"lanes":[{"id":"00000000-0000-0000-0000-000000000010","kind":"audio"}],
     "regions":[],"automation":[]}
    """

    /// Provenance 0 for an unstamped file — and the song itself survives. `0` is a TRUE
    /// statement ("predates versioning"), not a default standing in for "current"; that
    /// distinction is the entire point of the field.
    func testAPreVersioningSongLoadsAndReportsProvenanceZero() throws {
        let data = Data(preVersioningJSON.utf8)
        let doc = try JSONDecoder().decode(TimelineDocument.self, from: data)
        XCTAssertEqual(doc.schemaVersion, 0)
        XCTAssertEqual(doc.lanes.count, 1, "the song must survive the stamp being added")
        XCTAssertEqual(doc.lanes.first?.kind, .audio)
    }

    /// A freshly built document is by definition in this build's shape.
    func testAFreshDocumentCarriesTheCurrentVersion() {
        XCTAssertEqual(TimelineDocument().schemaVersion, TimelineDocument.currentSchemaVersion)
        XCTAssertGreaterThan(TimelineDocument.currentSchemaVersion, 0,
                             "0 is reserved for pre-versioning files and must never be current")
    }

    /// THE PROPERTY THE EXPLICIT ENCODER EXISTS FOR. Load an unstamped song (provenance 0),
    /// save it, and the BYTES must say current — while the in-memory value still says where
    /// it came from. A synthesized encoder fails this by writing the 0 back.
    func testSavingAnOldSongWritesTheCurrentStampNotItsProvenance() throws {
        let loaded = try JSONDecoder().decode(TimelineDocument.self,
                                              from: Data(preVersioningJSON.utf8))
        XCTAssertEqual(loaded.schemaVersion, 0, "precondition: provenance is still 0")

        let round = try JSONDecoder().decode(TimelineDocument.self,
                                             from: JSONEncoder().encode(loaded))
        XCTAssertEqual(round.schemaVersion, TimelineDocument.currentSchemaVersion,
                       "the file this build writes IS in this build's shape")
        XCTAssertEqual(round.lanes.count, 1, "and re-saving must not lose the song")
    }

    /// A song written by a LATER build loads and keeps its own (higher) stamp. Users move
    /// between TestFlight builds in both directions; a newer stamp is not corruption, and
    /// silently clamping it to current would erase the one signal a downgrade could act on.
    func testAFutureSongIsNotVaporizedAndKeepsItsOwnStamp() throws {
        let json = """
        {"schemaVersion":99,"lanes":[],"regions":[],"automation":[]}
        """
        let doc = try JSONDecoder().decode(TimelineDocument.self, from: Data(json.utf8))
        XCTAssertEqual(doc.schemaVersion, 99)
    }

    /// A MALFORMED stamp degrades to "unknown provenance" instead of throwing. This is the
    /// deliberate divergence from `Project`, whose `decodeIfPresent` would throw here: in
    /// this decoder a throw costs the user their entire song, which is the exact failure
    /// the surrounding element-tolerant decode was written to prevent.
    func testAMalformedStampCostsTheProvenanceNotTheSong() throws {
        for bad in ["\"1\"", "null", "{}", "[1]"] {
            let json = """
            {"schemaVersion":\(bad),
             "lanes":[{"id":"00000000-0000-0000-0000-000000000010","kind":"audio"}],
             "regions":[],"automation":[]}
            """
            let doc = try JSONDecoder().decode(TimelineDocument.self, from: Data(json.utf8))
            XCTAssertEqual(doc.schemaVersion, 0, "stamp \(bad) → unknown provenance")
            XCTAssertEqual(doc.lanes.count, 1, "stamp \(bad) must not cost the song")
        }
    }
}
