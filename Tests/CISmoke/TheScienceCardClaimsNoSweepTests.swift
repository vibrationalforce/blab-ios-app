import XCTest
@testable import Echoelmusic

/// #1089 — the in-app science card stops claiming a clinical protocol the app does not run.
///
/// WHY IT EXISTS. `BioScienceInfo.resonanceFrequency.detail` told users that Echoelmusic "can
/// sweep several paces and show you which one raises your own heart-rate variability most (the
/// Lehrer & Vaschillo resonance-frequency method)". Nothing sweeps. `ResonanceFinder` exists as
/// a pure core and has ZERO construction sites in `Sources/` — every mention outside its own file
/// is a doc comment — and its only API, `bestRate(from:)`, has no caller. The one reachable pacer
/// is `BreathCoachStrip`, which forces the single `.resonance` pattern (~6/min). Naming a cited
/// clinical method as a shipping feature is the #184 / §2.3 class, and this text reaches users
/// through a reachable Learn sheet — the one home of the claim that the store-copy guards do not
/// read.
///
/// ⚠️ THIS GUARD DOES NOT FORBID BUILDING THE SWEEP (#364). It goes red on the day someone
/// constructs a `ResonanceFinder` in production — at which point the card may say "sweep"
/// again, and claim 1 is lifted in the same commit as the wiring. Until then, the card and the
/// code agree.
///
/// ⚠️ GRADED HONESTLY (#464): claim 2 is a REGRESSION — red on the parent (`377cb0f`), green
/// here. Claim 1 is PREVENTIVE and green on both trees; claim 3 is the counterweight that keeps
/// claim 1 from being satisfied by deleting the core or the citation.
final class TheScienceCardClaimsNoSweepTests: XCTestCase {

    private func repoRoot() -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        return dir
    }

    private func source(_ relative: String) -> String {
        let url = repoRoot().appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) could not be read — a missing anchor is a "
                    + "finding, not a pass.")
            return ""
        }
        return text
    }

    /// Every `.swift` file under `Sources/`, as (relative path, text).
    private func sourceFiles() -> [(path: String, text: String)] {
        let root = repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            XCTFail("ANCHOR MISSING: Sources/ could not be enumerated.")
            return []
        }
        var files: [(String, String)] = []
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            if let text = try? String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8) {
                files.append(("Sources/" + rel, text))
            }
        }
        XCTAssertGreaterThan(files.count, 100, "Sources/ walk returned too few files to be the real tree.")
        return files
    }

    // 1 — nothing constructs the sweep. Comment lines are skipped so a doc comment that names
    //     the initialiser (the finder's own header does) is not booked as a producer.
    func testNothingConstructsTheResonanceFinder() {
        var sites: [String] = []
        for file in sourceFiles() where !file.path.hasSuffix("Bio/ResonanceFinder.swift") {
            for (n, line) in file.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("//") { continue }
                if code.contains("ResonanceFinder(") { sites.append("\(file.path):\(n + 1)") }
            }
        }
        XCTAssertTrue(sites.isEmpty, """
            `ResonanceFinder` is now constructed in production: \(sites.joined(separator: ", ")). \
            That is welcome — it means a real pace sweep exists. In the SAME commit, let \
            `BioScienceInfo.resonanceFrequency.detail` say so again and lift claim 2 below; \
            do not delete the construction to get this green.
            """)
    }

    // 2 — the card does not sell the sweep while claim 1 holds.
    func testTheCardDoesNotClaimASweep() {
        let card = source("Sources/Echoelmusic/Studio/BioScienceInfo.swift").lowercased()
        for needle in ["can sweep", "sweep several", "sweeps several"] {
            XCTAssertFalse(card.contains(needle), """
                `BioScienceInfo` says "\(needle)" — a pace sweep the app does not run \
                (`ResonanceFinder` has no production caller; the reachable pacer holds one rate). \
                Wire the finder first, then change the copy and this guard together.
                """)
        }
    }

    // 3 — COUNTERWEIGHT: the honest sentence keeps its citation, and the core it describes as
    //     absent is still in the tree (claim 1 must not be satisfied by deleting the file).
    func testTheCitationAndTheCoreSurvive() {
        let card = source("Sources/Echoelmusic/Studio/BioScienceInfo.swift")
        XCTAssertTrue(card.contains("Lehrer & Vaschillo"),
                      "The resonance card lost its Lehrer & Vaschillo citation — the science reference is the point of the card.")
        XCTAssertTrue(card.contains("does not run the clinical sweep"),
                      "The resonance card no longer states what it does NOT do; that sentence is the honest half.")
        let finder = repoRoot().appendingPathComponent("Sources/Echoelmusic/Bio/ResonanceFinder.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: finder.path),
                      "`Bio/ResonanceFinder.swift` is gone. Claim 1 is vacuous without it — if the core was deleted on purpose, retire this guard in the same commit.")
    }
}
