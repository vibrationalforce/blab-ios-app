// TheTimelineStoresLiveSurfaceTests.swift
// Echoel — #870. `TimelineStore` declares 58 methods and 42 of them have no caller.
//
// WHY THAT IS NOT A BUG REPORT. The 42 are one coherent set — add/remove/move/resize/split/
// merge region, mute/solo/arm, the per-lane dials, the whole automation API — i.e. the API of
// the arrangement surface that #121 Slice 4 deliberately deleted. The store's DOCUMENT, its
// migration and its save path stayed live; the editing API outlived its UI. That is a
// recorded state, not rot, and the full reasoning (including why the #527 "a persisted
// document can still reach it" argument does NOT apply to mutators) is in the header of
// `Core/TimelineStore.swift`.
//
// ⭐ WHAT THIS FILE ACTUALLY GUARDS, and it is the opposite of what its subject suggests: not
// the dead 42, but the LIVE 10. A store method losing its last caller is the invisible
// regression here — the capability does not break loudly, it just stops being reachable and
// joins the pile, and the next census reads "43 caller-less" as if that were always true.
// `persist` alone is called from nine files; if that went quiet, the timeline would stop
// saving and nothing else in the suite would say so.
//
// ⛔ NO ASSERTION HERE FORBIDS WORK (#364). Dooring a lane dial is exactly what the founder's
// "mehrere" ask points at, and building it is welcome; the counterweight below goes red on
// that day ON PURPOSE, and its message names the prose that must move with it. Deleting the
// 42 is also a legitimate call — it belongs to the founder, not to a cleanup pass.
//
// ⚠️ WHAT THIS FILE CANNOT DO. It reads source text. A caller inside a `#if` that never
// compiles still counts as a caller here, and a call reached only from dead code counts too.
// It proves a NAME is referenced, never that the path runs.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheTimelineStoresLiveSurfaceTests: XCTestCase {

    private static let sourcesRoot = "Sources/Echoelmusic"
    private static let storePath = "Sources/Echoelmusic/Core/TimelineStore.swift"

    /// The ten measured on 2026-08-29 as having a caller OUTSIDE the store's own file.
    private static let liveSurface = [
        "addRegion", "ensureComposerRegion", "flushPendingSave",
        "healRollSlotAudibility", "healRollSlotNamingCause", "persist",
        "snapshotForUndo", "undo", "redo", "unsilenceRollSlot",
    ]

    // MARK: - The live surface

    /// Every one of the ten still has an external caller. Losing one is a capability going
    /// doorless in silence — the failure mode this whole file exists for.
    func testEveryLiveStoreMethodStillHasAnExternalCaller() throws {
        for name in Self.liveSurface {
            let callers = try filesCalling(name)
            XCTAssertFalse(callers.isEmpty, """
                `TimelineStore.\(name)` no longer has a caller outside its own file. It had \
                one on 2026-08-29, so a capability just went doorless without breaking a \
                build. Either restore the call, or move it into the header's caller-less \
                list in `Core/TimelineStore.swift` IN THIS COMMIT and drop it from \
                `liveSurface` here — an undocumented move is how 42 of them got there.
                """)
        }
    }

    /// The save path is the one whose loss is silent AND destructive: the document simply
    /// stops being written. Pinned as a FLOOR (≥2), not the measured nine — a caller count is
    /// a date, and this repo has paid for reciting those before.
    func testTheSavePathIsCalledFromSeveralPlaces() throws {
        let callers = try filesCalling("persist")
        XCTAssertGreaterThanOrEqual(callers.count, 2, """
            `TimelineStore.persist` is called from \(callers.count) file(s) outside the store \
            (\(callers.joined(separator: ", "))). It was nine. A collapse to one or zero means \
            most edits no longer reach the disk — the timeline would look right in memory and \
            be gone after relaunch, which no other test in this bundle would notice.
            """)
    }

    // MARK: - Counterweight (#343) — the dead half must still be dead, or the header is stale

    /// ONE representative of the 42, not all of them (#486: one absence is one finding, and
    /// forty-two assertions of the same absence is noise that hides the one that matters).
    /// `setLanePan` is chosen because it is a per-lane dial — the exact thing a "mehrere"
    /// surface would door first, so this is the assertion most likely to go red for a GOOD
    /// reason.
    func testTheLaneDialsAreStillUnreachable() throws {
        let callers = try filesCalling("setLanePan")
        XCTAssertTrue(callers.isEmpty, """
            `TimelineStore.setLanePan` now has a caller: \(callers.joined(separator: ", ")). \
            If a lane surface was built, this red is CORRECT and welcome — it is not an \
            objection. It is a checklist: the header of `Core/TimelineStore.swift` says 42 \
            methods have no caller and names the per-lane dials among them, so that block \
            moves in this same commit, and this method joins `liveSurface` above.
            """)
    }

    /// The header's claim rests on the declarations actually existing. If the file were
    /// gutted, every assertion above would pass vacuously on an empty set (#343).
    func testTheStoreStillDeclaresAWholeEditingAPI() throws {
        let text = SourceText.codeOnly(try rawText(Self.storePath))
        let declarations = text.components(separatedBy: "func ").count - 1
        XCTAssertGreaterThan(declarations, 40, """
            `TimelineStore` now declares only \(declarations) methods. The header records 59 \
            declarations under 58 names (`moveRegion` is overloaded), 42 of them caller-less; \
            a large drop means someone took the deletion decision that the header says \
            belongs to the founder. If that was deliberate, rewrite the header block — do not \
            lower this threshold to match.
            """)
    }

    // MARK: - Reading the source

    /// Files under `Sources/` OTHER than the store itself that name `name(` in CODE.
    /// Dot-independent on purpose: a caller could be an extension of the same type.
    private func filesCalling(_ name: String) throws -> [String] {
        let root = try repoRoot()
        let sources = root.appendingPathComponent(Self.sourcesRoot)
        guard let walker = FileManager.default.enumerator(atPath: sources.path) else {
            throw XCTSkip("cannot enumerate \(Self.sourcesRoot) — refusing to report a green it did not earn")
        }
        var hits: [String] = []
        for case let relative as String in walker where relative.hasSuffix(".swift") {
            if relative.hasSuffix("Core/TimelineStore.swift") { continue }
            guard let text = try? String(contentsOf: sources.appendingPathComponent(relative), encoding: .utf8)
            else { continue }
            if Self.callsFunction(named: name, in: SourceText.codeOnly(text)) { hits.append(relative) }
        }
        return hits.sorted()
    }

    /// `code.contains("undo(")` is TRUE for `canUndo(` — a substring needle would have
    /// reported a caller that does not exist, and for the counterweight below the same class
    /// of error reports a door that was never built. So the character before the name must
    /// not be an identifier character. (#679/#738: an invented needle that cannot match its
    /// target is the same defect as one that matches too much.)
    private static func callsFunction(named name: String, in code: String) -> Bool {
        var searchStart = code.startIndex
        while let found = code.range(of: "\(name)(", range: searchStart..<code.endIndex) {
            if found.lowerBound == code.startIndex { return true }
            let before = code[code.index(before: found.lowerBound)]
            if !(before.isLetter || before.isNumber || before == "_") { return true }
            searchStart = found.upperBound
        }
        return false
    }

    private func rawText(_ relativePath: String) throws -> String {
        let url = try repoRoot().appendingPathComponent(relativePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("\(relativePath) not readable at \(url.path) — source scan skipped")
        }
        return text
    }

    private func repoRoot() throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
