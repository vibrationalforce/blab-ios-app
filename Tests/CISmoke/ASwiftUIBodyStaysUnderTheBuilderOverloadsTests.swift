import XCTest

// ⭐ #936 — A SwiftUI `body` WIDE ENOUGH TO NEED THE VARIADIC PACK IS A HAZARD, NOT A STYLE
// QUESTION, AND UNTIL NOW NOTHING IN THIS BUNDLE MEASURED ONE.
//
// THE OCCASION. CI run 33430039440 printed nine `took NNNms to type-check` warnings — a class
// the verdict reader only started surfacing with #933e/#935. Eight were in test files; the ONE
// in `Sources/` was `EchoelFXView.var body` at **1827 ms against a 200 ms limit**. Measured
// cause: its `Form` held TWENTY-ONE direct children. `ViewBuilder`'s fixed `buildBlock`
// overloads stop at ten, so everything past that resolves through the variadic generic pack and
// the checker re-infers one enormous aggregate type.
//
// WHY THIS BUNDLE CARES, and it is not build speed. CLAUDE.md's 10.76.34 entry records a
// SHIPPED black screen: `EchoelStudioView`'s aggregate generic type crossed the SwiftUI
// metadata-decoder's stack limit and SIGSEGV'd at first render, before any view appeared. That
// was the `.sheet` CHAIN; this is a `Form`'s CHILD LIST — different surface, same mechanism, and
// the same repo. A slow type-check is the only cheap symptom either one emits before it bites.
//
// ⚠️ WHAT THIS GUARD DOES NOT CLAIM. It does not say ten children crash anything; nothing here
// measured a threshold. It says the fifteen `effectSection` calls now live OUTSIDE `body`, which
// is the change #936 made and the thing a later "tidy up these tiny properties" pass would
// silently undo. A count-based claim would be the #364 trap — red on correct work the day
// someone legitimately adds a tenth row.
//
// ⛔ AND IT IS NOT ABOUT THE PRESENTATION CEILING. That budget is the `.sheet`/`.fullScreenCover`
// chain on `EchoelStudioView`, in a different file, pinned by a different guard. Nothing here
// moves it, and a session reading this must not "free up a modal slot" from it.
final class ASwiftUIBodyStaysUnderTheBuilderOverloadsTests: XCTestCase {

    private static let view = "Sources/Echoelmusic/Studio/EchoelFXView.swift"

    private func source(_ relative: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    /// The text of `var body` up to the next member declaration at the same indentation.
    ///
    /// ⛔ CALLERS MUST HAND IN COMMENT-STRIPPED CODE, and I found out by running this against
    /// the tree it was written for: `body` carries a COMMENT that says "…which is FOUR of the
    /// `effectSection(` calls below it", so the raw text counts ONE inline call and claim 1
    /// went RED on the correct tree. Same class as #926 (a scanner reading its own literal) and
    /// #932 (a needle that also matches the prose describing it) — third instance, and the
    /// cheapest to miss because the comment is TRUE and helpful.
    private func bodyText(of code: String) throws -> String {
        guard let start = code.range(of: "    var body: some View {") else {
            throw XCTSkip("`var body` is no longer spelled that way in \(Self.view) — re-anchor.")
        }
        let rest = code[start.upperBound...]
        // The next member of the struct starts a line with four spaces and a declaration word.
        for keyword in ["\n    @ViewBuilder", "\n    private var", "\n    private func", "\n    var "] {
            if let end = rest.range(of: keyword) {
                return String(rest[..<end.lowerBound])
            }
        }
        return String(rest)
    }

    // MARK: - 1: the fifteen rows are out of the body

    /// GRADING (#464): REGRESSION. On the parent tree this claim fails with 15 — that tree is
    /// exactly the 1827 ms measurement, so the claim's failure IS the defect it names.
    func testTheEffectRowsAreNotInlineInTheBody() throws {
        let body = try bodyText(of: SourceText.codeOnly(try source(Self.view)))
        let inline = body.components(separatedBy: "effectSection(").count - 1
        XCTAssertEqual(inline, 0, """
            \(inline) `effectSection(` call(s) are back inline in `EchoelFXView.body`.

            They were moved out by #936 because the `Form` had 21 direct children and the
            compiler reported the body at 1827 ms to type-check (limit 200 ms). Aggregate
            generic pressure in a SwiftUI body is the mechanism behind this repo's shipped
            black-screen SIGSEGV (CLAUDE.md, 10.76.34) — a slow type-check is the cheap symptom
            that arrives first.

            If the rows genuinely belong in the body again, say what changed about the builder
            or the measurement, and re-run the compile gate looking at the warning list — the
            verdict reader prints it (`python3 scripts/gh-test-verdict.py`, #933e).
            """)
    }

    // MARK: - 2: COUNTERWEIGHT — and they are still rendered

    /// ⭐ #343 — claim 1 alone is satisfied by DELETING the fifteen rows, which would remove
    /// half the FX panel and leave this file green. This is the claim that makes claim 1 mean
    /// "moved" rather than "gone".
    func testTheBodyStillRendersAllThreeGroups() throws {
        let code = SourceText.codeOnly(try source(Self.view))
        let body = try bodyText(of: code)
        for group in ["colourEffects", "voiceAndSpaceEffects", "modulationAndDynamicsEffects"] {
            XCTAssertTrue(body.contains(group), """
                `EchoelFXView.body` no longer renders `\(group)`.

                Claim 1 in this file is happy with an EMPTY body — this is the half that says
                the rows are still on screen. If the groups were renamed or merged, re-anchor
                here; if a group was deleted, the FX panel lost rows and that is the finding.
                """)
            XCTAssertTrue(code.contains("private var \(group): some View {"), """
                `\(group)` is referenced by the body but no longer declared. Either the
                declaration moved (re-anchor) or this file no longer compiles.
                """)
        }
        let total = code.components(separatedBy: "effectSection(\"").count - 1
        XCTAssertEqual(total, 15, """
            The FX panel declares \(total) effect rows, not the 15 that #936 moved.

            This is a FLOOR, not a style rule: adding a sixteenth effect is correct work and
            SHOULD turn this red once, so the number is re-stated deliberately rather than
            drifting. Removing one is the case worth reading twice — check it was a founder ask
            and not a casualty of a refactor.
            """)
    }
}
