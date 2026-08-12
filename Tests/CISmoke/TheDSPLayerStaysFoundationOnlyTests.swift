// TheDSPLayerStaysFoundationOnlyTests.swift
// Echoel — #550. The law survived; the reason printed next to it had been dead for weeks.
//
// WHAT THIS GUARDS. `DSP/` is a pure processing layer: 38 files whose entire import set is
// `{Foundation, Accelerate}`, and which name no Core/Sequencer type in code. That property is
// real, it is one of the standing laws, and until this slice nothing executable held it — it
// was carried by a prose block in `.claude/rules/swift-audio.md` that prescribed AUv3 patterns
// (`ParameterAddress`, `internalRenderBlock`, `fullState`) for a target removed 2026-07-24.
// Three of those four symbols occur ZERO times under `Sources/`.
//
// ⭐ WHY THE DEAD BLOCK WAS WORSE THAN NOTHING, which is the part worth carrying forward: it
// sat in the ALWAYS-LOADED set (`.claude/rules/*.md`, read before every session) and it was
// PRESCRIPTIVE. Stale descriptive prose makes a session believe something false; stale
// prescriptive prose makes it WRITE something false. `.claude/rules/context.md` measures that
// surface for exactly this reason, and the honest move when a rule dies is to replace it with
// the true one plus the command that re-derives it — not to leave it and not to delete the
// section, which would lose a live law along with a dead example.
//
// ⚠️ THE REASON IS OWNED ELSEWHERE AND IS NOT RESTATED HERE (#416).
// `FieldSoundSurvivesRelaunchTests` already says why the layer is Foundation-only ("hygiene",
// plus a plain `String` parameter is what makes its branches testable) AND carries the
// retraction of the old rationale in place: "(The reason is NOT 'the AUv3 target compiles DSP/
// in isolation', which this message said for one commit — that target was removed
// 2026-07-24.)" This file asserts the PROPERTY; that one owns the WHY.
//
// ⚠️ AND IT IS NOT "LINUX-TESTABLE", deliberately not written anywhere: 7 of the 38 import
// Accelerate, and `EchoelWSOLA.swift:16-17` does so with NO `#if canImport` guard while the
// other 6 have one. The honest property is DECOUPLING from the app's control plane, not
// portability. Claim 3 pins that asymmetry as a measured fact rather than repairing it —
// adding a guard to WSOLA is a separate decision with its own reasoning, and a guard that
// quietly assumed uniformity would be asserting something false about the tree.
//
// ⚠️ THE LIMIT. SOURCE-TEXT SCAN over a directory. It proves what the files DECLARE, not that
// no Accelerate symbol is reached transitively, and certainly not that the DSP sounds correct.
//
// ⚠️ HONEST GRADING — TRANSCRIBED against the parent `18bcdb2` and this tree, every claim
// driven in Python against both:
//   · ONE REGRESSION: claim 4, red on the parent for exactly the reason its name gives — the
//     fenced AUv3 example was still in `.claude/rules/swift-audio.md` there.
//   · THREE COUNTERWEIGHTS green on both trees, and they are the point of the file (#343):
//     the import set, the absence of control-plane types in code, and the measured Accelerate
//     asymmetry. A guard that only asserted "the dead block is gone" would stay green on a
//     tree that gutted `DSP/` down to a stub, having removed a rule and lost the law with it.
//     What the counterweights buy is the FUTURE red: claim 1 fires the day a DSP file imports
//     AVFoundation or SwiftUI, claim 2 the day one reaches for `EngineBus`.
//
// ⛔ AND THE FIRST DRAFT OF CLAIM 4 WOULD HAVE BEEN RED ON CORRECT CODE (#364). It scanned the
// WHOLE rules file, and the ⛔ retraction this same slice writes there names `internalRenderBlock`
// verbatim in order to say it is gone — the #486/#491 collision, walked into head-first inside
// the very file whose lesson is about prose outliving its subject. Caught by transcription
// before the commit, not by review. The repair is also the more CORRECT scan rather than a
// workaround: the defect was never "the word appears", it was "this file PRESCRIBES a dead
// API", and a rules file prescribes in its fenced examples. Naming a removed symbol while
// retracting it is the opposite of prescribing it.
//
// ⚠️ `SourceText.codeOnly` is LOAD-BEARING, MEASURED (#453) over {4 claims × 2 trees}: **2 of
// 8** verdicts flip — claim 2 on BOTH trees, PASS stripped and FAIL raw, because
// `EchoelDDSP.swift` and `StudioCalculator.swift` name `EngineBus`, `BioSampleFrame`,
// `MusicalFrame` and `PatternEngine` in COMMENTS while naming none of them in code. Two trees,
// two flips: a flip count is per (claim, TREE), which this session has now had to correct in
// three headers — so it is written out here rather than tallied a fourth time.

import Foundation
import XCTest

final class TheDSPLayerStaysFoundationOnlyTests: XCTestCase {

    /// The only two modules a pure processing file may import.
    private static let allowed: Set<String> = ["Foundation", "Accelerate"]

    /// Control-plane types that must not be reachable from a processor. Not exhaustive by
    /// design — an exhaustive list would go stale; these are the spine types whose presence
    /// would mean the layering broke rather than that one name drifted.
    private static let controlPlane = [
        "EngineBus", "BioSampleFrame", "MusicalFrame", "PatternEngine",
        "TimelineStore", "TimelineLane", "ClipStore",
    ]

    private static let rules = ".claude/rules/swift-audio.md"

    // MARK: - claim 1 — the import set

    func testEveryDSPFileImportsOnlyFoundationAndAccelerate() throws {
        var offenders: [String] = []
        for (name, code) in try dspFiles() {
            for line in code.split(separator: "\n", omittingEmptySubsequences: false) {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("import ") else { continue }
                let module = String(t.dropFirst("import ".count))
                    .split(separator: ".").first.map(String.init) ?? ""
                if !Self.allowed.contains(module) { offenders.append("\(name): \(t)") }
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) file(s) under `DSP/` import something outside \
            {Foundation, Accelerate}: \(offenders.joined(separator: " | ")). `DSP/` is a pure \
            processing layer — a file that imports AVFoundation, SwiftUI or CoreMIDI has stopped \
            being one, and the dependency now points the wrong way. If the import is deliberate, \
            move the law in `\(Self.rules)` in the SAME commit; do not leave the rule saying one \
            thing while the tree says another, which is the failure this file was written for.
            """)
    }

    // MARK: - claim 2 — no control-plane type in CODE

    func testNoDSPFileNamesAControlPlaneTypeInCode() throws {
        var offenders: [String] = []
        for (name, code) in try dspFiles() {
            for type in Self.controlPlane where code.contains(type) {
                offenders.append("\(name): \(type)")
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) control-plane reference(s) in `DSP/` CODE: \
            \(offenders.joined(separator: " | ")). Four of these names DO appear in `DSP/` \
            comments (`EchoelDDSP`, `StudioCalculator`) and that is fine — a processor may \
            explain what calls it. Reaching one is different: it makes the layer depend on the \
            app's control plane, and the pure cores stop being drivable from a test.
            """)
    }

    // MARK: - claim 3 (COUNTERWEIGHT) — the Accelerate asymmetry is a fact, not an assumption

    /// #343. A file asserting only "nothing forbidden is imported" stays green on a tree that
    /// deleted `DSP/` down to a stub. So pin that the layer is still SUBSTANTIAL and still
    /// really uses Accelerate — and pin the asymmetry the prose names, so nobody "tidies"
    /// `EchoelWSOLA` on the strength of a rule that never claimed uniformity.
    func testTheLayerIsSubstantialAndTheGuardAsymmetryIsReal() throws {
        let files = try dspFiles()
        XCTAssertGreaterThan(files.count, 30, """
            Only \(files.count) files under `DSP/`. The claims above would be nearly vacuous on \
            a stub layer; if the directory really shrank that far, re-derive the count in \
            `\(Self.rules)` rather than letting this pass quietly.
            """)
        let accelerate = files.filter { $0.code.contains("import Accelerate") }
        XCTAssertGreaterThan(accelerate.count, 0, """
            No file under `DSP/` imports Accelerate any more. That would make the allowlist in \
            claim 1 half dead, and it also retires the reason `\(Self.rules)` gives for NOT \
            calling this layer portable.
            """)
        let unguarded = accelerate.filter { !$0.code.contains("#if canImport(Accelerate)") }
        XCTAssertEqual(unguarded.map(\.name), ["EchoelWSOLA.swift"], """
            The set of Accelerate importers WITHOUT a `#if canImport` guard is now \
            \(unguarded.map(\.name)) — the prose in `\(Self.rules)` names exactly \
            `EchoelWSOLA.swift`, and uses it to explain why this layer must not be described as \
            portable. If you guarded WSOLA, that sentence is now wrong in the friendly \
            direction and must move; if a second file lost its guard, it is wrong in the other. \
            Either way this is a measured fact, not a rule — do not "fix" the tree to match it \
            without deciding that separately.
            """)
    }

    // MARK: - claim 4 — the always-loaded rule still describes this layer

    /// The dead AUv3 block is the whole reason this file exists, so its absence is asserted —
    /// and so is the presence of the command that lets the next reader re-derive the property
    /// instead of trusting a number (`.claude/rules/context.md` §2).
    func testTheRuleFileCarriesTheLiveLawAndNotTheDeadOne() throws {
        let text = try rawText(Self.rules)
        // ⛔ SCANNED IN THE FENCED CODE BLOCKS ONLY, and the first draft did not — it scanned
        // the whole file and was therefore RED ON THIS TREE, because the ⛔ retraction the same
        // slice writes into `\(Self.rules)` names `internalRenderBlock` verbatim in order to
        // say it is gone. That is the #486/#491 collision walked into head-first, inside the
        // very file whose lesson is about prose that outlives its subject. It matters WHY the
        // narrow scan is also the CORRECT one rather than a workaround: the defect was never
        // "the word appears", it was "the file PRESCRIBES a dead API" — and a rules file
        // prescribes in its code examples. Naming a removed symbol while retracting it is the
        // opposite of prescribing it.
        for dead in ["internalRenderBlock", "AUInternalRenderBlock", "case wetDry"] {
            let offenders = Self.fencedBlocks(in: text).filter { $0.contains(dead) }
            XCTAssertTrue(offenders.isEmpty, """
                A fenced code example in `\(Self.rules)` uses `\(dead)` again. That is AUv3 \
                vocabulary for a target removed 2026-07-24, and this file is in the \
                ALWAYS-LOADED set — stale PRESCRIPTIVE prose does not merely mislead a session, \
                it makes one write against an API that is not there. Prose ABOUT the removal is \
                fine and deliberately not scanned. If AUv3 came back, delete this assertion in \
                the commit that brings it back.
                """)
        }
        XCTAssertTrue(text.contains("Sources/Echoelmusic/DSP/*.swift"), """
            `\(Self.rules)` no longer prints the command that re-derives the DSP import set. A \
            number without its command is the thing `.claude/rules/context.md` §2 forbids: the \
            next reader can only trust it or re-invent it.
            """)
    }

    // MARK: - source access

    private struct DSPAnchorMissing: Error { let reason: String }

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

    /// The contents of every ``` fence in a Markdown file — the parts that PRESCRIBE. Prose
    /// outside them may name anything, including what it is retracting.
    private static func fencedBlocks(in markdown: String) -> [String] {
        var blocks: [String] = []
        var current: [String] = []
        var inside = false
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inside { blocks.append(current.joined(separator: "\n")); current = [] }
                inside.toggle()
                continue
            }
            if inside { current.append(String(line)) }
        }
        // An unterminated fence: keep what was collected rather than silently dropping it —
        // a scan that returns nothing would pass over the exact case it exists to catch.
        if inside, !current.isEmpty { blocks.append(current.joined(separator: "\n")) }
        return blocks
    }

    /// Raw text — the rules file is Markdown, where `//` is not a comment marker and the Swift
    /// stripper would be the wrong tool applied quietly.
    private func rawText(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DSPAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    /// Every `DSP/*.swift`, comment-stripped (#453 — one stripper for the whole bundle). The
    /// stripping is what separates this from a `grep`: four control-plane names appear in `DSP/`
    /// comments today and none in code.
    private func dspFiles() throws -> [(name: String, code: String)] {
        let dir = try repoRoot().appendingPathComponent("Sources/Echoelmusic/DSP")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".swift") }.sorted()
        guard !names.isEmpty else {
            throw DSPAnchorMissing(reason: "no Swift files under Sources/Echoelmusic/DSP")
        }
        return try names.map { name in
            let text = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            return (name, SourceText.codeOnly(text))
        }
    }
}
