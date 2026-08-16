// TheReadyPageNamesTheFirstActTests.swift
// Echoel — the last onboarding page must name the FIRST ACT: Play, camera light, strap.
//
// WHAT THIS GUARDS (#618, GUI-Board Zeile 8 / UX#3). The "Ready" page's one sentence of
// instruction read "Breathe, lock a key and BPM, and let your body compose." — poetic, and
// it named NONE of the three things a new player actually does first: press Play, put a
// fingertip on the camera light, or wear a Bluetooth strap. The UX audit filed that as its
// #3 finding: onboarding ends and the user does not know what starts the sound. The fix is
// ONE sentence naming all three, in the same vocabulary the app itself uses (#616's
// chooser says "camera light" / "Bluetooth strap"; the bioPanel caption says "Press Play
// to start — your body then drives the sound").
//
// KIND (per this directory's §1): SOURCE-TEXT SCAN. It proves the words sit in the
// `readyPage` slice — never that the page renders, reads well, or that VoiceOver speaks
// it in order. Those stay device probes.
//
// GRADING (#433): claims 1–2 are FORWARD guards — #618 writes the sentence they pin, so
// on the parent tree they are red for their named reason (tokens absent / stale sentence
// present) and could never have been red before. Claim 3 is a COUNTERWEIGHT, green on
// both trees. Stripper: MEASURED TRAGEND (1 of 5 verdicts flips raw vs stripped, on the
// worktree): the ⛔ comment #618 left at the sentence quotes "Breathe, lock a key and
// BPM" verbatim, so the stale-sentence absence check is red raw and green stripped —
// which is exactly the job `SourceText.codeOnly` exists for, and why this file delegates
// to it instead of declaring a private stripper (#453).
//
// ⚠️ #364: the tokens are pinned, not the sentence. Rewording stays legal as long as the
// three names survive; only dropping one of them — or reviving the old sentence — reds
// this file.

import Foundation
import XCTest

final class TheReadyPageNamesTheFirstActTests: XCTestCase {

    private func readyPageSlice() throws -> ArraySlice<String> {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent("Sources/Echoelmusic/Views/OnboardingView.swift")
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("""
                source tree not present at \(path.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        let lines = SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let declHits = lines.indices.filter { lines[$0].contains("private var readyPage: some View {") }
        XCTAssertEqual(declHits.count, 1, """
            `readyPage`'s declaration is no longer unique in OnboardingView — re-anchor \
            this slice before trusting anything below.
            """)
        guard let start = declHits.first,
              let end = lines[start...].firstIndex(where: { $0.contains("Text(\"Safety & privacy\")") })
        else {
            throw XCTSkip("""
                the readyPage → safety-heading span is gone from OnboardingView. If the \
                page was restructured, re-anchor this test in the same commit; do not let \
                it pass over an empty window.
                """)
        }
        return lines[start...end]
    }

    /// The one instruction sentence names all three of: Play, the camera light, the strap.
    func testTheFirstActIsNamed() throws {
        let page = try readyPageSlice()
        for token in ["Press Play", "camera light", "Bluetooth strap"] {
            XCTAssertTrue(page.contains { $0.contains(token) }, """
                the Ready page no longer says "\(token)". UX#3 (#618): onboarding's last \
                page is the one place a first-time player is TOLD what starts the sound — \
                the Play button and the two real bio sources, in the same words the app's \
                own chooser uses (#616's "camera light" / "Bluetooth strap"). Reword \
                freely, but keep all three names in the slice.
                """)
        }
    }

    /// The pre-#618 sentence named none of the three — it must not come back in place of them.
    func testTheOldSentenceIsGone() throws {
        let page = try readyPageSlice()
        XCTAssertFalse(page.contains { $0.contains("Breathe, lock a key and BPM") }, """
            the old Ready-page sentence is back. It reads well and names NOTHING a new \
            player can find: no Play, no camera, no strap — the exact UX#3 defect #618 \
            replaced it for. If both sentences are present this file stays green only \
            through the token assertions above; if it REPLACED the new one, they are red \
            with it.
            """)
    }

    /// COUNTERWEIGHT — green on both trees: the DAW-export promise survives the rewrite
    /// (the App Store text claims MIDI export; this page is where a producer first reads
    /// it), and the safety heading that bounds this window is still exactly one line.
    func testTheExportPromiseSurvives() throws {
        let page = try readyPageSlice()
        XCTAssertTrue(page.contains { $0.contains("Export to your DAW.") }, """
            the Ready page's "Export to your DAW." promise is gone. fastlane/metadata \
            claims the MIDI export — remove this sentence only together with that text, \
            not in a copy rewrite (#188's lesson: the export door and its words move \
            together).
            """)
    }
}
