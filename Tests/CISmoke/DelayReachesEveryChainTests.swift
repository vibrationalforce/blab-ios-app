// DelayReachesEveryChainTests.swift
// Echoel — a knob must land on every chain it claims to move. BLOCKING bundle.
//
// THE DEFECT (#240). `EchoelStudioView` drives more than one live `EchoelFXChain`: the
// composer's `synth` and — when the play surface exists — the Field's `touchSynth`. The FX
// character was stamped on BOTH (three call sites, each listing them inline), while
// `applyDelaySync(bpm:)` wrote only `synth.fxChain`.
//
// So the two chains agreed on WHETHER delay was on and disagreed on its TIME. Choosing a
// different delay division moved the room for the generated take and left the played notes
// echoing at whatever the character had stamped — audible, and impossible to attribute, because
// the picker showed one value and half the instrument used another.
//
// Two lists that must agree are one list. The fix is `characterFXChains`, and this file guards
// the fix's SHAPE rather than its effect, because there is no seam: the chains live behind
// `@Environment` on a SwiftUI `View`, `applyDelaySync` is `private`, and there is no local
// toolchain to build a UI-test host with. Same reasoning as `CleanIsDryTests`.
//
// A THIRD PATH was found while fixing it and is guarded here too: opening a saved project
// stamped the character (which sets a delay time) and never re-applied the division, so the
// picker lied again the moment a take was loaded. `delaySync` is `@State` and is NOT part of the
// saved `Project` — restoring the SAVED division would be a schema change; making the chain match
// what the picker SHOWS is what stops the lie.
//
// WHAT THIS CANNOT PROVE: that `touchSynth` is non-nil at runtime, that the Field is audible, or
// that the resulting delay time sounds right. It proves that no path writes a subset of the
// chains.

import Foundation
import XCTest
@testable import Echoelmusic

final class DelayReachesEveryChainTests: XCTestCase {

    private static let view = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// ⛔ THE GUARD. `applyDelaySync` must write the time over the inventory, not over one named
    /// chain. A re-introduced `synth.fxChain.delay` here is #240 coming back.
    func testTheDelayTimeIsWrittenOverTheWholeInventory() throws {
        let body = try functionBody(named: "private func applyDelaySync(bpm: Double)",
                                   in: Self.view)
        XCTAssertTrue(body.contains("characterFXChains"),
                      "`applyDelaySync` no longer iterates the chain inventory, so the delay "
                      + "division reaches some sounding chains and not others (#240):\n\(body)")
        XCTAssertFalse(body.contains("synth.fxChain"),
                       "`applyDelaySync` names one chain directly again. That is exactly the "
                       + "shape of #240: the character reaches every chain, the time reaches "
                       + "one:\n\(body)")
        XCTAssertTrue(body.contains("delay.timeSeconds"),
                      "`applyDelaySync` no longer sets the delay time at all, so the user's "
                      + "chosen division does nothing:\n\(body)")
    }

    /// The inventory itself must still hold MORE than the composer's synth — otherwise the fix
    /// above is a rename and #240 is intact behind a nicer symbol. This is the anti-vacuity
    /// assertion for the whole file.
    func testTheInventoryIsNotJustTheComposerSynth() throws {
        let body = try functionBody(named: "private var characterFXChains: [EchoelFXChain]",
                                   in: Self.view)
        XCTAssertTrue(body.contains("synth.fxChain"),
                      "the inventory lost the composer's own chain:\n\(body)")
        XCTAssertTrue(body.contains("touchSynth?.fxChain"),
                      "the inventory no longer includes the Field's chain, so it is a one-element "
                      + "list wearing a plural name and #240 is back:\n\(body)")
    }

    /// Every path that stamps the character must use the inventory too. If one reverts to naming
    /// chains inline, the lists drift apart again — which is how #240 arose in the first place:
    /// nothing was wrong with any single line, only with there being three of them.
    ///
    /// Counted on the WHOLE file rather than per-function, because the three sites live in
    /// `applyFX()`, the re-seed path and the project-open path, and each legitimately passes a
    /// different bpm/genre — so they cannot be collapsed into one call, only onto one inventory.
    func testEveryCharacterStampGoesThroughTheInventory() throws {
        let text = try source(Self.view)
        let stamps = text.components(separatedBy: .newlines)
            .filter { $0.contains("fxCharacter.apply(to:") }
        XCTAssertFalse(stamps.isEmpty, "no character stamp found — this guard lost its target")
        for line in stamps {
            XCTAssertTrue(line.contains("to: chain"),
                          "a character stamp names a chain directly instead of iterating the "
                          + "inventory, so it can drift from the delay-time write (#240): "
                          + line.trimmingCharacters(in: .whitespaces))
        }
    }

    /// Opening a saved take must re-apply the division. Asserted on the project-open function,
    /// because the re-seed path already did this and only the open path did not — a guard on
    /// "somewhere in the file" would have passed while the defect was live.
    /// ⚠️ ASSERTED ON `loadedTempo`, NOT ON `p.bpm`, and the difference is the second half of the
    /// fix. `PatternEngine.setTempo` CLAMPS, so a saved take whose tempo falls outside the
    /// engine's range plays at a different number than the one in the file — and both the
    /// character stamp and the division ran on the raw `p.bpm` earlier in the function, giving
    /// the FX room tempo-synced times for a tempo the app never plays at. The first draft of this
    /// guard pinned the `p.bpm` literals, which would have turned it RED for the corrected code:
    /// a test that locks in the staleness it was written to catch.
    func testOpeningAProjectReAppliesTheDelayDivisionAtThePlayedTempo() throws {
        let body = try functionBody(named: "private func open(_ p: Project) {", in: Self.view)
        XCTAssertTrue(body.contains("fxCharacter.apply(to: chain, bpm: loadedTempo"),
                      "the project-open path no longer stamps the character at the authoritative "
                      + "clamped tempo — either the stamp is gone (this guard's premise, so the "
                      + "assertion below would pass vacuously) or it is back on the raw file "
                      + "value:\n\(body)")
        XCTAssertTrue(body.contains("applyDelaySync(bpm: loadedTempo)"),
                      "opening a project stamps a character (which sets a delay TIME) without "
                      + "re-applying the chosen division at the tempo the app will actually play, "
                      + "so the Delay picker shows one value and the chain holds another the "
                      + "moment a take is loaded:\n\(body)")
        // Order is load-bearing: both writes must come AFTER `loadedTempo` is derived, or they
        // would be reading an uninitialised name — a compile error, not a silent bug, but pinning
        // it states the intent for whoever moves these lines next.
        guard let tempoLine = body.range(of: "let loadedTempo = beatPlayer.pattern.tempo"),
              let syncLine = body.range(of: "applyDelaySync(bpm: loadedTempo)") else {
            return XCTFail("both anchors must exist in `open`:\n\(body)")
        }
        XCTAssertTrue(tempoLine.upperBound < syncLine.lowerBound,
                      "the delay re-apply must follow the authoritative tempo, not precede it")
    }

    // MARK: - Reading the source

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: try repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// The lines from `declaration` to its matching closing brace, whole-line comments dropped
    /// BEFORE the brace arithmetic so a comment containing an unbalanced brace cannot desync the
    /// depth. Throws on a miss rather than returning empty — an empty body passes every
    /// `XCTAssertFalse` above vacuously, which is the failure mode `Tests/CISmoke` exists to stop.
    ///
    /// (An earlier draft grew a `fromEnclosingFunction` mode that walked upwards to the nearest
    /// line containing `func ` — deleted before it ran, because a doc comment above the target
    /// mentioning a function name would have anchored the scan in the wrong place. Naming the
    /// declaration is both shorter and honest about what is being read.)
    private func functionBody(named declaration: String, in relativePath: String) throws -> String {
        let lines = try source(relativePath).components(separatedBy: .newlines)
        let matches = lines.indices.filter { lines[$0].contains(declaration) }
        guard let start = matches.first else {
            XCTFail("Declaration not found: \(declaration) in \(relativePath). It was renamed or "
                    + "moved — re-point this test rather than deleting it.")
            throw CocoaError(.fileNoSuchFile)
        }
        XCTAssertEqual(matches.count, 1,
                       "`\(declaration)` appears \(matches.count) times; this scan reads only the "
                       + "first, so the guard may be pointing at the wrong one.")
        var depth = 0
        var collected: [String] = []
        for line in lines[start...] {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            collected.append(line)
            depth += line.filter { $0 == "{" }.count
            depth -= line.filter { $0 == "}" }.count
            if depth == 0 && collected.count > 1 { break }
        }
        return collected.joined(separator: "\n")
    }

    /// `#filePath` is inside `Tests/CISmoke/`, so the repo root is three directories up. A
    /// source-reading test that cannot find the source must SKIP, not pass.
    private func repoRoot() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CISmoke
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
        guard FileManager.default.fileExists(atPath:
                root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("source tree not present — this test inspects source text, so it "
                          + "SKIPS rather than reporting a green it did not earn")
        }
        return root
    }
}
