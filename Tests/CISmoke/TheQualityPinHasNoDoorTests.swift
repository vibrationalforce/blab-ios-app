// TheQualityPinHasNoDoorTests.swift
// Echoel — a doc comment that names the user and the use case for a branch that never runs. #727.
//
// WHAT WAS WRONG. `ResourceGovernor.isAutomatic` is `public var … = true` and its doc said a
// performer "can pin a tier (e.g. force High for a show)". Measured across all 369 files under
// `Sources/`, comments stripped: `isAutomatic` occurs THREE times — the declaration, its own
// `didSet`, and the `guard` in `recompute()`. No writer, no binding, no control.
//
// ⚠️ AND IT GOES ONE STEP FURTHER THAN THE BREATH-PLAY FINDING (#724/#725), which is why it is
// its own guard rather than a second claim there. There, a permanently-true flag meant the
// feature ALWAYS ran. Here, because `isAutomatic` can never be false, the
// `guard isAutomatic else { apply(…manualTier) }` branch is UNREACHABLE — so `manualTier`,
// whose only read lives inside it, can never affect anything either. The manual-override half
// of a live class does not run, and the doc described it in the present tense to a performer.
//
// ⭐ THE AUTOMATIC HALF IS LIVE, WHICH IS WHY CLAIMS 4 AND 5 EXIST. `EchoelmusicApp` constructs
// the governor, `MetalBioView` takes it from `@Environment`, `ExternalStageBridge` wires it,
// and CLAUDE.md records `bioHz` → `OSCSender` as its one wired consumer. Nothing here argues
// for deletion — what is missing is the DOOR. Without the counterweights, "remove the unused
// manual-tier code" would pass claims 1-3 and quietly answer a founder question.
//
// ⚠️ IT FORBIDS NOTHING (#364). Pinning a tier for a show is a real live-performance need and
// the machinery is two lines from working; whether it should exist is the founder's call. On
// the day a writer appears, claim 2 goes red BY DESIGN and its message names the ⛔ block in
// `ResourceGovernor.swift` that must move in the same commit (#456).
//
// ⛔ CLAIM 2 SCANS FOR THE NAME, NOT FOR WRITE SHAPES — the #725 lesson, paid for one slice
// ago. `ResourceGovernor` is `@MainActor @Observable`, so the realistic door is
// `@Bindable var g = governor` + `Toggle(…, isOn: $g.isAutomatic)`, i.e. the text
// `$g.isAutomatic` — which a needle list of `isAutomatic =`, `$isAutomatic`,
// `isAutomatic.toggle()` all miss. Enumerating write shapes is a guess about the future; the
// name is not. Zero occurrences outside the declaring file today, so the total scan is green.
//
// ⚠️ A MISSING ANCHOR FAILS, A MISSING TREE SKIPS (#454), and the walk asserts it actually saw
// the declaring file — a rename would otherwise leave claim 2 reporting "no writers" for a
// flag that still exists.
//
// ⚠️ HONEST GRADING (#433/#464/#486). This file names no symbol the slice adds, so it compiles
// against both trees and every assertion has a verdict. Hand-transcribed (a Python rebuild of
// `SourceText.codeOnly` driven against `git show <parent>:` and the worktree) — a CI round
// trip is a lottery ticket, not a check (#686):
//   · **1 REGRESSION** on the parent `bf069b8`: claim 1, the promise "can pin a tier" is
//     present and unretracted. Claim 1b is red there too, but by ANCHOR ABSENCE (the
//     retraction does not exist yet) — one absence, reported once (#486), not a second finding.
//   · **5 COUNTERWEIGHTS** green on both trees: no writer outside the file (2), exactly one
//     assignment inside it (2b), the unreachable branch still exists (3), the automatic half
//     is still constructed (4) and consumed (5). Green on both is the point, not padding
//     (#343). Seven test methods in total: 1 regression, 1 anchor-absence, 5 counterweights.
//   · SOURCE-TEXT SCAN throughout (§1). Nothing here drives the governor: `recompute()` is
//     private and the class is `@MainActor`.
//
// ⚠️ AND THE LIMIT FIRST. This proves no line in `Sources/` can turn automatic governing off,
// and that the prose agrees. It proves nothing about thermal behaviour on a device.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheQualityPinHasNoDoorTests: XCTestCase {

    private struct QualityAnchorMissing: Error, CustomStringConvertible {
        let reason: String
        var description: String { "quality-pin anchor missing: \(reason)" }
    }

    private static let governorRelative = "Echoelmusic/Core/ResourceGovernor.swift"
    private static let governor = "Sources/" + governorRelative

    // MARK: - 1: the doc no longer promises a performer control

    func testTheDocNoLongerPromisesAPin() throws {
        let phrase = "can pin a tier"
        let raw: String = try rawText(Self.governor)
        let offenders: [String] = raw.components(separatedBy: "\n")
            .filter({ $0.contains(phrase) && !$0.contains("SAID") })
        XCTAssertTrue(offenders.isEmpty, """
            `ResourceGovernor` promises again that a performer "\(phrase)", outside a \
            retraction:
            \(offenders.joined(separator: "\n"))
            Nothing in `Sources/` writes `isAutomatic`, so the branch that would honour a pin \
            never runs. If a control HAS been built, claim 2 is red in this same run and the \
            ⛔ block above the declaration is the work.
            """)
    }

    /// 1b — without this, deleting the whole ⛔ block passes every other claim while the
    /// measurement that justifies keeping the code is gone: "kept the LINE, lost the FACT" (#343).
    func testTheRetractionItselfIsStillOnRecord() throws {
        let raw: String = try rawText(Self.governor)
        // The needle lives on ONE line by construction — a two-line quote matches nothing and
        // is red on a correct tree (#725 made exactly that mistake and caught it in simulation).
        XCTAssertTrue(raw.contains("THIS LINE SAID a performer"), """
            The ⛔ retraction above `isAutomatic` is gone from \(Self.governor).

            If a door was built, that block SHOULD change — but then claim 2 is red too and \
            the replacement text is the work. If it was merely deleted, nothing records that \
            the manual-override branch is unreachable.
            """)
    }

    // MARK: - 2: THE FINDING — nothing outside the declaring file names the flag

    func testNothingOutsideTheDeclaringFileNamesTheFlag() throws {
        let writers: [String] = try filesNaming("isAutomatic")
        XCTAssertTrue(writers.isEmpty, """
            `isAutomatic` is now named outside `ResourceGovernor.swift`, in: \
            \(writers.joined(separator: ", ")).

            That is GOOD NEWS if it is a real door — this guard forbids building one (#364). \
            It fires on a mere READ too, deliberately: a needle list of write shapes misses \
            `$g.isAutomatic`, the `@Observable` binding that is the likeliest door of all \
            (#725). The repair is not to relax this: move the ⛔ block above the declaration \
            in `ResourceGovernor.swift` in the SAME commit (#456).
            """)
    }

    /// 2b — the declaring file must still assign it exactly once. Claim 2 skips that file, so
    /// a door added inside it would otherwise be invisible forever.
    /// ⛔ THE TYPE ANNOTATION IS WHY THIS IS NOT A COPY OF #725's VERSION. There the
    /// declaration reads `= true` straight after the name; here it is
    /// `public var isAutomatic: Bool = true`, so a test that demands `=` immediately after the
    /// name counts ZERO and is red on a correct tree. Caught in simulation before pushing —
    /// the same class of miss as a needle that matches nothing (#367), one level down: the
    /// rule was right and the spelling it assumed was not.
    func testTheDeclaringFileAssignsItExactlyOnce() throws {
        let code: String = try codeOf(Self.governor)
        var assignments: [String] = []
        for line in code.components(separatedBy: "\n") {
            guard let hit = line.range(of: "isAutomatic") else { continue }
            var tail: String = String(line[hit.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            if tail.hasPrefix(":") {                    // skip an explicit `: Bool`
                guard let eq = tail.firstIndex(of: "=") else { continue }
                tail = String(tail[eq...])
            }
            guard tail.hasPrefix("="), !tail.hasPrefix("==") else { continue }
            assignments.append(line)
        }
        XCTAssertEqual(assignments.count, 1, """
            \(Self.governorRelative) now assigns `isAutomatic` \(assignments.count) times, \
            not once:
            \(assignments.joined(separator: "\n"))
            One assignment is the declaration. A second is a door built inside the declaring \
            file, which claim 2 cannot see — same repair: move the ⛔ block.
            """)
    }

    // MARK: - 3: COUNTERWEIGHT — the branch the finding is about still exists

    /// Without this, deleting the manual-override branch would pass claims 1-2 trivially and
    /// answer a founder question ("should a performer be able to pin a tier?") by removal.
    func testTheUnreachableManualBranchStillExists() throws {
        let code: String = try codeOf(Self.governor)
        XCTAssertTrue(code.contains("guard isAutomatic else"), """
            `recompute()` no longer guards on `isAutomatic`.

            If the manual-override branch was DELETED, that decides a founder question by \
            cleanup: pinning a tier for a show is a real live-performance need and the \
            machinery was two lines from working. If it was merely reformatted, re-anchor \
            this needle on the new spelling — an unanchored scan is the #367 defect.
            """)
        XCTAssertTrue(code.contains("AdaptiveQuality.settings(for: manualTier)"), """
            The unreachable branch no longer applies `manualTier`, so the second half of the \
            finding (a property whose only read is inside a branch that never runs) can no \
            longer be stated from this file.
            """)
    }

    // MARK: - 4/5: COUNTERWEIGHTS — the automatic half really is live

    /// The finding is "no door", not "dead class". If the governor stopped being constructed,
    /// this would be a different and much larger finding.
    func testTheGovernorIsStillConstructedAtLaunch() throws {
        let app: String = try codeOf("Sources/Echoelmusic/EchoelmusicApp.swift")
        XCTAssertTrue(app.contains("ResourceGovernor()"), """
            `EchoelmusicApp` no longer constructs a `ResourceGovernor`.

            The whole finding rests on this class being LIVE with one half unreachable. If it \
            is no longer built at launch, the ⛔ block above `isAutomatic` overstates what is \
            running and must be rewritten, not this assertion.
            """)
    }

    func testTheGovernorStillHasAConsumer() throws {
        let consumers: [String] = try filesNaming("ResourceGovernor")
        XCTAssertFalse(consumers.isEmpty, """
            No file outside `ResourceGovernor.swift` names the type at all.

            Its live consumers are the reason "the automatic half is live" is written above \
            (`MetalBioView` via `@Environment`, `ExternalStageBridge.wire`, and the app \
            entry point). With none, this is not a missing door — it is an unreachable class, \
            a different finding that belongs in CLAUDE.md's doorless register.
            """)
    }

    // MARK: - helpers

    /// Files under `Sources/` whose code (comments stripped) names `needle`, excluding the
    /// declaring file by exact relative path — `hasSuffix` would also excuse a future
    /// `LegacyResourceGovernor.swift` anywhere in the tree.
    private func filesNaming(_ needle: String) throws -> [String] {
        let base = try repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: base.path) else {
            throw QualityAnchorMissing(reason: "cannot walk Sources/")
        }
        var hits: [String] = []
        var seen = 0
        var sawDeclaringFile = false
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            seen += 1
            if rel == Self.governorRelative {
                sawDeclaringFile = true
                continue
            }
            let text: String = SourceText.codeOnly(
                try String(contentsOf: base.appendingPathComponent(rel), encoding: .utf8))
            if text.contains(needle) { hits.append(rel) }
        }
        guard seen > 200 else {
            throw QualityAnchorMissing(reason: """
                only \(seen) Swift files walked under Sources/; the tree holds well over three \
                hundred, so this walk saw a partial checkout and would report a green it did \
                not earn (#454)
                """)
        }
        guard sawDeclaringFile else {
            throw QualityAnchorMissing(reason: """
                \(Self.governorRelative) was not among the \(seen) files walked — it moved or \
                was renamed. This FAILS rather than skips: a rename would otherwise leave \
                claim 2 reporting "no writers" for a flag that still exists (#454)
                """)
        }
        return hits.sorted()
    }

    private func codeOf(_ relativePath: String) throws -> String {
        SourceText.codeOnly(try rawText(relativePath))
    }

    private func rawText(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw QualityAnchorMissing(reason: """
                \(relativePath) is not present while `Sources/` is — the anchor moved. A \
                missing TREE skips (see `repoRoot`); a missing ANCHOR fails (#454)
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        return root
    }
}
