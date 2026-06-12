// SkillLevelTests.swift
// Echoel — the progressive-disclosure dial (noob → pro). Each level is a superset
// of the previous: higher levels only ADD surfaces, never remove.

import XCTest
@testable import Echoelmusic

final class SkillLevelTests: XCTestCase {

    func testOrdering() {
        XCTAssertLessThan(SkillLevel.beginner, .producer)
        XCTAssertLessThan(SkillLevel.producer, .pro)
        XCTAssertEqual(SkillLevel.allCases, [.beginner, .producer, .pro])
    }

    func testBeginnerIsEssentialsOnly() {
        XCTAssertFalse(SkillLevel.beginner.showsSongs, "beginner = Create + Meditate only")
        XCTAssertFalse(SkillLevel.beginner.showsProTabs)
    }

    func testProducerAddsSongsButNotProTabs() {
        XCTAssertTrue(SkillLevel.producer.showsSongs)
        XCTAssertFalse(SkillLevel.producer.showsProTabs, "Sessions/Connect are Pro-only")
    }

    func testProUnlocksEverything() {
        XCTAssertTrue(SkillLevel.pro.showsSongs)
        XCTAssertTrue(SkillLevel.pro.showsProTabs)
    }

    func testGatesAreMonotonic() {
        // Each surface, once unlocked, stays unlocked at every higher level.
        for level in SkillLevel.allCases {
            for higher in SkillLevel.allCases where higher >= level {
                if level.showsSongs { XCTAssertTrue(higher.showsSongs, "\(higher) must keep Songs") }
                if level.showsProTabs { XCTAssertTrue(higher.showsProTabs, "\(higher) must keep pro tabs") }
            }
        }
    }

    func testRawValueRoundTrips() {
        for level in SkillLevel.allCases {
            XCTAssertEqual(SkillLevel(rawValue: level.rawValue), level)
            XCTAssertFalse(level.displayName.isEmpty)
            XCTAssertFalse(level.blurb.isEmpty)
        }
        XCTAssertNil(SkillLevel(rawValue: "expert"), "unknown raw → nil (caller falls back to beginner)")
    }
}
