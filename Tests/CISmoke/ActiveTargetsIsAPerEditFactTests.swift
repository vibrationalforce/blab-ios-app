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

    /// ⭐ STORED, NOT COMPUTED — asserted POSITIVELY, by the trailing `= []`.
    ///
    /// ⛔ THE FIRST VERSION OF THIS TEST ASSERTED THE OPPOSITE OF WHAT ITS OWN DOC CLAIMED.
    /// The doc said "the needle is the trailing `= []`"; the code checked only that the line
    /// does not END in `{`. A single-line computed property ends in `}`, so
    /// `@ObservationIgnored private var activeTargets: Set<FXModTarget> { Set(routes.filter
    /// { $0.enabled }.map { $0.target }) }` — the original defect, byte for byte, on one line
    /// — passed every assertion in this file. Found by the mandatory reviewer, reproduced
    /// here before fixing. A negative needle can be walked around; a positive one names the
    /// shape that must be there.
    func testActiveTargetsIsAStoredCache() throws {
        let lines = try codeLines(Self.driver)
        let decls = lines.filter { $0.contains("var activeTargets") }
        XCTAssertEqual(decls.count, 1, """
            expected exactly one declaration of `activeTargets` in \(Self.driver), found \
            \(decls.count):
            \(decls.map { $0.trimmingCharacters(in: .whitespaces) })
            """)
        let decl = decls[0].trimmingCharacters(in: .whitespaces)
        XCTAssertTrue(decl.hasSuffix("= []"), """
            `activeTargets` is not a plain stored property initialised to `[]` (#388):
            \(decl)

            `tick()` reads it every 33 ms, so a computed body runs filter + map + Set thirty \
            times a second on the main actor, for a value that can only change when the user \
            edits a route. That is the exact construct the note on `pruneRouteFades` in the \
            same file forbids.

            This asserts the SHAPE, not the absence of one. A `didSet` observer or a computed \
            body both fail here, deliberately: the cache has exactly one writer, \
            `refreshActiveTargets()`, and either would be a second one.
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
    ///
    /// ⛔ THE FIRST VERSION BANNED TWO TOKENS AND LET FOUR BYPASSES THROUGH, all of them
    /// plausible edits rather than contrivances: calling `refreshActiveTargets()` from inside
    /// the tick (contains neither banned token, and rebuilds the Set every 33 ms just the
    /// same); `Set<FXModTarget>(…)`, which does not contain the substring `Set(`; a per-tick
    /// `activeTargets.filter { … }`, which allocates without constructing; and — because the
    /// positive needle was a PREFIX match — renaming the read to `activeTargetsNow`, a fresh
    /// computed property, while `let active = activeTargetsNow` still "contains" the needle.
    /// The needle is now an exact line match and the ban covers allocation, not two spellings
    /// of it.
    func testTheTickDoesNotRebuildTheSet() throws {
        let tick = try memberBody(startingWith: "private func tick()", in: Self.driver)
        XCTAssertFalse(tick.isEmpty, "`tick()` not found in \(Self.driver)")
        let reads = tick.map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertTrue(reads.contains("let active = activeTargets"), """
            `tick()` no longer reads the `activeTargets` cache — the line must be exactly \
            `let active = activeTargets`, so that reading a differently-named (and possibly \
            recomputed) property cannot pass as reading the cache:
            \(tick.joined(separator: "\n"))
            """)
        let banned = ["Set(", "Set<", "activeTargets =", "refreshActiveTargets()", ".filter", ".map"]
        let builders = tick.filter { line in banned.contains(where: { line.contains($0) }) }
        XCTAssertTrue(builders.isEmpty, """
            `tick()` allocates a collection again (#388) — this body runs every 33 ms on the \
            main actor:
            \(builders.map { $0.trimmingCharacters(in: .whitespaces) })

            Banned here: \(banned). If a future edit genuinely needs one of these in the 33 Hz \
            path, hoist the work to a per-edit function the way `refreshActiveTargets()` and \
            `pruneRouteFades()` were hoisted — do not relax the list.
            """)
    }

    /// ⭐ THE CACHE MUST ACTUALLY BE FILLED. Nothing above inspects the BODY of the writer, and
    /// the reviewer's sharpest bypass was `private func refreshActiveTargets() { }` — every
    /// other test green, `activeTargets` permanently empty, `tick()`'s loop never entered, and
    /// so EVERY bio→FX route silently dead with no restore and no error. That is a strictly
    /// worse outcome than the allocation this guard was written about, and the guard could not
    /// see it. Three cycles running, my guards have had a hole; this is the one that would
    /// have cost sound rather than CPU.
    func testTheRefreshActuallyWritesTheCache() throws {
        let body = try memberBody(startingWith: "private func refreshActiveTargets()", in: Self.driver)
        XCTAssertFalse(body.isEmpty, "`refreshActiveTargets()` not found in \(Self.driver)")
        XCTAssertTrue(body.contains(where: { $0.contains("activeTargets = Set(routes") }), """
            `refreshActiveTargets()` no longer writes the cache from `routes`:
            \(body.joined(separator: "\n"))

            An empty body here passes every other test in this file and switches off all \
            bio-reactive FX: the tick iterates an empty target set, so nothing is driven and \
            nothing is restored. Silent, total, and invisible to the user.
            """)
    }

    /// ⭐ NOTHING MAY RETURN BEFORE THE REFRESH. A route edit is a fact about `routes`, not
    /// about whether a chain happens to be bound — so `refreshActiveTargets()` must run on
    /// EVERY entry into `reconcileBases()`, unconditionally, the same way `pruneRouteFades()`
    /// does.
    ///
    /// ⛔ TWO CORRECTIONS TO THE FIRST VERSION, both from the reviewer.
    /// (1) It only compared the refresh against ONE named guard, so inserting a different
    ///     early return ABOVE the refresh — `guard !routes.isEmpty else { return }` is the
    ///     obvious one — still satisfied "refresh is above `guard !allChains.isEmpty`" while
    ///     producing a genuinely stale cache: delete the last route and `activeTargets` is
    ///     never cleared, so the tick keeps driving targets no route feeds and the restore
    ///     loop never runs. The check is now "no `return` above the refresh at all", which is
    ///     the actual invariant rather than one instance of it.
    /// (2) Its stated REASON was unreachable, and the same false claim stood in the driver.
    ///     Below the chain guard the cache could only go stale while `allChains` is empty, and
    ///     in that state `tick()` has already returned at its own chain guard; the only exit
    ///     is `attach`, which reconciles unconditionally. The placement is robustness and
    ///     symmetry, not a live bug — see the corrected note in `reconcileBases()`.
    func testNothingReturnsBeforeTheRefresh() throws {
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
        let escapesFirst = body[..<refresh].filter { $0.contains("return") }
        XCTAssertTrue(escapesFirst.isEmpty, """
            `reconcileBases()` can now return BEFORE it refreshes the `activeTargets` cache:
            \(escapesFirst.map { $0.trimmingCharacters(in: .whitespaces) })

            Any early exit above the refresh makes the cache stale on the path it takes. The \
            concrete case is `guard !routes.isEmpty else { return }`: delete the last route and \
            `activeTargets` is never cleared, so the 30 Hz tick keeps driving targets no route \
            feeds and `reconcileBases`'s restore loop never runs — the user's FX settings stay \
            parked wherever the last tick left them.

            If a new early exit is genuinely needed, put it BELOW the refresh.
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
