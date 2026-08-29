// TheAudioLanesHaveNoProducerTests.swift
// Echoel — a transport-driven executor with nothing to execute. #527.
//
// WHAT WAS WRONG, and it was a capability claim in the header of the file that owns the
// capability. `AudioLanePlayer.swift` said it is "WIRED since v191 … audio lanes now sound
// in time with the arrangement". Wired is TRUE — `EchoelmusicApp` constructs it and
// `TimelineRegionPlayer` calls prime/apply/stop on every transport step. Sounding is not:
// nothing a user can reach ever puts an audio region on an audio lane, so `apply` walks
// `doc.audioLaneIDs` and finds nothing to play.
//
// ⭐ THE MEASUREMENT, because "no door" is a claim like any other. There are FIVE
// `TimelineRegion(` construction sites in `Sources/`, and every one is accounted for:
//   · `TimelineStore.migrate(sections:)` seeds an empty `Audio 1` lane and puts EVERY
//     region on the MIDI lane — driven end-to-end below, not scanned.
//   · `ensureComposerRegion` / `ensureUserMidiRegion` build their clip `kind: .midi` by
//     construction — TRUE of both, and the only thing that is. ⛔ #865: this file used to
//     call them "the two region creators a door can reach", and that is HALF false.
//     Measured 2026-08-29: `.ensureComposerRegion(` has one production caller
//     (`Studio/EchoelStudioView.swift:10129`); `.ensureUserMidiRegion(` has **ZERO** — its
//     only callers are in the non-blocking `UserMidiRegionStoreTests`. It belongs with the
//     `RecordController` chain below as BUILT-BUT-DOORLESS, not up here as reachable.
//     The conclusion gets STRONGER, not weaker: one fewer reachable creator. That is why it
//     survived — a wrong reason pointing at a right answer is invisible until someone reads
//     the reason (#367), and the test name said "Reachable" too (#374).
//   · `RecordController` and `AudioClipFactory` are the only two that could produce an
//     audio-bearing region, and that chain is doorless: `AudioClipFactory` is called only
//     from `TakeRecorder`, `TakeRecorder` is constructed only from `RecordController`, and
//     `RecordController.arm()` has zero callers (#204).
// The arrangement UI that would have made one went with #121 Slice 4.
//
// ⚠️ THIS IS NOT AN ARGUMENT FOR DELETION — the reverse, and that is the point of the two
// counterweights. `TimelineDocument` is PERSISTED and decoded at launch, so a document from
// any build whose recorder path was reachable can still carry an audio region, and this
// coordinator is the only thing that would play it. Unwiring the layer as "dead" would turn
// such a project from obviously absent into silently silent — and the default document
// deliberately still seeds an empty audio lane, because the founder asked for the multi-lane
// shape ("mehrere") from day one.
//
// ⚠️ AND IT DOES NOT FORBID RE-DOORING AUDIO IMPORT (#364). Giving the layer a producer is
// exactly the work this finding argues for. What it forbids is doing it while the header
// still counts zero — when the chain assertions go red for that reason, the fix is to move
// the ⛔ block in `AudioLanePlayer.swift` and the register line in CLAUDE.md IN THE SAME
// COMMIT, not to relax the assertion.
//
// ⚠️ HONEST GRADING (#433/#464/#486). This file COMPILES against the parent tree — it names
// no symbol this commit adds — so every assertion has a verdict there. Transcribed by hand
// (a Python rebuild of `SourceText.codeOnly`, run against `git show HEAD:` and the worktree):
//   · **ONE needle is red on the parent** and it is the whole finding: the header's claim,
//     which on `HEAD` sits on a line with no `SAID` on it.
//   · **FIVE are counterweights**, green on both trees, and they are the value (#343). A
//     tree that fixes the prose and then deletes the wiring, or drops the seeded audio lane,
//     or lets a region creator start making audio clips, satisfies the needle above and
//     breaks what it describes.
//   · The migration assertion drives shipped code end to end — `TimelineStore.migrate` is a
//     pure `static` over `public` Foundation-only value types. The chain assertions are
//     source scans.
//
// ⚠️ `SourceText.codeOnly` IS LOAD-BEARING and that is MEASURED rather than assumed (#484
// and #485 each had to withdraw the stronger claim once, #486 twice) — and my first draft of
// this paragraph got the REASON wrong, which is the more useful half. It claimed the
// corrected header causes the collision by naming `AudioClipFactory` in prose; it does not,
// because the retraction writes the bare type name with no trailing dot. Measured instead:
// **2 of 12 needle-verdicts flip, on BOTH trees**, and the culprit is `AudioClipFactory.swift`
// line 1 — `// AudioClipFactory.swift`, the file's own name. A needle shaped `TypeName.`
// matches every Swift file's header comment, so the chain equality would be RED ON CORRECT
// CODE without the stripper, for a reason that has nothing to do with this slice and applies
// to every scan of that shape anyone writes here.
//
// ⚠️ AND THE LIMIT FIRST. Nothing here plays audio or proves silence on a device. It proves
// that no line in `Sources/` creates an audio-bearing region, and that a sentence and a
// measurement agree. `Tests/CISmoke` is the blocking bundle; a missing tree SKIPS (#454).

import Foundation
import XCTest
@testable import Echoelmusic

@MainActor
final class TheAudioLanesHaveNoProducerTests: XCTestCase {

    private static let sourcesRoot = "Sources/Echoelmusic"
    private static let player = "Sources/Echoelmusic/Sequencer/AudioLanePlayer.swift"

    // MARK: - The finding

    /// The header must not claim audio lanes sound while nothing can fill them.
    ///
    /// ⛔ SCOPED rather than a bare absence scan (#525): the corrected header quotes the
    /// withdrawn sentence in order to withdraw it, so a plain `contains` would be RED ON
    /// CORRECT CODE — and `codeOnly` cannot rescue it either, because the claim lives in a
    /// COMMENT on both trees and the stripper blanks it regardless. Per line: any line
    /// carrying the phrase must also carry `SAID`.
    func testTheHeaderNoLongerClaimsTheLanesSound() throws {
        let phrase = "lanes now sound in time with the arrangement"
        let offenders = try rawText(Self.player)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.contains(phrase) && !$0.contains("SAID") }
        XCTAssertTrue(offenders.isEmpty, """
            `AudioLanePlayer` asserts again that "\(phrase)", outside a retraction:
            \(offenders.joined(separator: "\n"))
            Wired is true; sounding is not. No reachable surface creates an audio-bearing \
            region — the only two producers terminate in `RecordController`, whose `arm()` \
            has zero callers (#204). If audio import HAS been re-doored, this run's chain \
            assertions go red too and the register line in CLAUDE.md is the work.
            """)
    }

    /// The legacy migration seeds an audio lane and puts nothing on it.
    ///
    /// Driven end to end rather than scanned: `migrate` is pure over `public`
    /// Foundation-only value types, so this is real behaviour, not text.
    func testTheMigrationSeedsAnEmptyAudioLane() throws {
        let sections = [
            ArrangementSection(clipID: UUID(), name: "A", lengthBars: 2),
            ArrangementSection(clipID: nil, name: "gap", lengthBars: 1),
            ArrangementSection(clipID: UUID(), name: "B", lengthBars: 4)
        ]
        let doc = TimelineStore.migrate(sections: sections)

        XCTAssertEqual(doc.audioLaneIDs.count, 1, """
            The migrated document no longer carries exactly one audio lane. The empty \
            `Audio 1` lane is deliberate — the founder asked for the multi-lane shape \
            ("mehrere") from day one — and it is what makes the absence of any audio region \
            visible rather than invisible.
            """)
        let audioLane = try XCTUnwrap(doc.audioLaneIDs.first)
        for region in doc.regions {
            XCTAssertNotEqual(region.laneID, audioLane, """
                `TimelineStore.migrate` placed a region on the AUDIO lane. Every region it \
                creates belongs to the MIDI lane; a section carries a MIDI clip. If audio \
                migration is genuinely being added, the header ⛔ block in \
                `AudioLanePlayer.swift` and CLAUDE.md's doorless register both count zero \
                producers and must move in the same commit.
                """)
        }
        XCTAssertFalse(doc.regions.isEmpty, """
            The migration produced no regions at all, so the assertion above passed \
            vacuously (#343). Two of the three fixture sections carry a clip id.
            """)
    }

    /// BOTH MIDI region creators build MIDI clips, by construction. Renamed in #865: the old
    /// name said "Reachable", and only one of the two is (#374 — a test name states a fact).
    func testBothMidiRegionCreatorsMakeMidiClips() throws {
        let store = SourceText.codeOnly(try rawText("\(Self.sourcesRoot)/Core/TimelineStore.swift"))
        for creator in ["ensureComposerRegion", "ensureUserMidiRegion"] {
            let body = try body(of: creator, in: store)
            XCTAssertTrue(body.contains("kind: .midi"), """
                `\(creator)` no longer builds its clip with `kind: .midi`. These two are the \
                only region creators OTHER than the doorless `RecordController` chain — one \
                of them reachable, one not (see the header). If either can now make an audio \
                clip, the audio lanes have a producer and the "no door" claim in \
                `AudioLanePlayer.swift` plus CLAUDE.md's register are both stale. Note what \
                CLAUDE.md actually says: it claims CONSTRUCTION (`kind: .midi`), never \
                reachability, so it is NOT stale today and must not be "corrected" from here.
                """)
        }
    }

    /// The asymmetry itself (#865). Pinned because the prose above is only as good as the
    /// measurement behind it, and that measurement had been wrong for the life of the file.
    ///
    /// ⚠️ THIS FORBIDS NOTHING (#364). Dooring `ensureUserMidiRegion` — giving the user a way
    /// to add their own MIDI clip to a lane — is legitimate, wanted work. This assertion goes
    /// red on the day it lands, and its job is to say WHICH PROSE moves in that same commit,
    /// not to argue against the change. Mitigate by updating; never by deleting.
    func testOnlyOneOfTheTwoMidiCreatorsHasADoor() throws {
        let composerCallers = try filesUnderSources(containing: ".ensureComposerRegion(")
        XCTAssertEqual(composerCallers, ["Studio/EchoelStudioView.swift"], """
            `ensureComposerRegion` is now called from \
            \(composerCallers.isEmpty ? "nothing" : composerCallers.joined(separator: ", ")). \
            If it lost its caller, the composer clip has no producer either and the header's \
            five-site census needs re-reading. If it gained one, say where the second door is.
            """)

        let userCallers = try filesUnderSources(containing: ".ensureUserMidiRegion(")
        XCTAssertTrue(userCallers.isEmpty, """
            `ensureUserMidiRegion` now has a production caller: \
            \(userCallers.joined(separator: ", ")). That is a NEW DOOR, and it is very likely \
            correct work — this is not an objection. It is a checklist. Three places call this \
            creator unreachable and must move in the same commit: (1) this file's header \
            bullet, (2) the failure message of `testBothMidiRegionCreatorsMakeMidiClips`, \
            (3) this test's own name and doc. Verify the new door creates `kind: .midi` only; \
            an audio-bearing clip here would give the audio lanes their first producer and \
            falsify the whole file.
            """)
    }

    // MARK: - Counterweights (#343)

    /// COUNTERWEIGHT — the only audio-bearing producer is still a doorless chain.
    ///
    /// Each link measured separately, because the finding is the CHAIN: a second caller
    /// anywhere along it is a door, and a door is the thing that changes the verdict.
    func testTheOnlyAudioProducerIsStillADoorlessChain() throws {
        let factoryCallers = try filesUnderSources(containing: "AudioClipFactory.")
        XCTAssertEqual(factoryCallers, ["Sequencer/TakeRecorder.swift"], """
            `AudioClipFactory` is now called from \
            \(factoryCallers.isEmpty ? "nothing" : factoryCallers.joined(separator: ", ")). \
            It is the one thing that mints an audio-bearing clip; a second caller is a new \
            path to a sounding audio lane, and the ⛔ block in `AudioLanePlayer.swift` counts \
            on there being exactly one.
            """)

        let recorderBuilders = try filesUnderSources(containing: "TakeRecorder(")
            .filter { $0 != "Sequencer/TakeRecorder.swift" }
        XCTAssertEqual(recorderBuilders, ["Core/RecordController.swift"], """
            `TakeRecorder` is now constructed by \
            \(recorderBuilders.isEmpty ? "nothing" : recorderBuilders.joined(separator: ", ")). \
            The chain that could fill an audio lane runs RecordController → TakeRecorder → \
            AudioClipFactory, and it is inert only because its first link is doorless (#204).
            """)
    }

    /// COUNTERWEIGHT — the layer must stay WIRED.
    ///
    /// The tempting cleanup after reading the finding is to unwire "dead" audio lanes.
    /// `TimelineDocument` is persisted and decoded at launch, so a project written by a build
    /// whose recorder path was reachable can still carry an audio region — and this
    /// coordinator is the only thing that would play it. Unwiring turns "obviously absent"
    /// into "silently silent".
    func testTheLayerIsStillWiredToTheTransport() throws {
        let app = SourceText.codeOnly(try rawText("\(Self.sourcesRoot)/EchoelmusicApp.swift"))
        XCTAssertTrue(app.contains("timelinePlayer.audioLanes = AudioLanePlayer("), """
            `AudioLanePlayer` is no longer attached to the transport in `EchoelmusicApp`. \
            That is not a cleanup: a persisted `TimelineDocument` carrying an audio region \
            would then decode, appear in the arrangement and never make a sound, with \
            nothing left to explain why.
            """)

        let player = SourceText.codeOnly(try rawText(Self.player))
        for entry in ["public func apply(", "public func prime(", "public func stopAll("] {
            XCTAssertTrue(player.contains(entry), """
                `AudioLanePlayer` no longer declares `\(entry)…`. The transport drives the \
                layer through exactly these three; losing one leaves audio lanes that start \
                and never stop, or stop and never start.
                """)
        }
    }

    // MARK: - Reading the source

    /// The brace-matched body of `name` inside `code`, so a needle cannot be satisfied by a
    /// neighbouring declaration. Throws rather than returning "" when the anchor is missing
    /// (#454) — a vanished creator must not read as a pass.
    private func body(of name: String, in code: String) throws -> String {
        guard let start = code.range(of: "func \(name)"),
              let open = code.range(of: "{", range: start.upperBound..<code.endIndex)
        else {
            throw XCTSkip("""
                `func \(name)` is not in TimelineStore.swift — the anchor moved, so this \
                guard SKIPS rather than reporting a green it did not earn
                """)
        }
        var depth = 0
        var index = open.lowerBound
        while index < code.endIndex {
            let character = code[index]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return String(code[open.upperBound..<index]) }
            }
            index = code.index(after: index)
        }
        throw XCTSkip("unbalanced braces after `func \(name)` — refusing to guess its body")
    }

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
