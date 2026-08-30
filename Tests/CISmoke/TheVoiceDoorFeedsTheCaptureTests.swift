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
// ⚠️ HONEST LIMITS. 5 tests, 16 `XCTAssert*` statements (hand-counted per test,
// 3+3+3+2+5 — re-counted after the first hand-count said 12; the two `XCTUnwrap`s also
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
// ⚠️ THE STAKES OF THAT ONE PROBE CHANGED ON 2026-08-24, AND NOTHING ELSE RECORDS IT.
// The ask itself is unchanged — do not file a second marker for it (#790: one question,
// one place). What changed is what rides on the answer. Until #795 the capability was
// sold only in `release_notes.txt`, which is version-scoped and scrolls away. #795 put it
// in `description.txt` in both locales and #797 put it on `docs/faq.html`,
// `docs/architecture.html` and `docs/dev/FEATURE_MATRIX.md`. Both moves were correct —
// the feature ships, is doored and is guard-pinned, and leaving it unsold was the
// under-claim those cycles existed to end — but a permanent App Store line is what a
// 2.3 review reads, and it is now backed by a probe nobody has run. That makes this the
// highest-stakes entry in the `scripts/founder-verify.py` backlog, not merely one of ~50.
//
// ⭐ #891 ADDED A FIFTH CLAIM, and it guards a JOIN the other four do not: what the
// controller does when `startRecording()` REFUSES. Three of that function's four silent
// early exits leave no tap, so no sample can ever arrive and the take would sit on
// `.capturing` 0 % until the user cancels — a hang, on the exact path the founder's #890
// device probe walks. The claim pins the abort AND its two counterweights (#343): the
// `hasPermission` discriminator, whose removal would abort the legitimate permission wait
// instead, and the deliberate absence of `releaseMic()` on that path, which would write a
// three-rung stop ladder for a mic that never started (#882).
//
// ⭐ GRADING OF THAT FIFTH CLAIM (§3), separately because it does NOT match the eight
// needles below. FOUR of its five assertions are red on the parent by absence, honestly
// FORWARD. The fifth — `XCTAssertFalse(releaseMic())` — is GREEN on the parent, and
// vacuously so: the window exists there and simply holds no such call. It is kept because
// it can still fail for a reason that exists (#367) — a later reader "tidying" the abort
// into the shared teardown is exactly the plausible edit — but it is a REGRESSION guard,
// not evidence for this slice, and calling it forward-red would be the over-claim.
//
// ⚠️ AND FOR THIS CLAIM THE STRIPPER IS LOAD-BEARING, not prophylactic — measured, 1 of 5
// needle verdicts FLIPS. The abort carries a ⛔ comment that NAMES `releaseMic()` to explain
// why it is absent. On the RAW text that comment sits inside the window, so the negative
// assertion would be red on a correct tree; stripped, it is green. That is the #404/#453
// defect in miniature, caught only because §3 asks for the raw-vs-stripped measurement
// instead of assuming it.
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

    /// #891 — a refused mic aborts the take instead of leaving it armed at 0 % forever,
    /// and the caption says so. Five assertions: the re-read, the discriminator, the
    /// state reset, the ladder counterweight, and the row join.
    func testARefusedMicAbortsTheTakeInsteadOfHanging() throws {
        let controller = try source("Sources/Echoelmusic/Studio/VoiceCaptureController.swift")
        let start = try XCTUnwrap(controller.range(of: "mic.startRecording()"),
                                  "the controller stopped starting the mic — re-anchor (#454)")
        let end = try XCTUnwrap(controller.range(of: "func cancel()", range: start.upperBound..<controller.endIndex),
                                "cancel() moved above begin() — re-anchor this window (#454)")
        let afterStart = String(controller[start.upperBound..<end.lowerBound])

        XCTAssertTrue(afterStart.contains("if !mic.isRecording, mic.hasPermission {"),
                      "begin() must RE-READ isRecording after startRecording(): three of "
                      + "that function's four silent exits install no tap, so the take "
                      + "would sit on .capturing 0 % with only Cancel to escape (#891)")
        XCTAssertTrue(afterStart.contains("mic.hasPermission"),
                      "the hasPermission discriminator is a COUNTERWEIGHT, not decoration: "
                      + "the no-permission exit also leaves isRecording false, but that wait "
                      + "RESOLVES once the system prompt is answered. Without this half the "
                      + "abort would fire on the first capture every new user ever tries")
        XCTAssertTrue(afterStart.contains("micUnavailable = true"),
                      "the abort must record WHY nothing happened — the row's caption is the "
                      + "only thing standing between the user and a button that looks dead")
        XCTAssertFalse(afterStart.contains("releaseMic()"),
                       "the abort must NOT go through releaseMic(): it calls stopRecording(), "
                       + "which walks a three-rung stop ladder and releases the record route "
                       + "a second time — rungs for a teardown of a mic that never started "
                       + "are exactly the lie the ladder law forbids (#882)")

        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertTrue(studio.contains("if controller.micUnavailable {"),
                      "the flag needs its reader: without the caption branch the abort is "
                      + "silent and a refused capture still looks like a dead button (#891)")
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
