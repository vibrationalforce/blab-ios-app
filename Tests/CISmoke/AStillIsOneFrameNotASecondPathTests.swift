import XCTest
@testable import Echoelmusic

/// #985 — the visual can hand you ONE FRAME as a picture.
///
/// WHY IT EXISTS. The output stage could produce an mp4 and nothing else; the cheapest and most
/// wanted artefact — a cover, a post, the frame worth keeping — had no path at all. Measured
/// before building: `VisualRecorder` has exactly one route out (`stop()` → mp4 → share/Photos),
/// and `capture(from:in:device:)` was already blitting each frame into a BGRA `CVPixelBuffer`.
/// So a still is that same buffer, once, rather than a second way into the drawable.
///
/// ⚠️ WHAT THIS FILE CAN AND CANNOT SEE. It runs no Metal and opens no photo library, so the
/// picture itself is NEEDS-FOUNDER-VERIFY (below). What it pins is the STRUCTURE that made the
/// feature cheap and keeps it honest: one arming flag, one question asked by the draw loop, the
/// flag cleared on the main thread, and no new presentation modifier.
final class AStillIsOneFrameNotASecondPathTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let url = dir.appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) could not be read — a missing anchor is a "
                    + "finding, not a pass.")
            return ""
        }
        return text
    }

    /// 1 — the draw loop asks ONE question. Two separate reads (`isRecording` OR `stillRequested`
    /// spelled out at the call site) is how a still and a take come to disagree about whether the
    /// drawable had to be readable this frame — and a non-readable drawable is the validation
    /// failure that once forced `framebufferOnly` permanently false.
    func testTheDrawLoopAsksOneQuestionAboutFrameCapture() throws {
        let view = try source("Sources/Echoelmusic/Views/MetalBioView.swift")
        XCTAssertTrue(view.contains("visualRecorder?.wantsFrameCapture"), """
            MetalBioView no longer gates capture on `wantsFrameCapture`. That property is the \
            single question ("is a take running OR is a still armed?"); asking the two halves \
            separately at this call site is what lets them disagree.
            """)
        XCTAssertFalse(view.contains("visualRecorder?.stillRequested"), """
            MetalBioView reads `stillRequested` directly. It must not know that stills exist as a \
            separate thing — it asks `wantsFrameCapture` and nothing else.
            """)
    }

    /// 2 — the arming flag is consumed on the frame that was blitted, on the main thread.
    /// Clearing it inside the `@Sendable` GPU-completion closure would be a main-actor write from
    /// a background thread AND could arm a second frame in the gap.
    func testTheStillFlagIsClearedBeforeTheCompletionHandler() throws {
        let recorder = try source("Sources/Echoelmusic/Video/VisualRecorder.swift")
        guard let clear = recorder.range(of: "if wantsStill { stillRequested = false }"),
              let handler = recorder.range(of: "commandBuffer.addCompletedHandler") else {
            XCTFail("the still's clear-line or the completion handler is gone — if the mechanism "
                    + "changed, re-point this claim in the same commit")
            return
        }
        XCTAssertLessThan(clear.lowerBound, handler.lowerBound, """
            `stillRequested` is cleared at or after `addCompletedHandler`. It must fall on the \
            main-thread draw loop, before the GPU closure exists.
            """)
        XCTAssertTrue(recorder.contains("let wantsStill = stillRequested"), """
            The still is no longer sampled ONCE at the top of `capture`. Reading the flag twice \
            in a function that also clears it is the half-armed state this line prevents.
            """)
    }

    /// 3 — a still taken while NOT recording must not be fed to the file sink; `ingest` would
    /// open a writer for a take nobody started.
    func testAStillDoesNotStartAVideoTake() throws {
        let recorder = try source("Sources/Echoelmusic/Video/VisualRecorder.swift")
        XCTAssertTrue(recorder.contains("if recording { box.sink.ingest("), """
            `ingest` is called unconditionally again. A still armed outside a take would then \
            hand a frame to the mp4 writer and start a file the user never asked for.
            """)
    }

    /// 4 — the door costs no presentation modifier. The still saves straight to Photos like the
    /// video does; a share sheet here would grow the chain the 10.76.34 black-screen law caps.
    func testTheStillDoorAddsNoModal() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertTrue(studio.contains("visualRecorder.requestStill()"), """
            The fullscreen visual row no longer has the still button — the capability would be \
            built and doorless, which is the trap this repo keeps paying for.
            """)
        // The counts this repo pins elsewhere; asserted here as a NON-GROWTH check only, so this
        // claim does not become a second home for the numbers (#416).
        XCTAssertEqual(studio.components(separatedBy: ".sheet(").count - 1, 14, """
            The presentation-modifier count moved. The still button is supposed to cost ZERO \
            modifiers (it writes to Photos, it does not present anything) — if a modal was added \
            for it, take an existing slot instead (CLAUDE.md's presentation paragraph).
            """)
    }

    /// 5 — `saveStillToPhotoLibrary` runs on the GPU completion thread, so it may not be
    /// main-actor isolated, and it must ask for the narrowest permission the video path uses.
    func testTheStillSaveIsNonisolatedAndAddOnly() throws {
        let recorder = try source("Sources/Echoelmusic/Video/VisualRecorder.swift")
        XCTAssertTrue(recorder.contains("nonisolated static func saveStillToPhotoLibrary"), """
            `saveStillToPhotoLibrary` is no longer `nonisolated static`. It is called from the \
            GPU completion handler; a main-actor-isolated function there is a concurrency error, \
            not a style preference.
            """)
        XCTAssertTrue(recorder.contains("requestAuthorization(for: .addOnly)"), """
            The still path asks for more than `.addOnly`. The video path settled on the narrowest \
            permission that works; the still must not widen it.
            """)
    }
}

// NEEDS-FOUNDER-VERIFY: Vollbild-Visual öffnen (Visual-Panel → „Full screen"), die Kamera-Taste
// neben der Aufnahmetaste antippen — liegt danach GENAU EIN Bild in der Fotos-App, zeigt es den
// Moment, den Du gesehen hast, und läuft das Bild dabei ohne Ruckler weiter? Zweite Probe: Taste
// WÄHREND einer laufenden Videoaufnahme antippen — Bild da UND Video ungestört?
