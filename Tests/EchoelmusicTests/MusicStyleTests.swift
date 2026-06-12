// MusicStyleTests.swift
// Echoel — the curated genre identity. Asserts each style is internally
// consistent (tempo default inside its window, beat-driven flag matches the
// transport default) and Codable.

import XCTest
@testable import Echoelmusic

final class MusicStyleTests: XCTestCase {

    func testStyleRoster() {
        XCTAssertEqual(MusicStyle.allCases.count, 12)
        // The requested genres are all present.
        let required: Set<MusicStyle> = [
            .dubTechno, .trap, .vaporwave, .eighties, .disco, .synthwave,
            .earlySynth, .futuristic, .sciFi, .psytrance, .esotericMeditation, .selfObservation
        ]
        XCTAssertTrue(required.isSubset(of: Set(MusicStyle.allCases)))
    }

    func testOnlyTwoStylesAreBeatDriven() {
        let beat = MusicStyle.allCases.filter { $0.isBeatDriven }
        XCTAssertEqual(Set(beat), [.dubTechno, .trap],
                       "all genres except Dub Techno and Trap are non-beat material")
    }

    func testEveryHarmonicGenreVoicesAChord() {
        // Non-beat, non-self genres must produce a usable chord (>= 1 tone) and a
        // valid progression.
        for style in MusicStyle.allCases where !style.isBeatDriven && style != .selfObservation {
            let p = style.harmonicProfile
            XCTAssertFalse(p.chordTones.isEmpty, "\(style) needs chord tones")
            XCTAssertFalse(p.progression.isEmpty, "\(style) needs a progression")
            XCTAssertGreaterThanOrEqual(p.leadDensity, 0)
            XCTAssertLessThanOrEqual(p.leadDensity, 1)
        }
    }

    func testEveryStyleHasTitleAndLineage() {
        for style in MusicStyle.allCases {
            XCTAssertFalse(style.displayName.isEmpty, "\(style) needs a title")
            XCTAssertFalse(style.lineage.isEmpty, "\(style) needs a lineage subtitle")
        }
    }

    /// Subtitles must stay descriptive — no real artist / label / film names
    /// (App Store-safe, no implied endorsement).
    func testNoArtistNamesInSubtitles() {
        let banned = ["moritz", "oswald", "echochord", "basic channel", "808 mafia",
                      "southside", "metro boomin", "carpenter", "kavinsky",
                      "tangerine", "klaus schulze", "blade runner", "steve roach"]
        for style in MusicStyle.allCases {
            let text = (style.displayName + " " + style.lineage).lowercased()
            for name in banned {
                XCTAssertFalse(text.contains(name), "\(style) subtitle must not name an artist (\(name))")
            }
        }
    }

    func testDefaultTempoIsInsideTheWindow() {
        for style in MusicStyle.allCases {
            XCTAssertTrue(style.tempoRange.contains(style.defaultTempo),
                          "\(style): default tempo \(style.defaultTempo) outside \(style.tempoRange)")
        }
    }

    func testGenreTempoWindowsAreDistinctAndOrdered() {
        XCTAssertEqual(MusicStyle.dubTechno.tempoRange, 118...128)
        XCTAssertEqual(MusicStyle.trap.tempoRange, 130...150)
        // Dub sits below trap — no overlap.
        XCTAssertLessThan(MusicStyle.dubTechno.tempoRange.upperBound,
                          MusicStyle.trap.tempoRange.lowerBound)
    }

    func testBeatDrivenMatchesTransportDefault() {
        XCTAssertTrue(MusicStyle.dubTechno.isBeatDriven)
        XCTAssertTrue(MusicStyle.trap.isBeatDriven)
        XCTAssertFalse(MusicStyle.selfObservation.isBeatDriven)

        XCTAssertEqual(MusicStyle.dubTechno.defaultMode, .studioLocked)
        XCTAssertEqual(MusicStyle.trap.defaultMode, .studioLocked)
        XCTAssertEqual(MusicStyle.selfObservation.defaultMode, .flowFree)
    }

    func testScalesAreGenreAppropriate() {
        XCTAssertEqual(MusicStyle.dubTechno.scale, .dorian)
        XCTAssertEqual(MusicStyle.trap.scale, .harmonicMinor)
        XCTAssertEqual(MusicStyle.selfObservation.scale, .minor)
    }

    func testCodableRoundTrip() throws {
        for style in MusicStyle.allCases {
            let data = try JSONEncoder().encode(style)
            let decoded = try JSONDecoder().decode(MusicStyle.self, from: data)
            XCTAssertEqual(decoded, style)
        }
    }
}
