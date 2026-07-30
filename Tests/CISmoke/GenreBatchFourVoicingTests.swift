// GenreBatchFourVoicingTests.swift
// Echoel — #254 batch 4 (founder 2026-07-30: "verschiedenste Techno und House Stile"). BLOCKING
// bundle, because the other suite cannot fail a merge (#208).
//
// WHY A FILE AND NOT JUST THE EXISTING SWEEPS. `GenreFamilyDistinctnessTests` is satisfied by ANY
// difference between two offered genres, and `GenreBatchThreeVoicingTests` pins batch 3's axes. This
// file pins the two things batch 4 was actually built ON, so a later "tidy-up" that flattens them
// back into shapes the roster already had goes red instead of quiet:
//
//   · `minimalTechno`  — a BARE OPEN FIFTH `[0, 4]`: the only TWO-NOTE voicing in the whole file
//     (33 profile arms, not just the offered ones), plus the cleanest chain of the beat-driven
//     offered genres and the smallest non-zero swing of any genre.
//   · `detroitTechno`  — a MINOR-NINTH SHELL `[0, 2, 6, 8]` (root, third, ♭7, ninth, NO FIFTH),
//     also new to the roster, and the only ELECTRONIC genre that comps rather than stabs.
//
// ⚠️ WHAT THIS FILE DOES NOT CLAIM.
//   · Nothing about how either genre SOUNDS on a device — that is a founder listening call, and one
//     axis is not even wired (#257: a genre's delay TIME never reaches the audio, four stamp paths
//     overwrite it). Mix, feedback, tone, spread, saturation, reverb, harmony, scale, swing and the
//     patch DO reach it.
//   · No superlative that a sweep did not survive. Two claims in the source were written wide and
//     measured back down BEFORE this file existed: minimal's saturation is the floor of the
//     BEAT-DRIVEN offered genres only (classical/deepDrone at 0.10 and ambientPulse at 0.12 are
//     lower, and all three are `.none`-archetype), and Detroit's chorus is NOT unique among offered
//     techno/house (dubTechno and deepHouse are chorused too — that comment had to be corrected).
//     Both narrowed forms are asserted here in DERIVED form, so the scope cannot silently widen.
//   · Trance's "more distinct roots than any offered genre" is deliberately NOT re-asserted here —
//     `GenreBatchThreeVoicingTests` already pins it in this same bundle, and Detroit's three-root
//     progression was chosen to keep it true. One owner per claim.

import Foundation
import XCTest
@testable import Echoelmusic

final class GenreBatchFourVoicingTests: XCTestCase {

    private let additions: [MusicStyle] = [.minimalTechno, .detroitTechno]

    // MARK: - Reachability

    /// A genre built only into the taxonomy is a doorless genre — the trap this repo keeps paying
    /// for. Both must be in the picker AND in their category's offered subset, or the picker renders
    /// a section that silently omits them.
    func testBothAdditionsAreReachableInThePicker() {
        for style in additions {
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

    /// ⛔ THE MINIMAL DYAD. `[0, 4]` on a 7-note minor is root + fifth and NOTHING else — no third,
    /// so it reads neither major nor minor. Trance reaches the same ambiguity by SUBSTITUTING a
    /// fourth for the third; this one reaches it by leaving the third out. Asserted in SEMITONES
    /// through `MusicalKey.degree` rather than as the degree literal, because a degree literal is
    /// only meaningful together with the scale length (`deepDrone`'s `[0, 3, 6]` on a five-note
    /// scale wraps into a completely different stack — same digits, different chord).
    func testTheMinimalChordIsABareOpenFifthWithNoThird() {
        let semitones = semitoneStack(of: .minimalTechno)

        XCTAssertEqual(semitones, [0, 7],
                       "the minimal voicing is no longer a bare root + fifth (got \(semitones) "
                       + "semitones). Weight instead of harmony IS the genre — add a third and it "
                       + "becomes an ordinary minor stab, indistinguishable from techHouse at a "
                       + "neighbouring tempo.")
        XCTAssertFalse(semitones.contains(3) || semitones.contains(4),
                       "a third appeared in the minimal chord (\(semitones)) — the dyad is defined "
                       + "by its absence")
    }

    /// ⛔ THE DETROIT NINTH SHELL. `[0, 2, 6, 8]` on dorian is root + minor third + ♭7 + NINTH. The
    /// ninth is only expressible at all because `MusicalKey.degree` wraps octaves for a degree above
    /// 6 — degree 8 is the second scale step an octave up (+14). The fifth is dropped for the same
    /// reason `techHouse` drops it: it is what makes a four-note stack muddy.
    func testTheDetroitChordIsAMinorNinthShellWithNoFifth() {
        let semitones = semitoneStack(of: .detroitTechno)

        XCTAssertEqual(semitones, [0, 3, 10, 14],
                       "the Detroit voicing is no longer root + minor third + ♭7 + ninth (got "
                       + "\(semitones) semitones). The NINTH is the whole jazz inflection, and it "
                       + "only exists because degree 8 wraps an octave — if `MusicalKey.degree` "
                       + "ever stops wrapping, this chord silently collapses to a triad rather "
                       + "than failing to compile.")
        XCTAssertFalse(semitones.contains(7),
                       "a fifth appeared in the Detroit chord (\(semitones)) — it is a shell "
                       + "voicing precisely because it has none")
    }

    /// ⛔ THE CLAIM THAT REPLACED A FALSE SUPERLATIVE AND A TAUTOLOGY. Detroit's doc said "the
    /// roster's richest voicing"; a sweep found NINE four-note genres, so it ties rather than
    /// leads. And the assertion under that message was `semitones.count == 4`, fully implied by the
    /// exact-stack assertion two lines above it — it could never fail on its own.
    ///
    /// The true, sharper and genuinely failable claim is this: the other eight four-note genres all
    /// voice the IDENTICAL `[0, 2, 4, 6]` — root/third/fifth/seventh, the ordinary seventh chord.
    /// Detroit is the only four-note stack in the product that drops the fifth. Derived over
    /// `allCases`, so a batch-5 genre that copies the shape is caught here.
    func testDetroitIsTheOnlyFourNoteVoicingWithoutAFifth() {
        let fourNote = MusicStyle.allCases.filter { $0.harmonicProfile.chordTones.count == 4 }
        XCTAssertGreaterThan(fourNote.count, 1,
                             "there must be other four-note genres for this comparison to mean "
                             + "anything")
        XCTAssertTrue(fourNote.contains(.detroitTechno))

        let othersWithoutAFifth = fourNote.filter {
            $0 != .detroitTechno && !$0.harmonicProfile.chordTones.contains(4)
        }
        XCTAssertTrue(othersWithoutAFifth.isEmpty,
                      "a second fifth-less four-note voicing appeared "
                      + "(\(othersWithoutAFifth.map(\.rawValue).sorted())). Dropping the fifth from "
                      + "a four-note stack is Detroit's whole separation from the eight ordinary "
                      + "seventh chords — if a newcomer wants it too, one of the two docs is now "
                      + "wrong.")
    }

    /// Both voicings must stay NEW to the roster. Written as a sweep over `allCases` — including the
    /// genres that are NOT offered — rather than against a hardcoded list of the shapes that existed
    /// before, so a later genre that picks one of these up is caught here instead of quietly halving
    /// the axis.
    func testNoOtherGenreCopiesEitherNewVoicing() {
        for (style, tones) in [(MusicStyle.minimalTechno, [0, 4]),
                               (MusicStyle.detroitTechno, [0, 2, 6, 8])] {
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

    /// ⛔ AND THE DYAD MUST STAY THE ONLY TWO-NOTE STACK. Stronger than the sweep above and worth its
    /// own assertion: `minimalTechno`'s case doc claims not just "nobody else has `[0, 4]`" but
    /// "nobody else has TWO NOTES". A future genre could take `[0, 2]` and leave the sweep above
    /// green while making the claim false.
    func testMinimalIsTheOnlyTwoNoteVoicingInTheRoster() {
        let dyads = MusicStyle.allCases.filter { $0.harmonicProfile.chordTones.count == 2 }
        XCTAssertEqual(dyads, [.minimalTechno],
                       "two-note voicings are now \(dyads.map(\.rawValue).sorted()) — minimal's "
                       + "\"only dyad in the file\" claim is what separates it from every other "
                       + "stab genre")
    }

    // MARK: - The articulation axis, which is the other half of Detroit

    /// ⛔ DETROIT COMPS, EVERY OTHER ELECTRONIC GENRE DOES NOT. `.backbeat` was chosen FOR the
    /// articulation, not for a beat — since #166/#167 removed the drums, `beatArchetype`'s only
    /// audible consequence is `chordArticulation` (its drum-grid side effect reaches no voice). This
    /// is the same move `deepHouse` made when it took `.offbeat` while being musically
    /// four-to-the-floor. Asserted as a DERIVED uniqueness over the electronic category so a later
    /// "fix" to `.fourOnFloor` — which would give it techHouse's on-beat stab and erase the one axis
    /// separating it from three siblings — goes red here.
    func testDetroitIsTheOnlyElectronicGenreThatComps() {
        XCTAssertEqual(MusicStyle.detroitTechno.beatArchetype, .backbeat)
        XCTAssertEqual(MusicStyle.detroitTechno.chordArticulation, .comp)

        let otherCompingElectronic = MusicStyle.Category.electronic.genres.filter {
            $0 != .detroitTechno && $0.chordArticulation == .comp
        }
        XCTAssertTrue(otherCompingElectronic.isEmpty,
                      "comping is no longer Detroit's alone among electronic genres "
                      + "(\(otherCompingElectronic.map(\.rawValue).sorted())) — a second comping "
                      + "electronic genre makes the two hard to tell apart, which is why the claim "
                      + "is pinned rather than left in a doc comment")
    }

    /// ⛔ AND BOTH ARTICULATIONS MUST ACTUALLY FIRE. An ARPEGGIATED profile takes the arp path inside
    /// `composeHarmonic` and bypasses articulation entirely — which is why `acidTechno`'s `.stab` is
    /// inert and documented as such. A `sustained` profile suppresses the inner pulse and the walking
    /// bass. Both additions are built on played chords, so both flags must stay false or the axis is
    /// decoration.
    func testBothAdditionsActuallyReachTheirArticulation() {
        XCTAssertEqual(MusicStyle.minimalTechno.chordArticulation, .stab)
        for style in additions {
            XCTAssertFalse(style.harmonicProfile.arpeggiated,
                           "\(style.rawValue) became arpeggiated, so it now takes the arp path and "
                           + "its articulation is INERT — the same silent no-op acidTechno "
                           + "documents. Either drop the arp or stop claiming the articulation.")
            XCTAssertFalse(style.harmonicProfile.sustained,
                           "\(style.rawValue) became sustained, which suppresses the inner pulse "
                           + "and the walking bass — the drive is the genre")
            XCTAssertFalse(MusicStyle.sustainedFlächen.contains(style))
            XCTAssertTrue(style.isBeatDriven)
            XCTAssertEqual(style.defaultMode, .studioLocked,
                           "\(style.rawValue) is a locked-tempo dance genre; `.flowFree` would let "
                           + "a resting pulse drag it off the grid. That switch ends in "
                           + "`default: .studioLocked`, so this asserts the fall-through is right "
                           + "rather than trusting it.")
        }
    }

    // MARK: - The two narrowed superlatives

    /// ⛔ THE SATURATION CLAIM, IN ITS MEASURED SCOPE — BOTH HALVES. Minimal is the cleanest chain of
    /// the BEAT-DRIVEN offered genres (it undercuts `deepHouse`'s 0.22, which held that floor), and
    /// it is NOT the roster floor (`classical` and `deepDrone` sit at 0.10, `ambientPulse` at 0.12 —
    /// all three `.none`-archetype, so none of them competes for the same listening slot). The second
    /// half is asserted on purpose: a superlative stated one notch too wide is the mistake this batch
    /// family has had to correct three times, and dropping the narrowing would let a later edit widen
    /// the doc back to "cleanest in the product" with a green test behind it.
    func testMinimalIsTheCleanestBeatDrivenChainButNotTheRosterFloor() {
        let minimal = MusicStyle.minimalTechno.fxPreset.saturation
        let otherBeatDriven = MusicStyle.offered
            .filter { $0 != .minimalTechno && $0.isBeatDriven }
            .map(\.fxPreset.saturation)
        XCTAssertFalse(otherBeatDriven.isEmpty, "no beat-driven offered genres left to compare with")
        XCTAssertLessThan(minimal, otherBeatDriven.min() ?? 0,
                          "minimal is no longer the driest of the beat-driven offered genres "
                          + "(\(minimal) vs a floor of \(otherBeatDriven.min() ?? 0)). Being "
                          + "defined by what is absent is one of its two FX axes.")

        let calmer = MusicStyle.offered.filter { $0.fxPreset.saturation < minimal }
        XCTAssertFalse(calmer.isEmpty,
                       "minimal is now the saturation floor of the WHOLE offered roster. Its doc "
                       + "deliberately scopes the claim to beat-driven genres because the calm ones "
                       + "sat lower — if that is no longer true, the scope in `GenreFX.swift` has to "
                       + "be widened deliberately, not discovered later.")
    }

    /// Minimal's second axis: it shuffles, barely. Present rather than zero because the micro-shuffle
    /// is what keeps a one-chord take from reading as a metronome; `acidTechno` and `upliftingTrance`
    /// are the genres that want a true 0. Derived as a strict minimum over the NON-ZERO swings of the
    /// whole roster, not compared against a literal.
    func testMinimalHasTheSmallestNonZeroSwingOfAnyGenre() {
        let minimal = MusicStyle.minimalTechno.swing
        XCTAssertGreaterThan(minimal, 0,
                             "minimal's swing went to zero — then it IS a metronome, and the doc "
                             + "claim about the micro-shuffle is fiction")
        let otherNonZero = MusicStyle.allCases
            .filter { $0 != .minimalTechno && $0.swing > 0 }
            .map(\.swing)
        XCTAssertLessThan(minimal, otherNonZero.min() ?? 1,
                          "minimal no longer has the smallest non-zero swing "
                          + "(\(minimal) vs \(otherNonZero.min() ?? 1))")
        XCTAssertGreaterThan(MusicStyle.detroitTechno.swing, MusicStyle.dubTechno.swing,
                             "Detroit must shuffle more than dubTechno's near-straight 0.08 — the "
                             + "two dorian siblings are separated on this axis among others")
        XCTAssertLessThan(MusicStyle.detroitTechno.swing, MusicStyle.techHouse.swing,
                          "Detroit must shuffle LESS than techHouse's rolling 0.12")
    }

    // MARK: - The constraint that FORCED the two patch names

    /// The six warm lead patches the roster is allowed to use. A FIXED list, copied deliberately
    /// from `MusicStyleLeadTests.warmLeadSet` (test-local there, so it cannot be imported) — see
    /// the test below for why it must not be derived from the data.
    private let warmLeadSet: Set<String> = [
        "Soft Keys", "Warm Strings", "Pluck", "Hollow Reed", "Choir Vox", "Deep Sub"
    ]

    /// ⛔ A MIRROR OF A NON-BLOCKING TEST, ON PURPOSE. `MusicStyleLeadTests
    /// .testLeadTimbresAreSpreadNotCollapsed` already guards this — but it lives in
    /// `Tests/EchoelmusicTests`, which runs behind `continue-on-error` (#208) and therefore goes red
    /// IN SILENCE. This constraint is what forced batch 4's two lead-patch names ("Deep Sub" and
    /// "Choir Vox" were the only names sitting below the ceiling), so a batch-5 author picking a
    /// third name freely needs the failure to actually block.
    ///
    /// ⛔ AND THE FIRST VERSION OF THIS "MIRROR" WAS NOT ONE — it divided by `counts.count`, the
    /// number of names ACTUALLY IN USE, which is derived from the very data being judged. Collapse
    /// all 24 genres onto one lead name and that divisor becomes 1, the ceiling becomes 24, and
    /// `24 <= 24` passes: a test called `…StaySpread…` would have gone GREEN on the maximally
    /// collapsed roster — precisely the state the original was written to catch. It also dropped
    /// the original's distinct-name floor. Both are restored here: a FIXED divisor of six, and the
    /// `>= 5` floor. The lesson is general enough to state — a pigeonhole ceiling must divide by
    /// the number of AVAILABLE slots, never by the number currently occupied.
    func testLeadTimbresStaySpreadInTheBlockingBundle() {
        let bearing = MusicStyle.allCases.filter { !$0.harmonicProfile.sustained }
        let leads = bearing.map(\.leadPatchName)
        XCTAssertFalse(leads.isEmpty, "there must be lead-bearing genres to guard")

        // A name outside the approved set would silently enlarge the palette and make the
        // fixed divisor below wrong — so it is caught here rather than diluting the ceiling.
        for style in bearing {
            XCTAssertTrue(warmLeadSet.contains(style.leadPatchName),
                          "\(style.rawValue) uses lead patch \"\(style.leadPatchName)\", which is "
                          + "not one of the six warm leads \(warmLeadSet.sorted()). Adding a "
                          + "seventh name is a palette decision, not a per-genre one — and it "
                          + "changes the spread ceiling this file and MusicStyleLeadTests share.")
        }

        var counts: [String: Int] = [:]
        for name in leads { counts[name, default: 0] += 1 }
        let ceiling = Int(ceil(Double(leads.count) / Double(warmLeadSet.count)))
        for (name, count) in counts.sorted(by: { $0.key < $1.key }) {
            XCTAssertLessThanOrEqual(count, ceiling,
                                     "lead timbre \"\(name)\" is on \(count) of \(leads.count) "
                                     + "lead-bearing genres, over the pigeonhole ceiling of "
                                     + "\(ceiling) that \(leads.count) genres over "
                                     + "\(warmLeadSet.count) warm patches allows. Adding a genre "
                                     + "means picking the name currently BELOW the ceiling, not "
                                     + "the one that sounds nicest — measure before choosing.")
        }

        XCTAssertGreaterThanOrEqual(Set(leads).count, 5,
                                    "lead-bearing genres use only \(Set(leads).sorted()) — at "
                                    + "least 5 of the 6 warm leads must be in play, or the "
                                    + "ceiling above can be satisfied by a collapsed palette")
    }

    // MARK: - Completeness

    /// The three per-genre fields that can be filled WRONG rather than left out — the exhaustive
    /// switches catch everything else at compile time. Patch-id uniqueness is already swept across
    /// `allCases` by `GenreBatchThreeVoicingTests`, so it is not repeated here.
    func testBothAdditionsAreComplete() {
        for style in additions {
            XCTAssertFalse(style.displayName.isEmpty)
            XCTAssertFalse(style.lineage.isEmpty)
            XCTAssertTrue(style.tempoRange.contains(style.defaultTempo),
                          "\(style.rawValue)'s default tempo \(style.defaultTempo) is outside its "
                          + "own window \(style.tempoRange)")
            XCTAssertTrue(style.fxPreset.delayEnabled,
                          "\(style.rawValue) has no delay at all — every genre preset carries one")
            XCTAssertFalse(style.synthPatch.name.isEmpty)
        }
    }

    // MARK: - Helper

    /// The chord expressed as semitones above its own root, which is the only form in which a
    /// voicing claim is checkable: the degree literal means nothing without the scale length.
    private func semitoneStack(of style: MusicStyle) -> [Int] {
        let profile = style.harmonicProfile
        let key = MusicalKey(root: 0, scale: style.scale)
        let root = key.degree(profile.chordTones[0], octave: profile.padOctave)
        return profile.chordTones.map { key.degree($0, octave: profile.padOctave) - root }
    }
}
