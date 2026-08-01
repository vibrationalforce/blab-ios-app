// SectionHeadingIsOneTreatmentTests.swift
// Echoel — one job, one treatment: every section heading in the studio goes through
// `groupHeader`.
//
// WHAT THIS GUARDS (#362). "A group of rows starts here" had THREE spellings, split by
// panel family, and no per-file review could see it because each panel was internally
// consistent:
//   · `soundPanel`   → `groupHeader(_:)`                    — 11 pt semibold, dim   (7 sites)
//   · Visual/Bio/Field → `font(10, .medium)` + dim inline   — 10 pt, weight ignored (5 sites)
//   · Session weather → `font(12, .semibold)` + dim inline  — 12 pt semibold        (2 sites)
// Three sizes and three weights, reachable in three taps of the same chip strip.
//
// ⭐ THE HALF THAT IS NOT TASTE. `EchoelTheme.font(_:_:)` maps only `.semibold/.bold/
// .heavy/.black` onto the Bold face; the app bundles Regular, Bold and Italic only, and
// `Font.custom` does not synthesize a weight from a family. So `font(10, .medium)` never
// rendered medium — it rendered 10 pt REGULAR (#361). The Field panel's own source comment
// had already recorded the SYMPTOM ("read as a SECOND panel title rather than a peer")
// without naming the cause. Unifying onto 11 pt semibold does not just pick a winner; it
// picks the one spelling that renders what it says.
//
// ⛔ WHAT IS DELIBERATELY NOT IN SCOPE, because my own first pass at #362 got it wrong.
// `Text("Motion")`, `Text("Rhythm")` and `Text("Grid")` sit in an `HStack` next to a
// `Picker`. They are ROW LABELS, not headings — `groupHeader` applies
// `.frame(maxWidth: .infinity, alignment: .leading)`, which would have pushed those pickers
// off their rows. I counted them among the "five heading treatments" from a grep of font
// sizes before reading their containers. A grep finds spellings; only the container says
// what a `Text` IS. (They carry a separate, real inconsistency — 12 pt against
// `EchoelValueField`'s 14 pt label two rows up — which is its own slice.)
//
// ⚠️ WHAT A GREEN HERE DOES NOT MEAN. This scans SOURCE TEXT: there is no simulator in this
// environment and `Tests/CISmoke` is the blocking bundle, so nothing here renders a view. It
// proves the seven headings still ROUTE through one builder and that the builder still names
// a weight the font file actually contains. It cannot prove they look right on a device —
// that is a founder sighting. If the checkout is not at the path this file was compiled
// from it SKIPS rather than passes; a silent pass on an unscanned tree is the
// `continue-on-error` lie the `doctor` skill exists to catch.

import Foundation
import XCTest

final class SectionHeadingIsOneTreatmentTests: XCTestCase {

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()   // CISmoke
            .deletingLastPathComponent()              // Tests
            .deletingLastPathComponent()              // repo
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }

    private func codeLines(_ path: String) throws -> [String] {
        let text = try String(contentsOf: try repoRoot().appendingPathComponent(path),
                              encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let theme = "Sources/Echoelmusic/Studio/EchoelTheme.swift"

    // MARK: - The builder itself

    func testGroupHeaderStillNamesAWeightTheFontFileHas() throws {
        let studio = try codeLines(Self.studio)
        guard let def = studio.firstIndex(where: {
            $0.contains("private func groupHeader(_ t: String)")
        }) else {
            return XCTFail("""
                `groupHeader` is gone from EchoelStudioView. It is the single section-heading \
                builder for every panel; if it was renamed, re-anchor this file in the same \
                commit rather than deleting it — the incoherence it closed took a whole audit \
                to see, and nothing else in the tree would notice it coming back.
                """)
        }
        let body = studio[def..<min(def + 5, studio.count)].joined(separator: "\n")
        XCTAssertTrue(body.contains("EchoelTheme.font(11, .semibold)"), """
            `groupHeader` no longer spells `EchoelTheme.font(11, .semibold)`. The weight is \
            not decoration: `EchoelTheme.font` maps ONLY .semibold/.bold/.heavy/.black onto \
            the Bold face, and the app bundles Regular/Bold/Italic only. Any other weight \
            silently renders REGULAR (#361), which is exactly how three "different" heading \
            treatments ended up looking like two.
            """)
        XCTAssertTrue(body.contains("EchoelTheme.dim"), """
            `groupHeader` no longer uses `EchoelTheme.dim`. A heading in `text` sits at the \
            same weight and colour as the panel TITLE one line above it, which is the defect \
            the Field panel's "Voice" heading was fixed for once already.
            """)
    }

    /// The mapping `groupHeader` depends on, pinned where it lives. Without this, someone
    /// could "tidy" `EchoelTheme.font`'s switch and turn every heading in the app back into
    /// Regular with no test anywhere going red.
    func testTheThemeStillMapsSemiboldOntoTheBoldFace() throws {
        let theme = try codeLines(Self.theme)
        XCTAssertTrue(theme.contains { $0.contains("case .semibold, .bold, .heavy, .black:") }, """
            `EchoelTheme.font`'s weight switch changed. Every heading in the studio asks for \
            `.semibold`; if that case stops selecting the Bold face, all of them fall to the \
            Regular face at once — visible everywhere, blamed nowhere.
            """)
        XCTAssertTrue(theme.contains { $0.contains("AtkinsonHyperlegible-Bold") }, """
            The Bold face name is gone from `EchoelTheme`. `Font.custom` does not synthesize \
            a weight from a family — the face must be named explicitly, or the request \
            silently returns the Regular face.
            """)
    }

    // MARK: - Every heading goes through it

    /// The seven headings #362 converted, named by their user-visible strings. Anchoring on
    /// the string rather than a line number is deliberate: this file has moved these lines by
    /// hundreds within a single commit before.
    func testEverySectionHeadingCallsTheBuilder() throws {
        let studio = try codeLines(Self.studio)
        let joined = studio.joined(separator: "\n")
        // "Look" appears twice on purpose — the inline Visual panel and the (dead, #270) VJ
        // overlay copy. Both are listed so a future revival of the overlay cannot bring the
        // old spelling back with it.
        for title in ["Look", "Signal", "Body", "Voice", "Self-play"] {
            XCTAssertTrue(joined.contains("groupHeader(\"\(title)\")"), """
                The "\(title)" section heading no longer calls `groupHeader`. It was one of \
                the seven #362 unified; spelling a heading inline is how the panels drifted \
                apart in the first place, and the drift is invisible in a per-file review \
                because each panel stays consistent with itself.
                """)
            XCTAssertFalse(joined.contains("Text(\"\(title)\").font(EchoelTheme.font(10"), """
                The "\(title)" heading is spelled inline at 10 pt again. That size came with \
                `.medium`, a weight this app cannot render — see the header.
                """)
        }
        // The Session panel's weather groups take their title as a parameter, so there is no
        // literal to look for — pin the call instead.
        XCTAssertTrue(joined.contains("groupHeader(title)"), """
            `weatherMixGroup` no longer routes its title through `groupHeader`. Its two \
            headings ("Sound" and "Image") were the 12 pt semibold third treatment.
            """)
    }

    /// Counting is the part a per-heading check misses: it catches a NEW heading added in the
    /// old inline style, which no assertion above can see.
    func testNoInlineHeadingSurvivesInTheStudio() throws {
        let studio = try codeLines(Self.studio)
        // Anchored to `Text(` as well as the font, so the `Label`, `Button` and `Toggle`
        // call sites that legitimately use the same font today cannot trip this. The
        // AirPlay hint in the VJ overlay is exactly such a `Label` — a caption, not a
        // heading, and it must stay a caption.
        //
        // ⛔ REPORTS THE MATCHED TEXT, NOT A LINE NUMBER, and that is a correction to my own
        // first draft: `codeLines` DROPS whole-line comments, so an index into it is not the
        // file's line number. A failure message that points at the wrong line is worse than
        // one that points nowhere — it sends the next reader to an innocent line and costs
        // them the trust they need to act on the rest of the message.
        let offenders = studio.filter {
            $0.contains("Text(")
                && $0.contains("EchoelTheme.font(10, .medium)")
                && $0.contains("EchoelTheme.dim")
        }
        // Hoisted out of the message: a closure inside a `\(...)` inside a multi-line literal
        // is the shape that made the blocking gate red on #287, where the expression cost more
        // to type-check than the assertion was worth.
        let shown = offenders.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " | ")
        XCTAssertTrue(offenders.isEmpty, """
            A heading is spelled inline as 10 pt dim again — \(shown). Every section heading \
            goes through `groupHeader`; a new one added in the old style is how the three \
            treatments grew in the first place, one honest local decision at a time.
            """)
    }
}
