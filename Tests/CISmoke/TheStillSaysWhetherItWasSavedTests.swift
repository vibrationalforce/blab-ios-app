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
        // ⛔ THIS ASSERTED THE OPPOSITE UNTIL #1069, AND IT WOULD HAVE BEEN RED ON A CORRECT
        // TREE. It required `EchoelStudioView` to mount `StillShutterButton`, because the
        // fullscreen COVER's top row was where the shutter lived. S3c deleted that cover, and
        // claim 6 below already pinned the surviving mount in `FloatingVisualWindow` — so the
        // door was never at risk, only this needle's anchor. Third time this bundle has recorded
        // the shape (#650, #960); §4's one-command prevention is grepping `Tests/CISmoke` for the
        // removed spelling in the SAME commit, which is how this was caught.
        XCTAssertFalse(studio.contains("StillShutterButton("), """
            `EchoelStudioView` mounts `StillShutterButton` again. Since #1069 the ONE visual \
            window owns the shutter (claim 6 pins that mount); a second one here would be a \
            second door to one action — #290 — and it would put the outcome sentence back into \
            the body that hosts the genre/key `.menu` Pickers.

            If a second host is genuinely wanted, decide its `AnswerPlacement` explicitly and say \
            why here; do not let it arrive as a copied line.
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

    // 6 — #1063: the shutter reaches the surface D1 is merging everything into, and its answer
    // does not eat the bar's width. Both halves matter and only together: mounting the button in
    // a row with 0 pt of measured slack on a 375 pt phone would put the sentence back where it
    // gets compressed to nothing, which is the silence claim 1 exists to forbid.
    func testTheWindowMountsTheShutterWithAnAnswerThatCostsNoBarWidth() throws {
        let window = try source("Sources/Echoelmusic/Studio/FloatingVisualWindow.swift")
        XCTAssertTrue(window.contains("StillShutterButton(recorder: recorder, answer: .below)"), """
            The floating window does not mount the shutter with the overlay answer. Once the \
            fullscreen cover is deleted (S3 of PLAN_ONE_VISUAL_SURFACE_2026-09-07) this is the \
            ONLY door to the still — and `.beside` here would place a sentence in a row that \
            `ChromeBudgetFitsTests` measures at 0 pt of slack on a 375 pt phone.
            """)
        XCTAssertTrue(window.contains("fit.stillShutter"), """
            The mount does not consult the chrome budget. An unbudgeted item draws past the \
            card and off the screen — the founder's original "geht über den Rand hinaus".
            """)
        for needle in ["lastStillOutcome", "stillOutcomeToken", "requestStill("] {
            XCTAssertFalse(window.contains(needle), """
                `FloatingVisualWindow` touches `\(needle)` itself. The tap and the outcome read \
                belong to the leaf — one owner, so a second call site cannot show no sentence \
                (claim 4 makes the same demand of `EchoelStudioView`).
                """)
        }

        // COUNTERWEIGHT (#367): the leaf really has TWO placements and the overlay really is the
        // one that claims no layout width. Without this, the needle above would pass over a
        // parameter nothing reads.
        //
        // ⚠️ `.beside` HAS NO CALLER SINCE #1069 — say it rather than let this counterweight read
        // as proof that both are in use. The cover's row was its one call site. It is KEPT, and
        // the reason is specific rather than sentimental: the two placements are what let ONE
        // leaf serve a row with width to spare AND a bar with none, and the second kind of host
        // is exactly what S4 (wrap the fullscreen bar instead of shedding) may produce. Deleting
        // a case to make a count tidy, then rewriting it a week later, is churn — but a
        // producerless case is a finding, so it is named here and in the leaf, not left silent.
        let leaf = try source("Sources/Echoelmusic/Studio/StillShutterButton.swift")
        for needle in ["case beside", "case below", "answer == .beside", "answer == .below",
                       ".overlay(alignment: .bottomTrailing)"] {
            XCTAssertTrue(leaf.contains(needle), """
                `StillShutterButton` no longer spells "\(needle)". The two placements are the \
                reason one leaf can serve a row with no width budget AND a bar with none to \
                spare; collapsing them silently picks one of the two defects.
                """)
        }
        XCTAssertTrue(leaf.contains("let answer: AnswerPlacement"), """
            The placement gained a default. #431: a defaulted argument no call site writes never \
            shows up in a diff — and here the wrong value is a sentence nobody can read.
            """)
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
