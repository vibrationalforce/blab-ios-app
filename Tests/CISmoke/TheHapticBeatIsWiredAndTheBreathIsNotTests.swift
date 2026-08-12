// TheHapticBeatIsWiredAndTheBreathIsNotTests.swift
// Echoel — #552. Three haptics file headers deferred the wiring of both drivers to a coming
// cycle. One of those drivers had shipped; the other genuinely had not.
//
// WHAT WAS MEASURED (2026-08-12). The BEAT path is complete and reachable:
// `EchoelmusicApp` registers `transport.addStepSubscriber("haptics", …)`, the closure calls
// `HapticController.tapBeat(step:)`, that reaches `HapticEngine.play(_:)`, and the arming
// switch `hapticsRow` ("Haptic beat (feel)") is mounted in `tempoToolsPanel` behind the Tempo
// chip. The BREATH path has zero production callers. So `docs/dev/PRODUCT_DEFINITION.md`'s
// "Body | HapticController | CoreHaptics" row is TRUE and is deliberately left alone — this
// slice corrects three source headers, it does not retract an output medium.
//
// ⭐ WHY A HALF-TRUE PLAN IS THE EXPENSIVE KIND, which is the transferable part. A stale FACT
// is refuted the moment a reader checks it. A stale PLAN survives every check that lands on
// the part still undone: a session verifying "the bio driver is missing" would find that true
// and carry the whole sentence forward — then either rebuild the beat path that already ships
// or report its door as absent. #550 said dead PRESCRIPTIVE law is worse than none because a
// session FOLLOWS it; this is the same defect with a working half attached, which is what let
// it sit unnoticed while the code around it changed.
//
// ⚠️ AND THE OBVIOUS COMPLETION IS A TRAP, recorded at `HapticController.breath(...)` rather
// than left for the next session to discover on a device: the tick a session would reach for
// is the ~10 Hz `bioVoice.onPollTick`, while `BioHaptics.breathPulse` defaults to
// `duration: 0.1` — ten abutting 0,1-s CONTINUOUS cues per second are one unbroken buzz, and
// the bio APPLY rate is ~1 Hz anyway (every consumer dedupes on `frame.timestamp`), so nine of
// the ten would carry identical phase and coherence. Claim 4 below therefore does NOT forbid
// wiring it (#364) — it names what must move in the same commit when someone does.
//
// ⚠️ THE LIMIT. SOURCE-TEXT SCAN throughout. It proves where text and call sites sit; it does
// not prove the phone vibrates. Whether the beat pulse FEELS like time rather than noise is a
// device probe and stays open.
//
// ⚠️ HONEST GRADING — transcribed in Python against the parent (`dd87f0d`) and this tree:
//   · ONE REGRESSION: claim 1, red on the parent at 5 sites across the 3 files. Five sites,
//     ONE finding (#486) — a single scan reporting N hits is not N regressions.
//   · THREE COUNTERWEIGHTS green on both trees, and they carry the file: claims 2 and 3 are
//     the two halves of "the beat path is live" (producer + door), claim 4 is "the breath path
//     is not". Without all three the corrected headers would be unfalsifiable prose.
//   · STRIPPER: TRAGEND, 1 of 4 verdicts flips. Claim 4's needle `.breath(` counts raw=2 /
//     stripped=0 on THIS tree — the two raw hits are the corrected comments in `BioHaptics`
//     and `HapticEngine` naming the method. Raw, this guard would be red on the very tree that
//     fixes the prose. On the parent it is raw=0 / stripped=0 and flips nothing. (This is also
//     why `HapticController`'s header states the fact instead of quoting a `git grep` for it:
//     a comment about a symbol contaminates any raw search for that symbol — the
//     `EchoelModalBank` recipe CLAUDE.md had to retract, arriving here by a different door.)

import Foundation
import XCTest

final class TheHapticBeatIsWiredAndTheBreathIsNotTests: XCTestCase {

    private static let controller = "Sources/Echoelmusic/Studio/HapticController.swift"
    private static let kernel = "Sources/Echoelmusic/Studio/BioHaptics.swift"
    private static let engine = "Sources/Echoelmusic/Studio/HapticEngine.swift"
    private static let app = "Sources/Echoelmusic/EchoelmusicApp.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// Phrases that defer this module's wiring to a future cycle. Each was in the tree before
    /// this slice; none may return while the beat half ships.
    private static let deferrals = [
        "next cycle", "later cycle", "Not yet wired", "changes no existing behavior",
    ]

    // MARK: - claim 1 (the regression) — no haptics header defers the wiring any more

    /// RAW text on purpose: the subject IS the prose. Stripping comments here would scan an
    /// almost empty file and report a confident green over nothing (#453 names one stripper
    /// for the bundle; it does not say every scan is about code).
    func testNoHapticsHeaderStillDefersTheWiring() throws {
        var offenders: [String] = []
        for rel in [Self.controller, Self.kernel, Self.engine] {
            let text = try rawText(rel)
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() {
                for phrase in Self.deferrals where line.contains(phrase) {
                    offenders.append("\(rel):\(i + 1) «\(phrase)»")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) site(s) in the haptics files defer this module's wiring to a \
            future cycle: \(offenders.joined(separator: " | ")). The BEAT driver ships — \
            producer in `\(Self.app)`, door in `\(Self.studio)` (claims 2 and 3 pin both). \
            Only the breath driver is absent, and saying so needs the specific half named, not \
            a promise over the whole module: a plan that is half done reads as correct to every \
            reader who checks the undone half.
            """)
    }

    // MARK: - claim 2 (COUNTERWEIGHT) — the beat producer

    /// #343. Claim 1 alone stays green on a tree that removed the deferral AND the wiring — at
    /// which point the corrected headers would be the false ones.
    func testTheTransportStillDrivesTheBeatPulse() throws {
        let code = try codeText(Self.app)
        XCTAssertTrue(code.contains("addStepSubscriber(\"haptics\""), """
            No `"haptics"` step subscriber in `\(Self.app)`. That registration is the ONLY \
            producer of a haptic beat; without it the corrected headers in the three haptics \
            files claim a live driver that no longer exists, and the honest text becomes the \
            deferral this slice removed. Move all three in the same commit.
            """)
        XCTAssertTrue(code.contains("tapBeat(step:"), """
            The step subscriber no longer calls `tapBeat(step:)` — the pulse is unwired even if \
            the subscriber survives. See above: the three headers move with it.
            """)
    }

    // MARK: - claim 3 (COUNTERWEIGHT) — the door that arms it

    func testTheArmingSwitchIsStillMounted() throws {
        let code = try codeText(Self.studio)
        let mentions = code.components(separatedBy: "hapticsRow").count - 1
        XCTAssertGreaterThanOrEqual(mentions, 2, """
            `hapticsRow` appears \(mentions)× in `\(Self.studio)` — it needs a definition AND a \
            mount. One mention means the row is defined and never rendered, which is the \
            doorless shape this repo keeps re-discovering: the driver would still fire, but \
            nothing could arm it, so the feature would be unreachable while reading as live.
            """)
        XCTAssertTrue(code.contains("$haptics.isEnabled"), """
            The row no longer binds `isEnabled`. Arming is what turns every `tapBeat` from a \
            no-op into a pulse (`guard isEnabled` in `\(Self.controller)`); a row that does not \
            bind it is decoration.
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHT) — the breath half really is producerless

    /// It does NOT forbid wiring the breath cue (#364) — it names what must move when someone
    /// does, including the hazard that makes the obvious wiring site wrong.
    func testTheBreathCueStillHasNoProductionCaller() throws {
        var callers: [String] = []
        for rel in try swiftFiles() where rel != Self.controller {
            let code = try codeText(rel)
            for (i, line) in code.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() where line.contains(".breath(") {
                callers.append("\(rel):\(i + 1)")
            }
        }
        XCTAssertTrue(callers.isEmpty, """
            `HapticController.breath(phase:coherence:)` now has \(callers.count) production \
            caller(s): \(callers.joined(separator: ", ")). GOOD — but three things move in the \
            SAME commit. (1) The headers of `\(Self.controller)`, `\(Self.kernel)` and \
            `\(Self.engine)` all state that this half is the absent one. (2) The ⚠️ warning at \
            `breath(phase:coherence:)` says the ~10 Hz poll tick against a 0,1-s continuous cue \
            is a continuous buzz, not a breath — if the new caller IS that tick, the cue's \
            duration or the drive rate had to change with it. (3) This assertion, which is the \
            record that it used to be absent.
            """)
    }

    // MARK: - source access

    private struct HapticAnchorMissing: Error { let reason: String }

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

    private func rawText(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw HapticAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    private func codeText(_ relativePath: String) throws -> String {
        SourceText.codeOnly(try rawText(relativePath))
    }

    private func swiftFiles() throws -> [String] {
        let base = try repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: base.path) else {
            throw HapticAnchorMissing(reason: "cannot walk Sources/")
        }
        var out: [String] = []
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            out.append("Sources/" + rel)
        }
        guard out.count > 200 else {
            throw HapticAnchorMissing(reason: """
                only \(out.count) Swift files walked under Sources/; the tree holds well over \
                three hundred, so a "nobody calls it" result here would be vacuous.
                """)
        }
        return out.sorted()
    }
}
