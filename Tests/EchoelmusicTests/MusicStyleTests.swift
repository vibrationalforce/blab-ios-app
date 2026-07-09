// MusicStyleTests.swift
// Echoel — the curated genre identity. Asserts each style is internally
// consistent (tempo default inside its window, beat-driven flag matches the
// transport default) and Codable.

import XCTest
@testable import Echoelmusic

final class MusicStyleTests: XCTestCase {

    func testStyleRoster() {
        // The FULL case list stays for Codable/persistence stability (retired
        // genres keep compiling); the PICKER offers only the curated roster
        // (founder 2026-07-08: "Alle Genres smooth und wirklich zum Chillen
        // und Meditieren machen oder raus damit").
        XCTAssertEqual(MusicStyle.curated, [
            .selfObservation, .esotericMeditation, .vaporwave,
            .dubTechno, .trap, .sciFi
        ])
        XCTAssertTrue(Set(MusicStyle.curated).isSubset(of: Set(MusicStyle.allCases)))
    }

    func testCuratedRoster_isActuallyCalm() {
        // Founder 2026-07-09: "die Melodie … besser wenn die komplett weg sind …
        // nur chillige mystische Flächen". Every offered genre is now a PURE
        // sustained Fläche — NO lead line at all (the pure-wave lead tones stuck
        // out of the mix), stillness held whatever the body does.
        for s in MusicStyle.curated {
            let p = s.harmonicProfile
            XCTAssertTrue(p.sustained, "\(s) must be a sustained Fläche")
            XCTAssertEqual(p.leadDensity, 0,
                           "\(s) carries NO lead melody (got leadDensity \(p.leadDensity))")
            XCTAssertFalse(p.arpeggiated, "\(s): a Fläche holds, it doesn't rattle")
        }
    }

    func testCuratedFlächenStayDistinct() {
        // "passende Presets für Genres": each Fläche keeps its own character —
        // no two curated genres share the same (scale, progression, voicing,
        // register) fingerprint even with the leads gone.
        var fingerprints = Set<String>()
        for s in MusicStyle.curated {
            let p = s.harmonicProfile
            let f = "\(s.scale)|\(p.progression)|\(p.chordTones)|\(p.padOctave)"
            XCTAssertTrue(fingerprints.insert(f).inserted,
                          "\(s) duplicates another curated genre's sound fingerprint (\(f))")
        }
    }

    func testDrumFreeStylesAreExactlyTheContemplativeThree() {
        // Audit B5: every beat-driven genre carries its groove; only the
        // contemplative genres stay drum-free by design.
        let drumFree = MusicStyle.allCases.filter { !$0.isBeatDriven }
        XCTAssertEqual(Set(drumFree), [.classical, .esotericMeditation, .selfObservation],
                       "drum-free = classical + meditation + self-observation, nothing else")
        // The two signature beats keep their hand-built builders.
        XCTAssertEqual(MusicStyle.dubTechno.beatArchetype, .signature)
        XCTAssertEqual(MusicStyle.trap.beatArchetype, .signature)
    }

    func testEveryHarmonicGenreVoicesAChord() {
        // Every genre except the two bespoke-melody signature beats and
        // self-observation voices its harmony through harmonicProfile — the
        // archetype-beat genres (rock, disco, …) DO use it.
        for style in MusicStyle.allCases
        where style.beatArchetype != .signature && style != .selfObservation {
            let p = style.harmonicProfile
            XCTAssertFalse(p.chordTones.isEmpty, "\(style) needs chord tones")
            XCTAssertFalse(p.progression.isEmpty, "\(style) needs a progression")
            XCTAssertGreaterThanOrEqual(p.leadDensity, 0)
            XCTAssertLessThanOrEqual(p.leadDensity, 1)
        }
    }

    func testSelfObservationIsATrueDrone() {
        // Founder 2026-07-07: the Fläche must be "sphärisch und beruhigend … reine
        // meditative Flächen … kohärentes Timbre am Start". A drone = one sustained
        // tonic (no chord movement) and NO lead line, so the take opens still and
        // coherent instead of noodling a melody over a chord change.
        let p = MusicStyle.selfObservation.harmonicProfile
        XCTAssertEqual(p.progression, [0], "a drone holds ONE tonic — no chord movement")
        XCTAssertEqual(p.leadDensity, 0, "pure Fläche — no lead/melody line")
        XCTAssertFalse(p.arpeggiated, "sustained pad, not an arpeggio")
        XCTAssertTrue(p.chordTones.contains(6), "lush open 7th voicing for a wide, still pad")
        // It must NOT share dub/trap's melody-over-chord-change profile any more.
        XCTAssertNotEqual(p.progression, MusicStyle.dubTechno.harmonicProfile.progression)
        // Still calm at the source: the tempo window tops out slow.
        XCTAssertLessThanOrEqual(MusicStyle.selfObservation.tempoRange.upperBound, 78)
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
