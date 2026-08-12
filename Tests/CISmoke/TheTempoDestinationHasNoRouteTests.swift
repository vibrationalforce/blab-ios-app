// TheTempoDestinationHasNoRouteTests.swift
// Echoel — #541. "ModulationEngine wired (bio→tempo)" was four words claiming a live capability.
//
// WHAT IS ACTUALLY TRUE, measured 2026-08-12. The MACHINE runs, end to end but one:
//   · `ModulationEngine` is constructed at launch and `start(subscribing: bus)` is called;
//   · its loop ticks at 100 ms and evaluates `matrix.routes`;
//   · `ModDestinationKey.tempo` IS registered, and its closure glides `BeatPlayer`'s pattern
//     tempo — behind the global BPM lock and octave-folded, which is the founder's v79.45
//     "die bpm springt nach oben" fix and is load-bearing;
//   · every applied modulation ALSO leaves over OSC as `/echoelmusic/mod/<key>`.
// What is missing is the ROUTE. The default matrix is EMPTY — `ModulationEngine` says so twice
// in its own prose — and `git grep -n "\bModRoute(" -- Sources` finds exactly ONE construction,
// the `LossyDecoded` decoder inside `ModulationMatrix.swift` itself. Nothing in the app creates
// a route, and no surface edits the matrix. So the body cannot drive the tempo today.
//
// ⚠️ THE WORD BOUNDARY IN THAT COMMAND IS PART OF THE MEASUREMENT. Without it the grep also
// matches `FXModRoute(` in `EchoelFXView` — a different type in a different system — and prints
// two lines beside prose that says one. Same trap as the `EchoelModalBank` recipe CLAUDE.md
// already retracts: a quoted command that contradicts its own claim reads as the claim being
// wrong. `routeConstructionSites()` below applies the boundary in code for the same reason.
//
// ⛔ THIS IS NOT A DELETION ARGUMENT, and that is the point of half the assertions here. The
// matrix is PERSISTED and decoded at launch (`load()` wins over the empty default), so a
// document written by a build that had a reachable surface would still pull the tempo. Cutting
// the wiring turns "obviously absent" into "silently mute" — the #527 lesson, second occurrence.
//
// ⚠️ WHAT THIS GUARD DOES NOT DO (#364): it does NOT forbid wiring a producer. Giving the matrix
// a real editor is desirable work. It goes red WHEN that happens, and its failure message names
// the two prose sites that must move in the same commit — the CURRENT STATE line and the
// doorless register in `CLAUDE.md`. A guard that made the fix illegal would be deleted, and the
// record would go with it.
//
// ⚠️ THE LIMIT. Assertions 1–2 are BEHAVIOURAL over a shipped public value type
// (`ModulationEngine`/`ModulationMatrix` are Foundation-only and instantiable here); the rest
// are SOURCE-TEXT SCANS over `EchoelmusicApp`, whose launch closure no test bundle can run.
// Nothing here proves what a device does with a persisted matrix — that is a device probe and
// it is OPEN.
//
// ⚠️ HONEST GRADING. Against `HEAD` this file is a pure FORWARD/COUNTERWEIGHT guard: ZERO
// regressions, because #541 changes prose and adds this file — it changes no code, so every
// assertion below is green on both trees BY CONSTRUCTION. Booking any of them as a regression
// would be the #433 self-flattery. The value is entirely in what they make fail LATER.
//
// ⚠️ `SourceText.codeOnly` is PROPHYLAKTISCH here, measured: **0 of 14** raw-vs-stripped
// verdicts flip (seven source scans × two trees; the two behavioural assertions have no
// raw/stripped variant). Every needle is an exact code expression, and the one negative scan
// counts CONSTRUCTIONS rather than asking whether a phrase is absent. It stays because a future
// ⛔ block quoting `ModRoute(` in a comment — exactly what this repo does when it retracts
// something — would otherwise make `testNothingInTheAppConstructsAModulationRoute` red on
// correct code. The transcription also confirmed the walker floor: 348 Swift files under
// `Sources/Echoelmusic`, against the `> 200` guard below.

import XCTest
@testable import Echoelmusic

final class TheTempoDestinationHasNoRouteTests: XCTestCase {

    private static let app = "Sources/Echoelmusic/EchoelmusicApp.swift"
    private static let engine = "Sources/Echoelmusic/Core/ModulationEngine.swift"

    // MARK: - behaviour: a fresh engine routes nothing

    /// The claim in one line. A default-constructed engine has no routes, so a bio frame moves
    /// nothing — which is what "wired but doorless" means and what the old CURRENT STATE line
    /// denied.
    func testAFreshMatrixCarriesNoRoutes() {
        XCTAssertTrue(ModulationMatrix().routes.isEmpty, """
            The default `ModulationMatrix` now ships routes. That is a real capability change: \
            the body would start driving whatever they target on first launch. Update the \
            CURRENT STATE line in CLAUDE.md ("verdrahtet, türlos, ohne Route wirkungslos") and \
            the doorless register's modulation entry in the same commit.
            """)
    }

    /// THE COUNTERWEIGHT THAT KEEPS THE FIRST ONE HONEST (#343). "No routes" is only meaningful
    /// while the destination KEY still exists — a tree that deleted `seq.tempo` would also pass
    /// assertion one, having removed the capability rather than left it doorless.
    func testTheTempoDestinationKeyStillExists() {
        XCTAssertEqual(ModDestinationKey.tempo, "seq.tempo", """
            The tempo destination key changed or vanished. It is the address the OSC mod-out \
            publishes (`/echoelmusic/mod/seq.tempo`, listed in CLAUDE.md's OSC section as real) \
            and the key the launch closure registers against — three places, one string.
            """)
    }

    // MARK: - the machine that is genuinely wired (counterweights)

    /// Registering the sink is what makes this "doorless" rather than "absent". Deleting it
    /// would be a quiet capability removal that no other check would notice.
    func testTheLaunchStillRegistersTheTempoDestination() throws {
        let src = try source(Self.app)
        XCTAssertTrue(src.contains("modulationEngine.register(ModDestinationKey.tempo)"), """
            The launch no longer registers the tempo destination. A persisted matrix from an \
            older build would then evaluate its route and dispatch it to nothing — the body \
            would appear to be ignored rather than unrouted.
            """)
        XCTAssertTrue(src.contains("modulationEngine.start(subscribing: bus)"), """
            The modulation engine is no longer started. Everything above becomes moot; say so \
            in CLAUDE.md rather than leaving a CURRENT STATE line describing a running loop.
            """)
    }

    /// The founder's v79.45 fix, pinned as behaviour-shaped source. Both halves matter: the lock
    /// must win, and the target must glide rather than snap.
    func testTheTempoRouteStillObeysTheLockAndGlides() throws {
        let src = try source(Self.app)
        XCTAssertTrue(src.contains("UserDefaults.standard.bool(forKey: \"studio.lockBPM\")"), """
            The bio→tempo destination no longer checks the global BPM lock. That is the exact \
            regression the founder filmed at 79.45: the route fired the instant the pulse \
            locked and overrode a tempo the user had deliberately fixed.
            """)
        XCTAssertTrue(src.contains("glideTempo(to: StudioCalculator.seedTempo(raw))"), """
            The destination no longer octave-folds and glides. Without the fold a normalized \
            signal can demand 196–300 bpm; without the glide the clock snaps mid-take. Both \
            were added together and neither is decoration.
            """)
    }

    /// The mod-out address CLAUDE.md's OSC section lists as REAL depends on this one line.
    func testEveryAppliedModulationStillLeavesOverOSC() throws {
        XCTAssertTrue(try source(Self.app).contains("modulationEngine.outputTap ="), """
            The modulation output tap is gone, so `/echoelmusic/mod/<key>` is never sent — while \
            CLAUDE.md's OSC address set still lists it as a live address with a producer. An \
            integrator waiting on that address would wait forever. Move the OSC section in the \
            same commit.
            """)
    }

    // MARK: - the missing half

    /// The measurement the CURRENT STATE line got wrong for four months.
    ///
    /// ⚠️ Deliberately NOT `XCTAssertEqual(sites, 1)` on a path. It asserts that the only file
    /// constructing a route is the matrix's own decoder — so MOVING that decoder stays green,
    /// while ADDING a producer anywhere goes red and gets told what to do.
    func testNothingInTheAppConstructsAModulationRoute() throws {
        let sites = try routeConstructionSites()
        XCTAssertEqual(sites, ["Core/ModulationMatrix.swift"], """
            `ModRoute(` is now constructed in \(sites.joined(separator: ", ")). If that is a real \
            producer — a matrix editor, a default route, a preset — then the body CAN drive the \
            tempo now and this is good news. Two prose sites must move in the SAME commit: \
            CLAUDE.md's CURRENT STATE line (the ⛔ block that says "verdrahtet, türlos, ohne \
            Route wirkungslos") and the modulation entry in the doorless register. Then relax \
            this expectation to the new set; do NOT delete the test — its four counterweights \
            above still guard the lock, the glide and the OSC tap.
            """)
    }

    /// A name that suggests a surface but is not one. Recorded because looking for the matrix
    /// UI and finding this file is how a session concludes the door exists.
    func testBioModulationIsAValueFileAndNotASurface() throws {
        let src = try source("Sources/Echoelmusic/Studio/BioModulation.swift")
        XCTAssertFalse(src.contains(": View"), """
            `Studio/BioModulation.swift` now declares a `View`. It has been a pair of value \
            types (`ClockSource`, `BoundParameter`) with no external consumer; if it became the \
            matrix surface, the doorless register's modulation entry is now wrong and this \
            guard's premise with it.
            """)
    }

    // MARK: - source access

    private struct RouteAnchorMissing: Error { let reason: String }

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

    /// Comment-stripped source (#453); a SKIP without a checkout, a FAILURE when the file moved
    /// (#454 — a skip passes CI, so "no tree" may skip and "my anchor was renamed" may not).
    private func source(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw RouteAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// Files under `Sources/Echoelmusic/` that CONSTRUCT a `ModRoute`, as paths relative to that
    /// directory, sorted.
    ///
    /// ⚠️ THE BOUNDARY CHECK IS THE WHOLE POINT: a plain `contains("ModRoute(")` also matches
    /// `FXModRoute(`, an unrelated type in the FX system, and would report a producer that is
    /// not one. The character before the match must not be a letter, digit or underscore.
    private func routeConstructionSites() throws -> [String] {
        let base = try repoRoot().appendingPathComponent("Sources/Echoelmusic")
        guard let walker = FileManager.default.enumerator(atPath: base.path) else {
            throw RouteAnchorMissing(reason: "cannot walk Sources/Echoelmusic")
        }
        var hits: [String] = []
        var seen = 0
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            seen += 1
            let text = SourceText.codeOnly(
                try String(contentsOf: base.appendingPathComponent(rel), encoding: .utf8))
            if constructsRoute(text) { hits.append(rel) }
        }
        // A walker that yielded nothing would report "no producers" over an empty list — the
        // silent-pass failure this bundle exists to prevent.
        guard seen > 200 else {
            throw RouteAnchorMissing(reason: """
                only \(seen) Swift files were walked under Sources/Echoelmusic; the tree holds \
                well over three hundred, so this scan saw almost nothing and its green would be \
                vacuous.
                """)
        }
        return hits.sorted()
    }

    private func constructsRoute(_ text: String) -> Bool {
        var searchStart = text.startIndex
        while let found = text.range(of: "ModRoute(", range: searchStart..<text.endIndex) {
            if found.lowerBound == text.startIndex {
                return true
            }
            let before = text[text.index(before: found.lowerBound)]
            if !(before.isLetter || before.isNumber || before == "_") {
                return true
            }
            searchStart = found.upperBound
        }
        return false
    }
}
