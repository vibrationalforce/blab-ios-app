// TheCoalescingGateGuardsAReaderlessSnapshotTests.swift
// Echoel — #952. Blocking bundle.
//
// ⭐ WHY THIS EXISTS. #951 collapsed `EngineBus.publish(controller:)`'s per-event
// `Task { @MainActor }` into ONE wake-up per batch. `EngineBus` has FOUR such publishes, and
// the obvious next move — "finish the job, coalesce the other three" — would break the app
// silently. This guard is here so that move goes red instead of shipping.
//
// **The gate is FIRST-WINS.** The single task captures the event that opened it, so the
// snapshot it writes is the FIRST of the batch, not the latest. That is harmless on the
// controller path for exactly one reason, and it is a measured one:
//
//     latestControllerEvent   0 reader files outside EngineBus.swift
//     latestBioEvent          1
//     latestMusical           1
//     latestBio              11   ← the four wire senders (OSC · Art-Net · sACN · ADM-OSC),
//                                   the three voices (BioReactiveSynth · PolySynth · FXBio-
//                                   Modulator), BioEventPublisher, SessionRecorder, and
//                                   exactly TWO surfaces: AlwaysOnBioRow and EchoelFXView
//
// ⛔ THE FIRST VERSION OF THIS BLOCK SAID 0 / 2 / 3 / 25, AND ALL THREE NON-ZERO FIGURES WERE
// A HAND-GREP, not this guard's measurement — the defect `.claude/rules/context.md` §2 names
// outright ("when a hand survey and an executable check disagree, the check is the
// measurement"). `git grep -l` counts PROSE (this repo argues about these symbols at length in
// comments) and it counts SUBSTRINGS: `latestBio` is contained in `latestBioEvent`, so every
// reader of the event snapshot was reported as a reader of the bio snapshot too. The numbers
// above are what `isSymbol` finds over comment-stripped source — the same thing the assertions
// below run on. **The asymmetry survives the correction and is the whole argument: 11 against
// 0.** Two operations, two numbers: 25 files MENTION `latestBio`, 11 READ it, and only the
// second is what a coalescing decision turns on.
//
// ⛔ AND THE ILLUSTRATIVE LIST WAS WRONG A SECOND TIME, in the same direction. It said "every
// bio surface, the modulation engine, CoherenceTrend". Measured: `ModulationEngine` and
// `CoherenceTrend` mention the symbol only in COMMENTS, and of nine bio surfaces exactly two
// read it — `AlwaysOnBioRow` and `EchoelFXView`. In a file whose whole subject is which
// snapshot is read by whom, an enumeration that counts prose as readers is the very thing it
// exists to prevent. Both corrections came from the mandatory review, not from a guard.
//
// On a snapshot nobody reads, first-vs-latest is not a question. On `latestBio` it is the
// whole meaning of the value: eleven files ask "what is the body doing NOW", and a first-wins
// gate would answer with the oldest frame of every batch. The consumers would not crash, they
// would quietly lag — the worst failure shape this repo has (a wire that looks connected).
//
// ⚠️ THIS DOES NOT FORBID COALESCING THE OTHER THREE (#364). It forbids giving them THIS gate.
// A latest-wins structure — a single atomic mailbox, which `SPSCQueue`'s own doc already names
// as the right shape for "newest wins" — is a legitimate future slice, and it would keep every
// assertion here green because it would not introduce `notifyScheduled`.
//
// ⚠️ HONEST GRADING, AND THE COUNT IS WRITTEN OUT BECAUSE TWO CLAIMS LOOP — a loop hides its
// number, and that has cost a grading in this repo three times. Claim 1: 1. Claim 2: 3 (one
// per snapshot). Claim 3: 1 declaration + 1 present + 3 absent (one per non-coalesced
// publish). Claim 4: 2.
// **11 assertions, 0 REGRESSION CATCHES** against the tree it was cut from,
// and that is the correct number rather than a modest one: this is an INVARIANT guard, not a
// bug fix, and the whole point is that nothing is broken today. Claiming catches it does not
// have would be the flattering direction (#433/#464). Against the pre-#951 tree claim 3a would
// be red — the gate did not exist yet — but that tree is behind us and quoting it would be
// arithmetic about a scenario nobody can reach.
//
// ⚠️ MIXED FILE (§1): claims 1–3 are SOURCE-TEXT SCANS, labelled as such at each claim;
// claim 4 is END-TO-END BEHAVIOUR on a shipped, constructible type.
//
// ⚠️ NOT A DUPLICATE OF `EngineBusTests.testPublishBio_updatesLatestSnapshot` (#416), which
// asserts the same runtime property as claim 4a: that suite is compiled by NO gate (#208), so
// its assertion cannot protect anything. Said here so the next reader does not file this as
// redundant. `ControllerEventDrainIsPushedTests` pins the hook's declaration, invocation and
// single installer — no overlap. `TheControllerNotifyIsCoalescedTests` pins the coalescing
// BEHAVIOUR and states the reader-less premise as PROSE ONLY; claim 1 makes that prose
// executable, which is the #416 answer rather than a restatement.
//
// ⚠️ Re-deriving these counts by hand needs BOTH corrections, which is why no one-liner is
// offered: strip comments first, and require the character after the match not to be a letter,
// digit or `_`. `git grep -l` does neither and over-counts on both axes. The executable form is
// `isSymbol` below; run the guard.

import Foundation
import XCTest
@testable import Echoelmusic

/// File scope, not nested: a nested type would compile too (nested types do not inherit a
/// global actor), but the one precedent in this bundle — `TheHeldFrameSurvivesAResolutionFlip
/// Tests`'s `FlipAnchorMissing` — puts it here, and with no local toolchain (§0) matching the
/// precedent exactly costs one line and removes the file's only unprecedented shape.
private struct CoalesceAnchorMissing: Error, CustomStringConvertible {
    let reason: String
    var description: String { reason }
}

@MainActor
final class TheCoalescingGateGuardsAReaderlessSnapshotTests: XCTestCase {

    private static let bus = "Sources/Echoelmusic/Core/EngineBus.swift"

    private func repoRoot() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        return root
    }

    /// Every `.swift` file under `Sources/`, comment-stripped, EXCEPT `EngineBus.swift` itself
    /// — the declaration and the one write live there and are not readers. Comments are
    /// stripped because this very asymmetry is discussed in prose inside several of these
    /// files, `EngineBus` included (#453 — one stripper, `SourceText.codeOnly`).
    ///
    /// ⚠️ **PROPHYLACTIC for the VERDICTS — 0 of 11 flip** — and **load-bearing for the
    /// COUNTS**: raw text reports 25 / 2 / 3 readers where stripped reports 11 / 1 / 1, and it
    /// is the counts this file's argument is made of (§2).
    private func consumerCode(excluding excluded: String) throws -> [String: String] {
        let root = try repoRoot()
        let sources = root.appendingPathComponent("Sources")
        var out: [String: String] = [:]
        guard let walk = FileManager.default.enumerator(atPath: sources.path) else {
            throw CoalesceAnchorMissing(reason: "could not walk \(sources.path)")
        }
        for case let rel as String in walk where rel.hasSuffix(".swift") {
            let full = "Sources/" + rel
            if full == excluded { continue }
            let url = sources.appendingPathComponent(rel)
            // `try?` + skip, matching `TheAudioLanesHaveNoProducerTests`: one unreadable file
            // must not fail a scan whose subject is elsewhere. The `> 100` anchor below is what
            // catches a walk that skipped too much.
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            out[full] = SourceText.codeOnly(text)
        }
        guard out.count > 100 else {
            throw CoalesceAnchorMissing(reason: """
                Only \(out.count) source files walked — this scan found nothing rather than \
                nothing wrong (#454). Re-anchor before trusting any count below.
                """)
        }
        return out
    }

    /// `latestBio` is a SUBSTRING of `latestBioEvent`, so a plain `contains` would report every
    /// event-snapshot reader as a bio-snapshot reader. The trailing character is therefore
    /// checked: a match followed by a letter, digit or `_` is a longer identifier, not this one.
    ///
    /// ⚠️ **PROPHYLACTIC — 0 of 11 file verdicts flip** (`Tests/CISmoke/CLAUDE.md` §2). ⛔ The
    /// first version of this comment said "A PLAIN `contains` WOULD LIE HERE", and measured, it
    /// does not lie today: the single comment-stripped `latestBioEvent` reader is
    /// `BioReactiveSynthVoice`, which reads `latestBio` standalone as well, so both matchers
    /// return the identical file list. Claiming a lie it prevented is the flattering direction
    /// (#433/#464) — and this directory has retracted three "load-bearing" claims that were
    /// never measured. The helper stays because the hazard is one rename away, not because it
    /// caught something.
    ///
    /// The LEADING side needs no check: Swift member access puts a `.` before the name, and no
    /// identifier in this repo ends in `latestBio`.
    private func isSymbol(_ name: String, in code: String) -> Bool {
        var searchFrom = code.startIndex
        while let hit = code.range(of: name, range: searchFrom..<code.endIndex) {
            if hit.upperBound == code.endIndex { return true }
            let next = code[hit.upperBound]
            if !next.isLetter && !next.isNumber && next != "_" { return true }
            searchFrom = hit.upperBound
        }
        return false
    }

    private func readers(of symbol: String, in code: [String: String]) -> [String] {
        code.filter { isSymbol(symbol, in: $0.value) }.keys.sorted()
    }

    /// The brace-matched body of a `publish` overload.
    private func publishBody(_ signature: String, in text: String) throws -> String {
        let hits = text.components(separatedBy: signature).count - 1
        guard hits == 1, let start = text.range(of: signature),
              let open = text[start.upperBound...].firstIndex(of: "{") else {
            throw CoalesceAnchorMissing(reason: """
                `\(signature)` occurs \(hits)× in \(Self.bus); this scan needs exactly one so \
                it cannot read a different member. Re-anchor it in the same commit.
                """)
        }
        var depth = 0
        var out = ""
        var i = open
        while i < text.endIndex {
            let c = text[i]
            if c == "{" { depth += 1 }
            if c == "}" { depth -= 1; if depth == 0 { return out } }
            out.append(c)
            i = text.index(after: i)
        }
        throw CoalesceAnchorMissing(reason: "unbalanced braces after `\(signature)`")
    }

    /// claim 1 (SOURCE-TEXT SCAN) — **THE PREMISE #951 RESTS ON.** The coalesced snapshot has no reader.
    func testTheControllerSnapshotStillHasNoReader() throws {
        let code = try consumerCode(excluding: Self.bus)
        let found = readers(of: "latestControllerEvent", in: code)

        XCTAssertEqual(found, [], """
            `latestControllerEvent` gained a reader: \(found)

            #951's coalescing gate is FIRST-WINS — the single task writes the event that OPENED \
            the batch, not the latest one — and the only reason that is safe is that nothing \
            reads this snapshot. A reader now sees the oldest event of every burst.

            Repair, and it is a choice not a revert: either drop the read, or change the gate \
            to a latest-wins structure (a single atomic mailbox — `SPSCQueue`'s own doc names \
            that as the right shape for "newest wins"). Do NOT simply delete this assertion.
            """)
    }

    /// claim 2 (SOURCE-TEXT SCAN, COUNTERWEIGHT) — the other three snapshots DO have readers.
    /// ⚠️ Its precise value is narrower than "the walk might be broken": a broken walk already
    /// throws at the `> 100` anchor. What claim 2 UNIQUELY catches is a walk that succeeds
    /// while `codeOnly` returns empty — then claim 1 would pass for the wrong reason (#488)
    /// and nothing else would notice.
    func testTheOtherSnapshotsAreReadAndAreThereforeNotCandidates() throws {
        let code = try consumerCode(excluding: Self.bus)

        for symbol in ["latestBio", "latestBioEvent", "latestMusical"] {
            let found = readers(of: symbol, in: code)
            XCTAssertFalse(found.isEmpty, """
                `\(symbol)` has no reader outside \(Self.bus) — either the walk is broken (then \
                claim 1 proves nothing either) or a whole consumer path was removed. \
                `latestBio` alone had 11 reader files when this guard was written (measured the \
                way this guard measures, not by `git grep`): the four wire senders, three \
                voices, `BioEventPublisher`, `SessionRecorder`, `AlwaysOnBioRow` and \
                `EchoelFXView`. Measure before believing this failure.
                """)
        }
    }

    /// claim 3 (SOURCE-TEXT SCAN) — the gate is on the reader-less path and ONLY there.
    func testTheFirstWinsGateIsOnlyOnTheControllerPublish() throws {
        let root = try repoRoot()
        let text = SourceText.codeOnly(
            try String(contentsOf: root.appendingPathComponent(Self.bus), encoding: .utf8))

        // 3a-i — the DECLARATION, so a RENAME fails with a message that says "renamed"
        // rather than turning 3a red with "removed" while 3b–3d go silently vacuous. This
        // directory has paid three times for a guard anchored on a spelling alone.
        XCTAssertEqual(
            text.components(separatedBy: "nonisolated(unsafe) private var notifyScheduled")
                .count - 1, 1, """
            The coalescing flag's declaration is not present exactly once in \(Self.bus). If it \
            was RENAMED, the three absence assertions below stop measuring anything (a needle \
            that cannot match is always absent) — rename it in them too, in this commit.
            """)

        let controller = try publishBody(
            "nonisolated public func publish(controller event: ControllerEvent)", in: text)
        XCTAssertTrue(controller.contains("notifyScheduled"), """
            `publish(controller:)` no longer carries #951's coalescing gate. If it was removed \
            on purpose, the per-event `Task { @MainActor }` is back — the 10.76.48 \
            executor-starvation shape from a source that can send thousands of messages a \
            second — and this file, `EngineBus`'s own doc and the HARNESS_LEDGER row move with \
            it (#456).
            """)

        for (signature, symbol) in [
            ("nonisolated public func publish(bio frame: BioSampleFrame)", "latestBio"),
            ("nonisolated public func publish(bioEvent event: BioEvent)", "latestBioEvent"),
            ("nonisolated public func publish(musical frame: MusicalFrame)", "latestMusical")
        ] {
            let body = try publishBody(signature, in: text)
            XCTAssertFalse(body.contains("notifyScheduled"), """
                `\(signature)` picked up #951's FIRST-WINS gate, and `\(symbol)` HAS readers \
                (claim 2). Its consumers would then see the OLDEST frame of every batch — they \
                would not crash, they would quietly lag, which is the worst failure shape this \
                repo has.

                Coalescing this path is not forbidden (#364); giving it THIS gate is. Use a \
                latest-wins mailbox instead, and claim 3 stays green because that introduces no \
                `notifyScheduled`.
                """)
        }
    }

    /// claim 4 (COUNTERWEIGHT, RUNTIME) — the property the eleven readers depend on: the
    /// bio snapshot tracks what was published last. Source text alone cannot see this.
    func testTheBioSnapshotStillTracksThePublishedFrame() async {
        let bus = EngineBus()
        // The full memberwise shape, copied from `ADMOSCAbsenceTests` rather than guessed —
        // `BioSampleFrame` has no defaulted initialiser and there is no local toolchain (§0).
        let a = BioSampleFrame(timestamp: 1, heartRateBPM: 60, hrvNormalized: 0.4,
                               breathRate: 0, breathPhase: 0, coherence: 0,
                               motionEnergy: 0, source: .cameraPPG)
        let b = BioSampleFrame(timestamp: 2, heartRateBPM: 90, hrvNormalized: 0.4,
                               breathRate: 0, breathPhase: 0, coherence: 0,
                               motionEnergy: 0, source: .cameraPPG)

        bus.publish(bio: a)
        for _ in 0..<40 where bus.latestBio == nil { await Task.yield() }
        XCTAssertEqual(bus.latestBio?.timestamp, a.timestamp, """
            The first published bio frame never reached `latestBio`. Eleven files read \
            this snapshot; if it stops tracking, every bio surface and every wire protocol \
            goes stale without an error.
            """)

        bus.publish(bio: b)
        for _ in 0..<40 where bus.latestBio?.timestamp != b.timestamp { await Task.yield() }
        XCTAssertEqual(bus.latestBio?.timestamp, b.timestamp, """
            A SECOND published bio frame did not replace the first. This is exactly what a \
            first-wins gate on this path would do — the batch's opening frame would stick — \
            and it is why claim 3 forbids that gate here.
            """)
    }
}
