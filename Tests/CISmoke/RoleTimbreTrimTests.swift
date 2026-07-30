// RoleTimbreTrimTests.swift
// Echoel — #253 A6 (founder 2026-07-30: "Die Sound Charakter werden dadurch auch minimal
// beeinflusst für mehr organisches Sound Design"). BLOCKING bundle, because the other suite
// cannot fail a merge (#208).
//
// WHAT THIS FILE IS ACTUALLY GUARDING. A6 makes the TONE follow the RHYTHM — a short hard
// figure gets a brighter snappier sound, a long legato one a darker slower sound. The obvious
// way to build that is also the way this project has already been burnt twice: pull every
// genre toward a per-character target timbre, and now six targets replace the one convergence
// bug of #81/#125. So the load-bearing assertions here are not "does the trim do something"
// (that is one line) but:
//
//   · NEUTRAL IS AN IDENTITY — a player who never opened the Pad rhythm row must hear the
//     genre's patch bit-identically. That is the whole reason `padRhythm` defaults to `""`.
//   · THE TRIM IS RELATIVE, SO GENRES STAY APART — swept over all 14 offered genres, per
//     character. This is the anti-convergence property and it is asserted on real patches,
//     not argued in a comment. ⚠️ Do NOT read that sweep as clamp-edge coverage: across all 84
//     combinations the only clamp any offered genre comes near is the attack floor (acidTechno
//     0.002 s, techHouse 0.003 s under the three brightening characters). The clamp edges are
//     covered by the hand-built patch in `testExtremeAndNonFinitePatchesStayLegal`, and the
//     commit that first shipped this file claimed otherwise.
//   · THE BOUND IS DERIVED FROM THE TYPE'S OWN CONSTANTS, so widening a number without
//     widening the declared bound turns red instead of quietly shipping a big trim.
//   · THE DIRECTION IS DERIVED FROM `Character.accentIsSubtle`, so re-tuning one of the two
//     tables without the other turns red. The first A7 UI hard-coded that split into a view
//     and got it wrong; this file will not let the same split drift again.
//
// ⚠️ WHAT IT DOES NOT CLAIM. Nothing here says the six sound GOOD, or that the founder will
// hear "organisch" — that is a device listening call. It says the trim is small, reversible,
// direction-correct, and cannot collapse the genre roster.

import Foundation
import XCTest
@testable import Echoelmusic

final class RoleTimbreTrimTests: XCTestCase {

    /// A real shipped patch rather than a hand-built one: the trim's whole job is to nudge the
    /// patches that actually exist, and a synthetic patch could sit at a clamp edge by accident.
    private var base: SynthPatch { MusicStyle.dubTechno.synthPatch }

    // MARK: - Neutral must be an identity

    /// ⛔ THE MOST IMPORTANT TEST IN THIS FILE. `StudioDefaultKeys.padRhythm` defaults to `""`,
    /// which resolves to no character, which resolves to `.neutral`. If that were not an exact
    /// identity, every existing user's sound would have changed the moment this slice shipped —
    /// silently, and on a surface (timbre) where they would blame the genre.
    ///
    /// ⛔ SWEPT OVER THE WHOLE ROSTER, AND THE FIRST VERSION WAS NOT. It asserted on `dubTechno`
    /// alone and passed — while `acidTechno` (`a: 0.002`) FAILED the same claim, because the
    /// original `trimmed(_:)` clamped to a fixed 0.003 s attack floor even at neutral. One genre
    /// is not a guard for an all-genres promise; the reviewer found the counterexample inside a
    /// sweep this very file already ran for a different reason.
    func testTheNeutralTrimIsAnExactIdentityForEveryOfferedGenre() {
        for style in MusicStyle.offered {
            let p = style.synthPatch
            XCTAssertEqual(RoleRhythm.TimbreTrim.neutral.trimmed(p), p,
                           "the neutral trim changed \(style.rawValue)'s patch — a user who never "
                           + "touched the Pad rhythm row would hear a different sound than before "
                           + "A6, which is exactly the silent regression the `\"\"` default exists "
                           + "to prevent")
        }
    }

    /// ⛔ THE USER-REACHABLE HALF OF THE SAME DEFECT, and the audible one. The Sound panel's
    /// Attack and Release rows start at 0 (`param("Attack", …, 0...5)` / `0...10`), so a player
    /// may deliberately set a 20 ms release. A fixed 0.05 s floor turned that into 50 ms — MORE
    /// than doubled — with no rhythm character chosen at all. Unlike the attack case (where the
    /// engine floors the ramp at 3 ms anyway, making it inaudible) `EchoelDDSP` floors release at
    /// ONE SAMPLE, so this one was a real change in the sound.
    func testAHandSetSubFloorValueSurvivesTheNeutralTrim() {
        var tiny = base
        tiny.attack = 0.0
        tiny.release = 0.02
        let out = RoleRhythm.TimbreTrim.neutral.trimmed(tiny)
        XCTAssertEqual(out.attack, 0.0, "neutral lengthened a deliberately instant attack")
        XCTAssertEqual(out.release, 0.02, "neutral more than doubled a deliberately tiny release")
    }

    /// And a NON-neutral character may shorten such a value further, but must not LENGTHEN it:
    /// a clamp bounds where the trim may push, never where the input was allowed to be.
    func testACharacterNeverLengthensAValueThatWasAlreadyBelowTheFloor() {
        var tiny = base
        tiny.release = 0.02
        for c in RoleRhythm.Character.allCases {
            let out = RoleRhythm.timbreTrim(for: c).trimmed(tiny)
            XCTAssertLessThanOrEqual(out.release, 0.02 * 1.25,
                                     "\(c.rawValue) pushed a 20 ms release past its own declared "
                                     + "bound by clamping it up to a fixed floor")
        }
    }

    /// Purity: the input must be untouched. Value semantics make this true by construction today,
    /// but the method could grow an `inout` or a reference field later.
    func testTrimmingDoesNotMutateItsInput() {
        let p = base
        let before = p
        _ = RoleRhythm.timbreTrim(for: .flowing).trimmed(p)
        XCTAssertEqual(p, before)
    }

    // MARK: - The bound IS the specification

    /// Every field of every character's trim must sit inside the constants the type itself
    /// declares. Derived, so widening a number without widening the bound fails here rather
    /// than shipping a trim that stops being "minimal".
    ///
    /// ⚠️ THE `1e-6` SLACK IS LOAD-BEARING, NOT DEFENSIVE ROUNDING — do not "tighten" it away.
    /// `Float(1.12) - 1 == 0.120000005` while `Float(0.12) == 0.119999997`, so the exact
    /// comparison is FALSE by ~8e-9. Same for `sparse`: `Float(1.22) - 1 == 0.22000003` against
    /// `Float(0.22) == 0.219999999`. The slack is three orders of magnitude larger than the error
    /// and still far smaller than any meaningful widening of the bound.
    func testEveryCharactersTrimStaysInsideTheDeclaredBound() {
        for c in RoleRhythm.Character.allCases {
            let t = RoleRhythm.timbreTrim(for: c)
            XCTAssertLessThanOrEqual(abs(t.brightness),
                                     RoleRhythm.TimbreTrim.maxBrightnessShift + 1e-6,
                                     "\(c.rawValue) shifts brightness by \(t.brightness), past the "
                                     + "declared maximum. Either it is not a minimal trim any "
                                     + "more or the constant needs a founder-visible change.")
            XCTAssertLessThanOrEqual(abs(t.cutoffFactor - 1),
                                     RoleRhythm.TimbreTrim.maxCutoffFactorDeviation + 1e-6,
                                     "\(c.rawValue)'s cutoff factor \(t.cutoffFactor) is outside "
                                     + "the declared deviation")
            for (name, f) in [("attack", t.attackFactor), ("release", t.releaseFactor)] {
                XCTAssertLessThanOrEqual(abs(f - 1),
                                         RoleRhythm.TimbreTrim.maxTimeFactorDeviation + 1e-6,
                                         "\(c.rawValue)'s \(name) factor \(f) is outside the "
                                         + "declared deviation")
            }
        }
    }

    /// No character may silently inherit a neutral trim: the switch is exhaustive, so a seventh
    /// character is a compile error — but an EXISTING one quietly set to all-neutral would be a
    /// rhythm whose tone does not follow it, with nothing on screen saying so.
    func testNoCharacterIsSilentlyNeutral() {
        for c in RoleRhythm.Character.allCases {
            XCTAssertNotEqual(RoleRhythm.timbreTrim(for: c), .neutral,
                              "\(c.rawValue) has no timbre trim, so its tone does not follow its "
                              + "rhythm — the one thing A6 exists to do")
        }
    }

    /// Six characters, six different trims. A duplicate would mean two of the six are
    /// indistinguishable on this axis, which is the "more options that sound the same" failure
    /// #81/#125 already cost this project twice.
    func testTheSixTrimsAreSixDifferentTrims() {
        let all = RoleRhythm.Character.allCases.map { RoleRhythm.timbreTrim(for: $0) }
        for i in all.indices {
            for j in all.indices where j > i {
                XCTAssertNotEqual(all[i], all[j],
                                  "\(RoleRhythm.Character.allCases[i].rawValue) and "
                                  + "\(RoleRhythm.Character.allCases[j].rawValue) trim the timbre "
                                  + "identically")
            }
        }
    }

    // MARK: - The direction must follow the rhythm

    /// ⛔ DERIVED FROM `accentIsSubtle`, NOT RESTATED. The three strong-accent characters are the
    /// short-gate ones and must brighten and shorten; the three subtle ones are the long-gate
    /// ones and must darken and lengthen. Hard-coding the membership list here is precisely the
    /// mistake the first A7 UI made (and got wrong — it left `sparse` out), so the split comes
    /// off the engine.
    func testTheTrimDirectionAgreesWithTheAccentSplit() {
        for c in RoleRhythm.Character.allCases {
            let t = RoleRhythm.timbreTrim(for: c)
            if c.accentIsSubtle {
                XCTAssertLessThan(t.brightness, 0, "\(c.rawValue) is a subtle, long-gate "
                                  + "character and must DARKEN, not brighten")
                XCTAssertLessThan(t.cutoffFactor, 1, "\(c.rawValue) must close the filter")
                XCTAssertGreaterThan(t.attackFactor, 1, "\(c.rawValue) must soften the onset")
                XCTAssertGreaterThan(t.releaseFactor, 1, "\(c.rawValue) must lengthen the tail — "
                                     + "these characters work by blurring into themselves")
            } else {
                XCTAssertGreaterThan(t.brightness, 0, "\(c.rawValue) is a strong-accent, "
                                     + "short-gate character and must BRIGHTEN")
                XCTAssertGreaterThan(t.cutoffFactor, 1, "\(c.rawValue) must open the filter")
                XCTAssertLessThan(t.attackFactor, 1, "\(c.rawValue) must sharpen the onset")
                XCTAssertLessThan(t.releaseFactor, 1, "\(c.rawValue) must shorten the tail so the "
                                  + "note speaks and gets out of the way")
            }
        }
    }

    // MARK: - Anti-convergence: the reason this is a trim and not a target

    /// ⛔ THE #81/#125 GUARD. Two patches that differ in brightness must STILL differ, in the
    /// same direction, after the same trim. A per-character target timbre would fail this — and
    /// a target is the obvious way to build "the character changes the sound".
    func testTheTrimPreservesTheOrderOfTwoDifferentPatches() {
        for c in RoleRhythm.Character.allCases {
            let t = RoleRhythm.timbreTrim(for: c)
            var dark = base, bright = base
            dark.brightness = 0.20;  bright.brightness = 0.60
            dark.filterCutoff = 800; bright.filterCutoff = 4000
            let a = t.trimmed(dark), b = t.trimmed(bright)
            XCTAssertLessThan(a.brightness, b.brightness,
                              "\(c.rawValue) collapsed two different brightnesses toward each "
                              + "other — that is a target, not a trim, and it is how every genre "
                              + "ended up sounding the same in #81/#125")
            XCTAssertLessThan(a.filterCutoff, b.filterCutoff,
                              "\(c.rawValue) collapsed two different cutoffs")
        }
    }

    /// The same property on the real roster: all 14 offered genres must remain mutually distinct
    /// under every character. Swept rather than argued, because "relative therefore safe" is only
    /// true until a clamp flattens two patches onto the same edge.
    func testEveryCharacterKeepsAllOfferedGenresApart() {
        for c in RoleRhythm.Character.allCases {
            let t = RoleRhythm.timbreTrim(for: c)
            var seen: [String: MusicStyle] = [:]
            for style in MusicStyle.offered {
                let p = t.trimmed(style.synthPatch)
                // The four fields A6 touches, at a resolution finer than the trim itself.
                let key = String(format: "%.4f|%.2f|%.5f|%.4f",
                                 p.brightness, p.filterCutoff, p.attack, p.release)
                if let clash = seen[key] {
                    XCTFail("under \(c.rawValue), \(style.rawValue) and \(clash.rawValue) land on "
                            + "the same timbre \(key). The trim is supposed to be relative; a "
                            + "clamp has flattened two genres onto one edge, which is the "
                            + "convergence bug wearing a different hat.")
                }
                seen[key] = style
            }
        }
    }

    // MARK: - Clamps, and the one hazard the doc warns about

    /// An extreme patch must land on legal numbers rather than push a field out of the range the
    /// live Sound panel itself offers (20…18000 Hz), and a non-finite value in a decoded patch
    /// must not propagate — every clamp is `min(upper, max(lower, v))` for exactly that reason
    /// (CLAUDE.md's NaN-argument-order law).
    func testExtremeAndNonFinitePatchesStayLegal() {
        let t = RoleRhythm.timbreTrim(for: .driving)   // the one that pushes everything UP
        var hot = base
        hot.brightness = 1.0
        hot.filterCutoff = 18_000
        hot.attack = 0.003
        hot.release = 0.05
        let out = t.trimmed(hot)
        XCTAssertLessThanOrEqual(out.brightness, 1.0)
        XCTAssertLessThanOrEqual(out.filterCutoff, 18_000)
        // The 3 ms is the ENGINE's click-safe onset (`EchoelDDSP` floors the attack ramp there);
        // the articulation macro's own floor is 5 ms and merely stays above it. An earlier version
        // of this line credited the macro with the constant.
        XCTAssertGreaterThanOrEqual(out.attack, 0.003,
                                    "a faster attack must not go below the engine's click-safe "
                                    + "3 ms onset")
        XCTAssertGreaterThanOrEqual(out.release, 0.05)

        var bad = base
        bad.brightness = .nan
        bad.filterCutoff = .infinity
        bad.attack = -.infinity
        bad.release = .nan
        let sane = RoleRhythm.timbreTrim(for: .flowing).trimmed(bad)
        for (name, v) in [("brightness", sane.brightness), ("cutoff", sane.filterCutoff),
                          ("attack", sane.attack), ("release", sane.release)] {
            XCTAssertTrue(v.isFinite, "\(name) came out non-finite (\(v)) — a bad decoded patch "
                          + "must land on a legal number, not propagate into the voice")
        }
        XCTAssertLessThanOrEqual(sane.filterCutoff, 18_000, "+infinity must land on the TOP of "
                                 + "the range, not the bottom")
    }

    /// ⛔ COMPOUNDING IS REAL, AND THIS TEST IS WHY THE CALLER MUST NOT STORE THE RESULT.
    /// `trimmed` MULTIPLIES, so feeding its own output back in moves further than the declared
    /// bound. `EchoelStudioView.applyTakeSound` therefore trims a LOCAL COPY at push time and
    /// never writes it into `currentPatch`. If this assertion ever fails because the trim became
    /// idempotent, that constraint can be relaxed — but until then it is load-bearing.
    func testApplyingTheTrimTwiceCompoundsWhichIsWhyItIsNeverStored() {
        let t = RoleRhythm.timbreTrim(for: .flowing)
        var p = base
        p.brightness = 0.5
        p.filterCutoff = 3000
        p.release = 2.0
        let once = t.trimmed(p)
        let twice = t.trimmed(once)
        XCTAssertNotEqual(once, twice,
                          "the trim became idempotent. That is not a bug, but the caller's "
                          + "local-copy discipline is documented as necessary BECAUSE it is not — "
                          + "update `RoleRhythm.TimbreTrim`'s warning and this test together.")
        XCTAssertLessThan(twice.filterCutoff, once.filterCutoff,
                          "second application should push further in the same direction")
    }
}
