// TheStripAsksOneFreshnessQuestionTests.swift
// Echoel — #507. One row on screen, three different answers to "is a body still arriving?"
//
// WHAT WENT WRONG. `BioStripView` is the reachable bio readout (pulse-pill tap → `bioPanel`;
// ⛔ this SAID "Bio chip →" and no chip OPENS the panel, #705/#706), and it
// was the only file in `Studio/` that used all three of the bus freshness accessors at once:
//
//   · the "live" tag and the activity light asked `bus.usableBio()`  — the source's OWN window
//   · the "Coh" cell asked `bus.freshBio()`                          — a FIXED 5 s, any source
//   · "HR", "HRV" and "Br" read `bus.latestBio`                      — the raw snapshot
//
// `EngineBus.latestBio` is NEVER cleared. Its only writer is the publish sink; neither `stop()`
// nor a lost pulse empties it — that is the very fact #503 was built on. So stopping the camera
// made the tag fall to "No signal" after 6 s and the coherence cell fall to "—" after 5 s, while
// the heart rate, HRV and breath numbers kept standing for the rest of the process, right beside
// a label saying nothing was arriving. That is #503's defect on the surface that actually HAS a
// door; #503 fixed the doorless always-on list inside the FX sheet.
//
// ⭐ IT IS NOT A NEW POLICY — it is this file's OWN, finally applied to the three cells that never
// followed it. `hasLiveSignal`'s doc has said since it was written: *a frozen reading expires
// after the freshness window, so the strip stops claiming a live body*. The tag obeyed that
// sentence; the numbers beside it did not.
//
// ⚠️ EXPIRY BLANKS HERE, it does not mark — the OPPOSITE of #503, deliberately, and the two are
// not in tension. `AlwaysOnBioView` reports WHAT THE ENGINE IS GETTING, and the sound producers
// park on the last body rather than dropping it, so clearing a number there would claim an abort
// that did not happen. This strip reports WHAT YOUR BODY IS DOING, and its own tag already says
// "No signal"; a held number here would be the contradiction, not the honesty.
//
// ⚠️ WHICH HALF IS REAL BEHAVIOUR AND WHICH IS A SCAN — the limit first, because this file looks
// broader than it is. `BioStripView`'s members are `private var`s on a SwiftUI `View` this bundle
// cannot instantiate, so claims 1–4 and 6 are SOURCE SCANS: they prove where text is, never that
// a cell renders. Only claim 5 drives shipped code end to end (`BioSource` and `freshnessWindow`
// are `public` and Foundation-only). That the row reads right on a device when the source drops
// is a device check, and it is OPEN.
//
// ⚠️ `SourceText.codeOnly` IS LOAD-BEARING HERE, and that is MEASURED, not assumed (#484, #485
// and #486 each had to retract the stronger claim). The retraction comment this slice writes into
// `statusBanner` quotes `bus.freshBio() == nil` verbatim to explain why that clock was wrong.
// Raw text on the fixed tree: `bus.freshBio(` appears 1×. Stripped: 0×. So the negative needle in
// claim 2 would be RED ON CORRECT CODE without the stripper — the #486/#491 collision again, this
// repo writes down what it removed.
//
// ⚠️ HONEST GRADING (#433), measured against the parent tree with a transcription of
// `SourceText.codeOnly`, not asserted. This file DOES compile against the parent (it names no
// symbol #507 introduces), so every claim has a verdict there — unlike #493/#497/#498/#503.
//   · claim 1 — RED on the parent for its STATED reason (no `private var reading` at all).
//   · claim 3 — RED on the parent for its STATED reason (both gates read `bus.freshBio()`).
//   · claim 2 — RED on the parent by ANCHOR ABSENCE (#486): it throws because the anchor is
//     missing, which is ONE absence reported a second time, not a second finding. Said plainly
//     rather than counted as a third regression.
//   · claims 4, 5, 6 — green on BOTH trees. They are COUNTERWEIGHTS, and they are the point:
//     the obvious later cleanup is "route the camera cell through `reading` too" (claim 4, which
//     would split this cell from `HeaderMonitors`), or "the windows all look the same, drop the
//     per-source lookup" (claim 5), or a future HealthKit coherence that silently makes the "+1 s
//     only" measurement in the source comment wrong (claim 6).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheStripAsksOneFreshnessQuestionTests: XCTestCase {

    private static let strip = "Sources/Echoelmusic/Studio/BioStripView.swift"

    // MARK: - 1. One question, and it is the per-source one

    func testTheStripDeclaresOneFreshnessQuestion() throws {
        let src = try code(at: Self.strip)
        XCTAssertEqual(
            occurrences(of: "private var reading", in: src), 1,
            """
            BioStripView must declare exactly ONE freshness question for the whole row (#507). \
            Two declarations means two answers again, which is the defect this slice removed.
            """)
        XCTAssertTrue(
            src.contains("private var reading: BioSampleFrame? { bus.usableBio() }"),
            """
            The one question must be `bus.usableBio()` — the source's OWN window \
            (`BioSource.freshnessWindow`), the same one `ModulationEngine.tick` gates on. \
            A hardcoded number here would be a fourth regime, not a fix.
            """)
    }

    // MARK: - 2. No cell reads the raw snapshot or the fixed window

    func testNoCellReadsTheRawSnapshotOrTheFixedWindow() throws {
        let src = try code(at: Self.strip)

        // #367: anchor FIRST. A bare "these tokens are absent" scan is green on a tree that lost
        // the whole readout — it would pass on an empty file. Fail loudly instead of vacuously.
        guard src.contains("private var reading") else {
            throw AnchorMissing(reason: """
                BioStripView no longer declares `private var reading` — the anchor for this scan \
                is gone. Re-anchor it; do not let the absence read as a pass.
                """)
        }

        XCTAssertEqual(
            occurrences(of: "bus.latestBio", in: src), 0,
            """
            A cell is reading `bus.latestBio` again (#507). `EngineBus` NEVER clears that \
            snapshot — its only writer is the publish sink, and neither `stop()` nor a lost pulse \
            empties it (#503) — so such a cell keeps its last number for the life of the process \
            while the tag beside it already says "No signal". Read `reading`.
            """)
        XCTAssertEqual(
            occurrences(of: "bus.freshBio(", in: src), 0,
            """
            Something in the strip is back on the FIXED 5 s window (#507). That clock ignores \
            which source is publishing: a Watch/HealthKit reading stays usable for 90 s and keeps \
            driving the music, so `freshBio()` blanks it 85 s early. Read `reading`.
            """)
    }

    // MARK: - 3. Both camera-denied gates ask the same question

    func testBothCameraDeniedGatesAskTheSameQuestion() throws {
        let src = try code(at: Self.strip)
        XCTAssertEqual(
            occurrences(of: "cameraRPPG.permissionDenied, reading == nil", in: src), 2,
            """
            The two camera-denied gates (the status banner and the source control) must both \
            suppress on the SAME clock as the rest of the strip (#507). They used to ask \
            `bus.freshBio() == nil`, so between two Watch writes — minutes apart, reading still \
            usable — the app nagged someone to enable a camera they had deliberately declined \
            while their wrist was driving the music.
            """)
    }

    // MARK: - 4. Counterweight: the camera cell keeps the HEADER's clock

    func testTheCameraCellStillPrefersTheHeaderClock() throws {
        let src = try code(at: Self.strip)
        XCTAssertTrue(
            src.contains("if cameraRPPG.isRunning, cameraRPPG.displayBPM > 0 {"),
            """
            The HR cell must still prefer the camera's calm `displayBPM` while the camera runs \
            (#507). This branch is DELIBERATELY not routed through `reading`: `displayBPM` is the \
            number `HeaderMonitors` shows and `stop()` sets it back to 0, so it cannot outlive a \
            stopped camera. Expiring it on the bus window instead would put this cell and the \
            header on two different clocks for ONE number — the disagreement #507 exists to \
            remove, not a smaller version of it.
            """)
    }

    // MARK: - 5. Behaviour: the windows genuinely differ (this is what made it a defect)

    func testTheSourceWindowsGenuinelyDiffer() {
        // The only claim in this file that drives shipped code. If these ever collapsed to one
        // number, #507 would be cosmetic — the whole slice rests on the spread being large.
        XCTAssertEqual(BioSource.cameraPPG.freshnessWindow, 6, accuracy: 0.0001)
        XCTAssertEqual(BioSource.ble.freshnessWindow, 6, accuracy: 0.0001)
        XCTAssertEqual(BioSource.healthKit.freshnessWindow, 90, accuracy: 0.0001)

        // 5 s is also exactly what `freshBio()` defaults to, which is the measured reason the
        // DEMO source is unchanged by this slice while camera and strap gain 1 s.
        XCTAssertEqual(BioSource.fallback.freshnessWindow, 5, accuracy: 0.0001)

        XCTAssertGreaterThan(
            BioSource.healthKit.freshnessWindow - BioSource.cameraPPG.freshnessWindow, 60,
            """
            The gap between a wrist window and a camera window must stay large enough that \
            asking the wrong one is a real defect and not a rounding difference (#507). At the \
            shipped values it is 84 s.
            """)
    }

    // MARK: - 6. Counterweight: the "+1 s only" measurement for the coherence cell

    func testOnlySixSecondSourcesEverPublishCoherence() throws {
        // The source comment on `coherenceString` states, as a MEASUREMENT, that moving that cell
        // from the fixed 5 s to the per-source window costs camera and strap exactly +1 s and the
        // demo nothing — because the two publishers with other windows write a literal zero and
        // can therefore never show anything in that cell. Give a future real coherence from either
        // of them a red test, so the 90 s question gets asked on purpose.
        for file in ["Sources/Echoelmusic/Bio/HealthKitBioPublisher.swift",
                     "Sources/Echoelmusic/Bio/FaceExpressionBioPublisher.swift"] {
            let src = try code(at: file)
            XCTAssertTrue(
                src.contains("coherence: 0,"),
                """
                \(file) no longer publishes a literal `coherence: 0`. The "+1 s only" measurement \
                written beside `coherenceString` in BioStripView assumed exactly that — re-measure \
                what the coherence cell now costs on that source's window before leaving it.
                """)
        }
    }

    // MARK: - Helpers

    private func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var search = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, range: search) {
            count += 1
            search = found.upperBound..<haystack.endIndex
        }
        return count
    }

    /// Comment-stripped source (#453 — the ONE definition of "code, not prose"). Load-bearing
    /// here: this slice's own retraction comments name the tokens claim 2 forbids.
    private func code(at relativePath: String) throws -> String {
        let path = try treeRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// The skip is scoped to the TREE, never to a file (#454): a per-file `fileExists` guard turns
    /// exactly the catastrophe this file watches for into a green skip.
    private func treeRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        return root
    }

    private struct AnchorMissing: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }
}
