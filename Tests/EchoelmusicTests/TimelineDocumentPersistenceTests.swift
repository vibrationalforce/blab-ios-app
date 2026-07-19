// TimelineDocumentPersistenceTests.swift
// Persistence & Schema-Migration guard (coverage audit 2026-07-19). The arrangement
// (TimelineDocument) is the user's most irreplaceable saved work, yet nothing pinned
// its wire format — a future field rename/removal would decode via the existing
// decodeIfPresent fallbacks and SILENTLY drop that data with no error. These tests
// make that failure LOUD: any change that stops a persisted lane field from
// round-tripping, or breaks loading a legacy document, fails here instead of on a
// user's device. Pure Foundation Codable → runs on every platform.

import XCTest
@testable import Echoelmusic

final class TimelineDocumentPersistenceTests: XCTestCase {

    /// Every persisted per-lane field must survive an encode → decode round-trip.
    /// If a future refactor drops a field from CodingKeys (or renames it), the
    /// decoded document stops equalling the original and this fails.
    func testDocument_encodeDecode_roundTripsEveryLaneField() throws {
        let id0 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let id1 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        // Values chosen to be exactly representable so the round-trip is bit-exact.
        let lead = TimelineLane(id: id0, name: "Lead", kind: .midi,
                                level: 0.75, isMuted: true, isSoloed: false, pan: -0.5,
                                isArmed: true, mood: MoodProfile(),
                                transposeSemitones: 5, detuneCents: 25, octaveDouble: 1)
        let bass = TimelineLane(id: id1, name: "Bass", kind: .audio,
                                level: 0.5, isMuted: false, isSoloed: true, pan: 0.25,
                                samplePath: "/media/audio/bass.caf")
        let doc = TimelineDocument(lanes: [lead, bass], regions: [], automation: [])

        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(TimelineDocument.self, from: data)

        XCTAssertEqual(doc, back, "every persisted lane field must survive a save/load round-trip")
    }

    /// A legacy document — saved before the automation field and before any of the
    /// per-track keys — must still load: never a decode failure, never a dropped
    /// lane, and the missing fields take their back-compat defaults.
    func testLegacyDocument_missingNewerKeys_loadsWithBackCompatDefaults() throws {
        let legacy = Data("""
        {"lanes":[{"id":"00000000-0000-0000-0000-000000000009","name":"Old","kind":"midi"}],"regions":[]}
        """.utf8)

        let doc = try JSONDecoder().decode(TimelineDocument.self, from: legacy)

        XCTAssertEqual(doc.lanes.count, 1, "the legacy lane must not be dropped")
        let lane = try XCTUnwrap(doc.lanes.first)
        XCTAssertEqual(lane.name, "Old")
        XCTAssertEqual(lane.kind, .midi)
        // Missing keys → the documented back-compat defaults, not a decode failure.
        XCTAssertEqual(lane.level, 1, "absent level ⇒ unity")
        XCTAssertEqual(lane.pan, 0, "absent pan ⇒ center")
        XCTAssertFalse(lane.isMuted)
        XCTAssertEqual(lane.transposeSemitones, 0)
        XCTAssertEqual(lane.detuneCents, 0)
        XCTAssertEqual(lane.octaveDouble, 0)
        XCTAssertNil(lane.mood, "absent mood ⇒ follows the global take")
        XCTAssertNil(lane.patch)
        XCTAssertTrue(doc.regions.isEmpty)
        XCTAssertTrue(doc.automation.isEmpty, "absent automation key ⇒ empty, never a failure")
    }

    /// The empty document (a fresh session) round-trips to itself — the base case
    /// the whole persistence path relies on.
    func testEmptyDocument_roundTrips() throws {
        let doc = TimelineDocument()
        let back = try JSONDecoder().decode(TimelineDocument.self,
                                            from: JSONEncoder().encode(doc))
        XCTAssertEqual(doc, back)
    }
}
