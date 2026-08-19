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
//   · claim 5 is a COUNTERWEIGHT, FULL STOP. ⛔ #630b: it was graded "counterweight on its
//     first half, regression on its second (the exception is only WRITTEN DOWN here)" — and
//     the second half has NO ASSERTION BEHIND IT, nor could it: `SourceText.codeOnly` blanks
//     comments, so this bundle cannot see whether anything is written down. Both of claim 5's
//     assertions are green on the parent. Calling half of it a regression was the flattering
//     direction §3 names, in the same file that pins an ordering precisely because a silent
//     no-op looks like a fix.
//   · claim 6 arrived with #630b. Measured on all THREE trees rather than described: against
//     `28b3805` (#630 itself) all three of its assertions are red — the helper was used, the
//     request-sized `frames` was gone, the blank did not exist. Against `ebf5e69` only the
//     BLANK assertion is red; the other two were already true there, because the method was
//     length-stable before #630 broke it. Three parents, named per assertion rather than
//     averaged into one comfortable word.
//   · claim 3 is a COUNTERWEIGHT — the length contract is unchanged by #630 and must stay so.
//
// Stripper: delegates to `SourceText.codeOnly` (#453). MEASURED **PROPHYLAKTISCH** — every
// source-scan verdict is identical raw and stripped; no comment on either tree spells a
// needle in its code form. ⛔ #630b: the count here read "seven needles / fourteen verdicts"
// and the needles were eight even then (claim 1 carries three, claim 2 two, claim 4 one,
// claim 5 two). With claim 6 they are eleven. The number is dropped rather than corrected a
// third time — this file's own §0 rule is that a hand count of its own assertions is exactly
// the kind of number that goes stale, and nothing depends on it.
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

    /// 2 — REGRESSION: the truncating window exists, is used, and actually consults the
    /// boundary. ⛔ #630b: this claim was called "the two FILE writers" and the count `3` was
    /// read as declaration-plus-two-writers. `captureRecent` must NOT be one of them (claim
    /// 6), and the third occurrence today is the honest pre-roll figure in `startRecording`'s
    /// log. The count is kept because it still forbids an un-clamped second writer, but what
    /// it MEANS is pinned by claim 6, not by this arithmetic.
    func testBothFileWritersTakeTheClampedWindow() throws {
        let lines = try codeLines("Sources/Echoelmusic/Audio/RetroCapture.swift")
        XCTAssertEqual(lines.filter { $0.contains("preRollWindow(requestedFrames:") }.count, 3, """
            the clamped-window helper no longer has exactly one declaration and two call \
            sites (`writePreRollToFile`, and `startRecording`'s log figure). A pre-roll writer \
            that computes its own `max(0, end - frames)` again can reach back across a rate \
            switch. WHICH readers may truncate is claim 6's subject, not this count's.
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
            // #630b: forbid the CLAMP as well as the helper. Claim 5's first form banned one
            // spelling — `preRollWindow(` — and an inline
            // `max(max(0, endFrame - totalFrames), Int(rateBoundaryFrame))` right above the
            // binning line is the natural way to "harmonise" the tick without the helper, and
            // would have passed untouched.
            XCTAssertFalse(window.contains { $0.contains("rateBoundaryFrame") }, """
                the waveform tick now consults the rate boundary by hand. Same objection as \
                the helper: it bins the WHOLE ring into a fixed number of display bins, so \
                clamping changes what a bin means, and blanking would show a gap that reads \
                as "the engine stopped" in a level meter (#630b).
                """)
        }
    }

    /// 6 — REGRESSION (#630b): `captureRecent` keeps its LENGTH. This is the claim that would
    /// have caught #630's own worst defect, and it did not exist then.
    ///
    /// Its two consumers both do duration arithmetic on the result: `VideoMuxer` end-aligns
    /// to `CMTimeMinimum(video, audio)` — so a short audio file CUTS THE VIDEO, and
    /// `VisualRecorder` then deletes the full-length original — and `SingleExport`'s trim
    /// resolver treats a too-short file as "export it all", reported as success. Truncating
    /// here traded a partly pitch-shifted clip for destroyed footage and a silently wrong loop.
    func testTheRetroactiveCaptureKeepsItsRequestedLength() throws {
        let lines = try codeLines("Sources/Echoelmusic/Audio/RetroCapture.swift")
        let start = lines.firstIndex { $0.contains("func captureRecent(seconds: Double) -> URL?") }
        // ⛔ #630b: the first version anchored the END on `// MARK: - Helpers` — a COMMENT,
        // which `SourceText.codeOnly` blanks. The bracket therefore failed on EVERY tree and
        // this claim was red on a correct one, the #626 failure exactly. Both anchors must be
        // CODE. Caught by the §0 transcription before the commit, not after.
        let end = lines.firstIndex { $0.contains("private func makeRecordingURL() throws -> URL") }
        guard let s = start, let e = end, s < e else {
            return XCTFail("could not bracket `captureRecent` — its declaration or the "
                           + "following `makeRecordingURL` moved, so this claim measures nothing")
        }
        let body = Array(lines[s...e])

        XCTAssertFalse(body.contains { $0.contains("preRollWindow(") }, """
            `captureRecent` takes the TRUNCATING window again. Its callers mux and trim by \
            duration: `VideoMuxer` cuts the video down to the audio's length and \
            `VisualRecorder` then deletes the original, so a route switch shortly before Stop \
            destroys the take. Truncation is only correct where the caller has no length \
            expectation — here it has two (#630b).
            """)
        XCTAssertEqual(body.filter {
            $0.contains("let frames = min(max(Int(seconds * captureSampleRate), 0), ringCapacity)")
        }.count, 1, """
            `captureRecent` no longer sizes its file from the REQUEST. A constant-duration \
            file is the contract both consumers were written against — and note the defect \
            fires without any rate switch at all: with the boundary at 0 a truncating window \
            is still short for the first ~30 s after every engine start (#630b).
            """)
        XCTAssertEqual(body.filter {
            $0.contains("guard startFrame + written + f >= boundary else {")
        }.count, 1, """
            `captureRecent` copies pre-boundary frames again. It keeps its length (above), so \
            without this skip the old-rate frames go into the file under the new rate — #630's \
            original defect, restored in the one reader that must not shorten (#630b).
            """)
    }
}
#endif
