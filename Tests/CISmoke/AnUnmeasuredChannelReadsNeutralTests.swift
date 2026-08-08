// AnUnmeasuredChannelReadsNeutralTests.swift
// Echoel — #497. The third and fourth members of the `hrvForSound` / `coherenceForSound`
// family. `coherenceForSound`'s own doc records that the sweep was left INCOMPLETE; this
// finishes it for the two sound channels that were still read RAW.
//
// ⭐ THE LAW, and it is not this slice's invention — the ENGINE writes it down. Every
// argument of `EchoelDDSP.applyBioReactive` declares its own neutral in its signature
// (`heartRate: Float = 0.5`, `breathPhase: Float = 0.5`). A caller that hands it a raw
// field when the publisher measured nothing is not passing "no information"; it is passing
// a specific, extreme instruction that the engine cannot tell from a real body.
//
// ⭐ WHAT THE TWO RAW READS COST, derived from the engine's own arithmetic, not estimated:
//   · heart rate — both producers spelled `clampUnit((frame.heartRateBPM - 40) / 160)`,
//     which is `0.0` with no lock. `applyBioReactive` maps it
//     `(1.0 + (heartRate - 0.5) * 0.5).clamped(to: 0.75...1.25)` → **0.75**, so the patch's
//     vibrato depth AND rate ran **25 % low, permanently**, indistinguishable from a real
//     40 BPM heart. On this app's acquisition record (#304/#410/#415 — fragile, ~19–32 s to
//     lock, drops out) that is the COMMON state of a take, not an edge case.
//   · breath phase — raw `0`. The engine maps
//     `breathSwell = 0.5 - 0.5*cos(phase*2π)`, then
//     `amplitude *= (1 - swellDepth + swellDepth*breathSwell)`: neutral 0.5 → ×1.0, raw 0 →
//     **×0.90 (−0.92 dB)** on `.natural` and ×0.82 on `.harmonicSeries`. And `0` is what
//     THREE of the four publishers write with no respiration — `PolarH10BioPublisher` and
//     `FaceExpressionBioPublisher` write the literal always (neither derives breathing),
//     `CameraRPPGBioPublisher` writes it below its confidence threshold. So the shipped BLE
//     strap ran the WHOLE instrument a decibel under its own patch, forever.
//
// ⚠️ EHRLICHE BENOTUNG — this file CANNOT BE GRADED against the pre-#497 tree at all, which
// is the #464 situation said plainly instead of dressed up. Every behaviour case names
// `BioSampleFrame.heartRateForSound` / `.breathPhaseForSound`, which do not exist there, so
// the bundle does not compile and NO assertion has a verdict. Hand-transcribed: the two
// source scans would be red for their STATED reason (both files spell the raw formula), the
// six behaviour cases could never have been red because the same commit creates the symbol
// they drive, and the three counterweights are green on both trees. Booking the behaviour
// cases as regressions would be the #433 defect in the flattering direction.
//
// ⚠️ `SourceText.codeOnly` is LOAD-BEARING here and that is MEASURED, not assumed (#484 and
// #485 each had to retract exactly this claim, #486 twice): the retraction comments this
// slice writes quote `clampUnit((frame.heartRateBPM - 40) / 160)` and
// `clampUnit(frame.breathPhase)` VERBATIM in both files. Raw: present in both. Stripped:
// absent in both. A raw-text scan would therefore be red on CORRECT code — 2 of 4 needles
// flip, in both files. Same collision as #486/#491: this repo writes down what it removed.
//
// ⚠️ AND THE LIMIT FIRST. The behaviour half is real end-to-end (`BioSampleFrame` is a
// public Foundation-only value type, so these drive the shipped accessors). The WIRING half
// is a SOURCE SCAN: `applyLatestIfFresh` / the poly enqueue are `private` members of
// `@MainActor` types this bundle cannot instantiate. That a take AUDIBLY stops running 25 %
// flat on vibrato and 0.92 dB down is a hearing check on device, and it is open — the same
// one #312 has had open since 07-31.

import Foundation
import XCTest
@testable import Echoelmusic

final class AnUnmeasuredChannelReadsNeutralTests: XCTestCase {

    // MARK: - Fixtures

    private static func frame(bpm: Float,
                              breathRate: Float = 0,
                              breathPhase: Float = 0) -> BioSampleFrame {
        BioSampleFrame(timestamp: 1,
                       heartRateBPM: bpm,
                       hrvNormalized: 0.5,
                       breathRate: breathRate,
                       breathPhase: breathPhase,
                       coherence: 0.5,
                       motionEnergy: 0,
                       source: .cameraPPG)
    }

    private static let producers = [
        "Sources/Echoelmusic/Tools/PolySynthVoice.swift",
        "Sources/Echoelmusic/Tools/BioReactiveSynthVoice.swift"
    ]

    private static func code(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // Tests/CISmoke
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // repo root
        // ⚠️ The skip gates on the DIRECTORY, never on the files (#475): wrapping each read
        // in a `fileExists` check would turn the very catastrophe this guard stands against
        // — a producer file deleted — into a green skip. A missing FILE is a hard failure.
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("Sources/Echoelmusic not reachable from \(root.path) — "
                          + "the bundle is running outside a checkout, so these scans "
                          + "would prove nothing either way.")
        }
        let text = try String(contentsOf: root.appendingPathComponent(relative),
                              encoding: .utf8)
        // #367: anchor on presence first. A scan that only forbids the old spelling stays
        // green on a tree that lost the file — the failure mode the blocking bundle exists
        // to prevent.
        XCTAssertFalse(text.isEmpty, "\(relative) is empty — the scan below would prove nothing")
        return SourceText.codeOnly(text)
    }

    // MARK: - Behaviour: heart rate

    /// The defect, at the channel that carries it furthest: no lock → the engine's own
    /// declared neutral, not the bottom of the scale.
    func testAnUnmeasuredPulseReadsTheEnginesNeutral() {
        XCTAssertEqual(Self.frame(bpm: 0).heartRateForSound, 0.5, accuracy: 1e-6,
                       "A frame with no pulse lock must hand `applyBioReactive` the neutral "
                       + "it declares (`heartRate: Float = 0.5`), not 0.0 — 0.0 is a 40 BPM "
                       + "heart and drops vibrato depth and rate 25 % under the patch.")
    }

    /// ⛔ THE LINE THIS PROPERTY MUST NOT CROSS. It covers the ABSENCE of a reading, never a
    /// LOW one. A measured 40 BPM is a real, rare, meaningful body and still reads 0.0 —
    /// making it "neutral too" would be inventing a number, the #424/#426/#433/#461 class.
    func testAMeasuredFortyStillReadsTheBottomOfTheScale() {
        XCTAssertEqual(Self.frame(bpm: 40).heartRateForSound, 0.0, accuracy: 1e-6,
                       "40 BPM is a MEASUREMENT. Only absence gets the neutral.")
    }

    /// Pins the endpoints, because the engine's own parameter doc disagrees with its own
    /// arithmetic: it says "0=40bpm, 1=180bpm" while the sentinel comment forty lines below
    /// says 200 — and 200 is what `(bpm - 40) / 160` actually yields. Whoever "fixes" the
    /// doc toward 180 must move this line too, deliberately.
    func testTheScaleRunsFromFortyToTwoHundred() {
        XCTAssertEqual(Self.frame(bpm: 200).heartRateForSound, 1.0, accuracy: 1e-6)
        XCTAssertEqual(Self.frame(bpm: 240).heartRateForSound, 1.0, accuracy: 1e-6,
                       "Above the top the clamp holds; it must not run past 1.")
        XCTAssertEqual(Self.frame(bpm: 120).heartRateForSound, 0.5, accuracy: 1e-6,
                       "120 BPM and 'unmeasured' are the same number here by construction — "
                       + "worth knowing before anyone reads a 0.5 as evidence of a reading.")
    }

    /// Both non-finite directions, and they fail differently — which is why the accessor
    /// guards `isFinite` explicitly instead of leaning on the `> 0` comparison. NaN was
    /// already safe by accident (`NaN > 0` is false); `+inf` passes that gate and clamps to
    /// 1.0, i.e. the TOP of the scale from a frame that measured nothing.
    func testANonFinitePulseIsAbsentRatherThanExtreme() {
        XCTAssertEqual(Self.frame(bpm: .nan).heartRateForSound, 0.5, accuracy: 1e-6)
        XCTAssertEqual(Self.frame(bpm: .infinity).heartRateForSound, 0.5, accuracy: 1e-6,
                       "+inf is not a measurement; without the isFinite guard it reads 1.0.")
    }

    // MARK: - Behaviour: breath phase

    /// The gate is `breathRate`, deliberately, and this is the case that proves why: the
    /// phase itself has NO unknown sentinel — `0` is a meaningful position (exhale start) —
    /// so it cannot answer the question about itself. Both raw phases below are the SAME
    /// value to a value-gate and must both read neutral.
    func testAnUnmeasuredBreathReadsTheEnginesNeutralWhateverThePhaseSays() {
        XCTAssertEqual(Self.frame(bpm: 60, breathRate: 0, breathPhase: 0).breathPhaseForSound,
                       0.5, accuracy: 1e-6,
                       "No respiration → neutral. The raw 0 costs the whole voice 0.92 dB.")
        XCTAssertEqual(Self.frame(bpm: 60, breathRate: 0, breathPhase: 0.9).breathPhaseForSound,
                       0.5, accuracy: 1e-6,
                       "A held phase beside `breathRate: 0` is the camera's pulse-hold "
                       + "republish — a swell driven by a frozen phase is not a breath.")
    }

    /// The counterpart, and the one a later "simplification" would break: a MEASURED breath
    /// passes its phase through untouched, including the extremes. Collapsing this property
    /// to `max(phase, something)` would flatten a real exhale.
    func testAMeasuredBreathPassesItsPhaseThrough() {
        XCTAssertEqual(Self.frame(bpm: 60, breathRate: 6, breathPhase: 0).breathPhaseForSound,
                       0.0, accuracy: 1e-6,
                       "A measured exhale start IS 0 and must stay 0.")
        XCTAssertEqual(Self.frame(bpm: 60, breathRate: 6, breathPhase: 0.75).breathPhaseForSound,
                       0.75, accuracy: 1e-6)
    }

    /// ⚠️ Non-finite is ABSENT, not clamped — and the distinction is the whole point:
    /// `clamped(to: 0...1)` maps NaN to the LOWER bound, which is exactly the −0.92 dB
    /// extreme this property exists to stop being the fallback (`FloatingPointClamp.swift`).
    func testANonFiniteBreathPhaseIsAbsentRatherThanExtreme() {
        XCTAssertEqual(
            Self.frame(bpm: 60, breathRate: 6, breathPhase: .nan).breathPhaseForSound,
            0.5, accuracy: 1e-6,
            "NaN through the clamp would be 0.0 — the very value #497 removes.")
    }

    // MARK: - Wiring (source scans; codeOnly is load-bearing, see the header)

    /// Both sound producers must READ the frame's decision instead of re-deriving it.
    func testBothSoundProducersReadTheNeutralAccessors() throws {
        for path in Self.producers {
            let code = try Self.code(path)
            XCTAssertTrue(code.contains("frame.heartRateForSound"),
                          "\(path) must hand the engine `BioSampleFrame.heartRateForSound`.")
            XCTAssertTrue(code.contains("frame.breathPhaseForSound"),
                          "\(path) must hand the engine `BioSampleFrame.breathPhaseForSound`.")
            XCTAssertTrue(code.contains("tryEnqueue("),
                          "\(path) lost its bio enqueue entirely — the two reads above would "
                          + "then be satisfied by nothing at all (#343).")
        }
    }

    /// The negative half, and the one that needs the comment stripper: neither producer may
    /// go back to deriving the value locally.
    func testNeitherProducerStillWritesTheRawFormula() throws {
        for path in Self.producers {
            let code = try Self.code(path)
            XCTAssertFalse(code.contains("(frame.heartRateBPM - 40) / 160"),
                           "\(path) re-derives the heart-rate scale locally. That spelling "
                           + "hands the engine 0.0 — the bottom of the scale — whenever the "
                           + "publisher has not locked a pulse (#497).")
            XCTAssertFalse(code.contains("clampUnit(frame.breathPhase)"),
                           "\(path) re-derives the breath phase locally. That spelling hands "
                           + "the engine a raw 0 with no respiration = −0.92 dB (#497).")
        }
    }

    // MARK: - Counterweights (green on both trees, and the point of the file)

    /// ⭐ THE ACCESSORS ARE ONLY CORRECT BECAUSE THE ENGINE DECLARES 0.5. If someone changes
    /// the engine's neutral, "0.5" here stops being the neutral and becomes a magic number —
    /// and nothing else in the repo would notice. Counts are compared to each other rather
    /// than pinned to a literal so that deleting a dead overload stays legal (#364).
    func testTheEngineStillDeclaresBothNeutralsAsAHalf() throws {
        let code = try Self.code("Sources/Echoelmusic/DSP/EchoelDDSP.swift")
        let hearts = code.components(separatedBy: "heartRate: Float = 0.5").count - 1
        let breaths = code.components(separatedBy: "breathPhase: Float = 0.5").count - 1
        XCTAssertGreaterThan(hearts, 0,
                             "`applyBioReactive` no longer declares 0.5 as the heart-rate "
                             + "neutral — `heartRateForSound` is then returning a number that "
                             + "matches nothing.")
        XCTAssertEqual(hearts, breaths,
                       "The two neutrals must move together; they are one decision.")
    }

    /// ⭐ The #343 form. A tree that DELETED the whole bio path would pass every negative
    /// scan above. The two older twins are pinned at both producers so that losing the
    /// capability is red, not quiet.
    func testTheSurvivingTwinsAreStillReadAtBothProducers() throws {
        for path in Self.producers {
            let code = try Self.code(path)
            XCTAssertTrue(code.contains("frame.hrvForSound"), "\(path) lost `hrvForSound`.")
            XCTAssertTrue(code.contains("frame.coherenceForSound"),
                          "\(path) lost `coherenceForSound`.")
        }
    }

    /// ⭐ The gate for the breath half lives on `breathRate`, not on the phase. If someone
    /// "simplifies" `hasMeasuredBreath` to look at `breathPhase`, every one of the neutral
    /// cases above silently changes meaning, so the premise is asserted rather than assumed.
    func testTheBreathGateStillAsksTheRateAndNotThePhase() {
        XCTAssertTrue(Self.frame(bpm: 60, breathRate: 6, breathPhase: 0).hasMeasuredBreath,
                      "A phase of 0 beside a real rate is a MEASUREMENT (exhale start).")
        XCTAssertFalse(Self.frame(bpm: 60, breathRate: 0, breathPhase: 0.5).hasMeasuredBreath,
                       "A mid-scale phase beside no rate is an ABSENCE.")
    }
}
