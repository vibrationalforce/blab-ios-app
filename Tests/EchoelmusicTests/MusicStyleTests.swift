// MusicStyleTests.swift
// Echoel — the curated genre identity. Asserts each style is internally
// consistent (tempo default inside its window, beat-driven flag matches the
// transport default) and Codable.

import XCTest
@testable import Echoelmusic

final class MusicStyleTests: XCTestCase {

    func testEveryGenreIsCategorizedExactlyOnce() {
        // The `Category` grouping is the FULL taxonomy: every genre is categorised
        // exactly once (so every exhaustive switch + stored @AppStorage value stays
        // valid). NOTE: since the 2026-07-24 curation the picker shows only
        // `MusicStyle.offered`, NOT this full roster — this test guards the taxonomy,
        // `testOfferedPaletteIsCuratedAndOpensContemplative` guards what's offered.
        let grouped = MusicStyle.Category.allCases.flatMap { $0.genres }
        XCTAssertEqual(Set(grouped), Set(MusicStyle.allCases),
                       "every genre must appear in some category")
        XCTAssertEqual(grouped.count, MusicStyle.allCases.count,
                       "no genre appears in two categories (each categorised exactly once)")
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

    func testOfferedPaletteIsCuratedAndOpensContemplative() {
        // Founder 2026-07-24 "Genre is better you decide and curate something that
        // really fits the brand … Die 6 ruhigen Genres": the picker offers only a
        // curated, brand-fitting contemplative palette — decoupled from the full
        // taxonomy (which stays complete, see testEveryGenreIsCategorizedExactlyOnce).
        let offered = MusicStyle.offered
        XCTAssertFalse(offered.isEmpty, "the picker must offer at least one genre")
        XCTAssertEqual(Set(offered).count, offered.count, "offered must have no duplicates")
        XCTAssertTrue(Set(offered).isSubset(of: Set(MusicStyle.allCases)),
                      "every offered genre must be a real MusicStyle case")
        // The default genre MUST be offered, else a fresh install shows an unselected
        // picker (the stored value would be a genre the user can't see).
        XCTAssertTrue(offered.contains(StudioDefaultKeys.genre.value),
                      "the default genre must be in the offered palette")
        // ⚠️ THE PER-GENRE "drum-free OR sustained" LOOP THAT STOOD HERE IS GONE, and it was not
        // loosened to make a new commit pass — it was contradicted by a later founder ask.
        //
        // It asserted that EVERY offered genre is drum-free or a sustained Fläche. That was a
        // faithful reading of 2026-07-24 ("Die 6 ruhigen Genres"). On 2026-07-30 the founder asked
        // for the opposite in the same breath: "mehr Genres der elektronischen Musik benötigt,
        // verschiedenste Techno und House Stile aber auch Ambient und meditations Musik, Trance,
        // acid etc". ⚠️ NOT because "a techno genre cannot be a sustained Fläche" — that was the
        // first version of this note and it is false: `dubTechno` is a techno genre with
        // `sustained: true` and it satisfied the old loop. What is incompatible is the loop with
        // THESE TWO DESIGNS — an acid line is a sequence, a house chord lands on the offbeat, and
        // sustaining either would make it not-acid and not-house, i.e. the very convergence the
        // founder reported (#81, #125). So the choice was between the genres he named and a
        // test-encoded inference from an earlier curation; the named genres win.
        //
        // Two further things make the old wording stale independently of that: since #166/#167
        // there are NO drums at all, so "drum-free" describes every genre and `isBeatDriven` now
        // only means "the pad articulates rhythmically instead of holding"; and the brand line
        // (immersive · bio-reactive · contemplative, NOT wellness) is carried by what the app OPENS
        // with, not by forbidding a genre the founder named. So that is what is asserted instead:
        let defaultGenre = StudioDefaultKeys.genre.value
        XCTAssertTrue(!defaultGenre.isBeatDriven || MusicStyle.sustainedFlächen.contains(defaultGenre),
                      "the DEFAULT genre (\(defaultGenre)) must be calm — a fresh install has to "
                      + "open on a contemplative Fläche, whatever else the palette offers")
        XCTAssertTrue(offered.contains(where: { MusicStyle.sustainedFlächen.contains($0) }),
                      "the offered palette lost every sustained Fläche — the contemplative core "
                      + "is the brand, and the electronic additions sit alongside it, not over it")
        // Each category's offeredGenres is a subset of its full genres (the filter is
        // honest — it never surfaces a genre outside its own taxonomy bucket).
        for cat in MusicStyle.Category.allCases {
            XCTAssertTrue(Set(cat.offeredGenres).isSubset(of: Set(cat.genres)),
                          "\(cat).offeredGenres must be a subset of its genres")
        }
    }

    func testSustainedFlächenMatchTheSustainedProfileFlag() {
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

    func testDrumFreeStylesAreExactlyTheContemplativeSet() {
        // Audit B5: every beat-driven genre carries its groove; only the
        // contemplative genres stay drum-free by design. Widened by G2 (founder
        // 2026-07-24 "erfinde noch passende dazu. Ambient-Meditation-drift-
        // contemplation") — new ambient-family genres are `.none`-beat Flächen, so
        // this set grows as they're added (see the offered-palette test comment).
        // ⚠️ THIS LITERAL WENT STALE THE MOMENT #254 batch 2 ADDED TWO AMBIENT GENRES, and the
        // comment above already anticipated growth ("this set grows as they're added") while the
        // assertion was a hard list — so it reddened, in a suite that cannot fail a merge (#208).
        // Extended rather than loosened: the invariant that matters is "drum-free == the
        // contemplative family plus classical", and naming the members is what makes a new
        // beat-driven genre sneaking into `.none` visible.
        let drumFree = MusicStyle.allCases.filter { !$0.isBeatDriven }
        XCTAssertEqual(Set(drumFree),
                       [.classical, .stillMeditation, .selfObservation, .drift, .contemplation,
                        .deepDrone, .ambientPulse],
                       "drum-free = classical + the contemplative family (meditation, "
                       + "self-observation, drift, contemplation, deep drone, ambient pulse), "
                       + "nothing else")
        // The two signature beats keep their hand-built builders.
        XCTAssertEqual(MusicStyle.dubTechno.beatArchetype, .signature)
        XCTAssertEqual(MusicStyle.trap.beatArchetype, .signature)
    }

    func testDriftIsADistinctContemplativeFläche() {
        // G2 (founder 2026-07-24): "Drift" must be a real contemplative Fläche that
        // does NOT collide with the two existing drum-free Flächen — the whole point
        // is to add variety without re-triggering the "everything sounds the same"
        // convergence. Assert its identity + that it differs on scale/register from
        // the sibling ambient genres.
        let drift = MusicStyle.drift
        let p = drift.harmonicProfile
        XCTAssertEqual(drift.category, .meditative, "drift belongs to the calm meditative world")
        XCTAssertFalse(drift.isBeatDriven, "drift is a drum-free Fläche")
        XCTAssertTrue(p.sustained, "drift holds — it's a Fläche, not a pulse")
        XCTAssertEqual(p.leadDensity, 0, "pure Fläche — no auto lead")
        XCTAssertFalse(p.arpeggiated, "held pad, not an arpeggio")
        XCTAssertEqual(drift.defaultMode, .flowFree, "an ambient genre follows the heart (Flow)")
        XCTAssertTrue(MusicStyle.offered.contains(drift), "drift is offered in the curated palette")
        // Airier than the darker siblings: it floats a register above them.
        XCTAssertGreaterThan(p.padOctave, MusicStyle.selfObservation.harmonicProfile.padOctave,
                             "drift floats above self-observation")
        XCTAssertGreaterThan(p.padOctave, MusicStyle.stillMeditation.harmonicProfile.padOctave,
                             "drift floats above deep-ambient")
        // Distinct modal colour from both siblings (no shared scale collision).
        XCTAssertNotEqual(drift.scale, MusicStyle.selfObservation.scale)
        XCTAssertNotEqual(drift.scale, MusicStyle.stillMeditation.scale)
        // Calm at the source: the tempo window tops out slow, like the other Flächen.
        XCTAssertLessThanOrEqual(drift.tempoRange.upperBound, 78)
    }

    func testContemplationIsADistinctGroundedFläche() {
        // G2 (founder 2026-07-24): "Contemplation" is the grounded/low pole of the
        // ambient family — it must be a real contemplative Fläche AND stay distinct
        // from BOTH the darker siblings and its airy sibling Drift, so no convergence.
        let c = MusicStyle.contemplation
        let p = c.harmonicProfile
        XCTAssertEqual(c.category, .meditative)
        XCTAssertFalse(c.isBeatDriven, "contemplation is a drum-free Fläche")
        XCTAssertTrue(p.sustained)
        XCTAssertEqual(p.leadDensity, 0, "pure Fläche — no auto lead")
        XCTAssertFalse(p.arpeggiated)
        XCTAssertEqual(c.defaultMode, .flowFree, "an ambient genre follows the heart (Flow)")
        XCTAssertTrue(MusicStyle.offered.contains(c), "contemplation is offered in the curated palette")
        // Grounded, not airy: it sits a register BELOW Drift (the opposite pole).
        XCTAssertLessThan(p.padOctave, MusicStyle.drift.harmonicProfile.padOctave,
                          "contemplation sits below drift (grounded vs airy)")
        // Distinct modal colour from drift and both darker siblings.
        for other in [MusicStyle.drift, .selfObservation, .stillMeditation] {
            XCTAssertNotEqual(c.scale, other.scale, "contemplation must not share \(other)'s scale")
        }
        // Slowest, calmest window of the family.
        XCTAssertLessThanOrEqual(c.tempoRange.upperBound, 78)
    }

    func testNoGenreAutoGeneratesLeadNotes() {
        // Founder 2026-07-21: "Die Genres Psytrance bis Rocksteady werden sehr
        // stressig wegen den Melodien. Melodien sollen die Leute selbst machen." —
        // extended (Council, same day) from the named 17-genre range to every
        // remaining melodic genre, so the invariant is uniform and not a partial
        // list a future genre could silently fall outside of. BioComposer gates
        // its whole lead-generation path behind `leadDensity > 0`, so this asserts
        // that NO genre auto-generates a lead melody.
        // ⚠️ It is NO LONGER "the single authoritative place" (it said so until
        // 2026-07-30): `Tests/CISmoke/LeadRoleAbsenceTests` now asserts the same
        // invariant in the BLOCKING bundle, and carries the checklist of the five
        // dormant paths that wake if a genre sings again. This copy is the
        // non-blocking twin — it cannot fail a merge (#208), which is exactly how
        // #253 A5 came to be built straight against an invariant already asserted
        // here. Keep both; when the founder answers #255, update BOTH.
        // The per-genre lead PATCH (leadPatchName) is untouched — a user
        // still plays their own melody on that genre's warm timbre.
        for style in MusicStyle.allCases {
            XCTAssertEqual(style.harmonicProfile.leadDensity, 0,
                           "\(style): leadDensity must be 0 — melodies are user-performed, not auto-generated")
        }
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
        XCTAssertNotEqual(p.progression, MusicStyle.stillMeditation.harmonicProfile.progression)
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
