// BioFXReachesEveryChainTests.swift
// Echoel — the body's FX modulation must reach every sounding chain. BLOCKING bundle. #386.
//
// THE DEFECT. `FXBioModulator` is the ~30 Hz driver that makes EchoelFX bio-reactive. It was
// bound with `attach(chain: polyVoice.fxChain, bus:)` — ONE chain. So while the take's filter,
// delay and reverb breathed with the pulse, the notes the performer played on the Field ran
// through a chain the body never touched. One body, two sounds, one of them deaf to it, and
// nothing on screen saying which.
//
// It is the SAME split reach `FXPanelReachesEveryChainTests` guards one level up: there the
// user's HAND reached one chain, here the user's BODY does. Two guards, one shape — if a third
// writer appears, it needs its own entry in both.
//
// ⛔ WHY THE BASE IS PER CHAIN, and why this file asserts the array and not just the loop. The
// driver's whole ownership model is "capture the user's intended value, drive around it,
// restore it on the way out". Chains are NOT guaranteed to hold the same value for a target:
// they converge on anything written through the FX surface (#318) or a character/preset apply,
// but nothing forces them equal, and `leadSynth.fxChain` is deliberately outside the inventory.
// Capturing ONE base and writing it to all of them would silently overwrite one chain's setting
// with another's the moment a route engages — and again on restore, permanently. The offset is
// a property of the BODY and is shared; the base is a property of the CHAIN and is not.
//
// ⚠️ WHY A SOURCE SCAN. `allChains`/`baseValues` are `private`, the driver is `@MainActor` and
// bound at app start from `EchoelmusicApp`, and there is no local toolchain to build a host
// with. House pattern — same as `FXPanelReachesEveryChainTests`, `DelayReachesEveryChainTests`,
// `SoundPanelReflowsTests`. It proves the fan-out is WRITTEN; it cannot prove it is audible.
//
// NEEDS-FOUNDER-VERIFY: add a bio route (Effects → Bio-reactive → e.g. coherence → Reverb mix)
// with the pulse running, then play the Field. Do the played notes breathe with the body the
// same way the generated take does?

import Foundation
import XCTest

final class BioFXReachesEveryChainTests: XCTestCase {

    private static let driver = "Sources/Echoelmusic/Tools/FXBioModulator.swift"
    private static let app = "Sources/Echoelmusic/EchoelmusicApp.swift"

    /// ⭐ THE GUARD. Every chain-writing loop in the driver must iterate the inventory, and the
    /// per-chain base must survive as an array. The needles carry their operators so a
    /// `.first`-style narrowing cannot pass as a fan-out.
    func testTheDriverKeepsAnInventoryAndAPerChainBase() throws {
        let code = try codeLines(Self.driver).joined(separator: "\n")
        XCTAssertTrue(code.contains("private var allChains: [EchoelFXChain]"), """
            `FXBioModulator` no longer keeps a chain INVENTORY (#386).

            Bound to a single chain, the body modulates the generated take's FX and leaves \
            the played notes untouched — the split reach this guard exists to hold shut.
            """)
        XCTAssertTrue(code.contains("private var baseValues: [FXModTarget: [Float]]"), """
            `baseValues` is no longer per-chain.

            One base for many chains overwrites one chain's user setting with another's the \
            first time a route engages, and again on restore. The offset is shared because it \
            comes from the body; the base is not, because it comes from the chain.
            """)
        XCTAssertTrue(code.contains("allChains.map { read(t, from: $0) }"), """
            the base capture no longer reads EVERY chain:
            \(code)
            """)
    }

    /// ⛔ THE THREE WRITE PATHS, named individually because a fan-out that covers two of them
    /// is worse than none: the tick would drive all chains while `stop()`/`reconcileBases()`
    /// restored only one, leaving the others parked wherever the last tick left them — a
    /// silent, permanent edit to a setting the user made by hand.
    func testEveryWritePathFansOut() throws {
        let lines = try codeLines(Self.driver)
        let writes = lines.filter { $0.contains(", to: c)") }
        XCTAssertGreaterThanOrEqual(writes.count, 4, """
            expected at least four chain writes in \(Self.driver) (tick, stop, reconcile \
            restore, attach restore), found \(writes.count):
            \(writes.map { $0.trimmingCharacters(in: .whitespaces) })
            """)
        let unfanned = writes.filter { !$0.contains("bases[") }
        XCTAssertTrue(unfanned.isEmpty, """
            these chain writes do not use a per-chain base — they write one value, so either \
            they hit one chain or they push one chain's base onto all of them:
            \(unfanned.map { $0.trimmingCharacters(in: .whitespaces) })
            """)
        // ⛔ THIS USED TO BE AN ANTI-VACUITY CHECK FOR "a loop exists ANYWHERE in the file", and
        // a reviewer showed it left the hole in exactly the shape of the bug. The three checks
        // above are independent — nothing tied a given write to a given loop — so narrowing the
        // TICK back to `if let c = allChains.first { … bases[0] … }` kept the write count at 4
        // (the three restore paths are untouched), kept a `bases[` on the narrowed line, and
        // kept an `enumerated()` loop alive in `stop()`. All green, defect fully restored, in
        // the one path that runs 30 times a second. Counting loops against writes closes it:
        // every chain write in this file lives in a fan-out, and a narrowing drops the count.
        let loops = lines.filter { $0.contains("for (i, c) in allChains.enumerated()") }
        XCTAssertEqual(loops.count, writes.count, """
            \(loops.count) fan-out loops for \(writes.count) chain writes in \(Self.driver) — \
            they must be one to one, or some write reaches a single chain.
            loops: \(loops.map { $0.trimmingCharacters(in: .whitespaces) })
            writes: \(writes.map { $0.trimmingCharacters(in: .whitespaces) })

            If a legitimate edit puts two writes inside ONE loop this count goes out of step. \
            Then re-express the invariant (per-member windowing), do not widen it back to \
            "a loop exists somewhere" — that is the version that let the regression through.
            """)
        // And the path that matters, named on its own, because the count above is a whole-file
        // property: the 30 Hz driver's own write must be inside a fan-out, not next to one.
        let tick = try memberBody(startingWith: "private func tick()", in: Self.driver)
        XCTAssertTrue(tick.contains(where: { $0.contains("for (i, c) in allChains.enumerated()") }), """
            `tick()` no longer fans out. This is the 30 Hz path — the one that makes the body \
            audible — so a narrowing here IS the defect, whatever the restore paths do:
            \(tick.joined(separator: "\n"))
            """)
    }

    /// The door. A fan-out capability with an empty inventory at the one call site is the
    /// lying-control shape (#164): the code reads as if the body reached every chain while
    /// `mirrors` defaulted to `[]`.
    func testTheCallSitePassesTheMirrors() throws {
        let code = try codeLines(Self.app).joined(separator: "\n")
        XCTAssertTrue(code.contains("mirrors: [touchVoice.fxChain]"), """
            `EchoelmusicApp` no longer hands `FXBioModulator` the Field's chain (#386).

            `mirrors` defaults to empty, so dropping it here compiles and silently restores \
            the original defect: the body drives the take and not the played notes. If the \
            Field's voice was renamed, move this needle with it in the same commit.
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

    /// Every line that is not a whole-line comment. Load-bearing: the ⛔ blocks in the driver
    /// quote `allChains`, `baseValues` and the old one-chain wording verbatim while explaining
    /// them, and a scan that read them would count the explanation as code.
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
