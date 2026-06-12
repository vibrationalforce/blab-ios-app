// PatchLibraryTests.swift
// Echoel — the curated factory preset database (broad-audience "pick a beautiful
// sound without knowing synthesis"). Structural + range invariants.

#if canImport(Accelerate)
import XCTest
@testable import Echoelmusic

final class PatchLibraryTests: XCTestCase {

    func testLibraryIsLarge() {
        XCTAssertGreaterThanOrEqual(PatchLibrary.all.count, 24, "a real, browsable database")
    }

    func testIdsAreUnique() {
        let ids = PatchLibrary.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "stable ids must be unique")
    }

    func testEveryPresetHasACategoryAndTags() {
        for lp in PatchLibrary.all {
            XCTAssertTrue(PatchLibrary.categories.contains(lp.category), "\(lp.patch.name) category")
            XCTAssertFalse(lp.tags.isEmpty, "\(lp.patch.name) should be tagged")
        }
    }

    func testParamsAreInValidRanges() {
        for lp in PatchLibrary.all {
            let p = lp.patch
            XCTAssertTrue((0...1).contains(p.brightness), p.name)
            XCTAssertTrue((0...1).contains(p.harmonicity), p.name)
            XCTAssertTrue((0...1).contains(p.sustain), p.name)
            XCTAssertTrue((0...1).contains(p.reverbMix), p.name)
            XCTAssertTrue((20...18_000).contains(p.filterCutoff), p.name)
            XCTAssertGreaterThan(p.attack, 0, p.name)
        }
    }

    func testPresetsInCategoryFilters() {
        for category in PatchLibrary.categories {
            let presets = PatchLibrary.presets(in: category)
            XCTAssertFalse(presets.isEmpty, "\(category) should have presets")
            XCTAssertTrue(presets.allSatisfy { $0.category == category })
        }
    }

    func testSearchMatchesNameAndTags() {
        XCTAssertTrue(PatchLibrary.search("meditation").count >= 2, "tag search")
        XCTAssertTrue(PatchLibrary.search("bell").contains { $0.patch.name.contains("Bell") })
        XCTAssertEqual(PatchLibrary.search("").count, PatchLibrary.all.count, "empty query = all")
    }
}
#endif
