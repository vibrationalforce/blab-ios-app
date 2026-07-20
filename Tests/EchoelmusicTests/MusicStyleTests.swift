// MusicStyleTests.swift
// Echoel — the curated genre identity. Asserts each style is internally
// consistent (tempo default inside its window, beat-driven flag matches the
// transport default) and Codable.

import XCTest
@testable import Echoelmusic

final class MusicStyleTests: XCTestCase {

    func testEveryGenreIsOfferedInExactlyOneCategory() {
        // Founder 2026-07-11 "Alles rein. Logisch sortiert. Gehe tief rein": every
        // genre is now offered, grouped into exactly one logical category — the picker
        // shows the full roster, sorted by sound-world.
        let grouped = MusicStyle.Category.allCases.flatMap { $0.genres }
        XCTAssertEqual(Set(grouped), Set(MusicStyle.allCases),
                       "every genre must appear in some category")
        XCTAssertEqual(grouped.count, MusicStyle.allCases.count,
                       "no genre appears in two categories (each offered exactly once)")
        // The `category` property agrees with the category's own genre list.
        for cat in MusicStyle.Category.allCases {
            for s in cat.genres {
                XCTAssertEqual(s.category, cat, "\(s).category must match the group it is listed in")
            }
        }
        // The calm meditative set stays FIRST so the relaxation identity leads.
        XCTAssertEqual(MusicStyle.Category.allCases.first, .meditative,
                       "meditative genres are listed first")
    }

    func testSustainedFlächenAreExactlyTheSixCalmGenres() {
        // The sustained Flächen (calm, one chord per bar, NO lead) are an invariant
        // decoupled from the offered roster since 2026-07-11. Source of truth = the
        // `sustained` profile flag.
        let sustained = MusicStyle.allCases.filter { $0.harmonicProfile.sustained }
        XCTAssertEqual(Set(sustained), Set(MusicStyle.sustainedFlächen),
                       "sustainedFlächen must equal the genres whose profile is sustained")
        for s in MusicStyle.sustainedFlächen {
            let p = s.harmonicProfile
            XCTAssertTrue(p.sustained, "\(s) must be a sustained Fläche")
            XCTAssertEqual(p.leadDensity, 0,
                           "\(s) carries NO lead melody (got leadDensity \(p.leadDensity))")
            XCTAssertFalse(p.arpeggiated, "\(s): a Fläche holds, it doesn't rattle")
        }
    }

    func testSustainedFlächenStayDistinct() {
        // Each Fläche keeps its own character — no two share the same
        // (scale, progression, voicing, register) fingerprint.
        var fingerprints = Set<String>()
        for s in MusicStyle.sustainedFlächen {
            let p = s.harmonicProfile
            let f = "\(s.scale)|\(p.progression)|\(p.chordTones)|\(p.padOctave)"
            XCTAssertTrue(fingerprints.insert(f).inserted,
                          "\(s) duplicates another Fläche's sound fingerprint (\(f))")
        }
    }

    func testEveryGenreHasADistinctMusicalIdentity() {
        // Durable guard for founder 2026-07-20 "die Genres klingen teilweise gleich":
        // no two genres may share their whole harmonic+rhythmic DNA — the scale, the
        // chord progression, the chord voicing AND the groove skeleton. A collision
        // means two genres would generate structurally identical starting material;
        // this test makes "genres stay distinct" a property no future edit can quietly
        // break (it holds today — every genre differs on at least one axis).
        var seen: [String: MusicStyle] = [:]
        for s in MusicStyle.allCases {
            let p = s.harmonicProfile
            let fingerprint = "\(s.scale)|\(p.progression)|\(p.chordTones)|\(s.beatArchetype)"
            if let other = seen[fingerprint] {
                XCTFail("\(s) and \(other) share an identical musical identity (\(fingerprint)) — differentiate one axis")
            }
            seen[fingerprint] = s
        }
        XCTAssertEqual(seen.count, MusicStyle.allCases.count,
                       "every genre must carry a unique scale·progression·voicing·groove fingerprint")
    }

    func testRockGenresUseRealPowerChords() {
        // Founder 2026-07-11 "Rockakkorde": the rock family voices a real power chord
        // (root + fifth + octave root), not a bare dyad.
        for s in [MusicStyle.rock, .punk, .heavyMetal, .doom] {
            XCTAssertEqual(s.harmonicProfile.chordTones, [0, 4, 7],
                           "\(s) must voice a full power chord [root, fifth, octave]")
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

    func testSelfObservationIsACalmMovingFläche() {
        // Founder 2026-07-11 (SUPERSEDES the 2026-07-07 "one frozen tonic" law): "es
        // soll ja weitergehen und sich mit dem Herzschlag weiterentwickeln" — the
        // single-chord drone [0] is exactly what "bleibt auf der Fläche liegen". The
        // Fläche now carries a gentle multi-chord JOURNEY (still sustained, still NO
        // lead), holding ONE chord per bar but advancing WHICH chord with the
        // bio-cadenced evolve (BioComposer.progressionPhase). Calm is preserved by
        // sustained + lead-free + a slow tempo window, not by freezing the harmony.
        let p = MusicStyle.selfObservation.harmonicProfile
        XCTAssertGreaterThan(p.progression.count, 1,
                             "the Fläche must travel through >1 chord — not freeze on the tonic")
        XCTAssertEqual(p.progression.first, 0, "still opens on the tonic (coherent start)")
        XCTAssertEqual(p.leadDensity, 0, "pure Fläche — no lead/melody line")
        XCTAssertFalse(p.arpeggiated, "sustained pad, not an arpeggio")
        XCTAssertTrue(p.sustained, "held pads (one chord per bar), not a busy pulse")
        XCTAssertTrue(p.chordTones.contains(6), "lush open 7th voicing for a wide, warm pad")
        // Still distinct from the other curated Flächen's journeys.
        XCTAssertNotEqual(p.progression, MusicStyle.dubTechno.harmonicProfile.progression)
        XCTAssertNotEqual(p.progression, MusicStyle.esotericMeditation.harmonicProfile.progression)
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
