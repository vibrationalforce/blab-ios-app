// GenreAnchorFloorTests.swift
// Echoel — the genre-identity anchor, in the BLOCKING bundle.
//
// THE FOUNDER COMPLAINT this law exists to answer (2026-07-22): *"ich gehe durch die Genres
// und nach kurzer Zeit klingt alles wie classic."* Harmony comes from a shared,
// coherence-selected chord journey; `genreAnchorCount` decides how many of a take's section
// roots are pulled back onto the genre's OWN authored progression instead. Calm body ⇒ all of
// them ⇒ Doom stays Doom. Aroused body ⇒ a floor ⇒ at least the first root stays anchored while
// the rest explores.
//
// ⛔ THE DEFECT (found 2026-07-29, shipped since the 2026-07-22 ultrascan). The floor was
// `min(n, Int((Float(n) * anchor).rounded()))` with `anchor ≥ 0.34`, and for a ONE-section take
// that rounds `1 × 0.34` down to **zero**. Not "a smaller anchor" — NO anchor at all: the single
// root came wholesale from the shared journey, so the genre contributed nothing to the harmony.
//
// It applies to exactly the genres where it hurts most:
//   • `.selfObservation`   — THE SHIPPED DEFAULT (`StudioDefaultKeys`), sustained, progression
//                            [0,5,3] → one section per take
//   • `.esotericMeditation`— sustained, progression [0,1,4] → one section per take
//   • `.psytrance`         — a one-chord progression [0]
//   • `.doom`              — a one-chord progression [0]
//   • `.deepDrone`         — a one-chord progression [0], sustained (#254 batch 2). It joined the
//                            set the moment it was added, and THIS FILE'S PREMISE TEST IS WHAT
//                            CAUGHT IT — the batch-2 commit turned the blocking pipeline red on
//                            exactly this assertion. Working as designed: a genre whose harmony is
//                            one frozen root is the case the anchor floor exists for, so a new
//                            drone genre MUST be listed here rather than have the test relaxed.
//
// …and for every body below coherence 0.35. Camera rPPG reports coherence 0 until beats accrue;
// HealthKit never measures coherence at all. So the uncovered case was not an exotic body state,
// it was THE FIRST MINUTES OF EVERY SESSION on the default genre — which is where a new listener
// decides whether this instrument has a sound of its own.
//
// ⚠️ That list said THREE, then FOUR, and is now FIVE — and every correction came from the
// premise test at the bottom of this file, never from a person reading the header. The sweep that
// found the original defect named `.selfObservation`, `.esotericMeditation` and `.psytrance` and
// missed `.doom`; `.deepDrone` was added by #254 batch 2 and the test failed the same hour. That
// is the whole argument for keeping a hand-written list guarded: a header that names genres is a
// claim about the source, and a claim needs a check that can fail.
//
// ⚠️ THE OLD CODE KNEW. Its comment said the floor guarantees an anchor "(k≥1 for n≥2)". The
// parenthetical is accurate and the hole was left open. A documented hole is still a hole; this
// file is the version that fails instead of explaining.
//
// WHY HERE AND NOT `Tests/EchoelmusicTests`: that bundle builds only under `full-tests.yml`,
// which carries `continue-on-error: true` on both its build and its run step (#208). A guard
// there cannot turn a merge red.
//
// WHAT THIS CANNOT PROVE: that the anchored harmony sounds better, or that the four genres are
// now distinguishable BY EAR. It pins the arithmetic that decides whether the genre gets a vote.

import Foundation
import XCTest
@testable import Echoelmusic

final class GenreAnchorFloorTests: XCTestCase {

    // MARK: - The regression

    /// ⛔ THE GUARD. A one-section take must anchor its single root to the genre, at ANY body
    /// state. Zero here means the default genre has no harmonic identity.
    func testAOneSectionTakeIsAnchoredEvenWhenTheBodyIsFullyAroused() {
        for coherence in [Float(0), 0.1, 0.2, 0.34, 0.349] {
            XCTAssertEqual(BioComposer.genreAnchorCount(sections: 1, coherence: coherence), 1,
                           "coherence \(coherence): a single-section take anchored 0 roots, so "
                           + ".selfObservation (the default), .esotericMeditation, .psytrance "
                           + "and .doom take their harmony wholesale from the shared journey "
                           + "and stop sounding like themselves. Camera rPPG reports coherence "
                           + "0 until beats accrue, so this is the state every session STARTS "
                           + "in.")
        }
    }

    /// The anchor may never exceed the number of sections there are to anchor — `prog[i]` is
    /// written for `i in 0..<k`, so a k above n is an out-of-bounds write, not a louder genre.
    func testTheAnchorNeverExceedsTheSectionCount() {
        for n in 1...8 {
            for coherence in [Float(0), 0.25, 0.5, 0.7, 0.99, 1.0, 2.0] {
                let k = BioComposer.genreAnchorCount(sections: n, coherence: coherence)
                XCTAssertTrue((1...n).contains(k),
                              "n=\(n), coherence=\(coherence) → k=\(k) is outside 1…\(n)")
            }
        }
    }

    // MARK: - The crossfade that was already correct

    /// The clamp must be a NO-OP for every multi-section take — this fix is allowed to change
    /// the four one-section genres and nothing else. `2 × 0.34 = 0.68` already rounded to 1.
    func testMultiSectionTakesAreUnchangedByTheFloor() {
        XCTAssertEqual(BioComposer.genreAnchorCount(sections: 2, coherence: 0), 1)
        XCTAssertEqual(BioComposer.genreAnchorCount(sections: 3, coherence: 0), 1)
        XCTAssertEqual(BioComposer.genreAnchorCount(sections: 4, coherence: 0), 1)
        XCTAssertEqual(BioComposer.genreAnchorCount(sections: 8, coherence: 0), 3)
    }

    /// ⛔ THE ROUNDING MODE, pinned rather than assumed. `Float.rounded()` is
    /// `.toNearestOrAwayFromZero`, so an anchor of exactly 0.5 rounds UP. That tie is
    /// load-bearing: coherence 0.35 is where a one-section take used to flip from 0 to 1, and
    /// it is the ONLY coherence at which the tie-break decides anything. Every value below it
    /// is arithmetically identical (all land on the floor), so the neighbours above are not
    /// redundant with the aroused sweep — they are the boundary that sweep stops just short of.
    func testTheRoundingTieAtTheOldFlipPoint() {
        XCTAssertEqual(BioComposer.genreAnchorCount(sections: 1, coherence: 0.35), 1)
        XCTAssertEqual(BioComposer.genreAnchorCount(sections: 2, coherence: 0.35), 1)
        XCTAssertEqual(BioComposer.genreAnchorCount(sections: 4, coherence: 0.35), 2)
    }

    /// The two constants ARE the law — retune either and the doc comments above become false
    /// with nothing to notice. `genreAnchorFullBy` in particular is otherwise unpinned: no test
    /// distinguishes 0.7 from 0.6, yet its own doc promises "anchored in FULL" at that value.
    func testTheAnchorConstantsAreTheOnesEveryCommentClaims() {
        XCTAssertEqual(BioComposer.genreAnchorFloor, 0.34)
        XCTAssertEqual(BioComposer.genreAnchorFullBy, 0.7)
    }

    /// A calm body hears the genre's progression in FULL, and reaches it by coherence 0.7 —
    /// the same threshold at which the beat turns spacious.
    func testACalmBodyGetsTheWholeGenreProgression() {
        for n in 1...8 {
            XCTAssertEqual(BioComposer.genreAnchorCount(sections: n, coherence: 0.7), n,
                           "n=\(n): the genre must be fully anchored by coherence 0.7")
            XCTAssertEqual(BioComposer.genreAnchorCount(sections: n, coherence: 1), n)
        }
    }

    /// The anchor only ever GROWS with coherence — a body settling further must never hear LESS
    /// of the genre. This is the property the crossfade is named for, and the one a future
    /// re-tuning of the floor or the 0.7 threshold is most likely to break.
    func testTheAnchorOnlyGrowsAsTheBodySettles() {
        for n in 1...8 {
            var previous = 0
            var coherence = Float(0)
            while coherence <= 1.0 {
                let k = BioComposer.genreAnchorCount(sections: n, coherence: coherence)
                XCTAssertGreaterThanOrEqual(k, previous,
                                            "n=\(n): coherence rose to \(coherence) and the "
                                            + "anchor SHRANK from \(previous) to \(k)")
                previous = k
                coherence += 0.01
            }
        }
    }

    // MARK: - Degenerate input

    /// Coherence reaches this from the bio path, where a bad rPPG frame produces NaN. `Int(_:)`
    /// TRAPS on a NaN argument, so an unguarded NaN here is a crash, not a wrong chord — and
    /// `clamp01` would not catch it (`max(NaN, 0)` returns NaN; see the argument-order law in
    /// CLAUDE.md). A non-finite body is treated as fully aroused.
    func testNonFiniteCoherenceIsTreatedAsFullyArousedAndNeverTraps() {
        for coherence in [Float.nan, .infinity, -.infinity, -1, -0.5] {
            let k = BioComposer.genreAnchorCount(sections: 1, coherence: coherence)
            XCTAssertEqual(k, 1, "coherence \(coherence) must fall back to the floor, not crash")
        }
        // +∞ is non-finite too, so it falls to the floor rather than to a full anchor: the
        // fallback is deliberately the SAFE end (still anchored), not the flattering one.
        XCTAssertEqual(BioComposer.genreAnchorCount(sections: 4, coherence: .infinity), 1)
        XCTAssertEqual(BioComposer.genreAnchorCount(sections: 4, coherence: .nan), 1)
    }

    /// Zero or negative sections: nothing to anchor. The caller's `if k > 0` guard depends on
    /// this returning 0 rather than the clamped 1.
    func testAnEmptySectionLayoutAnchorsNothing() {
        XCTAssertEqual(BioComposer.genreAnchorCount(sections: 0, coherence: 1), 0)
        XCTAssertEqual(BioComposer.genreAnchorCount(sections: -3, coherence: 1), 0)
    }

    // MARK: - The four profiles this actually changes

    /// Guards the PREMISE of the whole file: that exactly `.selfObservation`,
    /// `.esotericMeditation`, `.psytrance`, `.doom` and `.deepDrone` compose as one section.
    /// `composeHarmonic` derives the count as
    /// `(profile.sustained && progression.count > 2) ? 1 : max(1, progression.count)`.
    ///
    /// ⛔ THIS TEST HAS NOW EARNED ITS KEEP TWICE. Before it ever ran in CI it turned up a
    /// FOURTH genre the defect sweep had missed (`.doom`). Then #254 batch 2 added `.deepDrone`
    /// — progression `[0]`, sustained — and this assertion is what turned the blocking pipeline
    /// red, hours before anyone would have noticed that a new drone genre was silently relying
    /// on the shared journey for its only chord. A header that names genres by hand is a claim
    /// about the source, and this is the only thing that keeps that claim honest.
    func testTheOneSectionProfilesAreStillTheOnesNamedInThisFile() {
        let oneSection = MusicStyle.allCases.filter { style in
            let p = style.harmonicProfile
            let progression = p.progression.isEmpty ? [0] : p.progression
            let n = (p.sustained && progression.count > 2) ? 1 : Swift.max(1, progression.count)
            return n == 1
        }
        XCTAssertEqual(Set(oneSection), Set<MusicStyle>([.selfObservation,
                                                         .esotericMeditation,
                                                         .psytrance,
                                                         .doom,
                                                         .deepDrone]),
                       "The set of one-section genres changed to "
                       + "\(oneSection.map(\.rawValue).sorted()). That is not a failure by "
                       + "itself — but this file's header names the genres, and the anchor "
                       + "floor is the only thing giving them a harmonic identity at low "
                       + "coherence. Update both in the same commit.")
    }
}
