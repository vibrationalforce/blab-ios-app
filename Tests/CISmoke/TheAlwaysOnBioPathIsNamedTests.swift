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

// ─────────────────────────────────────────────────────────────────────────────────────────
// #542 — A SECOND SURFACE, AND WHAT THAT DID TO THIS FILE.
//
// The sentence moved from `BioModLiveView` to `AlwaysOnBioChannel`, beside the four cases it
// names, because the Bio panel needed it too: that panel promised "your body then drives the
// sound" and named nothing, while the answer sat two chips away behind Effects › All
// parameters › scroll. Every channel assertion now runs over BOTH sentences — asserting only
// the FX one would leave the newer surface free to drift into a different channel list, which
// is the exact defect #496 had to repair on the older one.
//
// ⚠️ HONEST GRADING of the #542 delta against its parent — TRANSCRIBED, not assumed. Of the ten
// scans this file now performs:
//   · ZERO REGRESSIONS. Nothing was red on the parent for the reason its name gives.
//   · ONE FINDING, reported SEVEN times (#486): neither `alwaysOnSentence` nor
//     `bioPanelSentence` exists there, so the two existence checks, the four-channel check, the
//     pinned-channel check, the mount check and both pointer checks fail together off a single
//     absence. Booking those as seven regressions would be the flattering direction of #433.
//   · THREE are COUNTERWEIGHTS, green on both trees: the FX footer is still mounted, the
//     "All parameters" door still exists, and the empty state still does not deny the always-on
//     path.
//
// ⚠️ `SourceText.codeOnly` REMAINS LOAD-BEARING, re-measured for the new shape: **2 of 20**
// raw-vs-stripped verdicts flip, both on `testTheEmptyStateNoLongerDeniesTheAlwaysOnPath` and on
// BOTH trees — the retraction block quotes the removed sentence verbatim, so without the
// stripper that assertion is red on correct code. Same #486/#491 collision as before.
// ─────────────────────────────────────────────────────────────────────────────────────────

import XCTest
@testable import Echoelmusic

final class TheAlwaysOnBioPathIsNamedTests: XCTestCase {

    private static let fxView = "Sources/Echoelmusic/Studio/EchoelFXView.swift"
    private static let poly = "Sources/Echoelmusic/Tools/PolySynthVoice.swift"
    private static let bioVoice = "Sources/Echoelmusic/Tools/BioReactiveSynthVoice.swift"
    private static let app = "Sources/Echoelmusic/EchoelmusicApp.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    /// Where the sentence lives since #542 — beside the four cases it names.
    private static let channels = "Sources/Echoelmusic/Studio/AlwaysOnBioChannel.swift"

    /// The four channels the note is allowed to name, in the words it uses.
    private static let namedChannels = ["coherence", "HRV", "heart rate", "breath phase"]

    /// The three the note must NOT name, in every spelling a well-meaning edit would reach for.
    /// Deliberately includes "coherence trend" even though "coherence" alone is legal — the
    /// assertion is on the two-word phrase, so the legal single word cannot trip it.
    private static let forbiddenChannels = ["breath depth", "LF/HF", "LF-HF", "coherence trend"]

    // MARK: - the copy (the regressions)

    func testTheAlwaysOnNoteExists() throws {
        XCTAssertFalse(try alwaysOnNote().isEmpty, "the always-on note must not be empty")
        XCTAssertFalse(try bioPanelNote().isEmpty, """
            the Bio-panel sentence is missing or empty. Without it that panel promises "your \
            body then drives the sound" and names nothing — the state #542 ended.
            """)
    }

    /// Both sentences name exactly the four channels a producer actually drives.
    ///
    /// ⭐ BOTH, since #542. Two surfaces say this now — the FX footer and the Bio panel — and
    /// the whole reason they share a home is that a channel list can drift. Asserting only the
    /// FX one would leave the second free to go stale in exactly the way #496 had to fix.
    func testTheNoteNamesTheFourDrivenChannels() throws {
        for (label, note) in [("FX footer", try alwaysOnNote()),
                              ("Bio panel", try bioPanelNote())] {
            for channel in Self.namedChannels {
                XCTAssertTrue(note.contains(channel),
                              "the \(label) sentence must name \(channel) — it is derived from "
                              + "the frame at both producers and is one of the four things the "
                              + "body really moves without any FX route")
            }
        }
    }

    /// THE COUNTERWEIGHT THAT MATTERS. CLAUDE.md's DDSP table lists seven mappings; a later
    /// "completeness" edit that copies all seven into this sentence would claim three channels
    /// nothing measures. That is the #439 over-claim, on the product's central surface.
    func testTheNoteDoesNotClaimThePinnedChannels() throws {
        for (label, note) in [("FX footer", try alwaysOnNote()),
                              ("Bio panel", try bioPanelNote())] {
            for channel in Self.forbiddenChannels {
                XCTAssertFalse(note.contains(channel),
                               "the \(label) sentence names \(channel), which NO producer drives "
                               + "— both `…BioParams(` sites pin it to a neutral literal. If you "
                               + "gave it a real producer, update this list and BOTH sentences "
                               + "together.")
            }
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

    /// The #542 half: the same rule applied to the surface where a player actually asks the
    /// question. A constant nobody renders is prose, and this one exists BECAUSE the Bio panel
    /// made a promise it did not keep.
    func testTheBioPanelRendersItsSentence() throws {
        let body = try declarationBody(of: "private var bioPanel: some View", in: Self.studio)
        XCTAssertTrue(body.contains("Text(AlwaysOnBioChannel.bioPanelSentence)"), """
            `bioPanel` no longer renders the always-on sentence. It still tells the player \
            "your body then drives the sound" one line above; without this it names nothing, \
            and the only place that does is two chips away behind Effects › All parameters.
            """)
    }

    /// ⚠️ THE COUNTERWEIGHT FOR THE *SECOND* SURFACE, and it is the one that makes the split
    /// honest rather than convenient. The Bio panel has no list of routes above it, so its
    /// sentence must not say "these routes" — and it must point somewhere real. Both halves are
    /// pinned, because "open Effects › All parameters" is a claim about a door that exists.
    func testTheBioPanelSentencePointsSomewhereReal() throws {
        let note = try bioPanelNote()
        XCTAssertFalse(note.contains("these routes"), """
            the Bio-panel sentence says "these routes", but nothing above it lists any — that \
            deixis belongs to the FX footer. This is why the two are separate strings.
            """)
        XCTAssertTrue(note.contains("All parameters"), """
            the Bio-panel sentence no longer names where the live readout is. The whole point of \
            #542 is that the answer existed and was unreachable from the question.
            """)
        let studioSource = try source(Self.studio)
        XCTAssertTrue(studioSource.contains("Text(\"All parameters\")"), """
            the sentence sends the player to "All parameters" and no control by that name is \
            rendered any more. Either restore the label or rewrite the sentence in the same \
            commit — a pointer to a door that is gone is worse than no pointer (#472).
            """)
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
    /// ⛔ THIS READ `BioModLiveView`'s OWN LITERAL UNTIL #542, and its failure message asked the
    /// next session to "re-anchor this scan and say why one definition became two". What
    /// happened is the opposite and better: the sentence got a SECOND surface (the Bio panel,
    /// which promised "your body then drives the sound" and named nothing), so it moved to
    /// `AlwaysOnBioChannel` — beside the four cases it names — and `BioModLiveView.alwaysOnNote`
    /// became a forwarder. Left as a retraction rather than silently re-pointed: a guard whose
    /// anchor moves without a note reads later as if the CLAIM had been rewritten.
    ///
    /// ⚠️ AND THE OLD FORM WOULD HAVE GONE RED ON CORRECT CODE — it extracted everything between
    /// `static let alwaysOnNote` and `var body`, which is now `= AlwaysOnBioChannel
    /// .alwaysOnSentence` and contains none of the four channel names. That is the #364 failure
    /// mode (a guard forbidding legitimate work), caught by grepping `Tests/CISmoke` for the
    /// surface before touching it (#456), not by CI.
    private func alwaysOnNote() throws -> String {
        try literal(named: "alwaysOnSentence", in: Self.channels)
    }

    /// The Bio panel's half of the same claim. Two strings, ONE decision: both name the four
    /// cases of `AlwaysOnBioChannel`, and every channel assertion in this file runs over both,
    /// so neither surface can drift into a different channel list.
    private func bioPanelNote() throws -> String {
        try literal(named: "bioPanelSentence", in: Self.channels)
    }

    /// The concatenated `"…"` pieces of a multi-line `public static let`, from its declaration
    /// to the first line that is neither the declaration nor a continuation.
    ///
    /// ⚠️ HONEST LIMIT: `SourceText.codeOnly` blanks comments while preserving line count, so a
    /// doc block cannot be swept in — but a blank line inserted mid-constant would truncate the
    /// value. That direction is safe by construction: a short read makes the positive channel
    /// assertions fail, never makes the negative ones pass.
    private func literal(named: String, in relativePath: String) throws -> String {
        let text = try source(relativePath)
        let anchor = "static let \(named)"
        guard text.components(separatedBy: anchor).count - 1 == 1 else {
            throw BioNoteAnchorMissing(reason: """
                `\(anchor)` does not occur exactly once in \(relativePath). It is the single \
                definition of the always-on claim; re-anchor this scan and say why.
                """)
        }
        var out = ""
        var started = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !started {
                if line.contains(anchor) { started = true } else { continue }
            } else if !(trimmed.hasPrefix("\"") || trimmed.hasPrefix("+")) {
                break
            }
            var inside = false
            var piece = ""
            for c in line {
                if c == "\"" { inside.toggle(); continue }
                if inside { piece.append(c) }
            }
            out += piece
        }
        return out
    }
}
