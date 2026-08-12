// TypeWeightsThatExistTests.swift
// Echoel — a font weight the app does not ship is not a lighter bold, it is nothing.
//
// WHAT THIS GUARDS (#361). `EchoelTheme.font(_:_:)` takes a `Font.Weight`, which offers nine
// values, and resolves it to one of TWO bundled faces: four of them pick
// `AtkinsonHyperlegible-Bold`, everything else picks `-Regular`. A custom font does not
// synthesize an intermediate weight from a family — the face must be named — and this app
// bundles exactly three files (Regular, Bold, Italic; `Resources/iOS/Info.plist` `UIAppFonts`).
//
// So `EchoelTheme.font(13, .medium)` was byte-identical to `EchoelTheme.font(13)`. 62 call
// sites wrote it. Every one was a design intention — a row label meant to sit a step above
// its value, a chip meant to read a touch firmer — that never reached a screen, often with a
// real `.semibold` sibling two lines away in the same file. It is the least visible kind of
// defect: there is nothing to notice, because the difference the source asked for is simply
// absent, and the code reads as though the decision was made.
//
// ⛔ ONE SITE ALREADY CARRIED THE FULL EXPLANATION. A comment in `EchoelStudioView` spelled
// out that "the app ships Regular, Bold and Italic only, so `font(10, .medium)` rendered as
// Regular" — written while fixing ONE row, next to 21 more in the same file. Diagnosing a
// class and repairing an instance is how a known defect survives for weeks; that is the
// second time this week (see `AnalysisViewsSpeakTheirNumbersTests`), so the rule is now the
// guard rather than the comment.
//
// ⚠️ `.font(.system(size:weight: .medium))` IS A DIFFERENT THING and is deliberately NOT
// caught here: SF ships a real medium and renders it. Those sites have their own question
// (why the system face instead of the brand one), and folding the two together would turn a
// precise finding into a sweep — the mistake #364 made an hour earlier.
//
// ⚠️ Source-text scan, no simulator; `Tests/CISmoke` is the blocking bundle. A green means
// no call site ASKS for a face the app cannot draw. It cannot tell you the typography is
// good — that is a device look.

import Foundation
import XCTest

final class TypeWeightsThatExistTests: XCTestCase {

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }

    private func swiftFiles() throws -> [(name: String, lines: [String])] {
        let sources = try repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: sources.path) else { return [] }
        var out: [(name: String, lines: [String])] = []
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            let text = try String(contentsOf: sources.appendingPathComponent(rel), encoding: .utf8)
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            out.append((rel, lines))
        }
        return out
    }

    /// The weights that resolve to `-Regular`, i.e. that the brand font cannot distinguish
    /// from writing no weight at all. `.regular` itself is excluded on purpose: spelling it
    /// is honest, and the one ternary that survives (`isOn ? .semibold : .regular`) needs it
    /// to state the contrast between its two branches.
    private static let indistinguishable = ["ultraLight", "thin", "light", "medium"]

    func testNoCallSiteAsksTheBrandFontForAFaceItDoesNotShip() throws {
        var offenders: [String] = []
        for file in try swiftFiles() {
            for line in file.lines where line.contains("EchoelTheme.font(") {
                for weight in Self.indistinguishable where line.contains(".\(weight))") {
                    offenders.append("\(file.name): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) call site(s) ask `EchoelTheme.font` for a weight the bundled \
            family cannot draw, so they render exactly as if no weight were given: \
            \(offenders.prefix(4).joined(separator: " | ")). Either drop the weight (the \
            honest spelling of what happens) or add the real face to \
            `Resources/iOS/Info.plist` + `Resources/Fonts` first — that plist is \
            founder-gated, so it is a decision, not a tidy-up.
            """)
    }

    /// The scan has to actually look at the app. A walker that yields nothing would report a
    /// perfect green over an empty list — the silent-pass failure this repo has paid for.
    func testTheScanReachesTheSourcesItClaimsToCover() throws {
        let files = try swiftFiles()
        XCTAssertGreaterThan(files.count, 200, """
            Only \(files.count) Swift files were walked under Sources/. The tree holds well \
            over three hundred; a truncated walk makes every assertion above vacuous.
            """)
        let users = files.filter { f in f.lines.contains { $0.contains("EchoelTheme.font(") } }
        XCTAssertGreaterThan(users.count, 20, """
            Only \(users.count) files call `EchoelTheme.font`. It is the app-wide type ramp; \
            a number this low means the call was renamed and this guard is now watching a \
            spelling nobody uses.
            """)
    }

    // MARK: - The two faces, and the bundle that has to contain them

    func testTheMappingStillFoldsExactlyTheHeavyWeightsOntoBold() throws {
        let theme = try String(
            contentsOf: repoRoot().appendingPathComponent(
                "Sources/Echoelmusic/Studio/EchoelTheme.swift"), encoding: .utf8)
        // ⛔ THE NEEDLE WAS `: face = "AtkinsonHyperlegible-Bold"` AND #536 MOVED IT. The switch
        // was hoisted out of `font(_:_:)` into `EchoelTheme.faceName(_:)` — same arms, same two
        // faces, but a `return` instead of an assignment to a local — because the brand mark
        // needs the FACE without `font(_:_:)`'s `relativeTo: .body`. This guard's own message
        // said "change the mapping and this guard in the same commit", and that is what
        // happened; it is recorded rather than silently re-spelled, because a needle that moves
        // without a note reads later like the mapping itself was rewritten.
        XCTAssertTrue(theme.contains("case .semibold, .bold, .heavy, .black: return \"AtkinsonHyperlegible-Bold\""), """
            The weight→face mapping changed. Everything in this file reasons from it: which \
            weights are real, which are silently regular, and why `.medium` had to go. Change \
            the mapping and this guard in the same commit.
            """)
    }

    func testTheBundleShipsExactlyTheFacesTheMappingNames() throws {
        let plist = try String(
            contentsOf: repoRoot().appendingPathComponent("Resources/iOS/Info.plist"),
            encoding: .utf8)
        for face in ["AtkinsonHyperlegible-Regular.ttf", "AtkinsonHyperlegible-Bold.ttf"] {
            XCTAssertTrue(plist.contains(face), """
                `UIAppFonts` no longer registers \(face). An unregistered custom font does not \
                fail loudly — `Font.custom` falls back to the system face, so the app keeps \
                rendering and simply stops being itself.
                """)
        }
        // A THIRD face appearing is the good outcome and still wants a look: whoever adds
        // Medium must also extend the mapping, or the file will sit in the bundle unused.
        XCTAssertFalse(plist.contains("AtkinsonHyperlegible-Medium"), """
            A Medium face is now bundled. That is welcome — but the switch in `EchoelTheme` \
            still folds `.medium` onto Regular, so the file ships and nothing draws with it. \
            Extend the mapping and relax `indistinguishable` here in the same commit.
            """)
    }
}
