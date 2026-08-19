// RadiusHasOneSpellingTests.swift
// Echoel — #483. A corner radius that EQUALS a named `EchoelTheme` constant must be spelled
// as that constant, not as the number the constant happens to hold today.
//
// WHY THIS EXISTS, and why it is not decoration. Until 2026-08-07 the app spelled its radii
// two ways at once: 163 call sites read `EchoelTheme.radius`, and 10 wrote `cornerRadius: 8` —
// the literal that constant holds. Same for `radiusSmall` (8 reads / 3 × `4`) and `radiusLarge`
// (7 reads / 6 × `12`). That is #416 at its quietest: ONE decision, TWO spellings, and nothing
// that notices when they part.
//
// ⭐ AND IT MATTERED MOST AT THE ONE PLACE THE FOUNDER NAMED. #481/#482 came from a screenshot
// with the transport row circled: *"Die größe der Buttons anpassen, die sollen immer gleichgroß
// sein. Orientiere dich an denen oben rechts."* The tiles "oben rechts" are `HeaderMonitors.swift`
// — and all EIGHT of its radius sites spelled `8`, while `EchoelIconTile`, the tile written to
// match them, reads `EchoelTheme.radius`. So moving the token would have moved the COPY and left
// the REFERENCE behind: the one pair the founder asked to keep identical was the one pair that
// could split without any diff looking wrong.
//
// ⚠️ HONEST SIZE: nothing moved a pixel. All NINETEEN literals were EQUAL to the constant they
// folded into, so this removes a MECHANISM and not a defect — said plainly rather than dressed
// up as a bug fix. What it buys is the NEXT token change.
//
// ⛔ NINETEEN FOLDED, EIGHTEEN VISIBLE — and that gap is the honest measure of this guard's
// reach, not a rounding slip. The scan below only sees a numeric literal in immediate postfix
// position after `cornerRadius:` and zero-or-more SPACES. It is therefore blind to a ternary, to
// tab separation, and to any computed radius. The first draft of #483 folded the eighteen the
// scan can see and left `FloatingVisualWindow.swift`'s `windowSize.isFullscreen ? 0 : 12` — two
// lines above a border that now read `EchoelTheme.radiusLarge`, i.e. the fold INTRODUCED the
// exact split it removes elsewhere, invisibly. The #483 reviewer found it. The nineteenth is
// folded by hand; the blind spots are written down here rather than quietly relied on, because a
// claim that is true only under the checker's own parser is the kind this repo retracts.
//
// ⚠️ WHAT IS DELIBERATELY NOT SWEPT: **seven** `cornerRadius:` literals remain in the app
// module — 4 × `6`, 3 × `2` — measured 2026-08-19 with
// `git grep -hoE 'cornerRadius: *[0-9]+' -- Sources/Echoelmusic | grep -oE '[0-9]+' | sort -n | uniq -c`.
// ⛔ This said "eight … 1 × `1`" and BOTH halves had aged: the `1` is gone, and the count with it.
// (The `8` a plain grep also prints is at `Studio/HeaderMonitors.swift:186` and is inside a
// COMMENT quoting this very rule — the stripper removes it, so it is not an offender. A count
// taken by eye off `git grep` and not through `codeOnly` would have called this rule red.)
// `EchoelTheme` names no radius with those values, so there is nothing to fold them INTO; giving
// them a token is a design decision (which surfaces deserve a fourth radius?) and not a
// mechanical fold. The rule below is therefore VALUE-BASED, not "no literals at all" — and
// `testAnUnnamedValueIsStillAllowed` pins exactly that, because the obvious next cleanup is
// "ban every numeric radius", which would force a token to be invented by whoever happens to
// touch the file next.
//
// ⚠️ AND THE RULE IS SELF-MAINTAINING BY CONSTRUCTION, which is the reason the constants' VALUES
// are NOT pinned here. Change `radius` from 8 to 10 and a stray literal `10` becomes a violation
// while a literal `8` becomes legal again — correct in both directions. Pinning 8/4/12 as well
// would make an ordinary design change red, and that is how a guard gets deleted (#364).
//
// ⚠️ GRADING, measured against the parent tree rather than remembered — TWO of the five methods
// are regressions, not one. `testNoRadiusLiteralDuplicatesANamedConstant` is red at eighteen
// sites, and `testTheReferenceAndTheCopyReadTheSameToken` is red on its HEADER half (the copy
// already passed; that asymmetry IS the defect). `testTheThemeStillNamesTheThreeRadii` is a
// premise and `testAnUnnamedValueIsStillAllowed` / `testTheIconTileDoesNotCarryABareRadiusLiteral`
// are counter-weights — all three green on both sides, which is what they are for: the plausible
// follow-ups (ban every numeric radius, or "match the header" by putting the literal BACK into
// `EchoelIconTile`) each undo this slice.
//
// ⛔ AND THE FIRST DRAFT OF THAT PARAGRAPH SAID "the one regression … the other three are
// counter-weights and green on both sides", which was wrong twice over — it missed the header
// half above, and its own `testAnUnnamedValueIsStillAllowed` carried a second assertion that was
// red at 8-of-26 on the parent. Both found by transcribing the scan and driving it against BOTH
// trees before committing, not by reading the code back. The redundant assertion is gone (see the
// ⛔ block at its site); the count is measured. (`testNoRadiusLiteralDuplicatesANamedConstant` is
// red at EIGHTEEN sites, not nineteen — the ternary was never visible to it; see the ⛔ block on
// reach above. The fold is nineteen, the regression is eighteen, and conflating the two is how a
// grading paragraph starts lying.)
//
// ⚠️ EVERY assertion here is a SOURCE-TEXT SCAN. That the corners LOOK right, that 8 pt is the
// right radius for a chrome tile, and that the header row and the icon tile read as one family
// on a device are all sight checks, and all open.
//
// `SourceText.codeOnly` (#453) is LOAD-BEARING, not prophylactic, and measurably so: the
// retraction comment this slice writes into `HeaderMonitors.swift` quotes `cornerRadius: 8`
// verbatim, so a raw-text scan would be RED on correct code. This repo writes down what it
// removed; a negative scan and an honest retraction collide by construction.

import Foundation
import XCTest

final class RadiusHasOneSpellingTests: XCTestCase {

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…` → up two).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()   // CISmoke
            .deletingLastPathComponent()              // Tests
            .deletingLastPathComponent()              // repo
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
                source tree not present at \(sources.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }

    /// Every `.swift` file under `Sources/Echoelmusic` — the APP MODULE, see the ⛔ below —
    /// comments removed by the ONE shared stripper (#453).
    private func sourceFiles() throws -> [(path: String, code: String)] {
        let root = try repoRoot()
        // ⛔ `Sources/Echoelmusic`, NOT `Sources` — narrowed by #632b, and the narrowing is a
        // CONFESSION rather than a convenience. `EchoelTheme` lives in the app module;
        // `project.yml` gives `EchoelmusicWidgets` and `EchoelmusicWatch` their own directory
        // plus `Core/BioFeedbackManager.swift` and nothing else, so neither target can spell
        // `EchoelTheme.radiusSmall` — the token this rule demands does not exist there. Scanning
        // them meant demanding a symbol that cannot compile.
        //
        // ⚠️ The gap is not swept under the rug: `testTheExtensionTargetsAreListedNotForgotten`
        // below scans exactly those two directories and pins every literal in them by NAME, so a
        // split that this rule can no longer prevent is at least WRITTEN DOWN — and a third
        // extension literal cannot appear unlisted. That is the `isFresh` shape (#545): an
        // exemption that is testable and that expires by itself the day the premise changes.
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard let walker = FileManager.default.enumerator(at: sources,
                                                          includingPropertiesForKeys: nil) else {
            return []
        }
        // ⛔ Declared WITH the labels the return type uses. `[(String, String)]` and
        // `[(path: String, code: String)]` are DIFFERENT types once they are an Array's element —
        // tuple-label conversion does not reach through a generic — and there is no compiler in
        // this session to catch it. `EveryReachableRowStatesItsGridTests` and `OneStartControlTests`
        // both carry this same note; this file's first draft wrote the unlabeled form anyway and
        // the #483 reviewer caught it. A build death here is indistinguishable from #396 without
        // reading the job log, which is what makes a free fix worth writing down.
        var out: [(path: String, code: String)] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
            out.append((rel, SourceText.codeOnly(text)))
        }
        // ⚠️ VACUITY FLOOR, and it lives HERE so no consumer can forget it. Without it the
        // enumerator returning nothing (wrong root, permissions, a moved tree) makes the
        // regression below pass on an EMPTY set — green on nothing, the #367 shape this bundle
        // exists to prevent. The floor is deliberately far below today's count rather than equal
        // to it: pinning the exact number would make every added file red (#364).
        guard out.count >= 300 else {
            throw ScanFloorViolated(description: """
                only \(out.count) Swift files found under Sources/Echoelmusic — the scan is vacuous, so a \
                green here would mean nothing. Expected 300+ (349 on 2026-08-07). If the tree \
                genuinely shrank that far, lower this floor deliberately in the same commit.
                """)
        }
        return out.sorted { $0.path < $1.path }
    }

    /// A scan that read too little is a failure, not a pass — thrown so XCTest reports it.
    private struct ScanFloorViolated: Error, CustomStringConvertible { let description: String }

    // MARK: - the named radii

    /// `name → value` for every `static let radius…: CGFloat = N` in `EchoelTheme`.
    private func namedRadii() throws -> [String: Double] {
        let url = try repoRoot()
            .appendingPathComponent("Sources/Echoelmusic/Studio/EchoelTheme.swift")
        let code = SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
        var found: [String: Double] = [:]
        for line in code.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("static let radius") else { continue }
            guard let eq = s.firstIndex(of: "="), let colon = s.firstIndex(of: ":") else { continue }
            let name = s[s.index(s.startIndex, offsetBy: "static let ".count)..<colon]
                .trimmingCharacters(in: .whitespaces)
            let rhs = s[s.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            guard let value = Double(rhs) else { continue }
            found[name] = value
        }
        return found
    }

    /// The premise every other assertion rests on. Without it a renamed or deleted token would
    /// leave the scan below comparing against an EMPTY set — green on a tree with no rule at all,
    /// which is the #367 trap this bundle exists to avoid.
    func testTheThemeStillNamesTheThreeRadii() throws {
        let radii = try namedRadii()
        for name in ["radius", "radiusSmall", "radiusLarge"] {
            XCTAssertNotNil(radii[name], """
                EchoelTheme no longer declares `static let \(name): CGFloat = …`. Found: \
                \(radii.keys.sorted()). If the token was renamed, rename it here in the SAME \
                commit — do not delete this check, it is what makes the scan below mean anything.
                """)
        }
    }

    // MARK: - the rule

    /// Numeric `cornerRadius:` literals, as `(file:line, value)`.
    private func radiusLiterals(_ files: [(path: String, code: String)]) -> [(String, Double)] {
        var out: [(String, Double)] = []
        for (path, code) in files {
            for (i, line) in code.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                var rest = line   // already a `Substring`; re-wrapping it copied for nothing
                while let r = rest.range(of: "cornerRadius:") {
                    let after = rest[r.upperBound...].drop(while: { $0 == " " })
                    let token = after.prefix(while: { $0.isNumber || $0 == "." })
                    if !token.isEmpty, let v = Double(String(token)) {
                        out.append(("\(path):\(i + 1)", v))
                    }
                    rest = rest[r.upperBound...]
                }
            }
        }
        return out
    }

    /// THE REGRESSION. Red at eighteen sites on every tree before #483 — eighteen and not the
    /// nineteen that were folded, because the nineteenth is a ternary this scan cannot see.
    func testNoRadiusLiteralDuplicatesANamedConstant() throws {
        let radii = try namedRadii()
        let byValue = Dictionary(radii.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
        let offenders = radiusLiterals(try sourceFiles()).compactMap { site, value -> String? in
            guard let name = byValue[value] else { return nil }
            return "\(site) writes \(Int(value)) — spell it `EchoelTheme.\(name)`"
        }
        XCTAssertTrue(offenders.isEmpty, """
            A corner radius is spelled as the number a token already holds, so moving the token \
            would move some surfaces and not others (#416, #483):
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// THE CONFESSION THAT REPLACES THE COVERAGE (#632b). The rule above can no longer reach
    /// `Sources/EchoelmusicWidgets` and `Sources/EchoelmusicWatch`, so this pins what is in
    /// them BY NAME. It is not a fold and cannot become one: those targets compile without the
    /// app module, so `EchoelTheme.radiusSmall` is not a symbol they have.
    ///
    /// ⛔ WHY A LIST AND NOT A BAN. Banning literals there would leave the two demo tags with no
    /// way to match the app's small radius at all, which is worse than a documented split. And a
    /// LOCAL constant would be the dishonest fix: the scan above would go green while the split
    /// it exists to expose stayed exactly where it was. This is the third option — keep the
    /// literal, and make it impossible for a fourth one to appear unnoticed.
    ///
    /// ⚠️ THE EXEMPTION EXPIRES BY ITSELF. If `project.yml` ever gives either target
    /// `EchoelTheme.swift`, the premise is void and the honest move is to fold these two and
    /// widen the walker back — claim 3 below goes red on that day and says so.
    func testTheExtensionTargetsAreListedNotForgotten() throws {
        let root = try repoRoot()
        var files: [(path: String, code: String)] = []
        for dir in ["Sources/EchoelmusicWidgets", "Sources/EchoelmusicWatch"] {
            let base = root.appendingPathComponent(dir)
            guard let walker = FileManager.default.enumerator(at: base,
                                                              includingPropertiesForKeys: nil) else {
                return XCTFail("\(dir) could not be enumerated — this list would be vacuous")
            }
            var seen = 0
            for case let url as URL in walker where url.pathExtension == "swift" {
                let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
                files.append((rel, SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))))
                seen += 1
            }
            XCTAssertGreaterThan(seen, 0, "\(dir) yielded no Swift file — vacuous scan (#367)")
        }

        // 1. Exactly the two known sites, both 4 (the value `EchoelTheme.radiusSmall` holds).
        //    ⚠️ FILE AND VALUE, NEVER THE LINE (#408): the first draft of this list pinned
        //    `:96`/`:97`, and the SAME commit added two modifiers above them. A line number in a
        //    guard over a living file is a date, not a fact.
        let found = radiusLiterals(files)
            .map { "\($0.0.split(separator: ":").first.map(String.init) ?? $0.0) = \(Int($0.1))" }
            .sorted()
        XCTAssertEqual(found, [
            "Sources/EchoelmusicWatch/EchoelWatchApp.swift = 4",
            "Sources/EchoelmusicWidgets/EchoelBioWidget.swift = 4"
        ], """
            The corner-radius literals in the two extension targets changed. This list is the \
            ONLY record of a split the rule above cannot police — update it deliberately, and \
            say in the commit why the new literal cannot be folded.
            """)

        // 2. …and they are the demo tag, not decoration that drifted in.
        for (path, code) in files where code.contains("cornerRadius:") {
            XCTAssertTrue(code.contains("demoTag"), """
                \(path) carries a corner-radius literal that is not the #632 demo tag. \
                A new rounded surface in an extension target needs its own line above.
                """)
        }

        // 3. The premise: neither target is given the theme, so neither CAN fold.
        let yml = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        XCTAssertFalse(yml.contains("Sources/Echoelmusic/Studio/EchoelTheme.swift"), """
            `project.yml` now hands `EchoelTheme.swift` to a target by path. If that target is \
            the widget or the watch, this whole exemption is void: fold both literals into \
            `EchoelTheme.radiusSmall` and widen the walker in `sourceFiles()` back to `Sources`.
            """)
    }

    // MARK: - counter-weights (green on both sides, and that is the point)

    /// The obvious next cleanup is "ban every numeric radius". That would force whoever touches
    /// one of these eight to invent a fourth token on the spot. A value with no constant to fold
    /// into is legal; it is a design question, not a fold.
    func testAnUnnamedValueIsStillAllowed() throws {
        let radii = try namedRadii()
        let values = Set(radii.values)
        let literals = radiusLiterals(try sourceFiles())
        let unnamed = literals.filter { !values.contains($0.1) }
        XCTAssertFalse(unnamed.isEmpty, """
            Every remaining `cornerRadius:` literal now equals a named token. That is not a \
            failure of the app — it is a failure of this counter-weight's PREMISE: it was written \
            while eight literals (6, 2, 1) had no constant to fold into. If a later slice gave \
            them one, delete this test deliberately rather than loosening it. (An EMPTY scan \
            would also land here, but it cannot: `sourceFiles()` throws below 300 files. Do not \
            read this message as "delete the check" when the real cause is a scan that read \
            nothing — that instruction, in the first draft, pointed at the only thing noticing.)
            """)
        // ⛔ The first version added `XCTAssertEqual(unnamed.count, literals.count)` here "so the
        // two tests cannot double-count". Measured against the parent tree before committing: that
        // made this method RED at 8-of-26 — i.e. a counter-weight failing for a reason its own name
        // does not mention, and it merely restated the regression above (offenders empty ⟺ unnamed
        // == all). Removed rather than kept: a counter-weight that is red on the old tree is
        // indistinguishable from a regression in the grading, which is the #433 defect.
    }

    /// The founder's reference pair, pinned by name rather than by count: the header tiles are
    /// what `EchoelIconTile` was written to match (#481/#482), so BOTH must read the token.
    /// Pinning only one of them is how they split in the first place.
    func testTheReferenceAndTheCopyReadTheSameToken() throws {
        let root = try repoRoot()
        for rel in ["Sources/Echoelmusic/Studio/HeaderMonitors.swift",
                    "Sources/Echoelmusic/Studio/EchoelIconTile.swift"] {
            let url = root.appendingPathComponent(rel)
            let code = SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
            XCTAssertFalse(code.isEmpty, "\(rel) is empty after comment stripping — anchor lost")
            XCTAssertTrue(code.contains("cornerRadius: EchoelTheme.radius"), """
                \(rel) no longer spells its corner radius as `EchoelTheme.radius`. The header \
                tiles and the icon tile are ONE format by founder instruction; if this surface \
                genuinely wants a different radius, that is a decision to write down, not a \
                literal to slip in.
                """)
        }
    }

    /// `EchoelIconTile` is the copy, so the tempting "fix" for a mismatch is to put the literal
    /// back INTO it to match a header that spells `8`. That direction is what #483 undid.
    func testTheIconTileDoesNotCarryABareRadiusLiteral() throws {
        let url = try repoRoot()
            .appendingPathComponent("Sources/Echoelmusic/Studio/EchoelIconTile.swift")
        let code = SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
        XCTAssertTrue(code.contains("EchoelTheme.radius"), "anchor lost — file no longer themed")
        XCTAssertFalse(code.contains("cornerRadius: 8"), """
            `EchoelIconTile` spells a bare `8`. It is the COPY of the header tiles; matching them \
            by inlining the number is the direction #483 removed — fold the reference to the \
            token instead.
            """)
    }
}
