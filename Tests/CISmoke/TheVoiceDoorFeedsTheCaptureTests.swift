// TheVoiceDoorFeedsTheCaptureTests.swift
// Echoel — the capture door exists, feeds the engine, and adds no modal cost. #592b.
//
// WHAT THIS GUARDS. The wiring half of the EchoelVoice capture: `MicrophoneManager`
// hands its existing main-thread sample blocks to `captureSampleSink` (riding the
// per-buffer hop that already exists — zero new thread crossings), the "Voice timbre"
// row is mounted inside `soundPanel` (a panel child, NOT a presentation modifier), and
// the controller that joins them is owned by `EchoelStudioView` so a capture survives
// the panel closing mid-take. Every claim here is a JOIN between two files — the class
// of defect where renaming one side leaves a door pointing at nothing (#351).
//
// ⚠️ HONEST LIMITS. 4 tests, 11 `XCTAssert*` statements (hand-counted per test,
// 3+3+3+2 — re-counted after the first hand-count said 12; the two `XCTUnwrap`s also
// fail their tests and are deliberately outside this count, which counts assertions,
// not failure points). ALL
// are SOURCE-TEXT JOINS: the controller's begin/cancel/apply flow drives a real
// `MicrophoneManager` + mic permission machinery that a test host cannot exercise
// honestly (its `startRecording` requests permission), and the engine underneath is
// already END-TO-END covered by `TheCaptureTurnsAToneIntoAProfileTests`. What no test
// here can prove: that the row RENDERS, that the mic actually flows on device, and how
// the captured timbre SOUNDS — the device probe, founder (NEEDS-FOUNDER-VERIFY: hold a
// tone via Sound panel → Capture, then play). Presentation-modifier budget is pinned by
// `ResetSoundClearsWhatTheLaunchLineReportsTests`, not re-counted here (#416).
//
// ⭐ GRADING (§3). Every needle names code this same commit writes — the file compiles
// against the parent (it names no new Swift symbol, only string needles) but every
// join assertion is red there by ANCHOR ABSENCE: one absence per file-pair, reported
// once (#486), honestly FORWARD. Stripper: all EIGHT needles of this file measured raw
// vs stripped on both trees (sink decl, sink call ×2 forms, mount, @State, struct,
// apply, load-absence) — every worktree count identical raw and stripped, so 0 of 8
// verdicts flip → PROPHYLAKTISCH (the doc mentions of `captureSampleSink` in prose ARE
// stripped, which is exactly why the needles carry the call/argument syntax).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheVoiceDoorFeedsTheCaptureTests: XCTestCase {

    /// The mic half: the sink exists and is called INSIDE `processExtractedAudio` —
    /// the existing main-thread landing point — before any early return.
    func testTheMicHandsItsSamplesToTheSink() throws {
        let mic = try source("Sources/Echoelmusic/MicrophoneManager.swift")
        XCTAssertTrue(mic.contains("var captureSampleSink: (([Float], Double) -> Void)?"),
                      "the sink declaration left MicrophoneManager")
        let fn = try XCTUnwrap(
            mic.range(of: "private func processExtractedAudio(_ samples: [Float], "
                        + "frameLength: Int, sampleRate: Double) {"),
            "the main-thread landing point was renamed — re-anchor (#454)")
        // The FIRST non-blank stripped line after the declaration — not merely "within
        // the first 200 chars", which a guard-return inserted above the call would pass
        // (review #592b, #367): the named law is "before any early return", so test it.
        let firstLine = mic[fn.upperBound...]
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        XCTAssertEqual(firstLine, "captureSampleSink?(samples, sampleRate)",
                       "the sink call must be the FIRST statement of "
                       + "processExtractedAudio — any early return above it (a level "
                       + "gate, a guard) would starve the capture quietly")
        XCTAssertEqual(codeOccurrences(of: "captureSampleSink?(", in: mic), 1,
                       "one call site — a second would double-feed the engine")
    }

    /// The door half: the row is mounted in the studio, exactly once, and the
    /// controller is owned by the VIEW (not the row), so a capture survives the
    /// panel closing mid-take.
    func testTheRowIsMountedAndTheControllerIsViewOwned() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertEqual(codeOccurrences(of: "VoiceCaptureRow(controller:", in: studio), 1,
                       "the door must be mounted exactly once (in soundPanel)")
        XCTAssertTrue(studio.contains("@State private var voiceCapture = VoiceCaptureController()"),
                      "the controller must be owned by EchoelStudioView — owned by the "
                      + "row, a mid-take panel close would abandon the capture")
        XCTAssertTrue(studio.contains("private struct VoiceCaptureRow: View"),
                      "the leaf row struct left the studio file")
    }

    /// The freeze law at this row: the ~12 Hz observable reads (`controller.progress`,
    /// `controller.hearingYou`) occur ONLY inside the leaf struct's body, never in the
    /// panel that mounts it (10.76.41/50 — an ancestor read would rebuild the whole
    /// root at capture rate and tear down open menus).
    func testTheProgressReadsStayInTheLeaf() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        let leafStart = try XCTUnwrap(studio.range(of: "private struct VoiceCaptureRow: View"))
        let beforeLeaf = studio[..<leafStart.lowerBound]
        XCTAssertFalse(beforeLeaf.contains("voiceCapture.progress")
                       || beforeLeaf.contains("voiceCapture.hearingYou"),
                       "a capture-rate observable read leaked ABOVE the leaf — the "
                       + "menu-freeze class (10.76.50) returned")
        // The panel hands over the REFERENCE only.
        //
        // ⛔ #631: the needle was `VoiceCaptureRow(controller: voiceCapture)` — with a
        // CLOSING PAREN — and #593c added a second argument (`, patch: $currentPatch`), so
        // this assertion had been UNCONDITIONALLY RED ever since, with no failure message at
        // all to say why. The same file gets it right one test up, at the `codeOccurrences`
        // call, by matching the PREFIX. A guard pinned to a full argument list breaks on the
        // next argument, which is exactly what happened; the property being defended is that
        // the panel passes the OBJECT and not a read value, and the prefix carries that.
        XCTAssertTrue(beforeLeaf.contains("VoiceCaptureRow(controller: voiceCapture"),
                      "the panel must hand over the reference, not a read value — a "
                      + "capture-rate read at the mount site is the menu-freeze class "
                      + "(10.76.50). Mount: `EchoelStudioView`'s soundPanel.")
        XCTAssertFalse(studio[leafStart.upperBound...].contains("voiceCapture.progress"),
                       "nothing after the leaf declaration may read the state either — "
                       + "the leaf reads its own `controller`, not the view's property")
    }

    /// The completion join: the controller applies through the #591a drain-surviving
    /// pathway, never through `loadTimbreProfile` directly (which the next patch
    /// recall would silently wipe — trap 1).
    func testTheControllerAppliesThroughTheSurvivingPathway() throws {
        let controller = try source("Sources/Echoelmusic/Studio/VoiceCaptureController.swift")
        XCTAssertTrue(controller.contains("applyVoiceProfile(profile)"),
                      "completion must go through PolySynthVoice.applyVoiceProfile — "
                      + "the staged, reasserted pathway")
        XCTAssertFalse(controller.contains("loadTimbreProfile("),
                       "a direct loadTimbreProfile call would be wiped by the next "
                       + "patch recall (trap 1) — the defect #591a exists to prevent")
    }

    // MARK: - helpers (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct DoorAnchorMissing: Error { let reason: String }

    private func codeOccurrences(of needle: String, in stripped: String) -> Int {
        stripped.components(separatedBy: needle).count - 1
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DoorAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
