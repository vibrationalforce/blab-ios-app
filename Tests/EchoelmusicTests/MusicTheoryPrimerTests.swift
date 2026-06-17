// MusicTheoryPrimerTests.swift
// Echoel — the music-theory "school" copy. Every topic fully explained,
// craft-first, and free of esoteric/overclaim terms (brand rule).

import XCTest
@testable import Echoelmusic

final class MusicTheoryPrimerTests: XCTestCase {

    func testEveryTopicFullyExplained() {
        for t in MusicTheoryTopic.allCases {
            XCTAssertFalse(t.title.isEmpty, "\(t) title")
            XCTAssertFalse(t.summary.isEmpty, "\(t) summary")
            XCTAssertGreaterThan(t.detail.count, 60, "\(t) detail should be a real explanation")
        }
    }

    func testRosterComplete() {
        XCTAssertEqual(MusicTheoryTopic.allCases.count, 9)
        XCTAssertEqual(Set(MusicTheoryTopic.allCases),
                       [.interval, .scale, .chord, .progression, .cadence, .key, .tempo, .swing, .dynamics])
    }

    func testNoEsotericOrOverclaim() {
        let banned = ["healing", "chakra", "solfeggio", "quantum", "aura", "akasha",
                      "planetary", "cosmic", "manifest", "frequency of the universe"]
        for t in MusicTheoryTopic.allCases {
            let text = (t.summary + " " + t.detail + " " + t.title).lowercased()
            for term in banned {
                XCTAssertFalse(text.contains(term), "\(t) copy must avoid '\(term)'")
            }
        }
        let footer = MusicTheoryTopic.footer.lowercased()
        for term in banned { XCTAssertFalse(footer.contains(term), "footer must avoid '\(term)'") }
    }

    func testFooterPresent() {
        XCTAssertFalse(MusicTheoryTopic.footer.isEmpty)
    }
}
