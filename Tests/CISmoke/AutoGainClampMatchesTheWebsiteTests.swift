// AutoGainClampMatchesTheWebsiteTests.swift
// Echoel — #333. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ WHAT THIS GUARDS AND WHY IT IS NOT DOC-TIDINESS: `docs/` is the PUBLISHED GitHub Pages
// site. `docs/architecture.html` is the page a technical reader — an integrator, a label, a
// venue — checks before believing the audio claims. Its `AutoMixChain` row said the master
// auto-gain works over **±12 dB**. The code clamps at **±6** and has since it was narrowed
// (`steadyGainDB(maxDB: Float = 6)`, and again at the node: `outputVolume` clamped to
// 0.5…2.0 linear, which is the same ±6.02 dB). The published figure was a factor of two out,
// in the direction that overstates the product.
//
// That is the class this repo has already paid for repeatedly — #158 and #192 spent two
// whole cycles removing ONE false AUv3 claim from this same site, #184 removed twelve from
// the App Store text, where a false claim is a 2.3 rejection. The pattern is always the
// same: a constant is tightened in code, and the prose that quoted it is not in the diff.
//
// THE INVARIANT, and it is deliberately ONE thing: whatever `steadyGainDB`'s `maxDB` default
// is, the website must quote THAT number. Not "the docs are accurate" — this file cannot
// know that. Just this one number, which is the one that was wrong.
//
// ⛔ WHY THE FOUR EQ FREQUENCIES ARE **NOT** PINNED HERE, though the same commit fixed all
// four (40→45 Hz, 180→140 Hz, 3→2.8 kHz, 10→9 kHz): the code writes `2800` and `9000` while
// the page writes "2.8 kHz" and "9 kHz". Any guard would need a code→prose formatting table,
// and that table is a THIRD copy of the numbers — the thing most likely to go stale, and it
// would go stale silently while looking like coverage. A guard that restates what it guards
// is not a guard. The frequencies are instead anchored in `configureEQ()`'s comments, which
// sit on the same screen as the values.
//
// ⚠️ WHAT THIS FILE CANNOT REACH: it does not render the page, does not run the audio graph,
// and does not verify that ±6 dB is the RIGHT clamp — only that one published number and one
// source constant say the same thing. It reads two files as text.

import Foundation
import XCTest

final class AutoGainClampMatchesTheWebsiteTests: XCTestCase {

    private static let chain = "Sources/Echoelmusic/Audio/AutoMixChain.swift"
    private static let page  = "docs/architecture.html"

    func testTheWebsiteQuotesTheClampTheCodeActuallyApplies() throws {
        let code = try source(Self.chain)
        let marker = "maxDB: Float = "

        guard let start = code.range(of: marker) else {
            XCTFail("""
                `\(marker)` is gone from `AutoMixChain.swift`, so this guard can no longer \
                see what the auto-gain clamps to. If the default moved or was renamed, point \
                this test at the new spelling in the SAME commit and re-check the `±… dB` \
                figure in `\(Self.page)` while you are there — that page is published.
                """)
            return
        }

        // Trailing `.0` normalised so `6` and `6.0` both compare against the page's "±6".
        // Prose does not write a trailing zero, and a RED over that would be a guard firing
        // on a change that broke nothing — the failure mode this bundle is most expensive for.
        var clamp = String(code[start.upperBound...].prefix { $0.isNumber || $0 == "." })
        if clamp.hasSuffix(".0") { clamp.removeLast(2) }

        XCTAssertFalse(clamp.isEmpty, """
            Could not read a number after `\(marker)` in `AutoMixChain.swift`. The default is \
            presumably an expression now; state the resulting dB figure in a comment there and \
            update this guard to read it.
            """)

        let quoted = "±\(clamp)&nbsp;dB"
        let page = try source(Self.page)

        XCTAssertTrue(page.contains(quoted), """
            The published architecture page does not quote the auto-gain clamp the code \
            applies. `steadyGainDB` clamps at ±\(clamp) dB, so the page must contain \
            "\(quoted)".
            This is the #333 defect exactly: the page said ±12 dB for a stage the code had \
            narrowed to ±6 — a factor of two, overstating the product, on the page a \
            technical reader checks. `docs/` is the live GitHub Pages site.
            Fix the sentence in `\(Self.page)`, not this test — unless the CLAMP itself moved, \
            in which case both change together.
            """)
    }

    // MARK: - helpers

    private func source(_ path: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                Source tree not reachable from the test bundle — skipping rather than reporting \
                a green this file did not earn.
                """)
        }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
