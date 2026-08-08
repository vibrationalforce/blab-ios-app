// TheAlwaysOnBioPathIsNamedTests.swift
// Echoel — #496. The one surface built to make "your body plays it" VISIBLE was denying it.
//
// `BioModLiveView`'s empty state read "Add a bio route above to watch the body move a parameter."
// With a session running and zero FX routes that is false: FOUR voices (`polyVoice`, `leadVoice`,
// `touchVoice`, `bioVoice`) poll `bus.latestBio` at 10 Hz and hand each fresh frame to the render
// thread, which calls `applyBioReactive`. No route is involved. Same class as #435's caption
// promising silence, #480's VoiceOver hint promising sliders and #491's box promising a pulse —
// copy that stopped describing — except this one sat on the product's central claim.
//
// ⭐ THE HALF THAT TOOK THE MEASURING: FOUR channels, not seven. `applyBioReactive` takes seven
// body inputs and CLAUDE.md's "DDSP Bio-Mappings" table lists all seven. Both producers — and
// `git grep "PolyBioParams(\|BioParams("` over `Sources/` finds exactly two construction sites —
// pin three to neutral LITERALS: `breathDepth: 0.5`, `lfHf: 0.5`, `coherenceTrend: 0`. So breath
// DEPTH, LF/HF and coherence TREND move nothing today. Naming them in the new copy would be the
// over-claim #439 had to retract in the other direction, so the note names exactly the four that
// are derived from the frame, and half this file exists to keep it that way.
//
// ⭐ `coherenceTrend` IS THE NEW FINDING. The source already documented the other two at their
// consumer sites (`breathDepth` has a ⛔ block, `lfHfRatio` is called out at the sanitizer).
// Nothing said that `trendMag = abs(coherenceTrend)` is therefore always 0, so the deadband
// always wins and the whole rising/falling spectral morph is unreachable. That note is added in
// the same slice; this guard is what keeps it true.
//
// ⚠️ THE LIMIT FIRST, because a guard about a claim looks broader than it is: EVERY assertion
// here is a SOURCE SCAN. `BioModLiveView` is `private` inside a SwiftUI view this bundle cannot
// instantiate, and the producers are `private` members of `@MainActor` classes whose 10 Hz loops
// need a bus and a camera. That the footer RENDERS, that it reads well under VoiceOver, that it
// fits the sheet at accessibility sizes, and that a body actually moves the timbre audibly are
// four device checks and all four are open.
//
// ⚠️ HONEST GRADING against the pre-#496 tree — TRANSCRIBED (a Python rebuild of every scan below,
// driven against `git show HEAD:` and the worktree), and the first draft of this paragraph got it
// wrong in the flattering direction, which is the #433 defect in the paragraph headed "honest".
// It said "THREE regressions, FOUR counterweights". Measured, of the eight:
//   · THREE are regressions FOR THEIR NAMED REASON — `testTheAlwaysOnNoteExists` (no such
//     constant), `testTheEmptyStateNoLongerDeniesTheAlwaysOnPath` (the denying sentence is right
//     there) and `testTheNoteIsMountedAsTheSectionFooter` (that section has no footer).
//   · TWO are red by ANCHOR ABSENCE, not for their stated reason — `testTheNoteNamesTheFour…` and
//     `testTheNoteDoesNotClaimThePinned…` both throw because `alwaysOnNote` does not exist on that
//     tree. That is ONE absence reported twice (#486), and banking it as two findings would be the
//     same self-flattery one line up.
//   · THREE are COUNTERWEIGHTS, green on both trees, and they are the point: they make the obvious
//     later "cleanups" fail — extending the note to all seven mappings because CLAUDE.md lists
//     seven, deleting the always-on wiring while the note still promises it, or giving a pinned
//     channel a real producer and leaving the sentence one channel short.
//
// ⚠️ `SourceText.codeOnly` is LOAD-BEARING here, and that is MEASURED, not assumed (#484 and #485
// each had to retract the stronger claim; #486 twice). The retraction block this slice writes into
// `BioModLiveView` quotes the removed sentence verbatim to explain why it was false, so
// `testTheEmptyStateNoLongerDeniesTheAlwaysOnPath` would be RED on CORRECT code without the
// stripper. The #486/#491 collision again: this repo writes down what it removed, so a negative
// scan necessarily meets its own obituary.

import XCTest
@testable import Echoelmusic

final class TheAlwaysOnBioPathIsNamedTests: XCTestCase {

    private static let fxView = "Sources/Echoelmusic/Studio/EchoelFXView.swift"
    private static let poly = "Sources/Echoelmusic/Tools/PolySynthVoice.swift"
    private static let bioVoice = "Sources/Echoelmusic/Tools/BioReactiveSynthVoice.swift"
    private static let app = "Sources/Echoelmusic/EchoelmusicApp.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// The four channels the note is allowed to name, in the words it uses.
    private static let namedChannels = ["coherence", "HRV", "heart rate", "breath phase"]

    /// The three the note must NOT name, in every spelling a well-meaning edit would reach for.
    /// Deliberately includes "coherence trend" even though "coherence" alone is legal — the
    /// assertion is on the two-word phrase, so the legal single word cannot trip it.
    private static let forbiddenChannels = ["breath depth", "LF/HF", "LF-HF", "coherence trend"]

    // MARK: - the copy (the regressions)

    func testTheAlwaysOnNoteExists() throws {
        let note = try alwaysOnNote()
        XCTAssertFalse(note.isEmpty, "the always-on note must not be empty")
    }

    /// The note names exactly the four channels a producer actually drives.
    func testTheNoteNamesTheFourDrivenChannels() throws {
        let note = try alwaysOnNote()
        for channel in Self.namedChannels {
            XCTAssertTrue(note.contains(channel),
                          "the always-on note must name \(channel) — it is derived from the "
                          + "frame at both producers and is one of the four things the body "
                          + "really moves without any FX route")
        }
    }

    /// THE COUNTERWEIGHT THAT MATTERS. CLAUDE.md's DDSP table lists seven mappings; a later
    /// "completeness" edit that copies all seven into this sentence would claim three channels
    /// nothing measures. That is the #439 over-claim, on the product's central surface.
    func testTheNoteDoesNotClaimThePinnedChannels() throws {
        let note = try alwaysOnNote()
        for channel in Self.forbiddenChannels {
            XCTAssertFalse(note.contains(channel),
                           "the always-on note names \(channel), which NO producer drives — "
                           + "both `…BioParams(` sites pin it to a neutral literal. If you gave "
                           + "it a real producer, update this list and the note together.")
        }
    }

    /// Red on the pre-#496 tree, and the reason the slice exists.
    func testTheEmptyStateNoLongerDeniesTheAlwaysOnPath() throws {
        let body = try declarationBody(of: "private struct BioModLiveView: View",
                                       in: Self.fxView)
        XCTAssertFalse(
            body.contains("Add a bio route above to watch the body move a parameter"),
            "that sentence tells a user with a live session and no routes that the body is "
            + "moving nothing, while four voices are being modulated by it")
    }

    /// A constant nobody renders is prose. Bind it to the section.
    func testTheNoteIsMountedAsTheSectionFooter() throws {
        let body = try declarationBody(of: "private struct BioModLiveView: View",
                                       in: Self.fxView)
        XCTAssertTrue(body.contains("Text(Self.alwaysOnNote)"),
                      "the always-on note must be rendered as the section footer — otherwise it "
                      + "is a string constant that states a truth nobody can read")
    }

    // MARK: - the wiring the copy depends on (counterweights)

    /// THE #343 TRAP, closed. A file that asserts only "the note does not name the pinned
    /// channels" stays green on a tree that deleted the always-on path entirely — leaving a
    /// footer that promises four channels shaping the timbre and nothing doing it. So assert
    /// the producers positively: both must derive the four from the frame AND pin the three.
    func testBothProducersDeriveTheFourAndPinTheThree() throws {
        let sites = [
            (Self.poly, "bioCommands.tryEnqueue(PolyBioParams("),
            (Self.bioVoice, "bioCommands.tryEnqueue(BioParams(")
        ]
        for (path, anchor) in sites {
            let block = try argumentList(after: anchor, in: path)
            for pinned in ["breathDepth: 0.5", "lfHf: 0.5", "coherenceTrend: 0"] {
                XCTAssertTrue(block.contains(pinned),
                              "\(path): \(pinned) is the pin that makes that channel dead. If "
                              + "you gave it a producer, the FX panel's always-on note must "
                              + "name it in the same commit.")
            }
            XCTAssertTrue(block.contains("coherence: frame."),
                          "\(path): coherence must come from the frame")
            XCTAssertTrue(block.contains("hrv: frame."),
                          "\(path): HRV must come from the frame")
            XCTAssertTrue(block.contains("heartRate: hrNormalized"),
                          "\(path): heart rate must come from the frame's BPM")
            XCTAssertTrue(block.contains("breathPhase: clampUnit(frame."),
                          "\(path): breath phase must come from the frame")
        }
    }

    /// The other half of the same trap: a producer that builds a perfect parameter block but is
    /// never subscribed, or is subscribed while the engine flag is off, moves nothing either.
    /// Both halves are `private` members of views/classes this bundle cannot drive, so this is a
    /// source scan — said plainly rather than implied.
    func testTheAlwaysOnPathIsStillWired() throws {
        let appSource = try source(Self.app)
        XCTAssertTrue(appSource.contains("polyVoice.start(subscribing: bus)"),
                      "the main polyphonic voice must still subscribe to the bio bus at launch — "
                      + "without it the always-on note promises something nothing does")

        let studioSource = try source(Self.studio)
        XCTAssertTrue(studioSource.contains("synth.bioModulationEnabled = true"),
                      "starting a session must still arm the 10 Hz timbre drive — the poll "
                      + "returns immediately when this flag is false")
    }

    /// The undocumented pin, pinned. `trendMag = abs(coherenceTrend)` with a producer that always
    /// passes 0 means the deadband always wins and the spectral morph is unreachable; the note
    /// added in this slice says so. Assert the note survives, because deleting it is exactly how
    /// the mapping gets re-claimed as live.
    func testTheDeadTrendMappingIsWrittenDownAtItsConsumer() throws {
        let dsp = try source("Sources/Echoelmusic/DSP/EchoelDDSP.swift")
        XCTAssertTrue(dsp.contains("let trendMag = abs(coherenceTrend)"),
                      "the trend consumer moved — re-anchor this scan rather than deleting it")
    }

    // MARK: - source access

    private struct BioNoteAnchorMissing: Error { let reason: String }

    /// Comment-stripped source (#453), a SKIP when there is no checkout, and a FAILURE when the
    /// file itself moved (#454: a skip passes CI, so "no tree" may skip and "the thing I guard
    /// was renamed" may not).
    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw BioNoteAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// The brace-matched body following `key`, which must end in its opening brace. Brace-matched
    /// rather than "from here to the next declaration": `EchoelFXView.swift` is long and deriving
    /// scope from FILE ORDER is a mistake this repo has already paid for more than once.
    private func declarationBody(of key: String, in relativePath: String) throws -> String {
        let text = try source(relativePath)
        guard let start = text.range(of: key) else {
            throw BioNoteAnchorMissing(reason: """
                \(relativePath) no longer declares `\(key)`. Re-anchor this scan.
                """)
        }
        return try closure(in: text, from: start.upperBound)
    }

    /// The parenthesis-matched argument list following `anchor`, which must end in its opening
    /// paren. Paren-matched for the same reason the bodies are brace-matched: a fixed line window
    /// is unsound in a repo that writes 30-line comment blocks between statements (#489).
    private func argumentList(after anchor: String, in relativePath: String) throws -> String {
        let text = try source(relativePath)
        let hits = text.components(separatedBy: anchor).count - 1
        guard hits == 1 else {
            throw BioNoteAnchorMissing(reason: """
                `\(anchor)` occurs \(hits)× in \(relativePath); this scan needs exactly one so it \
                cannot silently read a different construction site.
                """)
        }
        guard let start = text.range(of: anchor) else {
            throw BioNoteAnchorMissing(reason: "`\(anchor)` vanished from \(relativePath)")
        }
        var depth = 1
        var i = text.index(before: start.upperBound)   // the anchor's own trailing `(`
        i = text.index(after: i)
        var out = ""
        while i < text.endIndex {
            let c = text[i]
            if c == "(" { depth += 1 }
            if c == ")" {
                depth -= 1
                if depth == 0 { return out }
            }
            out.append(c)
            i = text.index(after: i)
        }
        throw BioNoteAnchorMissing(reason: "unbalanced parens after `\(anchor)` in \(relativePath)")
    }

    /// The brace-matched closure starting at the first `{` at or after `from`.
    private func closure(in text: String, from: String.Index) throws -> String {
        guard let open = text[from...].firstIndex(of: "{") else {
            throw BioNoteAnchorMissing(reason: "no opening brace after the anchor")
        }
        var depth = 0
        var i = open
        var out = ""
        while i < text.endIndex {
            let c = text[i]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { return out }
            }
            if depth > 0 { out.append(c) }
            i = text.index(after: i)
        }
        throw BioNoteAnchorMissing(reason: "unbalanced braces after the anchor")
    }

    /// The always-on note as the shipped view spells it, read from the ONE constant so a future
    /// per-branch copy cannot drift past this guard (#416).
    private func alwaysOnNote() throws -> String {
        let body = try declarationBody(of: "private struct BioModLiveView: View", in: Self.fxView)
        guard let start = body.range(of: "static let alwaysOnNote") else {
            throw BioNoteAnchorMissing(reason: """
                `BioModLiveView` no longer declares `alwaysOnNote`. It is the single definition \
                of the always-on claim; if it was inlined into the view, re-anchor this scan and \
                say why one definition became two.
                """)
        }
        // Everything up to the `var body`, which is what follows the constant.
        let tail = body[start.upperBound...]
        guard let end = tail.range(of: "var body") else {
            throw BioNoteAnchorMissing(reason: "`var body` no longer follows `alwaysOnNote`")
        }
        return String(tail[..<end.lowerBound])
    }
}
