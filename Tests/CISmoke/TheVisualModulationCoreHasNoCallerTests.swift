// TheVisualModulationCoreHasNoCallerTests.swift
// Echoel — a bio→visual routing core that nothing in the app calls. #921.
//
// WHAT THIS GUARDS, and it is a REGISTER gap rather than a code defect. `Core/VisualModulation`
// is a complete, tested bio→visual routing core: `VisualModRoute`, `VisualModTarget`, curves,
// hue wrap, an `isMeasured` gate matching the FX driver's. Measured 2026-08-31, code-only:
// **ZERO** `VisualModRoute(` construction sites in `Sources/` and **ZERO** callers of
// `VisualModulation.apply`. Its only two mentions under `Sources/` are comments in
// `Core/EngineBus.swift`, and one of them says so outright — "that core has no caller yet — it
// is a guard for when the visual path is wired, not a fix anyone has seen."
//
// ⭐ SO THE SOURCE WAS HONEST AND THE REGISTER WAS NOT. `CLAUDE.md`'s list of "genuinely
// app-unwired pure cores remaining" named BioModulation, CloudSync and `Core/BioSpaceMap` — not
// this one. That is the #867 pattern: a register line is the list a session reads BEFORE it
// looks at the source, so a gap in it never even becomes a question. It is also the specific
// trap this core sits in: the register truthfully says **`BioVisualParams` is wired**, so a
// session skimming for "is bio→visual live?" reads yes and can reasonably assume THIS is the
// mechanism. Two mechanisms, one wired, one not, and only one of them named.
//
// ⚠️ NOT AN ARGUMENT FOR DELETION. The core carries the `isMeasured` law in the exact shape the
// visual path will need — `Core/EngineBus.swift` calls it "a guard for when the visual path is
// wired" — and its own `apply` documents an asymmetry no future author should have to
// rediscover: skipping an unmeasured route is NOT identity, because `touched` stays false, and
// `combine` is not a no-op at offset 0 (`.hue` wraps, the rest clamp).
//
// ⚠️ AND IT DOES NOT FORBID WIRING IT (#364). Giving the core a caller is exactly the work this
// finding argues for. When these assertions go red for that reason, the fix is to move the
// register line in `CLAUDE.md` and the note in `Core/EngineBus.swift` IN THE SAME COMMIT — not
// to relax the assertion. One thing the wiring slice must decide, and it is the #920c lesson on
// this path: `bus.latestBio` INTERLEAVES (HealthKit is never stopped by `stopBioSource()` and
// publishes `coherence: 0`), so a per-frame skip would snap the target back to base every few
// seconds. `Tools/FXBioModulator` already solved that with a hold-and-fade; this core does not
// have one yet, and a wiring slice that does not add one ships a visible flicker.
//
// ⚠️ HONEST GRADING (#433/#464/#486). This file COMPILES against the parent tree — it names no
// symbol this commit adds — so every assertion has a verdict there, and **all of them are green
// on both trees**. That is stated rather than dressed up: this commit changes no behaviour, it
// records a measurement and pins it. The value is entirely in the counterweights (#343) — a
// tree that wires the core, or that deletes it as dead, or that lets the honest `EngineBus`
// note drift, turns one of these red.
//
// ⚠️ WHAT NO TEST HERE CAN SAY: whether the visual path SHOULD be wired. That is a product call
// and the ship gate already answers it for v1 ("light/space demonstrable, not required").

import Foundation
import XCTest
@testable import Echoelmusic

final class TheVisualModulationCoreHasNoCallerTests: XCTestCase {

    private static let sourcesRoot = "Sources/Echoelmusic"
    private static let coreFile = "Sources/Echoelmusic/Core/VisualModulation.swift"
    private static let busFile = "Sources/Echoelmusic/Core/EngineBus.swift"

    // MARK: - the measurement

    func testNoProductionCodeConstructsAVisualModRoute() throws {
        let hits = try filesUnderSources(containing: "VisualModRoute(")
        XCTAssertEqual(hits, [], """
            Something in Sources/ now builds a visual modulation route: \(hits). That is a real \
            capability arriving, not a defect — and this guard's job is to make sure the PROSE \
            arrives with it. In the same commit: add the core to CLAUDE.md's wired side (it is \
            currently absent from the unwired list, which is the gap #921 recorded), and update \
            the "no caller yet" note in Core/EngineBus.swift. Then decide the interleaving \
            question named in this file's header before shipping.
            """)
    }

    func testNoProductionCodeAppliesTheCore() throws {
        let hits = try filesUnderSources(containing: "VisualModulation.apply")
        XCTAssertEqual(hits, [], """
            Something in Sources/ now applies the visual modulation core: \(hits). See the \
            message on the route-construction claim — the same prose moves in the same commit.
            """)
    }

    // MARK: - counterweights: the core and its honest note must both still be there

    func testTheCoreStillExists() throws {
        let text = try rawText(Self.coreFile)
        XCTAssertTrue(text.contains("public static func apply(routes:"), """
            Core/VisualModulation.swift no longer exposes `apply`. If the core was deleted as \
            dead, that threw away the isMeasured law in the exact shape the visual path needs, \
            plus the documented non-identity of a skipped route (`touched` stays false and \
            `combine` is not a no-op at offset 0 — `.hue` wraps). Doorless is not the same as \
            worthless; this file's header says why.
            """)
    }

    func testTheSkipIsStillDocumentedAsNonIdentity() throws {
        let text = try rawText(Self.coreFile)
        XCTAssertTrue(text.contains("skipping is not QUITE identity"), """
            The note that a skipped route is NOT the same as a zero-offset route is gone from \
            Core/VisualModulation.swift. It is the one behavioural surprise in this core and \
            the reason a wiring slice cannot treat an unmeasured frame as a no-op.
            """)
    }

    func testTheBusNoteStillSaysTheCoreHasNoCaller() throws {
        let text = try rawText(Self.busFile)
        XCTAssertTrue(text.contains("that core has no"), """
            Core/EngineBus.swift no longer records that VisualModulation has no caller. That \
            note is the only place in Sources/ that stated it, and it was correct for months \
            while CLAUDE.md's register omitted the core entirely — which is exactly why #921 \
            pinned it here instead of trusting one comment to survive alone.
            """)
    }

    func testTheGateTheCoreSharesWithTheFXDriverIsStillThere() throws {
        let text = try rawText(Self.coreFile)
        XCTAssertTrue(SourceText.codeOnly(text).contains("source.isMeasured(in: bio)"), """
            Core/VisualModulation no longer gates on isMeasured. That gate is the whole reason \
            the core is worth keeping unwired: a bipolar route on a channel the body never \
            reported would otherwise pin its target to the bottom of range forever, which is \
            the defect the FX path had to be repaired for.
            """)
    }

    // MARK: - helpers

    private func filesUnderSources(containing needle: String) throws -> [String] {
        let root = try repoRoot().appendingPathComponent(Self.sourcesRoot)
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            throw XCTSkip("cannot enumerate \(Self.sourcesRoot) — refusing to report a green it did not earn")
        }
        var hits: [String] = []
        for case let relative as String in walker where relative.hasSuffix(".swift") {
            guard let text = try? String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            else { continue }
            if SourceText.codeOnly(text).contains(needle) { hits.append(relative) }
        }
        return hits.sorted()
    }

    private func rawText(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("""
                \(relativePath) is not present — this guard inspects source text, so it SKIPS \
                rather than reporting a green it did not earn (#454)
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    private func repoRoot() throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
