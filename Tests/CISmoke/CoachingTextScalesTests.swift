// CoachingTextScalesTests.swift
// Echoel — the line that tells you what to do must obey Larger Text. #353d.
//
// WHAT THIS GUARDS. `BioStripView.banner(_:color:systemImage:)` renders the strip's ONLY
// instruction: "Cover the camera and flash", "Enable camera access", "Pulse detected — you
// can let go & play". It was set with `.font(.system(size: 11, weight: .medium))`, and
// `.system(size:)` WITHOUT `relativeTo:` is an absolute point size — it does not participate
// in Dynamic Type at all. A user at AX5 read the app's coaching at 11 pt.
//
// ⭐ THE DISTINCTION THAT DECIDED THE SLICE, and it corrects a claim I had already filed.
// The strip below this banner carries `.minimumScaleFactor(0.6)`, which looks like the same
// defect and is NOT one: a scale factor is a fraction of the CURRENT size, so at AX3 those
// numbers still render larger than the default-size ones — the requested increase is capped,
// not cancelled. #353c had it written down as "shrinks the numbers when the user asks for
// bigger text", which is false, and it is corrected there. This banner is the genuinely
// binary case: absolute means absolute.
//
// ⚠️ THE WEIGHT WAS DROPPED ON PURPOSE, and a future reader must not "restore" it. The app
// bundles Atkinson Hyperlegible in Regular, Bold and Italic only, so `EchoelTheme.font(11,
// .medium)` resolves to Regular while READING as a decision — the exact 62-site defect #361
// swept out, and `TypeWeightsThatExistTests` fails it. The emphasis this line needs is
// carried by its semantic colour and its icon, both of which it already had.
//
// ⚠️ WHY THIS WAS SAFE WITHOUT A LAYOUT REDESIGN, which the third test pins: the banner is
// NOT under the strip's `.lineLimit(1)` (that modifier sits on `strip`, a sibling in the
// same `VStack`), it has no fixed height, and nothing above it in `bioPanel` constrains
// height either. So it wraps and the stack grows. Put a `lineLimit` on it and the fix
// silently converts from "text scales" to "text truncates" — worse than before, because the
// old 11 pt at least fit.
//
// ⚠️ HONEST LIMITS. Source-text scan, no simulator: it proves the font is still SPELLED as
// the scaling one, never that a sentence wraps legibly at AX5 (NEEDS-FOUNDER-VERIFY: Larger
// Text at AX3+, open Bio, cover the camera, read the amber line). And it pins ONE banner:
// `.font(.system(size:` remains in many other places under `Sources/`, most of them icon
// glyphs where the judgement is genuinely different — a symbol inside a deliberately-sized
// frame can burst it. Each needs its own look, which is why this is not a sweep. The class
// is filed as #353d, which carries the counting command.
//
// ⛔ NO COUNT IS QUOTED HERE, and the reason is that the first draft quoted one and it was
// WRONG WHEN COMMITTED. It said "still occurs 97 times across 25 files" — 97 was the figure
// BEFORE this slice, and this slice removes two of them. A count written into the same commit
// that changes it is stale on arrival. That is the third time in two cycles (see the ⛔ about
// "twelve comment lines" in `ChipLabelGrowsWithTheTextTests`), so the rule here is stronger
// than "re-count": a prose count next to work that moves it does not earn its place at all.
// The command lives in #353d, where it can be re-run.
//
// ⛔ ONE OF THE THREE TESTS GOES RED ON THE PRE-FIX SOURCE. Verified against `HEAD` before
// this slice: `testTheBannerUsesAScalingFont` fails both ways it can (two `.system(size:)`
// lines present, zero `EchoelTheme.font` calls). The weight test and the wrap test were
// already green and stay green — they are CONSISTENCY PINS against plausible regressions
// (a "restored" `.medium`, an added `lineLimit`), never evidence that this slice fixed
// anything there. Stated because "red for the right reason" has been claimed over a whole
// file in this bundle when it was true of one assertion.
// `Tests/CISmoke` is the blocking bundle. SKIPS rather than passes if the tree is absent.

import Foundation
import XCTest

final class CoachingTextScalesTests: XCTestCase {

    private static let strip = "Sources/Echoelmusic/Studio/BioStripView.swift"
    private static let bannerDeclaration =
        "private func banner(_ text: String, color: Color, systemImage: String)"

    /// The banner's own font must come from the brand helper, which is `relativeTo: .body`.
    func testTheBannerUsesAScalingFont() throws {
        let source = try codeLines(Self.strip)
        // ⛔ NOT NAMED `window`, in any of these three tests. A local `let window` shadows the
        // `window(_:from:)` helper below, and the third test calls that helper AFTER binding
        // it — `window(source, from:)` would then parse as calling an `ArraySlice` as a
        // function and fail to compile. Caught by reading, which is the only compiler this
        // environment has; a green `Xcode Compile Check` would not have caught it either,
        // since that gate never builds `Tests/`.
        let banner = try bannerWindow(source)

        let frozen = banner.filter { $0.contains(".system(size:") }
        XCTAssertTrue(frozen.isEmpty, """
            The bio strip's status banner is back on an absolute font size: \
            \(frozen.map { $0.trimmingCharacters(in: .whitespaces) }). \
            `.system(size:)` without `relativeTo:` does not scale with Dynamic Type at all, \
            and this banner is where the app says "Cover the camera and flash" and "Enable \
            camera access" — the instructions a user with impaired sight most needs to read. \
            Use `EchoelTheme.font(_:)`, which is `.custom(…, relativeTo: .body)`.
            """)

        let scaling = banner.filter { $0.contains("EchoelTheme.font(") }
        XCTAssertEqual(scaling.count, 2, """
            Expected exactly two `EchoelTheme.font(...)` calls in the banner (the icon and \
            the text), found \(scaling.count). Both must scale together: an SF Symbol pinned \
            at a fixed size beside text that reaches AX5 reads as a speck, and a symbol takes \
            its size from a custom `Font` just as a glyph does. If the banner genuinely grew a \
            third piece of content, widen this count in the same commit rather than deleting \
            the assertion.
            """)
    }

    /// A weight the app cannot render must not come back with the scaling font.
    ///
    /// ⚠️ NOT a duplicate of `TypeWeightsThatExistTests`. That guard sweeps `Sources/` for
    /// `EchoelTheme.font(_, .medium)` and friends generally. This one is anchored at the site
    /// that just LOST a `.medium` — the plausible regression here is someone reading the diff
    /// as an accidental weight loss and "restoring" it through the new helper, which would be
    /// invisible on screen. The sibling guard would catch it too; this one explains why.
    func testTheBannerDoesNotAskForAWeightTheAppLacks() throws {
        let source = try codeLines(Self.strip)
        let banner = try bannerWindow(source)
        for weight in ["ultraLight", "thin", "light", "medium"] {
            XCTAssertFalse(banner.contains { $0.contains("EchoelTheme.font(") && $0.contains(".\(weight)") }, """
                The banner asks `EchoelTheme.font` for `.\(weight)`. Echoel bundles Atkinson \
                Hyperlegible in Regular, Bold and Italic only, so anything that is not \
                semibold/bold/heavy/black silently resolves to Regular — the source would read \
                as a design decision that never reaches a screen (#361). If this line should \
                be heavier, say `.semibold` and get the Bold face; if it should not, say \
                nothing. `.\(weight)` says neither.
                """)
        }
    }

    /// The property the fix depends on: this text is allowed to wrap.
    func testTheBannerIsNotLineLimited() throws {
        let source = try codeLines(Self.strip)
        let banner = try bannerWindow(source)
        XCTAssertFalse(banner.contains { $0.contains("lineLimit") }, """
            A `lineLimit` appeared inside the bio strip's banner. Scaling the font was only \
            safe because this line WRAPS: the strip's own `.lineLimit(1)` sits on `strip`, a \
            sibling in the same `VStack`, and nothing above the strip in `bioPanel` fixes a \
            height. Capping the line count converts the fix from "the instruction gets bigger" \
            into "the instruction gets truncated", which is worse than the 11 pt it replaced — \
            at 11 pt the sentence at least fit. Truncated coaching text is the exact complaint \
            the founder raised twice about the HRV info sheets.
            """)

        // The other half of that claim: the `lineLimit(1)` is still on `strip`, where it
        // belongs. Asserted rather than assumed, because "it is elsewhere" is the whole
        // reason the banner may wrap — if BOTH lost it, the sibling metric cells would start
        // wrapping and the strip's careful equal-width cells would reflow.
        let stripWindow = try window(source, from: "private var strip: some View")
        XCTAssertTrue(stripWindow.contains { $0.contains("lineLimit(1)") }, """
            `strip` lost its `.lineLimit(1)`. That modifier is what keeps the four metric \
            cells on one line each inside their equal-width frames; without it a long value \
            wraps and the row reflows — the "wobble" the equal-width layout was built to stop. \
            It is also the line that makes the banner's freedom to wrap a deliberate \
            asymmetry rather than an oversight.
            """)
    }

    // MARK: - Reading the source

    private func bannerWindow(_ source: [String]) throws -> ArraySlice<String> {
        try window(source, from: Self.bannerDeclaration)
    }

    /// Lines from `declaration` up to the next member declaration.
    ///
    /// ⛔ BOUNDED BY THE NEXT MEMBER, NOT BY A LINE COUNT — the lesson `ChipLabelGrowsWith
    /// TheTextTests` paid for one slice earlier, applied from the start here. This slice adds
    /// a 20-line rationale block directly above the banner; a count anchored below it would
    /// have been wrong before it was ever committed.
    private func window(_ source: [String], from declaration: String) throws -> ArraySlice<String> {
        guard let start = source.firstIndex(where: { $0.contains(declaration) }) else {
            throw XCTSkip("""
                `\(declaration)` is gone from BioStripView — if the banner was restructured \
                this test should be rewritten with it, not left to pass vacuously
                """)
        }
        let end = source[start...].dropFirst()
            .firstIndex { $0.contains("private var ") || $0.contains("private func ") }
            ?? source.count
        return source[start..<end]
    }

    /// Lines of `path` that are not whole-line comments. Dropped because the rationale block
    /// above the banner QUOTES the spelling it replaced (`.system(size: 11, weight: .medium)`)
    /// — a naive match would find the old form in the prose explaining the new one and fail
    /// forever.
    ///
    /// ⚠️ Whole-line only: a TRAILING comment on a code line survives and would be read as
    /// code. Every comment in this window is whole-line today. Same accepted limit as the
    /// sibling guards in this bundle.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let probe = root.appendingPathComponent(Self.strip)
        guard FileManager.default.fileExists(atPath: probe.path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }
}
