import XCTest
@testable import Echoelmusic

/// #990 — a video take says what became of it.
///
/// WHY IT EXISTS. `VisualRecorder.stop()` returns nil on several paths and all three stop doors
/// discarded it, so an unrepeatable performance capture could end with no share sheet, no library
/// row and no sentence at all. The worst shape is the EMPTY take: the REC badge counts wall-clock
/// seconds off a `Date` while no frame ever reaches the writer, so the performer watches a running
/// timer for a recording that wrote nothing. This is the same defect the still button had before
/// #986, on the artefact that costs far more to lose.
///
/// ⚠️ WHAT THIS FILE CAN AND CANNOT SEE. It writes no mp4 and renders no SwiftUI, so whether the
/// sentence is legible over the picture is the NEEDS-FOUNDER-VERIFY at the foot of this file. What
/// it pins is that each ENDING has its own answer, that the double-tap path stays silent, and that
/// the read stayed out of the menu-hosting body.
final class TheTakeSaysWhetherItWasWrittenTests: XCTestCase {

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

    // 1 — BEHAVIOURAL: three endings, three different sentences, and the two failures are told
    // apart. An empty take is worth retrying; a writer error usually is not. Collapsing them into
    // one "failed" throws away the half the user can act on.
    func testTheThreeEndingsSayThreeDifferentThings() {
        let saved = TakeFeedback.sentence(for: .saved)
        let empty = TakeFeedback.sentence(for: .empty)
        let failed = TakeFeedback.sentence(for: .failed("writer refused"))

        XCTAssertEqual(Set([saved, empty, failed]).count, 3, """
            Two take endings share a sentence. The user cannot then tell "nothing arrived to \
            record" from "the writer refused", which are the two cases with opposite next steps.
            """)
        for sentence in [saved, empty, failed] {
            XCTAssertFalse(sentence.isEmpty, "A take ending has no words at all.")
        }
        XCTAssertEqual(TakeFeedback.sentence(for: .failed("A")),
                       TakeFeedback.sentence(for: .failed("B")), """
            The user-facing sentence varies with the writer's error text. That message is \
            technical and already goes to os_log and the diagnostics export; putting it on the \
            performance screen trades a readable sentence for a string nobody can act on.
            """)
    }

    // 2 — every ENDING of stop() publishes, and the count is asserted so a new early return
    // cannot quietly become a fourth silent exit.
    func testEveryEndingOfStopPublishesAnOutcome() throws {
        let recorder = try source("Sources/Echoelmusic/Video/VisualRecorder.swift")
        for needle in ["publishTake(.saved)", "publishTake(.empty)", "publishTake(.failed(message))"] {
            XCTAssertTrue(recorder.contains(needle), """
                `stop()` has no `\(needle)`. An ending that publishes nothing is the silence this \
                slice removes, one path further in.
                """)
        }
        let published = recorder.components(separatedBy: "publishTake(.").count - 1
        XCTAssertEqual(published, 5, """
            `stop()` publishes from \(published) sites, expected 5 — one failure, one empty, and \
            THREE saved paths (no audio, muxed, mux-failed-so-silent-video). If a path was added \
            or merged, re-derive this number and say which ending changed; if one was removed, \
            check it did not become a silent return.
            """)
    }

    // 3 — the double-tap guard stays SILENT. It is the second caller while the first is still in
    // flight; publishing there would overwrite the real answer with "nothing happened" moments
    // before the true one lands.
    func testTheReentryGuardPublishesNothing() throws {
        let recorder = try source("Sources/Echoelmusic/Video/VisualRecorder.swift")
        guard let guardRange = recorder.range(of: "guard video.recordState == .recording else { return nil }") else {
            XCTFail("The re-entry guard is gone. It exists because two stops in one run-loop turn "
                    + "once saved a take WITHOUT ITS AUDIO (#387) — do not remove it to satisfy "
                    + "this test.")
            return
        }
        // Nothing between that guard and the awaited stop may publish.
        let after = recorder[guardRange.upperBound...]
        let toStop = after.prefix(while: { _ in true })
        if let stopCall = toStop.range(of: "await video.stopRecording()") {
            let between = toStop[toStop.startIndex..<stopCall.lowerBound]
            XCTAssertFalse(between.contains("publishTake("), """
                The re-entry exit publishes an outcome. That path is the SECOND tap of a \
                double-tap; its answer would land on screen just before the real one and say the \
                opposite.
                """)
        }
    }

    // 4 — the answer read never enters the menu-hosting body, and the door is mounted.
    func testTheMenuHostMountsTheLeafAndReadsNothing() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertTrue(studio.contains("TakeOutcomeLine(recorder:"), """
            The fullscreen row no longer mounts `TakeOutcomeLine`, so a take stopped there says \
            nothing again.
            """)
        for needle in ["lastTakeOutcome", "takeOutcomeToken"] {
            XCTAssertFalse(studio.contains(needle), """
                `EchoelStudioView` reads `\(needle)`. That body hosts the genre/key `.menu` \
                Pickers; the read belongs in the leaf (10.76.41/50).
                """)
        }
    }

    // 5 — COUNTERWEIGHT, and it is the honest half of this slice: TWO stop doors still discard
    // the answer. This claim asserts the gap EXISTS so the next cycle cannot forget it, and it
    // goes red the day someone closes it — at which point delete the claim and say so (#364).
    func testTheOtherTwoStopDoorsStillSayNothingYet() throws {
        let floating = try source("Sources/Echoelmusic/Studio/FloatingVisualWindow.swift")
        let mountsInFloating = floating.contains("TakeOutcomeLine(recorder:")
        XCTAssertFalse(mountsInFloating, """
            GOOD NEWS, NOT A DEFECT: the floating window now shows the take's answer too. Delete \
            this claim in the same commit and update the ⚠️ note in EchoelStudioView's fullscreen \
            row that says these doors are still silent (#456 — prose moves with the code).
            """)
    }

    // NEEDS-FOUNDER-VERIFY: full screen → record → stop, twice. Once with the visual actually
    // running (expect "Take saved to Photos" and the file in Photos), and once stopped almost
    // immediately after starting, where no frame may have reached the writer — that is the case
    // that used to end in silence, and it should now say a sentence rather than nothing.
}
