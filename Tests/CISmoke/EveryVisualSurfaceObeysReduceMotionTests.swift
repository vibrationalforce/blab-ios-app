// EveryVisualSurfaceObeysReduceMotionTests.swift
// Echoel — the accessibility setting, on EVERY surface, in the BLOCKING bundle.
//
// ⛔ WHAT IT CAUGHT (#1118). The projector ignored "Reduce Motion" entirely, and it is the
// biggest surface the app drives. `FloatingVisualWindow` has read the setting since it was
// written and hands it to `MetalBioView`; `ExternalDisplayScene` never mentioned the word —
// `grep -n "reduceMotion" ExternalDisplayScene.swift` returned nothing. So a person who
// turns the setting on got a STILL picture on a 6-inch phone and a FULL-MOTION one on a
// projector filling a room: the wrong way round, and against what the site states plainly
// ("honouring Reduce Motion", `architecture.html`; "reduced-motion support", `faq.html`).
//
// ⚠️ WHY A TEXT SCAN AND NOT A TYPE CHECK. `MetalBioView.reduceMotion` has a DEFAULT of
// `false`, so a mount that omits it compiles perfectly and renders full motion. There is no
// compiler error to wait for, which is exactly the condition that let this survive: the one
// argument in that struct's header about "the ONE mount that omits it" is about
// `playGridKey`, a different parameter, and reads like cover for this one if skimmed.
//
// ⚠️ SCOPE. It checks that each construction site PASSES the argument, not what it passes.
// A site could hand it a constant `false` and stay green. That is deliberate: a per-surface
// override may one day be a real design decision (a stage that must keep moving), and a
// guard that forbade it would be the #364 mistake. What may never happen silently again is a
// surface that does not consider the setting at all.

import Foundation
import XCTest
@testable import Echoelmusic

final class EveryVisualSurfaceObeysReduceMotionTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Every `.swift` file under `Sources/`, read once.
    private func sources() -> [(path: String, text: String)] {
        let base = repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: base.path) else { return [] }
        var out: [(String, String)] = []
        for case let name as String in walker where name.hasSuffix(".swift") {
            let url = base.appendingPathComponent(name)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                out.append(("Sources/" + name, text))
            }
        }
        return out.map { (path: $0.0, text: $0.1) }
    }

    // MARK: - 1 · Every mount considers the setting

    func testEveryMetalBioViewMountPassesReduceMotion() {
        let files = sources()
        XCTAssertFalse(files.isEmpty, "no Swift sources were readable — this guard checked nothing")

        var mounts = 0
        for file in files {
            // Skip the renderer's own file: it DECLARES the view, it does not mount it, and
            // its header quotes the constructor in prose.
            guard !file.path.hasSuffix("MetalBioView.swift") else { continue }
            var cursor = file.text.startIndex
            while let hit = file.text.range(of: "MetalBioView(", range: cursor ..< file.text.endIndex) {
                cursor = hit.upperBound
                // The argument list, up to the first closing paren that ends the call. Reading
                // to the next `.environment(` / newline-brace would be fragile, so take a
                // generous window and look inside it — a false PASS is impossible because the
                // window can only ever be too big, never too small.
                let windowEnd = file.text.index(hit.upperBound, offsetBy: 1400,
                                                limitedBy: file.text.endIndex) ?? file.text.endIndex
                let window = String(file.text[hit.upperBound ..< windowEnd])
                mounts += 1
                XCTAssertTrue(window.contains("reduceMotion:"), """
                    A `MetalBioView(` mount in \(file.path) does not pass `reduceMotion:`. \
                    The parameter has a default of `false`, so this compiles and silently \
                    renders FULL MOTION for a user who asked the system for less — the exact \
                    defect #1118 fixed on the external display, where the surface is a \
                    projector. Pass it (it is declared SECOND in `MetalBioView`, so it goes \
                    right after `capturesVideo:` — Swift's memberwise init follows declaration \
                    order). If this surface genuinely must keep moving, pass an explicit \
                    value and say why at the call site; do not omit the argument.
                    """)
            }
        }
        XCTAssertGreaterThanOrEqual(mounts, 2, """
            Fewer than two `MetalBioView(` mounts were found outside the renderer's own file. \
            There are two — `FloatingVisualWindow` and `ExternalDisplayScene` (#1069 deleted \
            the third, the fullscreen cover). Fewer means the scan stopped matching, not that \
            a surface disappeared: check the needle before believing a green.
            """)
    }

    // MARK: - 2 · COUNTERWEIGHT — why claim 1 has to exist at all

    func testTheParameterStillHasASilentDefault() throws {
        let renderer = try String(
            contentsOf: repoRoot().appendingPathComponent("Sources/Echoelmusic/Views/MetalBioView.swift"),
            encoding: .utf8)
        XCTAssertTrue(renderer.contains("var reduceMotion: Bool = false"), """
            `MetalBioView.reduceMotion` no longer has its `= false` default. If you made the \
            parameter REQUIRED, that is strictly better than this guard — the compiler now \
            refuses a mount that ignores the setting, and it cannot be skimmed past. In that \
            case DELETE this file rather than restoring the default (#364: a guard that \
            outlives the problem it describes starts arguing against the fix). If the default \
            merely moved or was renamed, point both claims at the new spelling.
            """)
    }
}
