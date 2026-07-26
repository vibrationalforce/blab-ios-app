// MoodPresetTests.swift
// Echoel — named composition moods: Codable round-trip, capture/recall symmetry,
// curated factory invariants, ranking, and the bundled community loop.

import XCTest
@testable import Echoelmusic

final class MoodPresetTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let mood = MoodPreset.factory[2] // Romantic
        let data = try JSONEncoder().encode(mood)
        let decoded = try JSONDecoder().decode(MoodPreset.self, from: data)
        XCTAssertEqual(decoded, mood)
    }

    func testProfileRoundTrip_captureThenRecall() {
        let profile = MoodProfile(liveliness: 0.7, darkness: 0.2, tension: 0.9,
                                  romance: 0.1, weird: 0.6, virtuosity: 0.8,
                                  syncopation: 0.4, humanize: 0.3)
        let preset = MoodPreset(name: "Captured", from: profile)
        XCTAssertEqual(preset.profile, profile, "capture(from:) then .profile must be identity")
    }

    func testFactoryIsCuratedAndStable() {
        XCTAssertGreaterThanOrEqual(MoodPreset.factory.count, 6, "a real, browsable set")
        let a = MoodPreset.factory.map { $0.id }
        let b = MoodPreset.factory.map { $0.id }
        XCTAssertEqual(a, b, "factory ids must be stable")
        XCTAssertEqual(Set(a).count, a.count, "factory ids are unique")
        for m in MoodPreset.factory {
            XCTAssertFalse(m.name.isEmpty)
            XCTAssertFalse(m.tags.isEmpty, "\(m.name) should be tagged")
            for v in [m.liveliness, m.darkness, m.tension, m.romance,
                      m.weird, m.virtuosity, m.syncopation, m.humanize] {
                XCTAssertTrue((0...1).contains(v), "\(m.name) dims must be 0…1")
            }
        }
    }

    func testSearchMatchesNameAndTags() {
        let calm = MoodPreset.factory.first { $0.name == "Calm" }
        XCTAssertNotNil(calm)
        XCTAssertTrue(calm!.matches("cal"), "name match")
        XCTAssertTrue(calm!.matches("ambient"), "tag match")
        XCTAssertTrue(calm!.matches(""), "empty query matches all")
        XCTAssertFalse(calm!.matches("zzz"))
    }

    func testCommunityIssueURL_isWellFormed_withEmbeddedJSON() {
        let mood = MoodPreset.factory[0]
        guard let url = mood.communityIssueURL() else { return XCTFail("nil URL") }
        XCTAssertEqual(url.host, "github.com")
        XCTAssertTrue(url.path.hasSuffix("/issues/new"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains { $0.name == "labels" && $0.value == "mood-submission" })
        XCTAssertTrue(items.contains { $0.name == "title" && ($0.value?.contains(mood.name) ?? false) })
        XCTAssertTrue((items.first { $0.name == "body" }?.value ?? "").contains("\"name\""))
    }

    func testBundledCommunity_loadsSeededExample() {
        // Report what WAS loaded: an empty list means the resource was never located in
        // any candidate bundle (packaging), a non-empty one without the expected name
        // means it was found but decoded to something else (schema/name). The CI reveal
        // prints only the test name, so the bare form cannot tell those apart.
        let names = MoodPreset.community.map(\.name)
        XCTAssertTrue(names.contains("Aurora Calm"),
                      "seeded Resources/Community/moods/aurora-calm.json should bundle + decode — "
                      + (names.isEmpty
                         ? "EMPTY (resource not located in any candidate bundle)"
                         : "\(names.count) found: \(names.sorted().joined(separator: ", "))"))
    }

    @MainActor
    func testRanking_favoritesThenRecentsThenNatural() {
        let a = MoodPreset.factory[0], b = MoodPreset.factory[1], c = MoodPreset.factory[2]
        let moods = [a, b, c]
        XCTAssertEqual(MoodPresetStore.ranked(moods, favorites: [], recents: []).map(\.id),
                       [a.id, b.id, c.id])
        XCTAssertEqual(MoodPresetStore.ranked(moods, favorites: [c.id], recents: []).map(\.id),
                       [c.id, a.id, b.id])
        XCTAssertEqual(MoodPresetStore.ranked(moods, favorites: [], recents: [b.id]).map(\.id),
                       [b.id, a.id, c.id])
        XCTAssertEqual(MoodPresetStore.ranked(moods, favorites: [c.id], recents: [b.id]).map(\.id),
                       [c.id, b.id, a.id])
    }
}
