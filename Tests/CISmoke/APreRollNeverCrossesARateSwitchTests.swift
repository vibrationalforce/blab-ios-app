// APreRollNeverCrossesARateSwitchTests.swift
// Echoel — #630 (Ultra-Audit 2026-08-19, finding B1, CRITICAL): a retroactive capture must
// never write frames that were sampled at a different rate than the file says.
//
// WHAT THIS GUARDS. The configuration-change watchdog re-installs the `RetroCapture` tap
// exactly BECAUSE the hardware rate moves — its own comment in `AudioEngine.swift` names the
// rPPG camera dropping the route from 48 kHz to 44.1 kHz, and says the re-install is what
// stops a retroactive export from being pitch-shifted ("viel höher"). It was not enough:
// `install(on:)` re-read the new rate into `captureSampleRate` and left up to 30 s of
// OLD-RATE frames sitting in the ring, and every pre-roll reader computes its window — and
// builds the output file's format — from `captureSampleRate` for the WHOLE window. The
// pitch-shift the comment claims to prevent therefore survived, moved out of the live tap and
// into the pre-roll history, where nothing named it.
//
// THE FIX, and the two shapes it deliberately takes. `install(on:)` records
// `rateBoundaryFrame` when — and only when — the rate actually CHANGED (most re-installs, a
// headphone unplug for instance, keep the rate and must keep their history). Then:
//   · the two FILE writers TRUNCATE at the boundary, through one `preRollWindow(_:)`. Right
//     after a switch that legitimately yields nothing: a capture may be SHORT, it may not be
//     WRONG, which is this file's own standing rule.
//   · `snapshotPreRoll` keeps its requested LENGTH and BLANKS the pre-boundary part instead,
//     because its contract is "give me `seconds` worth" and `RetroCaptureTests` pins exactly
//     that for a fresh instance. Truncating it would have turned a narrow rate fix into a
//     wide behaviour change — claim 3 is here so nobody makes that trade by accident.
//   · the waveform tick is deliberately NOT clamped: it bins the whole ring for a level
//     display, writes no file, and clamping would silently change what a bin means. Claim 5
//     pins the exception so a later "consistency" pass does not quietly fold it in.
//
// KIND (§1): claim 3 is BEHAVIOURAL against a real `RetroCapture`. Claims 1, 2, 4 and 5 are
// SOURCE SCANS, because reaching the rate-change path needs a live `AVAudioEngine` and a
// hardware route switch — that is a DEVICE probe, not something this bundle can stage.
//
// GRADING (#433 / §3, against `ebf5e69`) — measured, not assumed:
//   · claims 1, 2 and 4 are REGRESSIONS: `rateBoundaryFrame` and `preRollWindow` did not
//     exist, so each needle is 0 there and 1 (or 2) here. This file compiles against the
//     parent — it names no new symbol, only greps for text — so unlike the #629 family these
//     really would have RUN and failed.
//   · claim 5 is a COUNTERWEIGHT on its first half (the waveform tick never used the helper,
//     0 on both trees) and a REGRESSION on its second (the exception is only WRITTEN DOWN
//     here).
//   · claim 3 is a COUNTERWEIGHT — the length contract is unchanged by #630 and must stay so.
//
// Stripper: delegates to `SourceText.codeOnly` (#453). MEASURED **PROPHYLAKTISCH** — all
// fourteen source-scan verdicts (seven needles × two trees) are identical raw and stripped;
// no comment on either tree spells a needle in its code form.
//
// ⚠️ #364: a different mechanism is not forbidden — zeroing the ring on a rate change would
// also be correct, just wasteful (an ~11 MB memset at route-change time, and it discards
// good audio on every same-rate re-install). What is forbidden silently is going back to a
// pre-roll that can reach across a rate boundary.
//
// ⚠️ THE ORDER IN CLAIM 1 IS THE POINT, not decoration: if `captureSampleRate` is assigned
// BEFORE the comparison, the comparison is always false, the boundary is never recorded, and
// every other assertion in this file stays green while the defect is fully restored.

// ⚠️ FILE-GUARDED, not per-claim-guarded: `RetroCapture` itself lives inside
// `#if canImport(AVFoundation)`, so claim 3 could not even name the type without this. The
// three SOURCE scans would compile anywhere, but splitting the file by platform would put
// one law in two places — the thing this repo pays for repeatedly.
#if canImport(AVFoundation)
import Foundation
import XCTest
@testable import Echoelmusic

@MainActor
final class APreRollNeverCrossesARateSwitchTests: XCTestCase {

    private func codeLines(_ relative: String) throws -> [String] {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("source tree not present at \(path.path)")
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// 1 — REGRESSION: the boundary is recorded, and it is recorded BEFORE the rate is
    /// overwritten. Both halves, because the second one is invisible in a diff.
    func testTheRateChangeRecordsABoundaryBeforeOverwritingTheRate() throws {
        let lines = try codeLines("Sources/Echoelmusic/Audio/RetroCapture.swift")

        let compareIdx = lines.firstIndex { $0.contains("if format.sampleRate != captureSampleRate") }
        XCTAssertNotNil(compareIdx, """
            `install(on:)` no longer compares the new rate against the old one. Without that \
            comparison there is no way to tell a rate CHANGE (history is invalid) from an \
            ordinary re-install such as a headphone unplug (history is fine) — and the \
            watchdog re-installs on every route change (#630).
            """)
        let boundaryIdx = lines.firstIndex { $0.contains("rateBoundaryFrame = ringWriteFrame.pointee") }
        XCTAssertNotNil(boundaryIdx, """
            the rate boundary is no longer recorded. The tap then keeps up to 30 s of \
            old-rate frames that every pre-roll reader would write out under the NEW rate — \
            the "viel höher" pitch-shift the AudioEngine watchdog comment claims to prevent \
            (#630).
            """)
        let assignIdx = lines.firstIndex { $0.contains("captureSampleRate = format.sampleRate") }
        XCTAssertNotNil(assignIdx)
        if let c = compareIdx, let a = assignIdx {
            XCTAssertLessThan(c, a, """
                `captureSampleRate` is assigned BEFORE it is compared. The comparison is then \
                always false, the boundary is never recorded, and #630 is fully undone while \
                every other assertion in this file still passes. This ordering is the whole \
                mechanism.
                """)
        }
    }

    /// 2 — REGRESSION: the two FILE writers go through the one clamped window helper, and the
    /// helper actually consults the boundary.
    func testBothFileWritersTakeTheClampedWindow() throws {
        let lines = try codeLines("Sources/Echoelmusic/Audio/RetroCapture.swift")
        XCTAssertEqual(lines.filter { $0.contains("preRollWindow(requestedFrames:") }.count, 3, """
            the clamped-window helper no longer has exactly one declaration and two callers. \
            The two callers are the FILE writers (`writePreRollToFile` and `captureRecent`); \
            a writer that computes its own `max(0, end - frames)` again can reach back across \
            a rate switch, which is #630 restored for that one path.
            """)
        XCTAssertEqual(lines.filter {
            $0.contains("max(max(0, end - wanted), Int(rateBoundaryFrame))")
        }.count, 1, """
            `preRollWindow` no longer clamps to the rate boundary. It would then be an \
            elaborate spelling of the arithmetic it replaced, and all three call sites would \
            silently go back to reading old-rate frames (#630).
            """)
    }

    /// 3 — COUNTERWEIGHT: the snapshot's LENGTH contract is untouched. #630 deliberately
    /// blanks rather than truncates here; this is what stops a later slice from
    /// "harmonising" it with the file writers and breaking every caller that sizes a preview
    /// from the returned array.
    func testTheSnapshotStillReturnsTheRequestedLength() {
        let capture = RetroCapture()
        XCTAssertEqual(capture.snapshotPreRoll(seconds: 30).count, 30 * 48000 * 2, """
            `snapshotPreRoll` no longer returns the requested window from a fresh instance. \
            Its contract is "give me `seconds` worth", zero-padded before any audio exists — \
            `RetroCaptureTests` pins the same thing. #630 must blank the pre-boundary frames, \
            never shorten the array.
            """)
        XCTAssertTrue(capture.snapshotPreRoll(seconds: 1).allSatisfy { $0 == 0 }, """
            a fresh capture's snapshot is no longer silence. Nothing has been captured, so \
            every sample must be zero; a non-zero value here means the ring is being read \
            outside the frames actually written.
            """)
    }

    /// 4 — REGRESSION: the snapshot blanks the pre-boundary frames instead of copying them.
    func testTheSnapshotBlanksPreBoundaryFramesRatherThanCopyingThem() throws {
        let lines = try codeLines("Sources/Echoelmusic/Audio/RetroCapture.swift")
        XCTAssertEqual(lines.filter { $0.contains("guard startFrame + f >= boundary else { continue }") }.count, 1, """
            the snapshot copies every frame in its window again, boundary or not. It keeps \
            its length (claim 3) — so without this skip the pre-switch frames are handed to a \
            preview as if they belonged to the current rate, which is #630's defect surviving \
            in the one reader that was allowed to keep its window (#630).
            """)
    }

    /// 5 — the waveform tick's EXCEPTION. First half counterweight (it never used the
    /// helper), second half regression (the reason is only written down since #630).
    func testTheWaveformTickKeepsItsDeliberateException() throws {
        let lines = try codeLines("Sources/Echoelmusic/Audio/RetroCapture.swift")
        let tickIdx = lines.firstIndex { $0.contains("let framesPerBin = totalFrames / waveformResolution") }
        XCTAssertNotNil(tickIdx, """
            the waveform tick's binning line is gone — this claim's subject moved and the \
            exception it documents needs re-deciding rather than silently dropping (#630).
            """)
        // The exception itself: the tick must NOT be routed through the clamped helper. A
        // "consistency" pass that folds it in would shrink `totalFrames` at a route change
        // and silently change what one display bin means.
        if let t = tickIdx {
            let window = lines[max(0, t - 12)...t]
            XCTAssertFalse(window.contains { $0.contains("preRollWindow(") }, """
                the waveform tick now takes the clamped window. It bins the WHOLE ring into a \
                fixed number of display bins and writes no file, so clamping changes what a \
                bin means and makes the level meter jump at a route change — for no honesty \
                gain, because nothing here is exported or played (#630).
                """)
        }
    }
}
#endif
