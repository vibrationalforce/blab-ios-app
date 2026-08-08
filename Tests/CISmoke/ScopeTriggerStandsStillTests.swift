// ScopeTriggerStandsStillTests.swift
// Echoel — #347 Slice 1. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ WHAT THIS PINS, and why it is a BEHAVIOURAL test rather than a text guard: an
// oscilloscope's entire value is that it stands still. `AudioEngine.copyLatestOutputSamples`
// returns the newest N samples, whose phase has no relation to the previous frame's — so
// plotting them directly makes a steady tone slide sideways. `ScopeTrigger` is the fix, and
// "does it actually lock" is exactly the kind of claim that a comment cannot carry.
//
// The central test feeds the SAME tone at two different phases and asserts the two
// triggered windows are the same picture. That is the promise, stated as maths.
//
// ⛔ CONTEXT A LATER SESSION WILL NEED: the shader already contains a "Scope" (style index
// 8) and a "Lissajous" (6), retired from the UI by founder curation on 2026-07-08. They are
// NOT what this replaces and must not be confused with it: `fieldScope(p, toneHz, phase,
// coh)` takes the NOTE frequency and bio, never audio — `MetalBioView` receives no samples
// at all. Those looks are drawn figures. This is the real signal. Re-labelling the shader
// look as an oscilloscope would be a lying control (#164/#227 class).

import Foundation
import XCTest
@testable import Echoelmusic

final class ScopeTriggerStandsStillTests: XCTestCase {

    private static let period = 64.0          // samples per cycle
    private static let bufferLength = 2048
    private static let windowLength = 512

    // ⛔ THE TYPE NAME SPELLED OUT, and NOT `Self.` — which is what the first fix wrote and
    // which took the blocking gate down: "error: covariant 'Self' type cannot be referenced
    // from a default argument expression". Swift rejects `Self` in a default argument inside
    // ANY class, `final` or not; the finality of this one is irrelevant to that rule.
    //
    // The original bare `bufferLength` was legal all along. It was changed for a purely
    // cosmetic reason (a reviewer noted it is the only unqualified-static-in-default-argument
    // in the repo) and that cosmetic change broke the build — the third parse-level trap in
    // two days, and the only one that was self-inflicted on WORKING code. The lesson is not
    // about `Self`: it is that a compiling line changed for readability alone still needs the
    // gate, because "obviously equivalent" is a claim about the language, not about the code.
    private func sine(phase: Double,
                      length: Int = ScopeTriggerStandsStillTests.bufferLength) -> [Float] {
        (0..<length).map { Float(sin(2 * Double.pi * (Double($0) / Self.period) + phase)) }
    }

    /// THE promise. Two buffers of the same tone captured at unrelated phases must, after
    /// triggering, draw the same picture — otherwise the trace slides and the view is
    /// useless as an instrument.
    func testTwoPhasesOfTheSameToneDrawTheSamePicture() {
        let a = sine(phase: 0)
        let b = sine(phase: 1.7)
        let wa = ScopeTrigger.window(a, start: ScopeTrigger.startIndex(in: a, windowLength: Self.windowLength),
                                     count: Self.windowLength)
        let wb = ScopeTrigger.window(b, start: ScopeTrigger.startIndex(in: b, windowLength: Self.windowLength),
                                     count: Self.windowLength)

        var worst: Float = 0
        for i in 0..<Self.windowLength { worst = Swift.max(worst, abs(wa[i] - wb[i])) }

        // 0.12 is the SAMPLE-QUANTISATION floor, not a slack tolerance: the trigger can only
        // land on a sample boundary, so up to a FULL sample of phase error survives — the
        // two captures can round to adjacent samples in opposite directions. (The first
        // version of this comment said "half a sample" and then did the arithmetic with a
        // whole one. The arithmetic was right; the sentence above it was not, and the
        // sentence is what a later reader would have used to justify tightening the bound.
        // The measured residual for these two phases is 0.685 samples.) At 64 samples per
        // cycle one sample is 2*pi/64 rad and the sine's slope near zero is 1, so the bound
        // is ~0.098. Measured worst case is 0.067. If this ever fails it means the trigger
        // stopped locking, not that the tolerance was too tight.
        XCTAssertLessThan(worst, 0.12, """
            Two captures of the same tone at different phases drew pictures differing by \
            \(worst). The scope no longer locks, so on device the trace will slide sideways \
            at the beat rate between the frame period and the signal period — which reads as \
            a broken visual, not as a subtle one.
            """)
    }

    /// The trigger point must be a RISING crossing, or the trace locks to the wrong half of
    /// the cycle and the picture is upside down relative to what the ear expects.
    func testTheTriggerLandsOnARisingCrossing() {
        let s = sine(phase: 0.4)
        let i = ScopeTrigger.startIndex(in: s, windowLength: Self.windowLength)

        XCTAssertGreaterThan(i, 0, """
            No trigger was found in a clean sine. The fallback (index 0) is only supposed to \
            be reached on silence, DC, or a period longer than the search range.
            """)
        XCTAssertGreaterThanOrEqual(s[i], 0, """
            The trigger fired at \(s[i]), below the level. It must fire on the sample that \
            reaches or crosses the level going UP.
            """)
        // THE crossing itself: the sample before the trigger must be negative and the
        // trigger sample non-negative. This replaces an "did the signal go below the arm
        // band ANYWHERE before i" check, which on a sine that spends half its time negative
        // is satisfied by almost any index — it would have passed for a trigger landing on
        // a FALLING edge, which is precisely the failure it was written to catch.
        XCTAssertLessThan(s[i - 1], 0, """
            The sample before the trigger is \(s[i - 1]), not negative — so index \(i) is \
            not a rising zero crossing. The trace will lock to the wrong half of the cycle \
            and the picture will read upside down against what the ear expects.
            """)

        // And the arm must still be what MADE it a crossing rather than a coincidence: the
        // signal has to have been below the arming band at some earlier point.
        XCTAssertTrue(s[0..<i].contains { $0 < -ScopeTrigger.hysteresis }, """
            The trigger fired without the signal ever dropping below the arming band, so it \
            latched onto the first non-negative sample rather than onto a crossing.
            """)
    }

    /// Silence must not invent a trigger. An untriggered scope drawing from the buffer start
    /// is the honest state; a fabricated one would make noise look periodic.
    func testSilenceAndDCFallBackToTheBufferStart() {
        XCTAssertEqual(ScopeTrigger.startIndex(in: [Float](repeating: 0, count: Self.bufferLength),
                                               windowLength: Self.windowLength), 0)
        // Constant 0.5 never drops below the arming band, so it can never fire.
        XCTAssertEqual(ScopeTrigger.startIndex(in: [Float](repeating: 0.5, count: Self.bufferLength),
                                               windowLength: Self.windowLength), 0, """
            A DC level above the trigger fired the trigger. Arming requires the signal to \
            fall below the level first; without that, any constant would "trigger" at once.
            """)
    }

    /// NaN can neither arm nor fire. A bad frame upstream must not decide where the picture
    /// starts — and it must not crash the draw loop either.
    func testANonFiniteSampleCannotDecideWhereThePictureStarts() {
        var s = sine(phase: 0)
        s[10] = .nan
        s[11] = .infinity
        let i = ScopeTrigger.startIndex(in: s, windowLength: Self.windowLength)
        XCTAssertTrue(i >= 0 && i + Self.windowLength <= s.count, """
            The trigger returned \(i), which is outside the buffer once the window is added. \
            The whole point of bounding the search is that the caller never has to clamp.
            """)
        let w = ScopeTrigger.window(s, start: i, count: Self.windowLength)
        XCTAssertTrue(w.allSatisfy { $0.isFinite }, """
            A non-finite sample reached the draw window. Canvas turns that into an undrawn \
            or wildly out-of-frame path, which looks like a rendering bug rather than a bad \
            input.
            """)

        // Disarming on a non-finite sample is DELIBERATE and worth pinning: a buffer whose
        // rising edge contains a NaN is not trustworthy for locating phase, so that period
        // is skipped and the next one re-arms.
        var poisoned = [Float](repeating: 1, count: Self.bufferLength)
        poisoned[0] = -1
        poisoned[1] = .nan
        XCTAssertEqual(ScopeTrigger.startIndex(in: poisoned, windowLength: Self.windowLength), 0, """
            A NaN between the arming sample and the rising sample still produced a trigger. \
            It must disarm instead.
            """)
    }

    /// Degenerate requests must return a blank frame, never trap. This runs inside a draw
    /// loop, where a crash is the one outcome worse than an empty picture.
    func testDegenerateRequestsReturnABlankFrameInsteadOfTrapping() {
        let s = sine(phase: 0, length: 100)
        XCTAssertEqual(ScopeTrigger.startIndex(in: s, windowLength: 100), 0)
        XCTAssertEqual(ScopeTrigger.startIndex(in: s, windowLength: 0), 0)
        XCTAssertEqual(ScopeTrigger.startIndex(in: [], windowLength: 512), 0)

        XCTAssertEqual(ScopeTrigger.window(s, start: 90, count: 512).count, 512, """
            An out-of-range window did not return a full-length blank frame. The caller \
            draws whatever comes back; a short array would silently shorten the trace.
            """)
        XCTAssertTrue(ScopeTrigger.window(s, start: 90, count: 512).allSatisfy { $0 == 0 })
        XCTAssertTrue(ScopeTrigger.window(s, start: -1, count: 8).allSatisfy { $0 == 0 })
    }

    /// The vertical scale is FIXED, not auto-ranging — that is what lets the picture show
    /// that the mix got louder, and lets a clipped take look clipped.
    func testTheTraceIsClampedNotNormalised() {
        let loud = [Float](repeating: 4, count: 64)
        let w = ScopeTrigger.window(loud, start: 0, count: 64)
        XCTAssertTrue(w.allSatisfy { $0 == 1 }, """
            A signal above full scale was rescaled instead of clamped. An auto-ranging scope \
            cannot show a level change at all, which is most of what the view is for.
            """)
        XCTAssertEqual(ScopeTrigger.peak(w), 1, accuracy: 0.0001)

        let quiet = sine(phase: 0, length: 64).map { $0 * 0.25 }
        XCTAssertEqual(ScopeTrigger.peak(ScopeTrigger.window(quiet, start: 0, count: 64)),
                       0.25, accuracy: 0.02, """
            A quiet signal did not stay quiet in the trace. Peak is the "is anything \
            playing" gate; if it rescales, the gate can never read silent.
            """)
    }

    /// ⛔ THE SCOPE'S OWN DOOR ASSERTION IS RETIRED (2026-08-02). The founder struck the
    /// oscilloscope out in red on the screenshot that asked for a physically honest picture of
    /// the sound (#385); the mount left `signalSection` one cycle later and the view is now
    /// PARKED — doorless on purpose, file intact, one line to restore. The reasoning for
    /// retiring rather than inverting the assertion is written out once, on
    /// `PoincareViewDoorTests.testTheParkedPlotStillExistsAsAFile`, because both views were
    /// struck by the same mark on the same day.
    ///
    /// WHAT THIS TEST STILL OWNS, and why it is not deleted: the SECTION. `signalSection` did
    /// not go anywhere — it now holds the wavefront view and the spectrum — and a section that
    /// exists but is never mounted is the #322 defect regardless of which pictures are in it.
    /// So the chain check below is unchanged, and the scope's own existence is asserted as a
    /// file rather than as a mount.
    ///
    /// Source text, because `EchoelStudioView` is a SwiftUI view this bundle cannot build —
    /// the house pattern (`SoundPanelPresetBarTests`, `NoDoorlessStudioViewsTests`).
    func testTheSignalSectionHasADoorAndTheParkedScopeStillExists() throws {
        let code = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        let view = try source("Sources/Echoelmusic/Studio/AnalysisScopeView.swift")
        XCTAssertTrue(view.contains("struct AnalysisScopeView"), """
            `AnalysisScopeView.swift` no longer declares `AnalysisScopeView`. The view is \
            PARKED, not retired — `signalSection` records the promise that restoring it costs \
            one line, and that promise needs the file to still be there. If it was genuinely \
            deleted, delete this test file with it and say so in the commit.
            """)
        XCTAssertTrue(code.contains("private var signalSection"), """
            `signalSection` is gone. It exists to keep `visualPanel` under the ViewBuilder \
            ten-child cap — inlining its rows back into the panel is what makes that closure \
            fail to compile with "extra argument in call".
            """)
        // COMMENTS STRIPPED FIRST, the way `NoDoorlessStudioViewsTests` does it. The naive
        // count found THREE occurrences — declaration, mount, and the prose above the
        // declaration explaining why the section exists — so deleting the actual mount still
        // left two and the guard still passed. A door test that survives the door being
        // removed is worse than no door test: it reports a green nobody earned.
        let mounts = Self.stripComments(code)
            .components(separatedBy: "signalSection").count - 1
        XCTAssertGreaterThanOrEqual(mounts, 2, """
            `signalSection` appears \(mounts) time(s) in the CODE (comments excluded) — it \
            is declared but never mounted, which is the #322 orphan shape exactly. The \
            Field panel must render it.
            """)
    }

    /// THE READOUT ABOVE THE PICTURE, pinned because it shipped wrong once and the failure
    /// was invisible to every other gate: the first version printed
    /// `20·log10(max(masterLevel, masterLevelR))` as "Peak … dBFS". `masterLevel` is an RMS
    /// times three, hard-clamped to 1.0 and measured BEFORE the master chain — so it read
    /// ~6.5 dB high at −20 dBFS and pinned at "0.0 dBFS" for everything above ≈ −6.5. It
    /// compiled, it looked plausible, and only a human comparing it against the Master panel
    /// would ever have caught it. Three separate properties are asserted because the defect
    /// needed all three to be wrong at once.
    func testThePeakReadoutIsAPeakAndNotTheRMSMeter() throws {
        let code = try source("Sources/Echoelmusic/Studio/AnalysisScopeView.swift")

        XCTAssertTrue(code.contains("audioEngine.masterOutputTruePeakDb"), """
            The scope's readout no longer reads `masterOutputTruePeakDb` — the meter's own \
            decaying true-peak hold, measured at the chain output with `outputTrimDb` \
            applied. Whatever replaced it has to answer the same three questions: is it a \
            PEAK (not an RMS), is it measured AFTER the master chain, and does it carry the \
            output trim? If not, the number on screen is not the number the Master panel \
            shows and the two surfaces disagree about the same signal.
            """)
        XCTAssertFalse(code.contains("audioEngine.masterLevel"), """
            `masterLevel` is back in the scope's readout. It is `vDSP_rmsqv(…) × 3.0` \
            clamped to 1.0 — a meter-ballistics value with a contract to \
            `AutoMixChain.updateLUFS`, NOT a dBFS source. Rendering it as decibels pins \
            everything above ≈ −6.5 dBFS at "0.0" while the mix keeps getting louder: a \
            readout that stops responding exactly when it matters (#164/#227).
            """)
        XCTAssertFalse(code.contains("String(format:"), """
            A `String(format:)` readout is back in the scope. #267 removed exactly this \
            class app-wide: one surface printing "−8.3" while every other prints "−8,3" is \
            the defect, and it is invisible to anyone testing in English.
            """)
        XCTAssertTrue(code.contains("EchoelDecimalText.string(db"), """
            The peak value no longer goes through `EchoelDecimalText`. See #267 — the \
            decimal separator is a setting, not a literal.
            """)
    }

    /// Drops `//` line comments so a guard counts call sites and not the prose about them.
    ///
    /// ⛔ #460: this was a private naive truncate at the first `//`, which is NOT the same
    /// operation — it also cuts a `//` that sits INSIDE a string literal. The one source this file
    /// strips, `EchoelStudioView.swift`, carries one — the WeatherKit attribution
    /// `URL(string: "https://developer.apple.com/…")`, which the old strip left as
    /// `URL(string: "https:`. Exactly one line.
    /// Verdict-neutral on today's anchors (measured: 0 flips over every literal in this file) —
    /// but a future needle anywhere on such a line would have gone red on CORRECT code.
    /// `SourceText.codeOnly` (#453) is the ONE definition: string-aware, ordered,
    /// line-count-preserving. Do not re-inline a local copy.
    private static func stripComments(_ code: String) -> String {
        SourceText.codeOnly(code)
    }

    // MARK: - helpers

    private func source(_ path: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                Source tree not reachable from the test bundle — skipping rather than \
                reporting a green this file did not earn.
                """)
        }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
