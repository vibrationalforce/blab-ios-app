// ContentPipelineClaimsTests.swift
// Echoel — `ContentPipeline/CLAIMS.md` is the one list of what may be claimed in a script, a
// caption or a store text. It exists because a false claim is expensive here: #158 and #192
// each spent a whole cycle removing ONE of them (AUv3) from eight files of the website, and
// #184 removed twelve from the App Store text, where a false claim is a 2.3 rejection.
//
// ⭐ THE PROBLEM THIS FILE SOLVES, which is the opposite of the usual one: the claims file
// does not go wrong by being edited. It goes wrong by the REPO changing underneath it while
// it stays still. Two of its entries are not opinions but facts about the build, and nothing
// noticed when they drifted:
//
//   · ✅ "Null externe Abhängigkeiten, alles on-device" — true only while `Package.swift`
//     declares no package dependency. The day someone adds one, a shipped marketing line
//     becomes false and no test in this repo would have said so.
//   · ⛔ "AUv3-Plugin darf NICHT behauptet werden" — a PROHIBITION, and prohibitions rot in
//     the other direction. #191 recorded the founder's intent to ship Echoel AS an AUv3
//     later; on that day this entry stops being true and has to be rewritten rather than
//     obeyed. Failing loudly is how the rewrite gets remembered.
//
// ⚠️ WHAT THIS CANNOT DO. It cannot check a claim that is a judgement ("Wellness", "Biohacking",
// the watch wording) — those have no machine-readable fact behind them and stay with the
// human check the file's own header prescribes. It also cannot stop a script from making a
// claim; it only keeps the reference honest. Do not read a green here as "the marketing is
// true".
//
// ⚠️ It scans SOURCE TEXT: if the checkout is not at the path this file was compiled from it
// SKIPS rather than passes — a silent pass on an unscanned tree is the `continue-on-error`
// lie the `doctor` skill exists to catch.

import Foundation
import XCTest

final class ContentPipelineClaimsTests: XCTestCase {

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`, three levels
    /// up: CISmoke → Tests → repo).
    ///
    /// ⛔ THE SENTINEL MUST NOT BE ONE OF THE FILES UNDER TEST, and the first version made it
    /// `Package.swift` — which is also the subject of the first assertion. Delete or rename
    /// that file and a should-be-failure turns into a SKIP: exactly the silent pass the header
    /// above warns about, built into the guard against it. `Sources/Echoelmusic` is asserted
    /// about by nothing here, which is why `StringCatalogIsHonestTests` uses it too.
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath:
                root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("repo root not present at \(root.path) — this test inspects source "
                          + "text, so it SKIPS rather than reporting a green it did not earn")
        }
        return root
    }

    /// Lines of `path` that are not whole-line comments, in the given comment syntax.
    ///
    /// ⛔ THE COMMENT FILTER IS LOAD-BEARING FOR `project.yml` SPECIFICALLY, and forgetting it
    /// would have made the AUv3 check fail on arrival: the removal is DOCUMENTED there in a
    /// `#`-comment that names `EchoelmusicAUv3` ("The EchoelmusicAUv3 app-extension target …
    /// are gone"). Matching that comment would report the target as present *because* the file
    /// says it was deleted. (⛔ The first version of this note said "twice". It occurs once —
    /// the neighbouring lines say `AUv3` without the target name. One match is enough to fail
    /// the assertion, so the mechanism was right and only the sentence was wrong.)
    ///
    /// ⚠️ WHOLE-LINE ONLY, said plainly rather than implied: a TRAILING comment on a code line
    /// survives the filter (`- target: Foo  # replaces EchoelmusicAUv3`), as would a `/* … */`
    /// block in `Package.swift`. No such line exists today, and the failure direction is the
    /// safe one — a false FAILURE is loud and gets read, a false pass would not be.
    private func codeLines(_ path: String, comment: String) throws -> [String] {
        let text = try String(contentsOf: try repoRoot().appendingPathComponent(path),
                              encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(comment) }
    }

    /// ✅-Tabelle, Zeile "Null externe Abhängigkeiten".
    ///
    /// ⛔ BOTH MANIFESTS, and the first version checked only one. `Package.swift` is NOT what
    /// the shipped app is built from — CI runs `xcodebuild` over the XcodeGen project generated
    /// from `project.yml`, which supports its own `packages:` block. A dependency added there
    /// would ship in the archive while this test stayed green and the ✅ line stayed false.
    /// A fence that covers half the ground is worse than none, because the header claims it
    /// covers the ground.
    func testTheZeroDependenciesClaimIsStillTrue() throws {
        let declared = try codeLines("Package.swift", comment: "//")
            .filter { $0.contains(".package(") }
        XCTAssertTrue(declared.isEmpty, """
        Package.swift now declares a package dependency:
        \(declared.joined(separator: "\n"))

        That may well be the right call — but `ContentPipeline/CLAIMS.md` lists "Null externe \
        Abhängigkeiten, alles on-device" as claimable, and §8 forbids naming any SDK we do not \
        ship. Update BOTH in this commit, or a caption keeps saying something the build no \
        longer does.
        """)

        // XcodeGen's block is a TOP-LEVEL `packages:` key, so an exact trimmed match is both
        // precise and enough — a nested `packages:` under a target is `dependencies:` in
        // XcodeGen's schema, not this key.
        let xcodegen = try codeLines("project.yml", comment: "#")
            .filter { $0.trimmingCharacters(in: .whitespaces) == "packages:" }
        XCTAssertTrue(xcodegen.isEmpty, """
        project.yml declares a `packages:` block. That is the manifest the SHIPPED app is built \
        from, so the dependency reaches the archive even though `Package.swift` is still empty \
        — and "Null externe Abhängigkeiten" in CLAIMS.md becomes false. Same instruction: \
        update the claim in this commit.
        """)
    }

    /// ⛔-Liste, Punkt 1: kein AUv3-Target, kein AUv3-Hosting.
    ///
    /// ⛔ EVERY FAILURE MESSAGE HERE IS A `"""` LITERAL, AND THAT IS NOT A STYLE CHOICE. The
    /// first version wrote them as `+`-chains of five string literals wrapped around a
    /// `joined(separator:)` call, inline in the `XCTAssertTrue(...)` argument. Swift's
    /// type-checker gave up on exactly this one — *"the compiler is unable to type-check this
    /// expression in reasonable time"*, a HARD error that turned the BLOCKING gate red. (The
    /// sibling assertion below it was a 6-second warning; same defect, under the limit.) A
    /// multi-line literal with interpolation is ONE expression and costs nothing. The irony is
    /// the lesson: a guard whose whole purpose is to keep a claim honest cannot ship if its own
    /// explanation is too expensive to compile.
    func testTheNoAUv3ClaimIsStillTheTruthAndNotAStaleProhibition() throws {
        let project = try codeLines("project.yml", comment: "#")
        let auv3 = project.filter { $0.contains("EchoelmusicAUv3") }
        XCTAssertTrue(auv3.isEmpty, """
        project.yml declares an AUv3 target again:
        \(auv3.joined(separator: "\n"))

        If that is #191 arriving (Echoel AS an AUv3), then `ContentPipeline/CLAIMS.md` §1 has \
        flipped from a true prohibition to a false one — and it is the file every script, \
        caption and store text is written from. Rewrite that entry in the SAME commit; do not \
        just delete this assertion.
        """)

        let sources = try repoRoot().appendingPathComponent("Sources/EchoelmusicAUv3")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sources.path), """
        Sources/EchoelmusicAUv3 exists again. Same instruction as above — the claims file is \
        the thing that has to move with it.
        """)

        // ⚠️ HALF A PIN, and CLAIMS.md now says so rather than letting the header imply more:
        // both checks are coupled to the literal name `EchoelmusicAUv3`, so a target returning
        // as `EchoelmusicAU` or `…Plugin` passes silently. And §1 makes a SECOND claim — that
        // Echoel cannot HOST foreign plugins — which nothing here covers, because "no code
        // instantiates AVAudioUnit for a third-party component" has no single token to match.
        // Both gaps are loud, deliberate changes rather than drift; that is why they are
        // documented instead of half-guarded.
    }

    /// And the file itself has to be there to be read. Trivial, and it is the assertion that
    /// catches the one failure the other two cannot: the reference being deleted or renamed,
    /// after which every check above still passes over a repo with no claims list at all.
    func testTheClaimsFileItselfIsStillWhereEveryPromptPointsAtIt() throws {
        let claims = try repoRoot().appendingPathComponent("ContentPipeline/CLAIMS.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: claims.path), """
        ContentPipeline/CLAIMS.md is gone. CLAUDE.md instructs every content session to read it \
        BEFORE writing a script, and the marketing skill routes through it. Without it the next \
        "bio-music app content" prompt reliably invents an AUv3 plugin and a meditation audience.
        """)
    }
}
