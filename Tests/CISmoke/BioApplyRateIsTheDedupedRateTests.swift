// BioApplyRateIsTheDedupedRateTests.swift
// Echoel — #341. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ THE NUMBER THIS PROTECTS, and the reason it earns a file of its own: CLAUDE.md's
// architecture line said the bio bus was a "10 Hz poll", and THREE shipped defects were
// derived from that one figure — #315 (a one-pole computed for 60 Hz fed at ~1 Hz, so the
// "living" bio wobble took 24–120 s per cycle instead of 0.4–2 s), #332 (the same class in
// two more poles) and #336 (`ModulationEngine`'s `dt`, still open). None of them was a
// coding mistake; each was a correct calculation from a wrong documented rate.
//
// The distinction that was missing: the POLL is 10 Hz, the APPLY rate is ~1 Hz, because
// every consumer dedupes on `frame.timestamp` and every wired publisher emits at ~1 Hz. The
// poll is a CEILING, not a target.
//
// ⛔ WHY THIS FILE EXISTS AT ALL — I claimed it did before it did. The #341 commit
// (`2446574`) added the sentence "Ein Wächter im blockierenden Bundle
// (`Tests/CISmoke/BioApplyRateIsTheDedupedRateTests.swift`) hält die Publisher-Kadenz und
// die Deduplizierung fest" to CLAUDE.md, in the present tense, and shipped no such file.
// The reviewer found it. That is precisely the unverifiable justification CLAUDE.md warns
// about at the `LaneVoiceKind.drums` paragraph ("ein 'NICHT löschen'-Kommentar mit falscher
// Begründung ist schlimmer als keiner — die nächste Session kann ihn nicht widerlegen"),
// committed in the one line whose stated purpose is to stop silent ageing. The lesson is
// not "write the test": it is that a sentence naming its own evidence must be written in
// the same commit as that evidence, or it is worse than no sentence.
//
// WHAT THIS CAN AND CANNOT SHOW: source text, because these are `@MainActor` publishers and
// polling loops this bundle cannot drive. It proves the CADENCE and the DEDUPE are still
// written where the architecture line says they are — not that a device measures 1 Hz. A
// stronger claim would need a device, and overstating a guard's reach is the failure mode
// this repo keeps paying for.

import Foundation
import XCTest

final class BioApplyRateIsTheDedupedRateTests: XCTestCase {

    /// The camera publisher is the fastest wired source, so it sets the ceiling everything
    /// else sits under. Its publish is gated to every TENTH tick of a 0.1 s loop = ~1 Hz.
    /// Both halves are asserted: the gate alone would still be 10 Hz if the loop sped up,
    /// and the loop alone says nothing about the gate.
    ///
    /// Since #577 the period can back off to 0.5 s — but ONLY while iOS holds the camera and
    /// nothing has arrived for six seconds, a state in which the publish path is already
    /// closed one line earlier on `inboundRateEMA`. So the ~1 Hz ceiling is unchanged for
    /// every tick that can publish, and the third assertion below pins that condition.
    func testTheCameraPublishesAtAboutOneHertzNotTen() throws {
        let code = try source("Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift")

        XCTAssertTrue(code.contains("tick % 10 == 0"), """
            The camera publisher no longer gates its bus publish to every tenth tick. If it \
            now publishes every tick, the bio APPLY rate is 10 Hz, and every time constant \
            derived from ~1 Hz (the shared `smoothCoeff` in `EchoelDDSP`, the visual eases, \
            `ModulationEngine`'s dt) is suddenly ten times too SLOW rather than too fast. \
            That is #315/#332/#336 in reverse; re-derive them before removing this gate.
            """)
        // ⛔ THIS ASSERTION READ `code.contains("milliseconds(100)")` AND WENT RED ON CORRECT
        // WORK. #577 made the loop's period a variable so it can back off to 0.5 s while iOS
        // holds the camera, and the literal disappeared. The guard did its job — its own
        // message demanded "change them as a pair, and update CLAUDE.md in the same commit",
        // which is what this commit does — but the ANCHOR was a spelling, not the law. A
        // literal in a `sleep` call is the most brittle possible way to pin a rate.
        //
        // Repointed at the NAMED constant, which is also what `AFutileTickCostsLessTests`
        // pins end-to-end (`1 / activeTickSeconds == 10`). The two files now protect one law
        // from two directions and that is deliberate, not duplication: this one owns "the
        // publish is ~1 Hz", that one owns "the rate maths still divides by the real period".
        XCTAssertTrue(code.contains("nonisolated static let activeTickSeconds = 0.1"), """
            The camera publisher's active loop period is no longer 0.1 s. The `tick % 10` gate \
            above is meaningless without it — together they are what makes the publish ~1 Hz. \
            Change them as a pair, and update CLAUDE.md's architecture line in the same commit.
            """)
        XCTAssertTrue(code.contains("var tickSeconds = CameraRPPGBioPublisher.activeTickSeconds"), """
            The loop no longer starts from `activeTickSeconds`. Pinning the constant proves \
            nothing if the `sleep` reads something else — that is precisely how the previous \
            spelling-based anchor would have failed silently in the other direction.
            """)
        // The backoff is allowed and must stay CONDITIONAL. If it ever engaged without the
        // interruption term, the publish would slow to ~0.2 Hz while frames were arriving, and
        // every time constant derived from ~1 Hz would be five times too slow — #315/#332/#336
        // once more, from a new direction.
        XCTAssertTrue(code.contains("tickSeconds = (self.heldQuiet && self.capture.isInterrupted)"), """
            The slow period is no longer gated on BOTH a held interruption and six seconds of \
            silence. Unconditional, it would relax the ~1 Hz publish cadence this whole file \
            exists to pin — while nothing else here would notice, because `tick % 10` and the \
            constant would both still be intact.
            """)
    }

    /// Every consumer of `latestBio` must dedupe on the frame's timestamp. That dedupe is
    /// what turns a 10 Hz poll into a ~1 Hz apply — remove it anywhere and that consumer
    /// silently starts running its smoothers ten times faster than the others, which is a
    /// divergence no single-file review can see.
    func testEveryBioConsumerDedupesOnTheFrameTimestamp() throws {
        // Each entry: the file, and the token that proves it compares against a remembered
        // timestamp. Deliberately the WHOLE comparison and not just the property name — a
        // stored `lastFrameTimestamp` that nothing reads would satisfy a name-only check.
        let consumers: [(String, String)] = [
            ("Sources/Echoelmusic/Tools/PolySynthVoice.swift",        "frame.timestamp != lastTimestamp"),
            ("Sources/Echoelmusic/Tools/BioReactiveSynthVoice.swift", "frame.timestamp != lastTimestamp"),
            ("Sources/Echoelmusic/Core/ModulationEngine.swift",       "frame.timestamp != lastFrameTimestamp"),
            ("Sources/Echoelmusic/Core/SessionRecorder.swift",        "frame.timestamp != lastFrameTimestamp"),
            ("Sources/Echoelmusic/Core/BioFeedbackPublisher.swift",   "frame.timestamp != lastPublishedTimestamp")
        ]
        for (path, token) in consumers {
            let code = try source(path)
            XCTAssertTrue(code.contains(token), """
                \(path) no longer dedupes bio frames on their timestamp. It will now apply \
                the SAME frame up to ten times per second while every sibling applies it \
                once — so its smoothing constants mean something different from theirs, and \
                nothing in that file looks wrong. This is the exact mechanism behind #315.
                """)
        }
    }

    /// The counters that COUNT the apply rate must stay unobserved. This is the second half
    /// of the same law and the one that bites differently: correcting the rate downward
    /// reads as permission to relax `@ObservationIgnored`, and it is not — the poll is a
    /// ceiling a faster publisher reaches without any of these lines changing, and a read in
    /// a view body tears down open `.menu` Pickers (10.76.48 / 10.76.50).
    func testTheApplyCountersStayUnobserved() throws {
        for path in ["Sources/Echoelmusic/Tools/PolySynthVoice.swift",
                     "Sources/Echoelmusic/Tools/BioReactiveSynthVoice.swift"] {
            let code = try source(path)
            guard let r = code.range(of: "var framesApplied") else {
                return XCTFail("`framesApplied` is gone from \(path) — re-point this guard.")
            }
            // Look back a short way: the attribute sits on the line above the declaration.
            //
            // ⛔ TWO STATEMENTS ON PURPOSE. The one-liner
            //     code[code.index(…, limitedBy: code.startIndex) ?? code.startIndex ..< r.lowerBound]
            // does not mean what it reads like, and it took the blocking gate down: `..<`
            // (RangeFormationPrecedence) binds TIGHTER than `??` (NilCoalescingPrecedence),
            // so Swift parses it as `index(…) ?? (startIndex ..< lowerBound)` — a
            // `String.Index?` coalesced with a `Range<String.Index>` — and reports it as
            // "type of expression is ambiguous without a type annotation", which points at
            // the subscript rather than at the operator that actually caused it.
            let lower: String.Index = code.index(r.lowerBound,
                                                 offsetBy: -220,
                                                 limitedBy: code.startIndex) ?? code.startIndex
            let head = code[lower ..< r.lowerBound]
            XCTAssertTrue(head.contains("@ObservationIgnored"), """
                `framesApplied` in \(path) is no longer `@ObservationIgnored`. As a tracked \
                `@Observable` property it invalidates every view that reads it on each new \
                bio frame — the "menus freeze while playing" class. The apply rate being \
                ~1 Hz rather than 10 Hz does NOT make this safe: the 10 Hz poll is a ceiling \
                a faster publisher can reach without this file changing.
                """)
        }
    }

    /// The architecture line itself. It is the sentence sessions plan time constants from,
    /// so it must keep both numbers AND their relationship — a line that says only "1 Hz"
    /// would invite someone to treat 1 Hz as a guarantee and size a buffer for it.
    func testTheArchitectureLineStillCarriesBothRates() throws {
        let claude = try source("CLAUDE.md")
        XCTAssertFalse(claude.contains("snapshot (10 Hz poll)"), """
            CLAUDE.md's architecture line claims a "10 Hz poll" as the bio rate again. That \
            exact phrasing produced #315, #332 and #336. The poll is 10 Hz; the APPLY rate \
            is ~1 Hz, and time constants must be derived from the latter.
            """)
        XCTAssertTrue(claude.contains("BioApplyRateIsTheDedupedRateTests"), """
            CLAUDE.md no longer references this guard. That is allowed — but then this file \
            protects a claim nobody is making, and the pair should go together. (The reverse \
            case is what created this file: the reference shipped without the file.)
            """)
    }

    // MARK: - helpers

    private func source(_ path: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                Source tree not reachable from the test bundle — skipping rather than \
                reporting a green this file did not earn.
                """)
        }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
