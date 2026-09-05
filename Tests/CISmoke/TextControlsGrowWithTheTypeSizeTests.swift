import XCTest

/// #1023 — "Alle Ansichten überprüfen … ob sie sich adaptiv verhalten, teilweise passt das noch
/// nicht" (founder, 2026-09-05), naming Routing and the Simulation source as examples.
///
/// WHAT WAS ACTUALLY WRONG, measured rather than guessed. `EchoelTheme.font(_:_:)` builds every
/// label with `relativeTo: .body`, so ALL text in this app already grows with Dynamic Type —
/// that half was never broken. What did not grow was the BOX around it: 37 text-bearing controls
/// carried a hard `.frame(height: N)`. At the default type size the two agree and nothing looks
/// wrong, which is why this survived so long; at an accessibility size the glyphs grow, the box
/// does not, and the label is clipped — a button whose caption you can no longer read.
/// `.frame(minHeight:)` is identical at the default size (the content is smaller than N, so the
/// frame is exactly N) and simply lets the box follow the text upward.
///
/// ⚠️ THIS IS THE CLASS, NOT THE ONE SCREEN. Routing (`PatchbayView`) held 6 of the 37; the root
/// instrument held 11. Fixing only the surface the founder happened to open would have left the
/// same defect in nine other views and taught the next session that it was a one-off.
///
/// ⚠️ WHAT IS DELIBERATELY NOT COVERED. A fixed height on something with no text — a divider, a
/// level meter, a waveform canvas, a keypad key — is correct and stays. The classifier below
/// looks for text in the four lines above the frame, which is what separates the two.
///
/// ⚠️ #364 — THIS GUARD FORBIDS NOTHING A FUTURE SESSION MAY NEED. A control that genuinely must
/// not grow can say so on its own line with `ADAPTIVE-EXEMPT:` plus a reason, and this claim
/// steps over it. The point is that the choice becomes visible in a diff, not that it becomes
/// impossible.
final class TextControlsGrowWithTheTypeSizeTests: XCTestCase {

    func testNoTextBearingControlPinsItsHeight() throws {
        let files = try sourceFiles()
        XCTAssertGreaterThan(files.count, 50, """
            The source sweep found almost nothing to read. A guard that scans an empty set is \
            green for the wrong reason (#808) — re-anchor the root before trusting this file.
            """)

        var offenders: [String] = []
        for url in files {
            let lines = try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (i, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") { continue }
                if line.contains("ADAPTIVE-EXEMPT:") { continue }
                guard line.range(of: #"\.frame\(height:\s*\d"#,
                                 options: .regularExpression) != nil else { continue }
                // The four lines above plus this one — the same window the sweep used.
                let context = lines[max(0, i - 4)...i]
                    .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                    .joined(separator: "\n")
                let carriesText = context.range(
                    of: #"\bText\(|\bLabel\(|TextField\(|systemImage:|Image\(systemName"#,
                    options: .regularExpression) != nil
                if carriesText {
                    offenders.append("\(url.lastPathComponent):\(i + 1)  \(trimmed.prefix(70))")
                }
            }
        }

        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) text-bearing control(s) pin their own height, so their label is \
            clipped at large Dynamic Type instead of the box growing with it (#1023):
            \(offenders.joined(separator: "\n"))
            Use `.frame(minHeight:)` — identical at the default type size — or, if the height \
            genuinely must not move, say so on the line with `ADAPTIVE-EXEMPT: <reason>`.
            """)
    }

    /// COUNTERWEIGHT — the classifier must still be able to SEE a fixed height, otherwise the
    /// claim above would go green the day the regex stops matching anything at all. Dividers and
    /// meters keep theirs on purpose, so a healthy tree always has some.
    func testTheSweepStillFindsTheFixedHeightsThatAreCorrect() throws {
        var found = 0
        for url in try sourceFiles() {
            let text = try String(contentsOf: url, encoding: .utf8)
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                if line.range(of: #"\.frame\(height:\s*\d"#,
                              options: .regularExpression) != nil { found += 1 }
            }
        }
        XCTAssertGreaterThan(found, 0, """
            The classifier no longer matches ANY `.frame(height:)` in `Sources/`. Either every \
            divider and meter lost its fixed height, or the regex stopped working — and in the \
            second case the claim above passes while inspecting nothing (#808).
            """)
    }

    // MARK: - helper

    private func sourceFiles() throws -> [URL] {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        guard FileManager.default.fileExists(atPath: sources.path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        guard let e = FileManager.default.enumerator(at: sources,
                                                     includingPropertiesForKeys: nil) else {
            throw XCTSkip("could not enumerate \(sources.path)")
        }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
