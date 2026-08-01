// AutoGainClampMatchesTheWebsiteTests.swift
// Echoel — #333. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ WHAT THIS GUARDS AND WHY IT IS NOT DOC-TIDINESS: `docs/` is the PUBLISHED GitHub Pages
// site. `docs/architecture.html` is the page a technical reader — an integrator, a label, a
// venue — checks before believing the audio claims. Its `AutoMixChain` row said the master
// auto-gain works over **±12 dB**. The code clamps at **±6**, in `steadyGainDB(maxDB: Float = 6)`.
// The published figure was a factor of two out, in the direction that overstates the product.
//
// ⛔ AND THE FIRST VERSION OF THIS PARAGRAPH ATTACHED A WRONG JUSTIFICATION TO THAT RIGHT
// NUMBER — the exact failure this slice exists to stop, committed inside the slice itself.
// It said the node clamp (`outputVolume` to 0.5…2.0 linear, `AutoMixChain.swift`) was "the
// same ±6.02 dB". It is neither the same nor a second expression of one invariant:
//   · 20·log10(2) = 6.0206 dB, so the node bound is 0.02 dB WIDER than `maxDB`;
//   · `smoothedGainDB` eases as `current + delta·coeff` with `coeff ∈ [0.05, 0.18] ⊂ (0,1)`
//     toward a value already clamped to [−6, 6] — a convex step that cannot leave that
//     interval. So `linearGain ∈ [0.50119, 1.99526]` and the node clamp CAN NEVER BIND.
// It is defensive, not confirmatory. Read the wrong way, it invites widening `maxDB` to 8 in
// the belief that the node still holds the line at 6 — it holds at 6.02, i.e. not at all.
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
// source constant say the same thing. It reads two files as text. It also only requires the
// figure to appear ONCE: a stale second `±12 dB` elsewhere on the page would not redden it.
// (Checked by hand at the time of writing — the page has exactly one `±… dB`. Stated because
// "the guard is green" and "the page is consistent" are different sentences.)

import Foundation
import XCTest

final class AutoGainClampMatchesTheWebsiteTests: XCTestCase {

    private static let chain = "Sources/Echoelmusic/Audio/AutoMixChain.swift"
    private static let page  = "docs/architecture.html"

    func testTheWebsiteQuotesTheClampTheCodeActuallyApplies() throws {
        let found = Self.declaredClamps(in: try source(Self.chain))

        guard found.count == 1, let clamp = found.first, !clamp.isEmpty else {
            XCTFail("""
                Expected exactly ONE `maxDB: Float = <number>` in `AutoMixChain.swift`, found \
                \(found.count)\(found.isEmpty ? "" : ": \(found.joined(separator: ", "))").
                Zero means the default moved, was renamed, or became an expression — point this \
                guard at the new spelling in the SAME commit and re-check the `±… dB` figure in \
                `\(Self.page)` while you are there, because that page is published.
                More than one means this guard can no longer tell which number is live; it reads \
                the FIRST, and a tombstone comment quoting an old value would make it enforce \
                that old value against a correct page. Anchor it on the live declaration.
                """)
            return
        }

        let quoted = "±\(clamp) dB"
        let page = Self.normalisingSpaces(try source(Self.page))

        XCTAssertTrue(page.contains(quoted), """
            The published architecture page does not quote the auto-gain clamp the code \
            applies. `steadyGainDB` clamps at ±\(clamp) dB, so the page must say "\(quoted)" \
            (a `&nbsp;` there is fine — this comparison normalises it).
            This is the #333 defect exactly: the page said ±12 dB for a stage the code had \
            narrowed to ±6 — a factor of two, overstating the product, on the page a \
            technical reader checks. `docs/` is the live GitHub Pages site.
            Fix the sentence in `\(Self.page)`, not this test — unless the CLAMP itself moved, \
            in which case both change together.
            """)
    }

    // MARK: - helpers

    /// Every `maxDB: Float = <number>` in the file, as the numbers alone with a trailing
    /// `.0` dropped. Three things this does that a literal `range(of: "maxDB: Float = ")`
    /// did not, each of which a reviewer showed was a live false-RED in the ONLY bundle
    /// that can fail a merge:
    ///  · it tolerates SPACING. `maxDB:Float = 6` or a SwiftFormat line-break through the
    ///    parameter list would have made the literal marker vanish and reddened the gate on
    ///    a change that altered nothing.
    ///  · it returns ALL occurrences instead of the first, so the caller can insist there is
    ///    exactly one. This file's own header quotes the signature verbatim and the house
    ///    style is heavy tombstone comments — a future `// was maxDB: Float = 12` placed
    ///    ABOVE the declaration would otherwise make the guard enforce 12 against a correct
    ///    page, with a message blaming the page. It failed safe here by luck, not design.
    ///  · trailing `.0` is dropped, because prose writes "±6" and never "±6.0". `6.5` is
    ///    untouched.
    private static func declaredClamps(in code: String) -> [String] {
        var numbers: [String] = []
        var from = code.startIndex
        while let hit = code.range(of: #"maxDB\s*:\s*Float\s*=\s*[0-9]+(\.[0-9]+)?"#,
                                   options: .regularExpression,
                                   range: from..<code.endIndex) {
            var n = String(code[hit])
            if let eq = n.range(of: "=") {
                n = String(n[eq.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            if n.hasSuffix(".0") { n.removeLast(2) }
            numbers.append(n)
            from = hit.upperBound
        }
        return numbers
    }

    /// HTML space entities → a plain space, so the comparison is about the NUMBER and not
    /// about how the page happens to encode the gap before "dB". `±6&nbsp;dB`, `±6&#160;dB`,
    /// a literal U+00A0 and a plain space all render identically; any HTML tidy pass can
    /// swap one for another. The first version hardcoded `&nbsp;` into the expected string,
    /// which made a purely cosmetic edit able to redden the blocking gate.
    private static func normalisingSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

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
