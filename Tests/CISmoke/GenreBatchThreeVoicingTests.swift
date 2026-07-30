// GenreBatchThreeVoicingTests.swift
// Echoel — #254 batch 3 (founder 2026-07-30: "verschiedenste Techno und House Stile … Trance,
// acid"). BLOCKING bundle, because the other suite cannot fail a merge (#208).
//
// WHY A FILE AND NOT JUST THE EXISTING SWEEP. `GenreFamilyDistinctnessTests` already asserts that
// no two OFFERED genres share an audible fingerprint, and both additions pass it. But that sweep
// is satisfied by ANY difference — the trap I walked into on batch 1, where `deepHouse` first
// shipped with `selfObservation`'s exact harmony and the sweep would have waved it through on
// register alone. So this file pins the two things each addition was actually built ON, in a form
// that fails if a later "tidy-up" flattens them back into the shapes the roster already had:
//
//   · `upliftingTrance` — a SUS4 voicing `[0, 3, 4]` (root + fourth + fifth, NO THIRD) and a
//     FOUR-root progression. Both are new to the whole roster.
//   · `techHouse`       — a DOMINANT-7th SHELL `[0, 2, 6]` (root + third + ♭7, NO FIFTH), the
//     first offered `mixolydian`, and its own swing value.
//
// ⚠️ WHAT THIS FILE DOES NOT CLAIM. Nothing here is about how either genre SOUNDS on a device —
// that is a founder listening call, and one axis is not even wired: per `GenreFXPreset.apply`, the
// genre's delay TIME never reaches the audio (a picker value overwrites it on four stamp paths, see
// #257). The FX presets' other fields, the harmony, the scale, the swing and the patch DO reach it.
// Nor does it claim the two are "the most distinct" of anything: the tempo windows deliberately
// overlap siblings, both map to the same `.stab` articulation, and `upliftingTrance` shares plain
// natural minor with two offered genres. Those overlaps are stated in the source and are the
// honest cost of putting each genre at its real tempo and in its real mode.

import Foundation
import XCTest
@testable import Echoelmusic

final class GenreBatchThreeVoicingTests: XCTestCase {

    // MARK: - Reachability

    /// A genre built only into the taxonomy is a doorless genre — the trap this repo keeps paying
    /// for. Both must be in the picker AND in their category's offered subset, or the picker
    /// renders a section that silently omits them.
    func testBothAdditionsAreReachableInThePicker() {
        for style in [MusicStyle.upliftingTrance, .techHouse] {
            XCTAssertTrue(MusicStyle.offered.contains(style),
                          "\(style.rawValue) is built but not offered — a doorless genre")
            XCTAssertEqual(style.category, .electronic,
                           "\(style.rawValue) must be categorised, or `Category.genres` is no "
                           + "longer the full taxonomy")
            XCTAssertTrue(MusicStyle.Category.electronic.offeredGenres.contains(style),
                          "\(style.rawValue) is offered but absent from its category's offered "
                          + "subset — the picker section would omit it")
        }
    }

    // MARK: - The voicings, which are the point

    /// ⛔ THE TRANCE SUS CHORD. `[0, 3, 4]` on a 7-note mode is root + FOURTH + fifth: no third at
    /// all, so it reads neither major nor minor. Asserted through `MusicalKey.degree` in SEMITONES
    /// rather than as the degree literal, because the literal is only meaningful together with the
    /// scale length — the same trap `deepDrone`'s `[0, 3, 6]` documents (on a five-note scale those
    /// degrees wrap into a completely different stack).
    func testTheTranceChordIsASuspendedFourthWithNoThird() {
        let profile = MusicStyle.upliftingTrance.harmonicProfile
        let key = MusicalKey(root: 0, scale: MusicStyle.upliftingTrance.scale)
        let root = key.degree(profile.chordTones[0], octave: profile.padOctave)
        let semitones = profile.chordTones.map { key.degree($0, octave: profile.padOctave) - root }

        XCTAssertEqual(semitones, [0, 5, 7],
                       "the trance voicing is no longer root + fourth + fifth (got \(semitones) "
                       + "semitones). The suspended, third-less stack IS the genre — a triad or a "
                       + "seventh here makes it indistinguishable from deepHouse at the same "
                       + "register.")
        XCTAssertFalse(semitones.contains(3) || semitones.contains(4),
                       "a third appeared in the trance chord (\(semitones)) — it is a sus chord "
                       + "precisely because it has none")
    }

    /// ⛔ THE TECH-HOUSE SHELL. `[0, 2, 6]` on mixolydian is root + MAJOR third + ♭7 and no fifth.
    /// The missing fifth is not an oversight: a shell stab is what the genre plays.
    func testTheTechHouseChordIsADominantSeventhShellWithNoFifth() {
        let profile = MusicStyle.techHouse.harmonicProfile
        let key = MusicalKey(root: 0, scale: MusicStyle.techHouse.scale)
        let root = key.degree(profile.chordTones[0], octave: profile.padOctave)
        let semitones = profile.chordTones.map { key.degree($0, octave: profile.padOctave) - root }

        XCTAssertEqual(semitones, [0, 4, 10],
                       "the tech-house voicing is no longer root + major third + ♭7 (got "
                       + "\(semitones) semitones). Both the MAJOR third (which only mixolydian "
                       + "gives over a minor-key roster) and the ABSENT fifth are what separate "
                       + "this stab from every other chord in the product.")
        XCTAssertFalse(semitones.contains(7),
                       "a fifth appeared in the tech-house chord (\(semitones)) — it is a shell "
                       + "voicing precisely because it has none")
    }

    /// Both voicings must stay NEW to the roster. Written as a sweep over `allCases` rather than a
    /// hardcoded list of the four shapes that existed before, so a later genre that happens to pick
    /// one of these up is caught here rather than quietly halving the axis.
    func testNoOtherGenreCopiesEitherNewVoicing() {
        for (style, tones) in [(MusicStyle.upliftingTrance, [0, 3, 4]),
                               (MusicStyle.techHouse, [0, 2, 6])] {
            let sharers = MusicStyle.allCases.filter {
                $0 != style && $0.harmonicProfile.chordTones == tones
            }
            XCTAssertTrue(sharers.isEmpty,
                          "\(style.rawValue)'s voicing \(tones) is now shared with "
                          + "\(sharers.map(\.rawValue).sorted()). It was unique to the roster when "
                          + "the genre was built, and that uniqueness is what its case doc claims "
                          + "— either give the newcomer its own stack or correct the doc.")
        }
    }

    // MARK: - The secondary axes each genre's doc leans on

    /// Trance's other claim: it TRAVELS. Four roots is more than any other offered genre, and that
    /// is the difference between a vamp and a progression. Derived (a max over `offered`), not a
    /// literal 4, so re-voicing another genre cannot make this quietly false.
    func testTranceHasTheLongestProgressionOfAnyOfferedGenre() {
        let trance = MusicStyle.upliftingTrance.harmonicProfile.progression.count
        let others = MusicStyle.offered
            .filter { $0 != .upliftingTrance }
            .map(\.harmonicProfile.progression.count)
        XCTAssertGreaterThan(trance, others.max() ?? 0,
                             "trance no longer travels further than every other offered genre "
                             + "(\(trance) roots vs a maximum of \(others.max() ?? 0)). That was "
                             + "one of the two axes it was built on.")
    }

    /// techHouse's other claims: the first OFFERED mixolydian, and its own swing between
    /// `dubTechno`'s and `deepHouse`'s. Swing is one of very few axes that is audible on a held
    /// chord without touching harmony, which is why it is pinned rather than left to taste.
    func testTechHouseOwnsMixolydianAndItsOwnSwing() {
        XCTAssertEqual(MusicStyle.techHouse.scale, .mixolydian)
        let otherMixolydian = MusicStyle.offered.filter {
            $0 != .techHouse && $0.scale == .mixolydian
        }
        XCTAssertTrue(otherMixolydian.isEmpty,
                      "mixolydian is no longer techHouse's alone among offered genres "
                      + "(\(otherMixolydian.map(\.rawValue).sorted())) — that colour was the "
                      + "reason it is not simply a faster deepHouse")

        let swing = MusicStyle.techHouse.swing
        XCTAssertGreaterThan(swing, MusicStyle.dubTechno.swing,
                             "techHouse must shuffle more than dubTechno's near-straight 0.08")
        XCTAssertLessThan(swing, MusicStyle.deepHouse.swing,
                          "techHouse must shuffle LESS than deepHouse's 0.16 — the two house "
                          + "genres are supposed to sit at different points on that axis, and "
                          + "`MusicStyleSwingTests` separately pins jazz as the roster maximum")
        XCTAssertEqual(MusicStyle.upliftingTrance.swing, 0,
                       "trance must stay machine-straight; a shuffle removes the "
                       + "four-on-the-floor lift the genre is built on")
    }

    // MARK: - The two ways a `.stab` genre can be built wrong

    /// ⛔ THE ARTICULATION MUST ACTUALLY FIRE. `.fourOnFloor` maps to `.stab`, but an ARPEGGIATED
    /// profile takes the arp path inside `composeHarmonic` and bypasses articulation entirely —
    /// which is why `acidTechno`'s `.stab` is inert and was documented as such. Both additions are
    /// built on on-beat chord stabs, so both must be non-arpeggiated or the axis is decoration.
    func testBothAdditionsActuallyReachTheStabArticulation() {
        for style in [MusicStyle.upliftingTrance, .techHouse] {
            XCTAssertEqual(style.beatArchetype, .fourOnFloor)
            XCTAssertEqual(style.chordArticulation, .stab)
            XCTAssertFalse(style.harmonicProfile.arpeggiated,
                           "\(style.rawValue) became arpeggiated, so it now takes the arp path and "
                           + "its `.stab` is INERT — the same silent-no-op acidTechno documents. "
                           + "Either drop the arp or stop claiming the articulation.")
            XCTAssertFalse(style.harmonicProfile.sustained,
                           "\(style.rawValue) became sustained, which suppresses the inner pulse "
                           + "and the walking bass — the drive is the genre")
        }
    }

    /// Both are beat-driven, so neither may leak into the contemplative core's invariants: not
    /// drum-free, not a sustained Fläche, and locked to a grid rather than following the breath.
    /// `defaultMode` is the one that a compiler cannot catch — that switch ends in
    /// `default: .studioLocked`, so a calm genre omitted from its `.flowFree` arm gets the wrong
    /// transport silently. Here the default IS correct, and this asserts it on purpose rather than
    /// trusting a fall-through.
    func testBothAdditionsStayOutOfTheContemplativeCore() {
        for style in [MusicStyle.upliftingTrance, .techHouse] {
            XCTAssertTrue(style.isBeatDriven)
            XCTAssertFalse(MusicStyle.sustainedFlächen.contains(style))
            XCTAssertEqual(style.defaultMode, .studioLocked,
                           "\(style.rawValue) is a locked-tempo dance genre; `.flowFree` would let "
                           + "a resting pulse drag it off the grid")
        }
    }

    // MARK: - Completeness

    /// Every per-genre field a batch has to fill, checked in one place. A missing entry is usually
    /// a compile error (the switches are exhaustive) — but `lineage`, `displayName` and the patch
    /// identity are the three that can be filled WRONG rather than left out.
    func testBothAdditionsAreCompleteAndTheirPatchIdentityIsStable() {
        var seenIDs: [UUID: MusicStyle] = [:]
        for style in MusicStyle.allCases {
            let patch = style.synthPatch
            if let clash = seenIDs[patch.id] {
                XCTFail("\(style.rawValue) and \(clash.rawValue) share patch id \(patch.id) — the "
                        + "UUID suffix must be exactly two hex digits and unique, or the "
                        + "interpolation falls through to `?? UUID()` and mints a random id per "
                        + "call (patch identity stops surviving relaunch)")
            }
            seenIDs[patch.id] = style
        }

        for style in [MusicStyle.upliftingTrance, .techHouse] {
            XCTAssertFalse(style.displayName.isEmpty)
            XCTAssertFalse(style.lineage.isEmpty)
            XCTAssertTrue(style.tempoRange.contains(style.defaultTempo),
                          "\(style.rawValue)'s default tempo \(style.defaultTempo) is outside its "
                          + "own window \(style.tempoRange)")
            XCTAssertTrue(style.fxPreset.delayEnabled,
                          "\(style.rawValue) has no delay at all — every genre preset carries one")
        }
    }
}
