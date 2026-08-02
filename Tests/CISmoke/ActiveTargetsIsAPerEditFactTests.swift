// ActiveTargetsIsAPerEditFactTests.swift
// Echoel — the 30 Hz bio-FX driver must not rebuild collections per tick. BLOCKING bundle. #388.
//
// THE DEFECT. `FXBioModulator.activeTargets` was a COMPUTED property, read once per `tick()`
// — every 33 ms — and each read ran `routes.filter { … }` (one array), `.map { … }` (a second
// array) and wrapped the result in a `Set` (a third allocation). On the main actor. The set it
// produced can only change when `routes` changes, so 29 of every 30 rebuilds a second threw
// away a value identical to the last one.
//
// ⛔ WHY THIS IS A GUARD AND NOT JUST A COMMIT. The rule was ALREADY WRITTEN IN THIS FILE'S
// SUBJECT, a few declarations below the offender: `pruneRouteFades`'s doc says in as many
// words that doing exactly this per tick "built an array, a map, a `Set` and a fresh dictionary
// 30× a second on the main actor — pure garbage for a per-edit fact, on the actor this app has
// a documented starvation law about". That note was written about the fade pruning, it was
// correct, and its own neighbour went on doing the same thing. A rule placed next to the one
// site that already obeys it does not find the site that does not — so the rule gets a test.
//
// The starvation law is not theoretical here: 10.76.48 was a shipped freeze where main-actor
// pressure from a high-rate producer stopped an open `.menu` Picker from responding.
//
// ⚠️ WHY A SOURCE SCAN. `activeTargets`, `routes`'s `didSet` and `tick()` are all private on a
// `@MainActor @Observable` class that is constructed once from `EchoelmusicApp`, and there is no
// local toolchain to build a host with. House pattern — same as `BioFXReachesEveryChainTests`,
// `FXPanelReachesEveryChainTests`, `SoundPanelReflowsTests`. It proves the shape is WRITTEN; it
// cannot measure an allocation.

import Foundation
import XCTest

final class ActiveTargetsIsAPerEditFactTests: XCTestCase {

    private static let driver = "Sources/Echoelmusic/Tools/FXBioModulator.swift"

    /// ⭐ STORED, NOT COMPUTED. The needle is the trailing `= []`, and the negative half is the
    /// one that actually catches a revert: a computed property's declaration ends in `{`.
    func testActiveTargetsIsAStoredCache() throws {
        let lines = try codeLines(Self.driver)
        let decls = lines.filter { $0.contains("var activeTargets") }
        XCTAssertEqual(decls.count, 1, """
            expected exactly one declaration of `activeTargets` in \(Self.driver), found \
            \(decls.count):
            \(decls.map { $0.trimmingCharacters(in: .whitespaces) })
            """)
        let decl = decls[0].trimmingCharacters(in: .whitespaces)
        XCTAssertFalse(decl.hasSuffix("{"), """
            `activeTargets` declaration ends in `{` — it is a computed property again (#388):
            \(decl)

            `tick()` reads it every 33 ms, so a computed body runs filter + map + Set thirty \
            times a second on the main actor, for a value that can only change when the user \
            edits a route. That is the exact construct the note on `pruneRouteFades` in the \
            same file forbids.

            (A stored property with a `didSet` observer would also end in `{` and fail here. \
            That is deliberate: this cache has one writer, `refreshActiveTargets()`, and an \
            observer on it would be a second one.)
            """)
        XCTAssertTrue(decl.contains("@ObservationIgnored"), """
            the `activeTargets` cache is no longer `@ObservationIgnored`:
            \(decl)

            It is internal driver state written from `reconcileBases`. Without the attribute the \
            `@Observable` macro tracks it, and a write would notify observers of a fact no view \
            is entitled to — the class already marks every other piece of internal state this way.
            """)
    }

    /// ⛔ THE TICK MUST ONLY READ. Checking the declaration alone is not enough: a future edit
    /// could keep the stored property and rebuild the set inline in the tick anyway, which is
    /// the original defect wearing the fix as a disguise.
    func testTheTickDoesNotRebuildTheSet() throws {
        let tick = try memberBody(startingWith: "private func tick()", in: Self.driver)
        XCTAssertFalse(tick.isEmpty, "`tick()` not found in \(Self.driver)")
        XCTAssertTrue(tick.contains(where: { $0.contains("let active = activeTargets") }), """
            `tick()` no longer reads the `activeTargets` cache:
            \(tick.joined(separator: "\n"))
            """)
        let builders = tick.filter { $0.contains("Set(") || $0.contains("activeTargets =") }
        XCTAssertTrue(builders.isEmpty, """
            `tick()` builds a collection again (#388) — this body runs every 33 ms on the main \
            actor:
            \(builders.map { $0.trimmingCharacters(in: .whitespaces) })
            """)
    }

    /// ⭐ THE ORDERING, which is the half a token check cannot see. `reconcileBases()` returns
    /// early when no chain is bound. Refreshing the cache BELOW that guard would leave it
    /// holding the pre-edit set until the next `attach()` — and `tick()` reads it as truth, so
    /// a route the user just enabled would never be driven. `pruneRouteFades()` already sits
    /// above the guard for the identical reason; this asserts the new call joined it there
    /// rather than landing in the "chain is bound" half.
    func testTheCacheIsRefreshedAboveTheChainGuard() throws {
        let body = try memberBody(startingWith: "private func reconcileBases()", in: Self.driver)
        XCTAssertFalse(body.isEmpty, "`reconcileBases()` not found in \(Self.driver)")
        guard let refresh = body.firstIndex(where: { $0.contains("refreshActiveTargets()") }) else {
            return XCTFail("""
                `reconcileBases()` no longer refreshes the `activeTargets` cache (#388). The \
                `routes` `didSet` is the only writer path, so without this call the cache \
                freezes at whatever it held when the last chain was attached:
                \(body.joined(separator: "\n"))
                """)
        }
        guard let guardIdx = body.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("guard !allChains.isEmpty")
        }) else {
            return XCTFail("""
                the `guard !allChains.isEmpty` early return is gone from `reconcileBases()`. If \
                that is deliberate, this ordering check no longer describes anything — rewrite \
                it against whatever now separates the bound and unbound halves, do not delete it:
                \(body.joined(separator: "\n"))
                """)
        }
        XCTAssertLessThan(refresh, guardIdx, """
            `refreshActiveTargets()` moved BELOW the chain guard in `reconcileBases()`.

            A route edit is a fact about `routes`, not about whether a chain happens to be bound \
            yet. Below the guard, an edit made before `attach()` leaves the cache stale, and the \
            30 Hz tick reads that stale set as the list of targets to drive.
            \(body.joined(separator: "\n"))
            """)
    }

    /// The reachability half. The cache is only correct because `routes`'s `didSet` runs
    /// `reconcileBases()` on every mutation — including `routes[i].enabled = false`, since
    /// `FXModRoute` is a struct. Without that edge the two checks above guard a dead path.
    func testRouteEditsReachTheRefresh() throws {
        let body = try memberBody(startingWith: "public var routes:", in: Self.driver)
        XCTAssertTrue(body.contains(where: { $0.contains("didSet") && $0.contains("reconcileBases()") }), """
            the `routes` property no longer calls `reconcileBases()` from its `didSet`:
            \(body.joined(separator: "\n"))

            That observer is the ONLY thing keeping the `activeTargets` cache in step with the \
            user's route edits. Remove it and the cache is a stale snapshot with no writer.
            """)
    }

    // MARK: - Source helpers

    /// Lines of a member, from the line that starts with `prefix` to the closing `}` at that
    /// line's OWN indentation. Structural, not a line count.
    private func memberBody(startingWith prefix: String, in path: String) throws -> [String] {
        let lines = try codeLines(path)
        guard let start = lines.firstIndex(where: { $0.contains(prefix) }) else {
            XCTFail("""
                `\(prefix)` is gone from \(path). If it was renamed, move this guard with it — \
                do not leave a check for a member that no longer exists.
                """)
            return []
        }
        let indent = lines[start].prefix { $0 == " " }.count
        let close = lines[(start + 1)...].firstIndex {
            $0.trimmingCharacters(in: .whitespaces) == "}"
                && $0.prefix { c in c == " " }.count == indent
        } ?? lines.endIndex
        return Array(lines[start..<close])
    }

    /// Every line that is not a whole-line comment. Load-bearing here: the driver's ⛔ blocks
    /// quote `activeTargets`, `Set`, `filter` and the old computed wording verbatim while
    /// explaining them, and a scan that read them would count the explanation as the code.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
                source tree not present at \(sources.path) — this test inspects source text, so \
                it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }
}
