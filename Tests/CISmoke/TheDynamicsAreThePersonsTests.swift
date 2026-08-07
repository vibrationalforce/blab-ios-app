// TheDynamicsAreThePersonsTests.swift
// Echoel — #403 Slice 3b. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ WHAT THIS PROTECTS. The founder's ask is that two people rendering the same preset do
// not get the same song. This slice gives the performer a say in how far the composed BASS
// LINE is lifted over the pad. Same section, more or less bottom.
//
// ⛔ AND WHY IT IS NOT THE LEVEL, WHICH IS WHAT SLICE 3 TILTED FOR ONE COMMIT. The full
// argument, with the arithmetic, is at `BioComposer.composeHarmonic`'s velocity site; it is
// NOT paraphrased here, because the first version of this header paraphrased it and repeated
// two claims the source review then falsified ("velocity reaches exactly one thing", "the
// servo removes a source offset entirely"). One place owns that reasoning. What matters for
// these tests: the composer owns BALANCE, a ratio, and no downstream stage normalises a ratio.
//
// ⚠️ WHAT THIS FILE CANNOT PROVE, said plainly because the epic's headline invites the
// opposite. It shows that two learned fingerprints produce a DIFFERENT bass-over-pad lift by a
// stated minimum, and that an unlearned one changes nothing at all. Whether that reads as
// "a different person" is a device listen, and no assertion here should be quoted as more.
//
// ⚠️ AND THE SIZE IS SMALL ENOUGH TO SAY OUT LOUD: full opposite fingerprints move the lift by
// ±0.07, ≈ 1 dB of bass weight relative to the pad on the shipped path.
//
// ⛔ THE FIRST VERSION THEN SAID "the composer's own per-note humanize is ±0.05 … the tilt is
// systematic where that jitter is random, so it is a different thing". Half right, and the
// wrong half matters. It counted only `hVel` and missed `hrvHumanize` (default-on in the app,
// up to ±0.036 more) — combined ±0.086 against a systematic ±0.07. And "systematic beats
// random" needs notes to average over: on the shipped genre a take is ONE sustained section,
// so `appendBass` writes exactly ONE bass note and there is nothing to average. The honest
// claim is that the fingerprint is a BIAS ACROSS TAKES, not a per-take guarantee. These tests
// hold it exactly because they compare two takes from the SAME seed, where the jitter is
// identical and cancels; the field does not grant that (Slice 1 salts the seed per performer).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheDynamicsAreThePersonsTests: XCTestCase {

    // MARK: - The golden law: an unlearned performer changes nothing

    func testAnUnlearnedSignatureContributesExactlyZero() {
        // The whole safety story of the epic, and the same one `SignatureIsThePersonNotTheMoment`
        // pins for the seed salt: a user who has never been measured must render bit-identically
        // to before the feature existed. Not "almost" — exactly 0.
        XCTAssertEqual(PerformerSignature.unknown.dynamicTilt, 0, """
            An unmeasured body now tilts the mix. Every take on every fresh install changes, \
            and the epic's one safety guarantee is gone.
            """)
    }

    func testTheUnlearnedLiftIsThePreSliceConstant() {
        // The other half of the same guarantee, at the point of use rather than at the source.
        // 0.14 is the literal this line carried before #403; if it moves, every existing take
        // changes for users who were never measured.
        XCTAssertEqual(BioComposer.bassLift(for: 0), 0.14, accuracy: 1e-6, """
            The un-tilted bass lift is no longer 0.14, so an unmeasured performer does not \
            render as they did before #403.
            """)
    }

    func testAnUnmeasuredHRVValueIsRejectedEvenWithACount() {
        // ⛔ THIS GUARD EXISTS BECAUSE THE FIRST VERSION LACKED IT. `0` means "not measured"
        // repo-wide (`BioSampleFrame.hrvNormalized`), and the decoder sanitises the COUNTS but
        // not the values — so a corrupt or hand-edited store could carry a positive count with
        // a zero value and produce a maximal NEGATIVE tilt out of an absence.
        var corrupt = PerformerSignature.unknown
        corrupt = corrupt.observing(Self.frame(hrv: 0.5, at: Self.moment(0)))
        XCTAssertGreaterThan(corrupt.hrvCount, 0, "Setup failed — nothing was learned.")
        // A learned signature whose value is legitimately positive tilts; the guard must not
        // have disarmed that.
        XCTAssertNotEqual(corrupt.dynamicTilt, 0, """
            A legitimately measured HRV no longer tilts at all — the `hrv > 0` guard is \
            rejecting real measurements, not just the "not measured" sentinel.
            """)

        // ⛔ AND THIS HALF IS THE ONE THE FIRST VERSION LEFT OUT, WHICH MADE THE TEST'S NAME A
        // LIE. It asserted only that the guard does NOT fire — so deleting `hrv > 0` from the
        // source kept the whole file green, i.e. the fix this commit added had no guard of its
        // own. The in-test comment then justified the omission with "the zero-value case is
        // unreachable through `observing` by construction", which is true of `observing` and
        // irrelevant: the guard's own doc names the reachable route, and it is right here.
        // `init(from:)` sanitises the COUNTS and not the VALUES, so a store carrying a
        // positive count with a zero value decodes exactly as written.
        let corruptJSON = Data(#"{"hrvCount":5,"hrvNormalized":0}"#.utf8)
        guard let decoded = try? JSONDecoder().decode(PerformerSignature.self, from: corruptJSON) else {
            return XCTFail("The corrupt-store fixture no longer decodes — the guard is untested again.")
        }
        XCTAssertEqual(decoded.hrvCount, 5, "Fixture failed — the count did not survive decoding.")
        XCTAssertEqual(decoded.hrvNormalized, 0, "Fixture failed — the zero value did not survive decoding.")
        XCTAssertEqual(decoded.dynamicTilt, 0, """
            A store carrying "5 observations, value 0" produced a non-zero tilt. `0` means NOT \
            MEASURED repo-wide, so this is a maximal fingerprint invented out of an absence.
            """)
    }

    // MARK: - The tilt does what it is for

    func testTwoDifferentBodiesGetADifferentLowEndByAStatedMinimum() {
        // ⚠️ A FLOOR, NOT `XCTAssertNotEqual`. Its Slice 2 counterpart learned this the hard
        // way: an inequality assertion passes for a difference of 1e-15, so shrinking the
        // effect to inaudibility would leave the whole file green while the feature is gone.
        // The floor is the design magnitude minus a margin, not a measurement of the code.
        let quiet = Self.learned(hrv: 0.05)          // habitually low variability → heavier
        let lively = Self.learned(hrv: 0.95)         // habitually high variability → lighter
        XCTAssertEqual(quiet.hrvCount, PerformerSignature.confidentAfter, "Setup: not fully ramped.")
        XCTAssertEqual(lively.hrvCount, PerformerSignature.confidentAfter, "Setup: not fully ramped.")

        let heavy = BioComposer.bassLift(for: quiet.dynamicTilt)
        let light = BioComposer.bassLift(for: lively.dynamicTilt)
        XCTAssertGreaterThan(heavy - light, 0.12, """
            Two opposite fingerprints differ by \(heavy - light) in bass lift — below the \
            0.12 floor this slice is designed around, so the personal weighting is no longer \
            a mix difference anyone could hear.
            """)
    }

    func testTheLiftNeverLeavesItsDesignedBand() {
        // Swept because the arithmetic is `0.14 − tilt · range` and a sign slip or a widened
        // range would put the bass above the pad by more than the mix can carry.
        //
        // ⚠️ AND THIS IS A BOUNDARY TEST, NOT A SHAPE TEST — the distinction
        // `ThePaceIsTiltedInsideTheGenre` had to add a whole test to make. A sweep like this
        // cannot tell a real tilt from one that was clamped flat; what makes that irrelevant
        // here is that there IS no clamp doing the bounding — `bassLift` is plain symmetric
        // arithmetic on a constant anchor, and `testTwoDifferentBodies…` above is the one that
        // would fail if the effect were flattened.
        for step in -12...12 {
            let tilt = Double(step) / 10                    // deliberately overshoots ±1
            let lift = BioComposer.bassLift(for: tilt)
            XCTAssertGreaterThanOrEqual(lift, 0.07 - 1e-6, "Lift \(lift) fell below the band at tilt \(tilt).")
            XCTAssertLessThanOrEqual(lift, 0.21 + 1e-6, "Lift \(lift) rose above the band at tilt \(tilt).")
        }
    }

    func testANonFiniteTiltIsTreatedAsNoFingerprint() {
        XCTAssertEqual(BioComposer.bassLift(for: .nan), 0.14, accuracy: 1e-6,
                       "A NaN tilt must fall back to the un-tilted lift, not poison the mix.")
        XCTAssertEqual(BioComposer.bassLift(for: .infinity), 0.14, accuracy: 1e-6,
                       "An infinite tilt must fall back to the un-tilted lift.")
    }

    // MARK: - The driver

    func testTheTiltRampsInInsteadOfLandingOnTheFirstSample() {
        // `blend` sets the mean OUTRIGHT from the first sample, so without the ramp one
        // artefact in the first take would move the mix of the whole session at full
        // magnitude. `tempoTilt` documents this at length; the copy must not drop it.
        var one = PerformerSignature.unknown
        one = one.observing(Self.frame(hrv: 0.7, at: Self.moment(0)))
        XCTAssertEqual(one.hrvCount, 1, """
            The frame was not accepted at all, so what follows would be asserting on an \
            unlearned signature rather than on the ramp.
            """)
        let first = abs(one.dynamicTilt)
        XCTAssertGreaterThan(first, 0, "One accepted HRV observation must start the tilt.")
        XCTAssertLessThan(first, 1, """
            A single observation already reaches full magnitude — the ramp is gone and one \
            artefact owns the mix of the session.
            """)
    }

    func testBothEndsOfTheSpanSaturateRatherThanRunAway() {
        // A position among people, not a clinical number — the same honest behaviour
        // `habitualSpan` chose for the heart. Outside the span the tilt stops moving; it does
        // not keep growing and it never leaves −1…1.
        let low = Self.learned(hrv: 0.01)
        let high = Self.learned(hrv: 0.99)
        XCTAssertEqual(low.hrvCount, PerformerSignature.confidentAfter, """
            Not every frame was accepted — the rate limit or the timestamp guard swallowed \
            some, so this is not the fully-ramped case it claims to test.
            """)
        XCTAssertEqual(high.hrvCount, PerformerSignature.confidentAfter,
                       "The high-variability signature did not fully ramp either.")
        XCTAssertGreaterThanOrEqual(low.dynamicTilt, -1, "A tilt escaped the −1 floor.")
        XCTAssertLessThanOrEqual(high.dynamicTilt, 1, "A tilt escaped the +1 ceiling.")
        XCTAssertLessThan(low.dynamicTilt, 0, "A habitually low-variability body tilts down.")
        XCTAssertGreaterThan(high.dynamicTilt, 0, "A habitually high-variability body tilts up.")
    }

    // MARK: - The wiring, end to end

    func testTwoFingerprintsProduceDifferentBassVelocitiesInARealTake() {
        // ⭐ THE ONLY TEST HERE THAT RUNS THE COMPOSER. A pure core with no caller is the same
        // defect with more steps, and a source scan proves the call EXISTS, not that it
        // changes a note. Two Inputs identical in every field except the fingerprint, same
        // seeds, same body — so any difference in the notes is the fingerprint and nothing else.
        //
        // ⛔ THE GENRE AND THE HUMANISATION ARE SET EXPLICITLY, because the first version left
        // both at `Input()`'s defaults and called the result "the default take". It was not:
        // `Input.style` defaults to `.dubTechno`, while the app SHIPS `.selfObservation`
        // (`StudioDefaultKeys.genre`), and the app passes `humanize: true`. The configuration
        // the whole commit reasoned about was the one configuration untested. It is also the
        // harder case: `.selfObservation` is sustained with ONE section, so the take carries
        // exactly one bass note and there is no averaging to hide behind. The comparison stays
        // exact because the tilt consumes no RNG — both takes draw identical jitter from the
        // same seed, so the difference below is the fingerprint alone. (In the FIELD the seed
        // is salted per performer by Slice 1, so the jitter differs too and the effect is a
        // bias across takes rather than a per-take guarantee — stated at the source.)
        var quiet = BioComposer.Input()
        quiet.style = .selfObservation
        quiet.humanize = true
        quiet.seed = 4242
        quiet.structureSeed = 99
        quiet.signatureDynamicTilt = -1
        var lively = quiet
        lively.signatureDynamicTilt = 1

        let a = BioComposer.compose(quiet).notes.filter { $0.role == .bass }
        let b = BioComposer.compose(lively).notes.filter { $0.role == .bass }
        XCTAssertFalse(a.isEmpty, "The shipped-genre take has no bass notes — this test proves nothing.")
        XCTAssertEqual(a.count, b.count, """
            The fingerprint changed HOW MANY bass notes there are. It is meant to change their \
            weight only; a note-count difference means it leaked into structure.
            """)
        let heaviest = a.map(\.velocity).max() ?? 0
        let lightest = b.map(\.velocity).max() ?? 0
        XCTAssertGreaterThan(heaviest - lightest, 0.12, """
            Two opposite fingerprints produced bass velocities \(heaviest) and \(lightest) — \
            the composer is not reading the tilt, or is reading it at a magnitude nobody hears.
            """)
    }

    func testThePadIsNotTiltedAtAll() {
        // ⛔ THE POINT OF SLICE 3b, ASSERTED RATHER THAN ONLY DESCRIBED. If a later cycle
        // re-tilts the pad velocity "to make it bigger", the level tilt is back and the
        // loudness servo will erase it again — silently, because everything else here passes.
        var quiet = BioComposer.Input()
        quiet.seed = 4242
        quiet.structureSeed = 99
        quiet.signatureDynamicTilt = -1
        var lively = quiet
        lively.signatureDynamicTilt = 1

        let a = BioComposer.compose(quiet).notes.filter { $0.role == .harmony }.map(\.velocity)
        let b = BioComposer.compose(lively).notes.filter { $0.role == .harmony }.map(\.velocity)
        XCTAssertFalse(a.isEmpty, "The default take has no harmony notes — this test proves nothing.")
        XCTAssertEqual(a, b, """
            The pad/harmony velocities moved with the fingerprint. That is a LEVEL tilt, and \
            the default-on loudness servo removes level by design — see this file's header.
            """)
    }

    func testTheAppSuppliesTheSignatureToTheComposer() throws {
        // The app half: the composer input must be SUPPLIED from the signature. Without this
        // the field defaults to 0 and every test above still passes against a dead feature.
        //
        // ⚠️ COMMENT-STRIPPED FIRST (the #367 trap). The doc blocks do not quote this string
        // today, so it changes nothing today — which is exactly when it is worth doing,
        // because the failure is silent: a later session that removes the call and explains
        // the removal in prose containing the same phrase leaves this guard green.
        let studio = Self.codeOnly(try Self.read("Sources/Echoelmusic/Studio/EchoelStudioView.swift"))
        XCTAssertTrue(studio.contains("signatureDynamicTilt: performerSignature.dynamicTilt"), """
            The composer input no longer carries the performer's dynamic tilt, so the field \
            defaults to 0 and the feature is silently off.
            """)
    }

    // MARK: - Helpers

    /// A signature ramped all the way in at one habitual HRV.
    private static func learned(hrv: Float) -> PerformerSignature {
        var s = PerformerSignature.unknown
        for n in 0..<PerformerSignature.confidentAfter {
            s = s.observing(frame(hrv: hrv, at: moment(n)))
        }
        return s
    }

    /// ⚠️ THE TIMESTAMP IS NOT DECORATION, and the first version of this file got it wrong in
    /// a way that would have made the blocking bundle green on a broken premise rather than
    /// red: it passed `0` for every frame. `observing` guards `now > 0` (a frame with no
    /// usable timestamp teaches nothing) and enforces `minimumObservationInterval` = 30 s
    /// between accepted observations, so eight frames at t=0 fold in ZERO of them and
    /// `hrvCount` stays 0 — the ramp tests would have been asserting on `unknown`.
    ///
    /// `.cameraPPG` because `mayTeach` refuses `.fallback` (the simulator): a demo session
    /// must not write the PERSON's handwriting.
    private static func frame(hrv: Float, at t: TimeInterval) -> BioSampleFrame {
        BioSampleFrame(timestamp: t,
                       heartRateBPM: 70,
                       hrvNormalized: hrv,
                       breathRate: 0,
                       breathPhase: 0.25,
                       coherence: 0.5,
                       motionEnergy: 0,
                       source: .cameraPPG)
    }

    /// The nth accepted observation time — `observing` needs strictly increasing timestamps
    /// at least `minimumObservationInterval` apart, and `> 0` for the first one.
    private static func moment(_ n: Int) -> TimeInterval {
        PerformerSignature.minimumObservationInterval * TimeInterval(n + 1)
    }

    /// Comments blanked by `SourceText.codeOnly` (#453), which is string-aware.
    /// ⛔ The line this replaces called truncating at the first `//` "adequate here, because the
    /// scan looks for a Swift argument label that never appears inside a literal in that file".
    /// The second half was right and the premise was wrong: `EchoelStudioView.swift` DOES hold
    /// such a literal — the WeatherKit attribution URL — and it was the ONE line where the two
    /// shapes disagreed. Nothing this file asserts touches it, so the verdict is unchanged; the
    /// claim "no literal contains `//`" was simply never true.
    private static func codeOnly(_ source: String) -> String {
        SourceText.codeOnly(source)
    }

    private static func read(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(relativePath) not reachable from \(#filePath) — tree not co-located.")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
