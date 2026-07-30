// FXPresetDelaySpreadTests.swift
// Echoel — a preset whose sound depends on what came before it is not a preset. BLOCKING bundle.
//
// THE DEFECT (#246). `EchoelDelay.spread` offsets the RIGHT tap by `spread * 0.025 * sampleRate`
// (`EchoelDelay.processStereo`, the `spreadSamples` line) — at the 0.6 some characters stamp,
// 15 ms, which is the whole difference between a centred echo and a wide one. Seven delay
// parameters round-tripped through `FXPreset`. This eighth one did not: no property, no decode,
// no `capture`, no `apply`, no `morphed`. Its only writer in the entire app was
// `GenreFXPreset.apply` (`chain.delay.spread = delaySpread` in GenreFX.swift). Since #251 the
// Delay section carries a Spread row, so the user is a writer too.
//
// TWO CONSEQUENCES, and the second is the one that makes it a defect rather than a gap:
//
//   1. `FXCuratedLibrary.curatedCommunity` builds every featured entry by stamping a character
//      into a fresh chain and calling `FXPreset.capture` — so each curated preset silently threw
//      away its own character's stereo image at the moment it was created.
//   2. `apply` never WROTE the field, so the chain kept whatever the last genre stamp had left
//      there. Load preset A after genre B and you hear A's delay in B's stereo image. Nothing is
//      broken, nothing errors, and the same preset sounds different depending on its history.
//
// ⚠️ WHAT THIS FILE CANNOT CATCH, stated because the sibling `FXPresetCompressorTimingTests`
// makes the same admission and it is worth keeping honest. `delaySpread` has no
// declaration-site default, so THREE of the six touchpoints are compiler-enforced rather than
// test-enforced: dropping the `init(from:)` decode leaves `self` uninitialised, and dropping the
// `capture` or `morphed` argument fails the memberwise call — none of those can reach CI as a red
// test, because they cannot reach CI at all. (An earlier draft of this comment scoped the
// admission to the decoder alone, which would have let a reader believe tests 1 and 6 guard the
// two memberwise sites against omission. They do not.)
//
// What these tests ARE pointed at, and what the compiler cannot see:
//   · a MIS-WIRED key — `delaySpread = f(.delayTone, …)`, or `delaySpread: chain.delay.wow` in
//     `capture`, the slip that sixty near-identical lines invite (tests 1 and 5);
//   · a NON-INTERPOLATING morph — `delaySpread: delaySpread` instead of `L(...)` (test 6);
//   · the ONE genuinely omittable line, `apply`'s write, which compiles fine when deleted and is
//     caught twice (tests 1 and 2);
//   · a decode default that drifts off the engine's own initial value (test 4).

import Foundation
import XCTest
@testable import Echoelmusic

final class FXPresetDelaySpreadTests: XCTestCase {

    // MARK: - The transfer that did not happen

    /// ⛔ THE ONE THAT MATTERS. Asserted as a TRANSFER across a preset boundary, not as "the
    /// field holds what I set" — the second form passes even when `apply` is missing entirely,
    /// which is exactly the state this task found.
    func testTheStereoImageCrossesAPresetBoundary() {
        let source = EchoelFXChain(sampleRate: 48000)
        source.delayEnabled = true
        source.delay.spread = 0.45

        let preset = FXPreset.capture(from: source, fxEnabled: true, name: "Wide")
        XCTAssertEqual(preset.delaySpread, 0.45,
                       "`capture` does not read the spread back out of the chain, so pressing "
                       + "Save writes a default over what the user dialled in (#246)")

        let target = EchoelFXChain(sampleRate: 48000)
        preset.apply(to: target)
        XCTAssertEqual(target.delay.spread, 0.45,
                       "`apply` does not write the spread, so the loaded preset's stereo image "
                       + "is whatever happened to be in the chain already (#246)")
    }

    /// ⛔ THE ACTUAL BUG, and it is the inverse assertion: applying a preset must OVERWRITE a
    /// spread the chain already carries. A field that is merely absent from `apply` looks
    /// harmless until you notice `GenreFXPreset.apply` leaves 0.6 there — then a preset captured
    /// from a dry chain plays wide, and no control anywhere shows why.
    func testApplyingAPresetErasesThePredecessorsStereoImage() {
        let chain = EchoelFXChain(sampleRate: 48000)
        chain.delay.spread = 0.6                       // as a genre/character stamp leaves it

        let dry = FXPreset.capture(from: EchoelFXChain(sampleRate: 48000),
                                   fxEnabled: true, name: "Centred")
        XCTAssertEqual(dry.delaySpread, 0,
                       "precondition: a fresh chain is centred, or the assertion below is vacuous")

        dry.apply(to: chain)
        XCTAssertEqual(chain.delay.spread, 0,
                       "the preset inherited the previous stamp's stereo image instead of "
                       + "replacing it — the same preset now sounds different depending on what "
                       + "was loaded before it (#246)")
    }

    /// ANTI-VACUITY for the whole file. If no shipped character stamped a spread, every
    /// assertion above would be about a parameter nobody uses. Written as a sweep over
    /// `allCases` rather than pinning one character's number, so re-voicing a character for
    /// musical reasons cannot redden this.
    func testAtLeastOneShippedCharacterActuallyStampsASpread() {
        var stamped = 0
        for character in FXCharacter.allCases {
            let chain = EchoelFXChain(sampleRate: 48000)
            character.apply(to: chain, bpm: 120, genre: .selfObservation)
            if chain.delay.spread > 0 { stamped += 1 }
        }
        XCTAssertGreaterThan(stamped, 0,
                             "no FX character stamps a stereo spread any more, so the parameter "
                             + "this file guards has no producer. Either the characters were "
                             + "re-voiced to centre or `GenreFXPreset.apply` stopped writing it "
                             + "— check which before relaxing this.")
    }

    // MARK: - Persistence

    /// A preset written before this key existed must load onto a FRESH chain bit-identically.
    /// Same law as the compressor block's `compAttack`/`compRelease`/`compKnee`: the decode
    /// default has to equal the ENGINE's own initial value, not a tidy-looking number.
    /// Raw JSON rather than a re-encoded `FXPreset`, because re-encoding would include the new
    /// key and the test would prove nothing.
    func testAPresetSavedBeforeThisFieldExistedStaysCentred() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Old","tags":[],"schema":4,
         "fxEnabled":true,
         "delayEnabled":true,"delayModeRaw":"digital","delayMix":0.4,"delayTime":0.25,
         "delayFeedback":0.5,"delayTone":0.3,"delayWow":0.1,"delayDrive":0.2,
         "limiterEnabled":true,"limiterCeiling":-0.5}
        """
        let preset = try JSONDecoder().decode(FXPreset.self, from: Data(json.utf8))

        // The values it DID carry survive — proves the payload decoded at all.
        XCTAssertEqual(preset.delayTone, 0.3)
        XCTAssertEqual(preset.delayWow, 0.1)

        XCTAssertEqual(preset.delaySpread, EchoelDelay(sampleRate: 48000).spread,
                       "an old preset must load with the engine's own starting image, so it "
                       + "sounds on a fresh chain exactly as it always did")
    }

    /// The field must survive a save/load round-trip. Pointed at the copy-paste slip: `encode`
    /// and `CodingKeys` are synthesised while `init(from:)` is sixty hand-written
    /// `f(.key, default)` lookups, so a crossed key drops or swaps the value with nothing
    /// anywhere raising. The value is deliberately one no other delay field in this test holds.
    func testTheSpreadSurvivesASaveAndLoad() throws {
        var preset = FXPreset.capture(from: EchoelFXChain(sampleRate: 48000),
                                      fxEnabled: true, name: "Round")
        preset.delaySpread = 0.37

        let back = try JSONDecoder().decode(FXPreset.self, from: JSONEncoder().encode(preset))
        XCTAssertEqual(back.delaySpread, 0.37,
                       "the spread did not survive encode→decode — most likely `init(from:)` "
                       + "reads a neighbouring delay key")
    }

    // MARK: - The domain the decoder does not enforce

    /// ⛔ THE HAZARD THIS SLICE OPENED. Until now `spread`'s only writer was `GenreFXPreset.apply`
    /// with hardcoded 0…0.6 literals, so nothing bounded it and nothing needed to. It now decodes
    /// from a file, and `FXPreset`'s decoder does not clamp — a hand-edited `.echoelfx` delivers
    /// any Float. The #251 Spread row can dial it back, but only within [0, 1], which is exactly
    /// why the render has to hold that domain: the row cannot reach a value it did not put there.
    ///
    /// ⚠️ NOT A CRASH TEST, and saying so matters because the obvious reading is wrong: the value
    /// cannot trap. `EchoelDelayLine.read` clamps to `1...maxDelaySamples` with the NaN-safe
    /// `clamped(to:)`, so the worst an unbounded spread could do is park the right tap a full
    /// second away. This pins the DECLARED [0, 1] domain instead, so a corrupt preset sounds wide
    /// rather than broken, and can be brought back by re-picking a character.
    ///
    /// ⛔ AND IT IS DELIBERATELY NOT A FINITENESS TEST, because that version WOULD HAVE BEEN
    /// VACUOUS and I wrote it first: without any clamp, `spreadSamples` is NaN, `baseR` is
    /// `Swift.max(1.0, NaN)` which returns 1.0 (argument order decides — CLAUDE.md's rule), and
    /// `read` clamps whatever survives. So `isFinite` holds with the clamp deleted. The only
    /// observable difference is WHERE THE RIGHT TAP LANDS, so that is what is measured.
    ///
    /// Measured through the audio, not by reading the property back: the clamp is a local inside
    /// `processStereo` and `spread` itself keeps whatever was written, exactly like `feedback` and
    /// `mix` — a getter check would prove nothing.
    func testAnAbsurdSpreadCannotPushTheRightTapOutOfItsDeclaredRange() {
        /// Impulse in, wet only, no feedback, time snapped by `reset()` so the 40 ms glide cannot
        /// move the tap mid-measurement. Returns the frame at which each channel peaks.
        func tapPeaks(spread: Float) -> (left: Int, right: Int, rightPeak: Float) {
            let delay = EchoelDelay(sampleRate: 48000)
            delay.mix = 1                    // wet only, so the peak IS the tap
            delay.feedback = 0               // one echo, not a train
            delay.timeSeconds = 0.01         // 480 samples
            delay.reset()                    // snap timeSmoothed to the target (EchoelDelay.reset)
            delay.spread = spread

            var lIdx = 0, rIdx = 0
            var lPeak: Float = 0, rPeak: Float = 0
            for i in 0..<8000 {              // 167 ms — far beyond any legal spread (25 ms)
                let x: Float = i == 0 ? 1 : 0
                let (l, r) = delay.processStereo(x, x)
                XCTAssertTrue(l.isFinite && r.isFinite, "spread \(spread) produced non-finite audio")
                if abs(l) > lPeak { lPeak = abs(l); lIdx = i }
                if abs(r) > rPeak { rPeak = abs(r); rIdx = i }
            }
            return (lIdx, rIdx, rPeak)
        }

        // PRECONDITION, and it is what makes the loop below mean something: a FULL legal spread
        // (1.0 → 25 ms → 1200 samples) must visibly move the right tap and no further.
        let legal = tapPeaks(spread: 1.0)
        XCTAssertGreaterThan(legal.rightPeak, 0.3,
                             "the right tap produced no echo at all inside the window — this "
                             + "test's premise is gone; re-derive it rather than deleting the clamp")
        XCTAssertGreaterThan(legal.right, legal.left,
                             "a full spread did not delay the right tap relative to the left, so "
                             + "the measurement below cannot detect an over-wide one")
        XCTAssertLessThanOrEqual(legal.right - legal.left, 1300,
                                 "even a legal 1.0 spread offsets more than 25 ms — the "
                                 + "`spread * 0.025 * sr` scaling changed and the bound below is "
                                 + "now measuring the wrong thing")

        // …and an absurd value must land in the SAME place as the legal maximum, not further out.
        // 40 unclamped is 48 000 samples = a full second: outside the window entirely, so the
        // right channel would be silent here and `rightPeak` would collapse.
        for absurd: Float in [1.5, 40, 1e30, .infinity, .nan, -1, -1e30, -.infinity] {
            let got = tapPeaks(spread: absurd)
            XCTAssertGreaterThan(got.rightPeak, 0.3,
                                 "spread \(absurd): the right tap left the audible window — it is "
                                 + "parked far out instead of held at the domain edge")
            XCTAssertLessThanOrEqual(got.right - got.left, 1300,
                                     "spread \(absurd): the right tap sits more than 25 ms from "
                                     + "the left, so the declared [0, 1] domain is not held in "
                                     + "the render (EchoelDelay.processStereo)")
        }
    }

    // MARK: - The morph

    /// The morph fader must carry it too. Left out of `morphed`, the fader would drag every
    /// other delay parameter toward the target preset and leave the stereo image pinned to the
    /// source — audible as an image that refuses to move while everything around it does.
    /// The midpoint is asserted exactly because `L(a, b)` is plain linear interpolation.
    func testTheMorphFaderCarriesTheStereoImage() {
        let dry = EchoelFXChain(sampleRate: 48000)
        var a = FXPreset.capture(from: dry, fxEnabled: true, name: "A")
        a.delaySpread = 0.2
        var b = FXPreset.capture(from: dry, fxEnabled: true, name: "B")
        b.delaySpread = 0.8

        XCTAssertEqual(a.morphed(to: b, amount: 0.5).delaySpread, 0.5, accuracy: 0.0001,
                       "the morph leaves the stereo image behind while the rest of the delay "
                       + "moves — the fader would be lying about `every parameter`")
        XCTAssertEqual(a.morphed(to: b, amount: 0).delaySpread, 0.2, accuracy: 0.0001)
        XCTAssertEqual(a.morphed(to: b, amount: 1).delaySpread, 0.8, accuracy: 0.0001)
    }
}
