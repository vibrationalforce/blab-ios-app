// TheMPEDimensionsReachNoVoiceTests.swift
// Echoel — #548. `CLAUDE.md` line 39 promised per-note expression to a voice that discards it.
//
// WHAT THIS GUARDS. The always-loaded file's pipeline line read
// "CoreMIDI MPE → controllerEvents → synth notes (performer priority)". Measured, that arrow
// carries three claims and keeps one:
//   · MPE — `MIDIBusPublisher` parses MPE traffic but does NOT disambiguate zones; its own
//     header names "MPE master vs. member channel disambiguation, RPN 6,6 zone detection, and
//     channelPressure" as absent. (⛔ That header used to end the sentence with "intentionally
//     NOT wired in this first cycle" and #770 struck those words — see claim 6. The quotation
//     is trimmed to the half that still exists verbatim; a citation of a live file that no
//     longer contains the quoted words is the stale-witness defect, #472.)
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
// ⚠️ THE OTHER PROSE SURFACES ARE ALREADY HONEST — `docs/faq.html` ("Full MPE zone handling
// (per-note channels, pressure) … on the roadmap, not in the app today"),
// `docs/architecture.html`, the App Store description and `ContentPipeline/CLAIMS.md`. That is
// why the correction borrows the FAQ's already-vetted wording instead of inventing a fifth
// spelling (#416).
//
// ⛔ AND THIS PARAGRAPH SAID "`CLAUDE.md` WAS THE LONE OUTLIER". IT WAS NOT (#766). Every one
// of the five surfaces #548 enumerated is PROSE. `SignalRouter`'s SOURCE port was still named
// "MIDI / MPE In", rendered by `PatchbayView` behind the reachable `showRouting` sheet — the
// only surface a player reads WHILE PATCHING, and it carried the claim for two months after
// the prose was corrected. `testTheRoutingScreenOffersNoMPEInput` is the sixth. **A capability
// claim has as many surfaces as somebody enumerates**; "all of them checked" only ever means
// "all the ones I thought of".
//
// ⛔ AND THE SIXTH WAS NOT THE LAST EITHER (#770) — the SEVENTH is a GATTUNG this file had
// not looked at once. Surfaces one to five were prose a founder reads; six was a label a player
// reads; seven is what a DEVELOPER reads: `MIDIInput`'s own class doc ("Minimal CoreMIDI input
// receiver for MIDI 2.0, MPE, and standard MIDI") and the `os_log` line at the end of its
// `setupMIDI()` ("MIDI: Input ready (MIDI 2.0 + MPE + network)"). The detection sign worked
// exactly as written down after #768: when every checked surface shares one GATTUNG, the
// ENUMERATION is what was incomplete, not the care taken over each item.
//
// ⭐ AND MEASURING IT MADE THE FINDING SHARPER THAN THE COPY FIX. `MIDIBusPublisher`'s header
// called channel pressure "intentionally NOT wired in this first cycle" — a WIRING gap, which
// sends a session to that class to attach a callback. There is no callback:
// `MIDIEventParse.event(word0:word1:)` has no case for Channel Pressure (0xD0 in the MIDI 1.0
// branch, 0xD in the MIDI 2.0 branch) in EITHER switch, and `MIDIInEvent` has no case to carry
// one. The byte is dropped by `default: return nil` one layer below any wiring. Claim 6 pins
// that, so the note can never drift back to naming the wrong file.
//
// ⛔ THE EIGHTH SURFACE (#774) IS THE FILE WHOSE ONLY JOB IS TO PREVENT THIS. Claim 3 below
// has pinned "one monophonic voice" in the CODE since #548 — and `ContentPipeline/CLAIMS.md`,
// the register a video script is required to read before writing a caption, still listed
// "**MIDI-Eingang**: externer Controller spielt die Stimmen". Plural. The very word #548 struck
// from `CLAUDE.md` for being unreachable by construction, sitting for months in the one file
// that exists to keep captions honest. Measured again for #774, comment-stripped: outside
// `EngineBus` there is exactly ONE consumer of `controllerEvents`. `PolySynthVoice` does call
// `start(subscribing:)` but never reads that topic, and `LaneVoiceRack`'s bio voice says in its
// own comment that it is "NEVER subscribed to the bus".
//
// ⭐ AND THE ROW DIRECTLY BELOW IT WAS SCRUPULOUS THE WHOLE TIME — "gespielte NOTEN an dein Rig
// (MIDI 1.0)", switch and default named. **Writing one line honestly does not harden the line
// next to it.** That is the sharpest form of the enumeration lesson so far: the two rows are
// adjacent, one author, one table, and only one of them was checked.
//
// ⚠️ AND THE OBVIOUS OVER-CORRECTION WAS CHECKED AND REJECTED: the MIDI input is NOT hidden
// behind the "Body voice" arm switch. `apply(controller:)` is deliberately not `isArmed`-gated
// ("the performer always leads", `BioReactiveSynthVoice.swift:285`) — only the BREATH path is.
// A controller sounds immediately; it is merely monophonic. Claim 8 asserts the copy, and
// claim 4 already pins the arm-independence premise it rests on.
//
// ⚠️ HONEST GRADING FOR #766 (parent `c1d285b`), TRANSCRIBED in Python against both trees:
// **claim 5 is a REGRESSION** — the `id: "midi.in"` line reads `name: "MIDI / MPE In"` on the
// parent and `name: "MIDI In"` here. Claims 1-4 stay COUNTERWEIGHTS, green on both; they are
// the premises that make claim 5 true rather than a style preference.
//
// ⭐ EARLIER GRADING FOR #548 (the commit that created this file): **ZERO REGRESSIONS, and that
// was the correct result, not a gap.** That slice changed PROSE in `CLAUDE.md`; every assertion
// described code neither tree touched, so all four were green on both by construction. Booking
// them as caught regressions would have been the flattering-direction defect (#433). What the
// file bought was the FUTURE red — and #766 is the first instalment of exactly that.
//
// ⚠️ HONEST GRADING FOR #774 (parent `534a9f3`), TRANSCRIBED in Python against both trees:
// **claim 8 is a REGRESSION CATCH** — the `**MIDI-Eingang**` row reads "spielt die Stimmen" on
// the parent and names one monophonic voice here. #367 driven: restoring the plural into the
// row turns it red; relabelling the row makes the ANCHOR fail rather than pass silently (#454);
// and a CONTROL confirms the new §6b, which QUOTES the struck wording, leaves it green — the
// #491 trap the row anchor exists to avoid. Claims 1-7 are unchanged COUNTERWEIGHTS here.
//
// ⚠️ HONEST GRADING FOR #770 (parent `4267cb5`), TRANSCRIBED in Python against both trees:
// **`testTheInputLogLineDoesNotAnnounceMPE` is a REGRESSION CATCH** — the log literal reads
// "(MIDI 2.0 + MPE + network)" on the parent and "(MIDI 1.0 + 2.0 notes/CC/bend + network)"
// here. **`testTheInputPathParsesNoChannelPressure` is a COUNTERWEIGHT, green on both** (#343):
// it pins the premise that makes the retraction more than a wording preference, and it is the
// assertion that goes red the day the follow-up is really built. Both were driven against
// deliberately mutated trees (#367) — adding `case channelPressure` to `MIDIInEvent`, adding
// `case 0xD0:` to the MIDI 1.0 switch, and adding `case 0xD:` to the MIDI 2.0 switch each turn
// the intended assertion red, and a CONTROL that only writes "0xD0" into a COMMENT leaves it
// green (the #762 comment-as-code trap, checked rather than assumed).
//
// ⚠️ `SourceText.codeOnly` is PROPHYLACTIC for claim 6, MEASURED over {3 assertions × 2 trees}:
// **0 of 6** verdicts flip raw-vs-stripped today. It stops being prophylactic the moment anyone
// writes the obvious explanatory comment next to that `default:` — which the CONTROL mutation
// above is exactly — so it stays, stated as insurance rather than claimed load-bearing.
//
// ⚠️ `SourceText.codeOnly` is PROPHYLACTIC for claims 1-4 too, MEASURED (#453) over
// {4 claims × 2 trees}:
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
    private static let router = "Sources/Echoelmusic/Core/SignalRouter.swift"
    private static let parse = "Sources/Echoelmusic/Audio/MIDIEventParse.swift"
    private static let input = "Sources/Echoelmusic/Audio/MIDIInput.swift"
    private static let claims = "ContentPipeline/CLAIMS.md"

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

    /// The routing screen must not offer an MPE INPUT the app cannot receive.
    ///
    /// ⛔ #766 — THE SIXTH SURFACE, AND #548 CHECKED FIVE. That slice corrected CLAUDE.md's
    /// pipeline line, the FAQ, `architecture.html`, the App Store text and
    /// `ContentPipeline/CLAIMS.md`. Every one of them is PROSE. `SignalRouter`'s source port
    /// was named "MIDI / MPE In" and is rendered by `PatchbayView`, which is reachable through
    /// the `showRouting` sheet — so the only surface a player reads WHILE PATCHING kept the
    /// claim for two months after the prose was fixed. A capability claim's surfaces are only
    /// as many as somebody enumerates.
    ///
    /// ⚠️ THE SINK KEEPS ITS NAME ON PURPOSE (#364). "MIDI / MPE Out" is TRUE: MPE out is real
    /// and switchable since #713, with two persisted toggles in this same routing surface. The
    /// asymmetry is the finding; a guard that banned "MPE" from the file would forbid the
    /// honest half and be deleted along with the law.
    ///
    /// ⚠️ IT ANCHORS ON THE SOURCE LINE, NOT ON A FILE-WIDE COUNT. `id: "midi.in"` occurs once
    /// and is the identity a rename cannot silently take with it; the display name travels
    /// beside it. A file-wide "MPE In" ban would also match the retraction comment above the
    /// line, which QUOTES the struck name — the #491 shape, red on the commit that fixes it.
    func testTheRoutingScreenOffersNoMPEInput() throws {
        let router = try source(Self.router)
        guard let line = SourceText.codeOnly(router)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first(where: { $0.contains("id: \"midi.in\"") })
        else {
            throw MPEAnchorMissing(reason: """
                No port declares `id: "midi.in"` in \(Self.router) — this scan found nothing \
                rather than nothing wrong (#454). If the port moved, re-anchor it here in the \
                same commit.
                """)
        }
        XCTAssertFalse(String(line).contains("MPE"), """
            The MIDI INPUT port is called "\(line.trimmingCharacters(in: .whitespaces))" again.

            The app cannot receive MPE: `MIDIBusPublisher` disambiguates no zones, and \
            `apply(controller:)` `break`s on `.slide`, `.airCC` and `.channelPressure` while \
            never reading `event.channel` — the three claims the tests above pin. MPE **out** \
            is real, so the sink port keeps its name; only the SOURCE must not promise it. \
            If a real MPE receiver is built, this whole file goes red together and the \
            corrected prose goes back — \(Self.prose)
            """)
    }

    // MARK: - claim 8 — the caption register does not promise voices, plural

    /// #774. `ContentPipeline/CLAIMS.md` is the list a short-form script must read before
    /// writing a caption; a wrong row there becomes a public promise. Its MIDI-INPUT row said
    /// the controller plays "die Stimmen".
    ///
    /// ⚠️ IT ANCHORS ON THE ROW, NOT ON THE FILE. The corrected row and the new §6b both QUOTE
    /// the struck wording — a file-wide ban would go red on the very commit that repairs it,
    /// the #491 shape this bundle has paid for. The row is found by its own label, which occurs
    /// once, and only that line is asked the question.
    func testTheClaimsRegisterDoesNotPromisePolyphonicMIDIInput() throws {
        let text = try rawFile(Self.claims)
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.contains("**MIDI-Eingang**") }
        guard rows.count == 1, let row = rows.first else {
            throw MPEAnchorMissing(reason: """
                Expected exactly one row labelled `**MIDI-Eingang**` in \(Self.claims); found \
                \(rows.count). This scan found nothing rather than nothing wrong (#454) — if \
                the register was restructured, re-anchor it here in the same commit.
                """)
        }
        XCTAssertFalse(String(row).contains("die Stimmen"), """
            The caption register promises "die Stimmen" (plural) for MIDI input again: \
            "\(row.trimmingCharacters(in: .whitespaces))".

            Measured, and claim 3 above pins it: `BioReactiveSynthVoice` is the only consumer \
            of `controllerEvents`, `heldByController` is a single `Bool`, and `playNote` sets \
            one `synth.frequency`. If the performer path really became polyphonic, this whole \
            file goes red together and \(Self.prose)
            """)
    }

    // MARK: - claim 6 — the PRESS dimension is never parsed, so no wiring could carry it

    /// #770. Claims 1-5 all live on the CONSUMER side: what the voice ignores, what the routing
    /// screen promises. This one is the PRODUCER side, and it is the stronger statement — MPE's
    /// Press dimension is Channel Pressure, and this receiver has no case for it in either
    /// protocol branch. That is why `MIDIBusPublisher`'s "not wired yet" wording had to go: a
    /// gap you cannot close from the file the note points at is not a wiring gap.
    ///
    /// ⚠️ IT ANCHORS ON THE EVENT TYPE, NOT ON A FILE-WIDE BAN OF THE WORD. `MIDIEventParse`'s
    /// own header legitimately discusses "a dense MPE stream" — MPE traffic really does arrive
    /// here as ordinary per-channel notes, bend and CC 74, and that sentence explains a real
    /// performance fix. Banning the token would forbid the honest half (#364) and would also
    /// match the retraction comments #770 wrote (#491). The scan asks the two questions that
    /// can only be answered by code: does the event type carry pressure, and does the log line
    /// still sell MPE input?
    func testTheInputPathParsesNoChannelPressure() throws {
        let body = try memberBody("public enum MIDIInEvent", in: Self.parse)
        XCTAssertFalse(body.contains("channelPressure") || body.contains("pressure"), """
            `MIDIInEvent` now carries a pressure case. If Channel Pressure (0xD0 / 0xD) is \
            parsed, MPE's Press dimension can finally arrive and every claim in this file is \
            due for review together — starting with `MIDIBusPublisher`'s header, `MIDIInput`'s \
            class doc, the routing screen's source port, and \(Self.prose)
            """)

        // The other half: the parser must still DROP it. A type without the case but a switch
        // that maps 0xD0 onto, say, `.cc` would be worse than either — it would deliver the
        // byte under a wrong name. Both protocol branches end in `default: return nil`.
        let decode = try memberBody("public static func event(word0: UInt32, word1: UInt32?)",
                                    in: Self.parse)
        XCTAssertFalse(decode.contains("0xD0") || decode.contains("case 0xD:"), """
            `MIDIEventParse` now has a Channel Pressure case. See the message above — the \
            producer half of the MPE claim has changed and the prose must move with it.
            """)
    }

    /// The `os_log` line the seventh surface was found in. Anchored on the message prefix rather
    /// than on the whole literal, because the surrounding text is exactly what a future cycle may
    /// legitimately reword (#655: a guard pinned to a full literal went red for five commits when
    /// a helper took ownership of the prefix).
    func testTheInputLogLineDoesNotAnnounceMPE() throws {
        let code = try source(Self.input)
        guard let line = code
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first(where: { $0.contains("\"MIDI: Input ready") })
        else {
            throw MPEAnchorMissing(reason: """
                No "MIDI: Input ready" log line in \(Self.input) — this scan found nothing \
                rather than nothing wrong (#454). If the line moved or was renamed, re-anchor \
                it here in the same commit.
                """)
        }
        XCTAssertFalse(String(line).contains("MPE"), """
            The MIDI input readiness log announces MPE again: \
            "\(line.trimmingCharacters(in: .whitespaces))".

            A developer reading Console during device triage is a surface like any other, and \
            this was the seventh one for this single claim. If a real MPE receiver was built, \
            the line is finally true — and then \(Self.prose)
            """)
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

    /// A file read WITHOUT the Swift comment stripper. `CLAIMS.md` is Markdown: `codeOnly`
    /// would treat a `//` inside a URL as a line comment and a `/*` in prose as a block, which
    /// is the shape `SourceText`'s own header warns about. A SKIP without a checkout, a FAILURE
    /// when a named file moved (#454).
    private func rawFile(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw MPEAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
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
