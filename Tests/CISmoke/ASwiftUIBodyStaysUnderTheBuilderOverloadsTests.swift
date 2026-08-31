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
    private static let groups = ["effectRowsA", "effectRowsB", "effectRowsC"]

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
        // ⛔ #936b — A LOST ANCHOR IS RED, NOT SKIPPED. `source()` has already proven the tree
        // and the file exist, so a `var body` spelled differently is a re-anchor obligation, not
        // an environment problem (#454; #806: a skip is not a pass).
        //
        // ⚠️ THE ANCHOR IS POSITIONAL. There are SEVEN `var body: some View {` in this file and
        // `EchoelFXView`'s is the first only because its `struct` is at the top and every other
        // view struct starts 600 lines below. A helper struct inserted ABOVE it would silently
        // re-point this at the wrong body and claim 1 would go green on nothing — hence the
        // ordering check, which is cheap and states what it assumes.
        guard let structAt = code.range(of: "struct EchoelFXView: View {"),
              let start = code.range(of: "    var body: some View {") else {
            XCTFail("`struct EchoelFXView: View {` or its `var body: some View {` is no longer "
                    + "spelled that way in \(Self.view). Re-anchor this guard; do not delete it.")
            return ""
        }
        XCTAssertLessThan(structAt.lowerBound, start.lowerBound, """
            The first `var body: some View {` in \(Self.view) no longer belongs to
            `EchoelFXView` — a type was inserted above it. Every claim here would then measure
            the wrong body and pass on nothing. Anchor on the struct, not on the position.
            """)
        let rest = code[start.upperBound...]
        // ⛔ #936b — EARLIEST MATCH, NOT FIRST KEYWORD. The original loop returned on the first
        // keyword in the LIST that matched anywhere later, which is a different thing: on the
        // parent tree it stopped at `@ViewBuilder` and over-included `morphTargets` and its MARK.
        // Harmless there, and exactly the silent over-reach a later edit turns into a wrong
        // answer. It also means my own local check — which took the minimum — was NOT testing
        // the shipped logic. That divergence is why the reviewer found this and I did not.
        //
        // ⛔ AND A `"\n    // MARK:"` TERMINATOR WAS IN THIS LIST FOR ONE DRAFT AND WAS DEAD BY
        // CONSTRUCTION: callers hand in `SourceText.codeOnly` output, which BLANKS comments while
        // preserving line count, so no `// MARK:` can survive to be matched. `dead-needles.py`
        // could not see it — it lives inside a Swift array literal, not at a call site. Removed
        // rather than left as decoration: a needle that cannot match is a claim that cannot fail.
        let ends = ["\n    @ViewBuilder", "\n    private var", "\n    private func", "\n    var "]
            .compactMap { rest.range(of: $0)?.lowerBound }
        guard let end = ends.min() else { return String(rest) }
        return String(rest[..<end])
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
        for group in Self.groups {
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
        // ⛔ #936b — THIS WAS `XCTAssertEqual(total, 15)` UNDER A MESSAGE THAT CALLED ITSELF "a
        // FLOOR, not a style rule". The check and its own explanation disagreed, and the
        // explanation was the honest half: adding a sixteenth effect is correct work and must
        // not go red (#364), while LOSING one is the case worth reading twice.
        XCTAssertGreaterThanOrEqual(total, 15, """
            The FX panel declares \(total) effect rows, fewer than the 15 that #936 moved.

            A row disappeared. Check it was a founder ask and not a casualty of a refactor —
            claim 1 in this file is satisfied by an EMPTY body, so nothing else here notices.
            Adding rows is fine and deliberately does not redden this.
            """)
    }

    // MARK: - 3: the law the class NAME states — no ONE block is wide again

    /// ⛔ #936b — THE REVIEWER'S SHARPEST FINDING. Claims 1 and 2 BOTH stay green if all fifteen
    /// rows are moved into ONE group and the other two become `EmptyView()` stubs. That is the
    /// exact >10 condition #936 exists to remove, reconstructed, with the guard silent — and the
    /// class is NAMED for the law it could not see. Location was pinned; WIDTH was not.
    ///
    /// ⚠️ TEN IS THE BUILDER'S NUMBER, NOT A CRASH THRESHOLD. Nothing here measured where a
    /// SwiftUI body actually breaks; `ViewBuilder`'s fixed `buildBlock` overloads simply stop at
    /// ten and the variadic pack takes over past that. Going red at eleven is the point — that
    /// is a day a human should look, not a day correct work is blocked (#364).
    func testNoSingleBlockHoldsMoreRowsThanTheBuilderHasOverloads() throws {
        let code = SourceText.codeOnly(try source(Self.view))
        for group in Self.groups {
            guard let at = code.range(of: "    private var \(group): some View {") else {
                XCTFail("`\(group)` is gone — claim 2 says what to do; this claim needs it to "
                        + "measure a width at all.")
                return
            }
            let rest = code[at.upperBound...]
            guard let end = rest.range(of: "\n    }") else {
                XCTFail("`\(group)` has no closing `    }` — the file does not compile, or the "
                        + "indentation this scan assumes has changed. Re-anchor.")
                return
            }
            let rows = rest[..<end.lowerBound].components(separatedBy: "effectSection(").count - 1
            XCTAssertLessThanOrEqual(rows, 10, """
                `\(group)` holds \(rows) effect rows. `ViewBuilder`'s fixed `buildBlock`
                overloads stop at TEN; past that the compiler resolves the block through the
                variadic generic pack and re-infers one enormous aggregate type — the whole
                reason #936 split these out of `body` (1827 ms to type-check, limit 200 ms).

                Moving rows between the three groups is fine. Piling eleven into one is the
                defect returning through a different door: split into a fourth group and name it
                in `body`, which has room (nine children, same ten-overload cliff).
                """)
        }
    }
}
