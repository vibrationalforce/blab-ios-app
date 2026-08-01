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

    private func sine(phase: Double, length: Int = bufferLength) -> [Float] {
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
        // land on a sample boundary, so up to half a sample of phase error survives. At 64
        // samples per cycle one sample is 2*pi/64 rad and the sine's slope near zero is 1,
        // so the bound is ~0.098. Measured worst case is 0.067. If this ever fails it means
        // the trigger stopped locking, not that the tolerance was too tight.
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
        // Somewhere before the trigger the signal must have gone below the arming band —
        // that is what makes the crossing "rising" rather than merely "non-negative".
        let armedSomewhere = s[0..<i].contains { $0 < -ScopeTrigger.hysteresis }
        XCTAssertTrue(armedSomewhere, """
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

    /// THE DOOR. A scope nobody can open is worth nothing, and this repo has accumulated a
    /// shelf of exactly that (`SpectralDonutView`, `SpectralDonutView`'s whole FFT, the VJ
    /// overlay …). The view is mounted from `visualPanel`, which the Field chip opens.
    ///
    /// Source text, because `EchoelStudioView` is a SwiftUI view this bundle cannot build —
    /// the house pattern (`SoundPanelPresetBarTests`, `NoDoorlessStudioViewsTests`). It
    /// checks the CHAIN, not just the construction: `signalSection` must both exist and be
    /// referenced, because a section nothing mounts is precisely the #322 defect.
    func testTheScopeHasADoor() throws {
        let code = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertTrue(code.contains("AnalysisScopeView(reduceMotion:"), """
            Nothing constructs `AnalysisScopeView` any more, so the oscilloscope is a file \
            with no surface. If it was removed on purpose, remove this test and the view in \
            the same commit; if it was refactored, re-point this guard at the new call site.
            """)
        XCTAssertTrue(code.contains("private var signalSection"), """
            `signalSection` is gone. It exists to keep `visualPanel` under the ViewBuilder \
            ten-child cap — inlining its rows back into the panel is what makes that closure \
            fail to compile with "extra argument in call".
            """)
        // Referenced, not merely declared: two occurrences = the declaration plus one mount.
        let mounts = code.components(separatedBy: "signalSection").count - 1
        XCTAssertGreaterThanOrEqual(mounts, 2, """
            `signalSection` appears \(mounts) time(s) — it is declared but never mounted, \
            which is the #322 orphan shape exactly. The Field panel must render it.
            """)
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
