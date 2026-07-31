// LibraryAutosaveSectionTests.swift
// Echoel — #285. The saved-projects library is newest-first by contract (`ProjectStore.save`
// does `insert(at: 0)`, `init` sorts by `savedAt`), and since #273 an autosave is written
// EVERY time the app goes to the background. The two together put a row the user never made
// permanently above the take they did make, with a fresh timestamp on every app switch.
//
// ⭐ WHAT THIS FILE PINS, and it is the half that can destroy data rather than the half that
// looks tidy. Splitting one `ForEach` into two means splitting `.onDelete` into two, and an
// `IndexSet` from the second section is an index into the SECOND array. The old single handler
// mapped straight into `projects.projects`; left in place under a split list it would have
// deleted the wrong project — silently, with the row the user swiped still sitting there. So
// the assertion is not "there are two sections" but "each handler indexes its own array, and
// the whole-array indexing is gone".
//
// ⚠️ WHY A SOURCE SCAN. `openSheet` is a `private` member of a view; `@testable import` grants
// `internal`, not `private`, and there is no simulator in this environment. House pattern:
// `ChromeDynamicTypeTests`, `UnisonRowDefaultsTests`.
//
// ⛔ HONEST LIMIT: this proves the code is WRITTEN that way. It cannot prove the sheet renders,
// that the sections appear in the intended order, or that a swipe deletes the right row on a
// device. The ordering and the delete are device-verified only.

import Foundation
import XCTest

final class LibraryAutosaveSectionTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// ⭐ THE DATA-LOSS GUARD. Both halves in ONE test on purpose: a split list with one
    /// whole-array delete handler is the defect, and neither assertion alone describes it.
    func testEachLibrarySectionDeletesOutOfItsOwnArray() throws {
        let body = try openSheetBody()
        for slice in ["saved[$0].id", "autosaved[$0].id"] {
            XCTAssertTrue(body.contains { $0.contains(slice) }, """
            the library's delete handler no longer maps through `\(slice)`. With the list split \
            into two sections, an `IndexSet` is an index into ITS OWN section — mapping it into \
            the full `projects.projects` deletes a different project than the one swiped, and \
            nothing on screen says so.
            """)
        }
        XCTAssertFalse(body.contains { $0.contains("projects.projects[$0]") }, """
        the whole-array delete handler is back inside `openSheet`. That was correct only while \
        ONE `ForEach` covered the entire array. If the sections were merged again deliberately, \
        delete this assertion in that commit — do not leave both shapes in the file.
        """)
    }

    /// The split itself, matched on the constant rather than on any display string — "Autosave"
    /// is copy and will be localised (#232/#283); `Project.autosaveSlotID` is code.
    func testTheAutosaveSlotIsSeparatedFromTheUsersOwnSaves() throws {
        let body = try openSheetBody()
        XCTAssertEqual(body.filter { $0.contains("Project.autosaveSlotID") }.count, 2, """
        `openSheet` no longer splits the library on `Project.autosaveSlotID` in exactly two \
        places (the user's saves, and the autosave slot). Without the split the autosave sits \
        at the top of a newest-first list and is re-stamped on EVERY app switch (#273), so it \
        permanently outranks the take the user made — which is #285.
        """)
    }

    /// Lines of `openSheet`'s body: from its declaration to the next member declaration.
    /// Scoping matters — the same tokens appear in `autosaveTake()` further down the file, and
    /// a whole-file scan would pass on those while `openSheet` had been reverted.
    private func openSheetBody() throws -> [String] {
        let lines = try codeLines(Self.studio)
        guard let start = lines.firstIndex(where: { $0.contains("private var openSheet") }) else {
            XCTFail("`openSheet` is gone from \(Self.studio) — that is the saved-projects "
                    + "library. If it was renamed, move this guard with it.")
            return []
        }
        let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("    private ") } ?? lines.endIndex
        return Array(lines[start..<end])
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`, three levels
    /// up: CISmoke → Tests → repo).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("source tree not present at \(sources.path) — this test inspects "
                          + "source text, so it SKIPS rather than reporting a green it did "
                          + "not earn")
        }
        return root
    }

    /// Every line of `path` that is not a whole-line comment. Load-bearing here: the ⛔ prose
    /// directly above `openSheet` quotes `Project.autosaveSlotID` and the delete trap by name,
    /// so without the filter both assertions would pass on the explanation after the code it
    /// explains had been reverted.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }
}
