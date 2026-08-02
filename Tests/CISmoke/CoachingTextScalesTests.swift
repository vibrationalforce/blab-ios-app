// CoachingTextScalesTests.swift
// Echoel — the line that tells you what to do must obey Larger Text. #353d.
//
// WHAT THIS GUARDS. `BioStripView.banner(_:color:systemImage:)` renders the strip's ONLY
// instruction. It has exactly three call sites and therefore three possible texts: the camera
// recovery/cooling/interruption hint, `PulseCue.cameraDenied.fullHint` ("Camera access is off
// — enable it in Settings to read your pulse"), and "Pulse detected — you can let go & play".
// (⛔ This paragraph listed "Cover the camera and flash" for a commit, a string that appears
// NOWHERE in `Sources/`. The real wording is `PulseCue.coverLens.fullHint` = "Cover the rear
// camera + flash", rendered by `HeaderMonitors`, not by this banner. The list matters because
// it is a claim about how LONG the longest sentence is — the thing a reader checks before
// deciding whether wrapping is safe. Same correction landed in `BioStripView.swift`.)
// It was set with `.font(.system(size: 11, weight: .medium))`, which is an
// absolute point size: it does not participate in Dynamic Type at all. A user at AX5 read the
// app's coaching at 11 pt. (⛔ This said "`.system(size:)` WITHOUT `relativeTo:`", which sends
// a reader hunting for a parameter that does not exist — `Font.system(size:weight:design:)`
// has no such argument. `relativeTo:` lives only on `Font.custom(_:size:relativeTo:)`, i.e.
// the fix is to change FAMILY, not to add an argument.)
//
// ⭐ THE DISTINCTION THAT DECIDED THE SLICE, and it corrects a claim I had already filed.
// The strip below this banner carries `.minimumScaleFactor(0.6)`, which looks like the same
// defect and is NOT one: a scale factor is a fraction of the CURRENT size, so at AX3 those
// numbers still render larger than the default-size ones — the requested increase is capped,
// not cancelled. #353c had it written down as "shrinks the numbers when the user asks for
// bigger text", which is false, and it is corrected there. This banner is the genuinely
// binary case: absolute means absolute.
//
// ⚠️ THE WEIGHT WAS DROPPED ON PURPOSE, and it IS a visible de-emphasis: SF-Medium-11 →
// Atkinson-Regular-11, real strokes lost. The brand family ships Regular, Bold and Italic
// only, so the honest choices were Regular or `.semibold` (the Bold face); Regular is chosen
// because the semantic colour and the icon already carry the emphasis, and because the line
// now GROWS with the reader's setting, which buys back far more legibility than a weight
// step. A future reader must not "restore" `.medium` — it is not on the menu whatever it
// looked like before. If a device look wants more weight, `.semibold` is the one alternative.
//
// ⛔ THIS PARAGRAPH ARGUED THE OPPOSITE FOR ONE COMMIT, and the refutation was three lines
// above the helper it cited. It said the drop was render-neutral because `EchoelTheme.font(11,
// .medium)` resolves to Regular anyway — the 62-site #361 defect. But the OLD spelling was
// `.system(size: 11, weight: .medium)`, and `EchoelTheme.font`'s own doc says in bold:
// "`.font(.system(size:weight: .medium))` IS NOT THIS BUG … SF ships a real medium and
// renders it … do not conflate the two." The source comment was corrected first; this header
// kept the refuted version for a commit, which is the same defect one file over.
//
// ⚠️ WHY THIS WAS SAFE WITHOUT A LAYOUT REDESIGN, and the load-bearing modifier is
// `.fixedSize(horizontal: false, vertical: true)` on the `Text` — NOT, as this paragraph
// first claimed, the mere absence of a `lineLimit`. A `Text` beside a `Spacer` in an `HStack`
// can settle on one truncated line; `fixedSize` is what makes wrapping deterministic, and it
// is what every other multi-line banner in this design system carries. The absence of a
// `lineLimit` is still necessary and still asserted, but it was never sufficient, and the
// banner had no `fixedSize` at all until the #353d Nachlese put one there.
//
// ⚠️ HONEST LIMITS. Source-text scan, no simulator: it proves the font is still SPELLED as
// the scaling one, never that a sentence wraps legibly at AX5 (NEEDS-FOUNDER-VERIFY: Larger
// Text at AX3+, open Bio, cover the camera, read the amber line). And it pins ONE banner:
// `.font(.system(size:` remains in many other places under `Sources/`, most of them icon
// glyphs where the judgement is genuinely different — a symbol inside a deliberately-sized
// frame can burst it. Each needs its own look, which is why this is not a sweep. The class
// is filed as #353d, which carries the counting command — a comment-STRIPPING one, because a
// naive `git grep -rn … Sources/` counts PROSE: two of its hits are comment lines that quote
// the spelling in order to warn against it (`EchoelTheme.swift:200` and the rationale block in
// `BioStripView.swift` that this slice wrote). A sweep that follows them "fixes" a warning.
// The gap is not rounding — one of those files has ONLY the prose hit, so the naive file count
// is over by one too. (This test file has four such quotes of its own; they never counted,
// because the command scopes `Sources/` and this lives under `Tests/`.)
//
// ⛔ NO COUNT IS QUOTED HERE, and the reason is that the first draft quoted one and it was
// WRONG WHEN COMMITTED. It said "still occurs 97 times across 25 files" — 97 was the figure
// BEFORE this slice, and this slice removes two of them. A count written into the same commit
// that changes it is stale on arrival. That is the third time in two cycles (see the ⛔ about
// "twelve comment lines" in `ChipLabelGrowsWithTheTextTests`), so the rule here is stronger
// than "re-count": a prose count next to work that moves it does not earn its place at all.
// The command lives in #353d, where it can be re-run.
//
// ⛔ TWO OF THE THREE TESTS GO RED ON THE PRE-FIX SOURCE — and this paragraph said ONE for a
// commit, in the one place whose whole job is not to over- or under-claim a guard's reach.
// `testTheBannerUsesAScalingFont` fails both ways it can (two `.system(size:)` lines present,
// zero `EchoelTheme.font` calls). `testTheBannerWraps` fails too, because `BioStripView` had
// ZERO occurrences of `.fixedSize` — not only before #353d but also at `1a9880f`, the commit
// that shipped the font change without it. So that assertion caught a real gap in already-
// pushed code, which is exactly what it is for. Only the weight test —
// `testTheBannerDoesNotAskForAWeightTheAppLacks` — was green before and stays green: a pure
// consistency pin. (Written on one line on purpose: this file already documents, forty lines
// down, that splitting an identifier across a line break makes it invisible to the `git grep`
// this repo reviews citations with, and then did it here anyway for a commit.)
//
// The under-claim happened because the Nachlese rewrote the test BODY and the source comment
// and left this header alone. Same lesson as the ⛔ above, in the same file, one paragraph
// apart: correcting a claim in one file does not correct its copy in another.
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
            An absolute `.system(size:)` does not scale with Dynamic Type at all, and this \
            banner is where the app says "Camera access is off — enable it in Settings to \
            read your pulse" and reports a camera recovery — the instructions a user with \
            impaired sight most needs to read. \
            Use `EchoelTheme.font(_:)`, which is `.custom(…, relativeTo: .body)`.
            """)

        // ⛔ COUNTS OCCURRENCES, NOT LINES. The first version filtered lines containing the
        // token, so writing the icon the way `EchoelNumberPad` writes it —
        // `Image(systemName: x).font(EchoelTheme.font(10))` on ONE line — would have dropped
        // the count to 1 and failed with a message accusing the banner of losing a font it
        // still had. A guard whose failure text is wrong is worse than a missing guard.
        let scaling = banner.joined(separator: "\n")
            .components(separatedBy: "EchoelTheme.font(").count - 1
        XCTAssertEqual(scaling, 2, """
            Expected exactly two `EchoelTheme.font(...)` calls in the banner (the icon and \
            the text), found \(scaling). Both must scale together: an SF Symbol pinned \
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

    /// The property the fix depends on: this text really does wrap.
    ///
    /// ⛔ THE FIRST VERSION OF THIS TEST ASSERTED ONLY THE ABSENCE OF A `lineLimit`, WHICH WAS
    /// ALREADY TRUE BEFORE THE SLICE AND WOULD HAVE STAYED TRUE THROUGH THE FAILURE IT CLAIMED
    /// TO GUARD. Absence of a cap is not presence of a wrap: a `Text` beside a `Spacer` in an
    /// `HStack` is exactly the shape where SwiftUI can settle on one truncated line, and the
    /// house answer is `.fixedSize(horizontal: false, vertical: true)` — which every other
    /// multi-line banner in this design system carries and `BioStripView` carried nowhere.
    /// So the guard now pins BOTH halves: nothing caps the line count, AND the modifier that
    /// makes wrapping deterministic is present. An assertion that cannot fail is worse than no
    /// assertion, because it reports a green nobody earned.
    ///
    /// ⚠️ ONE HONEST CAVEAT ABOUT THE PRECEDENT CITED IN THE FAILURE MESSAGE BELOW.
    /// `nonStandardTuningBanner` is the house build this copies — same icon + `Text` + `Spacer`
    /// in an `HStack`, same `.fixedSize(horizontal: false, vertical: true)` — but it is itself
    /// UNPRESENTED today (open task #325: it renders only for a non-standard tuning, and the
    /// path that would show one has no door). So it is a precedent for the CODE SHAPE, which is
    /// what is being copied, and not evidence that anyone has watched this shape wrap on a
    /// device. That evidence is the founder verify this slice is waiting on, and citing an
    /// unseen sibling as if it were proof is exactly the kind of borrowed confidence this file
    /// keeps correcting elsewhere.
    func testTheBannerWraps() throws {
        let source = try codeLines(Self.strip)
        let banner = try bannerWindow(source)

        XCTAssertTrue(banner.contains { $0.contains("fixedSize(horizontal: false, vertical: true)") }, """
            The bio strip's banner lost `.fixedSize(horizontal: false, vertical: true)`. That \
            modifier is what makes the coaching line WRAP rather than truncate once Dynamic \
            Type grows it: it tells SwiftUI to take the text's ideal HEIGHT while accepting the \
            offered width, which an `HStack` with a `Spacer` will not do on its own. Removing \
            it converts the whole point of #353d — "the instruction gets bigger" — into "the \
            instruction gets cut off", which is worse than the fixed 11 pt it replaced, because \
            at 11 pt the sentence at least fit. `nonStandardTuningBanner` in `EchoelStudioView` \
            is the same icon + text + Spacer build and carries the same modifier.
            """)

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

    /// Lines from `declaration` to the closing brace at the declaration's own indentation.
    ///
    /// ⛔ NOT BY A LINE COUNT, WHICH WAS THE FIRST THING RULED OUT — the lesson
    /// `ChipLabelGrowsWithTheTextTests` paid for one slice earlier, applied from the start
    /// here. This slice puts a long rationale block directly above the banner and then GREW it
    /// twice in review; any count anchored below it would have been wrong before it was ever
    /// committed. (⛔ The first version of this very sentence said "a 20-line rationale block"
    /// and it was 26 at that commit and 39 now — a self-referential count inside the paragraph
    /// arguing that counts rot. The identifier above was also split across two lines, which
    /// makes it invisible to the `git grep` this repo reviews citations with.)
    ///
    /// ⛔ AND THE REPLACEMENT, "STOP AT THE NEXT MEMBER", WAS SPELLED AS A NAMING
    /// CONVENTION for one commit — `private var ` or
    /// `private func ` — which is a guess about what the AUTHOR of the NEXT declaration will
    /// type, not a fact about this one. `fileprivate var`, `static func`, `private let`, or an
    /// attribute pushed onto its own line all miss, and the window then runs on: past `banner`
    /// it would swallow `infoButton`, whose `.font(.system(size: 12))` is a legitimate icon
    /// size, and the failure text would accuse the banner of a line that is not the banner's.
    /// A guard that can go red for a change in a NEIGHBOUR is worse than one that misses,
    /// because the message points at the wrong file region. The boundary is now STRUCTURAL:
    /// the closing brace sitting at exactly the declaration's own indentation, which does not
    /// care what comes next or how it is spelled.
    ///
    /// ⚠️ Accepted limit, stated so nobody discovers it as a surprise: a multi-line string
    /// literal containing a line that is exactly that indentation plus `}` would end the window
    /// early. Neither member inspected here contains a string literal at all; if one grows one,
    /// this helper needs a real brace scanner, not a wider regex.
    private func window(_ source: [String], from declaration: String) throws -> ArraySlice<String> {
        guard let start = source.firstIndex(where: { $0.contains(declaration) }) else {
            throw XCTSkip("""
                `\(declaration)` is gone from BioStripView — if the banner was restructured \
                this test should be rewritten with it, not left to pass vacuously
                """)
        }
        let indent = String(source[start].prefix { $0 == " " })
        let closer = indent + "}"
        guard let end = source[start...].dropFirst().firstIndex(where: {
            $0.hasPrefix(closer) && $0.trimmingCharacters(in: .whitespaces) == "}"
        }) else {
            throw XCTSkip("""
                `\(declaration)` in BioStripView has no closing brace at its own indentation — \
                the file was reformatted or the member was restructured, and reading on would \
                inspect the wrong lines. Rewrite this guard with the new shape rather than \
                letting it report on a window it cannot delimit
                """)
        }
        return source[start...end]
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
