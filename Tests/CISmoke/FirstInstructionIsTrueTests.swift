// FirstInstructionIsTrueTests.swift
// Echoel — the first thing the instrument tells a new user has to work when they do it.
//
// WHAT THIS GUARDS (#351). `InstrumentHintOverlay` is the whisper on the fullscreen
// visual (once-ever when #351 landed; since #604 it re-arms until learned/capped —
// the copy law here is unchanged by that), and its first line read:
//
//     "A finger on the camera brings it to life"
//
// It cannot. The camera has exactly ONE owner in reachable code — `startBioSource()` in
// `EchoelStudioView`, called from the start path — so before the user starts the music
// there is no capture session and a finger on the lens does nothing whatsoever. A new user
// who follows the app's very first instruction and sees no result concludes the app is
// broken, not that they missed a step. That is the most expensive kind of false claim in
// the product: it lands before any trust has been built.
//
// ⭐ THE TWO HALVES ARE ONE FACT, which is why one file pins both. The copy is only
// honest BECAUSE the camera is user-armed; if a later slice auto-starts capture at launch,
// the shorter promise becomes true again and this test should be changed, not worked
// around. So it asserts (a) the copy names the precondition and (b) the precondition still
// exists. Fail (b) alone and the right move is to relax (a).
//
// ⛔ WHY NOT "MAKE THE PROMISE TRUE" INSTEAD. The founder's law #1 quoted in the source
// ("app open, finger on camera, in 3 seconds it lives") is the INTENT, and honouring it
// literally means starting capture at first render — a camera-permission dialog before the
// user has touched anything, against the shipped design that bio is silent until armed.
// The copy follows the code here; flipping that is a founder call, not a wording fix.
//
// ⚠️ Source-text scan, no simulator (`Tests/CISmoke` is the blocking bundle). A green means
// the sentence still names the step and the step still exists — not that a user understood
// it. If the checkout is not at this file's compile-time path it SKIPS rather than passes.

import Foundation
import XCTest

final class FirstInstructionIsTrueTests: XCTestCase {

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }

    private func codeLines(_ path: String) throws -> [String] {
        let text = try String(contentsOf: try repoRoot().appendingPathComponent(path),
                              encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    private static let window = "Sources/Echoelmusic/Studio/FloatingVisualWindow.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    // MARK: - (a) the copy names the step

    func testTheHintNamesTheStepBeforeTheCameraDoesAnything() throws {
        let lines = try codeLines(Self.window)
        let joined = lines.joined(separator: " ")
        XCTAssertTrue(joined.contains("Start the music, then a finger on the back camera"), """
            The first-run hint no longer names the precondition. The camera does nothing \
            until the music is started (see the second test), so a bare "a finger on the \
            camera brings it to life" is an instruction that fails when followed — on the \
            first screen, before the user has any reason to trust the app.
            """)
        XCTAssertFalse(joined.contains("A finger on the camera brings it to life"), """
            The old unconditional promise is back in the hint.
            """)
        // VoiceOver reads the combined label, not the two `Label`s, so it is a SECOND copy of
        // the same sentence and drifts independently. It was already the more detailed of the
        // two ("Put a finger…") and carried the same falsehood.
        XCTAssertTrue(joined.contains("Start the music, then put a finger on the back camera"), """
            The hint's `accessibilityLabel` no longer names the precondition. It is a separate \
            string from the visible `Label`s — a VoiceOver user gets ONLY this one, so fixing \
            the visible copy alone would leave exactly the users who can least afford a false \
            instruction with the false one.
            """)
    }

    // MARK: - (b) the precondition still exists

    func testTheCameraStillHasExactlyOneOwnerOnTheStartPath() throws {
        let studio = try codeLines(Self.studio)
        let starts = studio.indices.filter { studio[$0].contains("cameraRPPG.start(publishing:") }
        XCTAssertEqual(starts.count, 1, """
            `EchoelStudioView` starts the rPPG camera at \(starts.count) places, not one. \
            A second owner is how the BLE strap got killed mid-performance by an unrelated \
            patchbay edit (BLE-3, 2026-07-15) — one lifecycle owner per sensor is a law here, \
            not a preference.
            """)
        guard let start = starts.first else { return }
        // Walk back to the nearest `private func` — the owner must be `startBioSource`.
        let owner = studio[..<start].lastIndex { $0.contains("private func ") }
            .map { studio[$0] } ?? "<none>"
        XCTAssertTrue(owner.contains("startBioSource"), """
            The camera start moved out of `startBioSource()` and now sits in \
            "\(owner.trimmingCharacters(in: .whitespaces))". The first-run hint's wording \
            ("Start the music, then a finger on the back camera") is only honest while the \
            camera is armed by the start path. If capture now begins earlier — at launch, on \
            appear — that is a real product improvement and the hint should go back to the \
            shorter promise. Change both in the same commit; do not silence this test.
            """)
    }
}
