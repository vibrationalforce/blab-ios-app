// DiagnosticsTextScalesTests.swift
// Echoel — the crash log the app asks you to read must obey Larger Text. #353d.
//
// ⛔ "the same diagnostic log" — #917 made that literally false and the pairing argument
// survives anyway; see `testBothSitesAgreeOnTheSize`. Read "a diagnostic log" below.
//
// WHAT THIS GUARDS. Echoel renders the same diagnostic log in two places: `SafeModeView`, the
// recovery screen shown when `LaunchGuard` decides the previous launch died before the studio
// finished loading, and `EchoelStudioView.diagnosticsSheet`, reachable from "Diagnostics" in
// Save & Export and opened automatically by `surfacePriorCrashIfAny()`. Both set the log with
// `.font(.system(size: 11, design: .monospaced))`. That overload takes an ABSOLUTE point size
// and does not participate in Dynamic Type at all, so a user at AX5 — who had set the whole
// system to large text — got 11 pt on the one screen the app shows precisely because something
// already went wrong, and whose own explanatory paragraphs three lines above it scale normally.
//
// ⭐ THE FIX IS THE TEXT-STYLE OVERLOAD, NOT THE BRAND HELPER, and that distinction is the
// judgement worth recording. Everywhere else in this repo the answer to "this font does not
// scale" is `EchoelTheme.font(_:_:)`, which is `.custom(…, relativeTo: .body)`. Here it would be
// wrong: Atkinson Hyperlegible is proportional, and a log dump loses its column alignment the
// moment it stops being monospaced. `Font.system(_ style:design:)` keeps the monospaced family
// and takes a TEXT STYLE instead of a size, which is what scales. `.caption2` is 11 pt at the
// default setting, so the change is invisible to anyone who has not asked for bigger text.
//
// ⚠️ WHY NO WRAPPING MODIFIER IS ASSERTED HERE, unlike `CoachingTextScalesTests` two files over.
// That guard pins `.fixedSize(horizontal: false, vertical: true)` because its `Text` sits beside
// a `Spacer` in an `HStack`, the one shape where SwiftUI can settle on a single truncated line.
// Neither site here is that shape: both are a lone `Text` in a `VStack` inside a `ScrollView`
// with `frame(maxWidth: .infinity, alignment: .leading)`. What IS asserted is the absence of a
// `lineLimit`, because that is the modifier that would convert "the log got bigger" into "the log
// got cut off" — strictly worse than the 11 pt it replaced, since at 11 pt the whole log fit.
//
// ⚠️ HONEST LIMITS. Source-text scan; there is no simulator in the blocking bundle. It proves
// the font is still SPELLED as the scaling one at both sites, never that a wrapped monospaced log
// reads well at AX5 — and that is a real open question for a raw log with long lines, not a
// formality. NEEDS-FOUNDER-VERIFY: Settings → Larger Text at AX3 or above, then Save & Export →
// Diagnostics. Does the log grow, and is it still usable, or does the wrapping make it worse than
// the fixed size was? If it reads badly, the answer is a `dynamicTypeSize` ceiling on this one
// `Text`, NOT a return to `.system(size:)` — a cap still honours part of the request.
//
// ⛔ TWO OF THE THREE TESTS GO RED ON THE PRE-FIX SOURCE, NOT ALL THREE — stated here because the
// previous cycle in this bundle shipped a commit body claiming "all three red" when one of them
// SKIPPED, and a skip is yellow. Verified by running each assertion against `git show HEAD:` for
// both files: `testTheRecoveryScreenLogScales` and `testTheDiagnosticsSheetLogScales` each fail
// twice over (one absolute `.system(size:` present, zero text-style fonts).
// `testBothSitesAgreeOnTheSize` SKIPS, because with no text-style font at either site there is
// nothing to compare — and a second confusing failure would only bury the two real ones. It earns
// its place from the day the fix lands, not before.
//
// This is one slice of #353d, which carries the counting command for the whole class. No count is
// quoted here on purpose: the sibling guard in this bundle records that a prose count written in
// the same commit that moves it has been wrong three times running.
//
// `Tests/CISmoke` is the blocking bundle. SKIPS rather than passes if the tree is absent.

import Foundation
import XCTest

final class DiagnosticsTextScalesTests: XCTestCase {

    private static let safeMode = "Sources/Echoelmusic/Studio/SafeModeView.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let sheetDeclaration = "private func diagnosticsSheet(_ text: String) -> some View"

    /// The recovery screen's log scales, and stays monospaced.
    func testTheRecoveryScreenLogScales() throws {
        // Whole file: `SafeModeView` is deliberately tiny (one `body`, no helpers), so there is
        // no neighbouring member a file-wide scan could wrongly accuse.
        let source = try codeLines(Self.safeMode)
        assertScalingMonospace(source, where: "SafeModeView")
    }

    /// The in-app Diagnostics sheet's log scales, and stays monospaced.
    func testTheDiagnosticsSheetLogScales() throws {
        let source = try codeLines(Self.studio)
        let sheet = try window(source, from: Self.sheetDeclaration, file: "EchoelStudioView")
        assertScalingMonospace(Array(sheet), where: "EchoelStudioView.diagnosticsSheet")
    }

    /// Both sites render A diagnostic log, so they must not disagree about its size.
    ///
    /// ⛔ THIS SAID "the SAME log" AND #917 MADE IT FALSE. The recovery screen now composes
    /// `recoveryExport()` — the previous run, plus a retained crash when that run carries no
    /// marker — while the sheet gets `diagnosticsExport()` or the auto-surfaced text. The
    /// ASSERTION is untouched and still right: it compares font SPELLINGS, and a user meeting
    /// the same kind of text through two doors should not meet it at two sizes. Only the
    /// identity claim had to go. This is the §4 shape — a guard that stays green while the
    /// reason printed beside it stops being true.
    ///
    /// ⛔ THE POINT OF THIS TEST IS THE PAIRING, NOT EITHER SITE. Each of the two above passes on
    /// its own with any scaling monospaced style, so a future edit could leave the recovery screen
    /// at `.caption2` and put the sheet on `.body` and both would stay green while the same text
    /// rendered at two sizes depending on which door you came through. That is the class of defect
    /// this repo has paid for repeatedly under a different name — one fact, two copies, corrected
    /// in one place.
    func testBothSitesAgreeOnTheSize() throws {
        let recovery = try fontSpelling(codeLines(Self.safeMode), where: "SafeModeView")
        let sheetSource = try codeLines(Self.studio)
        let sheet = try fontSpelling(Array(window(sheetSource, from: Self.sheetDeclaration,
                                                 file: "EchoelStudioView")),
                                     where: "EchoelStudioView.diagnosticsSheet")
        XCTAssertEqual(recovery, sheet, """
            The recovery screen and the Diagnostics sheet render the same crash log at two \
            different sizes: \(recovery) versus \(sheet). Whichever is right, both should say it. \
            A user who reaches the log through Save & Export and a user whose app fell into Safe \
            Mode are reading the same KIND of text (not, since #917, the identical string), and a \
            size that depends on which door they came through is a bug in exactly the place the \
            app is already apologising for one.
            """)
    }

    // MARK: - The shared assertion

    private func assertScalingMonospace(_ lines: [String], where site: String) {
        let absolute = lines.filter { $0.contains(".font(.system(size:") }
        XCTAssertTrue(absolute.isEmpty, """
            \(site) is back on an absolute font size for the diagnostic log: \
            \(absolute.map { $0.trimmingCharacters(in: .whitespaces) }). \
            `Font.system(size:design:)` does not participate in Dynamic Type at all, so this text \
            renders at its literal point size for every user including AX5. Use the TEXT-STYLE \
            overload — `.system(.caption2, design: .monospaced)` — which keeps the monospaced \
            family and scales. Do NOT reach for `EchoelTheme.font`: the brand face is \
            proportional and a log needs its columns to line up.
            """)

        let scaling = lines.filter { $0.contains(".font(.system(.") }
        XCTAssertEqual(scaling.count, 1, """
            Expected exactly one text-style `.font(.system(.…))` in \(site), found \
            \(scaling.count). This site renders one thing — the crash log — and it is the one \
            piece of text here that must scale without losing its monospaced family. If the view \
            genuinely grew a second such font, widen this count in the same commit rather than \
            deleting the assertion.
            """)

        XCTAssertTrue(scaling.allSatisfy { $0.contains("design: .monospaced") }, """
            \(site)'s log font is no longer monospaced: \
            \(scaling.map { $0.trimmingCharacters(in: .whitespaces) }). \
            The log is column-aligned text — timestamps on the left, breadcrumbs on the right. \
            In a proportional face those columns collapse and the log becomes materially harder \
            to scan, which is the opposite of what making it scale was for.
            """)

        XCTAssertFalse(lines.contains { $0.contains("lineLimit") }, """
            A `lineLimit` appeared in \(site). Scaling the log was only safe because it WRAPS: \
            the text is a lone `Text` in a `VStack` inside a `ScrollView`, with nothing capping \
            its height. Capping the line count turns "the log got bigger" into "the log got cut \
            off", which is worse than the fixed 11 pt it replaced — at 11 pt the whole log fit, \
            and a truncated crash log is a crash log nobody can share.
            """)
    }

    /// The single text-style font spelling at a site, trimmed — for comparing the two sites.
    private func fontSpelling(_ lines: [String], where site: String) throws -> String {
        guard let line = lines.first(where: { $0.contains(".font(.system(.") }) else {
            throw XCTSkip("""
                no text-style font found in \(site) — the other tests in this file report that \
                properly; comparing the two sites would only add a confusing second failure
                """)
        }
        return line.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Reading the source

    /// Lines from `declaration` to the closing brace at the declaration's own indentation.
    ///
    /// Structural, not a line count and not a naming convention — the house idiom in this bundle,
    /// arrived at because both alternatives failed: a count rots the moment a rationale block
    /// above it grows, and "stop at the next `private func`" is a guess about what the author of
    /// the NEXT member will type. Here the stakes are concrete: `EchoelStudioView` is over 6,000
    /// lines and the member following `diagnosticsSheet` is unrelated, so a window that ran on
    /// would report its lines under this test's name.
    ///
    /// ⚠️ Accepted limit: a multi-line string literal containing a line that is exactly this
    /// indentation plus `}` would end the window early. `diagnosticsSheet` contains no such
    /// literal; if it grows one, this needs a real brace scanner rather than a wider match.
    private func window(_ source: [String], from declaration: String,
                        file: String) throws -> ArraySlice<String> {
        guard let start = source.firstIndex(where: { $0.contains(declaration) }) else {
            throw XCTSkip("""
                `\(declaration)` is gone from \(file) — if the diagnostics sheet was \
                restructured this test should be rewritten with it, not left to pass vacuously
                """)
        }
        let indent = String(source[start].prefix { $0 == " " })
        let closer = indent + "}"
        guard let end = source[start...].dropFirst().firstIndex(where: {
            $0.hasPrefix(closer) && $0.trimmingCharacters(in: .whitespaces) == "}"
        }) else {
            throw XCTSkip("""
                `\(declaration)` in \(file) has no closing brace at its own indentation — the \
                file was reformatted or the member restructured, and reading on would inspect \
                the wrong lines
                """)
        }
        return source[start...end]
    }

    /// Lines of `path` that are not whole-line comments.
    ///
    /// ⚠️ Load-bearing HERE, and unlike the sibling guard that once claimed this falsely, the
    /// reason is checkable: this slice writes rationale blocks at both sites that QUOTE the
    /// spelling they replaced (`.font(.system(size: 11, design: .monospaced))`) in order to warn
    /// against it. An unfiltered scan would find the old form in the prose explaining the new one
    /// and fail forever.
    ///
    /// ⚠️ Whole-line only — a TRAILING comment on a code line survives and reads as code.
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
        guard FileManager.default.fileExists(atPath:
                root.appendingPathComponent(Self.safeMode).path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this test inspects source text, so \
                it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }
}
