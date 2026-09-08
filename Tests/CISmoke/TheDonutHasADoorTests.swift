// TheDonutHasADoorTests.swift
// Echoel — the spectral donut's reachability, in the BLOCKING bundle.
//
// ⛔ WHAT IT CAUGHT (#1122). `ResourceGovernor`'s own design notes said
// "`allowSpectralDonuts` → nobody; `SpectralDonutView` has no reachable door". Measured:
// `git grep -n "SpectralDonutView(" -- Sources` returns exactly ONE mount, in
// `FloatingVisualWindow` — the phone's live visual surface. The donut has been reachable
// the whole time. The note was written when #1069 deleted the SECOND door (the fullscreen
// cover's toggle) and it inverted the fact on the way.
//
// The direction is what makes it worth a guard. A premise of "there is no door" tells the
// next session the quality lever is MOOT, so nobody re-examines it; the same sentence had
// already spread into CLAUDE.md's register, which #1121 corrected in the commit before this
// one. Two files, one false fact, and neither could contradict the other.
//
// ⚠️ WHAT THIS DOES NOT ASSERT. It does not say the governor SHOULD drive the donut. The
// real reason it does not is written at both ends now and it is a render-safety decision:
// the donut is a SwiftUI `Canvas` inside a `TimelineView`, so its draw closure is ON the
// observation graph, in the window above the studio's menus — reading governor state there
// is the 10.76.41/50 menu-freeze pattern. `MetalBioView` gets away with it only because it
// reads inside `draw(in:)`, off the graph, which a `Canvas` has no equivalent of.
//
// ⚠️ Claim 2 is a COUNTERWEIGHT (#364). It goes red the day someone wires the lever, and
// its message says to update the prose rather than to revert the wiring.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheDonutHasADoorTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func sources() -> [(path: String, text: String)] {
        let base = repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: base.path) else { return [] }
        var out: [(String, String)] = []
        for case let name as String in walker where name.hasSuffix(".swift") {
            if let text = try? String(contentsOf: base.appendingPathComponent(name), encoding: .utf8) {
                out.append(("Sources/" + name, text))
            }
        }
        return out.map { (path: $0.0, text: $0.1) }
    }

    // MARK: - 1 · The door exists, and it is exactly one

    func testTheDonutIsMountedSomewhereReachable() {
        let files = sources()
        XCTAssertFalse(files.isEmpty, "no Swift sources were readable — this guard checked nothing")
        // COMMENT LINES ARE NOT MOUNTS, and this is not a nicety — measured while writing
        // this guard, a naive `text.contains` reported FIVE sites, four of them prose that
        // quotes the constructor (`LookBlendMap`, `EchoelStudioView` ×2, `VisualEnergy`,
        // `ResourceGovernor`) including the note #1122 had just added. Same trap as
        // `EchoelModalBank`: writing about a thing falsifies the grep that measures it.
        let mounts = files.filter { file in
            guard !file.path.hasSuffix("SpectralDonutView.swift") else { return false }
            return file.text.split(separator: "\n", omittingEmptySubsequences: false).contains {
                let line = $0.trimmingCharacters(in: .whitespaces)
                return !line.hasPrefix("//") && line.contains("SpectralDonutView(")
            }
        }.map(\.path)

        XCTAssertFalse(mounts.isEmpty, """
            `SpectralDonutView(` is constructed nowhere outside its own file, so the donut is \
            now doorless. That may be a deliberate retirement — but four places in this repo \
            reason from it being REACHABLE and must move in the same commit: this file, \
            `ResourceGovernor`'s note on `allowSpectralDonuts`, `SpectralDonutView`'s own \
            `bandCount` note, and CLAUDE.md's register entry (#1121 corrected that one). If \
            the look was retired, take its `LookBlendMap` handling with it.
            """)
        XCTAssertEqual(mounts.count, 1, """
            The donut is mounted at \(mounts.count) sites: \(mounts.joined(separator: ", ")). \
            There was exactly one, `FloatingVisualWindow` — the second was the fullscreen \
            cover's, deleted by #1069. A second mount is not forbidden, but it is a second \
            place that must pass `reduceMotion` and a second surface whose flash behaviour \
            nobody has looked at. Say why here, in the same commit.
            """)
    }

    // MARK: - 2 · COUNTERWEIGHT — the lever is still unwired, and for a stated reason

    func testTheQualityLeverIsStillNotReadInsideTheCanvas() throws {
        let donut = try String(
            contentsOf: repoRoot().appendingPathComponent("Sources/Echoelmusic/Studio/SpectralDonutView.swift"),
            encoding: .utf8)
        // A CODE-SHAPED NEEDLE, NOT A WORD. The first draft banned the WORDS
        // "ResourceGovernor" and "visualDetailScale" — and went red immediately, because the
        // `bandCount` note this same slice added has to NAME them to explain why they are
        // absent. A guard whose subject cannot be discussed is unusable; ban the injection
        // and the read instead, which is what actually puts the governor on the graph.
        for token in ["@Environment(ResourceGovernor.self)", "governor.settings"] {
            XCTAssertFalse(donut.contains(token), """
                `SpectralDonutView` now contains `\(token)`. If the quality governor was \
                deliberately wired here, GOOD — but it changes the premise two notes rest on, \
                and the freeze law has to be answered rather than skipped: this view's draw \
                closure is a `Canvas` inside a `TimelineView`, so it is ON the SwiftUI \
                observation graph, in the window above the studio's menus. `MetalBioView` \
                reads the governor inside `draw(in:)`, off the graph, which is why the same \
                read is safe there and not here. Confirm an open `.menu` Picker survives a \
                tier change on a device, then update this claim, the `bandCount` note here, \
                and `ResourceGovernor`'s `allowSpectralDonuts` line together.
                """)
        }
    }
}
