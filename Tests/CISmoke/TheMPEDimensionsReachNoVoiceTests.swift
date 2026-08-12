// TheMPEDimensionsReachNoVoiceTests.swift
// Echoel — #548. `CLAUDE.md` line 39 promised per-note expression to a voice that discards it.
//
// WHAT THIS GUARDS. The always-loaded file's pipeline line read
// "CoreMIDI MPE → controllerEvents → synth notes (performer priority)". Measured, that arrow
// carries three claims and keeps one:
//   · MPE — `MIDIBusPublisher` parses MPE traffic but does NOT disambiguate zones; its own
//     header says "MPE master vs. member channel disambiguation, RPN 6,6 zone detection, and
//     channelPressure are intentionally NOT wired in this first cycle".
//   · → synth — the consumer `BioReactiveSynthVoice.apply(controller:)` handles `.noteOn`,
//     `.noteOff` and `.pitchBend`, and `break`s on `.slide` (CC 74 timbre), `.airCC` and
//     `.channelPressure`: exactly the three dimensions that MAKE it MPE rather than MIDI 1.0.
//     It also never reads `event.channel`, which is where a member channel would arrive.
//   · notes, plural — `heldByController` is a single `Bool` and `playNote` sets one
//     `synth.frequency`. It is ONE monophonic voice, so per-note anything is unreachable by
//     construction, not merely unwired.
// What survives, and the corrected line keeps it: notes, pitch bend and performer priority
// over the breath envelope really do reach the voice.
//
// ⭐ WHY THE GUARD IS ON THE CONSUMER AND NOT ON THE PROSE. The obvious shape — scan
// `CLAUDE.md` for "MPE" — is the #486/#491 collision this repo has already paid for twice:
// that file deliberately quotes retracted claims inside ⛔ blocks, so a negative prose scan
// necessarily meets its own retraction and goes red on the very commit that fixes the text.
// Pinning the CONSUMER instead means the guard reds on the day someone builds a real MPE
// receiver — which is precisely the day the always-loaded line must change back. It fires on
// the right event rather than forbidding correct work (#364).
//
// ⚠️ THE LIMIT. SOURCE-TEXT SCAN. `apply(controller:)` is `private`; the file exposes
// `applyControllerForTests` under `#if DEBUG`, so a behavioural version of claim 1 is
// possible in principle — but it would prove "a slide event changes no audible parameter",
// and this bundle cannot hear. What the text can carry is that the three cases still fall
// into one `break` and that no member channel is read; that is the claim, stated as such.
//
// ⚠️ AND ONE THING THIS FILE DOES NOT TOUCH: the other four surfaces are already honest —
// `docs/faq.html` ("Full MPE zone handling (per-note channels, pressure) … on the roadmap,
// not in the app today"), `docs/architecture.html`, the App Store description and
// `ContentPipeline/CLAIMS.md`. `CLAUDE.md` was the lone outlier, which is why the correction
// borrows the FAQ's already-vetted wording instead of inventing a fifth spelling (#416).
//
// ⚠️ HONEST GRADING — TRANSCRIBED against the parent and this tree. **ZERO REGRESSIONS, and
// that is the correct result, not a gap.** This slice changes PROSE in `CLAUDE.md`; every
// assertion below describes code neither tree touches, so all four are green on both by
// construction. Booking them as caught regressions would be the flattering-direction defect
// (#433). What the file buys is the FUTURE red: the correction cannot silently rot back,
// because the day the consumer grows a real MPE path this guard names the line to rewrite.
//
// ⚠️ `SourceText.codeOnly` is PROPHYLACTIC here, MEASURED (#453) over {4 claims × 2 trees}:
// **0 of 8** verdicts flip. The scanned members carry comments that mention `.slide` and
// `channel`, but every assertion is scoped to a brace-matched body and asks about tokens that
// the comments happen not to spell in a way that would flip a verdict. Said plainly rather
// than claimed load-bearing — three slices in this repo asserted that without measuring and
// had to retract.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheMPEDimensionsReachNoVoiceTests: XCTestCase {

    private static let voice = "Sources/Echoelmusic/Tools/BioReactiveSynthVoice.swift"
    private static let bus = "Sources/Echoelmusic/Core/EngineBus.swift"

    /// The correction this guard protects, quoted so a failure can point at it precisely.
    private static let prose = """
        CLAUDE.md's pipeline line (search for `controllerEvents → `). It must not promise MPE, \
        per-note expression or polyphony from this path. The already-vetted wording lives in \
        `docs/faq.html`: notes, pitch bend and CC 74 slide are PARSED; full MPE zone handling \
        (per-note channels, pressure) is roadmap, not in the app today.
        """

    // MARK: - claim 1 — the three MPE dimensions land in one `break`

    func testTheThreeExpressionDimensionsAreDiscarded() throws {
        let body = try memberBody("private func apply(controller event: ControllerEvent)",
                                  in: Self.voice)
        XCTAssertTrue(body.contains("case .slide, .airCC, .channelPressure:"), """
            `BioReactiveSynthVoice.apply(controller:)` no longer discards slide, air CC and \
            channel pressure in one case. If you gave any of them an effect, this voice has \
            started to honour per-note expression and \(Self.prose)
            """)
        // The `break` must be the WHOLE handling. A body that grew statements under that case
        // would keep the needle above green while the behaviour changed — the "green for a
        // reason that no longer exists" failure this bundle exists to prevent (#456).
        guard let caseRange = body.range(of: "case .slide, .airCC, .channelPressure:") else {
            return   // already failed above with a message that says what to do
        }
        let rest = body[caseRange.upperBound...]
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        XCTAssertEqual(rest.first, "break", """
            The slide/air/pressure case is no longer a bare `break` — its first statement is \
            "\(rest.first ?? "")". Something now happens for those events, so \(Self.prose)
            """)
    }

    // MARK: - claim 2 — no member channel is read, so no zone can exist

    func testTheVoiceReadsNoMemberChannel() throws {
        let body = try memberBody("private func apply(controller event: ControllerEvent)",
                                  in: Self.voice)
        XCTAssertFalse(body.contains("event.channel"), """
            `apply(controller:)` now reads `event.channel`. That is where an MPE member \
            channel arrives, so this voice may have started distinguishing per-note zones — \
            the capability `CLAUDE.md` used to claim. Good news, and it means \(Self.prose)
            """)
    }

    // MARK: - claim 3 — one voice, so "notes" plural was never reachable here

    func testThePerformerPathIsMonophonic() throws {
        let code = try source(Self.voice)
        XCTAssertTrue(code.contains("private var heldByController = false"), """
            `heldByController` is no longer a single `Bool`. If the performer path became \
            polyphonic, "synth notes" is finally true of it and \(Self.prose)
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHT) — the true half is still true

    /// #343. A file that only asserts "MPE does not arrive" stays green on a tree that deleted
    /// external MIDI input altogether, leaving a corrected sentence that is now wrong the other
    /// way. So pin what the corrected line still promises: the dimensions exist on the event
    /// type (they are IGNORED, not absent), and notes and bend still reach the voice.
    func testNotesAndBendStillReachTheVoice() throws {
        let busCode = try source(Self.bus)
        for dimension in ["case channelPressure", "case slide", "case airCC"] {
            XCTAssertTrue(busCode.contains(dimension), """
                `ControllerEvent.Kind` no longer carries `\(dimension)`. The point of the \
                corrected prose is that these dimensions are PARSED and then ignored by the \
                voice; if the event type stopped carrying them, the honest sentence changes \
                again — \(Self.prose)
                """)
        }
        XCTAssertTrue(busCode.contains("public let channel: UInt8"), """
            `ControllerEvent.channel` is gone. Claim 2 asserts the voice does not READ it, \
            which only means something while the field exists to be read.
            """)
        let body = try memberBody("private func apply(controller event: ControllerEvent)",
                                  in: Self.voice)
        for handled in ["case .noteOn:", "case .noteOff:", "case .pitchBend:"] {
            XCTAssertTrue(body.contains(handled), """
                `apply(controller:)` no longer handles `\(handled)`. External MIDI notes and \
                bend are the half of the pipeline line that IS true; if they stopped arriving, \
                the corrected sentence overstates in the other direction — \(Self.prose)
                """)
        }
    }

    // MARK: - source access

    private struct MPEAnchorMissing: Error { let reason: String }

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

    /// Comment-stripped source (#453 — one stripper for the whole bundle). A SKIP without a
    /// checkout, a FAILURE when a named file moved (#454: a skip passes CI).
    private func source(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw MPEAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// The brace-matched body of `signature`. Brace-matched rather than a line window because
    /// this repo writes 30-line comment blocks between statements and `codeOnly` preserves line
    /// count, so any fixed window is unsound by construction (#408/#489). The signature is
    /// asserted UNIQUE first: an anchor that occurs twice can silently read the wrong member.
    private func memberBody(_ signature: String, in relativePath: String) throws -> String {
        let text = try source(relativePath)
        let hits = text.components(separatedBy: signature).count - 1
        guard hits == 1 else {
            throw MPEAnchorMissing(reason: """
                `\(signature)` occurs \(hits)× in \(relativePath); this scan needs exactly one \
                so it cannot read a different member. Re-anchor it.
                """)
        }
        guard let start = text.range(of: signature),
              let open = text[start.upperBound...].firstIndex(of: "{") else {
            throw MPEAnchorMissing(reason: "no body after `\(signature)` in \(relativePath)")
        }
        var depth = 0
        var out = ""
        var i = open
        while i < text.endIndex {
            let c = text[i]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { return out }
            }
            out.append(c)
            i = text.index(after: i)
        }
        throw MPEAnchorMissing(reason: "unbalanced braces after `\(signature)`")
    }
}
