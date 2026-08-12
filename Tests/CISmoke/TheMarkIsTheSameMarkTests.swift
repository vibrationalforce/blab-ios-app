// TheMarkIsTheSameMarkTests.swift
// Echoel — #536. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ THE ASK, founder 2026-08-12: *"Website Design CI und APP übereinstimmend? E links oben
// könnte gefühlt größer aber schau selbst"* — is the corporate identity of the site and the app
// the same thing, and the mark top-left could carry more presence.
//
// Measured before anything was changed, and the second half of the answer is the interesting
// one. The PALETTE agrees exactly (`--bg #000` ↔ `Color.black`; `--text #e0e0e0` ↔
// `Color(0.878, 0.878, 0.878)`, and 0.878 × 255 = 223.89 → 224 = 0xE0). The TYPEFACE agrees —
// both ship Atkinson Hyperlegible, the site as `docs/fonts/*.woff2`, the app as
// `Resources/Fonts/*.ttf` + `UIAppFonts`. The RADIUS agrees (8). The three echo waves of the
// mark agree coordinate for coordinate with `docs/favicon.svg`. And the PROPORTION agreed too:
// the site's nav sets the mark to 28 px in a 64 px bar (43.8 %), the app's `topBar` is ~50 pt
// and had 22 pt (44 %).
//
// ⛔ THE ONE THING THAT DID NOT AGREE WAS THE LETTER THE MARK IS BUILT AROUND. Every published
// copy — `docs/favicon.svg`, `docs/app-icon.svg`, `docs/logo-horizontal.svg`,
// `docs/logo-stacked.svg`, the inline nav `<svg>` in `docs/index.html` — sets
// `font-family="'Atkinson Hyperlegible',…"`. `EchoelLogoMark` drew it with
// `.system(size: 52 * s, weight: .bold)`, i.e. SF Pro. The waves around it were mirrored from
// the SVG exactly; the `E` was a different letterform in a mark whose own file header claims it
// "reproduces the app icon / website logo". That is a CI defect independent of any size, and it
// is corrected in the same commit. The size went 22 → 26 pt as well, which is the founder's
// judgement call and is NOT pinned here — freezing a design size makes ordinary design work red,
// and that is how a guard gets deleted (#364).
//
// ⚠️ WHAT THIS FILE CAN AND CANNOT DO, said before the assertions rather than after. It reads
// files as text and compares numbers. It does not render the mark, does not rasterise a glyph,
// and therefore CANNOT show that the `E` now looks right, that 26 pt reads as "bigger", or that
// Atkinson's `E` fills the 100-unit box more than SF Pro's did. Those are one look on the
// device and they stay open. What it proves is narrower and durable: the app's mark and the
// published mark describe the SAME GEOMETRY, and the letter inside it is named from the same
// bundled family the site declares.
//
// ⚠️ AND THE GEOMETRY CHECK IS DELIBERATELY AGAINST `docs/favicon.svg`, NOT `docs/app-icon.svg`.
// The favicon and the inline nav mark use the same 100-unit viewBox the Swift mirrors, so the
// numbers are identical and a mismatch is a real mismatch. `app-icon.svg` is a 1024-unit
// redraw with rounded control points (245 where 24 × 10.24 = 245.76), so comparing against it
// would need a tolerance — and a tolerance is exactly where a drift hides.
//
// ⚠️ HONEST GRADING (#433), transcribed and DRIVEN against both trees rather than asserted —
// this file reads text only and names no new symbol, so unlike #464 it compiles against the
// parent and every needle really has a verdict there. Of **20** needles, exactly **THREE** are
// REGRESSIONS, all in `EchoelLogoMark`: `EchoelTheme.faceName(.bold)` present, `.system(`
// absent, `fixedSize:` present. The other seventeen are COUNTERWEIGHTS, green on both trees —
// and they are the content (#343): the geometry, the palette and the family all agreed BEFORE
// this slice and the point is that they keep agreeing while the letterform moves.
//
// ⛔ AND THE FIRST VERSION OF THIS PARAGRAPH GOT ITS OWN GRADE WRONG IN THE FLATTERING
// DIRECTION — the exact #433 defect, in the paragraph headed "honest grading". It booked TWO
// further needles as regressions. (a) `EchoelTheme.font(` absent is green on the parent too:
// the mark never called that helper, it called `.system(`. (b) The single-definition check was
// claimed red "because the bold literal appeared twice, once per switch arm". Measured: the
// parent spells it **once**, in a local `var face` switch inside `font(_:_:)`, and the count is
// over FILES anyway — it was 1 before and is 1 now. It is a forward guard against a SECOND FILE
// re-spelling the face, which is a live risk only now that there are two callers. Worth keeping,
// not worth claiming credit for. ⚠️ Its honest limit, stated rather than discovered later: it
// counts files, so a second spelling INSIDE `EchoelTheme.swift` would not redden it.
//
// ⚠️ `SourceText.codeOnly` is TRAGEND here, and it is MEASURED, not assumed (three slices in a
// row had to retract that word): **2 of 8** raw-vs-stripped needle verdicts flip, both on this
// tree, and both are negative needles that collide with this slice's own retraction comment —
// `.system(` (quoted in the ⛔ block that explains what was removed) and `EchoelTheme.font(`
// (quoted in the ⚠️ block that explains why the tempting tidy is the bug). A raw-text scan
// would be red on CORRECT code, twice. The #486/#491 collision again: this repo writes down
// what it removed.

import Foundation
import XCTest

final class TheMarkIsTheSameMarkTests: XCTestCase {

    private static let mark  = "Sources/Echoelmusic/Studio/EchoelLogoMark.swift"
    private static let theme = "Sources/Echoelmusic/Studio/EchoelTheme.swift"
    private static let icon  = "docs/favicon.svg"
    private static let css   = "docs/shared.css"

    // MARK: - REGRESSIONS

    func testTheMarkDrawsItsLetterInTheBrandFace() throws {
        let code = SourceText.codeOnly(try source(Self.mark))

        XCTAssertTrue(code.contains("EchoelTheme.faceName(.bold)"), """
            `EchoelLogoMark` must name the BUNDLED brand face for its `E`. Every published copy \
            of this mark sets `font-family="'Atkinson Hyperlegible',…"` \
            (`docs/favicon.svg`, `docs/app-icon.svg`, `docs/logo-horizontal.svg`, \
            `docs/logo-stacked.svg`, and the inline nav <svg> in `docs/index.html`). Drawing the \
            letter in a different typeface makes the one part of the mark that is not a \
            reproduction the letter the mark is built around.
            """)

        XCTAssertFalse(code.contains(".system("), """
            `EchoelLogoMark` must not fall back to the system face. This is the defect #536 \
            fixed: the waves were mirrored from the SVG coordinate for coordinate and the `E` \
            was SF Pro.
            """)
    }

    /// ⚠️ MIXED, and graded needle by needle rather than by method: `fixedSize:` is a REGRESSION
    /// (absent on the parent); `EchoelTheme.font(` absent is a COUNTERWEIGHT (the mark never
    /// called that helper — it called `.system(`). The counterweight is the durable half: it
    /// reddens the tempting later tidy of "just use the theme helper".
    func testTheCanvasGlyphDoesNotScaleWithDynamicType() throws {
        let code = SourceText.codeOnly(try source(Self.mark))

        XCTAssertTrue(code.contains("fixedSize:"), """
            The `E` must be drawn with `.custom(_:fixedSize:)`. This `Canvas` derives every \
            coordinate from `s`, a hard ratio against the `.frame(width:height:)` the call site \
            pins — a Dynamic-Type-relative font would grow while the box did not, and the letter \
            would overrun the three waves at accessibility text sizes.
            """)

        XCTAssertFalse(code.contains("EchoelTheme.font("), """
            Do NOT point the mark at `EchoelTheme.font(_:_:)`. It returns \
            `relativeTo: .body` on purpose — that is right for every laid-out label in the app \
            and wrong inside this fixed-ratio canvas. The face lookup is shared \
            (`EchoelTheme.faceName`); the scaling behaviour deliberately is not.
            """)
    }

    // MARK: - COUNTERWEIGHTS (green on both trees — these are the content)

    /// ⚠️ A FORWARD guard, not a regression: the parent already spelled the bold face exactly
    /// once (in a local `var face` switch inside `font(_:_:)`), so this was green there too. It
    /// earns its place because #536 created the risk it covers — a SECOND caller with opposite
    /// Dynamic-Type needs, and therefore a standing temptation to type the face name again at
    /// the second call site instead of asking `faceName(_:)`.
    func testThereIsOneDefinitionOfTheBoldFace() throws {
        var files: [String] = []
        let root = try repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            return XCTFail("Could not walk `Sources/`.")
        }
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            let text = try String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
            if SourceText.codeOnly(text).contains("\"AtkinsonHyperlegible-Bold\"") {
                files.append("Sources/" + rel)
            }
        }

        XCTAssertEqual(files.count, 1, """
            The bold face name must be spelled in exactly ONE place (#416) — \
            `EchoelTheme.faceName(_:)` — because there are now two callers with opposite \
            Dynamic-Type needs and the face name is the only thing they share. Found in: \
            \(files.isEmpty ? "nowhere" : files.joined(separator: ", ")).
            """)
    }

    /// The three echo waves the app draws are the three the site publishes.
    ///
    /// Both are read out of their own file; nothing here restates a coordinate, because a guard
    /// that carries its own copy of the thing it guards is a third copy waiting to go stale
    /// (the `AutoGainClampMatchesTheWebsiteTests` lesson).
    func testTheWavesAreTheSameWaves() throws {
        let svg = try source(Self.icon)
        let code = SourceText.codeOnly(try source(Self.mark))

        let paths = Self.pathData(in: svg)
        XCTAssertEqual(paths.count, 3, """
            `docs/favicon.svg` must carry exactly three wave paths — found \(paths.count). \
            If the published mark changed, the app's `EchoelLogoMark` has to change with it.
            """)
        guard paths.count == 3 else { return }

        // Each published path is a plain vertical offset of the first — and the offsets are the
        // ones the Swift `for (dy, op) in [...]` table declares, not a set typed in here.
        let table = Self.numbers(in: Self.slice(code, from: "for (dy, op) in [", to: "]"))
        XCTAssertEqual(table.count, 6, """
            Expected three (dy, opacity) pairs in `EchoelLogoMark`, parsed \(table.count) \
            numbers. If that literal became an expression, this guard cannot read it — rewrite \
            the guard, do not delete it.
            """)
        guard table.count == 6 else { return }

        let offsets   = [table[0], table[2], table[4]]
        let opacities = [table[1], table[3], table[5]]
        let base = Self.numbers(in: paths[0])

        XCTAssertEqual(base.count, 20, """
            The published wave is expected to be one move plus three cubic curves \
            (20 alternating x,y numbers) — parsed \(base.count).
            """)
        guard base.count == 20 else { return }

        for (i, dy) in offsets.enumerated() {
            let expected = base.enumerated().map { $0.offset % 2 == 1 ? $0.element + dy : $0.element }
            XCTAssertEqual(Self.numbers(in: paths[i]), expected, """
                Wave \(i + 1) of `docs/favicon.svg` is not the first wave offset by the \(dy) the \
                app applies. The site and the app would draw different marks.
                """)
        }

        XCTAssertEqual(Self.opacities(in: svg), opacities, """
            The published wave opacities and the app's `(dy, op)` table disagree. Both describe \
            the same three-wave fade; one of them was edited alone.
            """)

        // Stroke width lives in the SVG's `<g>` and in the Swift's `StrokeStyle`.
        let strokeSVG = Self.numbers(in: Self.slice(svg, from: "stroke-width=\"", to: "\""))
        let strokeApp = Self.numbers(in: Self.slice(code, from: "lineWidth:", to: "* s"))
        XCTAssertEqual(strokeSVG, strokeApp, """
            Stroke width disagrees: the site draws \(strokeSVG), the app draws \(strokeApp) in \
            the same 100-unit box.
            """)
    }

    /// The one ink colour of the identity, stated as a hex on the site and as a component in the
    /// app. `--text: #e0e0e0` ↔ `textComponent = 0.878`, and 0.878 × 255 = 223.89 → 224 = 0xE0.
    func testTheInkIsTheSameGrey() throws {
        let css = try source(Self.css)
        let theme = SourceText.codeOnly(try source(Self.theme))

        let hex = Self.slice(css, from: "--text: #", to: ";")
            .trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(hex.count, 6, "Expected `--text: #rrggbb` in `docs/shared.css`, got '\(hex)'.")
        guard hex.count == 6, let channel = Int(hex.prefix(2), radix: 16) else { return }

        let component = Self.numbers(in: Self.slice(theme, from: "textComponent: Double", to: "\n"))
        XCTAssertEqual(component.count, 1, """
            Expected one number for `EchoelTheme.textComponent`, parsed \(component.count).
            """)
        guard let value = component.first else { return }

        XCTAssertEqual(Int((value * 255).rounded()), channel, """
            The app's ink and the site's ink are different greys: the app rounds to \
            \(Int((value * 255).rounded())), the site publishes \(channel) (#\(hex)). One \
            palette, two files — they must agree.
            """)
        XCTAssertTrue(css.contains("--bg: #000"), "The site's ground must stay pure black.")
        XCTAssertTrue(theme.contains("Color.black"), "The app's ground must stay pure black.")
    }

    func testBothSidesDeclareTheSameTypeface() throws {
        let css = try source(Self.css)
        let theme = SourceText.codeOnly(try source(Self.theme))

        XCTAssertTrue(css.contains("'Atkinson Hyperlegible'"), """
            `docs/shared.css` must lead its `--font` stack with Atkinson Hyperlegible — the \
            accessibility-first face the whole identity is built on.
            """)
        XCTAssertTrue(theme.contains("\"Atkinson Hyperlegible\""), """
            `EchoelTheme.fontFamily` must name the same family the site declares. The app \
            bundles it (`Resources/Fonts` + `UIAppFonts`); this is the string that says the two \
            are the same identity and not two lookalikes.
            """)
    }

    // MARK: - Reading helpers

    /// Numbers in `text`, ignoring digits that are part of an identifier.
    ///
    /// `control1:` / `control2:` in the Swift and `M` / `C` in the SVG path data are the two
    /// shapes that would otherwise poison this: the first would contribute a stray 1 and 2, the
    /// second sits flush against its first coordinate (`M24,60`). Identifier digits are dropped
    /// by looking at the preceding character; command letters are single and are dropped the
    /// same way only when they precede a digit — which is why the SVG's letters must be
    /// separated first. See `pathData(in:)`.
    private static func numbers(in text: String) -> [Double] {
        var out: [Double] = []
        var current = ""
        var previousWasLetter = false

        for ch in text {
            let isDigit = ch.isNumber || ch == "."
            if isDigit && !(current.isEmpty && previousWasLetter) {
                current.append(ch)
            } else {
                if let v = Double(current) { out.append(v) }
                current = ""
            }
            previousWasLetter = ch.isLetter || ch == "_"
        }
        if let v = Double(current) { out.append(v) }
        return out
    }

    /// The three `d="…"` payloads, with the SVG path commands replaced by spaces so a coordinate
    /// flush against `M` is still read as a coordinate.
    private static func pathData(in svg: String) -> [String] {
        var out: [String] = []
        var rest = Substring(svg)
        while let open = rest.range(of: "d=\"") {
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "\"") else { break }
            let raw = String(after[..<close.lowerBound])
            out.append(raw.map { $0.isLetter ? " " : $0 }.reduce(into: "") { $0.append($1) })
            rest = after[close.upperBound...]
        }
        return out
    }

    private static func opacities(in svg: String) -> [Double] {
        var out: [Double] = []
        var rest = Substring(svg)
        while let open = rest.range(of: "opacity=\"") {
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "\"") else { break }
            if let v = Double(after[..<close.lowerBound]) { out.append(v) }
            rest = after[close.upperBound...]
        }
        return out
    }

    /// The text strictly between the first `from` and the next `to` after it, or "" if either
    /// anchor is missing — an absent anchor then fails the assertion that uses it, rather than
    /// silently matching (#367).
    private static func slice(_ text: String, from: String, to: String) -> String {
        guard let open = text.range(of: from) else { return "" }
        let after = text[open.upperBound...]
        guard let close = after.range(of: to) else { return "" }
        return String(after[..<close.lowerBound])
    }

    private func repoRoot() throws -> URL {
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
        return root
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: try repoRoot().appendingPathComponent(path), encoding: .utf8)
    }
}
