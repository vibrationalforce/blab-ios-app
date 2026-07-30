// GenreFamilyDistinctnessTests.swift
// Echoel — a new genre must SOUND like a new genre. Blocking bundle (#254).
//
// ⭐ WHY THIS EXISTS, and why it is the gate on every future genre batch. The founder has told this
// project twice that its genres collapse into one another — #81 ("erst eine individuelle Variation
// und dann klingt plötzlich alles gleich") and #125, which ended with him curating the offered
// roster down to EIGHT genres by ear. So "add more genres" (founder 2026-07-30: "mehr Genres der
// elektronischen Musik benötigt, verschiedenste Techno und House Stile aber auch Ambient und
// meditations Musik, Trance, acid") is one careless commit away from being the very defect he
// complained about: more options that sound the same.
//
// A copy-pasted genre — same articulation, same scale, same voicing, same register — cannot be
// caught by a compiler and cannot be heard in CI. It CAN be caught structurally, and that is all
// this file does: it pins that every OFFERED genre differs from every other on the axes that are
// actually audible today, and it says plainly which axes those are.
//
// ⚠️ WHICH AXES ARE AUDIBLE — this is the non-obvious part, and getting it wrong would make the
// test theatre. Since #166/#167 removed the drums, `beatArchetype` and `beatFlavor` (hatRate,
// percGhostStep, kickCell) produce `drumSteps` that reach NO voice — `BioComposer` still computes
// them and only `BioVariationMaze` reads them, for a metric. So the archetype's one remaining
// audible consequence is `chordArticulation` (sustained / stab / skank / comp), which decides when
// the pad speaks. A genre differentiated ONLY by its drum pattern would be silent-identical to its
// neighbour, and this test would rightly still fail it.
//
// What the test does NOT do: judge whether any of it sounds GOOD. That is the founder's ear, and
// it is the reason every genre batch ships with an explicit listening item rather than a claim.

import XCTest
@testable import Echoelmusic

final class GenreFamilyDistinctnessTests: XCTestCase {

    /// The audible fingerprint of a genre, as of 2026-07-30. Drums are deliberately absent — see
    /// the file header. Tempo is deliberately absent too: `dubTechno` (118…128) and `deepHouse`
    /// (120…126) really are both ~124 genres, and forcing disjoint tempo windows would push new
    /// genres into wrong tempos to satisfy a test. Tempo is a *hint*, not an identity.
    private struct Fingerprint: Hashable, CustomStringConvertible {
        let articulation: String
        let scale: String
        let progression: [Int]
        let chordTones: [Int]
        let padOctave: Int
        let arpeggiated: Bool
        let sustained: Bool

        var description: String {
            "\(articulation)/\(scale)/prog\(progression)/tones\(chordTones)"
            + "/oct\(padOctave)\(arpeggiated ? "/arp" : "")\(sustained ? "/sus" : "")"
        }
    }

    private func fingerprint(_ style: MusicStyle) -> Fingerprint {
        let p = style.harmonicProfile
        return Fingerprint(articulation: "\(style.chordArticulation)",
                           scale: "\(style.scale)",
                           progression: p.progression,
                           chordTones: p.chordTones,
                           padOctave: p.padOctave,
                           arpeggiated: p.arpeggiated,
                           sustained: p.sustained)
    }

    /// ⛔ NO TWO OFFERED GENRES MAY SHARE AN AUDIBLE FINGERPRINT. This is the #81/#125 guard.
    ///
    /// Scoped to `offered` and not `allCases` on purpose: seven electronic genres were curated OUT
    /// by ear on 2026-07-24 and are unreachable in the picker, so whether two of THEM collide is
    /// not a user-visible defect and pinning it would block a future re-offer for the wrong reason.
    /// The moment a genre is added to `offered`, it comes under this assertion.
    func testNoTwoOfferedGenresShareAnAudibleFingerprint() {
        var seen: [Fingerprint: MusicStyle] = [:]
        for style in MusicStyle.offered {
            let fp = fingerprint(style)
            if let clash = seen[fp] {
                XCTFail("""
                    \(style.rawValue) and \(clash.rawValue) are audibly the same genre: \(fp).
                    Drums do not count (they make no sound since #166/#167) — differentiate on
                    articulation, scale, progression, voicing, register, arp or sustain.
                    """)
            }
            seen[fp] = style
        }
        XCTAssertEqual(seen.count, MusicStyle.offered.count)
    }

    /// The #254 batch-1 pair, asserted against each other and against the genre they were designed
    /// as poles of. Separate from the sweep above because THIS is the design intent — the sweep
    /// would still pass if acid and house differed on one incidental field.
    func testTheAcidAndHouseAdditionsArePolesNotVariants() {
        let acid = fingerprint(.acidTechno)
        let house = fingerprint(.deepHouse)
        let dub = fingerprint(.dubTechno)

        // Every axis the two new genres were designed to differ on. Each line is a claim the
        // design makes; if one flips, the pair has drifted toward each other.
        // ⚠️ THIS AXIS IS ONLY HALF AUDIBLE, and saying so is the point of the comment.
        // `deepHouse` genuinely skanks: non-arp + non-sustained reaches the chop branch of
        // `composeHarmonic`, which reads the articulation. `acidTechno` does NOT stab —
        // arpeggiated profiles take the arp branch, which never reads it, so acid's `.stab`
        // is inert. The assertion is kept because the values differing is still the
        // precondition for house's half being heard, and because if acid ever loses
        // `arpeggiated` this axis wakes up. It is NOT evidence that the two differ rhythmically.
        XCTAssertNotEqual(acid.articulation, house.articulation,
                          "house skanks on the OFFBEAT and acid does not — that was the point "
                          + "(acid's own articulation is inert while it stays arpeggiated)")
        XCTAssertNotEqual(acid.scale, house.scale)
        XCTAssertNotEqual(acid.chordTones, house.chordTones, "acid is a raw triad, house a lush 7th")
        XCTAssertNotEqual(acid.padOctave, house.padOctave, "acid sits low, house one octave up")
        XCTAssertTrue(acid.arpeggiated, "acidTechno IS a sequence — that is what makes it acid")
        XCTAssertFalse(house.arpeggiated, "deepHouse holds its chord")
        XCTAssertNotEqual(MusicStyle.acidTechno.swing, MusicStyle.deepHouse.swing,
                          "house swings, the 303 does not")

        // And neither may collapse onto dubTechno, the only electronic genre offered before them.
        XCTAssertNotEqual(acid.articulation, dub.articulation)
        XCTAssertNotEqual(house.articulation, dub.articulation)
        XCTAssertFalse(acid.sustained, "a sustained acid genre would be a Fläche, not a sequence")
        XCTAssertFalse(house.sustained, "sustained suppresses the offbeat skank that makes it house")
        XCTAssertTrue(dub.sustained, "dubTechno is the Fläche pole — if this flipped, re-check all three")
    }

    /// ⛔ THE NEAR-TWIN GUARD, and the one assertion here that the offered-only sweep above cannot
    /// make. `psytrance` is phrygian, arpeggiated AND four-on-the-floor — exactly like the new
    /// `acidTechno` — but it is NOT in `offered`, so the sweep never compares them and a real
    /// collision could ship unnoticed. That nearly happened: acid's first FX draft was a ping-pong
    /// sixteenth delay, character-for-character psytrance's preset.
    ///
    /// So the two are pinned apart on every axis the design uses, including the FX axis the sweep's
    /// fingerprint does not model. This test is scoped to ONE pair on purpose — a general
    /// "every case must differ on FX too" rule would be a much bigger claim than the roster can
    /// currently honour, and asserting it would either fail today or have to be watered down.
    func testAcidTechnoIsNotPsytranceWithASecondChord() {
        XCTAssertNotEqual(fingerprint(.acidTechno), fingerprint(.psytrance))
        // Disjoint tempo windows — the cheapest audible separation of two same-scale sequences.
        XCTAssertTrue(MusicStyle.acidTechno.tempoRange.upperBound
                      <= MusicStyle.psytrance.tempoRange.lowerBound,
                      "acid (\(MusicStyle.acidTechno.tempoRange)) must stay below psytrance "
                      + "(\(MusicStyle.psytrance.tempoRange)) — they share scale, arp and archetype")
        XCTAssertNotEqual(MusicStyle.acidTechno.harmonicProfile.padOctave,
                          MusicStyle.psytrance.harmonicProfile.padOctave)
        // The FX axis: the resonant chain filter is acid's signature and nothing else may claim it,
        // because it is the only thing that makes acid unmistakable rather than merely slower.
        XCTAssertTrue(MusicStyle.acidTechno.fxPreset.filterEnabled,
                      "acidTechno lost its resonant filter — without it, it is psytrance at 134")
        for style in MusicStyle.allCases where style != .acidTechno {
            XCTAssertFalse(style.fxPreset.filterEnabled,
                           "\(style.rawValue) now also enables the chain filter. That was acid's "
                           + "one unmistakable signature; either give acid a new one or accept that "
                           + "the two genres have converged.")
        }
        XCTAssertNotEqual(MusicStyle.acidTechno.fxPreset.delayMode,
                          MusicStyle.psytrance.fxPreset.delayMode,
                          "acid slaps a digital eighth, psytrance rolls a ping-pong sixteenth")
    }

    /// ⛔ THE SECOND NEAR-TWIN, and the reason the sweep above is NOT sufficient on its own.
    /// `deepHouse` first shipped as minor / [0, 5, 3] / [0, 2, 4, 6] — note-for-note
    /// `selfObservation`'s scale, progression AND voicing. Both are `offered`, so the sweep DID
    /// compare them, and it passed: articulation, register and the sustain flag all differed. But
    /// "the test passes" and "a listener can tell them apart" are not the same claim, and the
    /// founder's complaint (#81, #125) is about the second one. Two offered genres sharing their
    /// entire harmonic core is a convergence smell even when the sweep is satisfied.
    ///
    /// So the harmonic core — scale + progression + chord tones — is pinned as its own axis for
    /// the pair. A future genre may legitimately re-use one of the three; re-using all three is
    /// what this forbids.
    func testDeepHouseDoesNotBorrowTheCalmFlaecheHarmony() {
        let house = MusicStyle.deepHouse.harmonicProfile
        let calm = MusicStyle.selfObservation.harmonicProfile
        XCTAssertEqual(MusicStyle.deepHouse.scale, MusicStyle.selfObservation.scale,
                       "both are minor — if that changes this test is checking the wrong pair, "
                       + "and the harmonic-core clash it guards no longer exists")
        XCTAssertFalse(house.progression == calm.progression
                       && house.chordTones == calm.chordTones,
                       "deepHouse and selfObservation now share scale, progression AND voicing. "
                       + "Only articulation and register would separate the house genre from the "
                       + "flagship calm Fläche — change one of the three.")
    }

    /// ⭐ #254 BATCH 2 — the ambient pair, and the one claim in this batch that is a MECHANISM
    /// rather than a preference. `ambientPulse` and `acidTechno` are both arpeggiated, so neither
    /// reads `chordArticulation` (that was batch 1's correction). What decides their audible note
    /// RATE is `arpStep = (busy ? 2 : 4) * (tempoDensityScale(bpm) < 0.8 ? 2 : 1)`. The doubling
    /// switches on above ~106 BPM. `ambientPulse`'s whole window must therefore stay under it and
    /// `acidTechno`'s must stay over it — otherwise the two arp genres emit the same rate and the
    /// slow one stops being slow.
    ///
    /// This asserts the tempo windows rather than calling the private composer, because the window
    /// is the thing a future edit would change: widening `ambientPulse` past ~106 would silently
        /// halve its note count with no other symptom. The threshold is 110 BPM today; the test
    /// re-derives it from `tempoDensityScale` rather than hardcoding it, so a change to the
    /// curve moves the assertion with it instead of quietly invalidating it.
    func testTheTwoArpGenresSitOnOppositeSidesOfTheArpCoarseningThreshold() {
        // The boundary, re-derived from the composer's own rule rather than hardcoded: the lowest
        // BPM at which `tempoDensityScale` drops under 0.8 and `arpStep` doubles.
        let threshold = (60...200).first { BioComposer.tempoDensityScale(bpm: Double($0)) < 0.8 }
        XCTAssertNotNil(threshold, "tempoDensityScale never drops below 0.8 in 60…200 BPM — the "
                        + "arp-coarsening rule this test is built on has changed")
        guard let threshold else { return }

        let pulse = MusicStyle.ambientPulse.tempoRange
        XCTAssertLessThan(pulse.upperBound, Double(threshold),
                          "ambientPulse's window reaches \(pulse.upperBound) BPM, at or past the "
                          + "arp-coarsening threshold \(threshold). Above it `arpStep` doubles and "
                          + "the slow hypnotic sequence silently becomes half as dense — the one "
                          + "thing that distinguishes it from acidTechno. Keep the window below it.")
        let acid = MusicStyle.acidTechno.tempoRange
        XCTAssertGreaterThanOrEqual(acid.lowerBound, Double(threshold),
                                    "acidTechno's window starts at \(acid.lowerBound), below the "
                                    + "threshold \(threshold) — part of its range would now emit "
                                    + "the same arp rate as ambientPulse.")
        // Both are arpeggiated: that is the precondition for any of the above mattering.
        XCTAssertTrue(MusicStyle.ambientPulse.harmonicProfile.arpeggiated)
        XCTAssertTrue(MusicStyle.acidTechno.harmonicProfile.arpeggiated)
    }

    /// The ambient pair against the six calm genres that predate it. The sweep already forbids a
    /// full fingerprint collision; this pins the DESIGN — each of the two was added because it
    /// occupies territory no existing Fläche does, and if that stops being true the reason to have
    /// them is gone.
    func testTheAmbientAdditionsOccupyTerritoryNoFlaecheAlreadyHas() {
        // Both use a pentatonic scale, and they are the only two genres in the roster that do.
        // Every other genre is a 7-note mode, so no existing genre can be tension-free.
        let pentatonic: Set<Scale> = [.pentatonicMinor, .pentatonicMajor]
        let users = MusicStyle.allCases.filter { pentatonic.contains($0.scale) }
        XCTAssertEqual(Set(users), Set([MusicStyle.deepDrone, .ambientPulse]),
                       "the pentatonic scales are no longer exclusive to the ambient pair "
                       + "(\(users.map { $0.rawValue })) — that exclusivity is why they read as a "
                       + "different sound world rather than a seventh variation")

        // deepDrone is the LOWEST offered genre and the only offered one that never travels.
        let drone = MusicStyle.deepDrone.harmonicProfile
        XCTAssertEqual(drone.progression.count, 1,
                       "deepDrone gained a chord progression. Not moving at all is its identity — "
                       + "selfObservation is already the calm genre that travels (i–VI–iv).")
        for other in MusicStyle.offered where other != .deepDrone {
            XCTAssertGreaterThan(other.harmonicProfile.padOctave, drone.padOctave,
                                 "\(other.rawValue) now sits at or below deepDrone's register; "
                                 + "being the lowest offered genre is part of what makes it a drone")
        }
        // Its quartal voicing is not a triad or a 7th — the two shapes every other genre uses.
        XCTAssertFalse(drone.chordTones == [0, 2, 4] || drone.chordTones == [0, 2, 4, 6],
                       "deepDrone's voicing collapsed onto the roster's standard triad/7th")

        // ambientPulse is the calm family's only MOVING genre, and must not become a Fläche.
        XCTAssertTrue(MusicStyle.ambientPulse.harmonicProfile.arpeggiated)
        XCTAssertFalse(MusicStyle.ambientPulse.harmonicProfile.sustained,
                       "ambientPulse became sustained — that flag suppresses the inner pulse and "
                       + "the walking bass, i.e. it deletes the sequence that IS this genre")
        XCTAssertFalse(MusicStyle.sustainedFlächen.contains(.ambientPulse))
        XCTAssertTrue(MusicStyle.sustainedFlächen.contains(.deepDrone))

        // Both are breath-paced, not grid-locked. `defaultMode` ends in `default: .studioLocked`,
        // so this is the assertion that catches a new calm genre being silently grid-locked.
        for style in [MusicStyle.deepDrone, .ambientPulse] {
            XCTAssertEqual(style.defaultMode, .flowFree,
                           "\(style.rawValue) defaults to a locked grid tempo. It is an ambient "
                           + "genre; `defaultMode`'s `default:` arm is .studioLocked, so it has to "
                           + "be listed explicitly.")
            XCTAssertEqual(style.beatArchetype, .none, "\(style.rawValue) is drum-free by design")
        }
    }

    /// A new genre is worthless if the picker never shows it. This is the doorless-feature guard:
    /// the founder ASKED for these two, so being merely categorised is not enough.
    func testTheNewGenresAreReachableInThePicker() {
        for style in [MusicStyle.acidTechno, .deepHouse, .deepDrone, .ambientPulse] {
            XCTAssertTrue(MusicStyle.offered.contains(style),
                          "\(style.rawValue) is built but not offered — a doorless genre")
            XCTAssertTrue(style.category.offeredGenres.contains(style),
                          "\(style.rawValue) is offered but its category does not list it, so the "
                          + "picker section it belongs to will not show it")
            XCTAssertEqual(style.category,
                           style == .deepDrone || style == .ambientPulse
                               ? .meditative : .electronic)
        }
    }

    /// Every genre must be complete across the totals a listener depends on — no zero tempo, no
    /// empty progression, a patch whose stable identity actually parses. That last one is not
    /// hypothetical: `GenrePatches.patch(_:)` interpolates its suffix into
    /// "00000000-0000-0000-0000-0000000000\(suffix)", so a suffix that is not exactly two hex
    /// digits makes `UUID(uuidString:)` return nil and the `?? UUID()` fallback mints a RANDOM id
    /// on every call — silently destroying the stable patch identity the helper exists to provide.
    /// The #254 batch shipped "D26"/"D27" for one draft and would have done exactly that.
    func testEveryOfferedGenreIsCompleteAndItsPatchIdentityIsStable() {
        for style in MusicStyle.offered {
            XCTAssertFalse(style.harmonicProfile.progression.isEmpty, "\(style.rawValue)")
            XCTAssertFalse(style.harmonicProfile.chordTones.isEmpty, "\(style.rawValue)")
            XCTAssertTrue(style.tempoRange.contains(style.defaultTempo),
                          "\(style.rawValue): defaultTempo \(style.defaultTempo) is outside "
                          + "\(style.tempoRange)")
            XCTAssertFalse(style.displayName.isEmpty, "\(style.rawValue)")
            XCTAssertFalse(style.lineage.isEmpty, "\(style.rawValue)")
            XCTAssertTrue((0...0.5).contains(style.swing), "\(style.rawValue): swing \(style.swing)")

            // Stable patch identity: calling twice must yield the SAME id.
            XCTAssertEqual(style.synthPatch.id, style.synthPatch.id,
                           "\(style.rawValue): synthPatch.id is not stable across calls — its "
                           + "GenrePatches suffix is probably not exactly two hex digits")
        }
    }

    /// ⭐ THE BRAND HALF, moved here because the half that mattered was only non-blocking.
    ///
    /// `MusicStyleTests.testOfferedPaletteIsCuratedAndOpensContemplative` (renamed in this batch —
    /// it was `…IsCuratedAndContemplative`) used to assert that EVERY
    /// offered genre is drum-free or a sustained Fläche (founder 2026-07-24, "Die 6 ruhigen
    /// Genres"). This batch had to retire that loop: the founder asked on 2026-07-30 for
    /// "verschiedenste Techno und House Stile … Trance, acid", and sustaining an acid SEQUENCE or a
    /// house OFFBEAT chord would make it not-acid and not-house — the convergence defect itself.
    /// (⚠️ It is NOT that a techno genre cannot be sustained: `dubTechno` is one and is. The
    /// stronger claim stood here for one commit; do not cite it in the next batch.)
    ///
    /// What survives is the part that actually carries the contemplative identity, and it belongs
    /// in the BLOCKING bundle because the suite that held the original lives behind
    /// `continue-on-error` (#208): a fresh install must OPEN calm, and the calm family must not be
    /// crowded out. Widening the palette is allowed; replacing its centre is not.
    func testTheOfferedPaletteStillOpensContemplative() {
        let defaultGenre = StudioDefaultKeys.genre.value
        XCTAssertTrue(MusicStyle.offered.contains(defaultGenre),
                      "the default genre \(defaultGenre.rawValue) is not offered — a fresh install "
                      + "would show a picker with nothing selected")
        XCTAssertTrue(!defaultGenre.isBeatDriven
                      || MusicStyle.sustainedFlächen.contains(defaultGenre),
                      "the default genre \(defaultGenre.rawValue) is now a driving genre. The "
                      + "electronic additions sit ALONGSIDE the contemplative core — the first "
                      + "sound a new user hears is still supposed to be a still Fläche.")
        let calm = MusicStyle.offered.filter { MusicStyle.sustainedFlächen.contains($0) }
        XCTAssertGreaterThanOrEqual(calm.count, 4,
                                    "only \(calm.count) sustained Flächen are left in a palette of "
                                    + "\(MusicStyle.offered.count). Echoel's identity is immersive "
                                    + "and contemplative (NOT wellness, NOT a techno app) — if the "
                                    + "driving genres outgrow the calm ones, that is a founder call, "
                                    + "not a side effect of a genre batch.")
    }

    /// The `sustainedFlächen` list documents itself as equal to `allCases.filter { sustained }`.
    /// Re-asserted here (it is also in the non-blocking suite) because a new genre is exactly the
    /// change that breaks it, and this bundle is the one that can stop the merge (#208).
    func testTheSustainedListStillEqualsTheProfileFlag() {
        XCTAssertEqual(Set(MusicStyle.sustainedFlächen),
                       Set(MusicStyle.allCases.filter { $0.harmonicProfile.sustained }),
                       "sustainedFlächen drifted from the `sustained` profile flag — a new genre "
                       + "was added with sustained:true and not listed, or vice versa")
    }
}
