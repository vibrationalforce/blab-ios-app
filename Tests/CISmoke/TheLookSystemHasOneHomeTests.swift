// TheLookSystemHasOneHomeTests.swift
// Echoel — `BioVisualPattern` is a dead parallel look system, and the file that holds it
// pointed the next session at it. BLOCKING bundle.
//
// #1147. `Studio/BioVisualParams.swift` opened with "the richer Cymatics/Mandala GPU kernels
// next". Cymatics shipped — as `fieldDish` (shader style 2) driven by `Core/FaradayDish` — and
// did not come through that file. The header stayed, so the word a session searches for on the
// founder's own ask ("physikalisch echte Visuals … Cymatics") led to an enum nothing renders.
//
// ⛔ THIS GUARD FORBIDS NOTHING (#364). It does not require the enum to stay unconsumed: the
// day something renders `BioVisualPattern`, claim 1 goes red and its message says to move the
// retraction rather than to undo the wiring. It does not require the roster to stay at five
// either — claim 2 pins the two files that must BOTH gain a row, not how many rows they hold.
//
// ⚠️ NO COUNT IS PINNED, on purpose (#818). The roster moved from four to five when the Dish
// landed and can move again; a number here would be a date. What is pinned is the STRUCTURE:
// the roster lives in LookBlendMap, the flash budgets in FlashGuard, and the enum is in
// neither.

import XCTest

final class TheLookSystemHasOneHomeTests: XCTestCase {

    private static let params = "Sources/Echoelmusic/Studio/BioVisualParams.swift"
    private static let blendMap = "Sources/Echoelmusic/Studio/LookBlendMap.swift"
    private static let flashGuard = "Sources/Echoelmusic/Core/FlashGuard.swift"

    private func root() throws -> URL {
        let r = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: r.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(r.path)") }
        return r
    }

    private func raw(_ relativePath: String) throws -> String {
        let path = try root().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            XCTFail("ANCHOR MISSING: \(relativePath) could not be read — a missing anchor is a "
                    + "finding, not a pass.")
            return ""
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    /// Every `.swift` file under `Sources/`, so "no consumer" is a sweep and not a memory.
    private func allSources() throws -> [(String, String)] {
        let base = try root().appendingPathComponent("Sources")
        guard let walk = FileManager.default.enumerator(atPath: base.path) else { return [] }
        var out: [(String, String)] = []
        for case let rel as String in walk where rel.hasSuffix(".swift") {
            let url = base.appendingPathComponent(rel)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                out.append((rel, SourceText.codeOnly(text)))
            }
        }
        XCTAssertGreaterThan(out.count, 100, "The source walk collapsed — that is a finding.")
        return out
    }

    /// 1 — the enum is still rendered by nothing. Its own file is the only file that names it.
    func testNothingOutsideItsOwnFileNamesTheDeadLookEnum() throws {
        let others = try allSources()
            .filter { !$0.0.hasSuffix("BioVisualParams.swift") }
            .filter { $0.1.contains("BioVisualPattern") }
            .map(\.0)
        XCTAssertTrue(others.isEmpty,
                      "BioVisualPattern now has a consumer in \(others). That is an IMPROVEMENT, "
                      + "not a failure — but the ⛔ NO CONSUMER notes on the enum and on the "
                      + "`pattern` field in Studio/BioVisualParams.swift are now false and must "
                      + "be retracted in the same commit.")
    }

    /// 2 — the two homes a real look must be registered in both still exist and still hold the
    /// roster. If either moves, the header's "go here instead" directions are wrong.
    func testTheLiveLookSystemStillLivesInItsTwoNamedHomes() throws {
        let map = SourceText.codeOnly(try raw(Self.blendMap))
        XCTAssertTrue(map.contains("(0, \"Rings\")"),
                      "LookBlendMap's curated roster moved or was renamed. The header of "
                      + "Studio/BioVisualParams.swift names it as the place a new look is "
                      + "registered — move that direction with it.")
        let guardText = SourceText.codeOnly(try raw(Self.flashGuard))
        XCTAssertTrue(guardText.contains("fieldBudgets"),
                      "FlashGuard.fieldBudgets moved or was renamed. It is the second of the two "
                      + "homes the BioVisualParams header sends a session to; a look registered "
                      + "in only one of them has no flash budget.")
    }

    /// 3 — the retraction lives in the file a session opens when it searches for "Cymatics",
    /// not only in a session log (#456).
    func testTheSupersededPlanIsRetractedWhereItWasWritten() throws {
        let text = try raw(Self.params)
        XCTAssertFalse(text.contains("Cymatics/Mandala GPU kernels next"),
                       "The superseded 'next' promise is back in the header. Cymatics shipped as "
                       + "fieldDish/FaradayDish; that sentence sends a session to build a second "
                       + "one against an enum nothing renders.")
        XCTAssertTrue(text.contains("OVERTAKEN, NOT ABANDONED"),
                      "The retraction left the header. Without it the word 'Cymatics' in this "
                      + "file is the first hit a session gets on the founder's own ask.")
    }
}
