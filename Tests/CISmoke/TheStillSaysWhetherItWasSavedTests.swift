import XCTest
@testable import Echoelmusic

/// #986 — the still button ANSWERS.
///
/// WHY IT EXISTS. #985 shipped the picture and shipped a silence with it. Success, a denied
/// photo-library permission and an encode failure were indistinguishable from a dead button: the
/// only trace of any of them was an `os_log` line, which the founder cannot see on the device he
/// is holding. Two items of the CLEAR-SOFTWARE checklist were therefore open on a feature that
/// had just been called finished — "permission denials handled gracefully" and "buttons respond,
/// states change". A denial is the likely first run of this feature, because it is the run where
/// iOS asks.
///
/// ⚠️ WHAT THIS FILE CAN AND CANNOT SEE. It opens no photo library and renders no SwiftUI, so
/// whether the sentence is LEGIBLE on the device is the NEEDS-FOUNDER-VERIFY at the foot of this
/// file — ONE ask, phrased with a determiner here on purpose so the collector counts the job once
/// and not twice (#753/#984: prose ABOUT an ask must not become a second ask). What this file
/// pins is that every terminal path reports, that the words differ and name a remedy, and that
/// the read stayed out of the menu-hosting body.
final class TheStillSaysWhetherItWasSavedTests: XCTestCase {

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

    // 1 — BEHAVIOURAL, not a text scan: the three outcomes say three different things, and the
    // one the user can act on names the action. "Failed" for a denial sends someone back to tap
    // the same button that will keep refusing.
    func testEachOutcomeSaysSomethingDifferentAndTheDenialNamesTheRemedy() {
        let saved = StillFeedback.sentence(for: .saved)
        let denied = StillFeedback.sentence(for: .denied)
        let failed = StillFeedback.sentence(for: .failed)

        XCTAssertEqual(Set([saved, denied, failed]).count, 3, """
            Two outcomes share a sentence. The point of this slice is that the user can tell a \
            denial from a failure — collapsing them re-creates the silence #985 shipped, one \
            step less silently.
            """)
        for sentence in [saved, denied, failed] {
            XCTAssertFalse(sentence.isEmpty, "An outcome has no words at all.")
        }
        XCTAssertTrue(denied.contains("Settings"), """
            The denial sentence does not name where the permission lives. A denial is the only \
            outcome the user can DO anything about, and iOS never asks twice.
            """)
    }

    // 2 — every terminal path in the save reports. A `return` without a callback is the same dead
    // button, just further in.
    func testEveryPathOutOfTheSaveReportsAnOutcome() throws {
        let recorder = try source("Sources/Echoelmusic/Video/VisualRecorder.swift")
        for needle in ["completion(.failed)", "completion(.denied)",
                       "completion(success ? .saved : .failed)"] {
            XCTAssertTrue(recorder.contains(needle), """
                `saveStillToPhotoLibrary` has no `\(needle)`. Every exit has to say what happened, \
                including the encode failure and the denial — those are the two the user is most \
                likely to hit first.
                """)
        }
        // The platform-less branch is the easy one to forget: with Photos compiled out the body
        // was previously EMPTY, which is a callback that can never come.
        XCTAssertTrue(recorder.contains("#else"), """
            The save has no `#else` for a platform without Photos/CoreImage. A caller waiting for \
            a callback that cannot arrive looks exactly like the dead button this slice removes.
            """)
    }

    // 3 — the leaf watches the TOKEN, never the value. Two stills with the SAME outcome are two
    // events; watching the enum shows only the first.
    func testTheLeafWatchesTheTokenAndNotTheValue() throws {
        let leaf = try source("Sources/Echoelmusic/Studio/StillShutterButton.swift")
        XCTAssertTrue(leaf.contains("onChange(of: recorder.stillOutcomeToken)"), """
            The leaf does not watch `stillOutcomeToken`. That counter exists precisely because \
            `lastStillOutcome` does not change when the same outcome happens twice.
            """)
        XCTAssertFalse(leaf.contains("onChange(of: recorder.lastStillOutcome)"), """
            The leaf watches the outcome VALUE. Deny twice in a row and the second denial shows \
            nothing — the exact silence this slice exists to remove.
            """)
    }

    // 4 — one owner of the tap, and the outcome read never enters the menu-hosting body.
    func testTheMenuHostNeitherTapsNorReadsTheOutcome() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertTrue(studio.contains("StillShutterButton(recorder:"), """
            The fullscreen row no longer mounts `StillShutterButton`. The still then has no door \
            at all — a doorless capability, which this repo's register calls the expensive kind.
            """)
        XCTAssertFalse(studio.contains("requestStill("), """
            `EchoelStudioView` taps the shutter itself again. Two owners of one action is how the \
            tap and its answer drift apart: a second call site shows no sentence.
            """)
        for needle in ["lastStillOutcome", "stillOutcomeToken"] {
            XCTAssertFalse(studio.contains(needle), """
                `EchoelStudioView` reads `\(needle)`. That body hosts the genre/key `.menu` \
                Pickers; every observed property read there registers the WHOLE body as an \
                observer (10.76.41/50). This value is cold today — the rule is about where the \
                read LIVES, not how fast it happens to move this week.
                """)
        }
    }

    // 5 — one actor hop per STILL, never per frame. The 30 fps ban is the reason `capture` had no
    // hop at all before this slice; a hop that crept out of the `if wantsStill` block would fire
    // on every recorded frame.
    func testTheHopHappensOncePerStillAndNotPerFrame() throws {
        let recorder = try source("Sources/Echoelmusic/Video/VisualRecorder.swift")
        let hops = recorder.components(separatedBy: "Task { @MainActor").count - 1
        XCTAssertEqual(hops, 1, """
            `VisualRecorder` has \(hops) main-actor hops, expected exactly 1. The one hop belongs \
            to a human tap; a second one inside the capture path would submit a tiny main-actor \
            task per FRAME, which is the CameraRPPG starvation bug (10.76.48).
            """)
        guard let hopRange = recorder.range(of: "Task { @MainActor"),
              let armRange = recorder.range(of: "if wantsStill {\n                VisualRecorder.saveStillToPhotoLibrary") else {
            XCTFail("""
                Could not locate the still's arming block or the hop. If `capture` was \
                restructured, re-anchor this claim rather than deleting it — its subject is that \
                the hop is gated on a tap.
                """)
            return
        }
        XCTAssertTrue(armRange.lowerBound < hopRange.lowerBound, """
            The main-actor hop no longer sits inside the `if wantsStill` block. Outside it, the \
            hop runs for every captured frame of a video take.
            """)
    }

    // NEEDS-FOUNDER-VERIFY: full screen → camera button. Say whether the answer next to the
    // button is readable over the moving picture, and whether it is gone again before it turns
    // into noise. If the photo permission was never granted, the first tap should read "Photos
    // access is off — allow it in Settings" and not the
    // silence that shipped in the
    // build before this one.
}
