// TheVisualModulationCoreHasNoCallerTests.swift
// Echoel — a bio→visual routing core that nothing in the app calls. #921.
//
// WHAT THIS GUARDS, and it is a REGISTER gap rather than a code defect. `Core/VisualModulation`
// is a complete, tested bio→visual routing core: `VisualModRoute`, `VisualModTarget`, curves,
// hue wrap, an `isMeasured` gate matching the FX driver's. Measured 2026-08-31, code-only:
// **ZERO** `VisualModRoute(` construction sites in `Sources/` and **ZERO** callers of
// `VisualModulation.apply`. Its only two mentions under `Sources/` OUTSIDE ITS OWN FILE are
// comments in `Core/EngineBus.swift`, and one of them says so outright — "that core has no
// caller yet — it is a guard for when the visual path is wired, not a fix anyone has seen."
// ⛔ "outside its own file" is not padding: without it the sentence is FALSE, because
// `git grep VisualModulation -- Sources` returns four lines and one of them is the declaration
// `public enum VisualModulation`. #856/#867 are both this — a measurement quoted one qualifier
// short reads as a different, wrong measurement.
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
// note drift, or that quietly drops the register entry, turns one of these red. **Driven as
// eight mutants, not predicted** (#808): deletion → 4 red · a constructed route → 2 red · a
// DECODED `[VisualModRoute]` with no constructor literal → 1 red · an `apply` call → 1 red ·
// the register entry removed → 1 red · each of the three prose anchors removed → 1 red.
// ⛔ THE DELETION MUTANT SURVIVED THE FIRST DRAFT, and this paragraph claimed it did not.
// `rawText` throws `XCTSkip` when a file is absent, so deleting the core SKIPPED three claims,
// left the two scans green on "no hits", and passed the suite — while this very sentence named
// deletion as one of the three trees the counterweights catch. A skip is not a pass (#806), and
// the rule was already written down in `.claude/rules/context.md` §4. The existence check is an
// ASSERTION now, ahead of the skip path.
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
            arrives with it. In the same commit: MOVE the core from CLAUDE.md's unwired list to \
            the wired side — #921 put it on the unwired list, so adding it to the wired side \
            without removing it there makes the register claim both at once — and update the \
            "no caller yet" note in Core/EngineBus.swift. Then decide the interleaving question \
            named in this file's header before shipping. \
            (⛔ The first version of this message said the core was "currently absent from the \
            unwired list". That was true when it was drafted and false by the time the same \
            commit landed, because that commit is what added the entry. A repair instruction \
            that describes the tree BEFORE its own commit is #818 in its most direct form.)
            """)
    }

    func testNoProductionCodeAppliesTheCore() throws {
        let hits = try filesUnderSources(containing: "VisualModulation.apply")
        XCTAssertEqual(hits, [], """
            Something in Sources/ now applies the visual modulation core: \(hits). See the \
            message on the route-construction claim — the same prose moves in the same commit.
            """)
    }

    /// ⚠️ THE TWO SCANS ABOVE HAVE ESCAPE HATCHES, so this closes the likely one. A wiring
    /// slice that DECODES a persisted `[VisualModRoute]` writes no `VisualModRoute(` literal,
    /// and one that calls `apply(routes:)` unqualified from inside an `extension
    /// VisualModulation` writes no `VisualModulation.apply`. `VisualModRoute` is `Codable`, so
    /// the persisted-store path is the plausible one, not a theoretical one.
    func testNoProductionCodeNamesTheRouteTypeAtAll() throws {
        // ⚠️ EXCLUDING THE CORE'S OWN FILE IS REQUIRED, not tidiness: this needle is the bare
        // type name, and `Core/VisualModulation.swift` DECLARES it. Without the exclusion the
        // claim is red on a correct tree — the #364 failure in its purest form, written by the
        // same slice that quotes #364 in its header.
        let hits = try filesUnderSources(containing: "VisualModRoute", excluding: Self.coreFile)
        XCTAssertEqual(hits, [], """
            Sources/ now names the visual route type: \(hits). See the message on the \
            construction claim — the same prose moves in the same commit. This needle is the \
            broad one on purpose: it catches a decoded `[VisualModRoute]` that never writes a \
            constructor literal.
            """)
    }

    // MARK: - counterweights: the core and its honest note must both still be there

    func testTheCoreFileIsPresentAndStillDeclaresApply() throws {
        // ⛔ THE FIRST DRAFT OF THIS CLAIM COULD NOT FAIL FOR THE SCENARIO THE HEADER NAMED.
        // `rawText` throws `XCTSkip` when the file is absent, so deleting the core turned this
        // claim — and two of its neighbours — into SKIPS while the two scan claims went green on
        // "no hits", and the suite passed. A skip is not a pass (#806), and the header called
        // deletion one of the three trees these counterweights catch. The existence check is
        // therefore an ASSERTION here, before the skip path can swallow it.
        let path = try repoRoot().appendingPathComponent(Self.coreFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path), """
            \(Self.coreFile) has been deleted. If it went as "dead code", that threw away the \
            isMeasured law in the exact shape the visual path needs and the documented \
            non-identity of a skipped route. Doorless is not worthless — this file's header and \
            memory/LEDGER_COUNTS.md §M both say why, and neither was consulted if this is red.
            """)
        let text = try rawText(Self.coreFile)
        XCTAssertTrue(SourceText.codeOnly(text).contains("public static func apply(routes:"), """
            Core/VisualModulation.swift no longer declares `apply` in CODE (the needle is read \
            through the comment stripper, so a mention in prose cannot satisfy it). The core \
            without its entry point is not the core.
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

    func testTheBusStillRecordsThatTheCoreIsUncalled() throws {
        let text = try rawText(Self.busFile)
        XCTAssertTrue(text.contains("that core has no"), """
            Core/EngineBus.swift no longer records that VisualModulation has no caller. That \
            note is the only place in Sources/ that stated it, and it was correct for months \
            while CLAUDE.md's register omitted the core entirely — which is exactly why #921 \
            pinned it here instead of trusting one comment to survive alone.
            """)
    }

    func testTheCoreSideOfTheSharedMeasuredGateIsStillThere() throws {
        let text = try rawText(Self.coreFile)
        XCTAssertTrue(SourceText.codeOnly(text).contains("source.isMeasured(in: bio)"), """
            Core/VisualModulation no longer gates on isMeasured. That gate is the whole reason \
            the core is worth keeping unwired: a bipolar route on a channel the body never \
            reported would otherwise pin its target to the bottom of range forever, which is \
            the defect the FX path had to be repaired for.
            """)
    }

    // MARK: - the finding itself, pinned where it lives

    /// ⛔ WITHOUT THIS, THE SLICE'S OWN THESIS WAS UNGUARDED. #921's finding is that the REGISTER
    /// was wrong, not the code — and nothing here read the register, so deleting the entry again
    /// left all other claims green and reopened the gap silently.
    ///
    /// ⚠️ THIS IS A POSITIVE PIN AND THAT DISTINCTION IS THE WHOLE REASON IT IS ALLOWED. #491
    /// bars a NEGATIVE scan of `CLAUDE.md` — the file deliberately quotes retracted claims, so
    /// "this string must be absent" would fire on its own retraction. Asserting that a line IS
    /// present has no such failure mode, and `TheLawFileStaysUnderItsCeilingTests` already pins
    /// ledger headings the same way.
    func testTheRegisterStillNamesTheCoreAsUnwired() throws {
        let law = try rawText("CLAUDE.md")
        XCTAssertTrue(law.contains("`Core/VisualModulation`"), """
            CLAUDE.md no longer names Core/VisualModulation in its list of app-unwired pure \
            cores. If the core was WIRED, this claim is red together with the two scans above \
            and the repair is the same one they name. If it was merely edited out, the register \
            gap #921 found has reopened: the neighbouring line truthfully says BioVisualParams \
            is wired, so a session skimming for "is bio→visual live?" reads yes and takes THIS \
            core for the mechanism. That is why the entry has to be a claim and not a courtesy.
            """)
    }

    // MARK: - helpers

    /// Files under `Sources/` whose CODE (comments stripped) contains `needle`. `excluding` is a
    /// repo-relative path — pass the declaring file when the needle is a bare type name.
    private func filesUnderSources(containing needle: String,
                                   excluding excludedRepoPath: String? = nil) throws -> [String] {
        let root = try repoRoot().appendingPathComponent(Self.sourcesRoot)
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            throw XCTSkip("cannot enumerate \(Self.sourcesRoot) — refusing to report a green it did not earn")
        }
        var hits: [String] = []
        for case let relative as String in walker where relative.hasSuffix(".swift") {
            guard let text = try? String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            else { continue }
            if let excludedRepoPath, "\(Self.sourcesRoot)/\(relative)" == excludedRepoPath { continue }
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
